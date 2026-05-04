#==============================================================================
# WT-S20260504_002 — Step 4: Tail risk + 8 stress periods + AX-001 v2 metric
#
# Inputs : str1715_monthly_returns.parquet, sigma_p_forecast.csv
# Outputs: tail_risk.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(evir); library(fExtremes)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-S20260504_002"
SA <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID))
DIR_DBG <- file.path(SA, "_debug")

cat("[Step 4] Tail risk + stress — START\n")

# ─── Load STR_1715 268m returns ──────────────────────────────────────────
str_ret <- as.data.table(read_parquet(file.path(SA, "str1715_monthly_returns.parquet")))
setorder(str_ret, date)
T_m <- nrow(str_ret)
ret_x <- xts(str_ret$ret_net, order.by = str_ret$date)
ret_g <- xts(str_ret$ret_gross, order.by = str_ret$date)

# ─── 1. Standard tail risk (PerformanceAnalytics) ─────────────────────────
es95 <- as.numeric(PerformanceAnalytics::ES(ret_x, p = 0.95, method = "historical"))
es99 <- as.numeric(PerformanceAnalytics::ES(ret_x, p = 0.99, method = "historical"))
var95 <- as.numeric(PerformanceAnalytics::VaR(ret_x, p = 0.95, method = "historical"))
var99 <- as.numeric(PerformanceAnalytics::VaR(ret_x, p = 0.99, method = "historical"))
mdd_full <- as.numeric(maxDrawdown(ret_x))
sortino <- as.numeric(SortinoRatio(ret_x))
calmar <- as.numeric(CalmarRatio(ret_x))
ann_vol <- as.numeric(StdDev.annualized(ret_x))
cat(sprintf("[Step 4] ES95=%.4f ES99=%.4f VaR95=%.4f VaR99=%.4f\n", es95, es99, var95, var99))
cat(sprintf("[Step 4] MDD=%.4f Sortino=%.3f Calmar=%.3f AnnVol=%.4f\n",
            mdd_full, sortino, calmar, ann_vol))

# ─── 2. EVT-GPD POT (Pfaff Ch.7) ─────────────────────────────────────────
losses <- -as.numeric(ret_x)  # work with losses
threshold_pct <- 0.90
threshold_val <- quantile(losses, threshold_pct)
gpd_fit <- tryCatch({
  evir::gpd(losses, threshold = threshold_val)
}, error = function(e) NULL)

evt_summary <- list(threshold_pct = threshold_pct,
                    threshold_value = as.numeric(threshold_val))
if (!is.null(gpd_fit)) {
  xi <- as.numeric(gpd_fit$par.ests["xi"])
  beta_gpd <- as.numeric(gpd_fit$par.ests["beta"])
  evt_summary$xi <- xi
  evt_summary$beta <- beta_gpd
  evt_summary$n_excesses <- as.integer(gpd_fit$n.exceed)
  evt_summary$shape_se <- as.numeric(gpd_fit$par.ses["xi"])
  cat(sprintf("[Step 4] GPD fit: xi=%.4f, beta=%.6f, n_excesses=%d\n",
              xi, beta_gpd, gpd_fit$n.exceed))
} else {
  evt_summary$status <- "GPD_FIT_FAILED"
}

# Hill estimator (Pfaff Ch.7)
hill_k <- min(40L, max(20L, floor(T_m * 0.10)))  # ~k between 20 and 40
sorted_losses <- sort(losses, decreasing = TRUE)
top_k <- sorted_losses[seq_len(hill_k)]
threshold_hill <- sorted_losses[hill_k + 1L]
if (threshold_hill > 0) {
  hill_alpha <- 1 / mean(log(top_k / threshold_hill))
} else {
  hill_alpha <- NA_real_
}
cat(sprintf("[Step 4] Hill alpha (k=%d): %.4f (lower = heavier tail)\n", hill_k, hill_alpha))

# ─── 3. 8 stress periods (KR + global) ────────────────────────────────────
stress_periods <- list(
  list(name = "Terror_9_11",    start = "2001-09-01", end = "2001-12-31"),
  list(name = "GFC",            start = "2007-10-01", end = "2009-03-31"),
  list(name = "Euro_Debt",      start = "2011-07-01", end = "2011-12-31"),
  list(name = "China_Shock",    start = "2015-06-01", end = "2016-02-29"),
  list(name = "US_China_Trade", start = "2018-03-01", end = "2018-12-31"),
  list(name = "COVID",          start = "2020-01-01", end = "2020-06-30"),
  list(name = "Rate_Hike",      start = "2022-01-01", end = "2022-12-31"),
  list(name = "Iran_War_2026",  start = "2026-02-01", end = "2026-04-30")
)

stress_results <- vector("list", length(stress_periods))
for (i in seq_along(stress_periods)) {
  sp <- stress_periods[[i]]
  s <- as.Date(sp$start); e <- as.Date(sp$end)
  r <- ret_x[paste0(s, "/", e)]
  if (length(r) < 2L) {
    stress_results[[i]] <- list(name = sp$name, start = sp$start, end = sp$end,
                                n_obs = length(r), cum_ret = NA_real_, mdd = NA_real_,
                                note = "out_of_sample_or_too_few_obs")
  } else {
    cum_ret <- prod(1 + as.numeric(r)) - 1
    mdd_p <- as.numeric(maxDrawdown(r))
    stress_results[[i]] <- list(
      name = sp$name, start = sp$start, end = sp$end,
      n_obs = length(r),
      cum_ret = round(cum_ret, 6),
      mdd = round(mdd_p, 6),
      worst_month = round(min(as.numeric(r)), 6)
    )
    cat(sprintf("[Step 4] Stress %s: n=%d, cum=%.4f, mdd=%.4f\n",
                sp$name, length(r), cum_ret, mdd_p))
  }
}

# ─── 4. AX-001 v2 conditional metric: bad/normal realized risk ratio by σ_p quantile ──
# Use sigma_p_forecast quantile state (CRISIS = top 33%, NORMAL = mid 33%, BULL = bottom 33%)
sf <- fread(file.path(SA, "sigma_p_forecast.csv"))
sf[, regime_state := fcase(
  is.na(sigma_p_annual_forecast), NA_character_,
  sigma_p_annual_forecast >= quantile(sigma_p_annual_forecast, 0.667, na.rm=TRUE), "CRISIS",
  sigma_p_annual_forecast <= quantile(sigma_p_annual_forecast, 0.333, na.rm=TRUE), "BULL",
  default = "NORMAL"
)]
ax001_metric <- sf[!is.na(regime_state), .(
  n = .N,
  realized_ret_mean = mean(strategy_ret_net),
  realized_ret_sd = sd(strategy_ret_net) * sqrt(12),
  realized_mdd_proxy = -min(strategy_ret_net),
  pct_negative_months = mean(strategy_ret_net < 0)
), by = regime_state]
cat("[Step 4] AX-001 v2 conditional metric by DCC σ_p regime state:\n")
print(ax001_metric)

# Bad vs Normal realized risk ratio
bad_sd <- ax001_metric[regime_state == "CRISIS", realized_ret_sd]
norm_sd <- ax001_metric[regime_state == "NORMAL", realized_ret_sd]
bad_norm_ratio <- if (length(bad_sd) == 1L && length(norm_sd) == 1L) bad_sd / norm_sd else NA_real_
cat(sprintf("[Step 4] AX-001 v2 bad/normal realized risk ratio: %.4f\n", bad_norm_ratio))

# ─── 5. Save ──────────────────────────────────────────────────────────────
tail_risk <- list(
  source = "STR_1715 268m monthly net returns",
  T_months = T_m,
  date_range = list(start = as.character(min(str_ret$date)),
                    end = as.character(max(str_ret$date))),
  full_sample = list(
    var_95_historical = var95,
    var_99_historical = var99,
    es_95_historical = es95,
    es_99_historical = es99,
    mdd_full = mdd_full,
    sortino = sortino,
    calmar = calmar,
    annualized_vol = ann_vol
  ),
  evt_gpd = evt_summary,
  hill = list(
    k = hill_k,
    alpha = as.numeric(hill_alpha),
    interpretation = "alpha < 4 = heavy tails, alpha < 2 = no finite variance"
  ),
  stress_periods = stress_results,
  ax_001_v2_conditional_metric = list(
    state_definition = "DCC σ_p_annual_forecast quantile: BULL <= 33%, NORMAL 33-67%, CRISIS >= 67%",
    by_state = lapply(seq_len(nrow(ax001_metric)), function(i) as.list(ax001_metric[i])),
    bad_normal_realized_risk_ratio = as.numeric(bad_norm_ratio),
    interpretation = "bad/normal > 1 expected (CRISIS = high vol). Question is whether bad-state realized return remains tolerable per AX-001 v2."
  ),
  cvar_breach_flag = es95 < -0.20,
  policy_thresholds = list(
    cvar_breach_threshold = -0.20,
    mdd_target_pp = -0.25,
    cagr_floor = 0.20
  )
)
write_json(tail_risk, file.path(SA, "tail_risk.json"),
           pretty = TRUE, auto_unbox = TRUE)

write_json(list(
  step = "04_tail_risk_stress",
  status = if (!is.null(gpd_fit) && length(stress_results) == 8L) "PASS" else "WARN",
  T_m = T_m,
  es95 = es95, mdd = mdd_full,
  hill_alpha = as.numeric(hill_alpha),
  stress_periods_n = length(stress_results),
  cvar_breach_flag = es95 < -0.20,
  ax001_bad_normal_ratio = as.numeric(bad_norm_ratio)
), file.path(DIR_DBG, "step04_tail_risk.json"),
   pretty = TRUE, auto_unbox = TRUE)

cat("[Step 4] DONE\n")
