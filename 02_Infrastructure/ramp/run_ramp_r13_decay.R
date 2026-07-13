## run_ramp_r13_decay.R — RAMP R13: P-pure 감쇠속도(oos) 축 chain (FQ-026)
## ─────────────────────────────────────────────────────────────────────────────
## 도훈 mandate 2026-07-13: R12 메타진단의 축 전환을 소비. construction 4축(비중2.930·vintage2.895·
##   신선도2.852·비대칭퇴출2.937) 전부 cap-w ~2.94 포화 → 바인딩 실패 축 = oos_retention
##   (best +0.121 vs 문턱 0.7, construction-invariant). 따라서 1차 endpoint = oos_retention(v2),
##   cap-w는 2차 병기. 시간-함수형(선별 점수의 시간축)만 바꾸고 재료=realized active NW-t 그대로(R7 교훈).
##
## [endpoint 위계 (prereg 명시)] 1차 = oos_retention(v2 anchored 3분할 중앙값, cap-w act_bm)
##                              2차 = port_t_capwt (병기) + HARD 3종 + EW-uni + 2017+ 분리 + paired vs base
##   ★긴장 정직 기록: endpoint가 oos여도 arm '선택'은 IS-only(OOS 오염 방지). 선택=IS paired-t,
##     '판정'=게이트 산출 전체(oos 1차·cap-w 2차·HARD). oos는 최종 게이트 산출로만(선택 입력 아님).
##
## [chain 규율] measurement-graduation §3 — selection_type="chain"(sweep 아님. 각 arm=독립 감쇠 기전 가설):
##   · 각 arm = 변경사유 기전 진단 1줄(prereg). arm 간 선택 = IS-only(첫 65% 배포월 paired-t).
##   · 2차 결합 없음(1차만 — R11 IS-폐기 선례). DSR 진단용(chain → 게이트 부적용). n_trials lineage=24.
##
## [1차 3-arm] base = P-pure W36_K20 (종목 EW × 팩터 EW level36-top20, R6 저장 2.6124 parity 앵커)
##   arm D-1 (감쇠속도 선별): 선별점수 = z(level36) + λ·z(recent18_t − older18_t). λ=0.5(level-지배 보정).
##       수준 상위이나 최근-half 급락 팩터 강등. top-K20 by adj. base와 동일 base_anchors(cadence6).
##       기전: 수준-기반 trailing은 후행 평균 → 감쇠를 늦게 반영 = oos 실패의 직접 원인 가설.
##   arm D-2 (F-1a 융합): R12 F-1(반기 진입·분기 퇴출) 구조 유지 · 퇴출 트리거를 순위→감쇠속도로 교체
##       (held 팩터 recent18_t<0 OR (recent18_t−older18_t)<DROP_BAR(−1.0) 배출·빈슬롯 비-감쇠 차순위 충원).
##       기전: '무엇을 내보낼지'를 감쇠 신호로 직접 지정 — F-1(2.937 cap-w) 퇴출 규율에 감쇠 정보 주입.
##   arm D-3 (부분창 일관성): 선별점수 = min(NW-t over 3 부분창 12m×3). 부분창 전반 일관 팩터=감쇠저항 프록시.
##       기전: 지속성 프록시. 재료=realized active NW-t 그대로, 시간 함수형(min-subwindow)만 변경.
##       ⚠StabSel(서브샘플 LASSO relevance, R5 폐쇄)과 구분: 라벨=realized active NW-t(수익), relevance 아님.
##   ctrl_factormom (C① 대조군): top-K20 by recent18_t 단독(순수 팩터 모멘텀). D-1/D-2가 FM으로 수렴하는지 판별.
##
## [감쇠속도=팩터모멘텀 수렴 위험] R11 C① 방식(풀 churn·rank AC(Spearman)·Jaccard 궤적) vs ctrl_factormom 판별 의무.
##   교차모드 prior(hypothesis_index): "Alpha Decay Adaptive FM"·"IC Decay-Weighted FM" = MARGINAL,
##   "Cross-Factor Momentum" = FAIL, factor-momentum timing NULL(06-30), DIST-AR-007 momentum return-파생 = DISTILLED_NEG.
##   INV-7 재도전 차별점: ①endpoint=oos_retention(바인딩 벽, 직접 타깃 전무) ②재료=realized active NW-t(IC 아님)
##   ③D-3 min-subwindow=anti-momentum(지속성). = family(decay/FM) 동일하나 축·재료·구성 차별 명시.
##
## [측정 규율] proxy 손계산 없음 — weighted_screen_bt(계약, build_benchmark_compare) 경유. base parity == R6 2.6124.
## [실행] 단일스레드 · arrow io_thread(2) · pin r6 vintage 대조(1회) · governor 정지 · book 무변경.
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
logf <- file.path(".cache", sprintf("_ramp_r13_%s.txt", RUNTAG))
con <- file(logf,"w",encoding="UTF-8"); w<-function(...){ writeLines(paste0(...),con); flush(con) }; wf<-function(...){w(sprintf(...))}

## ── estimators (R6/R10/R11/R12 자구동일) ──
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA_real_); mean(x)/sd(x)*sqrt(12) }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
oos3 <- function(act){ .splits<-c(0.55,0.65,0.75)                       # v2 anchored 3분할 중앙값
  r <- sapply(.splits, function(fr){ k<-floor(length(act)*fr)
    if(k<12||(length(act)-k)<6) return(NA_real_); .is<-srf(act[1:k]); .oo<-srf(act[(k+1):length(act)])
    if(!is.na(.is)&&.is>0) .oo/.is else NA_real_ }); median(r, na.rm=TRUE) }
post2017 <- as.Date("2017-01-01")

## ── 사전등록 config (hash 동결) ──
TOP_N <- 25L; COST_BPS <- 15; LIQ_MIN <- 2e8; W36 <- 36L; W60 <- 60L; K20 <- 20L
CAP <- 0.20; FLOOR_FRAC <- 0.25
CADENCE_ENTRY <- 6L; CADENCE_EXIT <- 3L      # D-2: 진입 반기 / 퇴출 분기 (F-1 구조 승계)
LAMBDA_D1 <- 0.5                             # D-1: z(level) + λ·z(decay), level-지배 보정
DECAY_DROP_BAR <- -1.0                       # D-2: recent18_t − older18_t < −1.0 = 급락(퇴출)
GATE_PT <- 2.95; PAIRED_MEANINGFUL <- 2.0; OOS_TARGET <- 0.7
IS_FRAC <- 0.65                               # chain: IS-only 승자 지목용 (첫 65% 배포월)
N_TRIALS_R13 <- 3L                            # arm D-1, D-2, D-3 (2차 결합 없음)
N_TRIALS_LINEAGE <- 21L + N_TRIALS_R13        # P-pure 계보 chain 연속: R12까지 21 + R13 3 = 24 (chain — DSR 진단용)
R12_REF <- list(base_capwt=2.6124, base_oos=-0.0759, armF1_capwt=2.937, armF1_oos=0.0482, armF_oos_best=0.1208)
ARMS <- c("armD1_decay_penalty","armD2_decay_exit","armD3_subwin_consistency")
PREREG <- list(mode="RAMP", round="R13", fq="FQ-026",
  question="R12 메타진단 축전환(construction 4축 cap-w ~2.94 포화 → 바인딩 벽=oos_retention) 소비 — 감쇠속도 선별 3기전으로 oos 축 직타. 시간-함수형만 변경·재료=realized active NW-t 불변(R7)",
  base="Ppure_W36_K20 (종목 EW × 팩터 EW level36-top20, R6 저장 2.6124 parity 앵커)",
  selection_type="chain",
  endpoint_hierarchy=list(primary="oos_retention (v2 anchored 3분할 중앙값, cap-w act_bm)",
    secondary="port_t_capwt + HARD 3종 + EW-uni + 2017+ 분리 + paired vs base",
    tension="endpoint=oos여도 arm '선택'은 IS-only(OOS 오염 방지). 선택=IS paired-t · 판정=게이트 산출 전체. oos는 최종 게이트 산출로만(선택 입력 아님)"),
  chain_discipline="arm 간 선택 IS-only(첫 65% 배포월 paired-t) · oos는 최종 게이트 산출로만 · 2차 결합 없음(1차만) · DSR 진단용(게이트 부적용)",
  arms=list(
    armD1_decay_penalty=list(mechanism="선별점수 = z(level36) + 0.5·z(recent18_t − older18_t). 수준 상위이나 최근-half 급락 팩터 강등. top-K20 by adj. base와 동일 base_anchors(cadence6)",
      diag="수준-기반 trailing은 후행 평균 → 감쇠 늦게 반영 = oos 실패 직접 원인 가설. 감쇠속도 보정으로 선제 배출",
      adversarial="C① FM 수렴 = pool churn·rank AC(Spearman)·Jaccard vs ctrl_factormom(recent18 단독)"),
    armD2_decay_exit=list(mechanism="F-1(반기 진입·분기 퇴출) 구조 유지 · 퇴출 트리거 순위→감쇠속도(held recent18_t<0 OR decay<−1.0 배출·비-감쇠 차순위 충원)",
      diag="'무엇을 내보낼지'를 감쇠 신호로 직접 지정 — F-1(2.937) 퇴출 규율에 감쇠 정보 주입. F-1 oos(+0.048)<armF full(+0.121) 격차=진입측 갱신이 잡는 감쇠를 퇴출로 포획 가설",
      adversarial="C① FM 수렴 = churn·Jaccard vs ctrl_factormom + F-1 대비 pool 차이"),
    armD3_subwin_consistency=list(mechanism="선별점수 = min(NW-t over 3 부분창 12m×3). 부분창 전반 일관 팩터=감쇠저항 프록시. top-K20 by min_t",
      diag="지속성 프록시. 재료=realized active NW-t 그대로, 시간 함수형(min-subwindow)만 변경. anti-momentum(과거 약했으면 최근 강해도 강등)",
      adversarial="C② StabSel(서브샘플 LASSO relevance, R5 폐쇄)과 구분 = 라벨 realized active NW-t(수익)이지 relevance 아님 + FM Jaccard")),
  ctrl="ctrl_factormom: top-K20 by recent18_t 단독(순수 FM) — C① 수렴 대조군(판정 arm 아님)",
  no_2nd_combine="이번엔 1차만(결합은 R11서 IS-폐기 선례)",
  gate_hard=c(port_t_capwt=GATE_PT, oos_retention=OOS_TARGET, calmar=0.64, dsr=0.5),
  primary_criterion="1차 승자 = R13 자체 IS paired NW-t(cap-w act_bm) vs base 최대(IS-only). 최종 판정 = oos_retention(1차) + full HARD 3종 + full paired vs base + cap-w(2차)",
  kill_rule="전 arm oos_retention 0.7 미도달 AND HARD 3종 0/N AND full paired<2.0 → config-scoped negative(감쇠속도 선별 config 한정). '소진/dead-end' 어휘 금지 — next_probe >=2 도출 의무",
  honest_frame="본 라운드=감쇠속도 선별로 oos 축 직타. base oos −0.076·R12 best +0.121 vs 문턱 0.7 = 큰 격차 → 방향 개선이어도 0.7 도달 난망(정직 병기). return-derived substrate 재사용(신규 재료 아님). cap-tier×cap-w 벽 미해결 가능.",
  xmode_fail_prior="hypothesis_index: 'Alpha Decay Adaptive FM'·'IC Decay-Weighted FM' MARGINAL, 'Cross-Factor Momentum' FAIL, factor-momentum timing NULL(06-30), DIST-AR-007(momentum return-파생) DISTILLED_NEG. INV-7 재도전 차별점: ①endpoint=oos(바인딩 벽) ②재료=realized active NW-t(IC아님) ③D-3=anti-momentum(지속성)",
  is_frac=IS_FRAC, top_n=TOP_N, cost_bps_oneway=COST_BPS, liq_min=LIQ_MIN, cap=CAP, floor_frac=FLOOR_FRAC,
  cadence_entry=CADENCE_ENTRY, cadence_exit=CADENCE_EXIT, lambda_d1=LAMBDA_D1, decay_drop_bar=DECAY_DROP_BAR,
  windows=c(W36,W60), subwin_split=c(18,18), subwin3=c(12,12,12), n_trials_r13=N_TRIALS_R13, n_trials_lineage=N_TRIALS_LINEAGE, r12_ref=R12_REF,
  cost_model="delta-based |Δw|×15bps one-way (weighted_screen_bt 내장 — 선별 회전 자동 반영)",
  vintage_pin="r6_session_20260711 (sel_traj 36+60/pure_factor_scores/factor_group_scores/rawdata/panel; base parity Δ<5e-3 확인)",
  as_of_date="2026-07-13", source_version="RAMP_R13_v1",
  security_id="Ticker (rawdata) -> factor_id z (pure_factor_scores.z=Z_Score_Aligned)")
CFG_HASH <- substr(digest::digest(PREREG, algo="sha256"), 1, 16)
PREREG$config_hash <- CFG_HASH
PREREG$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
jsonlite::write_json(PREREG, file.path(OUT, sprintf("r13_decay_prereg_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=6)
wf("=== RAMP R13: 감쇠속도(oos) 축 chain (config_hash=%s) ===", CFG_HASH)
wf("arms: %s | ctrl=factormom | selection_type=chain | IS_FRAC=%.2f | n_trials R13=%d lineage=%d",
   paste(ARMS,collapse=","), IS_FRAC, N_TRIALS_R13, N_TRIALS_LINEAGE)
wf("endpoint: PRIMARY=oos_retention(v2) / SECONDARY=cap-w PORT_t | 선택=IS-only paired-t (oos 게이트 산출로만)")
wf("λ_D1=%.2f DECAY_DROP_BAR=%.2f | subwin: recent/older 18/18 · 3-subwin 12/12/12", LAMBDA_D1, DECAY_DROP_BAR)

## ── 데이터 (R6/R10/R11/R12 동일 소스) ──
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
base_anchors <- sel_traj[["36"]]$anchors                       # cadence 6 (base entry)
wf("substrate: %d approved factors | %d sig months %s~%s | base(36,cadence6) anchors=%d",
   length(POOL_FACS), n_sig, as.character(sig_dates[1]), as.character(sig_dates[n_sig]), length(base_anchors))

## ── 배포권 패널 Pmat (감쇠 부분창 NW-t용 — R6 factor_deployzone_active 재사용) ──
PANEL <- as.data.table(read_parquet(file.path(OUT,"r6_factor_deployzone_active.parquet"))); PANEL[, signal_date := as.Date(signal_date)]
PANEL_FACS <- sort(unique(PANEL$factor_id))
Pw <- dcast(PANEL, signal_date ~ factor_id, value.var="active_bm"); setorder(Pw, signal_date)
panel_dates <- Pw$signal_date; n_pm <- length(panel_dates)
Pmat <- as.matrix(Pw[, ..PANEL_FACS]); rownames(Pmat) <- as.character(panel_dates)
stopifnot(all(panel_dates == sig_dates[1:n_pm]))
wf("[panel] Pmat %d months x %d factors (감쇠 부분창 substrate)", n_pm, length(PANEL_FACS))

## ── 부분창 NW-t 벡터 (Pmat rows [a-back_start : a-back_end], 각 factor NW-t lag3) ──
win_nwt_vec <- function(a, back_start, back_end){
  lo <- a - back_start; hi <- a - back_end
  if(lo < 1L || hi > n_pm || lo > hi) return(NULL)
  sub <- Pmat[lo:hi, , drop=FALSE]
  apply(sub, 2, function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
    m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) })
}
## anchor 집합: base(cadence6, D-1/D-3/FM 선별) ∪ exit(cadence3, D-2) ∪ entry(cadence6)
anchors_exit  <- seq(W36+1L, n_sig-1L, by=CADENCE_EXIT)
cohortEntry   <- seq(W36+1L, n_sig-1L, by=CADENCE_ENTRY)
SUB_ANCHORS   <- sort(unique(c(as.integer(base_anchors), anchors_exit, cohortEntry)))
SUB_CACHE     <- file.path(".cache", sprintf("_ramp_r13_sub_%s.rds", RUNTAG))
if(file.exists(SUB_CACHE) && !nzchar(Sys.getenv("RAMP_R13_FORCE_SUB",""))){
  SUB <- readRDS(SUB_CACHE); wf("[cache] 부분창 NW-t 재사용: %s (%d anchors)", SUB_CACHE, length(SUB))
} else {
  wf("[compute] 부분창 NW-t %d anchors × (level36/recent18/older18/sub1/sub2/sub3) ...", length(SUB_ANCHORS))
  t0 <- Sys.time(); SUB <- list()
  for(a in SUB_ANCHORS){
    lvl <- win_nwt_vec(a, W36, 1L)        # level 36m
    if(is.null(lvl)) next
    SUB[[as.character(a)]] <- list(
      level36  = lvl,
      recent18 = win_nwt_vec(a, 18L, 1L),
      older18  = win_nwt_vec(a, 36L, 19L),
      sub1     = win_nwt_vec(a, 36L, 25L),   # oldest 12m
      sub2     = win_nwt_vec(a, 24L, 13L),   # middle 12m
      sub3     = win_nwt_vec(a, 12L, 1L))    # recent 12m
  }
  saveRDS(SUB, SUB_CACHE)
  wf("[compute] 부분창 NW-t 완료 %.0fs (%d valid anchors)", as.numeric(Sys.time()-t0,units="secs"), length(SUB))
}
## sanity: fresh level36 vs sel_traj trailing_t (base anchor 1개)
.chk_a <- as.character(base_anchors[ceiling(length(base_anchors)/2)])
if(!is.null(SUB[[.chk_a]]) && !is.null(sel_traj[["36"]]$traj[[.chk_a]]$trailing_t)){
  a1 <- SUB[[.chk_a]]$level36; a2 <- sel_traj[["36"]]$traj[[.chk_a]]$trailing_t
  cf <- intersect(names(a1[is.finite(a1)]), names(a2[is.finite(a2)]))
  wf("[sanity] fresh level36 vs sel_traj trailing_t @anchor %s: max|Δ|=%.2e (n=%d) — level 재계산 정합",
     .chk_a, max(abs(a1[cf]-a2[cf])), length(cf))
}

## ── 감쇠속도 선별 pool (D-1/D-3/FM: base_anchors 별 top-K20) ──
sel_pool_D1 <- list(); sel_pool_D3 <- list(); sel_pool_FM <- list()
for(a in base_anchors){
  S <- SUB[[as.character(a)]]; if(is.null(S)) next
  lvl <- S$level36; rec <- S$recent18; old <- S$older18
  ## D-1: z(level) + λ·z(decay); valid = finite lvl ∧ finite decay
  dec <- rec - old
  vd <- names(lvl)[ is.finite(lvl) & is.finite(dec[names(lvl)]) ]
  if(length(vd) >= K20){
    adj <- zc(lvl[vd]) + LAMBDA_D1 * zc(dec[vd]); names(adj) <- vd
    sel_pool_D1[[as.character(a)]] <- names(sort(adj, decreasing=TRUE))[seq_len(K20)]
  } else sel_pool_D1[[as.character(a)]] <- names(sort(lvl[is.finite(lvl)], decreasing=TRUE))[seq_len(min(K20,sum(is.finite(lvl))))]
  ## D-3: min over 3 subwindows; valid = finite in all three
  s1<-S$sub1; s2<-S$sub2; s3<-S$sub3
  vv <- names(lvl)[ is.finite(s1[names(lvl)]) & is.finite(s2[names(lvl)]) & is.finite(s3[names(lvl)]) ]
  if(length(vv) >= K20){
    mn <- pmin(s1[vv], s2[vv], s3[vv]); names(mn) <- vv
    sel_pool_D3[[as.character(a)]] <- names(sort(mn, decreasing=TRUE))[seq_len(K20)]
  } else sel_pool_D3[[as.character(a)]] <- names(sort(lvl[is.finite(lvl)], decreasing=TRUE))[seq_len(min(K20,sum(is.finite(lvl))))]
  ## ctrl FM: recent18 단독
  vr <- rec[is.finite(rec)]
  sel_pool_FM[[as.character(a)]] <- names(sort(vr, decreasing=TRUE))[seq_len(min(K20,length(vr)))]
}

## ── D-2 비대칭 퇴출(감쇠속도) pool 궤적(stateful) — 반기 full 진입 + 분기 감쇠 퇴출 + 비-감쇠 충원 ──
build_pool_traj_D2 <- function(){
  held <- NULL; pool_by_anchor <- list()
  for(a in anchors_exit){
    S <- SUB[[as.character(a)]]
    if(is.null(S) || is.null(S$level36)){ pool_by_anchor[[as.character(a)]] <- held; next }
    lvl <- S$level36; rec <- S$recent18; dec <- rec - S$older18
    ranked_lvl <- names(sort(lvl[is.finite(lvl)], decreasing=TRUE))
    is_entry <- a %in% cohortEntry
    if(is_entry || is.null(held)){
      held <- head(ranked_lvl, K20)                             # 반기 full top-K20 진입(level36)
    } else {
      keep <- held[ vapply(held, function(f){                   # 감쇠 퇴출: recent18<0 OR decay<DROP_BAR
        rf <- if(f %in% names(rec)) rec[[f]] else NA_real_
        df <- if(f %in% names(dec)) dec[[f]] else NA_real_
        (is.finite(rf) && rf >= 0) && !(is.finite(df) && df < DECAY_DROP_BAR) }, logical(1)) ]
      slots <- K20 - length(keep)
      if(slots > 0){
        pool_rank <- setdiff(ranked_lvl, keep)
        clean <- pool_rank[ vapply(pool_rank, function(f){ rf<-if(f %in% names(rec)) rec[[f]] else NA_real_; !is.finite(rf) || rf >= 0 }, logical(1)) ]
        fill <- head(clean, slots)
        if(length(fill) < slots){ rest <- setdiff(pool_rank, fill); fill <- c(fill, head(rest, slots-length(fill))) }
        held <- c(keep, fill)
      } else held <- keep
    }
    pool_by_anchor[[as.character(a)]] <- held
  }
  pool_by_anchor
}
POOL_D2 <- build_pool_traj_D2()

## ── pool getters (arm별) ──
getter_base <- function(i){ ga <- max(base_anchors[base_anchors<=i]); sel_traj[["36"]]$traj[[as.character(ga)]]$pool[["K20"]] }
getter_D1   <- function(i){ ga <- max(base_anchors[base_anchors<=i]); p <- sel_pool_D1[[as.character(ga)]]; if(is.null(p)) getter_base(i) else p }
getter_D3   <- function(i){ ga <- max(base_anchors[base_anchors<=i]); p <- sel_pool_D3[[as.character(ga)]]; if(is.null(p)) getter_base(i) else p }
getter_FM   <- function(i){ ga <- max(base_anchors[base_anchors<=i]); p <- sel_pool_FM[[as.character(ga)]]; if(is.null(p)) getter_base(i) else p }
getter_D2   <- function(i){ ga <- max(anchors_exit[anchors_exit<=i]); p <- POOL_D2[[as.character(ga)]]; if(is.null(p)) getter_base(i) else p }

## ── 공용: positive-shift 틸트 + cap water-fill (R10/R11/R12 자구동일) ──
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

## ── composite 재구성 (R10/R11/R12 build_composite EW 경로 자구동일 — pool getter만 파라미터화) ──
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

## ── weights_dt 빌더: composite -> top-25 -> 종목 EW (R10/R11/R12 build_weights 자구동일) ──
build_weights <- function(comp, stock_mode){
  S <- comp[!is.na(score), .(Date=as.Date(signal_date), Ticker=security_id, score)]
  S <- merge(S, LIQ_DT[, .(Date, Ticker, adv)], by=c("Date","Ticker"), all.x=TRUE)
  S <- S[is.na(adv) | adv >= LIQ_MIN]; S[, adv := NULL]
  setorder(S, Date, -score)
  S[, {
    n <- min(TOP_N, .N); sc_sel <- score[seq_len(n)]
    .(Ticker=Ticker[seq_len(n)], w=stock_weights(sc_sel, stock_mode))
  }, by=Date]
}

## ── gate: weighted_screen_bt -> period_returns -> R6 estimator (R10/R11/R12 gate_one 자구동일 + oos_ew 병기) ──
gate_one <- function(Wdt, lab){
  r <- tryCatch(weighted_screen_bt(Wdt, RET_DT, BENCH_DT, cost_bps_oneway=COST_BPS,
        run_id=paste0("r13_",lab), strategy_id=lab), error=function(e){ w("  [gate ERR ",lab,"] ",conditionMessage(e)); NULL })
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

## ════════════ 1차 측정 (base + 3 arm + FM 대조군) ════════════
wf("\n=== 1차 측정 (cap-w authoritative, weighted_screen_bt 계약경로) ===")
RES <- list(); PR <- list(); WMAP <- list(); CONC <- list(); COMPS <- list()
run_arm <- function(getter, lab, weight_mode="ew"){
  comp <- build_composite_g(getter); COMPS[[lab]] <<- comp
  W <- build_weights(comp, weight_mode)
  g <- gate_one(W, lab); RES[[lab]]<<-g$dt; PR[[lab]]<<-g$pr; WMAP[[lab]]<<-W; CONC[[lab]]<<-conc_diag(W,lab)
  wf("  [%-24s] pt_capwt=%+.3f pt_EWuni=%+.3f oos=%+.3f oos_ew=%+.3f calmar=%+.3f DSR=%+.3f post17SR=%+.3f TO=%.2f",
     lab, g$dt$port_t_capwt, g$dt$port_t_EWuni, g$dt$oos_retention, g$dt$oos_ew, g$dt$calmar, g$dt$dsr, g$dt$post2017_bm_sr, g$dt$turnover)
  invisible(g)
}
run_arm(getter_base, "base")
run_arm(getter_D1,   "armD1_decay_penalty")
run_arm(getter_D2,   "armD2_decay_exit")
run_arm(getter_D3,   "armD3_subwin_consistency")
run_arm(getter_FM,   "ctrl_factormom")

## ── base parity: cap-w == R6 저장 2.6124 ──
base_pt <- RES[["base"]]$port_t_capwt; R6_BASE <- 2.6124
parity_delta <- abs(base_pt - R6_BASE); parity_ok <- is.finite(parity_delta) && parity_delta < 5e-3
wf("\n[base parity] R13 base cap-w PORT_t=%.4f vs R6 저장 %.4f -> |Δ|=%.2e ok=%s", base_pt, R6_BASE, parity_delta, parity_ok)
if(!parity_ok) w("  ★ WARNING: base parity 미달 — 재구성 계열 라벨 강등 필요")

## ── paired NW-t (full + IS-only) vs base ──
pair_full <- function(la){ if(is.null(PR[[la]])||is.null(PR[["base"]])) return(NULL)
  m <- merge(PR[[la]][,.(date, a=act_bm)], PR[["base"]][,.(date, b=act_bm)], by="date")
  d <- m$a - m$b; n_is <- floor(nrow(m)*IS_FRAC)
  data.table(model=la, mean_diff_ann=mean(d,na.rm=TRUE)*12,
    paired_t_full=nwt(d), paired_t_IS=nwt(d[seq_len(n_is)]), paired_t_OOS=nwt(d[(n_is+1L):nrow(m)]),
    n=nrow(m), n_is=n_is) }
PAIRED <- rbindlist(lapply(ARMS, pair_full), fill=TRUE)
wf("\n=== paired NW-t vs base (IS_FRAC=%.2f: IS=첫 %d월 / OOS=나머지) ===", IS_FRAC, PAIRED$n_is[1])
for(i in seq_len(nrow(PAIRED))) wf("  [%-24s] Δ(ann)=%+.4f | paired_t: full=%+.3f IS=%+.3f OOS=%+.3f (n=%d)",
  PAIRED$model[i], PAIRED$mean_diff_ann[i], PAIRED$paired_t_full[i], PAIRED$paired_t_IS[i], PAIRED$paired_t_OOS[i], PAIRED$n[i])

## ── 1차 IS-only 승자 지목 (chain 규율, OOS 미조회) ──
winner <- PAIRED[which.max(paired_t_IS), model]
winner_is_t <- PAIRED[model==winner, paired_t_IS]
wf("\n=== 1차 IS-only 승자 (chain: OOS 미조회) ===")
wf("  winner = %s (IS paired_t=%+.3f) | 서열(IS): %s", winner, winner_is_t,
   paste(sprintf("%s=%.2f", PAIRED$model, PAIRED$paired_t_IS), collapse=" > "))

TAB <- rbindlist(lapply(RES, function(x) x), fill=TRUE)
CONCT <- rbindlist(CONC, fill=TRUE)

## ── HARD 게이트표 (1차 endpoint=oos_retention 강조) ──
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

## ════════════ 챌린지 진단: 감쇠속도 = 팩터모멘텀 수렴? (R11 C① 방식) ════════════
wf("\n=== 챌린지 진단: FM 수렴 (churn·rank AC(Spearman)·Jaccard vs ctrl_factormom) ===")
## pool churn (연속 배포월 pool 간 churn/K20)
pool_churn_traj <- function(getf){ idx <- (W36+1L):(n_sig-1L); ch <- c(); prev <- NULL
  for(i in idx){ p <- getf(i); if(!is.null(prev)) ch <- c(ch, length(setdiff(p, prev))/K20); prev <- p }; mean(ch, na.rm=TRUE) }
## Jaccard between arm pool and FM pool (per deploy month)
pool_jac_vs <- function(getA, getB){ idx <- (W36+1L):(n_sig-1L); jc <- c()
  for(i in idx){ a<-getA(i); b<-getB(i); if(length(a)&&length(b)) jc<-c(jc, length(intersect(a,b))/length(union(a,b))) }; mean(jc, na.rm=TRUE) }
## rank AC: consecutive base_anchors 선별 score 벡터 Spearman (high=stable, low=churning like momentum)
rank_ac <- function(score_by_anchor){ ac <- c(); prev <- NULL
  for(a in base_anchors){ s <- score_by_anchor[[as.character(a)]]
    if(!is.null(prev) && !is.null(s)){ cf <- intersect(names(prev[is.finite(prev)]), names(s[is.finite(s)]))
      if(length(cf)>=10) ac <- c(ac, cor(prev[cf], s[cf], method="spearman")) }; prev <- s }
  mean(ac, na.rm=TRUE) }
## score_by_anchor 재구성 (D-1 adj / D-3 min / FM recent18 / base level36)
score_D1 <- list(); score_D3 <- list(); score_FM <- list(); score_base <- list()
for(a in base_anchors){ S <- SUB[[as.character(a)]]; if(is.null(S)) next
  lvl<-S$level36; dec<-S$recent18 - S$older18
  vd <- names(lvl)[ is.finite(lvl) & is.finite(dec[names(lvl)]) ]
  if(length(vd)) { adj <- zc(lvl[vd]) + LAMBDA_D1*zc(dec[vd]); names(adj)<-vd; score_D1[[as.character(a)]] <- adj }
  vv <- names(lvl)[ is.finite(S$sub1[names(lvl)]) & is.finite(S$sub2[names(lvl)]) & is.finite(S$sub3[names(lvl)]) ]
  if(length(vv)){ mn <- pmin(S$sub1[vv],S$sub2[vv],S$sub3[vv]); names(mn)<-vv; score_D3[[as.character(a)]] <- mn }
  score_FM[[as.character(a)]] <- S$recent18; score_base[[as.character(a)]] <- lvl }
ch_base<-pool_churn_traj(getter_base); ch_D1<-pool_churn_traj(getter_D1); ch_D2<-pool_churn_traj(getter_D2); ch_D3<-pool_churn_traj(getter_D3); ch_FM<-pool_churn_traj(getter_FM)
jac_D1_FM<-pool_jac_vs(getter_D1,getter_FM); jac_D2_FM<-pool_jac_vs(getter_D2,getter_FM); jac_D3_FM<-pool_jac_vs(getter_D3,getter_FM)
jac_D1_base<-pool_jac_vs(getter_D1,getter_base); jac_D2_base<-pool_jac_vs(getter_D2,getter_base); jac_D3_base<-pool_jac_vs(getter_D3,getter_base)
ac_base<-rank_ac(score_base); ac_D1<-rank_ac(score_D1); ac_D3<-rank_ac(score_D3); ac_FM<-rank_ac(score_FM)
wf("  churn/K20:  base=%.3f D1=%.3f D2=%.3f D3=%.3f FM=%.3f", ch_base, ch_D1, ch_D2, ch_D3, ch_FM)
wf("  Jaccard vs FM:   D1=%.3f D2=%.3f D3=%.3f  (높을수록 FM 수렴)", jac_D1_FM, jac_D2_FM, jac_D3_FM)
wf("  Jaccard vs base: D1=%.3f D2=%.3f D3=%.3f  (감쇠선별이 base와 얼마나 다른가)", jac_D1_base, jac_D2_base, jac_D3_base)
wf("  rank AC(Spearman): base=%.3f D1=%.3f D3=%.3f FM=%.3f  (낮을수록 churning=momentum-like)", ac_base, ac_D1, ac_D3, ac_FM)

## ── oos subperiod 분해 (챌린지 ③: oos 개선이 특정 시기 아티팩트인지) ──
oos_subperiod <- function(la){ if(is.null(PR[[la]])) return(NULL)
  pr <- PR[[la]]; pre <- pr[date<post2017, act_bm]; post <- pr[date>=post2017, act_bm]
  data.table(model=la, sr_full=srf(pr$act_bm), sr_pre2017=srf(pre), sr_post2017=srf(post),
    oos_full=oos3(pr$act_bm), oos_pre=oos3(pre), oos_post=oos3(post), n_pre=length(pre), n_post=length(post)) }
OOSSUB <- rbindlist(lapply(c("base",ARMS,"ctrl_factormom"), oos_subperiod), fill=TRUE)
wf("\n=== oos/SR subperiod 분해 (2017 경계 — 챌린지 ③ 시기 아티팩트 판별) ===")
for(i in seq_len(nrow(OOSSUB))){ r<-OOSSUB[i]
  wf("  [%-24s] SR full=%+.3f pre17=%+.3f post17=%+.3f | oos full=%+.3f pre=%+.3f post=%+.3f",
     r$model, r$sr_full, r$sr_pre2017, r$sr_post2017, r$oos_full, r$oos_pre, r$oos_post) }

## ── pool 구성 변화 (챌린지 ②: 감쇠 페널티가 sticky-Value 풀 정체를 바꾸는가) ──
##   base pool vs D-1 pool 평균 중첩 + 각 pool 회전 대비. (D-1이 base와 다른 팩터를 실제로 뽑는가)
wf("\n=== pool 구성 변화 (챌린지 ②: 감쇠 페널티가 풀 정체를 바꾸는가) ===")
wf("  Jaccard(D1,base)=%.3f Jaccard(D3,base)=%.3f Jaccard(D2,base)=%.3f | pool churn D1=%.3f vs base=%.3f (Δ=%+.3f)",
   jac_D1_base, jac_D3_base, jac_D2_base, ch_D1, ch_base, ch_D1-ch_base)

## ── verdict 판정 (사전등록 — oos 1차 endpoint framing) ──
maxp_full <- suppressWarnings(max(PAIRED[model %in% ARMS, paired_t_full], na.rm=TRUE))
best_oos <- suppressWarnings(max(TAB[model %in% ARMS, oos_retention], na.rm=TRUE))
best_oos_arm <- TAB[model %in% ARMS][which.max(oos_retention)]
best_capwt_arm <- TAB[model %in% ARMS][which.max(port_t_capwt)]
any_grad <- any(is.finite(TAB$port_t_capwt) & TAB$port_t_capwt>=GATE_PT &
                is.finite(TAB$oos_retention) & TAB$oos_retention>=OOS_TARGET &
                is.finite(TAB$calmar) & TAB$calmar>=0.64 & TAB$model %in% ARMS)
base_oos <- TAB[model=="base", oos_retention]; oos_improve <- best_oos - base_oos
KILL <- !(is.finite(best_oos) && best_oos>=OOS_TARGET) && !any_grad && !(is.finite(maxp_full) && maxp_full>=PAIRED_MEANINGFUL)
wf("\n=== 판정 gate (사전등록 — 1차 oos endpoint) ===")
wf("  ★ best oos_retention(arm) = %+.4f [%s] (target %.1f) | base oos=%+.4f → Δoos=%+.4f (개선 방향?)",
   best_oos, best_oos_arm$model, OOS_TARGET, base_oos, oos_improve)
wf("  2차: best cap-w arm = %s %.3f | max full paired = %+.3f (문턱 %.1f) | any GRADUATION = %s",
   best_capwt_arm$model, best_capwt_arm$port_t_capwt, maxp_full, PAIRED_MEANINGFUL, any_grad)
wf("  => config_scoped_negative(감쇠속도 선별 config 한정) = %s [종결 아님·next_probe 도출 의무]", KILL)

## ── 저장 ──
res <- list(prereg=PREREG, config_hash=CFG_HASH,
  meta=list(as_of_date="2026-07-13", generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
    source_version="RAMP_R13_v1", security_id="Ticker->factor_id z (pure_factor_scores.z=Z_Score_Aligned)"),
  results=TAB, paired=PAIRED, concentration=CONCT, oos_subperiod=OOSSUB,
  base_parity=list(r13_base_pt=base_pt, r6_stored=R6_BASE, delta=parity_delta, ok=parity_ok),
  winner_1st=winner, winner_is_t=winner_is_t,
  endpoint_primary="oos_retention", endpoint_secondary="port_t_capwt",
  challenge=list(
    fm_convergence=list(churn_base=ch_base, churn_D1=ch_D1, churn_D2=ch_D2, churn_D3=ch_D3, churn_FM=ch_FM,
      jaccard_D1_FM=jac_D1_FM, jaccard_D2_FM=jac_D2_FM, jaccard_D3_FM=jac_D3_FM,
      jaccard_D1_base=jac_D1_base, jaccard_D2_base=jac_D2_base, jaccard_D3_base=jac_D3_base,
      rank_ac_base=ac_base, rank_ac_D1=ac_D1, rank_ac_D3=ac_D3, rank_ac_FM=ac_FM),
    oos_improve=oos_improve, base_oos=base_oos, best_oos=best_oos, best_oos_arm=best_oos_arm$model),
  kill=KILL, max_paired_full=maxp_full, any_graduation=any_grad,
  best_oos_arm=best_oos_arm$model, best_oos_val=best_oos, best_capwt_arm=best_capwt_arm$model, best_capwt_val=best_capwt_arm$port_t_capwt,
  n_trials_r13=N_TRIALS_R13, n_trials_lineage=N_TRIALS_LINEAGE, selection_type="chain", n_sig=n_sig,
  date_range=as.character(range(sig_dates)), r12_ref=R12_REF)
saveRDS(list(res=res, PR=PR, TAB=TAB, PAIRED=PAIRED, WMAP=WMAP, CONC=CONCT, COMPS=COMPS, OOSSUB=OOSSUB), file.path(".cache", sprintf("_ramp_r13_%s.rds", RUNTAG)))
write_parquet(TAB, file.path(OUT, sprintf("r13_decay_gates_%s.parquet", RUNTAG)))
if(nrow(PAIRED)) write_parquet(PAIRED, file.path(OUT, sprintf("r13_decay_paired_%s.parquet", RUNTAG)))
write_parquet(CONCT, file.path(OUT, sprintf("r13_decay_conc_%s.parquet", RUNTAG)))
write_parquet(OOSSUB, file.path(OUT, sprintf("r13_decay_oossub_%s.parquet", RUNTAG)))
jsonlite::write_json(res, file.path(OUT, sprintf("r13_decay_summary_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=4)

## ── best variant period_returns (텔레그램 차트용 — oos 1차이나 차트는 best cap-w arm 표준 3종) ──
best_lab <- best_capwt_arm$model
if(!is.null(PR[[best_lab]])){
  bpr <- merge(PR[[best_lab]][,.(date, ret_net)], BENCH_DT[,.(date=Date, BM_Ret)], by="date")
  saveRDS(list(best_lab=best_lab, best_oos_lab=best_oos_arm$model,
               period_returns=data.table(date=bpr$date, ret_net=bpr$ret_net, benchmark_ret=bpr$BM_Ret),
               base_pr=merge(PR[["base"]][,.(date,ret_net)], BENCH_DT[,.(date=Date,BM_Ret)], by="date")),
          file.path(".cache", sprintf("_ramp_r13_bestpr_%s.rds", RUNTAG)))
}

wf("\n=== VERDICT ===")
wf("  ★1차 best oos arm: %s oos=%+.4f (base %+.4f, Δ%+.4f) | target %.1f",
   best_oos_arm$model, best_oos, base_oos, oos_improve, OOS_TARGET)
wf("  2차 best cap-w arm: %s pt=%+.3f | 1차 IS 승자=%s | max full paired=%+.3f | config_scoped_negative=%s | base_parity=%s",
   best_capwt_arm$model, best_capwt_arm$port_t_capwt, winner, maxp_full, KILL, parity_ok)
close(con)
cat(sprintf("R13_DONE. winner=%s neg=%s any_grad=%s best_oos=%.4f(base %.4f Δ%.4f) max_paired_full=%.3f base_parity=%s(Δ%.2e) log=%s\n",
   winner, KILL, any_grad, best_oos, base_oos, oos_improve, maxp_full, parity_ok, parity_delta, logf))
cat(readLines(logf, encoding="UTF-8"), sep="\n")
