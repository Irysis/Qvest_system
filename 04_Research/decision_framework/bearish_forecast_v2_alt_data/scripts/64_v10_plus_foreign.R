#==============================================================================
# 64_v10_plus_foreign.R — Cycle 40 V10 + 외국인 net 매매 (KOSPI)
#
# Source: .cache/investor/investor_kospi_*.csv (2020-01-02 ~ 2026-03-13)
# Data: Daily aggregate 외국인 net (단위 백만원)
#
# Variants:
#   V10 (current PRIMARY)
#   V_F_a: V10 OR foreign_net_5d < q10_past (외국인 매도 강할 때 union)
#   V_F_b: V10 AND foreign_net_5d < q30_past
#   V_F_c: V10 OR foreign_net_5d < q20_past (broader)
#   V_F_d: V10 OR cum_foreign_5d in worst 10pct (5d cumulative)
#   V_F_e: foreign alone (control)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xts);
  library(PerformanceAnalytics); library(ggplot2); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

# ── (1) Load 외국인 daily net ──
inv_files <- list.files(file.path(PROJECT_ROOT, ".cache/investor"),
                         pattern = "investor_kospi_.*\\.csv", full.names = TRUE)
inv_dt <- rbindlist(lapply(inv_files, fread), use.names = TRUE, fill = TRUE)
inv_dt[, Date := as.Date(Date)]
setorder(inv_dt, Date)
inv_dt <- inv_dt[, .(Date, foreign_net = 외국인)]  # 백만원
inv_dt[, ym := format(Date, "%Y-%m")]
cat(sprintf("[Foreign data] %d daily rows / %s ~ %s\n",
            nrow(inv_dt), as.character(min(inv_dt$Date)),
            as.character(max(inv_dt$Date))))

# ── (2) Per-month aggregates ──
# 5-day cumulative foreign net (5-day window ending at month-end)
inv_me <- inv_dt[, .(foreign_net_eom = foreign_net[which.max(Date)],
                      foreign_cum_5d = sum(tail(foreign_net, 5)),
                      foreign_min_5d = min(tail(foreign_net, 5)),
                      foreign_avg_5d = mean(tail(foreign_net, 5))),
                 by = ym]
setorder(inv_me, ym)

# PIT past quantiles (foreign_cum_5d 매도가 심할수록 작은 값)
inv_me[, fcum_q10 := NA_real_]  # bottom 10% (강한 매도)
inv_me[, fcum_q20 := NA_real_]
inv_me[, fcum_q30 := NA_real_]
for (i in seq_len(nrow(inv_me))) {
  past <- inv_me$foreign_cum_5d[seq_len(i - 1)]
  past <- past[!is.na(past)]
  if (length(past) >= 12) {
    inv_me[i, fcum_q10 := quantile(past, 0.10)]
    inv_me[i, fcum_q20 := quantile(past, 0.20)]
    inv_me[i, fcum_q30 := quantile(past, 0.30)]
  }
}
inv_me[, f_trigger_q10 := !is.na(fcum_q10) & foreign_cum_5d < fcum_q10]
inv_me[, f_trigger_q20 := !is.na(fcum_q20) & foreign_cum_5d < fcum_q20]
inv_me[, f_trigger_q30 := !is.na(fcum_q30) & foreign_cum_5d < fcum_q30]

# ── (3) Load V10 panel ──
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
preds[, Date := as.Date(Date)]; preds[, p := p_M2_regime]
preds <- preds[!is.na(p)]
setorder(preds, Date)
preds[, ym := format(Date, "%Y-%m")]

preds_me <- preds[, .(p_eom = p[which.max(Date)],
                       trend_5d = tail(p, 1) - p[max(1, length(p) - 5)]),
                  by = ym]
setorder(preds_me, ym)
preds_me[, q70 := NA_real_]
for (i in seq_len(nrow(preds_me))) {
  past_p <- preds$p[preds$ym < preds_me$ym[i]]
  past_p <- past_p[!is.na(past_p)]
  if (length(past_p) >= 30) preds_me[i, q70 := quantile(past_p, 0.70)]
}
preds_me[, count_5_q70 := 0L]
for (i in seq_len(nrow(preds_me))) {
  if (is.na(preds_me$q70[i])) next
  ym_i <- preds_me$ym[i]
  last_p_all <- preds$p[preds$ym <= ym_i]
  preds_me[i, count_5_q70 := sum(tail(last_p_all, 5) >= preds_me$q70[i], na.rm = TRUE)]
}

preds_me[, realized_ym := shift(ym, -1, type = "lead")]
inv_me[, realized_ym := shift(ym, -1, type = "lead")]

panel <- merge(eom[, .(realized_ym, ret_kospi)],
               preds_me[, .(realized_ym, p_eom, trend_5d, q70, count_5_q70)],
               by = "realized_ym")
panel <- merge(panel,
               inv_me[, .(realized_ym, foreign_cum_5d, fcum_q10, fcum_q20, fcum_q30,
                           f_trigger_q10, f_trigger_q20, f_trigger_q30)],
               by = "realized_ym")
panel <- panel[!is.na(p_eom) & !is.na(q70) & !is.na(ret_kospi) & !is.na(foreign_cum_5d)]
cat(sprintf("[Panel] %d months (V10 + 외국인 모두 가용)\n", nrow(panel)))

# ── (4) Variants ──
panel[, trig_V10 := count_5_q70 >= 4 & trend_5d > 0 & p_eom > q70]
panel[, trig_V_F_a := trig_V10 | f_trigger_q10]
panel[, trig_V_F_b := trig_V10 & f_trigger_q30]
panel[, trig_V_F_c := trig_V10 | f_trigger_q20]
panel[, trig_V_F_d := trig_V10 | f_trigger_q30]
panel[, trig_V_F_e := f_trigger_q10]  # control
panel[, trig_V_F_f := f_trigger_q20]  # control
panel[, trig_V_F_g := f_trigger_q30]  # control

# ── (5) Build returns ──
cost <- 0.003
build_kill <- function(trig_vec, cost = 0.003) {
  trig_prev <- shift(trig_vec, 1, fill = FALSE)
  change <- trig_vec != trig_prev
  ret <- ifelse(trig_vec, 0, panel$ret_kospi)
  ret[change] <- ret[change] - cost
  ret
}
for (v in c("V10", "V_F_a", "V_F_b", "V_F_c", "V_F_d",
             "V_F_e", "V_F_f", "V_F_g")) {
  tcol <- paste0("trig_", v); rcol <- paste0("ret_", v)
  panel[[rcol]] <- build_kill(panel[[tcol]])
}
panel[, ret_BH := ret_kospi]

# ── (6) Metrics ──
compute_m <- function(ret_vec, dates) {
  xret <- xts::xts(ret_vec, order.by = dates)
  ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
  c(SR = as.numeric(ann[3, 1]),
    MDD = -as.numeric(maxDrawdown(xret)),
    CAGR = as.numeric(ann[1, 1]))
}
nw_t <- function(x, lag = 4) {
  n <- length(x); xbar <- mean(x); resid <- x - xbar
  S <- sum(resid^2) / n
  for (l in seq_len(lag)) {
    w <- 1 - l / (lag + 1)
    S <- S + 2 * w * sum(resid[(l + 1):n] * resid[1:(n - l)]) / n
  }
  xbar / sqrt(S / n)
}

dates <- as.Date(paste0(panel$realized_ym, "-01"))
m_base <- compute_m(panel$ret_BH, dates)
cat(sprintf("\n━━━ BH baseline (%d months 외국인-period) ━━━\n", nrow(panel)))
cat(sprintf("  SR %.4f / MDD %+.4f / CAGR %.4f\n\n",
            m_base["SR"], m_base["MDD"], m_base["CAGR"]))

variants <- c("V10", "V_F_a", "V_F_b", "V_F_c", "V_F_d",
               "V_F_e", "V_F_f", "V_F_g")
descs <- c("V10 (current PRIMARY)",
            "V_F_a V10 OR foreign_q10 (strong sell UNION)",
            "V_F_b V10 AND foreign_q30 (any sell + V10)",
            "V_F_c V10 OR foreign_q20 (moderate UNION)",
            "V_F_d V10 OR foreign_q30 (broad UNION)",
            "V_F_e foreign_q10 alone (strong sell control)",
            "V_F_f foreign_q20 alone (moderate control)",
            "V_F_g foreign_q30 alone (mild control)")
results <- data.table()
for (i in seq_along(variants)) {
  v <- variants[i]
  rcol <- paste0("ret_", v); tcol <- paste0("trig_", v)
  mm <- compute_m(panel[[rcol]], dates)
  ht <- nw_t(panel[[rcol]] - panel$ret_BH, 4)
  trig <- panel[[tcol]]
  n_act <- sum(trig)
  prec <- if (n_act > 0) sum(trig & panel$ret_BH < 0) / n_act else NA

  results <- rbind(results, data.table(
    variant = v, description = descs[i],
    n_trigger = n_act,
    precision = if (is.na(prec)) NA_real_ else round(prec, 3),
    SR = round(mm["SR"], 4),
    MDD = round(mm["MDD"], 4),
    CAGR = round(mm["CAGR"], 4),
    dSR = round(mm["SR"] - m_base["SR"], 4),
    harvey_t = round(ht, 3)
  ))
}
setorder(results, -dSR)
print(results)

best <- results[1]
cat(sprintf("\n[Best] %s — dSR %+.4f / Harvey-t %+.3f / precision %.3f\n",
            best$variant, best$dSR, best$harvey_t, best$precision))

# Walk-forward 36m for best
W <- 36
best_rcol <- paste0("ret_", best$variant)
if (nrow(panel) >= W + 5) {
  wf <- list()
  for (i in seq_len(nrow(panel) - W + 1)) {
    win <- panel[i:(i + W - 1)]
    m_b <- compute_m(win$ret_BH, dates[i:(i + W - 1)])
    m_h <- compute_m(win[[best_rcol]], dates[i:(i + W - 1)])
    wf[[i]] <- data.table(win_end = dates[i + W - 1],
                          dSR = m_h["SR"] - m_b["SR"])
  }
  wf_dt <- rbindlist(wf)
  cat(sprintf("\n━━━ Walk-forward 36m for %s ━━━\n", best$variant))
  cat(sprintf("  Windows: %d / Win rate %.0f%%%% / median dSR %+.4f\n",
              nrow(wf_dt), 100 * mean(wf_dt$dSR > 0), median(wf_dt$dSR)))
} else {
  cat(sprintf("\nNot enough data for 36m WF (n=%d < %d)\n", nrow(panel), W + 5))
}

# Save + chart
out <- list(
  baseline_BH = list(SR = unname(m_base["SR"]), MDD = unname(m_base["MDD"]),
                      CAGR = unname(m_base["CAGR"])),
  variants = results,
  best = list(variant = best$variant, dSR = best$dSR,
               SR = best$SR, MDD = best$MDD, harvey_t = best$harvey_t),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "v10_plus_foreign.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/v10_plus_foreign.json\n", EVAL_DIR))

# NAV top 3
top3 <- results[1:3]
nav_dt <- panel[, .(date = dates, BH = cumprod(1 + ret_BH))]
for (v in top3$variant) {
  nav_dt[, (v) := cumprod(1 + panel[[paste0("ret_", v)]])]
}
nav_long <- melt(nav_dt, id.vars = "date", variable.name = "Variant", value.name = "NAV")
g <- ggplot(nav_long, aes(x = date, y = NAV, color = Variant)) +
  geom_line(linewidth = 0.7) + scale_y_log10() +
  labs(title = sprintf("V10 + 외국인 net — TOP 3 (Best %s dSR %+.3f)",
                       best$variant, best$dSR),
       x = NULL, y = "NAV (log)") +
  theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "41_v10_plus_foreign.png"),
       plot = g, width = 13, height = 6, dpi = 120)
cat(sprintf("[Chart 41] %s/41_v10_plus_foreign.png\n", CHART_DIR))

cat("\n[DONE]\n")
