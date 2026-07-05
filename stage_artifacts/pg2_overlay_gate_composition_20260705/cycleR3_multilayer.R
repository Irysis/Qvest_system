## 리스크 오버레이 R3 — 다층 곱셈 오버레이 (도훈 지시: 각기 다른 리스크 계층 관리)
## 각 layer = 서로 다른 위기 tier 신호의 게이트, 곱셈 결합. m4 × ∏ L_i × ret_orig.
##   tier: R05(tail/regime-cash) · BearProb(jump/bear onset) · MSM(crisis prob) · Vol(단기변동성)
## max-cash 교훈: 곱셈 compound de-risk = 위기서 net-protective. 상관 낮은 tier일수록 보완.
## 렌즈: MDD·Calmar·SR·CVaR·risk-off + avg노출(과방어 감시) + lag1 robust(vs base_lag1).
suppressPackageStartupMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705"); COST<-0.0015
p <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); n<-nrow(p)
h <- fread(file.path(ROOT,"qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv"))[,.(realized_ym,R05_z_avg)]
p <- merge(p,h,by="realized_ym",all.x=TRUE,sort=FALSE); setorder(p,realized_ym)
mbeta<-mean(p$beta_R05); FLOOR<-min(p$beta_R05)
p[, dR05:=abs(beta_R05-shift(beta_R05,1,fill=1.0))]; p[, ret_base:=beta_R05*m4*ret_orig-dR05*COST]
epct<-function(x){u<-rep(0.5,length(x));for(i in 2:length(x)){pv<-x[1:(i-1)];pv<-pv[is.finite(pv)];if(length(pv)>=6&&is.finite(x[i]))u[i]<-mean(pv<x[i])};u}
load_pit<-function(f,col){urs<-as.data.table(read_parquet(file.path(WD,"pinned_cache",f)));urs[,Date:=as.Date(Date)];setorder(urs,Date)
  urs<-urs[is.finite(get(col))];v<-rep(NA_real_,n);for(i in 1:n){pv<-urs[Date<p$anchor_date[i]];if(nrow(pv)>0)v[i]<-tail(pv[[col]],1)};v}
## tier stress signals (PIT, [0,1] expanding percentile)
sgn<-sign(cor(p$beta_R05,p$R05_z_avg,use="complete.obs")); u<-epct(p$R05_z_avg); s_R05<-if(sgn>=0)(1-u)else u
s_BEAR<-epct(load_pit("regime_jump_daily.parquet","Bear_Prob_lag"))
s_MSM <-epct(load_pit("unified_regime_signal_daily.parquet","MSM_Crisis_Prob"))
so<-p$ret_orig; vol<-rep(NA_real_,n); for(i in 13:n) vol[i]<-sd(so[(i-12):(i-1)]); vol[!is.finite(vol)]<-median(vol,na.rm=T); s_VOL<-epct(vol)
PG("[PG] tier cor: R05-Bear=%.2f R05-MSM=%.2f Bear-MSM=%.2f Bear-Vol=%.2f",
   cor(s_R05,s_BEAR),cor(s_R05,s_MSM),cor(s_BEAR,s_MSM),cor(s_BEAR,s_VOL))
## layer gate: tailcut stress->[floor,1]; floorL per-layer
gate<-function(sv,floorL=0.5,gamma=2,th=NULL){ if(is.null(th)) th<-quantile(sv,0.6,na.rm=T)
  x<-pmax(0,(sv-th)/(1-th+1e-9)); 1-(1-floorL)*pmin(1,x)^gamma }
## avg-matched single gate (to target mean exposure) — for fair "same total defense"
gate_match<-function(sv,tgt=mbeta,floorL=FLOOR,gamma=2){ f<-function(t){x<-pmax(0,(sv-t)/(1-t+1e-9));mean(1-(1-floorL)*pmin(1,x)^gamma)-tgt}
  t<-tryCatch(uniroot(f,c(0,0.999))$root,error=function(e)NA);if(is.na(t))return(rep(NA,length(sv)));x<-pmax(0,(sv-t)/(1-t+1e-9));1-(1-floorL)*pmin(1,x)^gamma}
apply_beta<-function(bt){ db<-abs(bt-shift(bt,1,fill=1.0)); bt*p$m4*p$ret_orig-db*COST }
rmet<-function(rv,bt=NULL){x<-xts(rv,order.by=p$anchor_date);roff<-p$regime%in%c("CAUTION","CRISIS")
  nav<-cumprod(1+rv);uw<-nav<cummax(nav)*0.9999;rl<-rle(uw);dur<-if(any(rl$values))max(rl$lengths[rl$values])else 0
  list(SR=as.numeric(table.AnnualizedReturns(x,scale=12)[3,1]),CAGR=as.numeric(Return.annualized(x,scale=12)),
    MDD=as.numeric(maxDrawdown(x)),Calmar=as.numeric(Return.annualized(x,scale=12))/as.numeric(maxDrawdown(x)),
    CVaR95=-as.numeric(quantile(rv,0.05)),roffCum=prod(1+rv[roff])-1,maxDDdur=dur,
    avg_exp=if(is.null(bt))mbeta else mean(bt))}

## ---- multi-layer combos (beta_total = product of layer gates; m4 applied in apply_beta) ----
gR05<-gate(s_R05); gBEAR<-gate(s_BEAR); gMSM<-gate(s_MSM); gVOL<-gate(s_VOL)
combos<-list(
  L0_base_R05           = p$beta_R05,                                   # 현행 (m4×R05)
  L1_bear_replace       = gate_match(s_BEAR),                           # R2 winner (m4×Bear, avg-matched)
  L2_R05xBear           = p$beta_R05 * gBEAR,                           # 2-tier stack
  L2_R05xBear_match     = { b<-p$beta_R05*gate(s_BEAR); b*mbeta/mean(b) },  # 2-tier, exposure rescaled to base
  L3_R05xBearxVol       = p$beta_R05 * gBEAR * gVOL,                    # 3-tier stack
  L3_R05xBearxMSM       = p$beta_R05 * gBEAR * gMSM,                    # 3-tier (all regime-family)
  L2_union_match        = gate_match(pmax(s_R05,s_BEAR)),               # union-of-tiers, avg-matched
  L2_R05xBear_match2    = { b<-p$beta_R05*gate(s_BEAR,floorL=0.6); pmin(1,b*mbeta/mean(b)) }
)
base_r<-rmet(p$ret_base, p$beta_R05); PG("[PG] BASE MDD=%.4f Cal=%.3f SR=%.3f avg=%.3f", base_r$MDD,base_r$Calmar,base_r$SR,base_r$avg_exp)
rows<-list(data.table(tag="L0_base_R05",SR=base_r$SR,CAGR=base_r$CAGR,MDD=base_r$MDD,Calmar=base_r$Calmar,CVaR95=base_r$CVaR95,roffCum=base_r$roffCum,maxDDdur=base_r$maxDDdur,avg_exp=base_r$avg_exp,MDD_lag1=base_r$MDD,Cal_lag1=base_r$Calmar))
base_lag1<-rmet(apply_beta(shift(p$beta_R05,1,fill=1.0)))  # base under lag1 (reference)
for(nm in names(combos)){ if(nm=="L0_base_R05") next; bt<-combos[[nm]]; if(any(!is.finite(bt))){PG("[PG] skip %s",nm);next}
  bt<-pmin(1,pmax(FLOOR*0.9,bt)); rv<-apply_beta(bt); m<-rmet(rv,bt)
  ml<-rmet(apply_beta(shift(bt,1,fill=1.0)))
  rows[[length(rows)+1]]<-data.table(tag=nm,SR=m$SR,CAGR=m$CAGR,MDD=m$MDD,Calmar=m$Calmar,CVaR95=m$CVaR95,roffCum=m$roffCum,maxDDdur=m$maxDDdur,avg_exp=m$avg_exp,MDD_lag1=ml$MDD,Cal_lag1=ml$Calmar)
  PG("[PG] %-20s MDD=%.4f Cal=%.3f SR=%.3f avg=%.3f roffCum=%.3f | lag1 MDD=%.4f Cal=%.3f", nm,m$MDD,m$Calmar,m$SR,m$avg_exp,m$roffCum,ml$MDD,ml$Calmar) }
res<-rbindlist(rows,fill=TRUE)
## risk-win = Calmar>base AND MDD<base AND SR not materially worse (>= base-0.05) AND lag1 MDD<=base_lag1
res[, riskwin := Calmar>base_r$Calmar & MDD<base_r$MDD & SR>=base_r$SR-0.05 & MDD_lag1<=base_lag1$MDD+0.005]
print(res[, .(tag,MDD=round(MDD,4),Calmar=round(Calmar,3),SR=round(SR,3),CVaR95=round(CVaR95,4),roffCum=round(roffCum,3),avg=round(avg_exp,3),MDD_lag1=round(MDD_lag1,4),riskwin)])
fwrite(res, file.path(WD,"cycleR3_multilayer_results.csv"))
PG("[PG] base_lag1 MDD=%.4f | risk-wins=%d", base_lag1$MDD, sum(res$riskwin,na.rm=TRUE))
PG("[PG] DONE R3 multilayer")
