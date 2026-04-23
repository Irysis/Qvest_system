#==============================================================================
# QEPM Mean-Variance Optimizer — v2.1 (v6.1 Grinold Breadth Enforcement)
# 2026-04-23 v1.0 정통 MVO 복원
# 2026-04-24 v2.0 — Confidence-aware + ForecastUncertaintyPenalty
# 2026-04-24 v2.1 — min_names + HHI_cap + Alpha winsorization (Task #26, L-192)
#
# 목적함수 (v2.0):
#   max x'α̃ - (λ/2) x'Σx - φ·TC(x) - ψ·FU(x, c)
#   where α̃_i = c_i · α̂_i (confidence scaled)
#         FU(x, c) = Σ_i x_i² (1-c_i)² (low confidence 집중 penalty)
#   subject to 1'x = 1 (absolute) or 1'x = 0 (active)
#
# v6.1 R4 개선:
#   - Alpha confidence가 weight 결정에 수학적 반영
#   - 불안정 alpha (낮은 c)에는 집중 penalty
#
# v6.1 Task #26 (L-192 Remediation):
#   - min_names: Grinold IR = IC × √breadth 강화 (≥15 종목)
#   - hhi_cap:   Σ w_i² ≤ 0.10 (집중 방지)
#   - bounds:    default 0.20 → 0.10 (per-name 상한 축소)
#   - winsor:    alpha ±2σ clip (outlier 집중 방지)
#==============================================================================

suppressPackageStartupMessages({
  library(quadprog)
  library(data.table)
})

# ─── Alpha Winsorization Helper ───────────────────────────
# alpha z-score 계산 후 |z| > winsor 이면 sign(z) * winsor * sd + mean 로 clip.
# 전체 cross-section 기준.
.winsorize_alpha <- function(alpha_vec, winsor = 2.0) {
  if (is.na(winsor) || is.null(winsor) || winsor <= 0) return(alpha_vec)
  mu <- mean(alpha_vec, na.rm = TRUE)
  sd_ <- stats::sd(alpha_vec, na.rm = TRUE)
  if (!is.finite(sd_) || sd_ < 1e-12) return(alpha_vec)
  z <- (alpha_vec - mu) / sd_
  over <- !is.na(z) & abs(z) > winsor
  if (any(over)) {
    alpha_vec[over] <- sign(z[over]) * winsor * sd_ + mu
  }
  alpha_vec
}

# ─── HHI Projection Helper ─────────────────────────────────
# HHI = sum(w^2). Cap 초과 시 top weight 0.01 감소 → 나머지 non-cap 종목에
# 균등 재분배 → HHI 재계산. 수렴 혹은 max_iter 도달까지 반복.
# long-only + bounds + 합=target_sum 유지.
.project_hhi <- function(w,
                          cap = 0.10,
                          bounds = c(0, 0.10),
                          target_sum = 1,
                          step = 0.01,
                          max_iter = 500,
                          tol = 1e-6) {
  w <- as.numeric(w)
  N <- length(w)
  if (N == 0) return(w)

  # Guard: lower bound * N > target_sum 이면 infeasible → early return
  if (bounds[1] * N - target_sum > tol) return(w)

  hhi <- sum(w^2)
  iter <- 0
  while (hhi > cap + tol && iter < max_iter) {
    iter <- iter + 1
    # 제일 큰 weight (bounds[1] 초과, 즉 감축 가능) 선택
    reducible <- w > bounds[1] + tol
    if (!any(reducible)) break
    top_idx <- which.max(w * reducible)

    # 감축 가능량
    dec <- min(step, w[top_idx] - bounds[1])
    if (dec <= tol) break

    w[top_idx] <- w[top_idx] - dec

    # 나머지 종목(상한 여유 있는)에 균등 분배
    absorber <- which(w < bounds[2] - tol)
    absorber <- setdiff(absorber, top_idx)
    if (length(absorber) == 0) break

    # 각 absorber에 배분 시 상한 고려 (iterative fill)
    remaining <- dec
    absorber_order <- absorber[order(w[absorber])]  # 작은 weight 우선 fill
    for (ix in absorber_order) {
      if (remaining <= tol) break
      room <- bounds[2] - w[ix]
      add_ <- min(room, remaining / max(1, length(which(absorber_order == ix | absorber_order > ix))))
      # simple equal split → 남은 건 다음 iteration
      add_ <- min(room, remaining)
      add_ <- add_ / max(1, sum(absorber_order %in% absorber_order[seq(match(ix, absorber_order), length(absorber_order))]))
      add_ <- min(room, remaining)
      # 단순 greedy fill (복잡도 회피)
      put_ <- min(room, remaining)
      w[ix] <- w[ix] + put_
      remaining <- remaining - put_
    }

    # 합 재조정 (미세 오차 보정)
    s <- sum(w)
    if (abs(s - target_sum) > tol) {
      scale <- target_sum / s
      w <- w * scale
      # 상한 재clip
      over_cap <- w > bounds[2]
      if (any(over_cap)) {
        excess <- sum(w[over_cap] - bounds[2])
        w[over_cap] <- bounds[2]
        under_cap <- which(w < bounds[2] - tol)
        if (length(under_cap) > 0) {
          w[under_cap] <- w[under_cap] + excess / length(under_cap)
        }
      }
      # 하한 clip
      w <- pmax(w, bounds[1])
    }

    hhi <- sum(w^2)
  }

  list(w = w, hhi = hhi, iter = iter, converged = hhi <= cap + tol)
}

# ─── MVO Confidence-aware 구현 (v2.1) ────────────────────
# Inputs:
#   alpha: named vector (Ticker → expected active return)
#   confidence: named vector (Ticker → confidence [0,1]), optional
#   cov_matrix: symmetric PD matrix (Ticker × Ticker)
#   lambda: risk-aversion (default 1.0)
#   psi: forecast uncertainty penalty (default 0.3; 0 = disable)
#   bounds: c(min_w, max_w) = c(0, 0.10)  (v2.1: 0.20→0.10)
#   max_names: hard cap (default 20)
#   min_names: breadth 하한 (default 15L; NA 시 disable)
#   hhi_cap: HHI 상한 (default 0.10; NA 시 disable)
#   alpha_winsor: alpha z-score clip (default 2.0; NA 시 disable)
#   current_weights: named vector (for turnover penalty)
#   turnover_penalty: φ (default 0.0)
#   active: TRUE = active (Σw=0) / FALSE = absolute (Σw=1)
#
# v6.1 R4: confidence NULL이면 1.0으로 취급 (backward compat)
# v6.1 Task#26: min_names + hhi_cap + alpha_winsor 신규 (L-192)
mvo_weights <- function(alpha,
                         cov_matrix,
                         confidence = NULL,
                         lambda = 1.0,
                         psi = 0.3,
                         bounds = c(0, 0.10),
                         max_names = 20,
                         min_names = 15L,
                         hhi_cap = 0.10,
                         alpha_winsor = 2.0,
                         current_weights = NULL,
                         turnover_penalty = 0.0,
                         active = FALSE) {

  # Input 검증
  if (!is.numeric(alpha) || is.null(names(alpha))) {
    stop("[mvo_weights] alpha must be named numeric vector")
  }
  if (!is.matrix(cov_matrix) || nrow(cov_matrix) != ncol(cov_matrix)) {
    stop("[mvo_weights] cov_matrix must be square")
  }
  if (length(bounds) != 2 || bounds[1] > bounds[2]) {
    stop("[mvo_weights] bounds invalid")
  }

  # Universe 정합 (alpha와 cov 종목 일치)
  common <- intersect(names(alpha), rownames(cov_matrix))
  if (length(common) == 0) {
    stop("[mvo_weights] alpha and cov_matrix share no tickers")
  }

  alpha_vec <- alpha[common]
  Sigma <- cov_matrix[common, common]
  D <- length(common)

  # Confidence vector (v6.1 R4)
  if (is.null(confidence)) {
    c_vec <- rep(1.0, D)
  } else {
    c_vec <- confidence[common]
    c_vec[is.na(c_vec)] <- 0.5  # missing → neutral
    c_vec <- pmax(pmin(c_vec, 1.0), 0.0)  # [0, 1] clip
  }
  names(c_vec) <- common

  # v2.1 Task#26: Alpha winsorization (±winsor σ)
  winsor_applied <- FALSE
  alpha_raw <- alpha_vec
  if (!is.null(alpha_winsor) && !is.na(alpha_winsor) && alpha_winsor > 0) {
    alpha_vec_w <- .winsorize_alpha(alpha_vec, winsor = alpha_winsor)
    winsor_applied <- !isTRUE(all.equal(as.numeric(alpha_vec_w), as.numeric(alpha_vec)))
    alpha_vec <- alpha_vec_w
  }

  # α̃_i = c_i · α̂_i (confidence-scaled alpha)
  alpha_tilde <- c_vec * alpha_vec

  # Forecast Uncertainty Penalty: FU(x, c) = Σ_i x_i² (1-c_i)²
  fu_diag <- psi * (1 - c_vec)^2

  # quadprog formulation:
  #   min  (1/2) x'Dmat x - d_vec'x
  # MVO v2: max x'α̃ - (λ/2) x'Σx - ψ·x' diag((1-c)²) x
  #  ⇔ min (1/2) x'(λΣ + 2·ψ·diag((1-c)²))x - α̃'x
  Dmat <- lambda * Sigma + diag(2 * fu_diag)
  dvec <- as.vector(alpha_tilde)

  # Numerical stability: add small diagonal
  diag(Dmat) <- diag(Dmat) + 1e-8

  # Constraints:
  # 1'x = 1 (or 0 for active)  — equality
  # x >= bounds[1]              — inequality
  # -x >= -bounds[2]            — inequality (x <= bounds[2])
  Amat <- cbind(rep(1, D), diag(D), -diag(D))
  bvec <- c(if (active) 0 else 1,
            rep(bounds[1], D),
            rep(-bounds[2], D))
  meq <- 1  # 1st constraint is equality

  # v2.1 Feasibility pre-check:
  #   target_sum=1 과 bounds[2] 일관성 + min_names × bounds[2] >= target_sum 확인.
  #   min_names 종목에 고르게 분배 시 종목당 target_sum/min_names_eff 필요.
  #   단, D >= min_names 이고 universe 전체가 bound 채우면 달성 가능하므로
  #   실제로 infeasible 한 경우는 min_names × bounds[2] < target_sum 이 엄격히 맞을 때.
  target_sum <- if (active) 0 else 1
  min_names_eff <- if (is.null(min_names) || is.na(min_names)) 1L else as.integer(min_names)
  if (!active && min_names_eff > 1) {
    # min_names 종목에 고르게 분배 시 종목당 target_sum/min_names_eff 필요
    per_name_need <- target_sum / min_names_eff
    if (per_name_need > bounds[2] + 1e-9) {
      return(list(
        weights = NULL,
        method = "mvo",
        infeasible = TRUE,
        reason = sprintf("min_names_vs_upper_bound: %d × %.3f < %.3f",
                          min_names_eff, bounds[2], target_sum),
        infeasibility_report = list(
          violated_constraints = c("min_names", "weight_bounds_upper"),
          suggested_resolution = sprintf("bounds[2] >= %.4f or min_names <= %d",
                                          per_name_need, floor(target_sum / bounds[2]))
        )
      ))
    }
  }
  # Universe 크기 vs min_names
  if (!active && min_names_eff > D) {
    return(list(
      weights = NULL,
      method = "mvo",
      infeasible = TRUE,
      reason = sprintf("min_names (%d) > universe size (%d)", min_names_eff, D),
      infeasibility_report = list(
        violated_constraints = c("min_names", "universe_size"),
        suggested_resolution = "Expand universe or lower min_names"
      )
    ))
  }

  # Solve QP (1st attempt)
  mvo_solve <- function(lam_val) {
    Dmat_i <- lam_val * Sigma + diag(2 * fu_diag)
    diag(Dmat_i) <- diag(Dmat_i) + 1e-8
    tryCatch(
      solve.QP(Dmat_i, dvec, Amat, bvec, meq = meq),
      error = function(e) NULL
    )
  }

  sol <- mvo_solve(lambda)
  lambda_used <- lambda

  if (is.null(sol)) {
    return(list(
      weights = NULL,
      method = "mvo",
      infeasible = TRUE,
      reason = "QP_solve_failed"
    ))
  }

  w_full <- sol$solution
  names(w_full) <- common

  # ── v2.1 min_names 1차 확보: QP 결과 종목수 < min_names 면 lambda 감소 재시도 ──
  lambda_retries <- 0
  active_names <- function(w) sum(abs(w) > 1e-6)
  if (!active && min_names_eff > 0) {
    while (active_names(w_full) < min_names_eff && lambda_retries < 4) {
      lambda_retries <- lambda_retries + 1
      lambda_used <- lambda_used * 0.5
      sol2 <- mvo_solve(lambda_used)
      if (is.null(sol2)) break
      w_full <- sol2$solution
      names(w_full) <- common
    }
  }

  # max_names hard cap: top-N by |weight|
  if (length(w_full) > max_names) {
    top_idx <- order(abs(w_full), decreasing = TRUE)[seq_len(max_names)]
    w_sparse <- numeric(length(w_full))
    w_sparse[top_idx] <- w_full[top_idx]

    # Renormalize to maintain Σw = 1 (or 0)
    current_sum <- sum(w_sparse)

    if (!active && current_sum > 0) {
      w_sparse <- w_sparse * (target_sum / current_sum)
    }

    # Clip to bounds
    w_sparse <- pmax(pmin(w_sparse, bounds[2]), bounds[1])

    # Final renormalization
    if (!active && sum(w_sparse) > 0) {
      w_sparse <- w_sparse * (target_sum / sum(w_sparse))
    }

    names(w_sparse) <- common
    w_full <- w_sparse
  }

  # ── v2.1 min_names 최종 강제 (post-QP): 여전히 부족하면 top alpha로 보충 ──
  min_names_enforced <- FALSE
  if (!active && min_names_eff > 0 && active_names(w_full) < min_names_eff) {
    n_need <- min_names_eff - active_names(w_full)
    # 현재 active가 아닌 종목 중 alpha_tilde 상위 n_need 선택
    inactive_idx <- which(abs(w_full) <= 1e-6)
    if (length(inactive_idx) > 0) {
      alpha_inactive <- alpha_tilde[inactive_idx]
      add_order <- inactive_idx[order(alpha_inactive, decreasing = TRUE)]
      add_idx <- head(add_order, n_need)

      # 초기 baseline weight 부여 (target_sum / min_names_eff)
      baseline <- target_sum / min_names_eff
      baseline <- min(baseline, bounds[2])
      w_full[add_idx] <- baseline

      # 기존 active 종목의 weight를 비례 축소해서 합=target_sum 유지
      existing_idx <- setdiff(which(abs(w_full) > 1e-6), add_idx)
      excess <- sum(w_full) - target_sum
      if (excess > 0 && length(existing_idx) > 0) {
        scale_factor <- (sum(w_full[existing_idx]) - excess) / sum(w_full[existing_idx])
        scale_factor <- max(scale_factor, 0)
        w_full[existing_idx] <- w_full[existing_idx] * scale_factor
      }

      # bounds clip + 최종 재정규화
      w_full <- pmax(pmin(w_full, bounds[2]), bounds[1])
      if (!active && sum(w_full) > 0) {
        w_full <- w_full * (target_sum / sum(w_full))
      }
      min_names_enforced <- TRUE
    }
  }

  # ── v2.1 HHI cap projection ──
  hhi_applied <- FALSE
  hhi_converged <- TRUE
  if (!active && !is.null(hhi_cap) && !is.na(hhi_cap) && hhi_cap > 0) {
    current_hhi <- sum(w_full^2)
    if (current_hhi > hhi_cap + 1e-6) {
      proj <- .project_hhi(w_full,
                            cap = hhi_cap,
                            bounds = bounds,
                            target_sum = target_sum,
                            step = 0.005,
                            max_iter = 500)
      w_full <- proj$w
      names(w_full) <- common
      hhi_applied <- TRUE
      hhi_converged <- isTRUE(proj$converged)
    }
  }

  # Non-zero만 반환
  w_out <- w_full[abs(w_full) > 1e-6]
  n_final <- length(w_out)
  hhi_final <- sum(w_out^2)

  # Expected metrics (use RAW alpha for realistic expected_active_return)
  exp_ar <- sum(alpha_raw[names(w_out)] * w_out)
  exp_var <- as.numeric(t(w_out) %*% Sigma[names(w_out), names(w_out)] %*% w_out)
  exp_te <- sqrt(max(exp_var, 0))

  # Infeasibility summary (soft — weights still returned if non-NULL)
  infeasibility_report <- NULL
  violations <- character(0)
  if (!active && min_names_eff > 0 && n_final < min_names_eff) {
    violations <- c(violations, "min_names")
  }
  if (!is.null(hhi_cap) && !is.na(hhi_cap) && hhi_final > hhi_cap + 1e-4) {
    violations <- c(violations, "hhi_cap")
  }
  if (length(violations) > 0) {
    infeasibility_report <- list(
      violated_constraints = violations,
      n_final = n_final,
      min_names_required = min_names_eff,
      hhi_final = hhi_final,
      hhi_cap = hhi_cap,
      hhi_converged = hhi_converged,
      suggested_resolution = "Expand universe, raise bounds[2], or lower min_names/hhi_cap"
    )
  }

  list(
    weights = w_out,
    method = sprintf("MVO_lambda_%.2f_psi_%.2f_phi_%.2f",
                     lambda_used, psi, turnover_penalty),
    expected_active_return = exp_ar,
    expected_tracking_error = exp_te,
    expected_information_ratio = if (exp_te > 1e-6) exp_ar / exp_te else NA,
    n_names = n_final,
    hhi = hhi_final,
    confidence_used = !is.null(confidence),
    mean_confidence = mean(c_vec[names(w_out)]),
    min_names_enforced = min_names_enforced,
    hhi_enforced = hhi_applied,
    winsor_applied = winsor_applied,
    lambda_retries = lambda_retries,
    lambda_used = lambda_used,
    infeasible = length(violations) > 0,
    reason = if (length(violations) > 0) paste(violations, collapse = ",") else NULL,
    infeasibility_report = infeasibility_report,
    selection_objective = "net_ir"  # R4 P3: Optimizer는 net_ir로 선택
  )
}

# ─── MVO Grid Search (lambda + phi 탐색) ─────────────────
mvo_grid_search <- function(alpha, cov_matrix,
                             lambda_grid = c(0.5, 1.0, 2.0, 5.0),
                             phi_grid = c(0.0, 0.2, 0.5),
                             bounds = c(0, 0.10),
                             max_names = 20,
                             min_names = 15L,
                             hhi_cap = 0.10,
                             alpha_winsor = 2.0) {
  results <- list()
  i <- 0
  for (lam in lambda_grid) {
    for (ph in phi_grid) {
      i <- i + 1
      r <- mvo_weights(alpha, cov_matrix,
                        lambda = lam, bounds = bounds, max_names = max_names,
                        min_names = min_names, hhi_cap = hhi_cap,
                        alpha_winsor = alpha_winsor,
                        turnover_penalty = ph)
      r$lambda <- lam
      r$phi <- ph
      results[[i]] <- r
    }
  }

  # SR 최대 선택
  srs <- sapply(results, function(r) if (!is.null(r$expected_information_ratio)) r$expected_information_ratio else -Inf)
  best_idx <- which.max(srs)
  best <- results[[best_idx]]

  list(
    best = best,
    all_results = results,
    n_tested = length(results)
  )
}

cat("[mean_variance_optimizer.R] v2.1 (Task#26 breadth + HHI + winsor) Loaded. Functions:\n")
cat("  mvo_weights(alpha, cov, confidence=NULL, lambda=1.0, psi=0.3,\n")
cat("              bounds=c(0,0.10), max_names=20, min_names=15, hhi_cap=0.10, alpha_winsor=2.0)\n")
cat("  mvo_grid_search(alpha, cov, lambda_grid, phi_grid)\n")
