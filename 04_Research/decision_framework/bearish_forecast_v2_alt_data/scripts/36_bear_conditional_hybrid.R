#==============================================================================
# 36_bear_conditional_hybrid.R — Cycle 6.1 Bear-conditional Hybrid
#
# Hypothesis: Bear sub-period (B1: 6m rolling DD ≤ -10%%)에서만 V_S5 activate
# else STR_1715 admit baseline. State-dependent strategy.
#
# Hybrid return at month t:
#   if bear_trigger_lag1[t] == TRUE → ret = ret_S5[t]
#   else → ret = ret_L5_V5[t]
#
# PIT: 6m rolling DD uses past 6m ending at t-1, trigger decision at t-1 EOM
#      applied to month t (shift 1 lag)
#
# Switching cost: 30bps round-trip when strategy state changes
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

# ── (1) STR_1715 admit baseline ret_L5_V5 ──
bt <- readRDS(file.path(PROD_DIR, "04_backtest_results/bt_result_layer5_R05.rds"))
nav <- as.data.table(bt$nav)
nav[, anchor_date := as.Date(anchor_date)]
baseline <- nav[, .(anchor_date, realized_ym, nav_L5_V5)]
setorder(baseline, anchor_date)
baseline[, ret_L5_V5 := c(nav_L5_V5[1] - 1, diff(nav_L5_V5) / head(nav_L5_V5, -1))]

# ── (2) V_S5 standalone KOSPI200 timing ret ──
bm <- as.data.table(read_parquet(
  file.path(WS, "outputs/02_targets/targets_full.parquet")))
bm[, Date := as.Date(Date)]; bm[, ym := format(Date, "%Y-%m")]
setorder(bm, Date)
eom <- bm[, .(Date_eom = max(Date),
              close_eom = BM_Close[which.max(Date)]), by = ym]
setorder(eom, ym)
eom[, ret_kospi := shift(close_eom, n = 1L, type = "lead") / close_eom - 1]
eom[, realized_ym := shift(ym, n = 1L, type = "lead")]

preds <- as.data.table(read_parquet(
  file.path(WS, "outputs/03_models/dynamic_ensemble/predictions_dynamic_y_tail_q15.parquet")))
preds[, Date := as.Date(Date)]; preds[, p := p_M2_regime]
preds <- preds[!is.na(p)]; preds[, ym := format(Date, "%Y-%m")]
me <- preds[, .SD[which.max(Date)], by = ym]
setorder(me, Date)

s5 <- merge(eom, me[, .(ym, p, regime)], by = "ym", all.x = TRUE)
setorder(s5, ym)
s5[, pos_S5 := fcase(regime == "bull", 1.0,
                     regime == "bear", 0.0,
                     default = 0.5)]
s5[, turn_S5 := abs(pos_S5 - shift(pos_S5, 1, fill = 0))]
s5[, ret_S5 := pos_S5 * ret_kospi - turn_S5 * 0.003]  # 30bps round-trip

# ── (3) Build hybrid panel ──
# Merge baseline (STR_1715) + ret_S5 by realized_ym (from s5) ↔ realized_ym (baseline)
# In s5, realized_ym = ym + 1 (decision at ym EOM applied to next month)
panel <- merge(baseline,
               s5[, .(realized_ym, ret_S5, ret_kospi, p, regime)],
               by = "realized_ym", all.x = TRUE)
setorder(panel, anchor_date)

# ── (4) Compute 6m rolling DD bear trigger (using KOSPI200 ret) ──
panel[, kospi_log_cum := cumsum(log(1 + replace(ret_kospi, is.na(ret_kospi), 0)))]
panel[, kospi_lvl := exp(kospi_log_cum)]
panel[, kospi_6m_max := frollapply(kospi_lvl, 6, max, align = "right")]
panel[, kospi_dd_6m := kospi_lvl / kospi_6m_max - 1]
panel[, bear_trigger := !is.na(kospi_dd_6m) & kospi_dd_6m <= -0.10]

# PIT: trigger at t-1 EOM applied to month t
panel[, bear_trigger_lag1 := shift(bear_trigger, 1, fill = FALSE)]

cat(sprintf("━━━ Bear trigger coverage ━━━\n"))
cat(sprintf("  bear_trigger_lag1=TRUE: %d / %d months (%.1f%%)\n",
            sum(panel$bear_trigger_lag1),
            nrow(panel),
            100 * mean(panel$bear_trigger_lag1)))

# ── (5) Hybrid return ──
# If bear_trigger_lag1 = TRUE → ret_S5 (KOSPI200 timing)
# Else → ret_L5_V5 (STR_1715 admit)
# Switching cost: when state changes, 30bps additional cost
panel[, state := fifelse(bear_trigger_lag1, "BEAR", "BULL")]
panel[, state_change := state != shift(state, 1, fill = "BULL")]
panel[, ret_hybrid := fifelse(bear_trigger_lag1, ret_S5, ret_L5_V5)]
panel[state_change == TRUE, ret_hybrid := ret_hybrid - 0.003]  # 30bps switching cost

# ── (6) Eval windows ──
# Whole 267m (pre-2017 bear_trigger could activate but ret_S5 = NA → fallback)
panel[is.na(ret_S5), ret_S5 := 0]  # cash
panel[is.na(ret_hybrid), ret_hybrid := ret_L5_V5]  # fallback

# Three windows: 267m / 255m admit / 110m β_FX active
p267 <- panel[realized_ym >= "2004-02" & realized_ym <= "2026-04"]
p255 <- panel[realized_ym >= "2005-02" & realized_ym <= "2026-04"]
pfx <- panel[anchor_date >= as.Date("2017-03-01")]

# Metrics
compute_m <- function(ret_vec, dates, label) {
  ok <- !is.na(ret_vec) & is.finite(ret_vec)
  r <- ret_vec[ok]; d <- dates[ok]
  if (length(r) < 12) return(NULL)
  xret <- xts::xts(r, order.by = d)
  ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
  mdd <- maxDrawdown(xret)
  list(label = label, n = length(r),
       CAGR = round(as.numeric(ann[1, 1]), 4),
       Sharpe = round(as.numeric(ann[3, 1]), 4),
       MDD = round(-as.numeric(mdd), 4),
       Calmar = round(as.numeric(CalmarRatio(xret)), 4),
       Sortino = round(as.numeric(SortinoRatio(xret, MAR = 0)), 4))
}

nw_t <- function(x, lag = 4) {
  n <- length(x); xbar <- mean(x); resid <- x - xbar
  S <- sum(resid^2) / n
  for (l in seq_len(lag)) {
    w <- 1 - l / (lag + 1)
    S <- S + 2 * w * sum(resid[(l + 1):n] * resid[1:(n - l)]) / n
  }
  list(t = xbar / sqrt(S / n), mean = xbar)
}

# ── (7) Per window ──
cat(sprintf("\n━━━ 3-window comparison (Hybrid vs STR_1715 admit) ━━━\n\n"))
results <- list()
for (win_name in c("267m_full", "255m_admit", "110m_fx_active")) {
  if (win_name == "267m_full") pdt <- p267
  else if (win_name == "255m_admit") pdt <- p255
  else pdt <- pfx

  m_base <- compute_m(pdt$ret_L5_V5, pdt$anchor_date, sprintf("%s STR_1715", win_name))
  m_hyb  <- compute_m(pdt$ret_hybrid, pdt$anchor_date, sprintf("%s Hybrid", win_name))

  dSR <- m_hyb$Sharpe - m_base$Sharpe
  dMDD <- m_hyb$MDD - m_base$MDD
  dCAGR <- m_hyb$CAGR - m_base$CAGR

  diff_ret <- pdt$ret_hybrid - pdt$ret_L5_V5
  nw <- nw_t(diff_ret, 4)

  verdict <- fcase(
    dSR >= 0.05 & dMDD <= 0 & abs(nw$t) > 2.0, "✅ ADMIT_STRICT",
    dSR >= 0.05 & dMDD <= 0, "⚠️ ADMIT_WEAK",
    dSR > 0, "△ NEUTRAL_SR_GAIN",
    dMDD <= -0.02, "△ NEUTRAL_MDD_GAIN",
    default = "❌ REJECT"
  )

  cat(sprintf("━━ %s ━━\n", win_name))
  cat(sprintf("  STR_1715  : SR %.4f / MDD %.4f / CAGR %.4f\n",
              m_base$Sharpe, m_base$MDD, m_base$CAGR))
  cat(sprintf("  Hybrid    : SR %.4f / MDD %.4f / CAGR %.4f\n",
              m_hyb$Sharpe, m_hyb$MDD, m_hyb$CAGR))
  cat(sprintf("  Delta     : ΔSR %+.4f / ΔMDD %+.4f / ΔCAGR %+.4f\n",
              dSR, dMDD, dCAGR))
  cat(sprintf("  Harvey-t  : %+.3f  | Verdict: %s\n\n", nw$t, verdict))

  results[[win_name]] <- list(base = m_base, hyb = m_hyb,
                              dSR = dSR, dMDD = dMDD, dCAGR = dCAGR,
                              harvey_t = nw$t, verdict = verdict)
}

# ── (8) Bear-only subset (when activated) ──
cat(sprintf("━━━ Bear-only subset (when triggered) ━━━\n"))
bear_active <- pfx[bear_trigger_lag1 == TRUE]
cat(sprintf("  Active months (β_FX subset): %d\n", nrow(bear_active)))
if (nrow(bear_active) >= 6) {
  m_b_base <- compute_m(bear_active$ret_L5_V5, bear_active$anchor_date, "STR_1715 (bear)")
  m_b_hyb  <- compute_m(bear_active$ret_hybrid, bear_active$anchor_date, "Hybrid (bear)")
  m_b_kosp <- compute_m(bear_active$ret_kospi, bear_active$anchor_date, "BH KOSPI (bear)")
  cat(sprintf("  STR_1715 (bear): cum %+.2f%% / SR %.3f / MDD %.3f\n",
              100 * (prod(1 + bear_active$ret_L5_V5) - 1), m_b_base$Sharpe, m_b_base$MDD))
  cat(sprintf("  Hybrid (bear)  : cum %+.2f%% / SR %.3f / MDD %.3f\n",
              100 * (prod(1 + bear_active$ret_hybrid) - 1), m_b_hyb$Sharpe, m_b_hyb$MDD))
  cat(sprintf("  BH KOSPI (bear): cum %+.2f%% / SR %.3f / MDD %.3f\n",
              100 * (prod(1 + bear_active$ret_kospi) - 1), m_b_kosp$Sharpe, m_b_kosp$MDD))
}

# ── (9) Bull-only subset (no switch) ──
cat(sprintf("\n━━━ Bull-only subset (no trigger) ━━━\n"))
bull_inactive <- pfx[bear_trigger_lag1 == FALSE]
cat(sprintf("  Inactive months: %d\n", nrow(bull_inactive)))
if (nrow(bull_inactive) >= 12) {
  m_u_base <- compute_m(bull_inactive$ret_L5_V5, bull_inactive$anchor_date, "STR_1715 (bull)")
  m_u_hyb  <- compute_m(bull_inactive$ret_hybrid, bull_inactive$anchor_date, "Hybrid (bull)")
  cat(sprintf("  STR_1715 (bull): SR %.3f / cum %+.2f%%\n",
              m_u_base$Sharpe, 100 * (prod(1 + bull_inactive$ret_L5_V5) - 1)))
  cat(sprintf("  Hybrid (bull)  : SR %.3f / cum %+.2f%%\n",
              m_u_hyb$Sharpe, 100 * (prod(1 + bull_inactive$ret_hybrid) - 1)))
}

# ── (10) Save ──
out <- list(
  results_per_window = results,
  bear_active_subset_n = sum(panel$bear_trigger_lag1),
  trigger_rule = "kospi_6m_rolling_dd_lt_neg_10pct",
  active_strategy = "V_S5_regime_conditional",
  inactive_strategy = "STR_1715_admit",
  switching_cost_bps = 30,
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "bear_conditional_hybrid.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/bear_conditional_hybrid.json\n", EVAL_DIR))

# ── (11) Chart ──
nav_dt <- pfx[, .(anchor_date,
                  STR_1715 = cumprod(1 + ret_L5_V5),
                  Hybrid = cumprod(1 + ret_hybrid),
                  BH_KOSPI = cumprod(1 + replace(ret_kospi, is.na(ret_kospi), 0)),
                  bear_active = bear_trigger_lag1)]
nav_long <- melt(nav_dt[, .(anchor_date, STR_1715, Hybrid, BH_KOSPI)],
                 id.vars = "anchor_date", variable.name = "Strategy", value.name = "NAV")
bear_shade <- nav_dt[bear_active == TRUE, .(start = anchor_date)]
g <- ggplot() +
  geom_rect(data = bear_shade,
            aes(xmin = start - 15, xmax = start + 15, ymin = -Inf, ymax = Inf),
            fill = "red", alpha = 0.1, inherit.aes = FALSE) +
  geom_line(data = nav_long, aes(x = anchor_date, y = NAV, color = Strategy),
            linewidth = 0.7) + scale_y_log10() +
  scale_color_manual(values = c("STR_1715" = "#073B4C", "Hybrid" = "#EF476F",
                                 "BH_KOSPI" = "#FFD166")) +
  labs(title = "Bear-conditional Hybrid vs STR_1715 vs BH KOSPI (110m log NAV)",
       subtitle = sprintf("Bear trigger: 6m rolling DD ≤ -10%%%% (red shading) | %s",
                          results$`110m_fx_active`$verdict),
       x = NULL, y = "NAV (log)") +
  theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "17_bear_conditional_hybrid.png"),
       plot = g, width = 13, height = 6, dpi = 120)
cat(sprintf("[Chart 17] %s/17_bear_conditional_hybrid.png\n", CHART_DIR))

cat("\n[DONE]\n")
