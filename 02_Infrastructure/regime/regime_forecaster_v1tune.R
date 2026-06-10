#!/usr/bin/env Rscript
# =============================================================================
# regime_forecaster_v1tune.R — 국면엔진 강화: v1(최고모델)에 US-VIX nudge 추가
# -----------------------------------------------------------------------------
# v2(다항로짓 full feature)는 v1을 못 이김(과적합). 그러나 문헌 mandate(US-VIX가 KR
#   국면 Granger-cause; Kang-Yoon 2015)는 *targeted nudge*에 직접 넣으면 살 수 있음.
# 본 스크립트: v1(전이+nudge: CrisisP_chg/Claims/TS)을 baseline으로, v1_vix(+VIX_z항)를
#   동일 윈도우 walk-forward로 비교. 채택=v1_vix가 v1을 hit-rate AND Brier 둘 다 우위 시만.
#   다항로짓 없음 → 빠름. PIT trailing-only(전이행렬 1..t, feature t 월말값 → t+1 예측).
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"); setwd(PROJ)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
MIN_IS <- 100L
regimes <- c("RISK_ON","NEUTRAL","CAUTION","CRISIS","RISK_OFF")
VIX_COEF <- as.numeric(Sys.getenv("FC_VIX_COEF", "0.15"))   # US-VIX nudge 계수 (Claims와 동급 기본)

UN <- as.data.table(read_parquet(file.path(PROJ,".cache/unified_regime_signal_daily.parquet")))[, Date:=as.Date(Date)]
RD <- as.data.table(read_parquet(file.path(PROJ,".cache/regime_daily_v2.parquet")))[, Date:=as.Date(Date)]
setorder(UN, Date); UN[, ym := format(Date,"%Y%m")]
me <- UN[!is.na(Category), .(d=max(Date)), by=ym]
M <- merge(me, UN[, .(Date, Category, CrisisP=MSM_Crisis_Prob)], by.x="d", by.y="Date")
M <- merge(M, RD[, .(Date, VIX_z=VIX_z_smooth, Claims=Claims_z_smooth, TS=TS_z_smooth)], by.x="d", by.y="Date", all.x=TRUE)
setorder(M, d); M[, CrisisP_chg := CrisisP - shift(CrisisP)]
M <- M[Category %in% regimes & d >= as.Date("2000-06-01")]   # VIX 가용 구간 (공정비교)
M[, next_regime := shift(Category, 1L, type="lead")]
n <- nrow(M)

brier <- function(p, ai){ y<-rep(0,length(p)); y[ai]<-1; sum((p-y)^2) }
v1_hit<-rep(NA,n); vx_hit<-rep(NA,n); base_hit<-rep(NA,n)
v1_br<-rep(NA_real_,n); vx_br<-rep(NA_real_,n); base_br<-rep(NA_real_,n)
fcx <- character(n)
for(t in seq_len(n-1)){
  if(t < MIN_IS) next
  cur <- M$Category[t]; actual <- M$next_regime[t]; if(is.na(actual)) next
  ai <- match(actual, regimes)
  hist <- M[1:t]
  trans <- table(factor(hist$Category, regimes), factor(shift(hist$Category,1L,type="lead"), regimes))
  row <- trans[cur, ]; p0 <- (row + 0.5)/sum(row + 0.5)
  # 공통 stress (v1)
  s <- 0
  if(is.finite(M$CrisisP_chg[t])) s <- s + max(0, M$CrisisP_chg[t])*1.5
  if(is.finite(M$Claims[t]))      s <- s + max(0, M$Claims[t])*0.15
  if(is.finite(M$TS[t]))          s <- s + max(0, -M$TS[t])*0.10
  apply_nudge <- function(p, s){ s<-min(s,0.5); if(s>0){ defn<-regimes %in% c("CAUTION","CRISIS","RISK_OFF")
    p[defn]<-p[defn]*(1+s); p[!defn]<-p[!defn]*(1-s/2); p<-p/sum(p) }; p }
  # v1 (baseline)
  p1 <- apply_nudge(p0, s)
  pred1 <- regimes[which.max(p1)]; v1_hit[t+1]<-as.integer(pred1==actual); v1_br[t+1]<-brier(p1,ai)
  # v1_vix (+ US-VIX 항)
  svx <- s + (if(is.finite(M$VIX_z[t])) max(0, M$VIX_z[t])*VIX_COEF else 0)
  pvx <- apply_nudge(p0, svx)
  predx <- regimes[which.max(pvx)]; fcx[t+1]<-predx; vx_hit[t+1]<-as.integer(predx==actual); vx_br[t+1]<-brier(pvx,ai)
  # persistence
  base_hit[t+1]<-as.integer(cur==actual); bp<-rep(0.02,length(regimes)); bp[match(cur,regimes)]<-0.92; bp<-bp/sum(bp)
  base_br[t+1]<-brier(bp,ai)
}
ev <- which(!is.na(v1_hit) & !is.na(vx_hit))
v1h<-mean(v1_hit[ev]); vxh<-mean(vx_hit[ev]); bh<-mean(base_hit[ev])
v1b<-mean(v1_br[ev]);  vxb<-mean(vx_br[ev]);  bb<-mean(base_br[ev])
beats_v1 <- (vxh > v1h) && (vxb < v1b)
no_worse <- (vxh >= v1h) && (vxb <= v1b)

fc_series <- data.table(ym=M$ym, forecast_regime=ifelse(nzchar(fcx), fcx, NA_character_))
arrow::write_parquet(fc_series, file.path(PROJ,".cache/regime_forecast_series_v1vix.parquet"))
res <- list(schema_version="v1tune", generated=as.character(Sys.Date()),
  method=sprintf("v1(전이+nudge) + US-VIX nudge항(coef=%.2f). walk-forward 동일윈도우 비교.", VIX_COEF),
  vix_coef=VIX_COEF, n_eval=length(ev), eval_window=c(as.character(M$d[min(ev)]),as.character(M$d[max(ev)])),
  v1_hit_rate=round(v1h,3), v1vix_hit_rate=round(vxh,3), persistence_hit_rate=round(bh,3),
  v1_brier=round(v1b,4), v1vix_brier=round(vxb,4), persistence_brier=round(bb,4),
  beats_v1=beats_v1, no_worse_than_v1=no_worse,
  current_regime=M$Category[n], current_forecast=fcx[n] %||% NA,
  adopt=beats_v1, note="채택=beats_v1(hit↑ & Brier↓ 동시). no_worse면 US-VIX 무해편입 가능(문헌 mandate 충족).")
write_json(res, file.path(PROJ,"04_Research/factor_rotation/output/regime_forecast_v1vix.json"),
           auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
cat("\n==== regime_forecaster v1 + US-VIX nudge (국면엔진 강화) ====\n")
cat(sprintf("eval n=%d (%s..%s) | VIX_coef=%.2f\n", length(ev), res$eval_window[1], res$eval_window[2], VIX_COEF))
cat(sprintf("hit-rate:  v1+VIX=%.3f  v1=%.3f  persistence=%.3f\n", vxh, v1h, bh))
cat(sprintf("Brier:     v1+VIX=%.4f  v1=%.4f  persistence=%.4f\n", vxb, v1b, bb))
cat(sprintf("beats_v1=%s | no_worse=%s → %s\n", beats_v1, no_worse,
  if(beats_v1) "★ US-VIX nudge 채택" else if(no_worse) "무해(문헌 mandate 충족, 편입 가능)" else "악화 — 미채택"))
