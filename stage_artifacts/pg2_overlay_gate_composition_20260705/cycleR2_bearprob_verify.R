## 리스크 오버레이 R2 — BearProb_lag 게이트 개선 적대검증
## Q1 base도 lag1이면 붕괴? (lag1-collapse 보편성 → clean 비교 valid 여부)
## Q2 placebo: bear stress 셔플 200회 → MDD/Calmar/SR null → 유의성
## Q3 subperiod: 전/후반 각각 개선?
## Q4 orthogonality: Bear_Prob vs base R05 신호 상관 (진짜 다른 신호인가)
## Q5 PIT: Bear_Prob_lag(이미 lagged) + Date<anchor 이중 보수 timing 확인
suppressPackageStartupMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
COST <- 0.0015
p <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); n<-nrow(p)
h <- fread(file.path(ROOT,"qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv"))[, .(realized_ym, R05_z_avg)]
p <- merge(p, h, by="realized_ym", all.x=TRUE, sort=FALSE); setorder(p, realized_ym)
mean_beta_base <- mean(p$beta_R05); FLOOR <- min(p$beta_R05)
apply_gate <- function(bv){ db<-abs(bv-shift(bv,1,fill=1.0)); bv*p$m4*p$ret_orig - db*COST }
epct <- function(x){ u<-rep(0.5,length(x)); for(i in 2:length(x)){pv<-x[1:(i-1)];pv<-pv[is.finite(pv)];if(length(pv)>=6&&is.finite(x[i]))u[i]<-mean(pv<x[i])};u }
build_tailcut <- function(sv,tgt=mean_beta_base,floor=FLOOR,gamma=2){ f<-function(th){x<-pmax(0,(sv-th)/(1-th+1e-9));mean(1-(1-floor)*pmin(1,x)^gamma)-tgt}
  th<-tryCatch(uniroot(f,c(0,0.999))$root,error=function(e)NA);if(is.na(th))return(rep(NA,length(sv)));x<-pmax(0,(sv-th)/(1-th+1e-9));1-(1-floor)*pmin(1,x)^gamma }
rmet <- function(rv){ x<-xts(rv,order.by=p$anchor_date)
  list(SR=as.numeric(table.AnnualizedReturns(x,scale=12)[3,1]), MDD=as.numeric(maxDrawdown(x)),
       Calmar=as.numeric(Return.annualized(x,scale=12))/as.numeric(maxDrawdown(x)),
       CVaR95=-as.numeric(quantile(rv,0.05))) }

## bear prob (already-lagged source) + PIT load
urs <- as.data.table(read_parquet(file.path(WD,"pinned_cache/regime_jump_daily.parquet"))); urs[,Date:=as.Date(Date)]; setorder(urs,Date)
bp <- rep(NA_real_,n); bpc <- urs[is.finite(Bear_Prob_lag)]
for(i in 1:n){ pv<-bpc[Date<p$anchor_date[i]]; if(nrow(pv)>0) bp[i]<-tail(pv$Bear_Prob_lag,1) }
stress_bp <- epct(bp)
p[, dR05 := abs(beta_R05-shift(beta_R05,1,fill=1.0))]; p[, ret_base := beta_R05*m4*ret_orig - dR05*COST]

beta_bp <- build_tailcut(stress_bp)
PG("[PG] Q4 orthogonality: cor(beta_bp, beta_R05_base)=%.3f (낮을수록 다른 신호)", cor(beta_bp, p$beta_R05, use="complete.obs"))

## Q1 base lag1 vs candidate lag1 (동일 스트레스로 lag1-collapse 보편성)
mB<-rmet(p$ret_base); mBl<-rmet(apply_gate(shift(p$beta_R05,1,fill=1.0)))
mC<-rmet(apply_gate(beta_bp)); mCl<-rmet(apply_gate(shift(beta_bp,1,fill=1.0)))
PG("[PG] Q1 base:   clean MDD=%.4f Cal=%.3f SR=%.3f | lag1 MDD=%.4f Cal=%.3f SR=%.3f", mB$MDD,mB$Calmar,mB$SR, mBl$MDD,mBl$Calmar,mBl$SR)
PG("[PG] Q1 BearP:  clean MDD=%.4f Cal=%.3f SR=%.3f | lag1 MDD=%.4f Cal=%.3f SR=%.3f", mC$MDD,mC$Calmar,mC$SR, mCl$MDD,mCl$Calmar,mCl$SR)
PG("[PG] Q1 → clean에서 BearP가 base 지배 AND lag1에서도 base_lag1 대비? MDD %.4f vs %.4f", mCl$MDD, mBl$MDD)

## Q2 placebo: shuffle stress_bp (break time), rebuild+match, 200×
set.seed_manual <- function(k) k  ## no Math.random dependency; use deterministic permutations
nullMDD<-numeric(0); nullCal<-numeric(0); nullSR<-numeric(0)
for(s in 1:200){ idx<-((seq_len(n)*s*7 + s*13) %% n)+1; sh<-stress_bp[idx]; bsh<-build_tailcut(sh)
  if(all(is.finite(bsh))){ m<-rmet(apply_gate(bsh)); nullMDD<-c(nullMDD,m$MDD); nullCal<-c(nullCal,m$Calmar); nullSR<-c(nullSR,m$SR) } }
pMDD<-mean(nullMDD<=mC$MDD); pCal<-mean(nullCal>=mC$Calmar); pSR<-mean(nullSR>=mC$SR)
PG("[PG] Q2 placebo(n=%d): MDD p=%.3f (null mean %.4f) | Calmar p=%.3f (null %.3f) | SR p=%.3f (null %.3f)",
   length(nullMDD), pMDD, mean(nullMDD), pCal, mean(nullCal), pSR, mean(nullSR))

## Q3 subperiod halves
half<-floor(n/2); rc<-apply_gate(beta_bp)
sub<-function(idx){ x<-xts(rc[idx],order.by=p$anchor_date[idx]); xb<-xts(p$ret_base[idx],order.by=p$anchor_date[idx])
  c(cand_MDD=as.numeric(maxDrawdown(x)), base_MDD=as.numeric(maxDrawdown(xb)),
    cand_SR=as.numeric(table.AnnualizedReturns(x,scale=12)[3,1]), base_SR=as.numeric(table.AnnualizedReturns(xb,scale=12)[3,1])) }
s1<-sub(1:half); s2<-sub((half+1):n)
PG("[PG] Q3 1st half: cand MDD=%.3f/SR=%.3f vs base MDD=%.3f/SR=%.3f", s1["cand_MDD"],s1["cand_SR"],s1["base_MDD"],s1["base_SR"])
PG("[PG] Q3 2nd half: cand MDD=%.3f/SR=%.3f vs base MDD=%.3f/SR=%.3f", s2["cand_MDD"],s2["cand_SR"],s2["base_MDD"],s2["base_SR"])
fwrite(data.table(metric=c("clean_MDD","clean_Calmar","clean_SR","lag1_MDD","lag1_Calmar","base_lag1_MDD","base_lag1_Calmar",
  "cor_to_R05","placebo_pMDD","placebo_pCalmar","placebo_pSR","h1_cand_SR","h1_base_SR","h2_cand_SR","h2_base_SR"),
  value=c(mC$MDD,mC$Calmar,mC$SR,mCl$MDD,mCl$Calmar,mBl$MDD,mBl$Calmar,cor(beta_bp,p$beta_R05,use="complete.obs"),
  pMDD,pCal,pSR,s1["cand_SR"],s1["base_SR"],s2["cand_SR"],s2["base_SR"])), file.path(WD,"cycleR2_bearprob_verify_results.csv"))
PG("[PG] DONE R2 bearprob verify")
