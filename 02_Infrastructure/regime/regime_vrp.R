#==============================================================================
# Regime VRP (Variance Risk Premium) Signal
#
# Reference: Bollerslev, Tauchen & Zhou (2009) RFS
#   "Expected Stock Returns and Variance Risk Premia"
#
# VRP = Implied Variance - Realized Variance
#     = (VKOSPI/100)^2 - RV_22d
# where RV_22d = (252/22) * sum(r_t^2) over last 22 trading days
#
# Positive VRP = market pricing more risk than realized = normal
# Negative or very high VRP = elevated/collapsed risk premium = signal
#
# At each month_end, uses only data up to that date. Zero lookahead.
# Z-score computed via expanding window (PIT compliant).
#
# USAGE:
#   source("02_Infrastructure/regime_vrp.R")
#   vrp_dt <- compute_vrp_signal(month_ends)
#
# OUTPUT:
#   data.table(month_end, vrp, vrp_z)
#
# Author: Q-Lead Agent
# Date:   2026-03-17
#==============================================================================

cat("[regime_vrp] Loading...\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
}
if (!exists("CACHE_DIR")) {
  CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
}

#------------------------------------------------------------------------------
# compute_vrp_signal
#
# At each month_end:
#   1. Get VKOSPI (IKS221) as of month_end -> implied variance = (VKOSPI/100)^2
#   2. Get BM daily returns for last 22 trading days up to month_end
#   3. Compute RV_22d = (252/22) * sum(r^2)
#   4. VRP = IV - RV
#   5. Z-score VRP using expanding window
#
# Returns: data.table(month_end, vkospi_level, iv, rv_22d, vrp, vrp_z)
#------------------------------------------------------------------------------
compute_vrp_signal <- function(month_ends = NULL) {

  cat("[vrp] Computing Variance Risk Premium signal...\n")

  # --- Load VKOSPI (IKS221) ---
  ktri_path <- file.path(CACHE_DIR, "ktri_indices.parquet")
  if (!file.exists(ktri_path)) stop("[vrp] ktri_indices.parquet not found")

  ktri <- as.data.table(read_parquet(ktri_path))
  ktri[, Date := as.Date(Date)]
  setorder(ktri, Date)

  if (!"IKS221" %in% names(ktri)) {
    stop("[vrp] IKS221 (VKOSPI) column not found in ktri_indices.parquet")
  }

  vkospi <- ktri[!is.na(IKS221), .(Date, VKOSPI = IKS221)]
  vkospi[, VKOSPI := nafill(VKOSPI, type = "locf")]
  setkey(vkospi, Date)

  # --- Load BM daily returns ---
  bm_path <- file.path(CACHE_DIR, "benchmark.parquet")
  if (!file.exists(bm_path)) stop("[vrp] benchmark.parquet not found")

  bm <- as.data.table(read_parquet(bm_path))
  bm[, Date := as.Date(Date)]
  setorder(bm, Date)
  bm[, ret := BM_Close / shift(BM_Close, 1L) - 1]
  bm <- bm[!is.na(ret)]
  setkey(bm, Date)

  # --- Default month_ends ---
  if (is.null(month_ends)) {
    max_date <- max(bm$Date)
    fom_seq <- seq.Date(ANALYSIS_START_DATE, max_date, by = "month")
    month_ends <- sort(unique(as.Date(sapply(fom_seq, function(d) {
      as.Date(format(d, "%Y-%m-01")) - 1
    }), origin = "1970-01-01")))
    latest_me <- as.Date(format(max_date + 1, "%Y-%m-01")) - 1
    if (latest_me <= max_date) {
      month_ends <- sort(unique(c(month_ends, latest_me)))
    }
    month_ends <- month_ends[month_ends >= ANALYSIS_START_DATE - 1]
  }
  month_ends <- sort(as.Date(month_ends))

  cat(sprintf("[vrp] %d month-ends (%s ~ %s)\n",
              length(month_ends), min(month_ends), max(month_ends)))

  # --- Pre-index trading dates ---
  bm_dates <- sort(unique(bm$Date))
  td_idx <- data.table(Date = bm_dates, idx = seq_along(bm_dates))
  setkey(td_idx, Date)

  # --- Compute VRP at each month_end ---
  n_me <- length(month_ends)
  iv_vec     <- rep(NA_real_, n_me)
  rv_vec     <- rep(NA_real_, n_me)
  vrp_vec    <- rep(NA_real_, n_me)
  vkospi_vec <- rep(NA_real_, n_me)

  RV_WINDOW <- 22L  # 22 trading days ~ 1 month

  for (m in seq_len(n_me)) {
    me <- month_ends[m]

    # 1. VKOSPI as of month_end (roll forward from last available)
    vk_avail <- vkospi[Date <= me]
    if (nrow(vk_avail) == 0) next
    vk_level <- vk_avail[.N, VKOSPI]
    vkospi_vec[m] <- vk_level

    # Implied variance: VKOSPI is annualized volatility in %
    # IV = (VKOSPI/100)^2
    iv_vec[m] <- (vk_level / 100)^2

    # 2. Realized variance from last 22 trading days
    bm_avail <- td_idx[Date <= me]
    if (nrow(bm_avail) == 0) next
    end_idx <- bm_avail[.N, idx]
    if (end_idx < RV_WINDOW) next

    start_idx <- end_idx - RV_WINDOW + 1L
    window_dates <- bm_dates[start_idx:end_idx]
    bm_window <- bm[Date %in% window_dates]

    if (nrow(bm_window) < RV_WINDOW * 0.8) next  # require at least 80% data

    # RV_22d = (252/22) * sum(r^2)  [annualized realized variance]
    rv_vec[m] <- (252 / RV_WINDOW) * sum(bm_window$ret^2, na.rm = TRUE)

    # 3. VRP = IV - RV
    vrp_vec[m] <- iv_vec[m] - rv_vec[m]
  }

  # --- Expanding-window z-score of VRP ---
  vrp_z <- rep(NA_real_, n_me)
  MIN_OBS <- 24L  # need 24 months for meaningful z-score

  for (i in seq_len(n_me)) {
    if (is.na(vrp_vec[i])) next
    past <- vrp_vec[1:i]
    past <- past[!is.na(past)]
    if (length(past) < MIN_OBS) next
    m_vrp <- mean(past)
    s_vrp <- sd(past)
    if (!is.na(s_vrp) && s_vrp > 1e-8) {
      vrp_z[i] <- (vrp_vec[i] - m_vrp) / s_vrp
    }
  }

  result <- data.table(
    month_end    = month_ends,
    vkospi_level = round(vkospi_vec, 2),
    iv           = round(iv_vec, 6),
    rv_22d       = round(rv_vec, 6),
    vrp          = round(vrp_vec, 6),
    vrp_z        = round(vrp_z, 4)
  )

  # --- Summary ---
  valid <- result[!is.na(vrp)]
  cat(sprintf("\n[vrp] Done. %d/%d months computed.\n",
              nrow(valid), nrow(result)))
  if (nrow(valid) > 0) {
    cat(sprintf("  VRP range: [%.4f, %.4f], mean=%.4f\n",
                min(valid$vrp), max(valid$vrp), mean(valid$vrp)))
    cat(sprintf("  vrp_z range: [%.2f, %.2f]\n",
                min(result$vrp_z, na.rm = TRUE), max(result$vrp_z, na.rm = TRUE)))
  }

  # --- Crisis snapshots ---
  crisis_dates <- as.Date(c("2008-08-31", "2020-01-31", "2022-06-30"))
  cat("\n  Crisis snapshots:\n")
  for (cd in crisis_dates) {
    cd <- as.Date(cd, origin = "1970-01-01")
    row <- result[month_end == cd]
    if (nrow(row) == 0) {
      row <- result[month_end <= cd]
      if (nrow(row) > 0) row <- row[.N]
    }
    if (nrow(row) > 0) {
      cat(sprintf("    %s: VKOSPI=%.1f, IV=%.4f, RV=%.4f, VRP=%.4f, vrp_z=%.2f\n",
                  row$month_end, row$vkospi_level, row$iv, row$rv_22d,
                  row$vrp, row$vrp_z))
    }
  }

  result
}

cat("[regime_vrp] Loaded. Function: compute_vrp_signal(month_ends)\n")
