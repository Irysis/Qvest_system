#==============================================================================
# 58_v4_variants_exploration.R — Cycle 33 V4 변형 탐색 + Deep validation
#
# 도훈 mandate (2026-05-20):
#   "새로운 모델 확정되고나서 모닝브리핑 통합" → 모델 확정 집중.
#
# Cycle 32 finding: V4 (3-of-5 sustained q70) dSR +0.912 BREAKTHROUGH.
# This cycle: V4 변형 + sensitivity + deep validation.
#
# Variants (BH KOSPI base):
#   V4 (best, current): 3-of-5 days >= q70 → kill switch
#   V5a: 3-of-5 days >= q90 (stricter threshold)
#   V5b: 4-of-5 days >= q70 (stricter count)
#   V6a: 5-of-10 days >= q70 (longer window)
#   V6b: 7-of-10 days >= q70
#   V7: V3 + V4 OR ensemble (rising OR sustained)
#   V8: count-based smooth — pos = (count_q70 / 5) blend cash & long
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

# ── (2) Compute variant signals per month ──
preds_me <- preds[, .(
  p_eom = p[which.max(Date)],
  trend_5d = tail(p, 1) - p[max(1, length(p) - 5)]
), by = ym]
setorder(preds_me, ym)

# PIT q70/q90 per month
preds_me[, q70 := NA_real_]; preds_me[, q90 := NA_real_]
for (i in seq_len(nrow(preds_me))) {
  past_p <- preds$p[preds$ym < preds_me$ym[i]]
  past_p <- past_p[!is.na(past_p)]
  if (length(past_p) >= 30) {
    preds_me[i, q70 := quantile(past_p, 0.70)]
    preds_me[i, q90 := quantile(past_p, 0.90)]
  }
}

# Count-based: how many of past 5/10 days are above q70/q90 (PIT)
preds_me[, count_q70_5 := 0L]; preds_me[, count_q90_5 := 0L]
preds_me[, count_q70_10 := 0L]; preds_me[, count_q90_10 := 0L]
for (i in seq_len(nrow(preds_me))) {
  if (is.na(preds_me$q70[i])) next
  ym_i <- preds_me$ym[i]
  last_p <- preds$p[preds$ym <= ym_i]
  last_5 <- tail(last_p, 5)
  last_10 <- tail(last_p, 10)
  preds_me[i, count_q70_5 := sum(last_5 >= preds_me$q70[i], na.rm = TRUE)]
  preds_me[i, count_q90_5 := sum(last_5 >= preds_me$q90[i], na.rm = TRUE)]
  preds_me[i, count_q70_10 := sum(last_10 >= preds_me$q70[i], na.rm = TRUE)]
  preds_me[i, count_q90_10 := sum(last_10 >= preds_me$q90[i], na.rm = TRUE)]
}

preds_me[, realized_ym := shift(ym, -1, type = "lead")]
panel <- merge(eom[, .(realized_ym, ret_kospi)],
               preds_me[, .(realized_ym, p_eom, trend_5d,
                             q70, q90,
                             count_q70_5, count_q90_5,
                             count_q70_10, count_q90_10)],
               by = "realized_ym")
panel <- panel[!is.na(p_eom) & !is.na(q70) & !is.na(ret_kospi)]
cat(sprintf("[Panel] %d months\n", nrow(panel)))

# ── (3) Define triggers ──
panel[, trig_V4_3of5_q70 := count_q70_5 >= 3]                    # current best
panel[, trig_V5a_3of5_q90 := count_q90_5 >= 3]                   # stricter threshold
panel[, trig_V5b_4of5_q70 := count_q70_5 >= 4]                   # stricter count
panel[, trig_V6a_5of10_q70 := count_q70_10 >= 5]                 # longer window
panel[, trig_V6b_7of10_q70 := count_q70_10 >= 7]                 # longer + strict
panel[, trig_V7_V3orV4 := (count_q70_5 >= 3) |
                            (trend_5d > 0.05 & p_eom > q70)]      # union
panel[, trig_V8_smooth := pmax(0, pmin(1, (count_q70_5 - 2) / 3))]  # 0~1 weight

# ── (4) Build returns per variant ──
cost <- 0.003

build_kill <- function(trig_vec, cost = 0.003) {
  trigs_prev <- shift(trig_vec, 1, fill = FALSE)
  change <- trig_vec != trigs_prev
  ret <- ifelse(trig_vec, 0, panel$ret_kospi)
  ret[change] <- ret[change] - cost
  ret
}

build_smooth <- function(weight_vec, cost = 0.003) {
  # weight = 0 (full long), 1 (full cash)
  prev_w <- shift(weight_vec, 1, fill = 0)
  change_cost <- abs(weight_vec - prev_w) * cost
  ret <- (1 - weight_vec) * panel$ret_kospi - change_cost
  ret
}

panel[, ret_V4 := build_kill(trig_V4_3of5_q70)]
panel[, ret_V5a := build_kill(trig_V5a_3of5_q90)]
panel[, ret_V5b := build_kill(trig_V5b_4of5_q70)]
panel[, ret_V6a := build_kill(trig_V6a_5of10_q70)]
panel[, ret_V6b := build_kill(trig_V6b_7of10_q70)]
panel[, ret_V7 := build_kill(trig_V7_V3orV4)]
panel[, ret_V8 := build_smooth(trig_V8_smooth)]
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
cat(sprintf("\n━━━ BH baseline ━━━\n"))
cat(sprintf("  SR %.4f / MDD %+.4f / CAGR %.4f\n\n",
            m_base["SR"], m_base["MDD"], m_base["CAGR"]))

variants <- c("V4", "V5a", "V5b", "V6a", "V6b", "V7", "V8")
labels <- c("V4 3-of-5 q70 (cycle 32 best)",
            "V5a 3-of-5 q90 (strict threshold)",
            "V5b 4-of-5 q70 (strict count)",
            "V6a 5-of-10 q70 (long window)",
            "V6b 7-of-10 q70 (long + strict)",
            "V7 V3 OR V4 (union)",
            "V8 smooth weight (count/3 cap 1)")
results <- data.table()
for (i in seq_along(variants)) {
  v <- variants[i]
  rcol <- paste0("ret_", v)
  mm <- compute_m(panel[[rcol]], dates)
  ht <- nw_t(panel[[rcol]] - panel$ret_BH, 4)

  # Trigger count + precision
  tcol <- if (v == "V8") "trig_V8_smooth" else paste0("trig_", v, "_",
                                                        c("V4_3of5_q70" = "3of5_q70",
                                                          "V5a_3of5_q90" = "3of5_q90",
                                                          "V5b_4of5_q70" = "4of5_q70",
                                                          "V6a_5of10_q70" = "5of10_q70",
                                                          "V6b_7of10_q70" = "7of10_q70",
                                                          "V7_V3orV4" = "V3orV4")[v])
  # Actual columns built
  tcol_actual <- c(V4 = "trig_V4_3of5_q70", V5a = "trig_V5a_3of5_q90",
                    V5b = "trig_V5b_4of5_q70", V6a = "trig_V6a_5of10_q70",
                    V6b = "trig_V6b_7of10_q70", V7 = "trig_V7_V3orV4",
                    V8 = "trig_V8_smooth")[v]
  if (v == "V8") {
    n_act <- sum(panel[[tcol_actual]] > 0)
    prec <- NA  # smooth weight, precision undefined
  } else {
    trig <- panel[[tcol_actual]]
    n_act <- sum(trig)
    prec <- if (n_act > 0) sum(trig & panel$ret_BH < 0) / n_act else NA
  }

  results <- rbind(results, data.table(
    variant = v,
    description = labels[i],
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
cat(sprintf("\n[Best] %s — dSR %+.4f / SR %.3f / MDD %+.3f / Harvey-t %+.3f\n",
            best$variant, best$dSR, best$SR, best$MDD, best$harvey_t))

# ── (6) Walk-forward 36m on best ──
cat(sprintf("\n━━━ Walk-forward 36m rolling on %s ━━━\n", best$variant))
best_ret_col <- paste0("ret_", best$variant)
W <- 36
n_win <- nrow(panel) - W + 1
wf <- list()
for (i in seq_len(n_win)) {
  win <- panel[i:(i + W - 1)]
  if (nrow(win) < W) next
  m_b <- compute_m(win$ret_BH, dates[i:(i + W - 1)])
  m_h <- compute_m(win[[best_ret_col]], dates[i:(i + W - 1)])
  wf[[i]] <- data.table(win_start = dates[i], win_end = dates[i + W - 1],
                        dSR = m_h["SR"] - m_b["SR"],
                        dMDD = m_h["MDD"] - m_b["MDD"])
}
wf_dt <- rbindlist(wf)
win_rate <- mean(wf_dt$dSR > 0)
cat(sprintf("  Windows: %d / Win rate dSR > 0: %.0f%%%% (%d/%d)\n",
            nrow(wf_dt), 100 * win_rate,
            sum(wf_dt$dSR > 0), nrow(wf_dt)))
cat(sprintf("  dSR: median %+.4f / mean %+.4f / IQR [%+.4f, %+.4f]\n",
            median(wf_dt$dSR), mean(wf_dt$dSR),
            quantile(wf_dt$dSR, 0.25), quantile(wf_dt$dSR, 0.75)))
cat(sprintf("  dSR: min %+.4f / max %+.4f\n",
            min(wf_dt$dSR), max(wf_dt$dSR)))

# ── (7) Save + chart ──
out <- list(
  baseline_BH = list(SR = unname(m_base["SR"]), MDD = unname(m_base["MDD"]),
                      CAGR = unname(m_base["CAGR"])),
  variants = results,
  best = list(variant = best$variant, dSR = best$dSR,
               SR = best$SR, MDD = best$MDD, harvey_t = best$harvey_t),
  walkforward = list(
    n_windows = nrow(wf_dt),
    win_rate = win_rate,
    median_dsr = median(wf_dt$dSR),
    range = c(min(wf_dt$dSR), max(wf_dt$dSR))),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "v4_variants_exploration.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/v4_variants_exploration.json\n", EVAL_DIR))

# NAV chart top 3
top3 <- results[1:3]
nav_cols <- paste0("ret_", top3$variant)
nav_dt <- panel[, .(date = dates, BH = cumprod(1 + ret_BH))]
for (v in top3$variant) {
  nav_dt[, (v) := cumprod(1 + panel[[paste0("ret_", v)]])]
}
nav_long <- melt(nav_dt, id.vars = "date", variable.name = "Variant", value.name = "NAV")
g <- ggplot(nav_long, aes(x = date, y = NAV, color = Variant)) +
  geom_line(linewidth = 0.7) + scale_y_log10() +
  labs(title = sprintf("V4 variants exploration — TOP 3 (Best %s dSR %+.3f)",
                       best$variant, best$dSR),
       x = NULL, y = "NAV (log)") +
  theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "35_v4_variants.png"),
       plot = g, width = 13, height = 6, dpi = 120)
cat(sprintf("[Chart 35] %s/35_v4_variants.png\n", CHART_DIR))

cat("\n[DONE]\n")
