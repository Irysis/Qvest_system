#==============================================================================
# Regime Ensemble — Bayesian-Inspired Weighted Signal Combiner
#
# Author: Q-Lead Agent
# Date:   2026-03-17
#
# DESIGN:
#   Final combiner that loads ALL available regime signals and produces
#   a unified MRS_ensemble (0-100) with soft-ramp exposure.
#
#   Combining method: Bayesian-inspired F1-weighted average.
#   Each signal's weight = its expanding-window F1 score (track record).
#   F1 uses TP/FP/FN where "positive" = signal above threshold AND
#   next month had drawdown > 5%.
#
#   ALL computations use data available at month_end ONLY.
#   F1 weights use expanding window (no full-sample). Zero lookahead.
#
# SIGNALS LOADED (gracefully skips missing files):
#   1. Base v3 (regime_engine_v3.R)       — mandatory
#   2. Mahalanobis (regime_mahalanobis.R)  — optional
#   3. Absorption Ratio (regime_absorption.R) — optional
#   4. Logistic (regime_logistic.R)        — optional
#   5. HMM (regime_hmm.R)                 — optional
#   6. CUSUM (regime_cusum.R)             — optional
#
# USAGE:
#   source("02_Infrastructure/regime_ensemble.R")
#   ens <- build_regime_ensemble(month_ends)
#   regime_ensemble_kpi(ens)
#
# OUTPUT:
#   data.table(month_end, MRS_ensemble, exposure_ensemble,
#              MRS_v3, signal_cusum, ..., w_v3, w_cusum, ..., n_signals)
#==============================================================================

cat("[regime_ensemble] Loading...\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
}
if (!exists("CACHE_DIR")) {
  CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
}

INFRA_DIR <- file.path(PROJECT_ROOT, "02_Infrastructure")

#==============================================================================
# HELPER: Normalize signal to 0-100 range using expanding percentile
#==============================================================================
.normalize_signal <- function(x) {
  # Expanding-window percentile rank (no lookahead)
  n <- length(x)
  out <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (is.na(x[i])) next
    past <- x[1:i]
    past <- past[!is.na(past)]
    if (length(past) < 12) next  # need 12 months minimum
    out[i] <- mean(past <= x[i]) * 100
  }
  out
}

#==============================================================================
# HELPER: Expanding-window F1 score computation
#==============================================================================
.expanding_f1_weights <- function(signals_dt, bm_monthly, signal_cols,
                                  alert_threshold_pctile = 0.70,
                                  dd_threshold = -0.05) {
  # signals_dt: data.table with month_end + signal columns (0-100 normalized)
  # bm_monthly: data.table with month_end, next_month_ret
  # Returns: data.table with month_end + w_<signal> columns

  merged <- merge(signals_dt, bm_monthly, by = "month_end", all.x = TRUE)
  setorder(merged, month_end)
  n <- nrow(merged)

  # For each signal, compute expanding-window F1
  weight_cols <- paste0("w_", signal_cols)
  for (wc in weight_cols) merged[, (wc) := NA_real_]

  for (i in seq_len(n)) {
    if (i < 24) {
      # Not enough history; equal weight
      for (wc in weight_cols) set(merged, i, wc, 1.0)
      next
    }

    # Use data up to row i-1 for track record (no same-month leakage)
    hist <- merged[1:(i-1)]
    hist <- hist[!is.na(next_month_ret)]
    if (nrow(hist) < 12) {
      for (wc in weight_cols) set(merged, i, wc, 1.0)
      next
    }

    # Ground truth: did next month have DD > 5%?
    hist[, actual_bad := fifelse(next_month_ret < dd_threshold, 1L, 0L)]

    for (j in seq_along(signal_cols)) {
      sc <- signal_cols[j]
      wc <- weight_cols[j]

      sig_vals <- hist[[sc]]
      valid <- !is.na(sig_vals)
      if (sum(valid) < 12) {
        set(merged, i, wc, 1.0)
        next
      }

      # Dynamic threshold: 70th percentile of expanding history
      thresh <- quantile(sig_vals[valid], probs = alert_threshold_pctile, na.rm = TRUE)

      predicted_bad <- fifelse(!is.na(sig_vals) & sig_vals > thresh, 1L, 0L)
      actual <- hist$actual_bad

      TP <- sum(predicted_bad == 1L & actual == 1L, na.rm = TRUE)
      FP <- sum(predicted_bad == 1L & actual == 0L, na.rm = TRUE)
      FN <- sum(predicted_bad == 0L & actual == 1L, na.rm = TRUE)

      precision <- if ((TP + FP) > 0) TP / (TP + FP) else 0
      recall    <- if ((TP + FN) > 0) TP / (TP + FN) else 0
      f1 <- if ((precision + recall) > 0) 2 * precision * recall / (precision + recall) else 0.01

      # Floor at 0.01 to avoid zero weights
      set(merged, i, wc, max(0.01, f1))
    }
  }

  # Return only month_end + weight columns
  merged[, c("month_end", weight_cols), with = FALSE]
}


#==============================================================================
# MAIN: build_regime_ensemble
#==============================================================================
build_regime_ensemble <- function(month_ends = NULL) {

  cat("[ensemble] Building Bayesian-weighted regime ensemble...\n")

  # ─── 1. Load base v3 (mandatory) ─────────────────────────────────────────
  v3_path <- file.path(REGIME_DIR, "regime_engine_v3.R")
  if (!file.exists(v3_path)) stop("[ensemble] regime_engine_v3.R not found!")
  if (!exists("build_regime_v3")) source(v3_path)

  if (is.null(month_ends)) {
    v3 <- build_regime_v3()
    month_ends <- v3$month_end
  } else {
    month_ends <- sort(as.Date(month_ends))
    v3 <- build_regime_v3(target_month_ends = month_ends)
  }

  signals <- v3[, .(month_end, MRS_v3 = MRS)]
  signal_cols <- c("MRS_v3")
  cat(sprintf("  [1] Base v3: %d months loaded\n", nrow(v3)))

  # ─── 2. Load Mahalanobis (optional) ──────────────────────────────────────
  maha_path <- file.path(REGIME_DIR, "regime_mahalanobis.R")
  if (file.exists(maha_path)) {
    tryCatch({
      if (!exists("compute_mahalanobis_signal")) source(maha_path)
      maha <- compute_mahalanobis_signal(month_ends)
      # Detect output column: maha_score or maha_pctile
      maha_col <- intersect(c("maha_score", "maha_pctile"), names(maha))[1]
      if (!is.na(maha_col)) {
        signals <- merge(signals, maha[, .(month_end, signal_maha = get(maha_col) * 100)],
                         by = "month_end", all.x = TRUE)
        signal_cols <- c(signal_cols, "signal_maha")
        cat(sprintf("  [2] Mahalanobis: loaded (col=%s)\n", maha_col))
      }
    }, error = function(e) cat(sprintf("  [2] Mahalanobis: SKIP (%s)\n", e$message)))
  } else {
    cat("  [2] Mahalanobis: file not found, skipping\n")
  }

  # ─── 3. Load Absorption Ratio (optional) ─────────────────────────────────
  abs_path <- file.path(REGIME_DIR, "regime_absorption.R")
  if (file.exists(abs_path)) {
    tryCatch({
      if (!exists("compute_absorption_signal")) source(abs_path)
      abs_dt <- compute_absorption_signal(month_ends)
      if ("absorption_score" %in% names(abs_dt)) {
        signals <- merge(signals, abs_dt[, .(month_end, signal_absorption = absorption_score)],
                         by = "month_end", all.x = TRUE)
        signal_cols <- c(signal_cols, "signal_absorption")
        cat(sprintf("  [3] Absorption Ratio: loaded\n"))
      }
    }, error = function(e) cat(sprintf("  [3] Absorption Ratio: SKIP (%s)\n", e$message)))
  } else {
    cat("  [3] Absorption Ratio: file not found, skipping\n")
  }

  # ─── 4. Load Logistic (optional) ─────────────────────────────────────────
  logistic_path <- file.path(REGIME_DIR, "regime_logistic.R")
  if (file.exists(logistic_path)) {
    tryCatch({
      if (!exists("compute_logistic_signal")) source(logistic_path)
      log_dt <- compute_logistic_signal(month_ends)
      if ("logistic_score" %in% names(log_dt)) {
        signals <- merge(signals, log_dt[, .(month_end, signal_logistic = logistic_score)],
                         by = "month_end", all.x = TRUE)
        signal_cols <- c(signal_cols, "signal_logistic")
        cat(sprintf("  [4] Logistic: loaded\n"))
      }
    }, error = function(e) cat(sprintf("  [4] Logistic: SKIP (%s)\n", e$message)))
  } else {
    cat("  [4] Logistic: file not found, skipping\n")
  }

  # ─── 5. Load HMM (optional) ──────────────────────────────────────────────
  hmm_path <- file.path(REGIME_DIR, "regime_hmm.R")
  if (file.exists(hmm_path)) {
    tryCatch({
      if (!exists("compute_hmm_signal")) source(hmm_path)
      hmm_dt <- compute_hmm_signal(month_ends)
      # Detect output column: hmm_score or p_stress
      hmm_col <- intersect(c("hmm_score", "p_stress"), names(hmm_dt))[1]
      if (!is.na(hmm_col)) {
        signals <- merge(signals, hmm_dt[, .(month_end, signal_hmm = get(hmm_col) * 100)],
                         by = "month_end", all.x = TRUE)
        signal_cols <- c(signal_cols, "signal_hmm")
        cat(sprintf("  [5] HMM: loaded (col=%s)\n", hmm_col))
      }
    }, error = function(e) cat(sprintf("  [5] HMM: SKIP (%s)\n", e$message)))
  } else {
    cat("  [5] HMM: file not found, skipping\n")
  }

  # ─── 6. Load CUSUM (optional) ────────────────────────────────────────────
  cusum_path <- file.path(REGIME_DIR, "regime_cusum.R")
  if (file.exists(cusum_path)) {
    tryCatch({
      if (!exists("compute_cusum_signal")) source(cusum_path)
      cusum_dt <- compute_cusum_signal(month_ends)
      # Convert cusum to 0-100 scale: cusum_alert*50 + cusum_val normalized
      # cusum_val is continuous; normalize via expanding percentile
      cusum_dt[, cusum_pctile := .normalize_signal(cusum_val)]
      cusum_dt[, signal_cusum := pmin(100, cusum_alert * 40 + cusum_pctile * 0.6)]
      signals <- merge(signals, cusum_dt[, .(month_end, signal_cusum)],
                       by = "month_end", all.x = TRUE)
      signal_cols <- c(signal_cols, "signal_cusum")
      cat(sprintf("  [6] CUSUM: loaded\n"))
    }, error = function(e) cat(sprintf("  [6] CUSUM: SKIP (%s)\n", e$message)))
  } else {
    cat("  [6] CUSUM: file not found, skipping\n")
  }

  cat(sprintf("  Active signals: %d (%s)\n", length(signal_cols), paste(signal_cols, collapse = ", ")))
  setorder(signals, month_end)

  # ─── Normalize all signals to 0-100 using expanding percentile ──────────
  for (sc in signal_cols) {
    raw <- signals[[sc]]
    signals[, (sc) := .normalize_signal(raw)]
  }

  # ─── Compute BM next-month returns (for F1 track record) ────────────────
  bm <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
  bm[, Date := as.Date(Date)]
  setorder(bm, Date)
  bm[, YM := format(Date, "%Y-%m")]
  bm_monthly <- bm[, .(BM_last = last(BM_Close)), by = YM]
  setorder(bm_monthly, YM)
  bm_monthly[, next_month_ret := shift(BM_last, -1L, type = "lead") / BM_last - 1]

  # Map month_end -> YM for merge
  me_ym <- data.table(month_end = signals$month_end)
  me_ym[, YM := format(month_end, "%Y-%m")]
  bm_for_f1 <- merge(me_ym, bm_monthly[, .(YM, next_month_ret)], by = "YM", all.x = TRUE)
  # IMPORTANT: next_month_ret is the return of the MONTH AFTER month_end.
  # This is used ONLY for evaluating past track record in expanding window.
  # At time t, we only look at returns up to t-1 for F1 computation.

  # ─── Compute expanding-window F1 weights ────────────────────────────────
  cat("  Computing expanding-window F1 weights...\n")
  weights_dt <- .expanding_f1_weights(
    signals_dt = copy(signals),
    bm_monthly = bm_for_f1[, .(month_end, next_month_ret)],
    signal_cols = signal_cols,
    alert_threshold_pctile = 0.70,
    dd_threshold = -0.05
  )

  result <- merge(signals, weights_dt, by = "month_end", all.x = TRUE)
  setorder(result, month_end)

  # ─── Compute ensemble MRS ───────────────────────────────────────────────
  weight_cols <- paste0("w_", signal_cols)

  result[, MRS_ensemble := {
    mrs <- numeric(.N)
    for (row_i in seq_len(.N)) {
      sigs <- numeric(0)
      wts  <- numeric(0)
      for (j in seq_along(signal_cols)) {
        s <- .SD[[signal_cols[j]]][row_i]
        w <- .SD[[weight_cols[j]]][row_i]
        if (!is.na(s) && !is.na(w)) {
          sigs <- c(sigs, s)
          wts  <- c(wts, w)
        }
      }
      if (length(sigs) > 0 && sum(wts) > 0) {
        wts_norm <- wts / sum(wts)
        mrs[row_i] <- sum(wts_norm * sigs)
      } else {
        mrs[row_i] <- NA_real_
      }
    }
    mrs
  }, .SDcols = c(signal_cols, weight_cols)]

  # Clamp to 0-100
  result[, MRS_ensemble := pmin(100, pmax(0, MRS_ensemble))]

  # Soft ramp exposure — MRS_ensemble is 0-100 percentile-normalized
  # lo=30 (below = full exposure), hi=80 (above = zero exposure)
  # This maps to: ~30th pctile = normal, ~80th pctile = extreme risk
  result[, exposure_ensemble := pmax(0, pmin(1, 1 - (MRS_ensemble - 30) / 50))]

  # Metadata
  result[, n_signals := length(signal_cols)]
  result[, apply_start := month_end + 1L]
  result[, apply_month := format(apply_start, "%Y-%m")]

  cat(sprintf("\n[ensemble] Built: %d months, %d signals\n", nrow(result), length(signal_cols)))
  cat(sprintf("  MRS_ensemble: mean=%.1f, median=%.1f, max=%.0f\n",
              mean(result$MRS_ensemble, na.rm = TRUE),
              median(result$MRS_ensemble, na.rm = TRUE),
              max(result$MRS_ensemble, na.rm = TRUE)))
  cat(sprintf("  Exposure: mean=%.2f, min=%.2f\n",
              mean(result$exposure_ensemble, na.rm = TRUE),
              min(result$exposure_ensemble, na.rm = TRUE)))

  # Print weight summary for last available month
  last_row <- result[!is.na(MRS_ensemble)][.N]
  if (nrow(result[!is.na(MRS_ensemble)]) > 0) {
    cat("  Latest weights: ")
    for (wc in weight_cols) {
      cat(sprintf("%s=%.3f ", wc, last_row[[wc]]))
    }
    cat("\n")
  }

  result
}


#==============================================================================
# KPI EVALUATION: regime_ensemble_kpi
#==============================================================================
regime_ensemble_kpi <- function(ens_dt = NULL) {
  if (is.null(ens_dt)) ens_dt <- build_regime_ensemble()

  cat("==============================================================\n")
  cat("[regime_ensemble] KPI EVALUATION\n")
  cat("==============================================================\n\n")

  # Load BM monthly returns
  bm <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
  bm[, Date := as.Date(Date)]
  setorder(bm, Date)
  bm[, YM := format(Date, "%Y-%m")]
  bm_monthly <- bm[, .(
    BM_Close_last  = last(BM_Close),
    BM_Close_first = first(BM_Close)
  ), by = YM]
  bm_monthly[, bm_ret := BM_Close_last / BM_Close_first - 1]

  # Also compute drawdown from peak for each month
  bm_monthly[, cum := cumprod(1 + bm_ret)]
  bm_monthly[, peak := cummax(cum)]
  bm_monthly[, dd := cum / peak - 1]

  merged <- merge(ens_dt[, .(apply_month, MRS_ensemble, exposure_ensemble, MRS_v3)],
                  bm_monthly[, .(YM, bm_ret, dd)],
                  by.x = "apply_month", by.y = "YM", all.x = TRUE)
  merged <- merged[!is.na(bm_ret) & !is.na(MRS_ensemble)]
  setorder(merged, apply_month)

  cat(sprintf("  Data: %d months\n\n", nrow(merged)))

  # ─── KPI 1: DD>10% Recall ─────────────────────────────────────────────
  cat("--- KPI 1: DRAWDOWN RECALL ---\n")
  # DD > 10%: months where cumulative drawdown exceeded 10%
  merged[, next_ret := shift(bm_ret, -1L, type = "lead")]
  merged[, bad_10pct := fifelse(next_ret < -0.10, 1L, 0L)]
  merged[, bad_5pct  := fifelse(next_ret < -0.05, 1L, 0L)]

  for (thresh_name in c("DD>10%", "DD>5%")) {
    bad_col <- if (thresh_name == "DD>10%") "bad_10pct" else "bad_5pct"
    for (mrs_thresh in c(60, 70, 80)) {
      high_mrs <- merged[MRS_ensemble > mrs_thresh]
      n_bad <- sum(merged[[bad_col]] == 1L, na.rm = TRUE)
      if (n_bad > 0) {
        detected <- sum(high_mrs[[bad_col]] == 1L, na.rm = TRUE)
        recall <- detected / n_bad
        cat(sprintf("  %s, MRS>%d: recall=%.1f%% (%d/%d)\n",
                    thresh_name, mrs_thresh, recall * 100, detected, n_bad))
      }
    }
  }

  # ─── KPI 2: False Positive Rate ────────────────────────────────────────
  cat("\n--- KPI 2: FALSE POSITIVE RATE ---\n")
  for (mrs_thresh in c(60, 70, 80)) {
    flagged <- merged[MRS_ensemble > mrs_thresh]
    if (nrow(flagged) > 0) {
      fp <- sum(flagged$next_ret > 0, na.rm = TRUE)
      fpr <- fp / nrow(flagged)
      cat(sprintf("  MRS>%d: FP rate=%.1f%% (%d flagged, %d false)\n",
                  mrs_thresh, fpr * 100, nrow(flagged), fp))
    }
  }

  # ─── KPI 3: Regime Separation ──────────────────────────────────────────
  cat("\n--- KPI 3: REGIME SEPARATION ---\n")
  for (thresh in c(40, 50, 60)) {
    on  <- merged[MRS_ensemble <= thresh]
    off <- merged[MRS_ensemble > thresh]
    if (nrow(on) > 3 && nrow(off) > 3) {
      sr_on   <- mean(on$bm_ret) / sd(on$bm_ret) * sqrt(12)
      sr_off  <- mean(off$bm_ret) / sd(off$bm_ret) * sqrt(12)
      vol_on  <- sd(on$bm_ret) * sqrt(12) * 100
      vol_off <- sd(off$bm_ret) * sqrt(12) * 100
      cat(sprintf("  MRS>%d: RISK_ON SR=%.2f(vol %.0f%%) | RISK_OFF SR=%.2f(vol %.0f%%) | N=%d/%d\n",
                  thresh, sr_on, vol_on, sr_off, vol_off, nrow(on), nrow(off)))
    }
  }

  # ─── KPI 4: SR Cost vs Buy-and-Hold ───────────────────────────────────
  cat("\n--- KPI 4: VALUE-ADDED (Ensemble vs B&H vs Base v3) ---\n")
  n_months <- nrow(merged)

  # Buy & Hold
  bh_cum <- cumprod(1 + merged$bm_ret)
  bh_dd  <- bh_cum / cummax(bh_cum) - 1
  bh_sr  <- mean(merged$bm_ret) / sd(merged$bm_ret) * sqrt(12)
  bh_mdd <- min(bh_dd)
  bh_cagr <- (tail(bh_cum, 1))^(12/n_months) - 1

  # Ensemble overlay
  ens_ret <- merged$bm_ret * merged$exposure_ensemble
  ens_cum <- cumprod(1 + ens_ret)
  ens_dd  <- ens_cum / cummax(ens_cum) - 1
  ens_sr  <- mean(ens_ret) / sd(ens_ret) * sqrt(12)
  ens_mdd <- min(ens_dd)
  ens_cagr <- (tail(ens_cum, 1))^(12/n_months) - 1

  # Base v3 overlay (for comparison)
  if ("MRS_v3" %in% names(merged) && sum(!is.na(merged$MRS_v3)) > 0) {
    # Reconstruct v3 exposure using same ramp
    merged[, exposure_v3 := pmax(0, pmin(1, 1 - (MRS_v3 - 5) / 20))]
    v3_ret <- merged$bm_ret * merged$exposure_v3
    v3_cum <- cumprod(1 + v3_ret)
    v3_dd  <- v3_cum / cummax(v3_cum) - 1
    v3_sr  <- mean(v3_ret) / sd(v3_ret) * sqrt(12)
    v3_mdd <- min(v3_dd)
    v3_cagr <- (tail(v3_cum, 1))^(12/n_months) - 1
  } else {
    v3_sr <- v3_mdd <- v3_cagr <- NA
  }

  mdd_imp_ens <- (abs(bh_mdd) - abs(ens_mdd)) * 100
  sr_cost_ens <- bh_sr - ens_sr

  cat(sprintf("  Buy&Hold:  CAGR=%.1f%%, SR=%.3f, MDD=%.1f%%\n",
              bh_cagr * 100, bh_sr, bh_mdd * 100))
  if (!is.na(v3_sr)) {
    mdd_imp_v3 <- (abs(bh_mdd) - abs(v3_mdd)) * 100
    sr_cost_v3 <- bh_sr - v3_sr
    cat(sprintf("  Base v3:   CAGR=%.1f%%, SR=%.3f, MDD=%.1f%% (MDD+%.1f%%p, SR cost %.3f)\n",
                v3_cagr * 100, v3_sr, v3_mdd * 100, mdd_imp_v3, sr_cost_v3))
  }
  cat(sprintf("  Ensemble:  CAGR=%.1f%%, SR=%.3f, MDD=%.1f%% (MDD+%.1f%%p, SR cost %.3f)\n",
              ens_cagr * 100, ens_sr, ens_mdd * 100, mdd_imp_ens, sr_cost_ens))

  # ─── KPI 5: Crisis Period Performance ─────────────────────────────────
  cat("\n--- KPI 5: CRISIS PERIOD DETAIL ---\n")
  crisis_periods <- list(
    "GFC 2008"       = c("2008-09", "2009-03"),
    "COVID 2020"     = c("2020-02", "2020-04"),
    "Rate Hike 2022" = c("2022-01", "2022-10")
  )
  for (nm in names(crisis_periods)) {
    period <- crisis_periods[[nm]]
    sub <- merged[apply_month >= period[1] & apply_month <= period[2]]
    if (nrow(sub) == 0) next
    bh_r  <- prod(1 + sub$bm_ret) - 1
    ens_r <- prod(1 + sub$bm_ret * sub$exposure_ensemble) - 1
    v3_r  <- if ("exposure_v3" %in% names(sub)) prod(1 + sub$bm_ret * sub$exposure_v3) - 1 else NA
    cat(sprintf("  %-16s: BH=%.1f%%, Ensemble=%.1f%%, v3=%.1f%%, Saved=%.1f%%p\n",
                nm, bh_r*100, ens_r*100,
                ifelse(is.na(v3_r), NA, v3_r*100),
                (ens_r - bh_r)*100))
  }

  # ─── Signal Weight Summary ─────────────────────────────────────────────
  cat("\n--- SIGNAL WEIGHT EVOLUTION ---\n")
  weight_cols <- grep("^w_", names(ens_dt), value = TRUE)
  if (length(weight_cols) > 0) {
    # Show weights at 3 timepoints
    valid_rows <- ens_dt[!is.na(MRS_ensemble)]
    n_valid <- nrow(valid_rows)
    if (n_valid >= 3) {
      idx <- c(1, ceiling(n_valid/2), n_valid)
      for (ii in idx) {
        row <- valid_rows[ii]
        cat(sprintf("  %s: ", row$month_end))
        total_w <- 0
        for (wc in weight_cols) total_w <- total_w + row[[wc]]
        for (wc in weight_cols) {
          cat(sprintf("%s=%.1f%% ", wc, row[[wc]] / total_w * 100))
        }
        cat("\n")
      }
    }
  }

  # ─── OVERALL SUMMARY ──────────────────────────────────────────────────
  cat("\n==============================================================\n")
  cat(sprintf("  Ensemble: %d signals, %d months\n", ens_dt$n_signals[1], nrow(merged)))
  cat(sprintf("  SR cost vs B&H:     %.3f %s\n",
              sr_cost_ens, ifelse(sr_cost_ens < 0.05, "[EXCELLENT]",
                                  ifelse(sr_cost_ens < 0.10, "[GOOD]", "[HIGH]"))))
  cat(sprintf("  MDD improvement:    %.1f%%p %s\n",
              mdd_imp_ens, ifelse(mdd_imp_ens >= 15, "[EXCELLENT]",
                                  ifelse(mdd_imp_ens >= 10, "[GOOD]", "[WEAK]"))))
  if (!is.na(v3_sr)) {
    ens_vs_v3 <- ens_sr - v3_sr
    cat(sprintf("  Ensemble vs v3 SR:  %+.3f %s\n",
                ens_vs_v3, ifelse(ens_vs_v3 > 0, "[ENSEMBLE BETTER]", "[V3 BETTER]")))
    ens_vs_v3_mdd <- abs(v3_mdd) - abs(ens_mdd)
    cat(sprintf("  Ensemble vs v3 MDD: %+.1f%%p %s\n",
                ens_vs_v3_mdd * 100,
                ifelse(ens_vs_v3_mdd > 0, "[ENSEMBLE BETTER]", "[V3 BETTER]")))
  }
  cat("==============================================================\n")

  invisible(list(
    bh_sr = bh_sr, bh_mdd = bh_mdd, bh_cagr = bh_cagr,
    ens_sr = ens_sr, ens_mdd = ens_mdd, ens_cagr = ens_cagr,
    v3_sr = v3_sr, v3_mdd = v3_mdd, v3_cagr = v3_cagr,
    mdd_improvement_pct = mdd_imp_ens, sr_cost = sr_cost_ens,
    n_signals = ens_dt$n_signals[1]
  ))
}


cat("[regime_ensemble] Loaded. Functions:\n")
cat("  build_regime_ensemble(month_ends)  -- Bayesian F1-weighted combiner\n")
cat("  regime_ensemble_kpi(ens_dt)        -- KPI evaluation + comparison\n")
