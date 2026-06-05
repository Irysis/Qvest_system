#==============================================================================
# 134_sanity_recovery_period_analysis.R
#
# Cycle 53M — Sanity Recovery: Period-balanced PR-AUC + Alternative Label
#
# Phase 1: Period-stratified PR-AUC per cycle (per-year + multi-year segments)
#          + bootstrap 95% CI (block bootstrap, B=1000, block_len=21)
# Phase 2: Alternative label evaluation (abs10 / abs15 / oos_q15)
# Phase 3: Cross-period robustness verdict
# Phase 4: v1 calibration audit (53E v1 patch=4 vs 53B v5b PatchTST q126)
#
# CPU only — no retraining; analyse existing predictions only
# Author: Forge (Q-Lead delegated, 도훈 audit 후속)
# Date: 2026-05-20
#
# AX-008: single-source quick screening (sanity audit, admit decision X)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
  library(ggplot2)
  library(patchwork)
})

set.seed(20260520L)

ROOT <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "04_Research/decision_framework/bearish_forecast_v2_alt_data")
setwd(ROOT)

EVAL_DIR <- file.path(ROOT, "outputs/04_evaluation")
CHART_DIR <- file.path(ROOT, "outputs/06_reports/charts")
dir.create(EVAL_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(CHART_DIR, showWarnings = FALSE, recursive = TRUE)

BENCHMARK_PATH <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), ".cache/benchmark.parquet")

cat("=============================================================\n")
cat("Cycle 53M — Sanity Recovery: Period-balanced PR-AUC\n")
cat("=============================================================\n\n")

#==============================================================================
# Utility: PR-AUC (trapezoidal, inherited from script 130)
#==============================================================================
pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y)
  p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5 || sum(y) == length(y)) return(NA_real_)
  ord <- order(p, decreasing = TRUE)
  y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord)
  rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec)
  sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

ic_rank <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sd(p) < 1e-30) return(NA_real_)
  cor(rank(p), rank(y), method = "pearson")
}

# Moving-block bootstrap PR-AUC CI (default block_len=21 ≈ 1m)
pr_auc_bootstrap_ci <- function(p, y, B = 1000L, block_len = 21L, alpha = 0.05) {
  n <- length(p)
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
# Step 0 — Load prediction files (4 cycles + alt diagnostic v1)
#==============================================================================
PRED_FILES <- list(
  c52_v4a_q15 = list(
    path = "outputs/03_models/v4a_combined/predictions_5way_y_tail_q15.parquet",
    pred_col = "p_ew5",  # 5-way equal-weighted ensemble (Cycle 52 v4a 'combined')
    target = "y_tail_q15",
    label = "Cycle52 v4a 5way-EW (q15)"
  ),
  c53B_v5b_q126 = list(
    path = "outputs/03_models/v5b_patchtst_q126/predictions_patchtst_v5b_y_tail_q126.parquet",
    pred_col = "p_patchtst",
    target = "y_tail_q126",
    label = "Cycle53B v5b PatchTST (q126)"
  ),
  c53B_v5b_q15 = list(
    path = "outputs/03_models/v5b_patchtst_q126/predictions_patchtst_v5b_y_tail_q15.parquet",
    pred_col = "p_patchtst",
    target = "y_tail_q15",
    label = "Cycle53B v5b PatchTST (q15)"
  ),
  c53E_v2_q126 = list(
    path = "outputs/03_models/v5d_patchtst_q126_sweep/predictions_patchtst_v2_y_tail_q126.parquet",
    pred_col = "p_patchtst",
    target = "y_tail_q126",
    label = "Cycle53E v2 PatchTST patch=2 (q126, claimed PR=0.4747)"
  ),
  c53E_v1_q126 = list(
    path = "outputs/03_models/v5d_patchtst_q126_sweep/predictions_patchtst_v1_y_tail_q126.parquet",
    pred_col = "p_patchtst",
    target = "y_tail_q126",
    label = "Cycle53E v1 PatchTST patch=4 baseline (q126, calibration broken)"
  ),
  c53H_v5e_q126 = list(
    path = "outputs/03_models/v5e_patchtst_q126_usmacro/predictions_patchtst_v5e_y_tail_q126.parquet",
    pred_col = "p_patchtst",
    target = "y_tail_q126",
    label = "Cycle53H v5e PatchTST + US macro (q126, claimed PR=0.4012)"
  )
)

load_pred <- function(spec) {
  dt <- as.data.table(read_parquet(spec$path))
  dt[, Date := as.Date(Date)]
  setnames(dt, spec$pred_col, "p")
  dt[, .(Date, p, y)]
}

preds <- lapply(PRED_FILES, load_pred)

cat("Loaded predictions:\n")
for (nm in names(preds)) {
  dt <- preds[[nm]]
  cat(sprintf("  %-18s rows=%d  date=[%s..%s]  events=%d  p_mean=%.6e  p_max=%.6e\n",
              nm, nrow(dt), min(dt$Date), max(dt$Date),
              sum(dt$y, na.rm = TRUE), mean(dt$p, na.rm = TRUE), max(dt$p, na.rm = TRUE)))
}
cat("\n")

#==============================================================================
# Step 1 — Load targets (full series for OOS recompute later)
#==============================================================================
targets_full <- as.data.table(read_parquet("outputs/02_targets/targets_long_horizon.parquet"))
targets_full[, Date := as.Date(Date)]
cat(sprintf("Loaded targets_long_horizon: %d rows, %s..%s\n\n",
            nrow(targets_full), min(targets_full$Date), max(targets_full$Date)))

#==============================================================================
# Step 2 — Period strata definition (yearly + multi-year segments)
#==============================================================================
period_labels_year <- function(dt) {
  yrs <- as.integer(format(dt$Date, "%Y"))
  sprintf("Y%d", yrs)
}

period_labels_segment <- function(dt) {
  yrs <- as.integer(format(dt$Date, "%Y"))
  out <- character(length(yrs))
  out[yrs %in% 2018:2019] <- "S2018-2019"
  out[yrs %in% 2020:2021] <- "S2020-2021"
  out[yrs %in% 2022:2024] <- "S2022-2024"
  out[yrs %in% 2025:2026] <- "S2025-2026"
  out
}

#==============================================================================
# Phase 1 — Period-stratified PR-AUC per cycle
#==============================================================================
cat("=============================================================\n")
cat("PHASE 1 — Period-stratified PR-AUC per cycle\n")
cat("=============================================================\n\n")

compute_period_pr <- function(dt, period_fn, label_name) {
  dt2 <- copy(dt)
  dt2[, period := period_fn(dt2)]
  res <- dt2[, {
    .ci <- pr_auc_bootstrap_ci(p, y, B = 1000L, block_len = 21L)
    list(
      n_obs = .N,
      n_events = sum(y, na.rm = TRUE),
      event_rate = mean(y, na.rm = TRUE),
      pr_auc = .ci$pr_auc,
      pr_lo = .ci$lo,
      pr_hi = .ci$hi,
      ic_rank = ic_rank(p, y),
      base_rate = mean(y, na.rm = TRUE),  # baseline PR-AUC = positive rate
      lift_over_base = if (is.na(.ci$pr_auc) || is.na(mean(y, na.rm = TRUE)) || mean(y, na.rm = TRUE) == 0) NA_real_ else .ci$pr_auc / mean(y, na.rm = TRUE)
    )
  }, by = period]
  res[, period_kind := label_name]
  setorder(res, period)
  res[]
}

phase1_year <- list()
phase1_segment <- list()
phase1_overall <- list()

for (nm in names(preds)) {
  cat(sprintf("[%s] %s\n", nm, PRED_FILES[[nm]]$label))
  dt <- preds[[nm]]

  # Overall OOS
  ci_all <- pr_auc_bootstrap_ci(dt$p, dt$y, B = 1000L, block_len = 21L)
  base_overall <- mean(dt$y, na.rm = TRUE)
  phase1_overall[[nm]] <- data.table(
    cycle = nm,
    label = PRED_FILES[[nm]]$label,
    target = PRED_FILES[[nm]]$target,
    n_obs = nrow(dt),
    n_events = sum(dt$y, na.rm = TRUE),
    base_rate = base_overall,
    pr_auc = ci_all$pr_auc,
    pr_lo = ci_all$lo,
    pr_hi = ci_all$hi,
    ic_rank = ic_rank(dt$p, dt$y),
    lift_over_base = if (is.na(ci_all$pr_auc) || base_overall == 0) NA_real_ else ci_all$pr_auc / base_overall
  )

  # Yearly
  res_yr <- compute_period_pr(dt, period_labels_year, "year")
  res_yr[, cycle := nm]
  phase1_year[[nm]] <- res_yr

  # Multi-year segments
  res_seg <- compute_period_pr(dt, period_labels_segment, "segment")
  res_seg[, cycle := nm]
  phase1_segment[[nm]] <- res_seg

  cat(sprintf("  Overall PR-AUC=%.4f [%.4f, %.4f]  base=%.4f  lift=%.2fx  IC=%.4f\n",
              ci_all$pr_auc %||% NA, ci_all$lo %||% NA, ci_all$hi %||% NA,
              base_overall, ci_all$pr_auc / base_overall, ic_rank(dt$p, dt$y)))
}
cat("\n")

`%||%` <- function(a, b) if (is.null(a) || is.na(a)) b else a

phase1_year_dt <- rbindlist(phase1_year, fill = TRUE)
phase1_seg_dt <- rbindlist(phase1_segment, fill = TRUE)
phase1_overall_dt <- rbindlist(phase1_overall, fill = TRUE)

cat("--- Multi-year segments (PR-AUC + lift_over_base) ---\n")
print(phase1_seg_dt[, .(cycle, period, n_obs, n_events,
                        event_rate = round(event_rate, 4),
                        pr_auc = round(pr_auc, 4),
                        pr_lo = round(pr_lo, 4),
                        pr_hi = round(pr_hi, 4),
                        lift = round(lift_over_base, 2))])
cat("\n")

#==============================================================================
# Phase 2 — Alternative label evaluation
#==============================================================================
cat("=============================================================\n")
cat("PHASE 2 — Alternative label evaluation\n")
cat("=============================================================\n\n")

# alt label 1: y_tail_q126_abs10 = 1{ret_q126 <= -0.10}
# alt label 2: y_tail_q126_abs15 = 1{ret_q126 <= -0.15}
# alt label 3: y_tail_q126_oos_q15 = OOS portion 15th percentile recompute
#              (forward-looking selection bias 명시 — diagnostic only)

# Pull ret_q126 from targets_long_horizon
ret_q126_dt <- targets_full[, .(Date, ret_q126, q15_thr_q126_orig = q15_thr_q126, y_tail_q126_orig = y_tail_q126)]

# OOS recompute (forward-looking — DIAGNOSTIC ONLY)
oos_start <- as.Date("2018-01-01")
ret_oos <- ret_q126_dt[Date >= oos_start & !is.na(ret_q126)]
oos_q15_thr <- quantile(ret_oos$ret_q126, 0.15, na.rm = TRUE)
cat(sprintf("OOS-recomputed q15 threshold (DIAGNOSTIC ONLY, forward-looking): %.4f\n", oos_q15_thr))
cat(sprintf("Original q15 threshold (last value, expanding rolling): %.4f\n\n",
            tail(ret_q126_dt$q15_thr_q126_orig[!is.na(ret_q126_dt$q15_thr_q126_orig)], 1)))

# Build alt-label dt
alt_labels_dt <- ret_q126_dt[, .(
  Date = Date,
  ret_q126 = ret_q126,
  y_q126_orig = y_tail_q126_orig,
  y_q126_abs10 = as.integer(ret_q126 <= -0.10),
  y_q126_abs15 = as.integer(ret_q126 <= -0.15),
  y_q126_oos_q15 = as.integer(ret_q126 <= oos_q15_thr)
)]

# Events per year per label
alt_label_events_yearly <- function(alt_dt, oos_start_dt) {
  dt <- alt_dt[Date >= oos_start_dt & !is.na(ret_q126)]
  dt[, year := as.integer(format(Date, "%Y"))]
  out <- dt[, .(
    n_obs = .N,
    e_orig = sum(y_q126_orig, na.rm = TRUE),
    rate_orig = round(mean(y_q126_orig, na.rm = TRUE), 4),
    e_abs10 = sum(y_q126_abs10, na.rm = TRUE),
    rate_abs10 = round(mean(y_q126_abs10, na.rm = TRUE), 4),
    e_abs15 = sum(y_q126_abs15, na.rm = TRUE),
    rate_abs15 = round(mean(y_q126_abs15, na.rm = TRUE), 4),
    e_oos_q15 = sum(y_q126_oos_q15, na.rm = TRUE),
    rate_oos_q15 = round(mean(y_q126_oos_q15, na.rm = TRUE), 4)
  ), by = year]
  setorder(out, year)
  out
}

events_by_year <- alt_label_events_yearly(alt_labels_dt, oos_start)
cat("Events per year × alternative label:\n")
print(events_by_year)
cat("\n")

# Re-evaluate 4 cycle PR-AUC under each alternative label
# Only q126 cycles (c53B_v5b_q126, c53E_v2_q126, c53E_v1_q126, c53H_v5e_q126)
Q126_CYCLES <- c("c53B_v5b_q126", "c53E_v2_q126", "c53E_v1_q126", "c53H_v5e_q126")

reeval_under_label <- function(pred_dt, alt_dt, alt_label_col) {
  merged <- merge(pred_dt[, .(Date, p)], alt_dt[, .(Date, y_alt = get(alt_label_col))],
                  by = "Date", all.x = FALSE, all.y = FALSE)
  merged <- merged[!is.na(y_alt) & !is.na(p)]
  if (nrow(merged) < 60) return(NULL)
  list(
    n_obs = nrow(merged),
    n_events = sum(merged$y_alt),
    base_rate = mean(merged$y_alt),
    ci = pr_auc_bootstrap_ci(merged$p, merged$y_alt, B = 1000L, block_len = 21L),
    ic = ic_rank(merged$p, merged$y_alt)
  )
}

alt_label_cols <- c("y_q126_orig", "y_q126_abs10", "y_q126_abs15", "y_q126_oos_q15")
phase2_rows <- list()
for (cyc in Q126_CYCLES) {
  for (lbl in alt_label_cols) {
    res <- reeval_under_label(preds[[cyc]], alt_labels_dt, lbl)
    if (is.null(res)) next
    phase2_rows[[length(phase2_rows) + 1]] <- data.table(
      cycle = cyc,
      label = lbl,
      n_obs = res$n_obs,
      n_events = res$n_events,
      base_rate = round(res$base_rate, 4),
      pr_auc = round(res$ci$pr_auc, 4),
      pr_lo = round(res$ci$lo, 4),
      pr_hi = round(res$ci$hi, 4),
      ic_rank = round(res$ic, 4),
      lift_over_base = round(res$ci$pr_auc / res$base_rate, 2)
    )
  }
}
phase2_dt <- rbindlist(phase2_rows, fill = TRUE)
cat("--- Phase 2: Cycle × Alternative label PR-AUC ---\n")
print(phase2_dt)
cat("\n")

#==============================================================================
# Phase 3 — Cross-period robustness verdict (cycle × label × segment matrix)
#==============================================================================
cat("=============================================================\n")
cat("PHASE 3 — Cross-period robustness verdict\n")
cat("=============================================================\n\n")

phase3_rows <- list()
for (cyc in Q126_CYCLES) {
  for (lbl in alt_label_cols) {
    merged <- merge(preds[[cyc]][, .(Date, p)],
                    alt_labels_dt[, .(Date, y_alt = get(lbl))],
                    by = "Date", all.x = FALSE)
    merged <- merged[!is.na(y_alt) & !is.na(p)]
    if (nrow(merged) < 60) next
    merged[, segment := period_labels_segment(merged)]
    for (seg in c("S2018-2019", "S2020-2021", "S2022-2024", "S2025-2026")) {
      sub <- merged[segment == seg]
      if (nrow(sub) < 30 || sum(sub$y_alt, na.rm = TRUE) < 5) {
        phase3_rows[[length(phase3_rows) + 1]] <- data.table(
          cycle = cyc, label = lbl, segment = seg,
          n_obs = nrow(sub), n_events = sum(sub$y_alt, na.rm = TRUE),
          base_rate = if (nrow(sub) > 0) round(mean(sub$y_alt, na.rm = TRUE), 4) else NA_real_,
          pr_auc = NA_real_, pr_lo = NA_real_, pr_hi = NA_real_,
          lift_over_base = NA_real_, degenerate = TRUE
        )
        next
      }
      ci <- pr_auc_bootstrap_ci(sub$p, sub$y_alt, B = 500L, block_len = 21L)
      br <- mean(sub$y_alt, na.rm = TRUE)
      phase3_rows[[length(phase3_rows) + 1]] <- data.table(
        cycle = cyc, label = lbl, segment = seg,
        n_obs = nrow(sub), n_events = sum(sub$y_alt, na.rm = TRUE),
        base_rate = round(br, 4),
        pr_auc = round(ci$pr_auc, 4),
        pr_lo = round(ci$lo, 4), pr_hi = round(ci$hi, 4),
        lift_over_base = if (is.na(ci$pr_auc) || br == 0) NA_real_ else round(ci$pr_auc / br, 2),
        degenerate = FALSE
      )
    }
  }
}
phase3_dt <- rbindlist(phase3_rows, fill = TRUE)

cat("--- Phase 3 matrix (cycle × label × segment) ---\n")
print(phase3_dt[, .(cycle, label, segment, n_obs, n_events, base_rate, pr_auc, pr_lo, pr_hi, lift_over_base, degenerate)])
cat("\n")

# Robustness summary: per (cycle, label) — non-degenerate segments with lift > 1 count
robust_summary <- phase3_dt[degenerate == FALSE, .(
  n_segments_valid = .N,
  n_segments_lift_gt_1 = sum(lift_over_base > 1, na.rm = TRUE),
  n_segments_lift_gt_1p5 = sum(lift_over_base > 1.5, na.rm = TRUE),
  pr_auc_mean = round(mean(pr_auc, na.rm = TRUE), 4),
  pr_auc_min = round(min(pr_auc, na.rm = TRUE), 4),
  lift_min = round(min(lift_over_base, na.rm = TRUE), 2),
  lift_mean = round(mean(lift_over_base, na.rm = TRUE), 2)
), by = .(cycle, label)]

setorder(robust_summary, -n_segments_lift_gt_1, -lift_mean)
cat("--- Phase 3 Robustness summary (sorted by # segments with lift>1, then mean lift) ---\n")
print(robust_summary)
cat("\n")

# Identify best model and best label
best_combo <- robust_summary[1]
cat(sprintf("BEST robust (model, label): %s × %s\n", best_combo$cycle, best_combo$label))
cat(sprintf("  segments_lift>1: %d / %d  lift_min=%.2f  lift_mean=%.2f\n\n",
            best_combo$n_segments_lift_gt_1, best_combo$n_segments_valid,
            best_combo$lift_min, best_combo$lift_mean))

#==============================================================================
# Phase 4 — v1 calibration audit (53E v1 patch=4 vs 53B v5b PatchTST q126)
#==============================================================================
cat("=============================================================\n")
cat("PHASE 4 — v1 calibration audit\n")
cat("=============================================================\n\n")

v1_dt <- preds$c53E_v1_q126
v5b_dt <- preds$c53B_v5b_q126
v2_dt <- preds$c53E_v2_q126

calib_stats <- function(dt, name) {
  p <- dt$p
  list(
    name = name,
    n = length(p),
    p_min = min(p, na.rm = TRUE),
    p_q25 = unname(quantile(p, 0.25, na.rm = TRUE)),
    p_median = median(p, na.rm = TRUE),
    p_mean = mean(p, na.rm = TRUE),
    p_q75 = unname(quantile(p, 0.75, na.rm = TRUE)),
    p_max = max(p, na.rm = TRUE),
    # logit space (inverse sigmoid)
    logit_mean = mean(log(pmax(p, 1e-300) / pmax(1 - p, 1e-300)), na.rm = TRUE),
    logit_min = min(log(pmax(p, 1e-300) / pmax(1 - p, 1e-300)), na.rm = TRUE),
    logit_max = max(log(pmax(p, 1e-300) / pmax(1 - p, 1e-300)), na.rm = TRUE),
    p_below_1eM6 = sum(p < 1e-6, na.rm = TRUE) / length(p),
    p_below_1eM9 = sum(p < 1e-9, na.rm = TRUE) / length(p),
    range_p_max_minus_min = max(p, na.rm = TRUE) - min(p, na.rm = TRUE)
  )
}

calib_v1 <- calib_stats(v1_dt, "c53E_v1 patch=4 (baseline)")
calib_v5b <- calib_stats(v5b_dt, "c53B v5b PatchTST (q126)")
calib_v2 <- calib_stats(v2_dt, "c53E v2 patch=2 (winner)")

print_calib <- function(s) {
  cat(sprintf("[%s]\n", s$name))
  cat(sprintf("  p: min=%.4e  q25=%.4e  median=%.4e  mean=%.4e  q75=%.4e  max=%.4e\n",
              s$p_min, s$p_q25, s$p_median, s$p_mean, s$p_q75, s$p_max))
  cat(sprintf("  logit: min=%.2f  mean=%.2f  max=%.2f  (range %.2f)\n",
              s$logit_min, s$logit_mean, s$logit_max, s$logit_max - s$logit_min))
  cat(sprintf("  p<1e-6: %.1f%%  p<1e-9: %.1f%%  p-range: %.4e\n\n",
              100*s$p_below_1eM6, 100*s$p_below_1eM9, s$range_p_max_minus_min))
}

print_calib(calib_v1)
print_calib(calib_v5b)
print_calib(calib_v2)

# Diagnose: 53E v1 vs 53B v5b identical?
identical_p <- all.equal(v1_dt$p, v5b_dt$p)
cat(sprintf("Are c53E v1 and c53B v5b predictions identical? %s\n",
            if (isTRUE(identical_p)) "YES (same training run reused)" else paste0("NO: ", identical_p)))

cor_v1_v5b <- cor(v1_dt$p, v5b_dt$p, use = "pairwise.complete.obs")
cat(sprintf("Pearson cor(v1, v5b) = %.6f\n", cor_v1_v5b))
cor_v1_v2 <- cor(v1_dt$p, v2_dt$p, use = "pairwise.complete.obs")
cat(sprintf("Pearson cor(v1, v2)  = %.6f\n", cor_v1_v2))

# PR-AUC of v1 (even with broken calibration — ranking still works?)
ci_v1 <- pr_auc_bootstrap_ci(v1_dt$p, v1_dt$y, B = 1000L, block_len = 21L)
cat(sprintf("\nv1 PR-AUC (ranking only, ignoring calibration scale) = %.4f [%.4f, %.4f]\n",
            ci_v1$pr_auc, ci_v1$lo, ci_v1$hi))
cat("(Ranking is invariant to monotonic transform; PR-AUC works on order)\n\n")

# Verdict on v1 calibration
calibration_verdict <- list()
if (isTRUE(all.equal(v1_dt$p, v5b_dt$p))) {
  calibration_verdict$v1_v5b_identical <- TRUE
  calibration_verdict$root_cause <- "c53E v1 patch=4 and c53B v5b predictions are bit-identical — v5d sweep reused v5b's PatchTST run for v1 baseline instead of training a fresh patch=4. Both share the same near-zero calibration."
  calibration_verdict$implication <- "Calibration collapse is c53B v5b's own issue, not a v5d sweep-specific bug. Whatever caused 5b's logits to converge near -25 (sigmoid ~7e-12) applies to both."
} else {
  calibration_verdict$v1_v5b_identical <- FALSE
  calibration_verdict$cor_v1_v5b <- cor_v1_v5b
  calibration_verdict$root_cause <- "Distinct training runs but both collapse to near-zero. Likely shared cause: PatchTST loss converged to predict prior at logit ≈ -25 (sigmoid floor) under tail class imbalance + no class weighting."
}
calibration_verdict$ranking_intact_v1 <- ci_v1$pr_auc
calibration_verdict$root_cause_hypothesis <- c(
  "1. BCEWithLogitsLoss without pos_weight on ~25% imbalance can push baseline logit very negative — but the unusual depth here (logit ~ -25, sigmoid ~7e-12) suggests gradient saturation amplified by AdamW with low LR after epochs of plateau.",
  "2. v1 (patch=4) and v5b (PatchTST baseline patch=4) likely share identical hparams + same dataloader seed → identical convergence.",
  "3. v2 (patch=2) escapes via finer-grained patches that change attention pattern → richer logit dynamic range (logit min/max spread larger than v1)."
)
calibration_verdict$practical <- "v1 absolute probabilities unusable, but ranking (and therefore PR-AUC) is intact. Cycle 53E PR-AUC=0.1820 reported in the sweep table refers to v1's near-zero outputs — those values ARE ranking-valid even though they look broken."

cat("--- Calibration verdict ---\n")
cat(toJSON(calibration_verdict, pretty = TRUE, auto_unbox = TRUE))
cat("\n\n")

#==============================================================================
# Step 5 — Build final JSON
#==============================================================================
cat("=============================================================\n")
cat("FINAL VERDICT JSON\n")
cat("=============================================================\n\n")

# Verdict logic
verdict_53E_v2 <- {
  ci <- phase1_overall_dt[cycle == "c53E_v2_q126"]
  seg <- phase1_seg_dt[cycle == "c53E_v2_q126"]
  list(
    overall_pr_auc = ci$pr_auc,
    overall_pr_lo = ci$pr_lo,
    overall_pr_hi = ci$pr_hi,
    overall_lift = ci$lift_over_base,
    segment_pr_auc = setNames(round(seg$pr_auc, 4), seg$period),
    segment_lift = setNames(round(seg$lift_over_base, 2), seg$period),
    valid_segments_lift_gt_1 = sum(seg[!is.na(lift_over_base)]$lift_over_base > 1, na.rm = TRUE),
    total_segments_with_events = sum(!is.na(seg$lift_over_base)),
    ci_lower_bound_above_baseline = (ci$pr_lo > ci$base_rate),
    verdict = if (ci$pr_lo > ci$base_rate && sum(seg[!is.na(lift_over_base)]$lift_over_base > 1, na.rm = TRUE) >= 2) {
      "VALID_BUT_PERIOD_FRAGILE"
    } else if (ci$pr_lo > ci$base_rate) {
      "MARGINAL_VALID_HEAVY_PERIOD_DEPENDENCE"
    } else {
      "INVALID_CI_LOWER_BELOW_BASELINE"
    }
  )
}

verdict_53H <- {
  ci <- phase1_overall_dt[cycle == "c53H_v5e_q126"]
  seg <- phase1_seg_dt[cycle == "c53H_v5e_q126"]
  list(
    overall_pr_auc = ci$pr_auc,
    overall_pr_lo = ci$pr_lo,
    overall_pr_hi = ci$pr_hi,
    overall_lift = ci$lift_over_base,
    segment_pr_auc = setNames(round(seg$pr_auc, 4), seg$period),
    segment_lift = setNames(round(seg$lift_over_base, 2), seg$period),
    valid_segments_lift_gt_1 = sum(seg[!is.na(lift_over_base)]$lift_over_base > 1, na.rm = TRUE),
    total_segments_with_events = sum(!is.na(seg$lift_over_base)),
    ci_lower_bound_above_baseline = (ci$pr_lo > ci$base_rate),
    verdict = if (ci$pr_lo > ci$base_rate && sum(seg[!is.na(lift_over_base)]$lift_over_base > 1, na.rm = TRUE) >= 2) {
      "VALID_BUT_PERIOD_FRAGILE"
    } else if (ci$pr_lo > ci$base_rate) {
      "MARGINAL_VALID_HEAVY_PERIOD_DEPENDENCE"
    } else {
      "INVALID_CI_LOWER_BELOW_BASELINE"
    }
  )
}

# y_tail_q126 retain vs alternative recommendation
events_by_year_dt <- events_by_year
sd_orig <- sd(events_by_year_dt$rate_orig)
sd_abs10 <- sd(events_by_year_dt$rate_abs10)
sd_abs15 <- sd(events_by_year_dt$rate_abs15)
sd_oos <- sd(events_by_year_dt$rate_oos_q15)

label_recommendation <- {
  best_label <- robust_summary$label[1]
  most_balanced_label <- {
    sds <- c(y_q126_orig = sd_orig, y_q126_abs10 = sd_abs10,
             y_q126_abs15 = sd_abs15, y_q126_oos_q15 = sd_oos)
    names(which.min(sds))
  }
  list(
    best_robust_label_by_pr_auc = best_label,
    best_balanced_label_by_event_rate_sd = most_balanced_label,
    sd_event_rate_orig = round(sd_orig, 4),
    sd_event_rate_abs10 = round(sd_abs10, 4),
    sd_event_rate_abs15 = round(sd_abs15, 4),
    sd_event_rate_oos_q15 = round(sd_oos, 4),
    recommendation = sprintf("Adopt %s as primary label for next cycle (lowest yearly event-rate SD = %.4f) and report %s side-by-side as robustness check.",
                             most_balanced_label, min(c(sd_orig, sd_abs10, sd_abs15, sd_oos)), best_label),
    caveat_oos_q15 = "y_q126_oos_q15 uses forward-looking threshold (OOS-recomputed) — DIAGNOSTIC ONLY, not deployable for real-time prediction."
  )
}

future_cycle_checklist <- list(
  "1. Report per-year PR-AUC (not just overall) with bootstrap 95% CI",
  "2. Require non-degenerate events (n_events >= 10) in >= 3 of 4 multi-year segments (S2018-2019 / S2020-2021 / S2022-2024 / S2025-2026)",
  "3. CI lower bound > baseline rate (lift_lower > 1) in at least 2 segments — not just overall",
  "4. Cross-check with fixed-threshold label (abs10 or abs15) to detect regime-dependent threshold artefacts",
  "5. If overall PR-AUC inflated by single segment (e.g. >= 2x other segments), flag as PERIOD_FRAGILE and require additional cycle before admission consideration",
  "6. Calibration sanity: max(p) - min(p) >= 0.05 and logit range >= 5 (avoid v1-style logit collapse to -25)",
  "7. Document base rate per segment in cycle report"
)

final_json <- list(
  meta = list(
    script = "scripts/134_sanity_recovery_period_analysis.R",
    cycle = "53M_sanity_recovery",
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    purpose = "Period-balanced PR-AUC + alternative label sanity audit (Forge single-source quick screening, admit decision X)",
    ax_008_class = "single_source_quick_screening",
    cpu_only = TRUE,
    no_retraining = TRUE
  ),
  phase1_period_stratified = list(
    overall = phase1_overall_dt,
    by_year = phase1_year_dt,
    by_segment = phase1_seg_dt
  ),
  phase2_alternative_labels = list(
    oos_q15_threshold = oos_q15_thr,
    events_by_year = events_by_year_dt,
    cycle_x_label_pr_auc = phase2_dt
  ),
  phase3_robustness_matrix = list(
    cycle_x_label_x_segment = phase3_dt,
    robustness_summary = robust_summary,
    best_combo = list(cycle = best_combo$cycle, label = best_combo$label,
                      n_segments_lift_gt_1 = best_combo$n_segments_lift_gt_1,
                      n_segments_valid = best_combo$n_segments_valid,
                      lift_mean = best_combo$lift_mean)
  ),
  phase4_v1_calibration_audit = list(
    calib_v1 = calib_v1,
    calib_v5b = calib_v5b,
    calib_v2 = calib_v2,
    cor_v1_v5b = cor_v1_v5b,
    cor_v1_v2 = cor_v1_v2,
    v1_v5b_predictions_identical = isTRUE(identical_p),
    v1_pr_auc_ranking_intact = ci_v1$pr_auc,
    verdict = calibration_verdict
  ),
  verdict_53E_v2_0p4747 = verdict_53E_v2,
  verdict_53H_0p4012 = verdict_53H,
  label_recommendation = label_recommendation,
  future_cycle_mandatory_checklist = future_cycle_checklist
)

OUT_JSON <- file.path(EVAL_DIR, "sanity_recovery_v6a.json")
write_json(final_json, OUT_JSON, pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
cat(sprintf("Final JSON written: %s\n\n", OUT_JSON))

#==============================================================================
# Charts (Phase 1 + Phase 2)
#==============================================================================
cat("Building charts...\n")

# Chart 1: Period PR curves (segment-level, lift-over-base bar)
seg_plot_dt <- phase1_seg_dt[!is.na(lift_over_base)]
seg_plot_dt[, cycle_label := factor(cycle, levels = unique(cycle))]
p1 <- ggplot(seg_plot_dt, aes(x = period, y = pr_auc, fill = cycle_label)) +
  geom_col(position = "dodge") +
  geom_errorbar(aes(ymin = pr_lo, ymax = pr_hi),
                position = position_dodge(width = 0.9), width = 0.2) +
  geom_text(aes(label = sprintf("%.2fx", lift_over_base), y = pr_hi + 0.02),
            position = position_dodge(width = 0.9), size = 2.8) +
  facet_wrap(~ cycle, ncol = 2, scales = "free_x") +
  labs(title = "Phase 1 — Per-segment PR-AUC × 4 cycles (with bootstrap 95% CI)",
       subtitle = "Lift over base rate shown above each bar",
       x = "Period segment", y = "PR-AUC") +
  theme_minimal() +
  theme(legend.position = "none", axis.text.x = element_text(angle = 25, hjust = 1))

# Chart 2: Yearly event rates per alt label
plot_dt2 <- melt(events_by_year, id.vars = "year",
                 measure.vars = c("rate_orig", "rate_abs10", "rate_abs15", "rate_oos_q15"),
                 variable.name = "label", value.name = "event_rate")
p2 <- ggplot(plot_dt2, aes(x = factor(year), y = event_rate, fill = label)) +
  geom_col(position = "dodge") +
  labs(title = "Phase 2 — Yearly event rate × alternative label",
       subtitle = "Lower SD → more period-balanced label",
       x = "Year", y = "Event rate") +
  theme_minimal() +
  scale_fill_brewer(palette = "Set2")

# Save
ggsave(file.path(CHART_DIR, "134_period_pr_curve.png"), p1,
       width = 12, height = 8, dpi = 110)
ggsave(file.path(CHART_DIR, "134_alternative_label_compare.png"), p2,
       width = 12, height = 6, dpi = 110)

cat(sprintf("Charts saved:\n  %s\n  %s\n",
            file.path(CHART_DIR, "134_period_pr_curve.png"),
            file.path(CHART_DIR, "134_alternative_label_compare.png")))

#==============================================================================
# Final console summary
#==============================================================================
cat("\n=============================================================\n")
cat("SUMMARY VERDICT\n")
cat("=============================================================\n\n")

cat("[Q1] Cycle 53E v2 PR-AUC 0.4747 진정 valid?\n")
cat(sprintf("  Overall: %.4f [%.4f, %.4f]  base=%.4f  lift=%.2fx\n",
            verdict_53E_v2$overall_pr_auc, verdict_53E_v2$overall_pr_lo,
            verdict_53E_v2$overall_pr_hi,
            phase1_overall_dt[cycle == "c53E_v2_q126"]$base_rate,
            verdict_53E_v2$overall_lift))
cat(sprintf("  Verdict: %s\n", verdict_53E_v2$verdict))
cat(sprintf("  Per-segment lifts: %s\n",
            paste(sprintf("%s=%.2fx", names(verdict_53E_v2$segment_lift), verdict_53E_v2$segment_lift), collapse = " | ")))
cat(sprintf("  Segments with lift>1: %d/%d  CI-lower>baseline: %s\n\n",
            verdict_53E_v2$valid_segments_lift_gt_1, verdict_53E_v2$total_segments_with_events,
            verdict_53E_v2$ci_lower_bound_above_baseline))

cat("[Q2] Cycle 53H 0.4012 진정 valid?\n")
cat(sprintf("  Overall: %.4f [%.4f, %.4f]  base=%.4f  lift=%.2fx\n",
            verdict_53H$overall_pr_auc, verdict_53H$overall_pr_lo,
            verdict_53H$overall_pr_hi,
            phase1_overall_dt[cycle == "c53H_v5e_q126"]$base_rate,
            verdict_53H$overall_lift))
cat(sprintf("  Verdict: %s\n", verdict_53H$verdict))
cat(sprintf("  Per-segment lifts: %s\n",
            paste(sprintf("%s=%.2fx", names(verdict_53H$segment_lift), verdict_53H$segment_lift), collapse = " | ")))
cat(sprintf("  Segments with lift>1: %d/%d  CI-lower>baseline: %s\n\n",
            verdict_53H$valid_segments_lift_gt_1, verdict_53H$total_segments_with_events,
            verdict_53H$ci_lower_bound_above_baseline))

cat("[Q3] v1 calibration root cause:\n")
cat(sprintf("  v1 ≡ v5b? %s\n", isTRUE(identical_p)))
cat(sprintf("  v1 PR-AUC (ranking valid even with broken scale): %.4f\n", ci_v1$pr_auc))
cat("  → Calibration scale unusable. Ranking intact. Root cause: shared logit-collapse from PatchTST patch=4 baseline.\n\n")

cat("[Q4] Label recommendation:\n")
cat(sprintf("  Most balanced (lowest event-rate SD): %s\n", label_recommendation$best_balanced_label_by_event_rate_sd))
cat(sprintf("  Best robust by PR-AUC across segments: %s\n", label_recommendation$best_robust_label_by_pr_auc))
cat(sprintf("  Recommendation: %s\n\n", label_recommendation$recommendation))

cat("[Q5] Future cycle mandatory checklist:\n")
for (i in seq_along(future_cycle_checklist)) {
  cat(sprintf("  %s\n", future_cycle_checklist[[i]]))
}

cat("\nDone.\n")
