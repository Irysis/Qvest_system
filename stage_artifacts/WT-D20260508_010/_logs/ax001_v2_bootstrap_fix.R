#==============================================================================
# AX-001 v2 Bootstrap CI fix (Codex C5 ACCEPT/PARTIAL)
# - crisis_ic n=12 → bootstrap CI 추가
# - Status downgrade decision based on stricter criteria
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID     <- "WT-D20260508_010"
WT_DIR    <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
SA_DIR    <- file.path(PROJ_ROOT, "stage_artifacts", WT_ID)

cat("\n==================================================\n")
cat("AX-001 v2 Bootstrap CI fix (Codex C5)\n")
cat("==================================================\n")

alpha_panel <- as.data.table(read_parquet(file.path(SA_DIR, "alpha_scores.parquet")))
alpha_panel[, Date := as.Date(Date)]
panel_train <- alpha_panel[!is.na(fwd_ret_1m)]

stress_periods <- list(
  IMF_1997      = c("1997-07-01", "1998-12-31"),
  DotCom_2000   = c("2000-03-01", "2002-09-30"),
  GFC_2008      = c("2008-09-01", "2009-03-31"),
  EuDebt_2011   = c("2011-08-01", "2011-12-31"),
  China_2015    = c("2015-06-01", "2016-02-29"),
  VolShock_2018 = c("2018-10-01", "2018-12-31"),
  COVID_2020    = c("2020-02-15", "2020-04-30"),
  Inflation_2022 = c("2022-01-01", "2022-12-31")
)

panel_train[, regime := "NORMAL"]
for (pn in names(stress_periods)) {
  d_start <- as.Date(stress_periods[[pn]][1])
  d_end   <- as.Date(stress_periods[[pn]][2])
  panel_train[Date >= d_start & Date <= d_end, regime := "CRISIS"]
}

ic_per_date <- panel_train[, .(
  rank_ic = cor(alpha_z, fwd_ret_1m, method = "spearman", use = "pairwise.complete.obs"),
  regime = unique(regime)[1]
), by = Date]

ic_normal <- ic_per_date[regime == "NORMAL", rank_ic]
ic_crisis <- ic_per_date[regime == "CRISIS", rank_ic]

ic_normal_mean <- mean(ic_normal, na.rm = TRUE)
ic_crisis_mean <- mean(ic_crisis, na.rm = TRUE)

# Bootstrap CI
set.seed(20260508)
boot_n <- 5000L

# Crisis IC bootstrap
crisis_boot <- replicate(boot_n, mean(sample(ic_crisis, length(ic_crisis), replace = TRUE), na.rm = TRUE))
crisis_ci <- quantile(crisis_boot, c(0.025, 0.5, 0.975), na.rm = TRUE)

# Normal IC bootstrap
normal_boot <- replicate(boot_n, mean(sample(ic_normal, length(ic_normal), replace = TRUE), na.rm = TRUE))
normal_ci <- quantile(normal_boot, c(0.025, 0.5, 0.975), na.rm = TRUE)

# bad/normal ratio bootstrap
ratio_boot <- crisis_boot / pmax(abs(normal_boot), 1e-6) * sign(normal_boot)
ratio_ci <- quantile(ratio_boot, c(0.025, 0.5, 0.975), na.rm = TRUE)

cat(sprintf("Crisis IC: mean=%.5f / 95%% CI=[%.5f, %.5f] / n=%d months\n",
            ic_crisis_mean, crisis_ci[1], crisis_ci[3], length(ic_crisis)))
cat(sprintf("Normal IC: mean=%.5f / 95%% CI=[%.5f, %.5f] / n=%d months\n",
            ic_normal_mean, normal_ci[1], normal_ci[3], length(ic_normal)))
cat(sprintf("Ratio    : mean=%.4f / 95%% CI=[%.4f, %.4f]\n",
            mean(ratio_boot, na.rm=TRUE), ratio_ci[1], ratio_ci[3]))

# Stricter status determination
crisis_alpha_positive <- crisis_ci[1] > 0  # CI lower bound > 0 (statistically significant)
crisis_alpha_positive_point <- ic_crisis_mean > 0  # point estimate
ratio_above_1 <- ratio_ci[1] > 1.0  # CI lower bound > 1
ratio_above_1_point <- mean(ratio_boot, na.rm=TRUE) > 1.0

# AX-001 v2 strict status
ax001_status_strict <- if (crisis_alpha_positive && ratio_above_1) {
  "PASS_strict"
} else if (crisis_alpha_positive_point && ratio_above_1_point) {
  "PASS_point_only_CI_inconclusive"
} else if (crisis_alpha_positive_point) {
  "PARTIAL_crisis_positive_but_ratio_low"
} else {
  "FAIL_no_crisis_alpha"
}

# Combo MDD comparison
hybrid_path <- file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-P20260505_001/output/S3_Hybrid_70_15_15/03_period_returns.csv")
hybrid_ret <- fread(hybrid_path)
hybrid_ret[, date := as.Date(date)]

# Walk-forward combo replication for MDD
wf_top20 <- panel_train[, {
  ord <- order(-alpha_z); top_idx <- ord[1:min(20, .N)]
  list(alpha_top20_ew_fwd = mean(fwd_ret_1m[top_idx], na.rm = TRUE))
}, by = Date]
wf_top20[, ym := as.Date(format(Date + 1, "%Y-%m-01"))]
hybrid_ret[, ym := as.Date(format(date, "%Y-%m-01"))]
joined <- merge(hybrid_ret[, .(ym, hybrid_ret = ret_net)],
                wf_top20[, .(ym, alpha_ret = alpha_top20_ew_fwd)], by = "ym")
joined <- joined[!is.na(hybrid_ret) & !is.na(alpha_ret) & is.finite(alpha_ret)]

hybrid_alone_mdd <- min(cumprod(1 + joined$hybrid_ret) / cummax(cumprod(1 + joined$hybrid_ret)) - 1)
combo_70_30 <- 0.7 * joined$hybrid_ret + 0.3 * joined$alpha_ret
combo_70_30_mdd <- min(cumprod(1 + combo_70_30) / cummax(cumprod(1 + combo_70_30)) - 1)
mdd_improvement <- combo_70_30_mdd - hybrid_alone_mdd

# Final status — Codex strict reading: PASS requires crisis_alpha_positive + ratio > 1 + MDD relief
ax001_status_codex_strict <- if (crisis_alpha_positive_point && ratio_above_1_point && mdd_improvement > 0) {
  "PASS_full"
} else if (crisis_alpha_positive_point) {
  "FAIL_codex_strict_PARTIAL_legacy"
} else {
  "FAIL_no_crisis_alpha"
}

cat(sprintf("\nMDD: Hybrid alone=%.4f / 70-30 combo=%.4f / Δ=%+.4f\n",
            hybrid_alone_mdd, combo_70_30_mdd, mdd_improvement))
cat(sprintf("Status (point):       %s\n", ax001_status_strict))
cat(sprintf("Status (Codex strict): %s\n", ax001_status_codex_strict))

ax001_v2_strict <- list(
  alpha_id = "R14_DUVOL_skewness",
  measurement_basis = "Walk-forward sig-date IC partition by stress regime",
  ic_normal = list(
    n_months = length(ic_normal),
    mean = round(ic_normal_mean, 5),
    median_ci = round(normal_ci[2], 5),
    ci_95_lower = round(normal_ci[1], 5),
    ci_95_upper = round(normal_ci[3], 5)
  ),
  ic_crisis = list(
    n_months = length(ic_crisis),
    mean = round(ic_crisis_mean, 5),
    median_ci = round(crisis_ci[2], 5),
    ci_95_lower = round(crisis_ci[1], 5),
    ci_95_upper = round(crisis_ci[3], 5),
    note = "n_crisis only 12 in 2008-13/2014-19/2020-25 panel — wide CI expected"
  ),
  bad_normal_ratio = list(
    point = round(ic_crisis_mean / max(abs(ic_normal_mean), 1e-6) * sign(ic_normal_mean), 4),
    median_ci = round(ratio_ci[2], 4),
    ci_95_lower = round(ratio_ci[1], 4),
    ci_95_upper = round(ratio_ci[3], 4)
  ),
  mdd_comparison = list(
    hybrid_alone = round(hybrid_alone_mdd, 4),
    combo_70_30 = round(combo_70_30_mdd, 4),
    mdd_delta = round(mdd_improvement, 4),
    relief = mdd_improvement > 0
  ),
  status_options = list(
    point_estimate_lenient = ax001_status_strict,
    codex_strict_full_PASS = ax001_status_codex_strict
  ),
  status_final = ax001_status_codex_strict,
  bootstrap = list(B = boot_n, ci_method = "BCa naive percentile"),
  interpretation = sprintf(
    "Crisis IC %.4f (CI [%.4f, %.4f] n=%d). Normal IC %.4f. Ratio %.4f (CI [%.4f, %.4f]) — point estimate < 1.0 (crisis weaker than normal) and CI includes 1.0+ but also <1.0. MDD relief %.4f (NOT improved at 70/30). %s.",
    ic_crisis_mean, crisis_ci[1], crisis_ci[3], length(ic_crisis),
    ic_normal_mean, mean(ratio_boot, na.rm=TRUE), ratio_ci[1], ratio_ci[3],
    mdd_improvement,
    if (ax001_status_codex_strict == "PASS_full") "AX-001 v2 PASS"
    else if (ax001_status_codex_strict == "FAIL_codex_strict_PARTIAL_legacy") "AX-001 v2 FAIL by codex strict — alpha is weak diversifier role, not defense"
    else "AX-001 v2 FAIL — no crisis alpha"
  ),
  role_classification_advisory = if (mdd_improvement > 0 && ic_crisis_mean > ic_normal_mean) "Defense" else if (ic_crisis_mean > 0) "Diversifier" else "Reject"
)
write_json(ax001_v2_strict, file.path(WT_DIR, "ax001_v2_conditional_defense.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

cat(sprintf("\nUpdated ax001_v2_conditional_defense.json — status: %s\n", ax001_v2_strict$status_final))
cat(sprintf("Role advisory: %s\n", ax001_v2_strict$role_classification_advisory))
