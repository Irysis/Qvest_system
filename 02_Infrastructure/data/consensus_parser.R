#==============================================================================
# QuantiWise Consensus Data Parser
#
# 03_Universe/Consensus.xlsx (QuantiWise wide format) → .cache/consensus/ parquets
#
# Format: Row 8 = ticker codes, Row 9 = names, Row 15+ = date × ticker values
# Each sheet = one metric (EPS_1Y, BPS_1Y, TP, etc.)
#
# Usage:
#   source("config.R")
#   source("consensus_parser.R")
#   consensus_build_cache()          # full rebuild (slow, ~10min)
#   cs <- consensus_load()           # load cached long-format data.table
#   cs <- consensus_load("EPS_1Y")   # load single metric
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(readxl)
  library(arrow)
})

# ─── Paths ──────────────────────────────────────────────────────────────────
CONSENSUS_XLSX  <- file.path(PROJECT_ROOT, "03_Universe", "Consensus.xlsx")
CONSENSUS_CACHE <- file.path(CACHE_DIR, "consensus")

# ─── Sheet → metric name mapping ────────────────────────────────────────────
CONSENSUS_METRICS <- c(
  "EPS_1Y"       = "eps_1y",
  "BPS_1Y"       = "bps_1y",
  "DPS_1Y"       = "dps_1y",
  "EPS_Chg_1M"   = "eps_chg_1m",
  "EPS_Chg_3M"   = "eps_chg_3m",
  "TP"           = "target_price",
  "SUE_지배"      = "sue",
  "매출액_FY1"    = "revenue_fy1",
  "ESCR(지배)"    = "escr",
  "ESBR(지배)"    = "esbr",
  "커버리지"       = "coverage",
  "영업이익_FY1"   = "op_profit_fy1"
)

#' Parse a single QuantiWise sheet: wide → long
#' @param sheet_name Sheet name in Excel
#' @param metric_name Clean metric name for output
#' @return data.table with columns: Date, Ticker, Name, value (metric_name)
consensus_parse_sheet <- function(sheet_name, metric_name = sheet_name) {
  cat(sprintf("  Parsing [%s] → %s ...", sheet_name, metric_name))
  t0 <- proc.time()

  raw <- as.data.table(read_excel(
    CONSENSUS_XLSX, sheet = sheet_name,
    col_names = FALSE, .name_repair = "minimal"
  ))

  # Extract ticker codes (row 8) and names (row 9)
  tickers <- as.character(raw[8, 2:ncol(raw), with = FALSE])
  names_  <- as.character(raw[9, 2:ncol(raw), with = FALSE])

  # Valid columns (non-NA ticker)
  valid <- !is.na(tickers) & tickers != ""
  ticker_vec <- tickers[valid]
  name_vec   <- names_[valid]
  col_idx    <- which(valid) + 1L  # +1 for date column offset

  # Data rows start at row 15
  data_rows <- raw[15:nrow(raw), ]

  # Parse dates
  date_serial <- suppressWarnings(as.numeric(data_rows[[1]]))
  valid_dates <- !is.na(date_serial)
  dates <- as.Date(date_serial[valid_dates], origin = "1899-12-30")
  data_rows <- data_rows[valid_dates, ]

  # Extract value matrix
  val_mat <- as.matrix(data_rows[, col_idx, with = FALSE])
  storage.mode(val_mat) <- "double"

  # Melt to long format
  dt <- data.table(
    Date   = rep(dates, times = length(ticker_vec)),
    Ticker = rep(ticker_vec, each = length(dates)),
    value  = as.vector(val_mat)
  )

  # Drop NA values (sparse data — most cells are NA)
  dt <- dt[!is.na(value)]
  setnames(dt, "value", metric_name)

  elapsed <- (proc.time() - t0)[3]
  cat(sprintf(" %s rows [%.1fs]\n", format(nrow(dt), big.mark = ","), elapsed))
  dt
}

#' Build parquet cache for all consensus sheets
#' @param sheets Character vector of sheet names (default: all)
#' @param force Rebuild even if cache exists
consensus_build_cache <- function(sheets = names(CONSENSUS_METRICS), force = FALSE) {
  if (!file.exists(CONSENSUS_XLSX)) {
    stop("Consensus.xlsx not found: ", CONSENSUS_XLSX)
  }

  if (!dir.exists(CONSENSUS_CACHE)) {
    dir.create(CONSENSUS_CACHE, recursive = TRUE)
  }

  cat(sprintf("Building consensus cache from %s\n", basename(CONSENSUS_XLSX)))
  cat(sprintf("  Output: %s/\n", CONSENSUS_CACHE))

  # Also build ticker lookup from DATA_Key
  cat("  Parsing [DATA_Key]...")
  dk <- as.data.table(read_excel(CONSENSUS_XLSX, sheet = "DATA_Key", col_names = FALSE))
  ticker_map <- data.table(
    Ticker = as.character(dk[2:nrow(dk), 1, with = FALSE][[1]]),
    Name   = as.character(dk[2:nrow(dk), 2, with = FALSE][[1]])
  )
  ticker_map <- ticker_map[!is.na(Ticker) & Ticker != ""]
  arrow::write_parquet(ticker_map, file.path(CONSENSUS_CACHE, "ticker_map.parquet"))
  cat(sprintf(" %d tickers\n", nrow(ticker_map)))

  # Parse each sheet
  for (s in sheets) {
    metric <- CONSENSUS_METRICS[s]
    cache_file <- file.path(CONSENSUS_CACHE, paste0(metric, ".parquet"))

    if (!force && file.exists(cache_file)) {
      cat(sprintf("  [%s] cached — skip (use force=TRUE to rebuild)\n", s))
      next
    }

    tryCatch({
      dt <- consensus_parse_sheet(s, metric)
      arrow::write_parquet(dt, cache_file)
    }, error = function(e) {
      cat(sprintf("  [%s] ERROR: %s\n", s, e$message))
    })
  }

  cat("Done.\n")
}

#' Load cached consensus data
#' @param metrics Character vector of metric names, or NULL for all
#' @param date_from Filter: start date
#' @param date_to Filter: end date
#' @param tickers Filter: ticker codes (e.g., "A005930")
#' @return data.table (long format, one metric column per metric)
consensus_load <- function(metrics = NULL, date_from = NULL, date_to = NULL,
                           tickers = NULL) {
  if (!dir.exists(CONSENSUS_CACHE)) {
    stop("Consensus cache not found. Run consensus_build_cache() first.")
  }

  if (is.null(metrics)) {
    metrics <- CONSENSUS_METRICS
  } else {
    # Accept either sheet names or metric names
    idx <- match(metrics, names(CONSENSUS_METRICS))
    idx2 <- match(metrics, CONSENSUS_METRICS)
    metrics <- ifelse(!is.na(idx), CONSENSUS_METRICS[idx],
                      ifelse(!is.na(idx2), metrics, NA_character_))
    metrics <- metrics[!is.na(metrics)]
  }

  result <- NULL
  for (m in metrics) {
    f <- file.path(CONSENSUS_CACHE, paste0(m, ".parquet"))
    if (!file.exists(f)) {
      warning("Cache not found: ", m, " — skipping")
      next
    }
    dt <- as.data.table(arrow::read_parquet(f))

    # Apply filters
    if (!is.null(date_from)) dt <- dt[Date >= as.Date(date_from)]
    if (!is.null(date_to))   dt <- dt[Date <= as.Date(date_to)]
    if (!is.null(tickers))   dt <- dt[Ticker %in% tickers]

    if (is.null(result)) {
      result <- dt
    } else {
      result <- merge(result, dt, by = c("Date", "Ticker"), all = TRUE)
    }
  }

  setkey(result, Date, Ticker)
  result
}

#' Quick summary of cached consensus data
consensus_summary <- function() {
  if (!dir.exists(CONSENSUS_CACHE)) {
    cat("No cache found. Run consensus_build_cache() first.\n")
    return(invisible(NULL))
  }

  pq_files <- list.files(CONSENSUS_CACHE, pattern = "\\.parquet$", full.names = TRUE)
  pq_files <- pq_files[basename(pq_files) != "ticker_map.parquet"]

  cat(sprintf("Consensus cache: %s\n", CONSENSUS_CACHE))
  cat(sprintf("Metrics cached: %d / %d\n\n", length(pq_files), length(CONSENSUS_METRICS)))

  for (f in pq_files) {
    dt <- as.data.table(arrow::read_parquet(f))
    metric <- tools::file_path_sans_ext(basename(f))
    cat(sprintf("  %-15s  %s ~ %s  %6d tickers  %s rows\n",
                metric,
                min(dt$Date), max(dt$Date),
                uniqueN(dt$Ticker),
                format(nrow(dt), big.mark = ",")))
  }
}

#' Incremental update: append only new dates to existing cache
#' Reads each sheet, filters rows > max(cached date), appends to parquet.
#' Much faster than full rebuild (~2min vs ~10min).
consensus_incremental_update <- function(sheets = names(CONSENSUS_METRICS)) {
  if (!file.exists(CONSENSUS_XLSX)) stop("Consensus.xlsx not found: ", CONSENSUS_XLSX)
  if (!dir.exists(CONSENSUS_CACHE)) {
    cat("No cache found — falling back to full build.\n")
    return(consensus_build_cache(force = TRUE))
  }

  cat(sprintf("Incremental update from %s\n", basename(CONSENSUS_XLSX)))
  total_new <- 0L

  for (s in sheets) {
    metric <- CONSENSUS_METRICS[s]
    cache_file <- file.path(CONSENSUS_CACHE, paste0(metric, ".parquet"))

    if (!file.exists(cache_file)) {
      cat(sprintf("  [%s] no cache — full parse\n", s))
      tryCatch({
        dt <- consensus_parse_sheet(s, metric)
        arrow::write_parquet(dt, cache_file)
        total_new <- total_new + nrow(dt)
      }, error = function(e) cat(sprintf("  [%s] ERROR: %s\n", s, e$message)))
      next
    }

    # Load existing cache to find max date
    existing <- as.data.table(arrow::read_parquet(cache_file))
    max_date <- max(existing$Date, na.rm = TRUE)
    cat(sprintf("  [%s] cached through %s — ", s, max_date))

    # Parse full sheet (unavoidable with xlsx), then filter new rows only
    tryCatch({
      dt_full <- consensus_parse_sheet(s, metric)
      dt_new <- dt_full[Date > max_date]

      if (nrow(dt_new) == 0) {
        cat("no new data.\n")
      } else {
        # Append and write
        combined <- rbindlist(list(existing, dt_new), use.names = TRUE)
        setkey(combined, Date, Ticker)
        arrow::write_parquet(combined, cache_file)
        total_new <- total_new + nrow(dt_new)
        cat(sprintf("+%s rows (through %s)\n",
                    format(nrow(dt_new), big.mark = ","), max(dt_new$Date)))
      }
    }, error = function(e) cat(sprintf("ERROR: %s\n", e$message)))
  }

  # Update ticker map too
  cat("  Updating ticker_map...")
  tryCatch({
    dk <- as.data.table(read_excel(CONSENSUS_XLSX, sheet = "DATA_Key", col_names = FALSE))
    ticker_map <- data.table(
      Ticker = as.character(dk[2:nrow(dk), 1, with = FALSE][[1]]),
      Name   = as.character(dk[2:nrow(dk), 2, with = FALSE][[1]])
    )
    ticker_map <- ticker_map[!is.na(Ticker) & Ticker != ""]
    arrow::write_parquet(ticker_map, file.path(CONSENSUS_CACHE, "ticker_map.parquet"))
    cat(sprintf(" %d tickers\n", nrow(ticker_map)))
  }, error = function(e) cat(sprintf(" ERROR: %s\n", e$message)))

  cat(sprintf("Done. Total new rows: %s\n", format(total_new, big.mark = ",")))
  invisible(total_new)
}

cat("[consensus_parser.R] Loaded. Use consensus_build_cache() or consensus_incremental_update().\n")
