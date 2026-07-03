## run_ramp_selfdev_ar.R — RAMP 자율 자가발전: AR-배선 위 변형 탐색 (도훈 "알아서 진행").
## Diagnose: AR-soft pt 2.49(↑) but oos −0.27 binding. Propose: ① 분기리밸(oos레버) ② AR+MSM 2축(pt레버).
## 4변형: {AR / AR+MSM} × {monthly / quarterly}. AR 저장본 재사용(재계산 회피). 헌법 soft membership(no hard switch).
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
suppressMessages({library(sandwich);library(lmtest)})
con<-file(".cache/_ramp_selfdev_ar.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)
PG<-".cache/_sd_prog.txt"; cat("start\n",file=PG); pg<-function(...)cat(sprintf(...),file=PG,append=TRUE)
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}

## 데이터
g<-as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet")); g[,signal_date:=as.Date(signal_date)]
gw<-dcast(g,signal_date+security_id~family,value.var="group_z"); grp<-setdiff(names(gw),c("signal_date","security_id"))
.need<-c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata<-as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
sig_dates<-sort(unique(g$signal_date)); fwd<-build_monthly_forward_returns(rawdata,sig_dates)

## AR 신호 (저장본 재사용)
ARDT<-as.data.table(read_parquet("outputs/ramp/absorption_ratio_signal.parquet")); ARDT[,signal_date:=as.Date(signal_date)]
## MSM Crisis_Prob → 월말 + expanding z (PIT)
msm<-as.data.table(read_parquet(".cache/msm_daily_latest.parquet")); msm[,Date:=as.Date(Date)]
msm[,ym:=format(Date,"%Y-%m")]; msmm<-msm[,.(cp=last(Crisis_Prob)),by=ym]
msmm[,me:=as.Date(paste0(ym,"-01"))]; msmm[,me:=as.Date(sapply(me,function(d)as.character(seq(d,by="month",length.out=2)[2]-1)))]
A<-merge(ARDT[,.(signal_date,ar_z)], msmm[,.(signal_date=me,cp)], by="signal_date", all.x=TRUE)
A[is.na(cp),cp:=mean(A$cp,na.rm=TRUE)]
A[,cp_z:=0]; for(i in seq_len(nrow(A))){p<-A$cp[1:i];p<-p[is.finite(p)];if(length(p)>=12){s<-sd(p);if(!is.na(s)&&s>1e-8)A$cp_z[i]<-(A$cp[i]-mean(p))/s}}
pg("signals merged\n")

## soft membership 빌더
TAU<-1.0; anc<-c(risk_on=-1,neutral=0,crisis=1); softmem<-function(z){e<-exp(anc*z/TAU);e/sum(e)}
mk_mem<-function(use_msm){ z<-if(use_msm) 0.5*A$ar_z+0.5*A$cp_z else A$ar_z
  M<-data.table(signal_date=A$signal_date); mm<-t(sapply(z,softmem)); M[,w_risk_on:=mm[,1]];M[,w_neutral:=mm[,2]];M[,w_crisis:=mm[,3]]; M }
states<-c("risk_on","neutral","crisis")

## 군 월별 IC
ic<-merge(g[,.(signal_date,security_id,family,group_z)],fwd$returns_dt[,.(signal_date=as.Date(Date),security_id=Ticker,Ret_1m)],by=c("signal_date","security_id"))
gic0<-ic[,.(ic=if(.N>=10&&sd(group_z)>0&&sd(Ret_1m)>0)cor(group_z,Ret_1m,method="spearman")else NA_real_),by=.(signal_date,family)]

mk_score<-function(MEM){ gic<-merge(gic0,MEM,by="signal_date"); setorder(gic,family,signal_date); rows<-list()
  for(d in as.character(sig_dates)){dd<-as.Date(d); mt<-MEM[signal_date==dd]
    wts<-sapply(grp,function(fm){sub<-gic[family==fm&signal_date<dd];sub<-sub[is.finite(ic)];if(nrow(sub)<3)return(0)
      ics<-sapply(states,function(st){ww<-sub[[paste0("w_",st)]];if(sum(ww)<1e-6)return(NA);sum(sub$ic*ww)/sum(ww)})
      memnow<-c(mt$w_risk_on,mt$w_neutral,mt$w_crisis);max(sum(memnow*ics,na.rm=TRUE),0)})
    if(sum(wts)<1e-9)wts<-setNames(rep(1,length(grp)),grp);ww<-wts/sum(wts)
    sub<-gw[signal_date==dd];X<-as.matrix(sub[,..grp]);X[is.na(X)]<-0
    rows[[d]]<-data.table(signal_date=dd,security_id=sub$security_id,score=as.numeric(X%*%ww))}
  s<-rbindlist(rows); s[,score:=zc(score),by=signal_date]; s}

to_quarterly<-function(sc){ held<-sig_dates[((seq_along(sig_dates)-1)%%3)==0]; ff<-list()
  for(d in sig_dates){src<-max(held[held<=d]); ff[[as.character(d)]]<-sc[signal_date==src][,signal_date:=d]}; rbindlist(ff) }

gates<-function(sc,lab){
  cs<-tryCatch(canonical_screen_bt(sc[,.(Date=as.Date(signal_date),Ticker=security_id,score)],
        fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)],fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)],
        top_n=25L,cost_bps_oneway=15,liq_dt=fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)],liq_min=2e8,run_id="sd",strategy_id=lab),error=function(e)NULL)
  if(is.null(cs$period_returns))return(NULL)
  pr<-as.data.table(cs$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr)
  rets<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA})
  nav<-cumprod(1+pr$ret_net);dd<-min(nav/cummax(nav)-1);ann<-prod(1+pr$ret_net)^(12/n)-1;cal<-if(dd<0)ann/abs(dd)else NA
  data.table(model=lab,pt_capwt=nwt(act),oos_reten=median(rets,na.rm=T),calmar=cal,full_IR=IRf(act),TO=cs$turnover_annual)}

pg("AR scores\n"); scAR<-mk_score(mk_mem(FALSE))
pg("ARMSM scores\n"); scARMSM<-mk_score(mk_mem(TRUE))
R<-rbindlist(Filter(Negate(is.null),list(
  gates(scAR,"AR_monthly"), gates(to_quarterly(scAR),"AR_quarterly"),
  gates(scARMSM,"AR+MSM_monthly"), gates(to_quarterly(scARMSM),"AR+MSM_quarterly"))),fill=TRUE)
w("=== 자가발전 변형 (IC-가중316 + AR배선, cap-w, 게이트 2.95/0.7/0.64) ===")
w(sprintf("  %-20s %8s %9s %7s %7s %6s","model","pt_capwt","oos_reten","calmar","full_IR","TO"))
for(i in seq_len(nrow(R)))w(sprintf("  %-20s %+8.2f %+9.2f %+7.2f %+7.2f %6.1f",R$model[i],R$pt_capwt[i],R$oos_reten[i],R$calmar[i],R$full_IR[i],R$TO[i]))
w("\n게이트 통과(pt≥2.95∧oos≥0.7∧cal≥0.64):")
for(i in seq_len(nrow(R))){r<-R[i];p<-c(isTRUE(r$pt_capwt>=2.95),isTRUE(r$oos_reten>=0.7),isTRUE(r$calmar>=0.64))
  w(sprintf("  %-20s pt %s oos %s cal %s → %s",r$model,ifelse(p[1],"✓","✗"),ifelse(p[2],"✓","✗"),ifelse(p[3],"✓","✗"),ifelse(all(p),"★GRAD","미달")))}
b<-R[which.max(pt_capwt)]; w(sprintf("\n최고 pt: %s (%.2f) | 최고 oos: %s (%.2f)",b$model,b$pt_capwt,R[which.max(oos_reten),model],max(R$oos_reten,na.rm=T)))
saveRDS(R,".cache/_ramp_selfdev_ar.rds"); close(con); cat("SD_DONE\n")
