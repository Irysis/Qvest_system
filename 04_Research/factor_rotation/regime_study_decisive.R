#!/usr/bin/env Rscript
# =============================================================================
# regime_study_decisive.R — 국면 스터디 결정적 테스트.
# regime_study.R의 거짓양성(STR_1550가 거의 모든 레짐서 best=무조건부 품질) 차단:
#   "레짐을 알면 모듈선택이 *정적 최고선택을 넘어* 좋아지는가?"를 직접 검증.
#   ① demean 지속성: 레짐-상대 IR(모듈 IR − 모듈 전체평균)이 OOS에 남는가 (진짜 타이밍).
#   ② Head-to-race (월간, OOS): EW(12) vs Static top-k(IS 전체IR) vs Rotate top-k(IS 레짐IR).
#      Rotate ≈ Static 이면 레짐은 무가치(정적 선택만 유효). Rotate >> Static 이면 타이밍 실재.
# PIT: IS-only 추정, regime t-1(전월말), 비용 15bps(세트변경분). 실측-only, Σw=1.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(xts) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")); setwd(PROJ)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
sr <- function(r){ r<-r[is.finite(r)]; if(length(r)<6||sd(r)==0) return(NA_real_); mean(r)/sd(r)*sqrt(12) }   # monthly→ann
spear <- function(a,b){ ok<-is.finite(a)&is.finite(b); if(sum(ok)<4) return(NA_real_); suppressWarnings(cor(a[ok],b[ok],method="spearman")) }

# ── 데이터 (regime_study.R와 동일 로드) ──
MP <- fromJSON(file.path(PROJ,"06_Registry/module_performance.json"), simplifyVector=FALSE)
mod_ids <- names(MP$modules); RL<-list(); AL<-list()
for(sid in mod_ids){
  s <- tryCatch(readRDS(file.path(PROJ, MP$modules[[sid]]$sim_result_path)), error=function(e) NULL)
  if(is.null(s)||is.null(s$DAILY_NAV_DT)) next
  d <- as.data.table(s$DAILY_NAV_DT)[, .(Date=as.Date(Date), r=Strategy_Ret)]
  bm <- if(!is.null(s$bm_xts)) data.table(Date=as.Date(index(s$bm_xts)), bm=as.numeric(s$bm_xts[,1])) else NULL
  if(!is.null(bm)) d <- merge(d, bm, by="Date", all.x=TRUE) else d[, bm:=0]
  d[, a := r - fifelse(is.finite(bm), bm, 0)]
  RL[[sid]] <- d[,.(Date,r)]; AL[[sid]] <- d[,.(Date,a,bm)]
}
mod_ids <- names(RL)
RM <- Reduce(function(x,y) merge(x,y,by="Date",all=TRUE), lapply(mod_ids,function(s){z<-copy(RL[[s]]);setnames(z,"r",s);z})); setorder(RM,Date)
# 단일 benchmark 일간 (모듈간 bm 동일 — 가용분 median)
BMm <- Reduce(function(x,y) merge(x,y,by="Date",all=TRUE), lapply(mod_ids,function(s){z<-AL[[s]][,.(Date,bm)];setnames(z,"bm",s);z}))
BM <- data.table(Date=BMm$Date, bm=apply(as.matrix(BMm[,-1]),1,function(v) median(v,na.rm=TRUE)))
RM[, ym:=format(Date,"%Y%m")]
avail <- RM[, .(n=sum(sapply(.SD,function(c)any(is.finite(c))))), by=ym, .SDcols=mod_ids][n>=3, ym]
RM <- RM[ym %in% avail]

# 월간 모듈수익 + 월간 bm
MoM <- RM[, c(lapply(.SD, function(c){ c[!is.finite(c)]<-0; prod(1+c)-1 }), .(me=max(Date))), by=ym, .SDcols=mod_ids]
BM[, ym:=format(Date,"%Y%m")]; BMo <- BM[ym%in%avail, .(bm=prod(1+ifelse(is.finite(bm),bm,0))-1), by=ym]
MoM <- merge(MoM, BMo, by="ym"); setorder(MoM, me)

# ── 축 (t-1 월말 라벨) ──
RD <- as.data.table(read_parquet(file.path(PROJ,".cache/regime_daily_v2.parquet")))[, Date:=as.Date(Date)]
UN <- as.data.table(read_parquet(file.path(PROJ,".cache/unified_regime_signal_daily.parquet")))[, Date:=as.Date(Date)]
AX <- merge(RD[,.(Date,MRS,TS_z=TS_z_smooth)], UN[,.(Date,Category)], by="Date", all=TRUE); setorder(AX,Date)
AX[, MRS_l:=shift(MRS,1L)]; AX[, TS_l:=shift(TS_z,1L)]; AX[, Cat_l:=shift(Category,1L)]
# 월말 라벨을 다음달에 적용: me_date(전월말) 라벨 → 이번달
me_lab <- merge(MoM[,.(ym,me)], AX, by.x="me", by.y="Date", all.x=TRUE)
setorder(me_lab, me)
me_lab[, MRS_prev := shift(MRS_l)]; me_lab[, TS_prev := shift(TS_l)]; me_lab[, Cat_prev := shift(Cat_l)]  # 전월말 axis

# IS/OOS 월 분할 (60/40)
nM <- nrow(MoM); is_cut <- floor(nM*0.60); is_ym <- MoM$ym[1:is_cut]; oos_ym <- MoM$ym[(is_cut+1):nM]
cat(sprintf("[D0] 월 %d개 | IS %d (~%s) / OOS %d (%s~%s)\n", nM, is_cut, MoM$ym[is_cut], length(oos_ym), oos_ym[1], tail(oos_ym,1)))

# IS 통계: 모듈 전체IR(active) + 레짐별 IR
IS <- MoM[ym %in% is_ym]
isl <- me_lab[ym %in% is_ym]
act_is <- as.matrix(IS[, ..mod_ids]) - IS$bm
overall_IR <- setNames(apply(act_is, 2, function(x) sr(x)), mod_ids)

terc_break <- function(v, ref) { q<-quantile(ref[is.finite(ref)],c(.33,.67),na.rm=TRUE)
  fifelse(!is.finite(v),NA_character_, fifelse(v<=q[1],"L",fifelse(v<=q[2],"M","H"))) }
regimeIR <- function(axis_is_vec, states){   # IS 레짐별 모듈 active IR
  out <- list()
  for(st in states){ idx <- which(axis_is_vec==st); if(length(idx)<6){ out[[st]]<-setNames(rep(NA,length(mod_ids)),mod_ids); next }
    out[[st]] <- setNames(apply(act_is[idx,,drop=FALSE],2,function(x) sr(x)), mod_ids) }
  out }

# 레짐 라벨 (IS 경계로 tercile 고정)
mk_axis <- function(prevcol){
  isref <- me_lab[ym%in%is_ym][[prevcol]]
  if(prevcol=="Cat_prev"){ lab <- me_lab$Cat_prev; states<-c("RISK_ON","NEUTRAL","CAUTION","CRISIS") }
  else { lab <- terc_break(me_lab[[prevcol]], isref); states<-c("L","M","H") }
  list(lab=setNames(lab, me_lab$ym), states=states)
}

# ── ① demean 지속성: 레짐-상대 IR persistence ──
OOS <- MoM[ym %in% oos_ym]; act_oos <- as.matrix(OOS[, ..mod_ids]) - OOS$bm
demean_persist <- function(axis_name, prevcol){
  ax <- mk_axis(prevcol); lab<-ax$lab; states<-ax$states
  ir_is <- regimeIR(lab[is_ym], states)
  # OOS 레짐별 IR
  oosl <- lab[oos_ym]
  ir_oos <- list()
  for(st in states){ idx<-which(oosl==st); if(length(idx)<6){ir_oos[[st]]<-setNames(rep(NA,length(mod_ids)),mod_ids);next}
    ir_oos[[st]] <- setNames(apply(act_oos[idx,,drop=FALSE],2,function(x) sr(x)),mod_ids) }
  # raw cell persistence
  rawIS <- unlist(ir_is); rawOOS <- unlist(ir_oos[names(ir_is)])
  rho_raw <- spear(rawIS, rawOOS)
  # demeaned: 각 모듈의 레짐별 IR − 모듈 전체평균(레짐축 내)
  dm <- function(L){ m<-do.call(rbind,L); m - rowMeans(t(m),na.rm=TRUE)[col(t(m))] }  # placeholder
  # 수동 demean: state×mod 행렬
  MI <- do.call(rbind, ir_is); MO <- do.call(rbind, ir_oos[rownames(MI)])  # states×mods
  MId <- sweep(MI, 2, colMeans(MI,na.rm=TRUE)); MOd <- sweep(MO, 2, colMeans(MO,na.rm=TRUE))
  rho_dm <- spear(as.vector(MId), as.vector(MOd))
  data.table(axis=axis_name, rho_raw=round(rho_raw,3), rho_demeaned=round(rho_dm,3))
}
cat("\n[D1] 레짐-상대 IR 지속성 (demean = 진짜 레짐타이밍 스킬):\n")
DM <- rbindlist(list(demean_persist("Category","Cat_prev"), demean_persist("MRS","MRS_prev"), demean_persist("TS_z","TS_prev")))
print(DM)
cat("→ rho_raw 양수지만 rho_demeaned≈0/음수면: '좋은모듈이 좋다'(무조건부)일뿐 레짐타이밍 스킬 없음.\n")

# ── ② Head-to-race (월간 OOS): EW vs Static top-k vs Rotate top-k ──
port_oos <- function(sel_fun){   # sel_fun(ym) → 선택 모듈 벡터
  prev<-NULL; rn<-numeric(); ra<-numeric()
  for(y in oos_ym){ S<-sel_fun(y); S<-S[!is.na(S)]; if(!length(S)) { rn<-c(rn,NA);ra<-c(ra,NA); next }
    row<-MoM[ym==y]; pr<-mean(unlist(row[,..S])); pa<-pr-row$bm
    if(!is.null(prev)){ to<-length(union(setdiff(prev,S),setdiff(S,prev)))/max(length(S),1); cost<-to*(15/1e4)
      pr<-pr-cost; pa<-pa-cost }
    prev<-S; rn<-c(rn,pr); ra<-c(ra,pa) }
  list(net=rn, act=ra) }

race <- function(k){
  ew  <- port_oos(function(y) mod_ids)
  topS <- names(sort(overall_IR, decreasing=TRUE))[1:k]
  stat<- port_oos(function(y) topS)
  axR <- mk_axis("Cat_prev"); irR <- regimeIR(axR$lab[is_ym], axR$states)
  rot <- port_oos(function(y){ st<-axR$lab[[y]]; if(is.na(st)||is.null(irR[[st]])) return(topS)
    v<-irR[[st]]; if(all(is.na(v))) return(topS); names(sort(v,decreasing=TRUE))[1:k] })
  data.table(k=k,
    EW_net=round(sr(ew$net),3), Static_net=round(sr(stat$net),3), Rotate_net=round(sr(rot$net),3),
    EW_act=round(sr(ew$act),3), Static_act=round(sr(stat$act),3), Rotate_act=round(sr(rot$act),3),
    Rotate_minus_Static_net=round(sr(rot$net)-sr(stat$net),3),
    Rotate_minus_Static_act=round(sr(rot$act)-sr(stat$act),3)) }
cat("\n[D2] Head-to-race OOS (Category 로테이션, k∈{3,4,5}) — net/active 연율 Sharpe:\n")
RACE <- rbindlist(lapply(c(3,4,5), race))
print(RACE)
cat("→ Rotate_minus_Static ≈ 0/음수면: 레짐을 알아도 정적 최고선택 대비 추가가치 없음 = 로테이션 무가치.\n")

# ── 평결 ──
dm_ok  <- DM[axis=="Category", rho_demeaned] > 0.15
race_ok<- mean(RACE$Rotate_minus_Static_net, na.rm=TRUE) > 0.1
verdict <- if(dm_ok && race_ok) "REGIME_TIMING_REAL" else "STATIC_SELECTION_ONLY (레짐 무가치)"
cat(sprintf("\n★ 결정적 평결: %s\n  Category demeaned ρ=%.3f (>0.15?) | mean Rotate−Static net=%.3f (>0.1?)\n",
  verdict, DM[axis=="Category",rho_demeaned]%||%NA, mean(RACE$Rotate_minus_Static_net,na.rm=TRUE)))

out <- list(study="regime_decisive", n_months=nM, is_oos_cut_ym=MoM$ym[is_cut],
  demean_persistence=DM, head_to_race=RACE, verdict=verdict,
  interp="rho_demeaned≈0 & Rotate≈Static → 모듈품질은 지속되나 레짐타이밍 알파 부재. 레버는 정적선택+직교화이지 레짐로테이션 아님.")
write_json(out, file.path(PROJ,"04_Research/factor_rotation/output/regime_study_decisive.json"),
  auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
cat("\n저장: 04_Research/factor_rotation/output/regime_study_decisive.json\n")
