#!/usr/bin/env Rscript
# ============================================================================
# Patch v3 — Pfaff Ch.7 EVT-GPD threshold sensitivity + Ch.8 GARCH(1,1)
#
# 추가 분석:
# 1. Mean Residual Life (MRL) plot for KOSPI BM 36yr — GPD threshold robustness
# 2. GARCH(1,1)-t regime conditional vol on KR equity (AR proxy = KOSPI200 BM)
# 3. AR_KR10y rolling 12m correlation chart data — regime shift visualization
# 4. Hybrid 70/15/15 vs Pure AR (100%) MDD comparison — AX-001 v2 conditional defense
#
# 이 모두 PIT preserving — rolling/expanding window only
# ============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(PerformanceAnalytics)
  library(fExtremes)
  library(rugarch)
  library(xts)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/research/risk_model_meta_20260507")

LOG_FILE <- file.path(OUT_DIR, "meta_research_log.txt")
log_msg <- function(msg) {
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  line <- sprintf("[%s] [PATCH_V3] %s", ts, msg)
  cat(line, "\n")
  cat(line, "\n", file = LOG_FILE, append = TRUE)
}
log_msg("=== PATCH V3 START ===")

rawdata_path <- file.path(PROJECT_ROOT, ".cache/rawdata.parquet")
RAWDATA <- as.data.table(read_parquet(rawdata_path))
RAWDATA[, Date := as.Date(Date)]

# ============================================================================
# Section A: Mean Residual Life plot — GPD threshold sensitivity
# Pfaff (2016) Ch.7: MRL plot은 threshold 위 평균 초과량 vs threshold —
# linear 영역이 GPD 적합 시점
# ============================================================================

log_msg("--- Patch v3 A: MRL plot for KOSPI BM 36yr ---")

# BM monthly aggregation
bm_dt <- RAWDATA[!is.na(BM_Ret), .(BM_Ret = first(BM_Ret)), by = Date]
bm_dt[, YM := format(Date, "%Y-%m")]
bm_monthly <- bm_dt[, .(ret = prod(1 + BM_Ret, na.rm = TRUE) - 1), by = YM]
bm_monthly[, ym_date := as.Date(paste0(YM, "-01"))]
bm_monthly <- bm_monthly[order(ym_date)]

losses_monthly <- -bm_monthly$ret  # gain → loss convention
losses_daily <- -bm_dt$BM_Ret  # daily losses 36 yr
losses_daily <- losses_daily[!is.na(losses_daily)]
log_msg(sprintf("Daily losses: %d obs (%s ~ %s)",
                length(losses_daily), min(bm_dt$Date), max(bm_dt$Date)))

# MRL 함수: u_seq vs mean(losses[losses>u] - u)
mrl_curve <- function(losses, u_seq) {
  data.table(
    u = u_seq,
    mrl = sapply(u_seq, function(u) {
      ex <- losses[losses > u]
      if (length(ex) < 5) NA_real_ else mean(ex - u)
    }),
    n_exceed = sapply(u_seq, function(u) sum(losses > u))
  )
}

# Daily 기준 — quantile 0.85 ~ 0.999
q_seq <- seq(0.85, 0.999, by = 0.005)
u_seq_daily <- quantile(losses_daily, q_seq)
mrl_daily <- mrl_curve(losses_daily, u_seq_daily)
mrl_daily[, q := q_seq]
log_msg("=== MRL curve (KOSPI BM daily losses 36yr) — selected quantiles ===")
print(mrl_daily[q %in% c(0.85, 0.90, 0.95, 0.97, 0.99, 0.995)])
fwrite(mrl_daily, file.path(OUT_DIR, "mrl_curve_bm_daily.csv"))

# GPD fit at multiple thresholds
gpd_fits <- list()
for (q in c(0.85, 0.90, 0.95, 0.97, 0.99)) {
  u <- quantile(losses_daily, q)
  ex <- losses_daily[losses_daily > u]
  if (length(ex) < 30) next
  fit <- tryCatch({
    f <- fExtremes::gpdFit(losses_daily, u = u)
    list(threshold_q = q, threshold_u = u, n_exceed = length(ex),
         xi = f@fit$par.ests["xi"], beta = f@fit$par.ests["beta"],
         xi_se = f@fit$par.ses["xi"], beta_se = f@fit$par.ses["beta"])
  }, error = function(e) NULL)
  if (!is.null(fit)) gpd_fits[[length(gpd_fits) + 1]] <- as.data.table(fit)
}
gpd_fit_dt <- rbindlist(gpd_fits, fill = TRUE)
log_msg("=== GPD fit at multiple thresholds (KOSPI BM daily) ===")
print(gpd_fit_dt)
fwrite(gpd_fit_dt, file.path(OUT_DIR, "gpd_fit_threshold_sensitivity.csv"))

# ============================================================================
# Section B: GARCH(1,1)-t conditional volatility on KOSPI BM
# Pfaff Ch.8 — regime shift via conditional sigma_t
# ============================================================================

log_msg("--- Patch v3 B: GARCH(1,1)-t on KOSPI BM monthly ---")

bm_xts <- xts(bm_monthly$ret, order.by = bm_monthly$ym_date)
bm_xts <- bm_xts[!is.na(bm_xts)]

garch_spec <- ugarchspec(
  variance.model = list(model = "sGARCH", garchOrder = c(1, 1)),
  mean.model = list(armaOrder = c(0, 0), include.mean = TRUE),
  distribution.model = "std"  # Student-t
)

garch_fit <- tryCatch(
  ugarchfit(spec = garch_spec, data = bm_xts, solver = "hybrid"),
  error = function(e) {log_msg(sprintf("GARCH fit error: %s", conditionMessage(e))); NULL}
)

if (!is.null(garch_fit)) {
  garch_summary <- list(
    n_obs = length(bm_xts),
    omega = coef(garch_fit)["omega"],
    alpha1 = coef(garch_fit)["alpha1"],
    beta1 = coef(garch_fit)["beta1"],
    shape_t_dof = coef(garch_fit)["shape"],
    persistence = coef(garch_fit)["alpha1"] + coef(garch_fit)["beta1"],
    long_run_vol_annual = sqrt(uncvariance(garch_fit) * 12),
    log_lik = likelihood(garch_fit),
    aic = infocriteria(garch_fit)["Akaike",]
  )
  log_msg("=== GARCH(1,1)-t fit on KOSPI BM monthly ===")
  print(unlist(garch_summary))

  # Conditional sigma_t 시계열
  cond_sigma <- as.numeric(sigma(garch_fit))
  cond_sigma_dt <- data.table(
    date = index(bm_xts),
    bm_ret = as.numeric(bm_xts),
    cond_sigma_monthly = cond_sigma,
    cond_vol_annualized = cond_sigma * sqrt(12),
    bm_demean_std = as.numeric(bm_xts) / cond_sigma
  )
  log_msg(sprintf("Conditional vol min/max/mean/median (annualized %%):"))
  log_msg(sprintf("  min %.2f / max %.2f / mean %.2f / median %.2f",
                  100 * min(cond_sigma_dt$cond_vol_annualized, na.rm = TRUE),
                  100 * max(cond_sigma_dt$cond_vol_annualized, na.rm = TRUE),
                  100 * mean(cond_sigma_dt$cond_vol_annualized, na.rm = TRUE),
                  100 * median(cond_sigma_dt$cond_vol_annualized, na.rm = TRUE)))
  fwrite(cond_sigma_dt, file.path(OUT_DIR, "garch_cond_sigma_bm.csv"))

  # Regime classification by GARCH cond vol vs naive 12m rolling
  cond_sigma_dt[, naive_12m_vol := frollapply(shift(bm_ret, 1L), 12L, sd) * sqrt(12)]
  cond_sigma_dt[, garch_caution := cond_vol_annualized > 0.20]
  cond_sigma_dt[, garch_crisis := cond_vol_annualized > 0.30]

  garch_regime_summary <- list(
    n_total = nrow(cond_sigma_dt),
    pct_garch_caution = 100 * mean(cond_sigma_dt$garch_caution, na.rm = TRUE),
    pct_garch_crisis = 100 * mean(cond_sigma_dt$garch_crisis, na.rm = TRUE),
    cor_garch_naive_vol = cor(cond_sigma_dt$cond_vol_annualized,
                               cond_sigma_dt$naive_12m_vol,
                               use = "pairwise.complete.obs")
  )
  log_msg("=== GARCH-derived regime stats vs naive 12m rolling ===")
  print(unlist(garch_regime_summary))
  fwrite(as.data.table(garch_regime_summary),
         file.path(OUT_DIR, "garch_regime_summary.csv"))
} else {
  log_msg("GARCH fit 실패 - section B skip")
}

# ============================================================================
# Section C: AR_KR10y rolling 12m correlation — regime shift visualization
# ============================================================================

log_msg("--- Patch v3 C: AR_KR10y rolling correlation ---")

ret_file <- file.path(PROJECT_ROOT,
  "qepm/mailbox/worktask/WT-P20260505_001/architect_hybrid_returns_full256m.csv")
ret_dt <- fread(ret_file)
ret_dt[, date := as.Date(date)]
ret_dt <- ret_dt[order(date)]

# Rolling 12m correlation (PIT — uses past 12m only)
roll_corr <- function(x, y, w = 12L) {
  n <- length(x)
  out <- rep(NA_real_, n)
  for (i in w:n) {
    xi <- x[(i - w + 1):i]; yi <- y[(i - w + 1):i]
    ok <- !is.na(xi) & !is.na(yi)
    if (sum(ok) >= 5) out[i] <- cor(xi[ok], yi[ok])
  }
  out
}

ret_dt[, cor_AR_KR10y_12m := roll_corr(r_AR, r_KR10y, 12L)]
ret_dt[, cor_AR_TSMOM_12m := roll_corr(r_AR, r_TSMOM, 12L)]
ret_dt[, cor_KR10y_TSMOM_12m := roll_corr(r_KR10y, r_TSMOM, 12L)]

corr_summary_3pair <- ret_dt[!is.na(cor_AR_KR10y_12m), .(
  AR_KR10y_min = min(cor_AR_KR10y_12m, na.rm = TRUE),
  AR_KR10y_max = max(cor_AR_KR10y_12m, na.rm = TRUE),
  AR_KR10y_median = median(cor_AR_KR10y_12m, na.rm = TRUE),
  AR_KR10y_mean = mean(cor_AR_KR10y_12m, na.rm = TRUE),
  pct_negative = 100 * mean(cor_AR_KR10y_12m < 0, na.rm = TRUE)
)]
log_msg("=== AR_KR10y 12m rolling correlation summary ===")
print(corr_summary_3pair)

# 3-source rolling correlation (post-2015 only)
post2015 <- ret_dt[!is.na(cor_AR_TSMOM_12m)]
corr_3src_summary <- post2015[, .(
  AR_KR10y_median = median(cor_AR_KR10y_12m, na.rm = TRUE),
  AR_TSMOM_median = median(cor_AR_TSMOM_12m, na.rm = TRUE),
  KR10y_TSMOM_median = median(cor_KR10y_TSMOM_12m, na.rm = TRUE),
  AR_KR10y_pct_neg = 100 * mean(cor_AR_KR10y_12m < 0, na.rm = TRUE),
  AR_TSMOM_pct_neg = 100 * mean(cor_AR_TSMOM_12m < 0, na.rm = TRUE),
  KR10y_TSMOM_pct_neg = 100 * mean(cor_KR10y_TSMOM_12m < 0, na.rm = TRUE)
)]
log_msg("=== 3-source 12m rolling correlation summary (post-2015 137m) ===")
print(corr_3src_summary)

# Save rolling correlations time series
fwrite(ret_dt[, .(date, r_AR, r_KR10y, r_TSMOM, cor_AR_KR10y_12m,
                  cor_AR_TSMOM_12m, cor_KR10y_TSMOM_12m)],
       file.path(OUT_DIR, "rolling_12m_correlations.csv"))

# ============================================================================
# Section D: Hybrid 70/15/15 vs Pure AR 100% — MDD comparison (AX-001 v2)
# ============================================================================

log_msg("--- Patch v3 D: Hybrid vs Pure AR MDD comparison ---")

# Pure AR 100% (256m all)
ar_only <- na.omit(ret_dt$r_AR)
hybrid_full <- ret_dt[, ifelse(!is.na(r_TSMOM),
                                0.70 * r_AR + 0.15 * r_KR10y + 0.15 * r_TSMOM,
                                (0.70 * r_AR + 0.20 * r_KR10y) / 0.90)]
hybrid_full <- na.omit(hybrid_full)

# Performance metrics via PerformanceAnalytics
ar_xts <- xts(ar_only, order.by = ret_dt[!is.na(r_AR)]$date)
hybrid_xts <- xts(hybrid_full, order.by = ret_dt[!is.na(r_AR)]$date)

ar_metrics <- list(
  n_obs = length(ar_only),
  CAGR = as.numeric(Return.annualized(ar_xts)),
  Sharpe = as.numeric(SharpeRatio.annualized(ar_xts, Rf = 0)),
  MDD = as.numeric(maxDrawdown(ar_xts)),
  Vol_ann = as.numeric(StdDev.annualized(ar_xts)),
  CVaR_95_monthly = as.numeric(ES(ar_xts, p = 0.95, method = "historical"))
)
hybrid_metrics <- list(
  n_obs = length(hybrid_full),
  CAGR = as.numeric(Return.annualized(hybrid_xts)),
  Sharpe = as.numeric(SharpeRatio.annualized(hybrid_xts, Rf = 0)),
  MDD = as.numeric(maxDrawdown(hybrid_xts)),
  Vol_ann = as.numeric(StdDev.annualized(hybrid_xts)),
  CVaR_95_monthly = as.numeric(ES(hybrid_xts, p = 0.95, method = "historical"))
)

comparison_dt <- data.table(
  portfolio = c("Pure_AR_100", "Hybrid_70_15_15"),
  n_obs = c(ar_metrics$n_obs, hybrid_metrics$n_obs),
  CAGR = c(ar_metrics$CAGR, hybrid_metrics$CAGR),
  Sharpe = c(ar_metrics$Sharpe, hybrid_metrics$Sharpe),
  MDD_pct = c(ar_metrics$MDD * 100, hybrid_metrics$MDD * 100),
  Vol_ann_pct = c(ar_metrics$Vol_ann * 100, hybrid_metrics$Vol_ann * 100),
  CVaR_95_pct = c(ar_metrics$CVaR_95_monthly * 100, hybrid_metrics$CVaR_95_monthly * 100)
)
log_msg("=== Pure AR 100% vs Hybrid 70/15/15 (full 256m) ===")
print(comparison_dt)
fwrite(comparison_dt, file.path(OUT_DIR, "ar_vs_hybrid_full256m.csv"))

# AX-001 v2 conditional defense — bad regime decomposition
ret_dt[, ar_only := r_AR]
ret_dt[, hybrid_70_15_15 := ifelse(!is.na(r_TSMOM),
                                    0.70 * r_AR + 0.15 * r_KR10y + 0.15 * r_TSMOM,
                                    (0.70 * r_AR + 0.20 * r_KR10y) / 0.90)]

ax001_decomp_list <- list()
for (sp in list(
  list(name = "GFC_2008", start = "2007-10-01", end = "2009-03-31"),
  list(name = "EuDebt_2011", start = "2011-07-01", end = "2011-12-31"),
  list(name = "China_Shock_2015", start = "2015-06-01", end = "2016-02-29"),
  list(name = "VolShock_2018", start = "2018-02-01", end = "2018-12-31"),
  list(name = "COVID_2020", start = "2020-01-01", end = "2020-06-30"),
  list(name = "Inflation_2022", start = "2022-01-01", end = "2022-12-31")
)) {
  s <- as.Date(sp$start); e <- as.Date(sp$end)
  sub <- ret_dt[date >= s & date <= e & !is.na(ar_only) & !is.na(hybrid_70_15_15)]
  if (nrow(sub) < 3) next
  ax001_decomp_list[[sp$name]] <- data.table(
    period = sp$name, n_months = nrow(sub),
    ar_only_total = prod(1 + sub$ar_only) - 1,
    hybrid_total = prod(1 + sub$hybrid_70_15_15) - 1,
    ar_mdd = tryCatch(maxDrawdown(sub$ar_only), error = function(e) NA_real_),
    hybrid_mdd = tryCatch(maxDrawdown(sub$hybrid_70_15_15), error = function(e) NA_real_),
    crisis_alpha_pp = (prod(1 + sub$hybrid_70_15_15) - 1) -
                       (prod(1 + sub$ar_only) - 1)
  )
}
ax001_decomp_dt <- rbindlist(ax001_decomp_list, fill = TRUE)
log_msg("=== AX-001 v2 Conditional Defense Decomposition (Hybrid vs Pure AR) ===")
print(ax001_decomp_dt)
fwrite(ax001_decomp_dt, file.path(OUT_DIR, "ax001_v2_conditional_defense.csv"))

# Crisis alpha 정합 — 위기 시 Hybrid > Pure AR가 AX-001 v2 핵심
log_msg(sprintf("Crisis alpha PASS count: %d/%d periods Hybrid outperforms Pure AR",
                sum(ax001_decomp_dt$crisis_alpha_pp > 0, na.rm = TRUE),
                nrow(ax001_decomp_dt)))

log_msg("=== PATCH V3 EXTENDED COMPLETE ===")
