#==============================================================================
# Regime-Conditional Factor Allocation Engine
#
# The core brain: takes regime signal + factor IC history + factor momentum,
# produces per-stock composite scores via hierarchical allocation.
#
# Hierarchy:
#   1. Regime (MRS) → regime label (normal/elevated/crisis)
#   2. Factor Momentum (FM) → confidence (high/moderate/low)
#   3. Group weights (IV or EW by confidence)
#   4. Within-group factor weights (ICIR-proportional)
#   5. Composite z-score per stock
#
# Functions:
#   compute_allocation(regime_label, mrs_val, ic_dt, fm_dt, groups, ...)
#   compute_group_weights_iv(ic_history, groups, sig_date)
#   compute_within_group_weights(ic_dt, group_factors)
#   compute_composite_score(factor_dt, factor_weights)
#   get_regime_label(mrs_val, mrs_history)
#
# PIT: All weights use expanding-window IC/ICIR only.
#==============================================================================

suppressPackageStartupMessages(library(data.table))


#==============================================================================
# 1. get_regime_label() — MRS → 3-state classification
#==============================================================================

#' Classify MRS value into regime label using expanding percentiles.
#' PIT: Uses only MRS history up to sig_date.
#'
#' @param mrs_val Numeric. Current MRS (0-100)
#' @param mrs_history Numeric vector. MRS values up to (but not including) sig_date
#' @return Character: "normal" / "elevated" / "crisis"
get_regime_label <- function(mrs_val, mrs_history) {
  if (length(mrs_history) < 12) return("normal")

  p60 <- quantile(mrs_history, 0.60, na.rm = TRUE)
  p80 <- quantile(mrs_history, 0.80, na.rm = TRUE)

  if (mrs_val < p60) "normal"
  else if (mrs_val < p80) "elevated"
  else "crisis"
}


#==============================================================================
# 2. compute_group_weights_iv() — IV weighting across factor groups
#==============================================================================

#' Compute group weights via inverse-variance of group IC series.
#' Groups with more stable positive IC get higher weight.
#'
#' @param ic_history data.table with Date, Factor_Name, IC
#' @param groups Named list (family -> factor names)
#' @param sig_date Date. Current signal date (for expanding window cutoff)
#' @param min_months Integer. Min months for valid IV (default 24)
#' @return Named numeric vector (family -> weight, sums to 1)
compute_group_weights_iv <- function(ic_history, groups, sig_date,
                                     min_months = 24L) {
  sig_d <- as.Date(sig_date)
  ic <- ic_history[Date < sig_d]  # PIT: strictly before

  group_names <- names(groups)
  n_groups <- length(group_names)

  # Compute group-level IC time series
  group_stats <- rbindlist(lapply(group_names, function(gname) {
    facs <- groups[[gname]]
    ic_grp <- ic[Factor_Name %in% facs]

    if (nrow(ic_grp) == 0) {
      return(data.table(Family = gname, Mean_IC = NA_real_,
                        Var_IC = NA_real_, N = 0L))
    }

    # Group IC per month = mean of factor ICs
    monthly_ic <- ic_grp[, .(Group_IC = mean(IC, na.rm = TRUE)), by = Date]

    n <- nrow(monthly_ic)
    if (n < min_months) {
      return(data.table(Family = gname, Mean_IC = mean(monthly_ic$Group_IC, na.rm = TRUE),
                        Var_IC = NA_real_, N = n))
    }

    data.table(
      Family = gname,
      Mean_IC = mean(monthly_ic$Group_IC, na.rm = TRUE),
      Var_IC = var(monthly_ic$Group_IC, na.rm = TRUE),
      N = n
    )
  }))

  # IV weighting: w ∝ 1/var, but only for groups with positive Mean_IC
  group_stats[, IV_weight := fifelse(
    !is.na(Var_IC) & Var_IC > 1e-8 & Mean_IC > 0,
    1.0 / Var_IC,
    0.0
  )]

  total_iv <- sum(group_stats$IV_weight, na.rm = TRUE)

  if (total_iv < 1e-8) {
    # Fallback: equal weight
    weights <- setNames(rep(1.0 / n_groups, n_groups), group_names)
  } else {
    group_stats[, Weight := IV_weight / total_iv]
    weights <- setNames(group_stats$Weight, group_stats$Family)
  }

  # Ensure all groups present
  for (g in group_names) {
    if (is.na(weights[g]) || is.null(weights[g])) weights[g] <- 0
  }

  weights
}


#==============================================================================
# 3. compute_within_group_weights() — ICIR-proportional within group
#==============================================================================

#' Select and weight factors within a group by ICIR.
#' Factors with negative ICIR are excluded.
#'
#' @param ic_dt data.table from compute_rolling_ic_all (Factor_Name, ICIR, Mean_IC)
#' @param group_factors Character vector of factor names in this group
#' @param max_factors Integer. Max factors to keep per group (default 10)
#' @return data.table: Factor_Name, Weight (sums to 1 within group)
compute_within_group_weights <- function(ic_dt, group_factors, max_factors = 5L) {
  dt <- ic_dt[Factor_Name %in% group_factors & !is.na(ICIR) & ICIR > 0]

  if (nrow(dt) == 0) {
    # Fallback: equal weight all available
    avail <- ic_dt[Factor_Name %in% group_factors & !is.na(ICIR)]
    if (nrow(avail) == 0) return(data.table(Factor_Name = character(), Weight = numeric()))
    avail[, Weight := 1.0 / .N]
    return(avail[, .(Factor_Name, Weight)])
  }

  # Keep top max_factors by ICIR
  setorder(dt, -ICIR)
  dt <- head(dt, max_factors)

  # ICIR-proportional weights
  dt[, Weight := ICIR / sum(ICIR)]

  dt[, .(Factor_Name, Weight)]
}


#==============================================================================
# 4. compute_allocation() — Main orchestrator
#==============================================================================

#' Main allocation: regime + IC + FM → group weights + factor weights.
#'
#' @param regime_label Character. "normal" / "elevated" / "crisis"
#' @param mrs_val Numeric. Raw MRS value (0-100)
#' @param ic_dt data.table from compute_rolling_ic_all
#' @param fm_dt data.table from compute_factor_momentum
#' @param groups Named list (family -> factor names)
#' @param ic_history data.table with Date, Factor_Name, IC (for group IV)
#' @param sig_date Date. Current signal date
#' @param prev_group_weights Named numeric. Previous month's group weights (for smoothing)
#' @return Named list:
#'   $group_weights: named numeric vector
#'   $factor_weights: data.table(Factor_Name, Family, Weight_In_Group, Weight_Final)
#'   $confidence: "high" / "moderate" / "low"
compute_allocation <- function(regime_label, mrs_val,
                                ic_dt, fm_dt, groups,
                                ic_history, sig_date,
                                prev_group_weights = NULL) {

  # ---- Step 1: MRS + FM → Confidence ----
  fm_dir <- if (!is.null(fm_dt) && nrow(fm_dt) > 0) {
    # Source factor_momentum.R classify_fm_direction if available
    if (exists("classify_fm_direction")) classify_fm_direction(fm_dt)
    else "neutral"
  } else "neutral"

  confidence <- .determine_confidence(regime_label, fm_dir)

  # ---- Step 2: Group weights ----
  iv_weights <- compute_group_weights_iv(ic_history, groups, sig_date)
  ew_weights <- setNames(rep(1.0 / length(groups), length(groups)), names(groups))

  # Blend by confidence
  group_weights <- switch(confidence,
    high     = iv_weights,
    moderate = 0.7 * iv_weights + 0.3 * ew_weights,
    low      = ew_weights
  )

  # Regime-conditional floors/caps
  group_weights <- .apply_regime_bounds(group_weights, regime_label)

  # Normalize
  total <- sum(group_weights, na.rm = TRUE)
  if (total > 1e-8) group_weights <- group_weights / total

  # Smooth with previous month (reduce turnover)
  if (!is.null(prev_group_weights)) {
    for (g in names(group_weights)) {
      if (g %in% names(prev_group_weights)) {
        group_weights[g] <- 0.7 * group_weights[g] + 0.3 * prev_group_weights[g]
      }
    }
    total <- sum(group_weights, na.rm = TRUE)
    if (total > 1e-8) group_weights <- group_weights / total
  }

  # ---- Step 3: Within-group factor weights ----
  factor_weights_list <- list()
  for (gname in names(groups)) {
    wg <- compute_within_group_weights(ic_dt, groups[[gname]])
    if (nrow(wg) > 0) {
      wg[, Family := gname]
      wg[, Weight_Final := Weight * group_weights[gname]]
      factor_weights_list[[gname]] <- wg
    }
  }

  factor_weights <- rbindlist(factor_weights_list)
  setnames(factor_weights, "Weight", "Weight_In_Group")

  list(
    group_weights  = group_weights,
    factor_weights = factor_weights,
    confidence     = confidence,
    fm_direction   = fm_dir,
    regime_label   = regime_label
  )
}


#==============================================================================
# 5. compute_composite_score() — Per-stock composite
#==============================================================================

#' Produce composite stock score from weighted factor z-scores.
#'
#' @param factor_dt data.table: Ticker, Factor_Name, Z_Score_Aligned
#' @param factor_weights data.table: Factor_Name, Weight_Final
#' @param sector_map data.table: Ticker, Sector (for neutralization)
#' @return data.table: Ticker, Score (composite, higher = better)
compute_composite_score <- function(factor_dt, factor_weights, sector_map = NULL) {
  # Merge weights
  dt <- merge(factor_dt, factor_weights[, .(Factor_Name, Weight_Final)],
              by = "Factor_Name")

  # Weighted sum per ticker
  scores <- dt[, .(Score = sum(Z_Score_Aligned * Weight_Final, na.rm = TRUE)),
               by = Ticker]

  # Sector neutralization
  if (!is.null(sector_map) && nrow(sector_map) > 0) {
    scores <- merge(scores, sector_map, by = "Ticker", all.x = TRUE)
    scores[!is.na(Sector), Score := Score - mean(Score, na.rm = TRUE), by = Sector]
    scores[, Sector := NULL]
  }

  scores[order(-Score)]
}


#==============================================================================
# Internal helpers
#==============================================================================

.determine_confidence <- function(regime_label, fm_direction) {
  # MRS + FM agreement matrix
  if (regime_label == "normal" && fm_direction == "risk_on") return("high")
  if (regime_label == "crisis" && fm_direction == "risk_off") return("high")
  if (regime_label == "normal" && fm_direction == "risk_off") return("low")
  if (regime_label == "crisis" && fm_direction == "risk_on") return("low")
  if (regime_label == "elevated") return("moderate")
  # neutral FM
  if (fm_direction == "neutral") return("moderate")
  "moderate"
}

.apply_regime_bounds <- function(weights, regime_label) {
  # Structural bounds (Korean market: defense is persistent alpha)
  # Defense always at least 15%
  if ("defense" %in% names(weights)) weights["defense"] <- max(weights["defense"], 0.15)
  # Liquidity/Crowding cap 15% (weak standalone alpha)
  if ("liquidity" %in% names(weights)) weights["liquidity"] <- min(weights["liquidity"], 0.15)

  # Regime-conditional bounds
  if (regime_label == "crisis") {
    if ("defense" %in% names(weights)) weights["defense"] <- max(weights["defense"], 0.30)
    if ("quality" %in% names(weights)) weights["quality"] <- max(weights["quality"], 0.20)
    if ("momentum" %in% names(weights)) weights["momentum"] <- min(weights["momentum"], 0.05)
    if ("growth" %in% names(weights)) weights["growth"] <- min(weights["growth"], 0.05)
  } else if (regime_label == "elevated") {
    if ("defense" %in% names(weights)) weights["defense"] <- max(weights["defense"], 0.20)
    if ("quality" %in% names(weights)) weights["quality"] <- max(weights["quality"], 0.15)
    if ("momentum" %in% names(weights)) weights["momentum"] <- min(weights["momentum"], 0.15)
  } else {
    # Normal: cap any single group at 30%
    for (g in names(weights)) {
      weights[g] <- min(weights[g], 0.30)
    }
  }
  weights
}


cat("[regime_factor_alloc_engine] Loaded. Functions: compute_allocation(),\n")
cat("  compute_group_weights_iv(), compute_within_group_weights(),\n")
cat("  compute_composite_score(), get_regime_label()\n")
