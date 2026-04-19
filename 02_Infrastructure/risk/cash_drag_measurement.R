#==============================================================================
# Cash Drag Measurement (v55 Risk Engine L13 확장)
#
# role=cash_allocation sleeve의 opportunity cost / drag 측정.
# Cash는 tail risk 0이지만, equity 대비 기회비용이 존재.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

#' Measure cash drag (opportunity cost vs equity)
#'
#' @param cash_weights numeric (0-1) monthly cash allocation
#' @param equity_returns numeric (monthly)
#' @param rf_rates numeric (monthly 3M rate) or single value
#' @param regime_series character (optional, regime tagging)
#' @return list with drag metrics
measure_cash_drag <- function(cash_weights, equity_returns, rf_rates,
                               regime_series = NULL) {

  n <- length(cash_weights)
  if (length(equity_returns) != n) stop("length mismatch")

  if (length(rf_rates) == 1) rf_rates <- rep(rf_rates, n)

  # Per-period cash drag = cash_w * (equity_ret - rf_rate)
  # Positive drag means equity outperformed -> cash cost
  per_period_drag <- cash_weights * (equity_returns - rf_rates)

  # Annualize
  total_drag_ann <- sum(per_period_drag) / (n / 12)
  avg_drag_bps_ann <- mean(per_period_drag) * 12 * 10000

  result <- list(
    n_obs = n,
    avg_cash_pct = round(mean(cash_weights) * 100, 2),
    max_cash_pct = round(max(cash_weights) * 100, 2),
    total_drag_annualized = round(total_drag_ann, 4),
    avg_drag_bps_annualized = round(avg_drag_bps_ann, 2),
    threshold_20bps_check = avg_drag_bps_ann < 20
  )

  # Regime-conditional drag (optional)
  if (!is.null(regime_series) && length(regime_series) == n) {
    regime_drag <- tapply(per_period_drag, regime_series,
                          function(x) round(mean(x) * 12 * 10000, 2))
    result$drag_by_regime_bps_ann <- as.list(regime_drag)
  }

  # Negative drag interpretation: cash protected during equity drawdown
  result$protective_months <- sum(per_period_drag < 0)
  result$protective_pct <- round(100 * result$protective_months / n, 2)

  result
}

#' Crisis period cash benefit (AX-001 v2 alignment)
#'
#' Measure cash's crisis-period out-performance vs equity
cash_crisis_benefit <- function(cash_weights, equity_returns, rf_rates, dates,
                                  crisis_periods) {
  results <- lapply(names(crisis_periods), function(name) {
    period <- crisis_periods[[name]]
    mask <- dates >= period[1] & dates <= period[2]
    if (sum(mask) == 0) return(list(name = name, benefit = NA))

    cw <- cash_weights[mask]
    er <- equity_returns[mask]
    rf <- if (length(rf_rates) == 1) rep(rf_rates, sum(mask)) else rf_rates[mask]

    # Cash benefit during crisis = cash_w * (rf - equity_ret) when equity_ret < rf
    crisis_benefit <- mean(cw * (rf - er)) * 12 * 10000  # bps/yr equivalent

    list(
      name = name, period = period,
      n_obs = sum(mask),
      avg_cash = round(mean(cw), 3),
      avg_equity_ret = round(mean(er) * 12, 4),
      cash_benefit_bps_ann = round(crisis_benefit, 2),
      benefit_positive = crisis_benefit > 0
    )
  })

  names(results) <- names(crisis_periods)
  results
}

cat("[cash_drag_measurement] Loaded. Functions: measure_cash_drag, cash_crisis_benefit\n")
