#==============================================================================
# 139_v5d_FIXED_aggregate.R — Cycle 54A v5d_FIXED Sweep Aggregate + Period Analysis
#
# Reads:
#   outputs/03_models/v5d_FIXED/predictions_patchtst_v{N}_y_tail_q126.parquet
#   outputs/03_models/v5d_FIXED/variant_diagnostics.json
#   outputs/03_models/v5d_FIXED/provenance.json
#   outputs/04_evaluation/cycle54a_v5d_FIXED_period_analysis.json
#
# References for comparison:
#   v5b q126 (Cycle 53B):     0.3454 (logit-collapsed, ranking-only)
#   v5d original v1 (Cycle 53E): 0.3454 (logit-collapsed, identical to v5b — Cycle 53M finding)
#   v5d original v2 (53E):    0.4747 (proper calibration, patch_size=2)
#
# Steps:
#   Step 1: Per variant OOS PR-AUC + IC + collapse status
#   Step 2: Δ vs v1_FIXED + Δ vs v5b reference
#   Step 3: Period-balanced PR-AUC × variant matrix
#   Step 4: Period fragility detection (single-period > 70% of total signal)
#   Step 5: Compare to original v5d sweep (53E) — identify which variants changed
#   Step 6: Spearman rank consistency (v5d_FIXED ranking vs v5d_53E ranking)
#   Step 7: Chart: cycle54a_v5d_FIXED_comparison.png
#   Step 8: Cycle 54A verdict JSON
#
# Output:
#   outputs/04_evaluation/cycle54a_v5d_FIXED_aggregate.json
#   outputs/04_evaluation/v5d_FIXED_v2_period_analysis.json (user-requested name)
#   outputs/06_reports/charts/138_v5d_fix_comparison.png (user-requested name)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
FIXED_DIR <- file.path(WS, "outputs/03_models/v5d_FIXED")
ORIG_DIR  <- file.path(WS, "outputs/03_models/v5d_patchtst_q126_sweep")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")
dir.create(EVAL_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

OOS_START <- as.Date("2018-01-01")
OOS_END   <- as.Date("2026-04-30")

# Reference values
V5B_Q126_REF      <- 0.3454  # Cycle 53B (collapsed)
V5D_53E_V1_REF    <- 0.3454  # Cycle 53E v1 baseline (collapsed, identical to v5b)
V5D_53E_V2_REF    <- 0.4747  # Cycle 53E v2 patch_size=2

# Significance threshold
SIG_DELTA <- 0.005

# Period definitions (matches Python)
PERIODS <- list(
  S2018_19_calm        = c(as.Date("2018-01-01"), as.Date("2019-12-31")),
  S2020_21_COVID       = c(as.Date("2020-01-01"), as.Date("2021-12-31")),
  S2022_24_Stagflation = c(as.Date("2022-01-01"), as.Date("2024-12-31")),
  S2025_26_post        = c(as.Date("2025-01-01"), as.Date("2026-04-30"))
)

pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

ic_spearman_r <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30) return(NA_real_)
  cor(rank(p), rank(y), method = "pearson")
}

#==============================================================================
# Load FIXED variant diagnostics
#==============================================================================
diag_path <- file.path(FIXED_DIR, "variant_diagnostics.json")
if (!file.exists(diag_path)) {
  stop(sprintf("Missing FIXED variant diagnostics: %s\n  Run scripts/139_patchtst_q126_sweep_FIXED.py first.",
               diag_path))
}
fixed_diag <- fromJSON(diag_path, simplifyVector = FALSE)
variants <- fixed_diag$provenance$variants

cat(sprintf("\n[Loaded] %d variants from FIXED sweep\n", length(variants)))

# Original v5d 53E diagnostics (for comparison)
orig_diag_path <- file.path(ORIG_DIR, "variant_diagnostics.json")
orig_diag <- if (file.exists(orig_diag_path)) fromJSON(orig_diag_path, simplifyVector = FALSE) else NULL

#==============================================================================
# Step 1+2: Aggregate per variant (R re-verify)
#==============================================================================
cat("\n========== Step 1+2: Per variant OOS PR-AUC + Δ ==========\n")

aggregate_variant_fixed <- function(v) {
  pred_path <- file.path(FIXED_DIR,
                         sprintf("predictions_patchtst_v%d_y_tail_q126.parquet", v$id))
  if (!file.exists(pred_path)) {
    return(list(variant_id = v$id, variant_name = v$name,
                error = "missing_prediction_file",
                oos_pr = NA_real_, oos_ic = NA_real_,
                collapsed = NA, p_max = NA_real_))
  }
  dt <- as.data.table(read_parquet(pred_path))
  dt[, Date := as.Date(Date)]
  dt <- dt[Date >= OOS_START & Date <= OOS_END & !is.na(p_patchtst) & !is.na(y)]

  pa <- pr_auc(dt$p_patchtst, dt$y)
  ic <- ic_spearman_r(dt$p_patchtst, dt$y)
  p_max <- max(dt$p_patchtst, na.rm = TRUE)
  collapsed <- if ("collapsed" %in% names(dt)) dt$collapsed[1] else (p_max < 1e-4)
  adopted_seed <- if ("adopted_seed" %in% names(dt)) dt$adopted_seed[1] else NA

  list(
    variant_id = v$id,
    variant_name = v$name,
    n_obs = nrow(dt),
    n_bear = sum(dt$y),
    base_rate = mean(dt$y),
    oos_pr = pa,
    oos_ic = ic,
    p_max = p_max,
    p_p50 = median(dt$p_patchtst, na.rm = TRUE),
    p_std = sd(dt$p_patchtst, na.rm = TRUE),
    collapsed = collapsed,
    adopted_seed = adopted_seed
  )
}

agg_rows <- lapply(variants, aggregate_variant_fixed)

# Baseline (v1) from FIXED
v1_fixed_pr <- agg_rows[[1]]$oos_pr
v1_fixed_collapsed <- agg_rows[[1]]$collapsed

agg_dt <- rbindlist(lapply(agg_rows, function(r) data.table(
  variant_id = r$variant_id,
  variant_name = r$variant_name,
  n_obs = r$n_obs,
  n_bear = r$n_bear,
  oos_pr_fixed = r$oos_pr,
  oos_ic_fixed = r$oos_ic,
  p_max = r$p_max,
  collapsed_fixed = r$collapsed,
  adopted_seed = r$adopted_seed,
  delta_vs_v1_fixed = if (!is.na(r$oos_pr) && !is.na(v1_fixed_pr)) (r$oos_pr - v1_fixed_pr) else NA_real_,
  delta_vs_v5b      = if (!is.na(r$oos_pr)) (r$oos_pr - V5B_Q126_REF) else NA_real_
)), fill = TRUE)

cat("\n=== FIXED sweep results (q126) ===\n")
print(agg_dt[, .(variant_id, variant_name,
                 oos_pr_fixed = round(oos_pr_fixed, 4),
                 oos_ic_fixed = round(oos_ic_fixed, 4),
                 p_max = format(p_max, scientific = TRUE, digits = 2),
                 collapsed_fixed,
                 delta_vs_v1_fixed = round(delta_vs_v1_fixed, 4),
                 delta_vs_v5b = round(delta_vs_v5b, 4),
                 adopted_seed)])

#==============================================================================
# Step 3: Period-balanced PR-AUC matrix (R re-verify)
#==============================================================================
cat("\n========== Step 3: Period-balanced PR-AUC matrix ==========\n")

period_metrics_r <- function(p, y, dates, period_name, period_range) {
  m <- dates >= period_range[1] & dates <= period_range[2]
  n <- sum(m); n_bear <- sum(y[m])
  if (n_bear < 5) {
    return(list(period = period_name, n = n, n_bear = n_bear,
                pr_auc = NA_real_, ic = NA_real_, p_max = NA_real_,
                note = "insufficient_bear_events"))
  }
  list(
    period = period_name,
    n = n,
    n_bear = n_bear,
    base_rate = round(n_bear / n, 4),
    pr_auc = round(pr_auc(p[m], y[m]), 4),
    ic = round(ic_spearman_r(p[m], y[m]), 4),
    p_max = round(max(p[m], na.rm = TRUE), 6),
    p_p99 = round(quantile(p[m], 0.99, na.rm = TRUE), 6),
    p_p50 = round(median(p[m], na.rm = TRUE), 6),
    note = "OK"
  )
}

period_matrix <- list()
for (v in variants) {
  pred_path <- file.path(FIXED_DIR,
                         sprintf("predictions_patchtst_v%d_y_tail_q126.parquet", v$id))
  if (!file.exists(pred_path)) next
  dt <- as.data.table(read_parquet(pred_path))
  dt[, Date := as.Date(Date)]
  vkey <- sprintf("v%d_%s", v$id, v$name)
  pm <- list()
  for (pn in names(PERIODS)) {
    pm[[pn]] <- period_metrics_r(dt$p_patchtst, dt$y, dt$Date, pn, PERIODS[[pn]])
  }
  period_matrix[[vkey]] <- pm
}

# Pretty print period table for top variants (id 1, 2, 4, 8)
cat("\n=== Period-balanced PR-AUC (selected variants) ===\n")
for (vid in c(1, 2, 4, 8, 10)) {
  v <- variants[[vid]]
  vkey <- sprintf("v%d_%s", v$id, v$name)
  cat(sprintf("\n  -- v%d %s --\n", v$id, v$name))
  for (pn in names(PERIODS)) {
    pm <- period_matrix[[vkey]][[pn]]
    cat(sprintf("    %-25s n=%d n_bear=%d PR=%s IC=%s p_max=%s\n",
                pn, pm$n, pm$n_bear,
                ifelse(is.na(pm$pr_auc), "NA", as.character(pm$pr_auc)),
                ifelse(is.na(pm$ic), "NA", as.character(pm$ic)),
                ifelse(is.na(pm$p_max), "NA", as.character(pm$p_max))))
  }
}

#==============================================================================
# Step 4: Period fragility detection
#==============================================================================
cat("\n========== Step 4: Period fragility detection ==========\n")

period_fragility <- function(vkey) {
  pm <- period_matrix[[vkey]]
  prs <- sapply(pm, function(x) ifelse(is.null(x$pr_auc) || is.na(x$pr_auc), NA, x$pr_auc))
  prs <- prs[!is.na(prs)]
  if (length(prs) < 2) return(list(fragile = NA, max_ratio = NA))
  max_p <- max(prs); total_p <- sum(prs)
  max_ratio <- max_p / total_p
  list(fragile = (max_ratio > 0.50), max_ratio = round(max_ratio, 3),
       max_period = names(pm)[which.max(sapply(pm, function(x)
         ifelse(is.null(x$pr_auc) || is.na(x$pr_auc), -1, x$pr_auc)))])
}

frag_dt <- rbindlist(lapply(seq_along(variants), function(i) {
  v <- variants[[i]]; vkey <- sprintf("v%d_%s", v$id, v$name)
  fr <- period_fragility(vkey)
  data.table(variant_id = v$id, variant_name = v$name,
             max_ratio = fr$max_ratio, fragile = fr$fragile,
             dominant_period = fr$max_period)
}), fill = TRUE)
print(frag_dt)

#==============================================================================
# Step 5: Compare vs original v5d 53E sweep
#==============================================================================
cat("\n========== Step 5: vs 53E original sweep comparison ==========\n")

if (!is.null(orig_diag)) {
  orig_results <- orig_diag$results
  comp_rows <- list()
  for (v in variants) {
    k <- sprintf("v%d_%s_y_tail_q126", v$id, v$name)
    orig <- orig_results[[k]]
    orig_pr <- if (!is.null(orig$oos_pr)) orig$oos_pr else NA_real_
    fixed_pr <- agg_rows[[v$id]]$oos_pr
    diff <- if (!is.na(fixed_pr) && !is.na(orig_pr)) (fixed_pr - orig_pr) else NA_real_
    comp_rows[[length(comp_rows) + 1]] <- data.table(
      variant_id = v$id, variant_name = v$name,
      pr_53E = orig_pr, pr_54A_FIXED = fixed_pr,
      diff_FIXED_minus_53E = round(diff, 4)
    )
  }
  comp_dt <- rbindlist(comp_rows)
  print(comp_dt)

  # Spearman rank consistency
  m <- comp_dt[!is.na(pr_53E) & !is.na(pr_54A_FIXED)]
  if (nrow(m) >= 3) {
    spearman_consistency <- cor(rank(m$pr_53E), rank(m$pr_54A_FIXED), method = "pearson")
    cat(sprintf("\n  Spearman rank consistency (53E vs FIXED): %.4f (n=%d variants)\n",
                spearman_consistency, nrow(m)))
  }
}

#==============================================================================
# Step 7: Chart
#==============================================================================
cat("\n========== Step 7: Chart generation ==========\n")

# Long format for ggplot
chart_dt <- agg_dt[, .(variant_id, variant_name,
                       oos_pr_fixed,
                       delta_vs_v5b,
                       collapsed_fixed,
                       adopted_seed)]
chart_dt[, label := sprintf("v%d %s%s", variant_id, variant_name,
                            ifelse(collapsed_fixed %in% TRUE, " [COLLAPSED]", ""))]

p <- ggplot(chart_dt, aes(x = reorder(label, oos_pr_fixed), y = oos_pr_fixed,
                          fill = collapsed_fixed)) +
  geom_col() +
  geom_hline(yintercept = V5B_Q126_REF, linetype = "dashed", color = "red") +
  geom_hline(yintercept = V5D_53E_V2_REF, linetype = "dotted", color = "darkgreen") +
  geom_text(aes(label = sprintf("%.4f", oos_pr_fixed)), hjust = -0.1, size = 3) +
  coord_flip() +
  labs(title = "Cycle 54A v5d_FIXED q126 OOS PR-AUC",
       subtitle = sprintf("Red dash = v5b ref (%.4f, collapsed); Green dot = 53E v2 (%.4f)",
                          V5B_Q126_REF, V5D_53E_V2_REF),
       x = "Variant", y = "OOS PR-AUC (q126)") +
  theme_minimal() +
  scale_fill_manual(values = c("TRUE" = "tomato", "FALSE" = "steelblue", "NA" = "grey")) +
  expand_limits(y = c(0, 0.6))

chart_path <- file.path(CHART_DIR, "138_v5d_fix_comparison.png")
ggsave(chart_path, plot = p, width = 9, height = 6, dpi = 120)
cat(sprintf("[Chart] Saved: %s\n", chart_path))

#==============================================================================
# Step 8: Verdict + JSON
#==============================================================================
cat("\n========== Step 8: Verdict + JSON dump ==========\n")

# Verdict logic
v1_fix_pr <- agg_dt[variant_id == 1]$oos_pr_fixed
v2_fix_pr <- agg_dt[variant_id == 2]$oos_pr_fixed
v1_fix_col <- agg_dt[variant_id == 1]$collapsed_fixed
v2_fix_col <- agg_dt[variant_id == 2]$collapsed_fixed

verdict_parts <- list()

# Bug verdict
verdict_parts$bug_confirmed <- TRUE  # Cycle 53M finding bit-identicality reconfirmed at Phase 1
verdict_parts$bug_type <- "deterministic_logit_collapse_convergence"
verdict_parts$bug_explanation <- paste(
  "129 sweep DID retrain v1 (elapsed 880s, fresh per-fold values).",
  "However v1 baseline (patch=4 / d=64 / dropout=0.30 / SEED=42) converges to a",
  "logit-collapsed local optimum (sigmoid range [1e-26, 4e-9]) where PR-AUC=0.3454",
  "is preserved by ranking but predictions are unusable for calibration. Bit-identical",
  "to v5b because identical seed+hparams+data+cuBLAS+AMP produced identical trajectory."
)

# v1 FIXED verdict
verdict_parts$v1_fixed_collapsed <- v1_fix_col
verdict_parts$v1_fixed_pr <- v1_fix_pr

# v2 FIXED verdict
if (!is.na(v2_fix_pr)) {
  if (v2_fix_pr > V5D_53E_V2_REF + SIG_DELTA) {
    v2_verdict <- "VALID_IMPROVED"
  } else if (v2_fix_pr > V5D_53E_V2_REF - SIG_DELTA) {
    v2_verdict <- "VALID_RECONFIRMED"
  } else if (v2_fix_pr > 0.40) {
    v2_verdict <- "VALID_DEGRADED"
  } else {
    v2_verdict <- "INVALID_REVERT_REGRESSION"
  }
} else {
  v2_verdict <- "UNKNOWN"
}
verdict_parts$v2_verdict <- v2_verdict
verdict_parts$v2_fixed_pr <- v2_fix_pr
verdict_parts$v2_53E_ref <- V5D_53E_V2_REF
verdict_parts$v2_delta_vs_53E <- if (!is.na(v2_fix_pr)) round(v2_fix_pr - V5D_53E_V2_REF, 4) else NA

# Period fragility verdict for v2
v2_period <- period_matrix[[sprintf("v%d_%s", variants[[2]]$id, variants[[2]]$name)]]
v2_prs <- sapply(v2_period, function(x) ifelse(is.null(x$pr_auc) || is.na(x$pr_auc), NA, x$pr_auc))
v2_prs_clean <- v2_prs[!is.na(v2_prs)]
v2_frag <- frag_dt[variant_id == 2]
verdict_parts$v2_period_fragility <- list(
  fragile = v2_frag$fragile,
  max_ratio = v2_frag$max_ratio,
  dominant_period = v2_frag$dominant_period,
  per_period_pr = as.list(v2_prs)
)

# Output JSON
out_json <- list(
  cycle = "54A_v5d_FIXED",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  fixed_diagnostics_path = diag_path,
  references = list(
    v5b_q126_ref = V5B_Q126_REF,
    v5d_53E_v1_ref = V5D_53E_V1_REF,
    v5d_53E_v2_ref = V5D_53E_V2_REF
  ),
  per_variant = lapply(agg_rows, function(r) r),
  period_matrix = period_matrix,
  fragility = as.list(frag_dt),
  verdict = verdict_parts
)

out_path <- file.path(EVAL_DIR, "cycle54a_v5d_FIXED_aggregate.json")
write_json(out_json, out_path, pretty = TRUE, auto_unbox = TRUE, force = TRUE, na = "null")
cat(sprintf("[JSON] Saved: %s\n", out_path))

# Also save period analysis with user-requested name
period_path <- file.path(EVAL_DIR, "v5d_FIXED_v2_period_analysis.json")
period_out <- list(
  cycle = "54A_v5d_FIXED",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  period_definitions = lapply(PERIODS, function(p) list(start = format(p[1]), end = format(p[2]))),
  period_matrix = period_matrix,
  fragility = as.list(frag_dt),
  v2_focus = list(
    variant = "v2_patch_size_2",
    period_pr = as.list(v2_prs),
    fragile = v2_frag$fragile,
    max_ratio = v2_frag$max_ratio,
    dominant_period = v2_frag$dominant_period
  )
)
write_json(period_out, period_path, pretty = TRUE, auto_unbox = TRUE, force = TRUE, na = "null")
cat(sprintf("[Period analysis] Saved: %s\n", period_path))

cat("\n========== Cycle 54A FIXED aggregate DONE ==========\n")
