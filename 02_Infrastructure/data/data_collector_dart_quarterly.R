#==============================================================================
# Quant Module — DART Quarterly Data Collector + TTM Calculator
# Version: 1.0.0
#
# 분기별 재무제표 수집 (사업보고서 외 1Q/반기/3Q 추가)
# DART 누적보고서 → 개별 분기 추출 → TTM (Trailing Twelve Months) 산출
#
# 보고서 코드:
#   "11014" = 1분기 (1Q 누적)
#   "11012" = 반기   (1Q+2Q 누적)
#   "11013" = 3분기  (1Q+2Q+3Q 누적)
#   "11011" = 사업보고서 (연간, 1Q+2Q+3Q+4Q 누적)
#
# TTM 계산:
#   P/L, CF: 최근 4개 분기 합산
#   B/S: 최신 분기말 시점 값
#
# 사용법:
#   source("config.R")
#   source("data_collector_dart.R")  # .dart_fetch_single 필요
#   source("data_collector_dart_quarterly.R")
#   dart_fetch_quarterly(years = 2018:2025)   # 분기 보고서 수집
#   dart_compute_ttm()                         # TTM 계산 + parquet 저장
#
# API 제한: 일 10,000건 (4종 보고서 × 연도 × 종목 → 대량)
#==============================================================================

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
}

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(httr)
  library(jsonlite)
})

cat("[dart_quarterly] Loaded.\n")

# ─── Paths ──────────────────────────────────────────────────────────────────
DART_CACHE_DIR  <- file.path(CACHE_DIR, "dart")
DART_CORPCODE   <- file.path(DART_CACHE_DIR, "corpcode_map.parquet")
DART_QUARTERLY_RAW <- file.path(DART_CACHE_DIR, "dart_raw_quarterly.parquet")
DART_TTM_CACHE  <- file.path(CACHE_DIR, "fundamental_dart_quarterly.parquet")

if (!dir.exists(DART_CACHE_DIR)) dir.create(DART_CACHE_DIR, recursive = TRUE)

# Ensure base collector is loaded (for .dart_fetch_single and DART_API_KEY)
if (!exists(".dart_fetch_single")) {
  source(file.path(dirname(sys.frame(1)$ofile %||% "."), "data_collector_dart.R"))
}

# Report code → quarter mapping
REPRT_MAP <- data.table(
  reprt_code = c("11014", "11012", "11013", "11011"),
  quarter    = c(1L, 2L, 3L, 4L),
  label      = c("1Q", "반기", "3Q", "사업보고서")
)


#==============================================================================
# 1. Fetch Quarterly Financial Statements
#==============================================================================

dart_fetch_quarterly <- function(years = 2018:2025,
                                  reprt_codes = c("11014", "11012", "11013", "11011"),
                                  fs_div = "CFS",
                                  delay = 0.7,
                                  resume = TRUE) {
  # corp_code 매핑 로드
  if (!file.exists(DART_CORPCODE)) dart_update_corpcode()
  corpmap <- as.data.table(read_parquet(DART_CORPCODE))

  # 유니버스 티커 로드
  if (file.exists(RAWDATA_CACHE)) {
    raw_tickers <- unique(as.data.table(read_parquet(RAWDATA_CACHE))$Ticker)
  } else {
    stop("[dart_quarterly] RAWDATA cache not found.")
  }

  matched <- corpmap[Ticker %in% raw_tickers]
  cat(sprintf("[dart_quarterly] Universe: %d tickers | Matched: %d\n",
              length(raw_tickers), nrow(matched)))

  # 이미 수집된 데이터 (resume)
  existing <- NULL
  if (resume && file.exists(DART_QUARTERLY_RAW)) {
    existing <- as.data.table(read_parquet(DART_QUARTERLY_RAW))
    cat(sprintf("[dart_quarterly] Resuming: %d existing records\n", nrow(existing)))
  }

  # 수집 대상: 모든 (corp_code, year, reprt_code) 조합
  tasks <- CJ(corp_code = matched$corp_code,
              bsns_year = years,
              reprt_code = reprt_codes,
              sorted = FALSE)
  tasks <- merge(tasks, matched[, .(corp_code, Ticker, corp_name)], by = "corp_code")

  # 이미 수집된 건 제외
  if (!is.null(existing) && nrow(existing) > 0) {
    existing_keys <- unique(existing[, .(corp_code, bsns_year, reprt_code)])
    tasks <- tasks[!existing_keys, on = c("corp_code", "bsns_year", "reprt_code")]
    cat(sprintf("[dart_quarterly] Remaining tasks: %d\n", nrow(tasks)))
  }

  total <- nrow(tasks)
  if (total == 0) {
    cat("[dart_quarterly] All data already collected.\n")
    return(invisible(existing))
  }

  cat(sprintf("[dart_quarterly] Fetching %d tasks (~%.0f min)...\n",
              total, total * delay / 60))

  results <- list()
  n_success <- 0; n_empty <- 0; n_fail <- 0

  for (i in seq_len(total)) {
    task <- tasks[i]

    if (i %% 100 == 0 || i == 1) {
      cat(sprintf("  [%d/%d] %s (%s) %d %s | OK:%d EMPTY:%d FAIL:%d\n",
                  i, total, task$corp_name, task$Ticker,
                  task$bsns_year, task$reprt_code,
                  n_success, n_empty, n_fail))
    }

    dt <- tryCatch(
      .dart_fetch_single(task$corp_code, task$bsns_year,
                          task$reprt_code, fs_div),
      error = function(e) NULL
    )

    # CFS 없으면 OFS 시도
    if (is.null(dt) || nrow(dt) == 0) {
      if (fs_div == "CFS") {
        dt <- tryCatch(
          .dart_fetch_single(task$corp_code, task$bsns_year,
                              task$reprt_code, "OFS"),
          error = function(e) NULL
        )
        if (!is.null(dt) && nrow(dt) > 0) dt[, fs_div := "OFS"]
      }
    }

    if (!is.null(dt) && nrow(dt) > 0) {
      dt[, Ticker := task$Ticker]
      dt[, corp_code := task$corp_code]
      results[[length(results) + 1]] <- dt
      n_success <- n_success + 1
    } else {
      n_empty <- n_empty + 1
    }

    # 중간 저장 (매 500건)
    if (length(results) > 0 && length(results) %% 500 == 0) {
      cat("  > Checkpoint save...\n")
      batch <- rbindlist(results, fill = TRUE)
      if (!is.null(existing)) batch <- rbindlist(list(existing, batch), fill = TRUE)
      write_parquet(batch, DART_QUARTERLY_RAW)
    }

    Sys.sleep(delay)
  }

  # 최종 저장
  if (length(results) > 0) {
    all_data <- rbindlist(results, fill = TRUE)
    if (!is.null(existing)) all_data <- rbindlist(list(existing, all_data), fill = TRUE)
    write_parquet(all_data, DART_QUARTERLY_RAW)
    cat(sprintf("\n[dart_quarterly] DONE. Total: %d | OK: %d | Empty: %d | Fail: %d\n",
                nrow(all_data), n_success, n_empty, n_fail))
    invisible(all_data)
  } else {
    cat("[dart_quarterly] No new data.\n")
    invisible(existing)
  }
}


#==============================================================================
# 2. Parse Quarterly Raw → Individual Quarter Extraction
#==============================================================================

dart_parse_quarterly <- function(raw_dt = NULL) {
  if (is.null(raw_dt)) {
    if (!file.exists(DART_QUARTERLY_RAW))
      stop("[dart_quarterly] No quarterly raw cache. Run dart_fetch_quarterly() first.")
    raw_dt <- as.data.table(read_parquet(DART_QUARTERLY_RAW))
  }

  cat(sprintf("[dart_quarterly] Parsing %d raw quarterly records...\n", nrow(raw_dt)))

  # 금액 파싱
  .parse_amount <- function(x) {
    x <- gsub(",", "", as.character(x))
    x <- gsub("\\s+", "", x)
    suppressWarnings(as.numeric(x))
  }

  # 같은 account_map from data_collector_dart.R
  account_map <- list(
    Revenue       = c("매출액", "수익(매출액)", "영업수익"),
    COGS          = c("매출원가"),
    GrossProfit   = c("매출총이익"),
    SGAExpense    = c("판매비와관리비", "판매비와 관리비"),
    OperatingProfit = c("영업이익", "영업이익(손실)"),
    NetIncome     = c("당기순이익", "당기순이익(손실)",
                       "연결당기순이익", "연결당기순이익(손실)",
                       "지배기업소유주지분순이익", "지배기업의 소유주에게 귀속되는 당기순이익"),
    InterestExp   = c("이자비용", "금융비용"),
    DepAmort      = c("감가상각비", "감가상각비와상각비", "감가상각비 및 상각비"),
    TotalAssets   = c("자산총계"),
    CurrentAssets = c("유동자산"),
    CashAndEquiv  = c("현금및현금성자산", "현금 및 현금성자산"),
    Inventory     = c("재고자산"),
    AccountsRecv  = c("매출채권", "매출채권 및 기타유동채권", "매출채권및기타유동채권"),
    TotalLiab     = c("부채총계"),
    CurrentLiab   = c("유동부채"),
    AccountsPay   = c("매입채무", "매입채무 및 기타유동채무", "매입채무및기타유동채무"),
    TotalEquity   = c("자본총계"),
    OperatingCF   = c("영업활동현금흐름", "영업활동 현금흐름",
                       "영업활동으로인한현금흐름", "영업활동으로 인한 현금흐름"),
    InvestCF      = c("투자활동현금흐름", "투자활동 현금흐름",
                       "투자활동으로인한현금흐름")
  )

  sj_filter <- list(
    Revenue = c("IS", "CIS"), COGS = c("IS", "CIS"),
    GrossProfit = c("IS", "CIS"), SGAExpense = c("IS", "CIS"),
    OperatingProfit = c("IS", "CIS"), NetIncome = c("IS", "CIS"),
    InterestExp = c("IS", "CIS"), DepAmort = c("IS", "CIS", "CF"),
    TotalAssets = "BS", CurrentAssets = "BS", CashAndEquiv = "BS",
    Inventory = "BS", AccountsRecv = "BS",
    TotalLiab = "BS", CurrentLiab = "BS", AccountsPay = "BS",
    TotalEquity = "BS",
    OperatingCF = "CF", InvestCF = "CF"
  )

  raw_dt[, amount_clean := .parse_amount(thstrm_amount)]

  parsed_list <- list()
  for (var_name in names(account_map)) {
    patterns <- account_map[[var_name]]
    valid_sj <- sj_filter[[var_name]]
    matched_rows <- raw_dt[account_nm %in% patterns]
    if (!is.null(valid_sj)) matched_rows <- matched_rows[sj_div %in% valid_sj]
    if (nrow(matched_rows) > 0) {
      deduped <- matched_rows[, .(value = amount_clean[1]),
                                by = .(Ticker, bsns_year, reprt_code)]
      setnames(deduped, "value", var_name)
      parsed_list[[var_name]] <- deduped
    }
  }

  result <- parsed_list[[1]]
  for (i in 2:length(parsed_list)) {
    result <- merge(result, parsed_list[[i]],
                    by = c("Ticker", "bsns_year", "reprt_code"), all = TRUE)
  }

  # Quarter 번호 매핑
  result <- merge(result, REPRT_MAP[, .(reprt_code, quarter)],
                  by = "reprt_code", all.x = TRUE)
  setorder(result, Ticker, bsns_year, quarter)

  cat(sprintf("[dart_quarterly] Parsed: %d records | %d cols | %d tickers\n",
              nrow(result), ncol(result), uniqueN(result$Ticker)))

  result
}


#==============================================================================
# 3. Extract Individual Quarter from Cumulative Reports
#==============================================================================

# DART 누적보고서 → 개별 분기 추출
# 1Q: 그대로 사용
# 2Q: 반기 - 1Q
# 3Q: 3Q누적 - 반기
# 4Q: 연간 - 3Q누적
# B/S 항목은 시점 값이므로 변환 불필요

dart_extract_individual_quarters <- function(parsed_dt) {
  cat("[dart_quarterly] Extracting individual quarters...\n")

  # P/L and CF columns (flow = cumulative → need differencing)
  flow_cols <- c("Revenue", "COGS", "GrossProfit", "SGAExpense",
                 "OperatingProfit", "NetIncome", "InterestExp", "DepAmort",
                 "OperatingCF", "InvestCF")
  # B/S columns (stock = point-in-time → use as-is)
  stock_cols <- c("TotalAssets", "CurrentAssets", "CashAndEquiv", "Inventory",
                  "AccountsRecv", "TotalLiab", "CurrentLiab", "AccountsPay",
                  "TotalEquity")

  flow_cols <- intersect(flow_cols, names(parsed_dt))
  stock_cols <- intersect(stock_cols, names(parsed_dt))

  # Wide format: pivot quarters within same (Ticker, bsns_year)
  setorder(parsed_dt, Ticker, bsns_year, quarter)

  result_list <- list()

  for (tk in unique(parsed_dt$Ticker)) {
    tk_dt <- parsed_dt[Ticker == tk]

    for (yr in unique(tk_dt$bsns_year)) {
      yr_dt <- tk_dt[bsns_year == yr]
      yr_dt <- yr_dt[order(quarter)]

      for (i in seq_len(nrow(yr_dt))) {
        q <- yr_dt$quarter[i]
        row <- copy(yr_dt[i])

        if (q == 1L) {
          # 1Q: use as-is (already single quarter)
          # (flow and stock both fine)
        } else {
          # Need previous cumulative
          prev_q <- q - 1L
          prev_row <- yr_dt[quarter == prev_q]
          if (nrow(prev_row) == 1) {
            for (fc in flow_cols) {
              if (!is.na(row[[fc]]) && !is.na(prev_row[[fc]])) {
                set(row, 1L, fc, row[[fc]] - prev_row[[fc]])
              }
            }
          }
          # B/S: keep current quarter's point-in-time value (no change)
        }

        result_list[[length(result_list) + 1]] <- row
      }
    }
  }

  individual <- rbindlist(result_list)

  # Factor_Date: 분기 보고 후 ~45일
  # 1Q (3월말 결산) → 5/15, 2Q (6월말) → 8/15, 3Q (9월말) → 11/15, 4Q (12월말) → 3/31
  individual[, Factor_Date := as.Date(fifelse(
    quarter == 1L, paste0(bsns_year, "-05-15"),
    fifelse(quarter == 2L, paste0(bsns_year, "-08-15"),
      fifelse(quarter == 3L, paste0(bsns_year, "-11-15"),
              paste0(bsns_year + 1L, "-03-31")))
  ))]

  setorder(individual, Ticker, bsns_year, quarter)

  cat(sprintf("[dart_quarterly] Individual quarters: %d records\n", nrow(individual)))
  individual
}


#==============================================================================
# 4. Compute TTM (Trailing Twelve Months)
#==============================================================================

dart_compute_ttm <- function(raw_dt = NULL) {
  parsed <- dart_parse_quarterly(raw_dt)
  individual <- dart_extract_individual_quarters(parsed)

  cat("[dart_quarterly] Computing TTM factors...\n")

  flow_cols <- c("Revenue", "COGS", "GrossProfit", "SGAExpense",
                 "OperatingProfit", "NetIncome", "InterestExp", "DepAmort",
                 "OperatingCF", "InvestCF")
  stock_cols <- c("TotalAssets", "CurrentAssets", "CashAndEquiv", "Inventory",
                  "AccountsRecv", "TotalLiab", "CurrentLiab", "AccountsPay",
                  "TotalEquity")

  flow_cols <- intersect(flow_cols, names(individual))
  stock_cols <- intersect(stock_cols, names(individual))

  # Sort by Ticker, chronological order
  setorder(individual, Ticker, bsns_year, quarter)
  individual[, seq_id := seq_len(.N), by = Ticker]

  ttm_list <- list()

  for (tk in unique(individual$Ticker)) {
    tk_dt <- individual[Ticker == tk]

    if (nrow(tk_dt) < 4) next  # Need at least 4 quarters

    for (i in 4:nrow(tk_dt)) {
      window <- tk_dt[(i - 3):i]

      # Check: must be 4 consecutive quarters
      # (allow gaps — just sum available)
      row <- data.table(
        Ticker = tk,
        bsns_year = tk_dt$bsns_year[i],
        quarter = tk_dt$quarter[i],
        Factor_Date = tk_dt$Factor_Date[i]
      )

      # Flow: sum last 4 individual quarters
      for (fc in flow_cols) {
        vals <- window[[fc]]
        row[, (fc) := if (sum(!is.na(vals)) >= 3) sum(vals, na.rm = TRUE) else NA_real_]
      }

      # Stock: use latest quarter's value
      for (sc in stock_cols) {
        row[, (sc) := tk_dt[[sc]][i]]
      }

      ttm_list[[length(ttm_list) + 1]] <- row
    }
  }

  ttm_dt <- rbindlist(ttm_list, fill = TRUE)

  cat(sprintf("[dart_quarterly] TTM records: %d | %d tickers\n",
              nrow(ttm_dt), uniqueN(ttm_dt$Ticker)))

  # ── Compute TTM-based factors (same formulas as annual) ──
  .safe_div <- function(num, denom, min_denom = 0) {
    fifelse(!is.na(num) & !is.na(denom) & denom > min_denom, num / denom, NA_real_)
  }

  # Derived items
  ttm_dt[is.na(GrossProfit) & !is.na(Revenue) & !is.na(COGS),
         GrossProfit := Revenue - COGS]
  ttm_dt[, EBITDA := fifelse(!is.na(OperatingProfit),
    OperatingProfit + fifelse(!is.na(DepAmort), DepAmort, 0), NA_real_)]
  ttm_dt[, WorkingCapital := CurrentAssets - CurrentLiab]
  ttm_dt[, FCF := fifelse(!is.na(OperatingCF) & !is.na(InvestCF),
                           OperatingCF + InvestCF, NA_real_)]

  # Key factors (TTM)
  ttm_dt[, GPA := .safe_div(GrossProfit, TotalAssets)]
  ttm_dt[, ROE := .safe_div(NetIncome, TotalEquity)]
  ttm_dt[, ROA := .safe_div(NetIncome, TotalAssets)]
  ttm_dt[, OPM := .safe_div(OperatingProfit, Revenue)]
  ttm_dt[, GrossMargin := .safe_div(GrossProfit, Revenue)]
  ttm_dt[, NetMargin := .safe_div(NetIncome, Revenue)]
  ttm_dt[, EBIT_to_Assets := .safe_div(OperatingProfit, TotalAssets)]
  ttm_dt[, FCF_Margin := .safe_div(FCF, Revenue)]
  ttm_dt[, AssetTurnover := .safe_div(Revenue, TotalAssets)]
  ttm_dt[, Accrual := fifelse(!is.na(TotalAssets) & TotalAssets > 0 &
    !is.na(NetIncome) & !is.na(OperatingCF),
    (NetIncome - OperatingCF) / TotalAssets, NA_real_)]
  ttm_dt[, ICR := fifelse(!is.na(InterestExp) & InterestExp > 0 & !is.na(OperatingProfit),
                           OperatingProfit / InterestExp, NA_real_)]
  ttm_dt[, CurrentRatio := .safe_div(CurrentAssets, CurrentLiab)]
  ttm_dt[, CashToAssets := .safe_div(CashAndEquiv, TotalAssets)]
  ttm_dt[, DebtRatio := .safe_div(TotalLiab, TotalEquity)]

  # Efficiency (TTM)
  ttm_dt[, InventoryTurnover := .safe_div(COGS, Inventory)]
  ttm_dt[, ReceivablesTurnover := .safe_div(Revenue, AccountsRecv)]
  ttm_dt[, PayablesTurnover := .safe_div(COGS, AccountsPay)]
  ttm_dt[, DaysReceivable := fifelse(!is.na(ReceivablesTurnover) & ReceivablesTurnover > 0,
                                      365 / ReceivablesTurnover, NA_real_)]
  ttm_dt[, DaysInventory := fifelse(!is.na(InventoryTurnover) & InventoryTurnover > 0,
                                     365 / InventoryTurnover, NA_real_)]
  ttm_dt[, DaysPayable := fifelse(!is.na(PayablesTurnover) & PayablesTurnover > 0,
                                   365 / PayablesTurnover, NA_real_)]
  ttm_dt[, CCC := fifelse(!is.na(DaysReceivable) & !is.na(DaysInventory) & !is.na(DaysPayable),
                           DaysReceivable + DaysInventory - DaysPayable, NA_real_)]
  ttm_dt[, CashBurnRate := fifelse(!is.na(OperatingCF) & OperatingCF < 0 &
    !is.na(CashAndEquiv) & CashAndEquiv > 0,
    CashAndEquiv / abs(OperatingCF), NA_real_)]
  ttm_dt[, OCFToRevenue := .safe_div(OperatingCF, Revenue)]

  # Growth (vs 4 quarters ago = YoY)
  setorder(ttm_dt, Ticker, Factor_Date)
  growth_cols <- c("Revenue", "GrossProfit", "OperatingProfit", "NetIncome", "TotalAssets")
  for (gc in growth_cols) {
    delta_name <- paste0(gc, "Growth")
    ttm_dt[, (delta_name) := get(gc) / shift(get(gc), 4L) - 1, by = Ticker]
  }

  # Delta ratios (vs 4 quarters ago)
  delta_ratio_cols <- c("GPA", "ROA", "Accrual", "CCC")
  for (dc in delta_ratio_cols) {
    delta_name <- paste0("Delta_", dc)
    ttm_dt[, (delta_name) := get(dc) - shift(get(dc), 4L), by = Ticker]
  }

  # Save
  write_parquet(ttm_dt, DART_TTM_CACHE)
  cat(sprintf("[dart_quarterly] TTM saved: %d rows | %d tickers | %s\n",
              nrow(ttm_dt), uniqueN(ttm_dt$Ticker), DART_TTM_CACHE))

  # Coverage report
  key_cols <- c("GPA", "ROE", "ROA", "CCC", "Accrual", "Delta_GPA", "Delta_ROA",
                "Delta_Accrual", "CashBurnRate", "CurrentRatio")
  cat("\n[dart_quarterly] TTM Key Factor Coverage:\n")
  for (col in key_cols) {
    if (col %in% names(ttm_dt)) {
      pct <- round(mean(!is.na(ttm_dt[[col]])) * 100, 1)
      cat(sprintf("  %-20s: %5.1f%%\n", col, pct))
    }
  }

  invisible(ttm_dt)
}


#==============================================================================
# 5. Master Pipeline
#==============================================================================

dart_quarterly_pipeline <- function(years = 2018:2025) {
  cat("═══════════════════════════════════════════════\n")
  cat("[dart_quarterly] Starting quarterly pipeline\n")
  cat("═══════════════════════════════════════════════\n\n")

  cat("── Step 1: Fetch quarterly reports ──\n")
  dart_fetch_quarterly(years = years)

  cat("\n── Step 2: Compute TTM factors ──\n")
  dart_compute_ttm()

  cat("\n═══════════════════════════════════════════════\n")
  cat("[dart_quarterly] Pipeline complete!\n")
  cat("═══════════════════════════════════════════════\n")
}
