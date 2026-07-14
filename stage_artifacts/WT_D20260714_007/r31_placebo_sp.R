## R31 characterization: placebo (value-shuffle N=40) + lag1 PIT stress for SP (sales-yield),
## the only new value definition non-decaying post-2024. Beyond-gate diagnostic (SP fails AND-gate).
## Also EP for comparison. Confirms whether the weak full-period signal is real vs null.
suppressPackageStartupMessages({library(arrow); library(data.table); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260714_007")
source(file.path(QM,"02_Infrastructure/contracts/weighted_screen_bt.R"))
zc <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
cap_norm<-function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20
    if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}
nw_t<-function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<8)return(NA_real_);fit<-lm(x~1)
  se<-sqrt(NeweyWest(fit,lag=lag,prewhite=FALSE)[1,1]);unname(coef(fit)[1]/se)}
W_BLEND<-0.30

PAN <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_004/recon_panels.parquet"))); PAN[,Date:=as.Date(Date)]
SP7 <- as.data.table(read_parquet(file.path(WT,"subaxis_panels.parquet"))); SP7[,Date:=as.Date(Date)]
SI  <- readRDS(file.path(QM,"stage_artifacts/WT_D20260714_004/screen_inputs.rds"))
fwd_ret<-SI$fwd_ret; bench<-SI$bench; liqf<-SI$liqf; SIZE<-SI$SIZE
BR <- readRDS(file.path(WT,"base_ref.rds")); BA<-BR$ba

DT <- merge(PAN[,.(Date,Ticker,`0_stored_S7`)], SP7[,.(Date,Ticker,SP,EP)], by=c("Date","Ticker"), all.x=TRUE)
ST <- SIZE[!is.na(Size),.(Date,Ticker,Size)]; setorder(ST,Date,-Size); ST[,cap_rank:=seq_len(.N),by=Date]
ST[,tier:=fifelse(cap_rank<=10L,"MEGA",fifelse(cap_rank<=30L,"MID","OTHER"))]
DT <- merge(DT, ST[,.(Date,Ticker,tier)], by=c("Date","Ticker"), all.x=TRUE); DT[is.na(tier),tier:="OTHER"]

mk_capw <- function(dt, scorecol){
  S <- merge(dt[is.finite(get(scorecol)),.(Date,Ticker,sc=get(scorecol))], SIZE, by=c("Date","Ticker"))
  S <- merge(S, liqf, by=c("Date","Ticker"), all.x=TRUE); S <- S[is.na(adv)|adv>=2e8]
  dd <- sort(unique(S$Date)); W<-list()
  for(i in seq_along(dd)){d<-dd[i]; sub<-S[Date==d]; if(nrow(sub)<25) next
    setorder(sub,-sc); hd<-head(sub,25); W[[as.character(d)]]<-data.table(Date=d,Ticker=hd$Ticker,w=cap_norm(hd$Size))}
  rbindlist(W)}
paired_of <- function(bdt){
  W<-mk_capw(bdt,"csc"); if(nrow(W)==0) return(NA_real_)
  res<-weighted_screen_bt(W,fwd_ret,bench,cost_bps_oneway=15,run_id="pb",strategy_id="pb")
  pr<-as.data.table(res$period_returns); pr[,active:=ret_net-benchmark_ret]
  m<-merge(pr[,.(date,va=active)],BA,by="date"); nw_t(m$va-m$ba)}
build_csc <- function(valv){
  d<-copy(DT[is.finite(`0_stored_S7`),.(Date,Ticker,tier,b=`0_stored_S7`,v=valv[is.finite(DT$`0_stored_S7`)])])
  d[,b_z:=zc(b),by=Date]; d[,v_z:=zc(v),by=Date]; d[is.na(v_z),v_z:=0]
  d[,v_boost:=fifelse(tier %in% c("MID","OTHER"),v_z,0)]; d[,csc:=(1-W_BLEND)*b_z+W_BLEND*v_boost]
  merge(DT[,.(Date,Ticker)],d[,.(Date,Ticker,csc)],by=c("Date","Ticker"),all.x=TRUE)}

for(sx in c("SP","EP")){
  actual <- paired_of(build_csc(DT[[sx]]))
  ## placebo: shuffle value column within each month, N=40
  set.seed(4703)
  null_p <- numeric(0)
  for(b in 1:40){
    vv <- copy(DT[,.(Date,Ticker,v=get(sx))])
    vv[is.finite(v), v:=sample(v), by=Date]
    bp <- paired_of(build_csc(vv$v))
    if(is.finite(bp)) null_p<-c(null_p,bp)
  }
  p_emp <- mean(null_p >= actual, na.rm=TRUE)
  ## lag1 value-shift stress (PIT C5): shift value by +1 month
  dts<-sort(unique(DT$Date)); vv<-copy(DT[is.finite(get(sx)),.(Date,Ticker,v=get(sx))]); idx<-match(vv$Date,dts)
  vv[,Date:=dts[pmin(idx+1L,length(dts))]]; vv<-unique(vv,by=c("Date","Ticker"))
  d1<-merge(DT[,.(Date,Ticker)],vv,by=c("Date","Ticker"),all.x=TRUE)
  lag1 <- paired_of(build_csc(d1$v))
  cat(sprintf("[%s] actual paired=%.3f | placebo null max=%.3f mean=%.3f p_emp=%.3f | lag1=%.3f\n",
    sx, actual, max(null_p,na.rm=TRUE), mean(null_p,na.rm=TRUE), p_emp, lag1))
  saveRDS(list(subaxis=sx,actual=actual,null=null_p,p_emp=p_emp,lag1=lag1),
    file.path(WT,paste0("placebo_",sx,".rds")))
}
cat("PLACEBO_DONE\n")
