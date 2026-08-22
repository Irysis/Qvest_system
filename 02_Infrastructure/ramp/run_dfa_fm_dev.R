## run_dfa_fm_dev.R — R7: 팩터 모멘텀 정식 검증 + 발전 (FQ-239, prereg dfa_v9_prereg_20260822)
## arms: v0(확인) · F1(연속) · F2(12-1) · F4(broad) · C1(F1×F4) — 규칙 고정, 튜닝 없음(chain)
## 게이트: 구조 PIT + shift 사다리(m동월/m-1정본/m-2 lag1) + placebo 30-seed(월블록 셔플) + essence 계약 채점
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
source("02_Infrastructure/validation/overlay_pit_guard.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/audit_bt_result.R")
source("02_Infrastructure/contracts/essence_score.R")
set.seed(20260822)
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}

load_mon<-function(path){
  R<-as.data.table(read_parquet(path)); R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
  fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market"))
  R[,ym:=format(Date,"%Y-%m")]
  mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),.(medate=max(Date))),by=ym,.SDcols=c("Market",fac)]
  setorder(mon,medate); list(mon=mon,fac=fac) }
P6<-load_mon("outputs/ramp/shumulvey_index_returns_202608.parquet")
BR<-load_mon("outputs/ramp/dfa_index_returns_broad_202608.parquet")

## trailing active: skip=0 → (m-11..m) / skip=1 → (m-11..m-1) 를 결정월 m 기준으로
mk_sig<-function(mon,fac,skip=0){
  NM<-nrow(mon); S<-matrix(NA_real_,NM,length(fac)); colnames(S)<-fac
  for(fi in seq_along(fac)){ f<-fac[fi]
    for(m in 12:NM){ w<-(m-11):(m-skip); if(length(w)<6)next
      S[m,fi]<-prod(1+mon[[f]][w])/prod(1+mon$Market[w])-1 } }
  S }
## 팔 실행: 결정 m-dec_lag 월말 신호 → m월 적용 (dec_lag=1 정본 / 0 동월 고의 / 2 lag1)
run_arm<-function(mon,fac,S,mode=c("ew","cont"),bps,dec_lag=1,perm=NULL){
  mode<-match.arg(mode); NM<-nrow(mon); NAx<-1+length(fac)
  pr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM); wprev<-rep(1/NAx,NAx); dec_used<-rep(NA_integer_,NM)
  Suse<-if(is.null(perm)) S else S[perm,,drop=FALSE]
  for(m in (13+dec_lag):NM){ d<-m-dec_lag
    s<-Suse[d,]; if(all(!is.finite(s))) next
    pos<-which(is.finite(s)&s>0)
    w<-rep(0,NAx)
    if(length(pos)==0){ w[1]<-1 } else if(mode=="ew"){ w[1+pos]<-1/length(pos)
    } else { w[1+pos]<-s[pos]/sum(s[pos]) }
    ri<-unlist(mon[m,c("Market",fac),with=FALSE]); ri[!is.finite(ri)]<-0
    dlt<-sum(abs(w-wprev)); tov[m]<-dlt
    pr[m]<-sum(w*ri)-(bps/1e4)*dlt
    wd<-w*(1+ri); wprev<-wd/sum(wd); dec_used[m]<-d }
  list(pr=pr,tov=tov,dec_used=dec_used) }
mets<-function(mon,pr,tov){ k<-is.finite(pr); p<-pr[k]; mk<-mon$Market[k]
  act<-p-mk; nav<-cumprod(1+p); mdd<-min(nav/cummax(nav)-1); n<-length(p)
  post17<-format(mon$medate[k],"%Y")>="2017"
  data.table(n_mo=n, first=format(mon$medate[k][1],"%Y-%m"),
    pt_vsMkt=nwt(act), IR_vsMkt=IRf(act), SR=IRf(p),
    CAGR=prod(1+p)^(12/n)-1, MDD=mdd, calmar=(prod(1+p)^(12/n)-1)/abs(mdd),
    TO_ann=mean(tov[k],na.rm=TRUE)*12,
    pt_post17=nwt(act[post17]), pt_pre17=nwt(act[!post17])) }

S6_0<-mk_sig(P6$mon,P6$fac,0); S6_1<-mk_sig(P6$mon,P6$fac,1); SB_0<-mk_sig(BR$mon,BR$fac,0)
ARMS<-list(
  v0 =list(d=P6,S=S6_0,mode="ew"),
  F1 =list(d=P6,S=S6_0,mode="cont"),
  F2 =list(d=P6,S=S6_1,mode="ew"),
  F4 =list(d=BR,S=SB_0,mode="ew"),
  C1 =list(d=BR,S=SB_0,mode="cont"))

OUT<-list(); SER<-list()
for(an in names(ARMS)){ a<-ARMS[[an]]
  for(bps in c(5,15)){ r<-run_arm(a$d$mon,a$d$fac,a$S,a$mode,bps,1)
    m<-mets(a$d$mon,r$pr,r$tov); m<-cbind(data.table(arm=an,cost_bps=bps),m)
    OUT[[length(OUT)+1]]<-m; SER[[sprintf("%s_%d",an,bps)]]<-list(mon=a$d$mon,pr=r$pr,tov=r$tov) } }
RES<-rbindlist(OUT)
## v0 대비 paired (동일 지수셋 P6 팔만 직접 paired; broad 팔은 공통월 기준)
for(an in c("F1","F2","F4","C1")) for(bps in c(5,15)){
  s0<-SER[[sprintf("v0_%d",bps)]]; s1<-SER[[sprintf("%s_%d",an,bps)]]
  y0<-format(s0$mon$medate,"%Y-%m"); y1<-format(s1$mon$medate,"%Y-%m")
  cm<-intersect(y0[is.finite(s0$pr)],y1[is.finite(s1$pr)])
  a0<-(s0$pr-s0$mon$Market)[match(cm,y0)]; a1<-(s1$pr-s1$mon$Market)[match(cm,y1)]
  RES[arm==an&cost_bps==bps, paired_nwt_vs_v0:=nwt(a1-a0)] }
cat("== R7 팩터 모멘텀 발전 — 전 셀 (판정창: 전체 가용) ==\n"); print(RES,digits=3)

## ---- 게이트 ①: 구조 PIT (정본 dec_lag=1 — 결정 m-1 월말 < 적용월 시작) ----
r1<-run_arm(P6$mon,P6$fac,S6_0,"ew",15,1)
k<-which(is.finite(r1$pr))
assert_overlay_pit(P6$mon$medate[r1$dec_used[k]], as.Date(paste0(P6$mon$ym[k],"-01")), label="fm_v0_declag1")
cat("[게이트①] assert_overlay_pit PASS (v0 전수)\n")
## ---- 게이트 ②③: shift 사다리 (v0·C1, 15bps) ----
cat("\n[게이트②③ shift 사다리 — pt_vsMkt]\n")
for(an in c("v0","C1")){ a<-ARMS[[an]]
  for(dl in c(0,1,2)){ r<-run_arm(a$d$mon,a$d$fac,a$S,a$mode,15,dl)
    m<-mets(a$d$mon,r$pr,r$tov)
    cat(sprintf("  %s dec_lag=%d(%s): pt=%.3f IR=%.3f\n",an,dl,c("동월(고의)","정본 m-1","lag1 m-2")[dl+1],m$pt_vsMkt,m$IR_vsMkt)) } }
## ---- 게이트 ④: placebo 30-seed (월블록 셔플, v0·C1 15bps) ----
cat("\n[게이트④ placebo — IR_vsMkt]\n")
for(an in c("v0","C1")){ a<-ARMS[[an]]; NM<-nrow(a$d$mon)
  real<-RES[arm==an&cost_bps==15]$IR_vsMkt
  ps<-replicate(30,{ perm<-sample(NM); r<-run_arm(a$d$mon,a$d$fac,a$S,a$mode,15,1,perm=perm)
    m<-mets(a$d$mon,r$pr,r$tov); m$IR_vsMkt })
  cat(sprintf("  %s: real=%.3f | placebo mean=%.3f sd=%.3f | p(placebo>=real)=%.3f\n",
      an,real,mean(ps,na.rm=TRUE),sd(ps,na.rm=TRUE),mean(ps>=real,na.rm=TRUE))) }
## ---- 계약 채점 (전 팔 15bps + v0 5bps) ----
cat("\n[essence_score 계약 채점]\n")
for(cell in c("v0_5","v0_15","F1_15","F2_15","F4_15","C1_15")){
  s<-SER[[cell]]; k<-is.finite(s$pr); d<-s$mon$medate[k]; p<-s$pr[k]; mk<-s$mon$Market[k]
  sim<-list(DAILY_NAV_DT=data.table(Date=d,Strategy_Ret=p,NAV=cumprod(1+p)),
            strategy_xts=xts(p,order.by=d), bm_xts=xts(mk,order.by=d),
            cost_model_version=sprintf("fm_%s",cell))
  spec<-list(strategy_name=sprintf("DFA_FM_%s",toupper(cell)),description="무국면 팩터 모멘텀 배분 (R7)",
             universe="KR style indices",rebalance="monthly",signal="trailing 12M active momentum")
  bt<-build_bt_result(sim,spec,run_id=sprintf("fm_%s_20260822",cell),strategy_id=sprintf("DFA_FM_%s",toupper(cell)),
      benchmark_id="CAPW_PARENT",benchmark_name="cap-w parent",transaction_cost_bps=as.numeric(sub(".*_","",cell)),
      slippage_bps=0,frequency="monthly",universe_id="K200_KQ150",code_version="run_dfa_fm_dev.R",created_by_agent="Q-Lead")
  es<-essence_score(bt,n_trials_cumulative=44,selection_type="chain")
  cat(sprintf("  [%s] grade=%s pt=%.3f oos_ret=%.3f calmar=%.3f SR=%.2f MDD=%.3f | HARD: pt%s oos%s cal%s\n",
      cell,es$grade,es$essence$portfolio_alpha_t_nw_lag3,es$essence$oos_retention,es$essence$calmar,
      es$essence$net_sharpe,es$essence$mdd,
      ifelse(es$essence$portfolio_alpha_t_nw_lag3>=2.95,"P","F"),
      ifelse(is.finite(es$essence$oos_retention)&&es$essence$oos_retention>=0.7,"P",ifelse(is.finite(es$essence$oos_retention)&&es$essence$oos_retention>=0.5,"b","F")),
      ifelse(es$essence$calmar>=0.64,"P","F"))) }
fwrite(RES,"outputs/ramp/dfa_fm_dev_r7_20260822.csv")
saveRDS(SER,".cache/_dfa_fm_dev_r7.rds")
cat("R7_DONE\n")
