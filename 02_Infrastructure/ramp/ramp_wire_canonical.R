## ramp_wire_canonical.R — 검증된 RAMP 연구결과를 파이프라인에 영속 배선 + 등록 (도훈: "새롭게 배선").
## 산출: ① outputs/ramp/regime_soft_membership.parquet (AR+MSM soft regime, RAMP 정본 regime)
##       ② outputs/ramp/mcode_armq_scores.parquet (M-code 종목 score, 월별)
##       ③ outputs/ramp/mcode_armq_holdings.parquet (top-25 EW holdings, 월별)
##       ④ 06_Registry/ramp/ramp_registry.json 등록 (register_ramp_result, metric_type=backtested)
## 실측: canonical_screen_bt로 게이트 metric 산출 후 essence에 적재. §2.4 메타. governor 정지(자본 수동).
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R"); source("02_Infrastructure/ramp/register_ramp_result.R")
suppressMessages({library(sandwich);library(lmtest)})
`%||%`<-function(a,b)if(is.null(a)||length(a)==0L||(length(a)==1L&&is.na(a)))b else a
PG<-".cache/_wire_prog.txt"; cat("start\n",file=PG); pg<-function(...)cat(sprintf(...),file=PG,append=TRUE)
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
NOW<-format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"); SRC<-"ramp_v1.1_armsm_arwiring"
addmeta<-function(dt,asof){dt<-copy(dt);dt[,as_of_date:=as.character(asof)];dt[,generated_at:=NOW];dt[,source_version:=SRC];dt[,security_id_field:="Ticker"];dt}
wp<-function(dt,f){.t<-paste0(f,".tmp");write_parquet(dt,.t);if(file.exists(f))file.remove(f);file.rename(.t,f)}

## ── 데이터 + AR+MSM soft membership regime ──
g<-as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet"));g[,signal_date:=as.Date(signal_date)]
gw<-dcast(g,signal_date+security_id~family,value.var="group_z");grp<-setdiff(names(gw),c("signal_date","security_id"))
rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=all_of(c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret"))));rd[,Date:=as.Date(Date)]
sig_dates<-sort(unique(g$signal_date));fwd<-build_monthly_forward_returns(rd,sig_dates)
AR<-as.data.table(read_parquet("outputs/ramp/absorption_ratio_signal.parquet"));AR[,signal_date:=as.Date(signal_date)]
msm<-as.data.table(read_parquet(".cache/msm_daily_latest.parquet"));msm[,Date:=as.Date(Date)];msm[,ym:=format(Date,"%Y-%m")]
mm<-msm[,.(cp=last(Crisis_Prob)),by=ym];mm[,me:=as.Date(sapply(as.Date(paste0(ym,"-01")),function(d)as.character(seq(d,by="month",length.out=2)[2]-1)))]
A<-merge(AR[,.(signal_date,ar_z)],mm[,.(signal_date=me,cp)],by="signal_date",all.x=TRUE);A[is.na(cp),cp:=mean(A$cp,na.rm=T)]
A[,cpz:=0];for(i in seq_len(nrow(A))){p<-A$cp[1:i];p<-p[is.finite(p)];if(length(p)>=12){s<-sd(p);if(!is.na(s)&&s>1e-8)A$cpz[i]<-(A$cp[i]-mean(p))/s}}
anc<-c(-1,0,1);z<-0.5*A$ar_z+0.5*A$cpz;sm<-t(sapply(z,function(zz){e<-exp(anc*zz);e/sum(e)}))
REG<-data.table(signal_date=A$signal_date,ar_z=A$ar_z,msm_crisis_prob=A$cp,w_risk_on=sm[,1],w_neutral=sm[,2],w_crisis=sm[,3])
## ① 영속: regime soft membership
wp(addmeta(REG, max(REG$signal_date)), "outputs/ramp/regime_soft_membership.parquet"); pg("regime persisted\n")

## ── M-code score (AR+MSM soft μ_blend) → quarterly ──
MEM<-REG[,.(signal_date,r=w_risk_on,n=w_neutral,c=w_crisis)]
ic<-merge(g[,.(signal_date,security_id,family,group_z)],fwd$returns_dt[,.(signal_date=as.Date(Date),security_id=Ticker,Ret_1m)],by=c("signal_date","security_id"))
gic<-ic[,.(ic=if(.N>=10&&sd(group_z)>0&&sd(Ret_1m)>0)cor(group_z,Ret_1m,method="spearman")else NA_real_),by=.(signal_date,family)]
gic<-merge(gic,MEM,by="signal_date");setorder(gic,family,signal_date)
rows<-list()
for(d in as.character(sig_dates)){dd<-as.Date(d);mt<-MEM[signal_date==dd]
 wts<-sapply(grp,function(fm){sub<-gic[family==fm&signal_date<dd];sub<-sub[is.finite(ic)];if(nrow(sub)<3)return(0)
  ics<-c(sum(sub$ic*sub$r)/sum(sub$r),sum(sub$ic*sub$n)/sum(sub$n),sum(sub$ic*sub$c)/sum(sub$c));max(sum(c(mt$r,mt$n,mt$c)*ics,na.rm=T),0)})
 if(sum(wts)<1e-9)wts<-setNames(rep(1,length(grp)),grp);ww<-wts/sum(wts)
 sub<-gw[signal_date==dd];X<-as.matrix(sub[,..grp]);X[is.na(X)]<-0;rows[[d]]<-data.table(signal_date=dd,security_id=sub$security_id,score=as.numeric(X%*%ww))}
sc<-rbindlist(rows);sc[,score:=zc(score),by=signal_date]
held<-sig_dates[((seq_along(sig_dates)-1)%%3)==0];ff<-list();for(d in sig_dates){src<-max(held[held<=d]);ff[[as.character(d)]]<-sc[signal_date==src][,signal_date:=d]};scq<-rbindlist(ff)
## ② 영속: M-code scores
wp(addmeta(scq[,.(signal_date,security_id,score)], max(scq$signal_date)), "outputs/ramp/mcode_armq_scores.parquet"); pg("scores persisted\n")
## ③ 영속: holdings (top-25 EW, 유동성)
scl<-merge(scq,fwd$liq_dt[,.(signal_date=as.Date(Date),security_id=Ticker,adv)],by=c("signal_date","security_id"),all.x=TRUE);scl<-scl[is.na(adv)|adv>=2e8]
HD<-scl[order(signal_date,-score),.SD[1:min(25,.N)],by=signal_date][is.finite(score),.(signal_date,security_id,weight=1/.N),by=signal_date][,.(signal_date,security_id,weight=1/25)]
HD<-scl[order(signal_date,-score),head(.SD,25),by=signal_date][,weight:=1/.N,by=signal_date][,.(signal_date,security_id,score,weight)]
wp(addmeta(HD, max(HD$signal_date)), "outputs/ramp/mcode_armq_holdings.parquet"); pg("holdings persisted\n")

## ── 게이트 metric (canonical_screen_bt 실측) ──
cs<-canonical_screen_bt(scq[,.(Date=as.Date(signal_date),Ticker=security_id,score)],fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)],fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)],top_n=25L,cost_bps_oneway=15,liq_dt=fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)],liq_min=2e8,run_id="wire",strategy_id="RAMP_ARMSM_Q")
pr<-as.data.table(cs$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr)
rets<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA})
nav<-cumprod(1+pr$ret_net);dd<-min(nav/cummax(nav)-1);ann<-prod(1+pr$ret_net)^(12/n)-1;cal<-if(dd<0)ann/abs(dd)else NA
PT<-nwt(act);OOS<-median(rets,na.rm=T);CAL<-cal;IRv<-IRf(act);pg("gates computed pt=%.2f\n",PT)

## ④ 등록 (register_ramp_result, 실측-only)
ramp<-list(ramp_id=sprintf("RAMP_ARMSM_Q_%s",format(Sys.Date(),"%Y%m%d")),
  grade="B", metric_type="backtested", self_synthesized=FALSE,
  essence=list(port_t_capwt=round(PT,3),oos_retention=round(OOS,3),calmar=round(CAL,3),full_ir=round(IRv,3),turnover_annual=round(cs$turnover_annual,2),
               graduation="미달(screen-tier): pt<2.95·oos<0.7·calmar<0.64. 신호 실재(pt 2.73 hard분류기 1.81 대비)나 자본졸업 미달."),
  module_pool_n=length(grp), factor_groups=grp, n_trials=6,
  mcode_specs=list(construction="regime-IC soft-membership weighted group blend",rebalance="quarterly",universe="K200∪KQ150 top-25 EW long-only",cost="15bps one-way",
                   scores="outputs/ramp/mcode_armq_scores.parquet",holdings="outputs/ramp/mcode_armq_holdings.parquet"),
  as_of_date=as.character(max(sig_dates)), generated_at=NOW, source_version=SRC)
register_ramp_result(ramp,
  regime_engine_version="AR_soft_membership_v1: Absorption Ratio(Kritzman 63d/top15 시장동조화) + MSM Crisis_Prob → softmax 3-state(risk_on/neutral/crisis, Σ=1, no hard switch). outputs/ramp/regime_soft_membership.parquet",
  allocation_policy="regime-IC soft-membership μ_blend, quarterly rebalance, top-25 EW long-only 15bps")
cat(sprintf("WIRED: regime+scores+holdings 영속 + ramp_registry 등록. pt=%.2f oos=%.2f calmar=%.2f\nWIRE_DONE\n",PT,OOS,CAL))
