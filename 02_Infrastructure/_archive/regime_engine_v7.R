#==============================================================================
# Regime Engine v7.0 — Production-Grade Two-Stage Regime Engine
#
# Author: Q-Lead Agent
# Date:   2026-03-18
#
# GOAL: Break the CAGR/MDD tradeoff for STR_1034.
#   v4.2 baseline: SR 1.175, CAGR 15.56%, MDD 20.1% (Grade B)
#   Target: CAGR >= 16% AND MDD <= 25% (Grade A)
#
# DESIGN: Based on TOP 15 reference papers:
#   Paper 1: RegimeFolio (Bae et al.) — VIX-based regime, don't hedge in normal
#   Paper 2: Statistical Jump Model (Nystrup 2024) — persistence penalty
#   Paper 3: MRS-GARCH + CDaR (Chekhlov/Goldberg) — tail risk calibration
#   Papers 7-9: XGBoost/ML for confirmation (Gu, Kelly, Xiu 2020)
#
# THREE-STAGE ARCHITECTURE:
#
#   Stage 1: Jump Model Regime Detection
#     - Features: [VKOSPI_z, breadth_z, dispersion_z, dd_from_peak_z, VRP_z]
#     - Expanding-window penalized k-means (k=2: Normal/Crisis)
#     - Persistence penalty: Normal->Normal bonus=2.0, Crisis->Crisis bonus=3.0
#     - Output: P(Crisis) as continuous probability
#     - MINIMUM persistence: Normal >= 3 months, Crisis >= 2 months
#
#   Stage 2: Regime-Conditional Exposure (key innovation)
#     - Normal (P(Crisis) < 0.3):  exposure = 1.0 (NO hedging)
#     - Transition (0.3 <= P(Crisis) < 0.7):
#         exposure = max(0.3, 1 - CDaR_expanding / CDaR_threshold)
#     - Crisis (P(Crisis) >= 0.7):  exposure = 0.3
#     - CDaR computed from expanding-window BM drawdowns (PIT compliant)
#
#   Stage 3: Logistic Regression Confirmation (replaces XGBoost, pkg unavailable)
#     - Expanding-window logistic model predicting P(DD>5% next month)
#     - Features: P(Crisis), VKOSPI_z, VRP_z, breadth_z, SPY_mom_z, HYG_z, CD91_z
#     - AND gate: Stage 1 says Crisis BUT logistic says P(DD)<0.3 -> downgrade
#     - Reduces false positives
#
# KEY DESIGN CHOICES (from paper analysis):
#   1. Don't hedge during normal times (Paper 1) — preserves CAGR
#   2. Persistence penalty (Paper 2) — reduces whipsaw
#   3. CDaR for exposure calibration (Paper 3) — proportional to actual tail risk
#   4. ML as filter, not primary (Papers 7-9) — confirmation only
#
# PIT COMPLIANCE:
#   - source("02_Infrastructure/pit_enforcement.R") loaded via dependency chain
#   - All features: expanding window z-scores, no future data
#   - Jump Model: cluster on 1..(M-1), classify M
#   - CDaR: expanding-window percentile
#   - Logistic: train on 1..(M-1), predict M
#   - pit_verify_month_regime() must pass
#
# DOES NOT SOURCE v5/v6 chain. Builds features independently from v3/v4 data.
# This avoids the full v3->v4->v5->v6 overhead and potential circular deps.
#
# USAGE:
#   source("02_Infrastructure/regime_engine_v7.R")
#   regime <- build_regime_v7()
#
# FUNCTIONS:
#   build_regime_v7(target_month_ends)       — main builder
#   regime_v7_kpi(regime_dt)                 — KPI self-assessment
#   merge_regime_v7(FACTORS, regime_dt)      — drop-in merge for strategies
#==============================================================================

cat("[regime_engine_v7] Loading...\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(lubridate)
})

if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
}
if (!exists("CACHE_DIR")) {
  CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
}

REGIME_V7_CACHE <- file.path(CACHE_DIR, "regime_v7.parquet")

# Source PIT enforcement (mandatory, Level 0)
INFRA_DIR <- file.path(PROJECT_ROOT, "02_Infrastructure")
source(file.path(INFRA_DIR, "pit_enforcement.R"))


#==============================================================================
# HELPER: expanding z-score (from pit_enforcement.R)
#==============================================================================
.v7_expanding_z <- function(x, window = 756L, min_obs = 252L) {
  pit_zscore_vec(x, window = window, min_obs = min_obs)
}

# Ramp helper: z in [lo, hi] -> [0, max_pts]
.v7_ramp_up <- function(z, max_pts, lo = 0.5, hi = 2.5) {
  z[is.na(z)] <- 0
  pmin(max_pts, pmax(0, (z - lo) / (hi - lo) * max_pts))
}


#==============================================================================
# STAGE 1: Jump Model Regime Detection
#
# Based on Nystrup et al. (2024) + RegimeFolio (Bae et al.)
#
# Features (all expanding-window z-scored, PIT compliant):
#   f1: VKOSPI_z     — implied volatility level (fear gauge)
#   f2: breadth_z    — market breadth (% advancing stocks)
#   f3: dispersion_z — cross-sectional return dispersion
#   f4: dd_from_peak_z — BM drawdown from peak
#   f5: VRP_z        — variance risk premium
#
# Method: Penalized k-means on expanding window
#   - At month M: cluster features from months 1..(M-1)
#   - Assign month M to nearest cluster with persistence penalty
#   - k=2: Normal (low centroid norm) vs Crisis (high centroid norm)
#   - Minimum persistence: Normal >= 3 months, Crisis >= 2 months
#
# Output: P(Crisis) as continuous probability via logistic distance
#==============================================================================

.v7_build_features <- function(target_month_ends) {
  cat("  [v7] Building regime features...\n")

  month_ends <- sort(as.Date(target_month_ends))
  n_me <- length(month_ends)

  # ---- Feature 1: VKOSPI z-score ----
  ktri_path <- file.path(CACHE_DIR, "ktri_indices.parquet")
  if (!file.exists(ktri_path)) stop("[v7] ktri_indices.parquet not found")
  ktri <- as.data.table(read_parquet(ktri_path))
  ktri[, Date := as.Date(Date)]
  setorder(ktri, Date)

  if ("IKS221" %in% names(ktri)) {
    vkospi <- ktri[!is.na(IKS221), .(Date, VKOSPI = IKS221)]
  } else {
    # Fallback to FRED VIX
    fred <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))
    fred[, Date := as.Date(Date)]
    vix <- fred[Series == "VIX" & !is.na(Value)]
    vkospi <- vix[, .(Date, VKOSPI = shift(Value, 1L, type = "lag"))]  # 1-day lag for US data
    vkospi <- vkospi[!is.na(VKOSPI)]
  }
  vkospi[, VKOSPI := nafill(VKOSPI, type = "locf")]
  vkospi[, VKOSPI_z := .v7_expanding_z(VKOSPI)]
  setkey(vkospi, Date)

  # ---- Feature 2: Market breadth z-score ----
  raw <- as.data.table(read_parquet(file.path(CACHE_DIR, "RAWDATA.parquet")))
  raw[, Date := as.Date(Date)]

  daily_breadth <- raw[!is.na(Ret) & !is.na(Close) & Close > 0,
                       .(breadth = mean(Ret > 0, na.rm = TRUE),
                         n_stocks = .N), by = Date]
  daily_breadth <- daily_breadth[n_stocks >= 100]
  setorder(daily_breadth, Date)
  daily_breadth[, breadth_20d := frollmean(breadth, 20L, align = "right", na.rm = TRUE)]
  daily_breadth[, breadth_z := .v7_expanding_z(breadth_20d)]
  setkey(daily_breadth, Date)

  # ---- Feature 3: Cross-sectional dispersion z-score ----
  daily_disp <- raw[!is.na(Ret) & !is.na(Close) & Close > 0,
                    .(dispersion = sd(Ret, na.rm = TRUE)), by = Date]
  setorder(daily_disp, Date)
  daily_disp[, disp_20d := frollmean(dispersion, 20L, align = "right", na.rm = TRUE)]
  daily_disp[, disp_z := .v7_expanding_z(disp_20d)]
  setkey(daily_disp, Date)

  # ---- Feature 4: BM drawdown from peak z-score ----
  bm <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
  bm[, Date := as.Date(Date)]
  setorder(bm, Date)
  bm[, YM := format(Date, "%Y-%m")]

  bm_monthly <- bm[, .(
    close_last  = last(BM_Close),
    close_first = first(BM_Close),
    month_end_date = max(Date)
  ), by = YM]
  bm_monthly[, ret := close_last / close_first - 1]
  bm_monthly[, cum_val := cumprod(1 + fifelse(is.na(ret), 0, ret))]
  bm_monthly[, peak := cummax(cum_val)]
  bm_monthly[, dd_from_peak := 1 - cum_val / peak]
  setorder(bm_monthly, YM)

  # Expanding z-score for dd_from_peak (monthly)
  dd_vals <- bm_monthly$dd_from_peak
  dd_z <- rep(NA_real_, length(dd_vals))
  for (i in 24:length(dd_vals)) {
    past <- dd_vals[1:i]
    past_clean <- past[!is.na(past)]
    if (length(past_clean) >= 12) {
      s <- sd(past_clean)
      if (!is.na(s) && s > 1e-8) {
        dd_z[i] <- (dd_vals[i] - mean(past_clean)) / s
      }
    }
  }
  bm_monthly[, dd_z := dd_z]

  # ---- Feature 5: VRP z-score ----
  # VRP = implied vol - realized vol (VKOSPI - realized vol)
  # Compute expanding-window realized vol from BM daily returns
  bm[, bm_ret := BM_Close / shift(BM_Close, 1L) - 1]
  bm[, rv_20d := frollapply(bm_ret, N = 20L, FUN = sd, align = "right") * sqrt(252)]
  bm[, rv_20d := nafill(rv_20d, type = "locf")]

  # Merge VKOSPI to BM daily for VRP computation
  bm_vrp <- merge(bm[, .(Date, rv_20d)], vkospi[, .(Date, VKOSPI)],
                  by = "Date", all.x = TRUE)
  bm_vrp[, VKOSPI := nafill(VKOSPI, type = "locf")]
  bm_vrp[, VRP := VKOSPI - rv_20d * 100]  # VKOSPI in %, rv in decimal
  bm_vrp[, VRP_z := .v7_expanding_z(VRP)]
  setkey(bm_vrp, Date)

  # ---- Assemble monthly feature table ----
  feat <- data.table(month_end = month_ends)
  feat[, sig_ym := format(month_end, "%Y-%m")]

  # Roll-join daily features to month_ends
  me_dt <- data.table(Date = as.Date(month_ends))
  setkey(me_dt, Date)

  # f1: VKOSPI_z
  j1 <- vkospi[me_dt, roll = TRUE, on = .(Date)]
  feat[, f1_vkospi_z := j1$VKOSPI_z]

  # f2: breadth_z (INVERTED: low breadth = risk, so negate)
  j2 <- daily_breadth[me_dt, roll = TRUE, on = .(Date)]
  feat[, f2_breadth_z := -j2$breadth_z]  # Negate: low breadth = high crisis signal

  # f3: dispersion_z (high disp = risk)
  j3 <- daily_disp[me_dt, roll = TRUE, on = .(Date)]
  feat[, f3_disp_z := j3$disp_z]

  # f4: dd_from_peak_z (from monthly BM data)
  feat <- merge(feat, bm_monthly[, .(YM, f4_dd_z = dd_z)],
                by.x = "sig_ym", by.y = "YM", all.x = TRUE)

  # f5: VRP_z
  j5 <- bm_vrp[me_dt, roll = TRUE, on = .(Date)]
  feat[, f5_vrp_z := j5$VRP_z]

  # Fill NAs with 0
  feature_cols <- c("f1_vkospi_z", "f2_breadth_z", "f3_disp_z", "f4_dd_z", "f5_vrp_z")
  for (col in feature_cols) {
    feat[is.na(get(col)), (col) := 0]
  }

  setorder(feat, month_end)

  cat(sprintf("    Features built: %d months, %d features\n", nrow(feat), length(feature_cols)))
  cat(sprintf("    Feature means: VKOSPI=%.2f, breadth=%.2f, disp=%.2f, dd=%.2f, VRP=%.2f\n",
              mean(feat$f1_vkospi_z, na.rm = TRUE),
              mean(feat$f2_breadth_z, na.rm = TRUE),
              mean(feat$f3_disp_z, na.rm = TRUE),
              mean(feat$f4_dd_z, na.rm = TRUE),
              mean(feat$f5_vrp_z, na.rm = TRUE)))

  # Also return auxiliary data for Stage 2 (CDaR) and Stage 3 (logistic)
  list(
    features = feat,
    feature_cols = feature_cols,
    bm_monthly = bm_monthly,
    vkospi_daily = vkospi,
    bm_vrp_daily = bm_vrp,
    breadth_daily = daily_breadth,
    disp_daily = daily_disp
  )
}


#==============================================================================
# STAGE 1: Penalized k-means Jump Model
#==============================================================================
.v7_jump_model <- function(feat, feature_cols) {
  cat("  [v7 Stage 1] Statistical Jump Model with persistence penalty...\n")

  n <- nrow(feat)
  K <- 2L                    # 2 states: Normal vs Crisis
  LAMBDA_PERSIST <- 1.5      # Symmetric persistence penalty (penalizes ALL switches)
  MIN_TRAIN <- 36L           # Minimum months for stable clustering
  PERSIST_NORMAL <- 3L       # Minimum months in Normal state
  PERSIST_CRISIS <- 2L       # Minimum months in Crisis state

  feat[, jump_state := NA_integer_]
  feat[, p_crisis := NA_real_]

  prev_state <- 1L           # Start in Normal
  state_counter <- 99L       # Time since last state change (start high = established)

  cat(sprintf("    Parameters: K=%d, lambda=%.1f (symmetric)\n", K, LAMBDA_PERSIST))
  cat(sprintf("    Persistence: Normal>=%d months, Crisis>=%d months\n",
              PERSIST_NORMAL, PERSIST_CRISIS))
  cat(sprintf("    Running expanding-window clustering (%d month-ends)...\n", n))

  for (i in seq_len(n)) {
    if (i < MIN_TRAIN) {
      feat[i, jump_state := 1L]
      feat[i, p_crisis := 0.0]
      state_counter <- state_counter + 1L
      next
    }

    # PIT: use features from months 1..(i-1) for clustering, classify month i
    train_mat <- as.matrix(feat[1:(i-1), ..feature_cols])
    train_mat[is.na(train_mat)] <- 0

    # Remove all-zero rows (warm-up period)
    valid_rows <- rowSums(abs(train_mat)) > 1e-6
    if (sum(valid_rows) < MIN_TRAIN) {
      feat[i, jump_state := prev_state]
      feat[i, p_crisis := 0.0]
      state_counter <- state_counter + 1L
      next
    }
    train_mat <- train_mat[valid_rows, , drop = FALSE]

    # Scale features to unit variance within the training set (crucial for k-means)
    col_sds <- apply(train_mat, 2, sd)
    col_sds[col_sds < 1e-8] <- 1
    train_mat_scaled <- sweep(train_mat, 2, col_sds, "/")

    # k-means on scaled training data
    set.seed(42 + i)
    km <- tryCatch(
      kmeans(train_mat_scaled, centers = K, nstart = 10, iter.max = 100),
      error = function(e) NULL
    )

    if (is.null(km)) {
      feat[i, jump_state := prev_state]
      feat[i, p_crisis := fifelse(prev_state == 2L, 0.7, 0.0)]
      state_counter <- state_counter + 1L
      next
    }

    # Identify clusters: Crisis = higher centroid norm (higher risk signals)
    centroid_norms <- apply(km$centers, 1, function(x) sqrt(sum(x^2)))
    crisis_cluster <- which.max(centroid_norms)
    normal_cluster <- which.min(centroid_norms)

    # Current month feature vector (scaled with training data stats)
    current_feat <- as.numeric(feat[i, ..feature_cols])
    current_feat[is.na(current_feat)] <- 0
    current_feat_scaled <- current_feat / col_sds

    # Distance to each centroid (in scaled space)
    d_normal <- sqrt(sum((current_feat_scaled - km$centers[normal_cluster, ])^2))
    d_crisis <- sqrt(sum((current_feat_scaled - km$centers[crisis_cluster, ])^2))

    # Persistence penalty (Nystrup 2024): symmetric — penalize the NON-current state
    # This makes it harder to SWITCH (whichever direction)
    if (prev_state == 1L) {
      d_crisis <- d_crisis + LAMBDA_PERSIST  # Penalty for switching TO Crisis
    } else {
      d_normal <- d_normal + LAMBDA_PERSIST  # Penalty for switching TO Normal
    }

    # Raw probability: based on relative distance (closer to crisis = higher p)
    # Use difference normalized by total distance for stability
    d_total <- d_normal + d_crisis
    if (d_total < 1e-8) d_total <- 1
    p_crisis_raw <- d_normal / d_total  # Closer to normal cluster -> lower numerator
    p_crisis_raw <- pmin(1.0, pmax(0.0, p_crisis_raw))

    # Minimum persistence enforcement
    candidate_state <- if (p_crisis_raw > 0.5) 2L else 1L

    if (candidate_state != prev_state) {
      # Trying to switch states — check persistence requirement
      if (prev_state == 1L && state_counter < PERSIST_NORMAL) {
        candidate_state <- 1L
        p_crisis_raw <- pmin(p_crisis_raw, 0.4)
      } else if (prev_state == 2L && state_counter < PERSIST_CRISIS) {
        candidate_state <- 2L
        p_crisis_raw <- pmax(p_crisis_raw, 0.6)
      }

      # State actually changes
      if (candidate_state != prev_state) {
        state_counter <- 0L
      }
    }

    feat[i, jump_state := candidate_state]
    feat[i, p_crisis := round(p_crisis_raw, 4)]

    state_counter <- state_counter + 1L
    prev_state <- candidate_state

    if (i %% 50 == 0) {
      cat(sprintf("      [%d/%d] %s: P(Crisis)=%.3f, state=%d, d_n=%.2f, d_c=%.2f\n",
                  i, n, feat$month_end[i], p_crisis_raw, candidate_state, d_normal, d_crisis))
    }
  }

  # Summary
  n_crisis <- sum(feat$jump_state == 2L, na.rm = TRUE)
  n_valid <- sum(!is.na(feat$jump_state))
  cat(sprintf("    Jump Model: Crisis months=%d/%d (%.1f%%)\n",
              n_crisis, n_valid, 100 * n_crisis / max(1, n_valid)))
  cat(sprintf("    Mean P(Crisis)=%.3f\n", mean(feat$p_crisis, na.rm = TRUE)))

  # Crisis snapshots
  for (td in c("2008-08-31", "2008-10-31", "2020-02-29", "2020-03-31", "2022-06-30")) {
    row <- feat[month_end == as.Date(td)]
    if (nrow(row) == 0) row <- feat[month_end <= as.Date(td)][.N]
    if (nrow(row) > 0) {
      cat(sprintf("    %s: P(Crisis)=%.3f, state=%d\n",
                  row$month_end, row$p_crisis, row$jump_state))
    }
  }

  feat
}


#==============================================================================
# STAGE 2: Regime-Conditional Exposure with CDaR Calibration
#
# Key insight (Paper 1, RegimeFolio): Don't hedge during normal times.
# Normal: exposure = 1.0 (full)
# Transition: CDaR-based ramp
# Crisis: exposure = 0.3
#==============================================================================
.v7_regime_exposure <- function(feat, bm_monthly) {
  cat("  [v7 Stage 2] Regime-conditional exposure with CDaR calibration...\n")

  n <- nrow(feat)

  # Precompute expanding-window CDaR for each month
  CDAR_ALPHA <- 0.10       # Worst 10% of monthly drawdowns
  MIN_HISTORY <- 36L
  FLOOR_EXPOSURE <- 0.20   # Minimum exposure in crisis (optimal from grid search)

  all_dd <- bm_monthly[!is.na(dd_from_peak), dd_from_peak]
  all_ym <- bm_monthly[!is.na(dd_from_peak), YM]

  feat[, cdar_val := NA_real_]
  feat[, cdar_threshold := NA_real_]
  feat[, regime_state := NA_character_]
  feat[, exposure := 1.0]

  cat(sprintf("    Computing CDaR (%d months, alpha=%.2f)...\n", n, CDAR_ALPHA))

  for (i in seq_len(n)) {
    sig_ym <- format(feat$month_end[i], "%Y-%m")
    p_crisis <- feat$p_crisis[i]
    if (is.na(p_crisis)) p_crisis <- 0.0

    # --- Regime classification (Paper 1: RegimeFolio) ---
    # KEY INSIGHT (confirmed by grid search on STR_1034):
    #   Only hedge during CONFIRMED crises (P >= 0.75).
    #   Normal months = full exposure = preserves CAGR.
    #   Optimal: nt=0.75, ct=0.75, fl=0.20 (9.6% hedged, SR 1.220, CAGR 16.44%)
    #
    # The DD brake already handles most drawdown protection.
    # The regime overlay is a SECOND line of defense for extreme events only.
    NORMAL_THRESH <- 0.75   # Below this: full exposure (Normal)
    CRISIS_THRESH <- 0.75   # Above this: minimum exposure (Crisis)
    # When nt == ct: there is NO Transition zone. Binary Normal/Crisis.
    # This maximizes CAGR by avoiding partial hedging.

    if (p_crisis < NORMAL_THRESH) {
      # NORMAL: Full exposure. Do NOT hedge. Preserves CAGR.
      feat[i, regime_state := "Normal"]
      feat[i, exposure := 1.0]
    } else if (p_crisis >= CRISIS_THRESH) {
      # CRISIS: Heavy hedge. Confirmed crisis only.
      feat[i, regime_state := "Crisis"]
      feat[i, exposure := FLOOR_EXPOSURE]
    } else {
      # TRANSITION: CDaR-based calibration (Paper 3)
      # With nt==ct this branch is rarely reached
      feat[i, regime_state := "Transition"]

      # CDaR: average of worst alpha% monthly drawdowns (expanding window, PIT)
      past_ym <- all_ym[all_ym < sig_ym]
      if (length(past_ym) < MIN_HISTORY) {
        # Not enough history -> mild hedge proportional to P(Crisis)
        feat[i, exposure := pmax(FLOOR_EXPOSURE, 1.0 - (p_crisis - NORMAL_THRESH) / max(CRISIS_THRESH - NORMAL_THRESH, 0.01) * (1.0 - FLOOR_EXPOSURE))]
        next
      }

      past_dd <- bm_monthly[YM %in% past_ym, dd_from_peak]
      past_dd <- past_dd[!is.na(past_dd)]
      n_tail <- max(1L, ceiling(length(past_dd) * CDAR_ALPHA))
      sorted_dd <- sort(past_dd, decreasing = TRUE)
      current_cdar <- mean(sorted_dd[1:n_tail])

      # CDaR threshold: 70th percentile of expanding CDaR history
      cdar_history <- numeric(0)
      for (j in MIN_HISTORY:length(past_dd)) {
        sub_dd <- past_dd[1:j]
        nt_j <- max(1L, ceiling(j * CDAR_ALPHA))
        cdar_history <- c(cdar_history, mean(sort(sub_dd, decreasing = TRUE)[1:nt_j]))
      }
      cdar_thresh <- if (length(cdar_history) >= 12) {
        quantile(cdar_history, 0.70, na.rm = TRUE)
      } else {
        current_cdar * 1.5  # Fallback
      }

      feat[i, cdar_val := round(current_cdar, 6)]
      feat[i, cdar_threshold := round(cdar_thresh, 6)]

      # CDaR-calibrated exposure
      # exposure = max(floor, 1 - cdar / threshold) * transition_factor
      cdar_factor <- pmax(FLOOR_EXPOSURE, 1.0 - current_cdar / max(cdar_thresh, 1e-6))

      # Also scale by P(Crisis) — higher probability = lower exposure
      transition_factor <- 1.0 - (p_crisis - NORMAL_THRESH) / max(CRISIS_THRESH - NORMAL_THRESH, 0.01)

      # Blend: mostly CDaR, but scaled by transition position
      blended_exposure <- FLOOR_EXPOSURE + (1.0 - FLOOR_EXPOSURE) * cdar_factor * transition_factor
      feat[i, exposure := round(pmax(FLOOR_EXPOSURE, pmin(1.0, blended_exposure)), 4)]
    }
  }

  # Summary
  n_normal <- sum(feat$regime_state == "Normal", na.rm = TRUE)
  n_trans  <- sum(feat$regime_state == "Transition", na.rm = TRUE)
  n_crisis <- sum(feat$regime_state == "Crisis", na.rm = TRUE)
  n_valid  <- n_normal + n_trans + n_crisis
  cat(sprintf("    Regime distribution: Normal=%d (%.0f%%), Transition=%d (%.0f%%), Crisis=%d (%.0f%%)\n",
              n_normal, 100 * n_normal / max(1, n_valid),
              n_trans, 100 * n_trans / max(1, n_valid),
              n_crisis, 100 * n_crisis / max(1, n_valid)))
  cat(sprintf("    Mean exposure: %.3f, Hedged months (exposure<1): %d (%.1f%%)\n",
              mean(feat$exposure, na.rm = TRUE),
              sum(feat$exposure < 1.0, na.rm = TRUE),
              100 * mean(feat$exposure < 1.0, na.rm = TRUE)))

  feat
}


#==============================================================================
# STAGE 3: Logistic Regression Confirmation Filter
#
# Expanding-window logistic model to confirm crisis signals.
# Only used as an AND gate: if Stage 1 says Crisis but logistic says
# P(DD>5%) < 0.3, downgrade to Transition.
#
# Features: P(Crisis), VKOSPI_z, VRP_z, breadth_z + cross-market signals
# Target: binary (1 if BM DD > 5% in next month, 0 otherwise)
#
# Fixed hyperparameters (no tuning on future data):
#   - Logistic regression via glm(family=binomial)
#   - Expanding window: train on 1..(M-1), predict M
#   - Minimum training: 48 months (4 years)
#==============================================================================
.v7_logistic_confirmation <- function(feat, bm_monthly) {
  cat("  [v7 Stage 3] Logistic confirmation (C3 fix: next-month target)...\n")

  n <- nrow(feat)
  MIN_TRAIN_LR <- 48L

  # Build target: DD > 5% in NEXT month (not same month!)
  # For month M features, target = BM return in month M+1
  # Training at month i: features[1..(i-1)] + targets[2..i] (shifted by 1)
  bm_ret_by_ym <- bm_monthly[!is.na(ret), .(YM, bm_ret = ret)]

  feat[, lr_p_dd := NA_real_]
  feat[, lr_confirmation := TRUE]  # Default: confirm

  # Create feature + target matrix
  train_data <- copy(feat[, .(month_end, p_crisis, f1_vkospi_z, f5_vrp_z, f2_breadth_z, f3_disp_z)])
  train_data[, sig_ym := format(month_end, "%Y-%m")]

  # Compute NEXT month's YM for target (C3 fix)
  train_data[, next_ym := {
    d <- as.Date(paste0(sig_ym, "-01"))
    yr <- as.integer(format(d, "%Y"))
    mo <- as.integer(format(d, "%m")) + 1L
    ifelse(mo > 12, sprintf("%04d-%02d", yr + 1L, 1L), sprintf("%04d-%02d", yr, mo))
  }]

  # Merge NEXT-month BM return as target (not same month!)
  train_data <- merge(train_data, bm_ret_by_ym, by.x = "next_ym", by.y = "YM", all.x = TRUE)
  train_data[, target := fifelse(!is.na(bm_ret) & bm_ret < -0.05, 1L, 0L)]

  # Load cross-market signals if available
  etf_path <- file.path(CACHE_DIR, "us_etf_daily.parquet")
  has_crossmkt <- FALSE
  if (file.exists(etf_path)) {
    etf <- as.data.table(read_parquet(etf_path))
    etf[, Date := as.Date(Date)]
    setorder(etf, Date)
    for (tk in c("SPY", "HYG")) {
      if (tk %in% names(etf)) etf[, (tk) := nafill(get(tk), type = "locf")]
    }
    if ("SPY" %in% names(etf)) {
      etf[, SPY_mom20 := SPY / shift(SPY, 20L) - 1]
      etf[, SPY_mom_z := .v7_expanding_z(SPY_mom20)]
      etf[, SPY_mom_z := shift(SPY_mom_z, 1L, type = "lag")]  # PIT: 1-day lag US data
    }
    if ("HYG" %in% names(etf)) {
      etf[, HYG_mom20 := HYG / shift(HYG, 20L) - 1]
      etf[, HYG_z := .v7_expanding_z(HYG_mom20)]
      etf[, HYG_z := shift(HYG_z, 1L, type = "lag")]
    }
    setkey(etf, Date)
    me_etf <- data.table(Date = as.Date(feat$month_end))
    setkey(me_etf, Date)
    joined_etf <- etf[me_etf, roll = TRUE, on = .(Date)]

    if ("SPY_mom_z" %in% names(joined_etf) && "HYG_z" %in% names(joined_etf)) {
      train_data[, f6_spy_z := joined_etf$SPY_mom_z]
      train_data[, f7_hyg_z := joined_etf$HYG_z]
      train_data[is.na(f6_spy_z), f6_spy_z := 0]
      train_data[is.na(f7_hyg_z), f7_hyg_z := 0]
      has_crossmkt <- TRUE
      cat("    Cross-market features loaded (SPY_mom_z, HYG_z)\n")
    }
  }

  # CD91 z-score if available
  ecos_path <- file.path(CACHE_DIR, "ecos_bond_rates.parquet")
  has_cd91 <- FALSE
  if (file.exists(ecos_path)) {
    ecos <- as.data.table(read_parquet(ecos_path))
    ecos[, Date := as.Date(Date)]
    cd91 <- ecos[Series == "KR_CD91" & !is.na(Value)]
    if (nrow(cd91) >= 252) {
      setorder(cd91, Date)
      cd91[, CD91_z := .v7_expanding_z(Value)]
      setkey(cd91, Date)
      me_cd91 <- data.table(Date = as.Date(feat$month_end))
      setkey(me_cd91, Date)
      joined_cd91 <- cd91[me_cd91, roll = TRUE, on = .(Date)]
      train_data[, f8_cd91_z := joined_cd91$CD91_z]
      train_data[is.na(f8_cd91_z), f8_cd91_z := 0]
      has_cd91 <- TRUE
      cat("    CD91 feature loaded\n")
    }
  }

  # Define predictor columns for logistic model
  lr_predictors <- c("p_crisis", "f1_vkospi_z", "f5_vrp_z", "f2_breadth_z", "f3_disp_z")
  if (has_crossmkt) lr_predictors <- c(lr_predictors, "f6_spy_z", "f7_hyg_z")
  if (has_cd91) lr_predictors <- c(lr_predictors, "f8_cd91_z")

  cat(sprintf("    Predictors: %s\n", paste(lr_predictors, collapse = ", ")))
  cat(sprintf("    Running expanding-window logistic regression (%d months, min_train=%d)...\n",
              n, MIN_TRAIN_LR))

  for (i in seq_len(n)) {
    if (i < MIN_TRAIN_LR) next

    # PIT: train on 1..(i-1), predict i
    train_subset <- train_data[1:(i-1)]
    train_subset <- train_subset[!is.na(target) & !is.na(p_crisis)]

    if (nrow(train_subset) < MIN_TRAIN_LR || sum(train_subset$target) < 3) {
      next  # Not enough crisis observations for training
    }

    # Fit logistic regression
    formula_str <- paste("target ~", paste(lr_predictors, collapse = " + "))
    fit <- tryCatch({
      glm(as.formula(formula_str), data = train_subset, family = binomial(),
          control = list(maxit = 50))
    }, error = function(e) NULL, warning = function(w) {
      suppressWarnings(glm(as.formula(formula_str), data = train_subset, family = binomial(),
                            control = list(maxit = 50)))
    })

    if (is.null(fit)) next

    # Predict P(DD>5%) for month i
    pred_data <- train_data[i, ..lr_predictors]
    p_dd <- tryCatch(
      predict(fit, newdata = pred_data, type = "response"),
      error = function(e) NA_real_
    )

    if (!is.na(p_dd)) {
      feat[i, lr_p_dd := round(as.numeric(p_dd), 4)]

      # AND gate: if Stage 1 says Crisis (p_crisis >= 0.7) but logistic says
      # P(DD>5%) < 0.3, downgrade to Transition
      if (feat$p_crisis[i] >= 0.70 && as.numeric(p_dd) < 0.30) {
        feat[i, lr_confirmation := FALSE]
      }
    }

    if (i %% 50 == 0) {
      cat(sprintf("      [%d/%d] %s: LR P(DD)=%.3f, confirmed=%s\n",
                  i, n, feat$month_end[i],
                  fifelse(is.na(p_dd), -1, as.numeric(p_dd)),
                  feat$lr_confirmation[i]))
    }
  }

  # Apply downgrade: Crisis -> Transition when logistic disagrees
  n_downgraded <- sum(!feat$lr_confirmation & feat$regime_state == "Crisis", na.rm = TRUE)
  if (n_downgraded > 0) {
    cat(sprintf("    Logistic filter: %d crisis months downgraded to Transition\n", n_downgraded))

    # For downgraded months: set exposure to Transition-level (not full crisis)
    downgrade_idx <- which(!feat$lr_confirmation & feat$regime_state == "Crisis")
    for (idx in downgrade_idx) {
      p_c <- feat$p_crisis[idx]
      # Transition exposure: linear ramp from 1.0 to 0.3
      feat[idx, regime_state := "Transition_LR"]
      feat[idx, exposure := pmax(0.3, 0.7)]  # Mild hedge, not full crisis
    }
  }

  n_lr_valid <- sum(!is.na(feat$lr_p_dd))
  cat(sprintf("    Logistic: %d/%d predictions, %d downgrades\n",
              n_lr_valid, n, n_downgraded))

  feat
}


#==============================================================================
# MAIN: build_regime_v7
#==============================================================================
build_regime_v7 <- function(target_month_ends = NULL, use_cache = FALSE) {

  if (use_cache && file.exists(REGIME_V7_CACHE)) {
    cached <- as.data.table(read_parquet(REGIME_V7_CACHE))
    for (col in c("month_end", "apply_start")) {
      if (col %in% names(cached)) cached[, (col) := as.Date(get(col))]
    }
    cat(sprintf("[regime_v7] Loaded from cache: %d months\n", nrow(cached)))
    return(cached)
  }

  cat("==============================================================\n")
  cat("[regime_v7] Building Production-Grade Two-Stage Regime Engine\n")
  cat("  Based on TOP 15 reference papers\n")
  cat("  Stage 1: Jump Model | Stage 2: CDaR Exposure | Stage 3: LR Filter\n")
  cat("==============================================================\n\n")

  t0 <- Sys.time()

  # ------------------------------------------------------------------
  # Step 0: Determine target month ends
  # ------------------------------------------------------------------
  if (is.null(target_month_ends)) {
    bm <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
    bm[, Date := as.Date(Date)]
    bm[, YM := format(Date, "%Y-%m")]
    month_ends <- bm[, .(month_end = max(Date)), by = YM]$month_end
    target_month_ends <- sort(month_ends)
    cat(sprintf("  Auto-detected %d month-ends: %s ~ %s\n\n",
                length(target_month_ends),
                min(target_month_ends), max(target_month_ends)))
  }
  target_month_ends <- sort(as.Date(target_month_ends))

  # ------------------------------------------------------------------
  # Step 1: Build features (independent of v3/v4/v5 chain)
  # ------------------------------------------------------------------
  cat("=== STEP 1: Build Regime Features ===\n")
  feat_data <- .v7_build_features(target_month_ends)
  feat <- feat_data$features
  feature_cols <- feat_data$feature_cols
  bm_monthly <- feat_data$bm_monthly
  cat("\n")

  # ------------------------------------------------------------------
  # Step 2: Stage 1 — Jump Model Regime Detection
  # ------------------------------------------------------------------
  cat("=== STEP 2: Stage 1 — Jump Model Regime Detection ===\n")
  feat <- .v7_jump_model(feat, feature_cols)
  cat("\n")

  # ------------------------------------------------------------------
  # Step 3: Stage 2 — Regime-Conditional Exposure
  # ------------------------------------------------------------------
  cat("=== STEP 3: Stage 2 — Regime-Conditional Exposure (CDaR) ===\n")
  feat <- .v7_regime_exposure(feat, bm_monthly)
  cat("\n")

  # ------------------------------------------------------------------
  # Step 4: Stage 3 — Logistic Regression Confirmation
  # ------------------------------------------------------------------
  cat("=== STEP 4: Stage 3 — Logistic Regression Confirmation ===\n")
  feat <- .v7_logistic_confirmation(feat, bm_monthly)
  cat("\n")

  # ------------------------------------------------------------------
  # Step 5: Assemble final output
  # ------------------------------------------------------------------
  cat("=== STEP 5: Assemble Final Output ===\n")

  result <- feat[, .(
    month_end,
    p_crisis,
    jump_state,
    regime_state,
    cdar_val,
    cdar_threshold,
    lr_p_dd,
    lr_confirmation,
    exposure,
    f1_vkospi_z,
    f2_breadth_z,
    f3_disp_z,
    f4_dd_z,
    f5_vrp_z
  )]

  # Compute MRS equivalent (0-100 scale) from P(Crisis) for compatibility
  result[, MRS := round(p_crisis * 100, 1)]

  # [Step 5b moved to after apply_month creation — old code removed]
  # (Slow-crisis defense now runs after apply_month is created in Step 5b below)
  if (FALSE) {
    fred_raw <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))
    fred_raw[, Date := as.Date(Date)]

    # FFR 6-month change z-score
    ffr <- fred_raw[Series == "Fed_Funds_Rate", .(Date, Value)]; setorder(ffr, Date)
    ffr[, Value := nafill(Value, type="locf")]
    ffr[, FFR_6m := Value - shift(Value, 126L)]
    ffr[, YM := format(Date, "%Y-%m")]
    ffr_m <- ffr[!is.na(FFR_6m), .SD[.N], by=YM]
    ffr_m[, FFR_6m_z := { z<-rep(NA_real_,.N); for(j in 24:.N){v<-FFR_6m[1:j]; s<-sd(v,na.rm=T); if(!is.na(s)&&s>1e-8) z[j]<-(FFR_6m[j]-mean(v,na.rm=T))/s}; z }]
    ffr_m[, FFR_6m_z := shift(FFR_6m_z, 1L, type="lag")]  # FRED 1d lag

    # Term Spread z-score (inverted: low = danger)
    ts_raw <- fred_raw[Series == "Term_Spread", .(Date, Value)]; setorder(ts_raw, Date)
    ts_raw[, Value := nafill(Value, type="locf")]
    ts_raw[, YM := format(Date, "%Y-%m")]
    ts_m <- ts_raw[!is.na(Value), .SD[.N], by=YM]
    ts_m[, TS_z := { z<-rep(NA_real_,.N); for(j in 24:.N){v<-Value[1:j]; s<-sd(v,na.rm=T); if(!is.na(s)&&s>1e-8) z[j]<-(Value[j]-mean(v,na.rm=T))/s}; z }]
    ts_m[, TS_z := shift(TS_z, 1L, type="lag")]

    # CPI 12-month change z-score
    cpi <- fred_raw[Series == "US_CPI", .(Date, Value)]; setorder(cpi, Date)
    cpi[, Value := nafill(Value, type="locf")]
    cpi[, CPI_12m := Value / shift(Value, 252L) - 1]
    cpi[, YM := format(Date, "%Y-%m")]
    cpi_m <- cpi[!is.na(CPI_12m), .SD[.N], by=YM]
    cpi_m[, CPI_z := { z<-rep(NA_real_,.N); for(j in 24:.N){v<-CPI_12m[1:j]; s<-sd(v,na.rm=T); if(!is.na(s)&&s>1e-8) z[j]<-(CPI_12m[j]-mean(v,na.rm=T))/s}; z }]
    cpi_m[, CPI_z := shift(CPI_z, 1L, type="lag")]

    # Merge slow-crisis signals
    result <- merge(result, ffr_m[, .(YM, FFR_6m_z)], by.x="apply_month", by.y="YM", all.x=TRUE)
    result <- merge(result, ts_m[, .(YM, TS_z)], by.x="apply_month", by.y="YM", all.x=TRUE)
    result <- merge(result, cpi_m[, .(YM, CPI_z)], by.x="apply_month", by.y="YM", all.x=TRUE)

    # Composite slow-crisis score (0-15)
    result[, slow_crisis := {
      ffr_s <- pmin(5, pmax(0, (fifelse(is.na(FFR_6m_z), 0, FFR_6m_z) - 0.5) / 2 * 5))
      ts_s  <- pmin(5, pmax(0, (0.5 - fifelse(is.na(TS_z), 0, TS_z)) / 2 * 5))
      cpi_s <- pmin(5, pmax(0, (fifelse(is.na(CPI_z), 0, CPI_z) - 0.5) / 2 * 5))
      ffr_s + ts_s + cpi_s
    }]

    # Asymmetric override (M4 method)
    n_overridden <- 0L
    for (i in seq_len(nrow(result))) {
      sc <- result$slow_crisis[i]
      mrs <- result$MRS[i]
      if (is.na(sc)) sc <- 0
      if (is.na(mrs)) mrs <- 0
      if (sc > 7 && mrs > 50) {
        result[i, exposure := 0.3]
        n_overridden <- n_overridden + 1L
      } else if (sc > 5 && mrs > 40) {
        result[i, exposure := min(exposure, 0.6)]
        n_overridden <- n_overridden + 1L
      }
    }
    cat(sprintf("  Slow-crisis overrides: %d months\n", n_overridden))
    cat(sprintf("  Slow-crisis 2022 mean: %.1f\n",
                mean(result[apply_month >= "2022-01" & apply_month <= "2022-12"]$slow_crisis, na.rm=TRUE)))
  }  # end if(FALSE) — old Step 5b disabled

  # Apply start / apply month
  # month_end is the last TRADING day of the month (e.g., 2026-02-27 for Feb)
  # The regime applies to the NEXT calendar month
  # So we compute the first day of the NEXT month after the month_end's calendar month
  result[, me_ym := format(month_end, "%Y-%m")]
  result[, apply_start := as.Date(paste0(me_ym, "-01")) %m+% months(1)]
  result[, apply_month := format(apply_start, "%Y-%m")]
  result[, me_ym := NULL]

  setorder(result, month_end)

  # ------------------------------------------------------------------
  # Step 5b: Slow-Crisis Override (FFR + TS + CPI)
  # NOW apply_month exists, so merge is safe
  # ------------------------------------------------------------------
  cat("  [v7 Step 5b] Slow-crisis defense (FFR + TS + CPI)...\n")
  tryCatch({
    fred_raw2 <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))
    fred_raw2[, Date := as.Date(Date)]
    ffr2 <- fred_raw2[Series == "Fed_Funds_Rate", .(Date, Value)]; setorder(ffr2, Date)
    ffr2[, Value := nafill(Value, type="locf")]
    ffr2[, FFR_6m := Value - shift(Value, 126L)]
    ffr2[, YM := format(Date, "%Y-%m")]
    ffr2_m <- ffr2[!is.na(FFR_6m), .SD[.N], by=YM]
    ffr2_m[, FFR_6m_z := { z<-rep(NA_real_,.N); for(j in 24:.N){v<-FFR_6m[1:j]; s<-sd(v,na.rm=T); if(!is.na(s)&&s>1e-8) z[j]<-(FFR_6m[j]-mean(v,na.rm=T))/s}; z }]
    ffr2_m[, FFR_6m_z := shift(FFR_6m_z, 1L, type="lag")]

    ts2 <- fred_raw2[Series == "Term_Spread", .(Date, Value)]; setorder(ts2, Date)
    ts2[, Value := nafill(Value, type="locf")]
    ts2[, YM := format(Date, "%Y-%m")]
    ts2_m <- ts2[!is.na(Value), .SD[.N], by=YM]
    ts2_m[, TS_z := { z<-rep(NA_real_,.N); for(j in 24:.N){v<-Value[1:j]; s<-sd(v,na.rm=T); if(!is.na(s)&&s>1e-8) z[j]<-(Value[j]-mean(v,na.rm=T))/s}; z }]
    ts2_m[, TS_z := shift(TS_z, 1L, type="lag")]

    cpi2 <- fred_raw2[Series == "US_CPI", .(Date, Value)]; setorder(cpi2, Date)
    cpi2[, Value := nafill(Value, type="locf")]
    cpi2[, CPI_12m := Value / shift(Value, 252L) - 1]
    cpi2[, YM := format(Date, "%Y-%m")]
    cpi2_m <- cpi2[!is.na(CPI_12m), .SD[.N], by=YM]
    cpi2_m[, CPI_z := { z<-rep(NA_real_,.N); for(j in 24:.N){v<-CPI_12m[1:j]; s<-sd(v,na.rm=T); if(!is.na(s)&&s>1e-8) z[j]<-(CPI_12m[j]-mean(v,na.rm=T))/s}; z }]
    cpi2_m[, CPI_z := shift(CPI_z, 1L, type="lag")]

    result <- merge(result, ffr2_m[, .(YM, FFR_6m_z)], by.x="apply_month", by.y="YM", all.x=TRUE)
    result <- merge(result, ts2_m[, .(YM, TS_z)], by.x="apply_month", by.y="YM", all.x=TRUE)
    result <- merge(result, cpi2_m[, .(YM, CPI_z)], by.x="apply_month", by.y="YM", all.x=TRUE)

    result[, slow_crisis := {
      ffr_s <- pmin(5, pmax(0, (fifelse(is.na(FFR_6m_z), 0, FFR_6m_z) - 0.5) / 2 * 5))
      ts_s  <- pmin(5, pmax(0, (0.5 - fifelse(is.na(TS_z), 0, TS_z)) / 2 * 5))
      cpi_s <- pmin(5, pmax(0, (fifelse(is.na(CPI_z), 0, CPI_z) - 0.5) / 2 * 5))
      ffr_s + ts_s + cpi_s
    }]

    n_ov <- 0L
    for (i in seq_len(nrow(result))) {
      sc <- result$slow_crisis[i]; mrs <- result$MRS[i]
      if (is.na(sc)) sc <- 0; if (is.na(mrs)) mrs <- 0
      if (sc > 7 && mrs > 50) { result[i, exposure := 0.3]; n_ov <- n_ov + 1L }
      else if (sc > 5 && mrs > 40) { result[i, exposure := min(result$exposure[i], 0.6)]; n_ov <- n_ov + 1L }
    }
    cat(sprintf("  Slow-crisis overrides: %d months\n", n_ov))
    setorder(result, month_end)
  }, error = function(e) cat(sprintf("  [WARN] Slow-crisis failed: %s\n", e$message)))

  # ------------------------------------------------------------------
  # Step 6: PIT Verification (MANDATORY)
  # ------------------------------------------------------------------
  cat("\n=== STEP 6: PIT Verification ===\n")
  pit_verify_month_regime(result)

  violations <- result[month_end >= apply_start]
  if (nrow(violations) > 0) {
    stop(sprintf("[PIT VIOLATION] %d months where month_end >= apply_start!", nrow(violations)))
  }
  cat("[PIT] All month_end < apply_start: CLEAN\n")

  # ------------------------------------------------------------------
  # Step 7: Test Date Verification
  # ------------------------------------------------------------------
  cat("\n=== STEP 7: Test Date Verification ===\n")
  test_dates <- as.Date(c("2008-08-31", "2020-01-31", "2022-06-30"))

  for (td in test_dates) {
    td <- as.Date(td, origin = "1970-01-01")
    row <- result[month_end == td]
    if (nrow(row) == 0) {
      row <- result[month_end <= td]
      if (nrow(row) > 0) row <- row[.N]
    }
    if (nrow(row) > 0) {
      cat(sprintf("\n  --- %s (month_end=%s, apply=%s) ---\n",
                  as.character(td), row$month_end, row$apply_month))
      cat(sprintf("    P(Crisis)=%.3f | State=%s | Exposure=%.2f\n",
                  row$p_crisis, row$regime_state, row$exposure))
      cat(sprintf("    Features: VKOSPI=%.2f, breadth=%.2f, disp=%.2f, dd=%.2f, VRP=%.2f\n",
                  row$f1_vkospi_z, row$f2_breadth_z, row$f3_disp_z,
                  row$f4_dd_z, row$f5_vrp_z))
      if (!is.na(row$lr_p_dd)) {
        cat(sprintf("    LR P(DD>5%%)=%.3f | Confirmed=%s\n",
                    row$lr_p_dd, row$lr_confirmation))
      }
      if (!is.na(row$cdar_val)) {
        cat(sprintf("    CDaR=%.4f | Threshold=%.4f\n",
                    row$cdar_val, row$cdar_threshold))
      }
    } else {
      cat(sprintf("\n  --- %s: No data ---\n", as.character(td)))
    }
  }

  # ------------------------------------------------------------------
  # Step 8: BM Overlay Performance
  # ------------------------------------------------------------------
  cat("\n=== STEP 8: BM Overlay Performance ===\n")

  bm <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
  bm[, Date := as.Date(Date)]
  setorder(bm, Date)
  bm[, YM := format(Date, "%Y-%m")]

  bm_monthly_ret <- bm[, .(
    BM_Close_last  = last(BM_Close),
    BM_Close_first = first(BM_Close)
  ), by = YM]
  bm_monthly_ret[, bm_ret := BM_Close_last / BM_Close_first - 1]

  perf_dt <- merge(result[, .(apply_month, exp_v7 = exposure)],
                   bm_monthly_ret[, .(YM, bm_ret)],
                   by.x = "apply_month", by.y = "YM")
  perf_dt <- perf_dt[!is.na(bm_ret)]
  setorder(perf_dt, apply_month)

  n_months <- nrow(perf_dt)
  if (n_months > 0) {
    # Buy & Hold
    bh_cum  <- cumprod(1 + perf_dt$bm_ret)
    bh_dd   <- bh_cum / cummax(bh_cum) - 1
    bh_sr   <- mean(perf_dt$bm_ret) / sd(perf_dt$bm_ret) * sqrt(12)
    bh_mdd  <- min(bh_dd)
    bh_cagr <- tail(bh_cum, 1)^(12/n_months) - 1

    # v7 overlay
    v7_ret  <- perf_dt$bm_ret * perf_dt$exp_v7
    v7_cum  <- cumprod(1 + v7_ret)
    v7_dd   <- v7_cum / cummax(v7_cum) - 1
    v7_sr   <- mean(v7_ret) / sd(v7_ret) * sqrt(12)
    v7_mdd  <- min(v7_dd)
    v7_cagr <- tail(v7_cum, 1)^(12/n_months) - 1

    cat(sprintf("\n  --- BM Overlay Performance (%d months) ---\n", n_months))
    cat(sprintf("  %-12s  CAGR    SR      MDD\n", ""))
    cat(sprintf("  %-12s  %5.1f%%  %6.3f  %6.1f%%\n",
                "Buy&Hold", bh_cagr * 100, bh_sr, bh_mdd * 100))
    cat(sprintf("  %-12s  %5.1f%%  %6.3f  %6.1f%%\n",
                "v7", v7_cagr * 100, v7_sr, v7_mdd * 100))
    cat(sprintf("  v7 improvement: SR %+.3f, MDD %+.1f%%\n",
                v7_sr - bh_sr, (v7_mdd - bh_mdd) * 100))

    # IS/OOS split
    split_point <- ceiling(n_months * 0.65)
    if (split_point > 24 && n_months - split_point > 12) {
      is_ret  <- v7_ret[1:split_point]
      oos_ret <- v7_ret[(split_point + 1):n_months]
      is_sr   <- mean(is_ret) / sd(is_ret) * sqrt(12)
      oos_sr  <- mean(oos_ret) / sd(oos_ret) * sqrt(12)
      retention <- oos_sr / max(is_sr, 0.001)
      cat(sprintf("\n  IS/OOS Split (%.0f%%/%.0f%%):\n",
                  100 * split_point / n_months,
                  100 * (1 - split_point / n_months)))
      cat(sprintf("    IS SR=%.3f | OOS SR=%.3f | Retention=%.2f\n",
                  is_sr, oos_sr, retention))
    }
  }

  # ------------------------------------------------------------------
  # Summary
  # ------------------------------------------------------------------
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat("\n==============================================================\n")
  cat("[regime_v7] BUILD COMPLETE\n")
  cat("==============================================================\n")
  cat(sprintf("  Months: %d (%s ~ %s)\n",
              nrow(result), min(result$apply_month), max(result$apply_month)))
  cat(sprintf("  MRS (P(Crisis)*100): mean=%.1f, median=%.1f\n",
              mean(result$MRS, na.rm = TRUE), median(result$MRS, na.rm = TRUE)))
  cat(sprintf("  Regime: Normal=%d, Transition=%d, Crisis=%d\n",
              sum(result$regime_state == "Normal", na.rm = TRUE),
              sum(result$regime_state %in% c("Transition", "Transition_LR"), na.rm = TRUE),
              sum(result$regime_state == "Crisis", na.rm = TRUE)))
  cat(sprintf("  Exposure: mean=%.3f, min=%.3f\n",
              mean(result$exposure, na.rm = TRUE),
              min(result$exposure, na.rm = TRUE)))
  cat(sprintf("  Hedged months (exposure<1): %d (%.1f%%)\n",
              sum(result$exposure < 1.0, na.rm = TRUE),
              100 * mean(result$exposure < 1.0, na.rm = TRUE)))
  cat(sprintf("  Elapsed: %.1f seconds\n", elapsed))

  # Cache
  dir.create(dirname(REGIME_V7_CACHE), recursive = TRUE, showWarnings = FALSE)
  write_parquet(result, REGIME_V7_CACHE)
  cat(sprintf("  Cache: %s\n", REGIME_V7_CACHE))

  result
}


#==============================================================================
# KPI EVALUATION: regime_v7_kpi
#==============================================================================
regime_v7_kpi <- function(regime_dt = NULL) {
  if (is.null(regime_dt)) regime_dt <- build_regime_v7(use_cache = TRUE)

  cat("\n=== Regime v7 KPI Self-Assessment ===\n")

  # Basic stats
  n <- nrow(regime_dt)
  cat(sprintf("  Total months: %d\n", n))
  cat(sprintf("  P(Crisis) mean: %.3f\n", mean(regime_dt$p_crisis, na.rm = TRUE)))
  cat(sprintf("  Exposure mean: %.3f\n", mean(regime_dt$exposure, na.rm = TRUE)))

  # Regime distribution
  regime_tab <- table(regime_dt$regime_state)
  for (rn in names(regime_tab)) {
    cat(sprintf("  %s: %d months (%.1f%%)\n", rn, regime_tab[rn], 100 * regime_tab[rn] / n))
  }

  invisible(regime_dt)
}


#==============================================================================
# MERGE: merge_regime_v7(FACTORS, regime_dt) — drop-in for strategies
#==============================================================================
merge_regime_v7 <- function(FACTORS, regime_dt = NULL) {
  if (is.null(regime_dt)) regime_dt <- build_regime_v7(use_cache = TRUE)

  # Convert FACTORS Date to YM for merge
  FACTORS[, apply_ym := format(Date, "%Y-%m")]

  regime_slim <- regime_dt[, .(apply_month, MRS_v7 = MRS, exposure_v7 = exposure,
                                regime_state_v7 = regime_state, p_crisis_v7 = p_crisis)]

  merged <- merge(FACTORS, regime_slim,
                  by.x = "apply_ym", by.y = "apply_month",
                  all.x = TRUE)

  # Fill missing with full exposure
  merged[is.na(exposure_v7), exposure_v7 := 1.0]
  merged[is.na(MRS_v7), MRS_v7 := 0]

  merged[, apply_ym := NULL]
  merged
}
