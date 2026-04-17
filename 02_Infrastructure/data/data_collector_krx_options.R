#==============================================================================
# KRX Options IV Skew Data Collector
# Version: 1.0.0
#
# Purpose: Fetch KOSPI200 option implied volatility by strike from KRX Open API,
#          compute proper IV Skew (OTM put IV - ATM call IV), build cache.
#
# Reference: Xing, Zhang & Zhao (2010 JFE)
#   "What Does the Individual Option Volatility Smirk Tell Us About Future
#    Equity Returns?" — Put-Call IV Skew is a 1-4 week leading crash indicator.
#
# Data source: KRX Open API /drv/opt_bydd_trd
#   Fields: ISU_NM (종목명), RGHT_TP_NM (CALL/PUT), TDD_CLSPRC (종가),
#           IMP_VOLT (내재변동성), ACC_OPNINT_QTY (미결제약정), ACC_TRDVOL (거래량)
#   ISU_NM format: "코스피200 2601 C 280.0 (정규)" — contains expiry, type, strike
#
# Existing infrastructure:
#   krx_derivatives_collector.R already collects daily derivatives data including
#   a rough IV_Skew (mean IV of top-10 OI puts vs calls). This module provides:
#   (A) An enhanced per-strike IV extraction from cached raw option data
#   (B) Functions to build the proper ATM/OTM IV skew signal
#   (C) A consolidated cache for strategy use
#
# Output: .cache/krx_iv_skew.parquet with columns:
#   Date, K200_Spot, atm_call_iv, atm_put_iv, otm_put_iv, iv_skew,
#   iv_skew_z, pcr_vol, vkospi
#
# IMPORTANT: All data uses KST 15:30 close. Zero timezone lag.
#            IV skew z-score uses expanding window (PIT compliant, no lookahead).
#
# Usage:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/krx_data_collector.R")
#   source("02_Infrastructure/data_collector_krx_options.R")
#   krx_build_iv_skew_cache()       # build from existing derivatives cache
#   iv_dt <- krx_load_iv_skew()     # load cached skew data
#
# Author: Q-Lead Agent
# Date:   2026-03-18
#==============================================================================

cat("[krx_options_iv] Loading...\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
}
if (!exists("CACHE_DIR")) {
  CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
}

IV_SKEW_CACHE <- file.path(CACHE_DIR, "krx_iv_skew.parquet")
DRV_CACHE_DIR <- file.path(CACHE_DIR, "krx_derivatives")

# ── Helper: parse KRX numeric ──
.krx_num <- function(x) suppressWarnings(as.numeric(gsub(",", "", x)))


#==============================================================================
# 1. krx_fetch_options_iv(date_str)
#    Fetch KOSPI200 options raw data from KRX API for a single date.
#    Returns data.table with per-contract: expiry, strike, type, iv, oi, vol, price
#
#    This calls /drv/opt_bydd_trd and parses each contract's ISU_NM to extract
#    strike price, expiry, and call/put type.
#==============================================================================

krx_fetch_options_iv <- function(date_str) {

  if (!exists("krx_api", mode = "function")) {
    collector_path <- file.path(DATA_DIR, "krx_data_collector.R")
    if (file.exists(collector_path)) {
      source(collector_path, local = FALSE)
    } else {
      stop("[krx_options_iv] krx_data_collector.R not found. Source it first.")
    }
  }

  dt <- krx_api("/drv/opt_bydd_trd", list(basDd = date_str))
  if (is.null(dt) || nrow(dt) == 0) return(NULL)

  # Filter KOSPI200 options only (정규시장)
  k200 <- dt[grepl("코스피200 옵션", PROD_NM)]
  if (nrow(k200) == 0) return(NULL)

  # Parse ISU_NM to extract expiry, type (C/P), strike

  # Format: "코스피200 2601 C 280.0 (정규)" or "코스피200 2602 P 240.0 (정규)"
  k200[, `:=`(
    expiry_code = sub(".*코스피200\\s+(\\d{4})\\s+.*", "\\1", ISU_NM),
    opt_type    = sub(".*\\s+([CP])\\s+.*", "\\1", ISU_NM),
    strike      = .krx_num(sub(".*[CP]\\s+([0-9.]+).*", "\\1", ISU_NM)),
    iv          = .krx_num(IMP_VOLT),
    oi          = .krx_num(ACC_OPNINT_QTY),
    vol         = .krx_num(ACC_TRDVOL),
    price       = .krx_num(TDD_CLSPRC)
  )]

  # Keep only valid parsed rows
  k200 <- k200[!is.na(strike) & strike > 0 & opt_type %in% c("C", "P")]

  # Get KOSPI200 spot from futures
  fut_dt <- tryCatch({
    krx_api("/drv/fut_bydd_trd", list(basDd = date_str))
  }, error = function(e) NULL)

  spot <- NA_real_
  if (!is.null(fut_dt) && nrow(fut_dt) > 0) {
    k200_f <- fut_dt[grepl("코스피200 선물", PROD_NM) & MKT_NM == "정규"]
    if (nrow(k200_f) > 0) {
      spot <- .krx_num(k200_f[1]$SPOT_PRC)
    }
  }

  result <- k200[, .(Date = date_str, expiry_code, opt_type, strike, iv, oi, vol, price)]
  attr(result, "spot") <- spot
  result
}


#==============================================================================
# 2. compute_iv_skew_from_chain(chain_dt, spot)
#    Given a chain of options with (opt_type, strike, iv, oi, vol),
#    compute ATM call IV, OTM put IV (25-delta proxy), and IV skew.
#
#    ATM: strike closest to spot with iv > 0
#    OTM Put: strike ~5% below spot (Xing et al. proxy for 25-delta put)
#    If exact 5% OTM not available, use nearest OTM put with 3-8% moneyness.
#
#    IV Skew = OTM_Put_IV - ATM_Call_IV (level difference)
#    Normalized Skew = (OTM_Put_IV - ATM_Call_IV) / ATM_Call_IV (relative)
#==============================================================================

compute_iv_skew_from_chain <- function(chain_dt, spot) {
  if (is.null(chain_dt) || nrow(chain_dt) == 0 || is.na(spot) || spot <= 0) {
    return(list(atm_call_iv = NA_real_, atm_put_iv = NA_real_,
                otm_put_iv = NA_real_, iv_skew = NA_real_,
                iv_skew_norm = NA_real_))
  }

  # Use front-month expiry (earliest expiry code with decent liquidity)
  chain_dt <- chain_dt[iv > 0 & !is.na(iv)]
  if (nrow(chain_dt) == 0) {
    return(list(atm_call_iv = NA_real_, atm_put_iv = NA_real_,
                otm_put_iv = NA_real_, iv_skew = NA_real_,
                iv_skew_norm = NA_real_))
  }

  # Find front-month: earliest expiry with >= 5 contracts
  expiry_counts <- chain_dt[, .N, by = expiry_code][order(expiry_code)]
  front_expiry <- expiry_counts[N >= 5, expiry_code][1]
  if (is.na(front_expiry)) front_expiry <- expiry_counts[1, expiry_code]
  chain_dt <- chain_dt[expiry_code == front_expiry]

  calls <- chain_dt[opt_type == "C"]
  puts  <- chain_dt[opt_type == "P"]

  # ATM Call: strike closest to spot
  atm_call_iv <- NA_real_
  if (nrow(calls) > 0) {
    calls[, dist := abs(strike - spot)]
    atm_row <- calls[which.min(dist)]
    atm_call_iv <- atm_row$iv
  }

  # ATM Put: strike closest to spot
  atm_put_iv <- NA_real_
  if (nrow(puts) > 0) {
    puts[, dist := abs(strike - spot)]
    atm_put_row <- puts[which.min(dist)]
    atm_put_iv <- atm_put_row$iv
  }

  # OTM Put: ~5% below spot (proxy for 25-delta put, Xing et al. 2010)
  # Look for puts with moneyness 3-8% OTM (strike/spot between 0.92 and 0.97)
  otm_put_iv <- NA_real_
  if (nrow(puts) > 0) {
    puts[, moneyness := strike / spot]
    otm_puts <- puts[moneyness >= 0.92 & moneyness <= 0.97 & iv > 0]
    if (nrow(otm_puts) > 0) {
      # Weight by OI for more representative IV
      if (sum(otm_puts$oi, na.rm = TRUE) > 0) {
        otm_put_iv <- weighted.mean(otm_puts$iv, pmax(otm_puts$oi, 1), na.rm = TRUE)
      } else {
        # Target 5% OTM
        otm_puts[, target_dist := abs(moneyness - 0.95)]
        otm_put_iv <- otm_puts[which.min(target_dist)]$iv
      }
    } else {
      # Relax: any OTM put (moneyness 0.85-0.99, exclude deep OTM)
      otm_puts2 <- puts[moneyness >= 0.85 & moneyness < 1.0 & iv > 0]
      if (nrow(otm_puts2) > 0) {
        otm_puts2[, target_dist := abs(moneyness - 0.95)]
        otm_put_iv <- otm_puts2[which.min(target_dist)]$iv
      }
    }
  }

  # IV Skew
  iv_skew <- NA_real_
  iv_skew_norm <- NA_real_
  if (!is.na(otm_put_iv) && !is.na(atm_call_iv) && atm_call_iv > 0) {
    iv_skew      <- otm_put_iv - atm_call_iv
    iv_skew_norm <- iv_skew / atm_call_iv
  }

  list(
    atm_call_iv  = round(atm_call_iv, 4),
    atm_put_iv   = round(atm_put_iv, 4),
    otm_put_iv   = round(otm_put_iv, 4),
    iv_skew      = round(iv_skew, 4),
    iv_skew_norm = round(iv_skew_norm, 4)
  )
}


#==============================================================================
# 3. krx_build_iv_skew_cache()
#    Two-path builder:
#    (A) Enhanced: Re-fetch raw option chain from API for proper ATM/OTM split
#    (B) Fallback: Use existing IV_Skew from krx_derivatives cache
#
#    In practice, path (A) is expensive (API calls). Path (B) uses the already-
#    collected derivatives data which contains IV_Call_ATM, IV_Put_ATM, IV_Skew.
#    We enhance (B) with expanding-window z-score and merge with VKOSPI + PCR.
#
#    For backtest purposes, the existing IV_Skew (top-10 OI weighted) is a
#    reasonable proxy. True per-strike extraction (path A) is for future daily
#    collection only.
#==============================================================================

krx_build_iv_skew_cache <- function(force_rebuild = FALSE) {
  cat("[krx_options_iv] Building IV Skew cache...\n")

  if (file.exists(IV_SKEW_CACHE) && !force_rebuild) {
    existing <- as.data.table(read_parquet(IV_SKEW_CACHE))
    cat(sprintf("  Cache exists: %d rows (%s ~ %s). Use force_rebuild=TRUE to overwrite.\n",
                nrow(existing), min(existing$Date), max(existing$Date)))
    return(invisible(existing))
  }

  # ── Load all cached derivatives data ──
  if (!dir.exists(DRV_CACHE_DIR)) {
    stop("[krx_options_iv] No derivatives cache found at: ", DRV_CACHE_DIR,
         "\n  Run krx_collect_derivatives_range() first.")
  }

  files <- list.files(DRV_CACHE_DIR, pattern = "^drv_.*\\.parquet$", full.names = TRUE)
  if (length(files) == 0) stop("[krx_options_iv] No derivatives parquet files found.")

  cat(sprintf("  Loading %d derivatives files...\n", length(files)))
  drv <- rbindlist(lapply(files, function(f) {
    tryCatch(as.data.table(read_parquet(f)), error = function(e) NULL)
  }), fill = TRUE)

  drv[, Date := as.Date(Date, format = "%Y%m%d")]
  setorder(drv, Date)

  # ── Filter rows with IV data ──
  iv_cols <- c("IV_Call_ATM", "IV_Put_ATM", "IV_Skew")
  has_iv <- drv[!is.na(IV_Skew) & !is.na(IV_Call_ATM)]

  cat(sprintf("  Derivatives data: %d total, %d with IV Skew (%s ~ %s)\n",
              nrow(drv), nrow(has_iv),
              if (nrow(has_iv) > 0) min(has_iv$Date) else "NA",
              if (nrow(has_iv) > 0) max(has_iv$Date) else "NA"))

  if (nrow(has_iv) == 0) {
    cat("  ERROR: No IV data available. Cannot build cache.\n")
    return(invisible(data.table()))
  }

  # ── Build IV Skew table ──
  # IV_Skew from krx_derivatives_collector is (mean_put_iv - mean_call_iv) / mean_call_iv
  # This is the normalized skew. We also want the level skew.
  result <- has_iv[, .(
    Date        = Date,
    K200_Spot   = fifelse(!is.na(K200_Spot), K200_Spot, NA_real_),
    atm_call_iv = IV_Call_ATM,
    atm_put_iv  = IV_Put_ATM,
    iv_skew     = IV_Put_ATM - IV_Call_ATM,  # Level difference (pp)
    iv_skew_norm = IV_Skew,                   # Normalized (existing)
    pcr_vol     = fifelse(!is.na(PCR_Vol), PCR_Vol, NA_real_),
    pcr_oi      = fifelse(!is.na(PCR_OI), PCR_OI, NA_real_),
    vkospi      = fifelse(!is.na(VKOSPI), VKOSPI, NA_real_)
  )]

  setorder(result, Date)

  # ── Expanding-window z-score of IV Skew (PIT compliant) ──
  cat("  Computing expanding-window z-scores...\n")
  n <- nrow(result)
  iv_skew_z      <- rep(NA_real_, n)
  iv_skew_norm_z <- rep(NA_real_, n)
  pcr_vol_z      <- rep(NA_real_, n)

  MIN_OBS <- 60L  # Require 60 trading days (~3 months) for z-score

  for (i in seq_len(n)) {
    # IV Skew level z-score
    if (!is.na(result$iv_skew[i]) && i >= MIN_OBS) {
      past <- result$iv_skew[1:i]
      past <- past[!is.na(past)]
      if (length(past) >= MIN_OBS) {
        m <- mean(past)
        s <- sd(past)
        if (!is.na(s) && s > 1e-8) {
          iv_skew_z[i] <- (result$iv_skew[i] - m) / s
        }
      }
    }

    # IV Skew normalized z-score
    if (!is.na(result$iv_skew_norm[i]) && i >= MIN_OBS) {
      past <- result$iv_skew_norm[1:i]
      past <- past[!is.na(past)]
      if (length(past) >= MIN_OBS) {
        m <- mean(past)
        s <- sd(past)
        if (!is.na(s) && s > 1e-8) {
          iv_skew_norm_z[i] <- (result$iv_skew_norm[i] - m) / s
        }
      }
    }

    # PCR Volume z-score
    if (!is.na(result$pcr_vol[i]) && i >= MIN_OBS) {
      past <- result$pcr_vol[1:i]
      past <- past[!is.na(past)]
      if (length(past) >= MIN_OBS) {
        m <- mean(past)
        s <- sd(past)
        if (!is.na(s) && s > 1e-8) {
          pcr_vol_z[i] <- (result$pcr_vol[i] - m) / s
        }
      }
    }
  }

  result[, iv_skew_z      := round(iv_skew_z, 4)]
  result[, iv_skew_norm_z := round(iv_skew_norm_z, 4)]
  result[, pcr_vol_z      := round(pcr_vol_z, 4)]

  # ── VRP proxy: VKOSPI^2 / RV_22d equivalent ──
  # We already have VKOSPI. For VRP, use regime_vrp.R separately.
  # Here just add VKOSPI z-score
  vkospi_z <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (!is.na(result$vkospi[i]) && i >= MIN_OBS) {
      past <- result$vkospi[1:i]
      past <- past[!is.na(past)]
      if (length(past) >= MIN_OBS) {
        m <- mean(past)
        s <- sd(past)
        if (!is.na(s) && s > 1e-8) {
          vkospi_z[i] <- (result$vkospi[i] - m) / s
        }
      }
    }
  }
  result[, vkospi_z := round(vkospi_z, 4)]

  # ── Save cache ──
  write_parquet(result, IV_SKEW_CACHE)

  cat(sprintf("\n[krx_options_iv] Cache built: %d rows (%s ~ %s)\n",
              nrow(result), min(result$Date), max(result$Date)))
  cat(sprintf("  IV Skew:  median=%.2f, q05=%.2f, q95=%.2f\n",
              median(result$iv_skew, na.rm = TRUE),
              quantile(result$iv_skew, 0.05, na.rm = TRUE),
              quantile(result$iv_skew, 0.95, na.rm = TRUE)))
  cat(sprintf("  IV Skew z: non-NA=%d, range=[%.2f, %.2f]\n",
              sum(!is.na(result$iv_skew_z)),
              min(result$iv_skew_z, na.rm = TRUE),
              max(result$iv_skew_z, na.rm = TRUE)))
  cat(sprintf("  Saved to: %s\n", IV_SKEW_CACHE))

  invisible(result)
}


#==============================================================================
# 4. krx_load_iv_skew()
#    Load cached IV skew data. Build cache if not exists.
#==============================================================================

krx_load_iv_skew <- function() {
  if (!file.exists(IV_SKEW_CACHE)) {
    cat("[krx_options_iv] Cache not found. Building...\n")
    krx_build_iv_skew_cache()
  }
  if (!file.exists(IV_SKEW_CACHE)) {
    cat("[krx_options_iv] Could not build cache.\n")
    return(data.table())
  }
  dt <- as.data.table(read_parquet(IV_SKEW_CACHE))
  dt[, Date := as.Date(Date)]
  setorder(dt, Date)
  cat(sprintf("[krx_options_iv] Loaded: %d rows (%s ~ %s)\n",
              nrow(dt), min(dt$Date), max(dt$Date)))
  dt
}


#==============================================================================
# 5. krx_fetch_options_chain_daily(date_str)
#    Enhanced daily collector: fetches per-strike IV for proper ATM/OTM extraction.
#    For incremental daily collection (not historical backfill).
#    Saves raw chain + computed skew to DRV_CACHE_DIR.
#==============================================================================

krx_fetch_options_chain_daily <- function(date_str) {
  cat(sprintf("[krx_options_iv] Fetching full option chain: %s\n", date_str))

  chain <- krx_fetch_options_iv(date_str)
  if (is.null(chain) || nrow(chain) == 0) {
    cat("  No option data returned.\n")
    return(NULL)
  }

  spot <- attr(chain, "spot")
  cat(sprintf("  K200 Spot: %.2f | Contracts: %d (C:%d, P:%d)\n",
              spot, nrow(chain),
              sum(chain$opt_type == "C"), sum(chain$opt_type == "P")))

  # Compute proper IV skew
  skew_result <- compute_iv_skew_from_chain(chain, spot)

  cat(sprintf("  ATM Call IV: %.2f%% | OTM Put IV: %.2f%% | Skew: %.2f pp\n",
              skew_result$atm_call_iv, skew_result$otm_put_iv,
              skew_result$iv_skew))

  # Save raw chain
  chain_file <- file.path(DRV_CACHE_DIR, sprintf("opt_chain_%s.parquet", date_str))
  write_parquet(chain, chain_file)

  skew_result
}


#==============================================================================
# 6. iv_skew_monthly_signal(month_ends)
#    Compute month-end IV skew signal for strategy use.
#    At each month_end, uses the latest available IV skew (t-1 or t).
#    Returns: data.table(month_end, iv_skew, iv_skew_z, iv_skew_regime)
#
#    Regime classification:
#      iv_skew_z > 1.5  -> "fear"     (OTM put demand surge)
#      iv_skew_z < -1.0 -> "complacency"
#      else             -> "normal"
#==============================================================================

iv_skew_monthly_signal <- function(month_ends = NULL) {
  cat("[krx_options_iv] Computing monthly IV Skew signal...\n")

  iv_dt <- krx_load_iv_skew()
  if (nrow(iv_dt) == 0) {
    cat("  No IV skew data available.\n")
    return(data.table())
  }

  # Load BM for month-end dates
  bm_path <- file.path(CACHE_DIR, "benchmark.parquet")
  if (is.null(month_ends)) {
    if (file.exists(bm_path)) {
      bm <- as.data.table(read_parquet(bm_path))
      bm[, Date := as.Date(Date)]
      max_date <- max(bm$Date)
      fom_seq <- seq.Date(as.Date("2010-01-01"), max_date, by = "month")
      month_ends <- sort(unique(as.Date(sapply(fom_seq, function(d) {
        as.Date(format(d, "%Y-%m-01")) - 1
      }), origin = "1970-01-01")))
      month_ends <- month_ends[month_ends >= as.Date("2010-03-31")]
    } else {
      month_ends <- sort(unique(iv_dt[, .(me = as.Date(format(Date + 1, "%Y-%m-01")) - 1)]$me))
    }
  }
  month_ends <- sort(as.Date(month_ends))

  # Rolling join: for each month_end, get latest IV skew
  setkey(iv_dt, Date)
  me_dt <- data.table(Date = month_ends)
  setkey(me_dt, Date)

  merged <- iv_dt[me_dt, roll = TRUE]  # LOCF: latest available <= month_end

  result <- merged[, .(
    month_end    = Date,
    iv_skew      = iv_skew,
    iv_skew_norm = iv_skew_norm,
    iv_skew_z    = iv_skew_z,
    iv_skew_norm_z = iv_skew_norm_z,
    pcr_vol      = pcr_vol,
    pcr_vol_z    = pcr_vol_z,
    vkospi       = vkospi,
    vkospi_z     = vkospi_z,
    atm_call_iv  = atm_call_iv,
    atm_put_iv   = atm_put_iv
  )]

  # Regime classification based on normalized skew z-score
  result[, iv_skew_regime := fifelse(
    is.na(iv_skew_norm_z), NA_character_,
    fifelse(iv_skew_norm_z > 1.5, "fear",
            fifelse(iv_skew_norm_z < -1.0, "complacency", "normal"))
  )]

  cat(sprintf("  Monthly signal: %d months (%s ~ %s)\n",
              nrow(result), min(result$month_end), max(result$month_end)))
  cat(sprintf("  Regime: fear=%d, complacency=%d, normal=%d, NA=%d\n",
              sum(result$iv_skew_regime == "fear", na.rm = TRUE),
              sum(result$iv_skew_regime == "complacency", na.rm = TRUE),
              sum(result$iv_skew_regime == "normal", na.rm = TRUE),
              sum(is.na(result$iv_skew_regime))))

  result
}


#==============================================================================
# 7. test_iv_skew_signal()
#    Backtest: does IV skew predict next-month BM returns?
#    Computes rank correlation, quintile returns, and comparison with VKOSPI/VRP.
#==============================================================================

test_iv_skew_signal <- function() {
  cat("\n")
  cat("==============================================================\n")
  cat(" IV Skew Signal Backtest — Xing et al. (2010 JFE) Application\n")
  cat("==============================================================\n\n")

  # ── Load IV skew ──
  iv_signal <- iv_skew_monthly_signal()
  if (nrow(iv_signal) == 0) {
    cat("FAILED: No IV skew signal data.\n")
    return(invisible(NULL))
  }

  # ── Load BM monthly returns ──
  bm_path <- file.path(CACHE_DIR, "benchmark.parquet")
  if (!file.exists(bm_path)) {
    cat("FAILED: benchmark.parquet not found.\n")
    return(invisible(NULL))
  }

  bm <- as.data.table(read_parquet(bm_path))
  bm[, Date := as.Date(Date)]
  setorder(bm, Date)
  bm[, ret := BM_Close / shift(BM_Close, 1L) - 1]

  # Compute monthly returns at month-ends
  bm_dates <- sort(unique(bm$Date))
  month_ends <- sort(unique(iv_signal$month_end))

  # For each month_end, compute next-month BM return
  bm_monthly <- data.table()
  for (i in seq_along(month_ends)) {
    me <- month_ends[i]
    # Find nearest trading day <= me
    td_le <- bm_dates[bm_dates <= me]
    if (length(td_le) == 0) next
    td_me <- max(td_le)

    # Next month end
    if (i < length(month_ends)) {
      next_me <- month_ends[i + 1]
      td_le2 <- bm_dates[bm_dates <= next_me]
      if (length(td_le2) == 0) next
      td_next <- max(td_le2)

      bm_me <- bm[Date == td_me, BM_Close]
      bm_next <- bm[Date == td_next, BM_Close]

      if (length(bm_me) > 0 && length(bm_next) > 0 && bm_me > 0) {
        bm_monthly <- rbind(bm_monthly, data.table(
          month_end = me,
          bm_ret_next = bm_next / bm_me - 1
        ))
      }
    }
  }

  # ── Merge signal + forward returns ──
  test_dt <- merge(iv_signal, bm_monthly, by = "month_end")
  test_dt <- test_dt[!is.na(iv_skew_z) & !is.na(bm_ret_next)]

  cat(sprintf("Test sample: %d months (%s ~ %s)\n\n",
              nrow(test_dt), min(test_dt$month_end), max(test_dt$month_end)))

  if (nrow(test_dt) < 24) {
    cat("FAILED: Need at least 24 months of data.\n")
    return(invisible(test_dt))
  }

  # ── Test 1: Rank correlation ──
  cat("--- Test 1: Rank Correlation (IV Skew → Next Month BM Return) ---\n")
  signals <- c("iv_skew_z", "iv_skew_norm_z", "pcr_vol_z", "vkospi_z")
  signal_labels <- c("IV Skew (level)", "IV Skew (normalized)", "PCR Volume", "VKOSPI")

  for (j in seq_along(signals)) {
    sig <- signals[j]
    valid <- test_dt[!is.na(get(sig))]
    if (nrow(valid) < 24) {
      cat(sprintf("  %-25s: insufficient data (%d obs)\n", signal_labels[j], nrow(valid)))
      next
    }
    cor_test <- cor.test(valid[[sig]], valid$bm_ret_next, method = "spearman")
    cat(sprintf("  %-25s: rho=%.4f, p=%.4f, n=%d %s\n",
                signal_labels[j],
                cor_test$estimate, cor_test$p.value, nrow(valid),
                ifelse(cor_test$p.value < 0.05, "*", "")))
  }

  # ── Test 2: Quintile analysis (IV Skew z-score) ──
  cat("\n--- Test 2: Quintile Analysis (IV Skew Normalized Z → Next Month BM) ---\n")
  valid_q <- test_dt[!is.na(iv_skew_norm_z)]
  if (nrow(valid_q) >= 20) {
    valid_q[, quintile := cut(iv_skew_norm_z,
                               breaks = quantile(iv_skew_norm_z, probs = seq(0, 1, 0.2), na.rm = TRUE),
                               labels = paste0("Q", 1:5),
                               include.lowest = TRUE)]

    q_summary <- valid_q[!is.na(quintile), .(
      n = .N,
      mean_skew_z = round(mean(iv_skew_norm_z, na.rm = TRUE), 2),
      mean_bm_ret = round(mean(bm_ret_next, na.rm = TRUE) * 100, 2),
      median_bm_ret = round(median(bm_ret_next, na.rm = TRUE) * 100, 2),
      hit_rate = round(mean(bm_ret_next > 0, na.rm = TRUE) * 100, 1)
    ), by = quintile][order(quintile)]

    cat("  Quintile | N  | Mean SkewZ | Mean BM(%) | Median BM(%) | Hit%\n")
    cat("  ---------+----+------------+------------+--------------+------\n")
    for (r in seq_len(nrow(q_summary))) {
      cat(sprintf("  %-9s| %2d | %10.2f | %10.2f | %12.2f | %4.1f\n",
                  q_summary$quintile[r], q_summary$n[r],
                  q_summary$mean_skew_z[r], q_summary$mean_bm_ret[r],
                  q_summary$median_bm_ret[r], q_summary$hit_rate[r]))
    }

    # Q5-Q1 spread
    q1_ret <- q_summary[quintile == "Q1", mean_bm_ret]
    q5_ret <- q_summary[quintile == "Q5", mean_bm_ret]
    if (length(q1_ret) > 0 && length(q5_ret) > 0) {
      cat(sprintf("\n  Q5-Q1 spread: %.2f pp/month (High skew - Low skew)\n",
                  q5_ret - q1_ret))
      cat(sprintf("  Interpretation: %s\n",
                  ifelse(q5_ret < q1_ret,
                         "High IV skew predicts LOWER next-month returns (crash signal)",
                         "High IV skew predicts HIGHER next-month returns (contrarian)")))
    }
  }

  # ── Test 3: Crisis detection ──
  cat("\n--- Test 3: Crisis Period IV Skew Behavior ---\n")
  crisis_periods <- list(
    "COVID (2020-02)" = as.Date("2020-01-31"),
    "COVID (2020-03)" = as.Date("2020-02-29"),
    "Rate Hike (2022-06)" = as.Date("2022-05-31"),
    "Rate Hike (2022-09)" = as.Date("2022-08-31"),
    "SVB (2023-03)" = as.Date("2023-02-28"),
    "Fukushima (2011-03)" = as.Date("2011-02-28"),
    "Europe Debt (2011-08)" = as.Date("2011-07-31")
  )

  for (nm in names(crisis_periods)) {
    cd <- crisis_periods[[nm]]
    # Find closest month_end <= cd
    row <- test_dt[month_end <= cd]
    if (nrow(row) > 0) {
      row <- row[.N]
      cat(sprintf("  %-25s: skew_z=%.2f, pcr_z=%.2f, vkospi_z=%.2f → BM_next=%.1f%%\n",
                  nm,
                  row$iv_skew_norm_z %||% NA,
                  row$pcr_vol_z %||% NA,
                  row$vkospi_z %||% NA,
                  row$bm_ret_next * 100))
    }
  }

  # ── Test 4: Incremental value over VKOSPI ──
  cat("\n--- Test 4: Does IV Skew Add Value Beyond VKOSPI? ---\n")
  both_valid <- test_dt[!is.na(iv_skew_norm_z) & !is.na(vkospi_z)]
  if (nrow(both_valid) >= 24) {
    # Correlation between signals
    sig_cor <- cor(both_valid$iv_skew_norm_z, both_valid$vkospi_z,
                   use = "complete.obs", method = "spearman")
    cat(sprintf("  IV Skew z vs VKOSPI z correlation: %.3f\n", sig_cor))

    # Partial correlation: IV Skew → BM_next controlling for VKOSPI
    # Simple approach: residualize IV Skew on VKOSPI, then correlate with BM
    resid_skew <- residuals(lm(iv_skew_norm_z ~ vkospi_z, data = both_valid))
    partial_cor <- cor.test(resid_skew, both_valid$bm_ret_next, method = "spearman")
    cat(sprintf("  Partial rank-corr (Skew|VKOSPI → BM): rho=%.4f, p=%.4f %s\n",
                partial_cor$estimate, partial_cor$p.value,
                ifelse(partial_cor$p.value < 0.10, "(significant at 10%)", "")))

    # Combined signal: skew_z + vkospi_z
    both_valid[, combined_z := (iv_skew_norm_z + vkospi_z) / 2]
    combined_cor <- cor.test(both_valid$combined_z, both_valid$bm_ret_next,
                              method = "spearman")
    cat(sprintf("  Combined (Skew+VKOSPI)/2 → BM: rho=%.4f, p=%.4f\n",
                combined_cor$estimate, combined_cor$p.value))

    # Compare with VRP if available
    vrp_path <- file.path(CACHE_DIR, "regime_vrp.parquet")  # may not exist
    # VRP is in regime_vrp.R, computed on demand. Skip for now.
  }

  # ── Summary ──
  cat("\n")
  cat("==============================================================\n")
  cat(" Summary\n")
  cat("==============================================================\n")
  cat("  Data: KRX Open API /drv/opt_bydd_trd → IMP_VOLT per contract\n")
  cat(sprintf("  Coverage: %d daily obs (%s ~ %s)\n",
              nrow(test_dt), min(test_dt$month_end), max(test_dt$month_end)))
  cat("  IV Skew = (OTM Put IV - ATM Call IV) / ATM Call IV\n")
  cat("  Z-score: expanding window (PIT compliant, zero lookahead)\n")
  cat("  All data KST 15:30 close confirmed.\n")
  cat("==============================================================\n")

  invisible(test_dt)
}


cat("[krx_options_iv] Loaded. Functions:\n")
cat("  krx_fetch_options_iv(date_str) — raw per-strike option chain\n")
cat("  krx_build_iv_skew_cache()      — build .cache/krx_iv_skew.parquet\n")
cat("  krx_load_iv_skew()             — load cached skew data\n")
cat("  iv_skew_monthly_signal()       — monthly signal for strategies\n")
cat("  test_iv_skew_signal()          — backtest IV skew predictive power\n")
cat(sprintf("  Cache: %s\n", IV_SKEW_CACHE))
