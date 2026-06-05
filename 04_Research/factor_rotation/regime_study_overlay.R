#!/usr/bin/env Rscript
# =============================================================================
# regime_study_overlay.R — 국면 스터디 마지막 조각: 레짐 신호의 *대안 용도* 검증.
# 결정적 테스트(decisive)가 '모듈 선택용 레짐 로테이션 = 무가치'를 확정.
#   남은 질문: 레짐이 '북 전체 익스포저 오버레이'(CRISIS 디리스크)로는 가치 있는가?
#   = measurement-graduation §6이 SR 2.5 *주역*으로 지목한 메커니즘. 모듈선택과 별개 기전.
# 방법: 기준북 = EW(12). IS Category별 북 Sharpe로 디리스크 레짐을 IS-only 도출 →
#       그 규칙을 OOS에 적용(전월말 라벨). net Sharpe / MDD / CAGR 비교. PIT-clean.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(xts) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")); setwd(PROJ)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
srm <- function(r){ r<-r[is.finite(r)]; if(length(r)<6||sd(r)==0) return(NA_real_); mean(r)/sd(r)*sqrt(12) }
mddm<- function(r){ r<-r[is.finite(r)]; if(!length(r)) return(NA_real_); n<-cumprod(1+r); as.numeric(1-min(n/cummax(n))) }
cagrm<-function(r){ r<-r[is.finite(r)]; if(!length(r)) return(NA_real_); prod(1+r)^(12/length(r))-1 }

# 데이터
MP <- fromJSON(file.path(PROJ,"06_Registry/module_performance.json"), simplifyVector=FALSE)
mod_ids <- names(MP$modules); RL<-list(); BLs<-list()
for(sid in mod_ids){ s<-tryCatch(readRDS(file.path(PROJ,MP$modules[[sid]]$sim_result_path)),error=function(e)NULL)
  if(is.null(s)||is.null(s$DAILY_NAV_DT)) next
  d<-as.data.table(s$DAILY_NAV_DT)[,.(Date=as.Date(Date),r=Strategy_Ret)]
  bm<-if(!is.null(s$bm_xts)) data.table(Date=as.Date(index(s$bm_xts)),bm=as.numeric(s$bm_xts[,1])) else NULL
  if(!is.null(bm)) d<-merge(d,bm,by="Date",all.x=TRUE) else d[,bm:=0]
  RL[[sid]]<-d[,.(Date,r)]; BLs[[sid]]<-d[,.(Date,bm)] }
mod_ids<-names(RL)
RM<-Reduce(function(x,y)merge(x,y,by="Date",all=TRUE),lapply(mod_ids,function(s){z<-copy(RL[[s]]);setnames(z,"r",s);z}));setorder(RM,Date)
BMm<-Reduce(function(x,y)merge(x,y,by="Date",all=TRUE),lapply(mod_ids,function(s){z<-BLs[[s]];setnames(z,"bm",s);z}))
BM<-data.table(Date=BMm$Date, bm=apply(as.matrix(BMm[,-1]),1,function(v)median(v,na.rm=TRUE)))
RM[,ym:=format(Date,"%Y%m")]; avail<-RM[,.(n=sum(sapply(.SD,function(c)any(is.finite(c))))),by=ym,.SDcols=mod_ids][n>=3,ym]; RM<-RM[ym%in%avail]
# EW 북 일간 → 월간
RM[, ew := rowMeans(.SD,na.rm=TRUE), .SDcols=mod_ids]
BM[,ym:=format(Date,"%Y%m")]
book<-RM[,.(ew=prod(1+ifelse(is.finite(ew),ew,0))-1, me=max(Date)),by=ym]
bmo<-BM[ym%in%avail,.(bm=prod(1+ifelse(is.finite(bm),bm,0))-1),by=ym]
book<-merge(book,bmo,by="ym"); setorder(book,me)

# 레짐 (전월말 Category)
UN<-as.data.table(read_parquet(file.path(PROJ,".cache/unified_regime_signal_daily.parquet")))[,Date:=as.Date(Date)]; setorder(UN,Date)
UN[, Cat_l:=shift(Category,1L)]
ml<-merge(book[,.(ym,me)],UN[,.(Date,Cat_l)],by.x="me",by.y="Date",all.x=TRUE); setorder(ml,me)
ml[, reg_apply := shift(Cat_l)]   # 전월말 국면 → 이번달 적용
book<-merge(book, ml[,.(ym,reg=reg_apply)], by="ym"); setorder(book,me)
book[is.na(reg), reg:="RISK_ON"]

nM<-nrow(book); is_cut<-floor(nM*0.60); IS<-book[1:is_cut]; OOS<-book[(is_cut+1):nM]
cat(sprintf("[O0] EW 북 월 %d개 | IS %d / OOS %d (%s~%s)\n", nM, is_cut, nrow(OOS), OOS$ym[1], tail(OOS$ym,1)))

# IS Category별 북 통계 → 디리스크 레짐 도출 (IS-only)
isstat<-IS[, .(n=.N, mean=round(mean(ew),4), sharpe=round(srm(ew),3), mdd=round(mddm(ew),3)), by=reg][order(sharpe)]
cat("\n[O1] IS Category별 EW북 성과 (Sharpe 오름차순 = 디리스크 후보 위):\n"); print(isstat)
# 규칙: IS Sharpe 최저 1개 레짐 디리스크. 표본<6 레짐은 평가제외(중립 1.0).
elig<-isstat[n>=6]; derisk_reg <- elig$reg[1]
cat(sprintf("→ PIT 디리스크 레짐(IS 최저 Sharpe, n≥6): %s\n", derisk_reg))

# OOS 적용: 익스포저 e (디리스크 레짐만 축소), 나머지 1.0. cash=0. 전환 turnover 15bps.
run_overlay <- function(e_derisk){
  prev_e<-1; rn<-numeric()
  for(i in seq_len(nrow(OOS))){ e<-if(OOS$reg[i]==derisk_reg) e_derisk else 1.0
    r<- e*OOS$ew[i]; if(abs(e-prev_e)>1e-9) r<-r-abs(e-prev_e)*(15/1e4); prev_e<-e; rn<-c(rn,r) }
  rn }
base<-OOS$ew
variants<-rbindlist(lapply(c(1.0,0.5,0.0), function(e){ rn<-if(e==1.0) base else run_overlay(e)
  data.table(rule=sprintf("derisk_%s_e%.1f", derisk_reg, e), net_SR=round(srm(rn),3),
    CAGR=round(cagrm(rn),4), MDD=round(mddm(rn),3), Calmar=round(cagrm(rn)/mddm(rn),3)) }))
cat("\n[O2] OOS: 기준 EW북(e1.0) vs 디리스크 오버레이 — net Sharpe / CAGR / MDD / Calmar:\n")
print(variants)

# crisis 특정: CRISIS만 별도(표본 충분시) — AX-001 정합(crisis_alpha + MDD 완화)
if("CRISIS" %in% OOS$reg){
  cr_off<-function(e){ prev<-1;rn<-numeric(); for(i in seq_len(nrow(OOS))){ ee<-if(OOS$reg[i]=="CRISIS") e else 1
    r<-ee*OOS$ew[i]; if(abs(ee-prev)>1e-9) r<-r-abs(ee-prev)*(15/1e4); prev<-ee; rn<-c(rn,r)}; rn }
  crtab<-rbindlist(lapply(c(0.5,0.0),function(e){rn<-cr_off(e)
    data.table(rule=sprintf("CRISIS_off_e%.1f",e),net_SR=round(srm(rn),3),CAGR=round(cagrm(rn),4),MDD=round(mddm(rn),3),Calmar=round(cagrm(rn)/mddm(rn),3))}))
  cat("\n[O3] CRISIS 디리스크 단독 (AX-001 crisis_alpha/MDD 관점):\n")
  cat(sprintf("  기준 EW북: net_SR=%.3f CAGR=%.3f MDD=%.3f Calmar=%.3f\n", srm(base),cagrm(base),mddm(base),cagrm(base)/mddm(base)))
  print(crtab)
}

# 평결: 오버레이가 net SR 상승 OR (MDD 큰 완화 & 수익 유지) 면 가치
base_sr<-srm(base); base_mdd<-mddm(base); base_cal<-cagrm(base)/mddm(base)
best<-variants[net_SR==max(net_SR,na.rm=TRUE)][1]
overlay_helps <- (best$net_SR > base_sr+0.05) || (best$Calmar > base_cal*1.1)
verdict<- if(overlay_helps) "OVERLAY_PROMISING (book-level 디리스크 = 후속 레버)" else "OVERLAY_NEUTRAL (이 풀/기간선 미입증)"
cat(sprintf("\n★ 오버레이 평결: %s\n  기준 net_SR=%.3f Calmar=%.3f | best변형 net_SR=%.3f Calmar=%.3f\n",
  verdict, base_sr, base_cal, best$net_SR, best$Calmar))

out<-list(study="regime_overlay", base_EW_net_SR=round(base_sr,3), base_MDD=round(base_mdd,3), base_Calmar=round(base_cal,3),
  derisk_regime=derisk_reg, IS_regime_stats=isstat, OOS_variants=variants, verdict=verdict)
write_json(out, file.path(PROJ,"04_Research/factor_rotation/output/regime_study_overlay.json"), auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
cat("\n저장: 04_Research/factor_rotation/output/regime_study_overlay.json\n")
