# =============================================================================
# fe_rskew.R — Realized Return Skewness (Bali, Engle & Murray; Amaya et al. 2015)
# =============================================================================
# 논문: skewness preference — 우측꼬리(high positive skew, lottery-like) 종목은 과대평가
#   되어 미래 저수익. long low(negative) realized skewness decile.
#   (L-313 IdioSkew는 *잔차* 왜도; 본건은 *raw 일수익* 왜도 — 구분.)
#
# ★ 제1원칙 — 미명시값 보충(명시):
#   - realized skew = rolling 252거래일 일수익 3차 표준화 모멘트(최소60). 시그널 = -skew(low long).
#   - decile long-only EW. 월간. K200∪KQ150. 2005~.
# ===== PIT =====: 과거 252일 일수익만(과거 윈도우). NEGATE/FLIP 없음(부호는 skew preference 이론).
# RAWDATA columns: Date, Ticker, Ret, LiqPass
# =============================================================================
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)
stopifnot("Ret" %in% names(RAWDATA))

.skew <- function(x) {
  x <- x[is.finite(x)]; n <- length(x)
  if (n < 60L) return(NA_real_)
  m <- mean(x); s <- sd(x)
  if (!is.finite(s) || s <= 0) return(NA_real_)
  mean((x - m)^3) / s^3
}

RAWDATA[, .ym := format(Date, "%Y-%m")]
.me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
RAWDATA[, .rs := {
  v <- rep(NA_real_, .N); mp <- which(Date %in% .me & LiqPass == TRUE)
  for (ix in mp) { lo <- ix - 251L; if (lo >= 1L) v[ix] <- .skew(Ret[lo:ix]) }
  v
}, by = Ticker]

FACTORS <- RAWDATA[is.finite(.rs), .(Date, Ticker, Score = -.rs)]   # low skew long (skew preference)
FACTORS[, N := pmax(5L, as.integer(ceiling(.N / 10))), by = Date]
RAWDATA[, c(".rs", ".ym") := NULL]
cat(sprintf("[fe_rskew] realized skewness (low long) | rows=%d dates=%d decile N=%d~%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            if (nrow(FACTORS)) min(FACTORS$N) else 0L, if (nrow(FACTORS)) max(FACTORS$N) else 0L))
