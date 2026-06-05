#==============================================================================
# DM-TC Factor Engine — Distributional Market State × Stock-level Tail Co-movement
# WT-D20260527_001 Alpha Research v1.0
#
# Mechanism:
#   1) Market state S_t derived from P3/P4 forecasts (forward-looking but PIT-clean
#      since predictions made at t-1 close, used for t+1 sig_date allocation).
#   2) Stock-level tail sensitivity (z_tail) computed from rolling 252d daily
#      returns vs KOSPI200, using:
#        - tail_beta (van Oordt-Zhou 2016)
#        - downside_beta (Ang-Chen-Xing 2006)
#        - LTD proxy (lower-tail dependence quantile-quantile co-exceedance count)
#   3) Cross-section alpha = S_t * (-1) * z_composite_tail
#      (bear S_t = +1 → favor LOW tail-sensitive stocks)
#
# PIT discipline:
#   - All rolling windows END at sig_date - 1 trading day
#   - P3/P4 forecast at sig_date - 1 (made BEFORE rebalance)
#   - LIQ filter via 20d avg trading value at sig_date - 1
#
# Author: Alpha Research Agent
# Date: 2026-05-27
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

# ---- Constants ----
LIQ_THRESHOLD <- 2e8           # 20d avg TV >= 2e8 KRW
TAIL_WINDOW <- 252L            # 1y daily for tail beta
DAILY_VAR_5 <- 0.05            # 5% market VaR threshold for tail-state estimate
DOWNSIDE_THRESHOLD <- 0.0      # downside beta uses r_mkt < 0
LTD_QTILE <- 0.10              # 10% co-exceedance quantile

# Hansen Skewed-t Density (P3 1d) → 21d horizon transformation
# Use P4 directly (21d ECDF + ACI VaR5 calibrated, OOS extended)
P3_PATH <- "04_Research/decision_framework/bearish_forecast_v3/03_models/p3_trial19/all_predictions.parquet"
P4_PATH <- "04_Research/decision_framework/bearish_forecast_v3/03_models/p4_ecdf_final/all_predictions_extended.parquet"

#==============================================================================
# 1) Load market distribution forecasts
#==============================================================================

load_p4_forecasts <- function() {
  p4 <- as.data.table(read_parquet(P4_PATH))
  p4[, Date := as.Date(Date)]
  setkey(p4, Date)
  # Keep only useful cols
  p4[, .(Date, mu_p4 = mu, sigma_p4 = sigma, lam_p4 = lam, nu_p4 = nu,
         var_05_p4 = var_05, es_05_p4 = es_05,
         p_m5_p4 = p_minus_5pct, p_m7_p4 = p_minus_7pct, p_m10_p4 = p_minus_10pct)]
}

load_p3_forecasts <- function() {
  p3 <- as.data.table(read_parquet(P3_PATH))
  p3[, Date := as.Date(Date)]
  setkey(p3, Date)
  p3[, .(Date, mu_p3 = mu, sigma_p3 = sigma, lam_p3 = lam, nu_p3 = nu,
         var_05_p3 = var_05, es_05_p3 = es_05,
         p_m5_p3 = p_minus_5pct, p_m7_p3 = p_minus_7pct, p_m10_p3 = p_minus_10pct)]
}

#==============================================================================
# 2) Market state intensity (continuous, PIT-safe expanding window)
#==============================================================================
# S_t ∈ [-1, +1]:
#   - Use expanding rank percentile of p_m5_p4 vs full history up to t-1
#   - S_t = 2 * pctile(p_m5_p4_t) - 1
#   - +1 (high p_m5_p4) → strong bear / risk-off
#   - -1 (low p_m5_p4) → strong bull / risk-on
#   - 0 → neutral
#
# Optional skew-aware adjustment: when lam < -0.30 (heavy left skew),
# bump S_t upward by 0.10 (additional risk-off tilt).
#
# Quantile uses PIT-safe expanding window: only data up to t-1 included.

classify_market_state <- function(p4_dt, p3_dt = NULL, min_history = 252L,
                                  use_lam_adjust = TRUE) {
  setkey(p4_dt, Date)
  n <- nrow(p4_dt)
  p4_dt[, pctile_pm5 := NA_real_]

  if (n > min_history) {
    # Vectorized expanding rank: O(N^2) is fine since N ≈ 2500.
    hist_vec <- p4_dt$p_m5_p4
    for (i in (min_history + 1L):n) {
      hist <- hist_vec[1:(i - 1L)]
      hist <- hist[!is.na(hist)]
      if (length(hist) >= min_history) {
        # Empirical CDF at p_m5_p4[i] vs history (PIT-safe)
        val <- hist_vec[i]
        if (!is.na(val)) {
          p4_dt[i, pctile_pm5 := mean(hist < val, na.rm = TRUE)]
        }
      }
    }
  }

  # Map pctile [0, 1] to S_t [-1, +1]
  p4_dt[, state_raw := 2 * pctile_pm5 - 1]

  # Skew bump: lam < -0.30 (heavy left skew) → +0.10 to S_t (more risk-off)
  if (use_lam_adjust) {
    p4_dt[, state := pmin(pmax(state_raw + 0.10 * (lam_p4 < -0.30), -1), 1)]
  } else {
    p4_dt[, state := state_raw]
  }
  p4_dt
}

#==============================================================================
# 3) Stock-level tail sensitivity (rolling 252d)
#==============================================================================
# Inputs:
#   - returns_dt: data.table with Date, Ticker, Ret (long format)
#   - bm_dt: data.table with Date, BM_Ret
#   - sig_date: rebalance date (use t-1 cutoff)
# Output:
#   - data.table[ticker, tail_beta, downside_beta, ltd_proxy]
#
# Uses rolling window of TAIL_WINDOW = 252 daily trading days ending at sig_date.

compute_tail_sensitivity <- function(returns_dt, bm_dt, sig_date,
                                     window = TAIL_WINDOW,
                                     min_obs = 200L) {
  cutoff <- as.Date(sig_date) - 1L
  start_date <- cutoff - window * 1.5  # buffer for non-trading days

  R <- returns_dt[Date >= start_date & Date <= cutoff &
                  !is.na(Ret) & is.finite(Ret), .(Date, Ticker, Ret)]
  B <- bm_dt[Date >= start_date & Date <= cutoff &
             !is.na(BM_Ret) & is.finite(BM_Ret), .(Date, BM_Ret)]
  if (nrow(R) == 0 || nrow(B) == 0) return(data.table(Ticker = character(0)))

  # Merge
  R[, Date := as.Date(Date)]
  B[, Date := as.Date(Date)]
  setkey(R, Ticker, Date); setkey(B, Date)
  rb <- B[R, on = "Date", nomatch = NULL]
  if (nrow(rb) == 0) return(data.table(Ticker = character(0)))

  # Compute VaR_5 / VaR_10 of market over window
  bm_var5 <- quantile(B$BM_Ret, 0.05, na.rm = TRUE, names = FALSE)
  bm_q10 <- quantile(B$BM_Ret, 0.10, na.rm = TRUE, names = FALSE)

  # Per-ticker stats
  rb[, .(
    n_obs = .N,
    # tail beta (van Oordt-Zhou): cov / var over r_mkt < VaR_5%
    tail_beta = {
      tail_idx <- BM_Ret < bm_var5
      if (sum(tail_idx) >= 10) {
        cov(Ret[tail_idx], BM_Ret[tail_idx]) /
          var(BM_Ret[tail_idx])
      } else NA_real_
    },
    # downside beta (Ang-Chen-Xing): cov / var over r_mkt < 0
    downside_beta = {
      dn_idx <- BM_Ret < DOWNSIDE_THRESHOLD
      if (sum(dn_idx) >= 30) {
        cov(Ret[dn_idx], BM_Ret[dn_idx]) /
          var(BM_Ret[dn_idx])
      } else NA_real_
    },
    # LTD proxy: P(r_stock < q10_stock | r_mkt < q10_mkt) - 0.10
    # Higher → stronger lower-tail dependence
    ltd_proxy = {
      mkt_lt10 <- BM_Ret < bm_q10
      stock_q10 <- quantile(Ret, 0.10, na.rm = TRUE, names = FALSE)
      stock_lt10 <- Ret < stock_q10
      if (sum(mkt_lt10) >= 10) {
        sum(mkt_lt10 & stock_lt10, na.rm = TRUE) / sum(mkt_lt10, na.rm = TRUE) - 0.10
      } else NA_real_
    }
  ), by = Ticker][n_obs >= min_obs]
}

#==============================================================================
# 4) Universe filter (KOSPI200 ∪ KOSDAQ150, LIQ ≥ 2e8)
#==============================================================================

build_universe <- function(rawdata, sig_date) {
  cutoff <- as.Date(sig_date) - 1L
  start20 <- cutoff - 35L  # buffer for non-trading days

  win <- rawdata[Date >= start20 & Date <= cutoff, .(Date, Ticker, Close, Vol, K200, KQ150,
                                                      AdminStock, TradingHalt, UnfaithfulDisc, Size)]
  # 20d avg TV = mean(Close * Vol) for last 20 days
  win[, TV := Close * Vol]
  setorder(win, Ticker, -Date)
  win[, day_idx := seq_len(.N), by = Ticker]

  tv20 <- win[day_idx <= 20, .(LIQ_20d = mean(TV, na.rm = TRUE)), by = Ticker]

  last_row <- win[day_idx == 1L, .(Ticker, K200, KQ150, AdminStock, TradingHalt,
                                   UnfaithfulDisc, Size, Close, Date)]
  univ <- merge(last_row, tv20, by = "Ticker", all.x = TRUE)
  univ[, in_kospi200 := K200 == 1 & !is.na(K200)]
  univ[, in_kosdaq150 := KQ150 == 1 & !is.na(KQ150)]
  univ <- univ[(in_kospi200 | in_kosdaq150) &
               LIQ_20d >= LIQ_THRESHOLD &
               (is.na(AdminStock) | AdminStock == 0) &
               (is.na(TradingHalt) | TradingHalt == 0) &
               (is.na(UnfaithfulDisc) | UnfaithfulDisc == 0)]
  univ
}

#==============================================================================
# 5) Cross-section alpha vector
#==============================================================================
# α_{i,t} = -1 * S_t * z_composite_tail(stock_i, t-1)
#   z_composite_tail = (z_tail_beta + z_downside_beta + z_ltd_proxy) / 3
#
# Bear S_t = -1 → α positive for LOW tail-sensitive (defensive)
# Bull S_t = +1 → α positive for HIGH tail-sensitive (offensive)
# Normal S_t = 0 → α = 0 (cash-neutral, base case)

z_safe <- function(x) {
  x_clean <- x[!is.na(x) & is.finite(x)]
  if (length(x_clean) < 5) return(rep(NA_real_, length(x)))
  # Winsorize 1%/99%
  q <- quantile(x_clean, c(0.01, 0.99), na.rm = TRUE, names = FALSE)
  x_w <- pmin(pmax(x, q[1]), q[2])
  (x_w - mean(x_w, na.rm = TRUE)) / sd(x_w, na.rm = TRUE)
}

compute_alpha_vector <- function(rawdata, bm_dt, p4_state_dt, sig_date) {
  # 1) Universe filter
  univ <- build_universe(rawdata, sig_date)
  if (nrow(univ) == 0) return(data.table(Date = as.Date(sig_date), Ticker = character(0), alpha = numeric(0)))

  # 2) Restrict returns to universe + window
  R_subset <- rawdata[Ticker %in% univ$Ticker, .(Date, Ticker, Ret)]
  B_subset <- bm_dt[, .(Date = as.Date(Date), BM_Ret)]

  # 3) Compute tail sensitivity
  tail_sens <- compute_tail_sensitivity(R_subset, B_subset, sig_date)
  if (nrow(tail_sens) == 0) return(data.table(Date = as.Date(sig_date), Ticker = character(0), alpha = numeric(0)))

  # 4) Z-score (cross-sectional, direction-aligned)
  tail_sens[, z_tail_beta := z_safe(tail_beta)]
  tail_sens[, z_downside_beta := z_safe(downside_beta)]
  tail_sens[, z_ltd_proxy := z_safe(ltd_proxy)]
  tail_sens[, z_composite := rowMeans(.SD, na.rm = TRUE),
            .SDcols = c("z_tail_beta", "z_downside_beta", "z_ltd_proxy")]

  # 5) Get state S_t at sig_date - 1 (PIT-safe, continuous in [-1, +1])
  state_dt <- p4_state_dt[Date <= (as.Date(sig_date) - 1L)]
  if (nrow(state_dt) == 0) {
    state_st <- 0
  } else {
    state_st <- state_dt[order(-Date)][1, state]
    if (is.na(state_st)) state_st <- 0
  }

  # 6) α = -S_t · z_composite (sign convention per literature)
  #    Bear (S_t = +1):  high z_composite (tail-sens HIGH) → α negative (underweight)
  #                      low z_composite  (tail-sens LOW)  → α positive (overweight, defensive)
  #    Bull (S_t = -1):  high z_composite → α positive (offensive cyclical)
  #                      low z_composite  → α negative
  # Mechanism cites: van Oordt-Zhou 2016, Ang-Chen-Xing 2006, Chabi-Yo et al 2018,
  # Atilgan et al 2020 (left-tail momentum), Eom et al 2023 (KR-specific).
  tail_sens[, S_t := state_st]
  tail_sens[, alpha := -state_st * z_composite]
  tail_sens[, Date := as.Date(sig_date)]

  # Confidence based on z_composite presence + n_obs
  tail_sens[, confidence := pmin(pmax(
    0.5 + 0.5 * (n_obs / TAIL_WINDOW) - 0.5 * (sum(is.na(c(z_tail_beta, z_downside_beta, z_ltd_proxy))) / 3),
    0.10), 1.0)]

  out <- tail_sens[, .(Date, Ticker, alpha, confidence, S_t, z_composite,
                       tail_beta, downside_beta, ltd_proxy, n_obs)]
  out
}

#==============================================================================
# 6) Pipeline runner
#==============================================================================

generate_alpha_scores_panel <- function(sig_dates, rawdata, bm_dt, p4_state_dt) {
  result <- list()
  for (sd in sig_dates) {
    sd <- as.Date(sd)
    msg <- sprintf("[%s] generating alpha vector...", sd)
    cat(msg, "\n")
    a <- tryCatch(
      compute_alpha_vector(rawdata, bm_dt, p4_state_dt, sd),
      error = function(e) {
        cat("  err: ", e$message, "\n")
        data.table(Date = sd, Ticker = character(0), alpha = numeric(0))
      }
    )
    result[[as.character(sd)]] <- a
    cat("  N tickers with alpha:", sum(!is.na(a$alpha)),
        " | state:", if(nrow(a)>0) a$S_t[1] else NA, "\n")
  }
  rbindlist(result, fill = TRUE)
}
