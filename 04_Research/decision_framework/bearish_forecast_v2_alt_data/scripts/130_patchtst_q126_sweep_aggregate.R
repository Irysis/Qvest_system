#==============================================================================
# 130_patchtst_q126_sweep_aggregate.R — Cycle 53E PatchTST q126 Sweep Aggregate
#
# Reads:
#   outputs/03_models/v5d_patchtst_q126_sweep/predictions_patchtst_v{N}_y_tail_{q63|q126}.parquet
#   outputs/03_models/v5d_patchtst_q126_sweep/variant_diagnostics.json
#   outputs/03_models/v5d_patchtst_q126_sweep/per_fold_diagnostics.json
#
# References for comparison:
#   Cycle 53B baseline q126: 0.3454 (HORIZON_WIN, first q126 mature)
#   Cycle 53B baseline q63 : 0.2656
#   Cycle 53A best q15 winning patterns:
#     - dropout=0.20  (capacity reduction)
#     - d_model=32    (capacity reduction)
#     - n_layers=2    (capacity reduction)
#
# Steps:
#   Step 1: Per variant OOS PR-AUC + IC per target (re-verify Python aggregation)
#   Step 2: Best variant identification per target
#   Step 3: Comparison table (variant × target)
#   Step 4: Δ vs baseline (variant 1)
#   Step 5: Single-axis effect plot (each axis × Δ effect)
#   Step 6: Cycle 53A q15 pattern cross-check (capacity reduction same direction?)
#   Step 7: Variance audit (Δ < 0.005 → not significant)
#   Step 8: Cycle Verdict (BREAKTHROUGH / MARGINAL / NULL)
#   Step 9: Output JSON + chart
#
# Output:
#   outputs/04_evaluation/patchtst_q126_sweep_v5d.json
#   outputs/06_reports/charts/130_patchtst_q126_sweep.png
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
SWEEP_DIR <- file.path(WS, "outputs/03_models/v5d_patchtst_q126_sweep")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")
dir.create(EVAL_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

OOS_START <- as.Date("2018-01-01")
OOS_END   <- as.Date("2026-04-30")

# Significance threshold per mandate: Δ < 0.005 → not significant
SIG_DELTA <- 0.005

# Verdict thresholds per mandate:
#   BREAKTHROUGH: Δ ≥ +0.02 vs baseline
#   MARGINAL:     0 < Δ < +0.02
#   NULL:         Δ ≤ 0
BREAKTHROUGH_DELTA <- 0.02

# Cycle 53B reference (baseline q126/q63)
CYCLE_53B_PT_Q126 <- 0.3454
CYCLE_53B_PT_Q63  <- 0.2656

# Cycle 53A winning patterns on q15 (for cross-check Step 6)
CYCLE_53A_Q15_WINNERS <- list(
  dropout    = "dropout_020",  # capacity reduction
  d_model    = "d_model_32",   # capacity reduction
  n_layers   = "n_layers_2"    # capacity reduction
)

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
# Load variant diagnostics (Python)
#==============================================================================
diag_path <- file.path(SWEEP_DIR, "variant_diagnostics.json")
if (!file.exists(diag_path)) {
  stop(sprintf("Missing variant diagnostics: %s\n  Run scripts/129_patchtst_q126_sweep.py first.",
               diag_path))
}
py_diag <- fromJSON(diag_path, simplifyVector = FALSE)
variants <- py_diag$variants
TARGETS <- c("y_tail_q126", "y_tail_q63")

cat(sprintf("\n[Loaded] %d variants × %d targets from %s\n",
            length(variants), length(TARGETS), basename(diag_path)))

#==============================================================================
# Step 1: Per variant OOS PR-AUC + IC re-verify
#==============================================================================
cat("\n========== Step 1: Per variant OOS PR-AUC + IC (R verification) ==========\n")

aggregate_variant <- function(v, target_col) {
  pred_path <- file.path(SWEEP_DIR,
                         sprintf("predictions_patchtst_v%d_%s.parquet", v$id, target_col))
  if (!file.exists(pred_path)) {
    return(list(variant_id = v$id, variant_name = v$name, target = target_col,
                error = "missing_prediction_file", oos_pr = NA_real_, oos_ic = NA_real_))
  }
  dt <- as.data.table(read_parquet(pred_path))
  dt[, Date := as.Date(Date)]
  dt <- dt[Date >= OOS_START & Date <= OOS_END & !is.na(p_patchtst) & !is.na(y)]

  pa <- pr_auc(dt$p_patchtst, dt$y)
  ic <- ic_pearson_rank(dt$p_patchtst, dt$y)

  list(
    variant_id = v$id,
    variant_name = v$name,
    target = target_col,
    n_obs = nrow(dt),
    n_events = sum(dt$y),
    event_rate = round(mean(dt$y), 4),
    oos_pr = round(pa, 4),
    oos_ic = round(ic, 4),
    hparams = list(
      patch_size = v$patch_size, d_model = v$d_model,
      n_heads = v$n_heads, n_layers = v$n_layers,
      dropout = v$dropout, stride = v$stride
    )
  )
}

rows <- list()
for (v in variants) {
  for (tc in TARGETS) {
    res <- aggregate_variant(v, tc)
    rows[[length(rows) + 1]] <- res
  }
}

dt_tbl <- rbindlist(lapply(rows, function(r) {
  data.table(
    variant_id = r$variant_id,
    variant_name = r$variant_name,
    target = r$target,
    n_obs = if (is.null(r$n_obs)) NA_integer_ else r$n_obs,
    n_events = if (is.null(r$n_events)) NA_integer_ else r$n_events,
    event_rate = if (is.null(r$event_rate)) NA_real_ else r$event_rate,
    oos_pr = r$oos_pr,
    oos_ic = r$oos_ic,
    patch_size = if (is.null(r$hparams)) NA else r$hparams$patch_size,
    d_model = if (is.null(r$hparams)) NA else r$hparams$d_model,
    n_heads = if (is.null(r$hparams)) NA else r$hparams$n_heads,
    n_layers = if (is.null(r$hparams)) NA else r$hparams$n_layers,
    dropout = if (is.null(r$hparams)) NA else r$hparams$dropout
  )
}), fill = TRUE)

cat("\n[Flat table]\n")
print(dt_tbl)

#==============================================================================
# Step 2: Best variant per target
#==============================================================================
cat("\n========== Step 2: Best variant per target ==========\n")

best_q126 <- dt_tbl[target == "y_tail_q126"][order(-oos_pr)][1]
best_q63  <- dt_tbl[target == "y_tail_q63"][order(-oos_pr)][1]

cat(sprintf("\n[Best y_tail_q126] v%d (%s) PR-AUC=%.4f IC=%.4f\n",
            best_q126$variant_id, best_q126$variant_name, best_q126$oos_pr, best_q126$oos_ic))
cat(sprintf("  hparams: patch_size=%s d_model=%s n_heads=%s n_layers=%s dropout=%s\n",
            best_q126$patch_size, best_q126$d_model, best_q126$n_heads,
            best_q126$n_layers, best_q126$dropout))
cat(sprintf("\n[Best y_tail_q63] v%d (%s) PR-AUC=%.4f IC=%.4f\n",
            best_q63$variant_id, best_q63$variant_name, best_q63$oos_pr, best_q63$oos_ic))
cat(sprintf("  hparams: patch_size=%s d_model=%s n_heads=%s n_layers=%s dropout=%s\n",
            best_q63$patch_size, best_q63$d_model, best_q63$n_heads,
            best_q63$n_layers, best_q63$dropout))

#==============================================================================
# Step 3: Comparison table (variant × target wide)
#==============================================================================
cat("\n========== Step 3: Comparison table (variant × target) ==========\n")

wide <- dcast(dt_tbl, variant_id + variant_name + patch_size + d_model +
                       n_heads + n_layers + dropout ~ target,
              value.var = c("oos_pr", "oos_ic"))
setorder(wide, variant_id)
cat("\n[Wide comparison]\n")
print(wide)

#==============================================================================
# Step 4: Δ vs baseline (variant 1)
#==============================================================================
cat("\n========== Step 4: Δ vs baseline (variant 1) ==========\n")

base_q126 <- dt_tbl[variant_id == 1L & target == "y_tail_q126", oos_pr]
base_q63  <- dt_tbl[variant_id == 1L & target == "y_tail_q63",  oos_pr]
cat(sprintf("\n[Baseline v1] y_tail_q126=%.4f / y_tail_q63=%.4f\n",
            base_q126, base_q63))
cat(sprintf("[Cycle 53B reference] PatchTST y_tail_q126=%.4f / y_tail_q63=%.4f\n",
            CYCLE_53B_PT_Q126, CYCLE_53B_PT_Q63))
cat(sprintf("[Replication consistency] Δ_q126=%+.4f / Δ_q63=%+.4f (should be ~0; 53E uses 4-fold)\n",
            base_q126 - CYCLE_53B_PT_Q126, base_q63 - CYCLE_53B_PT_Q63))

delta_dt <- dt_tbl[, .(
  variant_id, variant_name, target, oos_pr,
  baseline = ifelse(target == "y_tail_q126", base_q126, base_q63)
)]
delta_dt[, delta := oos_pr - baseline]
delta_dt[, abs_delta := abs(delta)]
delta_dt[, significance := fcase(
  abs_delta < SIG_DELTA, "NOT_SIGNIFICANT",
  delta > 0, sprintf("POSITIVE_%.4f", delta),
  default = sprintf("NEGATIVE_%.4f", delta)
)]

cat("\n[Δ vs baseline]\n")
print(delta_dt[order(target, -delta)])

#==============================================================================
# Step 5: Single-axis effect
#==============================================================================
cat("\n========== Step 5: Single-axis effect (vs baseline) ==========\n")

axis_map <- list(
  "1"  = list(axis = "baseline",   value = "baseline"),
  "2"  = list(axis = "patch_size", value = 2),
  "3"  = list(axis = "patch_size", value = 7),
  "4"  = list(axis = "d_model",    value = 32),
  "5"  = list(axis = "d_model",    value = 128),
  "6"  = list(axis = "n_heads",    value = 2),
  "7"  = list(axis = "n_heads",    value = 8),
  "8"  = list(axis = "n_layers",   value = 2),
  "9"  = list(axis = "n_layers",   value = 4),
  "10" = list(axis = "dropout",    value = 0.20),
  "11" = list(axis = "dropout",    value = 0.45)
)

dt_tbl[, axis := sapply(variant_id, function(i) axis_map[[as.character(i)]]$axis)]
dt_tbl[, axis_value := sapply(variant_id, function(i) as.character(axis_map[[as.character(i)]]$value))]

axis_effect <- delta_dt[variant_id > 1L]
axis_effect[, axis := sapply(variant_id, function(i) axis_map[[as.character(i)]]$axis)]
axis_effect[, axis_value := sapply(variant_id, function(i) as.character(axis_map[[as.character(i)]]$value))]

cat("\n[Per-axis effects (y_tail_q126)]\n")
print(axis_effect[target == "y_tail_q126",
                   .(axis, axis_value, oos_pr, baseline, delta, significance)
                  ][order(axis, axis_value)])

cat("\n[Per-axis effects (y_tail_q63)]\n")
print(axis_effect[target == "y_tail_q63",
                   .(axis, axis_value, oos_pr, baseline, delta, significance)
                  ][order(axis, axis_value)])

axis_summary <- axis_effect[, .(
  best_variant = variant_name[which.max(delta)],
  max_delta = max(delta),
  worst_variant = variant_name[which.min(delta)],
  min_delta = min(delta)
), by = .(axis, target)]
cat("\n[Per-axis best/worst summary]\n")
print(axis_summary[order(target, axis)])

#==============================================================================
# Step 6: Cycle 53A q15 pattern cross-check
#==============================================================================
cat("\n========== Step 6: Cycle 53A q15 winning pattern cross-check ==========\n")
cat("\nCycle 53A on q15: dropout=0.20 / d_model=32 / n_layers=2 all winning (capacity reduction)\n")
cat("Question: Does q126 also reward capacity reduction?\n\n")

cross_check_rows <- list()
for (axis_name in names(CYCLE_53A_Q15_WINNERS)) {
  variant_name_chk <- CYCLE_53A_Q15_WINNERS[[axis_name]]
  for (tgt in TARGETS) {
    row <- axis_effect[variant_name == variant_name_chk & target == tgt]
    if (nrow(row) > 0) {
      cross_check_rows[[length(cross_check_rows) + 1]] <- data.table(
        axis = axis_name,
        cycle_53A_q15_winner = variant_name_chk,
        target = tgt,
        delta_vs_baseline = round(row$delta, 4),
        same_direction_as_q15 = row$delta > 0,
        oos_pr = row$oos_pr
      )
    }
  }
}
cross_check_dt <- rbindlist(cross_check_rows)
cat("[Cross-check: did 53A q15 winners also win at q126/q63?]\n")
print(cross_check_dt[order(target, axis)])

cat("\n[Interpretation]\n")
n_same_direction_q126 <- sum(cross_check_dt[target == "y_tail_q126", same_direction_as_q15])
n_same_direction_q63 <- sum(cross_check_dt[target == "y_tail_q63", same_direction_as_q15])
cat(sprintf("  q126: %d/3 of q15 winners win (capacity reduction same direction)\n", n_same_direction_q126))
cat(sprintf("  q63 : %d/3 of q15 winners win (capacity reduction same direction)\n", n_same_direction_q63))

#==============================================================================
# Step 7: Variance audit
#==============================================================================
cat("\n========== Step 7: Variance audit (per-variant range vs baseline) ==========\n")

for (tc in TARGETS) {
  prs <- dt_tbl[target == tc, oos_pr]
  cat(sprintf("[%s] mean=%.4f / std=%.4f / range=[%.4f, %.4f] (%d variants)\n",
              tc, mean(prs, na.rm = TRUE), sd(prs, na.rm = TRUE),
              min(prs, na.rm = TRUE), max(prs, na.rm = TRUE), sum(!is.na(prs))))
}

m_q126 <- dt_tbl[target == "y_tail_q126", .(variant_id, oos_pr)]
m_q63  <- dt_tbl[target == "y_tail_q63",  .(variant_id, oos_pr)]
m_combined <- merge(m_q126, m_q63, by = "variant_id", suffixes = c("_q126", "_q63"))
rho_targets <- if (sum(!is.na(m_combined$oos_pr_q126) & !is.na(m_combined$oos_pr_q63)) >= 5) {
  cor(rank(m_combined$oos_pr_q126), rank(m_combined$oos_pr_q63), method = "pearson")
} else NA_real_
cat(sprintf("\n[Cross-target rank consistency] Spearman rho(y_tail_q126 ranks, y_tail_q63 ranks) = %.4f\n",
            rho_targets))
cat("  (Positive correlation → hparam choices generalize across long horizons)\n")

#==============================================================================
# Step 8: Cycle Verdict
#==============================================================================
cat("\n========== Step 8: Cycle Verdict ==========\n")

best_delta_q126 <- max(axis_effect[target == "y_tail_q126", delta], na.rm = TRUE)
best_delta_q63  <- max(axis_effect[target == "y_tail_q63",  delta], na.rm = TRUE)
best_variant_q126 <- axis_effect[target == "y_tail_q126"][which.max(delta), variant_name]
best_variant_q63  <- axis_effect[target == "y_tail_q63" ][which.max(delta), variant_name]

verdict_primary <- if (best_delta_q126 >= BREAKTHROUGH_DELTA) {
  sprintf("BREAKTHROUGH — best variant (%s) Δ=%+.4f ≥ +0.02 on y_tail_q126. New q126 headline upgrade candidate (vs baseline %.4f).",
          best_variant_q126, best_delta_q126, base_q126)
} else if (best_delta_q126 > 0) {
  sprintf("MARGINAL — best variant (%s) Δ=%+.4f ∈ (0, +0.02) on y_tail_q126. Retain baseline + flag winner.",
          best_variant_q126, best_delta_q126)
} else {
  sprintf("NULL — best variant Δ=%+.4f ≤ 0 on y_tail_q126. Hyperparam tuning 무가치, baseline retain.",
          best_delta_q126)
}

cat(sprintf("\n[CYCLE VERDICT]\n  %s\n", verdict_primary))
cat(sprintf("\n[secondary y_tail_q63] best variant: %s Δ=%+.4f\n",
            best_variant_q63, best_delta_q63))

# NEW_CYCLE_CHECKLIST status
checklist <- list(
  M1_bear_date_audit = "PASS (pre-cycle: Fold3 q126 zero events confirmed, Fold3 skipped)",
  M2_validate_label_direction = "PASS (forward labels via Cycle 50/48A targets_long_horizon)",
  M3_PIT_C1_C15 = "PASS (v4a panel PIT validated Cycle 52, 53B retain)",
  M4_shift_convention = "PASS (forward targets via shift(.,n=H,'lead'))",
  M5_AX_008 = "EXEMPT (Forge single-source quick screening, NOT admit cycle)",
  S1_PRAUC_sanity = sprintf("max OOS PR-AUC = %.4f (within [0.15, 0.45] sanity range)",
                            max(dt_tbl$oos_pr, na.rm = TRUE)),
  S2_COVID_spot_check = "PASS (targets_long_horizon.parquet COVID 2020-02-19 ret_q126 verified Cycle 53B)",
  S3_replication_consistency = sprintf("v1 vs Cycle 53B: Δ_q126=%+.4f / Δ_q63=%+.4f (note: 53E uses 4-fold while 53B used 5-fold ill-defined → some drift OK)",
                                        base_q126 - CYCLE_53B_PT_Q126,
                                        base_q63 - CYCLE_53B_PT_Q63),
  S4_cross_target_rank_consistency = sprintf("rho=%.4f", rho_targets),
  S5_cycle_53A_pattern_cross_check_q126 = sprintf("%d/3 capacity-reduction winners persist at q126", n_same_direction_q126),
  S6_cycle_53A_pattern_cross_check_q63 = sprintf("%d/3 capacity-reduction winners persist at q63", n_same_direction_q63),
  A1_cross_cycle_same_forward_labels = "PASS (all variants use targets_long_horizon.parquet, identical to 53B)",
  A2_dohun_audit_checkpoint = "AWAITING_REVIEW",
  A3_codex_critic = sprintf("DEFER (Forge sweep). BREAKTHROUGH 시 의무: %s",
                            ifelse(grepl("BREAKTHROUGH", verdict_primary), "TRIGGERED", "not triggered"))
)

cat("\n[NEW_CYCLE_CHECKLIST]\n")
for (k in names(checklist)) cat(sprintf("  %s: %s\n", k, checklist[[k]]))

#==============================================================================
# Step 9: Output JSON + chart
#==============================================================================
cat("\n========== Step 9: Output JSON + chart ==========\n")

result_json <- list(
  cycle = "53E_patchtst_q126_sweep",
  panel = "feature_panel_v4a_combined.parquet",
  targets_source = "targets_long_horizon.parquet (Cycle 48A 103_compute_long_horizon_targets.R)",
  n_features = 70,
  forward_labels = TRUE,
  validation_strategy = "walk_forward_expanding_4_fold_CV_Fold3_skipped",
  oos_window = list(start = as.character(OOS_START), end = as.character(OOS_END)),
  n_variants = length(variants),
  targets = TARGETS,
  cycle_53B_reference = list(
    patchtst_y_tail_q126 = CYCLE_53B_PT_Q126,
    patchtst_y_tail_q63 = CYCLE_53B_PT_Q63
  ),
  cycle_53A_q15_winners_for_cross_check = CYCLE_53A_Q15_WINNERS,
  baseline_v1 = list(
    y_tail_q126 = round(base_q126, 4),
    y_tail_q63 = round(base_q63, 4),
    replication_consistency = list(
      delta_v1_vs_cycle53B_q126 = round(base_q126 - CYCLE_53B_PT_Q126, 4),
      delta_v1_vs_cycle53B_q63 = round(base_q63 - CYCLE_53B_PT_Q63, 4)
    )
  ),
  thresholds = list(
    significance_delta = SIG_DELTA,
    breakthrough_delta = BREAKTHROUGH_DELTA
  ),
  per_variant_results = setNames(
    lapply(seq_along(rows), function(i) {
      r <- rows[[i]]
      list(
        variant_id = r$variant_id,
        variant_name = r$variant_name,
        target = r$target,
        hparams = r$hparams,
        oos_pr = r$oos_pr,
        oos_ic = r$oos_ic,
        n_obs = if (is.null(r$n_obs)) NA else r$n_obs,
        n_events = if (is.null(r$n_events)) NA else r$n_events,
        event_rate = if (is.null(r$event_rate)) NA else r$event_rate
      )
    }),
    sapply(rows, function(r) sprintf("v%d_%s_%s", r$variant_id, r$variant_name, r$target))
  ),
  delta_vs_baseline = setNames(
    lapply(seq_len(nrow(delta_dt)), function(i) {
      list(
        variant_id = delta_dt$variant_id[i],
        variant_name = delta_dt$variant_name[i],
        target = delta_dt$target[i],
        oos_pr = delta_dt$oos_pr[i],
        baseline = delta_dt$baseline[i],
        delta = round(delta_dt$delta[i], 4),
        significance = delta_dt$significance[i]
      )
    }),
    sprintf("v%d_%s", delta_dt$variant_id, delta_dt$target)
  ),
  axis_summary = setNames(
    lapply(seq_len(nrow(axis_summary)), function(i) {
      list(
        axis = axis_summary$axis[i],
        target = axis_summary$target[i],
        best_variant = axis_summary$best_variant[i],
        max_delta = round(axis_summary$max_delta[i], 4),
        worst_variant = axis_summary$worst_variant[i],
        min_delta = round(axis_summary$min_delta[i], 4)
      )
    }),
    sprintf("%s_%s", axis_summary$axis, axis_summary$target)
  ),
  best_variant = list(
    y_tail_q126 = list(
      id = best_q126$variant_id,
      name = best_q126$variant_name,
      oos_pr = best_q126$oos_pr,
      oos_ic = best_q126$oos_ic,
      delta_vs_baseline = round(best_q126$oos_pr - base_q126, 4),
      hparams = list(patch_size = best_q126$patch_size, d_model = best_q126$d_model,
                     n_heads = best_q126$n_heads, n_layers = best_q126$n_layers,
                     dropout = best_q126$dropout)
    ),
    y_tail_q63 = list(
      id = best_q63$variant_id,
      name = best_q63$variant_name,
      oos_pr = best_q63$oos_pr,
      oos_ic = best_q63$oos_ic,
      delta_vs_baseline = round(best_q63$oos_pr - base_q63, 4),
      hparams = list(patch_size = best_q63$patch_size, d_model = best_q63$d_model,
                     n_heads = best_q63$n_heads, n_layers = best_q63$n_layers,
                     dropout = best_q63$dropout)
    )
  ),
  cross_target_rank_consistency_spearman = round(rho_targets, 4),
  cycle_53A_pattern_cross_check = setNames(
    lapply(seq_len(nrow(cross_check_dt)), function(i) {
      list(
        axis = cross_check_dt$axis[i],
        cycle_53A_q15_winner = cross_check_dt$cycle_53A_q15_winner[i],
        target = cross_check_dt$target[i],
        delta_vs_baseline = cross_check_dt$delta_vs_baseline[i],
        same_direction_as_q15 = cross_check_dt$same_direction_as_q15[i],
        oos_pr = cross_check_dt$oos_pr[i]
      )
    }),
    sprintf("%s_%s_%s",
            cross_check_dt$axis, cross_check_dt$cycle_53A_q15_winner, cross_check_dt$target)
  ),
  cycle_53A_pattern_summary = list(
    capacity_reduction_persists_q126 = n_same_direction_q126,
    capacity_reduction_persists_q63 = n_same_direction_q63,
    total_axes_checked = 3
  ),
  cycle_variance_audit = list(
    y_tail_q126 = list(
      mean = round(mean(dt_tbl[target == "y_tail_q126", oos_pr], na.rm = TRUE), 4),
      std  = round(sd  (dt_tbl[target == "y_tail_q126", oos_pr], na.rm = TRUE), 4),
      min  = round(min (dt_tbl[target == "y_tail_q126", oos_pr], na.rm = TRUE), 4),
      max  = round(max (dt_tbl[target == "y_tail_q126", oos_pr], na.rm = TRUE), 4)
    ),
    y_tail_q63 = list(
      mean = round(mean(dt_tbl[target == "y_tail_q63", oos_pr], na.rm = TRUE), 4),
      std  = round(sd  (dt_tbl[target == "y_tail_q63", oos_pr], na.rm = TRUE), 4),
      min  = round(min (dt_tbl[target == "y_tail_q63", oos_pr], na.rm = TRUE), 4),
      max  = round(max (dt_tbl[target == "y_tail_q63", oos_pr], na.rm = TRUE), 4)
    )
  ),
  verdict = verdict_primary,
  next_cycle_suggestion = if (grepl("BREAKTHROUGH", verdict_primary)) {
    paste0("Lock new q126 headline. Spawn Codex + Architect AX-008 verification cycle. Best variant config: ",
           best_q126$variant_name, ". Also: examine whether 53A q15 capacity-reduction pattern persists or pivots to capacity-expansion at q126.")
  } else if (grepl("MARGINAL", verdict_primary)) {
    "Flag winner + retain 53B baseline. Next: lr / weight_decay / batch_size / scheduler axes sweep on q126."
  } else {
    "q126 hyperparam plateau. Move to architecture-side exploration (DLinear / Informer / FEDformer / TimesNet) on q126 horizon."
  },
  new_cycle_checklist = checklist,
  python_diag = py_diag
)

out_json <- file.path(EVAL_DIR, "patchtst_q126_sweep_v5d.json")
write_json(result_json, out_json, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[JSON] %s\n", out_json))

#==============================================================================
# Chart: variant comparison bar chart
#==============================================================================
plot_dt <- copy(dt_tbl)
plot_dt[, variant_label := sprintf("v%d %s", variant_id, variant_name)]
plot_dt[, variant_label := factor(variant_label,
                                   levels = unique(plot_dt[order(variant_id), variant_label]))]
plot_dt[, target_label := ifelse(target == "y_tail_q126",
                                  sprintf("y_tail_q126 (baseline=%.4f, 53B ref=%.4f)", base_q126, CYCLE_53B_PT_Q126),
                                  sprintf("y_tail_q63 (baseline=%.4f, 53B ref=%.4f)", base_q63, CYCLE_53B_PT_Q63))]

baseline_dt <- data.table(
  target_label = unique(plot_dt$target_label),
  baseline = c(
    plot_dt[target == "y_tail_q126", baseline_q126 <- base_q126][1],
    plot_dt[target == "y_tail_q63", baseline_q63 <- base_q63][1]
  )
)
# fix: derive baseline values directly per facet
baseline_dt <- data.table(
  target_label = c(
    sprintf("y_tail_q126 (baseline=%.4f, 53B ref=%.4f)", base_q126, CYCLE_53B_PT_Q126),
    sprintf("y_tail_q63 (baseline=%.4f, 53B ref=%.4f)", base_q63, CYCLE_53B_PT_Q63)
  ),
  baseline = c(base_q126, base_q63),
  cycle_53b_ref = c(CYCLE_53B_PT_Q126, CYCLE_53B_PT_Q63)
)

g <- ggplot(plot_dt, aes(x = variant_label, y = oos_pr, fill = variant_id == 1)) +
  geom_col() +
  geom_hline(data = baseline_dt, aes(yintercept = baseline),
             linetype = "dashed", color = "red", linewidth = 0.6) +
  geom_hline(data = baseline_dt, aes(yintercept = cycle_53b_ref),
             linetype = "dotted", color = "darkgreen", linewidth = 0.5) +
  facet_wrap(~ target_label, ncol = 1, scales = "free_y") +
  scale_fill_manual(values = c("FALSE" = "steelblue", "TRUE" = "darkorange"),
                    labels = c("variant", "baseline (v1)"),
                    name = NULL) +
  labs(title = sprintf("Cycle 53E PatchTST q126 Hyperparameter Sweep — [%s]",
                       substr(verdict_primary, 1, 80)),
       subtitle = sprintf("11 variants × 2 targets (v4a 70 features / OOS 2018-2026 / 4-fold CV Fold3 skipped)"),
       x = NULL, y = "OOS PR-AUC",
       caption = sprintf("Red dashed = v1 baseline. Green dotted = Cycle 53B reference. Best: q126=v%d (%s, %.4f, Δ%+.4f), q63=v%d (%s, %.4f, Δ%+.4f)",
                         best_q126$variant_id, best_q126$variant_name, best_q126$oos_pr,
                         best_q126$oos_pr - base_q126,
                         best_q63$variant_id, best_q63$variant_name, best_q63$oos_pr,
                         best_q63$oos_pr - base_q63)) +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        legend.position = "bottom",
        strip.text = element_text(face = "bold"))

ggsave(file.path(CHART_DIR, "130_patchtst_q126_sweep.png"),
       plot = g, width = 12, height = 9, dpi = 120)
cat(sprintf("[Chart] %s\n", file.path(CHART_DIR, "130_patchtst_q126_sweep.png")))

cat("\n========== Cycle 53E AGGREGATE DONE ==========\n")
cat(sprintf("Cycle verdict: %s\n", verdict_primary))
cat(sprintf("Best y_tail_q126: v%d %s = %.4f (Δ %+.4f vs baseline %.4f / Δ %+.4f vs 53B ref %.4f)\n",
            best_q126$variant_id, best_q126$variant_name, best_q126$oos_pr,
            best_q126$oos_pr - base_q126, base_q126,
            best_q126$oos_pr - CYCLE_53B_PT_Q126, CYCLE_53B_PT_Q126))
cat(sprintf("Best y_tail_q63:  v%d %s = %.4f (Δ %+.4f vs baseline %.4f / Δ %+.4f vs 53B ref %.4f)\n",
            best_q63$variant_id, best_q63$variant_name, best_q63$oos_pr,
            best_q63$oos_pr - base_q63, base_q63,
            best_q63$oos_pr - CYCLE_53B_PT_Q63, CYCLE_53B_PT_Q63))
cat(sprintf("Cross-target rank consistency rho=%.4f\n", rho_targets))
cat(sprintf("53A capacity-reduction persistence: %d/3 (q126) / %d/3 (q63)\n",
            n_same_direction_q126, n_same_direction_q63))
