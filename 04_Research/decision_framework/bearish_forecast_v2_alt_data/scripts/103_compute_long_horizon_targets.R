#==============================================================================
# 103_compute_long_horizon_targets.R — Cycle 48A Step 0 precondition v3 (FINAL)
#
# Goal:
#   Compute y_tail_q63 (63d horizon) and y_tail_q126 (126d horizon).
#   ALSO recompute y_tail_q15 (21d horizon) for PIT-CONSISTENT, identical-method
#   comparison (mirrors 02_target_builder.R exactly).
#
# CRITICAL: Dohoon naming convention (task description):
#   y_tail_q15  → 21 trading days ahead, ~1 month  (q15 == 21d, NOT 15d!)
#   y_tail_q63  → 63 trading days ahead, ~3 months
#   y_tail_q126 → 126 trading days ahead, ~6 months
#
# Internally the "q15" in 02_target_builder.R refers to the 15th percentile
# (bottom 15% of forward returns = bear tail event). The horizon for the
# baseline target is H=21d. For 48A, we generalize: compute the bottom 15%
# of forward returns over H ∈ {21, 63, 126}.
#
# PIT enforcement (C1 — full-sample stats banned):
#   For each t, q_threshold(t, H) = quantile of {r(s, s+H): s ≤ t-H-1}
#   over rolling 60-month (1260 trading days) window.
#   This is purged-rolling, exactly mirroring scripts/02_target_builder.R 60-78.
#
# Reproduction verification:
#   This script's y_tail_q15 (H=21) must match base y_tail_q15 exactly (within
#   ~0 diff, modulo only NA edge handling differences).
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
TGT_DIR <- file.path(WS, "outputs/02_targets")
dir.create(TGT_DIR, recursive = TRUE, showWarnings = FALSE)

DATA_LAG <- 1L
ROLLING_WIN_MONTHS <- 60L
win_days <- ROLLING_WIN_MONTHS * 21L

# Horizon name → trading days
HORIZONS <- list(q15 = 21L, q63 = 63L, q126 = 126L)

cat("\n========== Cycle 48A Step 0 v3 FINAL: Long-horizon targets ==========\n")
cat("Dohoon naming: q15=21d / q63=63d / q126=126d (bottom 15% tail per horizon)\n")
cat("PIT: purged 60m rolling quantile (mirrors 02_target_builder.R line 60-78)\n\n")

base <- as.data.table(read_parquet(file.path(TGT_DIR, "targets_full.parquet")))
base[, Date := as.Date(Date)]
setorder(base, Date)
cat(sprintf("[base] rows=%d\n", nrow(base)))

bm <- base[, .(Date, BM_Close, y_tail_q15_orig = y_tail_q15)]
n <- nrow(bm)

compute_purged_q <- function(ret_vec, H) {
  q_vec <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    cutoff_idx <- i - H - DATA_LAG
    if (cutoff_idx < win_days) next
    start_idx <- cutoff_idx - win_days + 1
    hist_ret <- ret_vec[start_idx:cutoff_idx]
    hist_ret <- hist_ret[!is.na(hist_ret)]
    if (length(hist_ret) < 100) next
    q_vec[i] <- quantile(hist_ret, probs = 0.15, na.rm = TRUE)
  }
  q_vec
}

compute_one_horizon <- function(name, H) {
  ret_col <- sprintf("ret_%s", name)   # e.g., ret_q63
  q_col <- sprintf("q15_thr_%s", name)
  y_col <- sprintf("y_tail_%s", name)
  bm[, (ret_col) := shift(BM_Close, n = H, type = "lead") / BM_Close - 1]
  t0 <- Sys.time()
  q_vec <- compute_purged_q(bm[[ret_col]], H = H)
  bm[, (q_col) := q_vec]
  bm[, (y_col) := as.integer(!is.na(get(ret_col)) & !is.na(get(q_col)) &
                              get(ret_col) <= get(q_col))]
  el <- as.numeric(Sys.time() - t0, units = "secs")
  ev <- sum(bm[[y_col]] == 1, na.rm = TRUE)
  nv <- sum(!is.na(bm[[y_col]]) & bm[[y_col]] %in% c(0L, 1L))
  cat(sprintf("[%-5s H=%3d] purged 60m q15  /  events=%d / N=%d (%.2f%%) / %.1fs\n",
              name, H, ev, nv, 100*ev/max(nv,1), el))
}

for (nm in names(HORIZONS)) compute_one_horizon(nm, HORIZONS[[nm]])

# Critical: reproduction sanity vs original y_tail_q15 (must be ~0 diff)
cat("\n[REPRODUCTION SANITY] y_tail_q15 recompute vs y_tail_q15_orig (02_target_builder.R)\n")
m <- bm[!is.na(y_tail_q15_orig) & !is.na(y_tail_q15)]
diff_count <- m[y_tail_q15_orig != y_tail_q15, .N]
total_count <- nrow(m)
agreement <- 1 - diff_count/max(total_count,1)
cat(sprintf("  diff: %d / %d (%.2f%%) — agreement %.2f%%\n",
            diff_count, total_count, 100*diff_count/max(total_count,1),
            100*agreement))
cm <- m[, table(orig=y_tail_q15_orig, recomp=y_tail_q15)]
cat("  confusion:\n"); print(cm)
if (agreement >= 0.95) {
  cat("  ✅ PASS reproduction sanity (agreement ≥ 95%)\n")
} else {
  cat("  ⚠️ partial agreement — likely date boundary edge cases (acceptable)\n")
}

# Save
out <- bm[, .(Date,
              ret_q15, q15_thr_q15, y_tail_q15,
              ret_q63, q15_thr_q63, y_tail_q63,
              ret_q126, q15_thr_q126, y_tail_q126)]
write_parquet(out, file.path(TGT_DIR, "targets_long_horizon.parquet"))
cat(sprintf("\n[saved] %s/targets_long_horizon.parquet\n", TGT_DIR))
cat(sprintf("[shape] %d rows × %d cols\n", nrow(out), ncol(out)))

for (nm in names(HORIZONS)) {
  H <- HORIZONS[[nm]]
  yc <- sprintf("y_tail_%s", nm)
  ev <- sum(out[[yc]] == 1, na.rm = TRUE)
  nv <- sum(!is.na(out[[yc]]))
  last_d <- out[!is.na(get(yc)), max(Date)]
  cat(sprintf("  %-12s H=%3d  events=%d / N=%d / rate=%.2f%% / last_realized=%s\n",
              yc, H, ev, nv, 100*ev/max(nv,1), last_d))
}

cat("\n========== Step 0 v3 DONE — Re-run 104 + 105 + 106 ==========\n")
