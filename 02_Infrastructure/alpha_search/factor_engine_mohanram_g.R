# =============================================================================
# factor_engine_mohanram_g.R — Mohanram (2005, RAS) G-Score 완전 복제 (KR)
# =============================================================================
# "Separating Winners from Losers among Low Book-to-Market Stocks" (RAS 2005)
#   G-Score = growth(저BM) 종목 내 8개 binary signal 합. 고 G-Score long-only.
#   Piotroski(고BM/value)와 정반대 — 저BM(growth) 모집단이 적용 대상.
#
# === Mohanram 8 signals (논문 정의, 부호 그대로) ===
#   [수익성/현금흐름 3]
#     G1 ROA      = 1{ ROA   > 산업 중앙값 }          ROA = NI_ttm / TA_avg
#     G2 CFROA    = 1{ CFROA > 산업 중앙값 }          CFROA = CFO_ttm / TA_avg
#     G3 ACCRUAL  = 1{ CFO_ttm > NI_ttm }             현금이익 > 발생이익 (음의 accrual)
#   [실현 안정성 2 — 낮을수록 +]
#     G4 EARN_VAR = 1{ ROA의 변동성  < 산업 중앙값 }   분기 ROA 8Q rolling sd (낮을수록 우량)
#     G5 SG_VAR   = 1{ 매출성장 변동성 < 산업 중앙값 } 분기 매출 YoY성장 8Q rolling sd (낮을수록)
#   [성장 투자(conservatism, growth주는 높을수록 +) 3]
#     G6 RND      = 1{ R&D/TA      > 산업 중앙값 }     RandD_ttm / TotalAssets
#     G7 CAPEX    = 1{ CapEx/TA    > 산업 중앙값 }     ★KR raw CapEx 부재 → DepAmort_ttm/TA proxy
#     G8 ADV      = 1{ Adv/TA      > 산업 중앙값 }     ★KR raw 광고비 부재 → 미구현(7/8 복제)
#
#   ★ 복제 충실도 한계 (명시):
#     - G8(광고비/TA): KR fundamental DB에 advertising raw 항목 부재 → 제외. G-Score 7개 신호로.
#     - G7(CapEx/TA): KR raw에 CapitalExpenditure 직접 항목 없음(2016~ CapitalIntensity 파생은
#       범위 협소·2005 미가용). DepAmort(감가상각비)_ttm/TA를 capital-intensity proxy로 사용
#       (capital-intensive 정도의 학술적 대용 — 부호 동일: 자본집약 high = growth 우량 신호).
#       proxy임을 명시. → 실질 6 raw-direct + 1 proxy = 7개 신호.
#     - 산업 분류: RAWDATA$Sector (27 레벨, GICS-유사). 논문은 2-digit SIC 산업 중앙값.
#
# === 데이터 ===
#   재무: .cache/fundamental_merged.parquet (long: Ticker/Period/Period_Date/
#     Factor_Date/Item/Value). Factor_Date = PIT 가용일(이미 lag 반영, C4 충족).
#   flow(NI/CFO/Rev/RandD/DepAmort)는 분기 discrete → TTM(trailing 4Q) 합.
#   stock(TA/Equity)은 최근값. 산업/시총/BM은 RAWDATA(월말) 경유.
#   가용 광역 항목(2000~, 2500+종목)만 사용 — 협소 파생(2016~) 배제.
#
# === PIT ===
#   Factor_Date <= sig_date 만 사용(C4). 동일시점 순환 없음. rolling sd는 과거 8Q.
#   산업 중앙값은 각 sig_date "그 시점 가용 표본"의 cross-sectional median (C1 위반 아님:
#   동시점 횡단면 비교는 lookahead 아님 — Piotroski/Mohanram 원논문도 동시점 산업 median).
#
# === 모드 (env "MOHANRAM_MODE") ===
#   "LOWBM"(기본, 논문 정합): 저BM(growth) 절반 내 G-Score 상위 → 논문 전략.
#   "ALL"               : universe 전체 내 G-Score 상위 (비교 진단용).
#
# universe(K200_KQ150)·start_date(2005~)는 run_alpha_search가 처리.
# 산출: FACTORS(Date, Ticker, Score=G-Score). EW/IVOL top-N 선택.
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
suppressMessages({library(arrow); library(data.table)})

.MG_MODE <- Sys.getenv("MOHANRAM_MODE", "LOWBM")            # "LOWBM" | "ALL"
.FUND_PQ <- file.path(Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"), ".cache", "fundamental_merged.parquet")
stopifnot(file.exists(.FUND_PQ))

# ---- 1. 필요한 raw 항목만 1회 로드 (OOM 회피: Item push-down) -----------------
.items_need <- c("NetIncome", "OperatingCF", "TotalAssets", "TotalEquity",
                 "Revenue", "RandD", "DepAmort")
.fd <- as.data.table(read_parquet(
  .FUND_PQ,
  col_select = c("Ticker", "Period", "Period_Date", "Factor_Date", "Item", "Value")))
.fd <- .fd[Item %in% .items_need & is.finite(Value)]
# 동일 (Ticker,Period,Item) 복수 Source → Factor_Date 가장 이른(=가장 먼저 가용) 행 1개
setorder(.fd, Ticker, Item, Period, Factor_Date)
.fd <- .fd[, .SD[1], by = .(Ticker, Item, Period)]

# wide: 한 행 = (Ticker, Period) 모든 항목 + 그 Period의 Factor_Date(가용일)
.fad <- .fd[, .(Factor_Date = max(Factor_Date)), by = .(Ticker, Period, Period_Date)]
.w   <- dcast(.fd, Ticker + Period ~ Item, value.var = "Value")
.w   <- merge(.w, .fad, by = c("Ticker", "Period"))
setorder(.w, Ticker, Period)

# 누락 항목 NA 컬럼 보장
for (cc in .items_need) if (!cc %in% names(.w)) .w[[cc]] <- NA_real_

# ---- 2. TTM flow (trailing 4Q 합) -------------------------------------------
.flow <- c("NetIncome", "OperatingCF", "Revenue", "RandD", "DepAmort")
for (cc in .flow)
  .w[, (paste0(cc, "_ttm")) := frollsum(get(cc), 4L, align = "right"), by = Ticker]

# 평균자산(TTM ROA 분모): 최근 TA와 4분기 전 TA 평균(연간 평균자산 근사)
.w[, TA_lag4 := shift(TotalAssets, 4L), by = Ticker]
.w[, TA_avg  := fifelse(is.finite(TA_lag4), (TotalAssets + TA_lag4) / 2, TotalAssets)]

# ---- 3. 수준 비율 (현재 분기) ------------------------------------------------
.w[, ROA   := NetIncome_ttm   / TA_avg]          # G1 분자
.w[, CFROA := OperatingCF_ttm / TA_avg]          # G2 분자
.w[, RND_I := RandD_ttm       / TotalAssets]     # G6 R&D intensity
.w[, CAPX_I:= DepAmort_ttm    / TotalAssets]     # G7 CapEx intensity (DepAmort proxy)

# ---- 4. 실현 안정성: 분기 ROA, 분기 매출 YoY성장 → 과거 8Q rolling sd ----------
#   ROA 변동성: 분기 단위 ROA(분기 NI / TA)의 표준편차. PIT: 과거 8Q(현재 포함) rolling.
.w[, ROA_q := NetIncome / TotalAssets]                       # 분기 ROA(수준)
.w[, EARN_VAR := frollapply(ROA_q, 8L, sd, align = "right", na.rm = TRUE), by = Ticker]
#   매출성장 변동성: 분기 매출 YoY 성장률(t vs t-4Q)의 과거 8Q rolling sd
.w[, Rev_yoy := Revenue / shift(Revenue, 4L) - 1, by = Ticker]
.w[, SG_VAR  := frollapply(Rev_yoy, 8L, sd, align = "right", na.rm = TRUE), by = Ticker]

# ---- 5. PIT-safe 분기 레코드 (Factor_Date 유효 + 핵심 수준 유효) --------------
.MGq <- .w[is.finite(Factor_Date) & is.finite(TA_avg) & TA_avg > 0,
           .(Ticker, Factor_Date, Period,
             ROA, CFROA, RND_I, CAPX_I, EARN_VAR, SG_VAR,
             NI_ttm = NetIncome_ttm, CFO_ttm = OperatingCF_ttm, EQ = TotalEquity)]
setorder(.MGq, Ticker, Factor_Date)

# ---- 6. 월말 sig_date 추출 ----------------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)

# ---- 7. 각 sig_date에 PIT-safe 최신 분기 매핑 (Factor_Date <= sig_date 중 최신) -
.grid <- CJ(Ticker = unique(.MGq$Ticker), Date = .month_ends)
setkey(.MGq, Ticker, Factor_Date)
setkey(.grid, Ticker, Date)
.mapped <- .MGq[.grid, on = .(Ticker, Factor_Date = Date), roll = TRUE,
                .(Ticker, Date = Factor_Date,
                  ROA, CFROA, RND_I, CAPX_I, EARN_VAR, SG_VAR, NI_ttm, CFO_ttm, EQ)]
.mapped <- .mapped[is.finite(ROA)]

# ---- 8. 산업(Sector) + 시총 결합 (RAWDATA 월말) ------------------------------
.sec <- unique(RAWDATA[Date %in% .month_ends, .(Date, Ticker, Sector, MC = Size)])
.mapped <- merge(.mapped, .sec, by = c("Date", "Ticker"))
.mapped <- .mapped[!is.na(Sector)]                    # 산업 중앙값 비교 불가 종목 제외

# ---- 9. BM 계산 + 저BM(growth) 모집단 정의 (논문 핵심) ------------------------
#   BM = TotalEquity / MarketCap (장부가/시가). 저BM = growth.
.mapped[, BM := EQ / MC]
.mapped <- .mapped[is.finite(BM) & BM > 0]
if (.MG_MODE == "LOWBM") {
  #   각 Date에서 BM 하위 절반(median 미만) = 저BM(growth) 모집단 → Mohanram 적용 대상
  .mapped[, bm_med := median(BM, na.rm = TRUE), by = Date]
  .mapped <- .mapped[BM < bm_med]
}

# ---- 10. 산업 중앙값 대비 8(=7) binary signals ------------------------------
#   ★ 산업 중앙값은 "growth 모집단 내 + 그 sig_date 시점" 횡단면 median (동시점, lookahead 아님).
#      Sector별 표본 너무 작으면(<5) 전체 median fallback(안정성).
b <- function(x) as.integer(x)
.med_by_sec <- function(dt, col) {
  dt[, .sec_n := .N, by = .(Date, Sector)]
  dt[, .sm := median(get(col), na.rm = TRUE), by = .(Date, Sector)]   # 산업 median
  dt[, .gm := median(get(col), na.rm = TRUE), by = Date]              # 전체 median(fallback)
  out <- dt[, fifelse(.sec_n >= 5L & is.finite(.sm), .sm, .gm)]
  dt[, c(".sec_n", ".sm", ".gm") := NULL]
  out
}
.mapped[, med_ROA      := .med_by_sec(.mapped, "ROA")]
.mapped[, med_CFROA    := .med_by_sec(.mapped, "CFROA")]
.mapped[, med_RND_I    := .med_by_sec(.mapped, "RND_I")]
.mapped[, med_CAPX_I   := .med_by_sec(.mapped, "CAPX_I")]
.mapped[, med_EARN_VAR := .med_by_sec(.mapped, "EARN_VAR")]
.mapped[, med_SG_VAR   := .med_by_sec(.mapped, "SG_VAR")]

.mapped[, G1 := b(ROA    > med_ROA)]                      # ROA > 산업median
.mapped[, G2 := b(CFROA  > med_CFROA)]                    # CFROA > 산업median
.mapped[, G3 := b(CFO_ttm > NI_ttm)]                      # 음의 accrual(현금>발생)
.mapped[, G4 := b(EARN_VAR < med_EARN_VAR)]               # ROA변동성 낮음(< 산업median)
.mapped[, G5 := b(SG_VAR   < med_SG_VAR)]                 # 매출성장변동성 낮음
.mapped[, G6 := b(RND_I  > med_RND_I)]                    # R&D intensity 높음
.mapped[, G7 := b(CAPX_I > med_CAPX_I)]                   # CapEx intensity(proxy) 높음
# G8(광고비) = KR raw 부재 → 미구현 (7개 신호)

# ---- 11. G-Score = 7 신호 합 -------------------------------------------------
#   ★ 신호 유효성 정책 (env MOHANRAM_MINSIG):
#     "7"(기본, 완전복제): 7신호 모두 유효한 분기만(부분점수 배제) — Mohanram 원논문 정합.
#     정수 k(<7): k개 이상 유효하면 채택(available-case). KR R&D(G6)가 2016년 이후 데이터
#       소스 단절로 급감(1203→42 종목)해 complete-case는 2016+ 표본 붕괴(month당 ~10종목).
#       k=5 = available-case 강건 모드(2016+ OOS 표본 보존). complete-case는 "검증 무효" 아니라
#       데이터 한계 노출 — 논문 충실(7) + 강건(5) 둘 다 측정해 명시 비교.
.minsig <- suppressWarnings(as.integer(Sys.getenv("MOHANRAM_MINSIG", "7")))
if (is.na(.minsig)) .minsig <- 7L
.gcols <- paste0("G", c(1:7))
.mapped[, n_valid := rowSums(!is.na(.SD)), .SDcols = .gcols]
.mapped[, GSCORE  := rowSums(.SD, na.rm = TRUE), .SDcols = .gcols]
.MG <- .mapped[n_valid >= .minsig, .(Date, Ticker, GSCORE, n_valid)]
#   available-case(<7)에서 같은 날 종목 간 n_valid 상이 가능 → G-Score 절대합 비교 불공정.
#   신호율(GSCORE/n_valid)로 정규화해 랭킹 일관성 확보(top-N 선택은 횡단면 랭킹이라 단조변환 무해).
if (.minsig < 7L) .MG[, GSCORE := GSCORE / n_valid]
.MG <- .MG[, .(Date, Ticker, GSCORE)]
cat(sprintf("[mohanram_g] MINSIG=%d (7=완전복제 / <7=available-case 강건)\n", .minsig))

# ---- 12. FACTORS 산출 (유동성 통과 종목만) -----------------------------------
.liq <- RAWDATA[Date %in% .month_ends & LiqPass == TRUE, .(Date, Ticker)]
FACTORS <- merge(.MG, .liq, by = c("Date", "Ticker"))[, .(Date, Ticker, Score = GSCORE)]

RAWDATA[, .ym := NULL]
cat(sprintf("[mohanram_g] MODE=%s | FACTORS rows=%d | signal dates=%d | tickers=%d\n",
            .MG_MODE, nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
if (.minsig >= 7L) {
  cat(sprintf("[mohanram_g] G-Score 분포(0..7): %s\n",
              paste(sprintf("%d:%d", 0:7, tabulate(factor(FACTORS$Score, levels = 0:7), 8)), collapse = " ")))
} else {
  cat(sprintf("[mohanram_g] G-Score(신호율) min=%.2f median=%.2f max=%.2f\n",
              min(FACTORS$Score), median(FACTORS$Score), max(FACTORS$Score)))
}
