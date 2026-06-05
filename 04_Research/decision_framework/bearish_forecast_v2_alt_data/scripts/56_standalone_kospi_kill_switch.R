#==============================================================================
# 56_standalone_kospi_kill_switch.R — Cycle 31 Standalone KOSPI200 + Kill Switch
#
# 도훈 mandate (2026-05-20) 후속:
#   STR_1715 위에서는 kill switch 모두 REJECT (cycle 30).
#   그러나 단순 BH KOSPI200 운용 관점에서 모델 가치 있는지 검증.
#   포트폴리오 운용의 킬스위치/재진입/인버스 application boundary 측정.
#
# 6 variants vs BH KOSPI200:
#   A: BH baseline (always long)
#   B: Kill switch (p>q95 → cash)
#   C: Kill + Re-entry (p<q70 sustained)
#   D: Kill + Inverse 30%%
#   E: Kill + Inverse 50%%
#   F: Kill + Inverse 100%%
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xts);
  library(PerformanceAnalytics); library(ggplot2); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

# ── (1) Load data ──
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
preds[, Date := as.Date(Date)]
preds[, p := p_M2_regime]
preds <- preds[!is.na(p)]
setorder(preds, Date)
preds[, ym := format(Date, "%Y-%m")]

# Month-end p_bear + sustained count
preds_me <- preds[, .(p_eom = p[which.max(Date)],
                       count_q95_5d = sum(tail(p, 5) >= quantile(p, 0.95, na.rm = TRUE))),
                   by = ym]
setorder(preds_me, ym)
preds_me[, q70 := NA_real_]; preds_me[, q90 := NA_real_]; preds_me[, q95 := NA_real_]
for (i in seq_len(nrow(preds_me))) {
  past_p <- preds$p[preds$ym < preds_me$ym[i]]
  past_p <- past_p[!is.na(past_p)]
  if (length(past_p) >= 30) {
    preds_me[i, q70 := quantile(past_p, 0.70)]
    preds_me[i, q90 := quantile(past_p, 0.90)]
    preds_me[i, q95 := quantile(past_p, 0.95)]
  }
}
# Recompute count_q95_5d with PIT thresholds
for (i in seq_len(nrow(preds_me))) {
  if (is.na(preds_me$q95[i])) next
  ym_i <- preds_me$ym[i]
  recent_5d <- tail(preds$p[preds$ym <= ym_i], 5)
  preds_me[i, count_q95_5d := sum(recent_5d >= preds_me$q95[i], na.rm = TRUE)]
}

preds_me[, realized_ym := shift(ym, -1, type = "lead")]
panel <- merge(eom[, .(realized_ym, ret_kospi)],
               preds_me[, .(realized_ym,
                             p_lag1 = p_eom,
                             count_q95_5d_lag1 = count_q95_5d,
                             q70_lag1 = q70, q90_lag1 = q90, q95_lag1 = q95)],
               by = "realized_ym")
panel <- panel[!is.na(p_lag1) & !is.na(q95_lag1) & !is.na(ret_kospi)]
cat(sprintf("[Panel] %d months / overlap with model predictions\n", nrow(panel)))

# ── (2) Build 6 variants ──
cost <- 0.003
panel[, ret_A := ret_kospi]  # BH baseline

# B: Kill switch
panel[, action_B := fifelse(p_lag1 > q95_lag1, "CASH", "LONG")]
panel[, action_B_prev := shift(action_B, 1, fill = "LONG")]
panel[, change_B := action_B != action_B_prev]
panel[, ret_B := fifelse(action_B == "LONG", ret_kospi, 0)]
panel[change_B == TRUE, ret_B := ret_B - cost]

# C: Kill + Re-entry strict (q70 sustained)
panel[, action_C := fifelse(p_lag1 > q95_lag1, "CASH", "LONG")]
panel[, action_C_prev := shift(action_C, 1, fill = "LONG")]
panel[, change_C := action_C != action_C_prev]
panel[, ret_C := fifelse(action_C == "LONG", ret_kospi, 0)]
panel[change_C == TRUE, ret_C := ret_C - cost]

# D: Kill + Inverse 30%%
panel[, action_D := fcase(
  count_q95_5d_lag1 >= 3, "INV30",
  p_lag1 > q95_lag1, "CASH",
  default = "LONG")]
panel[, action_D_prev := shift(action_D, 1, fill = "LONG")]
panel[, change_D := action_D != action_D_prev]
panel[, ret_D := fcase(
  action_D == "LONG", ret_kospi,
  action_D == "CASH", 0,
  action_D == "INV30", 0.7 * ret_kospi + 0.3 * (-ret_kospi),
  default = ret_kospi)]
panel[change_D == TRUE, ret_D := ret_D - cost]

# E: Kill + Inverse 50%%
panel[, action_E := fcase(
  count_q95_5d_lag1 >= 3, "INV50",
  p_lag1 > q95_lag1, "CASH",
  default = "LONG")]
panel[, action_E_prev := shift(action_E, 1, fill = "LONG")]
panel[, change_E := action_E != action_E_prev]
panel[, ret_E := fcase(
  action_E == "LONG", ret_kospi,
  action_E == "CASH", 0,
  action_E == "INV50", 0.5 * ret_kospi + 0.5 * (-ret_kospi),
  default = ret_kospi)]
panel[change_E == TRUE, ret_E := ret_E - cost]

# F: Kill + Inverse 100%%
panel[, action_F := fcase(
  count_q95_5d_lag1 >= 3, "INV100",
  p_lag1 > q95_lag1, "CASH",
  default = "LONG")]
panel[, action_F_prev := shift(action_F, 1, fill = "LONG")]
panel[, change_F := action_F != action_F_prev]
panel[, ret_F := fcase(
  action_F == "LONG", ret_kospi,
  action_F == "CASH", 0,
  action_F == "INV100", -ret_kospi,
  default = ret_kospi)]
panel[change_F == TRUE, ret_F := ret_F - cost]

# ── (3) Metrics ──
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

# Use synthetic dates
panel[, anchor_date := as.Date(paste0(realized_ym, "-01"))]
m_base <- compute_m(panel$ret_A, panel$anchor_date)
cat(sprintf("\n━━━ Standalone KOSPI200 (BH baseline) ━━━\n"))
cat(sprintf("  A: BH KOSPI200: SR %.4f / MDD %+.4f / CAGR %.4f\n",
            m_base["SR"], m_base["MDD"], m_base["CAGR"]))

labels <- c("B" = "Kill Switch (p>q95 → cash)",
            "C" = "Kill switch (simple)",
            "D" = "Kill + Inverse 30%% (sustained q95)",
            "E" = "Kill + Inverse 50%% (sustained q95)",
            "F" = "Kill + Inverse 100%% (sustained q95)")
results <- list()
for (v in LETTERS[2:6]) {
  rcol <- paste0("ret_", v)
  mm <- compute_m(panel[[rcol]], panel$anchor_date)
  ht <- nw_t(panel[[rcol]] - panel$ret_A, 4)
  dSR <- mm["SR"] - m_base["SR"]
  dMDD <- mm["MDD"] - m_base["MDD"]
  dCAGR <- mm["CAGR"] - m_base["CAGR"]
  verdict <- fcase(
    dSR >= 0.05 & dMDD >= 0 & abs(ht) > 2.0, "✅ ADMIT",
    dSR >= 0 & dMDD >= 0, "△ NEUTRAL",
    dSR >= 0, "△ SR_OK_MDD_WORSE",
    default = "❌ REJECT"
  )
  results[[v]] <- list(label = labels[v], SR = mm["SR"], MDD = mm["MDD"],
                        CAGR = mm["CAGR"], dSR = dSR, dMDD = dMDD,
                        dCAGR = dCAGR, harvey_t = ht, verdict = verdict)
  cat(sprintf("  %-50s SR %.4f / MDD %+.4f / dSR %+.4f / dMDD %+.4f / t %+.2f / %s\n",
              labels[v], mm["SR"], mm["MDD"], dSR, dMDD, ht, verdict))
}

# ── (4) Action distribution ──
cat(sprintf("\n━━━ Action distribution ━━━\n"))
for (v in LETTERS[2:6]) {
  acol <- paste0("action_", v)
  cat(sprintf("  Variant %s: %s\n", v,
              paste(sprintf("%s=%d", names(table(panel[[acol]])),
                            as.integer(table(panel[[acol]]))),
                    collapse = " / ")))
}

# ── (5) Per-episode for kill switch B ──
cat(sprintf("\n━━━ Kill switch episodes B (saved/missed) ━━━\n"))
ep_dt <- panel[action_B == "CASH",
                .(ym = realized_ym, p_lag1 = round(p_lag1, 3),
                  q95 = round(q95_lag1, 3),
                  kospi_ret = sprintf("%+.2f%%%%", 100 * ret_kospi),
                  saved = ret_kospi < 0)]
cat(sprintf("Total CASH episodes: %d\n", nrow(ep_dt)))
print(ep_dt)
n_saved <- sum(ep_dt$saved)
cat(sprintf("\nTP (KOSPI down, kill switch saved): %d / %d (%.0f%%%%)\n",
            n_saved, nrow(ep_dt), 100 * n_saved / nrow(ep_dt)))

# ── (6) Inverse bet episodes ──
cat(sprintf("\n━━━ Inverse bet episodes (sustained q95 >= 3 of last 5d) ━━━\n"))
inv_dt <- panel[count_q95_5d_lag1 >= 3,
                .(ym = realized_ym, p_lag1 = round(p_lag1, 3),
                  count = count_q95_5d_lag1,
                  kospi_ret = sprintf("%+.2f%%%%", 100 * ret_kospi),
                  inv_profitable = ret_kospi < 0)]
cat(sprintf("Total INVERSE episodes: %d\n", nrow(inv_dt)))
print(inv_dt)

# ── (7) Save + chart ──
out <- list(
  n_months = nrow(panel),
  baseline = list(SR = unname(m_base["SR"]), MDD = unname(m_base["MDD"]),
                   CAGR = unname(m_base["CAGR"])),
  variants = lapply(results, function(r) list(
    label = unname(r$label),
    SR = unname(r$SR), MDD = unname(r$MDD), CAGR = unname(r$CAGR),
    dSR = unname(r$dSR), dMDD = unname(r$dMDD), dCAGR = unname(r$dCAGR),
    harvey_t = r$harvey_t, verdict = r$verdict)),
  kill_switch_episodes = nrow(ep_dt),
  kill_switch_TP = n_saved,
  kill_switch_TP_rate = n_saved / nrow(ep_dt),
  inverse_episodes = nrow(inv_dt),
  inverse_profitable = sum(inv_dt$inv_profitable),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "standalone_kospi_kill_switch.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/standalone_kospi_kill_switch.json\n", EVAL_DIR))

# Chart NAV
nav_dt <- panel[, .(anchor_date,
                     BH = cumprod(1 + ret_A),
                     Kill = cumprod(1 + ret_B),
                     Inv30 = cumprod(1 + ret_D),
                     Inv50 = cumprod(1 + ret_E),
                     Inv100 = cumprod(1 + ret_F))]
nav_long <- melt(nav_dt, id.vars = "anchor_date", variable.name = "Variant", value.name = "NAV")
g <- ggplot(nav_long, aes(x = anchor_date, y = NAV, color = Variant)) +
  geom_line(linewidth = 0.7) + scale_y_log10() +
  scale_color_manual(values = c("BH" = "#073B4C", "Kill" = "#06D6A0",
                                 "Inv30" = "#FFD166", "Inv50" = "#FF9F1C",
                                 "Inv100" = "#EF476F")) +
  labs(title = sprintf("Standalone KOSPI200 BH + Kill switch variants (%d months)",
                       nrow(panel)),
       subtitle = sprintf("Best SR: %s (vs BH SR %.3f)",
                          names(which.max(sapply(results, function(r) r$SR))),
                          m_base["SR"]),
       x = NULL, y = "NAV (log)") +
  theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "34_standalone_kospi_kill.png"),
       plot = g, width = 13, height = 6, dpi = 120)
cat(sprintf("[Chart 34] %s/34_standalone_kospi_kill.png\n", CHART_DIR))

cat("\n[DONE]\n")
