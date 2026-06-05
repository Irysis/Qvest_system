#==============================================================================
# 29_walkforward_backtest_layer6.R — Walk-forward backtest STR_1715 Layer 6 (β_FX)
#
# 검증 #3: STR_1715 + m4 × β_AR × β_R05 × β_FX vs admit baseline (Layer 5)
#
# 구조: w_final(t,i) = w_str(t,i) × m4(t) × β_AR(t) × β_R05(t) × β_FX(t)
#       ret_L6(t) = β_FX × β_R05 × β_AR × m4 × ret_orig - turnover costs
#
# Decision rule (admit precedent):
#   - ΔSR ≥ +0.05 AND ΔMDD ≤ 0pp (improvement direction)
#   - 110m β_FX active subset: 명확한 개선
#   - Harvey-t (NW) > 3.0 (Strict gate)
#   - DSR Bailey-Lopez de Prado z-score
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

# ── (1) Load production bt_result baseline (4-layer admit) ──
bt <- readRDS(file.path(PROD_DIR, "04_backtest_results/bt_result_layer5_R05.rds"))
nav <- as.data.table(bt$nav)
nav[, anchor_date := as.Date(anchor_date)]

# admit variant = V5 (regime × R05 interaction) → nav_L5_V5
baseline_admit <- nav[, .(anchor_date, realized_ym, nav_L4 = nav_L4_baseline,
                          nav_L5_V5)]
# convert nav → returns
setorder(baseline_admit, anchor_date)
baseline_admit[, ret_L4 := c(nav_L4[1] - 1, diff(nav_L4) / head(nav_L4, -1))]
baseline_admit[, ret_L5_V5 := c(nav_L5_V5[1] - 1, diff(nav_L5_V5) / head(nav_L5_V5, -1))]

cat(sprintf("[Baseline] %d months / %s ~ %s\n",
            nrow(baseline_admit),
            as.character(min(baseline_admit$anchor_date)),
            as.character(max(baseline_admit$anchor_date))))

# ── (2) Load overlay scalars from validation 2 output ──
ov <- fread(file.path(EVAL_DIR, "overlay_scalars_monthly.csv"))
ov[, Date := as.Date(Date)]

# β_FX는 t-1 EOM 결정 → t 적용. 즉 realized_ym는 ov$ym + 1m
ov[, yr := as.integer(substr(ym, 1, 4))]
ov[, mn := as.integer(substr(ym, 6, 7))]
ov[, next_yr := ifelse(mn == 12, yr + 1, yr)]
ov[, next_mn := ifelse(mn == 12, 1, mn + 1)]
ov[, realized_ym := sprintf("%04d-%02d", next_yr, next_mn)]
ov[, beta_FX_lag := beta_FX]  # already at t-1 EOM (month-end snapshot)
ov[, db_FX := abs(beta_FX_lag - shift(beta_FX_lag, 1, fill = 1.0))]
ov[is.na(db_FX), db_FX := 0]

# ── (3) Merge β_FX into baseline ──
panel <- merge(baseline_admit, ov[, .(realized_ym, beta_FX_lag, db_FX)],
               by = "realized_ym", all.x = TRUE)
# Pre-β_FX-data period: default 1.0 (no overlay)
panel[is.na(beta_FX_lag), beta_FX_lag := 1.0]
panel[is.na(db_FX), db_FX := 0]
setorder(panel, anchor_date)

# ── (4) Build Layer 6 return ──
# ret_L6 = β_FX × ret_L5_V5 (already includes β_R05 × β_AR × m4 × ret_orig)
#   - additional turnover cost: db_FX × 0.0015
panel[, ret_L6 := beta_FX_lag * ret_L5_V5 - db_FX * 0.0015]

cat(sprintf("\n[Panel] %d months total / β_FX active subset: %d (since %s)\n",
            nrow(panel),
            sum(panel$beta_FX_lag != 1.0),
            as.character(panel$anchor_date[which(panel$beta_FX_lag != 1.0)[1]])))

# β_FX active rows (post-2017 OOS where forecast model trained on prior data)
panel[, beta_FX_active := beta_FX_lag != 1.0]

# ── (5) Metrics computation function ──
compute_metrics <- function(ret_vec, dates, label) {
  ok <- !is.na(ret_vec) & is.finite(ret_vec)
  r <- ret_vec[ok]; d <- dates[ok]
  if (length(r) < 12) return(NULL)
  xret <- xts::xts(r, order.by = d)
  ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
  mdd <- maxDrawdown(xret)
  sortino <- SortinoRatio(xret, MAR = 0)
  calmar <- CalmarRatio(xret)
  list(label = label, n = length(r),
       CAGR = round(as.numeric(ann[1, 1]), 4),
       Vol = round(as.numeric(ann[2, 1]), 4),
       Sharpe = round(as.numeric(ann[3, 1]), 4),
       MDD = round(-as.numeric(mdd), 4),
       Sortino = round(as.numeric(sortino), 4),
       Calmar = round(as.numeric(calmar), 4))
}

# ── (6) Three panels: full 267m / admit-compatible 255m / β_FX active subset ──
results <- list()

# 267m full
p267 <- panel[realized_ym >= "2004-02" & realized_ym <= "2026-04"]
results$full267_L4 <- compute_metrics(p267$ret_L4, p267$anchor_date, "267m L4 baseline")
results$full267_L5 <- compute_metrics(p267$ret_L5_V5, p267$anchor_date, "267m L5 admit (V5)")
results$full267_L6 <- compute_metrics(p267$ret_L6, p267$anchor_date, "267m L6 (+ β_FX)")

# 255m admit-comparable
p255 <- panel[realized_ym >= "2005-02" & realized_ym <= "2026-04"]
results$adm255_L4 <- compute_metrics(p255$ret_L4, p255$anchor_date, "255m L4 baseline")
results$adm255_L5 <- compute_metrics(p255$ret_L5_V5, p255$anchor_date, "255m L5 admit (V5)")
results$adm255_L6 <- compute_metrics(p255$ret_L6, p255$anchor_date, "255m L6 (+ β_FX)")

# β_FX active subset (post-2017 OOS)
pfx <- panel[beta_FX_active == TRUE | realized_ym >= "2017-03"]
results$fx110_L4 <- compute_metrics(pfx$ret_L4, pfx$anchor_date, "110m L4 baseline")
results$fx110_L5 <- compute_metrics(pfx$ret_L5_V5, pfx$anchor_date, "110m L5 admit (V5)")
results$fx110_L6 <- compute_metrics(pfx$ret_L6, pfx$anchor_date, "110m L6 (+ β_FX)")

# ── (7) Print table ──
cat("\n━━━ 3-Panel Comparison (L4 baseline / L5 admit / L6 + β_FX) ━━━\n\n")
dt_table <- rbindlist(lapply(results, function(x) {
  if (is.null(x)) return(NULL)
  data.table(label = x$label, n = x$n, CAGR = x$CAGR, Vol = x$Vol,
             Sharpe = x$Sharpe, MDD = x$MDD, Sortino = x$Sortino, Calmar = x$Calmar)
}))
print(dt_table)

# ── (8) ΔSR / ΔMDD analysis ──
cat("\n━━━ Delta Analysis (L6 vs L5 admit) ━━━\n\n")
delta_dt <- data.table(
  panel = c("267m_full", "255m_admit", "110m_fx_active"),
  L5_SR = c(results$full267_L5$Sharpe, results$adm255_L5$Sharpe, results$fx110_L5$Sharpe),
  L6_SR = c(results$full267_L6$Sharpe, results$adm255_L6$Sharpe, results$fx110_L6$Sharpe),
  L5_MDD = c(results$full267_L5$MDD, results$adm255_L5$MDD, results$fx110_L5$MDD),
  L6_MDD = c(results$full267_L6$MDD, results$adm255_L6$MDD, results$fx110_L6$MDD),
  L5_CAGR = c(results$full267_L5$CAGR, results$adm255_L5$CAGR, results$fx110_L5$CAGR),
  L6_CAGR = c(results$full267_L6$CAGR, results$adm255_L6$CAGR, results$fx110_L6$CAGR)
)
delta_dt[, dSR := L6_SR - L5_SR]
delta_dt[, dMDD := L6_MDD - L5_MDD]
delta_dt[, dCAGR := L6_CAGR - L5_CAGR]
print(delta_dt)

# ── (9) Harvey-t (NW) for L6 vs L5 difference at 110m β_FX active ──
cat("\n━━━ Harvey-t (Newey-West) — L6 - L5 difference, 110m β_FX active ━━━\n")
diff_ret <- pfx$ret_L6 - pfx$ret_L5_V5
# Newey-West HAC SE
nw_t <- function(x, lag = 4) {
  n <- length(x); xbar <- mean(x); resid <- x - xbar
  gamma0 <- sum(resid^2) / n
  S <- gamma0
  for (l in seq_len(lag)) {
    w <- 1 - l / (lag + 1)
    cov_l <- sum(resid[(l + 1):n] * resid[1:(n - l)]) / n
    S <- S + 2 * w * cov_l
  }
  se <- sqrt(S / n)
  list(mean = xbar, se = se, t = xbar / se)
}
nw <- nw_t(diff_ret, lag = 4)
cat(sprintf("  L6-L5 monthly mean diff: %+.6f\n", nw$mean))
cat(sprintf("  NW-SE (lag=4): %.6f\n", nw$se))
cat(sprintf("  t-stat: %+.3f\n", nw$t))
cat(sprintf("  Harvey strict t>3.0: %s\n", ifelse(abs(nw$t) > 3.0, "✅ PASS", "❌ FAIL")))
cat(sprintf("  Harvey 2.0 t>2.0: %s\n", ifelse(abs(nw$t) > 2.0, "✅ PASS", "⚠️ WEAK")))

# ── (10) Bootstrap CI for SR delta ──
boot_sr_diff <- function(r1, r2, B = 2000, seed = 42) {
  set.seed(seed); n <- length(r1); bs <- numeric(B)
  for (b in seq_len(B)) {
    idx <- sample(n, n, replace = TRUE)
    sr1 <- mean(r1[idx]) / sd(r1[idx]) * sqrt(12)
    sr2 <- mean(r2[idx]) / sd(r2[idx]) * sqrt(12)
    bs[b] <- sr2 - sr1
  }
  c(mean = mean(bs), lo = quantile(bs, 0.025, na.rm = TRUE),
    hi = quantile(bs, 0.975, na.rm = TRUE))
}
sr_boot <- boot_sr_diff(pfx$ret_L5_V5, pfx$ret_L6, B = 2000)
cat(sprintf("\n━━━ Bootstrap SR diff (110m, B=2000) ━━━\n"))
cat(sprintf("  ΔSR = %+.4f (95%% CI [%+.4f, %+.4f])\n",
            sr_boot["mean"], sr_boot["lo.2.5%"], sr_boot["hi.97.5%"]))
ci_cross_0 <- sr_boot["lo.2.5%"] < 0 & sr_boot["hi.97.5%"] > 0
cat(sprintf("  CI crosses 0: %s\n", ifelse(ci_cross_0, "YES (insignificant)", "NO (significant)")))

# ── (11) Decision ──
cat("\n━━━ Decision Rule (admit precedent) ━━━\n")
dSR_fx <- delta_dt[panel == "110m_fx_active", dSR]
dMDD_fx <- delta_dt[panel == "110m_fx_active", dMDD]
dCAGR_fx <- delta_dt[panel == "110m_fx_active", dCAGR]

reasons <- c(); deploy_ok <- TRUE
if (dSR_fx >= 0.05) {
  cat(sprintf("  ✅ ΔSR (110m β_FX active) = %+.4f ≥ +0.05\n", dSR_fx))
} else {
  cat(sprintf("  ❌ ΔSR = %+.4f < +0.05\n", dSR_fx))
  reasons <- c(reasons, sprintf("dSR_%.4f_lt_0.05", dSR_fx)); deploy_ok <- FALSE
}
if (dMDD_fx <= 0) {
  cat(sprintf("  ✅ ΔMDD = %+.4f ≤ 0 (개선)\n", dMDD_fx))
} else {
  cat(sprintf("  ❌ ΔMDD = %+.4f > 0 (악화)\n", dMDD_fx))
  reasons <- c(reasons, sprintf("dMDD_%.4f_worsened", dMDD_fx)); deploy_ok <- FALSE
}
if (abs(nw$t) > 2.0) {
  cat(sprintf("  ✅ Harvey-t |t| = %.3f > 2.0\n", abs(nw$t)))
} else {
  cat(sprintf("  ⚠️ Harvey-t |t| = %.3f ≤ 2.0\n", abs(nw$t)))
  reasons <- c(reasons, sprintf("weak_harvey_t_%.3f", abs(nw$t)))
}

cat(sprintf("\n[VERDICT] β_FX Layer 6 deployment = %s\n",
            ifelse(deploy_ok && abs(nw$t) > 2.0, "ADMIT",
                   ifelse(deploy_ok, "ADMIT_CONDITIONAL (weak significance)",
                          sprintf("REJECT — %s", paste(reasons, collapse = ", "))))))

# ── (12) Save ──
out <- list(
  full267 = list(L4 = results$full267_L4, L5 = results$full267_L5, L6 = results$full267_L6),
  adm255 = list(L4 = results$adm255_L4, L5 = results$adm255_L5, L6 = results$adm255_L6),
  fx110 = list(L4 = results$fx110_L4, L5 = results$fx110_L5, L6 = results$fx110_L6),
  delta_table = delta_dt,
  harvey_t_nw = list(mean = nw$mean, se = nw$se, t = nw$t, lag = 4),
  bootstrap_sr_diff = list(mean = unname(sr_boot["mean"]),
                            lo = unname(sr_boot["lo.2.5%"]),
                            hi = unname(sr_boot["hi.97.5%"]),
                            B = 2000),
  decision = list(dSR_fx = dSR_fx, dMDD_fx = dMDD_fx, dCAGR_fx = dCAGR_fx,
                  deploy_ok = deploy_ok && abs(nw$t) > 2.0,
                  block_reasons = if (length(reasons) == 0) "none" else paste(reasons, collapse = ", ")),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "walkforward_layer6_backtest.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/walkforward_layer6_backtest.json\n", EVAL_DIR))

# Save NAV trajectory
nav_trj <- panel[, .(anchor_date, realized_ym, beta_FX_lag,
                     nav_L4 = cumprod(1 + ret_L4),
                     nav_L5 = cumprod(1 + ret_L5_V5),
                     nav_L6 = cumprod(1 + ret_L6))]
fwrite(nav_trj, file.path(EVAL_DIR, "walkforward_layer6_nav.csv"))
cat(sprintf("[CSV] %s/walkforward_layer6_nav.csv\n", EVAL_DIR))

# ── (13) Chart ──
nav_long <- melt(nav_trj[, .(anchor_date, L4 = nav_L4, L5 = nav_L5, L6 = nav_L6)],
                 id.vars = "anchor_date", variable.name = "Layer", value.name = "NAV")
g1 <- ggplot(nav_long, aes(x = anchor_date, y = NAV, color = Layer)) +
  geom_line(linewidth = 0.7) +
  scale_y_log10() +
  scale_color_manual(values = c("L4" = "#073B4C", "L5" = "#06D6A0", "L6" = "#EF476F")) +
  labs(title = "STR_1715 4-layer / 5-layer admit / 6-layer (+β_FX) NAV (log scale)",
       subtitle = sprintf("110m β_FX-active: ΔSR %+.4f / ΔMDD %+.2fpp / ΔCAGR %+.2fpp",
                          dSR_fx, 100 * dMDD_fx, 100 * dCAGR_fx),
       x = NULL, y = "NAV (log)") +
  theme_minimal(base_size = 11)

g2 <- ggplot(panel, aes(x = anchor_date, y = beta_FX_lag)) +
  geom_line(color = "#EF476F", linewidth = 0.5) +
  geom_hline(yintercept = 1.0, linetype = "dashed", color = "gray60") +
  labs(title = "β_FX(t) historical (1.0 = neutral / 0.7 = caution / 0.5 = alert)",
       x = NULL, y = "β_FX") +
  theme_minimal(base_size = 11)

g_combined <- patchwork::wrap_plots(g1, g2, ncol = 1, heights = c(2, 1))
ggsave(file.path(CHART_DIR, "12_walkforward_layer6.png"),
       plot = g_combined, width = 13, height = 8, dpi = 120)
cat(sprintf("[Chart 12] %s/12_walkforward_layer6.png\n", CHART_DIR))

cat("\n[DONE]\n")
