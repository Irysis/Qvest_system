#==============================================================================
# 52_cross_asset_bear_hedge.R — Cycle 23 Cross-asset bear hedge research
#
# Test: replace KOSPI200 long (active position) with KR 10y bond (148070)
# during bear_trigger episodes. Compare with KOSPI long-based V1a+V3 baseline.
#
# Hypothesis: in sustained bear (V-shape miss), bond outperforms KOSPI.
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

# Bond ETF data
bond <- fread(file.path(WS, "outputs/01_data/kr10y_bond_148070_monthly.csv"))
bond[, Date := as.Date(Date)]
bond[, ym := format(Date, "%Y-%m")]
setorder(bond, Date)
bond[, ret_bond := c(NA, diff(Close) / head(Close, -1))]
bond[, realized_ym := ym]  # bond return realized in same month

# Merge bond ret into panel
panel <- merge(baseline, eom[, .(realized_ym, ret_kospi)],
               by = "realized_ym", all.x = TRUE)
panel <- merge(panel, bond[, .(realized_ym, ret_bond)],
               by = "realized_ym", all.x = TRUE)
setorder(panel, anchor_date)
cat(sprintf("[Panel] %d months / bond data available: %d months\n",
            nrow(panel), sum(!is.na(panel$ret_bond))))
cat(sprintf("Bond available period: %s ~ %s\n",
            as.character(panel$anchor_date[which(!is.na(panel$ret_bond))[1]]),
            as.character(panel$anchor_date[max(which(!is.na(panel$ret_bond)))])))

# ── (2) Build bear trigger ──
panel[, kospi_log_cum := cumsum(log(1 + replace(ret_kospi, is.na(ret_kospi), 0)))]
panel[, kospi_lvl := exp(kospi_log_cum)]
panel[, kospi_2m_max := frollapply(kospi_lvl, 2, max, align = "right")]
panel[, kospi_dd_2m := kospi_lvl / kospi_2m_max - 1]
panel[, bear_trigger := !is.na(kospi_dd_2m) & kospi_dd_2m <= -0.05]
panel[, bear_trigger_lag1 := shift(bear_trigger, 1, fill = FALSE)]
panel[, dd_lag := shift(kospi_dd_2m, 1, fill = 0)]
panel[, trig_run := 0L]
for (i in seq_len(nrow(panel))) {
  if (panel$bear_trigger_lag1[i]) {
    panel[i, trig_run := ifelse(i > 1 && panel$bear_trigger_lag1[i - 1],
                                  panel$trig_run[i - 1] + 1L, 1L)]
  }
}
panel[, active := bear_trigger_lag1 & trig_run <= 2]

# ── (3) Build 3 variants ──
# A: KOSPI long (current best, cycle 18)
panel[, pos_A := pmax(0.0, 0.7 - 3.0 * pmax(0, -(dd_lag + 0.10)))]
panel[, ret_active_A := pos_A * ret_kospi]

# B: KR Bond (replace KOSPI with bond at same position)
panel[, pos_B := pmax(0.0, 0.7 - 3.0 * pmax(0, -(dd_lag + 0.10)))]
panel[, ret_active_B := pos_B * replace(ret_bond, is.na(ret_bond), 0)]

# C: 50/50 KOSPI/bond blend
panel[, pos_C_kospi := 0.5 * pmax(0.0, 0.7 - 3.0 * pmax(0, -(dd_lag + 0.10)))]
panel[, pos_C_bond := 0.5 * pmax(0.0, 0.7 - 3.0 * pmax(0, -(dd_lag + 0.10)))]
panel[, ret_active_C := pos_C_kospi * ret_kospi +
                         pos_C_bond * replace(ret_bond, is.na(ret_bond), 0)]

# Hybrid returns
panel[, state := fifelse(active, "BEAR", "BULL")]
panel[, state_change := state != shift(state, 1, fill = "BULL")]
for (v in c("A", "B", "C")) {
  rcol <- paste0("ret_active_", v); hcol <- paste0("ret_hyb_", v)
  panel[, (hcol) := fifelse(active, get(rcol), ret_L5_V5)]
  panel[state_change == TRUE, (hcol) := get(hcol) - 0.003]
}

# Restrict to bond-available period
pfx <- panel[!is.na(ret_bond)]
cat(sprintf("Eval period: %s ~ %s (n=%d)\n",
            as.character(min(pfx$anchor_date)),
            as.character(max(pfx$anchor_date)), nrow(pfx)))

# ── (4) Metrics ──
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

m_base <- compute_m(pfx$ret_L5_V5, pfx$anchor_date)
cat(sprintf("\n━━━ Baseline + 3 variants ━━━\n"))
cat(sprintf("  STR_1715       : SR %.4f / MDD %+.4f / CAGR %.4f\n",
            m_base["SR"], m_base["MDD"], m_base["CAGR"]))

results <- list()
labels <- c("A" = "Hybrid V1aV3 (KOSPI long, current best)",
            "B" = "Hybrid V_BOND (KR 10y bond replace)",
            "C" = "Hybrid V_50_50 (KOSPI/bond blend)")
for (v in c("A", "B", "C")) {
  rcol <- paste0("ret_hyb_", v)
  mm <- compute_m(pfx[[rcol]], pfx$anchor_date)
  ht <- nw_t(pfx[[rcol]] - pfx$ret_L5_V5, 4)
  dSR <- mm["SR"] - m_base["SR"]
  dMDD <- mm["MDD"] - m_base["MDD"]
  results[[v]] <- list(label = labels[v], SR = mm["SR"], MDD = mm["MDD"],
                        CAGR = mm["CAGR"], dSR = dSR, dMDD = dMDD,
                        harvey_t = ht)
  cat(sprintf("  Variant %s: SR %.4f / MDD %+.4f / CAGR %.4f / dSR %+.4f / dMDD %+.4f / t %+.3f\n",
              v, mm["SR"], mm["MDD"], mm["CAGR"], dSR, dMDD, ht))
}

# ── (5) Per-episode breakdown for B vs A ──
pfx[, trig_group := cumsum(state != shift(state, 1, fill = "BULL"))]
ep_dt <- pfx[active == TRUE,
              .(period = sprintf("%s~%s",
                                 format(min(anchor_date), "%y%m"),
                                 format(max(anchor_date), "%y%m")),
                n_months = .N,
                cum_A = prod(1 + ret_hyb_A) - 1,
                cum_B = prod(1 + ret_hyb_B) - 1,
                cum_C = prod(1 + ret_hyb_C) - 1,
                cum_base = prod(1 + ret_L5_V5) - 1,
                cum_kospi = prod(1 + ret_kospi) - 1,
                cum_bond = prod(1 + replace(ret_bond, is.na(ret_bond), 0)) - 1),
             by = trig_group]
cat(sprintf("\n━━━ Per-episode comparison (n=%d) ━━━\n", nrow(ep_dt)))
print(ep_dt[, .(period, n_months,
                 A_pct = round(100 * cum_A, 2),
                 B_pct = round(100 * cum_B, 2),
                 C_pct = round(100 * cum_C, 2),
                 base_pct = round(100 * cum_base, 2),
                 kospi_pct = round(100 * cum_kospi, 2),
                 bond_pct = round(100 * cum_bond, 2))])

# ── (6) Verdict ──
best_v <- names(which.max(sapply(c("A", "B", "C"), function(v) results[[v]]$dSR)))
cat(sprintf("\n━━━ Cross-asset Verdict ━━━\n"))
cat(sprintf("  BEST: V_%s — %s\n", best_v, labels[best_v]))
cat(sprintf("  dSR vs STR_1715: %+.4f / dMDD %+.4f / Harvey-t %+.3f\n",
            results[[best_v]]$dSR, results[[best_v]]$dMDD,
            results[[best_v]]$harvey_t))
if (best_v == "A") {
  cat(sprintf("  ✅ KOSPI long (current PRIMARY) remains best\n"))
} else if (best_v == "B") {
  cat(sprintf("  🎯 Bond replacement BETTER — V1.2 candidate\n"))
} else {
  cat(sprintf("  △ Blend marginally better — variant retention\n"))
}

# ── (7) Save ──
out <- list(
  baseline = list(SR = unname(m_base["SR"]), MDD = unname(m_base["MDD"]),
                   CAGR = unname(m_base["CAGR"])),
  variants = list(
    A = list(label = labels["A"], SR = unname(results$A$SR),
              dSR = unname(results$A$dSR),
              MDD = unname(results$A$MDD),
              harvey_t = results$A$harvey_t),
    B = list(label = labels["B"], SR = unname(results$B$SR),
              dSR = unname(results$B$dSR),
              MDD = unname(results$B$MDD),
              harvey_t = results$B$harvey_t),
    C = list(label = labels["C"], SR = unname(results$C$SR),
              dSR = unname(results$C$dSR),
              MDD = unname(results$C$MDD),
              harvey_t = results$C$harvey_t)
  ),
  best_variant = best_v,
  n_episodes = nrow(ep_dt),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "cross_asset_bear_hedge.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/cross_asset_bear_hedge.json\n", EVAL_DIR))

# Chart NAV
nav_dt <- pfx[, .(anchor_date,
                   STR_1715 = cumprod(1 + ret_L5_V5),
                   A_KOSPI = cumprod(1 + ret_hyb_A),
                   B_Bond = cumprod(1 + ret_hyb_B),
                   C_Blend = cumprod(1 + ret_hyb_C))]
nav_long <- melt(nav_dt, id.vars = "anchor_date", variable.name = "Strategy", value.name = "NAV")
g <- ggplot(nav_long, aes(x = anchor_date, y = NAV, color = Strategy)) +
  geom_line(linewidth = 0.7) + scale_y_log10() +
  scale_color_manual(values = c("STR_1715" = "#073B4C", "A_KOSPI" = "#EF476F",
                                 "B_Bond" = "#06D6A0", "C_Blend" = "#FFD166")) +
  labs(title = "Cross-asset bear hedge variants vs KOSPI long (bond available period)",
       subtitle = sprintf("Best: V_%s (dSR %+.4f / Harvey-t %+.3f)",
                          best_v, results[[best_v]]$dSR, results[[best_v]]$harvey_t),
       x = NULL, y = "NAV (log)") +
  theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "30_cross_asset.png"),
       plot = g, width = 13, height = 6, dpi = 120)
cat(sprintf("[Chart 30] %s/30_cross_asset.png\n", CHART_DIR))

cat("\n[DONE]\n")
