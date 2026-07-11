## r3_adversarial.R — Self-Adversarial: A3 crisis 기여 look-ahead 검증(regime lag1 스트레스)
##  + base 레벨 sanity(06-18 대비) + placebo(랜덤 regime 부여) + tail sleeve 부호 안정성
suppressPackageStartupMessages({library(data.table); library(arrow); library(dplyr)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R"); source("02_Infrastructure/data/pin_cache.R")
suppressMessages({library(sandwich);library(lmtest)})
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9) x-m else (x-m)/s}
nwt<-function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12)return(NA_real_);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=lag,prewhite=F))[1,3])}
D<-readRDS(".cache/_ramp_r3.rds"); PIN_TAG<-jsonlite::read_json("outputs/ramp/r3_summary_20260711.json")$pin_tag[[1]]
cat("pin tag:",PIN_TAG,"\n")

# 재현: base_sc, tail_raw, fwd, ewb (pinned)
g<-as.data.table(read_parquet(read_pinned("outputs/ramp/factor_group_scores.parquet",PIN_TAG))); g[,signal_date:=as.Date(signal_date)]
gw<-dcast(g,signal_date+security_id~family,value.var="group_z"); grp<-setdiff(names(gw),c("signal_date","security_id"))
a<-as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); a[,Date:=as.Date(Date)]
reg<-unique(a[,.(ym=format(Date,"%Y-%m"),regime=regime_state)])[,.SD[1],by=ym]
gw[,ym:=format(signal_date,"%Y-%m")]; gw<-merge(gw,reg,by="ym",all.x=TRUE); gw[is.na(regime),regime:="NORMAL"]
.need<-c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata<-as.data.table(read_parquet(read_pinned(".cache/rawdata.parquet",PIN_TAG),col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
sig_dates<-sort(unique(gw$signal_date)); fwd<-build_monthly_forward_returns(rawdata,sig_dates)
oos_cut<-sig_dates[length(sig_dates)-23]
ewb<-fwd$returns_dt[,.(ew=mean(Ret_1m,na.rm=TRUE)),by=.(date=as.Date(Date))]
regmap<-unique(gw[,.(signal_date,regime)]); setorder(regmap,signal_date)
ic<-merge(g[,.(signal_date,security_id,family,group_z)],fwd$returns_dt[,.(signal_date=as.Date(Date),security_id=Ticker,Ret_1m)],by=c("signal_date","security_id"))
gic<-ic[,.(ic=if(.N>=10&&sd(group_z)>0&&sd(Ret_1m)>0)cor(group_z,Ret_1m,method="spearman")else NA_real_),by=.(signal_date,family)]
gic<-merge(gic,unique(gw[,.(signal_date,regime)]),by="signal_date"); setorder(gic,family,signal_date)
mk_base<-function(){rows<-list();for(d in as.character(sig_dates)){dd<-as.Date(d);rg<-gw[signal_date==dd,regime][1]
  wts<-sapply(grp,function(fm){p<-gic[family==fm&regime==rg&signal_date<dd,ic];p<-p[is.finite(p)];if(length(p)>=3)max(mean(p),0)else 0})
  if(sum(wts)<1e-9)wts<-setNames(rep(1,length(grp)),grp);ww<-wts/sum(wts)
  sub<-gw[signal_date==dd];X<-as.matrix(sub[,..grp]);X[is.na(X)]<-0
  rows[[d]]<-data.table(signal_date=dd,security_id=sub$security_id,base=as.numeric(X%*%ww))};s<-rbindlist(rows);s[,base:=zc(base),by=signal_date];s}
base_sc<-mk_base()
ds<-arrow::open_dataset("outputs/ramp/pure_factor_scores.parquet")
tailf<-c("D47_CVaR_5pct","D48_VaR_5pct","R03_CVaR_95","R04_CVaR_99","R05_Tail_Risk")
pf<-ds %>% filter(factor_id %in% c(tailf,"D03_RealVol")) %>% select(signal_date,security_id,factor_id,z) %>% collect() %>% as.data.table()
pf[,signal_date:=as.Date(signal_date)]; Wz<-dcast(pf,signal_date+security_id~factor_id,value.var="z")
xcor<-function(dt,a,b){s<-dt[!is.na(get(a))&!is.na(get(b)),.(c=if(.N>=20&&sd(get(a))>0&&sd(get(b))>0)cor(get(a),get(b),method="spearman")else NA_real_),by=signal_date];mean(s$c,na.rm=TRUE)}
poles<-sapply(tailf,function(f) sign(xcor(Wz,f,"D03_RealVol")))
X<-copy(Wz);for(f in tailf)X[,(f):=get(f)*(-poles[f])];X[,tail:=rowMeans(.SD,na.rm=TRUE),.SDcols=tailf];X[,tail:=zc(tail),by=signal_date]
tail_raw<-X[,.(signal_date,security_id,sleeve=tail)]
run_cs<-function(scores)canonical_screen_bt(scores,fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)],fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)],top_n=25L,cost_bps_oneway=15,liq_dt=fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)],liq_min=2e8,run_id="r3adv",strategy_id="r3adv",diag_dual_basis=FALSE)
base_pr<-as.data.table(run_cs(base_sc[,.(Date=signal_date,Ticker=security_id,score=base)])$period_returns)[,.(date=as.Date(date),base_ret=ret_net)]

sched<-function(rg,lo,cau,cri,bull=0){w<-rep(lo,length(rg));w[rg=="BULL"]<-bull;w[rg=="CAUTION"]<-cau;w[rg=="CRISIS"]<-cri;w}
build_treat<-function(wvec){m<-merge(base_sc,tail_raw,by=c("signal_date","security_id"),all.x=TRUE);m[is.na(sleeve),sleeve:=0]
  wd<-data.table(signal_date=sig_dates,wt=wvec);m<-merge(m,wd,by="signal_date",all.x=TRUE);m[,score:=(1-wt)*base+wt*sleeve];m[,score:=zc(score),by=signal_date];m[,.(Date=signal_date,Ticker=security_id,score)]}
eval_treat<-function(wvec,lab,regvec){cs<-run_cs(build_treat(wvec));pr<-as.data.table(cs$period_returns)[,date:=as.Date(date)]
  pj<-merge(pr[,.(date,ret_net)],base_pr,by="date");pj[,d:=ret_net-base_ret];pj[,is_oos:=date>=oos_cut]
  pj<-merge(pj,data.table(date=sig_dates,regime=regvec),by="date",all.x=TRUE)
  cr<-pj[regime%in%c("CRISIS","CAUTION"),d];nm<-pj[regime%in%c("NORMAL","BULL"),d]
  cat(sprintf("  [%s] paired_t full=%+.2f IS=%+.2f | crisis_d=%+.4f(n=%d,t%+.2f) normal_d=%+.4f | port_t_capw=%+.2f\n",
    lab,nwt(pj$d),nwt(pj[is_oos==FALSE,d]),mean(cr,na.rm=T)*12,length(cr[is.finite(cr)]),nwt(cr,1L),mean(nm,na.rm=T)*12,cs$portfolio_alpha_t_nw_lag3))}

reg0<-regmap$regime[match(sig_dates,regmap$signal_date)]
reg1<-c("NORMAL",reg0[-length(reg0)])   # lag1: 전월 regime을 당월 배분에 적용 (보수적 PIT)
# placebo: regime 라벨 순환 시프트(구조 보존, 정렬 파괴)
set.seed(42); regP<-reg0[c((13:length(reg0)),(1:12))]

cat("\n=== A3 look-ahead 스트레스 (tail_raw regime-cond N.05/CAU.25/CRI.40) ===\n")
eval_treat(sched(reg0,0.05,0.25,0.40),"A3 regime@dd (원본)",reg0)
eval_treat(sched(reg1,0.05,0.25,0.40),"A3 regime lag1 (전월)",reg0)
eval_treat(sched(regP,0.05,0.25,0.40),"A3 placebo(shift 12m)",reg0)
cat("\n(해석: lag1이 원본과 유사 유지면 regime timing look-ahead 아님. placebo가 붕괴/음수면 crisis 정렬이 실재.)\n")
cat("R3_ADV_DONE\n")
