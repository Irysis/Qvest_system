suppressMessages({library(arrow);library(data.table)})
STAGE<-"stage_artifacts/WT-D20260705_009"; P<-file.path(STAGE,"panel")
fc<-as.data.table(read_parquet(file.path(STAGE,"forecast_dist.parquet")))
ret<-as.data.table(read_parquet(file.path(P,"returns_monthly.parquet")))
uf<-as.data.table(read_parquet(file.path(P,"universe_flags.parquet")))
bm<-as.data.table(read_parquet(file.path(P,"benchmark_monthly.parquet")))
for(x in list(fc,ret,uf,bm)) x[,Date:=as.Date(cut(as.Date(Date),"month"))]
d<-merge(fc[,.(Date,Ticker,mu_hat,sigma_hat)], ret[,.(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
d<-merge(d, uf[,.(Date,Ticker,adv=adv20)], by=c("Date","Ticker"), all.x=TRUE)
d<-d[(is.na(adv)|adv>=5e7) & is.finite(mu_hat)&is.finite(Ret_1m)]
bmv<-bm[,.(Date,BM_Ret)]

# (1) full-universe rank-IC of mu_hat vs top-half-only rank-IC (long-only relevant region)
icf<-d[,.(ic=cor(mu_hat,Ret_1m,method="spearman")),by=Date][is.finite(ic)]
d[, med:=median(mu_hat), by=Date]
icTop<-d[mu_hat>=med, .(ic=cor(mu_hat,Ret_1m,method="spearman")),by=Date][is.finite(ic)]
cat(sprintf("rank-IC FULL:  mean=%.4f t=%.2f\n", mean(icf$ic), mean(icf$ic)/sd(icf$ic)*sqrt(nrow(icf))))
cat(sprintf("rank-IC TOP-HALF only: mean=%.4f t=%.2f  (long-only relevant ordering)\n",
   mean(icTop$ic), mean(icTop$ic)/sd(icTop$ic)*sqrt(nrow(icTop))))

# (2) GROSS vs NET top-25 active PORT (mechanism: is turnover the killer?)
topN<-25L
armgross<-function(scorecol){
  s<-copy(d); s[,sc:=get(scorecol)]
  w<-s[order(Date,-sc)][, .(Ticker=Ticker[1:min(topN,.N)], w=1/min(topN,.N)), by=Date]
  wr<-merge(w,s[,.(Date,Ticker,Ret_1m)],by=c("Date","Ticker"))
  port<-wr[,.(g=sum(w*Ret_1m)),by=Date]
  # turnover
  dts<-sort(unique(w$Date)); prev<-data.table(Ticker=character(),w=numeric()); tr<-numeric(length(dts))
  for(i in seq_along(dts)){cur<-w[Date==dts[i],.(Ticker,w)];m<-merge(cur,prev,by="Ticker",all=TRUE,suffixes=c("_c","_p"));m[is.na(w_c),w_c:=0];m[is.na(w_p),w_p:=0];tr[i]<-sum(abs(m$w_c-m$w_p));prev<-cur}
  port[,traded:=tr[match(as.character(Date),as.character(dts))]]
  port<-merge(port,bmv,by="Date")
  port[,act_gross:=g-BM_Ret]; port[,act_net:=g-traded*15/1e4-BM_Ret]
  nwt<-function(v,lag=3){v<-v[is.finite(v)];n<-length(v);mu<-mean(v);e<-v-mu;g0<-sum(e^2)/n;vv<-g0;for(l in 1:lag){w<-1-l/(lag+1);vv<-vv+2*w*sum(e[(l+1):n]*e[1:(n-l)])/n};mu/sqrt(vv/n)}
  list(gross_ann=mean(port$act_gross)*12, net_ann=mean(port$act_net)*12,
       t_gross=nwt(port$act_gross), t_net=nwt(port$act_net), TO=mean(port$traded)*12)
}
cat("\n=== Top25 GROSS vs NET (mechanism) ===\n")
for(sc in c("mu_hat")){
  r<-armgross(sc)
  cat(sprintf("ArmA(%s): gross_active_ann=%.4f (t=%.2f) | net_active_ann=%.4f (t=%.2f) | TO=%.1fx\n",
    sc, r$gross_ann, r$t_gross, r$net_ann, r$t_net, r$TO))
}
d[,fir:=mu_hat/sigma_hat]
r<-armgross("fir")
cat(sprintf("ArmB(mu/sig): gross_active_ann=%.4f (t=%.2f) | net_active_ann=%.4f (t=%.2f) | TO=%.1fx\n",
  r$gross_ann, r$t_gross, r$net_ann, r$t_net, r$TO))
