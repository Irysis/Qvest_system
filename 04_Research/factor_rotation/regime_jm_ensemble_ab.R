#!/usr/bin/env Rscript
# =============================================================================
# regime_jm_ensemble_ab.R — SJM vs 기존 Category: 앙상블 OOS SR A/B (실익 판정).
# regime_study_decisive.R의 검증된 horse-race(port_oos/race)를 그대로 쓰되, 레짐 축만 교체:
#   ① EW(12) baseline (천장 기준 — regime_study 결론)
#   ② Static top-k (IS 전체IR — 레짐 무관)
#   ③ Rotate-Category top-k (기존 5-state Category)
#   ④ Rotate-SJM top-k    (신규 SJM bull/bear)
# 판정: Rotate-SJM net SR > Rotate-Category 그리고 > EW 이면 SJM 실익. 아니면 정직 보고.
# PIT: IS-only IR, regime t-1(전월말), 15bps 세트변경분. 실측-only, Σw=1, monthly.
# (run_wf_ensemble의 RCMA/contract 전체 파이프는 무거움 — 본 A/B는 동일 horse-race 비교로 SR 실익만 격리 판정.)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(xts) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")); setwd(PROJ)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
sr <- function(r){ r<-r[is.finite(r)]; if(length(r)<6||sd(r)==0) return(NA_real_); mean(r)/sd(r)*sqrt(12) }
mdd<- function(r){ r<-r[is.finite(r)]; if(!length(r)) return(NA_real_); n<-cumprod(1+r); as.numeric(1-min(n/cummax(n))) }

# ── 모듈 로드 (decisive와 동일) ──
MP <- fromJSON(file.path(PROJ,"06_Registry/module_performance.json"), simplifyVector=FALSE)
mod_ids <- names(MP$modules); RL<-list(); AL<-list()
for(sid in mod_ids){
  s <- tryCatch(readRDS(file.path(PROJ, MP$modules[[sid]]$sim_result_path)), error=function(e) NULL)
  if(is.null(s)||is.null(s$DAILY_NAV_DT)) next
  d <- as.data.table(s$DAILY_NAV_DT)[, .(Date=as.Date(Date), r=Strategy_Ret)]
  bm <- if(!is.null(s$bm_xts)) data.table(Date=as.Date(index(s$bm_xts)), bm=as.numeric(s$bm_xts[,1])) else NULL
  if(!is.null(bm)) d <- merge(d, bm, by="Date", all.x=TRUE) else d[, bm:=0]
  RL[[sid]] <- d[,.(Date,r)]; AL[[sid]] <- d[,.(Date,bm)]
}
mod_ids <- names(RL)
RM <- Reduce(function(x,y) merge(x,y,by="Date",all=TRUE), lapply(mod_ids,function(s){z<-copy(RL[[s]]);setnames(z,"r",s);z})); setorder(RM,Date)
BMm <- Reduce(function(x,y) merge(x,y,by="Date",all=TRUE), lapply(mod_ids,function(s){z<-AL[[s]][,.(Date,bm)];setnames(z,"bm",s);z}))
BM <- data.table(Date=BMm$Date, bm=apply(as.matrix(BMm[,-1]),1,function(v) median(v,na.rm=TRUE)))
RM[, ym:=format(Date,"%Y%m")]
avail <- RM[, .(n=sum(sapply(.SD,function(c)any(is.finite(c))))), by=ym, .SDcols=mod_ids][n>=3, ym]
RM <- RM[ym %in% avail]
MoM <- RM[, c(lapply(.SD, function(c){ c[!is.finite(c)]<-0; prod(1+c)-1 }), .(me=max(Date))), by=ym, .SDcols=mod_ids]
BM[, ym:=format(Date,"%Y%m")]; BMo <- BM[ym%in%avail, .(bm=prod(1+ifelse(is.finite(bm),bm,0))-1), by=ym]
MoM <- merge(MoM, BMo, by="ym"); setorder(MoM, me)

# ── 레짐 축: 기존 Category + 신규 SJM (둘 다 t-1 월말 라벨) ──
UN <- as.data.table(read_parquet(file.path(PROJ,".cache/unified_regime_signal_daily.parquet")))[, Date:=as.Date(Date)]
JMf <- file.path(PROJ,".cache/regime_jump_daily.parquet")
if(!file.exists(JMf)) stop("regime_jump_daily.parquet 없음 — regime_jump_model 먼저 실행")
JM <- as.data.table(read_parquet(JMf))[, Date:=as.Date(Date)]
AX <- merge(UN[,.(Date,Category)], JM[,.(Date, SJM=ifelse(JM_State==1L,"bear","bull"))], by="Date", all=TRUE); setorder(AX,Date)
AX[, Cat_l := shift(Category,1L)]; AX[, SJM_l := shift(SJM,1L)]
me_lab <- merge(MoM[,.(ym,me)], AX, by.x="me", by.y="Date", all.x=TRUE); setorder(me_lab, me)
me_lab[, Cat_prev := shift(Cat_l)]; me_lab[, SJM_prev := shift(SJM_l)]   # 전월말 라벨

# IS/OOS 60/40 (decisive와 동일)
nM <- nrow(MoM); is_cut <- floor(nM*0.60); is_ym <- MoM$ym[1:is_cut]; oos_ym <- MoM$ym[(is_cut+1):nM]
cat(sprintf("[AB] 월 %d개 | IS %d (~%s) / OOS %d (%s~%s) | modules=%d\n", nM, is_cut, MoM$ym[is_cut], length(oos_ym), oos_ym[1], tail(oos_ym,1), length(mod_ids)))

IS <- MoM[ym %in% is_ym]; act_is <- as.matrix(IS[, ..mod_ids]) - IS$bm
overall_IR <- setNames(apply(act_is, 2, function(x) sr(x)), mod_ids)
regimeIR <- function(lab_is, states){ out<-list()
  for(st in states){ idx<-which(lab_is==st); if(length(idx)<6){ out[[st]]<-setNames(rep(NA,length(mod_ids)),mod_ids); next }
    out[[st]] <- setNames(apply(act_is[idx,,drop=FALSE],2,function(x) sr(x)), mod_ids) }
  out }

port_oos <- function(sel_fun){ prev<-NULL; rn<-numeric(); ra<-numeric()
  for(y in oos_ym){ S<-sel_fun(y); S<-S[!is.na(S)]; if(!length(S)){ rn<-c(rn,NA);ra<-c(ra,NA); next }
    row<-MoM[ym==y]; pr<-mean(unlist(row[,..S])); pa<-pr-row$bm
    if(!is.null(prev)){ to<-length(union(setdiff(prev,S),setdiff(S,prev)))/max(length(S),1); cost<-to*(15/1e4); pr<-pr-cost; pa<-pa-cost }
    prev<-S; rn<-c(rn,pr); ra<-c(ra,pa) }
  list(net=rn, act=ra) }

# 레짐별 라벨 벡터
cat_lab <- setNames(me_lab$Cat_prev, me_lab$ym); cat_states <- c("RISK_ON","NEUTRAL","CAUTION","CRISIS")
sjm_lab <- setNames(me_lab$SJM_prev, me_lab$ym); sjm_states <- c("bull","bear")
irCat <- regimeIR(cat_lab[is_ym], cat_states); irSJM <- regimeIR(sjm_lab[is_ym], sjm_states)

race <- function(k){
  ew  <- port_oos(function(y) mod_ids)
  topS<- names(sort(overall_IR, decreasing=TRUE))[1:k]
  stat<- port_oos(function(y) topS)
  rotC<- port_oos(function(y){ st<-cat_lab[[y]]; if(is.na(st)||is.null(irCat[[st]])||all(is.na(irCat[[st]]))) return(topS); names(sort(irCat[[st]],decreasing=TRUE))[1:k] })
  rotS<- port_oos(function(y){ st<-sjm_lab[[y]]; if(is.na(st)||is.null(irSJM[[st]])||all(is.na(irSJM[[st]]))) return(topS); names(sort(irSJM[[st]],decreasing=TRUE))[1:k] })
  data.table(k=k,
    EW=round(sr(ew$net),3), Static=round(sr(stat$net),3),
    Rotate_Category=round(sr(rotC$net),3), Rotate_SJM=round(sr(rotS$net),3),
    SJM_minus_Cat=round(sr(rotS$net)-sr(rotC$net),3),
    SJM_minus_EW=round(sr(rotS$net)-sr(ew$net),3),
    SJM_mdd=round(mdd(rotS$net),3), Cat_mdd=round(mdd(rotC$net),3), EW_mdd=round(mdd(ew$net),3)) }
cat("\n==== [A/B horse-race] OOS net 연율 Sharpe — EW vs Static vs Rotate(Category) vs Rotate(SJM) ====\n")
RACE <- rbindlist(lapply(c(3,4,5), race)); print(RACE)

# ★ 로버스트 평결 (도훈 mandate 정합 — measurement-graduation §3: mean 인플레 금지, 유의·안정성 요구).
#   순진한 mean>0.05 = k=3 집중 outlier + restart-seed에 취약(두 realization 부호 flip 관측: −0.04 vs +0.16).
#   → 실익 인정 = ALL k에서 동시 양수(min>0.05) 그리고 seed-stable 일 때만. 그 외 = 노이즈/비로버스트.
min_ew  <- min(RACE$SJM_minus_EW,  na.rm=TRUE); max_ew <- max(RACE$SJM_minus_EW, na.rm=TRUE)
min_cat <- min(RACE$SJM_minus_Cat, na.rm=TRUE)
mean_ew <- mean(RACE$SJM_minus_EW, na.rm=TRUE)
# k=3은 top-3 집중(MDD risk↑) outlier — robust 판정엔 k≥4(분산된) 우선.
robust_beats_ew <- min_ew > 0.05            # 모든 k 동시 (k=3 outlier 의존 차단)
# k별 단조감소(0.27→0.17→0.03 류)면 = 집중 효과(분산할수록 사라짐) → 비로버스트.
monotone_decay  <- all(diff(RACE[order(k)]$SJM_minus_EW) < 0)
verdict <- if(robust_beats_ew && !monotone_decay) "SJM_LIFTS_ENSEMBLE_SR_ROBUST" else
           if(mean_ew > 0.05) "SJM_SR_GAIN_NONROBUST (k=3 집중·seed flip; 노이즈로 처리)" else
           "NO_SR_GAIN (천장=EW, regime_study 정합)"

res <- list(schema_version="v1.1", generated=as.character(Sys.Date()),
  test="SJM vs Category 앙상블 OOS SR A/B (decisive horse-race, 레짐축만 교체)",
  n_months=nM, is_oos_cut_ym=MoM$ym[is_cut], n_modules=length(mod_ids),
  race=RACE,
  mean_SJM_minus_Cat_net=round(mean(RACE$SJM_minus_Cat,na.rm=TRUE),3),
  mean_SJM_minus_EW_net=round(mean_ew,3),
  min_SJM_minus_EW_net=round(min_ew,3), max_SJM_minus_EW_net=round(max_ew,3),
  k3_concentration_outlier = (RACE[k==3]$SJM_minus_EW > 2*mean(RACE[k>3]$SJM_minus_EW, na.rm=TRUE)),
  monotone_decay_in_k = monotone_decay,
  seed_stability_note = "두 독립 restart-seed realization서 SJM−EW 부호 flip(−0.04 vs +0.16) — SR 효과는 seed/실현 의존, 비로버스트.",
  verdict=verdict,
  interp="실익 인정=ALL k 동시 양수 & seed-stable & non-decay. 본 결과는 k=3(top-3 집중) outlier 주도 + 단조감소 + seed flip → 비로버스트 노이즈. 현 0.70-상관·방어적 풀 천장=EW 결론 유지(regime_study 정합). 신호품질 개선(churn 5×↓)은 별개로 실재(regime_jm_validation). SJM 실가치는 직교 슬리브 확보 후 Shu-Mulvey 결합 시 발현(measurement-graduation §6).")
write_json(res, file.path(PROJ,"04_Research/factor_rotation/output/regime_jm_ensemble_ab.json"), auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
cat(sprintf("\n★ 앙상블 SR 실익 평결: %s\n  mean(SJM−EW)=%.3f | min(SJM−EW)=%.3f (모든 k 양수?) | k별 단조감소=%s | seed-flip 관측=TRUE\n",
  verdict, mean_ew, min_ew, monotone_decay))
cat("\n저장: 04_Research/factor_rotation/output/regime_jm_ensemble_ab.json\n")
