#==============================================================================
# 51_oos_cross_validation.R — Cycle 22 OOS Cross-Validation
#
# Critical test: 2m/-5%% trigger was found via 267m full grid optimization.
# 진짜 robust한가? In-sample vs Out-of-sample split test.
#
# Split:
#   Train: 2004-02 ~ 2014-12 (131 months) — 첫 49%%
#   Test:  2015-01 ~ 2026-04 (136 months) — 나머지 51%%
#
# Per period:
#   Run full grid (windows × thresholds)
#   Find optimal trigger
#   Compare in-sample optimal vs OOS optimal
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xts);
  library(PerformanceAnalytics); library(ggplot2); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
PROD_DIR <- file.path(PROJECT_ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

# ── (1) Load data ──
bt <- readRDS(file.path(PROD_DIR, "04_backtest_results/bt_result_layer5_R05.rds"))
nav <- as.data.table(bt$nav)
nav[, anchor_date := as.Date(anchor_date)]
baseline <- nav[, .(anchor_date, realized_ym, nav_L5_V5)]
setorder(baseline, anchor_date)
baseline[, ret_L5_V5 := c(nav_L5_V5[1] - 1, diff(nav_L5_V5) / head(nav_L5_V5, -1))]

bm <- as.data.table(read_parquet(
  file.path(WS, "outputs/02_targets/targets_full.parquet")))
bm[, Date := as.Date(Date)]; bm[, ym := format(Date, "%Y-%m")]
setorder(bm, Date)
eom <- bm[, .(close_eom = BM_Close[which.max(Date)]), by = ym]
setorder(eom, ym)
eom[, ret_kospi := shift(close_eom, n = 1L, type = "lead") / close_eom - 1]
eom[, realized_ym := shift(ym, n = 1L, type = "lead")]

panel_full <- merge(baseline, eom[, .(realized_ym, ret_kospi)],
                     by = "realized_ym", all.x = TRUE)
setorder(panel_full, anchor_date)
panel_full[, kospi_log_cum := cumsum(log(1 + replace(ret_kospi, is.na(ret_kospi), 0)))]
panel_full[, kospi_lvl := exp(kospi_log_cum)]

# Helpers
compute_m <- function(ret_vec, dates) {
  ok <- !is.na(ret_vec) & is.finite(ret_vec)
  r <- ret_vec[ok]; d <- dates[ok]
  if (length(r) < 12) return(c(SR = NA, MDD = NA, CAGR = NA))
  xret <- xts::xts(r, order.by = d)
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

# Build hybrid for given window + threshold
build_hyb_panel <- function(panel_dt, W_dd, thr, cost = 0.003) {
  pc <- copy(panel_dt)
  pc[, max_v := frollapply(kospi_lvl, W_dd, max, align = "right")]
  pc[, dd_v := kospi_lvl / max_v - 1]
  pc[, dd_lag := shift(dd_v, 1, fill = 0)]
  pc[, bear_trigger := !is.na(dd_v) & dd_v <= thr]
  pc[, bear_trigger_lag1 := shift(bear_trigger, 1, fill = FALSE)]
  pc[, trig_run := 0L]
  for (i in seq_len(nrow(pc))) {
    if (pc$bear_trigger_lag1[i]) {
      pc[i, trig_run := ifelse(i > 1 && pc$bear_trigger_lag1[i - 1],
                                 pc$trig_run[i - 1] + 1L, 1L)]
    }
  }
  pc[, active := bear_trigger_lag1 & trig_run <= 2]
  pc[, pos_combo := pmax(0.0, 0.7 - 3.0 * pmax(0, -(dd_lag + 0.10)))]
  pc[, ret_active := pos_combo * ret_kospi]
  pc[, state := fifelse(active, "BEAR", "BULL")]
  pc[, state_change := state != shift(state, 1, fill = "BULL")]
  pc[, ret_hyb := fifelse(active, ret_active, ret_L5_V5)]
  pc[state_change == TRUE, ret_hyb := ret_hyb - cost]
  pc
}

# ── (2) Split train/test ──
train <- panel_full[realized_ym >= "2004-02" & realized_ym <= "2014-12"]
test <- panel_full[realized_ym >= "2015-01" & realized_ym <= "2026-04"]
cat(sprintf("Train: %d months (%s ~ %s)\n", nrow(train),
            train$realized_ym[1], train$realized_ym[nrow(train)]))
cat(sprintf("Test:  %d months (%s ~ %s)\n", nrow(test),
            test$realized_ym[1], test$realized_ym[nrow(test)]))

# ── (3) Grid search on train ──
m_base_train <- compute_m(train$ret_L5_V5, train$anchor_date)
m_base_test <- compute_m(test$ret_L5_V5, test$anchor_date)

cat(sprintf("\n━━━ Train period grid search ━━━\n"))
cat(sprintf("Baseline train: SR %.4f / MDD %+.4f / CAGR %.4f\n",
            m_base_train["SR"], m_base_train["MDD"], m_base_train["CAGR"]))
cat(sprintf("Baseline test:  SR %.4f / MDD %+.4f / CAGR %.4f\n",
            m_base_test["SR"], m_base_test["MDD"], m_base_test["CAGR"]))

W_vals <- c(2, 3, 4, 5, 6)
thr_vals <- c(-0.03, -0.04, -0.05, -0.06, -0.07, -0.08, -0.10)
train_grid <- data.table()
for (W_dd in W_vals) for (thr in thr_vals) {
  pc <- build_hyb_panel(train, W_dd, thr)
  mm <- compute_m(pc$ret_hyb, pc$anchor_date)
  ht <- nw_t(pc$ret_hyb - pc$ret_L5_V5, 4)
  train_grid <- rbind(train_grid, data.table(
    W_dd = W_dd, threshold = thr,
    n_active = sum(pc$active),
    SR = round(mm["SR"], 4),
    dSR = round(mm["SR"] - m_base_train["SR"], 4),
    MDD = round(mm["MDD"], 4),
    dMDD = round(mm["MDD"] - m_base_train["MDD"], 4),
    harvey_t = round(ht, 3)))
}
setorder(train_grid, -dSR)
cat(sprintf("\nTop 5 IN-SAMPLE optimal triggers:\n"))
print(head(train_grid, 5))

# ── (4) Apply each IS top variant to OOS test period ──
cat(sprintf("\n━━━ OOS test results for top IS variants ━━━\n"))
cat(sprintf("%-8s %-12s %-12s %-12s %-12s %-12s %-12s %-12s\n",
            "Rank", "W/thr", "IS dSR", "IS Harvey-t",
            "OOS SR", "OOS dSR", "OOS Harvey-t", "Verdict"))
oos_results <- list()
for (i in seq_len(min(10, nrow(train_grid)))) {
  W_dd <- train_grid$W_dd[i]; thr <- train_grid$threshold[i]
  pc_test <- build_hyb_panel(test, W_dd, thr)
  mm <- compute_m(pc_test$ret_hyb, pc_test$anchor_date)
  ht <- nw_t(pc_test$ret_hyb - pc_test$ret_L5_V5, 4)
  oos_dSR <- mm["SR"] - m_base_test["SR"]
  verdict <- fcase(
    oos_dSR >= 0.1 & abs(ht) > 2.0, "✅ STRONG_OOS",
    oos_dSR >= 0.05, "△ POSITIVE",
    oos_dSR >= 0, "❑ MARGINAL",
    default = "❌ NEGATIVE")
  oos_results[[i]] <- data.table(
    rank = i, W_dd = W_dd, threshold = thr,
    IS_dSR = train_grid$dSR[i], IS_harvey_t = train_grid$harvey_t[i],
    OOS_SR = round(mm["SR"], 4), OOS_dSR = round(oos_dSR, 4),
    OOS_harvey_t = round(ht, 3),
    OOS_MDD = round(mm["MDD"], 4),
    verdict = verdict)
  cat(sprintf("%-8d %dm/%.0f%%%%   %-+12.4f %-+12.3f %-+12.4f %-+12.4f %-+12.3f %-12s\n",
              i, W_dd, 100 * thr, train_grid$dSR[i], train_grid$harvey_t[i],
              mm["SR"], oos_dSR, ht, verdict))
}
oos_dt <- rbindlist(oos_results)

# ── (5) IS-OOS rank correlation ──
cat(sprintf("\n━━━ IS-OOS rank correlation ━━━\n"))
oos_dt[, IS_rank := seq_len(.N)]
oos_dt[, OOS_rank := rank(-OOS_dSR)]
rank_cor <- cor(oos_dt$IS_rank, oos_dt$OOS_rank, method = "spearman")
cat(sprintf("Spearman rank correlation (IS_rank vs OOS_rank): %.4f\n", rank_cor))
if (rank_cor >= 0.5) {
  cat(sprintf("  ✅ Strong rank stability\n"))
} else if (rank_cor >= 0.2) {
  cat(sprintf("  △ Moderate rank stability\n"))
} else {
  cat(sprintf("  ❌ Weak rank stability (overfitting suspected)\n"))
}

# ── (6) Specific 2m/-5%% IS vs OOS ──
cat(sprintf("\n━━━ 2m/-5%% specific check ━━━\n"))
focal_train <- train_grid[W_dd == 2 & threshold == -0.05]
focal_oos <- oos_dt[W_dd == 2 & threshold == -0.05]
cat(sprintf("  IS rank: %d / 35 (top %.0f%%%%)\n",
            focal_train$dSR_rank <- which(train_grid$dSR == focal_train$dSR),
            100 * which(train_grid$dSR == focal_train$dSR) / 35))
cat(sprintf("  IS dSR: %+.4f / Harvey-t %+.3f\n",
            focal_train$dSR, focal_train$harvey_t))
if (nrow(focal_oos) > 0) {
  cat(sprintf("  OOS dSR: %+.4f / Harvey-t %+.3f / verdict %s\n",
              focal_oos$OOS_dSR, focal_oos$OOS_harvey_t, focal_oos$verdict))
}

# Also test 2m/-5%% on test
pc_test_25 <- build_hyb_panel(test, 2, -0.05)
m_test_25 <- compute_m(pc_test_25$ret_hyb, pc_test_25$anchor_date)
cat(sprintf("  Standalone OOS 2m/-5%%: SR %.4f / dSR %+.4f / MDD %+.4f\n",
            m_test_25["SR"], m_test_25["SR"] - m_base_test["SR"], m_test_25["MDD"]))

# ── (7) Verdict ──
cat(sprintf("\n━━━ Final OOS Cross-validation Verdict ━━━\n"))
top_oos <- oos_dt[which.max(OOS_dSR)]
cat(sprintf("  IS top: %dm/%.0f%%%% (dSR +%.4f)\n",
            train_grid$W_dd[1], 100 * train_grid$threshold[1], train_grid$dSR[1]))
cat(sprintf("  OOS top: %dm/%.0f%%%% (OOS_dSR +%.4f)\n",
            top_oos$W_dd, 100 * top_oos$threshold, top_oos$OOS_dSR))
is_top_oos_positive <- oos_dt$OOS_dSR[1] > 0
cat(sprintf("  IS top variant OOS performance positive: %s\n",
            ifelse(is_top_oos_positive, "✅ YES", "❌ NO")))

# ── (8) Save ──
out <- list(
  train_period = list(start = train$realized_ym[1], end = train$realized_ym[nrow(train)],
                       n = nrow(train)),
  test_period = list(start = test$realized_ym[1], end = test$realized_ym[nrow(test)],
                      n = nrow(test)),
  IS_top_3 = head(train_grid, 3),
  OOS_top_3 = head(oos_dt[order(-OOS_dSR)], 3),
  rank_correlation = rank_cor,
  IS_top_OOS_positive = is_top_oos_positive,
  focal_2m_5pct = list(IS_dSR = focal_train$dSR,
                        OOS_dSR = ifelse(nrow(focal_oos) > 0, focal_oos$OOS_dSR, NA)),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "oos_cross_validation.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/oos_cross_validation.json\n", EVAL_DIR))

# Chart: IS-OOS scatter
oos_dt_full <- merge(train_grid[, .(W_dd, threshold, IS_dSR = dSR)],
                      data.table(W_dd = sapply(oos_results, function(x) x$W_dd),
                                  threshold = sapply(oos_results, function(x) x$threshold),
                                  OOS_dSR = sapply(oos_results, function(x) x$OOS_dSR)),
                      by = c("W_dd", "threshold"))
g <- ggplot(oos_dt_full, aes(x = IS_dSR, y = OOS_dSR,
                              color = factor(W_dd), shape = factor(100 * threshold))) +
  geom_point(size = 4, alpha = 0.8) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "red") +
  geom_hline(yintercept = 0, color = "gray60") +
  geom_vline(xintercept = 0, color = "gray60") +
  labs(title = sprintf("IS vs OOS dSR (rank cor %.3f)", rank_cor),
       subtitle = sprintf("IS top: 2m/-5%%%% / OOS top: %dm/%.0f%%%%",
                          top_oos$W_dd, 100 * top_oos$threshold),
       x = "In-sample dSR (train 2004-2014)",
       y = "Out-of-sample dSR (test 2015-2026)",
       color = "DD window", shape = "Threshold (%%)") +
  theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "29_oos_cross_validation.png"),
       plot = g, width = 11, height = 6, dpi = 120)
cat(sprintf("[Chart 29] %s/29_oos_cross_validation.png\n", CHART_DIR))

cat("\n[DONE]\n")
