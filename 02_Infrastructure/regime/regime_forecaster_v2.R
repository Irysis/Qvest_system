#!/usr/bin/env Rscript
# =============================================================================
# regime_forecaster_v2.R — 국면 엔진 성능 강화 (Track1-B 예측기 v2)
# -----------------------------------------------------------------------------
# v1(regime_forecaster.R) = expanding 전이행렬 + persistence prior + 임시 stress nudge
#   (CrisisP/Claims/TS 3개만). hit 0.741 / Brier 0.399 (beats persistence).
# v2 강화: 문헌 mandate(US-VIX가 KR 국면 Granger-cause; Kang-Yoon 2015 — "US 신호 1급
#   feature 의무")를 반영해 **선행 feature 전체**(regime_daily_v2: US-VIX/HY/TS/BBB/
#   FinStress/NFCI/Claims/Sentiment z + CrisisP/CrisisP_chg)를 **walk-forward 다항로짓**
#   (nnet::multinom, current_regime factor 포함)으로 학습해 다음 국면 P(next) 예측.
#   → 전이행렬은 current_regime predictor가 흡수, nudge는 학습된 계수로 대체(원칙화).
#
# ★ 공정비교: v1(전이+nudge)·v2(multinom)·persistence를 **동일 윈도우**(feature 가용 2000~)
#   에서 동시 산출. 채택 게이트: v2가 v1을 hit-rate AND Brier 둘 다 우위 시에만 채택.
# ★ PIT: feature/Category 월말값(t까지) → 다음달 예측(proactive). 학습=rows 1..t-1(next 관측분).
#   refit 12개월마다(연 1회, RCMA 정합), 그 사이 모델 고정. 미래정보 無.
# 실측-only. 출력: regime_forecast_v2.json + .cache/regime_forecast_series_v2.parquet(앙상블 소비).
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(nnet) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"); setwd(PROJ)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
MIN_TRAIN <- 100L; REFIT_EVERY <- 12L
regimes <- c("RISK_ON","NEUTRAL","CAUTION","CRISIS","RISK_OFF")

# ---- 1. 월말 패널: Category + CrisisP + 선행 feature ------------------------
UN <- as.data.table(read_parquet(file.path(PROJ,".cache/unified_regime_signal_daily.parquet")))[, Date:=as.Date(Date)]
RD <- as.data.table(read_parquet(file.path(PROJ,".cache/regime_daily_v2.parquet")))[, Date:=as.Date(Date)]
setorder(UN, Date); UN[, ym := format(Date,"%Y%m")]
me <- UN[!is.na(Category), .(d=max(Date)), by=ym]
M <- merge(me, UN[, .(Date, Category, CrisisP=MSM_Crisis_Prob)], by.x="d", by.y="Date")
FEAT <- c("VIX_z_smooth","HY_z_smooth","TS_z_smooth","BBB_z_smooth","FinStress_z_smooth",
          "NFCI_z_smooth","Claims_z_smooth","Sentiment_z_smooth")
M <- merge(M, RD[, c("Date", FEAT), with=FALSE], by.x="d", by.y="Date", all.x=TRUE)
setorder(M, d)
M[, CrisisP_chg := CrisisP - shift(CrisisP)]
M <- M[Category %in% regimes]
M[, next_regime := shift(Category, 1L, type="lead")]
# feature 가용 행만(2000~). NA feature는 0(평균) 대체(z-score라 0=중립).
PREDS <- c(FEAT, "CrisisP", "CrisisP_chg")
for(c in PREDS) M[!is.finite(get(c)), (c):=0]
M <- M[d >= as.Date("2000-06-01")]    # 선행 feature 가용 구간
n <- nrow(M)
cat(sprintf("[fc_v2] 월말 패널 n=%d (%s..%s) | preds=%d\n", n, as.character(min(M$d)), as.character(max(M$d)), length(PREDS)))

brier <- function(p_vec, actual_idx){ y<-rep(0,length(p_vec)); y[actual_idx]<-1; sum((p_vec-y)^2) }
fml <- as.formula(paste("next_regime ~ curfac +", paste(PREDS, collapse=" + ")))

# ---- 2. walk-forward: v2(multinom) + v1(전이+nudge) + persistence ----------
fc2 <- character(n); v2_hit<-rep(NA,n); v1_hit<-rep(NA,n); base_hit<-rep(NA,n)
v2_br<-rep(NA_real_,n); v1_br<-rep(NA_real_,n); base_br<-rep(NA_real_,n)
mod <- NULL; mod_at <- -Inf; train_levels <- regimes
for(t in seq_len(n-1)){
  if(t < MIN_TRAIN) next
  cur <- M$Category[t]; actual <- M$next_regime[t]; if(is.na(actual)) next
  ai <- match(actual, regimes)
  # --- v2: multinom (refit 연 1회) ---
  if(is.null(mod) || (t - mod_at) >= REFIT_EVERY){
    tr <- M[1:(t-1)][!is.na(next_regime)]
    tr[, curfac := factor(Category, levels=regimes)]
    tr[, next_regime := factor(next_regime, levels=regimes)]
    mod <- tryCatch(suppressWarnings(nnet::multinom(fml, data=tr, trace=FALSE, maxit=300)),
                    error=function(e) NULL)
    mod_at <- t
  }
  if(!is.null(mod)){
    nd <- M[t]; nd[, curfac := factor(Category, levels=regimes)]
    pr <- tryCatch(predict(mod, newdata=nd, type="probs"), error=function(e) NULL)
    if(!is.null(pr)){
      p2 <- setNames(rep(0,length(regimes)), regimes)
      if(is.null(dim(pr))) p2[names(pr)] <- pr else p2[colnames(pr)] <- pr[1,]
      p2 <- p2[regimes]; p2[!is.finite(p2)] <- 0; if(sum(p2)>0) p2 <- p2/sum(p2)
      pred2 <- regimes[which.max(p2)]
      fc2[t+1] <- pred2; v2_hit[t+1] <- as.integer(pred2==actual); v2_br[t+1] <- brier(p2, ai)
    }
  }
  # --- v1: expanding 전이행렬 + stress nudge (regime_forecaster.R 동일 로직) ---
  hist <- M[1:t]
  trans <- table(factor(hist$Category, regimes), factor(shift(hist$Category,1L,type="lead"), regimes))
  row <- trans[cur, ]; p1 <- (row + 0.5)/sum(row + 0.5)
  s <- 0
  if(is.finite(M$CrisisP_chg[t])) s <- s + max(0, M$CrisisP_chg[t])*1.5
  if(is.finite(M$Claims_z_smooth[t])) s <- s + max(0, M$Claims_z_smooth[t])*0.15
  if(is.finite(M$TS_z_smooth[t])) s <- s + max(0, -M$TS_z_smooth[t])*0.10
  s <- min(s, 0.5)
  if(s>0){ defn <- regimes %in% c("CAUTION","CRISIS","RISK_OFF")
    p1[defn] <- p1[defn]*(1+s); p1[!defn] <- p1[!defn]*(1-s/2); p1 <- p1/sum(p1) }
  pred1 <- regimes[which.max(p1)]
  v1_hit[t+1] <- as.integer(pred1==actual); v1_br[t+1] <- brier(p1, ai)
  # --- persistence baseline ---
  base_hit[t+1] <- as.integer(cur==actual)
  bp <- rep(0.02,length(regimes)); bp[match(cur,regimes)] <- 0.92; bp <- bp/sum(bp)
  base_br[t+1] <- brier(bp, ai)
}
ev <- which(!is.na(v2_hit) & !is.na(v1_hit))
v2h<-mean(v2_hit[ev]); v1h<-mean(v1_hit[ev]); bh<-mean(base_hit[ev])
v2b<-mean(v2_br[ev]);  v1b<-mean(v1_br[ev]);  bb<-mean(base_br[ev])
beats_v1 <- (v2h > v1h) && (v2b < v1b)
beats_base <- (v2h > bh) && (v2b < bb)

# ---- 3. emit (앙상블 소비 series; 채택 게이트 명시) -------------------------
fc_series <- data.table(ym = M$ym, forecast_regime = ifelse(nzchar(fc2), fc2, NA_character_))
arrow::write_parquet(fc_series, file.path(PROJ,".cache/regime_forecast_series_v2.parquet"))
res <- list(schema_version="v2.0", generated=as.character(Sys.Date()),
  method="walk-forward 다항로짓(nnet::multinom): next_regime ~ current + 선행 feature 전체(US-VIX/HY/TS/BBB/FinStress/NFCI/Claims/Sentiment + CrisisP/chg). refit 12m. PIT trailing-only.",
  features=PREDS, n_eval=length(ev), eval_window=c(as.character(M$d[min(ev)]), as.character(M$d[max(ev)])),
  v2_hit_rate=round(v2h,3), v1_hit_rate=round(v1h,3), persistence_hit_rate=round(bh,3),
  v2_brier=round(v2b,4), v1_brier=round(v1b,4), persistence_brier=round(bb,4),
  beats_v1=beats_v1, beats_persistence=beats_base,
  current_regime=M$Category[n], current_forecast=fc2[n] %||% NA,
  adopt=beats_v1, note="채택(dispatch v2 사용)=beats_v1 TRUE 시에만. 아니면 v1 유지(과적합 회피).")
write_json(res, file.path(PROJ,"04_Research/factor_rotation/output/regime_forecast_v2.json"),
           auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
cat("\n==== regime_forecaster v2 (선행 feature 다항로짓, 국면엔진 강화) ====\n")
cat(sprintf("eval n=%d (%s..%s)\n", length(ev), res$eval_window[1], res$eval_window[2]))
cat(sprintf("hit-rate:  v2=%.3f  v1=%.3f  persistence=%.3f\n", v2h, v1h, bh))
cat(sprintf("Brier:     v2=%.4f  v1=%.4f  persistence=%.4f\n", v2b, v1b, bb))
cat(sprintf("beats_v1=%s (hit↑ & Brier↓ 동시) | beats_persistence=%s\n", beats_v1, beats_base))
cat(sprintf("→ %s\n", if(beats_v1) "★ v2 채택 가능 (dispatch에 v2 series 사용)" else "v2 미채택 — v1 유지(정직, 과적합 회피)"))
cat(sprintf("현재 국면=%s | v2 다음달 예측=%s\n", M$Category[n], fc2[n] %||% NA))
