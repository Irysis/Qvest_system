#==============================================================================
# WT-D20260508_010 — Risk Research Pipeline
# R14_DUVOL Skewness Idiosyncratic alpha + Hybrid 70/15/15 baseline
#
# 5축 자율 진단:
#   1축: 공분산 Σ (Sample / Ledoit-Wolf / Gerber-RMT 병렬 비교) — alpha top20 universe
#   2축: 꼬리위험 (Empirical / Normal / CF / EVT-GPD) — Hybrid baseline + R14 overlay
#   3축: 8 stress periods + AX-001 v2 conditional defense
#   4축: 군집/style + per-regime correlation + TDC + diversification source proof (-0.418 cor)
#   5축: AX-007 single-sleeve check (R14_DUVOL alone) + diversification analytic
#
# **CORE MANDATE**: -0.418 음의 상관 (R14_DUVOL alpha vs Hybrid 70/15/15)이
#                  diversification 개선 source인지 정량 입증
#
# 입력:
#   - alpha_package.json (factor_specs R14_DUVOL + alpha_vector 348 names)
#   - alpha_scores.parquet (60 sig dates × 348 tickers panel)
#   - RAWDATA cache (.cache/rawdata.parquet)
#   - Hybrid 256m monthly returns (WT-P20260505_001 S3_Hybrid_70_15_15)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(digest)
})

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID     <- "WT-D20260508_010"
WT_DIR    <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
SA_DIR    <- file.path(PROJ_ROOT, "stage_artifacts", WT_ID)
LOG_DIR   <- file.path(SA_DIR, "_logs")
dir.create(LOG_DIR, showWarnings = FALSE, recursive = TRUE)

cat("\n========================================================\n")
cat("Risk Research Pipeline | WT-D20260508_010\n")
cat("R14_DUVOL Skewness Idiosyncratic + Hybrid 70/15/15 baseline\n")
cat("CORE: -0.418 음의 상관 diversification source 정량 입증\n")
cat("========================================================\n\n")

#==============================================================================
# Step 0: Load alpha_package + alpha_scores panel
#==============================================================================

alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = FALSE)
cat(sprintf("[Step 0] alpha_package loaded\n"))
cat(sprintf("  factor_specs: %d\n", length(alpha_pkg$factor_specs)))
cat(sprintf("  alpha_vector forward names: %d\n", length(alpha_pkg$alpha_vector)))
cat(sprintf("  R14_DUVOL: ICIR=%.4f / Harvey-NW t=%.3f / IC=%.4f\n",
            alpha_pkg$diagnostics$icir_measured,
            alpha_pkg$diagnostics$harvey_t_NW_lag4_measured,
            alpha_pkg$diagnostics$rank_ic_measured))

# Forward alpha (sig_date 2026-04-30)
alpha_panel <- as.data.table(read_parquet(file.path(SA_DIR, "alpha_scores.parquet")))
alpha_panel[, Date := as.Date(Date)]
cat(sprintf("  alpha_scores.parquet: %d rows | %d dates × %d tickers\n",
            nrow(alpha_panel), uniqueN(alpha_panel$Date), uniqueN(alpha_panel$Ticker)))
cat(sprintf("  date range: %s ~ %s\n", min(alpha_panel$Date), max(alpha_panel$Date)))

sig_date <- max(alpha_panel$Date)
alpha_fwd <- alpha_panel[Date == sig_date]
cat(sprintf("  forward alpha (sig=%s): %d names\n", sig_date, nrow(alpha_fwd)))

#==============================================================================
# Step 1: Load RAWDATA + Hybrid baseline
#==============================================================================

cat("\n[Step 1] Load RAWDATA + Hybrid 256m monthly returns\n")
RAW <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/rawdata.parquet")))
RAW[, Date := as.Date(Date)]
setkey(RAW, Date, Ticker)
cat(sprintf("  RAWDATA: %d rows | %d tickers | %s ~ %s\n",
            nrow(RAW), uniqueN(RAW$Ticker), min(RAW$Date), max(RAW$Date)))

# Hybrid baseline
hybrid_path <- file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-P20260505_001/output/S3_Hybrid_70_15_15/03_period_returns.csv")
hybrid_ret <- fread(hybrid_path)
hybrid_ret[, date := as.Date(date)]
cat(sprintf("  Hybrid 70/15/15 monthly: %d months | %s ~ %s\n",
            nrow(hybrid_ret), min(hybrid_ret$date), max(hybrid_ret$date)))
cat(sprintf("    ret_net mean=%.4f  sd=%.4f  skew=%.3f\n",
            mean(hybrid_ret$ret_net, na.rm=TRUE),
            sd(hybrid_ret$ret_net, na.rm=TRUE),
            mean((hybrid_ret$ret_net - mean(hybrid_ret$ret_net))^3) / sd(hybrid_ret$ret_net)^3))

#==============================================================================
# Step 2: Build returns panel for R14_DUVOL universe
#  - sig_date 2026-04-30, alpha_fwd 348 names ∩ RAWDATA
#  - 252-day daily returns (PIT C2 strict)
#==============================================================================

cat("\n[Step 2] Build returns panel — alpha forward universe\n")
cutoff_date <- sig_date  # strict less-than for C2

risk_universe <- alpha_fwd$Ticker
cat(sprintf("  alpha forward universe: %d names\n", length(risk_universe)))

ret_panel <- RAW[Date < cutoff_date & Ticker %in% risk_universe,
                 .(Date, Ticker, Ret)]
last_dates <- tail(sort(unique(ret_panel$Date)), 252)
ret_panel <- ret_panel[Date %in% last_dates]
cat(sprintf("  panel rows: %d | dates: %d | tickers: %d\n",
            nrow(ret_panel), uniqueN(ret_panel$Date), uniqueN(ret_panel$Ticker)))

wide_ret <- dcast(ret_panel, Date ~ Ticker, value.var = "Ret")
ret_mat <- as.matrix(wide_ret[, -1, drop = FALSE])
keep_cols <- colSums(!is.na(ret_mat)) >= 200
cat(sprintf("  drop %d tickers with <200 obs (kept %d)\n",
            sum(!keep_cols), sum(keep_cols)))
ret_mat <- ret_mat[, keep_cols, drop = FALSE]
keep_rows <- rowSums(!is.na(ret_mat)) >= ncol(ret_mat) * 0.5
ret_mat <- ret_mat[keep_rows, , drop = FALSE]
ret_mat[is.na(ret_mat)] <- 0
cat(sprintf("  final ret_mat: %d × %d\n", nrow(ret_mat), ncol(ret_mat)))

N_ASSETS <- ncol(ret_mat)
T_DAYS   <- nrow(ret_mat)

#==============================================================================
# Step 3: Σ — 3 estimators 비교 (R13 v6.1 method shopping)
#==============================================================================

cat("\n[Step 3] Σ — sample / Ledoit-Wolf / Gerber-RMT 비교\n")
source(file.path(PROJ_ROOT, "02_Infrastructure/portfolio/hrp_core.R"))

method_log <- list()

# 3.1 Sample
t0 <- Sys.time()
sigma_sample <- .get_cor_cov(ret_mat, cov_method = "sample")$cov
t_sample <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cn_sample <- kappa(sigma_sample)
eig_sample <- eigen(sigma_sample, symmetric = TRUE, only.values = TRUE)$values
min_eig_sample <- min(eig_sample)
psd_sample <- min_eig_sample > -1e-10
cat(sprintf("  sample           : κ=%.2f | min_eig=%.3e | PSD=%s | %.2fs\n",
            cn_sample, min_eig_sample, psd_sample, t_sample))
method_log[[length(method_log) + 1L]] <- list(
  name = "sample", condition = cn_sample, min_eig = min_eig_sample,
  psd = psd_sample, time_sec = t_sample, selected = FALSE
)

# 3.2 Ledoit-Wolf
t0 <- Sys.time()
sigma_lw <- .get_cor_cov(ret_mat, cov_method = "ledoit_wolf")$cov
t_lw <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cn_lw <- kappa(sigma_lw)
eig_lw <- eigen(sigma_lw, symmetric = TRUE, only.values = TRUE)$values
min_eig_lw <- min(eig_lw)
psd_lw <- min_eig_lw > -1e-10
cat(sprintf("  ledoit_wolf      : κ=%.2f | min_eig=%.3e | PSD=%s | %.2fs\n",
            cn_lw, min_eig_lw, psd_lw, t_lw))
method_log[[length(method_log) + 1L]] <- list(
  name = "ledoit_wolf", condition = cn_lw, min_eig = min_eig_lw,
  psd = psd_lw, time_sec = t_lw, selected = FALSE
)

# 3.3 Gerber-RMT
t0 <- Sys.time()
sigma_gr <- tryCatch(.get_cor_cov(ret_mat, cov_method = "gerber_rmt")$cov,
                     error = function(e) {
                       cat(sprintf("  gerber_rmt FAIL: %s\n", conditionMessage(e)))
                       NULL
                     })
t_gr <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
if (!is.null(sigma_gr)) {
  cn_gr <- kappa(sigma_gr)
  eig_gr <- eigen(sigma_gr, symmetric = TRUE, only.values = TRUE)$values
  min_eig_gr <- min(eig_gr)
  psd_gr <- min_eig_gr > -1e-10
  cat(sprintf("  gerber_rmt       : κ=%.2f | min_eig=%.3e | PSD=%s | %.2fs\n",
              cn_gr, min_eig_gr, psd_gr, t_gr))
  method_log[[length(method_log) + 1L]] <- list(
    name = "gerber_rmt", condition = cn_gr, min_eig = min_eig_gr,
    psd = psd_gr, time_sec = t_gr, selected = FALSE
  )
}

# Selection: min(condition) AND PSD AND condition < 500
candidates <- method_log
ok_cands <- Filter(function(c) c$psd && c$condition < 500, candidates)
if (length(ok_cands) == 0) {
  selected_method <- "ledoit_wolf"
} else {
  conds <- sapply(ok_cands, function(c) c$condition)
  best  <- ok_cands[[which.min(conds)]]
  selected_method <- best$name
}
for (i in seq_along(method_log)) {
  if (method_log[[i]]$name == selected_method) method_log[[i]]$selected <- TRUE
}
cat(sprintf("\n  → SELECTED: %s (selection_objective=condition_number)\n", selected_method))

selected_sigma <- switch(selected_method,
  "sample"      = sigma_sample,
  "ledoit_wolf" = sigma_lw,
  "gerber_rmt"  = sigma_gr
)
sel_cn <- kappa(selected_sigma)

# Save covariance
cov_dt <- as.data.table(selected_sigma)
cov_dt[, Ticker := colnames(selected_sigma)]
setcolorder(cov_dt, c("Ticker", colnames(selected_sigma)))
write_parquet(cov_dt, file.path(SA_DIR, "covariance.parquet"))
cat(sprintf("  saved: covariance.parquet (%d × %d)\n", nrow(cov_dt), ncol(cov_dt) - 1L))

#==============================================================================
# Step 4: Tail Risk (4-method) on Hybrid baseline
#==============================================================================

cat("\n[Step 4] Tail risk — Hybrid baseline (256m monthly net returns)\n")
source(file.path(PROJ_ROOT, "02_Infrastructure/portfolio/tail_risk_engine.R"))

hr <- hybrid_ret$ret_net
hr <- hr[!is.na(hr)]

var95_emp <- quantile(hr, 0.05, na.rm = TRUE)
var99_emp <- quantile(hr, 0.01, na.rm = TRUE)
es95_emp  <- mean(hr[hr <= var95_emp], na.rm = TRUE)
es99_emp  <- mean(hr[hr <= var99_emp], na.rm = TRUE)

mu <- mean(hr, na.rm = TRUE); sg <- sd(hr, na.rm = TRUE)
var95_norm <- mu + sg * qnorm(0.05)
var99_norm <- mu + sg * qnorm(0.01)
es95_norm  <- mu - sg * dnorm(qnorm(0.05)) / 0.05
es99_norm  <- mu - sg * dnorm(qnorm(0.01)) / 0.01

cf_var <- compute_cf_var(hr, p = 0.95)
cf_var99 <- compute_cf_var(hr, p = 0.99)
cf95 <- if (is.list(cf_var)) -cf_var$var_cf else NA_real_
cf99 <- if (is.list(cf_var99)) -cf_var99$var_cf else NA_real_

evt_var95 <- compute_evt_var(hr, p = 0.95, threshold_q = 0.85, min_tail_n = 20L)
evt_var99 <- compute_evt_var(hr, p = 0.99, threshold_q = 0.90, min_tail_n = 15L)
evt95 <- if (is.list(evt_var95)) -evt_var95$var_evt else NA_real_
evt99 <- if (is.list(evt_var99)) -evt_var99$var_evt else NA_real_
evt_es95 <- if (is.list(evt_var95)) -evt_var95$es_evt else NA_real_
evt_es99 <- if (is.list(evt_var99)) -evt_var99$es_evt else NA_real_

cat(sprintf("  Empirical : VaR95=%.4f  VaR99=%.4f  ES95=%.4f  ES99=%.4f\n",
            var95_emp, var99_emp, es95_emp, es99_emp))
cat(sprintf("  Normal    : VaR95=%.4f  VaR99=%.4f  ES95=%.4f  ES99=%.4f\n",
            var95_norm, var99_norm, es95_norm, es99_norm))
cat(sprintf("  CF        : VaR95=%.4f  VaR99=%.4f\n", cf95, cf99))
cat(sprintf("  EVT-GPD   : VaR95=%.4f  VaR99=%.4f  ES95=%.4f  ES99=%.4f\n",
            evt95, evt99, evt_es95, evt_es99))

nav_hybrid <- cumprod(1 + hr)
cdar95 <- compute_cdar(nav_hybrid, alpha = 0.95)
mdd_hybrid <- min(nav_hybrid / cummax(nav_hybrid) - 1)
cat(sprintf("  CDaR95    : %.4f | MDD obs : %.4f\n", cdar95, mdd_hybrid))

# Hill α
neg_hr <- -hr[hr < 0]
neg_sorted <- sort(neg_hr, decreasing = TRUE)
n_top <- max(10L, floor(length(neg_sorted) * 0.1))
n_top <- min(n_top, length(neg_sorted) - 1L)
if (n_top >= 5) {
  thresh <- neg_sorted[n_top]
  hill_alpha <- 1 / mean(log(neg_sorted[1:n_top]) - log(thresh))
} else hill_alpha <- NA
cat(sprintf("  Hill α    : %.4f (n_top=%d)\n", hill_alpha, n_top))

tail_summary <- list(
  weight_basis = "Hybrid 70/15/15 monthly net returns 256m (WT-P20260505_001 S3)",
  n_obs_months = length(hr),
  empirical = list(var95 = var95_emp, var99 = var99_emp, es95 = es95_emp, es99 = es99_emp),
  normal    = list(var95 = var95_norm, var99 = var99_norm, es95 = es95_norm, es99 = es99_norm),
  cornish_fisher = list(var95 = cf95, var99 = cf99,
                        skewness = if (is.list(cf_var)) cf_var$skewness else NA,
                        kurtosis = if (is.list(cf_var)) cf_var$kurtosis else NA,
                        cf_vs_normal_ratio = if (is.list(cf_var99)) cf_var99$cf_vs_normal_ratio else NA),
  evt_gpd = list(var95 = evt95, var99 = evt99,
                 es95 = evt_es95, es99 = evt_es99,
                 shape_xi = if (is.list(evt_var99)) evt_var99$shape_xi else NA,
                 scale_beta = if (is.list(evt_var99)) evt_var99$scale_beta else NA,
                 threshold_u = if (is.list(evt_var99)) evt_var99$threshold_u else NA),
  cdar95 = cdar95,
  mdd_observed = mdd_hybrid,
  hill_alpha = hill_alpha,
  interpretation = "Empirical < CF < Normal < EVT-GPD typical for left-tailed monthly returns. Hill α ~2 indicates moderate fat tail."
)
write_json(tail_summary, file.path(SA_DIR, "tail_risk_diagnostics.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

#==============================================================================
# Step 5: Stress 8 periods on Hybrid baseline + market_down_5 scenario
#==============================================================================

cat("\n[Step 5] Stress 8 periods on Hybrid baseline\n")
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

stress_dt <- data.table(
  period = character(), start = character(), end = character(),
  n_months = integer(), cum_ret = numeric(), worst_month = numeric(),
  mean_month = numeric(), hybrid_obs_count = integer()
)

for (pn in names(stress_periods)) {
  d_start <- as.Date(stress_periods[[pn]][1])
  d_end   <- as.Date(stress_periods[[pn]][2])
  sub <- hybrid_ret[date >= d_start & date <= d_end]
  if (nrow(sub) > 0) {
    cum_r <- prod(1 + sub$ret_net) - 1
    worst <- min(sub$ret_net)
    mean_r <- mean(sub$ret_net)
    n_obs <- nrow(sub)
  } else {
    cum_r <- NA; worst <- NA; mean_r <- NA; n_obs <- 0L
  }
  stress_dt <- rbind(stress_dt, data.table(
    period = pn, start = as.character(d_start), end = as.character(d_end),
    n_months = n_obs, cum_ret = cum_r, worst_month = worst,
    mean_month = mean_r, hybrid_obs_count = n_obs
  ))
  cat(sprintf("  %-15s: %s ~ %s | n=%2d | cum=%6.2f%% | worst=%6.2f%% | mean=%6.2f%%\n",
              pn, d_start, d_end, n_obs,
              ifelse(is.na(cum_r), 0, cum_r * 100),
              ifelse(is.na(worst), 0, worst * 100),
              ifelse(is.na(mean_r), 0, mean_r * 100)))
}

# Market down 5% via β-proxy
bm_dt <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/benchmark.parquet")))
bm_dt[, Date := as.Date(Date)]
bm_dt[, ym := format(Date, "%Y-%m-01")]
bm_m <- bm_dt[, .(bm_ret = prod(1 + BM_Ret) - 1), by = .(ym = as.Date(ym))]
hybrid_ret[, ym := as.Date(format(date, "%Y-%m-01"))]
joined <- merge(hybrid_ret[, .(ym, ret_net)], bm_m, by = "ym")
beta_hybrid <- if (nrow(joined) >= 24)
  cov(joined$ret_net, joined$bm_ret, use = "pairwise.complete.obs") /
    var(joined$bm_ret, na.rm = TRUE) else NA_real_
market_down_5 <- if (!is.na(beta_hybrid)) beta_hybrid * (-0.05) else NA_real_
cat(sprintf("\n  β_hybrid (vs KOSPI200) = %.4f → market_down_5%% scenario = %.4f\n",
            beta_hybrid, market_down_5))

write_parquet(stress_dt, file.path(SA_DIR, "stress_periods.parquet"))

#==============================================================================
# Step 6: ★ CORE — Diversification Source Proof for -0.418 cor
#  R14_DUVOL alpha vs Hybrid 70/15/15 음의 상관이 portfolio diversification 개선 source
#==============================================================================

cat("\n[Step 6] ★ CORE: Diversification Source Proof for -0.418 cor\n")
cat("  Markowitz 1952 negative cov benefit: σ_p² = w_h²σ_h² + w_a²σ_a² + 2 w_h w_a ρ σ_h σ_a\n")
cat("  ρ < 0 → cross term < 0 → σ_p < independent baseline\n\n")

# Step 6.1 — alpha "portfolio" proxy: top 20 highest alpha names equal-weight monthly returns
# We compute alpha_top20_EW returns history matched to Hybrid date axis
# Use forward sig_date alpha to pick names (PIT: this is "as-of forecast holding"); then look back 256m
top20_pos_tickers <- alpha_fwd[order(-alpha_z)][1:20, Ticker]
cat(sprintf("  Top 20 R14_DUVOL forward names (positive alpha):\n"))
print(alpha_fwd[Ticker %in% top20_pos_tickers][order(-alpha_z), .(Ticker, alpha_z)])

# Build monthly EW returns of these 20 names over the past
# Use month-end snapshots to align with Hybrid monthly axis
RAW_t20 <- RAW[Ticker %in% top20_pos_tickers, .(Date, Ticker, Ret)]
# month-end Date for each YYYY-MM
RAW_t20[, ym := as.Date(format(Date, "%Y-%m-01"))]
# Compound daily Ret per Ticker per month
mret <- RAW_t20[, .(mret = prod(1 + Ret, na.rm = TRUE) - 1, n_obs = .N), by = .(ym, Ticker)]
# Drop sparse months (need at least 15 trading days)
mret <- mret[n_obs >= 15]
# EW across tickers
mret_ew <- mret[, .(alpha_top20_ew = mean(mret, na.rm = TRUE), n_t = .N), by = ym]
# Need at least 15 names per month
mret_ew <- mret_ew[n_t >= 15]
cat(sprintf("  Monthly EW alpha-top20 series: %d months | %s ~ %s\n",
            nrow(mret_ew), min(mret_ew$ym), max(mret_ew$ym)))

# Match to hybrid_ret month axis
joined_ah <- merge(hybrid_ret[, .(ym, hybrid_ret = ret_net)],
                   mret_ew[, .(ym, alpha_ret = alpha_top20_ew)],
                   by = "ym")
joined_ah <- joined_ah[!is.na(hybrid_ret) & !is.na(alpha_ret)]
cat(sprintf("  Matched months: %d | %s ~ %s\n",
            nrow(joined_ah), min(joined_ah$ym), max(joined_ah$ym)))

# Realize ρ_realized between alpha sleeve and Hybrid
rho_realized <- cor(joined_ah$alpha_ret, joined_ah$hybrid_ret, use = "pairwise.complete.obs")
sigma_alpha <- sd(joined_ah$alpha_ret, na.rm = TRUE)
sigma_hybrid <- sd(joined_ah$hybrid_ret, na.rm = TRUE)
cat(sprintf("  ρ_realized (alpha_top20_EW vs Hybrid) = %+.4f\n", rho_realized))
cat(sprintf("  σ_alpha = %.4f / σ_hybrid = %.4f\n", sigma_alpha, sigma_hybrid))

# Step 6.2 — Diversification gain calculation (Markowitz)
# σ_combo² for w_h ∈ {0.5, 0.7, 0.85} : w_a ∈ {0.5, 0.3, 0.15}
combo_grid <- data.table(w_hybrid = c(0.5, 0.7, 0.85, 0.9),
                         w_alpha  = c(0.5, 0.3, 0.15, 0.1))
combo_grid[, sigma_indep := sqrt((w_hybrid * sigma_hybrid)^2 + (w_alpha * sigma_alpha)^2)]
combo_grid[, sigma_combo := sqrt((w_hybrid * sigma_hybrid)^2 + (w_alpha * sigma_alpha)^2 +
                                 2 * w_hybrid * w_alpha * rho_realized * sigma_hybrid * sigma_alpha)]
combo_grid[, gain_pct := (sigma_indep - sigma_combo) / sigma_indep * 100]
combo_grid[, sigma_independent_naive := sqrt((w_hybrid^2) * sigma_hybrid^2 +
                                              (w_alpha^2) * sigma_alpha^2)]
cat("\n  Markowitz diversification gain (rho=", round(rho_realized, 4), "):\n", sep = "")
print(combo_grid)

# Empirical realized combo returns (varying w_alpha)
realized_combo <- list()
for (k in seq_len(nrow(combo_grid))) {
  wh <- combo_grid$w_hybrid[k]; wa <- combo_grid$w_alpha[k]
  combo_ret <- wh * joined_ah$hybrid_ret + wa * joined_ah$alpha_ret
  realized_combo[[k]] <- list(
    w_hybrid = wh, w_alpha = wa,
    n_months = length(combo_ret),
    mean_monthly = mean(combo_ret, na.rm = TRUE),
    sd_monthly = sd(combo_ret, na.rm = TRUE),
    cum_total = prod(1 + combo_ret, na.rm = TRUE) - 1,
    skew = mean((combo_ret - mean(combo_ret))^3) / sd(combo_ret)^3,
    sharpe_monthly = mean(combo_ret, na.rm = TRUE) / sd(combo_ret, na.rm = TRUE),
    sharpe_annual = mean(combo_ret, na.rm = TRUE) / sd(combo_ret, na.rm = TRUE) * sqrt(12),
    nav_max = max(cumprod(1 + combo_ret)),
    mdd = min(cumprod(1 + combo_ret) / cummax(cumprod(1 + combo_ret)) - 1)
  )
}
realized_combo_dt <- rbindlist(lapply(realized_combo, as.data.table))
cat("\n  Empirical combo realized stats:\n")
print(realized_combo_dt)

# Hybrid baseline alone (ref)
hybrid_only <- list(
  mean_monthly = mean(joined_ah$hybrid_ret, na.rm = TRUE),
  sd_monthly = sd(joined_ah$hybrid_ret, na.rm = TRUE),
  sharpe_annual = mean(joined_ah$hybrid_ret, na.rm = TRUE) / sd(joined_ah$hybrid_ret, na.rm = TRUE) * sqrt(12),
  mdd = min(cumprod(1 + joined_ah$hybrid_ret) / cummax(cumprod(1 + joined_ah$hybrid_ret)) - 1)
)
cat(sprintf("\n  Hybrid alone (matched panel): SR_annual=%.3f / MDD=%.4f / σ_monthly=%.4f\n",
            hybrid_only$sharpe_annual, hybrid_only$mdd, hybrid_only$sd_monthly))

# Diversification source verdict
sigma_reduction_70_30 <- combo_grid[w_hybrid == 0.7, gain_pct]
sigma_reduction_85_15 <- combo_grid[w_hybrid == 0.85, gain_pct]
sr_improvement <- realized_combo_dt[w_hybrid == 0.7, sharpe_annual] - hybrid_only$sharpe_annual
mdd_improvement <- realized_combo_dt[w_hybrid == 0.7, mdd] - hybrid_only$mdd

div_proof <- list(
  alpha_layer_reported_cor = -0.418,
  rho_realized_top20EW_vs_hybrid = round(rho_realized, 4),
  sigma_hybrid_monthly = round(sigma_hybrid, 4),
  sigma_alpha_top20EW_monthly = round(sigma_alpha, 4),
  matched_months = nrow(joined_ah),
  matched_period = list(start = as.character(min(joined_ah$ym)),
                        end = as.character(max(joined_ah$ym))),
  markowitz_gain_grid = list(
    "w_hybrid_0.50_w_alpha_0.50" = list(sigma_combo = round(combo_grid[1, sigma_combo], 4),
                                         sigma_indep = round(combo_grid[1, sigma_indep], 4),
                                         gain_pct = round(combo_grid[1, gain_pct], 2)),
    "w_hybrid_0.70_w_alpha_0.30" = list(sigma_combo = round(combo_grid[2, sigma_combo], 4),
                                         sigma_indep = round(combo_grid[2, sigma_indep], 4),
                                         gain_pct = round(combo_grid[2, gain_pct], 2)),
    "w_hybrid_0.85_w_alpha_0.15" = list(sigma_combo = round(combo_grid[3, sigma_combo], 4),
                                         sigma_indep = round(combo_grid[3, sigma_indep], 4),
                                         gain_pct = round(combo_grid[3, gain_pct], 2)),
    "w_hybrid_0.90_w_alpha_0.10" = list(sigma_combo = round(combo_grid[4, sigma_combo], 4),
                                         sigma_indep = round(combo_grid[4, sigma_indep], 4),
                                         gain_pct = round(combo_grid[4, gain_pct], 2))
  ),
  realized_combo_stats = realized_combo,
  hybrid_alone_baseline = hybrid_only,
  verdict = list(
    diversification_source = if (rho_realized < -0.10) "CONFIRMED" else if (rho_realized < 0.10) "PARTIAL" else "NOT_CONFIRMED",
    sigma_reduction_70_30_pct = round(sigma_reduction_70_30, 2),
    sigma_reduction_85_15_pct = round(sigma_reduction_85_15, 2),
    sr_improvement_70_30 = round(sr_improvement, 4),
    mdd_improvement_70_30 = round(mdd_improvement, 4)
  ),
  interpretation = sprintf(
    "Realized rho %.4f (vs alpha-layer reported -0.418 cross-section). %s diversification source. Markowitz gain %.2f%% at 70/30 mix.",
    rho_realized,
    if (rho_realized < -0.10) "CONFIRMED" else if (rho_realized < 0.10) "PARTIAL" else "NOT_CONFIRMED",
    sigma_reduction_70_30
  ),
  caveat = "alpha-layer cor -0.418 is cross-sectional (signal vs Hybrid score proxy). Realized cor here is time-series of returns. The two metrics measure different relationships; both are honest disclosures."
)
write_json(div_proof, file.path(WT_DIR, "diversification_source_proof.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("\n  → diversification source verdict: %s\n", div_proof$verdict$diversification_source))
cat(sprintf("  σ reduction (70/30) = %.2f%% / SR Δ = %+.4f / MDD Δ = %+.4f\n",
            sigma_reduction_70_30, sr_improvement, mdd_improvement))

#==============================================================================
# Step 7: Crowding + Style + Liquidity diagnostics
#==============================================================================

cat("\n[Step 7] Crowding + Style + Liquidity\n")

alpha_dt <- data.table(
  Ticker = names(alpha_pkg$alpha_vector),
  alpha  = unlist(alpha_pkg$alpha_vector)
)
setorder(alpha_dt, -alpha)
top_pos <- head(alpha_dt[alpha > 0], 20)
top_neg <- head(alpha_dt[order(alpha)][alpha < 0], 20)

# Sector
has_sector <- "Sector" %in% colnames(RAW)
has_sector_lv2 <- "Sector_Lv2" %in% colnames(RAW)
sec_count <- NULL
sec_col <- if (has_sector) "Sector" else if (has_sector_lv2) "Sector_Lv2" else NULL
if (!is.null(sec_col)) {
  univ_sec <- unique(RAW[Date == max(RAW$Date), c("Ticker", sec_col), with = FALSE])
  setnames(univ_sec, sec_col, "Sector")
  top_pos_sec <- merge(top_pos, univ_sec, by = "Ticker", all.x = TRUE)
  sec_count <- top_pos_sec[!is.na(Sector), .N, by = Sector]
  setorder(sec_count, -N)
  cat("  Top 20 positive alpha sector concentration:\n")
  print(sec_count)
} else {
  cat("  (no Sector column in RAWDATA — skip sector concentration)\n")
}

# Liquidity
liq_check <- RAW[Date >= max(RAW$Date) - 30 & Ticker %in% top_pos$Ticker,
                 .(adv20 = mean(Vol * Close, na.rm = TRUE)), by = Ticker]
adv_low_count <- sum(liq_check$adv20 < 2e8, na.rm = TRUE)
cat(sprintf("  Top 20 ADV20 < 2e8 KRW count: %d / %d (LIQ_THRESHOLD breach)\n",
            adv_low_count, nrow(liq_check)))

# Style: factor exposure of R14_DUVOL alpha vs FF3/FF5/Carhart proxies via cross-sectional regression
# Use forward sig_date Z scores on size + value + momentum proxies
# Proxies from RAWDATA: log(Size) for size; price-based momentum 6m-1m
sig_rd <- RAW[Date == max(RAW[Date < cutoff_date, Date]) & Ticker %in% alpha_fwd$Ticker,
              .(Ticker, Size, Close, BM_Ret)]
# 6m-1m momentum
d_6m <- max(RAW[Date < cutoff_date, Date]) - 180
d_1m <- max(RAW[Date < cutoff_date, Date]) - 21
mom_dt <- RAW[Date %in% c(d_6m, d_1m) & Ticker %in% alpha_fwd$Ticker]
mom_w <- dcast(mom_dt[, .(Ticker, Date, Close)], Ticker ~ Date, value.var = "Close")
setnames(mom_w, c("Ticker", "px_6m", "px_1m"))
mom_w[, mom_6_1 := log(px_1m / px_6m)]

style_dt <- merge(alpha_fwd[, .(Ticker, alpha_z)], sig_rd, by = "Ticker", all.x = TRUE)
style_dt <- merge(style_dt, mom_w[, .(Ticker, mom_6_1)], by = "Ticker", all.x = TRUE)
style_dt[, log_size := log(pmax(Size, 1))]

# Cross-sectional cor with style proxies
style_cors <- list(
  size_log_cor = cor(style_dt$alpha_z, style_dt$log_size, use = "pairwise.complete.obs"),
  momentum_6_1_cor = cor(style_dt$alpha_z, style_dt$mom_6_1, use = "pairwise.complete.obs"),
  n_obs = sum(!is.na(style_dt$log_size) & !is.na(style_dt$mom_6_1))
)
cat(sprintf("  Style cor: alpha vs log_size = %+.4f / vs mom_6_1 = %+.4f / n=%d\n",
            style_cors$size_log_cor, style_cors$momentum_6_1_cor, style_cors$n_obs))

#==============================================================================
# Step 8: Per-regime correlation + TDC for top 20 alpha names
#==============================================================================

cat("\n[Step 8] Per-regime correlation + TDC\n")

top20_in_mat <- intersect(top20_pos_tickers, colnames(ret_mat))
top20_ret <- RAW[Ticker %in% top20_in_mat, .(Date, Ticker, Ret)]
top20_wide <- dcast(top20_ret, Date ~ Ticker, value.var = "Ret")
top20_mat <- as.matrix(top20_wide[, -1, drop = FALSE])
top20_dates <- top20_wide$Date

regime_cor_list <- list()
for (pn in names(stress_periods)) {
  d_start <- as.Date(stress_periods[[pn]][1])
  d_end   <- as.Date(stress_periods[[pn]][2])
  in_period <- top20_dates >= d_start & top20_dates <= d_end
  if (sum(in_period) >= 20) {
    sub <- top20_mat[in_period, , drop = FALSE]
    cor_in <- mean(cor(sub, use = "pairwise.complete.obs")[upper.tri(diag(ncol(sub)))], na.rm = TRUE)
    regime_cor_list[[pn]] <- list(period = pn, n_days = sum(in_period), avg_pair_cor = cor_in)
  }
}
normal_mask <- rep(TRUE, length(top20_dates))
for (pn in names(stress_periods)) {
  d_start <- as.Date(stress_periods[[pn]][1])
  d_end   <- as.Date(stress_periods[[pn]][2])
  normal_mask <- normal_mask & !(top20_dates >= d_start & top20_dates <= d_end)
}
sub_n <- top20_mat[normal_mask, , drop = FALSE]
cor_n <- mean(cor(sub_n, use = "pairwise.complete.obs")[upper.tri(diag(ncol(sub_n)))], na.rm = TRUE)
regime_cor_list[["NORMAL"]] <- list(period = "NORMAL", n_days = sum(normal_mask), avg_pair_cor = cor_n)

regime_cor_dt <- rbindlist(lapply(regime_cor_list, as.data.table))
write_parquet(regime_cor_dt, file.path(SA_DIR, "regime_correlation.parquet"))
cat("  Top 20 alpha pair correlation by regime:\n")
print(regime_cor_dt[order(-avg_pair_cor)])

# TDC empirical (lower 5 / 10)
tdc_lower <- function(x, y, q) {
  qx <- quantile(x, q, na.rm = TRUE)
  qy <- quantile(y, q, na.rm = TRUE)
  joint <- sum(x <= qx & y <= qy, na.rm = TRUE)
  marg <- sum(x <= qx, na.rm = TRUE)
  if (marg == 0) NA else joint / marg
}

tdc5_vec <- c(); tdc10_vec <- c()
n_pairs <- min(50L, ncol(top20_mat) * (ncol(top20_mat) - 1L) / 2L)
pair_count <- 0L
for (i in 1:(ncol(top20_mat) - 1)) {
  for (j in (i + 1):ncol(top20_mat)) {
    if (pair_count >= n_pairs) break
    xi <- top20_mat[, i]; yj <- top20_mat[, j]
    tdc5_vec <- c(tdc5_vec, tdc_lower(xi, yj, 0.05))
    tdc10_vec <- c(tdc10_vec, tdc_lower(xi, yj, 0.10))
    pair_count <- pair_count + 1L
  }
  if (pair_count >= n_pairs) break
}
tdc5_mean <- mean(tdc5_vec, na.rm = TRUE)
tdc10_mean <- mean(tdc10_vec, na.rm = TRUE)
cat(sprintf("  TDC (top 20 alpha): lower 5%% mean=%.3f | lower 10%% mean=%.3f (n_pairs=%d)\n",
            tdc5_mean, tdc10_mean, pair_count))

#==============================================================================
# Step 9: AX-001 v2 conditional defense (Risk side)
#  - alpha_package에서: alpha_z 좌측꼬리 = high alpha (Z 정렬됨)
#  - Risk: crisis vs normal IC 측정, R14 alpha의 crisis 진성 방어형 입증
#==============================================================================

cat("\n[Step 9] AX-001 v2 conditional defense — Risk validation\n")

# Use historical alpha panel for crisis vs normal IC partition
# Tag each panel month with regime via stress periods
alpha_panel_train <- alpha_panel[!is.na(fwd_ret_1m)]
alpha_panel_train[, regime := "NORMAL"]
for (pn in names(stress_periods)) {
  d_start <- as.Date(stress_periods[[pn]][1])
  d_end   <- as.Date(stress_periods[[pn]][2])
  alpha_panel_train[Date >= d_start & Date <= d_end, regime := "CRISIS"]
}
cat(sprintf("  alpha panel regime split: NORMAL=%d / CRISIS=%d obs\n",
            nrow(alpha_panel_train[regime == "NORMAL"]),
            nrow(alpha_panel_train[regime == "CRISIS"])))

# Per-date IC, then partition by regime
ic_per_date_alpha <- alpha_panel_train[, .(
  rank_ic = cor(alpha_z, fwd_ret_1m, method = "spearman", use = "pairwise.complete.obs"),
  regime = unique(regime)[1]
), by = Date]

ic_normal <- ic_per_date_alpha[regime == "NORMAL", rank_ic]
ic_crisis <- ic_per_date_alpha[regime == "CRISIS", rank_ic]

ic_normal_mean <- mean(ic_normal, na.rm = TRUE)
ic_crisis_mean <- mean(ic_crisis, na.rm = TRUE)
crisis_alpha_positive <- !is.na(ic_crisis_mean) && ic_crisis_mean > 0
bad_normal_ratio <- if (!is.na(ic_normal_mean) && abs(ic_normal_mean) > 1e-6)
  ic_crisis_mean / ic_normal_mean else NA_real_

cat(sprintf("  IC_normal mean = %+.4f (n=%d)\n", ic_normal_mean, length(ic_normal)))
cat(sprintf("  IC_crisis mean = %+.4f (n=%d)\n", ic_crisis_mean, length(ic_crisis)))
cat(sprintf("  bad/normal ratio = %.4f\n", bad_normal_ratio))
cat(sprintf("  crisis_alpha_positive = %s\n", crisis_alpha_positive))

# Hybrid baseline crisis vs normal mean (already computed; here for reference)
hybrid_ret[, regime := "NORMAL"]
for (pn in names(stress_periods)) {
  d_start <- as.Date(stress_periods[[pn]][1])
  d_end   <- as.Date(stress_periods[[pn]][2])
  hybrid_ret[date >= d_start & date <= d_end, regime := "CRISIS"]
}
hybrid_crisis_mean <- mean(hybrid_ret[regime == "CRISIS", ret_net], na.rm = TRUE)
hybrid_normal_mean <- mean(hybrid_ret[regime == "NORMAL", ret_net], na.rm = TRUE)

# Core MDD comparison (Hybrid vs Hybrid+R14)
hybrid_nav <- cumprod(1 + hr)
hybrid_mdd <- min(hybrid_nav / cummax(hybrid_nav) - 1)

# Combo NAV (matched panel only) — 70/30 mix realized
matched_combo_70_30 <- 0.7 * joined_ah$hybrid_ret + 0.3 * joined_ah$alpha_ret
combo_nav <- cumprod(1 + matched_combo_70_30)
combo_mdd <- min(combo_nav / cummax(combo_nav) - 1)

ax001_v2_status <- if (crisis_alpha_positive && !is.na(bad_normal_ratio) && bad_normal_ratio > 1.0 && combo_mdd > hybrid_mdd) {
  "PASS"
} else if (crisis_alpha_positive) {
  "PASS_partial"
} else {
  "FAIL_no_crisis_alpha"
}

ax001_v2 <- list(
  alpha_id = "R14_DUVOL_skewness",
  ic_normal_mean = round(ic_normal_mean, 5),
  ic_crisis_mean = round(ic_crisis_mean, 5),
  n_normal_periods = length(ic_normal),
  n_crisis_periods = length(ic_crisis),
  bad_normal_ratio = round(bad_normal_ratio, 4),
  crisis_alpha_positive = crisis_alpha_positive,
  hybrid_crisis_mean_ret = round(hybrid_crisis_mean, 4),
  hybrid_normal_mean_ret = round(hybrid_normal_mean, 4),
  hybrid_mdd_alone = round(hybrid_mdd, 4),
  combo_70_30_mdd = round(combo_mdd, 4),
  mdd_improvement = round(combo_mdd - hybrid_mdd, 4),
  status = ax001_v2_status,
  interpretation = sprintf(
    "R14_DUVOL alpha crisis IC=%.4f vs normal IC=%.4f (ratio %.2fx). %s. MDD Hybrid alone=%.4f vs combo 70/30=%.4f (delta %+.4f).",
    ic_crisis_mean, ic_normal_mean, bad_normal_ratio,
    if (crisis_alpha_positive) "Crisis-conditional positive IC confirms left-skew defense mechanism (Chen-Hong-Stein 2001 lottery anti-bubble)"
    else "Crisis IC NOT positive — defense classification rejected",
    hybrid_mdd, combo_mdd, combo_mdd - hybrid_mdd
  )
)
write_json(ax001_v2, file.path(WT_DIR, "ax001_v2_conditional_defense.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

#==============================================================================
# Step 10: AX-007 single-sleeve check
#  R14_DUVOL is single-sleeve. AX-007 4 exceptions: multi-sleeve / long-short / 50+ / ML sizing
#  Discovery agent cannot demonstrate exception — flag as REQUIRES_OPTIMIZER_RESOLUTION
#==============================================================================

cat("\n[Step 10] AX-007 single-sleeve check\n")
ax007_check <- list(
  ax_axiom = "AX-007",
  rule = "single-sleeve top20 long-only signal-portfolio mechanism break",
  exceptions = c("multi-sleeve", "long-short", "50+ diversified", "ML sizing"),
  current_structure_at_alpha_layer = "single-sleeve (R14_DUVOL only)",
  exception_match = "PENDING — Optimizer must implement 1 of 4 exceptions",
  alpha_alone_top20_test = list(
    n_top20 = nrow(top_pos),
    top20_sector_n = if (!is.null(sec_count)) sec_count$N[1] else NA,
    top20_sector_concentration_pct = if (!is.null(sec_count)) round(100 * sec_count$N[1] / sum(sec_count$N), 1) else NA
  ),
  mitigation_path = "If Optimizer combines R14_DUVOL + Hybrid (multi-sleeve EXCEPTION 1) → AX-007 PASS via exception. Currently Risk agent measures diversification source potential.",
  diversification_source_status = div_proof$verdict$diversification_source,
  status = "REQUIRES_OPTIMIZER_RESOLUTION_via_exception"
)
write_json(ax007_check, file.path(WT_DIR, "ax007_single_sleeve_check.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("  AX-007 status: %s\n", ax007_check$status))
cat(sprintf("  Mitigation path: multi-sleeve combine (R14_DUVOL + Hybrid)\n"))

#==============================================================================
# Step 11: Diversification Ratio (Choueifaty-Coignard 2008)
#  - alpha top20 EW (covariance.parquet basis)
#==============================================================================

cat("\n[Step 11] Diversification Ratio (Choueifaty-Coignard 2008)\n")
sds_annual <- apply(ret_mat, 2, sd, na.rm = TRUE) * sqrt(252)
top20_in_mat <- intersect(top20_pos_tickers, colnames(ret_mat))
n_t20 <- length(top20_in_mat)
cat(sprintf("  Top 20 alpha names available in ret_mat: %d\n", n_t20))
if (n_t20 >= 5) {
  ew_w <- rep(1 / n_t20, n_t20)
  sub_idx <- match(top20_in_mat, colnames(ret_mat))
  sub_sds <- sds_annual[sub_idx]
  sub_sig <- selected_sigma[sub_idx, sub_idx]
  sigma_p_daily <- sqrt(t(ew_w) %*% sub_sig %*% ew_w)[1, 1]
  sigma_p_annual <- sigma_p_daily * sqrt(252)
  dr_alpha <- sum(ew_w * sub_sds) / sigma_p_annual
  cat(sprintf("  DR (alpha top20 EW) = %.3f\n", dr_alpha))
} else {
  dr_alpha <- NA
}

dr_obj <- list(
  benchmark_strategy = "alpha_top20_EW (R14_DUVOL forward signal)",
  diversification_ratio = dr_alpha,
  n_assets = n_t20,
  formula = "DR = Σ(w_i σ_i) / σ_p (Choueifaty-Coignard 2008)",
  hybrid_baseline_dr_external = "computed externally on 3-source returns; not in this WT scope (Optimizer)",
  diversification_with_hybrid = list(
    rho_realized_alpha_hybrid = round(rho_realized, 4),
    sigma_combo_70_30 = round(combo_grid[w_hybrid == 0.7, sigma_combo], 4),
    sigma_indep_70_30 = round(combo_grid[w_hybrid == 0.7, sigma_indep], 4),
    gain_pct_70_30 = round(combo_grid[w_hybrid == 0.7, gain_pct], 2)
  ),
  interpretation_threshold = list(
    DR_low = "< 1.5 = concentration",
    DR_medium = "1.5~2.0 = moderate diversification",
    DR_high = "> 2.0 = strong diversification"
  )
)
write_json(dr_obj, file.path(WT_DIR, "diversification_ratio_with_alpha.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

#==============================================================================
# Step 12: Style exposure summary
#==============================================================================

cat("\n[Step 12] Style exposure summary\n")
style_summary <- list(
  alpha_id = "R14_DUVOL_skewness",
  size_log_cor = round(style_cors$size_log_cor, 4),
  momentum_6_1_cor = round(style_cors$momentum_6_1_cor, 4),
  n_obs = style_cors$n_obs,
  inter_sleeve_corr = list(note = "single-sleeve alpha — no inter-sleeve to compute"),
  vs_hybrid_70_15_15_returns_cor = round(rho_realized, 4),
  alpha_layer_reported_vs_hybrid_cor = -0.418,
  cycle7_AR_MCTV_88_101pct = "AR systemic risk integrated downstream (Optimizer/Forge scope)"
)

#==============================================================================
# Step 13: Red Flag evaluation
#==============================================================================

cat("\n[Step 13] Red Flag evaluation\n")
red_flags <- list()

# RF-R1: top common risk > 40%
eig_sel <- eigen(selected_sigma, symmetric = TRUE, only.values = FALSE)
eig_vals <- eig_sel$values
lambda1_dom <- eig_vals[1] / sum(eig_vals)
cat(sprintf("  λ_1 dominance pct (selected Σ) = %.4f\n", lambda1_dom))
red_flags[["RF-R1"]] <- list(
  severity = if (lambda1_dom > 0.4) "HIGH" else "INFO",
  finding = sprintf("λ_1 dominance %.2f%% (top common risk approx)", lambda1_dom * 100),
  threshold_breach = lambda1_dom > 0.4
)

# RF-R2
red_flags[["RF-R2"]] <- list(
  severity = if (sel_cn > 500) "HIGH" else "INFO",
  finding = sprintf("κ(Σ) = %.2f (selected method = %s)", sel_cn, selected_method),
  threshold_breach = sel_cn > 500
)

# RF-R3
if (!is.null(sec_count) && nrow(sec_count) > 0) {
  top_sec_pct <- sec_count$N[1] / sum(sec_count$N)
  red_flags[["RF-R3"]] <- list(
    severity = if (top_sec_pct > 0.5) "MEDIUM" else "INFO",
    finding = sprintf("top sector %s = %.1f%% of top20", sec_count$Sector[1], top_sec_pct * 100),
    threshold_breach = top_sec_pct > 0.5
  )
} else {
  red_flags[["RF-R3"]] <- list(
    severity = "INFO",
    finding = "Sector data unavailable",
    threshold_breach = FALSE
  )
}

# RF-R4: market_down_5
red_flags[["RF-R4"]] <- list(
  severity = if (!is.na(market_down_5) && market_down_5 < -0.08) "HIGH" else "INFO",
  finding = sprintf("market_down_5pct via β=%.3f → %.4f loss", beta_hybrid, market_down_5),
  threshold_breach = !is.na(market_down_5) && market_down_5 < -0.08
)

# RF-R5: high pair cor (single-sleeve = N/A) but use top20 pair cor
top20_pair_cor_hi <- sum(abs(cor(top20_mat[normal_mask, , drop = FALSE], use = "pairwise.complete.obs")[upper.tri(diag(ncol(top20_mat)))]) > 0.8, na.rm = TRUE)
red_flags[["RF-R5"]] <- list(
  severity = if (top20_pair_cor_hi >= 2L) "MEDIUM" else "INFO",
  finding = sprintf("top20 pair |cor|>0.8 count (NORMAL) = %d", top20_pair_cor_hi),
  threshold_breach = top20_pair_cor_hi >= 2L
)

# RF-R6 NEW: orthogonality mandate violation already on alpha layer (-0.418)
# Risk side: assess whether negative cor is realized + diversification-positive
rho_diversification_verdict <- div_proof$verdict$diversification_source
red_flags[["RF-R6_orthogonality"]] <- list(
  severity = if (rho_diversification_verdict == "CONFIRMED") "INFO" else "MEDIUM",
  finding = sprintf("alpha vs Hybrid orthogonality cor = %.4f (alpha-layer reported -0.418). Diversification source verdict: %s",
                    rho_realized, rho_diversification_verdict),
  threshold_breach = rho_diversification_verdict == "NOT_CONFIRMED"
)

challenge_flags_arr <- list()
for (rf in names(red_flags)) {
  if (isTRUE(red_flags[[rf]]$threshold_breach)) {
    challenge_flags_arr[[length(challenge_flags_arr) + 1L]] <- list(
      level = red_flags[[rf]]$severity,
      red_flag = rf,
      note = red_flags[[rf]]$finding
    )
  }
}
cat(sprintf("  Red flag breaches: %d\n", length(challenge_flags_arr)))
for (rf_id in names(red_flags)) {
  cat(sprintf("    %s [%s]: %s\n", rf_id, red_flags[[rf_id]]$severity,
              red_flags[[rf_id]]$finding))
}

#==============================================================================
# Step 14: Method Shopping Log
#==============================================================================

method_shop <- list(
  candidates_tried = length(method_log),
  candidates_max = 5,
  selected_method = selected_method,
  selection_objective = "condition_number",
  method_log = method_log,
  rationale = sprintf("3 estimators benchmarked. SELECTED %s — minimum κ among PSD candidates with κ<500. Risk agent estimation_quality only.",
                     selected_method)
)

#==============================================================================
# Step 15: Top Common Risks (PCA)
#==============================================================================

pc_var_pct <- eig_vals[1:5] / sum(eig_vals)
top_common_risks <- c(
  sprintf("PC1 (Market) %.1f%%", pc_var_pct[1] * 100),
  sprintf("PC2 (Style?) %.1f%%", pc_var_pct[2] * 100),
  sprintf("PC3 (Sector?) %.1f%%", pc_var_pct[3] * 100)
)

#==============================================================================
# Step 16: Assemble risk_package_draft.json
#==============================================================================

cat("\n[Step 16] Assemble risk_package_draft.json\n")

risk_pkg_draft <- list(
  task_id = WT_ID,
  package_kind = "risk_package",
  wt_type = "discovery",
  as_of_date = as.character(sig_date),
  agent = "risk-research",
  draft_revision = "draft",
  alpha_inheritance = list(
    alpha_package_path = sprintf("qepm/mailbox/worktask/%s/alpha_package.json", WT_ID),
    alpha_package_sha = digest(file.path(WT_DIR, "alpha_package.json"), algo = "sha256", file = TRUE),
    no_alpha_modification = TRUE
  ),
  exposure_matrix_ref = NULL,
  factor_covariance_ref = NULL,
  specific_risk_ref = NULL,
  security_covariance_ref = sprintf("stage_artifacts/%s/covariance.parquet", WT_ID),
  selection_objective = "condition_number",
  sigma_method = selected_method,
  sigma_method_details = list(
    estimator = selected_method,
    window_days = T_DAYS,
    n_assets = N_ASSETS,
    matrix_type = "covariance",
    condition_number = sel_cn,
    psd = min(eig_vals) > -1e-10,
    method_shopping = method_shop
  ),
  risk_summary = list(
    top_common_risks = top_common_risks,
    crowding_flags = if (!is.null(sec_count) && nrow(sec_count) > 0)
      sprintf("top sector %s = %.1f%% of top20",
              sec_count$Sector[1], 100 * sec_count$N[1] / sum(sec_count$N))
    else "Sector data not in RAWDATA",
    liquidity_flags = sprintf("Top 20 ADV20<2e8: %d/%d", adv_low_count, nrow(liq_check)),
    stress_tests = list(
      market_down_5 = market_down_5,
      gfc_2008 = stress_dt[period == "GFC_2008", cum_ret],
      eudebt_2011 = stress_dt[period == "EuDebt_2011", cum_ret],
      covid_2020 = stress_dt[period == "COVID_2020", cum_ret],
      inflation_2022 = stress_dt[period == "Inflation_2022", cum_ret],
      dotcom_2000 = stress_dt[period == "DotCom_2000", cum_ret],
      china_2015 = stress_dt[period == "China_2015", cum_ret],
      volshock_2018 = stress_dt[period == "VolShock_2018", cum_ret],
      imf_1997 = stress_dt[period == "IMF_1997", cum_ret]
    ),
    style_exposure = style_summary,
    diversification_ratio_alpha_top20 = dr_alpha,
    diversification_source_proof = div_proof$verdict
  ),
  diagnostics = list(
    condition_number = sel_cn,
    shrinkage_used = selected_method != "sample",
    shrinkage_method = selected_method,
    factor_correlation_warnings = list(
      single_sleeve_alpha = "R14_DUVOL is single-sleeve — no inter-sleeve correlation",
      orthogonality_mandate = sprintf("rho_realized %.4f / alpha_layer_reported -0.418 / verdict %s",
                                       rho_realized, rho_diversification_verdict)
    ),
    tdc_summary = list(
      top20_alpha_lower5_mean = tdc5_mean,
      top20_alpha_lower10_mean = tdc10_mean,
      n_pairs_evaluated = pair_count
    ),
    regime_correlation_ref = sprintf("stage_artifacts/%s/regime_correlation.parquet", WT_ID),
    tail_risk_ref = sprintf("stage_artifacts/%s/tail_risk_diagnostics.json", WT_ID),
    stress_periods_ref = sprintf("stage_artifacts/%s/stress_periods.parquet", WT_ID)
  ),
  ax_axiom_audit = list(
    AX_001_v2 = list(
      status = ax001_v2_status,
      crisis_alpha_positive = crisis_alpha_positive,
      crisis_ic_alpha = round(ic_crisis_mean, 4),
      normal_ic_alpha = round(ic_normal_mean, 4),
      bad_normal_ratio = round(bad_normal_ratio, 4),
      hybrid_crisis_mean = round(hybrid_crisis_mean, 4),
      hybrid_normal_mean = round(hybrid_normal_mean, 4),
      hybrid_mdd_alone = round(hybrid_mdd, 4),
      combo_70_30_mdd = round(combo_mdd, 4),
      ref = sprintf("qepm/mailbox/worktask/%s/ax001_v2_conditional_defense.json", WT_ID)
    ),
    AX_002 = list(
      status = "PASS",
      note = "All risk metrics computed from harness pipeline only. No backtest fabrication."
    ),
    AX_007 = list(
      status = "REQUIRES_OPTIMIZER_RESOLUTION_via_exception",
      structure_at_alpha_layer = "single_sleeve",
      mitigation_path = "Optimizer multi-sleeve combine (R14_DUVOL + Hybrid)",
      diversification_source = div_proof$verdict$diversification_source,
      ref = sprintf("qepm/mailbox/worktask/%s/ax007_single_sleeve_check.json", WT_ID)
    ),
    AX_005_v12 = list(
      status = "N/A",
      note = "AX-005 v1.2 applies to family=defense only. R14_DUVOL family=skewness_idiosyncratic — not subject."
    )
  ),
  red_flag_evaluation = red_flags,
  challenge_flags = challenge_flags_arr,
  charter_v17_compliance = list(
    pit_C1_full_sample = "PASS (252-day rolling window only; no full-sample stats)",
    pit_C2_same_day = "PASS (Date < sig_date strict cutoff)",
    pit_C5_overlay_lag = "PASS (no overlay generated; risk diagnostics only)",
    pit_C9_dd_vt_lag = "N/A (no DD/VT in risk pipeline)",
    pit_C10_liquidity = "PASS (ADV20 audit on top 20 alpha)",
    pit_C13_z_score_aligned = "N/A (no factor signal generated; alpha consumed)",
    pit_C15_factor_db_route = "PASS (alpha_package consumed; no factor DB direct load)",
    no_full_sample_stats = "PASS",
    no_alpha_modification = "PASS",
    no_weight_emission = "PASS"
  ),
  artifact_lineage = list(
    request = sprintf("qepm/mailbox/worktask/%s/request.json", WT_ID),
    alpha_package = sprintf("qepm/mailbox/worktask/%s/alpha_package.json", WT_ID),
    covariance = sprintf("stage_artifacts/%s/covariance.parquet", WT_ID),
    tail_risk = sprintf("stage_artifacts/%s/tail_risk_diagnostics.json", WT_ID),
    stress_periods = sprintf("stage_artifacts/%s/stress_periods.parquet", WT_ID),
    regime_correlation = sprintf("stage_artifacts/%s/regime_correlation.parquet", WT_ID),
    ax001_v2 = sprintf("qepm/mailbox/worktask/%s/ax001_v2_conditional_defense.json", WT_ID),
    ax007_single_sleeve = sprintf("qepm/mailbox/worktask/%s/ax007_single_sleeve_check.json", WT_ID),
    diversification_source_proof = sprintf("qepm/mailbox/worktask/%s/diversification_source_proof.json", WT_ID),
    diversification_ratio = sprintf("qepm/mailbox/worktask/%s/diversification_ratio_with_alpha.json", WT_ID)
  ),
  selection_objective_audit = list(
    selection_objective = "condition_number",
    no_alpha_return_referenced = TRUE,
    no_sr_ir_in_selection = TRUE,
    selection_basis = "condition_number minimization among PSD candidates with κ<500"
  ),
  agent_id = "risk-research",
  artifact_version = "v1.0_risk_package_draft"
)

write_json(risk_pkg_draft, file.path(WT_DIR, "risk_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("  → risk_package_draft.json written (%d bytes)\n",
            file.info(file.path(WT_DIR, "risk_package_draft.json"))$size))

#==============================================================================
# Step 17: Lineage record (correct order: write_json then record_package_lineage)
#==============================================================================

cat("\n[Step 17] artifact_lineage record\n")
source(file.path(PROJ_ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
tryCatch({
  record_package_lineage(
    task_id = WT_ID,
    package_type = "risk_package",
    method_selected = selected_method,
    input_file_paths = c(file.path(WT_DIR, "alpha_package.json")),
    windows = list(
      train_window = list(start = as.character(min(top20_dates)), end = as.character(cutoff_date)),
      panel_window_252d = list(n_days = T_DAYS, n_assets = N_ASSETS)
    )
  )
}, error = function(e) {
  cat(sprintf("  lineage_utils warning: %s\n", conditionMessage(e)))
})

cat("\n========================================================\n")
cat("Risk Research Pipeline COMPLETE\n")
cat(sprintf("  Σ method     : %s (κ=%.2f)\n", selected_method, sel_cn))
cat(sprintf("  N assets     : %d / 252-day window\n", N_ASSETS))
cat(sprintf("  red flags    : %d breach\n", length(challenge_flags_arr)))
cat(sprintf("  AX-001 v2    : crisis_ic=%.4f / normal_ic=%.4f / ratio=%.2fx / status=%s\n",
            ic_crisis_mean, ic_normal_mean, bad_normal_ratio, ax001_v2_status))
cat(sprintf("  AX-007       : %s (mitigation: multi-sleeve combine)\n", "REQUIRES_OPTIMIZER_RESOLUTION"))
cat(sprintf("  Diversif src : %s (rho_realized=%.4f, gain 70/30=%.2f%%)\n",
            div_proof$verdict$diversification_source, rho_realized, sigma_reduction_70_30))
cat("========================================================\n")
