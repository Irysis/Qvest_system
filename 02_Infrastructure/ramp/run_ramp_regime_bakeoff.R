## run_ramp_regime_bakeoff.R — 국면엔진 리서치풀 전체를 RAMP에 적용·비교 (도훈: "국면엔진 리서치풀 모두 적용").
## 각 엔진 → 월별 stress 신호 → expanding z(PIT) → softmax soft 3-state membership → RAMP M_regdd quarterly → 게이트.
## 엔진: hard4(baseline)·AR·MSM·9축MRS·Jump·Cascade·Forecaster·AR+MSM(best)·ENSEMBLE(z평균). 효율=누적 조건부IC.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
suppressMessages({library(sandwich);library(lmtest)})
con<-file(".cache/_ramp_bakeoff.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)
PG<-".cache/_bo_prog.txt"; cat("start\n",file=PG); pg<-function(...)cat(sprintf(...),file=PG,append=TRUE)
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
me_of<-function(dts){d<-as.Date(dts);mon<-as.integer(format(d,"%m"));yr<-as.integer(format(d,"%Y"))  # 벡터화·NA-safe 월말
  nmon<-ifelse(mon==12L,1L,mon+1L);nyr<-ifelse(mon==12L,yr+1L,yr)
  out<-as.Date(rep(NA_real_,length(d)));ok<-!is.na(mon)&!is.na(yr);if(any(ok))out[ok]<-as.Date(sprintf("%04d-%02d-01",nyr[ok],nmon[ok]))-1L;out}
to_monthly<-function(dt,datecol,valcol){d<-copy(dt);d[,Date:=as.Date(get(datecol))];d<-d[!is.na(Date)];d[,ym:=format(Date,"%Y-%m")]
  m<-d[,.(v=last(get(valcol))),by=ym];m[,signal_date:=me_of(as.Date(paste0(ym,"-01")))];m[!is.na(signal_date),.(signal_date,v)]}
safe<-function(nm,expr){tryCatch({v<-eval(expr);pg("ok %s\n",nm);v},error=function(e){pg("FAIL %s: %s\n",nm,substr(conditionMessage(e),1,50));rep(0,length(sig_dates))})}
expz<-function(v){z<-rep(0,length(v));for(i in seq_along(v)){p<-v[1:i];p<-p[is.finite(p)];if(length(p)>=12){s<-sd(p);if(!is.na(s)&&s>1e-8)z[i]<-(v[i]-mean(p))/s}};z}

## 데이터
g<-as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet"));g[,signal_date:=as.Date(signal_date)]
gw<-dcast(g,signal_date+security_id~family,value.var="group_z");grp<-setdiff(names(gw),c("signal_date","security_id"))
sig_dates<-sort(unique(g$signal_date))
## [메모리 수리] fwd+gic0 캐시 (rawdata 14M 즉시해제, 5GB 스파이크 회피). 캐시 있으면 재사용.
CF<-".cache/_bo_fwdgic.rds"
if(file.exists(CF)){L<-readRDS(CF);fwd<-L$fwd;gic0<-L$gic0; pg("cache loaded\n")}else{
  rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=all_of(c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret"))));rd[,Date:=as.Date(Date)]
  fwd<-build_monthly_forward_returns(rd,sig_dates); rm(rd); invisible(gc()); pg("fwd built\n")
  ic<-merge(g[,.(signal_date,security_id,family,group_z)],fwd$returns_dt[,.(signal_date=as.Date(Date),security_id=Ticker,Ret_1m)],by=c("signal_date","security_id"))
  gic0<-ic[,.(ic=if(.N>=10&&sd(group_z)>0&&sd(Ret_1m)>0)cor(group_z,Ret_1m,method="spearman")else NA_real_),by=.(signal_date,family)]
  rm(ic); invisible(gc()); saveRDS(list(fwd=fwd,gic0=gic0),CF)}
SD<-data.table(signal_date=sig_dates)
pg("data loaded\n")

## ── 각 엔진의 월별 stress z (safe 격리) ──
algn<-function(mdt){merge(SD,mdt[!is.na(signal_date),.(signal_date=as.Date(signal_date),z)],by="signal_date",all.x=TRUE)$z}
sigz<-list()
sigz$AR<-safe("AR",quote({A<-as.data.table(read_parquet("outputs/ramp/absorption_ratio_signal.parquet"));A[,signal_date:=as.Date(signal_date)];algn(A[,.(signal_date,z=ar_z)])}))
sigz$MSM<-safe("MSM",quote({m<-to_monthly(as.data.table(read_parquet(".cache/msm_daily_latest.parquet")),"Date","Crisis_Prob");m[,z:=expz(v)];algn(m)}))
sigz$MRS9<-safe("MRS9",quote({m<-to_monthly(as.data.table(read_parquet(".cache/regime_daily_v2.parquet")),"Date","MRS");m[,z:=expz(v)];algn(m)}))
sigz$Jump<-safe("Jump",quote({m<-to_monthly(as.data.table(read_parquet(".cache/regime_jump_daily.parquet")),"Date","Bear_Prob_lag");m[,z:=expz(v)];algn(m)}))
sigz$Cascade<-safe("Cascade",quote({m<-to_monthly(as.data.table(read_parquet(".cache/unified_regime_signal_daily.parquet")),"Date","Regime_Score_smooth");m[,z:=expz(v)];algn(m)}))
sigz$Forecaster<-safe("Forecaster",quote({fc<-as.data.table(read_parquet(".cache/regime_forecast_series.parquet"));lvl<-c(RISK_ON=0,NEUTRAL=0.25,NORMAL=0.25,CAUTION=0.6,CRISIS=1,RISK_OFF=1)
  fc<-fc[grepl("^[0-9]{4}-[0-9]{2}$",ym)];fc[,sv:=as.numeric(lvl[forecast_regime])];fc[is.na(sv),sv:=0.25];fc[,signal_date:=me_of(as.Date(paste0(ym,"-01")))];fc[,z:=expz(sv)];algn(fc)}))
sigz$hard4<-safe("hard4",quote({a<-as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet"));a[,Date:=as.Date(Date)]
  reg<-unique(a[,.(ym=format(Date,"%Y-%m"),rs=regime_state)])[,.SD[1],by=ym];hv<-c(BULL=-1,NORMAL=0,CAUTION=0.6,CRISIS=1.6)
  reg[,signal_date:=me_of(as.Date(paste0(ym,"-01")))];reg[,z:=as.numeric(hv[rs])];reg[is.na(z),z:=0];algn(reg)}))
## ── 리서치/문헌-only 엔진 (인프라 미구현, 신규 구현, BM 월수익서 PIT 트레일링) ──
bm<-merge(SD,fwd$bench_dt[,.(signal_date=as.Date(Date),bmret=BM_Ret)],by="signal_date",all.x=TRUE);bmv<-bm$bmret;nn<-length(bmv)
gmm_bear<-function(x){x<-x[is.finite(x)];if(length(x)<24)return(0.5)  # 2-comp Gaussian mixture EM, P(bear=저평균 comp | 최근관측)
  mu<-as.numeric(quantile(x,c(.3,.7)));s<-rep(sd(x)+1e-9,2);p<-c(.5,.5)
  for(it in 1:40){d1<-p[1]*dnorm(x,mu[1],s[1]);d2<-p[2]*dnorm(x,mu[2],s[2]);r<-d2/(d1+d2+1e-12)
    p[2]<-mean(r);p[1]<-1-p[2];mu[2]<-sum(r*x)/sum(r);mu[1]<-sum((1-r)*x)/sum(1-r)
    s[2]<-sqrt(sum(r*(x-mu[2])^2)/sum(r))+1e-9;s[1]<-sqrt(sum((1-r)*(x-mu[1])^2)/sum(1-r))+1e-9}
  bear<-which.min(mu);xl<-x[length(x)];d1<-p[1]*dnorm(xl,mu[1],s[1]);d2<-p[2]*dnorm(xl,mu[2],s[2]);(c(d1,d2)/(d1+d2+1e-12))[bear]}
trend<-rep(0,nn);rvol<-rep(0,nn);ddr<-rep(0,nn);gmm<-rep(0.5,nn)
for(i in seq_len(nn)){ if(i<13)next; h<-bmv[max(1,i-12):(i-1)];h<-h[is.finite(h)]
  trend[i]<- -mean(h,na.rm=T)          # TSMOM: 하락추세=stress (Moskowitz-Ooi-Pedersen 2012)
  rvol[i]<-sd(h,na.rm=T)               # 변동성 국면 (Ang-Bekaert)
  pk<-bmv[1:(i-1)];pk<-pk[is.finite(pk)];if(length(pk)>1){nav<-cumprod(1+pk);ddr[i]<- -(nav[length(nav)]/max(nav)-1)}  # 낙폭 국면
  gmm[i]<-gmm_bear(bmv[1:(i-1)]) }     # GMM 비지도 국면군집
sigz$Trend<-expz(trend); sigz$RealizedVol<-expz(rvol); sigz$Drawdown<-expz(ddr); sigz$GMM<-expz(gmm-0.5)
pg("research engines built\n")
for(nm in names(sigz)){sigz[[nm]][is.na(sigz[[nm]])]<-0}
# 조합
sigz$`AR+MSM`<-0.5*sigz$AR+0.5*sigz$MSM
sigz$ENS_infra<-rowMeans(cbind(sigz$AR,sigz$MSM,sigz$MRS9,sigz$Jump,sigz$Cascade),na.rm=TRUE)
sigz$ENS_all<-rowMeans(cbind(sigz$AR,sigz$MSM,sigz$MRS9,sigz$Jump,sigz$Cascade,sigz$Trend,sigz$RealizedVol,sigz$Drawdown,sigz$GMM),na.rm=TRUE)
pg("signals built: %d engines\n",length(sigz))

## ── 효율적 score (누적 조건부 IC) ──
anc<-c(-1,0,1)
build_score<-function(z){ mem<-t(sapply(z,function(zz){e<-exp(anc*zz);e/sum(e)}))
  MEM<-data.table(signal_date=sig_dates,wr=mem[,1],wn=mem[,2],wc=mem[,3])
  G<-merge(gic0,MEM,by="signal_date");setorder(G,family,signal_date);G[is.na(ic),ic:=NA]
  # 누적 조건부 IC (PIT: shift 1)
  for(st in c("wr","wn","wc")){G[,paste0("ci_",st):=shift(cumsum(fifelse(is.finite(ic),ic*get(st),0))/cumsum(fifelse(is.finite(ic),get(st),0)),1),by=family]}
  G[,mu:=wr*ci_wr+wn*ci_wn+wc*ci_wc]; G[!is.finite(mu),mu:=0]; G[,muw:=pmax(mu,0)]
  MU<-dcast(G,signal_date~family,value.var="muw"); for(fm in grp)if(!fm%in%names(MU))MU[[fm]]<-0
  for(j in grp)set(MU,which(is.na(MU[[j]])),j,0)   # data.table NA-fill (dt[is.na(dt)]<-0 안 먹힘)
  rows<-list()
  for(d in as.character(sig_dates)){dd<-as.Date(d);mw<-as.numeric(MU[signal_date==dd,..grp]);mw[is.na(mw)]<-0;if(length(mw)==0||sum(mw)<1e-9)mw<-rep(1,length(grp));mw<-mw/sum(mw)
    sub<-gw[signal_date==dd];X<-as.matrix(sub[,..grp]);X[is.na(X)]<-0;rows[[d]]<-data.table(signal_date=dd,security_id=sub$security_id,score=as.numeric(X%*%mw))}
  s<-rbindlist(rows);s[,score:=zc(score),by=signal_date];s}
held<-sig_dates[((seq_along(sig_dates)-1)%%3)==0];toq<-function(sc){ff<-list();for(d in sig_dates){src<-max(held[held<=d]);ff[[as.character(d)]]<-sc[signal_date==src][,signal_date:=d]};rbindlist(ff)}
gates<-function(sc,lab){if(is.null(sc)||nrow(sc)==0){pg("  NULL sc %s\n",lab);return(NULL)}
  cs<-tryCatch(canonical_screen_bt(sc[,.(Date=as.Date(signal_date),Ticker=security_id,score)],fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)],fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)],top_n=25L,cost_bps_oneway=15,liq_dt=fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)],liq_min=2e8,run_id="bo",strategy_id=lab),error=function(e){pg("  cs ERR %s: %s\n",lab,substr(conditionMessage(e),1,40));NULL})
  if(is.null(cs)){return(NULL)};if(is.null(cs$period_returns)){pg("  no pr %s\n",lab);return(NULL)};pr<-as.data.table(cs$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr)
  rets<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA})
  nav<-cumprod(1+pr$ret_net);dd<-min(nav/cummax(nav)-1);ann<-prod(1+pr$ret_net)^(12/n)-1;cal<-if(dd<0)ann/abs(dd)else NA
  data.table(engine=lab,pt_capwt=nwt(act),oos_reten=median(rets,na.rm=T),calmar=cal,full_IR=IRf(act),TO=cs$turnover_annual)}
R<-list()
for(nm in names(sigz)){pg("engine %s\n",nm);scb<-tryCatch(toq(build_score(sigz[[nm]])),error=function(e){pg("  build ERR %s: %s\n",nm,substr(conditionMessage(e),1,40));NULL});R[[nm]]<-gates(scb,nm)}
RES<-rbindlist(Filter(Negate(is.null),R),fill=TRUE)
if(nrow(RES)==0){w("ALL gates NULL — 진단 _bo_prog.txt 참조");saveRDS(RES,".cache/_ramp_bakeoff.rds");close(con);cat("BAKEOFF_DONE\n");quit(save="no")}
RES<-RES[order(-pt_capwt)]
w("=== 국면엔진 리서치풀 × RAMP (quarterly, cap-w, 게이트 2.95/0.7/0.64) — pt 내림차순 ===")
w(sprintf("  %-12s %8s %9s %7s %7s %6s","engine","pt_capwt","oos_reten","calmar","full_IR","TO"))
for(i in seq_len(nrow(RES)))w(sprintf("  %-12s %+8.2f %+9.2f %+7.2f %+7.2f %6.1f",RES$engine[i],RES$pt_capwt[i],RES$oos_reten[i],RES$calmar[i],RES$full_IR[i],RES$TO[i]))
b<-RES[1];w(sprintf("\n최고 pt: %s (%.2f). 게이트 통과: %s",b$engine,b$pt_capwt,if(any(RES$pt_capwt>=2.95&RES$oos_reten>=0.7&RES$calmar>=0.64))"있음"else"없음(전부 미달)"))
saveRDS(RES,".cache/_ramp_bakeoff.rds");close(con);cat("BAKEOFF_DONE\n")
