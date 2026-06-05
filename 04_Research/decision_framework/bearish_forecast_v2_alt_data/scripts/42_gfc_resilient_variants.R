#==============================================================================
# 42_gfc_resilient_variants.R — Cycle 12 GFC-resilient Hybrid variants
#
# Problem (cycle 11): 2008-08~2009-03 GFC 8m episode causes -17.09%% Hybrid loss
# (vs STR_1715 -2.90%%). 110m subset hides this because of survivorship bias.
#
# Variants:
#   V1a: Re-entry after >2m trigger persistence (exit on month 3+)
#   V1b: Re-entry after >3m trigger persistence (exit on month 4+)
#   V1c: Re-entry after >4m trigger persistence (exit on month 5+)
#   V2: DD acceleration filter (only Hybrid if kospi_dd_6m recovering)
#   V3: Dynamic position scaling (KOSPI = 0.7 × (1 - max(0, -(dd+0.10)*5)))
#   Baseline: V0 = original 70/30 always-on (cycle 11 KOSPI_DD_Hybrid)
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

# ── (1) Load baseline + KOSPI200 ──
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

panel <- merge(baseline, eom[, .(realized_ym, ret_kospi)],
               by = "realized_ym", all.x = TRUE)
setorder(panel, anchor_date)

# Bear trigger + DD trend
panel[, kospi_log_cum := cumsum(log(1 + replace(ret_kospi, is.na(ret_kospi), 0)))]
panel[, kospi_lvl := exp(kospi_log_cum)]
panel[, kospi_6m_max := frollapply(kospi_lvl, 6, max, align = "right")]
panel[, kospi_dd_6m := kospi_lvl / kospi_6m_max - 1]
panel[, bear_trigger := !is.na(kospi_dd_6m) & kospi_dd_6m <= -0.10]
panel[, bear_trigger_lag1 := shift(bear_trigger, 1, fill = FALSE)]
panel[, kospi_dd_6m_lag1 := shift(kospi_dd_6m, 1, fill = 0)]
panel[, kospi_dd_6m_lag2 := shift(kospi_dd_6m, 2, fill = 0)]
# DD recovering = current dd > prev dd (less negative)
panel[, dd_recovering := kospi_dd_6m_lag1 > kospi_dd_6m_lag2]

# Trigger persistence count (consecutive months trigger active)
# Each row: how many consecutive previous months were triggered
panel[, trig_run := 0L]
for (i in seq_len(nrow(panel))) {
  if (panel$bear_trigger_lag1[i]) {
    panel[i, trig_run := ifelse(i > 1 && panel$bear_trigger_lag1[i - 1],
                                  panel$trig_run[i - 1] + 1L, 1L)]
  }
}

# ── (2) Build position variants ──
# V0: Original 70/30 always-on when trigger
panel[, pos_V0 := fifelse(bear_trigger_lag1, 0.7, NA_real_)]

# V1a: Exit after >2m trigger (trig_run > 2 → exit)
panel[, pos_V1a := fifelse(bear_trigger_lag1 & trig_run <= 2, 0.7, NA_real_)]
# V1b: Exit after >3m
panel[, pos_V1b := fifelse(bear_trigger_lag1 & trig_run <= 3, 0.7, NA_real_)]
# V1c: Exit after >4m
panel[, pos_V1c := fifelse(bear_trigger_lag1 & trig_run <= 4, 0.7, NA_real_)]

# V2: DD recovering filter (only Hybrid if DD becoming less negative)
panel[, pos_V2 := fifelse(bear_trigger_lag1 & dd_recovering, 0.7, NA_real_)]

# V3: Dynamic scaling — deeper DD → smaller position
# pos = max(0.0, 0.7 - 3 × max(0, -(kospi_dd_6m_lag1 + 0.10)))
# DD -10%% → pos 0.7, DD -20%% → pos 0.4, DD -30%% → pos 0.1
panel[, pos_V3 := fifelse(bear_trigger_lag1,
                           pmax(0.0, 0.7 - 3.0 * pmax(0, -(kospi_dd_6m_lag1 + 0.10))),
                           NA_real_)]

# ── (3) Build hybrid returns per variant ──
variants <- c("V0", "V1a", "V1b", "V1c", "V2", "V3")
for (v in variants) {
  pcol <- paste0("pos_", v)
  rcol <- paste0("ret_", v)
  panel[, in_hybrid := !is.na(get(pcol))]
  panel[, ret_hyb_v := fifelse(in_hybrid,
                                get(pcol) * ret_kospi,
                                ret_L5_V5)]
  # Switching cost
  panel[, state := fifelse(in_hybrid, "BEAR", "BULL")]
  panel[, state_change := state != shift(state, 1, fill = "BULL")]
  panel[state_change == TRUE, ret_hyb_v := ret_hyb_v - 0.003]
  panel[[rcol]] <- panel$ret_hyb_v
  panel[, c("in_hybrid", "state", "state_change", "ret_hyb_v") := NULL]
}

# ── (4) Per-window metrics ──
compute_full <- function(ret_vec, dates) {
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

cat(sprintf("━━━ 6-variant comparison on 3 windows ━━━\n\n"))
results <- list()
for (win_name in c("full267", "adm255", "fx110")) {
  win_panel <- switch(win_name,
                       full267 = panel[realized_ym >= "2004-02" & realized_ym <= "2026-04"],
                       adm255 = panel[realized_ym >= "2005-02" & realized_ym <= "2026-04"],
                       fx110 = panel[anchor_date >= as.Date("2017-03-01")])

  m_base <- compute_full(win_panel$ret_L5_V5, win_panel$anchor_date)
  res_win <- list(base = m_base)
  for (v in variants) {
    rcol <- paste0("ret_", v)
    mm <- compute_full(win_panel[[rcol]], win_panel$anchor_date)
    diff_ret <- win_panel[[rcol]] - win_panel$ret_L5_V5
    ht <- nw_t(diff_ret, 4)
    res_win[[v]] <- list(m = mm,
                         dSR = mm["SR"] - m_base["SR"],
                         dMDD = mm["MDD"] - m_base["MDD"],
                         dCAGR = mm["CAGR"] - m_base["CAGR"],
                         harvey_t = ht)
  }
  results[[win_name]] <- res_win
}

# Format & print
cat(sprintf("Window: full267 (n=267 months)\n"))
cat(sprintf("  STR_1715 base: SR %.4f / MDD %+.4f / CAGR %.4f\n",
            results$full267$base["SR"], results$full267$base["MDD"], results$full267$base["CAGR"]))
for (v in variants) {
  r <- results$full267[[v]]
  cat(sprintf("  %-5s: SR %.4f / MDD %+.4f / CAGR %.4f  ΔSR %+.4f / ΔMDD %+.4f / Harvey-t %+.3f\n",
              v, r$m["SR"], r$m["MDD"], r$m["CAGR"],
              r$dSR, r$dMDD, r$harvey_t))
}

cat(sprintf("\nWindow: adm255 (n=255 months)\n"))
cat(sprintf("  STR_1715 base: SR %.4f / MDD %+.4f / CAGR %.4f\n",
            results$adm255$base["SR"], results$adm255$base["MDD"], results$adm255$base["CAGR"]))
for (v in variants) {
  r <- results$adm255[[v]]
  cat(sprintf("  %-5s: SR %.4f / MDD %+.4f / CAGR %.4f  ΔSR %+.4f / ΔMDD %+.4f / Harvey-t %+.3f\n",
              v, r$m["SR"], r$m["MDD"], r$m["CAGR"],
              r$dSR, r$dMDD, r$harvey_t))
}

cat(sprintf("\nWindow: fx110 (n=110 months)\n"))
cat(sprintf("  STR_1715 base: SR %.4f / MDD %+.4f / CAGR %.4f\n",
            results$fx110$base["SR"], results$fx110$base["MDD"], results$fx110$base["CAGR"]))
for (v in variants) {
  r <- results$fx110[[v]]
  cat(sprintf("  %-5s: SR %.4f / MDD %+.4f / CAGR %.4f  ΔSR %+.4f / ΔMDD %+.4f / Harvey-t %+.3f\n",
              v, r$m["SR"], r$m["MDD"], r$m["CAGR"],
              r$dSR, r$dMDD, r$harvey_t))
}

# ── (5) GFC episode 2008-08~2009-03 detail ──
cat(sprintf("\n━━━ GFC episode (2008-08~2009-03) per-variant ━━━\n"))
gfc <- panel[anchor_date >= as.Date("2008-08-01") & anchor_date <= as.Date("2009-04-01")]
cat(sprintf("  STR_1715 cum: %+.2f%%%%\n", 100 * (prod(1 + gfc$ret_L5_V5) - 1)))
for (v in variants) {
  rcol <- paste0("ret_", v)
  cum_hyb <- prod(1 + gfc[[rcol]]) - 1
  cat(sprintf("  %-5s    cum: %+.2f%%%% (edge %+.2fpp)\n",
              v, 100 * cum_hyb, 100 * (cum_hyb - (prod(1 + gfc$ret_L5_V5) - 1))))
}

# ── (6) ADMIT rank ──
cat(sprintf("\n━━━ ADMIT ranking (all 3 windows ADMIT_WEAK+) ━━━\n"))
admit_ranks <- data.table()
for (v in variants) {
  admit_count <- 0
  total_dSR <- 0
  min_dSR <- Inf
  for (win in c("full267", "adm255", "fx110")) {
    r <- results[[win]][[v]]
    if (r$dSR >= 0.05 && r$dMDD >= -0.01 && abs(r$harvey_t) > 1.5) admit_count <- admit_count + 1
    total_dSR <- total_dSR + r$dSR
    min_dSR <- min(min_dSR, r$dSR)
  }
  admit_ranks <- rbind(admit_ranks, data.table(
    variant = v,
    admit_count = admit_count,
    avg_dSR = round(total_dSR / 3, 4),
    min_dSR = round(min_dSR, 4)
  ))
}
setorder(admit_ranks, -admit_count, -avg_dSR)
print(admit_ranks)

# ── (7) Save ──
out <- list(
  variants_tested = variants,
  full267_metrics = lapply(results$full267, function(x) if (is.list(x)) list(m = as.list(x$m), dSR = x$dSR, dMDD = x$dMDD, dCAGR = x$dCAGR, harvey_t = x$harvey_t) else as.list(x)),
  adm255_metrics = lapply(results$adm255, function(x) if (is.list(x)) list(m = as.list(x$m), dSR = x$dSR, dMDD = x$dMDD, dCAGR = x$dCAGR, harvey_t = x$harvey_t) else as.list(x)),
  fx110_metrics = lapply(results$fx110, function(x) if (is.list(x)) list(m = as.list(x$m), dSR = x$dSR, dMDD = x$dMDD, dCAGR = x$dCAGR, harvey_t = x$harvey_t) else as.list(x)),
  admit_ranks = admit_ranks,
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "gfc_resilient_variants.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/gfc_resilient_variants.json\n", EVAL_DIR))

# Chart: NAV
nav_dt <- panel[, .(anchor_date,
                     STR_1715 = cumprod(1 + ret_L5_V5),
                     V0 = cumprod(1 + ret_V0),
                     V1a = cumprod(1 + ret_V1a),
                     V1b = cumprod(1 + ret_V1b),
                     V2 = cumprod(1 + ret_V2),
                     V3 = cumprod(1 + ret_V3))]
nav_long <- melt(nav_dt, id.vars = "anchor_date", variable.name = "Variant", value.name = "NAV")
g <- ggplot(nav_long, aes(x = anchor_date, y = NAV, color = Variant)) +
  geom_line(linewidth = 0.6) + scale_y_log10() +
  labs(title = "GFC-resilient hybrid variants (267m, log NAV)",
       subtitle = sprintf("Best by avg ΔSR: %s (%+.3f)",
                          admit_ranks$variant[1], admit_ranks$avg_dSR[1]),
       x = NULL, y = "NAV (log)") +
  theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "22_gfc_resilient.png"),
       plot = g, width = 13, height = 6, dpi = 120)
cat(sprintf("[Chart 22] %s/22_gfc_resilient.png\n", CHART_DIR))

cat("\n[DONE]\n")
