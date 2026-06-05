#==============================================================================
# 50_etf_reproducibility.R — Cycle 20 Live KODEX 200 ETF reproducibility
#
# Tests:
#   (A) BM_Close vs 069500 monthly returns correlation + tracking error
#   (B) Reproduce Hybrid V1aV3 2m/-5%% using actual 069500 returns
#   (C) Performance comparison vs BM_Close-based result
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

# ── (1) Load ETF data ──
etf <- fread(file.path(WS, "outputs/01_data/kodex200_069500_monthly.csv"))
etf[, Date := as.Date(Date)]
etf[, ym := format(Date, "%Y-%m")]
setorder(etf, Date)
etf[, ret_etf := c(NA, diff(Close) / head(Close, -1))]

# ── (2) Load BM_Close ──
bm <- as.data.table(read_parquet(
  file.path(WS, "outputs/02_targets/targets_full.parquet")))
bm[, Date := as.Date(Date)]; bm[, ym := format(Date, "%Y-%m")]
setorder(bm, Date)
eom <- bm[, .(close_eom_bm = BM_Close[which.max(Date)]), by = ym]
setorder(eom, ym)
eom[, ret_bm := c(NA, diff(close_eom_bm) / head(close_eom_bm, -1))]

# ── (3) Merge for tracking error ──
m <- merge(etf[, .(ym, close_etf = Close, ret_etf)],
           eom[, .(ym, close_eom_bm, ret_bm)], by = "ym", all.x = TRUE)
m <- m[!is.na(ret_etf) & !is.na(ret_bm)]
setorder(m, ym)

cat(sprintf("━━━ BM_Close vs 069500 monthly returns ━━━\n"))
cat(sprintf("Overlap period: %s ~ %s (n=%d months)\n",
            m$ym[1], m$ym[nrow(m)], nrow(m)))
cat(sprintf("Correlation: %.4f\n", cor(m$ret_bm, m$ret_etf)))
cat(sprintf("BM_Close mean ret: %+.2f%%%% / SD: %.2f%%%%\n",
            100 * mean(m$ret_bm), 100 * sd(m$ret_bm)))
cat(sprintf("069500   mean ret: %+.2f%%%% / SD: %.2f%%%%\n",
            100 * mean(m$ret_etf), 100 * sd(m$ret_etf)))

# Tracking error: SD of (ret_etf - ret_bm)
te <- sd(m$ret_etf - m$ret_bm) * sqrt(12)
mean_diff <- mean(m$ret_etf - m$ret_bm) * 12
cat(sprintf("Tracking error (annualized): %.2f%%%%\n", 100 * te))
cat(sprintf("Mean difference (annualized): %+.2f%%%% (ETF - BM)\n", 100 * mean_diff))

# ── (4) Reproduce Hybrid V1aV3 2m/-5%% using ETF returns ──
cat(sprintf("\n━━━ Hybrid V1aV3 2m/-5%% reproducibility ━━━\n"))

# Load baseline + build panel with ETF returns
bt <- readRDS(file.path(PROD_DIR, "04_backtest_results/bt_result_layer5_R05.rds"))
nav <- as.data.table(bt$nav)
nav[, anchor_date := as.Date(anchor_date)]
baseline <- nav[, .(anchor_date, realized_ym, nav_L5_V5)]
setorder(baseline, anchor_date)
baseline[, ret_L5_V5 := c(nav_L5_V5[1] - 1, diff(nav_L5_V5) / head(nav_L5_V5, -1))]

# ETF realized_ym = month after ret (forward return convention)
etf[, yr := as.integer(substr(ym, 1, 4))]
etf[, mn := as.integer(substr(ym, 6, 7))]
etf[, prev_yr := ifelse(mn == 1, yr - 1, yr)]
etf[, prev_mn := ifelse(mn == 1, 12, mn - 1)]
etf[, realized_ym := sprintf("%04d-%02d", yr, mn)]
# ret_etf represents the return realized during 'ym' itself

# Similarly for BM (forward ret)
eom_realized <- copy(eom)
eom_realized[, yr := as.integer(substr(ym, 1, 4))]
eom_realized[, mn := as.integer(substr(ym, 6, 7))]
eom_realized[, prev_yr := ifelse(mn == 1, yr - 1, yr)]
eom_realized[, prev_mn := ifelse(mn == 1, 12, mn - 1)]
eom_realized[, prev_ym := sprintf("%04d-%02d", prev_yr, prev_mn)]
eom_realized[, realized_ym := ym]  # ret_bm is realized in 'ym'

# Test: Use BM_Close ret for trigger (PIT consistent with strategy spec)
# AND use ETF ret for actual portfolio return
panel <- merge(baseline, etf[, .(realized_ym, ret_etf)],
               by = "realized_ym", all.x = TRUE)
panel <- merge(panel, eom_realized[, .(realized_ym, ret_bm)],
               by = "realized_ym", all.x = TRUE)
setorder(panel, anchor_date)

# Build 2m DD trigger from BM (strategy spec uses BM)
panel[, kospi_log_cum := cumsum(log(1 + replace(ret_bm, is.na(ret_bm), 0)))]
panel[, kospi_lvl := exp(kospi_log_cum)]
panel[, kospi_2m_max := frollapply(kospi_lvl, 2, max, align = "right")]
panel[, kospi_dd_2m := kospi_lvl / kospi_2m_max - 1]
panel[, bear_trigger := !is.na(kospi_dd_2m) & kospi_dd_2m <= -0.05]
panel[, bear_trigger_lag1 := shift(bear_trigger, 1, fill = FALSE)]
panel[, kospi_dd_2m_lag1 := shift(kospi_dd_2m, 1, fill = 0)]
panel[, trig_run := 0L]
for (i in seq_len(nrow(panel))) {
  if (panel$bear_trigger_lag1[i]) {
    panel[i, trig_run := ifelse(i > 1 && panel$bear_trigger_lag1[i - 1],
                                  panel$trig_run[i - 1] + 1L, 1L)]
  }
}
panel[, active := bear_trigger_lag1 & trig_run <= 2]
panel[, pos_combo := pmax(0.0, 0.7 - 3.0 * pmax(0, -(kospi_dd_2m_lag1 + 0.10)))]

# Two versions of ret_active: BM-based vs ETF-based
panel[, ret_active_BM := pos_combo * ret_bm]
panel[, ret_active_ETF := pos_combo * ret_etf]
panel[, state := fifelse(active, "BEAR", "BULL")]
panel[, state_change := state != shift(state, 1, fill = "BULL")]

panel[, ret_hyb_BM := fifelse(active, ret_active_BM, ret_L5_V5)]
panel[state_change == TRUE, ret_hyb_BM := ret_hyb_BM - 0.003]

panel[, ret_hyb_ETF := fifelse(active, ret_active_ETF, ret_L5_V5)]
panel[state_change == TRUE, ret_hyb_ETF := ret_hyb_ETF - 0.003]

# ── (5) Metrics for both ──
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

# Restrict to ETF-available period (069500 listed since 2002-10, data from 2007+)
pfx <- panel[!is.na(ret_etf)]
cat(sprintf("\nEval period (ETF available): %s ~ %s (n=%d)\n",
            as.character(min(pfx$anchor_date)),
            as.character(max(pfx$anchor_date)), nrow(pfx)))

m_base <- compute_m(pfx$ret_L5_V5, pfx$anchor_date)
m_bm <- compute_m(pfx$ret_hyb_BM, pfx$anchor_date)
m_etf <- compute_m(pfx$ret_hyb_ETF, pfx$anchor_date)

cat(sprintf("\nPerformance comparison:\n"))
cat(sprintf("  Baseline STR_1715: SR %.4f / MDD %+.4f / CAGR %.4f\n",
            m_base["SR"], m_base["MDD"], m_base["CAGR"]))
cat(sprintf("  Hybrid (BM-based): SR %.4f / MDD %+.4f / CAGR %.4f / dSR %+.4f\n",
            m_bm["SR"], m_bm["MDD"], m_bm["CAGR"], m_bm["SR"] - m_base["SR"]))
cat(sprintf("  Hybrid (ETF live): SR %.4f / MDD %+.4f / CAGR %.4f / dSR %+.4f\n",
            m_etf["SR"], m_etf["MDD"], m_etf["CAGR"], m_etf["SR"] - m_base["SR"]))
cat(sprintf("\n  Gap (ETF vs BM): ΔSR %+.4f / ΔMDD %+.4f / ΔCAGR %+.4f\n",
            m_etf["SR"] - m_bm["SR"], m_etf["MDD"] - m_bm["MDD"],
            m_etf["CAGR"] - m_bm["CAGR"]))

# ── (6) Verdict ──
sr_drop <- m_etf["SR"] - m_bm["SR"]
cat(sprintf("\n━━━ Reproducibility Verdict ━━━\n"))
if (abs(sr_drop) < 0.05) {
  cat(sprintf("  ✅ STRONG (ΔSR |%.4f| < 0.05) — ETF deployment safe\n", sr_drop))
  verdict <- "STRONG"
} else if (abs(sr_drop) < 0.15) {
  cat(sprintf("  △ MODERATE (ΔSR |%.4f| in [0.05, 0.15]) — ETF deployment acceptable with monitoring\n", sr_drop))
  verdict <- "MODERATE"
} else {
  cat(sprintf("  ⚠️ WEAK (ΔSR |%.4f| >= 0.15) — ETF tracking issue, investigate\n", sr_drop))
  verdict <- "WEAK"
}

# Tracking error verdict
if (te < 0.05) {
  cat(sprintf("  ✅ Tracking error %.2f%%%% < 5%%%% — ETF tracks BM well\n", 100 * te))
} else if (te < 0.10) {
  cat(sprintf("  △ Tracking error %.2f%%%% in [5%%%%, 10%%%%] — moderate slippage\n", 100 * te))
} else {
  cat(sprintf("  ⚠️ Tracking error %.2f%%%% >= 10%%%% — high tracking error, investigate BM_Close definition\n", 100 * te))
}

# ── (7) Save ──
out <- list(
  bm_vs_etf_correlation = cor(m$ret_bm, m$ret_etf),
  tracking_error_annualized = te,
  mean_diff_annualized = mean_diff,
  baseline = list(SR = unname(m_base["SR"]), MDD = unname(m_base["MDD"]),
                   CAGR = unname(m_base["CAGR"])),
  hybrid_BM = list(SR = unname(m_bm["SR"]), MDD = unname(m_bm["MDD"]),
                    CAGR = unname(m_bm["CAGR"]),
                    dSR = unname(m_bm["SR"] - m_base["SR"])),
  hybrid_ETF = list(SR = unname(m_etf["SR"]), MDD = unname(m_etf["MDD"]),
                     CAGR = unname(m_etf["CAGR"]),
                     dSR = unname(m_etf["SR"] - m_base["SR"])),
  etf_vs_bm_gap = list(dSR = unname(m_etf["SR"] - m_bm["SR"]),
                        dMDD = unname(m_etf["MDD"] - m_bm["MDD"])),
  verdict = verdict,
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "etf_reproducibility.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/etf_reproducibility.json\n", EVAL_DIR))

# Chart: BM vs ETF monthly return scatter
g1 <- ggplot(m, aes(x = ret_bm * 100, y = ret_etf * 100)) +
  geom_point(alpha = 0.6, color = "#073B4C") +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "red") +
  labs(title = sprintf("BM_Close vs KODEX 200 (069500) monthly returns (n=%d)", nrow(m)),
       subtitle = sprintf("Correlation %.3f / TE annualized %.2f%%%% / mean diff %+.2f%%%%/y",
                          cor(m$ret_bm, m$ret_etf), 100 * te, 100 * mean_diff),
       x = "BM_Close return (%%)", y = "069500 ETF return (%%)") +
  theme_minimal(base_size = 11)

# Hybrid NAV comparison
nav_dt <- pfx[, .(anchor_date,
                   STR_1715 = cumprod(1 + ret_L5_V5),
                   Hybrid_BM = cumprod(1 + ret_hyb_BM),
                   Hybrid_ETF = cumprod(1 + ret_hyb_ETF))]
nav_long <- melt(nav_dt, id.vars = "anchor_date", variable.name = "Strategy", value.name = "NAV")
g2 <- ggplot(nav_long, aes(x = anchor_date, y = NAV, color = Strategy)) +
  geom_line(linewidth = 0.7) + scale_y_log10() +
  scale_color_manual(values = c("STR_1715" = "#073B4C",
                                 "Hybrid_BM" = "#EF476F",
                                 "Hybrid_ETF" = "#06D6A0")) +
  labs(title = sprintf("Hybrid V1aV3 2m/-5%%%% — BM-based vs ETF-live reproducibility"),
       subtitle = sprintf("Verdict: %s (ΔSR gap ETF-BM = %+.4f)", verdict, sr_drop),
       x = NULL, y = "NAV (log)") + theme_minimal(base_size = 11)

g_comb <- patchwork::wrap_plots(g1, g2, ncol = 1)
ggsave(file.path(CHART_DIR, "28_etf_reproducibility.png"),
       plot = g_comb, width = 13, height = 9, dpi = 120)
cat(sprintf("[Chart 28] %s/28_etf_reproducibility.png\n", CHART_DIR))

cat("\n[DONE]\n")
