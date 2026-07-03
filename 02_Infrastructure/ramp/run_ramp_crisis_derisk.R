## run_ramp_crisis_derisk.R — RAMP Gate8 인베스터 crisis 디리스크 (헌법 §3.5/Gate8 sum(a)≤1 허용).
## AR+MSM_quarterly best 위에 soft 위기 membership → exposure 스칼라(현금화). 위기 폭락 회피 = crisis alpha.
## 세 게이트 동시 공략(calmar=MDD / oos=폭락회피 / pt=음의tail제거). PIT: 위기membership_t는 ≤t 데이터(AR 63d·MSM expanding).
## ★마이닝 회피: crisis 현금수준 {1.0=baseline, 0.5, 0.3} 원리적 고정값만(타겟 스윕 X). weighted_screen_bt(exposure_dt) 경유.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R"); source("02_Infrastructure/contracts/backtest_result_contract.R")
suppressMessages({library(sandwich);library(lmtest)})
con<-file(".cache/_ramp_derisk.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)
PG<-".cache/_dr_prog.txt"; cat("start\n",file=PG); pg<-function(...)cat(sprintf(...),file=PG,append=TRUE)
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}

g<-as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet")); g[,signal_date:=as.Date(signal_date)]
gw<-dcast(g,signal_date+security_id~family,value.var="group_z"); grp<-setdiff(names(gw),c("signal_date","security_id"))
.need<-c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata<-as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
sig_dates<-sort(unique(g$signal_date)); fwd<-build_monthly_forward_returns(rawdata,sig_dates)
fwd_ret<-fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)]; bench<-fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)]; liq<-fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
## AR + MSM soft membership
ARDT<-as.data.table(read_parquet("outputs/ramp/absorption_ratio_signal.parquet")); ARDT[,signal_date:=as.Date(signal_date)]
msm<-as.data.table(read_parquet(".cache/msm_daily_latest.parquet")); msm[,Date:=as.Date(Date)]; msm[,ym:=format(Date,"%Y-%m")]
msmm<-msm[,.(cp=last(Crisis_Prob)),by=ym]; msmm[,me:=as.Date(sapply(as.Date(paste0(ym,"-01")),function(d)as.character(seq(d,by="month",length.out=2)[2]-1)))]
A<-merge(ARDT[,.(signal_date,ar_z)],msmm[,.(signal_date=me,cp)],by="signal_date",all.x=TRUE); A[is.na(cp),cp:=mean(A$cp,na.rm=T)]
A[,cp_z:=0]; for(i in seq_len(nrow(A))){p<-A$cp[1:i];p<-p[is.finite(p)];if(length(p)>=12){s<-sd(p);if(!is.na(s)&&s>1e-8)A$cp_z[i]<-(A$cp[i]-mean(p))/s}}
anc<-c(risk_on=-1,neutral=0,crisis=1); softmem<-function(z){e<-exp(anc*z/1.0);e/sum(e)}
z<-0.5*A$ar_z+0.5*A$cp_z; mm<-t(sapply(z,softmem))
MEM<-data.table(signal_date=A$signal_date,w_risk_on=mm[,1],w_neutral=mm[,2],w_crisis=mm[,3]); states<-c("risk_on","neutral","crisis")
ic<-merge(g[,.(signal_date,security_id,family,group_z)],fwd$returns_dt[,.(signal_date=as.Date(Date),security_id=Ticker,Ret_1m)],by=c("signal_date","security_id"))
gic0<-ic[,.(ic=if(.N>=10&&sd(group_z)>0&&sd(Ret_1m)>0)cor(group_z,Ret_1m,method="spearman")else NA_real_),by=.(signal_date,family)]
gic<-merge(gic0,MEM,by="signal_date"); setorder(gic,family,signal_date)
pg("setup done\n")
## AR+MSM score (monthly) → quarterly
rows<-list()
for(d in as.character(sig_dates)){dd<-as.Date(d);mt<-MEM[signal_date==dd]
  wts<-sapply(grp,function(fm){sub<-gic[family==fm&signal_date<dd];sub<-sub[is.finite(ic)];if(nrow(sub)<3)return(0)
    ics<-sapply(states,function(st){ww<-sub[[paste0("w_",st)]];if(sum(ww)<1e-6)return(NA);sum(sub$ic*ww)/sum(ww)})
    memnow<-c(mt$w_risk_on,mt$w_neutral,mt$w_crisis);max(sum(memnow*ics,na.rm=TRUE),0)})
  if(sum(wts)<1e-9)wts<-setNames(rep(1,length(grp)),grp);ww<-wts/sum(wts)
  sub<-gw[signal_date==dd];X<-as.matrix(sub[,..grp]);X[is.na(X)]<-0
  rows[[d]]<-data.table(signal_date=dd,security_id=sub$security_id,score=as.numeric(X%*%ww))}
sc<-rbindlist(rows); sc[,score:=zc(score),by=signal_date]
held<-sig_dates[((seq_along(sig_dates)-1)%%3)==0]; ff<-list(); for(d in sig_dates){src<-max(held[held<=d]);ff[[as.character(d)]]<-sc[signal_date==src][,signal_date:=d]}; scq<-rbindlist(ff)
pg("score done\n")
## EW top-25 weights
scq<-merge(scq,liq[,.(signal_date=Date,security_id=Ticker,adv)],by=c("signal_date","security_id"),all.x=TRUE); scq<-scq[is.na(adv)|adv>=2e8]
W<-scq[order(signal_date,-score),.SD[1:min(25,.N)],by=signal_date][is.finite(score),.(Date=signal_date,Ticker=security_id,w=1)]
## crisis 디리스크 exposure: exposure = 1 - w_crisis*(1-crisis_exp). crisis_exp=1 → no de-risk(baseline).
gate<-function(exp_dt,lab){ r<-tryCatch(weighted_screen_bt(W,fwd_ret,bench,cost_bps_oneway=15,run_id="dr",strategy_id=lab,exposure_dt=exp_dt),error=function(e)NULL)
  if(is.null(r$period_returns))return(NULL); pr<-as.data.table(r$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr)
  rets<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA})
  cal<-if(!is.na(r$abs_mdd)&&r$abs_mdd<0)r$abs_cagr/abs(r$abs_mdd)else NA
  data.table(model=lab,pt_capwt=nwt(act),oos_reten=median(rets,na.rm=T),calmar=cal,IR=r$information_ratio,abs_mdd=r$abs_mdd,TO=r$turnover_annual)}
## [수정] 극단위기 only — exposure=1 (평상), w_crisis>THRESH일 때만 디리스크(crisis alpha만, normal 드래그 제거)
THRESH<-0.6
mkexp<-function(ce){ e<-merge(data.table(Date=sig_dates),MEM[,.(Date=signal_date,w_crisis)],by="Date",all.x=TRUE); e[is.na(w_crisis),w_crisis:=0]
  e[,sev:=pmax(0,(w_crisis-THRESH)/(1-THRESH))]; e[,exposure:=1-sev*(1-ce)]; e[,.(Date,exposure)] }
nmx<-MEM[w_crisis>THRESH,.N]
R<-rbindlist(Filter(Negate(is.null),list(
  gate(NULL,"baseline_noDerisk"),
  gate(mkexp(0.3),sprintf("crisisONLY_e0.3_n%d",nmx)),
  gate(mkexp(0.0),sprintf("crisisONLY_full_n%d",nmx)))),fill=TRUE)
w("=== Gate8 crisis 디리스크 (AR+MSM_quarterly, 게이트 2.95/0.7/0.64) ===")
w(sprintf("  %-20s %8s %9s %7s %6s %7s %6s","model","pt_capwt","oos_reten","calmar","IR","MDD","TO"))
for(i in seq_len(nrow(R)))w(sprintf("  %-20s %+8.2f %+9.2f %+7.2f %+6.2f %+7.2f %6.1f",R$model[i],R$pt_capwt[i],R$oos_reten[i],R$calmar[i],R$IR[i],R$abs_mdd[i],R$TO[i]))
w("\n게이트:")
for(i in seq_len(nrow(R))){r<-R[i];p<-c(isTRUE(r$pt_capwt>=2.95),isTRUE(r$oos_reten>=0.7),isTRUE(r$calmar>=0.64))
  w(sprintf("  %-20s pt %s oos %s cal %s → %s",r$model,ifelse(p[1],"✓","✗"),ifelse(p[2],"✓","✗"),ifelse(p[3],"✓","✗"),ifelse(all(p),"★GRAD","미달")))}
saveRDS(R,".cache/_ramp_derisk.rds"); close(con); cat("DR_DONE\n")
