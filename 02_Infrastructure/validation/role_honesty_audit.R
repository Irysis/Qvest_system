#==============================================================================
# V7 Research Engine — Role Honesty Audit
# role_honesty_audit.R
#
# Detects role masquerade: strategies declaring one role (core_alpha,
# diversifier, defense) but exhibiting metrics consistent with a different
# role. Enforced at S6 by Judge as per V6 Stage Gate rules.
#
# Usage:
#   source("02_Infrastructure/role_honesty_audit.R")
#   result <- sg_audit_role_honesty("STR_1435", "diversifier", s2, s3, s4)
#   # result$honest         — TRUE if declared role matches detected role
#   # result$declared_role  — what the strategy claims
#   # result$detected_role  — what the metrics suggest
#   # result$confidence     — 0~1 confidence in detection
#   # result$violations     — character vector of specific mismatches
#
# Dependencies: data.table
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

# ─── Role Detection Thresholds ───────────────────────────────────────────────
.RH_CORE_DELTA_SR_MIN       <- 0.0     # Core must improve portfolio Sharpe
.RH_CORE_KOSPI_BEAT         <- TRUE    # Core must beat KOSPI
.RH_CORE_OOS_POSITIVE       <- TRUE    # Core must have positive OOS alpha
.RH_DIVERSIFIER_MAX_CORR    <- 0.50    # Diversifier max abs corr with portfolio
.RH_DIVERSIFIER_BENEFIT_MIN <- 0.0     # Must provide diversification benefit
.RH_DEFENSE_STRESS_OUTPERF  <- 0.0     # Must outperform in stress periods
.RH_CORE_CLAIMING_DIV_SR    <- 0.20    # Core disguised as diversifier threshold
.RH_DIV_CLAIMING_CORE_CORR  <- 0.50    # Diversifier disguised as core threshold

#==============================================================================
# Internal: check if metrics match Core Alpha role
#==============================================================================
.rh_check_core <- function(s2, s3, s4, stress_data) {
  evidence_for  <- character(0)
  evidence_against <- character(0)
  score <- 0.0

  # Delta Sharpe > 0 (portfolio improvement)
  delta_sr <- as.numeric(s4$delta_sharpe %||% s4$delta_sr %||% NA_real_)
  if (!is.na(delta_sr)) {
    if (delta_sr > .RH_CORE_DELTA_SR_MIN) {
      evidence_for <- c(evidence_for,
        sprintf("delta_sharpe=%.3f > 0 (improves portfolio)", delta_sr))
      score <- score + 0.3
    } else {
      evidence_against <- c(evidence_against,
        sprintf("delta_sharpe=%.3f <= 0 (does not improve portfolio)", delta_sr))
    }
  }

  # KOSPI beat
  kospi_beat <- as.logical(s4$kospi_beat %||% s2$kospi_beat %||% NA)
  if (!is.na(kospi_beat)) {
    if (kospi_beat) {
      evidence_for <- c(evidence_for, "Beats KOSPI benchmark")
      score <- score + 0.25
    } else {
      evidence_against <- c(evidence_against, "Does not beat KOSPI")
    }
  }

  # OOS positive
  oos_sr <- as.numeric(s4$oos_sharpe %||% s2$sharpe_oos %||% NA_real_)
  if (!is.na(oos_sr)) {
    if (oos_sr > 0) {
      evidence_for <- c(evidence_for,
        sprintf("OOS Sharpe=%.3f > 0", oos_sr))
      score <- score + 0.25
    } else {
      evidence_against <- c(evidence_against,
        sprintf("OOS Sharpe=%.3f <= 0", oos_sr))
    }
  }

  # High absolute Sharpe is core evidence
  full_sr <- as.numeric(s2$sharpe %||% s2$full_sharpe %||% NA_real_)
  if (!is.na(full_sr) && full_sr > 1.0) {
    evidence_for <- c(evidence_for, sprintf("High Sharpe=%.3f (> 1.0)", full_sr))
    score <- score + 0.2
  }

  list(score = min(score, 1.0), evidence_for = evidence_for,
       evidence_against = evidence_against)
}

#==============================================================================
# Internal: check if metrics match Diversifier role
#==============================================================================
.rh_check_diversifier <- function(s2, s3, s4, stress_data) {
  evidence_for <- character(0)
  evidence_against <- character(0)
  score <- 0.0

  # Low correlation with existing portfolio
  max_corr <- as.numeric(s3$max_abs_correlation %||% s3$max_corr %||% NA_real_)
  if (!is.na(max_corr)) {
    if (max_corr < .RH_DIVERSIFIER_MAX_CORR) {
      evidence_for <- c(evidence_for,
        sprintf("Low correlation: max|corr|=%.3f < %.2f", max_corr, .RH_DIVERSIFIER_MAX_CORR))
      score <- score + 0.35
    } else {
      evidence_against <- c(evidence_against,
        sprintf("High correlation: max|corr|=%.3f >= %.2f", max_corr, .RH_DIVERSIFIER_MAX_CORR))
    }
  }

  # Diversification benefit exists
  div_benefit <- as.numeric(s4$diversification_benefit %||%
                              s4$div_benefit %||% s3$diversification_ratio %||% NA_real_)
  if (!is.na(div_benefit)) {
    if (div_benefit > .RH_DIVERSIFIER_BENEFIT_MIN) {
      evidence_for <- c(evidence_for,
        sprintf("Diversification benefit=%.3f > 0", div_benefit))
      score <- score + 0.3
    } else {
      evidence_against <- c(evidence_against,
        sprintf("No diversification benefit (%.3f)", div_benefit))
    }
  }

  # Unique factor family
  family <- as.character(s3$family %||% s3$factor_family %||% "")
  family_unique <- as.logical(s3$family_unique %||% NA)
  if (!is.na(family_unique) && family_unique) {
    evidence_for <- c(evidence_for,
      sprintf("Unique factor family: '%s'", family))
    score <- score + 0.2
  }

  # Moderate (not extreme) standalone Sharpe is typical for diversifiers
  full_sr <- as.numeric(s2$sharpe %||% s2$full_sharpe %||% NA_real_)
  if (!is.na(full_sr) && full_sr > 0 && full_sr < 1.5) {
    evidence_for <- c(evidence_for,
      sprintf("Moderate standalone Sharpe=%.3f (diversifier profile)", full_sr))
    score <- score + 0.15
  }

  list(score = min(score, 1.0), evidence_for = evidence_for,
       evidence_against = evidence_against)
}

#==============================================================================
# Internal: check if metrics match Defense role
#==============================================================================
.rh_check_defense <- function(s2, s3, s4, stress_data) {
  evidence_for <- character(0)
  evidence_against <- character(0)
  score <- 0.0

  # Stress outperformance
  if (!is.null(stress_data)) {
    stress_outperf <- as.numeric(stress_data$conditional_value %||%
                                   stress_data$stress_alpha %||% NA_real_)
    if (!is.na(stress_outperf) && stress_outperf > .RH_DEFENSE_STRESS_OUTPERF) {
      evidence_for <- c(evidence_for,
        sprintf("Stress outperformance=%.3f", stress_outperf))
      score <- score + 0.35
    } else if (!is.na(stress_outperf)) {
      evidence_against <- c(evidence_against,
        sprintf("No stress outperformance (%.3f)", stress_outperf))
    }

    # Crisis beta improvement
    crisis_beta <- as.numeric(stress_data$crisis_beta %||% NA_real_)
    if (!is.na(crisis_beta) && crisis_beta < 0.8) {
      evidence_for <- c(evidence_for,
        sprintf("Low crisis beta=%.3f (defensive)", crisis_beta))
      score <- score + 0.25
    }
  }

  # Negative correlation with market in downturns
  down_corr <- as.numeric(s3$downside_correlation %||%
                            s3$crisis_corr %||% NA_real_)
  if (!is.na(down_corr) && down_corr < 0) {
    evidence_for <- c(evidence_for,
      sprintf("Negative downside correlation=%.3f", down_corr))
    score <- score + 0.2
  }

  # Lower MDD than benchmark
  mdd <- abs(as.numeric(s2$mdd %||% s2$max_drawdown %||% NA_real_))
  if (!is.na(mdd) && mdd < 0.20) {
    evidence_for <- c(evidence_for,
      sprintf("Low MDD=%.1f%% (defensive profile)", mdd * 100))
    score <- score + 0.2
  }

  list(score = min(score, 1.0), evidence_for = evidence_for,
       evidence_against = evidence_against)
}

#==============================================================================
# Main Function: sg_audit_role_honesty()
#==============================================================================

#' Audit role honesty of a strategy candidate
#'
#' Checks whether the declared role (core_alpha / diversifier / defense)
#' matches the strategy's actual metrics. Detects role masquerade.
#'
#' @param strategy_id Character. Strategy identifier
#' @param provisional_role Character. Declared role: "core_alpha", "diversifier", "defense"
#' @param s2 List. S2 (profile) artifact
#' @param s3 List. S3 (orthogonality) artifact
#' @param s4 List. S4 (integration) artifact
#' @param stress_data List. Stress test results (optional)
#' @return List with: honest, declared_role, detected_role, violations, confidence
sg_audit_role_honesty <- function(strategy_id,
                                  provisional_role,
                                  s2 = NULL,
                                  s3 = NULL,
                                  s4 = NULL,
                                  stress_data = NULL) {

  cat(sprintf("[role_honesty] Auditing %s (declared: %s)\n",
              strategy_id, provisional_role))

  provisional_role <- tolower(provisional_role)
  valid_roles <- c("core_alpha", "core", "diversifier", "defense")
  if (!provisional_role %in% valid_roles) {
    warning(sprintf("[role_honesty] Unknown role '%s'. Valid: %s",
                    provisional_role, paste(valid_roles, collapse = ", ")))
  }

  # Normalize role name
  if (provisional_role == "core") provisional_role <- "core_alpha"

  # Score each role
  core_check <- .rh_check_core(s2, s3, s4, stress_data)
  div_check  <- .rh_check_diversifier(s2, s3, s4, stress_data)
  def_check  <- .rh_check_defense(s2, s3, s4, stress_data)

  scores <- c(core_alpha = core_check$score,
              diversifier = div_check$score,
              defense = def_check$score)

  # Determine most likely role
  detected_role <- names(which.max(scores))

  # If scores are very close (within 0.1), it's ambiguous — benefit of the doubt
  sorted_scores <- sort(scores, decreasing = TRUE)
  ambiguous <- (sorted_scores[1] - sorted_scores[2]) < 0.1

  # Compute confidence: how much stronger is the detected role vs alternatives
  confidence <- if (sorted_scores[1] > 0) {
    min(1.0, (sorted_scores[1] - sorted_scores[2]) / sorted_scores[1])
  } else {
    0.0
  }

  # Cross-check violations
  violations <- character(0)

  # --- Core claiming Diversifier ---
  if (provisional_role == "diversifier" && detected_role == "core_alpha") {
    delta_sr <- as.numeric(s4$delta_sharpe %||% 0)
    kospi_beat <- isTRUE(as.logical(s4$kospi_beat %||% FALSE))
    if (delta_sr > .RH_CORE_CLAIMING_DIV_SR && kospi_beat) {
      violations <- c(violations, sprintf(
        "Core masquerading as Diversifier: delta_SR=%.3f + KOSPI beat → actually Core Alpha",
        delta_sr
      ))
    }
  }

  # --- Diversifier claiming Core ---
  if (provisional_role == "core_alpha" && detected_role == "diversifier") {
    max_corr <- as.numeric(s3$max_abs_correlation %||% s3$max_corr %||% NA_real_)
    if (!is.na(max_corr) && max_corr > .RH_DIV_CLAIMING_CORE_CORR) {
      violations <- c(violations, sprintf(
        "Redundant Core: max|corr|=%.3f > %.2f with existing sleeves → actually redundant (not true core)",
        max_corr, .RH_DIV_CLAIMING_CORE_CORR
      ))
    }
  }

  # --- Defense without crisis benefit ---
  if (provisional_role == "defense") {
    if (def_check$score < 0.3) {
      violations <- c(violations,
        "Defense without evidence: stress outperformance and crisis beta checks insufficient")
    }
  }

  # --- Any role with zero evidence ---
  declared_score <- scores[provisional_role]
  if (!is.na(declared_score) && declared_score < 0.15) {
    violations <- c(violations, sprintf(
      "Declared role '%s' has near-zero evidence score (%.2f)",
      provisional_role, declared_score
    ))
  }

  # Final honesty determination
  honest <- (provisional_role == detected_role) || ambiguous
  if (length(violations) > 0) honest <- FALSE

  cat(sprintf("[role_honesty] %s: declared=%s, detected=%s, honest=%s, confidence=%.2f\n",
              strategy_id, provisional_role, detected_role, honest, confidence))
  if (length(violations) > 0) {
    for (v in violations) cat(sprintf("  VIOLATION: %s\n", v))
  }

  list(
    strategy_id   = strategy_id,
    honest        = honest,
    declared_role = provisional_role,
    detected_role = detected_role,
    scores        = as.list(scores),
    confidence    = round(confidence, 3),
    ambiguous     = ambiguous,
    violations    = violations,
    evidence      = list(
      core_alpha  = core_check,
      diversifier = div_check,
      defense     = def_check
    )
  )
}

cat("[role_honesty_audit] Loaded — sg_audit_role_honesty() available.\n")
