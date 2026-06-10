# Codex HIGH/MEDIUM 대응: (1) e-level을 IS에서만 선택(OOS 미사용) (2) leave-one-crash-out.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(xts) })
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||!is.finite(a)) b else a
PROJ <- "G:/Quant_Module_Moltbot"
s  <- readRDS(file.path(PROJ, "04_Research/strategies/STR_valearn_70_top25/sim_result.rds"))
d  <- as.data.table(s$DAILY_NAV_DT)[, .(Date=as.Date(Date), r=Strategy_Ret)]; setorder(d, Date)
bm <- data.table(Date=as.Date(index(s$bm_xts)), bm=as.numeric(s$bm_xts[,1]))
d <- merge(d, bm, by="Date", all.x=TRUE)
RG <- as.data.table(read_parquet(file.path(PROJ, ".cache/unified_regime_signal_daily.parquet")))[!is.na(Category), .(Date=as.Date(Date), Category)]; setorder(RG, Date)
q <- data.table(Date=d$Date); res <- RG[q, on=.(Date), roll=TRUE]; d[, cat_me := res$Category]
d[, reg := shift(cat_me, 1L)]; d[is.na(reg), reg:="NEUTRAL"]
nM<-nrow(d); is_cut<-floor(nM*0.60)
srm<-function(x){x<-x[is.finite(x)];if(length(x)<3||sd(x)==0)return(NA);mean(x)/sd(x)*sqrt(12)}
mddm<-function(x){x<-x[is.finite(x)];n<-cumprod(1+x);as.numeric(1-min(n/cummax(n)))}
oos_ret_active <- function(net){ a<-net-d$bm; a<-a[is.finite(a)]; n<-length(a); kk<-floor(n*0.65)
  ii<-srm(a[1:kk]); oo<-srm(a[(kk+1):n]); if(is.finite(ii)&&ii>0.05) oo/ii else NA_real_ }
apply_ov <- function(e_d, idx=1:nM){ prev<-1; rn<-numeric(nM)
  for(i in 1:nM){ e<-if(d$reg[i]=="CAUTION"&&(i %in% idx)) e_d else 1; r<-e*d$r[i]; if(abs(e-prev)>1e-9) r<-r-abs(e-prev)*(15/1e4); prev<-e; rn[i]<-r }; rn }

cat("=== (1) e-level을 IS에서만 선택 (OOS 미사용; Codex HIGH#1) ===\n")
# IS window only: CAUTION off e in {0.5, 0.0} 중 IS Sharpe 최대 e 선택 → 그 e를 OOS에 forward 적용
is_idx <- 1:is_cut; oos_idx <- (is_cut+1):nM
is_sr_for_e <- sapply(c(0.5,0.0), function(e){ net<-apply_ov(e); srm(net[is_idx]) })
names(is_sr_for_e) <- c("e0.5","e0.0")
cat("  IS Sharpe by e (CAUTION off):\n"); print(round(is_sr_for_e,3))
e_star <- c(0.5,0.0)[which.max(is_sr_for_e)]
cat(sprintf("  → IS-선택 e* = %.1f (OOS 미열람)\n", e_star))
net_star <- apply_ov(e_star)
cat(sprintf("  forward OOS: net_SR(OOS)=%.3f MDD(OOS)=%.3f | full oos_retention=%.3f MDD(full)=%.3f\n",
  srm(net_star[oos_idx]), mddm(net_star[oos_idx]), oos_ret_active(net_star), mddm(net_star)))
cat(sprintf("  baseline OOS: net_SR=%.3f MDD=%.3f\n", srm(d$r[oos_idx]), mddm(d$r[oos_idx])))

cat("\n=== (2) leave-one-crash-out (Codex MEDIUM#3): CAUTION off e0.0, 특정 위기월 제외 ===\n")
# 위기 구간 인덱스
crash_2008 <- which(format(d$Date,"%Y%m") %in% c("200810","200811","200812","200902"))
crash_2020 <- which(format(d$Date,"%Y%m") %in% c("202002","202003","202004"))
full_net <- apply_ov(0.0)
cat(sprintf("  전체(2005~)         net_SR=%.3f MDD=%.3f oos_ret=%.3f\n", srm(full_net), mddm(full_net), oos_ret_active(full_net)))
# 2008 제외 (해당 월 baseline·overlay 동일 처리 위해 그 월 수익 0으로 마스킹 후 SR/MDD 재계산)
mask_sr <- function(net, drop){ keep<-setdiff(1:nM, drop); srm(net[keep]) }
mask_mdd<- function(net, drop){ keep<-setdiff(1:nM, drop); mddm(net[keep]) }
cat(sprintf("  2008위기 제외       overlay net_SR=%.3f MDD=%.3f | baseline net_SR=%.3f MDD=%.3f\n",
  mask_sr(full_net,crash_2008), mask_mdd(full_net,crash_2008), mask_sr(d$r,crash_2008), mask_mdd(d$r,crash_2008)))
cat(sprintf("  2020위기 제외       overlay net_SR=%.3f MDD=%.3f | baseline net_SR=%.3f MDD=%.3f\n",
  mask_sr(full_net,crash_2020), mask_mdd(full_net,crash_2020), mask_sr(d$r,crash_2020), mask_mdd(d$r,crash_2020)))
cat(sprintf("  둘 다 제외          overlay net_SR=%.3f MDD=%.3f | baseline net_SR=%.3f MDD=%.3f\n",
  mask_sr(full_net,c(crash_2008,crash_2020)), mask_mdd(full_net,c(crash_2008,crash_2020)),
  mask_sr(d$r,c(crash_2008,crash_2020)), mask_mdd(d$r,c(crash_2008,crash_2020))))
# CAUTION 디리스크가 위기 외 구간에서도 도움되는가 (SR 향상 지속성)
cat("\n  해석: 두 위기 모두 제외 후에도 overlay net_SR > baseline 이면 CAUTION 효과는 2-event 아티팩트 아님.\n")

cat("\n=== (3) RISK_ON throttle (Codex MEDIUM#4): OOS alpha 붕괴 지배국면 ===\n")
# RISK_ON e0.5 (IS Sharpe 양호하나 OOS active 음수 — 줄이면?)
ro_net <- (function(){ prev<-1; rn<-numeric(nM); for(i in 1:nM){ e<-if(d$reg[i]=="RISK_ON") 0.5 else 1; r<-e*d$r[i]; if(abs(e-prev)>1e-9) r<-r-abs(e-prev)*(15/1e4); prev<-e; rn[i]<-r }; rn })()
cat(sprintf("  RISK_ON e0.5: net_SR=%.3f MDD=%.3f oos_ret=%.3f (baseline oos_ret=-0.517)\n",
  srm(ro_net), mddm(ro_net), oos_ret_active(ro_net)))
cat("  주: RISK_ON 디리스크는 IS-위반 선택(IS Sharpe 1.08로 양호) → 데이터마이닝. 진단용만.\n")
