#!/usr/bin/env Rscript
# dpl_c2_eval_total.R — Qvest cycle2: C2 DPL best의 TOTAL + ACTIVE 지표 contract 단일경로 평가.
#
# 한 표에: TOTAL Sharpe(=SR-2.5 metric, rf=0) / CAGR / MDD / Calmar / TOTAL_SR_t(NW3)
#          + ACTIVE portfolio-alpha-t(NW3) / IR / TE / net-active-SR / TO/yr + DSR(n_trials=256).
# 비교군: DPL_C2_best, EW_top20(98f), MVO_2stage(98f), STR_1715(incumbent), 90f DPL_best(이전 baseline).
# 모든 지표 PerformanceAnalytics/contract 함수 — 자체합성 금지.
#
# 입력(env DPL_WT_DIR=WT_DPL_C2 기준):
#   dpl_best_net_returns.parquet (DPL_C2_best; method,date,ret_net,BM_Ret,traded)
#   baselines_net_returns.parquet (EW_top20/MVO_2stage; dpl_baselines.py 98f 재생성)
#   ../WT_DPL_C1/str1715_with_bm.parquet (STR_1715 net + BM)
#   ../WT_DPL_GPU_SWEEP/dpl_best_net_returns.parquet (90f 이전 DPL baseline)
# 출력: WT_DPL_C2/c2_eval_total.json + 콘솔표.
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(PerformanceAnalytics); library(xts); library(jsonlite)
})
ROOT <- Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
WT <- Sys.getenv("DPL_WT_DIR", "WT_DPL_C2")
OUT <- file.path(ROOT, "stage_artifacts", WT)
N_TRIALS <- as.integer(Sys.getenv("C2_N_TRIALS", "256"))   # honest sweep cells

nw_t <- function(x, lag = 3L) {
  x <- x[!is.na(x)]; n <- length(x)
  if (n < (lag + 2L)) return(NA_real_)
  mu <- mean(x); e <- x - mu; g0 <- sum(e^2)/n; s <- g0
  for (l in 1:lag) { w <- 1 - l/(lag+1); g <- sum(e[(l+1):n]*e[1:(n-l)])/n; s <- s + 2*w*g }
  if (s <= 0) return(NA_real_); mu / sqrt(s/n)
}
dsr_bldp <- function(sr_ann, n_obs, n_trials, skew = 0, kurt = 3, ann = 12) {
  if (!is.finite(sr_ann) || n_obs < 12) return(NA_real_)
  emc <- 0.5772156649; sr_m <- sr_ann/sqrt(ann); var0 <- 1/(n_obs-1)
  sr0 <- if (n_trials < 2) 0 else sqrt(var0)*((1-emc)*qnorm(1-1/n_trials)+emc*qnorm(1-1/(n_trials*exp(1))))
  den <- sqrt(1 - skew*sr_m + (kurt-1)/4*sr_m^2); if (den <= 0) return(NA_real_)
  pnorm((sr_m - sr0)*sqrt(n_obs-1)/den)
}
ym_key <- function(d) format(as.Date(d), "%Y-%m")

read_series <- function(path, method_filter = NULL) {
  if (!file.exists(path)) return(NULL)
  dt <- as.data.table(read_parquet(path)); setnames(dt, names(dt), tolower(names(dt)))
  if (!"bm_ret" %in% names(dt) && "bm_ret_1m" %in% names(dt)) setnames(dt, "bm_ret_1m", "bm_ret")
  if (!"method" %in% names(dt)) dt[, method := "series"]
  if (!is.null(method_filter)) dt <- dt[method %in% method_filter]
  dt
}

# DPL OOS window (C2 best) — 모든 비교군 정렬 기준 (apples-to-apples)
dplc2 <- read_series(file.path(OUT, "dpl_best_net_returns.parquet"))
stopifnot(!is.null(dplc2))
oos_ymk <- sort(unique(ym_key(dplc2$date)))

eval_total <- function(name, s, n_trials) {
  s <- s[!is.na(ret_net)][order(date)]
  s <- s[ym_key(date) %in% oos_ymk]
  if (nrow(s) < 24) return(NULL)
  dates <- as.Date(s$date)
  pr <- data.table(date = dates, ret_net = s$ret_net, frequency = "monthly",
                   risk_free_ret = 0, ret_gross = s$ret_net, excess_ret_net = s$ret_net,
                   cost_ret = 0, turnover = if ("traded" %in% names(s)) s$traded else NA_real_,
                   cash_weight = NA_real_, leverage = 1, n_holdings = NA_integer_,
                   run_id = "c2", strategy_id = name)
  br <- data.table(date = dates, benchmark_ret = s$bm_ret, benchmark_id = "KOSPI200_total_return")
  nav <- cumprod(1 + s$ret_net)
  navt <- data.table(date = dates, nav_net = nav, nav_gross = nav, cash_weight = 0,
                     gross_exposure = 1, net_exposure = 1, leverage = 1, cum_cost = 0,
                     drawdown_net = nav/cummax(nav) - 1, is_rebalance_date = TRUE,
                     run_id = "c2", strategy_id = name)
  m <- build_metrics(navt, pr, NULL, "c2", name, frequency = "monthly", annualization_factor = 12)
  gm <- function(nm){ v <- m[metric_name==nm, metric_value]; if(length(v)==0) NA_real_ else as.numeric(v[1]) }
  bc <- build_benchmark_compare(pr, br, run_id = "c2", strategy_id = name, annualization_factor = 12)
  gb <- function(nm){ v <- bc[metric_name==nm, active_value]; if(length(v)==0) NA_real_ else as.numeric(v[1]) }
  active <- s$ret_net - s$bm_ret
  total_sr <- gm("Sharpe")
  # OOS retention: worst-third active SR / full active SR
  s2 <- copy(s); s2[, g := cut(seq_len(.N), 3, labels = FALSE)]
  sub <- s2[, .(sr = { a <- ret_net - bm_ret; if (length(a) < 6 || sd(a)==0) NA_real_ else mean(a)/sd(a)*sqrt(12) }), by = g]
  full_asr <- mean(active)/sd(active)*sqrt(12)
  worst3 <- suppressWarnings(min(sub$sr, na.rm = TRUE))
  retention <- if (is.finite(full_asr) && full_asr > 1e-9) worst3/full_asr else NA_real_
  sk <- as.numeric(skewness(s$ret_net)); ku <- as.numeric(kurtosis(s$ret_net)) + 3
  list(strategy = name, n_months = nrow(s),
       total_sharpe = round(total_sr,4), total_sharpe_t_nw = round(nw_t(s$ret_net,3L),3),
       cagr = round(gm("CAGR"),4), mdd = round(gm("MDD"),4), calmar = round(gm("Calmar"),4),
       ann_vol = round(gm("Annualized_Volatility"),4),
       portfolio_alpha_t_nw_lag3 = round(gb("Portfolio_Alpha_t_NW_lag3"),4),
       net_active_sr = round(full_asr,4), information_ratio = round(gb("Information_Ratio"),4),
       tracking_error = round(gb("Tracking_Error"),4),
       oos_retention_worst3 = round(retention,3), worst3_active_sr = round(worst3,3),
       turnover_annual = if ("traded" %in% names(s) && any(is.finite(s$traded))) round(mean(s$traded,na.rm=TRUE)*12,2) else NA,
       dsr_total = round(dsr_bldp(total_sr, nrow(s), n_trials, sk, ku),4),
       n_trials = n_trials, metric_type = "backtested")
}

series_specs <- list(
  list(name = "DPL_C2_best", path = file.path(OUT, "dpl_best_net_returns.parquet"), mf = NULL, nt = N_TRIALS),
  list(name = "EW_top20",    path = file.path(OUT, "baselines_net_returns.parquet"), mf = "EW_top20", nt = 1L),
  list(name = "MVO_2stage",  path = file.path(OUT, "baselines_net_returns.parquet"), mf = "MVO_2stage", nt = 1L),
  list(name = "STR_1715",    path = file.path(ROOT, "stage_artifacts/WT_DPL_C1/str1715_with_bm.parquet"), mf = NULL, nt = 1L),
  list(name = "DPL_90f_prev",path = file.path(ROOT, "stage_artifacts/WT_DPL_GPU_SWEEP/dpl_best_net_returns.parquet"), mf = NULL, nt = 96L)
)

res <- list()
for (sp in series_specs) {
  s <- read_series(sp$path, sp$mf); if (is.null(s) || nrow(s)==0) { cat("[skip]", sp$name, "\n"); next }
  r <- eval_total(sp$name, s, sp$nt); if (!is.null(r)) res[[sp$name]] <- r
}

cat(sprintf("\n===== C2 DPL contract eval (OOS %s..%s, %d months, NW lag-3) =====\n",
            oos_ymk[1], oos_ymk[length(oos_ymk)], length(oos_ymk)))
cat(sprintf("%-13s %6s %8s %7s %7s %7s %8s %8s %7s %7s %7s\n",
            "strategy","n_m","TOTAL_SR","SR_t","CAGR","Calmar","PORT_t","net_aSR","ret_w3","TO/yr","DSR"))
cat(strrep("-",108),"\n")
for (nm in names(res)) { x <- res[[nm]]
  cat(sprintf("%-13s %6d %8.3f %7.2f %7.3f %7.3f %8.3f %8.3f %7.3f %7s %7.3f\n",
      substr(x$strategy,1,13), x$n_months, x$total_sharpe, x$total_sharpe_t_nw, x$cagr, x$calmar,
      x$portfolio_alpha_t_nw_lag3, x$net_active_sr, x$oos_retention_worst3,
      ifelse(is.na(x$turnover_annual),"NA",sprintf("%.1f",x$turnover_annual)), x$dsr_total)) }
cat("\n[note] TOTAL_SR = mean(ret_net)/sd(ret_net)*sqrt(12), rf=0 (SR-2.5 target metric).\n")
cat("[hurdle] PORT_t>=2.95 (HARD) | oos_retention>=0.7 (HARD) | DSR>=0.5 (HARD for sweep n_trials>1).\n")
write_json(res, file.path(OUT, "c2_eval_total.json"), auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[out] -> %s\n", file.path(OUT, "c2_eval_total.json")))
