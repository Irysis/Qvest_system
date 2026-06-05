#==============================================================================
# Step 6 — Alpha Validation (IC + ICIR + Harvey-t + DSR + Monotonicity + Subperiod)
#
# Test ladder:
#   1. Rank IC (Spearman) per sig_date — α̂(i,t) vs r(i,t+1M)
#   2. ICIR = mean(IC) / sd(IC)
#   3. Monotonicity (decile spread top-bottom return)
#   4. Subperiod stability (3 chunks: 2017-19, 2020-21, 2022-23)
#   5. Harvey-Liu-Zhu 2016 multi-specification t-stat:
#        spec_a: alpha_score raw
#        spec_b: alpha_score residualized vs equal-weight baseline (composite Z naive)
#        spec_c: top quintile vs bottom quintile (decile spread)
#        spec_d: alpha_score × confidence
#        spec_e: alpha_score residualized vs regime_state dummy
#      Each spec → Newey-West t-stat (lag = 1M).
#      Harvey 3.0 threshold: at least 3 of 5 specs > 3.0.
#   6. Bad/normal IC ratio (AX-001 v2 conditional alpha):
#        Bad regimes: var_05_22 < bottom 25% (high downside risk states)
#        Normal: else
#        Ratio = IC_bad / IC_normal (should be > 0.5 for crisis_alpha)
#   7. Bailey-Lopez de Prado DSR (Deflated Sharpe Ratio):
#        n_trials = 6 (one per family) — DSR(SR_observed)
#   8. Turnover proxy (top20 churn ratio per sig_date)
#
# Inputs:
#   - stage_artifacts/WT_D20260528_003/alpha_scores.parquet
#   - rawdata (forward return per ticker)
#   - regime_labels_monthly (regime state)
# Output:
#   - stage_artifacts/WT_D20260528_003/alpha_validation.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs")
SHARED_OUT <- file.path(BASE, "04_Research/decision_framework/smart_beta_regime/outputs")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003")
RAWDATA <- file.path(BASE, ".cache/rawdata.parquet")

HORIZON <- 21L
WINS_LOW <- -0.30
WINS_HIGH <- 0.30
N_TRIALS_HARVEY <- 5L
N_TRIALS_DSR <- 6L  # 6 families tested as alternatives

cat("[Step 6 Alpha Validation] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load alpha_scores + compute forward returns ----
cat("[1] Loading alpha_scores ...\n")
a <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores.parquet")))
a[, Date := as.Date(Date)]
setorder(a, Date, Ticker)
cat("  alpha rows:", nrow(a), " | distinct sig_dates:", uniqueN(a$Date), "\n")

# Forward 21d simple return (winsorized) per ticker
cat("[1b] Computing forward 21d returns ...\n")
rd <- as.data.table(read_parquet(RAWDATA, col_select = c("Date", "Ticker", "Close")))
rd[, Date := as.Date(Date)]
setorder(rd, Ticker, Date)
rd[, log_close := log(pmax(Close, 0.01))]
rd[, fwd_log_ret := shift(log_close, n = HORIZON, type = "lead") - log_close, by = Ticker]
rd[, fwd_simple_ret := exp(fwd_log_ret) - 1]
rd[, fwd_simple_ret_winsor := pmin(pmax(fwd_simple_ret, WINS_LOW), WINS_HIGH)]

# Merge alpha with forward returns (sig_date Date = same trading day → fwd_simple_ret @ Date)
alpha_with_ret <- merge(
  a, rd[, .(Date, Ticker, fwd_simple_ret_winsor)],
  by = c("Date", "Ticker"), all.x = TRUE
)
n_with_ret <- sum(!is.na(alpha_with_ret$fwd_simple_ret_winsor))
cat("  Merged rows with forward return:", n_with_ret, "/", nrow(alpha_with_ret), "\n")

# ---- 2. Rank IC per sig_date ----
cat("[2] Computing Rank IC per sig_date ...\n")
compute_ic <- function(dt, alpha_col = "alpha_score", ret_col = "fwd_simple_ret_winsor") {
  dt <- dt[!is.na(get(alpha_col)) & !is.na(get(ret_col))]
  if (nrow(dt) < 20) return(NA_real_)
  suppressWarnings(cor(dt[[alpha_col]], dt[[ret_col]], method = "spearman"))
}

ic_by_date <- alpha_with_ret[, .(rank_ic = compute_ic(.SD), n = .N), by = Date]
ic_by_date <- ic_by_date[!is.na(rank_ic)]
cat("  IC obs:", nrow(ic_by_date), " | mean IC:", round(mean(ic_by_date$rank_ic), 4),
    " | sd:", round(sd(ic_by_date$rank_ic), 4), "\n")

icir <- mean(ic_by_date$rank_ic) / sd(ic_by_date$rank_ic)
mean_ic <- mean(ic_by_date$rank_ic)

# ---- 3. Monotonicity (decile spread) ----
cat("[3] Computing decile spread (monotonicity) ...\n")
decile_returns <- alpha_with_ret[!is.na(alpha_score) & !is.na(fwd_simple_ret_winsor),
  {
    # rank-based decile cut (robust to duplicate quantile breaks)
    r <- frank(alpha_score, ties.method = "average") / .N
    d <- pmin(10L, pmax(1L, ceiling(r * 10)))
    list(decile = d, ret = fwd_simple_ret_winsor)
  }, by = Date][, .(mean_ret = mean(ret, na.rm = TRUE)), by = .(Date, decile)]

decile_avg <- decile_returns[, .(mean_ret = mean(mean_ret, na.rm = TRUE)), by = decile]
setorder(decile_avg, decile)
cat("  Decile mean returns:\n")
print(decile_avg)

# Top-bottom spread
top_dec <- decile_avg[decile == 10, mean_ret]
bot_dec <- decile_avg[decile == 1, mean_ret]
spread <- top_dec - bot_dec

# Spearman corr of decile rank with mean return
mono_corr <- suppressWarnings(cor(decile_avg$decile, decile_avg$mean_ret,
                                    method = "spearman"))

# ---- 4. Subperiod stability (3 chunks 2017-19, 2020-21, 2022-23) ----
cat("[4] Subperiod stability ...\n")
ic_by_date[, ym := format(Date, "%Y")]
ic_by_date[, subperiod := fcase(
  ym >= "2017" & ym <= "2019", "P1_2017_19",
  ym >= "2020" & ym <= "2021", "P2_2020_21",
  ym >= "2022" & ym <= "2023", "P3_2022_23",
  default = "other"
)]
sub_ic <- ic_by_date[subperiod != "other",
                       .(mean_ic = mean(rank_ic), sd_ic = sd(rank_ic), n = .N),
                       by = subperiod]
setorder(sub_ic, subperiod)
cat("  Per-subperiod IC:\n")
print(sub_ic)

# stability = min(positive_signs) / 3 if all positive, else lower
sub_signs <- sign(sub_ic$mean_ic)
n_pos <- sum(sub_signs > 0)
subperiod_stability <- n_pos / 3.0
cat("  Subperiod stability (fraction positive):", subperiod_stability, "\n")

# Stability via IC consistency: 1 - sd(sub_ic) / abs(overall mean)
stability_cv <- if (abs(mean_ic) > 0) 1 - (sd(sub_ic$mean_ic) / abs(mean_ic)) else NA_real_
cat("  Stability CV (1 - sd_subperiod / |mean overall|):", round(stability_cv, 3), "\n")

# ---- 5. Harvey-Liu-Zhu 2016 multi-spec ----
cat("[5] Harvey-Liu-Zhu 2016 multi-spec test ...\n")

# Newey-West t-stat for IC series
# IC series is monthly → lag = 1 (Andrews 1991 auto)
nw_tstat <- function(x, lag = 1L) {
  x <- x[!is.na(x)]
  n <- length(x)
  if (n < 5L) return(NA_real_)
  m <- mean(x)
  v <- var(x)
  # Newey-West weighted variance
  nw_var <- v
  if (lag > 0L) {
    for (k in 1:lag) {
      w <- 1 - k / (lag + 1L)
      auto_cov <- mean((x[1:(n - k)] - m) * (x[(k + 1):n] - m))
      nw_var <- nw_var + 2 * w * auto_cov
    }
  }
  nw_var <- max(nw_var, 1e-10)
  m / sqrt(nw_var / n)
}

# Spec A: raw α̂ IC
spec_a_ic <- ic_by_date$rank_ic
spec_a_t <- nw_tstat(spec_a_ic, lag = 1L)

# Spec B: α̂ residualized vs naive equal-weight composite Z
# Naive baseline: simple average across 6 family Z (no regime weight)
cat("[5b] Spec B baseline ...\n")
naive_a <- alpha_with_ret[, naive_alpha := rowMeans(.SD, na.rm = TRUE),
                            .SDcols = paste0("Z_", c("value","quality","momentum","low_vol","size","dividend"))]
# Per sig_date Spearman IC of naive vs raw - need cross-sectional residual
# Approach: at each sig_date, residualize alpha_score on naive_alpha, then IC vs ret
spec_b_ic <- alpha_with_ret[!is.na(naive_alpha) & !is.na(alpha_score) & !is.na(fwd_simple_ret_winsor),
  {
    if (.N < 30) NA_real_
    else {
      r <- tryCatch(residuals(lm(alpha_score ~ naive_alpha)),
                     error = function(e) rep(NA_real_, .N))
      if (all(is.na(r))) NA_real_
      else suppressWarnings(cor(r, fwd_simple_ret_winsor, method = "spearman"))
    }
  }, by = Date]$V1
spec_b_ic <- spec_b_ic[!is.na(spec_b_ic)]
spec_b_t <- nw_tstat(spec_b_ic, lag = 1L)

# Spec C: top quintile vs bottom quintile spread (per sig_date) — t-stat of spread
spec_c_spread <- alpha_with_ret[!is.na(alpha_score) & !is.na(fwd_simple_ret_winsor),
  {
    q <- quantile(alpha_score, c(0.2, 0.8), na.rm = TRUE)
    bot <- mean(fwd_simple_ret_winsor[alpha_score <= q[1]], na.rm = TRUE)
    top <- mean(fwd_simple_ret_winsor[alpha_score >= q[2]], na.rm = TRUE)
    top - bot
  }, by = Date]$V1
spec_c_spread <- spec_c_spread[!is.na(spec_c_spread)]
spec_c_t <- nw_tstat(spec_c_spread, lag = 1L)

# Spec D: α̂ × confidence weighted IC
spec_d_ic <- alpha_with_ret[!is.na(alpha_score) & !is.na(fwd_simple_ret_winsor) & !is.na(confidence),
  {
    if (.N < 30) NA_real_
    else {
      x <- alpha_score * confidence
      suppressWarnings(cor(x, fwd_simple_ret_winsor, method = "spearman"))
    }
  }, by = Date]$V1
spec_d_ic <- spec_d_ic[!is.na(spec_d_ic)]
spec_d_t <- nw_tstat(spec_d_ic, lag = 1L)

# Spec E: α̂ residualized vs regime_state dummy (9-level cluster mean)
spec_e_ic <- alpha_with_ret[!is.na(alpha_score) & !is.na(fwd_simple_ret_winsor) & !is.na(regime_state),
  {
    if (.N < 30 || uniqueN(regime_state) < 2L) NA_real_
    else {
      x <- alpha_score - ave(alpha_score, regime_state, FUN = function(v) mean(v, na.rm = TRUE))
      suppressWarnings(cor(x, fwd_simple_ret_winsor, method = "spearman"))
    }
  }, by = Date]$V1
spec_e_ic <- spec_e_ic[!is.na(spec_e_ic)]
spec_e_t <- nw_tstat(spec_e_ic, lag = 1L)

harvey_specs <- data.table(
  spec = c("A_raw", "B_residual_naive", "C_top_minus_bot_spread", "D_conf_weighted", "E_residual_regime"),
  t_stat = c(spec_a_t, spec_b_t, spec_c_t, spec_d_t, spec_e_t),
  n_obs = c(length(spec_a_ic), length(spec_b_ic), length(spec_c_spread), length(spec_d_ic), length(spec_e_ic))
)
cat("  Harvey-Liu-Zhu 2016 multi-spec result:\n")
print(harvey_specs)
n_passes_3 <- sum(harvey_specs$t_stat > 3.0, na.rm = TRUE)
n_passes_25 <- sum(harvey_specs$t_stat > 2.5, na.rm = TRUE)
cat("  Specs > 3.0:", n_passes_3, "/ 5\n")
cat("  Specs > 2.5:", n_passes_25, "/ 5\n")

# ---- 6. Bad/Normal IC ratio (AX-001 v2) ----
cat("[6] Bad/Normal IC ratio ...\n")
# Bad regime: states with high var_05_22 magnitude (top quartile of |var_05_22|)
# Load regime daily for var_05_22 mapping per sig_date
rd_regime <- as.data.table(read_parquet(file.path(SHARED_OUT, "regime_labels_daily.parquet"),
                                          col_select = c("Date", "regime_state", "var_05_22")))
rd_regime[, Date := as.Date(Date)]
# Per regime_state: median |var_05_22|
state_var <- rd_regime[, .(med_var_05 = median(abs(var_05_22), na.rm = TRUE)), by = regime_state]
setorder(state_var, regime_state)
# bad states: top 25% by |var_05_22|
state_var[, is_bad := med_var_05 >= quantile(med_var_05, 0.75, na.rm = TRUE)]
bad_states <- state_var[is_bad == TRUE, regime_state]
cat("  Bad regime states (top 25% |var_05_22|):", paste(bad_states, collapse = ","), "\n")

ic_by_date[, regime_state := alpha_with_ret[match(ic_by_date$Date, Date), regime_state]]
ic_by_date[, is_bad := regime_state %in% bad_states]
bad_ic <- mean(ic_by_date[is_bad == TRUE, rank_ic], na.rm = TRUE)
nor_ic <- mean(ic_by_date[is_bad == FALSE, rank_ic], na.rm = TRUE)
bad_norm_ratio <- if (abs(nor_ic) > 0) bad_ic / nor_ic else NA_real_
cat(sprintf("  Bad IC: %.4f | Normal IC: %.4f | Ratio: %.3f (>0.5 = crisis_alpha)\n",
            bad_ic, nor_ic, bad_norm_ratio))

# ---- 7. Bailey-Lopez de Prado Deflated Sharpe Ratio ----
cat("[7] Bailey-Lopez de Prado DSR ...\n")
# SR of monthly IC time series (treating IC as "return")
sr_observed <- mean(ic_by_date$rank_ic) / sd(ic_by_date$rank_ic) * sqrt(12)  # annualized
T_obs <- nrow(ic_by_date)
# Bailey-Lopez de Prado 2014: DSR formula
# E[max SR] approximation under N_TRIALS_DSR trials
# Σ_E_maxsr = (1 - γ) * Φ^(-1)(1 - 1/N) + γ * Φ^(-1)(1 - 1/(N*e))
# where γ = Euler-Mascheroni ≈ 0.5772
gamma_em <- 0.5772156649
exp_maxsr <- (1 - gamma_em) * qnorm(1 - 1/N_TRIALS_DSR) +
              gamma_em * qnorm(1 - 1/(N_TRIALS_DSR * exp(1)))

# Skewness, kurtosis of IC
ic_skew <- mean((ic_by_date$rank_ic - mean(ic_by_date$rank_ic))^3) /
              sd(ic_by_date$rank_ic)^3
ic_kurt <- mean((ic_by_date$rank_ic - mean(ic_by_date$rank_ic))^4) /
              sd(ic_by_date$rank_ic)^4

# DSR formula (annualized SR)
sr_annual <- mean(ic_by_date$rank_ic) / sd(ic_by_date$rank_ic) * sqrt(12)
denom <- sqrt((1 - ic_skew * sr_annual / sqrt(12) + (ic_kurt - 1) / 4 * (sr_annual / sqrt(12))^2) / (T_obs - 1))
z_dsr <- (sr_annual / sqrt(12) - exp_maxsr) / pmax(denom, 1e-10)
dsr <- pnorm(z_dsr)
cat(sprintf("  SR_annual: %.3f | T: %d | DSR: %.3f (>0.5 = above-random)\n",
            sr_annual, T_obs, dsr))

# ---- 8. Turnover proxy (top20 churn) ----
cat("[8] Top20 churn proxy ...\n")
top20_by_date <- alpha_with_ret[!is.na(alpha_score), .SD[rank_within_universe <= 20L], by = Date]
sig_dates <- sort(unique(top20_by_date$Date))
churn_rates <- c()
prev_top <- character(0)
for (sd_i in sig_dates) {
  this_top <- top20_by_date[Date == sd_i, Ticker]
  if (length(prev_top) > 0) {
    churn <- length(setdiff(this_top, prev_top)) / 20
    churn_rates <- c(churn_rates, churn)
  }
  prev_top <- this_top
}
turnover_avg <- if (length(churn_rates) > 0) mean(churn_rates, na.rm = TRUE) else NA_real_
turnover_ann <- turnover_avg * 12  # monthly → annual
cat(sprintf("  Top20 monthly churn: %.3f | Annualized turnover: %.2f\n",
            turnover_avg, turnover_ann))

# ---- 9. Aggregate validation summary ----
graduation_pass <- list(
  rank_ic = list(value = mean_ic, threshold = 0.04, pass = mean_ic >= 0.04),
  icir = list(value = icir, threshold = 0.20, pass = abs(icir) >= 0.20),
  subperiod_stability = list(value = subperiod_stability, threshold = 0.5,
                              pass = subperiod_stability >= 0.5),
  harvey_t = list(max_t = max(harvey_specs$t_stat, na.rm = TRUE),
                    n_pass_3 = n_passes_3, n_pass_25 = n_passes_25,
                    threshold = 3.0, pass = n_passes_3 >= 3L),
  dsr = list(value = dsr, threshold = 0.5, pass = dsr >= 0.5)
)
all_pass <- all(sapply(graduation_pass, function(g) isTRUE(g$pass)))

validation <- list(
  task_id = "WT-D20260528_003",
  signal_cutoff = "2023-12-22",
  n_sig_dates = uniqueN(alpha_with_ret$Date[!is.na(alpha_with_ret$fwd_simple_ret_winsor)]),
  n_alpha_obs = nrow(alpha_with_ret[!is.na(fwd_simple_ret_winsor)]),
  rank_ic_overall = mean_ic,
  rank_ic_sd = sd(ic_by_date$rank_ic),
  icir = icir,
  monotonicity_decile_spread = spread,
  monotonicity_decile_rank_corr = mono_corr,
  decile_returns = decile_avg,
  subperiod_ic = sub_ic,
  subperiod_stability = subperiod_stability,
  subperiod_stability_cv = stability_cv,
  harvey_specs = harvey_specs,
  n_harvey_pass_3_0 = n_passes_3,
  n_harvey_pass_2_5 = n_passes_25,
  bad_normal_ic_ratio = bad_norm_ratio,
  bad_ic_mean = bad_ic,
  normal_ic_mean = nor_ic,
  bad_states = bad_states,
  dsr = dsr,
  sr_annual = sr_annual,
  turnover_top20_monthly = turnover_avg,
  turnover_top20_annual = turnover_ann,
  graduation_criteria = graduation_pass,
  all_graduation_pass = all_pass,
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  elapsed_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
)

writeLines(toJSON(validation, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(STAGE_DIR, "alpha_validation.json"))
writeLines(toJSON(validation, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(OUT_DIR, "alpha_validation.json"))

cat("\n========================================\n")
cat("[Validation Summary]\n")
cat("  Rank IC:               ", round(mean_ic, 4), " (target ≥ 0.04)", ifelse(mean_ic >= 0.04, "PASS", "FAIL"), "\n")
cat("  ICIR:                  ", round(icir, 4),    " (target ≥ 0.20)", ifelse(abs(icir) >= 0.20, "PASS", "FAIL"), "\n")
cat("  Subperiod stability:   ", round(subperiod_stability, 3), " (target ≥ 0.5)", ifelse(subperiod_stability >= 0.5, "PASS", "FAIL"), "\n")
cat("  Harvey-t > 3.0:        ", n_passes_3, "/ 5 (target ≥ 3)", ifelse(n_passes_3 >= 3L, "PASS", "FAIL"), "\n")
cat("  DSR:                   ", round(dsr, 3), " (target ≥ 0.5)", ifelse(dsr >= 0.5, "PASS", "FAIL"), "\n")
cat("  Bad/Normal IC ratio:   ", round(bad_norm_ratio, 3), " (>0.5 = crisis_alpha)\n")
cat("  Annual turnover top20: ", round(turnover_ann, 2), " (target ≤ 6.0)\n")
cat("  ALL GRADUATION PASS:   ", all_pass, "\n")
cat("========================================\n")

cat("[Step 6] === DONE === elapsed:",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2), "min\n")
