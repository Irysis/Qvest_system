#==============================================================================
# WT-D20260502_001 Risk Research — Step 4: Tail Risk + TDC + STR_1715 cross-axis
#
# Q-Lead Directive #3:
#  STR_1715 returns Pearson cor 0.036 (alpha-research) — cross-validate via:
#  1. Pearson cor (re-derive)
#  2. Spearman cor (rank)
#  3. Kendall's tau
#  4. Lower-tail TDC (joint loss exceedance)
#  5. Crowding cor (ticker overlap weighted)
#  6. Regime-conditional cor (CRISIS / NORMAL split)
#
# Goal: Confirm Pearson 0.036 (TRUE diversifier) consistent across all axes.
#       If NOT, escalate as Risk concern.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ, "stage_artifacts/WT_D20260502_001/risk")
state <- readRDS(file.path(WT_DIR, "step3b_state.rds"))

`%||%` <- function(x, y) if (is.null(x)) y else x

# ---- Build alpha LS portfolio monthly returns (2008+ history) ---------------
# Use alpha_vector + monthly_wide_full (2008-now) to compute LS returns
covered_full_period <- state$covered_tickers_60M  # 336
monthly_wide_full <- state$monthly_wide_full
ym_full <- monthly_wide_full$YM
alpha_vec <- state$alpha_vector

# Use ALL alpha tickers (subset to those available in monthly_wide_full)
alpha_tickers_avail <- intersect(names(alpha_vec), names(monthly_wide_full)[-1])
cat(sprintf("[Step4] Alpha tickers available in monthly_wide_full: %d / %d\n",
            length(alpha_tickers_avail), length(alpha_vec)))

# Note: alpha_vector represents 2026-04-30 cross-section, NOT historical alpha.
# To compute LS portfolio return history, alpha-research already did this in
# ls_returns_inheritance_audit.csv. Read directly.
ls_audit <- fread(file.path(PROJ, "stage_artifacts/WT_D20260502_001/ls_returns_inheritance_audit.csv"))
cat(sprintf("[Step4] LS audit rows: %d cols=%s\n",
            nrow(ls_audit), paste(names(ls_audit), collapse=",")))

# ---- Load STR_1715 returns --------------------------------------------------
str1715_dt <- fread(file.path(PROJ,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"))
str1715_dt[, YM := format(as.Date(date), "%Y-%m")]
str1715_dt <- str1715_dt[, .(YM, STR1715_Ret = ret_net)]
cat(sprintf("[Step4] STR_1715 rows: %d range %s ~ %s\n",
            nrow(str1715_dt), min(str1715_dt$YM), max(str1715_dt$YM)))

# ---- Get alpha LS portfolio returns from ls_audit ---------------------------
# alpha-research saved as 'sig_date, alpha_ls_ret' typically
# Schema: ym, ls_ret, gated_ret, top_only_ret, def_C_bad, str1715_ret
alpha_history <- ls_audit[, .(YM = ym, Alpha_Ret = ls_ret,
                              Alpha_TopOnly = top_only_ret,
                              def_C_bad,
                              STR1715_Ret_From_Audit = str1715_ret)]
cat(sprintf("[Step4] Alpha history rows: %d (LS portfolio returns from audit)\n",
            nrow(alpha_history)))

# ---- Merge ---
joined <- merge(alpha_history, str1715_dt, by = "YM")
cat(sprintf("[Step4] Joined alpha+STR_1715: %d months\n", nrow(joined)))

# ---- Cross-validation Axis 1: Pearson, Spearman, Kendall --------------------
cor_pearson <- cor(joined$Alpha_Ret, joined$STR1715_Ret, method = "pearson")
cor_spearman <- cor(joined$Alpha_Ret, joined$STR1715_Ret, method = "spearman")
cor_kendall <- cor(joined$Alpha_Ret, joined$STR1715_Ret, method = "kendall")
cat(sprintf("[Step4] Pearson  r = %.4f\n", cor_pearson))
cat(sprintf("[Step4] Spearman r = %.4f\n", cor_spearman))
cat(sprintf("[Step4] Kendall  τ = %.4f\n", cor_kendall))

# ---- Cross-validation Axis 2: Lower-tail dependence coefficient (TDC) -------
# TDC = lim_{u->0} P(X<=F_X^-1(u) | Y<=F_Y^-1(u))
# Empirical: Joe-Clayton with quantile threshold (e.g., 10th percentile)
compute_lower_tdc <- function(x, y, q = 0.10) {
  qx <- quantile(x, q, na.rm = TRUE)
  qy <- quantile(y, q, na.rm = TRUE)
  joint_below <- sum(x <= qx & y <= qy, na.rm = TRUE)
  marginal_below_x <- sum(x <= qx, na.rm = TRUE)
  if (marginal_below_x == 0) return(NA)
  joint_below / marginal_below_x
}

ltdc_10 <- compute_lower_tdc(joined$Alpha_Ret, joined$STR1715_Ret, 0.10)
ltdc_05 <- compute_lower_tdc(joined$Alpha_Ret, joined$STR1715_Ret, 0.05)
ltdc_20 <- compute_lower_tdc(joined$Alpha_Ret, joined$STR1715_Ret, 0.20)
cat(sprintf("[Step4] Lower-tail TDC (q=0.10): %.4f\n", ltdc_10))
cat(sprintf("[Step4] Lower-tail TDC (q=0.05): %.4f\n", ltdc_05))
cat(sprintf("[Step4] Lower-tail TDC (q=0.20): %.4f\n", ltdc_20))

# Upper-tail TDC for completeness
compute_upper_tdc <- function(x, y, q = 0.90) {
  qx <- quantile(x, q, na.rm = TRUE)
  qy <- quantile(y, q, na.rm = TRUE)
  joint_above <- sum(x >= qx & y >= qy, na.rm = TRUE)
  marginal_above_x <- sum(x >= qx, na.rm = TRUE)
  if (marginal_above_x == 0) return(NA)
  joint_above / marginal_above_x
}
utdc_90 <- compute_upper_tdc(joined$Alpha_Ret, joined$STR1715_Ret, 0.90)
cat(sprintf("[Step4] Upper-tail TDC (q=0.90): %.4f\n", utdc_90))

# ---- Cross-validation Axis 3: Regime-conditional cor ------------------------
# Use FRED MRS p70 split (alpha used Definition_C MRS expanding p70)
# Alternative: split by VIX or simply by KOSPI drawdown periods
# Simpler approach: split monthly_full into "BAD" (top 30% loss months) and NORMAL
joined[, is_bad_kospi := STR1715_Ret <= quantile(STR1715_Ret, 0.30, na.rm = TRUE)]
cor_pearson_bad <- cor(joined[is_bad_kospi == TRUE]$Alpha_Ret,
                        joined[is_bad_kospi == TRUE]$STR1715_Ret)
cor_pearson_normal <- cor(joined[is_bad_kospi == FALSE]$Alpha_Ret,
                           joined[is_bad_kospi == FALSE]$STR1715_Ret)
cat(sprintf("[Step4] Regime-conditional cor:\n"))
cat(sprintf("  bad_30pct (n=%d):    %.4f\n",
            sum(joined$is_bad_kospi), cor_pearson_bad))
cat(sprintf("  normal_70pct (n=%d): %.4f\n",
            sum(!joined$is_bad_kospi), cor_pearson_normal))

# ---- Cross-validation Axis 4: Crowding cor (ticker overlap weighted) ---------
# STR_1715 holdings vs alpha portfolio at 2026-04-30
# Read STR_1715 latest holdings
str1715_holdings <- fread(file.path(PROJ,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/production_weights/20260501_weights_cap_0p20.csv"))
cat(sprintf("[Step4] STR_1715 holdings cols: %s\n",
            paste(names(str1715_holdings), collapse=",")))

# Identify ticker col
ticker_col_str1715 <- intersect(c("Ticker", "ticker", "Code"), names(str1715_holdings))
weight_col_str1715 <- intersect(c("weight", "Weight", "w_final"), names(str1715_holdings))
if (length(ticker_col_str1715) == 0 || length(weight_col_str1715) == 0) {
  cat("[Step4] STR_1715 holdings preview:\n")
  print(head(str1715_holdings, 3))
  stop("Cannot identify ticker/weight columns in STR_1715 holdings")
}
str1715_w <- str1715_holdings[[weight_col_str1715[1]]]
names(str1715_w) <- str1715_holdings[[ticker_col_str1715[1]]]
cat(sprintf("[Step4] STR_1715 holdings: %d names, sum_w=%.4f\n",
            length(str1715_w), sum(str1715_w)))

# Alpha vector top-20 by score (proxy for what optimizer might select)
alpha_sorted <- sort(state$alpha_vector, decreasing = TRUE)
top20_alpha_tickers <- names(head(alpha_sorted, 20))
str1715_tickers <- names(str1715_w)

overlap_top20_alpha_str1715 <- length(intersect(top20_alpha_tickers, str1715_tickers))
overlap_pct <- overlap_top20_alpha_str1715 / 20
cat(sprintf("[Step4] Top20 alpha vs STR_1715 holdings overlap: %d/20 (%.1f%%)\n",
            overlap_top20_alpha_str1715, overlap_pct * 100))

# Alpha-weighted overlap (continuous)
common_tickers <- intersect(names(state$alpha_vector), names(str1715_w))
overlap_continuous <- 0
for (t in common_tickers) {
  if (state$alpha_vector[t] > 0) {  # only positive alpha (long bias)
    overlap_continuous <- overlap_continuous + abs(state$alpha_vector[t]) * abs(str1715_w[t])
  }
}
cat(sprintf("[Step4] Continuous alpha-weighted overlap: %.6f\n", overlap_continuous))

# ---- Tail risk: portfolio CVaR if equal-weighted long top alpha -------------
# Simulate top-20 alpha portfolio CVaR using historical returns
top20_returns <- monthly_wide_full[, c("YM", top20_alpha_tickers), with = FALSE]
# Remove NA rows
top20_complete <- top20_returns[, colSums(is.na(top20_returns[, -1])) <= 0, with = FALSE]
top20_mat <- as.matrix(top20_returns[, -1])
top20_mat[is.na(top20_mat)] <- 0
ew_returns <- rowMeans(top20_mat)
cvar_99 <- mean(ew_returns[ew_returns <= quantile(ew_returns, 0.01)])
cvar_95 <- mean(ew_returns[ew_returns <= quantile(ew_returns, 0.05)])
var_99 <- quantile(ew_returns, 0.01)
var_95 <- quantile(ew_returns, 0.05)
cat(sprintf("[Step4] Top20 EW alpha portfolio CVaR/VaR (monthly):\n"))
cat(sprintf("  VaR(99%%) = %.4f | CVaR(99%%) = %.4f\n", var_99, cvar_99))
cat(sprintf("  VaR(95%%) = %.4f | CVaR(95%%) = %.4f\n", var_95, cvar_95))

# ---- AX-001 v2 axis 1: crisis_alpha measurement ---
# Compare alpha portfolio bad-state return vs STR_1715 bad-state return
crisis_alpha_pa <- mean(joined[is_bad_kospi == TRUE]$Alpha_Ret) -
                    mean(joined[is_bad_kospi == TRUE]$STR1715_Ret)
crisis_alpha_pa_annual <- crisis_alpha_pa * 12
cat(sprintf("[Step4] Crisis alpha (avg bad-state monthly): %.4f (%.2f%% annualized)\n",
            crisis_alpha_pa, crisis_alpha_pa_annual * 100))

# ---- Save state -------------------------------------------------------------
state$str1715_cor_validation <- list(
  pearson = cor_pearson,
  spearman = cor_spearman,
  kendall = cor_kendall,
  alpha_research_reported_pearson = 0.0361,
  pearson_consistency_check_pass = abs(cor_pearson - 0.0361) < 0.01,
  ltdc_10 = ltdc_10,
  ltdc_05 = ltdc_05,
  ltdc_20 = ltdc_20,
  utdc_90 = utdc_90,
  cor_bad_30pct = cor_pearson_bad,
  cor_normal_70pct = cor_pearson_normal,
  n_overlap_months = nrow(joined),
  crisis_alpha_monthly = crisis_alpha_pa,
  crisis_alpha_annualized = crisis_alpha_pa_annual,
  ax001_v2_axis1_crisis_alpha_positive = crisis_alpha_pa > 0,
  ax001_v2_axis2_anti_correlated = cor_pearson < -0.10  # threshold
)

state$str1715_crowding_validation <- list(
  top20_overlap_count = overlap_top20_alpha_str1715,
  top20_overlap_pct = overlap_pct,
  continuous_alpha_str1715_overlap = overlap_continuous,
  str1715_n_holdings = length(str1715_w),
  str1715_holdings_concentration_max_w = max(str1715_w)
)

state$tail_risk <- list(
  top20_ew_cvar_99 = cvar_99,
  top20_ew_cvar_95 = cvar_95,
  top20_ew_var_99 = var_99,
  top20_ew_var_95 = var_95,
  ew_returns_n_obs = length(ew_returns)
)

# Add to RF flags
if (cor_pearson > 0.50) {
  state$rf_flags[[length(state$rf_flags) + 1]] <- list(
    flag_id = "RF-R-CROSS-1", severity = "HIGH",
    description = sprintf("STR_1715 cross-validation: Pearson cor %.3f > 0.50, alpha NOT a true diversifier", cor_pearson))
}
if (overlap_pct > 0.50) {
  state$rf_flags[[length(state$rf_flags) + 1]] <- list(
    flag_id = "RF-R-CROSS-2", severity = "HIGH",
    description = sprintf("Top20 alpha and STR_1715 holdings overlap %d/20 (%.1f%%) > 50%% (crowding)",
                          overlap_top20_alpha_str1715, overlap_pct * 100))
}
if (cor_pearson_bad > 0.40) {
  state$rf_flags[[length(state$rf_flags) + 1]] <- list(
    flag_id = "RF-R-CROSS-3", severity = "MEDIUM",
    description = sprintf("Bad-regime cor %.3f — diversification fails when most needed", cor_pearson_bad))
}
if (ltdc_10 > 0.5) {
  state$rf_flags[[length(state$rf_flags) + 1]] <- list(
    flag_id = "RF-R-CROSS-4", severity = "HIGH",
    description = sprintf("Lower-tail TDC %.3f > 0.50, joint loss likely in tail", ltdc_10))
}

saveRDS(state, file.path(WT_DIR, "step4_state.rds"))
cat("[Step4] DONE.\n")
