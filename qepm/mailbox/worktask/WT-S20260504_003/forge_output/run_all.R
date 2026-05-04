## ============================================================================
## WT-S20260504_003 HMM Regime Forge — 3-Strategy Backtest (Pure Function)
## ============================================================================
## Role: Forge agent (v6.4)
## Boundary: alpha/risk/optimizer 패키지 수정 절대 금지.
##           weights.csv as-is (signal-date 기반) + STR_1715 268m returns 사용.
## Method: PerformanceAnalytics 표준 함수만 (Backtest Contract v1.0).
## Strategies:
##   S1            — STR_1715 baseline (w_str=1, w_cash=0 throughout)
##   HMM_Scale     — STR_1715 × HMM walk-forward scale_predicted (PIT-clean)
##   M4+HMM_Scale  — canonical: w_cash = max(M4_cash, 1 - HMM_scale)
##
## Date alignment:
##   weights.csv: signal_date (2004-01-01..2026-03-01, 267 dates, month-first)
##   STR_1715 returns: execution_date (2004-02-02..2026-05-01, 268 dates)
##   Match: weight at signal_date t applied to execution-month return at t+1
##   ⇒ join weights[1..267] ↔ returns[1..267] (drop last return 2026-05-01
##     which has no signal-date counterpart in weights schedule)
## ============================================================================

suppressMessages({
  library(data.table)
  library(PerformanceAnalytics)
  library(xts)
  library(jsonlite)
  library(digest)
})

## --- 0. Path setup -----------------------------------------------------------
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-S20260504_003"
OUT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID, "forge_output")
STAGE_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID))
WS_DIR <- file.path(OUT_DIR, "_workspace")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(WS_DIR, showWarnings = FALSE, recursive = TRUE)

cat("\n=== WT-S20260504_003 HMM Regime Forge — Pure Function 3-strategy ===\n")
cat(sprintf("Run at: %s\n", format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")))

## --- 1. Load contracts -------------------------------------------------------
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/audit_bt_result.R"))

## --- 2. Hash check (start) ---------------------------------------------------
hash_files <- c(
  file.path(STAGE_DIR, "weights.csv"),
  file.path(STAGE_DIR, "weights_variants/S1.csv"),
  file.path(STAGE_DIR, "weights_variants/HMM_Scale.csv"),
  file.path(STAGE_DIR, "weights_variants/M4+HMM_Scale.csv"),
  file.path(STAGE_DIR, "lro_params_frozen.json"),
  file.path(STAGE_DIR, "hmm_params.json")
)
start_hashes <- sapply(hash_files, function(f) digest(file = f, algo = "md5"))
names(start_hashes) <- basename(hash_files)
cat("\n[hash-start]\n"); print(start_hashes)

## --- 3. Load STR_1715 returns ------------------------------------------------
str_ret_path <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv")
str_ret <- fread(str_ret_path)
str_ret[, date := as.Date(date)]
setorder(str_ret, date)
cat(sprintf("\n[str_ret] %d rows, %s..%s\n", nrow(str_ret),
  min(str_ret$date), max(str_ret$date)))

## --- 4. Load HMM walk-forward path (for diagnostics) -------------------------
hmm_wf <- fread(file.path(STAGE_DIR, "hmm_posterior_path_walkforward.csv"))
hmm_wf[, date := as.Date(date)]
cat(sprintf("[hmm_wf] %d rows, valid scale_predicted = %d\n",
  nrow(hmm_wf), sum(!is.na(hmm_wf$scale_predicted))))

## --- 5. KOSPI200 benchmark from .cache/benchmark.parquet (daily → monthly) ---
## STR_1715's 05_benchmark_returns.csv is stub (all 0). Use actual KOSPI200 daily.
suppressMessages(library(arrow))
bm_daily <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/benchmark.parquet")))
bm_daily <- bm_daily[!is.na(BM_Ret)]
setorder(bm_daily, Date)
## Compute monthly KOSPI returns mapped to STR_1715 execution_dates (last available daily ≤ exec_date)
str_dates <- str_ret$date  # exec_dates (1st-of-month-ish)
bm_monthly <- data.table(date = str_dates, benchmark_ret = NA_real_)
for (i in seq_along(str_dates)) {
  if (i == 1) {
    sub <- bm_daily[Date <= str_dates[i]]
  } else {
    sub <- bm_daily[Date > str_dates[i-1] & Date <= str_dates[i]]
  }
  if (nrow(sub) > 0) bm_monthly$benchmark_ret[i] <- prod(1 + sub$BM_Ret) - 1
}
bm_monthly[is.na(benchmark_ret), benchmark_ret := 0]
bm_monthly[, benchmark_id := "KOSPI200"]
bm_monthly[, benchmark_name := "KOSPI 200"]
bm_monthly[, frequency := "monthly"]
bm_monthly[, benchmark_nav := cumprod(1 + benchmark_ret)]
bm_monthly[, risk_free_ret := 0]
bm_monthly[, benchmark_excess_ret := benchmark_ret]
setcolorder(bm_monthly, c("benchmark_id","benchmark_name","date","frequency",
                          "benchmark_ret","benchmark_nav","risk_free_ret","benchmark_excess_ret"))
bm_ret <- bm_monthly
cat(sprintf("[bm_ret] %d rows, benchmark=KOSPI200, total_ret=%.4f\n",
  nrow(bm_ret), prod(1 + bm_ret$benchmark_ret) - 1))

## --- 6. Strategy backtest function -------------------------------------------
##
## Pure function: weights_csv_path → bt_result list (10-component)
##
## Mapping convention:
##   weights.csv has signal_date (month-start, e.g., 2004-01-01).
##   STR_1715 returns has execution_date (e.g., 2004-02-02).
##   The signal at 2004-01-01 (∀i≤267) applies to execution at index i+1
##   in str_ret (which starts 2004-02-02).
##   ⇒ For period i in 1..267: ret_strategy[i] = w_str[i] * ret_str_1715[i+1]
##   First STR_1715 return (2004-02-02) thus has no preceding weight signal —
##   it represents the warm-up of the parent (assume w_str=1.0).
##
## Cost on weight transition: 15bps one-way × |w_str[i] - w_str[i-1]|.
## (At sleeve level — STR_1715 internal turnover already absorbed in str_ret.)

run_strategy <- function(weights_csv_path, strategy_name, run_id) {

  cat(sprintf("\n=== %s ===\n", strategy_name))

  w <- fread(weights_csv_path)
  setnames(w, c("Date", "weight_str1715", "weight_cash"),
              c("signal_date", "w_str", "w_cash"), skip_absent = TRUE)
  w[, signal_date := as.Date(signal_date)]
  setorder(w, signal_date)

  # Validate sums
  stopifnot(all(abs(w$w_str + w$w_cash - 1) < 1e-8))
  stopifnot(all(w$w_str >= 0 & w$w_str <= 1))
  stopifnot(all(w$w_cash >= 0 & w$w_cash <= 1))

  # Align with str_ret execution_date
  # signal_date i → execution_date == nth ret after warm-up
  # str_ret has 268 rows (2004-02-02 .. 2026-05-01).
  # weights has 267 rows (2004-01-01 .. 2026-03-01).
  # We treat str_ret row i+1 (i = 1..267) as paired with weights row i.
  # str_ret row 1 (2004-02-02) is warm-up: no weight applied (skip in match).

  if (nrow(w) != nrow(str_ret) - 1) {
    stop(sprintf("[run_strategy] weight rows %d != str_ret rows %d - 1",
                 nrow(w), nrow(str_ret)))
  }

  # Effective return per period at execution_date i+1:
  # ret_eff[i] = w_str[i] * ret_str[i+1] + w_cash[i] * 0 - cost[i]
  # cost[i] = 15bps * |w_str[i] - w_str[i-1]|, w_str[0] := 1 (S1 baseline initial)
  COST_BPS <- 0.0015  # 15bps one-way
  w_str_lag <- c(1.0, head(w$w_str, -1))  # initial w_str=1.0 for cost on first transition
  delta_w <- abs(w$w_str - w_str_lag)
  cost_seq <- COST_BPS * delta_w   # net additional cost at sleeve transition

  # str_ret aligned: rows 2..268 (execution_date) paired with weights rows 1..267
  exec_dates <- str_ret$date[2:nrow(str_ret)]
  ret_str_aligned <- str_ret$ret_net[2:nrow(str_ret)]
  ret_str_gross_aligned <- str_ret$ret_gross[2:nrow(str_ret)]

  ret_eff_net <- w$w_str * ret_str_aligned - cost_seq
  ret_eff_gross <- w$w_str * ret_str_gross_aligned  # gross excludes our overlay cost
  ## cost_ret = ret_gross - ret_net (Backtest Contract v1.0 Check 12 invariant)
  ## breakdown: STR_1715 internal cost (proportional to w_str) + sleeve-overlay cost
  cost_ret_full <- ret_eff_gross - ret_eff_net

  # Build period_returns table directly (frequency=monthly)
  pr_dt <- data.table(
    run_id = run_id,
    strategy_id = strategy_name,
    date = exec_dates,
    frequency = "monthly",
    ret_gross = ret_eff_gross,
    ret_net = ret_eff_net,
    risk_free_ret = 0,
    excess_ret_net = ret_eff_net,
    turnover = delta_w,  # sleeve-level weight transition magnitude (signal turnover)
    cost_ret = cost_ret_full,
    cash_weight = w$w_cash,
    leverage = 1,
    n_holdings = 20L  # STR_1715 internal top20 inherited
  )

  # Build NAV table (from period_returns_net)
  ret_xts <- xts(pr_dt$ret_net, order.by = pr_dt$date)
  ret_gross_xts <- xts(pr_dt$ret_gross, order.by = pr_dt$date)
  nav_net <- as.numeric(cumprod(1 + pr_dt$ret_net))
  nav_gross <- as.numeric(cumprod(1 + pr_dt$ret_gross))

  nav_dt <- data.table(
    run_id = run_id,
    strategy_id = strategy_name,
    date = exec_dates,
    nav_gross = nav_gross,
    nav_net = nav_net,
    cash_weight = w$w_cash,
    gross_exposure = w$w_str,
    net_exposure = w$w_str,
    leverage = 1,
    cum_cost = nav_gross - nav_net,
    drawdown_net = nav_net / cummax(nav_net) - 1,
    is_rebalance_date = TRUE
  )

  # Build benchmark_returns table (filter same exec_dates)
  bm_dt <- bm_ret[date %in% exec_dates,
    .(benchmark_id, benchmark_name, date, frequency,
      benchmark_ret, benchmark_nav,
      risk_free_ret = 0, benchmark_excess_ret = benchmark_ret)]

  # Build manifest
  manifest_dt <- data.table(
    run_id = run_id,
    strategy_id = strategy_name,
    strategy_version = "WT-S20260504_003_v1",
    run_datetime = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00"),
    start_date = as.character(min(exec_dates)),
    end_date = as.character(max(exec_dates)),
    frequency = "monthly",
    rebalance_rule = "monthly_signal_t_apply_to_t+1_execution",
    universe_id = "KOSPI200_KOSDAQ150_intersection",
    benchmark_ids = "KOSPI200",
    transaction_cost_bps = 15,
    slippage_bps = 0,
    risk_free_rate_source = "0",
    data_snapshot_id = format(Sys.Date(), "snapshot_%Y%m%d"),
    code_version = "wt_s20260504_003_forge_v1",
    created_by_agent = "forge",
    integrity_status = "PENDING"
  )

  # Build strategy_spec table (1-row)
  spec_dt <- data.table(
    run_id = run_id,
    strategy_id = strategy_name,
    strategy_name = strategy_name,
    strategy_family = "HMM_Regime_Sizing_Overlay",
    signal_description = sprintf("STR_1715 PG2 base alpha (top20) × %s overlay",
      strategy_name),
    universe_rule = "KOSPI200_KOSDAQ150_intersection_LIQ_2E8",
    rebalance_frequency = "monthly",
    signal_date_rule = "month_start",
    execution_date_rule = "next_month_first_trading_day",
    weighting_method = "INHERITED_STR_1715_internal + sleeve_overlay",
    max_position_weight = 0.20,
    max_leverage = 1,
    cash_rule = switch(strategy_name,
      "S1" = "w_cash = 0 always",
      "HMM_Scale" = "w_cash = 1 - scale_HMM_walkforward (PIT-clean; pre-2009-03 default 1.0)",
      "M4+HMM_Scale" = "w_cash = max(M4_parent_cash, 1 - scale_HMM_walkforward) — canonical max-rule"
    ),
    cost_model = "v2.3_kr_retail_15bps",
    missing_data_rule = "NA → 0 return",
    risk_controls = "long_only + sigma_w=1 + max_per_name=0.20 (inherited)",
    lookahead_prevention = "C1-C15 enforced; signal_date < execution_date; HMM walk-forward only",
    survivorship_bias_control = "INHERITED_FROM_STR_1715 (parent universe rule)"
  )

  # Build holdings table (synthetic — sleeve-level, not stock-level)
  # We do NOT have access to STR_1715 daily/monthly holdings at the sleeve level
  # (stock-level inherited from parent — see 04_holdings.csv reference).
  # For audit purposes we generate a single "STR_1715_sleeve" pseudo-ticker entry per date.
  holdings_dt <- data.table(
    run_id = run_id,
    strategy_id = strategy_name,
    date = exec_dates,
    ticker = "STR_1715_sleeve",
    name = "STR_1715 sleeve aggregate",
    sector = "MULTI",
    target_weight = w$w_str,
    actual_weight = w$w_str,
    price = NA_real_,
    shares = NA_real_,
    market_value = NA_real_,
    signal_score = NA_real_,
    rank = 1L,
    entry_date = as.Date(NA),
    holding_period = NA_integer_,
    is_new_position = FALSE,
    is_exiting_position = FALSE
  )

  # Build metrics manually (frequency=monthly, annualization_factor=12)
  ann_factor <- 12
  excess_xts <- xts(pr_dt$excess_ret_net, order.by = pr_dt$date)

  ann_vol <- sd(as.numeric(ret_xts), na.rm = TRUE) * sqrt(ann_factor)
  total_ret <- as.numeric(Return.cumulative(ret_xts))
  cagr_v <- (tail(nav_net, 1) / 1)^(ann_factor / length(nav_net)) - 1
  ds_vol <- as.numeric(DownsideDeviation(ret_xts, MAR = 0)) * sqrt(ann_factor)

  var95 <- as.numeric(quantile(as.numeric(ret_xts), 0.05, na.rm = TRUE))
  var99 <- as.numeric(quantile(as.numeric(ret_xts), 0.01, na.rm = TRUE))
  cvar95 <- mean(as.numeric(ret_xts)[as.numeric(ret_xts) <= var95], na.rm = TRUE)
  cvar99 <- mean(as.numeric(ret_xts)[as.numeric(ret_xts) <= var99], na.rm = TRUE)

  sr_v <- mean(as.numeric(excess_xts), na.rm = TRUE) /
          sd(as.numeric(excess_xts), na.rm = TRUE) * sqrt(ann_factor)
  sortino_v <- as.numeric(SortinoRatio(ret_xts, MAR = 0)) * sqrt(ann_factor)
  mdd_v <- as.numeric(maxDrawdown(ret_xts))
  calmar_v <- if (mdd_v > 0) cagr_v / mdd_v else NA_real_

  add_metric_row <- function(grp, nm, val, unit, src, mthd, mtype = "backtested") {
    data.table(
      run_id = run_id, strategy_id = strategy_name,
      metric_group = grp, metric_name = nm,
      metric_value = as.numeric(val), metric_unit = unit,
      period_start = min(exec_dates), period_end = max(exec_dates),
      frequency = "monthly", return_type = "net",
      annualization_factor = ann_factor,
      observation_count = length(ret_xts),
      metric_type = mtype, input_source = src,
      calculation_method = mthd, is_official = TRUE
    )
  }

  metrics_list <- list(
    add_metric_row("return", "Total_Return", total_ret, "ratio", "period_returns", "PerformanceAnalytics::Return.cumulative"),
    add_metric_row("return", "CAGR", cagr_v, "ratio", "nav", "(Final/1)^(12/n)-1"),
    add_metric_row("return", "Best_Period_Return", max(ret_xts, na.rm = TRUE), "ratio", "period_returns", "max(ret_net)"),
    add_metric_row("return", "Worst_Period_Return", min(ret_xts, na.rm = TRUE), "ratio", "period_returns", "min(ret_net)"),
    add_metric_row("return", "Positive_Period_Ratio", mean(as.numeric(ret_xts) > 0, na.rm = TRUE), "ratio", "period_returns", "mean(ret_net>0)"),
    add_metric_row("risk", "Annualized_Volatility", ann_vol, "ratio", "period_returns", "sd(ret_net)*sqrt(12)"),
    add_metric_row("risk", "Downside_Volatility", ds_vol, "ratio", "period_returns", "PerformanceAnalytics::DownsideDeviation"),
    add_metric_row("risk", "VaR_95", var95, "ratio", "period_returns", "quantile(ret,0.05)"),
    add_metric_row("risk", "VaR_99", var99, "ratio", "period_returns", "quantile(ret,0.01)"),
    add_metric_row("risk", "CVaR_95", cvar95, "ratio", "period_returns", "mean(ret<=VaR_95)"),
    add_metric_row("risk", "CVaR_99", cvar99, "ratio", "period_returns", "mean(ret<=VaR_99)"),
    add_metric_row("risk", "Skewness", as.numeric(skewness(ret_xts)), "ratio", "period_returns", "PerformanceAnalytics::skewness"),
    add_metric_row("risk", "Kurtosis", as.numeric(kurtosis(ret_xts)), "ratio", "period_returns", "PerformanceAnalytics::kurtosis"),
    add_metric_row("risk_adjusted", "Sharpe", sr_v, "ratio", "period_returns", "mean(ER)/sd(ER)*sqrt(12) [Charter v1.4 §12]"),
    add_metric_row("risk_adjusted", "Sortino", sortino_v, "ratio", "period_returns", "PerformanceAnalytics::SortinoRatio (annualized)"),
    add_metric_row("risk_adjusted", "Calmar", calmar_v, "ratio", "nav", "CAGR/abs(MDD)"),
    add_metric_row("risk_adjusted", "Return_to_CVaR", if (!is.na(cvar99) && cvar99 < 0) cagr_v / abs(cvar99) else NA_real_, "ratio", "period_returns", "CAGR/|CVaR_99|"),
    add_metric_row("drawdown", "MDD", mdd_v, "ratio", "nav", "PerformanceAnalytics::maxDrawdown")
  )

  # DD table
  dd_table <- tryCatch(table.Drawdowns(ret_xts, top = 100), error = function(e) NULL)
  if (!is.null(dd_table) && nrow(dd_table) > 0) {
    metrics_list <- c(metrics_list, list(
      add_metric_row("drawdown", "Max_DD_Duration_Months", max(dd_table$Length, na.rm = TRUE), "months", "drawdowns", "table.Drawdowns"),
      add_metric_row("drawdown", "Average_Drawdown", mean(dd_table$Depth, na.rm = TRUE), "ratio", "drawdowns", "mean(Depth)"),
      add_metric_row("drawdown", "Average_Recovery_Months", mean(dd_table$Recovery, na.rm = TRUE), "months", "drawdowns", "mean(Recovery)")
    ))
  }

  metrics_list <- c(metrics_list, list(
    add_metric_row("exposure", "Average_Turnover", mean(pr_dt$turnover, na.rm = TRUE), "ratio", "period_returns", "mean(|Δw_str|)"),
    add_metric_row("exposure", "Annualized_Turnover", mean(pr_dt$turnover, na.rm = TRUE) * 12, "ratio", "period_returns", "mean(|Δw_str|)*12"),
    add_metric_row("exposure", "Average_N_Holdings", 20, "count", "holdings", "STR_1715 internal top20"),
    add_metric_row("exposure", "Average_Cash_Weight", mean(w$w_cash, na.rm = TRUE), "ratio", "period_returns", "mean(w_cash)"),
    add_metric_row("exposure", "Average_Leverage", 1, "ratio", "period_returns", "mean(leverage)")
  ))

  metrics_dt <- rbindlist(metrics_list, use.names = TRUE, fill = TRUE)

  # benchmark_compare
  cmp <- merge(pr_dt[, .(date, ret_net)],
               bm_dt[, .(date, benchmark_ret)],
               by = "date")
  if (nrow(cmp) > 0) {
    cmp[, active := ret_net - benchmark_ret]
    s_xts <- xts(cmp$ret_net, order.by = cmp$date)
    b_xts <- xts(cmp$benchmark_ret, order.by = cmp$date)
    beta_v <- as.numeric(CAPM.beta(s_xts, b_xts, Rf = 0))
    alpha_v <- as.numeric(CAPM.alpha(s_xts, b_xts, Rf = 0)) * 12
    cor_v <- as.numeric(cor(cmp$ret_net, cmp$benchmark_ret))
    ir_v <- mean(cmp$active, na.rm = TRUE) / sd(cmp$active, na.rm = TRUE) * sqrt(12)
    te_v <- sd(cmp$active, na.rm = TRUE) * sqrt(12)
    up_cap <- as.numeric(UpDownRatios(s_xts, b_xts, method = "Capture", side = "Up"))
    dn_cap <- as.numeric(UpDownRatios(s_xts, b_xts, method = "Capture", side = "Down"))
    hit_v <- mean(cmp$ret_net > cmp$benchmark_ret, na.rm = TRUE)

    cum_s <- prod(1 + cmp$ret_net) - 1
    cum_b <- prod(1 + cmp$benchmark_ret) - 1

    bc_rows <- list(
      list("Excess_Total_Return", cum_s, cum_b, cum_s - cum_b, "ratio"),
      list("Active_Return_Mean", mean(cmp$ret_net), mean(cmp$benchmark_ret), mean(cmp$active), "ratio"),
      list("Tracking_Error", NA, NA, te_v, "ratio"),
      list("Information_Ratio", NA, NA, ir_v, "ratio"),
      list("Beta_to_Benchmark", beta_v, 1, beta_v - 1, "ratio"),
      list("Alpha_Annualized", alpha_v, 0, alpha_v, "ratio"),
      list("Correlation", cor_v, 1, cor_v - 1, "ratio"),
      list("Up_Capture", up_cap, 1, up_cap - 1, "ratio"),
      list("Down_Capture", dn_cap, 1, dn_cap - 1, "ratio"),
      list("Hit_Ratio_vs_BM", hit_v, 0.5, hit_v - 0.5, "ratio")
    )
    bc_dt <- rbindlist(lapply(bc_rows, function(r) {
      data.table(
        run_id = run_id, strategy_id = strategy_name, benchmark_id = bm_dt$benchmark_id[1],
        period_start = min(cmp$date), period_end = max(cmp$date),
        frequency = "monthly",
        metric_name = r[[1]],
        strategy_value = r[[2]], benchmark_value = r[[3]], active_value = r[[4]],
        metric_unit = r[[5]], observation_count = nrow(cmp)
      )
    }))
  } else {
    bc_dt <- data.table()
  }

  # rolling metrics (3M/6M/12M/36M)
  rolling_list <- list()
  for (w_n in c(3, 6, 12, 36)) {
    if (w_n >= length(ret_xts)) next
    rs <- rollapply(ret_xts, width = w_n, FUN = function(x) {
      if (sd(x, na.rm = TRUE) == 0 || length(x) == 0) return(NA)
      mean(x, na.rm = TRUE) / sd(x, na.rm = TRUE) * sqrt(12)
    }, fill = NA, align = "right")
    rs_dt <- data.table(date = as.Date(index(rs)),
      metric_name = sprintf("Rolling_Sharpe_%dM", w_n),
      metric_value = as.numeric(rs))[!is.na(metric_value)]
    if (nrow(rs_dt) > 0) {
      rs_dt[, run_id := run_id][, strategy_id := strategy_name]
      rs_dt[, benchmark_id := bm_dt$benchmark_id[1]][, window := sprintf("%dM", w_n)]
      rs_dt[, return_type := "net"][, observation_count := w_n]
      rolling_list[[length(rolling_list) + 1]] <- rs_dt
    }

    rm_x <- rollapply(ret_xts, width = w_n, FUN = function(x) {
      tryCatch(as.numeric(maxDrawdown(x)), error = function(e) NA)
    }, fill = NA, align = "right")
    rm_dt <- data.table(date = as.Date(index(rm_x)),
      metric_name = sprintf("Rolling_MDD_%dM", w_n),
      metric_value = as.numeric(rm_x))[!is.na(metric_value)]
    if (nrow(rm_dt) > 0) {
      rm_dt[, run_id := run_id][, strategy_id := strategy_name]
      rm_dt[, benchmark_id := bm_dt$benchmark_id[1]][, window := sprintf("%dM", w_n)]
      rm_dt[, return_type := "net"][, observation_count := w_n]
      rolling_list[[length(rolling_list) + 1]] <- rm_dt
    }
  }
  rolling_dt <- if (length(rolling_list) > 0) rbindlist(rolling_list, fill = TRUE) else data.table()

  # drawdowns table
  if (!is.null(dd_table) && nrow(dd_table) > 0) {
    dd_dt <- data.table(
      run_id = run_id, strategy_id = strategy_name,
      drawdown_id = seq_len(nrow(dd_table)),
      peak_date = as.Date(dd_table$From),
      trough_date = as.Date(dd_table$Trough),
      recovery_date = as.Date(dd_table$To),
      drawdown_depth = as.numeric(dd_table$Depth),
      drawdown_length = as.integer(dd_table$Length),
      recovery_length = as.integer(dd_table$Recovery),
      total_underwater_period = as.integer(dd_table$Length),
      benchmark_drawdown_depth = NA_real_,
      relative_drawdown = NA_real_
    )
  } else {
    dd_dt <- data.table()
  }

  # audit (placeholder — populated later by audit_bt_result)
  audit_dt <- data.table()

  bt_result <- list(
    manifest = manifest_dt,
    strategy_spec = spec_dt,
    nav = nav_dt,
    period_returns = pr_dt,
    holdings = holdings_dt,
    benchmark_returns = bm_dt,
    metrics = metrics_dt,
    benchmark_compare = bc_dt,
    rolling_metrics = rolling_dt,
    drawdowns = dd_dt,
    audit = audit_dt
  )
  class(bt_result) <- c("bt_result", "list")

  # Run audit
  bt_result <- audit_bt_result(bt_result)

  cat(sprintf("  SR=%.4f CAGR=%.4f MDD=%.4f Vol=%.4f Sortino=%.4f Calmar=%.4f\n",
    sr_v, cagr_v, mdd_v, ann_vol, sortino_v, calmar_v))
  cat(sprintf("  Avg cash=%.4f, Annual TO=%.4f, audit=%s\n",
    mean(w$w_cash), mean(pr_dt$turnover, na.rm = TRUE) * 12,
    bt_result$manifest$integrity_status))

  bt_result
}

## --- 7. Run 3 strategies -----------------------------------------------------
RUN_TS <- format(Sys.time(), "%Y%m%d_%H%M%S")

bt_S1 <- run_strategy(
  file.path(STAGE_DIR, "weights_variants/S1.csv"),
  "S1",
  paste0("WT-S20260504_003_S1_", RUN_TS)
)

bt_HMM <- run_strategy(
  file.path(STAGE_DIR, "weights_variants/HMM_Scale.csv"),
  "HMM_Scale",
  paste0("WT-S20260504_003_HMMScale_", RUN_TS)
)

bt_M4HMM <- run_strategy(
  file.path(STAGE_DIR, "weights.csv"),  # canonical
  "M4+HMM_Scale",
  paste0("WT-S20260504_003_M4HMM_", RUN_TS)
)

## --- 8. Save bt_result.rds ---------------------------------------------------
saveRDS(bt_S1,    file.path(STAGE_DIR, "bt_result_S1.rds"))
saveRDS(bt_HMM,   file.path(STAGE_DIR, "bt_result_HMM_Scale.rds"))
saveRDS(bt_M4HMM, file.path(STAGE_DIR, "bt_result_M4+HMM_Scale.rds"))
saveRDS(bt_M4HMM, file.path(STAGE_DIR, "bt_result.rds"))  # canonical
cat(sprintf("\n[saved] bt_result_*.rds  (canonical = M4+HMM_Scale)\n"))

## --- 9. Save bt_result CSVs (10-component) for canonical ---------------------
out_csv_dir <- file.path(OUT_DIR)
fwrite(bt_M4HMM$manifest,          file.path(out_csv_dir, "00_manifest.csv"))
fwrite(bt_M4HMM$strategy_spec,     file.path(out_csv_dir, "01_strategy_spec.csv"))
fwrite(bt_M4HMM$nav,               file.path(out_csv_dir, "02_nav.csv"))
fwrite(bt_M4HMM$period_returns,    file.path(out_csv_dir, "03_period_returns.csv"))
fwrite(bt_M4HMM$holdings,          file.path(out_csv_dir, "04_holdings.csv"))
fwrite(bt_M4HMM$benchmark_returns, file.path(out_csv_dir, "05_benchmark_returns.csv"))
fwrite(bt_M4HMM$metrics,           file.path(out_csv_dir, "06_metrics.csv"))
fwrite(bt_M4HMM$benchmark_compare, file.path(out_csv_dir, "07_benchmark_compare.csv"))
fwrite(bt_M4HMM$rolling_metrics,   file.path(out_csv_dir, "08_rolling_metrics.csv"))
fwrite(bt_M4HMM$drawdowns,         file.path(out_csv_dir, "09_drawdowns.csv"))
fwrite(bt_M4HMM$audit,             file.path(out_csv_dir, "10_audit.csv"))
cat(sprintf("[saved] 10-component CSVs to %s/\n", out_csv_dir))

## --- 10. lro_backtest_returns.csv (3-strategy 268m) --------------------------
lro_returns <- merge(
  bt_S1$period_returns[, .(date, S1 = ret_net)],
  bt_HMM$period_returns[, .(date, HMM_Scale = ret_net)], by = "date")
lro_returns <- merge(lro_returns,
  bt_M4HMM$period_returns[, .(date, `M4+HMM_Scale` = ret_net)], by = "date")
fwrite(lro_returns, file.path(STAGE_DIR, "lro_backtest_returns.csv"))
cat(sprintf("[saved] lro_backtest_returns.csv (%d rows)\n", nrow(lro_returns)))

## --- 11. lro_performance_summary.csv (3 strategies × metrics) ----------------
extract_metric <- function(bt, name) {
  v <- bt$metrics[metric_name == name, metric_value]
  if (length(v) == 0) return(NA_real_)
  v[1]
}

perf_summary <- data.table(
  strategy = c("S1", "HMM_Scale", "M4+HMM_Scale"),
  CAGR = c(extract_metric(bt_S1, "CAGR"),
           extract_metric(bt_HMM, "CAGR"),
           extract_metric(bt_M4HMM, "CAGR")),
  Sharpe = c(extract_metric(bt_S1, "Sharpe"),
             extract_metric(bt_HMM, "Sharpe"),
             extract_metric(bt_M4HMM, "Sharpe")),
  Sortino = c(extract_metric(bt_S1, "Sortino"),
              extract_metric(bt_HMM, "Sortino"),
              extract_metric(bt_M4HMM, "Sortino")),
  Calmar = c(extract_metric(bt_S1, "Calmar"),
             extract_metric(bt_HMM, "Calmar"),
             extract_metric(bt_M4HMM, "Calmar")),
  MDD = c(extract_metric(bt_S1, "MDD"),
          extract_metric(bt_HMM, "MDD"),
          extract_metric(bt_M4HMM, "MDD")),
  Ann_Vol = c(extract_metric(bt_S1, "Annualized_Volatility"),
              extract_metric(bt_HMM, "Annualized_Volatility"),
              extract_metric(bt_M4HMM, "Annualized_Volatility")),
  Downside_Vol = c(extract_metric(bt_S1, "Downside_Volatility"),
                   extract_metric(bt_HMM, "Downside_Volatility"),
                   extract_metric(bt_M4HMM, "Downside_Volatility")),
  CVaR_95 = c(extract_metric(bt_S1, "CVaR_95"),
              extract_metric(bt_HMM, "CVaR_95"),
              extract_metric(bt_M4HMM, "CVaR_95")),
  CVaR_99 = c(extract_metric(bt_S1, "CVaR_99"),
              extract_metric(bt_HMM, "CVaR_99"),
              extract_metric(bt_M4HMM, "CVaR_99")),
  VaR_95 = c(extract_metric(bt_S1, "VaR_95"),
             extract_metric(bt_HMM, "VaR_95"),
             extract_metric(bt_M4HMM, "VaR_95")),
  VaR_99 = c(extract_metric(bt_S1, "VaR_99"),
             extract_metric(bt_HMM, "VaR_99"),
             extract_metric(bt_M4HMM, "VaR_99")),
  Skewness = c(extract_metric(bt_S1, "Skewness"),
               extract_metric(bt_HMM, "Skewness"),
               extract_metric(bt_M4HMM, "Skewness")),
  Kurtosis = c(extract_metric(bt_S1, "Kurtosis"),
               extract_metric(bt_HMM, "Kurtosis"),
               extract_metric(bt_M4HMM, "Kurtosis")),
  Annual_Turnover = c(extract_metric(bt_S1, "Annualized_Turnover"),
                      extract_metric(bt_HMM, "Annualized_Turnover"),
                      extract_metric(bt_M4HMM, "Annualized_Turnover")),
  Avg_Cash = c(extract_metric(bt_S1, "Average_Cash_Weight"),
               extract_metric(bt_HMM, "Average_Cash_Weight"),
               extract_metric(bt_M4HMM, "Average_Cash_Weight")),
  Total_Return = c(extract_metric(bt_S1, "Total_Return"),
                   extract_metric(bt_HMM, "Total_Return"),
                   extract_metric(bt_M4HMM, "Total_Return")),
  Max_DD_Months = c(extract_metric(bt_S1, "Max_DD_Duration_Months"),
                    extract_metric(bt_HMM, "Max_DD_Duration_Months"),
                    extract_metric(bt_M4HMM, "Max_DD_Duration_Months")),
  audit_status = c(bt_S1$manifest$integrity_status,
                   bt_HMM$manifest$integrity_status,
                   bt_M4HMM$manifest$integrity_status)
)
fwrite(perf_summary, file.path(STAGE_DIR, "lro_performance_summary.csv"))
cat("\n[lro_performance_summary]\n"); print(perf_summary)

## --- 12. Cross-validation slices --------------------------------------------
##
## a) ex-2025 OOS (period excluding 2025-2026) — pre-2025 PIT-clean OOS slice
## b) ex-Semi (universe) — N/A (we don't have stock-level returns)
## c) ex-Samsung/Hynix — N/A (sleeve-level)
## d) sector-neutral — N/A (sleeve-level)
## We perform: (a) pre-LB cutoff slice + (e) post-LB OOS slice
## + crisis-state SR per HMM regime label

## (a) pre-2024 (lookback frozen) slice
cutoff_LB <- as.Date("2024-01-01")
pre_LB_metrics <- function(bt) {
  pr <- bt$period_returns[date < cutoff_LB]
  if (nrow(pr) < 12) return(list(SR = NA, CAGR = NA, MDD = NA, n = nrow(pr)))
  rx <- xts(pr$ret_net, order.by = pr$date)
  navp <- as.numeric(cumprod(1 + pr$ret_net))
  cagr <- (tail(navp, 1) / 1)^(12 / length(navp)) - 1
  list(
    SR = mean(pr$ret_net, na.rm = TRUE) / sd(pr$ret_net, na.rm = TRUE) * sqrt(12),
    CAGR = cagr,
    MDD = as.numeric(maxDrawdown(rx)),
    n = nrow(pr)
  )
}
post_LB_metrics <- function(bt) {
  pr <- bt$period_returns[date >= cutoff_LB]
  if (nrow(pr) < 6) return(list(SR = NA, CAGR = NA, MDD = NA, n = nrow(pr)))
  rx <- xts(pr$ret_net, order.by = pr$date)
  navp <- as.numeric(cumprod(1 + pr$ret_net))
  cagr <- (tail(navp, 1) / 1)^(12 / length(navp)) - 1
  list(
    SR = mean(pr$ret_net, na.rm = TRUE) / sd(pr$ret_net, na.rm = TRUE) * sqrt(12),
    CAGR = cagr,
    MDD = as.numeric(maxDrawdown(rx)),
    n = nrow(pr)
  )
}

slice_summary <- list(
  S1 = list(pre_LB = pre_LB_metrics(bt_S1), post_LB = post_LB_metrics(bt_S1)),
  HMM_Scale = list(pre_LB = pre_LB_metrics(bt_HMM), post_LB = post_LB_metrics(bt_HMM)),
  `M4+HMM_Scale` = list(pre_LB = pre_LB_metrics(bt_M4HMM), post_LB = post_LB_metrics(bt_M4HMM))
)

## (b) HMM regime-state forward vol (Crisis vs Normal vol ratio per state)
## Match exec_dates with HMM walkforward predicted state
## NOTE: weights signal_dates (1st of month) vs str_ret exec_dates (next-month execution).
## hmm_wf$date is signal_date convention. Map: hmm_wf row i ↔ str_ret row i+1.
hmm_match <- hmm_wf[, .(signal_date = as.Date(date),
                         regime_state = most_likely_predicted,
                         scale = scale_predicted)]
## Build a date-shifted join key: each hmm row aligns with NEXT month's exec_date
hmm_match[, exec_date := str_ret$date[match(signal_date, c(NA, head(str_ret$date, -1)))]]
## Simpler: weights w$signal_date[i] applies to str_ret$date[i+1].
## We set exec_date_i = str_ret$date[match(signal_date_i, weights$signal_date) + 1]
## but easier: just shift hmm_match by 1 row to align with exec_dates.
setorder(hmm_match, signal_date)
hmm_match[, exec_date := c(tail(str_ret$date, -1), NA)[match(signal_date, head(str_ret$date, -1))]]
## Clean fallback if NA: use signal_date as approx
hmm_match[is.na(exec_date), exec_date := signal_date]
regime_perf <- list()
for (sname in c("S1", "HMM_Scale", "M4+HMM_Scale")) {
  bt <- switch(sname, "S1" = bt_S1, "HMM_Scale" = bt_HMM, "M4+HMM_Scale" = bt_M4HMM)
  pr <- bt$period_returns[, .(date, ret_net)]
  joined <- merge(pr, hmm_match[, .(date = exec_date, regime_state)], by = "date", all.x = TRUE)
  for (st in c("Normal", "Caution", "Crisis")) {
    sub <- joined[regime_state == st & !is.na(ret_net)]
    if (nrow(sub) >= 6) {
      regime_perf[[length(regime_perf) + 1]] <- data.table(
        strategy = sname,
        regime = st,
        n_obs = nrow(sub),
        mean_ret = mean(sub$ret_net),
        vol_ann = sd(sub$ret_net) * sqrt(12),
        SR = mean(sub$ret_net) / sd(sub$ret_net) * sqrt(12),
        next3M_realized_vol_ann = NA_real_  # forward not available within slice
      )
    }
  }
}
regime_perf_dt <- rbindlist(regime_perf, fill = TRUE)
fwrite(regime_perf_dt, file.path(STAGE_DIR, "lro_regime_state_performance.csv"))
cat("\n[regime_perf]\n"); print(regime_perf_dt)

## (c) crisis-state forward vol comparison: 2008-09 ~ 2009-08, 2020-02 ~ 2020-04
crisis_periods <- list(
  GFC_2008 = c(as.Date("2008-09-01"), as.Date("2009-08-01")),
  COVID_2020 = c(as.Date("2020-02-01"), as.Date("2020-04-30")),
  Rate_2022 = c(as.Date("2022-08-01"), as.Date("2022-12-31"))
)
crisis_perf <- list()
for (sname in c("S1", "HMM_Scale", "M4+HMM_Scale")) {
  bt <- switch(sname, "S1" = bt_S1, "HMM_Scale" = bt_HMM, "M4+HMM_Scale" = bt_M4HMM)
  for (cn in names(crisis_periods)) {
    rng <- crisis_periods[[cn]]
    sub <- bt$period_returns[date >= rng[1] & date <= rng[2]]
    if (nrow(sub) >= 2) {
      crisis_perf[[length(crisis_perf) + 1]] <- data.table(
        strategy = sname, crisis = cn, n_obs = nrow(sub),
        cum_ret = prod(1 + sub$ret_net) - 1,
        max_dd = as.numeric(maxDrawdown(xts(sub$ret_net, order.by = sub$date))),
        vol_ann = sd(sub$ret_net) * sqrt(12)
      )
    }
  }
}
crisis_perf_dt <- rbindlist(crisis_perf, fill = TRUE)
fwrite(crisis_perf_dt, file.path(STAGE_DIR, "lro_crisis_period_performance.csv"))
cat("\n[crisis_perf]\n"); print(crisis_perf_dt)

## --- 13. Top-5 drawdowns table ----------------------------------------------
top5_dd <- list()
for (sname in c("S1", "HMM_Scale", "M4+HMM_Scale")) {
  bt <- switch(sname, "S1" = bt_S1, "HMM_Scale" = bt_HMM, "M4+HMM_Scale" = bt_M4HMM)
  dd <- bt$drawdowns
  if (nrow(dd) >= 1) {
    top <- head(dd[order(drawdown_depth)], 5)
    top[, strategy := sname]
    top5_dd[[sname]] <- top
  }
}
top5_dd_dt <- rbindlist(top5_dd, fill = TRUE)
fwrite(top5_dd_dt, file.path(STAGE_DIR, "lro_top5_drawdowns.csv"))
cat("\n[top5_dd]\n"); print(top5_dd_dt)

## --- 14. equity_curve.png ---------------------------------------------------
png_path <- file.path(OUT_DIR, "equity_curve.png")
png(png_path, width = 1400, height = 800)
par(mfrow = c(2, 1), mar = c(4, 4, 3, 1))
plot(bt_S1$nav$date, bt_S1$nav$nav_net, type = "l", lwd = 2, col = "black",
  log = "y", xlab = "Date", ylab = "NAV (log)", main = "WT-S20260504_003 — 3-Strategy Equity Curve")
lines(bt_HMM$nav$date, bt_HMM$nav$nav_net, lwd = 2, col = "blue")
lines(bt_M4HMM$nav$date, bt_M4HMM$nav$nav_net, lwd = 2, col = "red")
abline(v = cutoff_LB, col = "gray", lty = 2)
legend("topleft",
  legend = c("S1 baseline", "HMM_Scale", "M4+HMM_Scale (canonical)"),
  col = c("black", "blue", "red"), lwd = 2)

## drawdown panel
plot(bt_S1$nav$date, bt_S1$nav$drawdown_net, type = "l", lwd = 2, col = "black",
  xlab = "Date", ylab = "Drawdown", main = "Drawdown comparison")
lines(bt_HMM$nav$date, bt_HMM$nav$drawdown_net, lwd = 2, col = "blue")
lines(bt_M4HMM$nav$date, bt_M4HMM$nav$drawdown_net, lwd = 2, col = "red")
abline(h = 0, col = "gray")
abline(v = cutoff_LB, col = "gray", lty = 2)
dev.off()
cat(sprintf("[saved] %s\n", png_path))

## --- 15. annual_returns.png -------------------------------------------------
ann_path <- file.path(OUT_DIR, "annual_returns.png")
png(ann_path, width = 1400, height = 800)
yearly_ret <- function(bt) {
  pr <- bt$period_returns
  pr[, year := format(date, "%Y")]
  pr[, .(annual_ret = prod(1 + ret_net) - 1), by = year]
}
y_S1 <- yearly_ret(bt_S1); y_S1[, strat := "S1"]
y_HMM <- yearly_ret(bt_HMM); y_HMM[, strat := "HMM_Scale"]
y_M4HMM <- yearly_ret(bt_M4HMM); y_M4HMM[, strat := "M4+HMM_Scale"]
y_all <- rbind(y_S1, y_HMM, y_M4HMM)
y_w <- dcast(y_all, year ~ strat, value.var = "annual_ret")
y_mat <- as.matrix(y_w[, !"year"])
rownames(y_mat) <- y_w$year
barplot(t(y_mat), beside = TRUE,
  col = c("black", "blue", "red"),
  legend.text = c("S1", "HMM_Scale", "M4+HMM_Scale"),
  main = "Annual returns by strategy",
  ylab = "Annual return", xlab = "Year",
  args.legend = list(x = "topleft"))
abline(h = 0)
dev.off()
cat(sprintf("[saved] %s\n", ann_path))

## --- 16. oos_zoom_chart.png (post-LB cutoff zoom) ---------------------------
oos_path <- file.path(OUT_DIR, "oos_zoom_chart.png")
png(oos_path, width = 1400, height = 800)
oos_S1 <- bt_S1$nav[date >= cutoff_LB]
oos_HMM <- bt_HMM$nav[date >= cutoff_LB]
oos_M4HMM <- bt_M4HMM$nav[date >= cutoff_LB]
# Re-base to 1.0 at cutoff
rebase <- function(nav_dt) nav_dt$nav_net / nav_dt$nav_net[1]
plot(oos_S1$date, rebase(oos_S1), type = "l", lwd = 2, col = "black",
  ylim = range(c(rebase(oos_S1), rebase(oos_HMM), rebase(oos_M4HMM))),
  xlab = "Date", ylab = "NAV (rebased to 1.0 at 2024-01-01)",
  main = "OOS zoom (post-2024-01) — 3-strategy comparison")
lines(oos_HMM$date, rebase(oos_HMM), lwd = 2, col = "blue")
lines(oos_M4HMM$date, rebase(oos_M4HMM), lwd = 2, col = "red")
abline(h = 1, col = "gray", lty = 3)
legend("topleft",
  legend = c("S1 baseline", "HMM_Scale", "M4+HMM_Scale"),
  col = c("black", "blue", "red"), lwd = 2)
dev.off()
cat(sprintf("[saved] %s\n", oos_path))

## --- 17. regime_decomposition.png ------------------------------------------
reg_path <- file.path(OUT_DIR, "regime_decomposition.png")
png(reg_path, width = 1400, height = 800)
# regime_perf_dt: strategy / regime / n_obs / mean_ret / vol_ann / SR
if (nrow(regime_perf_dt) > 0) {
  par(mfrow = c(1, 2), mar = c(5, 4, 3, 1))
  # SR bar
  sr_w <- dcast(regime_perf_dt, regime ~ strategy, value.var = "SR")
  sr_mat <- as.matrix(sr_w[, !"regime"])
  rownames(sr_mat) <- sr_w$regime
  barplot(t(sr_mat), beside = TRUE,
    col = c("black", "blue", "red"),
    legend.text = c("S1", "HMM_Scale", "M4+HMM_Scale"),
    main = "SR by HMM regime", ylab = "Sharpe (annualized)",
    args.legend = list(x = "topleft"))
  abline(h = 0)
  # Vol bar
  vol_w <- dcast(regime_perf_dt, regime ~ strategy, value.var = "vol_ann")
  vol_mat <- as.matrix(vol_w[, !"regime"])
  rownames(vol_mat) <- vol_w$regime
  barplot(t(vol_mat), beside = TRUE,
    col = c("black", "blue", "red"),
    legend.text = c("S1", "HMM_Scale", "M4+HMM_Scale"),
    main = "Vol_ann by HMM regime", ylab = "Vol (annualized)",
    args.legend = list(x = "topleft"))
  abline(h = 0)
}
dev.off()
cat(sprintf("[saved] %s\n", reg_path))

## --- 18. Hash check (end) ---------------------------------------------------
end_hashes <- sapply(hash_files, function(f) digest(file = f, algo = "md5"))
names(end_hashes) <- basename(hash_files)
cat("\n[hash-end]\n"); print(end_hashes)

hash_match <- all(start_hashes == end_hashes)
cat(sprintf("\n[hash-integrity] start==end : %s\n", hash_match))
if (!hash_match) {
  cat("[WARN] Hash mismatch detected — Pure Function violation suspected!\n")
  print(data.table(file = names(start_hashes), start = start_hashes, end = end_hashes,
                    match = start_hashes == end_hashes))
}

writeLines(c(
  sprintf("Hash integrity check: %s", if (hash_match) "PASS" else "FAIL"),
  "Start hashes:",
  sprintf("  %s = %s", names(start_hashes), start_hashes),
  "End hashes:",
  sprintf("  %s = %s", names(end_hashes), end_hashes)
), con = file.path(WS_DIR, "hash_integrity_check.txt"))

## --- 19. Slice summary export (ex-2025 + post-LB) ---------------------------
slice_export <- rbindlist(lapply(names(slice_summary), function(s) {
  pre <- slice_summary[[s]]$pre_LB
  post <- slice_summary[[s]]$post_LB
  data.table(
    strategy = s,
    slice_pre_LB_n = pre$n, slice_pre_LB_SR = pre$SR, slice_pre_LB_CAGR = pre$CAGR, slice_pre_LB_MDD = pre$MDD,
    slice_post_LB_n = post$n, slice_post_LB_SR = post$SR, slice_post_LB_CAGR = post$CAGR, slice_post_LB_MDD = post$MDD
  )
}), fill = TRUE)
fwrite(slice_export, file.path(STAGE_DIR, "lro_oos_slices.csv"))
cat("\n[oos_slices]\n"); print(slice_export)

cat("\n=== Forge backtest complete. ===\n")
cat(sprintf("Output dir: %s\n", OUT_DIR))
cat(sprintf("Stage dir: %s\n", STAGE_DIR))

## NOTE: forge_package.json drafting + audit happens after this run completes
## (separate writer step in handoff script).
