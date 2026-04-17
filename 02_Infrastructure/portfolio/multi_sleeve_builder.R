#==============================================================================
# Quant Module — Multi-Sleeve Portfolio Builder
# Version: 1.0.0
#
# Combines multiple single-strategy backtests into a multi-sleeve portfolio.
# Analyzes inter-strategy correlations, identifies diversifying subsets,
# and applies portfolio-level combination methods.
#
# Main entry points:
#   load_sleeve_returns(strategy_dirs)       — simulate & cache daily returns
#   analyze_sleeve_correlations(strategy_dirs) — correlation matrix + clustering
#   build_multi_sleeve(strategy_dirs, method)  — combined portfolio backtest
#   summarise_multi_sleeve(result)             — performance summary table
#
# Dependencies: config.R, backtest_harness.R (must be sourced first)
#               data.table, xts, arrow, PerformanceAnalytics, stats
#
# Usage:
#   source("config.R")
#   source("backtest_harness.R")
#   source("multi_sleeve_builder.R")
#
#   top_dirs <- c("STR_401_ra_days_inv", "STR_316_ccc_gate",
#                 "STR_303_ivol40_assetgrowth_gate")
#   corr <- analyze_sleeve_correlations(top_dirs)
#   combined <- build_multi_sleeve(top_dirs, method = "risk_parity")
#   perf <- summarise_multi_sleeve(combined)
#==============================================================================

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
}

# Ensure backtest_harness is loaded (provides load_rawdata, run_monthly_simulation, etc.)
if (!exists("load_rawdata")) {
  source(file.path(FUNC_PATH, "backtest_harness.R"))
}

suppressPackageStartupMessages({
  library(data.table)
  library(xts)
  library(arrow)
  library(PerformanceAnalytics)
  library(stats)
})

cat("[multi_sleeve_builder] Loaded.\n")


#==============================================================================
# CONSTANTS
#==============================================================================

SLEEVE_CACHE_DIR <- file.path(CACHE_DIR, "sleeve_returns")
if (!dir.exists(SLEEVE_CACHE_DIR)) {
  dir.create(SLEEVE_CACHE_DIR, recursive = TRUE, showWarnings = FALSE)
}

# Default simulation parameters (matching PASS framework)
.SLEEVE_SIM_DEFAULTS <- list(
  n_holdings    = 30L,
  weight_method = "equal",
  commission    = 0.0015,
  buffer_zone   = list(keep_n = 50L, entry_n = 25L)
)


#==============================================================================
# 1. simulate_single_sleeve() — Run one strategy and return daily returns
#==============================================================================
#
# Loads factor_engine.R from a strategy directory, simulates, returns xts.
# Caches the daily return series to .cache/sleeve_returns/<dir_name>.parquet.
#
# Args:
#   strategy_dir  — directory name (e.g., "STR_401_ra_days_inv") or full path
#   RAWDATA       — data.table from load_rawdata()
#   BM_DT         — benchmark data.table
#   force_resim   — if TRUE, re-simulate even if cache exists
#   sim_params    — list override for simulation params (n_holdings, etc.)
#
# Returns: xts of daily returns, or NULL on failure
#==============================================================================

simulate_single_sleeve <- function(strategy_dir,
                                    RAWDATA,
                                    BM_DT,
                                    force_resim = FALSE,
                                    sim_params  = NULL) {

  # Resolve full path
  if (!dir.exists(strategy_dir)) {
    full_path <- file.path(STRATEGY_OUTPUT, strategy_dir)
    if (!dir.exists(full_path)) {
      cat(sprintf("[sleeve] ERROR: Directory not found: %s\n", strategy_dir))
      return(NULL)
    }
    strategy_dir <- full_path
  }

  dir_name <- basename(strategy_dir)
  cache_file <- file.path(SLEEVE_CACHE_DIR, paste0(dir_name, ".parquet"))

  # --- Check cache ---
  if (!force_resim && file.exists(cache_file)) {
    cache_age <- as.numeric(difftime(Sys.time(), file.mtime(cache_file), units = "days"))
    if (cache_age < 30) {
      cat(sprintf("[sleeve] Cache hit: %s (%.0fd old)\n", dir_name, cache_age))
      dt <- as.data.table(read_parquet(cache_file))
      dt[, Date := as.Date(Date)]
      ret_xts <- xts(dt$Ret, order.by = dt$Date)
      names(ret_xts) <- dir_name
      return(ret_xts)
    }
  }

  # --- Run factor_engine.R in isolated environment ---
  cat(sprintf("[sleeve] Simulating: %s ...\n", dir_name))

  factor_file <- file.path(strategy_dir, "factor_engine.R")
  if (!file.exists(factor_file)) {
    cat(sprintf("[sleeve] ERROR: factor_engine.R not found in %s\n", dir_name))
    return(NULL)
  }

  # Create a child environment to avoid polluting global scope
  sim_env <- new.env(parent = globalenv())

  # Copy necessary objects into child env
  sim_env$RAWDATA         <- RAWDATA
  sim_env$BM_DT           <- BM_DT
  sim_env$PROJECT_ROOT    <- PROJECT_ROOT
  sim_env$FUNC_PATH       <- FUNC_PATH
  sim_env$CACHE_DIR       <- CACHE_DIR
  sim_env$RAWDATA_CACHE   <- RAWDATA_CACHE
  sim_env$BM_CACHE        <- BM_CACHE
  sim_env$DART_FACTOR_CACHE <- DART_FACTOR_CACHE
  sim_env$FRED_MACRO_CACHE  <- FRED_MACRO_CACHE
  sim_env$FRED_REGIME_CACHE <- FRED_REGIME_CACHE
  sim_env$REGIME_ENDO_CACHE <- REGIME_ENDO_CACHE
  sim_env$REGIME_SIGNAL_CACHE <- REGIME_SIGNAL_CACHE
  sim_env$set.seed        <- set.seed

  result <- tryCatch({
    # Source factor_engine.R in isolated env
    source(factor_file, local = sim_env)

    if (!exists("FACTORS", envir = sim_env) || nrow(sim_env$FACTORS) == 0) {
      cat(sprintf("[sleeve] ERROR: FACTORS empty after sourcing %s\n", dir_name))
      return(NULL)
    }

    FACTORS <- sim_env$FACTORS

    # --- Detect sim params from run_all.R if available ---
    detected_params <- .detect_sim_params(strategy_dir)
    params <- .SLEEVE_SIM_DEFAULTS

    # Override with detected params
    if (!is.null(detected_params)) {
      for (nm in names(detected_params)) {
        params[[nm]] <- detected_params[[nm]]
      }
    }

    # Override with user-supplied params
    if (!is.null(sim_params)) {
      for (nm in names(sim_params)) {
        params[[nm]] <- sim_params[[nm]]
      }
    }

    sim <- run_monthly_simulation(
      RAWDATA       = RAWDATA,
      BM_DT         = BM_DT,
      FACTORS       = FACTORS,
      n_holdings    = params$n_holdings,
      weight_method = params$weight_method,
      commission    = params$commission,
      buffer_zone   = params$buffer_zone
    )

    sim$strategy_xts
  }, error = function(e) {
    cat(sprintf("[sleeve] ERROR in %s: %s\n", dir_name, conditionMessage(e)))
    NULL
  })

  if (is.null(result)) return(NULL)

  # --- Cache daily returns ---
  ret_dt <- data.table(
    Date = index(result),
    Ret  = as.numeric(coredata(result))
  )
  write_parquet(ret_dt, cache_file)
  cat(sprintf("[sleeve] Cached: %s (%d days, %s ~ %s)\n",
              dir_name, nrow(ret_dt),
              min(ret_dt$Date), max(ret_dt$Date)))

  names(result) <- dir_name
  result
}


#==============================================================================
# 1b. .detect_sim_params() — Parse run_all.R for simulation parameters
#==============================================================================

.detect_sim_params <- function(strategy_dir) {

  run_all_file <- file.path(strategy_dir, "run_all.R")
  if (!file.exists(run_all_file)) return(NULL)

  code <- tryCatch(readLines(run_all_file, warn = FALSE),
                   error = function(e) return(NULL))
  if (is.null(code)) return(NULL)

  params <- list()

  # Extract n_holdings
  m <- regmatches(code, regexpr("n_holdings\\s*=\\s*([0-9]+)", code))
  if (length(m) > 0) {
    val <- as.integer(sub(".*=\\s*", "", m[1]))
    if (!is.na(val)) params$n_holdings <- val
  }

  # Extract weight_method
  m <- regmatches(code, regexpr('weight_method\\s*=\\s*"([^"]+)"', code))
  if (length(m) > 0) {
    val <- sub('.*"([^"]+)".*', "\\1", m[1])
    if (nchar(val) > 0) params$weight_method <- val
  }

  # Extract commission
  m <- regmatches(code, regexpr("commission\\s*=\\s*([0-9.]+)", code))
  if (length(m) > 0) {
    val <- as.numeric(sub(".*=\\s*", "", m[1]))
    if (!is.na(val)) params$commission <- val
  }

  # Detect buffer_zone
  has_bz <- any(grepl("buffer_zone\\s*=\\s*list", code))
  if (has_bz) {
    # Extract keep_n and entry_n
    m_keep <- regmatches(code, regexpr("keep_n\\s*=\\s*([0-9]+)", code))
    m_entry <- regmatches(code, regexpr("entry_n\\s*=\\s*([0-9]+)", code))
    keep_n  <- if (length(m_keep) > 0)  as.integer(sub(".*=\\s*", "", m_keep[1]))  else 50L
    entry_n <- if (length(m_entry) > 0) as.integer(sub(".*=\\s*", "", m_entry[1])) else 25L
    params$buffer_zone <- list(keep_n = keep_n, entry_n = entry_n)
  } else {
    params$buffer_zone <- NULL
  }

  if (length(params) == 0) return(NULL)
  params
}


#==============================================================================
# 2. load_sleeve_returns() — Simulate & cache multiple strategies
#==============================================================================
#
# Args:
#   strategy_dirs — character vector of directory names
#   force_resim   — re-simulate all even if cached
#   sim_params    — optional list of param overrides applied to all
#
# Returns: named list of xts objects (one per strategy)
#==============================================================================

load_sleeve_returns <- function(strategy_dirs,
                                 force_resim = FALSE,
                                 sim_params  = NULL) {

  cat(sprintf("\n[multi_sleeve] Loading returns for %d strategies...\n",
              length(strategy_dirs)))

  # Load data once
  res <- load_rawdata()
  RAWDATA <- res$RAWDATA
  BM_DT   <- res$BM_DT

  results <- list()
  n_ok    <- 0L
  n_fail  <- 0L

  for (dir_name in strategy_dirs) {
    ret_xts <- simulate_single_sleeve(
      strategy_dir = dir_name,
      RAWDATA      = RAWDATA,
      BM_DT        = BM_DT,
      force_resim  = force_resim,
      sim_params   = sim_params
    )

    if (!is.null(ret_xts)) {
      results[[dir_name]] <- ret_xts
      n_ok <- n_ok + 1L
    } else {
      n_fail <- n_fail + 1L
    }
  }

  cat(sprintf("[multi_sleeve] Loaded: %d OK, %d failed out of %d\n",
              n_ok, n_fail, length(strategy_dirs)))

  results
}


#==============================================================================
# 3. analyze_sleeve_correlations() — Correlation analysis & clustering
#==============================================================================
#
# Args:
#   strategy_dirs  — character vector of strategy directory names
#   freq           — "daily" or "monthly" aggregation for correlation
#   force_resim    — re-simulate if needed
#
# Returns: list(
#   matrix       — pairwise correlation matrix
#   distance     — 1 - abs(corr) distance matrix
#   clusters     — hierarchical clustering result (hclust)
#   high_corr    — data.table of pairs with |corr| > 0.9
#   diversifying — character vector: most diversifying subset
#   n_strategies — number of successfully loaded strategies
# )
#==============================================================================

analyze_sleeve_correlations <- function(strategy_dirs,
                                         freq        = "daily",
                                         force_resim = FALSE) {

  sleeve_list <- load_sleeve_returns(strategy_dirs, force_resim = force_resim)

  if (length(sleeve_list) < 2) {
    cat("[correlation] Need at least 2 strategies for correlation analysis.\n")
    return(NULL)
  }

  # --- Merge all returns to common date range ---
  merged_xts <- do.call(merge, sleeve_list)
  merged_xts <- merged_xts[complete.cases(merged_xts), ]

  if (nrow(merged_xts) < 60) {
    cat("[correlation] Insufficient overlapping data (< 60 days).\n")
    return(NULL)
  }

  # --- Optionally aggregate to monthly ---
  if (freq == "monthly") {
    merged_xts <- apply.monthly(merged_xts, function(x) {
      apply(x, 2, function(col) prod(1 + col, na.rm = TRUE) - 1)
    })
    if (nrow(merged_xts) < 12) {
      cat("[correlation] Insufficient monthly data (< 12 months).\n")
      return(NULL)
    }
  }

  # --- Correlation matrix ---
  ret_mat <- coredata(merged_xts)
  corr_mat <- cor(ret_mat, use = "pairwise.complete.obs")

  # Clean names for display
  short_names <- gsub("^STR_", "", colnames(corr_mat))
  rownames(corr_mat) <- colnames(corr_mat) <- short_names

  # --- Distance & clustering ---
  dist_mat <- as.dist(sqrt(0.5 * (1 - corr_mat)))
  hc <- hclust(dist_mat, method = "ward.D2")

  # --- Identify highly correlated pairs (|r| > 0.9) ---
  high_pairs <- list()
  n <- ncol(corr_mat)
  for (i in 1:(n - 1)) {
    for (j in (i + 1):n) {
      if (abs(corr_mat[i, j]) > 0.9) {
        high_pairs[[length(high_pairs) + 1]] <- data.table(
          Sleeve_A = short_names[i],
          Sleeve_B = short_names[j],
          Corr     = round(corr_mat[i, j], 4)
        )
      }
    }
  }
  high_corr_dt <- if (length(high_pairs) > 0) rbindlist(high_pairs) else data.table()

  # --- Find most diversifying subset (greedy min-correlation) ---
  diversifying <- .greedy_diversify(corr_mat, names(sleeve_list))

  # --- Console summary ---
  cat("\n=== SLEEVE CORRELATION ANALYSIS ===\n")
  cat(sprintf("Strategies: %d | Overlapping %s obs: %d\n",
              length(sleeve_list), freq, nrow(merged_xts)))
  cat(sprintf("Avg pairwise correlation: %.3f\n", .avg_offdiag(corr_mat)))
  cat(sprintf("Min pairwise correlation: %.3f\n", .min_offdiag(corr_mat)))
  cat(sprintf("Max pairwise correlation: %.3f\n", .max_offdiag(corr_mat)))

  if (nrow(high_corr_dt) > 0) {
    cat(sprintf("\nHighly correlated pairs (|r| > 0.9): %d\n", nrow(high_corr_dt)))
    print(high_corr_dt)
  } else {
    cat("\nNo highly correlated pairs (|r| > 0.9).\n")
  }

  cat(sprintf("\nMost diversifying subset (%d sleeves): %s\n",
              length(diversifying), paste(diversifying, collapse = ", ")))
  cat("===================================\n\n")

  list(
    matrix       = corr_mat,
    distance     = dist_mat,
    clusters     = hc,
    high_corr    = high_corr_dt,
    diversifying = diversifying,
    n_strategies = length(sleeve_list),
    merged_xts   = merged_xts
  )
}


# Helper: average off-diagonal element
.avg_offdiag <- function(mat) {
  n <- nrow(mat)
  if (n < 2) return(NA_real_)
  vals <- mat[lower.tri(mat)]
  mean(vals, na.rm = TRUE)
}

.min_offdiag <- function(mat) {
  n <- nrow(mat)
  if (n < 2) return(NA_real_)
  min(mat[lower.tri(mat)], na.rm = TRUE)
}

.max_offdiag <- function(mat) {
  n <- nrow(mat)
  if (n < 2) return(NA_real_)
  max(mat[lower.tri(mat)], na.rm = TRUE)
}


#==============================================================================
# 3b. .greedy_diversify() — Greedy subset maximizing avg pairwise distance
#==============================================================================
#
# Start with the sleeve having lowest avg correlation to all others.
# Iteratively add the sleeve least correlated to the current set.
# Stop when adding any sleeve would raise avg pairwise corr above 0.85
# or all sleeves are included.
#
# Returns: character vector of selected full directory names
#==============================================================================

.greedy_diversify <- function(corr_mat, full_names,
                               max_avg_corr = 0.85,
                               min_sleeves  = 2L) {

  n <- nrow(corr_mat)
  if (n <= 2) return(full_names)

  # Average correlation of each sleeve to all others
  avg_corrs <- sapply(1:n, function(i) {
    mean(abs(corr_mat[i, -i]), na.rm = TRUE)
  })

  # Start with the most diversifying (lowest avg |corr|)
  selected <- which.min(avg_corrs)
  remaining <- setdiff(1:n, selected)

  while (length(remaining) > 0) {
    # For each candidate, compute avg |corr| with current selected set
    candidate_scores <- sapply(remaining, function(j) {
      mean(abs(corr_mat[j, selected]), na.rm = TRUE)
    })

    best_idx <- remaining[which.min(candidate_scores)]
    best_corr <- min(candidate_scores, na.rm = TRUE)

    # Check if adding this would violate threshold
    trial_set <- c(selected, best_idx)
    trial_corr_mat <- corr_mat[trial_set, trial_set, drop = FALSE]
    trial_avg <- .avg_offdiag(abs(trial_corr_mat))

    if (!is.na(trial_avg) && trial_avg > max_avg_corr &&
        length(selected) >= min_sleeves) {
      break
    }

    selected <- c(selected, best_idx)
    remaining <- setdiff(remaining, best_idx)
  }

  full_names[selected]
}


#==============================================================================
# 4. build_multi_sleeve() — Combine strategies into portfolio
#==============================================================================
#
# Methods:
#   "equal"          — 1/N equal weight across sleeves
#   "inverse_vol"    — weight by 1/volatility
#   "min_corr"       — greedy: start with best, add least correlated, then EW
#   "risk_parity"    — each sleeve contributes equal portfolio risk
#
# Args:
#   strategy_dirs — character vector of directory names
#   method        — combination method (default "equal")
#   rebalance     — "monthly" or "quarterly" sleeve weight rebalancing
#   lookback      — days for vol/corr estimation (default 252)
#   force_resim   — re-simulate strategies if needed
#
# Returns: list(
#   combined_xts    — xts of combined portfolio daily returns
#   sleeve_xts      — xts of individual sleeve returns (merged)
#   weights_log     — data.table of sleeve weights over time
#   method          — method used
#   strategy_dirs   — strategies included
#   perf            — performance summary (data.table)
# )
#==============================================================================

build_multi_sleeve <- function(strategy_dirs,
                                method      = "equal",
                                rebalance   = "monthly",
                                lookback    = 252L,
                                force_resim = FALSE) {

  cat(sprintf("\n[multi_sleeve] Building portfolio: method=%s, %d sleeves\n",
              method, length(strategy_dirs)))

  # --- Load all sleeve returns ---
  sleeve_list <- load_sleeve_returns(strategy_dirs, force_resim = force_resim)

  if (length(sleeve_list) < 2) {
    stop("[multi_sleeve] Need at least 2 strategies. Only loaded: ",
         length(sleeve_list))
  }

  # --- Merge to common dates ---
  merged_xts <- do.call(merge, sleeve_list)
  merged_xts <- merged_xts[complete.cases(merged_xts), ]

  if (nrow(merged_xts) < 60) {
    stop("[multi_sleeve] Insufficient overlapping data: ", nrow(merged_xts), " days")
  }

  n_sleeves <- ncol(merged_xts)
  all_dates <- index(merged_xts)

  cat(sprintf("[multi_sleeve] Merged: %d sleeves x %d days (%s ~ %s)\n",
              n_sleeves, length(all_dates),
              min(all_dates), max(all_dates)))

  # --- Pre-filter with greedy diversification for min_corr method ---
  if (method == "min_corr") {
    ret_mat <- coredata(merged_xts)
    corr_mat <- cor(ret_mat, use = "pairwise.complete.obs")
    div_names <- .greedy_diversify(corr_mat, colnames(merged_xts))
    if (length(div_names) < ncol(merged_xts)) {
      cat(sprintf("[multi_sleeve] min_corr: Reduced from %d to %d sleeves\n",
                  ncol(merged_xts), length(div_names)))
      merged_xts <- merged_xts[, div_names]
      n_sleeves <- ncol(merged_xts)
    }
  }

  # --- Determine rebalance dates ---
  reb_dates <- .get_rebalance_dates(all_dates, rebalance)
  cat(sprintf("[multi_sleeve] Rebalance dates: %d (%s)\n",
              length(reb_dates), rebalance))

  # --- Compute weights at each rebalance date ---
  weights_log <- list()
  current_weights <- rep(1 / n_sleeves, n_sleeves)
  names(current_weights) <- colnames(merged_xts)

  combined_rets <- numeric(length(all_dates))
  reb_idx <- 1L

  for (t in seq_along(all_dates)) {
    d <- all_dates[t]

    # Check if rebalance needed
    if (reb_idx <= length(reb_dates) && d >= reb_dates[reb_idx]) {

      # Compute new weights based on lookback window
      lb_start <- max(1L, t - lookback)
      window <- merged_xts[lb_start:(t - 1), ]

      if (nrow(window) >= 30) {
        new_weights <- .compute_sleeve_weights(window, method)
        if (!is.null(new_weights) && length(new_weights) == n_sleeves) {
          current_weights <- new_weights
        }
      }

      weights_log[[length(weights_log) + 1]] <- data.table(
        Date = d,
        t(current_weights)
      )

      reb_idx <- reb_idx + 1L
    }

    # Apply weights to day's returns
    day_rets <- as.numeric(coredata(merged_xts[t, ]))
    combined_rets[t] <- sum(current_weights * day_rets, na.rm = TRUE)
  }

  # --- Build output xts ---
  combined_xts <- xts(combined_rets, order.by = all_dates)
  names(combined_xts) <- "MultiSleeve"

  weights_dt <- rbindlist(weights_log, fill = TRUE)

  # --- Performance summary ---
  perf <- summarise_perf(combined_xts, sprintf("MultiSleeve_%s", method))

  # Individual sleeve performance
  sleeve_perfs <- rbindlist(lapply(1:n_sleeves, function(i) {
    summarise_perf(merged_xts[, i], colnames(merged_xts)[i])
  }))

  all_perf <- rbind(perf, sleeve_perfs)

  # --- Console report ---
  cat("\n=== MULTI-SLEEVE PORTFOLIO RESULT ===\n")
  cat(sprintf("Method    : %s\n", method))
  cat(sprintf("Sleeves   : %d\n", n_sleeves))
  cat(sprintf("Period    : %s ~ %s (%d days)\n",
              min(all_dates), max(all_dates), length(all_dates)))
  cat(sprintf("Rebalances: %d\n", nrow(weights_dt)))
  cat("\nPerformance:\n")
  print(all_perf)

  # Final weights
  if (nrow(weights_dt) > 0) {
    cat("\nFinal weights:\n")
    last_w <- weights_dt[.N]
    for (nm in colnames(merged_xts)) {
      w_val <- if (nm %in% names(last_w)) last_w[[nm]] else NA
      cat(sprintf("  %s: %.1f%%\n", nm, w_val * 100))
    }
  }
  cat("=====================================\n\n")

  list(
    combined_xts  = combined_xts,
    sleeve_xts    = merged_xts,
    weights_log   = weights_dt,
    method        = method,
    strategy_dirs = names(sleeve_list),
    perf          = all_perf,
    n_sleeves     = n_sleeves
  )
}


#==============================================================================
# 4b. .get_rebalance_dates() — Extract rebalance schedule from date vector
#==============================================================================

.get_rebalance_dates <- function(all_dates, freq = "monthly") {

  dt <- data.table(Date = all_dates)
  dt[, YM := format(Date, "%Y-%m")]

  if (freq == "quarterly") {
    dt[, Month := as.integer(format(Date, "%m"))]
    dt[, Quarter := ceiling(Month / 3)]
    dt[, YQ := paste0(format(Date, "%Y"), "-Q", Quarter)]
    reb <- dt[, .(Date = min(Date)), by = YQ]$Date
  } else {
    # Monthly: first trading day of each month
    reb <- dt[, .(Date = min(Date)), by = YM]$Date
  }

  sort(reb)
}


#==============================================================================
# 4c. .compute_sleeve_weights() — Weight computation for different methods
#==============================================================================

.compute_sleeve_weights <- function(window_xts, method) {

  n <- ncol(window_xts)
  ret_mat <- coredata(window_xts)

  if (method == "equal" || method == "min_corr") {
    # Equal weight (min_corr already filtered sleeves; EW within selected)
    return(rep(1 / n, n))
  }

  if (method == "inverse_vol") {
    vols <- apply(ret_mat, 2, sd, na.rm = TRUE)
    vols[vols < 1e-8] <- 1e-8
    w <- 1 / vols
    w <- w / sum(w)
    return(w)
  }

  if (method == "risk_parity") {
    return(.risk_parity_weights(ret_mat))
  }

  # Fallback
  rep(1 / n, n)
}


#==============================================================================
# 4d. .risk_parity_weights() — Equal risk contribution across sleeves
#==============================================================================

.risk_parity_weights <- function(ret_mat, max_iter = 200L, tol = 1e-8) {

  n <- ncol(ret_mat)
  if (n < 2) return(rep(1, n))

  # Covariance with shrinkage
  cov_mat <- cov(ret_mat, use = "pairwise.complete.obs")
  cov_mat[is.na(cov_mat)] <- 0

  # Simple shrinkage toward diagonal
  mu_cov <- mean(diag(cov_mat))
  cov_mat <- 0.8 * cov_mat + 0.2 * mu_cov * diag(n)

  # Iterative ERC (same algorithm as backtest_harness.R)
  w <- rep(1 / n, n)

  for (iter in 1:max_iter) {
    sigma_w <- as.numeric(cov_mat %*% w)
    port_vol <- sqrt(as.numeric(t(w) %*% cov_mat %*% w))

    if (port_vol < 1e-10) break

    rc <- w * sigma_w / port_vol
    target_rc <- port_vol / n

    w_new <- w * (target_rc / rc)
    w_new[is.na(w_new) | w_new < 1e-6] <- 1e-6
    w_new <- w_new / sum(w_new)

    if (max(abs(w_new - w)) < tol) break
    w <- w_new
  }

  w
}


#==============================================================================
# 5. summarise_multi_sleeve() — Extended performance summary
#==============================================================================
#
# Args:
#   result — output of build_multi_sleeve()
#
# Returns: data.table with full performance metrics for the combined portfolio
#          and each individual sleeve
#==============================================================================

summarise_multi_sleeve <- function(result) {

  if (is.null(result)) {
    cat("[summarise] No result to summarise.\n")
    return(NULL)
  }

  combined <- result$combined_xts
  sleeves  <- result$sleeve_xts

  # Combined portfolio metrics
  r <- combined[!is.na(combined)]
  n <- length(r)

  if (n < 60) {
    cat("[summarise] Insufficient data for summary.\n")
    return(NULL)
  }

  ann_ret <- as.numeric((prod(1 + r))^(252 / n) - 1)
  ann_vol <- as.numeric(sd(r) * sqrt(252))
  sharpe  <- ann_ret / ann_vol
  mdd     <- as.numeric(maxDrawdown(r))
  calmar  <- if (mdd > 0) ann_ret / mdd else NA_real_

  # Avg pairwise correlation among sleeves
  if (ncol(sleeves) >= 2) {
    corr_mat <- cor(coredata(sleeves), use = "pairwise.complete.obs")
    avg_corr <- .avg_offdiag(corr_mat)
  } else {
    avg_corr <- NA_real_
  }

  # Diversification ratio: sum(w_i * vol_i) / port_vol
  sleeve_vols <- apply(coredata(sleeves), 2, function(x) sd(x, na.rm = TRUE) * sqrt(252))
  n_s <- ncol(sleeves)
  w_eq <- rep(1 / n_s, n_s)  # approximate; actual weights may vary
  div_ratio <- sum(w_eq * sleeve_vols) / ann_vol

  combined_dt <- data.table(
    Label        = sprintf("MultiSleeve_%s", result$method),
    CAGR         = round(ann_ret * 100, 2),
    AnnVol       = round(ann_vol * 100, 2),
    Sharpe       = round(sharpe, 3),
    MDD          = round(mdd * 100, 2),
    Calmar       = round(calmar, 3),
    Avg_Corr     = round(avg_corr, 3),
    Div_Ratio    = round(div_ratio, 3),
    N_Sleeves    = n_s,
    Method       = result$method
  )

  # Individual sleeves
  sleeve_dt <- rbindlist(lapply(1:ncol(sleeves), function(i) {
    s <- sleeves[, i]
    perf <- summarise_perf(s, colnames(sleeves)[i])
    perf
  }))

  cat("\n=== MULTI-SLEEVE SUMMARY ===\n")
  cat("Combined:\n")
  print(combined_dt)
  cat("\nIndividual sleeves:\n")
  print(sleeve_dt)
  cat("============================\n")

  list(
    combined = combined_dt,
    sleeves  = sleeve_dt
  )
}


#==============================================================================
# 6. plot_sleeve_correlation() — Correlation heatmap
#==============================================================================
#
# Args:
#   corr_result — output of analyze_sleeve_correlations()
#   output_dir  — directory to save PNG (NULL = display only)
#
# Returns: ggplot object (invisible)
#==============================================================================

plot_sleeve_correlation <- function(corr_result, output_dir = NULL) {

  if (is.null(corr_result) || is.null(corr_result$matrix)) {
    cat("[plot] No correlation data.\n")
    return(invisible(NULL))
  }

  corr_mat <- corr_result$matrix
  n <- nrow(corr_mat)

  # Reshape for ggplot
  labels <- rownames(corr_mat)
  plot_dt <- data.table(
    Row = rep(labels, each = n),
    Col = rep(labels, times = n),
    Corr = as.vector(corr_mat)
  )

  # Order by clustering
  hc_order <- corr_result$clusters$order
  ordered_labels <- labels[hc_order]
  plot_dt[, Row := factor(Row, levels = ordered_labels)]
  plot_dt[, Col := factor(Col, levels = rev(ordered_labels))]

  p <- ggplot(plot_dt, aes(x = Row, y = Col, fill = Corr)) +
    geom_tile(color = "white", linewidth = 0.3) +
    geom_text(aes(label = sprintf("%.2f", Corr)),
              size = max(2.2, 4 - n * 0.15), color = "grey20") +
    scale_fill_gradient2(
      low = "#2166AC", mid = "white", high = "#B2182B",
      midpoint = 0, limits = c(-1, 1),
      name = "Correlation"
    ) +
    labs(
      title = sprintf("Sleeve Correlation Heatmap (%d strategies)", n),
      x = NULL, y = NULL
    ) +
    theme_minimal(base_size = 11) +
    theme(
      axis.text.x     = element_text(angle = 45, hjust = 1, size = 8),
      axis.text.y     = element_text(size = 8),
      plot.title       = element_text(face = "bold", hjust = 0.5, size = 13),
      panel.grid       = element_blank(),
      legend.position  = "right"
    ) +
    coord_fixed()

  if (!is.null(output_dir)) {
    if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
    ggsave(file.path(output_dir, "sleeve_correlation_heatmap.png"), p,
           width = max(8, n * 0.8 + 3), height = max(7, n * 0.8 + 2), dpi = 150)
    cat(sprintf("[plot] Heatmap saved to %s\n",
                file.path(output_dir, "sleeve_correlation_heatmap.png")))
  }

  print(p)
  invisible(p)
}


#==============================================================================
# 7. plot_sleeve_equity() — Combined equity curve plot
#==============================================================================
#
# Args:
#   result     — output of build_multi_sleeve()
#   output_dir — directory to save PNG (NULL = display only)
#
# Returns: ggplot object (invisible)
#==============================================================================

plot_sleeve_equity <- function(result, output_dir = NULL) {

  if (is.null(result)) {
    cat("[plot] No result to plot.\n")
    return(invisible(NULL))
  }

  combined <- result$combined_xts
  sleeves  <- result$sleeve_xts

  # Build cumulative return series
  all_series <- merge(combined, sleeves)
  cum_ret <- apply(coredata(all_series), 2, function(x) cumprod(1 + x))
  cum_dt <- data.table(
    Date = rep(index(all_series), ncol(all_series)),
    Label = rep(colnames(all_series), each = nrow(all_series)),
    CumRet = as.vector(cum_ret)
  )

  # Highlight combined portfolio
  cum_dt[, is_combined := Label == "MultiSleeve"]
  cum_dt[, LineSize := fifelse(is_combined, 1.8, 0.6)]

  # Color palette
  n_series <- ncol(all_series)
  colors <- c("#E84545", rep("#B0B8C1", n_series - 1))  # Red for combined, grey for sleeves
  names(colors) <- colnames(all_series)

  p <- ggplot(cum_dt, aes(x = Date, y = CumRet, color = Label, linewidth = LineSize)) +
    geom_line() +
    scale_color_manual(values = colors) +
    scale_linewidth_identity() +
    scale_y_log10(labels = scales::comma) +
    labs(
      title = sprintf("Multi-Sleeve Equity Curve (%s, %d sleeves)",
                      result$method, result$n_sleeves),
      x = NULL, y = "Cumulative Return (log scale)"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title       = element_text(face = "bold", size = 13),
      legend.position  = "bottom",
      legend.title     = element_blank(),
      panel.grid.minor = element_blank()
    )

  if (!is.null(output_dir)) {
    if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
    ggsave(file.path(output_dir, "sleeve_equity_curve.png"), p,
           width = 14, height = 7, dpi = 150)
    cat(sprintf("[plot] Equity curve saved to %s\n",
                file.path(output_dir, "sleeve_equity_curve.png")))
  }

  print(p)
  invisible(p)
}


#==============================================================================
# 8. plot_sleeve_weights() — Stacked area chart of sleeve weights over time
#==============================================================================

plot_sleeve_weights <- function(result, output_dir = NULL) {

  if (is.null(result) || nrow(result$weights_log) < 2) {
    cat("[plot] Insufficient weight data for plot.\n")
    return(invisible(NULL))
  }

  wt <- copy(result$weights_log)
  id_cols <- "Date"
  val_cols <- setdiff(names(wt), id_cols)

  wt_long <- melt(wt, id.vars = id_cols, variable.name = "Sleeve",
                   value.name = "Weight")

  p <- ggplot(wt_long, aes(x = Date, y = Weight, fill = Sleeve)) +
    geom_area(alpha = 0.8, position = "stack") +
    scale_y_continuous(labels = scales::percent_format(), expand = c(0, 0)) +
    labs(
      title = sprintf("Sleeve Weight Allocation (%s)", result$method),
      x = NULL, y = "Portfolio Weight"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title       = element_text(face = "bold", size = 13),
      legend.position  = "bottom",
      legend.title     = element_blank(),
      panel.grid.minor = element_blank()
    )

  if (!is.null(output_dir)) {
    if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
    ggsave(file.path(output_dir, "sleeve_weight_allocation.png"), p,
           width = 14, height = 5, dpi = 150)
    cat(sprintf("[plot] Weight chart saved to %s\n",
                file.path(output_dir, "sleeve_weight_allocation.png")))
  }

  print(p)
  invisible(p)
}


#==============================================================================
# 9. compare_combination_methods() — Run all 4 methods and compare
#==============================================================================
#
# Convenience function: runs build_multi_sleeve() with each method,
# returns a comparison table.
#
# Args:
#   strategy_dirs — character vector
#   rebalance     — "monthly" or "quarterly"
#   force_resim   — re-simulate if needed
#
# Returns: data.table comparing all methods side-by-side
#==============================================================================

compare_combination_methods <- function(strategy_dirs,
                                         rebalance   = "monthly",
                                         force_resim = FALSE) {

  methods <- c("equal", "inverse_vol", "min_corr", "risk_parity")
  results <- list()
  perf_list <- list()

  for (m in methods) {
    cat(sprintf("\n--- Method: %s ---\n", m))
    res <- tryCatch(
      build_multi_sleeve(strategy_dirs, method = m,
                          rebalance = rebalance, force_resim = force_resim),
      error = function(e) {
        cat(sprintf("[compare] Method '%s' failed: %s\n", m, conditionMessage(e)))
        NULL
      }
    )

    if (!is.null(res)) {
      results[[m]] <- res
      perf_list[[m]] <- res$perf[1]  # first row = combined portfolio
    }
  }

  if (length(perf_list) == 0) {
    cat("[compare] All methods failed.\n")
    return(NULL)
  }

  comparison <- rbindlist(perf_list)

  cat("\n=== METHOD COMPARISON ===\n")
  print(comparison)

  # Highlight best
  best_sharpe <- comparison[which.max(Sharpe)]
  best_cagr   <- comparison[which.max(CAGR)]
  best_mdd    <- comparison[which.min(MDD)]

  cat(sprintf("\nBest Sharpe : %s (%.3f)\n", best_sharpe$Label, best_sharpe$Sharpe))
  cat(sprintf("Best CAGR   : %s (%.2f%%)\n", best_cagr$Label, best_cagr$CAGR))
  cat(sprintf("Lowest MDD  : %s (%.2f%%)\n", best_mdd$Label, best_mdd$MDD))
  cat("=========================\n\n")

  list(
    comparison = comparison,
    results    = results
  )
}


#==============================================================================
# 10. clear_sleeve_cache() — Remove cached sleeve returns
#==============================================================================

clear_sleeve_cache <- function(strategy_dirs = NULL) {
  if (is.null(strategy_dirs)) {
    files <- list.files(SLEEVE_CACHE_DIR, pattern = "\\.parquet$", full.names = TRUE)
  } else {
    files <- file.path(SLEEVE_CACHE_DIR,
                       paste0(basename(strategy_dirs), ".parquet"))
    files <- files[file.exists(files)]
  }

  if (length(files) == 0) {
    cat("[cache] No cached sleeve returns to clear.\n")
    return(invisible(0L))
  }

  file.remove(files)
  cat(sprintf("[cache] Cleared %d cached sleeve return files.\n", length(files)))
  invisible(length(files))
}


cat("[multi_sleeve_builder] All functions defined.\n")
cat(sprintf("[multi_sleeve_builder] Sleeve cache dir: %s\n", SLEEVE_CACHE_DIR))
