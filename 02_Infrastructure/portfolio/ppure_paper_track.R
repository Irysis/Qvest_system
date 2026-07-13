## ppure_paper_track.R — D3 페이퍼 트래킹 병행안 월간 러너 (배선 태스크 #62, 도훈 승인 2026-07-13)
## ─────────────────────────────────────────────────────────────────────────────
## 목적: dossier §7 병행안 — base P-pure(W36_K20)와 D-2 변형(감쇠-트리거 퇴출, R13 armD2)
##       둘 다 페이퍼 트래킹. 사전등록 예측구간 봉인(1회, holdout_falsification.R 재사용) +
##       월간 frozen 선별 규칙으로 보유 산출 + 페이퍼 net 수익 적립.
##
## 트랙: 06_Registry/live_track/PPURE_BASE_W36K20  (base — 병행안의 사전지정 대조군)
##       06_Registry/live_track/PPURE_D2_DECAYEXIT (D-2 — ★선택편향 라벨: R13 게이트 산출 사후 지목 2026-07-13)
##
## 성격 (Level 0 명시):
##   - **페이퍼 전용** — book_state 쓰기 금지·자본 게이트(HARD 3종/ΔIR) 무관·실주문 없음·05_Production 무접촉.
##     cap-w 자본 게이트는 양 후보 모두 FAIL 불변(R8) — 본 트랙은 벤치-상대(EW-uni) 신호 지속성의 무비용 실측 장치.
##   - 텔레그램 발송 없음 (수치는 monitoring 월간 보고로).
##
## 규율:
##   - 선별 규칙 = frozen (R6 run_ramp_r6_portt_boruta.R + R13 run_ramp_r13_decay.R 코드경로 verbatim 재사용
##     — 신규 설계 없음. base: W36 trailing PORT_t top-K20 · cadence6 / D-2: 진입 cadence6 · 퇴출 cadence3,
##     recent18_t<0 OR (recent18_t−older18_t)<−1.0 배출·비-감쇠 차순위 충원). R13 prereg config_hash=d997ab856f3c4884.
##   - 수익 구성 = weighted_screen_bt (계약, build_benchmark_compare 경유) — 자체합성 금지 준수.
##     비용 = 15bps one-way delta-based Σ|Δw| (canonical_screen_bt 컨벤션 동일). 첫 페이퍼월 traded는
##     봉인 마지막월(2026-04 signal) 보유 대비 Δ — 연속 운용 가정(전량 신규구축 비용 아님, 라벨).
##   - parity guard fail-closed: 재구성 보유·수익이 봉인 참조(sealed_holdings_ref/sealed_source_series)와
##     불일치하면 append 중단 (업스트림 데이터 변형 경보 — [[project-cache-vintage-pinning]] 재발 방어).
##   - 쓰기 = temp+rename (OneDrive). 단일스레드 + arrow io(2). 한글경로 없음.
##
## 실행: cd C:/Users/99922/OneDrive/Quant_Module_Moltbot && Rscript -e 'source("02_Infrastructure/portfolio/ppure_paper_track.R")'
## 배선: 02_Infrastructure/prompts/monitoring_init.md 월간 항목 (task #62)
## ─────────────────────────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest); library(jsonlite)
})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")           # build_monthly_forward_returns (frozen 규약)
source("02_Infrastructure/contracts/weighted_screen_bt.R")     # 계약 수익 구성 (build_benchmark_compare)
source("02_Infrastructure/contracts/holdout_falsification.R")  # C3 build/save/judge (재사용 — 자체 구현 금지)

RUNSTAMP <- format(Sys.time(), "%Y%m%d_%H%M%S")
logf <- file.path(".cache", sprintf("_ppure_paper_track_%s.txt", format(Sys.Date(), "%Y%m%d")))
con <- file(logf, "w", encoding = "UTF-8")
w  <- function(...){ msg <- paste0(...); writeLines(msg, con); flush(con) }
wf <- function(...){ w(sprintf(...)) }

## ── frozen 상수 (R13 prereg 동결값 — 변경 금지) ──────────────────────────────
TOP_N <- 25L; COST_BPS <- 15; LIQ_MIN <- 2e8; W36 <- 36L; K20 <- 20L
CADENCE_ENTRY <- 6L; CADENCE_EXIT <- 3L; DECAY_DROP_BAR <- -1.0
R13_CFG_HASH <- "d997ab856f3c4884"
SEAL_END <- as.Date("2026-04-30")        # 봉인 IS+OOS 계열 마지막 signal month (220m, 2008-01-31~)
CAND_SELECTED_AT <- "2026-07-13"         # 후보 선택 시점 (D-2 선택편향 라벨 필수 기록)
HOLDOUT_M <- 21L; BLOCK <- 12L; BBOOT <- 4000L; SEED <- 7L   # STR_1715 c3 컨벤션 준수
R13_CACHE <- ".cache/_ramp_r13_20260713.rds"                 # 등록 1회에만 필요 (봉인 원천)
R13_SUMMARY <- "outputs/ramp/r13_decay_summary_20260713.json"
SEL_FROZEN <- ".cache/_ramp_r6_sel_20260711.rds"             # base 선별 궤적 (frozen)
SUB_FROZEN <- ".cache/_ramp_r13_sub_20260713.rds"            # 부분창 NW-t (frozen, anchors 37..256)
SUB_EXT    <- ".cache/_ppure_track_sub_ext.rds"              # 러너 소유 확장 (신규 anchor)
PANEL_STORED <- "outputs/ramp/r6_factor_deployzone_active.parquet"  # read-only (R6 산출물 — 러너가 덮어쓰지 않음)
PANEL_EXT    <- ".cache/_ppure_track_panel_ext.parquet"      # 러너 소유 패널 확장

TRACKS <- list(
  list(id = "PPURE_BASE_W36K20", model = "base",
       dir = "06_Registry/live_track/PPURE_BASE_W36K20",
       desc = "R6 P-pure Ppure_W36_K20 (base) — D3 벤치-상대 페이퍼 트래킹 (dossier §7 병행안 대조군)",
       selection_bias = paste0(
         "base = R6(2026-07-11) 원 산출·R8 band escalation 2/3로 D3 자격 회복(FQ-016) — 병행안의 사전지정 대조군. ",
         "D-2 대비 선택편향 낮음(단 R8 escalation 자체가 측정 후 자격 부여임을 정직 병기).")),
  list(id = "PPURE_D2_DECAYEXIT", model = "armD2_decay_exit",
       dir = "06_Registry/live_track/PPURE_D2_DECAYEXIT",
       desc = "R13 armD2_decay_exit — P-pure 감쇠-트리거 퇴출 변형 (진입 cadence6·퇴출 cadence3, recent18_t<0 OR decay<-1.0 배출)",
       selection_bias = paste0(
         "★선택편향 있음: 이 변형은 R13 게이트 산출(측정된 과거 — EW-oos 0.745)을 보고 ", CAND_SELECTED_AT,
         "에 사후 지목. 페이퍼 트래킹(미접촉 미래 실측)이 편향을 심판(dossier §7 정직 라벨)."))
)

## ── 공용 유틸 ────────────────────────────────────────────────────────────────
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA_real_); mean(x)/sd(x)*sqrt(12) }
hym <- function(d){ m <- as.integer(format(d,"%m")); y <- as.integer(format(d,"%Y"))   # 홀딩월 = signal월 + 1
  sprintf("%04d-%02d", y + (m %/% 12L), (m %% 12L) + 1L) }
fwrite_atomic <- function(dt, path){                       # OneDrive temp+rename 패턴
  tmp <- paste0(path, ".tmp_", Sys.getpid())
  fwrite(dt, tmp)
  if (file.exists(path)) unlink(path)
  if (!file.rename(tmp, path)) { file.copy(tmp, path, overwrite = TRUE); unlink(tmp) }
  invisible(path)
}
saveRDS_atomic <- function(obj, path){
  tmp <- paste0(path, ".tmp_", Sys.getpid()); saveRDS(obj, tmp)
  if (file.exists(path)) unlink(path)
  if (!file.rename(tmp, path)) { file.copy(tmp, path, overwrite = TRUE); unlink(tmp) }
  invisible(path)
}

wf("=== ppure_paper_track %s (task #62) — 페이퍼 전용·book_state 무관·자본 게이트 무관 ===", RUNSTAMP)

## ═══════════ 1. 데이터 (fresh — 페이퍼 트래킹 = monitoring 표면, lockbox 비적용) ═══════════
af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
APPROVED <- af[status == "approved", factor_id]
g <- as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet", col_select = "signal_date"))
sig_dates <- sort(unique(as.Date(g$signal_date))); n_sig <- length(sig_dates); rm(g)
n_dep <- n_sig   # 배포 상한 = 최신 score월 포함 (R13은 n_sig-1 — 당시 최신월 forward 미실현이었기 때문. 규칙 동일)

.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select = all_of(.need)))
rawdata[, Date := as.Date(Date)]
raw_max <- max(rawdata$Date)

## score 이후 완결 월말 추가 (최신 signal월 forward 실현용): 월말 m 완결 iff raw_max >= m - 4일
firsts <- seq(as.Date(format(max(sig_dates), "%Y-%m-01")), by = "month", length.out = 37)
mes <- firsts[-1] - 1L
mes_extra <- mes[mes > max(sig_dates) & (raw_max >= mes - 4L)]
calc_dates <- sort(unique(c(sig_dates, mes_extra)))
wf("[data] score 월 %d (%s~%s) | rawdata max=%s | 완결 추가 월말: %s",
   n_sig, as.character(sig_dates[1]), as.character(sig_dates[n_sig]), as.character(raw_max),
   if (length(mes_extra)) paste(as.character(mes_extra), collapse = ",") else "(없음)")
if (length(mes_extra) > 0)
  wf("[WARN] scores stale — 최신 score=%s < 최신 완결월=%s. RAMP score refresh 전까지 다음 홀딩월 보유 산출 불가.",
     as.character(max(sig_dates)), as.character(max(mes_extra)))

.udates <- sort(unique(rawdata$Date))
.me <- as.Date(vapply(calc_dates, function(d){ v <- .udates[.udates <= d]
  if (length(v)) as.character(max(v)) else NA_character_ }, character(1)))
rawme_f <- rawdata[Date %in% .me[!is.na(.me)]]
rm(rawdata); invisible(gc())
fwd <- build_monthly_forward_returns(rawme_f, calc_dates)
RET_DT   <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
BENCH_DT <- fwd$bench_dt[, .(Date = as.Date(Date), BM_Ret)]
LIQ_DT   <- fwd$liq_dt[, .(Date = as.Date(Date), Ticker, adv)]
ewb <- fwd$returns_dt[, .(ew = mean(Ret_1m, na.rm = TRUE)), by = .(date = as.Date(Date))]
realized_sig <- sort(unique(RET_DT$Date))
rm(rawme_f); invisible(gc())
wf("[fwd] 실현 signal월 %d (마지막 실현 = %s, 홀딩월 %s)", length(realized_sig),
   as.character(max(realized_sig)), hym(max(realized_sig)))

sc <- as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet",
        col_select = c("signal_date","security_id","factor_id","z")))
sc <- sc[factor_id %in% APPROVED]; sc[, signal_date := as.Date(signal_date)]
POOL_FACS <- sort(intersect(APPROVED, unique(sc$factor_id)))
fw <- dcast(sc, signal_date + security_id ~ factor_id, value.var = "z")
FW_FACS <- intersect(POOL_FACS, names(fw))
fw_z <- fw[, c("signal_date","security_id", FW_FACS), with = FALSE]; setkey(fw_z, signal_date)
rm(fw, sc); invisible(gc())

## ═══════════ 2. frozen 선별 기계 (R6/R13 verbatim) + 신규 anchor 확장 ═══════════
if (!file.exists(SEL_FROZEN)) stop("[fail-closed] frozen 선별 궤적 부재: ", SEL_FROZEN)
sel_traj <- readRDS(SEL_FROZEN)
frozen_base_anchors <- as.integer(sel_traj[["36"]]$anchors)

base_anchors_all <- seq(W36 + 1L, n_dep, by = CADENCE_ENTRY)   # = cohortEntry (동일 수열)
anchors_exit_all <- seq(W36 + 1L, n_dep, by = CADENCE_EXIT)    # 퇴출 anchor ⊇ 진입 anchor
cohortEntry_all  <- base_anchors_all

SUBALL <- if (file.exists(SUB_FROZEN)) readRDS(SUB_FROZEN) else list()
if (file.exists(SUB_EXT)) { .e <- readRDS(SUB_EXT); for (k in names(.e)) if (is.null(SUBALL[[k]])) SUBALL[[k]] <- .e[[k]] }
need_anchor <- setdiff(as.character(anchors_exit_all), names(SUBALL))

if (length(need_anchor)) {
  ## ── 신규 anchor: 배포권 패널에서 동일 규칙(win_nwt_vec)으로 부분창 NW-t 계산 ──
  wf("[extend] 신규 anchor %d건: %s — 패널 기반 부분창 NW-t 계산", length(need_anchor), paste(need_anchor, collapse = ","))
  PANEL <- as.data.table(read_parquet(PANEL_STORED)); PANEL[, signal_date := as.Date(signal_date)]
  if (file.exists(PANEL_EXT)) {
    pe <- as.data.table(read_parquet(PANEL_EXT)); pe[, signal_date := as.Date(signal_date)]
    PANEL <- rbindlist(list(PANEL, pe), fill = TRUE)
  }
  pan_dates <- sort(unique(PANEL$signal_date))
  need_pm <- max(as.integer(need_anchor)) - 1L
  if (length(pan_dates) < need_pm) {
    ## 패널 확장: R6 Step1 자구동일(per-factor canonical_screen_bt full 재계산) + 기존행 parity 후 신규행만 append.
    ## 저장은 러너 소유 캐시(PANEL_EXT)에만 — R6 산출물(PANEL_STORED)은 read-only 유지.
    wf("[extend] 패널 확장 필요: 보유 %d < 필요 %d — per-factor canonical_screen_bt 재계산 (수 분 소요)", length(pan_dates), need_pm)
    source("02_Infrastructure/contracts/canonical_screen_bt.R")
    sc2 <- as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet",
             col_select = c("signal_date","security_id","factor_id","z")))
    sc2 <- sc2[factor_id %in% APPROVED]; sc2[, signal_date := as.Date(signal_date)]
    rows <- list()
    for (fid in sort(unique(PANEL$factor_id))) {
      s <- sc2[factor_id == fid, .(Date = as.Date(signal_date), Ticker = security_id, score = z)][!is.na(score)]
      cs <- tryCatch(canonical_screen_bt(s, RET_DT, BENCH_DT, top_n = TOP_N, cost_bps_oneway = COST_BPS,
              liq_dt = LIQ_DT, liq_min = LIQ_MIN, run_id = "ppt_panel", strategy_id = fid,
              diag_dual_basis = FALSE), error = function(e) NULL)
      if (is.null(cs) || is.null(cs$period_returns)) next
      pr <- as.data.table(cs$period_returns)
      rows[[fid]] <- data.table(signal_date = as.Date(pr$date), factor_id = fid,
        ret_net = pr$ret_net, benchmark_ret = pr$benchmark_ret, active_bm = pr$ret_net - pr$benchmark_ret)
    }
    NEWP <- rbindlist(rows, fill = TRUE); rm(sc2); invisible(gc())
    ov <- merge(NEWP, PANEL[, .(signal_date, factor_id, ref = active_bm)], by = c("signal_date","factor_id"))
    ov_delta <- if (nrow(ov)) max(abs(ov$active_bm - ov$ref), na.rm = TRUE) else NA_real_
    wf("[extend] 패널 parity(기존행 재계산 vs 저장): n=%d max|d|=%.2e", nrow(ov), ov_delta)
    if (!is.finite(ov_delta) || ov_delta >= 1e-8)
      stop("[fail-closed] 패널 parity 미달 — 업스트림 데이터 변형 의심. append 중단(도훈 판단 재료).")
    add <- NEWP[!signal_date %in% pan_dates]
    if (nrow(add)) {
      pe_all <- if (file.exists(PANEL_EXT)) {
        p0 <- as.data.table(read_parquet(PANEL_EXT)); p0[, signal_date := as.Date(signal_date)]
        rbindlist(list(p0, add[, .(signal_date, factor_id, ret_net, benchmark_ret, active_bm)]), fill = TRUE)
      } else add[, .(signal_date, factor_id, ret_net, benchmark_ret, active_bm)]
      tmpp <- paste0(PANEL_EXT, ".tmp_", Sys.getpid()); write_parquet(unique(pe_all), tmpp)
      if (file.exists(PANEL_EXT)) unlink(PANEL_EXT); file.rename(tmpp, PANEL_EXT)
      PANEL <- rbindlist(list(PANEL, add), fill = TRUE)
      pan_dates <- sort(unique(PANEL$signal_date))
      wf("[extend] 패널 확장 완료: +%d행 -> %d개월 (러너 캐시 %s)", nrow(add), length(pan_dates), PANEL_EXT)
    }
  }
  stopifnot(all(pan_dates == realized_sig[seq_along(pan_dates)]))   # 정렬 검증 (signal 축 일치)
  PANEL_FACS <- sort(unique(PANEL$factor_id))
  Pw <- dcast(PANEL, signal_date ~ factor_id, value.var = "active_bm"); setorder(Pw, signal_date)
  Pmat <- as.matrix(Pw[, ..PANEL_FACS]); rownames(Pmat) <- as.character(Pw$signal_date)
  n_pm <- nrow(Pmat)
  win_nwt_vec <- function(a, back_start, back_end){                  # run_ramp_r13_decay.R 자구동일
    lo <- a - back_start; hi <- a - back_end
    if (lo < 1L || hi > n_pm || lo > hi) return(NULL)
    sub <- Pmat[lo:hi, , drop = FALSE]
    apply(sub, 2, function(x){ x <- x[is.finite(x)]; if (length(x) < 12) return(NA_real_)
      m <- lm(x ~ 1); as.numeric(coeftest(m, vcov = sandwich::NeweyWest(m, lag = 3, prewhite = FALSE))[1,3]) })
  }
  new_entries <- list()
  for (a_ch in need_anchor) {
    a <- as.integer(a_ch)
    if (a - 1L > n_pm) stop("[fail-closed] anchor ", a, " 부분창에 패널 부족(", n_pm, "행) — 다음 월 데이터 후 재시도")
    lvl <- win_nwt_vec(a, W36, 1L); if (is.null(lvl)) stop("[fail-closed] anchor ", a, " level36 계산 불가")
    new_entries[[a_ch]] <- list(level36 = lvl,
      recent18 = win_nwt_vec(a, 18L, 1L), older18 = win_nwt_vec(a, 36L, 19L),
      sub1 = win_nwt_vec(a, 36L, 25L), sub2 = win_nwt_vec(a, 24L, 13L), sub3 = win_nwt_vec(a, 12L, 1L))
  }
  ext_prev <- if (file.exists(SUB_EXT)) readRDS(SUB_EXT) else list()
  for (k in names(new_entries)) ext_prev[[k]] <- new_entries[[k]]
  saveRDS_atomic(ext_prev, SUB_EXT)
  for (k in names(new_entries)) SUBALL[[k]] <- new_entries[[k]]
  wf("[extend] SUB 확장 저장: +%d anchors -> %s", length(new_entries), SUB_EXT)
}

## ── base pool getter (R6 trailing PORT_t top-K20 — frozen 궤적 우선, 신규 anchor는 level36 동일 규칙) ──
pool_base_at <- function(ga){
  gc <- as.character(ga)
  tj <- sel_traj[["36"]]$traj[[gc]]
  if (!is.null(tj)) return(tj$pool[["K20"]])
  lvl <- SUBALL[[gc]]$level36
  head(names(sort(lvl[is.finite(lvl)], decreasing = TRUE)), K20)
}
getter_base <- function(i){ pool_base_at(max(base_anchors_all[base_anchors_all <= i])) }

## ── D-2 비대칭 퇴출(감쇠속도) pool 궤적 (run_ramp_r13_decay.R build_pool_traj_D2 자구동일) ──
build_pool_traj_D2 <- function(){
  held <- NULL; pool_by_anchor <- list()
  for (a in anchors_exit_all) {
    S <- SUBALL[[as.character(a)]]
    if (is.null(S) || is.null(S$level36)) { pool_by_anchor[[as.character(a)]] <- held; next }
    lvl <- S$level36; rec <- S$recent18; dec <- rec - S$older18
    ranked_lvl <- names(sort(lvl[is.finite(lvl)], decreasing = TRUE))
    is_entry <- a %in% cohortEntry_all
    if (is_entry || is.null(held)) {
      held <- head(ranked_lvl, K20)
    } else {
      keep <- held[ vapply(held, function(f){
        rf <- if (f %in% names(rec)) rec[[f]] else NA_real_
        df <- if (f %in% names(dec)) dec[[f]] else NA_real_
        (is.finite(rf) && rf >= 0) && !(is.finite(df) && df < DECAY_DROP_BAR) }, logical(1)) ]
      slots <- K20 - length(keep)
      if (slots > 0) {
        pool_rank <- setdiff(ranked_lvl, keep)
        clean <- pool_rank[ vapply(pool_rank, function(f){ rf <- if (f %in% names(rec)) rec[[f]] else NA_real_
          !is.finite(rf) || rf >= 0 }, logical(1)) ]
        fill <- head(clean, slots)
        if (length(fill) < slots) { rest <- setdiff(pool_rank, fill); fill <- c(fill, head(rest, slots - length(fill))) }
        held <- c(keep, fill)
      } else held <- keep
    }
    pool_by_anchor[[as.character(a)]] <- held
  }
  pool_by_anchor
}
POOL_D2 <- build_pool_traj_D2()
getter_D2 <- function(i){ ga <- max(anchors_exit_all[anchors_exit_all <= i])
  p <- POOL_D2[[as.character(ga)]]; if (is.null(p)) getter_base(i) else p }

## ── composite + weights (run_ramp_r13_decay.R build_composite_g/build_weights 자구동일; EW만 사용) ──
build_composite_g <- function(pool_getter){
  deploy_idx <- (W36 + 1L):n_dep; rows <- list()
  for (i in deploy_idx) {
    facs <- intersect(pool_getter(i), FW_FACS); if (length(facs) == 0) next
    sub <- fw_z[.(sig_dates[i])]; if (nrow(sub) == 0) next
    Xz <- sub[, lapply(.SD, zc), .SDcols = facs]; Xm <- as.matrix(Xz); Xm[is.na(Xm)] <- 0
    rows[[as.character(i)]] <- data.table(signal_date = sig_dates[i], security_id = sub$security_id, score = rowMeans(Xm))
  }
  s <- rbindlist(rows); s[, score := zc(score), by = signal_date]; s
}
build_weights_ew <- function(comp){
  S <- comp[!is.na(score), .(Date = as.Date(signal_date), Ticker = security_id, score)]
  S <- merge(S, LIQ_DT[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
  S <- S[is.na(adv) | adv >= LIQ_MIN]; S[, adv := NULL]
  setorder(S, Date, -score)
  S[, { n <- min(TOP_N, .N); .(Ticker = Ticker[seq_len(n)], w = rep(1/n, n)) }, by = Date]
}

wf("[frozen] base anchors(frozen)=%d..%d | exit anchors=%d개(마지막 %d) | D-2 pool anchors=%d",
   min(frozen_base_anchors), max(frozen_base_anchors), length(anchors_exit_all),
   max(anchors_exit_all), length(POOL_D2))

W_ALL <- list(
  PPURE_BASE_W36K20  = build_weights_ew(build_composite_g(getter_base)),
  PPURE_D2_DECAYEXIT = build_weights_ew(build_composite_g(getter_D2))
)

## ═══════════ 3. 등록 (1회, idempotent — holdout_falsification.R 계약 재사용) ═══════════
register_track <- function(td){
  ipath <- file.path(td$dir, "holdout_interval.json")
  if (file.exists(ipath)) { wf("[register %s] 기존 봉인 구간 존재 — 재등록 안함(불변 원칙)", td$id); return(invisible(fromJSON(ipath))) }
  if (!file.exists(R13_CACHE)) stop("[fail-closed] 등록 원천 부재: ", R13_CACHE)
  r13 <- readRDS(R13_CACHE)
  pr <- as.data.table(r13$PR[[td$model]]); pr[, date := as.Date(date)]
  wm <- as.data.table(r13$WMAP[[td$model]]); wm[, Date := as.Date(Date)]
  stopifnot(nrow(pr) == 220L, max(pr$date) == SEAL_END)
  ## base는 R6 저장 계열과 bit-일치 재검증 (가능 시)
  parity_r6 <- NA_real_
  if (td$model == "base" && file.exists(".cache/_ramp_r6_20260711.rds")) {
    r6 <- readRDS(".cache/_ramp_r6_20260711.rds")
    m0 <- merge(pr[, .(date, a = ret_net)], as.data.table(r6$PR[["Ppure_W36_K20"]])[, .(date = as.Date(date), b = ret_net)], by = "date")
    parity_r6 <- max(abs(m0$a - m0$b))
  }
  rrow <- tryCatch({ sm <- fromJSON(R13_SUMMARY); as.data.table(sm$results)[model == td$model] }, error = function(e) NULL)

  iv    <- build_holdout_interval(pr$ret_net, holdout_months = HOLDOUT_M, block = BLOCK, B = BBOOT, seed = SEED, strategy_id = td$id)
  iv_ew <- build_holdout_interval(pr$act,    holdout_months = HOLDOUT_M, block = BLOCK, B = BBOOT, seed = SEED, strategy_id = paste0(td$id, "_ew_active"))
  iv_bm <- build_holdout_interval(pr$act_bm, holdout_months = HOLDOUT_M, block = BLOCK, B = BBOOT, seed = SEED, strategy_id = paste0(td$id, "_capw_active"))
  pick <- function(x) x[c("q05","q95","sr_input","boot_median","holdout_months","block","B","seed","n_input_months")]

  iv$track_id <- td$id
  iv$track_desc <- td$desc
  iv$paper_only <- "페이퍼 전용 — book_state 무변경·자본 게이트(HARD 3종/book-marginal ΔIR) 무관·실주문 없음·05_Production 무접촉 (도훈 승인 2026-07-13 태스크 #62 병행안)"
  iv$candidate_selected_at <- CAND_SELECTED_AT
  iv$selection_bias_label <- td$selection_bias
  iv$live_start_signal_month <- as.character(sig_dates[sig_dates > SEAL_END][1])   # 봉인 이후 첫 signal월(2026-05-31)부터 페이퍼 적립
  iv$basis_labels <- list(
    primary_interval_basis = "absolute_net_monthly ret_net (STR_1715 c3 컨벤션 — sr_input/구간은 절대 net 월수익 기준)",
    ew_uni  = "EW-유니버스 active(진단·페이퍼 채점 프레임 — dossier §0 B안: 월간 EW-active 채점) -> supplementary_intervals$ew_active",
    capw    = "cap-w active(계약 권위 basis — 자본 게이트용. 본 트랙은 자본 게이트 무관, 병기만) -> supplementary_intervals$capw_active")
  iv$supplementary_intervals <- list(ew_active = pick(iv_ew), capw_active = pick(iv_bm))
  iv$reference_stats_r13 <- if (!is.null(rrow) && nrow(rrow)) as.list(rrow[1]) else "r13 summary 미로드"
  iv$source_series <- list(
    path = sprintf("%s $PR[['%s']] (220m %s~%s, weighted_screen_bt 계약 산출)", R13_CACHE, td$model, "2008-01-31", as.character(SEAL_END)),
    sealed_copy_series   = file.path(td$dir, "sealed_source_series.csv"),
    sealed_copy_holdings = file.path(td$dir, "sealed_holdings_ref.csv"),
    parity_base_vs_r6_stored = if (is.finite(parity_r6)) parity_r6 else NULL)
  iv$config <- list(r13_config_hash = R13_CFG_HASH,
    r13_summary = R13_SUMMARY, r6_summary = "outputs/ramp/r6_portt_boruta_summary_20260711.json",
    d3_dossier = "04_Research/01_reports/d3_deployability_dossier_20260713.md (승인안 = §7 병행안)",
    frozen_rule = if (td$model == "base")
      "W36 trailing realized active NW-t top-K20 pool (cadence6) -> 팩터 EW composite -> liq>=2e8 top-25 EW, 15bps delta-based"
    else
      "진입 cadence6 full top-K20(level36) / 퇴출 cadence3 감쇠트리거(recent18_t<0 OR recent18_t-older18_t<-1.0 배출, 비-감쇠 차순위 충원) -> 팩터 EW composite -> liq>=2e8 top-25 EW, 15bps delta-based")
  iv$dossier_prereg_proposal <- "dossier §0(정보성, 비바인딩·도훈 결정 사항): 페이퍼 12m EW-active IR<0 또는 trailing 12m PORT_t<0 -> 종결 재평가"
  save_holdout_interval(iv, ipath)

  dir.create(td$dir, recursive = TRUE, showWarnings = FALSE)
  fwrite_atomic(pr[, .(signal_date = date, ret_net, benchmark_ret, act_capw = act_bm, act_ew = act)],
                file.path(td$dir, "sealed_source_series.csv"))
  fwrite_atomic(wm[, .(signal_date = Date, Ticker, w)], file.path(td$dir, "sealed_holdings_ref.csv"))
  wf("[register %s] 봉인: net [%.4f, %.4f] (sr_input %.4f) | ew_active [%.4f, %.4f] | capw_active [%.4f, %.4f]%s",
     td$id, iv$q05, iv$q95, iv$sr_input, iv_ew$q05, iv_ew$q95, iv_bm$q05, iv_bm$q95,
     if (is.finite(parity_r6)) sprintf(" | base-vs-R6 parity max|d|=%.1e", parity_r6) else "")
  invisible(fromJSON(ipath))
}

## ═══════════ 4. 트랙 실행: parity guard -> 페이퍼 append -> 보유 스냅샷 -> trailing 판정 ═══════════
run_track <- function(td){
  wf("\n--- track %s ---", td$id)
  dir.create(td$dir, recursive = TRUE, showWarnings = FALSE)
  reg <- register_track(td)
  Wfull <- W_ALL[[td$id]]

  sref <- fread(file.path(td$dir, "sealed_source_series.csv"))
  href <- fread(file.path(td$dir, "sealed_holdings_ref.csv"))
  sref[, signal_date := as.Date(signal_date)]; href[, signal_date := as.Date(signal_date)]
  stopifnot(max(sref$signal_date) == SEAL_END)

  ## (1) 보유 parity (봉인 전 구간 전체 — 멤버십+비중 완전 일치 요구)
  A <- Wfull[Date <= SEAL_END]
  M <- merge(A, href[, .(Date = signal_date, Ticker, w_ref = w)], by = c("Date","Ticker"), all = TRUE)
  n_miss <- sum(is.na(M$w) | is.na(M$w_ref))
  dW <- if (n_miss > 0) Inf else max(abs(M$w - M$w_ref))
  parity_hold <- n_miss == 0 && dW < 1e-12
  wf("[parity %s] 보유(220m x 25): 불일치행=%d max|dw|=%.2e -> %s", td$id, n_miss, dW, ifelse(parity_hold, "PASS", "FAIL"))

  ## (2) 수익 구성 (계약 경로) + 봉인 계열 parity
  Wreal <- Wfull[Date %in% realized_sig]
  bt <- weighted_screen_bt(Wreal, RET_DT, BENCH_DT, cost_bps_oneway = COST_BPS,
                           run_id = "ppure_paper_track", strategy_id = td$id)
  pr <- as.data.table(bt$period_returns); pr[, date := as.Date(date)]
  ## 이중기입 검증: traded/cost 로컬 산출(weighted_screen_bt 자구동일 루프)이 계약 ret_net 재현하는지
  WR <- merge(Wreal, RET_DT[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"), all.x = TRUE)
  WR[is.na(Ret_1m), Ret_1m := 0]
  port <- WR[, .(port_gross = sum(w * Ret_1m)), by = Date]
  dts <- sort(unique(Wreal$Date)); traded <- numeric(length(dts)); names(traded) <- as.character(dts)
  prev <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    cur <- Wreal[Date == dts[i], .(Ticker, w)]
    m2 <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_cur","_prev"))
    m2[is.na(w_cur), w_cur := 0]; m2[is.na(w_prev), w_prev := 0]
    traded[i] <- sum(abs(m2$w_cur - m2$w_prev)); prev <- cur
  }
  setorder(port, Date); port[, traded := traded[as.character(Date)]]
  port[, cost := traded * COST_BPS / 1e4]; port[, ret_net_local := port_gross - cost]
  xc <- merge(port[, .(date = Date, ret_net_local)], pr[, .(date, ret_net)], by = "date")
  dxc <- max(abs(xc$ret_net_local - xc$ret_net))
  stopifnot(dxc < 1e-10)
  mm <- merge(pr[date <= SEAL_END, .(date, ret_net)], sref[, .(date = signal_date, ref = ret_net)], by = "date")
  dR <- if (nrow(mm) == nrow(sref)) max(abs(mm$ret_net - mm$ref)) else Inf
  parity_ret <- dR < 1e-10
  wf("[parity %s] 수익(계약 재구성 vs 봉인): n=%d/%d max|d|=%.2e -> %s | 이중기입 max|d|=%.2e",
     td$id, nrow(mm), nrow(sref), dR, ifelse(parity_ret, "PASS", "FAIL"), dxc)

  if (!(parity_hold && parity_ret))
    stop("[fail-closed ", td$id, "] parity guard 실패 — 업스트림 데이터 변형 의심. append 중단(도훈 보고 재료). ",
         "[[project-cache-vintage-pinning]] / [[project-rawdata-april-gap-incident-20260711]] 참조")

  ## (3) 페이퍼 NAV append (봉인 이후 실현월만; idempotent)
  navp <- file.path(td$dir, "paper_nav.csv")
  old <- if (file.exists(navp)) { o <- fread(navp); o[, signal_date := as.Date(signal_date)]; o } else NULL
  newpr <- pr[date > SEAL_END]
  newpr <- merge(newpr, ewb, by = "date", all.x = TRUE)
  newpr <- merge(newpr, port[, .(date = Date, port_gross, traded, cost)], by = "date", all.x = TRUE)
  rows <- newpr[, .(signal_date = date, holding_ym = hym(date),
                    ret_net, benchmark_ret, ew_ret = ew,
                    act_capw = ret_net - benchmark_ret, act_ew = ret_net - ew,
                    traded, cost, metric_type = "weighted_screen(계약)·paper", appended_at = RUNSTAMP)]
  if (!is.null(old)) rows <- rows[!signal_date %in% old$signal_date]
  n_new <- nrow(rows)
  allp <- rbindlist(list(old, rows), use.names = TRUE, fill = TRUE)
  if (nrow(allp)) {
    setorder(allp, signal_date)
    allp[, nav := cumprod(1 + ret_net)]   # 표시 참고용 누적(트랙 시작=1). 계약값은 ret_net.
    fwrite_atomic(allp, navp)
  }
  wf("[paper %s] 신규 %d행 append (누적 %d행, 최신 홀딩월 %s ret_net=%s)", td$id, n_new, nrow(allp),
     if (nrow(allp)) allp[.N, holding_ym] else "-", if (nrow(allp)) sprintf("%+.4f", allp[.N, ret_net]) else "-")

  ## (4) 보유 기록: paper_holdings append (봉인 이후 전 signal월, 미실현 최신월 포함) + 최신 스냅샷
  hp <- file.path(td$dir, "paper_holdings.csv")
  oldh <- if (file.exists(hp)) { o <- fread(hp); o[, signal_date := as.Date(signal_date)]; o } else NULL
  Hnew <- Wfull[Date > SEAL_END, .(signal_date = Date, Ticker, w)]
  Hnew[, holding_ym := hym(signal_date)]
  if (!is.null(oldh)) Hnew <- Hnew[!signal_date %in% oldh$signal_date]
  allh <- rbindlist(list(oldh, Hnew), use.names = TRUE, fill = TRUE)
  if (nrow(allh)) { setorder(allh, signal_date, -w, Ticker); fwrite_atomic(allh, hp) }
  lastW <- Wfull[Date == max(Date)]
  fwrite_atomic(lastW[order(-w, Ticker), .(signal_date = Date, holding_ym = hym(max(Wfull$Date)), Ticker, w)],
                file.path(td$dir, "holdings_latest.csv"))
  wf("[holdings %s] 최신 signal=%s 홀딩월=%s 종목수=%d (paper_holdings 누적 %d행)",
     td$id, as.character(max(Wfull$Date)), hym(max(Wfull$Date)), nrow(lastW), nrow(allh))

  ## (5) trailing 실측 vs 봉인 구간 (judge_holdout 공용 — 6개월 미만 INSUFFICIENT)
  vj <- if (nrow(allp) >= 1L) {
    j_net <- tryCatch({
      iv_top <- reg; iv_top$consumed <- isTRUE(reg$consumed)
      judge_holdout(iv_top, tail(allp$ret_net, min(HOLDOUT_M, nrow(allp))), window_label = "live_trailing_net")
    }, error = function(e) list(verdict = "CONSUMED_OR_ERR", n = NA_integer_, note = conditionMessage(e)))
    j_ew <- tryCatch({
      ivw <- reg$supplementary_intervals$ew_active; ivw$consumed <- FALSE
      judge_holdout(ivw, tail(allp$act_ew, min(HOLDOUT_M, nrow(allp))), window_label = "live_trailing_ew_active")
    }, error = function(e) list(verdict = "ERR", note = conditionMessage(e)))
    wf("[judge %s] net: %s (n=%d) | ew_active: %s", td$id, j_net$verdict, j_net$n,
       if (!is.null(j_ew$verdict)) j_ew$verdict else "ERR")
    list(net = j_net, ew = j_ew)
  } else { wf("[judge %s] 페이퍼 실측 0행 — 판정 없음", td$id); NULL }

  list(id = td$id, reg = reg, n_new = n_new, n_paper = nrow(allp),
       parity_hold = parity_hold, parity_ret = parity_ret, dW = dW, dR = dR, judge = vj,
       last_holdings = lastW, seal_holdings = Wfull[Date == SEAL_END])
}

RESULTS <- lapply(TRACKS, run_track)

## ═══════════ 5. 검증 출력: 봉인 마지막월 보유 vs d3 dossier / R13 스냅샷 ═══════════
d3h <- tryCatch(fread("stage_artifacts/d3_dossier/holdings_latest_ppure.csv"), error = function(e) NULL)
if (!is.null(d3h)) {
  bsl <- RESULTS[[1]]$seal_holdings$Ticker
  wf("\n[verify] base@%s vs d3_dossier holdings_latest_ppure.csv: overlap=%d/%d",
     as.character(SEAL_END), length(intersect(d3h$Ticker, bsl)), length(bsl))
} else w("\n[verify] d3_dossier 스냅샷 미존재 — 봉인 보유 parity(sealed_holdings_ref)로 대체 검증됨")
wf("[verify] D-2@%s 보유는 sealed_holdings_ref(=R13 WMAP armD2) 220m 전체 parity로 검증됨 (위 parity guard)", as.character(SEAL_END))

wf("\n=== DONE %s ===", RUNSTAMP)
for (r in RESULTS)
  wf("  %s: net봉인[%.4f,%.4f] | 신규 %d행 (누적 %d) | parity 보유 %s / 수익 %s | 최신판정 %s",
     r$id, r$reg$q05, r$reg$q95, r$n_new, r$n_paper,
     ifelse(r$parity_hold, "PASS", "FAIL"), ifelse(r$parity_ret, "PASS", "FAIL"),
     if (!is.null(r$judge)) r$judge$net$verdict else "-")
close(con)
cat(readLines(logf, encoding = "UTF-8"), sep = "\n")
cat(sprintf("\nPPURE_PAPER_TRACK_DONE tracks=%d new_rows=%s log=%s\n",
    length(RESULTS), paste(vapply(RESULTS, function(r) r$n_new, numeric(1)), collapse = ","), logf))
