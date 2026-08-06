# =============================================================================
# factor_engine_vol_rank_reverse.R — 변동성 순위 역방향 (FQ-092)
# =============================================================================
# 가설: vol rank 상승(고변동성 모멘텀) 종목 long — C_VolRankStability_3M 역방향
#   C_VolRankStability_3M: Score = -rank_std_12m (QUARANTINE: SR 0.275, IR -0.234)
#   FQ-092: Score = +rank_std_12m (변동성 순위 불안정·상승 종목 선택)
#   방향 근거: 정방향 실증 실패(arXiv:2607.27461 2-hits negative) →
#             역방향이 KR에서 양성인지 경험적으로 검증.
#
# 소스 논문: 2607.27461 (Three Matrices — Observable Matrix Dynamics for Portfolio Optimization)
#   vol rank chain persistence 분석에서 분위 상승 종목의 수익률 프리미엄 존재 여부 미명시.
#   역방향 가설은 prior failure로부터 도출된 next_probe (FQ-092).
#
# PIT 체크리스트:
#   C1: vol_20d = lag-1 rolling 20일 std → 전기간 통계 X
#   C2: shift(Ret, 1L) 사용 → [t-20, t-1] window (동일시점 순환 X)
#   C10: LiqPass (AvgTV20 >= 2e8) 사용
#   월말 rank_pct 계산도 해당 월말 이전 vol만 사용 → PIT OK
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- Step 1: 20거래일 실현변동성 (lag-1 PIT) --------------------------------
RAWDATA[, .ret_lag1 := shift(Ret, 1L), by = Ticker]
RAWDATA[, .vol_20d := zoo::rollapply(
  .ret_lag1, width = 20L, FUN = sd, fill = NA_real_, align = "right"
), by = Ticker]

# ---- Step 2: 월말 날짜 추출 --------------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends_set <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

# ---- Step 3: 월말 유동성 통과 종목 vol 순위 계산 ----------------------------
.vol_me <- RAWDATA[
  Date %in% .month_ends_set & LiqPass == TRUE & !is.na(.vol_20d),
  .(Date, Ticker, vol_20d = .vol_20d)
]

# 월말 cross-sectional 백분위 순위 (0~1, 낮을수록 저변동)
.vol_me[, rank_pct := frank(vol_20d, na.last = "keep", ties.method = "average") / .N,
        by = Date]

# ---- Step 4: 12개월 rolling std of rank_pct per stock ----------------------
setorder(.vol_me, Ticker, Date)
.vol_me[, rank_std_12m := zoo::rollapply(
  rank_pct, width = 12L, FUN = sd, fill = NA_real_, align = "right"
), by = Ticker]

# Score = +rank_std_12m: 변동성 순위 불안정·상승 종목 선택 (FQ-092 역방향)
# cf. factor_engine_vol_rank_stability.R: Score = -rank_std_12m (안정 = 높은 점수)
.vol_me[, .Score := rank_std_12m]

# ---- Step 5: FACTORS 조립 (유효 스코어 + 유동성 통과) -----------------------
FACTORS <- .vol_me[!is.na(.Score), .(Date, Ticker, Score = .Score)]

# ---- 임시 컬럼 정리 ---------------------------------------------------------
RAWDATA[, c(".ret_lag1", ".vol_20d", ".ym") := NULL]
rm(.vol_me)
gc(verbose = FALSE)

cat(sprintf(
  "[vol_rank_reverse] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
  nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)
))
