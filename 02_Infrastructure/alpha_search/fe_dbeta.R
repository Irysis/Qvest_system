# =============================================================================
# fe_dbeta.R — Downside Beta (Ang, Chen & Xing 2006)
# =============================================================================
# 논문: Ang, Chen & Xing (2006) "Downside Risk", RFS.
#   하락장(rm<0) 베타 β⁻ = cov(ri,rm | rm<0)/var(rm | rm<0)가 높은 종목은
#   하방위험 보상으로 높은 기대수익 (cross-sectional premium). long high-β⁻.
#
# ★ 제1원칙(완전 복제) — 미명시값 보충(명시):
#   - β⁻ 추정 윈도우: rolling 252 거래일(약 1년, 논문 daily). 하락일 최소 20.
#   - 시그널: β⁻ (high = 매수, Ang premium 방향). decile long-only EW.
#   - 리밸 월간. 유니버스 K200∪KQ150. 기간 2005~.
#
# ===== PIT =====
#   - β⁻은 t(월말) 과거 252일만(과거 윈도우). 시장수익 rm = BM_Ret(동시점 단면 아님, 과거).
#   - 동일시점 순환참조 없음. NEGATE/FLIP 없음.
# RAWDATA columns: Date, Ticker, Ret, BM_Ret, LiqPass ...
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)
stopifnot(all(c("Ret", "BM_Ret") %in% names(RAWDATA)))

.dbeta <- function(ri, rm) {
  dn <- which(rm < 0 & is.finite(ri) & is.finite(rm))
  if (length(dn) < 20L) return(NA_real_)
  vr <- stats::var(rm[dn])
  if (!is.finite(vr) || vr <= 0) return(NA_real_)
  stats::cov(ri[dn], rm[dn]) / vr
}

RAWDATA[, .ym := format(Date, "%Y-%m")]
.me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

RAWDATA[, .db := {
  v  <- rep(NA_real_, .N)
  mp <- which(Date %in% .me & LiqPass == TRUE)
  for (ix in mp) {
    lo <- ix - 251L
    if (lo >= 1L) v[ix] <- .dbeta(Ret[lo:ix], BM_Ret[lo:ix])
  }
  v
}, by = Ticker]

FACTORS <- RAWDATA[is.finite(.db), .(Date, Ticker, Score = .db)]   # high β⁻ long (Ang premium)
FACTORS[, N := pmax(5L, as.integer(ceiling(.N / 10))), by = Date]

RAWDATA[, c(".db", ".ym") := NULL]
cat(sprintf("[fe_dbeta] Ang-Chen-Xing 2006 downside beta | rows=%d dates=%d decile N=%d~%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            if (nrow(FACTORS)) min(FACTORS$N) else 0L,
            if (nrow(FACTORS)) max(FACTORS$N) else 0L))
