#==============================================================================
# 63_v10_plus_vkospi.R — Cycle 39 V10 + VKOSPI (실데이터)
#
# 도훈 mandate: 작업경로 universe 폴더 VKOSPI 데이터 사용
# Source: 03_Universe/Benchmark_price.xlsx > Benchmarks > IKS221 (코스피200 변동성지수)
# Period: 2003-01-02 ~ 2026-05-15 (5779일)
#
# V12 was V10 OR VIX>q90 (US fear) dSR +0.611
# V_VK는 V10 OR VKOSPI>q90 (KR 직접 implied vol)
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

# VKOSPI daily
vk <- fread(file.path(WS, "outputs/01_data/vkospi_daily.csv"))
vk[, Date := as.Date(Date)]
vk[, ym := format(Date, "%Y-%m")]
setorder(vk, Date)
cat(sprintf("[VKOSPI] %d daily rows, %s ~ %s\n",
            nrow(vk), as.character(min(vk$Date)), as.character(max(vk$Date))))

# Monthly EOM VKOSPI + PIT thresholds
vk_me <- vk[, .(vkospi_eom = VKOSPI[which.max(Date)],
                 vkospi_max_5d = max(tail(VKOSPI, 5)),
                 vkospi_avg_5d = mean(tail(VKOSPI, 5))),
             by = ym]
setorder(vk_me, ym)
vk_me[, vkospi_q70 := NA_real_]
vk_me[, vkospi_q90 := NA_real_]
for (i in seq_len(nrow(vk_me))) {
  past_v <- vk_me$vkospi_eom[seq_len(i - 1)]
  past_v <- past_v[!is.na(past_v)]
  if (length(past_v) >= 12) {
    vk_me[i, vkospi_q70 := quantile(past_v, 0.70)]
    vk_me[i, vkospi_q90 := quantile(past_v, 0.90)]
  }
}
vk_me[, vk_trigger_q70 := !is.na(vkospi_q70) & vkospi_eom > vkospi_q70]
vk_me[, vk_trigger_q90 := !is.na(vkospi_q90) & vkospi_eom > vkospi_q90]

# V10 ingredients (per month aggregate)
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
# VKOSPI lag: VKOSPI is published at end of month, available for next month decision
vk_me[, realized_ym := shift(ym, -1, type = "lead")]

panel <- merge(eom[, .(realized_ym, ret_kospi)],
               preds_me[, .(realized_ym, p_eom, trend_5d, q70, count_5_q70)],
               by = "realized_ym")
panel <- merge(panel,
               vk_me[, .(realized_ym, vkospi_eom, vkospi_q70, vkospi_q90,
                          vk_trigger_q70, vk_trigger_q90)],
               by = "realized_ym")
panel <- panel[!is.na(p_eom) & !is.na(q70) & !is.na(ret_kospi) & !is.na(vkospi_eom)]
cat(sprintf("[Panel] %d months (model + VKOSPI 모두 가용)\n", nrow(panel)))

# ── (2) Variants ──
panel[, trig_V10 := count_5_q70 >= 4 & trend_5d > 0 & p_eom > q70]
panel[, trig_VK_a := trig_V10 | vk_trigger_q90]                  # OR (cycle 38 V12 spec)
panel[, trig_VK_b := trig_V10 & vk_trigger_q70]                  # AND q70 (strict)
panel[, trig_VK_c := trig_V10 & vk_trigger_q90]                  # AND q90 (very strict)
panel[, trig_VK_d := trig_V10 | vk_trigger_q70]                  # OR q70 (broad)
panel[, trig_VK_e := vk_trigger_q70]                              # VKOSPI alone control
panel[, trig_VK_f := vk_trigger_q90]                              # VKOSPI q90 alone

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
panel[, ret_VK_a := build_kill(trig_VK_a)]
panel[, ret_VK_b := build_kill(trig_VK_b)]
panel[, ret_VK_c := build_kill(trig_VK_c)]
panel[, ret_VK_d := build_kill(trig_VK_d)]
panel[, ret_VK_e := build_kill(trig_VK_e)]
panel[, ret_VK_f := build_kill(trig_VK_f)]
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
cat(sprintf("\n━━━ BH KOSPI baseline (%d months VKOSPI-period) ━━━\n", nrow(panel)))
cat(sprintf("  SR %.4f / MDD %+.4f / CAGR %.4f\n\n",
            m_base["SR"], m_base["MDD"], m_base["CAGR"]))

variants <- c("V10", "VK_a", "VK_b", "VK_c", "VK_d", "VK_e", "VK_f")
descs <- c("V10 3-cond (current PRIMARY)",
            "VK_a V10 OR VKOSPI>q90 (UNION, key)",
            "VK_b V10 AND VKOSPI>q70 (strict)",
            "VK_c V10 AND VKOSPI>q90 (very strict)",
            "VK_d V10 OR VKOSPI>q70 (broad)",
            "VK_e VKOSPI>q70 alone (control)",
            "VK_f VKOSPI>q90 alone (control)")
results <- data.table()
for (i in seq_along(variants)) {
  v <- variants[i]
  rcol <- paste0("ret_", v)
  mm <- compute_m(panel[[rcol]], dates)
  ht <- nw_t(panel[[rcol]] - panel$ret_BH, 4)

  tcol <- c(V10 = "trig_V10", VK_a = "trig_VK_a", VK_b = "trig_VK_b",
             VK_c = "trig_VK_c", VK_d = "trig_VK_d",
             VK_e = "trig_VK_e", VK_f = "trig_VK_f")[v]
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
cat(sprintf("  Windows: %d / Win rate %.0f%%%% / median dSR %+.4f / IQR [%+.4f, %+.4f]\n",
            nrow(wf_dt), 100 * mean(wf_dt$dSR > 0),
            median(wf_dt$dSR),
            quantile(wf_dt$dSR, 0.25), quantile(wf_dt$dSR, 0.75)))

# Save + chart
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
write_json(out, file.path(EVAL_DIR, "v10_plus_vkospi.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/v10_plus_vkospi.json\n", EVAL_DIR))

# NAV chart top 3
top3 <- results[1:3]
nav_dt <- panel[, .(date = dates, BH = cumprod(1 + ret_BH))]
for (v in top3$variant) {
  nav_dt[, (v) := cumprod(1 + panel[[paste0("ret_", v)]])]
}
nav_long <- melt(nav_dt, id.vars = "date", variable.name = "Variant", value.name = "NAV")
g <- ggplot(nav_long, aes(x = date, y = NAV, color = Variant)) +
  geom_line(linewidth = 0.7) + scale_y_log10() +
  labs(title = sprintf("V10 + VKOSPI variants — TOP 3 (Best %s dSR %+.3f)",
                       best$variant, best$dSR),
       x = NULL, y = "NAV (log)") +
  theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "40_v10_plus_vkospi.png"),
       plot = g, width = 13, height = 6, dpi = 120)
cat(sprintf("[Chart 40] %s/40_v10_plus_vkospi.png\n", CHART_DIR))

cat("\n[DONE]\n")
