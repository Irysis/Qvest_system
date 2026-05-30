# dpl_compare_contract.R — DPL pilot 결과를 contract-grade로 비교.
# Python(dpl_portfolio.py)이 산출한 월별 net return series(DPL/EW/MVO)를
# R build_benchmark_compare()(02_Infrastructure/contracts/) 단일 경로로 routing →
# authoritative portfolio_alpha_t_nw_lag3 + IR + alpha_ann + net_SR.
# 자체합성 금지: SR/alpha-t는 contract 함수에서만 산출.
suppressMessages({ library(data.table); library(arrow); library(xts); library(PerformanceAnalytics) })

ROOT <- tryCatch(normalizePath(file.path(dirname(sys.frame(1)$ofile), "..", "..")),
                 error = function(e) getwd())
source(file.path(ROOT, "02_Infrastructure", "contracts", "backtest_result_contract.R"))

inp <- file.path(ROOT, "stage_artifacts", "WT_DPL_PILOT", "dpl_pilot_net_returns.parquet")
dt <- as.data.table(read_parquet(inp))
dt[, date := as.Date(date)]

methods <- unique(dt$method)
res <- list()
for (mth in methods) {
  d <- dt[method == mth][order(date)]
  pr <- data.table(date = d$date, ret_net = d$ret_net, frequency = "monthly")
  bm <- data.table(date = d$date, benchmark_ret = d$BM_Ret,
                   benchmark_id = "KOSPI200_total_return")
  bc <- build_benchmark_compare(pr, bm, run_id = paste0("dpl_pilot_", mth),
                                strategy_id = mth, annualization_factor = 12)
  g <- function(nm) { v <- bc[metric_name == nm, active_value]; if (length(v)==0) NA_real_ else as.numeric(v[1]) }
  active <- d$ret_net - d$BM_Ret
  net_sr <- mean(d$ret_net) / sd(d$ret_net) * sqrt(12)         # standalone net SR
  res[[mth]] <- data.table(
    method = mth, n_months = nrow(d),
    portfolio_alpha_t_nw_lag3 = g("Portfolio_Alpha_t_NW_lag3"),
    portfolio_alpha_t_pvalue  = g("Portfolio_Alpha_t_pvalue"),
    information_ratio = g("Information_Ratio"),
    alpha_annualized  = g("Alpha_Annualized"),
    tracking_error    = g("Tracking_Error"),
    net_sr_standalone = net_sr,
    mean_active_net   = mean(active),
    turnover_annual   = mean(d$traded) * 12,
    metric_type = "backtested_contract_build_benchmark_compare"
  )
}
out <- rbindlist(res)
setorder(out, -portfolio_alpha_t_nw_lag3)
cat("\n==================== DPL PILOT — contract-grade comparison ====================\n")
print(out)
fwrite(out, file.path(ROOT, "stage_artifacts", "WT_DPL_PILOT", "dpl_pilot_comparison.csv"))
cat("\nsaved: stage_artifacts/WT_DPL_PILOT/dpl_pilot_comparison.csv\n")
