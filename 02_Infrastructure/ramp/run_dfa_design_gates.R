## run_dfa_design_gates.R — 설계 타당성 게이트 (감사 사양 §8-1·§8-6, 도훈 지시 2026-08-21 "타당한지부터 검증")
## [사전 규칙 — 산출 전 고정]
##  G1 (§8-1 손익분기 회전율): gross_active(비용 전) = mean(actM)*12 + bps·TO_ann.
##     허용 TO 상한(15bps) = gross_active / 0.0015. 실제 TO가 상한 초과 = 비용이 신호 전량 소진 = 설계 부적합.
##  G2 (§8-6 무국면 벤치마크): FM-TS = 월말 trailing 12M active > 0 인 팩터 EW(없으면 Market 100%),
##     월말 결정→익월 적용, 비용 bps·Σ|Δw|. EW(7) 분기리밸 병기.
##     판정: DFA(M0-roll TE3)가 FM-TS를 공통창에서 못 이기면(pt·IR 열위 ∧ paired NW-t<0) 국면층 기각 후보.
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
.rds<-function(k){p<-sprintf(".cache/_dfa_v5_%s.rds",k); if(file.exists(p))p else sprintf(".cache/_smv_v5_%s.rds",k)}

## ---- G1: 손익분기 회전율 (M0-roll + H1-q95, 전 TE·비용) ----
cat("== G1 손익분기 회전율 게이트 (§8-1) ==\n")
g1<-list()
for(spec in list(c("f15_roll","M0"),c("f15_roll_h1q95","H1"))){
  Z<-readRDS(.rds(spec[1])); RESx<-Z$RES
  for(i in seq_len(nrow(RESx))){ r<-RESx[i]; if(r$arm!=spec[2])next
    s<-r$series[[1]]; if(is.null(s))next
    gross_act<-mean(s$actM,na.rm=TRUE)*12 + (r$cost_bps/1e4)*r$TO_ann
    be_to15<-gross_act/0.0015
    g1[[length(g1)+1]]<-data.table(run_key=spec[1],arm=r$arm,te=r$te,cost_bps=r$cost_bps,
      TO_ann=round(r$TO_ann,2), gross_act_ann=round(gross_act,4),
      drag15_ann=round(0.0015*r$TO_ann,4), net_act15_ann=round(gross_act-0.0015*r$TO_ann,4),
      breakeven_TO_at15=round(be_to15,2), headroom=round(be_to15-r$TO_ann,2)) }
}
G1<-rbindlist(g1); G1<-G1[cost_bps==5]   # gross는 비용-불변이므로 5bps 행만 (중복 제거)
print(G1,digits=3)

## ---- G2: 무국면 벤치마크 (paper6 지수, 공통창) ----
cat("\n== G2 무국면 벤치마크 게이트 (§8-6) ==\n")
Z<-readRDS(.rds("f15_roll"))
R<-as.data.table(read_parquet(Z$idxfile)); R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
FACN<-c("Value","Size","Momentum","Quality","LowVol","Growth"); IDX<-c("Market",FACN)
R[,ym:=format(Date,"%Y-%m")]
mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),.(medate=max(Date))),by=ym,.SDcols=IDX]
setorder(mon,medate); NMo<-nrow(mon)
## trailing 12M active (월말 결정 정보 = 해당 월까지)
act12<-matrix(NA_real_,NMo,6); colnames(act12)<-FACN
for(fi in seq_along(FACN)){ f<-FACN[fi]
  for(m in 12:NMo){ w<-(m-11):m
    act12[m,fi]<-prod(1+mon[[f]][w])/prod(1+mon$Market[w])-1 } }
run_bench<-function(kind,bps){
  pr<-rep(NA_real_,NMo); tov<-rep(NA_real_,NMo); wprev<-NULL
  wE<-rep(1/7,7)
  for(m in 13:NMo){ ## 결정 = m-1 월말 정보(act12[m-1]) → 적용 m월 (보정 회계)
    w<-switch(kind,
      fm={ pos<-which(is.finite(act12[m-1,]) & act12[m-1,]>0)
           v<-rep(0,7); if(length(pos)) v[1+pos]<-1/length(pos) else v[1]<-1; v },
      ew={ if((m-13)%%3==0) wE<<-rep(1/7,7); wE })
    ri<-unlist(mon[m,..IDX]); ri[!is.finite(ri)]<-0
    if(is.null(wprev)) wprev<-rep(1/7,7)
    dlt<-sum(abs(w-wprev)); tov[m]<-dlt
    pr[m]<-sum(w*ri)-(bps/1e4)*dlt
    wd<-w*(1+ri); wprev<-wd/sum(wd)
    if(kind=="ew") wE<-wprev }
  list(pr=pr,tov=tov) }
## DFA 시리즈 (TE3, 5/15bps)
out<-list()
for(bps in c(5,15)){
  rD<-Z$RES[arm=="M0"&te==3&cost_bps==bps][1]; sD<-rD$series[[1]]
  ymD<-substr(as.character(sD$months),1,7)
  fm<-run_bench("fm",bps); ew<-run_bench("ew",bps)
  i<-match(ymD,mon$ym); ok<-is.finite(fm$pr[i])&is.finite(sD$pr)
  dfa<-sD$pr[ok]; fmv<-fm$pr[i][ok]; ewv<-ew$pr[i][ok]; mkt<-mon$Market[i][ok]
  mets<-function(p,lab){ act<-p-mkt; nav<-cumprod(1+p)
    data.table(bench=lab,cost_bps=bps,n_mo=length(p),pt_vsMkt=nwt(act),IR_vsMkt=IRf(act),
      SR=IRf(p),MDD=min(nav/cummax(nav)-1)) }
  M<-rbind(mets(dfa,"DFA_M0roll_TE3"),mets(fmv,"FM_TS(무국면)"),mets(ewv,"EW7(무국면)"))
  M[,paired_nwt_vs_FM:=c(nwt(dfa-fmv),NA,NA)]
  M[,fm_TO_ann:=c(NA,mean(fm$tov[i][ok])*12,mean(ew$tov[i][ok])*12)]
  out[[length(out)+1]]<-M }
G2<-rbindlist(out); print(G2,digits=3)
fwrite(G1,"outputs/ramp/dfa_design_gate_g1_breakeven_20260821.csv")
fwrite(G2,"outputs/ramp/dfa_design_gate_g2_benchmarks_20260821.csv")
cat("\n[설계 노트] CV 내부 비용: 현행 ls_sh_t1 = 5bps 하드코딩 — §8-7 이식 규약(15bps)과 불일치. 감사 후 수정 항목.\n")
cat("DESIGN_GATES_DONE\n")
