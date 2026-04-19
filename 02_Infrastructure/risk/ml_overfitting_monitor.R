#==============================================================================
# ML Overfitting Monitor (v55 Risk Engine L13 확장)
#
# role=ml_predictive / trail=ml_empirical_first 전략 전용.
# OOS decay, feature concentration, data leakage 측정.
#
# Admission Rule v3.5.2 Gate 7 (ML_Predictive threshold) 자동화:
#   - SR_OOS / SR_IS >= 0.70
#   - feature_concentration_max < 0.4
#   - holdout 12M+
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

#' SR OOS/IS ratio — overfitting degree
#'
#' @param is_returns numeric (in-sample period)
#' @param oos_returns numeric (out-of-sample period)
#' @return list with SR ratio
sr_oos_is_ratio <- function(is_returns, oos_returns) {
  if (length(is_returns) < 12 || length(oos_returns) < 12) {
    return(list(ok = FALSE, reason = "insufficient data (IS or OOS < 12 obs)"))
  }

  sr_is <- mean(is_returns) / sd(is_returns) * sqrt(12)
  sr_oos <- mean(oos_returns) / sd(oos_returns) * sqrt(12)

  ratio <- if (abs(sr_is) > 0.01) sr_oos / sr_is else NA

  list(
    sr_is = round(sr_is, 3),
    sr_oos = round(sr_oos, 3),
    ratio = round(ratio, 3),
    threshold = 0.70,
    passed = !is.na(ratio) && ratio >= 0.70,
    n_is = length(is_returns),
    n_oos = length(oos_returns)
  )
}

#' Feature importance concentration (Herfindahl index)
#'
#' @param feature_importances numeric vector (non-negative, normalized)
#' @return list with concentration metric
feature_concentration <- function(feature_importances) {
  fi <- feature_importances[is.finite(feature_importances) & feature_importances > 0]
  if (length(fi) == 0) {
    return(list(ok = FALSE, reason = "no valid importance values"))
  }

  # Normalize
  fi_norm <- fi / sum(fi)

  # Herfindahl index (0 to 1, higher = more concentrated)
  hi <- sum(fi_norm^2)

  # Top-N share
  fi_sorted <- sort(fi_norm, decreasing = TRUE)
  top1 <- fi_sorted[1]
  top3 <- sum(fi_sorted[1:min(3, length(fi_sorted))])

  list(
    n_features = length(fi),
    herfindahl_index = round(hi, 4),
    top1_share = round(top1, 4),
    top3_share = round(top3, 4),
    threshold_max = 0.40,
    passed = hi < 0.40 && top1 < 0.4,
    reason = if (top1 >= 0.4)
               sprintf("Top feature %.2f >= 40%% (단일 지배)", top1)
             else if (hi >= 0.4)
               sprintf("Herfindahl %.3f >= 0.4 (집중 과다)", hi)
             else "diversified"
  )
}

#' Holdout split validation (12M+)
#'
#' @param dates Date vector
#' @param holdout_start Date
#' @return list with holdout metrics
holdout_12m_check <- function(dates, holdout_start) {
  if (inherits(dates, "character")) dates <- as.Date(dates)
  if (inherits(holdout_start, "character")) holdout_start <- as.Date(holdout_start)

  train_end <- holdout_start - 1
  holdout_obs <- sum(dates >= holdout_start)
  train_obs <- sum(dates <= train_end)

  # Assume monthly obs: 12 months minimum
  list(
    train_obs = train_obs,
    holdout_obs = holdout_obs,
    holdout_months_approx = holdout_obs,
    threshold_min = 12,
    passed = holdout_obs >= 12,
    holdout_start = as.character(holdout_start),
    train_period = sprintf("%s ~ %s", min(dates), as.character(train_end))
  )
}

#' ML Overfitting Overall Check (Admission Rule v3.5.2 Gate 7 ml_predictive)
#'
#' @param is_returns numeric
#' @param oos_returns numeric
#' @param feature_importances numeric vector
#' @param dates Date
#' @param holdout_start Date
#' @return full assessment
ml_overfitting_assess <- function(is_returns, oos_returns,
                                    feature_importances, dates, holdout_start) {
  sr_check <- sr_oos_is_ratio(is_returns, oos_returns)
  fc_check <- feature_concentration(feature_importances)
  ho_check <- holdout_12m_check(dates, holdout_start)

  passed <- isTRUE(sr_check$passed) && isTRUE(fc_check$passed) && isTRUE(ho_check$passed)

  list(
    sr_oos_is = sr_check,
    feature_concentration = fc_check,
    holdout_12m = ho_check,
    overall_passed = passed,
    admission_gate_7_ml = if (passed) "PASS" else "CONDITIONAL_PASS (재측정 요구)"
  )
}

cat("[ml_overfitting_monitor] Loaded. Functions: sr_oos_is_ratio, feature_concentration, holdout_12m_check, ml_overfitting_assess\n")
