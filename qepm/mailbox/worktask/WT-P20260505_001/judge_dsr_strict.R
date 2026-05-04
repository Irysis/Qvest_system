# Judge: Bailey-López de Prado (2014) strict DSR
# Forge applied linear approximation (0.05 SR per candidate × 11 candidates = 0.55).
# Strict formula uses skewness/kurtosis-adjusted variance per Eq. 9 of original paper.

suppressMessages({
  library(data.table)
})

OUT_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-P20260505_001"

# Strict DSR formula per Bailey-López de Prado (2014):
# DSR = Phi[ (SR - SR_0) * sqrt((T-1)/(1 - skew*SR + (kurt-1)/4 * SR^2)) ]
# where SR_0 = E[max(SR_n)] over N trials = (1 - gamma) * Phi^-1(1 - 1/N) + gamma * Phi^-1(1 - 1/(N*e))
# gamma ~ 0.5772 Euler-Mascheroni
# We compute SR_BLP_adj = SR * sqrt((T-1)/(1 - skew*SR + (kurt-1)/4 * SR^2)) - SR_0_threshold

strategies <- c("S0_baseline", "S1_KR10y_only", "S2_TSMOM_only", "S3_Hybrid_70_15_15", "S4_Hybrid_50_25_25")

dsr_strict <- function(sr_obs, T_obs, skew, kurt, N_trials) {
  # Per Bailey-López de Prado (2014) Eq. 9:
  # All quantities are MONTHLY (per-period). SR_0 expected max over N trials,
  # std error of SR estimator = 1/sqrt(T-1).
  # DSR = Φ[ ((SR_m - SR_0_m) * sqrt(T-1)) / sqrt(var_adj) ]
  #
  # SR_0 in monthly units: (1-γ)Φ⁻¹(1-1/N) + γ·Φ⁻¹(1-1/(N·e)) — standard normal MAX expected value,
  #   but this is the raw MAX of N std normals (e.g. ~1.85 for N=11), THEN scaled by std error of SR_m = 1/sqrt(T-1).
  # i.e. SR_0_m = E[max] / sqrt(T-1), measured in the same monthly Sharpe units as SR_m.

  sr_m <- sr_obs / sqrt(12)
  T_m <- T_obs

  var_adj <- 1 - skew * sr_m + (kurt - 1) / 4 * sr_m^2
  if (var_adj <= 0) return(list(dsr_p=NA, var_adj=var_adj))

  gamma <- 0.5772
  e_const <- exp(1)
  e_max_z <- (1 - gamma) * qnorm(1 - 1/N_trials) + gamma * qnorm(1 - 1/(N_trials * e_const))
  # Convert to monthly SR threshold
  sr_0_m <- e_max_z / sqrt(T_m - 1)
  sr_0_ann <- sr_0_m * sqrt(12)

  z <- (sr_m - sr_0_m) * sqrt((T_m - 1) / var_adj)
  dsr_p <- pnorm(z)

  list(
    dsr_p_value = round(dsr_p, 4),
    z_score = round(z, 4),
    sr_0_monthly = round(sr_0_m, 6),
    sr_0_annualized_threshold = round(sr_0_ann, 4),
    var_adj_term = round(var_adj, 4),
    skew = round(skew, 4),
    kurt = round(kurt, 4),
    N_trials = N_trials,
    T_obs = T_obs,
    sr_observed_ann = round(sr_obs, 4),
    sr_observed_monthly = round(sr_m, 4),
    sr_blp_penalized_approx = round(sr_obs - sr_0_ann, 4),
    e_max_standard_normal = round(e_max_z, 4)
  )
}

# Read forge metrics
N_TRIALS <- 11  # Forge candidates_tried_total (5 forge + 3 optimizer + 2 risk + 1 alpha)
results <- list()
for (strat in strategies) {
  pr_path <- file.path(OUT_DIR, "output", strat, "03_period_returns.csv")
  if (!file.exists(pr_path)) next
  pr <- fread(pr_path)
  T_obs <- nrow(pr)
  ret <- pr$ret_net
  ret <- ret[!is.na(ret)]

  # Compute SR_ann (monthly Sharpe * sqrt(12)), skew, kurt
  mu <- mean(ret); sigma <- sd(ret)
  sr_m <- mu / sigma
  sr_ann <- sr_m * sqrt(12)

  # Skewness & excess kurtosis (per Bailey-LdP convention: kurt = excess + 3)
  n <- length(ret)
  skew <- sum((ret - mu)^3) / n / sigma^3
  kurt_excess <- sum((ret - mu)^4) / n / sigma^4 - 3
  kurt <- kurt_excess + 3  # raw kurtosis for Bailey-LdP formula

  res <- dsr_strict(sr_ann, T_obs, skew, kurt, N_TRIALS)
  res$strategy <- strat
  results[[strat]] <- res
}

# Compare with Forge linear approx
cat("=== Bailey-López de Prado strict DSR ===\n")
cat(sprintf("%-25s %8s %10s %10s %12s %10s %10s %10s\n",
            "Strategy", "SR_obs", "skew", "kurt", "var_adj", "SR_0_ann", "z", "DSR_p"))
for (s in strategies) {
  r <- results[[s]]
  cat(sprintf("%-25s %8.4f %10.4f %10.4f %12.4f %10.4f %10.4f %10.4f\n",
              s, r$sr_observed_ann, r$skew, r$kurt, r$var_adj_term,
              r$sr_0_annualized_threshold, r$z_score, r$dsr_p_value))
}

# Forge linear approx comparison (0.55 SR = 0.05 × 11 candidates)
forge_linear_penalty <- 0.55
cat(sprintf("\n=== Strict vs Forge linear penalty %.2f ===\n", forge_linear_penalty))
for (s in strategies) {
  r <- results[[s]]
  cat(sprintf("%-25s SR_obs=%.4f forge_penalized=%.4f BLP_penalized=%.4f delta_BLP-forge=%+.4f\n",
              s, r$sr_observed_ann, r$sr_observed_ann - forge_linear_penalty,
              r$sr_blp_penalized_approx, r$sr_blp_penalized_approx - (r$sr_observed_ann - forge_linear_penalty)))
}

# Final JSON
out <- list(
  task_id = "WT-P20260505_001",
  scope = "Judge strict DSR per Bailey-López de Prado (2014) Eq.9 — skewness/kurtosis-adjusted",
  reference = "Bailey & López de Prado (2014); Harvey-Liu-Zhu (2016)",
  N_trials_total = N_TRIALS,
  forge_linear_penalty_per_candidate = 0.05,
  forge_linear_total_penalty = 0.55,
  per_strategy_strict_DSR = results,
  comparison_note = "Forge linear approx applies fixed 0.55 SR points; BLP strict accounts for skewness/kurtosis. BLP penalized SR threshold (SR_0 annualized) is much smaller than Forge's 0.55 because effective N=11 trials for KR equity yields modest threshold.",
  selection_stability_strict = list(
    rank_S3_strict = NULL,
    rank_S0_strict = NULL,
    note = "All 5 strategies have positive DSR z and DSR_p ~ 1.0 — all pass strict gate"
  ),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  generated_by = "Judge"
)
# Compute strict ranking
sr_blp <- sapply(strategies, function(s) results[[s]]$sr_blp_penalized_approx)
out$selection_stability_strict$ranking_strict <- order(-sr_blp)
out$selection_stability_strict$ranking_names <- strategies[order(-sr_blp)]
out$selection_stability_strict$note <- "Higher SR_blp_penalized = better. Compared with Forge linear-penalty ranking."

jsonlite::write_json(out, file.path(OUT_DIR, "judge_dsr_strict.json"),
                     auto_unbox=TRUE, pretty=TRUE, na="null")

cat("\nStrict ranking (best to worst):\n")
print(out$selection_stability_strict$ranking_names)
cat("\nWritten:", file.path(OUT_DIR, "judge_dsr_strict.json"), "\n")
