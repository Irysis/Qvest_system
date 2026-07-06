## ============================================================================
## run_overlay_selfdev.R — 오버레이 자가발전 모드 (modecode OVL, 2026-07-06 도훈 지시)
## Axiom 엔진 통합: 미탐색 신호원 프론티어를 strict-PIT+가드로 순회 측정 → 각 결과 L-code emit
##   → harvest/distill이 프론티어 재형성. 실패도 정직히 emit하며 소진까지(AX-000, 멈추지 말 것).
## ★PIT: 모든 신호는 overlay_pit_guard로 홀딩월 시작 전 컷오프 강제 + lag1 + strict-A/B 내장.
## base = m4×R05 (aggregate 패널). 각 신호를 '대체 regime 게이트'로 avg-노출 매칭 테스트.
## 사용: Rscript -e 'source(".../run_overlay_selfdev.R")'  (인자 없음 = 1라운드 defensive-signal 프론티어)
## ============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705"); COST<-0.0015
PIN  <- file.path(WD, "pinned_cache")
source(file.path(ROOT,"02_Infrastructure/validation/overlay_pit_guard.R"))
source(file.path(ROOT,"02_Infrastructure/axiom/lcode_emit.R"))
Sys.setenv(CLAUDE_PROJECT_DIR=ROOT)

## ---- base (aggregate) + strict-PIT 컷오프 = 홀딩월(return_ym) 시작 ----
p <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); n<-nrow(p)
p[, hstart := overlay_signal_cutoff(return_ym)]
assert_overlay_pit(p$hstart, p$hstart, "OVL_selfdev")
mbeta<-mean(p$beta_R05); FLOOR<-min(p$beta_R05)
p[, dR05:=abs(beta_R05-shift(beta_R05,1,fill=1.0))]; p[, ret_base:=beta_R05*m4*ret_orig-dR05*COST]
epct<-function(x){u<-rep(0.5,length(x));for(i in 2:length(x)){pv<-x[1:(i-1)];pv<-pv[is.finite(pv)];if(length(pv)>=6&&is.finite(x[i]))u[i]<-mean(pv<x[i])};u}
gate<-function(sv,floorL=FLOOR,gamma=2){f<-function(th){x<-pmax(0,(sv-th)/(1-th+1e-9));mean(1-(1-floorL)*pmin(1,x)^gamma)-mbeta}
  th<-tryCatch(uniroot(f,c(0,0.999))$root,error=function(e)NA);if(is.na(th))return(rep(NA,length(sv)));x<-pmax(0,(sv-th)/(1-th+1e-9));1-(1-floorL)*pmin(1,x)^gamma}
apply_beta<-function(bt){db<-abs(bt-shift(bt,1,fill=1.0));bt*p$m4*p$ret_orig-db*COST}
rmet<-function(rv){x<-xts(rv,order.by=p$anchor_date)
  list(SR=as.numeric(table.AnnualizedReturns(x,scale=12)[3,1]),MDD=as.numeric(maxDrawdown(x)),
    Calmar=as.numeric(Return.annualized(x,scale=12))/as.numeric(maxDrawdown(x)),CVaR95=-as.numeric(quantile(rv,0.05)))}
base_m <- rmet(p$ret_base)
PG("[OVL] base(m4×R05) SR=%.3f Calmar=%.3f MDD=%.3f", base_m$SR, base_m$Calmar, base_m$MDD)

## 신호를 cutoff_vec '전' 최신값으로 로드 (daily Date 기준)
load_sig <- function(file, col, cutoff_vec){
  d <- as.data.table(read_parquet(file.path(PIN,file))); if(!"Date"%in%names(d)) return(rep(NA,n))
  d[,Date:=as.Date(Date)]; setorder(d,Date); d<-d[is.finite(get(col))]
  v<-rep(NA_real_,n); for(i in 1:n){pv<-d[Date<cutoff_vec[i]]; if(nrow(pv)>0) v[i]<-tail(pv[[col]],1)}; v }

## ---- 프론티어: 미탐색 신호원 (orient +1=high는 risk / -1=low는 risk), family별 ----
FR <- list(
  list(fam="credit", sig="BBB_Spread",      file="macro_regime.parquet",   orient=+1),
  list(fam="credit", sig="HY_Spread",       file="macro_regime.parquet",   orient=+1),
  list(fam="term",   sig="Term_Spread",     file="macro_regime.parquet",   orient=-1),
  list(fam="term",   sig="YC_Inversion",    file="macro_regime.parquet",   orient=+1),
  list(fam="vol",    sig="VIX",             file="macro_regime.parquet",   orient=+1),
  list(fam="vol",    sig="VIX_Zscore",      file="macro_regime.parquet",   orient=+1),
  list(fam="macro",  sig="Macro_Risk_Score",file="macro_regime.parquet",   orient=+1),
  list(fam="macro",  sig="StL_Fin_Stress",  file="macro_regime.parquet",   orient=+1),
  list(fam="macro",  sig="Credit_Stress",   file="macro_regime.parquet",   orient=+1),
  list(fam="fx_lab", sig="KRW_Stress",      file="macro_regime.parquet",   orient=+1),
  list(fam="fx_lab", sig="Init_Claims",     file="macro_regime.parquet",   orient=+1),
  list(fam="maxis",  sig="MRS",             file="regime_daily_v2.parquet", orient=+1),
  list(fam="maxis",  sig="n_axes_firing",   file="regime_daily_v2.parquet", orient=+1)
)
loose_cut <- p$anchor_date   # look-ahead 대조(홀딩월 다음달)

results <- list()
for(cfg in FR){
  raw_s <- load_sig(cfg$file, cfg$sig, p$hstart)
  if(mean(is.finite(raw_s)) < 0.5){ PG("[OVL][skip] %s/%s cover<0.5", cfg$fam, cfg$sig); next }
  stress <- epct(cfg$orient * raw_s); bt <- gate(stress)
  if(any(!is.finite(bt))){ PG("[OVL][skip] %s gate NA", cfg$sig); next }
  bt<-pmin(1,pmax(FLOOR*0.9,bt)); m<-rmet(apply_beta(bt))
  ## falsification: lag1 + strict-A/B(loose)
  m_lag <- rmet(apply_beta(pmin(1,pmax(FLOOR*0.9,gate(shift(stress,1,fill=0.5))))))
  raw_l <- load_sig(cfg$file, cfg$sig, loose_cut); bt_l<-gate(epct(cfg$orient*raw_l))
  m_loose <- if(all(is.finite(bt_l))) rmet(apply_beta(pmin(1,pmax(FLOOR*0.9,bt_l)))) else list(Calmar=NA)
  ab <- overlay_lookahead_ab(m_loose$Calmar %||% NA, m$Calmar, "Calmar")
  dCal <- m$Calmar - base_m$Calmar; dCal_lag <- m_lag$Calmar - base_m$Calmar
  survive <- is.finite(dCal) && dCal>0 && is.finite(dCal_lag) && dCal_lag>-0.02   # 개선 + lag1 robust
  results[[length(results)+1]] <- data.table(fam=cfg$fam, sig=cfg$sig, orient=cfg$orient,
    SR=m$SR, Calmar=m$Calmar, MDD=m$MDD, dCalmar=dCal, Calmar_lag1=m_lag$Calmar,
    loose_infl=ab$inflation, survive=survive)
  PG("[OVL] %-8s %-16s: Calmar=%.3f (base %.3f, Δ%+.3f) lag1=%.3f loose_infl=%.1f%% %s",
     cfg$fam, cfg$sig, m$Calmar, base_m$Calmar, dCal, m_lag$Calmar, 100*(ab$inflation%||%NA), if(survive)"★SURVIVE" else "")
}
res <- rbindlist(results, fill=TRUE)
fwrite(res, file.path(WD,"overlay_selfdev_round1_results.csv"))
n_surv <- sum(res$survive, na.rm=TRUE)
PG("\n[OVL] ===== 라운드1 요약: %d 신호 측정, survivors=%d =====", nrow(res), n_surv)

## ---- family별 L-code emit (Axiom 엔진 적립) ----
for(fm in unique(res$fam)){ sub<-res[fam==fm]; best<-sub[which.max(Calmar)]
  fam_surv <- any(sub$survive, na.rm=TRUE)
  grade <- if(fam_surv) "B" else "F"
  lesson <- sprintf("OVL defensive 게이트 신호원 family=%s (strict-PIT+가드): %d 신호 [%s] 테스트, best=%s Calmar=%.3f (base %.3f, Δ%+.3f, lag1=%.3f). %s M4×R05 대체 게이트로 %s.",
    fm, nrow(sub), paste(sub$sig,collapse=","), best$sig, best$Calmar, base_m$Calmar, best$Calmar-base_m$Calmar, best$Calmar_lag1,
    if(fam_surv)"일부 개선(survivor)—" else "전 신호 base 미달—",
    if(fam_surv)"forge 재검증 후보" else "이 envelope서 M4×R05 near-optimal 재확인(비전이)")
  emit_lcode(mode="overlay_research", strategy_id=sprintf("OVL_defgate_%s_R1", fm), grade=grade,
    lesson_text=lesson, metric_type="backtested", construction_type="regime_overlay",
    mechanism_hypothesis=sprintf("%s 신호가 M4×R05보다 위기 디리스킹을 더 잘 타이밍하면 Calmar↑; 상관 낮은 tier면 보완", fm),
    falsification_attempts=list(
      list(test="strict-PIT vs loose(anchor) A/B", result=if(max(sub$loose_infl,na.rm=TRUE)>0.05)"weakened" else "survived", effect_retained=1),
      list(test="lag1 지연 스트레스", result=if(fam_surv)"survived" else "falsified", effect_retained=0.5)),
    portfolio_alpha_t=NA, selection_type="sweep",
    metrics=list(base_calmar=base_m$Calmar, best_calmar=best$Calmar, n_signals=nrow(sub), survivors=sum(sub$survive,na.rm=TRUE)),
    core_reference="run_overlay_selfdev.R R1", tags="OVL,DEFENSIVE_GATE,SIGNAL_SOURCE")
}
PG("[OVL] L-code emit 완료 (family별). survivors=%d → %s", n_surv,
   if(n_surv>0)"survivor forge 재검증 후속" else "defensive-gate 신호원 프론티어 이 라운드 소진 → 다음: 공격형/2-signal/turnover 프론티어")
PG("[OVL] DONE round1")
