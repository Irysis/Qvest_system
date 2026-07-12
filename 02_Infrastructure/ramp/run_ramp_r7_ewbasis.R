## run_ramp_r7_ewbasis.R — RAMP R7: 선별 라벨 basis 교체(cap-w→EW-uni) + R6 최선 dual-basis 재분류
## ─────────────────────────────────────────────────────────────────────────────
## 도훈 지시 2026-07-12 "그럼 R6부터". FQ-015. R6 잔존 frontier ②(데이터 게이트 없는 쪽) 발화.
##
## [E1 — 선별 라벨 basis 교체 (본 실험, trial 4)]
##   R6 P-pure와 정확 대칭 구조(semiannual 선별·top-K EW 로테이션·102 배포권 패널)에서
##   trailing 선별 라벨만 교체: cap-w active NW-t(R6) → EW-유니버스 active NW-t(E1).
##     EW active_f,t = ret_net_f,t(팩터 top-25 net) − ew_t(K200∪KQ150 유니버스 EW 평균 수익)
##   가설: cap-w 라벨은 mega-cap 레짐 드리프트(벤치-구성 미스매치)에 오염돼 팩터 횡단효능 순위를 왜곡 —
##     EW 라벨이 순위 노이즈를 줄이면 cap-w 최종 성과까지 개선될 수 있다(그 경우만 자본 관점 실익).
##   config 4: {창 36/60} × {K 10/20}. 판정=cap-w authoritative(HARD 3종+2017+ 분리)+EW-uni 진단 병기.
##   paired NW-t: E1 vs cap-w-repro(동일 창·K, 동일 Jul-12 vintage 재계산) = 라벨 교체 순수 효과.
##
## [E2 — R6 최선(Ppure_W36_K20=cap-w 선별) dual-basis·cap-tier 재분류 (characterization, trial 아님)]
##   ① EW-uni PORT_t + EW-basis oos_retention v2(3분할 중앙값) + EW-basis calmar
##   ② 보유 cap-tier 분해(MEGA/MID/OTHER 비중 시계열 + tier 기여, canonical diag_cap_tier + size_dt)
##   ③ post-2017 EW-basis 재판독 — 감쇠가 cap-w 아티팩트인지 EW서도 실재인지.
##   프레임: EW-real(EW-uni≥2.95 ∧ EW-oos≥0.7 근접)이면 자본 졸업 아니라 "벤치-상대 배포성 결정(D3형)" 재료.
##
## [KILL 사전등록] (A) 4 config 전부 paired(E1 vs capw-repro) < 2.0 (cap-w 개선 부재)
##                 AND (B) EW-real 후보(EW-uni≥2.95 ∧ EW-oos≥0.7) 부재 → "라벨 basis 축 소진".
## [정직 prior] R6: realized-PORT_t 기질 교체=RAMP 최강 선별 레버이나 post-2017 substrate decay 전이 벽 binding.
##             cap-w 트랩(알파=벤치-저비중 tier 국소화, memory project-captier-alpha-localization).
## [측정] cap-w authoritative(R6 gates() 복제) + HARD 3종 + 2017+ 분리 + DSR(family n_trials=20). 실측-only.
## [vintage] 패널=R6 frozen(Jul-11) 재사용(선별 substrate). 게이트=현 rawdata(Jul-12, April-gap 백필 후) —
##   E1 arm+capw-repro arm 동일 Jul-12 vintage로 재계산 → paired 내부정합. pin drift 정량화·기록.
## 단일스레드 · arrow io=2(io=1 HANG 회피, R6 실측). n_trials family=20(R4 4+R5 6+R6 6+R7 4).
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest); library(digest); library(jsonlite); library(e1071)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=QM); setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns
source("02_Infrastructure/contracts/canonical_screen_bt.R")
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a
fmtn <- function(x){ if(is.null(x)||length(x)==0||all(is.na(x))) "NA" else sprintf("%+.2f", as.numeric(x[1])) }
OUT <- "outputs/ramp"; RUNTAG <- "20260712"
logf <- file.path(".cache", sprintf("_ramp_r7_%s.txt", RUNTAG))
con <- file(logf,"w",encoding="UTF-8"); w<-function(...){ writeLines(paste0(...),con); flush(con) }; wf<-function(...){w(sprintf(...))}

## ── 사전등록 config (hash 고정 — 측정 전 동결) ──
WINDOWS <- c(36L, 60L)
KPOOL   <- c(10L, 20L)
CADENCE <- 6L
TOP_N   <- 25L; COST_BPS <- 15; LIQ_MIN <- 2e8
GATE_PT <- 2.95; GATE_OOS <- 0.7; GATE_CAL <- 0.64
N_TRIALS_R7 <- length(WINDOWS)*length(KPOOL)          # 4 (E1만; E2=characterization 비-trial)
N_TRIALS_FAMILY <- 4L + 6L + 6L + N_TRIALS_R7          # 20 = R4 4 + R5 6 + R6 6 + R7 4
PAIRED_KILL <- 2.0
EW_REAL_PT <- 2.95; EW_REAL_OOS <- 0.7                 # EW-real(D3형) 문턱
PREREG <- list(mode="RAMP", round="R7",
  mechanism="selection_label_basis_swap: trailing cap-w active NW-t -> EW-universe active NW-t (E1) + R6-best dual-basis/cap-tier reclass (E2)",
  revival_signal_of="R6 잔존 frontier ②: PORT_t-정렬 선별 × EW-basis (project-selection-discipline-arc-r4r5r6)",
  substrate="R6 frozen panel r6_factor_deployzone_active.parquet (102 factors x 256 months: ret_net/benchmark_ret/active_bm)",
  e1=list(design="R6 P-pure와 정확 대칭, trailing 선별 라벨만 EW-uni active로 교체",
          ew_active_def="ret_net(factor top-25 net) - ew(universe EW mean return, K200∪KQ150)",
          arms="Epure_EW_W{36,60}_K{10,20}", controls="capw-repro (동일 창/K, R6 cap-w 선별 Jul-12 재계산)",
          paired="E1(EW-sel) vs capw-repro(cap-w-sel) 동일 vintage; secondary: E1 vs R6-stored Ppure"),
  e2=list(target="R6 best Ppure_W36_K20 (cap-w 선별)", diag=c("EW-uni PORT_t","EW-basis oos_retention v2","EW-basis calmar","cap-tier MEGA/MID/OTHER 분해","post-2017 EW 재판독"),
          frame="EW-real이면 자본 졸업 아님 — 벤치-상대 배포성 결정(D3형) 재료. cap-w 게이트 authoritative 불변"),
  windows=WINDOWS, kpool=KPOOL, cadence_months=CADENCE, top_n=TOP_N, cost_bps_oneway=COST_BPS, liq_min=LIQ_MIN,
  gate_hard=c(port_t_capwt=GATE_PT, oos_retention=GATE_OOS, calmar=GATE_CAL, dsr=0.5),
  n_trials_r7=N_TRIALS_R7, n_trials_family=N_TRIALS_FAMILY, paired_kill_threshold=PAIRED_KILL,
  kill_rule="(A) all 4 paired(E1 vs capw-repro) < 2.0 AND (B) no EW-real (EW-uni PORT_t>=2.95 AND EW-oos>=0.7) -> label-basis axis exhausted",
  selection="trailing window realized active NW-t(lag3) -> top-K pool (PIT trailing-only). E1 uses EW-uni active, R6/capw-repro uses cap-w active",
  selection_type="sweep",
  pit="panel active = current-month score->realized fwd (PIT-safe); selection trailing-only last W months realized by decision date",
  honest_prior="R6: realized-PORT_t 기질=RAMP 최강 선별 레버이나 post-2017 substrate decay 전이 벽 binding + cap-w 트랩(알파=벤치-저비중 tier 국소화)",
  vintage_pin="panel frozen r6_20260711 (선별 substrate) + gate rawdata 20260712 (April-gap 백필 후). E1/capw-repro 동일 Jul-12 재계산 → paired 내부정합; pin drift 정량 기록",
  as_of_date="2026-07-12", source_version="RAMP_R7_v1",
  security_id="Ticker (rawdata) -> factor_id z (pure_factor_scores.z=Z_Score_Aligned)")
CFG_HASH <- substr(digest::digest(PREREG, algo="sha256"), 1, 16)
PREREG$config_hash <- CFG_HASH
PREREG$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
jsonlite::write_json(PREREG, file.path(OUT, sprintf("r7_ewbasis_prereg_%s.json", RUNTAG)), auto_unbox=TRUE, pretty=TRUE, digits=6)
wf("=== RAMP R7: EW-basis 선별 라벨 교체 (E1) + R6-best dual-basis 재분류 (E2) ===")
wf("config_hash=%s | windows={%s} K={%s} cadence=%dm | n_trials R7=%d family=%d | KILL: (A)paired<%.1f AND (B)no EW-real",
   CFG_HASH, paste(WINDOWS,collapse=","), paste(KPOOL,collapse=","), CADENCE, N_TRIALS_R7, N_TRIALS_FAMILY, PAIRED_KILL)

## ── 데이터 (R6 패턴) ──
af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
APPROVED <- af[status=="approved", factor_id]
g <- as.data.table(read_parquet(file.path(OUT,"factor_group_scores.parquet")))
g[, signal_date := as.Date(signal_date)]
sig_dates <- sort(unique(g$signal_date)); n_sig <- length(sig_dates); post2017 <- as.Date("2017-01-01")

.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
.udates <- sort(unique(rawdata$Date))
.me <- as.Date(vapply(sig_dates, function(d){ v <- .udates[.udates <= d]; if(length(v)) as.character(max(v)) else NA_character_ }, character(1)))
size_map <- data.table(me=.me, signal_date=sig_dates)[!is.na(me)]
rawdata <- rawdata[Date %in% .me[!is.na(.me)]]
## E2 size_dt (Date=signal_date, Size at decision month-end .me) — BM cap-weight와 동일 시점 Size
size_dt <- merge(rawdata[, .(me=Date, Ticker, Size)], size_map, by="me")[!is.na(Size), .(Date=signal_date, Ticker, Size)]
fwd <- build_monthly_forward_returns(rawdata, sig_dates); rm(rawdata)
RET_DT   <- fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)]
BENCH_DT <- fwd$bench_dt[,.(Date=as.Date(Date), BM_Ret)]
LIQ_DT   <- fwd$liq_dt[,.(Date=as.Date(Date), Ticker, adv)]
ewb <- fwd$returns_dt[, .(ew=mean(Ret_1m,na.rm=TRUE)), by=.(date=as.Date(Date))]        # 유니버스 EW 평균 수익 (Jul-12 vintage)
EWB_SD <- fwd$returns_dt[, .(ew=mean(Ret_1m,na.rm=TRUE)), by=.(signal_date=as.Date(Date))]

sc <- as.data.table(read_parquet(file.path(OUT,"pure_factor_scores.parquet"), col_select=c("signal_date","security_id","factor_id","z")))
sc <- sc[factor_id %in% APPROVED]; sc[, signal_date := as.Date(signal_date)]
POOL_FACS <- sort(intersect(APPROVED, unique(sc$factor_id)))
ret <- RET_DT[,.(signal_date=Date, security_id=Ticker, Ret_1m)]

## ── 게이트 계산기 (R6 gates() 복제; cap-w authoritative + EW-uni 진단 pt) ──
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA); mean(x)/sd(x)*sqrt(12) }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA); m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
oos_v2 <- function(active_bm){  # anchored 3분할 {55/65/75} 중앙값 (essence_score oos v2 개념)
  .splits<-c(0.55,0.65,0.75); n<-length(active_bm)
  .rets<-sapply(.splits,function(fr){ k<-floor(n*fr); if(k<12||(n-k)<6) return(NA_real_)
    .is<-srf(active_bm[1:k]); .oo<-srf(active_bm[(k+1):n]); if(!is.na(.is)&&.is>0) .oo/.is else NA_real_ })
  median(.rets, na.rm=TRUE) }
gates <- function(score_dt, lab, n_trials_dsr=N_TRIALS_FAMILY, diag=FALSE, size_panel=NULL){
  cs <- tryCatch(canonical_screen_bt(
        score_dt[,.(Date=as.Date(signal_date), Ticker=security_id, score)],
        RET_DT, BENCH_DT, top_n=TOP_N, cost_bps_oneway=COST_BPS,
        liq_dt=LIQ_DT, liq_min=LIQ_MIN, run_id="r7", strategy_id=lab,
        diag_dual_basis=diag, size_dt=size_panel), error=function(e){ w("  [gates ERR ",lab,"] ",conditionMessage(e)); NULL })
  if(is.null(cs) || is.null(cs$period_returns)) return(NULL)
  pr <- as.data.table(cs$period_returns); pr[,date:=as.Date(date)]
  pr <- merge(pr, ewb, by="date", all.x=TRUE)
  pr[, act := ret_net - ew]; pr[, act_bm := ret_net - benchmark_ret]
  pt <- nwt(pr$act); pt_bm <- nwt(pr$act_bm)                                # pt=EW-uni 진단, pt_bm=cap-w authoritative
  nav <- cumprod(1+pr$ret_net); dd <- min(nav/cummax(nav)-1); ann <- prod(1+pr$ret_net)^(12/nrow(pr))-1
  cal <- if(dd<0) ann/abs(dd) else NA                                       # cap-w calmar (net nav)
  retn <- oos_v2(pr$act_bm)                                                 # cap-w oos_retention v2
  sr_m <- mean(pr$act_bm)/sd(pr$act_bm); nn <- nrow(pr)
  sk <- tryCatch(e1071::skewness(pr$act_bm),error=function(e)0); ku <- tryCatch(e1071::kurtosis(pr$act_bm)+3,error=function(e)3)
  den <- sqrt((1-sk*sr_m+(ku-1)/4*sr_m^2)/(nn-1)); dsr_raw <- if(den>1e-10) sr_m/den else NA
  dsr <- if(!is.na(dsr_raw)) dsr_raw - n_trials_dsr*0.05 else NA
  post_sr <- srf(pr[date>=post2017, act_bm]); full_bm_sr <- srf(pr$act_bm)
  ## EW-basis 게이트 (진단 병기): EW active(pr$act) 기준 oos/calmar/post17
  ew_oos <- oos_v2(pr$act); ew_post_sr <- srf(pr[date>=post2017, act])
  navp <- cumprod(1+pr$ret_net)  # nav 동일(port net) — EW calmar은 EW active 기준 별도
  # EW calmar: EW active wealth 기반 낙폭(진단)
  ewnav <- cumprod(1+pr$act); ewdd <- min(ewnav/cummax(ewnav)-1); ewann <- prod(1+pr$act)^(12/nrow(pr))-1
  ew_cal <- if(ewdd<0) ewann/abs(ewdd) else NA
  list(dt=data.table(model=lab, port_t_EWuni=pt, port_t_capwt=pt_bm, oos_retention=retn, calmar=cal,
             dsr=dsr, post2017_bm_sr=post_sr, full_bm_sr=full_bm_sr,
             ew_oos_retention=ew_oos, ew_calmar=ew_cal, ew_post2017_sr=ew_post_sr,
             turnover=cs$turnover_annual, n_months=nrow(pr)),
       pr=pr[,.(date, act, act_bm, ret_net, benchmark_ret)], cs=cs)
}

## ════════════════ 패널 로드 (frozen) + EW active 재구성 ════════════════
PANEL <- as.data.table(read_parquet(file.path(OUT,"r6_factor_deployzone_active.parquet"))); PANEL[, signal_date := as.Date(signal_date)]
PANEL <- merge(PANEL, EWB_SD, by="signal_date", all.x=TRUE)
PANEL[, active_ew := ret_net - ew]
PANEL_FACS <- sort(unique(PANEL$factor_id))
Pw_capw <- dcast(PANEL, signal_date ~ factor_id, value.var="active_bm"); setorder(Pw_capw, signal_date)
Pw_ew   <- dcast(PANEL, signal_date ~ factor_id, value.var="active_ew"); setorder(Pw_ew, signal_date)
panel_dates <- Pw_capw$signal_date; n_pm <- length(panel_dates)
Pmat_capw <- as.matrix(Pw_capw[, ..PANEL_FACS]); rownames(Pmat_capw) <- as.character(panel_dates)
Pmat_ew   <- as.matrix(Pw_ew[,   ..PANEL_FACS]); rownames(Pmat_ew)   <- as.character(panel_dates)
stopifnot(all(panel_dates == sig_dates[1:n_pm]))
wf("panel: %d factors x %d months %s~%s | sig months=%d", length(PANEL_FACS), n_pm,
   as.character(panel_dates[1]), as.character(panel_dates[n_pm]), n_sig)

## ── vintage pin drift: 현 cap-w BM (Jul-12) vs 패널 benchmark_ret (Jul-11) ──
bm_panel <- PANEL[, .(bm_panel=benchmark_ret[1]), by=signal_date]
bm_cmp <- merge(BENCH_DT[,.(signal_date=Date, bm_new=BM_Ret)], bm_panel, by="signal_date")
vintage_bm_drift_max <- max(abs(bm_cmp$bm_new - bm_cmp$bm_panel), na.rm=TRUE)
vintage_bm_drift_n_nonzero <- sum(abs(bm_cmp$bm_new - bm_cmp$bm_panel) > 1e-9, na.rm=TRUE)
vintage_drift_months <- as.character(bm_cmp[abs(bm_new-bm_panel)>1e-6, signal_date])
wf("\n[vintage pin] cap-w BM Jul-12 vs 패널(Jul-11) benchmark_ret: max|Δ|=%.2e | nonzero months=%d/%d | >1e-6: %s",
   vintage_bm_drift_max, vintage_bm_drift_n_nonzero, nrow(bm_cmp),
   if(length(vintage_drift_months)) paste(vintage_drift_months,collapse=",") else "none")

## ── single-factor parity (task 의무): V02_EP 재구성 vs R6 fac_full port_t_full ──
pf_chk <- "V02_EP"; if(!(pf_chk %in% PANEL_FACS)) pf_chk <- PANEL_FACS[1]
sf <- PANEL[factor_id==pf_chk]
sf_capw_t <- nwt(sf$active_bm); sf_ew_t <- nwt(sf$active_ew)
r6_pf_ref <- tryCatch({ r6s <- fromJSON(file.path(OUT,"r6_portt_boruta_summary_20260711.json"))
  d <- as.data.table(r6s$per_factor_deployzone_top12); v <- d[factor_id==pf_chk, port_t_full]; if(length(v)) v[1] else NA_real_ }, error=function(e) NA_real_)
wf("[parity 1-factor] %s: 재구성 cap-w PORT_t_full=%+.4f (R6 fac_full=%s Δ=%.2e) | 재구성 EW-uni PORT_t_full=%+.4f",
   pf_chk, sf_capw_t, ifelse(is.na(r6_pf_ref),"NA",sprintf("%+.4f",r6_pf_ref)),
   ifelse(is.na(r6_pf_ref),NA,abs(sf_capw_t-r6_pf_ref)), sf_ew_t)

## ════════════════ trailing 선별 (cap-w=R6 재현, EW=E1) ════════════════
trailing_nwt <- function(Pmat, W, a_idx){
  lo <- a_idx - W; hi <- a_idx - 1L; if(lo < 1L) return(NULL)
  sub <- Pmat[lo:hi, , drop=FALSE]
  apply(sub, 2, function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
    m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) })
}
build_sel_traj <- function(Pmat){
  st <- list()
  for(W in WINDOWS){
    anchors <- seq(W+1L, n_sig-1L, by=CADENCE); tj <- list()
    for(a in anchors){ if(a-1L > n_pm) next
      tv <- trailing_nwt(Pmat, W, a); if(is.null(tv)) next
      ord <- names(sort(tv[is.finite(tv)], decreasing=TRUE))
      tj[[as.character(a)]] <- list(anchor_idx=a, trailing_t=tv, ranked=ord,
        pool=setNames(lapply(KPOOL, function(k) head(ord, k)), paste0("K",KPOOL))) }
    st[[as.character(W)]] <- list(anchors=anchors, traj=tj)
  }; st }
sel_capw <- build_sel_traj(Pmat_capw)   # = R6 P-pure 선별 재현
sel_ew   <- build_sel_traj(Pmat_ew)     # = E1 EW-basis 선별

## ── cap-w 선별 재현 확인: R6 sel_traj 캐시와 pool 일치 ──
sel_repro_ok <- NA; sel_repro_note <- "R6 sel cache 부재"
r6selc <- ".cache/_ramp_r6_sel_20260711.rds"
if(file.exists(r6selc)){
  r6sel <- readRDS(r6selc)
  mism <- 0L; tot <- 0L
  for(W in WINDOWS){ for(a_ch in names(sel_capw[[as.character(W)]]$traj)){
    p_new <- sel_capw[[as.character(W)]]$traj[[a_ch]]$pool[["K20"]]
    p_r6  <- tryCatch(r6sel[[as.character(W)]]$traj[[a_ch]]$pool[["K20"]], error=function(e) NULL)
    if(!is.null(p_r6)){ tot<-tot+1L; if(!identical(sort(p_new),sort(p_r6))) mism<-mism+1L } } }
  sel_repro_ok <- (tot>0 && mism==0L); sel_repro_note <- sprintf("K20 anchors 비교 %d개, 불일치 %d", tot, mism)
}
wf("[sel repro] cap-w 선별 vs R6 캐시: ok=%s (%s)", sel_repro_ok, sel_repro_note)

## ── EW vs cap-w 선별 차이 진단 (라벨 교체가 실제 다른 팩터를 고르나) ──
fam_of <- function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V") "Value" else if(p1=="M"&&p!="MA") "Momentum" else if(p1=="Q") "Quality"
  else if(p1=="D") "LowRisk" else if(p1=="L") "Size_Liquidity" else if(p1=="S"&&p!="SE") "Size_Liquidity"
  else if(p1=="R") "Reversal" else if(p=="GR") "Growth_Profit" else if(p=="AC") "Accruals"
  else if(p1=="C"&&p!="CR") "Consensus" else if(p=="CR") "Credit" else if(p=="IN") "Growth_Profit"
  else if(p=="XF") "Composite" else if(p=="MA") "Macro" else if(p1=="T") "Size_Liquidity" else "Composite" }
FAC_FAM <- setNames(sapply(PANEL_FACS, fam_of), PANEL_FACS)
sel_overlap <- list()
for(W in WINDOWS){ jac<-c(); keys<-intersect(names(sel_capw[[as.character(W)]]$traj), names(sel_ew[[as.character(W)]]$traj))
  for(a_ch in keys){ a<-sel_capw[[as.character(W)]]$traj[[a_ch]]$pool[["K20"]]; b<-sel_ew[[as.character(W)]]$traj[[a_ch]]$pool[["K20"]]
    jac<-c(jac, length(intersect(a,b))/length(union(a,b))) }
  vf_capw <- table(unlist(lapply(sel_capw[[as.character(W)]]$traj, function(x) FAC_FAM[x$pool[["K20"]]])))
  vf_ew   <- table(unlist(lapply(sel_ew[[as.character(W)]]$traj,   function(x) FAC_FAM[x$pool[["K20"]]])))
  sel_overlap[[as.character(W)]] <- list(W=W, k20_jaccard_mean=mean(jac,na.rm=TRUE),
    value_share_capw=round(as.numeric(vf_capw["Value"])/sum(vf_capw),3),
    value_share_ew=round(as.numeric(vf_ew["Value"])/sum(vf_ew),3))
  wf("  [sel diff W=%d] K20 Jaccard(cap-w∩EW)=%.2f | Value share cap-w=%.2f EW=%.2f", W,
     mean(jac,na.rm=TRUE), as.numeric(vf_capw["Value"])/sum(vf_capw), as.numeric(vf_ew["Value"])/sum(vf_ew))
}

## ── arm 빌더 (composite -> top-25) ──
fw <- dcast(sc, signal_date + security_id ~ factor_id, value.var="z")
FW_FACS <- intersect(POOL_FACS, names(fw))
fw_z <- fw[, c("signal_date","security_id", FW_FACS), with=FALSE]; setkey(fw_z, signal_date)
build_arm_score <- function(sel, W, k){
  anchors <- sel[[as.character(W)]]$anchors; deploy_idx <- (W+1L):(n_sig-1L); rows <- list()
  for(i in deploy_idx){
    ga <- max(anchors[anchors <= i]); facs <- intersect(sel[[as.character(W)]]$traj[[as.character(ga)]]$pool[[paste0("K",k)]], FW_FACS)
    if(length(facs)==0) next
    sub <- fw_z[.(sig_dates[i])]; if(nrow(sub)==0) next
    Xz <- sub[, lapply(.SD, zc), .SDcols=facs]; Xm <- as.matrix(Xz); Xm[is.na(Xm)] <- 0
    rows[[as.character(i)]] <- data.table(signal_date=sig_dates[i], security_id=sub$security_id, score=rowMeans(Xm))
  }
  s <- rbindlist(rows); s[, score := zc(score), by=signal_date]; s
}

## ════════════════ 측정: capw-repro (baseline) + E1 EW arms ════════════════
wf("\n=== 측정: capw-repro(R6 재현) + E1 EW-basis arms (cap-w authoritative) ===")
RES <- list(); PR <- list()
for(W in WINDOWS) for(k in KPOOL){
  lab <- sprintf("capwrepro_W%d_K%d", W, k); gg <- gates(build_arm_score(sel_capw, W, k), lab)
  if(!is.null(gg)){ RES[[lab]]<-gg$dt; PR[[lab]]<-gg$pr }
  wf("  [%s] capwt=%+.2f EWuni=%+.2f oos=%+.2f calmar=%+.2f DSR=%+.2f | EWoos=%+.2f EWpost17=%+.2f", lab,
     gg$dt$port_t_capwt, gg$dt$port_t_EWuni, gg$dt$oos_retention, gg$dt$calmar, gg$dt$dsr, gg$dt$ew_oos_retention, gg$dt$ew_post2017_sr)
}
for(W in WINDOWS) for(k in KPOOL){
  lab <- sprintf("Epure_EW_W%d_K%d", W, k); gg <- gates(build_arm_score(sel_ew, W, k), lab)
  if(!is.null(gg)){ RES[[lab]]<-gg$dt; PR[[lab]]<-gg$pr }
  wf("  [%s] capwt=%+.2f EWuni=%+.2f oos=%+.2f calmar=%+.2f DSR=%+.2f | EWoos=%+.2f EWpost17=%+.2f", lab,
     gg$dt$port_t_capwt, gg$dt$port_t_EWuni, gg$dt$oos_retention, gg$dt$calmar, gg$dt$dsr, gg$dt$ew_oos_retention, gg$dt$ew_post2017_sr)
}
saveRDS(list(RES=RES, PR=PR), file.path(".cache", sprintf("_ramp_r7_mid_%s.rds", RUNTAG)))
TAB <- rbindlist(RES, fill=TRUE)

## ── arm-level parity: capwrepro_W36_K20 vs R6-stored ──
r6_ref <- tryCatch(fromJSON(file.path(OUT,"r6_portt_boruta_summary_20260711.json")), error=function(e) NULL)
pin_capwt_delta <- pin_ewuni_delta <- NA
if(!is.null(r6_ref)){ rr <- as.data.table(r6_ref$results); r6pp <- rr[model=="Ppure_W36_K20"]
  cw <- TAB[model=="capwrepro_W36_K20"]
  if(nrow(r6pp) && nrow(cw)){ pin_capwt_delta <- abs(cw$port_t_capwt - r6pp$port_t_capwt); pin_ewuni_delta <- abs(cw$port_t_EWuni - r6pp$port_t_EWuni)
    wf("\n[arm parity] capwrepro_W36_K20 vs R6 Ppure_W36_K20: capwt %+.4f vs %+.4f (Δ=%.3f) | EWuni %+.4f vs %+.4f (Δ=%.3f)",
       cw$port_t_capwt, r6pp$port_t_capwt, pin_capwt_delta, cw$port_t_EWuni, r6pp$port_t_EWuni, pin_ewuni_delta) }
}

## ── paired NW-t: E1 vs capw-repro (동일 vintage) + secondary vs R6-stored ──
pair1 <- function(PRa, PRb, la, lb, kind){
  if(is.null(PRa) || is.null(PRb)) return(NULL)
  m <- merge(PRa[,.(date,a=act_bm)], PRb[,.(date,b=act_bm)], by="date")
  d <- m$a - m$b; data.table(model=la, base=lb, kind=kind, mean_diff_ann=mean(d,na.rm=TRUE)*12, paired_t=nwt(d), n=nrow(m))
}
r6_PR <- tryCatch(readRDS(".cache/_ramp_r6_20260711.rds")$PR, error=function(e) NULL)
paired <- list()
wf("\n=== paired NW-t (lag3) ===")
for(W in WINDOWS) for(k in KPOOL){
  la <- sprintf("Epure_EW_W%d_K%d",W,k); lb <- sprintf("capwrepro_W%d_K%d",W,k)
  p <- pair1(PR[[la]], PR[[lb]], la, lb, "labelswap_vs_capwrepro"); if(!is.null(p)){ paired[[length(paired)+1]]<-p
    wf("  [라벨교체]   %-18s vs %-18s Δ(ann)=%+.4f paired_t=%+.2f (n=%d)", p$model, p$base, p$mean_diff_ann, p$paired_t, p$n) }
  if(!is.null(r6_PR)){ r6lab <- sprintf("Ppure_W%d_K%d",W,k)
    p2 <- pair1(PR[[la]], r6_PR[[r6lab]], la, paste0("R6:",r6lab), "labelswap_vs_R6stored"); if(!is.null(p2)){ paired[[length(paired)+1]]<-p2
      wf("  [vs R6저장]  %-18s vs %-18s Δ(ann)=%+.4f paired_t=%+.2f (n=%d)", p2$model, p2$base, p2$mean_diff_ann, p2$paired_t, p2$n) } }
}
PAIRED <- rbindlist(paired, fill=TRUE)

## ── KILL 판정 (사전등록) ──
E1_TAB <- TAB[grepl("^Epure_EW_", model)]
maxp_labelswap <- if(nrow(PAIRED)) max(PAIRED[kind=="labelswap_vs_capwrepro", paired_t], na.rm=TRUE) else NA
condA_all_lt2 <- !(is.finite(maxp_labelswap) && maxp_labelswap >= PAIRED_KILL)     # (A) 모든 paired < 2.0
ew_real_tab <- E1_TAB[is.finite(port_t_EWuni) & port_t_EWuni>=EW_REAL_PT & is.finite(ew_oos_retention) & ew_oos_retention>=EW_REAL_OOS]
condB_no_ewreal <- (nrow(ew_real_tab)==0)                                          # (B) EW-real 부재
KILL_axis <- condA_all_lt2 && condB_no_ewreal
any_grad_capw <- any(is.finite(E1_TAB$port_t_capwt) & E1_TAB$port_t_capwt>=GATE_PT &
                     is.finite(E1_TAB$oos_retention) & E1_TAB$oos_retention>=GATE_OOS &
                     is.finite(E1_TAB$calmar) & E1_TAB$calmar>=GATE_CAL)
wf("\n=== KILL gate (사전등록) ===")
wf("  (A) max paired (E1 라벨교체 vs capw-repro) = %+.2f -> all<2.0 = %s", maxp_labelswap, condA_all_lt2)
wf("  (B) EW-real 후보(EW-uni>=%.2f AND EW-oos>=%.2f) 수 = %d -> none = %s", EW_REAL_PT, EW_REAL_OOS, nrow(ew_real_tab), condB_no_ewreal)
wf("  graduation (E1 cap-w HARD 3종 통과) = %s", any_grad_capw)
wf("  => KILL(라벨 basis 축 소진) = %s", KILL_axis)

wf("\n=== HARD 게이트 (capwt>=2.95 / oos>=0.7 / calmar>=0.64 / DSR>=0.5, family n_trials=%d) — E1 arms ===", N_TRIALS_FAMILY)
for(i in seq_len(nrow(E1_TAB))){ r<-E1_TAB[i]
  p<-c(capwt=isTRUE(r$port_t_capwt>=2.95), oos=isTRUE(r$oos_retention>=0.7), cal=isTRUE(r$calmar>=0.64), dsr=isTRUE(r$dsr>=0.5))
  wf("  [%-18s] %s -> %s", r$model, paste(names(p),ifelse(p,"✓","✗"),collapse=" "), ifelse(all(p),"★GRADUATION","미달")) }

## ════════════════ E2: R6 best Ppure_W36_K20 dual-basis + cap-tier 재분류 ════════════════
wf("\n=== E2: R6 best (capwrepro_W36_K20 = cap-w 선별) dual-basis + cap-tier 재분류 ===")
e2_score <- build_arm_score(sel_capw, 36L, 20L)
e2 <- gates(e2_score, "E2_capwrepro_W36_K20_DIAG", diag=TRUE, size_panel=size_dt)
E2 <- NULL
if(!is.null(e2)){
  cs <- e2$cs; dew <- cs$diag_ew_universe; dct <- cs$diag_cap_tier
  e2dt <- e2$dt
  wf("  cap-w authoritative: capwt=%+.2f oos=%+.2f calmar=%+.2f DSR=%+.2f post17=%+.2f", e2dt$port_t_capwt, e2dt$oos_retention, e2dt$calmar, e2dt$dsr, e2dt$post2017_bm_sr)
  wf("  EW-basis(gates): EWuni_t=%+.2f EW_oos=%+.2f EW_calmar=%+.2f EW_post17_sr=%+.2f", e2dt$port_t_EWuni, e2dt$ew_oos_retention, e2dt$ew_calmar, e2dt$ew_post2017_sr)
  if(!is.null(dew)) wf("  EW-uni(canonical diag): PORT_t=%s IR=%s net_sr=%s oos_approx=%s post2017_t=%s n17=%s",
    fmtn(dew$portfolio_alpha_t_nw_lag3), fmtn(dew$information_ratio), fmtn(dew$net_sr), fmtn(dew$oos_retention_approx), fmtn(dew$post2017_t_nw_lag3), dew$n_months_post2017 %||% NA)
  if(!is.null(dct) && isTRUE(dct$available)){
    ws <- dct$weight_share_avg; cg <- dct$contrib_gross_annualized
    wf("  cap-tier 비중(평균): MEGA=%.3f MID=%.3f OTHER=%.3f UNRANKED=%.3f", ws$MEGA, ws$MID, ws$OTHER, ws$UNRANKED)
    wf("  cap-tier 연기여(gross): MEGA=%+.3f MID=%+.3f OTHER=%+.3f UNRANKED=%+.3f", cg$MEGA, cg$MID, cg$OTHER, cg$UNRANKED)
  } else wf("  cap-tier: 미가용 (%s)", if(!is.null(dct)) (dct$note %||% dct$error %||% "?") else "?")
  ## EW-real 판정 (E2)
  ew_pt <- if(!is.null(dew)) dew$portfolio_alpha_t_nw_lag3 else e2dt$port_t_EWuni
  ew_oos <- e2dt$ew_oos_retention
  e2_ewreal <- isTRUE(ew_pt>=EW_REAL_PT) && isTRUE(ew_oos>=EW_REAL_OOS)
  e2_ewreal_near <- isTRUE(ew_pt>=EW_REAL_PT) && isTRUE(ew_oos>=0.5)
  wf("  => E2 EW-real(EW-uni>=%.2f ∧ EW-oos>=%.2f)=%s | near(oos>=0.5)=%s", EW_REAL_PT, EW_REAL_OOS, e2_ewreal, e2_ewreal_near)
  E2 <- list(cap_w=as.list(e2dt), diag_ew_universe=dew,
    cap_tier=list(weight_share_avg=if(!is.null(dct)) dct$weight_share_avg else NULL,
                  contrib_gross_annualized=if(!is.null(dct)) dct$contrib_gross_annualized else NULL,
                  by_month=if(!is.null(dct) && isTRUE(dct$available)) dct$by_month else NULL),
    ew_real=e2_ewreal, ew_real_near=e2_ewreal_near,
    frame="EW-real이면 자본 졸업 아님 — 벤치-상대 배포성 결정(D3형) 재료. cap-w authoritative HARD 3종이 자본 게이트")
}

## ── 저장 ──
res <- list(prereg=PREREG, config_hash=CFG_HASH,
  meta=list(as_of_date="2026-07-12", generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
            source_version="RAMP_R7_v1", security_id="Ticker->factor_id z (pure_factor_scores.z=Z_Score_Aligned)"),
  results=TAB, paired=PAIRED, e2=E2,
  vintage=list(bm_drift_max=vintage_bm_drift_max, bm_drift_n_nonzero=vintage_bm_drift_n_nonzero, drift_months=vintage_drift_months,
               pin_capwt_delta=pin_capwt_delta, pin_ewuni_delta=pin_ewuni_delta,
               sel_repro_ok=sel_repro_ok, sel_repro_note=sel_repro_note),
  parity_1factor=list(factor=pf_chk, recon_capw_t=sf_capw_t, r6_ref=r6_pf_ref,
                      delta=if(is.na(r6_pf_ref)) NA else abs(sf_capw_t-r6_pf_ref), recon_ew_t=sf_ew_t),
  sel_overlap=sel_overlap,
  kill=list(condA_all_paired_lt2=condA_all_lt2, max_paired_labelswap=maxp_labelswap,
            condB_no_ewreal=condB_no_ewreal, n_ewreal=nrow(ew_real_tab), KILL_axis=KILL_axis, any_graduation_capw=any_grad_capw),
  n_trials_r7=N_TRIALS_R7, n_trials_family=N_TRIALS_FAMILY, n_sig=n_sig, date_range=as.character(range(sig_dates)),
  r6_ref=list(best_ppure="Ppure_W36_K20", pt_capwt=2.6124, pt_EWuni=3.9191, oos=-0.0759, calmar=0.45, max_paired_trait=2.2534),
  families=sort(unique(FAC_FAM)), n_pool_factors=length(POOL_FACS), incumbent_book_ir=1.416)
saveRDS(list(res=res, PR=PR, TAB=TAB, PAIRED=PAIRED, E2=E2, e2_cs=if(!is.null(e2)) e2$cs else NULL), file.path(".cache", sprintf("_ramp_r7_%s.rds", RUNTAG)))
write_parquet(TAB, file.path(OUT, sprintf("r7_ewbasis_gates_%s.parquet", RUNTAG)))
if(nrow(PAIRED)) write_parquet(PAIRED, file.path(OUT, sprintf("r7_ewbasis_paired_%s.parquet", RUNTAG)))
if(!is.null(E2) && !is.null(E2$cap_tier$by_month)) write_parquet(as.data.table(E2$cap_tier$by_month), file.path(OUT, sprintf("r7_ewbasis_e2_captier_bymonth_%s.parquet", RUNTAG)))
jsonlite::write_json(res, file.path(OUT, sprintf("r7_ewbasis_summary_%s.json", RUNTAG)), auto_unbox=TRUE, pretty=TRUE, digits=4)
## E2 재분류 별도 요약
e2out <- list(meta=res$meta, target="capwrepro_W36_K20 (=R6 Ppure_W36_K20 cap-w 선별)", e2=E2,
              cap_w_authoritative=if(!is.null(E2)) E2$cap_w else NULL,
              interpretation=if(!is.null(E2) && isTRUE(E2$ew_real)) "EW-real → D3형 벤치-상대 배포성 결정 재료 (자본 졸업 아님)" else "EW-basis서도 미달 → null 종결 (cap-w authoritative HARD 미달과 정합)")
jsonlite::write_json(e2out, file.path(OUT, sprintf("r7_ewbasis_e2_reclass_%s.json", RUNTAG)), auto_unbox=TRUE, pretty=TRUE, digits=4)

wf("\n=== VERDICT ===")
bp <- E1_TAB[which.max(port_t_capwt)]
wf("  best E1: %s capwt=%+.2f EWuni=%+.2f oos=%+.2f calmar=%+.2f | max paired(vs capw-repro)=%+.2f", bp$model, bp$port_t_capwt, bp$port_t_EWuni, bp$oos_retention, bp$calmar, maxp_labelswap)
wf("  KILL_axis=%s (condA all<2.0=%s, condB no EW-real=%s) | graduation=%s", KILL_axis, condA_all_lt2, condB_no_ewreal, any_grad_capw)
wf("  E2 EW-real=%s | vintage bm_drift_max=%.2e sel_repro_ok=%s pin_capwt_Δ=%s", if(!is.null(E2)) E2$ew_real else NA, vintage_bm_drift_max, sel_repro_ok, ifelse(is.na(pin_capwt_delta),"NA",sprintf("%.3f",pin_capwt_delta)))
close(con)
cat(sprintf("R7_DONE. KILL_axis=%s graduation=%s maxp_labelswap=%.2f E2_ewreal=%s sel_repro=%s pin_capwtΔ=%s bm_drift=%.2e log=%s\n",
   KILL_axis, any_grad_capw, maxp_labelswap, if(!is.null(E2)) E2$ew_real else NA, sel_repro_ok,
   ifelse(is.na(pin_capwt_delta),"NA",sprintf("%.3f",pin_capwt_delta)), vintage_bm_drift_max, logf))
cat(readLines(logf), sep="\n")
