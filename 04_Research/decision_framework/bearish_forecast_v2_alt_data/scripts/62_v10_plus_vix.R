#==============================================================================
# 62_v10_plus_vix.R — Cycle 38 V10 + VIX 4-cond AND
#
# 도훈 mandate (2026-05-20):
#   "T+0 가용 데이터로 모델 강화"
#   VKOSPI 미가용 (Yahoo) → VIX (US fear) proxy 사용
#
# Variants (BH KOSPI base):
#   V10 (current PRIMARY): count_5_q70 ≥ 4 AND trend_5d > 0 AND p_eom > q70
#   V11 = V10 + VIX > VIX_q70_past (4-cond AND, strict)
#   V12 = V10 OR VIX_spike (union, more triggers)
#   V13 = V10 weighted by VIX (smooth combined signal)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xts);
  library(PerformanceAnalytics); library(ggplot2); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

# ── (1) Load ──
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

# VIX monthly
vix <- fread(file.path(WS, "outputs/01_data/vix_monthly.csv"))
vix[, Date := as.Date(Date)]; vix[, ym := format(Date, "%Y-%m")]
setorder(vix, Date)
# VIX threshold PIT past q70
vix[, vix_q70 := NA_real_]
vix[, vix_q90 := NA_real_]
for (i in seq_len(nrow(vix))) {
  past_v <- vix$VIX_Close[seq_len(i - 1)]
  past_v <- past_v[!is.na(past_v)]
  if (length(past_v) >= 12) {
    vix[i, vix_q70 := quantile(past_v, 0.70)]
    vix[i, vix_q90 := quantile(past_v, 0.90)]
  }
}
vix[, vix_trigger_q70 := !is.na(vix_q70) & VIX_Close > vix_q70]
vix[, vix_trigger_q90 := !is.na(vix_q90) & VIX_Close > vix_q90]

# Per-month aggregates (V10 ingredients)
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
# Merge VIX (lag = same realized_ym since VIX is monthly)
# VIX is published at the END of the month, available for next month's decision
vix_for_decision <- copy(vix)
vix_for_decision[, realized_ym := shift(ym, -1, type = "lead")]

panel <- merge(eom[, .(realized_ym, ret_kospi)],
               preds_me[, .(realized_ym, p_eom, trend_5d, q70, count_5_q70)],
               by = "realized_ym")
panel <- merge(panel,
               vix_for_decision[, .(realized_ym, VIX_Close, vix_q70,
                                     vix_trigger_q70, vix_trigger_q90)],
               by = "realized_ym")
panel <- panel[!is.na(p_eom) & !is.na(q70) & !is.na(ret_kospi) & !is.na(VIX_Close)]
cat(sprintf("[Panel] %d months (VIX-available)\n", nrow(panel)))

# ── (2) Define variants ──
# V10: count_5_q70 ≥ 4 AND trend_5d > 0 AND p_eom > q70
panel[, trig_V10 := count_5_q70 >= 4 & trend_5d > 0 & p_eom > q70]

# V11: V10 AND VIX > q70 (4-cond strict AND)
panel[, trig_V11_strict := trig_V10 & vix_trigger_q70]

# V12: V10 OR VIX_spike (q90)
panel[, trig_V12_union := trig_V10 | vix_trigger_q90]

# V13: V10 AND VIX (q90, very strict)
panel[, trig_V13_strict_q90 := trig_V10 & vix_trigger_q90]

# V14: VIX alone (control)
panel[, trig_V14_vix_only := vix_trigger_q70]

# ── (3) Build returns ──
cost <- 0.003
build_kill <- function(trig_vec, cost = 0.003) {
  trig_prev <- shift(trig_vec, 1, fill = FALSE)
  change <- trig_vec != trig_prev
  ret <- ifelse(trig_vec, 0, panel$ret_kospi)
  ret[change] <- ret[change] - cost
  ret
}
panel[, ret_V10 := build_kill(trig_V10)]
panel[, ret_V11 := build_kill(trig_V11_strict)]
panel[, ret_V12 := build_kill(trig_V12_union)]
panel[, ret_V13 := build_kill(trig_V13_strict_q90)]
panel[, ret_V14 := build_kill(trig_V14_vix_only)]
panel[, ret_BH := ret_kospi]

# ── (4) Metrics ──
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
cat(sprintf("\n━━━ BH baseline (VIX-period) ━━━\n  SR %.4f / MDD %+.4f / CAGR %.4f\n\n",
            m_base["SR"], m_base["MDD"], m_base["CAGR"]))

variants <- c("V10", "V11", "V12", "V13", "V14")
descs <- c("V10 3-cond AND (current PRIMARY)",
            "V11 V10 + VIX>q70 (4-cond strict AND)",
            "V12 V10 OR VIX>q90 (union)",
            "V13 V10 + VIX>q90 (very strict)",
            "V14 VIX>q70 alone (control)")
results <- data.table()
for (i in seq_along(variants)) {
  v <- variants[i]
  rcol <- paste0("ret_", v)
  mm <- compute_m(panel[[rcol]], dates)
  ht <- nw_t(panel[[rcol]] - panel$ret_BH, 4)

  tcol_actual <- c(V10 = "trig_V10",
                    V11 = "trig_V11_strict",
                    V12 = "trig_V12_union",
                    V13 = "trig_V13_strict_q90",
                    V14 = "trig_V14_vix_only")[v]
  trig <- panel[[tcol_actual]]
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

# ── (5) Episode detail (top variant) ──
best <- results[1]
cat(sprintf("\n[Best] %s — dSR %+.4f / Harvey-t %+.3f\n", best$variant, best$dSR, best$harvey_t))

# ── (6) Walk-forward 36m for best ──
W <- 36
best_rcol <- paste0("ret_", best$variant)
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
cat(sprintf("  Windows: %d / Win rate dSR>0: %.0f%%%% / median dSR %+.4f\n",
            nrow(wf_dt), 100 * mean(wf_dt$dSR > 0), median(wf_dt$dSR)))

# ── (7) Save + chart ──
out <- list(
  baseline_BH = list(SR = unname(m_base["SR"]), MDD = unname(m_base["MDD"]),
                      CAGR = unname(m_base["CAGR"])),
  variants = results,
  best = list(variant = best$variant, dSR = best$dSR,
               SR = best$SR, MDD = best$MDD, harvey_t = best$harvey_t),
  walkforward = list(n = nrow(wf_dt),
                      win_rate = mean(wf_dt$dSR > 0),
                      median_dsr = median(wf_dt$dSR)),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "v10_plus_vix.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/v10_plus_vix.json\n", EVAL_DIR))

# NAV chart top 3
top3 <- results[1:3]
nav_dt <- panel[, .(date = dates, BH = cumprod(1 + ret_BH))]
for (v in top3$variant) {
  nav_dt[, (v) := cumprod(1 + panel[[paste0("ret_", v)]])]
}
nav_long <- melt(nav_dt, id.vars = "date", variable.name = "Variant", value.name = "NAV")
g <- ggplot(nav_long, aes(x = date, y = NAV, color = Variant)) +
  geom_line(linewidth = 0.7) + scale_y_log10() +
  labs(title = sprintf("V10 + VIX variants — TOP 3 (Best %s dSR %+.3f)",
                       best$variant, best$dSR),
       x = NULL, y = "NAV (log)") +
  theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "39_v10_plus_vix.png"),
       plot = g, width = 13, height = 6, dpi = 120)
cat(sprintf("[Chart 39] %s/39_v10_plus_vix.png\n", CHART_DIR))

cat("\n[DONE]\n")
