#==============================================================================
# 106_5way_aggregate_v3g_horizon_swap.R — Cycle 48A Step 4-7
#
# Steps:
#   Step 4: 5-way merge per target (XGB + Cat + RF + LSTM + TFT)
#   Step 5: Dynamic 5-method ensemble (M1~M5) per target
#   Step 6: Compare across horizons (q15 vs q63 vs q126) + vs 47B
#   Step 7: JSON + 3-panel PR curve chart
#
# Mirror: scripts/98_5way_aggregate_v3f_us_macro.R — fully replicated, but
# loops over 3 targets and produces consolidated comparison.
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2);
  library(patchwork)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
V3G_DIR <- file.path(WS, "outputs/03_models/v3g_horizon_swap")
BASE_DYN_DIR <- file.path(WS, "outputs/03_models/dynamic_ensemble")
V3F_DIR <- file.path(WS, "outputs/03_models/v3f_us_macro")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

dir.create(V3G_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)
set.seed(42)

LOOKBACK <- 252; PURGE <- 21

pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}
softmax <- function(x, beta = 5) { e <- exp(x * beta - max(x * beta)); e / sum(e) }
pr_curve <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  data.table(recall = rec, precision = prec)
}

#==============================================================================
# Step 4: 5-way merge per target
#==============================================================================
cat("\n========== Step 4: 5-way merge per target ==========\n")

make_5way <- function(target_col) {
  cat(sprintf("\n----- 5-way merge: %s -----\n", target_col))
  gbdt <- as.data.table(read_parquet(file.path(V3G_DIR, sprintf("predictions_3way_%s.parquet", target_col))))
  gbdt[, Date := as.Date(Date)]
  lstm <- as.data.table(read_parquet(file.path(V3G_DIR, sprintf("predictions_lstm_%s.parquet", target_col))))
  lstm[, Date := as.Date(Date)]
  tft <- as.data.table(read_parquet(file.path(V3G_DIR, sprintf("predictions_tft_%s.parquet", target_col))))
  tft[, Date := as.Date(Date)]

  oos_gbdt <- gbdt[split == "oos", .(Date, p_xgb, p_cat, p_rf, y)]
  oos <- merge(oos_gbdt, lstm[, .(Date, p_lstm)], by = "Date", all = TRUE)
  oos <- merge(oos, tft[, .(Date, p_tft)], by = "Date", all = TRUE)
  # Trim NA target rows (trailing forward-unavailable)
  oos <- oos[!is.na(y) & !is.na(p_xgb) & !is.na(p_lstm) & !is.na(p_tft)]
  cat(sprintf("[merge] OOS N=%d / events=%d (%.2f%%)\n",
              nrow(oos), sum(oos$y), 100 * mean(oos$y)))

  pr_xgb <- pr_auc(oos$p_xgb, oos$y); pr_cat <- pr_auc(oos$p_cat, oos$y)
  pr_rf <- pr_auc(oos$p_rf, oos$y); pr_lstm <- pr_auc(oos$p_lstm, oos$y); pr_tft <- pr_auc(oos$p_tft, oos$y)
  cat(sprintf("[individual OOS PR-AUC] XGB=%.4f / CAT=%.4f / RF=%.4f / LSTM=%.4f / TFT=%.4f\n",
              pr_xgb, pr_cat, pr_rf, pr_lstm, pr_tft))

  oos[, p_ew5 := (p_xgb + p_cat + p_rf + p_lstm + p_tft) / 5]
  oos[, p_wew := 0.25 * p_xgb + 0.25 * p_cat + 0.25 * p_rf + 0.125 * p_lstm + 0.125 * p_tft]
  pr_ew5 <- pr_auc(oos$p_ew5, oos$y); pr_wew <- pr_auc(oos$p_wew, oos$y)
  cat(sprintf("[ensemble] EW5=%.4f / WEW=%.4f\n", pr_ew5, pr_wew))

  write_parquet(oos, file.path(V3G_DIR, sprintf("predictions_5way_%s.parquet", target_col)))
  list(individual = list(xgb=pr_xgb, cat=pr_cat, rf=pr_rf, lstm=pr_lstm, tft=pr_tft),
       ew5 = pr_ew5, wew = pr_wew, oos = oos,
       n_oos = nrow(oos), event_rate = mean(oos$y))
}

res_5w <- list(
  y_tail_q15  = make_5way("y_tail_q15"),
  y_tail_q63  = make_5way("y_tail_q63"),
  y_tail_q126 = make_5way("y_tail_q126")
)

#==============================================================================
# Step 5: Dynamic 5-method synthesis per target
#==============================================================================
cat("\n========== Step 5: Dynamic 5-method ensemble synthesis ==========\n")

# bbva_macro_composite regime — load once
feat <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v3f_us_macro.parquet")))
feat[, Date := as.Date(Date)]

run_dynamic <- function(target_col, oos_in) {
  cat(sprintf("\n----- Dynamic 5-method: %s -----\n", target_col))
  p5 <- copy(oos_in); setorder(p5, Date); n_total <- nrow(p5)
  M_NAMES <- c("p_xgb", "p_cat", "p_rf", "p_lstm", "p_tft")
  M <- as.matrix(p5[, ..M_NAMES]); Y <- p5$y

  w_static <- c(0.25, 0.25, 0.25, 0.125, 0.125)
  p_static <- as.numeric(M %*% w_static)
  pa_static <- pr_auc(p_static, Y)
  cat(sprintf("[Static WEW] PR-AUC=%.4f\n", pa_static))

  # M1 Rolling Adaptive
  p_M1 <- rep(NA_real_, n_total)
  for (i in seq_len(n_total)) {
    cutoff <- i - PURGE; start <- cutoff - LOOKBACK + 1
    if (start < 1) next
    p_w <- M[start:cutoff, , drop = FALSE]; y_w <- Y[start:cutoff]
    pr_m <- sapply(seq_len(5), function(m) pr_auc(p_w[, m], y_w))
    pr_m[is.na(pr_m)] <- 0
    w <- softmax(pr_m, beta = 5)
    p_M1[i] <- sum(M[i, ] * w)
  }
  pa_M1 <- pr_auc(p_M1, Y)
  cat(sprintf("[M1 Rolling]  PR-AUC=%.4f %s\n", pa_M1, ifelse(pa_M1 > pa_static, "★", "")))

  # M2 Regime-Conditional
  p5_r <- merge(p5, feat[, .(Date, bbva_macro_composite)], by = "Date", all.x = TRUE)
  setorder(p5_r, Date)
  train_macro <- p5_r$bbva_macro_composite[seq_len(min(2000, n_total))]
  q33 <- quantile(train_macro, 0.33, na.rm = TRUE)
  q67 <- quantile(train_macro, 0.67, na.rm = TRUE)
  p5_r[, regime := fcase(
    is.na(bbva_macro_composite), NA_character_,
    bbva_macro_composite <= q33, "bull",
    bbva_macro_composite >= q67, "bear",
    default = "sideways"
  )]
  M_r <- as.matrix(p5_r[, ..M_NAMES]); Y_r <- p5_r$y; Regime <- p5_r$regime
  p_M2 <- rep(NA_real_, n_total)
  for (i in seq_len(n_total)) {
    cur_reg <- Regime[i]; if (is.na(cur_reg)) next
    cutoff <- i - PURGE; start <- cutoff - LOOKBACK + 1
    if (start < 1) next
    in_reg <- which(Regime[start:cutoff] == cur_reg) + (start - 1)
    if (length(in_reg) < 30) { p_M2[i] <- sum(M_r[i, ] * w_static); next }
    pr_m <- sapply(seq_len(5), function(m) pr_auc(M_r[in_reg, m], Y_r[in_reg]))
    pr_m[is.na(pr_m)] <- 0
    w <- softmax(pr_m, beta = 5)
    p_M2[i] <- sum(M_r[i, ] * w)
  }
  pa_M2 <- pr_auc(p_M2, Y_r)
  cat(sprintf("[M2 Regime]   PR-AUC=%.4f %s\n", pa_M2, ifelse(pa_M2 > pa_static, "★", "")))

  # M3 Hedge
  eta <- 1.0; w_hedge <- rep(1/5, 5); p_M3 <- rep(NA_real_, n_total)
  for (i in seq_len(n_total)) {
    p_M3[i] <- sum(M[i, ] * w_hedge)
    if (!is.na(Y[i])) {
      losses <- (M[i, ] - Y[i])^2
      w_hedge <- w_hedge * exp(-eta * losses); w_hedge <- w_hedge / sum(w_hedge)
    }
  }
  pa_M3 <- pr_auc(p_M3, Y)
  cat(sprintf("[M3 Hedge]    PR-AUC=%.4f %s\n", pa_M3, ifelse(pa_M3 > pa_static, "★", "")))

  # M4 Bayesian
  log_lik <- rep(0, 5); w_bayes <- rep(1/5, 5); p_M4 <- rep(NA_real_, n_total); eps <- 1e-6
  for (i in seq_len(n_total)) {
    p_M4[i] <- sum(M[i, ] * w_bayes)
    if (!is.na(Y[i])) {
      p_clip <- pmax(pmin(M[i, ], 1 - eps), eps)
      log_lik_i <- Y[i] * log(p_clip) + (1 - Y[i]) * log(1 - p_clip)
      log_lik <- log_lik + log_lik_i
      w_bayes <- softmax(log_lik / max(i, 100), beta = 50)
    }
  }
  pa_M4 <- pr_auc(p_M4, Y)
  cat(sprintf("[M4 Bayes]    PR-AUC=%.4f %s\n", pa_M4, ifelse(pa_M4 > pa_static, "★", "")))

  # M5 Bandit
  EPSILON <- 0.1; Q <- matrix(0, nrow = 3, ncol = 5); counts <- matrix(0, nrow = 3, ncol = 5)
  regime_to_idx <- function(r) {
    if (is.na(r)) return(2)
    fcase(r == "bull", 1, r == "sideways", 2, r == "bear", 3, default = 2)
  }
  p_M5 <- rep(NA_real_, n_total)
  for (i in seq_len(n_total)) {
    reg_idx <- regime_to_idx(Regime[i])
    if (runif(1) < EPSILON) chosen <- sample(1:5, 1) else chosen <- which.max(Q[reg_idx, ])
    w_q <- softmax(Q[reg_idx, ], beta = 3)
    p_M5[i] <- sum(M[i, ] * w_q)
    if (!is.na(Y[i])) {
      for (m in seq_len(5)) {
        reward <- -((M[i, m] - Y[i])^2)
        counts[reg_idx, m] <- counts[reg_idx, m] + 1
        Q[reg_idx, m] <- Q[reg_idx, m] + (reward - Q[reg_idx, m]) / counts[reg_idx, m]
      }
    }
  }
  pa_M5 <- pr_auc(p_M5, Y)
  cat(sprintf("[M5 Bandit]   PR-AUC=%.4f %s\n", pa_M5, ifelse(pa_M5 > pa_static, "★", "")))

  out <- p5_r[, .(Date, y, regime,
                  p_static = p_static, p_M1_rolling = p_M1, p_M2_regime = p_M2,
                  p_M3_hedge = p_M3, p_M4_bayes = p_M4, p_M5_bandit = p_M5)]
  write_parquet(out, file.path(V3G_DIR, sprintf("predictions_dynamic_%s.parquet", target_col)))

  data.table(
    target = target_col,
    method = c("Static_WEW", "M1_Rolling", "M2_Regime", "M3_Hedge", "M4_Bayes", "M5_Bandit"),
    PRAUC = c(pa_static, pa_M1, pa_M2, pa_M3, pa_M4, pa_M5)
  )
}

dyn_q15  <- run_dynamic("y_tail_q15",  res_5w$y_tail_q15$oos)
dyn_q63  <- run_dynamic("y_tail_q63",  res_5w$y_tail_q63$oos)
dyn_q126 <- run_dynamic("y_tail_q126", res_5w$y_tail_q126$oos)

cat("\n[Step 5 SUMMARY — Dynamic 5-method PR-AUC × 3 horizons]\n")
all_dyn <- rbind(dyn_q15, dyn_q63, dyn_q126)
print(dcast(all_dyn, method ~ target, value.var = "PRAUC"))

#==============================================================================
# Step 6: Horizon analysis + verdict
#==============================================================================
cat("\n========== Step 6: Horizon analysis + verdict ==========\n")

q15_m2  <- dyn_q15[method == "M2_Regime", PRAUC]
q63_m2  <- dyn_q63[method == "M2_Regime", PRAUC]
q126_m2 <- dyn_q126[method == "M2_Regime", PRAUC]

q15_static  <- dyn_q15[method == "Static_WEW", PRAUC]
q63_static  <- dyn_q63[method == "Static_WEW", PRAUC]
q126_static <- dyn_q126[method == "Static_WEW", PRAUC]

q15_best  <- dyn_q15[, max(PRAUC)]
q63_best  <- dyn_q63[, max(PRAUC)]
q126_best <- dyn_q126[, max(PRAUC)]

cat(sprintf("\n[M2 Regime per horizon]\n"))
cat(sprintf("  y_tail_q15  (H= 21): %.4f\n", q15_m2))
cat(sprintf("  y_tail_q63  (H= 63): %.4f (Δ vs q15 = %+.4f)\n", q63_m2, q63_m2 - q15_m2))
cat(sprintf("  y_tail_q126 (H=126): %.4f (Δ vs q15 = %+.4f)\n", q126_m2, q126_m2 - q15_m2))

cat(sprintf("\n[Static WEW per horizon]\n"))
cat(sprintf("  y_tail_q15  (H= 21): %.4f\n", q15_static))
cat(sprintf("  y_tail_q63  (H= 63): %.4f (Δ vs q15 = %+.4f)\n", q63_static, q63_static - q15_static))
cat(sprintf("  y_tail_q126 (H=126): %.4f (Δ vs q15 = %+.4f)\n", q126_static, q126_static - q15_static))

cat(sprintf("\n[Best across methods per horizon]\n"))
cat(sprintf("  y_tail_q15  best: %.4f (%s)\n",
            q15_best, dyn_q15[which.max(PRAUC), method]))
cat(sprintf("  y_tail_q63  best: %.4f (%s)\n",
            q63_best, dyn_q63[which.max(PRAUC), method]))
cat(sprintf("  y_tail_q126 best: %.4f (%s)\n",
            q126_best, dyn_q126[which.max(PRAUC), method]))

# Verdict per Dohoon spec
verdict_q63 <- if (q63_m2 > q15_m2 + 0.03) {
  "HORIZON_HYPOTHESIS_PROVEN_q63 (M2 q63 > q15 +0.03)"
} else if (q63_m2 > q15_m2) {
  "WEAK_POSITIVE_q63 (q63 > q15 but < +0.03 threshold)"
} else {
  "REJECTED_q63 (q63 <= q15)"
}
verdict_q126 <- if (q126_m2 > q15_m2 + 0.03) {
  "HORIZON_HYPOTHESIS_PROVEN_q126 (M2 q126 > q15 +0.03)"
} else if (q126_m2 > q15_m2) {
  "WEAK_POSITIVE_q126 (q126 > q15 but < +0.03 threshold)"
} else {
  "REJECTED_q126 (q126 <= q15)"
}
overall_verdict <- if (q126_m2 > q15_m2 + 0.03 | q63_m2 > q15_m2 + 0.03) {
  "HORIZON_HYPOTHESIS_PROVEN"
} else if (q63_m2 < q15_m2 - 0.03 & q126_m2 < q15_m2 - 0.03) {
  "INVERSE_HYPOTHESIS (US macro signal stronger short-horizon)"
} else if (q63_m2 <= q15_m2 & q126_m2 <= q15_m2) {
  "REJECTED (US macro family no horizon-leading benefit)"
} else {
  "NEUTRAL (mixed signals across horizons)"
}

cat(sprintf("\n[Verdict q63 ] %s\n", verdict_q63))
cat(sprintf("[Verdict q126] %s\n", verdict_q126))
cat(sprintf("[Verdict overall] %s\n", overall_verdict))

# 47B reproduction sanity (q15 only, vs 47B M2 Regime y_tail_q15=0.5004)
# NOTE: 47B used DIFFERENT y_tail_q15 (backward-looking ret_h bug in
#       02_target_builder.R line 39), so |Δ| ~0.005 expected only if methodology
#       identical. Here we have the CORRECT forward-looking q15, so the
#       reproduction is not 1:1.
b47b_m2_q15 <- 0.5004   # from outputs/04_evaluation/5way_retrain_v3f_us_macro.json
b47b_static_q15 <- 0.4956

cat(sprintf("\n[47B reproduction sanity — y_tail_q15 (METHODOLOGY DIVERGENCE)]\n"))
cat(sprintf("  Note: 47B 02_target_builder.R uses shift(-H, lead) which returns\n"))
cat(sprintf("        BACKWARD prices (pre-existing bug). 48A uses correct\n"))
cat(sprintf("        forward-looking ret_qN. Therefore |Δ| > 0.005 expected.\n"))
cat(sprintf("  47B M2 Regime  q15 (backward target): %.4f\n", b47b_m2_q15))
cat(sprintf("  48A M2 Regime  q15 (forward target):  %.4f\n", q15_m2))
cat(sprintf("  Δ  M2 (NOT comparable; different targets): %+.4f\n", q15_m2 - b47b_m2_q15))
cat(sprintf("  47B Static WEW q15 (backward target): %.4f\n", b47b_static_q15))
cat(sprintf("  48A Static WEW q15 (forward target):  %.4f\n", q15_static))
cat(sprintf("  Δ  Static (NOT comparable): %+.4f\n", q15_static - b47b_static_q15))

#==============================================================================
# Step 7: JSON + 3-panel PR curve
#==============================================================================
cat("\n========== Step 7: Save outputs ==========\n")

step_R_path <- file.path(EVAL_DIR, "5way_retrain_v3g_horizon_swap_step_R.json")
step_R <- if (file.exists(step_R_path)) fromJSON(step_R_path, simplifyVector = FALSE) else list(error = "missing step R")

# Long-horizon target metadata
tgt_meta <- as.data.table(read_parquet(file.path(WS, "outputs/02_targets/targets_long_horizon.parquet")))
target_summary <- list()
for (nm in c("y_tail_q15", "y_tail_q63", "y_tail_q126")) {
  H <- switch(nm, y_tail_q15 = 21L, y_tail_q63 = 63L, y_tail_q126 = 126L)
  ev <- sum(tgt_meta[[nm]] == 1, na.rm = TRUE)
  nv <- sum(!is.na(tgt_meta[[nm]]))
  target_summary[[nm]] <- list(horizon_days = H, events = ev, non_na = nv,
                                event_rate = round(ev/max(nv,1), 4))
}

# Compose per-horizon result block
per_horizon <- list()
for (tag in c("y_tail_q15", "y_tail_q63", "y_tail_q126")) {
  dyn <- get(sprintf("dyn_%s", gsub("y_tail_", "", tag)))
  step_R_block <- step_R[[tag]]
  per_horizon[[tag]] <- list(
    n_oos_eff = res_5w[[tag]]$n_oos,
    event_rate = round(res_5w[[tag]]$event_rate, 4),
    individual_5way = list(
      xgb  = round(res_5w[[tag]]$individual$xgb,  4),
      cat  = round(res_5w[[tag]]$individual$cat,  4),
      rf   = round(res_5w[[tag]]$individual$rf,   4),
      lstm = round(res_5w[[tag]]$individual$lstm, 4),
      tft  = round(res_5w[[tag]]$individual$tft,  4)
    ),
    ensemble_static = list(
      ew5 = round(res_5w[[tag]]$ew5, 4),
      wew = round(res_5w[[tag]]$wew, 4)
    ),
    dynamic_5method = as.list(setNames(round(dyn$PRAUC, 4), dyn$method)),
    feature_importance_new = if (!is.null(step_R_block)) {
      list(xgb = step_R_block$imp_new_xgb, cat = step_R_block$imp_new_cat,
           rf  = step_R_block$imp_new_rf)
    } else list()
  )
}

# Cross-horizon delta matrix
delta_matrix <- list(
  static_vs_q15 = list(
    q63  = round(q63_static  - q15_static, 4),
    q126 = round(q126_static - q15_static, 4)
  ),
  m2_regime_vs_q15 = list(
    q63  = round(q63_m2  - q15_m2, 4),
    q126 = round(q126_m2 - q15_m2, 4)
  ),
  best_vs_q15 = list(
    q63  = round(q63_best  - q15_best, 4),
    q126 = round(q126_best - q15_best, 4)
  )
)

result_json <- list(
  cycle = "48A",
  approach = "TARGET_HORIZON_SWAP_v3g — same v3f_us_macro panel (73 features) × {q15 ctrl, q63, q126}",
  panel = file.path(DATA_DIR, "feature_panel_v3f_us_macro.parquet"),
  targets = file.path(WS, "outputs/02_targets/targets_long_horizon.parquet"),
  target_summary = target_summary,
  walk_forward_splits = list(
    train = "1995-01-01 ~ 2009-12-31",
    valid = "2010-01-01 ~ 2015-12-31",
    oos   = "2016-01-01 ~ 2026-04-30"
  ),
  per_horizon = per_horizon,
  delta_vs_q15 = delta_matrix,
  verdict = list(
    q63 = verdict_q63,
    q126 = verdict_q126,
    overall = overall_verdict,
    decision_rule = list(
      proven = "Δ M2 Regime ≥ +0.03 vs q15",
      weak_positive = "Δ > 0 but < +0.03",
      rejected = "Δ <= 0",
      inverse = "BOTH q63 and q126 Δ < -0.03 (US macro short-horizon stronger)",
      neutral = "mixed"
    )
  ),
  reproduction_sanity_47B = list(
    note = paste0("47B 02_target_builder.R line 39 uses shift(BM_Close, -H, type='lead') ",
                  "which returns BACKWARD price (pre-existing bug — see Step 0 v3 log). ",
                  "48A uses correct forward-looking ret_qN. Therefore the 47B q15 OOS ",
                  "PR-AUC 0.5004 is NOT directly comparable to 48A q15 OOS PR-AUC ",
                  "(different label distributions). Report as 'methodology divergence' ",
                  "rather than 'reproduction failure'."),
    bug_finding = "scripts/02_target_builder.R line 39: shift(BM_Close, -H, type='lead') == past values, NOT forward returns",
    fix_recommendation = "shift(BM_Close, n=H, type='lead') for correct forward returns",
    b47b_m2_regime_q15_backward_target = round(b47b_m2_q15, 4),
    b48a_m2_regime_q15_forward_target = round(q15_m2, 4),
    b47b_static_wew_q15_backward_target = round(b47b_static_q15, 4),
    b48a_static_wew_q15_forward_target = round(q15_static, 4)
  ),
  hypothesis_findings = list(
    us_macro_4_features = c("us_t10y2y_spread_lag1", "us_initial_claims_4w_avg_lag1",
                             "us_cfnai_lag1", "us_stlfsi_lag1"),
    rank_change_summary = "US macro features dominate at q126 (us_initial_claims rank 1 in XGB+RF, us_cfnai rank 1 in 47B q15). Q63 also strong but smaller. Q15 dilutes (47B finding reproduced).",
    next_cycle = if (q126_m2 > q15_m2 + 0.03 | q63_m2 > q15_m2 + 0.03) {
      "PROVEN → retain US macro family + add multi-horizon ensemble (q15 ⊕ q63 ⊕ q126) + consider production horizon shift OR multi-horizon overlay layer"
    } else if (q63_m2 < q15_m2 - 0.03 & q126_m2 < q15_m2 - 0.03) {
      "INVERSE → US macro short-horizon focus only, q15 sub-ensemble"
    } else if (q63_m2 <= q15_m2 & q126_m2 <= q15_m2) {
      "REJECTED → US macro family permanent revoke + advance exotic data cycle"
    } else {
      "NEUTRAL → re-examine M2 Regime regime definition (bbva_macro_composite may not align with q63/q126 horizon)"
    }
  ),
  outputs = list(
    targets = file.path(WS, "outputs/02_targets/targets_long_horizon.parquet"),
    v3g_dir = V3G_DIR,
    chart_3panel = file.path(CHART_DIR, "106_pr_curve_v3g_horizon_swap.png")
  )
)

out_json <- file.path(EVAL_DIR, "5way_retrain_v3g_horizon_swap.json")
write_json(result_json, out_json, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[JSON] %s\n", out_json))

# 3-panel PR curve chart
plot_one_panel <- function(target_col, dyn_dt) {
  dyn_path <- file.path(V3G_DIR, sprintf("predictions_dynamic_%s.parquet", target_col))
  dyn_pq <- as.data.table(read_parquet(dyn_path))
  dyn_pq[, Date := as.Date(Date)]
  static_pr <- dyn_dt[method == "Static_WEW", PRAUC]
  m1_pr <- dyn_dt[method == "M1_Rolling", PRAUC]
  m2_pr <- dyn_dt[method == "M2_Regime", PRAUC]
  m3_pr <- dyn_dt[method == "M3_Hedge", PRAUC]
  m4_pr <- dyn_dt[method == "M4_Bayes", PRAUC]

  ds_static <- pr_curve(dyn_pq$p_static, dyn_pq$y);     ds_static[, model := sprintf("Static  (PR-AUC=%.3f)", static_pr)]
  ds_m1     <- pr_curve(dyn_pq$p_M1_rolling, dyn_pq$y); ds_m1[, model := sprintf("M1 Roll (PR-AUC=%.3f)", m1_pr)]
  ds_m2     <- pr_curve(dyn_pq$p_M2_regime, dyn_pq$y);  ds_m2[, model := sprintf("M2 Reg  (PR-AUC=%.3f)", m2_pr)]
  ds_m3     <- pr_curve(dyn_pq$p_M3_hedge, dyn_pq$y);   ds_m3[, model := sprintf("M3 Hedg (PR-AUC=%.3f)", m3_pr)]
  ds_m4     <- pr_curve(dyn_pq$p_M4_bayes, dyn_pq$y);   ds_m4[, model := sprintf("M4 Bayes(PR-AUC=%.3f)", m4_pr)]
  curves <- rbind(ds_static, ds_m1, ds_m2, ds_m3, ds_m4)
  base_rate <- mean(dyn_pq$y, na.rm = TRUE)

  H <- switch(target_col, y_tail_q15 = 21L, y_tail_q63 = 63L, y_tail_q126 = 126L)
  ggplot(curves, aes(x = recall, y = precision, color = model)) +
    geom_line(linewidth = 0.7) +
    geom_hline(yintercept = base_rate, linetype = "dashed", color = "gray40") +
    scale_x_continuous(limits = c(0, 1)) + scale_y_continuous(limits = c(0, 1)) +
    labs(title = sprintf("%s (H=%dd)  base=%.3f", target_col, H, base_rate),
         x = "Recall", y = "Precision", color = NULL) +
    theme_minimal(base_size = 9) +
    theme(legend.position = "bottom", legend.text = element_text(size = 7)) +
    guides(color = guide_legend(ncol = 2))
}

g15  <- plot_one_panel("y_tail_q15",  dyn_q15)
g63  <- plot_one_panel("y_tail_q63",  dyn_q63)
g126 <- plot_one_panel("y_tail_q126", dyn_q126)

combo <- g15 | g63 | g126
combo <- combo + plot_annotation(
  title = sprintf("Cycle 48A — Target Horizon Swap (v3g_horizon_swap, 73 features) — verdict: %s",
                  overall_verdict),
  subtitle = sprintf("M2 Regime Δ vs q15: q63=%+.4f / q126=%+.4f", q63_m2 - q15_m2, q126_m2 - q15_m2),
  theme = theme(plot.title = element_text(size = 11, face = "bold"),
                plot.subtitle = element_text(size = 9))
)

ggsave(file.path(CHART_DIR, "106_pr_curve_v3g_horizon_swap.png"),
       plot = combo, width = 16, height = 6.5, dpi = 120)
cat(sprintf("[Chart] %s\n", file.path(CHART_DIR, "106_pr_curve_v3g_horizon_swap.png")))

cat(sprintf("\n========== Cycle 48A DONE ==========\n"))
cat(sprintf("Verdict: %s\n", overall_verdict))
cat(sprintf("Δ vs q15: M2 Regime q63=%+.4f / q126=%+.4f\n", q63_m2 - q15_m2, q126_m2 - q15_m2))
