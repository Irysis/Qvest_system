## run_ramp_r9_insider_f1.R — FQ-019/R9 Stage B: insider 확장 패널 × F-1 챔피언 construction
## ─────────────────────────────────────────────────────────────────────────────
## Stage A(run_ramp_r9_insider_ext.R)는 frozen prereg의 plain top-K pool 로테이션(2×2 격자)만 측정한다.
## armed spec §4.2(2026-07-13 개정)·FQ-028 next_probe ①은 R9 = "insider 재료 × 검증된 F-1 챔피언
## construction(반기 level36 진입 + 분기 rank-only 퇴출 + level36 재충원, R15 확정 2.937/+0.048)" 이식을
## 지정하나, run_ramp_r9_insider_ext.R 러너에는 F-1 construction이 미구현(plain만) — 이 companion이 그 갭을 채운다.
##
## [F-1 챔피언 construction] R15 run_ramp_r15_fill.R::build_pool_traj_fill("level36") 이식 (level36-only):
##   · level36 = trailing NW-t(lag3) over W36 (R6/R9 trailing_portt 자구동일). recent18/sub1-3 불요(L-1/L-3 전용).
##   · 진입(반기, cadence6): top-K by level36.
##   · 퇴출(분기, cadence3): held 팩터 현 rank>EXIT_RANK_BAR(30) 또는 level36<0 이면 배출.
##   · 충원: 빈 슬롯 = level36 차순위(수준-fill).
##   · 배포월 i pool = 최근 exit anchor pool.
##
## [측정 대조] R9 gates()(canonical_screen_bt) 자구동일 — Stage A와 동일 계약경로(plain-parity 재현으로 검증).
##   R15 챔피언은 weighted_screen_bt 경로였음. canonical(EW) vs weighted(EW) 등가성은 base parity로 검증됨
##   (R12/R15 base 2.6124 == R6 저장 2.6124). 본 companion은 **F-1 uplift(F-1 − plain, 102-only base)** 를
##   R15 uplift(+0.325 = 2.937−2.612)와 대조해 F-1 construction 재현 무결성을 게이트한다(계약·vintage 상쇄).
##
## [사전등록 arms] Ppins_F1_W36_K20 · Ppins_F1_W36_K10 (task 명시 F-1 config 2종) + 102-only 대응 control
##   (Pbase_F1_W36_K20 · Pbase_F1_W36_K10) + parity anchor(Pbase_plain_W36_K20). paired = Ppins_F1 vs Pbase_F1.
## [판정] paired NW-t(lag3) < 2.0 KILL(insider F-1 참여 한계기여 무효) + HARD 3종(cap-w 2.95·oos 0.7·calmar 0.64)
##   + dual-basis(EW-uni 병기). §7b: base=clean canonical(pin vintage), 저장 패널 동월 오염 무관(패널=r6 재사용).
## [실행] 단일스레드·arrow io(2)·pin rawdata·governor 정지·book/05_Production 무변경.
## ─────────────────────────────────────────────────────────────────────────────
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest); library(digest); library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }

OUT <- "outputs/ramp"; RUNTAG <- format(Sys.Date(),"%Y%m%d")
logf <- file.path(".cache", sprintf("_ramp_r9_insider_f1_%s.txt", RUNTAG))
if (file.exists(logf)) try(file.remove(logf), silent=TRUE)
w  <- function(...){ try({ .lc<-file(logf,"a",encoding="UTF-8"); writeLines(paste0(...), .lc); close(.lc) }, silent=TRUE); invisible() }
wf <- function(...){ w(sprintf(...)) }

## ── config (F-1 챔피언 — R15 값 승계) ─────────────────────────────────────────
W36 <- 36L; KPOOL <- c(20L, 10L); CADENCE_ENTRY <- 6L; CADENCE_EXIT <- 3L
EXIT_RANK_BAR <- 30L
TOP_N <- 25L; COST_BPS <- 15; LIQ_MIN <- 2e8
GATE_PT <- 2.95; PAIRED_KILL <- 2.0
N_TRIALS_FAMILY <- as.integer(Sys.getenv("RAMP_R9_NTRIALS", "24"))
R15_BASE_F1 <- 2.937; R15_PLAIN_BASE <- 2.6124; R15_F1_UPLIFT <- R15_BASE_F1 - R15_PLAIN_BASE  # +0.3246

## ── 패널 meta (재사용 — Stage A와 동일) ───────────────────────────────────────
SCORE_P <- file.path(OUT, "insider_factor_scores.parquet")
PANELI_P <- file.path(OUT, "insider_factor_deployzone_active.parquet")
META_P <- file.path(OUT, "insider_panel_meta.json")
ins_meta <- fromJSON(META_P)
stopifnot(isTRUE(ins_meta$pit_ok), !isTRUE(ins_meta$partial_data))
INS_IDS <- ins_meta$factors
wf("=== RAMP R9 Stage B: insider × F-1 챔피언 construction (level36 진입·rank 퇴출·level36 충원) ===")
wf("insider factors: %s | crawl %s~%s | EXIT_RANK_BAR=%d cadence entry=%d exit=%d",
   paste(INS_IDS,collapse=","), ins_meta$crawl_first_ym, ins_meta$crawl_last_ym, EXIT_RANK_BAR, CADENCE_ENTRY, CADENCE_EXIT)

## ── 데이터 (R9 로드 경로 자구동일 + pin vintage) ──────────────────────────────
gd <- as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet", col_select="signal_date"))
sig_dates <- sort(unique(as.Date(gd$signal_date))); rm(gd); n_sig <- length(sig_dates)
RAW_P <- Sys.getenv("R9_RAWDATA_PIN", ".cache/rawdata.parquet"); if(!file.exists(RAW_P)) RAW_P <- ".cache/rawdata.parquet"
wf("[vintage] rawdata source=%s (mtime=%s) | sig months=%d %s~%s", RAW_P,
   tryCatch(as.character(file.info(RAW_P)$mtime), error=function(e)"NA"), n_sig, as.character(sig_dates[1]), as.character(sig_dates[n_sig]))
.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata <- as.data.table(read_parquet(RAW_P, col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
.udates <- sort(unique(rawdata$Date))
.me <- as.Date(vapply(sig_dates, function(d){ v <- .udates[.udates <= d]; if(length(v)) as.character(max(v)) else NA_character_ }, character(1)))
rawdata <- rawdata[Date %in% .me[!is.na(.me)]]
fwd <- build_monthly_forward_returns(rawdata, sig_dates); rm(rawdata)
ewb <- fwd$returns_dt[, .(ew=mean(Ret_1m,na.rm=TRUE)), by=.(date=as.Date(Date))]
RET_DT   <- fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)]
BENCH_DT <- fwd$bench_dt[,.(Date=as.Date(Date), BM_Ret)]
LIQ_DT   <- fwd$liq_dt[,.(Date=as.Date(Date), Ticker, adv)]
invisible(gc())

## ── 패널: base(r6 102) + insider append → Pmat_ext / Pmat_base ────────────────
PANEL_BASE <- as.data.table(read_parquet(file.path(OUT,"r6_factor_deployzone_active.parquet")))
PANEL_BASE[, signal_date := as.Date(signal_date)]; PANEL_BASE <- PANEL_BASE[signal_date %in% sig_dates]
PANEL_INS <- as.data.table(read_parquet(PANELI_P)); PANEL_INS[, signal_date := as.Date(signal_date)]
PANEL_INS <- PANEL_INS[signal_date %in% sig_dates]
stopifnot(identical(sort(names(PANEL_BASE)), sort(names(PANEL_INS))))
PANEL <- rbind(PANEL_BASE, PANEL_INS, fill=TRUE)
BASE_FACS <- sort(unique(PANEL_BASE$factor_id)); EXT_FACS <- sort(unique(PANEL$factor_id))
Pw <- dcast(PANEL, signal_date ~ factor_id, value.var="active_bm"); setorder(Pw, signal_date)
panel_dates <- Pw$signal_date; n_pm <- length(panel_dates)
stopifnot(all(panel_dates == sig_dates[1:n_pm]))
Pmat_ext  <- as.matrix(Pw[, ..EXT_FACS]);  rownames(Pmat_ext)  <- as.character(panel_dates)
Pmat_base <- as.matrix(Pw[, ..BASE_FACS]); rownames(Pmat_base) <- as.character(panel_dates)
wf("panel: base %d + insider %d = ext %d factors | %d panel months", length(BASE_FACS), uniqueN(PANEL_INS$factor_id), length(EXT_FACS), n_pm)

## ── scores (pure z + insider z) → fw_z ────────────────────────────────────────
af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
APPROVED <- af[status=="approved", factor_id]
sc <- as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet",
        col_select=c("signal_date","security_id","factor_id","z")))
sc <- sc[factor_id %in% APPROVED]; sc[, signal_date := as.Date(signal_date)]; sc <- sc[signal_date %in% sig_dates]
sci <- as.data.table(read_parquet(SCORE_P)); sci[, signal_date := as.Date(signal_date)]; sci <- sci[signal_date %in% sig_dates]
sc <- rbind(sc, sci[, .(signal_date, security_id, factor_id, z)])

## ── estimators + gates (R9 자구동일) ──────────────────────────────────────────
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA); mean(x)/sd(x)*sqrt(12) }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
post2017 <- as.Date("2017-01-01")
gates <- function(score_dt, lab){
  cs <- tryCatch(canonical_screen_bt(
        score_dt[,.(Date=as.Date(signal_date), Ticker=security_id, score)],
        RET_DT, BENCH_DT, top_n=TOP_N, cost_bps_oneway=COST_BPS,
        liq_dt=LIQ_DT, liq_min=LIQ_MIN, run_id="r9f1", strategy_id=lab,
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
  .retsew<-sapply(.splits,function(fr){ k<-floor(nrow(pr)*fr)              # EW-uni oos 병기 (dual-basis)
    if(k<12||(nrow(pr)-k)<6) return(NA_real_); .is<-srf(pr$act[1:k]); .oo<-srf(pr$act[(k+1):nrow(pr)])
    if(!is.na(.is)&&.is>0) .oo/.is else NA_real_ })
  retn_ew <- median(.retsew, na.rm=TRUE)
  post_sr <- srf(pr[date>=post2017, act_bm]); post_sr_ew <- srf(pr[date>=post2017, act])
  list(dt=data.table(model=lab, port_t_capwt=pt_bm, port_t_EWuni=pt, oos_retention=retn, oos_ew=retn_ew,
             calmar=cal, post2017_bm_sr=post_sr, post2017_ew_sr=post_sr_ew,
             turnover=cs$turnover_annual, n_months=nrow(pr)),
       pr=pr[,.(date, act_bm, act, ret_net, benchmark_ret)])
}

## ── level36 (trailing NW-t over W36) @ anchors_exit (R9 trailing_portt 자구동일) ─
anchors_exit  <- seq(W36+1L, n_sig-1L, by=CADENCE_EXIT)     # 분기 퇴출 점검
cohortEntry   <- seq(W36+1L, n_sig-1L, by=CADENCE_ENTRY)    # 반기 진입 (⊂ anchors_exit)
stopifnot(all(cohortEntry %in% anchors_exit))
trailing_level36 <- function(M, a){ lo <- a - W36; hi <- a - 1L; if(lo<1L) return(NULL)
  sub <- M[lo:hi, , drop=FALSE]
  apply(sub, 2, function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
    m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }) }
TT_ext <- list(); TT_base <- list()
for(a in anchors_exit){ tv<-trailing_level36(Pmat_ext,a); if(!is.null(tv)) TT_ext[[as.character(a)]]<-tv
                        tb<-trailing_level36(Pmat_base,a); if(!is.null(tb)) TT_base[[as.character(a)]]<-tb }
wf("[level36] computed @ %d exit anchors (cadence %dm) | entry anchors %d (cadence %dm)", length(TT_ext), CADENCE_EXIT, length(cohortEntry), CADENCE_ENTRY)

## ── F-1 챔피언 pool 궤적 (R15 build_pool_traj_fill('level36') 이식) ────────────
build_pool_F1 <- function(TT, K){
  held <- NULL; pool_by_anchor <- list(); ins_hits <- 0L; ins_den <- 0L
  for(a in anchors_exit){
    lvl <- TT[[as.character(a)]]
    if(is.null(lvl)){ pool_by_anchor[[as.character(a)]] <- held; next }
    ranked_lvl <- names(sort(lvl[is.finite(lvl)], decreasing=TRUE))
    is_entry <- a %in% cohortEntry
    if(is_entry || is.null(held)){
      held <- head(ranked_lvl, K)                                        # 진입: top-K by level36
    } else {
      keep <- character(0)
      for(f in held){ r <- match(f, ranked_lvl); lf <- if(f %in% names(lvl)) lvl[[f]] else NA_real_
        if((!is.na(r) && r <= EXIT_RANK_BAR) && (is.finite(lf) && lf >= 0)) keep <- c(keep, f) }
      slots <- K - length(keep)
      fill <- if(slots > 0) head(setdiff(ranked_lvl, keep), slots) else character(0)  # level36 충원
      held <- c(keep, fill)
    }
    pool_by_anchor[[as.character(a)]] <- held
    ins_den <- ins_den + 1L; if(any(held %in% INS_IDS)) ins_hits <- ins_hits + 1L
  }
  attr(pool_by_anchor, "ins_hit_frac") <- if(ins_den>0) ins_hits/ins_den else NA_real_
  pool_by_anchor
}

## ── plain top-K pool (Stage A parity anchor — R9 build_sel_traj/getter 자구동일) ─
build_pool_plain <- function(M, K){
  anchors <- cohortEntry; pool_by_anchor <- list()
  for(a in anchors){ tv <- trailing_level36(M, a); if(is.null(tv)) next
    ord <- names(sort(tv[is.finite(tv)], decreasing=TRUE)); pool_by_anchor[[as.character(a)]] <- head(ord, K) }
  attr(pool_by_anchor, "anchors") <- anchors; pool_by_anchor
}

## ── composite (R9 build_arm_score 자구동일 — pool getter만 상이) ───────────────
POOL_UNION <- character(0)
fw <- NULL
build_arm_score <- function(pool_by_anchor, anchors_for_getter){
  deploy_idx <- (W36+1L):(n_sig-1L); rows <- list()
  for(i in deploy_idx){
    ga <- max(anchors_for_getter[anchors_for_getter <= i]); facs <- pool_by_anchor[[as.character(ga)]]
    facs <- intersect(facs, FW_FACS); if(length(facs)==0) next
    sub <- fw_z[.(sig_dates[i])]; if(nrow(sub)==0) next
    Xz <- sub[, lapply(.SD, zc), .SDcols=facs]; Xm <- as.matrix(Xz); Xm[is.na(Xm)] <- 0
    rows[[as.character(i)]] <- data.table(signal_date=sig_dates[i], security_id=sub$security_id, score=rowMeans(Xm))
  }
  s <- rbindlist(rows); s[, score := zc(score), by=signal_date]; s
}

## build all pools first → union of factors → build fw_z (memory 절약, R9 자구동일)
POOLS <- list()
for(K in KPOOL){
  POOLS[[sprintf("Ppins_F1_W36_K%d", K)]] <- list(pool=build_pool_F1(TT_ext, K),  anch=anchors_exit)
  POOLS[[sprintf("Pbase_F1_W36_K%d", K)]] <- list(pool=build_pool_F1(TT_base, K), anch=anchors_exit)
}
POOLS[["Pbase_plain_W36_K20"]] <- list(pool=build_pool_plain(Pmat_base, 20L), anch=cohortEntry)  # parity anchor
POOLS[["Ppins_plain_W36_K20"]] <- list(pool=build_pool_plain(Pmat_ext, 20L),  anch=cohortEntry)   # 참고
pool_union <- sort(unique(unlist(lapply(POOLS, function(x) unlist(x$pool)))))
fw <- dcast(sc[factor_id %in% pool_union], signal_date + security_id ~ factor_id, value.var="z")
FW_FACS <- intersect(pool_union, names(fw))
fw_z <- fw[, c("signal_date","security_id", FW_FACS), with=FALSE]; setkey(fw_z, signal_date)
rm(sc, sci, fw); invisible(gc())

## ── insider F-1 참여 진단 ─────────────────────────────────────────────────────
for(K in KPOOL) wf("[F-1 참여진단 K=%d] INS in pool 비율(ext)=%.2f", K, attr(POOLS[[sprintf("Ppins_F1_W36_K%d",K)]]$pool, "ins_hit_frac"))

## ── 측정 ──────────────────────────────────────────────────────────────────────
wf("\n=== 측정 [F-1 챔피언, cap-w authoritative] ===")
RES <- list(); PR <- list()
for(lab in names(POOLS)){
  gg <- gates(build_arm_score(POOLS[[lab]]$pool, POOLS[[lab]]$anch), lab)
  if(!is.null(gg)){ RES[[lab]]<-gg$dt; PR[[lab]]<-gg$pr }
  wf("  [%-22s] pt_capwt=%+.3f pt_EWuni=%+.3f oos=%+.3f oos_ew=%+.3f calmar=%+.3f post17=%+.3f TO=%.1f n=%d",
     lab, if(!is.null(gg)) gg$dt$port_t_capwt else NA, if(!is.null(gg)) gg$dt$port_t_EWuni else NA,
     if(!is.null(gg)) gg$dt$oos_retention else NA, if(!is.null(gg)) gg$dt$oos_ew else NA,
     if(!is.null(gg)) gg$dt$calmar else NA, if(!is.null(gg)) gg$dt$post2017_bm_sr else NA,
     if(!is.null(gg)) gg$dt$turnover else NA, if(!is.null(gg)) gg$dt$n_months else 0L)
}
TAB <- rbindlist(RES, fill=TRUE)

## ── F-1 construction parity (uplift 재현) ─────────────────────────────────────
plain_base <- TAB[model=="Pbase_plain_W36_K20", port_t_capwt]
f1_base    <- TAB[model=="Pbase_F1_W36_K20", port_t_capwt]
uplift_measured <- f1_base - plain_base
uplift_ok <- is.finite(uplift_measured) && abs(uplift_measured - R15_F1_UPLIFT) < 0.20   # 계약·vintage 상쇄 후 tol
wf("\n=== F-1 construction parity (uplift = F-1 − plain, 102-only base) ===")
wf("  Pbase_plain_W36_K20 cap-w=%.4f (Stage A 2.67 대조) | Pbase_F1_W36_K20 cap-w=%.4f", plain_base, f1_base)
wf("  measured uplift=%+.4f vs R15 uplift(2.937−2.612)=%+.4f -> |Δ|=%.4f construction_parity_ok=%s (tol 0.20)",
   uplift_measured, R15_F1_UPLIFT, abs(uplift_measured-R15_F1_UPLIFT), uplift_ok)
if(!uplift_ok) w("  ★ WARNING: F-1 construction parity 미달 — F-1 arm 라벨 강등(측정 신뢰 저하)")

## ── paired: Ppins_F1 vs Pbase_F1 (insider F-1 참여 한계기여) ──────────────────
pair1 <- function(la, lb){ if(is.null(PR[[la]])||is.null(PR[[lb]])) return(NULL)
  m <- merge(PR[[la]][,.(date,a=act_bm)], PR[[lb]][,.(date,b=act_bm)], by="date"); d <- m$a-m$b
  me <- merge(PR[[la]][,.(date,a=act)], PR[[lb]][,.(date,b=act)], by="date"); de <- me$a-me$b
  data.table(model=la, base=lb, mean_diff_ann=mean(d,na.rm=TRUE)*12, paired_t_capwt=nwt(d), paired_t_EWuni=nwt(de), n=nrow(m)) }
paired <- list()
wf("\n=== paired NW-t lag3 (Ppins_F1 vs Pbase_F1 — insider F-1 참여 한계기여) ===")
for(K in KPOOL){
  p <- pair1(sprintf("Ppins_F1_W36_K%d",K), sprintf("Pbase_F1_W36_K%d",K))
  if(!is.null(p)){ paired[[length(paired)+1]] <- p
    wf("  [ins F-1 참여 K=%d] Δ(ann)=%+.4f paired_t: cap-w=%+.2f EW-uni=%+.2f (n=%d)", K, p$mean_diff_ann, p$paired_t_capwt, p$paired_t_EWuni, p$n) }
}
PAIRED <- rbindlist(paired, fill=TRUE)

## ── KILL + HARD 게이트 ────────────────────────────────────────────────────────
maxp <- if(nrow(PAIRED)) suppressWarnings(max(PAIRED$paired_t_capwt, na.rm=TRUE)) else NA
KILL <- !(is.finite(maxp) && maxp >= PAIRED_KILL)
any_grad <- any(is.finite(TAB$port_t_capwt) & TAB$port_t_capwt>=GATE_PT & grepl("^Ppins_F1_", TAB$model))
wf("\n=== KILL gate (사전등록 paired>=%.1f) ===", PAIRED_KILL)
wf("  max paired (Ppins_F1 vs Pbase_F1) = %+.2f -> KILL(insider F-1 참여 무효)=%s", maxp, KILL)
wf("  graduation (any Ppins_F1 HARD PORT_t>=%.2f) = %s", GATE_PT, any_grad)
wf("\n=== HARD 게이트 (capwt 2.95 / oos 0.7 / calmar 0.64) ===")
for(i in seq_len(nrow(TAB))){ r<-TAB[i]
  p<-c(port_t=isTRUE(r$port_t_capwt>=2.95), oos=isTRUE(r$oos_retention>=0.7), cal=isTRUE(r$calmar>=0.64))
  wf("  [%-22s] pt=%+.3f %s oos=%+.3f %s cal=%+.3f %s -> %s", r$model, r$port_t_capwt, ifelse(p["port_t"],"v","x"),
     r$oos_retention, ifelse(p["oos"],"v","x"), r$calmar, ifelse(p["cal"],"v","x"), ifelse(all(p),"GRADUATION","미달")) }

## ── 저장 ──────────────────────────────────────────────────────────────────────
res <- list(mode="RAMP", round="R9_stageB_F1", construction="F-1 champion (level36 entry/rank exit/level36 fill, R15 이식)",
  results=TAB, paired=PAIRED, kill=KILL, any_graduation=any_grad, max_paired=maxp,
  construction_parity=list(plain_base=plain_base, f1_base=f1_base, uplift_measured=uplift_measured,
    r15_uplift=R15_F1_UPLIFT, ok=uplift_ok, stageA_pbase_plain=2.67, r15_base_f1=R15_BASE_F1),
  insider_f1_participation=setNames(lapply(KPOOL, function(K) attr(POOLS[[sprintf("Ppins_F1_W36_K%d",K)]]$pool,"ins_hit_frac")), paste0("K",KPOOL)),
  n_trials_family=N_TRIALS_FAMILY, n_sig=n_sig, date_range=as.character(range(sig_dates)),
  vintage_pin=RAW_P, as_of_date=RUNTAG, generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
  source_version="RAMP_R9_stageB_v1", security_id="Ticker->factor_id z (pure/insider z=Z_Score_Aligned)")
saveRDS(list(res=res, PR=PR, TAB=TAB, PAIRED=PAIRED), file.path(".cache", sprintf("_ramp_r9_insider_f1_%s.rds", RUNTAG)))
write_parquet(TAB, file.path(OUT, sprintf("r9_insider_f1_gates_%s.parquet", RUNTAG)))
if(nrow(PAIRED)) write_parquet(PAIRED, file.path(OUT, sprintf("r9_insider_f1_paired_%s.parquet", RUNTAG)))
write_json(res, file.path(OUT, sprintf("r9_insider_f1_summary_%s.json", RUNTAG)), auto_unbox=TRUE, pretty=TRUE, digits=4)
cat(sprintf("R9_F1_DONE kill=%s any_grad=%s max_paired=%.2f uplift_ok=%s(meas %.3f vs r15 %.3f) log=%s\n",
    KILL, any_grad, maxp, uplift_ok, uplift_measured, R15_F1_UPLIFT, logf))
cat(readLines(logf, encoding="UTF-8"), sep="\n")
