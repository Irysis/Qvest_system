#==============================================================================
# WT-D20260502_001 Risk Research — Step 2c: Finalize Σ with cn target ≤ 500
#
# Step 2b: LW2003 const-cor info_kept=95.8% but cn=1300 > 500 hard threshold
# Solution: blend LW2003 with diagonal shrinkage (Tikhonov)
#  Σ_final = (1 - alpha) * Σ_LW2003 + alpha * diag(Σ_LW2003)
# Find min alpha such that cn(Σ_final) <= 400 (margin of safety)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ, "stage_artifacts/WT_D20260502_001/risk")
state <- readRDS(file.path(WT_DIR, "step2b_state.rds"))

`%||%` <- function(x, y) if (is.null(x)) y else x

Sigma_lw03 <- state$Sigma_primary
S <- state$Sigma_sample_for_validation

# ---- Apply additional Tikhonov to get cn <= 400 -----------------------------
# Note: T<<N regime intrinsically forces high shrinkage. Honest tradeoff:
#  cn target 400 (our target) requires alpha ~0.6 -> info_kept ~40%
#  cn 500 (system threshold) with maximal info ~ alpha=0.55, info_kept=44%
#  Strategy: choose alpha minimizing alpha + lambda * (cn / target - 1)^2
target_cn <- 400
alphas <- seq(0.0, 0.95, by = 0.02)
diag_target <- diag(diag(Sigma_lw03))

results <- data.table(alpha = alphas, cn = NA_real_, min_eig = NA_real_, info_kept = NA_real_)
S_offdiag <- S[upper.tri(S, diag=FALSE)]
ref_offdiag <- mean(abs(S_offdiag))

for (i in seq_along(alphas)) {
  a <- alphas[i]
  Sigma_test <- (1 - a) * Sigma_lw03 + a * diag_target
  Sigma_test <- (Sigma_test + t(Sigma_test)) / 2
  eig <- eigen(Sigma_test, symmetric = TRUE, only.values = TRUE)$values
  results[i, cn := max(eig) / max(min(eig), 1e-15)]
  results[i, min_eig := min(eig)]
  test_offdiag <- Sigma_test[upper.tri(Sigma_test, diag=FALSE)]
  results[i, info_kept := mean(abs(test_offdiag)) / ref_offdiag]
}

cat("[Step2c] Tikhonov alpha sweep:\n")
print(results)

# Find smallest alpha such that cn <= target_cn
eligible <- results[cn <= target_cn & min_eig > 1e-8]
if (nrow(eligible) == 0) {
  alpha_star <- max(alphas)
} else {
  alpha_star <- eligible$alpha[1]
}
cat(sprintf("\n[Step2c] Selected alpha = %.3f (cn target = %d)\n", alpha_star, target_cn))

Sigma_final <- (1 - alpha_star) * Sigma_lw03 + alpha_star * diag_target
Sigma_final <- (Sigma_final + t(Sigma_final)) / 2

# Final diagnostics
eig_final <- eigen(Sigma_final, symmetric = TRUE, only.values = TRUE)$values
final_cn <- max(eig_final) / max(min(eig_final), 1e-15)
final_min_eig <- min(eig_final)
final_offdiag <- Sigma_final[upper.tri(Sigma_final, diag=FALSE)]
final_info_kept <- mean(abs(final_offdiag)) / ref_offdiag

cat(sprintf("[Step2c] FINAL Σ: cn=%.1f min_eig=%g info_kept=%.3f PSD=%s\n",
            final_cn, final_min_eig, final_info_kept,
            final_min_eig > -1e-10))

# ---- Save -------------------------------------------------------------------
state$Sigma_primary <- Sigma_final
state$Sigma_primary_name <- "lw_2003_const_cor_tikhonov"
state$Sigma_diagnostics <- list(
  condition_number = final_cn,
  min_eig = final_min_eig,
  max_eig = max(eig_final),
  is_psd = final_min_eig > -1e-10,
  trace = sum(diag(Sigma_final)),
  jitter_applied = 0,
  tikhonov_alpha = alpha_star,
  info_kept_vs_sample = final_info_kept,
  base_method = "lw_2003_const_cor",
  base_shrinkage_lw = 0.7865,
  base_r_bar = 0.2112
)
state$tikhonov_alpha = alpha_star
saveRDS(state, file.path(WT_DIR, "step2c_state.rds"))
cat("[Step2c] DONE.\n")
