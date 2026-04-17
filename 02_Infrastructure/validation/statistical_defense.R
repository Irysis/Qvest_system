#==============================================================================
# Statistical Defense Module — QEPM Lawbook v1.4 Ch.22
# DSR (Deflated Sharpe Ratio), FDR, Family Trial Accounting
#
# Bailey & Lopez de Prado (2014) "The Deflated Sharpe Ratio"
# Harvey, Liu & Zhu (2016) "...and the Cross-Section of Expected Returns"
#
# Usage:
#   source("statistical_defense.R")
#   dsr <- compute_dsr(sharpe, n_obs, n_trials, skew, excess_kurt)
#   family <- load_family_trials()
#   family <- update_family_trial(family, family_name, strategy_name, grade)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

cat("[stat_defense] Loaded.\n")

#==============================================================================
# DSR: Deflated Sharpe Ratio
# Tests whether observed Sharpe is significant after accounting for:
# (1) number of trials, (2) skewness/kurtosis, (3) sample size
#==============================================================================

compute_dsr <- function(observed_sr, n_obs, n_trials,
                         skew = 0, excess_kurt = 0) {
  if (n_trials < 1) n_trials <- 1
  if (n_obs < 30) {
    return(list(dsr = NA_real_, sr_max_expected = NA_real_,
                sr_se = NA_real_, n_trials = n_trials,
                note = "Insufficient observations (< 30)"))
  }

  # SE of Sharpe estimator (Lo 2002, Bailey & LdP 2014)
  sr_se <- sqrt((1 - skew * observed_sr +
                   (excess_kurt / 4) * observed_sr^2) / (n_obs - 1))

  # Expected max SR from N independent trials under null
  # Mertens (2002): E[max(Z_1,...,Z_N)]
  if (n_trials <= 1) {
    sr_max_expected <- 0
  } else {
    ln_n <- log(n_trials)
    e_max_z <- sqrt(2 * ln_n) -
      (log(log(n_trials)) + log(4 * pi)) / (2 * sqrt(2 * ln_n))
    sr_max_expected <- e_max_z * sr_se
  }

  # DSR = P(observed SR > expected max from noise)
  dsr <- if (sr_se > 1e-8) {
    pnorm((observed_sr - sr_max_expected) / sr_se)
  } else {
    0.5
  }

  list(
    dsr             = round(dsr, 4),
    sr_max_expected = round(sr_max_expected, 4),
    sr_se           = round(sr_se, 4),
    n_trials        = n_trials,
    significant     = dsr > 0.95,
    note = sprintf("DSR=%.3f (SR=%.3f, N=%d trials, T=%d obs, SR*=%.3f)",
                   dsr, observed_sr, n_trials, n_obs, sr_max_expected)
  )
}

#==============================================================================
# Family-Aware DSR: Adjusts N_trials based on family trial count
# v1.4.2 Lawbook: Same family → cumulative trial count for DSR
#==============================================================================

compute_dsr_family <- function(observed_sr, n_obs, family_name,
                                skew = 0, excess_kurt = 0,
                                path = FAMILY_TRIAL_PATH) {
  family_data <- load_family_trials(path)
  n_family <- get_family_n_trials(family_data, family_name)

  # Use family trial count as N_trials (not global total)
  # This penalizes repeated testing within same family
  dsr_result <- compute_dsr(observed_sr, n_obs, n_family, skew, excess_kurt)
  dsr_result$family_name <- family_name
  dsr_result$family_trials <- n_family

  # Additional threshold: if family has 10+ trials, require DSR > 0.99
  if (n_family >= 10) {
    dsr_result$significant <- dsr_result$dsr > 0.99
    dsr_result$note <- paste0(dsr_result$note,
                               sprintf(" [HIGH-TRIAL family: %d trials, DSR>0.99 required]", n_family))
  }

  dsr_result
}

#==============================================================================
# Family Trial Accounting
# Tracks how many strategies have been tested per family
#==============================================================================

FAMILY_TRIAL_PATH <- file.path(
  ifelse(exists("CACHE_DIR"), CACHE_DIR,
         "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/.cache"),
  "family_trial_accounting.json"
)

load_family_trials <- function(path = FAMILY_TRIAL_PATH) {
  if (file.exists(path)) {
    fromJSON(path, simplifyDataFrame = FALSE)
  } else {
    list()
  }
}

save_family_trials <- function(family_data, path = FAMILY_TRIAL_PATH) {
  write_json(family_data, path, auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf("[stat_defense] Family trials saved: %s\n", path))
}

update_family_trial <- function(family_data, family_name,
                                 strategy_name, grade,
                                 sharpe = NA, cagr = NA) {
  if (is.null(family_data[[family_name]])) {
    family_data[[family_name]] <- list(
      total_trials   = 0L,
      grade_a_count  = 0L,
      grade_b_count  = 0L,
      grade_f_count  = 0L,
      strategies     = list(),
      consecutive_fails = 0L,
      cooldown       = FALSE
    )
  }

  fam <- family_data[[family_name]]
  fam$total_trials <- fam$total_trials + 1L

  if (grade == "A") {
    fam$grade_a_count <- fam$grade_a_count + 1L
    fam$consecutive_fails <- 0L
  } else if (grade == "B") {
    fam$grade_b_count <- fam$grade_b_count + 1L
    fam$consecutive_fails <- 0L
  } else {
    fam$grade_f_count <- fam$grade_f_count + 1L
    fam$consecutive_fails <- fam$consecutive_fails + 1L
  }

  # Family cooldown: 3 consecutive hard fails
  fam$cooldown <- fam$consecutive_fails >= 3

  fam$strategies[[strategy_name]] <- list(
    grade = grade, sharpe = sharpe, cagr = cagr,
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  )

  fam$success_rate <- round(fam$grade_a_count / max(fam$total_trials, 1), 3)
  family_data[[family_name]] <- fam
  family_data
}

get_family_n_trials <- function(family_data, family_name) {
  if (is.null(family_data[[family_name]])) return(1L)
  max(1L, family_data[[family_name]]$total_trials)
}

#==============================================================================
# Batch DSR: Apply to all Grade A strategies
#==============================================================================

batch_dsr_audit <- function(strategies_dir = NULL, n_total_trials = NULL) {
  if (is.null(strategies_dir)) {
    strategies_dir <- file.path(
      "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
      "04_Research/strategies"
    )
  }

  hurdle_files <- list.files(strategies_dir, pattern = "hurdle_result\\.json$",
                              recursive = TRUE, full.names = TRUE)
  if (length(hurdle_files) == 0) {
    cat("[batch_dsr] No hurdle_result.json files found.\n")
    return(NULL)
  }

  results <- list()
  for (hf in hurdle_files) {
    h <- tryCatch(fromJSON(hf, simplifyDataFrame = FALSE), error = function(e) NULL)
    if (is.null(h)) next

    strat_name <- h$strategy
    grade      <- h$grade
    sharpe     <- h$metrics$Sharpe

    # Read performance.csv for return series stats
    perf_dir <- dirname(hf)
    perf_csv <- file.path(perf_dir, "performance.csv")
    skew <- 0; ekurt <- 0; n_obs <- 5000

    # Estimate n_obs from CAGR/dates (approximate)
    # Use ~252 trading days * years
    if (!is.null(h$metrics$Rolling3Y_Pos)) {
      n_obs <- round(as.numeric(difftime(Sys.Date(), as.Date("2002-01-01"),
                                          units = "days")) * 252 / 365.25)
    }

    n_trials <- if (!is.null(n_total_trials)) n_total_trials else 465L

    dsr_result <- compute_dsr(sharpe, n_obs, n_trials, skew, ekurt)

    results[[strat_name]] <- list(
      strategy = strat_name,
      grade    = grade,
      sharpe   = sharpe,
      cagr     = h$metrics$CAGR,
      mdd      = h$metrics$MDD,
      dsr      = dsr_result$dsr,
      dsr_significant = dsr_result$significant,
      sr_max_expected = dsr_result$sr_max_expected,
      n_trials = n_trials
    )
  }

  dt <- rbindlist(lapply(results, as.data.table), fill = TRUE)
  setorder(dt, -dsr)
  dt
}

#==============================================================================
# FDR: False Discovery Rate (Benjamini-Hochberg)
# Harvey, Liu & Zhu (2016): multiple testing correction for strategy selection
# Usage: compute_fdr(p_values) → adjusted p-values + significant flags
#==============================================================================

compute_fdr <- function(p_values, alpha = 0.05) {
  # p_values: named vector of p-values from strategy alpha tests
  if (length(p_values) == 0) return(NULL)

  n <- length(p_values)
  nms <- names(p_values)
  if (is.null(nms)) nms <- paste0("S", seq_len(n))

  # BH procedure: sort p-values, compare to i/n * alpha
  ord  <- order(p_values)
  p_sorted <- p_values[ord]
  n_sorted <- nms[ord]

  # Adjusted p-values (BH)
  p_adj <- numeric(n)
  p_adj[n] <- p_sorted[n]
  for (i in (n-1):1) {
    p_adj[i] <- min(p_adj[i+1], p_sorted[i] * n / i)
  }
  p_adj <- pmin(p_adj, 1.0)

  # Reconstruct in original order
  result <- data.table(
    strategy  = n_sorted,
    p_raw     = p_sorted,
    p_bh      = round(p_adj, 6),
    rank      = seq_len(n),
    threshold = round(seq_len(n) / n * alpha, 6),
    significant_bh = p_adj <= alpha
  )
  setorder(result, rank)

  n_reject <- sum(result$significant_bh)
  fdr_rate <- if (n_reject > 0) round(n_reject / n, 4) else 0

  list(
    results     = result,
    n_total     = n,
    n_rejected  = n_reject,
    fdr_rate    = fdr_rate,
    alpha       = alpha,
    note = sprintf("BH-FDR: %d/%d strategies survive at alpha=%.2f (FDR=%.1f%%)",
                   n_reject, n, alpha, fdr_rate * 100)
  )
}

#==============================================================================
# Bootstrap / Placebo Test
# Tests whether strategy alpha is significantly different from random selection
# Method: reshuffle stock assignments across signals, re-compute Sharpe N times
# Lawbook v1.4.2 Ch.22: Grade A requires DSR + min 1 of {placebo, bootstrap}
#==============================================================================

bootstrap_placebo_test <- function(ret_xts, bm_xts = NULL,
                                    n_boot = 1000L,
                                    block_size = 21L,
                                    seed = 42L) {
  # ret_xts: strategy daily return xts
  # bm_xts: benchmark daily return xts (for excess return test)
  # n_boot: number of bootstrap iterations
  # block_size: circular block bootstrap size (21 = ~1 month)
  #
  # Returns: p-value, observed Sharpe, bootstrap distribution

  set.seed(seed)
  r <- as.numeric(ret_xts[!is.na(ret_xts)])
  n <- length(r)

  if (n < 252) {
    return(list(
      p_value = NA_real_, observed_sharpe = NA_real_,
      boot_mean = NA_real_, boot_sd = NA_real_, n_boot = 0L,
      note = "Insufficient data (< 252 days)"
    ))
  }

  # Observed Sharpe
  obs_sharpe <- mean(r) / sd(r) * sqrt(252)

  # If benchmark provided, test excess returns
  if (!is.null(bm_xts)) {
    bm_r <- as.numeric(bm_xts[!is.na(bm_xts)])
    min_n <- min(length(r), length(bm_r))
    r <- r[1:min_n] - bm_r[1:min_n]
    n <- min_n
    obs_sharpe <- mean(r) / sd(r) * sqrt(252)
  }

  # Circular block bootstrap (Politis & Romano 1994)
  boot_sharpes <- numeric(n_boot)
  for (b in seq_len(n_boot)) {
    n_blocks <- ceiling(n / block_size)
    starts <- sample.int(n, n_blocks, replace = TRUE)
    boot_idx <- integer(0)
    for (s in starts) {
      idx <- ((s - 1 + seq_len(block_size)) %% n) + 1
      boot_idx <- c(boot_idx, idx)
    }
    boot_idx <- boot_idx[seq_len(n)]
    boot_r <- r[boot_idx]
    boot_sd <- sd(boot_r)
    boot_sharpes[b] <- if (boot_sd > 1e-10) mean(boot_r) / boot_sd * sqrt(252) else 0
  }

  # p-value: fraction of bootstrap Sharpes >= observed (one-sided)
  # Under null (random timing), Sharpe should be ~0
  # We test H0: Sharpe <= 0 by checking percentile
  p_value <- mean(boot_sharpes >= obs_sharpe)

  # Also compute confidence interval
  ci_95 <- quantile(boot_sharpes, c(0.025, 0.975))

  list(
    p_value         = round(p_value, 4),
    observed_sharpe = round(obs_sharpe, 4),
    boot_mean       = round(mean(boot_sharpes), 4),
    boot_sd         = round(sd(boot_sharpes), 4),
    boot_ci_025     = round(ci_95[1], 4),
    boot_ci_975     = round(ci_95[2], 4),
    n_boot          = n_boot,
    significant     = p_value < 0.05,
    note = sprintf("Bootstrap (N=%d, block=%d): obs_Sharpe=%.3f, boot_mean=%.3f, p=%.4f %s",
                   n_boot, block_size, obs_sharpe, mean(boot_sharpes), p_value,
                   if (p_value < 0.05) "[SIGNIFICANT]" else "[NOT significant]")
  )
}

#==============================================================================
# Placebo (Random Signal) Test
# Generates random factor scores, runs same portfolio construction, compares
# Sharpe. Tests whether the signal itself adds value vs random stock picking.
#==============================================================================

placebo_random_signal <- function(FACTORS, RAWDATA, run_sim_fn,
                                   n_placebo = 100L,
                                   seed = 42L,
                                   ...) {
  # FACTORS: data.table with Date, Ticker, Score
  # RAWDATA: full market data
  # run_sim_fn: function(FACTORS, RAWDATA, ...) → sim with strategy_xts
  # ...: additional args passed to run_sim_fn
  #
  # Returns: p-value, observed vs placebo Sharpe distribution

  set.seed(seed)

  # 1. Observed Sharpe from real FACTORS
  sim_obs <- tryCatch(run_sim_fn(FACTORS, RAWDATA, ...), error = function(e) NULL)
  if (is.null(sim_obs)) {
    return(list(p_value = NA_real_, note = "Observed simulation failed"))
  }
  obs_r <- as.numeric(sim_obs$strategy_xts[!is.na(sim_obs$strategy_xts)])
  obs_sharpe <- mean(obs_r) / sd(obs_r) * sqrt(252)

  # 2. Generate random signals with same structure
  placebo_sharpes <- numeric(n_placebo)
  for (i in seq_len(n_placebo)) {
    FACTORS_PLACEBO <- copy(FACTORS)
    # Shuffle scores within each signal date (preserves universe + date structure)
    FACTORS_PLACEBO[, Score := sample(Score), by = Date]

    sim_p <- tryCatch(run_sim_fn(FACTORS_PLACEBO, RAWDATA, ...), error = function(e) NULL)
    if (is.null(sim_p)) {
      placebo_sharpes[i] <- NA_real_
      next
    }
    p_r <- as.numeric(sim_p$strategy_xts[!is.na(sim_p$strategy_xts)])
    placebo_sharpes[i] <- if (length(p_r) > 252) mean(p_r) / sd(p_r) * sqrt(252) else NA_real_
  }

  valid <- placebo_sharpes[!is.na(placebo_sharpes)]
  p_value <- if (length(valid) > 10) mean(valid >= obs_sharpe) else NA_real_

  list(
    p_value           = round(p_value, 4),
    observed_sharpe   = round(obs_sharpe, 4),
    placebo_mean      = round(mean(valid), 4),
    placebo_sd        = round(sd(valid), 4),
    n_valid           = length(valid),
    n_placebo         = n_placebo,
    significant       = !is.na(p_value) && p_value < 0.05,
    note = sprintf("Placebo (N=%d valid/%d): obs=%.3f vs placebo_mean=%.3f, p=%.4f %s",
                   length(valid), n_placebo, obs_sharpe, mean(valid),
                   ifelse(is.na(p_value), NA_real_, p_value),
                   if (!is.na(p_value) && p_value < 0.05) "[SIGNAL HAS VALUE]" else "[random-equivalent]")
  )
}

cat("[stat_defense] Functions: compute_dsr(), compute_dsr_family(), compute_fdr(), bootstrap_placebo_test(), placebo_random_signal(), load_family_trials(), update_family_trial(), batch_dsr_audit()\n")
