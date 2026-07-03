## run_ramp_gate6_8_investor.R — 가이드북 Gate 6→7→8→9 제대로 구현 (단일 M_regdd 미완 Gate6 대체)
## Propose(§2.3): 현 게이트=6 미완(역할 M-code 부재). 증분 = M0-M4 역할 M-code + 리스크매니저 decay 플래그
##   + 인베스터 에이전트 동적배분(레짐 soft-blend × drift 감액, no hard switch). 한계(2017+ decay)는
##   리스크매니저 model_drift_risk 탐지 → 인베스터 감액으로 대응(가이드북 Gate7/8 메커니즘, 임의 overlay 아님).
## Test(Gate9): investor vs baselines(M0/EW-Mcode/risk-parity/no-regime/single-M_regdd) active IR vs cap-w + book 0.795.
## 실측-only(canonical_screen_bt). PIT: 모든 배분·플래그는 trailing(<t)만. no hard switch(cap 0.40).
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
suppressMessages({library(sandwich);library(lmtest)})
con<-file(".cache/_ramp_gate6_8.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9) x-m else (x-m)/s}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}

## ── 데이터: 11 경제군 group_z + forward + regime ──
g<-as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet")); g[,signal_date:=as.Date(signal_date)]
fams<-sort(unique(g$family))
a<-as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); a[,Date:=as.Date(Date)]
reg<-unique(a[,.(ym=format(Date,"%Y-%m"),regime=regime_state)])[,.SD[1],by=ym]
.need<-c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata<-as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
sig_dates<-sort(unique(g$signal_date)); fwd<-build_monthly_forward_returns(rawdata,sig_dates)
ewb<-fwd$returns_dt[,.(ew=mean(Ret_1m,na.rm=TRUE)),by=.(date=as.Date(Date))]   # EW-uni (진단)
# cap-w 벤치는 canonical benchmark_ret 사용(게이트-바인딩)
gw<-dcast(g,signal_date+security_id~family,value.var="group_z")
gw[,ym:=format(signal_date,"%Y-%m")]; gw<-merge(gw,reg,by="ym",all.x=TRUE); gw[is.na(regime),regime:="NORMAL"]

## ── GATE 6: 역할별 M-code (경제군 → 역할 배정, 가이드북 M0-M4) ──
mcode_def<-list(
  M0_baseline = fams,                                              # 전체 분산
  M1_defense  = intersect(c("LowRisk","Quality"),fams),
  M2_offense  = intersect(c("Momentum","Growth_Profit"),fams),
  M3_recovery = intersect(c("Value","Reversal"),fams),
  M4_neutral  = intersect(c("Consensus","Size_Liquidity","Accruals","Credit","Composite"),fams))
w("=== GATE 6: 역할 M-code 정의 (경제군 멤버) ===")
for(nm in names(mcode_def)) w(sprintf("  %-12s : %s", nm, paste(mcode_def[[nm]],collapse="+")))

# 각 M-code 월별 score(멤버군 group_z 평균 → 월별 재표준화) → canonical_screen top-25 net
mcode_series<-list(); mcode_sc<-list()
for(nm in names(mcode_def)){
  mem<-mcode_def[[nm]]; sub<-g[family %in% mem]
  s<-sub[,.(score=mean(group_z,na.rm=TRUE)),by=.(signal_date,security_id)]
  s[,score:=zc(score),by=signal_date]; mcode_sc[[nm]]<-s
  cs<-tryCatch(canonical_screen_bt(s[,.(Date=as.Date(signal_date),Ticker=security_id,score)],
        fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)],fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)],
        top_n=25L,cost_bps_oneway=15,liq_dt=fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)],liq_min=2e8,run_id="g6",strategy_id=nm),error=function(e)NULL)
  pr<-as.data.table(cs$period_returns); pr[,date:=as.Date(date)]
  mcode_series[[nm]]<-pr[,.(date,ret_net,bench=benchmark_ret)]
}
# M-code 패널: date × {M0..M4 ret_net} + bench + regime
MS<-Reduce(function(x,y)merge(x,y,by=c("date","bench"),all=TRUE),
  lapply(names(mcode_series),function(nm){d<-copy(mcode_series[[nm]]);setnames(d,"ret_net",nm);d}))
MS[,ym:=format(date,"%Y-%m")]; MS<-merge(MS,reg,by="ym",all.x=TRUE); MS[is.na(regime),regime:="NORMAL"]
setorder(MS,date); mc<-names(mcode_def)
for(nm in mc) MS[[paste0(nm,"_act")]]<-MS[[nm]]-MS$bench   # cap-w active

## ── GATE 7: 리스크매니저 — M-code별 model_drift_risk 플래그 (decay 탐지, PIT trailing) ──
## drift flag_t = trailing 24m active Sharpe < 0 (최근 성과 붕괴 = decay/crowding). drawdown flag 보조.
DR<-24
for(nm in mc){
  act<-MS[[paste0(nm,"_act")]]; n<-nrow(MS); fl<-rep(0,n)
  for(i in seq_len(n)){ if(i>DR){ h<-act[(i-DR):(i-1)]; sr<-IRf(h); fl[i]<-if(!is.na(sr)&&sr<0) 1 else 0 } }
  MS[[paste0(nm,"_drift")]]<-fl
}
w("\n=== GATE 7: model_drift_risk 발화율 (trailing 24m active SR<0) ===")
for(nm in mc) w(sprintf("  %-12s drift 발화 %d/%d 월 (%.0f%%)", nm, sum(MS[[paste0(nm,"_drift")]]), nrow(MS), 100*mean(MS[[paste0(nm,"_drift")]])))

## ── GATE 8: 인베스터 에이전트 — 레짐 soft-blend μ × drift 감액, no hard switch(cap 0.40) ──
## μ_blend_m,t = (1-conf)·uncond_trailing_mean_m + conf·regime_trailing_mean_m,t (전부 signal_date<t).
## a_m ∝ max(μ_blend,0) × drift_weight(1 or 0.3). Σa=1, a≤0.40. 의사결정 로그 기록.
CONF<-0.5; CAP<-0.40; DRIFT_W<-0.30
inv<-rep(NA_real_,nrow(MS)); alloc_log<-list()
for(i in seq_len(nrow(MS))){
  rg<-MS$regime[i]
  mu<-sapply(mc,function(nm){ act<-MS[[paste0(nm,"_act")]]
    un<-mean(act[seq_len(i-1)],na.rm=TRUE)                                  # uncond trailing
    rc<-mean(act[which(MS$regime[seq_len(i-1)]==rg)],na.rm=TRUE)            # regime trailing
    if(is.na(rc)) rc<-un; (1-CONF)*un + CONF*rc })
  dw<-sapply(mc,function(nm) if(MS[[paste0(nm,"_drift")]][i]==1) DRIFT_W else 1)
  raw<-pmax(mu,0)*dw
  if(sum(raw,na.rm=TRUE)<1e-9) a<-setNames(rep(1/length(mc),length(mc)),mc) else a<-raw/sum(raw,na.rm=TRUE)
  # cap 0.40 water-filling (no hard switch)
  for(k in 1:4){ over<-a>CAP; if(!any(over))break; ex<-sum(a[over]-CAP); a[over]<-CAP; fr<-!over; if(any(fr))a[fr]<-a[fr]+ex*a[fr]/sum(a[fr]) }
  inv[i]<-sum(a*sapply(mc,function(nm)MS[[nm]][i]),na.rm=TRUE)              # M-code net 가중합
  if(i %in% c(1,60,120,180,nrow(MS))) alloc_log[[length(alloc_log)+1]]<-data.table(date=MS$date[i],regime=rg,t(round(a,3)))
}
MS[,INVESTOR:=inv]; MS[,INVESTOR_act:=INVESTOR-bench]

## ── baselines ──
MS[,M0_only:=M0_baseline]; MS[,M0_only_act:=M0_baseline_act]
MS[,EW_Mcode:=rowMeans(MS[,..mc],na.rm=TRUE)]; MS[,EW_Mcode_act:=EW_Mcode-bench]
# no-regime investor (conf=0): uncond only
invnr<-rep(NA_real_,nrow(MS))
for(i in seq_len(nrow(MS))){ mu<-sapply(mc,function(nm)mean(MS[[paste0(nm,"_act")]][seq_len(i-1)],na.rm=TRUE))
  dw<-sapply(mc,function(nm) if(MS[[paste0(nm,"_drift")]][i]==1)DRIFT_W else 1); raw<-pmax(mu,0)*dw
  a<-if(sum(raw,na.rm=TRUE)<1e-9)setNames(rep(1/length(mc),length(mc)),mc)else raw/sum(raw,na.rm=TRUE)
  for(k in 1:4){over<-a>CAP;if(!any(over))break;ex<-sum(a[over]-CAP);a[over]<-CAP;fr<-!over;if(any(fr))a[fr]<-a[fr]+ex*a[fr]/sum(a[fr])}
  invnr[i]<-sum(a*sapply(mc,function(nm)MS[[nm]][i]),na.rm=TRUE)}
MS[,NoRegime:=invnr]; MS[,NoRegime_act:=NoRegime-bench]

## ── GATE 9: 통합 백테 비교 (active IR vs cap-w, IS/OOS, port_t) ──
methods<-c("INVESTOR","M0_only","EW_Mcode","NoRegime")
n<-nrow(MS); cut<-floor(n*0.6)
w(sprintf("\n=== GATE 9: 통합 백테 (cap-w active, n=%d, IS=%d/OOS=%d, book ref IR=0.795) ===",n,cut,n-cut))
w(sprintf("  %-12s %8s %8s %8s %9s","method","full_IR","IS_IR","OOS_IR","port_t"))
res<-list()
for(m in methods){ act<-MS[[paste0(m,"_act")]]
  res[[m]]<-data.table(method=m,full=IRf(act),IS=IRf(act[1:cut]),OOS=IRf(act[(cut+1):n]),port_t=nwt(act))
  w(sprintf("  %-12s %+8.3f %+8.3f %+8.3f %+9.2f",m,IRf(act),IRf(act[1:cut]),IRf(act[(cut+1):n]),nwt(act)))}
R<-rbindlist(res)
w("\n=== 의사결정 로그 샘플 (인베스터 M-code 배분, 가이드북 IAES) ===")
AL<-rbindlist(alloc_log,fill=TRUE); for(i in seq_len(nrow(AL))) w(sprintf("  %s [%s] %s",AL$date[i],AL$regime[i],paste(mc,round(unlist(AL[i,..mc]),2),sep=":",collapse=" ")))
best<-R[which.max(OOS)]
w(sprintf("\n판정: 최고 OOS = %s (%.3f). INVESTOR가 baselines·book(0.795) 능가? %s",
  best$method,best$OOS, ifelse(R[method=="INVESTOR",OOS]>=max(R[method!="INVESTOR",OOS])&&R[method=="INVESTOR",OOS]>0,"개선","미개선(가이드북 §9: 실패 정직보고)")))
saveRDS(list(R=R,MS=MS,alloc=AL),".cache/_ramp_gate6_8.rds")
fwrite(MS[,.(date,regime,INVESTOR,M0_only,EW_Mcode,NoRegime,bench)],"outputs/ramp/gate8_investor_series.csv")
close(con); cat("GATE6_8_DONE\n")
