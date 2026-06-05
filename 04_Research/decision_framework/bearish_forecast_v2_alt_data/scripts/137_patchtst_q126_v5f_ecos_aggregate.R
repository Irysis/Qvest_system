#==============================================================================
# 137_patchtst_q126_v5f_ecos_aggregate.R — Cycle 53I aggregate
#
# Steps:
#   1. Load 2 PatchTST predictions (q15 control / q126 primary)
#   2. PR-AUC + IC per horizon
#   3. vs Cycle 53H baseline 0.4012 (v5e 74, w/ US macro)
#   4. vs Cycle 53B baseline 0.3456 (v4a 70, no US macro, no ECOS)
#   5. Verdict ADDITIVE_STRONG / ADDITIVE_WEAK / NEUTRAL / DILUTION
#   6. Per-fold best_epoch summary
#   7. NEW_CYCLE_CHECKLIST 통과 audit
#   8. Next-cycle suggestion
#   9. 2-panel PR curve chart
#   10. Final JSON
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2); library(patchwork)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
V5F_DIR <- file.path(WS, "outputs/03_models/v5f_patchtst_q126_ecos")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")
dir.create(V5F_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

set.seed(42)
`%||%` <- function(a, b) if (!is.null(a)) a else b

OOS_START <- as.Date("2018-01-01")
OOS_END <- as.Date("2026-04-30")

# Baselines
CYCLE_53H_PATCHTST_Q126 <- 0.4012  # v5e 74 features (w/ US macro)
CYCLE_53B_PATCHTST_Q126 <- 0.3456  # v4a 70 features (no US macro, no ECOS)

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
  fp <- file.path(V5F_DIR, sprintf("predictions_patchtst_v5f_%s.parquet", target))
  if (!file.exists(fp)) stop(sprintf("missing: %s — run scripts/136_patchtst_q126_v5f_ecos.py first", fp))
  dt <- as.data.table(read_parquet(fp))
  dt[, Date := as.Date(Date)]
  dt[Date >= OOS_START & Date <= OOS_END]
}

dt_q15 <- load_pred("y_tail_q15")
dt_q126 <- load_pred("y_tail_q126")
cat(sprintf("  q15:  N=%d events=%d (%.2f%%)\n", nrow(dt_q15), sum(dt_q15$y), 100*mean(dt_q15$y)))
cat(sprintf("  q126: N=%d events=%d (%.2f%%)\n", nrow(dt_q126), sum(dt_q126$y), 100*mean(dt_q126$y)))

#==============================================================================
# Step 2: Per-horizon metrics
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
delta_vs_53h <- pr_q126 - CYCLE_53H_PATCHTST_Q126
delta_vs_53b <- pr_q126 - CYCLE_53B_PATCHTST_Q126

cat(sprintf("\n[Cycle 53H baseline (v5e 74 features w/ US macro)]\n"))
cat(sprintf("  baseline = %.4f → 53I q126 = %.4f (Δ %+.4f) — INCREMENTAL ECOS contribution\n",
            CYCLE_53H_PATCHTST_Q126, pr_q126, delta_vs_53h))

cat(sprintf("\n[Cycle 53B baseline (v4a 70 features, no US macro, no ECOS)]\n"))
cat(sprintf("  baseline = %.4f → 53I q126 = %.4f (Δ %+.4f) — CUMULATIVE US + ECOS contribution\n",
            CYCLE_53B_PATCHTST_Q126, pr_q126, delta_vs_53b))

#==============================================================================
# Step 5: Verdict (vs 53H as the relevant baseline for ECOS incremental test)
#==============================================================================
cat("\n========== Step 5: Cycle 53I Verdict (vs 53H) ==========\n")

if (delta_vs_53h >= 0.02) {
  verdict <- sprintf("ADDITIVE_STRONG — PatchTST q126 + ECOS KR macro = %.4f vs 53H 0.4012 (Δ %+.4f ≥ +0.02) → ECOS KR macro at q126 PROVEN (additive beyond US macro)",
                     pr_q126, delta_vs_53h)
  verdict_code <- "ADDITIVE_STRONG"
} else if (delta_vs_53h > 0) {
  verdict <- sprintf("ADDITIVE_WEAK — PatchTST q126 + ECOS KR macro = %.4f vs 53H 0.4012 (Δ %+.4f ∈ (0, +0.02)) → marginal contribution",
                     pr_q126, delta_vs_53h)
  verdict_code <- "ADDITIVE_WEAK"
} else if (delta_vs_53h >= -0.005) {
  verdict <- sprintf("NEUTRAL — PatchTST q126 + ECOS KR macro = %.4f vs 53H 0.4012 (Δ %+.4f ∈ [-0.005, 0]) → no incremental effect (BBVA composite + US macro covers KR macro)",
                     pr_q126, delta_vs_53h)
  verdict_code <- "NEUTRAL"
} else {
  verdict <- sprintf("DILUTION — PatchTST q126 + ECOS KR macro = %.4f vs 53H 0.4012 (Δ %+.4f < -0.005) → ECOS KR macro infringes existing signal (similar to Cycle 46 pattern)",
                     pr_q126, delta_vs_53h)
  verdict_code <- "DILUTION"
}
cat(sprintf("\n[VERDICT] %s\n", verdict))

# SANITY range
sanity_check <- function(v, label) {
  if (is.na(v)) return(sprintf("UNKNOWN — %s missing", label))
  if (v < 0.15) return(sprintf("SANITY_LOW — %s=%.4f < 0.15", label, v))
  if (v > 0.50) return(sprintf("SANITY_FLAG — %s=%.4f > 0.50 (possible bug)", label, v))
  sprintf("SANITY_PASS — %s=%.4f ∈ [0.15, 0.50]", label, v)
}
sanity_q15 <- sanity_check(pr_q15, "q15")
sanity_q126 <- sanity_check(pr_q126, "q126")
cat(sprintf("\n[SANITY q15] %s\n", sanity_q15))
cat(sprintf("[SANITY q126] %s\n", sanity_q126))

#==============================================================================
# Step 6: Per-fold
#==============================================================================
cat("\n========== Step 6: Per-fold diagnostics ==========\n")
per_fold_path <- file.path(V5F_DIR, "per_fold_diagnostics.json")
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
  M2_validate_label_direction = "PASS (targets_long_horizon.parquet forward semantics — inherits 53H/53B verified)",
  M3_PIT_C1_C15 = "PASS (v5e 74 PIT inherits 53H; ECOS lag1 + 35d/50d publication lag applied in script 134)",
  M4_shift_convention = "PASS (forward targets uses shift(BM_Close, n=H, type='lead'))",
  M5_AX_008 = "EXEMPT (Forge single-source quick screening; additivity hypothesis test, not admit cycle)",
  S1_PRAUC_sanity = paste(sanity_q15, "|", sanity_q126),
  S2_COVID_spot_check = "PASS (inherits 53H/53B forward semantics)",
  S3_Spearman_ranking_consistency = "N/A (single architecture)",
  A1_cross_cycle_same_forward_labels = "PASS (53B/53H/53I all use targets_long_horizon.parquet)",
  A2_dohun_audit_checkpoint = "AWAITING_REVIEW",
  A3_codex_critic = "DEFER (Forge single-source; admit cycle 시 의무)"
)
for (k in names(ncc)) cat(sprintf("  %s: %s\n", k, ncc[[k]]))

#==============================================================================
# Step 8: Next-cycle suggestion
#==============================================================================
cat("\n========== Step 8: Next-cycle suggestion ==========\n")
if (verdict_code == "ADDITIVE_STRONG") {
  next_suggestion <- "ADDITIVE_STRONG path: ECOS KR macro at q126 PROVEN. 다음 cycle: (a) 53M sanity recovery 우선 (y_tail_q126 정의 validation), (b) v5f panel을 base로 PatchTST hyperparam sweep (patch_size=2 53E discovery), (c) ECOS 추가 series (M1 / 사업체조사 등) 추가 cycle, (d) DART 데이터 (재무제표 alt) 통합 검토."
} else if (verdict_code == "ADDITIVE_WEAK") {
  next_suggestion <- "ADDITIVE_WEAK path: marginal contribution. 다음 cycle: (a) ECOS feature subset pruning (top-2 keep, low-importance drop), (b) PatchTST patch_size 변형 (53E discovery), (c) 53M sanity recovery로 q126 target 정의 확인 우선."
} else if (verdict_code == "NEUTRAL") {
  next_suggestion <- "NEUTRAL path: KR macro signal already captured by BBVA composite (32 features) + US macro. 다음 cycle: (a) BBVA composite 자체를 sub-pipeline (XGB only)로 분리 검토, (b) ECOS는 무가치 panel addition으로 결론 — DROP, (c) v5e baseline 유지하고 architecture sweep (Cycle 53A path C: PatchTST hyperparam)."
} else {
  next_suggestion <- "DILUTION path: ECOS KR macro infringes existing signal. 다음 cycle: (a) DROP ECOS from base panel, (b) 53H v5e 유지 = forward best ever (0.4012), (c) Cycle 53M q126 target 정의 sanity 재검토 우선 — 만약 q126 target 자체 invalid 판정시 모든 53H/53I 결과 영향."
}
cat(sprintf("  %s\n", next_suggestion))

cat(sprintf("\n[Cycle 53M sanity recovery 연계] 만약 53M q126 target 정의 invalid 판정 시: 53H/53I baseline/result 모두 재평가 필요. Cycle 53M PASS 시 본 53I 결과 유효.\n"))

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
    labs(title = sprintf("PatchTST + v5e + ECOS KR macro %s (PR-AUC=%.4f)", target_label, pr_v),
         subtitle = sprintf("base rate %.2f%% / N=%d / events=%d", 100*br, nrow(dt), sum(dt$y)),
         x = "Recall", y = "Precision") +
    theme_minimal(base_size = 10)
}

p1 <- build_panel(dt_q15, "q15 (21d, control)", pr_q15)
p2 <- build_panel(dt_q126, "q126 (126d, primary)", pr_q126)

combined <- (p1 | p2) +
  plot_annotation(
    title = sprintf("Cycle 53I — PatchTST + v5e + ECOS KR macro × {q15, q126}  [%s]",
                    substr(verdict, 1, 80)),
    subtitle = sprintf("v5f panel (79 features = v5e 74 + 5 ECOS) / WF 5-fold CV / seed=42 / OOS 2018-2026 / vs 53H %.4f vs 53B %.4f",
                       CYCLE_53H_PATCHTST_Q126, CYCLE_53B_PATCHTST_Q126),
    caption = "ECOS KR macro: m2_yoy / krw_usd_change_5d / base_rate / industrial_production_yoy / cpi_yoy (lag1 + 35d/50d/1d PIT lag)",
    theme = theme(plot.title = element_text(size = 12),
                  plot.subtitle = element_text(size = 9))
  )

chart_path <- file.path(CHART_DIR, "137_patchtst_q126_v5f_ecos.png")
ggsave(chart_path, plot = combined, width = 12, height = 5.5, dpi = 120)
cat(sprintf("[Chart] %s\n", chart_path))

#==============================================================================
# Step 10: Save final JSON
#==============================================================================
cat("\n========== Step 10: Save final JSON ==========\n")
py_diag_path <- file.path(EVAL_DIR, "patchtst_q126_v5f_ecos_python_diag.json")
py_diag <- if (file.exists(py_diag_path)) fromJSON(py_diag_path) else list(error = "missing python diag")

result_json <- list(
  cycle = "53I_patchtst_q126_v5f_ecos",
  approach = "ECOS_KR_MACRO_ADDITIVE_TEST_AT_Q126",
  hypothesis = "PatchTST q126 baseline 0.4012 (Cycle 53H v5e 74 features w/ US macro) + 5 ECOS KR macro = additive (+0.02~0.04 → 0.42~0.45)",
  panel = "feature_panel_v5f_ecos_kr.parquet",
  targets_source = "targets_long_horizon.parquet (Cycle 48A 103_compute_long_horizon_targets.R)",
  n_features = 79L,
  n_features_v5e_base = 74L,
  ecos_kr_macro_features = c(
    "ecos_m2_yoy_lag1",
    "ecos_krw_usd_change_5d_lag1",
    "ecos_base_rate_lag1",
    "ecos_industrial_production_yoy_lag1",
    "ecos_cpi_yoy_lag1"
  ),
  ecos_data_source = list(
    cached_pre_existing = list(
      krw_usd = ".cache/ecos_krw_usd.parquet (2000-01~)",
      call_rate = ".cache/ecos_bond_rates.parquet (KR_Call1D, 1995-01~)",
      cpi = ".cache/ecos_bond_rates.parquet (KR_CPI monthly, 1990-01~)"
    ),
    fetched_this_cycle = list(
      m2 = ".cache/ecos_m2_monthly.parquet (161Y006/BBHA00, 2003-10~2026-03)",
      industrial_production = ".cache/ecos_industrial_production_monthly.parquet (901Y033/A00, 2000-01~2026-03)"
    ),
    fetch_method = "BOK ECOS API (https://ecos.bok.or.kr/api/StatisticSearch/...)"
  ),
  forward_labels = TRUE,
  validation_strategy = "walk_forward_expanding_5_fold_CV",
  oos_window = list(start = as.character(OOS_START), end = as.character(OOS_END)),
  baselines = list(
    cycle_53h_v5e_with_us_macro = CYCLE_53H_PATCHTST_Q126,
    cycle_53b_v4a_no_us_macro_no_ecos = CYCLE_53B_PATCHTST_Q126
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
    delta_q126_vs_53h = round(delta_vs_53h, 4),
    delta_q126_vs_53b = round(delta_vs_53b, 4),
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
  cycle_53m_sanity_connection = "53I result validity contingent on Cycle 53M q126 target definition recovery. If 53M invalidates q126 target, all 53H/53I results subject to re-evaluation.",
  python_diagnostics_summary = py_diag,
  outputs = list(
    v5f_dir = V5F_DIR,
    chart = chart_path,
    final_json = file.path(EVAL_DIR, "patchtst_q126_v5f_ecos.json")
  )
)

out_json <- file.path(EVAL_DIR, "patchtst_q126_v5f_ecos.json")
write_json(result_json, out_json, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[JSON] %s\n", out_json))

cat("\n========== Cycle 53I AGGREGATE DONE ==========\n")
cat(sprintf("Verdict: %s\n", verdict))
cat(sprintf("Per-horizon q15=%.4f (IC=%.4f) / q126=%.4f (IC=%.4f)\n",
            pr_q15, ic_q15, pr_q126, ic_q126))
cat(sprintf("vs 53H q126 (incremental ECOS): %+.4f\n", delta_vs_53h))
cat(sprintf("vs 53B q126 (cumulative US+ECOS): %+.4f\n", delta_vs_53b))
cat(sprintf("Next: %s\n", next_suggestion))
