# =============================================================================
# factor_engine_composite_mom.R — Composite Momentum (12-1 + 6-1 + Residual)
# =============================================================================
# 가설: 단일 모멘텀 호라이즌보다 복합(12-1 가격모멘텀 + 6-1 가격모멘텀 +
#       시장상대 잔차모멘텀)이 노이즈를 평균화해 더 안정적 cross-sectional 신호.
#   - 12-1: 최근 1개월 제외 과거 12개월 수익률 (단기반전 회피, Jegadeesh-Titman)
#   - 6-1 : 최근 1개월 제외 과거 6개월 수익률 (중기 모멘텀)
#   - Residual: 시장상대(개별 Ret - BM_Ret) 누적 — 시장공통 성분 제거한 특이 모멘텀
#               (Blitz-Huij-Martens 2011 residual momentum의 경량 근사; beta=1 가정)
#   세 신호를 각 시그널 날짜에 cross-sectional z-score로 표준화 후 등가중 평균.
#
# PIT: 모든 입력은 shift(., k>=21) 과거 종가 또는 과거 누적수익 — 동일시점 참조 없음.
#      잔차도 과거 21~252일 구간의 (Ret - BM_Ret) 합으로 t 시점 정보 미사용.
# RAWDATA columns: Date, Ticker, Close, Vol, TradingValue, AvgTV20, LiqPass (+ Ret, BM_Ret)
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 개별/시장 일간수익률 (없으면 종가로 도출) -------------------------------
if (!("Ret" %in% names(RAWDATA)))
  RAWDATA[, Ret := Close / shift(Close, 1L) - 1, by = Ticker]
if (!("BM_Ret" %in% names(RAWDATA))) {
  # BM_DT(Date, BM_Ret)에서 일자 매칭 (load 시 함께 제공됨)
  if (exists("BM_DT") && "BM_Ret" %in% names(BM_DT)) {
    bm_map <- BM_DT[, .(Date, .BMR = BM_Ret)]
    RAWDATA[bm_map, BM_Ret := i..BMR, on = "Date"]
  } else {
    RAWDATA[, BM_Ret := 0]   # fallback: 시장중립 잔차 비활성 (12-1/6-1만)
  }
}

# ---- 팩터 정의 (과거 윈도우만 — PIT-safe) -----------------------------------
# 가격 모멘텀 (skip 최근 ~1개월 = 21거래일)
RAWDATA[, .mom_12_1 := shift(Close, 21L)  / shift(Close, 252L) - 1, by = Ticker]
RAWDATA[, .mom_6_1  := shift(Close, 21L)  / shift(Close, 126L) - 1, by = Ticker]

# 잔차 모멘텀: 과거 (12-1) 구간의 일간 (Ret - BM_Ret) 누적합.
#   t 시점 잔차 = sum_{k=22..252} (Ret_{t-k} - BM_Ret_{t-k})  → shift로 과거만 참조.
RAWDATA[, .exret := Ret - BM_Ret, by = Ticker]
# rolling sum of past excess returns over [t-252, t-21] (skip recent month)
RAWDATA[, .csum := cumsum(fifelse(is.finite(.exret), .exret, 0)), by = Ticker]
RAWDATA[, .resid_mom := shift(.csum, 21L) - shift(.csum, 252L), by = Ticker]

# ---- 월말 시그널 날짜 추출 ---------------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

# ---- cross-sectional z-score 합성 -------------------------------------------
.sig <- RAWDATA[
  Date %in% .month_ends & LiqPass == TRUE &
    is.finite(.mom_12_1) & is.finite(.mom_6_1) & is.finite(.resid_mom),
  .(Date, Ticker, .mom_12_1, .mom_6_1, .resid_mom)
]

.zsc <- function(x) { s <- sd(x, na.rm = TRUE); if (!is.finite(s) || s == 0) return(rep(0, length(x))); (x - mean(x, na.rm = TRUE)) / s }
.sig[, z_12_1 := .zsc(.mom_12_1), by = Date]
.sig[, z_6_1  := .zsc(.mom_6_1),  by = Date]
.sig[, z_res  := .zsc(.resid_mom), by = Date]
.sig[, Score  := (z_12_1 + z_6_1 + z_res) / 3]

FACTORS <- .sig[is.finite(Score), .(Date, Ticker, Score)]

# ---- 정리 (RAWDATA 임시컬럼 제거) -------------------------------------------
RAWDATA[, c(".mom_12_1", ".mom_6_1", ".exret", ".csum", ".resid_mom", ".ym") := NULL]

cat(sprintf("[factor_engine_composite_mom] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
