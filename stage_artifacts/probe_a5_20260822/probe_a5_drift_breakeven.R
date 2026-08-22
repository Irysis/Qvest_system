## probe_a5_drift_breakeven.R — A5 실제 계열(drift)의 위상평균 손익분기 확정
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
OUTD<-"stage_artifacts/probe_a5_20260822"
IRf<-function(x){x<-x[is.finite(x)];mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
load_mon<-function(path){ R<-as.data.table(read_parquet(path)); R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
  fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market")); R[,ym:=format(Date,"%Y-%m")]
  mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),.(medate=max(Date))),by=ym,.SDcols=c("Market",fac)]
  setorder(mon,medate); list(mon=mon,fac=fac) }
BR<-load_mon("outputs/ramp/dfa_index_returns_broad_202608.parquet")
mon<-BR$mon; fac<-BR$fac; NM<-nrow(mon); NAx<-1+length(fac)
S12<-matrix(NA_real_,NM,length(fac)); for(fi in seq_along(fac)){f<-fac[fi]
  for(m in 12:NM){w<-(m-11):m; S12[m,fi]<-prod(1+mon[[f]][w])/prod(1+mon$Market[w])-1}}
runD<-function(bps,freq,phase,start_m=13){   # A5 원판 = drift
  pr<-rep(NA_real_,NM); gr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM)
  wprev<-rep(1/NAx,NAx); wcur<-NULL
  for(m in start_m:NM){ d<-m-1
    if(is.null(wcur)||((m-start_m-phase)%%freq==0)){ s<-S12[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
      if(!length(pos))w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]); wcur<-w }
    ri<-unlist(mon[m,c("Market",fac),with=FALSE]); ri[!is.finite(ri)]<-0
    dlt<-sum(abs(wcur-wprev)); tov[m]<-dlt; gr[m]<-sum(wcur*ri); pr[m]<-gr[m]-(bps/1e4)*dlt
    wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev }
  k<-is.finite(pr); mk<-mon$Market[k]
  list(pt=nwt(pr[k]-mk),IR=IRf(pr[k]-mk),mean=mean(pr[k]-mk)*12,gmean=mean(gr[k]-mk)*12,
       gsd=sd(gr[k]-mk)*sqrt(12),TO=mean(tov[k])*12) }
cat("=== drift 계열 위상평균 손익분기 (freq1 vs freq3) ===\n")
R<-list()
for(b in c(0,5,10,15,20,25,26,27,30,40)){
  f1<-runD(b,1,0); f3<-lapply(0:2,function(p)runD(b,3,p))
  R[[length(R)+1]]<-data.table(bps=b,f1_pt=f1$pt,f3_pt_avg=mean(sapply(f3,`[[`,"pt")),
    f3_pt_p0=f3[[1]]$pt,f3_pt_p1=f3[[2]]$pt,f3_pt_p2=f3[[3]]$pt,
    f1_mean=f1$mean,f3_mean_avg=mean(sapply(f3,`[[`,"mean")),
    f1_IR=f1$IR,f3_IR_avg=mean(sapply(f3,`[[`,"IR")),
    f1_TO=f1$TO,f3_TO_avg=mean(sapply(f3,`[[`,"TO"))) }
R<-rbindlist(R); R[,`:=`(d_pt=f3_pt_avg-f1_pt,d_mean=f3_mean_avg-f1_mean,d_IR=f3_IR_avg-f1_IR)]
print(R[,.(bps,f1_pt,f3_pt_avg,f3_pt_p0,f3_pt_p1,f3_pt_p2,d_pt,d_mean,d_IR)],digits=4)
g<-runD(0,1,0); g3<-mean(sapply(0:2,function(p)runD(0,3,p)$gmean)); t3<-mean(sapply(0:2,function(p)runD(0,3,p)$TO))
cat(sprintf("\n  drift: dGross(freq1->3, 위상평균) = %.4f%%/yr · dTO = %.4f\n",(g3-g$gmean)*100,g$TO-t3))
cat(sprintf("  ★손익분기 = %.1f bps one-way (15bps 가정의 %.2f배)\n",(g$gmean-g3)/(g$TO-t3)*1e4,(g$gmean-g3)/(g$TO-t3)*1e4/15))
cat(sprintf("  15bps 에서 위상평균 d_pt = %+.4f  (A5 phase0 실측 d_pt = %+.4f)\n",
  R[bps==15]$d_pt, R[bps==15]$f3_pt_p0-R[bps==15]$f1_pt))
fwrite(R,file.path(OUTD,"p8_drift_breakeven.csv"))
cat("\nDRIFT_BREAKEVEN_DONE\n")
