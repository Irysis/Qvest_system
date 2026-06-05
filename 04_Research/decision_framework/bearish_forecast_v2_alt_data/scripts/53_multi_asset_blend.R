#==============================================================================
# 53_multi_asset_blend.R — Cycle 24 Multi-asset bear hedge (4-asset)
#
# Active state variants:
#   A: KOSPI (PRIMARY)
#   B: Bond only
#   C: Gold only
#   D: US Treasury only
#   E: 4-way blend (25% each)
#   F: Risk-parity-ish (KOSPI 30 + Bond 30 + Gold 20 + UST 20)
#
# All using V1a+V3 framework (trigger 2m/-5%%, trig_run≤2, dynamic position)
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

# ── (1) Load ALL data ──
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

# Bond
bond <- fread(file.path(WS, "outputs/01_data/kr10y_bond_148070_monthly.csv"))
bond[, Date := as.Date(Date)]; bond[, ym := format(Date, "%Y-%m")]
bond[, ret_bond := c(NA, diff(Close) / head(Close, -1))]
bond[, realized_ym := ym]

# Gold + UST
multi <- fread(file.path(WS, "outputs/01_data/multi_asset_close_monthly.csv"))
multi[, Date := as.Date(Date)]; multi[, ym := format(Date, "%Y-%m")]
setorder(multi, Date)
multi[, ret_gold := c(NA, diff(Gold_132030) / head(Gold_132030, -1))]
multi[, ret_ust := c(NA, diff(UST_153130) / head(UST_153130, -1))]
multi[, realized_ym := ym]

# Merge
panel <- merge(baseline, eom[, .(realized_ym, ret_kospi)],
               by = "realized_ym", all.x = TRUE)
panel <- merge(panel, bond[, .(realized_ym, ret_bond)],
               by = "realized_ym", all.x = TRUE)
panel <- merge(panel, multi[, .(realized_ym, ret_gold, ret_ust)],
               by = "realized_ym", all.x = TRUE)
setorder(panel, anchor_date)

cat(sprintf("[Panel] %d months / Bond: %d / Gold: %d / UST: %d\n",
            nrow(panel),
            sum(!is.na(panel$ret_bond)),
            sum(!is.na(panel$ret_gold)),
            sum(!is.na(panel$ret_ust))))

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
panel[, pos_factor := pmax(0.0, 0.7 - 3.0 * pmax(0, -(dd_lag + 0.10)))]

# ── (3) Build 6 active state variants ──
# Replace NA with 0 (no exposure when data unavailable)
for (col in c("ret_kospi", "ret_bond", "ret_gold", "ret_ust")) {
  panel[is.na(get(col)), (col) := 0]
}

panel[, ret_act_A := pos_factor * ret_kospi]                              # KOSPI only
panel[, ret_act_B := pos_factor * ret_bond]                               # Bond only
panel[, ret_act_C := pos_factor * ret_gold]                               # Gold only
panel[, ret_act_D := pos_factor * ret_ust]                                # UST only
panel[, ret_act_E := pos_factor * (0.25 * ret_kospi + 0.25 * ret_bond +
                                     0.25 * ret_gold + 0.25 * ret_ust)]    # 4-way EW
panel[, ret_act_F := pos_factor * (0.30 * ret_kospi + 0.30 * ret_bond +
                                     0.20 * ret_gold + 0.20 * ret_ust)]    # Risk-parity-ish

panel[, state := fifelse(active, "BEAR", "BULL")]
panel[, state_change := state != shift(state, 1, fill = "BULL")]
for (v in LETTERS[1:6]) {
  rcol <- paste0("ret_act_", v); hcol <- paste0("ret_hyb_", v)
  panel[, (hcol) := fifelse(active, get(rcol), ret_L5_V5)]
  panel[state_change == TRUE, (hcol) := get(hcol) - 0.003]
}

# ── (4) Eval (gold-available period: 2010-10+, UST: 2012-02+) ──
pfx <- panel[!is.na(ret_kospi) & anchor_date >= as.Date("2012-03-01")]
cat(sprintf("Eval period: %s ~ %s (n=%d, UST-available)\n",
            as.character(min(pfx$anchor_date)),
            as.character(max(pfx$anchor_date)), nrow(pfx)))

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
cat(sprintf("\n━━━ 6-variant Multi-asset hedge comparison ━━━\n"))
cat(sprintf("  Baseline STR_1715: SR %.4f / MDD %+.4f / CAGR %.4f\n\n",
            m_base["SR"], m_base["MDD"], m_base["CAGR"]))

labels <- c("A" = "KOSPI only (PRIMARY)",
            "B" = "Bond only",
            "C" = "Gold only",
            "D" = "US Treasury only",
            "E" = "4-way EW (25%% each)",
            "F" = "Risk-parity (K30 B30 G20 U20)")
results <- list()
for (v in LETTERS[1:6]) {
  rcol <- paste0("ret_hyb_", v)
  mm <- compute_m(pfx[[rcol]], pfx$anchor_date)
  ht <- nw_t(pfx[[rcol]] - pfx$ret_L5_V5, 4)
  dSR <- mm["SR"] - m_base["SR"]
  dMDD <- mm["MDD"] - m_base["MDD"]
  results[[v]] <- list(label = labels[v], SR = mm["SR"], MDD = mm["MDD"],
                        CAGR = mm["CAGR"], dSR = dSR, dMDD = dMDD,
                        harvey_t = ht)
  cat(sprintf("  %-6s : SR %.4f / MDD %+.4f / CAGR %.4f / dSR %+.4f / dMDD %+.4f / t %+.3f\n",
              v, mm["SR"], mm["MDD"], mm["CAGR"], dSR, dMDD, ht))
}

# ── (5) Ranking ──
cat(sprintf("\n━━━ Ranking by SR ━━━\n"))
sr_rank <- sapply(LETTERS[1:6], function(v) results[[v]]$SR)
names(sr_rank) <- LETTERS[1:6]
sr_rank_sorted <- sort(sr_rank, decreasing = TRUE)
for (i in seq_along(sr_rank_sorted)) {
  v <- names(sr_rank_sorted)[i]
  cat(sprintf("  %d. %s: SR %.4f / dSR %+.4f / MDD %+.4f\n",
              i, labels[v], results[[v]]$SR, results[[v]]$dSR,
              results[[v]]$MDD))
}

cat(sprintf("\n━━━ Ranking by MDD (less negative = better) ━━━\n"))
mdd_rank <- sapply(LETTERS[1:6], function(v) results[[v]]$MDD)
names(mdd_rank) <- LETTERS[1:6]
mdd_rank_sorted <- sort(mdd_rank, decreasing = TRUE)  # less negative first
for (i in seq_along(mdd_rank_sorted)) {
  v <- names(mdd_rank_sorted)[i]
  cat(sprintf("  %d. %s: MDD %+.4f / SR %.4f / dSR %+.4f\n",
              i, labels[v], results[[v]]$MDD, results[[v]]$SR,
              results[[v]]$dSR))
}

# Best for different objectives
best_sr <- names(which.max(sr_rank))
best_mdd <- names(which.max(mdd_rank))
cat(sprintf("\n━━━ Best by objective ━━━\n"))
cat(sprintf("  Max SR (return-oriented): %s — %s\n", best_sr, labels[best_sr]))
cat(sprintf("  Min MDD (risk-averse): %s — %s\n", best_mdd, labels[best_mdd]))

# ── (6) Save ──
out <- list(
  baseline = list(SR = unname(m_base["SR"]), MDD = unname(m_base["MDD"]),
                   CAGR = unname(m_base["CAGR"])),
  variants = lapply(results, function(r) list(label = unname(r$label),
                                                SR = unname(r$SR),
                                                MDD = unname(r$MDD),
                                                CAGR = unname(r$CAGR),
                                                dSR = unname(r$dSR),
                                                dMDD = unname(r$dMDD),
                                                harvey_t = r$harvey_t)),
  best_SR = best_sr, best_MDD = best_mdd,
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "multi_asset_blend.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/multi_asset_blend.json\n", EVAL_DIR))

# Chart
nav_dt <- pfx[, .(anchor_date,
                   Baseline = cumprod(1 + ret_L5_V5),
                   A_KOSPI = cumprod(1 + ret_hyb_A),
                   B_Bond = cumprod(1 + ret_hyb_B),
                   C_Gold = cumprod(1 + ret_hyb_C),
                   D_UST = cumprod(1 + ret_hyb_D),
                   E_EW = cumprod(1 + ret_hyb_E),
                   F_RP = cumprod(1 + ret_hyb_F))]
nav_long <- melt(nav_dt, id.vars = "anchor_date", variable.name = "Variant", value.name = "NAV")
g <- ggplot(nav_long, aes(x = anchor_date, y = NAV, color = Variant)) +
  geom_line(linewidth = 0.6) + scale_y_log10() +
  labs(title = "Multi-asset bear hedge — 6 variants (UST-available 2012-03~)",
       subtitle = sprintf("Best SR: %s | Best MDD: %s", best_sr, best_mdd),
       x = NULL, y = "NAV (log)") +
  theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "31_multi_asset.png"),
       plot = g, width = 13, height = 6, dpi = 120)
cat(sprintf("[Chart 31] %s/31_multi_asset.png\n", CHART_DIR))

cat("\n[DONE]\n")
