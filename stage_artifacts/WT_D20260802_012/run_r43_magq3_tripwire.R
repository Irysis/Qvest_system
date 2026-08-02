## run_r43_magq3_tripwire.R — WT-D20260802_012 / R43
## INS_MAGQ3 보조 tripwire 증분 실측 (WT-D20260802_007 NP-1 승계)
##   사전등록: stage_artifacts/WT_D20260802_012/preregistration.json (config_hash 검증 의무)
##   자본 아님 — per-holding 안전 특성화(monitoring). alpha/Σ/weight 미산출.
## 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_012/run_r43_magq3_tripwire.R", encoding="UTF-8")'
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest); library(digest)
})
setDTthreads(1); try(arrow::set_cpu_count(1), silent = TRUE); try(arrow::set_io_thread_count(2L), silent = TRUE)
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
set.seed(20260802L)

OUT  <- "stage_artifacts/WT_D20260802_012"
logf <- file.path(OUT, "_r43_run_log.txt"); if (file.exists(logf)) try(file.remove(logf), silent = TRUE)
w  <- function(...) { msg <- paste0(...)
  try({ .lc <- file(logf, "a", encoding = "UTF-8"); writeLines(msg, .lc); close(.lc) }, silent = TRUE); cat(msg, "\n") }
wf <- function(...) w(sprintf(...))

ymshift <- function(ymv, k) { y <- ymv %/% 100L; m <- ymv %% 100L; t <- (y * 12L + (m - 1L)) + k; (t %/% 12L) * 100L + (t %% 12L) + 1L }
## --- R38 verbatim: NW lag-3 mean/se/t on a monthly series ---
nw_fit <- function(x) { x <- x[is.finite(x)]; if (length(x) < 12) return(list(mean = NA, se = NA, t = NA, n = length(x)))
  m <- lm(x ~ 1); ct <- coeftest(m, vcov = sandwich::NeweyWest(m, lag = 3, prewhite = FALSE))
  list(mean = as.numeric(ct[1, 1]), se = as.numeric(ct[1, 2]), t = as.numeric(ct[1, 3]), n = length(x)) }
## --- R40 verbatim: risk_metrics ---
risk_metrics <- function(r) { r <- r[is.finite(r)]
  if (!length(r)) return(list(n = 0L, mean = NA_real_, downside = NA_real_, tail = NA_real_, vol = NA_real_, min = NA_real_))
  list(n = length(r), mean = mean(r), downside = mean(r[r < 0]), tail = mean(r < -0.15), vol = sd(r), min = min(r)) }

w("=== R43 INS_MAGQ3 보조 tripwire 증분 실측 — WT-D20260802_012 (monitoring 진단, 자본 아님) ===")

## ── 0. 사전등록 로드 + 해시 검증 (측정 전 고정 확인) ─────────────────────────────
PP <- file.path(OUT, "preregistration.json"); SP <- file.path(OUT, "preregistration.seal.json")
stopifnot(file.exists(PP), file.exists(SP))
PRE <- fromJSON(PP, simplifyVector = FALSE)
PRE_HASH <- PRE$config_hash
SEAL <- fromJSON(SP)
## 측정 개시 전 봉인된 파일 바이트와 대조 — 사전등록이 측정 후 손대지지 않았음의 증거
PRE_FILE_SHA <- digest::digest(file = PP, algo = "sha256")
if (!identical(PRE_FILE_SHA, SEAL$file_sha256))
  stop(sprintf("[prereg] 봉인 불일치 — 사전등록 변조 의심 (now=%s sealed=%s)", PRE_FILE_SHA, SEAL$file_sha256))
stopifnot(identical(PRE_HASH, SEAL$config_hash))
A_THR   <- as.numeric(PRE$signals$A_live$threshold)      # 1.0 (INS_NB_THR frozen)
AUX_THR <- as.numeric(PRE$signals$AUX_new$threshold)     # 1.0 (사전 고정)
wf("[prereg] hash=%s 검증 PASS | A_THR=%.2f AUX_THR=%.2f | selection=%s n_trials=%d",
   PRE_HASH, A_THR, AUX_THR, PRE$selection_type, PRE$n_trials)

## ============================================================================
## 1. 위반 주입 테스트 (측정 규율 #3) — 실제 판정 코드 경로를 먼저 시험한다.
##    오탐 제거와 검사 사망은 겉보기가 같으므로, 문턱/가드를 일부러 깨서 발화를 확인.
## ============================================================================
## 판정에 실제로 쓰이는 유일한 flag 생성기 (아래 전 구간이 이 함수만 사용)
mk_flag <- function(z, thr) as.integer(!is.na(z) & z >= thr)
## 판정에 실제로 쓰이는 유일한 상태기계 (A/A′ 공용). guard_cov/guard_consec 는 돌연변이 주입용 스위치.
build_states <- function(DT, on_col, cov_col, guard_cov = TRUE, guard_consec = TRUE) {
  d <- copy(DT); setorder(d, Ticker, hold_ym)
  d[, .on   := as.integer(get(on_col))]
  d[, .cov  := as.logical(get(cov_col))]
  d[, .onp  := shift(.on),  by = Ticker]
  d[, .covp := shift(.cov), by = Ticker]
  d[, .ymp  := shift(hold_ym), by = Ticker]
  d[, .consec := !is.na(.ymp) & (.ymp == ymshift(hold_ym, -1L))]
  d[, .both_cov := .cov & !is.na(.covp) & .covp]
  ok_cov    <- if (guard_cov)    d$.both_cov else d$.cov            # 돌연변이: 직전월 커버리지 요건 제거
  ok_consec <- if (guard_consec) d$.consec   else rep(TRUE, nrow(d)) # 돌연변이: 연속월 요건 제거
  d[, .valid := ok_cov & ok_consec & !is.na(.onp)]
  d[, .on_p := as.integer(.valid & !is.na(.onp) & .onp == 1L)]
  d[, state := fifelse(!.valid, NA_character_,
               fifelse(.on == 1L & .on_p == 0L, "ENTRY",
               fifelse(.on == 1L & .on_p == 1L, "SUSTAIN",
               fifelse(.on == 0L & .on_p == 1L, "EXIT", "OFF"))))]
  d[]
}

INJ <- list()
## IT-1 문턱 경계: z ∈ {0.999, 1.000, 1.001, NA} → flag {0,1,1,0}
it1_got <- mk_flag(c(0.999, 1.000, 1.001, NA_real_), A_THR)
it1_exp <- c(0L, 1L, 1L, 0L)
INJ$IT1 <- list(expected = it1_exp, got = it1_got, pass = identical(it1_got, it1_exp))
if (!INJ$IT1$pass) stop("[INJECT] IT-1 문턱 경계 FAIL — flag 생성기 사망")
wf("[INJECT] IT-1 문턱경계 {0.999,1.000,1.001,NA} → {%s} PASS", paste(it1_got, collapse = ","))

## IT-3 상태기계 합성 주입: 설계된 시퀀스가 정확히 재현되는가 + 가드 돌연변이가 반드시 결과를 바꾸는가
SYN <- data.table(
  Ticker  = c(rep("ZZTEST1", 6), rep("ZZTEST2", 3)),
  hold_ym = c(201001L, 201002L, 201003L, 201004L, 201006L, 201007L, 201001L, 201002L, 201003L),
  z       = c(0.0, 1.5, 1.5, 0.0, 1.5, 1.5,   1.5, NA_real_, 1.5))
SYN[, cov := !is.na(z)]; SYN[, on := mk_flag(z, A_THR)]
syn_st <- build_states(SYN, "on", "cov")$state
syn_exp <- c(NA, "ENTRY", "SUSTAIN", "EXIT", NA, "SUSTAIN",   NA, NA, NA)
INJ$IT3_base <- list(expected = syn_exp, got = syn_st, pass = identical(syn_st, syn_exp))
if (!INJ$IT3_base$pass)
  stop(sprintf("[INJECT] IT-3 상태기계 FAIL — got={%s} exp={%s}",
               paste(syn_st, collapse = ","), paste(syn_exp, collapse = ",")))
wf("[INJECT] IT-3 상태기계 합성주입 {%s} PASS (201005 결측월·201002 커버결측 모두 NA 처리)",
   paste(ifelse(is.na(syn_st), ".", syn_st), collapse = ","))
## IT-3 돌연변이 A: consec 가드 제거 → 201006 이 ENTRY 로 오분류되어야 (가드 살아있음의 증거)
mut_consec <- build_states(SYN, "on", "cov", guard_consec = FALSE)$state
INJ$IT3_mut_consec <- list(got = mut_consec, changed = !identical(mut_consec, syn_st))
if (!INJ$IT3_mut_consec$changed) stop("[INJECT] IT-3 돌연변이(consec 제거)가 결과를 바꾸지 못함 — 연속월 가드 사망")
## IT-3 돌연변이 B: both_cov 가드 제거 → ZZTEST2 201003 이 ENTRY 로 오분류되어야
mut_cov <- build_states(SYN, "on", "cov", guard_cov = FALSE)$state
INJ$IT3_mut_cov <- list(got = mut_cov, changed = !identical(mut_cov, syn_st))
if (!INJ$IT3_mut_cov$changed) stop("[INJECT] IT-3 돌연변이(both_cov 제거)가 결과를 바꾸지 못함 — 커버리지 가드 사망")
wf("[INJECT] IT-3 돌연변이 consec제거→{%s} / both_cov제거→{%s} : 둘 다 결과 변경 = 가드 실효 확인",
   paste(ifelse(is.na(mut_consec), ".", mut_consec), collapse = ","),
   paste(ifelse(is.na(mut_cov), ".", mut_cov), collapse = ","))

## ============================================================================
## 2. base 상속 (R38/R40 동일 uni) + 신호 부착
## ============================================================================
RDS <- "stage_artifacts/WT_D20260715_005/_r36_objects.rds"; stopifnot(file.exists(RDS))
o36 <- readRDS(RDS); uni <- copy(as.data.table(o36$uni))
BASE_PARITY <- o36$out$base_parity$clean_parity_port_t
RAW_P <- ".cache/pin/rawdata_r9_pin_20260715.parquet"; if (!file.exists(RAW_P)) RAW_P <- ".cache/rawdata.parquet"
PIN_MTIME <- as.character(file.info(RAW_P)$mtime)
LIQ <- 2e8
setorder(uni, Ticker, hold_ym)
MAX_YM <- max(uni$hold_ym); MIN_YM <- min(uni$hold_ym)
wf("[base] R36 uni 상속: rows=%d months=%d tickers=%d | production_parity_verified PORT_t=%.3f | pin=%s (mtime=%s) | 관측창=[%d,%d]",
   nrow(uni), uniqueN(uni$hold_ym), uniqueN(uni$Ticker), BASE_PARITY, RAW_P, PIN_MTIME, MIN_YM, MAX_YM)

## --- AUX: INS_MAGQ3 (WT-007 패널) → WT-007 AST 그대로 CS_WINSORIZE(3sd)+CS_ZSCORE ---
## run_wt007_eval.R::cs_z 산식 그대로 (by=Date → by=sig_ym 만 치환). 자체 재정의 금지.
PAN <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_007/insider_axes_panel.parquet"))
cs_z <- function(dt, col, orient = +1) {
  d <- dt[is.finite(get(col)), .(sig_ym, Ticker, x = orient * get(col))]
  d[, {
    mu <- mean(x); s <- sd(x)
    if (!is.finite(s) || s <= 0) list(Ticker = Ticker, score = rep(NA_real_, .N))
    else {
      xw <- pmin(pmax(x, mu - 3 * s), mu + 3 * s); s2 <- sd(xw)
      if (!is.finite(s2) || s2 <= 0) list(Ticker = Ticker, score = rep(NA_real_, .N))
      else list(Ticker = Ticker, score = (xw - mean(xw)) / s2)
    }
  }, by = sig_ym][is.finite(score)]
}
MAGZ <- cs_z(PAN, "INS_MAGQ3", +1)
MAGZ[, hold_ym := ymshift(as.integer(sig_ym), 1L)]          # PIT: 신호월 m → 홀딩월 m+1 (C5)
BRZ  <- cs_z(PAN, "INS02_BREADTH6", +1); BRZ[, hold_ym := ymshift(as.integer(sig_ym), 1L)]
wf("[aux] INS_MAGQ3 z: %d행 %d월 (%s~%s) | 문턱 %.1f 초과 %d행",
   nrow(MAGZ), uniqueN(MAGZ$sig_ym), min(MAGZ$sig_ym), max(MAGZ$sig_ym), AUX_THR, sum(MAGZ$score >= AUX_THR))

uni <- merge(uni, MAGZ[, .(hold_ym, Ticker, magq3 = score)], by = c("hold_ym", "Ticker"), all.x = TRUE)
uni <- merge(uni, BRZ[,  .(hold_ym, Ticker, br6_panel_z = score)], by = c("hold_ym", "Ticker"), all.x = TRUE)
setorder(uni, Ticker, hold_ym)

## --- 소스 정합 감사: live ramp INS02 z vs WT-007 패널 INS02 z (동일 원천이어야) ---
pz <- uni[!is.na(INS02_OffBuyBreadth6m) & !is.na(br6_panel_z)]
sp <- pz[, .(r = suppressWarnings(cor(INS02_OffBuyBreadth6m, br6_panel_z, method = "spearman")), n = .N), by = hold_ym][n >= 10]
flag_agree <- pz[, mean(mk_flag(INS02_OffBuyBreadth6m, A_THR) == mk_flag(br6_panel_z, A_THR))]
wf("[parity] ramp INS02 z ↔ WT007 패널 INS02 z: 월별 Spearman mean=%.4f min=%.4f (mo=%d) | flag 일치율=%.4f (n=%d)",
   mean(sp$r, na.rm = TRUE), min(sp$r, na.rm = TRUE), nrow(sp), flag_agree, nrow(pz))

## --- IT-2 돌연변이(문턱): 실데이터에서 문턱을 깨면 flag 집합이 반드시 변해야 ---
z_real <- uni$magq3
n1 <- sum(mk_flag(z_real, AUX_THR)); n0 <- sum(mk_flag(z_real, 0.5)); nInf <- sum(mk_flag(z_real, Inf))
INJ$IT2 <- list(n_at_thr = n1, n_at_mutant_0p5 = n0, n_at_inf = nInf,
                changed = (n0 != n1) && (nInf == 0L) && (n1 > 0L))
if (!INJ$IT2$changed)
  stop(sprintf("[INJECT] IT-2 문턱 돌연변이 FAIL — thr=1.0:%d thr=0.5:%d thr=Inf:%d (비교 사망 또는 z 퇴화)", n1, n0, nInf))
wf("[INJECT] IT-2 문턱 돌연변이 실데이터: thr=1.0→%d flag / thr=0.5→%d / thr=Inf→%d : 변화 확인 PASS", n1, n0, nInf)

## ============================================================================
## 3. flag / 4분할 그룹 / 상태기계 (A, A′)
## ============================================================================
uni[, cov_a := !is.na(INS02_OffBuyBreadth6m)]
uni[, cov_b := !is.na(magq3)]
uni[, a := mk_flag(INS02_OffBuyBreadth6m, A_THR)]     # A: live tripwire
uni[, b := mk_flag(magq3, AUX_THR)]                    # AUX: INS_MAGQ3 보조축
uni[, on_A  := a]
uni[, on_Ap := as.integer(a == 1L | b == 1L)]          # primary form = union (사전등록)
uni[, on_AND := as.integer(a == 1L & b == 1L)]         # 대조 기록 전용 (no-flip)
uni[, cov_Ap := cov_a | cov_b]

uni[, grp4 := fifelse(!(cov_a | cov_b), NA_character_,
              fifelse(a == 1L & b == 1L, "BOTH",
              fifelse(a == 1L & b == 0L, "A_ONLY",
              fifelse(a == 0L & b == 1L, "MAG_ONLY", "NEITHER"))))]
uni[, safe_side := fifelse(is.na(grp4), NA_character_,
                   fifelse(grp4 %in% c("BOTH", "A_ONLY"), "A_SAFE", grp4))]  # A-SAFE 합집합 (동질성 대조군)

SA  <- build_states(uni, "on_A",  "cov_a")[,  .(hold_ym, Ticker, state_A = state)]
SAP <- build_states(uni, "on_Ap", "cov_Ap")[, .(hold_ym, Ticker, state_Ap = state)]
uni <- merge(uni, SA,  by = c("hold_ym", "Ticker"), all.x = TRUE)
uni <- merge(uni, SAP, by = c("hold_ym", "Ticker"), all.x = TRUE)

## ============================================================================
## 4. D1 — 커버리지 변화 (i)
## ============================================================================
cov_row <- function(DT, lab) {
  data.table(slice = lab,
    covered_nm    = DT[cov_a | cov_b, .N],
    covered_A     = DT[cov_a == TRUE, .N],
    covered_Ap    = DT[cov_a | cov_b, .N],
    safe_A        = DT[a == 1L, .N],
    safe_Ap       = DT[on_Ap == 1L, .N],
    safe_MAG_only = DT[a == 0L & b == 1L, .N],
    safe_AND      = DT[on_AND == 1L, .N],
    months_A      = DT[a == 1L, uniqueN(hold_ym)],
    months_Ap     = DT[on_Ap == 1L, uniqueN(hold_ym)],
    tickers_A     = DT[a == 1L, uniqueN(Ticker)],
    tickers_Ap    = DT[on_Ap == 1L, uniqueN(Ticker)])
}
COV <- rbindlist(list(cov_row(uni, "ALL"), cov_row(uni[sz_tercile == "mid"], "MID_habitat"),
                      cov_row(uni[megatier == "TOP30"], "MEGA_TOP30"), cov_row(uni[megatier == "REST"], "REST")))
COV[, `:=`(safe_delta_pct = 100 * (safe_Ap - safe_A) / pmax(safe_A, 1L),
           cov_delta_pct  = 100 * (covered_Ap - covered_A) / pmax(covered_A, 1L))]
w("\n────── D1 커버리지 변화 (A = INS02 z>=1.0 / A′ = A ∪ MAGQ3 z>=1.0) ──────")
for (i in seq_len(nrow(COV))) { r <- COV[i]
  wf("   %-12s covered %d→%d (%+.1f%%) | SAFE %d→%d (%+.1f%%) | MAG_ONLY 신규 %d | 감시월 %d→%d | 종목 %d→%d",
     r$slice, r$covered_A, r$covered_Ap, r$cov_delta_pct, r$safe_A, r$safe_Ap, r$safe_delta_pct,
     r$safe_MAG_only, r$months_A, r$months_Ap, r$tickers_A, r$tickers_Ap) }
mo_names <- uni[, .(nA = sum(a == 1L), nAp = sum(on_Ap == 1L), nMO = sum(a == 0L & b == 1L)), by = hold_ym][order(hold_ym)]
wf("   월평균 SAFE 이름수: A=%.1f → A′=%.1f (MAG_ONLY 신규 %.1f/월) | 전체 %d개월",
   mean(mo_names$nA), mean(mo_names$nAp), mean(mo_names$nMO), nrow(mo_names))

## ============================================================================
## 5. D2 — primary: R38-스타일 월별-paired (SUSTAIN vs OFF), A / A′
## ============================================================================
## R38 paired_vs_off 산식 그대로 (그룹 컬럼만 일반화)
paired_grp <- function(DT, grpcol, target, ref, basis = "Ret_1m") {
  d <- DT[get(grpcol) %in% c(target, ref)]
  if (!nrow(d)) return(list(target = target, ref = ref, basis = basis, gap_ann = NA, gap_t = NA,
                            se = NA, n_months = 0L, avg_target_mo = NA, avg_ref_mo = NA, series = numeric(0), months = integer(0)))
  g <- d[, .(m_s = mean(get(basis)[get(grpcol) == target], na.rm = TRUE),
             m_r = mean(get(basis)[get(grpcol) == ref],    na.rm = TRUE),
             ns  = sum(get(grpcol) == target), nr = sum(get(grpcol) == ref)), by = hold_ym][ns > 0 & nr > 0]
  if (!nrow(g)) return(list(target = target, ref = ref, basis = basis, gap_ann = NA, gap_t = NA,
                            se = NA, n_months = 0L, avg_target_mo = NA, avg_ref_mo = NA, series = numeric(0), months = integer(0)))
  fit <- nw_fit(g$m_s - g$m_r)
  list(target = target, ref = ref, basis = basis, gap_ann = fit$mean * 12, gap_t = fit$t, se = fit$se,
       n_months = fit$n, avg_target_mo = mean(g$ns), avg_ref_mo = mean(g$nr),
       series = g$m_s - g$m_r, months = g$hold_ym)
}
prs <- function(x) sprintf("gap_ann=%+.4f t=%+.2f (mo=%d, %.1f names/mo)", x$gap_ann, x$gap_t, x$n_months, x$avg_target_mo)

MIDH <- uni[sz_tercile == "mid"]                 # R38 동일 habitat
D2 <- list()
for (sc in c("A", "Ap")) {
  col <- paste0("state_", sc)
  D2[[sc]] <- list(
    SUSTAIN = paired_grp(MIDH, col, "SUSTAIN", "OFF", "Ret_1m"),
    ENTRY   = paired_grp(MIDH, col, "ENTRY",   "OFF", "Ret_1m"),
    EXIT    = paired_grp(MIDH, col, "EXIT",    "OFF", "Ret_1m"),
    SUSTAIN_exc = paired_grp(MIDH, col, "SUSTAIN", "OFF", "exc"))
}
w("\n────── D2 primary: R38-스타일 월별-paired NW lag-3 (MID habitat, basis=Ret_1m) ──────")
for (sc in c("A", "Ap")) { lab <- if (sc == "A") "A (현행 INS02)" else "A′ (INS02 ∪ MAGQ3)"
  wf("   [%s] SUSTAIN vs OFF: %s | ENTRY %s | EXIT %s", lab,
     prs(D2[[sc]]$SUSTAIN), prs(D2[[sc]]$ENTRY), prs(D2[[sc]]$EXIT)) }
stc <- function(col) { x <- MIDH[!is.na(get(col)), .N, by = c(col)]; setnames(x, col, "state"); x[order(state)] }
wf("   상태분포 MID: A={%s} / A′={%s}",
   paste(sprintf("%s=%d", stc("state_A")$state, stc("state_A")$N), collapse=" "),
   paste(sprintf("%s=%d", stc("state_Ap")$state, stc("state_Ap")$N), collapse=" "))

## ============================================================================
## 6. D3/D4 — 증분 판정: 4분할 그룹 + R40-identical risk metrics + 동질성
## ============================================================================
grp_summary <- function(DT) {
  DT[!is.na(grp4), {
    rm_ <- risk_metrics(Ret_1m)
    .(n_obs = .N, n_months = uniqueN(hold_ym), mean_fwd = rm_$mean, mean_exc = mean(exc, na.rm = TRUE),
      downside = rm_$downside, tail_hit = rm_$tail, vol = rm_$vol, min = rm_$min,
      win_rate = mean(Ret_1m > 0, na.rm = TRUE))
  }, by = grp4][order(match(grp4, c("NEITHER", "A_ONLY", "BOTH", "MAG_ONLY")))]
}
GS_all <- grp_summary(uni); GS_mid <- grp_summary(MIDH)
w("\n────── D3 4분할 그룹 요약 (R40-identical: downside=mean(r|r<0) · tail=mean(r<-15%) · vol=sd) ──────")
w("[ALL]"); for (i in seq_len(nrow(GS_all))) { r <- GS_all[i]
  wf("   %-9s n=%6d mo=%3d fwd=%+.4f exc=%+.4f downside=%+.4f tail=%.3f vol=%.4f win=%.3f",
     r$grp4, r$n_obs, r$n_months, r$mean_fwd, r$mean_exc, r$downside, r$tail_hit, r$vol, r$win_rate) }
w("[MID habitat]"); for (i in seq_len(nrow(GS_mid))) { r <- GS_mid[i]
  wf("   %-9s n=%6d mo=%3d fwd=%+.4f exc=%+.4f downside=%+.4f tail=%.3f vol=%.4f win=%.3f",
     r$grp4, r$n_obs, r$n_months, r$mean_fwd, r$mean_exc, r$downside, r$tail_hit, r$vol, r$win_rate) }

D3 <- list(); for (g in c("A_ONLY", "BOTH", "MAG_ONLY")) {
  D3[[g]] <- list(mid_ret = paired_grp(MIDH, "grp4", g, "NEITHER", "Ret_1m"),
                  mid_exc = paired_grp(MIDH, "grp4", g, "NEITHER", "exc"),
                  all_ret = paired_grp(uni,  "grp4", g, "NEITHER", "Ret_1m")) }
w("\n────── D3 월별-paired vs NEITHER (증분 검정) ──────")
for (g in names(D3)) wf("   %-9s MID raw %s | MID exc %s | ALL raw %s",
   g, prs(D3[[g]]$mid_ret), prs(D3[[g]]$mid_exc), prs(D3[[g]]$all_ret))
## D4 동질성: MAG_ONLY vs A_SAFE(BOTH∪A_ONLY)
D4 <- list(mid_ret = paired_grp(MIDH, "safe_side", "MAG_ONLY", "A_SAFE", "Ret_1m"),
           mid_exc = paired_grp(MIDH, "safe_side", "MAG_ONLY", "A_SAFE", "exc"),
           all_ret = paired_grp(uni,  "safe_side", "MAG_ONLY", "A_SAFE", "Ret_1m"))
wf("\n[D4 동질성] MAG_ONLY vs A_SAFE: MID raw %s | MID exc %s | ALL raw %s",
   prs(D4$mid_ret), prs(D4$mid_exc), prs(D4$all_ret))

## ============================================================================
## 7. D5 — tier 분해 (megatier TOP30 vs REST, R37 정합)
## ============================================================================
D5 <- list()
for (tg in c("TOP30", "REST")) {
  T_ <- uni[megatier == tg]
  D5[[tg]] <- list(
    grp = grp_summary(T_),
    MAG_ONLY = paired_grp(T_, "grp4", "MAG_ONLY", "NEITHER", "Ret_1m"),
    A_SAFE   = paired_grp(T_, "safe_side", "A_SAFE", "NEITHER", "Ret_1m"),
    SUSTAIN_Ap = paired_grp(T_, "state_Ap", "SUSTAIN", "OFF", "Ret_1m"),
    SUSTAIN_A  = paired_grp(T_, "state_A",  "SUSTAIN", "OFF", "Ret_1m"))
}
w("\n────── D5 tier 분해 (R37: MEGA_TOP30 저신뢰 / REST=MID_OTHER 강건) ──────")
for (tg in c("TOP30", "REST")) wf("   [%s] MAG_ONLY vs NEITHER %s | A_SAFE vs NEITHER %s | SUSTAIN(A) %s | SUSTAIN(A′) %s",
   tg, prs(D5[[tg]]$MAG_ONLY), prs(D5[[tg]]$A_SAFE), prs(D5[[tg]]$SUSTAIN_A), prs(D5[[tg]]$SUSTAIN_Ap))

## ============================================================================
## 8. D6 — lag1 스트레스 (동월누출 배제)
## ============================================================================
uL <- copy(uni[!is.na(grp4), .(hold_ym = ymshift(hold_ym, 1L), Ticker, grp4_lag = grp4, ss_lag = safe_side)])
uJ <- merge(uni[, .(hold_ym, Ticker, Ret_1m, exc, sz_tercile, megatier)], uL, by = c("hold_ym", "Ticker"))
uJ[, grp4 := grp4_lag]; uJ[, safe_side := ss_lag]
D6 <- list(MAG_ONLY_mid = paired_grp(uJ[sz_tercile == "mid"], "grp4", "MAG_ONLY", "NEITHER", "Ret_1m"),
           A_SAFE_mid   = paired_grp(uJ[sz_tercile == "mid"], "safe_side", "A_SAFE", "NEITHER", "Ret_1m"))
wf("\n[D6 lag1] MAG_ONLY vs NEITHER t=%+.2f (base %+.2f) | A_SAFE vs NEITHER t=%+.2f (base %+.2f) — 붕괴 시 동월누출 의심",
   D6$MAG_ONLY_mid$gap_t, D3$MAG_ONLY$mid_ret$gap_t, D6$A_SAFE_mid$gap_t,
   paired_grp(MIDH, "safe_side", "A_SAFE", "NEITHER", "Ret_1m")$gap_t)

## ============================================================================
## 9. D7 — 검열/생존 편향 (R40 프레임)
## ============================================================================
rw <- as.data.table(read_parquet(RAW_P, col_select = c("Date","Ticker","Ret","Close","Vol","K200","KQ150","AdminStock","TradingHalt","UnfaithfulDisc")))
rw <- rw[Date >= as.Date("2004-06-01")]; rw[, ym := as.integer(format(Date, "%Y%m"))]
rmon <- rw[, .(ret_m = prod(1 + Ret, na.rm = TRUE) - 1, n_days = .N, adv_m = mean(Close * Vol, na.rm = TRUE),
               k200 = as.integer(any(K200 == 1, na.rm = TRUE)), kq150 = as.integer(any(KQ150 == 1, na.rm = TRUE)),
               admin = as.integer(any(AdminStock == 1, na.rm = TRUE)), halt = as.integer(any(TradingHalt == 1, na.rm = TRUE)),
               unfaith = as.integer(any(UnfaithfulDisc == 1, na.rm = TRUE))), by = .(Ticker, ym)]
rm(rw); invisible(gc(verbose = FALSE))
setkey(rmon, Ticker, ym); tick_last <- rmon[, .(last_ym = max(ym)), by = Ticker]; setkey(tick_last, Ticker)
wf("\n[rmon] pin 월간 패널: rows=%d ym=[%d,%d] tickers=%d", nrow(rmon), min(rmon$ym), max(rmon$ym), uniqueN(rmon$Ticker))

uni_key <- unique(uni[, .(Ticker, hold_ym)]); uni_key[, in_uni := 1L]
## ★terminal right-truncation 제외 (R40 GUARD): hold_ym==MAX_YM 은 j1 관측 불가
EV <- uni[!is.na(grp4) & hold_ym < MAX_YM, .(Ticker, hold_ym, grp4, sz_tercile, megatier, Ret_1m)]
EV[, j1 := ymshift(hold_ym, 1L)]
EV <- merge(EV, uni_key[, .(Ticker, hold_ym, in_uni_next = in_uni)], by.x = c("Ticker","j1"), by.y = c("Ticker","hold_ym"), all.x = TRUE)
EV <- merge(EV, rmon[, .(Ticker, ym, ret_m_n = ret_m, adv_m_n = adv_m, k200_n = k200, kq150_n = kq150,
                         admin_n = admin, halt_n = halt)], by.x = c("Ticker","j1"), by.y = c("Ticker","ym"), all.x = TRUE)
EV <- merge(EV, tick_last, by = "Ticker", all.x = TRUE)
EV[, left_uni  := as.integer(is.na(in_uni_next))]
EV[, delisted  := as.integer(is.na(in_uni_next) & is.na(ret_m_n) & (last_ym <= hold_ym))]
EV[, distress  := as.integer(is.na(in_uni_next) & !is.na(admin_n) & (admin_n == 1L | halt_n == 1L))]
EV[, catastrophic := as.integer(delisted == 1L | distress == 1L)]
cens_tab <- function(DT) DT[, .(n = .N, left_uni_rate = mean(left_uni), delist_rate = mean(delisted),
                                catastrophic_rate = mean(catastrophic)), by = grp4][order(grp4)]
CEN_all <- cens_tab(EV); CEN_mid <- cens_tab(EV[sz_tercile == "mid"])
w("\n────── D7 검열/생존 census (R40 프레임, terminal right-truncation 제외) ──────")
w("[ALL]"); for (i in seq_len(nrow(CEN_all))) { r <- CEN_all[i]
  wf("   %-9s n=%6d uni이탈=%.3f%% 진성폐지=%.4f%% catastrophic=%.4f%%", r$grp4, r$n, 100*r$left_uni_rate, 100*r$delist_rate, 100*r$catastrophic_rate) }
w("[MID]"); for (i in seq_len(nrow(CEN_mid))) { r <- CEN_mid[i]
  wf("   %-9s n=%6d uni이탈=%.3f%% 진성폐지=%.4f%% catastrophic=%.4f%%", r$grp4, r$n, 100*r$left_uni_rate, 100*r$delist_rate, 100*r$catastrophic_rate) }
prop_2 <- function(DT, gA, gB, col) {
  x <- c(sum(DT[grp4 == gA][[col]]), sum(DT[grp4 == gB][[col]])); n <- c(DT[grp4 == gA, .N], DT[grp4 == gB, .N])
  if (any(n == 0)) return(list(p = NA_real_, x = x, n = n))
  pt <- suppressWarnings(prop.test(x, n)); list(p = as.numeric(pt$p.value), x = x, n = n) }
DC <- list(mid_left = prop_2(EV[sz_tercile == "mid"], "MAG_ONLY", "NEITHER", "left_uni"),
           mid_delist = prop_2(EV[sz_tercile == "mid"], "MAG_ONLY", "NEITHER", "delisted"),
           mid_cat = prop_2(EV[sz_tercile == "mid"], "MAG_ONLY", "NEITHER", "catastrophic"))
wf("[차등검열 MID] MAG_ONLY vs NEITHER: uni이탈 p=%.3f (%d/%d vs %d/%d) | 진성폐지 p=%.3f | catastrophic p=%.3f",
   DC$mid_left$p, DC$mid_left$x[1], DC$mid_left$n[1], DC$mid_left$x[2], DC$mid_left$n[2], DC$mid_delist$p, DC$mid_cat$p)
## worst-case: MAG_ONLY 의 진성폐지 name-month 에 -100% 대입 후 risk 재산출
wc_grp <- function(g) { r <- EV[sz_tercile == "mid" & grp4 == g, Ret_1m]
  d <- EV[sz_tercile == "mid" & grp4 == g & delisted == 1L, .N]
  risk_metrics(c(r[is.finite(r)], rep(-1.0, d))) }
WC <- list(MAG_ONLY_actual = risk_metrics(EV[sz_tercile == "mid" & grp4 == "MAG_ONLY", Ret_1m]),
           MAG_ONLY_wipeout = wc_grp("MAG_ONLY"),
           NEITHER_actual = risk_metrics(EV[sz_tercile == "mid" & grp4 == "NEITHER", Ret_1m]))
wf("[worst-case MID] MAG_ONLY 실측 downside=%+.4f tail=%.4f → 진성폐지 -100%% 대입 downside=%+.4f tail=%.4f | NEITHER downside=%+.4f tail=%.4f",
   WC$MAG_ONLY_actual$downside, WC$MAG_ONLY_actual$tail, WC$MAG_ONLY_wipeout$downside, WC$MAG_ONLY_wipeout$tail,
   WC$NEITHER_actual$downside, WC$NEITHER_actual$tail)

## ============================================================================
## 10. 판정 (사전등록 결정규칙 기계 적용 — 사후 조정 금지)
## ============================================================================
mo_stat <- MIDH[grp4 == "MAG_ONLY", .(n = .N), by = hold_ym]
mo_n_months <- nrow(mo_stat); mo_avg_names <- if (mo_n_months) mean(mo_stat$n) else 0
t_inc <- D3$MAG_ONLY$mid_ret$gap_t
g_mo  <- GS_mid[grp4 == "MAG_ONLY"]; g_ne <- GS_mid[grp4 == "NEITHER"]
underpowered <- (mo_n_months < 60L) || (mo_avg_names < 3)
adverse   <- (is.finite(t_inc) && t_inc <= -2.0) || (is.finite(g_mo$tail_hit) && g_mo$tail_hit > g_ne$tail_hit * 1.25)
valid_ret <- is.finite(t_inc) && t_inc >= 2.0
risk_only <- is.finite(t_inc) && abs(t_inc) < 2.0 &&
             is.finite(g_mo$downside) && g_mo$downside >= g_ne$downside && g_mo$tail_hit <= g_ne$tail_hit
increment_verdict <- if (underpowered) "UNDERPOWERED" else if (adverse) "INCREMENT_ADVERSE" else
  if (valid_ret) "INCREMENT_VALID_RETURN" else if (risk_only) "INCREMENT_RISK_ONLY" else "INCREMENT_NULL"
t_hom <- D4$mid_ret$gap_t
homogeneity <- if (!is.finite(t_hom)) "UNDETERMINED" else if (abs(t_hom) < 2.0) "HOMOGENEOUS_WITH_A_SAFE" else
  if (t_hom <= -2.0) "INFERIOR_TO_A_SAFE" else "SUPERIOR_TO_A_SAFE"
rest_ok <- is.finite(D5$REST$MAG_ONLY$gap_t) && D5$REST$MAG_ONLY$gap_t >= 2.0
wiring_recommended <- (increment_verdict %in% c("INCREMENT_VALID_RETURN", "INCREMENT_RISK_ONLY")) && rest_ok
w("\n────── 판정 (사전등록 결정규칙 기계 적용) ──────")
wf("[power] MAG_ONLY MID: n_months=%d (floor 60) 월평균 이름수=%.2f (floor 3) → underpowered=%s", mo_n_months, mo_avg_names, underpowered)
wf("[return] t_inc(MAG_ONLY vs NEITHER, MID, Ret_1m)=%+.3f | [risk] downside %+.4f vs NEITHER %+.4f | tail %.4f vs %.4f (hangover 문턱 %.4f)",
   t_inc, g_mo$downside, g_ne$downside, g_mo$tail_hit, g_ne$tail_hit, g_ne$tail_hit * 1.25)
wf("[verdict] increment=%s | homogeneity(t=%+.2f)=%s | REST tier t=%+.2f → 배선 제안 자격=%s",
   increment_verdict, t_hom, homogeneity, D5$REST$MAG_ONLY$gap_t, wiring_recommended)

## ============================================================================
## 11. 저장
## ============================================================================
ser <- data.table(hold_ym = D3$MAG_ONLY$mid_ret$months, gap_mag_only = D3$MAG_ONLY$mid_ret$series)
a_ser <- data.table(hold_ym = paired_grp(MIDH, "safe_side", "A_SAFE", "NEITHER", "Ret_1m")$months,
                    gap_a_safe = paired_grp(MIDH, "safe_side", "A_SAFE", "NEITHER", "Ret_1m")$series)
SER <- merge(ser, a_ser, by = "hold_ym", all = TRUE)
write_parquet(SER, file.path(OUT, "r43_paired_series_mid.parquet"))
write_parquet(GS_mid, file.path(OUT, "r43_group_summary_mid.parquet"))
write_parquet(GS_all, file.path(OUT, "r43_group_summary_all.parquet"))
write_parquet(COV, file.path(OUT, "r43_coverage.parquet"))
write_parquet(mo_names, file.path(OUT, "r43_monthly_names.parquet"))
write_parquet(CEN_mid, file.path(OUT, "r43_censoring_mid.parquet"))
saveRDS(list(uni_slim = uni[, .(hold_ym, Ticker, sz_tercile, megatier, a, b, grp4, safe_side, state_A, state_Ap, Ret_1m, exc)],
             GS_all = GS_all, GS_mid = GS_mid, COV = COV, D2 = D2, D3 = D3, D4 = D4, D5 = D5, D6 = D6,
             CEN_all = CEN_all, CEN_mid = CEN_mid, DC = DC, WC = WC, INJ = INJ, mo_names = mo_names),
        file.path(OUT, "_r43_objects.rds"))

fmt_p <- function(x) list(gap_ann = round(x$gap_ann, 5), gap_t = round(x$gap_t, 3), n_months = x$n_months,
                          avg_target_mo = round(x$avg_target_mo, 2), avg_ref_mo = round(x$avg_ref_mo, 2))
res <- list(
  wt = "WT-D20260802_012", round = "R43", prereg_hash = PRE_HASH,
  claim_scope = "monitoring 진단 (per-holding 안전 특성화) — 자본 아님. book_state 무변경.",
  base = list(source = RDS, production_parity_verified_port_t = BASE_PARITY, vintage_pin = RAW_P, pin_mtime = PIN_MTIME,
              n_rows = nrow(uni), n_months = uniqueN(uni$hold_ym), obs_window = c(MIN_YM, MAX_YM)),
  source_parity = list(spearman_mean = round(mean(sp$r, na.rm = TRUE), 5), spearman_min = round(min(sp$r, na.rm = TRUE), 5),
                       n_months = nrow(sp), flag_agreement = round(flag_agree, 5), n_rows = nrow(pz),
                       note = "live ramp INS02 z 와 WT-007 패널 INS02 z 가 동일 원천임을 실측 확인 — A/A′ 는 같은 substrate 위 비교"),
  injection_tests = INJ,
  D1_coverage = list(table = lapply(seq_len(nrow(COV)), function(i) as.list(COV[i])),
                     monthly_avg_names = list(A = round(mean(mo_names$nA), 2), Ap = round(mean(mo_names$nAp), 2),
                                              MAG_ONLY = round(mean(mo_names$nMO), 2), n_months = nrow(mo_names))),
  D2_state_machine = list(
    A  = list(SUSTAIN_vs_OFF = fmt_p(D2$A$SUSTAIN), ENTRY_vs_OFF = fmt_p(D2$A$ENTRY), EXIT_vs_OFF = fmt_p(D2$A$EXIT),
              SUSTAIN_vs_OFF_exc = fmt_p(D2$A$SUSTAIN_exc)),
    Ap = list(SUSTAIN_vs_OFF = fmt_p(D2$Ap$SUSTAIN), ENTRY_vs_OFF = fmt_p(D2$Ap$ENTRY), EXIT_vs_OFF = fmt_p(D2$Ap$EXIT),
              SUSTAIN_vs_OFF_exc = fmt_p(D2$Ap$SUSTAIN_exc)),
    state_counts_mid = list(A = setNames(as.list(stc("state_A")$N), stc("state_A")$state),
                            Ap = setNames(as.list(stc("state_Ap")$N), stc("state_Ap")$state))),
  D3_group_summary = list(all = lapply(seq_len(nrow(GS_all)), function(i) as.list(GS_all[i])),
                          mid = lapply(seq_len(nrow(GS_mid)), function(i) as.list(GS_mid[i])),
                          paired_vs_NEITHER = lapply(D3, function(x) list(mid_ret = fmt_p(x$mid_ret), mid_exc = fmt_p(x$mid_exc), all_ret = fmt_p(x$all_ret)))),
  D4_homogeneity = list(mid_ret = fmt_p(D4$mid_ret), mid_exc = fmt_p(D4$mid_exc), all_ret = fmt_p(D4$all_ret), verdict = homogeneity),
  D5_tier = lapply(D5, function(x) list(MAG_ONLY_vs_NEITHER = fmt_p(x$MAG_ONLY), A_SAFE_vs_NEITHER = fmt_p(x$A_SAFE),
                                        SUSTAIN_A_vs_OFF = fmt_p(x$SUSTAIN_A), SUSTAIN_Ap_vs_OFF = fmt_p(x$SUSTAIN_Ap),
                                        groups = lapply(seq_len(nrow(x$grp)), function(i) as.list(x$grp[i])))),
  D6_lag1 = list(MAG_ONLY_mid_t = round(D6$MAG_ONLY_mid$gap_t, 3), base_t = round(D3$MAG_ONLY$mid_ret$gap_t, 3),
                 A_SAFE_mid_t = round(D6$A_SAFE_mid$gap_t, 3)),
  D7_censoring = list(all = lapply(seq_len(nrow(CEN_all)), function(i) as.list(CEN_all[i])),
                      mid = lapply(seq_len(nrow(CEN_mid)), function(i) as.list(CEN_mid[i])),
                      differential = lapply(DC, function(x) list(p = round(x$p, 4), x = x$x, n = x$n)),
                      worst_case = WC,
                      right_truncation_excluded_ym = MAX_YM),
  verdict = list(increment = increment_verdict, homogeneity = homogeneity,
                 t_inc = round(t_inc, 3), t_homogeneity = round(t_hom, 3),
                 underpowered = underpowered, adverse = adverse, valid_return = valid_ret, risk_only = risk_only,
                 rest_tier_t = round(D5$REST$MAG_ONLY$gap_t, 3), wiring_recommended = wiring_recommended,
                 n_months_mag_only = mo_n_months, avg_names_mag_only = round(mo_avg_names, 2)),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
write_json(res, file.path(OUT, "r43_results.json"), auto_unbox = TRUE, pretty = TRUE, digits = 5, na = "null")
wf("\nR43_DONE | increment=%s homogeneity=%s | t_inc=%+.2f t_hom=%+.2f | SAFE %d→%d name-months | wiring_recommended=%s",
   increment_verdict, homogeneity, t_inc, t_hom, COV[slice == "ALL", safe_A], COV[slice == "ALL", safe_Ap], wiring_recommended)
cat("[SAVED]", file.path(OUT, "r43_results.json"), "\n")
