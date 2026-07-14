## run_ramp_r9_insider_ext.R — FQ-019/R9: PORT_t-정렬 선별 × insider 확장 패널 (armed 하네스)
## ─────────────────────────────────────────────────────────────────────────────
## 진입: run_ramp_r6_portt_boruta.R 의 config 분기(RAMP_R6_INSIDER=1)에서 위임됨.
##   기존 R6 재현 경로는 불변 — 본 파일은 확장 경로 전용 (회귀 금지 설계).
##
## [frontier] 선별-규율 아크(R4~R7) 유일 잔존 = "PORT_t-정렬 선별 × 비-수익(insider) 패널"
##   (FQ-014 revival_signal ① / FQ-015 next_action / memory project-selection-discipline-arc).
##   구조: insider 파생 팩터(INS01~03)가 standalone이 아니라 **선별 풀에 참여** — FQ-001
##   ev_downgraded(standalone DEAD_PRELIM)와 구분되는 결합 가설.
##
## [2-모드]
##   SMOKE (기본): 크롤 부분창(현재 2005-2019)에서 end-to-end 배관 검증만.
##     - 산출 스키마 / parity(1팩터 canonical 대조 + base-arm vs R6 저장 시계열 대조) / PIT assert.
##     - ★성과 수치는 로그에만(SMOKE_ONLY 라벨). 판정·L-code·텔레그램 발화 절대 금지
##       (반쪽 창 증거력 없음 — post-2017 벽 검증 불가). 산출물은 .cache/ 에만.
##   FULL (RAMP_R9_FULL=1): 크롤 완결 후 본측정. fail-closed —
##     체크포인트 연속성(200501~R9_REQ_LAST_YM, gap 0) 미충족 시 즉시 stop.
##     패널 자동 재빌드(build_insider_factor_panel.R) 후 사전등록 4 config 측정.
##
## [사전등록 — FULL, 상세 04_Research/factor_selection_program/r9_insider_selection_armed_spec.md]
##   arms: Ppins_WxKy = trailing PORT_t top-K 선별 (기질 = 102+INS 확장 패널)
##   controls: Pbase_WxKy = 동일 선별, 기질 = 102-only (비-trial, insider 한계기여 격리)
##   paired: Ppins vs Pbase (per config, NW-t lag3)
##   KILL: 전 config paired < 2.0 → insider 풀-참여 무효 (선별-정렬 아크 종결 재료)
##   Boruta arm 없음 — Boruta-on-PORT_t-pool 음-소진 (FQ-014, 재시도 금지)
##   n_trials family 연속 회계: R4(4)+R5(6)+R6(6)+R7(4)=20 → R9 +4 = 24
##
## [측정 산식] R6 gates()/trailing_portt/build_arm_score 복제 (R4→R6 복제 선례 패턴).
##   cap-w authoritative + HARD 3종 + DSR. 실측-only. 단일스레드.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest); library(digest); library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns
source("02_Infrastructure/contracts/canonical_screen_bt.R")
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }

## ── 모드 결정 (fail-closed) ──────────────────────────────────────────────────
FULL_MODE  <- nzchar(Sys.getenv("RAMP_R9_FULL",""))
REQ_LAST_YM <- Sys.getenv("R9_REQ_LAST_YM", "202604")   # 본측정 최소 크롤 커버리지 (armed spec)
CKDIR <- ".cache/dart/insider_backfill"
ck_yms <- sort(gsub("\\.csv$","",list.files(CKDIR, pattern="^\\d{6}\\.csv$")))
stopifnot(length(ck_yms) > 0)
.ymseq <- function(a,b){ d<-seq(as.Date(paste0(a,"01"),"%Y%m%d"), as.Date(paste0(b,"01"),"%Y%m%d"), by="month"); format(d,"%Y%m") }
ck_gaps <- setdiff(.ymseq(ck_yms[1], ck_yms[length(ck_yms)]), ck_yms)
crawl_complete <- (length(ck_gaps)==0L) && (ck_yms[1] <= "200501") && (ck_yms[length(ck_yms)] >= REQ_LAST_YM)
if (FULL_MODE && !crawl_complete) {
  stop(sprintf("[R9] FULL 모드 거부 (fail-closed): 크롤 미완결 — last=%s(<%s 필요) gaps=%d. 부분 데이터 본측정 금지 (FQ-019).",
               ck_yms[length(ck_yms)], REQ_LAST_YM, length(ck_gaps)))
}
SMOKE <- !FULL_MODE
MODE_LAB <- if (SMOKE) "SMOKE_ONLY" else "FULL"

RUNTAG <- if (SMOKE) sprintf("smoke_%s", format(Sys.Date(),"%Y%m%d")) else format(Sys.Date(),"%Y%m%d")
OUT <- "outputs/ramp"
logf <- file.path(".cache", sprintf("_ramp_r9_insider_%s.txt", RUNTAG))
## [FQ-019 fix 2026-07-15] append-per-call 로거 — sourced 스크립트(build_insider_factor_panel.R)가
##   global `con` 변수를 clobber해 원 log 연결이 gc-close되며 wf() "invalid connection" halt(2026-07-14)한
##   버그 우회. persistent 연결 미보유(clobber 불가) + try()로 감싸 로그 실패가 측정 루프를 절대 halt시키지 않음.
if (file.exists(logf)) try(file.remove(logf), silent=TRUE)
w  <- function(...){ try({ .lc <- file(logf,"a",encoding="UTF-8"); writeLines(paste0(...), .lc); close(.lc) }, silent=TRUE); invisible() }
wf <- function(...){ w(sprintf(...)) }
wf("=== RAMP R9: PORT_t-정렬 선별 × insider 확장 패널 [%s] ===", MODE_LAB)
if (SMOKE) w("★SMOKE_ONLY — 배관 검증 한정. 아래 모든 성과 수치는 부분창(크롤 진행중) 산출로 증거력 없음.")
if (SMOKE) w("★판정·graduation·L-code·텔레그램 발화 금지. 산출물은 .cache/ 에만 기록.")
wf("crawl: %s~%s (%d개월, gap=%d) | complete(>=%s)=%s", ck_yms[1], ck_yms[length(ck_yms)],
   length(ck_yms), length(ck_gaps), REQ_LAST_YM, crawl_complete)

## ── insider 패널 준비 (FULL: 항상 재빌드 = 완결 크롤 소비 / SMOKE: 없으면 빌드) ──
SCORE_P <- file.path(OUT, "insider_factor_scores.parquet")
PANELI_P <- file.path(OUT, "insider_factor_deployzone_active.parquet")
META_P <- file.path(OUT, "insider_panel_meta.json")
need_build <- FULL_MODE || nzchar(Sys.getenv("RAMP_R9_FORCE_PANEL","")) ||
              !file.exists(SCORE_P) || !file.exists(PANELI_P)
if (need_build) {
  w("[R9] insider 패널 (재)빌드: build_insider_factor_panel.R")
  source("02_Infrastructure/ramp/build_insider_factor_panel.R", encoding="UTF-8")
  setwd(QM)
}
ins_meta <- fromJSON(META_P)
stopifnot(isTRUE(ins_meta$pit_ok))
if (FULL_MODE && isTRUE(ins_meta$partial_data)) stop("[R9] FULL 모드인데 패널 meta partial_data=TRUE — 중단")

## ── 사전등록 config ──────────────────────────────────────────────────────────
WINDOWS <- if (SMOKE) c(36L) else c(36L, 60L)
KPOOL   <- if (SMOKE) c(20L) else c(10L, 20L)
CADENCE <- 6L                                    # R6 고정 (base-arm parity 대조 가능 조건)
TOP_N <- 25L; COST_BPS <- 15; LIQ_MIN <- 2e8
GATE_PT <- 2.95; PAIRED_KILL <- 2.0
N_TRIALS_R9 <- length(WINDOWS)*length(KPOOL)     # FULL=4 / SMOKE=1(비-trial, 배관)
N_TRIALS_FAMILY <- as.integer(Sys.getenv("RAMP_R9_NTRIALS", "24"))  # R4~R7=20 + R9 4
INS_IDS <- ins_meta$factors
PREREG <- list(mode="RAMP", round="R9", run_mode=MODE_LAB,
  mechanism="trailing_realized_PORTt_pool_selection x insider-extended substrate (102+INS participation)",
  frontier_of="selection-discipline arc R4~R7 잔존 frontier ① (FQ-014 revival / FQ-015 next_action)",
  distinct_from="FQ-001 standalone insider (DEAD_PRELIM) — 본 건은 풀-참여 결합",
  substrate_ext="102 approved + INS01~03 (insider_factor_deployzone_active.parquet append)",
  substrate_base="102 approved only (Pbase controls — insider 한계기여 격리)",
  arms=list(Ppins="top-K pool EW rotation on extended panel"),
  controls=list(Pbase="동일 선별, 102-only 기질 (비-trial)"),
  paired="Ppins_WxKy vs Pbase_WxKy per config, NW-t lag3",
  kill_rule=sprintf("전 config paired < %.1f -> insider 풀-참여 무효", PAIRED_KILL),
  no_boruta="Boruta-on-PORT_t-pool 음-소진 (FQ-014 재시도 금지) — arm 없음",
  windows=WINDOWS, kpool=KPOOL, cadence_months=CADENCE,
  top_n=TOP_N, cost_bps_oneway=COST_BPS, liq_min=LIQ_MIN,
  gate_hard=c(port_t_capwt=GATE_PT, oos_retention=0.7, calmar=0.64, dsr=0.5),
  n_trials_r9=N_TRIALS_R9, n_trials_family=N_TRIALS_FAMILY, selection_type="sweep",
  crawl_coverage=sprintf("%s~%s gaps=%d", ck_yms[1], ck_yms[length(ck_yms)], length(ck_gaps)),
  insider_factors=INS_IDS,
  pit="insider 신호월 m=rcept 접수월, forward=m+1 (C5 정합) + 패널 truncation-invariance assert PASS",
  honest_prior="FQ-001 standalone DEAD_PRELIM / return-substrate post-2017 감쇠 벽(R6~R7) — 결합 EV 보수적",
  as_of_date=format(Sys.Date(),"%Y-%m-%d"), source_version="RAMP_R9_v1")
CFG_HASH <- substr(digest::digest(PREREG[setdiff(names(PREREG),"run_mode")], algo="sha256"),1,16)
PREREG$config_hash <- CFG_HASH; PREREG$generated_at <- format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z")
if (!SMOKE) write_json(PREREG, file.path(OUT, sprintf("r9_insider_prereg_%s.json",RUNTAG)), auto_unbox=TRUE, pretty=TRUE, digits=6)
wf("config_hash=%s | windows={%s} K={%s} cadence=%dm | n_trials R9=%d family=%d",
   CFG_HASH, paste(WINDOWS,collapse=","), paste(KPOOL,collapse=","), CADENCE, N_TRIALS_R9, N_TRIALS_FAMILY)

## ── 데이터 (R6 로드 경로 복제 + 창 절단) ─────────────────────────────────────
af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
APPROVED <- af[status=="approved", factor_id]
fam_of <- function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V") "Value" else if(p1=="M"&&p!="MA") "Momentum" else if(p1=="Q") "Quality"
  else if(p1=="D") "LowRisk" else if(p1=="L") "Size_Liquidity" else if(p1=="S"&&p!="SE") "Size_Liquidity"
  else if(p1=="R") "Reversal" else if(p=="GR") "Growth_Profit" else if(p=="AC") "Accruals"
  else if(p1=="C"&&p!="CR") "Consensus" else if(p=="CR") "Credit" else if(p=="IN") "Growth_Profit"
  else if(p=="XF") "Composite" else if(p=="MA") "Macro" else if(p1=="T") "Size_Liquidity" else "Composite" }
FAC_FAM <- c(setNames(sapply(APPROVED, fam_of), APPROVED), setNames(rep("Insider",length(INS_IDS)), INS_IDS))

gd <- as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet", col_select="signal_date"))
sig_dates_full <- sort(unique(as.Date(gd$signal_date))); rm(gd)
## 창: SMOKE = 크롤 최종월 말일까지 (현재 2019-12) / FULL = 전체
smoke_end <- as.Date(paste0(ck_yms[length(ck_yms)], "01"), "%Y%m%d")
smoke_end <- seq(smoke_end, by="month", length.out=2)[2] - 1
sig_dates <- if (SMOKE) sig_dates_full[sig_dates_full <= smoke_end] else sig_dates_full
n_sig <- length(sig_dates)
wf("window: %s~%s (%d개월)%s", as.character(sig_dates[1]), as.character(sig_dates[n_sig]), n_sig,
   if(SMOKE) sprintf(" [부분창 절단 @크롤말 %s]", as.character(smoke_end)) else "")

.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
.udates <- sort(unique(rawdata$Date))
.me <- as.Date(vapply(sig_dates, function(d){ v <- .udates[.udates <= d]
  if(length(v)) as.character(max(v)) else NA_character_ }, character(1)))
rawdata <- rawdata[Date %in% .me[!is.na(.me)]]
fwd <- build_monthly_forward_returns(rawdata, sig_dates); rm(rawdata)
post2017 <- as.Date("2017-01-01")
ewb <- fwd$returns_dt[, .(ew=mean(Ret_1m,na.rm=TRUE)), by=.(date=as.Date(Date))]
RET_DT   <- fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)]
BENCH_DT <- fwd$bench_dt[,.(Date=as.Date(Date), BM_Ret)]
LIQ_DT   <- fwd$liq_dt[,.(Date=as.Date(Date), Ticker, adv)]
invisible(gc())

## ── 패널: base(r6 102 재사용) + insider append ──────────────────────────────
PANEL_BASE <- as.data.table(read_parquet(file.path(OUT,"r6_factor_deployzone_active.parquet")))
PANEL_BASE[, signal_date := as.Date(signal_date)]; PANEL_BASE <- PANEL_BASE[signal_date %in% sig_dates]
PANEL_INS <- as.data.table(read_parquet(PANELI_P))
PANEL_INS[, signal_date := as.Date(signal_date)]; PANEL_INS <- PANEL_INS[signal_date %in% sig_dates]
stopifnot(identical(sort(names(PANEL_BASE)), sort(names(PANEL_INS))))   # 스키마 append 계약
PANEL <- rbind(PANEL_BASE, PANEL_INS, fill=TRUE)
BASE_FACS <- sort(unique(PANEL_BASE$factor_id)); EXT_FACS <- sort(unique(PANEL$factor_id))
wf("panel: base %d factors + insider %d = ext %d | rows %d | ins months %d (%s~%s)",
   length(BASE_FACS), uniqueN(PANEL_INS$factor_id), length(EXT_FACS), nrow(PANEL),
   uniqueN(PANEL_INS$signal_date), as.character(min(PANEL_INS$signal_date)), as.character(max(PANEL_INS$signal_date)))

Pw <- dcast(PANEL, signal_date ~ factor_id, value.var="active_bm"); setorder(Pw, signal_date)
panel_dates <- Pw$signal_date; n_pm <- length(panel_dates)
stopifnot(all(panel_dates == sig_dates[1:n_pm]))
Pmat_ext  <- as.matrix(Pw[, ..EXT_FACS]);  rownames(Pmat_ext)  <- as.character(panel_dates)
Pmat_base <- as.matrix(Pw[, ..BASE_FACS]); rownames(Pmat_base) <- as.character(panel_dates)

## ── scores (pure z + insider z) ──────────────────────────────────────────────
sc <- as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet",
        col_select=c("signal_date","security_id","factor_id","z")))
sc <- sc[factor_id %in% APPROVED]; sc[, signal_date := as.Date(signal_date)]
sc <- sc[signal_date %in% sig_dates]
sci <- as.data.table(read_parquet(SCORE_P)); sci[, signal_date := as.Date(signal_date)]
## PIT assert (필터링 전 원본): insider 신호 최종월 <= 크롤 최종월 말일 (미래 신호 부재)
stopifnot(max(sci$signal_date) <= smoke_end)
stopifnot(all(sci$signal_date %in% sig_dates_full))
sci <- sci[signal_date %in% sig_dates]
sc <- rbind(sc, sci[, .(signal_date, security_id, factor_id, z)])
POOL_EXT  <- sort(intersect(EXT_FACS,  unique(sc$factor_id)))
POOL_BASE <- sort(intersect(BASE_FACS, unique(sc$factor_id)))

## ── 게이트 계산기 + 선별 (R6 복제 — byte-등가 산식) ──────────────────────────
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA); mean(x)/sd(x)*sqrt(12) }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
gates <- function(score_dt, lab, n_trials_dsr=N_TRIALS_FAMILY){
  cs <- tryCatch(canonical_screen_bt(
        score_dt[,.(Date=as.Date(signal_date), Ticker=security_id, score)],
        RET_DT, BENCH_DT, top_n=TOP_N, cost_bps_oneway=COST_BPS,
        liq_dt=LIQ_DT, liq_min=LIQ_MIN, run_id="r9", strategy_id=lab,
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
trailing_portt <- function(M, W, a_idx){
  lo <- a_idx - W; hi <- a_idx - 1L
  if(lo < 1L) return(NULL)
  sub <- M[lo:hi, , drop=FALSE]
  apply(sub, 2, function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
    m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) })
}
build_sel_traj <- function(M, windows, kpool){
  out <- list()
  for(W in windows){
    anchors <- seq(W+1L, n_sig-1L, by=CADENCE); tj <- list()
    for(a in anchors){
      tv <- trailing_portt(M, W, a); if(is.null(tv)) next
      ord <- names(sort(tv[is.finite(tv)], decreasing=TRUE))
      tj[[as.character(a)]] <- list(anchor_idx=a, anchor_date=as.character(sig_dates[a]),
        trailing_t=tv, ranked=ord, pool=setNames(lapply(kpool, function(k) head(ord, k)), paste0("K",kpool)))
    }
    out[[as.character(W)]] <- list(anchors=anchors, traj=tj)
  }
  out
}
sel_ext  <- build_sel_traj(Pmat_ext,  WINDOWS, KPOOL)
sel_base <- build_sel_traj(Pmat_base, WINDOWS, KPOOL)

## insider 풀-참여 진단 (배관 검증 — 판정 아님)
for(W in WINDOWS){
  tjs <- sel_ext[[as.character(W)]]$traj
  hitK <- sapply(KPOOL, function(k) mean(sapply(tjs, function(x) any(x$pool[[paste0("K",k)]] %in% INS_IDS))))
  tvals <- unlist(lapply(tjs, function(x) x$trailing_t[INS_IDS]))
  wf("[참여진단 W=%d] anchors=%d | INS in pool 비율: %s | INS trailing NW-t 유한 %d/%d mean=%+.2f",
     W, length(tjs), paste(sprintf("K%d=%.2f", KPOOL, hitK), collapse=" "),
     sum(is.finite(tvals)), length(tvals), mean(tvals, na.rm=TRUE))
}

## ── composite wide (풀 합집합 컬럼만 — 메모리 절약) ──────────────────────────
pool_union <- sort(unique(c(
  unlist(lapply(WINDOWS, function(W) unlist(lapply(sel_ext[[as.character(W)]]$traj,  function(x) unlist(x$pool))))),
  unlist(lapply(WINDOWS, function(W) unlist(lapply(sel_base[[as.character(W)]]$traj, function(x) unlist(x$pool))))))))
fw <- dcast(sc[factor_id %in% pool_union], signal_date + security_id ~ factor_id, value.var="z")
FW_FACS <- intersect(pool_union, names(fw))
fw_z <- fw[, c("signal_date","security_id", FW_FACS), with=FALSE]; setkey(fw_z, signal_date)
rm(sc, sci, fw); invisible(gc())

build_arm_score <- function(W, facs_getter){
  anchors <- seq(W+1L, n_sig-1L, by=CADENCE); deploy_idx <- (W+1L):(n_sig-1L); rows <- list()
  for(i in deploy_idx){
    ga <- max(anchors[anchors <= i]); facs <- intersect(facs_getter(W, ga), FW_FACS)
    if(length(facs)==0) next
    sub <- fw_z[.(sig_dates[i])]; if(nrow(sub)==0) next
    Xz <- sub[, lapply(.SD, zc), .SDcols=facs]; Xm <- as.matrix(Xz); Xm[is.na(Xm)] <- 0
    rows[[as.character(i)]] <- data.table(signal_date=sig_dates[i], security_id=sub$security_id, score=rowMeans(Xm))
  }
  s <- rbindlist(rows); s[, score := zc(score), by=signal_date]; s
}
getter_of <- function(traj, k) function(W, ga) traj[[as.character(W)]]$traj[[as.character(ga)]]$pool[[paste0("K",k)]]

## ── 측정: Ppins(ext) + Pbase(control) ────────────────────────────────────────
wf("\n=== 측정 [%s] (cap-w authoritative — %s) ===", MODE_LAB,
   if(SMOKE) "수치는 배관 점검용, 증거력 없음" else "사전등록 본측정")
RES <- list(); PR <- list()
for(W in WINDOWS) for(k in KPOOL){
  for(arm in c("Ppins","Pbase")){
    traj <- if(arm=="Ppins") sel_ext else sel_base
    lab <- sprintf("%s_W%d_K%d", arm, W, k)
    gg <- gates(build_arm_score(W, getter_of(traj, k)), lab)
    if(!is.null(gg)){ RES[[lab]]<-gg$dt; PR[[lab]]<-gg$pr }
    wf("  [%s%s] pt_capwt=%+.2f oos=%+.2f calmar=%+.2f DSR=%+.2f n=%d",
       if(SMOKE) "SMOKE_ONLY " else "", lab,
       if(!is.null(gg)) gg$dt$port_t_capwt else NA, if(!is.null(gg)) gg$dt$oos_retention else NA,
       if(!is.null(gg)) gg$dt$calmar else NA, if(!is.null(gg)) gg$dt$dsr else NA,
       if(!is.null(gg)) gg$dt$n_months else 0L)
  }
}
TAB <- rbindlist(RES, fill=TRUE)

## ── paired: Ppins vs Pbase (insider 한계기여 격리) ───────────────────────────
pair1 <- function(la, lb, kind){
  if(is.null(PR[[la]]) || is.null(PR[[lb]])) return(NULL)
  m <- merge(PR[[la]][,.(date,a=act_bm)], PR[[lb]][,.(date,b=act_bm)], by="date")
  d <- m$a - m$b; data.table(model=la, base=lb, kind=kind, mean_diff_ann=mean(d,na.rm=TRUE)*12, paired_t=nwt(d), n=nrow(m))
}
paired <- list()
wf("\n=== paired NW-t lag3 [%s] ===", MODE_LAB)
for(W in WINDOWS) for(k in KPOOL){
  p <- pair1(sprintf("Ppins_W%d_K%d",W,k), sprintf("Pbase_W%d_K%d",W,k), "insider_participation")
  if(!is.null(p)){ paired[[length(paired)+1]] <- p
    wf("  [%sins참여] %-16s vs %-16s Δ(ann)=%+.4f paired_t=%+.2f (n=%d)",
       if(SMOKE) "SMOKE_ONLY " else "", p$model, p$base, p$mean_diff_ann, p$paired_t, p$n) }
}
PAIRED <- rbindlist(paired, fill=TRUE)

## ── SMOKE 전용: 배관 검증 3종 ────────────────────────────────────────────────
smoke_checks <- NULL
if (SMOKE) {
  w("\n=== SMOKE 배관 검증 ===")
  ## (a) 산출 스키마
  sch_ok <- identical(sort(names(TAB)), sort(c("model","port_t_EWuni","port_t_capwt","oos_retention",
              "calmar","dsr","post2017_bm_sr","full_bm_sr","turnover","n_months")))
  wf("  [schema] gates 테이블 10컬럼: %s", ifelse(sch_ok,"PASS","FAIL"))
  ## (b) parity 1: 1팩터 canonical 대조 — 하네스 내 재계산 vs 패널 빌더 산출
  fid0 <- INS_IDS[1]
  s0 <- as.data.table(read_parquet(SCORE_P)); s0[, signal_date := as.Date(signal_date)]
  s0 <- s0[factor_id==fid0 & signal_date %in% sig_dates, .(Date=signal_date, Ticker=security_id, score=z)][!is.na(score)]
  cs0 <- canonical_screen_bt(s0, RET_DT, BENCH_DT, top_n=TOP_N, cost_bps_oneway=COST_BPS,
           liq_dt=LIQ_DT, liq_min=LIQ_MIN, run_id="r9parity", strategy_id=fid0, diag_dual_basis=FALSE)
  pr0 <- as.data.table(cs0$period_returns)[, .(date=as.Date(date), fresh=ret_net-benchmark_ret)]
  m0 <- merge(pr0, PANEL_INS[factor_id==fid0, .(date=signal_date, stored=active_bm)], by="date")
  par1_delta <- if(nrow(m0)) max(abs(m0$fresh - m0$stored), na.rm=TRUE) else NA
  par1_ok <- is.finite(par1_delta) && par1_delta < 1e-10
  wf("  [parity-1] %s canonical 재계산 vs 패널저장: n=%d max|Δ|=%.2e %s", fid0, nrow(m0), par1_delta, ifelse(par1_ok,"PASS","FAIL"))
  ## (c) parity 2: base-arm(102-only) vs R6 저장 Ppure 시계열 (기계 복제 무결성)
  par2_delta <- NA; par2_ok <- NA; par2_n <- 0L
  r6c <- ".cache/_ramp_r6_20260711.rds"
  if (file.exists(r6c) && 36L %in% WINDOWS && 20L %in% KPOOL) {
    r6 <- readRDS(r6c); r6p <- r6$PR[["Ppure_W36_K20"]]; fb <- PR[["Pbase_W36_K20"]]
    if (!is.null(r6p) && !is.null(fb)) {
      mm <- merge(r6p[,.(date,r6=act_bm)], fb[,.(date,r9=act_bm)], by="date")
      par2_n <- nrow(mm); par2_delta <- if(par2_n) max(abs(mm$r6-mm$r9), na.rm=TRUE) else NA
      par2_ok <- is.finite(par2_delta) && par2_delta < 1e-8
    }
    wf("  [parity-2] Pbase_W36_K20 vs R6 Ppure_W36_K20 (겹침월): n=%d max|Δ|=%.2e %s",
       par2_n, par2_delta, ifelse(isTRUE(par2_ok),"PASS", ifelse(is.na(par2_ok),"SKIP","FAIL")))
  } else w("  [parity-2] SKIP (R6 rds 없음 또는 config 불일치)")
  ## (d) PIT assert 집계
  pit_ok_all <- isTRUE(ins_meta$pit_ok) && (max(as.Date(PANEL_INS$signal_date)) <= smoke_end)
  wf("  [PIT] 패널 truncation-invariance=%s | ins 신호 최종=%s <= 크롤말 %s: %s",
     ins_meta$pit_ok, as.character(max(PANEL_INS$signal_date)), as.character(smoke_end),
     ifelse(pit_ok_all,"PASS","FAIL"))
  smoke_checks <- list(schema_ok=sch_ok, parity1_factor=fid0, parity1_max_delta=par1_delta, parity1_ok=par1_ok,
                       parity2_n=par2_n, parity2_max_delta=par2_delta, parity2_ok=par2_ok, pit_ok=pit_ok_all)
  SMOKE_PASS <- sch_ok && par1_ok && (isTRUE(par2_ok) || is.na(par2_ok)) && pit_ok_all
  wf("  => SMOKE %s", ifelse(SMOKE_PASS, "PASS (배관 검증 완료 — armed)", "FAIL"))
}

## ── KILL/게이트 (FULL만 발화 — SMOKE는 로그 수치만) ──────────────────────────
maxp <- if(nrow(PAIRED)) suppressWarnings(max(PAIRED$paired_t, na.rm=TRUE)) else NA
if (!SMOKE) {
  KILL <- !(is.finite(maxp) && maxp >= PAIRED_KILL)
  any_grad <- any(is.finite(TAB$port_t_capwt) & TAB$port_t_capwt>=GATE_PT & grepl("^Ppins_", TAB$model))
  wf("\n=== KILL gate (사전등록 paired>=%.1f) ===", PAIRED_KILL)
  wf("  max paired (Ppins vs Pbase) = %+.2f -> KILL(insider 풀-참여 무효)=%s", maxp, KILL)
  wf("  graduation (any Ppins HARD PORT_t>=%.2f) = %s", GATE_PT, any_grad)
  wf("\n=== HARD 게이트 (capwt 2.95 / oos 0.7 / calmar 0.64 / DSR 0.5, family n_trials=%d) ===", N_TRIALS_FAMILY)
  for(i in seq_len(nrow(TAB))){ r<-TAB[i]
    p<-c(port_t=isTRUE(r$port_t_capwt>=2.95), oos=isTRUE(r$oos_retention>=0.7), cal=isTRUE(r$calmar>=0.64), dsr=isTRUE(r$dsr>=0.5))
    wf("  [%-16s] %s -> %s", r$model, paste(names(p),ifelse(p,"v","x"),collapse=" "), ifelse(all(p),"GRADUATION","미달")) }
} else {
  KILL <- NA; any_grad <- NA
  w("\n[SMOKE_ONLY] KILL/graduation 판정 발화 생략 — 부분창 증거력 없음. 본판정은 FULL 모드(크롤 완결 후)에서만.")
}

## ── 저장 (SMOKE=.cache만 / FULL=outputs) ─────────────────────────────────────
res <- list(prereg=PREREG, config_hash=CFG_HASH, run_mode=MODE_LAB, smoke_only=SMOKE,
  results=TAB, paired=PAIRED, smoke_checks=smoke_checks,
  kill=KILL, any_graduation=any_grad, max_paired=maxp,
  n_sig=n_sig, date_range=as.character(range(sig_dates)),
  crawl=list(first=ck_yms[1], last=ck_yms[length(ck_yms)], gaps=length(ck_gaps)),
  insider_meta=ins_meta[c("crawl_last_ym","partial_data","pit_ok","factors")],
  generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"))
saveRDS(list(res=res, PR=PR, TAB=TAB, PAIRED=PAIRED), file.path(".cache", sprintf("_ramp_r9_insider_%s.rds", RUNTAG)))
if (!SMOKE) {
  write_parquet(TAB, file.path(OUT, sprintf("r9_insider_gates_%s.parquet", RUNTAG)))
  if(nrow(PAIRED)) write_parquet(PAIRED, file.path(OUT, sprintf("r9_insider_paired_%s.parquet", RUNTAG)))
  write_json(res, file.path(OUT, sprintf("r9_insider_summary_%s.json", RUNTAG)), auto_unbox=TRUE, pretty=TRUE, digits=4)
} else {
  write_json(res, file.path(".cache", sprintf("_ramp_r9_insider_smoke_manifest_%s.json", RUNTAG)), auto_unbox=TRUE, pretty=TRUE, digits=4)
  w("[SMOKE_ONLY] 산출물 .cache/ 한정 — outputs/ 미기록 (판정 발화 금지 정합)")
}
close(con)
cat(sprintf("R9_DONE mode=%s smoke_pass=%s kill=%s log=%s\n", MODE_LAB,
    if(SMOKE) as.character(exists("SMOKE_PASS") && isTRUE(SMOKE_PASS)) else "NA", KILL, logf))
cat(readLines(logf), sep="\n")
