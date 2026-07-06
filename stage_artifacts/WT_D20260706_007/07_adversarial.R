suppressMessages({library(data.table)})
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260706_007")
log <- function(...) cat(format(Sys.time(),"%H:%M:%S"), ..., "\n")
E <- readRDS(file.path(OUT,"experiment_results.rds"))
fwd <- E$fwd; bm2 <- E$bm2
nwt <- function(a){n<-length(a); if(n<12) return(NA_real_); m<-mean(a); ac<-acf(a,lag.max=3,plot=FALSE,demean=TRUE)$acf[2:4]; s2<-var(a)/n*(1+2*sum((1-(1:3)/n)*ac)); if(!is.finite(s2)||s2<=0) return(NA_real_); m/sqrt(s2)}

log("== C1: short-side via top-25 vs bottom-25 NAMES (matches top-25 deployment) ==")
ss <- function(sc, from=NULL){
  d <- fwd[is.finite(get(sc))]; if(!is.null(from)) d<-d[ym>=from]
  d[, s := get(sc)]
  top <- d[order(Date,-s)][, .SD[1:min(25,.N)], by=Date][, .(ret=mean(fwd_mret)), by=Date]
  bot <- d[order(Date, s)][, .SD[1:min(25,.N)], by=Date][, .(ret=mean(fwd_mret)), by=Date]
  top <- merge(top, bm2, by="Date"); bot <- merge(bot, bm2, by="Date")
  top[, a:=ret-BM_Ret]; bot[, a:=ret-BM_Ret]
  data.table(long_t25_t=round(nwt(top$a),2), long_ann=round(mean(top$a)*1200,1),
             short_b25_t=round(nwt(-bot$a),2), short_ann=round(mean(-bot$a)*1200,1))
}
cat("value full :\n"); print(cbind(win="full", ss("val_z")))
cat("value 2017+:\n"); print(cbind(win="2017", ss("val_z",201701L)))

log("\n== C2: lag-1 stress on spread condition (extra 1M lag) ==")
spr <- E$spr[order(ym)]
spr[, exp_pctile_lag1 := shift(exp_pctile, 1)]
cond <- unique(fwd[,.(ym,Date)]); cond <- merge(cond, spr[,.(ym,exp_pctile,exp_pctile_lag1)], by="ym")
A <- as.data.table(E$A_val$period_returns); A[, active := ret_net-benchmark_ret]
A <- merge(A, cond[,.(Date,exp_pctile,exp_pctile_lag1)], by.x="date", by.y="Date")
for(lg in c("exp_pctile","exp_pctile_lag1")){
  A[, on := get(lg)>=0.80]; A[is.na(on), on:=FALSE]
  cond_active <- ifelse(A$on, A$active, 0)
  cat(sprintf("  %-18s cond PORT_t=%.3f  mean_active=%+.4f frac_on=%.2f\n", lg, nwt(cond_active), mean(cond_active), mean(A$on)))
}

log("\n== C3: is rank-IC long-side or short-side? (IC within cheap-half vs expensive-half) ==")
half_ic <- function(from=NULL){
  d <- fwd[is.finite(val_z)]; if(!is.null(from)) d<-d[ym>=from]
  d[, med := median(val_z), by=ym]
  cheap <- d[val_z>=med]; exp_ <- d[val_z<med]
  ic_c <- cheap[, .(ic=if(.N>=8) cor(val_z,fwd_mret,method="spearman") else NA), by=ym][is.finite(ic)]
  ic_e <- exp_[,  .(ic=if(.N>=8) cor(val_z,fwd_mret,method="spearman") else NA), by=ym][is.finite(ic)]
  data.table(cheap_half_ic_t=round(mean(ic_c$ic)/(sd(ic_c$ic)/sqrt(nrow(ic_c))),2),
             exp_half_ic_t=round(mean(ic_e$ic)/(sd(ic_e$ic)/sqrt(nrow(ic_e))),2),
             cheap_mean=round(mean(ic_c$ic),4), exp_mean=round(mean(ic_e$ic),4))
}
cat("full :\n"); print(half_ic())
cat("2017+:\n"); print(half_ic(201701L))
log("[done]")
