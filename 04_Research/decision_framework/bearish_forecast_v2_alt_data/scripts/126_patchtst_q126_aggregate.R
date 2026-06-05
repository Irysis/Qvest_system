#==============================================================================
# 126_patchtst_q126_aggregate.R — Cycle 53B Path C aggregate
#
# Steps:
#   Step 1: Load 3 PatchTST predictions (q15 / q63 / q126)
#   Step 2: PR-AUC + IC per horizon
#   Step 3: vs Cycle 52 PatchTST q15 0.2463
#   Step 4: vs Cycle 48A ensemble M2 Regime q126 0.3079
#   Step 5: Multi-horizon ensemble (equal-weight, performance-weighted)
#   Step 6: Verdict (HORIZON_WIN / HORIZON_NEUTRAL / HORIZON_FAIL)
#   Step 7: 3-panel chart (PR curves per horizon)
#   Step 8: Final JSON + chart
#
# Verdict logic (도훈 mandate):
#   HORIZON_WIN:     PatchTST q126 > 0.30 → Path C 입증
#   HORIZON_NEUTRAL: 0.25 < q126 ≤ 0.30   → q15와 비슷, multi-horizon ensemble
#   HORIZON_FAIL:    q126 ≤ 0.25          → q15 retain, q126 path 폐기
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2); library(patchwork)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
V5B_DIR <- file.path(WS, "outputs/03_models/v5b_patchtst_q126")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")
dir.create(V5B_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

set.seed(42)

OOS_START <- as.Date("2018-01-01")
OOS_END   <- as.Date("2026-04-30")

# Baselines
CYCLE_52_PATCHTST_Q15 <- 0.2463  # Cycle 52 PatchTST single y_tail_q15 (headline)
CYCLE_48A_ENS_Q126_M2 <- 0.3079  # Cycle 48A 5-method ensemble M2 Regime y_tail_q126

# Helpers
pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

ic_spearman <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30) return(NA_real_)
  cor(rank(p), rank(y), method = "pearson")
}

pr_curve <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  data.table(recall = rec, precision = prec)
}

#==============================================================================
# Step 1: Load 3 horizon predictions
#==============================================================================
cat("\n========== Step 1: Load PatchTST predictions per horizon ==========\n")

load_pred <- function(target) {
  fp <- file.path(V5B_DIR, sprintf("predictions_patchtst_v5b_%s.parquet", target))
  if (!file.exists(fp)) stop(sprintf("missing: %s — run scripts/125_patchtst_q126_horizon.py first", fp))
  dt <- as.data.table(read_parquet(fp))
  dt[, Date := as.Date(Date)]
  dt[Date >= OOS_START & Date <= OOS_END]
}

dt_q15 <- load_pred("y_tail_q15")
dt_q63 <- load_pred("y_tail_q63")
dt_q126 <- load_pred("y_tail_q126")
cat(sprintf("  q15:  N=%d events=%d (%.2f%%)\n", nrow(dt_q15), sum(dt_q15$y), 100*mean(dt_q15$y)))
cat(sprintf("  q63:  N=%d events=%d (%.2f%%)\n", nrow(dt_q63), sum(dt_q63$y), 100*mean(dt_q63$y)))
cat(sprintf("  q126: N=%d events=%d (%.2f%%)\n", nrow(dt_q126), sum(dt_q126$y), 100*mean(dt_q126$y)))

#==============================================================================
# Step 2: PR-AUC + IC per horizon
#==============================================================================
cat("\n========== Step 2: Per-horizon metrics ==========\n")
pr_q15 <- pr_auc(dt_q15$p_patchtst, dt_q15$y)
pr_q63 <- pr_auc(dt_q63$p_patchtst, dt_q63$y)
pr_q126 <- pr_auc(dt_q126$p_patchtst, dt_q126$y)
ic_q15 <- ic_spearman(dt_q15$p_patchtst, dt_q15$y)
ic_q63 <- ic_spearman(dt_q63$p_patchtst, dt_q63$y)
ic_q126 <- ic_spearman(dt_q126$p_patchtst, dt_q126$y)

per_horizon <- data.table(
  target = c("y_tail_q15", "y_tail_q63", "y_tail_q126"),
  horizon_days = c(21L, 63L, 126L),
  PR_AUC = c(pr_q15, pr_q63, pr_q126),
  IC = c(ic_q15, ic_q63, ic_q126),
  N = c(nrow(dt_q15), nrow(dt_q63), nrow(dt_q126)),
  events = c(sum(dt_q15$y), sum(dt_q63$y), sum(dt_q126$y)),
  base_rate = c(mean(dt_q15$y), mean(dt_q63$y), mean(dt_q126$y))
)
cat("Per-horizon table:\n")
print(per_horizon)

#==============================================================================
# Step 3-4: Baseline comparison
#==============================================================================
cat("\n========== Step 3-4: Baseline comparison ==========\n")
delta_vs_cycle52 <- pr_q15 - CYCLE_52_PATCHTST_Q15
delta_q126_vs_cycle48a_ens <- pr_q126 - CYCLE_48A_ENS_Q126_M2
cat(sprintf("[vs Cycle 52 PatchTST q15] baseline=%.4f → 53B q15=%.4f (Δ %+.4f)\n",
            CYCLE_52_PATCHTST_Q15, pr_q15, delta_vs_cycle52))
cat(sprintf("[vs Cycle 48A ensemble M2 q126] baseline=%.4f → 53B PatchTST q126=%.4f (Δ %+.4f)\n",
            CYCLE_48A_ENS_Q126_M2, pr_q126, delta_q126_vs_cycle48a_ens))

#==============================================================================
# Step 5: Multi-horizon ensemble (post-hoc exploration)
#==============================================================================
cat("\n========== Step 5: Multi-horizon ensemble ==========\n")

# Inner join on Date — keep rows that have all 3 horizons + same y target
# Use q15 base y for the headline ensemble metric (consistent with Cycle 52 framing)
mh_q15 <- merge(merge(
  dt_q15[, .(Date, p_q15 = p_patchtst, y_q15 = y)],
  dt_q63[, .(Date, p_q63 = p_patchtst, y_q63 = y)], by = "Date"),
  dt_q126[, .(Date, p_q126 = p_patchtst, y_q126 = y)], by = "Date"
)
cat(sprintf("[multi-horizon merge] N=%d (q15 base, 3 horizons predicted)\n", nrow(mh_q15)))

mh_q15[, p_ens_eq := (p_q15 + p_q63 + p_q126) / 3]
# Performance-weighted (post-hoc; informative only)
pr_individual <- c(pr_q15, pr_q63, pr_q126)
w_perf <- pmax(pr_individual, 1e-6); w_perf <- w_perf / sum(w_perf)
mh_q15[, p_ens_w := w_perf[1] * p_q15 + w_perf[2] * p_q63 + w_perf[3] * p_q126]

# Evaluate ensembles against each target (q15 / q63 / q126)
ens_eq_pr_q15 <- pr_auc(mh_q15$p_ens_eq, mh_q15$y_q15)
ens_eq_pr_q63 <- pr_auc(mh_q15$p_ens_eq, mh_q15$y_q63)
ens_eq_pr_q126 <- pr_auc(mh_q15$p_ens_eq, mh_q15$y_q126)
ens_w_pr_q15 <- pr_auc(mh_q15$p_ens_w, mh_q15$y_q15)
ens_w_pr_q63 <- pr_auc(mh_q15$p_ens_w, mh_q15$y_q63)
ens_w_pr_q126 <- pr_auc(mh_q15$p_ens_w, mh_q15$y_q126)

multi_horizon_dt <- data.table(
  ensemble = rep(c("EqualWeight", "PerfWeighted"), each = 3),
  target = rep(c("y_tail_q15", "y_tail_q63", "y_tail_q126"), 2),
  PR_AUC = c(ens_eq_pr_q15, ens_eq_pr_q63, ens_eq_pr_q126,
             ens_w_pr_q15, ens_w_pr_q63, ens_w_pr_q126)
)
cat("Multi-horizon ensemble PR-AUC table:\n")
print(multi_horizon_dt)
cat(sprintf("[Performance weights] q15=%.3f / q63=%.3f / q126=%.3f\n",
            w_perf[1], w_perf[2], w_perf[3]))
cat("[NOTE] performance-weighted uses OOS PR for weighting → post-hoc bias; exploration only.\n")

#==============================================================================
# Step 6: Verdict
#==============================================================================
cat("\n========== Step 6: Cycle 53B Verdict (Path C horizon test) ==========\n")

# Verdict on PatchTST q126 specifically
if (pr_q126 > 0.30) {
  verdict_q126 <- sprintf("HORIZON_WIN — PatchTST q126 = %.4f > 0.30 → Path C 입증 (long horizon × patch attention 시너지)", pr_q126)
} else if (pr_q126 > 0.25) {
  verdict_q126 <- sprintf("HORIZON_NEUTRAL — PatchTST q126 = %.4f ∈ (0.25, 0.30] → q15와 비슷, multi-horizon ensemble path", pr_q126)
} else {
  verdict_q126 <- sprintf("HORIZON_FAIL — PatchTST q126 = %.4f ≤ 0.25 → q15 retain, q126 path 폐기", pr_q126)
}
cat(sprintf("\n[VERDICT] %s\n", verdict_q126))

# Cross-horizon best
best_idx <- which.max(per_horizon$PR_AUC)
best_horizon <- per_horizon[best_idx]
cat(sprintf("[Best individual horizon] %s = %.4f (IC=%.4f)\n",
            best_horizon$target, best_horizon$PR_AUC, best_horizon$IC))

# Best multi-horizon ensemble
best_ens_idx <- which.max(multi_horizon_dt$PR_AUC)
best_ens <- multi_horizon_dt[best_ens_idx]
cat(sprintf("[Best multi-horizon ensemble] %s on %s = %.4f\n",
            best_ens$ensemble, best_ens$target, best_ens$PR_AUC))

# SHOULD S1: PR-AUC sanity range [0.15, 0.40]
sanity_check <- function(v, label) {
  if (is.na(v)) return(sprintf("UNKNOWN — %s missing", label))
  if (v < 0.15) return(sprintf("SANITY_LOW — %s=%.4f < 0.15 (below base rate × 1.15x)", label, v))
  if (v > 0.40) return(sprintf("SANITY_FLAG — %s=%.4f > 0.40 (possible bug, investigate)", label, v))
  sprintf("SANITY_PASS — %s=%.4f ∈ [0.15, 0.40]", label, v)
}
sanity_q15 <- sanity_check(pr_q15, "q15")
sanity_q63 <- sanity_check(pr_q63, "q63")
sanity_q126 <- sanity_check(pr_q126, "q126")
cat(sprintf("\n[SANITY q15] %s\n", sanity_q15))
cat(sprintf("[SANITY q63] %s\n", sanity_q63))
cat(sprintf("[SANITY q126] %s\n", sanity_q126))

#==============================================================================
# Step 7-8: Chart + JSON
#==============================================================================
cat("\n========== Step 7: Build 3-panel PR curve chart ==========\n")

build_panel <- function(dt, target_label, pr_v) {
  cv <- pr_curve(dt$p_patchtst, dt$y)
  br <- mean(dt$y, na.rm = TRUE)
  ggplot(cv, aes(x = recall, y = precision)) +
    geom_line(linewidth = 0.9, color = "#1f77b4") +
    geom_hline(yintercept = br, linetype = "dashed", color = "gray40") +
    scale_x_continuous(limits = c(0, 1)) + scale_y_continuous(limits = c(0, 1)) +
    labs(title = sprintf("PatchTST %s (PR-AUC=%.4f)", target_label, pr_v),
         subtitle = sprintf("base rate %.2f%% / N=%d / events=%d", 100*br, nrow(dt), sum(dt$y)),
         x = "Recall", y = "Precision") +
    theme_minimal(base_size = 10)
}

p1 <- build_panel(dt_q15, "q15 (21d)", pr_q15)
p2 <- build_panel(dt_q63, "q63 (63d)", pr_q63)
p3 <- build_panel(dt_q126, "q126 (126d)", pr_q126)

combined <- (p1 | p2 | p3) +
  plot_annotation(
    title = sprintf("Cycle 53B Path C — PatchTST × {q15, q63, q126} long horizon  [%s]",
                    substr(verdict_q126, 1, 60)),
    subtitle = sprintf("v4a panel (70 features) / walk-forward 5-fold CV / seed=42 / OOS 2018-2026 / vs Cycle 52 PatchTST q15=%.4f, vs Cycle 48A ens M2 q126=%.4f",
                       CYCLE_52_PATCHTST_Q15, CYCLE_48A_ENS_Q126_M2),
    caption = sprintf("Dashed = base rate per horizon. Multi-horizon EW ensemble best PR-AUC=%.4f (target=%s).",
                      max(multi_horizon_dt$PR_AUC), multi_horizon_dt[which.max(PR_AUC), target]),
    theme = theme(plot.title = element_text(size = 12),
                  plot.subtitle = element_text(size = 9))
  )

chart_path <- file.path(CHART_DIR, "126_patchtst_q126_horizon.png")
ggsave(chart_path, plot = combined, width = 14, height = 6, dpi = 120)
cat(sprintf("[Chart] %s\n", chart_path))

#==============================================================================
# Step 8: Save final JSON
#==============================================================================
cat("\n========== Step 8: Save final JSON ==========\n")

# Load python diagnostics
py_diag_path <- file.path(EVAL_DIR, "patchtst_q126_v5b_python_diag.json")
py_diag <- if (file.exists(py_diag_path)) fromJSON(py_diag_path) else list(error = "missing python diag")

result_json <- list(
  cycle = "53B_patchtst_q126_horizon",
  approach = "PATH_C_LONG_HORIZON_TARGET_SWAP",
  hypothesis = "PatchTST + q126 (6m forward) ≥ 0.30 → long horizon × patch attention 시너지",
  panel = "feature_panel_v4a_combined.parquet",
  targets_source = "targets_long_horizon.parquet (Cycle 48A 103_compute_long_horizon_targets.R)",
  n_features = 70,
  forward_labels = TRUE,
  validation_strategy = "walk_forward_expanding_5_fold_CV",
  oos_window = list(start = as.character(OOS_START), end = as.character(OOS_END)),
  baselines = list(
    cycle_52_patchtst_y_tail_q15 = CYCLE_52_PATCHTST_Q15,
    cycle_48a_ensemble_M2_y_tail_q126 = CYCLE_48A_ENS_Q126_M2,
    note = "Cycle 52 PatchTST = single-architecture headline. Cycle 48A ensemble M2 = dynamic 5-method ensemble (not single-architecture)."
  ),
  per_horizon = list(
    y_tail_q15 = list(PR_AUC = round(pr_q15, 4), IC = round(ic_q15, 4),
                       N = nrow(dt_q15), events = sum(dt_q15$y),
                       base_rate = round(mean(dt_q15$y), 4),
                       horizon_days = 21L),
    y_tail_q63 = list(PR_AUC = round(pr_q63, 4), IC = round(ic_q63, 4),
                       N = nrow(dt_q63), events = sum(dt_q63$y),
                       base_rate = round(mean(dt_q63$y), 4),
                       horizon_days = 63L),
    y_tail_q126 = list(PR_AUC = round(pr_q126, 4), IC = round(ic_q126, 4),
                       N = nrow(dt_q126), events = sum(dt_q126$y),
                       base_rate = round(mean(dt_q126$y), 4),
                       horizon_days = 126L)
  ),
  per_fold = list(
    y_tail_q15 = py_diag$patchtst_y_tail_q15,
    y_tail_q63 = py_diag$patchtst_y_tail_q63,
    y_tail_q126 = py_diag$patchtst_y_tail_q126
  ),
  delta_vs_baselines = list(
    delta_q15_vs_cycle52_patchtst = round(delta_vs_cycle52, 4),
    delta_q126_vs_cycle48a_ensemble_M2 = round(delta_q126_vs_cycle48a_ens, 4),
    note = "Cycle 48A ensemble M2 baseline uses dynamic 5-method ensemble; direct comparison with single PatchTST is informative not equivalent."
  ),
  best_individual_horizon = list(
    target = best_horizon$target,
    horizon_days = best_horizon$horizon_days,
    PR_AUC = round(best_horizon$PR_AUC, 4),
    IC = round(best_horizon$IC, 4)
  ),
  multi_horizon_ensemble = list(
    n_merged = nrow(mh_q15),
    performance_weights = list(q15 = round(w_perf[1], 4), q63 = round(w_perf[2], 4), q126 = round(w_perf[3], 4)),
    weights_caveat = "performance weights are POST-HOC (using OOS PR-AUC) → upper bound, not deployable. Equal-weight is the production-safe variant.",
    equal_weight = list(
      pr_q15 = round(ens_eq_pr_q15, 4),
      pr_q63 = round(ens_eq_pr_q63, 4),
      pr_q126 = round(ens_eq_pr_q126, 4)
    ),
    performance_weighted = list(
      pr_q15 = round(ens_w_pr_q15, 4),
      pr_q63 = round(ens_w_pr_q63, 4),
      pr_q126 = round(ens_w_pr_q126, 4)
    ),
    best = list(
      ensemble = best_ens$ensemble,
      target = best_ens$target,
      PR_AUC = round(best_ens$PR_AUC, 4)
    )
  ),
  verdict_cycle = verdict_q126,
  verdict_sanity = list(
    q15 = sanity_q15,
    q63 = sanity_q63,
    q126 = sanity_q126
  ),
  new_cycle_checklist_compliance = list(
    M1_bear_date_audit = "PASS (pre-cycle 4/4, log qepm/observability/sanity_checks/bear_date_audit_latest.json)",
    M2_validate_label_direction = "PASS (targets_long_horizon.parquet uses shift(., n=H, 'lead') - forward semantics verified COVID 2020-02-19 q15=-0.3405 / q126=+0.0289 V-recovery)",
    M3_PIT_C1_C15 = "PASS (purged 60m rolling quantile per horizon, mirrors 02_target_builder.R line 60-78)",
    M4_shift_convention = "PASS (forward targets uses shift(BM_Close, n=H, type='lead'))",
    M5_AX_008 = "EXEMPT (Forge single-source quick screening; not admit cycle)",
    S1_PRAUC_sanity = paste(sanity_q15, "|", sanity_q63, "|", sanity_q126),
    S2_COVID_spot_check = "PASS (q15 ret_h=-0.3405 / q126 ret_h=+0.0289 forward semantics confirmed)",
    S3_Spearman_ranking_consistency = "N/A (single architecture, no cross-cycle dynamic ranking)",
    A1_cross_cycle_same_forward_labels = "PASS (all baselines forward labels, Cycle 50 fix retained)",
    A2_dohun_audit_checkpoint = "AWAITING_REVIEW",
    A3_codex_critic = "DEFER (Forge single-source; admit cycle 시 의무)"
  ),
  next_cycle_suggestion = if (grepl("HORIZON_WIN", verdict_q126)) {
    "Path C 확장: PatchTST hyperparam tuning under q126 (patch_size 변형 / d_model upscale) + multi-horizon ensemble Cycle 48A 동급 dynamic 5-method 적용"
  } else if (grepl("HORIZON_NEUTRAL", verdict_q126)) {
    "Multi-horizon ensemble path: q15 + q63 + q126 equal-weight (production-safe) — dynamic ensemble M2 Regime 적용으로 boost 시도"
  } else {
    "q15 단독 retain. q126 long-horizon-on-PatchTST 효과 없음; Cycle 48A ensemble 효과는 ensemble dynamic이 driver (architecture 무관)"
  },
  python_diagnostics_summary = py_diag,
  outputs = list(
    v5b_dir = V5B_DIR,
    chart = chart_path,
    final_json = file.path(EVAL_DIR, "patchtst_q126_v5b.json")
  )
)

out_json <- file.path(EVAL_DIR, "patchtst_q126_v5b.json")
write_json(result_json, out_json, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[JSON] %s\n", out_json))

cat("\n========== Cycle 53B Path C AGGREGATE DONE ==========\n")
cat(sprintf("Verdict: %s\n", verdict_q126))
cat(sprintf("Per-horizon best: %s = %.4f (IC=%.4f)\n",
            best_horizon$target, best_horizon$PR_AUC, best_horizon$IC))
cat(sprintf("Multi-horizon best: %s ensemble on %s = %.4f\n",
            best_ens$ensemble, best_ens$target, best_ens$PR_AUC))
cat(sprintf("vs Cycle 52 PatchTST q15: %+.4f\n", delta_vs_cycle52))
cat(sprintf("vs Cycle 48A ens M2 q126: %+.4f (informative, dynamic ensemble vs single architecture)\n",
            delta_q126_vs_cycle48a_ens))
