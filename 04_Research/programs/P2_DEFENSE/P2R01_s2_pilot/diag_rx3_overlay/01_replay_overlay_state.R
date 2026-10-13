#!/usr/bin/env Rscript
#==============================================================================
# 01_replay_overlay_state.R — P2R01_RX3(trend_persist_tilt) 오버레이 상태 경로 재도출 · 진단 전용
#
# 무엇: 측정 시점 엔진(rf_cell_engine.R @ REV)의 오버레이 블록(§5.5)을 **그 코드 그대로** 평가해
#       시그널일별 상태(r252 → 연속 길이 run → 분위 q → 개입 강도 g)와 종목별 노출을 얻고,
#       측정 산출물(RX3 · RX0 의 04_holdings.csv)과 대조한다. 상태 함수는 엔진이 쓰는 arm 파일 그대로 호출한다.
# 입력: 측정과 같은 캐시 .cache/benchmark.parquet · .cache/RAWDATA.parquet(Date·Ticker·Close)를
#       τ_D(2022-12-31)에서 자른 것. 엔진 오버레이 계산은 전부 과거 창(확장창 · 후행 252일 · 누적합)이라
#       τ_D 이전 값은 절단 전과 같다(아래 V1 이 RX3 산출 비중과 대조해 확인한다).
#       사전 오버레이 PORTFOLIO = RX0(같은 사양 · 오버레이만 없음) 04_holdings 를 집행일 → 시그널일로 환원.
# 반사실(CF): 같은 arm 을 이력 기점만 BM 자료 시작(1990-01)으로 옮긴 H 에 호출 — 상태만(수익 합성 없음).
# 쓰기: 이 디렉터리 out/ 만. 코드 · 등록부 · 산출물 무수정. τ_D 이후 값은 계산 입력에서부터 없다.
# 실행(저장소 루트): QM_ROOT=<root> CLAUDE_PROJECT_DIR=<root> Rscript <this>
#==============================================================================
options(warn = 1, width = 220, datatable.print.nrows = 400)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
if (!identical(gsub("\\\\", "/", Sys.getenv("QM_ROOT")), ROOT)) stop("QM_ROOT 가 ", ROOT, " 이어야 한다")
TAU  <- as.Date("2022-12-31")
REV  <- "6e7e58884"   # RX3 측정(2026-10-13 17:50~18:03) 시점 HEAD — 엔진 최종 변경 커밋 642813208 과 내용 동일
DIAG <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R01_s2_pilot/diag_rx3_overlay")
OUTD <- file.path(DIAG, "out"); dir.create(OUTD, showWarnings = FALSE, recursive = TRUE)
RX3_DIR   <- file.path(ROOT, "stage_artifacts/replication/20261013_175043_25968")
RX0_DIR   <- file.path(ROOT, "stage_artifacts/replication/20261013_165251_20896")
SPEC_PATH <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R01_s2_pilot/specs/P2R01_RX3.json")
ENG_REL   <- "02_Infrastructure/reinforcement/rf_cell_engine.R"
say <- function(...) cat(sprintf(...), "\n", sep = "")

#── 0. 측정 시점 엔진 원문 · 파스(srcref 로 줄 번호 보존) ─────────────────────────────
eng_file <- file.path(tempdir(), sprintf("rf_cell_engine_%s.R", REV))
rc <- system2("git", c("-C", ROOT, "show", sprintf("%s:%s", REV, ENG_REL)), stdout = eng_file)
if (!identical(as.integer(rc), 0L) || !file.exists(eng_file)) stop("git show 실패: ", REV)
ex <- parse(eng_file, keep.source = TRUE, encoding = "UTF-8")
sr <- attr(ex, "srcref")
L1 <- vapply(sr, function(s) as.integer(s[1]), 1L); L2 <- vapply(sr, function(s) as.integer(s[3]), 1L)
run_top <- function(env, a, b) {
  idx <- which(L1 >= a & L2 <= b)
  if (!length(idx)) stop(sprintf("엔진 %d-%d 에 문장이 없다", a, b))
  for (i in idx) eval(ex[[i]], envir = env)
  invisible(data.table(from = L1[idx], to = L2[idx]))
}
is_ov_block <- function(e) is.call(e) && identical(e[[1]], as.name("if")) &&
  grepl(".ov_kind, \"none\"", paste(deparse(e[[2]]), collapse = ""), fixed = TRUE)
ov_i <- which(vapply(ex, is_ov_block, logical(1)))
if (length(ov_i) != 1L) stop("오버레이 블록을 하나로 특정하지 못했다")
say("[engine@%s] 오버레이 블록 = %s:%d-%d", REV, ENG_REL, L1[ov_i], L2[ov_i])
# 작업 트리 판과 블록 동일성(작업 트리는 이후 MC5 편집 중 — 줄만 이동했는지 확인)
same_wt <- tryCatch({
  ex_wt <- parse(file.path(ROOT, ENG_REL), keep.source = FALSE, encoding = "UTF-8")
  ov_wt <- which(vapply(ex_wt, is_ov_block, logical(1)))
  identical(deparse(ex[[ov_i]], control = NULL), deparse(ex_wt[[ov_wt]], control = NULL))
}, error = function(e) paste("판독 불가:", conditionMessage(e)))
say("[engine] 작업 트리 오버레이 블록과 내용 동일: %s", as.character(same_wt))
blk  <- ex[[ov_i]][[3]]
bsr  <- attr(blk, "srcref")
bst  <- as.list(blk)[-1]; bL1 <- vapply(bsr[-1], function(s) as.integer(s[1]), 1L); bL2 <- vapply(bsr[-1], function(s) as.integer(s[3]), 1L)
run_blk <- function(env, a, b, skip = integer(0)) {
  idx <- which(bL1 >= a & bL2 <= b & !(bL1 %in% skip))
  if (!length(idx)) stop(sprintf("블록 %d-%d 에 문장이 없다", a, b))
  for (i in idx) eval(bst[[i]], envir = env)
  invisible(data.table(from = bL1[idx], to = bL2[idx]))
}

#── 1. 엔진 환경 — 측정과 같은 머리 문장 ─────────────────────────────────────────────
Sys.setenv(RF_CELL_SPEC = SPEC_PATH)          # 이 프로세스 한정(엔진 32행이 읽는다)
E <- new.env(parent = globalenv())
run_top(E, 27, 38)                             # library · %||% · .RF_ROOT · SPEC · .AX · .N_MAX
run_top(E, 62, 63)                             # .LIQ_MIN · .START
# ★블록이 실행 중 source/parse 하는 파일 3개도 REV 판으로 고정한다(작업 트리는 이후 MC5 편집 중) —
#   임시 미러 디렉터리(세션 tempdir)에 git show 로 꺼내 .RF_ROOT 를 그쪽으로 돌린다. 데이터 경로는 이 스크립트가 따로 읽는다.
PIN <- file.path(tempdir(), paste0("pin_", REV))
for (rel in c("02_Infrastructure/validation/overlay_pit_guard.R",
              "02_Infrastructure/reinforcement/overlay_arms/trend_persist_tilt.R",
              "02_Infrastructure/backtest_harness.R")) {
  dir.create(dirname(file.path(PIN, rel)), recursive = TRUE, showWarnings = FALSE)
  rc <- system2("git", c("-C", ROOT, "show", sprintf("%s:%s", REV, rel)), stdout = file.path(PIN, rel))
  if (!identical(as.integer(rc), 0L)) stop("git show 실패: ", rel)
}
E$.RF_ROOT <- PIN
say("[pin] 블록 실행 파일(overlay_pit_guard · arm · backtest_harness) = %s 판 · 미러 %s", REV, PIN)
say("[spec] code=%s overlay.kind=%s arm_id=%s start_date=%s", E$SPEC$code, E$SPEC$overlay$kind,
    E$SPEC$overlay$arm_id, format(E$.START))

#── 2. 입력 — 측정 캐시를 τ_D 에서 절단 ──────────────────────────────────────────────
bm <- as.data.table(arrow::read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))
if (!inherits(bm$Date, "Date")) bm[, Date := as.Date(Date)]
say("[bm] benchmark.parquet %s ~ %s (%d행 · BM_Src %s) → τ_D 절단", min(bm$Date), max(bm$Date), nrow(bm),
    paste(unique(bm$BM_Src), collapse = ","))
E$BM_DT <- bm[Date <= TAU]
raw <- as.data.table(arrow::read_parquet(file.path(ROOT, ".cache/RAWDATA.parquet"),
                                         col_select = tidyselect::all_of(c("Date", "Ticker", "Close"))))
if (!inherits(raw$Date, "Date")) raw[, Date := as.Date(Date)]
say("[raw] RAWDATA.parquet %s ~ %s (%d행) → τ_D 절단", min(raw$Date), max(raw$Date), nrow(raw))
E$RAWDATA <- raw[Date <= TAU]; rm(raw); invisible(gc(verbose = FALSE))
run_top(E, 84, 86)                             # DT <- RAWDATA · Date · setorder
run_top(E, 196, 197)                           # .sig_dates (월말 거래일 · Date >= .START)
SIG <- E$.sig_dates
say("[sig] 시그널일 %d개 %s ~ %s", length(SIG), min(SIG), max(SIG))
ALLD <- sort(unique(E$DT$Date))

#── 3. 사전 오버레이 PORTFOLIO = RX0 보유(집행일 → 시그널일) ─────────────────────────
rd_hold <- function(dir) {
  h <- fread(file.path(dir, "04_holdings.csv"), select = c("date", "ticker", "target_weight"))
  h[, date := as.Date(date)]; h <- h[date <= TAU]
  h[, sig_date := SIG[findInterval(as.numeric(date) - 0.5, as.numeric(SIG))]]
  h
}
h0 <- rd_hold(RX0_DIR); h3 <- rd_hold(RX3_DIR)
gap <- unique(h0[, .(date, sig_date)])[, .(date, sig_date, k = match(date, ALLD) - match(sig_date, ALLD))]
if (any(is.na(gap$k)) || any(gap$k != 1L)) stop("집행일이 시그널일 다음 거래일이 아닌 행이 있다")
say("[hold] RX0 집행일 %d개(%s ~ %s) — 전부 시그널일 다음 거래일(close_t1) · RX0 Σw 범위 %.12f ~ %.12f",
    nrow(gap), min(gap$date), max(gap$date), min(h0[, sum(target_weight), by = date]$V1), max(h0[, sum(target_weight), by = date]$V1))
if (!all(h0$ticker %in% E$DT$Ticker)) stop("RX0 보유 종목 코드가 RAWDATA 와 안 맞는다")
E$PORTFOLIO <- h0[, .(Date = sig_date, Ticker = ticker, Weight = target_weight, Leg = "LONG")]

#── 4. 엔진 오버레이 블록 평가(576-609 층 해석 + 블록 전체) ─────────────────────────────
run_top(E, 576, 609)
say("[engine] 층 %s · n_min %s", paste(E$.OV_NAMES, collapse = "+"), "(블록 안 .n_min_of)")
eval(ex[[ov_i]], envir = E)                    # ← 측정과 같은 코드 경로(가드 · assert_overlay_pit 포함)
M <- copy(E$.M); N <- nrow(M)
say("[engine] .M %d행 %s ~ %s · .OV_NMIN=%d · .n_floor=%d", N, min(M$Date), max(M$Date), E$.OV_NMIN[1], E$.n_floor)

#── V1. 재평가 비중 = RX3 산출 비중? ──────────────────────────────────────────────────
cmp <- merge(E$PORTFOLIO[, .(sig_date = Date, ticker = Ticker, w_engine = Weight)],
             h3[, .(sig_date, ticker, w_rx3 = target_weight)], by = c("sig_date", "ticker"), all = TRUE)
v1_na <- cmp[is.na(w_engine) | is.na(w_rx3), .N]
v1_mx <- cmp[!is.na(w_engine) & !is.na(w_rx3), max(abs(w_engine - w_rx3))]
say("[V1] 재평가 PORTFOLIO vs RX3 04_holdings: 행 %d · 한쪽만 있는 행 %d · 최대 |Δw| %.3e", nrow(cmp), v1_na, v1_mx)
if (v1_na > 0L || v1_mx > 1e-10) stop("V1 실패 — 재평가가 측정과 다르다")

#── 5. 상태 함수 탐침 — 엔진 arm 함수를 그대로 부른다(보유 = 베타 0·1 두 탐침 종목) ─────────
fn <- E$.OV_FNS[[1]]
probe_g <- function(MM, t) {
  H <- MM[seq_len(t)]; H[t, fwd := NA_real_]                     # 엔진 781-782 와 같은 H
  ctx <- list(t = t, date = MM$Date[t], v_now = H$rv60[t], tgt = stats::median(H$rv60, na.rm = TRUE),
              n_min = 24L, strict = FALSE,
              hold = data.table(Date = MM$Date[t], Ticker = c("PROBE_LO", "PROBE_HI"), beta = c(0, 1),
                                dbeta = NA_real_, ovol = NA_real_, bcorr = NA_real_, n_obs = 1000L))
  e <- fn(H, t, ctx)
  if (is.data.frame(e)) (1 - e$e[e$Ticker == "PROBE_LO"]) / 0.25 else { stopifnot(isTRUE(all.equal(as.numeric(e), 1))); 0 }
}
g_probe <- vapply(seq_len(N), function(t) probe_g(M, t), numeric(1))

#── 6. 분해(arm 33-58 행의 산술 · 설명용 — 탐침 g 와 비트 대조) + 문턱 경로 ────────────────
decomp <- function(MM) {
  n <- nrow(MM); r <- suppressWarnings(as.numeric(MM$r252)); below <- is.finite(r) & r < 0
  run <- integer(n); acc <- 0L
  for (s in seq_len(n)) { acc <- if (isTRUE(below[s])) acc + 1L else 0L; run[s] <- acc }
  n_fin <- cumsum(is.finite(r)); n_hist <- cumsum(run > 0L)
  q <- rep(NA_real_, n); g <- numeric(n); med <- rep(NA_real_, n)
  kd <- rep(NA_integer_, n); kf <- rep(NA_integer_, n); n_prior <- integer(n)
  for (t in seq_len(n)) {
    hr <- run[seq_len(t)]; hr <- hr[hr > 0L]
    if (length(hr)) med[t] <- stats::median(hr)
    if (run[t] > 0L && length(hr)) q[t] <- stats::ecdf(hr)(run[t])           # 최소 표본 무시한 그림자 q
    if (n_fin[t] >= 24L && run[t] > 0L && length(hr) >= 24L) g[t] <- max(0, min(1, (q[t] - 0.5) / 0.5))
    # 문턱: 지금(또는 다음) 연속 구간이 몇 개월 이어져야 g>0 인가 — 이전 구간들의 값만 고정 분포로 두고
    #   현재 구간 값 1..k 가 분포에 함께 들어가는 arm 정의 그대로. q(k) 는 k 에 대해 비감소.
    st <- if (run[t] > 0L) t - run[t] + 1L else t + 1L
    prior <- run[seq_len(st - 1L)]; prior <- prior[prior > 0L]; np <- length(prior); n_prior[t] <- np
    k <- 1L; while ((sum(prior <= k) + k) / (np + k) <= 0.5) k <- k + 1L
    kd[t] <- k; kf[t] <- max(k, 24L - np)
  }
  data.table(Date = MM$Date, r252 = r, below = below, run_now = run, n_r252_finite = n_fin,
             n_below_hist = n_hist, n_prior_below = n_prior, median_hist_run = med, q = q, g = g,
             k_star_dist = kd, k_star_full = kf)
}
D <- decomp(M)
D[, t := .I]; D[, g_probe := g_probe]
v2 <- D[, max(abs(g - g_probe))]
say("[V2] 분해 g vs 엔진 arm 탐침 g: 최대 |Δ| %.3e", v2)
if (v2 > 1e-12) stop("V2 실패 — 분해가 arm 과 다르다")
D[, w_shrink := pmin(1, t / E$.OV_NMIN[1])]
D[, g_eff := fifelse(t < E$.n_floor, 0, w_shrink * g)]
D[, guard := fifelse(t < E$.n_floor, "engine_floor_t<12",
              fifelse(n_r252_finite < 24L, "arm_r252_finite<24",
              fifelse(run_now == 0L, "above_trend_run0",
              fifelse(n_below_hist < 24L, "warmup_below_months<24",
              fifelse(g <= 0, "q<=0.5", "ACTIVE")))))]
# 엔진 자신의 층 기록(축소 후) — 보유 위 평균 · 최소 노출
D[, mean_e_engine := E$.L_MEAN[, 1]]; D[, min_e_engine := E$.L_MIN[, 1]]; D[, xsd_e_engine := E$.L_XSD[, 1]]
hold_n <- E$PORTFOLIO[, .N, by = Date]   # 오버레이 후 — 행 수는 사전과 같다(e > 0)
D[, n_hold := hold_n$N[match(Date, hold_n$Date)]]
bok <- E$.HOLD[, .(n_beta_ok = sum(is.finite(beta)), beta_mean = mean(beta, na.rm = TRUE)), by = Date]
D[, n_beta_ok := bok$n_beta_ok[match(Date, bok$Date)]]
# 산출물 Σw (집행일 = 시그널 다음 거래일)
s3 <- h3[, .(sum_w_rx3 = sum(target_weight)), by = .(sig_date, exec_date = date)]
s0 <- h0[, .(sum_w_rx0 = sum(target_weight)), by = .(sig_date)]
D <- merge(D, s3, by.x = "Date", by.y = "sig_date", all.x = TRUE)
D <- merge(D, s0, by.x = "Date", by.y = "sig_date", all.x = TRUE)
setorder(D, Date)
D[, active_engine := is.finite(min_e_engine) & min_e_engine < 1 - 1e-12]
D[, active_artifact := is.finite(sum_w_rx3) & sum_w_rx3 < 1 - 1e-9]
v3 <- D[!is.na(sum_w_rx3), sum(active_engine != active_artifact)] + D[!is.na(sum_w_rx3), sum(active_engine != (guard == "ACTIVE"))]
say("[V3] 발화 판정 불일치(엔진 층 기록 vs 산출물 Σw<1 vs 분해 ACTIVE): %d", v3)

#── 7. 반사실 CF — 이력 기점을 BM 자료 시작(1990-01)으로 옮긴 H 에 같은 arm ──────────────────
E2 <- new.env(parent = E)
E2$.B <- E$.B
E2$.sig_dates <- E$DT[Date >= as.Date("1990-01-01"), .(d = max(Date)), by = .(ym = format(Date, "%Y%m"))]$d
E2$.sig_dates <- sort(unique(E2$.sig_dates))
run_blk(E2, 637, 650, skip = c(647L, 648L))     # .M 구성 — ew·xs 병합(이 arm 미사용)만 건너뜀
MC <- copy(E2$.M); NC <- nrow(MC)
gC <- vapply(seq_len(NC), function(t) probe_g(MC, t), numeric(1))
DC <- decomp(MC); DC[, t := .I]; DC[, g_probe := gC]
v4 <- DC[, max(abs(g - g_probe))]
say("[CF] 이력 %s ~ %s (%d개월) · 분해 vs 탐침 최대 |Δ| %.3e · r252 첫 유한 %s", min(MC$Date), max(MC$Date), NC, v4,
    format(MC$Date[which(is.finite(MC$r252))[1]]))
DC[, guard := fifelse(n_r252_finite < 24L, "arm_r252_finite<24",
               fifelse(run_now == 0L, "above_trend_run0",
               fifelse(n_below_hist < 24L, "warmup_below_months<24",
               fifelse(g <= 0, "q<=0.5", "ACTIVE"))))]

#── 8. Pagan-Sossounov 국면(행동 카드와 같은 계약 함수 · 벤치 1990~τ_D) ──────────────────
B <- new.env(parent = globalenv())
sys.source(file.path(ROOT, "02_Infrastructure/contracts/behavior_card.R"), envir = B, keep.source = FALSE)
Hm <- B$bc_monthly(E$BM_DT[is.finite(BM_Ret), .(date = Date, r = BM_Ret)], "r")
PH <- B$bc_phases(B$bc_regimes(Hm))
fwrite(PH[end_ym >= "2004-01"], file.path(OUTD, "ps_phases_le_tauD.csv"))
ym_kind <- rbindlist(lapply(seq_len(nrow(PH)), function(i) {
  ys <- seq(as.Date(paste0(PH$start_ym[i], "-01")), as.Date(paste0(PH$end_ym[i], "-01")), by = "month")
  data.table(ym = format(ys, "%Y-%m"), ps_phase = PH$kind[i]) }))
# 시그널일 d 의 상태가 지배하는 보유 = 익월 → 그 '보유월'의 국면 라벨
D[, hold_ym := format(seq(as.Date(format(Date, "%Y-%m-01")), by = "month", length.out = 2L)[2L], "%Y-%m"), by = Date]
D[, ps_phase_hold_month := ym_kind$ps_phase[match(hold_ym, ym_kind$ym)]]

#── 9. 저장 ─────────────────────────────────────────────────────────────────────────
cols <- c("Date", "exec_date", "hold_ym", "t", "r252", "below", "run_now", "n_below_hist", "n_prior_below",
          "median_hist_run", "k_star_dist", "k_star_full", "q", "g", "w_shrink", "g_eff", "guard",
          "mean_e_engine", "min_e_engine", "xsd_e_engine", "n_hold", "n_beta_ok", "sum_w_rx3", "sum_w_rx0",
          "active_engine", "active_artifact", "ps_phase_hold_month")
fwrite(D[, ..cols], file.path(OUTD, "state_path_le_tauD.csv"))
fwrite(DC[Date >= as.Date("2004-01-01"), .(Date, r252, below, run_now, n_below_hist, n_prior_below, median_hist_run,
                                           k_star_dist, k_star_full, q, g, guard)],
       file.path(OUTD, "cf_full_history_state_2004_tauD.csv"))
saveRDS(list(D = D, DC = DC, PH = PH, rev = REV, block_lines = c(L1[ov_i], L2[ov_i]),
             v1 = c(rows = nrow(cmp), na = v1_na, maxdiff = v1_mx), v2 = v2, v3 = v3, v4 = v4),
        file.path(OUTD, "replay.rds"))
say("[done] out/state_path_le_tauD.csv · out/cf_full_history_state_2004_tauD.csv · out/ps_phases_le_tauD.csv · out/replay.rds")
