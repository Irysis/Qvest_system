#==============================================================================
# Regime Switching Cost (v55 Risk Engine L13 확장)
#
# role=regime_adaptive 전략 전용.
# Transition cost, signal lag, stability 측정.
#
# Admission Rule v3.5.2 Gate 7 (Regime_Adaptive threshold) 자동화:
#   - switching_alpha > 0.10
#   - transition_cost < 50bps
#   - regime_signal_lag <= 1 month
#   - stability_score_36M >= 0.60
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

#' Switching alpha: regime-conditional vs unconditional SR diff
#'
#' @param returns numeric (monthly)
#' @param regime_series factor/character
switching_alpha_check <- function(returns, regime_series) {
  n <- length(returns)
  if (length(regime_series) != n) stop("length mismatch")

  sr_unconditional <- mean(returns) / sd(returns) * sqrt(12)

  # Regime-conditional SR (weighted avg of regime-specific SR)
  regimes <- unique(regime_series)
  regime_srs <- sapply(regimes, function(r) {
    mask <- regime_series == r
    if (sum(mask) < 6) return(NA)
    rets <- returns[mask]
    mean(rets) / sd(rets) * sqrt(12)
  })
  regime_weights <- sapply(regimes, function(r) sum(regime_series == r) / n)
  sr_conditional <- sum(regime_srs * regime_weights, na.rm = TRUE)

  switching_alpha <- sr_conditional - sr_unconditional

  list(
    sr_unconditional = round(sr_unconditional, 3),
    sr_conditional = round(sr_conditional, 3),
    switching_alpha = round(switching_alpha, 3),
    regime_specific_sr = as.list(round(regime_srs, 3)),
    threshold = 0.10,
    passed = !is.na(switching_alpha) && switching_alpha > 0.10
  )
}

#' Transition cost: weight change × turnover impact
#'
#' @param weights_history data.frame/data.table (cols = strategy_id, rows = time)
#' @param turnover_impact_bps numeric (per-unit weight change impact, default 10bps)
transition_cost_check <- function(weights_history, turnover_impact_bps = 10) {
  if (is.data.frame(weights_history)) weights_history <- as.matrix(weights_history)

  # Per-period abs weight change
  weight_changes <- abs(diff(weights_history))
  total_turnover <- rowSums(weight_changes)

  avg_turnover <- mean(total_turnover)
  transition_cost_bps <- avg_turnover * turnover_impact_bps
  transition_cost_ann_bps <- transition_cost_bps * 12

  list(
    avg_turnover_per_period = round(avg_turnover, 4),
    transition_cost_bps_per_period = round(transition_cost_bps, 2),
    transition_cost_bps_annualized = round(transition_cost_ann_bps, 2),
    threshold_max_bps = 50,
    passed = transition_cost_ann_bps < 50
  )
}

#' Regime signal lag check (forward-looking 방지)
#'
#' @param signal_dates Date vector (when signal was generated)
#' @param execution_dates Date vector (when decision applied)
signal_lag_check <- function(signal_dates, execution_dates) {
  if (length(signal_dates) != length(execution_dates)) stop("length mismatch")

  if (inherits(signal_dates, "character")) signal_dates <- as.Date(signal_dates)
  if (inherits(execution_dates, "character")) execution_dates <- as.Date(execution_dates)

  # Lag in days (execution - signal, should be positive)
  lags <- as.numeric(execution_dates - signal_dates)

  any_forward_looking <- any(lags < 0)  # signal date > execution date = forward-looking
  avg_lag_days <- mean(lags, na.rm = TRUE)
  avg_lag_months <- avg_lag_days / 30.44

  list(
    avg_lag_days = round(avg_lag_days, 1),
    avg_lag_months = round(avg_lag_months, 2),
    any_forward_looking = any_forward_looking,
    threshold_max_months = 1,
    passed = !any_forward_looking && avg_lag_months <= 1,
    reason = if (any_forward_looking) "Forward-looking bias detected"
             else if (avg_lag_months > 1) "Lag > 1 month"
             else "OK"
  )
}

#' Stability score (feature/regime-weight rolling 36M)
#'
#' @param weight_history data.frame/matrix rolling weights
#' @param window_months integer (default 36)
stability_score_check <- function(weight_history, window_months = 36) {
  if (is.data.frame(weight_history)) weight_history <- as.matrix(weight_history)

  n <- nrow(weight_history)
  if (n < window_months) {
    return(list(ok = FALSE,
                reason = sprintf("insufficient obs (%d < %d)", n, window_months)))
  }

  # Rolling stability: 1 - mean(sd(weight) / mean(weight))
  # Higher = more stable
  col_stabilities <- apply(weight_history, 2, function(col) {
    rolling_sds <- sapply(window_months:n, function(i) {
      sd(col[(i - window_months + 1):i], na.rm = TRUE)
    })
    rolling_means <- sapply(window_months:n, function(i) {
      mean(col[(i - window_months + 1):i], na.rm = TRUE)
    })
    cv <- rolling_sds / abs(rolling_means + 0.0001)
    1 - mean(cv, na.rm = TRUE)
  })

  overall_stability <- mean(col_stabilities, na.rm = TRUE)

  list(
    col_stabilities = round(col_stabilities, 3),
    overall_stability = round(overall_stability, 3),
    threshold_min = 0.60,
    passed = !is.na(overall_stability) && overall_stability >= 0.60
  )
}

#' Regime Adaptive Overall Check (Admission Rule v3.5.2 Gate 7 regime_adaptive)
regime_adaptive_assess <- function(returns, regime_series,
                                     weights_history = NULL,
                                     signal_dates = NULL, execution_dates = NULL) {
  result <- list()

  result$switching_alpha <- switching_alpha_check(returns, regime_series)

  if (!is.null(weights_history)) {
    result$transition_cost <- transition_cost_check(weights_history)
    result$stability <- stability_score_check(weights_history)
  }

  if (!is.null(signal_dates) && !is.null(execution_dates)) {
    result$signal_lag <- signal_lag_check(signal_dates, execution_dates)
  }

  # Overall
  checks <- sapply(result, function(x) isTRUE(x$passed))
  result$overall_passed <- all(checks, na.rm = TRUE)
  result$admission_gate_7_regime <- if (result$overall_passed) "PASS"
                                     else "CONDITIONAL_PASS (재측정 요구)"
  result
}

cat("[regime_switching_cost] Loaded. Functions: switching_alpha_check, transition_cost_check, signal_lag_check, stability_score_check, regime_adaptive_assess\n")
