# R16 measure — canonical dual-basis + subperiod + IC + Size-partial for 5 factors
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
data.table::setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent = TRUE)
STAGE <- "stage_artifacts/r16_microstructure"
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a

scores_long <- as.data.table(read_parquet(file.path(STAGE,"scores_long.parquet")))
returns_dt  <- as.data.table(read_parquet(file.path(STAGE,"returns_dt.parquet")))
bench_dt    <- as.data.table(read_parquet(file.path(STAGE,"bench_dt.parquet")))
size_dt     <- as.data.table(read_parquet(file.path(STAGE,"size_dt.parquet")))
liq_dt      <- as.data.table(read_parquet(file.path(STAGE,"liq_dt.parquet")))
for (d in list(scores_long,returns_dt,bench_dt,size_dt,liq_dt)) d[, Date := as.Date(Date)]

FACS <- c("VSHK_P","TOD_DT","AMT_ASY","VPRC_CORR","ILLIQ_VOL")
SPLIT <- as.Date("2017-01-01")

nw_port_t <- function(pr_sub) {   # pr_sub: date, ret_net, benchmark_ret
  if (nrow(pr_sub) < 12) return(NA_real_)
  prt <- data.table(date = pr_sub$date, ret_net = pr_sub$ret_net, frequency = "monthly")
  bmt <- data.table(date = pr_sub$date, benchmark_ret = pr_sub$benchmark_ret, benchmark_id = "cap_w")
  bc <- tryCatch(build_benchmark_compare(prt, bmt, run_id="sub", strategy_id="sub", annualization_factor=12L),
                 error = function(e) NULL)
  if (is.null(bc)) return(NA_real_)
  v <- bc[metric_name == "Portfolio_Alpha_t_NW_lag3", active_value]
  if (length(v)==0) NA_real_ else as.numeric(v[1])
}
oos_ret_v2 <- function(active) {
  n <- length(active); if (n < 24) return(NA_real_)
  vals <- sapply(c(.55,.65,.75), function(a){
    k <- floor(n*a); is <- active[1:k]; oos <- active[(k+1):n]
    sri <- mean(is)/sd(is); sro <- mean(oos)/sd(oos)
    if (is.na(sri) || sri <= 0) return(NA_real_); sro/sri
  })
  if (all(is.na(vals))) return(NA_real_); median(vals, na.rm=TRUE)
}

results <- list()
for (f in FACS) {
  cat("=== ", f, " ===\n")
  sc <- scores_long[factor == f, .(Date, Ticker, score)]
  cs <- canonical_screen_bt(sc, returns_dt[, .(Date, Ticker, Ret_1m)],
                            bench_dt[, .(Date, BM_Ret)],
                            top_n = 25L, cost_bps_oneway = 15,
                            liq_dt = liq_dt, liq_min = 2e8,
                            size_dt = size_dt, diag_dual_basis = TRUE,
                            run_id = f, strategy_id = paste0("R16_", f))
  pr <- as.data.table(cs$period_returns)   # date, ret_net, benchmark_ret
  active <- pr$ret_net - pr$benchmark_ret
  pre <- pr[date <  SPLIT]; post <- pr[date >= SPLIT]

  # rank-IC + Size-partial IC (per month spearman)
  m <- merge(sc, returns_dt[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
  m <- merge(m, size_dt, by = c("Date","Ticker"), all.x = TRUE)
  m[, lsize := ifelse(Size > 0, log(Size), NA_real_)]
  ic_by <- m[, {
    if (.N >= 10 && sd(score) > 0 && sd(Ret_1m) > 0) {
      ic <- cor(score, Ret_1m, method = "spearman")
      # size-partial: residualize both on lsize then spearman
      if (sum(!is.na(lsize)) >= 10 && sd(lsize, na.rm=TRUE) > 0) {
        rs <- residuals(lm(score ~ lsize, na.action = na.exclude))
        rr <- residuals(lm(Ret_1m ~ lsize, na.action = na.exclude))
        pic <- suppressWarnings(cor(rs, rr, method = "spearman", use = "complete.obs"))
        scz <- suppressWarnings(cor(score, lsize, method = "spearman", use = "complete.obs"))
      } else { pic <- NA_real_; scz <- NA_real_ }
      .(ic = ic, pic = pic, scz = scz)
    } else .(ic = NA_real_, pic = NA_real_, scz = NA_real_)
  }, by = Date]
  rank_ic <- mean(ic_by$ic, na.rm = TRUE)
  icir <- rank_ic / sd(ic_by$ic, na.rm = TRUE)
  ic_t <- rank_ic / (sd(ic_by$ic, na.rm=TRUE)/sqrt(sum(!is.na(ic_by$ic))))
  size_partial_ic <- mean(ic_by$pic, na.rm = TRUE)
  size_corr <- mean(ic_by$scz, na.rm = TRUE)

  d_ew <- cs$diag_ew_universe; d_ct <- cs$diag_cap_tier
  results[[f]] <- list(
    factor = f, n_months = cs$n_months,
    capw_port_t = cs$portfolio_alpha_t_nw_lag3,
    capw_port_p = cs$portfolio_alpha_t_pvalue,
    capw_IR = cs$information_ratio, net_sr = cs$net_sr,
    alpha_ann = cs$alpha_annualized, turnover_annual = cs$turnover_annual,
    mean_active_net = cs$mean_active_net,
    port_t_pre2017 = nw_port_t(pre), port_t_post2017 = nw_port_t(post),
    n_pre = nrow(pre), n_post = nrow(post),
    oos_retention_capw = oos_ret_v2(active),
    rank_ic = rank_ic, icir = icir, ic_t = ic_t,
    size_partial_ic = size_partial_ic, size_corr = size_corr,
    diag_ew_universe = d_ew, diag_cap_tier = d_ct
  )
  cat(sprintf("    capw_PORT_t=%.3f | EWuni_PORT_t=%s | rank_ic=%.4f (t=%.2f) | size_pic=%.4f size_corr=%.3f | post2017_t=%.2f | oos=%.2f\n",
      cs$portfolio_alpha_t_nw_lag3 %||% NA,
      if (!is.null(d_ew$portfolio_alpha_t_nw_lag3)) round(d_ew$portfolio_alpha_t_nw_lag3,3) else "NA",
      rank_ic, ic_t, size_partial_ic, size_corr,
      nw_port_t(post) %||% NA, oos_ret_v2(active) %||% NA))
}
write_json(results, file.path(STAGE, "results_main.json"), auto_unbox = TRUE, pretty = TRUE, na = "null")
# tidy summary table
summ <- rbindlist(lapply(results, function(r) data.table(
  factor = r$factor, n = r$n_months,
  capw_PORT_t = round(r$capw_port_t,3),
  EWuni_PORT_t = round(r$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA,3),
  post2017_t = round(r$port_t_post2017,3),
  oos_capw = round(r$oos_retention_capw,3),
  rank_ic = round(r$rank_ic,4), ic_t = round(r$ic_t,2),
  size_pic = round(r$size_partial_ic,4), size_corr = round(r$size_corr,3),
  net_sr = round(r$net_sr,3), turn = round(r$turnover_annual,2))), fill = TRUE)
fwrite(summ, file.path(STAGE, "summary_main.csv"))
cat("\n===== SUMMARY =====\n"); print(summ)
cat("[DONE measure_main]\n")
