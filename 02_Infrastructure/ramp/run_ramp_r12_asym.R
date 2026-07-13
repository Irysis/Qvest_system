## run_ramp_r12_asym.R — RAMP R12: P-pure 비대칭·이질 construction chain (FQ-025)
## ─────────────────────────────────────────────────────────────────────────────
## 도훈 mandate 2026-07-13: R11 next_probe 수렴점 소비. "퇴출은 빠르게, 진입은 엄격하게" 비대칭.
## 수렴 진단(존재 이유): armF(신선 풀 우위, oos +0.121 사상최고 — factor-momentum 아님) +
##   armB(대칭 밴드 FALSIFIED — 히스테리시스가 감쇠명 지연보유로 손해, 경계 churn=신호)
##   → 두 실패의 공통 처방 = 비대칭(퇴출 빠르게·진입 엄격하게).
##
## [chain 규율] measurement-graduation §3 — selection_type="chain"(sweep 아님. 각 arm이 R11 진단에 1:1):
##   · 각 arm = 독립 기전 가설 + 변경사유 기전 진단 1줄(prereg)
##   · arm 간 선택 = IS-only(첫 65% 배포월 paired-t). oos_retention은 최종 게이트 산출로만.
##   · 2차 결합 없음(이번엔 1차만 — R11서 IS-폐기 선례). DSR은 진단용(chain → 게이트 부적용).
##   · OOS 노출 관리: R11 OOS 수치는 arm '선택 입력'으로 쓰지 않는다(가설 동기로만). R12는 자체 사전등록 신규 측정.
##
## [1차 3-arm] base = P-pure W36_K20 (종목 EW × 팩터 EW, R6 저장 2.6124 parity 앵커. 참고: R11 armF 2.852 / armV 2.895)
##   arm F-1 (팩터 퇴출 비대칭): 진입=반기(cadence6) full top-K20 유지 / 퇴출=분기(cadence3) 즉시
##       (held 팩터의 현 trailing-t rank>EXIT_RANK_BAR(30) 또는 trailing-t<0 이면 배출·빈 슬롯은 차순위 충원).
##       기전: armF 개선의 원천이 '감쇠 팩터 조기 제거'라면 갱신 전체(armF full 재선별) 아니라 퇴출만 빨라도 충분,
##             회전 비용은 더 적다. (C① 차별성 = F-1 pool churn·TO·Jaccard vs armF cadence3 대조)
##   arm B-1 (종목 비대칭 밴드): R11 대칭밴드[25,35]의 정확한 역 — 진입 엄격(rank<=20 만 신규진입)·퇴출 즉시(rank>25 이탈 시 매도).
##       25종 미달 월은 기존 보유 유지분(직전 held)으로 best-rank 순 충원(봉투 <=25 준수).
##       기전: armB 반증이 가리킨 방향 — 퇴출 지연이 손해였으니 퇴출 즉시, 경계 신규진입 잡음만 진입 문턱으로 거른다.
##   arm V-1 (창 이질 앙상블): 36m 코호트 pool ∪ 60m 코호트 pool(R6 W60 궤적 재사용) → 합집합 위 EW composite(합의).
##       기전: R11 armV 한계=코호트 과-동질(3M-offset Spearman 0.92)이었으니 offset 아니라 관측창 이질화로 진짜 다양성.
##
## [판정] cap-w authoritative(nwt act_bm) + EW-uni 진단 병기 + HARD 3종 + 2017+ 분리 + paired NW-t vs base(문턱 2.0).
##   1차 IS-only 승자 = R12 자체 IS paired-t vs base 최대(R11 OOS 미입력). oos_retention = 최종 게이트 산출.
## [측정 규율] proxy 손계산 없음 — weighted_screen_bt(계약, build_benchmark_compare) 경유. base parity == R6 2.6124.
## [실행] 단일스레드 · arrow io_thread(2) · pin r6 vintage 대조 · governor 정지 · book 무변경.
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
logf <- file.path(".cache", sprintf("_ramp_r12_%s.txt", RUNTAG))
con <- file(logf,"w",encoding="UTF-8"); w<-function(...){ writeLines(paste0(...),con); flush(con) }; wf<-function(...){w(sprintf(...))}

## ── estimators (R6/R10/R11 자구동일) ──
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA_real_); mean(x)/sd(x)*sqrt(12) }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
oos3 <- function(act){ .splits<-c(0.55,0.65,0.75)
  r <- sapply(.splits, function(fr){ k<-floor(length(act)*fr)
    if(k<12||(length(act)-k)<6) return(NA_real_); .is<-srf(act[1:k]); .oo<-srf(act[(k+1):length(act)])
    if(!is.na(.is)&&.is>0) .oo/.is else NA_real_ }); median(r, na.rm=TRUE) }
post2017 <- as.Date("2017-01-01")

## ── 사전등록 config (hash 동결) ──
TOP_N <- 25L; COST_BPS <- 15; LIQ_MIN <- 2e8; W36 <- 36L; W60 <- 60L; K20 <- 20L
CAP <- 0.20; FLOOR_FRAC <- 0.25
CADENCE_ENTRY <- 6L; CADENCE_EXIT <- 3L      # F-1: 진입 반기 / 퇴출 분기
EXIT_RANK_BAR <- 30L                          # F-1: held 팩터 현 trailing-t rank > 30 이면 배출(풀 하위 기준)
B1_ENTER <- 20L; B1_EXIT <- 25L               # B-1: 진입 엄격 rank<=20 / 퇴출 즉시 rank>25
GATE_PT <- 2.95; PAIRED_MEANINGFUL <- 2.0
IS_FRAC <- 0.65                               # chain: IS-only 승자 지목용 (첫 65% 배포월)
N_TRIALS_R12 <- 3L                            # arm F-1, B-1, V-1 (2차 결합 없음)
N_TRIALS_LINEAGE <- 18L + N_TRIALS_R12        # P-pure 계보 chain 연속: R11까지 18 + R12 3 = 21 (chain — DSR 진단용)
R11_REF <- list(base_capwt=2.6124, armF_capwt=2.8520, armF_oos=0.1208, armV_capwt=2.8948, armV_oos=0.0868)
ARMS <- c("armF1_asym_exit","armB1_asym_band","armV1_hetero_window")
PREREG <- list(mode="RAMP", round="R12", fq="FQ-025",
  question="R11 next_probe 수렴점 '퇴출 빠르게·진입 엄격하게'를 세 비대칭/이질 construction 기전(팩터 퇴출 비대칭 / 종목 비대칭 밴드 / 창 이질 앙상블)으로 공략",
  base="Ppure_W36_K20 (종목 EW × 팩터 EW, R6 저장 2.6124 parity 앵커)",
  selection_type="chain",
  chain_discipline="arm 간 선택 IS-only(첫 65% 배포월 paired-t) · oos는 최종 게이트 산출로만 · 2차 결합 없음(1차만) · DSR 진단용(게이트 부적용)",
  oos_exposure_mgmt="R11 OOS(게이트 산출로 소비됨)는 arm 선택 입력으로 미사용 — 가설 동기로만. R12는 자체 사전등록 신규 측정(IS-only 승자는 R12 IS paired-t)",
  arms=list(
    armF1_asym_exit=list(mechanism="진입=반기(cadence6) full top-K20 / 퇴출=분기(cadence3) 즉시(held rank>30 또는 trailing-t<0 배출·빈슬롯 차순위 충원)",
      diag="armF 개선 원천이 '감쇠 팩터 조기 제거'라면 갱신 전체(armF full 재선별) 아니라 퇴출만 빨라도 충분·회전 비용 더 적다",
      adversarial="C① 차별성 = F-1 pool churn·TO·Jaccard vs armF cadence3 대조(퇴출 가속이 사실상 cadence3와 동일 효과인가)"),
    armB1_asym_band=list(mechanism="진입 엄격 rank<=20 만 신규진입 / 퇴출 즉시 rank>25 이탈 매도. 25종 미달 월 기존 보유 유지분 best-rank 충원(봉투<=25)",
      diag="armB 반증(퇴출 지연=손해) 방향 — 퇴출 즉시로 두고 경계 신규진입 잡음만 진입 문턱으로 거른다",
      adversarial="C② eff-N·HHI·n_hold — 엄격 진입이 유효 종목수 미달/집중을 만드는가"),
    armV1_hetero_window=list(mechanism="36m 코호트 pool ∪ 60m 코호트 pool(R6 W60 궤적 재사용) → 합집합 위 EW composite(합의)",
      diag="R11 armV 한계=코호트 과-동질(3M-offset Spearman 0.92) → offset 아니라 관측창 이질화(36m 감쇠민감+60m 안정)로 진짜 다양성",
      adversarial="C③ Jaccard·Spearman(36,60) vs R11 armV(0.671/0.923) — 이질 코호트의 실제 다양성")),
  no_2nd_combine="이번엔 1차만(결합은 R11서 IS-폐기 선례)",
  gate_hard=c(port_t_capwt=GATE_PT, oos_retention=0.7, calmar=0.64, dsr=0.5),
  primary_criterion="1차 승자 = R12 자체 IS paired NW-t(cap-w act_bm) vs base 최대(IS-only). 최종 판정 = full HARD 3종 + full paired vs base + oos_retention",
  kill_rule="전 arm full paired<2.0 AND HARD 3종 0/N AND oos_retention 0.7 미도달 → config-scoped negative(대칭→비대칭 config 집합 한정). '소진/dead-end' 어휘 금지 — next_probe >=2 도출 의무",
  honest_frame="본 라운드=비대칭/이질 construction 레버 검증. construction-invariant ~2.9 천장 진단 존재 → cap-tier×cap-w 벽은 못 풀 수 있음(정직 병기). return-derived substrate 재사용(신규 재료 아님)",
  is_frac=IS_FRAC, top_n=TOP_N, cost_bps_oneway=COST_BPS, liq_min=LIQ_MIN, cap=CAP, floor_frac=FLOOR_FRAC,
  cadence_entry=CADENCE_ENTRY, cadence_exit=CADENCE_EXIT, exit_rank_bar=EXIT_RANK_BAR, b1_enter=B1_ENTER, b1_exit=B1_EXIT,
  windows=c(W36,W60), n_trials_r12=N_TRIALS_R12, n_trials_lineage=N_TRIALS_LINEAGE, r11_ref=R11_REF,
  cost_model="delta-based |Δw|×15bps one-way (weighted_screen_bt 내장 — 밴드/선별 회전 자동 반영)",
  xmode_check="hypothesis_index: factor-momentum timing NULL(06-30) prior — F-1 퇴출가속이 armF cadence3(full 재선별)와 다른가 = churn/TO/Jaccard 적대검증. B-1/V-1은 R11 next_probe 직계(중복 아님, INV-7 재도전)",
  vintage_pin="r6_session_20260711 (sel_traj 36+60/pure_factor_scores/factor_group_scores/rawdata/panel; base parity Δ=0 확인)",
  as_of_date="2026-07-13", source_version="RAMP_R12_v1",
  security_id="Ticker (rawdata) -> factor_id z (pure_factor_scores.z=Z_Score_Aligned)")
CFG_HASH <- substr(digest::digest(PREREG, algo="sha256"), 1, 16)
PREREG$config_hash <- CFG_HASH
PREREG$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
jsonlite::write_json(PREREG, file.path(OUT, sprintf("r12_asym_prereg_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=6)
wf("=== RAMP R12: 비대칭·이질 construction chain (config_hash=%s) ===", CFG_HASH)
wf("arms: %s | selection_type=chain | IS_FRAC=%.2f | n_trials R12=%d lineage=%d",
   paste(ARMS,collapse=","), IS_FRAC, N_TRIALS_R12, N_TRIALS_LINEAGE)

## ── 데이터 (R6/R10/R11 동일 소스) ──
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

## ── 선별 궤적 (R6 캐시 = 36m base + 60m 이질창) ──
sel_traj <- readRDS(".cache/_ramp_r6_sel_20260711.rds")
base_anchors <- sel_traj[["36"]]$anchors                       # cadence 6 (base entry)
w60_anchors  <- sel_traj[["60"]]$anchors
wf("substrate: %d approved factors | %d sig months %s~%s | base(36,cadence6) anchors=%d | W60 anchors=%d",
   length(POOL_FACS), n_sig, as.character(sig_dates[1]), as.character(sig_dates[n_sig]), length(base_anchors), length(w60_anchors))

## ── 배포권 패널 Pmat 재구성 (F-1 재선별·trailing_t용 — R6 factor_deployzone_active 재사용) ──
PANEL <- as.data.table(read_parquet(file.path(OUT,"r6_factor_deployzone_active.parquet"))); PANEL[, signal_date := as.Date(signal_date)]
PANEL_FACS <- sort(unique(PANEL$factor_id))
Pw <- dcast(PANEL, signal_date ~ factor_id, value.var="active_bm"); setorder(Pw, signal_date)
panel_dates <- Pw$signal_date; n_pm <- length(panel_dates)
Pmat <- as.matrix(Pw[, ..PANEL_FACS]); rownames(Pmat) <- as.character(panel_dates)
stopifnot(all(panel_dates == sig_dates[1:n_pm]))
wf("[panel] Pmat %d months x %d factors (F-1 재선별 substrate)", n_pm, length(PANEL_FACS))

## trailing PORT_t 벡터 (R6/R11 trailing_portt 자구동일 — 각 factor NW-t lag3, W36 창)
trailing_portt_vec <- function(W, a_idx){
  lo <- a_idx - W; hi <- a_idx - 1L
  if(lo < 1L || hi > n_pm) return(NULL)
  sub <- Pmat[lo:hi, , drop=FALSE]
  apply(sub, 2, function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
    m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) })
}
## anchor 집합: 진입 반기(cohortEntry=base_anchors) + 퇴출 분기(anchors_exit) 모두 W36 trailing_t 필요
anchors_exit  <- seq(W36+1L, n_sig-1L, by=CADENCE_EXIT)     # 분기 퇴출 점검 (반기 진입 anchor 포함하는 superset)
cohortEntry   <- seq(W36+1L, n_sig-1L, by=CADENCE_ENTRY)    # = base R6 anchors (반기 진입)
armF_anchors  <- anchors_exit                              # R11 armF(cadence3 full 재선별) 대조군 재구성용
TT_ANCHORS <- sort(unique(c(anchors_exit, cohortEntry)))
## R11 이 anchor superset을 이미 캐시(_ramp_r11_tt) — anchors_exit ⊂ R11 TT_ANCHORS. 재사용 시도.
TT_CACHE_R11 <- file.path(".cache", sprintf("_ramp_r11_tt_%s.rds", RUNTAG))
TT_CACHE     <- file.path(".cache", sprintf("_ramp_r12_tt_%s.rds", RUNTAG))
if(file.exists(TT_CACHE) && !nzchar(Sys.getenv("RAMP_R12_FORCE_TT",""))){
  TT_ALL <- readRDS(TT_CACHE); wf("[cache] trailing_t 재사용(R12): %s (%d anchors)", TT_CACHE, length(TT_ALL))
} else if(file.exists(TT_CACHE_R11) && !nzchar(Sys.getenv("RAMP_R12_FORCE_TT",""))){
  TT_R11 <- readRDS(TT_CACHE_R11)
  need <- setdiff(as.character(TT_ANCHORS), names(TT_R11))
  if(length(need)==0){ TT_ALL <- TT_R11[as.character(TT_ANCHORS)]; wf("[cache] R11 trailing_t 재사용(anchor 완전포함): %d anchors", length(TT_ALL)) }
  else {
    wf("[compute] R11 캐시 부분포함 — 누락 %d anchor 보강 계산 ...", length(need))
    TT_ALL <- TT_R11
    for(a in as.integer(need)){ tv <- trailing_portt_vec(W36, a); if(!is.null(tv)) TT_ALL[[as.character(a)]] <- tv }
    TT_ALL <- TT_ALL[as.character(TT_ANCHORS)]
    saveRDS(TT_ALL, TT_CACHE)
  }
} else {
  wf("[compute] trailing_t %d anchors ...", length(TT_ANCHORS))
  t0 <- Sys.time(); TT_ALL <- list()
  for(a in TT_ANCHORS){ tv <- trailing_portt_vec(W36, a); if(!is.null(tv)) TT_ALL[[as.character(a)]] <- tv }
  saveRDS(TT_ALL, TT_CACHE)
  wf("[compute] trailing_t 완료 %.0fs (%d valid anchors)", as.numeric(Sys.time()-t0,units="secs"), length(TT_ALL))
}
ranked_from_tt <- function(tt){ tt<-tt[is.finite(tt)]; names(sort(tt, decreasing=TRUE)) }
topK_from_tt   <- function(tt, k=K20){ r<-ranked_from_tt(tt); if(length(r)<k) return(r); r[seq_len(k)] }

## ════════ F-1 비대칭 퇴출 pool 궤적(stateful) — 반기 full 진입 + 분기 즉시 퇴출 + 차순위 충원 ════════
build_pool_traj_F1 <- function(){
  held <- NULL; pool_by_anchor <- list()
  for(a in anchors_exit){
    tt <- TT_ALL[[as.character(a)]]
    if(is.null(tt)){ pool_by_anchor[[as.character(a)]] <- held; next }
    ranked <- ranked_from_tt(tt)
    is_entry <- a %in% cohortEntry
    if(is_entry || is.null(held)){
      held <- head(ranked, K20)                                  # 반기 full top-K20 진입(strict)
    } else {
      keep <- held[ vapply(held, function(f){                    # 즉시 퇴출: 현 rank>30(풀 하위) 또는 trailing-t<0
                    r <- match(f, ranked)                        # NA = finite ranking서 이탈(감쇠)
                    ttf <- if(f %in% names(tt)) tt[[f]] else NA_real_
                    (!is.na(r) && r <= EXIT_RANK_BAR) && (is.finite(ttf) && ttf >= 0) }, logical(1)) ]
      slots <- K20 - length(keep)
      if(slots > 0){ cand <- setdiff(ranked, keep); held <- c(keep, head(cand, slots)) } else held <- keep
    }
    pool_by_anchor[[as.character(a)]] <- held
  }
  pool_by_anchor
}
POOL_F1 <- build_pool_traj_F1()

## ── pool getters (arm별) ──
getter_base <- function(i){ ga <- max(base_anchors[base_anchors<=i]); sel_traj[["36"]]$traj[[as.character(ga)]]$pool[["K20"]] }
getter_F1   <- function(i){ ga <- max(anchors_exit[anchors_exit<=i]); p <- POOL_F1[[as.character(ga)]]; if(is.null(p)) getter_base(i) else p }
getter_V1   <- function(i){                                        # 36m ∪ 60m pool union (창 이질)
  ga36 <- max(base_anchors[base_anchors<=i]); p36 <- sel_traj[["36"]]$traj[[as.character(ga36)]]$pool[["K20"]]
  a60 <- w60_anchors[w60_anchors<=i]
  if(!length(a60)) return(p36)
  ga60 <- max(a60); p60 <- sel_traj[["60"]]$traj[[as.character(ga60)]]$pool[["K20"]]
  unique(c(p36, p60))
}
## armF (R11 cadence3 full 재선별) — C① 대조군 getter
getter_armF <- function(i){ ga <- max(armF_anchors[armF_anchors<=i]); tt <- TT_ALL[[as.character(ga)]]; if(is.null(tt)) getter_base(i) else topK_from_tt(tt) }

## ── 공용: positive-shift 틸트 + cap water-fill (R10/R11 자구동일) ──
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
stock_weights <- function(scores, mode){   # mode: ew | linear | sqrt
  n <- length(scores); if(mode=="ew") return(rep(1/n, n))
  p <- tilt_shift(scores); raw <- if(mode=="sqrt") sqrt(p) else p; cap_normalize(raw) }

## ── composite 재구성 (R10/R11 build_composite EW 경로 자구동일 — pool getter만 파라미터화) ──
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

## ── weights_dt 빌더: composite -> top-25 -> 종목 EW (R10/R11 build_weights 자구동일) ──
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

## ── B-1 비대칭 밴드 빌더: 진입 rank<=ENTER / 퇴출 즉시 rank>EXIT, 25종 미달 시 기존 보유 유지분 충원 ──
build_weights_asymband <- function(comp, enter=B1_ENTER, exit=B1_EXIT, weight_mode="ew"){
  S <- comp[!is.na(score), .(Date=as.Date(signal_date), Ticker=security_id, score)]
  S <- merge(S, LIQ_DT[, .(Date, Ticker, adv)], by=c("Date","Ticker"), all.x=TRUE)
  S <- S[is.na(adv) | adv >= LIQ_MIN]; S[, adv := NULL]
  dts <- sort(unique(S$Date)); held <- character(0); rows <- vector("list", length(dts))
  churn_ct <- 0L; n_reb <- 0L; short_ct <- 0L
  for(ix in seq_along(dts)){
    d <- dts[ix]; cur <- S[Date==d][order(-score)]
    if(nrow(cur) < TOP_N){ next }
    cur[, rk := seq_len(.N)]                                   # 1 = best
    top_enter <- cur[rk <= enter, Ticker]                     # 신규진입 자격(엄격)
    keep_pool <- cur[rk <= exit, Ticker]                      # 잔류 자격(즉시퇴출: rank>exit 매도)
    retain <- intersect(held, keep_pool)
    if(length(retain) > TOP_N) retain <- cur[Ticker %in% retain][order(-score)][seq_len(TOP_N), Ticker]
    slots <- TOP_N - length(retain); fill <- character(0)
    if(slots > 0){ cand <- setdiff(top_enter, retain)
      if(length(cand) > 0) fill <- cur[Ticker %in% cand][order(-score)][seq_len(min(slots, length(cand))), Ticker] }
    newsel <- unique(c(retain, fill))
    if(length(newsel) < TOP_N && length(held) > 0){            # 25종 미달 → 기존 보유 유지분(직전 held) best-rank 충원
      extra_cand <- setdiff(held, newsel)
      extra_rk <- cur[Ticker %in% extra_cand][order(-score)]$Ticker  # 유동성 통과분만 (cur 내)
      if(length(extra_rk) > 0){ need <- TOP_N - length(newsel); newsel <- c(newsel, head(extra_rk, need)) }
    }
    if(length(newsel) < TOP_N) short_ct <- short_ct + 1L
    if(ix > 1){ churn_ct <- churn_ct + length(setdiff(newsel, held)); n_reb <- n_reb + 1L }
    held <- newsel
    scv <- cur[Ticker %in% held][match(held, Ticker), score]
    ww <- if(weight_mode=="sqrt") stock_weights(scv, "sqrt") else rep(1/length(held), length(held))
    rows[[ix]] <- data.table(Date=d, Ticker=held, w=ww)
  }
  wdt <- rbindlist(rows)
  attr(wdt, "name_churn_per_reb") <- if(n_reb>0) churn_ct/n_reb else NA_real_
  attr(wdt, "short_months") <- short_ct
  wdt
}

## ── gate: weighted_screen_bt -> period_returns -> R6 estimator (R10/R11 gate_one 자구동일) ──
gate_one <- function(Wdt, lab){
  r <- tryCatch(weighted_screen_bt(Wdt, RET_DT, BENCH_DT, cost_bps_oneway=COST_BPS,
        run_id=paste0("r12_",lab), strategy_id=lab), error=function(e){ w("  [gate ERR ",lab,"] ",conditionMessage(e)); NULL })
  if(is.null(r) || is.null(r$period_returns)) return(NULL)
  pr <- as.data.table(r$period_returns); pr[, date:=as.Date(date)]
  pr <- merge(pr, ewb, by="date", all.x=TRUE)
  pr[, act := ret_net - ew]; pr[, act_bm := ret_net - benchmark_ret]
  pt_ew <- nwt(pr$act); pt_bm <- nwt(pr$act_bm)
  nav <- cumprod(1+pr$ret_net); dd <- min(nav/cummax(nav)-1); ann <- prod(1+pr$ret_net)^(12/nrow(pr))-1
  cal <- if(dd<0) ann/abs(dd) else NA_real_
  retn <- oos3(pr$act_bm)
  sr_m <- mean(pr$act_bm)/sd(pr$act_bm); nn <- nrow(pr)
  sk <- tryCatch(e1071::skewness(pr$act_bm),error=function(e)0); ku <- tryCatch(e1071::kurtosis(pr$act_bm)+3,error=function(e)3)
  den <- sqrt((1-sk*sr_m+(ku-1)/4*sr_m^2)/(nn-1)); dsr_raw <- if(den>1e-10) sr_m/den else NA_real_
  dsr <- if(!is.na(dsr_raw)) dsr_raw - N_TRIALS_LINEAGE*0.05 else NA_real_
  post_sr <- srf(pr[date>=post2017, act_bm]); full_sr <- srf(pr$act_bm)
  list(dt=data.table(model=lab, port_t_capwt=pt_bm, port_t_EWuni=pt_ew, oos_retention=retn, calmar=cal,
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

## ════════════ 1차 측정 (base + 3 arm + armF 대조군) ════════════
wf("\n=== 1차 측정 (cap-w authoritative, weighted_screen_bt 계약경로) ===")
RES <- list(); PR <- list(); WMAP <- list(); CONC <- list(); META <- list(); COMPS <- list()

comp_base <- build_composite_g(getter_base); COMPS[["base"]] <- comp_base
W_base <- build_weights(comp_base, "ew")
gb <- gate_one(W_base, "base"); RES[["base"]]<-gb$dt; PR[["base"]]<-gb$pr; WMAP[["base"]]<-W_base; CONC[["base"]]<-conc_diag(W_base,"base")
wf("  [base           ] pt_capwt=%+.3f pt_EWuni=%+.3f oos=%+.3f calmar=%+.3f DSR=%+.3f post17SR=%+.3f TO=%.2f",
   gb$dt$port_t_capwt, gb$dt$port_t_EWuni, gb$dt$oos_retention, gb$dt$calmar, gb$dt$dsr, gb$dt$post2017_bm_sr, gb$dt$turnover)

comp_F1 <- build_composite_g(getter_F1); COMPS[["armF1_asym_exit"]] <- comp_F1
W_F1 <- build_weights(comp_F1, "ew")
gF1 <- gate_one(W_F1, "armF1_asym_exit"); RES[["armF1_asym_exit"]]<-gF1$dt; PR[["armF1_asym_exit"]]<-gF1$pr; WMAP[["armF1_asym_exit"]]<-W_F1; CONC[["armF1_asym_exit"]]<-conc_diag(W_F1,"armF1_asym_exit")
wf("  [armF1_asym_exit] pt_capwt=%+.3f pt_EWuni=%+.3f oos=%+.3f calmar=%+.3f DSR=%+.3f post17SR=%+.3f TO=%.2f",
   gF1$dt$port_t_capwt, gF1$dt$port_t_EWuni, gF1$dt$oos_retention, gF1$dt$calmar, gF1$dt$dsr, gF1$dt$post2017_bm_sr, gF1$dt$turnover)

W_B1 <- build_weights_asymband(comp_base, B1_ENTER, B1_EXIT, "ew")
gB1 <- gate_one(W_B1, "armB1_asym_band"); RES[["armB1_asym_band"]]<-gB1$dt; PR[["armB1_asym_band"]]<-gB1$pr; WMAP[["armB1_asym_band"]]<-W_B1; CONC[["armB1_asym_band"]]<-conc_diag(W_B1,"armB1_asym_band")
META[["armB1_name_churn_per_reb"]] <- attr(W_B1, "name_churn_per_reb"); META[["armB1_short_months"]] <- attr(W_B1, "short_months")
wf("  [armB1_asym_band] pt_capwt=%+.3f pt_EWuni=%+.3f oos=%+.3f calmar=%+.3f DSR=%+.3f post17SR=%+.3f TO=%.2f (name_churn/reb=%.2f short_months=%d)",
   gB1$dt$port_t_capwt, gB1$dt$port_t_EWuni, gB1$dt$oos_retention, gB1$dt$calmar, gB1$dt$dsr, gB1$dt$post2017_bm_sr, gB1$dt$turnover, META[["armB1_name_churn_per_reb"]], META[["armB1_short_months"]])

comp_V1 <- build_composite_g(getter_V1); COMPS[["armV1_hetero_window"]] <- comp_V1
W_V1 <- build_weights(comp_V1, "ew")
gV1 <- gate_one(W_V1, "armV1_hetero_window"); RES[["armV1_hetero_window"]]<-gV1$dt; PR[["armV1_hetero_window"]]<-gV1$pr; WMAP[["armV1_hetero_window"]]<-W_V1; CONC[["armV1_hetero_window"]]<-conc_diag(W_V1,"armV1_hetero_window")
wf("  [armV1_hetero_w ] pt_capwt=%+.3f pt_EWuni=%+.3f oos=%+.3f calmar=%+.3f DSR=%+.3f post17SR=%+.3f TO=%.2f",
   gV1$dt$port_t_capwt, gV1$dt$port_t_EWuni, gV1$dt$oos_retention, gV1$dt$calmar, gV1$dt$dsr, gV1$dt$post2017_bm_sr, gV1$dt$turnover)

## armF 대조군(R11 cadence3 full 재선별) — C① 차별성 대조 (판정 arm 아님, 진단용)
comp_armF <- build_composite_g(getter_armF); COMPS[["ctrl_armF_cad3"]] <- comp_armF
W_armF <- build_weights(comp_armF, "ew")
gAF <- gate_one(W_armF, "ctrl_armF_cad3"); RES[["ctrl_armF_cad3"]]<-gAF$dt; PR[["ctrl_armF_cad3"]]<-gAF$pr; WMAP[["ctrl_armF_cad3"]]<-W_armF
wf("  [ctrl_armF_cad3 ] pt_capwt=%+.3f oos=%+.3f TO=%.2f (R11 armF 대조: 저장 2.852/oos+0.121)",
   gAF$dt$port_t_capwt, gAF$dt$oos_retention, gAF$dt$turnover)

## ── base parity: cap-w == R6 저장 2.6124 ──
base_pt <- RES[["base"]]$port_t_capwt; R6_BASE <- 2.6124
parity_delta <- abs(base_pt - R6_BASE); parity_ok <- is.finite(parity_delta) && parity_delta < 5e-3
wf("\n[base parity] R12 base cap-w PORT_t=%.4f vs R6 저장 %.4f -> |Δ|=%.2e ok=%s", base_pt, R6_BASE, parity_delta, parity_ok)
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
for(i in seq_len(nrow(PAIRED))) wf("  [%-18s] Δ(ann)=%+.4f | paired_t: full=%+.3f IS=%+.3f OOS=%+.3f (n=%d)",
  PAIRED$model[i], PAIRED$mean_diff_ann[i], PAIRED$paired_t_full[i], PAIRED$paired_t_IS[i], PAIRED$paired_t_OOS[i], PAIRED$n[i])

## ── 1차 IS-only 승자 지목 (chain 규율, R11 OOS 미입력) ──
winner <- PAIRED[which.max(paired_t_IS), model]
winner_is_t <- PAIRED[model==winner, paired_t_IS]
wf("\n=== 1차 IS-only 승자 (chain: OOS 미조회, R11 OOS 미입력) ===")
wf("  winner = %s (IS paired_t=%+.3f) | 서열(IS): %s", winner, winner_is_t,
   paste(sprintf("%s=%.2f", PAIRED$model, PAIRED$paired_t_IS), collapse=" > "))

TAB <- rbindlist(lapply(RES, function(x) x), fill=TRUE)
CONCT <- rbindlist(CONC, fill=TRUE)

## ── HARD 게이트표 ──
wf("\n=== HARD 게이트 (capwt %.2f / oos 0.7 / calmar 0.64 / DSR 0.5[chain 진단], n_trials lineage=%d) ===", GATE_PT, N_TRIALS_LINEAGE)
for(i in seq_len(nrow(TAB))){ r<-TAB[i]
  p<-c(port_t=isTRUE(r$port_t_capwt>=GATE_PT), oos=isTRUE(r$oos_retention>=0.7), cal=isTRUE(r$calmar>=0.64))
  wf("  [%-18s] pt=%+.3f %s oos=%+.3f %s cal=%+.3f %s -> %s", r$model, r$port_t_capwt, ifelse(p["port_t"],"✓","✗"),
     r$oos_retention, ifelse(p["oos"],"✓","✗"), r$calmar, ifelse(p["cal"],"✓","✗"), ifelse(all(p),"★GRADUATION","미달")) }

## ── concentration ──
wf("\n=== concentration (소형농축·유효종목수·HHI) ===")
wf("  %-18s %6s %6s %6s %6s %6s | %6s %6s %6s", "model","HHI","effN","maxw","nHold","minNH","MEGA","MID","OTHER")
for(i in seq_len(nrow(CONCT))){ r<-CONCT[i]
  wf("  %-18s %6.4f %6.2f %6.3f %6.1f %6.0f | %6.3f %6.3f %6.3f", r$model, r$hhi, r$n_eff, r$maxw, r$n_hold, r$min_nhold, r$w_MEGA, r$w_MID, r$w_OTHER) }

## ════════════ 챌린지 진단 3종 ════════════
wf("\n=== 챌린지 진단 (self-adversarial 재료) ===")
## ① arm F-1: 퇴출 가속이 armF cadence3(full 재선별)과 다른가 — pool churn + TO + Jaccard 대조
pool_churn_traj <- function(getf){                          # 연속 배포월 pool 간 churn/K20
  idx <- (W36+1L):(n_sig-1L); ch <- c(); prev <- NULL
  for(i in idx){ p <- getf(i); if(!is.null(prev)) ch <- c(ch, length(setdiff(p, prev))/K20); prev <- p }
  mean(ch, na.rm=TRUE) }
pool_jac_F1_vs_armF <- function(){                          # 월별 F-1 pool vs armF pool Jaccard
  idx <- (W36+1L):(n_sig-1L); jc <- c()
  for(i in idx){ a<-getter_F1(i); b<-getter_armF(i); if(length(a)&&length(b)) jc<-c(jc, length(intersect(a,b))/length(union(a,b))) }
  mean(jc, na.rm=TRUE) }
churn_base <- pool_churn_traj(getter_base); churn_F1 <- pool_churn_traj(getter_F1); churn_armF <- pool_churn_traj(getter_armF)
jac_F1_armF <- pool_jac_F1_vs_armF()
to_base <- TAB[model=="base", turnover]; to_F1 <- TAB[model=="armF1_asym_exit", turnover]; to_armF <- TAB[model=="ctrl_armF_cad3", turnover]
oos_F1 <- TAB[model=="armF1_asym_exit", oos_retention]; oos_armF <- TAB[model=="ctrl_armF_cad3", oos_retention]
capwt_F1 <- TAB[model=="armF1_asym_exit", port_t_capwt]; capwt_armF <- TAB[model=="ctrl_armF_cad3", port_t_capwt]
wf("  ① F-1 vs armF(cadence3) 차별성: pool churn base=%.3f F1=%.3f armF=%.3f | F1↔armF pool Jaccard=%.3f | TO base=%.2f F1=%.2f armF=%.2f | oos F1=%+.3f armF=%+.3f | cap-w F1=%+.3f armF=%+.3f",
   churn_base, churn_F1, churn_armF, jac_F1_armF, to_base, to_F1, to_armF, oos_F1, oos_armF, capwt_F1, capwt_armF)
## ② arm B-1: 엄격 진입이 유효 종목수 미달/집중 만드는가 — eff-N·HHI·n_hold·short_months
cB <- CONCT[model=="armB1_asym_band"]; bB <- PAIRED[model=="armB1_asym_band"]
wf("  ② B-1 유효종목수·집중: n_hold(mean)=%.1f min=%.0f short_months=%d | eff-N=%.2f HHI=%.4f maxw=%.3f | vs base eff-N=%.2f | paired IS=%+.3f OOS=%+.3f TO=%.2f→%.2f",
   cB$n_hold, cB$min_nhold, META[["armB1_short_months"]], cB$n_eff, cB$hhi, cB$maxw, CONCT[model=="base",n_eff],
   bB$paired_t_IS, bB$paired_t_OOS, to_base, TAB[model=="armB1_asym_band",turnover])
## ③ arm V-1: 창 이질 코호트의 실제 다양성 — Jaccard·Spearman(36,60) vs R11 armV(0.671/0.923)
coh_jac <- c(); coh_spr <- c(); union_sz <- c()
for(i in (W36+1L):(n_sig-1L)){
  ga36 <- max(base_anchors[base_anchors<=i]); p36 <- sel_traj[["36"]]$traj[[as.character(ga36)]]$pool[["K20"]]
  a60 <- w60_anchors[w60_anchors<=i]; if(!length(a60)) next
  ga60 <- max(a60); p60 <- sel_traj[["60"]]$traj[[as.character(ga60)]]$pool[["K20"]]
  coh_jac <- c(coh_jac, length(intersect(p36,p60))/length(union(p36,p60)))
  union_sz <- c(union_sz, length(union(p36,p60)))
  tt36 <- sel_traj[["36"]]$traj[[as.character(ga36)]]$trailing_t; tt60 <- sel_traj[["60"]]$traj[[as.character(ga60)]]$trailing_t
  if(!is.null(tt36) && !is.null(tt60)){ cf <- intersect(names(tt36[is.finite(tt36)]), names(tt60[is.finite(tt60)]))
    if(length(cf)>=10) coh_spr <- c(coh_spr, cor(tt36[cf], tt60[cf], method="spearman")) }
}
wf("  ③ V-1 창 이질 다양성: 36∪60 Jaccard mean=%.3f (R11 armV 3M-offset 0.671) | trailing_t Spearman mean=%.3f (R11 0.923) | union size mean=%.1f (더 낮을수록/클수록 진짜 다양성)",
   mean(coh_jac,na.rm=TRUE), mean(coh_spr,na.rm=TRUE), mean(union_sz,na.rm=TRUE))

## ── KILL/verdict 판정 (사전등록 — config-scoped negative 어휘) ──
maxp_full <- suppressWarnings(max(PAIRED[model %in% ARMS, paired_t_full], na.rm=TRUE))
any_grad <- any(is.finite(TAB$port_t_capwt) & TAB$port_t_capwt>=GATE_PT &
                is.finite(TAB$oos_retention) & TAB$oos_retention>=0.7 &
                is.finite(TAB$calmar) & TAB$calmar>=0.64 & TAB$model %in% ARMS)
best_oos <- suppressWarnings(max(TAB[model %in% ARMS, oos_retention], na.rm=TRUE))
best_capwt_arm <- TAB[model %in% ARMS][which.max(port_t_capwt)]
KILL <- !(is.finite(maxp_full) && maxp_full >= PAIRED_MEANINGFUL) && !any_grad && !(is.finite(best_oos) && best_oos>=0.7)
wf("\n=== 판정 gate (사전등록) ===")
wf("  max full paired (arm vs base) = %+.3f (문턱 %.1f)", maxp_full, PAIRED_MEANINGFUL)
wf("  any arm GRADUATION(HARD 3종) = %s | best oos_retention(arm) = %+.3f (target 0.7) | best cap-w arm = %s %.3f",
   any_grad, best_oos, best_capwt_arm$model, best_capwt_arm$port_t_capwt)
wf("  => config_scoped_negative(비대칭/이질 config 한정) = %s [종결 아님·next_probe 도출 의무]", KILL)

## ── 저장 ──
res <- list(prereg=PREREG, config_hash=CFG_HASH,
  meta=list(as_of_date="2026-07-13", generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
    source_version="RAMP_R12_v1", security_id="Ticker->factor_id z (pure_factor_scores.z=Z_Score_Aligned)"),
  results=TAB, paired=PAIRED, concentration=CONCT,
  base_parity=list(r12_base_pt=base_pt, r6_stored=R6_BASE, delta=parity_delta, ok=parity_ok),
  winner_1st=winner, winner_is_t=winner_is_t,
  challenge=list(
    armF1=list(pool_churn_base=churn_base, pool_churn_F1=churn_F1, pool_churn_armF=churn_armF,
               jaccard_F1_armF=jac_F1_armF, to_base=to_base, to_F1=to_F1, to_armF=to_armF,
               oos_F1=oos_F1, oos_armF=oos_armF, capwt_F1=capwt_F1, capwt_armF=capwt_armF),
    armB1=list(n_hold_mean=cB$n_hold, n_hold_min=cB$min_nhold, short_months=META[["armB1_short_months"]],
               n_eff=cB$n_eff, hhi=cB$hhi, maxw=cB$maxw, n_eff_base=CONCT[model=="base",n_eff],
               paired_is=bB$paired_t_IS, paired_oos=bB$paired_t_OOS, name_churn_per_reb=META[["armB1_name_churn_per_reb"]],
               to_base=to_base, to_B1=TAB[model=="armB1_asym_band",turnover]),
    armV1=list(cohort_jaccard_mean=mean(coh_jac,na.rm=TRUE), cohort_spearman_mean=mean(coh_spr,na.rm=TRUE),
               union_size_mean=mean(union_sz,na.rm=TRUE), r11_armV_jaccard=0.6706, r11_armV_spearman=0.9226)),
  kill=KILL, max_paired_full=maxp_full, any_graduation=any_grad, best_oos_arm=best_oos,
  n_trials_r12=N_TRIALS_R12, n_trials_lineage=N_TRIALS_LINEAGE, selection_type="chain", n_sig=n_sig,
  date_range=as.character(range(sig_dates)), r11_ref=R11_REF)
saveRDS(list(res=res, PR=PR, TAB=TAB, PAIRED=PAIRED, WMAP=WMAP, CONC=CONCT, COMPS=COMPS), file.path(".cache", sprintf("_ramp_r12_%s.rds", RUNTAG)))
write_parquet(TAB, file.path(OUT, sprintf("r12_asym_gates_%s.parquet", RUNTAG)))
if(nrow(PAIRED)) write_parquet(PAIRED, file.path(OUT, sprintf("r12_asym_paired_%s.parquet", RUNTAG)))
write_parquet(CONCT, file.path(OUT, sprintf("r12_asym_conc_%s.parquet", RUNTAG)))
jsonlite::write_json(res, file.path(OUT, sprintf("r12_asym_summary_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=4)

## ── best variant period_returns (텔레그램 차트용) ──
best_lab <- TAB[model %in% ARMS][which.max(port_t_capwt), model]
if(!is.null(PR[[best_lab]])){
  bpr <- merge(PR[[best_lab]][,.(date, ret_net)], BENCH_DT[,.(date=Date, BM_Ret)], by="date")
  saveRDS(list(best_lab=best_lab,
               period_returns=data.table(date=bpr$date, ret_net=bpr$ret_net, benchmark_ret=bpr$BM_Ret),
               base_pr=merge(PR[["base"]][,.(date,ret_net)], BENCH_DT[,.(date=Date,BM_Ret)], by="date")),
          file.path(".cache", sprintf("_ramp_r12_bestpr_%s.rds", RUNTAG)))
}

wf("\n=== VERDICT ===")
bv <- TAB[model %in% ARMS][which.max(port_t_capwt)]
wf("  best cap-w arm: %s pt_capwt=%+.3f oos=%+.3f calmar=%+.3f | base=%.4f", bv$model, bv$port_t_capwt, bv$oos_retention, bv$calmar, base_pt)
wf("  1차 IS 승자=%s | max full paired=%+.3f | config_scoped_negative=%s | base_parity=%s",
   winner, maxp_full, KILL, parity_ok)
close(con)
cat(sprintf("R12_DONE. winner=%s neg=%s any_grad=%s max_paired_full=%.3f best_oos=%.3f base_parity=%s(Δ%.2e) log=%s\n",
   winner, KILL, any_grad, maxp_full, best_oos, parity_ok, parity_delta, logf))
cat(readLines(logf, encoding="UTF-8"), sep="\n")
