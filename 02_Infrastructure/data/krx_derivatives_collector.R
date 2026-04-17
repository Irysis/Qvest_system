#==============================================================================
# KRX Derivatives Data Collector
# VKOSPI, KOSPI200 Futures Basis, Options Put-Call Ratio, Open Interest
#
# Depends: krx_data_collector.R (for krx_api())
# Usage:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/krx_data_collector.R")
#   source("02_Infrastructure/krx_derivatives_collector.R")
#   krx_collect_derivatives("20260303")
#   drv <- krx_load_derivatives()
#==============================================================================
cat("[krx_derivatives] Loading...\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

DRV_CACHE_DIR <- file.path(CACHE_DIR, "krx_derivatives")
if (!dir.exists(DRV_CACHE_DIR)) dir.create(DRV_CACHE_DIR, recursive = TRUE)

# ── Helper: parse KRX numeric (remove commas, convert) ──
.krx_num <- function(x) {
  suppressWarnings(as.numeric(gsub(",", "", x)))
}

#──────────────────────────────────────────────────────────────────────────────
# 1. VKOSPI: Extract from 변동성지수 선물 SPOT_PRC
#──────────────────────────────────────────────────────────────────────────────
krx_vkospi <- function(date_str) {
  dt <- krx_api("/drv/fut_bydd_trd", list(basDd = date_str))
  if (is.null(dt) || nrow(dt) == 0) return(NULL)

  # 변동성지수 선물 → SPOT_PRC = VKOSPI
  vf <- dt[grepl("변동성지수", PROD_NM) & MKT_NM == "정규"]
  if (nrow(vf) == 0) return(NULL)

  # Front-month (shortest expiry) for SPOT_PRC
  front <- vf[1]
  data.table(
    Date       = date_str,
    VKOSPI     = .krx_num(front$SPOT_PRC),
    VF_Close   = .krx_num(front$TDD_CLSPRC),
    VF_OI      = .krx_num(front$ACC_OPNINT_QTY),
    VF_Volume  = .krx_num(front$ACC_TRDVOL)
  )
}

#──────────────────────────────────────────────────────────────────────────────
# 2. KOSPI200 Futures: Basis, Open Interest, Volume
#──────────────────────────────────────────────────────────────────────────────
krx_k200_futures <- function(date_str) {
  dt <- krx_api("/drv/fut_bydd_trd", list(basDd = date_str))
  if (is.null(dt) || nrow(dt) == 0) return(NULL)

  # 코스피200 선물 (정규시장)
  k200 <- dt[grepl("코스피200 선물", PROD_NM) & MKT_NM == "정규"]
  if (nrow(k200) == 0) return(NULL)

  # Front-month contract
  front <- k200[1]
  fut_close <- .krx_num(front$TDD_CLSPRC)
  spot      <- .krx_num(front$SPOT_PRC)
  basis     <- fut_close - spot
  basis_pct <- if (!is.na(fut_close) && !is.na(spot) && spot > 0) (basis / spot) * 100 else NA_real_

  # Aggregate OI/Volume across all maturities
  total_oi  <- sum(.krx_num(k200$ACC_OPNINT_QTY), na.rm = TRUE)
  total_vol <- sum(.krx_num(k200$ACC_TRDVOL), na.rm = TRUE)

  data.table(
    Date       = date_str,
    K200_Fut   = fut_close,
    K200_Spot  = spot,
    K200_Basis = basis,
    K200_Basis_Pct = basis_pct,
    K200_Fut_OI    = total_oi,
    K200_Fut_Vol   = total_vol
  )
}

#──────────────────────────────────────────────────────────────────────────────
# 3. KOSPI200 Options: Put-Call Ratio (OI & Volume), IV ATM
#──────────────────────────────────────────────────────────────────────────────
krx_k200_options <- function(date_str) {
  dt <- krx_api("/drv/opt_bydd_trd", list(basDd = date_str))
  if (is.null(dt) || nrow(dt) == 0) return(NULL)

  # KOSPI200 options only (정규)
  k200 <- dt[grepl("코스피200 옵션", PROD_NM) & grepl("정규", ISU_NM)]
  if (nrow(k200) == 0) {
    # Try 미니코스피200
    k200 <- dt[grepl("미니코스피200 옵션", PROD_NM) & grepl("정규", ISU_NM)]
  }
  if (nrow(k200) == 0) return(NULL)

  k200[, oi := .krx_num(ACC_OPNINT_QTY)]
  k200[, vol := .krx_num(ACC_TRDVOL)]
  k200[, iv := .krx_num(IMP_VOLT)]
  k200[, price := .krx_num(TDD_CLSPRC)]

  # Put-Call Ratio (Open Interest based)
  call_oi <- sum(k200[RGHT_TP_NM == "CALL"]$oi, na.rm = TRUE)
  put_oi  <- sum(k200[RGHT_TP_NM == "PUT"]$oi, na.rm = TRUE)
  pcr_oi  <- if (call_oi > 0) put_oi / call_oi else NA_real_

  # Put-Call Ratio (Volume based)
  call_vol <- sum(k200[RGHT_TP_NM == "CALL"]$vol, na.rm = TRUE)
  put_vol  <- sum(k200[RGHT_TP_NM == "PUT"]$vol, na.rm = TRUE)
  pcr_vol  <- if (call_vol > 0) put_vol / call_vol else NA_real_

  # IV: ATM approximation (highest OI near-money contracts)
  # Mean IV for top-10 OI calls and puts
  top_call_iv <- k200[RGHT_TP_NM == "CALL" & iv > 0][order(-oi)][1:min(10, .N), mean(iv, na.rm = TRUE)]
  top_put_iv  <- k200[RGHT_TP_NM == "PUT" & iv > 0][order(-oi)][1:min(10, .N), mean(iv, na.rm = TRUE)]
  iv_skew     <- if (!is.na(top_put_iv) && !is.na(top_call_iv) && top_call_iv > 0)
                   (top_put_iv - top_call_iv) / top_call_iv else NA_real_

  data.table(
    Date        = date_str,
    PCR_OI      = round(pcr_oi, 4),
    PCR_Vol     = round(pcr_vol, 4),
    Call_OI     = call_oi,
    Put_OI      = put_oi,
    Call_Vol    = call_vol,
    Put_Vol     = put_vol,
    IV_Call_ATM = round(top_call_iv, 2),
    IV_Put_ATM  = round(top_put_iv, 2),
    IV_Skew     = round(iv_skew, 4)
  )
}

#──────────────────────────────────────────────────────────────────────────────
# 4. Daily derivatives collection (all 3 in one call)
#──────────────────────────────────────────────────────────────────────────────
krx_collect_derivatives <- function(date_str) {
  cat(sprintf("[krx_derivatives] Collecting %s...\n", date_str))

  # VKOSPI (from futures endpoint — already fetches all futures)
  vk <- krx_vkospi(date_str)

  # K200 Futures — separate call (same endpoint, but we need specific parsing)
  # Actually krx_vkospi already called /drv/fut_bydd_trd
  # Let's call once and parse both
  fut_raw <- krx_api("/drv/fut_bydd_trd", list(basDd = date_str))
  k200_fut <- NULL
  vkospi_row <- NULL

  if (!is.null(fut_raw) && nrow(fut_raw) > 0) {
    # VKOSPI from 변동성지수 선물
    vf <- fut_raw[grepl("변동성지수", PROD_NM) & MKT_NM == "정규"]
    if (nrow(vf) > 0) {
      front <- vf[1]
      vkospi_row <- data.table(
        Date      = date_str,
        VKOSPI    = .krx_num(front$SPOT_PRC),
        VF_Close  = .krx_num(front$TDD_CLSPRC),
        VF_OI     = .krx_num(front$ACC_OPNINT_QTY),
        VF_Volume = .krx_num(front$ACC_TRDVOL)
      )
    }

    # K200 Futures
    k200_f <- fut_raw[grepl("코스피200 선물", PROD_NM) & MKT_NM == "정규"]
    if (nrow(k200_f) > 0) {
      front <- k200_f[1]
      fut_close <- .krx_num(front$TDD_CLSPRC)
      spot      <- .krx_num(front$SPOT_PRC)
      basis     <- fut_close - spot
      basis_pct <- if (!is.na(fut_close) && !is.na(spot) && spot > 0) (basis / spot) * 100 else NA_real_
      total_oi  <- sum(.krx_num(k200_f$ACC_OPNINT_QTY), na.rm = TRUE)
      total_vol <- sum(.krx_num(k200_f$ACC_TRDVOL), na.rm = TRUE)
      k200_fut <- data.table(
        Date           = date_str,
        K200_Fut       = fut_close,
        K200_Spot      = spot,
        K200_Basis     = basis,
        K200_Basis_Pct = basis_pct,
        K200_Fut_OI    = total_oi,
        K200_Fut_Vol   = total_vol
      )
    }
  }

  # K200 Options (separate API call)
  opt_row <- krx_k200_options(date_str)

  # Merge all into single row
  result <- data.table(Date = date_str)
  if (!is.null(vkospi_row)) result <- merge(result, vkospi_row, by = "Date")
  if (!is.null(k200_fut))   result <- merge(result, k200_fut, by = "Date")
  if (!is.null(opt_row))    result <- merge(result, opt_row, by = "Date")

  # Save
  out_file <- file.path(DRV_CACHE_DIR, sprintf("drv_%s.parquet", date_str))
  write_parquet(result, out_file)
  cat(sprintf("[krx_derivatives] Saved: %d cols for %s\n", ncol(result), date_str))
  invisible(result)
}

#──────────────────────────────────────────────────────────────────────────────
# 5. Range collection
#──────────────────────────────────────────────────────────────────────────────
krx_collect_derivatives_range <- function(start_str, end_str) {
  dates <- seq(as.Date(start_str, "%Y%m%d"), as.Date(end_str, "%Y%m%d"), by = "day")
  dates <- dates[!weekdays(dates) %in% c("Saturday", "Sunday")]
  date_strs <- format(dates, "%Y%m%d")

  cat(sprintf("[krx_derivatives] Range: %s ~ %s (%d biz days)\n",
              start_str, end_str, length(date_strs)))

  for (i in seq_along(date_strs)) {
    ds <- date_strs[i]
    out_file <- file.path(DRV_CACHE_DIR, sprintf("drv_%s.parquet", ds))
    if (file.exists(out_file)) {
      if (i %% 20 == 0) cat(sprintf("  [%d/%d] %s — skip (cached)\n", i, length(date_strs), ds))
      next
    }
    if (.krx_is_holiday(ds)) next

    tryCatch(krx_collect_derivatives(ds), error = function(e) {
      cat(sprintf("  [ERROR] %s: %s\n", ds, e$message))
    })
  }
  cat("[krx_derivatives] Range collection complete.\n")
}

#──────────────────────────────────────────────────────────────────────────────
# 6. Load all cached derivatives data
#──────────────────────────────────────────────────────────────────────────────
krx_load_derivatives <- function() {
  files <- list.files(DRV_CACHE_DIR, pattern = "^drv_.*\\.parquet$", full.names = TRUE)
  if (length(files) == 0) {
    cat("[krx_derivatives] No cached data found\n")
    return(data.table())
  }
  dt <- rbindlist(lapply(files, function(f) as.data.table(read_parquet(f))), fill = TRUE)
  dt[, Date := as.Date(Date, format = "%Y%m%d")]
  setorder(dt, Date)
  cat(sprintf("[krx_derivatives] Loaded: %d rows (%s ~ %s)\n",
              nrow(dt), min(dt$Date), max(dt$Date)))
  dt
}

cat(sprintf("[krx_derivatives] Loaded. Cache: %s\n", DRV_CACHE_DIR))
cat("[krx_derivatives] Functions: krx_collect_derivatives(), krx_load_derivatives()\n")
