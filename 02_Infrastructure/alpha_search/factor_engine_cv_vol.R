# =============================================================================
# factor_engine_cv_vol.R — CV_Vol: Coefficient of Variation of Daily Volume
# FQ-143 (2026-08-04 AS-20260804 신규 등재)
#
# Hypothesis (2607.01377 파생): 일별 거래량의 변동계수(CV = std/mean)가 낮은 종목이
# 유동성 불안정성 프리미엄이 낮아 더 높은 수익률을 보임.
# 신호 방향: LONG low-CV_Vol (안정적 거래량 = 유동성 예측 가능)
#
# PIT: 월말 시점에 직전 21거래일 Vol만 사용 (C1-safe, look-ahead 없음)
# EV check (2026-08-04): cor(CV_Vol, L13)=0.41, cor(CV_Vol, L16)=0.225 → NOVEL
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# Fast frollmean approach: O(n_total_rows) instead of O(n_tickers × n_months)
RAWDATA[, .vol := as.numeric(Vol)]
RAWDATA[, .vol_sq := .vol^2]

# Rolling 21d statistics (right-aligned: uses past 21 obs including current)
# PIT-safe: at month-end date t, uses Vol from days t-20 through t
RAWDATA[, .roll_mean   := frollmean(.vol,    n = 21L, align = "right", fill = NA), by = Ticker]
RAWDATA[, .roll_meansq := frollmean(.vol_sq, n = 21L, align = "right", fill = NA), by = Ticker]

# CV = std / mean = sqrt(E[X^2] - E[X]^2) / E[X]
RAWDATA[, .roll_var := pmax(.roll_meansq - .roll_mean^2, 0)]
RAWDATA[, .CV_Vol   := sqrt(.roll_var) / .roll_mean]

# Score = -CV_Vol (lower CV → higher score = prefer low-uncertainty stocks)
RAWDATA[, .Score := -.CV_Vol]

# Month-end signal dates
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

FACTORS <- RAWDATA[
  Date %in% .month_ends & LiqPass == TRUE & is.finite(.Score),
  .(Date, Ticker, Score = .Score)
]

# Cleanup temp columns
RAWDATA[, c(".vol", ".vol_sq", ".roll_mean", ".roll_meansq",
            ".roll_var", ".CV_Vol", ".Score", ".ym") := NULL]

cat(sprintf("[factor_engine_cv_vol] FACTORS rows=%d | signal dates=%d | avg per month=%.0f\n",
    nrow(FACTORS), uniqueN(FACTORS$Date), nrow(FACTORS)/max(1, uniqueN(FACTORS$Date))))
