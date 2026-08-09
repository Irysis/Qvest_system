#==============================================================================
# Factor DB — Momentum Factors (M01~M09)
#
# compute_momentum(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL)
#   RAWDATA:    data.table(Date, Ticker, Close, Ret, Vol, Size, Sector, BM_Ret)
#   sig_date:   signal date (Date class)
#   FUND:       not used (signature kept for consistency)
#   CONSENSUS:  not used (signature kept for consistency)
#
# Returns: data.table(Ticker, Factor_Name, Raw_Value)
#
# PIT: All lookbacks use RAWDATA[Date <= sig_date] only. No future data.
#==============================================================================

suppressPackageStartupMessages(library(data.table))

compute_momentum <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {

  sig_date <- as.Date(sig_date)

  # ---- Lookback window: up to sig_date ----
  window <- RAWDATA[Date <= sig_date]
  if (nrow(window) == 0L) return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))

  setorder(window, Ticker, Date)

  # ---- BM daily returns for CAPM ----
  bm_daily <- unique(window[, .(Date, BM_Ret)])
  setorder(bm_daily, Date)

  # ---- Constants ----
  SKIP  <- 21L   # 1-month skip (trading days)
  MIN_OBS <- 60L

  # ==== M01~M04, M05, M06, M08: per-ticker computations ====
  mom_dt <- window[!is.na(Ret) & !is.na(Close), {
    n <- .N
    rets  <- Ret
    dates <- Date
    prices <- Close

    # --- M01: Mom_12_1 (252d lookback, skip last 21d) ---
    m01 <- NA_real_
    if (n > 252L) {
      idx_start <- max(1L, n - 252L + 1L)
      idx_end   <- n - SKIP
      if (idx_end > idx_start) m01 <- prod(1 + rets[idx_start:idx_end]) - 1
    }

    # --- M02: Mom_6_1 (126d lookback, skip last 21d) ---
    m02 <- NA_real_
    if (n > 126L) {
      idx_start <- max(1L, n - 126L + 1L)
      idx_end   <- n - SKIP
      if (idx_end > idx_start) m02 <- prod(1 + rets[idx_start:idx_end]) - 1
    }

    # --- M03: Mom_3_1 (63d lookback, skip last 21d) ---
    m03 <- NA_real_
    if (n > 63L) {
      idx_start <- max(1L, n - 63L + 1L)
      idx_end   <- n - SKIP
      if (idx_end > idx_start) m03 <- prod(1 + rets[idx_start:idx_end]) - 1
    }

    # --- M04: Mom_1 (last 21d, no skip) ---
    m04 <- NA_real_
    if (n > 21L) {
      idx_start <- n - 21L + 1L
      m04 <- prod(1 + rets[idx_start:n]) - 1
    }

    # --- M05: Trended Momentum (log-price 252d slope × 252) ---
    m05 <- NA_real_
    if (n >= MIN_OBS) {
      # Use last 252 days (or all if < 252)
      use_n <- min(252L, n)
      p_tail <- prices[(n - use_n + 1L):n]
      valid  <- !is.na(p_tail) & p_tail > 0
      if (sum(valid) >= MIN_OBS) {
        lp <- log(p_tail[valid])
        sq <- seq_along(lp)
        fit <- .lm.fit(cbind(1, sq), lp)
        m05 <- fit$coefficients[2L] * 252
      }
    }

    # --- M06: High_52w (Close / 52-week high) ---
    m06 <- NA_real_
    if (n >= SKIP) {
      use_n <- min(252L, n)
      hi <- max(prices[(n - use_n + 1L):n], na.rm = TRUE)
      if (hi > 0) m06 <- prices[n] / hi
    }

    # --- M08: Residual Momentum (CAPM residual 252d cumulative, skip 1m) ---
    m08 <- NA_real_
    if (n >= 252L) {
      tk_dt <- data.table(Date = dates, Ret = rets)
      merged <- merge(tk_dt, bm_daily, by = "Date", all.x = TRUE)
      merged <- merged[!is.na(Ret) & !is.na(BM_Ret)]
      nm <- nrow(merged)
      if (nm >= 252L) {
        fit <- .lm.fit(cbind(1, merged$BM_Ret), merged$Ret)
        res <- fit$residuals
        nr  <- length(res)
        idx_end <- nr - SKIP
        idx_start <- max(1L, nr - 252L + 1L)
        if (idx_end > idx_start) {
          m08 <- sum(res[idx_start:idx_end])
        }
      }
    }

    list(M01 = m01, M02 = m02, M03 = m03, M04 = m04,
         M05 = m05, M06 = m06, M08 = m08)
  }, by = Ticker]

  # ==== M07: IndMom (Sector 12-1m momentum) ====
  # Sector-level cumulative return over 12 months, skip last 1 month
  sector_dt <- window[!is.na(Ret) & !is.na(Sector), .(SR = mean(Ret, na.rm = TRUE)),
                      by = .(Date, Sector)]
  setorder(sector_dt, Sector, Date)

  indmom <- sector_dt[, {
    n <- .N
    im <- NA_real_
    if (n > 252L) {
      idx_start <- max(1L, n - 252L + 1L)
      idx_end   <- n - SKIP
      if (idx_end > idx_start) im <- prod(1 + SR[idx_start:idx_end]) - 1
    } else if (n > SKIP + 21L) {
      # shorter history: use all available minus skip
      idx_end <- n - SKIP
      im <- prod(1 + SR[1:idx_end]) - 1
    }
    list(M07 = im)
  }, by = Sector]

  # Map sector IndMom back to tickers
  snap_sector <- RAWDATA[Date == sig_date, .(Ticker, Sector)]
  snap_sector <- merge(snap_sector, indmom, by = "Sector", all.x = TRUE)

  # ==== Merge M07 into mom_dt ====
  mom_dt <- merge(mom_dt, snap_sector[, .(Ticker, M07)], by = "Ticker", all.x = TRUE)

  # ==== M09: Composite Momentum ====
  # mean(z(M01) + z(M02) + z(M05))
  z_safe <- function(x) {
    s <- sd(x, na.rm = TRUE)
    if (is.na(s) || s < 1e-8) return(rep(NA_real_, length(x)))
    (x - mean(x, na.rm = TRUE)) / s
  }

  mom_dt[, z_M01 := fifelse(!is.na(M01), z_safe(M01), NA_real_)]
  mom_dt[, z_M02 := fifelse(!is.na(M02), z_safe(M02), NA_real_)]
  mom_dt[, z_M05 := fifelse(!is.na(M05), z_safe(M05), NA_real_)]

  mom_dt[, n_comp := (!is.na(z_M01)) + (!is.na(z_M02)) + (!is.na(z_M05))]
  mom_dt[n_comp >= 2L, M09 := rowMeans(.SD, na.rm = TRUE),
         .SDcols = c("z_M01", "z_M02", "z_M05")]

  # ==========================================================================
  # M10~M32: Additional Momentum Factors (from extraction report)
  # ==========================================================================

  # ---- M10: Intermediate Momentum (12-7 month, Novy-Marx 2012) ----
  # Cumulative return from t-252 to t-147 (months ~12 to ~7).
  mom_dt2 <- window[!is.na(Ret) & !is.na(Close), {
    n <- .N
    rets <- Ret
    prices <- Close
    dates <- Date

    # --- M10: IntMom (252d to 147d, ~months 12 to 7) ---
    m10 <- NA_real_
    if (n > 252L) {
      idx_start <- max(1L, n - 252L + 1L)
      idx_end   <- n - 147L
      if (idx_end > idx_start) m10 <- prod(1 + rets[idx_start:idx_end]) - 1
    }

    # --- M11: Short-Term Reversal (last 5 trading days) ---
    m11 <- NA_real_
    if (n >= 5L) {
      m11 <- prod(1 + rets[(n - 4L):n]) - 1
    }

    # --- M12: Long-Run Reversal (60m to 13m, ~1260d to 273d) ---
    m12 <- NA_real_
    if (n > 1260L) {
      idx_start <- max(1L, n - 1260L + 1L)
      idx_end   <- n - 273L
      if (idx_end > idx_start) m12 <- prod(1 + rets[idx_start:idx_end]) - 1
    }

    # --- M13: Volatility-Adjusted Momentum (Mom_12_1 / realized vol) ---
    m13 <- NA_real_
    if (n > 252L) {
      idx_s <- max(1L, n - 252L + 1L)
      idx_e <- n - SKIP
      if (idx_e > idx_s) {
        raw_mom <- prod(1 + rets[idx_s:idx_e]) - 1
        rvol <- sd(rets[idx_s:idx_e], na.rm = TRUE) * sqrt(252)
        if (!is.na(rvol) && rvol > 1e-8) m13 <- raw_mom / rvol
      }
    }

    # --- M14: Risk-Adjusted Momentum (Sharpe-like: mean daily ret / sd) ---
    m14 <- NA_real_
    if (n >= 252L) {
      use_n <- min(252L, n)
      r_sub <- rets[(n - use_n + 1L):n]
      mu <- mean(r_sub, na.rm = TRUE)
      sig <- sd(r_sub, na.rm = TRUE)
      if (!is.na(sig) && sig > 1e-8) m14 <- (mu / sig) * sqrt(252)
    }

    # --- M15: Mom_3 (last 63 days, no skip — pure 3-month) ---
    m15 <- NA_real_
    if (n > 63L) {
      m15 <- prod(1 + rets[(n - 63L + 1L):n]) - 1
    }

    # --- M16: Trend Factor (MA cross signals, Han et al. 2016) ---
    # Aggregate signal from MA(3), MA(5), MA(10), MA(20), MA(50), MA(100), MA(200)
    m16 <- NA_real_
    if (n >= 200L) {
      p <- prices[(n - 199L):n]
      ma_lens <- c(3L, 5L, 10L, 20L, 50L, 100L, 200L)
      signal_sum <- 0
      for (ml in ma_lens) {
        ma_val <- mean(p[(201L - ml):200L], na.rm = TRUE)
        signal_sum <- signal_sum + fifelse(p[200L] > ma_val, 1, -1)
      }
      m16 <- signal_sum / length(ma_lens)  # normalized [-1, 1]
    }

    # --- M17: Low_52w (Close / 52-week low — distance from trough) ---
    m17 <- NA_real_
    if (n >= SKIP) {
      use_n <- min(252L, n)
      lo <- min(prices[(n - use_n + 1L):n], na.rm = TRUE)
      if (lo > 0) m17 <- prices[n] / lo
    }

    # --- M18: RSI (14-day Relative Strength Index) ---
    m18 <- NA_real_
    if (n >= 14L) {
      r14 <- rets[(n - 13L):n]
      gains <- pmax(r14, 0)
      losses <- pmax(-r14, 0)
      avg_gain <- mean(gains, na.rm = TRUE)
      avg_loss <- mean(losses, na.rm = TRUE)
      if (avg_loss > 1e-10) {
        rs <- avg_gain / avg_loss
        m18 <- 100 - (100 / (1 + rs))
      } else if (avg_gain > 0) {
        m18 <- 100
      }
    }

    # --- M19: MACD Signal (12-26 EMA diff / 26-day EMA) ---
    m19 <- NA_real_
    if (n >= 26L) {
      p_sub <- prices[(n - 25L):n]
      # Simple exponential moving average approximation
      ema12 <- mean(p_sub[15:26], na.rm = TRUE)  # last 12
      ema26 <- mean(p_sub, na.rm = TRUE)          # last 26
      if (ema26 > 0) m19 <- (ema12 - ema26) / ema26
    }

    # --- M20: Keller Momentum Score (12*r1 + 4*r3 + 2*r6 + r12) ---
    m20 <- NA_real_
    if (n > 252L) {
      r1  <- prices[n] / prices[max(1L, n - 21L)] - 1
      r3  <- prices[n] / prices[max(1L, n - 63L)] - 1
      r6  <- prices[n] / prices[max(1L, n - 126L)] - 1
      r12 <- prices[n] / prices[max(1L, n - 252L)] - 1
      m20 <- 12 * r1 + 4 * r3 + 2 * r6 + r12
    }

    # --- M21: Return Seasonality (MomSeason, Heston-Sadka 2008) ---
    # Average return in the same calendar month over years 2-5
    m21 <- NA_real_
    if (n > 504L) {  # need ~2+ years
      curr_month <- as.integer(format(dates[n], "%m"))
      month_vec  <- as.integer(format(dates, "%m"))
      # Returns in the same calendar month, excluding last 252 days
      same_month_idx <- which(month_vec == curr_month & seq_along(month_vec) <= (n - 252L))
      if (length(same_month_idx) >= 10L) {
        m21 <- mean(rets[same_month_idx], na.rm = TRUE) * 21  # scale to monthly
      }
    }

    # --- M22: Max Return (Bali et al. 2011) ---
    # Maximum single-day return in past month. High max → lower future returns.
    m22 <- NA_real_
    if (n >= 21L) {
      m22 <- max(rets[(n - 20L):n], na.rm = TRUE)
    }

    # --- M23: Acceleration (Mom change — 2nd derivative) ---
    # Mom_6_1(current) - Mom_6_1(63d ago)
    m23 <- NA_real_
    if (n > 252L) {
      # Current 6-1
      mom6_now <- NA_real_
      idx_s <- max(1L, n - 126L + 1L)
      idx_e <- n - SKIP
      if (idx_e > idx_s) mom6_now <- prod(1 + rets[idx_s:idx_e]) - 1
      # 63d ago 6-1
      n2 <- n - 63L
      if (n2 > 126L) {
        idx_s2 <- max(1L, n2 - 126L + 1L)
        idx_e2 <- n2 - SKIP
        if (idx_e2 > idx_s2) {
          mom6_past <- prod(1 + rets[idx_s2:idx_e2]) - 1
          if (!is.na(mom6_now) && !is.na(mom6_past)) m23 <- mom6_now - mom6_past
        }
      }
    }

    list(M10 = m10, M11 = m11, M12 = m12, M13 = m13, M14 = m14,
         M15 = m15, M16 = m16, M17 = m17, M18 = m18, M19 = m19,
         M20 = m20, M21 = m21, M22 = m22, M23 = m23)
  }, by = Ticker]

  # Merge new momentum columns into mom_dt
  mom_dt <- merge(mom_dt, mom_dt2, by = "Ticker", all.x = TRUE)

  # ==== M24: Sector-Relative Momentum ====
  # Mom_12_1 minus sector average Mom_12_1
  sec_snap <- RAWDATA[Date == sig_date, .(Ticker, Sector)]
  mom_dt <- merge(mom_dt, sec_snap, by = "Ticker", all.x = TRUE)
  mom_dt[, sec_avg_m01 := mean(M01, na.rm = TRUE), by = Sector]
  mom_dt[, M24 := fifelse(!is.na(M01) & !is.na(sec_avg_m01), M01 - sec_avg_m01, NA_real_)]

  # ==== M25: Earnings Momentum (SUE streak proxy from CONSENSUS) ====
  # Number of consecutive positive SUE observations (trailing).
  # DATA_NEEDED: CONSENSUS$sue data.table with Date, Ticker, sue
  mom_dt[, M25 := NA_real_]
  if (is.list(CONSENSUS) && "sue" %in% names(CONSENSUS) && is.data.table(CONSENSUS$sue) && nrow(CONSENSUS$sue) > 0L) {
    cs <- copy(CONSENSUS$sue)
    cs[, Date := as.Date(Date)]
    cs <- cs[Date <= sig_date & !is.na(sue)]
    if (nrow(cs) > 0L) {
      setorder(cs, Ticker, -Date)
      sue_streak <- cs[, {
        streak <- 0L
        for (i in seq_len(.N)) {
          if (!is.na(sue[i]) && sue[i] > 0) streak <- streak + 1L else break
        }
        list(sue_streak = as.numeric(streak))
      }, by = Ticker]
      mom_dt <- merge(mom_dt, sue_streak, by = "Ticker", all.x = TRUE)
      mom_dt[, M25 := sue_streak]
      mom_dt[, sue_streak := NULL]
    }
  }

  # ==== M26: Revenue Momentum (consensus revenue change) ====
  # DATA_NEEDED: CONSENSUS$revenue_fy1 data.table with Date, Ticker, revenue_fy1
  mom_dt[, M26 := NA_real_]
  if (is.list(CONSENSUS) && "revenue_fy1" %in% names(CONSENSUS) && is.data.table(CONSENSUS$revenue_fy1) && nrow(CONSENSUS$revenue_fy1) > 0L) {
    cs <- copy(CONSENSUS$revenue_fy1)
    cs[, Date := as.Date(Date)]
    cs <- cs[Date <= sig_date & !is.na(revenue_fy1)]
    if (nrow(cs) > 0L) {
      setorder(cs, Ticker, -Date)
      # Latest vs 63d-ago revenue forecast
      lag_d <- sig_date - 63L
      cs_now <- cs[, .SD[1L], by = Ticker][, .(Ticker, rev_now = revenue_fy1)]
      cs_lag <- cs[Date <= lag_d]
      if (nrow(cs_lag) > 0L) {
        cs_lag <- cs_lag[, .SD[1L], by = Ticker][, .(Ticker, rev_lag = revenue_fy1)]
        rev_chg <- merge(cs_now, cs_lag, by = "Ticker")
        rev_chg[, rev_mom := fifelse(abs(rev_lag) > 1e-6, (rev_now - rev_lag) / abs(rev_lag), NA_real_)]
        mom_dt <- merge(mom_dt, rev_chg[, .(Ticker, M26_val = rev_mom)], by = "Ticker", all.x = TRUE)
        mom_dt[!is.na(M26_val), M26 := M26_val]
        mom_dt[, M26_val := NULL]
      }
    }
  }

  # ==== M27: Analyst Revision Momentum (EPS revision 1m from CONSENSUS) ====
  mom_dt[, M27 := NA_real_]
  if (is.list(CONSENSUS) && "eps_chg_1m" %in% names(CONSENSUS) && is.data.table(CONSENSUS$eps_chg_1m) && nrow(CONSENSUS$eps_chg_1m) > 0L) {
    cs <- copy(CONSENSUS$eps_chg_1m)
    cs[, Date := as.Date(Date)]
    cs <- cs[Date <= sig_date & !is.na(eps_chg_1m)]
    if (nrow(cs) > 0L) {
      setorder(cs, Ticker, -Date)
      cs_latest <- cs[, .SD[1L], by = Ticker]
      mom_dt <- merge(mom_dt, cs_latest[, .(Ticker, M27_val = eps_chg_1m)],
                      by = "Ticker", all.x = TRUE)
      mom_dt[!is.na(M27_val), M27 := M27_val]
      mom_dt[, M27_val := NULL]
    }
  }

  # ==== M28: Operating Profit Revision Momentum ====
  # DATA_NEEDED: CONSENSUS$op_profit_fy1 data.table with Date, Ticker, op_profit_fy1
  mom_dt[, M28 := NA_real_]
  if (is.list(CONSENSUS) && "op_profit_fy1" %in% names(CONSENSUS) && is.data.table(CONSENSUS$op_profit_fy1) && nrow(CONSENSUS$op_profit_fy1) > 0L) {
    cs <- copy(CONSENSUS$op_profit_fy1)
    cs[, Date := as.Date(Date)]
    cs <- cs[Date <= sig_date & !is.na(op_profit_fy1)]
    if (nrow(cs) > 0L) {
      setorder(cs, Ticker, -Date)
      lag_d <- sig_date - 63L
      cs_now <- cs[, .SD[1L], by = Ticker][, .(Ticker, op_now = op_profit_fy1)]
      cs_lag <- cs[Date <= lag_d]
      if (nrow(cs_lag) > 0L) {
        cs_lag <- cs_lag[, .SD[1L], by = Ticker][, .(Ticker, op_lag = op_profit_fy1)]
        op_chg <- merge(cs_now, cs_lag, by = "Ticker")
        op_chg[, op_mom := fifelse(abs(op_lag) > 1e-6, (op_now - op_lag) / abs(op_lag), NA_real_)]
        mom_dt <- merge(mom_dt, op_chg[, .(Ticker, M28_val = op_mom)], by = "Ticker", all.x = TRUE)
        mom_dt[!is.na(M28_val), M28 := M28_val]
        mom_dt[, M28_val := NULL]
      }
    }
  }

  # ==== M29: Price Momentum 5-day ====
  mom_dt[, M29 := NA_real_]
  m29_dt <- window[!is.na(Ret), {
    n <- .N
    val <- NA_real_
    if (n >= 5L) val <- prod(1 + Ret[(n - 4L):n]) - 1
    list(M29 = val)
  }, by = Ticker]
  mom_dt <- merge(mom_dt, m29_dt, by = "Ticker", all.x = TRUE, suffixes = c("", "_m29"))
  if ("M29_m29" %in% names(mom_dt)) {
    mom_dt[is.na(M29) & !is.na(M29_m29), M29 := M29_m29]
    mom_dt[, M29_m29 := NULL]
  }

  # ==== M30: Price Momentum 10-day ====
  mom_dt[, M30 := NA_real_]
  m30_dt <- window[!is.na(Ret), {
    n <- .N
    val <- NA_real_
    if (n >= 10L) val <- prod(1 + Ret[(n - 9L):n]) - 1
    list(M30 = val)
  }, by = Ticker]
  mom_dt <- merge(mom_dt, m30_dt, by = "Ticker", all.x = TRUE, suffixes = c("", "_m30"))
  if ("M30_m30" %in% names(mom_dt)) {
    mom_dt[is.na(M30) & !is.na(M30_m30), M30 := M30_m30]
    mom_dt[, M30_m30 := NULL]
  }

  # ==== M31: Breadth Momentum (fraction of sectors with positive 6m mom) ====
  # Cross-sectional breadth indicator. Not stock-specific — same for all stocks.
  m31_val <- NA_real_
  if (nrow(indmom) > 0L && "M07" %in% names(indmom)) {
    n_pos <- sum(indmom$M07 > 0, na.rm = TRUE)
    n_tot <- sum(!is.na(indmom$M07))
    if (n_tot > 0L) m31_val <- n_pos / n_tot
  }
  mom_dt[, M31 := m31_val]

  # ==== M32: Composite Momentum v2 (5-component) ====
  # mean(z(M01) + z(M10) + z(M13) + z(M24) + z(M25))
  for (mc in c("M10", "M13", "M24", "M25")) {
    zcol <- paste0("z_", mc)
    mom_dt[, (zcol) := fifelse(!is.na(get(mc)), z_safe(get(mc)), NA_real_)]
  }
  mom_dt[, n_comp_v2 := (!is.na(z_M01)) + (!is.na(z_M10)) + (!is.na(z_M13)) +
                          (!is.na(z_M24)) + (!is.na(z_M25))]
  mom_dt[n_comp_v2 >= 3L, M32 := rowMeans(.SD, na.rm = TRUE),
         .SDcols = c("z_M01", "z_M10", "z_M13", "z_M24", "z_M25")]

  # ==== Melt to long format ====
  factor_names <- c("M01_Mom_12_1", "M02_Mom_6_1", "M03_Mom_3_1", "M04_Mom_1",
                    "M05_Trended_Mom", "M06_High_52w", "M07_IndMom",
                    "M08_Residual_Mom", "M09_Composite_Mom",
                    "M10_Intermediate_Mom", "M11_ST_Reversal", "M12_LR_Reversal",
                    "M13_VolAdj_Mom", "M14_RiskAdj_Mom", "M15_Mom_3",
                    "M16_Trend_Factor", "M17_Low_52w", "M18_RSI",
                    "M19_MACD", "M20_Keller_Mom", "M21_Seasonality",
                    "M22_Max_Return", "M23_Acceleration",
                    "M24_Sector_Rel_Mom", "M25_Earnings_Mom_Streak",
                    "M26_Revenue_Mom", "M27_Analyst_Rev_Mom",
                    "M28_OP_Rev_Mom", "M29_Mom_5d", "M30_Mom_10d",
                    "M31_Breadth_Mom", "M32_Composite_Mom_v2")
  factor_cols  <- c("M01", "M02", "M03", "M04", "M05", "M06", "M07", "M08", "M09",
                    "M10", "M11", "M12", "M13", "M14", "M15", "M16", "M17", "M18",
                    "M19", "M20", "M21", "M22", "M23", "M24", "M25", "M26", "M27",
                    "M28", "M29", "M30", "M31", "M32")

  results <- list()
  for (i in seq_along(factor_cols)) {
    col <- factor_cols[i]
    fname <- factor_names[i]
    if (col %in% names(mom_dt)) {
      sub <- mom_dt[!is.na(get(col)) & is.finite(get(col)),
                    .(Ticker, Factor_Name = fname, Raw_Value = get(col))]
      if (nrow(sub) > 0L) results[[fname]] <- sub
    }
  }

  out <- rbindlist(results, use.names = TRUE)
  return(out)
}
