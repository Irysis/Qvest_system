#!/usr/bin/env Rscript
# =============================================================================
# ep_multisleeve.R — EP 직교 슬리브 실가치: momentum + EP 명시적 결합 vs 단독.
#   A/B horse-race(IR-rank)는 약한-overall 모듈(EP)을 top-k서 자동 배제 → 직교가치 발현 안 됨.
#   본 스크립트는 직교성 가치가 발현되는 구조(명시적 2-sleeve 결합)를 직접 측정:
#     단독 momentum / 단독 EP / [50:50] / [risk-parity inverse-vol] / [SJM-conditional]
#   기준: 결합 net SR > max(단독) 또는 결합 MDD < min(단독 MDD)면 직교 슬리브 실가치.
# PIT: 모듈 frozen, 월간, 15bps 리밸 비용, IS/OOS 60/40 OOS 보고.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(xts); library(arrow) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"); setwd(PROJ)
sr  <- function(r){ r<-r[is.finite(r)]; if(length(r)<6||sd(r)==0) return(NA_real_); mean(r)/sd(r)*sqrt(12) }
mdd <- function(r){ r<-r[is.finite(r)]; if(!length(r)) return(NA_real_); n<-cumprod(1+r); as.numeric(1-min(n/cummax(n))) }
cagr<- function(r){ r<-r[is.finite(r)]; if(!length(r)) return(NA_real_); (prod(1+r))^(12/length(r))-1 }
load_monthly <- function(p){ s<-readRDS(file.path(PROJ,p)); d<-as.data.table(s$DAILY_NAV_DT)[,.(Date=as.Date(Date),r=Strategy_Ret)]
  bm<-data.table(Date=as.Date(index(s$bm_xts)),bm=as.numeric(s$bm_xts[,1])); d<-merge(d,bm,by='Date',all.x=TRUE)
  d[,ym:=format(Date,'%Y%m')]; d[!is.finite(r),r:=0]; d[!is.finite(bm),bm:=0]; d[,.(r=prod(1+r)-1,bm=prod(1+bm)-1),by=ym] }

EP_ID  <- "STR_AS_20260605_202226_37668"
# momentum sleeve 후보: residual momentum 풀구간(grade C, 가장 강한 momentum 모듈)
MOM_ID <- "STR_AS_20260605_185153_35464"
EP  <- load_monthly(file.path("04_Research/strategies", EP_ID,  "sim_result.rds"))
MOM <- load_monthly(file.path("04_Research/strategies", MOM_ID, "sim_result.rds"))
D <- merge(EP[,.(ym, ep=r, bm=bm)], MOM[,.(ym, mom=r)], by="ym"); setorder(D, ym)
cat(sprintf("[multi-sleeve] overlap %d months %s~%s\n", nrow(D), D$ym[1], tail(D$ym,1)))
cat(sprintf("  EP vs MOM cor_ret=%.3f cor_act=%.3f\n",
            cor(D$ep, D$mom), cor(D$ep-D$bm, D$mom-D$bm)))

# IS/OOS 60/40
nM<-nrow(D); cut<-floor(nM*0.6); is_ix<-1:cut; oos_ix<-(cut+1):nM
cat(sprintf("  IS=%s~%s OOS=%s~%s\n", D$ym[1], D$ym[cut], D$ym[cut+1], tail(D$ym,1)))

# 결합 방식 (전부 long-only convex, Σw=1)
# 1) 단독 MOM  2) 단독 EP  3) 50:50  4) inverse-vol risk-parity (IS vol로 weight, OOS 적용)
to_cost <- function(w_series_prev, w_series_now){ # 월간 리밸 turnover×15bps (2-asset)
  sum(abs(w_series_now - w_series_prev)) * (15/1e4) }

build_port <- function(w_ep_fun){
  # w_ep_fun(y_idx) returns ep weight in [0,1]; mom = 1-ep. 비용=월 turnover.
  prev_ep <- NA; rn<-numeric(nM)
  for(i in 1:nM){ wep<-w_ep_fun(i); wmom<-1-wep
    pr <- wep*D$ep[i] + wmom*D$mom[i]
    if(!is.na(prev_ep)){ to <- abs(wep-prev_ep)+abs(wmom-(1-prev_ep)); pr <- pr - to*(15/1e4) }
    prev_ep<-wep; rn[i]<-pr }
  rn }

# IS inverse-vol weights (frozen, OOS 적용)
v_ep <- sd(D$ep[is_ix]); v_mom <- sd(D$mom[is_ix])
w_ep_iv <- (1/v_ep)/((1/v_ep)+(1/v_mom))
cat(sprintf("  IS vol: EP=%.4f MOM=%.4f → inverse-vol EP weight=%.3f\n", v_ep, v_mom, w_ep_iv))

ports <- list(
  MOM_only   = build_port(function(i) 0),
  EP_only    = build_port(function(i) 1),
  EW_5050    = build_port(function(i) 0.5),
  InvVol     = build_port(function(i) w_ep_iv)
)

# OOS 성과
tab <- rbindlist(lapply(names(ports), function(nm){
  r <- ports[[nm]]; ro <- r[oos_ix]
  data.table(sleeve=nm,
    OOS_netSR=round(sr(ro),3), OOS_CAGR=round(cagr(ro)*100,2), OOS_MDD=round(mdd(ro)*100,2),
    Full_netSR=round(sr(r),3), Full_MDD=round(mdd(r)*100,2)) }))
cat("\n==== EP+momentum multi-sleeve (OOS 60/40) ====\n"); print(tab)

# 평결
oos_sr <- setNames(tab$OOS_netSR, tab$sleeve); oos_mdd<-setNames(tab$OOS_MDD, tab$sleeve)
best_single_sr  <- max(oos_sr[c("MOM_only","EP_only")], na.rm=TRUE)
best_combo_sr   <- max(oos_sr[c("EW_5050","InvVol")], na.rm=TRUE)
min_single_mdd  <- min(oos_mdd[c("MOM_only","EP_only")], na.rm=TRUE)
best_combo_mdd  <- min(oos_mdd[c("EW_5050","InvVol")], na.rm=TRUE)
sr_improve  <- best_combo_sr  - best_single_sr
mdd_improve <- min_single_mdd - best_combo_mdd   # 양수면 MDD 감소(개선)
verdict <- if(sr_improve > 0.05 && mdd_improve > 0) "EP_SLEEVE_ADDS_VALUE (SR↑ & MDD↓)" else
           if(sr_improve > 0.05) "EP_SLEEVE_SR_ONLY (SR↑, MDD 미개선)" else
           if(mdd_improve > 1.0) "EP_SLEEVE_MDD_ONLY (MDD↓, SR 미개선 — 분산효과)" else
           "EP_SLEEVE_NO_VALUE (결합 < 단독)"
cat(sprintf("\n★ multi-sleeve 평결: %s\n  best single OOS SR=%.3f → best combo=%.3f (Δ%+.3f) | min single MDD=%.1f%% → combo=%.1f%% (Δ%+.1fpp)\n",
            verdict, best_single_sr, best_combo_sr, sr_improve, min_single_mdd, best_combo_mdd, -mdd_improve))

res <- list(schema_version="v1.0", generated=as.character(Sys.time()),
  ep_module=EP_ID, mom_module=MOM_ID, n_months=nM, oos_cut_ym=D$ym[cut],
  cor_ret=round(cor(D$ep,D$mom),3), cor_act=round(cor(D$ep-D$bm,D$mom-D$bm),3),
  inverse_vol_ep_weight=round(w_ep_iv,3), table=tab,
  best_single_oos_sr=round(best_single_sr,3), best_combo_oos_sr=round(best_combo_sr,3),
  sr_improvement=round(sr_improve,3), mdd_improvement_pp=round(mdd_improve,2),
  verdict=verdict)
write_json(res, file.path(PROJ,"04_Research/factor_rotation/output/ep_multisleeve.json"),
           auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
cat("저장: 04_Research/factor_rotation/output/ep_multisleeve.json\n")
