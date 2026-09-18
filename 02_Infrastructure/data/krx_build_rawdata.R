#==============================================================================
# KRX Build RAWDATA — Transform KRX API data into RAWDATA format
#
# Pipeline: detect gap → collect via API → transform → merge → update cache
#
# Usage:
#   source("config.R")
#   source("krx_data_collector.R")
#   source("krx_build_rawdata.R")
#   krx_run_pipeline()
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

if (!exists("PROJECT_ROOT")) source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
if (!exists("krx_api")) source(file.path(DATA_DIR, "krx_data_collector.R"))
# [Track R fix 2026-06-12] trading_calendar 의무 로드 — krx_detect_interior_gaps()/
# krx_merge_rawdata()의 거래일 가드가 exists() 조건부라 미로드 시 죽은 코드였음
# (daily_refresh [2]가 본 파일만 source → interior gap 감지 0건 고정, 06-04~09 누락 영구화).
if (!exists("is_trading_day")) {
  tryCatch(source(file.path(DATA_DIR, "trading_calendar.R")),
           error = function(e) cat(sprintf(
             "[krx_build_rawdata][WARN] trading_calendar load FAILED (%s) - calendar guards DEAD\n",
             e$message)))
}

#──────────────────────────────────────────────────────────────────────────────
# 1. Detect gap between RAWDATA and current date
#──────────────────────────────────────────────────────────────────────────────
krx_detect_gap <- function() {
  raw <- as.data.table(read_parquet(RAWDATA_CACHE))
  last_date <- max(raw$Date)

  # last_confirmed_trading_day() 사용 (있으면), 없으면 T-1
  if (exists("last_confirmed_trading_day")) {
    target <- last_confirmed_trading_day()
  } else {
    target <- Sys.Date() - 1
  }

  list(
    last_rawdata_date = last_date,
    start = format(last_date + 1, "%Y%m%d"),
    end   = format(target, "%Y%m%d"),
    n_calendar_days = as.integer(target - last_date)
  )
}

#──────────────────────────────────────────────────────────────────────────────
# 1b. Interior gap 탐지 — RAWDATA 내 누락 거래일 전수 탐색
#──────────────────────────────────────────────────────────────────────────────
krx_detect_interior_gaps <- function(lookback_days = 60L) {
  if (!exists("get_trading_days")) {
    cat("[interior_gap] trading_calendar 미로드. 스킵.\n")
    return(character(0))
  }

  raw <- as.data.table(read_parquet(RAWDATA_CACHE))
  existing_dates <- sort(unique(raw$Date))

  cutoff <- Sys.Date() - lookback_days
  recent_existing <- existing_dates[existing_dates >= cutoff]
  if (length(recent_existing) < 2) return(character(0))

  confirmed <- if (exists("last_confirmed_trading_day")) last_confirmed_trading_day() else Sys.Date() - 1
  expected <- get_trading_days(min(recent_existing), confirmed)

  missing <- setdiff(as.character(expected), as.character(recent_existing))
  if (length(missing) > 0) {
    cat(sprintf("[interior_gap] %d 누락 거래일: %s\n", length(missing), paste(missing, collapse = ", ")))
  }
  missing
}

#──────────────────────────────────────────────────────────────────────────────
# 2. Transform a single date's KRX data → RAWDATA format
#──────────────────────────────────────────────────────────────────────────────
krx_transform_daily <- function(date_str) {
  # Load KOSPI + KOSDAQ OHLCV
  stk_file <- file.path(KRX_CACHE_DIR, "stk_ohlcv", sprintf("stk_ohlcv_%s.parquet", date_str))
  ksq_file <- file.path(KRX_CACHE_DIR, "ksq_ohlcv", sprintf("ksq_ohlcv_%s.parquet", date_str))

  stk <- if (file.exists(stk_file)) as.data.table(read_parquet(stk_file)) else NULL
  ksq <- if (file.exists(ksq_file)) as.data.table(read_parquet(ksq_file)) else NULL

  if (is.null(stk) && is.null(ksq)) return(NULL)

  ohlcv <- rbindlist(list(stk, ksq), fill = TRUE)

  # Column mapping (KRX API → RAWDATA)
  # ISU_CD → Ticker (prefix "A" to match RAWDATA format A000010)
  # ISU_NM → Name
  # Market → Market (already added in krx_collect_daily)
  # SECT_TP_NM → Sector
  # TDD_OPNPRC → Open, TDD_HGPRC → High, TDD_LWPRC → Low, TDD_CLSPRC → Close
  # ACC_TRDVOL → Vol, MKTCAP → Size

  .num <- function(x) as.numeric(gsub(",", "", x))

  dt <- ohlcv[, .(
    Date   = as.Date(date_str, "%Y%m%d"),
    Ticker = paste0("A", ISU_CD),
    Name   = ISU_NM,
    Market = fifelse(is.na(Market) | Market == "", MKT_NM, Market),
    Sector = fifelse(is.na(SECT_TP_NM) | SECT_TP_NM == "", NA_character_, SECT_TP_NM),
    Open   = .num(TDD_OPNPRC),
    High   = .num(TDD_HGPRC),
    Low    = .num(TDD_LWPRC),
    Close  = .num(TDD_CLSPRC),
    Vol    = .num(ACC_TRDVOL),
    Size   = .num(MKTCAP)
  )]

  # Remove rows with zero/NA Close
  dt <- dt[!is.na(Close) & Close > 0]

  dt
}

#──────────────────────────────────────────────────────────────────────────────
# 3. Compute BM_Ret from KOSPI 200 index
#──────────────────────────────────────────────────────────────────────────────
krx_compute_bm_ret <- function(date_strs) {
  idx_dir <- file.path(KRX_CACHE_DIR, "kospi_index")
  if (!dir.exists(idx_dir)) return(NULL)

  idx_list <- list()
  for (ds in date_strs) {
    f <- file.path(idx_dir, sprintf("kospi_index_%s.parquet", ds))
    if (file.exists(f)) {
      dt <- as.data.table(read_parquet(f))
      # ★2026-09-07 정정 — 여기는 **코스피200**이어야 한다 (구판은 "^코스피$" = 종합지수).
      #   근거 3중:
      #     ① 2026-07-02 도훈 mandate: 북 벤치 = 코스피200(IKS200). build_index_cache.py 도
      #        naver_benchmark_update.py(symbol='KPI200') 도 전부 코스피200이다.
      #     ② 이 함수의 이름·주석이 이미 "Compute BM_Ret from KOSPI 200 index" 다.
      #     ③ 실측: `.cache/benchmark.parquet::BM_Ret` 은 indices.parquet$kospi200 과 일치하고
      #        kospi(종합)와는 0% 일치한다. 종합을 넣으면 **다른 지수의 수익률**이 RAWDATA::BM_Ret
      #        으로 들어간다(benchmark_source_parity.R 이 2026-07 에 잡은 8일 불일치의 계통).
      #   ★아래 |BM_Ret|>0.30 가드는 이 오선택을 못 잡는다(실측 2026-09-02: 종합 6,562 vs
      #     BM_Close 9,113 → 이음매 수익률 -28.0%, 문턱 0.30 **바로 아래**로 통과했을 것).
      #     지수 선택이 맞아야 그 가드가 fail-closed 로 작동한다.
      #   한글 리터럴은 비교식에 직접 박지 않는다 — Windows 네이티브 인코딩 세션에서
      #   parquet(UTF-8) 문자열과 바이트가 갈린다(benchmark_level_axis.R 과 같은 규약).
      .idx_nm_k200 <- intToUtf8(c(0xCF54, 0xC2A4, 0xD53C, 0x20, 0x32, 0x30, 0x30))  # KOSPI 200
      k200 <- dt[trimws(enc2utf8(as.character(IDX_NM))) == .idx_nm_k200]
      if (nrow(k200) > 0) {
        idx_list[[length(idx_list) + 1]] <- data.table(
          Date     = as.Date(ds, "%Y%m%d"),
          BM_Close = as.numeric(gsub(",", "", k200$CLSPRC_IDX[1]))
        )
      }
    }
  }

  if (length(idx_list) == 0) return(NULL)
  bm_new <- rbindlist(idx_list)
  setorder(bm_new, Date)
  bm_new
}

#──────────────────────────────────────────────────────────────────────────────
# 4. Merge new data into RAWDATA.parquet
#──────────────────────────────────────────────────────────────────────────────
krx_merge_rawdata <- function() {
  gap <- krx_detect_gap()
  if (gap$n_calendar_days <= 0) {
    cat("[krx_merge] RAWDATA is up to date.\n")
    return(invisible(NULL))
  }

  dates <- seq(as.Date(gap$start, "%Y%m%d"), as.Date(gap$end, "%Y%m%d"), by = "day")
  # [Track R fix 2026-06-12] locale 무관 주말 필터 (한국어 locale에서 weekdays() 비교 무력)
  dates <- dates[!as.POSIXlt(dates)$wday %in% c(0L, 6L)]
  date_strs <- format(dates, "%Y%m%d")

  # Filter out known holidays
  date_strs <- date_strs[!sapply(date_strs, .krx_is_holiday)]

  # Transform each date
  cat(sprintf("[krx_merge] Transforming %d dates...\n", length(date_strs)))
  new_rows <- rbindlist(lapply(date_strs, function(ds) {
    tryCatch(krx_transform_daily(ds), error = function(e) {
      cat(sprintf("  [WARN] Transform failed for %s: %s\n", ds, e$message))
      NULL
    })
  }), fill = TRUE)

  if (is.null(new_rows) || nrow(new_rows) == 0) {
    cat("[krx_merge] No new data to merge.\n")
    return(invisible(NULL))
  }

  # Load existing RAWDATA — accept new tickers (신규 상장 반영)
  old_raw <- as.data.table(read_parquet(RAWDATA_CACHE))
  known_tickers <- unique(old_raw$Ticker)
  new_tickers <- setdiff(unique(new_rows$Ticker), known_tickers)
  if (length(new_tickers) > 0) {
    cat(sprintf("[krx_merge] New tickers detected: %d (e.g. %s)\n",
                length(new_tickers), paste(head(new_tickers, 5), collapse = ", ")))
  }
  cat(sprintf("[krx_merge] Total tickers: %d (existing %d + new %d)\n",
              uniqueN(new_rows$Ticker), length(known_tickers), length(new_tickers)))

  # Compute daily returns per ticker
  # Get previous Close from existing RAWDATA for the first day
  last_closes <- old_raw[Date == max(Date), .(Ticker, Prev_Close = Close)]
  setorder(new_rows, Ticker, Date)

  # For each ticker, compute Ret = Close / lag(Close) - 1
  new_rows[, Ret := Close / shift(Close) - 1, by = Ticker]
  # Fix first day: use previous RAWDATA Close
  first_day <- min(new_rows$Date)
  first_rows <- new_rows[Date == first_day]
  first_rows <- merge(first_rows, last_closes, by = "Ticker", all.x = TRUE)
  first_rows[!is.na(Prev_Close) & Prev_Close > 0, Ret := Close / Prev_Close - 1]
  new_rows[Date == first_day, Ret := first_rows[match(new_rows[Date == first_day, Ticker], Ticker), Ret]]

  # Compute BM_Ret from KOSPI 200 index
  bm_new <- krx_compute_bm_ret(date_strs)
  if (!is.null(bm_new) && nrow(bm_new) > 0) {
    # Get previous BM_Close for first day's return
    old_bm <- as.data.table(read_parquet(BM_CACHE))
    # [fix 2026-06-17] benchmark.parquet Date가 [1pre] naver_benchmark_update.py에서
    # POSIXct(09:00:00)로 기록되며, bm_new/new_rows의 Date(as.Date)와 class가 달라
    # line 223 merge / line 228 rbind이 "Class attribute on column 1" halt → KRX 전체
    # 파이프라인 abort → RAWDATA가 매일 06-12에서 동결되던 회귀버그. 양쪽 Date로 정규화.
    if (inherits(old_bm$Date, "POSIXt") || !inherits(old_bm$Date, "Date"))
      old_bm[, Date := as.Date(Date)]
    last_bm_close <- old_bm[Date == max(Date)]$BM_Close[1]

    bm_new[, BM_Ret := BM_Close / shift(BM_Close) - 1]
    if (!is.na(last_bm_close) && last_bm_close > 0) {
      bm_new[1, BM_Ret := BM_Close / last_bm_close - 1]
    }

    # [fix 2026-07-05, 재오염 방지 가드] KOSPI200 일간 |BM_Ret|>0.30은 물리적 불가
    #   (2020 COVID 최악 일간 ~-8%). krx_compute_bm_ret 독립계산이 canonical benchmark
    #   (build_index_cache.py)와 스케일 불일치(구 IKS001↔IKS200 등) 시 이상치 발생 →
    #   RAWDATA + benchmark.parquet(line 234 rbind) 양쪽 오염. NA 처리로 전파 차단
    #   (→ 하단 sentinel 0 폴백 + canonical benchmark 재동기화가 정정).
    #   근원 사고: 2026-07-01 BM_Ret 5.39 (last_bm_close가 구 IKS001 스케일).
    # ★2026-09-18 축 정규화 후: 이 가드가 **상시 발화하던 원인이 사라졌다**. 여기서 쓰는
    #   BM_Close 는 KRX CLSPRC_IDX(생 포인트)인데 저장된 last_bm_close 가 8.83배 체인이라
    #   첫날 BM_Ret 이 항상 ~-88.7% 로 나왔고 → NA → 하단 sentinel 0 으로 굳었다
    #   (= KRX 로 메운 날의 벤치 수익률이 조용히 0 이 됐다). 두 쪽이 같은 축이 된 지금은
    #   그 비율이 진짜 수익률이므로 가드는 본래 표적(오심볼·기준단절)만 잡는다.
    n_insane <- sum(abs(bm_new$BM_Ret) > 0.30, na.rm = TRUE)
    if (n_insane > 0) {
      cat(sprintf("[krx_merge][GUARD] |BM_Ret|>0.30 이상치 %d건 (스케일 불일치 의심, 값: %s) → NA 처리, benchmark 전파 차단\n",
                  n_insane, paste(round(bm_new[abs(BM_Ret) > 0.30]$BM_Ret, 3), collapse = ", ")))
      bm_new[abs(BM_Ret) > 0.30, BM_Ret := NA_real_]
    }

    # Join BM_Ret to new_rows
    new_rows <- merge(new_rows, bm_new[, .(Date, BM_Ret)], by = "Date", all.x = TRUE,
                      suffixes = c(".old", ""))
    if ("BM_Ret.old" %in% names(new_rows)) new_rows[, BM_Ret.old := NULL]

    # Update benchmark cache
    # ★2026-09-18: provenance 열을 채운다 — 안 채우면 fill=TRUE 가 조용히 NA 를 넣는다.
    #   (KRX CLSPRC_IDX = 공표 코스피200 포인트. 축은 정본 xlsx 와 같다.)
    if ("BM_Src" %in% names(old_bm)) bm_new[, BM_Src := "krx_kospi200"]
    old_bm_ext <- rbind(old_bm, bm_new[!is.na(BM_Ret)], fill = TRUE)
    old_bm_ext <- unique(old_bm_ext, by = "Date")
    setorder(old_bm_ext, Date)
    setkey(old_bm_ext, Date)
    # [fix 2026-06-17] Windows arrow mmap(error 1224): read_parquet(BM_CACHE)가 파일을
    # mmap한 채라 동일 경로 write_parquet이 실패 → temp-rename 으로 회피.
    # [fix 2026-08-30] ★선삭제 제거 — 구판은 tmp 로 쓴 뒤 **본 파일을 지우고** rename 했다.
    #   file.rename 은 대상이 존재해도 덮어쓰므로 선삭제는 얻는 게 0이고, 삭제~rename 사이에
    #   **파일 부재 창**을 만든다. 2026-08-29 23:27 실사고: 그 창에서 프로세스가 죽어
    #   benchmark.parquet 이 부재로 남았고 하류가 정지했다([bm-gate][B] 거래일 판정 불가 /
    #   regime_jump_model Windows error 2). 게다가 rename 실패(소비자 핸들 점유)를
    #   반환값 무시로 삼켜 **갱신 유실이 조용했다**. 공용 정본으로 교체 — 선삭제 없음 +
    #   유한 재시도 + 실패 시 stop(원본 보존). copy 폴백은 절단원이라 쓰지 않는다.
    #   근거: 02_Infrastructure/utils/atomic_parquet.R [측정 1][측정 4]
    if (!exists("qvest_atomic_write_parquet"))
      source(file.path(PROJECT_ROOT, "02_Infrastructure/utils/atomic_parquet.R"))
    rm(old_bm); gc(verbose = FALSE)
    qvest_atomic_write_parquet(old_bm_ext, BM_CACHE, tag = "krx_merge/bm")
    cat(sprintf("[krx_merge] Benchmark updated: %s ~ %s\n",
                min(old_bm_ext$Date), max(old_bm_ext$Date)))
  } else {
    new_rows[, BM_Ret := NA_real_]
    cat("[krx_merge] WARNING: No KOSPI 200 index data. BM_Ret = NA.\n")
  }

  # BM_Ret fallback: NA면 0 sentinel (날짜 전체 삭제 방지)
  bm_na <- sum(is.na(new_rows$BM_Ret))
  if (bm_na > 0) {
    cat(sprintf("[krx_merge] BM_Ret NA: %d rows → sentinel 0 적용 (삭제 안 함)\n", bm_na))
    new_rows[is.na(BM_Ret), BM_Ret := 0]
  }

  # Ret NA만 제거 (BM_Ret는 sentinel 처리했으므로 제거 안 함)
  new_rows <- new_rows[!is.na(Ret)]

  # 거래일 검증 gate
  if (exists("is_trading_day")) {
    non_td <- new_rows[!sapply(Date, is_trading_day)]
    if (nrow(non_td) > 0) {
      cat(sprintf("[krx_merge] 비거래일 %d rows 차단\n", nrow(non_td)))
      new_rows <- new_rows[sapply(Date, is_trading_day)]
    }
  }

  # source 태그
  if (!"source" %in% names(new_rows)) new_rows[, source := "krx_api"]

  # Ensure column order matches RAWDATA
  rawdata_cols <- c("Date", "BM_Ret", "Ticker", "Name", "Market", "Sector",
                    "Open", "High", "Low", "Close", "Vol", "Size", "Ret", "source")
  # Keep only existing columns
  keep_cols <- intersect(rawdata_cols, names(new_rows))
  new_rows <- new_rows[, ..keep_cols]

  # Add missing columns as NA
  for (col in setdiff(rawdata_cols, names(new_rows))) {
    new_rows[, (col) := NA]
  }
  # ★NA-fill 루프가 source 를 NA 로 채우고 지나갈 수 있다(위 태그가 조건부라서).
  #   라벨 NA 는 우선순위 판정에서 '모른다' = stop 이고, 그러면 일일 배관이 죽는다.
  #   이 writer 가 만든 행의 출처는 아는 값이므로 여기서 되찍는다(추측이 아니라 사실).
  if (nrow(new_rows)) new_rows[is.na(source) | !nzchar(as.character(source)), source := "krx_api"]
  setcolorder(new_rows, rawdata_cols)

  # Append to existing RAWDATA
  # ignore.attr=TRUE: 무신규 데이터일(주말/휴장, new 0 tickers) 컬럼 class-attr 불일치로
  # rbindlist halt 나던 것 방지 (값은 동일 날짜형, attr만 상이; 아래 unique/setorder가 정합). 2026-06-13
  combined <- rbind(old_raw, new_rows, fill = TRUE, ignore.attr = TRUE)
  # ── 원천 우선순위 경유 (2026-09-07 도훈 지시) ─────────────────────────────
  #   구판은 `unique(combined, by=c("Date","Ticker"))` 였다. unique() 는 **첫 행**을
  #   남기므로 old_raw 가 이기는데, 그건 규칙이 아니라 rbind 인자 순서라는 우연이다.
  #   순서를 한 줄 바꾸면 판정이 조용히 뒤집힌다. 승패는 정본이 정한다:
  #   06_Registry/rawdata_source_priority.json (krx_api = 퇴역 임시 레인 = 최하위).
  #   ★빈 자리(gap 메우기)는 incumbent 가 없으므로 그대로 채워진다 — 이 경로의 본래 목적.
  if (!exists("rawdata_priority_dedup")) source(file.path(DATA_DIR, "rawdata_source_priority.R"))
  .ded <- rawdata_priority_dedup(combined, context = "krx_merge/rawdata")
  if (.ded$n_dropped > 0L) {
    cat(sprintf("[krx_merge] 우선순위 중복 해소: %s행 제거\n",
                format(.ded$n_dropped, big.mark = ",")))
    print(.ded$dropped_by)
  }
  combined <- .ded$dt
  setorder(combined, Date, Ticker)

  # [fix 2026-06-17] Windows arrow mmap(error 1224): read_parquet(RAWDATA_CACHE) mmap
  # 해제 후 temp-rename. (구 직접 write_parquet은 동일 경로 mmap halt — benchmark와 동일)
  # [fix 2026-08-30] 위 BM 쓰기와 **같은 함수·같은 병** — 선삭제 제거 + 실패 fail-loud.
  #   공용 정본 = 02_Infrastructure/utils/atomic_parquet.R
  if (!exists("qvest_atomic_write_parquet"))
    source(file.path(PROJECT_ROOT, "02_Infrastructure/utils/atomic_parquet.R"))
  rm(old_raw); gc(verbose = FALSE)
  qvest_atomic_write_parquet(combined, RAWDATA_CACHE, tag = "krx_merge/rawdata")

  cat(sprintf("[krx_merge] RAWDATA extended: +%d rows | now %s ~ %s | %d total\n",
              nrow(new_rows), min(combined$Date), max(combined$Date), nrow(combined)))

  invisible(combined)
}

#──────────────────────────────────────────────────────────────────────────────
# 5. Orchestrator: full pipeline
#──────────────────────────────────────────────────────────────────────────────
krx_run_pipeline <- function() {
  cat("=== KRX Data Pipeline ===\n")

  # 1. Detect gap
  gap <- krx_detect_gap()
  cat(sprintf("Last RAWDATA date: %s\n", gap$last_rawdata_date))
  cat(sprintf("Target range: %s ~ %s (%d calendar days)\n",
              gap$start, gap$end, gap$n_calendar_days))

  if (gap$n_calendar_days <= 0) {
    cat("[pipeline] RAWDATA is already up to date.\n")
    return(invisible(NULL))
  }

  # 2. Collect from KRX API
  cat("\n[Step 1/3] Collecting from KRX API...\n")
  krx_collect_range(gap$start, gap$end)

  # 3. Transform + Merge
  cat("\n[Step 2/3] Transforming and merging...\n")
  result <- krx_merge_rawdata()

  # 4. Validate
  cat("\n[Step 3/3] Validation...\n")
  raw <- as.data.table(read_parquet(RAWDATA_CACHE))
  cat(sprintf("  RAWDATA: %d rows | %d tickers | %s ~ %s\n",
              nrow(raw), uniqueN(raw$Ticker), min(raw$Date), max(raw$Date)))

  # Spot-check: last 3 dates
  last_dates <- tail(sort(unique(raw$Date)), 3)
  for (d in last_dates) {
    n <- nrow(raw[Date == d])
    cat(sprintf("  %s: %d tickers\n", d, n))
  }

  cat("\n=== KRX Pipeline Complete ===\n")
  invisible(result)
}

cat("[krx_build_rawdata] Loaded.\n")
