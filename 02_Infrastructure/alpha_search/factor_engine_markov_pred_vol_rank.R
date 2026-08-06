# =============================================================================
# factor_engine_markov_pred_vol_rank.R
#
# 소스 논문: Halperin (2026) "Are Three Matrices All You Need To Beat the Market?"
#   arXiv:2607.27461 — §2.1 변동성 Markov chain 전이행렬 (P^V)
#
# 팩터 ID: Markov_PredVolRank
# 신호 정의:
#   월말 trailing 21d 실현변동성(RMS) → 횡단면 10분위(1=최저, 10=최고) →
#   rolling 36M 전이행렬 P^V (10×10, Laplace smoothing) →
#   기대 다음 분위: E_next_i = sum_j(j * P[decile_i, j])  for j=1..10
#   Score = -E_next_i  (낮은 예측 분위 = 높은 Score = 매수 우선)
#
# vs 기존(Vol_Rank_Markov_Persistence 2026-08-04):
#   기존: Score = P^V[i,1] + P^V[i,2]  (분위 1·2 도달 확률합 = 저변동 유지 확률)
#   본 신호: Score = -E[next decile]   (전이분포 전체 가중평균 — 추후 분위 기대값)
#   차이: 분위 3~10으로 가는 질량을 분위별로 차등 가중 → 미묘한 vol 회귀 vs 지속 구분
#   논문 구현: 도훈 지시의 step 4~5 수식 (E_next = sum_j j*P[i,j])
#
# PIT 체크:
#   C1: vol21d = sqrt(frollmean(Ret^2, 21)) — rolling window, 전기간 통계 금지
#   C2: 전이행렬 추정은 Date < tgt_date 인 과거 전이만 (미래 decile_next 배제)
#   C3: 신호 날짜 T = 월말 (장 종료 후 확정); 다음달 보유 수익에만 적용
#   C10: LiqPass == TRUE 필터 적용
#   shift 방향: Ret에 lag-1 선적용 (C2 — 일별 미래 수익 참조 방지)
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- Step 1: Trailing 21-day realized vol (RMS, lag-1 PIT) ------------------
# 논문 §2.1: realized_vol_i = sqrt(mean(Ret_i^2, trailing 21일))
# PIT: Ret는 당일 장중 확정 — shift(1) 선적용으로 당일 Ret 포함 금지
# frollmean(x^2, 21) 은 rolling mean이므로 C1 준수
RAWDATA[, .ret_lag := shift(Ret, 1L), by = Ticker]
RAWDATA[, .vol21d_rms := sqrt(frollmean(.ret_lag^2, n = 21L, fill = NA_real_,
                                         align = "right", na.rm = FALSE)),
        by = Ticker]

# ---- Step 2: 월말 날짜 추출 + 월별 vol 스냅샷 --------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends_set <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

.vol_mon <- RAWDATA[
  Date %in% .month_ends_set & LiqPass == TRUE & !is.na(.vol21d_rms),
  .(Date, Ticker, vol21d = .vol21d_rms)
]
setorder(.vol_mon, Date, Ticker)

# ---- Step 3: 횡단면 10분위 랭킹 (1=최저변동성) --------------------------------
# 논문 Eq.(3): c_i(t) = ceil(10 * rank_i / N), rank 1 = lowest vol
.vol_mon[, n_valid := .N, by = Date]
.vol_mon[n_valid >= 10, decile := {
  rk <- frank(vol21d, ties.method = "average", na.last = "keep")
  as.integer(ceiling(10L * rk / .N))
}, by = Date]
.vol_mon <- .vol_mon[!is.na(decile) & decile >= 1L & decile <= 10L]

# ---- Step 4: 전이 쌍 구성 (Date → Date+1M) -----------------------------------
# PIT: decile_next는 다음 달 월말에 확정되는 값
#       → 신호 날짜 T에서 .trans_all[Date < T] 조건으로 접근 금지
#       단, 전이 쌍 정의 자체에서는 (Date, decile) → (Date+1M, decile_next)를
#       구성하는 것이므로 PIT 위반 아님 — 추정 필터에서 Date < T 로 차단됨
setorder(.vol_mon, Ticker, Date)
.vol_mon[, decile_next := shift(decile, -1L), by = Ticker]
.vol_mon[, date_next   := shift(Date,   -1L), by = Ticker]

# 연속월 전이만 (20~45일 간격)
.vol_mon[, .gap := as.numeric(date_next - Date)]
.trans_all <- .vol_mon[!is.na(decile_next) & .gap >= 20L & .gap <= 45L,
                       .(Date, Ticker, decile_from = decile, decile_to = decile_next)]
setorder(.trans_all, Date)

# ---- Step 5: Rolling 36M P^V + 기대 다음 분위 계산 --------------------------
# 36개월 ≈ 1100일 (윤년·장기월 포함 안전 상한)
WINDOW_DAYS <- 1100L
K <- 10L
j_vec <- seq_len(K)  # 분위 가중: 1..10

all_sig_dates <- sort(unique(.vol_mon$Date))

.sig_list <- vector("list", length(all_sig_dates))

for (i in seq_along(all_sig_dates)) {
  T <- all_sig_dates[[i]]

  # PIT: 신호날 T 이전에 시작한(Date < T) 전이만 사용
  # (Date==T인 전이의 decile_to는 T 이후 확정 → 배제)
  win_start <- T - WINDOW_DAYS
  .tw <- .trans_all[Date >= win_start & Date < T]

  # 최소 12개월치 데이터 미만이면 NA (최소 window 조건)
  n_months_approx <- as.numeric(T - win_start) / 30.5
  if (n_months_approx < 12 || nrow(.tw) < 30L) next

  # 10×10 전이 카운트 (Laplace smoothing pseudocount = 1 per cell — 지시서 명시)
  .cnt <- .tw[, .N, by = .(decile_from, decile_to)]

  P_V <- matrix(1.0, nrow = K, ncol = K)  # pseudocount=1 (Laplace)
  for (r in seq_len(nrow(.cnt))) {
    a <- .cnt$decile_from[[r]]
    b <- .cnt$decile_to[[r]]
    if (a >= 1L && a <= K && b >= 1L && b <= K) {
      P_V[a, b] <- P_V[a, b] + .cnt$N[[r]]
    }
  }
  # 행 정규화 → 전이확률
  P_V <- P_V / rowSums(P_V)

  # 각 행의 기대 다음 분위: E_next[i] = sum_j(j * P_V[i,j])
  E_next <- as.numeric(P_V %*% j_vec)  # 길이 K 벡터

  # 현재 신호 날짜 T의 종목별 분위
  .now <- .vol_mon[Date == T & !is.na(decile), .(Ticker, decile)]
  if (nrow(.now) == 0L) next

  # Score = -E_next[decile_i]  (낮은 기대 분위 = 높은 스코어 = 매수 우선)
  .now[, Score := -E_next[decile]]
  .now[, Date := T]

  .sig_list[[i]] <- .now[!is.na(Score), .(Date, Ticker, Score)]
}

FACTORS <- rbindlist(.sig_list, use.names = TRUE, fill = TRUE)
FACTORS <- FACTORS[!is.na(Score)]

# ---- 정리 -------------------------------------------------------------------
RAWDATA[, c(".ret_lag", ".vol21d_rms", ".ym") := NULL]
rm(.vol_mon, .trans_all, .sig_list, .cnt, P_V, E_next, j_vec)
suppressWarnings(rm(.tw, .now))
gc(verbose = FALSE)

cat(sprintf(
  "[Markov_PredVolRank] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
  nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)
))
