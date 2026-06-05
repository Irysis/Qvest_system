#!/usr/bin/env Rscript
# 189_q15_cross_market_aggregate.R — Cycle 58B Phase 4: aggregate + leaderboard
#
# Mandate (도훈 2026-05-21):
#   Cross-market features (7 new) added on top of v5f_FIXED2 base (79 features).
#   Compare v5g_cross_market (86 features) vs Cycle 57A 53I_v5f_FIXED baseline (79 feat, mean5 PR-AUC 0.2382).
#
# Verdict thresholds:
#   - ADDITIVE_STRONG: Δ PR-AUC ≥ +0.02 vs 53I_v5f_FIXED baseline (0.2382 → 0.258+)
#   - ADDITIVE_WEAK  : 0 < Δ < +0.02 (marginal)
#   - NEUTRAL        : -0.005 ≤ Δ ≤ +0.005 (within noise)
#   - DILUTION       : Δ < -0.005 (cross-market noise hurts)
#
# Code: XGB importance ranking + correlation matrix vs existing features
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(arrow)
  has_xgb <- requireNamespace("xgboost", quietly = TRUE)
  if (!has_xgb) cat("[NOTE] xgboost not installed — XGB importance will be skipped\n")
})

WS <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "04_Research/decision_framework/bearish_forecast_v2_alt_data")
IN_V5G  <- file.path(WS, "outputs/03_models/cycle58b_v5g_q15")
IN_57A  <- file.path(WS, "outputs/03_models/cycle57a_q15_FRED_fixed")
EVAL    <- file.path(WS, "outputs/04_evaluation")
CHARTS  <- file.path(WS, "outputs/06_reports/charts")
dir.create(EVAL, recursive = TRUE, showWarnings = FALSE)
dir.create(CHARTS, recursive = TRUE, showWarnings = FALSE)

SEEDS <- c(42, 123, 456, 789, 1024)

# Metric functions (identical to 177_q15_FRED_fixed_aggregate.R)
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

# -----------------------------------------------------------------------------
# Cycle definitions
# -----------------------------------------------------------------------------
CYCLES <- list(
  `53I_v5g_cross_market` = list(dir = IN_V5G, pattern = "predictions_53I_v5g_cross_market_seed%d_y_tail_q15.parquet",
                                 n_feat = 86, hparams = "patch=4 d=64 nhead=4 nlayer=3",
                                 cross_market_added = TRUE,
                                 status = "NEW_v5g_v5f_FIXED2_plus_7_cross_market_features_PIT_safe_lag1"),
  `53I_v5f_FIXED_57A`    = list(dir = IN_57A, pattern = "predictions_53I_v5f_FIXED_seed%d_y_tail_q15.parquet",
                                 n_feat = 79, hparams = "patch=4 d=64 nhead=4 nlayer=3",
                                 cross_market_added = FALSE,
                                 status = "BASELINE_57A_53I_v5f_FIXED_no_cross_market")
)

cat(rep("=", 70), "\n", sep="")
cat("[Cycle 58B Phase 4] v5g_cross_market vs baseline 53I_v5f_FIXED q15\n")
cat("[Cycle 58B Phase 4] TARGET = y_tail_q15 (21-day forward bear tail event)\n")
cat("[Cycle 58B Phase 4] Compare 86 features (v5g) vs 79 features (baseline 57A)\n")
cat(rep("=", 70), "\n", sep="")

aggregate_cycle <- function(cn, cfg) {
  cat("\n[", cn, "] status=", cfg$status, "\n", sep="")
  per_seed <- list(); preds_mat <- NULL; ref_y <- NULL; ref_dates <- NULL; missing_seeds <- c()
  for (s in SEEDS) {
    fp <- file.path(cfg$dir, sprintf(cfg$pattern, s))
    if (!file.exists(fp)) {
      missing_seeds <- c(missing_seeds, s); next
    }
    df <- as.data.table(arrow::read_parquet(fp))
    pcol <- if ("p_expert" %in% names(df)) "p_expert" else if ("p_strict" %in% names(df)) "p_strict" else stop("no pred col in ", fp)
    pr <- pr_auc(df[[pcol]], df$y); ic <- ic_spearman(df[[pcol]], df$y)
    cat(sprintf("  seed=%d: n=%d bears=%d PR-AUC=%.4f IC=%.4f\n",
                s, nrow(df), as.integer(sum(df$y)), pr, ic))
    per_seed[[as.character(s)]] <- list(df = df, pr = pr, ic = ic)
    if (is.null(ref_y)) {
      ref_y <- df$y; ref_dates <- df$Date
      preds_mat <- matrix(NA_real_, nrow = nrow(df), ncol = length(SEEDS))
    } else {
      # CODEX C2 FIX (2026-05-21): assert identical Date + y alignment across seeds
      if (nrow(df) != length(ref_y)) stop(sprintf("seed %d row count %d != ref %d", s, nrow(df), length(ref_y)))
      if (!identical(as.character(df$Date), as.character(ref_dates))) stop(sprintf("seed %d Date misalignment vs ref", s))
      if (any(df$y != ref_y, na.rm = TRUE)) stop(sprintf("seed %d y misalignment vs ref", s))
    }
    preds_mat[, which(SEEDS == s)] <- df[[pcol]]
  }
  if (length(per_seed) == 0) {
    cat("  [WARN] no seeds — SKIPPED\n"); return(NULL)
  }
  if (length(missing_seeds) > 0) {
    cat("  [INFO] missing seeds:", missing_seeds, "\n")
    # CODEX C2 FIX: warn loudly + record but continue (caller decides)
    cat(sprintf("  [WARN] CYCLE %s has only %d/%d seeds — mean5 ensemble below canonical 5-seed mean\n",
                cn, length(per_seed), length(SEEDS)))
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

  list(per_seed = per_seed, mean5_pr_auc = mean_pr, mean5_ic = mean_ic,
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
    cycle = cn, n_feat = CYCLES[[cn]]$n_feat, hparams = CYCLES[[cn]]$hparams,
    status = CYCLES[[cn]]$status, cross_market_added = CYCLES[[cn]]$cross_market_added,
    per_seed_pr_mean = round(r$per_seed_summary$mean, 4),
    per_seed_pr_std  = round(r$per_seed_summary$std, 4),
    per_seed_pr_min  = round(r$per_seed_summary$min, 4),
    per_seed_pr_max  = round(r$per_seed_summary$max, 4),
    mean5_pr_auc = round(r$mean5_pr_auc, 4), mean5_ic = round(r$mean5_ic, 4),
    bootstrap_lo = round(r$bootstrap["lo"], 4), bootstrap_hi = round(r$bootstrap["hi"], 4),
    euroafter_lift = round(r$period_balanced$per1$lift_vs_base, 2),
    covid_lift = round(r$period_balanced$per2$lift_vs_base, 2),
    recent_lift = round(r$period_balanced$per3$lift_vs_base, 2),
    lift_3of3 = r$period_balanced$lift_3of3
  ))
}

# -----------------------------------------------------------------------------
# Verdict
# -----------------------------------------------------------------------------
verdict <- list(class = "UNKNOWN", delta_pr_auc = NA_real_)
if (!is.null(results[["53I_v5g_cross_market"]]) && !is.null(results[["53I_v5f_FIXED_57A"]])) {
  v5g_pr <- results[["53I_v5g_cross_market"]]$mean5_pr_auc
  base_pr <- results[["53I_v5f_FIXED_57A"]]$mean5_pr_auc
  delta <- v5g_pr - base_pr
  verdict$delta_pr_auc <- round(delta, 4)
  verdict$v5g_pr_auc <- round(v5g_pr, 4)
  verdict$baseline_pr_auc <- round(base_pr, 4)
  verdict$class <- if (delta >= 0.02) "ADDITIVE_STRONG"
              else if (delta > 0)     "ADDITIVE_WEAK"
              else if (delta >= -0.005) "NEUTRAL"
              else                    "DILUTION"
  cat(sprintf("\n[VERDICT] v5g_cross_market PR-AUC=%.4f vs baseline %.4f Δ=%+.4f → %s\n",
              v5g_pr, base_pr, delta, verdict$class))
}

# -----------------------------------------------------------------------------
# XGB feature importance (top 30) on v5g panel — verify cross-market features rank
# -----------------------------------------------------------------------------
xgb_imp <- NULL
if (has_xgb) {
  cat("\n[XGB Importance] Training XGBoost on v5g_cross_market for feature importance...\n")
  panel <- as.data.table(arrow::read_parquet(file.path(WS, "outputs/01_data/feature_panel_v5g_cross_market.parquet")))
  tgt <- as.data.table(arrow::read_parquet(file.path(WS, "outputs/02_targets/targets_long_horizon_observable.parquet")))
  # CODEX C4 FIX (post-debug): panel Date is POSIXct (KST timestamp), tgt Date is Date class.
  # Coerce BOTH to as.Date BEFORE merge, otherwise merge produces all-NA on ret_q15.
  panel[, Date := as.Date(Date)]
  tgt[, Date := as.Date(Date)]
  m <- merge(panel, tgt[, .(Date, y_tail_q15, ret_q15)], by = "Date", all.x = TRUE)
  m <- m[!is.na(ret_q15) & !is.na(y_tail_q15)]
  m <- m[Date >= as.Date("2018-01-01") & Date <= as.Date("2026-04-30")]
  feat_cols <- setdiff(names(m), c("Date", "y_tail_q15", "ret_q15"))
  # CODEX C5 FIX: force contiguous double matrix (xgboost pointer alignment)
  X_df <- as.data.frame(m[, ..feat_cols])
  for (cc in names(X_df)) X_df[[cc]] <- as.numeric(X_df[[cc]])
  X_mat <- as.matrix(X_df)
  storage.mode(X_mat) <- "double"
  X_mat[is.na(X_mat)] <- 0.0
  y_vec <- as.numeric(m$y_tail_q15)
  cat(sprintf("  XGB train: n=%d positives=%d features=%d\n", nrow(X_mat), sum(y_vec == 1), ncol(X_mat)))
  set.seed(42)
  dtrain <- xgboost::xgb.DMatrix(data = X_mat, label = y_vec)
  bst <- xgboost::xgb.train(
    params = list(objective = "binary:logistic", eval_metric = "aucpr",
                  max_depth = 4, eta = 0.1, subsample = 0.7, colsample_bytree = 0.7,
                  scale_pos_weight = sum(y_vec == 0) / max(sum(y_vec == 1), 1)),
    data = dtrain, nrounds = 200, verbose = 0
  )
  imp <- xgboost::xgb.importance(model = bst)
  xgb_imp <- imp
  cat("\n[XGB Importance — Top 30]:\n")
  print(imp[1:min(30, nrow(imp))])
  fwrite(imp, file.path(EVAL, "cycle58b_v5g_xgb_importance.csv"))
  # Highlight cross-market features
  cross_market_names <- c("nikkei225_return_lag1", "sp500_overnight_return_lag1",
                          "dxy_change_5d_lag1", "usdkrw_change_5d_lag1",
                          "hangseng_return_lag1", "wti_change_5d_lag1", "vix_change_5d_lag1")
  cm_in_imp <- imp[Feature %in% cross_market_names]
  cm_in_imp[, rank := match(Feature, imp$Feature)]
  cat("\n[Cross-market features in XGB importance]:\n")
  print(cm_in_imp[, .(Feature, Gain = round(Gain, 5), Cover = round(Cover, 5), Frequency = round(Frequency, 5), rank)])
}

# -----------------------------------------------------------------------------
# Save final JSON + leaderboard
# -----------------------------------------------------------------------------
cat("\n", rep("=", 70), "\n", sep="")
cat("[Cycle 58B q15 cross-market LEADERBOARD]\n")
cat(rep("=", 70), "\n", sep="")
setorder(leaderboard, -mean5_pr_auc)
print(leaderboard)

fwrite(leaderboard, file.path(EVAL, "cycle58b_v5g_q15_leaderboard.csv"))

# Bear date check — compare predictions on known bear dates (Lehman/Euro/Covid/Recent)
bear_check <- NULL
if (!is.null(results[["53I_v5g_cross_market"]])) {
  r <- results[["53I_v5g_cross_market"]]
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
  cat("\n[Bear date prediction check (v5g):]\n")
  for (k in names(bear_check)) {
    bc <- bear_check[[k]]
    if (is.null(bc$pred_in_window)) cat(sprintf("  %s (%s): no window\n", k, bc$date))
    else cat(sprintf("  %s (%s): max pred=%.4f y=%d\n", k, bc$date, bc$pred_in_window, bc$y_in_window))
  }
}

# Combine final
out_json <- list(
  cycle = "58B_q15_cross_market",
  script = "189_q15_cross_market_aggregate.R",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  target = "y_tail_q15", target_horizon_days = 21,
  baseline_comparison = list(
    baseline_cycle = "53I_v5f_FIXED_57A",
    baseline_mean5_pr_auc = if (!is.null(results[["53I_v5f_FIXED_57A"]])) results[["53I_v5f_FIXED_57A"]]$mean5_pr_auc else 0.2382,
    new_cycle = "53I_v5g_cross_market",
    new_mean5_pr_auc = if (!is.null(results[["53I_v5g_cross_market"]])) results[["53I_v5g_cross_market"]]$mean5_pr_auc else NA,
    verdict = verdict
  ),
  leaderboard = leaderboard,
  per_cycle = lapply(results, function(r) {
    list(mean5_pr_auc = round(r$mean5_pr_auc, 4), mean5_ic = round(r$mean5_ic, 4),
         per_seed_summary = lapply(r$per_seed_summary, function(x) round(x, 4)),
         bootstrap = round(r$bootstrap, 4),
         period_balanced = r$period_balanced,
         per_seed_pr = sapply(r$per_seed, function(p) round(p$pr, 4)),
         per_seed_ic = sapply(r$per_seed, function(p) round(p$ic, 4)))
  }),
  bear_date_check = bear_check,
  xgb_importance_top30 = if (!is.null(xgb_imp)) head(xgb_imp, 30) else NULL,
  cross_market_features = c("nikkei225_return_lag1", "sp500_overnight_return_lag1",
                            "dxy_change_5d_lag1", "usdkrw_change_5d_lag1",
                            "hangseng_return_lag1", "wti_change_5d_lag1", "vix_change_5d_lag1"),
  reference_baselines_q15 = list(
    v1_3_C50_6method_dyn_mean = 0.1643,
    v2_2feat_C43_best_forward = 0.2129,
    v4a_C52_mean5             = 0.2463,
    cycle56a_53I_v5f_mean5    = 0.2356,
    cycle57a_53I_v5f_FIXED    = 0.2382))

write_json(out_json, file.path(EVAL, "cycle58b_v5g_q15.json"))

# Chart
if (requireNamespace("ggplot2", quietly = TRUE)) {
  library(ggplot2)
  lb2 <- copy(leaderboard)
  lb2[, label := paste0(cycle, "\n(n_feat=", n_feat, ")")]
  p <- ggplot(lb2, aes(x = reorder(label, mean5_pr_auc), y = mean5_pr_auc, fill = cross_market_added)) +
    geom_bar(stat = "identity") +
    geom_errorbar(aes(ymin = bootstrap_lo, ymax = bootstrap_hi), width = 0.2) +
    geom_text(aes(label = sprintf("%.4f", mean5_pr_auc)), vjust = -0.5, size = 4) +
    coord_flip() +
    labs(title = "Cycle 58B v5g_cross_market q15 (PatchTST 5-seed mean)",
         subtitle = sprintf("Baseline 57A 53I_v5f_FIXED PR-AUC=0.2382 | Verdict: %s", verdict$class),
         x = "Cycle", y = "Mean5 PR-AUC (q15 OOS 2018-2026)") +
    theme_minimal(base_size = 12)
  ggsave(file.path(CHARTS, "189_v5g_q15_cross_market.png"), p, width = 10, height = 6, dpi = 120)
  cat(sprintf("\n[saved chart] %s\n", file.path(CHARTS, "189_v5g_q15_cross_market.png")))
}

cat(sprintf("\n[saved] %s\n", file.path(EVAL, "cycle58b_v5g_q15.json")))
cat(sprintf("[saved] %s\n", file.path(EVAL, "cycle58b_v5g_q15_leaderboard.csv")))
cat("\n[DONE] Phase 4 complete.\n")
