#==============================================================================
# RAWDATA Sanitize — 비거래일 제거 + 날짜 교정 + 누락일 복원
#
# Phase 1 일회성 정화 + 향후 /data-refresh --sanitize 에서 재사용
#
# 사용법:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/trading_calendar.R")
#   source("02_Infrastructure/rawdata_sanitize.R")
#   sanitize_rawdata()
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

if (!exists("PROJECT_ROOT")) source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
if (!exists("is_trading_day")) source(file.path(DATA_DIR, "trading_calendar.R"))

# ─── Ret Sanity 방화벽 (R44, 2026-07-15 — WT-D20260715_013) ────────────────────
#   목적: 물리 불가능한 Ret가 canonical 입력단을 통과하는 구조적 취약 수리.
#   R43 census(WT-D20260715_012): 전역 일간 Ret max=66999(전일종가 0원류·+6,699,900%).
#     |Ret|>0.31 = 2,760 종목-일 · |Ret|>1.0(물리불가) = 343 · 유니버스內(K200∪KQ150) 17.
#   KR 일일 가격제한 ±30%(0.30) → 0.31 초과 = 제한위반, 1.0 초과 = 물리 불가능.
#   세-단계 격리 (오염만 제거·정당 데이터 불변 = known-case parity):
#     ① HARD (Ret:=NA → 후속 !is.na(Ret) 제거가 소비): 물리불가(|Ret|>1.0) + 0원제수
#        (prevClose≤10, 반올림 증폭) + 날짜갭>20d ∧ stored 무효(|stored|>0.31 or NA).
#        → 정당 limit-bound(≤0.30) 및 megacap 레짐 정당 이동은 불변(reference-kr-2025-megacap 준수).
#     ② RESTORE (P3, R46 — WT-D20260715_015): 날짜갭>20d ∧ stored 물리타당(|stored|≤0.31).
#        R45(WT-D20260715_014) 근원 규명: date-gap 불일치의 recompute(Close/shift(Close)-1)는
#        Close 시계열 구멍을 gap 넘어 stale prevClose로 참조한 스퓨리어스이고 stored Ret이
#        참값(|stored|≤0.31 물리타당 196/196=100%). → NA 격리 대신 stored 참값 복원(행 보존·
#        recompute 스퓨리어스만 폐기 = 정보손실 방지). 소비는 mask_restore로 Ret:=Ret_stored.
#     ③ SUSPECT (값 유지 · 격리리스트 아티팩트로만 보존): 0.31<|Ret|≤1.0 잔여(분할류
#        ratio≈정수배 등). 분할 back-adjust는 R2/R3 KRX 백필 리빌드 소관 — 방화벽은 FLAG,
#        리빌드가 FIX. rawdata 스키마 불변(새 컬럼 미추가, "직접수정 금지" 정합).
#   ★stored Ret 참조: 명시 Ret_stored 컬럼 우선(sanitize Step5·census 주입), 없으면 dt$Ret 자체.
#   ★순수 함수(부작용 없음) — sanitize Step5와 회귀검증이 동일 로직을 공유(단일 진실).
#' @param dt data.table(Ticker, Date, Close, Ret[, Ret_stored, prevClose, gapdays, K200, KQ150])
#'           prevClose/gapdays 부재 시 Ticker·Date 정렬 후 shift로 계산(원본 복제, 미변경).
#'           Ret_stored(recompute 전 원본 stored Ret) 있으면 P3 date-gap 참값보존 활성.
#' @return list(mask_hard, mask_suspect, mask_restore, isolation=data.table, thresholds, counts)
ret_sanity_firewall <- function(dt,
                                ret_phys_impossible = 1.0,
                                ret_limit = 0.31,
                                zero_div_prevclose = 10,
                                dategap_max = 20L) {
  need_pc <- !("prevClose" %in% names(dt))
  need_gd <- !("gapdays"  %in% names(dt))
  D <- dt
  if (need_pc || need_gd) {
    D <- data.table::copy(dt); data.table::setorder(D, Ticker, Date)
    if (need_pc) D[, prevClose := shift(Close), by = Ticker]
    if (need_gd) D[, gapdays := as.integer(Date - shift(Date)), by = Ticker]
  }
  ret <- D$Ret; pc <- D$prevClose; gd <- D$gapdays
  # stored Ret 참조 (P3, R46) — 명시 Ret_stored 컬럼 우선(sanitize Step5·census 주입),
  #   없으면 ret 자체(standalone census: dt$Ret이 이미 stored 참값).
  stored_ret <- if ("Ret_stored" %in% names(D)) D$Ret_stored else ret
  has_ret <- !is.na(ret)
  stored_valid <- !is.na(stored_ret) & abs(stored_ret) <= ret_limit
  m_flagged <- has_ret & abs(ret) > ret_limit
  m_phys    <- m_flagged & abs(ret) > ret_phys_impossible
  m_zerodiv <- m_flagged & !is.na(pc) & pc <= zero_div_prevclose
  m_dategap_all <- m_flagged & !is.na(gd) & gd > dategap_max
  # ── P3 (R46): date-gap ∧ stored 물리타당 → stored 참값 보존(RESTORE, NA 대신 stored 복원) ──
  #   date-gap이면 recompute(Close/shift(Close)-1) 자체가 Close-hole을 gap 넘어 참조한 스퓨리어스
  #   (magnitude 무관 — |recompute|>1.0(phys)·penny 포함). stored 물리타당(|stored|≤0.31)이면 stored가
  #   참값(R45 196/196=100%) → NA 대신 복원. ★date-gap이 phys/zerodiv보다 우선(restore carve-out);
  #   연속일(non-gap) phys/0원제수만 HARD(stored도 오염). date-gap ∧ stored 무효 → HARD NA 유지.
  m_dategap_restore <- m_dategap_all & stored_valid
  m_hard    <- (m_phys | m_zerodiv | m_dategap_all) & !m_dategap_restore
  m_suspect <- m_flagged & !m_hard & !m_dategap_restore
  # SUSPECT 세분: 분할/증자류(ratio≈정수배 up 또는 1/정수 down) 식별 — R2/R3 back-adjust 표적화용.
  #   ratio = Close/prevClose = 1+Ret. up=액면분할/증자(≈정수배), down=병합/reverse-split·seam(≈1/정수).
  ratio <- 1 + ret
  int_tol <- 0.03
  m_split <- m_suspect & !is.na(ratio) & (
    (ratio >= 1.5 & abs(ratio - round(ratio)) <= int_tol * pmax(round(ratio), 1) & round(ratio) >= 2) |
    (ratio > 0 & ratio <= 0.67 & abs(1/ratio - round(1/ratio)) <= int_tol * pmax(round(1/ratio), 1) & round(1/ratio) >= 2))
  cause <- rep(NA_character_, length(ret))
  cause[m_suspect]         <- "SUSPECT_above_limit"
  cause[m_split]           <- "SUSPECT_split_like_ratio_int"        # 분할류(ratio≈정수배) — log+flag(값유지)
  cause[m_dategap_restore] <- "RESTORE_dategap_stored_valid_kept"   # P3 — stored 참값 보존(행 유지)
  # HARD 세부 라벨(우선순위 phys>zerodiv>dategap) — restore는 carve-out되어 m_hard=FALSE
  cause[m_hard & m_dategap_all & !m_phys & !m_zerodiv] <- "HARD_dategap_gt20d_stored_invalid"
  cause[m_hard & m_zerodiv]  <- "HARD_zerodiv_prevclose_le10"
  cause[m_hard & m_phys]     <- "HARD_phys_impossible_absret_gt1"   # 우선순위: 물리불가가 최상위
  k200  <- if ("K200"  %in% names(D)) D$K200  else rep(NA, nrow(D))
  kq150 <- if ("KQ150" %in% names(D)) D$KQ150 else rep(NA, nrow(D))
  in_univ <- (!is.na(k200) & k200 == TRUE) | (!is.na(kq150) & kq150 == TRUE)
  iso_idx <- which(m_hard | m_suspect | m_dategap_restore)
  isolation <- data.table::data.table(
    Ticker = D$Ticker[iso_idx], Date = D$Date[iso_idx], Ret = ret[iso_idx],
    Ret_stored = stored_ret[iso_idx],
    Close = D$Close[iso_idx], prevClose = pc[iso_idx], gapdays = gd[iso_idx],
    in_universe = in_univ[iso_idx],
    action = data.table::fifelse(m_hard[iso_idx], "NA_isolated",
              data.table::fifelse(m_dategap_restore[iso_idx], "stored_restored_kept", "suspect_flag_kept")),
    cause = cause[iso_idx])
  list(mask_hard = m_hard, mask_suspect = m_suspect, mask_restore = m_dategap_restore,
       isolation = isolation,
       thresholds = list(ret_phys_impossible = ret_phys_impossible, ret_limit = ret_limit,
                         zero_div_prevclose = zero_div_prevclose, dategap_max = dategap_max),
       counts = list(hard = sum(m_hard, na.rm = TRUE), suspect = sum(m_suspect, na.rm = TRUE),
                     restore = sum(m_dategap_restore, na.rm = TRUE),
                     hard_in_universe = sum(m_hard & in_univ, na.rm = TRUE),
                     suspect_in_universe = sum(m_suspect & in_univ, na.rm = TRUE),
                     restore_in_universe = sum(m_dategap_restore & in_univ, na.rm = TRUE)))
}

# ─── Close 연속성 tripwire (P2, R46 — WT-D20260715_015) ────────────────────────
#   목적: factor_db/sanitize 리빌드 *전에* 활성상장(비-상폐) 종목의 Close 시계열 구멍
#     (gapdays>threshold hole)을 감지·리포트. April-gap류 재발 조기 감지 (source seam
#     krx_api_backfill_*→krx_api 경계가 지문). Ret firewall(recompute 산물 격리)과 상보 —
#     firewall은 이미 발생한 스퓨리어스만 잡고, tripwire는 근원(Close hole) 자체를 조기 감지.
#   판정 배경(R45): recompute Ret 스퓨리어스의 근원 = Close hole. 홀 자체를 리빌드 전에 보면
#     R2/R3 KRX 백필 우선순위(유니버스 진입 후보)를 조준할 수 있다.
#   ★threshold=20d: KR 최장 연휴(설/추석 ~주말포함 최대 ~9일) 초과 → 진성 구멍만 검출
#     (정당 공휴일 gap 오탐 방지). ★순수 함수(부작용 없음, dt copy). rawdata 미변경.
#' @param dt data.table(Ticker, Date, Close[, source, K200, KQ150, Name, Market])
#' @param gap_threshold 캘린더-일 gap 임계(초과 = 진성 구멍). 기본 20L.
#' @param active_lag_days 종목 최종관측일이 데이터셋 max에서 이 이내면 '활성상장'. 기본 90L.
#' @param report_path (선택) 구멍 리스트 CSV 저장 경로.
#' @return list(holes=data.table, counts, thresholds, ds_max)
close_continuity_tripwire <- function(dt, gap_threshold = 20L, active_lag_days = 90L,
                                      report_path = NULL) {
  stopifnot(all(c("Ticker", "Date", "Close") %in% names(dt)))
  D <- data.table::copy(dt)
  D[, Date := as.Date(Date)]
  data.table::setorder(D, Ticker, Date)
  D[, prevDate := shift(Date), by = Ticker]
  D[, gapdays  := as.integer(Date - prevDate)]
  D[, prevClose := shift(Close), by = Ticker]
  has_src <- "source" %in% names(D)
  if (has_src) D[, prevSource := shift(source), by = Ticker]
  ds_max <- max(D$Date, na.rm = TRUE)
  # 활성상장(비-상폐): 종목 최종 관측일이 데이터셋 max에서 active_lag_days 이내
  last_dt <- D[, .(last_date = max(Date)), by = Ticker]
  active_tick <- last_dt[as.integer(ds_max - last_date) <= active_lag_days, Ticker]
  k200  <- if ("K200"  %in% names(D)) D$K200  else rep(NA, nrow(D))
  kq150 <- if ("KQ150" %in% names(D)) D$KQ150 else rep(NA, nrow(D))
  D[, in_universe := (!is.na(k200) & k200 == TRUE) | (!is.na(kq150) & kq150 == TRUE)]
  # 구멍: gapdays > threshold (mid-series — shift 이므로 gap 후 재개 행만 잡힘 = 상폐경계 아님)
  holes <- D[!is.na(gapdays) & gapdays > gap_threshold]
  if (nrow(holes) > 0) {
    holes[, active_listed := Ticker %in% active_tick]
    holes[, source_seam := if (has_src) (!is.na(prevSource) & source != prevSource) else NA]
    holes[, recent := as.integer(ds_max - Date) <= active_lag_days]
  }
  keep <- intersect(c("Ticker", "Name", "Market", "prevDate", "Date", "gapdays",
                      "prevClose", "Close", "source", "prevSource",
                      "in_universe", "active_listed", "source_seam", "recent"), names(holes))
  holes_out <- if (nrow(holes) > 0) holes[order(-recent, -in_universe, -gapdays), ..keep] else holes[, ..keep]
  cnt <- list(
    total_holes            = nrow(holes),
    in_universe            = if (nrow(holes)) holes[in_universe == TRUE, .N] else 0L,
    active_listed          = if (nrow(holes)) holes[active_listed == TRUE, .N] else 0L,
    in_universe_active     = if (nrow(holes)) holes[in_universe == TRUE & active_listed == TRUE, .N] else 0L,
    recent                 = if (nrow(holes)) holes[recent == TRUE, .N] else 0L,
    source_seam            = if (nrow(holes) && has_src) holes[source_seam == TRUE, .N] else 0L,
    unique_tickers         = if (nrow(holes)) holes[, uniqueN(Ticker)] else 0L)
  # ★게이트 신호: 유니버스內 활성 구멍(=리빌드가 오염 유발 가능) → 리빌드 전 경보 대상
  cnt$gate_flag_in_universe_active <- cnt$in_universe_active > 0L
  if (!is.null(report_path) && nrow(holes_out) > 0) data.table::fwrite(holes_out, report_path)
  list(holes = holes_out, counts = cnt,
       thresholds = list(gap_threshold = gap_threshold, active_lag_days = active_lag_days),
       ds_max = ds_max)
}

sanitize_rawdata <- function(dry_run = FALSE) {
  cat("=== RAWDATA Sanitize 시작 ===\n\n")

  RAWDATA_CACHE <- file.path(CACHE_DIR, "rawdata.parquet")
  BM_CACHE <- file.path(CACHE_DIR, "benchmark.parquet")
  cal <- .load_calendar()

  # ─── Step 1: 백업 ───────────────────────────────────────────────────────────
  cat("[Step 1] 백업...\n")
  raw <- as.data.table(read_parquet(RAWDATA_CACHE))
  bm  <- as.data.table(read_parquet(BM_CACHE))

  backup_path <- file.path(CACHE_DIR, sprintf("rawdata_backup_%s.parquet", format(Sys.Date(), "%Y%m%d")))
  bm_backup   <- file.path(CACHE_DIR, sprintf("benchmark_backup_%s.parquet", format(Sys.Date(), "%Y%m%d")))

  if (!file.exists(backup_path)) {
    write_parquet(raw, backup_path)
    cat(sprintf("  RAWDATA 백업: %s (%s rows)\n", backup_path, format(nrow(raw), big.mark=",")))
  } else {
    cat(sprintf("  백업 이미 존재: %s\n", backup_path))
  }
  if (!file.exists(bm_backup)) {
    write_parquet(bm, bm_backup)
    cat(sprintf("  Benchmark 백업: %s\n", bm_backup))
  }

  before_rows <- nrow(raw)
  before_dates <- length(unique(raw$Date))
  before_tickers <- uniqueN(raw$Ticker)

  # ─── Step 2: 04/01 → 03/31 재태깅 (Naver 날짜 버그 교정) ──────────────────
  cat("\n[Step 2] 04/01 → 03/31 재태깅...\n")
  d_0401 <- as.Date("2026-04-01")
  d_0331 <- as.Date("2026-03-31")

  n_0401 <- raw[Date == d_0401, .N]
  if (n_0401 > 0 && d_0331 %in% cal$Date) {
    # 03/31이 이미 RAWDATA에 있으면 04/01 제거 (중복 방지)
    if (d_0331 %in% raw$Date) {
      cat(sprintf("  03/31 이미 존재 (%d종목). 04/01 (%d종목) 제거.\n",
                  raw[Date == d_0331, .N], n_0401))
      raw <- raw[Date != d_0401]
    } else {
      raw[Date == d_0401, Date := d_0331]
      cat(sprintf("  04/01 → 03/31 재태깅: %d종목\n", n_0401))
    }
  } else if (n_0401 > 0) {
    cat(sprintf("  04/01 데이터 %d종목 있으나 03/31이 캘린더에 없음. 제거.\n", n_0401))
    raw <- raw[Date != d_0401]
  } else {
    cat("  04/01 데이터 없음. 스킵.\n")
  }

  # Benchmark도 동일
  if (d_0401 %in% bm$Date) {
    if (d_0331 %in% bm$Date) {
      bm <- bm[Date != d_0401]
    } else {
      bm[Date == d_0401, Date := d_0331]
    }
    ## ★2026-08-10 (FQ-127 F5): 이 줄은 `dry_run` 과 무관하게 "완료" 를 주장했다.
    ##   메모리상 bm 은 실제로 고쳐지지만 **저장은 뒤의 `if (!dry_run)` 안에서만** 일어나므로,
    ##   드라이런 사용자는 파일이 안 고쳐졌는데 "완료" 를 본다.
    ##   (close_round 의 '마커 발행 → Stop 게이트 자동 통과' 와 동형 — 억제 플래그 하의 거짓 보고.)
    ##   동작은 그대로 두고 **문구만** 실제와 맞춘다.
    cat(sprintf("  Benchmark도 교정%s\n",
                if (isTRUE(dry_run)) " (메모리상 — dry_run 이라 **미저장**)." else " 완료."))
  }

  # ─── Step 3: 비거래일 행 제거 ───────────────────────────────────────────────
  cat("\n[Step 3] 비거래일 행 제거...\n")
  all_dates <- sort(unique(raw$Date))
  non_td <- all_dates[!all_dates %in% cal$Date]
  cat(sprintf("  비거래일 수: %d\n", length(non_td)))

  # [guard 2026-07-11] 캘린더 결손 방어 — benchmark.parquet(chart-API 실세션)에 존재하는
  # 날짜를 '비거래일'로 지우려 하면 캘린더 구멍 의심 → 즉시 중단. 실사고: QuantiWise
  # 수출 이음매 구멍(base ~03-27 / update 04-30~)이 캘린더에 전사돼 2026-03-30~04-29
  # 실데이터 ~72k rows가 '비거래일'로 오판·삭제됨 (rawdata_april_gap_incident_20260711).
  if (length(non_td) > 0) {
    bm_sessions <- as.Date(bm$Date)
    cal_hole <- non_td[non_td %in% bm_sessions]
    if (length(cal_hole) > 0) {
      cat(sprintf("  ⛔ 중단: 제거 대상 %d일이 benchmark 실세션 날짜와 충돌 (%s ~ %s)\n",
                  length(cal_hole), min(cal_hole), max(cal_hole)))
      cat("     → trading calendar 결손 의심. build_trading_calendar(force=TRUE)로 재빌드 후 재시도.\n")
      return(invisible(NULL))
    }
  }

  if (length(non_td) > 0) {
    non_td_rows <- raw[Date %in% non_td, .N]
    cat(sprintf("  제거 대상: %s rows (%.1f%%)\n",
                format(non_td_rows, big.mark=","),
                100 * non_td_rows / nrow(raw)))

    # 안전 체크: 너무 많은 비율이면 경고
    pct <- non_td_rows / nrow(raw) * 100
    if (pct > 30) {
      cat("  ⚠️ 경고: 30% 이상 제거 대상. 캘린더 오류 가능성. 중단.\n")
      return(invisible(NULL))
    }
    if (pct > 15) {
      cat(sprintf("  참고: %.1f%% 제거 — 36년간 매주 일요일+공휴일 포함 시 정상 범위.\n", pct))
    }

    if (!dry_run) {
      raw <- raw[!Date %in% non_td]
      cat(sprintf("  제거 완료. 남은: %s rows\n", format(nrow(raw), big.mark=",")))
    }

    # Benchmark도 동일
    bm_non_td <- bm[!Date %in% cal$Date]
    if (nrow(bm_non_td) > 0) {
      cat(sprintf("  Benchmark 비거래일: %d행 제거\n", nrow(bm_non_td)))
      if (!dry_run) bm <- bm[Date %in% cal$Date]
    }
  }

  # ─── Step 4: 누락 거래일 확인 ───────────────────────────────────────────────
  cat("\n[Step 4] 누락 거래일 확인...\n")
  raw_dates <- sort(unique(raw$Date))
  # RAWDATA 범위 내에서 캘린더에 있는데 RAWDATA에 없는 날짜
  expected <- cal[Date >= min(raw_dates) & Date <= max(raw_dates)]$Date
  missing_td <- expected[!expected %in% raw_dates]

  if (length(missing_td) > 0) {
    cat(sprintf("  누락 거래일: %d일\n", length(missing_td)))
    # 최근 60일만 표시
    recent_missing <- missing_td[missing_td >= Sys.Date() - 60]
    if (length(recent_missing) > 0) {
      cat("  최근 60일 내 누락:\n")
      for (d in recent_missing) {
        cat(sprintf("    %s\n", as.Date(d, origin="1970-01-01")))
      }
    }
    cat(sprintf("  (전체 누락 중 대부분은 과거 공휴일 — 정상)\n"))
  } else {
    cat("  누락 없음.\n")
  }

  # ─── Step 4b: Close 연속성 tripwire (P2, R46) — 리빌드 전 구멍 조기 감지 ───────
  #   report-only(비변경). 유니버스內 활성 구멍 존재 시 경보(April-gap류 재발 조기 감지).
  cat("\n[Step 4b] Close 연속성 tripwire (P2, gapdays>20 hole)...\n")
  tw_path <- file.path(CACHE_DIR, sprintf("close_continuity_holes_%s.csv", format(Sys.Date(), "%Y%m%d")))
  tw <- close_continuity_tripwire(raw, gap_threshold = 20L, active_lag_days = 90L, report_path = tw_path)
  cat(sprintf("  구멍(gapdays>20): %d행 · 고유종목 %d · 유니버스內 %d · 활성상장 %d · 유니버스×활성 %d · 최근90d %d · source-seam %d\n",
              tw$counts$total_holes, tw$counts$unique_tickers, tw$counts$in_universe,
              tw$counts$active_listed, tw$counts$in_universe_active, tw$counts$recent, tw$counts$source_seam))
  if (isTRUE(tw$counts$gate_flag_in_universe_active)) {
    cat(sprintf("  ⚠️ 경보: 유니버스內 활성 Close 구멍 %d건 — 리빌드 전 KRX 백필 우선 권고(R2/R3). 리스트: %s\n",
                tw$counts$in_universe_active, tw_path))
  } else if (tw$counts$total_holes > 0) {
    cat(sprintf("  참고: 구멍 전량 비-유니버스/비-활성 (April-gap 비-유니버스 잔여) — 라이브 무영향. 리스트: %s\n", tw_path))
  }

  # ─── Step 5: Ret 재계산 + Ret sanity 방화벽 (R44/R46) ───────────────────────
  #   원리: ret_sanity_firewall() (파일 상단) — 물리불가·0원제수·날짜갭∧stored무효는 HARD 격리
  #         (Ret:=NA), 날짜갭∧stored물리타당은 RESTORE(stored 참값 복원·P3), 분할류 잔여는
  #         SUSPECT flag(값 유지·격리리스트만). 정당 데이터 불변(known-case parity).
  cat("\n[Step 5] Ret 재계산 + Ret sanity 방화벽 (R44/R46)...\n")
  if (!dry_run) {
    raw[, Ret_stored := Ret]                       # P3(R46): recompute 전 stored 참값 보존
    setorder(raw, Ticker, Date)
    raw[, prevClose := shift(Close), by = Ticker]
    raw[, gapdays   := as.integer(Date - shift(Date)), by = Ticker]
    raw[, Ret := Close / prevClose - 1]            # = Close/shift(Close)-1 (parity 불변)

    fw  <- ret_sanity_firewall(raw)               # Ret_stored/prevClose/gapdays 존재 → P3 restore 활성
    iso <- fw$isolation
    cnt <- fw$counts

    # 격리 리스트 파일 기록 (n_isolated 기록 — R43 R4 권고)
    if (nrow(iso) > 0) {
      iso_path <- file.path(CACHE_DIR, sprintf("ret_firewall_isolation_%s.csv", format(Sys.Date(), "%Y%m%d")))
      data.table::fwrite(iso, iso_path)
      cat(sprintf("  격리 리스트 기록: %s (%d행)\n", iso_path, nrow(iso)))
    }

    # HARD 격리: Ret:=NA → 다음 !is.na(Ret) 제거가 소비 (오염행 제거·정당 데이터 불변)
    if (cnt$hard > 0) raw[fw$mask_hard, Ret := NA_real_]
    # RESTORE (P3): date-gap ∧ stored 물리타당 → stored 참값 복원(recompute 스퓨리어스만 폐기·행 보존)
    if (cnt$restore > 0) raw[fw$mask_restore, Ret := Ret_stored]

    # 각 종목 첫 날 Ret = NA + HARD 격리 NA → 제거 (RESTORE는 유효값 → 보존)
    raw <- raw[!is.na(Ret)]
    raw[, c("prevClose", "gapdays", "Ret_stored") := NULL]  # 임시 컬럼 정리(Step 8 core_cols에도 부재)

    cat(sprintf("  방화벽 격리: HARD NA %d건(유니버스 %d) · RESTORE(stored 보존) %d건(유니버스 %d) · SUSPECT flag %d건(유니버스 %d)\n",
                cnt$hard, cnt$hard_in_universe, cnt$restore, cnt$restore_in_universe,
                cnt$suspect, cnt$suspect_in_universe))
    cat(sprintf("  잔여 |Ret|>0.3: %d건 (suspect·값 유지 — 분할 back-adjust는 R2/R3 리빌드 소관)\n",
                raw[abs(Ret) > 0.3, .N]))
  }

  # ─── Step 6: BM_Ret 재계산 ──────────────────────────────────────────────────
  cat("\n[Step 6] BM_Ret 재계산...\n")
  if (!dry_run) {
    setorder(bm, Date)
    bm[, BM_Ret := BM_Close / shift(BM_Close) - 1]
    bm <- bm[!is.na(BM_Ret)]

    # RAWDATA에 BM_Ret 매핑 — ★W-09(2026-09-23): 전열 재조인 대신 단일 writer 경유.
    #   구판(`BM_Ret := NULL` + merge)은 보호 구간(1990~98 토요장 계열 · 2024-12-30)까지
    #   덮고 열 순서를 바꿨다. 정의·보호·킬스위치 = data/rawdata_bm_ret_sync.R 하나.
    if (!exists("rawdata_bm_ret_sync_dt")) source(file.path(DATA_DIR, "rawdata_bm_ret_sync.R"))
    raw[, Date := as.Date(Date)]
    raw <- rawdata_bm_ret_sync_dt(raw, bench = bm[, .(Date = as.Date(Date), BM_Ret)],
                                  tag = "sanitize/bm_ret")$dt

    bm_na <- raw[is.na(BM_Ret), .N]
    if (bm_na > 0) cat(sprintf("  BM_Ret NA: %d rows (BM 데이터 없는 날짜)\n", bm_na))

    cat("  BM_Ret 재계산 완료.\n")
  }

  # ─── Step 7: source 컬럼 추가 ───────────────────────────────────────────────
  cat("\n[Step 7] source 컬럼 추가...\n")
  if (!dry_run) {
    if (!"source" %in% names(raw)) {
      raw[, source := "quantiwise"]  # 기본값 (OHLCVS base)
    }
    cat("  source 컬럼 확인 완료.\n")
  }

  # ─── Step 8: 저장 ───────────────────────────────────────────────────────────
  cat("\n[Step 8] 저장...\n")
  if (!dry_run) {
    # 컬럼 순서 정리
    # [fix 2026-07-03, 감사 DATA-P1-3] Layer2 컬럼(K200/KQ150/UnfaithfulDisc/
    #   AdminStock/TradingHalt/Float/Sector_Lv2)을 core_cols에 포함 — 구 버전이
    #   이 7컬럼을 strip해 apply_universe_mapping 재복구가 필요했던 사고 재발 방지.
    #   (intersect 방식이라 컬럼 부재 시에도 안전)
    core_cols <- c("Date", "BM_Ret", "Ticker", "Name", "Market", "Sector",
                   "K200", "KQ150", "UnfaithfulDisc", "AdminStock", "TradingHalt",
                   "Float", "Sector_Lv2",
                   "Open", "High", "Low", "Close", "Vol", "Size", "Ret", "source")
    keep <- intersect(core_cols, names(raw))
    dropped <- setdiff(names(raw), keep)
    if (length(dropped) > 0) {
      cat(sprintf("  ⚠️ core_cols 외 컬럼 drop: %s\n", paste(dropped, collapse = ", ")))
    }
    raw <- raw[, ..keep]
    setorder(raw, Date, Ticker)

    # [fix 2026-06-17] Windows arrow mmap(error 1224) — raw/bm가 각 source(RAWDATA_CACHE/
    # BM_CACHE)를 mmap한 채라 동일 경로 write_parquet halt 회피, temp-rename.
    # (raw/bm는 검증 요약·반환에 쓰이므로 rm 불가 — rename만으로 inode 교체)
    # [fix 2026-08-30] ★선삭제 제거 + 실패 fail-loud. 구판은 tmp 로 쓴 뒤 본 파일을 **지우고**
    #   rename 했고 rename 반환값을 버렸다. rename 은 대상이 있어도 덮어쓰므로 선삭제는
    #   이득 0 · 손실 무한(삭제~rename 사이 부재 창 — 2026-08-29 23:27 benchmark 실사고).
    #   공용 정본 = 02_Infrastructure/utils/atomic_parquet.R (선삭제 없음 · 유한 재시도 ·
    #   실패 시 stop 으로 원본 보존 · copy 폴백 없음).
    if (!exists("qvest_atomic_write_parquet"))
      source(file.path(PROJECT_ROOT, "02_Infrastructure/utils/atomic_parquet.R"))
    qvest_atomic_write_parquet(raw, RAWDATA_CACHE, tag = "sanitize/rawdata")
    # [정규화 2026-07-25] Date를 Date-class로 강제 후 기록 → on-disk date32[day] 보장.
    #   종전 passthrough는 읽은 dtype을 그대로 되썼기에, 상류가 timestamp를 남기면 그대로
    #   유통시켰다(오염원은 아니나 정규화 지점도 아님). writer 4곳(build_index_cache.py /
    #   naver_benchmark_update.py / krx_build_rawdata.R / 본 함수) 전부를 정규화 지점으로
    #   승격해 실행 순서와 무관하게 date32로 수렴시킨다. dtype 이탈은 소비자에서 silent
    #   all-NA 조인으로만 드러나므로(phase7 β-파생 ~54팩터 전멸, 2026-07-18) 쓰기 측에서 닫는다.
    if (!inherits(bm$Date, "Date")) bm[, Date := as.Date(Date)]
    qvest_atomic_write_parquet(bm, BM_CACHE, tag = "sanitize/bm")
    cat(sprintf("  RAWDATA 저장: %s rows\n", format(nrow(raw), big.mark=",")))
    cat(sprintf("  Benchmark 저장: %d rows\n", nrow(bm)))
  }

  # ─── 검증 요약 ──────────────────────────────────────────────────────────────
  cat("\n=== 검증 요약 ===\n")
  after_rows <- nrow(raw)
  after_dates <- length(unique(raw$Date))
  after_tickers <- uniqueN(raw$Ticker)

  cat(sprintf("  Before: %s rows, %d dates, %d tickers\n",
              format(before_rows, big.mark=","), before_dates, before_tickers))
  cat(sprintf("  After:  %s rows, %d dates, %d tickers\n",
              format(after_rows, big.mark=","), after_dates, after_tickers))
  cat(sprintf("  Removed: %s rows (%d non-trading dates)\n",
              format(before_rows - after_rows, big.mark=","), length(non_td)))

  # 비거래일 체크
  final_non_td <- unique(raw$Date)[!unique(raw$Date) %in% cal$Date]
  cat(sprintf("  비거래일 잔여: %d\n", length(final_non_td)))

  # 연속성 체크 (삼성전자)
  samsung <- raw[Ticker == "A005930" & Date >= as.Date("2026-03-25"), .(Date, Close, Ret)]
  cat("\n  삼성전자 최근:\n")
  print(samsung)

  cat("\n=== RAWDATA Sanitize 완료 ===\n")
  invisible(raw)
}

cat("[rawdata_sanitize] Loaded. Run: sanitize_rawdata() or sanitize_rawdata(dry_run=TRUE)\n")
