#==============================================================================
# WT-D20260430_001 RISK PHASE — REVISE post-Codex R1
#
# Apply 5 ACCEPT + 2 REBUTTAL actions per risk_challenge_note.md:
#   C1 (PARTIAL): + Hill α / EVT-GPD / VaR_99 / ES_99
#   C3 (PARTIAL): + Degenerate BΩB'+D parquet stubs
#   C4 (ACCEPT):  4-bucket regime + bootstrap CI for CRISIS
#   C5 (REBUTTAL): + regime PIT lineage proof in package
#   C6 (PARTIAL):  + artifact_manifest
#   C7 (ACCEPT):  AX-008 downgrade to PARTIAL
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(arrow)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID <- "WT-D20260430_001"
WT_DIR <- file.path("qepm/mailbox/worktask", WT_ID)
OUT_DIR <- file.path(WT_DIR, "stage_artifacts")

set.seed(20260430L)

# ── Reload intermediate ──
ri <- readRDS(file.path(OUT_DIR, "risk_intermediate.rds"))

# Reload alpha_scores
ap <- as.data.table(read_parquet(file.path(OUT_DIR, "alpha_scores.parquet")))
setorder(ap, Date)

# Rebuild S1/S2/S3 returns (same as risk_run_all.R)
bt <- readRDS("04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/bt_result.rds")
pr_str <- as.data.table(bt$period_returns)[, .(Date = as.Date(date), str1715_ret = ret_net,
                                               turnover_str1715 = turnover)]
mtab <- merge(ap[, .(Date, ret_net, weight_str1715, weight_cash, Cash_Pct_lag,
                     combined_regime, MSM_Crisis_Prob_lag)],
              pr_str, by = "Date", all.x = TRUE)
mtab[, ret_S1 := str1715_ret]
mtab[is.na(ret_S1), ret_S1 := 0]
mtab[, weight_S2 := 1 - ifelse(is.na(Cash_Pct_lag), 0, Cash_Pct_lag)]
mtab[, ret_S2 := weight_S2 * str1715_ret]
mtab[, ret_S3 := weight_str1715 * str1715_ret]

# Daily-frequency returns approximation (for EVT/Hill we have only monthly; document caveat)
ret_S3 <- na.omit(mtab$ret_S3)
ret_S1 <- na.omit(mtab$ret_S1)
ret_S2 <- na.omit(mtab$ret_S2)

# ─── C1: Hill α / EVT-GPD / VaR_99 / ES_99 ──────────────────────────────────

cat("\n[C1 REVISE] Tail risk extension\n")

# Hill estimator (heavy-tail index)
# Hill (1975): α = k / Σ ln(X_(i) / X_(k+1)) for k upper order statistics
# We use lower tail = losses (-r > threshold)
hill_alpha <- function(r, k_frac = 0.10) {
  losses <- -r  # losses positive
  losses <- losses[losses > 0]
  n <- length(losses)
  if (n < 30) return(c(alpha = NA_real_, k = NA_integer_, threshold = NA_real_, n = n))
  losses_sorted <- sort(losses, decreasing = TRUE)
  k <- max(20L, floor(n * k_frac))
  k <- min(k, n - 1)
  thr <- losses_sorted[k + 1]
  if (thr <= 0) return(c(alpha = NA_real_, k = k, threshold = thr, n = n))
  log_ratios <- log(losses_sorted[1:k] / thr)
  alpha_hat <- k / sum(log_ratios)
  c(alpha = alpha_hat, k = k, threshold = thr, n = n)
}

hill_S1 <- hill_alpha(ret_S1, k_frac = 0.20)  # monthly only 267 obs, need more upper k
hill_S2 <- hill_alpha(ret_S2, k_frac = 0.20)
hill_S3 <- hill_alpha(ret_S3, k_frac = 0.20)

cat(sprintf("  Hill α (k_frac=0.20):\n"))
cat(sprintf("    S1: α=%.4f (k=%d, thr=%.4f, n=%d)\n", hill_S1["alpha"], hill_S1["k"], hill_S1["threshold"], hill_S1["n"]))
cat(sprintf("    S2: α=%.4f (k=%d, thr=%.4f, n=%d)\n", hill_S2["alpha"], hill_S2["k"], hill_S2["threshold"], hill_S2["n"]))
cat(sprintf("    S3: α=%.4f (k=%d, thr=%.4f, n=%d)\n", hill_S3["alpha"], hill_S3["k"], hill_S3["threshold"], hill_S3["n"]))
cat("    Interp: α > 2 → finite variance. α ∈ (2,4) → finite mean+var but heavy-tail.\n")

# EVT-GPD via fExtremes (or POT method directly)
# Pickands-Balkema-de Haan: excesses over threshold ~ GPD(ξ, β)
# Use Pickands method-of-moments for ξ
gpd_pot <- function(r, threshold_q = 0.85) {
  losses <- -r
  losses <- losses[losses > 0]
  n <- length(losses)
  if (n < 30) return(list(xi = NA_real_, beta = NA_real_, n_exceed = 0L, threshold = NA_real_))
  thr <- as.numeric(quantile(losses, threshold_q))
  excess <- losses[losses > thr] - thr
  if (length(excess) < 15) return(list(xi = NA_real_, beta = NA_real_, n_exceed = length(excess), threshold = thr))
  # Method of moments (simplified):
  # mean(excess) = β / (1-ξ)
  # var(excess)  = β^2 / ((1-ξ)^2 (1-2ξ))
  m <- mean(excess); s2 <- var(excess)
  if (s2 <= 0) return(list(xi = NA_real_, beta = NA_real_, n_exceed = length(excess), threshold = thr))
  # Solve: ξ = 0.5 (1 - m^2/s2)
  xi <- 0.5 * (1 - m^2 / s2)
  beta <- m * (1 - xi)
  list(xi = xi, beta = beta, n_exceed = length(excess), threshold = thr,
       n_total = n, exceed_rate = length(excess) / n)
}

gpd_S1 <- gpd_pot(ret_S1, threshold_q = 0.85)
gpd_S3 <- gpd_pot(ret_S3, threshold_q = 0.85)

cat(sprintf("  EVT-GPD (threshold_q=0.85, MoM):\n"))
cat(sprintf("    S1: ξ=%.4f β=%.4f (n_exceed=%d / %d)\n", gpd_S1$xi, gpd_S1$beta, gpd_S1$n_exceed, gpd_S1$n_total))
cat(sprintf("    S3: ξ=%.4f β=%.4f (n_exceed=%d / %d)\n", gpd_S3$xi, gpd_S3$beta, gpd_S3$n_exceed, gpd_S3$n_total))

# VaR_99 / ES_99
compute_var_es <- function(r, p = 0.99) {
  r <- na.omit(r)
  thr <- as.numeric(quantile(r, 1 - p))
  cvar <- mean(r[r <= thr])
  c(VaR = -thr, ES = -cvar)
}
var99_S1 <- compute_var_es(ret_S1, 0.99)
var99_S2 <- compute_var_es(ret_S2, 0.99)
var99_S3 <- compute_var_es(ret_S3, 0.99)
cat(sprintf("  VaR_99 / ES_99:\n"))
cat(sprintf("    S1: VaR_99=%.4f ES_99=%.4f\n", var99_S1["VaR"], var99_S1["ES"]))
cat(sprintf("    S2: VaR_99=%.4f ES_99=%.4f\n", var99_S2["VaR"], var99_S2["ES"]))
cat(sprintf("    S3: VaR_99=%.4f ES_99=%.4f\n", var99_S3["VaR"], var99_S3["ES"]))

# ─── C3: Degenerate BΩB'+D parquet stubs ────────────────────────────────────

cat("\n[C3 REVISE] Degenerate BΩB'+D decomposition\n")

# Universe = (STR_1715_SLEEVE, CASH_KRW)
# B (exposure, 2 × 1):
#   STR_1715_SLEEVE has unit exposure to STR_1715_factor
#   CASH_KRW has zero exposure
B_mat <- matrix(c(1, 0), nrow = 2, ncol = 1, dimnames = list(c("STR_1715_SLEEVE", "CASH_KRW"), c("STR_1715_factor")))

# Ω (factor covariance, 1 × 1) = var(STR_1715 monthly returns)
var_str <- var(ret_S1)
Omega_mat <- matrix(var_str, nrow = 1, ncol = 1, dimnames = list("STR_1715_factor", "STR_1715_factor"))

# D (specific risk, 2 × 2 diagonal) = idiosyncratic variance
# In this universe, factor IS the strategy; no residual idio for STR_1715. Cash variance = 0.
D_mat <- matrix(0, nrow = 2, ncol = 2, dimnames = list(c("STR_1715_SLEEVE", "CASH_KRW"), c("STR_1715_SLEEVE", "CASH_KRW")))

# Σ = BΩB' + D (2 × 2)
Sigma_2x2 <- B_mat %*% Omega_mat %*% t(B_mat) + D_mat
cat(sprintf("  B (2×1):\n"))
print(B_mat)
cat(sprintf("  Ω (1×1) = var(STR_1715) = %.6f\n", var_str))
cat(sprintf("  D (2×2 diag):\n"))
print(D_mat)
cat(sprintf("  Σ = BΩB' + D:\n"))
print(Sigma_2x2)
cat(sprintf("  Σ[STR_1715_SLEEVE, STR_1715_SLEEVE] = %.6f vs sample var(S1) = %.6f\n",
            Sigma_2x2[1,1], var_str))

# Save B / Ω / D parquets
B_dt <- as.data.table(B_mat); B_dt[, asset := rownames(B_mat)]; setcolorder(B_dt, c("asset", "STR_1715_factor"))
write_parquet(B_dt, file.path(OUT_DIR, "exposure_matrix.parquet"))

Omega_dt <- as.data.table(Omega_mat); Omega_dt[, factor := rownames(Omega_mat)]; setcolorder(Omega_dt, c("factor", "STR_1715_factor"))
write_parquet(Omega_dt, file.path(OUT_DIR, "factor_covariance.parquet"))

D_dt <- as.data.table(D_mat); D_dt[, asset := rownames(D_mat)]; setcolorder(D_dt, c("asset", colnames(D_mat)))
write_parquet(D_dt, file.path(OUT_DIR, "specific_risk.parquet"))

cat(sprintf("  → exposure_matrix.parquet, factor_covariance.parquet, specific_risk.parquet saved\n"))

# Factor coverage R²
# In degenerate case: by construction R² = 1.0 (factor IS the strategy)
factor_coverage_r2 <- 1.0
cat(sprintf("  Factor coverage R² = %.4f (degenerate: factor = strategy)\n", factor_coverage_r2))

# ─── C4: 4-bucket regime + bootstrap CI ─────────────────────────────────────

cat("\n[C4 REVISE] 4-bucket regime split + bootstrap CI\n")

# BULL: combined_regime <= 0.20
# NORMAL: 0.20 < combined_regime <= 0.40
# CAUTION: 0.40 < combined_regime <= 0.60
# CRISIS: combined_regime > 0.60

mtab[, regime_4 := fifelse(combined_regime <= 0.20, "BULL",
                   fifelse(combined_regime <= 0.40, "NORMAL",
                   fifelse(combined_regime <= 0.60, "CAUTION", "CRISIS")))]

regime_n <- mtab[!is.na(regime_4), .N, by = regime_4]
print(regime_n)

regime_4_rows <- list()
for (rg_name in c("BULL", "NORMAL", "CAUTION", "CRISIS")) {
  sub <- mtab[regime_4 == rg_name & !is.na(ret_S1)]
  n <- nrow(sub)
  if (n < 8) {
    regime_4_rows[[length(regime_4_rows) + 1]] <- list(
      regime = rg_name, n = n,
      var_S1 = NA_real_, var_S3 = NA_real_,
      cor_S3_S1 = NA_real_, vol_ratio_S3_S1 = NA_real_,
      cor_ci_lo = NA_real_, cor_ci_hi = NA_real_,
      vol_ratio_ci_lo = NA_real_, vol_ratio_ci_hi = NA_real_,
      mean_S1 = NA_real_, mean_S3 = NA_real_,
      fallback = "POOLED_NORMAL_CAUTION"
    )
    next
  }
  v1 <- var(sub$ret_S1); v3 <- var(sub$ret_S3)
  c31 <- cor(sub$ret_S3, sub$ret_S1)
  vol_ratio <- sqrt(v3 / v1)

  # Bootstrap 95% CI (B=1000)
  if (n >= 24) {
    B <- 1000L
    cor_boot <- numeric(B); vr_boot <- numeric(B)
    for (b in 1:B) {
      idx <- sample.int(n, n, replace = TRUE)
      cor_boot[b] <- cor(sub$ret_S3[idx], sub$ret_S1[idx])
      vr_boot[b] <- sqrt(var(sub$ret_S3[idx]) / var(sub$ret_S1[idx]))
    }
    cor_ci <- quantile(cor_boot, c(0.025, 0.975), na.rm = TRUE)
    vr_ci  <- quantile(vr_boot,  c(0.025, 0.975), na.rm = TRUE)
  } else {
    cor_ci <- c(NA_real_, NA_real_)
    vr_ci  <- c(NA_real_, NA_real_)
  }

  regime_4_rows[[length(regime_4_rows) + 1]] <- list(
    regime = rg_name, n = n,
    var_S1 = v1, var_S3 = v3,
    cor_S3_S1 = c31, vol_ratio_S3_S1 = vol_ratio,
    cor_ci_lo = unname(cor_ci[1]), cor_ci_hi = unname(cor_ci[2]),
    vol_ratio_ci_lo = unname(vr_ci[1]), vol_ratio_ci_hi = unname(vr_ci[2]),
    mean_S1 = mean(sub$ret_S1), mean_S3 = mean(sub$ret_S3),
    fallback = "none_required"
  )
}
regime_4_dt <- rbindlist(lapply(regime_4_rows, as.data.table), fill = TRUE)
print(regime_4_dt[, .(regime, n,
                     vol_S1 = round(sqrt(var_S1), 4),
                     vol_S3 = round(sqrt(var_S3), 4),
                     cor_S3_S1 = round(cor_S3_S1, 4),
                     vol_ratio = round(vol_ratio_S3_S1, 4),
                     vr_ci = sprintf("[%.3f, %.3f]", vol_ratio_ci_lo, vol_ratio_ci_hi),
                     fallback)])

write_parquet(regime_4_dt, file.path(OUT_DIR, "regime_4bucket.parquet"))
cat("  → regime_4bucket.parquet saved\n")

# Regime switch rate (estimated)
# Switch: regime_4 changes from one row to next
mtab[, regime_4_lag := shift(regime_4, 1L)]
n_switches <- sum(mtab$regime_4 != mtab$regime_4_lag, na.rm = TRUE)
n_obs_with_lag <- sum(!is.na(mtab$regime_4_lag) & !is.na(mtab$regime_4))
regime_switch_rate <- n_switches / n_obs_with_lag
cat(sprintf("  Regime switch rate (estimated): %.4f (= %d switches / %d months)\n",
            regime_switch_rate, n_switches, n_obs_with_lag))

# ─── Save revised intermediate ──────────────────────────────────────────────

ri_revise <- list(
  hill_S1 = hill_S1, hill_S2 = hill_S2, hill_S3 = hill_S3,
  gpd_S1 = gpd_S1, gpd_S3 = gpd_S3,
  var99_S1 = var99_S1, var99_S2 = var99_S2, var99_S3 = var99_S3,
  Sigma_2x2 = Sigma_2x2, B_mat = B_mat, Omega_mat = Omega_mat, D_mat = D_mat,
  factor_coverage_r2 = factor_coverage_r2,
  regime_4_dt = regime_4_dt,
  regime_switch_rate = regime_switch_rate
)
saveRDS(ri_revise, file.path(OUT_DIR, "risk_intermediate_revise.rds"))

cat("\n[REVISE] DONE — risk_intermediate_revise.rds saved\n")
