#==============================================================================
# build_fundamental_merged_v2.R — 재무 v2 → 갈아 끼울 병합 표(.cache/fundamental_merged_v2.parquet)
# (2026-11-09 · 도훈 결정 '퀀티 메인 · DART 정정 검사 · 실제 공시일' ·
#  04_Research/01_reports/quantiwise_data_expansion_20261106/fundamentals_v2/README.md §8 2단계)
#
# 팩터 모듈이 fundamental_merged.parquet 에서 읽는 구성을 그대로 따르고 원천만 바꾼다.
#   <=2014  분기 단독 원계정 41개(기존 이름) + NetIncome(보고된 당기순이익) + 파생 TotalDebt · NOPAT
#   2015~   회계연도 말 연간 행: 원계정(흐름 = 네 분기 합 · 잔액 = 연말 값) + 파생 140개
#           (fundamental_derive_items.R — 지금 파이프라인과 같은 공식 하나)
# 값: 퀀티 v2(.cache/fundamental_v2/fund_v2_quarterly.parquet).
#   정정 의심 기업-연도(Check = restated)는 그해 퀀티 기록이 정정으로 덮여 있으므로 DART 당시 보고서 기록(원계정 +
#   파생, fundamental_dart.parquet)을 DART 접수 다음 거래일부터 쓴다 = 지금 병합 표가 DART 연도를 쓰는 방식(날짜만 실제).
#   DART 에 없는 퀀티 전용 항목은 v2 가 미룬 날짜(다음 회계연도 사업보고서 뒤)로 둔다.
# 날짜: Factor_Date = 쓸 수 있는 첫날(v2 = max(퀀티 공시일, DART 접수일) 다음 거래일).
# 열: Ticker · Period · Period_Date · Factor_Date · Item · Value · Source · Freq(Q 분기 단독 | A 연간)
#   Source: QW_V2 · QW_V2_UNVERIFIED(2015~ DART 대조 없음) · QW_V2_DELAYED · DART_RESTATED · QW_V2_derived
#   ★전환 때: Source == "DART" 로 연간 행을 가르는 소비자 2곳(alpha_search/factor_engine_fq081_dupont_indrel.R:51 ·
#   fq081_dupont_panel.R:57)은 Freq == "A" 로 바꿔야 한다.
# 쓰지 않는 것: fundamental_merged.parquet · 팩터 DB(전환 = DART 보충 뒤 팩터 DB 재빌드와 함께 · 도훈 확인).
# 실행: Rscript build_fundamental_merged_v2.R [--root R] [--v2-dir D] [--qw-dir D] [--dart F] [--registry F] [--out F]
# 종료: 0 성공 · 1 오류(중복 키 등) · 3 입력 없음
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
args <- commandArgs(trailingOnly = TRUE)
argv <- function(flag, default) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
ROOT <- argv("--root", Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")))
V2D  <- argv("--v2-dir", file.path(ROOT, ".cache", "fundamental_v2"))
QWD  <- argv("--qw-dir", file.path(ROOT, ".cache", "qw_fund_v2"))
DART <- argv("--dart", file.path(ROOT, ".cache", "fundamental_dart.parquet"))
REG  <- argv("--registry", file.path(ROOT, "02_Infrastructure", "data", "qw_updatefile_registry.json"))
OUT  <- argv("--out", file.path(ROOT, ".cache", "fundamental_merged_v2.parquet"))
.self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
source(file.path(dirname(.self), "fundamental_derive_items.R"))
inputs <- c(file.path(V2D, "fund_v2_quarterly.parquet"), file.path(V2D, "fund_v2_annual_check.parquet"),
            file.path(QWD, "fiscal_month.parquet"), DART, REG)
for (p in inputs) if (!file.exists(p)) { cat("[merged-v2] 입력 없음:", p, "\n"); quit(status = 3) }
t0 <- Sys.time()

# 기존 이름 = v2 항목(11-09 대조 · <=2014 기존 XLSX 와 0.5% 일치율 1.000, ISSD 만 0.899 = 수정주식수 소급)
MAP <- c(AccountsPay = "AccountsPay", AccountsRecv = "AccountsRecv", COGS = "COGS", CapitalStock = "CapitalStock",
         CashAndEquiv = "CashAndEquiv", CurrentAssets = "CurrentAssets", CurrentLiab = "CurrentLiab",
         DepAmort = "DepAmortSGA", Dividends = "DividendsPaid", FCF1 = "FCF1", FCF2 = "FCF2", FinanceCF = "FinanceCF",
         GrossProfit = "GrossProfit", ISSD = "SharesCommonAdj", IntangibleAssets = "Intangibles",
         InterestExp = "InterestExp", InterestIncome = "InterestIncome", Inventory = "Inventory", InvestCF = "InvestCF",
         LongTermBorr = "LongTermBorr", LongTermPay = "LongTermPay", LongTermRecv = "LongTermRecv",
         NetInterestExp = "NetInterestExp", NonCurrentAssets = "NonCurrentAssets", NonCurrentLiab = "NonCurrentLiab",
         OperatingCF = "OperatingCF", OperatingProfit = "OperatingProfit", OrdRandD = "ExpOrdRandD",
         PretaxIncome = "PretaxIncome", RandD = "RandD",
         RetainedEarnings = "RetainedEarnings",   # 기존 XLSX '이익잉여금' 시트는 자본잉여금(M115500)이었다 — 바로잡음
         Revenue = "Revenue", SBB = "BuybackShares", SGAExpense = "SGAExpense",
         ShortTermBorr = "CurrentBorr",           # 기존 XLSX = 유동성사채(오표기) · DART = 단기차입금만 · v2 = 단기차입금 + 유동성장기차입금(+ IFRS 유동 리스부채)
         TangibleAssets = "PPE", TaxExpense = "TaxExpense", TotalAssets = "TotalAssets", TotalEquity = "TotalEquity",
         TotalLiab = "TotalLiab", TotalNetInterestExp = "TotalNetInterestExp", NetIncome = "NetIncome")
reg <- fromJSON(REG, simplifyVector = TRUE)$fundamentals_v2$items
kind <- setNames(reg$kind, reg$sheet)
FLOW_V2 <- c(names(kind)[kind == "flow"], "BuybackShares")   # 기중 취득 자기주식수 = 기간 합

q <- as.data.table(read_parquet(file.path(V2D, "fund_v2_quarterly.parquet"),
                                col_select = c("Ticker", "Period", "Period_Date", "Item", "Value", "Factor_Date", "Check")))
q <- q[Item %in% MAP]
q[, Old := names(MAP)[match(Item, MAP)]]
q[, P := as.integer(Period)]
fm <- as.data.table(read_parquet(file.path(QWD, "fiscal_month.parquet")))[, .(Ticker, FM = as.integer(FiscalMonth))]
q <- merge(q, fm, by = "Ticker", all.x = TRUE)
q[is.na(FM), FM := 12L]
q[, FY := fifelse(P %% 100L <= FM, P %/% 100L, P %/% 100L + 1L)]
q[, FYE := FY * 100L + FM]
cat(sprintf("[merged-v2] v2 행 %s (항목 %d)\n", format(nrow(q), big.mark = ","), uniqueN(q$Old)))

# ---- A. <=2014 분기 단독 ------------------------------------------------------------------------
A <- q[P %/% 100L <= 2014L, .(Ticker, Period, Period_Date, Factor_Date, Item = Old, Value, Source = "QW_V2", Freq = "Q")]
dA <- derive_fundamental_items(A[, .(Ticker, Period, Period_Date, Factor_Date, Item, Value)])
dA <- dA[Item %in% c("TotalDebt", "NOPAT"), .(Ticker, Period, Period_Date, Factor_Date, Item, Value,
                                               Source = "QW_V2_derived", Freq = "Q")]

# ---- B. 2015~ 회계연도 말 연간(2014 = 성장률 씨앗) -----------------------------------------------------
qa <- q[FY >= 2014L]
key <- unique(qa[P == FYE, .(Ticker, FY, Period_Date, Factor_Date, Check)])
if (anyDuplicated(key[, .(Ticker, FY)])) { cat("[merged-v2] 오류: 연말 키가 겹친다\n"); quit(status = 1) }
fl <- qa[Item %in% FLOW_V2, .(Value = sum(Value), n = .N), by = .(Ticker, FY, FYE, Old)][n == 4L]
st <- qa[!(Item %in% FLOW_V2) & P == FYE, .(Ticker, FY, FYE, Old, Value)]
an <- merge(rbind(fl[, .(Ticker, FY, FYE, Old, Value)], st), key, by = c("Ticker", "FY"))
an[, Period := as.character(FYE)]
# 침묵 탈락 방지: 연말 분기 행이 없는 기업-연도(결산월이 분기 말이 아님 · 연말 자료 없음)는 연간 행을 못 만든다
#   진행 중인 회계연도(연말이 자료 마지막 분기 뒤)는 정상이라 따로 센다
#   센다 = 그 회계연도에 자산총계가 한 분기라도 있는 기업-연도(주식 수 · 자사주만 띄엄띄엄 있는 종목은 빼고)
lostk <- unique(qa[FY >= 2015L & Old == "TotalAssets", .(Ticker, FY, FYE)])[!key, on = .(Ticker, FY)]
lostk[, open := FYE > max(q$P)]
if (nrow(lostk[open == FALSE]) > 0L) {
  cat(sprintf("[merged-v2] ⚠ 연말 분기 행이 없어 연간 행을 못 만든 기업-연도 %d개(결산월이 분기 말 아님 · 상장 폐지 · 연말 자료 없음) · 연도별 %s\n",
              nrow(lostk[open == FALSE]),
              paste(lostk[open == FALSE, .N, by = FY][order(FY), paste0(FY, ":", N)], collapse = " ")))
}
cat(sprintf("[merged-v2] 진행 중인 회계연도(연말 미도래) %d 기업-연도 — 연간 행 없음(정상)\n", nrow(lostk[open == TRUE])))
RS <- unique(key[Check == "restated", .(Ticker, FY)])
dB <- derive_fundamental_items(an[, .(Ticker, Period, Period_Date, Factor_Date, Item = Old, Value)])
dB[, FY := as.integer(Period) %/% 100L]
dB <- dB[FY >= 2015L & !(Item %in% names(MAP))][!RS, on = .(Ticker, FY)]
dB <- dB[, .(Ticker, Period, Period_Date, Factor_Date, Item, Value, Source = "QW_V2_derived", Freq = "A")]
B <- an[FY >= 2015L][!RS, on = .(Ticker, FY)][, .(Ticker, Period, Period_Date, Factor_Date, Item = Old, Value,
            Source = fifelse(Check == "agree", "QW_V2", "QW_V2_UNVERIFIED"), Freq = "A")]

# ---- C. 정정 의심 기업-연도 = DART 당시 보고서 기록 + 퀀티 전용 항목(미룸) --------------------------------------
ck <- as.data.table(read_parquet(file.path(V2D, "fund_v2_annual_check.parquet")))
dfd <- unique(ck[!is.na(DART_Factor_Date), .(Ticker, FY, DART_Factor_Date)])
if (anyDuplicated(dfd[, .(Ticker, FY)])) { cat("[merged-v2] 오류: DART 날짜가 기업-연도마다 하나가 아니다\n"); quit(status = 1) }
dd <- as.data.table(read_parquet(DART))
num <- setdiff(names(dd)[vapply(dd, is.numeric, logical(1))], "bsns_year")
for (col in num) if (!is.double(dd[[col]])) set(dd, j = col, value = as.double(dd[[col]]))
dl <- melt(dd, id.vars = c("Ticker", "bsns_year"), measure.vars = num, variable.name = "Item", value.name = "Value",
           variable.factor = FALSE)[!is.na(Value)]
dl <- dl[RS, on = .(Ticker, bsns_year = FY), nomatch = 0L]
dl <- merge(dl, dfd, by.x = c("Ticker", "bsns_year"), by.y = c("Ticker", "FY"))
# sprintf, not paste0: paste0(integer(0), "-12-31") returns "-12-31" (length 1) and as.Date() then fails when no
#   company-year is restated (11-09 대조군 TC)
DR <- dl[, .(Ticker, Period = sprintf("%d12", bsns_year), Period_Date = as.Date(sprintf("%d-12-31", bsns_year)),
             Factor_Date = DART_Factor_Date, Item, Value, Source = "DART_RESTATED", Freq = "A")]
covered <- unique(dl[, .(Ticker, FY = bsns_year, Old = Item)])
RQ <- an[FY >= 2015L][RS, on = .(Ticker, FY), nomatch = 0L][!covered, on = .(Ticker, FY, Old)]
RQ <- RQ[, .(Ticker, Period, Period_Date, Factor_Date, Item = Old, Value, Source = "QW_V2_DELAYED", Freq = "A")]
miss_rs <- nrow(RS) - uniqueN(dl[, .(Ticker, bsns_year)])
if (miss_rs > 0L) cat(sprintf("[merged-v2] ⚠ 정정 의심 %d 기업-연도에 DART 기록/날짜가 없다 — 퀀티 미룸 값만 남는다\n", miss_rs))

# ---- D. 합치기 · 검사 · 쓰기 --------------------------------------------------------------------------------
M <- rbindlist(list(A, dA, B, dB, DR, RQ), use.names = TRUE)
dup <- M[, .N, by = .(Ticker, Period, Item)][N > 1L]
if (nrow(dup)) { cat("[merged-v2] 오류: 중복 키", nrow(dup), "\n"); print(head(dup)); quit(status = 1) }
bad <- M[is.na(Factor_Date) | Factor_Date <= Period_Date]
if (nrow(bad)) { cat("[merged-v2] 오류: Factor_Date 가 없거나 기간 말 이전인 행", nrow(bad), "\n"); print(head(bad)); quit(status = 1) }
setorder(M, Ticker, Item, Factor_Date)
tmp <- paste0(OUT, ".tmp", Sys.getpid())
write_parquet(M, tmp, compression = "zstd", compression_level = 5L, write_statistics = FALSE)
if (file.exists(OUT)) unlink(OUT)
if (!file.rename(tmp, OUT)) { cat("[merged-v2] 오류: 이름 바꾸기 실패", tmp, "\n"); quit(status = 1) }
src <- M[, .N, by = .(Source, Freq)][order(Freq, Source)]
rep <- list(schema = "fundamental_merged_v2_report/v1", built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
            rows = nrow(M), tickers = uniqueN(M$Ticker), items = uniqueN(M$Item),
            by_source = setNames(as.list(src$N), paste(src$Freq, src$Source)),
            restated_company_years = nrow(RS), restated_without_dart = miss_rs,
            annual_company_years = uniqueN(M[Freq == "A", .(Ticker, Period)]))
writeLines(toJSON(rep, auto_unbox = TRUE, pretty = TRUE), file.path(dirname(OUT), "fundamental_merged_v2_report.json"), useBytes = TRUE)
cat(sprintf("[merged-v2] 저장 %s · 행 %s · 종목 %d · 항목 %d · %.0fs\n", OUT, format(nrow(M), big.mark = ","),
            uniqueN(M$Ticker), uniqueN(M$Item), as.numeric(difftime(Sys.time(), t0, units = "secs"))))
print(src)
