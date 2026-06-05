#!/usr/bin/env Rscript
# =============================================================================
# regime_forecaster.R — Factor Rotation Mode Track1-B (국면 사전 예측).
# 목적: 현 국면 분류가 아니라 *다음 국면을 사전 예측*해 배분을 선제적으로(reactive→proactive).
#   P(regime_{t+1} | info_t). PIT: trailing 관측만(expanding 추정, t-1 feature).
# 모델: ① expanding 경험적 전이행렬 P(next|current) + ② 지속(persistence) prior
#       + ③ stress nudge(Crisis_Prob 상승/Claims_z 고/TS_z 역전 → CRISIS·CAUTION 가중).
# 검증(walk-forward OOS): hit-rate + multiclass Brier — persistence baseline 대비.
#   채택 조건: forecast가 baseline 대비 우위 시만(아니면 contemporaneous 분류 사용 — 과적합 회피).
# 도훈 mandate 2026-06-05. 실측-only. 학술: Hamilton MS transition / BOCPD / FRED 선행.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")); setwd(PROJ)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
MIN_IS <- 60L  # 최소 IS 개월

# 1. 월간 국면(t-1) + 선행 feature -------------------------------------------
UN <- as.data.table(read_parquet(file.path(PROJ,".cache/unified_regime_signal_daily.parquet")))[, Date:=as.Date(Date)]
RD <- tryCatch(as.data.table(read_parquet(file.path(PROJ,".cache/regime_daily_v2.parquet")))[, Date:=as.Date(Date)], error=function(e) NULL)
setorder(UN, Date)
UN[, ym := format(Date,"%Y%m")]
# 월말 레코드 (Category + 선행지표). t-1 lag는 forecast 시점에 적용.
me <- UN[!is.na(Category), .(d=max(Date)), by=ym]
M <- merge(me, UN[, .(Date, Category, CrisisP=MSM_Crisis_Prob, KTRI=KTRI_Score)], by.x="d", by.y="Date")
if(!is.null(RD)) M <- merge(M, RD[, .(Date, Claims=Claims_z_smooth, TS=TS_z_smooth)], by.x="d", by.y="Date", all.x=TRUE)
setorder(M, d)
M[, CrisisP_chg := CrisisP - shift(CrisisP)]                 # 상승 = 스트레스 가속
regimes <- c("RISK_ON","NEUTRAL","CAUTION","CRISIS","RISK_OFF")
M <- M[Category %in% regimes]
M[, next_regime := shift(Category, 1L, type="lead")]         # 실제 다음달 국면 (검증용 label)
n <- nrow(M)

# 2. walk-forward 예측 --------------------------------------------------------
#   각 t: IS(1..t)로 전이행렬 추정 → 현재 Category + stress nudge로 P(next) → forecast.
brier <- function(p_vec, actual_idx){ y<-rep(0,length(p_vec)); y[actual_idx]<-1; sum((p_vec-y)^2) }
fc <- character(n); fc_hit <- rep(NA,n); base_hit <- rep(NA,n); fc_brier <- rep(NA_real_,n); base_brier <- rep(NA_real_,n)
for(t in seq_len(n-1)){
  if(t < MIN_IS) next
  cur <- M$Category[t]; actual <- M$Category[t+1]; if(is.na(actual)) next
  # 전이행렬 (IS 1..t, expanding)
  hist <- M[1:t]; trans <- table(factor(hist$Category, regimes), factor(shift(hist$Category,1L,type="lead"), regimes))
  row <- trans[cur, ]; p <- (row + 0.5) / sum(row + 0.5)     # Laplace smooth
  # stress nudge: Crisis_Prob 상승 + Claims 고 + TS 역전 → CRISIS/CAUTION 가중
  s <- 0
  if(is.finite(M$CrisisP_chg[t])) s <- s + max(0, M$CrisisP_chg[t]) * 1.5
  if(is.finite(M$Claims[t]))      s <- s + max(0, M$Claims[t]) * 0.15
  if(is.finite(M$TS[t]))          s <- s + max(0, -M$TS[t]) * 0.10
  s <- min(s, 0.5)
  if(s > 0){ defensive <- regimes %in% c("CAUTION","CRISIS","RISK_OFF")
    p[defensive] <- p[defensive] * (1+s); p[!defensive] <- p[!defensive] * (1-s/2); p <- p/sum(p) }
  pred <- regimes[which.max(p)]
  fc[t+1] <- pred
  fc_hit[t+1] <- as.integer(pred == actual)
  base_hit[t+1] <- as.integer(cur == actual)                # persistence baseline
  ai <- match(actual, regimes)
  fc_brier[t+1] <- brier(p, ai)
  base_p <- rep(0.02, length(regimes)); base_p[match(cur,regimes)] <- 0.92; base_p <- base_p/sum(base_p)
  base_brier[t+1] <- brier(base_p, ai)
}
ev <- which(!is.na(fc_hit))
res <- list(
  schema_version="v1.0", generated=as.character(Sys.Date()),
  method="expanding 전이행렬 + persistence prior + stress nudge(CrisisP/Claims/TS). walk-forward. PIT trailing-only.",
  n_eval=length(ev),
  forecast_hit_rate=round(mean(fc_hit[ev]),3), baseline_hit_rate=round(mean(base_hit[ev]),3),
  forecast_brier=round(mean(fc_brier[ev]),4), baseline_brier=round(mean(base_brier[ev]),4),
  beats_baseline = (mean(fc_hit[ev]) > mean(base_hit[ev])) && (mean(fc_brier[ev]) < mean(base_brier[ev])),
  current_regime = M$Category[n],
  note="채택 조건: beats_baseline=TRUE 시에만 forecast로 dispatch. 아니면 contemporaneous 분류 사용(과적합 회피, plan T1-B).")
dir.create(file.path(PROJ,"04_Research/factor_rotation/output"), showWarnings=FALSE, recursive=TRUE)
write_json(res, file.path(PROJ,"04_Research/factor_rotation/output/regime_forecast.json"), auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
cat(sprintf("\n==== regime_forecaster (다음국면 사전예측, walk-forward) ====\n"))
cat(sprintf("n_eval=%d | hit-rate forecast=%.3f vs persistence=%.3f | Brier forecast=%.4f vs %.4f\n",
  length(ev), mean(fc_hit[ev]), mean(base_hit[ev]), mean(fc_brier[ev]), mean(base_brier[ev])))
cat(sprintf("beats_baseline=%s → %s\n", res$beats_baseline,
  if(isTRUE(res$beats_baseline)) "forecast 채택 가능" else "미달 — contemporaneous 분류 사용(정직, 과적합 회피)"))
cat(sprintf("현재 국면=%s\n", res$current_regime %||% NA))
