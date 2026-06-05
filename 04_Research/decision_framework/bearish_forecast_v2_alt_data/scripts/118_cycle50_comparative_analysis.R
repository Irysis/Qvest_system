#==============================================================================
# 118_cycle50_comparative_analysis.R — Cycle 50 Phase 4 Comparative Analysis
#
# Outputs:
#   outputs/04_evaluation/cycle50_rebaseline_summary.json (4 cycles × forward PR-AUC)
#   outputs/06_reports/charts/118_rebaseline_buggy_vs_forward.png (4-panel bar chart)
#
# Comparison matrix:
#   Cycle         | Method      | Buggy (backward) | Forward (Cycle 50)  | Δ          | Verdict
#   v1.3 baseline | Static_WEW  | 0.5814           | 0.1605              | -0.42      | --
#   v1.3 baseline | M2_Regime   | 0.6078           | 0.1450              | -0.46      | NEW BASELINE
#   v2_2feat (43) | M2_Regime   | 0.6390           | TBD                 | --         | rank preserve?
#   v3b_inst (45B)| M2_Regime   | 0.6417           | TBD                 | --         | rank preserve?
#   v3e_arch (45E)| WEW         | 0.6105           | TBD                 | --         | rank preserve?
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite); library(data.table); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

# Helper: load each cycle's forward JSON
load_forward <- function(json_path) {
  if (!file.exists(json_path)) {
    message(sprintf("[WARN] missing %s", json_path))
    return(NULL)
  }
  fromJSON(json_path)
}

method_names <- c("Static_WEW", "M1_Rolling", "M2_Regime", "M3_Hedge", "M4_Bayes", "M5_Bandit")

extract_dynamic <- function(jdata, level, target = "y_tail_q15") {
  if (is.null(jdata)) return(rep(NA_real_, 6))
  block <- jdata[[level]]
  if (is.null(block)) return(rep(NA_real_, 6))
  raw <- block[[sprintf("dynamic_PRAUC_%s", target)]]
  if (is.null(raw)) return(rep(NA_real_, 6))
  v <- as.numeric(raw)
  if (length(v) != 6) {
    message(sprintf("[WARN] dynamic_PRAUC_%s in %s has %d entries (expected 6)",
                    target, level, length(v)))
  }
  v
}

extract_individual <- function(jdata, level, target = "y_tail_q15") {
  if (is.null(jdata)) return(NULL)
  block <- jdata[[level]]
  if (is.null(block)) return(NULL)
  block[[sprintf("individual_OOS_PRAUC_%s", target)]]
}

#==============================================================================
# Load all 4 cycle forward results
#==============================================================================
cat("\n========== Loading all 4 cycle forward JSON files ==========\n")

j_v1f <- load_forward(file.path(EVAL_DIR, "v1_3_rebaseline_forward.json"))
j_v2f <- load_forward(file.path(EVAL_DIR, "v2_2feat_rebaseline_forward.json"))
j_v3bf <- load_forward(file.path(EVAL_DIR, "v3b_inst_rebaseline_forward.json"))
j_v3ef <- load_forward(file.path(EVAL_DIR, "v3e_arch_pivot_rebaseline_forward.json"))

cat(sprintf("v1.3 forward: %s\n", if (!is.null(j_v1f)) "LOADED" else "MISSING"))
cat(sprintf("v2_2feat forward: %s\n", if (!is.null(j_v2f)) "LOADED" else "MISSING"))
cat(sprintf("v3b_inst forward: %s\n", if (!is.null(j_v3bf)) "LOADED" else "MISSING"))
cat(sprintf("v3e_arch_pivot forward: %s\n", if (!is.null(j_v3ef)) "LOADED" else "MISSING"))

# v1.3 dynamic
v1_dyn_q15   <- extract_dynamic(j_v1f, "v1_3_forward", "y_tail_q15")
v1_dyn_onset <- extract_dynamic(j_v1f, "v1_3_forward", "y_onset")
# v2_2feat dynamic
v2_dyn_q15   <- extract_dynamic(j_v2f, "v2_2feat_forward", "y_tail_q15")
v2_dyn_onset <- extract_dynamic(j_v2f, "v2_2feat_forward", "y_onset")
# v3b_inst dynamic
v3b_dyn_q15   <- extract_dynamic(j_v3bf, "v3b_inst_forward", "y_tail_q15")
v3b_dyn_onset <- extract_dynamic(j_v3bf, "v3b_inst_forward", "y_onset")
# v3e_arch_pivot dynamic
v3e_dyn_q15   <- extract_dynamic(j_v3ef, "v3e_forward", "y_tail_q15")
v3e_dyn_onset <- extract_dynamic(j_v3ef, "v3e_forward", "y_onset")

#==============================================================================
# Buggy baseline (from prior cycle evaluation JSONs / methodology memory)
#==============================================================================
# Sources:
#   v1.3 baseline buggy:   outputs/03_models/dynamic_ensemble/dynamic_ensemble_summary.csv
#   Cycle 43 v2_2feat:    outputs/04_evaluation/5way_retrain_v2_2feat.json
#   Cycle 45B v3b_inst:   outputs/04_evaluation/5way_retrain_v3b_inst_suite.json
#   Cycle 45E v3e_arch:   outputs/04_evaluation/5way_retrain_v3e_arch_pivot.json

baseline_csv <- file.path(WS, "outputs/03_models/dynamic_ensemble/dynamic_ensemble_summary.csv")
buggy_v1_3 <- fread(baseline_csv)
buggy_v1_dyn_q15 <- buggy_v1_3[target == "y_tail_q15", PRAUC]
buggy_v1_dyn_onset <- buggy_v1_3[target == "y_onset", PRAUC]

# Try to load cycle 43 buggy
load_buggy_dynamic <- function(json_path, branch, target = "y_tail_q15") {
  if (!file.exists(json_path)) {
    message(sprintf("[WARN] missing buggy %s", json_path))
    return(rep(NA_real_, 6))
  }
  jd <- fromJSON(json_path)
  blk <- jd[[branch]]
  if (is.null(blk)) {
    message(sprintf("[WARN] no branch %s in %s", branch, json_path))
    return(rep(NA_real_, 6))
  }
  rawf <- sprintf("dynamic_PRAUC_%s", target)
  raw <- blk[[rawf]]
  if (is.null(raw)) {
    message(sprintf("[WARN] no field %s in %s.%s", rawf, json_path, branch))
    return(rep(NA_real_, 6))
  }
  if (is.list(raw) || !is.null(names(raw))) {
    # named list/vector → order by method_names
    out <- numeric(6)
    nm <- if (is.list(raw)) names(raw) else names(raw)
    for (i in seq_along(method_names)) {
      m <- method_names[i]
      if (m %in% nm) out[i] <- as.numeric(raw[[m]]) else out[i] <- NA_real_
    }
    return(out)
  }
  as.numeric(raw)
}

buggy_v2_dyn_q15   <- load_buggy_dynamic(file.path(EVAL_DIR, "5way_retrain_v2_2feat.json"),
                                          "v2_2feat", "y_tail_q15")
buggy_v2_dyn_onset <- load_buggy_dynamic(file.path(EVAL_DIR, "5way_retrain_v2_2feat.json"),
                                          "v2_2feat", "y_onset")

buggy_v3b_dyn_q15   <- load_buggy_dynamic(file.path(EVAL_DIR, "5way_retrain_v3b_inst_suite.json"),
                                           "v3b_inst_suite", "y_tail_q15")
buggy_v3b_dyn_onset <- load_buggy_dynamic(file.path(EVAL_DIR, "5way_retrain_v3b_inst_suite.json"),
                                           "v3b_inst_suite", "y_onset")

buggy_v3e_dyn_q15   <- load_buggy_dynamic(file.path(EVAL_DIR, "5way_retrain_v3e_arch_pivot.json"),
                                           "v3e_arch_pivot", "y_tail_q15")
buggy_v3e_dyn_onset <- load_buggy_dynamic(file.path(EVAL_DIR, "5way_retrain_v3e_arch_pivot.json"),
                                           "v3e_arch_pivot", "y_onset")

#==============================================================================
# Build comparative table
#==============================================================================
cat("\n========== Building comparative table ==========\n")

build_cmp_block <- function(cycle_label, buggy_dyn, fwd_dyn, target_label) {
  data.table(
    cycle = cycle_label,
    target = target_label,
    method = method_names,
    buggy = buggy_dyn,
    forward = fwd_dyn,
    delta = fwd_dyn - buggy_dyn,
    ratio = ifelse(buggy_dyn > 0, fwd_dyn / buggy_dyn, NA_real_)
  )
}

cmp_q15 <- rbindlist(list(
  build_cmp_block("v1.3 baseline", buggy_v1_dyn_q15, v1_dyn_q15, "y_tail_q15"),
  build_cmp_block("Cycle 43 v2_2feat", buggy_v2_dyn_q15, v2_dyn_q15, "y_tail_q15"),
  build_cmp_block("Cycle 45B v3b_inst", buggy_v3b_dyn_q15, v3b_dyn_q15, "y_tail_q15"),
  build_cmp_block("Cycle 45E v3e_arch", buggy_v3e_dyn_q15, v3e_dyn_q15, "y_tail_q15")
))

cmp_onset <- rbindlist(list(
  build_cmp_block("v1.3 baseline", buggy_v1_dyn_onset, v1_dyn_onset, "y_onset"),
  build_cmp_block("Cycle 43 v2_2feat", buggy_v2_dyn_onset, v2_dyn_onset, "y_onset"),
  build_cmp_block("Cycle 45B v3b_inst", buggy_v3b_dyn_onset, v3b_dyn_onset, "y_onset"),
  build_cmp_block("Cycle 45E v3e_arch", buggy_v3e_dyn_onset, v3e_dyn_onset, "y_onset")
))

cat("\n=== y_tail_q15 comparison ===\n")
print(cmp_q15)

cat("\n=== y_onset comparison ===\n")
print(cmp_onset)

#==============================================================================
# Ranking preservation
#==============================================================================
cat("\n========== Ranking preservation verdict ==========\n")

ranking_verdict <- function(cmp_dt, target_label) {
  cat(sprintf("\n--- %s ---\n", target_label))

  # Among 4 cycles compare M2_Regime PRAUC ranking
  m2 <- cmp_dt[method == "M2_Regime"]
  setorder(m2, -buggy)
  cat("[M2_Regime ranking by BUGGY]:\n")
  print(m2[, .(cycle, buggy, forward, delta)])

  setorder(m2, -forward)
  cat("\n[M2_Regime ranking by FORWARD]:\n")
  print(m2[, .(cycle, forward, buggy, delta)])

  # Check if best (highest) is preserved
  best_bug <- m2[which.max(buggy)]$cycle
  best_fwd <- m2[which.max(forward)]$cycle
  cat(sprintf("\n[Best by BUGGY] = %s\n", best_bug))
  cat(sprintf("[Best by FORWARD] = %s\n", best_fwd))
  cat(sprintf("[Best preserved] = %s\n", best_bug == best_fwd))

  # Compute Spearman rank correlation
  ranks_bug <- rank(-m2$buggy)
  ranks_fwd <- rank(-m2$forward)
  ok <- !is.na(m2$buggy) & !is.na(m2$forward)
  if (sum(ok) >= 2) {
    rho <- cor(ranks_bug[ok], ranks_fwd[ok], method = "pearson")
    cat(sprintf("[Spearman rho (M2_Regime ranking)] = %.4f\n", rho))
  }
}

ranking_verdict(cmp_q15, "y_tail_q15")
ranking_verdict(cmp_onset, "y_onset")

#==============================================================================
# Save summary JSON
#==============================================================================
cat("\n========== Save summary JSON ==========\n")

summary_json <- list(
  cycle = "50_rebaseline_comparative",
  forward_labels = TRUE,
  bug_fix = list(
    file = "scripts/02_target_builder.R",
    line = 39,
    old = "bm[, ret_h := shift(BM_Close, -H, type = 'lead') / BM_Close - 1]  # BACKWARD",
    new = "bm[, ret_h := shift(BM_Close, n = H, type = 'lead') / BM_Close - 1]  # FORWARD",
    semantics = "shift(., n=H, 'lead') returns x[t+H] (forward), NOT x[t-H] (backward as shift(.,-H,'lead') does)"
  ),
  event_rate_change = list(
    y_tail_q15_buggy_pct = 12.96,
    y_tail_q15_forward_pct = 12.82,
    y_onset_buggy_pct = 10.55,
    y_onset_forward_pct = 10.55,
    note = "y_onset event rate unchanged (uses dd_252_fwd_min via frollapply align='left', already correct)"
  ),
  comparative_y_tail_q15 = lapply(seq_len(nrow(cmp_q15)), function(i) {
    list(
      cycle = cmp_q15$cycle[i],
      method = cmp_q15$method[i],
      buggy_PRAUC = round(cmp_q15$buggy[i], 4),
      forward_PRAUC = round(cmp_q15$forward[i], 4),
      delta = round(cmp_q15$delta[i], 4),
      ratio = round(cmp_q15$ratio[i], 4)
    )
  }),
  comparative_y_onset = lapply(seq_len(nrow(cmp_onset)), function(i) {
    list(
      cycle = cmp_onset$cycle[i],
      method = cmp_onset$method[i],
      buggy_PRAUC = round(cmp_onset$buggy[i], 4),
      forward_PRAUC = round(cmp_onset$forward[i], 4),
      delta = round(cmp_onset$delta[i], 4),
      ratio = round(cmp_onset$ratio[i], 4)
    )
  })
)

out_json <- file.path(EVAL_DIR, "cycle50_rebaseline_summary.json")
write_json(summary_json, out_json, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[JSON] %s\n", out_json))

#==============================================================================
# Chart: 4-panel bar chart (1 panel per cycle, buggy vs forward bars)
#==============================================================================
cat("\n========== Generate chart ==========\n")

chart_dt <- copy(cmp_q15)
chart_dt[, cycle := factor(cycle,
                           levels = c("v1.3 baseline", "Cycle 43 v2_2feat",
                                       "Cycle 45B v3b_inst", "Cycle 45E v3e_arch"))]
chart_dt[, method := factor(method, levels = method_names)]
long <- melt(chart_dt, id.vars = c("cycle", "method"),
             measure.vars = c("buggy", "forward"),
             variable.name = "label", value.name = "PRAUC")
long[, label := factor(label, levels = c("buggy", "forward"),
                        labels = c("Buggy (backward labels)", "Forward (Cycle 50 fix)"))]

g <- ggplot(long, aes(x = method, y = PRAUC, fill = label)) +
  geom_bar(stat = "identity", position = position_dodge(width = 0.8), width = 0.7) +
  geom_text(aes(label = sprintf("%.3f", PRAUC)),
            position = position_dodge(width = 0.8), vjust = -0.4, size = 2.6) +
  facet_wrap(~ cycle, ncol = 2, scales = "free_y") +
  scale_fill_manual(values = c("Buggy (backward labels)" = "#E07A5F",
                                "Forward (Cycle 50 fix)" = "#3D5A80")) +
  labs(title = "Cycle 50 Foundational Re-baseline — Buggy vs Forward labels",
       subtitle = "y_tail_q15 OOS PR-AUC | All 4 cycle re-measurements",
       caption = "Buggy: shift(., -H, 'lead') = past h-day return (sign-flipped). Forward: shift(., n=H, 'lead') = correct forward h-day.",
       x = NULL, y = "OOS PR-AUC", fill = NULL) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 30, hjust = 1),
        plot.title = element_text(face = "bold"),
        strip.text = element_text(face = "bold"))

chart_path <- file.path(CHART_DIR, "118_rebaseline_buggy_vs_forward.png")
ggsave(chart_path, plot = g, width = 12, height = 8, dpi = 120)
cat(sprintf("[Chart] %s\n", chart_path))

cat("\n========== Cycle 50 Comparative Analysis DONE ==========\n")
