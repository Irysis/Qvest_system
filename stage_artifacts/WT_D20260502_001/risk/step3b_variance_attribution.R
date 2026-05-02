#==============================================================================
# WT-D20260502_001 Risk Research — Step 3b: Proper variance attribution
#
# Step 3 had non-additive factor variance contributions (each factor independent).
# Use Euler decomposition (or marginal contributions) for additive attribution:
#  σ² = sum over k of: B_k' * Omega_k * B_k where B_k is the k-th column of B
#  But systematic = trace(B Ω B') = sum over k,l: tr(B_k B_l') * Omega[k,l]
#                  = sum over k,l: (B_k . B_l) * Omega[k,l]
#
# Per-factor attribution (correlated factors): use Cholesky orthogonalization
# OR sequential R² (Type I sum of squares).
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ, "stage_artifacts/WT_D20260502_001/risk")
state <- readRDS(file.path(WT_DIR, "step3_state.rds"))

`%||%` <- function(x, y) if (is.null(x)) y else x

B <- state$exposure_matrix_B
Omega <- state$factor_covariance_Omega
F_mat <- state$factor_returns_F
factor_cols <- state$factor_names
covered <- rownames(B)

# ---- Cross-sectional approach: attribute variance via factor index ----------
# For each asset, decompose total systematic variance using:
#   var(BF) = B' Ω B (1 x 1 scalar for vector-valued)
# Per-factor contribution at asset level:
#   contrib_k(asset_i) = B_i,k * Σ_l (B_i,l * Ω[k,l])
#  i.e. B_i' * Ω_k where Ω_k is column k of Omega — covariance of factor k with all factors

# Universe-wide (mean across assets) average attribution
asset_total_systematic <- diag(B %*% Omega %*% t(B))

# Per-factor average contribution
n_assets <- nrow(B)
per_factor_avg_contrib <- numeric(ncol(B))
for (k in seq_along(factor_cols)) {
  # contribution of factor k to asset i: B[i,k] * sum_l(B[i,l] * Omega[k,l])
  contrib_per_asset <- B[, k] * (B %*% Omega[, k])
  per_factor_avg_contrib[k] <- mean(contrib_per_asset)
}
names(per_factor_avg_contrib) <- factor_cols

# Total per-asset systematic
total_per_asset_avg <- mean(asset_total_systematic)
factor_var_pct_additive <- per_factor_avg_contrib / total_per_asset_avg
cat(sprintf("[Step3b] Sum factor pct: %.4f (should be 1.0)\n",
            sum(factor_var_pct_additive)))

# ---- Now standardize as percentage ---
top_factors_dt2 <- data.table(Factor = factor_cols,
                               Var_Pct_Additive = round(factor_var_pct_additive * 100, 2),
                               Avg_Beta = round(colMeans(B), 3),
                               Beta_StdDev = round(apply(B, 2, sd), 3))
top_factors_dt2 <- top_factors_dt2[order(-Var_Pct_Additive)]
cat("[Step3b] Additive variance attribution (top 8):\n")
print(head(top_factors_dt2, 8))

# Total specific risk percentage
asset_total_var <- diag(state$Sigma_factor_model)  # B Ω B' + D
asset_specific <- state$specific_risk_D
total_specific_pct <- mean(asset_specific / asset_total_var) * 100
total_systematic_pct <- 100 - total_specific_pct
cat(sprintf("[Step3b] Avg variance: Systematic=%.1f%% Specific=%.1f%%\n",
            total_systematic_pct, total_specific_pct))

# ---- Group factors: Market / Size / Sector ---
group_pct <- list(
  Market = factor_var_pct_additive["BM_Ret_Monthly"],
  Size_SMB = factor_var_pct_additive["SMB"],
  Sector_Total = sum(factor_var_pct_additive[!names(factor_var_pct_additive) %in% c("BM_Ret_Monthly", "SMB")])
)
group_pct$Specific = total_specific_pct / 100  # relative to total var
# Renormalize systematic to fraction of total var
sys_frac <- total_systematic_pct / 100
group_pct_total <- list(
  Market = group_pct$Market * sys_frac,
  Size_SMB = group_pct$Size_SMB * sys_frac,
  Sector_Total = group_pct$Sector_Total * sys_frac,
  Specific = group_pct$Specific
)
cat("\n[Step3b] Group attribution (% of total variance):\n")
for (g in names(group_pct_total)) {
  cat(sprintf("  %s: %.1f%%\n", g, group_pct_total[[g]] * 100))
}

# ---- Top common risks (group + top sectors) ---------------------------------
# Format: "Market (35%)", "Sector_IT (12%)" etc
top_common_risks <- list()
top_common_risks[[length(top_common_risks) + 1]] <-
  sprintf("Market %.1f%%", group_pct_total$Market * 100)
top_common_risks[[length(top_common_risks) + 1]] <-
  sprintf("Size_SMB %.1f%%", group_pct_total$Size_SMB * 100)

# Top 5 sectors
sector_factors <- factor_var_pct_additive[!names(factor_var_pct_additive) %in% c("BM_Ret_Monthly", "SMB")]
sector_factors_sorted <- sort(sector_factors, decreasing = TRUE)
for (i in seq_len(min(5, length(sector_factors_sorted)))) {
  fname <- names(sector_factors_sorted)[i]
  pct <- sector_factors_sorted[i] * sys_frac
  top_common_risks[[length(top_common_risks) + 1]] <-
    sprintf("Sector_%s %.1f%%", fname, pct * 100)
}

cat("\n[Step3b] Top common risks:\n")
for (r in top_common_risks) cat("  ", r, "\n")

# ---- RF-R1 check ---
market_pct <- group_pct_total$Market * 100
rfr1_violation <- market_pct > 40
cat(sprintf("\n[Step3b] RF-R1 (Market > 40%%): %s (%.1f%%)\n",
            ifelse(rfr1_violation, "VIOLATED", "OK"), market_pct))

# ---- Save updated state ---
state$factor_var_pct_additive <- factor_var_pct_additive
state$group_pct <- group_pct_total
state$top_common_risks_v2 <- top_common_risks
state$avg_R_squared_systematic <- mean(state$factor_R2$per_asset, na.rm = TRUE)
state$total_systematic_pct <- total_systematic_pct
state$total_specific_pct <- total_specific_pct

# RF flags
state$rf_flags <- list()
if (rfr1_violation) {
  state$rf_flags[[length(state$rf_flags) + 1]] <- list(
    flag_id = "RF-R1", severity = "HIGH",
    description = sprintf("Market exposure %.1f%% > 40%% threshold (universe-level top common risk)",
                          market_pct))
}

saveRDS(state, file.path(WT_DIR, "step3b_state.rds"))
cat("[Step3b] DONE.\n")
