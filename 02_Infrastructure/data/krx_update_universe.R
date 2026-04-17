#==============================================================================
# krx_update_universe.R — Universe 캐시 월말 자동 갱신
#
# Universe_master.xlsx 없이, RAWDATA + 기존 Universe 기반으로 월말 갱신
#
# 로직:
#   1. 기존 universe.parquet 최신 날짜 이후 새 월말 탐지
#   2. 최근 universe 멤버십(K200/KQ150) carry forward
#   3. RAWDATA에서 해당 월의 거래대금(ACC_TRDVAL) 기반 유동성 필터
#   4. 상폐 종목 제거 (해당 월 RAWDATA에 없으면 제외)
#   5. Sector 매핑 carry forward
#
# 제한:
#   - K200/KQ150 정기변경(6월/12월)은 반영 불가 → 수동 업데이트 필요
#   - Sector 신규 매핑 불가 → 기존 매핑 유지
#   - Float, Sector_Lv2 미지원 (KRX API 미제공)
#
# Usage:
#   source("02_Infrastructure/krx_update_universe.R")
#   krx_update_universe()       # 자동 갱신
#   krx_update_universe(force_rebuild_from = "2026-01-01")  # 특정 시점부터 재빌드
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
}

UNIVERSE_CACHE <- file.path(CACHE_DIR, "universe.parquet")

#==============================================================================
# krx_update_universe() — 메인 함수
#==============================================================================
krx_update_universe <- function(
    force_rebuild_from = NULL,
    liq_kospi  = 0.20,   # KOSPI 거래대금 하위 20% 제거
    liq_kosdaq = 0.30    # KOSDAQ 거래대금 하위 30% 제거
) {
  cat("[universe_update] Starting universe refresh...\n")

  # ── 1. 기존 Universe 로드 (없으면 빈 테이블로 시작) ──
  if (file.exists(UNIVERSE_CACHE)) {
    uni <- as.data.table(read_parquet(UNIVERSE_CACHE))
    uni[, Date := as.Date(Date)]
    last_uni_date <- max(uni$Date)
    cat(sprintf("  Existing universe: %s ~ %s (%d dates, %d tickers)\n",
                min(uni$Date), last_uni_date, length(unique(uni$Date)),
                uniqueN(uni$Ticker)))
  } else {
    cat("[universe_update] No existing universe.parquet — creating from scratch.\n")
    uni <- data.table(Date = as.Date(character()), Ticker = character(),
                      Name = character(), Market = character(), Sector = character())
    last_uni_date <- as.Date("1990-01-01")
    if (is.null(force_rebuild_from)) force_rebuild_from <- format(ANALYSIS_START_DATE, "%Y-%m-%d")
  }

  # ── 2. RAWDATA에서 새 월말 탐지 ──
  raw <- as.data.table(read_parquet(RAWDATA_CACHE))
  raw[, Date := as.Date(Date)]
  last_raw_date <- max(raw$Date)

  start_from <- if (!is.null(force_rebuild_from)) as.Date(force_rebuild_from) else last_uni_date + 1

  # RAWDATA의 날짜 중, start_from 이후 각 월의 마지막 거래일 찾기
  raw_dates <- sort(unique(raw[Date >= start_from]$Date))
  if (length(raw_dates) == 0) {
    cat("[universe_update] No new dates to process. Universe is up to date.\n")
    return(invisible(uni))
  }

  raw_dt <- data.table(Date = raw_dates)
  raw_dt[, YM := format(Date, "%Y-%m")]
  month_ends <- raw_dt[, .(MonthEnd = max(Date)), by = YM][order(YM)]

  # 이미 universe에 있는 월 제외 (force가 아닌 경우)
  if (is.null(force_rebuild_from)) {
    existing_ym <- format(unique(uni$Date), "%Y-%m")
    month_ends <- month_ends[!YM %in% existing_ym]
  }

  if (nrow(month_ends) == 0) {
    cat("[universe_update] No new month-ends to add. Universe is up to date.\n")
    return(invisible(uni))
  }

  cat(sprintf("  New month-ends to process: %d (%s)\n",
              nrow(month_ends), paste(month_ends$YM, collapse = ", ")))

  # ── 3. 최신 Universe 멤버십 + Sector 매핑 가져오기 ──
  if (nrow(uni) > 0) {
    latest_uni <- uni[Date == last_uni_date]
    sector_map <- unique(uni[, .(Ticker, Name, Market, Sector)])
    sector_map <- sector_map[, .SD[.N], by = Ticker]
  } else {
    latest_uni <- data.table(Ticker = character(), Name = character(),
                             Market = character(), Sector = character())
    sector_map <- data.table(Ticker = character(), Name = character(),
                             Market = character(), Sector = character())
  }

  cat(sprintf("  Base membership: %d tickers from %s\n",
              nrow(latest_uni), last_uni_date))

  # ── 4. 각 월말에 대해 Universe 생성 ──
  new_rows_list <- list()

  for (i in seq_len(nrow(month_ends))) {
    me <- month_ends$MonthEnd[i]
    ym <- month_ends$YM[i]
    cat(sprintf("  [%d/%d] %s (month-end: %s)...\n", i, nrow(month_ends), ym, me))

    # 해당 월의 RAWDATA (유동성 계산용 — 월 전체 평균 거래대금)
    month_start <- as.Date(paste0(ym, "-01"))
    month_raw <- raw[Date >= month_start & Date <= me]

    if (nrow(month_raw) == 0) {
      cat("    No RAWDATA for this month. Skipping.\n")
      next
    }

    # 월말 기준 활성 종목 (해당 월에 거래 기록이 있는 종목)
    active_tickers <- unique(month_raw$Ticker)

    # 기존 Universe 멤버십이 있으면 활성 종목만 유지, 없으면 전체 활성 종목으로 시작
    if (nrow(latest_uni) > 0) {
      candidates <- latest_uni[Ticker %in% active_tickers, .(Ticker)]
    } else {
      # from scratch: 모든 활성 종목이 후보
      candidates <- data.table(Ticker = active_tickers)
    }

    # Sector/Name/Market 매핑 (기존 매핑 우선)
    if (nrow(sector_map) > 0) {
      candidates <- merge(candidates, sector_map, by = "Ticker", all.x = TRUE)
    } else {
      candidates[, `:=`(Name = NA_character_, Market = NA_character_, Sector = NA_character_)]
    }

    # RAWDATA에서 보충 (Name/Market/Sector가 NA인 종목)
    raw_cols <- intersect(c("Name", "Market", "Sector"), names(month_raw))
    if (length(raw_cols) > 0) {
      raw_info <- month_raw[Date == me, c("Ticker", raw_cols), with = FALSE]
      raw_info <- raw_info[!duplicated(Ticker)]
      setnames(raw_info, raw_cols, paste0(raw_cols, "_raw"))
      candidates <- merge(candidates, raw_info, by = "Ticker", all.x = TRUE)
      for (col in raw_cols) {
        raw_col <- paste0(col, "_raw")
        if (raw_col %in% names(candidates)) {
          candidates[is.na(get(col)), (col) := get(raw_col)]
          candidates[, (raw_col) := NULL]
        }
      }
    }

    # KRX API 캐시에서 Market 정보 보충 (RAWDATA에 Market이 없을 때)
    if (sum(is.na(candidates$Market)) > 0) {
      krx_info_dir <- file.path(CACHE_DIR, "krx")
      # KOSPI stock info에 있으면 KOSPI, 아니면 KOSDAQ
      kospi_files <- list.files(file.path(krx_info_dir, "stk_info"), full.names = TRUE)
      kosdaq_files <- list.files(file.path(krx_info_dir, "ksq_info"), full.names = TRUE)
      kospi_tickers <- character()
      kosdaq_tickers <- character()
      if (length(kospi_files) > 0) {
        latest_kospi <- tryCatch(as.data.table(read_parquet(tail(sort(kospi_files), 1))),
                                 error = function(e) NULL)
        if (!is.null(latest_kospi) && "ISU_SRT_CD" %in% names(latest_kospi))
          kospi_tickers <- latest_kospi$ISU_SRT_CD
      }
      if (length(kosdaq_files) > 0) {
        latest_kosdaq <- tryCatch(as.data.table(read_parquet(tail(sort(kosdaq_files), 1))),
                                  error = function(e) NULL)
        if (!is.null(latest_kosdaq) && "ISU_SRT_CD" %in% names(latest_kosdaq))
          kosdaq_tickers <- latest_kosdaq$ISU_SRT_CD
      }
      candidates[is.na(Market) & Ticker %in% kospi_tickers, Market := "KOSPI"]
      candidates[is.na(Market) & Ticker %in% kosdaq_tickers, Market := "KOSDAQ"]
      # 여전히 NA면 KOSPI로 기본 분류
      candidates[is.na(Market), Market := "KOSPI"]
    }

    # 유동성 필터: 월 평균 거래대금 기준 percentile
    vol_stats <- month_raw[, .(
      AvgTrdVal = mean(Vol * Close, na.rm = TRUE)
    ), by = Ticker]
    # Market 정보는 candidates에서 가져옴
    vol_stats <- merge(vol_stats, candidates[, .(Ticker, Market)], by = "Ticker", all.x = TRUE)
    vol_stats[is.na(Market), Market := "KOSPI"]

    vol_stats[, Vol_Pct := frank(AvgTrdVal, ties.method = "dense") / .N, by = Market]

    # 필터 적용
    liq_pass <- vol_stats[
      (Market == "KOSPI"  & Vol_Pct >= liq_kospi) |
      (Market == "KOSDAQ" & Vol_Pct >= liq_kosdaq)
    ]$Ticker

    candidates <- candidates[Ticker %in% liq_pass]

    # 지주회사 필터 (기존 로직 재현)
    finance_sectors <- c("은행", "증권", "보험")
    candidates <- candidates[
      !(!(Sector %in% finance_sectors) & grepl("홀딩스|지주", Name))
    ]

    # Sector NA 허용 (Universe_Support 매핑 전이므로 NA 가능)
    # 지주회사 필터에서 Sector가 NA면 필터 통과 (보수적)

    # 월말 날짜 설정
    candidates[, Date := me]

    new_rows_list[[length(new_rows_list) + 1]] <- candidates[, .(Date, Ticker, Name, Market, Sector)]

    cat(sprintf("    Active: %d → Liquidity: %d → Final: %d tickers\n",
                length(active_tickers), length(liq_pass), nrow(candidates)))
  }

  if (length(new_rows_list) == 0) {
    cat("[universe_update] No new rows generated.\n")
    return(invisible(uni))
  }

  # ── 5. Universe 병합 + 저장 ──
  new_uni <- rbindlist(new_rows_list)

  if (!is.null(force_rebuild_from)) {
    # force 모드: 해당 기간 기존 데이터 제거 후 교체
    uni <- uni[Date < as.Date(force_rebuild_from)]
  }

  combined <- rbind(uni, new_uni)
  combined <- unique(combined, by = c("Date", "Ticker"))
  setkey(combined, Ticker, Date)
  write_parquet(combined, UNIVERSE_CACHE)

  cat(sprintf("\n[universe_update] === 완료 ===\n"))
  cat(sprintf("  추가: %d rows (%d months)\n", nrow(new_uni), length(new_rows_list)))
  cat(sprintf("  전체: %s ~ %s (%d dates, %d tickers)\n",
              min(combined$Date), max(combined$Date),
              length(unique(combined$Date)), uniqueN(combined$Ticker)))

  # 최근 3개 월말 요약
  recent_dates <- tail(sort(unique(combined$Date)), 3)
  for (d in recent_dates) {
    sub <- combined[Date == d]
    cat(sprintf("  %s: %d tickers (KOSPI %d, KOSDAQ %d)\n", d,
                nrow(sub),
                nrow(sub[Market == "KOSPI"]),
                nrow(sub[Market == "KOSDAQ"])))
  }

  invisible(combined)
}

cat("[krx_update_universe] Loaded.\n")
cat("[krx_update_universe] Functions: krx_update_universe()\n")
