## ★ PIT 감사 — BearProb 오버레이 동월 누출(faith 버그 재발) 여부 판정
## 의심: 신호를 Date<anchor_date(=return_ym 다음달 첫날)로 로드 = 홀딩월 말 정보 사용 = look-ahead
## 올바른 PIT: 신호는 홀딩월(return_ym) 시작 전 = Date < first-day-of-return_ym
## 세 타이밍으로 오버레이 재측정 → 개선이 엄격 PIT서 살아남으면 clean, 사라지면 누출.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts); library(lubridate) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705"); COST<-0.0015
p <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); n<-nrow(p)
p[, ret_ym_start := as.Date(paste0(return_ym, "-01"))]
mbeta<-mean(p$beta_R05); FLOOR<-min(p$beta_R05)
p[, dR05:=abs(beta_R05-shift(beta_R05,1,fill=1.0))]; p[, ret_base:=beta_R05*m4*ret_orig-dR05*COST]

## 라벨 타이밍 진단: anchor_date vs return_ym 시작일 간격
gap <- as.numeric(p$anchor_date - p$ret_ym_start)
PG("=== 타이밍 진단 ===")
PG("anchor_date − return_ym시작일 간격(일): 평균 %.1f  중앙 %.1f  범위 [%d, %d]", mean(gap), median(gap), min(gap), max(gap))
PG("→ 간격이 ~30일+면 anchor_date는 홀딩월 다음달 = 'Date<anchor'는 홀딩월 말 정보 사용(look-ahead)")
PG("예: return_ym=%s ret_orig=%.4f anchor_date=%s ret_ym시작=%s", p$return_ym[2], p$ret_orig[2], p$anchor_date[2], p$ret_ym_start[2])

## raw Bear_Prob daily
urs<-as.data.table(read_parquet(file.path(WD,"pinned_cache/regime_jump_daily.parquet")))
urs[,Date:=as.Date(Date)]; setorder(urs,Date); urs<-urs[is.finite(Bear_Prob_lag)]
load_at <- function(cutoff_vec){ v<-rep(NA_real_,n); for(i in 1:n){pv<-urs[Date<cutoff_vec[i]]; if(nrow(pv)>0) v[i]<-tail(pv$Bear_Prob_lag,1)}; v }
epct<-function(x){u<-rep(0.5,length(x));for(i in 2:length(x)){pv<-x[1:(i-1)];pv<-pv[is.finite(pv)];if(length(pv)>=6&&is.finite(x[i]))u[i]<-mean(pv<x[i])};u}
gate<-function(sv,floorL=0.5,gamma=2){th<-quantile(sv,0.6,na.rm=T);x<-pmax(0,(sv-th)/(1-th));1-(1-floorL)*pmin(1,x)^gamma}
apply_beta<-function(bt){db<-abs(bt-shift(bt,1,fill=1.0));bt*p$m4*p$ret_orig-db*COST}

## benchmark (anchor-window IKS200)
bm<-as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet")))
bm[,Date:=as.Date(Date)];bm<-bm[is.finite(BM_Ret)];setorder(bm,Date);bm_x<-xts(bm$BM_Ret,order.by=bm$Date)
a<-p$anchor_date;bmw<-rep(NA_real_,n);for(i in 2:n){seg<-bm_x[index(bm_x)>a[i-1]&index(bm_x)<=a[i]];if(nrow(seg)>0)bmw[i]<-as.numeric(Return.cumulative(seg))};bmw[1]<-0

met<-function(rv,tag){x<-xts(rv,order.by=p$anchor_date);act<-rv-bmw;act<-act[is.finite(act)]
  mu<-mean(act);dm<-act-mu;nn<-length(act);g0<-sum(dm^2)/nn;gs<-0;for(L in 1:3){w<-1-L/4;gs<-gs+2*w*sum(dm[(L+1):nn]*dm[1:(nn-L)])/nn};pt<-mu/sqrt((g0+gs)/nn)
  data.table(tag=tag,SR=as.numeric(table.AnnualizedReturns(x,scale=12)[3,1]),MDD=as.numeric(maxDrawdown(x)),
    Calmar=as.numeric(Return.annualized(x,scale=12))/as.numeric(maxDrawdown(x)),PORT_t=pt,IR=mu/sd(act)*sqrt(12))}

## 세 타이밍
timings <- list(
  T_anchor_CURRENT = p$anchor_date,                         # 현재(의심): 홀딩월 말 정보
  T_retstart_PIT   = p$ret_ym_start,                        # 엄격 PIT: 홀딩월 시작 전
  T_prevmonth_PIT  = p$ret_ym_start %m-% months(0) - 0      # (동일, 명시)
)
timings$T_prevmonth_PIT <- NULL   # 중복 제거
base_m <- met(p$ret_base,"BASE(clean incumbent)")
PG("\n=== BASE recon ===")
PG("%s: SR=%.4f Calmar=%.4f MDD=%.4f PORT_t=%.3f IR=%.4f", base_m$tag, base_m$SR, base_m$Calmar, base_m$MDD, base_m$PORT_t, base_m$IR)
rows<-list(cbind(base_m, data.table(dIR=0)))
PG("\n=== BearProb 오버레이(L2m: R05×Bear 노출매칭) — 타이밍별 ===")
for(tn in names(timings)){ cutoff<-timings[[tn]]
  raw<-load_at(cutoff); stress<-epct(raw); gb<-gate(stress)
  b<-p$beta_R05*gb; b<-pmin(1,b*mbeta/mean(b))      # L2m: 노출 base로 매칭
  m<-met(apply_beta(b), tn); m$dIR<-m$IR-base_m$IR
  rows[[length(rows)+1]]<-m
  PG("%-18s SR=%.4f Calmar=%.4f MDD=%.4f PORT_t=%.3f IR=%.4f ΔIR=%+.4f | 신호커버=%.2f", tn, m$SR, m$Calmar, m$MDD, m$PORT_t, m$IR, m$dIR, mean(is.finite(raw))) }
res<-rbindlist(rows,fill=TRUE)
fwrite(res, file.path(WD,"pit_audit_bearprob_results.csv"))
PG("\n[판정] 현재타이밍 대비 엄격PIT서 Calmar/MDD 개선이 유지되면 clean, 사라지면 동월누출.")
PG("[DONE] PIT audit")
