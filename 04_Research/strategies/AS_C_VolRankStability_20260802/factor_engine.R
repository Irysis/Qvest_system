# =============================================================================
# factor_engine.R — C_VolRankStability_3M
# 출처: Halperin (2026), "Are Three Matrices All You Need To Beat the Market?"
#       arxiv:2607.27461
#
# 핵심 논문 발견:
#   - vol rank(변동성 순위)는 1개월 선행 예측 가능 (Markov 체인 지속성)
#   - return rank는 예측 불가
#   - vol rank 변화를 long-only 신호로 사용 가능
#
# 팩터 정의 (C_VolRankStability_3M):
#   - 월말 t 기준 과거 252 거래일 일별 수익률 → 실현 연간변동성
#   - 유니버스 내 횡단면 랭크 (1=최저변동성, N=최고변동성)
#   - Signal = -(vol_rank_t - vol_rank_{t-3})
#     양수 = 3개월 전보다 상대 변동성 순위가 낮아짐 = 변동성 개선 = 매수
#
# PIT 준수:
#   - t월 시그널은 t-1월 말까지의 일별 수익률만 사용 (shift(Ret,1) via 월간 lag)
#   - 월간 패널로 변환 후 3개월 lag 적용 (shift(vol_rank, 3L))
#   - C1: rolling 252일 윈도우만 (전표본 통계 금지)
#   - C2: 당월 수익률 사용 금지
#   - C10: 유동성 필터는 t-1 데이터 기준 (LiqPass 이미 t-1 PIT 적용됨)
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- Step 1: 월별 실현변동성 계산 (일별 Ret → rolling 252일 std) ----------
# RAWDATA의 Ret 컬럼은 당일 종가 기반 수익률 (t일 Ret = Pt/Pt-1 - 1)
# PIT: 월말 t 리밸 시 shift(1) 하여 전월 말 기준 252일 윈도우 사용
# data_table_shift_convention: shift(n) = n행 과거 (lag n)

# 일별 수익률의 252일 rolling std (annualized)
# frollapply: 최소 윈도우 126일(약 6개월) 충족 시만 유효
RAWDATA[, .rvol := frollapply(Ret, n = 252L, FUN = function(x) {
  if (sum(is.finite(x)) < 126L) return(NA_real_)
  sd(x, na.rm = TRUE) * sqrt(252)
}, align = "right", fill = NA), by = Ticker]

# ---- Step 2: 월말 시그널 날짜 추출 ------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym][, Date]

# ---- Step 3: 월별 패널 생성 (월말 시점의 실현변동성) ------------------------
# PIT lag=1: 리밸런싱은 다음달 첫날 → 월말 데이터로 신호 생성 후
# run_monthly_simulation이 내부에서 1개월 lag 적용함
# 여기서는 월말 .rvol 값을 사용 (이미 252일 과거 데이터 기반)

.monthly <- RAWDATA[
  Date %in% .month_ends & LiqPass == TRUE & is.finite(.rvol),
  .(Date, Ticker, rvol = .rvol)
]
setorder(.monthly, Date, Ticker)

# ---- Step 4: 유니버스 내 횡단면 랭크 (낮을수록 = 저변동성) -----------------
# rank(): 동점 처리 "average", na.last=TRUE (NA는 최하위)
.monthly[, vol_rank := rank(rvol, ties.method = "average", na.last = TRUE),
         by = Date]

# ---- Step 5: 3개월 전 랭크 (PIT: 과거 lag=3) --------------------------------
# shift(3L) = 3개월 전 vol_rank (by Ticker, 시계열)
setorder(.monthly, Ticker, Date)
.monthly[, vol_rank_lag3 := shift(vol_rank, n = 3L, type = "lag"), by = Ticker]

# ---- Step 6: 신호 계산 -------------------------------------------------------
# Signal = -(vol_rank_t - vol_rank_lag3)
# 양수 = 3개월 전보다 순위가 낮아짐 = 상대 변동성 개선 = 매수
.monthly[, .Score := -(vol_rank - vol_rank_lag3)]

# ---- Step 7: FACTORS 산출 ---------------------------------------------------
FACTORS <- .monthly[
  is.finite(.Score) & !is.na(vol_rank_lag3),
  .(Date, Ticker, Score = .Score)
]

# 정리
RAWDATA[, c(".rvol", ".ym") := NULL]
rm(.monthly, .month_ends)

cat(sprintf("[factor_engine] C_VolRankStability_3M | rows=%d | dates=%d | tickers=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
cat(sprintf("[factor_engine] Score 분포: min=%.1f, mean=%.1f, max=%.1f\n",
            min(FACTORS$Score, na.rm=TRUE),
            mean(FACTORS$Score, na.rm=TRUE),
            max(FACTORS$Score, na.rm=TRUE)))
