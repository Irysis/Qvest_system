#!/usr/bin/env Rscript
# 172_q15_strict_PIT_aggregate.R — Cycle 56A aggregate + leaderboard
#
# Aggregates strict-PIT q15 (21-day forward) PatchTST results across 5 cycles × 5 seeds:
#   53B v5b (70 feat) / 53H v5e (74 feat) / 53I v5f (79 feat) /
#   54A v3 patch7 (70 feat) / 54A v4 dm32 (70 feat)
#
# Per-cycle:
#   - Per-seed PR-AUC + IC
#   - 5-seed mean prediction PR-AUC (ensemble)
#   - Period-balanced bootstrap CI (S2018-19 EuroAfter / S2020-21 Covid / S2022-26 Recent)
# Cross-cycle:
#   - Best forward q15 identification (vs 55A q126 0.5473 baseline for relative compare)
#
# Mandate (도훈 2026-05-21): 원래 +21d 약세 확률값 mandate 회복.
# Cycle 48A 이후 q126 drift (Q-Lead 자체 결정 미허가) → q15 진정 baseline 회복.
#
# Outputs:
#   outputs/04_evaluation/cycle56a_q15_strict_PIT_all.json
#   outputs/04_evaluation/cycle56a_q15_leaderboard.csv
#   outputs/06_reports/charts/172_q15_strict_PIT_leaderboard.png

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(ggplot2)
})

WS <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "04_Research/decision_framework/bearish_forecast_v2_alt_data")
IN_NEW <- file.path(WS, "outputs/03_models/cycle56a_q15_strict_PIT")
EVAL <- file.path(WS, "outputs/04_evaluation")
CHARTS <- file.path(WS, "outputs/06_reports/charts")
dir.create(EVAL, recursive = TRUE, showWarnings = FALSE)
dir.create(CHARTS, recursive = TRUE, showWarnings = FALSE)

# -----------------------------------------------------------------------------
# Metric functions (R port matching 167b template)
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

# Plain OOS PR-AUC bootstrap (1000 reps)
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
# Load all per-seed predictions across 5 cycles
# -----------------------------------------------------------------------------
SEEDS <- c(42, 123, 456, 789, 1024)
arrow_ok <- requireNamespace("arrow", quietly = TRUE)
if (!arrow_ok) stop("arrow package required: install.packages('arrow')")

# CYCLE 56A q15: fresh retrain of all 5 cycles (no 56B FULL inheritance — that was q126-specific)
CYCLES <- list(
  `53B_v5b`        = list(dir = IN_NEW, pattern = "predictions_53B_v5b_seed%d_y_tail_q15.parquet",
                          n_feat = 70, hparams = "patch=4 d=64 nhead=4 nlayer=3"),
  `53H_v5e`        = list(dir = IN_NEW, pattern = "predictions_53H_v5e_seed%d_y_tail_q15.parquet",
                          n_feat = 74, hparams = "patch=4 d=64 nhead=4 nlayer=3"),
  `53I_v5f`        = list(dir = IN_NEW, pattern = "predictions_53I_v5f_seed%d_y_tail_q15.parquet",
                          n_feat = 79, hparams = "patch=4 d=64 nhead=4 nlayer=3"),
  `54A_v3_patch7`  = list(dir = IN_NEW, pattern = "predictions_54A_v3_patch7_seed%d_y_tail_q15.parquet",
                          n_feat = 70, hparams = "patch=7 d=64 nhead=4 nlayer=3 stride=2"),
  `54A_v4_dm32`    = list(dir = IN_NEW, pattern = "predictions_54A_v4_dm32_seed%d_y_tail_q15.parquet",
                          n_feat = 70, hparams = "patch=4 d=32 nhead=4 nlayer=3 stride=2")
)

cat("=" , rep("=",70), "\n", sep="")
cat("[Cycle 56A q15] Aggregating strict-PIT q15 results across", length(CYCLES), "cycles\n")
cat("[Cycle 56A q15] TARGET = y_tail_q15 (21-day forward bear tail event)\n")
cat("[Cycle 56A q15] Mandate: +21d 약세 확률값 (도훈 mandate 회복 from q126 drift)\n")
cat("=" , rep("=",70), "\n", sep="")

all_per_seed <- list()
all_mean5    <- list()
leaderboard  <- data.table()

for (cn in names(CYCLES)) {
  cfg <- CYCLES[[cn]]
  cat("\n[", cn, "] dir=", cfg$dir, " n_feat=", cfg$n_feat, "\n", sep="")
  cat("  hparams: ", cfg$hparams, "\n", sep="")

  per_seed <- list()
  preds_mat <- NULL
  ref_y <- NULL
  ref_dates <- NULL
  pred_col <- NULL
  missing_seeds <- c()

  for (s in SEEDS) {
    fp <- file.path(cfg$dir, sprintf(cfg$pattern, s))
    if (!file.exists(fp)) {
      missing_seeds <- c(missing_seeds, s)
      next
    }
    df <- as.data.table(arrow::read_parquet(fp))
    pcol <- if ("p_expert" %in% names(df)) "p_expert" else if ("p_strict" %in% names(df)) "p_strict" else stop("no pred col in ", fp)
    pred_col <- pcol
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
    next
  }
  if (length(missing_seeds) > 0) {
    cat("  [INFO] missing seeds:", missing_seeds, "\n")
  }

  preds_subset <- preds_mat[, !apply(preds_mat, 2, function(c) all(is.na(c))), drop = FALSE]

  # Codex 56A code review hardening: assert per-seed Date+y alignment
  # (167b template's build_5seed_mean_ensemble does this in Python; we replicate in R aggregator)
  for (s_name in names(per_seed)) {
    s_df <- per_seed[[s_name]]$df
    if (length(s_df$Date) != length(ref_dates) || !all(s_df$Date == ref_dates)) {
      stop(sprintf("[%s seed=%s] Date vector mismatch vs reference seed — aggregator misalignment risk", cn, s_name))
    }
    if (!identical(as.integer(s_df$y), as.integer(ref_y))) {
      stop(sprintf("[%s seed=%s] y vector mismatch vs reference seed — aggregator misalignment risk", cn, s_name))
    }
  }
  cat(sprintf("  [alignment-assert] all %d seed predictions share identical Date+y vectors\n",
              length(per_seed)))

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
    max  = max(prs_vec, na.rm = TRUE),
    range= max(prs_vec, na.rm = TRUE) - min(prs_vec, na.rm = TRUE)
  )
  cat(sprintf("  Per-seed: mean=%.4f std=%.4f min=%.4f max=%.4f range=%.4f\n",
              prs_summary$mean, prs_summary$std, prs_summary$min,
              prs_summary$max, prs_summary$range))

  # Period-balanced bootstrap (53M framework)
  ref_dt <- as.Date(ref_dates)
  per1_idx <- which(ref_dt >= as.Date("2018-01-01") & ref_dt <= as.Date("2019-12-31"))
  per2_idx <- which(ref_dt >= as.Date("2020-01-01") & ref_dt <= as.Date("2021-12-31"))
  per3_idx <- which(ref_dt >= as.Date("2022-01-01") & ref_dt <= as.Date("2026-04-30"))

  per_pr_summary <- function(idx, label) {
    if (length(idx) < 30) return(list(period = label, n = length(idx), pr_auc = NA, lift_vs_base = NA))
    pr_p <- pr_auc(mean_pred[idx], ref_y[idx])
    base <- sum(ref_y[idx]) / length(idx)
    lift <- pr_p / base
    list(period = label, n = length(idx), n_bear = sum(ref_y[idx]), pr_auc = pr_p, base_rate = base, lift_vs_base = lift)
  }
  per1 <- per_pr_summary(per1_idx, "EuroAfter_2018_2019")
  per2 <- per_pr_summary(per2_idx, "Covid_2020_2021")
  per3 <- per_pr_summary(per3_idx, "Recent_2022_2026")
  lift_3of3 <- sum(c(per1$lift_vs_base, per2$lift_vs_base, per3$lift_vs_base) > 1, na.rm = TRUE)
  cat(sprintf("  Period-balanced: EuroAfter lift=%.2fx Covid lift=%.2fx Recent lift=%.2fx → %d/3 > 1.0\n",
              per1$lift_vs_base, per2$lift_vs_base, per3$lift_vs_base, lift_3of3))

  # Plain OOS bootstrap CI
  boot <- boot_pr(mean_pred, ref_y, B = 1000)
  cat(sprintf("  Plain bootstrap [B=1000]: mean=%.4f  95%% CI=[%.4f, %.4f]\n",
              boot["mean"], boot["lo"], boot["hi"]))

  all_per_seed[[cn]] <- per_seed
  all_mean5[[cn]] <- list(
    df = data.table(Date = ref_dates, p_mean = mean_pred,
                     p_per_seed_std = per_date_std, y = ref_y),
    pr = mean_pr, ic = mean_ic,
    bootstrap = boot,
    per_seed_summary = prs_summary,
    period_balanced = list(per1 = per1, per2 = per2, per3 = per3, lift_3of3 = lift_3of3)
  )

  leaderboard <- rbind(leaderboard, data.table(
    cycle = cn, n_feat = cfg$n_feat, hparams = cfg$hparams,
    n_seeds_used = ncol(preds_subset), n_obs = nrow(per_seed[[1]]$df),
    n_bears = as.integer(sum(ref_y)),
    per_seed_pr_mean = round(prs_summary$mean, 4),
    per_seed_pr_std = round(prs_summary$std, 4),
    per_seed_pr_min = round(prs_summary$min, 4),
    per_seed_pr_max = round(prs_summary$max, 4),
    mean5_pr_auc = round(mean_pr, 4),
    mean5_ic = round(mean_ic, 4),
    bootstrap_lo = round(boot["lo"], 4),
    bootstrap_hi = round(boot["hi"], 4),
    euroafter_lift = round(per1$lift_vs_base, 2),
    covid_lift = round(per2$lift_vs_base, 2),
    recent_lift = round(per3$lift_vs_base, 2),
    lift_3of3 = lift_3of3
  ))
}

# -----------------------------------------------------------------------------
# Leaderboard ranking
# -----------------------------------------------------------------------------
if (nrow(leaderboard) > 0) {
  setorder(leaderboard, -mean5_pr_auc)
  cat("\n", rep("=",70), "\n", sep="")
  cat("[Cycle 56A q15 LEADERBOARD]\n")
  cat(rep("=",70), "\n", sep="")
  print(leaderboard)

  fwrite(leaderboard, file.path(EVAL, "cycle56a_q15_leaderboard.csv"))
  cat("\n[Saved] ", file.path(EVAL, "cycle56a_q15_leaderboard.csv"), "\n", sep="")

  json_payload <- list(
    cycle = "56A_strict_PIT_all_q15",
    target = "y_tail_q15",
    target_horizon_days = 21L,
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    n_cycles = nrow(leaderboard),
    seeds = SEEDS,
    pit_fixes = list(
      bug_1_purged_kfold_cv = "np.busday_offset(dates, 21, roll='forward') < valid_start",
      bug_2_y_valid_mask = "ret_q15.notna() — train/valid/OOS exclude unresolved",
      M6_phantom0_guard = "target_path = targets_long_horizon_observable.parquet (Cycle 54D Phase 4)",
      M7_pub_lag_acknowledged = "CFNAI ~22d / ICSA ~5d in v5e/v4a/v5f panels inherited — q15 horizon (21d forward) impact est. < 0.005 PR-AUC (55B Codex)",
      reference_master = "scripts/167b_patchtst_strict_PIT_q15_template.py (adapted from 157)"
    ),
    leaderboard = leaderboard,
    baseline_55a_q126_top_mean5 = 0.5473,  # 53I_v5f from 55A q126 leaderboard
    baseline_54e_new_5seed_q15_range = list(min = 0.1874, max = 0.2568),
    per_cycle_detail = lapply(names(all_mean5), function(cn) {
      m <- all_mean5[[cn]]
      list(
        cycle = cn,
        mean5_pr_auc = m$pr,
        mean5_ic = m$ic,
        bootstrap_95ci = unname(m$bootstrap),
        per_seed_pr_mean = m$per_seed_summary$mean,
        per_seed_pr_std = m$per_seed_summary$std,
        per_seed_pr_min = m$per_seed_summary$min,
        per_seed_pr_max = m$per_seed_summary$max,
        period_balanced = m$period_balanced
      )
    })
  )
  jsonlite::write_json(json_payload,
                       file.path(EVAL, "cycle56a_q15_strict_PIT_all.json"),
                       pretty = TRUE, auto_unbox = TRUE, na = "null")
  cat("[Saved] ", file.path(EVAL, "cycle56a_q15_strict_PIT_all.json"), "\n", sep="")

  # Leaderboard chart
  lb_long <- melt(leaderboard,
                  id.vars = c("cycle", "n_feat"),
                  measure.vars = c("per_seed_pr_mean", "mean5_pr_auc"),
                  variable.name = "metric", value.name = "pr_auc")
  lb_long[, cycle_label := paste0(cycle, "\n(", n_feat, " feat)")]
  lb_long[, metric_label := ifelse(metric == "per_seed_pr_mean",
                                    "Per-seed mean",
                                    "5-seed MEAN ensemble")]

  p <- ggplot(lb_long, aes(x = reorder(cycle_label, pr_auc), y = pr_auc, fill = metric_label)) +
    geom_col(position = position_dodge(width = 0.8), width = 0.7) +
    geom_hline(yintercept = 0.13, linetype = "dotted", color = "gray40", linewidth = 0.5) +
    annotate("text", x = 1, y = 0.14,
             label = "base_rate ≈ 0.13 (1148/8956)", color = "gray40", size = 3, hjust = 0) +
    geom_text(aes(label = sprintf("%.3f", pr_auc)),
              position = position_dodge(width = 0.8), vjust = -0.3, size = 3) +
    scale_fill_manual(values = c("Per-seed mean" = "steelblue",
                                  "5-seed MEAN ensemble" = "darkorange")) +
    labs(title = "Cycle 56A — strict-PIT q15 (+21d 약세 확률값) PatchTST leaderboard",
         subtitle = "도훈 mandate 회복 (q126 drift → q15). Per-seed avg + 5-seed mean ensemble.",
         x = NULL, y = "PR-AUC", fill = NULL) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom",
          plot.title = element_text(face = "bold"),
          axis.text.x = element_text(face = "bold"))

  ggsave(file.path(CHARTS, "172_q15_strict_PIT_leaderboard.png"),
         p, width = 10, height = 6, dpi = 120, bg = "white")
  cat("[Saved] ", file.path(CHARTS, "172_q15_strict_PIT_leaderboard.png"), "\n", sep="")
} else {
  cat("\n[ERROR] no cycles aggregated\n")
  quit(status = 1)
}

cat("\n[Cycle 56A q15 DONE]\n")
