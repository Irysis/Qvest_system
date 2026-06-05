#==============================================================================
# Step 4 — Full Validation v3.6 (Harvey 5-spec + Subperiod + DSR + AX-001 v2)
#
# v3.6 final graduation diagnostics on regime-weighted sector-neutralized composite
# Computed metrics:
#   - Rank IC mean + ICIR + NW-t
#   - Harvey-Liu-Zhu 2016 5-spec t-stat (A=raw IC, B=resid, C=quintile spread,
#       D=top decile minus market, E=regime residual)
#   - Subperiod stability (2017-19 / 2020-22 / 2023+)
#   - DSR (Bailey-Lopez de Prado, n_trials adjusted)
#   - AX-001 v2 bad/normal IC ratio (drawdown periods vs normal)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_6")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003_v3_6")
ALPHA_RW <- file.path(OUT_DIR, "alpha_regime_weighted_neut_v36.parquet")
RAWDATA <- file.path(BASE, ".cache/rawdata.parquet")
REGIME_MONTHLY <- file.path(OUT_DIR, "regime_labels_monthly_v36.parquet")
BENCHMARK_PATH <- file.path(BASE, ".cache/benchmark.parquet")

cat("[Validation v3.6] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load alpha + fwd ----
cat("[1] Loading alpha_rw + fwd ...\n")
alpha_dt <- as.data.table(read_parquet(ALPHA_RW))
alpha_dt[, Date := as.Date(Date)]
sig_dates <- sort(unique(alpha_dt$Date))
cat("  N sig_dates:", length(sig_dates), " | n_obs:", nrow(alpha_dt), "\n")

# ---- 2. Per-Date IC + Quintile spread + Top decile market spread ----
cat("[2] Per-date IC + decile / quintile diagnostics ...\n")

# Benchmark return per period (K200_TR)
bm <- tryCatch(as.data.table(read_parquet(BENCHMARK_PATH)), error = function(e) NULL)
if (!is.null(bm) && "Date" %in% names(bm)) {
  bm[, Date := as.Date(Date)]
}

# Compute benchmark forward return per sig_date (1M)
# Use sig_date level — interpolation from BM panel.
# If unavailable, market_ret = mean(fwd_ret) per sig_date.
ic_metrics <- list()
for (i in seq_along(sig_dates)) {
  sig_d <- sig_dates[i]
  sub <- alpha_dt[Date == sig_d]
  valid <- !is.na(sub$alpha_rw) & !is.na(sub$fwd_ret)
  if (sum(valid) < 20L) next
  x <- sub$alpha_rw[valid]
  y <- sub$fwd_ret[valid]
  ic_raw <- suppressWarnings(cor(x, y, method = "spearman"))

  # Quintiles
  qs <- quantile(x, c(0.2, 0.4, 0.6, 0.8), na.rm = TRUE)
  bot <- y[x <= qs[1]]
  top <- y[x >= qs[4]]
  q_spread <- mean(top, na.rm = TRUE) - mean(bot, na.rm = TRUE)

  # Top decile vs market (market = mean(y))
  d_top <- quantile(x, 0.9, na.rm = TRUE)
  top_dec <- y[x >= d_top]
  top_minus_mkt <- mean(top_dec, na.rm = TRUE) - mean(y, na.rm = TRUE)

  # CAPM residual IC (using fwd_ret - cross-section mean as residual)
  resid <- y - mean(y, na.rm = TRUE)
  ic_resid <- suppressWarnings(cor(x, resid, method = "spearman"))

  ic_metrics[[i]] <- list(
    Date = sig_d, n = sum(valid),
    ic_raw = ic_raw, ic_resid = ic_resid,
    q_spread = q_spread, top_minus_mkt = top_minus_mkt
  )
}
ic_dt <- rbindlist(ic_metrics, fill = TRUE, use.names = TRUE)
ic_dt[, Date := as.Date(Date)]
cat("  IC metrics rows:", nrow(ic_dt), "\n")

# ---- 3. Harvey-Liu-Zhu 5-spec t-stats (NW lag 6) ----
cat("[3] Harvey-NW 5-spec t-stats ...\n")

nw_tstat <- function(x, h = 6L) {
  x <- x[!is.na(x)]
  n <- length(x)
  if (n < 12L) return(list(t = NA_real_, n = n))
  mu <- mean(x)
  gamma0 <- var(x)
  if (n > h) {
    gammas <- sapply(1:h, function(k) cov(x[1:(n-k)], x[(1+k):n]))
    bw <- 1 - (1:h) / (h + 1)
    lrv <- max(gamma0 + 2 * sum(bw * gammas), 1e-10)
  } else {
    lrv <- gamma0
  }
  se <- sqrt(lrv / n)
  list(t = mu / se, n = n, mean = mu, se = se)
}

# Load regime labels for spec E
regime <- as.data.table(read_parquet(REGIME_MONTHLY))
regime[, Date := as.Date(Date)]
regime[, ym := format(Date, "%Y-%m")]
ic_dt[, ym := format(Date, "%Y-%m")]
ic_with_regime <- merge(ic_dt, regime[, .(ym, regime_state)], by = "ym", all.x = TRUE)
ic_with_regime[, regime_state_lag1 := shift(regime_state, n = 1L, type = "lag")]
# Within-state residual (subtract state mean)
ic_with_regime[, ic_regime_resid := ic_raw - mean(ic_raw, na.rm = TRUE),
                  by = regime_state_lag1]

spec_A <- nw_tstat(ic_dt$ic_raw)
spec_B <- nw_tstat(ic_dt$ic_resid)
spec_C <- nw_tstat(ic_dt$q_spread)
spec_D <- nw_tstat(ic_dt$top_minus_mkt)
spec_E <- nw_tstat(ic_with_regime$ic_regime_resid)

cat(sprintf("  A_raw_ic         : t=%.4f n=%d\n", spec_A$t, spec_A$n))
cat(sprintf("  B_resid_naive    : t=%.4f n=%d\n", spec_B$t, spec_B$n))
cat(sprintf("  C_quintile_spread: t=%.4f n=%d\n", spec_C$t, spec_C$n))
cat(sprintf("  D_top_dec_minus_m: t=%.4f n=%d\n", spec_D$t, spec_D$n))
cat(sprintf("  E_regime_resid   : t=%.4f n=%d\n", spec_E$t, spec_E$n))

ts_at_3 <- c(spec_A$t, spec_B$t, spec_C$t, spec_D$t, spec_E$t)
ts_at_3 <- ts_at_3[!is.na(ts_at_3)]
n_pass_3 <- sum(ts_at_3 > 3.0)
n_pass_25 <- sum(ts_at_3 > 2.5)
cat(sprintf("  HARVEY: %d/5 t>3.0 (need 3/5), %d/5 t>2.5\n", n_pass_3, n_pass_25))

# ---- 4. Subperiod stability ----
cat("[4] Subperiod stability ...\n")
ic_dt[, period := fcase(
  Date < as.Date("2020-01-01"), "2017-19",
  Date < as.Date("2023-01-01"), "2020-22",
  default = "2023+"
)]
period_ic <- ic_dt[, .(N = .N, mean_ic = mean(ic_raw, na.rm = TRUE),
                         sd_ic = sd(ic_raw, na.rm = TRUE),
                         icir = mean(ic_raw, na.rm = TRUE) / sd(ic_raw, na.rm = TRUE)),
                     by = period]
setorder(period_ic, period)
cat("  Per-period:\n")
print(period_ic)
sub_stab <- mean(period_ic$mean_ic > 0)
cat(sprintf("  Subperiod stability (frac periods with mean_ic > 0): %.2f\n", sub_stab))

# ---- 5. DSR (Bailey-Lopez de Prado) ----
cat("[5] DSR (Bailey-Lopez de Prado) ...\n")
# Conservative: n_trials = 18 (number of signals tried: 8 raw + 8 neut + 1 eq-w + 1 regime-w)
n_trials <- 18L

ic_vec <- ic_dt$ic_raw[!is.na(ic_dt$ic_raw)]
n <- length(ic_vec)
sr_obs <- mean(ic_vec) / sd(ic_vec) * sqrt(12L)  # annualized

if (n > 30L) {
  # Skew + Kurt of IC distribution
  sk <- sum((ic_vec - mean(ic_vec))^3) / (n * sd(ic_vec)^3)
  ku <- sum((ic_vec - mean(ic_vec))^4) / (n * sd(ic_vec)^4)

  # Expected max SR under null with n_trials
  z_alpha <- qnorm(1 - 0.5 / n_trials)
  expected_max_sr <- z_alpha - (z_alpha^2 - 1) / (2 * z_alpha + 1e-10)

  # Standard error of SR
  se_sr <- sqrt((1 - sk * (sr_obs / sqrt(12)) +
                    (ku - 1) / 4 * (sr_obs / sqrt(12))^2) / (n - 1))

  # DSR z-score
  dsr_z <- (sr_obs / sqrt(12) - expected_max_sr) / max(se_sr, 1e-10)
  dsr <- pnorm(dsr_z)

  cat(sprintf("  Annual SR (raw IC): %.4f\n", sr_obs))
  cat(sprintf("  n_trials: %d, n_obs: %d, skew: %.3f, kurt: %.3f\n", n_trials, n, sk, ku))
  cat(sprintf("  Expected_max_SR: %.4f, SE: %.4f, DSR_z: %.4f\n",
               expected_max_sr, se_sr, dsr_z))
  cat(sprintf("  DSR (probability): %.4f\n", dsr))
} else {
  dsr <- NA_real_
  cat("  Insufficient n for DSR\n")
}

# ---- 6. AX-001 v2 bad/normal IC ratio ----
cat("[6] AX-001 v2 crisis_alpha (bad/normal IC ratio) ...\n")
# Bad periods: COVID 2020-03, 2022-09 (KR slump), 2023-04 (tightening)
# Identify by extreme negative market returns
bad_dates <- as.Date(c("2020-03-31", "2020-04-30", "2022-09-30", "2022-10-31", "2023-04-30"))
ic_dt[, period_type := fifelse(Date %in% bad_dates, "bad", "normal")]
bad_mean <- mean(ic_dt[period_type == "bad", ic_raw], na.rm = TRUE)
normal_mean <- mean(ic_dt[period_type == "normal", ic_raw], na.rm = TRUE)
bn_ratio <- if (abs(normal_mean) > 1e-10) bad_mean / normal_mean else NA_real_
cat(sprintf("  Bad period mean IC: %.4f (n=%d)\n", bad_mean,
             sum(ic_dt$period_type == "bad")))
cat(sprintf("  Normal period mean IC: %.4f (n=%d)\n", normal_mean,
             sum(ic_dt$period_type == "normal")))
cat(sprintf("  Bad/Normal ratio: %.4f (AX-001 v2 PASS if ratio >= 0.5 OR bad > 0)\n", bn_ratio))
ax001_v2_pass <- (bad_mean > 0) || (!is.na(bn_ratio) && bn_ratio >= 0.5)

# ---- 7. Monotonicity (decile spread) ----
cat("[7] Monotonicity (decile spread) ...\n")
dec_mono <- list()
for (sig_d in sig_dates) {
  sub <- alpha_dt[Date == sig_d & !is.na(alpha_rw) & !is.na(fwd_ret)]
  if (nrow(sub) < 30L) next
  sub[, dec := cut(alpha_rw, breaks = quantile(alpha_rw, probs = seq(0, 1, 0.1), na.rm = TRUE),
                     labels = 1:10, include.lowest = TRUE)]
  dec_mean <- sub[, .(mean_ret = mean(fwd_ret, na.rm = TRUE)), by = dec][order(dec)]
  if (nrow(dec_mean) == 10L) {
    spread <- dec_mean$mean_ret[10] - dec_mean$mean_ret[1]
    mono <- cor(seq_len(10L), dec_mean$mean_ret)
    dec_mono[[length(dec_mono) + 1L]] <- list(Date = sig_d, spread = spread, mono_cor = mono)
  }
}
mono_dt <- rbindlist(dec_mono, fill = TRUE, use.names = TRUE)
mean_mono_cor <- mean(mono_dt$mono_cor, na.rm = TRUE)
mean_spread_d10_d1 <- mean(mono_dt$spread, na.rm = TRUE)
cat(sprintf("  Mean monotonicity correlation: %.4f\n", mean_mono_cor))
cat(sprintf("  Mean decile 10 - decile 1 spread: %.4f\n", mean_spread_d10_d1))

# ---- 8. Turnover proxy ----
cat("[8] Turnover proxy ...\n")
setorder(alpha_dt, Ticker, Date)
turnover_list <- list()
for (i in 2:length(sig_dates)) {
  d0 <- sig_dates[i - 1]
  d1 <- sig_dates[i]
  a0 <- alpha_dt[Date == d0, .(Ticker, a0 = alpha_rw)]
  a1 <- alpha_dt[Date == d1, .(Ticker, a1 = alpha_rw)]
  merged <- merge(a0, a1, by = "Ticker", all = TRUE)
  merged[is.na(a0), a0 := 0]
  merged[is.na(a1), a1 := 0]
  # Top decile turnover
  q90_0 <- quantile(merged$a0, 0.9, na.rm = TRUE)
  q90_1 <- quantile(merged$a1, 0.9, na.rm = TRUE)
  top0 <- merged[a0 >= q90_0, Ticker]
  top1 <- merged[a1 >= q90_1, Ticker]
  tov <- length(setdiff(top1, top0)) / max(length(top1), 1)
  turnover_list[[i - 1]] <- list(Date = d1, top_decile_turnover = tov)
}
tov_dt <- rbindlist(turnover_list, fill = TRUE, use.names = TRUE)
mean_top_tov <- mean(tov_dt$top_decile_turnover, na.rm = TRUE) * 12  # annual
cat(sprintf("  Mean annual top-decile turnover: %.2f\n", mean_top_tov))

# ---- 9. Final summary ----
cat("[9] Summary ...\n")
icir_overall <- mean(ic_dt$ic_raw, na.rm = TRUE) / sd(ic_dt$ic_raw, na.rm = TRUE)

summary <- list(
  rank_ic = round(mean(ic_dt$ic_raw, na.rm = TRUE), 4),
  rank_ic_sd = round(sd(ic_dt$ic_raw, na.rm = TRUE), 4),
  icir = round(icir_overall, 4),
  harvey_5_spec = list(
    A_raw_ic = list(t_nw_lag6 = round(spec_A$t, 4), n = spec_A$n),
    B_resid_naive = list(t_nw_lag6 = round(spec_B$t, 4), n = spec_B$n),
    C_top_minus_bot_quintile = list(t_nw_lag6 = round(spec_C$t, 4), n = spec_C$n),
    D_top_decile_minus_market = list(t_nw_lag6 = round(spec_D$t, 4), n = spec_D$n),
    E_regime_residual = list(t_nw_lag6 = round(spec_E$t, 4), n = spec_E$n)
  ),
  harvey_n_pass_3 = n_pass_3,
  harvey_n_pass_25 = n_pass_25,
  subperiod_stability_frac = round(sub_stab, 4),
  subperiod_detail = period_ic,
  dsr = round(dsr, 4),
  n_trials = n_trials,
  bad_normal_ic_ratio = round(bn_ratio, 4),
  ax001_v2_pass = ax001_v2_pass,
  bad_period_mean_ic = round(bad_mean, 4),
  bad_period_n = sum(ic_dt$period_type == "bad"),
  monotonicity_correlation = round(mean_mono_cor, 4),
  decile_spread_d10_d1 = round(mean_spread_d10_d1, 4),
  annual_top_decile_turnover = round(mean_top_tov, 4)
)

writeLines(toJSON(summary, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(OUT_DIR, "alpha_validation_v36.json"))

# Save IC per-date for downstream
write_parquet(ic_dt, file.path(OUT_DIR, "ic_per_date_validated_v36.parquet"))
write_parquet(ic_dt, file.path(STAGE_DIR, "ic_per_date_validated_v36.parquet"))

cat("\n[Validation v3.6] === DONE === elapsed:",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2), "min\n")
cat("\n=== GRADUATION SUMMARY ===\n")
cat(sprintf("  Rank IC                : %.4f (need >= 0.04)\n", summary$rank_ic))
cat(sprintf("  ICIR                   : %.4f (need >= 0.20)\n", summary$icir))
cat(sprintf("  Harvey t>3.0           : %d/5 (need 3/5)\n", n_pass_3))
cat(sprintf("  Harvey t>2.5           : %d/5\n", n_pass_25))
cat(sprintf("  Subperiod stability    : %.2f (need >= 0.50)\n", sub_stab))
cat(sprintf("  DSR                    : %.4f (need >= 0.5)\n", dsr))
cat(sprintf("  AX-001 v2 bad/normal   : %.4f (need >= 0.50)\n", bn_ratio))
cat(sprintf("  Monotonicity           : %.4f (need >= 0.70)\n", mean_mono_cor))
cat(sprintf("  Annual top-decile TO   : %.2f (need <= 3.0)\n", mean_top_tov))
