## run_ramp_r6_portt_boruta.R — RAMP R6: trailing PORT_t 상위 기질 선별 + Boruta arm P
## ─────────────────────────────────────────────────────────────────────────────
## 도훈 mandate 2026-07-11: "PORT_t 상위 팩터들로 보루타 다시 돌려봐". FQ-014.
##
## [부활신호] R5(selection_summary) 명시: "선별 기준을 relevance→realized-PORT_t로 교체" = frontier crack.
##   R4/R5는 relevance-objective(RF importance/LASSO stab/mRMR MI) 선별 → 전멸(계열 폐쇄).
##   R6 novelty 축 = 선별 규율이 아니라 **기질/라벨을 배포권 실현 성과(top-25 net-active PORT_t)로 교체**.
##
## [설계] Step1 배포권 패널(102 승인팩터 각 top-25 EW long-only net15bps active, PIT-안전 당월-only) →
##   Step2 trailing 창(36/60m) realized active NW-t(lag3)로 top-K 풀 선별(PIT: trailing-only) →
##   Step3 arm 구조:
##     P-pure  = top-K 풀 EW 로테이션(무-Boruta)            → "PORT_t-정렬 선별 자체" 효과
##     P-boruta= 같은 풀 내 Boruta(RF+shadow) confirmed → 로테이션 → Boruta 한계 기여
##     controls(비-trial): base_all11_EW(R4/R5 substrate) + ctrl_all102_EW(선별無 substrate)
##   paired NW-t: P-pure vs base_all11(기질 교체) · P-pure vs ctrl_all102(선별 격리) · P-boruta vs P-pure(Boruta)
##
## [KILL 사전등록] 전 config P-pure vs base < 2.0 AND P-boruta vs P-pure < 2.0 → PORT_t-정렬 축도 소진.
## [정직 prior] trailing 실현성과 선별 = 팩터 모멘텀 계열 → factor-of-factors momentum timing NULL(06-30).
## [측정] cap-w authoritative(R4 gates() 복제) + HARD 3종 + 2017+ 분리 + DSR(family n_trials=16). 실측-only.
## 단일스레드 · vintage: R4/R5 세션 pin. [최적화] 키드 subset + slim Boruta table + P-pure先/Boruta後 + flush/checkpoint.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest); library(Boruta); library(digest); library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns
source("02_Infrastructure/contracts/canonical_screen_bt.R")
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }
OUT <- "outputs/ramp"; RUNTAG <- "20260711"
logf <- file.path(".cache", sprintf("_ramp_r6_%s.txt", RUNTAG))
con <- file(logf,"w",encoding="UTF-8"); w<-function(...){ writeLines(paste0(...),con); flush(con) }; wf<-function(...){w(sprintf(...))}

## ── 사전등록 config (hash 고정 — 이전 실행과 byte-identical: 재등록 아님) ──
BORUTA <- list(nmax=3000L, ntree=100L, maxRuns=40L, imp="RfZ_default", decide="Confirmed_only", seed_base=6000L)
WINDOWS <- c(36L, 60L)
KPOOL   <- c(10L, 20L)
BORUTA_KPOOL <- c(20L)
CADENCE <- 6L
TOP_N   <- 25L; COST_BPS <- 15; LIQ_MIN <- 2e8
GATE_PT <- 2.95
N_TRIALS_R6 <- length(WINDOWS)*length(KPOOL) + length(WINDOWS)*length(BORUTA_KPOOL)  # 6
N_TRIALS_FAMILY <- 4L + 6L + N_TRIALS_R6   # 16
PAIRED_KILL <- 2.0
PREREG <- list(mode="RAMP", round="R6",
               mechanism="trailing_realized_PORTt_pool_selection + Boruta_within_pool",
               revival_signal_of="R5 selection_summary: relevance->realized-PORT_t (frontier crack)",
               substrate="102 approved factors (Z_Score_Aligned) per-factor top-25 EW long-only net-active panel",
               panel="outputs/ramp/r6_factor_deployzone_active.parquet (102 factors x ~256 months cap-w active)",
               selection="trailing window realized active NW-t(lag3) -> top-K pool (PIT trailing-only)",
               arms=list(P_pure="top-K pool EW rotation", P_boruta="Boruta RF+shadow confirmed within pool"),
               controls=list(base_all11="R4/R5 11-family EW composite (pin-checked)",
                             ctrl_all102="all-102 individual EW composite (no selection)"),
               boruta=BORUTA, windows=WINDOWS, kpool=KPOOL, boruta_kpool=BORUTA_KPOOL,
               cadence_months=CADENCE, top_n=TOP_N, cost_bps_oneway=COST_BPS, liq_min=LIQ_MIN,
               gate_hard=c(port_t_capwt=GATE_PT, oos_retention=0.7, calmar=0.64, dsr=0.5),
               n_trials_r6=N_TRIALS_R6, n_trials_family=N_TRIALS_FAMILY,
               paired_kill_threshold=PAIRED_KILL, selection_type="sweep",
               target_boruta="within-month z-scored forward 1M return (cross-sectional)",
               pit="panel active = current-month score->realized fwd (PIT-safe); selection trailing-only last W months realized by decision date",
               honest_prior="trailing realized-perf selection = factor momentum; factor-of-factors momentum timing NULL (memory project-factor-of-factors-scoping 06-30)",
               vintage_pin="r4r5_session_20260711 (rawdata current + pure_factor_scores 06-18 z; provenance parity max|d|=0 vs load_month_factors)",
               as_of_date="2026-07-11", source_version="RAMP_R6_v1",
               security_id="Ticker (rawdata) -> factor_id z (pure_factor_scores.z=Z_Score_Aligned)")
CFG_HASH <- substr(digest::digest(PREREG, algo="sha256"), 1, 16)
PREREG$config_hash <- CFG_HASH
PREREG$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
jsonlite::write_json(PREREG, file.path(OUT, sprintf("r6_portt_boruta_prereg_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=6)

## ── 데이터 ──
af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
APPROVED <- af[status=="approved", factor_id]
fam_of <- function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V") "Value" else if(p1=="M"&&p!="MA") "Momentum" else if(p1=="Q") "Quality"
  else if(p1=="D") "LowRisk" else if(p1=="L") "Size_Liquidity" else if(p1=="S"&&p!="SE") "Size_Liquidity"
  else if(p1=="R") "Reversal" else if(p=="GR") "Growth_Profit" else if(p=="AC") "Accruals"
  else if(p1=="C"&&p!="CR") "Consensus" else if(p=="CR") "Credit" else if(p=="IN") "Growth_Profit"
  else if(p=="XF") "Composite" else if(p=="MA") "Macro" else if(p1=="T") "Size_Liquidity" else "Composite" }
FAC_FAM <- setNames(sapply(APPROVED, fam_of), APPROVED)

g <- as.data.table(read_parquet(file.path(OUT,"factor_group_scores.parquet")))
g[, signal_date := as.Date(signal_date)]
FAMS <- sort(unique(g$family))
gw <- dcast(g, signal_date + security_id ~ family, value.var="group_z")
sig_dates <- sort(unique(gw$signal_date)); n_sig <- length(sig_dates)

.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
.udates <- sort(unique(rawdata$Date))
.me <- as.Date(vapply(sig_dates, function(d){ v <- .udates[.udates <= d]
  if(length(v)) as.character(max(v)) else NA_character_ }, character(1)))
rawdata <- rawdata[Date %in% .me[!is.na(.me)]]
fwd <- build_monthly_forward_returns(rawdata, sig_dates); rm(rawdata)
ret <- fwd$returns_dt[,.(signal_date=as.Date(Date), security_id=Ticker, Ret_1m)]
post2017 <- as.Date("2017-01-01")
ewb <- fwd$returns_dt[, .(ew=mean(Ret_1m,na.rm=TRUE)), by=.(date=as.Date(Date))]
RET_DT   <- fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)]
BENCH_DT <- fwd$bench_dt[,.(Date=as.Date(Date), BM_Ret)]
LIQ_DT   <- fwd$liq_dt[,.(Date=as.Date(Date), Ticker, adv)]

sc <- as.data.table(read_parquet(file.path(OUT,"pure_factor_scores.parquet"),
        col_select=c("signal_date","security_id","factor_id","z")))
sc <- sc[factor_id %in% APPROVED]; sc[, signal_date := as.Date(signal_date)]
POOL_FACS <- sort(intersect(APPROVED, unique(sc$factor_id)))

wf("=== RAMP R6: trailing PORT_t 선별 + Boruta arm P ===")
wf("config_hash=%s | windows={%s} K={%s} boruta_K={%s} cadence=%dm | n_trials R6=%d family=%d",
   CFG_HASH, paste(WINDOWS,collapse=","), paste(KPOOL,collapse=","), paste(BORUTA_KPOOL,collapse=","),
   CADENCE, N_TRIALS_R6, N_TRIALS_FAMILY)
wf("pool: %d approved factors | %d families | %d sig months %s~%s",
   length(POOL_FACS), length(FAMS), n_sig, as.character(sig_dates[1]), as.character(sig_dates[n_sig]))

## ── 게이트 계산기 (R4 gates() 복제; cap-w authoritative) ──
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA); mean(x)/sd(x)*sqrt(12) }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
gates <- function(score_dt, lab, n_trials_dsr=N_TRIALS_FAMILY){
  cs <- tryCatch(canonical_screen_bt(
        score_dt[,.(Date=as.Date(signal_date), Ticker=security_id, score)],
        RET_DT, BENCH_DT, top_n=TOP_N, cost_bps_oneway=COST_BPS,
        liq_dt=LIQ_DT, liq_min=LIQ_MIN, run_id="r6", strategy_id=lab,
        diag_dual_basis=FALSE), error=function(e){ w("  [gates ERR ",lab,"] ",conditionMessage(e)); NULL })
  if(is.null(cs) || is.null(cs$period_returns)) return(NULL)
  pr <- as.data.table(cs$period_returns); pr[,date:=as.Date(date)]
  pr <- merge(pr, ewb, by="date", all.x=TRUE)
  pr[, act := ret_net - ew]; pr[, act_bm := ret_net - benchmark_ret]
  pt <- nwt(pr$act); pt_bm <- nwt(pr$act_bm)
  nav <- cumprod(1+pr$ret_net); dd <- min(nav/cummax(nav)-1); ann <- prod(1+pr$ret_net)^(12/nrow(pr))-1
  cal <- if(dd<0) ann/abs(dd) else NA
  .splits<-c(0.55,0.65,0.75); .rets<-sapply(.splits,function(fr){ k<-floor(nrow(pr)*fr)
    if(k<12||(nrow(pr)-k)<6) return(NA_real_); .is<-srf(pr$act_bm[1:k]); .oo<-srf(pr$act_bm[(k+1):nrow(pr)])
    if(!is.na(.is)&&.is>0) .oo/.is else NA_real_ })
  retn <- median(.rets, na.rm=TRUE)
  sr_m <- mean(pr$act_bm)/sd(pr$act_bm); nn <- nrow(pr)
  sk <- tryCatch(e1071::skewness(pr$act_bm),error=function(e)0); ku <- tryCatch(e1071::kurtosis(pr$act_bm)+3,error=function(e)3)
  den <- sqrt((1-sk*sr_m+(ku-1)/4*sr_m^2)/(nn-1)); dsr_raw <- if(den>1e-10) sr_m/den else NA
  dsr <- if(!is.na(dsr_raw)) dsr_raw - n_trials_dsr*0.05 else NA
  post_sr <- srf(pr[date>=post2017, act_bm]); full_bm_sr <- srf(pr$act_bm)
  list(dt=data.table(model=lab, port_t_EWuni=pt, port_t_capwt=pt_bm, oos_retention=retn, calmar=cal,
             dsr=dsr, post2017_bm_sr=post_sr, full_bm_sr=full_bm_sr, turnover=cs$turnover_annual, n_months=nrow(pr)),
       pr=pr[,.(date, act_bm, ret_net, benchmark_ret)])
}

## ════════════════ Step 1: 배포권 실측 패널 (102 factor top-25 active) — 캐시 ════════════════
PANEL_CACHE <- file.path(OUT, "r6_factor_deployzone_active.parquet")
if(file.exists(PANEL_CACHE) && !nzchar(Sys.getenv("RAMP_R6_FORCE_PANEL",""))){
  PANEL <- as.data.table(read_parquet(PANEL_CACHE)); PANEL[, signal_date := as.Date(signal_date)]
  wf("[cache] 배포권 패널 재사용: %s (%d rows, %d factors)", PANEL_CACHE, nrow(PANEL), uniqueN(PANEL$factor_id))
} else {
  wf("\n=== Step1: 배포권 패널 구축 (102 factor x top-25 EW active, canonical_screen_bt 직접) ===")
  t0 <- Sys.time(); rows <- list()
  for(fid in POOL_FACS){
    s <- sc[factor_id==fid, .(Date=as.Date(signal_date), Ticker=security_id, score=z)][!is.na(score)]
    cs <- tryCatch(canonical_screen_bt(s, RET_DT, BENCH_DT, top_n=TOP_N, cost_bps_oneway=COST_BPS,
            liq_dt=LIQ_DT, liq_min=LIQ_MIN, run_id="r6panel", strategy_id=fid, diag_dual_basis=FALSE),
            error=function(e) NULL)
    if(is.null(cs) || is.null(cs$period_returns)) next
    pr <- as.data.table(cs$period_returns)
    rows[[fid]] <- data.table(signal_date=as.Date(pr$date), factor_id=fid,
      ret_net=pr$ret_net, benchmark_ret=pr$benchmark_ret, active_bm=pr$ret_net - pr$benchmark_ret,
      family=FAC_FAM[[fid]])
  }
  PANEL <- rbindlist(rows, fill=TRUE)
  write_parquet(PANEL, PANEL_CACHE)
  wf("[cache] 패널 저장: %s | %.0fs | %d factors x %d months | %d rows",
     PANEL_CACHE, as.numeric(Sys.time()-t0,units="secs"), uniqueN(PANEL$factor_id),
     uniqueN(PANEL$signal_date), nrow(PANEL))
}
PANEL_FACS <- sort(unique(PANEL$factor_id))
Pw <- dcast(PANEL, signal_date ~ factor_id, value.var="active_bm"); setorder(Pw, signal_date)
panel_dates <- Pw$signal_date
Pmat <- as.matrix(Pw[, ..PANEL_FACS]); rownames(Pmat) <- as.character(panel_dates)
n_pm <- length(panel_dates)
stopifnot(all(panel_dates == sig_dates[1:n_pm]))

fac_full <- PANEL[, .(port_t_full=nwt(active_bm), net_sr=srf(ret_net-benchmark_ret),
                      post17_sr=srf(active_bm[signal_date>=post2017]), n=.N), by=.(factor_id, family)]
setorder(fac_full, -port_t_full)
wf("\n=== per-factor 배포권 실측 (full-period PORT_t 상위 12 — SELECTION엔 미사용, 진단 only) ===")
for(i in 1:min(12,nrow(fac_full))) wf("  %-30s [%-14s] PORT_t_full=%+.2f net_sr=%+.2f post17_sr=%+.2f",
  fac_full$factor_id[i], fac_full$family[i], fac_full$port_t_full[i], fac_full$net_sr[i], fac_full$post17_sr[i])

## ════════════════ Step 2: trailing PORT_t 선별 (PIT trailing-only) ════════════════
trailing_portt <- function(W, a_idx){
  lo <- a_idx - W; hi <- a_idx - 1L
  if(lo < 1L) return(NULL)
  sub <- Pmat[lo:hi, , drop=FALSE]
  apply(sub, 2, function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
    m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) })
}
SEL_CACHE <- file.path(".cache", sprintf("_ramp_r6_sel_%s.rds", RUNTAG))
if(file.exists(SEL_CACHE) && !nzchar(Sys.getenv("RAMP_R6_FORCE_SEL",""))){
  sel_traj <- readRDS(SEL_CACHE); wf("[cache] 선별 궤적 재사용: %s", SEL_CACHE)
} else {
  sel_traj <- list()
  for(W in WINDOWS){
    anchors <- seq(W+1L, n_sig-1L, by=CADENCE); tj <- list()
    for(a in anchors){
      tv <- trailing_portt(W, a); if(is.null(tv)) next
      ord <- names(sort(tv[is.finite(tv)], decreasing=TRUE))
      tj[[as.character(a)]] <- list(anchor_idx=a, anchor_date=as.character(sig_dates[a]),
        trailing_t=tv, ranked=ord, pool=setNames(lapply(KPOOL, function(k) head(ord, k)), paste0("K",KPOOL)))
    }
    sel_traj[[as.character(W)]] <- list(anchors=anchors, traj=tj)
  }
  saveRDS(sel_traj, SEL_CACHE); wf("[cache] 선별 궤적 저장: %s", SEL_CACHE)
}
## pool_union (Boruta slim table 컬럼) = 모든 anchor K20 풀 합집합
pool_union <- sort(unique(unlist(lapply(WINDOWS, function(W)
  unlist(lapply(sel_traj[[as.character(W)]]$traj, function(x) x$pool[["K20"]]))))))
wf("\n[Boruta slim] pool_union 팩터 수 = %d (전체 %d 중)", length(pool_union), length(POOL_FACS))

## ── composite/Boruta 공용 wide (키드) ──
fw <- dcast(sc, signal_date + security_id ~ factor_id, value.var="z")
fw <- merge(fw, ret, by=c("signal_date","security_id"), all.x=TRUE)
fw[, y := { m<-mean(Ret_1m,na.rm=TRUE); s<-sd(Ret_1m,na.rm=TRUE); if(is.na(s)||s<1e-9) Ret_1m-m else (Ret_1m-m)/s }, by=signal_date]
FW_FACS <- intersect(POOL_FACS, names(fw))
fw_z <- fw[, c("signal_date","security_id", FW_FACS), with=FALSE]; setkey(fw_z, signal_date)
gw_z <- gw[, c("signal_date","security_id", FAMS), with=FALSE]; setkey(gw_z, signal_date)
## slim Boruta table (pool_union 컬럼 + y) 키드
fwb <- fw[, c("signal_date","security_id","y", intersect(pool_union, names(fw))), with=FALSE]; setkey(fwb, signal_date)
rm(sc, g, gw); invisible(gc())

## ── arm 빌더 (composite -> top-25) ──
build_arm_score <- function(W, facs_getter){
  anchors <- sel_traj[[as.character(W)]]$anchors; deploy_idx <- (W+1L):(n_sig-1L); rows <- list()
  for(i in deploy_idx){
    ga <- max(anchors[anchors <= i]); facs <- intersect(facs_getter(W, ga), FW_FACS)
    if(length(facs)==0) next
    sub <- fw_z[.(sig_dates[i])]; if(nrow(sub)==0) next
    Xz <- sub[, lapply(.SD, zc), .SDcols=facs]; Xm <- as.matrix(Xz); Xm[is.na(Xm)] <- 0
    rows[[as.character(i)]] <- data.table(signal_date=sig_dates[i], security_id=sub$security_id, score=rowMeans(Xm))
  }
  s <- rbindlist(rows); s[, score := zc(score), by=signal_date]; s
}
build_base11_score <- function(W){
  deploy_idx <- (W+1L):(n_sig-1L); rows <- list()
  for(i in deploy_idx){
    sub <- gw_z[.(sig_dates[i])]; if(nrow(sub)==0) next
    Xz <- sub[, lapply(.SD, zc), .SDcols=FAMS]; Xm <- as.matrix(Xz); Xm[is.na(Xm)] <- 0
    rows[[as.character(i)]] <- data.table(signal_date=sig_dates[i], security_id=sub$security_id, score=rowMeans(Xm))
  }
  s <- rbindlist(rows); s[, score := zc(score), by=signal_date]; s
}
getter_pure  <- function(k) function(W, ga) sel_traj[[as.character(W)]]$traj[[as.character(ga)]]$pool[[paste0("K",k)]]
getter_all102<- function(W, ga) FW_FACS

## ════════════════ 측정 1/2: controls + P-pure (Boruta 불필요 — 먼저·빠르게) ════════════════
wf("\n=== 측정: controls + P-pure (cap-w authoritative) ===")
RES <- list(); PR <- list()
for(W in WINDOWS){
  lab <- sprintf("base_all11_W%d", W); gg <- gates(build_base11_score(W), lab); if(!is.null(gg)){ RES[[lab]]<-gg$dt; PR[[lab]]<-gg$pr }
  lab <- sprintf("ctrl_all102_W%d", W); gg <- gates(build_arm_score(W, getter_all102), lab); if(!is.null(gg)){ RES[[lab]]<-gg$dt; PR[[lab]]<-gg$pr }
}
for(W in WINDOWS) for(k in KPOOL){
  lab <- sprintf("Ppure_W%d_K%d", W, k); gg <- gates(build_arm_score(W, getter_pure(k)), lab)
  if(!is.null(gg)){ RES[[lab]]<-gg$dt; PR[[lab]]<-gg$pr }
  wf("  [%s] pt_capwt=%+.2f oos=%+.2f calmar=%+.2f DSR=%+.2f", lab,
     if(!is.null(gg)) gg$dt$port_t_capwt else NA, if(!is.null(gg)) gg$dt$oos_retention else NA,
     if(!is.null(gg)) gg$dt$calmar else NA, if(!is.null(gg)) gg$dt$dsr else NA)
}
saveRDS(list(RES=RES, PR=PR), file.path(".cache", sprintf("_ramp_r6_ppure_%s.rds", RUNTAG)))  # 중간저장

## ════════════════ Boruta within-pool (K=20) 궤적 — slim table, per-window checkpoint ════════════════
boruta_in_pool <- function(W, a_idx, pool, seed){
  lo <- a_idx - W; hi <- a_idx - 1L; win_dates <- sig_dates[lo:hi]
  pcols <- intersect(pool, names(fwb))
  pan <- fwb[.(win_dates)][is.finite(y)]
  if(nrow(pan) < 200 || length(pcols) < 3) return(list(confirmed=pool, degenerate="fallback_all_pool"))
  set.seed(seed); idx <- if(nrow(pan)>BORUTA$nmax) sample(nrow(pan), BORUTA$nmax) else seq_len(nrow(pan))
  X <- pan[idx, ..pcols]; for(f in pcols) X[[f]][is.na(X[[f]])] <- 0
  yv <- pan$y[idx]
  set.seed(seed)
  bor <- tryCatch(Boruta(x=as.data.frame(X), y=yv, maxRuns=BORUTA$maxRuns, doTrace=0, ntree=BORUTA$ntree),
                  error=function(e) NULL)
  if(is.null(bor)) return(list(confirmed=pool, degenerate="boruta_error"))
  dec <- bor$finalDecision; conf <- names(dec)[dec=="Confirmed"]; tent <- names(dec)[dec=="Tentative"]
  deg <- NA_character_
  if(length(conf) < 2){ conf <- union(conf, tent); deg <- "confirmed<2_add_tentative" }
  if(length(conf) < 1){ conf <- pool; deg <- "confirmed=0_fallback_pool" }
  list(confirmed=conf, tentative=tent, degenerate=deg, n_confirmed=length(conf))
}
BOR_CACHE <- file.path(".cache", sprintf("_ramp_r6_boruta_%s.rds", RUNTAG))
if(file.exists(BOR_CACHE) && !nzchar(Sys.getenv("RAMP_R6_FORCE_BOR",""))){
  bor_traj <- readRDS(BOR_CACHE); wf("[cache] Boruta 궤적 재사용: %s", BOR_CACHE)
} else {
  wf("\n=== Boruta within-pool 궤적 (K=20 풀, R4 params nmax=%d ntree=%d maxRuns=%d) ===", BORUTA$nmax, BORUTA$ntree, BORUTA$maxRuns)
  bor_traj <- list(); tB0 <- Sys.time(); ncall <- 0L
  for(W in WINDOWS){
    tjs <- sel_traj[[as.character(W)]]$traj; bt <- list()
    for(a_ch in names(tjs)){
      a <- as.integer(a_ch); pool <- tjs[[a_ch]]$pool[["K20"]]
      bsel <- boruta_in_pool(W, a, pool, seed=BORUTA$seed_base + a); ncall <- ncall + 1L
      bt[[a_ch]] <- list(anchor_idx=a, pool=pool, confirmed=bsel$confirmed,
                         n_confirmed=length(bsel$confirmed), degenerate=bsel$degenerate)
      wf("  [W=%d anchor %s] confirmed=%d/20 %.0fs-cum {%s}", W, as.character(sig_dates[a]),
         length(bsel$confirmed), as.numeric(Sys.time()-tB0,units="secs"), paste(head(bsel$confirmed,6),collapse=","))
    }
    bor_traj[[as.character(W)]] <- bt
    saveRDS(bor_traj, BOR_CACHE)   # per-window checkpoint
  }
  wf("[cache] Boruta 궤적 저장: %s (%d calls, %.0fs)", BOR_CACHE, ncall, as.numeric(Sys.time()-tB0,units="secs"))
}
getter_boruta<- function(W, ga){ bt<-bor_traj[[as.character(W)]][[as.character(ga)]]; if(is.null(bt)) FW_FACS else bt$confirmed }

## ════════════════ 측정 2/2: P-boruta (K=20) ════════════════
wf("\n=== 측정: P-boruta ===")
for(W in WINDOWS) for(k in BORUTA_KPOOL){
  lab <- sprintf("Pboruta_W%d_K%d", W, k); gg <- gates(build_arm_score(W, getter_boruta), lab)
  if(!is.null(gg)){ RES[[lab]]<-gg$dt; PR[[lab]]<-gg$pr }
  wf("  [%s] pt_capwt=%+.2f oos=%+.2f calmar=%+.2f DSR=%+.2f", lab,
     if(!is.null(gg)) gg$dt$port_t_capwt else NA, if(!is.null(gg)) gg$dt$oos_retention else NA,
     if(!is.null(gg)) gg$dt$calmar else NA, if(!is.null(gg)) gg$dt$dsr else NA)
}
TAB <- rbindlist(RES, fill=TRUE)
wf("\n=== 전체 게이트표 (cap-w authoritative) ===")
wf("  %-22s %9s %9s %9s %7s %7s %8s %6s", "model","pt_capwt","pt_EWuni","oos_ret","calmar","DSR","post17SR","TO")
for(i in seq_len(nrow(TAB))) wf("  %-22s %+9.2f %+9.2f %+9.2f %+7.2f %+7.2f %+8.2f %6.0f",
  TAB$model[i], TAB$port_t_capwt[i], TAB$port_t_EWuni[i], TAB$oos_retention[i], TAB$calmar[i], TAB$dsr[i], TAB$post2017_bm_sr[i], TAB$turnover[i])

## ── pin identity check: fresh base_all11_W36 vs R4 stored ──
r4c <- ".cache/_ramp_r4_20260711.rds"; pin_ok <- NA; pin_delta <- NA
if(file.exists(r4c)){
  r4 <- readRDS(r4c); r4_base <- r4$PR[["base_W36_EW"]]; fresh <- PR[["base_all11_W36"]]
  if(!is.null(r4_base) && !is.null(fresh)){
    m <- merge(r4_base[,.(date,r4=act_bm)], fresh[,.(date,r6=act_bm)], by="date")
    pin_delta <- if(nrow(m)) max(abs(m$r4 - m$r6), na.rm=TRUE) else NA
    pin_ok <- is.finite(pin_delta) && pin_delta < 1e-8
    wf("\n[pin identity] base_all11_W36 fresh vs R4 base_W36_EW: n=%d max|Δ|=%.2e ok=%s", nrow(m), pin_delta, pin_ok)
  }
}

## ── paired NW-t ──
paired <- list()
pair1 <- function(la, lb, kind){
  if(is.null(PR[[la]]) || is.null(PR[[lb]])) return(NULL)
  m <- merge(PR[[la]][,.(date,a=act_bm)], PR[[lb]][,.(date,b=act_bm)], by="date")
  d <- m$a - m$b; data.table(model=la, base=lb, kind=kind, mean_diff_ann=mean(d,na.rm=TRUE)*12, paired_t=nwt(d), n=nrow(m))
}
wf("\n=== paired NW-t (lag3) ===")
for(W in WINDOWS) for(k in KPOOL){ p<-pair1(sprintf("Ppure_W%d_K%d",W,k), sprintf("base_all11_W%d",W), "trait_repl_vs_base11"); if(!is.null(p)){ paired[[length(paired)+1]]<-p
  wf("  [기질교체] %-16s vs %-16s Δ(ann)=%+.4f paired_t=%+.2f (n=%d)", p$model, p$base, p$mean_diff_ann, p$paired_t, p$n) } }
for(W in WINDOWS) for(k in KPOOL){ p<-pair1(sprintf("Ppure_W%d_K%d",W,k), sprintf("ctrl_all102_W%d",W), "selection_vs_all102"); if(!is.null(p)){ paired[[length(paired)+1]]<-p
  wf("  [선별격리] %-16s vs %-16s Δ(ann)=%+.4f paired_t=%+.2f (n=%d)", p$model, p$base, p$mean_diff_ann, p$paired_t, p$n) } }
for(W in WINDOWS) for(k in BORUTA_KPOOL){ p<-pair1(sprintf("Pboruta_W%d_K%d",W,k), sprintf("Ppure_W%d_K%d",W,k), "boruta_vs_pure"); if(!is.null(p)){ paired[[length(paired)+1]]<-p
  wf("  [Boruta한계] %-16s vs %-16s Δ(ann)=%+.4f paired_t=%+.2f (n=%d)", p$model, p$base, p$mean_diff_ann, p$paired_t, p$n) } }
PAIRED <- rbindlist(paired, fill=TRUE)

## ── KILL 판정 (사전등록) ──
maxp_trait <- if(nrow(PAIRED)) max(PAIRED[kind=="trait_repl_vs_base11", paired_t], na.rm=TRUE) else NA
maxp_boruta<- if(nrow(PAIRED)) suppressWarnings(max(PAIRED[kind=="boruta_vs_pure", paired_t], na.rm=TRUE)) else NA
kill_pure  <- !(is.finite(maxp_trait) && maxp_trait >= PAIRED_KILL)
kill_boruta<- !(is.finite(maxp_boruta) && maxp_boruta >= PAIRED_KILL)
KILL <- kill_pure && kill_boruta
any_grad <- any(is.finite(TAB$port_t_capwt) & TAB$port_t_capwt>=GATE_PT & grepl("^P(pure|boruta)_", TAB$model))
wf("\n=== KILL gate (사전등록 paired>=%.1f) ===", PAIRED_KILL)
wf("  max paired (P-pure vs base_all11) = %+.2f -> kill_pure=%s", maxp_trait, kill_pure)
wf("  max paired (P-boruta vs P-pure)   = %+.2f -> kill_boruta=%s", maxp_boruta, kill_boruta)
wf("  graduation (any arm HARD PORT_t>=2.95) = %s", any_grad)
wf("  => KILL(PORT_t-정렬 축 소진) = %s", KILL)

wf("\n=== HARD 게이트 (capwt 2.95 / oos 0.7 / calmar 0.64 / DSR 0.5, family n_trials=%d) ===", N_TRIALS_FAMILY)
for(i in seq_len(nrow(TAB))){ r<-TAB[i]
  p<-c(port_t=isTRUE(r$port_t_capwt>=2.95), oos=isTRUE(r$oos_retention>=0.7), cal=isTRUE(r$calmar>=0.64), dsr=isTRUE(r$dsr>=0.5))
  wf("  [%-22s] %s -> %s", r$model, paste(names(p),ifelse(p,"✓","✗"),collapse=" "), ifelse(all(p),"★GRADUATION","미달")) }

## ── 선별 진단 (challenge): rank persistence + pool family skew ──
wf("\n=== 선별 진단 (challenge) ===")
persist <- list()
for(W in WINDOWS){
  tjs <- sel_traj[[as.character(W)]]$traj; keys <- names(tjs); rc <- c()
  for(j in 2:length(keys)){ t1 <- tjs[[keys[j-1]]]$trailing_t; t2 <- tjs[[keys[j]]]$trailing_t
    cf <- intersect(names(t1[is.finite(t1)]), names(t2[is.finite(t2)]))
    if(length(cf)>=10) rc <- c(rc, cor(t1[cf], t2[cf], method="spearman")) }
  poolfreq <- table(unlist(lapply(tjs, function(x) FAC_FAM[x$pool[["K20"]]])))
  persist[[as.character(W)]] <- list(W=W, n_anchor=length(keys),
    rank_ac_mean=mean(rc,na.rm=TRUE), rank_ac_sd=sd(rc,na.rm=TRUE),
    pool_family_freq=as.list(round(poolfreq/sum(poolfreq),3)))
  wf("  W=%d: anchors=%d | trailing NW-t rank 자기상관(연속) mean=%.2f sd=%.2f", W, length(keys), mean(rc,na.rm=TRUE), sd(rc,na.rm=TRUE))
  pf <- sort(poolfreq/sum(poolfreq), decreasing=TRUE)
  wf("    K20 풀 family 빈도: %s", paste(sprintf("%s=%.2f",names(pf),pf),collapse=" "))
}

## ── 저장 ──
res <- list(prereg=PREREG, config_hash=CFG_HASH, meta=list(as_of_date="2026-07-11",
    generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"), source_version="RAMP_R6_v1",
    security_id="Ticker->factor_id z (pure_factor_scores.z=Z_Score_Aligned)"),
  results=TAB, paired=PAIRED, persistence=persist,
  per_factor_deployzone_top12=fac_full[1:min(12,nrow(fac_full))],
  pin_ok=pin_ok, pin_delta=pin_delta, kill_pure=kill_pure, kill_boruta=kill_boruta, KILL=KILL,
  max_paired_trait=maxp_trait, max_paired_boruta=maxp_boruta,
  any_graduation=any_grad, n_trials_r6=N_TRIALS_R6, n_trials_family=N_TRIALS_FAMILY,
  n_sig=n_sig, date_range=as.character(range(sig_dates)),
  r4_ref=list(base_W36_EW_pt_capwt=1.024, r4_kill=TRUE, r4_max_paired=-2.02),
  r5_ref=list(family_closed=TRUE, r5_max_paired=0.18),
  families=FAMS, n_pool_factors=length(POOL_FACS), incumbent_book_ir=1.416)
saveRDS(list(res=res, PR=PR, TAB=TAB, PAIRED=PAIRED), file.path(".cache", sprintf("_ramp_r6_%s.rds", RUNTAG)))
write_parquet(TAB, file.path(OUT, sprintf("r6_portt_boruta_gates_%s.parquet", RUNTAG)))
if(nrow(PAIRED)) write_parquet(PAIRED, file.path(OUT, sprintf("r6_portt_boruta_paired_%s.parquet", RUNTAG)))
jsonlite::write_json(res, file.path(OUT, sprintf("r6_portt_boruta_summary_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=4)

wf("\n=== VERDICT ===")
bp <- TAB[grepl("^Ppure_",model)][which.max(port_t_capwt)]
bb <- TAB[grepl("^Pboruta_",model)][which.max(port_t_capwt)]
wf("  best P-pure:   %s pt_capwt=%+.2f oos=%+.2f calmar=%+.2f DSR=%+.2f", bp$model, bp$port_t_capwt, bp$oos_retention, bp$calmar, bp$dsr)
if(nrow(bb)) wf("  best P-boruta: %s pt_capwt=%+.2f oos=%+.2f calmar=%+.2f DSR=%+.2f", bb$model, bb$port_t_capwt, bb$oos_retention, bb$calmar, bb$dsr)
wf("  KILL=%s (kill_pure=%s kill_boruta=%s) | graduation=%s | pin_ok=%s", KILL, kill_pure, kill_boruta, any_grad, pin_ok)
close(con); cat(sprintf("R6_DONE. KILL=%s any_grad=%s maxp_trait=%.2f maxp_boruta=%.2f pin_ok=%s log=%s\n",
   KILL, any_grad, maxp_trait, maxp_boruta, pin_ok, logf))
cat(readLines(logf), sep="\n")
