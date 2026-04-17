#==============================================================================
# V7 Research Engine — Antipattern Detector
# antipattern_detector.R
#
# Detects 13 structural antipatterns in strategy candidates before portfolio
# admission. Each check is a self-contained function returning a standardized
# result. The main function aggregates all checks and returns pass/fail with
# severity.
#
# Usage:
#   source("02_Infrastructure/antipattern_detector.R")
#   result <- sg_detect_antipatterns(
#     candidate_id, portfolio_state, s2, s3, s4, s6
#   )
#   # result$pass             — TRUE if no critical patterns
#   # result$severity         — "none" / "warning" / "critical"
#   # result$patterns_detected — character vector of triggered pattern names
#   # result$details          — list of per-check detail objects
#
# Dependencies: data.table, jsonlite
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

# ─── Constants ───────────────────────────────────────────────────────────────
.AP_CORR_CROWDED_THRESH     <- 0.70
.AP_CORR_CLUSTER_SIZE       <- 3L
.AP_CORR_DIVERSIFIER_THRESH <- 0.50
.AP_OOS_RETENTION_MIN       <- 0.50
.AP_MDD_AMPLIFY_PP          <- 3.0
.AP_TURNOVER_MAX_PCT        <- 400.0
.AP_IC_DECAY_RATIO          <- 0.50
.AP_FAMILY_SATURATION_MAX   <- 3L
.AP_GHOST_ALPHA_TC_BPS      <- 30
.AP_MIN_DATA_YEARS          <- 5
.AP_COVERAGE_JUMP_THRESH    <- 0.20
.AP_COMPLEXITY_TIER_THRESH  <- 2L

# ─── Helper: standardized check result ────────────────────────────────────────
.ap_result <- function(detected = FALSE, severity = "none", detail = "") {
  list(detected = detected, severity = severity, detail = detail)
}

#==============================================================================
# 1. Crowded Factor — max absolute correlation > 0.7 with 2+ existing sleeves
#==============================================================================
.ap_crowded_factor <- function(s3, portfolio_state) {
  if (is.null(s3) || is.null(s3$correlation_matrix) || is.null(portfolio_state$current_sleeves)) {
    return(.ap_result())
  }

  corr_mat <- s3$correlation_matrix
  existing <- portfolio_state$current_sleeves

  if (length(existing) < 2) return(.ap_result())

  # Extract correlations of candidate with existing sleeves
  high_corr_count <- 0L
  high_corr_names <- character(0)

  for (sleeve in existing) {
    if (sleeve %in% names(corr_mat)) {
      abs_corr <- abs(as.numeric(corr_mat[[sleeve]]))
      if (!is.na(abs_corr) && abs_corr > .AP_CORR_CROWDED_THRESH) {
        high_corr_count <- high_corr_count + 1L
        high_corr_names <- c(high_corr_names, sleeve)
      }
    }
  }

  if (high_corr_count >= 2L) {
    return(.ap_result(
      detected = TRUE,
      severity = "critical",
      detail = sprintf(
        "Crowded factor: |corr| > %.2f with %d sleeves (%s)",
        .AP_CORR_CROWDED_THRESH, high_corr_count,
        paste(high_corr_names, collapse = ", ")
      )
    ))
  }
  .ap_result()
}

#==============================================================================
# 2. Role Masquerade — core claiming diversifier or vice versa
#==============================================================================
.ap_role_masquerade <- function(s4, validated_role) {
  if (is.null(s4) || is.null(validated_role)) return(.ap_result())

  declared <- tolower(as.character(s4$assigned_role %||% s4$role %||% ""))
  actual   <- tolower(as.character(validated_role))

  if (nchar(declared) == 0 || nchar(actual) == 0) return(.ap_result())

  if (declared != actual) {
    return(.ap_result(
      detected = TRUE,
      severity = "critical",
      detail = sprintf(
        "Role masquerade: declared '%s' but validated as '%s'",
        declared, actual
      )
    ))
  }
  .ap_result()
}

#==============================================================================
# 3. Complexity Inflation — method tier > 2 without OOS improvement
#==============================================================================
.ap_complexity_inflation <- function(s4) {
  if (is.null(s4)) return(.ap_result())

  tier <- as.integer(s4$method_tier %||% s4$complexity_tier %||% 1L)
  oos_improvement <- as.numeric(s4$oos_improvement %||% s4$delta_sharpe_oos %||% NA_real_)

  if (is.na(tier) || tier <= .AP_COMPLEXITY_TIER_THRESH) return(.ap_result())

  # High complexity: demand OOS improvement over simpler baseline
  baseline_sr <- as.numeric(s4$baseline_sharpe %||% 0)
  oos_sr      <- as.numeric(s4$oos_sharpe %||% s4$sharpe_oos %||% 0)

  if (!is.na(oos_improvement) && oos_improvement <= 0) {
    return(.ap_result(
      detected = TRUE,
      severity = "warning",
      detail = sprintf(
        "Complexity inflation: tier %d but OOS improvement = %.3f (no gain over baseline)",
        tier, oos_improvement
      )
    ))
  }

  if (is.na(oos_improvement) && oos_sr <= baseline_sr) {
    return(.ap_result(
      detected = TRUE,
      severity = "warning",
      detail = sprintf(
        "Complexity inflation: tier %d, OOS SR (%.3f) <= baseline SR (%.3f)",
        tier, oos_sr, baseline_sr
      )
    ))
  }

  .ap_result()
}

#==============================================================================
# 4. Regime Tunnel — alpha only in 1 regime
#==============================================================================
.ap_regime_tunnel <- function(s6) {
  if (is.null(s6) || is.null(s6$stress_results) && is.null(s6$regime_sharpes)) {
    return(.ap_result())
  }

  regime_sharpes <- s6$regime_sharpes %||% s6$stress_results$regime_sharpes
  if (is.null(regime_sharpes) || length(regime_sharpes) < 2) return(.ap_result())

  # Count regimes with positive Sharpe
  positive_regimes <- sum(sapply(regime_sharpes, function(x) {
    val <- as.numeric(x)
    !is.na(val) && val > 0
  }))

  if (positive_regimes <= 1L) {
    regime_names <- paste(names(regime_sharpes), "=",
                          round(as.numeric(regime_sharpes), 3),
                          collapse = ", ")
    return(.ap_result(
      detected = TRUE,
      severity = "critical",
      detail = sprintf(
        "Regime tunnel: positive alpha in only %d regime(s). [%s]",
        positive_regimes, regime_names
      )
    ))
  }
  .ap_result()
}

#==============================================================================
# 5. OOS Collapse — OOS retention < 0.5
#==============================================================================
.ap_oos_collapse <- function(s6) {
  if (is.null(s6)) return(.ap_result())

  is_sr  <- as.numeric(s6$sharpe_is %||% s6$in_sample_sharpe %||% NA_real_)
  oos_sr <- as.numeric(s6$sharpe_oos %||% s6$out_of_sample_sharpe %||% NA_real_)

  if (is.na(is_sr) || is.na(oos_sr) || is_sr <= 0) return(.ap_result())

  retention <- oos_sr / is_sr

  if (retention < .AP_OOS_RETENTION_MIN) {
    return(.ap_result(
      detected = TRUE,
      severity = "critical",
      detail = sprintf(
        "OOS collapse: retention = %.2f (IS SR %.3f → OOS SR %.3f). Threshold = %.2f",
        retention, is_sr, oos_sr, .AP_OOS_RETENTION_MIN
      )
    ))
  }
  .ap_result()
}

#==============================================================================
# 6. MDD Amplifier — candidate increases portfolio MDD > 3pp
#==============================================================================
.ap_mdd_amplifier <- function(s4, portfolio_state) {
  if (is.null(s4) || is.null(portfolio_state)) return(.ap_result())

  candidate_mdd <- abs(as.numeric(s4$mdd %||% s4$max_drawdown %||% NA_real_))
  portfolio_mdd <- abs(as.numeric(portfolio_state$current_mdd %||% NA_real_))

  if (is.na(candidate_mdd) || is.na(portfolio_mdd)) return(.ap_result())

  # Simulated portfolio MDD impact (conservative heuristic: weighted average

  # with bump if high drawdown correlation is expected)
  projected_mdd <- as.numeric(s4$projected_portfolio_mdd %||% NA_real_)

  if (!is.na(projected_mdd)) {
    delta_mdd <- (projected_mdd - portfolio_mdd) * 100  # convert to pp
    if (delta_mdd > .AP_MDD_AMPLIFY_PP) {
      return(.ap_result(
        detected = TRUE,
        severity = "warning",
        detail = sprintf(
          "MDD amplifier: projected portfolio MDD %.1f%% → %.1f%% (+%.1fpp > %.1fpp threshold)",
          portfolio_mdd * 100, projected_mdd * 100, delta_mdd, .AP_MDD_AMPLIFY_PP
        )
      ))
    }
  } else {
    # Fallback: simple rule — if candidate MDD > portfolio MDD + 3pp
    if ((candidate_mdd - portfolio_mdd) * 100 > .AP_MDD_AMPLIFY_PP * 2) {
      return(.ap_result(
        detected = TRUE,
        severity = "warning",
        detail = sprintf(
          "MDD amplifier (heuristic): candidate MDD %.1f%% far exceeds portfolio %.1f%%",
          candidate_mdd * 100, portfolio_mdd * 100
        )
      ))
    }
  }
  .ap_result()
}

#==============================================================================
# 7. Turnover Bomb — annualized turnover > 400%
#==============================================================================
.ap_turnover_bomb <- function(s2) {
  if (is.null(s2)) return(.ap_result())

  turnover <- as.numeric(s2$annualized_turnover %||% s2$turnover_annual %||%
                           s2$turnover %||% NA_real_)

  if (is.na(turnover)) return(.ap_result())

  # Normalize: if reported as decimal (e.g. 4.0 = 400%), convert
  turnover_pct <- if (turnover <= 10) turnover * 100 else turnover

  if (turnover_pct > .AP_TURNOVER_MAX_PCT) {
    return(.ap_result(
      detected = TRUE,
      severity = "warning",
      detail = sprintf(
        "Turnover bomb: %.0f%% annualized (threshold = %.0f%%)",
        turnover_pct, .AP_TURNOVER_MAX_PCT
      )
    ))
  }
  .ap_result()
}

#==============================================================================
# 8. Correlation Cluster — forms 3+ correlated group
#==============================================================================
.ap_correlation_cluster <- function(s3, portfolio_state) {
  if (is.null(s3) || is.null(s3$correlation_matrix) || is.null(portfolio_state$current_sleeves)) {
    return(.ap_result())
  }

  corr_mat <- s3$correlation_matrix
  existing <- portfolio_state$current_sleeves

  if (length(existing) < 2) return(.ap_result())

  # Find all sleeves correlated with candidate above threshold (0.5)
  correlated_sleeves <- character(0)
  for (sleeve in existing) {
    if (sleeve %in% names(corr_mat)) {
      abs_corr <- abs(as.numeric(corr_mat[[sleeve]]))
      if (!is.na(abs_corr) && abs_corr > .AP_CORR_DIVERSIFIER_THRESH) {
        correlated_sleeves <- c(correlated_sleeves, sleeve)
      }
    }
  }

  # Check if these correlated sleeves also correlate with each other
  # forming a cluster
  if (length(correlated_sleeves) >= (.AP_CORR_CLUSTER_SIZE - 1L)) {
    # Candidate + correlated_sleeves form a cluster of size >= 3
    cluster_size <- length(correlated_sleeves) + 1L  # +1 for candidate
    return(.ap_result(
      detected = TRUE,
      severity = "warning",
      detail = sprintf(
        "Correlation cluster: candidate + %d sleeves form correlated group of %d (>= %d). Members: %s",
        length(correlated_sleeves), cluster_size, .AP_CORR_CLUSTER_SIZE,
        paste(correlated_sleeves, collapse = ", ")
      )
    ))
  }
  .ap_result()
}

#==============================================================================
# 9. Data Vintage Mismatch — data period too short
#==============================================================================
.ap_data_vintage_mismatch <- function(s1, portfolio_state) {
  if (is.null(s1)) return(.ap_result())

  # Check candidate data span
  data_start <- as.Date(s1$data_start %||% s1$start_date %||% NA_character_)
  data_end   <- as.Date(s1$data_end %||% s1$end_date %||% NA_character_)

  if (is.na(data_start) || is.na(data_end)) return(.ap_result())

  data_years <- as.numeric(difftime(data_end, data_start, units = "days")) / 365.25

  if (data_years < .AP_MIN_DATA_YEARS) {
    return(.ap_result(
      detected = TRUE,
      severity = "critical",
      detail = sprintf(
        "Data vintage mismatch: only %.1f years of data (minimum = %d years). Period: %s to %s",
        data_years, .AP_MIN_DATA_YEARS, data_start, data_end
      )
    ))
  }

  # Also check if significantly shorter than portfolio average
  if (!is.null(portfolio_state$avg_data_years)) {
    avg_years <- as.numeric(portfolio_state$avg_data_years)
    if (data_years < avg_years * 0.6) {
      return(.ap_result(
        detected = TRUE,
        severity = "warning",
        detail = sprintf(
          "Data vintage mismatch: %.1f years vs portfolio avg %.1f years (< 60%%)",
          data_years, avg_years
        )
      ))
    }
  }
  .ap_result()
}

#==============================================================================
# 10. IC Decay Spiral — recent 1Y IC < 50% of full sample IC
#==============================================================================
.ap_ic_decay_spiral <- function(s2, s6) {
  if (is.null(s2) && is.null(s6)) return(.ap_result())

  full_ic   <- as.numeric(s2$ic_mean %||% s2$full_sample_ic %||% NA_real_)
  recent_ic <- as.numeric(s6$recent_1y_ic %||% s6$ic_last_12m %||%
                            s2$ic_recent_1y %||% NA_real_)

  if (is.na(full_ic) || is.na(recent_ic) || full_ic <= 0) return(.ap_result())

  ratio <- recent_ic / full_ic

  if (ratio < .AP_IC_DECAY_RATIO) {
    return(.ap_result(
      detected = TRUE,
      severity = "warning",
      detail = sprintf(
        "IC decay spiral: recent 1Y IC (%.4f) = %.0f%% of full-sample IC (%.4f). Threshold = %.0f%%",
        recent_ic, ratio * 100, full_ic, .AP_IC_DECAY_RATIO * 100
      )
    ))
  }
  .ap_result()
}

#==============================================================================
# 11. Family Saturation — same family 3+ already in portfolio
#==============================================================================
.ap_family_saturation <- function(s3, portfolio_state) {
  if (is.null(s3) || is.null(portfolio_state$family_counts)) return(.ap_result())

  candidate_family <- tolower(as.character(
    s3$family %||% s3$factor_family %||% ""
  ))

  if (nchar(candidate_family) == 0) return(.ap_result())

  family_counts <- portfolio_state$family_counts
  current_count <- as.integer(family_counts[[candidate_family]] %||% 0L)

  if (current_count >= .AP_FAMILY_SATURATION_MAX) {
    return(.ap_result(
      detected = TRUE,
      severity = "warning",
      detail = sprintf(
        "Family saturation: family '%s' already has %d sleeves in portfolio (max = %d)",
        candidate_family, current_count, .AP_FAMILY_SATURATION_MAX
      )
    ))
  }
  .ap_result()
}

#==============================================================================
# 12. Survivorship Leak — coverage increases suspiciously over time
#==============================================================================
.ap_survivorship_leak <- function(s1) {
  if (is.null(s1)) return(.ap_result())

  # Check if coverage ratio increases monotonically
  coverage_ts <- s1$coverage_timeseries %||% s1$coverage_by_year
  if (is.null(coverage_ts) || length(coverage_ts) < 3) return(.ap_result())

  cov_vals <- as.numeric(coverage_ts)
  cov_vals <- cov_vals[!is.na(cov_vals)]
  if (length(cov_vals) < 3) return(.ap_result())

  # Check if early-period coverage is suspiciously higher than expected
  # (should start low and grow with market development)
  n <- length(cov_vals)
  early_mean <- mean(cov_vals[1:min(3, n)])
  late_mean  <- mean(cov_vals[max(1, n - 2):n])

  # Suspiciously flat or early-high coverage suggests survivorship bias
  if (early_mean > 0 && late_mean > 0) {
    # If early coverage > 80% of late coverage — suspicious
    if (early_mean / late_mean > (1 - .AP_COVERAGE_JUMP_THRESH)) {
      return(.ap_result())  # Actually looks stable, not suspicious
    }

    # Large jump from early to late: normal market development
    # But check for mid-period dip then jump — that's suspicious
    mid_mean <- mean(cov_vals[max(1, floor(n/3)):min(n, ceiling(2*n/3))])
    if (mid_mean < early_mean * 0.8 && late_mean > early_mean * 1.2) {
      return(.ap_result(
        detected = TRUE,
        severity = "warning",
        detail = sprintf(
          "Survivorship leak: coverage pattern suspicious (early=%.2f, mid=%.2f, late=%.2f). Possible delisted stock exclusion.",
          early_mean, mid_mean, late_mean
        )
      ))
    }
  }
  .ap_result()
}

#==============================================================================
# 13. Ghost Alpha — alpha disappears at 30bps transaction cost
#==============================================================================
.ap_ghost_alpha <- function(s6) {
  if (is.null(s6)) return(.ap_result())

  sr_base <- as.numeric(s6$sharpe_base %||% s6$sharpe_15bps %||% s6$sharpe %||% NA_real_)
  sr_30bps <- as.numeric(s6$sharpe_30bps %||% s6$sharpe_high_tc %||% NA_real_)

  if (is.na(sr_base) || is.na(sr_30bps)) {
    # Try to compute from CAGR / volatility if available
    cagr_30 <- as.numeric(s6$cagr_30bps %||% NA_real_)
    vol     <- as.numeric(s6$volatility %||% s6$vol %||% NA_real_)
    rf      <- 0.03  # conservative risk-free
    if (!is.na(cagr_30) && !is.na(vol) && vol > 0) {
      sr_30bps <- (cagr_30 - rf) / vol
    }
  }

  if (is.na(sr_base) || is.na(sr_30bps)) return(.ap_result())

  if (sr_30bps <= 0) {
    return(.ap_result(
      detected = TRUE,
      severity = "critical",
      detail = sprintf(
        "Ghost alpha: SR at %dbps TC = %.3f (base SR = %.3f). Alpha vanishes under realistic costs.",
        .AP_GHOST_ALPHA_TC_BPS, sr_30bps, sr_base
      )
    ))
  }
  .ap_result()
}

#==============================================================================
# Main Aggregator: sg_detect_antipatterns()
#==============================================================================

#' Detect antipatterns in a strategy candidate
#'
#' Runs 13 internal checks against a candidate strategy, its stage artifacts,
#' and the current portfolio state.
#'
#' @param candidate_id Character. Strategy identifier (e.g. "STR_1435")
#' @param portfolio_state List with: current_sleeves (character vector),
#'   grade_a_pool (character vector), family_counts (named list),
#'   current_mdd (numeric), avg_data_years (numeric, optional)
#' @param s1 List. S1 (construction) stage artifact. Can be NULL.
#' @param s2 List. S2 (profile) stage artifact
#' @param s3 List. S3 (orthogonality) stage artifact
#' @param s4 List. S4 (integration) stage artifact
#' @param s6 List. S6 (validation) stage artifact
#' @return List with: patterns_detected (character), severity ("none"/"warning"/"critical"),
#'   pass (logical), details (list of check results)
sg_detect_antipatterns <- function(candidate_id,
                                   portfolio_state = list(),
                                   s1 = NULL,
                                   s2 = NULL,
                                   s3 = NULL,
                                   s4 = NULL,
                                   s6 = NULL) {

  cat(sprintf("[antipattern_detector] Scanning %s for antipatterns...\n", candidate_id))

  # Derive validated_role from s4 if available

  validated_role <- s4$validated_role %||% s4$detected_role %||% s4$assigned_role %||% NULL

  # Run all 13 checks
  checks <- list(
    crowded_factor      = tryCatch(.ap_crowded_factor(s3, portfolio_state),
                                   error = function(e) .ap_result(detail = paste("ERROR:", e$message))),
    role_masquerade     = tryCatch(.ap_role_masquerade(s4, validated_role),
                                   error = function(e) .ap_result(detail = paste("ERROR:", e$message))),
    complexity_inflation = tryCatch(.ap_complexity_inflation(s4),
                                    error = function(e) .ap_result(detail = paste("ERROR:", e$message))),
    regime_tunnel       = tryCatch(.ap_regime_tunnel(s6),
                                   error = function(e) .ap_result(detail = paste("ERROR:", e$message))),
    oos_collapse        = tryCatch(.ap_oos_collapse(s6),
                                   error = function(e) .ap_result(detail = paste("ERROR:", e$message))),
    mdd_amplifier       = tryCatch(.ap_mdd_amplifier(s4, portfolio_state),
                                   error = function(e) .ap_result(detail = paste("ERROR:", e$message))),
    turnover_bomb       = tryCatch(.ap_turnover_bomb(s2),
                                   error = function(e) .ap_result(detail = paste("ERROR:", e$message))),
    correlation_cluster = tryCatch(.ap_correlation_cluster(s3, portfolio_state),
                                   error = function(e) .ap_result(detail = paste("ERROR:", e$message))),
    data_vintage_mismatch = tryCatch(.ap_data_vintage_mismatch(s1, portfolio_state),
                                     error = function(e) .ap_result(detail = paste("ERROR:", e$message))),
    ic_decay_spiral     = tryCatch(.ap_ic_decay_spiral(s2, s6),
                                   error = function(e) .ap_result(detail = paste("ERROR:", e$message))),
    family_saturation   = tryCatch(.ap_family_saturation(s3, portfolio_state),
                                   error = function(e) .ap_result(detail = paste("ERROR:", e$message))),
    survivorship_leak   = tryCatch(.ap_survivorship_leak(s1),
                                   error = function(e) .ap_result(detail = paste("ERROR:", e$message))),
    ghost_alpha         = tryCatch(.ap_ghost_alpha(s6),
                                   error = function(e) .ap_result(detail = paste("ERROR:", e$message)))
  )

  # Aggregate results
  detected_names <- character(0)
  severities     <- character(0)


  for (nm in names(checks)) {
    chk <- checks[[nm]]
    if (isTRUE(chk$detected)) {
      detected_names <- c(detected_names, nm)
      severities     <- c(severities, chk$severity)
    }
  }

  # Determine overall severity
  if (length(severities) == 0) {
    overall_severity <- "none"
  } else if ("critical" %in% severities) {
    overall_severity <- "critical"
  } else {
    overall_severity <- "warning"
  }

  pass <- overall_severity != "critical"

  cat(sprintf(
    "[antipattern_detector] %s: %d pattern(s) detected, severity=%s, pass=%s\n",
    candidate_id, length(detected_names), overall_severity, pass
  ))

  if (length(detected_names) > 0) {
    for (nm in detected_names) {
      cat(sprintf("  [%s] %s — %s\n",
                  checks[[nm]]$severity, nm, checks[[nm]]$detail))
    }
  }

  list(
    candidate_id      = candidate_id,
    patterns_detected = detected_names,
    severity          = overall_severity,
    pass              = pass,
    n_checks          = length(checks),
    n_detected        = length(detected_names),
    n_critical        = sum(severities == "critical"),
    n_warning         = sum(severities == "warning"),
    details           = checks
  )
}

cat("[antipattern_detector] Loaded — 13 antipattern checks available.\n")
