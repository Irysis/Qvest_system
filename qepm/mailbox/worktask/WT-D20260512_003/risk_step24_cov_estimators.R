#==============================================================================
# Risk Step 2-4: Σ Estimator Comparison + Factor Decomposition Σ = BΩB' + D
#
# 5 candidate estimators (parallel R13):
#   1. Sample (pairwise) — baseline
#   2. Ledoit-Wolf to identity (constant variance target)
#   3. Ledoit-Wolf to constant correlation (Honey & Wolf 2004)
#   4. Gerber statistic + RMT denoise (noise-robust)
#   5. Factor model: Σ = BΩB' + D (FF-Carhart-Tail 7 factor)
#
# Selection objective: condition_number + stress_robust  (R4 P3 mandate)
# PIT: rolling 60m window (latest 60m = 2021-05~2026-04)
# Universe: 238 tickers (alpha emission as_of 2026-04-01)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(future); library(future.apply)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
source("02_Infrastructure/portfolio/hrp_core.R")

OUT_DIR <- "stage_artifacts/WT_D20260512_003"
N_OBS_WINDOW <- 60L

# ── 1. Load returns + factor TS ─────────────────────────────────────────────
ret_wide <- as.data.table(read_parquet(file.path(OUT_DIR, "_risk_monthly_returns_wide.parquet")))
factor_ts <- as.data.table(read_parquet(file.path(OUT_DIR, "_risk_factor_ts.parquet")))
alpha_dt <- as.data.table(read_parquet(file.path(OUT_DIR, "alpha_scores_new.parquet")))

# Universe = top 238 active at 2026-04-01
last_date <- max(alpha_dt$Date)
univ <- sort(unique(alpha_dt[Date == last_date & !is.na(z_blend_composite), Ticker]))
cat("[Step2] Universe:", length(univ), "  Latest sig_date:", as.character(last_date), "\n")

# Select latest 60 sig_dates (PIT: window = (last - 59) to last_date inclusive, but ret_t available at sig_date t)
# We use the alpha-aligned monthly returns. last_date 2026-04-01 emits weights for May.
# For Σ estimation we use returns t = 2021-05-01 ~ 2026-04-01 (60 obs).
# Each return Ret_m[t] is computed from Close[t-1m] to Close[t] which is PIT-clean.
all_dates <- sort(ret_wide$Date)
end_idx <- which(all_dates == last_date)
start_idx <- end_idx - N_OBS_WINDOW + 1L
if (start_idx < 1L) stop("Insufficient history")
window_dates <- all_dates[start_idx:end_idx]
cat("[Step2] Estimation window:", as.character(window_dates[1]), " ~ ", as.character(window_dates[N_OBS_WINDOW]),
    " (T =", N_OBS_WINDOW, ")\n")

ret_sub <- ret_wide[Date %in% window_dates]
setorder(ret_sub, Date)

# Restrict columns to universe present at last date
ret_mat <- as.matrix(ret_sub[, ..univ])
rownames(ret_mat) <- as.character(ret_sub$Date)
# Track tickers with sufficient coverage
n_obs_per_ticker <- colSums(!is.na(ret_mat))
keep_tickers <- names(n_obs_per_ticker)[n_obs_per_ticker >= 40L]
cat("[Step2] Tickers with >=40 obs:", length(keep_tickers), "/", length(univ), "\n")
ret_mat <- ret_mat[, keep_tickers]
cat("[Step2] Final returns matrix:", nrow(ret_mat), "x", ncol(ret_mat), "\n")

# Mean-impute residual NAs (rare, < few obs)
ret_mat[is.na(ret_mat)] <- 0
cat("[Step2] NAs replaced with 0 (residual).\n")

# ── 2. Estimator definitions ────────────────────────────────────────────────
est_sample <- function(R) {
  cv <- cov(R, use = "pairwise.complete.obs")
  cv[is.na(cv)] <- 0
  cv
}

# Ledoit-Wolf 2004 shrinkage to identity (or constant variance target)
est_lw_identity <- function(R) {
  S <- cov(R, use = "pairwise.complete.obs")
  S[is.na(S)] <- 0
  p <- ncol(R); n <- nrow(R)
  mu <- mean(diag(S))
  F_target <- mu * diag(p)
  # Ledoit-Wolf optimal shrinkage intensity
  # Honey-Wolf (2003) eqn 16: rho = (sum_var_S_ij - cov_S_F) / ||S - F||^2
  # Simplified: rho = pi / (n * (gamma^2))
  Rc <- scale(R, center = TRUE, scale = FALSE)
  Rc[is.na(Rc)] <- 0
  pi_hat <- 0
  for (i in 1:p) for (j in 1:p) {
    pi_hat <- pi_hat + var(Rc[,i] * Rc[,j], na.rm=TRUE)
  }
  pi_hat <- pi_hat / n
  gamma_hat <- sum((F_target - S)^2)
  rho <- max(0, min(1, pi_hat / gamma_hat))
  Sigma_lw <- (1 - rho) * S + rho * F_target
  attr(Sigma_lw, "shrinkage") <- rho
  Sigma_lw
}

# Ledoit-Wolf to constant-correlation target (better for equity panels)
est_lw_constcor <- function(R) {
  S <- cov(R, use = "pairwise.complete.obs")
  S[is.na(S)] <- 0
  p <- ncol(R); n <- nrow(R)
  sds <- sqrt(diag(S))
  if (any(sds <= 0)) sds[sds <= 0] <- 1e-8
  cor_mat <- S / outer(sds, sds)
  cor_mat[is.na(cor_mat)] <- 0
  diag(cor_mat) <- 1
  r_bar <- (sum(cor_mat) - p) / (p * (p - 1))
  F_target_cor <- matrix(r_bar, p, p); diag(F_target_cor) <- 1
  F_target <- F_target_cor * outer(sds, sds)
  Rc <- scale(R, center = TRUE, scale = FALSE)
  Rc[is.na(Rc)] <- 0
  pi_hat <- 0
  for (i in 1:p) for (j in 1:p) {
    pi_hat <- pi_hat + var(Rc[,i] * Rc[,j], na.rm = TRUE)
  }
  pi_hat <- pi_hat / n
  gamma_hat <- sum((F_target - S)^2)
  rho <- max(0, min(1, pi_hat / gamma_hat))
  Sigma_lw <- (1 - rho) * S + rho * F_target
  attr(Sigma_lw, "shrinkage") <- rho
  Sigma_lw
}

# Gerber+RMT via hrp_core .get_cor_cov
est_gerber_rmt <- function(R) {
  res <- .get_cor_cov(R, cov_method = "gerber_rmt")
  res$cov
}

# Factor model B Omega B' + D
est_factor_model <- function(R, F_mat) {
  # R: T x N stock returns; F_mat: T x K factor returns
  ok_rows <- complete.cases(F_mat)
  Rk <- R[ok_rows, , drop = FALSE]
  Fk <- as.matrix(F_mat[ok_rows, , drop = FALSE])
  T_eff <- nrow(Rk); K <- ncol(Fk); N <- ncol(Rk)
  if (T_eff < K + 3) stop("Factor model: insufficient obs")

  # OLS B via lm on each stock
  B <- matrix(0, N, K)
  D_diag <- rep(0, N)
  alpha_intercept <- rep(0, N)
  Fdesign <- cbind(1, Fk)  # intercept column
  XtX_inv <- solve(crossprod(Fdesign))

  for (j in 1:N) {
    y <- Rk[, j]
    coefs <- as.vector(XtX_inv %*% crossprod(Fdesign, y))
    alpha_intercept[j] <- coefs[1]
    B[j, ] <- coefs[-1]
    resid <- y - Fdesign %*% coefs
    D_diag[j] <- var(resid)
  }
  rownames(B) <- colnames(R); colnames(B) <- colnames(Fk)
  names(D_diag) <- colnames(R)
  Omega <- cov(Fk)

  Sigma_F <- B %*% Omega %*% t(B)
  # Cross terms (B Omega B') + D
  Sigma_total <- Sigma_F + diag(D_diag)
  rownames(Sigma_total) <- colnames(Sigma_total) <- colnames(R)

  # Symmetric guarantee
  Sigma_total <- (Sigma_total + t(Sigma_total)) / 2
  attr(Sigma_total, "B") <- B
  attr(Sigma_total, "Omega") <- Omega
  attr(Sigma_total, "D") <- D_diag
  attr(Sigma_total, "alpha") <- alpha_intercept
  attr(Sigma_total, "factor_explained_var_pct") <- sum(diag(Sigma_F)) / sum(diag(Sigma_total)) * 100
  Sigma_total
}

# ── 3. Prepare factor matrix for the window ─────────────────────────────────
factor_window <- factor_ts[Date %in% window_dates]
setorder(factor_window, Date)
F_mat <- as.matrix(factor_window[, .(RM_KR, F_SIZE, F_VAL, F_MOM, F_QMJ, F_BAB, F_LIQ, F_TAIL)])
cat("[Step2] Factor matrix:", nrow(F_mat), "x", ncol(F_mat), "  NA rows:", sum(!complete.cases(F_mat)), "\n")

# ── 4. Parallel estimator comparison (R13) ──────────────────────────────────
# 5 estimators tested. Cap = 5. method_shopping_log compliance.

# Note: per R13 sequential safer for moderate size (T=60, N=238). Try parallel light.
n_workers <- 1L  # serial for stability (Sigma calc takes <30s each)
cat("[Step2] Running", 5, "estimators (n_workers =", n_workers, ")...\n")

estimators <- list(
  list(name = "sample",       fn = function() est_sample(ret_mat)),
  list(name = "ledoit_wolf_identity",  fn = function() est_lw_identity(ret_mat)),
  list(name = "ledoit_wolf_constcor",  fn = function() est_lw_constcor(ret_mat)),
  list(name = "gerber_rmt",            fn = function() est_gerber_rmt(ret_mat)),
  list(name = "factor_model_8f",       fn = function() est_factor_model(ret_mat, F_mat))
)

results <- lapply(estimators, function(e) {
  t0 <- Sys.time()
  out <- tryCatch({
    Sigma <- e$fn()
    eig <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
    list(
      ok = TRUE, name = e$name, Sigma = Sigma,
      shrinkage = attr(Sigma, "shrinkage"),
      factor_explained_pct = attr(Sigma, "factor_explained_var_pct"),
      condition_number = max(eig) / max(min(eig), 1e-12),
      min_eigenvalue = min(eig),
      max_eigenvalue = max(eig),
      n_negative_eig = sum(eig < -1e-10),
      psd = all(eig >= -1e-8),
      avg_vol_diag = mean(sqrt(diag(Sigma)))
    )
  }, error = function(err) {
    list(ok = FALSE, name = e$name, error = conditionMessage(err))
  })
  out$elapsed_sec <- round(as.numeric(Sys.time() - t0, "secs"), 2)
  cat(sprintf("  [%s] ok=%s cond=%.1f shrink=%s elapsed=%.2fs\n",
              e$name, out$ok,
              ifelse(is.null(out$condition_number), NA, out$condition_number),
              ifelse(is.null(out$shrinkage), NA, round(out$shrinkage, 4)),
              out$elapsed_sec))
  out
})

# ── 5. Display comparison table ─────────────────────────────────────────────
summary_dt <- rbindlist(lapply(results, function(r) {
  data.table(
    method = r$name,
    ok = r$ok,
    condition_number = ifelse(is.null(r$condition_number), NA_real_, r$condition_number),
    min_eig = ifelse(is.null(r$min_eigenvalue), NA_real_, r$min_eigenvalue),
    psd = ifelse(is.null(r$psd), NA, r$psd),
    shrinkage = ifelse(is.null(r$shrinkage), NA_real_, r$shrinkage),
    factor_explained_pct = ifelse(is.null(r$factor_explained_pct), NA_real_, r$factor_explained_pct),
    avg_vol_diag = ifelse(is.null(r$avg_vol_diag), NA_real_, r$avg_vol_diag),
    elapsed_sec = r$elapsed_sec
  )
}), fill = TRUE)

cat("\n[Step2-4] ESTIMATOR COMPARISON TABLE:\n")
print(summary_dt)

# ── 6. Selection (R4 P3 objective: condition_number + stress_robust) ────────
# Hard cut: PSD required (psd = TRUE)
# Sort by condition_number ascending — lowest cond = best conditioning
candidates <- summary_dt[ok == TRUE & psd == TRUE]
setorder(candidates, condition_number)
cat("\n[Step2-4] PSD candidates ordered by condition_number:\n")
print(candidates)

# Primary selection: prefer factor_model if cond is reasonable (<500),
# else fallback to ledoit_wolf_constcor or gerber_rmt
selection <- NULL
fm_row <- candidates[method == "factor_model_8f"]
if (nrow(fm_row) == 1 && fm_row$condition_number < 500) {
  selection <- "factor_model_8f"
  rationale <- "Factor model 8F (FF + Carhart MOM + QMJ + BAB + LIQ + TAIL) prevails — interpretable B Omega B' + D structure + condition number acceptable."
} else if (candidates[1, condition_number] < 200) {
  selection <- candidates[1, method]
  rationale <- "Lowest condition_number estimator selected per R4 P3 objective."
} else {
  # Force Ledoit-Wolf constant-correlation as defensive fallback
  selection <- "ledoit_wolf_constcor"
  rationale <- "Defensive fallback — high-dim p=238 vs T=60 requires constant-correlation shrinkage."
}

cat("\n[Step2-4] PRIMARY SELECTION:", selection, "\n")
cat("Rationale:", rationale, "\n")

# Save selected Σ + diagnostics
primary <- results[[which(sapply(results, function(r) r$name == selection))]]
Sigma_primary <- primary$Sigma

# Save covariance.parquet (long format: i, j, sigma_ij)
cov_long <- as.data.table(expand.grid(i = rownames(Sigma_primary), j = colnames(Sigma_primary), stringsAsFactors = FALSE))
cov_long[, sigma_ij := as.vector(Sigma_primary)]
cov_long[, estimator := selection]
write_parquet(cov_long, file.path(OUT_DIR, "covariance.parquet"))
cat("[Step2-4] covariance.parquet saved (", nrow(cov_long), "rows).\n")

# Save B, Omega, D separately for factor model
if (selection == "factor_model_8f") {
  B <- attr(Sigma_primary, "B")
  Omega <- attr(Sigma_primary, "Omega")
  D <- attr(Sigma_primary, "D")
  alpha_int <- attr(Sigma_primary, "alpha")

  # B as long format
  B_dt <- as.data.table(B, keep.rownames = "Ticker")
  write_parquet(B_dt, file.path(OUT_DIR, "exposure_matrix.parquet"))

  Omega_dt <- as.data.table(Omega, keep.rownames = "Factor")
  write_parquet(Omega_dt, file.path(OUT_DIR, "factor_covariance.parquet"))

  D_dt <- data.table(Ticker = names(D), specific_var = D, specific_vol = sqrt(D),
                     alpha_intercept = alpha_int)
  write_parquet(D_dt, file.path(OUT_DIR, "specific_risk.parquet"))
  cat("[Step2-4] B / Ω / D saved as exposure_matrix / factor_covariance / specific_risk.\n")
}

# Save method_shopping_log
ms_log <- list(
  candidates_tried = nrow(summary_dt),
  cap = 5L,
  method_log = lapply(seq_len(nrow(summary_dt)), function(k) {
    list(
      name = summary_dt$method[k],
      condition = summary_dt$condition_number[k],
      psd = as.logical(summary_dt$psd[k]),
      shrinkage = summary_dt$shrinkage[k],
      factor_explained_pct = summary_dt$factor_explained_pct[k],
      avg_vol_diag = summary_dt$avg_vol_diag[k],
      selected = (summary_dt$method[k] == selection)
    )
  }),
  selected = selection,
  rationale = rationale,
  selection_objective = "condition_number_stress_robust",
  estimation_window = paste0(as.character(window_dates[1]), "/", as.character(window_dates[N_OBS_WINDOW])),
  N_obs = N_OBS_WINDOW,
  N_assets = ncol(ret_mat)
)
jsonlite::write_json(ms_log, file.path(OUT_DIR, "_risk_method_shopping_log.json"),
                     pretty = TRUE, auto_unbox = TRUE)

# Save full summary for downstream stress test
saveRDS(list(
  results = results,
  summary = summary_dt,
  selection = selection,
  ret_mat = ret_mat,
  F_mat = F_mat,
  window_dates = window_dates,
  univ = keep_tickers
), file.path(OUT_DIR, "_risk_step24_results.rds"))
cat("[Step2-4] DONE.\n")
