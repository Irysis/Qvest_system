#==============================================================================
# 37_robustness_sweep.R — Cycle 7 Bear-conditional Hybrid Robustness Sweep
#
# Grid (48 combos):
#   DD thresholds: -5%%, -10%%, -15%%, -20%%
#   Active strategies: V_S1 (long-only switch), V_S3 (LCI asym), V_S5 (regime)
#   Switching cost: 15bps, 30bps, 60bps, 100bps
#
# Metrics: ΔSR / ΔMDD / ΔCAGR / Harvey-t per combo
# Verdict logic fix: dMDD >= 0 = improvement (less negative)
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

# ── (1) Load baseline + V_S{1,3,5} variants ──
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

expanding_q <- function(x, dates, q = 0.5) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    past <- x[dates < dates[i]]; past <- past[!is.na(past)]
    if (length(past) >= 12) out[i] <- as.numeric(quantile(past, q, na.rm = TRUE))
  }
  out
}

vpanel <- merge(eom, me[, .(ym, p, regime)], by = "ym", all.x = TRUE)
setorder(vpanel, ym)
vpanel[, q50 := expanding_q(p, Date_eom, 0.50)]
vpanel[, q70 := expanding_q(p, Date_eom, 0.70)]
vpanel[, q90 := expanding_q(p, Date_eom, 0.90)]

vpanel[, pos_S1 := fifelse(!is.na(q50) & p < q50, 1.0, 0.0)]
vpanel[, pos_S3 := fcase(is.na(q70) | is.na(q90), 0.0,
                          p < q70, 1.0,
                          p > q90, -1.0,
                          default = 0.0)]
vpanel[, pos_S5 := fcase(regime == "bull", 1.0,
                          regime == "bear", 0.0,
                          default = 0.5)]

# Build panel with all needed data
panel <- merge(baseline,
               vpanel[, .(realized_ym, pos_S1, pos_S3, pos_S5, ret_kospi)],
               by = "realized_ym", all.x = TRUE)
setorder(panel, anchor_date)

# 6m rolling DD on KOSPI200
panel[, kospi_log_cum := cumsum(log(1 + replace(ret_kospi, is.na(ret_kospi), 0)))]
panel[, kospi_lvl := exp(kospi_log_cum)]
panel[, kospi_6m_max := frollapply(kospi_lvl, 6, max, align = "right")]
panel[, kospi_dd_6m := kospi_lvl / kospi_6m_max - 1]

# Restrict to β_FX active subset (110m)
pfx_master <- panel[anchor_date >= as.Date("2017-03-01")]

# Metrics
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

# ── (2) Grid sweep ──
dd_thresholds <- c(-0.05, -0.10, -0.15, -0.20)
strategies <- c("S1", "S3", "S5")
costs_bps <- c(15, 30, 60, 100)

grid <- expand.grid(dd_thr = dd_thresholds, strat = strategies,
                    cost_bps = costs_bps, stringsAsFactors = FALSE)
grid_dt <- as.data.table(grid)

# Baseline metrics
base_m <- compute_m(pfx_master$ret_L5_V5, pfx_master$anchor_date)

cat(sprintf("━━━ Baseline (STR_1715 admit, 110m β_FX active) ━━━\n"))
cat(sprintf("  SR=%.4f  MDD=%.4f  CAGR=%.4f\n\n", base_m["SR"], base_m["MDD"], base_m["CAGR"]))

results <- vector("list", nrow(grid_dt))
for (i in seq_len(nrow(grid_dt))) {
  dd_thr <- grid_dt$dd_thr[i]
  strat <- grid_dt$strat[i]
  cost <- grid_dt$cost_bps[i] / 10000

  pfx <- copy(pfx_master)
  pfx[, bear_trigger := !is.na(kospi_dd_6m) & kospi_dd_6m <= dd_thr]
  pfx[, bear_trigger_lag1 := shift(bear_trigger, 1, fill = FALSE)]

  pos_col <- paste0("pos_", strat)
  pfx[, turn := abs(get(pos_col) - shift(get(pos_col), 1, fill = 0))]
  pfx[is.na(turn), turn := 0]
  pfx[, ret_strat := get(pos_col) * ret_kospi - turn * cost]
  pfx[is.na(ret_strat), ret_strat := 0]

  pfx[, state := fifelse(bear_trigger_lag1, "BEAR", "BULL")]
  pfx[, state_change := state != shift(state, 1, fill = "BULL")]
  pfx[, ret_hybrid := fifelse(bear_trigger_lag1, ret_strat, ret_L5_V5)]
  pfx[state_change == TRUE, ret_hybrid := ret_hybrid - cost]

  hyb_m <- compute_m(pfx$ret_hybrid, pfx$anchor_date)
  diff_ret <- pfx$ret_hybrid - pfx$ret_L5_V5
  ht <- nw_t(diff_ret, 4)

  dSR <- hyb_m["SR"] - base_m["SR"]
  dMDD <- hyb_m["MDD"] - base_m["MDD"]  # >0 = MDD less negative = improvement
  dCAGR <- hyb_m["CAGR"] - base_m["CAGR"]

  # Fixed verdict: dMDD >= 0 (less negative = improvement)
  verdict <- fcase(
    dSR >= 0.05 & dMDD >= 0 & abs(ht) > 2.0, "ADMIT_STRICT",
    dSR >= 0.05 & dMDD >= 0, "ADMIT_WEAK",
    dSR >= 0.05, "MIXED_SR_GAIN",
    dSR > 0, "MARGINAL",
    default = "REJECT"
  )

  results[[i]] <- data.table(
    dd_thr = dd_thr, strat = strat, cost_bps = grid_dt$cost_bps[i],
    SR_hyb = round(unname(hyb_m["SR"]), 4),
    MDD_hyb = round(unname(hyb_m["MDD"]), 4),
    CAGR_hyb = round(unname(hyb_m["CAGR"]), 4),
    dSR = round(unname(dSR), 4),
    dMDD = round(unname(dMDD), 4),
    dCAGR = round(unname(dCAGR), 4),
    harvey_t = round(ht, 3),
    n_trigger = sum(pfx$bear_trigger_lag1),
    verdict = verdict
  )
}
grid_res <- rbindlist(results)
setorder(grid_res, -dSR)

# Sort by dSR descending — top 10
cat(sprintf("━━━ TOP 10 combinations (by ΔSR) ━━━\n\n"))
print(head(grid_res, 10))

cat(sprintf("\n━━━ Verdict distribution ━━━\n"))
print(table(grid_res$verdict))

# ── (3) Best variant — full detail ──
best <- grid_res[1]
cat(sprintf("\n━━━ BEST variant ━━━\n"))
cat(sprintf("  DD threshold: %.2f%%%%  /  Strategy: V_%s  /  Switching cost: %dbps\n",
            100 * best$dd_thr, best$strat, best$cost_bps))
cat(sprintf("  SR=%.4f (ΔSR %+.4f) / MDD=%.4f (ΔMDD %+.4f) / CAGR=%.4f (ΔCAGR %+.4f)\n",
            best$SR_hyb, best$dSR, best$MDD_hyb, best$dMDD, best$CAGR_hyb, best$dCAGR))
cat(sprintf("  Harvey-t=%+.3f / Triggered months=%d / Verdict=%s\n",
            best$harvey_t, best$n_trigger, best$verdict))

# ── (4) ADMIT count + sensitivity statistics ──
n_admit_strict <- sum(grid_res$verdict == "ADMIT_STRICT")
n_admit_weak <- sum(grid_res$verdict == "ADMIT_WEAK")
n_admit_any <- sum(grid_res$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK"))
cat(sprintf("\n━━━ Robustness Summary ━━━\n"))
cat(sprintf("  ADMIT_STRICT: %d / 48 (%.0f%%%%)\n", n_admit_strict, 100 * n_admit_strict / nrow(grid_res)))
cat(sprintf("  ADMIT_WEAK  : %d / 48 (%.0f%%%%)\n", n_admit_weak, 100 * n_admit_weak / nrow(grid_res)))
cat(sprintf("  ANY ADMIT   : %d / 48 (%.0f%%%%)\n", n_admit_any, 100 * n_admit_any / nrow(grid_res)))

# Per-dimension breakdown
cat(sprintf("\n━━━ Per-dimension admit rate ━━━\n"))
cat(sprintf("  By DD threshold:\n"))
for (dd in dd_thresholds) {
  sub <- grid_res[dd_thr == dd]
  cat(sprintf("    DD %.0f%%%%: ADMIT %d / %d (%.0f%%%%) / median dSR %+.3f\n",
              100 * dd, sum(sub$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK")),
              nrow(sub),
              100 * mean(sub$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK")),
              median(sub$dSR)))
}
cat(sprintf("\n  By strategy:\n"))
for (s in strategies) {
  sub <- grid_res[strat == s]
  cat(sprintf("    V_%s: ADMIT %d / %d (%.0f%%%%) / median dSR %+.3f\n",
              s, sum(sub$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK")), nrow(sub),
              100 * mean(sub$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK")),
              median(sub$dSR)))
}
cat(sprintf("\n  By switching cost:\n"))
for (c_bps in costs_bps) {
  sub <- grid_res[cost_bps == c_bps]
  cat(sprintf("    %dbps: ADMIT %d / %d (%.0f%%%%) / median dSR %+.3f\n",
              c_bps, sum(sub$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK")), nrow(sub),
              100 * mean(sub$verdict %in% c("ADMIT_STRICT", "ADMIT_WEAK")),
              median(sub$dSR)))
}

# ── (5) Save ──
fwrite(grid_res, file.path(EVAL_DIR, "robustness_sweep_grid.csv"))
out <- list(
  baseline = list(SR = unname(base_m["SR"]), MDD = unname(base_m["MDD"]),
                   CAGR = unname(base_m["CAGR"])),
  best = as.list(best),
  n_admit_strict = n_admit_strict,
  n_admit_weak = n_admit_weak,
  n_admit_any = n_admit_any,
  grid_size = nrow(grid_res),
  robust_pct = 100 * n_admit_any / nrow(grid_res),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "robustness_sweep_summary.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/robustness_sweep_summary.json\n", EVAL_DIR))
cat(sprintf("[CSV] %s/robustness_sweep_grid.csv\n", EVAL_DIR))

# ── (6) Heatmap chart per strategy ──
for (s in strategies) {
  sub <- grid_res[strat == s]
  g <- ggplot(sub, aes(x = factor(cost_bps), y = factor(100 * dd_thr), fill = dSR)) +
    geom_tile(color = "white") +
    geom_text(aes(label = sprintf("%.2f\n(t=%.1f)", dSR, harvey_t)),
              size = 3, color = "black") +
    scale_fill_gradient2(low = "#073B4C", mid = "white", high = "#EF476F",
                         midpoint = 0) +
    labs(title = sprintf("V_%s: ΔSR by DD threshold × switching cost (110m β_FX)", s),
         x = "Switching cost (bps)", y = "DD threshold (%%)", fill = "ΔSR") +
    theme_minimal(base_size = 10)
  ggsave(file.path(CHART_DIR, sprintf("18_robustness_%s.png", s)),
         plot = g, width = 9, height = 5, dpi = 120)
}
cat(sprintf("[Charts] 18_robustness_S1/S3/S5.png\n"))

cat("\n[DONE]\n")
