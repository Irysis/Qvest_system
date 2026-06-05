#!/usr/bin/env Rscript
# 194_q15_58c_aggregate.R — Cycle 58C Phase 5: aggregate + significance test
#
# 3 variants compared:
#   1. 53I_v5f_FIXED_57A (baseline, 79 features, 5 seeds, mean5 = 0.2382)
#   2. 53I_v5g_cross_market 15-seed (86 features, mean15) — Phase 2 output
#   3. 53I_v5h_interactions 5-seed (91 features, mean5) — Phase 3 output
#
# Significance test:
#   - Bootstrap (B=1000) CI of mean15 PR-AUC vs baseline (53I_v5f_FIXED upper=0.2732)
#   - Significant boost: v5g_mean15_CI_lower > baseline_CI_upper
#   - Paired bootstrap delta CI: P(Δ > 0)
#
# Period-balanced: EuroAfter / COVID / Recent — lift_3of3 per variant
# Final verdict: ADDITIVE_STRONG / WEAK / NEUTRAL / DILUTION
#                + significance class: STAT_SIG / MARGINAL / NOT_SIG

suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(arrow)
  has_xgb <- requireNamespace("xgboost", quietly = TRUE)
})

WS <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "04_Research/decision_framework/bearish_forecast_v2_alt_data")
IN_V5G_15 <- file.path(WS, "outputs/03_models/cycle58c_v5g_15seed")
IN_V5H_5  <- file.path(WS, "outputs/03_models/cycle58c_v5h_5seed")
IN_57A    <- file.path(WS, "outputs/03_models/cycle57a_q15_FRED_fixed")
EVAL      <- file.path(WS, "outputs/04_evaluation")
CHARTS    <- file.path(WS, "outputs/06_reports/charts")
dir.create(EVAL, recursive = TRUE, showWarnings = FALSE)
dir.create(CHARTS, recursive = TRUE, showWarnings = FALSE)

SEEDS_15 <- c(42, 123, 456, 789, 1024, 2048, 3000, 5000, 7777, 9999, 10000, 20000, 30000, 40000, 50000)
SEEDS_5  <- c(42, 123, 456, 789, 1024)

# Metric functions (identical to 189)
pr_auc <- function(p, y) {
  ok <- !(is.na(p) | is.na(y))
  p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  o <- order(-p); y_ord <- y[o]
  prec <- cumsum(y_ord) / seq_along(y_ord)
  rec  <- cumsum(y_ord) / sum(y_ord)
  sum(diff(rec) * (prec[-1] + head(prec, -1)) / 2)
}
ic_spearman <- function(p, y) {
  ok <- !(is.na(p) | is.na(y))
  p <- p[ok]; y <- y[ok]
  if (length(p) < 30) return(NA_real_)
  suppressWarnings(cor(rank(p), rank(y)))
}
boot_pr <- function(p, y, B = 1000, seed = 42) {
  set.seed(seed); n <- length(p)
  if (n < 30 || sum(y) < 5) return(c(mean = NA, lo = NA, hi = NA))
  res <- numeric(B)
  for (b in seq_len(B)) {
    idx <- sample.int(n, n, replace = TRUE)
    res[b] <- pr_auc(p[idx], y[idx])
  }
  res <- res[!is.na(res)]
  c(mean = mean(res), lo = quantile(res, 0.025, names = FALSE),
    hi = quantile(res, 0.975, names = FALSE))
}
# Paired bootstrap: Δ PR-AUC with same idx sampled across both predictors
boot_delta_pr <- function(p_new, p_base, y, B = 1000, seed = 42) {
  set.seed(seed); n <- length(p_new)
  stopifnot(length(p_base) == n, length(y) == n)
  if (n < 30 || sum(y) < 5) return(list(mean = NA, lo = NA, hi = NA, p_gt_0 = NA))
  deltas <- numeric(B)
  for (b in seq_len(B)) {
    idx <- sample.int(n, n, replace = TRUE)
    pr_new <- pr_auc(p_new[idx], y[idx])
    pr_base <- pr_auc(p_base[idx], y[idx])
    deltas[b] <- pr_new - pr_base
  }
  deltas <- deltas[!is.na(deltas)]
  list(mean = mean(deltas),
       lo = quantile(deltas, 0.025, names = FALSE),
       hi = quantile(deltas, 0.975, names = FALSE),
       p_gt_0 = mean(deltas > 0))
}

# -----------------------------------------------------------------------------
# Cycle definitions
# -----------------------------------------------------------------------------
CYCLES <- list(
  `53I_v5g_cross_market_15seed` = list(
    dir = IN_V5G_15,
    pattern = "predictions_53I_v5g_cross_market_seed%d_y_tail_q15.parquet",
    seeds = SEEDS_15, n_feat = 86, hparams = "patch=4 d=64 nhead=4 nlayer=3",
    status = "58C_15seed_v5g_cross_market"
  ),
  `53I_v5h_interactions_5seed` = list(
    dir = IN_V5H_5,
    pattern = "predictions_53I_v5h_interactions_seed%d_y_tail_q15.parquet",
    seeds = SEEDS_5, n_feat = 91, hparams = "patch=4 d=64 nhead=4 nlayer=3",
    status = "58C_5seed_v5h_v5g_plus_5_interactions"
  ),
  `53I_v5f_FIXED_57A` = list(
    dir = IN_57A,
    pattern = "predictions_53I_v5f_FIXED_seed%d_y_tail_q15.parquet",
    seeds = SEEDS_5, n_feat = 79, hparams = "patch=4 d=64 nhead=4 nlayer=3",
    status = "BASELINE_57A_53I_v5f_FIXED_no_cross_market"
  )
)

cat(rep("=", 70), "\n", sep="")
cat("[Cycle 58C Phase 5] q15 3-variants aggregate + significance test\n")
cat(rep("=", 70), "\n", sep="")

aggregate_cycle <- function(cn, cfg) {
  cat("\n[", cn, "] status=", cfg$status, "  n_seeds=", length(cfg$seeds), "\n", sep="")
  per_seed <- list(); preds_mat <- NULL; ref_y <- NULL; ref_dates <- NULL; missing_seeds <- c()
  for (s in cfg$seeds) {
    fp <- file.path(cfg$dir, sprintf(cfg$pattern, s))
    if (!file.exists(fp)) { missing_seeds <- c(missing_seeds, s); next }
    df <- as.data.table(arrow::read_parquet(fp))
    pcol <- if ("p_expert" %in% names(df)) "p_expert" else if ("p_strict" %in% names(df)) "p_strict" else if ("p_oos" %in% names(df)) "p_oos" else stop("no pred col in ", fp)
    pr <- pr_auc(df[[pcol]], df$y); ic <- ic_spearman(df[[pcol]], df$y)
    cat(sprintf("  seed=%d: n=%d bears=%d PR-AUC=%.4f IC=%.4f\n",
                s, nrow(df), as.integer(sum(df$y)), pr, ic))
    per_seed[[as.character(s)]] <- list(df = df, pr = pr, ic = ic)
    if (is.null(ref_y)) {
      ref_y <- df$y; ref_dates <- df$Date
      preds_mat <- matrix(NA_real_, nrow = nrow(df), ncol = length(cfg$seeds))
    } else {
      if (nrow(df) != length(ref_y)) stop(sprintf("seed %d row count %d != ref %d", s, nrow(df), length(ref_y)))
      if (!identical(as.character(df$Date), as.character(ref_dates))) stop(sprintf("seed %d Date misalignment vs ref", s))
      if (any(df$y != ref_y, na.rm = TRUE)) stop(sprintf("seed %d y misalignment vs ref", s))
    }
    preds_mat[, which(cfg$seeds == s)] <- df[[pcol]]
  }
  if (length(per_seed) == 0) {
    cat("  [WARN] no seeds — SKIPPED\n"); return(NULL)
  }
  if (length(missing_seeds) > 0) {
    cat(sprintf("  [WARN] CYCLE %s has only %d/%d seeds — mean ensemble below canonical\n",
                cn, length(per_seed), length(cfg$seeds)))
  }
  preds_subset <- preds_mat[, !apply(preds_mat, 2, function(c) all(is.na(c))), drop = FALSE]
  mean_pred <- rowMeans(preds_subset, na.rm = TRUE)
  mean_pr <- pr_auc(mean_pred, ref_y); mean_ic <- ic_spearman(mean_pred, ref_y)
  cat(sprintf("  [%d-seed MEAN] PR-AUC=%.4f IC=%.4f\n", ncol(preds_subset), mean_pr, mean_ic))
  prs_vec <- sapply(per_seed, function(r) r$pr)
  prs_summary <- list(mean = mean(prs_vec, na.rm = TRUE), std = sd(prs_vec, na.rm = TRUE),
                      min = min(prs_vec, na.rm = TRUE), max = max(prs_vec, na.rm = TRUE))
  cat(sprintf("  Per-seed: mean=%.4f std=%.4f min=%.4f max=%.4f\n",
              prs_summary$mean, prs_summary$std, prs_summary$min, prs_summary$max))

  # Period-balanced
  ref_dt <- as.Date(ref_dates)
  per1_idx <- which(ref_dt >= as.Date("2018-01-01") & ref_dt <= as.Date("2019-12-31"))
  per2_idx <- which(ref_dt >= as.Date("2020-01-01") & ref_dt <= as.Date("2021-12-31"))
  per3_idx <- which(ref_dt >= as.Date("2022-01-01") & ref_dt <= as.Date("2026-04-30"))
  per_pr_summary <- function(idx, label) {
    if (length(idx) < 30) return(list(period = label, n = length(idx), pr_auc = NA, lift_vs_base = NA))
    pr_p <- pr_auc(mean_pred[idx], ref_y[idx]); base <- sum(ref_y[idx]) / length(idx)
    list(period = label, n = length(idx), n_bear = sum(ref_y[idx]),
         pr_auc = pr_p, base_rate = base, lift_vs_base = pr_p / base)
  }
  per1 <- per_pr_summary(per1_idx, "EuroAfter_2018_2019")
  per2 <- per_pr_summary(per2_idx, "Covid_2020_2021")
  per3 <- per_pr_summary(per3_idx, "Recent_2022_2026")
  lift_3of3 <- sum(c(per1$lift_vs_base, per2$lift_vs_base, per3$lift_vs_base) > 1, na.rm = TRUE)
  cat(sprintf("  Period-balanced: EuroAfter lift=%.2fx Covid lift=%.2fx Recent lift=%.2fx → %d/3 > 1.0\n",
              per1$lift_vs_base, per2$lift_vs_base, per3$lift_vs_base, lift_3of3))

  boot <- boot_pr(mean_pred, ref_y, B = 1000)
  cat(sprintf("  Bootstrap [B=1000]: mean=%.4f  95%% CI=[%.4f, %.4f]\n",
              boot["mean"], boot["lo"], boot["hi"]))

  list(per_seed = per_seed, mean_pr_auc = mean_pr, mean_ic = mean_ic,
       bootstrap = boot, per_seed_summary = prs_summary, mean_pred = mean_pred,
       ref_y = ref_y, ref_dates = ref_dates,
       period_balanced = list(per1 = per1, per2 = per2, per3 = per3, lift_3of3 = lift_3of3),
       cfg = cfg)
}

results <- list(); leaderboard <- data.table()
for (cn in names(CYCLES)) {
  r <- aggregate_cycle(cn, CYCLES[[cn]])
  if (is.null(r)) next
  results[[cn]] <- r
  leaderboard <- rbind(leaderboard, data.table(
    cycle = cn, n_feat = CYCLES[[cn]]$n_feat, n_seeds = length(CYCLES[[cn]]$seeds),
    status = CYCLES[[cn]]$status,
    per_seed_pr_mean = round(r$per_seed_summary$mean, 4),
    per_seed_pr_std  = round(r$per_seed_summary$std, 4),
    per_seed_pr_min  = round(r$per_seed_summary$min, 4),
    per_seed_pr_max  = round(r$per_seed_summary$max, 4),
    mean_pr_auc = round(r$mean_pr_auc, 4), mean_ic = round(r$mean_ic, 4),
    bootstrap_lo = round(r$bootstrap["lo"], 4), bootstrap_hi = round(r$bootstrap["hi"], 4),
    euroafter_lift = round(r$period_balanced$per1$lift_vs_base, 2),
    covid_lift = round(r$period_balanced$per2$lift_vs_base, 2),
    recent_lift = round(r$period_balanced$per3$lift_vs_base, 2),
    lift_3of3 = r$period_balanced$lift_3of3
  ))
}

# -----------------------------------------------------------------------------
# Significance test: v5g_15seed vs baseline (CI overlap + paired delta CI)
# -----------------------------------------------------------------------------
sig_test_v5g <- list(); sig_test_v5h <- list()
if (!is.null(results[["53I_v5g_cross_market_15seed"]]) && !is.null(results[["53I_v5f_FIXED_57A"]])) {
  v5g <- results[["53I_v5g_cross_market_15seed"]]
  base <- results[["53I_v5f_FIXED_57A"]]
  # CI overlap test
  ci_overlap_v5g <- (v5g$bootstrap["lo"] <= base$bootstrap["hi"])
  significant_v5g <- (v5g$bootstrap["lo"] > base$bootstrap["hi"])
  # Paired delta
  if (length(v5g$mean_pred) == length(base$mean_pred) &&
      identical(as.character(v5g$ref_dates), as.character(base$ref_dates)) &&
      all(v5g$ref_y == base$ref_y, na.rm = TRUE)) {
    delta_boot <- boot_delta_pr(v5g$mean_pred, base$mean_pred, v5g$ref_y, B = 1000)
  } else {
    cat("[WARN] paired bootstrap skipped: ref dates/y mismatch v5g vs baseline\n")
    delta_boot <- list(mean = NA, lo = NA, hi = NA, p_gt_0 = NA)
  }
  sig_test_v5g <- list(
    v5g_15seed_mean = round(v5g$mean_pr_auc, 4),
    v5g_15seed_CI = c(round(v5g$bootstrap["lo"], 4), round(v5g$bootstrap["hi"], 4)),
    baseline_mean = round(base$mean_pr_auc, 4),
    baseline_CI = c(round(base$bootstrap["lo"], 4), round(base$bootstrap["hi"], 4)),
    delta = round(v5g$mean_pr_auc - base$mean_pr_auc, 4),
    CI_overlap = ci_overlap_v5g,
    significant_lo_gt_baseline_hi = significant_v5g,
    paired_delta_bootstrap = list(
      mean = round(delta_boot$mean, 4),
      CI = c(round(delta_boot$lo, 4), round(delta_boot$hi, 4)),
      p_gt_0 = round(delta_boot$p_gt_0, 4)
    ),
    significance_class = if (isTRUE(significant_v5g)) "STAT_SIG_CI_LO_GT_BASELINE_HI"
                         else if (isTRUE(delta_boot$p_gt_0 >= 0.95)) "STAT_SIG_PAIRED_DELTA_p_gt_0_ge_0.95"
                         else if (isTRUE(delta_boot$p_gt_0 >= 0.90)) "MARGINAL_SIG_paired_delta_p_gt_0_ge_0.90"
                         else "NOT_SIG"
  )
  cat("\n[SIGNIFICANCE v5g 15-seed vs baseline 5-seed]:\n")
  cat(sprintf("  v5g 15-seed CI: [%.4f, %.4f]  baseline 5-seed CI: [%.4f, %.4f]\n",
              v5g$bootstrap["lo"], v5g$bootstrap["hi"],
              base$bootstrap["lo"], base$bootstrap["hi"]))
  cat(sprintf("  CI overlap: %s   |   significant (lo > base_hi): %s\n",
              ci_overlap_v5g, significant_v5g))
  cat(sprintf("  Paired Δ: mean=%.4f  CI=[%.4f, %.4f]  P(Δ>0)=%.4f\n",
              delta_boot$mean, delta_boot$lo, delta_boot$hi, delta_boot$p_gt_0))
  cat(sprintf("  significance class: %s\n", sig_test_v5g$significance_class))
}

if (!is.null(results[["53I_v5h_interactions_5seed"]]) && !is.null(results[["53I_v5g_cross_market_15seed"]])) {
  v5h <- results[["53I_v5h_interactions_5seed"]]
  v5g <- results[["53I_v5g_cross_market_15seed"]]
  if (length(v5h$mean_pred) == length(v5g$mean_pred) &&
      identical(as.character(v5h$ref_dates), as.character(v5g$ref_dates))) {
    delta_v5h_vs_v5g <- boot_delta_pr(v5h$mean_pred, v5g$mean_pred, v5h$ref_y, B = 1000)
  } else {
    delta_v5h_vs_v5g <- list(mean = NA, lo = NA, hi = NA, p_gt_0 = NA)
  }
  sig_test_v5h <- list(
    v5h_5seed_mean = round(v5h$mean_pr_auc, 4),
    v5g_15seed_mean = round(v5g$mean_pr_auc, 4),
    delta_v5h_vs_v5g = round(v5h$mean_pr_auc - v5g$mean_pr_auc, 4),
    paired_delta_bootstrap = list(
      mean = round(delta_v5h_vs_v5g$mean, 4),
      CI = c(round(delta_v5h_vs_v5g$lo, 4), round(delta_v5h_vs_v5g$hi, 4)),
      p_gt_0 = round(delta_v5h_vs_v5g$p_gt_0, 4)
    ),
    interaction_effect = if (isTRUE(delta_v5h_vs_v5g$p_gt_0 >= 0.90)) "INTERACTION_POSITIVE"
                          else if (isTRUE(delta_v5h_vs_v5g$p_gt_0 >= 0.50)) "INTERACTION_NEUTRAL"
                          else "INTERACTION_NEGATIVE"
  )
  cat("\n[v5h interactions vs v5g 15-seed]:\n")
  cat(sprintf("  Δ mean: %+.4f   paired CI=[%+.4f, %+.4f]  P(Δ>0)=%.4f\n",
              v5h$mean_pr_auc - v5g$mean_pr_auc,
              delta_v5h_vs_v5g$lo, delta_v5h_vs_v5g$hi, delta_v5h_vs_v5g$p_gt_0))
  cat(sprintf("  interaction_effect class: %s\n", sig_test_v5h$interaction_effect))
}

# -----------------------------------------------------------------------------
# Verdict (overall)
# -----------------------------------------------------------------------------
verdict <- list(class = "UNKNOWN")
if (!is.null(results[["53I_v5g_cross_market_15seed"]]) && !is.null(results[["53I_v5f_FIXED_57A"]])) {
  v5g_pr <- results[["53I_v5g_cross_market_15seed"]]$mean_pr_auc
  base_pr <- results[["53I_v5f_FIXED_57A"]]$mean_pr_auc
  delta <- v5g_pr - base_pr
  verdict$delta_v5g_vs_baseline <- round(delta, 4)
  verdict$v5g_15seed_pr_auc <- round(v5g_pr, 4)
  verdict$baseline_pr_auc <- round(base_pr, 4)
  verdict$class <- if (delta >= 0.02) "ADDITIVE_STRONG"
              else if (delta > 0)     "ADDITIVE_WEAK"
              else if (delta >= -0.005) "NEUTRAL"
              else                    "DILUTION"
  verdict$significance_class <- sig_test_v5g$significance_class
  cat(sprintf("\n[VERDICT v5g_15seed vs baseline] PR-AUC=%.4f vs %.4f  Δ=%+.4f → %s (%s)\n",
              v5g_pr, base_pr, delta, verdict$class, verdict$significance_class))
}

# -----------------------------------------------------------------------------
# Bear date check (v5g 15-seed)
# -----------------------------------------------------------------------------
bear_check <- NULL
if (!is.null(results[["53I_v5g_cross_market_15seed"]])) {
  r <- results[["53I_v5g_cross_market_15seed"]]
  ref_dt <- as.Date(r$ref_dates)
  bear_events <- list(
    Lehman_GFC      = as.Date("2008-09-12"),
    Euro_Crisis     = as.Date("2011-08-08"),
    COVID           = as.Date("2020-02-19"),
    Recent_2022_max = as.Date("2022-06-15"),
    Recent_2024_max = as.Date("2024-08-02"))
  bear_check <- list()
  for (ev_name in names(bear_events)) {
    ev_date <- bear_events[[ev_name]]
    nearby <- which(abs(as.numeric(ref_dt - ev_date)) <= 5)
    if (length(nearby) == 0) {
      bear_check[[ev_name]] <- list(date = as.character(ev_date), status = "no_pred_window")
    } else {
      bear_check[[ev_name]] <- list(
        date = as.character(ev_date),
        pred_in_window = round(max(r$mean_pred[nearby], na.rm = TRUE), 4),
        y_in_window = max(r$ref_y[nearby], na.rm = TRUE))
    }
  }
  cat("\n[Bear date check v5g 15-seed]:\n")
  for (k in names(bear_check)) {
    bc <- bear_check[[k]]
    if (is.null(bc$pred_in_window)) cat(sprintf("  %s (%s): no window\n", k, bc$date))
    else cat(sprintf("  %s (%s): max pred=%.4f y=%d\n", k, bc$date, bc$pred_in_window, bc$y_in_window))
  }
}

cat("\n", rep("=", 70), "\n", sep="")
cat("[Cycle 58C LEADERBOARD]\n")
cat(rep("=", 70), "\n", sep="")
setorder(leaderboard, -mean_pr_auc)
print(leaderboard)
fwrite(leaderboard, file.path(EVAL, "cycle58c_q15_leaderboard.csv"))

# -----------------------------------------------------------------------------
# Save final JSON
# -----------------------------------------------------------------------------
out_json <- list(
  cycle = "58C_q15_3variants_significance",
  script = "194_q15_58c_aggregate.R",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  target = "y_tail_q15", target_horizon_days = 21,
  axes_summary = list(
    axis1 = "v5g 15-seed multi-seed significance (5 existing + 10 new)",
    axis2 = "v5h 5-seed cross-market × KR interactions (5 new features)",
    axis3 = "v5g_FIXED2 DEFERRED — v5g already inherits BBVA-FIXED2 from v5f_FIXED2 (PARITY_VERIFIED in Phase 4 stub)"
  ),
  baseline_comparison = list(
    baseline_cycle = "53I_v5f_FIXED_57A",
    baseline_mean5_pr_auc = if (!is.null(results[["53I_v5f_FIXED_57A"]])) results[["53I_v5f_FIXED_57A"]]$mean_pr_auc else 0.2382,
    verdict = verdict
  ),
  significance_v5g_vs_baseline = sig_test_v5g,
  significance_v5h_vs_v5g = sig_test_v5h,
  leaderboard = leaderboard,
  per_cycle = lapply(results, function(r) {
    list(mean_pr_auc = round(r$mean_pr_auc, 4),
         mean_ic = round(r$mean_ic, 4),
         per_seed_summary = lapply(r$per_seed_summary, function(x) round(x, 4)),
         bootstrap = round(r$bootstrap, 4),
         period_balanced = r$period_balanced,
         per_seed_pr = sapply(r$per_seed, function(p) round(p$pr, 4)),
         per_seed_ic = sapply(r$per_seed, function(p) round(p$ic, 4)))
  }),
  bear_date_check = bear_check,
  reference_baselines_q15 = list(
    v1_3_C50_6method_dyn_mean = 0.1643,
    v2_2feat_C43_best_forward = 0.2129,
    v4a_C52_mean5             = 0.2463,
    cycle56a_53I_v5f_mean5    = 0.2356,
    cycle57a_53I_v5f_FIXED    = 0.2382,
    cycle58b_53I_v5g_5seed    = 0.273
  ))

write_json(out_json, file.path(EVAL, "cycle58c_q15_significance_interactions.json"))

# -----------------------------------------------------------------------------
# Chart: 3-variants comparison
# -----------------------------------------------------------------------------
if (requireNamespace("ggplot2", quietly = TRUE)) {
  library(ggplot2)
  lb2 <- copy(leaderboard)
  lb2[, label := paste0(cycle, "\n(n_feat=", n_feat, ", seeds=", n_seeds, ")")]
  p <- ggplot(lb2, aes(x = reorder(label, mean_pr_auc), y = mean_pr_auc,
                       fill = factor(n_seeds, levels = c(5, 15)))) +
    geom_bar(stat = "identity") +
    geom_errorbar(aes(ymin = bootstrap_lo, ymax = bootstrap_hi), width = 0.2) +
    geom_text(aes(label = sprintf("%.4f\n[%.3f, %.3f]", mean_pr_auc, bootstrap_lo, bootstrap_hi)),
              vjust = -0.3, size = 3.5) +
    coord_flip() +
    labs(title = "Cycle 58C q15 3-variants: v5f_FIXED baseline vs v5g 15-seed vs v5h 5-seed (interactions)",
         subtitle = sprintf("Baseline 0.2382 → 58C verdict: %s | sig class: %s",
                            verdict$class, sig_test_v5g$significance_class),
         x = "Cycle", y = "Mean PR-AUC (q15 OOS 2018-2026)",
         fill = "n_seeds") +
    theme_minimal(base_size = 12)
  ggsave(file.path(CHARTS, "194_q15_58c_3variants.png"), p, width = 12, height = 7, dpi = 120)
  cat(sprintf("\n[saved chart] %s\n", file.path(CHARTS, "194_q15_58c_3variants.png")))
}

cat(sprintf("\n[saved] %s\n", file.path(EVAL, "cycle58c_q15_significance_interactions.json")))
cat(sprintf("[saved] %s\n", file.path(EVAL, "cycle58c_q15_leaderboard.csv")))
cat("\n[DONE] Phase 5 complete.\n")
