suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
TMP <- "C:/Users/99922/AppData/Local/Temp/claude"
pl <- readRDS(file.path(TMP,"wt008_pl.rds")); setDT(pl)
b <- as.data.table(read_parquet(".cache/benchmark.parquet")); b[, Date:=as.Date(Date)]; b[, ym:=format(Date,"%Y-%m")]
setorder(b,Date); bm_me <- b[, .(bmclose=last(BM_Close)), by=ym]; setorder(bm_me,ym)
bm_me[, bm_ret_m := bmclose/shift(bmclose)-1]; bm_me[, fwd_bm := shift(bm_ret_m,-1)]
# flag glitch forward-bench months
bm_me[, glitch := abs(fwd_bm)>0.20]
pl <- merge(pl, bm_me[,.(ym,fwd_bm,glitch)], by="ym", all.x=TRUE)
pl <- pl[!is.na(fwd_bm)&is.finite(fwd_bm)&!is.na(fwd_ret)]
cat("glitch fwd-bench months in sample:", uniqueN(pl[glitch==TRUE]$ym), "\n\n")

run <- function(d, col, label){
  d<-d[!is.na(get(col))&is.finite(get(col))]
  sc<-d[,.(Date=me_date,Ticker,score=get(col))];rr<-d[,.(Date=me_date,Ticker,Ret_1m=fwd_ret)];bd<-unique(d[,.(Date=me_date,BM_Ret=fwd_bm)])
  r<-tryCatch(canonical_screen_bt(sc,rr,bd,top_n=25L,cost_bps_oneway=15),error=function(e)NULL); if(is.null(r))return()
  cat(sprintf("%-30s | PORT_t=%+.2f netSR=%+.2f alpha=%+.2f%% n=%d\n",label,r$portfolio_alpha_t_nw_lag3,r$net_sr,r$alpha_annualized*100,r$n_months))
}
cat("=== A/F with glitch-bench months REMOVED (adversarial robustness) ===\n")
plc <- pl[glitch==FALSE]
run(plc, "z_basis_pct", "A: richest basis (clean bench)")
plc[, negoi:=-z_oi_chg]
plcx <- copy(plc); plcx[, rk:=frank(z_basis_pct)/.N, by=ym]
run(plcx[rk>0.20], "adv_m", "F: liq EXCL cheap basis (clean)")
# also EW all-names benchmark-free: is the top-quintile even beating equal-weight universe?
cat("\n=== EW-universe-relative (no external bench): top-25 basis vs EW-all avg ===\n")
d <- plc[!is.na(z_basis_pct)]
d[, ewuni := mean(fwd_ret), by=ym]  # equal-weight universe return that month
setorder(d, ym, -z_basis_pct)
top <- d[, head(.SD,25), by=ym]
act <- top[, .(a=mean(fwd_ret)-mean(ewuni)), by=ym]  # active vs EW universe
cat(sprintf("top-25 basis active vs EW-universe: mean=%+.3f%%/mo  t=%+.2f (n=%d)\n",
  mean(act$a)*100, mean(act$a)/sd(act$a)*sqrt(nrow(act)), nrow(act)))
