# =============================================================================
# factor_engine_vol_rank_markov_persistence.R
#
# 소스 논문: Halperin (2026) "Are Three Matrices All You Need To Beat the Market?"
#   arXiv:2607.27461 — §2.1 변동성 Markov chain 전이행렬 (P^V)
#
# 가설 (tier-2 recheck / factor_id: Vol_Rank_Markov_Persistence):
#   월말 trailing 21d 실현변동성 → 횡단면 10분위 →
#   rolling 36M pooled P^V 추정 →
#   π^V_i = P^V[decile_i, {1,2}] (최저변동 2분위 도달확률) →
#   상위 25종 EW 월간 리밸 15bps
#
# 차별점 vs 기존 테스트:
#   - vol_rank_stability (2607.19005): 12M rolling std(rank_pct) = 순위 안정성 스칼라
#   - C_VolRankStability_3M (2607.27461 prior): 3M rank 변화량
#   - 본 신호: 36M Markov 전이행렬에서 추출한 '저변동 도달 확률' — 현재 분위에서
#     다음달 분위 {1,2}로 전이할 사후확률. 분위 1·2 모두 포함 (논문 score s_i = p^V_i)
#
# PIT 체크:
#   C1: vol21d = shift(Ret,1) → rolling 21일 → 전기간 통계 X
#   C2: 전이행렬 추정에 Date < tgt_date 조건 → 미래 decile_next 배제
#   C10: LiqPass 필터 적용
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- Step 1: Trailing 21-day realized vol (lag-1 PIT) ----------------------
RAWDATA[, .ret_lag := shift(Ret, 1L), by = Ticker]
RAWDATA[, .vol21d := zoo::rollapply(
  .ret_lag, width = 21L, FUN = sd, fill = NA_real_, align = "right"
), by = Ticker]

# ---- Step 2: Month-end extraction + monthly vol snapshot --------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends_set <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

.vol_mon <- RAWDATA[
  Date %in% .month_ends_set & LiqPass == TRUE & !is.na(.vol21d),
  .(Date, Ticker, vol21d = .vol21d)
]
setorder(.vol_mon, Date, Ticker)

# ---- Step 3: Monthly cross-sectional decile rank (1=lowest vol = best) -----
# Paper: c_i(t) = ceil(K * rk_i(t) / N), K=10, rank1 = lowest vol
.vol_mon[, n_valid := .N, by = Date]
.vol_mon[n_valid >= 10, decile := {
  rk <- frank(vol21d, ties.method = "average", na.last = "keep")
  as.integer(ceiling(10L * rk / .N))
}, by = Date]
.vol_mon <- .vol_mon[!is.na(decile) & decile >= 1L & decile <= 10L]

# ---- Step 4: Build one-step transitions (Date → Date+1M) -------------------
setorder(.vol_mon, Ticker, Date)
.vol_mon[, decile_next := shift(decile, -1L),  by = Ticker]
.vol_mon[, date_next   := shift(Date,   -1L),  by = Ticker]

# Keep only valid one-step transitions (20~45 day gap = consecutive month)
.vol_mon[, .gap := as.numeric(date_next - Date)]
.trans_all <- .vol_mon[!is.na(decile_next) & .gap >= 20 & .gap <= 45,
                       .(Date, Ticker, decile_from = decile, decile_to = decile_next)]
setorder(.trans_all, Date)

# ---- Step 5: Rolling 36M P^V + signal per signal date ----------------------
# 36개월 ≈ 1100일 (윤년 포함 안전 상한)
WINDOW_DAYS <- 1100L
all_sig_dates <- sort(unique(.vol_mon$Date))

.sig_list <- vector("list", length(all_sig_dates))

for (i in seq_along(all_sig_dates)) {
  T <- all_sig_dates[[i]]

  # PIT: transitions that STARTED before T (decile_next is known at T)
  # Last valid transition: Date = T-1M → decile_next = decile(T) (known at T)
  win_start <- T - WINDOW_DAYS
  .tw <- .trans_all[Date >= win_start & Date < T]

  # Need minimum 50 transitions for P^V to be meaningful
  if (nrow(.tw) < 50L) next

  # Count transitions (decile_from, decile_to) — aggregate across all stocks+months
  .cnt <- .tw[, .N, by = .(decile_from, decile_to)]

  # Build 10x10 P^V with Laplace additive smoothing (pseudocount = 0.5 per cell)
  K <- 10L
  P_V <- matrix(0.5, nrow = K, ncol = K)
  # Add observed counts
  for (r in seq_len(nrow(.cnt))) {
    a <- .cnt$decile_from[[r]]
    b <- .cnt$decile_to[[r]]
    if (a >= 1L && a <= K && b >= 1L && b <= K) {
      P_V[a, b] <- P_V[a, b] + .cnt$N[[r]]
    }
  }
  # Row-normalize → transition probabilities
  P_V <- P_V / rowSums(P_V)

  # Current stocks at signal date T (with valid decile)
  .now <- .vol_mon[Date == T & !is.na(decile), .(Ticker, decile)]
  if (nrow(.now) == 0L) next

  # Signal: π^V_i = P^V[decile_i, 1] + P^V[decile_i, 2]
  # (probability of reaching lowest-vol 2 deciles next month)
  .now[, Score := P_V[cbind(decile, 1L)] + P_V[cbind(decile, 2L)]]
  .now[, Date := T]

  .sig_list[[i]] <- .now[!is.na(Score), .(Date, Ticker, Score)]
}

FACTORS <- rbindlist(.sig_list, use.names = TRUE, fill = TRUE)
FACTORS <- FACTORS[!is.na(Score)]

# ---- Cleanup ---------------------------------------------------------------
RAWDATA[, c(".ret_lag", ".vol21d", ".ym") := NULL]
rm(.vol_mon, .trans_all, .sig_list)
suppressWarnings(rm(.tw, .cnt, .now, P_V))
gc(verbose = FALSE)

cat(sprintf(
  "[Vol_Rank_Markov_Persistence] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
  nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)
))
