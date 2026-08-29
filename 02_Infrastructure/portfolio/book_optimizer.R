#==============================================================================
# ★v10 (2026-08-29 도훈): governor 폐지 — book_update()/update_book_state() 의 book_state.json
#   쓰기 경로는 봉인(legacy 동결 — book_write_guard.sh 가 차단). book_information_ratio 등
#   계산 함수는 2계층 dispatcher 래퍼가 계속 쓴다(존치).
# QEPM Book-Level Optimizer — v6.1 R5 (2026-04-24)
#
# Problem: Governor는 개별 WT admission만 판정. 여러 admitted WT가 결합됐을 때
#   book-level exposure (factor crowding / 섹터 집중 / 금리 민감도) 미포착.
#
# Input: optimization_package list (admitted WTs)
# Output: book-level weights per WT (단일 book 내 WT 배분)
#
# Objective:
#   max   w_book' · μ_book
#       - (λ/2) · w_book' · Σ_cross · w_book       (cross-WT variance)
#       - γ_crowd · CrowdingPenalty(w_book, factor_loadings)
#       - γ_redun · RedundancyPenalty(w_book, pairwise_corr)
#
# Constraints:
#   Σ w_book = 1 (absolute book weight across WTs)
#   w_book >= 0 (long-only book combination)
#   max_per_wt (default 0.50)
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(quadprog)
  library(data.table)
})

# ─── Utility ────────────────────────────────────────────
`%||%` <- function(a, b) if (!is.null(a) && !is.na(a)) a else b

# ─── Load admitted WT packages ──────────────────────────
load_admitted_packages <- function(wt_ids, wt_root = "qepm/mailbox/worktask") {
  pkgs <- list()
  for (id in wt_ids) {
    opt_path <- file.path(wt_root, id, "optimization_package.json")
    risk_path <- file.path(wt_root, id, "risk_package.json")
    alpha_path <- file.path(wt_root, id, "alpha_package.json")
    if (!all(file.exists(c(opt_path, risk_path, alpha_path)))) {
      warning(sprintf("[book_optimizer] %s — 3-package 불완전, skip", id))
      next
    }
    pkgs[[id]] <- list(
      alpha = fromJSON(alpha_path, simplifyVector = FALSE),
      risk = fromJSON(risk_path, simplifyVector = FALSE),
      opt = fromJSON(opt_path, simplifyVector = FALSE)
    )
  }
  pkgs
}

# ─── Build cross-WT expected return vector ──────────────
build_wt_expected_return <- function(pkgs) {
  vapply(pkgs, function(p) p$opt$expected_active_return %||% 0,
         FUN.VALUE = numeric(1))
}

# ─── Build cross-WT covariance (portfolio of portfolios) ─
# For each pair (i, j), approximate cov via shared ticker overlap
# weighted by target_weights (simple attribution).
build_cross_wt_cov <- function(pkgs) {
  n <- length(pkgs)
  if (n == 0) return(matrix(0, 0, 0))
  ids <- names(pkgs)

  # Collect tick-weight vectors
  weight_list <- lapply(pkgs, function(p) {
    tw <- p$opt$target_weights
    if (is.null(tw)) return(numeric(0))
    unlist(tw)
  })

  # Union universe
  uni <- sort(unique(unlist(lapply(weight_list, names))))
  if (length(uni) == 0) return(matrix(0, n, n))

  # Pad into matrix (ticker × WT)
  W <- matrix(0, nrow = length(uni), ncol = n,
              dimnames = list(uni, ids))
  for (j in seq_len(n)) {
    wv <- weight_list[[j]]
    if (length(wv) > 0) W[names(wv), j] <- as.numeric(wv)
  }

  # Approximate TE for each WT
  te_vec <- vapply(pkgs, function(p) p$opt$expected_tracking_error %||% 0.05,
                   FUN.VALUE = numeric(1))

  # Pairwise cosine similarity × TE_i × TE_j (proxy for cov)
  sig <- matrix(0, n, n, dimnames = list(ids, ids))
  for (i in seq_len(n)) {
    for (j in seq_len(n)) {
      vi <- W[, i]
      vj <- W[, j]
      denom <- sqrt(sum(vi^2)) * sqrt(sum(vj^2))
      rho <- if (denom > 0) sum(vi * vj) / denom else 0
      sig[i, j] <- rho * te_vec[i] * te_vec[j]
    }
  }
  sig
}

# ─── Crowding penalty via shared factor exposure ─────────
# Sum of |shared factor weights|^2 penalized
compute_crowding_factor <- function(pkgs) {
  n <- length(pkgs)
  if (n == 0) return(numeric(0))

  # Collect factor families
  all_factors <- c()
  wt_factors <- lapply(pkgs, function(p) {
    specs <- p$alpha$factor_specs %||% list()
    if (length(specs) == 0) return(character(0))
    vapply(specs, function(s) s$factor_family %||% "", character(1))
  })

  # Crowding intensity = count of WTs sharing a factor family
  all_factors <- unlist(wt_factors)
  fam_counts <- table(all_factors)

  # Per-WT crowding = avg (count - 1) across its factors
  vapply(wt_factors, function(fs) {
    if (length(fs) == 0) return(0)
    shares <- fam_counts[fs] - 1
    mean(pmax(shares, 0))
  }, numeric(1))
}

# ─── Book Optimizer QP ──────────────────────────────────
book_optimize <- function(pkgs,
                          lambda = 2.0,
                          gamma_crowd = 0.3,
                          gamma_redun = 0.2,
                          max_per_wt = 0.50,
                          min_per_wt = 0.05) {
  if (length(pkgs) == 0) stop("[book_optimize] no admitted WTs")

  ids <- names(pkgs)
  n <- length(pkgs)

  mu <- build_wt_expected_return(pkgs)
  Sigma <- build_cross_wt_cov(pkgs)
  crowding <- compute_crowding_factor(pkgs)

  # Crowding penalty → diagonal addition
  crowd_diag <- gamma_crowd * crowding

  # Redundancy penalty: pairwise off-diagonal of Sigma (already built in)
  # Simply scale Sigma
  Dmat <- lambda * Sigma + diag(2 * crowd_diag, nrow = n) * gamma_redun
  diag(Dmat) <- diag(Dmat) + 1e-6

  dvec <- mu

  # Constraints: Σw = 1, w >= min_per_wt, w <= max_per_wt
  Amat <- cbind(rep(1, n), diag(n), -diag(n))
  bvec <- c(1, rep(min_per_wt, n), rep(-max_per_wt, n))
  meq <- 1

  sol <- tryCatch(
    solve.QP(Dmat, dvec, Amat, bvec, meq = meq),
    error = function(e) {
      warning("[book_optimize] QP failed: ", conditionMessage(e))
      NULL
    }
  )

  if (is.null(sol)) {
    # Fallback: equal-weight
    w <- rep(1 / n, n)
    names(w) <- ids
    return(list(
      book_weights = w,
      method = "equal_weight_fallback",
      infeasible = TRUE,
      reason = "QP_solve_failed_equal_fallback"
    ))
  }

  w <- sol$solution
  names(w) <- ids

  # Book-level metrics
  book_mu <- sum(w * mu)
  book_var <- as.numeric(t(w) %*% Sigma %*% w)
  book_te <- sqrt(max(book_var, 0))
  book_ir <- if (book_te > 1e-6) book_mu / book_te else NA

  list(
    book_weights = w,
    method = sprintf("book_QP_lam%.2f_crowd%.2f_redun%.2f",
                     lambda, gamma_crowd, gamma_redun),
    book_expected_return = book_mu,
    book_tracking_error = book_te,
    book_information_ratio = book_ir,
    cross_wt_cov = Sigma,
    crowding_per_wt = crowding,
    admitted_ids = ids,
    infeasible = FALSE
  )
}

# ─── book_state.json 업데이트 ───────────────────────────
update_book_state <- function(book_result,
                              state_path = "qepm/mailbox/governor/book_state.json") {
  dir.create(dirname(state_path), recursive = TRUE, showWarnings = FALSE)

  # Aggregate factor exposure
  state <- list(
    updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    n_admitted = length(book_result$admitted_ids),
    admitted_ids = as.list(book_result$admitted_ids),
    book_weights = as.list(book_result$book_weights),
    book_metrics = list(
      expected_return = book_result$book_expected_return,
      tracking_error = book_result$book_tracking_error,
      information_ratio = book_result$book_information_ratio
    ),
    crowding_per_wt = as.list(book_result$crowding_per_wt),
    method = book_result$method,
    infeasible = book_result$infeasible,
    reason = book_result$reason
  )

  write_json(state, state_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[book_state] updated: %d WTs, IR=%.3f\n",
              state$n_admitted,
              state$book_metrics$information_ratio %||% NA))
  invisible(state)
}

# ─── End-to-end ─────────────────────────────────────────
book_update <- function(admitted_wt_ids,
                        lambda = 2.0,
                        gamma_crowd = 0.3,
                        gamma_redun = 0.2,
                        max_per_wt = 0.50,
                        min_per_wt = 0.05) {
  pkgs <- load_admitted_packages(admitted_wt_ids)
  if (length(pkgs) == 0) {
    warning("[book_update] no valid packages loaded")
    return(invisible(NULL))
  }

  result <- book_optimize(pkgs,
                          lambda = lambda,
                          gamma_crowd = gamma_crowd,
                          gamma_redun = gamma_redun,
                          max_per_wt = max_per_wt,
                          min_per_wt = min_per_wt)

  update_book_state(result)
  invisible(result)
}

cat("[book_optimizer.R] v6.1 R5 Loaded. Functions:\n")
cat("  book_update(admitted_wt_ids) — end-to-end book rebalance\n")
cat("  book_optimize(pkgs, lambda, gamma_crowd, gamma_redun)\n")
cat("  load_admitted_packages(wt_ids)\n")
cat("  update_book_state(book_result, state_path)\n")
