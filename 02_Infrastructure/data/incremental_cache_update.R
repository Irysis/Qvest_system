#==============================================================================
# Incremental Cache Update v2 — QuantiWise xlsx → parquet
#
# xlsx mtime 비교 → 변경 시만 증분/리빌드.
# OHLCVS = 수정주가 → 전체 리빌드 + API 데이터 보존
# Consensus/Investor/Fundamental/Universe_Support = 증분 append
#
# Usage:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/incremental_cache_update.R")
#   incremental_update_all()
#==============================================================================

library(data.table)
library(arrow)
library(openxlsx)

# config.R에서 이미 정의된 경로 사용 (fallback)
if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
  source(file.path(PROJECT_ROOT, "02_Infrastructure", "config.R"))
}

# ─── Helper ──────────────────────────────────────────────────────────────────
.get_max_date <- function(pq_path, date_col = "Date") {
  if (!file.exists(pq_path)) return(as.Date("1900-01-01"))
  dt <- as.data.table(read_parquet(pq_path, col_select = date_col))
  dt[[date_col]] <- as.Date(dt[[date_col]])
  max(dt[[date_col]], na.rm = TRUE)
}

.xlsx_newer <- function(xlsx_path, ref_path) {
  if (!file.exists(xlsx_path)) return(FALSE)
  if (!file.exists(ref_path)) return(TRUE)
  file.mtime(xlsx_path) > file.mtime(ref_path)
}

# ─── 1. RAWDATA (OHLCVS.xlsx) ───────────────────────────────────────────────
# 수정주가 → 전체 리빌드 필수. 리빌드 후 기존 API 데이터(KRX/Naver) 보존.
incremental_rawdata <- function() {
  ohlcvs_xlsx <- file.path(RAWDATA_PATH, "OHLCVS.xlsx")

  if (!.xlsx_newer(ohlcvs_xlsx, RAWDATA_CACHE)) {
    cat("[incr] OHLCVS.xlsx not newer — skip.\n")
    return(invisible(FALSE))
  }

  # 기존 API 데이터 보존 (xlsx max date 이후)
  old_api_data <- NULL
  if (file.exists(RAWDATA_CACHE)) {
    cat("[incr] Saving API data (KRX/Naver) before rebuild...\n")
    old_raw <- as.data.table(read_parquet(RAWDATA_CACHE))
    old_raw[, Date := as.Date(Date)]
    old_max <- max(old_raw$Date)
  }

  # xlsx 전체 리빌드 (수정주가)
  cat("[incr] OHLCVS.xlsx updated — full rebuild (adjusted prices).\n")
  source(file.path(DATA_DIR, "build_cache.R"))

  # 리빌드 후 API 데이터 복원 (xlsx max date 이후)
  if (!is.null(old_raw) && file.exists(RAWDATA_CACHE)) {
    new_raw <- as.data.table(read_parquet(RAWDATA_CACHE))
    new_raw[, Date := as.Date(Date)]
    xlsx_max <- max(new_raw$Date)

    api_only <- old_raw[Date > xlsx_max]
    if (nrow(api_only) > 0) {
      # ── 원천 라벨 복구 ────────────────────────────────────────────────────
      #   build_cache.R 은 base xlsx 를 그대로 세우고 `source` 를 찍지 않는다(라벨은
      #   rawdata_sanitize.R Step 7 이 나중에 "quantiwise" 로 채운다). 라벨 없이 병합하면
      #   우선순위를 판정할 축이 없다 — 여기서 같은 기본값으로 복구한다(관측이 아니라
      #   **선언된 출처**라는 사실을 라벨에 남긴다).
      if (!"source" %in% names(new_raw)) new_raw[, source := "quantiwise"]
      if (!"source" %in% names(api_only)) api_only[, source := NA_character_]
      combined <- rbindlist(list(new_raw, api_only), use.names = TRUE, fill = TRUE)
      # ── 원천 우선순위 경유 (2026-09-07 도훈 지시) ─────────────────────────
      #   구판은 unique(by=c("Date","Ticker")) — new_raw 를 먼저 놓았으니 xlsx 가 이겼다.
      #   결과는 같아도 근거가 rbind 인자 순서라는 우연이었다. 승패는 정본이 정한다.
      #   (api_only 는 정의상 Date > xlsx_max 라 겹침이 0인 것이 정상 — 겹치면 그게 신호다)
      if (!exists("rawdata_priority_dedup")) {
        # DATA_DIR 은 config.R 산출이지만 이 파일의 로드 분기가 조건부라 부재할 수 있다 —
        # 없으면 루트에서 재도출한다(침묵 낙하 금지: 둘 다 없으면 아래 source 가 fail-loud).
        .ddir <- if (exists("DATA_DIR")) DATA_DIR else file.path(PROJECT_ROOT, "02_Infrastructure/data")
        source(file.path(.ddir, "rawdata_source_priority.R"))
      }
      .ded <- rawdata_priority_dedup(combined, context = "incremental_rawdata")
      if (.ded$n_dropped > 0L) {
        cat(sprintf("[incr] 우선순위 중복 해소: %d행 제거 (xlsx_max=%s 너머에 겹침 존재)\n",
                    .ded$n_dropped, xlsx_max))
        print(.ded$dropped_by)
      }
      combined <- .ded$dt
      setorder(combined, Date, Ticker)
      # [fix 2026-06-17] Windows arrow mmap(error 1224) — read_parquet(RAWDATA_CACHE) mmap
      # 해제 후 temp-rename (동일 경로 read→write halt 회피, krx_build_rawdata 동일 패턴)
      rm(old_raw, new_raw, api_only); gc(verbose = FALSE)
      .raw_tmp <- paste0(RAWDATA_CACHE, ".tmp")
      write_parquet(combined, .raw_tmp)
      if (file.exists(RAWDATA_CACHE)) file.remove(RAWDATA_CACHE)
      file.rename(.raw_tmp, RAWDATA_CACHE)
      cat(sprintf("[incr] API data restored: +%d rows (dates > %s)\n",
                  nrow(api_only), xlsx_max))
    } else {
      rm(old_raw, new_raw, api_only); gc(verbose = FALSE)
    }
  }

  invisible(TRUE)
}

# ─── 2. Consensus (Consensus.xlsx) ──────────────────────────────────────────
incremental_consensus <- function() {
  cons_xlsx <- file.path(RAWDATA_PATH, "Consensus.xlsx")
  cons_dir  <- file.path(CACHE_DIR, "consensus")
  ref_pq    <- file.path(cons_dir, "eps_1y.parquet")

  if (!.xlsx_newer(cons_xlsx, ref_pq)) {
    cat("[incr] Consensus.xlsx not newer — skip.\n")
    return(invisible(FALSE))
  }

  cat("[incr] Consensus.xlsx updated — rebuilding cache...\n")

  # consensus_parser.R의 consensus_build_cache() 사용
  tryCatch({
    source(file.path(DATA_DIR, "consensus_parser.R"), local = TRUE)
    if (exists("consensus_build_cache", inherits = FALSE)) {
      consensus_build_cache()
    } else {
      # fallback: 파서가 다른 이름일 수 있음
      cat("[incr] consensus_build_cache() not found — trying alternative...\n")
      source(file.path(DATA_DIR, "parse_consensus_quantiwise.R"), local = TRUE)
      if (exists("parse_consensus_all", inherits = FALSE)) {
        parse_consensus_all()
      }
    }
    cat("[incr] Consensus cache rebuilt.\n")
  }, error = function(e) {
    cat(sprintf("[incr] Consensus rebuild failed: %s\n", e$message))
  })

  invisible(TRUE)
}

# ─── 3. Investor (Investor_Act.xlsx) ────────────────────────────────────────
# xlsx 변경 시만 실행 (daily rebuild 안 함)
incremental_investor <- function() {
  inv_xlsx <- file.path(RAWDATA_PATH, "Investor_Act.xlsx")
  ref_pq   <- file.path(INVESTOR_CACHE, "investor_foreign.parquet")

  if (!.xlsx_newer(inv_xlsx, ref_pq)) {
    cat("[incr] Investor_Act.xlsx not newer — skip.\n")
    return(invisible(FALSE))
  }

  cat("[incr] Investor_Act.xlsx updated — rebuilding...\n")
  tryCatch({
    source(file.path(DATA_DIR, "parse_investor_quantiwise.R"), local = TRUE)
    parse_investor_act()
    cat("[incr] Investor cache rebuilt.\n")
  }, error = function(e) {
    cat(sprintf("[incr] Investor rebuild failed: %s\n", e$message))
  })

  invisible(TRUE)
}

# ─── 4. Fundamental (Fundamental.xlsx) ──────────────────────────────────────
incremental_fundamental <- function() {
  fund_xlsx <- file.path(RAWDATA_PATH, "Fundamental.xlsx")
  fund_pq   <- file.path(CACHE_DIR, "fundamental_xlsx.parquet")

  if (!.xlsx_newer(fund_xlsx, fund_pq)) {
    cat("[incr] Fundamental.xlsx not newer — skip.\n")
    return(invisible(FALSE))
  }

  cat("[incr] Fundamental.xlsx updated — rebuilding...\n")
  tryCatch({
    source(file.path(DATA_DIR, "parse_fundamental_xlsx.R"), local = TRUE)
    parse_fundamental_xlsx()
    compute_ttm()
    merge_fundamental_all()
    cat("[incr] Fundamental cache rebuilt.\n")
  }, error = function(e) {
    cat(sprintf("[incr] Fundamental rebuild failed: %s\n", e$message))
  })

  invisible(TRUE)
}

# ─── 5. Universe Support (Universe_Support.xlsx) ────────────────────────────
# [2026-07-25 수리] 구 코드 결함 2건: ① ref 파일명 오기("sector_lv1.parquet" — 실제는
# "us_sector_lv1.parquet")로 상시-newer 판정 ② parse_universe_support() force=FALSE 호출은
# 캐시 존재 시 전 시트 "Cache hit" 스킵 = 매 실행 no-op인데 "rebuilt"로 위장 로그.
# 현행: base xlsx가 캐시보다 새 것이면 정직 WARN만 발행 — 전체 리파싱(force=TRUE)은 base
# xlsx 통짜 로드(수백 MB 시트 XML)라 무인 daily 흐름에서 자동 실행하지 않는다(수동 판단).
# 월간 스냅샷 증분은 incremental_update_file.R::incremental_universe_support()가 표준 경로.
incremental_universe_support <- function() {
  if (!exists("UNIVERSE_SUPPORT_XLSX")) return(invisible(FALSE))
  support_xlsx <- UNIVERSE_SUPPORT_XLSX
  support_dir  <- UNIVERSE_SUPPORT_CACHE

  if (!file.exists(support_xlsx)) {
    cat("[incr] Universe_Support.xlsx not found — skip (Phase B pending).\n")
    return(invisible(FALSE))
  }

  ref_pq <- file.path(support_dir, "us_sector_lv1.parquet")
  if (!.xlsx_newer(support_xlsx, ref_pq)) {
    cat("[incr] Universe_Support.xlsx not newer — skip.\n")
    return(invisible(FALSE))
  }

  cat("[incr] ⚠ Universe_Support.xlsx(base)가 캐시보다 최신 — 자동 리빌드 없음.\n")
  cat("[incr]   전체 재파싱 = parse_universe_support(force = TRUE) 수동 실행 (메모리 大, base xlsx 전체 로드).\n")
  cat("[incr]   월간 스냅샷 증분 = incremental_update_file.R::incremental_universe_support() (표준 경로).\n")

  invisible(TRUE)
}

# ─── 전체 증분 업데이트 (daily_refresh.sh / qvest 부트스트랩) ────────────────
incremental_update_all <- function() {
  cat("=== QuantiWise xlsx Cache Update ===\n")
  t0 <- Sys.time()

  incremental_rawdata()
  incremental_consensus()
  incremental_investor()
  incremental_fundamental()
  incremental_universe_support()

  elapsed <- round(difftime(Sys.time(), t0, units = "mins"), 1)
  cat(sprintf("\n=== xlsx Cache Update Done (%.1f min) ===\n", elapsed))
}
