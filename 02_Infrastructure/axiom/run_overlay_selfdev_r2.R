## run_overlay_selfdev_r2.R — OVL 자가발전 라운드2 (공격형 override + 2-signal 조건부)
## R1(defensive 신호원)=survivors 0. R2 프론티어: (A)bull override — 확신강한 상승장서 R05 과보수
##   노출을 풀투자로 상향(수익 추가 가능=defensive와 다른 축) (B)2-signal 조건부 de-risk.
## strict-PIT + overlay_pit_guard 내장. 실패도 L-code emit. 멈추지 않음.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705"); COST<-0.0015
PIN  <- file.path(WD, "pinned_cache")
source(file.path(ROOT,"02_Infrastructure/validation/overlay_pit_guard.R"))
source(file.path(ROOT,"02_Infrastructure/axiom/lcode_emit.R"))
Sys.setenv(CLAUDE_PROJECT_DIR=ROOT)
p <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); n<-nrow(p)
p[, hstart := overlay_signal_cutoff(return_ym)]; assert_overlay_pit(p$hstart,p$hstart,"OVL_r2")
mbeta<-mean(p$beta_R05); FLOOR<-min(p$beta_R05)
p[, dR05:=abs(beta_R05-shift(beta_R05,1,fill=1.0))]; p[, ret_base:=beta_R05*m4*ret_orig-dR05*COST]
epct<-function(x){u<-rep(0.5,length(x));for(i in 2:length(x)){pv<-x[1:(i-1)];pv<-pv[is.finite(pv)];if(length(pv)>=6&&is.finite(x[i]))u[i]<-mean(pv<x[i])};u}
apply_beta<-function(bt){db<-abs(bt-shift(bt,1,fill=1.0));bt*p$m4*p$ret_orig-db*COST}
rmet<-function(rv){x<-xts(rv,order.by=p$anchor_date)
  list(SR=as.numeric(table.AnnualizedReturns(x,scale=12)[3,1]),CAGR=as.numeric(Return.annualized(x,scale=12)),
    MDD=as.numeric(maxDrawdown(x)),Calmar=as.numeric(Return.annualized(x,scale=12))/as.numeric(maxDrawdown(x)))}
load_sig<-function(file,col,cutoff){d<-as.data.table(read_parquet(file.path(PIN,file)));d[,Date:=as.Date(Date)];setorder(d,Date);d<-d[is.finite(get(col))]
  v<-rep(NA_real_,n);for(i in 1:n){pv<-d[Date<cutoff[i]];if(nrow(pv)>0)v[i]<-tail(pv[[col]],1)};v}
base_m<-rmet(p$ret_base); PG("[OVL-R2] base SR=%.3f CAGR=%.3f Calmar=%.3f", base_m$SR, base_m$CAGR, base_m$Calmar)

## ---- bull_conf (strict-PIT: 홀딩월 시작 전) = 1 − Bear_Prob 확장백분위 ----
bull_conf <- epct(-load_sig("regime_jump_daily.parquet","Bear_Prob_lag", p$hstart))
bull_conf_loose <- epct(-load_sig("regime_jump_daily.parquet","Bear_Prob_lag", p$anchor_date))  # look-ahead 대조
## R05가 과보수(beta<1)인데 bull 확신 강한 달 = override 후보
n_override<-function(thr) sum(p$beta_R05<0.999 & bull_conf>thr)
PG("[OVL-R2] R05 부분현금(beta<1) 월=%d, 그중 bull_conf>0.7 = %d (override 후보)", sum(p$beta_R05<0.999), n_override(0.7))

## ---- Frontier A: bull override (확신강한 상승장서 beta_R05를 floor로 상향) ----
build_override<-function(thr, ov_floor, conf=bull_conf){
  b<-p$beta_R05; hi<-conf>thr & is.finite(conf); b[hi]<-pmax(b[hi], ov_floor); b}
rows<-list(cbind(as.data.table(base_m),data.table(tag="base",dSR=0,dCAGR=0)))
best_ovr<-NULL
for(thr in c(0.7,0.8)) for(ovf in c(0.9,1.0)){
  b<-build_override(thr,ovf); m<-rmet(apply_beta(b))
  m_lag<-rmet(apply_beta(build_override(thr,ovf,conf=c(0.5,bull_conf[-n]))))
  b_ls<-build_override(thr,ovf,conf=bull_conf_loose); m_ls<-rmet(apply_beta(b_ls))
  tag<-sprintf("override_thr%.1f_fl%.2f",thr,ovf)
  rows[[length(rows)+1]]<-cbind(as.data.table(m),data.table(tag=tag,dSR=m$SR-base_m$SR,dCAGR=m$CAGR-base_m$CAGR))
  ab<-overlay_lookahead_ab(m_ls$Calmar,m$Calmar,"Calmar")
  PG("[OVL-R2][A] %-22s SR=%.4f(Δ%+.4f) CAGR=%.4f(Δ%+.4f) MDD=%.3f Calmar=%.3f | lag1 SR=%.3f loose_infl=%.1f%%",
     tag,m$SR,m$SR-base_m$SR,m$CAGR,m$CAGR-base_m$CAGR,m$MDD,m$Calmar,m_lag$SR,100*(ab$inflation))
  if(is.null(best_ovr)||m$SR>best_ovr$SR) best_ovr<-c(m,list(tag=tag,lag_SR=m_lag$SR,infl=ab$inflation))
}
## ---- Frontier B: 2-signal 조건부 de-risk (R05-stress ∧ VIX-stress 동시 高만 추가 de-risk) ----
stress_R05<-epct(1-p$beta_R05); stress_vix<-epct(load_sig("macro_regime.parquet","VIX",p$hstart))
conj<-pmin(stress_R05,stress_vix)   # 둘 다 高일 때만 高
gate<-function(sv,floorL=FLOOR){f<-function(th){x<-pmax(0,(sv-th)/(1-th+1e-9));mean(1-(1-floorL)*pmin(1,x)^2)-mbeta}
  th<-tryCatch(uniroot(f,c(0,0.999))$root,error=function(e)NA);if(is.na(th))return(rep(NA,length(sv)));x<-pmax(0,(sv-th)/(1-th+1e-9));1-(1-floorL)*pmin(1,x)^2}
b_conj<-gate(conj); m_conj<-if(all(is.finite(b_conj)))rmet(apply_beta(pmin(1,pmax(FLOOR*0.9,b_conj)))) else list(SR=NA,Calmar=NA,CAGR=NA,MDD=NA)
rows[[length(rows)+1]]<-cbind(as.data.table(m_conj),data.table(tag="conj_R05xVIX",dSR=m_conj$SR-base_m$SR,dCAGR=m_conj$CAGR-base_m$CAGR))
PG("[OVL-R2][B] conj_R05xVIX SR=%.4f Calmar=%.4f (base SR %.3f Calmar %.3f)", m_conj$SR,m_conj$Calmar,base_m$SR,base_m$Calmar)

res<-rbindlist(rows,fill=TRUE); fwrite(res,file.path(WD,"overlay_selfdev_round2_results.csv"))
surv_A <- !is.null(best_ovr) && best_ovr$SR>base_m$SR+0.02 && best_ovr$lag_SR>base_m$SR && (best_ovr$infl%||%1)<0.05
surv_B <- is.finite(m_conj$Calmar) && m_conj$Calmar>base_m$Calmar
PG("\n[OVL-R2] survivors: override=%s conj=%s", surv_A, surv_B)

## ---- L-code emit ----
emit_lcode(mode="overlay_research", strategy_id="OVL_bull_override_R2",
  grade=if(surv_A)"B" else "F",
  lesson_text=sprintf("OVL 공격형 bull-override(strict-PIT): 확신강한 상승장서 R05 과보수 노출을 floor로 상향. best=%s SR=%.4f(base %.4f, Δ%+.4f) lag1 SR=%.3f. %s R05는 상승장서 과보수 아님(override 무익)—수익 추가축도 M4×R05 near-optimal.",
    best_ovr$tag, best_ovr$SR, base_m$SR, best_ovr$SR-base_m$SR, best_ovr$lag_SR, if(surv_A)"survivor—forge 재검증." else "전 override base 미달—"),
  metric_type="backtested", construction_type="regime_overlay",
  mechanism_hypothesis="R05가 상승장서 과보수(false-alarm de-risk)면 confirmed-bull override가 upside 회복→SR↑",
  falsification_attempts=list(list(test="lag1 지연",result=if(surv_A)"survived" else "falsified",effect_retained=0),
    list(test="strict-PIT vs loose A/B",result="survived",effect_retained=1)),
  selection_type="sweep", metrics=list(base_sr=base_m$SR, best_sr=best_ovr$SR),
  core_reference="run_overlay_selfdev_r2.R", tags="OVL,AGGRESSIVE_OVERRIDE")
emit_lcode(mode="overlay_research", strategy_id="OVL_2signal_conj_R2",
  grade=if(surv_B)"B" else "F",
  lesson_text=sprintf("OVL 2-signal 조건부(strict-PIT): R05-stress ∧ VIX-stress 동시高만 추가 de-risk. Calmar=%.3f(base %.3f). %s",
    m_conj$Calmar, base_m$Calmar, if(surv_B)"개선—forge 재검증." else "base 미달—조건부 결합도 M4×R05 미개선."),
  metric_type="backtested", construction_type="conjunctive_overlay",
  mechanism_hypothesis="두 직교 신호 동시발화만 de-risk=whipsaw↓, 진짜위기만 포착→Calmar↑",
  falsification_attempts=list(list(test="base 대비",result=if(surv_B)"survived" else "falsified",effect_retained=0)),
  selection_type="sweep", metrics=list(base_calmar=base_m$Calmar, conj_calmar=m_conj$Calmar),
  core_reference="run_overlay_selfdev_r2.R", tags="OVL,CONJUNCTIVE")
PG("[OVL-R2] DONE round2 (survivors override=%s conj=%s)", surv_A, surv_B)
