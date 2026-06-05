#==============================================================================
# 02_target_builder.R — Y_onset + Y_tail_Q15/Q10 build (PIT purged)
#
# Plan v0.4.2 target definition (Codex round 3 precision D1 정합):
#   Y_onset(t)    = 1{ DD_252(t-1) > -0.10
#                      AND ∃ τ ∈ [t, t+h]: DD_252(τ) ≤ -0.10 최초 crossing }
#   Y_tail_Q15(t) = 1{ r(t, t+h) ≤ q_Q15_purged(t) }
#   Y_tail_Q10(t) = 1{ r(t, t+h) ≤ q_Q10_purged(t) }
#
# h = 21 trading days
# purged quantile: q(t) = quantile({r(s, s+h): s ≤ t-h-data_lag}, prob, window=60m)
# data_lag = 1 (conservative, observable label만)
#
# Output: outputs/02_targets/{y_onset, y_tail_q15, y_tail_q10, y_regime_strong}.parquet
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v1")
OUT_DIR <- file.path(WS_DIR, "outputs/02_targets")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

H <- 21L                # forecast horizon (trading days)
DATA_LAG <- 1L          # additional safety
ROLLING_WIN_MONTHS <- 60L   # 5 year rolling quantile

# ── 1. Load benchmark (KOSPI200 close) ────────────────────────
build_targets <- function() {
  bm_path <- file.path(PROJECT_ROOT, ".cache/benchmark.parquet")
  if (!file.exists(bm_path)) stop("[target] benchmark.parquet missing")
  bm <- as.data.table(read_parquet(bm_path))
  setorder(bm, Date)

  # Compute forward h-day return r(t, t+h)
  bm[, ret_h := shift(BM_Close, -H, type = "lead") / BM_Close - 1]

  # Compute DD_252 (running 1y peak-to-trough drawdown)
  bm[, peak_252 := frollapply(BM_Close, 252, max, na.rm = TRUE, align = "right")]
  bm[, dd_252 := BM_Close / peak_252 - 1]

  # ── 2. Y_onset (primary, event-onset) ──────────────────────
  # Forward h-day max DD breach
  bm[, dd_252_fwd_min := frollapply(dd_252, H, min, na.rm = TRUE, align = "left")]
  # shift to align with t+h window starting at t+1
  bm[, dd_252_fwd_min := shift(dd_252_fwd_min, -1, type = "lead")]

  bm[, y_onset := as.integer(
    !is.na(dd_252) & shift(dd_252, 1, type = "lag") > -0.10 &
    !is.na(dd_252_fwd_min) & dd_252_fwd_min <= -0.10
  )]

  # ── 3. Y_tail_Q15 / Q10 (purged quantile) ─────────────────
  # Trading days per month approx 21 → 60m = 1260 trading days lookback
  win_days <- ROLLING_WIN_MONTHS * 21L

  # Purged: 현 시점 t의 quantile은 s ≤ t-h-data_lag 데이터만 사용
  compute_purged_q <- function(probs) {
    n <- nrow(bm)
    q_vec <- rep(NA_real_, n)
    for (i in seq_len(n)) {
      cutoff_idx <- i - H - DATA_LAG
      if (cutoff_idx < win_days) next
      start_idx <- cutoff_idx - win_days + 1
      hist_ret <- bm$ret_h[start_idx:cutoff_idx]
      hist_ret <- hist_ret[!is.na(hist_ret)]
      if (length(hist_ret) < 100) next
      q_vec[i] <- quantile(hist_ret, probs = probs, na.rm = TRUE)
    }
    q_vec
  }

  bm[, q_q15_purged := compute_purged_q(0.15)]
  bm[, q_q10_purged := compute_purged_q(0.10)]

  bm[, y_tail_q15 := as.integer(!is.na(ret_h) & !is.na(q_q15_purged) & ret_h <= q_q15_purged)]
  bm[, y_tail_q10 := as.integer(!is.na(ret_h) & !is.na(q_q10_purged) & ret_h <= q_q10_purged)]

  # ── 4. Y_regime_strong (보조: DD -20% within h) ───────────
  bm[, y_regime_strong := as.integer(!is.na(dd_252_fwd_min) & dd_252_fwd_min <= -0.20)]

  # ── 5. Save targets + effective N audit ────────────────────
  targets <- bm[, .(Date, BM_Close, ret_h, dd_252, dd_252_fwd_min,
                    q_q15_purged, q_q10_purged,
                    y_onset, y_tail_q15, y_tail_q10, y_regime_strong)]

  write_parquet(targets, file.path(OUT_DIR, "targets_full.parquet"))

  # Effective N audit
  audit <- list(
    total_rows = nrow(targets),
    y_onset_events = sum(targets$y_onset, na.rm = TRUE),
    y_tail_q15_events = sum(targets$y_tail_q15, na.rm = TRUE),
    y_tail_q10_events = sum(targets$y_tail_q10, na.rm = TRUE),
    y_regime_strong_events = sum(targets$y_regime_strong, na.rm = TRUE),
    date_range = c(as.character(min(targets$Date)), as.character(max(targets$Date)))
  )
  jsonlite::write_json(audit, file.path(OUT_DIR, "effective_n_audit.json"),
                       auto_unbox = TRUE, pretty = TRUE)

  cat("[target_builder] PASS\n")
  cat(sprintf("  total rows: %d\n", audit$total_rows))
  cat(sprintf("  y_onset events: %d (%.2f%%)\n",
              audit$y_onset_events, 100 * audit$y_onset_events / audit$total_rows))
  cat(sprintf("  y_tail_q15 events: %d (%.2f%%)\n",
              audit$y_tail_q15_events, 100 * audit$y_tail_q15_events / audit$total_rows))
  cat(sprintf("  y_tail_q10 events: %d (%.2f%%)\n",
              audit$y_tail_q10_events, 100 * audit$y_tail_q10_events / audit$total_rows))
  cat(sprintf("  y_regime_strong events: %d (%.2f%%)\n",
              audit$y_regime_strong_events, 100 * audit$y_regime_strong_events / audit$total_rows))

  invisible(targets)
}

# If invoked directly
if (!interactive() && identical(sys.nframe(), 0L)) {
  build_targets()
}
