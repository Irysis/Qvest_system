#==============================================================================
# V7 Research Engine — Leave-One-Out Validator
# loo_validator.R
#
# Four LOO validation functions that stress-test strategy robustness by
# systematically removing crises, regimes, subperiods, or sleeves and
# checking whether performance degrades beyond acceptable thresholds.
#
# Usage:
#   source("02_Infrastructure/loo_validator.R")
#   crisis_result  <- sg_loo_crisis("STR_1435")
#   regime_result  <- sg_loo_regime("STR_1435")
#   period_result  <- sg_loo_subperiod("STR_1435", subperiod_years = 3)
#   sleeve_result  <- sg_loo_sleeve("PORT_001", c("STR_1060", "STR_1435"))
#
# Dependencies: data.table, xts, PerformanceAnalytics
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(xts)
  library(PerformanceAnalytics)
})

# ─── Config: find project root ───────────────────────────────────────────────
if (!exists("PROJECT_ROOT")) {
  .loo_root_candidates <- c(
    "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
    "/mnt/c/Users/99922/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
  )
  PROJECT_ROOT <- .loo_root_candidates[sapply(.loo_root_candidates, dir.exists)][1]
  if (is.na(PROJECT_ROOT)) {
    PROJECT_ROOT <- Sys.getenv("QM_ROOT",
      unset = "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot")
  }
  rm(.loo_root_candidates)
}
STRATEGY_OUTPUT <- file.path(PROJECT_ROOT, "04_Research", "strategies")

# ─── Default Crisis Periods ──────────────────────────────────────────────────
.LOO_DEFAULT_CRISES <- list(
  GFC   = c("2008-01-01", "2009-03-31"),
  COVID = c("2020-01-01", "2020-06-30"),
  RATE  = c("2022-01-01", "2022-12-31")
)

# ─── Helper: load sim_result.rds from strategy directory ─────────────────────
.loo_load_sim <- function(strategy_id) {
  # Try multiple path patterns
  candidates <- c(
    file.path(STRATEGY_OUTPUT, strategy_id, "output", "sim_result.rds"),
    file.path(STRATEGY_OUTPUT, strategy_id, "sim_result.rds"),
    file.path(STRATEGY_OUTPUT, strategy_id, "output", "sim_result.RDS")
  )

  for (path in candidates) {
    if (file.exists(path)) {
      sim <- tryCatch(readRDS(path), error = function(e) NULL)
      if (!is.null(sim)) {
        cat(sprintf("[loo_validator] Loaded sim_result from: %s\n", path))
        return(sim)
      }
    }
  }
  stop(sprintf("[loo_validator] sim_result.rds not found for %s. Searched:\n  %s",
               strategy_id, paste(candidates, collapse = "\n  ")))
}

# ─── Helper: extract daily returns as xts ────────────────────────────────────
.loo_extract_returns <- function(sim) {
  # Try strategy_xts first (most common in this codebase)
  if (!is.null(sim$strategy_xts) && is.xts(sim$strategy_xts)) {
    ret <- sim$strategy_xts
    if (ncol(ret) > 1 && "Strategy" %in% colnames(ret)) {
      return(ret[, "Strategy"])
    }
    return(ret[, 1])
  }

  # Try PORTFOLIO_LOG
  if (!is.null(sim$PORTFOLIO_LOG)) {
    pl <- as.data.table(sim$PORTFOLIO_LOG)
    if ("Date" %in% names(pl) && "Return" %in% names(pl)) {
      pl <- pl[order(Date)]
      ret_xts <- xts(pl$Return, order.by = as.Date(pl$Date))
      colnames(ret_xts) <- "Strategy"
      return(ret_xts)
    }
    if ("Date" %in% names(pl) && "NAV" %in% names(pl)) {
      pl <- pl[order(Date)]
      navs <- as.numeric(pl$NAV)
      rets <- c(0, diff(navs) / head(navs, -1))
      ret_xts <- xts(rets, order.by = as.Date(pl$Date))
      colnames(ret_xts) <- "Strategy"
      return(ret_xts)
    }
  }

  # Try daily_returns
  if (!is.null(sim$daily_returns)) {
    dr <- sim$daily_returns
    if (is.xts(dr)) return(dr[, 1])
    if (is.data.table(dr) || is.data.frame(dr)) {
      dr <- as.data.table(dr)
      date_col <- intersect(names(dr), c("Date", "date"))[1]
      ret_col  <- intersect(names(dr), c("Return", "return", "ret", "Ret"))[1]
      if (!is.na(date_col) && !is.na(ret_col)) {
        ret_xts <- xts(dr[[ret_col]], order.by = as.Date(dr[[date_col]]))
        colnames(ret_xts) <- "Strategy"
        return(ret_xts)
      }
    }
  }

  stop("[loo_validator] Cannot extract returns from sim_result. Expected strategy_xts, PORTFOLIO_LOG, or daily_returns.")
}

# ─── Helper: compute annualized Sharpe from xts returns ──────────────────────
.loo_sharpe <- function(ret_xts, rf = 0.03) {
  if (is.null(ret_xts) || length(ret_xts) < 20) return(NA_real_)

  ret_vec <- as.numeric(coredata(ret_xts))
  ret_vec <- ret_vec[!is.na(ret_vec)]
  if (length(ret_vec) < 20) return(NA_real_)

  # Trading days per year
  n_days <- length(ret_vec)
  date_range <- as.numeric(difftime(max(index(ret_xts)), min(index(ret_xts)), units = "days"))
  ann_factor <- if (date_range > 0) n_days / (date_range / 365.25) else 252

  mu <- mean(ret_vec) * ann_factor
  vol <- sd(ret_vec) * sqrt(ann_factor)

  if (is.na(vol) || vol < 1e-10) return(NA_real_)
  (mu - rf) / vol
}

#==============================================================================
# 1. sg_loo_crisis — Leave-Out each crisis period
#==============================================================================

#' LOO Crisis Test
#'
#' For each crisis period, remove those dates from returns and recompute Sharpe.
#' Strategy passes if Sharpe without any crisis > max(0.3, 0.5 * full_sharpe).
#'
#' @param strategy_id Character. Strategy folder name
#' @param crises Named list of c(start, end) date strings. NULL uses defaults.
#' @return List with pass (logical), results (data.table)
sg_loo_crisis <- function(strategy_id, crises = NULL) {
  cat(sprintf("[loo_crisis] Running crisis LOO for %s\n", strategy_id))

  sim <- .loo_load_sim(strategy_id)
  ret <- .loo_extract_returns(sim)

  if (is.null(crises)) crises <- .LOO_DEFAULT_CRISES

  full_sharpe <- .loo_sharpe(ret)
  threshold   <- max(0.3, 0.5 * full_sharpe)

  results <- rbindlist(lapply(names(crises), function(crisis_name) {
    period <- crises[[crisis_name]]
    start_d <- as.Date(period[1])
    end_d   <- as.Date(period[2])

    # Remove crisis dates
    crisis_mask <- index(ret) >= start_d & index(ret) <= end_d
    n_removed   <- sum(crisis_mask)

    if (n_removed == 0) {
      return(data.table(
        crisis = crisis_name, n_removed = 0L,
        sharpe_full = round(full_sharpe, 4),
        sharpe_without = round(full_sharpe, 4),
        delta = 0, pass = TRUE
      ))
    }

    ret_excl <- ret[!crisis_mask]
    sr_excl  <- .loo_sharpe(ret_excl)
    delta    <- sr_excl - full_sharpe

    data.table(
      crisis         = crisis_name,
      n_removed      = as.integer(n_removed),
      sharpe_full    = round(full_sharpe, 4),
      sharpe_without = round(sr_excl, 4),
      delta          = round(delta, 4),
      pass           = !is.na(sr_excl) && sr_excl > threshold
    )
  }))

  overall_pass <- all(results$pass)

  cat(sprintf("[loo_crisis] %s: %s (threshold=%.3f)\n",
              strategy_id, ifelse(overall_pass, "PASS", "FAIL"), threshold))
  print(results)

  list(
    strategy_id = strategy_id,
    pass        = overall_pass,
    full_sharpe = full_sharpe,
    threshold   = threshold,
    results     = results
  )
}

#==============================================================================
# 2. sg_loo_regime — Leave-Out each regime category
#==============================================================================

#' LOO Regime Test
#'
#' Remove all dates belonging to each regime category, recompute Sharpe.
#' Pass: no single regime removal causes Sharpe < 0.
#'
#' @param strategy_id Character
#' @param regime_signal data.table with Date and regime columns, or NULL to auto-load
#' @return List with pass, results
sg_loo_regime <- function(strategy_id, regime_signal = NULL) {
  cat(sprintf("[loo_regime] Running regime LOO for %s\n", strategy_id))

  sim <- .loo_load_sim(strategy_id)
  ret <- .loo_extract_returns(sim)

  # Load regime signal if not provided
  if (is.null(regime_signal)) {
    regime_path <- file.path(PROJECT_ROOT, ".cache", "unified_regime_signal.parquet")
    if (file.exists(regime_path)) {
      tryCatch({
        if (requireNamespace("arrow", quietly = TRUE)) {
          regime_signal <- as.data.table(arrow::read_parquet(regime_path))
        }
      }, error = function(e) {
        cat(sprintf("[loo_regime] Warning: cannot load regime signal: %s\n", e$message))
      })
    }
  }

  if (is.null(regime_signal)) {
    cat("[loo_regime] No regime signal available. Skipping.\n")
    return(list(
      strategy_id = strategy_id,
      pass = NA,
      results = data.table(regime_removed = character(0), sharpe = numeric(0), pass = logical(0)),
      note = "No regime signal available"
    ))
  }

  regime_signal <- as.data.table(regime_signal)
  if (!"Date" %in% names(regime_signal)) {
    date_col <- intersect(names(regime_signal), c("date", "month_end"))[1]
    if (!is.na(date_col)) setnames(regime_signal, date_col, "Date")
  }
  regime_signal[, Date := as.Date(Date)]

  regime_col <- intersect(names(regime_signal), c("regime", "Regime", "regime_label", "signal"))[1]
  if (is.na(regime_col)) {
    cat("[loo_regime] No regime column found. Skipping.\n")
    return(list(strategy_id = strategy_id, pass = NA, results = data.table()))
  }

  # Map returns dates to regimes
  ret_dt <- data.table(Date = index(ret), Return = as.numeric(coredata(ret)))
  setkey(regime_signal, Date)
  setkey(ret_dt, Date)
  merged <- regime_signal[ret_dt, on = "Date", roll = TRUE]  # forward-fill regime
  merged <- merged[!is.na(get(regime_col))]

  regime_categories <- unique(merged[[regime_col]])
  full_sharpe <- .loo_sharpe(ret)

  results <- rbindlist(lapply(regime_categories, function(regime_cat) {
    mask <- merged[[regime_col]] != regime_cat
    remaining <- merged[mask]

    if (nrow(remaining) < 60) {
      return(data.table(
        regime_removed = as.character(regime_cat),
        n_removed = sum(!mask),
        sharpe = NA_real_,
        pass = NA
      ))
    }

    ret_excl <- xts(remaining$Return, order.by = as.Date(remaining$Date))
    sr <- .loo_sharpe(ret_excl)

    data.table(
      regime_removed = as.character(regime_cat),
      n_removed      = as.integer(sum(!mask)),
      sharpe         = round(sr, 4),
      pass           = !is.na(sr) && sr >= 0
    )
  }))

  overall_pass <- all(results$pass, na.rm = TRUE)

  cat(sprintf("[loo_regime] %s: %s\n",
              strategy_id, ifelse(overall_pass, "PASS", "FAIL")))
  print(results)

  list(
    strategy_id = strategy_id,
    pass        = overall_pass,
    full_sharpe = full_sharpe,
    results     = results
  )
}

#==============================================================================
# 3. sg_loo_subperiod — Leave-Out non-overlapping 3Y windows
#==============================================================================

#' LOO Subperiod Test
#'
#' Split into non-overlapping windows, remove each, recompute Sharpe.
#' Pass: worst removal still > 0.3.
#'
#' @param strategy_id Character
#' @param subperiod_years Numeric. Window size in years (default = 3)
#' @return List with pass, results
sg_loo_subperiod <- function(strategy_id, subperiod_years = 3) {
  cat(sprintf("[loo_subperiod] Running %dY subperiod LOO for %s\n",
              subperiod_years, strategy_id))

  sim <- .loo_load_sim(strategy_id)
  ret <- .loo_extract_returns(sim)

  dates <- index(ret)
  date_range <- as.numeric(difftime(max(dates), min(dates), units = "days")) / 365.25

  if (date_range < subperiod_years * 2) {
    cat(sprintf("[loo_subperiod] Data span (%.1f years) too short for %dY windows.\n",
                date_range, subperiod_years))
    return(list(
      strategy_id = strategy_id,
      pass = NA,
      results = data.table(),
      note = "Data span too short"
    ))
  }

  full_sharpe <- .loo_sharpe(ret)

  # Create non-overlapping windows
  start_date <- min(dates)
  windows <- list()
  w_idx <- 1L

  while (TRUE) {
    w_start <- start_date + (w_idx - 1) * subperiod_years * 365.25
    w_end   <- w_start + subperiod_years * 365.25 - 1

    if (w_start > max(dates)) break

    # Clamp end to data end
    w_end <- min(w_end, max(dates))

    # Only include if window has meaningful data (at least 1 year)
    if (as.numeric(difftime(w_end, w_start, units = "days")) >= 252) {
      windows[[paste0("W", w_idx)]] <- c(as.Date(w_start), as.Date(w_end))
    }
    w_idx <- w_idx + 1L
  }

  if (length(windows) < 2) {
    return(list(
      strategy_id = strategy_id,
      pass = NA,
      results = data.table(),
      note = "Insufficient windows"
    ))
  }

  results <- rbindlist(lapply(names(windows), function(w_name) {
    w <- windows[[w_name]]
    mask <- dates >= w[1] & dates <= w[2]
    n_removed <- sum(mask)

    ret_excl <- ret[!mask]
    sr <- .loo_sharpe(ret_excl)

    data.table(
      window         = w_name,
      window_start   = as.character(w[1]),
      window_end     = as.character(w[2]),
      n_removed      = as.integer(n_removed),
      sharpe_without = round(sr, 4),
      delta          = round(sr - full_sharpe, 4),
      pass           = !is.na(sr) && sr > 0.3
    )
  }))

  overall_pass <- all(results$pass, na.rm = TRUE)

  cat(sprintf("[loo_subperiod] %s: %s (worst SR without = %.3f)\n",
              strategy_id,
              ifelse(overall_pass, "PASS", "FAIL"),
              min(results$sharpe_without, na.rm = TRUE)))
  print(results)

  list(
    strategy_id = strategy_id,
    pass        = overall_pass,
    full_sharpe = full_sharpe,
    n_windows   = length(windows),
    results     = results
  )
}

#==============================================================================
# 4. sg_loo_sleeve — Leave-Out each sleeve in multi-sleeve portfolio
#==============================================================================

#' LOO Sleeve Test
#'
#' For a multi-sleeve portfolio: remove each sleeve and check that portfolio
#' Sharpe decreases (i.e. every sleeve contributes positively).
#'
#' @param portfolio_id Character. Portfolio identifier
#' @param sleeve_ids Character vector of strategy IDs in the portfolio
#' @param weights Numeric vector of sleeve weights (default: equal weight)
#' @return List with pass, results
sg_loo_sleeve <- function(portfolio_id, sleeve_ids, weights = NULL) {
  cat(sprintf("[loo_sleeve] Running sleeve LOO for %s (%d sleeves)\n",
              portfolio_id, length(sleeve_ids)))

  if (length(sleeve_ids) < 2) {
    return(list(
      portfolio_id = portfolio_id,
      pass = NA,
      results = data.table(),
      note = "Need >= 2 sleeves for LOO"
    ))
  }

  if (is.null(weights)) {
    weights <- rep(1 / length(sleeve_ids), length(sleeve_ids))
  }
  stopifnot(length(weights) == length(sleeve_ids))
  weights <- weights / sum(weights)  # normalize

  # Load all sleeve returns
  sleeve_returns <- list()
  for (sid in sleeve_ids) {
    sim <- tryCatch(.loo_load_sim(sid), error = function(e) {
      cat(sprintf("[loo_sleeve] Cannot load %s: %s\n", sid, e$message))
      NULL
    })
    if (!is.null(sim)) {
      sleeve_returns[[sid]] <- .loo_extract_returns(sim)
    }
  }

  if (length(sleeve_returns) < 2) {
    return(list(
      portfolio_id = portfolio_id,
      pass = NA,
      results = data.table(),
      note = "Could not load enough sleeve data"
    ))
  }

  # Align all sleeves to common dates
  common_dates <- Reduce(intersect, lapply(sleeve_returns, function(x) as.character(index(x))))
  common_dates <- sort(as.Date(common_dates))

  if (length(common_dates) < 60) {
    return(list(
      portfolio_id = portfolio_id,
      pass = NA,
      results = data.table(),
      note = "Insufficient common dates"
    ))
  }

  # Compute full portfolio return (weighted sum)
  available_ids <- names(sleeve_returns)
  w_map <- setNames(weights[match(available_ids, sleeve_ids)], available_ids)
  w_map <- w_map / sum(w_map)  # re-normalize for available sleeves

  aligned <- do.call(merge, lapply(sleeve_returns, function(x) x[common_dates]))
  colnames(aligned) <- available_ids

  full_port_ret <- xts(
    as.numeric(coredata(aligned) %*% w_map[colnames(aligned)]),
    order.by = common_dates
  )
  full_sharpe <- .loo_sharpe(full_port_ret)
  full_mdd    <- tryCatch(
    as.numeric(maxDrawdown(full_port_ret)),
    error = function(e) NA_real_
  )

  # LOO: remove each sleeve and recompute
  results <- rbindlist(lapply(available_ids, function(remove_id) {
    remaining <- setdiff(available_ids, remove_id)
    if (length(remaining) == 0) {
      return(data.table(
        sleeve_removed = remove_id,
        sharpe_full = round(full_sharpe, 4),
        sharpe_without = NA_real_,
        sharpe_delta = NA_real_,
        mdd_full = round(full_mdd * 100, 2),
        mdd_without = NA_real_,
        mdd_delta = NA_real_,
        contributes = NA
      ))
    }

    # Re-weight remaining sleeves proportionally
    w_remaining <- w_map[remaining]
    w_remaining <- w_remaining / sum(w_remaining)

    port_excl <- xts(
      as.numeric(coredata(aligned[, remaining, drop = FALSE]) %*% w_remaining),
      order.by = common_dates
    )
    sr_excl  <- .loo_sharpe(port_excl)
    mdd_excl <- tryCatch(
      as.numeric(maxDrawdown(port_excl)),
      error = function(e) NA_real_
    )

    sr_delta  <- sr_excl - full_sharpe
    mdd_delta <- if (!is.na(mdd_excl) && !is.na(full_mdd)) {
      (mdd_excl - full_mdd) * 100
    } else NA_real_

    data.table(
      sleeve_removed = remove_id,
      sharpe_full    = round(full_sharpe, 4),
      sharpe_without = round(sr_excl, 4),
      sharpe_delta   = round(sr_delta, 4),
      mdd_full       = round(full_mdd * 100, 2),
      mdd_without    = round(mdd_excl * 100, 2),
      mdd_delta      = round(mdd_delta, 2),
      contributes    = !is.na(sr_delta) && sr_delta < 0  # removal hurts → sleeve contributes
    )
  }))

  overall_pass <- all(results$contributes, na.rm = TRUE)

  cat(sprintf("[loo_sleeve] %s: %s\n",
              portfolio_id, ifelse(overall_pass, "PASS", "FAIL")))
  print(results)

  list(
    portfolio_id = portfolio_id,
    pass         = overall_pass,
    full_sharpe  = full_sharpe,
    full_mdd     = full_mdd,
    results      = results
  )
}

cat("[loo_validator] Loaded — 4 LOO validation functions available.\n")
