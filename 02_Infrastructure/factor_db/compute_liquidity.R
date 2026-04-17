#==============================================================================
# compute_liquidity.R — Liquidity / Market Micro Factor 계산 모듈 (L01~L45)
#
# 함수: compute_liquidity(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL)
# 반환: data.table(Ticker, Factor_Name, Raw_Value)
#
# PIT 준수: Date <= sig_date, 252d/20d lookback
# RAWDATA 컬럼: Date, Ticker, Ret, Vol, Close, High, Low, Size
#
# L01~L04: Original factors
# L05~L45: New liquidity / market microstructure factors (41 additional)
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
})

compute_liquidity <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {
  sig_d <- as.Date(sig_date)
  results <- list()

  # --- 가격 데이터 준비 (PIT: Date <= sig_date) ---
  rd <- copy(RAWDATA)
  rd[, Date := as.Date(Date)]
  lookback_start <- sig_d - 365  # ~252 trading days
  rd <- rd[Date <= sig_d & Date >= lookback_start]

  if (nrow(rd) == 0) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }

  setkey(rd, Ticker, Date)   # keyed access: rd[.(tk)] is O(log N) vs O(N) scan

  # unique ticker list for lapply-based factors
  tickers <- unique(rd$Ticker)

  # estimated shares per ticker-date (Size = MarketCap, Close = price)
  if (all(c("Size", "Close") %in% names(rd))) {
    rd[, est_shares := fifelse(Close > 0, Size / Close, NA_real_)]
  }

  # --- L01: Amihud = -mean(|Ret| / Vol, 252d) ---
  # Amihud (2002): higher = less liquid → negate so liquid = good
  if (all(c("Ret", "Vol") %in% names(rd))) {
    rd[, amihud_daily := fifelse(Vol > 0, abs(Ret) / Vol, NA_real_)]

    l01 <- rd[!is.na(amihud_daily), .(
      n = .N,
      amihud_mean = mean(amihud_daily, na.rm = TRUE)
    ), by = Ticker]
    l01 <- l01[n >= 120L & !is.na(amihud_mean) & is.finite(amihud_mean)]
    if (nrow(l01) > 0) {
      results[["L01"]] <- l01[, .(Ticker, Factor_Name = "L01_Amihud",
                                  Raw_Value = -amihud_mean)]
    }
  }

  # --- L02: Turnover = mean(Vol / est_shares, 20d) ---
  if (all(c("Vol", "est_shares") %in% names(rd))) {
    # 최근 20 거래일
    recent_20d <- rd[, .(Date = tail(Date, 20)), by = Ticker]
    rd_20 <- rd[recent_20d, on = .(Ticker, Date), nomatch = 0]

    rd_20[, turnover := fifelse(est_shares > 0, Vol / est_shares, NA_real_)]

    l02 <- rd_20[!is.na(turnover), .(
      n = .N,
      mean_turnover = mean(turnover, na.rm = TRUE)
    ), by = Ticker]
    l02 <- l02[n >= 10L & !is.na(mean_turnover)]
    if (nrow(l02) > 0) {
      results[["L02"]] <- l02[, .(Ticker, Factor_Name = "L02_Turnover",
                                  Raw_Value = mean_turnover)]
    }
  }

  # --- L03: Volume Momentum = mean(Vol, 20d) / mean(Vol, 252d) ---
  if ("Vol" %in% names(rd)) {
    vol_stats <- rd[!is.na(Vol) & Vol > 0, {
      n_total <- .N
      dates_sorted <- sort(Date)

      # 전체 기간 (252d) 평균
      vol_252 <- mean(Vol, na.rm = TRUE)

      # 최근 20 거래일 평균
      if (n_total >= 20) {
        recent_idx <- seq(max(1, n_total - 19), n_total)
        vol_20 <- mean(Vol[recent_idx], na.rm = TRUE)
      } else {
        vol_20 <- NA_real_
      }

      list(n = n_total, vol_20 = vol_20, vol_252 = vol_252)
    }, by = Ticker]

    l03 <- vol_stats[n >= 60L & !is.na(vol_20) & !is.na(vol_252) & vol_252 > 0]
    if (nrow(l03) > 0) {
      results[["L03"]] <- l03[, .(Ticker, Factor_Name = "L03_Volume_Mom",
                                  Raw_Value = vol_20 / vol_252)]
    }
  }

  # --- L04: Bid-Ask Proxy — Corwin-Schultz (2012) High-Low Spread ---
  if (all(c("High", "Low") %in% names(rd))) {
    l04 <- .compute_corwin_schultz(rd)
    if (!is.null(l04) && nrow(l04) > 0) results[["L04"]] <- l04
  }

  # =============================================================================
  # NEW LIQUIDITY FACTORS (L05~L45) — 41 additional
  # =============================================================================

  # --- L05: Dollar Volume = mean(Close * Vol, 20d) ---
  # Higher dollar volume = more liquid
  if (all(c("Close", "Vol") %in% names(rd))) {
    rd_20d_dates <- rd[, .(Date = tail(sort(unique(Date)), 20))]
    rd_20d <- rd[Date %in% rd_20d_dates$Date]
    l05 <- rd_20d[!is.na(Close) & !is.na(Vol) & Close > 0 & Vol > 0, .(
      n = .N,
      dv = mean(Close * Vol, na.rm = TRUE)
    ), by = Ticker]
    l05 <- l05[n >= 10L & !is.na(dv)]
    if (nrow(l05) > 0) {
      results[["L05"]] <- l05[, .(Ticker, Factor_Name = "L05_Dollar_Volume",
                                  Raw_Value = log(dv + 1))]  # log scale
    }
  }

  # --- L06: Zero Trading Days (252d) = proportion of days with Vol == 0 ---
  # Liu (2006): more zero days = more illiquid
  if ("Vol" %in% names(rd)) {
    l06 <- rd[, {
      n <- .N
      if (n >= 60L) {
        zero_prop <- sum(is.na(Vol) | Vol == 0, na.rm = TRUE) / n
        list(zero_prop = zero_prop)
      } else list(zero_prop = NA_real_)
    }, by = Ticker]
    l06 <- l06[!is.na(zero_prop)]
    if (nrow(l06) > 0) {
      results[["L06"]] <- l06[, .(Ticker, Factor_Name = "L06_Zero_Trade_Days",
                                  Raw_Value = -zero_prop)]  # fewer zero = more liquid
    }
  }

  # --- L07: Zero Return Days = proportion of |Ret| < 0.001 days ---
  # Lesmond, Ogden, Trzcinka (1999): zero-return days proxy for trading costs
  if ("Ret" %in% names(rd)) {
    l07 <- rd[!is.na(Ret), {
      n <- .N
      if (n >= 60L) {
        zero_ret <- sum(abs(Ret) < 0.001) / n
        list(zero_ret = zero_ret)
      } else list(zero_ret = NA_real_)
    }, by = Ticker]
    l07 <- l07[!is.na(zero_ret)]
    if (nrow(l07) > 0) {
      results[["L07"]] <- l07[, .(Ticker, Factor_Name = "L07_Zero_Return_Days",
                                  Raw_Value = -zero_ret)]
    }
  }

  # --- L08: Roll Spread = 2 * sqrt(-cov(Ret_t, Ret_{t-1})) ---
  # Roll (1984): effective spread estimator from serial covariance.
  # Vectorized by=Ticker (replaces lapply).
  if ("Ret" %in% names(rd)) {
    l08_dt <- rd[!is.na(Ret), {
      n <- .N
      l08 <- NA_real_
      if (n >= 60L) {
        r <- Ret
        # cov(r[-1], r[-n]) via sums: E[r1*r0] - E[r1]*E[r0]
        r1 <- r[-1L]; r0 <- r[-n]
        ok <- !is.na(r1) & !is.na(r0)
        m <- sum(ok)
        if (m >= 30L) {
          serial_cov <- (sum(r1[ok] * r0[ok]) - sum(r1[ok]) * sum(r0[ok]) / m) / (m - 1L)
          l08 <- if (!is.na(serial_cov) && serial_cov < 0) -2 * sqrt(-serial_cov) else 0
        }
      }
      list(L08 = l08)
    }, by = Ticker]
    l08_dt <- l08_dt[!is.na(L08)]
    if (nrow(l08_dt) > 0)
      results[["L08"]] <- l08_dt[, .(Ticker, Factor_Name = "L08_Roll_Spread", Raw_Value = L08)]
  }

  # --- L09: Amihud 20d (short-term) ---
  if (all(c("Ret", "Vol") %in% names(rd))) {
    rd_20d_dates2 <- rd[, .(Date = tail(sort(unique(Date)), 20))]
    rd_20d2 <- rd[Date %in% rd_20d_dates2$Date]
    rd_20d2[, amihud_d := fifelse(Vol > 0, abs(Ret) / Vol, NA_real_)]
    l09 <- rd_20d2[!is.na(amihud_d), .(
      n = .N,
      amihud_20 = mean(amihud_d, na.rm = TRUE)
    ), by = Ticker]
    l09 <- l09[n >= 10L & !is.na(amihud_20) & is.finite(amihud_20)]
    if (nrow(l09) > 0) {
      results[["L09"]] <- l09[, .(Ticker, Factor_Name = "L09_Amihud_20d",
                                  Raw_Value = -amihud_20)]
    }
  }

  # --- L10: Amihud Ratio = Amihud_20d / Amihud_252d ---
  # Liquidity trend: ratio > 1 = deteriorating liquidity
  if (!is.null(results[["L01"]]) && !is.null(results[["L09"]])) {
    a252 <- results[["L01"]][, .(Ticker, a252 = -Raw_Value)]  # un-negate
    a20 <- results[["L09"]][, .(Ticker, a20 = -Raw_Value)]
    ar <- merge(a252, a20, by = "Ticker")
    ar <- ar[a252 > 1e-12]
    if (nrow(ar) > 0) {
      results[["L10"]] <- ar[, .(Ticker, Factor_Name = "L10_Amihud_Ratio",
                                 Raw_Value = -(a20 / a252))]
    }
  }

  # --- L11: Kyle Lambda = |Ret| / sqrt(Vol) per day, averaged ---
  # Kyle (1985) market impact proxy
  if (all(c("Ret", "Vol") %in% names(rd))) {
    l11 <- rd[!is.na(Ret) & !is.na(Vol) & Vol > 0, {
      n <- .N
      if (n >= 60L) {
        kyle <- abs(Ret) / sqrt(Vol)
        list(kyle_lambda = mean(kyle, na.rm = TRUE))
      } else list(kyle_lambda = NA_real_)
    }, by = Ticker]
    l11 <- l11[!is.na(kyle_lambda) & is.finite(kyle_lambda)]
    if (nrow(l11) > 0) {
      results[["L11"]] <- l11[, .(Ticker, Factor_Name = "L11_Kyle_Lambda",
                                  Raw_Value = -kyle_lambda)]
    }
  }

  # --- L12: Pastor-Stambaugh Gamma (liquidity proxy) ---
  # gamma = coef on sign(r_t-1)*Vol_t. Vectorized by=Ticker (replaces lapply).
  if (all(c("Ret", "Vol") %in% names(rd))) {
    l12_dt <- rd[!is.na(Ret) & !is.na(Vol), {
      n <- .N
      l12 <- NA_real_
      if (n >= 60L) {
        r_curr  <- Ret[-1L]
        r_lag   <- Ret[-n]
        sv      <- sign(r_lag) * Vol[-1L]
        ok      <- !is.na(r_curr) & !is.na(r_lag) & !is.na(sv) & is.finite(sv)
        if (sum(ok) >= 40L) {
          fit <- tryCatch(
            lm.fit(cbind(1, r_lag[ok], sv[ok]), r_curr[ok]),
            error = function(e) NULL
          )
          if (!is.null(fit)) {
            g <- fit$coefficients[3L]
            if (!is.na(g)) l12 <- g
          }
        }
      }
      list(L12 = l12)
    }, by = Ticker]
    l12_dt <- l12_dt[!is.na(L12)]
    if (nrow(l12_dt) > 0)
      results[["L12"]] <- l12_dt[, .(Ticker, Factor_Name = "L12_PS_Gamma", Raw_Value = L12)]
  }

  # --- L13: Volume Variance Ratio = var(Vol) / mean(Vol)^2 ---
  # Irregular volume = less liquid
  if ("Vol" %in% names(rd)) {
    l13 <- rd[!is.na(Vol) & Vol > 0, {
      n <- .N
      if (n >= 60L) {
        mv <- mean(Vol, na.rm = TRUE)
        vv <- var(Vol, na.rm = TRUE)
        if (mv > 0) list(vvr = vv / mv^2) else list(vvr = NA_real_)
      } else list(vvr = NA_real_)
    }, by = Ticker]
    l13 <- l13[!is.na(vvr) & is.finite(vvr)]
    if (nrow(l13) > 0) {
      results[["L13"]] <- l13[, .(Ticker, Factor_Name = "L13_Vol_Variance_Ratio",
                                  Raw_Value = -vvr)]
    }
  }

  # --- L14: Price Impact (5-min proxy) = |Ret| / log(1 + Vol) ---
  # Price impact at daily level proxy
  if (all(c("Ret", "Vol") %in% names(rd))) {
    l14 <- rd[!is.na(Ret) & !is.na(Vol) & Vol > 0, {
      n <- .N
      if (n >= 60L) {
        pi_daily <- abs(Ret) / log(1 + Vol)
        list(pi_avg = mean(pi_daily, na.rm = TRUE))
      } else list(pi_avg = NA_real_)
    }, by = Ticker]
    l14 <- l14[!is.na(pi_avg) & is.finite(pi_avg)]
    if (nrow(l14) > 0) {
      results[["L14"]] <- l14[, .(Ticker, Factor_Name = "L14_Price_Impact",
                                  Raw_Value = -pi_avg)]
    }
  }

  # --- L15: Turnover 252d (annual average) ---
  if (all(c("Vol", "est_shares") %in% names(rd))) {
    rd[, turnover_d := fifelse(!is.na(est_shares) & est_shares > 0, Vol / est_shares, NA_real_)]
    l15 <- rd[!is.na(turnover_d), .(
      n = .N,
      mean_to = mean(turnover_d, na.rm = TRUE)
    ), by = Ticker]
    l15 <- l15[n >= 120L & !is.na(mean_to)]
    if (nrow(l15) > 0) {
      results[["L15"]] <- l15[, .(Ticker, Factor_Name = "L15_Turnover_252d",
                                  Raw_Value = mean_to)]
    }
  }

  # --- L16: Turnover Volatility = sd(daily turnover) ---
  if ("turnover_d" %in% names(rd)) {
    l16 <- rd[!is.na(turnover_d), .(
      n = .N,
      sd_to = sd(turnover_d, na.rm = TRUE)
    ), by = Ticker]
    l16 <- l16[n >= 60L & !is.na(sd_to)]
    if (nrow(l16) > 0) {
      results[["L16"]] <- l16[, .(Ticker, Factor_Name = "L16_Turnover_Vol",
                                  Raw_Value = -sd_to)]  # lower vol = steadier liquidity
    }
  }

  # --- L17: LOT Measure (Lesmond-Ogden-Trzcinka) ---
  # Proportion of zero-return days (refined version of L07 with threshold)
  if ("Ret" %in% names(rd)) {
    l17 <- rd[!is.na(Ret), {
      n <- .N
      if (n >= 60L) {
        # LOT: use threshold based on 1% of mean|Ret|
        thresh <- 0.01 * mean(abs(Ret), na.rm = TRUE)
        thresh <- max(thresh, 1e-6)
        lot <- sum(abs(Ret) < thresh) / n
        list(lot = lot)
      } else list(lot = NA_real_)
    }, by = Ticker]
    l17 <- l17[!is.na(lot)]
    if (nrow(l17) > 0) {
      results[["L17"]] <- l17[, .(Ticker, Factor_Name = "L17_LOT_Measure",
                                  Raw_Value = -lot)]
    }
  }

  # --- L18: Effective Spread Proxy = 2 * |Close - (High + Low)/2| / Close ---
  if (all(c("High", "Low", "Close") %in% names(rd))) {
    l18 <- rd[!is.na(High) & !is.na(Low) & !is.na(Close) & Close > 0, {
      n <- .N
      if (n >= 60L) {
        mid <- (High + Low) / 2
        eff_sp <- 2 * abs(Close - mid) / Close
        list(eff_spread = mean(eff_sp, na.rm = TRUE))
      } else list(eff_spread = NA_real_)
    }, by = Ticker]
    l18 <- l18[!is.na(eff_spread)]
    if (nrow(l18) > 0) {
      results[["L18"]] <- l18[, .(Ticker, Factor_Name = "L18_Eff_Spread_Proxy",
                                  Raw_Value = -eff_spread)]
    }
  }

  # --- L19: Price Delay (Hou-Moskowitz 2005) ---
  # 1 - R2_restricted/R2_unrestricted. Vectorized by=Ticker (replaces lapply).
  if (all(c("Ret", "BM_Ret") %in% names(rd))) {
    l19_dt <- rd[!is.na(Ret) & !is.na(BM_Ret), {
      n <- .N
      l19 <- NA_real_
      if (n >= 30L) {
        y  <- Ret[6L:n]
        x0 <- BM_Ret[6L:n]
        fit_r <- tryCatch(lm.fit(cbind(1, x0), y), error = function(e) NULL)
        if (!is.null(fit_r)) {
          ss_tot <- sum((y - mean(y))^2)
          if (ss_tot >= 1e-12) {
            r2_r <- 1 - sum(fit_r$residuals^2) / ss_tot
            X_u  <- cbind(1, x0,
                          BM_Ret[5L:(n-1L)], BM_Ret[4L:(n-2L)],
                          BM_Ret[3L:(n-3L)], BM_Ret[2L:(n-4L)],
                          BM_Ret[1L:(n-5L)])
            fit_u <- tryCatch(lm.fit(X_u, y), error = function(e) NULL)
            if (!is.null(fit_u)) {
              r2_u <- 1 - sum(fit_u$residuals^2) / ss_tot
              if (r2_u >= 1e-8) {
                delay <- max(0, min(1 - r2_r / r2_u, 1))
                l19 <- -delay
              }
            }
          }
        }
      }
      list(L19 = l19)
    }, by = Ticker]
    l19_dt <- l19_dt[!is.na(L19)]
    if (nrow(l19_dt) > 0)
      results[["L19"]] <- l19_dt[, .(Ticker, Factor_Name = "L19_Price_Delay", Raw_Value = L19)]
  }

  # --- L20: Trading Frequency = count of days with Vol > 0 / total days ---
  if ("Vol" %in% names(rd)) {
    l20 <- rd[, {
      n <- .N
      if (n >= 60L) {
        freq <- sum(!is.na(Vol) & Vol > 0) / n
        list(freq = freq)
      } else list(freq = NA_real_)
    }, by = Ticker]
    l20 <- l20[!is.na(freq)]
    if (nrow(l20) > 0) {
      results[["L20"]] <- l20[, .(Ticker, Factor_Name = "L20_Trade_Frequency",
                                  Raw_Value = freq)]
    }
  }

  # --- L21: Market Depth Proxy = mean(Vol) / sd(Ret) ---
  # High volume relative to volatility = deep market
  if (all(c("Vol", "Ret") %in% names(rd))) {
    l21 <- rd[!is.na(Vol) & !is.na(Ret), {
      n <- .N
      if (n >= 60L) {
        mv <- mean(Vol, na.rm = TRUE)
        sr <- sd(Ret, na.rm = TRUE)
        if (sr > 1e-8) list(depth = log(mv / sr + 1)) else list(depth = NA_real_)
      } else list(depth = NA_real_)
    }, by = Ticker]
    l21 <- l21[!is.na(depth) & is.finite(depth)]
    if (nrow(l21) > 0) {
      results[["L21"]] <- l21[, .(Ticker, Factor_Name = "L21_Market_Depth",
                                  Raw_Value = depth)]
    }
  }

  # --- L22: Return Autocorrelation (lag-1) + L23: Volume Autocorrelation ---
  # Single by=Ticker pass for both (replaces 2 separate lapply loops).
  if ("Ret" %in% names(rd)) {
    l22_dt <- rd[!is.na(Ret), {
      n <- .N
      l22 <- NA_real_
      if (n >= 60L) {
        r1 <- Ret[-1L]; r0 <- Ret[-n]
        ok <- !is.na(r1) & !is.na(r0); m <- sum(ok)
        if (m >= 30L) {
          cov_val <- (sum(r1[ok] * r0[ok]) - sum(r1[ok]) * sum(r0[ok]) / m) / (m - 1L)
          sd1 <- sd(r1[ok]); sd0 <- sd(r0[ok])
          if (!is.na(sd1) && !is.na(sd0) && sd1 > 1e-12 && sd0 > 1e-12) {
            ac1 <- cov_val / (sd1 * sd0)
            l22 <- -abs(ac1)
          }
        }
      }
      list(L22 = l22)
    }, by = Ticker]
    l22_dt <- l22_dt[!is.na(L22)]
    if (nrow(l22_dt) > 0)
      results[["L22"]] <- l22_dt[, .(Ticker, Factor_Name = "L22_Ret_Autocorr", Raw_Value = L22)]
  }

  if ("Vol" %in% names(rd)) {
    l23_dt <- rd[!is.na(Vol) & Vol > 0, {
      n <- .N
      l23 <- NA_real_
      if (n >= 60L) {
        v <- log(Vol + 1)
        v1 <- v[-1L]; v0 <- v[-n]
        ok <- !is.na(v1) & !is.na(v0); m <- sum(ok)
        if (m >= 30L) {
          cov_val <- (sum(v1[ok] * v0[ok]) - sum(v1[ok]) * sum(v0[ok]) / m) / (m - 1L)
          sd1 <- sd(v1[ok]); sd0 <- sd(v0[ok])
          if (!is.na(sd1) && !is.na(sd0) && sd1 > 1e-12 && sd0 > 1e-12) {
            l23 <- cov_val / (sd1 * sd0)
          }
        }
      }
      list(L23 = l23)
    }, by = Ticker]
    l23_dt <- l23_dt[!is.na(L23)]
    if (nrow(l23_dt) > 0)
      results[["L23"]] <- l23_dt[, .(Ticker, Factor_Name = "L23_Vol_Autocorr", Raw_Value = L23)]
  }

  # --- L24: Intraday Range / Volume = (H-L) / Vol ---
  # Higher = more price impact per unit volume = less liquid
  if (all(c("High", "Low", "Vol") %in% names(rd))) {
    l24 <- rd[!is.na(High) & !is.na(Low) & !is.na(Vol) & Vol > 0, {
      n <- .N
      if (n >= 60L) {
        rv <- (High - Low) / Vol
        list(rv_avg = mean(rv, na.rm = TRUE))
      } else list(rv_avg = NA_real_)
    }, by = Ticker]
    l24 <- l24[!is.na(rv_avg) & is.finite(rv_avg)]
    if (nrow(l24) > 0) {
      results[["L24"]] <- l24[, .(Ticker, Factor_Name = "L24_Range_per_Vol",
                                  Raw_Value = -rv_avg)]
    }
  }

  # --- L25: Amihud Volatility = sd(daily Amihud) ---
  if ("amihud_daily" %in% names(rd)) {
    l25 <- rd[!is.na(amihud_daily) & is.finite(amihud_daily), .(
      n = .N,
      sd_amihud = sd(amihud_daily, na.rm = TRUE)
    ), by = Ticker]
    l25 <- l25[n >= 60L & !is.na(sd_amihud)]
    if (nrow(l25) > 0) {
      results[["L25"]] <- l25[, .(Ticker, Factor_Name = "L25_Amihud_Vol",
                                  Raw_Value = -sd_amihud)]
    }
  }

  # --- L26: Log Market Cap (size as liquidity proxy) ---
  if ("Size" %in% names(rd)) {
    snap_liq <- rd[Date == max(Date), .(Ticker, Size)]
    snap_liq <- snap_liq[!is.na(Size) & Size > 0]
    if (nrow(snap_liq) > 0) {
      results[["L26"]] <- snap_liq[, .(Ticker, Factor_Name = "L26_Log_MktCap",
                                       Raw_Value = log(Size))]
    }
  }

  # --- L27: Price Level (higher price = more liquid generally) ---
  if ("Close" %in% names(rd)) {
    snap_close <- rd[Date == max(Date) & !is.na(Close) & Close > 0, .(Ticker, Close)]
    if (nrow(snap_close) > 0) {
      results[["L27"]] <- snap_close[, .(Ticker, Factor_Name = "L27_Price_Level",
                                         Raw_Value = log(Close))]
    }
  }

  # --- L28: Volume Momentum Ratio (63d) = mean(Vol,20d) / mean(Vol,63d) ---
  if ("Vol" %in% names(rd)) {
    l28 <- rd[!is.na(Vol) & Vol > 0, {
      n <- .N
      if (n >= 63L) {
        v20 <- mean(Vol[seq(max(1, n - 19), n)], na.rm = TRUE)
        v63 <- mean(Vol[seq(max(1, n - 62), n)], na.rm = TRUE)
        if (v63 > 0) list(vmr = v20 / v63) else list(vmr = NA_real_)
      } else list(vmr = NA_real_)
    }, by = Ticker]
    l28 <- l28[!is.na(vmr)]
    if (nrow(l28) > 0) {
      results[["L28"]] <- l28[, .(Ticker, Factor_Name = "L28_Vol_Mom_63d",
                                  Raw_Value = vmr)]
    }
  }

  # --- L29: Illiquidity Change = Amihud_63d / Amihud_252d ---
  if (all(c("Ret", "Vol") %in% names(rd))) {
    rd_63 <- rd[Date >= (sig_d - 95)]
    a63 <- rd_63[!is.na(Ret) & !is.na(Vol) & Vol > 0, .(
      n = .N,
      amihud_63 = mean(abs(Ret) / Vol, na.rm = TRUE)
    ), by = Ticker]
    a63 <- a63[n >= 40L & !is.na(amihud_63) & is.finite(amihud_63)]

    a252 <- rd[!is.na(Ret) & !is.na(Vol) & Vol > 0, .(
      n = .N,
      amihud_252 = mean(abs(Ret) / Vol, na.rm = TRUE)
    ), by = Ticker]
    a252 <- a252[n >= 120L & !is.na(amihud_252) & is.finite(amihud_252)]

    if (nrow(a63) > 0 && nrow(a252) > 0) {
      ic <- merge(a63[, .(Ticker, a63 = amihud_63)],
                  a252[, .(Ticker, a252 = amihud_252)], by = "Ticker")
      ic <- ic[a252 > 1e-12]
      if (nrow(ic) > 0) {
        results[["L29"]] <- ic[, .(Ticker, Factor_Name = "L29_Illiq_Change",
                                   Raw_Value = -(a63 / a252))]
      }
    }
  }

  # --- L30: Bid-Ask Proxy Corwin-Schultz (20d, short-term) ---
  if (all(c("High", "Low") %in% names(rd))) {
    rd_cs20 <- rd[Date >= (sig_d - 35)]
    l30 <- .compute_corwin_schultz(rd_cs20)
    if (!is.null(l30) && nrow(l30) > 0) {
      l30[, Factor_Name := "L30_CS_Spread_20d"]
      results[["L30"]] <- l30
    }
  }

  # --- L31: Volume Concentration (Herfindahl of daily vol shares) ---
  # Concentrated volume across few days = less continuously liquid
  if ("Vol" %in% names(rd)) {
    l31 <- rd[!is.na(Vol) & Vol > 0, {
      n <- .N
      if (n >= 60L) {
        total_vol <- sum(Vol, na.rm = TRUE)
        if (total_vol > 0) {
          shares <- Vol / total_vol
          hhi <- sum(shares^2)
          list(hhi = hhi)
        } else list(hhi = NA_real_)
      } else list(hhi = NA_real_)
    }, by = Ticker]
    l31 <- l31[!is.na(hhi)]
    if (nrow(l31) > 0) {
      # Low HHI = evenly distributed volume = more liquid
      results[["L31"]] <- l31[, .(Ticker, Factor_Name = "L31_Vol_Concentration",
                                  Raw_Value = -hhi)]
    }
  }

  # --- L32: Return-Volume Correlation + L33: |Ret|-Volume Correlation ---
  # Single by=Ticker pass for both (replaces 2 separate lapply loops).
  if (all(c("Ret", "Vol") %in% names(rd))) {
    l3233_dt <- rd[!is.na(Ret) & !is.na(Vol) & Vol > 0, {
      n <- .N
      l32 <- l33 <- NA_real_
      if (n >= 60L) {
        lv <- log(Vol + 1)
        ok <- !is.na(Ret) & !is.na(lv); m <- sum(ok)
        if (m >= 30L) {
          r_ok  <- Ret[ok]; ar_ok <- abs(Ret[ok]); lv_ok <- lv[ok]
          # correlation via cov/sd formula
          .corr <- function(a, b) {
            ma <- mean(a); mb <- mean(b)
            cov_ab <- mean((a - ma) * (b - mb))
            sd_a <- sqrt(mean((a - ma)^2)); sd_b <- sqrt(mean((b - mb)^2))
            if (sd_a > 1e-12 && sd_b > 1e-12) cov_ab / (sd_a * sd_b) else NA_real_
          }
          l32 <- .corr(r_ok, lv_ok)
          l33 <- .corr(ar_ok, lv_ok)
        }
      }
      list(L32 = l32, L33 = l33)
    }, by = Ticker]
    l32_sub <- l3233_dt[!is.na(L32)]
    if (nrow(l32_sub) > 0)
      results[["L32"]] <- l32_sub[, .(Ticker, Factor_Name = "L32_Ret_Vol_Corr",   Raw_Value = L32)]
    l33_sub <- l3233_dt[!is.na(L33)]
    if (nrow(l33_sub) > 0)
      results[["L33"]] <- l33_sub[, .(Ticker, Factor_Name = "L33_AbsRet_Vol_Corr", Raw_Value = L33)]
  }

  # --- L34: Max Volume / Mean Volume (volume spike ratio) ---
  if ("Vol" %in% names(rd)) {
    l34 <- rd[!is.na(Vol) & Vol > 0, {
      n <- .N
      if (n >= 60L) {
        mv <- mean(Vol, na.rm = TRUE)
        if (mv > 0) list(spike = max(Vol, na.rm = TRUE) / mv)
        else list(spike = NA_real_)
      } else list(spike = NA_real_)
    }, by = Ticker]
    l34 <- l34[!is.na(spike) & is.finite(spike)]
    if (nrow(l34) > 0) {
      results[["L34"]] <- l34[, .(Ticker, Factor_Name = "L34_Vol_Spike_Ratio",
                                  Raw_Value = -spike)]
    }
  }

  # --- L35: Reversal Intensity = mean(|Ret| on reversal days) ---
  # Vectorized by=Ticker (replaces lapply).
  if ("Ret" %in% names(rd)) {
    l35_dt <- rd[!is.na(Ret), {
      n <- .N
      l35 <- NA_real_
      if (n >= 60L) {
        r   <- Ret
        rev <- sign(r[-1L]) != sign(r[-n])
        # NA signs treated as non-reversal
        rev[is.na(rev)] <- FALSE
        n_rev <- sum(rev)
        if (n_rev >= 10L) {
          l35 <- -mean(abs(r[-1L][rev]), na.rm = TRUE)
        }
      }
      list(L35 = l35)
    }, by = Ticker]
    l35_dt <- l35_dt[!is.na(L35)]
    if (nrow(l35_dt) > 0)
      results[["L35"]] <- l35_dt[, .(Ticker, Factor_Name = "L35_Reversal_Intensity", Raw_Value = L35)]
  }

  # --- L36: Close Location Value = (Close - Low) / (High - Low) ---
  # Measures where close falls in daily range (closer to mid = more balanced flow)
  if (all(c("High", "Low", "Close") %in% names(rd))) {
    l36 <- rd[!is.na(High) & !is.na(Low) & !is.na(Close) &
                (High - Low) > 0, {
      n <- .N
      if (n >= 60L) {
        clv <- (Close - Low) / (High - Low)
        list(clv_sd = sd(clv, na.rm = TRUE))  # Lower variability = more stable = liquid
      } else list(clv_sd = NA_real_)
    }, by = Ticker]
    l36 <- l36[!is.na(clv_sd)]
    if (nrow(l36) > 0) {
      results[["L36"]] <- l36[, .(Ticker, Factor_Name = "L36_CLV_Stability",
                                  Raw_Value = -clv_sd)]
    }
  }

  # --- L37: Relative Volume (vs sector/cross-section median) ---
  if ("Vol" %in% names(rd)) {
    # Cross-sectional median volume on most recent date
    last_date <- max(rd$Date, na.rm = TRUE)
    cs_vol <- rd[Date == last_date & !is.na(Vol) & Vol > 0, .(Ticker, Vol)]
    med_vol <- median(cs_vol$Vol, na.rm = TRUE)
    if (!is.na(med_vol) && med_vol > 0) {
      l37 <- cs_vol[, .(Ticker, Factor_Name = "L37_Relative_Vol",
                         Raw_Value = log(Vol / med_vol + 1))]
      if (nrow(l37) > 0) results[["L37"]] <- l37
    }
  }

  # --- L38: Dollar Volume Momentum = DolVol_20d / DolVol_252d ---
  if (all(c("Close", "Vol") %in% names(rd))) {
    l38 <- rd[!is.na(Close) & !is.na(Vol) & Close > 0 & Vol > 0, {
      n <- .N
      if (n >= 60L) {
        dv <- Close * Vol
        dv_20 <- mean(tail(dv, 20), na.rm = TRUE)
        dv_252 <- mean(dv, na.rm = TRUE)
        if (dv_252 > 0) list(dvm = dv_20 / dv_252) else list(dvm = NA_real_)
      } else list(dvm = NA_real_)
    }, by = Ticker]
    l38 <- l38[!is.na(dvm) & is.finite(dvm)]
    if (nrow(l38) > 0) {
      results[["L38"]] <- l38[, .(Ticker, Factor_Name = "L38_DolVol_Mom",
                                  Raw_Value = dvm)]
    }
  }

  # --- L39: Overnight Spread Proxy = |Open_t / Close_{t-1} - 1| averaged ---
  # Vectorized by=Ticker (replaces lapply).
  if (all(c("Open", "Close") %in% names(rd))) {
    l39_dt <- rd[!is.na(Open) & !is.na(Close) & Close > 0 & Open > 0, {
      n <- .N
      l39 <- NA_real_
      if (n >= 60L) {
        gap <- abs(Open[-1L] / Close[-n] - 1)
        gap <- gap[!is.na(gap) & is.finite(gap)]
        if (length(gap) >= 30L) l39 <- -mean(gap)
      }
      list(L39 = l39)
    }, by = Ticker]
    l39_dt <- l39_dt[!is.na(L39)]
    if (nrow(l39_dt) > 0)
      results[["L39"]] <- l39_dt[, .(Ticker, Factor_Name = "L39_Overnight_Spread", Raw_Value = L39)]
  }

  # --- L40: Volume-Weighted Price Spread = mean(|Ret|*Vol) / mean(Vol) ---
  # Volume-weighted average absolute price change
  if (all(c("Ret", "Vol") %in% names(rd))) {
    l40 <- rd[!is.na(Ret) & !is.na(Vol) & Vol > 0, {
      n <- .N
      if (n >= 60L) {
        vwap_spread <- sum(abs(Ret) * Vol, na.rm = TRUE) / sum(Vol, na.rm = TRUE)
        list(vwas = vwap_spread)
      } else list(vwas = NA_real_)
    }, by = Ticker]
    l40 <- l40[!is.na(vwas) & is.finite(vwas)]
    if (nrow(l40) > 0) {
      results[["L40"]] <- l40[, .(Ticker, Factor_Name = "L40_VWAP_Spread",
                                  Raw_Value = -vwas)]
    }
  }

  # --- L41: Intraday Volatility Proxy = mean((High-Low)/Open) ---
  if (all(c("High", "Low", "Open") %in% names(rd))) {
    l41 <- rd[!is.na(High) & !is.na(Low) & !is.na(Open) & Open > 0, {
      n <- .N
      if (n >= 60L) {
        intraday <- (High - Low) / Open
        list(iv = mean(intraday, na.rm = TRUE))
      } else list(iv = NA_real_)
    }, by = Ticker]
    l41 <- l41[!is.na(iv)]
    if (nrow(l41) > 0) {
      # Lower intraday range relative to open = calmer market = liquid
      results[["L41"]] <- l41[, .(Ticker, Factor_Name = "L41_Intraday_Vol_Proxy",
                                  Raw_Value = -iv)]
    }
  }

  # --- L42: Volume Skewness ---
  if ("Vol" %in% names(rd)) {
    l42 <- rd[!is.na(Vol) & Vol > 0, {
      n <- .N
      if (n >= 60L) {
        lv <- log(Vol + 1)
        m <- mean(lv, na.rm = TRUE)
        s <- sd(lv, na.rm = TRUE)
        if (s > 1e-8) list(vskew = mean(((lv - m) / s)^3, na.rm = TRUE))
        else list(vskew = NA_real_)
      } else list(vskew = NA_real_)
    }, by = Ticker]
    l42 <- l42[!is.na(vskew)]
    if (nrow(l42) > 0) {
      # Negative skew = occasional very low volume days = illiquid episodes
      results[["L42"]] <- l42[, .(Ticker, Factor_Name = "L42_Vol_Skewness",
                                  Raw_Value = vskew)]
    }
  }

  # --- L43: Turnover Change (20d vs 60d) ---
  if (all(c("Vol", "est_shares") %in% names(rd))) {
    l43 <- rd[!is.na(Vol) & !is.na(est_shares) & est_shares > 0, {
      n <- .N
      if (n >= 63L) {
        to <- Vol / est_shares
        to_20 <- mean(tail(to, 20), na.rm = TRUE)
        to_60 <- mean(tail(to, 60), na.rm = TRUE)
        if (to_60 > 1e-12) list(to_chg = to_20 / to_60)
        else list(to_chg = NA_real_)
      } else list(to_chg = NA_real_)
    }, by = Ticker]
    l43 <- l43[!is.na(to_chg) & is.finite(to_chg)]
    if (nrow(l43) > 0) {
      results[["L43"]] <- l43[, .(Ticker, Factor_Name = "L43_Turnover_Change",
                                  Raw_Value = to_chg)]
    }
  }

  # --- L44: Volume-Return Asymmetry ---
  # Difference in average volume on up vs down days
  if (all(c("Ret", "Vol") %in% names(rd))) {
    l44 <- rd[!is.na(Ret) & !is.na(Vol) & Vol > 0, {
      n <- .N
      if (n >= 60L) {
        up_vol <- mean(Vol[Ret > 0], na.rm = TRUE)
        dn_vol <- mean(Vol[Ret < 0], na.rm = TRUE)
        if (!is.na(up_vol) && !is.na(dn_vol) && (up_vol + dn_vol) > 0) {
          list(va = (up_vol - dn_vol) / (up_vol + dn_vol))
        } else list(va = NA_real_)
      } else list(va = NA_real_)
    }, by = Ticker]
    l44 <- l44[!is.na(va)]
    if (nrow(l44) > 0) {
      results[["L44"]] <- l44[, .(Ticker, Factor_Name = "L44_Vol_Ret_Asymmetry",
                                  Raw_Value = va)]
    }
  }

  # --- L45: Composite Liquidity Score = mean(z(L01), z(L02), z(L04), z(L05)) ---
  liq_keys <- c("L01", "L02", "L04", "L05")
  liq_avail <- intersect(liq_keys, names(results))
  if (length(liq_avail) >= 2) {
    liq_parts <- rbindlist(results[liq_avail], use.names = TRUE)
    if (nrow(liq_parts) > 0) {
      liq_parts[, z_val := {
        m <- mean(Raw_Value, na.rm = TRUE)
        s <- sd(Raw_Value, na.rm = TRUE)
        if (is.na(s) || s < 1e-8) NA_real_ else (Raw_Value - m) / s
      }, by = Factor_Name]
      liq_comp <- liq_parts[!is.na(z_val), .(z_mean = mean(z_val, na.rm = TRUE)), by = Ticker]
      liq_comp <- liq_comp[!is.na(z_mean)]
      if (nrow(liq_comp) > 0) {
        results[["L45"]] <- liq_comp[, .(Ticker, Factor_Name = "L45_Composite_Liquidity",
                                         Raw_Value = z_mean)]
      }
    }
  }

  # 결합
  if (length(results) == 0) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }
  out <- rbindlist(results, use.names = TRUE, fill = TRUE)
  out[, .(Ticker, Factor_Name, Raw_Value)]
}

# =============================================================================
# Internal: Corwin-Schultz (2012) High-Low Spread Estimator
# =============================================================================
.compute_corwin_schultz <- function(rd) {
  # Corwin & Schultz (2012): S = 2(e^alpha - 1) / (1 + e^alpha)
  # where alpha = (sqrt(2*beta) - sqrt(beta)) / (3 - 2*sqrt(2)) - sqrt(gamma / (3 - 2*sqrt(2)))
  # beta = E[sum of squared log(H/L) over 2 consecutive days]
  # gamma = [log(H2d/L2d)]^2 (2-day high-low range)

  MIN_OBS <- 60L

  rd_hl <- rd[!is.na(High) & !is.na(Low) & High > 0 & Low > 0]
  if (nrow(rd_hl) == 0) return(NULL)

  setorder(rd_hl, Ticker, Date)

  # Per ticker: compute daily log(H/L), then rolling pairs
  cs_results <- rd_hl[, {
    n <- .N
    if (n < MIN_OBS) {
      NULL
    } else {
      h <- High
      l <- Low
      log_hl <- log(h / l)
      log_hl_sq <- log_hl^2

      # beta_j = log(H_j/L_j)^2 + log(H_{j+1}/L_{j+1})^2
      # gamma_j = log(max(H_j,H_{j+1}) / min(L_j,L_{j+1}))^2
      n_pairs <- n - 1L
      if (n_pairs < MIN_OBS) {
        NULL
      } else {
        beta_vec <- log_hl_sq[1:n_pairs] + log_hl_sq[2:n]

        h2d <- pmax(h[1:n_pairs], h[2:n])
        l2d <- pmin(l[1:n_pairs], l[2:n])
        gamma_vec <- (log(h2d / l2d))^2

        # Mean beta and gamma
        beta_mean <- mean(beta_vec, na.rm = TRUE)
        gamma_mean <- mean(gamma_vec, na.rm = TRUE)

        # alpha calculation
        k <- sqrt(2.0) - 1.0  # 3 - 2*sqrt(2) denominator factor
        denom <- 3.0 - 2.0 * sqrt(2.0)

        term1 <- (sqrt(2.0 * beta_mean) - sqrt(beta_mean)) / denom
        term2 <- sqrt(gamma_mean / denom)

        alpha <- term1 - term2

        # Spread: S = 2(e^alpha - 1)/(1 + e^alpha)
        # Clamp alpha to avoid extreme values
        alpha <- max(alpha, -2)
        alpha <- min(alpha, 2)
        spread <- 2.0 * (exp(alpha) - 1.0) / (1.0 + exp(alpha))
        spread <- max(spread, 0)  # spread cannot be negative

        list(Factor_Name = "L04_Bid_Ask_Proxy", Raw_Value = -spread)
      }
    }
  }, by = Ticker]

  if (is.null(cs_results) || nrow(cs_results) == 0) return(NULL)
  cs_results[, .(Ticker, Factor_Name, Raw_Value)]
}

cat("[factor_db] compute_liquidity.R loaded (L01~L45: 4 original + 41 new)\n")
