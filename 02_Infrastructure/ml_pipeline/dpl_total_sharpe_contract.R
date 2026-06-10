#!/usr/bin/env Rscript
# dpl_total_sharpe_contract.R — Qvest v8.x cycle1: TOTAL Sharpe (the SR-2.5 metric) of DPL series.
#
# 기존 DPL eval_contract.R 들은 *active* Sharpe(ret_net - benchmark)만 산출했다(net_active_SR ~0.7).
# 그러나 과제 목표 'SR 2.5'와 STR_1652 'Sharpe 1.2'는 *total* Sharpe(ret_net/vol, rf=0)다.
# 본 스크립트는 임의의 DPL net-return parquet(method,date,ret_net,BM_Ret[,traded])을 받아
# contract build_bt_result()/build_benchmark_compare() 단일경로로:
#   total Sharpe / CAGR / MDD / Calmar / total-Sharpe-t(NW)  + active portfolio-alpha-t / IR / TE
# 를 산출한다. 자체합성 금지 — Return.portfolio 불필요(이미 월별 포트 net return 시계열 입력),
# 단 모든 지표는 PerformanceAnalytics/contract 함수로 계산.
#
# 사용: Rscript dpl_total_sharpe_contract.R <parquet1> [<parquet2> ...]
#   각 parquet은 columns: method,date,ret_net,BM_Ret (traded optional).
# 출력: stage_artifacts/WT_DPL_C1/total_sharpe_<basename>.json + 콘솔표.

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(PerformanceAnalytics); library(xts); library(jsonlite)
})
ROOT <- Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))

OUT <- file.path(ROOT, "stage_artifacts", "WT_DPL_C1")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

# NW t of mean (same as contract .nw_t_mean, lag 3) — for total Sharpe significance
nw_t <- function(x, lag = 3L) {
  x <- x[!is.na(x)]; n <- length(x)
  if (n < (lag + 2L)) return(NA_real_)
  mu <- mean(x); e <- x - mu
  g0 <- sum(e^2) / n; s <- g0
  for (l in 1:lag) { w <- 1 - l / (lag + 1); g <- sum(e[(l + 1):n] * e[1:(n - l)]) / n; s <- s + 2 * w * g }
  if (s <= 0) return(NA_real_); mu / sqrt(s / n)
}

# Bailey-Lopez de Prado 2014 DSR (per-period), matching dpl_gpu_sweep.deflated_sharpe_ratio
dsr_bldp <- function(sr_ann, n_obs, n_trials, skew = 0, kurt = 3, annualize = 12) {
  if (!is.finite(sr_ann) || n_obs < 12) return(NA_real_)
  emc <- 0.5772156649
  sr_m <- sr_ann / sqrt(annualize)
  var0 <- 1.0 / (n_obs - 1)
  if (n_trials < 2) { sr0 <- 0.0 } else {
    z1 <- qnorm(1 - 1.0 / n_trials); z2 <- qnorm(1 - 1.0 / (n_trials * exp(1)))
    sr0 <- sqrt(var0) * ((1 - emc) * z1 + emc * z2)
  }
  den <- sqrt(1 - skew * sr_m + (kurt - 1) / 4.0 * sr_m^2)
  if (den <= 0) return(NA_real_)
  num <- (sr_m - sr0) * sqrt(n_obs - 1)
  pnorm(num / den)
}

eval_total <- function(path, n_trials = 1L) {
  dt <- as.data.table(read_parquet(path))
  setnames(dt, names(dt), tolower(names(dt)))
  if (!"bm_ret" %in% names(dt) && "bm_ret_1m" %in% names(dt)) setnames(dt, "bm_ret_1m", "bm_ret")
  methods <- if ("method" %in% names(dt)) unique(dt$method) else "series"
  if (!"method" %in% names(dt)) dt[, method := "series"]
  out <- list()
  for (mth in methods) {
    s <- dt[method == mth][order(date)]
    s <- s[!is.na(ret_net)]
    if (nrow(s) < 24) next
    dates <- as.Date(s$date)
    pr <- data.table(date = dates, ret_net = s$ret_net, frequency = "monthly",
                     risk_free_ret = 0, ret_gross = s$ret_net,
                     excess_ret_net = s$ret_net, cost_ret = 0,
                     turnover = if ("traded" %in% names(s)) s$traded else NA_real_,
                     cash_weight = NA_real_, leverage = 1, n_holdings = NA_integer_,
                     run_id = "c1", strategy_id = mth)
    br <- data.table(date = dates, benchmark_ret = s$bm_ret, benchmark_id = "KOSPI200_total_return")
    # nav for CAGR/MDD/Calmar (contract build_metrics path)
    nav_net <- cumprod(1 + s$ret_net)
    nav_tbl <- data.table(date = dates, nav_net = nav_net, nav_gross = nav_net,
                          cash_weight = 0, gross_exposure = 1, net_exposure = 1, leverage = 1,
                          cum_cost = 0, drawdown_net = nav_net / cummax(nav_net) - 1,
                          is_rebalance_date = TRUE, run_id = "c1", strategy_id = mth)
    metrics <- build_metrics(nav_tbl, pr, NULL, "c1", mth, frequency = "monthly", annualization_factor = 12)
    getm <- function(nm) { v <- metrics[metric_name == nm, metric_value]; if (length(v)==0) NA_real_ else as.numeric(v[1]) }
    bc <- build_benchmark_compare(pr, br, run_id = "c1", strategy_id = mth, annualization_factor = 12)
    getbc <- function(nm) { v <- bc[metric_name == nm, active_value]; if (length(v)==0) NA_real_ else as.numeric(v[1]) }

    total_sr   <- getm("Sharpe")          # mean(ret_net)/sd(ret_net)*sqrt(12), rf=0  ← THE SR-2.5 metric
    cagr       <- getm("CAGR")
    mdd        <- getm("MDD")
    calmar     <- getm("Calmar")
    sortino    <- getm("Sortino")
    ann_vol    <- getm("Annualized_Volatility")
    port_a_t   <- getbc("Portfolio_Alpha_t_NW_lag3")
    ir         <- getbc("Information_Ratio")
    te         <- getbc("Tracking_Error")
    net_active_sr <- mean(s$ret_net - s$bm_ret) / sd(s$ret_net - s$bm_ret) * sqrt(12)
    total_sr_t <- nw_t(s$ret_net, 3L)     # NW t of monthly net return mean
    # DSR on TOTAL Sharpe (skew/kurt of net returns)
    sk <- as.numeric(skewness(s$ret_net)); ku <- as.numeric(kurtosis(s$ret_net)) + 3  # kurtosis() is excess
    dsr_total <- dsr_bldp(total_sr, nrow(s), n_trials, sk, ku)
    to_ann <- if ("traded" %in% names(s)) mean(s$traded, na.rm = TRUE) * 12 else NA_real_

    out[[mth]] <- list(strategy = mth, n_months = nrow(s),
                       total_sharpe = round(total_sr, 4), total_sharpe_t_nw = round(total_sr_t, 3),
                       cagr = round(cagr, 4), mdd = round(mdd, 4), calmar = round(calmar, 4),
                       sortino = round(sortino, 3), ann_vol = round(ann_vol, 4),
                       net_active_sr = round(net_active_sr, 4),
                       portfolio_alpha_t_nw_lag3 = round(port_a_t, 4),
                       information_ratio = round(ir, 4), tracking_error = round(te, 4),
                       turnover_annual = if (is.na(to_ann)) NA else round(to_ann, 2),
                       dsr_total_sharpe = round(dsr_total, 4), n_trials = n_trials,
                       metric_type = "backtested")
  }
  out
}

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  args <- c(file.path(ROOT, "stage_artifacts/WT_DPL_GPU_SWEEP/dpl_best_net_returns.parquet"),
            file.path(ROOT, "stage_artifacts/WT_DPL_GPU_SWEEP/baselines_net_returns.parquet"))
}

cat(sprintf("%-16s %6s %8s %7s %8s %7s %7s %8s %8s %7s %7s\n",
            "strategy","n_m","TOTAL_SR","SR_t","CAGR","MDD","Calmar","net_aSR","PORT_t","IR","DSR_tot"))
cat(strrep("-", 110), "\n")
all_res <- list()
for (p in args) {
  if (!file.exists(p)) { cat("[skip missing]", p, "\n"); next }
  base <- tools::file_path_sans_ext(basename(p))
  r <- eval_total(p, n_trials = 1L)
  for (nm in names(r)) {
    x <- r[[nm]]
    cat(sprintf("%-16s %6d %8.3f %7.2f %8.3f %7.3f %7.3f %8.3f %8.3f %7.3f %7.3f\n",
                substr(x$strategy,1,16), x$n_months, x$total_sharpe, x$total_sharpe_t_nw,
                x$cagr, x$mdd, x$calmar, x$net_active_sr, x$portfolio_alpha_t_nw_lag3,
                x$information_ratio, x$dsr_total_sharpe))
    all_res[[paste0(base, "::", nm)]] <- x
  }
  write_json(r, file.path(OUT, paste0("total_sharpe_", base, ".json")), auto_unbox = TRUE, pretty = TRUE)
}
cat("\n[note] TOTAL_SR = mean(ret_net)/sd(ret_net)*sqrt(12), rf=0  (the SR-2.5 target metric).\n")
cat("[note] net_aSR = active Sharpe (prior FINDINGS reported THIS, not TOTAL).\n")
write_json(all_res, file.path(OUT, "total_sharpe_summary.json"), auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("[out] -> %s\n", file.path(OUT, "total_sharpe_summary.json")))
