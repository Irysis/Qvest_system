# strategy_tilt_weights.R — STR_1715 production 가중 함수 추출 (도훈 mandate 2026-06-18)
#
# 출처: 04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/run_all.R (lines 137-187) verbatim.
# 목적: QEPM 후보 가중 A/B에서 "기존전략방법론" baseline을 *전략과 동일*하게 재현하기 위한 sourceable 모듈.
#   - linear_tilt_qd: rank 기반 선형 틸트(λ) + long-only cap.
#   - linear_tilt_to_penalty_qd: 위 틸트 + w_prev로 TOphi(φ) 블렌드(턴오버 패널티).
#   - normalize_long_only: lb/ub clip + 초과 재분배.
# 전략 production 파라미터: λ=1.5, φ=3, ub=0.20 (CRISIS regime 시 ub=0.10), MAX_NAMES=20.

normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1, max_iter = 50) {
  w[!is.finite(w)] <- 0
  w[w < lb] <- lb
  w[w > ub] <- ub
  s <- sum(w)
  if (s <= 1e-12) {
    n <- length(w)
    return(rep(target_sum / n, n))
  }
  w <- w * (target_sum / s)
  for (k in seq_len(max_iter)) {
    over <- w > ub + 1e-12
    if (!any(over)) break
    excess <- sum(w[over] - ub)
    w[over] <- ub
    free <- which(!over & w > lb + 1e-12)
    if (length(free) == 0) {
      w <- w * (target_sum / sum(w)); break
    }
    w[free] <- w[free] + excess * (w[free] / sum(w[free]))
  }
  w / sum(w) * target_sum
}

linear_tilt_qd <- function(alpha_t, lambda = 1.0, lb = 0, ub = 0.20) {
  N <- length(alpha_t)
  if (N <= 1) return(rep(1, N))
  r <- rank(alpha_t, ties.method = "average")
  centered <- (r - mean(r)) / (N - 1)
  w_raw <- pmax(1 + lambda * 2 * centered, 1e-6)
  w <- w_raw / sum(w_raw)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

linear_tilt_to_penalty_qd <- function(alpha_t, lambda = 1.5, w_prev = NULL,
                                      phi = 3.0, lb = 0, ub = 0.20) {
  w_tilt <- linear_tilt_qd(alpha_t, lambda = lambda, lb = lb, ub = ub)
  names(w_tilt) <- names(alpha_t)
  if (is.null(w_prev) || phi <= 0) return(w_tilt)
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev))
  wp[common] <- w_prev[common]
  dropped <- 1 - sum(wp)
  if (dropped > 0) wp <- wp + dropped * w_tilt
  if (sum(wp) > 0) wp <- wp / sum(wp)
  blend <- phi / (1 + phi)
  w_out <- blend * wp + (1 - blend) * w_tilt
  normalize_long_only(w_out, lb = lb, ub = ub, target_sum = 1)
}

cat("[strategy_tilt_weights.R] Loaded — linear_tilt_qd / linear_tilt_to_penalty_qd / normalize_long_only (STR_1715 production verbatim)\n")
