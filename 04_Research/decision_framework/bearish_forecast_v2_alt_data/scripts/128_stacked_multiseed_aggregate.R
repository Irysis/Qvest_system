#==============================================================================
# 128_stacked_multiseed_aggregate.R — Cycle 53C Stacked Multi-Seed Aggregate
#
# Reads:
#   outputs/03_models/v5c_stacked_multiseed/predictions_stacked_seed{42|123|456}_y_{tail_q15|onset}.parquet (6 files)
#   outputs/03_models/v5c_stacked_multiseed/predictions_stacked_mean_y_{tail_q15|onset}.parquet (2 files)
#   outputs/03_models/v5c_stacked_multiseed/per_fold_diagnostics.json
#   outputs/03_models/v5c_stacked_multiseed/multiseed_variance_audit.json
#   outputs/03_models/v5a_patchtst_sweep/predictions_patchtst_v10_y_tail_q15.parquet (v10 reference)
#   outputs/03_models/v5a_patchtst_sweep/predictions_patchtst_v1_y_tail_q15.parquet  (v1 baseline)
#
# Steps:
#   Step 1: Per-seed OOS PR-AUC + IC (re-verify Python aggregation)
#   Step 2: 3-seed mean prediction PR-AUC (R re-compute)
#   Step 3: Multi-seed stability verdict (STABLE / MODERATE / UNSTABLE)
#   Step 4: vs Cycle 53A v10 (single seed=42) — additivity verdict
#   Step 5: vs cross-cycle baselines (Cycle 52 PatchTST 0.2463 / Cycle 43 forward 0.2129)
#   Step 6: Per-date prediction std audit (Cycle 52 N-BEATS pattern)
#   Step 7: NEW_CYCLE_CHECKLIST status
#   Step 8: Output JSON + chart
#
# Output:
#   outputs/04_evaluation/stacked_multiseed_v5c.json
#   outputs/06_reports/charts/128_stacked_multiseed.png
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2)
  library(patchwork)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
STACK_DIR <- file.path(WS, "outputs/03_models/v5c_stacked_multiseed")
SWEEP_DIR <- file.path(WS, "outputs/03_models/v5a_patchtst_sweep")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")
dir.create(EVAL_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

OOS_START <- as.Date("2018-01-01")
OOS_END   <- as.Date("2026-04-30")

SEEDS <- c(42L, 123L, 456L)
TARGETS <- c("y_tail_q15", "y_onset")

# Mandate thresholds (Cycle 53C report)
ADDITIVITY_STRONG_DELTA <- 0.02
ADDITIVITY_WEAK_DELTA   <- 0.005

STABILITY_STABLE_STD   <- 0.02
STABILITY_MODERATE_STD <- 0.05

# Cross-cycle reference points (from prior cycles)
CYCLE_53A_V10_Q15        <- 0.2598   # Cycle 53A winner single seed=42
CYCLE_53A_V10_ONSET      <- 0.1443
CYCLE_53A_V1_Q15         <- 0.2396
CYCLE_53A_V1_ONSET       <- 0.1332
CYCLE_52_PT_Q15          <- 0.2463
CYCLE_52_PT_ONSET        <- 0.1372
CYCLE_43_FORWARD_BEST_Q15 <- 0.2129  # M4_Bayes forward best

pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

ic_pearson_rank <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30) return(NA_real_)
  cor(rank(p), rank(y), method = "pearson")
}

#==============================================================================
# Load Python diagnostics
#==============================================================================
diag_path <- file.path(STACK_DIR, "per_fold_diagnostics.json")
audit_path <- file.path(STACK_DIR, "multiseed_variance_audit.json")
if (!file.exists(diag_path)) {
  stop(sprintf("Missing per_fold_diagnostics: %s\n  Run scripts/127_patchtst_stacked_multiseed.py first.",
               diag_path))
}
if (!file.exists(audit_path)) {
  stop(sprintf("Missing multiseed_variance_audit: %s\n  Run scripts/127_patchtst_stacked_multiseed.py first.",
               audit_path))
}
py_diag <- fromJSON(diag_path, simplifyVector = FALSE)
py_audit <- fromJSON(audit_path, simplifyVector = FALSE)

cat(sprintf("\n[Loaded] per_fold_diagnostics.json + multiseed_variance_audit.json\n"))
cat(sprintf("[Stacked config] %s\n", py_diag$stacked_config$name))
cat(sprintf("  d_model=%s n_layers=%s dropout=%s patch_size=%s n_heads=%s\n",
            py_diag$stacked_config$d_model, py_diag$stacked_config$n_layers,
            py_diag$stacked_config$dropout, py_diag$stacked_config$patch_size,
            py_diag$stacked_config$n_heads))

#==============================================================================
# Step 1: Per-seed OOS PR-AUC + IC re-verify
#==============================================================================
cat("\n========== Step 1: Per-seed OOS PR-AUC + IC (R verification) ==========\n")

aggregate_seed <- function(seed, target_col) {
  pred_path <- file.path(STACK_DIR,
                         sprintf("predictions_stacked_seed%d_%s.parquet", seed, target_col))
  if (!file.exists(pred_path)) {
    return(list(seed = seed, target = target_col, error = "missing_prediction_file",
                oos_pr = NA_real_, oos_ic = NA_real_))
  }
  dt <- as.data.table(read_parquet(pred_path))
  dt[, Date := as.Date(Date)]
  dt <- dt[Date >= OOS_START & Date <= OOS_END & !is.na(p_patchtst_stacked) & !is.na(y)]
  pa <- pr_auc(dt$p_patchtst_stacked, dt$y)
  ic <- ic_pearson_rank(dt$p_patchtst_stacked, dt$y)
  list(
    seed = seed, target = target_col,
    n_obs = nrow(dt), n_events = sum(dt$y),
    event_rate = round(mean(dt$y), 4),
    oos_pr = round(pa, 4), oos_ic = round(ic, 4)
  )
}

per_seed_rows <- list()
for (s in SEEDS) for (tc in TARGETS) {
  per_seed_rows[[length(per_seed_rows) + 1]] <- aggregate_seed(s, tc)
}

per_seed_dt <- rbindlist(lapply(per_seed_rows, function(r) {
  data.table(
    seed = r$seed, target = r$target,
    n_obs = if (is.null(r$n_obs)) NA_integer_ else r$n_obs,
    n_events = if (is.null(r$n_events)) NA_integer_ else r$n_events,
    event_rate = if (is.null(r$event_rate)) NA_real_ else r$event_rate,
    oos_pr = r$oos_pr, oos_ic = r$oos_ic
  )
}), fill = TRUE)

cat("\n[Per-seed table]\n")
print(per_seed_dt)

#==============================================================================
# Step 2: 3-seed mean prediction PR-AUC (R re-compute)
#==============================================================================
cat("\n========== Step 2: 3-seed mean prediction PR-AUC (R verify) ==========\n")

aggregate_mean <- function(target_col) {
  pred_path <- file.path(STACK_DIR,
                         sprintf("predictions_stacked_mean_%s.parquet", target_col))
  if (!file.exists(pred_path)) {
    return(list(target = target_col, error = "missing_mean_file",
                oos_pr_mean = NA_real_, oos_ic_mean = NA_real_))
  }
  dt <- as.data.table(read_parquet(pred_path))
  dt[, Date := as.Date(Date)]
  dt <- dt[Date >= OOS_START & Date <= OOS_END & !is.na(p_patchtst_stacked_mean) & !is.na(y)]
  pa <- pr_auc(dt$p_patchtst_stacked_mean, dt$y)
  ic <- ic_pearson_rank(dt$p_patchtst_stacked_mean, dt$y)
  per_date_std_mean <- mean(dt$p_per_seed_std, na.rm = TRUE)
  per_date_std_med  <- median(dt$p_per_seed_std, na.rm = TRUE)
  per_date_std_max  <- max(dt$p_per_seed_std, na.rm = TRUE)
  list(
    target = target_col, n_obs = nrow(dt), n_events = sum(dt$y),
    event_rate = round(mean(dt$y), 4),
    oos_pr_mean = round(pa, 4), oos_ic_mean = round(ic, 4),
    per_date_std_mean = round(per_date_std_mean, 4),
    per_date_std_median = round(per_date_std_med, 4),
    per_date_std_max = round(per_date_std_max, 4)
  )
}

mean_rows <- list()
for (tc in TARGETS) {
  mean_rows[[tc]] <- aggregate_mean(tc)
}

cat("\n[3-seed mean prediction]\n")
for (tc in TARGETS) {
  r <- mean_rows[[tc]]
  cat(sprintf(paste0("  %s: PR-AUC=%.4f IC=%.4f n_obs=%d n_events=%d ",
                     "per_date_std mean=%.4f / median=%.4f / max=%.4f\n"),
              tc, r$oos_pr_mean, r$oos_ic_mean, r$n_obs, r$n_events,
              r$per_date_std_mean, r$per_date_std_median, r$per_date_std_max))
}

#==============================================================================
# Step 3: Multi-seed stability verdict
#==============================================================================
cat("\n========== Step 3: Multi-seed stability verdict ==========\n")

stability_table <- per_seed_dt[, .(
  n_seeds = .N,
  mean_pr = round(mean(oos_pr, na.rm = TRUE), 4),
  std_pr  = round(sd(oos_pr, na.rm = TRUE), 4),
  min_pr  = round(min(oos_pr, na.rm = TRUE), 4),
  max_pr  = round(max(oos_pr, na.rm = TRUE), 4),
  range_pr = round(max(oos_pr, na.rm = TRUE) - min(oos_pr, na.rm = TRUE), 4)
), by = target]

stability_table[, stability_verdict := fcase(
  std_pr < STABILITY_STABLE_STD, "STABLE",
  std_pr <= STABILITY_MODERATE_STD, "MODERATE",
  default = "UNSTABLE"
)]

cat("\n[Stability per target]\n")
print(stability_table)

#==============================================================================
# Step 4: vs Cycle 53A v10 single-seed — additivity verdict
#==============================================================================
cat("\n========== Step 4: vs Cycle 53A v10 (single seed=42) — additivity ==========\n")

# v10 reference (single seed=42 OOS PR-AUC from sweep)
# Use the more conservative single seed=42 comparison + 3-seed mean comparison

mean_pr_q15 <- mean_rows[["y_tail_q15"]]$oos_pr_mean
mean_pr_ons <- mean_rows[["y_onset"]]$oos_pr_mean

# Stacked seed=42 (matched single seed)
stacked_s42_q15 <- per_seed_dt[seed == 42L & target == "y_tail_q15", oos_pr]
stacked_s42_ons <- per_seed_dt[seed == 42L & target == "y_onset", oos_pr]

# Delta vs v10 (single-seed comparison)
delta_s42_v10_q15 <- stacked_s42_q15 - CYCLE_53A_V10_Q15
delta_s42_v10_ons <- stacked_s42_ons - CYCLE_53A_V10_ONSET

# Delta vs v10 (3-seed mean comparison; more robust)
delta_mean_v10_q15 <- mean_pr_q15 - CYCLE_53A_V10_Q15
delta_mean_v10_ons <- mean_pr_ons - CYCLE_53A_V10_ONSET

# Per-seed mean comparison (cleaner cross-seed view)
mean_per_seed_q15 <- stability_table[target == "y_tail_q15", mean_pr]
mean_per_seed_ons <- stability_table[target == "y_onset", mean_pr]
delta_mean_seed_v10_q15 <- mean_per_seed_q15 - CYCLE_53A_V10_Q15
delta_mean_seed_v10_ons <- mean_per_seed_ons - CYCLE_53A_V10_ONSET

cat(sprintf("\n[Cycle 53A v10 reference] y_tail_q15=%.4f / y_onset=%.4f (single seed=42)\n",
            CYCLE_53A_V10_Q15, CYCLE_53A_V10_ONSET))

cat(sprintf("\n[Stacked seed=42 (match) vs v10] q15: %.4f Δ%+.4f / onset: %.4f Δ%+.4f\n",
            stacked_s42_q15, delta_s42_v10_q15, stacked_s42_ons, delta_s42_v10_ons))

cat(sprintf("\n[Stacked 3-seed mean prediction vs v10] q15: %.4f Δ%+.4f / onset: %.4f Δ%+.4f\n",
            mean_pr_q15, delta_mean_v10_q15, mean_pr_ons, delta_mean_v10_ons))

cat(sprintf("\n[Stacked across-seed mean PR-AUC vs v10] q15: %.4f Δ%+.4f / onset: %.4f Δ%+.4f\n",
            mean_per_seed_q15, delta_mean_seed_v10_q15, mean_per_seed_ons, delta_mean_seed_v10_ons))

# Additivity verdict: use 3-seed mean prediction (more robust than single seed=42 match)
classify_additivity <- function(delta) {
  if (is.na(delta)) return("N/A")
  if (delta >= ADDITIVITY_STRONG_DELTA) return("ADDITIVE_STRONG")
  if (delta >= ADDITIVITY_WEAK_DELTA)   return("ADDITIVE_WEAK")
  if (delta > -ADDITIVITY_WEAK_DELTA)   return("NON_ADDITIVE")
  return("NEGATIVE")
}

add_verdict_meanpred_q15 <- classify_additivity(delta_mean_v10_q15)
add_verdict_meanpred_ons <- classify_additivity(delta_mean_v10_ons)
add_verdict_seedmean_q15 <- classify_additivity(delta_mean_seed_v10_q15)
add_verdict_seedmean_ons <- classify_additivity(delta_mean_seed_v10_ons)
add_verdict_s42_q15 <- classify_additivity(delta_s42_v10_q15)

cat(sprintf("\n[Additivity verdict — 3-seed mean prediction]\n"))
cat(sprintf("  y_tail_q15: %s (Δ=%+.4f vs v10)\n", add_verdict_meanpred_q15, delta_mean_v10_q15))
cat(sprintf("  y_onset:    %s (Δ=%+.4f vs v10)\n", add_verdict_meanpred_ons, delta_mean_v10_ons))

cat(sprintf("\n[Additivity verdict — across-seed mean PR-AUC]\n"))
cat(sprintf("  y_tail_q15: %s (Δ=%+.4f vs v10)\n", add_verdict_seedmean_q15, delta_mean_seed_v10_q15))
cat(sprintf("  y_onset:    %s (Δ=%+.4f vs v10)\n", add_verdict_seedmean_ons, delta_mean_seed_v10_ons))

cat(sprintf("\n[Sanity — stacked seed=42 matched comparison]\n"))
cat(sprintf("  y_tail_q15 Δ=%+.4f → %s (single seed=42, same as v10 seed)\n",
            delta_s42_v10_q15, add_verdict_s42_q15))

#==============================================================================
# Step 5: vs cross-cycle baselines
#==============================================================================
cat("\n========== Step 5: vs cross-cycle baselines ==========\n")

cat(sprintf("\n[y_tail_q15 cross-cycle ladder]\n"))
cat(sprintf("  Cycle 43 forward best (M4_Bayes):     %.4f\n", CYCLE_43_FORWARD_BEST_Q15))
cat(sprintf("  Cycle 52 PatchTST baseline:           %.4f\n", CYCLE_52_PT_Q15))
cat(sprintf("  Cycle 53A v1 (replication baseline):  %.4f\n", CYCLE_53A_V1_Q15))
cat(sprintf("  Cycle 53A v10 (dropout=0.20 winner):  %.4f\n", CYCLE_53A_V10_Q15))
cat(sprintf("  Cycle 53C stacked seed=42:            %.4f (Δ%+.4f vs v10 / Δ%+.4f vs Cycle 43 fwd best)\n",
            stacked_s42_q15, stacked_s42_q15 - CYCLE_53A_V10_Q15,
            stacked_s42_q15 - CYCLE_43_FORWARD_BEST_Q15))
cat(sprintf("  Cycle 53C stacked across-seed mean PR-AUC: %.4f (Δ%+.4f vs v10 / Δ%+.4f vs Cycle 43 fwd best)\n",
            mean_per_seed_q15, mean_per_seed_q15 - CYCLE_53A_V10_Q15,
            mean_per_seed_q15 - CYCLE_43_FORWARD_BEST_Q15))
cat(sprintf("  Cycle 53C stacked 3-seed mean prediction:  %.4f (Δ%+.4f vs v10 / Δ%+.4f vs Cycle 43 fwd best)\n",
            mean_pr_q15, mean_pr_q15 - CYCLE_53A_V10_Q15,
            mean_pr_q15 - CYCLE_43_FORWARD_BEST_Q15))

cat(sprintf("\n[y_onset cross-cycle ladder]\n"))
cat(sprintf("  Cycle 52 PatchTST baseline:           %.4f\n", CYCLE_52_PT_ONSET))
cat(sprintf("  Cycle 53A v1:                          %.4f\n", CYCLE_53A_V1_ONSET))
cat(sprintf("  Cycle 53A v10:                         %.4f\n", CYCLE_53A_V10_ONSET))
cat(sprintf("  Cycle 53C stacked seed=42:            %.4f\n", stacked_s42_ons))
cat(sprintf("  Cycle 53C stacked across-seed mean:   %.4f\n", mean_per_seed_ons))
cat(sprintf("  Cycle 53C stacked 3-seed mean pred:   %.4f\n", mean_pr_ons))

#==============================================================================
# Step 6: Per-date prediction std audit (Cycle 52 N-BEATS pattern)
#==============================================================================
cat("\n========== Step 6: Per-date prediction std audit ==========\n")

cat("\n[Per-date std (lower = more consistent across seeds)]\n")
for (tc in TARGETS) {
  r <- mean_rows[[tc]]
  cat(sprintf("  %s: mean=%.4f / median=%.4f / max=%.4f / n=%d\n",
              tc, r$per_date_std_mean, r$per_date_std_median, r$per_date_std_max, r$n_obs))
}

# Cross-target rank consistency check (NEW_CYCLE_CHECKLIST S3 proxy)
mean_q15_dt <- as.data.table(read_parquet(file.path(
  STACK_DIR, "predictions_stacked_mean_y_tail_q15.parquet")))
mean_q15_dt[, Date := as.Date(Date)]
mean_q15_dt <- mean_q15_dt[Date >= OOS_START & Date <= OOS_END]

mean_ons_dt <- as.data.table(read_parquet(file.path(
  STACK_DIR, "predictions_stacked_mean_y_onset.parquet")))
mean_ons_dt[, Date := as.Date(Date)]
mean_ons_dt <- mean_ons_dt[Date >= OOS_START & Date <= OOS_END]

merged <- merge(
  mean_q15_dt[, .(Date, p_q15 = p_patchtst_stacked_mean)],
  mean_ons_dt[, .(Date, p_ons = p_patchtst_stacked_mean)],
  by = "Date"
)
rho_across_targets <- if (nrow(merged) >= 30) {
  cor(rank(merged$p_q15), rank(merged$p_ons), method = "pearson")
} else NA_real_
cat(sprintf("\n[Cross-target rank consistency] Spearman rho(stacked mean q15, stacked mean onset) = %.4f\n",
            rho_across_targets))

#==============================================================================
# Step 7: NEW_CYCLE_CHECKLIST status
#==============================================================================
cat("\n========== Step 7: NEW_CYCLE_CHECKLIST status ==========\n")

# Headline numerics used in the verdict
headline_pr <- mean_pr_q15  # 3-seed mean prediction PR-AUC on y_tail_q15
within_sanity <- (headline_pr >= 0.15) && (headline_pr <= 0.40)
sanity_msg <- if (within_sanity) {
  sprintf("PASS (3-seed mean prediction PR-AUC %.4f ∈ [0.15, 0.40])", headline_pr)
} else if (headline_pr > 0.40) {
  sprintf("WARN (%.4f > 0.40 — sanity check repeat 의무 per NEW_CYCLE_CHECKLIST S1)", headline_pr)
} else {
  sprintf("FAIL (%.4f < 0.15 — model has no value vs base rate)", headline_pr)
}

checklist <- list(
  M1_bear_date_audit = "PASS (pre-cycle 4/4, latest log retained in qepm/observability/sanity_checks)",
  M2_validate_label_direction = "PASS (forward labels via Cycle 50 fix, inherited from Cycle 52/53A)",
  M3_PIT_C1_C15 = "PASS (v4a panel PIT validated Cycle 52, no new data introduced)",
  M4_shift_convention = "PASS (forward targets via shift(.,n=H,'lead'), inherited)",
  M5_AX_008 = "EXEMPT (Forge single-source quick screening, NOT admit cycle)",
  S1_PRAUC_sanity = sanity_msg,
  S2_COVID_spot_check = "PASS (targets_full.parquet 2020-02-19 ret_h = -0.3405, inherited)",
  S3_cross_target_rank_consistency = sprintf("rho=%.4f", rho_across_targets),
  A1_cross_cycle_same_forward_labels = "PASS (all seeds + v10 use targets_full.parquet forward labels)",
  A2_dohun_audit_checkpoint = "AWAITING_REVIEW",
  A3_codex_critic = if (add_verdict_meanpred_q15 == "ADDITIVE_STRONG") {
    "TRIGGERED (ADDITIVE_STRONG → admit pathway mandatory)"
  } else {
    sprintf("DEFER (Forge multi-seed audit; verdict=%s)", add_verdict_meanpred_q15)
  }
)

cat("\n[NEW_CYCLE_CHECKLIST]\n")
for (k in names(checklist)) cat(sprintf("  %s: %s\n", k, checklist[[k]]))

#==============================================================================
# Step 8: Output JSON + chart
#==============================================================================
cat("\n========== Step 8: Output JSON + chart ==========\n")

# Final combined verdict
stab_q15 <- stability_table[target == "y_tail_q15", stability_verdict]
stab_ons <- stability_table[target == "y_onset",    stability_verdict]

cycle_verdict <- list(
  additivity_q15_mean_prediction = add_verdict_meanpred_q15,
  additivity_q15_across_seed_mean = add_verdict_seedmean_q15,
  additivity_q15_seed42_match = add_verdict_s42_q15,
  additivity_onset_mean_prediction = add_verdict_meanpred_ons,
  stability_q15 = stab_q15,
  stability_onset = stab_ons,
  primary_summary = sprintf(
    paste0("Stacked PatchTST (d_model=32 / n_layers=2 / dropout=0.20): ",
           "y_tail_q15 mean-prediction PR-AUC=%.4f (Δ%+.4f vs v10 → %s additivity) | ",
           "across-seed std=%.4f → %s stability | seed=42 match Δ%+.4f → %s"),
    mean_pr_q15, delta_mean_v10_q15, add_verdict_meanpred_q15,
    stability_table[target == "y_tail_q15", std_pr], stab_q15,
    delta_s42_v10_q15, add_verdict_s42_q15
  )
)

if (add_verdict_meanpred_q15 == "ADDITIVE_STRONG" && stab_q15 == "STABLE") {
  next_cycle_suggestion <- paste0(
    "LOCK headline: stacked PatchTST 3-seed mean as new SOT. ",
    "Spawn Codex + Architect AX-008 admit pathway. ",
    "Secondary axis sweep (lr / weight_decay / scheduler) on locked stacked baseline next."
  )
} else if (add_verdict_meanpred_q15 %in% c("ADDITIVE_STRONG", "ADDITIVE_WEAK") && stab_q15 == "MODERATE") {
  next_cycle_suggestion <- paste0(
    "Promising but moderate seed variance — extend to 5+ seeds before headline lock. ",
    "Capture per-fold variance trace for ICIR robustness assessment."
  )
} else if (add_verdict_meanpred_q15 %in% c("ADDITIVE_STRONG", "ADDITIVE_WEAK") && stab_q15 == "UNSTABLE") {
  next_cycle_suggestion <- paste0(
    "Multi-seed UNSTABLE invalidates single-seed v10 headline. Revert to v1 baseline. ",
    "Investigate seed sensitivity origin (data augmentation / pos_weight cap / batch_size scaling)."
  )
} else if (add_verdict_meanpred_q15 == "NON_ADDITIVE") {
  next_cycle_suggestion <- paste0(
    "Combine of 3 axes -> no gain over single best axis (v10 dropout). ",
    "v10 dropout reduction the only effective axis. ",
    "Hold v10 + run secondary axis sweep (lr / weight_decay / scheduler) on dropout=0.20 baseline."
  )
} else if (add_verdict_meanpred_q15 == "NEGATIVE") {
  next_cycle_suggestion <- paste0(
    "3-axis combine -> dilution (worse than v10 single axis). ",
    "v10 single-axis dropout is correct headline. Stop combine; ",
    "pivot to architecture-side exploration (DLinear / Informer / FEDformer / TimesNet)."
  )
} else {
  next_cycle_suggestion <- "Unable to classify; manual review required."
}

result_json <- list(
  cycle = "53C_patchtst_stacked_multiseed",
  panel = "feature_panel_v4a_combined.parquet",
  n_features = 70,
  forward_labels = TRUE,
  validation_strategy = "walk_forward_expanding_5_fold_CV",
  oos_window = list(start = as.character(OOS_START), end = as.character(OOS_END)),
  stacked_config = py_diag$stacked_config,
  seeds = SEEDS,
  targets = TARGETS,
  references = list(
    cycle_43_forward_best_q15 = CYCLE_43_FORWARD_BEST_Q15,
    cycle_52_patchtst_q15 = CYCLE_52_PT_Q15,
    cycle_52_patchtst_onset = CYCLE_52_PT_ONSET,
    cycle_53a_v1_q15 = CYCLE_53A_V1_Q15,
    cycle_53a_v1_onset = CYCLE_53A_V1_ONSET,
    cycle_53a_v10_q15 = CYCLE_53A_V10_Q15,
    cycle_53a_v10_onset = CYCLE_53A_V10_ONSET
  ),
  thresholds = list(
    additivity_strong_delta = ADDITIVITY_STRONG_DELTA,
    additivity_weak_delta = ADDITIVITY_WEAK_DELTA,
    stability_stable_std = STABILITY_STABLE_STD,
    stability_moderate_std = STABILITY_MODERATE_STD,
    sanity_pr_min = 0.15,
    sanity_pr_max = 0.40
  ),
  per_seed_results = setNames(
    lapply(seq_len(nrow(per_seed_dt)), function(i) {
      list(
        seed = per_seed_dt$seed[i],
        target = per_seed_dt$target[i],
        oos_pr = per_seed_dt$oos_pr[i],
        oos_ic = per_seed_dt$oos_ic[i],
        n_obs = per_seed_dt$n_obs[i],
        n_events = per_seed_dt$n_events[i],
        event_rate = per_seed_dt$event_rate[i]
      )
    }),
    sprintf("seed%d_%s", per_seed_dt$seed, per_seed_dt$target)
  ),
  stability_per_target = setNames(
    lapply(seq_len(nrow(stability_table)), function(i) {
      list(
        target = stability_table$target[i],
        n_seeds = stability_table$n_seeds[i],
        mean_pr_across_seeds = stability_table$mean_pr[i],
        std_pr_across_seeds = stability_table$std_pr[i],
        min_pr = stability_table$min_pr[i],
        max_pr = stability_table$max_pr[i],
        range_pr = stability_table$range_pr[i],
        stability_verdict = stability_table$stability_verdict[i]
      )
    }),
    stability_table$target
  ),
  mean_prediction = setNames(
    lapply(TARGETS, function(tc) {
      r <- mean_rows[[tc]]
      list(
        target = tc,
        n_obs = r$n_obs,
        n_events = r$n_events,
        event_rate = r$event_rate,
        oos_pr_mean_prediction = r$oos_pr_mean,
        oos_ic_mean_prediction = r$oos_ic_mean,
        per_date_std_mean = r$per_date_std_mean,
        per_date_std_median = r$per_date_std_median,
        per_date_std_max = r$per_date_std_max
      )
    }),
    TARGETS
  ),
  vs_cycle_53a_v10 = list(
    y_tail_q15 = list(
      v10_reference = CYCLE_53A_V10_Q15,
      stacked_seed42_match = round(stacked_s42_q15, 4),
      stacked_seed42_match_delta = round(delta_s42_v10_q15, 4),
      stacked_across_seed_mean_pr = round(mean_per_seed_q15, 4),
      stacked_across_seed_mean_delta = round(delta_mean_seed_v10_q15, 4),
      stacked_3seed_mean_prediction = round(mean_pr_q15, 4),
      stacked_3seed_mean_prediction_delta = round(delta_mean_v10_q15, 4),
      additivity_verdict_mean_prediction = add_verdict_meanpred_q15,
      additivity_verdict_across_seed_mean = add_verdict_seedmean_q15,
      additivity_verdict_seed42_match = add_verdict_s42_q15
    ),
    y_onset = list(
      v10_reference = CYCLE_53A_V10_ONSET,
      stacked_seed42_match = round(stacked_s42_ons, 4),
      stacked_seed42_match_delta = round(delta_s42_v10_ons, 4),
      stacked_across_seed_mean_pr = round(mean_per_seed_ons, 4),
      stacked_across_seed_mean_delta = round(delta_mean_seed_v10_ons, 4),
      stacked_3seed_mean_prediction = round(mean_pr_ons, 4),
      stacked_3seed_mean_prediction_delta = round(delta_mean_v10_ons, 4),
      additivity_verdict_mean_prediction = add_verdict_meanpred_ons
    )
  ),
  cross_target_rank_consistency_spearman = round(rho_across_targets, 4),
  cycle_verdict = cycle_verdict,
  next_cycle_suggestion = next_cycle_suggestion,
  new_cycle_checklist = checklist,
  python_per_fold_diag = py_diag,
  python_audit = py_audit
)

out_json <- file.path(EVAL_DIR, "stacked_multiseed_v5c.json")
write_json(result_json, out_json, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[JSON] %s\n", out_json))

#==============================================================================
# Chart: 3 panels
#   (A) Per-seed PR-AUC bar (3 seeds × 2 targets) with v10 + Cycle 52 + Cycle 43 reference lines
#   (B) Per-date prediction std distribution (y_tail_q15)
#   (C) Cross-cycle progression: Cycle 43 → 52 → 53A v1 → 53A v10 → 53C stacked
#==============================================================================

# Panel A
plot_dt_a <- copy(per_seed_dt)
plot_dt_a[, seed_label := factor(sprintf("seed=%d", seed),
                                  levels = sapply(SEEDS, function(s) sprintf("seed=%d", s)))]
plot_dt_a[, target_label := ifelse(target == "y_tail_q15",
                                    "y_tail_q15 (primary)",
                                    "y_onset (secondary)")]

# Add mean prediction row per target for visualization
plot_extra <- rbindlist(lapply(TARGETS, function(tc) {
  data.table(seed = -1L, target = tc, n_obs = NA_integer_, n_events = NA_integer_,
             event_rate = NA_real_,
             oos_pr = mean_rows[[tc]]$oos_pr_mean,
             oos_ic = mean_rows[[tc]]$oos_ic_mean,
             seed_label = "3-seed mean pred",
             target_label = ifelse(tc == "y_tail_q15", "y_tail_q15 (primary)", "y_onset (secondary)"))
}), fill = TRUE)
plot_extra[, seed_label := factor("3-seed mean pred",
                                   levels = c(sapply(SEEDS, function(s) sprintf("seed=%d", s)),
                                              "3-seed mean pred"))]

plot_dt_a_full <- rbind(plot_dt_a, plot_extra, fill = TRUE)
plot_dt_a_full[, seed_label := factor(seed_label,
                                       levels = c(sapply(SEEDS, function(s) sprintf("seed=%d", s)),
                                                  "3-seed mean pred"))]

ref_dt <- rbindlist(list(
  data.table(target_label = "y_tail_q15 (primary)",
             ref_label = "Cycle 53A v10", ref_value = CYCLE_53A_V10_Q15, ref_color = "darkorange"),
  data.table(target_label = "y_tail_q15 (primary)",
             ref_label = "Cycle 52 PatchTST",  ref_value = CYCLE_52_PT_Q15, ref_color = "darkgreen"),
  data.table(target_label = "y_tail_q15 (primary)",
             ref_label = "Cycle 43 fwd best", ref_value = CYCLE_43_FORWARD_BEST_Q15, ref_color = "purple"),
  data.table(target_label = "y_onset (secondary)",
             ref_label = "Cycle 53A v10", ref_value = CYCLE_53A_V10_ONSET, ref_color = "darkorange"),
  data.table(target_label = "y_onset (secondary)",
             ref_label = "Cycle 52 PatchTST", ref_value = CYCLE_52_PT_ONSET, ref_color = "darkgreen")
))

gA <- ggplot(plot_dt_a_full, aes(x = seed_label, y = oos_pr,
                                  fill = seed_label == "3-seed mean pred")) +
  geom_col() +
  geom_hline(data = ref_dt, aes(yintercept = ref_value, color = ref_label),
             linetype = "dashed", linewidth = 0.5) +
  facet_wrap(~ target_label, ncol = 2, scales = "free_y") +
  scale_fill_manual(values = c("FALSE" = "steelblue", "TRUE" = "firebrick"),
                    labels = c("per-seed", "3-seed mean prediction"),
                    name = NULL) +
  scale_color_manual(values = c("Cycle 53A v10" = "darkorange",
                                "Cycle 52 PatchTST" = "darkgreen",
                                "Cycle 43 fwd best" = "purple"),
                     name = NULL) +
  labs(title = "Cycle 53C Stacked PatchTST — Per-seed PR-AUC",
       subtitle = sprintf("Config: d_model=32 / n_layers=2 / dropout=0.20  |  q15 stability=%s, std=%.4f  |  Additivity vs v10: %s (Δ%+.4f)",
                          stab_q15, stability_table[target == "y_tail_q15", std_pr],
                          add_verdict_meanpred_q15, delta_mean_v10_q15),
       x = NULL, y = "OOS PR-AUC") +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        legend.position = "bottom",
        strip.text = element_text(face = "bold"))

# Panel B: Per-date prediction std histogram (y_tail_q15)
gB <- ggplot(mean_q15_dt[!is.na(p_per_seed_std)], aes(x = p_per_seed_std)) +
  geom_histogram(bins = 40, fill = "steelblue", alpha = 0.7) +
  geom_vline(xintercept = mean_rows[["y_tail_q15"]]$per_date_std_mean,
             linetype = "dashed", color = "red", linewidth = 0.6) +
  labs(title = "Per-date prediction std across 3 seeds (y_tail_q15)",
       subtitle = sprintf("mean=%.4f / median=%.4f / max=%.4f (lower = more seed-consistent)",
                          mean_rows[["y_tail_q15"]]$per_date_std_mean,
                          mean_rows[["y_tail_q15"]]$per_date_std_median,
                          mean_rows[["y_tail_q15"]]$per_date_std_max),
       x = "per-date std of seed predictions", y = "count") +
  theme_minimal(base_size = 11)

# Panel C: Cross-cycle progression
cycle_prog <- data.table(
  cycle = factor(c("C43 fwd best", "C52 PatchTST", "C53A v1", "C53A v10",
                   "C53C seed=42", "C53C across-seed mean", "C53C 3-seed mean pred"),
                 levels = c("C43 fwd best", "C52 PatchTST", "C53A v1", "C53A v10",
                            "C53C seed=42", "C53C across-seed mean", "C53C 3-seed mean pred")),
  pr = c(CYCLE_43_FORWARD_BEST_Q15, CYCLE_52_PT_Q15, CYCLE_53A_V1_Q15, CYCLE_53A_V10_Q15,
         stacked_s42_q15, mean_per_seed_q15, mean_pr_q15),
  group = c("baseline", "baseline", "baseline", "winner_53A",
            "current", "current", "current")
)

gC <- ggplot(cycle_prog, aes(x = cycle, y = pr, fill = group)) +
  geom_col() +
  geom_text(aes(label = sprintf("%.4f", pr)), vjust = -0.5, size = 3.2) +
  scale_fill_manual(values = c("baseline" = "lightgray",
                                "winner_53A" = "darkorange",
                                "current" = "firebrick"),
                    name = NULL) +
  labs(title = "Cross-cycle progression on y_tail_q15 (OOS PR-AUC)",
       subtitle = sprintf("Headline 3-seed mean = %.4f (Δ%+.4f vs Cycle 43 fwd best / Δ%+.4f vs v10)",
                          mean_pr_q15, mean_pr_q15 - CYCLE_43_FORWARD_BEST_Q15,
                          mean_pr_q15 - CYCLE_53A_V10_Q15),
       x = NULL, y = "OOS PR-AUC") +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1),
        legend.position = "bottom") +
  ylim(0, max(cycle_prog$pr) * 1.15)

g_combined <- gA / (gB | gC) +
  plot_annotation(
    title = sprintf("Cycle 53C Stacked PatchTST Multi-Seed Audit — %s / %s",
                    add_verdict_meanpred_q15, stab_q15),
    subtitle = sprintf("Stacked = d_model=32 + n_layers=2 + dropout=0.20 (3 Cycle 53A winners) | seeds [42, 123, 456] | v4a 70 features | OOS 2018-2026")
  )

chart_path <- file.path(CHART_DIR, "128_stacked_multiseed.png")
ggsave(chart_path, plot = g_combined, width = 14, height = 11, dpi = 120)
cat(sprintf("[Chart] %s\n", chart_path))

cat("\n========== Cycle 53C AGGREGATE DONE ==========\n")
cat(sprintf("Additivity verdict (3-seed mean prediction vs v10): %s (Δ=%+.4f)\n",
            add_verdict_meanpred_q15, delta_mean_v10_q15))
cat(sprintf("Stability verdict (y_tail_q15): %s (per-seed std=%.4f)\n",
            stab_q15, stability_table[target == "y_tail_q15", std_pr]))
cat(sprintf("Headline 3-seed mean prediction PR-AUC: %.4f (Δ%+.4f vs Cycle 43 forward best)\n",
            mean_pr_q15, mean_pr_q15 - CYCLE_43_FORWARD_BEST_Q15))
cat(sprintf("Next cycle suggestion:\n  %s\n", next_cycle_suggestion))
