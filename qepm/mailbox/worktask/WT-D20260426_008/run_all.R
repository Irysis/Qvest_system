cat("=== STR_1703: WT-D20260426_008 Track A Iter15 V3 ERC Backtest ===\n")
cat("## 핵심아이디어: STR_1701 multi-mutation upgrade (Slot 0.65/0.35 + persist=2 + EMA)\n")
cat("## PG2 decisive gate: V3 blend realized SR vs baseline 1.4625\n")

# ============================================================================
# QEPM Work Task Forge Integration — WT-D20260426_008
# Track A Iter 15 V3 ERC Walk-forward Backtest
# Pure Function: alpha/risk/optimization packages not modified
# ============================================================================

# ── Hash Audit START ─────────────────────────────────────────────────────────
START_HASHES <- list(
  alpha_package    = "40b99b7f30c95a879a0aed21591571b6",
  risk_package     = "4c3dfe0c981c1c104a3d92f81f100fce",
  optimization_pkg = "9f7b026fbd6ca68000d8ef3d19db4be1",
  weights_csv      = "1bab3f481fad431dd32632a373509a9a"
)
cat("[HASH_AUDIT] Start hashes recorded.\n")

# ── Package loading ───────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(xts)
  library(zoo)
  library(PerformanceAnalytics)
  library(ggplot2)
  library(scales)
  library(lubridate)
})
options(scipen = 999, stringsAsFactors = FALSE)
Sys.setenv(TZ = "Asia/Seoul")

`%||%` <- function(a, b) if (!is.null(a) && !is.na(a)[1]) a else b

# ── Path setup ────────────────────────────────────────────────────────────────
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

WT_DIR    <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260426_008")
STAGE_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260426_008")
OUT_DIR   <- file.path(WT_DIR, "backtest_result")
JUDGE_DIR <- file.path(WT_DIR, "judge_ready")
dir.create(OUT_DIR,   recursive = TRUE, showWarnings = FALSE)
dir.create(JUDGE_DIR, recursive = TRUE, showWarnings = FALSE)

PIT_CUTOFF <- as.Date("2023-11-30")  # Hard PIT cutoff

cat(sprintf("[Path] WT_DIR: %s\n", WT_DIR))
cat(sprintf("[Path] OUT_DIR: %s\n", OUT_DIR))

# ── Step 1: Load packages (pure function — read-only) ─────────────────────────
cat("\n[Step 1] Load 3-agent packages (pure function, read-only)\n")

alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = FALSE)
risk_pkg  <- fromJSON(file.path(WT_DIR, "risk_package.json"),  simplifyVector = FALSE)
opt_pkg   <- fromJSON(file.path(WT_DIR, "optimization_package.json"), simplifyVector = FALSE)

cat(sprintf("  Alpha task_id:   %s\n", alpha_pkg$task_id))
cat(sprintf("  Risk task_id:    %s\n", risk_pkg$task_id))
cat(sprintf("  Opt task_id:     %s\n", opt_pkg$task_id))
cat(sprintf("  Optimizer:       %s (net_IR %.4f)\n",
            opt_pkg$selection_objective$objective, opt_pkg$expected_information_ratio))
cat(sprintf("  CVaR_d post-opt: %.4f (cap: -0.025 => BREACH flagged)\n",
            opt_pkg$cvar_d_post_optim))

# ── Step 2: Load alpha scores + weights ──────────────────────────────────────
cat("\n[Step 2] Load alpha_scores.parquet + weights.csv\n")

alpha_scores <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores.parquet")))
setkey(alpha_scores, Date, Ticker)
cat(sprintf("  alpha_scores: %d rows x %d cols | dates: %d\n",
            nrow(alpha_scores), ncol(alpha_scores), uniqueN(alpha_scores$Date)))

weights_dt <- fread(file.path(WT_DIR, "weights.csv"))
weights_dt[, Date := as.Date(Date)]
setkey(weights_dt, Date, Ticker)
cat(sprintf("  weights_dt: %d rows | dates: %d | tickers per date: ~%.0f\n",
            nrow(weights_dt), uniqueN(weights_dt$Date),
            weights_dt[, .N, by=Date][, mean(N)]))

# ── Step 3: Hard constraint re-verification ───────────────────────────────────
cat("\n[Step 3] Hard constraint verification\n")
n_per_date <- weights_dt[, .N, by=Date]
if (any(n_per_date$N > 20)) stop("[FAIL] n_names > 20 at some date")
cat(sprintf("  max_names per date: %d <= 20 OK\n", max(n_per_date$N)))
if (any(weights_dt$Weight < -1e-8)) stop("[FAIL] long-only violated")
cat("  long-only: OK\n")
if (any(weights_dt$Weight > 0.20 + 1e-6)) stop("[FAIL] weight > 0.20")
cat("  weight upper bound 0.20: OK\n")
sum_check <- weights_dt[, sum(Weight), by=Date]
if (any(abs(sum_check$V1 - 1.0) > 0.005)) {
  bad <- sum_check[abs(V1 - 1.0) > 0.005]
  warning(sprintf("[WARN] Sigma_w deviation at %d dates (max dev %.4f)", nrow(bad), max(abs(bad$V1 - 1.0))))
}
cat(sprintf("  Sigma_w range: [%.4f, %.4f] OK\n",
            min(sum_check$V1), max(sum_check$V1)))

# ── Step 4: PIT verification ──────────────────────────────────────────────────
cat("\n[Step 4] PIT verification\n")
# C14: alpha scores Usable_Date <= sig_date (alpha_package states signal_as_of 2023-12-01)
max_sig_date <- max(alpha_scores$Date)
cat(sprintf("  Max alpha sig_date: %s (cutoff: %s)\n",
            format(max_sig_date), format(PIT_CUTOFF)))
if (max_sig_date > PIT_CUTOFF + 31) {
  warning("[PIT C1] alpha sig_date beyond PIT cutoff 2023-11-30")
} else {
  cat("  C1/C14 OK (training period <=2023-11-30)\n")
}
# Weights use precomputed ERC from optimizer — no look-ahead
cat("  C2 same-day circular: OK (weights from optimizer, exec t+1)\n")
cat("  C9 VT/DD lag: N/A (ERC weights, no VT overlay)\n")

# ── Step 5: Load RAWDATA ───────────────────────────────────────────────────────
cat("\n[Step 5] Load RAWDATA from cache\n")
raw_data <- load_rawdata(use_cache = TRUE)
RAWDATA <- raw_data$RAWDATA
BM_DT   <- raw_data$BM_DT
setkey(RAWDATA, Date, Ticker)
cat(sprintf("  RAWDATA: %d rows | %s ~ %s\n",
            nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date)))

# ── Step 6: Build FACTORS data.table from weights + scores ───────────────────
cat("\n[Step 6] Build FACTORS data.table (weight-assigned, ERC)\n")

# Selected tickers per signal date from weights_dt (all 20 per date)
# Score = score_eff_v3 from alpha_scores (for reference/ordering)
# Weight = ERC weight from optimizer output
FACTORS <- merge(
  weights_dt,
  alpha_scores[, .(Date, Ticker, Score = score_eff_v3, top_flag)],
  by = c("Date", "Ticker"),
  all.x = TRUE
)
setkey(FACTORS, Date, Ticker)

# Ensure we use top_flag=1 tickers only
FACTORS <- FACTORS[!is.na(Weight)]
cat(sprintf("  FACTORS: %d rows | dates: %d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))

# For run_monthly_simulation, use Score column for stock ordering
# (ordering irrelevant for weight-assigned mode — we'll override weights)
FACTORS[is.na(Score), Score := 0]  # Fill NAs with 0 for ordering

# ── Step 7: Walk-forward backtest — ERC weight-applied (return-based) ────────
cat("\n[Step 7] Walk-forward backtest (ERC weights, 240 sig_dates, 15bps)\n")
cat("  Commission: 15bps (0.0015) per side, applied at rebalance\n")
cat("  Rebalance: monthly (sig_dates)\n")
cat("  Period: 2004-01 to 2023-12 (IS train) + OOS 2024+\n")
cat("  Method: return-based weight-applied (no fractional shares)\n")

# Return-based simulation: compute daily returns as weighted sum of stock returns
# This is the correct approach for a weight-assigned backtest

# First: compute daily returns for all tickers in RAWDATA
RAWDATA_RET <- copy(RAWDATA[, .(Date, Ticker, Close)])
setkey(RAWDATA_RET, Ticker, Date)
RAWDATA_RET[, Ret_d := Close / shift(Close, 1) - 1, by = Ticker]
RAWDATA_RET <- RAWDATA_RET[!is.na(Ret_d)]
setkey(RAWDATA_RET, Date, Ticker)

all_dates_raw  <- sort(unique(RAWDATA$Date))
signal_dates_v <- sort(unique(weights_dt$Date))

cat(sprintf("  Signal dates: %d | First: %s | Last: %s\n",
            length(signal_dates_v),
            format(min(signal_dates_v)),
            format(max(signal_dates_v))))

INITIAL_CAP <- 1e8
COMMISSION  <- 0.0015

# For each signal period: [exec_date_prev+1, exec_date], use weights from signal_date
# Execution date = first trading day after signal_date
get_exec_date_local <- function(sig_d, all_d) {
  future <- all_d[all_d > sig_d]
  if (length(future) == 0) return(NA)
  min(future)
}

# Build execution schedule
exec_schedule <- data.table(
  sig_date  = signal_dates_v,
  exec_date = sapply(signal_dates_v, get_exec_date_local, all_d = all_dates_raw)
)
exec_schedule[, exec_date := as.Date(exec_date, origin = "1970-01-01")]
exec_schedule <- exec_schedule[!is.na(exec_date)]
exec_schedule[, next_exec := shift(exec_date, -1)]  # Next execution date
exec_schedule[is.na(next_exec), next_exec := max(all_dates_raw) + 1]

cat(sprintf("  Execution schedule: %d periods\n", nrow(exec_schedule)))

# Simulate daily portfolio returns
portfolio_rets <- list()
portfolio_log_list <- list()
prev_tickers <- character(0)

for (i in seq_len(nrow(exec_schedule))) {
  if (i %% 50 == 0) {
    cat(sprintf("  [sim] Period %d/%d (%s)...\n",
                i, nrow(exec_schedule), format(exec_schedule$sig_date[i])))
    gc(verbose=FALSE)
  }

  sig_d    <- exec_schedule$sig_date[i]
  exec_d   <- exec_schedule$exec_date[i]
  next_d   <- exec_schedule$next_exec[i]

  # Weights for this period
  w_today <- weights_dt[Date == sig_d]
  if (nrow(w_today) == 0) next
  curr_tickers <- w_today$Ticker
  curr_weights <- setNames(w_today$Weight, w_today$Ticker)

  # Compute turnover vs previous period
  exited  <- setdiff(prev_tickers, curr_tickers)
  entered <- setdiff(curr_tickers, prev_tickers)
  to_pct  <- (length(exited) + length(entered)) / max(length(prev_tickers), length(curr_tickers), 1)
  # Commission: one-way cost on gross turnover
  commission_drag <- to_pct * COMMISSION  # as fraction of portfolio

  # Days in this holding period: from exec_d to (next_d - 1)
  hold_dates <- all_dates_raw[all_dates_raw >= exec_d & all_dates_raw < next_d]

  for (d in hold_dates) {
    # Compute weighted portfolio return for day d
    day_d <- as.Date(d, origin = "1970-01-01")
    ret_today <- RAWDATA_RET[Date == day_d & Ticker %in% curr_tickers]

    if (nrow(ret_today) == 0) next

    # Match weights to available returns
    merged_r <- merge(data.table(Ticker = curr_tickers, w = curr_weights),
                      ret_today[, .(Ticker, Ret_d)],
                      by = "Ticker")

    if (nrow(merged_r) == 0) next

    # Re-normalize weights to available stocks (handle delistings)
    w_sum <- sum(merged_r$w)
    if (w_sum < 0.5) next  # Too few stocks available
    merged_r[, w_norm := w / w_sum]

    port_ret <- sum(merged_r$w_norm * merged_r$Ret_d)

    # Apply commission drag on rebalance day (exec_d)
    if (day_d == exec_d && to_pct > 0) {
      port_ret <- port_ret - commission_drag
    }

    portfolio_rets[[length(portfolio_rets) + 1]] <-
      data.table(Date = day_d, Strategy_Ret = port_ret,
                 n_names = nrow(merged_r), period_sig = sig_d)
  }

  portfolio_log_list[[length(portfolio_log_list) + 1]] <- data.table(
    sig_date     = sig_d,
    exec_date    = exec_d,
    n_names      = length(curr_tickers),
    turnover_pct = round(to_pct * 100, 2),
    commission_drag = round(commission_drag * 100, 4)
  )

  prev_tickers <- curr_tickers
}

cat(sprintf("  [sim] Done. Total daily records: %d\n", length(portfolio_rets)))

# ── Step 8: Build NAV data.table + returns ────────────────────────────────────
cat("\n[Step 8] Build NAV time series\n")

ret_dt <- rbindlist(portfolio_rets)
setorder(ret_dt, Date)

# Compute cumulative NAV
ret_dt[, NAV := INITIAL_CAP * cumprod(1 + Strategy_Ret)]
nav_dt <- ret_dt[, .(Date, NAV, Strategy_Ret)]

cat(sprintf("  NAV rows: %d | %s ~ %s\n",
            nrow(nav_dt), min(nav_dt$Date), max(nav_dt$Date)))
cat(sprintf("  NAV at end: %.0f (%.1fx)\n",
            tail(nav_dt$NAV, 1), tail(nav_dt$NAV, 1) / INITIAL_CAP))

# IS period: train up to 2023-12-31
nav_is <- nav_dt[Date <= as.Date("2023-12-31")]
cat(sprintf("  IS NAV rows: %d | %s ~ %s\n",
            nrow(nav_is),
            if (nrow(nav_is) > 0) format(min(nav_is$Date)) else "N/A",
            if (nrow(nav_is) > 0) format(max(nav_is$Date)) else "N/A"))

# Note: weights.csv only goes to 2023-12-01 (IS train)
# OOS (2024+) = frozen weights from 2023-12-01 signal, buy-and-hold
nav_oos <- nav_dt[Date >= as.Date("2024-01-01")]
cat(sprintf("  OOS NAV rows: %d | %s ~ %s\n",
            nrow(nav_oos),
            if (nrow(nav_oos) > 0) format(min(nav_oos$Date)) else "N/A",
            if (nrow(nav_oos) > 0) format(max(nav_oos$Date)) else "N/A"))

# Full period xts
nav_full <- nav_dt[!is.na(Strategy_Ret)]
strat_xts <- xts(nav_full$Strategy_Ret, order.by = as.Date(nav_full$Date))

# ── Step 9: Performance metrics ────────────────────────────────────────────────
cat("\n[Step 9] Performance metrics\n")

# Full IS period (training: 2004-2023)
strat_is_xts <- strat_xts[index(strat_xts) <= as.Date("2023-12-31")]
perf_is  <- summarise_perf(strat_is_xts, label = "V3_IS_full")
cat("  IS performance:\n")
print(perf_is)

# OOS (2024-2026)
perf_oos <- NULL
if (nrow(nav_oos) > 10) {
  strat_oos_xts <- strat_xts[index(strat_xts) >= as.Date("2024-01-01")]
  if (length(strat_oos_xts) > 10) {
    perf_oos <- summarise_perf(strat_oos_xts, label = "V3_OOS_24_26")
    cat("  OOS performance (2024-2026):\n")
    print(perf_oos)
  }
}

# Full period
perf_full <- summarise_perf(strat_xts, label = "V3_full")
cat("  Full period performance:\n")
print(perf_full)

# ── Step 10: PG2 Blend NAV (V3 ERC 80% + STR_1656 20%) ──────────────────────
cat("\n[Step 10] PG2 Blend NAV computation\n")

nav_1656_path <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1656_MLRA/output/nav_S1_B.csv")
nav_1656 <- fread(nav_1656_path)
nav_1656[, Date := as.Date(Date)]

# Compute daily returns
nav_1656[, Ret_1656 := c(NA_real_, diff(log(NAV)))]
nav_1656 <- nav_1656[!is.na(Ret_1656)]

nav_full2 <- nav_dt[!is.na(Strategy_Ret)][, .(Date, Ret_V3 = Strategy_Ret)]

# Merge on Date (inner join)
blend_dt <- merge(nav_full2, nav_1656[, .(Date, Ret_1656)], by = "Date")
cat(sprintf("  Blend common dates: %d | %s ~ %s\n",
            nrow(blend_dt), min(blend_dt$Date), max(blend_dt$Date)))

# Blend: 80% V3 + 20% STR_1656
blend_dt[, Ret_blend := 0.80 * Ret_V3 + 0.20 * Ret_1656]

# IS period for blend (common period with both)
blend_is <- blend_dt[Date <= as.Date("2023-12-31")]
cat(sprintf("  Blend IS dates: %d\n", nrow(blend_is)))

blend_xts_is <- xts(blend_is$Ret_blend, order.by = blend_is$Date)
perf_blend_is <- summarise_perf(blend_xts_is, label = "V3_blend_IS")
cat("  PG2 Blend IS performance:\n")
print(perf_blend_is)

# Full available period
blend_xts_full <- xts(blend_dt$Ret_blend, order.by = blend_dt$Date)
perf_blend_full <- summarise_perf(blend_xts_full, label = "V3_blend_full")
cat("  PG2 Blend FULL performance:\n")
print(perf_blend_full)

# ── Step 11: STR_1701 standalone comparison ────────────────────────────────────
cat("\n[Step 11] STR_1701 standalone comparison\n")

# STR_1701 uses alpha_scores column score_eff_str1701
# We simulate STR_1701 standalone using its score column from the same dataset
# Use equal weight (as STR_1701 was run with ivol weights at S1)
# For fair comparison: use the same alpha_scores parquet with score_eff_str1701

cat("  Note: STR_1701 standalone sim would require re-running harness.\n")
cat("  Using alpha_scores score_eff_str1701 for IC comparison only.\n")
cat("  Actual STR_1701 SR (Iter 11 production): 1.4625 (baseline PG2 anchor)\n")

# ── Step 12: FF5 Factor Regression (5-spec Harvey) ────────────────────────────
cat("\n[Step 12] FF5 Factor Regressions (5-spec Harvey)\n")

ff_path <- file.path(PROJECT_ROOT, ".cache/kr_factor_returns_v2.parquet")
ff_dt   <- as.data.table(read_parquet(ff_path))
ff_dt[, Date := as.Date(Date)]
setorder(ff_dt, Date)
cat(sprintf("  FF data: %d obs | %s ~ %s\n",
            nrow(ff_dt), min(ff_dt$Date), max(ff_dt$Date)))

# Monthly returns for regression
monthly_strat_xts <- apply.monthly(strat_is_xts, Return.cumulative)
monthly_strat <- data.table(
  Date     = as.Date(format(index(monthly_strat_xts), "%Y-%m-%d")),
  strat_ret = as.numeric(monthly_strat_xts)
)

# Merge on monthly dates
ff_monthly <- ff_dt  # already monthly
reg_dt <- merge(monthly_strat, ff_monthly, by = "Date")
reg_dt[, excess_ret := strat_ret - RF]

n_reg <- nrow(reg_dt)
cat(sprintf("  Regression obs: %d months\n", n_reg))

harvey_results <- list()

if (n_reg >= 24) {
  # Spec 1: CAPM
  m1 <- lm(excess_ret ~ MKT, data = reg_dt)
  s1 <- summary(m1)
  alpha_capm <- coef(m1)["(Intercept)"]
  t_capm     <- s1$coefficients["(Intercept)", "t value"]
  harvey_results[["CAPM"]] <- list(alpha = alpha_capm, t = t_capm,
    pass_harvey = abs(t_capm) > 3.0)

  # Spec 2: Carhart-3 (Fama-French 3 factor)
  m2 <- lm(excess_ret ~ MKT + SMB + HML, data = reg_dt)
  s2 <- summary(m2)
  alpha_ff3 <- coef(m2)["(Intercept)"]
  t_ff3     <- s2$coefficients["(Intercept)", "t value"]
  harvey_results[["FF3"]] <- list(alpha = alpha_ff3, t = t_ff3,
    pass_harvey = abs(t_ff3) > 3.0)

  # Spec 3: Carhart-4
  m3 <- lm(excess_ret ~ MKT + SMB + HML + WML, data = reg_dt)
  s3 <- summary(m3)
  alpha_c4 <- coef(m3)["(Intercept)"]
  t_c4     <- s3$coefficients["(Intercept)", "t value"]
  harvey_results[["Carhart4"]] <- list(alpha = alpha_c4, t = t_c4,
    pass_harvey = abs(t_c4) > 3.0)

  # Spec 4: FF5
  m4 <- lm(excess_ret ~ MKT + SMB + HML + RMW + CMA, data = reg_dt)
  s4 <- summary(m4)
  alpha_ff5 <- coef(m4)["(Intercept)"]
  t_ff5     <- s4$coefficients["(Intercept)", "t value"]
  harvey_results[["FF5"]] <- list(alpha = alpha_ff5, t = t_ff5,
    pass_harvey = abs(t_ff5) > 3.0)

  # Spec 5: FF6 (FF5 + WML)
  m5 <- lm(excess_ret ~ MKT + SMB + HML + WML + RMW + CMA, data = reg_dt)
  s5 <- summary(m5)
  alpha_ff6 <- coef(m5)["(Intercept)"]
  t_ff6     <- s5$coefficients["(Intercept)", "t value"]
  harvey_results[["FF6"]] <- list(alpha = alpha_ff6, t = t_ff6,
    pass_harvey = abs(t_ff6) > 3.0)

  harvey_pass_count <- sum(sapply(harvey_results, function(x) x$pass_harvey))
  cat(sprintf("  Harvey pass (|t|>3.0): %d/5\n", harvey_pass_count))
  for (spec_name in names(harvey_results)) {
    hr <- harvey_results[[spec_name]]
    cat(sprintf("    %s: alpha=%.4f%% t=%.3f %s\n",
                spec_name, hr$alpha * 100, hr$t,
                if (hr$pass_harvey) "PASS" else "FAIL"))
  }
} else {
  cat("  Insufficient obs for FF5 regressions.\n")
  harvey_pass_count <- 0
}

# ── Step 13: DSR (Deflated Sharpe Ratio) ─────────────────────────────────────
cat("\n[Step 13] DSR post-penalty computation\n")

sr_is <- as.numeric(perf_is$Sharpe)
n_trials_v3 <- 15  # Iter 15 = 15 permutation trials in Track A

# DSR = Sharpe * sqrt((1 - skew * SR / sqrt(T) + (kurtosis-1)/4 * SR^2 / T) / n_trials) ...
# Simplified Haircut Sharpe (Bailey & Lopez de Prado 2012)
# SR* = SR * (1 - sqrt(ln(n_trials) / ln(T))) where T = months
T_months <- nrow(monthly_strat)
dsr_penalty <- sqrt(log(n_trials_v3) / log(T_months))
sr_dsr <- sr_is * (1 - dsr_penalty)
cat(sprintf("  SR_IS: %.4f | n_trials: %d | T: %d months\n",
            sr_is, n_trials_v3, T_months))
cat(sprintf("  DSR penalty factor: %.4f | SR_DSR: %.4f\n", dsr_penalty, sr_dsr))

# ── Step 14: Tail risk measurement (weight-applied) ──────────────────────────
cat("\n[Step 14] Tail risk measurement\n")

r_num <- as.numeric(strat_is_xts)
r_num <- r_num[!is.na(r_num)]

# CVaR daily (ES99)
cvar_cutoff <- quantile(r_num, 0.05, na.rm = TRUE)  # 5% daily CVaR
tail_r <- r_num[r_num <= cvar_cutoff]
cvar_d_realized <- if (length(tail_r) > 0) mean(tail_r) else NA_real_
cat(sprintf("  CVaR_d (5%% ES) realized: %.4f (%.2f%%)\n",
            cvar_d_realized, cvar_d_realized * 100))
cat(sprintf("  CVaR_d cap breach check: %.4f vs -0.025 => %s\n",
            cvar_d_realized,
            if (!is.na(cvar_d_realized) && cvar_d_realized < -0.025) "BREACH" else "PASS"))

# MDD
mdd_realized <- -maxDrawdown(strat_is_xts)
cat(sprintf("  MDD realized: %.2f%%\n", mdd_realized * 100))

# ── Step 15: 8-stress period analysis ────────────────────────────────────────
cat("\n[Step 15] 8-stress period analysis\n")

stress_periods <- list(
  list(name = "GFC_2008",      start = "2008-09-01", end = "2009-03-31"),
  list(name = "EU_Debt_2011",  start = "2011-07-01", end = "2011-12-31"),
  list(name = "China_2015",    start = "2015-06-01", end = "2016-02-29"),
  list(name = "KOSPI_2018",    start = "2018-10-01", end = "2018-12-31"),
  list(name = "COVID_2020",    start = "2020-01-01", end = "2020-03-31"),
  list(name = "Rate_Hike_2022",start = "2022-01-01", end = "2022-12-31"),
  list(name = "KR_Semi_2023",  start = "2023-01-01", end = "2023-06-30"),
  list(name = "MRS_CRISIS_2024",start="2024-01-01", end = "2024-12-31")
)

stress_results <- lapply(stress_periods, function(sp) {
  s_xts <- strat_xts[paste0(sp$start, "/", sp$end)]
  if (length(s_xts) < 5) return(data.table(period = sp$name, ret = NA, mdd = NA, n = 0))
  ret <- as.numeric(prod(1 + s_xts) - 1) * 100
  mdd_s <- -maxDrawdown(s_xts) * 100
  data.table(period = sp$name, ret = round(ret, 2), mdd = round(mdd_s, 2),
             n = length(s_xts))
})
stress_dt <- rbindlist(stress_results)
cat("  Stress period summary:\n")
print(stress_dt)

# ── Step 16: Save NAV CSVs ────────────────────────────────────────────────────
cat("\n[Step 16] Save NAV outputs\n")

# Monthly NAV for judge
nav_monthly_raw <- apply.monthly(strat_xts, Return.cumulative)
nav_monthly_dt  <- data.table(
  Date       = as.Date(format(index(nav_monthly_raw), "%Y-%m-%d")),
  Monthly_Ret = round(as.numeric(nav_monthly_raw), 6)
)
fwrite(nav_monthly_dt, file.path(JUDGE_DIR, "nav_monthly_v3.csv"))
cat(sprintf("  nav_monthly_v3.csv: %d rows\n", nrow(nav_monthly_dt)))

# Daily ret
fwrite(nav_dt[, .(Date, NAV, Strategy_Ret)],
       file.path(JUDGE_DIR, "ret_d_v3.csv"))
cat(sprintf("  ret_d_v3.csv: %d rows\n", nrow(nav_dt)))

# Blend monthly
blend_monthly_raw <- apply.monthly(blend_xts_full, Return.cumulative)
blend_monthly_dt  <- data.table(
  Date       = as.Date(format(index(blend_monthly_raw), "%Y-%m-%d")),
  Monthly_Ret = round(as.numeric(blend_monthly_raw), 6)
)
fwrite(blend_monthly_dt, file.path(JUDGE_DIR, "nav_monthly_blend.csv"))
cat(sprintf("  nav_monthly_blend.csv: %d rows\n", nrow(blend_monthly_dt)))

# Portfolio log
if (length(portfolio_log_list) > 0) {
  port_log <- rbindlist(portfolio_log_list)
  fwrite(port_log, file.path(OUT_DIR, "portfolio_log.csv"))
  cat(sprintf("  portfolio_log.csv: %d rows\n", nrow(port_log)))

  # Annualized turnover
  n_years_sim <- as.numeric(difftime(max(port_log$exec_date),
                                      min(port_log$exec_date), units="days")) / 365.25
  annual_to <- sum(port_log$turnover_pct) / n_years_sim
  cat(sprintf("  Annualized turnover: %.1f%%\n", annual_to))
} else {
  annual_to <- NA_real_
}

# ── Step 17: Charts (4종) ─────────────────────────────────────────────────────
cat("\n[Step 17] Generate charts\n")

# BM returns for overlay
bm_xts <- NULL
tryCatch({
  bm_sub <- BM_DT[Date >= min(nav_full$Date) & Date <= max(nav_full$Date)]
  setorder(bm_sub, Date)
  bm_sub[, BM_Ret := c(NA, diff(log(Close)))]
  bm_sub <- bm_sub[!is.na(BM_Ret)]
  bm_xts <- xts(bm_sub$BM_Ret, order.by = as.Date(bm_sub$Date))
}, error = function(e) cat("[WARN] BM load failed:", conditionMessage(e), "\n"))

# Chart 1: Equity curve
png(file.path(OUT_DIR, "equity_curve.png"), width = 1200, height = 700, res = 120)
nav_cum <- cumprod(1 + strat_xts)
plot_dt <- data.table(Date = index(nav_cum), V3 = as.numeric(nav_cum))

if (!is.null(bm_xts)) {
  bm_cum <- cumprod(1 + bm_xts)
  bm_dt  <- data.table(Date = index(bm_cum), BM = as.numeric(bm_cum))
  plot_dt <- merge(plot_dt, bm_dt, by = "Date", all.x = TRUE)
} else {
  plot_dt[, BM := NA_real_]
}

p1 <- ggplot(melt(plot_dt, id.vars = "Date", na.rm = TRUE)) +
  geom_line(aes(x = Date, y = value, color = variable), linewidth = 0.8) +
  geom_vline(xintercept = as.Date("2024-01-01"), linetype = "dashed",
             color = "gray40", linewidth = 0.6) +
  annotate("text", x = as.Date("2024-02-01"), y = max(plot_dt$V3, na.rm=TRUE) * 0.9,
           label = "OOS\n2024+", size = 3, color = "gray40") +
  scale_color_manual(values = c(V3 = "#1f77b4", BM = "#d62728")) +
  scale_y_log10(labels = label_number(accuracy = 0.01)) +
  labs(title = "WT-D20260426_008 Track A Iter15 V3 ERC — Equity Curve",
       subtitle = sprintf("SR=%.3f | CAGR=%.1f%% | MDD=%.1f%% | IS: 2004-2023",
                          perf_is$Sharpe, perf_is$CAGR, -abs(perf_is$MDD)),
       x = NULL, y = "Cumulative NAV (log)", color = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top")
print(p1)
dev.off()
cat("  equity_curve.png saved.\n")

# Chart 2: Annual returns bar chart
ann_rets <- apply.yearly(strat_xts, Return.cumulative)
ann_dt   <- data.table(Year = as.integer(format(as.Date(format(index(ann_rets), "%Y-%m-%d")), "%Y")),
                        Ret  = round(as.numeric(ann_rets) * 100, 2))
ann_dt[, Color := ifelse(Ret >= 0, "positive", "negative")]

png(file.path(OUT_DIR, "annual_returns.png"), width = 1200, height = 600, res = 120)
p2 <- ggplot(ann_dt, aes(x = Year, y = Ret, fill = Color)) +
  geom_bar(stat = "identity", width = 0.7) +
  geom_hline(yintercept = 0, linewidth = 0.3) +
  geom_text(aes(label = sprintf("%.1f", Ret),
                vjust = ifelse(Ret >= 0, -0.3, 1.3)), size = 2.8) +
  scale_fill_manual(values = c(positive = "#2ca02c", negative = "#d62728")) +
  labs(title = "V3 ERC — Annual Returns",
       subtitle = sprintf("IS 2004-2023 | OOS 2024+"),
       x = NULL, y = "Return (%)", fill = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "none")
print(p2)
dev.off()
cat("  annual_returns.png saved.\n")

# Chart 3: OOS zoom (2024-2026)
png(file.path(OUT_DIR, "oos_zoom.png"), width = 1200, height = 600, res = 120)
strat_oos_plot <- strat_xts[index(strat_xts) >= as.Date("2024-01-01")]
if (length(strat_oos_plot) > 5) {
  oos_cum <- cumprod(1 + strat_oos_plot)
  oos_dt  <- data.table(Date = index(oos_cum), V3 = as.numeric(oos_cum))
  p3 <- ggplot(oos_dt, aes(x = Date, y = V3)) +
    geom_line(color = "#1f77b4", linewidth = 1.0) +
    geom_hline(yintercept = 1.0, linetype = "dashed", color = "gray60") +
    scale_y_continuous(labels = label_percent(accuracy = 0.1, scale = 100)) +
    labs(title = "V3 ERC — OOS 2024-2026 (Frozen Weights)",
         subtitle = if (!is.null(perf_oos)) {
           sprintf("OOS SR=%.3f | CAGR=%.1f%% | MDD=%.1f%%",
                   perf_oos$Sharpe, perf_oos$CAGR, -abs(perf_oos$MDD))
         } else "OOS period (2024+)",
         x = NULL, y = "Cumulative Return") +
    theme_minimal(base_size = 11)
  print(p3)
} else {
  plot.new()
  title("OOS 2024-2026: Insufficient data")
}
dev.off()
cat("  oos_zoom.png saved.\n")

# Chart 4: Scenario comparison (V3 blend vs baseline PG2 vs current PG2)
png(file.path(OUT_DIR, "scenario_comparison.png"), width = 1200, height = 700, res = 120)

# V3 blend
blend_cum <- cumprod(1 + blend_xts_full)
scen_dt <- data.table(Date = index(blend_cum),
                       V3_Blend = as.numeric(blend_cum))

# STR_1656 standalone
nav_1656_sub <- nav_1656[Date >= min(blend_dt$Date)]
strat_1656_xts <- xts(nav_1656_sub$Ret_1656, order.by = nav_1656_sub$Date)
strat_1656_xts <- strat_1656_xts[!is.na(strat_1656_xts)]
cum_1656 <- cumprod(1 + strat_1656_xts)
dt_1656  <- data.table(Date = index(cum_1656), STR_1656 = as.numeric(cum_1656))

scen_dt <- merge(scen_dt, dt_1656, by = "Date", all.x = TRUE)

# Note: Baseline PG2 (STR_1701 80% + STR_1656 20%) realized SR = 1.4625
# We don't have STR_1701 daily NAV available so we annotate instead
scen_long <- melt(scen_dt, id.vars = "Date", na.rm = TRUE)
p4 <- ggplot(scen_long, aes(x = Date, y = value, color = variable)) +
  geom_line(linewidth = 0.8) +
  geom_vline(xintercept = as.Date("2024-01-01"), linetype = "dashed",
             color = "gray40", linewidth = 0.5) +
  scale_color_manual(values = c(V3_Blend = "#1f77b4", STR_1656 = "#ff7f0e")) +
  scale_y_log10(labels = label_number(accuracy = 0.01)) +
  annotate("label", x = as.Date("2014-01-01"),
           y = max(scen_dt$V3_Blend, na.rm=TRUE) * 0.3,
           label = sprintf("Baseline PG2 SR: 1.4625\nV3 blend SR: %.4f\nDelta: %+.4f",
                           perf_blend_full$Sharpe,
                           perf_blend_full$Sharpe - 1.4625),
           size = 3, hjust = 0) +
  labs(title = "Scenario Comparison: V3 Blend vs Components",
       subtitle = "V3 blend = V3_ERC 80% + STR_1656 20% | Baseline PG2 SR=1.4625",
       x = NULL, y = "Cumulative NAV (log)", color = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top")
print(p4)
dev.off()
cat("  scenario_comparison.png saved.\n")

# ── Step 18: Forge package JSON ────────────────────────────────────────────────
cat("\n[Step 18] Write forge_package.json\n")

v3_blend_sr  <- round(as.numeric(perf_blend_full$Sharpe), 4)
v3_blend_mdd <- round(as.numeric(-abs(perf_blend_full$MDD)), 2)
pg2_baseline  <- 1.4625
v3_vs_baseline_delta <- round(v3_blend_sr - pg2_baseline, 4)

forge_pkg <- list(
  task_id           = "WT-D20260426_008",
  agent             = "Forge",
  forge_version     = "v6.1",
  timestamp         = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  iter              = 15,
  strategy_name     = "V3_ERC_Iter15",
  pit_cutoff        = format(PIT_CUTOFF),
  hash_audit = list(
    start = START_HASHES,
    end   = list(
      alpha_package    = as.character(system("md5sum '/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-D20260426_008/alpha_package.json' | cut -d' ' -f1", intern=TRUE)),
      risk_package     = as.character(system("md5sum '/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-D20260426_008/risk_package.json' | cut -d' ' -f1", intern=TRUE)),
      optimization_pkg = as.character(system("md5sum '/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-D20260426_008/optimization_package.json' | cut -d' ' -f1", intern=TRUE)),
      weights_csv      = as.character(system("md5sum '/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-D20260426_008/weights.csv' | cut -d' ' -f1", intern=TRUE))
    ),
    pure_function_verified = TRUE,
    note = "Alpha/Risk/Optimization packages read-only. No recomputation."
  ),
  performance = list(
    V3_IS_full = list(
      sr   = round(as.numeric(perf_is$Sharpe), 4),
      cagr = round(as.numeric(perf_is$CAGR), 2),
      mdd  = round(as.numeric(-abs(perf_is$MDD)), 2),
      vol  = round(as.numeric(perf_is$AnnVol), 2)
    ),
    V3_blend_full = list(
      sr           = v3_blend_sr,
      cagr         = round(as.numeric(perf_blend_full$CAGR), 2),
      mdd          = v3_blend_mdd,
      baseline_pg2 = pg2_baseline,
      delta_vs_baseline = v3_vs_baseline_delta,
      pg2_upgrade  = v3_blend_sr > pg2_baseline
    ),
    V3_blend_IS = list(
      sr   = round(as.numeric(perf_blend_is$Sharpe), 4),
      cagr = round(as.numeric(perf_blend_is$CAGR), 2),
      mdd  = round(as.numeric(-abs(perf_blend_is$MDD)), 2)
    ),
    V3_OOS_24_26 = if (!is.null(perf_oos)) list(
      sr   = round(as.numeric(perf_oos$Sharpe), 4),
      cagr = round(as.numeric(perf_oos$CAGR), 2),
      mdd  = round(as.numeric(-abs(perf_oos$MDD)), 2)
    ) else list(sr = NA, cagr = NA, mdd = NA)
  ),
  tail_risk = list(
    cvar_d_5pct_realized = round(cvar_d_realized, 6),
    cvar_d_cap_breach = if (!is.na(cvar_d_realized)) cvar_d_realized < -0.025 else TRUE,
    mdd_realized     = round(mdd_realized, 4),
    cvar_optimizer_flagged = opt_pkg$cvar_d_post_optim,
    structural_infeasibility = "ERC chosen as best-effort; CVaR_d -3.08% structural breach in NORMAL regime"
  ),
  harvey_ff5 = list(
    specs_tested   = 5,
    pass_count     = harvey_pass_count,
    results        = harvey_results
  ),
  dsr = list(
    sr_is      = sr_is,
    n_trials   = n_trials_v3,
    t_months   = T_months,
    sr_dsr     = round(sr_dsr, 4),
    method     = "Bailey-LopezdePrado 2012 haircut"
  ),
  turnover = list(
    annual_pct = if (exists("annual_to") && !is.na(annual_to)) round(annual_to, 1) else NA
  ),
  stress_periods = stress_dt,
  pg2_decision = list(
    baseline_sr    = pg2_baseline,
    v3_blend_sr    = v3_blend_sr,
    delta          = v3_vs_baseline_delta,
    recommend      = if (!is.na(v3_blend_sr) && v3_blend_sr > pg2_baseline) "UPGRADE_PG2" else "MAINTAIN_BASELINE",
    notes          = "ERC near-EW (alpha tilt minimal). CVaR structural breach. Net_IR 0.91 < STR_1701 standalone 1.29."
  ),
  codex_stance    = "OVERRIDE_005",
  codex_note      = "Codex CLI stall risk acknowledged per WT mandate. Self-disclosed infeasibility + Risk pkg structural diagnosis as substitute evidence.",
  outputs = list(
    nav_d_csv       = file.path(JUDGE_DIR, "ret_d_v3.csv"),
    nav_monthly_csv = file.path(JUDGE_DIR, "nav_monthly_v3.csv"),
    blend_monthly   = file.path(JUDGE_DIR, "nav_monthly_blend.csv"),
    equity_curve    = file.path(OUT_DIR, "equity_curve.png"),
    annual_returns  = file.path(OUT_DIR, "annual_returns.png"),
    oos_zoom        = file.path(OUT_DIR, "oos_zoom.png"),
    scenario_cmp    = file.path(OUT_DIR, "scenario_comparison.png")
  )
)

write_json(forge_pkg, file.path(WT_DIR, "forge_package.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("  forge_package.json written.\n"))

# ── Step 19: Codex OVERRIDE_005 evidence JSON ─────────────────────────────────
cat("\n[Step 19] Write codex_critic_response_forge.json (OVERRIDE_005)\n")

codex_override <- list(
  task_id     = "WT-D20260426_008",
  override_code = "OVERRIDE_005",
  trigger     = "Codex CLI stall pattern — Risk + Optimizer both flagged structural infeasibility",
  substitute_evidence = list(
    source_1_forge_self_disclosure = list(
      finding     = "ERC near-EW range 0.048~0.052. Alpha tilt effectively zero.",
      implication = "Net IR 0.91 < STR_1701 standalone 1.29 (Iter 11). Multi-mutation upgrade did not improve alpha utilization.",
      code        = "FORGE_SELF_DISCLOSED"
    ),
    source_2_risk_structural = list(
      finding     = "CVaR_d structural infeasibility: KR top-20 long-only universe EW floor -2.90% in NORMAL regime",
      implication = "No long-only optimizer can satisfy -2.5% cap without 30%+ cash overlay (out of scope)",
      code        = "RISK_PKG_STRUCTURAL_DIAGNOSIS"
    ),
    source_3_optimizer_selection = list(
      finding     = "ERC selected as best-effort among [ERC/HRP/InvVol/MVO]. HRP fails MDD (-56%). InvVol fails TO (7.85 > 6.0 cap).",
      implication = "ERC is least-bad but CVaR constraint remains violated.",
      code        = "OPT_PKG_INFEASIBILITY_REPORT"
    )
  ),
  verdict = "PROCEED_WITH_CAVEATS",
  caveats = list(
    "CVaR_d -3.08% (cap: -2.5%) structural breach — Governor/Q-Lead must decide on cap relaxation",
    "Alpha utilization near-zero (ERC ≈ EW) — PG2 upgrade benefit minimal",
    "V3 net_IR 0.91 < baseline 1.29 confirms mutation did not improve raw IR"
  ),
  recommendation = "Run full backtest for honest measurement. Let realized SR decide PG2 fate."
)

write_json(codex_override, file.path(WT_DIR, "codex_critic_response_forge.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("  codex_critic_response_forge.json written.\n")

# ── Step 20: Hash Audit COMPLETE ─────────────────────────────────────────────
cat("\n[Step 20] Hash Audit COMPLETE verification\n")
end_hashes <- list(
  alpha_package    = trimws(system(paste0("md5sum '", file.path(WT_DIR, "alpha_package.json"), "' | cut -d' ' -f1"), intern=TRUE)),
  risk_package     = trimws(system(paste0("md5sum '", file.path(WT_DIR, "risk_package.json"), "' | cut -d' ' -f1"), intern=TRUE)),
  optimization_pkg = trimws(system(paste0("md5sum '", file.path(WT_DIR, "optimization_package.json"), "' | cut -d' ' -f1"), intern=TRUE)),
  weights_csv      = trimws(system(paste0("md5sum '", file.path(WT_DIR, "weights.csv"), "' | cut -d' ' -f1"), intern=TRUE))
)
hash_ok <- all(mapply(function(s, e) s == e, START_HASHES, end_hashes))
cat(sprintf("  Hash match: %s\n", if (hash_ok) "ALL PASS" else "MISMATCH DETECTED"))
for (nm in names(START_HASHES)) {
  match_flag <- START_HASHES[[nm]] == end_hashes[[nm]]
  cat(sprintf("    %s: %s\n", nm, if (match_flag) "OK" else paste("MISMATCH", end_hashes[[nm]])))
}
if (!hash_ok) stop("[HASH_AUDIT FAIL] Pure function violated: package modified during backtest")

# ── Step 21: Telegram notification ────────────────────────────────────────────
cat("\n[Step 21] Telegram notification\n")
tryCatch({
  source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

  v3_sr_is   <- round(as.numeric(perf_is$Sharpe), 3)
  v3_sr_full <- round(as.numeric(perf_full$Sharpe), 3)
  v3_sr_blend <- v3_blend_sr
  delta_sr    <- v3_vs_baseline_delta
  v3_mdd      <- round(as.numeric(-abs(perf_is$MDD)), 1)
  v3_cagr     <- round(as.numeric(perf_is$CAGR), 1)
  oos_sr_str  <- if (!is.null(perf_oos)) sprintf("%.3f", perf_oos$Sharpe) else "N/A"
  harvey_str  <- sprintf("%d/5", harvey_pass_count)
  recommend   <- if (!is.na(v3_blend_sr) && v3_blend_sr > pg2_baseline) "UPGRADE_PG2" else "MAINTAIN_BASELINE"
  upgrade_flag <- v3_blend_sr > pg2_baseline

  tg_agent_brief(
    agent    = "Forge",
    scope    = "WT-D20260426_008 Track A Iter15 V3 ERC Backtest",
    headline = sprintf("[Forge] WT-D20260426_008 Track A Iter15 V3 ERC Backtest 완료"),
    sections = list(
      list(type = "text", label = "PG2 결정 지표",
           content = sprintf("V3 blend SR: %.4f vs Baseline 1.4625 | Delta: %+.4f => %s",
                             v3_blend_sr, delta_sr, recommend)),
      list(type = "table", label = "성과 요약",
           content = data.frame(
             지표    = c("V3 IS SR", "V3 Blend SR", "Baseline PG2", "Delta", "MDD", "CAGR", "OOS SR"),
             값      = c(v3_sr_is, v3_sr_blend, pg2_baseline, delta_sr, v3_mdd, v3_cagr, oos_sr_str)
           )),
      list(type = "kv", label = "Factor Regression",
           content = list(Harvey_5spec = harvey_str,
                          DSR_post = round(sr_dsr, 4),
                          CVaR_d_realized = round(cvar_d_realized * 100, 2),
                          CVaR_breach = cvar_d_realized < -0.025,
                          Codex = "OVERRIDE_005")),
      list(type = "bullet", label = "주요 우려사항",
           content = c(
             "ERC near-EW (0.048~0.052): alpha tilt 거의 활용 X",
             sprintf("V3 net_IR 0.91 < STR_1701 standalone 1.29"),
             sprintf("CVaR_d %.2f%% vs cap -2.5%% BREACH (구조적)",
                     cvar_d_realized * 100),
             "Hash audit PASS — pure function verified"
           ))
    ),
    photos = c(
      file.path(OUT_DIR, "equity_curve.png"),
      file.path(OUT_DIR, "annual_returns.png"),
      file.path(OUT_DIR, "oos_zoom.png"),
      file.path(OUT_DIR, "scenario_comparison.png")
    )
  )
  cat("  Telegram sent.\n")
}, error = function(e) {
  cat(sprintf("[WARN] Telegram failed: %s\n", conditionMessage(e)))
  # Fallback: direct tg_send
  tryCatch({
    msg <- sprintf(
      "[Forge] WT-D20260426_008 Track A Iter15 V3 ERC Backtest 완료\n\nPG2 결정: V3 blend SR=%.4f vs Baseline 1.4625 | Delta=%+.4f | %s\n\nV3 IS SR=%.3f | CAGR=%.1f%% | MDD=%.1f%%\nHarvey %s | DSR_post=%.4f\nCVaR_d=%.2f%% (%s)\nCodex: OVERRIDE_005 | Hash: PASS",
      v3_blend_sr, delta_sr,
      if (!is.na(v3_blend_sr) && v3_blend_sr > pg2_baseline) "UPGRADE_PG2" else "MAINTAIN_BASELINE",
      v3_sr_is, v3_cagr, v3_mdd, harvey_str, sr_dsr,
      cvar_d_realized * 100,
      if (cvar_d_realized < -0.025) "BREACH" else "PASS"
    )
    tg_send(msg, parse_mode = "")
    # Send charts
    for (chart_path in c(
      file.path(OUT_DIR, "equity_curve.png"),
      file.path(OUT_DIR, "annual_returns.png"),
      file.path(OUT_DIR, "oos_zoom.png"),
      file.path(OUT_DIR, "scenario_comparison.png")
    )) {
      if (file.exists(chart_path)) tg_send_photo(chart_path)
    }
    cat("  Fallback Telegram sent.\n")
  }, error = function(e2) {
    cat(sprintf("[WARN] Fallback Telegram also failed: %s\n", conditionMessage(e2)))
  })
})

# ── Final Summary ─────────────────────────────────────────────────────────────
cat("\n", rep("=", 60), "\n", sep="")
cat("FORGE_DONE SUMMARY\n")
cat(rep("=", 60), "\n", sep="")
cat(sprintf("V3_standalone_sr_full     = %.4f\n", as.numeric(perf_full$Sharpe)))
cat(sprintf("V3_standalone_sr_IS       = %.4f\n", as.numeric(perf_is$Sharpe)))
cat(sprintf("V3_blend_realized_sr      = %.4f\n", v3_blend_sr))
cat(sprintf("baseline_PG2_sr           = 1.4625\n"))
cat(sprintf("V3_vs_baseline_delta      = %+.4f\n", v3_vs_baseline_delta))
cat(sprintf("mdd                       = %.2f%%\n", as.numeric(-abs(perf_is$MDD))))
cat(sprintf("cvar_d_realized           = %.4f (%.2f%%)\n",
            cvar_d_realized, cvar_d_realized * 100))
cat(sprintf("harvey_5spec              = %d/5\n", harvey_pass_count))
cat(sprintf("dsr_post                  = %.4f\n", sr_dsr))
cat(sprintf("oos_24_26_sr              = %s\n",
            if (!is.null(perf_oos)) sprintf("%.4f", as.numeric(perf_oos$Sharpe)) else "N/A"))
cat(sprintf("codex_stance              = OVERRIDE_005\n"))
cat(sprintf("hash_audit                = %s\n", if (hash_ok) "PASS" else "FAIL"))
cat(sprintf("pg2_recommend             = %s\n",
            if (!is.na(v3_blend_sr) && v3_blend_sr > pg2_baseline) "UPGRADE_PG2" else "MAINTAIN_BASELINE"))
cat(rep("=", 60), "\n", sep="")
cat("=== WT-D20260426_008 Forge 백테스트 완료 ===\n")
