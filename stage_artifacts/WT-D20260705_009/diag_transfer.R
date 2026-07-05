suppressMessages({library(arrow);library(data.table)})
STAGE<-"stage_artifacts/WT-D20260705_009"; P<-file.path(STAGE,"panel")
fc<-as.data.table(read_parquet(file.path(STAGE,"forecast_dist.parquet")))
ret<-as.data.table(read_parquet(file.path(P,"returns_monthly.parquet")))
uf<-as.data.table(read_parquet(file.path(P,"universe_flags.parquet")))
for(d in list(fc,ret,uf)) d[,Date:=as.Date(cut(as.Date(Date),"month"))]
d<-merge(fc[,.(Date,Ticker,mu_hat,sigma_hat)], ret[,.(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
d<-merge(d, uf[,.(Date,Ticker,adv=adv20)], by=c("Date","Ticker"), all.x=TRUE)
# apply same liquidity filter as canonical (adv>=5e7 or NA passes)
d<-d[is.na(adv) | adv>=5e7]
d<-d[is.finite(mu_hat)&is.finite(Ret_1m)]

# forward return by mu_hat decile (cross-sectional per month), EW, then mean active vs benchmark-free
d[, dec := as.integer(cut(frank(mu_hat)/.N, breaks=seq(0,1,.1), labels=1:10, include.lowest=TRUE)), by=Date]
dec_ret <- d[, .(mean_ret=mean(Ret_1m), n=.N), by=.(Date,dec)][, .(mean_ret=mean(mean_ret)), by=dec][order(dec)]
cat("=== mu_hat DECILE forward return (EW, monthly mean) ===\n")
print(dec_ret)
# top-25 specifically: what's mean fwd ret of the top-25-by-mu vs top-25-by-mu/sigma each month?
topN<-25L
tA <- d[order(Date,-mu_hat)][, .SD[1:min(topN,.N)], by=Date][, .(retA=mean(Ret_1m), sig=mean(sigma_hat), advm=median(adv,na.rm=TRUE)), by=Date]
d[, fir := mu_hat/sigma_hat]
tB <- d[order(Date,-fir)][, .SD[1:min(topN,.N)], by=Date][, .(retB=mean(Ret_1m), sig=mean(sigma_hat), advm=median(adv,na.rm=TRUE)), by=Date]
cat(sprintf("\nTop25-by-mu:     mean fwd ret=%.4f  mean sigma_hat=%.4f  median adv(bn)=%.2f\n",
   mean(tA$retA), mean(tA$sig), median(tA$advm,na.rm=TRUE)/1e9))
cat(sprintf("Top25-by-mu/sig: mean fwd ret=%.4f  mean sigma_hat=%.4f  median adv(bn)=%.2f\n",
   mean(tB$retB), mean(tB$sig), median(tB$advm,na.rm=TRUE)/1e9))
# does Arm B actually pick lower-sigma names? (mechanism sanity)
cat(sprintf("\nmean sigma of full universe=%.4f  ArmA-selected=%.4f  ArmB-selected=%.4f\n",
   mean(d$sigma_hat), mean(tA$sig), mean(tB$sig)))
# benchmark mean monthly
bm<-as.data.table(read_parquet(file.path(P,"benchmark_monthly.parquet"))); bm[,Date:=as.Date(cut(as.Date(Date),"month"))]
bm<-bm[Date%in%tA$Date]
cat(sprintf("benchmark mean monthly fwd ret=%.4f  => ArmA active=%.4f  ArmB active=%.4f\n",
   mean(bm$BM_Ret), mean(tA$retA)-mean(bm$BM_Ret), mean(tB$retB)-mean(bm$BM_Ret)))
