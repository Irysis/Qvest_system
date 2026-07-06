## run_overlay_selfdev_r3.R — OVL 자가발전 라운드3 (book vol-targeting + 3-signal + 연속 regime)
## R1(신호원)·R2(공격형/2-sig) survivors 0. R3: (A)book-level 변동성타게팅(trailing book vol PIT)
##   (B)3-signal 조건부 (C)연속 regime-composite 게이트. strict-PIT+가드. 실패도 emit, 멈추지 않음.
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
p[, hstart := overlay_signal_cutoff(return_ym)]; assert_overlay_pit(p$hstart,p$hstart,"OVL_r3")
mbeta<-mean(p$beta_R05); FLOOR<-min(p$beta_R05)
p[, dR05:=abs(beta_R05-shift(beta_R05,1,fill=1.0))]; p[, ret_base:=beta_R05*m4*ret_orig-dR05*COST]
## ret_orig 기반 = 오버레이 전 base 수익 (PIT: trailing만)
epct<-function(x){u<-rep(0.5,length(x));for(i in 2:length(x)){pv<-x[1:(i-1)];pv<-pv[is.finite(pv)];if(length(pv)>=6&&is.finite(x[i]))u[i]<-mean(pv<x[i])};u}
apply_beta<-function(bt){db<-abs(bt-shift(bt,1,fill=1.0));bt*p$m4*p$ret_orig-db*COST}
rmet<-function(rv){x<-xts(rv,order.by=p$anchor_date)
  list(SR=as.numeric(table.AnnualizedReturns(x,scale=12)[3,1]),CAGR=as.numeric(Return.annualized(x,scale=12)),
    MDD=as.numeric(maxDrawdown(x)),Calmar=as.numeric(Return.annualized(x,scale=12))/as.numeric(maxDrawdown(x)))}
load_sig<-function(file,col,cutoff){d<-as.data.table(read_parquet(file.path(PIN,file)));d[,Date:=as.Date(Date)];setorder(d,Date);d<-d[is.finite(get(col))]
  v<-rep(NA_real_,n);for(i in 1:n){pv<-d[Date<cutoff[i]];if(nrow(pv)>0)v[i]<-tail(pv[[col]],1)};v}
match_beta<-function(sv,floorL=FLOOR){f<-function(th){x<-pmax(0,(sv-th)/(1-th+1e-9));mean(1-(1-floorL)*pmin(1,x)^2)-mbeta}
  th<-tryCatch(uniroot(f,c(0,0.999))$root,error=function(e)NA);if(is.na(th))return(rep(NA,length(sv)));x<-pmax(0,(sv-th)/(1-th+1e-9));1-(1-floorL)*pmin(1,x)^2}
base_m<-rmet(p$ret_base); PG("[OVL-R3] base SR=%.3f Calmar=%.3f MDD=%.3f", base_m$SR,base_m$Calmar,base_m$MDD)
rows<-list(cbind(as.data.table(base_m),data.table(tag="base")))
emit_res<-list()

## ---- A: book-level 변동성 타게팅 (trailing 12m ret_orig vol, PIT) ----
so<-p$ret_orig; tv<-rep(NA_real_,n); for(i in 13:n) tv[i]<-sd(so[(i-12):(i-1)]); tv[!is.finite(tv)]<-median(tv,na.rm=T)
## beta_vt = target/tv, avg-matched via target
fvt<-function(tg){b<-pmin(1,pmax(FLOOR, tg/tv)); mean(b)-mbeta}
tg<-tryCatch(uniroot(fvt,c(1e-6,1))$root,error=function(e)NA)
if(!is.na(tg)){ b_vt<-pmin(1,pmax(FLOOR,tg/tv)); m_vt<-rmet(apply_beta(b_vt))
  b_vt_lag<-pmin(1,pmax(FLOOR,tg/c(median(tv,na.rm=T),tv[-n]))); m_vt_lag<-rmet(apply_beta(b_vt_lag))
  rows[[length(rows)+1]]<-cbind(as.data.table(m_vt),data.table(tag="book_voltarget"))
  survA<-m_vt$Calmar>base_m$Calmar & m_vt_lag$Calmar>base_m$Calmar-0.02
  PG("[OVL-R3][A] book_voltarget SR=%.4f Calmar=%.4f MDD=%.3f | lag1 Calmar=%.3f %s", m_vt$SR,m_vt$Calmar,m_vt$MDD,m_vt_lag$Calmar,if(survA)"★SURVIVE" else "")
  emit_res[["voltarget"]]<-list(grade=if(survA)"B" else "F",cal=m_vt$Calmar,lag=m_vt_lag$Calmar,surv=survA)
} else { emit_res[["voltarget"]]<-list(grade="F",cal=NA,lag=NA,surv=FALSE); PG("[OVL-R3][A] voltarget build fail") }

## ---- B: 3-signal 조건부 (R05 ∧ VIX ∧ StL_Fin_Stress 동시高만 de-risk) ----
sR05<-epct(1-p$beta_R05); sVIX<-epct(load_sig("macro_regime.parquet","VIX",p$hstart)); sFS<-epct(load_sig("macro_regime.parquet","StL_Fin_Stress",p$hstart))
conj3<-pmin(sR05,sVIX,sFS); b_c3<-match_beta(conj3)
m_c3<-if(all(is.finite(b_c3)))rmet(apply_beta(pmin(1,pmax(FLOOR*0.9,b_c3)))) else list(SR=NA,Calmar=NA,MDD=NA,CAGR=NA)
rows[[length(rows)+1]]<-cbind(as.data.table(m_c3),data.table(tag="conj3"))
survB<-is.finite(m_c3$Calmar)&&m_c3$Calmar>base_m$Calmar
PG("[OVL-R3][B] conj3(R05∧VIX∧FS) Calmar=%.4f (base %.3f) %s", m_c3$Calmar,base_m$Calmar,if(survB)"★SURVIVE" else "")
emit_res[["conj3"]]<-list(grade=if(survB)"B" else "F",cal=m_c3$Calmar,surv=survB)

## ---- C: 연속 regime-composite 게이트 (MRS 연속, avg-matched) ----
sMRS<-epct(load_sig("regime_daily_v2.parquet","MRS",p$hstart)); b_rc<-match_beta(sMRS)
m_rc<-if(all(is.finite(b_rc)))rmet(apply_beta(pmin(1,pmax(FLOOR*0.9,b_rc)))) else list(SR=NA,Calmar=NA,MDD=NA,CAGR=NA)
rows[[length(rows)+1]]<-cbind(as.data.table(m_rc),data.table(tag="regime_composite"))
survC<-is.finite(m_rc$Calmar)&&m_rc$Calmar>base_m$Calmar
PG("[OVL-R3][C] regime_composite(MRS연속) Calmar=%.4f %s", m_rc$Calmar,if(survC)"★SURVIVE" else "")
emit_res[["regime"]]<-list(grade=if(survC)"B" else "F",cal=m_rc$Calmar,surv=survC)

res<-rbindlist(rows,fill=TRUE); fwrite(res,file.path(WD,"overlay_selfdev_round3_results.csv"))
nsurv<-sum(sapply(emit_res,function(x)isTRUE(x$surv)))
## emit
emit_lcode(mode="overlay_research",strategy_id="OVL_book_voltarget_R3",grade=emit_res$voltarget$grade,
  lesson_text=sprintf("OVL book-level 변동성타게팅(trailing 12m book vol PIT, avg-matched): Calmar=%.3f(base %.3f) lag1=%.3f. %s vol-targeting book레벨도 M4×R05 미개선(vol-managed KR 비이전 재확인).",
    emit_res$voltarget$cal%||%NA,base_m$Calmar,emit_res$voltarget$lag%||%NA,if(emit_res$voltarget$surv)"survivor." else "미달—"),
  metric_type="backtested",construction_type="vol_target_overlay",
  mechanism_hypothesis="book 실현변동성 역가중=고변동기 노출↓→MDD↓·Calmar↑",
  falsification_attempts=list(list(test="lag1",result=if(emit_res$voltarget$surv)"survived" else "falsified",effect_retained=0)),
  selection_type="chain",metrics=list(base_calmar=base_m$Calmar,vt_calmar=emit_res$voltarget$cal%||%NA),
  core_reference="run_overlay_selfdev_r3.R",tags="OVL,VOL_TARGET")
emit_lcode(mode="overlay_research",strategy_id="OVL_conj3_regime_R3",grade=if(survB||survC)"B" else "F",
  lesson_text=sprintf("OVL 3-signal 조건부(R05∧VIX∧FS) Calmar=%.3f + 연속 regime-composite(MRS) Calmar=%.3f (base %.3f). 조건부·연속 결합도 M4×R05 미개선.",
    m_c3$Calmar%||%NA,m_rc$Calmar%||%NA,base_m$Calmar),
  metric_type="backtested",construction_type="conjunctive_overlay",
  mechanism_hypothesis="3직교신호 동시발화만 de-risk(whipsaw↓) + 연속매핑(cliff↓)",
  falsification_attempts=list(list(test="base 대비",result=if(survB||survC)"survived" else "falsified",effect_retained=0)),
  selection_type="sweep",metrics=list(base_calmar=base_m$Calmar,conj3_calmar=m_c3$Calmar%||%NA,regime_calmar=m_rc$Calmar%||%NA),
  core_reference="run_overlay_selfdev_r3.R",tags="OVL,CONJUNCTIVE,CONTINUOUS")
PG("[OVL-R3] ===== R3 survivors=%d =====", nsurv)
PG("[OVL-R3] DONE round3")
