## run_ramp_r15_fill.R — RAMP R15: 충원(fill) 규율 축 chain (FQ-028)
## ─────────────────────────────────────────────────────────────────────────────
## 도훈 mandate 2026-07-13: R14 next_probe 1순위(challenge ④) 소비. R14에서 ctrl_D2가 fill 선택만으로
##   cap-w 2.406↔2.503 이동 = fill이 퇴출과 직교하는 실민감 다이얼임을 노출. 챔피언 = F-1(순위-단독 퇴출).
##   따라서 진입(반기 top-K20 by level36)·퇴출(F-1 rank-only, 분기) 고정하고 '충원(fill) 규율만' 변주.
##
## [격자 엄밀 — fill만 변수] base=F-1(level36-fill, R14 ctrl_F1 정확 2.937 재현) 위에서 fill 규칙만 교체:
##   arm L-1 (신선-fill): 빈 슬롯 충원 = recent-half(18m) NW-t 상위 차순위. 기전: 충원 시점=정보 최신 순간,
##       수준-fill은 감쇠 중 팩터 재유입 위험.
##   arm L-2 (무-fill 축소): 퇴출 슬롯을 다음 반기 진입까지 미충원(풀 자연 축소, 종목 top-25는 잔여 풀 합의).
##       기전: 충원 자체가 잡음 유입일 가능성 — 검증된 생존자만으로 압축 운용.
##   arm L-3 (일관성-fill): 충원 = 부분창(12m×3) NW-t 최소값 상위(R13 D-3 산식 fill에만 적용). 기전: 충원
##       팩터만큼은 감쇠-저항성 검증 요구.
##
## [prereg 구분] 진입·퇴출 술어는 전 arm 동일 → 차이는 순수히 '빈 슬롯을 무엇으로 메우나'에 귀속(entry/exit
##   교란 제거). 신호=pool 위 z-composite EW 불변(무엇을 살지의 수익파생 교집합 아님). DIST 조건부 교집합 대상 아님.
##
## [endpoint 위계 (R13/R14 동일)] 1차 = oos_retention(v2 anchored 3분할 중앙값, cap-w act_bm)
##   2차 = port_t_capwt(병기) + HARD 3종 + EW-uni + 2017+ 분리 + paired vs base(F-1). 선택=IS-only paired-t.
## [chain 규율] selection_type="chain" · arm 간 선택 IS-only · 2차 결합 없음 · DSR 진단용(게이트 부적용).
##   n_trials: 계보 R14까지 27 + 본 3(L-1/L-2/L-3)=30 (chain — DSR 진단용).
## [측정 규율] proxy 손계산 없음 — weighted_screen_bt(계약, build_benchmark_compare) 경유.
##   parity: ①R6 no-exit anchor cap-w == R6 저장 2.6124  ②base_F1(level36-fill) cap-w == R14 ctrl_F1 2.937 Δ=0.
## [실행] 단일스레드 · arrow io_thread(2) · pin r6 vintage(SUB=_ramp_r13_sub 재사용) · governor 정지 · book 무변경.
## [challenge 사전지정] ① L-2 무-fill이 K 축소 sweep(R6 K10 cap-w 1.906·oos -0.375)과 수렴하는지(유효 K·pool 크기)
##   ② L-1 신선-fill이 FM 수렴하는지(fill에만 적용해도 pool FM화 Jaccard) ③ fill 빈도(교대구조상 exit-only anchor만)
##   낮으면 검정력 한계 정직 기록.
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
logf <- file.path(".cache", sprintf("_ramp_r15_%s.txt", RUNTAG))
con <- file(logf,"w",encoding="UTF-8"); w<-function(...){ writeLines(paste0(...),con); flush(con) }; wf<-function(...){w(sprintf(...))}

## ── estimators (R6/R10~R14 자구동일) ──
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
CADENCE_ENTRY <- 6L; CADENCE_EXIT <- 3L      # F-1 구조 승계: 반기 진입 / 분기 퇴출
EXIT_RANK_BAR <- 30L                          # F-1 rank 트리거(고정): held rank>30 또는 level36_t<0
GATE_PT <- 2.95; PAIRED_MEANINGFUL <- 2.0; OOS_TARGET <- 0.7
IS_FRAC <- 0.65                               # chain: IS-only 승자 지목용 (첫 65% 배포월)
N_TRIALS_R15 <- 3L                            # L-1/L-2/L-3 (2차 결합 없음)
N_TRIALS_LINEAGE <- 27L + N_TRIALS_R15        # R14까지 27 + R15 3 = 30 (chain — DSR 진단용)
R14_CTRLF1 <- 2.937; R6_BASE <- 2.6124; R6_K10 <- 1.9055; R6_K10_OOS <- -0.3753
JUDGED_ARMS <- c("armL1_fresh_fill","armL2_nofill_shrink","armL3_consist_fill")
BASE_LAB   <- "base_F1_level36fill"
REF_LABS   <- c("anchor_R6_noexit")           # vintage parity anchor (판정 arm 아님)
ALLNONBASE <- c(JUDGED_ARMS, REF_LABS)
PREREG <- list(mode="RAMP", round="R15", fq="FQ-028",
  question="퇴출 트리거를 챔피언 F-1(순위-단독)에 고정하고 빈 슬롯 충원(fill) 규율만 변주(수준-fill/신선-fill/무-fill 축소/일관성-fill)하면 cap-w 또는 oos가 움직이는가. R14 ④(ctrl_D2 fill 선택만으로 2.406↔2.503 이동)이 노출한 퇴출-직교 다이얼.",
  base="base_F1_level36fill (진입 반기 top-K20 by level36 · 퇴출 F-1 rank-only 분기 · 충원 level36-top = R14 ctrl_F1 2.937 정확 재현)",
  selection_type="chain",
  lattice="entry(반기 top-K20 level36)·exit(F-1 rank-only 분기) 전 arm 고정 → 차이는 빈 슬롯 충원 규율만. base=level36-fill, L-1=recent18-fill, L-2=no-fill(축소), L-3=consist-min-fill(12m×3)",
  endpoint_hierarchy=list(primary="oos_retention (v2 anchored 3분할 중앙값, cap-w act_bm)",
    secondary="port_t_capwt + HARD 3종 + EW-uni + 2017+ 분리 + paired vs base(F-1)",
    tension="endpoint=oos여도 arm '선택'은 IS-only(OOS 오염 방지). 선택=IS paired-t · 판정=게이트 산출 전체"),
  chain_discipline="arm 간 선택 IS-only(첫 65% 배포월 paired-t) · oos는 최종 게이트 산출로만 · 2차 결합 없음(1차만) · DSR 진단용(게이트 부적용)",
  arms=list(
    armL1_fresh_fill=list(mechanism="퇴출=F-1 rank-only(불변). 빈 슬롯 충원 = recent18 NW-t 상위 차순위(수준-fill 대신 신선-fill). 유한 recent18 소진 시 level36 순서로 tail 폴백(K20 유지)",
      diag="충원 시점은 정보가 가장 신선해야 할 순간 — 수준-fill(trailing 36m)은 감쇠 중인 팩터를 다시 들일 수 있다",
      adversarial="② L-1이 FM 수렴하는가 — fill에만 적용해도 pool이 FM화되는지 Jaccard(L-1 vs FMpure) vs (base vs FMpure)"),
    armL2_nofill_shrink=list(mechanism="퇴출=F-1 rank-only(불변). 퇴출 슬롯을 다음 반기 진입까지 미충원 → 팩터 pool 자연 축소(exit-only anchor 후 <K20). 종목 top-25는 잔여 풀 z-composite 합의로 유지. 다음 반기 진입서 level36 top-K20 재충전",
      diag="충원 자체가 잡음 유입일 가능성 — 검증된 생존자만으로 압축 운용. 팩터 breadth 축소가 신호를 정제하는가 잡음 낳는가",
      adversarial="① L-2가 K 축소 sweep(R6 K10 cap-w 1.906·oos -0.375)과 수렴하는가 — 유효 K(pool 크기 궤적)·수렴 여부 정량화"),
    armL3_consist_fill=list(mechanism="퇴출=F-1 rank-only(불변). 빈 슬롯 충원 = min(NW-t over 3 부분창 12m×3) 상위 차순위(R13 D-3 산식 fill에만 적용). 유한 consist-min 소진 시 level36 tail 폴백",
      diag="충원 팩터만큼은 감쇠-저항성(부분창 전반 일관) 검증을 요구 — 신규 진입에 지속성 프록시 게이트",
      adversarial="StabSel(relevance, R5 폐쇄)과 구분 = 라벨 realized active NW-t(수익)이지 relevance 아님. fill-only 적용이 pool 정체를 바꾸는가 Jaccard")),
  ctrl=list(anchor_R6_noexit="R6 Ppure_W36_K20(no-exit, level36-top) — vintage parity anchor(cap-w 2.6124 재현). 판정 arm 아님",
    r6_k10_ref="R6 Ppure_W36_K10 cap-w 1.9055·oos -0.3753 = L-2 무-fill 수렴 판별 대조(challenge ①)"),
  gate_hard=c(port_t_capwt=GATE_PT, oos_retention=OOS_TARGET, calmar=0.64, dsr=0.5),
  primary_criterion="1차 승자 = R15 자체 IS paired NW-t(cap-w act_bm) vs base(F-1) 최대(IS-only, JUDGED_ARMS만). 최종 판정 = oos_retention(1차) + full HARD 3종 + full paired vs base + cap-w(2차)",
  kill_rule="전 judged arm oos_retention 0.7 미도달 AND HARD 3종 0/N AND full paired<2.0 → config-scoped negative(충원 규율 config 한정). '소진/dead-end' 어휘 금지 — next_probe >=2 도출 의무",
  honest_frame="본 라운드=충원 규율 레버(퇴출과 직교). construction cap-w ~2.94 포화·oos 천장 ~+0.12 진단 존재 → 정직 기대=이 다이얼이 그 천장 밖 값을 내는지 판별(소폭 돌파 또는 재확인). ★설계상 fill은 exit-only anchor(교대구조상 반기당 1회)에서만 작동 → 개입 빈도 낮음 = 검정력 한계 사전 예고(challenge ③). return-derived substrate 재사용(신규 재료 아님). cap-tier×cap-w 벽 미해결 가능(정직 병기)",
  xmode_fail_prior="hypothesis_index: 'fill/충원' 키워드 0-coverage(novel 다이얼, INV-7 차별점 충족). 인접 prior: factor-momentum timing NULL(06-30)·DIST-AR-007 momentum return-파생 DISTILLED_NEG — L-1(recent18-fill)이 FM 계열 근접이나 ①fill-only 적용(전체 선별 아님)②재료=realized active NW-t(IC 아님)③퇴출 F-1 고정으로 pool 골격 유지 = family 근접하나 개입면 차별. R13 D-1(감쇠속도 선별)이 FM 수렴 붕괴(Jaccard vs FM 0.713)한 선례 → L-1 fill-only가 그 수렴을 회피하는지 판별.",
  is_frac=IS_FRAC, top_n=TOP_N, cost_bps_oneway=COST_BPS, liq_min=LIQ_MIN, cap=CAP, floor_frac=FLOOR_FRAC,
  cadence_entry=CADENCE_ENTRY, cadence_exit=CADENCE_EXIT, exit_rank_bar=EXIT_RANK_BAR,
  n_trials_r15=N_TRIALS_R15, n_trials_lineage=N_TRIALS_LINEAGE,
  ref=list(r14_ctrl_f1_capwt=R14_CTRLF1, r6_base=R6_BASE, r6_k10_capwt=R6_K10, r6_k10_oos=R6_K10_OOS),
  cost_model="delta-based |Δw|×15bps one-way (weighted_screen_bt 내장 — 충원 회전 자동 반영)",
  vintage_pin="r6_session_20260711 (sel_traj 36/pure_factor_scores/factor_group_scores/rawdata/panel; SUB=_ramp_r13_sub 재사용; base_F1 parity Δ<5e-3 확인)",
  as_of_date="2026-07-13", source_version="RAMP_R15_v1",
  security_id="Ticker (rawdata) -> factor_id z (pure_factor_scores.z=Z_Score_Aligned)")
CFG_HASH <- substr(digest::digest(PREREG, algo="sha256"), 1, 16)
PREREG$config_hash <- CFG_HASH
PREREG$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
jsonlite::write_json(PREREG, file.path(OUT, sprintf("r15_fill_prereg_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=6)
wf("=== RAMP R15: 충원(fill) 규율 축 chain (config_hash=%s) ===", CFG_HASH)
wf("judged arms: %s | base(paired)=%s | selection_type=chain | IS_FRAC=%.2f | n_trials R15=%d lineage=%d",
   paste(JUDGED_ARMS,collapse=","), BASE_LAB, IS_FRAC, N_TRIALS_R15, N_TRIALS_LINEAGE)
wf("endpoint: PRIMARY=oos_retention(v2) / SECONDARY=cap-w PORT_t | 선택=IS-only paired-t")
wf("EXIT=F-1 rank-only(고정, bar=%d) | fill: base=level36 / L-1=recent18 / L-2=none / L-3=consist-min(12m×3)", EXIT_RANK_BAR)

## ── 데이터 (R6/R10~R14 동일 소스) ──
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

## ── anchors ──
anchors_exit  <- seq(W36+1L, n_sig-1L, by=CADENCE_EXIT)   # 분기 퇴출 점검 (진입 anchor 포함하는 superset)
cohortEntry   <- seq(W36+1L, n_sig-1L, by=CADENCE_ENTRY)  # = base R6 anchors (반기 진입)
stopifnot(identical(as.integer(base_anchors), as.integer(cohortEntry)))

## ── SUB(부분창 NW-t) 재사용: R13 캐시 = level36/recent18/older18/sub1/sub2/sub3 @ anchors_exit∪base ──
SUB_CACHE <- file.path(".cache", sprintf("_ramp_r13_sub_%s.rds", RUNTAG))
if(!file.exists(SUB_CACHE)) stop("[R15] SUB 캐시 부재: ", SUB_CACHE, " — R13 먼저 실행 필요")
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

## ════════ fill-ranking 헬퍼 (각 fill 규율의 차순위 순서 — level36 tail 폴백으로 K20 항상 보장) ════════
rank_level36 <- function(S){ names(sort(S$level36[is.finite(S$level36)], decreasing=TRUE)) }
rank_recent18 <- function(S){ rec<-S$recent18; ord<-names(sort(rec[is.finite(rec)], decreasing=TRUE))
  rest <- setdiff(rank_level36(S), ord); c(ord, rest) }
rank_consist <- function(S){ lvl<-S$level36; s1<-S$sub1; s2<-S$sub2; s3<-S$sub3; nm<-names(lvl)
  fin <- nm[ is.finite(s1[nm]) & is.finite(s2[nm]) & is.finite(s3[nm]) ]
  ord <- if(length(fin)){ mn<-pmin(s1[fin],s2[fin],s3[fin]); names(mn)<-fin; names(sort(mn, decreasing=TRUE)) } else character(0)
  rest <- setdiff(rank_level36(S), ord); c(ord, rest) }

## ════════ 통일 fill-궤적 빌더 (entry·exit=F-1 rank 고정, fill_rule만 상이) ════════
##   fill_rule ∈ {"level36"(base), "recent18"(L-1), "none"(L-2), "consist"(L-3)}
build_pool_traj_fill <- function(fill_rule){
  held <- NULL; pool_by_anchor <- list()
  st <- list(n_check=0L, rank_fire=0L, n_exit=0L, n_exitcheck=0L,
             sum_slots=0L, sum_filled=0L, underfill_months=0L,
             pool_sizes=integer(0), fresh_frac_num=0L, fresh_frac_den=0L)
  for(a in anchors_exit){
    S <- SUB[[as.character(a)]]
    if(is.null(S) || is.null(S$level36)){ pool_by_anchor[[as.character(a)]] <- held; next }
    lvl <- S$level36; ranked_lvl <- rank_level36(S)
    is_entry <- a %in% cohortEntry
    if(is_entry || is.null(held)){
      held <- head(ranked_lvl, K20)                            # ★진입: 반기 full top-K20 by level36 (전 arm 동일)
    } else {
      st$n_exitcheck <- st$n_exitcheck + 1L
      keep <- character(0)
      for(f in held){                                          # ★퇴출: F-1 rank-only (전 arm 동일·고정)
        r  <- match(f, ranked_lvl); lf <- if(f %in% names(lvl)) lvl[[f]] else NA_real_
        keep_rank <- (!is.na(r) && r <= EXIT_RANK_BAR) && (is.finite(lf) && lf >= 0)
        st$n_check <- st$n_check + 1L
        if(!keep_rank) st$rank_fire <- st$rank_fire + 1L
        if(keep_rank) keep <- c(keep, f) else st$n_exit <- st$n_exit + 1L
      }
      slots <- K20 - length(keep)
      if(fill_rule == "none"){
        fill <- character(0)                                   # ★L-2: 무-fill (풀 자연 축소)
      } else {
        ranked_fill <- switch(fill_rule,
          "level36"  = ranked_lvl,                             # base F-1: 수준-fill
          "recent18" = rank_recent18(S),                       # L-1: 신선-fill
          "consist"  = rank_consist(S))                        # L-3: 일관성-fill
        fill <- if(slots > 0) head(setdiff(ranked_fill, keep), slots) else character(0)
        ## 신선도 진단: fill이 level36-fill과 다른 팩터를 실제로 뽑는가 (fresh_frac)
        if(slots > 0 && fill_rule != "level36"){
          base_fill <- head(setdiff(ranked_lvl, keep), slots)
          st$fresh_frac_num <- st$fresh_frac_num + length(setdiff(fill, base_fill))
          st$fresh_frac_den <- st$fresh_frac_den + length(fill)
        }
      }
      st$sum_slots <- st$sum_slots + slots; st$sum_filled <- st$sum_filled + length(fill)
      if(length(fill) < slots) st$underfill_months <- st$underfill_months + 1L
      held <- c(keep, fill)
    }
    st$pool_sizes <- c(st$pool_sizes, length(held))
    pool_by_anchor[[as.character(a)]] <- held
  }
  attr(pool_by_anchor, "stats") <- st
  pool_by_anchor
}
POOL_BASE <- build_pool_traj_fill("level36")   # base F-1 (level36-fill)
POOL_L1   <- build_pool_traj_fill("recent18")  # L-1 fresh
POOL_L2   <- build_pool_traj_fill("none")      # L-2 no-fill shrink
POOL_L3   <- build_pool_traj_fill("consist")   # L-3 consist-min

## ── FMpure 대조 pool (challenge ②: L-1 FM 수렴 판별) = base_anchors서 recent18 top-K20, no-exit ──
FMpure_pool <- list()
for(a in base_anchors){ S <- SUB[[as.character(a)]]; if(is.null(S)) next
  rec <- S$recent18; vr <- rec[is.finite(rec)]
  FMpure_pool[[as.character(a)]] <- names(sort(vr, decreasing=TRUE))[seq_len(min(K20,length(vr)))] }

## ── pool getters ──
getter_base_r6   <- function(i){ ga <- max(base_anchors[base_anchors<=i]); sel_traj[["36"]]$traj[[as.character(ga)]]$pool[["K20"]] }
getter_from_exit <- function(POOL){ force(POOL); function(i){ ga <- max(anchors_exit[anchors_exit<=i]); p <- POOL[[as.character(ga)]]; if(is.null(p)) getter_base_r6(i) else p } }
getter_BASE <- getter_from_exit(POOL_BASE); getter_L1 <- getter_from_exit(POOL_L1)
getter_L2   <- getter_from_exit(POOL_L2);   getter_L3 <- getter_from_exit(POOL_L3)
getter_FMpure <- function(i){ ga <- max(base_anchors[base_anchors<=i]); p<-FMpure_pool[[as.character(ga)]]; if(is.null(p)) getter_base_r6(i) else p }

## ── 공용: positive-shift 틸트 + cap water-fill (R10~R14 자구동일) ──
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

## ── composite 재구성 (R10~R14 build_composite EW 경로 자구동일) ──
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

## ── gate: weighted_screen_bt -> period_returns -> R6 estimator (R13/R14 gate_one 자구동일 + oos_ew 병기) ──
gate_one <- function(Wdt, lab){
  r <- tryCatch(weighted_screen_bt(Wdt, RET_DT, BENCH_DT, cost_bps_oneway=COST_BPS,
        run_id=paste0("r15_",lab), strategy_id=lab), error=function(e){ w("  [gate ERR ",lab,"] ",conditionMessage(e)); NULL })
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

## ════════════ 측정 (R6 anchor + base_F1 + 3 arm) ════════════
wf("\n=== 측정 (cap-w authoritative, weighted_screen_bt 계약경로) ===")
RES <- list(); PR <- list(); WMAP <- list(); CONC <- list(); COMPS <- list()
run_arm <- function(getter, lab){
  comp <- build_composite_g(getter); COMPS[[lab]] <<- comp
  W <- build_weights(comp, "ew")
  g <- gate_one(W, lab); RES[[lab]]<<-g$dt; PR[[lab]]<<-g$pr; WMAP[[lab]]<<-W; CONC[[lab]]<<-conc_diag(W,lab)
  wf("  [%-22s] pt_capwt=%+.3f pt_EWuni=%+.3f oos=%+.3f oos_ew=%+.3f calmar=%+.3f DSR=%+.3f post17SR=%+.3f TO=%.2f",
     lab, g$dt$port_t_capwt, g$dt$port_t_EWuni, g$dt$oos_retention, g$dt$oos_ew, g$dt$calmar, g$dt$dsr, g$dt$post2017_bm_sr, g$dt$turnover)
  invisible(g)
}
run_arm(getter_base_r6, "anchor_R6_noexit")
run_arm(getter_BASE,    "base_F1_level36fill")
run_arm(getter_L1,      "armL1_fresh_fill")
run_arm(getter_L2,      "armL2_nofill_shrink")
run_arm(getter_L3,      "armL3_consist_fill")

## ── parity: ①R6 anchor==2.6124  ②base_F1==R14 ctrl_F1 2.937 ──
r6_pt   <- RES[["anchor_R6_noexit"]]$port_t_capwt
baseF1_pt <- RES[["base_F1_level36fill"]]$port_t_capwt
r6_delta   <- abs(r6_pt - R6_BASE); r6_ok <- is.finite(r6_delta) && r6_delta < 5e-3
f1_delta   <- abs(baseF1_pt - R14_CTRLF1); f1_ok <- is.finite(f1_delta) && f1_delta < 5e-3
wf("\n[parity] R6 anchor cap-w=%.4f vs R6 저장 %.4f -> |Δ|=%.2e ok=%s", r6_pt, R6_BASE, r6_delta, r6_ok)
wf("[parity] base_F1 cap-w=%.4f vs R14 ctrl_F1 %.3f -> |Δ|=%.2e ok=%s (fill·exit 동일 → Δ=0 기대)", baseF1_pt, R14_CTRLF1, f1_delta, f1_ok)
if(!f1_ok) w("  ★ WARNING: base_F1 parity 미달 — 재구성 계열 라벨 강등 필요")

## ── paired NW-t (full + IS-only) vs base(F-1) ──
pair_full <- function(la){ if(is.null(PR[[la]])||is.null(PR[[BASE_LAB]])) return(NULL)
  m <- merge(PR[[la]][,.(date, a=act_bm)], PR[[BASE_LAB]][,.(date, b=act_bm)], by="date")
  d <- m$a - m$b; n_is <- floor(nrow(m)*IS_FRAC)
  data.table(model=la, mean_diff_ann=mean(d,na.rm=TRUE)*12,
    paired_t_full=nwt(d), paired_t_IS=nwt(d[seq_len(n_is)]), paired_t_OOS=nwt(d[(n_is+1L):nrow(m)]),
    n=nrow(m), n_is=n_is) }
PAIRED <- rbindlist(lapply(JUDGED_ARMS, pair_full), fill=TRUE)
wf("\n=== paired NW-t vs base(F-1) (IS_FRAC=%.2f: IS=첫 %d월 / OOS=나머지) ===", IS_FRAC, PAIRED$n_is[1])
for(i in seq_len(nrow(PAIRED))) wf("  [%-22s] Δ(ann)=%+.4f | paired_t: full=%+.3f IS=%+.3f OOS=%+.3f (n=%d)",
  PAIRED$model[i], PAIRED$mean_diff_ann[i], PAIRED$paired_t_full[i], PAIRED$paired_t_IS[i], PAIRED$paired_t_OOS[i], PAIRED$n[i])

## ── 1차 IS-only 승자 지목 (JUDGED_ARMS만, chain 규율 OOS 미조회) ──
winner <- PAIRED[which.max(paired_t_IS), model]; winner_is_t <- PAIRED[model==winner, paired_t_IS]
wf("\n=== 1차 IS-only 승자 (JUDGED_ARMS, chain: OOS 미조회) ===")
wf("  winner = %s (IS paired_t=%+.3f) | 서열(IS): %s", winner, winner_is_t,
   paste(sprintf("%s=%.2f", PAIRED$model, PAIRED$paired_t_IS), collapse=" > "))

TAB <- rbindlist(lapply(RES, function(x) x), fill=TRUE)
CONCT <- rbindlist(CONC, fill=TRUE)

## ── HARD 게이트표 (1차 oos 강조) ──
wf("\n=== HARD 게이트 (★1차 oos 0.7 / capwt %.2f(2차) / calmar 0.64 / DSR 0.5[chain 진단], n_trials lineage=%d) ===", GATE_PT, N_TRIALS_LINEAGE)
for(i in seq_len(nrow(TAB))){ r<-TAB[i]
  p<-c(oos=isTRUE(r$oos_retention>=OOS_TARGET), port_t=isTRUE(r$port_t_capwt>=GATE_PT), cal=isTRUE(r$calmar>=0.64))
  wf("  [%-22s] ★oos=%+.3f %s | pt=%+.3f %s cal=%+.3f %s -> %s", r$model, r$oos_retention, ifelse(p["oos"],"✓","✗"),
     r$port_t_capwt, ifelse(p["port_t"],"✓","✗"), r$calmar, ifelse(p["cal"],"✓","✗"), ifelse(all(p),"★GRADUATION","미달")) }

## ── concentration ──
wf("\n=== concentration ===")
wf("  %-22s %6s %6s %6s %6s %6s | %6s %6s %6s", "model","HHI","effN","maxw","nHold","minNH","MEGA","MID","OTHER")
for(i in seq_len(nrow(CONCT))){ r<-CONCT[i]
  wf("  %-22s %6.4f %6.2f %6.3f %6.1f %6.0f | %6.3f %6.3f %6.3f", r$model, r$hhi, r$n_eff, r$maxw, r$n_hold, r$min_nhold, r$w_MEGA, r$w_MID, r$w_OTHER) }

## ════════════ 챌린지 진단 (self-adversarial 재료) ════════════
wf("\n=== 챌린지 진단 ===")
stB<-attr(POOL_BASE,"stats"); stL1<-attr(POOL_L1,"stats"); stL2<-attr(POOL_L2,"stats"); stL3<-attr(POOL_L3,"stats")
pool_jac <- function(getA, getB){ idx <- (W36+1L):(n_sig-1L); jc <- c()
  for(i in idx){ a<-getA(i); b<-getB(i); if(length(a)&&length(b)) jc<-c(jc, length(intersect(a,b))/length(union(a,b))) }; mean(jc, na.rm=TRUE) }
psz <- function(st) c(mean=mean(st$pool_sizes), min=min(st$pool_sizes), max=max(st$pool_sizes))
## ① L-2 무-fill = K 축소 sweep 수렴? (pool 크기 궤적·유효 K vs R6 K10)
szB<-psz(stB); szL2<-psz(stL2)
wf("  ① L-2 무-fill 유효 K: base pool size mean=%.2f(min %.0f max %.0f) | L-2 mean=%.2f(min %.0f max %.0f)",
   szB["mean"],szB["min"],szB["max"], szL2["mean"],szL2["min"],szL2["max"])
wf("     L-2 exit-only anchor당 배출 slots: 총 slots=%d filled=%d underfill_months=%d/%d | R6 K10 참조 cap-w %.3f oos %.3f",
   stL2$sum_slots, stL2$sum_filled, stL2$underfill_months, stL2$n_exitcheck, R6_K10, R6_K10_OOS)
## ② L-1 신선-fill = FM 수렴? (fill-only 적용이 pool을 FM화하는지 Jaccard)
jac_L1_FM <- pool_jac(getter_L1, getter_FMpure); jac_base_FM <- pool_jac(getter_BASE, getter_FMpure)
jac_L3_FM <- pool_jac(getter_L3, getter_FMpure)
jac_L1_base <- pool_jac(getter_L1, getter_BASE); jac_L2_base <- pool_jac(getter_L2, getter_BASE); jac_L3_base <- pool_jac(getter_L3, getter_BASE)
fresh_L1 <- if(stL1$fresh_frac_den>0) stL1$fresh_frac_num/stL1$fresh_frac_den else NA_real_
fresh_L3 <- if(stL3$fresh_frac_den>0) stL3$fresh_frac_num/stL3$fresh_frac_den else NA_real_
wf("  ② L-1 FM 수렴: Jaccard(L-1↔FMpure)=%.3f vs (base↔FMpure)=%.3f (Δ=%+.3f=fill-only FM 주입폭) | Jaccard(L-1↔base)=%.3f",
   jac_L1_FM, jac_base_FM, jac_L1_FM-jac_base_FM, jac_L1_base)
wf("     fill이 level36-fill과 다른 팩터 뽑은 비율: L-1 fresh_frac=%.3f(%d/%d) L-3 fresh_frac=%.3f(%d/%d) | Jaccard(L-3↔base)=%.3f (L-3↔FMpure)=%.3f",
   fresh_L1, stL1$fresh_frac_num, stL1$fresh_frac_den, fresh_L3, stL3$fresh_frac_num, stL3$fresh_frac_den, jac_L3_base, jac_L3_FM)
## ③ fill 빈도 = 검정력 한계 (교대구조상 exit-only anchor에서만 fill 작동)
wf("  ③ fill 개입 빈도(검정력): exit-only anchor=%d개 · rank 퇴출 총 %d회 · anchor당 배출 slots 평균=%.2f | Jaccard(L-2↔base)=%.3f",
   stB$n_exitcheck, stB$rank_fire, stB$sum_slots/max(1,stB$n_exitcheck), jac_L2_base)

## ── oos subperiod 분해 (개선이 특정 시기 아티팩트인가) ──
oos_subperiod <- function(la){ if(is.null(PR[[la]])) return(NULL)
  pr <- PR[[la]]; pre <- pr[date<post2017, act_bm]; post <- pr[date>=post2017, act_bm]
  data.table(model=la, sr_full=srf(pr$act_bm), sr_pre2017=srf(pre), sr_post2017=srf(post),
    oos_full=oos3(pr$act_bm), oos_pre=oos3(pre), oos_post=oos3(post), n_pre=length(pre), n_post=length(post)) }
OOSSUB <- rbindlist(lapply(c(BASE_LAB,JUDGED_ARMS), oos_subperiod), fill=TRUE)
wf("\n  ④ oos/SR subperiod (2017 경계):")
for(i in seq_len(nrow(OOSSUB))){ r<-OOSSUB[i]
  wf("     [%-22s] SR full=%+.3f pre17=%+.3f post17=%+.3f | oos full=%+.3f pre=%+.3f post=%+.3f",
     r$model, r$sr_full, r$sr_pre2017, r$sr_post2017, r$oos_full, r$oos_pre, r$oos_post) }

## ── verdict 판정 (JUDGED_ARMS만, oos 1차 endpoint framing) ──
maxp_full <- suppressWarnings(max(PAIRED[model %in% JUDGED_ARMS, paired_t_full], na.rm=TRUE))
best_oos <- suppressWarnings(max(TAB[model %in% JUDGED_ARMS, oos_retention], na.rm=TRUE))
best_oos_arm <- TAB[model %in% JUDGED_ARMS][which.max(oos_retention)]
best_capwt_arm <- TAB[model %in% JUDGED_ARMS][which.max(port_t_capwt)]
any_grad <- any(is.finite(TAB$port_t_capwt) & TAB$port_t_capwt>=GATE_PT &
                is.finite(TAB$oos_retention) & TAB$oos_retention>=OOS_TARGET &
                is.finite(TAB$calmar) & TAB$calmar>=0.64 & TAB$model %in% JUDGED_ARMS)
base_oos <- TAB[model==BASE_LAB, oos_retention]; base_capwt <- TAB[model==BASE_LAB, port_t_capwt]
oos_improve <- best_oos - base_oos
KILL <- !(is.finite(best_oos) && best_oos>=OOS_TARGET) && !any_grad && !(is.finite(maxp_full) && maxp_full>=PAIRED_MEANINGFUL)
wf("\n=== 판정 gate (사전등록 — 1차 oos endpoint, JUDGED_ARMS만) ===")
wf("  ★ best oos_retention(arm) = %+.4f [%s] (target %.1f) | base(F-1) oos=%+.4f → Δoos=%+.4f",
   best_oos, best_oos_arm$model, OOS_TARGET, base_oos, oos_improve)
wf("  2차: best cap-w arm = %s %.3f (base F-1 %.3f) | max full paired = %+.3f (문턱 %.1f) | any GRADUATION = %s",
   best_capwt_arm$model, best_capwt_arm$port_t_capwt, base_capwt, maxp_full, PAIRED_MEANINGFUL, any_grad)
wf("  => config_scoped_negative(충원 규율 config 한정) = %s [종결 아님·next_probe 도출 의무]", KILL)

## ── 저장 ──
CHAL <- list(
  pool_size=list(base=as.list(szB), L1=as.list(psz(stL1)), L2=as.list(szL2), L3=as.list(psz(stL3))),
  fill_stats=list(base=stB[c("n_exitcheck","rank_fire","sum_slots","sum_filled","underfill_months")],
    L1=stL1[c("sum_slots","sum_filled","underfill_months","fresh_frac_num","fresh_frac_den")],
    L2=stL2[c("sum_slots","sum_filled","underfill_months")],
    L3=stL3[c("sum_slots","sum_filled","underfill_months","fresh_frac_num","fresh_frac_den")]),
  jaccard=list(L1_FM=jac_L1_FM, base_FM=jac_base_FM, L3_FM=jac_L3_FM,
    L1_base=jac_L1_base, L2_base=jac_L2_base, L3_base=jac_L3_base),
  fresh_frac=list(L1=fresh_L1, L3=fresh_L3),
  r6_k10_ref=list(capwt=R6_K10, oos=R6_K10_OOS),
  parity=list(r6_anchor=r6_delta, base_F1_vs_r14=f1_delta))
res <- list(prereg=PREREG, config_hash=CFG_HASH,
  meta=list(as_of_date="2026-07-13", generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
    source_version="RAMP_R15_v1", security_id="Ticker->factor_id z (pure_factor_scores.z=Z_Score_Aligned)"),
  results=TAB, paired=PAIRED, concentration=CONCT, oos_subperiod=OOSSUB,
  parity=list(r6_anchor_pt=r6_pt, r6_stored=R6_BASE, r6_delta=r6_delta, r6_ok=r6_ok,
    base_F1_pt=baseF1_pt, r14_ctrl_f1=R14_CTRLF1, f1_delta=f1_delta, f1_ok=f1_ok),
  winner_1st=winner, winner_is_t=winner_is_t,
  endpoint_primary="oos_retention", endpoint_secondary="port_t_capwt",
  challenge=CHAL,
  kill=KILL, max_paired_full=maxp_full, any_graduation=any_grad,
  base_oos=base_oos, base_capwt=base_capwt,
  best_oos_arm=best_oos_arm$model, best_oos_val=best_oos, best_capwt_arm=best_capwt_arm$model, best_capwt_val=best_capwt_arm$port_t_capwt,
  n_trials_r15=N_TRIALS_R15, n_trials_lineage=N_TRIALS_LINEAGE, selection_type="chain", n_sig=n_sig,
  date_range=as.character(range(sig_dates)))
saveRDS(list(res=res, PR=PR, TAB=TAB, PAIRED=PAIRED, WMAP=WMAP, CONC=CONCT, COMPS=COMPS, OOSSUB=OOSSUB,
  POOLS=list(BASE=POOL_BASE,L1=POOL_L1,L2=POOL_L2,L3=POOL_L3)), file.path(".cache", sprintf("_ramp_r15_%s.rds", RUNTAG)))
write_parquet(TAB, file.path(OUT, sprintf("r15_fill_gates_%s.parquet", RUNTAG)))
if(nrow(PAIRED)) write_parquet(PAIRED, file.path(OUT, sprintf("r15_fill_paired_%s.parquet", RUNTAG)))
write_parquet(CONCT, file.path(OUT, sprintf("r15_fill_conc_%s.parquet", RUNTAG)))
write_parquet(OOSSUB, file.path(OUT, sprintf("r15_fill_oossub_%s.parquet", RUNTAG)))
jsonlite::write_json(res, file.path(OUT, sprintf("r15_fill_summary_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=4)

## ── best variant period_returns (텔레그램 차트용 — best cap-w arm 표준 3종 + base F-1) ──
best_lab <- best_capwt_arm$model
if(!is.null(PR[[best_lab]])){
  bpr <- merge(PR[[best_lab]][,.(date, ret_net)], BENCH_DT[,.(date=Date, BM_Ret)], by="date")
  saveRDS(list(best_lab=best_lab, best_oos_lab=best_oos_arm$model,
               period_returns=data.table(date=bpr$date, ret_net=bpr$ret_net, benchmark_ret=bpr$BM_Ret),
               base_pr=merge(PR[[BASE_LAB]][,.(date,ret_net)], BENCH_DT[,.(date=Date,BM_Ret)], by="date")),
          file.path(".cache", sprintf("_ramp_r15_bestpr_%s.rds", RUNTAG)))
}

wf("\n=== VERDICT ===")
wf("  ★1차 best oos arm: %s oos=%+.4f (base F-1 %+.4f, Δ%+.4f) | target %.1f",
   best_oos_arm$model, best_oos, base_oos, oos_improve, OOS_TARGET)
wf("  2차 best cap-w arm: %s pt=%+.3f | IS 승자=%s | max full paired=%+.3f | config_scoped_negative=%s | parity F1=%s(Δ%.2e) R6=%s(Δ%.2e)",
   best_capwt_arm$model, best_capwt_arm$port_t_capwt, winner, maxp_full, KILL, f1_ok, f1_delta, r6_ok, r6_delta)
close(con)
cat(sprintf("R15_DONE. winner=%s neg=%s any_grad=%s best_oos=%.4f(baseF1 %.4f Δ%.4f) best_capwt=%.4f max_paired_full=%.3f f1_parity=%s(Δ%.2e) r6_parity=%s(Δ%.2e) log=%s\n",
   winner, KILL, any_grad, best_oos, base_oos, oos_improve, best_capwt_arm$port_t_capwt, maxp_full, f1_ok, f1_delta, r6_ok, r6_delta, logf))
cat(readLines(logf, encoding="UTF-8"), sep="\n")
