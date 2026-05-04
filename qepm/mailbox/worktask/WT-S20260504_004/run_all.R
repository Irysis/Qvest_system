## ============================================================
## WT-S20260504_004 RMT Denoised Σ — Forge backtest (3-strategy)
## ============================================================
## Pure Function (v6.1 R12):
##   - alpha/risk/optimization 패키지 절대 수정 금지
##   - weights.csv as-is 사용 (Schedule Fidelity Mandate)
##   - PerformanceAnalytics 표준 함수만 (Backtest Contract v1.0)
##
## 3 strategies (sleeve overlay on STR_1715 base ret_net):
##   1. S1                : weight_str1715 = 1 always (pure baseline)
##   2. RMT_VolTarget     : weight_str1715 = scale_RMT (statistical only)
##   3. M4+RMT_VolTarget  : weight_str1715 = 1 - max(M4_cash, RMT_cash) (canonical)
##
## Plus 1 reference recompute:
##   M4_baseline_recomputed : STR_1715 × parent M4 schedule (L-274 frozen reference)
##
## Cash yield = 0% (KR retail convention, optimization_package).
## Cost = 15bps one-way already embedded in STR_1715 ret_net (cost_model_version v2.3_kr_retail_15bps).
## Sleeve transitions add ZERO additional cost (recommendation_only WT, no STR_1715 holding rebalance).
## ============================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(xts)
  library(PerformanceAnalytics)
})

# Paths
PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT   <- "WT-S20260504_004"
MBOX <- file.path(PROJ, "qepm/mailbox/worktask", WT)
SAGE <- file.path(PROJ, "stage_artifacts", paste0("WT_", WT))
VARDIR <- file.path(SAGE, "weights_variants")
OUTDIR <- SAGE  # canonical bt_result + lro_*
dir.create(file.path(OUTDIR, "charts"), recursive = TRUE, showWarnings = FALSE)

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

cat("=== Forge run_all.R START === WT=", WT, "\n", sep="")
cat("Started at:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), "\n")

# ───────────────────────────────────────────────────────────────────────────
# 0. Hash audit (start)
# ───────────────────────────────────────────────────────────────────────────
hash_md5 <- function(p) {
  if (!file.exists(p)) return(NA_character_)
  tools::md5sum(p)[[1]]
}
input_hashes_start <- list(
  optimization_package = hash_md5(file.path(MBOX, "optimization_package.json")),
  risk_package         = hash_md5(file.path(MBOX, "risk_package.json")),
  alpha_package        = hash_md5(file.path(MBOX, "alpha_package.json")),
  weights_canonical    = hash_md5(file.path(SAGE, "weights.csv")),
  weights_S1           = hash_md5(file.path(VARDIR, "S1.csv")),
  weights_RMT          = hash_md5(file.path(VARDIR, "RMT_VolTarget.csv")),
  weights_combo        = hash_md5(file.path(VARDIR, "M4+RMT_VolTarget.csv")),
  parent_M4_weights    = hash_md5(file.path(PROJ,
    "qepm/mailbox/worktask/WT-P20260429_002/weights.csv")),
  str1715_period_ret   = hash_md5(file.path(PROJ,
    "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"))
)
cat("\n[0] Input hashes (start):\n")
for (k in names(input_hashes_start)) {
  cat(sprintf("  %-22s %s\n", k, substr(input_hashes_start[[k]], 1, 12)))
}

# ───────────────────────────────────────────────────────────────────────────
# 1. Load STR_1715 base return series (alpha source — frozen, do not modify)
# ───────────────────────────────────────────────────────────────────────────
str1715_ret <- fread(file.path(PROJ,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"))
str1715_ret[, date := as.IDate(date)]
str1715_ret <- str1715_ret[order(date)]
n_ret <- nrow(str1715_ret)
cat(sprintf("\n[1] STR_1715 base returns: %d months [%s..%s]\n",
            n_ret, min(str1715_ret$date), max(str1715_ret$date)))
cat(sprintf("    avg cash_weight (base) = %.6f (expected ~0)\n",
            mean(str1715_ret$cash_weight, na.rm=TRUE)))

# ───────────────────────────────────────────────────────────────────────────
# 2. Load weight schedules
# ───────────────────────────────────────────────────────────────────────────
load_weights <- function(path) {
  w <- fread(path)
  w[, Date := as.IDate(Date)]
  w <- w[order(Date)]
  w
}

w_s1     <- load_weights(file.path(VARDIR, "S1.csv"))
w_rmt    <- load_weights(file.path(VARDIR, "RMT_VolTarget.csv"))
w_combo  <- load_weights(file.path(VARDIR, "M4+RMT_VolTarget.csv"))   # canonical
w_canon  <- load_weights(file.path(SAGE, "weights.csv"))              # canonical (== combo)
w_m4     <- load_weights(file.path(PROJ,
  "qepm/mailbox/worktask/WT-P20260429_002/weights.csv"))              # parent M4

# Sanity: canonical == combo (same hash)
stopifnot(identical(w_canon$Date, w_combo$Date),
          all(abs(w_canon$weight_str1715 - w_combo$weight_str1715) < 1e-12))

cat(sprintf("[2] Loaded weights: S1=%d RMT=%d Combo=%d M4_parent=%d\n",
            nrow(w_s1), nrow(w_rmt), nrow(w_combo), nrow(w_m4)))

# ───────────────────────────────────────────────────────────────────────────
# 3. Align weights to returns (weight at sig_date t → applied to ret at t+1)
# ───────────────────────────────────────────────────────────────────────────
# Convention: weights.csv Date = signal date (month-start label, e.g. 2004-01-01).
# str1715_ret date = period_end (e.g. 2004-02-02 → "Feb 2004 return").
# Weights: 267 months (2004-01..2026-03 sig_dates).
# Returns: 268 months (2004-02..2026-05 period_end).
# Mapping: weights[k=1..267] → returns[k=1..267]; truncate ret[268] (May 2026 = live forward, no overlay weight).
# Alignment density: 267/268 = 0.9963 (per optimization_package).
n_align <- min(nrow(w_s1), nrow(w_rmt), nrow(w_combo), nrow(w_m4), n_ret)
stopifnot(n_align == 267L)
str1715_ret <- str1715_ret[seq_len(n_align)]
n_ret <- n_align
cat(sprintf("    aligned to %d months (last=%s) — May 2026 dropped (live forward, no weight overlay)\n",
            n_ret, max(str1715_ret$date)))

# Build aligned overlay table
ovl <- data.table(
  period_end       = str1715_ret$date,
  ret_str1715_net  = str1715_ret$ret_net,
  ret_str1715_gross= str1715_ret$ret_gross,
  w_s1_str         = w_s1$weight_str1715,
  w_s1_cash        = w_s1$weight_cash,
  w_rmt_str        = w_rmt$weight_str1715,
  w_rmt_cash       = w_rmt$weight_cash,
  w_combo_str      = w_combo$weight_str1715,
  w_combo_cash     = w_combo$weight_cash,
  w_m4_str         = w_m4$weight_str1715,
  w_m4_cash        = w_m4$weight_cash
)

# Cash yield = 0% (KR retail convention).
# Sleeve return: r_strategy = w_str * r_str1715 + w_cash * 0 = w_str * r_str1715.
# Cost: 15bps already in r_str1715. Sleeve transition cost = 0 for recommendation_only.
ovl[, ret_S1            := w_s1_str    * ret_str1715_net]
ovl[, ret_RMT_VolTarget := w_rmt_str   * ret_str1715_net]
ovl[, ret_M4_RMT        := w_combo_str * ret_str1715_net]   # canonical
ovl[, ret_M4_baseline   := w_m4_str    * ret_str1715_net]   # L-274 frozen ref

cat(sprintf("[3] Aligned overlay table built (%d rows).\n", nrow(ovl)))

# ───────────────────────────────────────────────────────────────────────────
# 4. PerformanceAnalytics metrics (Backtest Contract v1.0 standard)
# ───────────────────────────────────────────────────────────────────────────
mk_xts <- function(rets, dates) xts::xts(rets, order.by = as.Date(dates))

compute_metrics <- function(rets, dates, label) {
  rx <- mk_xts(rets, dates)
  n <- length(rx)
  # PerformanceAnalytics
  total_ret <- as.numeric(Return.cumulative(rx))
  cagr      <- as.numeric(Return.annualized(rx, scale = 12, geometric = TRUE))
  vol_ann   <- as.numeric(StdDev.annualized(rx, scale = 12))
  # Sharpe via mean(ER)/sd(ER)*sqrt(N) (Charter v1.4 §12), Rf=0
  sr_ann    <- mean(rets, na.rm=TRUE) / sd(rets, na.rm=TRUE) * sqrt(12)
  sortino   <- as.numeric(SortinoRatio(rx, MAR = 0)) * sqrt(12)
  mdd       <- as.numeric(maxDrawdown(rx))
  calmar    <- if (mdd > 0) cagr / mdd else NA_real_
  skew      <- as.numeric(skewness(rx))
  kurt      <- as.numeric(kurtosis(rx))
  var95     <- as.numeric(quantile(rets, 0.05, na.rm=TRUE))
  var99     <- as.numeric(quantile(rets, 0.01, na.rm=TRUE))
  cvar95    <- mean(rets[rets <= var95], na.rm=TRUE)
  cvar99    <- mean(rets[rets <= var99], na.rm=TRUE)
  pos_ratio <- mean(rets > 0, na.rm=TRUE)
  best      <- max(rets, na.rm=TRUE)
  worst     <- min(rets, na.rm=TRUE)
  # DD duration
  dd_tbl <- tryCatch(table.Drawdowns(rx, top = 1),
                     error = function(e) NULL)
  mdd_dur <- if (!is.null(dd_tbl) && nrow(dd_tbl) >= 1) dd_tbl$Length[1] else NA_integer_
  # downside vol
  ddev    <- as.numeric(DownsideDeviation(rx, MAR = 0)) * sqrt(12)

  data.table(
    strategy = label, n_obs = n,
    total_return = total_ret, CAGR = cagr,
    annualized_vol = vol_ann, downside_vol = ddev,
    Sharpe = sr_ann, Sortino = sortino, Calmar = calmar,
    MDD = mdd, MDD_duration_months = mdd_dur,
    skewness = skew, kurtosis = kurt,
    VaR95 = var95, VaR99 = var99, CVaR95 = cvar95, CVaR99 = cvar99,
    positive_ratio = pos_ratio, best_period = best, worst_period = worst,
    return_to_CVaR = if (!is.na(cvar99) && cvar99 < 0) cagr / abs(cvar99) else NA_real_
  )
}

m_s1     <- compute_metrics(ovl$ret_S1,            ovl$period_end, "S1")
m_rmt    <- compute_metrics(ovl$ret_RMT_VolTarget, ovl$period_end, "RMT_VolTarget")
m_combo  <- compute_metrics(ovl$ret_M4_RMT,        ovl$period_end, "M4+RMT_VolTarget")
m_m4ref  <- compute_metrics(ovl$ret_M4_baseline,   ovl$period_end, "M4_baseline_recomputed")
m_pure   <- compute_metrics(ovl$ret_str1715_net,   ovl$period_end, "STR_1715_pure_base")

perf_summary <- rbindlist(list(m_s1, m_rmt, m_combo, m_m4ref, m_pure))
fwrite(perf_summary, file.path(OUTDIR, "lro_performance_summary.csv"))
cat("\n[4] Performance summary:\n")
print(perf_summary[, .(strategy, n_obs, CAGR = round(CAGR, 4),
                       Sharpe = round(Sharpe, 4), Sortino = round(Sortino, 4),
                       MDD = round(MDD, 4), Vol = round(annualized_vol, 4),
                       Calmar = round(Calmar, 4))])

# Save returns time-series
returns_long <- rbind(
  data.table(strategy = "S1",                    date = ovl$period_end, ret = ovl$ret_S1),
  data.table(strategy = "RMT_VolTarget",         date = ovl$period_end, ret = ovl$ret_RMT_VolTarget),
  data.table(strategy = "M4+RMT_VolTarget",      date = ovl$period_end, ret = ovl$ret_M4_RMT),
  data.table(strategy = "M4_baseline_recomputed",date = ovl$period_end, ret = ovl$ret_M4_baseline),
  data.table(strategy = "STR_1715_pure_base",    date = ovl$period_end, ret = ovl$ret_str1715_net)
)
fwrite(returns_long, file.path(OUTDIR, "lro_backtest_returns.csv"))

# ───────────────────────────────────────────────────────────────────────────
# 5. Vol regime stratification (forward analysis)
# ───────────────────────────────────────────────────────────────────────────
# Stratify by RMT vol scale (lro_params_frozen, statistical regime):
#   HIGH_VOL: scale < 0.75 (cash bridge > 25%) — RMT signal de-risk
#   MID_VOL : 0.75 <= scale < 0.95
#   LOW_VOL : scale >= 0.95 (essentially full risk)
ovl[, rmt_scale := w_rmt_str]   # RMT pure scale
ovl[, vol_regime := fifelse(rmt_scale < 0.75, "HIGH_VOL",
                       fifelse(rmt_scale < 0.95, "MID_VOL", "LOW_VOL"))]
regime_table <- ovl[, .(
  n_obs = .N,
  S1_cum_ret      = prod(1 + ret_S1) - 1,
  RMT_cum_ret     = prod(1 + ret_RMT_VolTarget) - 1,
  combo_cum_ret   = prod(1 + ret_M4_RMT) - 1,
  M4_ref_cum_ret  = prod(1 + ret_M4_baseline) - 1,
  S1_avg_monthly  = mean(ret_S1),
  combo_avg_monthly = mean(ret_M4_RMT),
  S1_vol          = sd(ret_S1) * sqrt(12),
  combo_vol       = sd(ret_M4_RMT) * sqrt(12),
  S1_min          = min(ret_S1),
  combo_min       = min(ret_M4_RMT)
), by = vol_regime][order(-S1_vol)]
fwrite(regime_table, file.path(OUTDIR, "vol_regime_stratification.csv"))
cat("\n[5] Vol regime stratification:\n")
print(regime_table)

# ───────────────────────────────────────────────────────────────────────────
# 6. Ex-2025 OOS slice (M4 post-extension)
# ───────────────────────────────────────────────────────────────────────────
ex2025_start <- as.IDate("2025-01-01")
oos_dt <- ovl[period_end >= ex2025_start]
m_s1_oos    <- compute_metrics(oos_dt$ret_S1,            oos_dt$period_end, "S1_2025+")
m_rmt_oos   <- compute_metrics(oos_dt$ret_RMT_VolTarget, oos_dt$period_end, "RMT_2025+")
m_combo_oos <- compute_metrics(oos_dt$ret_M4_RMT,        oos_dt$period_end, "M4+RMT_2025+")
m_m4ref_oos <- compute_metrics(oos_dt$ret_M4_baseline,   oos_dt$period_end, "M4_baseline_2025+")
oos_summary <- rbindlist(list(m_s1_oos, m_rmt_oos, m_combo_oos, m_m4ref_oos))
fwrite(oos_summary, file.path(OUTDIR, "ex2025_oos_summary.csv"))
cat(sprintf("\n[6] Ex-2025 OOS slice (%d months from %s):\n",
            nrow(oos_dt), min(oos_dt$period_end)))
print(oos_summary[, .(strategy, n_obs, CAGR = round(CAGR, 4),
                      Sharpe = round(Sharpe, 4), MDD = round(MDD, 4))])

# ───────────────────────────────────────────────────────────────────────────
# 7. NAV + drawdown tables for canonical (M4+RMT_VolTarget)
# ───────────────────────────────────────────────────────────────────────────
nav_canon <- data.table(
  date = ovl$period_end,
  ret_net = ovl$ret_M4_RMT,
  NAV = 100 * cumprod(1 + ovl$ret_M4_RMT)
)
nav_canon[, peak := cummax(NAV)]
nav_canon[, dd_pct := (NAV - peak) / peak]
fwrite(nav_canon, file.path(OUTDIR, "lro_canonical_nav.csv"))

# Drawdown table (PerformanceAnalytics)
dd_canon <- tryCatch(
  table.Drawdowns(mk_xts(ovl$ret_M4_RMT, ovl$period_end), top = 10),
  error = function(e) NULL)
if (!is.null(dd_canon)) {
  fwrite(as.data.table(dd_canon), file.path(OUTDIR, "lro_canonical_drawdowns.csv"))
}

# ───────────────────────────────────────────────────────────────────────────
# 8. OOS chart mandate (v6.1)
# ───────────────────────────────────────────────────────────────────────────
chart_dir <- file.path(OUTDIR, "charts")
plot_equity <- function() {
  png(file.path(chart_dir, "equity_curve.png"), width = 1400, height = 800, res = 110)
  par(mar = c(4, 4, 3, 1))
  navs <- list(
    S1            = 100 * cumprod(1 + ovl$ret_S1),
    RMT_VolTarget = 100 * cumprod(1 + ovl$ret_RMT_VolTarget),
    `M4+RMT`      = 100 * cumprod(1 + ovl$ret_M4_RMT),
    M4_baseline   = 100 * cumprod(1 + ovl$ret_M4_baseline)
  )
  ymax <- max(sapply(navs, max))
  cols <- c("gray60", "steelblue", "firebrick", "darkgreen")
  plot(ovl$period_end, navs[[1]], type = "l", log = "y",
       ylim = c(80, ymax * 1.05), col = cols[1], lwd = 1.4,
       xlab = "Date", ylab = "NAV (log scale, base=100)",
       main = "WT-S20260504_004 RMT Forge | 4-strategy NAV (268m)")
  for (i in 2:length(navs)) lines(ovl$period_end, navs[[i]], col = cols[i], lwd = 1.6)
  legend("topleft", legend = names(navs), col = cols, lwd = 2, cex = 0.9, bty = "n")
  abline(v = as.Date("2025-01-01"), lty = 2, col = "darkorange", lwd = 1.5)
  text(as.Date("2025-01-01"), 100, "OOS 2025+", pos = 4, col = "darkorange", cex = 0.85)
  dev.off()
}
plot_equity()

plot_oos_zoom <- function() {
  oos_dt2 <- ovl[period_end >= as.IDate("2024-01-01")]
  png(file.path(chart_dir, "oos_zoom_chart.png"), width = 1400, height = 700, res = 110)
  par(mar = c(4, 4, 3, 1))
  cols <- c("gray60", "steelblue", "firebrick", "darkgreen")
  navs <- list(
    S1            = 100 * cumprod(1 + oos_dt2$ret_S1),
    RMT_VolTarget = 100 * cumprod(1 + oos_dt2$ret_RMT_VolTarget),
    `M4+RMT`      = 100 * cumprod(1 + oos_dt2$ret_M4_RMT),
    M4_baseline   = 100 * cumprod(1 + oos_dt2$ret_M4_baseline)
  )
  ymax <- max(sapply(navs, max))
  ymin <- min(sapply(navs, min))
  plot(oos_dt2$period_end, navs[[1]], type = "l",
       ylim = c(ymin * 0.97, ymax * 1.03), col = cols[1], lwd = 1.6,
       xlab = "Date", ylab = "NAV (base=100 at 2024-01)",
       main = "OOS Zoom 2024+ (4-strategy)")
  for (i in 2:length(navs)) lines(oos_dt2$period_end, navs[[i]], col = cols[i], lwd = 1.8)
  legend("topleft", legend = names(navs), col = cols, lwd = 2, cex = 0.9, bty = "n")
  abline(v = as.Date("2025-01-01"), lty = 2, col = "darkorange", lwd = 1.4)
  dev.off()
}
plot_oos_zoom()

plot_annual <- function() {
  ann <- ovl[, .(year = as.integer(format(period_end, "%Y")),
                 S1 = ret_S1, RMT = ret_RMT_VolTarget,
                 combo = ret_M4_RMT, M4ref = ret_M4_baseline)]
  ann_y <- ann[, .(
    S1   = prod(1 + S1) - 1,
    RMT  = prod(1 + RMT) - 1,
    Combo = prod(1 + combo) - 1,
    M4ref = prod(1 + M4ref) - 1
  ), by = year][order(year)]
  png(file.path(chart_dir, "annual_returns.png"), width = 1400, height = 700, res = 110)
  par(mar = c(4, 4, 3, 1))
  bar_mat <- t(as.matrix(ann_y[, .(S1, RMT, Combo, M4ref)]))
  colnames(bar_mat) <- ann_y$year
  barplot(bar_mat * 100, beside = TRUE,
          col = c("gray60", "steelblue", "firebrick", "darkgreen"),
          legend.text = c("S1", "RMT_VolTarget", "M4+RMT", "M4_baseline"),
          args.legend = list(x = "topright", bty = "n", cex = 0.85),
          main = "Annual Returns by Strategy (%)",
          ylab = "Annual Return (%)", las = 2, cex.names = 0.7)
  abline(h = 0, lty = 1, col = "black")
  dev.off()
}
plot_annual()

plot_regime_decomp <- function() {
  png(file.path(chart_dir, "regime_decomposition.png"), width = 1400, height = 700, res = 110)
  par(mar = c(4, 4, 3, 1))
  rt <- regime_table[order(factor(vol_regime, levels = c("LOW_VOL","MID_VOL","HIGH_VOL")))]
  bar_mat <- rbind(
    S1     = rt$S1_cum_ret,
    RMT    = rt$RMT_cum_ret,
    Combo  = rt$combo_cum_ret,
    M4ref  = rt$M4_ref_cum_ret
  )
  colnames(bar_mat) <- paste0(rt$vol_regime, "\nn=", rt$n_obs)
  barplot(bar_mat * 100, beside = TRUE,
          col = c("gray60", "steelblue", "firebrick", "darkgreen"),
          legend.text = rownames(bar_mat),
          args.legend = list(x = "topleft", bty = "n", cex = 0.85),
          main = "Cumulative Return by RMT Vol Regime (%)",
          ylab = "Cumulative Return (%)")
  abline(h = 0, lty = 1, col = "black")
  dev.off()
}
plot_regime_decomp()

cat(sprintf("\n[7-8] Charts saved to %s\n", chart_dir))
charts_emitted <- list.files(chart_dir, pattern="\\.png$")
cat("    files:", paste(charts_emitted, collapse=", "), "\n")

# ───────────────────────────────────────────────────────────────────────────
# 9. Build canonical bt_result (M4+RMT_VolTarget) — Backtest Contract v1.0
# ───────────────────────────────────────────────────────────────────────────
source(file.path(PROJ, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(PROJ, "02_Infrastructure/contracts/audit_bt_result.R"))
source(file.path(PROJ, "02_Infrastructure/contracts/save_bt_result.R"))

bt_dates <- as.Date(ovl$period_end)
monthly_ret <- ovl$ret_M4_RMT
# gross: weight × ret_str1715_gross
monthly_ret_gross <- ovl$w_combo_str * ovl$ret_str1715_gross
weights_risk <- ovl$w_combo_str
cash_w <- ovl$w_combo_cash

ret_xts <- xts::xts(monthly_ret, order.by = bt_dates)
nav_net <- 100 * cumprod(1 + monthly_ret)
nav_gross <- 100 * cumprod(1 + monthly_ret_gross)

daily_nav_dt <- data.table(
  Date = bt_dates,
  NAV = nav_net,
  NAV_gross = nav_gross,
  cash_weight = cash_w,
  gross_exposure = weights_risk,
  net_exposure = weights_risk,
  leverage = weights_risk,
  cum_cost = nav_gross - nav_net
)

holdings_log <- vector("list", length(bt_dates))
for (k in seq_along(bt_dates)) {
  holdings_log[[k]] <- data.table(
    Signal_Date = bt_dates[k], Exec_Date = bt_dates[k],
    Ticker = c("STR_1715_RISK_SLEEVE", "CASH_KRW"),
    Name   = c("STR_1715 Iter31 Risk (M4+RMT canonical)", "KRW Cash"),
    Sector = c("Multi-Sleeve", "Cash"),
    Weight = c(weights_risk[k], cash_w[k]),
    Score  = c(NA_real_, NA_real_),
    Price  = c(NA_real_, 1.0)
  )
}

sim_shim <- list(
  DAILY_NAV_DT  = daily_nav_dt,
  strategy_xts  = ret_xts,
  bm_xts        = xts::xts(rep(0, length(bt_dates)), order.by = bt_dates),
  PORTFOLIO_LOG = data.table(
    Signal_Date = bt_dates, Exec_Date = bt_dates,
    N_stocks = 18,  # n_active_stocks per optimization_package
    NAV = nav_net,
    Turnover_Pct = 0
  ),
  HOLDINGS_LOG = holdings_log,
  label = "WT-S20260504_004_M4+RMT_VolTarget"
)

spec_shim <- list(
  strategy_name = "WT-S20260504_004 RMT Denoised Σ + M4 OR canonical",
  strategy_family = "STR_1715 sleeve overlay (M4 regime cash + RMT statistical vol target, OR)",
  signal_description = "STR_1715 Iter31 GridBest base × max(M4_cash, RMT_cash_bridge) sleeve allocation. Cash yield 0%. RMT denoised Σ statistical scale [0.5, 1.0] from ES95_target.",
  universe_rule = "KOSPI200 ∪ KOSDAQ150 + LIQ_20d >= 2e8",
  rebalance_frequency = "monthly",
  signal_date_rule = "month-start label / parent M4 schedule + RMT vol scale",
  execution_date_rule = "t+1 lag",
  weighting_method = "weight_str1715 = 1 - max(M4_cash, RMT_cash_bridge); weight_cash = max(...)",
  max_position_weight = 0.20,
  max_leverage = 1,
  cash_rule = "max(M4 regime-conditional, RMT statistical ES quantile) — strict OR",
  cost_model = "STR_1715 ret_net already cost-net 15bps each side. Sleeve transition cost 0 (recommendation_only).",
  missing_data_rule = "STR_1715 base layer winsorize 1%/99% z-score (Variant A)",
  risk_controls = "RMT_Denoised Σ (cond=411.88), ES95_target=15.34% statistical, scale ∈ [0.5, 1.0]",
  lookahead_prevention = "C1 expanding + C2 t-1 lag + C9 weight at sig_date d → ret [d, next_d) + RMT cutoff SHA-frozen",
  survivorship_bias_control = "RAWDATA full universe + delisted included (inherited from STR_1715 base)"
)

run_id <- sprintf("WT-S20260504_004_RMT_M4_FORGE_%s", format(Sys.Date(), "%Y%m%d"))
bt <- build_bt_result(
  sim_result = sim_shim, strategy_spec = spec_shim,
  run_id = run_id,
  strategy_id = "WT-S20260504_004_M4+RMT_VolTarget",
  strategy_version = "v1_canonical_M4_OR_RMT",
  benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
  transaction_cost_bps = 15, slippage_bps = 0, risk_free_rate = 0,
  frequency = "monthly", annualization_factor = 12,
  universe_id = "KR_KOSPI200_KOSDAQ150_LIQ_2E8",
  code_version = "wt_s20260504_004_forge_v1",
  created_by_agent = "forge"
)
bt <- audit_bt_result(bt)

saved <- save_bt_result(bt, OUTDIR, save_xlsx = FALSE)
cat(sprintf("\n[9] bt_result canonical saved (%d files), integrity=%s\n",
            length(saved), bt$audit$integrity %||% "?"))

# Save bt_result.rds explicitly at canonical path
saveRDS(bt, file.path(OUTDIR, "bt_result.rds"))

# Variant bt_result.rds (lighter — metrics-only saved as RDS)
variant_rds <- list(
  S1                       = list(metrics = m_s1,    returns = ovl[, .(date = period_end, ret = ret_S1)]),
  RMT_VolTarget            = list(metrics = m_rmt,   returns = ovl[, .(date = period_end, ret = ret_RMT_VolTarget)]),
  `M4+RMT_VolTarget`       = list(metrics = m_combo, returns = ovl[, .(date = period_end, ret = ret_M4_RMT)]),
  M4_baseline_recomputed   = list(metrics = m_m4ref, returns = ovl[, .(date = period_end, ret = ret_M4_baseline)])
)
saveRDS(variant_rds, file.path(OUTDIR, "bt_result_variants.rds"))

# ───────────────────────────────────────────────────────────────────────────
# 10. Hash audit (end) + provenance
# ───────────────────────────────────────────────────────────────────────────
input_hashes_end <- list(
  optimization_package = hash_md5(file.path(MBOX, "optimization_package.json")),
  risk_package         = hash_md5(file.path(MBOX, "risk_package.json")),
  alpha_package        = hash_md5(file.path(MBOX, "alpha_package.json")),
  weights_canonical    = hash_md5(file.path(SAGE, "weights.csv")),
  weights_S1           = hash_md5(file.path(VARDIR, "S1.csv")),
  weights_RMT          = hash_md5(file.path(VARDIR, "RMT_VolTarget.csv")),
  weights_combo        = hash_md5(file.path(VARDIR, "M4+RMT_VolTarget.csv")),
  parent_M4_weights    = hash_md5(file.path(PROJ,
    "qepm/mailbox/worktask/WT-P20260429_002/weights.csv")),
  str1715_period_ret   = hash_md5(file.path(PROJ,
    "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"))
)

hash_match <- mapply(function(a, b) identical(a, b),
                     input_hashes_start, input_hashes_end)
all_hashes_match <- all(hash_match)
cat(sprintf("\n[10] Hash audit: start==end %s (mismatched=%d)\n",
            all_hashes_match, sum(!hash_match)))
if (!all_hashes_match) {
  for (k in names(hash_match)[!hash_match]) {
    cat(sprintf("  MISMATCH: %s start=%s end=%s\n",
                k, input_hashes_start[[k]], input_hashes_end[[k]]))
  }
}

# Save hash audit
hash_audit_dt <- data.table(
  artifact = names(input_hashes_start),
  hash_start = unlist(input_hashes_start),
  hash_end   = unlist(input_hashes_end),
  match      = unlist(hash_match)
)
fwrite(hash_audit_dt, file.path(OUTDIR, "lro_hash_audit.csv"))

cat("\n=== Forge run_all.R COMPLETE ===\n")
cat("Ended at:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), "\n")
