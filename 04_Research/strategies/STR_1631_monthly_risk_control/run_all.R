cat("=== STR_1631 Monthly Risk Control: MRS-Based Monthly Cash Allocation ===\n")
## 핵심 아이디어: 데일리 overlay 없이 월간 리밸런싱 시점에만 MRS를 확인하여
## 현금 비중을 조절함으로써 MDD를 제어.
## Base: C19 Top-20 CVaR LP 비중 (STR_1631_weight_extreme 최상위)
## PIT: MRS는 regime_v7에서 이미 t-1 lag 적용, DD brake는 expanding peak
## C1(expanding only), C2(t-1 lag), C5(overlay t-1)

t0 <- Sys.time()

# ===================================================================
# 0. Environment Setup
# ===================================================================
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR  <- file.path(PROJECT_ROOT, ".cache")
CONS_DIR   <- file.path(CACHE_DIR, "consensus")
STRAT_DIR  <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR    <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales)
  library(lubridate); library(jsonlite)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

LIQ_THRESHOLD <- 2e8
N_HOLD        <- 20L
MAX21D_EXCL   <- 0.80
MAX_W         <- 0.15

cat(sprintf("[setup] PROJECT_ROOT: %s\n", PROJECT_ROOT))

# ===================================================================
# 1. Load RAWDATA + infrastructure (single bulk load, OPT-1/2)
# ===================================================================
cat("\n[Step 1] Loading RAWDATA + infrastructure...\n")
source(file.path(FUNC_PATH, "backtest_harness.R"))
source(file.path(FUNC_PATH, "portfolio/advanced_weights.R"))

res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
RAWDATA[, Date := as.Date(Date)]; BM_DT[, Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= ANALYSIS_START_DATE]; BM_DT <- BM_DT[Date >= ANALYSIS_START_DATE]
dc <- intersect(c("Open", "High", "Low", "source", "Size", "Market"), names(RAWDATA))
if (length(dc) > 0) RAWDATA[, (dc) := NULL]
if (!"Name" %in% names(RAWDATA) || !"Sector" %in% names(RAWDATA)) {
  ud <- as.data.table(arrow::read_parquet(file.path(CACHE_DIR, "universe.parquet")))
  ud[, Date := as.Date(Date)]; setorder(ud, Ticker, -Date)
  ti <- ud[, .(Name = Name[1], Sector = Sector[1]), by = Ticker]
  if (!"Name" %in% names(RAWDATA)) RAWDATA <- merge(RAWDATA, ti[, .(Ticker, Name)], by = "Ticker", all.x = TRUE)
  if (!"Sector" %in% names(RAWDATA)) RAWDATA <- merge(RAWDATA, ti[, .(Ticker, Sector)], by = "Ticker", all.x = TRUE)
  rm(ud, ti)
}
gc(verbose = FALSE)

# ===================================================================
# 1b. Bulk consensus load (all 5 files at once, OPT-1)
# ===================================================================
cat("[Step 1b] Bulk loading consensus parquets...\n")
cons_files <- c("sue.parquet", "esbr.parquet", "eps_chg_1m.parquet",
                "coverage.parquet", "target_price.parquet")
cons_list <- lapply(cons_files, function(f) {
  fp <- file.path(CONS_DIR, f)
  dt <- as.data.table(arrow::read_parquet(fp))
  dt[, Date := as.Date(Date)]; dt <- dt[Date >= ANALYSIS_START_DATE]
  setkey(dt, Ticker, Date); dt
})
names(cons_list) <- c("sue", "esbr", "eps1m", "cov", "tp")
SUE_DT <- cons_list$sue; ESBR_DT <- cons_list$esbr; EPS1M_DT <- cons_list$eps1m
COV_DT <- cons_list$cov; TP_DT <- cons_list$tp
rm(cons_list)

# Signal dates (monthly)
RAWDATA[, YM := format(Date, "%Y-%m")]
sd_dt <- RAWDATA[, .(sig_date = max(Date)), by = YM]; setorder(sd_dt, sig_date)
sd_dt <- sd_dt[sig_date >= SIGNAL_START_DATE]
SIG_DATES <- sd_dt$sig_date

# Pre-compute LIQ and MAX21d
setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradVal := Close * Vol]
RAWDATA[, LIQ_20d := frollmean(TradVal, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
RAWDATA[, TradVal := NULL]
RAWDATA[, Ret_abs := abs(Ret)]
RAWDATA[, MAX21d_raw := {
  ra <- Ret_abs; n <- length(ra)
  if (n < 21L) cummax(fifelse(is.na(ra), -Inf, ra))
  else frollapply(ra, n = 21L, FUN = max, fill = NA, align = "right")
}, by = Ticker]
RAWDATA[, MAX21d := shift(MAX21d_raw, n = 1L, type = "lag"), by = Ticker]
RAWDATA[, c("Ret_abs", "MAX21d_raw") := NULL]

SIG_SNAP <- RAWDATA[Date %in% SIG_DATES & !is.na(Close),
                     .(Date, Ticker, Close, LIQ_20d, MAX21d)]
setkey(SIG_SNAP, Date, Ticker)
RAWDATA[, c("LIQ_20d", "MAX21d", "YM") := NULL]
setkey(RAWDATA, Date, Ticker)
gc(verbose = FALSE)

cat(sprintf("[Step 1] %d signal dates (%s ~ %s)\n",
            length(SIG_DATES), min(SIG_DATES), max(SIG_DATES)))

# ===================================================================
# 2. Build C19 FACTORS (vectorized lapply)
# ===================================================================
cat("\n[Step 2] Building C19 top-20...\n")
z_safe <- function(x) {
  nv <- sum(!is.na(x)); if (nv < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x))); (x - mu) / s
}

FACTORS <- rbindlist(lapply(seq_along(SIG_DATES), function(i) {
  sd <- SIG_DATES[i]
  univ <- SIG_SNAP[Date == sd & !is.na(LIQ_20d)][LIQ_20d >= LIQ_THRESHOLD]
  if (nrow(univ) < 30L) return(NULL)
  mq <- quantile(univ$MAX21d, MAX21D_EXCL, na.rm = TRUE)
  univ <- univ[is.na(MAX21d) | MAX21d <= mq]; if (nrow(univ) < 30L) return(NULL)
  probe <- data.table(Ticker = univ$Ticker, Date = sd); setkey(probe, Ticker, Date)
  sue_j   <- SUE_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, sue)]
  esbr_j  <- ESBR_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, esbr)]
  eps1m_j <- EPS1M_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, eps_chg_1m)]
  cov_j   <- COV_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, coverage)]
  tp_j    <- TP_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, target_price)]
  sig <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = FALSE),
                list(univ[, .(Ticker, Close)], sue_j, esbr_j, eps1m_j, cov_j, tp_j))
  sig <- sig[!is.na(coverage) & coverage >= 3L]; if (nrow(sig) < 20L) return(NULL)
  sig[, TP_Gap := (target_price - Close) / Close]
  sig[, z_sue := z_safe(sue)]; sig[, z_esbr := z_safe(esbr)]
  sig[, z_eps1m := z_safe(eps_chg_1m)]; sig[, z_tpgap := z_safe(TP_Gap)]
  sig <- sig[!is.na(z_sue) & !is.na(z_esbr) & !is.na(z_eps1m) & !is.na(z_tpgap)]
  if (nrow(sig) < 20L) return(NULL)
  sig[, C19 := (z_sue + z_esbr + z_eps1m + z_tpgap) / 4]
  setorder(sig, -C19); top <- head(sig, N_HOLD)
  data.table(Date = sd, Ticker = top$Ticker, Score = top$C19)
}))
cat(sprintf("[Step 2] FACTORS: %d rows | %d months\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
rm(SUE_DT, ESBR_DT, EPS1M_DT, COV_DT, TP_DT, SIG_SNAP); gc(verbose = FALSE)

# ===================================================================
# 3. Load Regime v7 (single read, no loop)
# ===================================================================
cat("\n[Step 3] Loading Regime v7...\n")
REGIME <- as.data.table(arrow::read_parquet(file.path(CACHE_DIR, "regime_v7.parquet")))
if ("month_end" %in% names(REGIME)) {
  REGIME[, Date := tryCatch(as.Date(month_end), error = function(e) as.Date(as.numeric(month_end), origin="1970-01-01"))]
} else {
  REGIME[, Date := as.Date(paste0(apply_month, "-01")) + 30L]
}
REGIME <- REGIME[!is.na(Date)]; setkey(REGIME, Date)
cat(sprintf("[Step 3] Regime: %d rows | MRS range: %.1f ~ %.1f\n",
            nrow(REGIME), min(REGIME$MRS), max(REGIME$MRS)))

# ===================================================================
# 4. Run CVaR LP base backtest via run_monthly_simulation() (OPT-3)
# ===================================================================
cat("\n[Step 4] Running CVaR LP base backtest...\n")

all_trade_dates <- sort(unique(RAWDATA$Date))
sig_date_list <- sort(unique(FACTORS$Date))

get_ret_sub <- function(sd, lookback = 120L) {
  idx <- which(all_trade_dates < sd)
  if (length(idx) < lookback) lb_dates <- all_trade_dates[idx]
  else lb_dates <- all_trade_dates[tail(idx, lookback)]
  RAWDATA[Date %in% lb_dates, .(Date, Ticker, Ret)]
}

# Pre-compute CVaR LP weights (lapply, OPT-1 compliant)
cvar_lp_weights <- setNames(lapply(sig_date_list, function(sd) {
  tickers <- FACTORS[Date == sd, Ticker]
  ret_sub <- get_ret_sub(sd, 120L)
  w <- tryCatch(
    calc_cvar_lp_weights(tickers, ret_sub, alpha = 0.95, n_days = 120, max_w = MAX_W),
    error = function(e) rep(1/length(tickers), length(tickers))
  )
  setNames(w, tickers)
}), as.character(sig_date_list))

# Override calc_ivol_weights to inject CVaR LP weights into run_monthly_simulation
orig_fn <- calc_ivol_weights
calc_ivol_weights <- function(tickers, ret_dt, n_days = 60, max_w = 0.15) {
  wl <- cvar_lp_weights
  lapply(names(wl), function(d) {
    hw <- wl[[d]]
    if (all(tickers %in% names(hw))) return(as.numeric(hw[tickers] / sum(hw[tickers])))
    NULL
  }) -> matches
  matches <- matches[!sapply(matches, is.null)]
  if (length(matches) > 0) return(matches[[1]])
  rep(1 / length(tickers), length(tickers))
}

sim <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS,
                               n_holdings = N_HOLD,
                               weight_method = "ivol",
                               commission = 0.0015,
                               buffer_zone = list(keep_n = N_HOLD + 15L, entry_n = N_HOLD))
calc_ivol_weights <- orig_fn

# Extract monthly returns from simulation NAV (OPT-3 compliant: no inline NAV loop)
nav_dt <- sim$DAILY_NAV_DT
nav_dt[, Date := as.Date(Date)]
setorder(nav_dt, Date)
nav_dt[, YM := format(Date, "%Y-%m")]

monthly_ret <- nav_dt[, .(
  month_end = max(Date),
  NAV_start = NAV[1],
  NAV_end = tail(NAV, 1),
  month_ret = tail(NAV, 1) / NAV[1] - 1
), by = YM]
setorder(monthly_ret, month_end)

base_perf <- summarise_perf(sim$strategy_xts, "CVaR_LP_Base")
cat(sprintf("[Step 4] Base CVaR LP: %d months | SR: %.3f | CAGR: %.2f%% | MDD: %.2f%%\n",
            nrow(monthly_ret), base_perf$Sharpe, base_perf$CAGR, base_perf$MDD))

# ===================================================================
# 5. Build MRS lookup (vectorized rolling join, no loops)
# ===================================================================
cat("\n[Step 5] Building MRS monthly lookup...\n")

mrs_probe <- data.table(Date = monthly_ret$month_end); setkey(mrs_probe, Date)
mrs_joined <- REGIME[mrs_probe, .(Date = i.Date, MRS = x.MRS), roll = TRUE]
monthly_ret[, MRS := mrs_joined$MRS]

# MRS lags via shift (vectorized)
monthly_ret[, MRS_lag2 := shift(MRS, n = 1L, type = "lag")]
monthly_ret[, MRS_lag3 := shift(MRS, n = 2L, type = "lag")]
monthly_ret[is.na(MRS_lag2), MRS_lag2 := MRS]
monthly_ret[is.na(MRS_lag3), MRS_lag3 := MRS]

# Expanding median of MRS (PIT safe, C1: expanding only)
monthly_ret[, MRS_exp_median := frollapply(MRS, n = seq_len(.N), FUN = median, adaptive = TRUE)]

cat(sprintf("[Step 5] MRS attached | mean: %.1f | median: %.1f\n",
            mean(monthly_ret$MRS, na.rm = TRUE), median(monthly_ret$MRS, na.rm = TRUE)))

# ===================================================================
# 6. Apply risk control methods (vectorized + Reduce)
# ===================================================================
cat("\n[Step 6] Applying risk control methods...\n")

# --- R1: MRS Level-Based Cash (fully vectorized) ---
monthly_ret[, R1_cash := fifelse(MRS >= 60, 0.50,
                         fifelse(MRS >= 40, 0.30,
                         fifelse(MRS >= 20, 0.10, 0.00)))]
monthly_ret[, R1_ret := month_ret * (1 - R1_cash)]

# --- R2: Monthly Drawdown Check (Reduce accumulator — sequential by nature) ---
# Checks portfolio drawdown at each monthly rebalance, raises cash when in drawdown
r2_state <- Reduce(function(acc, i) {
  nav_prev <- acc$nav
  peak <- max(acc$peak, nav_prev)
  dd_pct <- (nav_prev - peak) / peak
  cash <- fifelse(dd_pct < -0.20, 0.50, fifelse(dd_pct < -0.10, 0.25, 0.00))
  nav_new <- nav_prev * (1 + monthly_ret$month_ret[i] * (1 - cash))
  list(nav = nav_new, peak = peak, cash_vec = c(acc$cash_vec, cash))
}, x = 2:nrow(monthly_ret),
  init = list(nav = 100 * (1 + monthly_ret$month_ret[1]), peak = 100, cash_vec = 0),
  accumulate = FALSE)
monthly_ret[, R2_cash := r2_state$cash_vec]
monthly_ret[, R2_ret := month_ret * (1 - R2_cash)]

# --- R3: MRS Momentum Cash (vectorized) ---
mrs_mom_vec <- monthly_ret$MRS - monthly_ret$MRS_lag2
monthly_ret[, R3_cash := pmax(0, pmin(0.5, mrs_mom_vec / 40))]
monthly_ret[, R3_ret := month_ret * (1 - R3_cash)]

# --- R4: MRS Dual Momentum (vectorized) ---
mrs_abs_v <- monthly_ret$MRS > monthly_ret$MRS_lag3
mrs_rel_v <- monthly_ret$MRS > monthly_ret$MRS_exp_median
monthly_ret[, R4_cash := fifelse(mrs_abs_v & mrs_rel_v, 0.40,
                         fifelse(mrs_abs_v & !mrs_rel_v, 0.15,
                         fifelse(!mrs_abs_v & mrs_rel_v, 0.10, 0.00)))]
monthly_ret[, R4_ret := month_ret * (1 - R4_cash)]

# --- R5: Hybrid MRS Level + Drawdown Check (Reduce accumulator) ---
r5_init_mrs <- monthly_ret$MRS[1]
r5_init_cash <- fifelse(r5_init_mrs >= 60, 0.40, fifelse(r5_init_mrs >= 40, 0.20,
                fifelse(r5_init_mrs >= 20, 0.05, 0.00)))
r5_state <- Reduce(function(acc, i) {
  nav_prev <- acc$nav
  peak <- max(acc$peak, nav_prev)
  dd_pct <- (nav_prev - peak) / peak
  dd_cash_val <- fifelse(dd_pct < -0.15, 0.30, fifelse(dd_pct < -0.08, 0.15, 0.00))
  mrs_cash_val <- fifelse(monthly_ret$MRS[i] >= 60, 0.40,
                  fifelse(monthly_ret$MRS[i] >= 40, 0.20,
                  fifelse(monthly_ret$MRS[i] >= 20, 0.05, 0.00)))
  cash <- min(0.60, max(dd_cash_val, mrs_cash_val))
  nav_new <- nav_prev * (1 + monthly_ret$month_ret[i] * (1 - cash))
  list(nav = nav_new, peak = peak, cash_vec = c(acc$cash_vec, cash))
}, x = 2:nrow(monthly_ret),
  init = list(nav = 100 * (1 + monthly_ret$month_ret[1] * (1 - r5_init_cash)),
              peak = 100, cash_vec = r5_init_cash),
  accumulate = FALSE)
monthly_ret[, R5_cash := r5_state$cash_vec]
monthly_ret[, R5_ret := month_ret * (1 - R5_cash)]

cat("[Step 6] All 5 risk control applied (vectorized + Reduce).\n")

# ===================================================================
# 7. Compute performance metrics (lapply, no loops)
# ===================================================================
cat("\n[Step 7] Computing performance metrics...\n")

compute_monthly_perf <- function(monthly_returns, label) {
  r <- monthly_returns[!is.na(monthly_returns)]
  n_months <- length(r); n_years <- n_months / 12
  nav <- cumprod(1 + r)
  cagr <- (tail(nav, 1)) ^ (1 / n_years) - 1
  ann_vol <- sd(r) * sqrt(12)
  sr <- (mean(r) * 12) / ann_vol
  downside <- r[r < 0]
  down_vol <- sqrt(mean(downside^2)) * sqrt(12)
  sortino <- (mean(r) * 12) / down_vol
  peak <- cummax(nav); dd <- (nav - peak) / peak; mdd <- min(dd) * 100
  calmar <- cagr / abs(mdd / 100)
  win_rate <- sum(r > 0) / length(r) * 100
  worst_month <- min(r) * 100
  roll3 <- if (length(r) >= 3) zoo::rollapply(1 + r, width = 3, FUN = prod, align = "right") - 1 else r
  worst_3m <- min(roll3) * 100
  sorted_r <- sort(r)
  cutoff95 <- max(1L, ceiling(length(sorted_r) * 0.05))
  cvar_95 <- mean(sorted_r[1:cutoff95]) * 100
  cutoff99 <- max(1L, ceiling(length(sorted_r) * 0.01))
  es_99 <- mean(sorted_r[1:cutoff99]) * 100
  n <- length(r); mu <- mean(r); s <- sd(r)
  sk <- (n / ((n-1)*(n-2))) * sum(((r - mu)/s)^3)
  ku <- (n*(n+1)) / ((n-1)*(n-2)*(n-3)) * sum(((r - mu)/s)^4) - 3*(n-1)^2/((n-2)*(n-3))
  dd_sq <- ((nav - peak) / peak)^2; ulcer <- sqrt(mean(dd_sq)) * 100
  data.table(
    Label = label, CAGR = round(cagr * 100, 2), AnnVol = round(ann_vol * 100, 2),
    Sharpe = round(sr, 3), Sortino = round(sortino, 3), MDD = round(mdd, 2),
    Calmar = round(calmar, 3), WinRate = round(win_rate, 1),
    WorstMonth = round(worst_month, 2), Worst3M = round(worst_3m, 2),
    CVaR95_m = round(cvar_95, 2), ES99_m = round(es_99, 2),
    Skewness = round(sk, 3), ExKurtosis = round(ku, 3), Ulcer = round(ulcer, 2)
  )
}

method_specs <- list(
  list(ret_col = "month_ret",  cash_col = NA,        label = "Base_CVaR_LP"),
  list(ret_col = "R1_ret",     cash_col = "R1_cash", label = "R1_MRS_Level"),
  list(ret_col = "R2_ret",     cash_col = "R2_cash", label = "R2_Drawdown_Check"),
  list(ret_col = "R3_ret",     cash_col = "R3_cash", label = "R3_MRS_Momentum"),
  list(ret_col = "R4_ret",     cash_col = "R4_cash", label = "R4_Dual_Momentum"),
  list(ret_col = "R5_ret",     cash_col = "R5_cash", label = "R5_Hybrid_MRS_DD")
)

perf_all <- rbindlist(lapply(method_specs, function(spec) {
  p <- compute_monthly_perf(monthly_ret[[spec$ret_col]], spec$label)
  if (!is.na(spec$cash_col)) {
    p[, Avg_Cash_Pct := round(mean(monthly_ret[[spec$cash_col]]) * 100, 1)]
    p[, Cash_Normal := round(mean(monthly_ret[MRS < 20][[spec$cash_col]]) * 100, 1)]
    p[, Cash_Crisis := round(mean(monthly_ret[MRS >= 60][[spec$cash_col]]) * 100, 1)]
  } else {
    p[, Avg_Cash_Pct := 0]; p[, Cash_Normal := 0]; p[, Cash_Crisis := 0]
  }
  p
}))

cat("\n================================================================\n")
cat("   STR_1631 Monthly Risk Control: MRS-Based Cash Allocation\n")
cat(sprintf("   %d months | %s ~ %s\n", nrow(monthly_ret),
            min(monthly_ret$month_end), max(monthly_ret$month_end)))
cat("================================================================\n\n")

cat("=== FULL COMPARISON ===\n")
print(perf_all[, .(Label, CAGR, AnnVol, Sharpe, Sortino, MDD, Calmar,
                    WinRate, WorstMonth, Worst3M, CVaR95_m, Avg_Cash_Pct)])

cat("\n=== TAIL RISK DETAIL ===\n")
print(perf_all[, .(Label, ES99_m, CVaR95_m, Worst3M, Skewness, ExKurtosis, Ulcer)])

# ===================================================================
# 8. Stress Period Analysis (8 canonical, reference_stress_periods.md)
# ===================================================================
cat("\n\n=== STRESS PERIOD ANALYSIS (8 Canonical Periods) ===\n")

stress_periods <- list(
  list(label = "9/11_Terror",      start = "2001-09", end = "2001-12"),
  list(label = "GFC_2008",         start = "2007-10", end = "2009-03"),
  list(label = "EU_Debt_2011",     start = "2011-07", end = "2011-12"),
  list(label = "China_Shock_2015", start = "2015-06", end = "2016-02"),
  list(label = "Trade_War_2018",   start = "2018-03", end = "2018-12"),
  list(label = "COVID_2020",       start = "2020-01", end = "2020-06"),
  list(label = "Rate_Hike_2022",   start = "2022-01", end = "2022-12"),
  list(label = "Iran_War_2026",    start = "2026-02", end = "2026-04")
)

stress_results <- rbindlist(lapply(stress_periods, function(sp) {
  sub <- monthly_ret[YM >= sp$start & YM <= sp$end]
  if (nrow(sub) == 0) return(NULL)
  rbindlist(lapply(method_specs, function(spec) {
    r <- sub[[spec$ret_col]]
    cum_ret <- prod(1 + r) - 1
    avg_cash <- if (!is.na(spec$cash_col)) mean(sub[[spec$cash_col]]) else 0
    data.table(Period = sp$label, Method = spec$label,
               Cum_Ret = round(cum_ret * 100, 2),
               Avg_Cash = round(avg_cash * 100, 1), N_Months = length(r))
  }))
}))

invisible(lapply(unique(stress_results$Period), function(sp_name) {
  cat(sprintf("\n--- %s ---\n", sp_name))
  print(stress_results[Period == sp_name, .(Method, Cum_Ret, Avg_Cash, N_Months)])
}))

# ===================================================================
# 9. Regime-Conditional Cash Distribution
# ===================================================================
cat("\n\n=== REGIME-CONDITIONAL CASH DISTRIBUTION ===\n")

regime_bins <- c("Normal (MRS<20)", "Caution (20-40)", "Elevated (40-60)", "Crisis (60+)")
monthly_ret[, Regime_Bin := factor(
  fifelse(MRS < 20, "Normal (MRS<20)",
  fifelse(MRS < 40, "Caution (20-40)",
  fifelse(MRS < 60, "Elevated (40-60)", "Crisis (60+)"))),
  levels = regime_bins)]

invisible(lapply(method_specs[-1], function(spec) {
  cat(sprintf("\n%s:\n", spec$label))
  cash_by_regime <- monthly_ret[, .(
    N = .N,
    Avg_Cash = round(mean(get(spec$cash_col)) * 100, 1),
    Base_Ret = round(mean(month_ret) * 100, 2),
    Ctrl_Ret = round(mean(get(spec$ret_col)) * 100, 2)
  ), by = Regime_Bin]
  setorder(cash_by_regime, Regime_Bin)
  print(cash_by_regime)
}))

# ===================================================================
# 10. Alpha Drag Analysis
# ===================================================================
cat("\n\n=== ALPHA DRAG ANALYSIS ===\n")
cat("Efficiency = MDD improvement / CAGR sacrifice\n\n")

base_cagr <- perf_all[Label == "Base_CVaR_LP", CAGR]
base_mdd  <- perf_all[Label == "Base_CVaR_LP", MDD]
base_sr   <- perf_all[Label == "Base_CVaR_LP", Sharpe]

drag_dt <- perf_all[Label != "Base_CVaR_LP", .(
  Method = Label,
  CAGR_Loss = round(base_cagr - CAGR, 2),
  MDD_Improve = round(abs(base_mdd) - abs(MDD), 2),
  SR_Delta = round(Sharpe - base_sr, 3),
  Efficiency = round((abs(base_mdd) - abs(MDD)) / pmax(base_cagr - CAGR, 0.01), 2),
  Avg_Cash_Pct
)]
print(drag_dt)

# ===================================================================
# 11. Charts (all via ggplot, no loops)
# ===================================================================
cat("\n[Step 11] Generating charts...\n")

method_colors <- c(
  "Base_CVaR_LP" = "grey40", "R1_MRS_Level" = "#E41A1C",
  "R2_Drawdown_Check" = "#377EB8", "R3_MRS_Momentum" = "#4DAF4A",
  "R4_Dual_Momentum" = "#984EA3", "R5_Hybrid_MRS_DD" = "#FF7F00")

# 11a. Equity curves
nav_series <- rbindlist(lapply(method_specs, function(spec) {
  nav <- cumprod(1 + monthly_ret[[spec$ret_col]])
  data.table(Date = monthly_ret$month_end, NAV = nav, Method = spec$label)
}))

p1 <- ggplot(nav_series, aes(x = Date, y = NAV, color = Method)) +
  geom_line(linewidth = 0.7) +
  scale_y_log10(labels = scales::comma) +
  scale_color_manual(values = method_colors) +
  labs(title = "Monthly Risk Control: Equity Curves (log)",
       subtitle = "C19 Top-20 CVaR LP Base + 5 Risk Control Methods",
       x = NULL, y = "NAV (log scale)") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom", legend.title = element_blank())
ggsave(file.path(OUT_DIR, "equity_curves_risk_control.png"), p1, width = 14, height = 8, dpi = 150)

# 11b. Drawdown comparison
dd_series <- rbindlist(lapply(method_specs, function(spec) {
  nav <- cumprod(1 + monthly_ret[[spec$ret_col]])
  peak <- cummax(nav); dd <- (nav - peak) / peak * 100
  data.table(Date = monthly_ret$month_end, DD = dd, Method = spec$label)
}))

p2 <- ggplot(dd_series, aes(x = Date, y = DD, color = Method)) +
  geom_line(linewidth = 0.5) +
  geom_hline(yintercept = -25, linetype = "dashed", color = "red", linewidth = 0.3) +
  geom_hline(yintercept = -45, linetype = "dashed", color = "darkred", linewidth = 0.3) +
  scale_color_manual(values = method_colors) +
  labs(title = "Monthly Risk Control: Drawdown Comparison",
       subtitle = "Dashed lines at -25% (target) and -45%",
       x = NULL, y = "Drawdown (%)") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom", legend.title = element_blank())
ggsave(file.path(OUT_DIR, "drawdown_comparison.png"), p2, width = 14, height = 8, dpi = 150)

# 11c. Cash allocation timeline
cash_series <- rbindlist(lapply(method_specs[-1], function(spec) {
  data.table(Date = monthly_ret$month_end,
             Cash = monthly_ret[[spec$cash_col]] * 100, Method = spec$label)
}))

p3 <- ggplot(cash_series, aes(x = Date, y = Cash, color = Method)) +
  geom_line(linewidth = 0.5) +
  scale_color_manual(values = method_colors[-1]) +
  labs(title = "Cash Allocation Over Time by Method",
       x = NULL, y = "Cash (%)") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom", legend.title = element_blank())
ggsave(file.path(OUT_DIR, "cash_allocation_timeline.png"), p3, width = 14, height = 6, dpi = 150)

# 11d. SR vs MDD tradeoff scatter
p4 <- ggplot(perf_all, aes(x = abs(MDD), y = Sharpe, label = Label)) +
  geom_point(size = 3, color = "steelblue") +
  geom_text(hjust = -0.1, vjust = 0.5, size = 3, show.legend = FALSE) +
  geom_hline(yintercept = base_sr, linetype = "dashed", color = "grey50") +
  geom_vline(xintercept = 25, linetype = "dashed", color = "red") +
  labs(title = "Risk-Return Tradeoff: SR vs MDD",
       subtitle = "Horizontal = Base SR | Vertical = 25% MDD target",
       x = "MDD (%)", y = "Sharpe Ratio") +
  theme_minimal(base_size = 12)
ggsave(file.path(OUT_DIR, "sr_vs_mdd_tradeoff.png"), p4, width = 10, height = 7, dpi = 150)

# ===================================================================
# 12. Save all outputs
# ===================================================================
cat("\n[Step 12] Saving results...\n")

fwrite(perf_all, file.path(OUT_DIR, "risk_control_comparison.csv"))
fwrite(monthly_ret, file.path(OUT_DIR, "monthly_returns_with_controls.csv"))
fwrite(stress_results, file.path(OUT_DIR, "stress_period_analysis.csv"))
fwrite(drag_dt, file.path(OUT_DIR, "alpha_drag_analysis.csv"))

write_json(list(
  strategy = "STR_1631_monthly_risk_control",
  description = "Monthly MRS-based cash allocation risk control on CVaR LP base",
  base = list(method = "C19 Top-20 CVaR LP", source = "STR_1631_weight_extreme"),
  n_methods = 6,
  results = lapply(seq_len(nrow(perf_all)), function(i) as.list(perf_all[i])),
  alpha_drag = lapply(seq_len(nrow(drag_dt)), function(i) as.list(drag_dt[i])),
  stress_analysis = stress_results,
  pit_compliance = list(
    MRS_lag = "t-1 (regime_v7 pre-lagged)",
    drawdown_check = "expanding peak (past NAV only)",
    MRS_momentum = "shift(MRS, 1) - shift(MRS, 2), both past",
    expanding_median = "cumulative median, PIT safe (C1)",
    cash_return = "0% conservative assumption"
  ),
  run_time_sec = as.numeric(difftime(Sys.time(), t0, units = "secs"))
), file.path(OUT_DIR, "performance.json"), pretty = TRUE, auto_unbox = TRUE)

elapsed <- difftime(Sys.time(), t0, units = "secs")
cat(sprintf("\n[DONE] Monthly Risk Control complete in %.1f seconds.\n", elapsed))
cat("=== END ===\n")
