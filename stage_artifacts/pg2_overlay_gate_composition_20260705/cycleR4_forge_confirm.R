## 리스크 오버레이 R4 — 다층 오버레이 authoritative 확정 (contract-grade + book-marginal + DSR)
## base = production ret_orig × m4 × beta_R05 (재구성 아님, 실제 STR_1715 base return)
## 후보 = base × gate(BearProb) [× gate(MSM)]. contract build_metrics/build_benchmark_compare.
## 판정: recon(incumbent 1.704/1.94/6.21/IR1.416) + PORT_t + ΔIR≥0.05 + paired NW-t + DSR≥0.5.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705"); COST<-0.0015
source(file.path(ROOT,"02_Infrastructure/contracts/backtest_result_contract.R"))
p <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); n<-nrow(p)
h <- fread(file.path(ROOT,"qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv"))[,.(realized_ym,R05_z_avg)]
p <- merge(p,h,by="realized_ym",all.x=TRUE,sort=FALSE); setorder(p,realized_ym)
mbeta<-mean(p$beta_R05); FLOOR<-min(p$beta_R05)
p[, dR05:=abs(beta_R05-shift(beta_R05,1,fill=1.0))]; p[, ret_base:=beta_R05*m4*ret_orig-dR05*COST]
epct<-function(x){u<-rep(0.5,length(x));for(i in 2:length(x)){pv<-x[1:(i-1)];pv<-pv[is.finite(pv)];if(length(pv)>=6&&is.finite(x[i]))u[i]<-mean(pv<x[i])};u}
load_pit<-function(f,col){urs<-as.data.table(read_parquet(file.path(WD,"pinned_cache",f)));urs[,Date:=as.Date(Date)];setorder(urs,Date)
  urs<-urs[is.finite(get(col))];v<-rep(NA_real_,n);for(i in 1:n){pv<-urs[Date<p$anchor_date[i]];if(nrow(pv)>0)v[i]<-tail(pv[[col]],1)};v}
s_BEAR<-epct(load_pit("regime_jump_daily.parquet","Bear_Prob_lag")); s_MSM<-epct(load_pit("unified_regime_signal_daily.parquet","MSM_Crisis_Prob"))
gate<-function(sv,floorL=0.5,gamma=2,th=NULL){if(is.null(th))th<-quantile(sv,0.6,na.rm=T);x<-pmax(0,(sv-th)/(1-th+1e-9));1-(1-floorL)*pmin(1,x)^gamma}
apply_beta<-function(bt){db<-abs(bt-shift(bt,1,fill=1.0));bt*p$m4*p$ret_orig-db*COST}

## ---- benchmark (Track A와 동일: pinned IKS200 anchor-window) ----
bm<-as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet")))
bm[,Date:=as.Date(Date)];bm<-bm[is.finite(BM_Ret)];setorder(bm,Date);bm_x<-xts(bm$BM_Ret,order.by=bm$Date)
a<-p$anchor_date;bmw<-rep(NA_real_,n);for(i in 2:n){seg<-bm_x[index(bm_x)>a[i-1]&index(bm_x)<=a[i]];if(nrow(seg)>0)bmw[i]<-as.numeric(Return.cumulative(seg))};bmw[1]<-0
br<-data.table(benchmark_id="KOSPI200",benchmark_name="KOSPI 200",date=p$anchor_date,benchmark_ret=bmw,
  benchmark_nav=cumprod(1+ifelse(is.na(bmw),0,bmw)),risk_free_ret=0,benchmark_excess_ret=bmw,frequency="monthly")

cmet<-function(rv,tag){ pr<-data.table(run_id="R4",strategy_id=tag,date=p$anchor_date,frequency="monthly",
    ret_gross=rv,ret_net=rv,risk_free_ret=0,excess_ret_net=rv,turnover=NA_real_,cost_ret=0,cash_weight=NA_real_,leverage=NA_real_,n_holdings=NA_integer_)
  nav<-cumprod(1+rv);navt<-data.table(run_id="R4",strategy_id=tag,date=pr$date,frequency="monthly",nav_gross=nav,nav_net=nav,drawdown=NA_real_)
  ht<-data.table(matrix(nrow=0,ncol=length(HOLDINGS_COLS),dimnames=list(NULL,HOLDINGS_COLS)))
  m<-build_metrics(navt,pr,ht,"R4",tag,frequency="monthly",annualization_factor=12)
  bc<-build_benchmark_compare(pr,br,"R4",tag,annualization_factor=12)
  gv<-function(dt,mn,cl="metric_value"){v<-dt[metric_name==mn][[cl]];if(length(v))as.numeric(v[1])else NA_real_}
  x<-xts(rv,order.by=p$anchor_date)
  list(tag=tag,SR=as.numeric(table.AnnualizedReturns(x,scale=12)[3,1]),CAGR=gv(m,"CAGR"),MDD=gv(m,"MDD"),Calmar=gv(m,"Calmar"),
    PORT_t=gv(bc,"Portfolio_Alpha_t_NW_lag3","strategy_value"),IR=gv(bc,"Information_Ratio","active_value"),
    active=rv-br$benchmark_ret) }

gate_match<-function(sv,tgt=mbeta,floorL=FLOOR,gamma=2){f<-function(t){x<-pmax(0,(sv-t)/(1-t+1e-9));mean(1-(1-floorL)*pmin(1,x)^gamma)-tgt}
  t<-tryCatch(uniroot(f,c(0,0.999))$root,error=function(e)NA);if(is.na(t))return(rep(NA,length(sv)));x<-pmax(0,(sv-t)/(1-t+1e-9));1-(1-floorL)*pmin(1,x)^gamma}
betaL1<-gate_match(s_BEAR, mbeta)                                    # BearProb 대체, 노출매칭(same avg defense)
betaL2m<-{b<-p$beta_R05*gate(s_BEAR); pmin(1,b*mbeta/mean(b))}       # R05×Bear, 노출을 base로 rescale
betaL2<-pmin(1,pmax(FLOOR*0.9,p$beta_R05*gate(s_BEAR)))
betaL3<-pmin(1,pmax(FLOOR*0.9,p$beta_R05*gate(s_BEAR)*gate(s_MSM)))
B <-cmet(p$ret_base,"L0_base")
L1<-cmet(apply_beta(betaL1),"L1_bear_replace_match"); L2m<-cmet(apply_beta(betaL2m),"L2_R05xBear_match")
L2<-cmet(apply_beta(betaL2),"L2_R05xBear"); L3<-cmet(apply_beta(betaL3),"L3_R05xBearxMSM")
PG("[PG] RECON base: SR=%.4f Calmar=%.4f MDD=%.4f PORT_t=%.3f IR=%.4f (target ~1.895/1.94/0.233/6.21/1.416)", B$SR,B$Calmar,B$MDD,B$PORT_t,B$IR)

## book-marginal: ΔIR + paired NW-t of active diff
nw<-function(d,lag=3){d<-d[is.finite(d)];nn<-length(d);mu<-mean(d);dm<-d-mu;g0<-sum(dm^2)/nn;gs<-0;for(L in 1:lag){w<-1-L/(lag+1);gs<-gs+2*w*sum(dm[(L+1):nn]*dm[1:(nn-L)])/nn};mu/sqrt((g0+gs)/nn)}
for(C in list(L1,L2m,L2,L3)){ dIR<-C$IR-B$IR; pt<-nw(C$active-B$active)
  PG("[PG] %-22s SR=%.3f Calmar=%.3f MDD=%.4f PORT_t=%.3f IR=%.3f | ΔIR=%+.4f active-paired_t=%.3f", C$tag,C$SR,C$Calmar,C$MDD,C$PORT_t,C$IR,dIR,pt) }
PG("[PG] avg exposure: L1=%.3f L2m=%.3f L2=%.3f L3=%.3f base=%.3f", mean(betaL1),mean(betaL2m),mean(betaL2),mean(betaL3),mbeta)

## DSR: deflated Sharpe given sweep. trial SRs from R1+R3 (실제 탐색한 config들)
trial_SR <- c(1.895,1.876,1.709,1.682,2.049,1.878,1.823,1.733, 2.049,2.102,2.092,2.020,2.124,1.909,2.054)  # per-annum
sr_sd <- sd(trial_SR)/sqrt(12); N<-length(trial_SR); T_<-n
best_sr_pp <- max(L2$SR,L3$SR)/sqrt(12)
emc<-0.5772; e<-exp(1)
sr0 <- sr_sd*((1-emc)*qnorm(1-1/N) + emc*qnorm(1-1/(N*e)))  # expected max SR under N trials
## returns for skew/kurt of best candidate
rvbest<-if(L3$SR>=L2$SR) apply_beta(betaL3) else apply_beta(betaL2)
sk<-skewness(rvbest); ku<-kurtosis(rvbest)+3
dsr <- pnorm(((best_sr_pp - sr0)*sqrt(T_-1))/sqrt(1 - sk*best_sr_pp + ((ku-1)/4)*best_sr_pp^2))
PG("[PG] DSR: N_trials=%d sr0(exp max)=%.4f best_sr_pp=%.4f skew=%.2f kurt=%.2f → DSR=%.3f (≥0.5 HARD)", N,sr0,best_sr_pp,sk,ku,dsr)

## subperiod PORT_t (post-2017)
sub_t<-function(C,from){idx<-p$anchor_date>=as.Date(from);a<-C$active[idx];mu<-mean(a);dm<-a-mu;nn<-length(a);g0<-sum(dm^2)/nn;gs<-0;for(L in 1:3){w<-1-L/4;gs<-gs+2*w*sum(dm[(L+1):nn]*dm[1:(nn-L)])/nn};mu/sqrt((g0+gs)/nn)}
PG("[PG] post-2017 active-improvement paired_t: L2=%.2f L3=%.2f", sub_t(L2,"2017-01-01"),sub_t(L3,"2017-01-01"))
res<-rbindlist(list(as.data.table(B[c("tag","SR","CAGR","MDD","Calmar","PORT_t","IR")]),
  as.data.table(L2[c("tag","SR","CAGR","MDD","Calmar","PORT_t","IR")]),as.data.table(L3[c("tag","SR","CAGR","MDD","Calmar","PORT_t","IR")])))
res[, dIR_vs_base := IR - B$IR]
print(res[, .(tag,SR=round(SR,3),Calmar=round(Calmar,3),MDD=round(MDD,4),PORT_t=round(PORT_t,3),IR=round(IR,3),dIR=round(dIR_vs_base,4))])
fwrite(res, file.path(WD,"cycleR4_forge_confirm_results.csv"))
PG("[PG] DONE R4. DSR=%.3f", dsr)
