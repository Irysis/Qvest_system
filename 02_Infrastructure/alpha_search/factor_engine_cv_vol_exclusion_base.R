# =============================================================================
# factor_engine_cv_vol_exclusion_base.R
# FQ-150: CV_Vol exclusion filter baseline — 필터 없는 EW uniform
#
# 목적: exclusion filter 측정의 base case.
#   CV_Vol 필터 없이, 유동성 통과 K200∪KQ150 유니버스 전체에서 uniform score(=EW).
#   이 결과를 10pct/20pct exclusion 결과와 비교해 ΔIR 방향 확인.
#
# Score: uniform 1.0 (EW, 필터 효과 측정을 위한 순수 base)
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 월말 시그널 날짜 추출 ---------------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

# ---- FACTORS: 유동성 통과 종목 전체, uniform score --------------------------
FACTORS <- RAWDATA[
  Date %in% .month_ends & LiqPass == TRUE,
  .(Date, Ticker, Score = 1.0)
]

# 정리
RAWDATA[, ".ym" := NULL]

cat(sprintf("[cv_vol_excl_base] FACTORS rows=%d | signal dates=%d | avg/month=%.0f\n",
    nrow(FACTORS), uniqueN(FACTORS$Date), nrow(FACTORS) / max(1, uniqueN(FACTORS$Date))))
