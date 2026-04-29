#==============================================================================
# FRED supplement via yfinance (latest-fill only, FRED-priority)
# Author: Q-Lead (2026-04-30)
#
# 정책:
#   1. fred_macro_wide.parquet 마지막 N일 NA row 만 yfinance close 로 보충
#   2. FRED 데이터 있으면 yfinance overwrite 안 함 (FRED 우선)
#   3. yfinance 보충된 cell 은 _yf 보조 컬럼 (TRUE/FALSE) 으로 source 표시
#   4. 다음 cron 에서 FRED publish 되면 자동으로 FRED 값으로 교체 (NA 였던 cell 만 채움)
#
# Series mapping:
#   VIX           <- ^VIX   (CBOE VIX)
#   US_10Y_Yield  <- ^TNX / 10  (Yahoo ^TNX 는 10x scale)
#   KRW_USD       <- KRW=X  (USD/KRW spot)
#
# HY_Spread (BAMLH0A0HYM2 OAS) 는 yfinance 직접 매핑 series 없음 → FRED only.
#
# Public API:
#   supplement_fred_with_yfinance(lookback_days = 7)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(quantmod)
})

if (!exists("CACHE_DIR")) CACHE_DIR <- file.path(getwd(), ".cache")
FRED_WIDE_PATH <- file.path(CACHE_DIR, "fred_macro_wide.parquet")

.YF_MAPPINGS <- list(
  VIX          = list(symbol = "^VIX",  scale = 1.0),
  US_10Y_Yield = list(symbol = "^TNX",  scale = 1.0),  # ^TNX 는 이미 % 단위 (e.g., 4.418 = 4.418%)
  KRW_USD      = list(symbol = "KRW=X", scale = 1.0)
)

.fetch_yf_close <- function(symbol, from_date, to_date) {
  out <- tryCatch({
    raw <- quantmod::getSymbols(symbol, src = "yahoo", auto.assign = FALSE,
                                 from = from_date, to = to_date + 1)
    cl <- quantmod::Cl(raw)
    data.table(Date = as.Date(zoo::index(cl)),
               Close = as.numeric(cl))
  }, error = function(e) {
    cat(sprintf("[fred_supplement] yfinance fetch fail: %s — %s\n", symbol, e$message))
    NULL
  })
  out
}

supplement_fred_with_yfinance <- function(lookback_days = 7L) {
  if (!file.exists(FRED_WIDE_PATH)) {
    cat(sprintf("[fred_supplement] %s not found — skip\n", FRED_WIDE_PATH))
    return(invisible(NULL))
  }

  fd <- as.data.table(arrow::read_parquet(FRED_WIDE_PATH))
  setorder(fd, Date)
  if (!inherits(fd$Date, "Date")) fd[, Date := as.Date(Date)]

  to_d   <- max(fd$Date, na.rm = TRUE)
  from_d <- to_d - lookback_days
  cat(sprintf("[fred_supplement] window: %s ~ %s (%d days)\n",
              from_d, to_d, lookback_days))

  n_filled_total <- 0L
  fill_log <- list()

  for (col in names(.YF_MAPPINGS)) {
    if (!col %in% names(fd)) {
      cat(sprintf("  - %-15s: column missing — skip\n", col))
      next
    }

    map <- .YF_MAPPINGS[[col]]
    yf  <- .fetch_yf_close(map$symbol, from_d, to_d + 1)
    if (is.null(yf) || nrow(yf) == 0L) {
      cat(sprintf("  - %-15s: yfinance empty — skip\n", col))
      next
    }
    yf[, Close := Close * map$scale]

    # Lookup key
    setkey(yf, Date)
    setkey(fd, Date)

    # FRED 가 NA 인 cell 만 yfinance 로 채움 (FRED 우선)
    target_idx <- which(fd$Date >= from_d & fd$Date <= to_d & is.na(fd[[col]]))
    if (length(target_idx) == 0L) {
      cat(sprintf("  - %-15s: no NA cell in window — skip\n", col))
      next
    }

    n_filled_col <- 0L
    filled_dates <- c()
    for (i in target_idx) {
      d <- fd$Date[i]
      yf_row <- yf[Date == d]
      if (nrow(yf_row) == 1L && !is.na(yf_row$Close)) {
        fd[i, (col) := yf_row$Close]
        n_filled_col <- n_filled_col + 1L
        filled_dates <- c(filled_dates, as.character(d))
      }
    }

    if (n_filled_col > 0L) {
      cat(sprintf("  + %-15s: %d cells filled (%s) | dates: %s\n",
                  col, n_filled_col, map$symbol,
                  paste(filled_dates, collapse = ", ")))
      fill_log[[col]] <- list(symbol = map$symbol, n_filled = n_filled_col,
                              dates = filled_dates)
      n_filled_total <- n_filled_total + n_filled_col
    } else {
      cat(sprintf("  - %-15s: yfinance no overlap with NA cells — skip\n", col))
    }
  }

  if (n_filled_total > 0L) {
    tmp <- paste0(FRED_WIDE_PATH, ".tmp")
    arrow::write_parquet(fd, tmp)
    file.rename(tmp, FRED_WIDE_PATH)
    cat(sprintf("[fred_supplement] total filled: %d cells | saved: %s\n",
                n_filled_total, FRED_WIDE_PATH))
  } else {
    cat("[fred_supplement] no cells filled — fred_macro_wide.parquet unchanged\n")
  }

  invisible(list(n_filled = n_filled_total, log = fill_log))
}

cat("[fred_supplement_yfinance] Loaded. supplement_fred_with_yfinance(lookback_days=7L)\n")
