#==============================================================================
# WT-D20260502_001 Risk Research — Step 5: Stress Tests + Regime Correlation
#
# 8 reference stress periods (def_stress_periods from strategy_analyzer.R:498):
#  Terror_9_11 / GFC / Euro_Debt / China_Shock / US_China_Trade /
#  COVID / Rate_Hike / Iran_War (2026-02~04)
#
# For each period: Top20 EW alpha portfolio cumulative return + MDD
# + STR_1715 same period for comparison
#
# Regime correlation: Compute Σ in CRISIS vs NORMAL months.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ, "stage_artifacts/WT_D20260502_001/risk")
state <- readRDS(file.path(WT_DIR, "step4_state.rds"))

`%||%` <- function(x, y) if (is.null(x)) y else x

# ---- Load daily RAWDATA returns for daily-level stress test analysis ---------
RAWDATA <- as.data.table(read_parquet(file.path(PROJ, ".cache/rawdata.parquet")))

# Top20 alpha tickers (long bias)
alpha_sorted <- sort(state$alpha_vector, decreasing = TRUE)
top20_alpha_tickers <- names(head(alpha_sorted, 20))
cat(sprintf("[Step5] Top20 tickers: %s\n", paste(head(top20_alpha_tickers, 5), collapse=",")))

# Daily returns of top20 (long history)
top20_daily <- RAWDATA[Ticker %in% top20_alpha_tickers, .(Date, Ticker, Ret)]
top20_wide <- dcast(top20_daily, Date ~ Ticker, value.var = "Ret")

# EW daily portfolio return (treating absent as 0)
top20_mat <- as.matrix(top20_wide[, -1])
top20_mat[is.na(top20_mat)] <- 0
ew_daily <- rowMeans(top20_mat)
ew_dt <- data.table(Date = top20_wide$Date, EW_Ret = ew_daily)
setkey(ew_dt, Date)
cat(sprintf("[Step5] Top20 EW daily portfolio: %d days, %s ~ %s\n",
            nrow(ew_dt), min(ew_dt$Date), max(ew_dt$Date)))

# BM daily
bm_daily <- unique(RAWDATA[!is.na(BM_Ret), .(Date, BM_Ret)])
setkey(bm_daily, Date)

# Merge
joined_daily <- merge(ew_dt, bm_daily, by = "Date")

# ---- 8 Stress periods --------------------------------------------------------
stress_periods <- list(
  list(name = "Terror_9_11",     start = "2001-09-01", end = "2001-12-31"),
  list(name = "GFC_2008",        start = "2007-10-01", end = "2009-03-31"),
  list(name = "Euro_Debt_2011",  start = "2011-07-01", end = "2011-12-31"),
  list(name = "China_Shock_2015",start = "2015-06-01", end = "2016-02-29"),
  list(name = "US_China_Trade",  start = "2018-03-01", end = "2018-12-31"),
  list(name = "COVID_2020",      start = "2020-01-01", end = "2020-06-30"),
  list(name = "Rate_Hike_2022",  start = "2022-01-01", end = "2022-12-31"),
  list(name = "Iran_War_2026",   start = "2026-02-01", end = "2026-04-30")
)

# Helper functions
compute_mdd <- function(rets) {
  cumret <- cumprod(1 + rets)
  drawdown <- cumret / cummax(cumret) - 1
  min(drawdown, na.rm = TRUE)
}

compute_period_metrics <- function(rets) {
  if (length(rets) < 5) return(list(cum_ret = NA, mdd = NA, vol = NA, n = length(rets)))
  list(
    cum_ret = prod(1 + rets, na.rm = TRUE) - 1,
    mdd = compute_mdd(rets),
    vol = sd(rets, na.rm = TRUE) * sqrt(252),
    n = length(rets)
  )
}

# Per-period metrics
stress_results <- list()
for (sp in stress_periods) {
  s <- as.Date(sp$start)
  e <- as.Date(sp$end)
  sub <- joined_daily[Date >= s & Date <= e]
  ew_metrics <- compute_period_metrics(sub$EW_Ret)
  bm_metrics <- compute_period_metrics(sub$BM_Ret)
  alpha_excess <- (ew_metrics$cum_ret %||% NA) - (bm_metrics$cum_ret %||% NA)
  stress_results[[sp$name]] <- list(
    start = sp$start, end = sp$end,
    n_days = ew_metrics$n,
    portfolio_ret = round(ew_metrics$cum_ret * 100, 2),
    portfolio_mdd = round(ew_metrics$mdd * 100, 2),
    portfolio_vol_ann = round(ew_metrics$vol * 100, 2),
    benchmark_ret = round(bm_metrics$cum_ret * 100, 2),
    benchmark_mdd = round(bm_metrics$mdd * 100, 2),
    excess_ret = round(alpha_excess * 100, 2),
    outperform = !is.na(alpha_excess) && alpha_excess > 0
  )
}

cat("[Step5] Stress test results (Top20 EW alpha portfolio):\n")
sr_dt <- rbindlist(lapply(names(stress_results), function(n) {
  r <- stress_results[[n]]
  data.table(Period = n, Days = r$n_days,
             Port_Ret = r$portfolio_ret, Port_MDD = r$portfolio_mdd,
             BM_Ret = r$benchmark_ret, BM_MDD = r$benchmark_mdd,
             Excess = r$excess_ret, Outperf = r$outperform)
}))
print(sr_dt)

# ---- Market down 5% scenario (1-month conditional) --------------------------
# Compute alpha portfolio expected return when market down 5% in a month
# Using conditional regression: alpha = β_market * market + intercept
alpha_monthly <- state$str1715_cor_validation
# Using monthly returns from joined data
monthly_joined <- merge(
  data.table(YM = format(joined_daily$Date, "%Y-%m"),
             EW_Ret = joined_daily$EW_Ret, BM_Ret = joined_daily$BM_Ret)[
             , .(EW_M = prod(1 + EW_Ret) - 1, BM_M = prod(1 + BM_Ret) - 1), by = YM
             ],
  state$monthly_wide_60[, .(YM)], by = "YM"
)
# Beta to BM
beta_market <- cov(monthly_joined$EW_M, monthly_joined$BM_M) /
               var(monthly_joined$BM_M)
intercept_market <- mean(monthly_joined$EW_M) - beta_market * mean(monthly_joined$BM_M)
market_down_5_loss <- intercept_market + beta_market * (-0.05)
cat(sprintf("[Step5] Market beta = %.3f, intercept = %.4f\n",
            beta_market, intercept_market))
cat(sprintf("[Step5] Market_down_5: portfolio expected loss = %.4f (%.2f%%)\n",
            market_down_5_loss, market_down_5_loss * 100))

# Value crash scenario: assume value factor down 5%, beta to value
# Using SMB beta from factor model
B_mat <- state$exposure_matrix_B
# Value crash proxy: monthly worst-decile of SMB
smb_worst <- min(state$factor_returns_F[, "SMB"], na.rm = TRUE)
mean_smb_beta <- mean(B_mat[top20_alpha_tickers[top20_alpha_tickers %in% rownames(B_mat)], "SMB"], na.rm = TRUE)
value_crash_loss <- mean_smb_beta * smb_worst
cat(sprintf("[Step5] Value crash (SMB beta=%.3f, SMB worst=%.4f): %.4f\n",
            mean_smb_beta, smb_worst, value_crash_loss))

# Momentum reversal: monthly worst-decile of momentum proxy
# We don't have explicit momentum factor; use semiconductor sector worst (proxy for 'momentum darling')
sem_factor_worst <- min(state$factor_returns_F[, "반도체"], na.rm = TRUE)
mean_sem_beta <- mean(B_mat[top20_alpha_tickers[top20_alpha_tickers %in% rownames(B_mat)], "반도체"], na.rm = TRUE)
momentum_reversal_loss <- mean_sem_beta * sem_factor_worst
cat(sprintf("[Step5] Semiconductor crash (β=%.3f, worst=%.4f): %.4f\n",
            mean_sem_beta, sem_factor_worst, momentum_reversal_loss))

# ---- Regime correlation matrix (CRISIS vs NORMAL) ----------------------------
ls_audit <- state$str1715_cor_validation
joined_alpha <- fread(file.path(PROJ, "stage_artifacts/WT_D20260502_001/ls_returns_inheritance_audit.csv"))

# Use def_C_bad as regime tag
regime_dt <- joined_alpha[, .(YM = ym, def_C_bad, ls_ret)]
state_monthly <- as.data.table(state$monthly_wide_60)
covered <- state$covered_tickers_60M

# Only compute when monthly data available + n_obs sufficient
state_long <- melt(state_monthly, id.vars = "YM", variable.name = "Ticker",
                    value.name = "Ret", variable.factor = FALSE)
state_long <- state_long[Ticker %in% covered]

# Regime tag: from FRED MRS p70 (use simpler proxy: bad_30pct months from joined data)
# OR use joined_alpha def_C_bad. Limit to months where regime tag exists
state_long_with_regime <- merge(state_long, regime_dt[, .(YM, def_C_bad)], by = "YM", all.x = TRUE)
state_long_with_regime[is.na(def_C_bad), def_C_bad := FALSE]

# Crisis cor: only use months where def_C_bad == TRUE
crisis_months <- sort(unique(state_long_with_regime[def_C_bad == TRUE]$YM))
normal_months <- sort(unique(state_long_with_regime[def_C_bad == FALSE]$YM))
cat(sprintf("[Step5] CRISIS months: %d | NORMAL months: %d\n",
            length(crisis_months), length(normal_months)))

# For computational efficiency, compute mean cor in each regime
compute_mean_offdiag_cor <- function(monthly_wide_dt, ym_subset, ticker_list) {
  sub <- monthly_wide_dt[YM %in% ym_subset, c("YM", ticker_list), with = FALSE]
  if (nrow(sub) < 5) return(NA)
  mat <- as.matrix(sub[, -1])
  mat[is.na(mat)] <- 0
  cor_mat <- cor(mat, use = "pairwise.complete.obs")
  cor_mat[is.na(cor_mat)] <- 0
  off_diag <- cor_mat[upper.tri(cor_mat, diag = FALSE)]
  list(mean = mean(off_diag, na.rm = TRUE),
       median = median(off_diag, na.rm = TRUE),
       max = max(off_diag, na.rm = TRUE))
}

# Use ALL 336 covered tickers for the full regime cor matrix would be too heavy
# Subsample to reasonable size: top 50 by absolute alpha
top_for_regime <- names(sort(abs(unlist(state$alpha_vector)), decreasing = TRUE))
top_for_regime <- intersect(top_for_regime, covered)[1:50]

cor_crisis <- compute_mean_offdiag_cor(state$monthly_wide_60, crisis_months, top_for_regime)
cor_normal <- compute_mean_offdiag_cor(state$monthly_wide_60, normal_months, top_for_regime)
cat(sprintf("[Step5] Regime cor matrix (top50 alpha):\n"))
cat(sprintf("  CRISIS  mean=%.3f median=%.3f max=%.3f\n",
            cor_crisis$mean, cor_crisis$median, cor_crisis$max))
cat(sprintf("  NORMAL  mean=%.3f median=%.3f max=%.3f\n",
            cor_normal$mean, cor_normal$median, cor_normal$max))
regime_cor_shift <- cor_crisis$mean - cor_normal$mean
cat(sprintf("  Regime SHIFT: cor_crisis - cor_normal = %.3f (positive = correlation breakdown)\n",
            regime_cor_shift))

# ---- Save state -------------------------------------------------------------
state$stress_results <- stress_results
state$stress_results_dt <- sr_dt

state$stress_scenarios <- list(
  market_down_5_loss = market_down_5_loss,
  market_beta = beta_market,
  market_intercept = intercept_market,
  value_crash_loss = value_crash_loss,
  smb_beta_avg_top20 = mean_smb_beta,
  semiconductor_crash_loss = momentum_reversal_loss,
  semi_beta_avg_top20 = mean_sem_beta
)

state$regime_correlation <- list(
  crisis = cor_crisis,
  normal = cor_normal,
  regime_shift = regime_cor_shift,
  n_crisis_months = length(crisis_months),
  n_normal_months = length(normal_months)
)

# RF flag check on stress
if (market_down_5_loss < -0.08) {
  state$rf_flags[[length(state$rf_flags) + 1]] <- list(
    flag_id = "RF-R4", severity = "HIGH",
    description = sprintf("Market_down_5 expected loss %.2f%% < -8%%", market_down_5_loss * 100))
}

# Save regime correlation matrix as parquet (using top50 + 2 regimes)
regime_cor_dt <- data.table(
  Regime = c("CRISIS", "NORMAL"),
  Mean_OffDiag_Cor = c(cor_crisis$mean, cor_normal$mean),
  Median_OffDiag_Cor = c(cor_crisis$median, cor_normal$median),
  Max_OffDiag_Cor = c(cor_crisis$max, cor_normal$max),
  N_Months = c(length(crisis_months), length(normal_months))
)
write_parquet(regime_cor_dt, file.path(WT_DIR, "regime_correlation.parquet"))

saveRDS(state, file.path(WT_DIR, "step5_state.rds"))
cat("[Step5] DONE.\n")
