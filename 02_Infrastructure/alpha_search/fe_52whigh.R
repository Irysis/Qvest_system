# =============================================================================
# fe_52whigh.R — 52-Week High Proximity (George & Hwang 2004)
# =============================================================================
# 논문: George & Hwang (2004) "The 52-Week High and Momentum Investing", JF.
#   현재가가 52주 최고가에 근접한 종목(앵커링 미반영)이 미래 초과수익.
#   Score = Close / max(High, 252거래일). 1에 가까울수록 매수.
#
# ★ 제1원칙 — 미명시값 보충(명시):
#   - 52주 = rolling 252거래일 High 최대. 시그널 = Close/52w_High. decile long-only EW.
#   - 월간 리밸. 유니버스 K200∪KQ150. 기간 2005~.
# ===== PIT =====: 과거 252일 High/현재 Close(t-1까지). 동일시점 순환 없음. NEGATE/FLIP 없음.
# RAWDATA columns: Date, Ticker, Close, High, LiqPass
# =============================================================================
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)
stopifnot("High" %in% names(RAWDATA))

RAWDATA[, .ym := format(Date, "%Y-%m")]
.me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
RAWDATA[, .h52 := {
  v <- rep(NA_real_, .N); mp <- which(Date %in% .me & LiqPass == TRUE)
  for (ix in mp) {
    lo <- ix - 251L
    if (lo >= 1L) { mx <- max(High[lo:ix], na.rm = TRUE)
      if (is.finite(mx) && mx > 0) v[ix] <- Close[ix] / mx }
  }
  v
}, by = Ticker]

FACTORS <- RAWDATA[is.finite(.h52), .(Date, Ticker, Score = .h52)]   # 고점 근접 long (GH momentum)
FACTORS[, N := pmax(5L, as.integer(ceiling(.N / 10))), by = Date]
RAWDATA[, c(".h52", ".ym") := NULL]
cat(sprintf("[fe_52whigh] George-Hwang 2004 | rows=%d dates=%d decile N=%d~%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            if (nrow(FACTORS)) min(FACTORS$N) else 0L, if (nrow(FACTORS)) max(FACTORS$N) else 0L))
