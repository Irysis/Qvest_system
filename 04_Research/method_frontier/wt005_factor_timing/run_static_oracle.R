# WT-D20260718_005 — Static base + Oracle ceiling (decisive HKS/Arnott prior test)
# Static EW family composite vs single-family vs perfect-foresight rotation ceiling.
# All via canonical_screen_bt (top-25 EW long-only, cap-w KOSPI200 benchmark, 15bps).
suppressMessages({library(data.table); library(arrow); library(PerformanceAnalytics); library(xts)})
setDTthreads(1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=root); setwd(root)
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "04_Research/method_frontier/wt005_factor_timing"

FAM <- as.data.table(read_parquet(file.path(OUT,"family_z_panel.parquet"))); FAM[, Date:=as.Date(Date)]
Rg  <- as.data.table(read_parquet(file.path(OUT,"grid_returns.parquet"))); Rg[, Date:=as.Date(Date)]
BMg <- as.data.table(read_parquet(file.path(OUT,"grid_bench.parquet"))); BMg[, Date:=as.Date(Date)]
LQg <- as.data.table(read_parquet(file.path(OUT,"grid_liq.parquet"))); LQg[, Date:=as.Date(Date)]
fams <- c("value","quality","momentum","low_vol","size","dividend")
size_dt <- FAM[, .(Date, Ticker, size=Size)]

canon <- function(score_dt){
  S <- score_dt[!is.na(score), .(Date,Ticker,score)]
  S <- S[Date %in% Rg$Date]
  canonical_screen_bt(S, Rg, BMg, top_n=25L, cost_bps_oneway=15,
                      liq_dt=LQg, liq_min=2e8, run_id="wt005", strategy_id="wt005",
                      periods_per_year=12L, diag_dual_basis=TRUE, size_dt=size_dt)
}
calmar_of <- function(pr){  # pr: data.table(date, ret_net)
  x <- xts(pr$ret_net, order.by=as.Date(pr$date))
  n <- nrow(x); ann <- prod(1+coredata(x))^(12/n)-1
  mdd <- as.numeric(maxDrawdown(x)); if(!is.finite(mdd)||mdd<=0) return(NA_real_)
  ann/mdd
}
summ <- function(res, label){
  pr <- res$period_returns
  data.table(strategy=label, n=res$n_months,
             port_t=round(res$portfolio_alpha_t_nw_lag3,3),
             pval=round(res$portfolio_alpha_t_pvalue,4),
             IR=round(res$information_ratio,3),
             net_sr=round(res$net_sr,3),
             calmar=round(calmar_of(pr),3),
             turn=round(res$turnover_annual,2),
             ew_uni_t=round(tryCatch(res$diag_ew_universe$portfolio_alpha_t_nw_lag3,error=function(e)NA),3))
}

# ---- static EW composite ----
FAM[, score_ew := rowMeans(.SD, na.rm=TRUE), .SDcols=fams]
res_ew <- canon(FAM[, .(Date,Ticker,score=score_ew)])
cat("static EW done. port_t=", round(res_ew$portfolio_alpha_t_nw_lag3,3), "\n")

# ---- single family portfolios (also give per-month net returns for oracle) ----
per_fam_pr <- list(); rows <- list(); rows[["static_EW"]] <- summ(res_ew, "static_EW_composite")
for (fk in fams) {
  r <- canon(FAM[, .(Date,Ticker,score=get(fk))])
  per_fam_pr[[fk]] <- r$period_returns[, .(date, ret_net)]
  rows[[fk]] <- summ(r, paste0("single_",fk))
  cat("single", fk, "port_t=", round(r$portfolio_alpha_t_nw_lag3,3), "\n")
}

# ---- oracle rotation ceiling: each month hold winner family's top-25 (look-ahead upper bound) ----
M <- Reduce(function(a,b) merge(a,b,by="date"), lapply(names(per_fam_pr), function(fk){
  x <- per_fam_pr[[fk]]; setnames(x, "ret_net", fk); x }))
bm <- BMg[, .(date=Date, benchmark_ret=BM_Ret)]
M <- merge(M, bm, by="date")
retmat <- as.matrix(M[, ..fams])
M[, oracle_ret := apply(retmat, 1, max)]
active_oracle <- M$oracle_ret - M$benchmark_ret
port_t_oracle <- .nw_t_mean(active_oracle, lag=3)
net_sr_oracle <- mean(active_oracle)/sd(active_oracle)*sqrt(12)
calmar_oracle <- calmar_of(M[, .(date, ret_net=oracle_ret)])
rows[["oracle_rotation"]] <- data.table(strategy="ORACLE_rotation(lookahead_ceiling)", n=length(active_oracle),
  port_t=round(port_t_oracle,3), pval=NA, IR=NA, net_sr=round(net_sr_oracle,3),
  calmar=round(calmar_oracle,3), turn=NA, ew_uni_t=NA)

# best-static-family = highest full-sample port_t among singles
tab <- rbindlist(rows, use.names=TRUE, fill=TRUE)
print(tab)
fwrite(tab, file.path(OUT,"static_oracle_summary.csv"))
saveRDS(list(res_ew=res_ew, per_fam_pr=per_fam_pr, M=M, tab=tab), file.path(OUT,"static_oracle.rds"))
cat("\n[decision inputs] static_EW port_t=", round(res_ew$portfolio_alpha_t_nw_lag3,3),
    " | oracle_rotation port_t=", round(port_t_oracle,3),
    " | headroom(oracle-static)=", round(port_t_oracle-res_ew$portfolio_alpha_t_nw_lag3,3), "\n")
