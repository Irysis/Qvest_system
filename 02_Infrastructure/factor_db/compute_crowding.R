#==============================================================================
# compute_crowding.R -- Crowding + Sentiment + Trend Factor Module
#   CR01~CR11 (Crowding), SE01~SE02 (Sentiment), TR01~TR02 (Trend)
#
# compute_crowding(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL)
#   RAWDATA:    data.table(Date, Ticker, Close, Ret, Vol, Size, Sector, BM_Ret,
#                          Open, High, Low)
#   sig_date:   signal date (Date class)
#   FUND:       fundamentals (for ownership-related factors)
#   CONSENSUS:  consensus data (for sentiment proxies)
#
# Returns: data.table(Ticker, Factor_Name, Raw_Value)
#
# PIT: Date <= sig_date. Expanding window. No future data.
#      C1-C11 compliant.
#
# Note: Many crowding factors in the literature require hedge fund holdings,
#       short interest, or order flow data not available in RAWDATA.
#       Implementable factors use price/volume proxies. Others marked DATA_NEEDED.
#
# References:
#   Cahan & Luo (2013) MPC, Lou & Polk DTC, Palmon actratio proxy,
#   ADX for trend, consensus dispersion for sentiment
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
})

compute_crowding <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {

  sig_d <- as.Date(sig_date)
  results <- list()

  # ---- Price data prep ----
  rd <- copy(RAWDATA)
  rd[, Date := as.Date(Date)]
  lookback_start <- sig_d - 365
  rd <- rd[Date <= sig_d & Date >= lookback_start]

  if (nrow(rd) == 0L) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }

  setorder(rd, Ticker, Date)

  MIN_OBS <- 60L

  # ---- BM daily ----
  bm_daily <- unique(rd[!is.na(BM_Ret), .(Date, BM_Ret)])
  setorder(bm_daily, Date)

  # ---- Helper: safe divide ----
  .sdiv <- function(num, den) {
    fifelse(!is.na(num) & !is.na(den) & abs(den) > 1e-8, num / den, NA_real_)
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

  tickers <- unique(rd$Ticker)

  # ==========================================================================
  # CROWDING FACTORS (CR01~CR11)
  # ==========================================================================

  # ---- CR01: Return Comovement (Mean Pairwise Correlation proxy) ----
  # Higher MPC with sector peers = more crowded
  # Use 63d rolling correlation with sector average return
  if ("Sector" %in% names(rd)) {
    # Compute sector average return (excluding self)
    rd_sec <- rd[!is.na(Ret) & !is.na(Sector)]
    if (nrow(rd_sec) > 0L) {
      sec_avg <- rd_sec[, .(sec_ret = mean(Ret, na.rm = TRUE), sec_n = .N), by = .(Date, Sector)]
      rd_sec <- merge(rd_sec, sec_avg, by = c("Date", "Sector"), all.x = TRUE)
      # Adjust for self: sec_ret_ex = (sec_ret * sec_n - Ret) / (sec_n - 1)
      rd_sec[, sec_ret_ex := fifelse(sec_n > 1, (sec_ret * sec_n - Ret) / (sec_n - 1), NA_real_)]

      cr01 <- rd_sec[!is.na(Ret) & !is.na(sec_ret_ex), {
        if (.N >= MIN_OBS) {
          # Rolling 63d correlation
          n_roll <- min(.N, 63L)
          tail_ret  <- Ret[(.N - n_roll + 1):.N]
          tail_sec  <- sec_ret_ex[(.N - n_roll + 1):.N]
          valid <- !is.na(tail_ret) & !is.na(tail_sec)
          if (sum(valid) >= 30L) {
            rho <- cor(tail_ret[valid], tail_sec[valid])
            .(Factor_Name = "CR01_Sector_Comovement", Raw_Value = -rho)  # high comove = crowded = bad
          } else {
            .(Factor_Name = "CR01_Sector_Comovement", Raw_Value = NA_real_)
          }
        } else {
          .(Factor_Name = "CR01_Sector_Comovement", Raw_Value = NA_real_)
        }
      }, by = Ticker]
      cr01 <- cr01[!is.na(Raw_Value)]
      if (nrow(cr01) > 0L) results[["CR01"]] <- cr01
    }
  }

  # ---- CR02: Volume Concentration (20d vol / 252d vol) ----
  # Sudden volume surge = crowding signal
  vol_data <- rd[!is.na(Vol) & Vol > 0]
  if (nrow(vol_data) > 0L) {
    cr02 <- vol_data[, {
      if (.N >= MIN_OBS) {
        vol20  <- mean(Vol[max(1, .N - 19):.N], na.rm = TRUE)
        vol252 <- mean(Vol, na.rm = TRUE)
        if (!is.na(vol252) && vol252 > 0) {
          .(Factor_Name = "CR02_Volume_Concentration", Raw_Value = -(vol20 / vol252))
        } else {
          .(Factor_Name = "CR02_Volume_Concentration", Raw_Value = NA_real_)
        }
      } else {
        .(Factor_Name = "CR02_Volume_Concentration", Raw_Value = NA_real_)
      }
    }, by = Ticker]
    cr02 <- cr02[!is.na(Raw_Value)]
    if (nrow(cr02) > 0L) results[["CR02"]] <- cr02
  }

  # ---- CR03: Herding Measure (Cross-Sectional Dispersion of Returns) ----
  # Low dispersion = high herding = more crowded
  disp_data <- rd[!is.na(Ret)]
  if (nrow(disp_data) > 0L) {
    cs_disp <- disp_data[Date >= (sig_d - 21), .(disp = sd(Ret, na.rm = TRUE)), by = Date]
    if (nrow(cs_disp) > 0L) {
      mean_disp <- mean(cs_disp$disp, na.rm = TRUE)
      snap_tickers <- unique(rd[Date == sig_d]$Ticker)
      if (length(snap_tickers) > 0L && !is.na(mean_disp)) {
        results[["CR03"]] <- data.table(
          Ticker = snap_tickers,
          Factor_Name = "CR03_Herding_Dispersion",
          Raw_Value = mean_disp  # higher dispersion = less herding = better
        )
      }
    }
  }

  # ---- CR04: Ownership Concentration proxy (Turnover Ratio inverse) ----
  # Low turnover = concentrated holding = more crowded
  if (all(c("Vol", "Size", "Close") %in% names(rd))) {
    rd[, est_shares := fifelse(Close > 0, Size / Close, NA_real_)]
    cr04_data <- rd[!is.na(Vol) & !is.na(est_shares) & est_shares > 0]
    if (nrow(cr04_data) > 0L) {
      cr04 <- cr04_data[, {
        if (.N >= 20L) {
          # 20d average turnover rate
          n_tail <- min(.N, 20L)
          tail_data <- .SD[(.N - n_tail + 1):.N]
          avg_turnover <- mean(tail_data$Vol / tail_data$est_shares, na.rm = TRUE)
          .(Factor_Name = "CR04_Ownership_Concentration", Raw_Value = avg_turnover)
          # Higher turnover = less concentrated = better
        } else {
          .(Factor_Name = "CR04_Ownership_Concentration", Raw_Value = NA_real_)
        }
      }, by = Ticker]
      cr04 <- cr04[!is.na(Raw_Value)]
      if (nrow(cr04) > 0L) results[["CR04"]] <- cr04
    }
  }

  # ---- CR05: Short Interest Proxy (inferred from price-volume dynamics) ----
  # Amihud ratio on down days vs up days. Higher on down days = short pressure.
  # DATA_NEEDED: actual short interest for proper implementation
  if (all(c("Ret", "Vol") %in% names(rd))) {
    cr05 <- rd[!is.na(Ret) & !is.na(Vol) & Vol > 0, {
      if (.N >= MIN_OBS) {
        down <- .SD[Ret < 0]
        up   <- .SD[Ret >= 0]
        if (nrow(down) >= 20L && nrow(up) >= 20L) {
          amihud_down <- mean(abs(down$Ret) / down$Vol, na.rm = TRUE)
          amihud_up   <- mean(abs(up$Ret) / up$Vol, na.rm = TRUE)
          if (amihud_up > 1e-12) {
            .(Factor_Name = "CR05_Short_Pressure_Proxy", Raw_Value = -(amihud_down / amihud_up))
          } else {
            .(Factor_Name = "CR05_Short_Pressure_Proxy", Raw_Value = NA_real_)
          }
        } else {
          .(Factor_Name = "CR05_Short_Pressure_Proxy", Raw_Value = NA_real_)
        }
      } else {
        .(Factor_Name = "CR05_Short_Pressure_Proxy", Raw_Value = NA_real_)
      }
    }, by = Ticker]
    cr05 <- cr05[!is.na(Raw_Value)]
    if (nrow(cr05) > 0L) results[["CR05"]] <- cr05
  }

  # ---- CR06: Days to Cover proxy (Vol / 20d avg vol) ----
  # DATA_NEEDED: actual short interest for DTC = SI / ADV
  # Proxy: use turnover persistence instead
  if (all(c("Vol", "Size", "Close") %in% names(rd))) {
    cr06 <- rd[!is.na(Vol) & Vol > 0, {
      if (.N >= 20L) {
        n_tail <- min(.N, 20L)
        avg_vol <- mean(Vol[max(1, .N - 19):.N], na.rm = TRUE)
        est_sh <- Size[.N] / Close[.N]
        if (!is.na(avg_vol) && avg_vol > 0 && !is.na(est_sh) && est_sh > 0) {
          dtc <- est_sh / avg_vol  # days to trade all shares
          .(Factor_Name = "CR06_DTC_Proxy", Raw_Value = -dtc)  # lower DTC = more liquid = better
        } else {
          .(Factor_Name = "CR06_DTC_Proxy", Raw_Value = NA_real_)
        }
      } else {
        .(Factor_Name = "CR06_DTC_Proxy", Raw_Value = NA_real_)
      }
    }, by = Ticker]
    cr06 <- cr06[!is.na(Raw_Value)]
    if (nrow(cr06) > 0L) results[["CR06"]] <- cr06
  }

  # ---- CR07: Factor Crowding (correlation with momentum factor portfolio) ----
  # Stocks moving too closely with momentum portfolio = crowded
  #
  # build-gap fix (2026-05-29): the 12-1 momentum needs >252 daily points per
  # ticker, but the shared `rd` is truncated to a 365-calendar-day window
  # (line 37-38) holding only 242~253 KR trading days. In recent years (more
  # holidays) max .N fell to ~248 -> 0 tickers qualified -> CR07 silently
  # dropped (only 200602~201008 survived, exactly the 253-trading-day windows).
  # Fix: build the momentum ranking from a wider ~410-day slice of the ORIGINAL
  # RAWDATA argument (PIT-safe: Date <= sig_d only, past data only). The
  # correlation step still uses the 365d `rd` (MIN_OBS=60), unchanged.
  rd_mom <- copy(RAWDATA)
  rd_mom[, Date := as.Date(Date)]
  rd_mom <- rd_mom[Date <= sig_d & Date >= (sig_d - 410L)]
  setorder(rd_mom, Ticker, Date)
  mom_12_1 <- rd_mom[!is.na(Ret), {
    if (.N > 252L) {
      idx_s <- max(1L, .N - 252L + 1L)
      idx_e <- .N - 21L
      if (idx_e > idx_s) {
        .(mom_val = prod(1 + Ret[idx_s:idx_e]) - 1)
      } else {
        .(mom_val = NA_real_)
      }
    } else {
      .(mom_val = NA_real_)
    }
  }, by = Ticker]
  mom_12_1 <- mom_12_1[!is.na(mom_val)]
  if (nrow(mom_12_1) > 0L) {
    # Create momentum-weighted portfolio return
    mom_12_1[, mom_rank := frank(mom_val) / .N]
    # Top quintile momentum stocks
    top_mom <- mom_12_1[mom_rank >= 0.8]$Ticker
    if (length(top_mom) >= 5L) {
      mom_port <- rd[Ticker %in% top_mom & !is.na(Ret),
                     .(port_ret = mean(Ret, na.rm = TRUE)), by = Date]
      setorder(mom_port, Date)
      # Each ticker's correlation with momentum portfolio
      cr07 <- rd[!is.na(Ret), {
        sub_m <- merge(.SD[, .(Date, Ret)], mom_port, by = "Date", all.x = TRUE)
        sub_m <- sub_m[!is.na(Ret) & !is.na(port_ret)]
        if (nrow(sub_m) >= MIN_OBS) {
          rho <- cor(sub_m$Ret, sub_m$port_ret)
          .(Factor_Name = "CR07_Momentum_Crowding", Raw_Value = -rho)
        } else {
          .(Factor_Name = "CR07_Momentum_Crowding", Raw_Value = NA_real_)
        }
      }, by = Ticker]
      cr07 <- cr07[!is.na(Raw_Value)]
      if (nrow(cr07) > 0L) results[["CR07"]] <- cr07
    }
  }

  # ---- CR08: Volume-Price Divergence (rising price + falling volume = divergence) ----
  cr08 <- rd[!is.na(Ret) & !is.na(Vol) & Vol > 0, {
    if (.N >= 42L) {
      n21 <- min(.N, 21L)
      tail21 <- .SD[(.N - n21 + 1):.N]
      price_trend <- mean(tail21$Ret, na.rm = TRUE)
      # Volume trend: log(recent vol / prior vol)
      vol_recent <- mean(tail21$Vol, na.rm = TRUE)
      n_prior <- min(.N - n21, 21L)
      if (n_prior > 0L) {
        prior_start <- max(1L, .N - n21 - n_prior + 1L)
        vol_prior <- mean(Vol[prior_start:(.N - n21)], na.rm = TRUE)
        if (vol_prior > 0) {
          vol_trend <- log(vol_recent / vol_prior)
          # Divergence: price up but volume down (or vice versa)
          div_score <- price_trend * sign(-vol_trend) * abs(vol_trend)
          .(Factor_Name = "CR08_Volume_Price_Divergence", Raw_Value = -abs(div_score))
        } else {
          .(Factor_Name = "CR08_Volume_Price_Divergence", Raw_Value = NA_real_)
        }
      } else {
        .(Factor_Name = "CR08_Volume_Price_Divergence", Raw_Value = NA_real_)
      }
    } else {
      .(Factor_Name = "CR08_Volume_Price_Divergence", Raw_Value = NA_real_)
    }
  }, by = Ticker]
  cr08 <- cr08[!is.na(Raw_Value)]
  if (nrow(cr08) > 0L) results[["CR08"]] <- cr08

  # ---- CR09: Smart/Dumb Money proxy (large vs small trade imbalance) ----
  # DATA_NEEDED: actual fund flow data. Proxy: volume on up vs down days
  if (all(c("Ret", "Vol") %in% names(rd))) {
    cr09 <- rd[!is.na(Ret) & !is.na(Vol) & Vol > 0, {
      if (.N >= MIN_OBS) {
        up_vol   <- sum(Vol[Ret > 0], na.rm = TRUE)
        down_vol <- sum(Vol[Ret < 0], na.rm = TRUE)
        total_vol <- up_vol + down_vol
        if (total_vol > 0) {
          money_flow <- (up_vol - down_vol) / total_vol
          .(Factor_Name = "CR09_Money_Flow_Ratio", Raw_Value = money_flow)
        } else {
          .(Factor_Name = "CR09_Money_Flow_Ratio", Raw_Value = NA_real_)
        }
      } else {
        .(Factor_Name = "CR09_Money_Flow_Ratio", Raw_Value = NA_real_)
      }
    }, by = Ticker]
    cr09 <- cr09[!is.na(Raw_Value)]
    if (nrow(cr09) > 0L) results[["CR09"]] <- cr09
  }

  # ---- CR10: Convergence/Divergence premium proxy ----
  # Stocks with mean-reverting returns vs trending returns
  cr10 <- rd[!is.na(Ret), {
    if (.N >= MIN_OBS) {
      # AR(1) coefficient: positive = trending, negative = mean-reverting
      y <- Ret[-1]; x <- Ret[-.N]
      if (sd(x, na.rm = TRUE) > 1e-8) {
        fit <- tryCatch(lm.fit(cbind(1, x), y), error = function(e) NULL)
        if (!is.null(fit)) {
          ar1 <- fit$coefficients[2]
          # Mean-reverting (convergence) strategies are safer
          .(Factor_Name = "CR10_Convergence_Premium", Raw_Value = -ar1)
        } else {
          .(Factor_Name = "CR10_Convergence_Premium", Raw_Value = NA_real_)
        }
      } else {
        .(Factor_Name = "CR10_Convergence_Premium", Raw_Value = NA_real_)
      }
    } else {
      .(Factor_Name = "CR10_Convergence_Premium", Raw_Value = NA_real_)
    }
  }, by = Ticker]
  cr10 <- cr10[!is.na(Raw_Value)]
  if (nrow(cr10) > 0L) results[["CR10"]] <- cr10

  # ---- CR11: Idiosyncratic Return (stocks with unique returns less crowded) ----
  cr11 <- rd[!is.na(Ret) & !is.na(BM_Ret), {
    if (.N >= MIN_OBS) {
      fit <- tryCatch(lm.fit(cbind(1, BM_Ret), Ret), error = function(e) NULL)
      if (!is.null(fit)) {
        r_sq <- 1 - sum(fit$residuals^2) / sum((Ret - mean(Ret))^2)
        .(Factor_Name = "CR11_Idiosyncratic_Return", Raw_Value = 1 - r_sq)
        # Higher idiosyncratic component = less crowded
      } else {
        .(Factor_Name = "CR11_Idiosyncratic_Return", Raw_Value = NA_real_)
      }
    } else {
      .(Factor_Name = "CR11_Idiosyncratic_Return", Raw_Value = NA_real_)
    }
  }, by = Ticker]
  cr11 <- cr11[!is.na(Raw_Value)]
  if (nrow(cr11) > 0L) results[["CR11"]] <- cr11

  # ==========================================================================
  # SENTIMENT FACTORS (SE01~SE02)
  # ==========================================================================

  # ---- SE01: Consensus Dispersion (forecast disagreement) ----
  # Higher dispersion = more uncertainty
  # CONSENSUS is a named list of data.tables; merge relevant sub-tables
  .cons_merged <- NULL
  if (is.list(CONSENSUS) && length(CONSENSUS) > 0L) {
    .cons_parts <- list()
    for (.nm in names(CONSENSUS)) {
      .sub <- CONSENSUS[[.nm]]
      if (is.data.table(.sub) && nrow(.sub) > 0L && all(c("Date", "Ticker") %in% names(.sub))) {
        .sub <- copy(.sub)
        .sub[, Date := as.Date(Date)]
        .cons_parts[[.nm]] <- .sub
      }
    }
    if (length(.cons_parts) > 0L) {
      .cons_merged <- Reduce(function(a, b) merge(a, b, by = c("Date", "Ticker"), all = TRUE), .cons_parts)
      .cons_merged <- .cons_merged[Date <= sig_d]
      if (nrow(.cons_merged) == 0L) .cons_merged <- NULL
    }
  }

  if (!is.null(.cons_merged) && nrow(.cons_merged) > 0L) {
    cs_pit <- .cons_merged
    # Check for dispersion or std columns
    disp_cols <- intersect(names(cs_pit), c("eps_std", "eps_dispersion",
                                             "target_std", "target_dispersion"))
    if (length(disp_cols) > 0L) {
      setorder(cs_pit, Ticker, -Date)
      cs_latest <- cs_pit[, .SD[1L], by = Ticker]
      # Use first available dispersion measure
      dc <- disp_cols[1]
      cs_latest[, SE01 := -get(dc)]  # negate: higher disagreement = bad
      se01 <- cs_latest[!is.na(SE01), .(Ticker, Factor_Name = "SE01_Consensus_Dispersion", Raw_Value = SE01)]
      if (nrow(se01) > 0L) results[["SE01"]] <- se01
    }

    # ---- SE02: Earnings Revision (consensus change proxy) ----
    # Need at least 2 consensus dates to compute revision
    rev_cols <- intersect(names(cs_pit), c("eps_1y", "target_price"))
    if (length(rev_cols) > 0L) {
      rc <- rev_cols[1]
      cs_pit[, date_rank := frank(-as.numeric(Date)), by = Ticker]
      curr_cs <- cs_pit[date_rank == 1, .(Ticker, val_curr = get(rc))]
      prev_cs <- cs_pit[date_rank == 2, .(Ticker, val_prev = get(rc))]
      rev_dt <- merge(curr_cs, prev_cs, by = "Ticker", all = FALSE)
      rev_dt <- rev_dt[!is.na(val_curr) & !is.na(val_prev) & abs(val_prev) > 1e-8]
      if (nrow(rev_dt) > 0L) {
        rev_dt[, SE02 := (val_curr - val_prev) / abs(val_prev)]
        results[["SE02"]] <- rev_dt[!is.na(SE02) & is.finite(SE02),
                                     .(Ticker, Factor_Name = "SE02_Consensus_Revision", Raw_Value = SE02)]
      }
    }
  } else {
    # DATA_NEEDED: consensus data for SE01~SE02
    # Fallback: use price-based sentiment proxy
    # SE01 fallback: Realized vol as uncertainty proxy
    se01_fb <- rd[!is.na(Ret), {
      if (.N >= 21L) {
        vol21 <- sd(Ret[max(1, .N - 20):.N], na.rm = TRUE)
        .(Factor_Name = "SE01_Volatility_Uncertainty", Raw_Value = -vol21)
      } else {
        .(Factor_Name = "SE01_Volatility_Uncertainty", Raw_Value = NA_real_)
      }
    }, by = Ticker]
    se01_fb <- se01_fb[!is.na(Raw_Value)]
    if (nrow(se01_fb) > 0L) results[["SE01_fb"]] <- se01_fb
  }

  # ---- SE01 fallback when consensus exists but has NO dispersion column ----
  # build-gap fix (2026-05-29): consensus tables (eps_1y, target_price, sue, ...)
  # exist from 2000-03 onward but NONE carry a dispersion column (eps_std /
  # eps_dispersion / target_std / target_dispersion). The consensus branch
  # therefore produced SE02 but never SE01_Consensus_Dispersion, AND the
  # else-fallback above only fires when consensus is entirely absent. Net result:
  # SE01 had a permanent hole 2000-03 onward (only 199002~200002 survived via
  # the pre-consensus fallback). This block emits the realized-vol uncertainty
  # proxy whenever the consensus dispersion measure was unavailable, restoring
  # full-history SE01 coverage. PIT-safe: 21-day trailing realized vol, past only.
  if (is.null(results[["SE01"]]) && is.null(results[["SE01_fb"]])) {
    se01_fb2 <- rd[!is.na(Ret), {
      if (.N >= 21L) {
        vol21 <- sd(Ret[max(1, .N - 20):.N], na.rm = TRUE)
        .(Factor_Name = "SE01_Volatility_Uncertainty", Raw_Value = -vol21)
      } else {
        .(Factor_Name = "SE01_Volatility_Uncertainty", Raw_Value = NA_real_)
      }
    }, by = Ticker]
    se01_fb2 <- se01_fb2[!is.na(Raw_Value)]
    if (nrow(se01_fb2) > 0L) results[["SE01_fb2"]] <- se01_fb2
  }

  # ==========================================================================
  # TREND FACTORS (TR01~TR02)
  # ==========================================================================

  # ---- TR01: ADX Proxy (Average Directional Index, Wilder 1978) ----
  # Requires High, Low, Close
  if (all(c("High", "Low", "Close") %in% names(rd))) {
    tr01 <- rd[!is.na(High) & !is.na(Low) & !is.na(Close), {
      if (.N >= 28L) {
        n <- .N
        hi  <- High
        lo  <- Low
        cl  <- Close

        # True Range
        tr <- pmax(hi[-1] - lo[-1],
                   abs(hi[-1] - cl[-n]),
                   abs(lo[-1] - cl[-n]))

        # +DM, -DM
        up_move   <- hi[-1] - hi[-n]
        down_move <- lo[-n] - lo[-1]
        plus_dm  <- fifelse(up_move > down_move & up_move > 0, up_move, 0)
        minus_dm <- fifelse(down_move > up_move & down_move > 0, down_move, 0)

        # Smoothed over 14 periods using Wilder's method
        period <- 14L
        if (length(tr) >= period) {
          # Initial sums
          atr14  <- mean(tr[1:period])
          pdi14  <- mean(plus_dm[1:period])
          mdi14  <- mean(minus_dm[1:period])

          # Wilder smoothing for remaining periods
          for (i in (period + 1):length(tr)) {
            atr14 <- (atr14 * (period - 1) + tr[i]) / period
            pdi14 <- (pdi14 * (period - 1) + plus_dm[i]) / period
            mdi14 <- (mdi14 * (period - 1) + minus_dm[i]) / period
          }

          if (atr14 > 1e-8) {
            plus_di  <- pdi14 / atr14 * 100
            minus_di <- mdi14 / atr14 * 100
            di_sum   <- plus_di + minus_di
            if (di_sum > 1e-8) {
              dx <- abs(plus_di - minus_di) / di_sum * 100
              # ADX is smoothed DX; single-period proxy
              .(Factor_Name = "TR01_ADX_Proxy", Raw_Value = dx)
              # Higher ADX = stronger trend
            } else {
              .(Factor_Name = "TR01_ADX_Proxy", Raw_Value = NA_real_)
            }
          } else {
            .(Factor_Name = "TR01_ADX_Proxy", Raw_Value = NA_real_)
          }
        } else {
          .(Factor_Name = "TR01_ADX_Proxy", Raw_Value = NA_real_)
        }
      } else {
        .(Factor_Name = "TR01_ADX_Proxy", Raw_Value = NA_real_)
      }
    }, by = Ticker]
    tr01 <- tr01[!is.na(Raw_Value)]
    if (nrow(tr01) > 0L) results[["TR01"]] <- tr01
  }

  # ---- TR02: Trend Consistency (fraction of positive returns in 63d) ----
  tr02 <- rd[!is.na(Ret), {
    if (.N >= 63L) {
      tail63 <- Ret[(.N - 62):.N]
      pct_pos <- mean(tail63 > 0, na.rm = TRUE)
      trend_score <- abs(pct_pos - 0.5) * 2  # 0 = no trend, 1 = perfect trend
      .(Factor_Name = "TR02_Trend_Consistency", Raw_Value = trend_score)
    } else {
      .(Factor_Name = "TR02_Trend_Consistency", Raw_Value = NA_real_)
    }
  }, by = Ticker]
  tr02 <- tr02[!is.na(Raw_Value)]
  if (nrow(tr02) > 0L) results[["TR02"]] <- tr02

  # ---- Combine all ----
  if (length(results) == 0L) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }
  out <- rbindlist(results, use.names = TRUE, fill = TRUE)
  out[, .(Ticker, Factor_Name, Raw_Value)]
}

cat("[factor_db] compute_crowding.R loaded (CR01~CR11, SE01~SE02, TR01~TR02)\n")
