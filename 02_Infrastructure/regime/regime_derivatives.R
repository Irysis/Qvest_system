#==============================================================================
# Quant Module — KRX Derivatives-Based Regime Engine
# Version: 1.0.0
#
# Uses KRX derivative market data (VKOSPI, futures basis, options PCR, skew)
# to build regime signals complementary to the FRED macro regime engine.
#
# Models:
#   1. VKOSPI Regime       — implied vol = direct fear measurement
#   2. Put/Call Ratio       — Easley et al. (1998), informed trading proxy
#   3. Futures Basis        — Gorton & Rouwenhorst (2006), cost-of-carry stress
#   4. Options Skew         — OTM put IV / ATM call IV = tail risk demand
#   5. Derivatives Ensemble — soft voting across models 1-4
#   6. Full pipeline        — load + compute + cache
#   7. FRED integration     — merge derivatives + macro regime
#
# Depends: config.R (for CACHE_DIR), krx_derivatives_collector.R (for data)
# Usage:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/regime_derivatives.R")
#   regime <- drv_compute_regime(start_date = "2020-01-01")
#==============================================================================

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
}

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

cat("[regime_derivatives] Loading...\n")

# ─── Cache Path ─────────────────────────────────────────────────────────────
DRV_REGIME_CACHE <- file.path(CACHE_DIR, "regime_derivatives.parquet")


#==============================================================================
# 1. VKOSPI Regime
#    VKOSPI > 30 -> crisis, > 20 -> elevated, <= 20 -> normal
#    Academic: Black-Scholes implied vol = market fear direct measurement
#    Uses 3-day MA for smoothing
#==============================================================================

drv_vkospi_regime <- function(drv_data) {
  cat("[regime_derivatives] Computing VKOSPI regime...\n")

  if (!"VKOSPI" %in% names(drv_data)) {
    cat("  WARN: VKOSPI column not found. Returning NA.\n")
    return(data.table(
      Date = drv_data$Date,
      VKOSPI_raw   = NA_real_,
      VKOSPI_MA3   = NA_real_,
      VKOSPI_regime = NA_character_,
      VKOSPI_vote   = NA_integer_
    ))
  }

  dt <- copy(drv_data[, .(Date, VKOSPI)])
  setorder(dt, Date)

  # 3-day MA for smoothing

  dt[, VKOSPI_MA3 := frollmean(VKOSPI, n = 3, align = "right", fill = NA_real_)]

  # Use smoothed value; fall back to raw if MA not available
  dt[, vk := fifelse(!is.na(VKOSPI_MA3), VKOSPI_MA3, VKOSPI)]

  # Regime classification (calibrated to KRX distribution: median=16.7, q95=31.3)
  dt[, VKOSPI_regime := fifelse(
    is.na(vk), NA_character_,
    fifelse(vk > 25, "crisis",
            fifelse(vk > 18, "elevated", "normal"))
  )]

  # Vote: -1 (crisis), 0 (normal), +1 is not used for VKOSPI
  # We use: crisis = -1, elevated = -0.5 (partial risk-off), normal = 0
  dt[, VKOSPI_vote := fifelse(
    is.na(VKOSPI_regime), NA_integer_,
    fifelse(VKOSPI_regime == "crisis", -1L,
            fifelse(VKOSPI_regime == "elevated", 0L, 0L))
  )]

  # Rename raw column for clarity
  setnames(dt, "VKOSPI", "VKOSPI_raw")
  dt[, vk := NULL]

  cat(sprintf("  VKOSPI regime: %d rows | crisis: %d, elevated: %d, normal: %d\n",
              nrow(dt),
              sum(dt$VKOSPI_regime == "crisis", na.rm = TRUE),
              sum(dt$VKOSPI_regime == "elevated", na.rm = TRUE),
              sum(dt$VKOSPI_regime == "normal", na.rm = TRUE)))
  dt
}


#==============================================================================
# 2. Put/Call Volume Ratio Regime
#    PCR = put_volume / call_volume
#    PCR > 1.3 -> extreme fear (contrarian buy signal)
#    PCR < 0.5 -> complacency (risk warning)
#    Academic: Easley et al. (1998) -- put demand surge = informed trading
#    Rolling 5-day MA, z-score vs 60-day lookback
#==============================================================================

drv_pcr_regime <- function(drv_data) {
  cat("[regime_derivatives] Computing Put/Call Ratio regime...\n")

  # Prefer volume-based PCR; fall back to OI-based
  pcr_col <- if ("PCR_Vol" %in% names(drv_data)) "PCR_Vol"
             else if ("PCR_OI" %in% names(drv_data)) "PCR_OI"
             else NULL

  if (is.null(pcr_col)) {
    cat("  WARN: No PCR column found. Returning NA.\n")
    return(data.table(
      Date = drv_data$Date,
      PCR_raw    = NA_real_,
      PCR_MA5    = NA_real_,
      PCR_zscore = NA_real_,
      PCR_regime = NA_character_,
      PCR_vote   = NA_integer_
    ))
  }

  dt <- copy(drv_data[, c("Date", pcr_col), with = FALSE])
  setnames(dt, pcr_col, "PCR_raw")
  setorder(dt, Date)

  # 5-day MA for smoothing
  dt[, PCR_MA5 := frollmean(PCR_raw, n = 5, align = "right", fill = NA_real_)]

  # Z-score vs 60-day lookback (expanding window if < 60 obs)
  dt[, PCR_mean60 := frollmean(PCR_raw, n = 60, align = "right", fill = NA_real_)]
  dt[, PCR_sd60   := frollapply(PCR_raw, n = 60, FUN = sd, align = "right",
                                 fill = NA_real_)]
  dt[, PCR_zscore := fifelse(
    !is.na(PCR_sd60) & PCR_sd60 > 1e-8,
    (PCR_MA5 - PCR_mean60) / PCR_sd60,
    NA_real_
  )]

  # Use smoothed PCR for regime classification
  dt[, pcr := fifelse(!is.na(PCR_MA5), PCR_MA5, PCR_raw)]

  # Regime classification (calibrated: median=0.96, q95=1.29, q05=0.70)
  dt[, PCR_regime := fifelse(
    is.na(pcr), NA_character_,
    fifelse(pcr > 1.2, "extreme_fear",
            fifelse(pcr < 0.75, "complacency", "normal"))
  )]

  # Vote: extreme fear is contrarian bullish (+1), complacency is risk (-1)
  dt[, PCR_vote := fifelse(
    is.na(PCR_regime), NA_integer_,
    fifelse(PCR_regime == "extreme_fear", 1L,
            fifelse(PCR_regime == "complacency", -1L, 0L))
  )]

  dt[, c("PCR_mean60", "PCR_sd60", "pcr") := NULL]

  cat(sprintf("  PCR regime: %d rows | fear: %d, complacency: %d, normal: %d\n",
              nrow(dt),
              sum(dt$PCR_regime == "extreme_fear", na.rm = TRUE),
              sum(dt$PCR_regime == "complacency", na.rm = TRUE),
              sum(dt$PCR_regime == "normal", na.rm = TRUE)))
  dt
}


#==============================================================================
# 3. Futures Basis Regime
#    Basis = (futures_price - spot_price) / spot_price * 100
#    Basis < -0.5% -> backwardation = stress
#    Basis > 1.0%  -> strong contango = normal
#    Academic: Gorton & Rouwenhorst (2006)
#==============================================================================

drv_basis_regime <- function(drv_data) {
  cat("[regime_derivatives] Computing Futures Basis regime...\n")

  if (!"K200_Basis_Pct" %in% names(drv_data)) {
    cat("  WARN: K200_Basis_Pct column not found. Returning NA.\n")
    return(data.table(
      Date = drv_data$Date,
      Basis_Pct_raw = NA_real_,
      Basis_MA5     = NA_real_,
      Basis_regime  = NA_character_,
      Basis_vote    = NA_integer_
    ))
  }

  dt <- copy(drv_data[, .(Date, K200_Basis_Pct)])
  setnames(dt, "K200_Basis_Pct", "Basis_Pct_raw")
  setorder(dt, Date)

  # 5-day MA smoothing
  dt[, Basis_MA5 := frollmean(Basis_Pct_raw, n = 5, align = "right",
                               fill = NA_real_)]

  # Use smoothed value
  dt[, basis := fifelse(!is.na(Basis_MA5), Basis_MA5, Basis_Pct_raw)]

  # Regime classification (calibrated: median=0.065, q05=-0.41, q95=0.59)
  dt[, Basis_regime := fifelse(
    is.na(basis), NA_character_,
    fifelse(basis < -0.3, "backwardation",
            fifelse(basis > 0.4, "contango", "normal"))
  )]

  # Vote: backwardation = stress (-1), contango = normal/bullish (0)
  dt[, Basis_vote := fifelse(
    is.na(Basis_regime), NA_integer_,
    fifelse(Basis_regime == "backwardation", -1L, 0L)
  )]

  dt[, basis := NULL]

  cat(sprintf("  Basis regime: %d rows | backwardation: %d, contango: %d, normal: %d\n",
              nrow(dt),
              sum(dt$Basis_regime == "backwardation", na.rm = TRUE),
              sum(dt$Basis_regime == "contango", na.rm = TRUE),
              sum(dt$Basis_regime == "normal", na.rm = TRUE)))
  dt
}


#==============================================================================
# 4. Options Skew Regime
#    Skew = (OTM put IV - ATM call IV) / ATM call IV
#    High skew (> 0.3) -> tail risk fear
#    Negative skew (< -0.1) -> complacency / euphoria
#    Uses IV_Skew from krx_derivatives_collector
#==============================================================================

drv_skew_regime <- function(drv_data) {
  cat("[regime_derivatives] Computing Options Skew regime...\n")

  if (!"IV_Skew" %in% names(drv_data)) {
    cat("  WARN: IV_Skew column not found. Returning NA.\n")
    return(data.table(
      Date = drv_data$Date,
      Skew_raw    = NA_real_,
      Skew_MA5    = NA_real_,
      Skew_regime = NA_character_,
      Skew_vote   = NA_integer_
    ))
  }

  dt <- copy(drv_data[, .(Date, IV_Skew)])
  setnames(dt, "IV_Skew", "Skew_raw")
  setorder(dt, Date)

  # 5-day MA smoothing
  dt[, Skew_MA5 := frollmean(Skew_raw, n = 5, align = "right", fill = NA_real_)]

  # Use smoothed value
  dt[, skew := fifelse(!is.na(Skew_MA5), Skew_MA5, Skew_raw)]

  # Regime classification (calibrated: median=0.60, q75=0.90, q05=0.13)
  dt[, Skew_regime := fifelse(
    is.na(skew), NA_character_,
    fifelse(skew > 0.9, "tail_fear",
            fifelse(skew < 0.2, "euphoria", "normal"))
  )]

  # Vote: tail fear = risk-off (-1), euphoria = complacency warning (-1 too)
  # Extreme skew in either direction is unusual
  dt[, Skew_vote := fifelse(
    is.na(Skew_regime), NA_integer_,
    fifelse(Skew_regime == "tail_fear", -1L,
            fifelse(Skew_regime == "euphoria", -1L, 0L))
  )]

  dt[, skew := NULL]

  cat(sprintf("  Skew regime: %d rows | tail_fear: %d, euphoria: %d, normal: %d\n",
              nrow(dt),
              sum(dt$Skew_regime == "tail_fear", na.rm = TRUE),
              sum(dt$Skew_regime == "euphoria", na.rm = TRUE),
              sum(dt$Skew_regime == "normal", na.rm = TRUE)))
  dt
}


#==============================================================================
# 5. Derivatives Ensemble
#    Soft voting across models 1-4
#    Each model votes: -1 (crisis/stress), 0 (normal), +1 (contrarian buy)
#    Ensemble score = mean(available votes)
#    Score < -0.5 -> risk_off
#    Score > 0.3  -> euphoria_warning
#    Otherwise    -> normal
#==============================================================================

drv_ensemble_regime <- function(drv_data) {
  cat("[regime_derivatives] Computing Derivatives Ensemble...\n")

  # Compute individual regimes
  vkospi_dt <- drv_vkospi_regime(drv_data)
  pcr_dt    <- drv_pcr_regime(drv_data)
  basis_dt  <- drv_basis_regime(drv_data)
  skew_dt   <- drv_skew_regime(drv_data)

  # Merge all on Date
  ensemble <- merge(
    vkospi_dt[, .(Date, VKOSPI_raw, VKOSPI_MA3, VKOSPI_regime, VKOSPI_vote)],
    pcr_dt[, .(Date, PCR_raw, PCR_MA5, PCR_zscore, PCR_regime, PCR_vote)],
    by = "Date", all = TRUE
  )
  ensemble <- merge(ensemble,
    basis_dt[, .(Date, Basis_Pct_raw, Basis_MA5, Basis_regime, Basis_vote)],
    by = "Date", all = TRUE
  )
  ensemble <- merge(ensemble,
    skew_dt[, .(Date, Skew_raw, Skew_MA5, Skew_regime, Skew_vote)],
    by = "Date", all = TRUE
  )

  setorder(ensemble, Date)

  # Ensemble score = mean of available (non-NA) votes
  vote_cols <- c("VKOSPI_vote", "PCR_vote", "Basis_vote", "Skew_vote")
  ensemble[, Drv_Ensemble_Score := {
    votes <- .SD
    row_scores <- numeric(.N)
    for (i in seq_len(.N)) {
      v <- as.numeric(votes[i])
      valid <- v[!is.na(v)]
      row_scores[i] <- if (length(valid) > 0) mean(valid) else NA_real_
    }
    row_scores
  }, .SDcols = vote_cols]

  # Count how many models contributed
  ensemble[, Drv_N_Votes := rowSums(!is.na(.SD)), .SDcols = vote_cols]

  # Ensemble regime
  ensemble[, Drv_Ensemble_Regime := fifelse(
    is.na(Drv_Ensemble_Score), NA_character_,
    fifelse(Drv_Ensemble_Score < -0.5, "risk_off",
            fifelse(Drv_Ensemble_Score > 0.3, "euphoria_warning", "normal"))
  )]

  cat(sprintf("  Ensemble: %d rows | risk_off: %d, euphoria: %d, normal: %d | avg votes: %.1f\n",
              nrow(ensemble),
              sum(ensemble$Drv_Ensemble_Regime == "risk_off", na.rm = TRUE),
              sum(ensemble$Drv_Ensemble_Regime == "euphoria_warning", na.rm = TRUE),
              sum(ensemble$Drv_Ensemble_Regime == "normal", na.rm = TRUE),
              mean(ensemble$Drv_N_Votes, na.rm = TRUE)))
  ensemble
}


#==============================================================================
# 6. Full Computation Pipeline
#    Loads derivative data -> computes all 5 models -> saves to cache
#    Output: data.table with Date + all regime signals
#    Cache: .cache/regime_derivatives.parquet
#==============================================================================

drv_compute_regime <- function(start_date = "2020-01-01", end_date = NULL) {
  cat("[regime_derivatives] === Starting Derivatives Regime Pipeline ===\n")

  # Check if krx_load_derivatives is available
  if (!exists("krx_load_derivatives", mode = "function")) {
    # Try to source the collector
    collector_path <- file.path(DATA_DIR, "krx_derivatives_collector.R")
    if (file.exists(collector_path)) {
      # Also need krx_data_collector.R for krx_api()
      base_collector <- file.path(DATA_DIR, "krx_data_collector.R")
      if (file.exists(base_collector) && !exists("krx_api", mode = "function")) {
        source(base_collector)
      }
      source(collector_path)
    } else {
      stop("[regime_derivatives] krx_derivatives_collector.R not found at: ",
           collector_path)
    }
  }

  # Check cache directory for derivative data
  drv_cache_dir <- file.path(CACHE_DIR, "krx_derivatives")
  drv_files <- if (dir.exists(drv_cache_dir)) {
    list.files(drv_cache_dir, pattern = "^drv_.*\\.parquet$")
  } else {
    character(0)
  }

  if (length(drv_files) == 0) {
    cat("\n")
    cat("  *** NO DERIVATIVE DATA FOUND ***\n")
    cat("  You need to collect derivative data first by running:\n")
    cat("    source('02_Infrastructure/config.R')\n")
    cat("    source('02_Infrastructure/krx_data_collector.R')\n")
    cat("    source('02_Infrastructure/krx_derivatives_collector.R')\n")
    cat("    krx_collect_derivatives_range('20200101', format(Sys.Date(), '%Y%m%d'))\n")
    cat("\n")
    cat("  Returning empty data.table.\n")
    return(data.table())
  }

  # Load derivative data
  drv_data <- krx_load_derivatives()

  if (nrow(drv_data) == 0) {
    cat("  WARN: Loaded derivative data is empty.\n")
    return(data.table())
  }

  # Filter by date range
  if (!is.null(start_date)) {
    drv_data <- drv_data[Date >= as.Date(start_date)]
  }
  if (!is.null(end_date)) {
    drv_data <- drv_data[Date <= as.Date(end_date)]
  }

  if (nrow(drv_data) == 0) {
    cat(sprintf("  WARN: No data in range %s ~ %s.\n",
                start_date, end_date %||% "today"))
    return(data.table())
  }

  cat(sprintf("  Data range: %s ~ %s (%d trading days)\n",
              min(drv_data$Date), max(drv_data$Date), nrow(drv_data)))

  # Compute ensemble (calls all 4 individual models internally)
  regime_dt <- drv_ensemble_regime(drv_data)

  # Save cache
  if (!dir.exists(dirname(DRV_REGIME_CACHE))) {
    dir.create(dirname(DRV_REGIME_CACHE), recursive = TRUE)
  }
  write_parquet(regime_dt, DRV_REGIME_CACHE)

  cat(sprintf("\n[regime_derivatives] Pipeline complete. Saved: %s\n", DRV_REGIME_CACHE))
  cat(sprintf("  Total: %d rows | %s ~ %s\n",
              nrow(regime_dt), min(regime_dt$Date), max(regime_dt$Date)))

  # Print latest status
  latest <- tail(regime_dt[!is.na(Drv_Ensemble_Score)], 1)
  if (nrow(latest) > 0) {
    cat(sprintf("\n  Latest (%s):\n", latest$Date))
    cat(sprintf("    VKOSPI:   %s (%.1f)\n",
                latest$VKOSPI_regime %||% "NA", latest$VKOSPI_raw %||% NA))
    cat(sprintf("    PCR:      %s (%.3f)\n",
                latest$PCR_regime %||% "NA", latest$PCR_raw %||% NA))
    cat(sprintf("    Basis:    %s (%.3f%%)\n",
                latest$Basis_regime %||% "NA", latest$Basis_Pct_raw %||% NA))
    cat(sprintf("    Skew:     %s (%.4f)\n",
                latest$Skew_regime %||% "NA", latest$Skew_raw %||% NA))
    cat(sprintf("    Ensemble: %s (score: %.3f, %d votes)\n",
                latest$Drv_Ensemble_Regime,
                latest$Drv_Ensemble_Score,
                latest$Drv_N_Votes))
  }

  invisible(regime_dt)
}


#==============================================================================
# 7. Integration with FRED Regime
#    Merge derivatives regime with FRED macro regime
#    Combined score: 60% FRED + 40% Derivatives
#    Returns: enhanced regime signal
#==============================================================================

drv_merge_with_fred <- function(drv_regime = NULL, fred_regime = NULL) {
  cat("[regime_derivatives] Merging derivatives + FRED regime signals...\n")

  # Load from cache if not provided
  if (is.null(drv_regime)) {
    if (file.exists(DRV_REGIME_CACHE)) {
      drv_regime <- as.data.table(read_parquet(DRV_REGIME_CACHE))
      cat(sprintf("  Loaded derivatives regime: %d rows\n", nrow(drv_regime)))
    } else {
      cat("  WARN: No derivatives regime cache. Run drv_compute_regime() first.\n")
      drv_regime <- data.table()
    }
  }

  if (is.null(fred_regime)) {
    fred_cache <- file.path(CACHE_DIR, "macro_regime.parquet")
    if (file.exists(fred_cache)) {
      fred_regime <- as.data.table(read_parquet(fred_cache))
      cat(sprintf("  Loaded FRED regime: %d rows\n", nrow(fred_regime)))
    } else {
      cat("  WARN: No FRED regime cache. Run fred_compute_regime() first.\n")
      fred_regime <- data.table()
    }
  }

  # If one is empty, return the other with score mapping
  if (nrow(drv_regime) == 0 && nrow(fred_regime) == 0) {
    cat("  WARN: Both regime sources empty.\n")
    return(data.table())
  }

  if (nrow(drv_regime) == 0) {
    cat("  Using FRED-only regime (no derivatives data).\n")
    result <- copy(fred_regime)
    result[, Combined_Risk_Score := Macro_Risk_Score]
    result[, Regime_Source := "FRED_only"]
    return(result)
  }

  if (nrow(fred_regime) == 0) {
    cat("  Using derivatives-only regime (no FRED data).\n")
    # Normalize derivatives score to 0-100 scale
    result <- copy(drv_regime)
    # Drv_Ensemble_Score range: [-1, +1], map to [0, 100]
    result[, Combined_Risk_Score := fifelse(
      is.na(Drv_Ensemble_Score), NA_real_,
      pmin(100, pmax(0, (-Drv_Ensemble_Score + 1) * 50))
    )]
    result[, Regime_Source := "DRV_only"]
    return(result)
  }

  # --- Both available: merge ---

  # Prepare FRED: extract key columns + monthly resolution
  fred_cols <- intersect(names(fred_regime),
    c("Date", "Macro_Risk_Score", "VIX_Regime", "YC_Inversion",
      "Credit_Stress", "KRW_Stress", "Buddha_Mode"))
  fred_sub <- fred_regime[, ..fred_cols]
  setnames(fred_sub, "Macro_Risk_Score", "FRED_Risk_Score")
  setkey(fred_sub, Date)

  # Prepare DRV: daily resolution, keep ensemble + key signals
  drv_cols <- c("Date", "Drv_Ensemble_Score", "Drv_Ensemble_Regime",
                "Drv_N_Votes", "VKOSPI_raw", "VKOSPI_regime",
                "PCR_raw", "PCR_regime", "Basis_Pct_raw", "Basis_regime",
                "Skew_raw", "Skew_regime")
  drv_cols <- intersect(drv_cols, names(drv_regime))
  drv_sub <- drv_regime[, ..drv_cols]
  setkey(drv_sub, Date)

  # Rolling join: for each DRV date, get latest FRED regime (FRED is monthly)
  merged <- fred_sub[drv_sub, roll = TRUE]

  # Normalize DRV score to 0-100 scale (same direction as FRED: higher = riskier)
  # Drv_Ensemble_Score: -1 (very risky) to +1 (contrarian bullish/safe)
  # Map: -1 -> 100 (crisis), 0 -> 50 (neutral), +1 -> 0 (safe)
  merged[, DRV_Risk_Score := fifelse(
    is.na(Drv_Ensemble_Score), NA_real_,
    pmin(100, pmax(0, (-Drv_Ensemble_Score + 1) * 50))
  )]

  # Combined score: 60% FRED + 40% Derivatives
  merged[, Combined_Risk_Score := fifelse(
    is.na(DRV_Risk_Score) & is.na(FRED_Risk_Score), NA_real_,
    fifelse(is.na(DRV_Risk_Score), FRED_Risk_Score,
            fifelse(is.na(FRED_Risk_Score), DRV_Risk_Score,
                    0.6 * FRED_Risk_Score + 0.4 * DRV_Risk_Score))
  )]

  # Source indicator
  merged[, Regime_Source := fifelse(
    !is.na(DRV_Risk_Score) & !is.na(FRED_Risk_Score), "FRED+DRV",
    fifelse(!is.na(DRV_Risk_Score), "DRV_only", "FRED_only")
  )]

  # Enhanced Buddha Mode: Combined_Risk_Score >= 70
  merged[, Enhanced_Buddha := fifelse(
    !is.na(Combined_Risk_Score) & Combined_Risk_Score >= 70, TRUE, FALSE
  )]

  setorder(merged, Date)

  cat(sprintf("  Merged: %d rows | %s ~ %s\n",
              nrow(merged), min(merged$Date), max(merged$Date)))
  cat(sprintf("  Source: FRED+DRV %d, FRED_only %d, DRV_only %d\n",
              sum(merged$Regime_Source == "FRED+DRV", na.rm = TRUE),
              sum(merged$Regime_Source == "FRED_only", na.rm = TRUE),
              sum(merged$Regime_Source == "DRV_only", na.rm = TRUE)))

  # Latest status
  latest <- tail(merged[!is.na(Combined_Risk_Score)], 1)
  if (nrow(latest) > 0) {
    cat(sprintf("\n  Latest (%s):\n", latest$Date))
    cat(sprintf("    FRED Risk Score: %.0f/100\n", latest$FRED_Risk_Score %||% NA))
    cat(sprintf("    DRV  Risk Score: %.0f/100\n", latest$DRV_Risk_Score %||% NA))
    cat(sprintf("    Combined Score:  %.0f/100 (60/40 blend)\n",
                latest$Combined_Risk_Score))
    cat(sprintf("    Buddha Mode:     %s\n",
                if (isTRUE(latest$Enhanced_Buddha)) "ON" else "OFF"))
  }

  invisible(merged)
}


#==============================================================================
# 8. Load Derivatives Regime Cache
#==============================================================================

load_drv_regime_cache <- function() {
  if (!file.exists(DRV_REGIME_CACHE)) {
    cat("[regime_derivatives] No cached regime data. Run drv_compute_regime() first.\n")
    return(NULL)
  }
  dt <- as.data.table(read_parquet(DRV_REGIME_CACHE))
  cat(sprintf("[regime_derivatives] Loaded cache: %d rows | %s ~ %s\n",
              nrow(dt), min(dt$Date), max(dt$Date)))
  dt
}


#==============================================================================
# 9. Merge Derivatives Regime to Strategy Signals (rolling join)
#==============================================================================

drv_merge_to_signals <- function(FACTORS, drv_regime = NULL) {
  if (is.null(drv_regime)) {
    drv_regime <- load_drv_regime_cache()
  }
  if (is.null(drv_regime) || nrow(drv_regime) == 0) {
    cat("[regime_derivatives] No derivatives regime to merge. Returning FACTORS unchanged.\n")
    return(FACTORS)
  }

  # Select key columns for merge
  merge_cols <- intersect(names(drv_regime),
    c("Date", "VKOSPI_raw", "VKOSPI_regime",
      "PCR_raw", "PCR_regime", "Basis_Pct_raw", "Basis_regime",
      "Skew_raw", "Skew_regime",
      "Drv_Ensemble_Score", "Drv_Ensemble_Regime", "Drv_N_Votes"))

  regime_sub <- drv_regime[, ..merge_cols]
  setkey(regime_sub, Date)

  # Rolling join on unique dates
  unique_dates <- data.table(Date = unique(FACTORS$Date))
  setkey(unique_dates, Date)
  date_regime <- regime_sub[unique_dates, roll = TRUE]

  merged <- merge(FACTORS, date_regime, by = "Date", all.x = TRUE,
                  suffixes = c("", "_drv"))

  n_matched <- sum(!is.na(merged$Drv_Ensemble_Score))
  cat(sprintf("[regime_derivatives] Merged: %d of %d dates matched (%.1f%%)\n",
              n_matched, uniqueN(merged$Date),
              n_matched / max(1, uniqueN(merged$Date)) * 100))

  merged
}


cat("[regime_derivatives] Loaded. Functions:\n")
cat("  drv_vkospi_regime(), drv_pcr_regime(), drv_basis_regime(), drv_skew_regime()\n")
cat("  drv_ensemble_regime(), drv_compute_regime(), drv_merge_with_fred()\n")
cat("  load_drv_regime_cache(), drv_merge_to_signals()\n")
