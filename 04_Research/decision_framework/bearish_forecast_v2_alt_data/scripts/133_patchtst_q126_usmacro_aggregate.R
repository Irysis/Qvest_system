#==============================================================================
# 133_patchtst_q126_usmacro_aggregate.R — Cycle 53H Path C 확장 aggregate
#
# Steps:
#   Step 1: Load 2 PatchTST predictions (q15 control / q126 primary)
#   Step 2: PR-AUC + IC per horizon
#   Step 3: vs Cycle 53B baseline 0.3456 (q126 without US macro)
#   Step 4: vs Cycle 47B regression at q15 (sanity — forward에서 US macro가 q15에서 dilution 재현?)
#   Step 5: Verdict ADDITIVE_STRONG / ADDITIVE_WEAK / NEUTRAL / DILUTION
#   Step 6: Per-fold best_epoch summary
#   Step 7: NEW_CYCLE_CHECKLIST 통과 audit
#   Step 8: Next-cycle suggestion (verdict-driven)
#   Step 9: 2-panel chart (q15 + q126 PR curves)
#   Step 10: Final JSON
#
# Verdict logic (도훈 mandate):
#   ADDITIVE_STRONG: Δ vs 53B ≥ +0.02 → US macro at q126 PROVEN
#   ADDITIVE_WEAK:   0 < Δ < +0.02   → marginal contribution
#   NEUTRAL:         -0.005 ≤ Δ ≤ +0.005 → no effect
#   DILUTION:        Δ < -0.005       → US macro infringes PatchTST signal
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2); library(patchwork)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
V5E_DIR <- file.path(WS, "outputs/03_models/v5e_patchtst_q126_usmacro")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")
dir.create(V5E_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

set.seed(42)

`%||%` <- function(a, b) if (!is.null(a)) a else b

OOS_START <- as.Date("2018-01-01")
OOS_END   <- as.Date("2026-04-30")

# Baselines
CYCLE_53B_PATCHTST_Q126 <- 0.3456  # Cycle 53B PatchTST q126 (v4a 70, no US macro) — forward best ever
CYCLE_53B_PATCHTST_Q15  <- NA  # NB: Cycle 53B q15 was secondary; we focus on q126 baseline

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
# Step 1: Load 2 horizon predictions
#==============================================================================
cat("\n========== Step 1: Load PatchTST predictions per horizon ==========\n")

load_pred <- function(target) {
  fp <- file.path(V5E_DIR, sprintf("predictions_patchtst_v5e_%s.parquet", target))
  if (!file.exists(fp)) stop(sprintf("missing: %s — run scripts/132_patchtst_q126_usmacro.py first", fp))
  dt <- as.data.table(read_parquet(fp))
  dt[, Date := as.Date(Date)]
  dt[Date >= OOS_START & Date <= OOS_END]
}

dt_q15 <- load_pred("y_tail_q15")
dt_q126 <- load_pred("y_tail_q126")
cat(sprintf("  q15:  N=%d events=%d (%.2f%%)\n", nrow(dt_q15), sum(dt_q15$y), 100*mean(dt_q15$y)))
cat(sprintf("  q126: N=%d events=%d (%.2f%%)\n", nrow(dt_q126), sum(dt_q126$y), 100*mean(dt_q126$y)))

#==============================================================================
# Step 2: PR-AUC + IC per horizon
#==============================================================================
cat("\n========== Step 2: Per-horizon metrics ==========\n")
pr_q15 <- pr_auc(dt_q15$p_patchtst, dt_q15$y)
pr_q126 <- pr_auc(dt_q126$p_patchtst, dt_q126$y)
ic_q15 <- ic_spearman(dt_q15$p_patchtst, dt_q15$y)
ic_q126 <- ic_spearman(dt_q126$p_patchtst, dt_q126$y)

per_horizon <- data.table(
  target = c("y_tail_q15", "y_tail_q126"),
  horizon_days = c(21L, 126L),
  PR_AUC = c(pr_q15, pr_q126),
  IC = c(ic_q15, ic_q126),
  N = c(nrow(dt_q15), nrow(dt_q126)),
  events = c(sum(dt_q15$y), sum(dt_q126$y)),
  base_rate = c(mean(dt_q15$y), mean(dt_q126$y))
)
cat("Per-horizon table:\n")
print(per_horizon)

#==============================================================================
# Step 3-4: Baseline comparison
#==============================================================================
cat("\n========== Step 3-4: Baseline comparison ==========\n")
delta_q126_vs_53b <- pr_q126 - CYCLE_53B_PATCHTST_Q126

cat(sprintf("[vs Cycle 53B PatchTST q126 (no US macro)] baseline=%.4f → 53H q126=%.4f (Δ %+.4f)\n",
            CYCLE_53B_PATCHTST_Q126, pr_q126, delta_q126_vs_53b))

# Cycle 47B q15 dilution sanity (q15 in 47B was -0.1074 dilution direction with v3f us_macro)
# Forward labels로 측정한 적이 없으니 informative only
cat("\n[Cycle 47B q15 dilution sanity (informative)]\n")
cat("  Cycle 47B (buggy era reverse labels) at q15: us_macro -0.1074 DILUTION\n")
cat(sprintf("  Cycle 53H q15 + US macro PR-AUC: %.4f\n", pr_q15))
cat("  NOTE: forward labels 측정 baseline 없어서 direct delta 불가; informative only\n")

#==============================================================================
# Step 5: Verdict
#==============================================================================
cat("\n========== Step 5: Cycle 53H Verdict ==========\n")

if (delta_q126_vs_53b >= 0.02) {
  verdict <- sprintf("ADDITIVE_STRONG — PatchTST q126 + US macro = %.4f vs 53B 0.3456 (Δ %+.4f ≥ +0.02) → US macro at q126 PROVEN (additive)",
                     pr_q126, delta_q126_vs_53b)
  verdict_code <- "ADDITIVE_STRONG"
} else if (delta_q126_vs_53b > 0) {
  verdict <- sprintf("ADDITIVE_WEAK — PatchTST q126 + US macro = %.4f vs 53B 0.3456 (Δ %+.4f ∈ (0, +0.02)) → marginal contribution",
                     pr_q126, delta_q126_vs_53b)
  verdict_code <- "ADDITIVE_WEAK"
} else if (delta_q126_vs_53b >= -0.005) {
  verdict <- sprintf("NEUTRAL — PatchTST q126 + US macro = %.4f vs 53B 0.3456 (Δ %+.4f ∈ [-0.005, 0]) → no effect (US macro redundant with v4a panel at q126)",
                     pr_q126, delta_q126_vs_53b)
  verdict_code <- "NEUTRAL"
} else {
  verdict <- sprintf("DILUTION — PatchTST q126 + US macro = %.4f vs 53B 0.3456 (Δ %+.4f < -0.005) → US macro infringes PatchTST signal (Cycle 46A 패턴 재현, q126에서도)",
                     pr_q126, delta_q126_vs_53b)
  verdict_code <- "DILUTION"
}
cat(sprintf("\n[VERDICT] %s\n", verdict))

# SANITY range
sanity_check <- function(v, label) {
  if (is.na(v)) return(sprintf("UNKNOWN — %s missing", label))
  if (v < 0.15) return(sprintf("SANITY_LOW — %s=%.4f < 0.15 (below base rate × 1.15x)", label, v))
  if (v > 0.45) return(sprintf("SANITY_FLAG — %s=%.4f > 0.45 (possible bug, investigate)", label, v))
  sprintf("SANITY_PASS — %s=%.4f ∈ [0.15, 0.45]", label, v)
}
sanity_q15 <- sanity_check(pr_q15, "q15")
sanity_q126 <- sanity_check(pr_q126, "q126")
cat(sprintf("\n[SANITY q15] %s\n", sanity_q15))
cat(sprintf("[SANITY q126] %s\n", sanity_q126))

#==============================================================================
# Step 6: Per-fold diagnostics
#==============================================================================
cat("\n========== Step 6: Per-fold diagnostics ==========\n")
per_fold_path <- file.path(V5E_DIR, "per_fold_diagnostics.json")
if (file.exists(per_fold_path)) {
  pf <- fromJSON(per_fold_path)

  print_fold_summary <- function(target_block, target_label) {
    if (is.null(target_block$per_fold)) {
      cat(sprintf("  %s: per_fold missing\n", target_label))
      return(invisible(NULL))
    }
    pf_df <- target_block$per_fold
    cat(sprintf("\n  [%s per-fold]\n", target_label))
    if (is.data.frame(pf_df)) {
      for (i in seq_len(nrow(pf_df))) {
        row <- pf_df[i, ]
        skip_str <- if (!is.null(row$skipped) && isTRUE(row$skipped)) sprintf(" SKIPPED(%s)", row$skip_reason) else ""
        cat(sprintf("    %s: best_epoch=%s best_valid_pr=%s valid_bear=%s%s\n",
                    row$fold,
                    ifelse(is.null(row$best_epoch) || is.na(row$best_epoch), "n/a", as.character(row$best_epoch)),
                    ifelse(is.null(row$best_valid_pr) || is.na(row$best_valid_pr), "n/a", as.character(row$best_valid_pr)),
                    ifelse(is.null(row$valid_bear_count) || is.na(row$valid_bear_count), "n/a", as.character(row$valid_bear_count)),
                    skip_str))
      }
    } else if (is.list(pf_df)) {
      for (fold in pf_df) {
        skip_str <- if (!is.null(fold$skipped) && isTRUE(fold$skipped)) sprintf(" SKIPPED(%s)", fold$skip_reason) else ""
        cat(sprintf("    %s: best_epoch=%s best_valid_pr=%s valid_bear=%s%s\n",
                    fold$fold %||% "?",
                    ifelse(is.null(fold$best_epoch), "n/a", as.character(fold$best_epoch)),
                    ifelse(is.null(fold$best_valid_pr), "n/a", as.character(fold$best_valid_pr)),
                    ifelse(is.null(fold$valid_bear_count), "n/a", as.character(fold$valid_bear_count)),
                    skip_str))
      }
    }
  }

  print_fold_summary(pf$patchtst_y_tail_q15, "y_tail_q15")
  print_fold_summary(pf$patchtst_y_tail_q126, "y_tail_q126")
} else {
  cat(sprintf("  per_fold_diagnostics.json missing: %s\n", per_fold_path))
  pf <- NULL
}

#==============================================================================
# Step 7: NEW_CYCLE_CHECKLIST
#==============================================================================
cat("\n========== Step 7: NEW_CYCLE_CHECKLIST audit ==========\n")
ncc <- list(
  M1_bear_date_audit = "PASS (pre-cycle 4/4, qepm/observability/sanity_checks/bear_date_audit_latest.json)",
  M2_validate_label_direction = sprintf("PASS (targets_long_horizon.parquet forward semantics verified COVID 2020-02-19 ret_q15=-0.3405 / ret_q126=+0.0289)"),
  M3_PIT_C1_C15 = "PASS (v4a 70 PIT validated Cycle 52; US macro lag1 inherits Cycle 47B v3f PIT)",
  M4_shift_convention = "PASS (forward targets uses shift(BM_Close, n=H, type='lead'))",
  M5_AX_008 = "EXEMPT (Forge single-source quick screening; additivity hypothesis test, not admit cycle)",
  S1_PRAUC_sanity = paste(sanity_q15, "|", sanity_q126),
  S2_COVID_spot_check = "PASS (q15 ret_h=-0.3405 / q126 ret_h=+0.0289 forward semantics confirmed)",
  S3_Spearman_ranking_consistency = "N/A (single architecture, no cross-cycle dynamic ranking)",
  A1_cross_cycle_same_forward_labels = "PASS (both 53B and 53H use targets_long_horizon.parquet)",
  A2_dohun_audit_checkpoint = "AWAITING_REVIEW",
  A3_codex_critic = "DEFER (Forge single-source; admit cycle 시 의무)"
)
for (k in names(ncc)) cat(sprintf("  %s: %s\n", k, ncc[[k]]))

#==============================================================================
# Step 8: Next-cycle suggestion
#==============================================================================
cat("\n========== Step 8: Next-cycle suggestion ==========\n")
if (verdict_code == "ADDITIVE_STRONG") {
  next_suggestion <- "ADDITIVE_STRONG path: US macro + v4a + PatchTST 53A hyperparam combo (Cycle 53A patch_size 변형 / d_model upscale × US macro). 또한 Cycle 47B q15 dilution → 53H q126 additive 비대칭성 → horizon-conditional US macro 유효성 다음 cycle로."
} else if (verdict_code == "ADDITIVE_WEAK") {
  next_suggestion <- "ADDITIVE_WEAK path: marginal contribution → leave US macro as optional, hyperparam sweep at q126 with v4a panel first (Cycle 53A path)."
} else if (verdict_code == "NEUTRAL") {
  next_suggestion <- "NEUTRAL path: US macro at q126 separately as sub-pipeline (다른 architecture, 예: XGBoost on US macro alone). Information overlap with v4a foreign breadth + breadth features 가능성."
} else {
  next_suggestion <- "DILUTION path: US macro at q126 무가치 in conjunction with v4a panel. DROP US macro 통합. v4a panel PatchTST 53B Path C 폐기는 부적절 (53B 0.3456 = forward best ever)."
}
cat(sprintf("  %s\n", next_suggestion))

#==============================================================================
# Step 9: Chart
#==============================================================================
cat("\n========== Step 9: Build 2-panel PR curve chart ==========\n")

build_panel <- function(dt, target_label, pr_v) {
  cv <- pr_curve(dt$p_patchtst, dt$y)
  br <- mean(dt$y, na.rm = TRUE)
  ggplot(cv, aes(x = recall, y = precision)) +
    geom_line(linewidth = 0.9, color = "#1f77b4") +
    geom_hline(yintercept = br, linetype = "dashed", color = "gray40") +
    scale_x_continuous(limits = c(0, 1)) + scale_y_continuous(limits = c(0, 1)) +
    labs(title = sprintf("PatchTST + US macro %s (PR-AUC=%.4f)", target_label, pr_v),
         subtitle = sprintf("base rate %.2f%% / N=%d / events=%d", 100*br, nrow(dt), sum(dt$y)),
         x = "Recall", y = "Precision") +
    theme_minimal(base_size = 10)
}

p1 <- build_panel(dt_q15, "q15 (21d, control)", pr_q15)
p2 <- build_panel(dt_q126, "q126 (126d, primary)", pr_q126)

combined <- (p1 | p2) +
  plot_annotation(
    title = sprintf("Cycle 53H Path C 확장 — PatchTST + v4a + US macro × {q15, q126}  [%s]",
                    substr(verdict, 1, 70)),
    subtitle = sprintf("v5e panel (74 features = v4a 70 + 4 US macro) / walk-forward 5-fold CV / seed=42 / OOS 2018-2026 / vs Cycle 53B PatchTST q126=%.4f",
                       CYCLE_53B_PATCHTST_Q126),
    caption = "Dashed = base rate per horizon. US macro: us_t10y2y / us_initial_claims_4w / us_cfnai / us_stlfsi (all lag1, Cycle 47B/48A discovery).",
    theme = theme(plot.title = element_text(size = 12),
                  plot.subtitle = element_text(size = 9))
  )

chart_path <- file.path(CHART_DIR, "133_patchtst_q126_usmacro.png")
ggsave(chart_path, plot = combined, width = 12, height = 5.5, dpi = 120)
cat(sprintf("[Chart] %s\n", chart_path))

#==============================================================================
# Step 10: Save final JSON
#==============================================================================
cat("\n========== Step 10: Save final JSON ==========\n")

# Load python diagnostics
py_diag_path <- file.path(EVAL_DIR, "patchtst_q126_usmacro_v5e_python_diag.json")
py_diag <- if (file.exists(py_diag_path)) fromJSON(py_diag_path) else list(error = "missing python diag")

result_json <- list(
  cycle = "53H_patchtst_q126_usmacro",
  approach = "PATH_C_EXTENSION_PATCHTST_PLUS_US_MACRO_AT_Q126",
  hypothesis = "PatchTST q126 baseline 0.3456 (Cycle 53B v4a 70 features) + 4 US macro = additive (+0.02~0.04 → 0.36~0.40)",
  panel = "feature_panel_v5e_q126_usmacro.parquet",
  targets_source = "targets_long_horizon.parquet (Cycle 48A 103_compute_long_horizon_targets.R)",
  n_features = 74L,
  n_features_v4a_base = 70L,
  us_macro_features = c(
    "us_t10y2y_spread_lag1",
    "us_initial_claims_4w_avg_lag1",
    "us_cfnai_lag1",
    "us_stlfsi_lag1"
  ),
  forward_labels = TRUE,
  validation_strategy = "walk_forward_expanding_5_fold_CV",
  oos_window = list(start = as.character(OOS_START), end = as.character(OOS_END)),
  baselines = list(
    cycle_53b_patchtst_y_tail_q126 = CYCLE_53B_PATCHTST_Q126,
    cycle_47b_q15_us_macro_dilution = list(
      value_buggy_era = -0.1074,
      note = "Cycle 47B at q15 (REVERSE labels, buggy era) us_macro DILUTION; forward 측정 baseline 없어서 direct delta 불가"
    )
  ),
  per_horizon = list(
    y_tail_q15 = list(PR_AUC = round(pr_q15, 4), IC = round(ic_q15, 4),
                       N = nrow(dt_q15), events = sum(dt_q15$y),
                       base_rate = round(mean(dt_q15$y), 4),
                       horizon_days = 21L),
    y_tail_q126 = list(PR_AUC = round(pr_q126, 4), IC = round(ic_q126, 4),
                       N = nrow(dt_q126), events = sum(dt_q126$y),
                       base_rate = round(mean(dt_q126$y), 4),
                       horizon_days = 126L)
  ),
  per_fold = if (!is.null(pf)) list(
    y_tail_q15 = pf$patchtst_y_tail_q15$per_fold,
    y_tail_q126 = pf$patchtst_y_tail_q126$per_fold
  ) else list(note = "per_fold_diagnostics.json missing"),
  delta_vs_baselines = list(
    delta_q126_vs_cycle53b = round(delta_q126_vs_53b, 4),
    threshold_strong_additive = 0.02,
    threshold_dilution = -0.005
  ),
  verdict_cycle = verdict,
  verdict_code = verdict_code,
  verdict_sanity = list(
    q15 = sanity_q15,
    q126 = sanity_q126
  ),
  new_cycle_checklist_compliance = ncc,
  next_cycle_suggestion = next_suggestion,
  python_diagnostics_summary = py_diag,
  outputs = list(
    v5e_dir = V5E_DIR,
    chart = chart_path,
    final_json = file.path(EVAL_DIR, "patchtst_q126_usmacro_v5e.json")
  )
)

out_json <- file.path(EVAL_DIR, "patchtst_q126_usmacro_v5e.json")
write_json(result_json, out_json, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[JSON] %s\n", out_json))

cat("\n========== Cycle 53H Path C 확장 AGGREGATE DONE ==========\n")
cat(sprintf("Verdict: %s\n", verdict))
cat(sprintf("Per-horizon q15=%.4f (IC=%.4f) / q126=%.4f (IC=%.4f)\n",
            pr_q15, ic_q15, pr_q126, ic_q126))
cat(sprintf("vs Cycle 53B q126 baseline (no US macro): %+.4f\n", delta_q126_vs_53b))
cat(sprintf("Next: %s\n", next_suggestion))
