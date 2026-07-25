#==============================================================================
# Incremental Update File — Update_File 증분 파서
#
# 03_Universe/Update_File/*_update.xlsx → RAWDATA/consensus/investor 증분 갱신
# QuantiWise 증분 도착 시 KRX/Naver 임시 데이터 완벽 교체
# Factor DB는 이 함수 완료 후에만 재빌드 (Level 0 규칙)
#
# 사용법:
#   source("02_Infrastructure/incremental_update_file.R")
#   result <- incremental_update_all()  # 전체 자동
#   result <- incremental_ohlcvs()      # OHLCVS만
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(readxl)
})

if (!exists("PROJECT_ROOT")) source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
if (!exists("is_trading_day")) source(file.path(DATA_DIR, "trading_calendar.R"))

UPDATE_DIR <- file.path(PROJECT_ROOT, "03_Universe", "Update_File")
LAST_PROCESSED_FILE <- file.path(CACHE_DIR, "update_file_last_processed.rds")

# ─── Internal: 마지막 처리 시각 ──────────────────────────────────────────────
.get_last_processed <- function() {
  if (file.exists(LAST_PROCESSED_FILE)) readRDS(LAST_PROCESSED_FILE)
  else list(time = as.POSIXct("1970-01-01"), files = list())
}

.save_last_processed <- function(file_mtimes) {
  saveRDS(list(time = Sys.time(), files = file_mtimes), LAST_PROCESSED_FILE)
}

# ─── Internal: Update_File 변경 감지 ─────────────────────────────────────────
detect_update_changes <- function() {
  if (!dir.exists(UPDATE_DIR)) return(list(changed = character(0)))

  update_files <- list.files(UPDATE_DIR, pattern = "\\.xlsx$", full.names = TRUE)
  if (length(update_files) == 0) return(list(changed = character(0)))

  last <- .get_last_processed()
  changed <- character(0)
  current_mtimes <- list()

  for (f in update_files) {
    mt <- file.mtime(f)
    current_mtimes[[basename(f)]] <- mt
    prev_mt <- last$files[[basename(f)]]
    if (is.null(prev_mt) || mt > prev_mt) {
      changed <- c(changed, f)
    }
  }

  list(changed = changed, mtimes = current_mtimes)
}

# ─── OHLCVS 증분 ────────────────────────────────────────────────────────────
incremental_ohlcvs <- function() {
  ohlcvs_update <- file.path(UPDATE_DIR, "OHLCVS_update.xlsx")
  if (!file.exists(ohlcvs_update)) {
    cat("[incr_ohlcvs] OHLCVS_update.xlsx 없음. 스킵.\n")
    return(invisible(NULL))
  }

  cat("[incr_ohlcvs] OHLCVS_update.xlsx 증분 처리...\n")

  RAWDATA_CACHE <- file.path(CACHE_DIR, "rawdata.parquet")
  raw <- as.data.table(read_parquet(RAWDATA_CACHE))

  # base max date = OHLCVS.xlsx (base 파일)의 max date
  # Update_File은 항상 base 이후 전부 추출하여 교체
  base_ohlcvs <- file.path(PROJECT_ROOT, "03_Universe", "OHLCVS.xlsx")
  base_dates <- .extract_qw_dates(base_ohlcvs)
  base_max <- max(base_dates)
  cat(sprintf("  base max date (OHLCVS.xlsx): %s\n", base_max))

  # Update xlsx 파싱 (6 시트) — QT_to_xts 우회, 직접 파싱
  # (QT_to_xts는 xts의 TZ 변환에서 1일 밀림 버그 발생)
  var_names <- c("Open", "High", "Low", "Close", "Vol", "Size")
  all_long <- NULL

  for (i in seq_along(var_names)) {
    cat(sprintf("  Sheet %d/6: %s...\n", i, var_names[i]))
    raw_df <- as.data.frame(read_xlsx(ohlcvs_update, sheet = i, skip = 7,
                                       col_names = TRUE, na = c("", "NA")))
    # 첫 5행 스킵 (Name, Item Code, Unit, Base Date, D A T E)
    raw_df <- raw_df[-1:-5, ]

    # 첫 열 = Date serial, 나머지 = Ticker 값
    serials <- suppressWarnings(as.numeric(raw_df[[1]]))
    dates <- as.Date(serials, origin = "1899-12-30")

    ticker_cols <- names(raw_df)[-1]
    vals <- as.data.table(raw_df[, -1])
    vals <- vals[, lapply(.SD, as.numeric)]
    vals[, Date := dates]

    long <- melt(vals, id.vars = "Date", variable.name = "Ticker",
                 value.name = var_names[i], variable.factor = FALSE)
    long <- long[!is.na(Date) & Date > base_max]
    rm(raw_df, vals); gc()

    if (is.null(all_long)) {
      all_long <- long
    } else {
      all_long <- merge(all_long, long, by = c("Date", "Ticker"), all = TRUE)
    }
    rm(long); gc()
  }

  if (is.null(all_long) || nrow(all_long) == 0) {
    cat("  증분 데이터 없음.\n")
    return(invisible(NULL))
  }

  # 거래일 필터
  cal <- .load_calendar()
  before_n <- nrow(all_long)
  all_long <- all_long[Date %in% cal$Date]
  cat(sprintf("  거래일 필터: %d → %d rows\n", before_n, nrow(all_long)))

  # [guard 2026-07-11] 수출 이음매 검증 — update 최소일이 base 직후 거래일보다 뒤면
  # base/update 커버리지 사이에 구멍(실사고: base ~03-27 + update 04-30~ → 03-30~04-29
  # 소실, rawdata_april_gap_incident_20260711). rawdata가 그 구간을 보유하면 WARN만
  # (본 함수는 update 날짜만 교체하므로 데이터 안전), 미보유면 강한 경고.
  if (nrow(all_long) > 0) {
    upd_min <- min(all_long$Date)
    seam_days <- as.Date(cal[Date > base_max & Date < upd_min]$Date)
    if (length(seam_days) > 0) {
      seam_missing <- seam_days[!seam_days %in% unique(raw$Date)]
      cat(sprintf("  ⚠️ [이음매] base(~%s)와 update(%s~) 사이 거래일 %d일 — QuantiWise 수출 커버리지 구멍.\n",
                  base_max, upd_min, length(seam_days)))
      if (length(seam_missing) > 0) {
        cat(sprintf("  ⛔ [이음매] 그중 %d일은 rawdata에도 부재 (%s ~ %s) — KRX 백필 또는 QuantiWise 재수출(B5=%s) 필요!\n",
                    length(seam_missing), min(seam_missing), max(seam_missing),
                    format(base_max + 1, "%Y%m%d")))
      } else {
        cat("     rawdata는 해당 구간 보유 (KRX/Naver 수집분) — 데이터 안전. 근본 해소는 QuantiWise 재수출.\n")
      }
    }
  }

  # 유효 행만 (Close > 0)
  all_long <- all_long[!is.na(Close) & Close > 0]

  # source 태그
  all_long[, source := "quantiwise_update"]

  # 기존 RAWDATA에서 증분 구간의 임시 데이터 제거
  update_dates <- unique(all_long$Date)
  n_replaced <- raw[Date %in% update_dates, .N]
  raw <- raw[!Date %in% update_dates]
  cat(sprintf("  기존 데이터 교체: %s rows (날짜 %d일)\n",
              format(n_replaced, big.mark = ","), length(update_dates)))

  # Append
  # 컬럼 맞추기
  for (col in setdiff(names(raw), names(all_long))) {
    all_long[, (col) := NA]
  }
  for (col in setdiff(names(all_long), names(raw))) {
    raw[, (col) := NA]
  }
  common_cols <- intersect(names(raw), names(all_long))
  raw <- rbind(raw[, ..common_cols], all_long[, ..common_cols], fill = TRUE)

  # Ret 재계산
  setorder(raw, Ticker, Date)
  raw[, Ret := Close / shift(Close) - 1, by = Ticker]

  # BM_Ret 매핑
  bm <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
  # [guard 2026-07-18] benchmark.parquet Date가 writer(naver_benchmark_update.py)에 따라
  # POSIXct(timestamp)일 수 있음 → Date-class인 raw$Date와 by="Date" 조인 시 silent all-NA →
  # RAWDATA.BM_Ret 14M행 전멸 후 write-back 위험. 양측 Date를 Date-class로 강제(build_cache/phase7 동일).
  bm[, Date := as.Date(Date)]
  raw[, Date := as.Date(Date)]
  raw[, BM_Ret := NULL]
  raw <- merge(raw, bm[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)

  # 저장
  setorder(raw, Date, Ticker)
  write_parquet(raw, RAWDATA_CACHE)

  cat(sprintf("[incr_ohlcvs] 완료: %s rows | %s ~ %s\n",
              format(nrow(raw), big.mark = ","),
              min(raw$Date), max(raw$Date)))

  invisible(list(dates_updated = update_dates, rows = nrow(all_long)))
}

# ─── Consensus 증분 ──────────────────────────────────────────────────────────
incremental_consensus <- function() {
  cons_update <- file.path(UPDATE_DIR, "Consensus_update.xlsx")
  if (!file.exists(cons_update)) {
    cat("[incr_consensus] Consensus_update.xlsx 없음. 스킵.\n")
    return(invisible(NULL))
  }

  cat("[incr_consensus] Consensus_update.xlsx 증분 처리...\n")
  cons_cache_dir <- file.path(CACHE_DIR, "consensus")

  # 기존 캐시의 max date
  ref_file <- file.path(cons_cache_dir, "eps_1y.parquet")
  if (!file.exists(ref_file)) {
    cat("  기존 캐시 없음. base Consensus.xlsx부터 빌드 필요.\n")
    return(invisible(NULL))
  }
  ref <- as.data.table(read_parquet(ref_file))
  base_max <- max(ref$Date, na.rm = TRUE)
  cat(sprintf("  기존 캐시 max: %s\n", base_max))

  # Update_File을 임시 파싱 → base_max 이후만 추출 → 기존 캐시에 append
  source(file.path(DATA_DIR, "consensus_parser.R"))

  # 임시 디렉토리에 Update_File 파싱
  tmp_dir <- file.path(CACHE_DIR, "consensus_tmp")
  dir.create(tmp_dir, showWarnings = FALSE)

  old_cache <- CONSENSUS_CACHE
  CONSENSUS_CACHE <<- tmp_dir
  old_xlsx <- CONSENSUS_XLSX
  CONSENSUS_XLSX <<- cons_update

  tryCatch({
    consensus_build_cache(force = TRUE)

    # 각 metric의 증분만 기존 캐시에 append
    tmp_files <- list.files(tmp_dir, pattern = "\\.parquet$", full.names = TRUE)
    for (tf in tmp_files) {
      metric <- basename(tf)
      orig_file <- file.path(cons_cache_dir, metric)

      tmp_dt <- as.data.table(read_parquet(tf))
      new_rows <- tmp_dt[Date > base_max]

      if (nrow(new_rows) > 0 && file.exists(orig_file)) {
        orig_dt <- as.data.table(read_parquet(orig_file))
        # 겹치는 날짜 제거 후 append
        orig_dt <- orig_dt[!Date %in% unique(new_rows$Date)]
        combined <- rbind(orig_dt, new_rows, fill = TRUE)
        setorder(combined, Date)
        # [2026-06-17 fix] Windows arrow mmap-on-write 잠금(error 1224) 회피:
        #   read_parquet(orig)의 mmap을 rm+gc로 해제 후, temp 파일에 쓰고 rename으로 원자 교체.
        rm(orig_dt); gc()
        .tmp_out <- paste0(orig_file, ".tmp")
        write_parquet(combined, .tmp_out)
        if (file.exists(orig_file)) file.remove(orig_file)
        file.rename(.tmp_out, orig_file)
        cat(sprintf("  %s: +%d rows (max: %s)\n", metric, nrow(new_rows), max(combined$Date)))
      }
    }

    # 임시 디렉토리 정리
    unlink(tmp_dir, recursive = TRUE)
    cat("[incr_consensus] 증분 완료.\n")
  }, error = function(e) {
    cat(sprintf("[incr_consensus] 오류: %s\n", e$message))
    unlink(tmp_dir, recursive = TRUE)
  }, finally = {
    CONSENSUS_CACHE <<- old_cache
    CONSENSUS_XLSX <<- old_xlsx
  })
}

# ─── Investor_Act 증분 ───────────────────────────────────────────────────────
incremental_investor <- function() {
  inv_update <- file.path(UPDATE_DIR, "Investor_Act_update.xlsx")
  if (!file.exists(inv_update)) {
    cat("[incr_investor] Investor_Act_update.xlsx 없음. 스킵.\n")
    return(invisible(NULL))
  }

  cat("[incr_investor] Investor_Act_update.xlsx 증분 처리...\n")

  inv_cache_dir <- file.path(CACHE_DIR, "investor_stock")
  if (!dir.exists(inv_cache_dir)) dir.create(inv_cache_dir, recursive = TRUE)

  # 기존 캐시 max date
  all_file <- file.path(inv_cache_dir, "investor_all.parquet")
  if (file.exists(all_file)) {
    existing <- as.data.table(read_parquet(all_file))
    base_max <- max(existing$Date, na.rm = TRUE)
    cat(sprintf("  기존 캐시 max: %s (%s rows)\n", base_max, format(nrow(existing), big.mark = ",")))
  } else {
    existing <- NULL
    base_max <- as.Date("2026-03-27")
    cat(sprintf("  기존 캐시 없음. base_max: %s\n", base_max))
  }

  # 4시트 직접 파싱 (QT_to_xts 우회, 5행 스킵)
  sheet_map <- list("외인" = "Foreign", "기관" = "Institutional",
                    "개인" = "Individual", "기타법인" = "OtherCorp")
  all_new <- list()

  for (sheet_name in names(sheet_map)) {
    cat(sprintf("  시트 '%s'...\n", sheet_name))
    raw_df <- as.data.frame(read_xlsx(inv_update, sheet = sheet_name, skip = 7,
                                       col_names = TRUE, na = c("", "NA")))
    raw_df <- raw_df[-1:-5, ]  # 5행 스킵 (Update_File 공통 형태)

    serials <- suppressWarnings(as.numeric(raw_df[[1]]))
    dates <- as.Date(serials, origin = "1899-12-30")

    vals <- as.data.table(raw_df[, -1])
    vals <- vals[, lapply(.SD, as.numeric)]
    vals[, Date := dates]

    long <- melt(vals, id.vars = "Date", variable.name = "Ticker",
                 value.name = "NetBuy", variable.factor = FALSE)
    long <- long[!is.na(Date) & Date > base_max & !is.na(NetBuy) & NetBuy != 0]
    long[, InvestorType := sheet_map[[sheet_name]]]

    if (nrow(long) > 0) all_new[[length(all_new) + 1]] <- long
    cat(sprintf("    %d rows (> %s)\n", nrow(long), base_max))
    rm(raw_df, vals, long); gc()
  }

  if (length(all_new) == 0) {
    cat("  증분 데이터 없음.\n")
    return(invisible(NULL))
  }

  new_dt <- rbindlist(all_new)

  # 기존 캐시에 append (겹치는 날짜 교체)
  if (!is.null(existing)) {
    existing <- existing[!Date %in% unique(new_dt$Date)]
    combined <- rbind(existing, new_dt, fill = TRUE)
  } else {
    combined <- new_dt
  }
  setorder(combined, Date, Ticker, InvestorType)
  write_parquet(combined, all_file)

  # [2026-07-17 배관수리] 파생 파일 동반 재생성 — 기존엔 investor_all만 갱신되고
  # per-type 분리 파일(investor_foreign/institutional/individual/othercorp.parquet)과
  # investor_wide.parquet는 full 파서(parse_investor_act)에서만 쓰여 영구 stale
  # (실측: all=2026-07-01 vs 분리=2026-03-26 → flow_features_daily 113d stale의 원인).
  for (itype in unique(combined$InvestorType)) {
    split_path <- file.path(inv_cache_dir, sprintf("investor_%s.parquet", tolower(itype)))
    write_parquet(combined[InvestorType == itype], split_path)
  }
  wide <- dcast(combined, Date + Ticker ~ InvestorType, value.var = "NetBuy", fill = 0)
  write_parquet(wide, file.path(inv_cache_dir, "investor_wide.parquet"))
  cat(sprintf("  파생 재생성: 분리 %d종 + wide (max: %s)\n",
              uniqueN(combined$InvestorType), max(combined$Date)))

  cat(sprintf("[incr_investor] 완료: +%s rows → 총 %s rows (max: %s)\n",
              format(nrow(new_dt), big.mark = ","),
              format(nrow(combined), big.mark = ","),
              max(combined$Date)))
}

# ─── Universe_Support 증분 ───────────────────────────────────────────────────
# [2026-07-25 W3 재작성 — D1 적발 결함 수리]
#   구 구현 = parse_universe_support(us_update) 호출:
#     · force=FALSE(기본) → 캐시 존재 시 전 시트 skip = 영구 no-op (증분 미반영)
#     · force=TRUE → update xlsx(스냅샷 수 개)만으로 패널 통째 덮어쓰기
#       = 1990~ 역사 소실 clobber
#   신 구현 = us_update_merge.py (openpyxl 스트리밍 — 484MB XML-bloat xlsx라
#   R openxlsx/readxl 회피, D1 실측 완주 경로) 위임:
#     ① cache-hit 판정 = 시트별 update max Date > 패널 max Date일 때만 진행
#     ② merge = 겹침 날짜만 교체 후 rbind (역사 보존)
#     ③ 디스크 시맨틱 컬럼명('K200' 등) 기준 정합 (레거시 'Value' 자동 정규화)
#     ④ temp-rename 쓰기
incremental_universe_support <- function(force = FALSE) {
  us_update <- file.path(UPDATE_DIR, "Universe_Support_update.xlsx")
  if (!file.exists(us_update)) {
    cat("[incr_universe_support] Universe_Support_update.xlsx 없음. 스킵.\n")
    return(invisible(NULL))
  }

  cat("[incr_universe_support] Universe_Support_update.xlsx 증분 merge...\n")

  # python 선택: pyarrow+openpyxl 필요 → 표준 venv(.venv_qvest_ml, python-policy §2)
  # 우선. QVEST_PY(시스템 Python312)는 pyarrow 부재 실측(2026-07-25) — fallback만.
  venv_py <- file.path(PROJECT_ROOT, ".venv_qvest_ml/Scripts/python.exe")
  pyexe <- if (file.exists(venv_py)) venv_py else Sys.getenv("QVEST_PY", venv_py)
  helper <- file.path(DATA_DIR, "us_update_merge.py")
  us_cache <- if (exists("UNIVERSE_SUPPORT_CACHE")) UNIVERSE_SUPPORT_CACHE
              else file.path(CACHE_DIR, "universe_support")

  args <- c(shQuote(helper),
            "--xlsx", shQuote(us_update),
            "--cache", shQuote(us_cache))
  if (isTRUE(force)) args <- c(args, "--force")

  out <- suppressWarnings(system2(pyexe, args = args, stdout = TRUE, stderr = TRUE))
  rc <- attr(out, "status") %||% 0L
  cat(paste(out, collapse = "\n"), "\n")

  if (rc != 0) {
    cat(sprintf("[incr_universe_support] 오류: us_update_merge.py 실패 (rc=%d)\n", rc))
  } else {
    cat("[incr_universe_support] 완료.\n")
  }
  invisible(rc == 0)
}

# ─── 전체 증분 실행 ──────────────────────────────────────────────────────────
incremental_update_all <- function() {
  cat("=== Incremental Update_File 처리 시작 ===\n\n")

  changes <- detect_update_changes()
  if (length(changes$changed) == 0) {
    cat("Update_File 변경 없음.\n")
    return(invisible(list(updated = FALSE)))
  }

  cat(sprintf("변경 감지: %d 파일\n", length(changes$changed)))
  for (f in changes$changed) cat(sprintf("  → %s\n", basename(f)))
  cat("\n")

  ohlcvs_result <- NULL
  qw_updated <- FALSE

  # OHLCVS
  if (any(grepl("OHLCVS", changes$changed))) {
    ohlcvs_result <- incremental_ohlcvs()
    qw_updated <- TRUE
  }

  # Consensus
  if (any(grepl("Consensus", changes$changed))) {
    incremental_consensus()
    qw_updated <- TRUE
  }

  # Investor_Act
  if (any(grepl("Investor", changes$changed))) {
    incremental_investor()
  }

  # Universe_Support
  if (any(grepl("Universe_Support", changes$changed))) {
    incremental_universe_support()
  }

  # 처리 완료 기록
  .save_last_processed(changes$mtimes)

  cat("\n=== Incremental Update 완료 ===\n")
  invisible(list(updated = TRUE, qw_updated = qw_updated, ohlcvs = ohlcvs_result))
}

cat("[incremental_update_file] Loaded. Functions: incremental_update_all(), incremental_ohlcvs(), detect_update_changes()\n")
