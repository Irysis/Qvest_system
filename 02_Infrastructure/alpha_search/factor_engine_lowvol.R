# =============================================================================
# factor_engine_lowvol.R — 저변동성 효과 (Low-Volatility Anomaly)
# 논문: Blitz, D. & van Vliet, P. (2007), "The Volatility Effect:
#       Lower Risk Without Lower Return", Journal of Portfolio Management 34(1).
# 가설: 과거 변동성이 낮은 종목이 위험조정수익에서 우수 (CAPM 예측에 반함).
#       → 저변동성 종목을 매수.
#
# 산출: FACTORS(Date, Ticker, Score), Score = -(과거 252일 실현변동성)  (낮을수록 우선)
# PIT: 변동성은 t-1까지의 과거 윈도우만 사용 (shift(Ret,1) 후 rolling, 동일시점 참조 금지).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 과거 252일 실현변동성 (t-1까지) -----------------------------------------
# E[r^2]-E[r]^2 분산식 + frollmean(C 구현)으로 252-window sd 근사 → 빠르고 PIT-safe.
RAWDATA[, .ret_lag := shift(Ret, 1L), by = Ticker]          # 당일 제외 (t-1까지)
RAWDATA[, .r2      := .ret_lag^2]
RAWDATA[, .m1      := frollmean(.ret_lag, 252L, align = "right"), by = Ticker]
RAWDATA[, .m2      := frollmean(.r2,      252L, align = "right"), by = Ticker]
RAWDATA[, .vol252  := sqrt(pmax(.m2 - .m1^2, 0))]
RAWDATA[, .Score   := -.vol252]                              # 저변동성 = 높은 Score

# ---- 월말 시그널 날짜 --------------------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

# ---- FACTORS 산출 (유동성 통과 + 유효·양의 변동성만) -------------------------
FACTORS <- RAWDATA[
  Date %in% .month_ends & LiqPass == TRUE & is.finite(.Score) & .vol252 > 0,
  .(Date, Ticker, Score = .Score)
]

# 임시컬럼 정리
RAWDATA[, c(".ret_lag", ".r2", ".m1", ".m2", ".vol252", ".Score", ".ym") := NULL]

cat(sprintf("[factor_engine_lowvol] FACTORS rows=%d | signal dates=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date)))
