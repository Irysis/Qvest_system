## ============================================================================
## Backtest Result Contract v1.0 — Schema + Builder + Validator
## Lawbook: 00_Lawbook/Multi_Agent/backtest_result_contract.md
## 발효: 2026-04-29 (도훈 명시 지침, Session 73)
## 정합: Charter v1.4 §9/§11/§12 + Plan §"백테스트 자체 합성 금지" + 답변 원칙 v1.0
## ============================================================================

suppressMessages({
  library(data.table); library(PerformanceAnalytics); library(xts); library(jsonlite)
})

## ─── 10-Component Schema Definitions ────────────────────────────────────────
BT_RESULT_COMPONENTS <- c(
  "manifest", "strategy_spec", "nav", "period_returns",
  "holdings", "benchmark_returns", "metrics",
  "benchmark_compare", "rolling_metrics", "drawdowns", "audit"
)

MANIFEST_FIELDS <- c(
  "run_id", "strategy_id", "strategy_version", "run_datetime",
  "start_date", "end_date", "frequency", "rebalance_rule",
  "universe_id", "benchmark_ids", "transaction_cost_bps", "slippage_bps",
  "risk_free_rate_source", "data_snapshot_id", "code_version",
  "created_by_agent", "integrity_status"
)

STRATEGY_SPEC_FIELDS <- c(
  "strategy_id", "strategy_name", "strategy_family",
  "signal_description", "universe_rule",
  "rebalance_frequency", "signal_date_rule", "execution_date_rule",
  "weighting_method", "max_position_weight", "max_leverage",
  "cash_rule", "cost_model", "missing_data_rule",
  "risk_controls", "lookahead_prevention", "survivorship_bias_control"
)

NAV_COLS <- c(
  "run_id", "strategy_id", "date",
  "nav_gross", "nav_net", "cash_weight",
  "gross_exposure", "net_exposure", "leverage",
  "cum_cost", "drawdown_net", "is_rebalance_date"
)

PERIOD_RETURNS_COLS <- c(
  "run_id", "strategy_id", "date", "frequency",
  "ret_gross", "ret_net", "risk_free_ret", "excess_ret_net",
  "turnover", "cost_ret",
  "cash_weight", "leverage", "n_holdings"
)

HOLDINGS_COLS <- c(
  "run_id", "strategy_id", "date",
  "ticker", "name", "sector",
  "target_weight", "actual_weight", "price", "shares", "market_value",
  "signal_score", "rank",
  "entry_date", "holding_period",
  "is_new_position", "is_exiting_position"
)

BENCHMARK_RETURNS_COLS <- c(
  "benchmark_id", "benchmark_name", "date", "frequency",
  "benchmark_ret", "benchmark_nav", "risk_free_ret", "benchmark_excess_ret"
)

METRICS_COLS <- c(
  "run_id", "strategy_id",
  "metric_group", "metric_name", "metric_value", "metric_unit",
  "period_start", "period_end", "frequency", "return_type",
  "annualization_factor", "observation_count",
  "metric_type", "input_source", "calculation_method", "is_official"
)

METRIC_TYPE_VALID <- c("backtested", "estimated", "proxy", "unavailable")

BENCHMARK_COMPARE_COLS <- c(
  "run_id", "strategy_id", "benchmark_id",
  "period_start", "period_end", "frequency",
  "metric_name", "strategy_value", "benchmark_value", "active_value",
  "metric_unit", "observation_count"
)

ROLLING_METRICS_COLS <- c(
  "run_id", "strategy_id", "benchmark_id",
  "date", "window", "metric_name", "metric_value",
  "return_type", "observation_count"
)

DRAWDOWNS_COLS <- c(
  "run_id", "strategy_id", "drawdown_id",
  "peak_date", "trough_date", "recovery_date",
  "drawdown_depth", "drawdown_length", "recovery_length",
  "total_underwater_period",
  "benchmark_drawdown_depth", "relative_drawdown"
)

AUDIT_COLS <- c(
  "run_id", "check_group", "check_name", "status",
  "details", "affected_metrics", "severity"
)

AUDIT_CHECKS_10 <- c(
  "realized_return_vector_exists",
  "nav_path_exists",
  "rebalance_path_executed",
  "transaction_cost_param_recorded",
  "benchmark_aligned",
  "risk_free_rate_defined",
  "point_in_time_checked",
  "lookahead_bias_checked",
  "survivorship_bias_checked",
  "estimated_metrics_separated_from_backtested"
)

## ─── Builder Functions ──────────────────────────────────────────────────────

#' Build manifest table
#' @param sim_result list from run_monthly_simulation()
#' @param strategy_spec list with STRATEGY_SPEC_FIELDS
#' @param run_id, strategy_id, etc.
build_manifest <- function(run_id, strategy_id, strategy_version,
                            sim_result, strategy_spec,
                            transaction_cost_bps = 15, slippage_bps = 15,
                            risk_free_rate_source = "0",
                            data_snapshot_id = format(Sys.Date(), "snapshot_%Y%m%d"),
                            code_version = "run_all_v1",
                            created_by_agent = "Q-Lead",
                            universe_id = "KR_TOP342",
                            benchmark_ids = "KOSPI200") {
  nav_dt <- sim_result$DAILY_NAV_DT
  data.table(
    run_id = run_id,
    strategy_id = strategy_id,
    strategy_version = strategy_version,
    run_datetime = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00"),
    start_date = as.character(min(nav_dt$Date)),
    end_date = as.character(max(nav_dt$Date)),
    frequency = strategy_spec$rebalance_frequency %||% "monthly",
    rebalance_rule = strategy_spec$execution_date_rule %||% "month_end_signal_t_plus_1",
    universe_id = universe_id,
    benchmark_ids = benchmark_ids,
    transaction_cost_bps = transaction_cost_bps,
    slippage_bps = slippage_bps,
    risk_free_rate_source = risk_free_rate_source,
    data_snapshot_id = data_snapshot_id,
    code_version = code_version,
    created_by_agent = created_by_agent,
    integrity_status = "PENDING"  # audit 후 갱신
  )
}

#' Build strategy_spec table (input list → data.table)
build_strategy_spec_tbl <- function(spec_list, run_id) {
  spec_dt <- as.data.table(spec_list)
  spec_dt[, run_id := run_id]
  setcolorder(spec_dt, c("run_id", intersect(STRATEGY_SPEC_FIELDS, names(spec_dt))))
  spec_dt
}

#' Build nav table
build_nav <- function(sim_result, run_id, strategy_id) {
  nav_dt <- copy(sim_result$DAILY_NAV_DT)
  if (!"NAV_gross" %in% names(nav_dt)) nav_dt[, NAV_gross := NAV]  # fallback
  setnames(nav_dt, c("NAV_gross", "NAV"), c("nav_gross", "nav_net"), skip_absent = TRUE)

  # cash_weight, exposure, leverage, drawdown은 sim_result에서 derive
  if (!"cash_weight" %in% names(nav_dt)) nav_dt[, cash_weight := 0]
  if (!"gross_exposure" %in% names(nav_dt)) nav_dt[, gross_exposure := 1 - cash_weight]
  if (!"net_exposure" %in% names(nav_dt)) nav_dt[, net_exposure := gross_exposure]
  if (!"leverage" %in% names(nav_dt)) nav_dt[, leverage := gross_exposure]

  # drawdown_net via PerformanceAnalytics-style cummax
  nav_dt[, drawdown_net := nav_net / cummax(nav_net) - 1]

  # cum_cost: nav_gross - nav_net (백테스트 commission 차감 누적)
  if (!"cum_cost" %in% names(nav_dt)) nav_dt[, cum_cost := nav_gross - nav_net]

  # is_rebalance_date
  if (!"is_rebalance_date" %in% names(nav_dt)) nav_dt[, is_rebalance_date := FALSE]
  if (!is.null(sim_result$PORTFOLIO_LOG)) {
    rebal_dates <- as.Date(sim_result$PORTFOLIO_LOG$Exec_Date %||%
                            sim_result$PORTFOLIO_LOG$Signal_Date %||% character(0))
    nav_dt[Date %in% rebal_dates, is_rebalance_date := TRUE]
  }

  nav_dt[, run_id := run_id]
  nav_dt[, strategy_id := strategy_id]
  setnames(nav_dt, "Date", "date", skip_absent = TRUE)

  cols_present <- intersect(NAV_COLS, names(nav_dt))
  nav_dt[, ..cols_present]
}

#' Build period_returns table
#' @param sim_result list
#' @param frequency "daily" or "monthly"
#' @param risk_free_rate scalar or vector
build_period_returns <- function(sim_result, run_id, strategy_id,
                                  frequency = "daily", risk_free_rate = 0,
                                  holdings_for_turnover = NULL) {
  # PerformanceAnalytics 표준 함수만 사용
  ret_xts <- sim_result$strategy_xts

  if (frequency == "monthly") {
    ret_xts <- apply.monthly(ret_xts, Return.cumulative)
  }

  ret_dt <- data.table(
    date = as.Date(index(ret_xts)),
    ret_net = as.numeric(ret_xts)
  )

  # ret_gross: nav_gross에서 산출 (PerformanceAnalytics::CalculateReturns 사용)
  if (!is.null(sim_result$DAILY_NAV_DT$NAV_gross)) {
    nav_g_xts <- xts(sim_result$DAILY_NAV_DT$NAV_gross,
                     order.by = sim_result$DAILY_NAV_DT$Date)
    if (frequency == "monthly") nav_g_xts <- apply.monthly(nav_g_xts, last)
    ret_g <- diff(log(nav_g_xts))
    ret_g[is.na(ret_g)] <- 0
    ret_g <- exp(ret_g) - 1
    ret_g_dt <- data.table(date = as.Date(index(ret_g)), ret_gross = as.numeric(ret_g))
    ret_dt <- merge(ret_dt, ret_g_dt, by = "date", all.x = TRUE)
  } else {
    ret_dt[, ret_gross := ret_net]
  }
  ret_dt[is.na(ret_gross), ret_gross := ret_net]

  # risk_free_ret
  if (length(risk_free_rate) == 1) {
    ret_dt[, risk_free_ret := risk_free_rate]
  } else if (length(risk_free_rate) == nrow(ret_dt)) {
    ret_dt[, risk_free_ret := risk_free_rate]
  } else {
    ret_dt[, risk_free_ret := 0]
  }
  ret_dt[, excess_ret_net := ret_net - risk_free_ret]
  ret_dt[, cost_ret := ret_gross - ret_net]

  # turnover from holdings (if provided + 컬럼명 검증)
  required_h_cols <- c("date", "ticker", "actual_weight")
  if (!is.null(holdings_for_turnover) && nrow(holdings_for_turnover) > 0 &&
      all(required_h_cols %in% names(holdings_for_turnover))) {
    h_wide <- tryCatch({
      dcast(holdings_for_turnover, date ~ ticker,
            value.var = "actual_weight", fill = 0)
    }, error = function(e) {
      message(sprintf("[build_period_returns] holdings dcast skip: %s",
                      conditionMessage(e)))
      NULL
    })
    if (!is.null(h_wide) && nrow(h_wide) > 1) {
      h_dates <- h_wide$date
      h_mat <- as.matrix(h_wide[, !"date"])
      to_vec <- c(NA, sapply(2:nrow(h_mat), function(i) {
        sum(abs(h_mat[i, ] - h_mat[i - 1, ])) / 2
      }))
      to_dt <- data.table(date = h_dates, turnover = to_vec)
      ret_dt <- merge(ret_dt, to_dt, by = "date", all.x = TRUE)
    }
  }
  if (!"turnover" %in% names(ret_dt)) ret_dt[, turnover := NA_real_]

  ret_dt[, run_id := run_id]
  ret_dt[, strategy_id := strategy_id]
  ret_dt[, frequency := frequency]
  ret_dt[, cash_weight := NA_real_]
  ret_dt[, leverage := 1]
  ret_dt[, n_holdings := NA_integer_]

  cols_present <- intersect(PERIOD_RETURNS_COLS, names(ret_dt))
  ret_dt[, ..cols_present]
}

#' Build holdings table
build_holdings <- function(sim_result, run_id, strategy_id) {
  if (is.null(sim_result$HOLDINGS_LOG) || length(sim_result$HOLDINGS_LOG) == 0) {
    return(data.table(matrix(nrow = 0, ncol = length(HOLDINGS_COLS),
                              dimnames = list(NULL, HOLDINGS_COLS))))
  }

  if (is.list(sim_result$HOLDINGS_LOG) && !is.data.frame(sim_result$HOLDINGS_LOG)) {
    h_dt <- rbindlist(sim_result$HOLDINGS_LOG, fill = TRUE)
  } else {
    h_dt <- as.data.table(sim_result$HOLDINGS_LOG)
  }

  # backtest_harness.R schema (Signal_Date/Exec_Date) → contract schema (date)
  if (!"date" %in% names(h_dt)) {
    if ("Exec_Date" %in% names(h_dt)) {
      setnames(h_dt, "Exec_Date", "date")
    } else if ("Signal_Date" %in% names(h_dt)) {
      setnames(h_dt, "Signal_Date", "date")
    } else if ("Date" %in% names(h_dt)) {
      setnames(h_dt, "Date", "date")
    }
  }
  if ("date" %in% names(h_dt)) h_dt[, date := as.Date(date)]

  setnames(h_dt, c("Ticker", "Name", "Sector", "Weight", "Score", "Price"),
           c("ticker", "name", "sector", "actual_weight", "signal_score", "price"),
           skip_absent = TRUE)

  if (!"target_weight" %in% names(h_dt) && "actual_weight" %in% names(h_dt)) {
    h_dt[, target_weight := actual_weight]
  }
  if (!"price" %in% names(h_dt)) h_dt[, price := NA_real_]
  if (!"shares" %in% names(h_dt)) h_dt[, shares := NA_real_]
  if (!"market_value" %in% names(h_dt)) h_dt[, market_value := NA_real_]
  if (!"signal_score" %in% names(h_dt)) h_dt[, signal_score := NA_real_]
  if (!"rank" %in% names(h_dt)) h_dt[, rank := NA_integer_]
  if (!"entry_date" %in% names(h_dt)) h_dt[, entry_date := as.Date(NA)]
  if (!"holding_period" %in% names(h_dt)) h_dt[, holding_period := NA_integer_]
  if (!"is_new_position" %in% names(h_dt)) h_dt[, is_new_position := FALSE]
  if (!"is_exiting_position" %in% names(h_dt)) h_dt[, is_exiting_position := FALSE]

  h_dt[, run_id := run_id]
  h_dt[, strategy_id := strategy_id]

  cols_present <- intersect(HOLDINGS_COLS, names(h_dt))
  h_dt[, ..cols_present]
}

#' Build benchmark_returns table
build_benchmark_returns <- function(sim_result, benchmark_id = "KOSPI200",
                                    benchmark_name = "KOSPI 200",
                                    frequency = "daily", risk_free_rate = 0) {
  if (is.null(sim_result$bm_xts)) {
    return(data.table(matrix(nrow = 0, ncol = length(BENCHMARK_RETURNS_COLS),
                              dimnames = list(NULL, BENCHMARK_RETURNS_COLS))))
  }
  bm_xts <- sim_result$bm_xts
  if (frequency == "monthly") bm_xts <- apply.monthly(bm_xts, Return.cumulative)

  bm_dt <- data.table(
    benchmark_id = benchmark_id,
    benchmark_name = benchmark_name,
    date = as.Date(index(bm_xts)),
    frequency = frequency,
    benchmark_ret = as.numeric(bm_xts)
  )
  bm_dt[, benchmark_nav := cumprod(1 + benchmark_ret)]  # PerformanceAnalytics 동등 (cum 자체는 sequential)
  bm_dt[, risk_free_ret := risk_free_rate]
  bm_dt[, benchmark_excess_ret := benchmark_ret - risk_free_ret]
  bm_dt[, ..BENCHMARK_RETURNS_COLS]
}

## ─── metrics builder (long-format, PerformanceAnalytics 표준) ───────────────

build_metrics <- function(nav_tbl, period_returns_tbl, holdings_tbl,
                           run_id, strategy_id,
                           frequency = "daily", annualization_factor = 252) {
  ret_xts <- xts(period_returns_tbl$ret_net, order.by = period_returns_tbl$date)
  rf_xts  <- xts(period_returns_tbl$risk_free_ret, order.by = period_returns_tbl$date)
  excess_xts <- ret_xts - rf_xts

  nav_xts <- xts(nav_tbl$nav_net, order.by = nav_tbl$date)

  metrics_list <- list()
  add_metric <- function(group, name, value, unit, source, method,
                         metric_type = "backtested", is_official = TRUE) {
    metrics_list[[length(metrics_list) + 1]] <<- data.table(
      run_id = run_id, strategy_id = strategy_id,
      metric_group = group, metric_name = name,
      metric_value = as.numeric(value), metric_unit = unit,
      period_start = min(period_returns_tbl$date),
      period_end = max(period_returns_tbl$date),
      frequency = frequency, return_type = "net",
      annualization_factor = annualization_factor,
      observation_count = nrow(period_returns_tbl),
      metric_type = metric_type, input_source = source,
      calculation_method = method, is_official = is_official
    )
  }

  # 13.1 수익률
  add_metric("return", "Total_Return",
             as.numeric(Return.cumulative(ret_xts)), "ratio",
             "period_returns", "PerformanceAnalytics::Return.cumulative")
  nav_v <- as.numeric(nav_xts)
  cagr_v <- if (length(nav_v) > 1 && nav_v[1] > 0) {
    (tail(nav_v, 1) / head(nav_v, 1))^(annualization_factor / length(nav_v)) - 1
  } else NA_real_
  add_metric("return", "CAGR", cagr_v, "ratio", "nav",
             "(Final/Initial)^(annualization_factor/n) - 1")
  add_metric("return", "Best_Period_Return", max(ret_xts, na.rm = TRUE),
             "ratio", "period_returns", "max(ret_net)")
  add_metric("return", "Worst_Period_Return", min(ret_xts, na.rm = TRUE),
             "ratio", "period_returns", "min(ret_net)")
  add_metric("return", "Positive_Period_Ratio", mean(as.numeric(ret_xts) > 0, na.rm = TRUE),
             "ratio", "period_returns", "mean(ret_net > 0)")

  # 13.2 위험
  ann_vol <- sd(as.numeric(ret_xts), na.rm = TRUE) * sqrt(annualization_factor)
  add_metric("risk", "Annualized_Volatility", ann_vol, "ratio",
             "period_returns", "sd(ret_net) * sqrt(annualization_factor)")
  ds_vol <- as.numeric(DownsideDeviation(ret_xts, MAR = 0)) * sqrt(annualization_factor)
  add_metric("risk", "Downside_Volatility", ds_vol, "ratio",
             "period_returns", "PerformanceAnalytics::DownsideDeviation")
  add_metric("risk", "VaR_95", as.numeric(quantile(as.numeric(ret_xts), 0.05, na.rm = TRUE)),
             "ratio", "period_returns", "quantile(ret_net, 0.05)")
  add_metric("risk", "VaR_99", as.numeric(quantile(as.numeric(ret_xts), 0.01, na.rm = TRUE)),
             "ratio", "period_returns", "quantile(ret_net, 0.01)")
  cvar99 <- mean(as.numeric(ret_xts)[as.numeric(ret_xts) <=
                                       quantile(as.numeric(ret_xts), 0.01, na.rm = TRUE)],
                 na.rm = TRUE)
  add_metric("risk", "CVaR_99", cvar99, "ratio",
             "period_returns", "mean(ret_net <= VaR_99)")
  cvar95 <- mean(as.numeric(ret_xts)[as.numeric(ret_xts) <=
                                       quantile(as.numeric(ret_xts), 0.05, na.rm = TRUE)],
                 na.rm = TRUE)
  add_metric("risk", "CVaR_95", cvar95, "ratio",
             "period_returns", "mean(ret_net <= VaR_95)")
  add_metric("risk", "Skewness", as.numeric(skewness(ret_xts)),
             "ratio", "period_returns", "PerformanceAnalytics::skewness")
  add_metric("risk", "Kurtosis", as.numeric(kurtosis(ret_xts)),
             "ratio", "period_returns", "PerformanceAnalytics::kurtosis")

  # 13.3 위험조정 (Charter v1.4 §12 학술 표준)
  sr_v <- mean(as.numeric(excess_xts), na.rm = TRUE) /
           sd(as.numeric(excess_xts), na.rm = TRUE) * sqrt(annualization_factor)
  add_metric("risk_adjusted", "Sharpe", sr_v, "ratio",
             "period_returns", "mean(ER)/sd(ER)*sqrt(N) [Charter v1.4 §12]")
  sortino_v <- as.numeric(SortinoRatio(ret_xts, MAR = 0)) * sqrt(annualization_factor)
  add_metric("risk_adjusted", "Sortino", sortino_v, "ratio",
             "period_returns", "PerformanceAnalytics::SortinoRatio (annualized)")
  mdd_v <- as.numeric(maxDrawdown(ret_xts))
  calmar_v <- if (mdd_v > 0) cagr_v / mdd_v else NA_real_
  add_metric("risk_adjusted", "Calmar", calmar_v, "ratio",
             "nav", "CAGR / abs(MDD)")
  ret_cvar <- if (!is.na(cvar99) && cvar99 < 0) cagr_v / abs(cvar99) else NA_real_
  add_metric("risk_adjusted", "Return_to_CVaR", ret_cvar, "ratio",
             "period_returns", "CAGR / abs(CVaR_99)")

  # 13.4 드로다운
  add_metric("drawdown", "MDD", mdd_v, "ratio",
             "nav", "PerformanceAnalytics::maxDrawdown")
  dd_table <- tryCatch(table.Drawdowns(ret_xts, top = 100), error = function(e) NULL)
  if (!is.null(dd_table) && nrow(dd_table) > 0) {
    add_metric("drawdown", "Max_DD_Duration_Months",
               as.numeric(max(dd_table$Length, na.rm = TRUE)),
               "months", "drawdowns", "PerformanceAnalytics::table.Drawdowns")
    add_metric("drawdown", "Average_Drawdown",
               as.numeric(mean(dd_table$Depth, na.rm = TRUE)),
               "ratio", "drawdowns", "mean(Depth) [PerformanceAnalytics]")
    add_metric("drawdown", "Average_Recovery_Months",
               as.numeric(mean(dd_table$Recovery, na.rm = TRUE)),
               "months", "drawdowns", "mean(Recovery)")
  }

  # 13.5 거래 (cost 제외)
  if (!is.null(holdings_tbl) && nrow(holdings_tbl) > 0 &&
      "turnover" %in% names(period_returns_tbl)) {
    avg_to <- mean(period_returns_tbl$turnover, na.rm = TRUE)
    if (!is.na(avg_to)) {
      add_metric("exposure", "Average_Turnover", avg_to, "ratio",
                 "period_returns", "mean(turnover) — turnover from holdings L1/2")
      # turnover는 리밸런스 행에만 값이 있는 sparse 시리즈일 수 있어
      # mean × annualization_factor는 행 빈도(일별)를 리밸런스 빈도로 오인한다.
      # 총회전 / 경과연수는 행 밀도 규약(일별 sparse / 월별 dense)과 무관하게 동일.
      n_years <- as.numeric(difftime(max(period_returns_tbl$date),
                                     min(period_returns_tbl$date),
                                     units = "days")) / 365.25
      ann_to <- if (is.finite(n_years) && n_years > 0) {
        sum(period_returns_tbl$turnover, na.rm = TRUE) / n_years
      } else NA_real_
      add_metric("exposure", "Annualized_Turnover", ann_to,
                 "ratio", "period_returns", "sum(turnover) / years_elapsed")
    }
  }
  if (!is.null(holdings_tbl) && nrow(holdings_tbl) > 0 &&
      "date" %in% names(holdings_tbl)) {
    n_per_date <- tryCatch(
      holdings_tbl[, .N, by = date],
      error = function(e) NULL
    )
    if (!is.null(n_per_date) && nrow(n_per_date) > 0 && "N" %in% names(n_per_date)) {
      add_metric("exposure", "Average_N_Holdings",
                 as.numeric(mean(n_per_date$N, na.rm = TRUE)),
                 "count", "holdings", "mean(N per date)")
    }
  }
  if ("cash_weight" %in% names(period_returns_tbl)) {
    add_metric("exposure", "Average_Cash_Weight",
               mean(period_returns_tbl$cash_weight, na.rm = TRUE),
               "ratio", "period_returns", "mean(cash_weight)")
  }
  add_metric("exposure", "Average_Leverage",
             mean(period_returns_tbl$leverage, na.rm = TRUE),
             "ratio", "period_returns", "mean(leverage)")

  rbindlist(metrics_list, use.names = TRUE, fill = TRUE)
}

## ─── benchmark_compare builder ──────────────────────────────────────────────

# Newey-West t-stat of the MEAN of a series (autocorr-robust). lag=3 default.
# WS1 (v8.x): forge-authoritative portfolio-alpha t. NOT IC t (rank-IC t와 구분).
# 패턴 출처: qmj_alpha_build.R::nw_t (동일 공식, contract-grade로 승격).
.nw_t_mean <- function(x, lag = 3L) {
  x <- x[!is.na(x)]; n <- length(x)
  if (n < (lag + 2L)) return(NA_real_)
  mu <- mean(x); e <- x - mu
  g0 <- sum(e^2) / n; s <- g0
  for (l in 1:lag) {
    w <- 1 - l / (lag + 1)
    g <- sum(e[(l + 1):n] * e[1:(n - l)]) / n
    s <- s + 2 * w * g
  }
  if (s <= 0) return(NA_real_)
  mu / sqrt(s / n)
}

build_benchmark_compare <- function(period_returns_tbl, benchmark_returns_tbl,
                                     run_id, strategy_id,
                                     annualization_factor = 252) {
  bm_id <- benchmark_returns_tbl$benchmark_id[1]
  cmp <- merge(period_returns_tbl[, .(date, ret_net)],
                benchmark_returns_tbl[, .(date, benchmark_ret)],
                by = "date")
  if (nrow(cmp) == 0) {
    return(data.table(matrix(nrow = 0, ncol = length(BENCHMARK_COMPARE_COLS),
                              dimnames = list(NULL, BENCHMARK_COMPARE_COLS))))
  }
  cmp[, active := ret_net - benchmark_ret]

  s_xts <- xts(cmp$ret_net, order.by = cmp$date)
  b_xts <- xts(cmp$benchmark_ret, order.by = cmp$date)
  active_xts <- xts(cmp$active, order.by = cmp$date)

  beta_v <- as.numeric(CAPM.beta(s_xts, b_xts, Rf = 0))
  alpha_v <- as.numeric(CAPM.alpha(s_xts, b_xts, Rf = 0)) * annualization_factor
  cor_v <- as.numeric(cor(cmp$ret_net, cmp$benchmark_ret))
  ir_v <- mean(cmp$active, na.rm = TRUE) / sd(cmp$active, na.rm = TRUE) * sqrt(annualization_factor)
  te_v <- sd(cmp$active, na.rm = TRUE) * sqrt(annualization_factor)
  up_cap <- as.numeric(UpDownRatios(s_xts, b_xts, method = "Capture", side = "Up"))
  dn_cap <- as.numeric(UpDownRatios(s_xts, b_xts, method = "Capture", side = "Down"))
  hit_v <- mean(cmp$ret_net > cmp$benchmark_ret, na.rm = TRUE)

  cum_s <- prod(1 + cmp$ret_net) - 1
  cum_b <- prod(1 + cmp$benchmark_ret) - 1

  # WS1 (v8.x): forge-authoritative portfolio-alpha t-stat (NW lag-3 on net active series).
  # Harvey-Liu-Zhu 2016 hurdle(t>=2.95)을 실현 portfolio alpha에 적용 — graduation Gate C 권위 지표.
  pa_t_v <- .nw_t_mean(cmp$active, lag = 3L)
  pa_p_v <- if (is.na(pa_t_v)) NA_real_ else 2 * (1 - pnorm(abs(pa_t_v)))

  # NOTE(2026-05-31): 진단지표(Beta/Correlation/Hit/Up·Down_Capture)의 *raw 값*은 strategy_value에 있음.
  #   active_value는 규약상 "strategy_value − benchmark 기준"(beta−1 / cor−1 / hit−0.5 / cap−1)이라
  #   active_value만 읽으면 음수로 오해됨(예: cor 0.71 → active −0.29). 진단지표는 strategy_value를 읽을 것.
  #   PORT_t/IR/TE/Alpha는 본질적 active 지표라 active_value가 곧 값(벤치 기준 0). essence_score는 후자만 사용.
  rows <- list(
    list("Excess_Total_Return", cum_s, cum_b, cum_s - cum_b, "ratio"),
    list("Active_Return_Mean", mean(cmp$ret_net), mean(cmp$benchmark_ret), mean(cmp$active), "ratio"),
    list("Tracking_Error", NA, NA, te_v, "ratio"),
    list("Information_Ratio", NA, NA, ir_v, "ratio"),
    list("Beta_to_Benchmark", beta_v, 1, beta_v - 1, "ratio"),
    list("Alpha_Annualized", alpha_v, 0, alpha_v, "ratio"),
    list("Portfolio_Alpha_t_NW_lag3", pa_t_v, 0, pa_t_v, "t_stat"),
    list("Portfolio_Alpha_t_pvalue", pa_p_v, NA, pa_p_v, "pvalue"),
    list("Correlation", cor_v, 1, cor_v - 1, "ratio"),
    list("Up_Capture", up_cap, 1, up_cap - 1, "ratio"),
    list("Down_Capture", dn_cap, 1, dn_cap - 1, "ratio"),
    list("Hit_Ratio_vs_BM", hit_v, 0.5, hit_v - 0.5, "ratio")
  )

  out_dt <- rbindlist(lapply(rows, function(r) {
    data.table(
      run_id = run_id, strategy_id = strategy_id, benchmark_id = bm_id,
      period_start = min(cmp$date), period_end = max(cmp$date),
      frequency = period_returns_tbl$frequency[1],
      metric_name = r[[1]],
      strategy_value = r[[2]], benchmark_value = r[[3]], active_value = r[[4]],
      metric_unit = r[[5]], observation_count = nrow(cmp)
    )
  }))
  out_dt
}

## ─── rolling_metrics builder ────────────────────────────────────────────────

build_rolling_metrics <- function(period_returns_tbl, benchmark_returns_tbl,
                                   run_id, strategy_id,
                                   windows = c(3, 6, 12, 36),
                                   annualization_factor = 252) {
  ret_xts <- xts(period_returns_tbl$ret_net, order.by = period_returns_tbl$date)
  out_list <- list()
  bm_id <- benchmark_returns_tbl$benchmark_id[1]

  freq_factor <- if (period_returns_tbl$frequency[1] == "monthly") 1 else 21

  for (w in windows) {
    win_obs <- w * freq_factor
    if (win_obs >= nrow(period_returns_tbl)) next

    # Rolling Sharpe
    rs <- rollapply(ret_xts, width = win_obs, FUN = function(x) {
      if (sd(x, na.rm = TRUE) == 0 || length(x) == 0) return(NA)
      mean(x, na.rm = TRUE) / sd(x, na.rm = TRUE) * sqrt(annualization_factor)
    }, fill = NA, align = "right")
    rs_dt <- data.table(date = as.Date(index(rs)),
                        metric_name = sprintf("Rolling_Sharpe_%dM", w),
                        metric_value = as.numeric(rs))[!is.na(metric_value)]
    if (nrow(rs_dt) > 0) {
      rs_dt[, run_id := run_id][, strategy_id := strategy_id]
      rs_dt[, benchmark_id := bm_id][, window := sprintf("%dM", w)]
      rs_dt[, return_type := "net"][, observation_count := win_obs]
      out_list[[length(out_list) + 1]] <- rs_dt
    }

    # Rolling MDD
    rm_xts <- rollapply(ret_xts, width = win_obs, FUN = function(x) {
      tryCatch(as.numeric(maxDrawdown(x)), error = function(e) NA)
    }, fill = NA, align = "right")
    rm_dt <- data.table(date = as.Date(index(rm_xts)),
                        metric_name = sprintf("Rolling_MDD_%dM", w),
                        metric_value = as.numeric(rm_xts))[!is.na(metric_value)]
    if (nrow(rm_dt) > 0) {
      rm_dt[, run_id := run_id][, strategy_id := strategy_id]
      rm_dt[, benchmark_id := bm_id][, window := sprintf("%dM", w)]
      rm_dt[, return_type := "net"][, observation_count := win_obs]
      out_list[[length(out_list) + 1]] <- rm_dt
    }
  }

  if (length(out_list) == 0) {
    return(data.table(matrix(nrow = 0, ncol = length(ROLLING_METRICS_COLS),
                              dimnames = list(NULL, ROLLING_METRICS_COLS))))
  }
  out_dt <- rbindlist(out_list, use.names = TRUE, fill = TRUE)
  cols_present <- intersect(ROLLING_METRICS_COLS, names(out_dt))
  out_dt[, ..cols_present]
}

## ─── drawdowns builder ─────────────────────────────────────────────────────

build_drawdowns <- function(period_returns_tbl, benchmark_returns_tbl,
                             run_id, strategy_id, top_n = 100) {
  ret_xts <- xts(period_returns_tbl$ret_net, order.by = period_returns_tbl$date)
  dd_table <- tryCatch(table.Drawdowns(ret_xts, top = top_n), error = function(e) NULL)
  if (is.null(dd_table) || nrow(dd_table) == 0) {
    return(data.table(matrix(nrow = 0, ncol = length(DRAWDOWNS_COLS),
                              dimnames = list(NULL, DRAWDOWNS_COLS))))
  }

  bm_drawdown_xts <- if (!is.null(benchmark_returns_tbl) && nrow(benchmark_returns_tbl) > 0) {
    xts(benchmark_returns_tbl$benchmark_ret, order.by = benchmark_returns_tbl$date)
  } else NULL

  dd_dt <- data.table(
    run_id = run_id, strategy_id = strategy_id,
    drawdown_id = seq_len(nrow(dd_table)),
    peak_date = as.Date(dd_table$From),
    trough_date = as.Date(dd_table$Trough),
    recovery_date = as.Date(dd_table$To),
    drawdown_depth = as.numeric(dd_table$Depth),
    drawdown_length = as.integer(dd_table$Length),
    recovery_length = as.integer(dd_table$Recovery),
    total_underwater_period = as.integer(dd_table$Length)
  )

  if (!is.null(bm_drawdown_xts)) {
    dd_dt[, benchmark_drawdown_depth := sapply(seq_len(.N), function(i) {
      # NA recovery_date = unrecovered (open) drawdown → use series end as range bound
      # (avoids xts ISO8601 parse failure on "<peak>/NA"; common at backtest series end)
      end_bound <- if (is.na(recovery_date[i])) as.Date(end(bm_drawdown_xts)) else recovery_date[i]
      if (is.na(peak_date[i])) return(NA_real_)
      sub <- tryCatch(bm_drawdown_xts[paste0(peak_date[i], "/", end_bound)],
                      error = function(e) bm_drawdown_xts[NULL])
      if (length(sub) == 0) return(NA_real_)
      tryCatch(as.numeric(maxDrawdown(sub)), error = function(e) NA_real_)
    })]
    dd_dt[, relative_drawdown := drawdown_depth - benchmark_drawdown_depth]
  } else {
    dd_dt[, benchmark_drawdown_depth := NA_real_]
    dd_dt[, relative_drawdown := NA_real_]
  }
  dd_dt[, ..DRAWDOWNS_COLS]
}

## ─── %||% helper ────────────────────────────────────────────────────────────
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

## ─── 통합 builder: build_bt_result() ────────────────────────────────────────

#' Build complete bt_result list (10 components)
#' @param sim_result list from run_monthly_simulation()
#' @param strategy_spec list with STRATEGY_SPEC_FIELDS
#' @param run_id, strategy_id, strategy_version
#' @param benchmark_id, benchmark_name
#' @param transaction_cost_bps, slippage_bps, risk_free_rate
#' @param frequency "daily" (default for nav) or "monthly"
#' @param annualization_factor 252 (daily) or 12 (monthly)
build_bt_result <- function(sim_result, strategy_spec,
                             run_id, strategy_id, strategy_version = "v1.0",
                             benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
                             transaction_cost_bps = 15, slippage_bps = 15,
                             risk_free_rate = 0,
                             frequency = "daily", annualization_factor = 252,
                             universe_id = "KR_TOP342",
                             code_version = "run_all_v1",
                             created_by_agent = "Q-Lead") {

  cat(sprintf("[build_bt_result] %s | run_id=%s | freq=%s\n",
              strategy_id, run_id, frequency))

  # Component 1: manifest
  manifest_tbl <- build_manifest(run_id, strategy_id, strategy_version,
                                  sim_result, strategy_spec,
                                  transaction_cost_bps, slippage_bps,
                                  universe_id = universe_id,
                                  benchmark_ids = benchmark_id,
                                  code_version = code_version,
                                  created_by_agent = created_by_agent)

  # Component 2: strategy_spec
  spec_tbl <- build_strategy_spec_tbl(strategy_spec, run_id)

  # Component 3: nav
  nav_tbl <- build_nav(sim_result, run_id, strategy_id)

  # Component 5: holdings (먼저 — turnover 계산 input)
  holdings_tbl <- build_holdings(sim_result, run_id, strategy_id)

  # Component 4: period_returns (turnover 포함)
  period_returns_tbl <- build_period_returns(sim_result, run_id, strategy_id,
                                              frequency, risk_free_rate,
                                              holdings_for_turnover = holdings_tbl)

  # Component 6: benchmark_returns
  benchmark_returns_tbl <- build_benchmark_returns(sim_result,
                                                    benchmark_id, benchmark_name,
                                                    frequency, risk_free_rate)

  # Component 7: metrics
  metrics_tbl <- build_metrics(nav_tbl, period_returns_tbl, holdings_tbl,
                                run_id, strategy_id,
                                frequency, annualization_factor)

  # Component 8: benchmark_compare
  benchmark_compare_tbl <- build_benchmark_compare(period_returns_tbl,
                                                    benchmark_returns_tbl,
                                                    run_id, strategy_id,
                                                    annualization_factor)

  # Component 9: rolling_metrics
  rolling_metrics_tbl <- build_rolling_metrics(period_returns_tbl,
                                                benchmark_returns_tbl,
                                                run_id, strategy_id)

  # Component 10: drawdowns
  drawdowns_tbl <- build_drawdowns(period_returns_tbl, benchmark_returns_tbl,
                                     run_id, strategy_id)

  # Component 11: audit (placeholder; audit_bt_result.R로 채움)
  audit_tbl <- data.table(matrix(nrow = 0, ncol = length(AUDIT_COLS),
                                   dimnames = list(NULL, AUDIT_COLS)))

  bt_result <- list(
    manifest          = manifest_tbl,
    strategy_spec     = spec_tbl,
    nav               = nav_tbl,
    period_returns    = period_returns_tbl,
    holdings          = holdings_tbl,
    benchmark_returns = benchmark_returns_tbl,
    metrics           = metrics_tbl,
    benchmark_compare = benchmark_compare_tbl,
    rolling_metrics   = rolling_metrics_tbl,
    drawdowns         = drawdowns_tbl,
    audit             = audit_tbl
  )

  class(bt_result) <- c("bt_result", "list")
  bt_result
}

## ─── Validator ──────────────────────────────────────────────────────────────

#' Validate bt_result schema
#' @return list(valid=TRUE/FALSE, errors=character)
validate_bt_result <- function(bt_result) {
  errors <- character(0)

  # Components 모두 존재 확인
  missing_comp <- setdiff(BT_RESULT_COMPONENTS, names(bt_result))
  if (length(missing_comp) > 0) {
    errors <- c(errors, sprintf("Missing components: %s", paste(missing_comp, collapse = ", ")))
  }

  # Schema 검증
  check_cols <- function(comp_name, expected_cols) {
    if (is.null(bt_result[[comp_name]])) return()
    actual <- names(bt_result[[comp_name]])
    missing <- setdiff(expected_cols, actual)
    if (length(missing) > 0) {
      errors <<- c(errors, sprintf("%s missing cols: %s",
                                    comp_name, paste(missing, collapse = ", ")))
    }
  }

  check_cols("nav", NAV_COLS)
  check_cols("period_returns", PERIOD_RETURNS_COLS)
  check_cols("metrics", METRICS_COLS)
  check_cols("benchmark_compare", BENCHMARK_COMPARE_COLS)
  check_cols("audit", AUDIT_COLS)

  # metric_type 유효성
  if (!is.null(bt_result$metrics) && nrow(bt_result$metrics) > 0) {
    invalid_mt <- setdiff(unique(bt_result$metrics$metric_type), METRIC_TYPE_VALID)
    if (length(invalid_mt) > 0) {
      errors <- c(errors, sprintf("Invalid metric_type: %s", paste(invalid_mt, collapse = ", ")))
    }
  }

  list(valid = length(errors) == 0, errors = errors)
}

cat("[backtest_result_contract.R] Loaded — Backtest Result Contract v1.0\n")
cat("  Functions: build_bt_result() / validate_bt_result()\n")
cat("  10 components: ", paste(BT_RESULT_COMPONENTS, collapse = ", "), "\n", sep = "")
