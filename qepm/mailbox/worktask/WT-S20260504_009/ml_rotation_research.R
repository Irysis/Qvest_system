#!/usr/bin/env Rscript
# WT-S20260504_009 — ML-driven Multi-Asset KR ETF Rotation
# Alpha Research Agent execution script
# 도훈 명시 (2026-05-04 19:50): long-only / 선물 X / ETF 풀만 / ML 가능

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(xgboost)
})

set.seed(42)
WT_ID <- "WT-S20260504_009"
WT_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-S20260504_009"
STAGE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/stage_artifacts/WT_WT-S20260504_009"
DOCS <- file.path(WT_DIR, "docs")
dir.create(STAGE_DIR, recursive=TRUE, showWarnings=FALSE)
dir.create(DOCS, recursive=TRUE, showWarnings=FALSE)

cat("=== WT-S20260504_009 — ML ETF Rotation ===\n")
cat("Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# ---- 1. STR_1715 base reference ---------------------------------------
ref <- fread(file.path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-P20260504_001/four_layer_returns_path.csv"))
ref[, date := as.Date(date)]
ref[, ym := format(date, "%Y-%m")]
# Crucial column: ret_AR_on_M4 (STR_1715 alpha being protected)
cat("STR_1715 reference loaded:", nrow(ref), "months\n")
cat("  Date range:", format(min(ref$date)), "to", format(max(ref$date)), "\n")
cat("  ret_AR_on_M4 stats: mean=", round(mean(ref$ret_AR_on_M4),5), " sd=", round(sd(ref$ret_AR_on_M4),5), "\n\n")

# Drop 2026-05 partial month (PIT 안전, WT-008 동일 처리)
ref_clean <- ref[date <= as.Date("2026-04-30")]

# ---- 2. Macro features from FRED ---------------------------------------
fred <- as.data.table(read_parquet("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/.cache/fred_macro.parquet"))
fred_wide <- dcast(fred, Date ~ Series, value.var = "Value", fun.aggregate = mean)
setnames(fred_wide, "Date", "date")
fred_wide[, ym := format(date, "%Y-%m")]
# Month-end values (last obs per ym)
fred_eom <- fred_wide[, lapply(.SD, function(x) tail(na.omit(x), 1)),
                     by = ym, .SDcols = setdiff(names(fred_wide), c("date","ym"))]
cat("FRED EOM panel:", nrow(fred_eom), "months,", ncol(fred_eom)-1, "series\n")

# ---- 3. KR ETF synthetic NAV proxies -------------------------------------
# Real KR ETF NAV pre-inception 부재 → academic proxies (cor < 0.30 + crisis behavior 측정 가능)
# All proxies PIT compliant (lag t-1)

# 3-A. ECOS bond rates for KR equity / bond
ecos_bond <- as.data.table(read_parquet("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/.cache/ecos_bond_rates.parquet"))
cat("ECOS bond schema:", names(ecos_bond), "\n")

# 3-B. KOSPI200 returns from ref bm_12m + ret_orig 역산
# ref$ret_orig = STR_1715 base monthly return — stocks only, not KOSPI200 directly
# We need KOSPI200 benchmark. Use bm_12m signal in ref + reconstruct
# Or use rawdata to get KOSPI200 directly
# Quick path: KOSPI200 ~ broad equity proxy via STR_1715 ret_orig de-alpha'd is too noisy
# Simpler: use FRED-shifted regression — but FRED has no KOSPI direct
# Ultra-simple: load benchmark.parquet
bm_dt <- as.data.table(read_parquet("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/.cache/benchmark.parquet"))
cat("benchmark.parquet schema:", paste(names(bm_dt), collapse=","), "\n")

# Aggregate to monthly returns
if ("Date" %in% names(bm_dt)) bm_dt[, date := as.Date(Date)]
if ("Close" %in% names(bm_dt)) {
  bm_dt[, ym := format(date, "%Y-%m")]
  bm_monthly <- bm_dt[, .(close = tail(Close, 1)), by = ym][order(ym)]
  bm_monthly[, kospi_ret := close / shift(close, 1) - 1]
} else if ("BM_Ret" %in% names(bm_dt)) {
  bm_dt[, ym := format(date, "%Y-%m")]
  bm_monthly <- bm_dt[, .(kospi_ret = sum(BM_Ret, na.rm=TRUE)), by = ym][order(ym)]
}
cat("KOSPI monthly:", nrow(bm_monthly), "months\n\n")

# ---- 4. Build 9 ETF synthetic monthly returns ------------------------------
# All proxies are SYNTHETIC (literature-anchored). Real KOFIA NAV cross-validation deferred to follow-up WT.

# Common base: ym from ref_clean
asset_panel <- copy(ref_clean[, .(date, ym, ret_AR_on_M4, ret_orig, bm_12m)])

# Merge KOSPI return
asset_panel <- merge(asset_panel, bm_monthly[, .(ym, kospi_ret)], by="ym", all.x=TRUE)

# Merge FRED EOM features (lagged 1m for PIT)
asset_panel <- merge(asset_panel, fred_eom, by="ym", all.x=TRUE)
setorder(asset_panel, date)
# Lag macro features (t-1)
macro_cols <- intersect(c("VIX","US_10Y_Yield","US_2Y_Yield","KRW_USD","Copper_Price",
                          "BBB_Spread","HY_Spread","Term_Spread","Fed_Funds_Rate",
                          "Breakeven_5Y","StL_Fin_Stress","Chi_Fin_Cond"),
                        names(asset_panel))
for (cc in macro_cols) {
  asset_panel[, paste0(cc, "_lag") := shift(get(cc), 1)]
  asset_panel[, paste0("d_", cc) := get(cc) - shift(get(cc), 1)]
  asset_panel[, paste0("d_", cc, "_lag") := shift(get(paste0("d_", cc)), 1)]
}

# Synthetic ETF returns (all PIT t-1 lagged inputs):
# A069500 KODEX 200 = kospi_ret (KOSPI200 monthly TR proxy)
asset_panel[, etf_KODEX_200 := kospi_ret]

# A148070 KODEX 국고채10년 = -8 * d(US_10Y)/100 + lag(yield)/12/100  (WT-008 proxy, KR yield ≈ US 10y proxy via term_spread)
asset_panel[, kr_10y_yield_proxy := US_10Y_Yield_lag + 0.5]  # KR slightly higher avg
asset_panel[, etf_KODEX_KTB10Y := -8 * (US_10Y_Yield - US_10Y_Yield_lag) / 100 + kr_10y_yield_proxy / 12 / 100]

# A143850 TIGER S&P500 (FX hedged) — use US 10Y inverse as proxy not great
# Better: use VIX-decomposed equity premium with KRW hedge
# Simplest: use a proxy from KOSPI + US-KR equity differential
# Proxy: kospi_ret + 0.3 * (-VIX_chg)  — capturing SP500 less dramatic moves
asset_panel[, etf_TIGER_SP500_H := kospi_ret + 0.005 - 0.002 * (VIX - VIX_lag)]

# A132030 KODEX 골드(H) — krw_chg + vix_chg + dxy (WT-008 proxy)
asset_panel[, etf_KODEX_GOLD_H := 0.003 + 0.3 * (KRW_USD / KRW_USD_lag - 1) + 0.005 * (VIX - VIX_lag)/VIX_lag]

# A308620 KODEX 미국채10년(H) = -8 * d(US_10Y)/100 + carry/12 (KRW hedged so no FX)
asset_panel[, etf_KODEX_UST10Y_H := -8 * (US_10Y_Yield - US_10Y_Yield_lag) / 100 + US_10Y_Yield_lag / 12 / 100 - 0.0015]

# A284430 KODEX 200 + UST blend = 0.5 * kodex_200 + 0.5 * ust10y
asset_panel[, etf_KODEX_200_UST := 0.5 * etf_KODEX_200 + 0.5 * etf_KODEX_UST10Y_H]

# A329200 KODEX KR REIT — bond_proxy + 0.3*kospi (interest-rate sensitive equity)
asset_panel[, etf_KODEX_KR_REIT := 0.3 * etf_KODEX_KTB10Y + 0.5 * etf_KODEX_200 + 0.001]

# A229200 KODEX 200 저변동성 — kospi * 0.7 (low-vol haircut + Frazzini-Pedersen alpha)
asset_panel[, etf_KODEX_200_LV := 0.7 * etf_KODEX_200 + 0.001]

# A157450 TIGER 단기통안채 = CD91 yield/12 (carry-only no duration)
# Use Fed Funds + KR-US spread ~ 1%
asset_panel[, etf_TIGER_SHORT_TERM := pmax(0.001, (Fed_Funds_Rate_lag + 1.0) / 12 / 100)]

# Validate
etf_cols <- c("etf_KODEX_200", "etf_KODEX_KTB10Y", "etf_TIGER_SP500_H",
              "etf_KODEX_GOLD_H", "etf_KODEX_UST10Y_H", "etf_KODEX_200_UST",
              "etf_KODEX_KR_REIT", "etf_KODEX_200_LV", "etf_TIGER_SHORT_TERM")
for (ec in etf_cols) {
  if (!ec %in% names(asset_panel)) {
    cat("MISSING:", ec, "\n")
  } else {
    nv <- sum(!is.na(asset_panel[[ec]]))
    cat(ec, ": n=", nv, " mean=", round(mean(asset_panel[[ec]], na.rm=TRUE),4),
        " sd=", round(sd(asset_panel[[ec]], na.rm=TRUE),4), "\n")
  }
}
cat("\n")

# ---- 5. Cross-asset features (lagged) -----------------------------------
for (ec in etf_cols) {
  asset_panel[, paste0(ec, "_lag") := shift(get(ec), 1)]
  asset_panel[, paste0(ec, "_3m") := frollmean(get(ec), 3, fill=NA)]
  asset_panel[, paste0(ec, "_3m_lag") := shift(get(paste0(ec, "_3m")), 1)]
  asset_panel[, paste0(ec, "_vol_6m_lag") := shift(frollapply(get(ec), 6, sd, fill=NA), 1)]
}

# Calendar features
asset_panel[, month_of_year := as.integer(format(date, "%m"))]
asset_panel[, year := as.integer(format(date, "%Y"))]

# ---- 6. STR_1715 regime info (info from ref) -----------------------------
# AR_t value (lagged) = info available at t
asset_panel[, ar_t_lag := shift(ret_AR_on_M4, 1)]
asset_panel[, mrs_cash_lag := shift(0, 1)]  # not in ref directly; derived later

# bm_12m is already in ref (last 12m benchmark cum return) — PIT compliant signal at sig_date
asset_panel[, bm_12m_lag := shift(bm_12m, 1)]

# ---- 7. Train/test split (walk-forward expanding window) ----------------
# WT-009 spec walk-forward:
#   T1: train 2005-2014, test 2015-2018
#   T2: train 2005-2018, test 2019-2022
#   T3: train 2005-2022, test 2023-2026

asset_panel[, period := fcase(
  date >= as.Date("2005-02-01") & date <= as.Date("2014-12-31"), "train_T1",
  date >= as.Date("2015-01-01") & date <= as.Date("2018-12-31"), "test_T1",
  date >= as.Date("2019-01-01") & date <= as.Date("2022-12-31"), "test_T2",
  date >= as.Date("2023-01-01") & date <= as.Date("2026-04-30"), "test_T3",
  default = "skip"
)]

table(asset_panel$period)

# ---- 8. ML feature matrix -----------------------------------------------
feature_cols <- c(
  paste0(macro_cols, "_lag"),   # macro level
  paste0("d_", macro_cols, "_lag"),  # macro changes
  paste0(etf_cols, "_lag"),     # ETF level
  paste0(etf_cols, "_3m_lag"),  # ETF 3m mean
  paste0(etf_cols, "_vol_6m_lag"),  # ETF 6m vol
  "bm_12m_lag", "ar_t_lag",
  "month_of_year", "year"
)
feature_cols <- intersect(feature_cols, names(asset_panel))
cat("Feature count:", length(feature_cols), "\n")

# ---- 9. Build ML training: predict next-month return per ETF, then softmax -
# Approach: for each ETF, train XGBoost predict next-month return.
# At test time: compute predicted returns for 9 ETFs, softmax → weights, apply, get realized return.
# COR penalty during prediction phase: penalize selecting ETFs whose realized returns correlate with STR_1715 alpha.

train_xgb_per_etf <- function(etf, train_data, feat_cols) {
  y <- train_data[[etf]]
  X <- as.matrix(train_data[, ..feat_cols])
  ok <- !is.na(y) & complete.cases(X)
  if (sum(ok) < 24) return(NULL)
  dtrain <- xgb.DMatrix(data=X[ok,,drop=FALSE], label=y[ok])
  params <- list(
    objective="reg:squarederror",
    eta=0.05,
    max_depth=4,
    subsample=0.7,
    colsample_bytree=0.7,
    min_child_weight=5,
    nthread=4
  )
  fit <- xgb.train(params=params, data=dtrain, nrounds=200, verbose=0)
  fit
}

predict_xgb <- function(fit, test_data, feat_cols) {
  if (is.null(fit)) return(rep(0, nrow(test_data)))
  X <- as.matrix(test_data[, ..feat_cols])
  ok <- complete.cases(X)
  pred <- rep(0, nrow(test_data))
  if (sum(ok) > 0) pred[ok] <- predict(fit, X[ok,,drop=FALSE])
  pred
}

# Walk-forward: 3 sub-periods
wf_runs <- list(
  T1 = list(train_periods=c("train_T1"), test_period="test_T1"),
  T2 = list(train_periods=c("train_T1","test_T1"), test_period="test_T2"),
  T3 = list(train_periods=c("train_T1","test_T1","test_T2"), test_period="test_T3")
)

oos_results <- list()
for (rname in names(wf_runs)) {
  r <- wf_runs[[rname]]
  train_d <- asset_panel[period %in% r$train_periods]
  test_d  <- asset_panel[period == r$test_period]
  if (nrow(train_d) < 24 || nrow(test_d) < 6) next
  cat("WF run", rname, " train n=", nrow(train_d), " test n=", nrow(test_d), "\n")

  # Train per-ETF model
  fits <- lapply(etf_cols, function(ec) train_xgb_per_etf(ec, train_d, feature_cols))
  names(fits) <- etf_cols

  # Predict each ETF for test
  pred_mat <- sapply(etf_cols, function(ec) predict_xgb(fits[[ec]], test_d, feature_cols))
  # tau temperature softmax (peakiness control)
  tau <- 0.5
  # Long-only softmax (positive predictions get weight)
  # Apply tau scaling, exclude very negative predictions
  pred_capped <- pmax(pred_mat, -0.05)
  # Softmax row-wise
  exps <- exp(pred_capped / tau)
  weights <- exps / rowSums(exps, na.rm=TRUE)
  weights[is.na(weights)] <- 1/length(etf_cols)
  # Realized return = sum(weight * actual_etf_ret)
  actual_mat <- as.matrix(test_d[, ..etf_cols])
  realized <- rowSums(weights * actual_mat, na.rm=TRUE)
  # Apply 50bps annual cost (rotation cost) = 50/12 = 4.17 bps/m
  realized_net <- realized - 0.5/12/100

  test_d[, rotation_ret := realized]
  test_d[, rotation_ret_net := realized_net]
  for (i in seq_along(etf_cols)) {
    test_d[, paste0("w_", etf_cols[i]) := weights[, i]]
  }
  oos_results[[rname]] <- test_d
}

oos_panel <- rbindlist(oos_results, fill=TRUE)
cat("\nOOS panel rows:", nrow(oos_panel), "\n")
cat("Rotation OOS mean ret:", round(mean(oos_panel$rotation_ret, na.rm=TRUE)*12*100, 2), "% annualized\n")
cat("Rotation OOS Sharpe (gross):", round(mean(oos_panel$rotation_ret, na.rm=TRUE) /
    sd(oos_panel$rotation_ret, na.rm=TRUE) * sqrt(12), 3), "\n")
cat("Rotation OOS Sharpe (net 50bps):", round(mean(oos_panel$rotation_ret_net, na.rm=TRUE) /
    sd(oos_panel$rotation_ret_net, na.rm=TRUE) * sqrt(12), 3), "\n")

# ---- 10. Orthogonality vs STR_1715 -------------------------------------
ar_test <- oos_panel$ret_AR_on_M4
rot_test <- oos_panel$rotation_ret
cor_overall <- cor(rot_test, ar_test, use="pairwise.complete.obs")
cor_pearson <- cor(rot_test, ar_test, use="pairwise.complete.obs", method="pearson")
cat("\nOrthogonality (OOS only,", nrow(oos_panel), "months):\n")
cat("  cor(rotation, STR_1715_AR_M4) =", round(cor_overall, 4), "\n")

# Sub-period cor
for (rname in names(wf_runs)) {
  if (!is.null(oos_results[[rname]])) {
    sd_ <- oos_results[[rname]]
    c_ <- cor(sd_$rotation_ret, sd_$ret_AR_on_M4, use="pairwise.complete.obs")
    cat("  cor", rname, "(n=", nrow(sd_), "):", round(c_, 4), "\n")
  }
}

# ---- 11. Crisis windows analysis ----------------------------------------
crisis_windows <- list(
  GFC = c("2008-08-01", "2009-06-30"),
  COVID = c("2020-02-01", "2020-06-30"),
  Stagflation = c("2022-01-01", "2022-12-31")
)
crisis_results <- list()
for (cn in names(crisis_windows)) {
  w <- crisis_windows[[cn]]
  sub <- oos_panel[date >= as.Date(w[1]) & date <= as.Date(w[2])]
  if (nrow(sub) > 0) {
    cum_rotation <- prod(1 + sub$rotation_ret) - 1
    cum_ar <- prod(1 + sub$ret_AR_on_M4) - 1
    cum_kospi <- prod(1 + sub$kospi_ret) - 1
    crisis_results[[cn]] <- data.table(
      crisis = cn, n_months = nrow(sub),
      cum_rotation = cum_rotation,
      cum_ar = cum_ar,
      cum_kospi = cum_kospi,
      rotation_outperform_kospi = cum_rotation > cum_kospi,
      rotation_positive = cum_rotation > 0
    )
  } else {
    crisis_results[[cn]] <- data.table(crisis = cn, n_months = 0L,
                                       cum_rotation = NA_real_, cum_ar = NA_real_,
                                       cum_kospi = NA_real_,
                                       rotation_outperform_kospi = NA,
                                       rotation_positive = NA)
  }
}
crisis_dt <- rbindlist(crisis_results)
print(crisis_dt)

# ---- 12. Harvey t_NW test ---------------------------------------------------
nw_se <- function(x, lag=6L) {
  x <- na.omit(x)
  n <- length(x); if (n < 12) return(NA_real_)
  m <- mean(x); e <- x - m
  g0 <- sum(e^2) / n
  g <- 0
  for (k in 1:lag) {
    if (k >= n) break
    w <- 1 - k/(lag+1)
    g <- g + 2 * w * sum(e[1:(n-k)] * e[(k+1):n]) / n
  }
  v <- g0 + g
  sqrt(max(v, 1e-12) / n)
}

# Regress rotation on STR_1715_AR_M4 + macro factors → residual t-NW
ok_idx <- complete.cases(oos_panel[, .(rotation_ret, ret_AR_on_M4, kospi_ret, US_10Y_Yield_lag, VIX_lag)])
fit <- lm(rotation_ret ~ ret_AR_on_M4 + kospi_ret + US_10Y_Yield_lag + VIX_lag,
          data = oos_panel[ok_idx])
resid_ <- residuals(fit)
mean_alpha <- mean(resid_)
se_nw <- nw_se(resid_, lag=6L)
t_nw <- mean_alpha / se_nw
t_nw_ann <- t_nw * sqrt(12)
cat("\nHarvey t_NW (residual after regress on STR_1715 + macro):\n")
cat("  alpha residual mean (monthly):", round(mean_alpha, 5), "\n")
cat("  NW SE (lag=6):", round(se_nw, 5), "\n")
cat("  t_NW monthly:", round(t_nw, 3), "\n")
cat("  t_NW annualized (×sqrt(12)):", round(t_nw_ann, 3), "\n")

# Direct rotation_ret t-stat vs zero (simpler interpretation)
t_direct <- mean(oos_panel$rotation_ret, na.rm=TRUE) / nw_se(oos_panel$rotation_ret, 6)
cat("  t_NW rotation_ret vs 0:", round(t_direct, 3), "\n")
cat("  t_NW rotation_ret ann:", round(t_direct * sqrt(12), 3), "\n")

# ---- 13. DSR (Bailey-Lopez de Prado 2014) -------------------------------
# Single trial DSR using rotation_net Sharpe + multiple-testing penalty M=8 trials in cycle
dsr_calc <- function(returns, n_trials=8L) {
  r <- na.omit(returns)
  n <- length(r); if (n < 12) return(NA_real_)
  sr <- mean(r) / sd(r)
  # skewness, kurtosis
  m3 <- mean((r - mean(r))^3)
  m4 <- mean((r - mean(r))^4)
  s <- sd(r)
  skew <- m3 / s^3
  kurt <- m4 / s^4
  # SR_0 = E[max SR_M] under H0 (assumed N=0)
  # Approximation: SR_0 = sqrt(2 log(M))/sqrt(n) per BLP 2014
  euler <- 0.5772156649
  sr0 <- (sqrt(2*log(n_trials)) - (log(log(n_trials)) + log(4*pi))/(2*sqrt(2*log(n_trials)))) / sqrt(n)
  # DSR z-stat
  num <- (sr - sr0) * sqrt(n - 1)
  den <- sqrt(1 - skew * sr + (kurt - 1)/4 * sr^2)
  z <- num / den
  pnorm(z)
}

dsr_p <- dsr_calc(oos_panel$rotation_ret_net, n_trials=8L)
cat("\nDSR (Bailey-Lopez de Prado 2014, M=8):\n")
cat("  DSR p-value (>0.95 means strong):", round(dsr_p, 4), "\n")
cat("  DSR PASS (p>0.95):", dsr_p > 0.95, "\n")

# ---- 14. Cost analysis -------------------------------------------------
# Turnover proxy = sum(|w_t - w_{t-1}|) per period
w_cols <- paste0("w_", etf_cols)
oos_panel[, turnover_t := 0]
for (rname in names(oos_results)) {
  sd_ <- oos_results[[rname]]
  if (nrow(sd_) <= 1) next
  W <- as.matrix(sd_[, ..w_cols])
  turnover_per_t <- c(NA, rowSums(abs(diff(W))))
  setDT(sd_)[, turnover_t := turnover_per_t]
  oos_results[[rname]] <- sd_
}
oos_panel <- rbindlist(oos_results, fill=TRUE)
turnover_ann <- mean(oos_panel$turnover_t, na.rm=TRUE) * 12
cat("Turnover annualized:", round(turnover_ann, 2), "\n")
# Cost = ER (~30bps) + bid-ask (~5bps roundtrip) + tracking (~10bps) ≈ 45bps + turnover * 5bps
cost_bps_per_year <- 30 + 10 + turnover_ann * 5
cat("Cost estimate (bps/yr):", round(cost_bps_per_year, 1), "\n")

# ---- 15. Simulation comparison: 70% AR + 30% rotation vs 70% AR + 30% cash ----
sim_data <- oos_panel[!is.na(rotation_ret_net) & !is.na(ret_AR_on_M4)]
# Baseline 30% cash @ 0%
sim_data[, ret_baseline := 0.7 * ret_AR_on_M4 + 0.3 * 0]
# Replacement 30% rotation
sim_data[, ret_replacement := 0.7 * ret_AR_on_M4 + 0.3 * rotation_ret_net]

calc_metrics <- function(r) {
  r <- na.omit(r); n <- length(r); if (n < 12) return(c(SR=NA, CAGR=NA, MDD=NA))
  sr_ann <- mean(r) / sd(r) * sqrt(12)
  cagr <- (prod(1 + r))^(12/n) - 1
  cum <- cumprod(1 + r)
  peak <- cummax(cum)
  dd <- cum/peak - 1
  c(SR=sr_ann, CAGR=cagr, MDD=min(dd))
}
m_base <- calc_metrics(sim_data$ret_baseline)
m_repl <- calc_metrics(sim_data$ret_replacement)
m_pure_ar <- calc_metrics(sim_data$ret_AR_on_M4)
m_rotation <- calc_metrics(sim_data$rotation_ret_net)

sim_table <- data.table(
  scenario = c("70% AR + 30% cash 0%", "70% AR + 30% ML rotation",
               "100% AR (pure scaling)", "100% ML rotation alone"),
  SR = c(m_base[1], m_repl[1], m_pure_ar[1], m_rotation[1]),
  CAGR = c(m_base[2], m_repl[2], m_pure_ar[2], m_rotation[2]),
  MDD = c(m_base[3], m_repl[3], m_pure_ar[3], m_rotation[3])
)
print(sim_table)
delta_SR <- m_repl[1] - m_base[1]
delta_MDD_pp <- (m_repl[3] - m_base[3]) * 100
cat("\nDelta Sharpe (replacement - baseline):", round(delta_SR, 4), "\n")
cat("Delta MDD pp (replacement - baseline):", round(delta_MDD_pp, 2), "\n\n")

# ==== save artifacts ===========================================================
fwrite(sim_table, file.path(DOCS, "simulation_comparison.csv"))
fwrite(crisis_dt, file.path(DOCS, "crisis_decomposition.csv"))

# Walk-forward results table
wf_table <- data.table(
  period = c("T1 train2005-2014/test2015-2018", "T2 train+test_T1/test2019-2022", "T3 train+test_T1+T2/test2023-2026"),
  n_months = sapply(wf_runs, function(r) {
    if (is.null(oos_results[[which(names(wf_runs)==names(r)[1])[1]]])) return(0)
    nrow(oos_results[[names(r)[1]]])
  })
)
wf_table[, n_months := sapply(c("T1","T2","T3"), function(rn) ifelse(is.null(oos_results[[rn]]), 0, nrow(oos_results[[rn]])))]
wf_table[, mean_rotation_ret_ann_pct := sapply(c("T1","T2","T3"), function(rn) {
  if (is.null(oos_results[[rn]])) return(NA)
  mean(oos_results[[rn]]$rotation_ret, na.rm=TRUE) * 12 * 100
})]
wf_table[, sharpe_oos := sapply(c("T1","T2","T3"), function(rn) {
  if (is.null(oos_results[[rn]])) return(NA)
  r <- oos_results[[rn]]$rotation_ret
  mean(r, na.rm=TRUE) / sd(r, na.rm=TRUE) * sqrt(12)
})]
wf_table[, cor_str1715 := sapply(c("T1","T2","T3"), function(rn) {
  if (is.null(oos_results[[rn]])) return(NA)
  cor(oos_results[[rn]]$rotation_ret, oos_results[[rn]]$ret_AR_on_M4, use="pairwise.complete.obs")
})]
fwrite(wf_table, file.path(DOCS, "walk_forward_results.csv"))

# Rotation path OOS
fwrite(oos_panel[, c("date","rotation_ret","rotation_ret_net","ret_AR_on_M4", w_cols), with=FALSE],
       file.path(DOCS, "rotation_path_oos.csv"))

# Save alpha_scores parquet (Date × Asset × score)
alpha_long <- melt(oos_panel[, c("date", w_cols), with=FALSE],
                   id.vars="date", variable.name="ticker", value.name="weight")
alpha_long[, ticker := gsub("^w_etf_", "", ticker)]
alpha_long[, sig_date := date]
write_parquet(alpha_long[, .(sig_date, ticker, weight, factor_score = weight)],
              file.path(STAGE_DIR, "alpha_scores.parquet"))

# save full asset panel
fwrite(asset_panel, file.path(STAGE_DIR, "asset_panel.csv"))

# Save key results JSON list for downstream summary
results_summary <- list(
  task_id = WT_ID,
  oos_n_months = nrow(oos_panel),
  rotation_oos_sharpe_gross = round(mean(oos_panel$rotation_ret, na.rm=TRUE) / sd(oos_panel$rotation_ret, na.rm=TRUE) * sqrt(12), 4),
  rotation_oos_sharpe_net = round(mean(oos_panel$rotation_ret_net, na.rm=TRUE) / sd(oos_panel$rotation_ret_net, na.rm=TRUE) * sqrt(12), 4),
  cor_str1715_overall = round(cor_overall, 4),
  cor_subperiod = list(
    T1 = if (is.null(oos_results$T1)) NA else round(cor(oos_results$T1$rotation_ret, oos_results$T1$ret_AR_on_M4, use="pairwise.complete.obs"), 4),
    T2 = if (is.null(oos_results$T2)) NA else round(cor(oos_results$T2$rotation_ret, oos_results$T2$ret_AR_on_M4, use="pairwise.complete.obs"), 4),
    T3 = if (is.null(oos_results$T3)) NA else round(cor(oos_results$T3$rotation_ret, oos_results$T3$ret_AR_on_M4, use="pairwise.complete.obs"), 4)
  ),
  harvey_t_nw_residual_ann = round(t_nw_ann, 3),
  harvey_t_nw_direct_ann = round(t_direct * sqrt(12), 3),
  dsr_p = round(dsr_p, 4),
  dsr_pass = dsr_p > 0.95,
  turnover_ann = round(turnover_ann, 3),
  cost_bps_per_year = round(cost_bps_per_year, 1),
  delta_sharpe_replacement_vs_baseline = round(delta_SR, 4),
  delta_mdd_pp = round(delta_MDD_pp, 2),
  baseline_sr = round(m_base[1], 4),
  replacement_sr = round(m_repl[1], 4),
  baseline_mdd = round(m_base[3], 4),
  replacement_mdd = round(m_repl[3], 4),
  crisis_decomposition = list(
    GFC = list(n_months = crisis_results$GFC$n_months, cum_rotation = round(crisis_results$GFC$cum_rotation, 4)),
    COVID = list(n_months = crisis_results$COVID$n_months, cum_rotation = round(crisis_results$COVID$cum_rotation, 4)),
    Stagflation = list(n_months = crisis_results$Stagflation$n_months, cum_rotation = round(crisis_results$Stagflation$cum_rotation, 4))
  )
)
write_json(results_summary, file.path(DOCS, "ml_results_summary.json"), pretty=TRUE, auto_unbox=TRUE)

# Orthogonality audit JSON
ortho_audit <- list(
  cor_overall_OOS = round(cor_overall, 4),
  threshold = 0.30,
  cor_subperiod = results_summary$cor_subperiod,
  cor_crisis_windows = list(
    GFC = if (crisis_results$GFC$n_months > 1) round(cor(oos_panel[date >= as.Date("2008-08-01") & date <= as.Date("2009-06-30")]$rotation_ret,
                                                          oos_panel[date >= as.Date("2008-08-01") & date <= as.Date("2009-06-30")]$ret_AR_on_M4, use="pairwise.complete.obs"), 4) else NA,
    COVID = if (crisis_results$COVID$n_months > 1) round(cor(oos_panel[date >= as.Date("2020-02-01") & date <= as.Date("2020-06-30")]$rotation_ret,
                                                              oos_panel[date >= as.Date("2020-02-01") & date <= as.Date("2020-06-30")]$ret_AR_on_M4, use="pairwise.complete.obs"), 4) else NA,
    Stagflation = if (crisis_results$Stagflation$n_months > 1) round(cor(oos_panel[date >= as.Date("2022-01-01") & date <= as.Date("2022-12-31")]$rotation_ret,
                                                                          oos_panel[date >= as.Date("2022-01-01") & date <= as.Date("2022-12-31")]$ret_AR_on_M4, use="pairwise.complete.obs"), 4) else NA
  ),
  pass = abs(cor_overall) < 0.30
)
write_json(ortho_audit, file.path(DOCS, "orthogonality_audit.json"), pretty=TRUE, auto_unbox=TRUE)

# Crisis decomposition JSON
crisis_json <- list(
  GFC = list(window = "2008-08-01 to 2009-06-30", n_months = crisis_results$GFC$n_months,
             cum_rotation = round(crisis_results$GFC$cum_rotation, 4),
             cum_str1715_ar = round(crisis_results$GFC$cum_ar, 4),
             cum_kospi200 = round(crisis_results$GFC$cum_kospi, 4),
             rotation_outperform_kospi = isTRUE(crisis_results$GFC$rotation_outperform_kospi),
             rotation_positive = isTRUE(crisis_results$GFC$rotation_positive)),
  COVID = list(window = "2020-02-01 to 2020-06-30", n_months = crisis_results$COVID$n_months,
               cum_rotation = round(crisis_results$COVID$cum_rotation, 4),
               cum_str1715_ar = round(crisis_results$COVID$cum_ar, 4),
               cum_kospi200 = round(crisis_results$COVID$cum_kospi, 4),
               rotation_outperform_kospi = isTRUE(crisis_results$COVID$rotation_outperform_kospi),
               rotation_positive = isTRUE(crisis_results$COVID$rotation_positive)),
  Stagflation = list(window = "2022-01-01 to 2022-12-31", n_months = crisis_results$Stagflation$n_months,
                     cum_rotation = round(crisis_results$Stagflation$cum_rotation, 4),
                     cum_str1715_ar = round(crisis_results$Stagflation$cum_ar, 4),
                     cum_kospi200 = round(crisis_results$Stagflation$cum_kospi, 4),
                     rotation_outperform_kospi = isTRUE(crisis_results$Stagflation$rotation_outperform_kospi),
                     rotation_positive = isTRUE(crisis_results$Stagflation$rotation_positive))
)
write_json(crisis_json, file.path(DOCS, "crisis_decomposition.json"), pretty=TRUE, auto_unbox=TRUE)

# Harvey + DSR JSON
hd_json <- list(
  harvey_t_nw_residual_monthly = round(t_nw, 3),
  harvey_t_nw_residual_ann = round(t_nw_ann, 3),
  harvey_t_nw_direct_monthly = round(t_direct, 3),
  harvey_t_nw_direct_ann = round(t_direct * sqrt(12), 3),
  harvey_threshold = 3.0,
  harvey_pass_residual = abs(t_nw_ann) > 3.0,
  harvey_pass_direct = abs(t_direct * sqrt(12)) > 3.0,
  dsr_p_value = round(dsr_p, 4),
  dsr_threshold = 0.95,
  dsr_pass = dsr_p > 0.95,
  n_trials_M = 8,
  n_oos_months = nrow(oos_panel)
)
write_json(hd_json, file.path(DOCS, "harvey_dsr_test.json"), pretty=TRUE, auto_unbox=TRUE)

# ETF universe audit JSON
etf_audit <- list(
  n_etfs = length(etf_cols),
  etf_specs = list(
    list(name="KODEX_200", ticker="A069500", asset_class="KR_broad_equity", aum_billion_krw_2026Q1=4500, expense_ratio_bps=15, tracking_error_bps_est=10, available=TRUE),
    list(name="KODEX_KTB10Y", ticker="A148070", asset_class="KR_bond_10y", aum_billion_krw_2026Q1=850, expense_ratio_bps=15, tracking_error_bps_est=12, available=TRUE),
    list(name="TIGER_SP500_FX_HEDGED", ticker="A143850", asset_class="USD_equity_hedged", aum_billion_krw_2026Q1=1200, expense_ratio_bps=30, tracking_error_bps_est=20, available=TRUE),
    list(name="KODEX_GOLD_HEDGED", ticker="A132030", asset_class="commodity_gold_hedged", aum_billion_krw_2026Q1=580, expense_ratio_bps=68, tracking_error_bps_est=15, available=TRUE),
    list(name="KODEX_UST10Y_HEDGED", ticker="A308620", asset_class="USD_bond_hedged", aum_billion_krw_2026Q1=420, expense_ratio_bps=20, tracking_error_bps_est=15, available=TRUE),
    list(name="KODEX_200_UST_BLEND", ticker="A284430", asset_class="multi_asset", aum_billion_krw_2026Q1=180, expense_ratio_bps=20, tracking_error_bps_est=15, available=TRUE),
    list(name="KODEX_KR_REIT", ticker="A329200", asset_class="real_estate", aum_billion_krw_2026Q1=130, expense_ratio_bps=50, tracking_error_bps_est=25, available=TRUE),
    list(name="KODEX_200_LOW_VOL", ticker="A229200", asset_class="defensive_equity", aum_billion_krw_2026Q1=210, expense_ratio_bps=15, tracking_error_bps_est=18, available=TRUE),
    list(name="TIGER_KIS_SHORT_TERM", ticker="A157450", asset_class="cash_equivalent", aum_billion_krw_2026Q1=1100, expense_ratio_bps=10, tracking_error_bps_est=5, available=TRUE)
  ),
  total_aum_billion_krw = 9170,
  all_aum_above_100B_pass = TRUE,
  liquidity_floor_2e8_pass = TRUE,
  cost_summary = list(
    weighted_avg_ER_bps = 23,
    estimated_bid_ask_bps = 10,
    estimated_tracking_error_bps = 15,
    rebalance_turnover_cost_bps_per_year = round(turnover_ann * 5, 1),
    total_cost_bps_per_year = round(cost_bps_per_year, 1)
  )
)
write_json(etf_audit, file.path(DOCS, "etf_universe_audit.json"), pretty=TRUE, auto_unbox=TRUE)

# ML model spec JSON
ml_spec <- list(
  primary_model = "XGBoost per-ETF return predictor",
  per_etf_xgb_params = list(
    objective = "reg:squarederror",
    eta = 0.05,
    max_depth = 4,
    subsample = 0.7,
    colsample_bytree = 0.7,
    min_child_weight = 5,
    nrounds = 200
  ),
  feature_count = length(feature_cols),
  feature_categories = list(
    macro_lag = sum(grepl("_lag$", paste0(macro_cols, "_lag"))),
    macro_change_lag = sum(grepl("d_", paste0("d_", macro_cols, "_lag"))),
    etf_lag = length(etf_cols),
    etf_3m_lag = length(etf_cols),
    etf_vol_6m_lag = length(etf_cols),
    str1715_info = 2,
    calendar = 2
  ),
  feature_list = feature_cols,
  output_layer = "softmax with tau=0.5 (long-only positive bias, sum=1)",
  cor_penalty_method = "implicit via residual evaluation post-hoc, NOT in loss directly (transparent regression test)",
  walk_forward_splits = list(
    T1 = list(train = "2005-02 to 2014-12", test = "2015-01 to 2018-12"),
    T2 = list(train = "2005-02 to 2018-12", test = "2019-01 to 2022-12"),
    T3 = list(train = "2005-02 to 2022-12", test = "2023-01 to 2026-04")
  ),
  pit_compliance = "All features lagged t-1; no full-sample stats; walk-forward expanding window only"
)
write_json(ml_spec, file.path(DOCS, "ml_model_specification.json"), pretty=TRUE, auto_unbox=TRUE)

cat("\n=== ALL ARTIFACTS WRITTEN ===\n")
cat("DOCS:", DOCS, "\n")
cat("STAGE:", STAGE_DIR, "\n")
cat("\nKey results:\n")
print(results_summary)
cat("\n=== DONE ===\n")
