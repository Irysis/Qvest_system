#!/usr/bin/env Rscript
# dpl_cbe_eval_contract.R — Qvest v8.x Dev-CBE contract-grade 평가 (NW lag-3, backtested).
#
# DPL(90f baseline) vs DPL+C vs DPL+C+B vs DPL+C+B+E (OOS) + 각 in-sample 분리.
# vs EW_top20 0.84 / MVO 0.11 / STR_1715 incumbent 5.34.
# build_benchmark_compare() 단일경로. 자체합성 금지. metric_type=backtested.

suppressPackageStartupMessages({ library(arrow); library(data.table); library(jsonlite) })

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts", "WT_DPL_GPU_SWEEP")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))

ym_key <- function(d) format(as.Date(d), "%Y-%m")

bm <- as.data.table(read_parquet(file.path(OUT, "benchmark_monthly.parquet")))
bm[, ymk := ym_key(date)]
bm_keyed <- bm[, .(ymk, benchmark_ret = BM_Ret_1m)]

read_series <- function(fname) {
  fp <- file.path(OUT, fname)
  if (!file.exists(fp)) return(NULL)
  dt <- as.data.table(read_parquet(fp))
  dt[, .(ymk = ym_key(date), ret_net, traded)]
}

series_list <- list()
# baseline DPL (90f, 기존)
series_list[["DPL_90f"]]   <- read_series("dpl_best_net_returns.parquet")
# CBE variants OOS
series_list[["DPL_C"]]     <- read_series("cbe_C_net_returns.parquet")
series_list[["DPL_CB"]]    <- read_series("cbe_CB_net_returns.parquet")
series_list[["DPL_CBE"]]   <- read_series("cbe_CBE_net_returns.parquet")
# in-sample (분리 보고 — cherry-pick 경계 명시)
series_list[["DPL_C_IS"]]  <- read_series("cbe_C_is_net_returns.parquet")
series_list[["DPL_CB_IS"]] <- read_series("cbe_CB_is_net_returns.parquet")
series_list[["DPL_CBE_IS"]]<- read_series("cbe_CBE_is_net_returns.parquet")
# references
base_dt <- as.data.table(read_parquet(file.path(OUT, "baselines_net_returns.parquet")))
for (mth in unique(base_dt$method)) {
  series_list[[mth]] <- base_dt[method == mth, .(ymk = ym_key(date), ret_net, traded)]
}
str1715 <- as.data.table(read_parquet(
  file.path(ROOT, "stage_artifacts/WT_WT-S20260504_002/str1715_monthly_returns.parquet")))
series_list[["STR_1715"]] <- str1715[, .(ymk = ym_key(date), ret_net, traded = NA_real_)]

series_list <- series_list[!sapply(series_list, is.null)]

# 공통 OOS 윈도우 = DPL_90f (apples-to-apples). IS 계열은 자체 구간(별도).
oos_ymk <- sort(unique(series_list[["DPL_90f"]]$ymk))

eval_one <- function(name, dt, restrict_oos = TRUE) {
  if (restrict_oos) dt <- dt[ymk %in% oos_ymk]
  dt <- merge(dt, bm_keyed, by = "ymk")
  if (nrow(dt) == 0) return(NULL)
  setorder(dt, ymk)
  dates <- as.Date(paste0(dt$ymk, "-01"))
  pr <- data.table(date = dates, ret_net = dt$ret_net, frequency = "monthly")
  br <- data.table(date = dates, benchmark_ret = dt$benchmark_ret,
                   benchmark_id = "KOSPI200_total_return")
  bc <- build_benchmark_compare(pr, br, run_id = paste0("cbe_eval_", name),
                                strategy_id = name, annualization_factor = 12)
  getbc <- function(nm) { v <- bc[metric_name == nm, active_value]; if (length(v)==0) NA_real_ else as.numeric(v[1]) }
  active <- dt$ret_net - dt$benchmark_ret
  net_sr <- mean(active) / sd(active) * sqrt(12)
  to_ann <- if (all(is.na(dt$traded))) NA_real_ else mean(dt$traded, na.rm = TRUE) * 12
  list(strategy = name, n_months = nrow(dt),
       portfolio_alpha_t_nw_lag3 = getbc("Portfolio_Alpha_t_NW_lag3"),
       portfolio_alpha_t_pvalue  = getbc("Portfolio_Alpha_t_pvalue"),
       information_ratio = getbc("Information_Ratio"),
       alpha_annualized  = getbc("Alpha_Annualized"),
       net_active_sr = net_sr, tracking_error = getbc("Tracking_Error"),
       turnover_annual = to_ann, metric_type = "backtested")
}

res <- list()
# IS 계열은 restrict 안 함(자체 train 구간 전체)
for (nm in names(series_list)) {
  is_is <- grepl("_IS$", nm)
  r <- eval_one(nm, series_list[[nm]], restrict_oos = !is_is)
  if (!is.null(r)) res[[nm]] <- r
}

cat("\n===== DPL Dev-CBE contract-grade comparison (NW lag-3, backtested) =====\n")
cat(sprintf("OOS window: %s .. %s (%d months)\n", oos_ymk[1], oos_ymk[length(oos_ymk)], length(oos_ymk)))
cat(sprintf("%-14s %8s %9s %8s %8s %8s %8s\n",
            "strategy", "alpha_t", "p_val", "IR", "net_SR", "TE", "TO/yr"))
ord <- c("DPL_90f","DPL_C","DPL_CB","DPL_CBE","DPL_C_IS","DPL_CB_IS","DPL_CBE_IS",
         "EW_top20","MVO_2stage","STR_1715")
for (nm in ord) {
  if (is.null(res[[nm]])) next
  r <- res[[nm]]
  cat(sprintf("%-14s %8.3f %9.4f %8.3f %8.3f %8.3f %8s\n",
              r$strategy, r$portfolio_alpha_t_nw_lag3, r$portfolio_alpha_t_pvalue,
              r$information_ratio, r$net_active_sr, r$tracking_error,
              ifelse(is.na(r$turnover_annual), "NA", sprintf("%.2f", r$turnover_annual))))
}
cat("\nHarvey-Liu-Zhu 2016 hurdle: portfolio-alpha t >= 2.95\n")
cat("references: DPL_90f baseline α-t 2.766 / EW 0.835 / STR_1715 incumbent 5.344\n")
cat("[IS = in-sample (전체구간 fit·eval, 과적합 상한 — cherry-pick 경계 명시)]\n")

write_json(res, file.path(OUT, "cbe_eval_contract.json"), auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[eval] -> %s\n", file.path(OUT, "cbe_eval_contract.json")))
