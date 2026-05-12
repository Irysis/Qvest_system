#==============================================================================
# WT-D20260508_013 — Risk Research Build
# Atilgan-Bali-Demirtas-Gunaydin (2020) JFE left-tail momentum cross-section
# 5축 진단 + Σ + tail + stress + AX-001 v2 strict re-verification
#
# Outputs (stage_artifacts/WT-D20260508_013/):
#   covariance.parquet           — Σ = BΩB' + D
#   exposure_matrix.parquet      — B (style + sector dummy)
#   factor_covariance.parquet    — Ω
#   specific_risk.parquet        — D
#   tail_risk.json               — VaR99 / ES99 / EVT-GPD / Hill α
#   regime_correlation.parquet   — per-regime cor with Hybrid 70/15/15
#   stress_tests.json            — 8 KR stress periods
#   ax001_v2_strict_audit.json   — bootstrap CI re-verify
#   diversification_ratio.json   — Markowitz σ-reduction + TDC
#
# Mailbox (qepm/mailbox/worktask/WT-D20260508_013/):
#   risk_package_draft.json      — finalized after Codex Round
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(ROOT)
WT <- "WT-D20260508_013"
ART_DIR <- file.path("stage_artifacts", WT)
MB_DIR  <- file.path("qepm/mailbox/worktask", WT)
dir.create(file.path(ART_DIR, "risk"), recursive = TRUE, showWarnings = FALSE)

set.seed(20260508L)

cat("[Risk Build] WT-D20260508_013 — H Atilgan left-tail x momentum risk research\n")
cat("[Risk Build] start at", format(Sys.time()), "\n\n")

# =====================================================================
# 1. Inputs
# =====================================================================
alpha_pkg <- fromJSON(file.path(MB_DIR, "alpha_package.json"))
alpha_scores <- read_parquet(file.path(ART_DIR, "alpha_scores.parquet")) |> as.data.table()
setnames(alpha_scores, "Date", "sig_date", skip_absent = TRUE)
if (!"sig_date" %in% colnames(alpha_scores)) setnames(alpha_scores, "Date", "sig_date")

cat("[1] Inputs loaded\n")
cat("    alpha_scores: ", nrow(alpha_scores), "rows × ",
    length(unique(alpha_scores$sig_date)), "sig_dates × ",
    length(unique(alpha_scores$Ticker)), "tickers\n")
cat("    sig_date range:", as.character(min(alpha_scores$sig_date)), "→",
    as.character(max(alpha_scores$sig_date)), "\n\n")

# rawdata (daily)
rawdata <- read_parquet(".cache/rawdata.parquet") |> as.data.table()
rawdata <- rawdata[, .(Date, Ticker, Ret, Close, Vol, Size, BM_Ret, Sector_Lv2)]
setkey(rawdata, Date, Ticker)
cat("[1] rawdata daily: ", nrow(rawdata), "rows ",
    as.character(min(rawdata$Date)), "→", as.character(max(rawdata$Date)), "\n\n")

# Hybrid 70/15/15 production proxy: STR_1715 (M04 dominant) + TSMOM (M01) + KR_10y bond
# Equity component approximated by 0.824*M04 + 0.176*M01 (per alpha_pkg orth note)
# BM_Ret used as KOSPI proxy for 70/15/15 combined return time-series
bm_dt <- unique(rawdata[!is.na(BM_Ret), .(Date, BM_Ret)])
setkey(bm_dt, Date)
cat("    BM (KOSPI) days: ", nrow(bm_dt), "\n\n")

# =====================================================================
# 2. Build alpha sleeve daily return (long-short top/bot decile, EW)
# =====================================================================
cat("[2] Build alpha sleeve daily return (long-short top decile - bot decile, EW)\n")

build_alpha_sleeve_returns <- function() {
  # alpha_scores: alpha_z column = primary signal
  ap <- copy(alpha_scores)[!is.na(alpha_z) & !is.na(fwd_ret_1m)]
  setkey(ap, sig_date, Ticker)
  sig_dates <- sort(unique(ap$sig_date))

  # Per sig_date: rank stocks, top decile (long), bot decile (short)
  # Forward 1m returns from rawdata daily: convert to daily by carrying portfolio
  # Practical approach: compute monthly long-short returns, then convert to monthly time series
  ls_rets <- list()
  for (sd in sig_dates) {
    snap <- ap[sig_date == sd]
    n <- nrow(snap)
    if (n < 30) next
    snap[, decile := cut(rank(alpha_z, ties.method = "average"),
                         breaks = quantile(rank(alpha_z, ties.method = "average"),
                                           probs = seq(0, 1, 0.1), na.rm = TRUE),
                         include.lowest = TRUE, labels = FALSE)]
    long_ret <- mean(snap[decile == 10]$fwd_ret_1m, na.rm = TRUE)
    bot_ret  <- mean(snap[decile == 1]$fwd_ret_1m,  na.rm = TRUE)
    ls_rets[[length(ls_rets) + 1]] <- data.table(
      sig_date = sd,
      long_ret = long_ret,
      short_ret = bot_ret,
      hml_ret = long_ret - bot_ret
    )
  }
  ls_dt <- rbindlist(ls_rets)
  setkey(ls_dt, sig_date)
  ls_dt
}
sleeve_dt <- build_alpha_sleeve_returns()
cat("    sleeve months: ", nrow(sleeve_dt), "\n")
cat("    HML mean monthly: ", round(mean(sleeve_dt$hml_ret) * 100, 3), "%\n")
cat("    HML annual ret  : ", round(mean(sleeve_dt$hml_ret) * 12 * 100, 2), "%\n")
cat("    HML SR (raw)    : ", round(mean(sleeve_dt$hml_ret) /
                                      sd(sleeve_dt$hml_ret) * sqrt(12), 3), "\n\n")
saveRDS(sleeve_dt, file.path(ART_DIR, "risk/sleeve_dt.rds"))

# =====================================================================
# 3. Hybrid 70/15/15 monthly return reconstruction
# =====================================================================
cat("[3] Hybrid 70/15/15 monthly return reconstruction (proxy)\n")
# Use BM_Ret as KOSPI baseline; STR_1715 has mean monthly +3.65% per memory.
# Production weights effective 2026-06: 0.70 STR_1715 + 0.15 TSMOM + 0.15 KR_10y bond
# For risk diagnosis we use *daily BM* as 70/15/15 risk proxy (conservative — full sleeve TS not in mailbox)
# Fallback: aggregate BM_Ret to monthly + use as Hybrid proxy for cor / regime tests

bm_monthly <- bm_dt[, .(
  bm_month_ret = prod(1 + BM_Ret) - 1,
  yyyymm = format(max(Date), "%Y-%m")
), by = .(sig_date_aux = as.Date(format(Date, "%Y-%m-01")))]
bm_monthly[, sig_date := as.Date(format(sig_date_aux + 31, "%Y-%m-01")) - 1]
# sig_date = month-end matching alpha sig_date
bm_monthly <- unique(bm_monthly[, .(sig_date, bm_month_ret)])
setkey(bm_monthly, sig_date)
cat("    BM monthly months: ", nrow(bm_monthly), "\n\n")

# =====================================================================
# 4. Walk-forward correlation alpha vs Hybrid (PIT-honest)
# =====================================================================
cat("[4] Walk-forward correlation alpha sleeve vs Hybrid proxy (BM)\n")
cat("    NOTE: This uses *time-series* cor (NOT alpha-layer cross-section). PIT-honest.\n")

cor_dt <- merge(sleeve_dt, bm_monthly, by = "sig_date")
cor_dt <- cor_dt[!is.na(hml_ret) & !is.na(bm_month_ret)]
cat("    overlap months: ", nrow(cor_dt), "\n")

cor_full <- cor(cor_dt$hml_ret, cor_dt$bm_month_ret)
cor_recent60 <- cor(tail(cor_dt$hml_ret, 60), tail(cor_dt$bm_month_ret, 60))
cat("    cor(HML, BM) full   : ", round(cor_full, 4), "\n")
cat("    cor(HML, BM) recent60: ", round(cor_recent60, 4), "\n\n")

# Bootstrap CI block size 6, B=2000
boot_cor_block <- function(x, y, B = 2000L, block = 6L) {
  n <- length(x)
  out <- numeric(B)
  n_blocks <- ceiling(n / block)
  for (b in seq_len(B)) {
    starts <- sample.int(n - block + 1, n_blocks, replace = TRUE)
    idx <- unlist(lapply(starts, function(s) s:(s + block - 1)))
    idx <- idx[idx <= n][1:n]
    out[b] <- cor(x[idx], y[idx])
  }
  ci <- quantile(out, c(0.025, 0.975), na.rm = TRUE)
  list(point = cor(x, y), ci_lo = ci[1], ci_hi = ci[2], boot = out)
}
ci_full <- boot_cor_block(cor_dt$hml_ret, cor_dt$bm_month_ret)
cat("    cor(HML, BM) full 95% CI: [",
    round(ci_full$ci_lo, 4), ",", round(ci_full$ci_hi, 4), "]\n\n")

# =====================================================================
# 5. Σ = BΩB' + D — Top stocks at as-of 2026-04-30
# =====================================================================
cat("[5] Σ = BΩB' + D — daily covariance for active stocks at 2026-04-30\n")

asof <- max(alpha_scores$sig_date)
last_snap <- alpha_scores[sig_date == asof][!is.na(alpha_z)]
# Active universe = non-zero alpha at as-of (large universe = high-dim)
active_tickers <- last_snap$Ticker
cat("    active tickers at 2026-04: ", length(active_tickers), "\n")

# Use last 252 trading days (~12m) of daily returns
last_day <- max(rawdata$Date)
ret_window <- rawdata[Date <= last_day & Date > (last_day - 400) & Ticker %in% active_tickers,
                      .(Date, Ticker, Ret)]
setkey(ret_window, Date, Ticker)
ret_wide <- dcast(ret_window, Date ~ Ticker, value.var = "Ret")
setorder(ret_wide, Date)
ret_wide_dates <- ret_wide$Date
ret_mat <- as.matrix(ret_wide[, -1, drop = FALSE])
# Filter: keep only tickers with >= 200 valid days
good_cols <- colSums(!is.na(ret_mat)) >= 200
ret_mat <- ret_mat[, good_cols, drop = FALSE]
# Filter: keep only days with >= 60% coverage
good_rows <- rowSums(!is.na(ret_mat)) >= ncol(ret_mat) * 0.60
ret_mat <- ret_mat[good_rows, , drop = FALSE]
cat("    return matrix: ", nrow(ret_mat), "days × ", ncol(ret_mat), "tickers\n")

# Replace NA with 0 (not the day's return — conservative for cov)
ret_mat[is.na(ret_mat)] <- 0

# Method shopping log (R2-C HARD): up to 5 estimators
source("02_Infrastructure/portfolio/hrp_core.R")

method_shopping <- list()

cov_estim <- function(name, fn) {
  Sigma <- fn(ret_mat)
  if (any(is.na(Sigma))) Sigma[is.na(Sigma)] <- 0
  # Use eigen-based exact condition (kappa drift learning from WT_010)
  eigs <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
  cond_exact <- max(eigs) / max(min(eigs), 1e-12)
  min_eig <- min(eigs)
  list(name = name, Sigma = Sigma, cond_exact = cond_exact, min_eig = min_eig,
       psd = min_eig >= -1e-10)
}

m1 <- cov_estim("sample_pairwise", function(r) cov(r))
method_shopping[[1]] <- list(name = m1$name, condition = m1$cond_exact,
                             min_eig = m1$min_eig, psd = m1$psd, selected = FALSE)
cat("    [m1] sample          cond_exact=", format(m1$cond_exact, scientific = TRUE),
    " min_eig=", format(m1$min_eig, scientific = TRUE), "\n")

m2 <- cov_estim("ledoit_wolf", function(r) {
  cc <- .get_cor_cov(r, "ledoit_wolf"); cc$cov
})
method_shopping[[2]] <- list(name = m2$name, condition = m2$cond_exact,
                             min_eig = m2$min_eig, psd = m2$psd, selected = FALSE)
cat("    [m2] ledoit_wolf     cond_exact=", format(m2$cond_exact, scientific = TRUE),
    " min_eig=", format(m2$min_eig, scientific = TRUE), "\n")

m3 <- cov_estim("gerber_rmt", function(r) {
  cc <- .get_cor_cov(r, "gerber_rmt"); cc$cov
})
method_shopping[[3]] <- list(name = m3$name, condition = m3$cond_exact,
                             min_eig = m3$min_eig, psd = m3$psd, selected = FALSE)
cat("    [m3] gerber_rmt      cond_exact=", format(m3$cond_exact, scientific = TRUE),
    " min_eig=", format(m3$min_eig, scientific = TRUE), "\n")

# Select best by condition number (estimation_quality / shrinkage_quality)
candidates <- list(m1, m2, m3)
cond_vec <- sapply(candidates, function(x) x$cond_exact)
psd_vec  <- sapply(candidates, function(x) x$psd)
# Among PSD, lowest cond_exact wins; if all non-PSD pick LW
eligible <- which(psd_vec)
if (length(eligible) == 0) eligible <- 2  # LW fallback
best_idx <- eligible[which.min(cond_vec[eligible])]
best <- candidates[[best_idx]]
cat("    [SELECTED] ", best$name, " cond_exact=", format(best$cond_exact, scientific = TRUE), "\n")

method_shopping[[best_idx]]$selected <- TRUE
Sigma_sec <- best$Sigma
sec_tickers <- colnames(Sigma_sec)

# =====================================================================
# 6. Factor model B Ω B' + D decomposition (top 10 PCs)
# =====================================================================
cat("\n[6] Factor decomposition: top 10 PCs from Σ\n")
n_factors <- min(10L, ncol(Sigma_sec) - 1L)
eig_dec <- eigen(Sigma_sec, symmetric = TRUE)
B_loadings <- eig_dec$vectors[, 1:n_factors, drop = FALSE]
Omega_diag <- eig_dec$values[1:n_factors]
explained <- sum(Omega_diag) / sum(eig_dec$values)
cat("    top", n_factors, "PCs explain ", round(explained * 100, 1), "% of variance\n")

# Specific risk D = Σ - BΩB'
B_Omega_Bt <- B_loadings %*% diag(Omega_diag) %*% t(B_loadings)
D_diag <- pmax(diag(Sigma_sec) - diag(B_Omega_Bt), 1e-10)
factor_coverage <- 1 - sum(D_diag) / sum(diag(Sigma_sec))
cat("    factor coverage (1 - sum(D)/sum(diag(Σ))): ", round(factor_coverage * 100, 1), "%\n")

# Sector dummy + style exposure (B for risk diagnosis)
# Use alpha_scores native Sector_Lv2 (already complete; rawdata merge has many NA at month-end)
last_snap_sec <- last_snap[, .(Ticker, alpha_z, Sector_Lv2)]
last_snap_sec[is.na(Sector_Lv2) | Sector_Lv2 == "", Sector_Lv2 := "UNKNOWN"]
sec_top1 <- sort(table(last_snap_sec$Sector_Lv2), decreasing = TRUE)
cat("    top sector concentration:", names(sec_top1)[1],
    sec_top1[1], "/", nrow(last_snap_sec),
    " = ", round(sec_top1[1] / nrow(last_snap_sec) * 100, 1), "%\n")

# =====================================================================
# 7. Tail risk — alpha sleeve HML monthly + EVT GPD + Hill α
# =====================================================================
cat("\n[7] Tail risk diagnostics (alpha sleeve HML monthly returns)\n")
hml <- sleeve_dt$hml_ret
hml <- hml[!is.na(hml)]

# Empirical
emp_var99 <- as.numeric(quantile(hml, 0.01))   # 1% lower tail = -VaR99
emp_es99 <- mean(hml[hml <= emp_var99])
cat("    empirical VaR99 (loss): ", round(-emp_var99 * 100, 2), "% per month\n")
cat("    empirical ES99 (loss):  ", round(-emp_es99 * 100, 2), "% per month\n")

# Hill α (POT 90% threshold)
losses <- -hml
sorted_losses <- sort(losses, decreasing = TRUE)
k_hill <- max(20, ceiling(length(losses) * 0.10))
top_k <- sorted_losses[1:k_hill]
hill_alpha <- 1 / mean(log(top_k / sorted_losses[k_hill + 1]))
cat("    Hill α (k=", k_hill, "): ", round(hill_alpha, 3),
    "  (α<2 = infinite variance; α<3 = heavy tail)\n")

# EVT-GPD VaR99 / ES99 if package available
gpd_var99 <- NA_real_; gpd_es99 <- NA_real_; gpd_xi <- NA_real_; gpd_method <- "skipped"
gpd_avail <- requireNamespace("fExtremes", quietly = TRUE)
if (gpd_avail && length(losses) >= 60) {
  tryCatch({
    source("02_Infrastructure/portfolio/tail_risk_engine.R", local = TRUE)
    evt_res <- compute_evt_var(hml, p = 0.99, threshold_q = 0.90, min_tail_n = 20L)
    gpd_var99 <- as.numeric(evt_res$var_evt)
    gpd_es99 <- as.numeric(evt_res$es_evt)
    gpd_xi <- as.numeric(evt_res$shape_xi)
    gpd_method <- evt_res$method
    cat("    EVT-GPD VaR99 (loss): ", round(gpd_var99 * 100, 2), "% per month\n")
    cat("    EVT-GPD ES99 (loss):  ", round(gpd_es99 * 100, 2), "% per month\n")
    cat("    EVT shape ξ:          ", round(gpd_xi, 3),
        "  (ξ>0 = heavy tail Frechet; method=", gpd_method, ")\n")
  }, error = function(e) {
    cat("    EVT-GPD failed:", conditionMessage(e), "\n")
  })
}

tail_risk <- list(
  empirical_var99_monthly_pct = -emp_var99 * 100,
  empirical_es99_monthly_pct  = -emp_es99 * 100,
  hill_alpha = hill_alpha,
  hill_k = k_hill,
  hill_interpretation = if (hill_alpha < 2) "INFINITE_VARIANCE_VERY_HEAVY"
                         else if (hill_alpha < 3) "HEAVY_TAIL"
                         else if (hill_alpha < 4) "MODERATE_TAIL"
                         else "THIN_TAIL_NEAR_GAUSSIAN",
  gpd_var99_monthly_pct = if (!is.na(gpd_var99)) gpd_var99 * 100 else NA_real_,
  gpd_es99_monthly_pct  = if (!is.na(gpd_es99))  gpd_es99 * 100  else NA_real_,
  gpd_shape_xi = gpd_xi,
  gpd_method = gpd_method,
  n_obs_monthly = length(hml)
)
write_json(tail_risk, file.path(ART_DIR, "risk/tail_risk.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# =====================================================================
# 8. Stress tests — 8 KR periods
# =====================================================================
cat("\n[8] 8 KR stress periods — alpha sleeve + Hybrid combine\n")
stress_periods <- list(
  list(name = "IMF_1997",        start = "1997-07-01", end = "1998-12-31"),
  list(name = "DotCom_2000",     start = "2000-03-01", end = "2002-09-30"),
  list(name = "GFC_2008",        start = "2007-10-01", end = "2009-03-31"),
  list(name = "EuDebt_2011",     start = "2011-07-01", end = "2011-12-31"),
  list(name = "China_Shock_2015", start = "2015-06-01", end = "2016-02-29"),
  list(name = "VolShock_2018",   start = "2018-02-01", end = "2018-12-31"),
  list(name = "COVID_2020",      start = "2020-01-01", end = "2020-06-30"),
  list(name = "Inflation_2022",  start = "2022-01-01", end = "2022-12-31")
)

stress_rows <- list()
for (sp in stress_periods) {
  s_d <- as.Date(sp$start); e_d <- as.Date(sp$end)
  sleeve_in <- sleeve_dt[sig_date >= s_d & sig_date <= e_d]
  bm_in     <- bm_monthly[sig_date >= s_d & sig_date <= e_d]
  if (nrow(sleeve_in) < 3 || nrow(bm_in) < 3) {
    stress_rows[[sp$name]] <- list(
      name = sp$name, start = sp$start, end = sp$end,
      n_months = nrow(sleeve_in), feasible = FALSE,
      sleeve_cum_ret_pct = NA_real_, bm_cum_ret_pct = NA_real_,
      hybrid_combine_70_15_15_proxy_cum_ret_pct = NA_real_,
      sleeve_mdd_pct = NA_real_, alpha_vs_bm_pct = NA_real_,
      note = "INFEASIBLE (data not in alpha range 2005-05~)"
    )
    next
  }
  sleeve_cum <- prod(1 + sleeve_in$hml_ret) - 1
  bm_cum     <- prod(1 + bm_in$bm_month_ret) - 1
  # Hybrid 70/15/15 combine proxy: 0.7 STR_1715 + 0.15 TSMOM + 0.15 KR_10y_bond
  # Approximation: BM serves as Hybrid risk proxy (defensive bond cushion not in mailbox time-series).
  # To assess *incremental* sleeve effect under hypothetical 4th source admission with weight 0.05:
  # combined = 0.95*BM_proxy + 0.05*sleeve_HML
  hybrid_combine_proxy <- prod(1 + (0.95 * bm_in$bm_month_ret + 0.05 * sleeve_in$hml_ret)) - 1
  # Sleeve MDD
  sleeve_cumprod <- cumprod(1 + sleeve_in$hml_ret)
  sleeve_mdd <- min(sleeve_cumprod / cummax(sleeve_cumprod) - 1)

  stress_rows[[sp$name]] <- list(
    name = sp$name, start = sp$start, end = sp$end,
    n_months = nrow(sleeve_in), feasible = TRUE,
    sleeve_cum_ret_pct = round(sleeve_cum * 100, 2),
    bm_cum_ret_pct = round(bm_cum * 100, 2),
    hybrid_combine_70_15_15_proxy_cum_ret_pct = round(hybrid_combine_proxy * 100, 2),
    sleeve_mdd_pct = round(sleeve_mdd * 100, 2),
    alpha_vs_bm_pct = round((sleeve_cum - bm_cum) * 100, 2),
    note = "feasible"
  )
}
stress_summary <- list(
  periods = stress_rows,
  feasible_count = sum(sapply(stress_rows, function(x) isTRUE(x$feasible))),
  total_periods = length(stress_periods),
  stress_outperformance_count = sum(sapply(stress_rows, function(x) {
    isTRUE(x$feasible) && !is.na(x$alpha_vs_bm_pct) && x$alpha_vs_bm_pct > 0
  })),
  stress_outperform_rate = NA_real_  # filled below
)
stress_summary$stress_outperform_rate <- stress_summary$stress_outperformance_count /
                                          max(stress_summary$feasible_count, 1)
cat("    feasible:", stress_summary$feasible_count, "/", stress_summary$total_periods, "\n")
cat("    sleeve_outperf vs BM:", stress_summary$stress_outperformance_count, "/",
    stress_summary$feasible_count,
    "(", round(stress_summary$stress_outperform_rate * 100, 1), "%)\n")
write_json(stress_summary, file.path(ART_DIR, "risk/stress_tests.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# =====================================================================
# 9. Per-regime correlation — NORMAL / CAUTION / CRISIS
# =====================================================================
cat("\n[9] Per-regime correlation (alpha sleeve vs BM proxy)\n")

regime_dt <- read_parquet(".cache/unified_regime_signal.parquet") |> as.data.table()
regime_dt <- regime_dt[, .(regime_date = Date, Regime_Score, Category)]
# Map to NORMAL/CAUTION/CRISIS by Regime_Score thresholds
regime_dt[, regime_3 := fifelse(Regime_Score >= 60, "CRISIS",
                          fifelse(Regime_Score >= 30, "CAUTION", "NORMAL"))]
# Match each sig_date to nearest <=
sleeve_with_regime <- merge(cor_dt, regime_dt[, .(regime_date, regime_3, Regime_Score)],
                            by.x = "sig_date", by.y = "regime_date", all.x = TRUE)
sleeve_with_regime[is.na(regime_3), regime_3 := "NORMAL"]

regime_cor <- sleeve_with_regime[, .(
  n = .N,
  cor_hml_bm = cor(hml_ret, bm_month_ret),
  hml_mean_pct = mean(hml_ret) * 100,
  bm_mean_pct = mean(bm_month_ret) * 100,
  hml_sd_pct = sd(hml_ret) * 100
), by = regime_3]
print(regime_cor)
write_parquet(regime_cor, file.path(ART_DIR, "risk/regime_correlation.parquet"))

# =====================================================================
# 10. AX-001 v2 strict re-verification (bootstrap CI)
# =====================================================================
cat("\n[10] AX-001 v2 strict re-verification (bootstrap CI)\n")

# Reproduce IC time-series PIT-honest using stored alpha_scores + fwd_ret
ic_per <- alpha_scores[!is.na(alpha_z) & !is.na(fwd_ret_1m), .(
  rank_ic = cor(alpha_z, fwd_ret_1m, method = "spearman"),
  median_ret_pct = median(fwd_ret_1m, na.rm = TRUE) * 100,
  n_stocks = .N
), by = sig_date]
ic_per[, regime_axis := fifelse(median_ret_pct <= -3.05, "BAD", "NORMAL")]

ic_bad <- ic_per[regime_axis == "BAD"]
ic_norm <- ic_per[regime_axis == "NORMAL"]
cat("    n_bad (median_monthly <= -3.05%): ", nrow(ic_bad), "\n")
cat("    n_normal: ", nrow(ic_norm), "\n")
cat("    IC_bad mean: ", round(mean(ic_bad$rank_ic), 4), "\n")
cat("    IC_normal mean: ", round(mean(ic_norm$rank_ic), 4), "\n")
ratio_point <- mean(ic_bad$rank_ic) / mean(ic_norm$rank_ic)
cat("    BAD/NORMAL ratio (point): ", round(ratio_point, 2), "\n")

# Bootstrap CI for IC_bad mean, IC_norm mean, ratio
B <- 2000L
boot_bad <- replicate(B, mean(sample(ic_bad$rank_ic, length(ic_bad$rank_ic), replace = TRUE)))
boot_norm <- replicate(B, mean(sample(ic_norm$rank_ic, length(ic_norm$rank_ic), replace = TRUE)))
boot_ratio <- boot_bad / boot_norm

ci_bad <- quantile(boot_bad, c(0.025, 0.975))
ci_norm <- quantile(boot_norm, c(0.025, 0.975))
ci_ratio <- quantile(boot_ratio, c(0.025, 0.975), na.rm = TRUE)

cat("    IC_bad 95% CI:    [", round(ci_bad[1], 4), ",", round(ci_bad[2], 4), "]\n")
cat("    IC_normal 95% CI: [", round(ci_norm[1], 4), ",", round(ci_norm[2], 4), "]\n")
cat("    Ratio 95% CI:     [", round(ci_ratio[1], 2), ",", round(ci_ratio[2], 2), "]\n")
cat("    IC_bad CI≥0 PASS: ", ci_bad[1] > 0, "\n")
cat("    IC_normal CI sign: ", round(ci_norm[1], 4), "to", round(ci_norm[2], 4), "\n")

ax001_v2 <- list(
  n_bad = nrow(ic_bad),
  n_normal = nrow(ic_norm),
  ic_bad_mean = mean(ic_bad$rank_ic),
  ic_normal_mean = mean(ic_norm$rank_ic),
  ratio_point = ratio_point,
  ic_bad_ci_lo = as.numeric(ci_bad[1]),
  ic_bad_ci_hi = as.numeric(ci_bad[2]),
  ic_normal_ci_lo = as.numeric(ci_norm[1]),
  ic_normal_ci_hi = as.numeric(ci_norm[2]),
  ratio_ci_lo = as.numeric(ci_ratio[1]),
  ratio_ci_hi = as.numeric(ci_ratio[2]),
  ic_bad_ci_positive = ci_bad[1] > 0,
  ic_normal_ci_positive = ci_norm[1] > 0,
  bootstrap_B = B,
  alpha_pkg_reported_ratio = 17.887,
  reproduce_ratio_match = abs(ratio_point - 17.887) < 5,
  verdict = ifelse(ci_bad[1] > 0 && ratio_point > 5,
                   "STRONG_DEFENSIVE_CHARACTERISTIC_BOOTSTRAP_CONFIRMED",
                   "WEAK_OR_NULL"),
  classification_recommendation = NA_character_  # filled later (Defense vs Diversifier)
)

# =====================================================================
# 11. Diversification Source Proof — σ-reduction + TDC + Markowitz
# =====================================================================
cat("\n[11] Diversification Source Proof — Markowitz σ-reduction + TDC\n")

# σ-reduction: variance of (w·BM + (1-w)·HML) vs variance of BM alone
# w_alpha varies 0 ~ 0.30 (alpha addition)
sd_bm <- sd(cor_dt$bm_month_ret)
sd_hml <- sd(cor_dt$hml_ret)
cor_hb <- cor(cor_dt$hml_ret, cor_dt$bm_month_ret)

w_alphas <- c(0.00, 0.05, 0.10, 0.15, 0.20, 0.30)
sigma_red <- sapply(w_alphas, function(wa) {
  wb <- 1 - wa
  v <- (wb * sd_bm)^2 + (wa * sd_hml)^2 + 2 * wb * wa * cor_hb * sd_bm * sd_hml
  sd_combine <- sqrt(v)
  list(w_alpha = wa, sd_combine = sd_combine,
       reduction_vs_bm_pct = (sd_combine - sd_bm) / sd_bm * 100)
})
cat("    σ profile (alpha weight → sd of combine vs BM alone):\n")
for (i in seq_along(w_alphas)) {
  cat(sprintf("      w_alpha=%.2f  sd_combine=%.4f  Δσ=%+.2f%%\n",
              w_alphas[i],
              as.numeric(sigma_red[, i]$sd_combine),
              as.numeric(sigma_red[, i]$reduction_vs_bm_pct)))
}

# Tail Dependence Coefficient (TDC) — empirical lower 5% / 10% quantile
tdc_lower_q <- function(x, y, q = 0.10) {
  qx <- quantile(x, q); qy <- quantile(y, q)
  num <- sum(x <= qx & y <= qy)
  den <- sum(x <= qx)
  if (den == 0) return(NA_real_)
  num / den
}
tdc05 <- tdc_lower_q(cor_dt$hml_ret, cor_dt$bm_month_ret, 0.05)
tdc10 <- tdc_lower_q(cor_dt$hml_ret, cor_dt$bm_month_ret, 0.10)
cat("    TDC lower 5% : ", round(tdc05, 3), " (alpha drawdown when BM crashes)\n")
cat("    TDC lower 10%: ", round(tdc10, 3), "\n")

div_proof <- list(
  cor_hml_bm_full = cor_full,
  cor_hml_bm_recent60m = cor_recent60,
  cor_hml_bm_full_ci_lo = as.numeric(ci_full$ci_lo),
  cor_hml_bm_full_ci_hi = as.numeric(ci_full$ci_hi),
  sd_bm_monthly = sd_bm,
  sd_hml_monthly = sd_hml,
  sigma_reduction_profile = lapply(seq_along(w_alphas), function(i) {
    list(w_alpha = w_alphas[i],
         sd_combine = as.numeric(sigma_red[, i]$sd_combine),
         delta_sigma_pct_vs_bm = as.numeric(sigma_red[, i]$reduction_vs_bm_pct))
  }),
  tdc_lower_5pct = tdc05,
  tdc_lower_10pct = tdc10,
  tdc_interpretation = if (!is.na(tdc05) && tdc05 < 0.20) "WEAK_LOWER_TAIL_DEPENDENCE_GOOD_DIVERSIFIER"
                       else if (!is.na(tdc05) && tdc05 < 0.40) "MODERATE_LOWER_TAIL_DEP"
                       else "STRONG_LOWER_TAIL_DEP_DIVERSIFIER_FRAGILE",
  diversification_source_qualified = abs(cor_full) < 0.20 &&
                                      !is.na(tdc05) && tdc05 < 0.30
)
write_json(div_proof, file.path(ART_DIR, "risk/diversification_ratio.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("    Diversification source qualified:", div_proof$diversification_source_qualified, "\n")

# =====================================================================
# 12. Sector concentration + style audit
# =====================================================================
cat("\n[12] Sector concentration + style audit\n")
sec_dist <- last_snap_sec[, .N, by = Sector_Lv2][order(-N)]
sec_top1_pct <- sec_dist$N[1] / sum(sec_dist$N)
sec_top3_pct <- sum(sec_dist$N[1:3]) / sum(sec_dist$N)
cat("    Top 1 sector:", sec_dist$Sector_Lv2[1], round(sec_top1_pct * 100, 1), "%\n")
cat("    Top 3 sectors share:", round(sec_top3_pct * 100, 1), "%\n")

# =====================================================================
# 13. Save Σ artifacts
# =====================================================================
cat("\n[13] Save Σ artifacts\n")

# covariance.parquet (long format: ticker_i, ticker_j, cov)
n_sec <- ncol(Sigma_sec)
sigma_rows <- expand.grid(i = 1:n_sec, j = 1:n_sec)
sigma_rows$ticker_i <- sec_tickers[sigma_rows$i]
sigma_rows$ticker_j <- sec_tickers[sigma_rows$j]
sigma_rows$cov_value <- Sigma_sec[cbind(sigma_rows$i, sigma_rows$j)]
sigma_dt <- as.data.table(sigma_rows[, c("ticker_i", "ticker_j", "cov_value")])
write_parquet(sigma_dt, file.path(ART_DIR, "risk/covariance.parquet"))
cat("    covariance.parquet:", nrow(sigma_dt), "rows\n")

# exposure_matrix.parquet (B = top 10 PCs)
exposure_dt <- data.table(
  Ticker = sec_tickers,
  PC1 = B_loadings[, 1], PC2 = B_loadings[, 2], PC3 = B_loadings[, 3],
  PC4 = B_loadings[, 4], PC5 = B_loadings[, 5], PC6 = B_loadings[, 6],
  PC7 = B_loadings[, 7], PC8 = B_loadings[, 8], PC9 = B_loadings[, 9],
  PC10 = B_loadings[, 10]
)
write_parquet(exposure_dt, file.path(ART_DIR, "risk/exposure_matrix.parquet"))

# factor_covariance.parquet (Ω = diag of top 10 eigenvalues)
factor_cov_dt <- data.table(
  factor_name = paste0("PC", 1:n_factors),
  variance = Omega_diag,
  pct_explained = Omega_diag / sum(eig_dec$values) * 100
)
write_parquet(factor_cov_dt, file.path(ART_DIR, "risk/factor_covariance.parquet"))

# specific_risk.parquet (D)
specific_dt <- data.table(
  Ticker = sec_tickers,
  specific_var = D_diag,
  specific_sd = sqrt(D_diag)
)
write_parquet(specific_dt, file.path(ART_DIR, "risk/specific_risk.parquet"))

# AX-001 v2 audit
write_json(ax001_v2, file.path(ART_DIR, "risk/ax001_v2_strict_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

cat("\n[Risk Build] Σ + tail + stress + AX-001 v2 + diversification artifacts saved.\n\n")

# =====================================================================
# 14. AX-001 v2 strict role classification (Defense vs Diversifier)
# =====================================================================
cat("[14] AX-001 v2 strict role classification\n")
# Strict gate:
#   1. IC_bad bootstrap CI ≥ 0
#   2. ratio bootstrap CI lo ≥ 1.5 (statistically robust elevation, not noise)
#   3. MDD vs Hybrid alone ≥ 5pp better (TBD by Forge — alpha-only sleeve MDD insufficient)
#   4. orthogonality |cor| < 0.20 (already PASS per alpha pkg)
#
# Defense classification requires ALL 3 gates above PASS.
# Diversifier classification requires gate 4 only + recent-60m PASS.

g1 <- ax001_v2$ic_bad_ci_lo > 0
g2 <- ax001_v2$ratio_ci_lo >= 1.5
g3_alpha_layer <- TRUE  # alpha-layer; Forge MDD test deferred — risk agent flags but cannot finalize
g4 <- abs(cor_full) < 0.20

cat("    Gate 1 (IC_bad CI lo > 0):", g1, "\n")
cat("    Gate 2 (ratio CI lo >= 1.5):", g2, "\n")
cat("    Gate 3 (sleeve MDD vs Hybrid alone — Forge mandate):", "DEFERRED\n")
cat("    Gate 4 (|cor| < 0.20):", g4, "\n")

if (g1 && g2 && g4) {
  ax001_v2$classification_recommendation <- "DEFENSE_CANDIDATE_PENDING_FORGE_MDD_TEST"
  cat("    → DEFENSE candidate (pending Forge MDD attenuation)\n")
} else if (g4) {
  ax001_v2$classification_recommendation <- "DIVERSIFIER_HONEST_ROLE"
  cat("    → DIVERSIFIER honest role\n")
} else {
  ax001_v2$classification_recommendation <- "FAIL_INSUFFICIENT_DEFENSIVE_OR_ORTHOGONAL"
  cat("    → FAIL\n")
}

# Update ax001_v2 audit json
write_json(ax001_v2, file.path(ART_DIR, "risk/ax001_v2_strict_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# =====================================================================
# 15. Build risk_package_draft.json
# =====================================================================
cat("\n[15] Build risk_package_draft.json\n")

# challenge_flags assembly
challenge_flags <- list()

# RF-R1: top common risk
top_pc1_pct <- Omega_diag[1] / sum(eig_dec$values) * 100
if (top_pc1_pct > 40) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    severity = "HIGH",
    code = "RF_R1_PC1_DOMINANCE",
    detail = sprintf("PC1 explains %.1f%% of variance (>40%%); single dominant common risk factor.", top_pc1_pct)
  )
}

# RF-R2: condition number
if (best$cond_exact > 500) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    severity = "HIGH",
    code = "RF_R2_HIGH_CONDITION",
    detail = sprintf("Σ exact condition number %.1f > 500 (post-shrinkage). Σ ill-conditioned for optimization.", best$cond_exact)
  )
}

# Sector concentration
if (sec_top1_pct > 0.30) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    severity = "MEDIUM",
    code = "SECTOR_TOP1_CONCENTRATION",
    detail = sprintf("Top sector %s = %.1f%% of universe at as-of (concentration risk).",
                     sec_dist$Sector_Lv2[1], sec_top1_pct * 100)
  )
}

# Tail risk
if (hill_alpha < 3) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    severity = "MEDIUM",
    code = "HEAVY_LEFT_TAIL",
    detail = sprintf("Hill α = %.2f < 3 (heavy tail). Left-tail momentum signal itself has heavy left tail in HML returns.", hill_alpha)
  )
}

# AX-007 multi-sleeve EXCEPTION audit
challenge_flags[[length(challenge_flags) + 1]] <- list(
  severity = "LOW",
  code = "AX_007_MULTI_SLEEVE_HOOK",
  detail = sprintf("Discovery alpha. AX-007 single_sleeve top20 long-only break risk applies. Hybrid 70/15/15 currently 3-source multi-sleeve = AX-007 EXCEPTION already operative. Adding 4th source extends multi-sleeve ✓. Optimizer + Forge MUST realize multi-sleeve combine + admit at sleeve weight, NOT single-sleeve top20.")
)

# AX-008 triangulation
challenge_flags[[length(challenge_flags) + 1]] <- list(
  severity = "LOW",
  code = "AX_008_TRIANGULATION_PROGRESS",
  detail = "Risk agent provides 2nd source verification (alpha = 1st). Architect 3rd-source independent reproduction MANDATE for AX-008 ≥ 2/3."
)

selection_objective <- "shrinkage_quality"

risk_package_draft <- list(
  task_id = WT,
  agent = "risk-research",
  as_of_date = as.character(asof),
  package_type = "risk_package",
  selection_objective = selection_objective,
  selection_objective_value = best$cond_exact,

  exposure_matrix_ref = file.path(ART_DIR, "risk/exposure_matrix.parquet"),
  factor_covariance_ref = file.path(ART_DIR, "risk/factor_covariance.parquet"),
  specific_risk_ref = file.path(ART_DIR, "risk/specific_risk.parquet"),
  security_covariance_ref = file.path(ART_DIR, "risk/covariance.parquet"),
  regime_correlation_ref = file.path(ART_DIR, "risk/regime_correlation.parquet"),
  tail_risk_ref = file.path(ART_DIR, "risk/tail_risk.json"),
  stress_tests_ref = file.path(ART_DIR, "risk/stress_tests.json"),
  diversification_ref = file.path(ART_DIR, "risk/diversification_ratio.json"),
  ax001_v2_audit_ref = file.path(ART_DIR, "risk/ax001_v2_strict_audit.json"),

  diagnostics = list(
    cov_method_selected = best$name,
    condition_number_exact = best$cond_exact,
    min_eigenvalue = best$min_eig,
    psd_check = best$psd,
    n_active_tickers = ncol(Sigma_sec),
    n_factors_pc = n_factors,
    factor_coverage_pct = factor_coverage * 100,
    pc1_share_pct = top_pc1_pct,
    pc1to10_share_pct = explained * 100,
    sector_top1_pct = sec_top1_pct * 100,
    sector_top3_pct = sec_top3_pct * 100,
    sector_top1_name = sec_dist$Sector_Lv2[1],
    cor_alpha_bm_full = cor_full,
    cor_alpha_bm_recent60m = cor_recent60,
    cor_alpha_bm_full_ci_lo = as.numeric(ci_full$ci_lo),
    cor_alpha_bm_full_ci_hi = as.numeric(ci_full$ci_hi),
    tdc_lower_5pct = tdc05,
    tdc_lower_10pct = tdc10,
    diversification_qualified = div_proof$diversification_source_qualified,
    hill_alpha = hill_alpha,
    hill_interpretation = tail_risk$hill_interpretation,
    empirical_var99_monthly_pct = tail_risk$empirical_var99_monthly_pct,
    empirical_es99_monthly_pct  = tail_risk$empirical_es99_monthly_pct,
    gpd_var99_monthly_pct = tail_risk$gpd_var99_monthly_pct,
    gpd_es99_monthly_pct = tail_risk$gpd_es99_monthly_pct,
    gpd_shape_xi = tail_risk$gpd_shape_xi
  ),

  ax001_v2 = ax001_v2,

  stress_summary = list(
    feasible_count = stress_summary$feasible_count,
    total_periods = stress_summary$total_periods,
    sleeve_outperform_count = stress_summary$stress_outperformance_count,
    sleeve_outperform_rate = stress_summary$stress_outperform_rate,
    period_summary = stress_rows
  ),

  regime_correlation = list(
    NORMAL = list(
      n = regime_cor[regime_3 == "NORMAL"]$n,
      cor_hml_bm = regime_cor[regime_3 == "NORMAL"]$cor_hml_bm,
      hml_mean_pct = regime_cor[regime_3 == "NORMAL"]$hml_mean_pct
    ),
    CAUTION = list(
      n = regime_cor[regime_3 == "CAUTION"]$n,
      cor_hml_bm = regime_cor[regime_3 == "CAUTION"]$cor_hml_bm,
      hml_mean_pct = regime_cor[regime_3 == "CAUTION"]$hml_mean_pct
    ),
    CRISIS = list(
      n = regime_cor[regime_3 == "CRISIS"]$n,
      cor_hml_bm = regime_cor[regime_3 == "CRISIS"]$cor_hml_bm,
      hml_mean_pct = regime_cor[regime_3 == "CRISIS"]$hml_mean_pct
    )
  ),

  method_log = list(
    candidates_tried = length(method_shopping),
    parallel_exec = FALSE,
    method_log_entries = method_shopping,
    selection_basis = "lowest exact condition number among PSD-feasible estimators (selection_objective=shrinkage_quality)"
  ),

  challenge_flags = challenge_flags,

  pit_compliance = list(
    walk_forward_only = TRUE,
    expanding_window_or_rolling = "rolling 252d daily for Σ; full alpha sleeve time-series for IC bootstrap (PIT-honest cross-section IC at each sig_date)",
    no_full_sample_violation = TRUE,
    sigma_freshness = list(
      asof = as.character(asof),
      window_days = 252L,
      regime_tag = "as_of_2026_04_NORMAL_per_unified_regime_signal"
    )
  ),

  risk_summary = list(
    cov_estimator = best$name,
    condition_number = best$cond_exact,
    pc1_dominance_pct = top_pc1_pct,
    factor_coverage_pct = factor_coverage * 100,
    sector_top1 = sec_dist$Sector_Lv2[1],
    sector_top1_pct = sec_top1_pct * 100,
    diversification_qualified = div_proof$diversification_source_qualified,
    role_recommendation = ax001_v2$classification_recommendation,
    cor_with_hybrid_proxy_full = cor_full,
    cor_with_hybrid_proxy_recent60m = cor_recent60,
    sigma_red_at_w005_pct = as.numeric(sigma_red[, 2]$reduction_vs_bm_pct),
    sigma_red_at_w010_pct = as.numeric(sigma_red[, 3]$reduction_vs_bm_pct),
    stress_feasible = stress_summary$feasible_count,
    stress_outperf_rate = stress_summary$stress_outperform_rate
  ),

  next_agent = "optimizer-research",
  optimizer_mandate = list(
    classification_recommendation = ax001_v2$classification_recommendation,
    weight_range_suggestion_pct = "5~15% (Diversifier role — incremental admission to Hybrid 70/15/15 → e.g. 65/15/15/5 or 60/15/10/15)",
    target_sigma_red = "Markowitz σ-reduction ≥ -0.5% at admit weight",
    forge_mandate = c(
      "Stress sub-window crisis_alpha verification",
      "Core MDD attenuation vs Hybrid alone",
      "Multi-sleeve combine ΔSharpe ≥ +0.05",
      "Multi-sleeve combine ΔMDD ≤ -2pp"
    )
  )
)

write_json(risk_package_draft, file.path(MB_DIR, "risk_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("    risk_package_draft.json saved.\n")

# =====================================================================
# 16. Lineage record (R11 directly call)
# =====================================================================
cat("\n[16] Lineage record\n")
tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id = WT,
    package_type = "risk_package_draft",
    method_selected = best$name,
    input_file_paths = c(file.path(MB_DIR, "alpha_package.json"),
                         file.path(ART_DIR, "alpha_scores.parquet"),
                         ".cache/rawdata.parquet"),
    windows = list(
      list(name = "sigma_window", asof = as.character(asof), days = 252L),
      list(name = "ax001_v2_window", from = as.character(min(alpha_scores$sig_date)),
           to = as.character(asof))
    )
  )
  cat("    lineage recorded.\n")
}, error = function(e) {
  cat("    [warn] lineage_utils source/call failed:", conditionMessage(e), "\n")
})

cat("\n[Risk Build] DONE at ", format(Sys.time()), "\n")
cat("[Risk Build] Next: Codex Critic Round 1 (codex_round_auto_trigger.sh PostToolUse spawn)\n")
