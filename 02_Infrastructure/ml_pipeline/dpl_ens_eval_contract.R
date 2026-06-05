#!/usr/bin/env Rscript
# dpl_ens_eval_contract.R — Qvest v8.x Dev: DPL ENSEMBLE variance-reduction contract-grade 평가.
#
# baseline DPL_C(cbe_C) vs ENS seed_K8 / seed_K16 / config5 — OOS + in-sample 분리.
# vs EW_top20 / STR_1715 incumbent 5.34. build_benchmark_compare() 단일경로(NW lag-3).
# 자체합성 금지. metric_type=backtested. 동일 168m OOS·동일 KOSPI200.

suppressPackageStartupMessages({ library(arrow); library(data.table); library(jsonlite) })

ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
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
# baseline DPL_C (prior, cbe_C OOS) — anchor for apples-to-apples OOS window
series_list[["DPL_C"]]        <- read_series("cbe_C_net_returns.parquet")
# ENSEMBLE variants OOS
series_list[["ENS_seed_K8"]]  <- read_series("ens_seed_K8_net_returns.parquet")
series_list[["ENS_seed_K16"]] <- read_series("ens_seed_K16_net_returns.parquet")
series_list[["ENS_config5"]]  <- read_series("ens_config5_net_returns.parquet")
# in-sample (분리 — cherry-pick 경계 명시)
series_list[["ENS_seed_K8_IS"]]  <- read_series("ens_seed_K8_is_net_returns.parquet")
series_list[["ENS_seed_K16_IS"]] <- read_series("ens_seed_K16_is_net_returns.parquet")
series_list[["ENS_config5_IS"]]  <- read_series("ens_config5_is_net_returns.parquet")
# references
bf <- file.path(OUT, "baselines_net_returns.parquet")
if (file.exists(bf)) {
  base_dt <- as.data.table(read_parquet(bf))
  for (mth in unique(base_dt$method)) {
    series_list[[mth]] <- base_dt[method == mth, .(ymk = ym_key(date), ret_net, traded)]
  }
}
s1715f <- file.path(ROOT, "stage_artifacts/WT_WT-S20260504_002/str1715_monthly_returns.parquet")
if (file.exists(s1715f)) {
  str1715 <- as.data.table(read_parquet(s1715f))
  series_list[["STR_1715"]] <- str1715[, .(ymk = ym_key(date), ret_net, traded = NA_real_)]
}

series_list <- series_list[!sapply(series_list, is.null)]

# 공통 OOS 윈도우 = DPL_C (apples-to-apples). IS 계열은 자체구간.
oos_ymk <- sort(unique(series_list[["DPL_C"]]$ymk))

# Bailey-Lopez de Prado (2014) Deflated Sharpe Ratio (per-period 단위, R 독립구현 — Python과 동일 공식)
deflated_sharpe_ratio <- function(sr_ann, n_obs, n_trials, skew = 0, kurt = 3, A = 12) {
  if (!is.finite(sr_ann) || n_obs < 12) return(NA_real_)
  emc <- 0.5772156649
  sr_m <- sr_ann / sqrt(A)
  var0 <- 1 / (n_obs - 1)
  if (n_trials < 2) { sr0 <- 0 } else {
    z1 <- qnorm(1 - 1 / n_trials); z2 <- qnorm(1 - 1 / (n_trials * exp(1)))
    sr0 <- sqrt(var0) * ((1 - emc) * z1 + emc * z2)
  }
  den <- sqrt(1 - skew * sr_m + (kurt - 1) / 4 * sr_m^2)
  if (den <= 0) return(NA_real_)
  num <- (sr_m - sr0) * sqrt(n_obs - 1)
  pnorm(num / den)
}

subperiod_srs <- function(dt) {
  setorder(dt, ymk)
  active <- dt$ret_net - dt$benchmark_ret
  n <- length(active); idx <- cut(seq_len(n), 3, labels = FALSE)
  sapply(1:3, function(g) {
    a <- active[idx == g]
    if (length(a) < 6 || sd(a) == 0) NA_real_ else mean(a) / sd(a) * sqrt(12)
  })
}

eval_one <- function(name, dt, restrict_oos = TRUE, n_trials_cum = 123) {
  if (restrict_oos) dt <- dt[ymk %in% oos_ymk]
  dt <- merge(dt, bm_keyed, by = "ymk")
  if (nrow(dt) == 0) return(NULL)
  setorder(dt, ymk)
  dates <- as.Date(paste0(dt$ymk, "-01"))
  pr <- data.table(date = dates, ret_net = dt$ret_net, frequency = "monthly")
  br <- data.table(date = dates, benchmark_ret = dt$benchmark_ret,
                   benchmark_id = "KOSPI200_total_return")
  bc <- build_benchmark_compare(pr, br, run_id = paste0("ens_eval_", name),
                                strategy_id = name, annualization_factor = 12)
  getbc <- function(nm) { v <- bc[metric_name == nm, active_value]; if (length(v)==0) NA_real_ else as.numeric(v[1]) }
  active <- dt$ret_net - dt$benchmark_ret
  net_sr <- mean(active) / sd(active) * sqrt(12)
  to_ann <- if (all(is.na(dt$traded))) NA_real_ else mean(dt$traded, na.rm = TRUE) * 12
  sk <- moments_skew(active); ku <- moments_kurt(active)
  dsr <- deflated_sharpe_ratio(net_sr, length(active), n_trials_cum, sk, ku)
  subs <- subperiod_srs(dt)
  list(strategy = name, n_months = nrow(dt),
       portfolio_alpha_t_nw_lag3 = getbc("Portfolio_Alpha_t_NW_lag3"),
       portfolio_alpha_t_pvalue  = getbc("Portfolio_Alpha_t_pvalue"),
       information_ratio = getbc("Information_Ratio"),
       alpha_annualized  = getbc("Alpha_Annualized"),
       net_active_sr = net_sr, tracking_error = getbc("Tracking_Error"),
       turnover_annual = to_ann,
       DSR_corrected = dsr, n_trials_cumulative = n_trials_cum,
       subperiod_active_SR = round(subs, 3),
       subperiod_min = round(min(subs, na.rm = TRUE), 3),
       metric_type = "backtested")
}

# skew/kurt (population, fisher=FALSE 정합 — scipy kurtosis fisher=False = Pearson)
moments_skew <- function(x) { x <- x[is.finite(x)]; m <- mean(x); s <- sd(x); if (s == 0) return(0); mean(((x-m)/s)^3) }
moments_kurt <- function(x) { x <- x[is.finite(x)]; m <- mean(x); s <- sd(x); if (s == 0) return(3); mean(((x-m)/s)^4) }

# n_trials_cumulative per strategy (from ens_sweep_results.json if present)
ntc <- 123
ens_json <- file.path(OUT, "ens_sweep_results.json")
ntc_map <- list()
if (file.exists(ens_json)) {
  ej <- fromJSON(ens_json, simplifyVector = FALSE)
  for (mode in names(ej$modes)) {
    ntc_map[[paste0("ENS_", mode)]] <- ej$modes[[mode]]$n_trials_cumulative
    ntc_map[[paste0("ENS_", mode, "_IS")]] <- ej$modes[[mode]]$n_trials_cumulative
  }
}
ntc_map[["DPL_C"]] <- 123  # baseline prior cumulative

res <- list()
for (nm in names(series_list)) {
  is_is <- grepl("_IS$", nm)
  ntc_use <- if (!is.null(ntc_map[[nm]])) as.numeric(ntc_map[[nm]]) else 123
  r <- eval_one(nm, series_list[[nm]], restrict_oos = !is_is, n_trials_cum = ntc_use)
  if (!is.null(r)) res[[nm]] <- r
}

cat("\n===== DPL ENSEMBLE variance-reduction contract-grade (NW lag-3, backtested) =====\n")
cat(sprintf("OOS window: %s .. %s (%d months)\n", oos_ymk[1], oos_ymk[length(oos_ymk)], length(oos_ymk)))
cat(sprintf("%-16s %8s %9s %8s %8s %8s %8s %8s %10s\n",
            "strategy", "alpha_t", "p_val", "IR", "net_SR", "TE", "TO/yr", "DSR", "sub_min"))
ord <- c("DPL_C", "ENS_seed_K8", "ENS_seed_K16", "ENS_config5",
         "ENS_seed_K8_IS", "ENS_seed_K16_IS", "ENS_config5_IS",
         "EW_top20", "MVO_2stage", "STR_1715")
for (nm in ord) {
  if (is.null(res[[nm]])) next
  r <- res[[nm]]
  cat(sprintf("%-16s %8.3f %9.4f %8.3f %8.3f %8.3f %8s %8.3f %10s\n",
              r$strategy, r$portfolio_alpha_t_nw_lag3, r$portfolio_alpha_t_pvalue,
              r$information_ratio, r$net_active_sr, r$tracking_error,
              ifelse(is.na(r$turnover_annual), "NA", sprintf("%.2f", r$turnover_annual)),
              ifelse(is.na(r$DSR_corrected), NA_real_, r$DSR_corrected),
              paste0("[", paste(r$subperiod_active_SR, collapse=","), "]")))
}
cat("\nHarvey-Liu-Zhu 2016 hurdle: portfolio-alpha t >= 2.95 ; DSR hurdle 0.5\n")
cat("baseline DPL_C: alpha_t 2.906 / DSR_prior 0.378 / sub[1.495,-0.349,0.77] / TO 14.35\n")
cat("[IS = in-sample 전체구간 fit·eval (과적합 상한 — cherry-pick 경계 명시)]\n")

write_json(res, file.path(OUT, "ens_eval_contract.json"), auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[eval] -> %s\n", file.path(OUT, "ens_eval_contract.json")))
