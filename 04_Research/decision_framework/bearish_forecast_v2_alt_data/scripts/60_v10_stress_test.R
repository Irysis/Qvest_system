#==============================================================================
# 60_v10_stress_test.R — Cycle 35 V10 Last Validation (OOS + Cost + Threshold)
#
# V10 (3-cond AND): count_5_q70>=4 AND trend_5d>0 AND p_eom>q70
# Cycle 34: dSR +0.47, WF 100%%, LOO all+, BS CI [+0.06, +0.94]
#
# Tests:
#   (A) OOS cross-validation (split 50/50)
#   (B) Cost sensitivity (15/30/60/100bps)
#   (C) Threshold sensitivity (count 3/4/5 × trend 0/0.02/0.05)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xts);
  library(PerformanceAnalytics); library(ggplot2); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

# ── (1) Load ──
bm <- as.data.table(read_parquet(
  file.path(WS, "outputs/02_targets/targets_full.parquet")))
bm[, Date := as.Date(Date)]; bm[, ym := format(Date, "%Y-%m")]
setorder(bm, Date)
eom <- bm[, .(close_eom = BM_Close[which.max(Date)]), by = ym]
setorder(eom, ym)
eom[, ret_kospi := shift(close_eom, n = 1L, type = "lead") / close_eom - 1]
eom[, realized_ym := shift(ym, n = 1L, type = "lead")]

preds <- as.data.table(read_parquet(
  file.path(WS, "outputs/03_models/dynamic_ensemble/predictions_dynamic_y_tail_q15.parquet")))
preds[, Date := as.Date(Date)]; preds[, p := p_M2_regime]
preds <- preds[!is.na(p)]
setorder(preds, Date)
preds[, ym := format(Date, "%Y-%m")]

# Per-month aggregates
preds_me <- preds[, .(p_eom = p[which.max(Date)],
                       trend_5d = tail(p, 1) - p[max(1, length(p) - 5)]),
                  by = ym]
setorder(preds_me, ym)
preds_me[, q70 := NA_real_]
for (i in seq_len(nrow(preds_me))) {
  past_p <- preds$p[preds$ym < preds_me$ym[i]]
  past_p <- past_p[!is.na(past_p)]
  if (length(past_p) >= 30) preds_me[i, q70 := quantile(past_p, 0.70)]
}
preds_me[, count_5_q70 := 0L]
for (i in seq_len(nrow(preds_me))) {
  if (is.na(preds_me$q70[i])) next
  ym_i <- preds_me$ym[i]
  last_p_all <- preds$p[preds$ym <= ym_i]
  preds_me[i, count_5_q70 := sum(tail(last_p_all, 5) >= preds_me$q70[i], na.rm = TRUE)]
}
preds_me[, realized_ym := shift(ym, -1, type = "lead")]
panel <- merge(eom[, .(realized_ym, ret_kospi)],
               preds_me[, .(realized_ym, p_eom, trend_5d, q70, count_5_q70)],
               by = "realized_ym")
panel <- panel[!is.na(p_eom) & !is.na(q70) & !is.na(ret_kospi)]
cat(sprintf("[Panel] %d months\n", nrow(panel)))

dates <- as.Date(paste0(panel$realized_ym, "-01"))

# Helpers
compute_m <- function(ret_vec, dates) {
  xret <- xts::xts(ret_vec, order.by = dates)
  ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
  c(SR = as.numeric(ann[3, 1]),
    MDD = -as.numeric(maxDrawdown(xret)),
    CAGR = as.numeric(ann[1, 1]))
}
nw_t <- function(x, lag = 4) {
  n <- length(x); xbar <- mean(x); resid <- x - xbar
  if (n < 10) return(NA)
  S <- sum(resid^2) / n
  for (l in seq_len(lag)) {
    w <- 1 - l / (lag + 1)
    S <- S + 2 * w * sum(resid[(l + 1):n] * resid[1:(n - l)]) / n
  }
  xbar / sqrt(S / n)
}

build_v10 <- function(panel, count_thresh = 4, trend_thresh = 0, cost = 0.003) {
  trig <- panel$count_5_q70 >= count_thresh &
            panel$trend_5d > trend_thresh &
            panel$p_eom > panel$q70
  trig_prev <- shift(trig, 1, fill = FALSE)
  change <- trig != trig_prev
  ret <- ifelse(trig, 0, panel$ret_kospi)
  ret[change] <- ret[change] - cost
  list(ret = ret, n_trigger = sum(trig))
}

# ── (A) OOS cross-validation 50/50 split ──
cat(sprintf("\n━━━ (A) OOS Cross-Validation (50/50 split) ━━━\n"))
midpoint <- floor(nrow(panel) / 2)
train <- panel[1:midpoint]
test <- panel[(midpoint + 1):nrow(panel)]
train_dates <- dates[1:midpoint]
test_dates <- dates[(midpoint + 1):nrow(panel)]
cat(sprintf("  Train: %d months (%s ~ %s)\n", nrow(train),
            train$realized_ym[1], train$realized_ym[nrow(train)]))
cat(sprintf("  Test:  %d months (%s ~ %s)\n", nrow(test),
            test$realized_ym[1], test$realized_ym[nrow(test)]))

# V10 standard on train + test
train_v10 <- build_v10(train)
test_v10 <- build_v10(test)
m_train_bh <- compute_m(train$ret_kospi, train_dates)
m_train_v10 <- compute_m(train_v10$ret, train_dates)
m_test_bh <- compute_m(test$ret_kospi, test_dates)
m_test_v10 <- compute_m(test_v10$ret, test_dates)

cat(sprintf("\n  TRAIN: BH SR %.4f / V10 SR %.4f / dSR %+.4f / n_trig %d\n",
            m_train_bh["SR"], m_train_v10["SR"],
            m_train_v10["SR"] - m_train_bh["SR"], train_v10$n_trigger))
cat(sprintf("  TEST:  BH SR %.4f / V10 SR %.4f / dSR %+.4f / n_trig %d\n",
            m_test_bh["SR"], m_test_v10["SR"],
            m_test_v10["SR"] - m_test_bh["SR"], test_v10$n_trigger))
cat(sprintf("  OOS preservation: %s\n",
            ifelse(m_test_v10["SR"] > m_test_bh["SR"] + 0.1,
                   "✅ STRONG", "⚠️ WEAK")))

# ── (B) Cost sensitivity ──
cat(sprintf("\n━━━ (B) Cost sensitivity (full panel) ━━━\n"))
cost_dt <- data.table()
for (cost_bps in c(15, 30, 60, 100, 200)) {
  v <- build_v10(panel, cost = cost_bps / 10000)
  mm <- compute_m(v$ret, dates)
  ht <- nw_t(v$ret - panel$ret_kospi, 4)
  cost_dt <- rbind(cost_dt, data.table(
    cost_bps = cost_bps,
    SR = round(mm["SR"], 4),
    MDD = round(mm["MDD"], 4),
    dSR = round(mm["SR"] - compute_m(panel$ret_kospi, dates)["SR"], 4),
    harvey_t = round(ht, 3),
    n_trigger = v$n_trigger))
}
print(cost_dt)

# ── (C) Threshold sensitivity grid ──
cat(sprintf("\n━━━ (C) Threshold sensitivity (count × trend grid) ━━━\n"))
m_base_full <- compute_m(panel$ret_kospi, dates)
thr_dt <- data.table()
for (count_t in c(3, 4, 5)) for (trend_t in c(0, 0.02, 0.05)) {
  v <- build_v10(panel, count_thresh = count_t, trend_thresh = trend_t)
  mm <- compute_m(v$ret, dates)
  ht <- nw_t(v$ret - panel$ret_kospi, 4)
  thr_dt <- rbind(thr_dt, data.table(
    count = count_t,
    trend = trend_t,
    n_trig = v$n_trigger,
    SR = round(mm["SR"], 4),
    MDD = round(mm["MDD"], 4),
    dSR = round(mm["SR"] - m_base_full["SR"], 4),
    harvey_t = round(ht, 3)))
}
setorder(thr_dt, -dSR)
print(thr_dt)
best_thr <- thr_dt[1]
cat(sprintf("\n  Best: count=%d, trend>%.2f → dSR %+.4f\n",
            best_thr$count, best_thr$trend, best_thr$dSR))

# ── (D) Final V10 verdict ──
cat(sprintf("\n━━━ Final V10 Verdict ━━━\n"))
all_pass <- TRUE
checks <- list()

# OOS test
oos_pos <- m_test_v10["SR"] > m_test_bh["SR"]
oos_strong <- m_test_v10["SR"] > m_test_bh["SR"] + 0.1
cat(sprintf("  OOS test SR > baseline: %s (%.3f vs %.3f)\n",
            ifelse(oos_pos, "✅", "❌"), m_test_v10["SR"], m_test_bh["SR"]))
checks$oos_pos <- oos_pos
if (!oos_pos) all_pass <- FALSE

# Cost insensitive (100bps still positive)
cost_100 <- cost_dt[cost_bps == 100]
cost_robust <- cost_100$dSR > 0
cat(sprintf("  Cost 100bps still positive: %s (dSR %+.4f)\n",
            ifelse(cost_robust, "✅", "❌"), cost_100$dSR))
checks$cost_robust <- cost_robust
if (!cost_robust) all_pass <- FALSE

# Threshold near best
v10_standard <- thr_dt[count == 4 & trend == 0]
top3_dSR <- head(thr_dt$dSR, 3)
v10_in_top3 <- v10_standard$dSR >= min(top3_dSR)
cat(sprintf("  V10 (count=4, trend>0) in TOP 3 grid: %s (dSR %+.4f vs top3 min %+.4f)\n",
            ifelse(v10_in_top3, "✅", "❌"),
            v10_standard$dSR, min(top3_dSR)))
checks$v10_in_top3 <- v10_in_top3

cat(sprintf("\n[VERDICT] %s\n",
            ifelse(all_pass, "✅ V10 CONFIRMED — 모델 PRIMARY 확정. 모닝브리핑 통합 진행 가능.",
                   "⚠️ PARTIAL — 추가 cycle 필요")))

# ── (E) Save ──
out <- list(
  oos_test = list(train_dSR = m_train_v10["SR"] - m_train_bh["SR"],
                   test_dSR = m_test_v10["SR"] - m_test_bh["SR"],
                   oos_pos = oos_pos, oos_strong = oos_strong),
  cost_sensitivity = cost_dt,
  threshold_sensitivity = thr_dt,
  best_threshold = list(count = best_thr$count, trend = best_thr$trend,
                         dSR = best_thr$dSR),
  v10_standard = list(count = 4, trend = 0,
                       dSR = v10_standard$dSR,
                       in_top3 = v10_in_top3),
  final_verdict = ifelse(all_pass, "CONFIRMED_PRIMARY", "PARTIAL"),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "v10_stress_test.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/v10_stress_test.json\n", EVAL_DIR))

# Heatmap chart
g <- ggplot(thr_dt, aes(x = factor(trend), y = factor(count), fill = dSR)) +
  geom_tile(color = "white") +
  geom_text(aes(label = sprintf("%.3f\n(n=%d)", dSR, n_trig)),
            size = 3, color = "black") +
  scale_fill_gradient2(low = "#073B4C", mid = "white", high = "#EF476F",
                       midpoint = 0) +
  labs(title = "V10 threshold sensitivity (count × trend)",
       subtitle = sprintf("Best: count=%d / trend>%.2f / dSR %+.3f",
                          best_thr$count, best_thr$trend, best_thr$dSR),
       x = "Trend threshold (>)", y = "Count threshold (>=)", fill = "dSR") +
  theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "37_v10_stress.png"),
       plot = g, width = 9, height = 5, dpi = 120)
cat(sprintf("[Chart 37] %s/37_v10_stress.png\n", CHART_DIR))

cat("\n[DONE]\n")
