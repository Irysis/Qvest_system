#!/usr/bin/env Rscript
# 177_q15_FRED_fixed_aggregate.R — Cycle 57A Phase 4 aggregate + corrected leaderboard
#
# Mandate: substitute Cycle 56A 53H_v5e + 53I_v5f BUGGY (direct us_* FRED features)
# with Cycle 57A FIXED retrain. 53B_v5b / 54A_v3 / 54A_v4 use v4a base panel which
# DOES NOT contain direct us_* FRED features — hence retain as "direct-us-FRED-unaffected".
#
# IMPORTANT SCOPE CAVEAT (Codex Q3a/Q3b 2026-05-21):
#   v4a panel inherits BBVA macro features (bbva_market_z etc.) from A6_bbva_macro_builder.R
#   which uses fred_macro_wide.parquet Init_Claims (the same ICSA Saturday-dating bug
#   as direct us_initial_claims_4w_avg_lag1). This is a SECONDARY indirect dependency
#   not addressed in Cycle 57A scope (out of Forge agent autonomous mandate boundary
#   — requires upstream fred_macro_wide rebuild + A6 rebuild + ALL cycles retrain).
#   Cycle 57A retain claim is therefore DIRECT-us-FRED-only. BBVA-derived contamination
#   remains as Cycle 57A_followup deferred work.
#
# Output: cycle57a_q15_FRED_fixed.json + cycle57a_q15_FRED_fixed_leaderboard.csv
#
# Cross-cycle reference baselines (q15 forward, all post-Cycle 50 bug fix):
#   - v1.3 C50 baseline (6-method dynamic mean): 0.1643 (range 0.1450~0.1917)
#   - Cycle 43 v2_2feat best forward: 0.2129 (see cycle50_rebaseline_summary.json)
#   - Cycle 52 v4a 5-seed mean ensemble: 0.2463
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(ggplot2); library(arrow)
})

WS <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "04_Research/decision_framework/bearish_forecast_v2_alt_data")
IN_FIXED <- file.path(WS, "outputs/03_models/cycle57a_q15_FRED_fixed")
IN_56A   <- file.path(WS, "outputs/03_models/cycle56a_q15_strict_PIT")
EVAL <- file.path(WS, "outputs/04_evaluation")
CHARTS <- file.path(WS, "outputs/06_reports/charts")
dir.create(EVAL, recursive = TRUE, showWarnings = FALSE)
dir.create(CHARTS, recursive = TRUE, showWarnings = FALSE)
dir.create(IN_FIXED, recursive = TRUE, showWarnings = FALSE)

# -----------------------------------------------------------------------------
# Metric functions
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
# Cycle definitions — substitute FIXED for affected, retain valid 56A for others
# -----------------------------------------------------------------------------
SEEDS <- c(42, 123, 456, 789, 1024)

CYCLES <- list(
  `53B_v5b`             = list(dir = IN_56A,   pattern = "predictions_53B_v5b_seed%d_y_tail_q15.parquet",
                                n_feat = 70, hparams = "patch=4 d=64 nhead=4 nlayer=3",
                                direct_us_fred_dep = FALSE,
                                indirect_bbva_init_claims_dep = TRUE,
                                status = "retain_56A_no_direct_us_FRED_BUT_bbva_init_claims_indirect_contamination_remains"),
  `53H_v5e_FIXED`       = list(dir = IN_FIXED, pattern = "predictions_53H_v5e_FIXED_seed%d_y_tail_q15.parquet",
                                n_feat = 74, hparams = "patch=4 d=64 nhead=4 nlayer=3",
                                direct_us_fred_dep = TRUE,
                                indirect_bbva_init_claims_dep = TRUE,
                                status = "FRED_direct_us_lag_FIXED_57A_but_BBVA_indirect_remains",
                                substitute_for = "53H_v5e (cycle56a, BUGGY direct + indirect)"),
  `53I_v5f_FIXED`       = list(dir = IN_FIXED, pattern = "predictions_53I_v5f_FIXED_seed%d_y_tail_q15.parquet",
                                n_feat = 79, hparams = "patch=4 d=64 nhead=4 nlayer=3",
                                direct_us_fred_dep = TRUE,
                                indirect_bbva_init_claims_dep = TRUE,
                                status = "FRED_direct_us_lag_FIXED_57A_but_BBVA_indirect_remains",
                                substitute_for = "53I_v5f (cycle56a, BUGGY direct + indirect)"),
  `54A_v3_patch7`       = list(dir = IN_56A,   pattern = "predictions_54A_v3_patch7_seed%d_y_tail_q15.parquet",
                                n_feat = 70, hparams = "patch=7 d=64 nhead=4 nlayer=3 stride=2",
                                direct_us_fred_dep = FALSE,
                                indirect_bbva_init_claims_dep = TRUE,
                                status = "retain_56A_no_direct_us_FRED_BUT_bbva_init_claims_indirect_contamination_remains"),
  `54A_v4_dm32`         = list(dir = IN_56A,   pattern = "predictions_54A_v4_dm32_seed%d_y_tail_q15.parquet",
                                n_feat = 70, hparams = "patch=4 d=32 nhead=4 nlayer=3 stride=2",
                                direct_us_fred_dep = FALSE,
                                indirect_bbva_init_claims_dep = TRUE,
                                status = "retain_56A_no_direct_us_FRED_BUT_bbva_init_claims_indirect_contamination_remains")
)

# BUGGY references (for divergence diagnosis)
CYCLES_BUGGY <- list(
  `53H_v5e_BUGGY` = list(dir = IN_56A, pattern = "predictions_53H_v5e_seed%d_y_tail_q15.parquet",
                          n_feat = 74),
  `53I_v5f_BUGGY` = list(dir = IN_56A, pattern = "predictions_53I_v5f_seed%d_y_tail_q15.parquet",
                          n_feat = 79)
)

cat(rep("=", 70), "\n", sep="")
cat("[Cycle 57A] FRED publication-lag FIXED q15 leaderboard\n")
cat("[Cycle 57A] TARGET = y_tail_q15 (21-day forward bear tail event)\n")
cat("[Cycle 57A] Substitute: 53H_v5e_FIXED + 53I_v5f_FIXED for buggy 56A counterparts\n")
cat("[Cycle 57A] Retain:    53B_v5b + 54A_v3_patch7 + 54A_v4_dm32 (v4a base, NO FRED)\n")
cat(rep("=", 70), "\n", sep="")

aggregate_cycle <- function(cn, cfg) {
  cat("\n[", cn, "] status=", cfg$status, " dir=", cfg$dir, " n_feat=", cfg$n_feat, "\n", sep="")

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
    list(period = label, n = length(idx), n_bear = sum(ref_y[idx]), pr_auc = pr_p, base_rate = base, lift_vs_base = pr_p / base)
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
# Aggregate FIXED + retained cycles
# -----------------------------------------------------------------------------
results <- list()
leaderboard <- data.table()
for (cn in names(CYCLES)) {
  r <- aggregate_cycle(cn, CYCLES[[cn]])
  if (is.null(r)) next
  results[[cn]] <- r
  leaderboard <- rbind(leaderboard, data.table(
    cycle = cn,
    n_feat = CYCLES[[cn]]$n_feat,
    hparams = CYCLES[[cn]]$hparams,
    status = CYCLES[[cn]]$status,
    direct_us_fred_dep = CYCLES[[cn]]$direct_us_fred_dep,
    indirect_bbva_init_claims_dep = CYCLES[[cn]]$indirect_bbva_init_claims_dep,
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
# Divergence diagnosis (BUGGY vs FIXED) for 53H_v5e + 53I_v5f
# -----------------------------------------------------------------------------
cat("\n", rep("=", 70), "\n", sep="")
cat("[Divergence diagnosis] BUGGY 56A vs FIXED 57A (FRED publication-lag impact)\n")
cat(rep("=", 70), "\n", sep="")

buggy_results <- list()
for (cn in names(CYCLES_BUGGY)) {
  cat("\n[BUGGY ", cn, "]\n", sep="")
  r <- aggregate_cycle(cn, CYCLES_BUGGY[[cn]])
  if (!is.null(r)) buggy_results[[cn]] <- r
}

divergence <- data.table()
for (pair in list(
  list(buggy = "53H_v5e_BUGGY", fixed = "53H_v5e_FIXED"),
  list(buggy = "53I_v5f_BUGGY", fixed = "53I_v5f_FIXED")
)) {
  if (is.null(buggy_results[[pair$buggy]]) || is.null(results[[pair$fixed]])) next
  b <- buggy_results[[pair$buggy]]
  f <- results[[pair$fixed]]
  d <- f$mean5_pr_auc - b$mean5_pr_auc
  divergence <- rbind(divergence, data.table(
    pair_name = sprintf("%s vs %s", pair$buggy, pair$fixed),
    buggy_mean5_pr = round(b$mean5_pr_auc, 4),
    fixed_mean5_pr = round(f$mean5_pr_auc, 4),
    diff_pr = round(d, 4),
    diff_sign = if (d > 0) "fixed > buggy (good news — lookahead was suppressing model)" else if (d < 0) "fixed < buggy (fix removed inflated signal, true OOS reveal)" else "tie"
  ))
  cat(sprintf("\n  %s vs %s: BUGGY=%.4f FIXED=%.4f Δ=%+.4f\n",
              pair$buggy, pair$fixed, b$mean5_pr_auc, f$mean5_pr_auc, d))
}

# -----------------------------------------------------------------------------
# Leaderboard with reference baselines
# -----------------------------------------------------------------------------
cat("\n", rep("=", 70), "\n", sep="")
cat("[Cycle 57A q15 FIXED LEADERBOARD]\n")
cat(rep("=", 70), "\n", sep="")
setorder(leaderboard, -mean5_pr_auc)
print(leaderboard)

# Reference baselines (Cycle 50/43/52, q15 forward post-bug-fix)
# Codex Q3c (2026-05-21) correction: previous 0.1581 was Cycle 45B v3b_inst M3_Hedge, NOT v1.3 C50.
# True v1.3 C50 q15 = 6-method dynamic mean 0.1643 (range 0.1450~0.1917)
# (source: cycle50_rebaseline_summary.json + v1_3_rebaseline_forward.json)
ref_baselines <- data.table(
  cycle = c("v1.3_C50_6method_dyn_mean", "v2_2feat_C43_best_forward", "v4a_C52_mean5"),
  n_feat = c(69, 71, 70),
  mean5_pr_auc = c(0.1643, 0.2129, 0.2463),
  status = "historical_reference_q15"
)
cat("\n[Reference baselines (historical, q15)]:\n")
print(ref_baselines)

# Write leaderboard
fwrite(leaderboard, file.path(EVAL, "cycle57a_q15_FRED_fixed_leaderboard.csv"))
cat("\n[Saved] ", file.path(EVAL, "cycle57a_q15_FRED_fixed_leaderboard.csv"), "\n", sep="")

# Headline candidate
best <- leaderboard[1]
headline <- sprintf(
  "Cycle 57A FIXED q15 forward best: %s (mean5 PR-AUC=%.4f, n_feat=%d, status=%s)",
  best$cycle, best$mean5_pr_auc, best$n_feat, best$status
)
cat("\n[HEADLINE]", headline, "\n")

# JSON
json_payload <- list(
  cycle = "57A_FRED_publication_lag_FIXED_q15",
  target = "y_tail_q15",
  target_horizon_days = 21L,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  n_cycles = nrow(leaderboard),
  seeds = SEEDS,
  pit_fixes = list(
    bug_1_purged_kfold_cv = "np.busday_offset(dates, 21, roll='forward') < valid_start (55A inherit)",
    bug_2_y_valid_mask = "ret_q15.notna() (55A inherit)",
    M6_phantom0_guard = "targets_long_horizon_observable.parquet (54D inherit)",
    M7_direct_us_pub_lag_FIXED = "FRED CFNAI +55d (MM-START dating, release ~25d post month-END) / ICSA +5d (Sat-dated to Thu release) — applied to direct us_* FRED features (57A Phase 1)",
    M7_indirect_bbva_dep_NOT_addressed = list(
      scope = "out_of_cycle_57A_scope",
      issue = "v1.3/v4a base panels inherit BBVA macro features (bbva_market_z etc.) from A6_bbva_macro_builder.R using fred_macro_wide.parquet Init_Claims (~5d ICSA lag bug). Affects all 5 cycles including retained 53B/54A.",
      mitigation_estimate = "Codex 55B Q2 estimate < 0.01 PR-AUC impact at q15 (Init_Claims used in BBVA composite z-score = diluted signal).",
      followup = "Cycle 57A_followup: rebuild fred_macro_wide via 95-style pub-lag fix + rebuild A6 BBVA + rebuild v1.3/v4a + retrain ALL 5 cycles. Deferred per Forge agent autonomous mandate scope."
    )
  ),
  approach = "DIRECT US FRED LAG FIX ONLY. Substitute 53H_v5e + 53I_v5f with FRED publication-lag fixed retrain (direct us_* features). Retain 53B/54A (no direct us_* FRED) but disclose indirect BBVA-derived ICSA contamination remains.",
  codex_review_concerns_addressed = list(
    Q1_publication_lag = "PASS (no fix needed)",
    Q2_pit_integrity = "PASS_WITH_NIT (sanity check still print-only; future: add stopifnot)",
    Q3a_retain_classification = "FIXED: relabeled as 'no_direct_us_FRED' with explicit indirect_bbva_init_claims_dep=TRUE flag",
    Q3b_v4a_inheritance = "DISCLOSED: v4a still carries BBVA Init_Claims contamination — out of 57A scope",
    Q3c_baseline_misattribution = "FIXED: 0.1581 (45B v3b_inst M3_Hedge) → 0.1643 (v1.3 C50 6-method dynamic mean)"
  ),
  leaderboard = leaderboard,
  divergence_diagnosis = divergence,
  reference_baselines = ref_baselines,
  headline = headline,
  per_cycle_detail = lapply(names(results), function(cn) {
    r <- results[[cn]]
    list(
      cycle = cn,
      n_feat = r$cfg$n_feat,
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
                     file.path(EVAL, "cycle57a_q15_FRED_fixed.json"),
                     pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("[Saved] ", file.path(EVAL, "cycle57a_q15_FRED_fixed.json"), "\n", sep="")

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
lb_long[, fred_status := ifelse(direct_us_fred_dep, "Direct US FRED FIXED", "v4a base (no direct US FRED)")]

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
  labs(title = "Cycle 57A — strict-PIT q15 DIRECT US FRED publication-lag FIXED (BBVA-indirect remains)",
       subtitle = "FRED CFNAI +55d (MM-START dating, release ~25d post MM-end) / ICSA +5d (Sat→Thu) — direct us_* features only",
       x = NULL, y = "PR-AUC", fill = NULL,
       caption = "BBVA-derived ICSA bug remains in v4a base panel (53B/54A) — see 57A_followup deferred work") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom",
        plot.title = element_text(face = "bold"),
        axis.text.x = element_text(face = "bold"))

ggsave(file.path(CHARTS, "177_q15_FRED_fixed_leaderboard.png"),
       p, width = 12, height = 7, dpi = 120, bg = "white")
cat("[Saved] ", file.path(CHARTS, "177_q15_FRED_fixed_leaderboard.png"), "\n", sep="")

cat("\n[Cycle 57A q15 FIXED DONE]\n")
