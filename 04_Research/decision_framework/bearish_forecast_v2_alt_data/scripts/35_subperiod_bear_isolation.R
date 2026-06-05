#==============================================================================
# 35_subperiod_bear_isolation.R — Cycle 5.1 Sub-period bear market isolation
#
# Hypothesis: 110m overall은 KOSPI200 강세장 dominant → standalone LOSE.
# 그러나 bear sub-period에서만 isolation해보면 모델의 "bear hedge" 가치 입증
# 가능성. 모델 위치: bear market overlay / hedging instrument.
#
# Bear definition (3 variants):
#   B1 (programmatic): KOSPI200 6m rolling max-drawdown ≤ -10%%
#   B2 (regime label): preds$regime == "bear" months
#   B3 (manual): 4 명시 bear periods (2018-10~12, 2020-01~03, 2022-01~10, 2025-09~)
#
# Strategies (per cycle 4.1):
#   V_S1 (long-only switch p<q50), V_S5 (regime cond), V_S3 (LCI asym)
#
# Compare per sub-period:
#   - Buy-and-hold KOSPI200 (in sub-period)
#   - Each timing variant (in sub-period)
#   - Bear hedge value = ΔSR or Δret per period
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xts);
  library(PerformanceAnalytics); library(ggplot2); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

# ── (1) Load monthly returns + p_bear + regime (same as cycle 4) ──
bm <- as.data.table(read_parquet(
  file.path(WS, "outputs/02_targets/targets_full.parquet")))
bm[, Date := as.Date(Date)]; bm[, ym := format(Date, "%Y-%m")]
setorder(bm, Date)
eom <- bm[, .(Date_eom = max(Date),
              close_eom = BM_Close[which.max(Date)]), by = ym]
setorder(eom, ym)
eom[, ret_kospi := shift(close_eom, n = 1L, type = "lead") / close_eom - 1]
eom[, ym_target := shift(ym, n = 1L, type = "lead")]

preds <- as.data.table(read_parquet(
  file.path(WS, "outputs/03_models/dynamic_ensemble/predictions_dynamic_y_tail_q15.parquet")))
preds[, Date := as.Date(Date)]; preds[, p := p_M2_regime]
preds <- preds[!is.na(p)]; preds[, ym := format(Date, "%Y-%m")]
me <- preds[, .SD[which.max(Date)], by = ym]
setorder(me, Date)

panel <- merge(eom, me[, .(ym, p, regime)], by = "ym", all.x = TRUE)
setorder(panel, ym)

# Re-derive PIT quantiles
expanding_q <- function(x, dates, q = 0.5) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    past <- x[dates < dates[i]]; past <- past[!is.na(past)]
    if (length(past) >= 12) out[i] <- as.numeric(quantile(past, q, na.rm = TRUE))
  }
  out
}
panel <- panel[!is.na(p)]
panel[, q50 := expanding_q(p, Date_eom, 0.50)]
panel[, q70 := expanding_q(p, Date_eom, 0.70)]
panel[, q90 := expanding_q(p, Date_eom, 0.90)]

# Position variants (per cycle 4)
panel[, pos_S1 := fifelse(!is.na(q50) & p < q50, 1.0, 0.0)]
panel[, pos_S3 := fcase(is.na(q70) | is.na(q90), 0.0,
                         p < q70, 1.0,
                         p > q90, -1.0,
                         default = 0.0)]
panel[, pos_S5 := fcase(regime == "bull", 1.0,
                         regime == "bear", 0.0,
                         default = 0.5)]

# Returns with 30bps round-trip cost
for (v in c("S1", "S3", "S5")) {
  pcol <- paste0("pos_", v); tcol <- paste0("turn_", v); rcol <- paste0("ret_", v)
  panel[, (tcol) := abs(get(pcol) - shift(get(pcol), 1, fill = 0))]
  panel[, (rcol) := get(pcol) * ret_kospi - get(tcol) * 0.003]
}
panel[, ret_BH := ret_kospi]
panel <- panel[!is.na(ret_kospi)]

# ── (2) Bear definition B1: 6m rolling max drawdown ≤ -10%% ──
panel[, kospi_log_ret := log(1 + ret_kospi)]
panel[, kospi_log_cum := cumsum(kospi_log_ret)]
panel[, kospi_lvl := exp(kospi_log_cum)]
# 6m rolling DD computed retrospectively
panel[, kospi_6m_max := frollapply(kospi_lvl, 6, max, align = "right")]
panel[, kospi_dd_6m := kospi_lvl / kospi_6m_max - 1]
panel[, bear_B1 := !is.na(kospi_dd_6m) & kospi_dd_6m <= -0.10]

# Bear B2: regime label
panel[, bear_B2 := regime == "bear"]

# Bear B3: manual 4 periods
panel[, bear_B3 := (ym >= "2018-10" & ym <= "2018-12") |
                    (ym >= "2020-01" & ym <= "2020-04") |
                    (ym >= "2022-01" & ym <= "2022-10") |
                    (ym >= "2025-09" & ym <= "2026-04")]

cat(sprintf("━━━ Bear definition coverage (out of %d months) ━━━\n", nrow(panel)))
cat(sprintf("  B1 (6m rolling DD ≤ -10%%%%): %d months\n", sum(panel$bear_B1)))
cat(sprintf("  B2 (regime == 'bear'): %d months\n", sum(panel$bear_B2, na.rm=TRUE)))
cat(sprintf("  B3 (manual 4 periods): %d months\n", sum(panel$bear_B3)))

# ── (3) Per-bear-definition metric comparison ──
compute_m <- function(ret_vec, dates, label) {
  ok <- !is.na(ret_vec) & is.finite(ret_vec)
  r <- ret_vec[ok]; d <- dates[ok]
  if (length(r) < 6) return(NULL)
  xret <- xts::xts(r, order.by = d)
  ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
  mdd <- maxDrawdown(xret)
  cum <- prod(1 + r) - 1
  list(label = label, n = length(r),
       cum_ret = round(cum, 4),
       CAGR = round(as.numeric(ann[1, 1]), 4),
       Sharpe = round(as.numeric(ann[3, 1]), 4),
       MDD = round(-as.numeric(mdd), 4),
       win_rate = round(mean(r > 0), 3))
}

cat(sprintf("\n━━━ Bear sub-period metrics ━━━\n\n"))
all_res <- list()
for (bdef in c("B1", "B2", "B3")) {
  bcol <- paste0("bear_", bdef)
  sub <- panel[get(bcol) == TRUE]
  if (nrow(sub) < 6) { cat(sprintf("  %s: only %d months, skipped\n", bdef, nrow(sub))); next }
  cat(sprintf("━━ Bear def %s (n=%d) ━━\n", bdef, nrow(sub)))
  res <- list()
  res$BH <- compute_m(sub$ret_BH, sub$Date_eom, "Buy-and-hold")
  res$S1 <- compute_m(sub$ret_S1, sub$Date_eom, "V_S1 (p<q50)")
  res$S3 <- compute_m(sub$ret_S3, sub$Date_eom, "V_S3 LCI asym")
  res$S5 <- compute_m(sub$ret_S5, sub$Date_eom, "V_S5 regime")
  dt_res <- rbindlist(lapply(res, function(x) {
    data.table(variant = x$label, n = x$n,
               cum_ret = x$cum_ret, CAGR = x$CAGR,
               Sharpe = x$Sharpe, MDD = x$MDD, win_rate = x$win_rate)
  }))
  print(dt_res)
  cat(sprintf("\n"))
  all_res[[bdef]] <- res
}

# ── (4) Manual 4-period detail ──
cat(sprintf("━━━ Manual periods detail (B3) ━━━\n\n"))
manual_periods <- list(
  "2018-10~12_USrate" = c("2018-10", "2018-12"),
  "2020-01~04_COVID" = c("2020-01", "2020-04"),
  "2022-01~10_Russia" = c("2022-01", "2022-10"),
  "2025-09~2026-04_current" = c("2025-09", "2026-04")
)
per_period <- data.table()
for (name in names(manual_periods)) {
  rng <- manual_periods[[name]]
  sub <- panel[ym >= rng[1] & ym <= rng[2]]
  if (nrow(sub) < 2) next
  cat(sprintf("◆ %s (n=%d months)\n", name, nrow(sub)))
  ret_cum <- list(
    BH = prod(1 + sub$ret_BH) - 1,
    S1 = prod(1 + sub$ret_S1) - 1,
    S3 = prod(1 + sub$ret_S3) - 1,
    S5 = prod(1 + sub$ret_S5) - 1
  )
  cat(sprintf("  BH cum: %+.2f%% / S1 cum: %+.2f%% / S3 cum: %+.2f%% / S5 cum: %+.2f%%\n",
              100 * ret_cum$BH, 100 * ret_cum$S1, 100 * ret_cum$S3, 100 * ret_cum$S5))
  per_period <- rbind(per_period, data.table(
    period = name, n = nrow(sub),
    cum_BH = ret_cum$BH, cum_S1 = ret_cum$S1,
    cum_S3 = ret_cum$S3, cum_S5 = ret_cum$S5,
    edge_S1 = ret_cum$S1 - ret_cum$BH,
    edge_S3 = ret_cum$S3 - ret_cum$BH,
    edge_S5 = ret_cum$S5 - ret_cum$BH))
}
cat(sprintf("\n━━━ Per-period edge vs BH (positive = model wins) ━━━\n"))
print(per_period)

# ── (5) Bear hedge value verdict ──
cat(sprintf("\n━━━ Bear Hedge Verdict ━━━\n"))
for (bdef in names(all_res)) {
  res <- all_res[[bdef]]
  best_v <- NULL; best_edge <- -Inf
  for (v in c("S1", "S3", "S5")) {
    if (is.null(res[[v]])) next
    edge <- res[[v]]$cum_ret - res$BH$cum_ret
    if (edge > best_edge) { best_edge <- edge; best_v <- v }
  }
  if (is.null(best_v)) next
  if (best_edge > 0.05) {
    cat(sprintf("  ✅ %s: BEST V_%s edge %+.2f%% vs BH — bear hedge value 입증\n",
                bdef, best_v, 100 * best_edge))
  } else if (best_edge > 0) {
    cat(sprintf("  △ %s: BEST V_%s edge %+.2f%% vs BH — marginal hedge\n",
                bdef, best_v, 100 * best_edge))
  } else {
    cat(sprintf("  ❌ %s: BEST V_%s edge %+.2f%% vs BH — bear hedge value 없음\n",
                bdef, best_v, 100 * best_edge))
  }
}

# ── (6) Save ──
out <- list(
  bear_coverage = list(B1 = sum(panel$bear_B1),
                        B2 = sum(panel$bear_B2, na.rm = TRUE),
                        B3 = sum(panel$bear_B3)),
  per_def_metrics = all_res,
  manual_period_detail = per_period,
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "subperiod_bear_isolation.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/subperiod_bear_isolation.json\n", EVAL_DIR))

# ── (7) Chart ──
if (nrow(per_period) > 0) {
  edge_long <- melt(per_period[, .(period, S1 = edge_S1, S3 = edge_S3, S5 = edge_S5)],
                    id.vars = "period", variable.name = "variant", value.name = "edge")
  g <- ggplot(edge_long, aes(x = period, y = 100 * edge, fill = variant)) +
    geom_col(position = "dodge", alpha = 0.85) +
    geom_hline(yintercept = 0, color = "gray60") +
    scale_fill_manual(values = c("S1" = "#06D6A0", "S3" = "#EF476F", "S5" = "#FFD166")) +
    labs(title = "Bear sub-period edge vs Buy-and-hold (cum ret diff)",
         subtitle = "Positive = model timing wins / Negative = BH wins",
         x = NULL, y = "Edge (cum ret diff, %%)") +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_text(angle = 30, hjust = 1))
  ggsave(file.path(CHART_DIR, "16_subperiod_bear.png"),
         plot = g, width = 13, height = 5.5, dpi = 120)
  cat(sprintf("[Chart 16] %s/16_subperiod_bear.png\n", CHART_DIR))
}

cat("\n[DONE]\n")
