# =============================================================================
# factor_engine_piotroski_f9.R — Piotroski (2000, JAR) F-Score 완전 복제 (KR)
# =============================================================================
# "Value Investing: The Use of Historical Financial Statement Information"
#   F-Score = 9 binary signal 합 (0~9). 고 F-Score long-only.
#
# 9 signals (Piotroski 2000, 부호 논문대로):
#   [수익성 4]
#     F1 ROA       = 1{ ROA = NI_ttm / TA_avg > 0 }
#     F2 CFO       = 1{ CFO_ttm / TA_avg > 0 }
#     F3 dROA      = 1{ ROA_t > ROA_{t-1y} }
#     F4 ACCRUAL   = 1{ CFO_ttm/TA > ROA }   (현금이익 > 발생이익)
#   [레버리지/유동성/자금원천 3]
#     F5 dLEVER    = 1{ (LTDebt/TA)_t  < (LTDebt/TA)_{t-1y} }   장기레버리지 ↓
#     F6 dLIQUID   = 1{ CurrentRatio_t > CurrentRatio_{t-1y} }  유동비율 ↑
#     F7 EQ_OFFER  = 1{ Shares_t <= Shares_{t-1y} }             신주발행 없음
#   [운영효율 2]
#     F8 dMARGIN   = 1{ GrossMargin_t > GrossMargin_{t-1y} }    매출총이익률 ↑
#     F9 dTURN     = 1{ AssetTurnover_t > AssetTurnover_{t-1y} } 자산회전율 ↑
#
# 데이터: .cache/fundamental_merged.parquet (long: Ticker/Period/Period_Date/
#   Factor_Date/Item/Value). raw 항목 2000-03~ , Factor_Date = PIT 가용일(이미 lag).
#   flow(NI/CFO/Rev/GP)는 분기 discrete → TTM(trailing 4Q) 합. stock(TA/LTDebt/
#   CurAssets/CurLiab/Shares)은 최근값. dY는 4분기(=1년) 전 대비.
#
# PIT: Factor_Date <= sig_date 만 사용(C4 재무 lag 이미 반영). 동일시점 순환 없음.
#   월말 sig_date 각각에 대해 "Factor_Date <= sig_date 중 최신 분기"의 F-Score 사용.
#
# universe 필터(K200_KQ150)·start_date(2005~)는 run_alpha_search가 처리.
# 산출: FACTORS(Date, Ticker, Score=F-Score 0..9). EW top-N 선택.
#
# MODE env "PIO_MODE": "ALL"(기본, universe 내 F-Score) / "HIGHBM"(고 BM value 절반 내).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
suppressMessages({library(arrow); library(data.table)})

.PIO_MODE <- Sys.getenv("PIO_MODE", "ALL")            # "ALL" | "HIGHBM"
.FUND_PQ  <- file.path(Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"), ".cache", "fundamental_merged.parquet")
stopifnot(file.exists(.FUND_PQ))

# ---- 1. 필요한 raw 항목만 1회 로드 (OOM 회피: Item 필터 push-down) ------------
.items_need <- c("NetIncome","OperatingCF","TotalAssets","LongTermBorr","NonCurrentLiab",
                 "CurrentAssets","CurrentLiab","CapitalStock","GrossProfit","Revenue")
.fd <- as.data.table(read_parquet(
  .FUND_PQ,
  col_select = c("Ticker","Period","Period_Date","Factor_Date","Item","Value")))
.fd <- .fd[Item %in% .items_need & is.finite(Value)]
# 동일 (Ticker,Period,Item)에 복수 Source 존재 가능 → Factor_Date 가장 이른(=가장 먼저 가용) 행 1개
setorder(.fd, Ticker, Item, Period, Factor_Date)
.fd <- .fd[, .SD[1], by = .(Ticker, Item, Period)]

# wide: 한 행 = (Ticker, Period) 의 모든 항목 + 그 Period의 Factor_Date(가용일)
.fad <- .fd[, .(Factor_Date = max(Factor_Date)), by = .(Ticker, Period, Period_Date)]
.w   <- dcast(.fd, Ticker + Period ~ Item, value.var = "Value")
.w   <- merge(.w, .fad, by = c("Ticker", "Period"))
setorder(.w, Ticker, Period)

# ---- 2. TTM flow (trailing 4Q 합) + prior-year(4Q 전) -------------------------
# flow 항목은 분기 discrete → 4분기 rolling sum = 연간(TTM). 분기 4개 미만이면 NA.
.flow <- c("NetIncome","OperatingCF","GrossProfit","Revenue")
for (cc in .flow) {
  if (!cc %in% names(.w)) { .w[[cc]] <- NA_real_ }
  .w[, (paste0(cc, "_ttm")) := frollsum(get(cc), 4L, align = "right"), by = Ticker]
}
# stock 항목(없으면 NA 컬럼 생성)
for (cc in c("TotalAssets","LongTermBorr","NonCurrentLiab","CurrentAssets","CurrentLiab","CapitalStock"))
  if (!cc %in% names(.w)) .w[[cc]] <- NA_real_

# 장기부채: LongTermBorr 우선, 없으면 NonCurrentLiab fallback
.w[, LTDebt := fifelse(is.finite(LongTermBorr), LongTermBorr, NonCurrentLiab)]
# 평균자산(TTM ROA 분모): 최근 TA와 4분기 전 TA의 평균(Piotroski 연간 평균자산 근사)
.w[, TA_lag4 := shift(TotalAssets, 4L), by = Ticker]
.w[, TA_avg  := fifelse(is.finite(TA_lag4), (TotalAssets + TA_lag4) / 2, TotalAssets)]

# ---- 3. 비율 (현재) -----------------------------------------------------------
.w[, ROA_lvl := NetIncome_ttm   / TA_avg]
.w[, CFOA    := OperatingCF_ttm / TA_avg]                       # F2: CFO/TA
.w[, CR      := CurrentAssets   / CurrentLiab]                  # 유동비율
.w[, LEVER   := LTDebt          / TotalAssets]                  # 장기레버리지(자산대비)
.w[, GM      := GrossProfit_ttm / Revenue_ttm]                  # 매출총이익률
.w[, ATO     := Revenue_ttm     / TotalAssets]                  # 자산회전율
.w[, SHR     := CapitalStock]                                   # 신주발행 proxy(자본금)

# ---- 4. prior-year (4분기 전) 비율 -------------------------------------------
.w[, ROA_py := shift(ROA_lvl, 4L), by = Ticker]
.w[, CR_py  := shift(CR,      4L), by = Ticker]
.w[, LEV_py := shift(LEVER,   4L), by = Ticker]
.w[, GM_py  := shift(GM,      4L), by = Ticker]
.w[, ATO_py := shift(ATO,     4L), by = Ticker]
.w[, SHR_py := shift(SHR,     4L), by = Ticker]

# ---- 5. 9 binary signals (부호 논문대로) -------------------------------------
b <- function(x) as.integer(x)   # TRUE->1, FALSE->0, NA->NA
.w[, F1 := b(ROA_lvl > 0)]
.w[, F2 := b(CFOA    > 0)]
.w[, F3 := b(ROA_lvl > ROA_py)]
.w[, F4 := b(CFOA    > ROA_lvl)]                 # accrual: 현금 > 발생
.w[, F5 := b(LEVER   < LEV_py)]                  # 레버리지 감소
.w[, F6 := b(CR      > CR_py)]                   # 유동비율 증가
.w[, F7 := b(SHR    <= SHR_py)]                  # 신주발행 없음(자본금 불변/감소)
.w[, F8 := b(GM      > GM_py)]                   # 매출총이익률 증가
.w[, F9 := b(ATO     > ATO_py)]                  # 자산회전율 증가

# F-Score: 9 신호 합. 4분기 미만/누락으로 일부 신호 NA → 신호별 NA는 0 처리는 정보왜곡이므로,
#   "유효 신호가 9개 모두 산출된" 분기만 채택(Piotroski 완전 복제 — 부분 점수 배제).
.fcols <- paste0("F", 1:9)
.w[, n_valid := rowSums(!is.na(.SD)), .SDcols = .fcols]
.w[, FSCORE  := rowSums(.SD, na.rm = TRUE),  .SDcols = .fcols]
.PIO <- .w[n_valid == 9L & is.finite(Factor_Date),
           .(Ticker, Factor_Date, Period, FSCORE)]
setorder(.PIO, Ticker, Factor_Date)

# ---- 6. 월말 sig_date 추출 ----------------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)

# ---- 7. 각 sig_date에 PIT-safe F-Score 매핑 (Factor_Date <= sig_date 중 최신) --
#   rolling join: 각 (Ticker, sig_date)에 Factor_Date<=sig_date 최신 분기의 FSCORE.
.grid <- CJ(Ticker = unique(.PIO$Ticker), Date = .month_ends)
setkey(.PIO, Ticker, Factor_Date)
setkey(.grid, Ticker, Date)
.mapped <- .PIO[.grid, on = .(Ticker, Factor_Date = Date), roll = TRUE,
                .(Ticker, Date = Factor_Date, FSCORE)]
.mapped <- .mapped[is.finite(FSCORE)]

# stale 재무 컷오프: F-Score가 18개월 넘게 갱신 안 된(상폐/보고 누락) 종목 제외(PIT 안전)
.lastfd <- .PIO[, .(last_fd = max(Factor_Date)), by = Ticker]   # 진단용(미사용 컷)

# ---- 8. 고 BM value 절반 내 선별 모드 (HIGHBM) — 원논문 정합 옵션 -------------
if (.PIO_MODE == "HIGHBM") {
  # BM = TotalEquity / MarketCap. MarketCap=Size(RAWDATA). Equity=TotalAssets-TotalLiab → 별도 로드.
  .eq <- as.data.table(read_parquet(.FUND_PQ,
            col_select = c("Ticker","Period","Factor_Date","Item","Value")))
  .eq <- .eq[Item == "TotalEquity" & is.finite(Value)]
  setorder(.eq, Ticker, Period, Factor_Date)
  .eq <- .eq[, .SD[1], by = .(Ticker, Period)][, .(Ticker, Factor_Date, EQ = Value)]
  setkey(.eq, Ticker, Factor_Date)
  .eqm <- .eq[.grid, on = .(Ticker, Factor_Date = Date), roll = TRUE,
              .(Ticker, Date = Factor_Date, EQ)][is.finite(EQ)]
  # 시총: RAWDATA Size (월말)
  .mc <- RAWDATA[Date %in% .month_ends, .(Ticker, Date, MC = Size)]
  .bm <- merge(.eqm, .mc, by = c("Ticker","Date"))
  .bm[, BM := EQ / MC]
  .bm <- .bm[is.finite(BM) & BM > 0]
  # 각 Date에서 BM 상위 절반(median 초과)만 통과
  .bm[, bm_med := median(BM, na.rm = TRUE), by = Date]
  .keep_bm <- .bm[BM >= bm_med, .(Ticker, Date)]
  .mapped <- merge(.mapped, .keep_bm, by = c("Ticker","Date"))
}

# ---- 9. FACTORS 산출 (유동성 통과 종목만) ------------------------------------
.liq <- RAWDATA[Date %in% .month_ends & LiqPass == TRUE, .(Date, Ticker)]
FACTORS <- merge(.mapped, .liq, by = c("Date","Ticker"))[, .(Date, Ticker, Score = FSCORE)]

RAWDATA[, .ym := NULL]
cat(sprintf("[piotroski_f9] MODE=%s | FACTORS rows=%d | signal dates=%d | tickers=%d\n",
            .PIO_MODE, nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
cat(sprintf("[piotroski_f9] F-Score 분포: %s\n",
            paste(sprintf("%d:%d", 0:9, tabulate(factor(FACTORS$Score, levels=0:9), 10)), collapse=" ")))
