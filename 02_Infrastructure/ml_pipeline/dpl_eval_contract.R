#!/usr/bin/env Rscript
# dpl_eval_contract.R — Qvest v8.x DPL contract-grade 평가.
#
# DPL-best / EW_top20 / MVO_2stage / STR_1715(incumbent) 4종을 동일 OOS·동일 benchmark로
# contract `build_benchmark_compare()` 단일경로 → portfolio_alpha_t_nw_lag3(NW lag-3) +
# net SR + IR + 회전율 산출. metric_type=backtested 라벨. 자체합성 금지.
#
# 입력(Python sweep/baseline export):
#   dpl_best_net_returns.parquet      (method=DPL_best, date, ret_net, BM_Ret, traded)
#   baselines_net_returns.parquet     (EW_top20 / MVO_2stage)
#   stage_artifacts/WT_WT-S20260504_002/str1715_monthly_returns.parquet (incumbent net)
#   benchmark_monthly.parquet         (date, BM_Ret_1m)

suppressPackageStartupMessages({ library(arrow); library(data.table) })

ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
OUT  <- file.path(ROOT, "stage_artifacts", "WT_DPL_GPU_SWEEP")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))

ym_key <- function(d) format(as.Date(d), "%Y-%m")

# benchmark monthly (year-month key)
bm <- as.data.table(read_parquet(file.path(OUT, "benchmark_monthly.parquet")))
bm[, ymk := ym_key(date)]
bm_keyed <- bm[, .(ymk, benchmark_ret = BM_Ret_1m)]

# DPL best + baselines + STR_1715
dpl <- as.data.table(read_parquet(file.path(OUT, "dpl_best_net_returns.parquet")))
base <- as.data.table(read_parquet(file.path(OUT, "baselines_net_returns.parquet")))
str1715 <- as.data.table(read_parquet(
  file.path(ROOT, "stage_artifacts/WT_WT-S20260504_002/str1715_monthly_returns.parquet")))

series_list <- list()
# DPL
d <- dpl[, .(ymk = ym_key(date), ret_net, traded)]
series_list[["DPL_best"]] <- d
# baselines
for (mth in unique(base$method)) {
  b <- base[method == mth, .(ymk = ym_key(date), ret_net, traded)]
  series_list[[mth]] <- b
}
# STR_1715 (net) — traded 미보유 → NA
s1 <- str1715[, .(ymk = ym_key(date), ret_net, traded = NA_real_)]
series_list[["STR_1715"]] <- s1

# DPL OOS 윈도우로 모든 비교군 정렬 (apples-to-apples)
oos_ymk <- sort(unique(d$ymk))

eval_one <- function(name, dt) {
  dt <- merge(dt[ymk %in% oos_ymk], bm_keyed, by = "ymk")
  if (nrow(dt) == 0) return(NULL)
  setorder(dt, ymk)
  # contract 형식 (date = month-end 근사: ymk → 1일, 월단위 정렬만 필요)
  dates <- as.Date(paste0(dt$ymk, "-01"))
  pr <- data.table(date = dates, ret_net = dt$ret_net, frequency = "monthly")
  br <- data.table(date = dates, benchmark_ret = dt$benchmark_ret,
                   benchmark_id = "KOSPI200_total_return")
  bc <- build_benchmark_compare(pr, br, run_id = paste0("dpl_eval_", name),
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
       net_active_sr = net_sr,
       tracking_error = getbc("Tracking_Error"),
       turnover_annual = to_ann,
       metric_type = "backtested")
}

res <- list()
for (nm in names(series_list)) {
  r <- eval_one(nm, series_list[[nm]])
  if (!is.null(r)) res[[nm]] <- r
}

cat("\n===== DPL contract-grade comparison (OOS, NW lag-3) =====\n")
cat(sprintf("OOS window: %s .. %s (%d months)\n", oos_ymk[1], oos_ymk[length(oos_ymk)], length(oos_ymk)))
cat(sprintf("%-12s %10s %9s %8s %8s %8s %8s\n",
            "strategy", "alpha_t", "p_val", "IR", "net_SR", "TE", "TO/yr"))
for (nm in names(res)) {
  r <- res[[nm]]
  cat(sprintf("%-12s %10.3f %9.4f %8.3f %8.3f %8.3f %8s\n",
              r$strategy, r$portfolio_alpha_t_nw_lag3, r$portfolio_alpha_t_pvalue,
              r$information_ratio, r$net_active_sr, r$tracking_error,
              ifelse(is.na(r$turnover_annual), "NA", sprintf("%.2f", r$turnover_annual))))
}
cat("\nHarvey-Liu-Zhu 2016 hurdle: portfolio-alpha t >= 2.95\n")
cat("incumbent ceiling (도훈): portfolio-α t = 2.95 / EW = 2.67\n")

jsonlite::write_json(res, file.path(OUT, "eval_contract.json"), auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[eval] -> %s\n", file.path(OUT, "eval_contract.json")))
