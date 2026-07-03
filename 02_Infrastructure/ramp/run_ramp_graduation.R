## run_ramp_graduation.R — RAMP M-code graduation 게이트 평가 (Score 단계 수리 포함)
## 게이트(measurement-graduation §3, vs EW-universe): port_t≥2.95 · oos_retention≥0.7 · calmar≥0.64 · DSR≥0.5(sweep).
## 변형: 현 best(regime_dd) + 회전제어(분기 리밸=hysteresis). 단일스레드·실측-only.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R"); source("02_Infrastructure/ramp/ramp_loop.R")
suppressMessages({library(sandwich);library(lmtest)})
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9) x-m else (x-m)/s}
con<-file(".cache/_ramp_grad.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)
N_TRIALS<-14L  # 누적 탐색 config 수 (DSR deflation)

g<-as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet")); g[,signal_date:=as.Date(signal_date)]
gw<-dcast(g,signal_date+security_id~family,value.var="group_z"); grp<-setdiff(names(gw),c("signal_date","security_id"))
a<-as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); a[,Date:=as.Date(Date)]
reg<-unique(a[,.(ym=format(Date,"%Y-%m"),regime=regime_state)])[,.SD[1],by=ym]
gw[,ym:=format(signal_date,"%Y-%m")]; gw<-merge(gw,reg,by="ym",all.x=TRUE); gw[is.na(regime),regime:="NORMAL"]
## [2026-06-18] col_select — full 14M×21col(2.5GB) 풀로드 세그폴트 회피.
.need<-c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata<-as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
sig_dates<-sort(unique(gw$signal_date)); fwd<-build_monthly_forward_returns(rawdata,sig_dates)
oos_cut<-sig_dates[length(sig_dates)-23]
ewb<-fwd$returns_dt[,.(ew=mean(Ret_1m,na.rm=TRUE)),by=.(date=as.Date(Date))]

# regime_dd score
ic<-merge(g[,.(signal_date,security_id,family,group_z)],fwd$returns_dt[,.(signal_date=as.Date(Date),security_id=Ticker,Ret_1m)],by=c("signal_date","security_id"))
gic<-ic[,.(ic=if(.N>=10&&sd(group_z)>0&&sd(Ret_1m)>0)cor(group_z,Ret_1m,method="spearman")else NA_real_),by=.(signal_date,family)]
gic<-merge(gic,unique(gw[,.(signal_date,regime)]),by="signal_date"); setorder(gic,family,signal_date)
mk_score<-function(){rows<-list()
  for(d in as.character(sig_dates)){dd<-as.Date(d);rg<-gw[signal_date==dd,regime][1]
    wts<-sapply(grp,function(fm){p<-gic[family==fm&regime==rg&signal_date<dd,ic];p<-p[is.finite(p)];if(length(p)>=3)max(mean(p),0)else 0})
    if(sum(wts)<1e-9)wts<-setNames(rep(1,length(grp)),grp);ww<-wts/sum(wts)
    sub<-gw[signal_date==dd];X<-as.matrix(sub[,..grp]);X[is.na(X)]<-0
    rows[[d]]<-data.table(signal_date=dd,security_id=sub$security_id,score=as.numeric(X%*%ww))}
  s<-rbindlist(rows); s[,score:=zc(score),by=signal_date]; s}
sc<-mk_score()

# 게이트 계산: period_returns(vs EW-uni) → port_t/oos_retention/calmar/DSR
gates<-function(sc,lab){
  cs<-tryCatch(canonical_screen_bt(sc[,.(Date=as.Date(signal_date),Ticker=security_id,score)],
        fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)],fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)],
        top_n=25L,cost_bps_oneway=15,liq_dt=fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)],liq_min=2e8,run_id="grad",strategy_id=lab),error=function(e)NULL)
  if(is.null(cs$period_returns))return(NULL)
  pr<-as.data.table(cs$period_returns); pr[,date:=as.Date(date)]; pr<-merge(pr,ewb,by="date",all.x=TRUE)
  pr[,act:=ret_net-ew]; pr[,is_oos:=date>=oos_cut]
  srf<-function(x)mean(x,na.rm=T)/sd(x,na.rm=T)*sqrt(12)
  is_sr<-srf(pr[is_oos==F,act]); oos_sr<-srf(pr[is_oos==T,act]); full_sr<-srf(pr$act)
  nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
  pt<-nwt(pr$act)
  # [2026-06-18 감사반영] 계약-authoritative 벤치(cap-weighted KOSPI200 BM_Ret) 대비 port_t 동시 산출.
  # EW-universe(pt)는 factor-neutral 진단, cap-weighted(pt_bm)는 §2 계약 게이트-바인딩. KR 소형주틸트로 EW가 ~+1.3t 낙관적.
  pt_bm<-nwt(pr$ret_net - pr$benchmark_ret)
  # calmar (port own): ann ret / |maxDD|
  nav<-cumprod(1+pr$ret_net); dd<-min(nav/cummax(nav)-1); ann<-prod(1+pr$ret_net)^(12/nrow(pr))-1
  cal<-if(dd<0) ann/abs(dd) else NA
  # DSR (deflated, n_trials)
  sr_m<-mean(pr$act)/sd(pr$act); n<-nrow(pr); sk<-tryCatch(e1071::skewness(pr$act),error=function(e)0); ku<-tryCatch(e1071::kurtosis(pr$act)+3,error=function(e)3)
  den<-sqrt((1-sk*sr_m+(ku-1)/4*sr_m^2)/(n-1)); dsr_raw<-if(den>1e-10)(sr_m*sqrt(12))/(den*sqrt(12))else NA
  dsr<-if(!is.na(dsr_raw))dsr_raw-N_TRIALS*0.05 else NA  # 다중검정 deflation
  # oos_retention v2 (규약: anchored 3-split {55/65/75} 중앙값 — 단일-24m보다 robust, full-cycle 공정)
  .splits<-c(0.55,0.65,0.75); .rets<-sapply(.splits,function(fr){k<-floor(nrow(pr)*fr); if(k<12||(nrow(pr)-k)<6)return(NA_real_)
    .is<-srf(pr$act[1:k]); .oo<-srf(pr$act[(k+1):nrow(pr)]); if(!is.na(.is)&&.is>0) .oo/.is else NA_real_})
  retn<-median(.rets,na.rm=TRUE)
  data.table(model=lab, port_t=pt, port_t_capwt=pt_bm, oos_retention=retn, calmar=cal, dsr=dsr, full_sr=full_sr, is_sr=is_sr, oos_sr=oos_sr, turnover=cs$turnover_annual)
}

ramp_observe(verbose=FALSE)
G<-list(); G$base<-gates(sc,"M_regdd")
# 회전제어: 분기 리밸 (3개월마다만 score 갱신, 사이 hold)
scq<-copy(sc); setorder(scq,security_id,signal_date)
qmap<-data.table(signal_date=sig_dates, qkey=rep(seq_along(sig_dates),each=1)); qmap[,qkey:=((seq_len(.N)-1)%/%3)]
held<-sig_dates[((seq_along(sig_dates)-1)%%3)==0]  # 분기 시작월만 갱신
scq2<-sc[signal_date %in% held]
# forward-fill: 각 분기 시작 score를 다음 2개월에 복제
ff<-list(); for(i in seq_along(sig_dates)){d<-sig_dates[i]; src<-max(held[held<=d]); ff[[as.character(d)]]<-scq2[signal_date==src][,signal_date:=d]}
scq3<-rbindlist(ff)
G$quarterly<-gates(scq3,"M_regdd_quarterly")
R<-rbindlist(Filter(Negate(is.null),G),fill=TRUE)

w("=== RAMP graduation 게이트 (n_trials=14 DSR) ===")
w(sprintf("  %-20s %8s %9s %10s %7s %7s %7s","model","pt_EWuni","pt_capwt","oos_reten","calmar","DSR","TO"))
for(i in seq_len(nrow(R)))w(sprintf("  %-20s %+8.2f %+9.2f %+10.2f %+7.2f %+7.2f %7.1f",R$model[i],R$port_t[i],R$port_t_capwt[i],R$oos_retention[i],R$calmar[i],R$dsr[i],R$turnover[i]))
w("\n  pt_EWuni = factor-neutral 진단 / pt_capwt = §2 계약 게이트-바인딩(authoritative)")
w("게이트 HARD: port_t(capwt)≥2.95 · oos_retention≥0.7 · calmar≥0.64 · DSR≥0.5")
for(i in seq_len(nrow(R))){r<-R[i]
  p<-c(port_t=isTRUE(r$port_t_capwt>=2.95),oos=isTRUE(r$oos_retention>=0.7),cal=isTRUE(r$calmar>=0.64),dsr=isTRUE(r$dsr>=0.5))
  w(sprintf("  [%s] %s → %s", r$model, paste(names(p),ifelse(p,"✓","✗"),collapse=" "), ifelse(all(p),"★GRADUATION","미달")))}
b<-R[which.max(port_t)]
ramp_document(strategy_id=sprintf("RAMP_GRADUATION_%s",format(Sys.Date(),"%Y%m%d")),grade=ifelse(!is.na(b$port_t)&&b$port_t>=2.95,"A","B"),
  lesson_text=sprintf("Graduation 시도: best=%s port_t=%.2f oos_reten=%.2f calmar=%.2f DSR=%.2f (vs EW-uni). 게이트 HARD(2.95/0.7/0.64/0.5) 판정.",b$model,b$port_t,b$oos_retention,b$calmar,b$dsr),
  metrics=list(port_t=b$port_t,oos_retention=b$oos_retention,calmar=b$calmar,dsr=b$dsr),core_reference="RAMP graduation gate eval")
saveRDS(R,".cache/_ramp_grad.rds"); close(con); cat("GRAD_DONE\n")
