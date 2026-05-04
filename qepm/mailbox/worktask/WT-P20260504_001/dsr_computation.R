## DSR — Deflated Sharpe Ratio (Bailey-Lopez de Prado 2014)
## "The Deflated Sharpe Ratio: Correcting for Selection Bias, Backtest
##  Overfitting, and Non-Normality" Journal of Portfolio Management 40(5).
##
## Formula:
##   DSR = (SR_hat - SR_star) * sqrt(T-1)
##         / sqrt(1 - skew * SR_hat + ((kurt-1)/4) * SR_hat^2)
##
##   SR_star = (1 - gamma) * Z_inv(1 - 1/N)
##           + gamma * Z_inv(1 - 1/(N*e))
##     gamma = 0.5772 (Euler-Mascheroni)
##     N = number of trials (7 across our 7-WT cycle)

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

base_dir <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
wt_dir <- file.path(base_dir, "qepm/mailbox/worktask/WT-P20260504_001")

# ------------------------------------------------------------
# 1. Load S1 threshold AR overlay returns
# ------------------------------------------------------------
str_returns_path <- file.path(base_dir,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv")
str_dt <- fread(str_returns_path)
str_dt[, date := as.Date(date)]
setorder(str_dt, date)

beta_path <- file.path(base_dir,
  "stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv")
beta_dt <- fread(beta_path)
beta_dt[, Date := as.Date(Date)]
setorder(beta_dt, Date)
beta_dt[, beta_threshold_lag := shift(beta_threshold, 1, fill = 1.0)]

str_dt[, ym := format(date, "%Y-%m")]
beta_dt[, ym := format(Date, "%Y-%m")]
mrg <- beta_dt[str_dt, on = "ym"]
mrg <- mrg[!is.na(beta_threshold_lag)]
mrg[, db_thr := abs(beta_threshold_lag - shift(beta_threshold_lag, 1, fill = 1.0))]
mrg[, ret_S1 := beta_threshold_lag * ret_net - db_thr * 0.0015]

ret_S1 <- mrg$ret_S1
T_obs <- length(ret_S1)
cat("[DSR] T (n monthly obs):", T_obs, "\n")

# ------------------------------------------------------------
# 2. Compute moments
# ------------------------------------------------------------
mu <- mean(ret_S1)
sigma <- sd(ret_S1)
SR_hat_monthly <- mu / sigma
SR_hat_annual <- SR_hat_monthly * sqrt(12)

# Skewness and kurtosis (Pearson moment, excess kurtosis = kurt - 3)
n <- length(ret_S1)
m2 <- mean((ret_S1 - mu)^2)
m3 <- mean((ret_S1 - mu)^3)
m4 <- mean((ret_S1 - mu)^4)
skew <- m3 / m2^1.5
kurt <- m4 / m2^2  # raw kurtosis (= 3 for normal)

cat(sprintf("\nMoments:\n  mu_m=%.6f\n  sigma_m=%.6f\n",
            mu, sigma))
cat(sprintf("  SR_hat_monthly=%.4f\n  SR_hat_annual=%.4f\n",
            SR_hat_monthly, SR_hat_annual))
cat(sprintf("  skew=%.4f\n  kurt(raw)=%.4f (excess=%.4f)\n",
            skew, kurt, kurt - 3))

# ------------------------------------------------------------
# 3. Compute SR* (expected max SR under null with N trials)
# ------------------------------------------------------------
# Bailey-Lopez de Prado 2014 Eq.(2)
N_trials <- 7L  # 7 statistical risk overlay trials in cycle
gamma_em <- 0.5772156649  # Euler-Mascheroni
e_val <- exp(1)

# SR_star_z is in z-score (standard-normal) units of the max-of-N order statistic
SR_star_z <- (1 - gamma_em) * qnorm(1 - 1 / N_trials) +
  gamma_em * qnorm(1 - 1 / (N_trials * e_val))
# Convert to per-period SR threshold units (Bailey-Lopez de Prado convention)
SR_threshold_per_period <- SR_star_z / sqrt(T_obs - 1)
cat(sprintf("\nN_trials (cycle)=%d\n", N_trials))
cat(sprintf("SR_star_z (max of %d normal order stat)=%.4f\n",
            N_trials, SR_star_z))
cat(sprintf("SR_threshold (per-period units)=%.4f\n",
            SR_threshold_per_period))

# ------------------------------------------------------------
# 4. DSR computation
# ------------------------------------------------------------
denom <- sqrt(1 - skew * SR_hat_monthly + ((kurt - 1) / 4) * SR_hat_monthly^2)
numer <- (SR_hat_monthly - SR_threshold_per_period) * sqrt(T_obs - 1)
DSR <- numer / denom
p_value <- 1 - pnorm(DSR)

cat(sprintf("\n=== DSR RESULTS ===\n"))
cat(sprintf("DSR = (%.4f - %.4f) * sqrt(%d) / sqrt(%.4f)\n",
            SR_hat_monthly, SR_threshold_per_period,
            T_obs - 1, denom^2))
cat(sprintf("    = %.4f / %.4f = %.4f\n",
            numer, denom, DSR))
cat(sprintf("p-value = 1 - Phi(DSR) = %.6f\n", p_value))

verdict <- if (DSR > 0 && p_value < 0.05) "PASS" else
           if (DSR > 0) "PASS_LOW_POWER" else "FAIL"
cat(sprintf("Verdict: %s\n", verdict))

# ------------------------------------------------------------
# 5. Robustness — sensitivity to N_trials
# ------------------------------------------------------------
sens <- data.table(
  N_trials = c(1L, 3L, 5L, 7L, 10L, 20L, 50L, 100L)
)
sens[, SR_star_z := (1 - gamma_em) * qnorm(1 - 1 / N_trials) +
                    gamma_em * qnorm(1 - 1 / (N_trials * e_val))]
sens[, SR_threshold := SR_star_z / sqrt(T_obs - 1)]
sens[, DSR := (SR_hat_monthly - SR_threshold) * sqrt(T_obs - 1) / denom]
sens[, p_value := 1 - pnorm(DSR)]
sens[, verdict := fifelse(DSR > 0 & p_value < 0.05, "PASS",
                           fifelse(DSR > 0, "PASS_LOW_POWER", "FAIL"))]

cat("\n=== Sensitivity to N_trials ===\n")
print(sens)

# ------------------------------------------------------------
# 6. Save JSON
# ------------------------------------------------------------
output <- list(
  task_id = "WT-P20260504_001",
  prereq = "P3_dsr_bailey_lopez_de_prado",
  variant_under_test = "S1_threshold_step",
  T_observations = T_obs,
  SR_hat_monthly = SR_hat_monthly,
  SR_hat_annual = SR_hat_annual,
  skewness = skew,
  kurtosis_raw = kurt,
  kurtosis_excess = kurt - 3,
  N_trials_in_cycle = N_trials,
  SR_star_z = SR_star_z,
  SR_threshold_per_period = SR_threshold_per_period,
  DSR = DSR,
  p_value = p_value,
  verdict = verdict,
  hurdle = "DSR > 0 + p_value < 0.05 (Bailey-Lopez de Prado 2014)",
  pass_strict = (DSR > 0 && p_value < 0.05),
  sensitivity_to_N = lapply(seq_len(nrow(sens)), function(i) {
    list(
      N_trials = sens$N_trials[i],
      SR_star_z = sens$SR_star_z[i],
      SR_threshold = sens$SR_threshold[i],
      DSR = sens$DSR[i],
      p_value = sens$p_value[i],
      verdict = sens$verdict[i]
    )
  }),
  caveats = list(
    "N=7 reflects total statistical risk overlay trials (WT-001 PCA / 002 DCC / 003 HMM / 004 RMT / 005 Factor Beta / 006 IPCA / 007 AR)",
    "Higher N (20, 50) more conservative — reflects ongoing QEPM research breadth",
    "DSR uses monthly SR (not annualized) per Bailey-Lopez de Prado convention",
    "Excess kurtosis quantifies non-normality penalty"
  ),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
)

write_json(output, file.path(wt_dir, "dsr_computation.json"),
           pretty = TRUE, auto_unbox = TRUE)
fwrite(sens, file.path(wt_dir, "dsr_sensitivity_n_trials.csv"))
cat("\n[saved] dsr_computation.json + dsr_sensitivity_n_trials.csv\n")
