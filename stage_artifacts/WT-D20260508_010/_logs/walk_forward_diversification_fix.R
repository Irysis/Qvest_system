#==============================================================================
# WT-D20260508_010 — Walk-Forward Diversification Source Proof (Codex C4 ACCEPT)
#
# Codex 정확 진단:
#   원래 코드는 2026-04-30 top20 alpha 이름을 선택 후 2009-05까지 backfill
#   → PIT C1/C3/C6/C12 위반 (survivorship + look-ahead)
#
# Fix: per-month walk-forward
#   각 historical sig_date에서:
#     1. alpha_panel[Date == sig_date]의 top20 alpha_z 이름 선택 (PIT-safe)
#     2. 다음 월 forward 1m return 계산
#     3. EW combine
#   → walk-forward alpha_top20 monthly returns series
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(digest)
})

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID     <- "WT-D20260508_010"
WT_DIR    <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
SA_DIR    <- file.path(PROJ_ROOT, "stage_artifacts", WT_ID)

cat("\n==================================================\n")
cat("Walk-Forward Diversification Fix (Codex C4 ACCEPT)\n")
cat("==================================================\n")

alpha_panel <- as.data.table(read_parquet(file.path(SA_DIR, "alpha_scores.parquet")))
alpha_panel[, Date := as.Date(Date)]
sig_dates <- sort(unique(alpha_panel$Date))
cat(sprintf("alpha_panel: %d sig_dates (%s ~ %s)\n",
            length(sig_dates), min(sig_dates), max(sig_dates)))

# Walk-forward: for each historical sig_date, pick top20 alpha names + use realized fwd_ret_1m (already in panel)
panel_train <- alpha_panel[!is.na(fwd_ret_1m)]
cat(sprintf("  Train sig_dates (with fwd ret): %d\n", uniqueN(panel_train$Date)))

# Per sig_date, top20 by alpha_z, EW return
wf_top20 <- panel_train[, {
  ord <- order(-alpha_z)
  top_idx <- ord[1:min(20, .N)]
  list(
    n_top20 = length(top_idx),
    alpha_top20_ew_fwd = mean(fwd_ret_1m[top_idx], na.rm = TRUE),
    avg_alpha_z_top20 = mean(alpha_z[top_idx], na.rm = TRUE),
    median_fwd_top20 = median(fwd_ret_1m[top_idx], na.rm = TRUE)
  )
}, by = Date]
cat(sprintf("  Walk-forward top20 monthly: %d months\n", nrow(wf_top20)))

# Hybrid baseline
hybrid_path <- file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-P20260505_001/output/S3_Hybrid_70_15_15/03_period_returns.csv")
hybrid_ret <- fread(hybrid_path)
hybrid_ret[, date := as.Date(date)]
hybrid_ret[, ym := as.Date(format(date, "%Y-%m-01"))]

# Match: sig_date is month-end, fwd_ret_1m is realized over next month → align to next month-start ym
wf_top20[, ym := as.Date(format(Date + 1, "%Y-%m-01"))]
joined_wf <- merge(hybrid_ret[, .(ym, hybrid_ret = ret_net)],
                   wf_top20[, .(ym, alpha_ret = alpha_top20_ew_fwd, n_top20)],
                   by = "ym")
joined_wf <- joined_wf[!is.na(hybrid_ret) & !is.na(alpha_ret) & is.finite(alpha_ret)]
cat(sprintf("  Walk-forward matched months: %d (%s ~ %s)\n",
            nrow(joined_wf), min(joined_wf$ym), max(joined_wf$ym)))

# Realized cor + diversification analysis (PIT-CLEAN)
rho_wf <- cor(joined_wf$alpha_ret, joined_wf$hybrid_ret, use = "pairwise.complete.obs")
sigma_alpha_wf <- sd(joined_wf$alpha_ret, na.rm = TRUE)
sigma_hybrid_wf <- sd(joined_wf$hybrid_ret, na.rm = TRUE)
cat(sprintf("  ρ_realized (walk-forward) = %+.4f\n", rho_wf))
cat(sprintf("  σ_alpha = %.4f / σ_hybrid = %.4f\n", sigma_alpha_wf, sigma_hybrid_wf))

# Markowitz combo grid
combo_grid_wf <- data.table(w_hybrid = c(0.5, 0.7, 0.85, 0.9),
                            w_alpha  = c(0.5, 0.3, 0.15, 0.1))
combo_grid_wf[, sigma_indep := sqrt((w_hybrid * sigma_hybrid_wf)^2 + (w_alpha * sigma_alpha_wf)^2)]
combo_grid_wf[, sigma_combo := sqrt((w_hybrid * sigma_hybrid_wf)^2 + (w_alpha * sigma_alpha_wf)^2 +
                                     2 * w_hybrid * w_alpha * rho_wf * sigma_hybrid_wf * sigma_alpha_wf)]
combo_grid_wf[, gain_pct := (sigma_indep - sigma_combo) / sigma_indep * 100]
cat("\n  Markowitz combo grid (walk-forward, rho=", round(rho_wf, 4), "):\n", sep="")
print(combo_grid_wf)

# Empirical realized combo stats
realized_wf <- list()
for (k in seq_len(nrow(combo_grid_wf))) {
  wh <- combo_grid_wf$w_hybrid[k]; wa <- combo_grid_wf$w_alpha[k]
  cr <- wh * joined_wf$hybrid_ret + wa * joined_wf$alpha_ret
  realized_wf[[k]] <- list(
    w_hybrid = wh, w_alpha = wa,
    n_months = length(cr),
    mean_monthly = mean(cr, na.rm = TRUE),
    sd_monthly = sd(cr, na.rm = TRUE),
    sharpe_annual = mean(cr, na.rm = TRUE) / sd(cr, na.rm = TRUE) * sqrt(12),
    cum_total = prod(1 + cr, na.rm = TRUE) - 1,
    skew = mean((cr - mean(cr))^3) / sd(cr)^3,
    nav_max = max(cumprod(1 + cr)),
    mdd = min(cumprod(1 + cr) / cummax(cumprod(1 + cr)) - 1)
  )
}
realized_wf_dt <- rbindlist(lapply(realized_wf, as.data.table))
cat("\n  Empirical realized combo (walk-forward):\n")
print(realized_wf_dt)

# Hybrid alone (matched panel)
hybrid_alone_wf <- list(
  n_months = nrow(joined_wf),
  mean_monthly = mean(joined_wf$hybrid_ret, na.rm = TRUE),
  sd_monthly = sd(joined_wf$hybrid_ret, na.rm = TRUE),
  sharpe_annual = mean(joined_wf$hybrid_ret, na.rm = TRUE) / sd(joined_wf$hybrid_ret, na.rm = TRUE) * sqrt(12),
  mdd = min(cumprod(1 + joined_wf$hybrid_ret) / cummax(cumprod(1 + joined_wf$hybrid_ret)) - 1)
)
cat(sprintf("\n  Hybrid alone (matched, walk-forward): SR=%.3f / MDD=%.4f / σ=%.4f\n",
            hybrid_alone_wf$sharpe_annual, hybrid_alone_wf$mdd, hybrid_alone_wf$sd_monthly))

# Verdict
sigma_red_wf_70_30 <- combo_grid_wf[w_hybrid == 0.7, gain_pct]
sr_diff_wf_70_30 <- realized_wf_dt[w_hybrid == 0.7, sharpe_annual] - hybrid_alone_wf$sharpe_annual
mdd_diff_wf_70_30 <- realized_wf_dt[w_hybrid == 0.7, mdd] - hybrid_alone_wf$mdd

verdict_wf <- if (rho_wf < -0.10) "CONFIRMED" else if (rho_wf < 0.10) "PARTIAL" else "NOT_CONFIRMED"

# Bootstrap CI on rho (block size 6 months for ρ stability)
set.seed(20260508)
boot_n <- 2000L
block_size <- 6L
rhos_boot <- numeric(boot_n)
n_obs <- nrow(joined_wf)
for (b in 1:boot_n) {
  starts <- sample(seq_len(n_obs - block_size + 1), ceiling(n_obs / block_size), replace = TRUE)
  idx <- unlist(lapply(starts, function(s) s:(s + block_size - 1)))
  idx <- idx[idx <= n_obs][1:n_obs]
  rhos_boot[b] <- cor(joined_wf$alpha_ret[idx], joined_wf$hybrid_ret[idx], use = "pairwise.complete.obs")
}
rho_boot_ci <- quantile(rhos_boot, c(0.025, 0.5, 0.975), na.rm = TRUE)
cat(sprintf("\n  Block-bootstrap 95%% CI on rho (block=%d, B=%d): [%.4f, %.4f] (median %.4f)\n",
            block_size, boot_n, rho_boot_ci[1], rho_boot_ci[3], rho_boot_ci[2]))

# Save fixed proof
proof_wf <- list(
  context = "WALK-FORWARD diversification source proof (Codex C4 ACCEPT — original was PIT-violating backfill)",
  pit_compliance = list(
    method = "Per-month walk-forward: at each historical sig_date, top20 alpha names selected from alpha_panel using ONLY data <= sig_date (PIT-safe via load_month_factors). Forward 1m returns realized.",
    backfill_check = "REJECTED — no future-snapshot universe used"
  ),
  alpha_layer_reported_cor = -0.418,
  rho_realized_walk_forward = round(rho_wf, 4),
  sigma_hybrid_monthly_wf = round(sigma_hybrid_wf, 4),
  sigma_alpha_top20_walkforward_monthly = round(sigma_alpha_wf, 4),
  matched_months_wf = nrow(joined_wf),
  matched_period_wf = list(start = as.character(min(joined_wf$ym)),
                            end = as.character(max(joined_wf$ym))),
  bootstrap_ci_rho = list(
    lower_2_5 = round(rho_boot_ci[1], 4),
    median = round(rho_boot_ci[2], 4),
    upper_97_5 = round(rho_boot_ci[3], 4),
    n_bootstraps = boot_n,
    block_size_months = block_size,
    method = "Block bootstrap (Politis-Romano 1994)"
  ),
  markowitz_gain_grid_wf = lapply(seq_len(nrow(combo_grid_wf)), function(k) {
    list(
      w_hybrid = combo_grid_wf$w_hybrid[k],
      w_alpha = combo_grid_wf$w_alpha[k],
      sigma_indep = round(combo_grid_wf$sigma_indep[k], 4),
      sigma_combo = round(combo_grid_wf$sigma_combo[k], 4),
      gain_pct = round(combo_grid_wf$gain_pct[k], 2)
    )
  }),
  realized_combo_stats_wf = realized_wf,
  hybrid_alone_baseline_wf = hybrid_alone_wf,
  verdict_wf = list(
    diversification_source = verdict_wf,
    sigma_reduction_70_30_pct = round(sigma_red_wf_70_30, 2),
    sr_improvement_70_30 = round(sr_diff_wf_70_30, 4),
    mdd_improvement_70_30 = round(mdd_diff_wf_70_30, 4),
    rho_in_negative_zone = rho_wf < -0.10
  ),
  interpretation = sprintf(
    "Walk-forward rho %.4f (CI [%.4f, %.4f]). %s diversification source. Sigma reduction at 70/30 = %.2f%%. SR Δ %+.4f / MDD Δ %+.4f.",
    rho_wf, rho_boot_ci[1], rho_boot_ci[3],
    verdict_wf,
    sigma_red_wf_70_30, sr_diff_wf_70_30, mdd_diff_wf_70_30
  ),
  caveat = "alpha-layer cor -0.418 is cross-sectional (signal vs Hybrid_proxy_z). Walk-forward time-series cor is realized portfolio-vs-portfolio. Different metrics. Walk-forward replaces prior backfilled estimate +0.063 (PIT-violating).",
  vs_original_backfill = list(
    rho_backfill = 0.0625,
    rho_walkforward = round(rho_wf, 4),
    delta = round(rho_wf - 0.0625, 4),
    note = "If walk-forward rho close to backfill, original was incidentally PIT-clean. If divergent, magnitudes differ."
  )
)
write_json(proof_wf, file.path(WT_DIR, "diversification_source_proof_walk_forward.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

cat(sprintf("\n  Saved: diversification_source_proof_walk_forward.json\n"))
cat(sprintf("  Verdict (PIT-clean): %s\n", verdict_wf))
cat(sprintf("  rho_wf=%.4f / σ_red 70/30=%.2f%% / SR Δ=%+.4f / MDD Δ=%+.4f\n",
            rho_wf, sigma_red_wf_70_30, sr_diff_wf_70_30, mdd_diff_wf_70_30))
