## run_ramp_regime_multiaxis.R — 국면엔진 강화 v2(도훈): multi-axis 분업.
## 스마트앙상블 실패(엔진 redundant→평균이 최고 희석) 극복: 각 팩터군을 *경제적으로 맞는* 국면엔진에 조건화.
## 사전등록 매핑(과적합 아님): 모멘텀↔Trend / 방어(LowRisk·Quality)↔MRS9변동성 / 밸류·경기↔Cascade / 위기민감↔MSM.
## vs Cascade 단독(2.85). PIT(각 엔진 trailing). quarterly·실측.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
suppressMessages({library(sandwich);library(lmtest)})
con<-file(".cache/_ramp_multiaxis.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)
PG<-".cache/_ma_prog.txt"; cat("start\n",file=PG); pg<-function(...)cat(sprintf(...),file=PG,append=TRUE)
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

## 엔진 stress z → soft membership
sigz<-list()
sigz$Cascade<-{m<-to_m(as.data.table(read_parquet(".cache/unified_regime_signal_daily.parquet")),"Date","Regime_Score_smooth");m[,z:=expz(v)];algn(m)}
sigz$MSM<-{m<-to_m(as.data.table(read_parquet(".cache/msm_daily_latest.parquet")),"Date","Crisis_Prob");m[,z:=expz(v)];algn(m)}
sigz$MRS9<-{m<-to_m(as.data.table(read_parquet(".cache/regime_daily_v2.parquet")),"Date","MRS");m[,z:=expz(v)];algn(m)}
bm<-merge(SD,fwd$bench_dt[,.(signal_date=as.Date(Date),bmret=BM_Ret)],by="signal_date",all.x=TRUE);bmv<-bm$bmret;tr<-rep(0,length(bmv))
for(i in seq_along(bmv)){if(i<13)next;tr[i]<- -mean(bmv[max(1,i-12):(i-1)],na.rm=T)};sigz$Trend<-expz(tr)
for(nm in names(sigz))sigz[[nm]][is.na(sigz[[nm]])]<-0
anc<-c(-1,0,1);MEMs<-list()
for(nm in names(sigz)){sm<-t(sapply(sigz[[nm]],function(zz){e<-exp(anc*zz);e/sum(e)}));MEMs[[nm]]<-data.table(signal_date=sig_dates,r=sm[,1],n=sm[,2],c=sm[,3])}
pg("memberships built\n")

## 사전등록 group→axis 매핑 (경제논리)
axis_of<-function(fm){ if(fm%in%c("Momentum","Reversal"))"Trend"
  else if(fm%in%c("LowRisk","Quality"))"MRS9"
  else if(fm%in%c("Value","Growth_Profit","Accruals","Credit"))"Cascade"
  else "MSM" }   # Consensus·Size_Liquidity·Composite → MSM(위기민감)
w("=== group→국면축 분업 매핑 ===")
for(fm in grp)w(sprintf("  %-16s → %s",fm,axis_of(fm)))

## M_regdd score: 각 군 conditional IC를 *그 군의 축* membership으로
build_multiaxis<-function(){ GIC<-lapply(names(MEMs),function(nm){x<-merge(gic0,MEMs[[nm]],by="signal_date");setorder(x,family,signal_date);x});names(GIC)<-names(MEMs)
  rows<-list()
  for(d in as.character(sig_dates)){dd<-as.Date(d)
    wts<-sapply(grp,function(fm){ax<-axis_of(fm);gic<-GIC[[ax]];mt<-MEMs[[ax]][signal_date==dd]
      sub<-gic[family==fm&signal_date<dd];sub<-sub[is.finite(ic)];if(nrow(sub)<3)return(0)
      ics<-c(sum(sub$ic*sub$r)/sum(sub$r),sum(sub$ic*sub$n)/sum(sub$n),sum(sub$ic*sub$c)/sum(sub$c));max(sum(c(mt$r,mt$n,mt$c)*ics,na.rm=T),0)})
    if(sum(wts)<1e-9)wts<-setNames(rep(1,length(grp)),grp);ww<-wts/sum(wts)
    sub<-gw[signal_date==dd];X<-as.matrix(sub[,..grp]);X[is.na(X)]<-0;rows[[d]]<-data.table(signal_date=dd,security_id=sub$security_id,score=as.numeric(X%*%ww))}
  s<-rbindlist(rows);s[,score:=zc(score),by=signal_date];s}
# Cascade 단독 (비교)
build_single<-function(nm){MEM<-MEMs[[nm]];gic<-merge(gic0,MEM,by="signal_date");setorder(gic,family,signal_date);rows<-list()
  for(d in as.character(sig_dates)){dd<-as.Date(d);mt<-MEM[signal_date==dd]
    wts<-sapply(grp,function(fm){sub<-gic[family==fm&signal_date<dd];sub<-sub[is.finite(ic)];if(nrow(sub)<3)return(0)
      ics<-c(sum(sub$ic*sub$r)/sum(sub$r),sum(sub$ic*sub$n)/sum(sub$n),sum(sub$ic*sub$c)/sum(sub$c));max(sum(c(mt$r,mt$n,mt$c)*ics,na.rm=T),0)})
    if(sum(wts)<1e-9)wts<-setNames(rep(1,length(grp)),grp);ww<-wts/sum(wts)
    sub<-gw[signal_date==dd];X<-as.matrix(sub[,..grp]);X[is.na(X)]<-0;rows[[d]]<-data.table(signal_date=dd,security_id=sub$security_id,score=as.numeric(X%*%ww))}
  s<-rbindlist(rows);s[,score:=zc(score),by=signal_date];s}
pg("scoring\n");scMA<-build_multiaxis();scCA<-build_single("Cascade")
held<-sig_dates[((seq_along(sig_dates)-1)%%3)==0];toq<-function(sc){ff<-list();for(d in sig_dates){src<-max(held[held<=d]);ff[[as.character(d)]]<-sc[signal_date==src][,signal_date:=d]};rbindlist(ff)}
gate<-function(sc,lab){cs<-tryCatch(canonical_screen_bt(sc[,.(Date=as.Date(signal_date),Ticker=security_id,score)],fwd_ret,bench,top_n=25L,cost_bps_oneway=15,liq_dt=liq,liq_min=2e8,run_id="ma",strategy_id=lab),error=function(e)NULL)
  if(is.null(cs$period_returns))return(NULL);pr<-as.data.table(cs$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr)
  rets<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA})
  nav<-cumprod(1+pr$ret_net);dd<-min(nav/cummax(nav)-1);ann<-prod(1+pr$ret_net)^(12/n)-1;cal<-if(dd<0)ann/abs(dd)else NA
  data.table(model=lab,pt_capwt=nwt(act),oos_reten=median(rets,na.rm=T),calmar=cal,full_IR=IRf(act),TO=cs$turnover_annual)}
R<-rbindlist(Filter(Negate(is.null),list(gate(toq(scCA),"Cascade단독(best)"),gate(toq(scMA),"Multi-axis 분업"))),fill=TRUE)
w("\n=== 국면엔진 강화 v2: multi-axis 분업 vs Cascade 단독 (게이트 2.95/0.7/0.64) ===")
w(sprintf("  %-20s %8s %9s %7s %7s %6s","model","pt_capwt","oos_reten","calmar","full_IR","TO"))
for(i in seq_len(nrow(R)))w(sprintf("  %-20s %+8.2f %+9.2f %+7.2f %+7.2f %6.1f",R$model[i],R$pt_capwt[i],R$oos_reten[i],R$calmar[i],R$full_IR[i],R$TO[i]))
saveRDS(R,".cache/_ramp_multiaxis.rds");close(con);cat("MULTIAXIS_DONE\n")
