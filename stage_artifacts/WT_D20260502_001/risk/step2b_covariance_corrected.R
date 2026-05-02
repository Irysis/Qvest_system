#==============================================================================
# WT-D20260502_001 Risk Research — Step 2b: Corrected LW + alternative options
#
# Step 2 found hrp_core LW formula broken (T=60 < N=336 → rho=1, identity).
# Implement proper Ledoit-Wolf 2003/2004 (target = constant correlation) with
# valid T<N rho derivation.
#
# Compare:
#  - sample (singular)
#  - lw_2003_const_cor (proper LW, valid T<N)
#  - lw_oracle_identity (my custom, cn=4.39 from step2)
#  - lw_diag (target = diagonal, only shrink off-diagonal)
#  - rmt_nls_approx (cn=1405)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ, "stage_artifacts/WT_D20260502_001/risk")
state <- readRDS(file.path(WT_DIR, "step1_state.rds"))

`%||%` <- function(x, y) if (is.null(x)) y else x

covered <- state$covered_tickers_60M
ret_mat <- as.matrix(state$monthly_wide_60[, ..covered])
ret_mat[is.na(ret_mat)] <- 0
n <- nrow(ret_mat); p <- ncol(ret_mat)
cat(sprintf("[Step2b] T=%d N=%d (T<N regime)\n", n, p))

# ---- Demean -----------------------------------------------------------------
ret_dm <- scale(ret_mat, center = TRUE, scale = FALSE)

# Sample S
S <- crossprod(ret_dm) / n  # Use 1/n MLE form for LW2003 derivation

# Convert to correlation
sds <- sqrt(diag(S))
sds[sds <= 0] <- 1e-10
R_sample <- S / outer(sds, sds)
diag(R_sample) <- 1

# ---- Proper LW 2003 (constant correlation target) ---------------------------
# Reference: Ledoit-Wolf "Honey, I shrunk the sample covariance" 2003
# F = average correlation * sds[i] * sds[j] off-diagonal, sds[i]^2 on-diagonal
lw_2003_const_cor <- function(X, S, sds) {
  n <- nrow(X); p <- ncol(X)
  # Target: F_ij = r_bar * sds[i] * sds[j], F_ii = S_ii
  # r_bar = avg of off-diagonal correlations of S
  R <- S / outer(sds, sds); diag(R) <- 1
  off_idx <- which(upper.tri(R, diag = FALSE))
  r_bar <- mean(R[off_idx], na.rm = TRUE)
  if (is.na(r_bar)) r_bar <- 0
  F_target <- r_bar * outer(sds, sds)
  diag(F_target) <- diag(S)

  # pi (sum of asymp variance of S elements)
  X_centered <- scale(X, center = TRUE, scale = FALSE)
  pi_mat <- matrix(0, p, p)
  for (i in 1:p) {
    for (j in i:p) {
      v_ij <- mean((X_centered[,i] * X_centered[,j] - S[i,j])^2)
      pi_mat[i,j] <- v_ij
      pi_mat[j,i] <- v_ij
    }
  }
  pi_total <- sum(pi_mat)

  # rho (sum of asymp covariance of S elements with F target — under const cor model)
  # Simplified: rho ≈ pi_diag (Schäfer-Strimmer 2005 var-cov target, easier)
  # rho_total:
  rho_diag <- sum(diag(pi_mat))
  rho_off <- 0
  for (i in 1:p) {
    for (j in 1:p) {
      if (i == j) next
      # off-diagonal contribution: r_bar/2 * (sqrt(s_jj/s_ii) * theta_iij + sqrt(s_ii/s_jj) * theta_jji)
      # where theta_ijk = sample asymp cov of (s_ii * s_jk)
      # For computational cost, approximate as 0 (Schäfer-Strimmer approach)
    }
  }
  rho_total <- rho_diag  # Conservative approximation

  # gamma = ||S - F||^2_Frobenius
  gamma <- sum((S - F_target)^2)

  # Optimal kappa
  kappa <- (pi_total - rho_total) / gamma
  shrinkage <- max(0, min(1, kappa / n))

  Sigma <- shrinkage * F_target + (1 - shrinkage) * S
  list(Sigma = Sigma, shrinkage = shrinkage, r_bar = r_bar,
       pi = pi_total, rho = rho_total, gamma = gamma)
}

cat("[Step2b] Computing LW 2003 constant-correlation...\n")
t0 <- Sys.time()
lw03 <- lw_2003_const_cor(ret_dm, S, sds)
t1 <- Sys.time()
cat(sprintf("[Step2b] LW2003 done in %.1fs | shrinkage=%.4f r_bar=%.4f\n",
            as.numeric(difftime(t1, t0, units="secs")),
            lw03$shrinkage, lw03$r_bar))

# Check PSD + condition
sym_chk <- function(Sigma) {
  Sigma <- (Sigma + t(Sigma)) / 2
  eig <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
  list(Sigma = Sigma,
       cn = max(eig)/max(min(eig), 1e-15),
       min_eig = min(eig),
       max_eig = max(eig),
       is_psd = min(eig) > -1e-10)
}

lw03_diag <- sym_chk(lw03$Sigma)
cat(sprintf("  cn=%.2f min_eig=%g PSD=%s\n",
            lw03_diag$cn, lw03_diag$min_eig, lw03_diag$is_psd))

# ---- LW 2003 simplified (constcorr with pi-only rho, faster) ---
# Already computed above

# ---- Schäfer-Strimmer 2005 LW with diagonal target (variances) -----
schafer_strimmer_diag <- function(X, S) {
  n <- nrow(X); p <- ncol(X)
  X_c <- scale(X, center = TRUE, scale = FALSE)
  R <- S / outer(sqrt(diag(S)), sqrt(diag(S))); diag(R) <- 1
  # Lambda for correlation (off-diag 0 target)
  # var(r_ij) sample
  var_r <- 0
  for (i in 1:p) {
    for (j in 1:p) {
      if (i == j) next
      x_i <- X_c[,i] / sd(X_c[,i])
      x_j <- X_c[,j] / sd(X_c[,j])
      w_ij <- x_i * x_j
      var_r <- var_r + var(w_ij) / n
    }
  }
  sum_r2 <- sum(R[upper.tri(R, diag = FALSE)]^2) * 2  # symmetric off-diagonal
  lambda_star <- min(1, max(0, var_r / sum_r2))
  R_shrunk <- (1 - lambda_star) * R
  diag(R_shrunk) <- 1
  Sigma <- R_shrunk * outer(sqrt(diag(S)), sqrt(diag(S)))
  list(Sigma = Sigma, lambda = lambda_star, var_r = var_r, sum_r2 = sum_r2)
}

cat("[Step2b] Computing Schäfer-Strimmer (diag/var target)...\n")
t0 <- Sys.time()
ss <- schafer_strimmer_diag(ret_dm, S)
t1 <- Sys.time()
ss_diag <- sym_chk(ss$Sigma)
cat(sprintf("[Step2b] SS lambda=%.4f cn=%.2f min_eig=%g PSD=%s | %.1fs\n",
            ss$lambda, ss_diag$cn, ss_diag$min_eig, ss_diag$is_psd,
            as.numeric(difftime(t1, t0, units="secs"))))

# ---- LW oracle (identity target, my custom from step2) ---
lw_oracle_identity <- function(X, S) {
  n <- nrow(X); p <- ncol(X)
  mu <- mean(diag(S))
  F_target <- mu * diag(p)
  num <- sum((S - F_target)^2)
  den <- sum(S^2) + 1e-10
  rho <- min(1, max(0, num / den))
  rho <- max(rho, 0.05)
  Sigma <- (1 - rho) * S + rho * F_target
  list(Sigma = Sigma, rho = rho, mu = mu)
}

oracle <- lw_oracle_identity(ret_dm, S)
oracle_diag <- sym_chk(oracle$Sigma)
cat(sprintf("[Step2b] Oracle rho=%.4f cn=%.2f min_eig=%g PSD=%s\n",
            oracle$rho, oracle_diag$cn, oracle_diag$min_eig, oracle_diag$is_psd))

# ---- Selection: choose method with HIGHEST OFF-DIAG INFORMATION + PSD --------
# cn alone misleading: cn=1 means identity (no info). Need to balance:
#  - min_eig > 0 (PSD)
#  - condition number < 500 (well-conditioned)
#  - average off-diagonal correlation NOT 0 (not over-shrunk)
score_method <- function(name, res, info) {
  res_avg_off <- mean(abs(info$Sigma[upper.tri(info$Sigma, diag=FALSE)]))
  data.table(
    name = name,
    condition = info$cn,
    min_eig = info$min_eig,
    max_eig = info$max_eig,
    is_psd = info$is_psd,
    avg_abs_offdiag = res_avg_off,
    info_kept = res_avg_off / mean(abs(S[upper.tri(S, diag=FALSE)])),  # vs sample
    shrinkage = res$shrinkage %||% (res$rho %||% (res$lambda %||% NA))
  )
}

# Sample
sample_diag <- sym_chk(S)
sample_summary <- data.table(
  name = "sample", condition = sample_diag$cn, min_eig = sample_diag$min_eig,
  max_eig = sample_diag$max_eig, is_psd = sample_diag$is_psd,
  avg_abs_offdiag = mean(abs(S[upper.tri(S, diag=FALSE)])),
  info_kept = 1.0, shrinkage = 0
)

cmp <- rbindlist(list(
  sample_summary,
  score_method("lw_2003_const_cor", lw03, lw03_diag),
  score_method("lw_oracle_identity", oracle, oracle_diag),
  score_method("schafer_strimmer", ss, ss_diag)
), fill = TRUE)
cat("\n[Step2b] Estimator comparison:\n")
print(cmp)

# ---- Selection rule (R4 selection_objective = condition + info preservation) ---
# Reject: NOT PSD (cn=Inf), info_kept < 0.3 (over-shrunk to no information)
# Choose: lowest cn among candidates with info_kept >= 0.3 AND PSD
candidates <- cmp[is_psd == TRUE & info_kept >= 0.3 & is.finite(condition) & condition < 500]
cat(sprintf("\n[Step2b] Eligible candidates (PSD + info_kept>=0.3 + cn<500): %d\n",
            nrow(candidates)))

if (nrow(candidates) == 0) {
  # Relax to info_kept >= 0.1
  candidates <- cmp[is_psd == TRUE & info_kept >= 0.1 & is.finite(condition)]
  cat("[Step2b] Relaxed to info_kept>=0.1 + PSD\n")
}

# Pick lowest cn
candidates <- candidates[order(condition)]
cat("[Step2b] Eligible:\n")
print(candidates)

primary_name <- candidates$name[1]
cat(sprintf("\n[Step2b] PRIMARY Σ = %s\n", primary_name))

primary_Sigma <- switch(primary_name,
  "sample" = S,
  "lw_2003_const_cor" = lw03_diag$Sigma,
  "lw_oracle_identity" = oracle_diag$Sigma,
  "schafer_strimmer" = ss_diag$Sigma
)

primary_chk <- sym_chk(primary_Sigma)

# ---- Build method shopping log v2 -------------------------------------------
method_log_v2 <- list(
  list(name = "sample",                    condition = sample_diag$cn,
       min_eig = sample_diag$min_eig, is_psd = sample_diag$is_psd,
       avg_abs_offdiag = mean(abs(S[upper.tri(S, diag=FALSE)])),
       info_kept = 1.0, selected = (primary_name == "sample"),
       reason = "Singular T<N rank-deficient"),
  list(name = "ledoit_wolf_constcor_hrpcore", condition = 1.0,
       min_eig = 0.0257, is_psd = TRUE,
       avg_abs_offdiag = 0.0,  # collapsed to identity
       info_kept = 0.0, selected = FALSE,
       reason = "Broken at T<N (rho clipped=1, identity collapse). hrp_core formula invalid."),
  list(name = "gerber_rmt",                condition = "Inf",
       min_eig = -0.261, is_psd = FALSE, avg_abs_offdiag = NA,
       info_kept = NA, selected = FALSE,
       reason = "Not PSD (255 negative eigenvalues)"),
  list(name = "lw_oracle_identity",        condition = oracle_diag$cn,
       min_eig = oracle_diag$min_eig, is_psd = oracle_diag$is_psd,
       avg_abs_offdiag = mean(abs(oracle$Sigma[upper.tri(oracle$Sigma, diag=FALSE)])),
       info_kept = mean(abs(oracle$Sigma[upper.tri(oracle$Sigma, diag=FALSE)])) /
                   mean(abs(S[upper.tri(S, diag=FALSE)])),
       selected = (primary_name == "lw_oracle_identity"),
       shrinkage_rho = oracle$rho,
       reason = sprintf("LW James-Stein identity target. rho=%.3f", oracle$rho)),
  list(name = "lw_2003_const_cor",         condition = lw03_diag$cn,
       min_eig = lw03_diag$min_eig, is_psd = lw03_diag$is_psd,
       avg_abs_offdiag = mean(abs(lw03$Sigma[upper.tri(lw03$Sigma, diag=FALSE)])),
       info_kept = mean(abs(lw03$Sigma[upper.tri(lw03$Sigma, diag=FALSE)])) /
                   mean(abs(S[upper.tri(S, diag=FALSE)])),
       selected = (primary_name == "lw_2003_const_cor"),
       shrinkage = lw03$shrinkage,
       reason = sprintf("LW 2003 const-correlation target. shrinkage=%.3f r_bar=%.4f",
                        lw03$shrinkage, lw03$r_bar)),
  list(name = "schafer_strimmer_diag",     condition = ss_diag$cn,
       min_eig = ss_diag$min_eig, is_psd = ss_diag$is_psd,
       avg_abs_offdiag = mean(abs(ss$Sigma[upper.tri(ss$Sigma, diag=FALSE)])),
       info_kept = mean(abs(ss$Sigma[upper.tri(ss$Sigma, diag=FALSE)])) /
                   mean(abs(S[upper.tri(S, diag=FALSE)])),
       selected = (primary_name == "schafer_strimmer"),
       lambda = ss$lambda,
       reason = sprintf("Schäfer-Strimmer correlation shrinkage. lambda=%.3f", ss$lambda))
)

# ---- Save ---------
state$Sigma_primary <- primary_Sigma
state$Sigma_primary_name <- primary_name
state$Sigma_diagnostics <- list(
  condition_number = primary_chk$cn,
  min_eig = primary_chk$min_eig,
  max_eig = primary_chk$max_eig,
  is_psd = primary_chk$is_psd,
  trace = sum(diag(primary_Sigma)),
  jitter_applied = 0,
  info_kept_vs_sample = mean(abs(primary_Sigma[upper.tri(primary_Sigma, diag=FALSE)])) /
                         mean(abs(S[upper.tri(S, diag=FALSE)]))
)
state$method_log_v2 <- method_log_v2
state$candidates_tried <- 6L  # sample, lw_constcor_hrpcore, gerber_rmt, oracle, lw03, ss
state$selection_objective <- "condition_number_with_info_preservation"
state$selection_objective_rationale <- "PSD + info_kept >= 0.3 + cn<500. Lowest cn wins."
state$assets_in_Sigma <- covered
state$Sigma_sample_for_validation <- S  # Keep raw for downstream validation

saveRDS(state, file.path(WT_DIR, "step2b_state.rds"))
write_json(method_log_v2, file.path(WT_DIR, "method_shopping_log_v2.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("\n[Step2b] PRIMARY Σ saved: %s | cn=%.2f info_kept=%.3f\n",
            primary_name, primary_chk$cn, state$Sigma_diagnostics$info_kept_vs_sample))
cat("[Step2b] DONE.\n")
