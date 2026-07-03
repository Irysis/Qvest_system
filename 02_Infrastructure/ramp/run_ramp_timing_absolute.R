## run_ramp_timing_absolute.R — 제약완화(도훈): active-only 제약 풀고 Gate8 soft 타이밍 + 절대측정.
## 최고엔진 Cascade regime → ① soft membership(군 로테이션) ② Category 노출스케줄(soft 디리스크, hard switch 아님).
## 측정: 절대 SR/CAGR/MDD/calmar(프로젝트 목표 2.5/16%/25%/0.64) + active pt. weighted_screen_bt(exposure_dt) 경유.
## 헌법: Gate8 Σa≤1 허용, 규제국면 graduated 노출(book M4식). PIT: Cascade Category t-1 lag.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R"); source("02_Infrastructure/contracts/backtest_result_contract.R")
suppressMessages({library(sandwich);library(lmtest)})
con<-file(".cache/_ramp_timing.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)
PG<-".cache/_tm_prog.txt"; cat("start\n",file=PG); pg<-function(...)cat(sprintf(...),file=PG,append=TRUE)
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
me_of<-function(dts){d<-as.Date(dts);mon<-as.integer(format(d,"%m"));yr<-as.integer(format(d,"%Y"));nmon<-ifelse(mon==12L,1L,mon+1L);nyr<-ifelse(mon==12L,yr+1L,yr);out<-as.Date(rep(NA_real_,length(d)));ok<-!is.na(mon)&!is.na(yr);if(any(ok))out[ok]<-as.Date(sprintf("%04d-%02d-01",nyr[ok],nmon[ok]))-1L;out}
expz<-function(v){z<-rep(0,length(v));for(i in seq_along(v)){p<-v[1:i];p<-p[is.finite(p)];if(length(p)>=12){s<-sd(p);if(!is.na(s)&&s>1e-8)z[i]<-(v[i]-mean(p))/s}};z}

g<-as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet"));g[,signal_date:=as.Date(signal_date)]
gw<-dcast(g,signal_date+security_id~family,value.var="group_z");grp<-setdiff(names(gw),c("signal_date","security_id"))
sig_dates<-sort(unique(g$signal_date))
CF<-".cache/_bo_fwdgic.rds"
if(file.exists(CF)){L<-readRDS(CF);fwd<-L$fwd;gic0<-L$gic0}else{
  rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=all_of(c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret"))));rd[,Date:=as.Date(Date)]
  fwd<-build_monthly_forward_returns(rd,sig_dates);rm(rd);invisible(gc())
  ic<-merge(g[,.(signal_date,security_id,family,group_z)],fwd$returns_dt[,.(signal_date=as.Date(Date),security_id=Ticker,Ret_1m)],by=c("signal_date","security_id"));gic0<-ic[,.(ic=if(.N>=10&&sd(group_z)>0&&sd(Ret_1m)>0)cor(group_z,Ret_1m,method="spearman")else NA_real_),by=.(signal_date,family)];rm(ic);invisible(gc());saveRDS(list(fwd=fwd,gic0=gic0),CF)}
SD<-data.table(signal_date=sig_dates);fwd_ret<-fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)];bench<-fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)];liq<-fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
pg("data loaded\n")

## Cascade: Regime_Score_smooth(소프트) + Category(노출), 월말 PIT
uni<-as.data.table(read_parquet(".cache/unified_regime_signal_daily.parquet"));uni[,Date:=as.Date(Date)];uni<-uni[!is.na(Date)];uni[,ym:=format(Date,"%Y-%m")]
um<-uni[,.(rs=last(Regime_Score_smooth),cat=last(Category)),by=ym];um[,signal_date:=me_of(as.Date(paste0(ym,"-01")))];um<-um[!is.na(signal_date)]
C<-merge(SD,um[,.(signal_date,rs,cat)],by="signal_date",all.x=TRUE)
C[,rsz:=expz(rs)];C[is.na(rsz),rsz:=0]
anc<-c(-1,0,1);sm<-t(sapply(C$rsz,function(zz){e<-exp(anc*zz);e/sum(e)}))
MEM<-data.table(signal_date=C$signal_date,r=sm[,1],n=sm[,2],c=sm[,3])
# Category 노출 스케줄 (t-1 lag, graduated soft — book M4식): RISK_ON/NEUTRAL 1.0 / CAUTION 0.7 / CRISIS·RISK_OFF 0.4
catexp<-c(RISK_ON=1.0,NEUTRAL=1.0,RISK_OFF=0.4,CAUTION=0.7,CRISIS=0.4)
C[,ce:=catexp[cat]];C[is.na(ce),ce:=1.0];C[,ce_lag:=shift(ce,1)];C[is.na(ce_lag),ce_lag:=1.0]
pg("cascade regime built\n")

## M_regdd score (Cascade soft membership) → quarterly
gic<-merge(gic0,MEM,by="signal_date");setorder(gic,family,signal_date);rows<-list()
for(d in as.character(sig_dates)){dd<-as.Date(d);mt<-MEM[signal_date==dd]
 wts<-sapply(grp,function(fm){sub<-gic[family==fm&signal_date<dd];sub<-sub[is.finite(ic)];if(nrow(sub)<3)return(0)
  ics<-c(sum(sub$ic*sub$r)/sum(sub$r),sum(sub$ic*sub$n)/sum(sub$n),sum(sub$ic*sub$c)/sum(sub$c));max(sum(c(mt$r,mt$n,mt$c)*ics,na.rm=T),0)})
 if(sum(wts)<1e-9)wts<-setNames(rep(1,length(grp)),grp);ww<-wts/sum(wts)
 sub<-gw[signal_date==dd];X<-as.matrix(sub[,..grp]);X[is.na(X)]<-0;rows[[d]]<-data.table(signal_date=dd,security_id=sub$security_id,score=as.numeric(X%*%ww))}
sc<-rbindlist(rows);sc[,score:=zc(score),by=signal_date]
held<-sig_dates[((seq_along(sig_dates)-1)%%3)==0];ff<-list();for(d in sig_dates){src<-max(held[held<=d]);ff[[as.character(d)]]<-sc[signal_date==src][,signal_date:=d]};scq<-rbindlist(ff)
scl<-merge(scq,liq[,.(signal_date=Date,security_id=Ticker,adv)],by=c("signal_date","security_id"),all.x=TRUE);scl<-scl[is.na(adv)|adv>=2e8]
W<-scl[order(signal_date,-score),head(.SD,25),by=signal_date][,.(Date=signal_date,Ticker=security_id,w=1)]
pg("score+weights done\n")

## 측정: 노출 없음(baseline) vs Category 노출(soft 디리스크)
gate<-function(exp_dt,lab){r<-tryCatch(weighted_screen_bt(W,fwd_ret,bench,cost_bps_oneway=15,run_id="tm",strategy_id=lab,exposure_dt=exp_dt),error=function(e)NULL)
  if(is.null(r$period_returns))return(NULL);pr<-as.data.table(r$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr)
  rets<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA})
  cal<-if(!is.na(r$abs_mdd)&&r$abs_mdd<0)r$abs_cagr/abs(r$abs_mdd)else NA
  data.table(model=lab, abs_SR=r$abs_net_sr, abs_CAGR=r$abs_cagr, abs_MDD=r$abs_mdd, calmar=cal, pt_capwt=nwt(act), oos_reten=median(rets,na.rm=T), TO=r$turnover_annual)}
EXP<-C[,.(Date=signal_date,exposure=ce_lag)]
R<-rbindlist(Filter(Negate(is.null),list(gate(NULL,"Cascade_noExp(baseline)"),gate(EXP,"Cascade+Gate8_timing"))),fill=TRUE)
w("=== 제약완화: Cascade + Gate8 soft 타이밍, 절대측정 (프로젝트목표 SR2.5/CAGR0.16/MDD-0.25/calmar0.64) ===")
w(sprintf("  %-26s %7s %8s %8s %7s %8s %9s %5s","model","abs_SR","abs_CAGR","abs_MDD","calmar","pt_capwt","oos_reten","TO"))
for(i in seq_len(nrow(R)))w(sprintf("  %-26s %+7.2f %+8.3f %+8.3f %+7.2f %+8.2f %+9.2f %5.1f",R$model[i],R$abs_SR[i],R$abs_CAGR[i],R$abs_MDD[i],R$calmar[i],R$pt_capwt[i],R$oos_reten[i],R$TO[i]))
w("\n프로젝트목표 충족(SR≥2.5 / CAGR≥0.16 / MDD≥-0.25 / calmar≥0.64):")
for(i in seq_len(nrow(R))){r<-R[i];p<-c(isTRUE(r$abs_SR>=2.5),isTRUE(r$abs_CAGR>=0.16),isTRUE(r$abs_MDD>=-0.25),isTRUE(r$calmar>=0.64))
 w(sprintf("  %-26s SR %s CAGR %s MDD %s calmar %s → %s",r$model,ifelse(p[1],"✓","✗"),ifelse(p[2],"✓","✗"),ifelse(p[3],"✓","✗"),ifelse(p[4],"✓","✗"),ifelse(all(p),"★목표달성",sprintf("%d/4",sum(p)))))}
saveRDS(R,".cache/_ramp_timing.rds");close(con);cat("TIMING_DONE\n")
