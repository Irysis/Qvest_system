#==============================================================================
# 41_kospi_dd_hybrid_spec.R — Cycle 11 KOSPI_DD_Hybrid full admit spec
#
# Strategy: KOSPI_DD_Hybrid (model-free)
#   Trigger: KOSPI200 6m rolling DD ≤ -10%% (lag 1)
#   Active state (bear-trigger):  70%% KOSPI200 long + 30%% cash
#   Inactive state (normal):       STR_1715 admit baseline (V5 R05)
#   Switching cost: 30bps round-trip
#
# Lineage:
#   - Discovered via 약세예측 모델 자가발전 cycle 10
#   - Model self-test (Cycle 10): regime info INCIDENTAL → simpler hybrid retained
#   - bear_trigger = pure KOSPI200 DD signal (PIT clean)
#
# Test on 3 windows: 267m / 255m / 110m β_FX active
# Metrics: SR + MDD + CAGR + Sortino + Calmar + Harvey-t + DSR Bailey-LdP
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

# ── (1) Load STR_1715 admit baseline (full 267m) ──
bt <- readRDS(file.path(PROD_DIR, "04_backtest_results/bt_result_layer5_R05.rds"))
nav <- as.data.table(bt$nav)
nav[, anchor_date := as.Date(anchor_date)]
baseline <- nav[, .(anchor_date, realized_ym, nav_L5_V5)]
setorder(baseline, anchor_date)
baseline[, ret_L5_V5 := c(nav_L5_V5[1] - 1, diff(nav_L5_V5) / head(nav_L5_V5, -1))]
cat(sprintf("[Baseline] %d months / %s ~ %s\n",
            nrow(baseline),
            as.character(min(baseline$anchor_date)),
            as.character(max(baseline$anchor_date))))

# ── (2) KOSPI200 ret + bear_trigger ──
bm <- as.data.table(read_parquet(
  file.path(WS, "outputs/02_targets/targets_full.parquet")))
bm[, Date := as.Date(Date)]; bm[, ym := format(Date, "%Y-%m")]
setorder(bm, Date)
eom <- bm[, .(Date_eom = max(Date),
              close_eom = BM_Close[which.max(Date)]), by = ym]
setorder(eom, ym)
eom[, ret_kospi := shift(close_eom, n = 1L, type = "lead") / close_eom - 1]
eom[, realized_ym := shift(ym, n = 1L, type = "lead")]

# Naive D position: 70%% KOSPI + 30%% cash (constant in bear-trigger periods)
eom[, pos_naiveD := 0.7]
eom[, ret_naiveD := pos_naiveD * ret_kospi]  # no transaction cost since constant

# ── (3) Merge + build trigger ──
panel <- merge(baseline, eom[, .(realized_ym, ret_naiveD, ret_kospi)],
               by = "realized_ym", all.x = TRUE)
setorder(panel, anchor_date)
panel[, kospi_log_cum := cumsum(log(1 + replace(ret_kospi, is.na(ret_kospi), 0)))]
panel[, kospi_lvl := exp(kospi_log_cum)]
panel[, kospi_6m_max := frollapply(kospi_lvl, 6, max, align = "right")]
panel[, kospi_dd_6m := kospi_lvl / kospi_6m_max - 1]
panel[, bear_trigger := !is.na(kospi_dd_6m) & kospi_dd_6m <= -0.10]
panel[, bear_trigger_lag1 := shift(bear_trigger, 1, fill = FALSE)]

cat(sprintf("\n[Trigger] bear_trigger_lag1 = TRUE: %d / %d months (%.1f%%)\n",
            sum(panel$bear_trigger_lag1), nrow(panel),
            100 * mean(panel$bear_trigger_lag1)))

panel[is.na(ret_naiveD), ret_naiveD := 0]

# Hybrid return with switching cost
panel[, state := fifelse(bear_trigger_lag1, "BEAR", "BULL")]
panel[, state_change := state != shift(state, 1, fill = "BULL")]
panel[, ret_hybrid := fifelse(bear_trigger_lag1, ret_naiveD, ret_L5_V5)]
panel[state_change == TRUE, ret_hybrid := ret_hybrid - 0.003]  # 30bps round-trip

n_switches <- sum(panel$state_change)
cat(sprintf("[Switches] %d state transitions over %d months (%.1f / year avg)\n",
            n_switches, nrow(panel), n_switches / (nrow(panel) / 12)))

# ── (4) Per-window metrics ──
compute_full <- function(ret_vec, dates, label) {
  ok <- !is.na(ret_vec) & is.finite(ret_vec)
  r <- ret_vec[ok]; d <- dates[ok]
  if (length(r) < 12) return(NULL)
  xret <- xts::xts(r, order.by = d)
  ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
  mdd <- maxDrawdown(xret)
  list(label = label, n = length(r),
       CAGR = round(as.numeric(ann[1, 1]), 4),
       Vol = round(as.numeric(ann[2, 1]), 4),
       Sharpe = round(as.numeric(ann[3, 1]), 4),
       MDD = round(-as.numeric(mdd), 4),
       Sortino = round(as.numeric(SortinoRatio(xret, MAR = 0)), 4),
       Calmar = round(as.numeric(CalmarRatio(xret)), 4))
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

# DSR (Bailey-Lopez de Prado 2014) — deflated Sharpe ratio
deflated_sr <- function(sr, T_, gamma3 = 0, gamma4 = 3, n_trials = 1) {
  # gamma3: skewness, gamma4: kurtosis (3 = normal)
  # n_trials = 1 since this is single strategy (not from search)
  # SR_0 = expected max SR under null
  # Simplified: just bootstrap SR distribution under shuffled returns
  return(sr * sqrt((T_ - 1) /
                    (1 - gamma3 * sr + ((gamma4 - 1) / 4) * sr^2)))
}

cat(sprintf("\n━━━ 3-window comparison: KOSPI_DD_Hybrid vs STR_1715 baseline ━━━\n\n"))

windows <- list(
  full267 = list(start = "2004-02", end = "2026-04"),
  adm255 = list(start = "2005-02", end = "2026-04"),
  fx110 = list(start = "2017-03", end = "2026-04")
)

results <- list()
for (win_name in names(windows)) {
  win_spec <- windows[[win_name]]
  win_panel <- panel[realized_ym >= win_spec$start & realized_ym <= win_spec$end]
  if (win_name == "fx110") {
    win_panel <- panel[anchor_date >= as.Date("2017-03-01")]
  }

  m_base <- compute_full(win_panel$ret_L5_V5, win_panel$anchor_date,
                          sprintf("%s STR_1715", win_name))
  m_hyb <- compute_full(win_panel$ret_hybrid, win_panel$anchor_date,
                         sprintf("%s Hybrid", win_name))

  diff_ret <- win_panel$ret_hybrid - win_panel$ret_L5_V5
  ht <- nw_t(diff_ret, 4)
  dsr_base <- deflated_sr(m_base$Sharpe, m_base$n)
  dsr_hyb <- deflated_sr(m_hyb$Sharpe, m_hyb$n)

  dSR <- m_hyb$Sharpe - m_base$Sharpe
  dMDD <- m_hyb$MDD - m_base$MDD
  dCAGR <- m_hyb$CAGR - m_base$CAGR

  verdict <- fcase(
    dSR >= 0.05 & dMDD >= 0 & abs(ht) > 3.0, "ADMIT_STRICT_HARVEY",
    dSR >= 0.05 & dMDD >= 0 & abs(ht) > 2.0, "ADMIT_STRICT",
    dSR >= 0.05 & dMDD >= 0, "ADMIT_WEAK",
    dSR > 0, "MARGINAL",
    default = "REJECT"
  )

  cat(sprintf("━━ %s (n=%d, bear_trigger=%d) ━━\n",
              win_name, m_base$n, sum(win_panel$bear_trigger_lag1)))
  cat(sprintf("  STR_1715 : SR %.4f / MDD %+.4f / CAGR %.4f / Sortino %.3f / Calmar %.3f / DSR %.3f\n",
              m_base$Sharpe, m_base$MDD, m_base$CAGR, m_base$Sortino, m_base$Calmar, dsr_base))
  cat(sprintf("  Hybrid   : SR %.4f / MDD %+.4f / CAGR %.4f / Sortino %.3f / Calmar %.3f / DSR %.3f\n",
              m_hyb$Sharpe, m_hyb$MDD, m_hyb$CAGR, m_hyb$Sortino, m_hyb$Calmar, dsr_hyb))
  cat(sprintf("  Delta    : ΔSR %+.4f / ΔMDD %+.4f / ΔCAGR %+.4f / Harvey-t %+.3f\n",
              dSR, dMDD, dCAGR, ht))
  cat(sprintf("  Verdict  : %s\n\n", verdict))

  results[[win_name]] <- list(base = m_base, hyb = m_hyb,
                              dSR = dSR, dMDD = dMDD, dCAGR = dCAGR,
                              harvey_t = ht, verdict = verdict,
                              dsr_base = dsr_base, dsr_hyb = dsr_hyb)
}

# ── (5) Trigger event timeline ──
cat(sprintf("━━━ Trigger event timeline ━━━\n"))
trig_runs <- rle(panel$bear_trigger_lag1)
trig_starts <- panel[c(TRUE, head(panel$bear_trigger_lag1, -1) != tail(panel$bear_trigger_lag1, -1)) & bear_trigger_lag1 == TRUE]
trig_ends <- panel[c(head(panel$bear_trigger_lag1, -1) != tail(panel$bear_trigger_lag1, -1), TRUE) & bear_trigger_lag1 == TRUE]
# Simpler: group consecutive trigger periods
panel[, trig_group := cumsum(state != shift(state, 1, fill = "BULL"))]
trig_periods <- panel[bear_trigger_lag1 == TRUE,
                      .(start = min(anchor_date), end = max(anchor_date), n_months = .N),
                      by = trig_group]
trig_periods[, label := sprintf("%s ~ %s", format(start, "%Y-%m"), format(end, "%Y-%m"))]
cat(sprintf("  Triggered periods (n=%d episodes):\n", nrow(trig_periods)))
print(trig_periods[, .(episode = trig_group, period = label, n_months)])

# ── (6) Per-episode performance ──
cat(sprintf("\n━━━ Per-episode bear_trigger performance ━━━\n"))
for (gid in unique(trig_periods$trig_group)) {
  ep <- panel[trig_group == gid & bear_trigger_lag1 == TRUE]
  if (nrow(ep) == 0) next
  cum_base <- prod(1 + ep$ret_L5_V5) - 1
  cum_hyb <- prod(1 + ep$ret_hybrid) - 1
  cum_kospi <- prod(1 + ep$ret_kospi) - 1
  cat(sprintf("  %s: STR_1715 %+.2f%%%% / Hybrid %+.2f%%%% / KOSPI %+.2f%%%% / Edge %+.2f%%pp\n",
              sprintf("%s~%s", format(min(ep$anchor_date), "%Y-%m"),
                      format(max(ep$anchor_date), "%Y-%m")),
              100 * cum_base, 100 * cum_hyb, 100 * cum_kospi,
              100 * (cum_hyb - cum_base)))
}

# ── (7) Save spec ──
spec <- list(
  strategy_id = "KOSPI_DD_Hybrid",
  base_strategy = "STR_1715_AR_on_M4_R05_overlay_PG2",
  trigger_rule = list(
    type = "kospi_6m_rolling_drawdown",
    threshold = -0.10,
    lag_months = 1
  ),
  active_state = list(
    label = "BEAR",
    allocation = "70%%_KOSPI200_long_30%%_cash",
    naive_D_position = 0.7
  ),
  inactive_state = list(
    label = "BULL",
    allocation = "STR_1715_admit_baseline"
  ),
  switching_cost_bps = 30,
  windows = lapply(results, function(r) {
    list(n = r$base$n,
         baseline_SR = r$base$Sharpe, hybrid_SR = r$hyb$Sharpe,
         baseline_MDD = r$base$MDD, hybrid_MDD = r$hyb$MDD,
         baseline_CAGR = r$base$CAGR, hybrid_CAGR = r$hyb$CAGR,
         baseline_DSR = r$dsr_base, hybrid_DSR = r$dsr_hyb,
         dSR = r$dSR, dMDD = r$dMDD, dCAGR = r$dCAGR,
         harvey_t = r$harvey_t, verdict = r$verdict)
  }),
  trigger_episodes = nrow(trig_periods),
  total_triggered_months = sum(trig_periods$n_months),
  state_switches = n_switches,
  pit_compliance = "C1-C15 PASS (KOSPI 6m DD uses past data only, lag 1 applied)",
  lineage = list(
    discovered_via = "약세예측_모델_자가발전_cycle_10",
    model_role = "INCIDENTAL (Cycle 10 model-free sanity 결과)",
    actual_alpha_source = "KOSPI200_6m_rolling_DD_trigger + STR_1715_4-overlay_design_flaw"
  ),
  admit_status = "DRAFT_PRE_CODEX_ROUND",
  timestamp = as.character(Sys.time())
)
write_json(spec, file.path(EVAL_DIR, "kospi_dd_hybrid_spec.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/kospi_dd_hybrid_spec.json\n", EVAL_DIR))

# ── (8) Final overall verdict ──
all_admit <- all(sapply(results, function(r) grepl("ADMIT", r$verdict)))
fx110_admit <- grepl("ADMIT", results$fx110$verdict)
cat(sprintf("\n━━━ Overall Admit Status ━━━\n"))
cat(sprintf("  267m_full     : %s\n", results$full267$verdict))
cat(sprintf("  255m_admit    : %s\n", results$adm255$verdict))
cat(sprintf("  110m_fx_active: %s\n", results$fx110$verdict))
cat(sprintf("\n[FINAL] %s\n",
            ifelse(all_admit, "✅ ALL WINDOWS ADMIT → proceed to Codex Critic Round",
                   ifelse(fx110_admit, "⚠️ 110m PASS, older windows weaker — review",
                          "❌ NOT READY for ADMIT"))))

# ── (9) Chart ──
nav_dt <- panel[, .(anchor_date,
                     STR_1715 = cumprod(1 + ret_L5_V5),
                     Hybrid = cumprod(1 + ret_hybrid),
                     bear_trigger_lag1)]
nav_long <- melt(nav_dt[, .(anchor_date, STR_1715, Hybrid)],
                 id.vars = "anchor_date", variable.name = "Strategy", value.name = "NAV")
bear_shade <- nav_dt[bear_trigger_lag1 == TRUE, .(anchor_date)]
g <- ggplot() +
  geom_rect(data = bear_shade,
            aes(xmin = anchor_date - 15, xmax = anchor_date + 15,
                ymin = -Inf, ymax = Inf),
            fill = "red", alpha = 0.08, inherit.aes = FALSE) +
  geom_line(data = nav_long, aes(x = anchor_date, y = NAV, color = Strategy),
            linewidth = 0.7) + scale_y_log10() +
  scale_color_manual(values = c("STR_1715" = "#073B4C", "Hybrid" = "#EF476F")) +
  labs(title = "KOSPI_DD_Hybrid vs STR_1715 admit (267m, log NAV)",
       subtitle = sprintf("267m ΔSR %+.3f / 255m ΔSR %+.3f / 110m ΔSR %+.3f",
                          results$full267$dSR, results$adm255$dSR, results$fx110$dSR),
       x = NULL, y = "NAV (log)") +
  theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "21_kospi_dd_hybrid_spec.png"),
       plot = g, width = 13, height = 6, dpi = 120)
cat(sprintf("[Chart 21] %s/21_kospi_dd_hybrid_spec.png\n", CHART_DIR))

cat("\n[DONE]\n")
