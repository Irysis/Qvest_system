## BearProb 오버레이 계산 단계별 실측 추출 (설명용)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1)
PG <- function(...) message(sprintf(...))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/pg2_overlay_gate_composition_20260705")
p <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); n<-nrow(p)

## STEP 1: 원자료 — 점프모델 Bear_Prob_lag (PIT: anchor 이전 최신값)
urs<-as.data.table(read_parquet(file.path(WD,"pinned_cache/regime_jump_daily.parquet")))
urs[,Date:=as.Date(Date)]; setorder(urs,Date); urs<-urs[is.finite(Bear_Prob_lag)]
raw<-rep(NA_real_,n); for(i in 1:n){pv<-urs[Date<p$anchor_date[i]]; if(nrow(pv)>0) raw[i]<-tail(pv$Bear_Prob_lag,1)}

## STEP 2: 확장 백분위 (과거 대비 지금 위험도 순위, PIT)
epct<-function(x){u<-rep(0.5,length(x));for(i in 2:length(x)){pv<-x[1:(i-1)];pv<-pv[is.finite(pv)];if(length(pv)>=6&&is.finite(x[i]))u[i]<-mean(pv<x[i])};u}
stress<-epct(raw)

## STEP 3: tailcut 게이트 (백분위 → 노출 β), 파라미터 명시
floorL<-0.5; gamma<-2; th<-quantile(stress,0.6,na.rm=TRUE)
gate<-function(sv){x<-pmax(0,(sv-th)/(1-th)); 1-(1-floorL)*pmin(1,x)^gamma}
beta_bear<-gate(stress)

## STEP 4: 최종 노출 = m4 × R05 × BearProb
p[, beta_bearp := beta_bear]
p[, beta_total_L2 := beta_R05 * beta_bearp]     # 곱셈 스택 (m4는 별도 곱해짐)
PG("=== 파라미터 ===")
PG("floor=%.2f  gamma=%d  threshold θ=%.3f (백분위 60%%지점)", floorL, gamma, th)
PG("raw Bear_Prob 범위 [%.3f, %.3f]  평균 %.3f", min(raw,na.rm=T), max(raw,na.rm=T), mean(raw,na.rm=T))
PG("게이트 β_bear: 평균 %.3f  1.0인 달 %.0f%%  0.5(바닥)인 달 %.0f%%", mean(beta_bear), 100*mean(beta_bear>0.999), 100*mean(beta_bear<0.55))

## 예시 월: 평온기 / 경계기 / 위기기
PG("\n=== 예시 월 (원자료→백분위→게이트→최종노출) ===")
ex<-p[realized_ym %in% c("2006-05","2008-10","2011-09","2020-03","2020-04","2022-06","2024-01")]
ex[, raw_bp := raw[match(realized_ym, p$realized_ym)]]
ex[, stress_pct := stress[match(realized_ym, p$realized_ym)]]
for(i in 1:nrow(ex)){ r<-ex[i]
  PG("%s regime=%-7s | Bear_Prob=%.3f → 백분위=%.0f%% → β_bear=%.3f | m4=%.2f β_R05=%.2f → 총노출=%.3f",
     r$realized_ym, r$regime, r$raw_bp, 100*r$stress_pct, r$beta_bearp, r$m4, r$beta_R05, r$m4*r$beta_R05*r$beta_bearp) }

## 게이트 곡선 (백분위→β 매핑 실측 몇 점)
PG("\n=== 게이트 곡선 (백분위 → β) ===")
for(q in c(0.3,0.5,0.6,0.7,0.8,0.9,1.0)) PG("백분위 %.0f%% → β_bear = %.3f", 100*q, gate(q))
PG("\n[DONE] BearProb 계산 단계 추출 완료")
