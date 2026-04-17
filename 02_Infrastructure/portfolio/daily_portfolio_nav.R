#==============================================================================
# Quant Module — Daily Portfolio NAV Report
# daily_portfolio_nav.R
# Version: 1.0.0
#
# 매일 아침 전일 종가 기준 포트폴리오 수익률을 계산하고 텔레그램으로 발송.
# Multi-sleeve 및 single-sim 모두 지원.
#
# Functions:
#   daily_nav_report(strategy_id)   — 단일 전략 NAV 보고
#   daily_nav_summary(strategy_ids) — 복수 전략 일괄 요약
#
# Usage:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/backtest_harness.R")
#   source("02_Infrastructure/sleeve_save_helper.R")
#   source("02_Infrastructure/daily_portfolio_nav.R")
#   daily_nav_report("STR_905")
#
# Cron: Add to morning_briefing.sh
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

# ─── Ensure infrastructure is loaded ─────────────────────────────────────────
if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
}
if (!exists("load_rawdata")) {
  source(file.path(PROJECT_ROOT, "02_Infrastructure", "backtest_harness.R"))
}
if (!exists("get_portfolio_at_date")) {
  source(file.path(PROJECT_ROOT, "02_Infrastructure", "sleeve_save_helper.R"))
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

cat("[daily_nav] Loaded.\n")


#==============================================================================
# Internal: Find strategy directory by ID
#==============================================================================
.find_strategy_dir <- function(strategy_id) {
  strat_base <- file.path(PROJECT_ROOT, "04_Research", "strategies")
  # Exact match first
  exact <- file.path(strat_base, strategy_id)
  if (dir.exists(exact)) return(exact)

  # Pattern match: STR_905 -> STR_905_*
  candidates <- list.dirs(strat_base, recursive = FALSE, full.names = TRUE)
  matched <- candidates[grepl(strategy_id, basename(candidates), fixed = TRUE)]
  if (length(matched) == 0) return(NULL)
  # Return the most recently modified
  mtimes <- file.mtime(matched)
  matched[which.max(mtimes)]
}


#==============================================================================
# Internal: Load holdings from sim_result or sleeve CSVs
#==============================================================================
.load_latest_holdings <- function(strat_dir) {

  output_dir <- file.path(strat_dir, "output")

  # ── Try 1: Individual sleeve CSV files ──
  sleeve_csvs <- list.files(output_dir, pattern = "^holdings_sleeve_.*\\.csv$",
                            full.names = TRUE)
  if (length(sleeve_csvs) > 0) {
    all_h <- rbindlist(lapply(sleeve_csvs, fread), fill = TRUE)
    # Get latest rebalancing date per sleeve
    latest <- all_h[, .SD[Signal_Date == max(Signal_Date)], by = Sleeve]
    cat(sprintf("[daily_nav] Loaded %d sleeve holdings (%d unique tickers)\n",
                nrow(latest), uniqueN(latest$Ticker)))
    return(latest)
  }

  # ── Try 2: Combined holdings file ──
  combined <- file.path(output_dir, "holdings_all_sleeves.csv")
  if (file.exists(combined)) {
    dt <- fread(combined)
    latest <- dt[Signal_Date == max(Signal_Date)]
    cat(sprintf("[daily_nav] Loaded combined holdings: %d tickers\n", nrow(latest)))
    return(latest)
  }

  # ── Try 3: Single holdings_detail.csv ──
  detail <- file.path(output_dir, "holdings_detail.csv")
  if (file.exists(detail)) {
    dt <- fread(detail)
    latest <- dt[Signal_Date == max(Signal_Date)]
    if (!"Sleeve" %in% names(latest)) latest[, Sleeve := "single"]
    cat(sprintf("[daily_nav] Loaded detail holdings: %d tickers\n", nrow(latest)))
    return(latest)
  }

  # ── Try 4: Extract from sim_result.rds HOLDINGS_LOG ──
  rds_path <- file.path(strat_dir, "sim_result.rds")
  if (file.exists(rds_path)) {
    sim <- readRDS(rds_path)
    if (!is.null(sim$HOLDINGS_LOG) && nrow(sim$HOLDINGS_LOG) > 0) {
      hl <- as.data.table(sim$HOLDINGS_LOG)
      latest <- hl[Signal_Date == max(Signal_Date)]
      if (!"Sleeve" %in% names(latest)) latest[, Sleeve := "single"]
      cat(sprintf("[daily_nav] Loaded from sim_result HOLDINGS_LOG: %d tickers\n",
                  nrow(latest)))
      return(latest)
    }
  }

  # ── Try 5: Per-sleeve sim RDS files ──
  sleeve_rds <- list.files(strat_dir, pattern = "^sim_sleeve_.*\\.rds$",
                           full.names = TRUE)
  if (length(sleeve_rds) > 0) {
    all_h <- list()
    for (f in sleeve_rds) {
      sname <- gsub("sim_sleeve_|\\.rds$", "", basename(f))
      sim <- readRDS(f)
      if (!is.null(sim$HOLDINGS_LOG) && nrow(sim$HOLDINGS_LOG) > 0) {
        hl <- as.data.table(sim$HOLDINGS_LOG)
        hl[, Sleeve := sname]
        latest <- hl[Signal_Date == max(Signal_Date)]
        all_h[[sname]] <- latest
      }
    }
    if (length(all_h) > 0) {
      result <- rbindlist(all_h, fill = TRUE)
      cat(sprintf("[daily_nav] Loaded from %d sleeve RDS: %d tickers\n",
                  length(all_h), nrow(result)))
      return(result)
    }
  }

  cat("[daily_nav] WARNING: No holdings found.\n")
  return(NULL)
}


#==============================================================================
# Internal: Load FM weights from strategy output or default to equal
#==============================================================================
.load_fm_weights <- function(strat_dir, sleeves) {
  # Try reading from the strategy's performance CSV or run_all output
  perf_file <- file.path(strat_dir, "output", "sleeve_annual_contribution.csv")
  if (file.exists(perf_file)) {
    # Extract most recent FM weights if embedded
    # (sleeves are named A_defense, B_indmom, C_consensus etc.)
  }

  # Default: equal weight across sleeves
  n_sleeves <- length(unique(sleeves))
  if (n_sleeves <= 1) return(data.table(Sleeve = unique(sleeves), FM_Weight = 1.0))

  w <- 1.0 / n_sleeves
  data.table(Sleeve = unique(sleeves), FM_Weight = w)
}


#==============================================================================
# daily_nav_report() — Main function
#==============================================================================

daily_nav_report <- function(strategy_id  = "STR_905",
                              report_date = NULL,
                              send_telegram = TRUE,
                              save_tracking = TRUE) {

  cat("\n")
  cat("==============================================================================\n")
  cat(sprintf("  Daily NAV Report — %s\n", strategy_id))
  cat(sprintf("  %s\n", Sys.time()))
  cat("==============================================================================\n\n")

  # ── Step 1: Find strategy directory ──
  strat_dir <- .find_strategy_dir(strategy_id)
  if (is.null(strat_dir)) {
    cat(sprintf("[daily_nav] ERROR: Strategy directory not found for %s\n", strategy_id))
    return(invisible(NULL))
  }
  cat(sprintf("[daily_nav] Strategy dir: %s\n", basename(strat_dir)))

  # ── Step 2: Load holdings ──
  holdings <- .load_latest_holdings(strat_dir)
  if (is.null(holdings) || nrow(holdings) == 0) {
    cat("[daily_nav] ERROR: No holdings to track.\n")
    return(invisible(NULL))
  }

  # Ensure required columns
  if (!"Ticker" %in% names(holdings)) {
    cat("[daily_nav] ERROR: Holdings missing 'Ticker' column.\n")
    return(invisible(NULL))
  }

  # ── Step 3: Load RAWDATA for prices ──
  if (!exists("RAWDATA", envir = .GlobalEnv) || nrow(get("RAWDATA", envir = .GlobalEnv)) == 0) {
    cat("[daily_nav] Loading RAWDATA...\n")
    res <- load_rawdata()
    RAWDATA <<- res$RAWDATA
    BM_DT   <<- res$BM_DT
  }
  rawdata <- get("RAWDATA", envir = .GlobalEnv)
  bm_dt   <- get("BM_DT", envir = .GlobalEnv)

  # ── Step 4: Determine report date (yesterday = most recent trading day) ──
  all_dates <- sort(unique(rawdata$Date))
  if (is.null(report_date)) {
    # Most recent 2 trading days
    report_date <- all_dates[length(all_dates)]
  } else {
    report_date <- as.Date(report_date)
  }

  prev_date_idx <- which(all_dates == report_date) - 1L
  if (prev_date_idx < 1) {
    cat("[daily_nav] ERROR: Not enough history for daily return calc.\n")
    return(invisible(NULL))
  }
  prev_date <- all_dates[prev_date_idx]

  cat(sprintf("[daily_nav] Report date: %s | Previous: %s\n",
              report_date, prev_date))

  # ── Step 5: Get closing prices for holdings ──
  tickers <- unique(holdings$Ticker)

  prices_today <- rawdata[Ticker %in% tickers & Date == report_date,
                          .(Ticker, Close_Today = Close, Name)]
  prices_yesterday <- rawdata[Ticker %in% tickers & Date == prev_date,
                              .(Ticker, Close_Yesterday = Close)]

  price_dt <- merge(prices_today, prices_yesterday, by = "Ticker", all.x = TRUE)

  # Handle missing prices (delisted, suspended)
  price_dt[is.na(Close_Today), Close_Today := Close_Yesterday]
  price_dt[is.na(Close_Yesterday), Close_Yesterday := Close_Today]
  price_dt[, Daily_Ret := fifelse(
    Close_Yesterday > 0,
    Close_Today / Close_Yesterday - 1,
    0.0
  )]

  # ── Step 6: Merge with holdings and compute contributions ──
  # Normalize weights within each sleeve
  holdings_w <- copy(holdings)
  if (!"Weight" %in% names(holdings_w)) {
    # EW fallback within sleeve
    holdings_w[, Weight := 1.0 / .N, by = Sleeve]
  }

  # Get FM weights per sleeve
  sleeves <- unique(holdings_w$Sleeve)
  fm_w <- .load_fm_weights(strat_dir, sleeves)
  holdings_w <- merge(holdings_w, fm_w, by = "Sleeve", all.x = TRUE)
  holdings_w[, Portfolio_Weight := Weight * FM_Weight]

  # Merge prices
  result_dt <- merge(holdings_w, price_dt, by = "Ticker", all.x = TRUE)
  result_dt[is.na(Daily_Ret), Daily_Ret := 0.0]
  result_dt[, Contribution := Daily_Ret * Portfolio_Weight]

  # ── Step 7: Compute returns ──
  portfolio_ret <- sum(result_dt$Contribution, na.rm = TRUE)

  # Sleeve-level returns
  sleeve_rets <- result_dt[, .(
    Sleeve_Ret = sum(Contribution, na.rm = TRUE),
    N_Stocks   = .N
  ), by = Sleeve]
  sleeve_rets <- merge(sleeve_rets, fm_w, by = "Sleeve", all.x = TRUE)

  # Benchmark return
  bm_today     <- bm_dt[Date == report_date, BM_Ret]
  bm_yesterday <- bm_dt[Date == prev_date, BM_Ret]
  # BM_Ret is usually daily return already; if not, compute from Close
  if ("Close" %in% names(bm_dt)) {
    bm_close_t <- bm_dt[Date == report_date, Close]
    bm_close_y <- bm_dt[Date == prev_date, Close]
    bm_ret <- if (length(bm_close_t) > 0 && length(bm_close_y) > 0 && bm_close_y > 0) {
      bm_close_t / bm_close_y - 1
    } else if (length(bm_today) > 0) {
      bm_today[1]
    } else 0
  } else {
    bm_ret <- if (length(bm_today) > 0) bm_today[1] else 0
  }

  active_ret <- portfolio_ret - bm_ret

  # ── Step 8: Compute MTD, YTD, DD ──
  nav_tracking_dir <- file.path(PROJECT_ROOT, "04_Research", "nav_tracking")
  if (!dir.exists(nav_tracking_dir)) dir.create(nav_tracking_dir, recursive = TRUE)

  tracking_file <- file.path(nav_tracking_dir, sprintf("%s_daily_nav.csv", strategy_id))

  # Load existing tracking data
  if (file.exists(tracking_file)) {
    track_dt <- fread(tracking_file)
    track_dt[, Date := as.Date(Date)]
  } else {
    track_dt <- data.table(
      Date = as.Date(character(0)),
      Portfolio_Ret = numeric(0),
      BM_Ret = numeric(0),
      Active_Ret = numeric(0)
    )
  }

  # Compute cumulative metrics from tracking history + today
  today_row <- data.table(
    Date          = report_date,
    Portfolio_Ret = portfolio_ret,
    BM_Ret        = bm_ret,
    Active_Ret    = active_ret
  )

  # Add sleeve returns as columns
  for (i in seq_len(nrow(sleeve_rets))) {
    col_name <- sprintf("Sleeve_%s_Ret", sleeve_rets$Sleeve[i])
    today_row[[col_name]] <- sleeve_rets$Sleeve_Ret[i]
  }

  # Append/replace today's row
  if (nrow(track_dt) > 0) {
    track_dt <- track_dt[Date != report_date]
  }
  track_dt <- rbind(track_dt, today_row, fill = TRUE)
  setorder(track_dt, Date)

  # MTD: cumulative return for current month
  cur_month <- format(report_date, "%Y-%m")
  mtd_rows <- track_dt[format(Date, "%Y-%m") == cur_month]
  mtd_ret <- if (nrow(mtd_rows) > 0) {
    prod(1 + mtd_rows$Portfolio_Ret) - 1
  } else portfolio_ret

  # YTD: cumulative return for current year
  cur_year <- format(report_date, "%Y")
  ytd_rows <- track_dt[format(Date, "%Y") == cur_year]
  ytd_ret <- if (nrow(ytd_rows) > 0) {
    prod(1 + ytd_rows$Portfolio_Ret) - 1
  } else portfolio_ret

  # Drawdown from peak (using all tracking history)
  if (nrow(track_dt) > 0) {
    track_dt[, Cum_NAV := cumprod(1 + Portfolio_Ret)]
    track_dt[, Peak_NAV := cummax(Cum_NAV)]
    dd_from_peak <- 1 - track_dt[.N, Cum_NAV] / track_dt[.N, Peak_NAV]

    # Add computed fields to today's row for saving
    today_row$MTD <- mtd_ret
    today_row$YTD <- ytd_ret
    today_row$DD_from_Peak <- dd_from_peak
  } else {
    dd_from_peak <- 0
    today_row$MTD <- mtd_ret
    today_row$YTD <- ytd_ret
    today_row$DD_from_Peak <- 0
  }

  # ── Step 9: Top / Bottom performers ──
  setorder(result_dt, -Daily_Ret)
  top3 <- head(result_dt[Daily_Ret > 0], 3)
  bot3 <- tail(result_dt[Daily_Ret < 0], 3)
  setorder(bot3, Daily_Ret)

  # ── Step 10: Generate console report ──
  cat("\n")
  cat(sprintf("  Portfolio: %+.2f%% | BM: %+.2f%% | Active: %+.2f%%\n",
              100 * portfolio_ret, 100 * bm_ret, 100 * active_ret))
  cat(sprintf("  MTD: %+.2f%% | YTD: %+.2f%% | DD: -%.2f%%\n",
              100 * mtd_ret, 100 * ytd_ret, 100 * dd_from_peak))

  cat("\n  Sleeve Returns:\n")
  for (i in seq_len(nrow(sleeve_rets))) {
    cat(sprintf("    %s (%.0f%%): %+.2f%%  [%d stocks]\n",
                sleeve_rets$Sleeve[i],
                100 * sleeve_rets$FM_Weight[i],
                100 * sleeve_rets$Sleeve_Ret[i],
                sleeve_rets$N_Stocks[i]))
  }

  if (nrow(top3) > 0) {
    cat("\n  Top performers:\n")
    for (i in seq_len(nrow(top3))) {
      r <- top3[i]
      nm <- if ("Name.y" %in% names(r)) r$Name.y else if ("Name" %in% names(r)) r$Name else ""
      if (is.na(nm)) nm <- r$Ticker
      cat(sprintf("    + %s %+.1f%% [%s]\n", nm, 100 * r$Daily_Ret, r$Sleeve))
    }
  }
  if (nrow(bot3) > 0) {
    cat("  Bottom performers:\n")
    for (i in seq_len(nrow(bot3))) {
      r <- bot3[i]
      nm <- if ("Name.y" %in% names(r)) r$Name.y else if ("Name" %in% names(r)) r$Name else ""
      if (is.na(nm)) nm <- r$Ticker
      cat(sprintf("    - %s %+.1f%% [%s]\n", nm, 100 * r$Daily_Ret, r$Sleeve))
    }
  }

  # ── Step 11: Save tracking file ──
  if (save_tracking) {
    # Re-build full tracking with all fields
    track_save <- copy(track_dt)
    # Replace today's row with updated one
    track_save <- track_save[Date != report_date]
    track_save <- rbind(track_save, today_row, fill = TRUE)
    setorder(track_save, Date)

    # Remove temp columns
    for (cc in c("Cum_NAV", "Peak_NAV")) {
      if (cc %in% names(track_save)) track_save[, (cc) := NULL]
    }

    fwrite(track_save, tracking_file)
    cat(sprintf("\n[daily_nav] Tracking saved: %s (%d days)\n",
                tracking_file, nrow(track_save)))
  }

  # ── Step 12: Telegram report ──
  if (send_telegram) {
    tryCatch({
      tg_path <- file.path(PROJECT_ROOT, "02_Infrastructure", "telegram", "telegram_notify.R")
      if (!exists("tg_send") && file.exists(tg_path)) source(tg_path)

      if (exists("tg_send")) {

        # ── QTD (Quarter-to-Date) ──
        cur_q_start <- as.Date(sprintf("%s-%02d-01", cur_year,
          (as.integer(format(report_date, "%m")) - 1) %/% 3 * 3 + 1))
        qtd_rows <- track_dt[Date >= cur_q_start & Date <= report_date]
        qtd_ret <- if (nrow(qtd_rows) > 0) prod(1 + qtd_rows$Portfolio_Ret) - 1 else 0

        # ── Risk metrics (from tracking history) ──
        n_track <- nrow(track_dt)
        if (n_track >= 20) {
          recent_20d_vol <- sd(tail(track_dt$Portfolio_Ret, 20)) * sqrt(252) * 100
          consec_neg <- 0; max_consec <- 0
          for (r_val in tail(track_dt$Portfolio_Ret, 60)) {
            if (r_val < 0) { consec_neg <- consec_neg + 1; max_consec <- max(max_consec, consec_neg) }
            else consec_neg <- 0
          }
        } else {
          recent_20d_vol <- NA; max_consec <- 0
        }

        # ── Check rebalancing signal (is today a signal date?) ──
        # Load production config for rebalancing schedule
        prod_cfg_path <- file.path(PROJECT_ROOT, "05_Production", "production_config.json")
        rebal_msg <- NULL
        if (file.exists(prod_cfg_path)) {
          prod_cfg <- tryCatch(fromJSON(prod_cfg_path), error = function(e) NULL)
          if (!is.null(prod_cfg)) {
            strat_cfg <- prod_cfg$strategies[[strategy_id]]
            if (!is.null(strat_cfg)) {
              rebal_months <- strat_cfg$rebalancing$months
              cur_month_num <- as.integer(format(report_date, "%m"))
              # Signal on last trading day of rebalancing month
              next_date <- all_dates[which(all_dates == report_date) + 1]
              next_month <- if (!is.na(next_date)) as.integer(format(next_date, "%m")) else cur_month_num
              if (cur_month_num %in% rebal_months && next_month != cur_month_num) {
                # Today is last trading day of a rebalancing month!
                rebal_msg <- sprintf("REBALANCING SIGNAL\n%s %s\n",
                  strategy_id, format(report_date, "%Y-%m"))
                # Show current holdings
                rebal_msg <- paste0(rebal_msg, "\nCurrent Portfolio:\n")
                for (i in seq_len(nrow(result_dt))) {
                  r <- result_dt[i]
                  nm <- if ("Name.y" %in% names(r)) r$Name.y else if ("Name" %in% names(r)) r$Name else ""
                  if (is.na(nm)) nm <- ""
                  rebal_msg <- paste0(rebal_msg,
                    sprintf("%s %s %.1f%% [%s]\n",
                      r$Ticker, nm, r$Portfolio_Weight*100, r$Sleeve))
                }
                rebal_msg <- paste0(rebal_msg,
                  "\nRun pm_run_multisleeve() for new signal")
              }
            }
          }
        }

        # ── Build telegram message ──
        tg_lines <- character(0)
        tg_lines <- c(tg_lines,
          sprintf("%s Morning Briefing (%s)", strategy_id, report_date),
          "",
          "--- Returns ---",
          sprintf("Daily:   Port %+.2f%% | BM %+.2f%% | Active %+.2f%%",
                  100*portfolio_ret, 100*bm_ret, 100*active_ret),
          sprintf("MTD:     %+.2f%%", 100*mtd_ret),
          sprintf("QTD:     %+.2f%%", 100*qtd_ret),
          sprintf("YTD:     %+.2f%%", 100*ytd_ret),
          "")

        # Sleeve breakdown
        tg_lines <- c(tg_lines, "--- Sleeves ---")
        for (i in seq_len(nrow(sleeve_rets))) {
          tg_lines <- c(tg_lines,
            sprintf("%s (%.0f%%): %+.2f%%",
                    sleeve_rets$Sleeve[i],
                    100*sleeve_rets$FM_Weight[i],
                    100*sleeve_rets$Sleeve_Ret[i]))
        }

        # Risk metrics
        tg_lines <- c(tg_lines, "", "--- Risk ---",
          sprintf("DD from Peak: -%.2f%%", 100*dd_from_peak))
        if (!is.na(recent_20d_vol))
          tg_lines <- c(tg_lines, sprintf("20D Vol(ann): %.1f%%", recent_20d_vol))
        if (max_consec > 0)
          tg_lines <- c(tg_lines, sprintf("Max Consec Loss: %d days", max_consec))

        # Top/Bottom
        tg_lines <- c(tg_lines, "", "--- Top/Bottom ---")
        if (nrow(top3) > 0) {
          for (i in seq_len(nrow(top3))) {
            r <- top3[i]
            nm <- if ("Name.y" %in% names(r)) r$Name.y else if ("Name" %in% names(r)) r$Name else r$Ticker
            if (is.na(nm)) nm <- r$Ticker
            tg_lines <- c(tg_lines,
              sprintf("+ %s %+.1f%% (%s)", nm, 100*r$Daily_Ret, r$Sleeve))
          }
        }
        if (nrow(bot3) > 0) {
          for (i in seq_len(nrow(bot3))) {
            r <- bot3[i]
            nm <- if ("Name.y" %in% names(r)) r$Name.y else if ("Name" %in% names(r)) r$Name else r$Ticker
            if (is.na(nm)) nm <- r$Ticker
            tg_lines <- c(tg_lines,
              sprintf("- %s %+.1f%% (%s)", nm, 100*r$Daily_Ret, r$Sleeve))
          }
        }

        # Rebalancing alert (if applicable)
        if (!is.null(rebal_msg)) {
          tg_lines <- c(tg_lines, "", "===", rebal_msg)
        }

        tg_msg <- paste(tg_lines, collapse = "\n")
        tg_send(tg_msg)
        cat("[daily_nav] Telegram sent.\n")
      }
    }, error = function(e) {
      cat(sprintf("[daily_nav] Telegram error: %s\n", e$message))
    })
  }

  cat("\n==============================================================================\n")
  cat(sprintf("  Daily NAV Report — %s — Complete\n", strategy_id))
  cat("==============================================================================\n")

  invisible(list(
    strategy_id  = strategy_id,
    report_date  = report_date,
    portfolio_ret = portfolio_ret,
    bm_ret       = bm_ret,
    active_ret   = active_ret,
    mtd          = mtd_ret,
    ytd          = ytd_ret,
    dd           = dd_from_peak,
    sleeve_rets  = sleeve_rets,
    holdings     = result_dt,
    top          = top3,
    bottom       = bot3
  ))
}


#==============================================================================
# daily_nav_summary() — Multiple strategies at once
#==============================================================================

daily_nav_summary <- function(strategy_ids = c("STR_905"),
                               report_date  = NULL,
                               send_telegram = TRUE) {

  cat("\n")
  cat("==============================================================================\n")
  cat("  Daily NAV Summary — Multi-Strategy\n")
  cat(sprintf("  %s | %d strategies\n", Sys.time(), length(strategy_ids)))
  cat("==============================================================================\n\n")

  results <- list()

  for (sid in strategy_ids) {
    cat(sprintf("\n--- %s ---\n", sid))
    tryCatch({
      r <- daily_nav_report(sid,
                            report_date   = report_date,
                            send_telegram = FALSE,
                            save_tracking = TRUE)
      if (!is.null(r)) results[[sid]] <- r
    }, error = function(e) {
      cat(sprintf("[daily_nav] %s ERROR: %s\n", sid, e$message))
    })
  }

  if (length(results) == 0) {
    cat("[daily_nav] No results to summarize.\n")
    return(invisible(NULL))
  }

  # ── Summary table ──
  summary_dt <- rbindlist(lapply(results, function(r) {
    data.table(
      Strategy     = r$strategy_id,
      Date         = r$report_date,
      Portfolio    = sprintf("%+.2f%%", 100 * r$portfolio_ret),
      BM           = sprintf("%+.2f%%", 100 * r$bm_ret),
      Active       = sprintf("%+.2f%%", 100 * r$active_ret),
      MTD          = sprintf("%+.1f%%", 100 * r$mtd),
      YTD          = sprintf("%+.1f%%", 100 * r$ytd),
      DD           = sprintf("-%.1f%%", 100 * r$dd)
    )
  }))

  cat("\n\n  Summary:\n")
  print(summary_dt)

  # ── Telegram summary ──
  if (send_telegram) {
    tryCatch({
      tg_path <- file.path(PROJECT_ROOT, "02_Infrastructure", "telegram", "telegram_notify.R")
      if (!exists("tg_send") && file.exists(tg_path)) source(tg_path)

      if (exists("tg_send")) {
        rd <- if (!is.null(report_date)) report_date else results[[1]]$report_date
        tg_lines <- c(sprintf("<b>Daily NAV Summary (%s)</b>", rd), "")

        for (r in results) {
          tg_lines <- c(tg_lines,
            sprintf("<b>%s</b>: %+.2f%% (Active: %+.2f%%) | MTD %+.1f%% | DD -%.1f%%",
                    r$strategy_id, 100*r$portfolio_ret, 100*r$active_ret,
                    100*r$mtd, 100*r$dd))
        }

        tg_send(paste(tg_lines, collapse = "\n"))
        cat("[daily_nav] Summary telegram sent.\n")
      }
    }, error = function(e) {
      cat(sprintf("[daily_nav] Telegram error: %s\n", e$message))
    })
  }

  invisible(list(
    results = results,
    summary = summary_dt
  ))
}
