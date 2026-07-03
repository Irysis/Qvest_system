## run_ramp_pergroup_jump.R — 새 국면엔진(Shu-Mulvey 2024, arXiv 2410.14841): Per-Group Jump-Model Regime.
## 시장국면 아닌 *각 팩터군의 자기 성과 주기성*에서 국면 추론. 각 군 IC 시계열에 2-state jump model(점프페널티
##   λ로 과전환 억제, Nystrup/Shu SJM) walk-forward → "그 군이 통하는 국면" P(working). 그걸로 군 가중.
## vs Cascade단독(2.85, 시장국면 최고). PIT(expanding, refit 12m). quarterly·실측.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
suppressMessages({library(sandwich);library(lmtest)})
con<-file(".cache/_ramp_pgjump.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)
PG<-".cache/_pg_prog.txt"; cat("start\n",file=PG); pg<-function(...)cat(sprintf(...),file=PG,append=TRUE)
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
ewm<-function(x,hl){a<-1-exp(log(0.5)/hl);y<-rep(NA_real_,length(x));acc<-NA;for(i in seq_along(x)){xi<-x[i];if(is.na(xi)){y[i]<-acc;next};acc<-if(is.na(acc))xi else a*xi+(1-a)*acc;y[i]<-acc};y}

## 2-state jump model (1-D, 점프페널티 DP) — Shu/Nystrup SJM
jump_states<-function(x,lam){x<-as.numeric(x);n<-length(x);if(n<12)return(rep(NA,n))
  th<-as.numeric(quantile(x,c(.35,.65),na.rm=T));if(diff(th)<1e-9)th<-c(mean(x)-sd(x),mean(x)+sd(x))
  s<-ifelse(x<=median(x,na.rm=T),1L,2L)
  for(it in 1:15){for(k in 1:2)if(any(s==k,na.rm=T))th[k]<-mean(x[s==k],na.rm=T)
    C<-cbind((x-th[1])^2,(x-th[2])^2);C[is.na(C)]<-0
    D<-matrix(Inf,n,2);bp<-matrix(1L,n,2);D[1,]<-C[1,]
    for(t in 2:n)for(k in 1:2){cand<-D[t-1,]+c(if(k==1)0 else lam,if(k==2)0 else lam);j<-which.min(cand);D[t,k]<-C[t,k]+cand[j];bp[t,k]<-j}
    ns<-integer(n);ns[n]<-which.min(D[n,]);for(t in (n-1):1)ns[t]<-bp[t+1,ns[t+1]];s<-ns}
  list(s=s,th=th,wk=which.max(th))}

g<-as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet"));g[,signal_date:=as.Date(signal_date)]
gw<-dcast(g,signal_date+security_id~family,value.var="group_z");grp<-setdiff(names(gw),c("signal_date","security_id"))
sig_dates<-sort(unique(g$signal_date));SD<-data.table(signal_date=sig_dates)
CF<-".cache/_bo_fwdgic.rds";L<-readRDS(CF);fwd<-L$fwd;gic0<-L$gic0
fwd_ret<-fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)];bench<-fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)];liq<-fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
pg("data loaded\n")

## 각 군 IC 시계열 + EWM smooth(성과 피처) → per-group jump regime P(working), walk-forward PIT
LAM<-2.0; REFIT<-12L
pw<-data.table(signal_date=sig_dates)  # group별 P(working)
for(fm in grp){ ics<-merge(SD,gic0[family==fm,.(signal_date,ic)],by="signal_date",all.x=TRUE)$ic
  sic<-ewm(ifelse(is.finite(ics),ics,NA),6)  # EWM-smooth IC (HL=6m) = 성과 피처
  P<-rep(0.5,length(sig_dates)); st<-NULL
  for(i in seq_along(sig_dates)){ if(i<24){next}
    if(is.null(st)||((i)%%REFIT==0)){ hi<-sic[1:(i-1)];hi<-hi[is.finite(hi)];if(length(hi)>=12){st<-jump_states(hi,LAM)} }  # refit on past
    if(!is.null(st)){ mid<-mean(st$th);scl<-max(abs(diff(st$th))/4,1e-6);cur<-sic[i-1]  # PIT: t-1 smoothed IC
      if(is.finite(cur)){pwk<-1/(1+exp(-(cur-mid)/scl));P[i]<-if(st$wk==2)pwk else 1-pwk} } }
  pw[[fm]]<-P }
pg("per-group regimes built\n")
w("=== Per-Group Jump Regime — 군별 평균 P(working) (자기 국면 추론) ===")
for(fm in grp)w(sprintf("  %-16s P(working) 평균 %.2f",fm,mean(pw[[fm]],na.rm=T)))

## M_regdd score: 군 가중 = P(working_g,t) × max(trailing IC_g,0)
gicw<-merge(gic0,SD,by="signal_date",all.y=TRUE);setorder(gicw,family,signal_date)
build<-function(){rows<-list()
  for(d in as.character(sig_dates)){dd<-as.Date(d);prow<-pw[signal_date==dd]
    wts<-sapply(grp,function(fm){p<-gic0[family==fm&signal_date<dd,ic];p<-p[is.finite(p)];ti<-if(length(p)>=3)max(mean(p),0)else 0
      pwork<-prow[[fm]];if(length(pwork)==0||is.na(pwork))pwork<-0.5; ti*pwork})
    if(sum(wts)<1e-9)wts<-setNames(rep(1,length(grp)),grp);ww<-wts/sum(wts)
    sub<-gw[signal_date==dd];X<-as.matrix(sub[,..grp]);X[is.na(X)]<-0;rows[[d]]<-data.table(signal_date=dd,security_id=sub$security_id,score=as.numeric(X%*%ww))}
  s<-rbindlist(rows);s[,score:=zc(score),by=signal_date];s}
pg("scoring\n");scPG<-build()
held<-sig_dates[((seq_along(sig_dates)-1)%%3)==0];toq<-function(sc){ff<-list();for(d in sig_dates){src<-max(held[held<=d]);ff[[as.character(d)]]<-sc[signal_date==src][,signal_date:=d]};rbindlist(ff)}
gate<-function(sc,lab){cs<-tryCatch(canonical_screen_bt(sc[,.(Date=as.Date(signal_date),Ticker=security_id,score)],fwd_ret,bench,top_n=25L,cost_bps_oneway=15,liq_dt=liq,liq_min=2e8,run_id="pg",strategy_id=lab),error=function(e)NULL)
  if(is.null(cs$period_returns))return(NULL);pr<-as.data.table(cs$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr)
  rets<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA})
  nav<-cumprod(1+pr$ret_net);dd<-min(nav/cummax(nav)-1);ann<-prod(1+pr$ret_net)^(12/n)-1;cal<-if(dd<0)ann/abs(dd)else NA
  data.table(model=lab,pt_capwt=nwt(act),oos_reten=median(rets,na.rm=T),calmar=cal,full_IR=IRf(act),TO=cs$turnover_annual)}
R<-gate(toq(scPG),"PerGroupJump(Shu-Mulvey)")
w("\n=== 새 국면엔진: Per-Group Jump Regime (Shu-Mulvey 2024) vs Cascade단독 2.85 (게이트 2.95/0.7/0.64) ===")
w(sprintf("  %-26s %8s %9s %7s %7s %6s","model","pt_capwt","oos_reten","calmar","full_IR","TO"))
if(!is.null(R))w(sprintf("  %-26s %+8.2f %+9.2f %+7.2f %+7.2f %6.1f",R$model[1],R$pt_capwt[1],R$oos_reten[1],R$calmar[1],R$full_IR[1],R$TO[1]))
w(sprintf("  %-26s %+8.2f %+9.2f %+7.2f %+7.2f %6.1f","Cascade단독(기준)",2.85,-0.02,0.40,0.62,6.2))
saveRDS(R,".cache/_ramp_pgjump.rds");close(con);cat("PGJUMP_DONE\n")
