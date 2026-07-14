## ============================================================================
## insider_safe_live_track.R — SAFE/SAFE_FADING live 발화 종목 익월 실현위험 OOS 누적 (배관)
##   R42 (FQ-053 P2, WT-D20260715_011, 2026-07-15). monitoring 배관 · 자본/sizing 아님.
##
## 목적: filing_delay_watch.R Part C(insider_net_buy_safe)가 발화한 SAFE/SAFE_FADING 보유
##   종목을 등록하고, 익월부터 각 발화의 fading/SAFE 홀딩월 *실현* 위험(하방/tail/변동성)을
##   누적 append 해 R40(WT_D20260715_009) protection 창 예측을 out-of-sample 확증한다.
##   R40 실측: 청산 후 protection = ~1개월 transient(h0 tail 5.2%·h1 3.5% < OFF baseline 7.9% /
##   h2 12.3%·h3 10.5% baseline 복귀). ⇒ SAFE_FADING(mso∈{0,1}) 창의 실현 tail-hit이 baseline
##   7.9% 미만으로 누적되면 R40 h0-1 protection 창이 라이브에서 재현됨(자동조치 없음·도훈 재료).
##
## 상류(월간 실행 순서): filing_delay_watch.R 실행 후 본 스크립트 source.
##   cd 02_Infrastructure/reports && Rscript -e 'source("filing_delay_watch.R")'  # FDW latest 갱신
##   cd 02_Infrastructure/reports && Rscript -e 'source("insider_safe_live_track.R")'  # 본 트랙 갱신
##
## 동작(월간):
##   ① 발화 register  — 현 홀딩월 insider_flag∈{NET_BUY_SAFE,SAFE_FADING} 보유를 트랙 등록
##                      (발화월·종목·상태·mso·tier·발화시점 INS02 z). 기존 active episode는 갱신.
##   ② 실현위험 append — 각 트랙의 *완료된* fading/SAFE 홀딩월(H<현 캘린더월 ∧ rawdata H 완결)에
##                      대해 Ret_1m(동월 실현) → downside/tail/vol observation append (당월/미래 pending).
##   ③ auto-clear 로그 — active 트랙이 현 홀딩월 fired 집합에서 사라지면(mso>=2 → NEUTRAL 등) cleared
##                      기록 → R40 transient horizon(mso 1→2 auto-clear) 실증 누적.
##
## 실현위험 산식 = R40 정확 재사용(run_r40_insider_exit_censoring.R L.56/L.189):
##   Ret_1m = prod(1+Ret)-1 (Ticker×홀딩월 단일자산 월수익, 포트 합성 아님 · cor=1.0 rmon 검증) ·
##   downside=mean(r<0) · tail=P(r< -0.15) · vol=sd(r). metric_type=observational_monitoring.
##
## 규율: 단일스레드 · arrow io(2) · OneDrive temp-rename · DART API 0 · book_state/05_Production/
##   outputs.ramp 무변경(monitoring 배관만) · cov/weights 미산출(역할경계) · 텔레그램 미발송(배관).
## ============================================================================
Sys.setenv(ARROW_IO_THREADS = "2")
suppressWarnings(suppressMessages({
  library(arrow); library(data.table); library(jsonlite)
}))
setDTthreads(1)
try(arrow::set_io_thread_count(2L), silent = TRUE)

`%||%` <- function(a, b) if (is.null(a)) b else a   # null-coalesce (FDW 필드 방어)

ROOT     <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
FDW_JSON <- file.path(ROOT, "qepm/observability/filing_delay_watch_latest.json")   # 상류(read-only)
RAW_P    <- file.path(ROOT, ".cache/rawdata.parquet")                              # 실현수익 소스(완료월만)
OUT      <- file.path(ROOT, "qepm/observability/insider_safe_live_track.json")     # 본 트랙(누적)
OUT_DIR  <- dirname(OUT)
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

## 사전 고정 파라미터 — sweep 금지 (변경은 도훈 mandate)
FADE_MAX_MSO <- 1L      # R41/R40: fading 창 = months_since_off∈{0,1}, >=2 auto-clear (filing_delay_watch.R와 동일)
TAIL_THR     <- -0.15   # R40 tail 정의: P(Ret_1m < -0.15)
RET_LIMIT    <- 0.31    # KR 가격제한(±30%) — |일간 Ret| > 0.31 = 물리적 불가능 = 데이터 오염(rawdata 실측 max 66999).
                        #   초과분 제거(정당 limit-bound 이동은 보존). sweep 아님 = 제도 상수(KR ±30% 제한).
                        #   ★live rawdata 오염 실측(R42 진단, _r42_ret_scale_diag_log.txt): 전역 Ret max 66999.
                        #   ⚠ 익월 1차 실현 obs는 R40 production-basis(uni$Ret_1m)와 cohort 스팟체크 후 신뢰(§7b, next_probe).

## R40(WT_D20260715_009) baseline — frozen 인용(r40_results.json). OOS 대조 기준.
R40_BASELINE <- list(
  verdict          = "capability_established / no_hangover_horizon_limited (WT_D20260715_009)",
  off_baseline_tail    = 0.07946,   # OFF(MID) tail(<-15%) — SAFE 미보유 기저 위험
  off_baseline_downside= -0.08641,  # OFF(MID) downside=mean(r<0)
  h0_tail = 0.052, h1_tail = 0.035, # protection 창(mso 0/1) — <baseline (집중)
  h2_tail = 0.123, h3_tail = 0.105, # baseline 복귀(mso>=2, paired-t 전구간 |t|<2 비유의)
  protection_window_mso = c(0L, 1L),
  tail_threshold   = TAIL_THR,
  oos_comparison_rule = paste0(
    "발화 종목 fading 창(mso 0/1) 실현 tail-hit/downside를 R40 baseline OFF(tail 7.9%) 및 ",
    "h0-1 예측(<baseline)과 누적 대조. 표본이 R40 protection 창을 재현하는지 OOS 확증. ",
    "자동조치 없음 — 도훈 판단 재료. (자본/sizing 아님)"))

ym    <- function(d) { d <- as.Date(d); as.integer(format(d, "%Y")) * 100L + as.integer(format(d, "%m")) }
ymadd <- function(ymv, k) { y <- ymv %/% 100L; m <- ymv %% 100L; t <- (y*12L + (m-1L)) + k; (t %/% 12L)*100L + (t %% 12L) + 1L }
eom   <- function(ymv) { y <- ymv %/% 100L; m <- ymv %% 100L
                         d <- as.Date(sprintf("%d-%02d-01", y + (m==12L), ifelse(m==12L, 1L, m+1L))); d - 1L }

## ---- 1. 상류 FDW latest 로드 --------------------------------------------------
if (!file.exists(FDW_JSON))
  stop(sprintf("insider_safe_live_track: 상류 FDW 부재 (%s) — filing_delay_watch.R 먼저 실행", FDW_JSON))
fdw <- fromJSON(FDW_JSON, simplifyVector = FALSE)
ins <- fdw$insider_net_buy_safe
if (is.null(ins) || !isTRUE(ins$insider_source_ok)) {
  ins_ok <- FALSE
} else ins_ok <- TRUE

chy          <- if (ins_ok) as.integer(ins$current_holding_ym) else NA_integer_   # 현 홀딩월(발화월)
latest_sig   <- if (ins_ok) ins$latest_signal_date else NA_character_
panel_stale  <- if (ins_ok) isTRUE(ins$panel_stale) else NA
book_id      <- if (!is.null(fdw$book)) fdw$book else "STR_1715_on_M4_R05_noLayer4_PG2"

## 현 홀딩월 발화 보유 추출 (per_holding_insider — insider_flag∈{NET_BUY_SAFE,SAFE_FADING})
fired <- list()
if (ins_ok && length(ins$per_holding_insider)) {
  for (r in ins$per_holding_insider) {
    fl <- r$insider_flag
    if (!is.null(fl) && fl %in% c("NET_BUY_SAFE", "SAFE_FADING")) {
      fired[[r$ticker]] <- list(
        ticker = r$ticker, name = r$name %||% NA_character_,
        weight = r$weight %||% NA_real_,
        status = fl,
        insider_state = r$insider_state %||% NA_character_,
        mso    = if (is.null(r$months_since_off)) NA_integer_ else as.integer(r$months_since_off),
        dur_trust = r$dur_trust %||% NA_character_,
        ins02_z = r$ins02_net_buy_breadth %||% NA_real_,
        ins02_z_prev = r$ins02_prev_month %||% NA_real_,
        size_rank = if (is.null(r$size_rank)) NA_integer_ else as.integer(r$size_rank),
        tier = r$tier %||% NA_character_,
        tier_confidence = r$tier_confidence %||% NA_character_)
    }
  }
}

## ---- 2. 기존 트랙 로드 (없으면 init) -----------------------------------------
if (file.exists(OUT)) {
  TRK <- fromJSON(OUT, simplifyVector = FALSE)
  tracked     <- if (is.null(TRK$tracked))     list() else TRK$tracked
  cleared_log <- if (is.null(TRK$cleared_log)) list() else TRK$cleared_log
  created_at  <- if (is.null(TRK$created_at))  format(Sys.Date()) else TRK$created_at
} else {
  tracked <- list(); cleared_log <- list(); created_at <- format(Sys.Date())
}

## 헬퍼: active episode(같은 ticker, state=="active") 인덱스 찾기
find_active <- function(tk) {
  if (!length(tracked)) return(NA_integer_)
  for (i in seq_along(tracked))
    if (identical(tracked[[i]]$ticker, tk) && identical(tracked[[i]]$state, "active")) return(i)
  NA_integer_
}

now_iso <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
n_registered <- 0L; n_updated <- 0L; n_cleared <- 0L; n_obs_appended <- 0L
need_ret <- list()   # 실현위험 계산 대기: list(ticker, hold_ym, track_idx)

## ---- 3. 발화 register / 기존 episode 갱신 ------------------------------------
if (ins_ok && !is.na(chy)) {
  for (tk in names(fired)) {
    f <- fired[[tk]]
    ai <- find_active(tk)
    if (is.na(ai)) {
      ## 신규 발화 episode 등록
      tracked[[length(tracked) + 1L]] <- list(
        track_id            = sprintf("%s@%d", tk, chy),
        ticker              = tk,
        name                = f$name,
        book                = book_id,
        status_at_firing    = f$status,
        firing_holding_ym   = chy,
        firing_mso          = f$mso,
        insider_state_at_firing = f$insider_state,
        tier                = f$tier,
        tier_confidence     = f$tier_confidence,
        size_rank_at_firing = f$size_rank,
        weight_at_firing    = f$weight,
        ins02_z_at_firing   = f$ins02_z,
        ins02_z_prev        = f$ins02_z_prev,
        clears_at_mso       = FADE_MAX_MSO + 1L,
        state               = "active",
        last_seen_holding_ym= chy,
        last_status         = f$status,
        last_mso            = f$mso,
        registered_at       = now_iso,
        observations        = list(),
        note                = sprintf("발화 등록 %d (%s, mso=%s, %s). R40 protection 창 대조 대상 — 익월부터 fading/SAFE 홀딩월 실현위험 append(pending).",
                                      chy, f$status, ifelse(is.na(f$mso), "NA", as.character(f$mso)), f$tier))
      n_registered <- n_registered + 1L
    } else {
      ## 기존 active episode 갱신(청산창 지속 h0→h1 등)
      tracked[[ai]]$last_seen_holding_ym <- chy
      tracked[[ai]]$last_status <- f$status
      tracked[[ai]]$last_mso    <- f$mso
      n_updated <- n_updated + 1L
    }
  }
}

## ---- 4. auto-clear: active 트랙이 현 홀딩월 fired에서 사라짐 → cleared 로그 ----
if (ins_ok && !is.na(chy)) {
  for (i in seq_along(tracked)) {
    t <- tracked[[i]]
    if (identical(t$state, "active") && !(t$ticker %in% names(fired)) &&
        !is.na(t$last_seen_holding_ym) && chy > as.integer(t$last_seen_holding_ym)) {
      tracked[[i]]$state <- "cleared"
      tracked[[i]]$cleared_at_holding_ym <- chy
      reason <- "auto_clear_mso_ge_2"   # SAFE_FADING mso 1→2 초과 = protection 창 종료(R40 transient)
      tracked[[i]]$cleared_reason <- reason
      cleared_log[[length(cleared_log) + 1L]] <- list(
        track_id = t$track_id, ticker = t$ticker, name = t$name,
        firing_holding_ym = t$firing_holding_ym, cleared_at_holding_ym = chy,
        last_status = t$last_status, last_mso = t$last_mso, reason = reason,
        note = "R40 transient horizon 실증 — fading 창(mso 0/1) 벗어나 NEUTRAL 자동 해제(mso>=2).",
        logged_at = now_iso)
      n_cleared <- n_cleared + 1L
    }
  }
}

## ---- 5. 실현위험 append: 완료된 fading/SAFE 홀딩월만 (당월/미래 pending) --------
ccm <- ym(Sys.Date())                         # 현 캘린더월
rd_max_ym <- NA_integer_
have_obs_ym <- function(t, H) {
  if (!length(t$observations)) return(FALSE)
  any(vapply(t$observations, function(o) identical(as.integer(o$holding_ym), as.integer(H)), logical(1)))
}
## 각 트랙의 [firing_holding_ym .. last_seen_holding_ym] 중 완료·미관측 홀딩월 수집
for (i in seq_along(tracked)) {
  t <- tracked[[i]]
  h_from <- as.integer(t$firing_holding_ym)
  h_to   <- as.integer(t$last_seen_holding_ym %||% t$firing_holding_ym)
  H <- h_from
  while (H <= h_to) {
    complete_cal <- H < ccm                    # 캘린더상 해당 월 종료
    if (complete_cal && !have_obs_ym(t, H))
      need_ret[[length(need_ret) + 1L]] <- list(track_idx = i, ticker = t$ticker, hold_ym = H,
                                                 mso = t$firing_mso, status = t$status_at_firing)
    H <- ymadd(H, 1L)
  }
}
if (length(need_ret)) {
  rw <- as.data.table(read_parquet(RAW_P, col_select = c("Date", "Ticker", "Ret")))
  rw[, Date := as.Date(Date)]
  rd_max_ym <- ym(max(rw$Date, na.rm = TRUE))
  rw[, ymv := ym(Date)]
  for (nr in need_ret) {
    H <- as.integer(nr$hold_ym)
    ## rawdata가 홀딩월 H를 완결 커버할 때만(월말 실현) — 아니면 pending 유지
    if (is.na(rd_max_ym) || rd_max_ym < H) next
    rr_raw <- rw[Ticker == nr$ticker & ymv == H, Ret]
    rr_raw <- rr_raw[is.finite(rr_raw)]
    if (!length(rr_raw)) next
    n_drop <- sum(abs(rr_raw) > RET_LIMIT)      # KR ±30% 초과 = 오염 제거(정당 limit-bound 보존)
    rr <- rr_raw[abs(rr_raw) <= RET_LIMIT]
    if (!length(rr)) next
    ret_1m   <- prod(1 + rr) - 1               # R40-identical 단일자산 월수익(포트 합성 아님)
    tail_hit <- as.integer(ret_1m < TAIL_THR)
    mso_H    <- if (is.na(nr$mso)) NA_integer_ else as.integer(nr$mso)
    in_prot  <- if (is.na(mso_H)) NA else (mso_H %in% R40_BASELINE$protection_window_mso)
    obs <- list(
      holding_ym = H, mso_at_holding = mso_H, status = nr$status,
      ret_1m = round(ret_1m, 5),
      tail_hit = tail_hit,
      downside_contrib = if (ret_1m < 0) round(ret_1m, 5) else 0,
      in_protection_window = in_prot,
      n_days = length(rr), n_days_dropped_contamination = n_drop,
      source_verified = FALSE,   # §7b: R40 production-basis(uni$Ret_1m) cohort 스팟체크 후 TRUE (익월 1차 obs 검증)
      baseline_off_tail = R40_BASELINE$off_baseline_tail,
      expected_vs_baseline = if (isTRUE(in_prot)) "tail < baseline 7.9% (R40 h0-1 protection)"
                             else if (identical(in_prot, FALSE)) "baseline 복귀(R40 h2+)" else "NA",
      appended_at = now_iso)
    ti <- nr$track_idx
    tracked[[ti]]$observations[[length(tracked[[ti]]$observations) + 1L]] <- obs
    n_obs_appended <- n_obs_appended + 1L
  }
}

## ---- 6. OOS rollup: protection 창(mso 0/1) 실현 tail-hit 누적 vs R40 baseline ----
all_obs <- list()
for (t in tracked) for (o in t$observations) all_obs[[length(all_obs) + 1L]] <- o
prot_ret <- c(); prot_tail <- c()
for (o in all_obs) if (isTRUE(o$in_protection_window)) {
  prot_ret  <- c(prot_ret, o$ret_1m); prot_tail <- c(prot_tail, o$tail_hit)
}
oos_rollup <- list(
  n_observations_total   = length(all_obs),
  n_protection_window    = length(prot_ret),
  realized_tail_hit_rate = if (length(prot_tail)) round(mean(prot_tail), 4) else NA,
  realized_downside      = if (length(prot_ret)) round(mean(prot_ret[prot_ret < 0]), 5) else NA,
  baseline_off_tail      = R40_BASELINE$off_baseline_tail,
  r40_h0_h1_tail_pred    = c(R40_BASELINE$h0_tail, R40_BASELINE$h1_tail),
  confirms_protection    = if (length(prot_tail)) (mean(prot_tail) < R40_BASELINE$off_baseline_tail) else NA,
  status = if (length(prot_ret)) "accumulating" else "pending (익월부터 — 현 발화 홀딩월 미완결)",
  note   = "protection 창(mso∈{0,1}) 실현 tail-hit이 R40 baseline OFF 7.9% 미만 누적 = 라이브 protection 재현. 표본 축적 전 판정 금지(자동조치 없음).")

## ---- 7. 트랙 JSON 저장 (OneDrive temp-rename) --------------------------------
n_active  <- sum(vapply(tracked, function(t) identical(t$state, "active"), logical(1)))
n_cleared_total <- sum(vapply(tracked, function(t) identical(t$state, "cleared"), logical(1)))
out <- list(
  schema      = "insider_safe_live_track_v1",
  purpose     = paste0("SAFE/SAFE_FADING live 발화 종목 익월 실현위험 OOS 누적 — R40 protection 창",
                       "(mso 0/1 tail<baseline) out-of-sample 확증. monitoring 배관 · 자본/sizing 아님."),
  book        = book_id,
  metric_type = "observational_monitoring",
  created_at  = created_at,
  updated_at  = now_iso,
  as_of       = format(Sys.Date()),
  current_holding_ym = if (is.na(chy)) NA else chy,
  latest_signal_date = latest_sig,
  panel_stale = panel_stale,
  upstream    = "qepm/observability/filing_delay_watch_latest.json (insider_net_buy_safe)",
  writer      = "02_Infrastructure/reports/insider_safe_live_track.R",
  realized_source = paste0(".cache/rawdata.parquet Ret_1m = prod(1+Ret)-1 per Ticker×월 (R40-identical) + KR ±30% ",
                           "가격제한 가드(|일간 Ret|>", RET_LIMIT, " 오염 제거 — live rawdata 전역 max 66999 실측). ",
                           "⚠ 익월 1차 obs는 source_verified=FALSE — R40 production-basis(uni$Ret_1m) cohort 스팟체크 후 신뢰(§7b)."),
  rawdata_max_ym  = if (is.na(rd_max_ym)) NA else rd_max_ym,
  fade_max_mso    = FADE_MAX_MSO,
  auto_clear_at_mso = FADE_MAX_MSO + 1L,
  r40_baseline    = R40_BASELINE,
  run_summary = list(
    registered_this_run = n_registered, updated_this_run = n_updated,
    cleared_this_run = n_cleared, observations_appended_this_run = n_obs_appended,
    n_active = n_active, n_cleared_total = n_cleared_total),
  oos_rollup  = oos_rollup,
  tracked     = tracked,
  cleared_log = cleared_log,
  provenance  = list(
    round = "R42 (WT-D20260715_011, FQ-053 P2)",
    parent = "R41 next_probe P1 (SAFE/SAFE_FADING live OOS 추적 배관, armed→active)",
    r40 = "stage_artifacts/WT_D20260715_009/verdict.json (protection ~1개월 transient)",
    discipline = "monitoring 배관 · 자본 아님 · DART API 0 · book/05_Production 무변경 · 자동조치 없음(도훈 재료)"))

tmp <- paste0(OUT, ".tmp_", Sys.getpid())
write_json(out, tmp, auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
if (file.exists(OUT)) file.remove(OUT)
invisible(file.rename(tmp, OUT))

## ---- 8. 콘솔 요약 ------------------------------------------------------------
cat(sprintf("\n[live_track] insider SAFE/SAFE_FADING live OOS 추적 (R42, FQ-053 P2) — %s\n", format(Sys.Date())))
cat(sprintf("   상류 FDW: 현 홀딩월=%s · 최신 signal=%s · panel_stale=%s\n",
            ifelse(is.na(chy), "NA", chy), latest_sig, panel_stale))
cat(sprintf("   이번 실행: register %d · update %d · cleared %d · obs append %d\n",
            n_registered, n_updated, n_cleared, n_obs_appended))
cat(sprintf("   트랙 상태: active %d · cleared %d · 관측 총 %d(protection창 %d)\n",
            n_active, n_cleared_total, oos_rollup$n_observations_total, oos_rollup$n_protection_window))
for (t in tracked) if (identical(t$state, "active"))
  cat(sprintf("   • %-14s %-10s 발화%d status=%-12s mso=%s tier=%s z=%s obs=%d\n",
              t$track_id, ifelse(is.null(t$name)||is.na(t$name),"-",t$name), t$firing_holding_ym,
              t$status_at_firing, ifelse(is.na(t$firing_mso),"NA",t$firing_mso), t$tier,
              ifelse(is.na(t$ins02_z_at_firing),"NA",sprintf("%+.3f",t$ins02_z_at_firing)),
              length(t$observations)))
cat(sprintf("   OOS rollup: %s (realized tail-hit=%s vs baseline %.3f)\n",
            oos_rollup$status,
            ifelse(is.na(oos_rollup$realized_tail_hit_rate),"pending",oos_rollup$realized_tail_hit_rate),
            R40_BASELINE$off_baseline_tail))
cat(sprintf("[live_track] → %s\n", OUT))
