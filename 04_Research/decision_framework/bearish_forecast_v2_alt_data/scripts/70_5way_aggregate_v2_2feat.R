#==============================================================================
# 70_5way_aggregate_v2_2feat.R — Cycle 43 Step 4-6
#
# Steps:
#   Step 4: 5-way merge (XGB + CatBoost + RF + LSTM + TFT v2_2feat preds)
#   Step 5: Dynamic 5-method ensemble synthesis (M1~M5 같은 알고리즘)
#   Step 6: Compare vs V1.3 baseline 0.608 + V10 trigger 재평가
#
# Output:
#   outputs/03_models/v2_2feat/predictions_5way_{target}.parquet
#   outputs/03_models/v2_2feat/predictions_dynamic_{target}.parquet
#   outputs/04_evaluation/5way_retrain_v2_2feat.json
#   outputs/06_reports/charts/70_pr_curve_v2_2feat.png
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
V2_DIR <- file.path(WS, "outputs/03_models/v2_2feat")
BASE_DYN_DIR <- file.path(WS, "outputs/03_models/dynamic_ensemble")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

dir.create(V2_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

set.seed(42)

LOOKBACK <- 252
PURGE <- 21

pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

softmax <- function(x, beta = 5) {
  e <- exp(x * beta - max(x * beta))
  e / sum(e)
}

pr_curve <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  data.table(recall = rec, precision = prec)
}

#==============================================================================
# Step 4: 5-way merge
#==============================================================================
cat("\n========== Step 4: 5-way merge (XGB+Cat+RF + LSTM + TFT) ==========\n")

make_5way <- function(target_col) {
  cat(sprintf("\n----- 5-way merge: %s -----\n", target_col))
  gbdt <- as.data.table(read_parquet(file.path(V2_DIR, sprintf("predictions_3way_%s.parquet", target_col))))
  gbdt[, Date := as.Date(Date)]
  lstm <- as.data.table(read_parquet(file.path(V2_DIR, sprintf("predictions_lstm_%s.parquet", target_col))))
  lstm[, Date := as.Date(Date)]
  tft <- as.data.table(read_parquet(file.path(V2_DIR, sprintf("predictions_tft_%s.parquet", target_col))))
  tft[, Date := as.Date(Date)]

  oos_gbdt <- gbdt[split == "oos", .(Date, p_xgb, p_cat, p_rf, y)]
  oos <- merge(oos_gbdt, lstm[, .(Date, p_lstm)], by = "Date", all = TRUE)
  oos <- merge(oos, tft[, .(Date, p_tft)], by = "Date", all = TRUE)
  oos <- oos[!is.na(y) & !is.na(p_xgb) & !is.na(p_lstm) & !is.na(p_tft)]
  cat(sprintf("[merge] OOS N=%d / events=%d (%.2f%%)\n",
              nrow(oos), sum(oos$y), 100 * mean(oos$y)))

  pr_xgb <- pr_auc(oos$p_xgb, oos$y); pr_cat <- pr_auc(oos$p_cat, oos$y)
  pr_rf <- pr_auc(oos$p_rf, oos$y); pr_lstm <- pr_auc(oos$p_lstm, oos$y); pr_tft <- pr_auc(oos$p_tft, oos$y)

  cat(sprintf("[v2_2feat individual OOS PR-AUC] XGB=%.4f / CAT=%.4f / RF=%.4f / LSTM=%.4f / TFT=%.4f\n",
              pr_xgb, pr_cat, pr_rf, pr_lstm, pr_tft))

  # EW + Weighted EW for reference
  oos[, p_ew5 := (p_xgb + p_cat + p_rf + p_lstm + p_tft) / 5]
  oos[, p_wew := 0.25 * p_xgb + 0.25 * p_cat + 0.25 * p_rf + 0.125 * p_lstm + 0.125 * p_tft]
  pr_ew5 <- pr_auc(oos$p_ew5, oos$y); pr_wew <- pr_auc(oos$p_wew, oos$y)
  cat(sprintf("[v2_2feat] EW5=%.4f / WEW=%.4f\n", pr_ew5, pr_wew))

  write_parquet(oos, file.path(V2_DIR, sprintf("predictions_5way_%s.parquet", target_col)))
  list(individual = list(xgb=pr_xgb, cat=pr_cat, rf=pr_rf, lstm=pr_lstm, tft=pr_tft),
       ew5 = pr_ew5, wew = pr_wew, oos = oos)
}

res_5w_q15 <- make_5way("y_tail_q15")
res_5w_onset <- make_5way("y_onset")

#==============================================================================
# Step 5: Dynamic 5-method synthesis (M1~M5)
#==============================================================================
cat("\n========== Step 5: Dynamic 5-method ensemble synthesis ==========\n")

run_dynamic_v2 <- function(target_col, oos_in) {
  cat(sprintf("\n----- Dynamic 5-method: %s -----\n", target_col))
  p5 <- copy(oos_in); setorder(p5, Date); n_total <- nrow(p5)
  M_NAMES <- c("p_xgb", "p_cat", "p_rf", "p_lstm", "p_tft")
  M <- as.matrix(p5[, ..M_NAMES]); Y <- p5$y

  # Static baseline (Weighted EW)
  w_static <- c(0.25, 0.25, 0.25, 0.125, 0.125)
  p_static <- as.numeric(M %*% w_static)
  pa_static <- pr_auc(p_static, Y)
  cat(sprintf("[Static WEW] PR-AUC=%.4f\n", pa_static))

  # M1: Rolling Adaptive
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

  # M2: Regime-Conditional (bbva_macro_composite quantile)
  feat <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v2_2feat.parquet")))
  feat[, Date := as.Date(Date)]
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
    cur_reg <- Regime[i]
    if (is.na(cur_reg)) next
    cutoff <- i - PURGE; start <- cutoff - LOOKBACK + 1
    if (start < 1) next
    in_reg <- which(Regime[start:cutoff] == cur_reg) + (start - 1)
    if (length(in_reg) < 30) {
      p_M2[i] <- sum(M_r[i, ] * w_static); next
    }
    pr_m <- sapply(seq_len(5), function(m) pr_auc(M_r[in_reg, m], Y_r[in_reg]))
    pr_m[is.na(pr_m)] <- 0
    w <- softmax(pr_m, beta = 5)
    p_M2[i] <- sum(M_r[i, ] * w)
  }
  pa_M2 <- pr_auc(p_M2, Y_r)
  cat(sprintf("[M2 Regime]   PR-AUC=%.4f %s\n", pa_M2, ifelse(pa_M2 > pa_static, "★", "")))

  # M3: Online Hedge
  eta <- 1.0; w_hedge <- rep(1/5, 5)
  p_M3 <- rep(NA_real_, n_total)
  for (i in seq_len(n_total)) {
    p_M3[i] <- sum(M[i, ] * w_hedge)
    if (!is.na(Y[i])) {
      losses <- (M[i, ] - Y[i])^2
      w_hedge <- w_hedge * exp(-eta * losses); w_hedge <- w_hedge / sum(w_hedge)
    }
  }
  pa_M3 <- pr_auc(p_M3, Y)
  cat(sprintf("[M3 Hedge]    PR-AUC=%.4f %s\n", pa_M3, ifelse(pa_M3 > pa_static, "★", "")))

  # M4: Bayesian Online
  log_lik <- rep(0, 5); w_bayes <- rep(1/5, 5)
  p_M4 <- rep(NA_real_, n_total); eps <- 1e-6
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

  # M5: Contextual Bandit
  EPSILON <- 0.1
  Q <- matrix(0, nrow = 3, ncol = 5); counts <- matrix(0, nrow = 3, ncol = 5)
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
                  p_static = p_static,
                  p_M1_rolling = p_M1,
                  p_M2_regime = p_M2,
                  p_M3_hedge = p_M3,
                  p_M4_bayes = p_M4,
                  p_M5_bandit = p_M5)]
  write_parquet(out, file.path(V2_DIR, sprintf("predictions_dynamic_%s.parquet", target_col)))

  data.table(
    target = target_col,
    method = c("Static_WEW", "M1_Rolling", "M2_Regime", "M3_Hedge", "M4_Bayes", "M5_Bandit"),
    PRAUC = c(pa_static, pa_M1, pa_M2, pa_M3, pa_M4, pa_M5)
  )
}

dyn_q15 <- run_dynamic_v2("y_tail_q15", res_5w_q15$oos)
dyn_onset <- run_dynamic_v2("y_onset", res_5w_onset$oos)

cat("\n[Step 5 Dynamic SUMMARY]\n")
print(rbind(dyn_q15, dyn_onset))

#==============================================================================
# Step 6: Compare vs V1.3 baseline + V10 trigger 재평가
#==============================================================================
cat("\n========== Step 6: Compare vs V1.3 baseline 0.608 ==========\n")

# V1.3 baseline values (from outputs/03_models/dynamic_ensemble/dynamic_ensemble_summary.csv)
baseline_csv <- file.path(BASE_DYN_DIR, "dynamic_ensemble_summary.csv")
baseline_dyn <- fread(baseline_csv)
cat("\n[V1.3 baseline (69 features)]\n"); print(baseline_dyn)

bsl_q15 <- baseline_dyn[target == "y_tail_q15"]
bsl_static_q15 <- bsl_q15[method == "Static_WEW", PRAUC]
bsl_m2_q15     <- bsl_q15[method == "M2_Regime", PRAUC]

v2_static_q15  <- dyn_q15[method == "Static_WEW", PRAUC]
v2_m2_q15      <- dyn_q15[method == "M2_Regime", PRAUC]

delta_static <- v2_static_q15 - bsl_static_q15
delta_m2     <- v2_m2_q15 - bsl_m2_q15

cat(sprintf("\n[Δ vs V1.3 baseline on y_tail_q15]\n"))
cat(sprintf("  Static WEW:  V1.3=%.4f → v2_2feat=%.4f  (Δ %+.4f)\n",
            bsl_static_q15, v2_static_q15, delta_static))
cat(sprintf("  M2 Regime:   V1.3=%.4f → v2_2feat=%.4f  (Δ %+.4f) ★\n",
            bsl_m2_q15, v2_m2_q15, delta_m2))

verdict <- if (delta_m2 >= 0.03) {
  "ADMIT_CYCLE_RECOMMENDED"
} else if (delta_m2 >= 0.0) {
  "MARGINAL_PRESERVE_ONLY"
} else {
  "NEW_FEATURES_NOT_VALUABLE"
}
cat(sprintf("\n[Verdict (5-way M2 Regime)] %s\n", verdict))

#==============================================================================
# Step 6b: V10 trigger 재평가 (v2 M2 Regime 활용)
#==============================================================================
cat("\n========== Step 6b: V10 trigger 재평가 ==========\n")

# V10_v2 = count_5_q70 ≥ 4 AND trend_5d > 0 AND p_eom > q70 (모두 v2 p_M2_regime 기준)
# count_5_q70: 직전 5일 중 p > q70인 일수
# trend_5d: p의 5일 변화 (양수 = 상승 추세)
# p_eom: 월말 p값
# Compare: V10 baseline (V1.3 p_M2_regime) vs V10_v2 (v2_2feat p_M2_regime)

# Load v2 dynamic predictions
v2_dyn_q15 <- as.data.table(read_parquet(file.path(V2_DIR, "predictions_dynamic_y_tail_q15.parquet")))
v2_dyn_q15[, Date := as.Date(Date)]
setorder(v2_dyn_q15, Date)

# Load v1.3 baseline dynamic predictions
v1_dyn_q15 <- as.data.table(read_parquet(file.path(BASE_DYN_DIR, "predictions_dynamic_y_tail_q15.parquet")))
v1_dyn_q15[, Date := as.Date(Date)]
setorder(v1_dyn_q15, Date)

# Load KOSPI200 returns for dSR
kospi_path <- file.path(DATA_DIR, "kodex200_069500_monthly.csv")
if (file.exists(kospi_path)) {
  bm <- fread(kospi_path); bm[, Date := as.Date(Date)]
  cat(sprintf("KOSPI BM loaded: %d obs, columns: %s\n",
              nrow(bm), paste(names(bm), collapse=", ")))
} else {
  cat(sprintf("[V10] KOSPI BM not available — skip V10 evaluation\n"))
  bm <- NULL
}

eval_v10 <- function(dyn_dt, label, bm_dt) {
  # Compute features per day on the p_M2_regime
  dt <- copy(dyn_dt); setorder(dt, Date)
  dt[, p_M2 := p_M2_regime]
  dt <- dt[!is.na(p_M2)]
  if (nrow(dt) < 100) return(list(verdict = "NA_INSUFFICIENT_DATA", n = nrow(dt)))

  # Compute training q70 from first 60% of data
  n_total <- nrow(dt)
  cut_train <- floor(n_total * 0.6)
  q70 <- quantile(dt$p_M2[seq_len(cut_train)], 0.70, na.rm = TRUE)
  cat(sprintf("[%s] q70 = %.4f (train period n=%d)\n", label, q70, cut_train))

  # Rolling 5-day features
  dt[, is_above_q70 := as.integer(p_M2 > q70)]
  dt[, count_5_q70 := frollsum(is_above_q70, n = 5, align = "right", na.rm = TRUE)]
  dt[, trend_5d := p_M2 - shift(p_M2, 5L, type = "lag")]

  # End-of-month p_eom
  dt[, YearMonth := format(Date, "%Y-%m")]
  dt[, p_eom := last(p_M2), by = YearMonth]

  # V10 trigger: count_5_q70 ≥ 4 AND trend_5d > 0 AND p_eom > q70
  dt[, V10_trigger := as.integer(
    !is.na(count_5_q70) & count_5_q70 >= 4 &
    !is.na(trend_5d) & trend_5d > 0 &
    !is.na(p_eom) & p_eom > q70
  )]

  n_trigger_days <- sum(dt$V10_trigger == 1, na.rm = TRUE)
  cat(sprintf("[%s] V10 trigger days: %d / %d (%.2f%%)\n",
              label, n_trigger_days, nrow(dt), 100 * n_trigger_days / nrow(dt)))

  # dSR calculation if BM available
  if (!is.null(bm_dt) && nrow(bm_dt) > 50) {
    # Identify monthly trigger (first trigger day of each month)
    dt[, month_first_trigger := (V10_trigger == 1) &
            !duplicated(YearMonth) & V10_trigger == 1, by = YearMonth]
    # Simpler: monthly trigger = any day in month had V10 trigger
    monthly_trigger <- dt[, .(trigger_any = any(V10_trigger == 1)), by = YearMonth]
    monthly_trigger[, YearMonth := as.character(YearMonth)]

    bm_local <- copy(bm_dt); setorder(bm_local, Date)
    # Identify BM monthly returns — robust to capitalization variants
    close_col <- NULL
    for (cand in c("Close", "close", "KODEX200_close", "kodex200_close")) {
      if (cand %in% names(bm_local)) { close_col <- cand; break }
    }
    if (!is.null(close_col)) {
      bm_local[, ret := log(get(close_col)) - shift(log(get(close_col)), 1)]
    } else if ("ret" %in% names(bm_local)) {
      # already returns
    } else {
      cat(sprintf("[%s] BM 컬럼 인식 불가 — skip dSR\n", label))
      return(list(verdict = "DSR_SKIPPED",
                   n_trigger = n_trigger_days, q70 = round(q70, 4)))
    }

    bm_local[, YearMonth := format(Date, "%Y-%m")]
    bm_local <- bm_local[!is.na(ret)]
    bm_monthly <- bm_local[, .(bm_ret = sum(ret, na.rm = TRUE)), by = YearMonth]

    df_eval <- merge(monthly_trigger, bm_monthly, by = "YearMonth")
    df_eval <- df_eval[!is.na(bm_ret)]

    # V10 strategy: 단기 위험 회피 — trigger 시 BM 회피 (0% 비중) vs BH KOSPI
    df_eval[, v10_ret := ifelse(trigger_any, 0, bm_ret)]
    df_eval[, bh_ret  := bm_ret]

    sr_v10 <- mean(df_eval$v10_ret) / sd(df_eval$v10_ret) * sqrt(12)
    sr_bh  <- mean(df_eval$bh_ret)  / sd(df_eval$bh_ret)  * sqrt(12)
    dSR <- sr_v10 - sr_bh

    cat(sprintf("[%s] V10 BH-avoidance dSR: SR_v10=%.4f / SR_bh=%.4f / dSR=%+.4f\n",
                label, sr_v10, sr_bh, dSR))
    return(list(q70 = round(q70, 4),
                 n_trigger_days = n_trigger_days,
                 n_total = nrow(dt),
                 sr_v10 = round(sr_v10, 4),
                 sr_bh = round(sr_bh, 4),
                 dSR = round(dSR, 4)))
  }
  list(q70 = round(q70, 4),
       n_trigger_days = n_trigger_days,
       n_total = nrow(dt))
}

v10_base <- tryCatch(eval_v10(v1_dyn_q15, "V10_baseline_v1.3", bm),
                     error = function(e) {
                       cat(sprintf("[V10 baseline error] %s\n", conditionMessage(e)))
                       list(verdict = "ERROR", msg = conditionMessage(e))
                     })
v10_v2   <- tryCatch(eval_v10(v2_dyn_q15, "V10_v2_2feat", bm),
                     error = function(e) {
                       cat(sprintf("[V10 v2 error] %s\n", conditionMessage(e)))
                       list(verdict = "ERROR", msg = conditionMessage(e))
                     })

#==============================================================================
# Step 7: Save JSON + Chart
#==============================================================================
cat("\n========== Step 7: Save outputs ==========\n")

# Load Step 2 summary for feature importance
step2_path <- file.path(EVAL_DIR, "5way_retrain_v2_2feat_step2.json")
step2 <- if (file.exists(step2_path)) fromJSON(step2_path) else list(error = "missing step2 json")

result_json <- list(
  cycle = 43,
  approach = "B_PARTIAL_RETAIN",
  baseline_v1_3 = list(
    n_features = 69,
    static_wew_y_tail_q15 = round(bsl_static_q15, 4),
    m2_regime_y_tail_q15 = round(bsl_m2_q15, 4)
  ),
  v2_2feat = list(
    n_features = 71,
    new_features = c("ad_ratio_5d_avg_lag1", "foreign_cum_5d_lag1"),
    individual_OOS_PRAUC_y_tail_q15 = res_5w_q15$individual,
    individual_OOS_PRAUC_y_onset = res_5w_onset$individual,
    dynamic_PRAUC_y_tail_q15 = setNames(dyn_q15$PRAUC, dyn_q15$method),
    dynamic_PRAUC_y_onset = setNames(dyn_onset$PRAUC, dyn_onset$method),
    feature_importance = step2$y_tail_q15
  ),
  delta_vs_baseline = list(
    delta_static_wew = round(delta_static, 4),
    delta_m2_regime = round(delta_m2, 4)
  ),
  verdict = verdict,
  decision_rule = list(
    admit_cycle = "Δ M2 Regime ≥ +0.03",
    marginal_preserve = "0 ~ +0.03",
    reject = "< 0"
  ),
  v10_trigger_revalidation = list(
    baseline_v1_3 = v10_base,
    v2_2feat = v10_v2,
    dSR_delta = if (!is.null(v10_v2$dSR) && !is.null(v10_base$dSR))
                round(v10_v2$dSR - v10_base$dSR, 4) else NULL
  ),
  outputs = list(
    panel = file.path(DATA_DIR, "feature_panel_v2_2feat.parquet"),
    v2_dir = V2_DIR,
    chart = file.path(CHART_DIR, "70_pr_curve_v2_2feat.png")
  )
)

out_json <- file.path(EVAL_DIR, "5way_retrain_v2_2feat.json")
write_json(result_json, out_json, auto_unbox = TRUE, pretty = TRUE,
            na = "null")
cat(sprintf("[JSON] %s\n", out_json))

# Chart: Static + M2 Regime baseline vs v2 PR curve
ds_v1_static <- pr_curve(v1_dyn_q15$p_static, v1_dyn_q15$y)
ds_v1_static[, model := sprintf("V1.3 Static (PR-AUC=%.4f)", bsl_static_q15)]
ds_v1_m2 <- pr_curve(v1_dyn_q15$p_M2_regime, v1_dyn_q15$y)
ds_v1_m2[, model := sprintf("V1.3 M2 Regime (PR-AUC=%.4f)", bsl_m2_q15)]
ds_v2_static <- pr_curve(v2_dyn_q15$p_static, v2_dyn_q15$y)
ds_v2_static[, model := sprintf("v2_2feat Static (PR-AUC=%.4f)", v2_static_q15)]
ds_v2_m2 <- pr_curve(v2_dyn_q15$p_M2_regime, v2_dyn_q15$y)
ds_v2_m2[, model := sprintf("v2_2feat M2 Regime (PR-AUC=%.4f)", v2_m2_q15)]

curves <- rbind(ds_v1_static, ds_v1_m2, ds_v2_static, ds_v2_m2)
base_rate <- mean(v2_dyn_q15$y, na.rm = TRUE)

g <- ggplot(curves, aes(x = recall, y = precision, color = model)) +
  geom_line(linewidth = 0.8) +
  geom_hline(yintercept = base_rate, linetype = "dashed", color = "gray40") +
  scale_x_continuous(limits = c(0, 1)) + scale_y_continuous(limits = c(0, 1)) +
  labs(title = sprintf("5-way Dynamic Ensemble — V1.3 (69) vs v2_2feat (71)  [%s]",
                       verdict),
       subtitle = sprintf("y_tail_q15 OOS  /  Δ Static %+.4f  /  Δ M2 Regime %+.4f",
                          delta_static, delta_m2),
       x = "Recall", y = "Precision", color = NULL,
       caption = "Dashed = base rate (positive rate)") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom", legend.text = element_text(size = 9)) +
  guides(color = guide_legend(ncol = 2))

ggsave(file.path(CHART_DIR, "70_pr_curve_v2_2feat.png"),
       plot = g, width = 11, height = 7, dpi = 120)
cat(sprintf("[Chart] %s\n", file.path(CHART_DIR, "70_pr_curve_v2_2feat.png")))

cat("\n========== Cycle 43 DONE ==========\n")
cat(sprintf("Verdict: %s\n", verdict))
cat(sprintf("Δ Static: %+.4f  /  Δ M2 Regime: %+.4f\n", delta_static, delta_m2))
