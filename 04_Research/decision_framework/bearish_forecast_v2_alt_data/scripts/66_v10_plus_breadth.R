#==============================================================================
# 66_v10_plus_breadth.R — Cycle 41 Phase 2: V10 + Market Breadth backtest
#
# Breadth signals (from 65_breadth_extract.R):
#   ad_ratio_5d_avg: 5-day avg of (외국인 매수 종목 수 / 매매 종목 수)
#                    < q30_past → bearish breadth (broad selling)
#   hhi_buy_5d_avg: 외국인 매수 concentration
#                   > q70_past → narrow buying (concentrated risk)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xts);
  library(PerformanceAnalytics); library(ggplot2); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

# ── (1) Load breadth ──
br <- fread(file.path(WS, "outputs/01_data/investor_breadth_daily.csv"))
br[, Date := as.Date(Date)]
br <- br[n_active >= 100]  # filter days with sufficient data
br[, ym := format(Date, "%Y-%m")]
setorder(br, Date)
cat(sprintf("[Breadth] %d daily rows (n_active >= 100), %s ~ %s\n",
            nrow(br), as.character(min(br$Date)), as.character(max(br$Date))))

# Per-month aggregates (5-day window ending at EOM)
br_me <- br[, .(ad_ratio_eom = ad_ratio[which.max(Date)],
                 ad_ratio_5d_avg = mean(tail(ad_ratio, 5), na.rm = TRUE),
                 ad_ratio_5d_min = min(tail(ad_ratio, 5), na.rm = TRUE),
                 hhi_eom = hhi_buy[which.max(Date)],
                 hhi_5d_avg = mean(tail(hhi_buy, 5), na.rm = TRUE)),
             by = ym]
setorder(br_me, ym)

# PIT past quantiles
br_me[, ad_q30 := NA_real_]
br_me[, ad_q20 := NA_real_]
br_me[, ad_q10 := NA_real_]
br_me[, hhi_q70 := NA_real_]
br_me[, hhi_q90 := NA_real_]
for (i in seq_len(nrow(br_me))) {
  past_ad <- br_me$ad_ratio_5d_avg[seq_len(i - 1)]
  past_ad <- past_ad[!is.na(past_ad)]
  past_hhi <- br_me$hhi_5d_avg[seq_len(i - 1)]
  past_hhi <- past_hhi[!is.na(past_hhi)]
  if (length(past_ad) >= 24) {
    br_me[i, ad_q30 := quantile(past_ad, 0.30)]
    br_me[i, ad_q20 := quantile(past_ad, 0.20)]
    br_me[i, ad_q10 := quantile(past_ad, 0.10)]
  }
  if (length(past_hhi) >= 24) {
    br_me[i, hhi_q70 := quantile(past_hhi, 0.70)]
    br_me[i, hhi_q90 := quantile(past_hhi, 0.90)]
  }
}
br_me[, br_low30 := !is.na(ad_q30) & ad_ratio_5d_avg < ad_q30]
br_me[, br_low20 := !is.na(ad_q20) & ad_ratio_5d_avg < ad_q20]
br_me[, br_low10 := !is.na(ad_q10) & ad_ratio_5d_avg < ad_q10]
br_me[, hhi_high70 := !is.na(hhi_q70) & hhi_5d_avg > hhi_q70]
br_me[, hhi_high90 := !is.na(hhi_q90) & hhi_5d_avg > hhi_q90]

# ── (2) Load V10 panel ──
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
br_me[, realized_ym := shift(ym, -1, type = "lead")]

panel <- merge(eom[, .(realized_ym, ret_kospi)],
               preds_me[, .(realized_ym, p_eom, trend_5d, q70, count_5_q70)],
               by = "realized_ym")
panel <- merge(panel,
               br_me[, .(realized_ym, ad_ratio_5d_avg, hhi_5d_avg,
                          ad_q30, hhi_q70,
                          br_low30, br_low20, br_low10,
                          hhi_high70, hhi_high90)],
               by = "realized_ym")
panel <- panel[!is.na(p_eom) & !is.na(q70) & !is.na(ret_kospi) &
                !is.na(ad_ratio_5d_avg)]
cat(sprintf("[Panel] %d months (V10 + breadth 모두 가용)\n", nrow(panel)))

# ── (3) Variants ──
panel[, trig_V10 := count_5_q70 >= 4 & trend_5d > 0 & p_eom > q70]
panel[, trig_BR_a := trig_V10 | br_low10]                # V10 OR very broad selling
panel[, trig_BR_b := trig_V10 | br_low20]
panel[, trig_BR_c := trig_V10 | br_low30]
panel[, trig_BR_d := trig_V10 & br_low30]                # AND
panel[, trig_BR_e := br_low20]                           # alone control
panel[, trig_BR_f := trig_V10 | hhi_high90]              # V10 OR concentrated buying
panel[, trig_BR_g := trig_V10 | (br_low20 & hhi_high70)] # broad sell + concentrated buy

# ── (4) Returns ──
cost <- 0.003
build_kill <- function(trig_vec, cost = 0.003) {
  trig_prev <- shift(trig_vec, 1, fill = FALSE)
  change <- trig_vec != trig_prev
  ret <- ifelse(trig_vec, 0, panel$ret_kospi)
  ret[change] <- ret[change] - cost
  ret
}
for (v in c("V10", "BR_a", "BR_b", "BR_c", "BR_d", "BR_e", "BR_f", "BR_g")) {
  tcol <- paste0("trig_", v); rcol <- paste0("ret_", v)
  panel[[rcol]] <- build_kill(panel[[tcol]])
}
panel[, ret_BH := ret_kospi]

# ── (5) Metrics ──
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
cat(sprintf("\n━━━ BH baseline (%d months) ━━━\n", nrow(panel)))
cat(sprintf("  SR %.4f / MDD %+.4f / CAGR %.4f\n\n",
            m_base["SR"], m_base["MDD"], m_base["CAGR"]))

variants <- c("V10", "BR_a", "BR_b", "BR_c", "BR_d", "BR_e", "BR_f", "BR_g")
descs <- c("V10 (current PRIMARY)",
            "BR_a V10 OR breadth<q10 (very broad sell)",
            "BR_b V10 OR breadth<q20 (broad sell)",
            "BR_c V10 OR breadth<q30 (mild broad)",
            "BR_d V10 AND breadth<q30",
            "BR_e breadth<q20 alone (control)",
            "BR_f V10 OR hhi>q90 (concentrated buy)",
            "BR_g V10 OR (broad sell + concentrated buy)")
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
cat(sprintf("\n[Best] %s — dSR %+.4f / precision %.3f / Harvey-t %+.3f\n",
            best$variant, best$dSR, best$precision, best$harvey_t))

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
write_json(out, file.path(EVAL_DIR, "v10_plus_breadth.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/v10_plus_breadth.json\n", EVAL_DIR))

# NAV chart top 3
top3 <- results[1:3]
nav_dt <- panel[, .(date = dates, BH = cumprod(1 + ret_BH))]
for (v in top3$variant) {
  nav_dt[, (v) := cumprod(1 + panel[[paste0("ret_", v)]])]
}
nav_long <- melt(nav_dt, id.vars = "date", variable.name = "Variant", value.name = "NAV")
g <- ggplot(nav_long, aes(x = date, y = NAV, color = Variant)) +
  geom_line(linewidth = 0.7) + scale_y_log10() +
  labs(title = sprintf("V10 + Market Breadth — TOP 3 (Best %s dSR %+.3f)",
                       best$variant, best$dSR),
       x = NULL, y = "NAV (log)") +
  theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "42_v10_plus_breadth.png"),
       plot = g, width = 13, height = 6, dpi = 120)
cat(sprintf("[Chart 42] %s/42_v10_plus_breadth.png\n", CHART_DIR))

cat("\n[DONE]\n")
