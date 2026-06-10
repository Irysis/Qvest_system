#!/usr/bin/env Rscript
# =============================================================================
# regime_forecaster_v4.R — 국면엔진 예측력 강화: SJM(jump model) 선행 전환신호
# -----------------------------------------------------------------------------
# v2/v3 교훈: feature를 nudge에 더하면 crisis-prob와 중복·포화(예측 거의 불변). 문제는
#   feature가 아니라 *전환점 포착*. SJM(Statistical Jump Model)은 전환을 가장 빠르게
#   탐지(GFC 0d·COVID 5d, churn 4.7×↓)하도록 설계 → v1이 놓치는 전환을 선행할 후보.
# 2 구조 동시 테스트(둘 다 v1 대비 beats_v1 게이트):
#   v4a = v1 nudge + SJM Bear_Prob_chg 항 (빠른 changepoint nudge)
#   v4o = v1 + SJM **state-flip override**: SJM이 bear(JM_State_lag=1)인데 v1 예측이
#         비방어면 → CAUTION으로 선제 override(전환 anticipation, 구조적으로 다름)
# ★ PIT: SJM Bear_Prob_lag/JM_State_lag(이미 t-1 lag) 월말값. 실측 SJM 캐시(무fabrication).
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"); setwd(PROJ)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
MIN_IS <- 100L
regimes <- c("RISK_ON","NEUTRAL","CAUTION","CRISIS","RISK_OFF")
SJM_COEF <- as.numeric(Sys.getenv("FC_SJM_COEF","1.0"))   # SJM Bear_Prob_chg nudge (CrisisP_chg와 동급)

UN <- as.data.table(read_parquet(file.path(PROJ,".cache/unified_regime_signal_daily.parquet")))[, Date:=as.Date(Date)]
RD <- as.data.table(read_parquet(file.path(PROJ,".cache/regime_daily_v2.parquet")))[, Date:=as.Date(Date)]
JM <- as.data.table(read_parquet(file.path(PROJ,".cache/regime_jump_daily.parquet")))[, Date:=as.Date(Date)]
setorder(UN, Date); UN[, ym := format(Date,"%Y%m")]
me <- UN[!is.na(Category), .(d=max(Date)), by=ym]
M <- merge(me, UN[, .(Date, Category, CrisisP=MSM_Crisis_Prob)], by.x="d", by.y="Date")
M <- merge(M, RD[, .(Date, Claims=Claims_z_smooth, TS=TS_z_smooth)], by.x="d", by.y="Date", all.x=TRUE)
# SJM 월말값: 각 월말 이전 최근 (rolling join, t-1 lag 컬럼 사용 = 이중 PIT 안전)
M <- JM[, .(Date, SJM_Bear=Bear_Prob_lag, SJM_State=JM_State_lag)][M, on=.(Date=d), roll=TRUE]
setnames(M, "Date", "d"); setorder(M, d)
M[, CrisisP_chg := CrisisP - shift(CrisisP)]
M[, SJM_Bear_chg := SJM_Bear - shift(SJM_Bear)]
M <- M[Category %in% regimes]
M[, next_regime := shift(Category, 1L, type="lead")]
M <- M[d >= as.Date("2003-01-01")]
n <- nrow(M)
cat(sprintf("[fc_v4] 월말 패널 n=%d (%s..%s) | SJM Bear_Prob lead\n", n, as.character(min(M$d)), as.character(max(M$d))))

brier <- function(p, ai){ y<-rep(0,length(p)); y[ai]<-1; sum((p-y)^2) }
apply_nudge <- function(p, s){ s<-min(s,0.5); if(s>0){ defn<-regimes %in% c("CAUTION","CRISIS","RISK_OFF")
  p[defn]<-p[defn]*(1+s); p[!defn]<-p[!defn]*(1-s/2); p<-p/sum(p) }; p }
v1_hit<-rep(NA,n); va_hit<-rep(NA,n); vo_hit<-rep(NA,n); base_hit<-rep(NA,n)
v1_br<-rep(NA_real_,n); va_br<-rep(NA_real_,n); vo_br<-rep(NA_real_,n)
n_override <- 0L; n_a_diff <- 0L
for(t in seq_len(n-1)){
  if(t < MIN_IS) next
  cur <- M$Category[t]; actual <- M$next_regime[t]; if(is.na(actual)) next
  ai <- match(actual, regimes)
  hist <- M[1:t]
  trans <- table(factor(hist$Category, regimes), factor(shift(hist$Category,1L,type="lead"), regimes))
  row <- trans[cur, ]; p0 <- (row + 0.5)/sum(row + 0.5)
  s <- 0
  if(is.finite(M$CrisisP_chg[t])) s <- s + max(0, M$CrisisP_chg[t])*1.5
  if(is.finite(M$Claims[t]))      s <- s + max(0, M$Claims[t])*0.15
  if(is.finite(M$TS[t]))          s <- s + max(0, -M$TS[t])*0.10
  p1 <- apply_nudge(p0, s); pred1 <- regimes[which.max(p1)]
  v1_hit[t+1]<-as.integer(pred1==actual); v1_br[t+1]<-brier(p1,ai)
  # v4a: + SJM Bear_Prob_chg nudge
  sa <- s + (if(is.finite(M$SJM_Bear_chg[t])) max(0, M$SJM_Bear_chg[t])*SJM_COEF else 0)
  pa <- apply_nudge(p0, sa); preda <- regimes[which.max(pa)]
  va_hit[t+1]<-as.integer(preda==actual); va_br[t+1]<-brier(pa,ai); if(preda!=pred1) n_a_diff<-n_a_diff+1L
  # v4o: SJM state-flip override (bear인데 v1 예측 비방어 → CAUTION 선제)
  predo <- pred1; po <- p1
  if(is.finite(M$SJM_State[t]) && M$SJM_State[t]==1 && !(pred1 %in% c("CAUTION","CRISIS","RISK_OFF"))){
    predo <- "CAUTION"; n_override<-n_override+1L
    po <- rep(0.02,length(regimes)); names(po)<-regimes; po["CAUTION"]<-0.6; po["CRISIS"]<-0.2; po<-po/sum(po)
  }
  vo_hit[t+1]<-as.integer(predo==actual); vo_br[t+1]<-brier(po,ai)
  base_hit[t+1]<-as.integer(cur==actual)
}
ev <- which(!is.na(v1_hit) & !is.na(va_hit))
v1h<-mean(v1_hit[ev]); vah<-mean(va_hit[ev]); voh<-mean(vo_hit[ev]); bh<-mean(base_hit[ev])
v1b<-mean(v1_br[ev]);  vab<-mean(va_br[ev]);  vob<-mean(vo_br[ev])
beats_a <- (vah > v1h) && (vab < v1b); beats_o <- (voh > v1h) && (vob < v1b)
best <- if(beats_a||beats_o){ if(beats_a && (!beats_o || vah>=voh)) "v4a" else "v4o" } else "v1"

res <- list(schema_version="v4", generated=as.character(Sys.Date()),
  method="SJM(jump model) 선행 전환신호: v4a=Bear_Prob_chg nudge / v4o=state-flip override(bear→CAUTION 선제). v1 비교.",
  source="SJM regime_jump_daily.parquet (Statistical Jump Model, churn4.7×↓·crisis 신속탐지)",
  n_eval=length(ev), eval_window=c(as.character(M$d[min(ev)]),as.character(M$d[max(ev)])),
  n_a_changed_pred=n_a_diff, n_override=n_override,
  v1_hit_rate=round(v1h,3), v4a_hit_rate=round(vah,3), v4o_hit_rate=round(voh,3), persistence_hit_rate=round(bh,3),
  v1_brier=round(v1b,4), v4a_brier=round(vab,4), v4o_brier=round(vob,4),
  beats_v1_a=beats_a, beats_v1_o=beats_o, best_model=best,
  current_regime=M$Category[n], adopt=(beats_a||beats_o),
  note="채택=beats_v1(hit↑ & Brier↓). SJM이 전환점 선행으로 v1 천장 넘는가.")
write_json(res, file.path(PROJ,"04_Research/factor_rotation/output/regime_forecast_v4.json"),
           auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
cat("\n==== regime_forecaster v4 (SJM 선행 전환신호, 예측력 강화) ====\n")
cat(sprintf("eval n=%d (%s..%s) | v4a 예측바뀜=%d월 | v4o override=%d월\n", length(ev), res$eval_window[1], res$eval_window[2], n_a_diff, n_override))
cat(sprintf("hit-rate:  v4a=%.3f  v4o=%.3f  v1=%.3f  persist=%.3f\n", vah, voh, v1h, bh))
cat(sprintf("Brier:     v4a=%.4f  v4o=%.4f  v1=%.4f\n", vab, vob, v1b))
cat(sprintf("beats_v1: a=%s o=%s | best=%s → %s\n", beats_a, beats_o, best,
  if(beats_a||beats_o) "★ SJM 선행신호 채택" else "v1 천장 — SJM도 못 넘음(전환 정보 redundant/exogenous)"))
