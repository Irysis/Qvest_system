#==============================================================================
# 59_v5b_deep_plus_variants.R — Cycle 34 V5b deep + Multi-horizon + V9/V10
#
# Cycle 33 V5b (4-of-5 q70 PIT) best dSR +0.28 / WF 72%%. This cycle:
#   (A) V5b deep validation (LOO + bootstrap + per-episode)
#   (B) Multi-horizon ensemble (5d + 10d + 21d count blend)
#   (C) V9: V5b + double confirm (last_day_p > q80)
#   (D) V10: 3-condition AND (4-of-5 q70 AND trend > 0 AND p_eom > q70)
#   (E) V11: smooth blend (weighted 5d/10d/21d counts)
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

# ── (2) Build per-month aggregates with strict PIT ──
preds_me <- preds[, .(
  p_eom = p[which.max(Date)],
  trend_5d = tail(p, 1) - p[max(1, length(p) - 5)]
), by = ym]
setorder(preds_me, ym)

preds_me[, q70 := NA_real_]; preds_me[, q80 := NA_real_]
preds_me[, q90 := NA_real_]
for (i in seq_len(nrow(preds_me))) {
  past_p <- preds$p[preds$ym < preds_me$ym[i]]
  past_p <- past_p[!is.na(past_p)]
  if (length(past_p) >= 30) {
    preds_me[i, q70 := quantile(past_p, 0.70)]
    preds_me[i, q80 := quantile(past_p, 0.80)]
    preds_me[i, q90 := quantile(past_p, 0.90)]
  }
}

# Counts per multiple windows
preds_me[, count_5_q70 := 0L]; preds_me[, count_10_q70 := 0L]
preds_me[, count_21_q70 := 0L]
for (i in seq_len(nrow(preds_me))) {
  if (is.na(preds_me$q70[i])) next
  ym_i <- preds_me$ym[i]
  last_p_all <- preds$p[preds$ym <= ym_i]
  preds_me[i, count_5_q70 := sum(tail(last_p_all, 5) >= preds_me$q70[i], na.rm = TRUE)]
  preds_me[i, count_10_q70 := sum(tail(last_p_all, 10) >= preds_me$q70[i], na.rm = TRUE)]
  preds_me[i, count_21_q70 := sum(tail(last_p_all, 21) >= preds_me$q70[i], na.rm = TRUE)]
}

preds_me[, realized_ym := shift(ym, -1, type = "lead")]
panel <- merge(eom[, .(realized_ym, ret_kospi)],
               preds_me[, .(realized_ym, p_eom, trend_5d,
                             q70, q80, q90,
                             count_5_q70, count_10_q70, count_21_q70)],
               by = "realized_ym")
panel <- panel[!is.na(p_eom) & !is.na(q70) & !is.na(ret_kospi)]
cat(sprintf("[Panel] %d months\n", nrow(panel)))

# ── (3) Triggers ──
panel[, trig_V5b := count_5_q70 >= 4]
panel[, trig_V9 := count_5_q70 >= 4 & p_eom > q80]               # V5b + double confirm
panel[, trig_V10 := count_5_q70 >= 4 & trend_5d > 0 & p_eom > q70]  # 3-cond AND
panel[, trig_V11 := count_10_q70 >= 7]                            # 7-of-10
panel[, trig_V12 := count_21_q70 >= 12]                           # 12-of-21 (long sustained)

# Smooth multi-horizon (count_5/5*0.5 + count_10/10*0.3 + count_21/21*0.2)
panel[, smooth_V13 := pmin(1, pmax(0,
  (count_5_q70 / 5) * 0.5 +
  (count_10_q70 / 10) * 0.3 +
  (count_21_q70 / 21) * 0.2))]

# ── (4) Build returns ──
cost <- 0.003

build_kill <- function(trig_vec, cost = 0.003) {
  trigs_prev <- shift(trig_vec, 1, fill = FALSE)
  change <- trig_vec != trigs_prev
  ret <- ifelse(trig_vec, 0, panel$ret_kospi)
  ret[change] <- ret[change] - cost
  ret
}

build_smooth <- function(weight_vec, cost = 0.003) {
  prev_w <- shift(weight_vec, 1, fill = 0)
  cost_apply <- abs(weight_vec - prev_w) * cost
  ret <- (1 - weight_vec) * panel$ret_kospi - cost_apply
  ret
}

panel[, ret_V5b := build_kill(trig_V5b)]
panel[, ret_V9 := build_kill(trig_V9)]
panel[, ret_V10 := build_kill(trig_V10)]
panel[, ret_V11 := build_kill(trig_V11)]
panel[, ret_V12 := build_kill(trig_V12)]
panel[, ret_V13 := build_smooth(smooth_V13)]
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
cat(sprintf("\n━━━ BH baseline ━━━\n  SR %.4f / MDD %+.4f / CAGR %.4f\n\n",
            m_base["SR"], m_base["MDD"], m_base["CAGR"]))

variants_info <- list(
  list(v = "V5b", desc = "V5b 4-of-5 q70 (current best)"),
  list(v = "V9", desc = "V5b + p_eom > q80 (double confirm)"),
  list(v = "V10", desc = "V5b + trend>0 + p_eom>q70 (3-cond AND)"),
  list(v = "V11", desc = "7-of-10 q70 (longer window)"),
  list(v = "V12", desc = "12-of-21 q70 (very long sustained)"),
  list(v = "V13", desc = "Smooth multi-horizon weight")
)
results <- data.table()
for (vi in variants_info) {
  v <- vi$v
  rcol <- paste0("ret_", v)
  mm <- compute_m(panel[[rcol]], dates)
  ht <- nw_t(panel[[rcol]] - panel$ret_BH, 4)

  tcol_actual <- if (v == "V13") "smooth_V13" else paste0("trig_", v)
  trig <- panel[[tcol_actual]]
  if (v == "V13") {
    n_act <- sum(trig > 0)
    prec <- NA
  } else {
    n_act <- sum(trig)
    prec <- if (n_act > 0) sum(trig & panel$ret_BH < 0) / n_act else NA
  }

  results <- rbind(results, data.table(
    variant = v, description = vi$desc,
    n_trigger = n_act,
    precision = if (is.na(prec)) NA_real_ else round(prec, 3),
    SR = round(mm["SR"], 4), MDD = round(mm["MDD"], 4),
    CAGR = round(mm["CAGR"], 4),
    dSR = round(mm["SR"] - m_base["SR"], 4),
    harvey_t = round(ht, 3)
  ))
}
setorder(results, -dSR)
cat(sprintf("━━━ All variants (sorted by dSR) ━━━\n"))
print(results)

best <- results[1]
cat(sprintf("\n[Best] %s — dSR %+.4f / SR %.3f / MDD %+.3f / Harvey-t %+.3f\n",
            best$variant, best$dSR, best$SR, best$MDD, best$harvey_t))

# ── (6) Deep validation for best ──
best_rcol <- paste0("ret_", best$variant)
cat(sprintf("\n━━━ Deep validation for %s ━━━\n", best$variant))

# (a) Walk-forward
W <- 36
wf <- list()
for (i in seq_len(nrow(panel) - W + 1)) {
  win <- panel[i:(i + W - 1)]
  m_b <- compute_m(win$ret_BH, dates[i:(i + W - 1)])
  m_h <- compute_m(win[[best_rcol]], dates[i:(i + W - 1)])
  wf[[i]] <- data.table(win_end = dates[i + W - 1],
                        dSR = m_h["SR"] - m_b["SR"])
}
wf_dt <- rbindlist(wf)
win_rate <- mean(wf_dt$dSR > 0)
cat(sprintf("  Walk-forward 36m: win rate %.0f%%%% (%d/%d) / median dSR %+.3f\n",
            100 * win_rate, sum(wf_dt$dSR > 0), nrow(wf_dt), median(wf_dt$dSR)))

# (b) LOO year
panel[, yr := format(dates, "%Y")]
loo_dt <- data.table()
for (yr_iter in sort(unique(panel$yr))) {
  sub <- panel[yr != yr_iter]
  if (nrow(sub) < 24) next
  sub_dates <- as.Date(paste0(sub$realized_ym, "-01"))
  m_b <- compute_m(sub$ret_BH, sub_dates)
  m_h <- compute_m(sub[[best_rcol]], sub_dates)
  loo_dt <- rbind(loo_dt, data.table(year_excluded = yr_iter,
                                      dSR = m_h["SR"] - m_b["SR"]))
}
cat(sprintf("  LOO dSR range: [%+.4f, %+.4f] / all positive: %s\n",
            min(loo_dt$dSR), max(loo_dt$dSR),
            ifelse(all(loo_dt$dSR > 0), "YES ✅", "NO ❌")))

# (c) Bootstrap CI
set.seed(42)
B <- 2000
boot_dSR <- numeric(B)
for (b in seq_len(B)) {
  idx <- sample(nrow(panel), nrow(panel), replace = TRUE)
  sub <- panel[idx]
  sub_d <- dates[idx]
  m_b <- compute_m(sub$ret_BH, sub_d)
  m_h <- compute_m(sub[[best_rcol]], sub_d)
  boot_dSR[b] <- m_h["SR"] - m_b["SR"]
}
boot_dSR <- boot_dSR[!is.na(boot_dSR)]
cat(sprintf("  Bootstrap CI (B=2000): mean %+.4f / 95%%%% [%+.4f, %+.4f]\n",
            mean(boot_dSR), quantile(boot_dSR, 0.025), quantile(boot_dSR, 0.975)))

# ── (7) Save + chart ──
out <- list(
  baseline_BH = list(SR = unname(m_base["SR"]), MDD = unname(m_base["MDD"]),
                      CAGR = unname(m_base["CAGR"])),
  variants = results,
  best = list(variant = best$variant, dSR = best$dSR,
               SR = best$SR, MDD = best$MDD, harvey_t = best$harvey_t),
  walkforward = list(n = nrow(wf_dt), win_rate = win_rate,
                      median_dsr = median(wf_dt$dSR)),
  loo = list(all_positive = all(loo_dt$dSR > 0),
              dsr_range = c(min(loo_dt$dSR), max(loo_dt$dSR))),
  bootstrap = list(B = B, mean_dsr = mean(boot_dSR),
                    ci_lo = unname(quantile(boot_dSR, 0.025)),
                    ci_hi = unname(quantile(boot_dSR, 0.975))),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "v5b_deep_plus_variants.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/v5b_deep_plus_variants.json\n", EVAL_DIR))

# NAV chart top 3
top3 <- results[1:3]
nav_dt <- panel[, .(date = dates, BH = cumprod(1 + ret_BH))]
for (v in top3$variant) {
  nav_dt[, (v) := cumprod(1 + panel[[paste0("ret_", v)]])]
}
nav_long <- melt(nav_dt, id.vars = "date", variable.name = "Variant", value.name = "NAV")
g <- ggplot(nav_long, aes(x = date, y = NAV, color = Variant)) +
  geom_line(linewidth = 0.7) + scale_y_log10() +
  labs(title = sprintf("V5b + variants — TOP 3 (Best %s dSR %+.3f, BS CI [%+.3f, %+.3f])",
                       best$variant, best$dSR,
                       quantile(boot_dSR, 0.025), quantile(boot_dSR, 0.975)),
       x = NULL, y = "NAV (log)") +
  theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "36_v5b_variants.png"),
       plot = g, width = 13, height = 6, dpi = 120)
cat(sprintf("[Chart 36] %s/36_v5b_variants.png\n", CHART_DIR))

cat("\n[DONE]\n")
