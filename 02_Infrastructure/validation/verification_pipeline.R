#==============================================================================
# Verification Pipeline — Lawbook v1.4.2 3-Axis Verification
#
# Axis 1: Hallucination — DSR (→ statistical_defense.R)
# Axis 2: Loss — IS/OOS overfitting detection
# Axis 3: Distortion — Data quality & look-ahead bias
#
# Usage:
#   source("verification_pipeline.R")
#   result <- verify_strategy(strategy_xts, bm_xts, strategy_name, family)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(xts)
  library(PerformanceAnalytics)
  library(jsonlite)
})

cat("[verification_pipeline] Loaded.\n")

#==============================================================================
# Axis 2: Loss Detection — IS/OOS Overfitting Analysis
#==============================================================================

#' IS/OOS Split Analysis
#' @param strategy_xts xts of daily strategy returns
#' @param split_ratio Fraction for in-sample (default 0.65)
#' @return List with IS metrics, OOS metrics, retention ratios, verdict
verify_loss_axis <- function(strategy_xts, split_ratio = 0.65) {
  r <- as.numeric(strategy_xts[!is.na(strategy_xts)])
  n <- length(r)

  if (n < 252 * 5) {
    return(list(
      verdict = "SKIP",
      reason = sprintf("Insufficient data: %d obs (need 1260+)", n),
      is_sharpe = NA, oos_sharpe = NA, retention = NA
    ))
  }

  split_idx <- floor(n * split_ratio)
  r_is  <- r[1:split_idx]
  r_oos <- r[(split_idx + 1):n]

  # IS metrics
  is_ann <- as.numeric((prod(1 + r_is))^(252 / length(r_is)) - 1)
  is_vol <- as.numeric(sd(r_is) * sqrt(252))
  is_sr  <- if (is_vol > 0) is_ann / is_vol else 0
  is_mdd <- as.numeric(maxDrawdown(xts(r_is,
    order.by = index(strategy_xts)[1:split_idx])))

  # OOS metrics
  oos_ann <- as.numeric((prod(1 + r_oos))^(252 / length(r_oos)) - 1)
  oos_vol <- as.numeric(sd(r_oos) * sqrt(252))
  oos_sr  <- if (oos_vol > 0) oos_ann / oos_vol else 0
  oos_mdd <- as.numeric(maxDrawdown(xts(r_oos,
    order.by = index(strategy_xts)[(split_idx + 1):n])))

  # Retention ratios
  sharpe_retention <- if (abs(is_sr) > 0.05) oos_sr / is_sr else NA
  cagr_retention   <- if (abs(is_ann) > 0.01) oos_ann / is_ann else NA

  # Verdict
  verdict <- if (is.na(sharpe_retention)) {
    "INCONCLUSIVE"
  } else if (sharpe_retention >= 0.7) {
    "ROBUST"           # OOS retains 70%+ of IS performance
  } else if (sharpe_retention >= 0.4) {
    "ACCEPTABLE"       # Some degradation but not severe
  } else if (sharpe_retention >= 0.0) {
    "DEGRADED"         # Significant overfitting signal
  } else {
    "OVERFIT_SEVERE"   # OOS Sharpe negative = strong overfitting
  }

  # Subsample stability: split into 4 quarters
  quarter_sharpes <- sapply(1:4, function(q) {
    start <- floor((q - 1) * n / 4) + 1
    end <- floor(q * n / 4)
    rq <- r[start:end]
    ann_q <- as.numeric((prod(1 + rq))^(252 / length(rq)) - 1)
    vol_q <- sd(rq) * sqrt(252)
    if (vol_q > 0) ann_q / vol_q else 0
  })
  quarter_consistency <- sum(quarter_sharpes > 0) / 4

  list(
    verdict     = verdict,
    is_sharpe   = round(is_sr, 3),
    is_cagr     = round(is_ann * 100, 2),
    is_mdd      = round(is_mdd * 100, 2),
    oos_sharpe  = round(oos_sr, 3),
    oos_cagr    = round(oos_ann * 100, 2),
    oos_mdd     = round(oos_mdd * 100, 2),
    sharpe_retention = round(sharpe_retention, 3),
    cagr_retention   = round(cagr_retention, 3),
    quarter_sharpes  = round(quarter_sharpes, 3),
    quarter_consistency = quarter_consistency,
    split_ratio = split_ratio,
    n_is  = split_idx,
    n_oos = n - split_idx
  )
}

#==============================================================================
# Axis 3: Distortion Detection — Data Quality & Look-Ahead Bias
#==============================================================================

#' Check for common data distortions
#' @param strategy_xts xts of strategy returns
#' @param FACTORS data.table with Date, Ticker, Score columns
#' @param RAWDATA Optional: raw data for cross-validation
#' @return List with distortion checks and overall verdict
verify_distortion_axis <- function(strategy_xts, FACTORS = NULL,
                                    RAWDATA = NULL) {
  checks <- list()
  flags <- 0L

  r <- as.numeric(strategy_xts[!is.na(strategy_xts)])
  dates <- index(strategy_xts[!is.na(strategy_xts)])

  # Check 1: Suspicious return patterns (exact zeros, repeated values)
  n_zero <- sum(r == 0)
  zero_pct <- n_zero / length(r)
  if (zero_pct > 0.3) {
    flags <- flags + 1L
    checks$excessive_zeros <- list(
      flag = TRUE,
      detail = sprintf("%.1f%% zero returns (%d/%d) — possible stale data",
                       zero_pct * 100, n_zero, length(r))
    )
  } else {
    checks$excessive_zeros <- list(flag = FALSE, detail = "OK")
  }

  # Check 2: Return magnitude — daily returns > 30% are suspicious
  extreme_rets <- sum(abs(r) > 0.30)
  if (extreme_rets > 5) {
    flags <- flags + 1L
    checks$extreme_returns <- list(
      flag = TRUE,
      detail = sprintf("%d daily returns > 30%% — possible data error", extreme_rets)
    )
  } else {
    checks$extreme_returns <- list(flag = FALSE, detail = "OK")
  }

  # Check 3: Gaps in trading dates (missing business days)
  if (length(dates) >= 100) {
    diffs <- as.numeric(diff(dates))
    long_gaps <- sum(diffs > 7)  # More than 1 week gap
    if (long_gaps > 10) {
      flags <- flags + 1L
      checks$date_gaps <- list(
        flag = TRUE,
        detail = sprintf("%d gaps > 7 days — possible incomplete data", long_gaps)
      )
    } else {
      checks$date_gaps <- list(flag = FALSE, detail = "OK")
    }
  }

  # Check 4: Look-ahead bias — Factor signals should only use past data
  if (!is.null(FACTORS)) {
    factor_dates <- sort(unique(FACTORS$Date))
    trading_dates <- sort(unique(dates))

    # Factor date should be a trading day or month-end
    # Suspicious: factor dates that are in the future relative to trading
    future_signals <- sum(factor_dates > max(trading_dates))
    if (future_signals > 0) {
      flags <- flags + 1L
      checks$look_ahead <- list(
        flag = TRUE,
        detail = sprintf("%d factor dates beyond trading data — possible look-ahead",
                         future_signals)
      )
    } else {
      checks$look_ahead <- list(flag = FALSE, detail = "OK")
    }

    # Check signal count consistency
    avg_signals <- mean(FACTORS[, .N, by = Date]$N)
    if (avg_signals < 20) {
      flags <- flags + 1L
      checks$thin_signals <- list(
        flag = TRUE,
        detail = sprintf("Avg %.0f signals/date — very thin universe", avg_signals)
      )
    } else {
      checks$thin_signals <- list(flag = FALSE, detail = "OK")
    }
  }

  # Check 5: Survivorship bias proxy — early-period vs late-period universe size
  if (!is.null(RAWDATA)) {
    dates_sorted <- sort(unique(RAWDATA$Date))
    n_dates <- length(dates_sorted)
    if (n_dates >= 500) {
      early_dates <- dates_sorted[1:min(252, n_dates)]
      late_dates  <- tail(dates_sorted, 252)
      early_n <- RAWDATA[Date %in% early_dates, uniqueN(Ticker)]
      late_n  <- RAWDATA[Date %in% late_dates, uniqueN(Ticker)]
      ratio <- early_n / max(late_n, 1)
      if (ratio < 0.3) {
        flags <- flags + 1L
        checks$survivorship <- list(
          flag = TRUE,
          detail = sprintf("Early universe %d vs late %d (ratio %.2f) — possible survivorship",
                           early_n, late_n, ratio)
        )
      } else {
        checks$survivorship <- list(flag = FALSE, detail = "OK")
      }
    }
  }

  # Overall verdict
  verdict <- if (flags == 0) {
    "CLEAN"
  } else if (flags <= 2) {
    "MINOR_FLAGS"
  } else {
    "DISTORTED"
  }

  list(
    verdict = verdict,
    n_flags = flags,
    checks  = checks
  )
}

#==============================================================================
# Combined 3-Axis Verification
#==============================================================================

#' Run full 3-axis verification
#' @param strategy_xts xts of strategy returns
#' @param bm_xts Optional benchmark xts
#' @param strategy_name Strategy identifier
#' @param family Factor family for DSR
#' @param FACTORS Optional factor data.table
#' @param RAWDATA Optional raw data for distortion checks
#' @param output_dir Optional directory to save verification JSON
#' @return List with all 3 axes results and overall verdict
verify_strategy <- function(strategy_xts, bm_xts = NULL,
                             strategy_name = "Unknown",
                             family = "general",
                             FACTORS = NULL,
                             RAWDATA = NULL,
                             output_dir = NULL) {

  cat(sprintf("\n=== 3-Axis Verification: %s ===\n", strategy_name))

  # Axis 1: Hallucination (DSR)
  ax1 <- list(verdict = "SKIP", note = "DSR computed in hurdle_gate.R")
  r <- as.numeric(strategy_xts[!is.na(strategy_xts)])
  if (exists("compute_dsr_family") && is.function(compute_dsr_family)) {
    sharpe <- mean(r) / sd(r) * sqrt(252)
    ax1 <- tryCatch(
      compute_dsr_family(sharpe, length(r), family),
      error = function(e) list(verdict = "ERROR", note = conditionMessage(e))
    )
    ax1$verdict <- if (isTRUE(ax1$significant)) "PASS" else "FAIL"
  } else if (exists("compute_dsr") && is.function(compute_dsr)) {
    sharpe <- mean(r) / sd(r) * sqrt(252)
    ax1 <- tryCatch(
      compute_dsr(sharpe, length(r), 465L),
      error = function(e) list(verdict = "ERROR", note = conditionMessage(e))
    )
    ax1$verdict <- if (isTRUE(ax1$significant)) "PASS" else "FAIL"
  }
  cat(sprintf("  Axis 1 (Hallucination/DSR): %s\n", ax1$verdict))

  # Axis 2: Loss (IS/OOS)
  ax2 <- verify_loss_axis(strategy_xts)
  cat(sprintf("  Axis 2 (Loss/Overfitting):  %s", ax2$verdict))
  if (!is.na(ax2$sharpe_retention)) {
    cat(sprintf(" (IS SR=%.3f, OOS SR=%.3f, retention=%.2f)",
                ax2$is_sharpe, ax2$oos_sharpe, ax2$sharpe_retention))
  }
  cat("\n")

  # Axis 3: Distortion
  ax3 <- verify_distortion_axis(strategy_xts, FACTORS, RAWDATA)
  cat(sprintf("  Axis 3 (Distortion):        %s (%d flags)\n",
              ax3$verdict, ax3$n_flags))

  # Overall
  verdicts <- c(ax1$verdict, ax2$verdict, ax3$verdict)
  severe <- any(verdicts %in% c("FAIL", "OVERFIT_SEVERE", "DISTORTED"))
  minor  <- any(verdicts %in% c("DEGRADED", "MINOR_FLAGS"))

  overall <- if (severe) {
    "FAIL"
  } else if (minor) {
    "PASS_WITH_FLAGS"
  } else {
    "PASS"
  }

  cat(sprintf("  OVERALL: %s\n", overall))
  cat("================================\n")

  result <- list(
    strategy    = strategy_name,
    family      = family,
    timestamp   = format(Sys.time(), "%Y-%m-%d %H:%M:%S KST"),
    overall     = overall,
    axis1_hallucination = ax1,
    axis2_loss          = ax2,
    axis3_distortion    = ax3
  )

  # Save if output_dir provided
  if (!is.null(output_dir)) {
    if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
    out_path <- file.path(output_dir, "verification_result.json")
    write_json(result, out_path, auto_unbox = TRUE, pretty = TRUE)
    cat(sprintf("  Saved: %s\n", out_path))
  }

  result
}

cat("[verification_pipeline] Functions: verify_loss_axis(), verify_distortion_axis(), verify_strategy()\n")
