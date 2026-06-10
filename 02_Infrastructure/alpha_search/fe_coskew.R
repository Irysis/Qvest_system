# =============================================================================
# fe_coskew.R — Coskewness (Harvey & Siddique 2000)
# =============================================================================
# 논문: Harvey & Siddique (2000) "Conditional Skewness in Asset Pricing Tests", JF.
#   시장수익 제곱에 대한 종목 동조(coskewness)가 음(-)인 종목(시장 급락 시 더 하락)은
#   위험 보상으로 높은 기대수익. long negative-coskewness decile.
#
# ★ 제1원칙 — 미명시값 보충(명시):
#   - standardized coskewness = E[ε_i·ε_m²] / (√E[ε_i²]·E[ε_m²]), rolling 252거래일(최소60).
#   - 시그널 = -coskew (낮을수록 매수, HS premium 방향). decile long-only EW. 월간. K200∪KQ150. 2005~.
# ===== PIT =====: 과거 252일만(과거 윈도우), rm=BM_Ret. 동일시점 순환 없음. NEGATE/FLIP 없음.
# RAWDATA columns: Date, Ticker, Ret, BM_Ret, LiqPass
# =============================================================================
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)
stopifnot(all(c("Ret", "BM_Ret") %in% names(RAWDATA)))

.coskew <- function(ri, rm) {
  ok <- is.finite(ri) & is.finite(rm); ri <- ri[ok]; rm <- rm[ok]
  if (length(ri) < 60L) return(NA_real_)
  em <- rm - mean(rm); ei <- ri - mean(ri)
  denom <- sqrt(mean(ei^2)) * mean(em^2)
  if (!is.finite(denom) || denom <= 0) return(NA_real_)
  mean(ei * em^2) / denom
}

RAWDATA[, .ym := format(Date, "%Y-%m")]
.me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
RAWDATA[, .cs := {
  v <- rep(NA_real_, .N); mp <- which(Date %in% .me & LiqPass == TRUE)
  for (ix in mp) { lo <- ix - 251L; if (lo >= 1L) v[ix] <- .coskew(Ret[lo:ix], BM_Ret[lo:ix]) }
  v
}, by = Ticker]

FACTORS <- RAWDATA[is.finite(.cs), .(Date, Ticker, Score = -.cs)]   # low(negative) coskew long
FACTORS[, N := pmax(5L, as.integer(ceiling(.N / 10))), by = Date]
RAWDATA[, c(".cs", ".ym") := NULL]
cat(sprintf("[fe_coskew] Harvey-Siddique 2000 | rows=%d dates=%d decile N=%d~%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            if (nrow(FACTORS)) min(FACTORS$N) else 0L, if (nrow(FACTORS)) max(FACTORS$N) else 0L))
