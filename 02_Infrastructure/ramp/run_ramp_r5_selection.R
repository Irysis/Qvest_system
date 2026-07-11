## run_ramp_r5_selection.R — RAMP R5: 선별-규율 계열 폐쇄 판정 (Branch B)
## ─────────────────────────────────────────────────────────────────────────────
## 사전등록 스펙: 04_Research/factor_selection_program/r5_selection_comparison_spec.md
## 분기: Branch B (계열 폐쇄) — R4(Boruta) arm S = 선별 실효 실재(non-vacuous) ∧ 방향 유의 음
##   (paired NW-t 4구성 -2.02~-2.51, kill 발동). 목적 = "Boruta-특이 실패인가, 선별-규율 계열
##   전체가 죽었는가" 확정. StabSel + mRMR을 동일 하네스로 최소 예산 측정.
##
## [재사용 하네스] R4(run_ramp_r4_boruta.R)의 panel / within-month z / gates()(canonical_screen_bt)
##   / paired NW-t 를 byte-동일 재사용. 선별 모듈만 Boruta → StabSel(glmnet LASSO) / mRMR(corr) 교체.
## [base] all-11 {EW} — R4와 동일 harness로 fresh 재계산 후 R4 stored 값과 일치(pin identity) 확인.
##   내 R5 config는 전부 EW 배분(선별효과 순수 격리) → paired vs base_W{W}_EW.
## [측정] cap-w authoritative + EW-uni 진단 병기 + HARD 3종(2.95/0.7/0.64) + 2017+ 분리 + DSR(sweep)
##   + base 대비 paired NW-t(lag3, 문턱 2.0). 실측-only. PIT: 학습창 trailing-only(C1).
## [KILL 사전등록] R5 전 config paired < 2.0 → 선별-규율 계열(shadow-null·stability·redundancy)
##   config-scoped 소진 → L-code + DIST 후보 초안.
## 실측-only · 단일스레드 · vintage: R4 세션 pin(factor_group_scores 2026-06-19, slim rds).
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)
  library(glmnet); library(digest); library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
## R4가 사용한 slim rawdata 재사용(fwd 동일성 보장). 미존재 시 parquet+월말필터로 동일 fwd 산출.
SLIM <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/3d6b0eb6-6786-4a56-916d-9681f94897fe/scratchpad/ramp_r4_slim.rds"
if(file.exists(SLIM)) Sys.setenv(RAMP_R1_SLIM_RDS=SLIM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns
source("02_Infrastructure/contracts/canonical_screen_bt.R")
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }
OUT <- "outputs/ramp"; RUNTAG <- format(Sys.Date(),"%Y%m%d")
logf <- file.path(".cache", sprintf("_ramp_r5_%s.txt", RUNTAG))
con <- file(logf,"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con); wf<-function(...){w(sprintf(...))}

## ── 사전등록 config (hash 고정 — 측정 전 동결) ──
WINDOWS <- c(36L, 60L); CADENCE <- 6L
TOP_N <- 25L; COST_BPS <- 15; LIQ_MIN <- 2e8
GATE_PT <- 2.95; PAIRED_KILL <- 2.0
B_PAIRS <- 50L; SS_SEED_BASE <- 5000L
## StabSel 3 config (EW 배분): {W,π} — 2조합 + 1 재량(짧은창 stricter π)
SS_CONFIGS  <- list(list(W=36L,pi=0.60), list(W=36L,pi=0.70), list(W=60L,pi=0.60))
## mRMR 3 config (EW 배분): {k,W} — corr-기반 근사(praznik/infotheo 미가용)
MR_CONFIGS  <- list(list(W=36L,k=4L),  list(W=36L,k=6L),  list(W=60L,k=6L))
N_TRIALS_R5 <- length(SS_CONFIGS) + length(MR_CONFIGS)   # =6 (R5 sweep DSR deflation)
N_TRIALS_FAMILY <- 4L + N_TRIALS_R5                       # Boruta arm-S(4) + R5(6) = 10 (family 회계)
PREREG <- list(mode="RAMP", round="R5", branch="B_family_closure",
  spec="04_Research/factor_selection_program/r5_selection_comparison_spec.md",
  r4_ref=list(lcode="L-RAMP-20260711_181539", kill=TRUE, max_paired_t=-2.02,
              base_pt_capwt=list(base_W36_EW=1.02, base_W36_ICW=1.66, base_W60_EW=0.40, base_W60_ICW=0.42)),
  mechanisms=c("stability_selection_glmnet_lasso_complementary_pairs","mRMR_correlation_based_signed_rankIC_relevance"),
  substrate="outputs/ramp/factor_group_scores.parquet (11 orthogonal economic families)",
  stabsel=list(base_selector="glmnet_lasso_alpha1", lambda="cv.glmnet 5fold lambda.1se (min fallback)",
               subsample="complementary_pairs B=50 (=100 subsamples), row-level", pi_hat="selection freq at lambda*",
               configs=SS_CONFIGS, min_size_fallback=2L),
  mrmr=list(relevance="trailing mean spearman rank-IC (signed)", redundancy="mean |pearson cor| among selected",
            greedy="MID (relevance - mean redundancy)", note="praznik/infotheo unavailable -> correlation approximation",
            configs=MR_CONFIGS),
  allocation="EW on selected families (within-month z composite -> top-25)", weight_matched_base="base_W{W}_EW",
  windows=WINDOWS, cadence_months=CADENCE, top_n=TOP_N, cost_bps_oneway=COST_BPS, liq_min=LIQ_MIN,
  gate_hard=c(port_t_capwt=GATE_PT, oos_retention=0.7, calmar=0.64, dsr=0.5),
  n_trials_r5=N_TRIALS_R5, n_trials_family=N_TRIALS_FAMILY, paired_kill_threshold=PAIRED_KILL,
  target="within-month z-scored forward 1M return (cross-sectional)",
  pit="training window trailing-only (last W sig_dates strictly before rebalance; fwd realized by t)",
  vintage_pin=sprintf("r4_session_%s", RUNTAG),
  selection_type="sweep",
  as_of_date=as.character(Sys.Date()), generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
  source_version="RAMP_R5_v1", security_id="Ticker (rawdata) -> family group_z (factor_group_scores)")
CFG_HASH <- substr(digest::digest(PREREG, algo="sha256"), 1, 16); PREREG$config_hash <- CFG_HASH
dir.create(OUT, showWarnings=FALSE, recursive=TRUE)
jsonlite::write_json(PREREG, file.path(OUT, sprintf("r5_selection_prereg_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=6)   # 측정 전 동결 저장

## ── 데이터 (R4 동일 소스·파이프라인) ──
g <- as.data.table(read_parquet(file.path(OUT,"factor_group_scores.parquet")))
g[, signal_date := as.Date(signal_date)]; FAMS <- sort(unique(g$family))
gw <- dcast(g, signal_date + security_id ~ family, value.var="group_z")
.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
sig_dates <- sort(unique(gw$signal_date)); n_sig <- length(sig_dates)
.slim_rds <- Sys.getenv("RAMP_R1_SLIM_RDS", "")
if (nzchar(.slim_rds) && file.exists(.slim_rds)) {
  rawdata <- as.data.table(readRDS(.slim_rds)); rawdata[, Date := as.Date(Date)]
} else {
  rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
  .udates <- sort(unique(rawdata$Date))
  .me <- as.Date(vapply(sig_dates, function(d){ v <- .udates[.udates <= d]
    if(length(v)) as.character(max(v)) else NA_character_ }, character(1)))
  rawdata <- rawdata[Date %in% .me[!is.na(.me)]]
}
fwd <- build_monthly_forward_returns(rawdata, sig_dates)
ret <- fwd$returns_dt[,.(signal_date=as.Date(Date), security_id=Ticker, Ret_1m)]
post2017 <- as.Date("2017-01-01")
ewb <- fwd$returns_dt[, .(ew=mean(Ret_1m,na.rm=TRUE)), by=.(date=as.Date(Date))]
panel <- merge(gw[, c("signal_date","security_id", FAMS), with=FALSE], ret, by=c("signal_date","security_id"), all.x=TRUE)
panel[, y := { m<-mean(Ret_1m,na.rm=TRUE); s<-sd(Ret_1m,na.rm=TRUE); if(is.na(s)||s<1e-9) Ret_1m-m else (Ret_1m-m)/s }, by=signal_date]
gw_z_month <- gw[, c("signal_date","security_id"), with=FALSE]; for(f in FAMS) gw_z_month[[f]] <- gw[[f]]

wf("=== RAMP R5: 선별-규율 계열 폐쇄 판정 (Branch B) — StabSel(glmnet) + mRMR(corr) ===")
wf("config_hash=%s | %d families {%s} | %d months %s~%s | ~%d stk/mo",
   CFG_HASH, length(FAMS), paste(FAMS,collapse=","), n_sig, as.character(sig_dates[1]),
   as.character(sig_dates[n_sig]), median(gw[,.N,by=signal_date]$N))
wf("R5 configs: StabSel{%s} + mRMR{%s} | B_pairs=%d | family n_trials=%d",
   paste(sapply(SS_CONFIGS,function(c)sprintf("W%d_pi%.2f",c$W,c$pi)),collapse=","),
   paste(sapply(MR_CONFIGS,function(c)sprintf("W%d_k%d",c$W,c$k)),collapse=","), B_PAIRS, N_TRIALS_FAMILY)

## ── trailing IC (R4 복제 — mRMR relevance) ──
trailing_ic <- function(train_idx, fams){
  win_dates <- sig_dates[train_idx]; pan <- panel[signal_date %in% win_dates]
  sapply(fams, function(fm){
    d <- pan[is.finite(get(fm)) & is.finite(Ret_1m)]; if(nrow(d) < 30) return(0)
    icv <- d[, { if(.N>=10 && sd(get(fm))>0 && sd(Ret_1m)>0) .(ic=cor(get(fm),Ret_1m,method="spearman")) else .(ic=NA_real_) }, by=signal_date]$ic
    m <- mean(icv, na.rm=TRUE); if(is.na(m)) 0 else m })
}

## ── StabSel 궤적 (window별, semiannual anchor; weight-independent 캐시) ──
SS_CACHE <- file.path(".cache", sprintf("_ramp_r5_stabsel_traj_%s.rds", RUNTAG))
stabsel_window <- function(W){
  anchors <- seq(W+1L, n_sig-1L, by=CADENCE); tj <- list()
  for(a_i in anchors){
    tr <- (a_i-W):(a_i-1L); pan <- panel[signal_date %in% sig_dates[tr] & is.finite(y)]
    if(nrow(pan) < 200){ tj[[as.character(a_i)]] <- list(anchor_idx=a_i, anchor_date=as.character(sig_dates[a_i]),
        pi_hat=setNames(rep(1,length(FAMS)),FAMS), degenerate="too_few_rows", n_rows=nrow(pan)); next }
    X <- as.matrix(pan[, ..FAMS]); X[is.na(X)] <- 0; yv <- pan$y
    set.seed(SS_SEED_BASE + a_i)
    cvf <- tryCatch(cv.glmnet(X, yv, alpha=1, nfolds=5, standardize=TRUE), error=function(e) NULL)
    if(is.null(cvf)){ tj[[as.character(a_i)]] <- list(anchor_idx=a_i, anchor_date=as.character(sig_dates[a_i]),
        pi_hat=setNames(rep(1,length(FAMS)),FAMS), degenerate="cv_error", n_rows=nrow(pan)); next }
    lam <- cvf$lambda.1se
    nz1 <- tryCatch(sum(as.matrix(coef(cvf, s=lam))[-1,1] != 0), error=function(e) 0)
    if(nz1 < 1) lam <- cvf$lambda.min
    lam_grid <- cvf$lambda
    n <- nrow(X); half <- floor(n/2); sel_cube <- matrix(0, nrow=2L*B_PAIRS, ncol=length(FAMS)); colnames(sel_cube) <- FAMS
    r <- 0L
    for(b in seq_len(B_PAIRS)){
      set.seed(SS_SEED_BASE*7L + a_i*13L + b); perm <- sample(n)
      idxA <- perm[1:half]; idxB <- perm[(half+1L):(2L*half)]
      for(idx in list(idxA, idxB)){
        r <- r+1L
        gsub <- tryCatch(glmnet(X[idx,,drop=FALSE], yv[idx], alpha=1, lambda=lam_grid, standardize=TRUE), error=function(e) NULL)
        if(is.null(gsub)) next
        cf <- tryCatch(as.matrix(coef(gsub, s=lam))[-1,1], error=function(e) setNames(rep(0,length(FAMS)),FAMS))
        sel_cube[r, names(cf)[is.finite(cf) & cf != 0]] <- 1
      }
    }
    pi_hat <- colMeans(sel_cube[1:r,,drop=FALSE])
    tj[[as.character(a_i)]] <- list(anchor_idx=a_i, anchor_date=as.character(sig_dates[a_i]),
      pi_hat=pi_hat, lambda=lam, n_rows=n, n_sub=r, degenerate=NA_character_)
    wf("  [StabSel W=%d anchor %s] lam=%.5f pi_hat top: %s", W, as.character(sig_dates[a_i]), lam,
       paste(sprintf("%s=%.2f",names(sort(pi_hat,decreasing=TRUE))[1:4], sort(pi_hat,decreasing=TRUE)[1:4]),collapse=" "))
  }
  list(anchors=anchors, traj=tj)
}
if(file.exists(SS_CACHE) && !nzchar(Sys.getenv("RAMP_R5_FORCE",""))){
  ss_all <- readRDS(SS_CACHE); wf("[cache] StabSel 궤적 재사용")
} else { ss_all <- list(); for(W in WINDOWS){ ss_all[[as.character(W)]] <- stabsel_window(W); saveRDS(ss_all, SS_CACHE) } }

## ── mRMR 궤적 (window별; corr-based, weight-independent 캐시) ──
mrmr_window <- function(W){
  anchors <- seq(W+1L, n_sig-1L, by=CADENCE); tj <- list()
  for(a_i in anchors){
    tr <- (a_i-W):(a_i-1L); pan <- panel[signal_date %in% sig_dates[tr]]
    rel <- trailing_ic(tr, FAMS)                       # signed trailing rank-IC relevance
    M <- as.matrix(pan[, ..FAMS]); C <- suppressWarnings(cor(M, use="pairwise.complete.obs", method="pearson"))
    C[is.na(C)] <- 0; absC <- abs(C)
    remaining <- FAMS; f1 <- names(rel)[which.max(rel)]; order_sel <- f1; remaining <- setdiff(remaining, f1)
    while(length(remaining) > 0){
      sc <- sapply(remaining, function(f) rel[[f]] - mean(absC[f, order_sel])); fnext <- remaining[which.max(sc)]
      order_sel <- c(order_sel, fnext); remaining <- setdiff(remaining, fnext)
    }
    tj[[as.character(a_i)]] <- list(anchor_idx=a_i, anchor_date=as.character(sig_dates[a_i]),
      greedy_order=order_sel, relevance=rel, degenerate=NA_character_)
  }
  list(anchors=anchors, traj=tj)
}
mr_all <- list(); for(W in WINDOWS) mr_all[[as.character(W)]] <- mrmr_window(W)

## ── walk-forward 스코어 (EW; R4 EW branch 복제) ──
build_wf_sel <- function(W, anchors, sel_fun){
  deploy_idx <- (W+1L):(n_sig-1L); rows <- list()
  for(i in deploy_idx){
    ga <- max(anchors[anchors <= i]); fams <- sel_fun(ga)
    wv <- setNames(rep(1/length(fams), length(fams)), fams)
    sub <- gw_z_month[signal_date==sig_dates[i]]
    Xz <- sub[, lapply(.SD, zc), .SDcols=fams]; Xm <- as.matrix(Xz); Xm[is.na(Xm)] <- 0
    sc <- as.numeric(Xm %*% wv[fams])
    rows[[as.character(i)]] <- data.table(signal_date=sig_dates[i], security_id=sub$security_id, score=sc)
  }
  s <- rbindlist(rows); s[, score := zc(score), by=signal_date]; s
}
ss_sel_fun <- function(W, pi_thr){ tj <- ss_all[[as.character(W)]]$traj
  function(ga){ ph <- tj[[as.character(ga)]]$pi_hat; sel <- names(ph)[ph >= pi_thr]
    if(length(sel) < 2) sel <- names(sort(ph, decreasing=TRUE))[1:2]; sel } }
mr_sel_fun <- function(W, k){ tj <- mr_all[[as.character(W)]]$traj
  function(ga){ ord <- tj[[as.character(ga)]]$greedy_order; ord[1:min(k,length(ord))] } }

## ── 게이트 계산기 (R4 gates() 복제; cap-w authoritative) ──
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA); mean(x)/sd(x)*sqrt(12) }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
gates <- function(score_dt, lab, n_trials){
  cs <- tryCatch(canonical_screen_bt(
        score_dt[,.(Date=as.Date(signal_date), Ticker=security_id, score)],
        fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)], fwd$bench_dt[,.(Date=as.Date(Date), BM_Ret)],
        top_n=TOP_N, cost_bps_oneway=COST_BPS, liq_dt=fwd$liq_dt[,.(Date=as.Date(Date), Ticker, adv)],
        liq_min=LIQ_MIN, run_id="r5", strategy_id=lab), error=function(e){ w("  [gates ERR ",lab,"] ",conditionMessage(e)); NULL })
  if(is.null(cs) || is.null(cs$period_returns)) return(NULL)
  pr <- as.data.table(cs$period_returns); pr[,date:=as.Date(date)]; pr <- merge(pr, ewb, by="date", all.x=TRUE)
  pr[, act := ret_net - ew]; pr[, act_bm := ret_net - benchmark_ret]
  pt <- nwt(pr$act); pt_bm <- nwt(pr$act_bm)
  nav <- cumprod(1+pr$ret_net); dd <- min(nav/cummax(nav)-1); ann <- prod(1+pr$ret_net)^(12/nrow(pr))-1
  cal <- if(dd<0) ann/abs(dd) else NA
  .splits<-c(0.55,0.65,0.75); .rets<-sapply(.splits,function(fr){ k<-floor(nrow(pr)*fr)
    if(k<12||(nrow(pr)-k)<6) return(NA_real_); .is<-srf(pr$act_bm[1:k]); .oo<-srf(pr$act_bm[(k+1):nrow(pr)])
    if(!is.na(.is)&&.is>0) .oo/.is else NA_real_ }); retn <- median(.rets, na.rm=TRUE)
  sr_m <- mean(pr$act_bm)/sd(pr$act_bm); nn <- nrow(pr)
  sk <- tryCatch(e1071::skewness(pr$act_bm),error=function(e)0); ku <- tryCatch(e1071::kurtosis(pr$act_bm)+3,error=function(e)3)
  den <- sqrt((1-sk*sr_m+(ku-1)/4*sr_m^2)/(nn-1)); dsr_raw <- if(den>1e-10) sr_m/den else NA
  dsr <- if(!is.na(dsr_raw)) dsr_raw - n_trials*0.05 else NA
  post_sr <- srf(pr[date>=post2017, act_bm]); full_bm_sr <- srf(pr$act_bm)
  list(dt=data.table(model=lab, port_t_EWuni=pt, port_t_capwt=pt_bm, oos_retention=retn, calmar=cal,
             dsr=dsr, post2017_bm_sr=post_sr, full_bm_sr=full_bm_sr, turnover=cs$turnover_annual, n_months=nrow(pr)),
       pr=pr[,.(date, act_bm, ret_net, benchmark_ret)])
}

## ── base(all-11 EW) fresh 재계산 + pin identity 확인 ──
wf("\n=== base(all-11 EW) fresh 재계산 + R4 pin identity 확인 ===")
r4 <- readRDS(".cache/_ramp_r4_20260711.rds"); r4res <- as.data.table(r4$res$results)
RES <- list(); PR <- list(); pin_ok <- TRUE
for(W in WINDOWS){
  anch <- seq(W+1L, n_sig-1L, by=CADENCE)
  lab <- sprintf("base_W%d_EW", W)
  gg <- gates(build_wf_sel(W, anch, function(ga) FAMS), lab, N_TRIALS_R5)
  if(!is.null(gg)){ RES[[lab]] <- gg$dt; PR[[lab]] <- gg$pr
    r4v <- r4res[model==lab, port_t_capwt]
    dv <- if(length(r4v)) abs(gg$dt$port_t_capwt - r4v) else NA
    ok <- is.finite(dv) && dv < 0.02
    if(!ok) pin_ok <- FALSE
    wf("  [%s] R5 pt_capwt=%+.3f | R4 stored=%+.3f | Δ=%.4f | pin=%s", lab, gg$dt$port_t_capwt,
       ifelse(length(r4v),r4v,NA), ifelse(is.finite(dv),dv,NA), ifelse(ok,"OK","DRIFT")) }
}
if(!pin_ok){ wf("\n[HALT] base pin identity DRIFT — R4 harness/데이터와 불일치. 측정 중단.")
  close(con); cat("R5_HALT_PIN_DRIFT log=",logf,"\n",sep=""); cat(readLines(logf),sep="\n"); quit(save="no", status=2) }
wf("  => pin identity OK (fresh base == R4 stored). fwd·harness R4 동일 확인.")

## ── arm 측정: StabSel(3) + mRMR(3) ──
wf("\n=== 측정: StabSel(3) + mRMR(3) — cap-w authoritative ===")
CFG_META <- list()
for(cc in SS_CONFIGS){ W<-cc$W; lab <- sprintf("stabsel_W%d_pi%02d", W, round(cc$pi*100))
  anch <- seq(W+1L, n_sig-1L, by=CADENCE)
  gg <- gates(build_wf_sel(W, anch, ss_sel_fun(W, cc$pi)), lab, N_TRIALS_R5)
  if(!is.null(gg)){ RES[[lab]] <- gg$dt; PR[[lab]] <- gg$pr; CFG_META[[lab]] <- list(method="stabsel", W=W, base=sprintf("base_W%d_EW",W)) } }
for(cc in MR_CONFIGS){ W<-cc$W; lab <- sprintf("mrmr_W%d_k%d", W, cc$k)
  anch <- seq(W+1L, n_sig-1L, by=CADENCE)
  gg <- gates(build_wf_sel(W, anch, mr_sel_fun(W, cc$k)), lab, N_TRIALS_R5)
  if(!is.null(gg)){ RES[[lab]] <- gg$dt; PR[[lab]] <- gg$pr; CFG_META[[lab]] <- list(method="mrmr", W=W, base=sprintf("base_W%d_EW",W)) } }
TAB <- rbindlist(RES, fill=TRUE)
wf("  %-20s %9s %9s %9s %7s %7s %8s %6s", "model","pt_capwt","pt_EWuni","oos_ret","calmar","DSR","post17SR","TO")
for(i in seq_len(nrow(TAB))) wf("  %-20s %+9.2f %+9.2f %+9.2f %+7.2f %+7.2f %+8.2f %6.0f",
  TAB$model[i], TAB$port_t_capwt[i], TAB$port_t_EWuni[i], TAB$oos_retention[i], TAB$calmar[i], TAB$dsr[i], TAB$post2017_bm_sr[i], TAB$turnover[i])

## ── paired NW-t (config − matching base_EW) ──
wf("\n=== paired NW-t (lag3): R5 arm(EW selected) − base_W{W}_EW(all11 EW) ===")
paired <- list()
for(lab in names(CFG_META)){ lb <- CFG_META[[lab]]$base
  if(is.null(PR[[lab]]) || is.null(PR[[lb]])) next
  m <- merge(PR[[lab]][,.(date, a=act_bm)], PR[[lb]][,.(date, b=act_bm)], by="date")
  d <- m$a - m$b; tval <- nwt(d)
  paired[[lab]] <- data.table(model=lab, base=lb, method=CFG_META[[lab]]$method,
    mean_diff_ann=mean(d,na.rm=TRUE)*12, paired_t=tval, n=nrow(m))
  wf("  %-20s vs %-14s Δmean(ann)=%+.4f paired_t=%+.2f (n=%d)", lab, lb, mean(d,na.rm=TRUE)*12, tval, nrow(m)) }
PAIRED <- rbindlist(paired, fill=TRUE)

## ── 선별 실효 + 방법간 수렴 진단 ──
wf("\n=== 선별 실효 진단 (StabSel/mRMR가 실제로 거르는가 + 방법간 수렴) ===")
sel_sets_by_cfg <- list()
# StabSel: config별 anchor 선택집합
for(cc in SS_CONFIGS){ W<-cc$W; lab <- sprintf("stabsel_W%d_pi%02d", W, round(cc$pi*100))
  tj <- ss_all[[as.character(W)]]$traj; f <- ss_sel_fun(W, cc$pi)
  anch <- ss_all[[as.character(W)]]$anchors; sets <- lapply(anch, function(a) f(a)); names(sets) <- anch
  sizes <- sapply(sets, length); jac <- if(length(sets)>=2) sapply(2:length(sets), function(k){ i<-intersect(sets[[k]],sets[[k-1]]); u<-union(sets[[k]],sets[[k-1]]); 1-length(i)/length(u) }) else NA
  vac <- mean(sizes >= length(FAMS)); sel_sets_by_cfg[[lab]] <- sets
  wf("  [%s] size mean=%.1f [%d~%d] | 전팩터-선택 비율=%.2f | set-turnover(Jaccard)=%.2f",
     lab, mean(sizes), min(sizes), max(sizes), vac, mean(jac,na.rm=TRUE)) }
for(cc in MR_CONFIGS){ W<-cc$W; lab <- sprintf("mrmr_W%d_k%d", W, cc$k)
  f <- mr_sel_fun(W, cc$k); anch <- mr_all[[as.character(W)]]$anchors; sets <- lapply(anch, function(a) f(a)); names(sets)<-anch
  sizes <- sapply(sets, length); jac <- if(length(sets)>=2) sapply(2:length(sets), function(k){ i<-intersect(sets[[k]],sets[[k-1]]); u<-union(sets[[k]],sets[[k-1]]); 1-length(i)/length(u) }) else NA
  sel_sets_by_cfg[[lab]] <- sets
  wf("  [%s] size=%d (fixed) | set-turnover(Jaccard)=%.2f", lab, cc$k, mean(jac,na.rm=TRUE)) }
# 팩터군별 선택 빈도 (StabSel pi>=0.6 · mRMR k6 · Boruta[R4]) — 방법간 수렴 확인
wf("\n  팩터군별 선택 빈도 (W=36; StabSel π0.6 / mRMR k6 / Boruta[R4]):")
freq_by_method <- list()
sc <- sel_sets_by_cfg[["stabsel_W36_pi60"]]; f_ss <- sapply(FAMS, function(fm) mean(sapply(sc, function(s) fm %in% s)))
mc <- sel_sets_by_cfg[["mrmr_W36_k6"]];    f_mr <- sapply(FAMS, function(fm) mean(sapply(mc, function(s) fm %in% s)))
bt36 <- r4$traj[["36"]]$traj; f_bt <- sapply(FAMS, function(fm) mean(sapply(bt36, function(x) fm %in% x$confirmed)))
freq_by_method <- data.table(family=FAMS, stabsel_pi60=f_ss, mrmr_k6=f_mr, boruta_r4=f_bt)
ord <- order(-(f_ss+f_mr+f_bt))
for(j in ord) wf("   %-16s StabSel=%.2f  mRMR=%.2f  Boruta=%.2f", FAMS[j], f_ss[j], f_mr[j], f_bt[j])
# 방법간 평균 선택집합 Jaccard (수렴도)
conv_jac <- function(A,B){ mean(mapply(function(a,b){ i<-intersect(a,b); u<-union(a,b); if(length(u)==0) NA else length(i)/length(u) },
  A[intersect(names(A),names(B))], B[intersect(names(A),names(B))]), na.rm=TRUE) }
bt_sets36 <- lapply(bt36, function(x) x$confirmed); names(bt_sets36) <- sapply(bt36, function(x) x$anchor_idx)
j_ss_mr <- conv_jac(sel_sets_by_cfg[["stabsel_W36_pi60"]], sel_sets_by_cfg[["mrmr_W36_k6"]])
j_ss_bt <- conv_jac(sel_sets_by_cfg[["stabsel_W36_pi60"]], bt_sets36)
j_mr_bt <- conv_jac(sel_sets_by_cfg[["mrmr_W36_k6"]], bt_sets36)
wf("\n  방법간 선택집합 평균 Jaccard 유사도 (W=36): StabSel~mRMR=%.2f  StabSel~Boruta=%.2f  mRMR~Boruta=%.2f",
   j_ss_mr, j_ss_bt, j_mr_bt)

## ── KILL gate 판정 (사전등록 paired>=2.0) ──
max_paired_r5 <- if(nrow(PAIRED)) max(PAIRED$paired_t, na.rm=TRUE) else NA
any_pass_grad <- any(is.finite(TAB$port_t_capwt) & TAB$port_t_capwt >= GATE_PT & grepl("^(stabsel|mrmr)_", TAB$model))
kill_r5 <- !(is.finite(max_paired_r5) && max_paired_r5 >= PAIRED_KILL)
family_closed <- kill_r5 && TRUE   # R4 kill=TRUE (max_paired -2.02) ∧ R5 kill
wf("\n=== KILL gate (사전등록 paired>=%.1f) ===", PAIRED_KILL)
wf("  R5 max paired_t = %+.2f | R5 graduation pass = %s | R5 kill = %s", max_paired_r5, any_pass_grad, kill_r5)
wf("  R4 kill = TRUE (max paired -2.02) → 선별-규율 계열(Boruta+StabSel+mRMR) 폐쇄 = %s", family_closed)

## ── HARD 게이트 판정표 ──
wf("\n=== HARD 게이트 (capwt 2.95 / oos 0.7 / calmar 0.64 / DSR 0.5) ===")
for(i in seq_len(nrow(TAB))){ r<-TAB[i]
  p<-c(port_t=isTRUE(r$port_t_capwt>=2.95), oos=isTRUE(r$oos_retention>=0.7), cal=isTRUE(r$calmar>=0.64), dsr=isTRUE(r$dsr>=0.5))
  wf("  [%-20s] %s → %s", r$model, paste(names(p),ifelse(p,"✓","✗"),collapse=" "), ifelse(all(p),"★GRADUATION","미달")) }

## ── 저장 (출력 규약: as_of/generated/source_version/security_id) ──
META <- list(as_of_date=PREREG$as_of_date, generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
  source_version=PREREG$source_version, security_id=PREREG$security_id, config_hash=CFG_HASH)
res <- list(prereg=PREREG, meta=META, results=TAB, paired=PAIRED, freq_by_method=freq_by_method,
  method_jaccard=list(stabsel_mrmr=j_ss_mr, stabsel_boruta=j_ss_bt, mrmr_boruta=j_mr_bt),
  r5_max_paired_t=max_paired_r5, r5_kill=kill_r5, r4_kill=TRUE, r4_max_paired_t=-2.02,
  family_closed=family_closed, any_graduation=any_pass_grad,
  n_trials_r5=N_TRIALS_R5, n_trials_family=N_TRIALS_FAMILY, families=FAMS,
  n_sig=n_sig, date_range=as.character(range(sig_dates)), incumbent_book_ir=1.416, pin_ok=pin_ok)
saveRDS(list(res=res, PR=PR, ss_traj=ss_all, mr_traj=mr_all), file.path(".cache", sprintf("_ramp_r5_%s.rds", RUNTAG)))
write_parquet(TAB, file.path(OUT, sprintf("r5_selection_gates_%s.parquet", RUNTAG)))
if(nrow(PAIRED)) write_parquet(PAIRED, file.path(OUT, sprintf("r5_selection_paired_%s.parquet", RUNTAG)))
write_parquet(freq_by_method, file.path(OUT, sprintf("r5_selection_selfreq_%s.parquet", RUNTAG)))
jsonlite::write_json(res, file.path(OUT, sprintf("r5_selection_summary_%s.json", RUNTAG)), auto_unbox=TRUE, pretty=TRUE, digits=4)

wf("\n=== VERDICT (R5 Branch B) ===")
bb <- TAB[grepl("^(stabsel|mrmr)_",model)][which.max(port_t_capwt)]
wf("  best R5 arm: %s pt_capwt=%+.2f oos=%+.2f calmar=%+.2f DSR=%+.2f",
   bb$model, bb$port_t_capwt, bb$oos_retention, bb$calmar, bb$dsr)
wf("  R5 max paired=%+.2f | R5 kill=%s | family(Boruta+StabSel+mRMR) 폐쇄=%s | graduation=%s",
   max_paired_r5, kill_r5, family_closed, any_pass_grad)
close(con)
cat(sprintf("R5_DONE. r5_kill=%s family_closed=%s r5_max_paired=%.2f best=%s(pt=%.2f) log=%s\n",
   kill_r5, family_closed, max_paired_r5, bb$model, bb$port_t_capwt, logf))
cat(readLines(logf), sep="\n")
