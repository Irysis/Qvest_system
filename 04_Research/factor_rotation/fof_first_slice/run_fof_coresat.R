## run_fof_coresat.R — core-satellite trade-off frontier (메가캡 코어 α + IC-가중 위성)
## w = α·(메가캡 adv-base) + (1-α)·(IC-가중 팩터 틸트). α 0→1. vs cap-weight 지수 full/pre2018/2018+.
## 질문: 팩터알파(pre-2018강·2018+약) vs 메가캡추종(pre약·2018+강) 사이 최적 α가 졸업급 frontier 만드나?
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_coresat.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
w("================ core-satellite frontier ================"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(date=as.Date(Date),tic=Ticker,Ret=Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(date=as.Date(Date),BM=BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(date=as.Date(Date),tic=Ticker,adv)]
FIC<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC,factor_id,Date)
FIC[,tt:=shift(frollmean(ic,12L,na.rm=TRUE),1L),by=factor_id]; tic<-FIC[,.(signal_date=Date,factor_id,tic=tt)]
x<-merge(sc,tic,by=c("signal_date","factor_id")); x<-x[is.finite(tic)]; x[,wf:=pmax(tic,0)]
S<-x[,.(score=if(sum(wf)>0) sum(wf*nz)/sum(wf) else mean(nz)),by=.(signal_date,security_id)]; S[,score:=zc(score),by=signal_date]
setnames(S,c("signal_date","security_id"),c("date","tic"))
P<-merge(S, ret_dt, by=c("date","tic")); P<-merge(P, liq_dt, by=c("date","tic")); P<-P[adv>=2e8]

## w_sat = IC-가중 팩터 top-25 EW (알파 위성)
sat<-P[, .SD[frank(-score,ties.method="first")<=25], by=date][, .(date,tic,w_sat=1/25)]
## w_core = adv-weight top-100 (메가캡 코어)
cor<-P[, .SD[frank(-adv,ties.method="first")<=100], by=date]; cor[, w_core:=adv/sum(adv), by=date]; cor<-cor[,.(date,tic,w_core)]
B<-merge(sat, cor, by=c("date","tic"), all=TRUE); B[is.na(w_sat),w_sat:=0]; B[is.na(w_core),w_core:=0]
B<-merge(B, ret_dt, by=c("date","tic")); B<-merge(B, bench_dt, by="date")

perf<-function(BW){
  g<-BW[,.(g=sum(wg*Ret,na.rm=TRUE)),by=date]
  WW<-dcast(BW, date~tic, value.var="wg", fill=0); setorder(WW,date); M<-as.matrix(WW[,-1])
  to<-c(NA, rowSums(abs(diff(M)))); g[, net:=g-0.0015*ifelse(is.na(to),0,to)]
  g<-merge(g, unique(BW[,.(date,BM)]), by="date"); g[, act:=net-BM]; setorder(g,date)
  pt<-function(from=NULL,to_=NULL){ a<-g; if(!is.null(from)) a<-a[date>=as.Date(from)]; if(!is.null(to_)) a<-a[date<as.Date(to_)]
    if(nrow(a)<12) return(NA); f<-lm(act~1,data=a); as.numeric(coeftest(f,vcov=sandwich::NeweyWest(f,lag=3,prewhite=FALSE))[1,3]) }
  list(full=pt(), pre=pt(NULL,"2018-01-01"), y18=pt("2018-01-01"), sr=mean(g$act)/sd(g$act)*sqrt(12), to=mean(to,na.rm=T)) }
w("\n=== α(메가캡 코어 비중) frontier (vs cap-weight 지수) ===")
tab<-data.table()
for(a in c(0,0.2,0.3,0.4,0.5,0.6,0.7,0.8,1.0)){ BW<-copy(B); BW[, wg:= a*w_core+(1-a)*w_sat]; BW<-BW[wg>0]; BW[, wg:=wg/sum(wg), by=date]
  m<-perf(BW); tab<-rbind(tab,data.table(alpha=a,full=m$full,pre2018=m$pre,y2018p=m$y18,net_SR=m$sr,to=round(100*m$to)))
  w(sprintf("  α=%.1f (코어%.0f%%): full=%+.2f | pre2018=%+.2f | 2018+=%+.2f | net_SR=%+.3f | TO=%d%%", a,100*a,m$full,m$pre,m$y18,m$sr,round(100*m$to))) }
w("\n  → full AND 2018+ 둘 다 양수·높은 α가 frontier 최적. 둘 다 졸업급(>2)인 α 있나?")
fwrite(tab,file.path(OUT,"coresat_results.csv"))
cat("CORESAT|", paste(sprintf("a%.1f:full%.2f/18p%.2f/sr%.2f",tab$alpha,tab$full,tab$y2018p,tab$net_SR),collapse=" "),"\n")
close(con); cat("FOF_CORESAT_DONE\n")
