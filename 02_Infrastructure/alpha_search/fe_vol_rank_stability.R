# =============================================================================
# fe_vol_rank_stability.R — Volatility Rank Stability Factor
# =============================================================================
# 논문: Halperin (2026-07-21) "Observable Matrix Dynamics of Stocks"
#       arxiv:2607.19005
#       핵심 발견: 주식 변동성 순위를 Markov chain으로 모델링하면 vol chain이
#       "far more persistent, financial-sector led, arrow of time" 특성.
#       return chain보다 volatility chain이 훨씬 더 안정적.
#
# ★ 팩터 정의 (논문 착안 — KR long-only 사상):
#   - 20일 실현변동성 rank의 시계열 안정성 측정
#   - 순위가 안정적으로 낮은(저변동성 지속) 종목 long → 방어적 특성
#   Step 1: 매일 각 종목의 20일 실현변동성 계산 (t-1까지 — PIT)
#   Step 2: 매일 유니버스 내 변동성 백분위 순위 (0~1) 계산
#   Step 3: 월말 기준 과거 252 거래일 윈도우의 순위 표준편차 계산
#   Factor Score = -(252일 순위 표준편차) → 높을수록 순위 안정적
#
# ===== PIT 준수 =====
#   - 20일 변동성: shift(.ret, 1L)로 t-1까지 수익률 사용 (당일 미포함 — C2 안전)
#   - frollmean 252일 rolling: 동일 시점 순환참조 없음 (C1/C3 안전)
#   - 백분위 순위: 동일 날짜 횡단면 (동시점 순환참조 없음 — C2 정합)
#   - 월말 신호: 해당 월 말까지 축적된 과거 252 거래일 정보만 사용 (C3 안전)
#   - NEGATE/FLIP 수동 부호반전 없음 (C13 안전 — Score = -std가 신호 방향 정의)
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- Step 1: 20일 실현변동성 (t-1까지 수익률 기반, PIT-safe) ----
# .ret = 전일 대비 수익률 (당일 종가 / 전일 종가 - 1)
# shift(.ret, 1L) = t-1일까지만 — 당일 수익률 배제 (C2 준수)
RAWDATA[, .ret  := Close / shift(Close, 1L) - 1, by = Ticker]
RAWDATA[, .m1   := frollmean(shift(.ret, 1L),      20L, align = "right"), by = Ticker]
RAWDATA[, .m2   := frollmean(shift(.ret, 1L)^2L,   20L, align = "right"), by = Ticker]
RAWDATA[, .rvol := sqrt(pmax(.m2 - .m1^2L, 0)), by = Ticker]  # 20일 실현변동성

# ---- Step 2: 횡단면 변동성 백분위 순위 (매일, 0~1) ----
# 동일 날짜 유효 종목들 사이의 순위 → 정보 비대칭 없음 (C2 안전)
RAWDATA[
  is.finite(.rvol),
  .rank_pct := rank(.rvol, ties.method = "average") / .N,
  by = Date
]
# rvol NA/Inf 행은 rank_pct도 NA로 유지 (결측 처리)
RAWDATA[!is.finite(.rvol), .rank_pct := NA_real_]

# ---- Step 3: 252 거래일 윈도우의 순위 시계열 표준편차 ----
# frollmean + sqrt(Var) 방식으로 rolling std 계산 (PIT-safe rolling)
RAWDATA[, .rm1   := frollmean(.rank_pct,    252L, align = "right"), by = Ticker]
RAWDATA[, .rm2   := frollmean(.rank_pct^2L, 252L, align = "right"), by = Ticker]
RAWDATA[, .rstd  := sqrt(pmax(.rm2 - .rm1^2L, 0)), by = Ticker]

# Factor Score: 순위 표준편차의 역(음수) → 높을수록 순위 안정적
RAWDATA[, .Score := -.rstd]

# ---- 월말 시그널 날짜 (각 달 마지막 거래일) ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)

# ---- FACTORS 산출: 유니버스 멤버십 + 유동성 + 유효 스코어 ----
# universe="K200_KQ150" 필터 (fe 내부 적용 — 횡단면 순위 분모 정합)
.mem <- RAWDATA[
  Date %in% .month_ends &
    (K200 == TRUE | KQ150 == TRUE) &
    is.finite(.Score),
  .(Date, Ticker, Score = .Score)
]
FACTORS <- copy(.mem)

# ---- 정리: RAWDATA 임시 컬럼 제거 ----
RAWDATA[, c(".ret", ".m1", ".m2", ".rvol", ".rank_pct",
            ".rm1", ".rm2", ".rstd", ".Score", ".ym") := NULL]

cat(sprintf(
  "[fe_vol_rank_stability] Vol Rank Stability (252d rank-std) | rows=%d | months=%d\n",
  nrow(FACTORS), uniqueN(FACTORS$Date)
))
