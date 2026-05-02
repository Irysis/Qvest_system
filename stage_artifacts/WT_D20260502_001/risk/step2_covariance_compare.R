#==============================================================================
# WT-D20260502_001 Risk Research — Step 2: Covariance Estimator Comparison (R13)
#
# Goal: Choose primary Σ via R4 selection_objective (estimation quality only).
#  Compare 5 estimators: Sample / Ledoit-Wolf (Oracle) / Gerber+RMT / LW-ConstCorr / NLS-approx
#  Method shopping log (R2-C max=5) — log all, single selection.
#
#  R13 Parallel — future_lapply, n_workers = min(5, cores - 1)
#
# Returns matrix: monthly 60M (322 covered tickers) — sufficient T to avoid singular
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(future)
  library(future.apply)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ, "stage_artifacts/WT_D20260502_001/risk")
state <- readRDS(file.path(WT_DIR, "step1_state.rds"))

`%||%` <- function(x, y) if (is.null(x)) y else x

# ---- Build monthly returns matrix --------------------------------------------
monthly_wide_60 <- state$monthly_wide_60
covered <- state$covered_tickers_60M
ret_mat_full <- as.matrix(monthly_wide_60[, ..covered])
# Replace NA with 0 (after coverage filter, missing data = no return that month)
ret_mat <- ret_mat_full
ret_mat[is.na(ret_mat)] <- 0
n_obs <- nrow(ret_mat)
n_assets <- ncol(ret_mat)
cat(sprintf("[Step2] Returns matrix: %d months x %d assets\n", n_obs, n_assets))

# Source hrp_core for Gerber + LW + RMT
source(file.path(PROJ, "02_Infrastructure/portfolio/hrp_core.R"))

# ---- Define 5 estimators (R2-C max=5) ----------------------------------------
estimators <- list(

  # 1. Sample (with pairwise.complete)
  list(name = "sample", fn = function(r) {
    n <- nrow(r); p <- ncol(r)
    Sigma <- cov(r, use = "pairwise.complete.obs")
    Sigma[is.na(Sigma)] <- 0
    Sigma
  }),

  # 2. Ledoit-Wolf (constant correlation prior, original formula in hrp_core)
  list(name = "ledoit_wolf_constcor", fn = function(r) {
    cc <- .get_cor_cov(r, "ledoit_wolf")
    cc$cov
  }),

  # 3. Gerber + RMT denoise
  list(name = "gerber_rmt", fn = function(r) {
    cc <- .get_cor_cov(r, "gerber_rmt")
    cc$cov
  }),

  # 4. Ledoit-Wolf to identity (oracle approximation, James-Stein style)
  list(name = "ledoit_wolf_oracle", fn = function(r) {
    n <- nrow(r); p <- ncol(r)
    S <- cov(r, use = "pairwise.complete.obs")
    S[is.na(S)] <- 0
    # F = (trace(S)/p) * I  (identity scaled by avg variance)
    mu <- mean(diag(S), na.rm = TRUE)
    F_target <- mu * diag(p)
    # Optimal shrinkage rho (Ledoit-Wolf 2004 closed form)
    # Simplified: use min(1, max(0, (trace(S^2) - trace(S)^2/p) / ((n-1)*||S - F||^2)))
    diff <- S - F_target
    num <- sum((S - F_target)^2)
    den <- sum(S^2)  # approximation
    rho <- min(1, max(0, num / (den + 1e-10)))
    # 보수적 lower bound
    rho <- max(rho, 0.05)
    Sigma <- (1 - rho) * S + rho * F_target
    attr(Sigma, "rho") <- rho
    Sigma
  }),

  # 5. NLS approximation: trim eigenvalues below MP cutoff to mean (RMT only, no Gerber)
  list(name = "rmt_nls_approx", fn = function(r) {
    n <- nrow(r); p <- ncol(r)
    S <- cov(r, use = "pairwise.complete.obs")
    S[is.na(S)] <- 0
    # Convert to correlation
    sds <- sqrt(diag(S))
    sds[sds == 0] <- 1e-8
    cor_mat <- S / outer(sds, sds)
    diag(cor_mat) <- 1
    # RMT eigenvalue trimming
    q_ratio <- n / p
    if (q_ratio < 1) {
      # If T < N, use Marchenko-Pastur clipping with bound
      lambda_plus <- (1 + 1 / sqrt(max(q_ratio, 0.1)))^2
    } else {
      lambda_plus <- (1 + 1 / sqrt(q_ratio))^2
    }
    eig <- eigen(cor_mat, symmetric = TRUE)
    vals <- eig$values
    vecs <- eig$vectors
    # Replace noise eigenvalues with mean
    noise_idx <- which(vals <= lambda_plus)
    if (length(noise_idx) > 0 && length(noise_idx) < length(vals)) {
      vals[noise_idx] <- mean(vals[noise_idx])
    }
    cor_clean <- vecs %*% diag(vals) %*% t(vecs)
    diag(cor_clean) <- 1
    cor_clean <- (cor_clean + t(cor_clean)) / 2
    # Convert back to covariance
    Sigma <- cor_clean * outer(sds, sds)
    Sigma
  })
)

# Diagnostics computation
estimator_diag <- function(Sigma, name) {
  Sigma_sym <- (Sigma + t(Sigma)) / 2
  eig_vals <- tryCatch(
    eigen(Sigma_sym, only.values = TRUE)$values,
    error = function(e) NA
  )
  if (any(is.na(eig_vals))) {
    return(list(ok = FALSE, name = name, error = "eigen_failed"))
  }
  min_eig <- min(eig_vals)
  max_eig <- max(eig_vals)
  cn <- if (min_eig > 0) max_eig / min_eig else Inf
  is_psd <- min_eig > -1e-10
  list(
    ok = TRUE,
    name = name,
    Sigma = Sigma_sym,
    condition = cn,
    min_eig = min_eig,
    max_eig = max_eig,
    is_psd = is_psd,
    n_negative_eig = sum(eig_vals < -1e-10),
    trace = sum(diag(Sigma_sym)),
    diag_sd_mean = mean(sqrt(diag(Sigma_sym)))
  )
}

# ---- R13 Parallel execution --------------------------------------------------
n_workers <- min(5L, max(1L, parallel::detectCores() - 1L))
cat(sprintf("[Step2] Parallel covariance: %d workers, %d estimators\n",
            n_workers, length(estimators)))

t0 <- Sys.time()
plan(multisession, workers = n_workers)

results <- future_lapply(estimators, function(e) {
  source(file.path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
                   "02_Infrastructure/portfolio/hrp_core.R"))
  res <- tryCatch({
    Sigma <- e$fn(ret_mat)
    diag <- estimator_diag(Sigma, e$name)
    diag
  }, error = function(err) {
    list(ok = FALSE, name = e$name, error = conditionMessage(err))
  })
  res
}, future.seed = NULL, future.globals = list(ret_mat = ret_mat,
                                              estimator_diag = estimator_diag,
                                              estimators = estimators,
                                              e = NULL))
plan(sequential)
t1 <- Sys.time()
cat(sprintf("[Step2] Parallel covariance done in %.1fs\n",
            as.numeric(difftime(t1, t0, units = "secs"))))

# ---- Method shopping log ----
method_log <- list()
for (i in seq_along(results)) {
  r <- results[[i]]
  if (r$ok) {
    method_log[[length(method_log) + 1]] <- list(
      name = r$name,
      condition = round(r$condition, 2),
      min_eig = signif(r$min_eig, 4),
      max_eig = signif(r$max_eig, 4),
      is_psd = r$is_psd,
      n_negative_eig = r$n_negative_eig,
      ok = TRUE,
      selected = FALSE
    )
  } else {
    method_log[[length(method_log) + 1]] <- list(
      name = r$name,
      ok = FALSE,
      error = r$error,
      selected = FALSE
    )
  }
}

# ---- Selection rule: R4 selection_objective = condition_number minimization ---
# But also require PSD. Among PSD candidates, lowest condition number = best.
# If no PSD, pick lowest abs(min_eig) and apply jitter.
psd_results <- Filter(function(r) r$ok && r$is_psd, results)
if (length(psd_results) > 0) {
  conds <- sapply(psd_results, function(r) r$condition)
  best_idx <- which.min(conds)
  primary <- psd_results[[best_idx]]
  cat(sprintf("[Step2] Primary Σ: %s (cn=%.1f, min_eig=%g, PSD=TRUE)\n",
              primary$name, primary$condition, primary$min_eig))
} else {
  # No PSD: choose lowest abs(min_eig) and apply jitter
  abs_min_eig <- sapply(Filter(function(r) r$ok, results),
                        function(r) abs(r$min_eig))
  best_idx <- which.min(abs_min_eig)
  primary <- Filter(function(r) r$ok, results)[[best_idx]]
  jitter <- abs(primary$min_eig) * 1.5 + 1e-6
  primary$Sigma <- primary$Sigma + jitter * diag(nrow(primary$Sigma))
  primary$jitter_applied <- jitter
  primary$is_psd <- TRUE
  primary$min_eig <- min(eigen(primary$Sigma, only.values=TRUE)$values)
  primary$condition <- max(eigen(primary$Sigma, only.values=TRUE)$values) / primary$min_eig
  cat(sprintf("[Step2] No PSD; jittered %s (jitter=%g, new cn=%.1f)\n",
              primary$name, jitter, primary$condition))
}

# Mark selected in log
for (i in seq_along(method_log)) {
  if (method_log[[i]]$name == primary$name) method_log[[i]]$selected <- TRUE
}

# ---- Save state -------------------------------------------------------------
state$Sigma_primary <- primary$Sigma
state$Sigma_primary_name <- primary$name
state$Sigma_diagnostics <- list(
  condition_number = primary$condition,
  min_eig = primary$min_eig,
  max_eig = primary$max_eig,
  is_psd = primary$is_psd,
  trace = primary$trace,
  jitter_applied = primary$jitter_applied %||% 0
)
state$method_log <- method_log
state$candidates_tried <- length(results)
state$selection_objective <- "condition_number"
state$assets_in_Sigma <- colnames(state$monthly_wide_60[, ..covered])

saveRDS(state, file.path(WT_DIR, "step2_state.rds"))
write_json(method_log, file.path(WT_DIR, "method_shopping_log.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("[Step2] DONE.\n")
print(method_log)
