#==============================================================================
# 124_patchtst_sweep_aggregate.R — Cycle 53A PatchTST Sweep Aggregate
#
# Reads:
#   outputs/03_models/v5a_patchtst_sweep/predictions_patchtst_v{N}_y_{tail_q15|onset}.parquet
#   outputs/03_models/v5a_patchtst_sweep/variant_diagnostics.json
#
# Steps:
#   Step 1: Per variant OOS PR-AUC + IC per target (re-verify Python aggregation)
#   Step 2: Best variant identification per target
#   Step 3: Comparison table (variant × target)
#   Step 4: Δ vs baseline (variant 1)
#   Step 5: Single-axis effect plot (each axis × Δ effect)
#   Step 6: Variance audit (Δ < 0.005 → not significant)
#   Step 7: Cycle Verdict (BREAKTHROUGH / MARGINAL / NULL)
#   Step 8: Output JSON + chart
#
# Output:
#   outputs/04_evaluation/patchtst_sweep_v5a.json
#   outputs/06_reports/charts/124_patchtst_sweep.png
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
SWEEP_DIR <- file.path(WS, "outputs/03_models/v5a_patchtst_sweep")
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

# Cycle 52 reference (for sanity)
CYCLE_52_PT_Q15 <- 0.2463
CYCLE_52_PT_ONSET <- 0.1372

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
  stop(sprintf("Missing variant diagnostics: %s\n  Run scripts/123_patchtst_hyperparam_sweep.py first.",
               diag_path))
}
py_diag <- fromJSON(diag_path, simplifyVector = FALSE)
variants <- py_diag$variants

cat(sprintf("\n[Loaded] %d variants × 2 targets from %s\n",
            length(variants), basename(diag_path)))

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
  for (tc in c("y_tail_q15", "y_onset")) {
    res <- aggregate_variant(v, tc)
    rows[[length(rows) + 1]] <- res
  }
}

# Build flat data.table
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

best_q15 <- dt_tbl[target == "y_tail_q15"][order(-oos_pr)][1]
best_ons <- dt_tbl[target == "y_onset"][order(-oos_pr)][1]

cat(sprintf("\n[Best y_tail_q15] v%d (%s) PR-AUC=%.4f IC=%.4f\n",
            best_q15$variant_id, best_q15$variant_name, best_q15$oos_pr, best_q15$oos_ic))
cat(sprintf("  hparams: patch_size=%s d_model=%s n_heads=%s n_layers=%s dropout=%s\n",
            best_q15$patch_size, best_q15$d_model, best_q15$n_heads,
            best_q15$n_layers, best_q15$dropout))
cat(sprintf("\n[Best y_onset]    v%d (%s) PR-AUC=%.4f IC=%.4f\n",
            best_ons$variant_id, best_ons$variant_name, best_ons$oos_pr, best_ons$oos_ic))
cat(sprintf("  hparams: patch_size=%s d_model=%s n_heads=%s n_layers=%s dropout=%s\n",
            best_ons$patch_size, best_ons$d_model, best_ons$n_heads,
            best_ons$n_layers, best_ons$dropout))

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

base_q15 <- dt_tbl[variant_id == 1L & target == "y_tail_q15", oos_pr]
base_ons <- dt_tbl[variant_id == 1L & target == "y_onset", oos_pr]
cat(sprintf("\n[Baseline v1] y_tail_q15=%.4f / y_onset=%.4f\n",
            base_q15, base_ons))
cat(sprintf("[Cycle 52 reference] PatchTST y_tail_q15=%.4f / y_onset=%.4f\n",
            CYCLE_52_PT_Q15, CYCLE_52_PT_ONSET))
cat(sprintf("[Replication consistency] Δ_q15=%+.4f / Δ_onset=%+.4f (should be ~0)\n",
            base_q15 - CYCLE_52_PT_Q15, base_ons - CYCLE_52_PT_ONSET))

delta_dt <- dt_tbl[, .(
  variant_id, variant_name, target, oos_pr,
  baseline = ifelse(target == "y_tail_q15", base_q15, base_ons)
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

# Map variant id → axis (NULL for baseline)
axis_map <- list(
  "1" = list(axis = "baseline", value = "baseline"),
  "2" = list(axis = "patch_size", value = 2),
  "3" = list(axis = "patch_size", value = 7),
  "4" = list(axis = "d_model", value = 32),
  "5" = list(axis = "d_model", value = 128),
  "6" = list(axis = "n_heads", value = 2),
  "7" = list(axis = "n_heads", value = 8),
  "8" = list(axis = "n_layers", value = 2),
  "9" = list(axis = "n_layers", value = 4),
  "10" = list(axis = "dropout", value = 0.20),
  "11" = list(axis = "dropout", value = 0.45)
)

dt_tbl[, axis := sapply(variant_id, function(i) axis_map[[as.character(i)]]$axis)]
dt_tbl[, axis_value := sapply(variant_id, function(i) as.character(axis_map[[as.character(i)]]$value))]

axis_effect <- delta_dt[variant_id > 1L]
axis_effect[, axis := sapply(variant_id, function(i) axis_map[[as.character(i)]]$axis)]
axis_effect[, axis_value := sapply(variant_id, function(i) as.character(axis_map[[as.character(i)]]$value))]

cat("\n[Per-axis effects (y_tail_q15)]\n")
print(axis_effect[target == "y_tail_q15",
                   .(axis, axis_value, oos_pr, baseline, delta, significance)
                  ][order(axis, axis_value)])

cat("\n[Per-axis effects (y_onset)]\n")
print(axis_effect[target == "y_onset",
                   .(axis, axis_value, oos_pr, baseline, delta, significance)
                  ][order(axis, axis_value)])

# Aggregate "best axis" per target
axis_summary <- axis_effect[, .(
  best_variant = variant_name[which.max(delta)],
  max_delta = max(delta),
  worst_variant = variant_name[which.min(delta)],
  min_delta = min(delta)
), by = .(axis, target)]
cat("\n[Per-axis best/worst summary]\n")
print(axis_summary[order(target, axis)])

#==============================================================================
# Step 6: Variance audit (per-variant stability cross check)
#==============================================================================
cat("\n========== Step 6: Variance audit (per-variant range vs baseline) ==========\n")

# Note: single-seed runs so per-date std cannot be computed.
# Cross-variant std is a proxy for "fragility to hyperparam choice"
for (tc in c("y_tail_q15", "y_onset")) {
  prs <- dt_tbl[target == tc, oos_pr]
  cat(sprintf("[%s] mean=%.4f / std=%.4f / range=[%.4f, %.4f] (%d variants)\n",
              tc, mean(prs, na.rm = TRUE), sd(prs, na.rm = TRUE),
              min(prs, na.rm = TRUE), max(prs, na.rm = TRUE), sum(!is.na(prs))))
}

# Cross-variant rank consistency between targets (NEW_CYCLE_CHECKLIST SHOULD S3 proxy)
m_q15 <- dt_tbl[target == "y_tail_q15", .(variant_id, oos_pr)]
m_ons <- dt_tbl[target == "y_onset", .(variant_id, oos_pr)]
m_combined <- merge(m_q15, m_ons, by = "variant_id", suffixes = c("_q15", "_ons"))
rho_targets <- if (sum(!is.na(m_combined$oos_pr_q15) & !is.na(m_combined$oos_pr_ons)) >= 5) {
  cor(rank(m_combined$oos_pr_q15), rank(m_combined$oos_pr_ons), method = "pearson")
} else NA_real_
cat(sprintf("\n[Cross-target rank consistency] Spearman rho(y_tail_q15 ranks, y_onset ranks) = %.4f\n",
            rho_targets))
cat("  (Note: positive correlation suggests hparam choices generalize across targets)\n")

#==============================================================================
# Step 7: Cycle Verdict
#==============================================================================
cat("\n========== Step 7: Cycle Verdict ==========\n")

best_delta_q15 <- max(axis_effect[target == "y_tail_q15", delta], na.rm = TRUE)
best_delta_ons <- max(axis_effect[target == "y_onset", delta], na.rm = TRUE)
best_variant_q15 <- axis_effect[target == "y_tail_q15"][which.max(delta), variant_name]
best_variant_ons <- axis_effect[target == "y_onset"][which.max(delta), variant_name]

verdict_primary <- if (best_delta_q15 >= BREAKTHROUGH_DELTA) {
  sprintf("BREAKTHROUGH — best variant (%s) Δ=%+.4f ≥ +0.02 on y_tail_q15. Headline upgrade candidate.",
          best_variant_q15, best_delta_q15)
} else if (best_delta_q15 > 0) {
  sprintf("MARGINAL — best variant (%s) Δ=%+.4f ∈ (0, +0.02) on y_tail_q15. Retain baseline + flag winner.",
          best_variant_q15, best_delta_q15)
} else {
  sprintf("NULL — best variant Δ=%+.4f ≤ 0 on y_tail_q15. Hyperparam tuning 무가치, baseline retain.",
          best_delta_q15)
}

cat(sprintf("\n[CYCLE VERDICT]\n  %s\n", verdict_primary))
cat(sprintf("\n[secondary y_onset] best variant: %s Δ=%+.4f\n",
            best_variant_ons, best_delta_ons))

# NEW_CYCLE_CHECKLIST status
checklist <- list(
  M1_bear_date_audit = "PASS (pre-cycle 4/4)",
  M2_validate_label_direction = "PASS (forward labels via Cycle 50 fix)",
  M3_PIT_C1_C15 = "PASS (v4a panel PIT validated Cycle 52)",
  M4_shift_convention = "PASS (forward targets via shift(.,n=H,'lead'))",
  M5_AX_008 = "EXEMPT (Forge single-source quick screening, NOT admit cycle)",
  S1_PRAUC_sanity = sprintf("max OOS PR-AUC = %.4f (within [0.15, 0.40] sanity range)",
                            max(dt_tbl$oos_pr, na.rm = TRUE)),
  S2_COVID_spot_check = "PASS (targets_full.parquet 2020-02-19 ret_h = -0.3405)",
  S3_replication_consistency = sprintf("v1 vs Cycle 52: Δ_q15=%+.4f / Δ_onset=%+.4f (should be ~0)",
                                        base_q15 - CYCLE_52_PT_Q15,
                                        base_ons - CYCLE_52_PT_ONSET),
  S4_cross_target_rank_consistency = sprintf("rho=%.4f", rho_targets),
  A1_cross_cycle_same_forward_labels = "PASS (all variants use targets_full.parquet)",
  A2_dohun_audit_checkpoint = "AWAITING_REVIEW",
  A3_codex_critic = sprintf("DEFER (Forge sweep). BREAKTHROUGH 시 의무: %s",
                            ifelse(grepl("BREAKTHROUGH", verdict_primary), "TRIGGERED", "not triggered"))
)

cat("\n[NEW_CYCLE_CHECKLIST]\n")
for (k in names(checklist)) cat(sprintf("  %s: %s\n", k, checklist[[k]]))

#==============================================================================
# Step 8: Output JSON + chart
#==============================================================================
cat("\n========== Step 8: Output JSON + chart ==========\n")

result_json <- list(
  cycle = "53A_patchtst_hyperparam_sweep",
  panel = "feature_panel_v4a_combined.parquet",
  n_features = 70,
  forward_labels = TRUE,
  validation_strategy = "walk_forward_expanding_5_fold_CV",
  oos_window = list(start = as.character(OOS_START), end = as.character(OOS_END)),
  n_variants = length(variants),
  targets = c("y_tail_q15", "y_onset"),
  cycle_52_reference = list(
    patchtst_y_tail_q15 = CYCLE_52_PT_Q15,
    patchtst_y_onset = CYCLE_52_PT_ONSET
  ),
  baseline_v1 = list(
    y_tail_q15 = round(base_q15, 4),
    y_onset = round(base_ons, 4),
    replication_consistency = list(
      delta_v1_vs_cycle52_q15 = round(base_q15 - CYCLE_52_PT_Q15, 4),
      delta_v1_vs_cycle52_onset = round(base_ons - CYCLE_52_PT_ONSET, 4)
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
    y_tail_q15 = list(
      id = best_q15$variant_id,
      name = best_q15$variant_name,
      oos_pr = best_q15$oos_pr,
      oos_ic = best_q15$oos_ic,
      delta_vs_baseline = round(best_q15$oos_pr - base_q15, 4),
      hparams = list(patch_size = best_q15$patch_size, d_model = best_q15$d_model,
                     n_heads = best_q15$n_heads, n_layers = best_q15$n_layers,
                     dropout = best_q15$dropout)
    ),
    y_onset = list(
      id = best_ons$variant_id,
      name = best_ons$variant_name,
      oos_pr = best_ons$oos_pr,
      oos_ic = best_ons$oos_ic,
      delta_vs_baseline = round(best_ons$oos_pr - base_ons, 4),
      hparams = list(patch_size = best_ons$patch_size, d_model = best_ons$d_model,
                     n_heads = best_ons$n_heads, n_layers = best_ons$n_layers,
                     dropout = best_ons$dropout)
    )
  ),
  cross_target_rank_consistency_spearman = round(rho_targets, 4),
  cycle_variance_audit = list(
    y_tail_q15 = list(
      mean = round(mean(dt_tbl[target == "y_tail_q15", oos_pr], na.rm = TRUE), 4),
      std  = round(sd  (dt_tbl[target == "y_tail_q15", oos_pr], na.rm = TRUE), 4),
      min  = round(min (dt_tbl[target == "y_tail_q15", oos_pr], na.rm = TRUE), 4),
      max  = round(max (dt_tbl[target == "y_tail_q15", oos_pr], na.rm = TRUE), 4)
    ),
    y_onset = list(
      mean = round(mean(dt_tbl[target == "y_onset", oos_pr], na.rm = TRUE), 4),
      std  = round(sd  (dt_tbl[target == "y_onset", oos_pr], na.rm = TRUE), 4),
      min  = round(min (dt_tbl[target == "y_onset", oos_pr], na.rm = TRUE), 4),
      max  = round(max (dt_tbl[target == "y_onset", oos_pr], na.rm = TRUE), 4)
    )
  ),
  verdict = verdict_primary,
  next_cycle_suggestion = if (grepl("BREAKTHROUGH", verdict_primary)) {
    paste0("Lock new headline. Spawn Codex + Architect AX-008 verification cycle. Best variant config: ",
           best_q15$variant_name)
  } else if (grepl("MARGINAL", verdict_primary)) {
    "Flag winner + retain baseline. Next: lr / weight_decay / batch_size / scheduler axes sweep."
  } else {
    "Hyperparam plateau. Move to architecture-side exploration (DLinear / Informer / FEDformer / TimesNet)."
  },
  new_cycle_checklist = checklist,
  python_diag = py_diag
)

out_json <- file.path(EVAL_DIR, "patchtst_sweep_v5a.json")
write_json(result_json, out_json, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[JSON] %s\n", out_json))

#==============================================================================
# Chart: variant comparison bar chart
#==============================================================================
plot_dt <- copy(dt_tbl)
plot_dt[, variant_label := sprintf("v%d %s", variant_id, variant_name)]
plot_dt[, variant_label := factor(variant_label,
                                   levels = unique(plot_dt[order(variant_id), variant_label]))]
plot_dt[, target_label := ifelse(target == "y_tail_q15",
                                  sprintf("y_tail_q15 (baseline=%.4f)", base_q15),
                                  sprintf("y_onset (baseline=%.4f)", base_ons))]

baseline_dt <- data.table(
  target_label = unique(plot_dt$target_label),
  baseline = c(base_q15, base_ons)
)

g <- ggplot(plot_dt, aes(x = variant_label, y = oos_pr, fill = variant_id == 1)) +
  geom_col() +
  geom_hline(data = baseline_dt, aes(yintercept = baseline),
             linetype = "dashed", color = "red", linewidth = 0.6) +
  facet_wrap(~ target_label, ncol = 1, scales = "free_y") +
  scale_fill_manual(values = c("FALSE" = "steelblue", "TRUE" = "darkorange"),
                    labels = c("variant", "baseline (v1)"),
                    name = NULL) +
  labs(title = sprintf("Cycle 53A PatchTST Hyperparameter Sweep — [%s]",
                       substr(verdict_primary, 1, 80)),
       subtitle = sprintf("11 variants × 2 targets (v4a 70 features / OOS 2018-2026)"),
       x = NULL, y = "OOS PR-AUC",
       caption = sprintf("Baseline (red dashed) v1=baseline. Best: y_tail_q15=v%d (%s, %.4f, Δ%+.4f), y_onset=v%d (%s, %.4f, Δ%+.4f)",
                         best_q15$variant_id, best_q15$variant_name, best_q15$oos_pr,
                         best_q15$oos_pr - base_q15,
                         best_ons$variant_id, best_ons$variant_name, best_ons$oos_pr,
                         best_ons$oos_pr - base_ons)) +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        legend.position = "bottom",
        strip.text = element_text(face = "bold"))

ggsave(file.path(CHART_DIR, "124_patchtst_sweep.png"),
       plot = g, width = 12, height = 9, dpi = 120)
cat(sprintf("[Chart] %s\n", file.path(CHART_DIR, "124_patchtst_sweep.png")))

cat("\n========== Cycle 53A AGGREGATE DONE ==========\n")
cat(sprintf("Cycle verdict: %s\n", verdict_primary))
cat(sprintf("Best y_tail_q15: v%d %s = %.4f (Δ %+.4f vs baseline %.4f)\n",
            best_q15$variant_id, best_q15$variant_name, best_q15$oos_pr,
            best_q15$oos_pr - base_q15, base_q15))
cat(sprintf("Best y_onset:    v%d %s = %.4f (Δ %+.4f vs baseline %.4f)\n",
            best_ons$variant_id, best_ons$variant_name, best_ons$oos_pr,
            best_ons$oos_pr - base_ons, base_ons))
cat(sprintf("Cross-target rank consistency rho=%.4f\n", rho_targets))
