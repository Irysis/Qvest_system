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
#   두-단계 격리 (오염만 제거·정당 데이터 불변 = known-case parity):
#     ① HARD (Ret:=NA → 후속 !is.na(Ret) 제거가 소비): 물리불가(|Ret|>1.0) + 0원제수
#        (prevClose≤10, 반올림 증폭) + 날짜갭>20d(상폐/재상장 cross-gap 허위수익).
#        → 정당 limit-bound(≤0.30) 및 megacap 레짐 정당 이동은 불변(reference-kr-2025-megacap 준수).
#     ② SUSPECT (값 유지 · 격리리스트 아티팩트로만 보존): 0.31<|Ret|≤1.0 잔여(분할류
#        ratio≈정수배 등). 분할 back-adjust는 R2/R3 KRX 백필 리빌드 소관 — 방화벽은 FLAG,
#        리빌드가 FIX. rawdata 스키마 불변(새 컬럼 미추가, "직접수정 금지" 정합).
#   ★순수 함수(부작용 없음) — sanitize Step5와 회귀검증이 동일 로직을 공유(단일 진실).
#' @param dt data.table(Ticker, Date, Close, Ret[, prevClose, gapdays, K200, KQ150])
#'           prevClose/gapdays 부재 시 Ticker·Date 정렬 후 shift로 계산(원본 복제, 미변경).
#' @return list(mask_hard, mask_suspect, isolation=data.table, thresholds, counts)
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
  has_ret <- !is.na(ret)
  m_phys    <- has_ret & abs(ret) > ret_phys_impossible
  m_zerodiv <- has_ret & abs(ret) > ret_limit & !is.na(pc) & pc <= zero_div_prevclose
  m_dategap <- has_ret & abs(ret) > ret_limit & !is.na(gd) & gd > dategap_max
  m_hard    <- m_phys | m_zerodiv | m_dategap
  m_suspect <- has_ret & abs(ret) > ret_limit & !m_hard
  # SUSPECT 세분: 분할/증자류(ratio≈정수배 up 또는 1/정수 down) 식별 — R2/R3 back-adjust 표적화용.
  #   ratio = Close/prevClose = 1+Ret. up=액면분할/증자(≈정수배), down=병합/reverse-split·seam(≈1/정수).
  ratio <- 1 + ret
  int_tol <- 0.03
  m_split <- m_suspect & !is.na(ratio) & (
    (ratio >= 1.5 & abs(ratio - round(ratio)) <= int_tol * pmax(round(ratio), 1) & round(ratio) >= 2) |
    (ratio > 0 & ratio <= 0.67 & abs(1/ratio - round(1/ratio)) <= int_tol * pmax(round(1/ratio), 1) & round(1/ratio) >= 2))
  cause <- rep(NA_character_, length(ret))
  cause[m_suspect] <- "SUSPECT_above_limit"
  cause[m_split]   <- "SUSPECT_split_like_ratio_int"       # 분할류(ratio≈정수배) — log+flag(값유지)
  cause[m_dategap] <- "HARD_dategap_gt20d"
  cause[m_zerodiv] <- "HARD_zerodiv_prevclose_le10"
  cause[m_phys]    <- "HARD_phys_impossible_absret_gt1"    # 우선순위: 물리불가가 최상위
  k200  <- if ("K200"  %in% names(D)) D$K200  else rep(NA, nrow(D))
  kq150 <- if ("KQ150" %in% names(D)) D$KQ150 else rep(NA, nrow(D))
  in_univ <- (!is.na(k200) & k200 == TRUE) | (!is.na(kq150) & kq150 == TRUE)
  iso_idx <- which(m_hard | m_suspect)
  isolation <- data.table::data.table(
    Ticker = D$Ticker[iso_idx], Date = D$Date[iso_idx], Ret = ret[iso_idx],
    Close = D$Close[iso_idx], prevClose = pc[iso_idx], gapdays = gd[iso_idx],
    in_universe = in_univ[iso_idx],
    action = data.table::fifelse(m_hard[iso_idx], "NA_isolated", "suspect_flag_kept"),
    cause = cause[iso_idx])
  list(mask_hard = m_hard, mask_suspect = m_suspect, isolation = isolation,
       thresholds = list(ret_phys_impossible = ret_phys_impossible, ret_limit = ret_limit,
                         zero_div_prevclose = zero_div_prevclose, dategap_max = dategap_max),
       counts = list(hard = sum(m_hard, na.rm = TRUE), suspect = sum(m_suspect, na.rm = TRUE),
                     hard_in_universe = sum(m_hard & in_univ, na.rm = TRUE),
                     suspect_in_universe = sum(m_suspect & in_univ, na.rm = TRUE)))
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
    cat("  Benchmark도 교정 완료.\n")
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

  # ─── Step 5: Ret 재계산 + Ret sanity 방화벽 (R44) ───────────────────────────
  #   원리: ret_sanity_firewall() (파일 상단) — 물리불가·0원제수·날짜갭은 HARD 격리(Ret:=NA),
  #         분할류 잔여는 SUSPECT flag(값 유지·격리리스트만). 정당 데이터 불변(known-case parity).
  cat("\n[Step 5] Ret 재계산 + Ret sanity 방화벽 (R44)...\n")
  if (!dry_run) {
    setorder(raw, Ticker, Date)
    raw[, prevClose := shift(Close), by = Ticker]
    raw[, gapdays   := as.integer(Date - shift(Date)), by = Ticker]
    raw[, Ret := Close / prevClose - 1]            # = Close/shift(Close)-1 (parity 불변)

    fw  <- ret_sanity_firewall(raw)               # prevClose/gapdays 이미 존재 → 재계산 안 함
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

    # 각 종목 첫 날 Ret = NA + HARD 격리 NA → 제거
    raw <- raw[!is.na(Ret)]
    raw[, c("prevClose", "gapdays") := NULL]      # 임시 컬럼 정리(Step 8 core_cols에도 부재)

    cat(sprintf("  방화벽 격리: HARD NA %d건(유니버스 %d) · SUSPECT flag %d건(유니버스 %d)\n",
                cnt$hard, cnt$hard_in_universe, cnt$suspect, cnt$suspect_in_universe))
    cat(sprintf("  잔여 |Ret|>0.3: %d건 (전량 suspect·값 유지 — 분할 back-adjust는 R2/R3 리빌드 소관)\n",
                raw[abs(Ret) > 0.3, .N]))
  }

  # ─── Step 6: BM_Ret 재계산 ──────────────────────────────────────────────────
  cat("\n[Step 6] BM_Ret 재계산...\n")
  if (!dry_run) {
    setorder(bm, Date)
    bm[, BM_Ret := BM_Close / shift(BM_Close) - 1]
    bm <- bm[!is.na(BM_Ret)]

    # RAWDATA에 BM_Ret 매핑
    raw[, BM_Ret := NULL]
    raw <- merge(raw, bm[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)

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
    .raw_tmp <- paste0(RAWDATA_CACHE, ".tmp")
    write_parquet(raw, .raw_tmp)
    if (file.exists(RAWDATA_CACHE)) file.remove(RAWDATA_CACHE)
    file.rename(.raw_tmp, RAWDATA_CACHE)
    .bm_tmp <- paste0(BM_CACHE, ".tmp")
    write_parquet(bm, .bm_tmp)
    if (file.exists(BM_CACHE)) file.remove(BM_CACHE)
    file.rename(.bm_tmp, BM_CACHE)
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
