#==============================================================================
# 138_cycle54b_abs15_reeval.R
#
# Cycle 54B — y_tail_q126_abs15 Primary 전환 + 모든 cycle re-baseline
#
# Phase 1: abs15 label 추가 (targets_long_horizon_with_abs15.parquet 생성)
#          abs15 = 1{ret_q126 <= -0.15}, regime-invariant
# Phase 2: 모든 cycle predictions re-evaluate (PR-AUC orig vs abs15)
#          + Period-balanced (S2018-19 / S2020-21 / S2022-24 / S2025-26) per cycle per label
#          + IC rank + bootstrap CI (block_len=21, B=1000)
# Phase 3: Robustness verdict (best label per metric, ranking 일관성)
# Phase 4: Visualization (139_cycle54b_label_compare.png)
#
# CPU only, no retraining; re-evaluate existing predictions.
# Pre-cycle bear_date_audit PASS (4/4 — Lehman/Euro/COVID/Stagflation, 21d)
# AX-008: 2-source (Forge + Codex code review only — design verdict by Q-Lead)
#
# Author: Forge agent
# Date: 2026-05-21
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
  library(ggplot2)
  library(patchwork)
})

set.seed(20260521L)

ROOT <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "04_Research/decision_framework/bearish_forecast_v2_alt_data")
setwd(ROOT)

EVAL_DIR <- file.path(ROOT, "outputs/04_evaluation")
CHART_DIR <- file.path(ROOT, "outputs/06_reports/charts")
TARGET_DIR <- file.path(ROOT, "outputs/02_targets")
dir.create(EVAL_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(CHART_DIR, showWarnings = FALSE, recursive = TRUE)

cat("=============================================================\n")
cat("Cycle 54B — y_tail_q126_abs15 Primary 전환 + Re-baseline\n")
cat("=============================================================\n\n")

# `%||%` operator — defined early per Codex review item 8 (defensive: R 4.5+ base has %||%
# with different semantics; explicit local defn overrides for NA handling).
`%||%` <- function(a, b) if (is.null(a) || (is.numeric(a) && is.na(a))) b else a

#==============================================================================
# Utility — PR-AUC (anchored trapezoidal) and IC rank
#==============================================================================
# Anchored PR-AUC (Codex review BUG #2 fix): integrate only at recall-change points
# (positive hits), prepending (rec=0, prec=1). Perfect ranking → 1.0 (not 1 - 1/events).
pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y)
  p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5 || sum(y) == length(y)) return(NA_real_)
  ord <- order(p, decreasing = TRUE)
  y_ord <- y[ord]
  tp <- cumsum(y_ord)
  pos <- which(y_ord == 1L)
  if (length(pos) == 0L) return(NA_real_)
  rec <- c(0, tp[pos] / sum(y_ord))
  prec <- c(1, tp[pos] / pos)
  n <- length(prec)
  sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

ic_rank <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sd(p) < 1e-30 || sd(y) < 1e-30) return(NA_real_)
  cor(rank(p), rank(y), method = "pearson")
}

# Moving-block bootstrap PR-AUC CI
pr_auc_bootstrap_ci <- function(p, y, B = 1000L, block_len = 21L, alpha = 0.05) {
  ok <- !is.na(p) & !is.na(y)
  if (sum(ok) < 60 || sum(y[ok]) < 10) {
    return(list(pr_auc = pr_auc(p, y), lo = NA_real_, hi = NA_real_, B_eff = 0L))
  }
  p <- p[ok]; y <- y[ok]; n <- length(p)
  n_blocks <- ceiling(n / block_len)
  starts_max <- n - block_len + 1L
  if (starts_max < 1L) {
    return(list(pr_auc = pr_auc(p, y), lo = NA_real_, hi = NA_real_, B_eff = 0L))
  }
  boot_vals <- numeric(B)
  for (b in seq_len(B)) {
    starts <- sample.int(starts_max, n_blocks, replace = TRUE)
    idx <- unlist(lapply(starts, function(s) s:(s + block_len - 1L)))
    idx <- idx[seq_len(n)]
    boot_vals[b] <- pr_auc(p[idx], y[idx])
  }
  boot_vals <- boot_vals[!is.na(boot_vals)]
  if (length(boot_vals) < 30L) {
    return(list(pr_auc = pr_auc(p, y), lo = NA_real_, hi = NA_real_, B_eff = length(boot_vals)))
  }
  list(
    pr_auc = pr_auc(p, y),
    lo = unname(quantile(boot_vals, alpha / 2)),
    hi = unname(quantile(boot_vals, 1 - alpha / 2)),
    B_eff = length(boot_vals)
  )
}

#==============================================================================
# Phase 1 — abs15 label 생성 + targets_long_horizon_with_abs15.parquet
#==============================================================================
cat("=== Phase 1: abs15 label 생성 ===\n")
lh_path <- file.path(TARGET_DIR, "targets_long_horizon.parquet")
lh <- as.data.table(read_parquet(lh_path))
setorder(lh, Date)

# abs15: 1 iff ret_q126 ≤ -0.15 (fixed threshold, regime-invariant)
# NA-safe: NA in ret_q126 → NA in abs15 (consistent with y_tail_q126 NA handling)
lh[, y_tail_q126_abs15 := as.integer(ret_q126 <= -0.15)]
# Also abs10 for diagnostic
lh[, y_tail_q126_abs10 := as.integer(ret_q126 <= -0.10)]

# Verify abs15 events
n_abs15 <- sum(lh$y_tail_q126_abs15, na.rm = TRUE)
n_orig <- sum(lh$y_tail_q126, na.rm = TRUE)
n_obs_q126 <- sum(!is.na(lh$y_tail_q126_abs15))

cat(sprintf("y_tail_q126_orig events: %d / %d (rate=%.4f)\n", n_orig, n_obs_q126,
            n_orig / n_obs_q126))
cat(sprintf("y_tail_q126_abs15 events: %d / %d (rate=%.4f)\n", n_abs15, n_obs_q126,
            n_abs15 / n_obs_q126))
cat(sprintf("y_tail_q126_abs10 events: %d / %d (rate=%.4f)\n",
            sum(lh$y_tail_q126_abs10, na.rm = TRUE), n_obs_q126,
            sum(lh$y_tail_q126_abs10, na.rm = TRUE) / n_obs_q126))

# Sanity check abs15 on 3 known dates (forward 126d)
sanity_dates <- list(
  list(name = "Lehman GFC", date = as.Date("2008-09-12")),  # used_date from audit
  list(name = "COVID", date = as.Date("2020-02-19")),
  list(name = "Stagflation 2022", date = as.Date("2022-09-26"))
)
cat("\nSanity (3 dates) — abs15:\n")
for (sd_ in sanity_dates) {
  row <- lh[Date == sd_$date]
  if (nrow(row) > 0) {
    cat(sprintf("  %s @ %s: ret_q126=%+.4f, abs15=%d, abs10=%d, orig=%d\n",
                sd_$name, as.character(sd_$date), row$ret_q126,
                row$y_tail_q126_abs15, row$y_tail_q126_abs10, row$y_tail_q126))
  }
}

# Save augmented targets
out_path <- file.path(TARGET_DIR, "targets_long_horizon_with_abs15.parquet")
write_parquet(lh, out_path)
cat(sprintf("\nSaved: %s (%d rows, %d cols)\n", basename(out_path), nrow(lh), ncol(lh)))

# Events by year — TWO views (53M apples-to-apples + full long_horizon)
lh[, year := year(Date)]
# View A: OOS 2018-2025 (53M scope, apples-to-apples with prior cycle headline)
# Codex review BUG #6 — View A uses .N denominator + NA->0 convention (53M legacy).
# Also report parallel View A_known (denominator restricted to non-NA per label) for honesty.
oos_lh <- lh[year >= 2018 & year <= 2025]
ey_oos <- oos_lh[, .(n = .N,
                     e_orig = sum(fcoalesce(y_tail_q126, 0L)),
                     rate_orig = mean(fcoalesce(y_tail_q126, 0L)),
                     e_abs15 = sum(fcoalesce(y_tail_q126_abs15, 0L)),
                     rate_abs15 = mean(fcoalesce(y_tail_q126_abs15, 0L)),
                     e_abs10 = sum(fcoalesce(y_tail_q126_abs10, 0L)),
                     rate_abs10 = mean(fcoalesce(y_tail_q126_abs10, 0L))),
                 by = year]
setorder(ey_oos, year)
# View A_known: restrict denominator to non-NA per label (no NA->0 bias)
ey_oos_known <- oos_lh[, .(n = .N,
                           n_obs_orig = sum(!is.na(y_tail_q126)),
                           rate_orig_known = sum(y_tail_q126, na.rm = TRUE) /
                                              pmax(sum(!is.na(y_tail_q126)), 1L),
                           n_obs_abs15 = sum(!is.na(y_tail_q126_abs15)),
                           rate_abs15_known = sum(y_tail_q126_abs15, na.rm = TRUE) /
                                               pmax(sum(!is.na(y_tail_q126_abs15)), 1L),
                           n_obs_abs10 = sum(!is.na(y_tail_q126_abs10)),
                           rate_abs10_known = sum(y_tail_q126_abs10, na.rm = TRUE) /
                                               pmax(sum(!is.na(y_tail_q126_abs10)), 1L)),
                       by = year]
setorder(ey_oos_known, year)

# View B: Full long_horizon coverage (1990-2026) — label-specific denominators
# Codex review BUG #6 fix: use sum(!is.na(label)) per label (not restrict by orig).
# (Empirical: abs15 and orig have identical NA pattern in this dataset; check_na_align
# at Phase 1 head verifies. But defensive label-specific denominators are correct in
# principle for arbitrary label additions.)
ey_full <- lh[, .(n = .N,
                  n_obs_orig = sum(!is.na(y_tail_q126)),
                  e_orig = sum(y_tail_q126, na.rm = TRUE),
                  rate_orig = sum(y_tail_q126, na.rm = TRUE) /
                              pmax(sum(!is.na(y_tail_q126)), 1L),
                  n_obs_abs15 = sum(!is.na(y_tail_q126_abs15)),
                  e_abs15 = sum(y_tail_q126_abs15, na.rm = TRUE),
                  rate_abs15 = sum(y_tail_q126_abs15, na.rm = TRUE) /
                               pmax(sum(!is.na(y_tail_q126_abs15)), 1L),
                  n_obs_abs10 = sum(!is.na(y_tail_q126_abs10)),
                  e_abs10 = sum(y_tail_q126_abs10, na.rm = TRUE),
                  rate_abs10 = sum(y_tail_q126_abs10, na.rm = TRUE) /
                               pmax(sum(!is.na(y_tail_q126_abs10)), 1L)),
              by = year]
setorder(ey_full, year)
# Verify NA alignment claim (orig vs abs15 NA pattern)
na_align_full <- sum(is.na(lh$y_tail_q126) == is.na(lh$y_tail_q126_abs15)) / nrow(lh)
cat(sprintf("NA-alignment orig vs abs15: %.4f (1.0 == identical)\n", na_align_full))

cat("\nEvents by year — View A (OOS 2018-2025, 53M scope, NA->0 convention):\n")
print(ey_oos)

cat("\nEvents by year — View B (Full long_horizon coverage):\n")
print(ey_full)

sd_rate <- list(
  oos_orig = sd(ey_oos$rate_orig, na.rm = TRUE),
  oos_abs15 = sd(ey_oos$rate_abs15, na.rm = TRUE),
  oos_abs10 = sd(ey_oos$rate_abs10, na.rm = TRUE),
  oos_known_orig = sd(ey_oos_known$rate_orig_known, na.rm = TRUE),
  oos_known_abs15 = sd(ey_oos_known$rate_abs15_known, na.rm = TRUE),
  oos_known_abs10 = sd(ey_oos_known$rate_abs10_known, na.rm = TRUE),
  full_orig = sd(ey_full$rate_orig, na.rm = TRUE),
  full_abs15 = sd(ey_full$rate_abs15, na.rm = TRUE),
  full_abs10 = sd(ey_full$rate_abs10, na.rm = TRUE)
)
cat(sprintf("\nYearly SD — OOS 2018-2025 (NA->0, 53M legacy): orig=%.4f, abs15=%.4f, abs10=%.4f\n",
            sd_rate$oos_orig, sd_rate$oos_abs15, sd_rate$oos_abs10))
cat(sprintf("Yearly SD — OOS 2018-2025 (NA-omit, known-only): orig=%.4f, abs15=%.4f, abs10=%.4f\n",
            sd_rate$oos_known_orig, sd_rate$oos_known_abs15, sd_rate$oos_known_abs10))
cat(sprintf("Yearly SD — Full 1990-2026: orig=%.4f, abs15=%.4f, abs10=%.4f\n",
            sd_rate$full_orig, sd_rate$full_abs15, sd_rate$full_abs10))

# Keep ey = oos view for back-compat (used in plot p_b)
ey <- ey_oos

#==============================================================================
# Phase 2 — All cycles re-evaluate (orig + abs15 + abs10)
#==============================================================================
cat("\n=== Phase 2: Cycle predictions re-evaluation ===\n")

# Cycle prediction file roster — all q126-based + 53M reference
# (q15 cycles excluded — different forecast horizon, label mapping ambiguous;
#  Cycle 52 v4a q15 retained for cross-horizon orig baseline)
PRED_FILES <- list(
  list(cycle = "c52_v4a_q15_5way",
       label = "Cycle52 v4a 5way-EW (q15)",
       path = "outputs/03_models/v4a_combined/predictions_5way_y_tail_q15.parquet",
       pred_col = "p_ew5", target = "y_tail_q15", horizon = "q15"),
  list(cycle = "c53B_v5b_q15",
       label = "Cycle53B v5b PatchTST (q15)",
       path = "outputs/03_models/v5b_patchtst_q126/predictions_patchtst_v5b_y_tail_q15.parquet",
       pred_col = "p_patchtst", target = "y_tail_q15", horizon = "q15"),
  list(cycle = "c53B_v5b_q126",
       label = "Cycle53B v5b PatchTST (q126)",
       path = "outputs/03_models/v5b_patchtst_q126/predictions_patchtst_v5b_y_tail_q126.parquet",
       pred_col = "p_patchtst", target = "y_tail_q126", horizon = "q126"),
  list(cycle = "c53E_v1_q126",
       label = "Cycle53E v1 PatchTST patch=4 (q126)",
       path = "outputs/03_models/v5d_patchtst_q126_sweep/predictions_patchtst_v1_y_tail_q126.parquet",
       pred_col = "p_patchtst", target = "y_tail_q126", horizon = "q126"),
  list(cycle = "c53E_v2_q126",
       label = "Cycle53E v2 PatchTST patch=2 (q126)",
       path = "outputs/03_models/v5d_patchtst_q126_sweep/predictions_patchtst_v2_y_tail_q126.parquet",
       pred_col = "p_patchtst", target = "y_tail_q126", horizon = "q126"),
  list(cycle = "c53E_v3_q126",
       label = "Cycle53E v3 PatchTST patch=6 (q126)",
       path = "outputs/03_models/v5d_patchtst_q126_sweep/predictions_patchtst_v3_y_tail_q126.parquet",
       pred_col = "p_patchtst", target = "y_tail_q126", horizon = "q126"),
  list(cycle = "c53E_v4_q126",
       label = "Cycle53E v4 PatchTST patch=8 (q126)",
       path = "outputs/03_models/v5d_patchtst_q126_sweep/predictions_patchtst_v4_y_tail_q126.parquet",
       pred_col = "p_patchtst", target = "y_tail_q126", horizon = "q126"),
  list(cycle = "c53E_v5_q126",
       label = "Cycle53E v5 PatchTST (q126)",
       path = "outputs/03_models/v5d_patchtst_q126_sweep/predictions_patchtst_v5_y_tail_q126.parquet",
       pred_col = "p_patchtst", target = "y_tail_q126", horizon = "q126"),
  list(cycle = "c53E_v6_q126",
       label = "Cycle53E v6 PatchTST (q126)",
       path = "outputs/03_models/v5d_patchtst_q126_sweep/predictions_patchtst_v6_y_tail_q126.parquet",
       pred_col = "p_patchtst", target = "y_tail_q126", horizon = "q126"),
  list(cycle = "c53E_v7_q126",
       label = "Cycle53E v7 PatchTST (q126)",
       path = "outputs/03_models/v5d_patchtst_q126_sweep/predictions_patchtst_v7_y_tail_q126.parquet",
       pred_col = "p_patchtst", target = "y_tail_q126", horizon = "q126"),
  list(cycle = "c53E_v8_q126",
       label = "Cycle53E v8 PatchTST (q126)",
       path = "outputs/03_models/v5d_patchtst_q126_sweep/predictions_patchtst_v8_y_tail_q126.parquet",
       pred_col = "p_patchtst", target = "y_tail_q126", horizon = "q126"),
  list(cycle = "c53E_v9_q126",
       label = "Cycle53E v9 PatchTST (q126)",
       path = "outputs/03_models/v5d_patchtst_q126_sweep/predictions_patchtst_v9_y_tail_q126.parquet",
       pred_col = "p_patchtst", target = "y_tail_q126", horizon = "q126"),
  list(cycle = "c53E_v10_q126",
       label = "Cycle53E v10 PatchTST (q126)",
       path = "outputs/03_models/v5d_patchtst_q126_sweep/predictions_patchtst_v10_y_tail_q126.parquet",
       pred_col = "p_patchtst", target = "y_tail_q126", horizon = "q126"),
  list(cycle = "c53E_v11_q126",
       label = "Cycle53E v11 PatchTST (q126)",
       path = "outputs/03_models/v5d_patchtst_q126_sweep/predictions_patchtst_v11_y_tail_q126.parquet",
       pred_col = "p_patchtst", target = "y_tail_q126", horizon = "q126"),
  list(cycle = "c53H_v5e_q126",
       label = "Cycle53H v5e PatchTST + US macro (q126)",
       path = "outputs/03_models/v5e_patchtst_q126_usmacro/predictions_patchtst_v5e_y_tail_q126.parquet",
       pred_col = "p_patchtst", target = "y_tail_q126", horizon = "q126"),
  list(cycle = "c53I_v5f_q126",
       label = "Cycle53I v5f PatchTST + ECOS KR macro (q126)",
       path = "outputs/03_models/v5f_patchtst_q126_ecos/predictions_patchtst_v5f_y_tail_q126.parquet",
       pred_col = "p_patchtst", target = "y_tail_q126", horizon = "q126")
)

# Period segments
SEGMENTS <- list(
  list(name = "S2018-19", start = as.Date("2018-01-01"), end = as.Date("2019-12-31")),
  list(name = "S2020-21", start = as.Date("2020-01-01"), end = as.Date("2021-12-31")),
  list(name = "S2022-24", start = as.Date("2022-01-01"), end = as.Date("2024-12-31")),
  list(name = "S2025-26", start = as.Date("2025-01-01"), end = as.Date("2026-12-31"))
)

# Build evaluation table per (cycle × label)
all_rows <- list()

for (cf in PRED_FILES) {
  if (!file.exists(cf$path)) {
    cat(sprintf("  [SKIP] %s — missing: %s\n", cf$cycle, cf$path))
    next
  }
  dt <- as.data.table(read_parquet(cf$path))
  # Convert POSIXct → Date if needed
  if (inherits(dt$Date, "POSIXct") || inherits(dt$Date, "POSIXt")) {
    dt[, Date := as.Date(Date)]
  }
  if (!cf$pred_col %in% names(dt)) {
    cat(sprintf("  [SKIP] %s — missing pred col '%s'\n", cf$cycle, cf$pred_col))
    next
  }
  # Merge with abs15-augmented targets on Date for all labels
  m <- merge(dt[, .(Date, p = get(cf$pred_col), y_orig_file = y)],
             lh[, .(Date, y_orig = get(cf$target),
                    y_abs15 = y_tail_q126_abs15, y_abs10 = y_tail_q126_abs10)],
             by = "Date", all.x = TRUE)

  # Sanity: y_orig_file should match y_orig from lh (for same horizon target)
  agree_n <- sum(!is.na(m$y_orig_file) & !is.na(m$y_orig) & m$y_orig_file == m$y_orig)
  total_n <- sum(!is.na(m$y_orig_file) & !is.na(m$y_orig))
  cat(sprintf("  [%s] orig label cross-check: %d/%d match (%.2f%%)\n",
              cf$cycle, agree_n, total_n,
              ifelse(total_n > 0, 100 * agree_n / total_n, NA)))

  # For q15 cycles: only orig label is meaningful (q15 target). abs15 from q126 only.
  labels_to_eval <- if (cf$horizon == "q126") {
    list(orig = "y_orig", abs15 = "y_abs15", abs10 = "y_abs10")
  } else {
    list(orig = "y_orig")  # q15 cycles: orig label only
  }

  for (lab_name in names(labels_to_eval)) {
    y_col <- labels_to_eval[[lab_name]]
    y <- m[[y_col]]; p <- m$p
    overall <- pr_auc_bootstrap_ci(p, y, B = 1000L, block_len = 21L)
    n_obs <- sum(!is.na(p) & !is.na(y))
    n_events <- sum(y[!is.na(p) & !is.na(y)] == 1, na.rm = TRUE)
    base_rate <- ifelse(n_obs > 0, n_events / n_obs, NA)
    ic <- ic_rank(p, y)

    # Per segment
    seg_results <- list()
    for (s in SEGMENTS) {
      sel <- !is.na(m$Date) & m$Date >= s$start & m$Date <= s$end
      p_s <- p[sel]; y_s <- y[sel]
      n_s <- sum(!is.na(p_s) & !is.na(y_s))
      e_s <- sum(y_s[!is.na(p_s) & !is.na(y_s)] == 1, na.rm = TRUE)
      pr_s <- pr_auc_bootstrap_ci(p_s, y_s, B = 500L, block_len = 21L)
      seg_results[[s$name]] <- list(
        n_obs = n_s, n_events = e_s,
        base_rate = ifelse(n_s > 0, e_s / n_s, NA_real_),
        pr_auc = pr_s$pr_auc, pr_lo = pr_s$lo, pr_hi = pr_s$hi,
        ic_rank = ic_rank(p_s, y_s),
        lift_over_base = ifelse(!is.na(pr_s$pr_auc) && !is.na(e_s / n_s) && (e_s / n_s) > 0,
                                pr_s$pr_auc / (e_s / n_s), NA_real_)
      )
    }

    all_rows[[length(all_rows) + 1L]] <- list(
      cycle = cf$cycle,
      cycle_label = cf$label,
      horizon = cf$horizon,
      label = lab_name,
      n_obs = n_obs,
      n_events = n_events,
      base_rate = base_rate,
      pr_auc = overall$pr_auc,
      pr_lo = overall$lo,
      pr_hi = overall$hi,
      ic_rank = ic,
      lift_over_base = ifelse(!is.na(overall$pr_auc) && !is.na(base_rate) && base_rate > 0,
                               overall$pr_auc / base_rate, NA_real_),
      segments = seg_results
    )
    cat(sprintf("  %s × %s: PR-AUC %.4f [%.4f, %.4f], lift %.3f, IC %.4f\n",
                cf$cycle, lab_name, overall$pr_auc %||% NA, overall$lo %||% NA,
                overall$hi %||% NA,
                ifelse(!is.na(overall$pr_auc) && !is.na(base_rate) && base_rate > 0,
                       overall$pr_auc / base_rate, NA_real_),
                ic %||% NA))
  }
}

cat(sprintf("\nTotal (cycle × label) evaluations: %d\n", length(all_rows)))

#==============================================================================
# Phase 3 — Robustness verdict + leaderboard
#==============================================================================
cat("\n=== Phase 3: Robustness verdict ===\n")

# Flat table for ranking
flat_tbl <- rbindlist(lapply(all_rows, function(r) {
  data.table(
    cycle = r$cycle, label = r$label, horizon = r$horizon,
    cycle_label = r$cycle_label, n_obs = r$n_obs, n_events = r$n_events,
    base_rate = round(r$base_rate, 4),
    pr_auc = round(r$pr_auc, 4),
    pr_lo = round(r$pr_lo, 4), pr_hi = round(r$pr_hi, 4),
    ic_rank = round(r$ic_rank, 4),
    lift = round(r$lift_over_base, 4),
    pr_ci_above_baseline = ifelse(!is.na(r$pr_lo) && !is.na(r$base_rate),
                                  as.integer(r$pr_lo > r$base_rate), NA_integer_)
  )
}))
setorder(flat_tbl, -pr_auc)

# Leaderboard under abs15 (q126 cycles only)
abs15_tbl <- flat_tbl[label == "abs15"]
setorder(abs15_tbl, -pr_auc)
cat("\n--- Leaderboard under abs15 label (q126 cycles only) ---\n")
print(abs15_tbl[, .(cycle, cycle_label, n_events, base_rate, pr_auc,
                    pr_lo, pr_hi, lift, ic_rank, pr_ci_above_baseline)])

# Leaderboard under orig (q126)
orig_q126_tbl <- flat_tbl[label == "orig" & horizon == "q126"]
setorder(orig_q126_tbl, -pr_auc)
cat("\n--- Leaderboard under y_tail_q126 (orig 60m purged rolling 15th pctile) ---\n")
print(orig_q126_tbl[, .(cycle, cycle_label, n_events, base_rate, pr_auc,
                        pr_lo, pr_hi, lift, ic_rank, pr_ci_above_baseline)])

# Ranking consistency (Spearman correlation orig PR-AUC vs abs15 PR-AUC)
# Codex review BUG #7 fix: use UNROUNDED raw values to avoid artificial ties.
raw_rows_q126 <- Filter(function(r) r$horizon == "q126", all_rows)
raw_orig <- rbindlist(lapply(raw_rows_q126, function(r) {
  if (r$label != "orig") return(NULL)
  data.table(cycle = r$cycle, pr_orig = r$pr_auc, ic_orig = r$ic_rank,
             lift_orig = r$lift_over_base)
}))
raw_abs15 <- rbindlist(lapply(raw_rows_q126, function(r) {
  if (r$label != "abs15") return(NULL)
  data.table(cycle = r$cycle, pr_abs15 = r$pr_auc, ic_abs15 = r$ic_rank,
             lift_abs15 = r$lift_over_base)
}))
merged_rank <- merge(raw_orig, raw_abs15, by = "cycle")
spearman_pr <- if (nrow(merged_rank) >= 3) cor(merged_rank$pr_orig, merged_rank$pr_abs15,
                                                method = "spearman") else NA_real_
spearman_ic <- if (nrow(merged_rank) >= 3) cor(merged_rank$ic_orig, merged_rank$ic_abs15,
                                                method = "spearman") else NA_real_

cat(sprintf("\nSpearman rank correlation PR-AUC (orig vs abs15): %.4f\n", spearman_pr))
cat(sprintf("Spearman rank correlation IC (orig vs abs15): %.4f\n", spearman_ic))

best_orig <- orig_q126_tbl[1, cycle]
best_abs15 <- abs15_tbl[1, cycle]
cat(sprintf("Best (q126) under orig: %s (PR=%.4f)\n", best_orig, orig_q126_tbl[1, pr_auc]))
cat(sprintf("Best (q126) under abs15: %s (PR=%.4f)\n", best_abs15, abs15_tbl[1, pr_auc]))
cat(sprintf("Best consistency: %s\n", ifelse(best_orig == best_abs15, "YES — robust", "NO — divergent")))

# Period-robust: per cycle, segments lift > 1 count under each label
period_robust <- list()
for (r in all_rows) {
  if (r$horizon != "q126" || r$label != "abs15") next
  segs <- r$segments
  lift_gt_1 <- sum(sapply(segs, function(s)
                          !is.na(s$lift_over_base) && s$lift_over_base > 1), na.rm = TRUE)
  n_with_events <- sum(sapply(segs, function(s) s$n_events >= 5), na.rm = TRUE)
  period_robust[[r$cycle]] <- list(
    cycle = r$cycle, lift_gt_1 = lift_gt_1, n_with_events = n_with_events,
    pr_auc_overall = r$pr_auc
  )
}
pr_tbl <- rbindlist(lapply(period_robust, as.data.table))
setorder(pr_tbl, -lift_gt_1, -pr_auc_overall)
cat("\n--- Period-robust under abs15 (count of segments with lift>1, segments with n_events>=5) ---\n")
print(pr_tbl)

#==============================================================================
# Phase 4 — Save results (cycle54b_all_cycles_reeval.json)
#==============================================================================
cat("\n=== Phase 4: Saving results ===\n")

out_results <- list(
  meta = list(
    script = "scripts/138_cycle54b_abs15_reeval.R",
    cycle = "54B_abs15_primary_reeval",
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    purpose = paste("y_tail_q126_abs15 primary 전환 + 모든 cycle re-evaluate",
                    "(orig vs abs15 leaderboard + period-balanced + ranking 일관성)"),
    ax_008_class = "code_review_only_codex",
    cpu_only = TRUE,
    no_retraining = TRUE,
    pre_cycle_bear_date_audit = "PASS_4_of_4"
  ),
  phase1_label_summary = list(
    n_obs_q126 = n_obs_q126,
    n_events_orig = n_orig,
    rate_orig = round(n_orig / n_obs_q126, 4),
    n_events_abs15 = n_abs15,
    rate_abs15 = round(n_abs15 / n_obs_q126, 4),
    n_events_abs10 = sum(lh$y_tail_q126_abs10, na.rm = TRUE),
    rate_abs10 = round(sum(lh$y_tail_q126_abs10, na.rm = TRUE) / n_obs_q126, 4),
    events_by_year_oos_legacy_53M = ey_oos,
    events_by_year_oos_known_only = ey_oos_known,
    events_by_year_full = ey_full,
    na_alignment_orig_vs_abs15 = round(na_align_full, 4),
    yearly_sd_event_rate = sd_rate,
    yearly_sd_note = paste(
      "53M Phase 2 headline (abs15 SD=0.0714) used OOS 2018-2025 + NA->0 convention",
      "(=oos_abs15 here). Full long_horizon 1990-2026 view also retained for honesty."),
    targets_file_saved = basename(out_path)
  ),
  phase2_cycle_x_label = flat_tbl,
  phase3_robustness = list(
    leaderboard_abs15 = abs15_tbl[, .(cycle, cycle_label, n_events, base_rate, pr_auc,
                                       pr_lo, pr_hi, lift, ic_rank, pr_ci_above_baseline)],
    leaderboard_orig_q126 = orig_q126_tbl[, .(cycle, cycle_label, n_events, base_rate, pr_auc,
                                                pr_lo, pr_hi, lift, ic_rank,
                                                pr_ci_above_baseline)],
    spearman_pr_orig_vs_abs15 = round(spearman_pr, 4),
    spearman_ic_orig_vs_abs15 = round(spearman_ic, 4),
    best_orig_q126 = best_orig,
    best_abs15 = best_abs15,
    best_consistent = best_orig == best_abs15,
    period_robust_under_abs15 = pr_tbl
  ),
  phase4_per_cycle_segments = all_rows
)

out_json_path <- file.path(EVAL_DIR, "cycle54b_all_cycles_reeval.json")
write_json(out_results, out_json_path, auto_unbox = TRUE, pretty = TRUE,
           force = TRUE, na = "string", digits = 6)
cat(sprintf("Saved: %s\n", out_json_path))

#==============================================================================
# Phase 5 — Visualization (139_cycle54b_label_compare.png)
#==============================================================================
cat("\n=== Phase 5: Visualization ===\n")

# Two-panel: (a) leaderboard barchart (orig vs abs15) per cycle
# (b) yearly event rate (orig vs abs15)

# (a) Cycle PR-AUC under orig vs abs15
plot_a_data <- merged_rank[, .(cycle, pr_orig, pr_abs15)]
plot_a_long <- melt(plot_a_data, id.vars = "cycle",
                    variable.name = "label", value.name = "pr_auc")
plot_a_long[, label := factor(label, levels = c("pr_orig", "pr_abs15"),
                              labels = c("orig (60m purged q15)", "abs15 (fixed -15%)"))]
# Order by abs15 PR-AUC desc
order_cycles <- plot_a_data[order(-pr_abs15), cycle]
plot_a_long[, cycle := factor(cycle, levels = order_cycles)]

p_a <- ggplot(plot_a_long, aes(x = cycle, y = pr_auc, fill = label)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  geom_text(aes(label = sprintf("%.3f", pr_auc)),
            position = position_dodge(width = 0.8), vjust = -0.2, size = 2.5) +
  scale_fill_manual(values = c("orig (60m purged q15)" = "#3B82F6",
                               "abs15 (fixed -15%)" = "#EF4444")) +
  geom_hline(yintercept = 0.2522, linetype = "dashed", color = "#3B82F6", alpha = 0.6) +
  geom_hline(yintercept = round(n_abs15 / n_obs_q126, 4),
             linetype = "dashed", color = "#EF4444", alpha = 0.6) +
  labs(title = "Cycle 54B — PR-AUC per cycle: orig (q126) vs abs15 (fixed -15%)",
       subtitle = "Dashed line = base rate per label (blue=orig 25.22%, red=abs15)",
       x = "Cycle (q126)", y = "PR-AUC") +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        legend.position = "top",
        plot.title = element_text(face = "bold"))

# (b) Yearly event rate
ey_long <- melt(ey[, .(year, rate_orig, rate_abs15, rate_abs10)],
                id.vars = "year", variable.name = "label", value.name = "rate")
ey_long[, label := factor(label, levels = c("rate_orig", "rate_abs15", "rate_abs10"),
                          labels = c("orig (q15 thr)", "abs15", "abs10"))]
p_b <- ggplot(ey_long, aes(x = factor(year), y = rate, fill = label)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  scale_fill_manual(values = c("orig (q15 thr)" = "#3B82F6",
                               "abs15" = "#EF4444",
                               "abs10" = "#10B981")) +
  labs(title = "Yearly event rate by label (OOS 2018-2025, NA->0 convention)",
       subtitle = sprintf("OOS yearly SD: orig=%.4f, abs15=%.4f, abs10=%.4f (abs15 = lowest = period-balanced)",
                          sd_rate$oos_orig, sd_rate$oos_abs15, sd_rate$oos_abs10),
       x = "Year", y = "Event rate") +
  theme_minimal(base_size = 10) +
  theme(legend.position = "top", axis.text.x = element_text(angle = 45, hjust = 1))

p_combined <- p_a / p_b + plot_layout(heights = c(1.2, 1))
chart_path <- file.path(CHART_DIR, "139_cycle54b_label_compare.png")
ggsave(chart_path, p_combined, width = 13, height = 9, dpi = 100)
cat(sprintf("Saved chart: %s\n", chart_path))

cat("\n=============================================================\n")
cat("Cycle 54B — Phase 1~5 COMPLETE\n")
cat("=============================================================\n")
cat(sprintf("Output JSON: %s\n", out_json_path))
cat(sprintf("Output PNG: %s\n", chart_path))
cat(sprintf("Output Parquet: %s\n", out_path))
cat(sprintf("\nBest cycle (orig q126): %s — PR-AUC %.4f\n", best_orig, orig_q126_tbl[1, pr_auc]))
cat(sprintf("Best cycle (abs15):     %s — PR-AUC %.4f\n", best_abs15, abs15_tbl[1, pr_auc]))
cat(sprintf("Spearman rank corr (PR-AUC orig vs abs15): %.4f\n", spearman_pr))
cat(sprintf("OOS yearly SD (2018-2025, 53M apples-to-apples): orig=%.4f, abs15=%.4f (%.1fx improvement)\n",
            sd_rate$oos_orig, sd_rate$oos_abs15, sd_rate$oos_orig / sd_rate$oos_abs15))
cat(sprintf("Full yearly SD (1990-2026): orig=%.4f, abs15=%.4f (%.1fx improvement)\n",
            sd_rate$full_orig, sd_rate$full_abs15, sd_rate$full_orig / sd_rate$full_abs15))
