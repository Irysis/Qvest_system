## ============================================================================
## 리스크 오버레이 리서치 R1 — M4×R05 디리스킹 게이트 개선 (RISK 렌즈, not alpha)
## base = beta_R05×m4×ret_orig − |Δβ|×15bps (Track A 정의, 269m, 평균노출 매칭)
## 렌즈 = AX-001 조건부: 국면별 Sharpe + MDD relief + Calmar/Sortino/CVaR + max-DD-dur
##        + ★lag1 PIT에서 MDD/Calmar 개선 생존? (리스크 오버레이 판정 핵심)
## 후보: A5(MSM위기확률) · condvoltgt · ★DD-control(CPPI) · ★jump-prob · ★MSM×R05결합
## 목표: 같은 평균노출서 더 나은 하방보호(MDD↓·crisis-Sharpe↑·drag 최소)·lag1 robust.
## ============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
COST <- 0.0015

## ---- base panel (Track A와 동일) ----
p <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); stopifnot(nrow(p)==269)
h <- fread(file.path(ROOT,"qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv"))
h <- h[, .(realized_ym, R05_z_avg)]
p <- merge(p, h, by="realized_ym", all.x=TRUE, sort=FALSE); setorder(p, realized_ym)
p[, dR05_base := abs(beta_R05 - shift(beta_R05,1,fill=1.0))]
p[, ret_base  := beta_R05*m4*ret_orig - dR05_base*COST]
n <- nrow(p); mean_beta_base <- mean(p$beta_R05); FLOOR <- min(p$beta_R05)
PG("[PG] base mean_beta=%.4f floor=%.2f", mean_beta_base, FLOOR)

apply_gate <- function(bv){ dbeta <- abs(bv - shift(bv,1,fill=1.0)); bv*p$m4*p$ret_orig - dbeta*COST }

## ---- expanding-percentile PIT helper ----
epct <- function(x){ u<-rep(0.5,length(x)); for(i in 2:length(x)){ pv<-x[1:(i-1)]; pv<-pv[is.finite(pv)]
  if(length(pv)>=6 && is.finite(x[i])) u[i]<-mean(pv<x[i]) }; u }

## ---- stress signals ----
## R05_z (base signal)
sgn <- sign(cor(p$beta_R05, p$R05_z_avg, use="complete.obs")); stress_R05 <- { u<-epct(p$R05_z_avg); if(sgn>=0)(1-u) else u }
## A5: MSM crisis prob (pinned)
load_pit <- function(file, cols){ urs<-as.data.table(read_parquet(file.path(WD,"pinned_cache",file)))
  cc<-intersect(cols,names(urs))[1]; if(is.na(cc)) return(list(v=rep(NA,n),col=NA))
  urs[,Date:=as.Date(Date)]; setorder(urs,Date); urs<-urs[is.finite(get(cc))]
  v<-rep(NA_real_,n); for(i in 1:n){ pv<-urs[Date<p$anchor_date[i]]; if(nrow(pv)>0) v[i]<-tail(pv[[cc]],1) }; list(v=v,col=cc) }
a5 <- load_pit("unified_regime_signal_daily.parquet", c("MSM_Crisis_Prob"))
stress_MSM <- epct(a5$v); PG("[PG] A5 col=%s", a5$col)
## Bear_Prob_lag: jump-model bear prob, ALREADY LAGGED (PIT-clean by construction)
jp <- load_pit("regime_jump_daily.parquet", c("Bear_Prob_lag","Bear_Prob"))
stress_JMP <- epct(jp$v); PG("[PG] jump col=%s finite=%.2f", jp$col, mean(is.finite(jp$v)))
## Regime_Score_smooth: smoothed regime score (less whipsaw)
rsm <- load_pit("unified_regime_signal_daily.parquet", c("Regime_Score_smooth"))
sgn_rsm <- sign(cor(p$beta_R05, epct(rsm$v), use="complete.obs")); u_rsm<-epct(rsm$v)
stress_RSM <- if(sgn_rsm>=0)(1-u_rsm) else u_rsm; PG("[PG] RSM col=%s sgn=%d", rsm$col, sgn_rsm)
## DD-control: underlying ret_orig running drawdown, LAGGED (C9 PIT) — persistent/slow signal
nav_o <- cumprod(1+p$ret_orig); peak<-cummax(nav_o); dd <- 1 - nav_o/peak; dd_lag <- c(0, dd[-n])
stress_DD <- dd_lag                        ## raw lagged drawdown (linear rule below)
## combined MSM x R05 (max stress = union of both risk signals)
stress_CMB <- pmax(stress_R05, stress_MSM)
## avg-matched LINEAR de-risk builder (for persistent signals like DD)
build_linear <- function(sv, tgt=mean_beta_base, floor=FLOOR){
  f<-function(k) mean(pmax(floor, 1 - k*sv)) - tgt
  k<-tryCatch(uniroot(f,c(0,200))$root,error=function(e)NA); if(is.na(k)) return(rep(NA,length(sv)))
  pmax(floor, 1 - k*sv) }

## ---- avg-exposure-matched tail-cut builder ----
build_tailcut <- function(sv, tgt=mean_beta_base, floor=FLOOR, gamma=2){
  f<-function(th){ x<-pmax(0,(sv-th)/(1-th+1e-9)); mean(1-(1-floor)*pmin(1,x)^gamma)-tgt }
  th<-tryCatch(uniroot(f,c(0,0.999))$root,error=function(e)NA); if(is.na(th)) return(rep(NA,length(sv)))
  x<-pmax(0,(sv-th)/(1-th+1e-9)); 1-(1-floor)*pmin(1,x)^gamma }

## ---- RISK-lens metric set ----
risk_metrics <- function(ret_vec, tag){
  x<-xts(ret_vec, order.by=p$anchor_date)
  sr<-as.numeric(table.AnnualizedReturns(x,scale=12)[3,1]); cagr<-as.numeric(Return.annualized(x,scale=12))
  mdd<-as.numeric(maxDrawdown(x)); calmar<-cagr/mdd; sortino<-as.numeric(SortinoRatio(x))*sqrt(12)
  cvar95<- -as.numeric(quantile(ret_vec,0.05)); cvar99<- -as.numeric(quantile(ret_vec,0.01))
  ## max DD duration (months underwater)
  nav<-cumprod(1+ret_vec); pk<-cummax(nav); uw<-nav<pk*0.9999; rl<-rle(uw); mdur<-if(any(rl$values)) max(rl$lengths[rl$values]) else 0
  ## regime-conditional (AX-001): risk-off = CAUTION+CRISIS (19mo); mean ret + cumret in risk-off
  roff_idx <- p$regime %in% c("CAUTION","CRISIS")
  ro_mean <- mean(ret_vec[roff_idx]); ro_cum <- prod(1+ret_vec[roff_idx])-1
  ro_worst <- min(ret_vec[roff_idx])
  data.table(tag=tag, SR=sr, CAGR=cagr, MDD=mdd, Calmar=calmar, Sortino=sortino,
    CVaR95=cvar95, CVaR99=cvar99, maxDDdur=mdur,
    riskoff_mean=ro_mean, riskoff_cum=ro_cum, riskoff_worst=ro_worst) }

base_m <- risk_metrics(p$ret_base, "BASE_no_faith")
PG("[PG] recon SR=%.4f Calmar=%.4f MDD=%.4f", base_m$SR, base_m$Calmar, base_m$MDD)

cands <- list(
  A5_MSM_crisisprob = build_tailcut(stress_MSM),
  A3_condvoltarget  = NULL,  # placeholder (built below)
  DDctrl_linear     = build_linear(stress_DD),                                    # own-drawdown, persistent
  DDctrl_tailcut    = build_tailcut(epct(stress_DD)),                             # own-drawdown, percentile
  BearProb_lag      = if(mean(is.finite(jp$v))>0.5) build_tailcut(stress_JMP) else NULL,  # jump-model, pre-lagged
  RegScore_smooth   = build_tailcut(stress_RSM),                                  # smoothed regime (less whipsaw)
  MSMxR05_combined  = build_tailcut(stress_CMB),
  R05only_softref   = build_tailcut(stress_R05)
)
## A3 conditional vol-target (risk-off only), avg-matched
so<-p$ret_orig; sig<-rep(NA_real_,n); for(i in 13:n) sig[i]<-sd(so[(i-12):(i-1)]); sig[!is.finite(sig)]<-median(sig,na.rm=TRUE)
roff<-p$regime%in%c("CAUTION","CRISIS")
fv<-function(sc) mean(ifelse(roff,pmin(1,pmax(FLOOR,sc/sig)),1))-mean_beta_base
sc<-tryCatch(uniroot(fv,c(1e-6,100))$root,error=function(e)NA); cands$A3_condvoltarget<- if(!is.na(sc)) ifelse(roff,pmin(1,pmax(FLOOR,sc/sig)),1) else NULL

rows<-list(cbind(base_m, data.table(mean_beta=mean_beta_base, MDD_lag1=base_m$MDD, Calmar_lag1=base_m$Calmar, ret_paired_t=NA_real_)))
nw_t<-function(cand,base,lag=3){d<-cand-base;d<-d[is.finite(d)];nn<-length(d);mu<-mean(d);dm<-d-mu;g0<-sum(dm^2)/nn;gs<-0
  for(L in 1:lag){w<-1-L/(lag+1);gs<-gs+2*w*sum(dm[(L+1):nn]*dm[1:(nn-L)])/nn};mu/sqrt((g0+gs)/nn)}
for(nm in names(cands)){ bv<-cands[[nm]]; if(is.null(bv)||any(!is.finite(bv))){ PG("[PG] skip %s",nm); next }
  rc<-apply_gate(bv); mm<-risk_metrics(rc,nm)
  bv_lag<-shift(bv,1,fill=1.0); rc_lag<-apply_gate(bv_lag); ml<-risk_metrics(rc_lag,paste0(nm,"_lag1"))
  rpt<-nw_t(rc,p$ret_base)
  rows[[length(rows)+1]]<-cbind(mm, data.table(mean_beta=mean(bv), MDD_lag1=ml$MDD, Calmar_lag1=ml$Calmar, ret_paired_t=rpt))
  PG("[PG] %-18s MDD=%.4f(lag1 %.4f) Calmar=%.3f(lag1 %.3f) SR=%.3f roffCum=%.3f drag_t=%.2f",
     nm, mm$MDD, ml$MDD, mm$Calmar, ml$Calmar, mm$SR, mm$riskoff_cum, rpt) }
res<-rbindlist(rows,fill=TRUE)
## risk-overlay WIN = MDD < base AND lag1 MDD < base (robust) AND Calmar >= base AND drag small
res[, riskwin := is.finite(MDD)&MDD<base_m$MDD & is.finite(MDD_lag1)&MDD_lag1<base_m$MDD & Calmar>=base_m$Calmar]
print(res[, .(tag, MDD=round(MDD,4), MDD_lag1=round(MDD_lag1,4), Calmar=round(Calmar,3), Calmar_lag1=round(Calmar_lag1,3),
              SR=round(SR,3), roffCum=round(riskoff_cum,3), CVaR95=round(CVaR95,4), drag_t=round(ret_paired_t,2), riskwin)])
fwrite(res, file.path(WD,"cycleR1_riskoverlay_results.csv"))
PG("[PG] DONE R1. base MDD=%.4f Calmar=%.3f | risk-wins(robust)=%d", base_m$MDD, base_m$Calmar, sum(res$riskwin,na.rm=TRUE))
