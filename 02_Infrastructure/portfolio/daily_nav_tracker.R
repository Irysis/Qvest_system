# =============================================================================
# Daily NAV Tracker — 사용자 등록 전략만 모니터링
# nav_register(strategy) / nav_unregister(strategy) / nav_list() / nav_track()
#
# Usage:
#   source("02_Infrastructure/daily_nav_tracker.R")
#   nav_register("STR_803")      # 추적 시작
#   nav_track()                   # 등록된 전략 일일 NAV 업데이트
#   nav_unregister("STR_803")    # 추적 중단
# =============================================================================

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
}

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

NAV_WATCHLIST_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure", "nav_watchlist.json")
NAV_TRACKING_DIR   <- file.path(PROJECT_ROOT, "04_Research", "nav_tracking")
if (!dir.exists(NAV_TRACKING_DIR)) dir.create(NAV_TRACKING_DIR, recursive = TRUE)

# --- Watchlist I/O ---
.nav_read_watchlist <- function() {
  if (!file.exists(NAV_WATCHLIST_PATH)) return(list())
  tryCatch(fromJSON(NAV_WATCHLIST_PATH, simplifyDataFrame = FALSE),
           error = function(e) list())
}

.nav_write_watchlist <- function(wl) {
  write_json(wl, NAV_WATCHLIST_PATH, auto_unbox = TRUE, pretty = TRUE)
}

#' Register a strategy for daily NAV tracking
#' @param strategy_name e.g. "STR_803"
nav_register <- function(strategy_name) {
  wl <- .nav_read_watchlist()

  # Find the strategy's output directory (holdings_detail.csv)
  strat_dirs <- list.dirs(file.path(PROJECT_ROOT, "04_Research", "strategies"),
                           recursive = FALSE)
  match_dir <- strat_dirs[grepl(strategy_name, basename(strat_dirs), fixed = TRUE)]
  if (length(match_dir) == 0) {
    cat(sprintf("[nav] Strategy directory not found for %s\n", strategy_name))
    return(invisible(FALSE))
  }

  # Find holdings_detail.csv
  hd_files <- list.files(match_dir[1], pattern = "holdings_detail\\.csv$",
                          recursive = TRUE, full.names = TRUE)
  if (length(hd_files) == 0) {
    cat(sprintf("[nav] No holdings_detail.csv found for %s\n", strategy_name))
    return(invisible(FALSE))
  }

  wl[[strategy_name]] <- list(
    registered = format(Sys.time(), "%Y-%m-%d %H:%M"),
    holdings_path = hd_files[1],
    output_dir = dirname(hd_files[1])
  )
  .nav_write_watchlist(wl)
  cat(sprintf("[nav] Registered: %s (holdings: %s)\n", strategy_name, basename(hd_files[1])))
  invisible(TRUE)
}

#' Unregister a strategy from tracking
nav_unregister <- function(strategy_name) {
  wl <- .nav_read_watchlist()
  if (strategy_name %in% names(wl)) {
    wl[[strategy_name]] <- NULL
    .nav_write_watchlist(wl)
    cat(sprintf("[nav] Unregistered: %s\n", strategy_name))
  } else {
    cat(sprintf("[nav] %s not in watchlist\n", strategy_name))
  }
  invisible(NULL)
}

#' List all registered strategies
nav_list <- function() {
  wl <- .nav_read_watchlist()
  if (length(wl) == 0) {
    cat("[nav] Watchlist empty\n")
    return(invisible(data.table()))
  }
  dt <- rbindlist(lapply(names(wl), function(nm) {
    data.table(Strategy = nm, Registered = wl[[nm]]$registered)
  }))
  print(dt)
  invisible(dt)
}

#' Run daily NAV tracking for all registered strategies
#' Reads latest holdings, computes NAV from current RAWDATA prices
#' @param alert_dd_short DD threshold for short-term alert (default 4%)
#' @param alert_dd_med DD threshold for medium-term alert (default 8%)
nav_track <- function(alert_dd_short = 0.04, alert_dd_med = 0.08) {
  wl <- .nav_read_watchlist()
  if (length(wl) == 0) {
    cat("[nav] No strategies registered. Use nav_register() first.\n")
    return(invisible(NULL))
  }

  # Load RAWDATA for latest prices
  RAWDATA <- as.data.table(read_parquet(RAWDATA_CACHE))
  latest_date <- max(RAWDATA$Date)
  cat(sprintf("[nav] Tracking %d strategies | Latest data: %s\n", length(wl), latest_date))

  alerts <- list()

  for (strat_name in names(wl)) {
    entry <- wl[[strat_name]]
    hd_path <- entry$holdings_path

    if (!file.exists(hd_path)) {
      cat(sprintf("  [%s] holdings_detail.csv missing, skipping\n", strat_name))
      next
    }

    # Read holdings
    hd <- tryCatch(fread(hd_path), error = function(e) NULL)
    if (is.null(hd) || nrow(hd) == 0) next

    # Get latest rebalance holdings
    if ("Signal_Date" %in% names(hd)) {
      latest_reb <- max(hd$Signal_Date)
      current_holdings <- hd[Signal_Date == latest_reb]
    } else if ("Exec_Date" %in% names(hd)) {
      latest_reb <- max(hd$Exec_Date)
      current_holdings <- hd[Exec_Date == latest_reb]
    } else {
      current_holdings <- tail(hd, 20)  # fallback: last 20 rows
    }

    tickers <- unique(current_holdings$Ticker)
    if (length(tickers) == 0) next

    # Compute daily portfolio return (EW)
    port_data <- RAWDATA[Ticker %in% tickers & !is.na(Ret)]
    if (nrow(port_data) == 0) next

    daily_port <- port_data[, .(PortRet = mean(Ret, na.rm = TRUE)), by = Date]
    setorder(daily_port, Date)
    daily_port[, NAV := cumprod(1 + PortRet) * 10000]
    daily_port[, DD := 1 - NAV / cummax(NAV)]

    # Save NAV time series
    nav_file <- file.path(NAV_TRACKING_DIR, paste0(strat_name, "_nav.csv"))
    fwrite(daily_port, nav_file)

    # Current stats
    current_dd <- tail(daily_port$DD, 1)
    current_nav <- tail(daily_port$NAV, 1)
    ytd_ret <- tail(daily_port$NAV, 1) / daily_port[year(Date) == year(latest_date)][1]$NAV - 1

    # 20d short-term DD
    if (nrow(daily_port) >= 20) {
      last20 <- tail(daily_port, 20)
      short_dd <- 1 - tail(last20$NAV, 1) / max(last20$NAV)
    } else {
      short_dd <- 0
    }

    cat(sprintf("  [%s] NAV=%.0f | DD=%.1f%% | 20d-DD=%.1f%% | Holdings=%d\n",
                strat_name, current_nav, current_dd * 100, short_dd * 100, length(tickers)))

    # Alert checks
    if (short_dd >= alert_dd_short) {
      alerts[[length(alerts) + 1]] <- list(
        strategy = strat_name, type = "SHORT_DD",
        value = short_dd, threshold = alert_dd_short
      )
    }
    if (current_dd >= alert_dd_med) {
      alerts[[length(alerts) + 1]] <- list(
        strategy = strat_name, type = "MED_DD",
        value = current_dd, threshold = alert_dd_med
      )
    }
  }

  # Send alerts via Telegram
  if (length(alerts) > 0 && exists("tg_send")) {
    for (a in alerts) {
      msg <- paste0(
        "[NAV ALERT] ", a$strategy, "\n",
        a$type, ": ", round(a$value * 100, 1), "% (threshold: ", round(a$threshold * 100, 1), "%)"
      )
      tryCatch(tg_send(msg), error = function(e) NULL)
    }
    cat(sprintf("[nav] %d alerts sent via Telegram\n", length(alerts)))
  }

  invisible(list(tracked = names(wl), alerts = alerts))
}

cat("[daily_nav_tracker] Loaded. Functions: nav_register(), nav_unregister(), nav_list(), nav_track()\n")
