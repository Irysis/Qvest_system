#!/usr/bin/env Rscript
# 185_q15_BBVA_indirect_fixed_aggregate.R — Cycle 57B Phase 5 aggregator
#
# Mandate (Codex 57A_followup priority 1):
#   Aggregate 5 q15 cycles retrained on FIXED2 panels (BBVA indirect ICSA contamination removed).
#
#   Cycles (all FIXED2):
#     - 53B_v5b_FIXED2          (v4a_FIXED2 70, patch=4 d=64)
#     - 53H_v5e_FIXED2          (v5e_FIXED2 74, patch=4 d=64) — also direct US FRED FIXED
#     - 53I_v5f_FIXED2          (v5f_FIXED2 79, patch=4 d=64) — also direct US FRED FIXED + ECOS
#     - 54A_v3_patch7_FIXED2    (v4a_FIXED2 70, patch=7 d=64 stride=2)
#     - 54A_v4_dm32_FIXED2      (v4a_FIXED2 70, patch=4 d=32 stride=2)
#
#   Comparison axes:
#     1) Cycle 57B FIXED2 (BBVA + direct US FRED both fixed)
#     2) Cycle 57A FIXED (only direct US FRED fixed) — for 53H/53I
#     3) Cycle 56A original (no fix) — for 53B/54A baseline
#
#   BBVA-effect quantification:
#     Δ_BBVA_PR = FIXED2.mean5_pr - FIXED.mean5_pr (53H/53I)
#                 or FIXED2.mean5_pr - 56A.mean5_pr (53B/54A — no FIXED equivalent)
#
# Output:
#   outputs/04_evaluation/cycle57b_q15_BBVA_indirect_fixed.json (정정 leaderboard)
#   outputs/04_evaluation/cycle57b_q15_BBVA_indirect_fixed_leaderboard.csv
#   outputs/06_reports/charts/185_q15_BBVA_indirect_fixed.png

suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(ggplot2); library(arrow)
})

WS <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "04_Research/decision_framework/bearish_forecast_v2_alt_data")
IN_57B   <- file.path(WS, "outputs/03_models/cycle57b_q15_BBVA_fixed")
IN_57A   <- file.path(WS, "outputs/03_models/cycle57a_q15_FRED_fixed")
IN_56A   <- file.path(WS, "outputs/03_models/cycle56a_q15_strict_PIT")
EVAL <- file.path(WS, "outputs/04_evaluation")
CHARTS <- file.path(WS, "outputs/06_reports/charts")
dir.create(EVAL, recursive = TRUE, showWarnings = FALSE)
dir.create(CHARTS, recursive = TRUE, showWarnings = FALSE)

# -----------------------------------------------------------------------------
# Metric helpers (177 inherit)
# -----------------------------------------------------------------------------
pr_auc <- function(p, y) {
  ok <- !(is.na(p) | is.na(y))
  p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  o <- order(-p)
  y_ord <- y[o]
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
  set.seed(seed)
  n <- length(p)
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

# -----------------------------------------------------------------------------
# Cycle definitions — 5 FIXED2 cycles + reference (57A/56A) for diff
# -----------------------------------------------------------------------------
SEEDS <- c(42, 123, 456, 789, 1024)

CYCLES_FIXED2 <- list(
  `53B_v5b_FIXED2` = list(
    dir = IN_57B,
    pattern = "predictions_53B_v5b_FIXED2_seed%d_y_tail_q15.parquet",
    n_feat = 70, hparams = "patch=4 d=64 nhead=4 nlayer=3 stride=2",
    panel = "v4a_FIXED2 (BBVA indirect ICSA fixed)",
    direct_us_fred_dep = FALSE,
    indirect_bbva_init_claims_dep = FALSE,  # FIXED2
    status = "BBVA_indirect_ICSA_FIXED_57B_no_direct_us_FRED"
  ),
  `53H_v5e_FIXED2` = list(
    dir = IN_57B,
    pattern = "predictions_53H_v5e_FIXED2_seed%d_y_tail_q15.parquet",
    n_feat = 74, hparams = "patch=4 d=64 nhead=4 nlayer=3 stride=2",
    panel = "v5e_FIXED2 (BBVA + direct US FRED both fixed)",
    direct_us_fred_dep = TRUE,
    indirect_bbva_init_claims_dep = FALSE,
    status = "BBVA_indirect_ICSA_FIXED_57B_plus_direct_us_FRED_FIXED_57A"
  ),
  `53I_v5f_FIXED2` = list(
    dir = IN_57B,
    pattern = "predictions_53I_v5f_FIXED2_seed%d_y_tail_q15.parquet",
    n_feat = 79, hparams = "patch=4 d=64 nhead=4 nlayer=3 stride=2",
    panel = "v5f_FIXED2 (BBVA + direct US FRED both fixed + 5 ECOS)",
    direct_us_fred_dep = TRUE,
    indirect_bbva_init_claims_dep = FALSE,
    status = "BBVA_indirect_ICSA_FIXED_57B_plus_direct_us_FRED_FIXED_57A_plus_ECOS"
  ),
  `54A_v3_patch7_FIXED2` = list(
    dir = IN_57B,
    pattern = "predictions_54A_v3_patch7_FIXED2_seed%d_y_tail_q15.parquet",
    n_feat = 70, hparams = "patch=7 d=64 nhead=4 nlayer=3 stride=2",
    panel = "v4a_FIXED2 (BBVA indirect ICSA fixed)",
    direct_us_fred_dep = FALSE,
    indirect_bbva_init_claims_dep = FALSE,
    status = "BBVA_indirect_ICSA_FIXED_57B_no_direct_us_FRED"
  ),
  `54A_v4_dm32_FIXED2` = list(
    dir = IN_57B,
    pattern = "predictions_54A_v4_dm32_FIXED2_seed%d_y_tail_q15.parquet",
    n_feat = 70, hparams = "patch=4 d=32 nhead=4 nlayer=3 stride=2",
    panel = "v4a_FIXED2 (BBVA indirect ICSA fixed)",
    direct_us_fred_dep = FALSE,
    indirect_bbva_init_claims_dep = FALSE,
    status = "BBVA_indirect_ICSA_FIXED_57B_no_direct_us_FRED"
  )
)

# Reference: 57A FIXED (for 53H/53I direct US FRED only fixed)
CYCLES_57A_FIXED <- list(
  `53H_v5e_FIXED` = list(dir = IN_57A,
                         pattern = "predictions_53H_v5e_FIXED_seed%d_y_tail_q15.parquet",
                         n_feat = 74),
  `53I_v5f_FIXED` = list(dir = IN_57A,
                         pattern = "predictions_53I_v5f_FIXED_seed%d_y_tail_q15.parquet",
                         n_feat = 79)
)

# Reference: 56A original (for 53B/54A no fix at all)
CYCLES_56A <- list(
  `53B_v5b_56A` = list(dir = IN_56A,
                       pattern = "predictions_53B_v5b_seed%d_y_tail_q15.parquet",
                       n_feat = 70),
  `54A_v3_patch7_56A` = list(dir = IN_56A,
                             pattern = "predictions_54A_v3_patch7_seed%d_y_tail_q15.parquet",
                             n_feat = 70),
  `54A_v4_dm32_56A` = list(dir = IN_56A,
                           pattern = "predictions_54A_v4_dm32_seed%d_y_tail_q15.parquet",
                           n_feat = 70)
)

cat(rep("=", 70), "\n", sep="")
cat("[Cycle 57B] BBVA indirect ICSA contamination FIXED q15 leaderboard\n")
cat("[Cycle 57B] TARGET = y_tail_q15 (21-day forward bear tail event)\n")
cat("[Cycle 57B] All 5 cycles retrained on FIXED2 panels (BBVA + direct US FRED both fixed)\n")
cat(rep("=", 70), "\n", sep="")

aggregate_cycle <- function(cn, cfg) {
  cat("\n[", cn, "] dir=", cfg$dir, " n_feat=", cfg$n_feat, "\n", sep="")

  per_seed <- list()
  preds_mat <- NULL
  ref_y <- NULL
  ref_dates <- NULL
  missing_seeds <- c()

  for (s in SEEDS) {
    fp <- file.path(cfg$dir, sprintf(cfg$pattern, s))
    if (!file.exists(fp)) {
      missing_seeds <- c(missing_seeds, s)
      next
    }
    df <- as.data.table(arrow::read_parquet(fp))
    pcol <- if ("p_expert" %in% names(df)) "p_expert" else if ("p_strict" %in% names(df)) "p_strict" else stop("no pred col in ", fp)
    pr <- pr_auc(df[[pcol]], df$y)
    ic <- ic_spearman(df[[pcol]], df$y)
    cat(sprintf("  seed=%d: n=%d bears=%d PR-AUC=%.4f IC=%.4f\n",
                s, nrow(df), as.integer(sum(df$y)), pr, ic))
    per_seed[[as.character(s)]] <- list(df = df, pr = pr, ic = ic)
    if (is.null(ref_y)) {
      ref_y <- df$y
      ref_dates <- df$Date
      preds_mat <- matrix(NA_real_, nrow = nrow(df), ncol = length(SEEDS))
    }
    preds_mat[, which(SEEDS == s)] <- df[[pcol]]
  }

  if (length(per_seed) == 0) {
    cat("  [WARN] no seeds available — cycle SKIPPED\n")
    return(NULL)
  }
  if (length(missing_seeds) > 0) {
    cat("  [INFO] missing seeds:", missing_seeds, "\n")
  }

  preds_subset <- preds_mat[, !apply(preds_mat, 2, function(c) all(is.na(c))), drop = FALSE]
  mean_pred <- rowMeans(preds_subset, na.rm = TRUE)
  mean_pr <- pr_auc(mean_pred, ref_y)
  mean_ic <- ic_spearman(mean_pred, ref_y)
  per_date_std <- apply(preds_subset, 1, sd, na.rm = TRUE)

  cat(sprintf("  [%d-seed MEAN ensemble] PR-AUC=%.4f IC=%.4f\n",
              ncol(preds_subset), mean_pr, mean_ic))

  prs_vec <- sapply(per_seed, function(r) r$pr)
  prs_summary <- list(
    mean = mean(prs_vec, na.rm = TRUE),
    std  = sd(prs_vec, na.rm = TRUE),
    min  = min(prs_vec, na.rm = TRUE),
    max  = max(prs_vec, na.rm = TRUE)
  )
  cat(sprintf("  Per-seed: mean=%.4f std=%.4f min=%.4f max=%.4f\n",
              prs_summary$mean, prs_summary$std, prs_summary$min, prs_summary$max))

  # Period-balanced
  ref_dt <- as.Date(ref_dates)
  per1_idx <- which(ref_dt >= as.Date("2018-01-01") & ref_dt <= as.Date("2019-12-31"))
  per2_idx <- which(ref_dt >= as.Date("2020-01-01") & ref_dt <= as.Date("2021-12-31"))
  per3_idx <- which(ref_dt >= as.Date("2022-01-01") & ref_dt <= as.Date("2026-04-30"))

  per_pr_summary <- function(idx, label) {
    if (length(idx) < 30) return(list(period = label, n = length(idx), pr_auc = NA, lift_vs_base = NA))
    pr_p <- pr_auc(mean_pred[idx], ref_y[idx])
    base <- sum(ref_y[idx]) / length(idx)
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
  cat(sprintf("  Plain bootstrap [B=1000]: mean=%.4f  95%% CI=[%.4f, %.4f]\n",
              boot["mean"], boot["lo"], boot["hi"]))

  list(
    per_seed = per_seed,
    mean5_pr_auc = mean_pr, mean5_ic = mean_ic,
    bootstrap = boot,
    per_seed_summary = prs_summary,
    period_balanced = list(per1 = per1, per2 = per2, per3 = per3, lift_3of3 = lift_3of3),
    cfg = cfg
  )
}

# -----------------------------------------------------------------------------
# Aggregate 5 FIXED2 cycles
# -----------------------------------------------------------------------------
results <- list()
leaderboard <- data.table()
for (cn in names(CYCLES_FIXED2)) {
  r <- aggregate_cycle(cn, CYCLES_FIXED2[[cn]])
  if (is.null(r)) next
  results[[cn]] <- r
  leaderboard <- rbind(leaderboard, data.table(
    cycle = cn,
    n_feat = CYCLES_FIXED2[[cn]]$n_feat,
    hparams = CYCLES_FIXED2[[cn]]$hparams,
    panel = CYCLES_FIXED2[[cn]]$panel,
    status = CYCLES_FIXED2[[cn]]$status,
    direct_us_fred_dep = CYCLES_FIXED2[[cn]]$direct_us_fred_dep,
    indirect_bbva_init_claims_dep = CYCLES_FIXED2[[cn]]$indirect_bbva_init_claims_dep,
    per_seed_pr_mean = round(r$per_seed_summary$mean, 4),
    per_seed_pr_std  = round(r$per_seed_summary$std, 4),
    per_seed_pr_min  = round(r$per_seed_summary$min, 4),
    per_seed_pr_max  = round(r$per_seed_summary$max, 4),
    mean5_pr_auc = round(r$mean5_pr_auc, 4),
    mean5_ic = round(r$mean5_ic, 4),
    bootstrap_lo = round(r$bootstrap["lo"], 4),
    bootstrap_hi = round(r$bootstrap["hi"], 4),
    euroafter_lift = round(r$period_balanced$per1$lift_vs_base, 2),
    covid_lift = round(r$period_balanced$per2$lift_vs_base, 2),
    recent_lift = round(r$period_balanced$per3$lift_vs_base, 2),
    lift_3of3 = r$period_balanced$lift_3of3
  ))
}

# -----------------------------------------------------------------------------
# Reference: 57A FIXED + 56A original (for diff diagnosis)
# -----------------------------------------------------------------------------
cat("\n", rep("=", 70), "\n", sep="")
cat("[Reference: 57A FIXED (direct US FRED only)]\n")
cat(rep("=", 70), "\n", sep="")
ref_57a_results <- list()
for (cn in names(CYCLES_57A_FIXED)) {
  cat("\n[57A REF ", cn, "]\n", sep="")
  r <- aggregate_cycle(cn, CYCLES_57A_FIXED[[cn]])
  if (!is.null(r)) ref_57a_results[[cn]] <- r
}

cat("\n", rep("=", 70), "\n", sep="")
cat("[Reference: 56A original (no fix)]\n")
cat(rep("=", 70), "\n", sep="")
ref_56a_results <- list()
for (cn in names(CYCLES_56A)) {
  cat("\n[56A REF ", cn, "]\n", sep="")
  r <- aggregate_cycle(cn, CYCLES_56A[[cn]])
  if (!is.null(r)) ref_56a_results[[cn]] <- r
}

# -----------------------------------------------------------------------------
# BBVA effect diagnosis (FIXED2 vs FIXED for 53H/53I; FIXED2 vs 56A for 53B/54A)
# -----------------------------------------------------------------------------
cat("\n", rep("=", 70), "\n", sep="")
cat("[BBVA-effect diagnosis] FIXED2 vs FIXED/56A\n")
cat(rep("=", 70), "\n", sep="")

bbva_diag_rows <- list()
diagnose <- function(fixed2_cn, ref_cn, ref_label, ref_results) {
  if (is.null(results[[fixed2_cn]]) || is.null(ref_results[[ref_cn]])) return(NULL)
  f2 <- results[[fixed2_cn]]
  rf <- ref_results[[ref_cn]]
  d <- f2$mean5_pr_auc - rf$mean5_pr_auc
  sign_label <- if (d > 0.005) "FIXED2 > REF (good — BBVA contamination was suppressing model)" else
                if (d < -0.005) "FIXED2 < REF (BBVA contamination was inflating model — TRUE OOS reveal)" else
                                "tie (BBVA effect minimal)"
  cat(sprintf("\n  %s vs %s [%s]: FIXED2=%.4f REF=%.4f Δ=%+.4f → %s\n",
              fixed2_cn, ref_cn, ref_label, f2$mean5_pr_auc, rf$mean5_pr_auc, d, sign_label))
  return(data.table(
    fixed2_cycle = fixed2_cn,
    ref_cycle = ref_cn,
    ref_source = ref_label,
    fixed2_mean5_pr = round(f2$mean5_pr_auc, 4),
    ref_mean5_pr = round(rf$mean5_pr_auc, 4),
    diff_pr = round(d, 4),
    diff_sign = sign_label
  ))
}

# 53H/53I: FIXED2 vs 57A FIXED (BBVA-only effect, direct US FRED constant)
bbva_diag_rows[[1]] <- diagnose("53H_v5e_FIXED2", "53H_v5e_FIXED",
                                 "57A_FIXED (direct US FRED only)", ref_57a_results)
bbva_diag_rows[[2]] <- diagnose("53I_v5f_FIXED2", "53I_v5f_FIXED",
                                 "57A_FIXED (direct US FRED only)", ref_57a_results)

# 53B/54A: FIXED2 vs 56A (BBVA + direct US FRED combined; but 53B/54A had no direct US FRED)
bbva_diag_rows[[3]] <- diagnose("53B_v5b_FIXED2", "53B_v5b_56A",
                                 "56A_original (no fix)", ref_56a_results)
bbva_diag_rows[[4]] <- diagnose("54A_v3_patch7_FIXED2", "54A_v3_patch7_56A",
                                 "56A_original (no fix)", ref_56a_results)
bbva_diag_rows[[5]] <- diagnose("54A_v4_dm32_FIXED2", "54A_v4_dm32_56A",
                                 "56A_original (no fix)", ref_56a_results)

bbva_diag_rows <- bbva_diag_rows[!sapply(bbva_diag_rows, is.null)]
divergence <- if (length(bbva_diag_rows) > 0) rbindlist(bbva_diag_rows) else data.table()

# -----------------------------------------------------------------------------
# Leaderboard with reference baselines
# -----------------------------------------------------------------------------
cat("\n", rep("=", 70), "\n", sep="")
cat("[Cycle 57B q15 FIXED2 LEADERBOARD]\n")
cat(rep("=", 70), "\n", sep="")
setorder(leaderboard, -mean5_pr_auc)
print(leaderboard)

# Reference baselines (Cycle 50/43/52, q15 forward post-bug-fix) — same as 177
ref_baselines <- data.table(
  cycle = c("v1.3_C50_6method_dyn_mean", "v2_2feat_C43_best_forward", "v4a_C52_mean5"),
  n_feat = c(69, 71, 70),
  mean5_pr_auc = c(0.1643, 0.2129, 0.2463),
  status = "historical_reference_q15"
)
cat("\n[Reference baselines (historical, q15)]:\n")
print(ref_baselines)

# Write leaderboard
fwrite(leaderboard, file.path(EVAL, "cycle57b_q15_BBVA_indirect_fixed_leaderboard.csv"))
cat("\n[Saved] ", file.path(EVAL, "cycle57b_q15_BBVA_indirect_fixed_leaderboard.csv"), "\n", sep="")

# Headline candidate
best <- leaderboard[1]
headline <- sprintf(
  "Cycle 57B FIXED2 q15 forward best: %s (mean5 PR-AUC=%.4f, n_feat=%d, status=%s)",
  best$cycle, best$mean5_pr_auc, best$n_feat, best$status
)
cat("\n[HEADLINE]", headline, "\n")

# -----------------------------------------------------------------------------
# JSON payload (177 inherit, extended)
# -----------------------------------------------------------------------------
json_payload <- list(
  cycle = "57B_BBVA_indirect_ICSA_FIXED_q15",
  target = "y_tail_q15",
  target_horizon_days = 21L,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  n_cycles_fixed2 = nrow(leaderboard),
  seeds = SEEDS,
  pit_fixes = list(
    bug_1_purged_kfold_cv = "np.busday_offset(dates, 21, roll='forward') < valid_start (55A inherit)",
    bug_2_y_valid_mask = "ret_q15.notna() (55A inherit)",
    M6_phantom0_guard = "targets_long_horizon_observable.parquet (54D inherit)",
    M7_direct_us_pub_lag_FIXED_57A = "FRED CFNAI +55d / ICSA +5d — direct us_* features (57A Phase 1)",
    M7_indirect_bbva_pub_lag_FIXED_57B = list(
      mandate = "Cycle 57A_followup priority 1 (Codex Q3a/Q3b 2026-05-21)",
      phase1 = "fred_macro_wide.parquet pub-lag fix (13 indicators: 10 monthly + 4 weekly), 9 daily retained no-lag",
      phase2 = "A6_bbva_macro rebuild using fred_macro_wide_FIXED.parquet (logic 100% identical, Forge Pure Function)",
      phase3 = "v1.3/v4a/v5e/v5f panels rebuild (BBVA inherit clean + direct US FRED FIXED both)",
      phase4 = "5 q15 cycles retrain (53B/53H/53I/54A_v3/54A_v4) on FIXED2 panels with strict-PIT"
    )
  ),
  approach = "BBVA indirect ICSA contamination fix on top of 57A direct US FRED fix. All 5 q15 cycles retrained on FIXED2 panels.",
  codex_review_concerns_addressed_57a_inherit = list(
    Q1_publication_lag = "PASS (57A inherit)",
    Q2_pit_integrity = "PASS_WITH_NIT (57A inherit)",
    Q3a_retain_classification = "RESOLVED in 57B — all 5 cycles now BBVA-FIXED2 (no more 'retain' deferred)",
    Q3b_v4a_inheritance = "RESOLVED in 57B — v4a/v5e/v5f panels rebuilt with FIXED BBVA",
    Q3c_baseline_misattribution = "FIXED (57A inherit) 0.1643"
  ),
  leaderboard = leaderboard,
  bbva_effect_diagnosis = divergence,
  reference_baselines = ref_baselines,
  headline = headline,
  per_cycle_detail = lapply(names(results), function(cn) {
    r <- results[[cn]]
    list(
      cycle = cn,
      n_feat = r$cfg$n_feat,
      panel = r$cfg$panel,
      status = r$cfg$status,
      mean5_pr_auc = r$mean5_pr_auc,
      mean5_ic = r$mean5_ic,
      bootstrap_95ci = unname(r$bootstrap),
      per_seed_pr_mean = r$per_seed_summary$mean,
      per_seed_pr_std = r$per_seed_summary$std,
      period_balanced = r$period_balanced
    )
  })
)
jsonlite::write_json(json_payload,
                     file.path(EVAL, "cycle57b_q15_BBVA_indirect_fixed.json"),
                     pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("[Saved] ", file.path(EVAL, "cycle57b_q15_BBVA_indirect_fixed.json"), "\n", sep="")

# -----------------------------------------------------------------------------
# Leaderboard chart
# -----------------------------------------------------------------------------
lb_long <- melt(leaderboard,
                id.vars = c("cycle", "n_feat", "direct_us_fred_dep"),
                measure.vars = c("per_seed_pr_mean", "mean5_pr_auc"),
                variable.name = "metric", value.name = "pr_auc")
lb_long[, cycle_label := paste0(cycle, "\n(", n_feat, " feat)")]
lb_long[, metric_label := ifelse(metric == "per_seed_pr_mean",
                                  "Per-seed mean",
                                  "5-seed MEAN ensemble")]

p <- ggplot(lb_long, aes(x = reorder(cycle_label, pr_auc), y = pr_auc, fill = metric_label)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  geom_hline(yintercept = 0.13, linetype = "dotted", color = "gray40", linewidth = 0.5) +
  geom_hline(yintercept = 0.1643, linetype = "dashed", color = "navy", linewidth = 0.4) +
  geom_hline(yintercept = 0.2129, linetype = "dashed", color = "darkred", linewidth = 0.4) +
  geom_hline(yintercept = 0.2463, linetype = "dashed", color = "darkgreen", linewidth = 0.4) +
  annotate("text", x = 1, y = 0.135,
           label = "base_rate ≈ 0.13", color = "gray40", size = 3, hjust = 0) +
  annotate("text", x = 1, y = 0.170,
           label = "v1.3_C50_6method_mean 0.1643", color = "navy", size = 2.5, hjust = 0) +
  annotate("text", x = 1, y = 0.218,
           label = "v2_2feat_C43 0.2129", color = "darkred", size = 2.5, hjust = 0) +
  annotate("text", x = 1, y = 0.252,
           label = "v4a_C52 0.2463", color = "darkgreen", size = 2.5, hjust = 0) +
  geom_text(aes(label = sprintf("%.3f", pr_auc)),
            position = position_dodge(width = 0.8), vjust = -0.3, size = 3) +
  scale_fill_manual(values = c("Per-seed mean" = "steelblue",
                                "5-seed MEAN ensemble" = "darkorange")) +
  labs(title = "Cycle 57B — strict-PIT q15 BBVA indirect ICSA FIXED (FIXED2 panels)",
       subtitle = "fred_macro_wide → A6_bbva → v1.3/v4a/v5e/v5f rebuild (Forge Pure Function logic)",
       x = NULL, y = "PR-AUC", fill = NULL,
       caption = "BBVA + direct US FRED both fixed; all 5 q15 cycles retrained with strict-PIT") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom",
        plot.title = element_text(face = "bold"),
        axis.text.x = element_text(face = "bold"))

ggsave(file.path(CHARTS, "185_q15_BBVA_indirect_fixed.png"),
       p, width = 14, height = 8, dpi = 120, bg = "white")
cat("[Saved] ", file.path(CHARTS, "185_q15_BBVA_indirect_fixed.png"), "\n", sep="")

cat("\n[Cycle 57B q15 BBVA-FIXED2 DONE]\n")
