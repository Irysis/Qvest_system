suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
TMP <- "C:/Users/99922/AppData/Local/Temp/claude"
pl <- readRDS(file.path(TMP,"wt008_pl.rds")); setDT(pl); setorder(pl, Ticker, ym)
b <- as.data.table(read_parquet(".cache/benchmark.parquet")); b[, Date:=as.Date(Date)]; b[, ym:=format(Date,"%Y-%m")]
setorder(b,Date); bm_me <- b[, .(bmclose=last(BM_Close)), by=ym]; setorder(bm_me,ym)
bm_me[, bm_ret_m := bmclose/shift(bmclose)-1]; bm_me[, fwd_bm := shift(bm_ret_m,-1)]
pl <- merge(pl, bm_me[,.(ym,fwd_bm)], by="ym", all.x=TRUE)
pl <- pl[!is.na(fwd_bm)&is.finite(fwd_bm)&!is.na(fwd_ret)]

# smoothed basis (3M mean) to cut turnover
pl[, basis_3m := frollmean(basis_pct, 3, align="right"), by=Ticker]
wins<-function(x,k=3){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);pmin(pmax(x,m-k*s),m+k*s)}
pl[, z_basis_3m := wins(basis_3m), by=ym]
# lag-1 extra: signal from t-1 (PIT robustness / look-ahead check)
pl[, z_basis_lag1 := shift(z_basis_pct,1), by=Ticker]

run <- function(d, col, label){
  d <- d[!is.na(get(col))&is.finite(get(col))]
  sc<-d[,.(Date=me_date,Ticker,score=get(col))]; rr<-d[,.(Date=me_date,Ticker,Ret_1m=fwd_ret)]
  bd<-unique(d[,.(Date=me_date,BM_Ret=fwd_bm)])
  r<-tryCatch(canonical_screen_bt(sc,rr,bd,top_n=25L,cost_bps_oneway=15),error=function(e){cat("ERR",label,e$message,"\n");NULL})
  if(is.null(r))return()
  cat(sprintf("%-26s | PORT_t=%+.2f netSR=%+.2f alpha=%+.2f%% TO=%.0f%% n=%d\n",
    label,r$portfolio_alpha_t_nw_lag3,r$net_sr,r$alpha_annualized*100,r$turnover_annual*100,r$n_months))
}
cat("=== Robustness: turnover reduction + look-ahead lag check ===\n")
run(pl, "z_basis_pct",  "raw basis (monthly)")
run(pl, "z_basis_3m",   "basis 3M-smoothed")
run(pl, "z_basis_lag1", "basis lag-1 (PIT check)")

# rank-IC of lag-1 (if signal survives extra lag, not look-ahead)
d <- pl[!is.na(z_basis_lag1)]
ic <- d[, .(ic=cor(z_basis_lag1, fwd_ret, method="spearman"),n=.N), by=ym][n>=20]
cat(sprintf("\nlag-1 basis rank-IC: mean=%+.4f  t=%+.2f (n=%d)  [raw basis IC was +0.045 t+5.5]\n",
  mean(ic$ic), mean(ic$ic)/sd(ic$ic)*sqrt(nrow(ic)), nrow(ic)))
