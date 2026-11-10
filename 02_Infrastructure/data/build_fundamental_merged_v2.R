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
#   연간 행 = 그 회계연도 네 분기 가운데 가장 늦은 날(흐름 = 네 분기 합) · 파생 = 그해와 직전 연도 가운데 늦은 날
#   (성장률 · 평균 · 변화량이 직전 연도 값을 쓴다). 정정 의심 연도의 DART 기록이 퀀티 미룬 값보다도 늦게 나왔으면
#   (나중 정정 · 11-09 실측 A036030 FY2019 DART 2023-09-01) 그해는 퀀티 미룬 값을 쓴다.
# ★날짜 순서 계약(11-09 · 지금 병합 표의 성질 = 겹침 0 · 역전 0 · 소비자 39곳이 기댄다): (종목, 항목) 안에서
#   Factor_Date 는 기간 순서대로 엄격히 는다. 팩터 모듈은 Factor_Date 순위로 '최신 · 직전 기간'을 고르고
#   (compute_growth.R .get_two_periods 등), 같은 날짜가 둘이면 dcast 가 값 대신 개수(length)를 넣어 그 모듈의
#   그 항목이 전 종목에서 망가진다(11-09 시범: 삼성전자 매출 성장률 3.0e14 · GR04/GR05 전 종목 같은 값).
#   ① 늦게 도착한 옛 기간(더 새 기간이 이미 더 일찍 쓰일 수 있었다) = 버린다 — 도착 때 이미 최신이 아니고,
#      남기면 최신으로 읽힌다. ② 같은 날 도착 = 새 기간을 하루씩 늦춘다. 날짜는 늦추기만 한다(미래참조 없음).
# 열: Ticker · Period · Period_Date · Factor_Date · Item · Value · Source · Origin · Freq(Q 분기 단독 | A 연간)
#   Source = 소비자 호환 역할 표지(지금 병합 표와 같은 뜻): XLSX(분기 원계정) · xlsx_derived(분기 파생) · DART(연간 원계정 + 파생)
#     — 전략 엔진 약 20곳(04_Research/strategies/DT_2002_06975 · RP_AUTO_2002_06975 등)이 이 표지로 연간 · 분기 행을 가른다.
#   Origin = 실제 출처: QW_V2 · QW_V2_UNVERIFIED(2015~ DART 대조 없음) · QW_V2_DELAYED · DART_RESTATED · QW_V2_derived
#   (fq081 소비자 2곳은 11-09 Freq == "A" 로도 가른다 — 12월 외 결산 연간 행 포함.)
# 둘째 산출(--out-xlsx): fundamental_xlsx.parquet 와 같은 꼴의 분기 단독 원계정 41개 전 기간(XF 팩터 ·
#   xlsx_factor_calculator.R 가 읽는 표) — 같은 날짜 순서 계약.
# 쓰지 않는 것: fundamental_merged.parquet · fundamental_xlsx.parquet · 팩터 DB(전환 = DART 보충 뒤 팩터 DB 재빌드와 함께).
# 실행: Rscript build_fundamental_merged_v2.R [--root R] [--v2-dir D] [--qw-dir D] [--dart F] [--registry F] [--out F]
#        [--out-xlsx F]
# 종료: 0 성공 · 1 오류(중복 키 · 날짜 순서 계약 위반 등) · 3 입력 없음
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
OUTX <- argv("--out-xlsx", file.path(ROOT, ".cache", "fundamental_xlsx_v2.parquet"))
.self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
source(file.path(dirname(.self), "fundamental_derive_items.R"))

# 날짜 순서 계약(머리말 ★): (종목, 항목) 안에서 기간 순서대로 Factor_Date 가 엄격히 늘게 만든다. 날짜는 늦추기만 한다.
#   ① 버림: 자기보다 새 기간 가운데 더 이른 날짜가 있는 행(늦게 도착한 옛 기간)
#   ② 하루씩 늦춤: d_i = max(f_i, d_{i-1} + 1) = i + cummax(f_j - j) (같은 날 도착한 새 기간)
#   묶음별 함수 호출 대신 묶음 번호 g 에 큰 수를 곱해 더하는 방식으로 묶음 안 누적 최소 · 최대를 한 번에 구한다
#   (BIG > 날짜 폭 · g · BIG 은 double 로 정확).
order_contract <- function(D) {
  setorder(D, Ticker, Item, Period_Date)
  D[, f := as.integer(Factor_Date)]
  D[, g := rleid(Ticker, Item)]
  BIG <- 1e6
  stopifnot(diff(range(D$f)) + 200 < BIG)
  sentinel <- max(D$f) + 1L
  nxt <- shift(D$f, -1L)
  nxt[is.na(nxt) | D$g != shift(D$g, -1L, fill = -1L)] <- sentinel
  y <- nxt + D$g * BIG
  D[, later_min := rev(cummin(rev(y))) - g * BIG]          # 자기보다 새 기간들의 가장 이른 날짜
  D[, late := f > later_min]
  D[, hole := !late & shift(late, 1L, fill = FALSE) & g == shift(g, 1L, fill = 0L)]
  st <- list(rows_in = nrow(D), dropped = sum(D$late), holes_created = sum(D$hole))
  if ("Source" %in% names(D))
    st$dropped_by_source <- as.list(D[late == TRUE, .N, by = Source][order(-N), setNames(N, Source)])
  D <- D[late == FALSE]
  D[, i := rowid(g)]
  D[, d := i + (cummax((f - i) + g * BIG) - g * BIG)]
  st$shifted <- sum(D$d > D$f)
  st$max_shift_days <- if (st$shifted > 0L) max(D$d - D$f) else 0L
  # 검사: 늦추기만 했고 · 묶음 안에서 엄격히 는다
  if (any(D$d < D$f)) stop("[merged-v2] 날짜 순서 계약: 앞당긴 행이 있다")
  if (any(D$g == shift(D$g, 1L, fill = 0L) & D$d <= shift(D$d, 1L, fill = 0L)))
    stop("[merged-v2] 날짜 순서 계약: (종목, 항목) 안 Factor_Date 가 엄격히 늘지 않는다")
  D[, Factor_Date := as.Date(d, origin = "1970-01-01")]
  D[, c("f", "g", "later_min", "late", "hole", "i", "d") := NULL]
  list(D = D, stats = st)
}
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
         ShortTermBorr = "CurrentBorr",           # 기존 XLSX = 유동성사채(오표기) · DART = 단기차입금만 · v2 = 단기차입금 + 유동성장기차입금(+ IFRS 유동 리스부채) + 유동 사채(11-10 · 위 DEBT_TO)
         TangibleAssets = "PPE", TaxExpense = "TaxExpense", TotalAssets = "TotalAssets", TotalEquity = "TotalEquity",
         TotalLiab = "TotalLiab", TotalNetInterestExp = "TotalNetInterestExp", NetIncome = "NetIncome")
reg <- fromJSON(REG, simplifyVector = TRUE)$fundamentals_v2$items
kind <- setNames(reg$kind, reg$sheet)
FLOW_V2 <- c(names(kind)[kind == "flow"], "BuybackShares")   # 기중 취득 자기주식수 = 기간 합

q <- as.data.table(read_parquet(file.path(V2D, "fund_v2_quarterly.parquet"),
                                col_select = c("Ticker", "Period", "Period_Date", "Item", "Value", "Factor_Date", "Check")))
# ★2026-11-10 차입금 = Compustat 정의(도훈 '팩터 DB 의 총부채(TotalDebt) 수리해 0으로 나와'):
#   ShortTermBorr ← 유동 차입금(CurrentBorr · M113300) + 유동 사채(CurrentBonds · M113400) = DLC
#   LongTermBorr  ← 장기차입금(LongTermBorr · M113700) + 사채(Bonds · M113600)         = DLTT
#   (등록부 qw_updatefile_registry.json 의 QMJ DLC · DLTT 표지와 같다). 구판은 CurrentBorr · LongTermBorr 만 써서 사채가 통째로
#   빠졌다 — 2025 연말 한국전력 TotalDebt 22.0조 vs 4항목 129.8조(FnGuide 이자발생부채 132.9조) · 현대차 42.8조 vs 175.3조.
#   두 원계정을 바로잡으면 TotalDebt 와 단기 · 장기차입금을 직접 더해 쓰는 팩터 모듈(EV · 레버리지 · 발생액 · NOA · 부채 증가율 · XF)이
#   모두 같이 고쳐진다(항목 이름 · 개수 그대로 = 소비자 계약 그대로). 전환사채 · BW · EB 는 사채 안에 들어 있다(11-10 실측: 전환사채 ≤
#   사채 1288/1295 · 셋을 더하면 4항목 합이 이자발생부채를 1,226행 넘는다 · 4항목만이면 6행) — 더하지 않는다.
#   성분이 하나라도 있으면 있는 것의 합 · 날짜 = 성분 가운데 늦은 날(합은 둘 다 안 뒤에야 안다).
DEBT_TO <- c(CurrentBorr = "CurrentBorr", CurrentBonds = "CurrentBorr", LongTermBorr = "LongTermBorr", Bonds = "LongTermBorr")
# 차입에 기대는 기존 이름(원계정 2 + 파생 9 · fundamental_derive_items.R) — 정정 의심 연도(아래 C)엔 DART 기록 대신 퀀티(미룬 날짜):
#   DART 쪽 차입 계정은 정의가 다르다(단기차입금 = '단기차입금' 이름 하나 · 유동성장기부채 · 유동 사채 없음 · v2 정정 검사도 단기차입금을
#   '정의가 달라' 뺐다 — 일치율 0.07~0.40). 실측: LG화학 FY2019~2025 DART TotalDebt = 0 · 현대차 FY2023 26.6조 vs 퀀티 124.8조.
DEBT_ITEMS <- c("ShortTermBorr", "LongTermBorr", "TotalDebt", "NetDebt", "ROIC", "LongTermDebtToEquity", "TotalDebtToAssets",
                "NetDebtToEBITDA", "NetDebtToAssets", "ShortTermDebtRatio", "BorrowingDependency")
dq <- q[Item %in% names(DEBT_TO)]
debt_n_in <- dq[, .N, by = Item]
dq[, To := DEBT_TO[Item]]
# 사채가 값을 보탠 칸 표지는 묶기 전에 단다 — 묶음 이름 Item = To 가 j 안에서 원래 Item 열을 가려 구판 any(Item %in% ...)는 늘 FALSE 였다
#   (11-10 확인 · 로그 '사채 포함 0' · 값 합에는 영향 없음)
dq[, bond_part := Item %in% c("CurrentBonds", "Bonds") & Value != 0]
debt_mixed <- dq[, .(k = uniqueN(Check), pd = uniqueN(Period_Date)), by = .(Ticker, Period, To)][k > 1L | pd > 1L, .N]
dq <- dq[, .(Period_Date = Period_Date[1L], Value = sum(Value), Factor_Date = max(Factor_Date), Check = Check[1L],
             with_bonds = any(bond_part)), by = .(Ticker, Period, Item = To)]
debt_cells_reported <- nrow(dq)
# ★2026-11-10(2) 차입 두 줄 = 기간 완비(도훈 '옛 차입 줄 섞임 — 여기서 고쳐줘'): 한 기간에 DLC · DLTT 가운데 하나만 있으면 없는 줄을
#   값 0 행으로 같은 날짜 · 같은 표지에 둔다. 왜: 소비자(팩터 모듈 · 전략 엔진)는 항목마다 Factor_Date 최신 행을 따로 고른다. 줄 하나가
#   어느 해부터 원천에서 빠지면 마지막으로 보고된 옛 값이 그 뒤 모든 달에 섞였다(2025-06 저장값 R18(두 줄 합) vs Q16(같은 기간 TotalDebt)
#   차이 > 자산 1% = 781/3,513 종목 · 002290 = 2001년 장기차입금 32억이 2025년 레버리지에). '없는 줄 = 0'은 TotalDebt 파생 · 모듈 합산 규칙
#   (한쪽만 있으면 다른 쪽 0)이 이미 쓰는 관례다 — 그 관례를 줄 단위로 내려 두 줄 합 = TotalDebt 가 기간마다 맞게 한다(아래 .check_debt_lines 단정).
#   근거(원천 fund_v2_quarterly · 재무상태표 칸 218,044 · 11-10 실측): 퀀티는 유동 두 줄(CurrentBorr · CurrentBonds)은 0 도 적지만 비유동 두 줄
#   (LongTermBorr · Bonds)은 없으면 줄을 뺀다(두 줄 칸 140,568 가운데 DLTT = 0 은 0건). DLC 만 67,602칸 = 이자발생부채(M113800) ÷ DLC 중앙 1.000 ·
#   차이 ≤ 자산 2% 86.2%(두 줄 칸 90.1%) → 없는 DLTT = 0. DLTT 만 6,255칸 = 은행 · 증권 · 보험 87%(유동 · 비유동 구분 없는 서식이라 유동 차입
#   줄 자체가 없다) → DLC = 0. 둘 다 없는 3,619칸은 채우지 않는다(TotalDebt 도 없다 = 미지).
#   날짜: 원천은 (종목, 기간) 안 항목 날짜가 하나다(실측 예외 0). 두 줄이 갈리면 늦은 날로 맞춘다(늦추기만 · 합은 둘 다 안 뒤에 안다).
debt_fill <- dq[, if (.N == 1L) .SD, by = .(Ticker, Period)]
debt_fill[, `:=`(Item = fifelse(Item == "CurrentBorr", "LongTermBorr", "CurrentBorr"), Value = 0, with_bonds = FALSE)]
debt_fill_n <- debt_fill[, .N, by = Item]
dq <- rbind(dq, debt_fill, use.names = TRUE)
dq[, fd_max := max(Factor_Date), by = .(Ticker, Period)]
debt_redated <- dq[Factor_Date < fd_max, .N]
dq[, Factor_Date := fd_max][, fd_max := NULL]
.fill_n <- function(it) { n <- debt_fill_n[Item == it, N]; if (length(n)) n else 0L }
cat(sprintf(paste0("[merged-v2] 차입금 = 차입 + 사채(DLC · DLTT): 성분 %s → %s칸(사채 포함 %s · 성분끼리 기간 말일이나 정정 표지가 갈린 칸 %d) · ",
                   "한 줄만 있는 칸의 없는 줄 = 0 행: DLC %s · DLTT %s · 두 줄 날짜 맞춤 %d\n"),
            paste(debt_n_in[, sprintf("%s %s", Item, format(N, big.mark = ","))], collapse = " · "),
            format(debt_cells_reported, big.mark = ","), format(dq[with_bonds == TRUE, .N], big.mark = ","), debt_mixed,
            format(.fill_n("CurrentBorr"), big.mark = ","), format(.fill_n("LongTermBorr"), big.mark = ","), debt_redated))
debt_stats <- list(parts_in = setNames(as.list(debt_n_in$N), debt_n_in$Item), cells = debt_cells_reported,
                   cells_with_bonds = dq[with_bonds == TRUE, .N], cells_mixed_check = debt_mixed,
                   zero_line_written = list(ShortTermBorr = .fill_n("CurrentBorr"), LongTermBorr = .fill_n("LongTermBorr")),
                   lines_redated = debt_redated)
dq[, with_bonds := NULL]
q <- rbind(q[!Item %in% names(DEBT_TO)], dq, use.names = TRUE)
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
# A2. 2015~ 주식 수(ISSD) · 기중 취득 자기주식 수(SBB)는 분기 그대로 — 지금 병합 표도 2015~ 에 이 둘만 XLSX 분기 행으로
#     가진다(11-09 실측 · DART 에 없는 항목). 연간 행(B · RQ)에서는 뺀다(같은 기간 키 중복 방지).
SHQ <- c("ISSD", "SBB")
A2 <- q[P %/% 100L >= 2015L & Old %in% SHQ, .(Ticker, Period, Period_Date, Factor_Date, Item = Old, Value,
                                             Source = "QW_V2", Freq = "Q")]

# ---- B. 2015~ 회계연도 말 연간(2014 = 성장률 씨앗) -----------------------------------------------------
qa <- q[FY >= 2014L]
key <- unique(qa[P == FYE, .(Ticker, FY, Period_Date, Factor_Date, Check)])
if (anyDuplicated(key[, .(Ticker, FY)])) { cat("[merged-v2] 오류: 연말 키가 겹친다\n"); quit(status = 1) }
# 연간 행 날짜 = 그 회계연도 네 분기 가운데 가장 늦은 날: 흐름은 네 분기 합이라, 연말 뒤에 정정된 분기가 있으면
#   그 정정이 나온 뒤에야 합을 안다(앞당김 금지)
kq <- qa[, .(fy_fd = max(Factor_Date)), by = .(Ticker, FY)]
key <- kq[key, on = .(Ticker, FY)]
n_key_late <- key[fy_fd > Factor_Date, .N]
key[fy_fd > Factor_Date, Factor_Date := fy_fd][, fy_fd := NULL]
cat(sprintf("[merged-v2] 연간 날짜 = 네 분기 가운데 가장 늦은 날로 늦춘 기업-연도 %d\n", n_key_late))
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
# 정정 의심 기업-연도: DART 당시 기록이 퀀티 미룬 값보다 먼저 쓰일 수 있으면 DART(RS) · 아니면(DART 가 나중 정정본 ·
#   기록 없음) 퀀티 미룬 값(RSQ) — 둘 다 그 날짜엔 공개된 값이고, 늦게 오는 쪽은 도착 때 이미 최신이 아니다
ck <- as.data.table(read_parquet(file.path(V2D, "fund_v2_annual_check.parquet")))
dfd <- unique(ck[!is.na(DART_Factor_Date), .(Ticker, FY, DART_Factor_Date)])
if (anyDuplicated(dfd[, .(Ticker, FY)])) { cat("[merged-v2] 오류: DART 날짜가 기업-연도마다 하나가 아니다\n"); quit(status = 1) }
RSk <- merge(unique(key[Check == "restated", .(Ticker, FY, kfd = Factor_Date)]), dfd, by = c("Ticker", "FY"), all.x = TRUE)
RS  <- RSk[!is.na(DART_Factor_Date) & DART_Factor_Date <= kfd, .(Ticker, FY)]
RSQ <- RSk[is.na(DART_Factor_Date) | DART_Factor_Date > kfd, .(Ticker, FY)]
cat(sprintf("[merged-v2] 정정 의심 %d 기업-연도 = DART 당시 기록 %d + 퀀티 미룬 값 %d(DART 기록이 더 늦음 %d · 없음 %d)\n",
            nrow(RSk), nrow(RS), nrow(RSQ), RSk[!is.na(DART_Factor_Date) & DART_Factor_Date > kfd, .N],
            RSk[is.na(DART_Factor_Date), .N]))
dB <- derive_fundamental_items(an[, .(Ticker, Period, Period_Date, Factor_Date, Item = Old, Value)])
dB[, FY := as.integer(Period) %/% 100L]
dB <- dB[FY >= 2015L & !(Item %in% names(MAP))]
# 정정 의심 연도(RS = DART 당시 기록을 쓰는 해)도 차입 파생 항목만은 퀀티 파생을 쓴다 — 날짜 = 그해 퀀티 키 날짜(정정 의심이면 v2 가
#   미룬 날 = 다음 회계연도 사업보고서 뒤 · PIT 안전) · DART 차입 계정은 정의가 달라 쓰지 않는다(위 DEBT_ITEMS · 아래 C).
dB <- rbind(dB[!RS, on = .(Ticker, FY)], dB[RS, on = .(Ticker, FY), nomatch = 0L][Item %in% DEBT_ITEMS])
# 파생은 직전 연도 값을 쓴다(성장률 · 평균 · 변화량) → 날짜 = 그해와 직전 연도 가운데 늦은 날
pk <- key[, .(Ticker, FY = FY + 1L, prev_fd = Factor_Date)]
dB <- pk[dB, on = .(Ticker, FY)]
n_der_redate <- dB[!is.na(prev_fd) & prev_fd > Factor_Date, .N]
dB[!is.na(prev_fd) & prev_fd > Factor_Date, Factor_Date := prev_fd]
dB <- dB[, .(Ticker, Period, Period_Date, Factor_Date, Item, Value, Source = "QW_V2_derived", Freq = "A")]
B <- an[FY >= 2015L][!RSk, on = .(Ticker, FY)][, .(Ticker, Period, Period_Date, Factor_Date, Item = Old, Value,
            Source = fifelse(Check == "agree", "QW_V2", "QW_V2_UNVERIFIED"), Freq = "A")][!(Item %in% SHQ)]

# ---- C. 정정 의심 기업-연도 = DART 당시 보고서 기록 + 퀀티 전용 항목(미룸) · 또는 퀀티 미룬 값 전부(RSQ) ------------
dd <- as.data.table(read_parquet(DART))
num <- setdiff(names(dd)[vapply(dd, is.numeric, logical(1))], "bsns_year")
for (col in num) if (!is.double(dd[[col]])) set(dd, j = col, value = as.double(dd[[col]]))
dl <- melt(dd, id.vars = c("Ticker", "bsns_year"), measure.vars = num, variable.name = "Item", value.name = "Value",
           variable.factor = FALSE)[!is.na(Value)]
dl <- dl[RS, on = .(Ticker, bsns_year = FY), nomatch = 0L]
# 차입 원계정 · 파생은 DART 기록에서 뺀다(정의가 다르다 · DEBT_ITEMS) → covered 에 없으니 원계정은 아래 RQ 가 퀀티 미룬 값으로 채우고,
#   파생은 위 dB 가 퀀티 파생으로 채운다(2026-11-10).
n_dart_debt_dropped <- dl[Item %in% DEBT_ITEMS, .N]
dl <- dl[!Item %in% DEBT_ITEMS]
dl <- merge(dl, dfd, by.x = c("Ticker", "bsns_year"), by.y = c("Ticker", "FY"))
# sprintf, not paste0: paste0(integer(0), "-12-31") returns "-12-31" (length 1) and as.Date() then fails when no
#   company-year is restated (11-09 대조군 TC)
DR <- dl[, .(Ticker, FY = bsns_year, Period = sprintf("%d12", bsns_year), Period_Date = as.Date(sprintf("%d-12-31", bsns_year)),
             Factor_Date = DART_Factor_Date, Item, Value, Source = "DART_RESTATED", Freq = "A")]
# DART 파생(원계정 이름 밖)도 직전 연도 값을 쓴다 → 직전 연도 DART 날짜(없으면 퀀티 직전 연도 날짜)와 비교해 늦은 날
pdd <- dfd[, .(Ticker, FY = FY + 1L, prev_dfd = DART_Factor_Date)]
DR <- pdd[DR, on = .(Ticker, FY)]
DR <- pk[DR, on = .(Ticker, FY)]
DR[, prev_fd := fifelse(!is.na(prev_dfd), prev_dfd, prev_fd)]
n_dr_redate <- DR[!(Item %in% names(MAP)) & !is.na(prev_fd) & prev_fd > Factor_Date, .N]
DR[!(Item %in% names(MAP)) & !is.na(prev_fd) & prev_fd > Factor_Date, Factor_Date := prev_fd]
DR <- DR[, .(Ticker, Period, Period_Date, Factor_Date, Item, Value, Source, Freq)]
cat(sprintf("[merged-v2] 파생 날짜를 직전 연도 날짜로 늦춘 행: 퀀티 %d · DART %d\n", n_der_redate, n_dr_redate))
covered <- unique(dl[, .(Ticker, FY = bsns_year, Old = Item)])
RQ <- rbind(an[FY >= 2015L][RS, on = .(Ticker, FY), nomatch = 0L][!covered, on = .(Ticker, FY, Old)],
            an[FY >= 2015L][RSQ, on = .(Ticker, FY), nomatch = 0L])
RQ <- RQ[, .(Ticker, Period, Period_Date, Factor_Date, Item = Old, Value, Source = "QW_V2_DELAYED", Freq = "A")][!(Item %in% SHQ)]
miss_rs <- RSk[is.na(DART_Factor_Date), .N]

# ---- D. 합치기 · 검사 · 날짜 순서 계약 · 쓰기 ---------------------------------------------------------------
.check_keys <- function(D, label) {
  dup <- D[, .N, by = .(Ticker, Period, Item)][N > 1L]
  if (nrow(dup)) { cat("[merged-v2] 오류:", label, "중복 키", nrow(dup), "\n"); print(head(dup)); quit(status = 1) }
  bad <- D[is.na(Factor_Date) | Factor_Date <= Period_Date]
  if (nrow(bad)) { cat("[merged-v2] 오류:", label, "Factor_Date 가 없거나 기간 말 이전인 행", nrow(bad), "\n"); print(head(bad)); quit(status = 1) }
}
.write_atomic <- function(D, path) {
  setindex(D, NULL)   # 자동 색인을 파일에 싣지 않는다(R 메타데이터로 저장돼 읽을 때 되살아난다 · 11-10 · 위 .check_debt_lines)
  tmp <- paste0(path, ".tmp", Sys.getpid())
  write_parquet(D, tmp, compression = "zstd", compression_level = 5L, write_statistics = FALSE)
  if (file.exists(path)) unlink(path)
  if (!file.rename(tmp, path)) { cat("[merged-v2] 오류: 이름 바꾸기 실패", tmp, "\n"); quit(status = 1) }
}
.say_order <- function(label, s) {
  cat(sprintf("[merged-v2] %s 날짜 순서 계약: 늦게 도착한 옛 기간 %s행 버림(바로 뒤 기간에 빈칸 %s) · 같은 날 도착 %s행 늦춤(최대 %d일)\n",
              label, format(s$dropped, big.mark = ","), format(s$holes_created, big.mark = ","),
              format(s$shifted, big.mark = ","), as.integer(s$max_shift_days)))
}
# 차입 두 줄 기간 완비 단정(★2026-11-10(2) · 위 debt_fill): 단기 · 장기차입금은 같은 (종목, 기간)에 함께 있고 날짜가 같다 —
#   그래야 '항목마다 최신 행'을 고르는 소비자가 두 줄을 같은 기간에서 읽는다. 병합 표는 두 줄 합 = 같은 기간 TotalDebt 도 단정한다
#   (TotalDebt 만 있거나 두 줄만 있는 칸 = 파생 날짜를 직전 연도 날짜로 늦춘 행이 순서 계약에서 갈린 것 — 세어서 보고).
.check_debt_lines <- function(D, label, with_total = FALSE) {
  # 사본 위에서 고른다 — D[Item == ...] 는 data.table 자동 색인을 D 에 남기고, 이미 정렬된 표에는 쓰기 직전 setorder 가 아무 일도 안 해서
  #   그 색인이 parquet R 메타데이터로 저장 · 읽을 때 되살아난다(11-10 실측: 병합 표 56 → 175 MB · 아래 .write_atomic 도 색인을 지운다)
  w <- D[, .(Ticker, Period, Item, Factor_Date, Value)]
  s <- w[Item == "ShortTermBorr", .(Ticker, Period, fs = Factor_Date, vs = Value)]
  l <- w[Item == "LongTermBorr", .(Ticker, Period, fl = Factor_Date, vl = Value)]
  j <- merge(s, l, by = c("Ticker", "Period"), all = TRUE)
  bad <- j[is.na(fs) | is.na(fl) | fs != fl]
  if (nrow(bad)) {
    cat("[merged-v2] 오류:", label, "차입 두 줄(단기 · 장기차입금)의 기간 · 날짜가 갈린 칸", nrow(bad), "\n"); print(head(bad)); quit(status = 1)
  }
  st <- list(cells = nrow(j))
  if (with_total) {
    k <- merge(j[, .(Ticker, Period, sl = vs + vl)], w[Item == "TotalDebt", .(Ticker, Period, td = Value)],
               by = c("Ticker", "Period"), all = TRUE)
    badv <- k[!is.na(sl) & !is.na(td) & abs(sl - td) > 1e-9 * pmax(1, abs(td))]
    if (nrow(badv)) {
      cat("[merged-v2] 오류:", label, "두 줄 합 ≠ 같은 기간 TotalDebt", nrow(badv), "칸\n"); print(head(badv)); quit(status = 1)
    }
    st$lines_without_total <- k[is.na(td), .N]
    st$total_without_lines <- k[is.na(sl), .N]
  }
  cat(sprintf("[merged-v2] %s 차입 두 줄 기간 완비: %s칸 · 날짜 같음%s\n", label, format(st$cells, big.mark = ","),
              if (with_total) sprintf(" · 합 = TotalDebt(두 줄만 %d · TotalDebt 만 %d)", st$lines_without_total, st$total_without_lines) else ""))
  st
}
M <- rbindlist(list(A, A2, dA, B, dB, DR, RQ), use.names = TRUE)
.check_keys(M, "병합")
oc <- order_contract(M); M <- oc$D
.say_order("병합", oc$stats)
.check_keys(M, "병합(계약 뒤)")
dlm <- .check_debt_lines(M, "병합", with_total = TRUE)
# Source = 소비자 호환 역할 표지(지금 병합 표의 뜻 그대로: XLSX 분기 원계정 · xlsx_derived 분기 파생 · DART 연간 원계정 +
#   파생) — 전략 엔진 약 20곳이 Source == "DART" / "XLSX" 로 연간 · 분기 행을 가른다(11-09 전수 검색 · 엔진 파일은 연구
#   산출물이라 고치지 않는다). 실제 출처는 Origin(QW_V2 · QW_V2_UNVERIFIED · QW_V2_DELAYED · DART_RESTATED · QW_V2_derived).
setnames(M, "Source", "Origin")
M[, Source := fifelse(Freq == "A", "DART", fifelse(Origin == "QW_V2_derived", "xlsx_derived", "XLSX"))]
setcolorder(M, c("Ticker", "Period", "Period_Date", "Factor_Date", "Item", "Value", "Source", "Origin", "Freq"))
setorder(M, Ticker, Item, Factor_Date)
.write_atomic(M, OUT)

# ---- E. 분기 단독 원계정 41개 전 기간(fundamental_xlsx.parquet 꼴 · XF 팩터) --------------------------------------
X <- q[Old %in% FUND_RAW_ITEMS, .(Ticker, Period, Item = Old, Value, Period_Date, Factor_Date)]
.check_keys(X, "분기 표")
ox <- order_contract(X); X <- ox$D
.say_order("분기 표", ox$stats)
.check_keys(X, "분기 표(계약 뒤)")
dlx <- .check_debt_lines(X, "분기 표")
setcolorder(X, c("Ticker", "Period", "Item", "Value", "Period_Date", "Factor_Date"))
setorder(X, Ticker, Item, Factor_Date)
.write_atomic(X, OUTX)

src <- M[, .N, by = .(Source, Origin, Freq)][order(Freq, Source, Origin)]
rep <- list(schema = "fundamental_merged_v2_report/v2", built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
            rows = nrow(M), tickers = uniqueN(M$Ticker), items = uniqueN(M$Item),
            by_source = setNames(as.list(src$N), paste(src$Freq, src$Source, src$Origin)),
            restated_company_years = nrow(RSk), restated_dart_record = nrow(RS), restated_qw_delayed = nrow(RSQ),
            restated_without_dart = miss_rs,
            debt = c(debt_stats, list(definition = paste("ShortTermBorr = CurrentBorr + CurrentBonds (DLC) · LongTermBorr = LongTermBorr + Bonds (DLTT) ·",
                                                         "TotalDebt NA when both absent · period-complete lines: one line present -> the other written as 0 (same date)"),
                                      dart_debt_rows_dropped_restated = n_dart_debt_dropped,
                                      lines_check = list(merged = dlm, xlsx = dlx))),
            annual_company_years = uniqueN(M[Freq == "A", .(Ticker, Period)]),
            annual_date_raised_to_latest_quarter = n_key_late,
            derived_date_raised_to_prior_year = list(qw = n_der_redate, dart = n_dr_redate),
            order_contract = list(merged = oc$stats, xlsx = ox$stats),
            xlsx = list(path = OUTX, rows = nrow(X), tickers = uniqueN(X$Ticker), items = uniqueN(X$Item)))
writeLines(toJSON(rep, auto_unbox = TRUE, pretty = TRUE), file.path(dirname(OUT), "fundamental_merged_v2_report.json"), useBytes = TRUE)
cat(sprintf("[merged-v2] 저장 %s · 행 %s · 종목 %d · 항목 %d\n", OUT, format(nrow(M), big.mark = ","),
            uniqueN(M$Ticker), uniqueN(M$Item)))
cat(sprintf("[merged-v2] 저장 %s · 행 %s · 종목 %d · 항목 %d · %.0fs\n", OUTX, format(nrow(X), big.mark = ","),
            uniqueN(X$Ticker), uniqueN(X$Item), as.numeric(difftime(Sys.time(), t0, units = "secs"))))
print(src)
