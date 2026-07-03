## run_ramp_regime_strengthen.R — 국면엔진 강화(도훈): PIT 트레일링-실력 가중 스마트 앙상블.
## bake-off 교훈(순진 z평균<최고단독) 극복: 상위 5엔진 각자 M_regdd score를 *트레일링 active-IR*로 가중결합.
## 매월 최근 잘 맞춘 엔진에 더 비중(walk-forward, 과적합 아님). vs Cascade(최고단독 2.85). quarterly·실측.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
suppressMessages({library(sandwich);library(lmtest)})
con<-file(".cache/_ramp_strengthen.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)
PG<-".cache/_st_prog.txt"; cat("start\n",file=PG); pg<-function(...)cat(sprintf(...),file=PG,append=TRUE)
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
me_of<-function(dts){d<-as.Date(dts);mon<-as.integer(format(d,"%m"));yr<-as.integer(format(d,"%Y"));nmon<-ifelse(mon==12L,1L,mon+1L);nyr<-ifelse(mon==12L,yr+1L,yr);out<-as.Date(rep(NA_real_,length(d)));ok<-!is.na(mon)&!is.na(yr);if(any(ok))out[ok]<-as.Date(sprintf("%04d-%02d-01",nyr[ok],nmon[ok]))-1L;out}
expz<-function(v){z<-rep(0,length(v));for(i in seq_along(v)){p<-v[1:i];p<-p[is.finite(p)];if(length(p)>=12){s<-sd(p);if(!is.na(s)&&s>1e-8)z[i]<-(v[i]-mean(p))/s}};z}
to_m<-function(dt,dc,vc){d<-copy(dt);d[,Date:=as.Date(get(dc))];d<-d[!is.na(Date)];d[,ym:=format(Date,"%Y-%m")];m<-d[,.(v=last(get(vc))),by=ym];m[,signal_date:=me_of(as.Date(paste0(ym,"-01")))];m[!is.na(signal_date),.(signal_date,v)]}

g<-as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet"));g[,signal_date:=as.Date(signal_date)]
gw<-dcast(g,signal_date+security_id~family,value.var="group_z");grp<-setdiff(names(gw),c("signal_date","security_id"))
sig_dates<-sort(unique(g$signal_date));SD<-data.table(signal_date=sig_dates)
CF<-".cache/_bo_fwdgic.rds";L<-readRDS(CF);fwd<-L$fwd;gic0<-L$gic0
fwd_ret<-fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)];bench<-fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)];liq<-fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
algn<-function(m){merge(SD,m[!is.na(signal_date),.(signal_date=as.Date(signal_date),z)],by="signal_date",all.x=TRUE)$z}
pg("data loaded\n")

## 상위 5 엔진 stress z
sigz<-list()
sigz$Cascade<-{m<-to_m(as.data.table(read_parquet(".cache/unified_regime_signal_daily.parquet")),"Date","Regime_Score_smooth");m[,z:=expz(v)];algn(m)}
sigz$MSM<-{m<-to_m(as.data.table(read_parquet(".cache/msm_daily_latest.parquet")),"Date","Crisis_Prob");m[,z:=expz(v)];algn(m)}
sigz$MRS9<-{m<-to_m(as.data.table(read_parquet(".cache/regime_daily_v2.parquet")),"Date","MRS");m[,z:=expz(v)];algn(m)}
sigz$AR<-{A<-as.data.table(read_parquet("outputs/ramp/absorption_ratio_signal.parquet"));A[,signal_date:=as.Date(signal_date)];algn(A[,.(signal_date,z=ar_z)])}
bm<-merge(SD,fwd$bench_dt[,.(signal_date=as.Date(Date),bmret=BM_Ret)],by="signal_date",all.x=TRUE);bmv<-bm$bmret;nn<-length(bmv);tr<-rep(0,nn)
for(i in seq_len(nn)){if(i<13)next;h<-bmv[max(1,i-12):(i-1)];tr[i]<- -mean(h,na.rm=T)};sigz$Trend<-expz(tr)
for(nm in names(sigz))sigz[[nm]][is.na(sigz[[nm]])]<-0
pg("signals built\n")

## 엔진별 monthly M_regdd score + monthly active series
anc<-c(-1,0,1)
build_sc<-function(z){mem<-t(sapply(z,function(zz){e<-exp(anc*zz);e/sum(e)}));MEM<-data.table(signal_date=sig_dates,r=mem[,1],n=mem[,2],c=mem[,3])
  gic<-merge(gic0,MEM,by="signal_date");setorder(gic,family,signal_date);rows<-list()
  for(d in as.character(sig_dates)){dd<-as.Date(d);mt<-MEM[signal_date==dd]
    wts<-sapply(grp,function(fm){sub<-gic[family==fm&signal_date<dd];sub<-sub[is.finite(ic)];if(nrow(sub)<3)return(0)
      ics<-c(sum(sub$ic*sub$r)/sum(sub$r),sum(sub$ic*sub$n)/sum(sub$n),sum(sub$ic*sub$c)/sum(sub$c));max(sum(c(mt$r,mt$n,mt$c)*ics,na.rm=T),0)})
    if(sum(wts)<1e-9)wts<-setNames(rep(1,length(grp)),grp);ww<-wts/sum(wts)
    sub<-gw[signal_date==dd];X<-as.matrix(sub[,..grp]);X[is.na(X)]<-0;rows[[d]]<-data.table(signal_date=dd,security_id=sub$security_id,score=as.numeric(X%*%ww))}
  rbindlist(rows)}
csmonthly<-function(sc){cs<-tryCatch(canonical_screen_bt(sc[,.(Date=as.Date(signal_date),Ticker=security_id,score=zc(score))][,score:=zc(score),by=Date],fwd_ret,bench,top_n=25L,cost_bps_oneway=15,liq_dt=liq,liq_min=2e8,run_id="st",strategy_id="e"),error=function(e)NULL)
  if(is.null(cs$period_returns))return(NULL);pr<-as.data.table(cs$period_returns);pr[,act:=ret_net-benchmark_ret];pr[,.(date=as.Date(date),act)]}
ENG<-names(sigz);SCs<-list();ACT<-list()
for(nm in ENG){pg("build %s\n",nm);SCs[[nm]]<-build_sc(sigz[[nm]]);a<-csmonthly(SCs[[nm]]);ACT[[nm]]<-a}
pg("engine scores+active done\n")

## 트레일링 active-IR 가중 (PIT, expanding) → 스마트 결합 score
actwide<-Reduce(function(a,b)merge(a,b,by="date",all=TRUE),lapply(ENG,function(nm){d<-copy(ACT[[nm]]);setnames(d,"act",nm);d}))
setorder(actwide,date);adates<-actwide$date
trIR<-matrix(0,length(adates),length(ENG),dimnames=list(NULL,ENG))
for(i in seq_along(adates))for(j in seq_along(ENG)){h<-actwide[[ENG[j]]][seq_len(i-1)];ir<-IRf(h);trIR[i,j]<-if(is.na(ir))0 else max(ir,0)}
trIRdt<-data.table(date=adates,trIR);  # 각 월의 엔진별 트레일링 IR weight
# 결합 score: 각 월 Σ_e w_e,t · zc(engine_score_e(stock))
combined<-list()
for(d in as.character(sig_dates)){dd<-as.Date(d);wrow<-trIRdt[date==dd]
  ws<-if(nrow(wrow)==0)setNames(rep(1,length(ENG)),ENG)else{v<-as.numeric(wrow[,..ENG]);if(sum(v)<1e-9)rep(1,length(ENG))else v};ws<-ws/sum(ws);names(ws)<-ENG
  parts<-lapply(ENG,function(nm){s<-SCs[[nm]][signal_date==dd];d<-data.table(security_id=s$security_id);d[[paste0("sc_",nm)]]<-zc(s$score)*ws[nm];d})
  m<-Reduce(function(a,b)merge(a,b,by="security_id",all=TRUE),parts)
  scols<-paste0("sc_",ENG);scols<-scols[scols%in%names(m)];m[,score:=rowSums(.SD,na.rm=TRUE),.SDcols=scols]
  combined[[d]]<-data.table(signal_date=dd,security_id=m$security_id,score=m$score)}
scC<-rbindlist(combined);scC[,score:=zc(score),by=signal_date]
pg("combined built\n")

## quarterly + gates (결합 vs Cascade 단독)
held<-sig_dates[((seq_along(sig_dates)-1)%%3)==0];toq<-function(sc){ff<-list();for(d in sig_dates){src<-max(held[held<=d]);ff[[as.character(d)]]<-sc[signal_date==src][,signal_date:=d]};rbindlist(ff)}
gate<-function(sc,lab){cs<-tryCatch(canonical_screen_bt(sc[,.(Date=as.Date(signal_date),Ticker=security_id,score)],fwd_ret,bench,top_n=25L,cost_bps_oneway=15,liq_dt=liq,liq_min=2e8,run_id="stg",strategy_id=lab),error=function(e)NULL)
  if(is.null(cs$period_returns))return(NULL);pr<-as.data.table(cs$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr)
  rets<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA})
  nav<-cumprod(1+pr$ret_net);dd<-min(nav/cummax(nav)-1);ann<-prod(1+pr$ret_net)^(12/n)-1;cal<-if(dd<0)ann/abs(dd)else NA
  data.table(model=lab,pt_capwt=nwt(act),oos_reten=median(rets,na.rm=T),calmar=cal,full_IR=IRf(act),TO=cs$turnover_annual)}
R<-rbindlist(Filter(Negate(is.null),list(gate(toq(SCs$Cascade),"Cascade단독(best)"),gate(toq(scC),"스마트앙상블(IR가중)"))),fill=TRUE)
w("=== 국면엔진 강화: 트레일링-IR 가중 스마트 앙상블 vs Cascade 단독 (게이트 2.95/0.7/0.64) ===")
w(sprintf("  %-22s %8s %9s %7s %7s %6s","model","pt_capwt","oos_reten","calmar","full_IR","TO"))
for(i in seq_len(nrow(R)))w(sprintf("  %-22s %+8.2f %+9.2f %+7.2f %+7.2f %6.1f",R$model[i],R$pt_capwt[i],R$oos_reten[i],R$calmar[i],R$full_IR[i],R$TO[i]))
w("\n엔진별 평균 트레일링 IR 가중(스마트앙상블이 누구를 신뢰했나):")
aw<-colMeans(trIR);for(nm in ENG)w(sprintf("  %-10s %.3f",nm,aw[nm]/sum(aw)))
saveRDS(list(R=R,trIRdt=trIRdt),".cache/_ramp_strengthen.rds");close(con);cat("STRENGTHEN_DONE\n")
