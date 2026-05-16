#!/usr/bin/env Rscript
# Evaluation helpers for WT-D20260514_009 ML Alpha Cycle
# - rank_IC, ICIR, monotonicity (decile Q1-Q10)
# - Harvey 5-spec NW t-stat (CAPM / FF3 / Carhart4 / FF5 / FF6) with NW lag=6
# - DSR (Bailey-Lopez de Prado 2014)
# - Pareto 6-axis orthogonality vs reference alpha
# - Sub-period stability (3 periods: 2020-22 / 2023-24 / 2025-26)

suppressMessages({
  library(data.table); library(arrow); library(dplyr); library(lubridate)
  library(sandwich); library(lmtest)
})

# ===========================================================
# Rank IC per sig_date + ICIR
# ===========================================================
compute_rank_ic <- function(preds_dt, pred_col, target_col = "ret_1m_fwd_w") {
  preds_dt <- as.data.table(preds_dt)
  ic_by_sd <- preds_dt[!is.na(get(pred_col)) & !is.na(get(target_col)),
                        .(ic = cor(get(pred_col), get(target_col),
                                    method="spearman", use="pair"),
                          n = .N),
                        by = sig_date]
  ic_by_sd <- ic_by_sd[!is.na(ic)]
  list(
    ic_by_sd = ic_by_sd,
    mean_ic = mean(ic_by_sd$ic, na.rm=TRUE),
    median_ic = median(ic_by_sd$ic, na.rm=TRUE),
    sd_ic = sd(ic_by_sd$ic, na.rm=TRUE),
    icir = mean(ic_by_sd$ic, na.rm=TRUE) / sd(ic_by_sd$ic, na.rm=TRUE),
    pct_positive = mean(ic_by_sd$ic > 0, na.rm=TRUE),
    n_sig_dates = nrow(ic_by_sd)
  )
}

# ===========================================================
# Decile monotonicity (Q1 to Q10 mean forward returns)
# ===========================================================
compute_decile_monotonicity <- function(preds_dt, pred_col, target_col = "ret_1m_fwd_w", n_decile = 10) {
  preds_dt <- as.data.table(preds_dt)
  preds_dt <- preds_dt[!is.na(get(pred_col)) & !is.na(get(target_col))]
  # cross-section decile per sig_date
  preds_dt[, decile := cut(frank(get(pred_col), na.last="keep")/.N,
                           breaks=seq(0, 1, length.out=n_decile+1),
                           labels=1:n_decile, include.lowest=TRUE), by=sig_date]
  # monthly EW within decile, then time-series average
  dec_monthly <- preds_dt[, .(ret_dec = mean(get(target_col), na.rm=TRUE)), by=.(sig_date, decile)]
  dec_avg <- dec_monthly[, .(mean_ret = mean(ret_dec, na.rm=TRUE),
                              n_obs = .N), by=decile]
  setorder(dec_avg, decile)
  # Monotonicity: Spearman rank correlation between decile rank (1..10) and mean_ret
  mono_corr <- cor(as.numeric(as.character(dec_avg$decile)),
                    dec_avg$mean_ret, method="spearman")
  # Q10 - Q1 spread
  q10_q1_spread <- dec_avg[decile == n_decile, mean_ret] - dec_avg[decile == 1, mean_ret]
  list(
    decile_means = dec_avg,
    monotonicity_corr = mono_corr,
    q10_q1_spread = q10_q1_spread
  )
}

# ===========================================================
# Long-short monthly returns (Q10 long, Q1 short, EW within deciles)
# Used for Harvey-t and DSR calculations
# ===========================================================
build_ls_monthly <- function(preds_dt, pred_col, target_col = "ret_1m_fwd_w", n_decile = 10) {
  preds_dt <- as.data.table(preds_dt)
  preds_dt <- preds_dt[!is.na(get(pred_col)) & !is.na(get(target_col))]
  preds_dt[, decile := cut(frank(get(pred_col), na.last="keep")/.N,
                           breaks=seq(0, 1, length.out=n_decile+1),
                           labels=1:n_decile, include.lowest=TRUE), by=sig_date]
  dec_monthly <- preds_dt[, .(ret_dec = mean(get(target_col), na.rm=TRUE)),
                          by=.(sig_date, decile)]
  ls_dt <- dcast(dec_monthly, sig_date ~ decile, value.var="ret_dec")
  setnames(ls_dt, as.character(1:n_decile), paste0("Q", 1:n_decile))
  ls_dt[, LS := get(paste0("Q", n_decile)) - Q1]
  ls_dt[, sig_date := as.Date(sig_date)]
  ls_dt
}

# ===========================================================
# Long-only monthly returns (Q10 EW)
# ===========================================================
build_long_only_monthly <- function(preds_dt, pred_col, target_col = "ret_1m_fwd_w", n_decile = 10) {
  preds_dt <- as.data.table(preds_dt)
  preds_dt <- preds_dt[!is.na(get(pred_col)) & !is.na(get(target_col))]
  preds_dt[, decile := cut(frank(get(pred_col), na.last="keep")/.N,
                           breaks=seq(0, 1, length.out=n_decile+1),
                           labels=1:n_decile, include.lowest=TRUE), by=sig_date]
  ret_long <- preds_dt[decile == n_decile,
                        .(ret_top = mean(get(target_col), na.rm=TRUE),
                          n_top = .N),
                        by=sig_date]
  ret_long[, sig_date := as.Date(sig_date)]
  setorder(ret_long, sig_date)
  ret_long
}

# ===========================================================
# KR FF5 factor construction (admit precedent method)
# Mkt = compound BM_Ret monthly
# SMB = small - big (size median)
# HML = top V01_BM - bottom (top/bottom 30%)
# UMD = top 12-1m mom - bottom
# RMW = top Q02_ROE - bottom
# CMA = top Q07_Earnings_Stability - bottom
# ===========================================================
build_kr_factors_monthly <- function(date_min = "2016-01-01", date_max = "2026-05-31") {
  raw <- as.data.table(read_parquet(".cache/rawdata.parquet"))
  raw[, Date := as.Date(Date)]
  raw <- raw[Date >= as.Date(date_min) & Date <= as.Date(date_max)]
  raw[, ym := format(Date, "%Y-%m")]
  raw <- raw[!is.na(Ret) & is.finite(Ret) & abs(Ret) < 0.5]
  raw <- raw[!is.na(Size) & Size > 0]

  # Mkt = monthly compound BM_Ret
  bm_daily <- raw[, .(BM = first(BM_Ret)), by = .(Date, ym)]
  mkt_dt <- bm_daily[, .(Mkt = prod(1 + BM, na.rm=TRUE) - 1), by = ym]

  # Monthly returns per ticker
  ret_m <- raw[, .(ret_m = prod(1 + Ret) - 1), by = .(ym, Ticker)]
  size_first <- raw[, .(Size_first = first(Size)), by = .(ym, Ticker)]
  size_first[, size_med := median(Size_first, na.rm=TRUE), by = ym]
  size_first[, size_class := ifelse(Size_first <= size_med, "S", "B")]
  ret_with_size <- ret_m[size_first, on = c("ym","Ticker"), nomatch=0]
  smb_dt <- ret_with_size[, .(ret_class = mean(ret_m, na.rm=TRUE)), by = .(ym, size_class)]
  smb_dt <- dcast(smb_dt, ym ~ size_class, value.var="ret_class")
  smb_dt[, SMB := S - B]

  # For HML/UMD/RMW/CMA we need factor signals from features_master.
  # Simplification: use BM proxy from features_master if available, else skip.
  # Since features_master sig_date is month-end, ym key = format(sig_date, "%Y-%m")
  ft <- read_parquet("stage_artifacts/WT_D20260514_008/features_master.parquet")
  ft <- as.data.table(ft)
  ft[, ym := format(as.Date(sig_date), "%Y-%m")]

  build_top_bot <- function(score_col, ret_col = "ret_m") {
    # join ft (signal at sig_date = month-end t) with ret_m (return realized in month t+1)
    # IMPORTANT PIT: ft sig_date = end of month X. ret_m at ym = month X is realized AT month X.
    # Forward-month return: ret_m at ym = month X+1 should be used for signal at month X (sig_date end).
    # Build ym_signal = ft$ym, ym_realized = ym_signal + 1 month
    ft_sub <- ft[!is.na(get(score_col)), .(ym_signal = ym, Ticker, score = get(score_col))]
    ft_sub[, ym_realized := format(as.Date(paste0(ym_signal, "-01")) %m+% months(1), "%Y-%m")]
    setnames(ft_sub, "ym_realized", "ym")
    j <- merge(ft_sub, ret_m, by=c("ym","Ticker"), all.x=FALSE)
    j[, q70 := quantile(score, 0.70, na.rm=TRUE), by=ym_signal]
    j[, q30 := quantile(score, 0.30, na.rm=TRUE), by=ym_signal]
    j[, side := fifelse(score >= q70, "top",
                  fifelse(score <= q30, "bot", "mid"))]
    fac <- j[side != "mid", .(ret = mean(ret_m, na.rm=TRUE)),
              by = .(ym, side)]
    fac <- dcast(fac, ym ~ side, value.var="ret")
    fac[, factor_ret := top - bot]
    fac[, .(ym, factor_ret)]
  }

  hml_dt <- tryCatch(build_top_bot("fdb_m_V01_BM"), error=function(e) NULL)
  umd_dt <- tryCatch(build_top_bot("fdb_m_M01_Mom_12_1"), error=function(e) NULL)
  rmw_dt <- tryCatch(build_top_bot("fdb_m_Q02_ROE"), error=function(e) NULL)
  cma_dt <- tryCatch(build_top_bot("fdb_m_Q07_Earnings_Stability"), error=function(e) NULL)

  out <- mkt_dt[smb_dt[, .(ym, SMB)], on="ym"]
  if (!is.null(hml_dt)) {setnames(hml_dt, "factor_ret", "HML"); out <- out[hml_dt, on="ym"]}
  if (!is.null(umd_dt)) {setnames(umd_dt, "factor_ret", "UMD"); out <- out[umd_dt, on="ym"]}
  if (!is.null(rmw_dt)) {setnames(rmw_dt, "factor_ret", "RMW"); out <- out[rmw_dt, on="ym"]}
  if (!is.null(cma_dt)) {setnames(cma_dt, "factor_ret", "CMA"); out <- out[cma_dt, on="ym"]}

  out[, sig_date := as.Date(paste0(ym, "-01")) %m+% months(1) - days(1)]  # month-end
  out
}

# ===========================================================
# Harvey 5-spec NW t-stat (alpha intercept regression)
# strategy_ret = alpha + beta * factor_ret + epsilon
# H0: alpha = 0. Reject if |t_NW(alpha)| > 3.0 (Harvey-Liu-Zhu 2016)
# NW lag = 6 for monthly returns
# ===========================================================
harvey_5spec <- function(strategy_ret_dt, kr_factors_dt, ret_col = "LS", nw_lag = 6L) {
  # strategy_ret_dt: data.table with sig_date + ret_col
  # kr_factors_dt: ym + Mkt + SMB + HML + UMD + RMW + CMA
  strategy_ret_dt <- as.data.table(strategy_ret_dt)
  strategy_ret_dt[, ym := format(as.Date(sig_date), "%Y-%m")]
  m <- merge(strategy_ret_dt, kr_factors_dt, by="ym")
  m <- m[!is.na(get(ret_col))]
  y <- m[[ret_col]]

  run_lm <- function(rhs_cols, label) {
    rhs <- m[, ..rhs_cols]
    rhs_str <- paste(rhs_cols, collapse=" + ")
    fm <- as.formula(paste0("y ~ ", rhs_str))
    df <- data.frame(y=y, rhs)
    fit <- lm(fm, data=df)
    nw <- coeftest(fit, vcov = NeweyWest(fit, lag=nw_lag, prewhite=FALSE))
    alpha_idx <- which(rownames(nw) == "(Intercept)")
    list(
      spec = label,
      n_obs = nrow(m),
      alpha_monthly = as.numeric(nw[alpha_idx, "Estimate"]),
      se_NW = as.numeric(nw[alpha_idx, "Std. Error"]),
      t_NW = as.numeric(nw[alpha_idx, "t value"]),
      p_NW = as.numeric(nw[alpha_idx, "Pr(>|t|)"]),
      pass_t3 = abs(as.numeric(nw[alpha_idx, "t value"])) > 3.0,
      r_squared = summary(fit)$r.squared,
      coefs = setNames(as.numeric(nw[, "Estimate"]), rownames(nw))
    )
  }

  results <- list()
  if ("Mkt" %in% names(m))
    results$CAPM <- run_lm(c("Mkt"), "CAPM")
  if (all(c("Mkt","SMB","HML") %in% names(m)))
    results$FF3 <- run_lm(c("Mkt","SMB","HML"), "FF3")
  if (all(c("Mkt","SMB","HML","UMD") %in% names(m)))
    results$Carhart4 <- run_lm(c("Mkt","SMB","HML","UMD"), "Carhart4")
  if (all(c("Mkt","SMB","HML","RMW","CMA") %in% names(m)))
    results$FF5 <- run_lm(c("Mkt","SMB","HML","RMW","CMA"), "FF5")
  if (all(c("Mkt","SMB","HML","UMD","RMW","CMA") %in% names(m)))
    results$FF6 <- run_lm(c("Mkt","SMB","HML","UMD","RMW","CMA"), "FF6")

  pass_count <- sum(sapply(results, function(r) r$pass_t3))
  list(
    specs = results,
    pass_count = pass_count,
    total_specs = length(results),
    pass_3of5 = pass_count >= 3
  )
}

# ===========================================================
# DSR (Bailey-Lopez de Prado 2014)
# DSR = Pr(SR > 0 | observed SR_hat, skew, kurt, N) adjusted by max(SR_trials)
# Simplified: use estimated max_SR from N_trials = 5 (ex-ante grid strict)
# ===========================================================
compute_dsr <- function(ret_series, N_trials = 5L, ann_factor = 12) {
  ret <- ret_series[!is.na(ret_series)]
  T <- length(ret)
  if (T < 12) return(list(dsr = NA, sr_hat = NA, sr_max_expected = NA))
  sr_hat <- mean(ret, na.rm=TRUE) / sd(ret, na.rm=TRUE)  # not annualized
  # Skew, kurt
  sk <- mean((ret - mean(ret))^3, na.rm=TRUE) / sd(ret)^3
  ku <- mean((ret - mean(ret))^4, na.rm=TRUE) / sd(ret)^4
  # Expected max SR over N trials (Bailey-LdP eqn 5)
  E <- 0.5772156649  # Euler-Mascheroni
  sr_max_exp <- sqrt(2 * log(N_trials)) - (E + log(log(N_trials))) / (2 * sqrt(2 * log(N_trials)))
  # PSR (probabilistic sharpe ratio) vs sr_max_exp
  numerator <- (sr_hat - sr_max_exp) * sqrt(T - 1)
  denom <- sqrt(1 - sk * sr_hat + (ku - 1) / 4 * sr_hat^2)
  if (is.na(denom) || denom <= 0) return(list(dsr = NA, sr_hat = sr_hat, sr_max_expected = sr_max_exp))
  z <- numerator / denom
  dsr <- pnorm(z)
  list(
    dsr = dsr,
    z = z,
    sr_hat_monthly = sr_hat,
    sr_hat_annual = sr_hat * sqrt(ann_factor),
    sr_max_expected = sr_max_exp,
    sr_max_expected_annual = sr_max_exp * sqrt(ann_factor),
    T = T,
    N_trials = N_trials,
    skew = sk,
    kurt = ku
  )
}

# ===========================================================
# Pareto 6-axis orthogonality vs reference (e.g., STR_1715 score_eff)
# 1. monthly Pearson cor (alpha-level)
# 2. monthly Spearman cor (rank-level)
# 3. monthly Kendall tau (concordance)
# 4. Lower-tail dependence coefficient (TDC) — using empirical quantile cor
# 5. Daily-or-monthly cross cor at portfolio realized return level
# 6. Diversification ratio: 1 - sqrt(var(combined)) / (w1*sd(r1) + w2*sd(r2))
# ===========================================================
pareto_6axis <- function(ml_alpha_dt, ref_alpha_dt, key_cols = c("sig_date","Ticker"),
                          ml_col = "pred_ensemble", ref_col = "score_eff") {
  ml_alpha_dt <- as.data.table(ml_alpha_dt)
  ref_alpha_dt <- as.data.table(ref_alpha_dt)
  # align sig_date format
  if ("Date" %in% names(ref_alpha_dt)) ref_alpha_dt[, sig_date := as.Date(Date)]
  ml_alpha_dt[, sig_date := as.Date(sig_date)]
  ref_alpha_dt[, sig_date := as.Date(sig_date)]

  m <- merge(ml_alpha_dt[, c(key_cols, ml_col), with=FALSE],
              ref_alpha_dt[, c(key_cols, ref_col), with=FALSE],
              by=key_cols, all=FALSE)
  m <- m[!is.na(get(ml_col)) & !is.na(get(ref_col))]
  if (nrow(m) < 100) return(list(error = "too few observations"))

  # 1. Pooled Pearson
  rho_pearson <- cor(m[[ml_col]], m[[ref_col]], method="pearson")
  # 2. Pooled Spearman (rank IC)
  rho_spearman <- cor(m[[ml_col]], m[[ref_col]], method="spearman")
  # 3. Pooled Kendall tau (use small subset for speed if huge)
  if (nrow(m) > 20000) {
    set.seed(42L)
    msub <- m[sample(.N, 20000)]
  } else msub <- m
  rho_kendall <- cor(msub[[ml_col]], msub[[ref_col]], method="kendall")

  # 4. Lower-tail dependence: pr(rank(X)<q | rank(Y)<q) at q=0.10
  q_lo <- 0.10
  rx <- frank(m[[ml_col]], na.last="keep") / nrow(m)
  ry <- frank(m[[ref_col]], na.last="keep") / nrow(m)
  tdc_lower <- mean(rx < q_lo & ry < q_lo) / mean(ry < q_lo)
  tdc_upper <- mean(rx > (1-q_lo) & ry > (1-q_lo)) / mean(ry > (1-q_lo))

  # 5. Cross-section average per-sig_date cor (rebalance-aware)
  per_sd <- m[, .(rho_sd = cor(get(ml_col), get(ref_col), method="spearman", use="pair"),
                   n_sd = .N), by=sig_date]
  per_sd <- per_sd[!is.na(rho_sd)]
  mean_per_sd_cor <- mean(per_sd$rho_sd, na.rm=TRUE)

  # 6. Diversification proxy: build EW Q10 returns for each, then ts cor
  # (deferred to step3_evaluate — need both forward returns linked)

  list(
    pearson = rho_pearson,
    spearman = rho_spearman,
    kendall = rho_kendall,
    tdc_lower_q10 = tdc_lower,
    tdc_upper_q10 = tdc_upper,
    mean_per_sigdate_spearman = mean_per_sd_cor,
    n_observations = nrow(m),
    n_sig_dates_compared = nrow(per_sd),
    per_sd_correlations = per_sd
  )
}

# ===========================================================
# Sub-period stability (3 periods)
# Mean IC per sub-period; stability = min/max
# ===========================================================
compute_subperiod_stability <- function(preds_dt, pred_col, target_col = "ret_1m_fwd_w") {
  preds_dt <- as.data.table(preds_dt)
  preds_dt[, sig_date := as.Date(sig_date)]
  preds_dt[, period := fcase(
    sig_date < as.Date("2023-01-01"), "P1_2020_22",
    sig_date < as.Date("2025-01-01"), "P2_2023_24",
    default = "P3_2025_26"
  )]
  ic_period <- preds_dt[!is.na(get(pred_col)) & !is.na(get(target_col)),
                         .(ic_pooled = cor(get(pred_col), get(target_col),
                                            method="spearman", use="pair"),
                           n = .N),
                         by = period]
  setorder(ic_period, period)
  positive_periods <- sum(ic_period$ic_pooled > 0)
  list(
    by_period = ic_period,
    min_ic = min(ic_period$ic_pooled, na.rm=TRUE),
    max_ic = max(ic_period$ic_pooled, na.rm=TRUE),
    stability_ratio = if (max(ic_period$ic_pooled, na.rm=TRUE) > 0)
      min(ic_period$ic_pooled) / max(ic_period$ic_pooled) else NA,
    positive_periods = positive_periods,
    n_periods = nrow(ic_period)
  )
}

cat("evaluation_helpers.R loaded.\n")
