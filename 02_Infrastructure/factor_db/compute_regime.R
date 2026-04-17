#==============================================================================
# compute_regime.R -- Regime + Macro Factor Module (RE01~RE16, MA01~MA07)
#
# compute_regime(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL)
#   RAWDATA:    data.table(Date, Ticker, Close, Ret, Vol, Size, Sector, BM_Ret)
#   sig_date:   signal date (Date class)
#   FUND:       fundamentals (for macro sensitivity beta estimation)
#   CONSENSUS:  not used
#
# External data:
#   .cache/macro_fred.parquet — 22 macro series (Date, Series, Value)
#   ECOS data if available
#
# Returns: data.table(Ticker, Factor_Name, Raw_Value)
#
# PIT: Date <= sig_date. Expanding window. Macro data lagged 1 day minimum.
#      FRED monthly data: use value available as of sig_date only (C11 compliant).
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
})

compute_regime <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {

  sig_d <- as.Date(sig_date)
  results <- list()

  # ---- Price data prep (PIT: Date <= sig_date) ----
  rd <- copy(RAWDATA)
  rd[, Date := as.Date(Date)]
  lookback_start <- sig_d - 365
  rd <- rd[Date <= sig_d & Date >= lookback_start]

  if (nrow(rd) == 0L) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }

  setkey(rd, Ticker, Date)

  MIN_OBS <- 120L

  # ---- BM daily returns ----
  bm_daily <- unique(rd[!is.na(BM_Ret), .(Date, BM_Ret)])
  setorder(bm_daily, Date)

  # ---- Macro data loading ----
  proj_root <- tryCatch(
    dirname(dirname(dirname(sys.frame(1)$ofile))),
    error = function(e) {
      Sys.getenv("QUANT_ROOT",
                 unset = "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot")
    }
  )

  macro_path <- file.path(proj_root, ".cache", "macro_fred.parquet")
  MACRO <- NULL
  if (file.exists(macro_path)) {
    MACRO <- tryCatch({
      if (requireNamespace("arrow", quietly = TRUE)) {
        dt <- as.data.table(arrow::read_parquet(macro_path))
        dt[, Date := as.Date(Date)]
        # C11: FRED monthly data published with lag. Use data available by sig_date.
        # Conservative: only use data up to sig_date - 1 day (publication lag)
        dt[Date <= (sig_d - 1L)]
      } else NULL
    }, error = function(e) NULL)
  }

  # ---- Helper: EWMA ----
  .ewma <- function(x, halflife = 21) {
    alpha <- 1 - exp(-log(2) / halflife)
    n <- length(x)
    out <- rep(NA_real_, n)
    if (n == 0L) return(out)
    out[1] <- x[1]
    for (i in 2:n) {
      if (is.na(x[i])) {
        out[i] <- out[i - 1]
      } else if (is.na(out[i - 1])) {
        out[i] <- x[i]
      } else {
        out[i] <- alpha * x[i] + (1 - alpha) * out[i - 1]
      }
    }
    out
  }

  # ---- Helper: safe divide ----
  .sdiv <- function(num, den) {
    fifelse(!is.na(num) & !is.na(den) & abs(den) > 1e-8, num / den, NA_real_)
  }

  # ==========================================================================
  # REGIME FACTORS (RE01~RE16) — Market-level, applied to each ticker as
  # cross-sectional sensitivity (beta) to regime indicators
  # ==========================================================================

  # ---- RE01: Market Return EWMA 21d ----
  if (nrow(bm_daily) >= 21L) {
    bm_daily[, mkt_ewma := .ewma(BM_Ret, halflife = 21)]
    mkt_ewma_val <- bm_daily[Date == max(Date)]$mkt_ewma
    if (length(mkt_ewma_val) > 0L && !is.na(mkt_ewma_val)) {
      # Cross-sectional: each ticker gets market-level signal
      snap_tickers <- unique(rd[Date == sig_d]$Ticker)
      if (length(snap_tickers) > 0L) {
        results[["RE01"]] <- data.table(
          Ticker = snap_tickers,
          Factor_Name = "RE01_Mkt_EWMA_21d",
          Raw_Value = mkt_ewma_val
        )
      }
    }
  }

  # ---- RE02: Market Volatility Regime (expanding percentile of 21d realized vol) ----
  if (nrow(bm_daily) >= 42L) {
    # frollsum-based rolling SD (replaces frollapply + sd: O(N) vs O(N*window))
    .roll_sd_bm <- function(x, n) {
      m <- length(x)
      if (m < n) return(rep(NA_real_, m))
      s1 <- suppressWarnings(frollsum(x,   n=n, fill=NA_real_, align="right", na.rm=FALSE))
      s2 <- suppressWarnings(frollsum(x^2, n=n, fill=NA_real_, align="right", na.rm=FALSE))
      vx <- (s2 - s1^2 / n) / (n - 1L)
      sqrt(pmax(vx, 0))
    }
    bm_daily[, mkt_vol21 := .roll_sd_bm(BM_Ret, 21L)]
    last_vol <- bm_daily[Date == max(Date)]$mkt_vol21
    if (length(last_vol) > 0L && !is.na(last_vol)) {
      # Expanding percentile (PIT compliant)
      all_vols <- bm_daily[!is.na(mkt_vol21) & Date <= sig_d]$mkt_vol21
      pctile <- mean(all_vols <= last_vol, na.rm = TRUE)
      snap_tickers <- unique(rd[Date == sig_d]$Ticker)
      if (length(snap_tickers) > 0L) {
        results[["RE02"]] <- data.table(
          Ticker = snap_tickers,
          Factor_Name = "RE02_Vol_Regime_Pctile",
          Raw_Value = -pctile  # negate: high vol = bad
        )
      }
    }
  }

  # ---- RE03: Market Drawdown Regime ----
  if (nrow(bm_daily) >= 21L) {
    bm_daily[, cum_bm := cumprod(1 + fifelse(is.na(BM_Ret), 0, BM_Ret))]
    bm_daily[, cum_max_bm := cummax(cum_bm)]
    bm_daily[, dd_bm := (cum_bm - cum_max_bm) / cum_max_bm]
    last_dd <- bm_daily[Date == max(Date)]$dd_bm
    if (length(last_dd) > 0L && !is.na(last_dd)) {
      snap_tickers <- unique(rd[Date == sig_d]$Ticker)
      if (length(snap_tickers) > 0L) {
        results[["RE03"]] <- data.table(
          Ticker = snap_tickers,
          Factor_Name = "RE03_Mkt_Drawdown",
          Raw_Value = last_dd  # negative = drawdown, positive = near peak
        )
      }
    }
  }

  # ---- RE04~RE09: Stock-level sensitivity to market regime ----
  # Pre-join bm_daily signals to rd → single by=Ticker pass (replaces lapply).
  bm_cols <- c("Date", "BM_Ret")
  if ("mkt_vol21" %in% names(bm_daily)) bm_cols <- c(bm_cols, "mkt_vol21")
  if ("dd_bm"     %in% names(bm_daily)) bm_cols <- c(bm_cols, "dd_bm")

  rd_regime <- merge(
    rd[!is.na(Ret), .(Ticker, Date, Ret)],
    bm_daily[, ..bm_cols],
    by = "Date", all.x = TRUE
  )
  rd_regime <- rd_regime[!is.na(Ret) & !is.na(BM_Ret)]
  setkey(rd_regime, Ticker, Date)

  has_vol21 <- "mkt_vol21" %in% names(rd_regime)
  has_dd    <- "dd_bm"     %in% names(rd_regime)

  regime_betas <- rd_regime[, {
    n <- .N
    re04 <- re05 <- re06 <- re07 <- re08 <- re09 <- NA_real_
    if (n >= MIN_OBS) {
      # RE04/RE05: conditional beta on vol regime
      if (has_vol21 && sum(!is.na(mkt_vol21)) > 0L) {
        vol_med   <- median(mkt_vol21, na.rm = TRUE)
        hv_ok <- !is.na(mkt_vol21) & mkt_vol21 >  vol_med
        lv_ok <- !is.na(mkt_vol21) & mkt_vol21 <= vol_med
        if (sum(hv_ok) >= 30L) {
          f <- tryCatch(lm.fit(cbind(1, BM_Ret[hv_ok]), Ret[hv_ok]), error=function(e) NULL)
          if (!is.null(f)) re04 <- -f$coefficients[2L]
        }
        if (sum(lv_ok) >= 30L) {
          f <- tryCatch(lm.fit(cbind(1, BM_Ret[lv_ok]), Ret[lv_ok]), error=function(e) NULL)
          if (!is.null(f)) re05 <- -f$coefficients[2L]
        }
        if (!is.na(re04) && !is.na(re05)) re06 <- re04 - re05
      }
      # RE07: Crisis beta (market DD < -5%)
      if (has_dd) {
        cr_ok <- !is.na(dd_bm) & dd_bm < -0.05
        if (sum(cr_ok) >= 20L) {
          f <- tryCatch(lm.fit(cbind(1, BM_Ret[cr_ok]), Ret[cr_ok]), error=function(e) NULL)
          if (!is.null(f)) re07 <- -f$coefficients[2L]
        }
      }
      # RE08: Down-market excess return
      dn_ok <- !is.na(BM_Ret) & BM_Ret < 0
      if (sum(dn_ok) >= 30L)
        re08 <- mean(Ret[dn_ok] - BM_Ret[dn_ok], na.rm = TRUE)
      # RE09: Up/Down capture ratio
      up_ok <- !is.na(BM_Ret) & BM_Ret > 0
      if (sum(up_ok) >= 30L && sum(dn_ok) >= 30L) {
        up_cap  <- mean(Ret[up_ok], na.rm=TRUE) / mean(BM_Ret[up_ok], na.rm=TRUE)
        dn_cap  <- mean(Ret[dn_ok], na.rm=TRUE) / mean(BM_Ret[dn_ok], na.rm=TRUE)
        if (!is.na(dn_cap) && abs(dn_cap) > 1e-8) re09 <- up_cap / dn_cap
      }
    }
    list(RE04=re04, RE05=re05, RE06=re06, RE07=re07, RE08=re08, RE09=re09)
  }, by = Ticker]

  # Unpack regime_betas into results list
  .add_re <- function(col, fname) {
    sub <- regime_betas[!is.na(get(col)), .(Ticker, Factor_Name=fname, Raw_Value=get(col))]
    if (nrow(sub) > 0) results[[fname]] <<- sub
  }
  .add_re("RE04", "RE04_HighVol_Beta")
  .add_re("RE05", "RE05_LowVol_Beta")
  .add_re("RE06", "RE06_Beta_Asymmetry")
  .add_re("RE07", "RE07_Crisis_Beta")
  .add_re("RE08", "RE08_Down_Market_Excess")
  .add_re("RE09", "RE09_Capture_Ratio")

  # ==========================================================================
  # RE10~RE16: VIX-based regime indicators (if macro data available)
  # ==========================================================================
  if (!is.null(MACRO) && nrow(MACRO) > 0L) {
    snap_tickers <- unique(rd[Date == sig_d]$Ticker)

    # ---- RE10: VIX Level (expanding percentile) ----
    vix_dt <- MACRO[Series == "VIXCLS" & !is.na(Value)]
    if (nrow(vix_dt) >= 21L) {
      setorder(vix_dt, Date)
      last_vix <- vix_dt[Date == max(Date)]$Value
      if (length(last_vix) > 0L) {
        vix_pctile <- mean(vix_dt$Value <= last_vix, na.rm = TRUE)
        results[["RE10"]] <- data.table(
          Ticker = snap_tickers,
          Factor_Name = "RE10_VIX_Pctile",
          Raw_Value = -vix_pctile  # high VIX = bad
        )
      }

      # ---- RE11: VIX Change EWMA 21d ----
      vix_dt[, vix_ret := c(NA, diff(log(Value)))]
      vix_dt[, vix_ewma := .ewma(vix_ret, halflife = 21)]
      last_ewma <- vix_dt[Date == max(Date)]$vix_ewma
      if (length(last_ewma) > 0L && !is.na(last_ewma)) {
        results[["RE11"]] <- data.table(
          Ticker = snap_tickers,
          Factor_Name = "RE11_VIX_Change_EWMA",
          Raw_Value = -last_ewma  # rising VIX = bad
        )
      }
    }

    # ---- RE12: VIX Rolling Quantile Regime (3-state) ----
    if (nrow(vix_dt) >= 252L) {
      setorder(vix_dt, Date)
      last_vix <- vix_dt[Date == max(Date)]$Value
      # Trailing 252d quantiles
      trailing <- vix_dt[Date >= (sig_d - 365)]$Value
      q33 <- quantile(trailing, 0.33, na.rm = TRUE)
      q67 <- quantile(trailing, 0.67, na.rm = TRUE)
      regime_state <- if (last_vix <= q33) 1 else if (last_vix <= q67) 0 else -1
      results[["RE12"]] <- data.table(
        Ticker = snap_tickers,
        Factor_Name = "RE12_VIX_Regime_3State",
        Raw_Value = regime_state  # 1=low vol, 0=mid, -1=high
      )
    }

    # ---- RE13: Credit Spread (High Yield OAS) ----
    hy_dt <- MACRO[Series %in% c("BAMLH0A0HYM2", "BAMLH0A0HYM2EY") & !is.na(Value)]
    if (nrow(hy_dt) >= 21L) {
      setorder(hy_dt, Date)
      last_hy <- hy_dt[Date == max(Date)]$Value
      if (length(last_hy) > 0L) {
        hy_pctile <- mean(hy_dt$Value <= last_hy, na.rm = TRUE)
        results[["RE13"]] <- data.table(
          Ticker = snap_tickers,
          Factor_Name = "RE13_Credit_Spread_Pctile",
          Raw_Value = -hy_pctile  # wide spread = bad
        )
      }
    }

    # ---- RE14: Inflation Regime (CPI YoY expanding percentile) ----
    cpi_dt <- MACRO[Series %in% c("CPIAUCSL", "CPIAUCNS") & !is.na(Value)]
    if (nrow(cpi_dt) >= 13L) {
      setorder(cpi_dt, Date)
      cpi_dt[, cpi_yoy := Value / shift(Value, 12) - 1]
      cpi_dt <- cpi_dt[!is.na(cpi_yoy)]
      if (nrow(cpi_dt) > 0L) {
        last_cpi <- cpi_dt[Date == max(Date)]$cpi_yoy
        if (length(last_cpi) > 0L) {
          # High inflation = regime signal
          results[["RE14"]] <- data.table(
            Ticker = snap_tickers,
            Factor_Name = "RE14_Inflation_YoY",
            Raw_Value = -last_cpi  # high inflation = bad for equities
          )
        }
      }
    }

    # ---- RE15: Cross-Sectional Breadth (% of stocks with positive returns) ----
    # Market-internal breadth indicator
    breadth_dt <- rd[Date >= (sig_d - 21L) & Date <= sig_d & !is.na(Ret)]
    if (nrow(breadth_dt) > 0L) {
      breadth <- breadth_dt[, .(pct_positive = mean(Ret > 0, na.rm = TRUE)), by = Date]
      last_breadth <- mean(breadth$pct_positive, na.rm = TRUE)
      results[["RE15"]] <- data.table(
        Ticker = snap_tickers,
        Factor_Name = "RE15_Market_Breadth_21d",
        Raw_Value = last_breadth  # higher breadth = healthier market
      )
    }

    # ---- RE16: Canary Momentum Signal proxy ----
    # Use S&P 500 + VIX as canary: if S&P momentum negative, defensive signal
    sp_dt <- MACRO[Series %in% c("SP500", "GSPC") & !is.na(Value)]
    if (nrow(sp_dt) >= 63L) {
      setorder(sp_dt, Date)
      last_sp <- sp_dt[Date == max(Date)]$Value
      sp_63d  <- sp_dt[Date <= (sig_d - 63)]
      if (nrow(sp_63d) > 0L) {
        sp_mom <- last_sp / sp_63d[Date == max(Date)]$Value - 1
        if (length(sp_mom) > 0L && !is.na(sp_mom)) {
          canary_signal <- fifelse(sp_mom < 0, -1, 1)
          results[["RE16"]] <- data.table(
            Ticker = snap_tickers,
            Factor_Name = "RE16_Canary_Signal",
            Raw_Value = canary_signal
          )
        }
      }
    }
  }

  # ==========================================================================
  # MACRO FACTORS (MA01~MA07) — Stock-level beta to macro variables
  # ==========================================================================
  if (!is.null(MACRO) && nrow(MACRO) > 0L) {
    snap_tickers <- unique(rd[Date == sig_d]$Ticker)

    # Prepare monthly stock returns for macro regression
    rd_monthly <- rd[, .(monthly_ret = prod(1 + Ret, na.rm = TRUE) - 1),
                     by = .(Ticker, YM = format(Date, "%Y-%m"))]

    # ---- Helper: compute beta to a macro series for each ticker ----
    .macro_beta <- function(macro_series_name, factor_name) {
      ms <- MACRO[Series == macro_series_name & !is.na(Value)]
      if (nrow(ms) < 12L) return(NULL)
      setorder(ms, Date)
      ms[, YM := format(Date, "%Y-%m")]
      # Monthly change in macro variable
      ms[, macro_chg := Value - shift(Value, 1)]
      ms <- ms[!is.na(macro_chg), .(YM, macro_chg)]

      merged <- merge(rd_monthly, ms, by = "YM", all.x = TRUE)
      merged <- merged[!is.na(monthly_ret) & !is.na(macro_chg)]

      if (nrow(merged) < 12L) return(NULL)

      betas <- merged[, {
        if (.N >= 12L) {
          fit <- tryCatch(lm.fit(cbind(1, macro_chg), monthly_ret), error = function(e) NULL)
          if (!is.null(fit)) {
            .(beta = fit$coefficients[2])
          } else {
            .(beta = NA_real_)
          }
        } else {
          .(beta = NA_real_)
        }
      }, by = Ticker]

      betas <- betas[!is.na(beta)]
      if (nrow(betas) == 0L) return(NULL)
      betas[, .(Ticker, Factor_Name = factor_name, Raw_Value = beta)]
    }

    # ---- MA01: GDP Sensitivity (using GDP proxy or industrial production) ----
    ma01 <- .macro_beta("INDPRO", "MA01_GDP_Sensitivity")
    if (is.null(ma01)) ma01 <- .macro_beta("A191RL1Q225SBEA", "MA01_GDP_Sensitivity")
    if (!is.null(ma01)) results[["MA01"]] <- ma01

    # ---- MA02: CPI Sensitivity ----
    ma02 <- .macro_beta("CPIAUCSL", "MA02_CPI_Sensitivity")
    if (is.null(ma02)) ma02 <- .macro_beta("CPIAUCNS", "MA02_CPI_Sensitivity")
    if (!is.null(ma02)) results[["MA02"]] <- ma02

    # ---- MA03: Interest Rate Sensitivity (10Y Treasury) ----
    ma03 <- .macro_beta("GS10", "MA03_Rate_Sensitivity")
    if (is.null(ma03)) ma03 <- .macro_beta("DGS10", "MA03_Rate_Sensitivity")
    if (!is.null(ma03)) results[["MA03"]] <- ma03

    # ---- MA04: Yield Curve Sensitivity (10Y-2Y spread) ----
    ys10 <- MACRO[Series %in% c("GS10", "DGS10") & !is.na(Value)]
    ys2  <- MACRO[Series %in% c("GS2", "DGS2") & !is.na(Value)]
    if (nrow(ys10) > 0L && nrow(ys2) > 0L) {
      setorder(ys10, Date); setorder(ys2, Date)
      ys10[, YM := format(Date, "%Y-%m")]
      ys2[, YM := format(Date, "%Y-%m")]
      yc <- merge(ys10[, .(YM, y10 = Value)], ys2[, .(YM, y2 = Value)], by = "YM")
      yc[, spread := y10 - y2]
      yc[, spread_chg := spread - shift(spread, 1)]
      yc <- yc[!is.na(spread_chg)]
      if (nrow(yc) >= 12L) {
        merged_yc <- merge(rd_monthly, yc[, .(YM, macro_chg = spread_chg)], by = "YM", all.x = TRUE)
        merged_yc <- merged_yc[!is.na(monthly_ret) & !is.na(macro_chg)]
        if (nrow(merged_yc) >= 12L) {
          betas_yc <- merged_yc[, {
            if (.N >= 12L) {
              fit <- tryCatch(lm.fit(cbind(1, macro_chg), monthly_ret), error = function(e) NULL)
              if (!is.null(fit)) .(beta = fit$coefficients[2]) else .(beta = NA_real_)
            } else .(beta = NA_real_)
          }, by = Ticker]
          betas_yc <- betas_yc[!is.na(beta)]
          if (nrow(betas_yc) > 0L) {
            results[["MA04"]] <- betas_yc[, .(Ticker, Factor_Name = "MA04_YieldCurve_Sensitivity", Raw_Value = beta)]
          }
        }
      }
    }

    # ---- MA05: Monetary Policy Momentum (1Y change in 2Y yield) ----
    ys2_mp <- MACRO[Series %in% c("GS2", "DGS2") & !is.na(Value)]
    if (nrow(ys2_mp) >= 252L) {
      setorder(ys2_mp, Date)
      last_y2 <- ys2_mp[Date == max(Date)]$Value
      y2_1y   <- ys2_mp[Date <= (sig_d - 365)]
      if (nrow(y2_1y) > 0L) {
        y2_1y_val <- y2_1y[Date == max(Date)]$Value
        mp_mom <- last_y2 - y2_1y_val
        if (length(mp_mom) > 0L && !is.na(mp_mom)) {
          results[["MA05"]] <- data.table(
            Ticker = snap_tickers,
            Factor_Name = "MA05_MonetaryPolicy_Mom",
            Raw_Value = -mp_mom  # rising yields = tightening = bad for equities
          )
        }
      }
    }

    # ---- MA06: Risk Sentiment (1Y equity market return) ----
    if (nrow(bm_daily) >= 252L) {
      bm_1y <- bm_daily[Date >= (sig_d - 365)]
      if (nrow(bm_1y) > 0L) {
        mkt_1y_ret <- prod(1 + bm_1y$BM_Ret, na.rm = TRUE) - 1
        results[["MA06"]] <- data.table(
          Ticker = snap_tickers,
          Factor_Name = "MA06_Risk_Sentiment_1Y",
          Raw_Value = mkt_1y_ret
        )
      }
    }

    # ---- MA07: Business Cycle Composite ----
    # Combine GDP + CPI momentum into composite
    ma07_parts <- list()
    gdp_dt <- MACRO[Series %in% c("INDPRO", "A191RL1Q225SBEA") & !is.na(Value)]
    if (nrow(gdp_dt) >= 13L) {
      setorder(gdp_dt, Date)
      gdp_dt[, gdp_yoy := Value / shift(Value, 12) - 1]
      last_gdp <- gdp_dt[!is.na(gdp_yoy)][Date == max(Date)]$gdp_yoy
      if (length(last_gdp) > 0L) ma07_parts[["gdp"]] <- last_gdp
    }
    cpi_dt2 <- MACRO[Series %in% c("CPIAUCSL", "CPIAUCNS") & !is.na(Value)]
    if (nrow(cpi_dt2) >= 13L) {
      setorder(cpi_dt2, Date)
      cpi_dt2[, cpi_yoy := Value / shift(Value, 12) - 1]
      last_cpi2 <- cpi_dt2[!is.na(cpi_yoy)][Date == max(Date)]$cpi_yoy
      if (length(last_cpi2) > 0L) ma07_parts[["cpi"]] <- last_cpi2
    }
    if (length(ma07_parts) >= 1L) {
      # 50/50 GDP growth + (-CPI inflation)
      gdp_val <- if (!is.null(ma07_parts[["gdp"]])) ma07_parts[["gdp"]] else 0
      cpi_val <- if (!is.null(ma07_parts[["cpi"]])) -ma07_parts[["cpi"]] else 0
      bc_composite <- 0.5 * gdp_val + 0.5 * cpi_val
      results[["MA07"]] <- data.table(
        Ticker = snap_tickers,
        Factor_Name = "MA07_BusinessCycle_Composite",
        Raw_Value = bc_composite
      )
    }
  } else {
    # No macro data -- mark as DATA_NEEDED
    # DATA_NEEDED: macro_fred.parquet for MA01~MA07, RE10~RE16
    snap_tickers <- unique(rd[Date == sig_d]$Ticker)
  }

  # ---- Combine all ----
  if (length(results) == 0L) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }
  out <- rbindlist(results, use.names = TRUE, fill = TRUE)
  out[, .(Ticker, Factor_Name, Raw_Value)]
}

cat("[factor_db] compute_regime.R loaded (RE01~RE16, MA01~MA07)\n")
