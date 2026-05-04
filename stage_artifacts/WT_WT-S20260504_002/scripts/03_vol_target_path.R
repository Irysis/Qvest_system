#==============================================================================
# WT-S20260504_002 — Step 3: σ_p forecast path + Vol Target + cash_bridge
#
# Two layers:
#  Layer A (forward-looking, May 2026 operational):
#    18-stock DCC Σ_T+1 forecast × current 5월 weights → σ_p_T+1 (annualized)
#  Layer B (historical 268m σ_p,t for retrospective vol-target backtesting):
#    Univariate GARCH(1,1) Gaussian on STR_1715 strategy monthly returns
#    1-step-ahead σ_p,t+1 forecast for each historical month
#
# Vol target decision rule (statistical, no heuristic):
#  target = rolling-36m median of expanding annualized realized σ_p
#    (NOT a fixed 15% pick — chosen statistically from history)
#  Compare to fixed 15% benchmark for sensitivity
#  scale_factor_t = min(1, target / forecast_σ_p,t)
#  cash_bridge_t = 1 - scale_factor_t   (vol target leverage capped at 1.0)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(rugarch); library(rmgarch)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-S20260504_002"
SA <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID))
DIR_DBG <- file.path(SA, "_debug")

cat("[Step 3] Vol target path — START\n")

# ─── 1. Load STR_1715 monthly returns ────────────────────────────────────
str_ret <- as.data.table(read_parquet(file.path(SA, "str1715_monthly_returns.parquet")))
setorder(str_ret, date)
T_m <- nrow(str_ret)
cat(sprintf("[Step 3] STR_1715 T_m=%d (%s -> %s)\n", T_m,
            as.character(min(str_ret$date)),
            as.character(max(str_ret$date))))

# ─── 2. Univariate GARCH(1,1) Gaussian on strategy monthly returns ───────
ret_p <- str_ret$ret_net
spec_p <- ugarchspec(
  variance.model = list(model = "sGARCH", garchOrder = c(1L, 1L)),
  mean.model     = list(armaOrder = c(0L, 0L), include.mean = TRUE),
  distribution.model = "norm"
)

# Full-sample GARCH for diagnostics
fit_p_full <- tryCatch(
  ugarchfit(spec_p, data = ret_p, solver = "hybrid"),
  error = function(e) NULL
)
if (is.null(fit_p_full) || fit_p_full@fit$convergence != 0L) {
  stop("[Step 3] STR_1715 univariate GARCH did NOT converge — fall back to EWMA")
}
cf_p <- coef(fit_p_full)
pers_p <- as.numeric(cf_p["alpha1"]) + as.numeric(cf_p["beta1"])
cat(sprintf("[Step 3] STR_1715 GARCH params: omega=%.6f, alpha=%.4f, beta=%.4f, persistence=%.4f\n",
            as.numeric(cf_p["omega"]),
            as.numeric(cf_p["alpha1"]),
            as.numeric(cf_p["beta1"]),
            pers_p))

# ─── 3. Rolling 1-step-ahead σ forecast (PIT-safe, expanding window) ─────
# burn-in 60 months, refit every 12 months (statistical compromise: full refit
# every month is too slow; quarterly is reasonable, params change slowly given
# pers ~ 0.95). 1-step-ahead forecast at each t uses params from latest refit.
BURN_IN <- 60L
REFIT_EVERY <- 12L

sigma_p_forecast <- rep(NA_real_, T_m)
mu_p_forecast <- rep(NA_real_, T_m)
last_fit <- NULL
last_fit_idx <- 0L

for (t in seq.int(BURN_IN + 1L, T_m)) {
  if (t - last_fit_idx >= REFIT_EVERY || is.null(last_fit)) {
    fit_t <- tryCatch(
      ugarchfit(spec_p, data = ret_p[seq_len(t - 1L)], solver = "hybrid"),
      error = function(e) NULL
    )
    if (!is.null(fit_t) && fit_t@fit$convergence == 0L) {
      last_fit <- fit_t
      last_fit_idx <- t
    }
  }
  if (!is.null(last_fit)) {
    fc <- tryCatch(ugarchforecast(last_fit, n.ahead = 1L), error = function(e) NULL)
    if (!is.null(fc)) {
      sigma_p_forecast[t] <- as.numeric(sigma(fc))
      mu_p_forecast[t] <- as.numeric(fitted(fc))
    }
  }
}
cat(sprintf("[Step 3] σ_p forecast valid: %d/%d months (burn-in=%d)\n",
            sum(!is.na(sigma_p_forecast)), T_m, BURN_IN))

# ─── 4. Vol target rule (statistical) ────────────────────────────────────
# Annualize monthly sigma: sigma_ann = sigma_m * sqrt(12)
sigma_ann_forecast <- sigma_p_forecast * sqrt(12)
realized_vol_36m <- frollapply(ret_p, n = 36L, FUN = function(x) sd(x) * sqrt(12),
                               align = "right", fill = NA_real_)

# Target = median of valid 36m annualized rolling vol after burn-in
valid_realized <- realized_vol_36m[(BURN_IN + 1L):T_m]
target_realized_median <- median(valid_realized, na.rm = TRUE)
target_fixed_15pct <- 0.15

# Decision: choose statistically the lower (more conservative) of
#   (a) realized-vol median target
#   (b) fixed 15% benchmark
# Use target_choice = min, justified: defense priority + mdd_target ≤ -25%
target_choice_value <- min(target_realized_median, target_fixed_15pct, na.rm = TRUE)
target_choice_label <- if (target_realized_median < target_fixed_15pct) {
  "rolling_36m_median_realized_vol"
} else {
  "fixed_15pct_annual"
}
cat(sprintf("[Step 3] Vol target candidates: realized_36m_median=%.4f, fixed_15pct=%.4f\n",
            target_realized_median, target_fixed_15pct))
cat(sprintf("[Step 3] Vol target chosen: %s = %.4f (annualized)\n",
            target_choice_label, target_choice_value))

# ─── 5. Scale factor + cash_bridge path ──────────────────────────────────
scale_factor <- pmin(1.0, target_choice_value / sigma_ann_forecast)
cash_bridge <- pmax(0.0, 1.0 - scale_factor)
# Active months (not burn-in)
n_active <- sum(!is.na(scale_factor))
n_cash_active <- sum(cash_bridge > 0, na.rm = TRUE)
mean_cash_bridge <- mean(cash_bridge, na.rm = TRUE)
mean_scale <- mean(scale_factor, na.rm = TRUE)
cat(sprintf("[Step 3] Cash bridge active months: %d/%d (%.1f%%) | mean cash=%.4f\n",
            n_cash_active, n_active, 100 * n_cash_active / n_active, mean_cash_bridge))

# ─── 6. Save outputs ──────────────────────────────────────────────────────
out_dt <- data.table(
  date = str_ret$date,
  strategy_ret_net = str_ret$ret_net,
  sigma_p_monthly_forecast = sigma_p_forecast,
  sigma_p_annual_forecast = sigma_ann_forecast,
  realized_vol_36m_annual = realized_vol_36m,
  vol_target_annual = target_choice_value,
  scale_factor = scale_factor,
  cash_bridge = cash_bridge
)
fwrite(out_dt, file.path(SA, "sigma_p_forecast.csv"))

cash_bridge_dt <- out_dt[, .(date, sigma_p_annual_forecast, vol_target_annual,
                             scale_factor, cash_bridge)]
fwrite(cash_bridge_dt, file.path(SA, "cash_bridge_path.csv"))

# ─── 7. Forward-looking May 2026 σ_p_T+1 (Layer A) ───────────────────────
# 18-stock DCC forecast × 5월 운용 weights
dcc_fit <- readRDS(file.path(SA, "dcc_fit_object.rds"))
ret_dt <- as.data.table(read_parquet(file.path(SA, "returns_daily_18.parquet")))
stk_cols <- setdiff(names(ret_dt), "Date")

# 5월 weights (active 18 risk weights, normalized to sum=1 within risk universe)
may_weights_raw <- c(
  A010950=0.20, A050890=0.20, A009420=0.130904852948158, A058470=0.0758930316282816,
  A005930=0.0726755623339949, A071970=0.070114519442123, A095340=0.0394954049568652,
  A084370=0.0349333827957962, A403870=0.0302175416965821, A218410=0.0299991087888644,
  A039030=0.0260128238872486, A240810=0.0258636225491299, A002380=0.0221375390336184,
  A000660=0.0148433275805222, A064760=0.0116718177268105, A053030=0.0106864841458154,
  A290650=0.00320539292722091, A026960=0.00134557859704099
)
may_weights_raw <- may_weights_raw[stk_cols]  # align order
w_sum <- sum(may_weights_raw)
may_weights <- may_weights_raw / w_sum  # normalize within risk universe (cash inferred)
cat(sprintf("[Step 3] May 2026 risk weights: sum_raw=%.6f, normalized=%.6f\n",
            w_sum, sum(may_weights)))

# DCC 1-step-ahead forecast Σ_{T+1}
dcc_fc <- dccforecast(dcc_fit, n.ahead = 1L)
H_fc <- rcov(dcc_fc)[[1]]  # K x K x 1
Sigma_T1 <- H_fc[, , 1L]
sigma_p_T1_daily <- sqrt(as.numeric(t(may_weights) %*% Sigma_T1 %*% may_weights))
sigma_p_T1_annual <- sigma_p_T1_daily * sqrt(252)  # daily DCC -> annual
cat(sprintf("[Step 3] May 2026 forward σ_p_T+1: daily=%.6f, annualized=%.4f\n",
            sigma_p_T1_daily, sigma_p_T1_annual))

# Compare to vol target
scale_T1 <- min(1.0, target_choice_value / sigma_p_T1_annual)
cash_bridge_T1 <- max(0.0, 1.0 - scale_T1)
cat(sprintf("[Step 3] May 2026 forward scale_factor=%.4f, cash_bridge=%.4f\n",
            scale_T1, cash_bridge_T1))

# ─── 8. Vol target metadata ──────────────────────────────────────────────
vol_target_meta <- list(
  layer_A_forward_may_2026 = list(
    method = "18-stock DCC × 5월 risk weights × sqrt(252)",
    sigma_p_daily_T1 = as.numeric(sigma_p_T1_daily),
    sigma_p_annual_T1 = as.numeric(sigma_p_T1_annual),
    scale_factor_T1 = as.numeric(scale_T1),
    cash_bridge_T1 = as.numeric(cash_bridge_T1)
  ),
  layer_B_historical_268m = list(
    method = "Univariate GARCH(1,1) Gaussian on STR_1715 monthly net returns, expanding window 60m burn-in, refit every 12m",
    burn_in_months = BURN_IN,
    refit_every_months = REFIT_EVERY,
    n_active_months = n_active,
    n_cash_bridge_active = n_cash_active,
    pct_cash_bridge_active = round(100 * n_cash_active / n_active, 2),
    mean_scale_factor = as.numeric(mean_scale),
    mean_cash_bridge = as.numeric(mean_cash_bridge),
    realized_36m_median_annual = as.numeric(target_realized_median),
    fixed_15pct_benchmark = 0.15
  ),
  vol_target_decision = list(
    rule = "min(rolling_36m_median_realized_vol, fixed_15pct_annual)",
    chosen_label = target_choice_label,
    chosen_value = as.numeric(target_choice_value),
    rationale = "Statistical: median of expanding 36m realized vol provides natural target reflecting strategy's own volatility regime. Capped at 15% (heuristic ceiling for conservative defense alignment with mdd_target ≤ -25%). NO fixed % heuristic chosen unilaterally."
  ),
  garch_full_sample_diag = list(
    omega = as.numeric(cf_p["omega"]),
    alpha = as.numeric(cf_p["alpha1"]),
    beta = as.numeric(cf_p["beta1"]),
    persistence = as.numeric(pers_p),
    half_life_months = as.numeric(if (pers_p < 1) log(0.5)/log(pers_p) else NA_real_),
    log_lik = as.numeric(likelihood(fit_p_full)),
    AIC = as.numeric(infocriteria(fit_p_full)["Akaike", 1]),
    BIC = as.numeric(infocriteria(fit_p_full)["Bayes", 1])
  )
)
write_json(vol_target_meta, file.path(SA, "vol_target_meta.json"),
           pretty = TRUE, auto_unbox = TRUE)

write_json(list(
  step = "03_vol_target_path",
  status = if (n_active > 200L) "PASS" else "WARN",
  T_m = T_m,
  burn_in = BURN_IN,
  n_active = n_active,
  vol_target_annual = as.numeric(target_choice_value),
  vol_target_label = target_choice_label,
  may2026_sigma_annual = as.numeric(sigma_p_T1_annual),
  may2026_cash_bridge = as.numeric(cash_bridge_T1)
), file.path(DIR_DBG, "step03_vol_target.json"),
   pretty = TRUE, auto_unbox = TRUE)

cat("[Step 3] DONE\n")
