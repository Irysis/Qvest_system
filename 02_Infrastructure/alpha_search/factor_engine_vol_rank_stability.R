# =============================================================================
# factor_engine_vol_rank_stability.R
#
# 소스 논문: Halperin (2026) "Observable Matrix Dynamics of Stocks"
#   arXiv:2607.19005 — 변동성 순위(vol rank)를 Markov chain으로 분석.
#   핵심 발견: "The volatility chain is far more persistent, financial-sector
#   led, and is the only one to carry a weak, episodic arrow of time."
#
# 가설: 변동성 순위가 안정적인 종목 = Markov 상태 지속성 높음
#   → 예측 가능한 위험 구조 → 미래 수익률 예측력 가설.
#   논문은 분석 대상 유니버스(S&P500)에서 변동성 체인이 수익률 체인보다
#   훨씬 지속적이며 특히 금융 섹터가 선도함을 보임.
#   KR K200∪KQ150에서 cross-sectional 팩터로 전용: 순위 안정성 상위 매수.
#
# 팩터 정의:
#   vol_20d  = 주식별 20거래일 실현변동성 (Ret lag-1 기준, PIT-safe)
#   rank_pct = 월말 유동성 통과 유니버스 내 vol_20d 백분위 순위 (0=저변동, 1=고변동)
#   Score    = -std(rank_pct, trailing 12 months) per stock
#              높을수록 순위 안정적 → 매수 우선
#
# 방향 가설: 순위 안정성 자체가 예측력을 가진다면 방향은 양의 관계여야 하나,
#   저변동 안정 vs. 고변동 안정의 두 군이 혼합될 수 있음.
#   (run_alpha_search에서 양방향 테스트 의도, 현재 Score는 high=stable)
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
# shift(Ret, 1L): date t → Ret[t-1], rolling 20 = window [t-20, t-1]
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

# Score = -(순위 변동성): 높을수록 순위 안정적
.vol_me[, .Score := -rank_std_12m]

# ---- Step 5: FACTORS 조립 (유효 스코어 + 유동성 통과) -----------------------
FACTORS <- .vol_me[!is.na(.Score), .(Date, Ticker, Score = .Score)]

# ---- 임시 컬럼 정리 ---------------------------------------------------------
RAWDATA[, c(".ret_lag1", ".vol_20d", ".ym") := NULL]
rm(.vol_me)
gc(verbose = FALSE)

cat(sprintf(
  "[vol_rank_stability] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
  nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)
))
