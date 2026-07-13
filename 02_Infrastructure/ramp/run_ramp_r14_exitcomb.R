## run_ramp_r14_exitcomb.R — RAMP R14: cap-w×oos 이중 endpoint 퇴출 결합 chain (FQ-027)
## ─────────────────────────────────────────────────────────────────────────────
## 도훈 mandate 2026-07-13: R12 F-1(cap-w 2.937 최고·순위 트리거)과 R13 D-2(oos +0.045 최고·감쇠 트리거)의
##   퇴출 기전을 결합해 두 endpoint를 동시 취득하는가. chain 연속(R12 F-1 · R13 D-2 기전 결합).
##
## [구조 진단 — ExExEx 교대] anchors_exit(cadence3)=74, cohortEntry(cadence6)=37, 완전 교대(E x E x ..).
##   → 각 진입(반기 full top-K20 by level36) 사이에 exit-only 점검 정확히 1회. 따라서 4 gate는 동일 진입·동일
##   level36 충원을 공유하고 '퇴출 술어(predicate)'만 다르다 → 격자(lattice)가 엄밀:
##     퇴출집합  C-1(AND) ⊆ {F-1(RANK), D-2(DECAY)} ⊆ C-2(OR),  base=퇴출 없음.
##   차이는 순수히 퇴출-술어 결합에 귀속(entry/fill 교란 제거). C-1 유예(grace)는 점검 1회뿐이라 만료 거의 불가
##   → C-1 ≡ '단일 중간점검에서 both-fire(순위∧감쇠)만 배출'. (challenge ① 발화빈도로 정량화 의무)
##
## [퇴출 술어 (F-1/D-2 keep 조건 자구 이식)]
##   keep_rank(F-1)  = (rank(level36) ∈ [1,30]) ∧ (level36_t ≥ 0);  rank_departed = ¬keep_rank
##   keep_decay(D-2) = (recent18_t ≥ 0) ∧ ¬(decay(=recent18−older18) < −1.0);  decay_fired = ¬keep_decay
##   gate: RANK=rank_dep / DECAY=decay_fr / OR=rank_dep∨decay_fr / AND=rank_dep∧decay_fr(단일이면 유예 1분기)
##   entry(cohortEntry)=반기 full top-K20 by level36 · fill=head(setdiff(ranked_level36, keep), slots) [전 gate 동일]
##
## [prereg 구분 — AND-gate ≠ 수익파생 신호 교집합] arm C-1은 팩터 pool의 '유지/배출' 운영 규율 결합이다.
##   종목 선택 신호(무엇을 살지)의 교집합이 아님(신호는 여전히 pool 위 z-composite EW, 변경 없음). 결합 대상은
##   '언제 팩터를 배출하나(when to drop)' 게이트 → DIST 조건부 교집합(수익파생 AND-gate 금지) 대상 아님.
##
## [endpoint 위계 (R13 동일)] 1차 = oos_retention(v2 anchored 3분할 중앙값, cap-w act_bm)
##   2차 = port_t_capwt(병기) + HARD 3종 + EW-uni + 2017+ 분리 + paired vs base. 선택=IS-only paired-t(OSS 미조회).
## [chain 규율] selection_type="chain" · arm 간 선택 IS-only · 2차 결합 없음 · DSR 진단용(게이트 부적용).
##   n_trials: 계보 R13까지 24 + 본 3(2 arm C-1/C-2 + 1 diag D-3a, DSR 보수 위해 diag도 산입)=27.
## [보조 측정 — arm 아님·판정 무관] diag D-3a: 12m창을 6m 스텝으로 겹쳐 5개(overlapping) → trimmed-min
##   (최악 1창 제거 후 최소) 일관성 선별. R13 D-3(비겹침 12m×3 hard-min, cap-w 2.164·oos −0.028·rank AC 0.513
##   =12m 노이즈)의 '노이즈 완화' 가설 확인용 진단. (6m×2 겹침 = 6m 스텝 겹침창 해석, 명시)
## [측정 규율] proxy 손계산 없음 — weighted_screen_bt(계약, build_benchmark_compare) 경유. base parity == R6 2.6124.
## [실행] 단일스레드 · arrow io_thread(2) · pin r6 vintage(base parity 1회) · governor 정지 · book 무변경.
## ─────────────────────────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest); library(digest); library(jsonlite)
})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")           # build_monthly_forward_returns
source("02_Infrastructure/contracts/weighted_screen_bt.R")     # weighted_screen_bt (임의가중 계약경로)
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }
OUT <- "outputs/ramp"; RUNTAG <- "20260713"
logf <- file.path(".cache", sprintf("_ramp_r14_%s.txt", RUNTAG))
con <- file(logf,"w",encoding="UTF-8"); w<-function(...){ writeLines(paste0(...),con); flush(con) }; wf<-function(...){w(sprintf(...))}

## ── estimators (R6/R10~R13 자구동일) ──
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA_real_); mean(x)/sd(x)*sqrt(12) }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
oos3 <- function(act){ .splits<-c(0.55,0.65,0.75)                       # v2 anchored 3분할 중앙값
  r <- sapply(.splits, function(fr){ k<-floor(length(act)*fr)
    if(k<12||(length(act)-k)<6) return(NA_real_); .is<-srf(act[1:k]); .oo<-srf(act[(k+1):length(act)])
    if(!is.na(.is)&&.is>0) .oo/.is else NA_real_ }); median(r, na.rm=TRUE) }
post2017 <- as.Date("2017-01-01")

## ── 사전등록 config (hash 동결) ──
TOP_N <- 25L; COST_BPS <- 15; LIQ_MIN <- 2e8; W36 <- 36L; K20 <- 20L
CAP <- 0.20; FLOOR_FRAC <- 0.25
CADENCE_ENTRY <- 6L; CADENCE_EXIT <- 3L      # F-1/D-2 구조 승계: 반기 진입 / 분기 퇴출
EXIT_RANK_BAR <- 30L                          # F-1 rank 트리거: held rank>30 또는 level36_t<0
DECAY_DROP_BAR <- -1.0                        # D-2 decay 트리거: recent18<0 OR decay<−1.0
GATE_PT <- 2.95; PAIRED_MEANINGFUL <- 2.0; OOS_TARGET <- 0.7
IS_FRAC <- 0.65                               # chain: IS-only 승자 지목용 (첫 65% 배포월)
N_TRIALS_R14 <- 3L                            # 2 arm(C-1,C-2) + 1 diag(D-3a) — DSR 보수 산입
N_TRIALS_LINEAGE <- 24L + N_TRIALS_R14        # R13까지 24 + R14 3 = 27 (chain — DSR 진단용)
R12_F1 <- 2.937; R13_D2 <- 2.503; R6_BASE <- 2.6124
JUDGED_ARMS <- c("armC1_and_exit","armC2_or_exit")
REF_MODELS  <- c("ctrl_F1_rank_exit","ctrl_D2_decay_exit","diagD3a_trim_consistency")
NONBASE     <- c(JUDGED_ARMS, REF_MODELS)
PREREG <- list(mode="RAMP", round="R14", fq="FQ-027",
  question="R12 F-1(cap-w 2.937·순위 퇴출)과 R13 D-2(oos +0.045·감쇠 퇴출)의 퇴출 트리거를 AND/OR 결합해 두 endpoint 동시 취득 여부 판별. 보조 diag D-3a=6m 스텝 겹침 12m창×5 trimmed-min(12m 노이즈 완화)",
  base="Ppure_W36_K20 (종목 EW × 팩터 EW level36-top20, R6 저장 2.6124 parity 앵커)",
  selection_type="chain",
  lattice="ExExEx 교대 → 진입 사이 exit-only 점검 1회. 4 gate 동일 진입·동일 level36 fill, 퇴출 술어만 상이. 퇴출집합 C-1(AND)⊆{F-1,D-2}⊆C-2(OR), base=퇴출 없음",
  endpoint_hierarchy=list(primary="oos_retention (v2 anchored 3분할 중앙값, cap-w act_bm)",
    secondary="port_t_capwt + HARD 3종 + EW-uni + 2017+ 분리 + paired vs base",
    tension="endpoint=oos여도 arm '선택'은 IS-only(OOS 오염 방지). 선택=IS paired-t · 판정=게이트 산출 전체"),
  chain_discipline="arm 간 선택 IS-only(첫 65% 배포월 paired-t) · oos는 최종 게이트 산출로만 · 2차 결합 없음(1차만) · DSR 진단용(게이트 부적용)",
  arms=list(
    armC1_and_exit=list(mechanism="퇴출 = 순위 이탈(rank>30 OR level36_t<0) AND 감쇠 신호(recent18<0 OR decay<−1.0) 동시 충족 시 즉시 퇴출. 단일 트리거만이면 유예 1분기(grace). entry/fill=F-1 동일",
      diag="순위-단독(F-1)은 잡음 이탈을 퇴출·감쇠-단독(D-2)은 순위 건재한 감쇠 초기 놓침 — 교집합이 '진짜 죽는 팩터' 정밀 지정",
      distinction="퇴출 규칙(운영 규율) 결합 — 종목 선택 신호(무엇을 살지)의 수익파생 교집합 아님. 신호=pool 위 z-composite EW 불변. 결합 대상=팩터 유지/배출 게이트(when to drop). DIST 조건부 교집합 대상 아님",
      adversarial="C① both-fire 발화빈도·grace 만료빈도 — C-1이 F-1 궤적과 사실상 동일한가(AND의 감쇠 조건 비활성 여부)"),
    armC2_or_exit=list(mechanism="퇴출 = 순위 이탈 OR 감쇠 신호 어느 쪽이든 발화 시 즉시 퇴출(가장 공격적 신선도). grace 없음",
      diag="C-1과 대조 — '정밀 지정 vs 공격적 청소' 어느 기전이 유효한지 판별",
      adversarial="C② 과도 회전이 비용 잠식하는가 — turnover·either-fire 빈도·oos/cap-w 대조")),
  diag_D3a=list(mechanism="선별점수 = trimmed-min(5 겹침창 NW-t: 12m창을 6m 스텝으로 [36:25][30:19][24:13][18:7][12:1]) — 최악 1창 제거 후 최소. top-K20 by trimmed-min. base_anchors(cadence6) 진입, 퇴출 없음",
    diag="R13 D-3(비겹침 12m×3 hard-min, cap-w 2.164·oos −0.028·rank AC 0.513=12m 노이즈)의 노이즈 완화 가설 확인 진단. arm 아님·판정 무관",
    interp="'6m×2 겹침창' = 6m 스텝 겹침 12m창(D-3 3창 대비 ~2배 밀도)·trimmed=최악 1창 절사"),
  ctrl=list(ctrl_F1_rank_exit="RANK gate=R12 F-1 정확 재구성(entry/fill 동일·level36=trailing_t 정합). 참조 2.937",
    ctrl_D2_decay_exit="DECAY gate=D-2 퇴출 술어 재구성. 단 fill=level36(격자 통일) — R13 D-2(감쇠-인지 fill) 2.503과 fill 상이 가능(정직 병기)"),
  gate_hard=c(port_t_capwt=GATE_PT, oos_retention=OOS_TARGET, calmar=0.64, dsr=0.5),
  primary_criterion="1차 승자 = R14 자체 IS paired NW-t(cap-w act_bm) vs base 최대(IS-only, JUDGED_ARMS만). 최종 판정 = oos_retention(1차) + full HARD 3종 + full paired vs base + cap-w(2차)",
  kill_rule="전 judged arm oos_retention 0.7 미도달 AND HARD 3종 0/N AND full paired<2.0 → config-scoped negative(퇴출 결합 config 한정). '소진/dead-end' 어휘 금지 — next_probe >=2 도출 의무",
  honest_frame="본 라운드=퇴출 트리거 결합 레버. R13 진단 = oos 천장 ~+0.12 exit-rule-invariant(단일 트리거). 결합이 천장을 소폭이라도 여는가 판별. 정직 기대=천장 재확인 또는 소폭 돌파. cap-tier×cap-w 벽 미해결 가능(정직 병기). return-derived substrate 재사용(신규 재료 아님)",
  xmode_fail_prior="hypothesis_index: R12 F-1(cap-w 2.937·oos +0.048)·R13 D-2(oos +0.045)·armF cad3(oos +0.121) — 단일 퇴출 트리거 oos 천장 ~+0.12. factor-momentum timing NULL(06-30)·DIST-AR-007 momentum return-파생 DISTILLED_NEG. INV-7 재도전 차별점: ①퇴출 술어 결합(AND/OR 격자, 미탐색 construction) ②재료=realized active NW-t(IC 아님) ③운영 규율 결합(신호 교집합 아님)",
  is_frac=IS_FRAC, top_n=TOP_N, cost_bps_oneway=COST_BPS, liq_min=LIQ_MIN, cap=CAP, floor_frac=FLOOR_FRAC,
  cadence_entry=CADENCE_ENTRY, cadence_exit=CADENCE_EXIT, exit_rank_bar=EXIT_RANK_BAR, decay_drop_bar=DECAY_DROP_BAR,
  d3a_windows="12m@6m-step [36:25][30:19][24:13][18:7][12:1] trimmed-min(drop worst 1)",
  n_trials_r14=N_TRIALS_R14, n_trials_lineage=N_TRIALS_LINEAGE,
  ref=list(r12_f1_capwt=R12_F1, r13_d2_capwt=R13_D2, r6_base=R6_BASE),
  cost_model="delta-based |Δw|×15bps one-way (weighted_screen_bt 내장 — 퇴출 회전 자동 반영)",
  vintage_pin="r6_session_20260711 (sel_traj 36/pure_factor_scores/factor_group_scores/rawdata/panel; SUB=_ramp_r13_sub 재사용; base parity Δ<5e-3 확인)",
  as_of_date="2026-07-13", source_version="RAMP_R14_v1",
  security_id="Ticker (rawdata) -> factor_id z (pure_factor_scores.z=Z_Score_Aligned)")
CFG_HASH <- substr(digest::digest(PREREG, algo="sha256"), 1, 16)
PREREG$config_hash <- CFG_HASH
PREREG$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
jsonlite::write_json(PREREG, file.path(OUT, sprintf("r14_exitcomb_prereg_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=6)
wf("=== RAMP R14: 퇴출 결합 chain (config_hash=%s) ===", CFG_HASH)
wf("judged arms: %s | ref: %s | selection_type=chain | IS_FRAC=%.2f | n_trials R14=%d lineage=%d",
   paste(JUDGED_ARMS,collapse=","), paste(REF_MODELS,collapse=","), IS_FRAC, N_TRIALS_R14, N_TRIALS_LINEAGE)
wf("endpoint: PRIMARY=oos_retention(v2) / SECONDARY=cap-w PORT_t | 선택=IS-only paired-t")
wf("EXIT_RANK_BAR=%d DECAY_DROP_BAR=%.1f | lattice: C-1(AND)⊆{F-1,D-2}⊆C-2(OR), base=no-exit", EXIT_RANK_BAR, DECAY_DROP_BAR)

## ── 데이터 (R6/R10~R13 동일 소스) ──
af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
APPROVED <- af[status=="approved", factor_id]
g <- as.data.table(read_parquet(file.path(OUT,"factor_group_scores.parquet"))); g[, signal_date := as.Date(signal_date)]
sig_dates <- sort(unique(g$signal_date)); n_sig <- length(sig_dates); rm(g)
.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
.udates <- sort(unique(rawdata$Date))
.me <- as.Date(vapply(sig_dates, function(d){ v <- .udates[.udates <= d]; if(length(v)) as.character(max(v)) else NA_character_ }, character(1)))
rawme_f <- rawdata[Date %in% .me[!is.na(.me)]]
me_map <- data.table(Date_me=.me, Date=sig_dates)[!is.na(Date_me)]
SIZE_DT <- merge(rawme_f[, .(Date_me=as.Date(Date), Ticker, Size)], me_map, by="Date_me")[, .(Date, Ticker, Size)]
fwd <- build_monthly_forward_returns(rawme_f, sig_dates); rm(rawdata, rawme_f); invisible(gc())
RET_DT   <- fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)]
BENCH_DT <- fwd$bench_dt[,.(Date=as.Date(Date), BM_Ret)]
LIQ_DT   <- fwd$liq_dt[,.(Date=as.Date(Date), Ticker, adv)]
ewb <- fwd$returns_dt[, .(ew=mean(Ret_1m,na.rm=TRUE)), by=.(date=as.Date(Date))]  # EW-uni 벤치(진단)

sc <- as.data.table(read_parquet(file.path(OUT,"pure_factor_scores.parquet"),
        col_select=c("signal_date","security_id","factor_id","z")))
sc <- sc[factor_id %in% APPROVED]; sc[, signal_date := as.Date(signal_date)]
POOL_FACS <- sort(intersect(APPROVED, unique(sc$factor_id)))
fw <- dcast(sc, signal_date + security_id ~ factor_id, value.var="z")
FW_FACS <- intersect(POOL_FACS, names(fw))
fw_z <- fw[, c("signal_date","security_id", FW_FACS), with=FALSE]; setkey(fw_z, signal_date)
rm(fw, sc); invisible(gc())

## ── 선별 궤적 (R6 캐시 = 36m base 앵커·pool) ──
sel_traj <- readRDS(".cache/_ramp_r6_sel_20260711.rds")
base_anchors <- sel_traj[["36"]]$anchors                       # cadence 6 (base entry) == cohortEntry
wf("substrate: %d approved factors | %d sig months %s~%s | base_anchors=%d",
   length(POOL_FACS), n_sig, as.character(sig_dates[1]), as.character(sig_dates[n_sig]), length(base_anchors))

## ── 배포권 패널 Pmat (감쇠/일관성 부분창 NW-t용 — R6 factor_deployzone_active 재사용) ──
PANEL <- as.data.table(read_parquet(file.path(OUT,"r6_factor_deployzone_active.parquet"))); PANEL[, signal_date := as.Date(signal_date)]
PANEL_FACS <- sort(unique(PANEL$factor_id))
Pw <- dcast(PANEL, signal_date ~ factor_id, value.var="active_bm"); setorder(Pw, signal_date)
panel_dates <- Pw$signal_date; n_pm <- length(panel_dates)
Pmat <- as.matrix(Pw[, ..PANEL_FACS]); rownames(Pmat) <- as.character(panel_dates)
stopifnot(all(panel_dates == sig_dates[1:n_pm]))

win_nwt_vec <- function(a, back_start, back_end){    # rows [a-back_start : a-back_end], 각 factor NW-t lag3
  lo <- a - back_start; hi <- a - back_end
  if(lo < 1L || hi > n_pm || lo > hi) return(NULL)
  sub <- Pmat[lo:hi, , drop=FALSE]
  apply(sub, 2, function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
    m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) })
}

## anchors
anchors_exit  <- seq(W36+1L, n_sig-1L, by=CADENCE_EXIT)   # 분기 퇴출 점검 (진입 anchor 포함하는 superset)
cohortEntry   <- seq(W36+1L, n_sig-1L, by=CADENCE_ENTRY)  # = base R6 anchors (반기 진입)
stopifnot(identical(as.integer(base_anchors), as.integer(cohortEntry)))

## ── SUB(부분창 NW-t) 재사용: R13 캐시 = level36/recent18/older18/sub1/sub2/sub3 @ anchors_exit∪base ──
SUB_CACHE <- file.path(".cache", sprintf("_ramp_r13_sub_%s.rds", RUNTAG))
if(!file.exists(SUB_CACHE)) stop("[R14] SUB 캐시 부재: ", SUB_CACHE, " — R13 먼저 실행 필요")
SUB <- readRDS(SUB_CACHE)
stopifnot(all(as.character(anchors_exit) %in% names(SUB)))
wf("[cache] SUB(부분창 NW-t) 재사용: %s (%d anchors) — anchors_exit 완전포함 확인", SUB_CACHE, length(SUB))
## sanity: SUB level36 == sel trailing_t (base anchor 1개)
.chk_a <- as.character(base_anchors[ceiling(length(base_anchors)/2)])
if(!is.null(SUB[[.chk_a]]) && !is.null(sel_traj[["36"]]$traj[[.chk_a]]$trailing_t)){
  a1 <- SUB[[.chk_a]]$level36; a2 <- sel_traj[["36"]]$traj[[.chk_a]]$trailing_t
  cf <- intersect(names(a1[is.finite(a1)]), names(a2[is.finite(a2)]))
  wf("[sanity] SUB level36 vs sel trailing_t @%s: max|Δ|=%.2e (n=%d)", .chk_a, max(abs(a1[cf]-a2[cf])), length(cf))
}

## ════════ 통일 퇴출-궤적 빌더 (gate 술어만 상이 — 격자 엄밀) ════════
## gate ∈ {RANK(F-1), DECAY(D-2), OR(C-2), AND(C-1, grace)}
build_pool_traj_combo <- function(gate){
  held <- NULL; grace <- integer(0); pool_by_anchor <- list()
  st <- list(n_check=0L, rank_fire=0L, decay_fire=0L, both=0L, either=0L,
             grace_start=0L, grace_expire=0L, n_exit=0L, n_exitcheck=0L)
  for(a in anchors_exit){
    S <- SUB[[as.character(a)]]
    if(is.null(S) || is.null(S$level36)){ pool_by_anchor[[as.character(a)]] <- held; next }
    lvl <- S$level36; rec <- S$recent18; dec <- rec - S$older18
    ranked_lvl <- names(sort(lvl[is.finite(lvl)], decreasing=TRUE))
    is_entry <- a %in% cohortEntry
    if(is_entry || is.null(held)){
      held <- head(ranked_lvl, K20); grace <- setNames(integer(length(held)), held)
    } else {
      st$n_exitcheck <- st$n_exitcheck + 1L
      keep <- character(0); newgrace <- integer(0)
      for(f in held){
        r  <- match(f, ranked_lvl); lf <- if(f %in% names(lvl)) lvl[[f]] else NA_real_
        rf <- if(f %in% names(rec)) rec[[f]] else NA_real_
        df <- if(f %in% names(dec)) dec[[f]] else NA_real_
        keep_rank  <- (!is.na(r) && r <= EXIT_RANK_BAR) && (is.finite(lf) && lf >= 0)
        keep_decay <- (is.finite(rf) && rf >= 0) && !(is.finite(df) && df < DECAY_DROP_BAR)
        rank_dep <- !keep_rank; decay_fr <- !keep_decay
        st$n_check <- st$n_check + 1L
        if(rank_dep) st$rank_fire <- st$rank_fire + 1L
        if(decay_fr) st$decay_fire <- st$decay_fire + 1L
        if(rank_dep && decay_fr) st$both <- st$both + 1L
        if(rank_dep || decay_fr) st$either <- st$either + 1L
        exit_now <- FALSE; g_new <- 0L
        if(gate=="RANK")       exit_now <- rank_dep
        else if(gate=="DECAY") exit_now <- decay_fr
        else if(gate=="OR")    exit_now <- rank_dep || decay_fr
        else if(gate=="AND"){
          if(rank_dep && decay_fr) exit_now <- TRUE
          else if(xor(rank_dep, decay_fr)){
            prevg <- if(f %in% names(grace)) grace[[f]] else 0L
            if(prevg >= 1L){ exit_now <- TRUE; st$grace_expire <- st$grace_expire + 1L }
            else { exit_now <- FALSE; g_new <- 1L; st$grace_start <- st$grace_start + 1L }
          } else exit_now <- FALSE
        }
        if(!exit_now){ keep <- c(keep, f); newgrace[f] <- g_new } else st$n_exit <- st$n_exit + 1L
      }
      slots <- K20 - length(keep)
      fill <- if(slots > 0) head(setdiff(ranked_lvl, keep), slots) else character(0)
      held <- c(keep, fill)
      grace <- c(newgrace, setNames(rep(0L, length(fill)), fill))
    }
    pool_by_anchor[[as.character(a)]] <- held
  }
  attr(pool_by_anchor, "stats") <- st
  pool_by_anchor
}
POOL_C1 <- build_pool_traj_combo("AND")
POOL_C2 <- build_pool_traj_combo("OR")
POOL_F1 <- build_pool_traj_combo("RANK")
POOL_D2 <- build_pool_traj_combo("DECAY")

## ── D-3a: 겹침 12m창×5 trimmed-min 선별 pool (base_anchors, 퇴출 없음) ──
sel_pool_D3a <- list()
for(a in base_anchors){
  S <- SUB[[as.character(a)]]; if(is.null(S) || is.null(S$level36)) next
  lvl <- S$level36
  w1 <- S$sub1                        # [a-36:a-25]
  w2 <- win_nwt_vec(a, 30L, 19L)      # NEW 겹침창 [a-30:a-19]
  w3 <- S$sub2                        # [a-24:a-13]
  w4 <- win_nwt_vec(a, 18L, 7L)       # NEW 겹침창 [a-18:a-7]
  w5 <- S$sub3                        # [a-12:a-1]
  nm <- names(lvl)
  ok <- nm[ is.finite(w1[nm]) & is.finite(w2[nm]) & is.finite(w3[nm]) & is.finite(w4[nm]) & is.finite(w5[nm]) ]
  if(length(ok) >= K20){
    tm <- vapply(ok, function(f) sort(c(w1[[f]],w2[[f]],w3[[f]],w4[[f]],w5[[f]]))[2], numeric(1))  # 최악 1창 절사 → 2번째 최소
    names(tm) <- ok
    sel_pool_D3a[[as.character(a)]] <- names(sort(tm, decreasing=TRUE))[seq_len(K20)]
  } else sel_pool_D3a[[as.character(a)]] <- names(sort(lvl[is.finite(lvl)], decreasing=TRUE))[seq_len(min(K20,sum(is.finite(lvl))))]
}

## ── pool getters ──
getter_base <- function(i){ ga <- max(base_anchors[base_anchors<=i]); sel_traj[["36"]]$traj[[as.character(ga)]]$pool[["K20"]] }
getter_from_exit <- function(POOL){ force(POOL); function(i){ ga <- max(anchors_exit[anchors_exit<=i]); p <- POOL[[as.character(ga)]]; if(is.null(p)) getter_base(i) else p } }
getter_C1 <- getter_from_exit(POOL_C1); getter_C2 <- getter_from_exit(POOL_C2)
getter_F1 <- getter_from_exit(POOL_F1); getter_D2 <- getter_from_exit(POOL_D2)
getter_D3a <- function(i){ ga <- max(base_anchors[base_anchors<=i]); p <- sel_pool_D3a[[as.character(ga)]]; if(is.null(p)) getter_base(i) else p }

## ── 공용: positive-shift 틸트 + cap water-fill (R10~R13 자구동일) ──
cap_normalize <- function(raw, cap=CAP){
  raw <- pmax(raw, 0); if(sum(raw)<=0) return(rep(1/length(raw), length(raw)))
  w <- raw/sum(raw)
  for(it in 1:50){ over <- w > cap + 1e-12; if(!any(over)) break
    excess <- sum(w[over]-cap); w[over] <- cap; under <- !over
    if(!any(under)||sum(w[under])<=0){ w <- w/sum(w); break }
    w[under] <- w[under] + excess*w[under]/sum(w[under]) }
  w/sum(w)
}
tilt_shift <- function(x, floor_frac=FLOOR_FRAC){ rng <- max(x)-min(x)
  if(!is.finite(rng)||rng<1e-9) return(rep(mean(abs(x))+1e-6, length(x)))
  x - min(x) + floor_frac*rng }
stock_weights <- function(scores, mode){
  n <- length(scores); if(mode=="ew") return(rep(1/n, n))
  p <- tilt_shift(scores); raw <- if(mode=="sqrt") sqrt(p) else p; cap_normalize(raw) }

## ── composite 재구성 (R10~R13 build_composite EW 경로 자구동일) ──
build_composite_g <- function(pool_getter){
  deploy_idx <- (W36+1L):(n_sig-1L); rows <- list()
  for(i in deploy_idx){
    facs <- intersect(pool_getter(i), FW_FACS); if(length(facs)==0) next
    sub <- fw_z[.(sig_dates[i])]; if(nrow(sub)==0) next
    Xz <- sub[, lapply(.SD, zc), .SDcols=facs]; Xm <- as.matrix(Xz); Xm[is.na(Xm)] <- 0
    rows[[as.character(i)]] <- data.table(signal_date=sig_dates[i], security_id=sub$security_id, score=rowMeans(Xm))
  }
  s <- rbindlist(rows); s[, score := zc(score), by=signal_date]; s
}
build_weights <- function(comp, stock_mode="ew"){
  S <- comp[!is.na(score), .(Date=as.Date(signal_date), Ticker=security_id, score)]
  S <- merge(S, LIQ_DT[, .(Date, Ticker, adv)], by=c("Date","Ticker"), all.x=TRUE)
  S <- S[is.na(adv) | adv >= LIQ_MIN]; S[, adv := NULL]
  setorder(S, Date, -score)
  S[, { n <- min(TOP_N, .N); sc_sel <- score[seq_len(n)]
    .(Ticker=Ticker[seq_len(n)], w=stock_weights(sc_sel, stock_mode)) }, by=Date]
}

## ── gate: weighted_screen_bt -> period_returns -> R6 estimator (R13 gate_one 자구동일 + oos_ew 병기) ──
gate_one <- function(Wdt, lab){
  r <- tryCatch(weighted_screen_bt(Wdt, RET_DT, BENCH_DT, cost_bps_oneway=COST_BPS,
        run_id=paste0("r14_",lab), strategy_id=lab), error=function(e){ w("  [gate ERR ",lab,"] ",conditionMessage(e)); NULL })
  if(is.null(r) || is.null(r$period_returns)) return(NULL)
  pr <- as.data.table(r$period_returns); pr[, date:=as.Date(date)]
  pr <- merge(pr, ewb, by="date", all.x=TRUE)
  pr[, act := ret_net - ew]; pr[, act_bm := ret_net - benchmark_ret]
  pt_ew <- nwt(pr$act); pt_bm <- nwt(pr$act_bm)
  nav <- cumprod(1+pr$ret_net); dd <- min(nav/cummax(nav)-1); ann <- prod(1+pr$ret_net)^(12/nrow(pr))-1
  cal <- if(dd<0) ann/abs(dd) else NA_real_
  retn    <- oos3(pr$act_bm)     # 1차 endpoint (cap-w authoritative)
  retn_ew <- oos3(pr$act)        # EW-uni 진단 병기
  sr_m <- mean(pr$act_bm)/sd(pr$act_bm); nn <- nrow(pr)
  sk <- tryCatch(e1071::skewness(pr$act_bm),error=function(e)0); ku <- tryCatch(e1071::kurtosis(pr$act_bm)+3,error=function(e)3)
  den <- sqrt((1-sk*sr_m+(ku-1)/4*sr_m^2)/(nn-1)); dsr_raw <- if(den>1e-10) sr_m/den else NA_real_
  dsr <- if(!is.na(dsr_raw)) dsr_raw - N_TRIALS_LINEAGE*0.05 else NA_real_
  post_sr <- srf(pr[date>=post2017, act_bm]); full_sr <- srf(pr$act_bm)
  list(dt=data.table(model=lab, port_t_capwt=pt_bm, port_t_EWuni=pt_ew, oos_retention=retn, oos_ew=retn_ew, calmar=cal,
         dsr=dsr, post2017_bm_sr=post_sr, full_bm_sr=full_sr, turnover=r$turnover_annual, n_months=nrow(pr)),
       pr=pr[,.(date, act_bm, act, ret_net, benchmark_ret)], W=Wdt)
}
conc_diag <- function(Wdt, lab){
  Z <- copy(SIZE_DT); Z <- Z[!is.na(Size)]; setorder(Z, Date, -Size); Z[, crank:=seq_len(.N), by=Date]
  Z[, tier:=fifelse(crank<=10L,"MEGA",fifelse(crank<=30L,"MID","OTHER"))]
  H <- merge(as.data.table(Wdt), Z[,.(Date,Ticker,tier)], by=c("Date","Ticker"), all.x=TRUE)
  H[is.na(tier), tier:="UNRANKED"]
  hhi <- H[, .(hhi=sum(w^2), n_eff=1/sum(w^2), maxw=max(w), n_hold=.N), by=Date]
  tw  <- H[, .(wshare=sum(w)), by=.(Date, tier)]; twa <- tw[, .(wshare=mean(wshare)), by=tier]
  tiers <- c("MEGA","MID","OTHER","UNRANKED"); ts <- setNames(rep(0,4), tiers)
  for(t in tiers) if(t %in% twa$tier) ts[t] <- twa[tier==t, wshare]
  data.table(model=lab, hhi=mean(hhi$hhi), n_eff=mean(hhi$n_eff), maxw=mean(hhi$maxw), n_hold=mean(hhi$n_hold),
    min_nhold=min(hhi$n_hold), w_MEGA=ts["MEGA"], w_MID=ts["MID"], w_OTHER=ts["OTHER"], w_UNRANKED=ts["UNRANKED"])
}

## ════════════ 측정 (base + 2 arm + 2 ctrl + 1 diag) ════════════
wf("\n=== 측정 (cap-w authoritative, weighted_screen_bt 계약경로) ===")
RES <- list(); PR <- list(); WMAP <- list(); CONC <- list(); COMPS <- list()
run_arm <- function(getter, lab){
  comp <- build_composite_g(getter); COMPS[[lab]] <<- comp
  W <- build_weights(comp, "ew")
  g <- gate_one(W, lab); RES[[lab]]<<-g$dt; PR[[lab]]<<-g$pr; WMAP[[lab]]<<-W; CONC[[lab]]<<-conc_diag(W,lab)
  wf("  [%-24s] pt_capwt=%+.3f pt_EWuni=%+.3f oos=%+.3f oos_ew=%+.3f calmar=%+.3f DSR=%+.3f post17SR=%+.3f TO=%.2f",
     lab, g$dt$port_t_capwt, g$dt$port_t_EWuni, g$dt$oos_retention, g$dt$oos_ew, g$dt$calmar, g$dt$dsr, g$dt$post2017_bm_sr, g$dt$turnover)
  invisible(g)
}
run_arm(getter_base, "base")
run_arm(getter_C1,   "armC1_and_exit")
run_arm(getter_C2,   "armC2_or_exit")
run_arm(getter_F1,   "ctrl_F1_rank_exit")
run_arm(getter_D2,   "ctrl_D2_decay_exit")
run_arm(getter_D3a,  "diagD3a_trim_consistency")

## ── base parity + ctrl 참조 parity ──
base_pt <- RES[["base"]]$port_t_capwt
parity_delta <- abs(base_pt - R6_BASE); parity_ok <- is.finite(parity_delta) && parity_delta < 5e-3
f1_pt <- RES[["ctrl_F1_rank_exit"]]$port_t_capwt; d2_pt <- RES[["ctrl_D2_decay_exit"]]$port_t_capwt
wf("\n[base parity] R14 base cap-w=%.4f vs R6 %.4f -> |Δ|=%.2e ok=%s", base_pt, R6_BASE, parity_delta, parity_ok)
wf("[ctrl parity] ctrl_F1 cap-w=%.4f vs R12 F-1 %.3f (Δ=%+.4f, fill 동일 → 정합 기대) | ctrl_D2 cap-w=%.4f vs R13 D-2 %.3f (Δ=%+.4f, fill 상이 가능)",
   f1_pt, R12_F1, f1_pt-R12_F1, d2_pt, R13_D2, d2_pt-R13_D2)
if(!parity_ok) w("  ★ WARNING: base parity 미달 — 재구성 계열 라벨 강등 필요")

## ── paired NW-t (full + IS-only) vs base ──
pair_full <- function(la){ if(is.null(PR[[la]])||is.null(PR[["base"]])) return(NULL)
  m <- merge(PR[[la]][,.(date, a=act_bm)], PR[["base"]][,.(date, b=act_bm)], by="date")
  d <- m$a - m$b; n_is <- floor(nrow(m)*IS_FRAC)
  data.table(model=la, mean_diff_ann=mean(d,na.rm=TRUE)*12,
    paired_t_full=nwt(d), paired_t_IS=nwt(d[seq_len(n_is)]), paired_t_OOS=nwt(d[(n_is+1L):nrow(m)]),
    n=nrow(m), n_is=n_is) }
PAIRED <- rbindlist(lapply(NONBASE, pair_full), fill=TRUE)
wf("\n=== paired NW-t vs base (IS_FRAC=%.2f: IS=첫 %d월 / OOS=나머지) ===", IS_FRAC, PAIRED$n_is[1])
for(i in seq_len(nrow(PAIRED))) wf("  [%-24s] Δ(ann)=%+.4f | paired_t: full=%+.3f IS=%+.3f OOS=%+.3f (n=%d)",
  PAIRED$model[i], PAIRED$mean_diff_ann[i], PAIRED$paired_t_full[i], PAIRED$paired_t_IS[i], PAIRED$paired_t_OOS[i], PAIRED$n[i])

## ── 1차 IS-only 승자 지목 (JUDGED_ARMS만, chain 규율 OOS 미조회) ──
PJ <- PAIRED[model %in% JUDGED_ARMS]
winner <- PJ[which.max(paired_t_IS), model]; winner_is_t <- PJ[model==winner, paired_t_IS]
wf("\n=== 1차 IS-only 승자 (JUDGED_ARMS, chain: OOS 미조회) ===")
wf("  winner = %s (IS paired_t=%+.3f) | 서열(IS): %s", winner, winner_is_t,
   paste(sprintf("%s=%.2f", PJ$model, PJ$paired_t_IS), collapse=" > "))

TAB <- rbindlist(lapply(RES, function(x) x), fill=TRUE)
CONCT <- rbindlist(CONC, fill=TRUE)

## ── HARD 게이트표 (1차 oos 강조) ──
wf("\n=== HARD 게이트 (★1차 oos 0.7 / capwt %.2f(2차) / calmar 0.64 / DSR 0.5[chain 진단], n_trials lineage=%d) ===", GATE_PT, N_TRIALS_LINEAGE)
for(i in seq_len(nrow(TAB))){ r<-TAB[i]
  p<-c(oos=isTRUE(r$oos_retention>=OOS_TARGET), port_t=isTRUE(r$port_t_capwt>=GATE_PT), cal=isTRUE(r$calmar>=0.64))
  wf("  [%-24s] ★oos=%+.3f %s | pt=%+.3f %s cal=%+.3f %s -> %s", r$model, r$oos_retention, ifelse(p["oos"],"✓","✗"),
     r$port_t_capwt, ifelse(p["port_t"],"✓","✗"), r$calmar, ifelse(p["cal"],"✓","✗"), ifelse(all(p),"★GRADUATION","미달")) }

## ── concentration ──
wf("\n=== concentration ===")
wf("  %-24s %6s %6s %6s %6s %6s | %6s %6s %6s", "model","HHI","effN","maxw","nHold","minNH","MEGA","MID","OTHER")
for(i in seq_len(nrow(CONCT))){ r<-CONCT[i]
  wf("  %-24s %6.4f %6.2f %6.3f %6.1f %6.0f | %6.3f %6.3f %6.3f", r$model, r$hhi, r$n_eff, r$maxw, r$n_hold, r$min_nhold, r$w_MEGA, r$w_MID, r$w_OTHER) }

## ════════════ 챌린지 진단 (self-adversarial 재료) ════════════
wf("\n=== 챌린지 진단 ===")
## ① C-1이 F-1 궤적과 사실상 동일한가 — 발화빈도 + Jaccard
stC1 <- attr(POOL_C1,"stats"); stC2 <- attr(POOL_C2,"stats"); stF1 <- attr(POOL_F1,"stats"); stD2 <- attr(POOL_D2,"stats")
pool_jac <- function(getA, getB){ idx <- (W36+1L):(n_sig-1L); jc <- c()
  for(i in idx){ a<-getA(i); b<-getB(i); if(length(a)&&length(b)) jc<-c(jc, length(intersect(a,b))/length(union(a,b))) }; mean(jc, na.rm=TRUE) }
jac_C1_F1 <- pool_jac(getter_C1, getter_F1); jac_C1_D2 <- pool_jac(getter_C1, getter_D2); jac_C1_base <- pool_jac(getter_C1, getter_base)
jac_C2_F1 <- pool_jac(getter_C2, getter_F1); jac_C2_D2 <- pool_jac(getter_C2, getter_D2)
wf("  ① 퇴출 발화(단일 중간점검 held당): C-1(AND) n_check=%d both=%d exit=%d grace_start=%d grace_expire=%d",
   stC1$n_check, stC1$both, stC1$n_exit, stC1$grace_start, stC1$grace_expire)
wf("     비교 발화(각 gate 자체 held 기준): F-1 rank_fire=%d exit=%d | D-2 decay_fire=%d exit=%d | C-2 either=%d exit=%d",
   stF1$rank_fire, stF1$n_exit, stD2$decay_fire, stD2$n_exit, stC2$either, stC2$n_exit)
wf("     Jaccard: C-1↔F-1=%.3f C-1↔D-2=%.3f C-1↔base=%.3f | C-2↔F-1=%.3f C-2↔D-2=%.3f",
   jac_C1_F1, jac_C1_D2, jac_C1_base, jac_C2_F1, jac_C2_D2)
## ② C-2 과도 회전 비용 잠식 — turnover 대조
to_base<-TAB[model=="base",turnover]; to_C1<-TAB[model=="armC1_and_exit",turnover]; to_C2<-TAB[model=="armC2_or_exit",turnover]
to_F1<-TAB[model=="ctrl_F1_rank_exit",turnover]; to_D2<-TAB[model=="ctrl_D2_decay_exit",turnover]
wf("  ② turnover(연): base=%.2f C-1=%.2f C-2=%.2f | F-1=%.2f D-2=%.2f (C-2 공격적 회전이 비용 잠식하는가)",
   to_base, to_C1, to_C2, to_F1, to_D2)
## ③ oos subperiod 분해 (개선이 특정 시기 아티팩트인가)
oos_subperiod <- function(la){ if(is.null(PR[[la]])) return(NULL)
  pr <- PR[[la]]; pre <- pr[date<post2017, act_bm]; post <- pr[date>=post2017, act_bm]
  data.table(model=la, sr_full=srf(pr$act_bm), sr_pre2017=srf(pre), sr_post2017=srf(post),
    oos_full=oos3(pr$act_bm), oos_pre=oos3(pre), oos_post=oos3(post), n_pre=length(pre), n_post=length(post)) }
OOSSUB <- rbindlist(lapply(c("base",NONBASE), oos_subperiod), fill=TRUE)
wf("  ③ oos/SR subperiod (2017 경계):")
for(i in seq_len(nrow(OOSSUB))){ r<-OOSSUB[i]
  wf("     [%-24s] SR full=%+.3f pre17=%+.3f post17=%+.3f | oos full=%+.3f pre=%+.3f post=%+.3f",
     r$model, r$sr_full, r$sr_pre2017, r$sr_post2017, r$oos_full, r$oos_pre, r$oos_post) }

## ── verdict 판정 (JUDGED_ARMS만, oos 1차 endpoint framing) ──
maxp_full <- suppressWarnings(max(PAIRED[model %in% JUDGED_ARMS, paired_t_full], na.rm=TRUE))
best_oos <- suppressWarnings(max(TAB[model %in% JUDGED_ARMS, oos_retention], na.rm=TRUE))
best_oos_arm <- TAB[model %in% JUDGED_ARMS][which.max(oos_retention)]
best_capwt_arm <- TAB[model %in% JUDGED_ARMS][which.max(port_t_capwt)]
any_grad <- any(is.finite(TAB$port_t_capwt) & TAB$port_t_capwt>=GATE_PT &
                is.finite(TAB$oos_retention) & TAB$oos_retention>=OOS_TARGET &
                is.finite(TAB$calmar) & TAB$calmar>=0.64 & TAB$model %in% JUDGED_ARMS)
base_oos <- TAB[model=="base", oos_retention]; oos_improve <- best_oos - base_oos
KILL <- !(is.finite(best_oos) && best_oos>=OOS_TARGET) && !any_grad && !(is.finite(maxp_full) && maxp_full>=PAIRED_MEANINGFUL)
wf("\n=== 판정 gate (사전등록 — 1차 oos endpoint, JUDGED_ARMS만) ===")
wf("  ★ best oos_retention(arm) = %+.4f [%s] (target %.1f) | base oos=%+.4f → Δoos=%+.4f",
   best_oos, best_oos_arm$model, OOS_TARGET, base_oos, oos_improve)
wf("  2차: best cap-w arm = %s %.3f | max full paired = %+.3f (문턱 %.1f) | any GRADUATION = %s",
   best_capwt_arm$model, best_capwt_arm$port_t_capwt, maxp_full, PAIRED_MEANINGFUL, any_grad)
wf("  => config_scoped_negative(퇴출 결합 config 한정) = %s [종결 아님·next_probe 도출 의무]", KILL)

## ── 저장 ──
CHAL <- list(
  C1_stats=stC1, C2_stats=stC2, F1_stats=stF1, D2_stats=stD2,
  jaccard=list(C1_F1=jac_C1_F1, C1_D2=jac_C1_D2, C1_base=jac_C1_base, C2_F1=jac_C2_F1, C2_D2=jac_C2_D2),
  turnover=list(base=to_base, C1=to_C1, C2=to_C2, F1=to_F1, D2=to_D2),
  parity=list(base=parity_delta, ctrl_F1_vs_r12=f1_pt-R12_F1, ctrl_D2_vs_r13=d2_pt-R13_D2))
res <- list(prereg=PREREG, config_hash=CFG_HASH,
  meta=list(as_of_date="2026-07-13", generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
    source_version="RAMP_R14_v1", security_id="Ticker->factor_id z (pure_factor_scores.z=Z_Score_Aligned)"),
  results=TAB, paired=PAIRED, concentration=CONCT, oos_subperiod=OOSSUB,
  base_parity=list(r14_base_pt=base_pt, r6_stored=R6_BASE, delta=parity_delta, ok=parity_ok,
    ctrl_F1_pt=f1_pt, ctrl_D2_pt=d2_pt),
  winner_1st=winner, winner_is_t=winner_is_t,
  endpoint_primary="oos_retention", endpoint_secondary="port_t_capwt",
  challenge=CHAL,
  kill=KILL, max_paired_full=maxp_full, any_graduation=any_grad,
  best_oos_arm=best_oos_arm$model, best_oos_val=best_oos, best_capwt_arm=best_capwt_arm$model, best_capwt_val=best_capwt_arm$port_t_capwt,
  n_trials_r14=N_TRIALS_R14, n_trials_lineage=N_TRIALS_LINEAGE, selection_type="chain", n_sig=n_sig,
  date_range=as.character(range(sig_dates)))
saveRDS(list(res=res, PR=PR, TAB=TAB, PAIRED=PAIRED, WMAP=WMAP, CONC=CONCT, COMPS=COMPS, OOSSUB=OOSSUB,
  POOLS=list(C1=POOL_C1,C2=POOL_C2,F1=POOL_F1,D2=POOL_D2)), file.path(".cache", sprintf("_ramp_r14_%s.rds", RUNTAG)))
write_parquet(TAB, file.path(OUT, sprintf("r14_exitcomb_gates_%s.parquet", RUNTAG)))
if(nrow(PAIRED)) write_parquet(PAIRED, file.path(OUT, sprintf("r14_exitcomb_paired_%s.parquet", RUNTAG)))
write_parquet(CONCT, file.path(OUT, sprintf("r14_exitcomb_conc_%s.parquet", RUNTAG)))
write_parquet(OOSSUB, file.path(OUT, sprintf("r14_exitcomb_oossub_%s.parquet", RUNTAG)))
jsonlite::write_json(res, file.path(OUT, sprintf("r14_exitcomb_summary_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=4)

## ── best variant period_returns (텔레그램 차트용 — best cap-w arm 표준 3종) ──
best_lab <- best_capwt_arm$model
if(!is.null(PR[[best_lab]])){
  bpr <- merge(PR[[best_lab]][,.(date, ret_net)], BENCH_DT[,.(date=Date, BM_Ret)], by="date")
  saveRDS(list(best_lab=best_lab, best_oos_lab=best_oos_arm$model,
               period_returns=data.table(date=bpr$date, ret_net=bpr$ret_net, benchmark_ret=bpr$BM_Ret),
               base_pr=merge(PR[["base"]][,.(date,ret_net)], BENCH_DT[,.(date=Date,BM_Ret)], by="date")),
          file.path(".cache", sprintf("_ramp_r14_bestpr_%s.rds", RUNTAG)))
}

wf("\n=== VERDICT ===")
wf("  ★1차 best oos arm: %s oos=%+.4f (base %+.4f, Δ%+.4f) | target %.1f",
   best_oos_arm$model, best_oos, base_oos, oos_improve, OOS_TARGET)
wf("  2차 best cap-w arm: %s pt=%+.3f | IS 승자=%s | max full paired=%+.3f | config_scoped_negative=%s | base_parity=%s(Δ%.2e)",
   best_capwt_arm$model, best_capwt_arm$port_t_capwt, winner, maxp_full, KILL, parity_ok, parity_delta)
close(con)
cat(sprintf("R14_DONE. winner=%s neg=%s any_grad=%s best_oos=%.4f(base %.4f Δ%.4f) best_capwt=%.4f max_paired_full=%.3f base_parity=%s(Δ%.2e) log=%s\n",
   winner, KILL, any_grad, best_oos, base_oos, oos_improve, best_capwt_arm$port_t_capwt, maxp_full, parity_ok, parity_delta, logf))
cat(readLines(logf, encoding="UTF-8"), sep="\n")
