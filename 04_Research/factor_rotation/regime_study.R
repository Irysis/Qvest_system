#!/usr/bin/env Rscript
# =============================================================================
# regime_study.R — Factor Rotation Mode: 국면 분석 스터디 (진단 전용, 비-deploy).
# 목적: FR_001 OOS_retention=0.022 붕괴의 근본원인을 3축으로 정식 진단.
#   PART A — 레짐 신호 특성(상태분포/지속/월간 전환/PIT). "신호가 노이즈인가?"
#   PART B — 모듈×레짐 판별력(IS): 레짐별 모듈 IR dispersion + 랭킹. "모듈이 갈리는가?"
#   PART C — OOS 지속성(핵심): IS 레짐별 모듈랭킹이 OOS에 남는가 (Spearman + top-k lift).
#            "갈려도 OOS에 남는가?"  ← 0.022의 정체.
#   PART D — 구조 천장: 12모듈 평균 상관 + EW 대비 로테이션 엣지 분해.
#   PART E — 평결: 생존 축 유무 → rotate / orthogonalize / abandon.
# PIT: 축 t-1 lag, IS/OOS 분할시 tercile 경계는 IS-only로 산출 후 전구간 적용(룩어헤드 無).
#      실측-only (모듈 sim_result NAV, 자체합성 없음).
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(xts) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")); setwd(PROJ)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
ANN <- 252
sr  <- function(r){ r<-r[is.finite(r)]; if(length(r)<20||sd(r)==0) return(NA_real_); mean(r)/sd(r)*sqrt(ANN) }
spear <- function(a,b){ ok<-is.finite(a)&is.finite(b); if(sum(ok)<4) return(NA_real_); suppressWarnings(cor(a[ok],b[ok],method="spearman")) }
sec <- function(t) cat(sprintf("\n\n========== %s ==========\n", t))

# ── 0. 모듈 일간 수익 + active(=ret-bm) 로드 ─────────────────────────────────
MP <- fromJSON(file.path(PROJ,"06_Registry/module_performance.json"), simplifyVector=FALSE)
mod_ids <- names(MP$modules)
RL <- list(); AL <- list()
for(sid in mod_ids){
  s <- tryCatch(readRDS(file.path(PROJ, MP$modules[[sid]]$sim_result_path)), error=function(e) NULL)
  if(is.null(s)||is.null(s$DAILY_NAV_DT)) next
  d <- as.data.table(s$DAILY_NAV_DT)[, .(Date=as.Date(Date), r=Strategy_Ret)]
  bm <- if(!is.null(s$bm_xts)) data.table(Date=as.Date(index(s$bm_xts)), bm=as.numeric(s$bm_xts[,1])) else NULL
  if(!is.null(bm)) d <- merge(d, bm, by="Date", all.x=TRUE) else d[, bm:=0]
  d[, a := r - fifelse(is.finite(bm), bm, 0)]
  RL[[sid]] <- d[, .(Date, r)]; AL[[sid]] <- d[, .(Date, a)]
}
mod_ids <- names(RL)
RM <- Reduce(function(x,y) merge(x,y,by="Date",all=TRUE), lapply(mod_ids,function(s){z<-copy(RL[[s]]);setnames(z,"r",s);z}))
RA <- Reduce(function(x,y) merge(x,y,by="Date",all=TRUE), lapply(mod_ids,function(s){z<-copy(AL[[s]]);setnames(z,"a",s);z}))
setorder(RM,Date); setorder(RA,Date)
RM[, ym:=format(Date,"%Y%m")]; RA[, ym:=format(Date,"%Y%m")]
# 월별 ≥3 모듈 가용 구간만
avail <- RM[, .(n=sum(sapply(.SD,function(c)any(is.finite(c))))), by=ym, .SDcols=mod_ids][n>=3, ym]
RM <- RM[ym %in% avail]; RA <- RA[ym %in% avail]
cat(sprintf("[0] 모듈 %d개 | 일간 %d행 | %s..%s | 월 %d개\n",
  length(mod_ids), nrow(RA), as.character(min(RA$Date)), as.character(max(RA$Date)), uniqueN(RA$ym)))

# ── 축 로드 (t-1 lag) ────────────────────────────────────────────────────────
RD <- as.data.table(read_parquet(file.path(PROJ,".cache/regime_daily_v2.parquet")))[, Date:=as.Date(Date)]
UN <- as.data.table(read_parquet(file.path(PROJ,".cache/unified_regime_signal_daily.parquet")))[, Date:=as.Date(Date)]
MS <- as.data.table(read_parquet(file.path(PROJ,".cache/msm_daily_latest.parquet")))[, Date:=as.Date(Date)]
AX <- merge(RD[, .(Date, MRS, VIX_z=VIX_z_smooth, TS_z=TS_z_smooth)],
            UN[, .(Date, KTRI=KTRI_Score, VEA=VEA_Score, Category)], by="Date", all=TRUE)
AX <- merge(AX, MS[, .(Date, CrisisP=Crisis_Prob)], by="Date", all=TRUE); setorder(AX, Date)
cont_axes <- c("MRS","VIX_z","TS_z","CrisisP","KTRI","VEA")
for(a in c(cont_axes)) AX[, (paste0(a,"_lag")) := shift(get(a),1L)]
AX[, Cat_lag := shift(Category,1L)]

# tercile 라벨 생성기: IS 구간(idx_is) 분포로 경계 산출 후 전구간 적용 (PIT-safe split)
mk_terc_fixed <- function(v, is_mask){
  q <- quantile(v[is_mask & is.finite(v)], c(.33,.67), na.rm=TRUE)
  if(any(is.na(q))||q[1]>=q[2]) return(rep(NA_character_, length(v)))
  fifelse(!is.finite(v), NA_character_, fifelse(v<=q[1],"L", fifelse(v<=q[2],"M","H")))
}

# 공통 IS/OOS 분할 (시간순 60/40, 일간 기준)
dord <- RA$Date; nb <- length(dord); cut_date <- dord[floor(nb*0.60)]
cat(sprintf("[0] IS/OOS 경계: %s (IS %d일 / OOS %d일)\n", as.character(cut_date), sum(dord<=cut_date), sum(dord>cut_date)))

# =============================================================================
sec("PART A — 레짐 신호 특성 (신호가 노이즈인가)")
# Category: 상태분포 + 일간/월간 전환 + 지속
DC <- merge(RA[,.(Date,ym)], AX[,.(Date,Cat_lag)], by="Date")[!is.na(Cat_lag)]
setorder(DC,Date)
cat("\n[A1] Category 상태분포 (분석구간 내, t-1 lag):\n")
print(DC[, .(n_days=.N, pct=round(100*.N/nrow(DC),1)), by=Cat_lag][order(-n_days)])
DC[, pc := shift(Cat_lag)]
cat(sprintf("\n[A2] Category 일간 전환율: %.1f%% (평균 지속 %.0f일)\n",
  100*DC[!is.na(pc)&Cat_lag!=pc,.N]/DC[!is.na(pc),.N], DC[!is.na(pc),.N]/max(1,DC[!is.na(pc)&Cat_lag!=pc,.N])))
# 월말 라벨 월간 지속 (월간 리밸 관점 — 핵심)
me <- DC[, .(d=max(Date)), by=ym]; mlab <- merge(me, DC[,.(Date,Cat_lag)], by.x="d", by.y="Date")
setorder(mlab, d); mlab[, pl := shift(Cat_lag)]
cat(sprintf("[A3] Category 월말→다음월말 전환율: %.1f%%  → 월간 리밸시 직전국면이 이번달과 다를 확률\n",
  100*mlab[!is.na(pl)&Cat_lag!=pl,.N]/mlab[!is.na(pl),.N]))

# 연속축: 커버리지 + 월간 tercile 지속
cat("\n[A4] 연속축 커버리지 + 월간 tercile 라벨 지속성:\n")
covtab <- list()
for(a in cont_axes){
  col <- paste0(a,"_lag"); v <- AX[[col]]
  cov_pct <- 100*mean(is.finite(v))
  # 월말값 tercile(expanding 간이: 전구간 분포) → 월간 전환
  mev <- merge(me, AX[,c("Date",col),with=FALSE], by.x="d", by.y="Date")
  mev[, lab := mk_terc_fixed(get(col), rep(TRUE,.N))]; setorder(mev,d); mev[, pl:=shift(lab)]
  mtrans <- 100*mev[!is.na(pl)&!is.na(lab)&lab!=pl,.N]/max(1,mev[!is.na(pl)&!is.na(lab),.N])
  covtab[[a]] <- data.table(axis=a, coverage_pct=round(cov_pct,1), monthly_terc_transition_pct=round(mtrans,1),
                            usable=(cov_pct>=80))
}
print(rbindlist(covtab))
cat("→ 해석: 커버리지<80% 축은 부분구간 한정. 월간전환율 높을수록 신호 churn(월간 로테이션 부적합).\n")

# =============================================================================
sec("PART B — 모듈×레짐 판별력 (IS 전구간, 모듈이 갈리는가)")
# 정의별 일간 레짐 라벨 → 레짐별 모듈 active-IR → dispersion + best
axis_defs <- list(Category = AX[,.(Date,lab=Cat_lag)])
for(a in cont_axes){ col<-paste0(a,"_lag")
  axis_defs[[a]] <- AX[, .(Date, lab=mk_terc_fixed(get(col), rep(TRUE,.N)))] }

disc <- list()
for(nm in names(axis_defs)){
  lab <- merge(RA[,c("Date",mod_ids),with=FALSE], axis_defs[[nm]], by="Date")[!is.na(lab)]
  states <- lab[, .N, by=lab][N>=250, lab]   # 최소 ~1년
  rows <- list()
  for(st in states){
    irs <- sapply(mod_ids, function(s) sr(lab[lab==st][[s]]))
    rows[[st]] <- data.table(axis=nm, regime=st, n_days=lab[lab==st,.N],
      ir_dispersion=round(sd(irs,na.rm=TRUE),3), ir_best=round(max(irs,na.rm=TRUE),3),
      ir_worst=round(min(irs,na.rm=TRUE),3), best_mod=mod_ids[which.max(irs)])
  }
  disc[[nm]] <- rbindlist(rows)
}
DISC <- rbindlist(disc)
cat("\n[B1] 레짐별 모듈 active-IR dispersion (높을수록 모듈이 레짐 안에서 갈림):\n")
print(DISC[, .(axis,regime,n_days,ir_disp=ir_dispersion,ir_best,ir_worst,best_mod)])
cat(sprintf("\n[B2] 축별 평균 dispersion (모듈을 가장 잘 가르는 축):\n"))
print(DISC[, .(mean_ir_disp=round(mean(ir_dispersion,na.rm=TRUE),3), n_states=.N), by=axis][order(-mean_ir_disp)])

# =============================================================================
sec("PART C — OOS 지속성 [핵심] (IS 레짐별 모듈랭킹이 OOS에 남는가)")
is_mask_d <- AX$Date <= cut_date
persist <- list(); celldat <- list()
for(nm in names(axis_defs)){
  # IS-only tercile 경계로 라벨 재생성 (연속축), Category는 그대로
  if(nm=="Category"){ labA <- AX[,.(Date,lab=Cat_lag)] } else {
    col <- paste0(nm,"_lag"); labA <- AX[, .(Date, lab=mk_terc_fixed(get(col), is_mask_d))] }
  M <- merge(RA[,c("Date",mod_ids),with=FALSE], labA, by="Date")[!is.na(lab)]
  M[, seg := fifelse(Date<=cut_date,"IS","OOS")]
  states <- intersect(M[seg=="IS",.N,by=lab][N>=20,lab], M[seg=="OOS",.N,by=lab][N>=20,lab])
  rc <- c(); lifts <- c()
  for(st in states){
    is_ir  <- sapply(mod_ids, function(s) sr(M[seg=="IS" & lab==st][[s]]))
    oos_ir <- sapply(mod_ids, function(s) sr(M[seg=="OOS"& lab==st][[s]]))
    rho <- spear(is_ir, oos_ir); rc <- c(rc, rho)
    # top-3 by IS_IR → OOS active-IR vs EW(전모듈) OOS active-IR
    top3 <- mod_ids[order(-is_ir)][1:3]
    oos_top <- mean(oos_ir[top3], na.rm=TRUE); oos_ew <- mean(oos_ir, na.rm=TRUE)
    lifts <- c(lifts, oos_top - oos_ew)
    celldat[[paste(nm,st)]] <- data.table(axis=nm, regime=st, is_ir=is_ir, oos_ir=oos_ir, mod=mod_ids)
  }
  persist[[nm]] <- data.table(axis=nm, n_states=length(states),
    mean_rank_corr_IS_OOS=round(mean(rc,na.rm=TRUE),3),
    mean_top3_OOS_lift=round(mean(lifts,na.rm=TRUE),3))
}
PERS <- rbindlist(persist)[order(-mean_rank_corr_IS_OOS)]
cat("\n[C1] 축별 IS→OOS 모듈랭킹 Spearman + top3 OOS lift (핵심표):\n")
print(PERS)
# 풀링: 모든 (축,레짐) 셀의 IS_IR vs OOS_IR 한방 상관 (헤드라인 1수치)
CELL <- rbindlist(celldat)
pooled_rho <- spear(CELL$is_ir, CELL$oos_ir)
cat(sprintf("\n[C2] ★헤드라인★ 전체 (축×레짐×모듈) 셀 IS_IR vs OOS_IR Spearman = %.3f  (n=%d 셀)\n",
  pooled_rho, sum(is.finite(CELL$is_ir)&is.finite(CELL$oos_ir))))
cat("→ 0 근처/음수면: 레짐별 '어느 모듈이 잘하는지'가 OOS에 안 남음 = 로테이션 OOS 엣지 부재 (0.022 정체).\n")

# =============================================================================
sec("PART D — 구조 천장 (모듈 상관 + EW 대비 엣지)")
CM <- cor(as.matrix(RM[, ..mod_ids]), use="pairwise.complete.obs")
offdiag <- CM[upper.tri(CM)]
cat(sprintf("\n[D1] 12모듈 일간수익 평균 페어와이즈 상관 = %.3f (min %.2f / max %.2f)\n",
  mean(offdiag,na.rm=TRUE), min(offdiag,na.rm=TRUE), max(offdiag,na.rm=TRUE)))
CMa <- cor(as.matrix(RA[, ..mod_ids]), use="pairwise.complete.obs"); od2 <- CMa[upper.tri(CMa)]
cat(sprintf("[D2] 12모듈 active(초과)수익 평균 상관 = %.3f → 초과수익 직교성 정도\n", mean(od2,na.rm=TRUE)))
cat("→ 수익 상관 높을수록 로테이션이 만들 수 있는 분산효과/직교 활성수익 천장이 낮음.\n")

# =============================================================================
sec("PART E — 평결")
viable <- PERS[mean_rank_corr_IS_OOS>0.2 & mean_top3_OOS_lift>0]
cat(sprintf("\n생존 축(rank_corr>0.2 & top3_lift>0): %s\n",
  if(nrow(viable)) paste(viable$axis,collapse=", ") else "없음"))
cat(sprintf("헤드라인 OOS 셀 상관: %.3f | 모듈 active 평균상관: %.3f | Category 월간전환: %.1f%%\n",
  pooled_rho, mean(od2,na.rm=TRUE),
  100*mlab[!is.na(pl)&Cat_lag!=pl,.N]/mlab[!is.na(pl),.N]))
verdict <- if(nrow(viable)==0 && (is.na(pooled_rho)||pooled_rho<0.2)) "ABANDON_OR_ORTHOGONALIZE" else "VIABLE_AXIS_FOUND"
cat(sprintf("\n★ 평결: %s\n", verdict))

# ── 저장 ─────────────────────────────────────────────────────────────────────
out <- list(schema_version="v1.0", study="regime_analysis", generated_for="FR OOS_retention 0.022 진단",
  n_modules=length(mod_ids), date_range=c(as.character(min(RA$Date)),as.character(max(RA$Date))),
  is_oos_cut=as.character(cut_date),
  partA_category_monthly_transition_pct=round(100*mlab[!is.na(pl)&Cat_lag!=pl,.N]/mlab[!is.na(pl),.N],1),
  partA_axis_coverage=rbindlist(covtab),
  partB_axis_dispersion=DISC[, .(mean_ir_disp=round(mean(ir_dispersion,na.rm=TRUE),3)), by=axis][order(-mean_ir_disp)],
  partC_persistence=PERS, partC_pooled_rho=round(pooled_rho,3),
  partD_module_ret_corr=round(mean(offdiag,na.rm=TRUE),3), partD_module_active_corr=round(mean(od2,na.rm=TRUE),3),
  verdict=verdict)
dir.create(file.path(PROJ,"04_Research/factor_rotation/output"), showWarnings=FALSE, recursive=TRUE)
write_json(out, file.path(PROJ,"04_Research/factor_rotation/output/regime_study.json"),
  auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
cat("\n저장: 04_Research/factor_rotation/output/regime_study.json\n")
