#==============================================================================
# compute_consensus.R — Consensus / Earnings Factor 계산 모듈 (C01~C08)
#
# 함수: compute_consensus(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL)
# 반환: data.table(Ticker, Factor_Name, Raw_Value)
#
# PIT 준수: Date <= sig_date for consensus data
# CONSENSUS 스키마: Date, Ticker, sue, eps_chg_1m, eps_chg_3m, esbr, escr,
#                   target_price, coverage (+ 기타)
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
})

compute_consensus <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {
  sig_d <- as.Date(sig_date)
  results <- list()

  # --- CONSENSUS is a named list of data.tables (e.g. CONSENSUS$sue, CONSENSUS$eps_1y, ...) ---
  # Merge all sub-tables into one wide data.table keyed by (Date, Ticker)
  if (!is.list(CONSENSUS) || length(CONSENSUS) == 0L) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }

  # ── Performance-optimized merge: extract latest per Ticker BEFORE joining ──
  # Old approach: Reduce(full-outer-join, 13 tables) → filter → last-per-ticker
  # New approach: filter → last-per-ticker per table → merge small tables (2506 rows each)
  latest_parts <- list()
  for (nm in names(CONSENSUS)) {
    sub <- CONSENSUS[[nm]]
    if (!is.data.table(sub) || nrow(sub) == 0L || !all(c("Date", "Ticker") %in% names(sub))) next
    if (!inherits(sub$Date, "Date")) sub[, Date := as.Date(Date)]
    sub_pit <- sub[Date <= sig_d]
    if (nrow(sub_pit) == 0L) next
    setorder(sub_pit, Ticker, Date)
    latest_sub <- sub_pit[, .SD[.N], by = Ticker]
    # Keep only Ticker, Date, and metric columns (drop duplicate Date from later merges)
    metric_cols <- setdiff(names(latest_sub), c("Ticker", "Date"))
    if (length(metric_cols) == 0L) next
    latest_parts[[nm]] <- latest_sub[, c("Ticker", "Date", metric_cols), with = FALSE]
  }

  if (length(latest_parts) == 0L) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }

  # Now merge the small latest-per-ticker tables (each ~2506 rows max)
  # Take max Date from each part for the final "latest date" column
  latest <- latest_parts[[1L]]
  if (length(latest_parts) > 1L) {
    for (i in seq(2L, length(latest_parts))) {
      part <- latest_parts[[i]]
      # Rename "Date" to avoid collision; we'll resolve after
      metric_cols_i <- setdiff(names(part), c("Ticker", "Date"))
      part_sub <- part[, c("Ticker", metric_cols_i), with = FALSE]
      latest <- merge(latest, part_sub, by = "Ticker", all = TRUE)
    }
  }
  # cons variable is no longer used below but some C07 code references it — rebuild slim version
  cons <- rbindlist(lapply(latest_parts, function(p) p[, .(Ticker, Date)]), use.names = TRUE)[
    , .(Date = max(Date)), by = Ticker]
  # Attach metric data back from latest for lag computations
  # (C07 needs historical cons, so rebuild from original for lag lookups)
  cons_for_lag <- NULL
  if ("target_price" %in% names(latest)) {
    tp_src <- CONSENSUS[["target_price"]]
    if (!is.null(tp_src) && nrow(tp_src) > 0L) {
      if (!inherits(tp_src$Date, "Date")) tp_src[, Date := as.Date(Date)]
      cons_for_lag <- tp_src[Date <= sig_d]
      setorder(cons_for_lag, Ticker, Date)
    }
  }

  # --- C01: SUE (Standardized Unexpected Earnings) ---
  if ("sue" %in% names(latest)) {
    c01 <- latest[!is.na(sue), .(Ticker, Factor_Name = "C01_SUE", Raw_Value = sue)]
    if (nrow(c01) > 0) results[["C01"]] <- c01
  }

  # --- C02: EPS Change 1m ---
  if ("eps_chg_1m" %in% names(latest)) {
    c02 <- latest[!is.na(eps_chg_1m), .(Ticker, Factor_Name = "C02_EPS_Chg_1m", Raw_Value = eps_chg_1m)]
    if (nrow(c02) > 0) results[["C02"]] <- c02
  }

  # --- C03: EPS Change 3m ---
  if ("eps_chg_3m" %in% names(latest)) {
    c03 <- latest[!is.na(eps_chg_3m), .(Ticker, Factor_Name = "C03_EPS_Chg_3m", Raw_Value = eps_chg_3m)]
    if (nrow(c03) > 0) results[["C03"]] <- c03
  }

  # --- C04: ESBR (Earnings Sentiment Breadth Ratio) ---
  if ("esbr" %in% names(latest)) {
    c04 <- latest[!is.na(esbr), .(Ticker, Factor_Name = "C04_ESBR", Raw_Value = esbr)]
    if (nrow(c04) > 0) results[["C04"]] <- c04
  }

  # --- C05: ESCR (Earnings Sentiment Consistency Ratio) ---
  if ("escr" %in% names(latest)) {
    c05 <- latest[!is.na(escr), .(Ticker, Factor_Name = "C05_ESCR", Raw_Value = escr)]
    if (nrow(c05) > 0) results[["C05"]] <- c05
  }

  # --- C06: TP Gap = (Target Price - Close) / Close ---
  if ("target_price" %in% names(latest)) {
    # Close from RAWDATA at sig_date — use .pit_rawdata pattern (setkey already applied)
    rd_snap <- RAWDATA[Date == sig_d]
    if (nrow(rd_snap) == 0L) {
      # sig_d may be non-trading day; take most recent available trading day
      avail_d <- sort(unique(RAWDATA$Date[RAWDATA$Date <= sig_d]))
      if (length(avail_d) > 0L) rd_snap <- RAWDATA[Date == avail_d[length(avail_d)]]
    }
    rd_latest <- rd_snap

    if ("Close" %in% names(rd_latest) && nrow(rd_latest) > 0) {
      tp_merged <- merge(
        latest[!is.na(target_price), .(Ticker, target_price)],
        rd_latest[!is.na(Close) & Close > 0, .(Ticker, Close)],
        by = "Ticker"
      )
      if (nrow(tp_merged) > 0) {
        c06 <- tp_merged[, .(Ticker, Factor_Name = "C06_TP_Gap",
                             Raw_Value = (target_price - Close) / Close)]
        c06 <- c06[is.finite(Raw_Value)]
        if (nrow(c06) > 0) results[["C06"]] <- c06
      }
    }
  }

  # --- C07: TP Momentum = delta(target_price, 35d lag) / target_price ---
  if ("target_price" %in% names(latest)) {
    lag_date <- sig_d - 35
    # Current TP: latest
    tp_curr <- latest[!is.na(target_price), .(Ticker, tp_curr = target_price)]

    # Lagged TP: use cons_for_lag (slim target_price history table)
    cons_lag <- if (!is.null(cons_for_lag)) cons_for_lag[Date <= lag_date] else NULL
    if (!is.null(cons_lag) && nrow(cons_lag) > 0) {
      setorder(cons_lag, Ticker, Date)
      tp_lag <- cons_lag[!is.na(target_price), .SD[.N], by = Ticker]
      tp_lag <- tp_lag[, .(Ticker, tp_lag = target_price)]

      tp_both <- merge(tp_curr, tp_lag, by = "Ticker")
      tp_both <- tp_both[tp_lag > 0]
      if (nrow(tp_both) > 0) {
        c07 <- tp_both[, .(Ticker, Factor_Name = "C07_TP_Mom",
                           Raw_Value = (tp_curr - tp_lag) / tp_lag)]
        c07 <- c07[is.finite(Raw_Value)]
        if (nrow(c07) > 0) results[["C07"]] <- c07
      }
    }
  }

  # --- C08: Coverage (analyst count) ---
  if ("coverage" %in% names(latest)) {
    c08 <- latest[!is.na(coverage), .(Ticker, Factor_Name = "C08_Coverage", Raw_Value = as.numeric(coverage))]
    if (nrow(c08) > 0) results[["C08"]] <- c08
  }

  # ==========================================================================
  # C09~C19: Additional Earnings / Consensus Factors (from extraction report)
  # ==========================================================================

  # --- C09: Earnings Surprise (normalized) ---
  # (Actual - Forecast) / |Forecast|.  Different from SUE: no std normalization.
  # Uses sue as proxy if actual/forecast not separately available.
  # If we have eps_1y (forecast) and a way to get actual, compute directly.
  # For now, abs(sue) gives magnitude; sue itself is the standardized version.
  # Distinct metric: sign(sue) * sue^2 amplifies large surprises.
  if ("sue" %in% names(latest)) {
    c09 <- latest[!is.na(sue), .(Ticker, Factor_Name = "C09_Earnings_Surprise_Sq",
                                  Raw_Value = sign(sue) * sue^2)]
    c09 <- c09[is.finite(Raw_Value)]
    if (nrow(c09) > 0) results[["C09"]] <- c09
  }

  # --- C10: Earnings Surprise Persistence (PEAD proxy) ---
  # Average of last 4 SUE values — captures persistent drift.
  if ("sue" %in% names(cons)) {
    setorder(cons, Ticker, -Date)
    sue_avg <- cons[!is.na(sue), {
      n <- min(.N, 4L)
      list(sue_avg4 = mean(sue[1:n]))
    }, by = Ticker]
    if (nrow(sue_avg) > 0) {
      c10 <- sue_avg[!is.na(sue_avg4),
                      .(Ticker, Factor_Name = "C10_SUE_Persistence", Raw_Value = sue_avg4)]
      if (nrow(c10) > 0) results[["C10"]] <- c10
    }
  }

  # --- C11: Earnings Streak (consecutive positive SUE count) ---
  if ("sue" %in% names(cons)) {
    setorder(cons, Ticker, -Date)
    sue_streak <- cons[!is.na(sue), {
      streak <- 0L
      for (i in seq_len(.N)) {
        if (!is.na(sue[i]) && sue[i] > 0) streak <- streak + 1L else break
      }
      list(streak = as.numeric(streak))
    }, by = Ticker]
    if (nrow(sue_streak) > 0) {
      c11 <- sue_streak[, .(Ticker, Factor_Name = "C11_Earnings_Streak", Raw_Value = streak)]
      if (nrow(c11) > 0) results[["C11"]] <- c11
    }
  }

  # --- C12: Estimate Dispersion (forecast std / |mean forecast|) ---
  # DATA_NEEDED: analyst-level EPS forecasts for proper dispersion
  # Proxy: use coverage & eps_1y to flag — if we had individual forecasts,
  # dispersion = sd(forecasts) / |mean(forecasts)|.
  # For now, return NA with comment.
  # Possible proxy: |eps_chg_1m - eps_chg_3m| / |eps_1y| as disagreement signal.
  if (all(c("eps_chg_1m", "eps_chg_3m", "eps_1y") %in% names(latest))) {
    c12 <- latest[!is.na(eps_chg_1m) & !is.na(eps_chg_3m) & !is.na(eps_1y) & abs(eps_1y) > 1e-6,
                   .(Ticker, Factor_Name = "C12_Estimate_Dispersion_Proxy",
                     Raw_Value = abs(eps_chg_1m - eps_chg_3m) / abs(eps_1y))]
    c12 <- c12[is.finite(Raw_Value)]
    if (nrow(c12) > 0) results[["C12"]] <- c12
  }

  # --- C13: Revision Breadth (ESBR - already C04, but 3m rolling version) ---
  # Use time-series of ESBR: average ESBR over last 3 observations.
  if ("esbr" %in% names(cons)) {
    setorder(cons, Ticker, -Date)
    esbr_avg <- cons[!is.na(esbr), {
      n <- min(.N, 3L)
      list(esbr_avg3 = mean(esbr[1:n]))
    }, by = Ticker]
    if (nrow(esbr_avg) > 0) {
      c13 <- esbr_avg[!is.na(esbr_avg3),
                       .(Ticker, Factor_Name = "C13_Revision_Breadth_3m", Raw_Value = esbr_avg3)]
      if (nrow(c13) > 0) results[["C13"]] <- c13
    }
  }

  # --- C14: Revenue Surprise (consensus revenue_fy1 change) ---
  # Jegadeesh-Livnat (2006): revenue surprises add incremental predictive power.
  if ("revenue_fy1" %in% names(cons)) {
    setorder(cons, Ticker, -Date)
    lag_d <- sig_d - 63L
    rev_now <- cons[!is.na(revenue_fy1), .SD[1L], by = Ticker][, .(Ticker, rev_now = revenue_fy1)]
    rev_lag <- cons[Date <= lag_d & !is.na(revenue_fy1), .SD[1L], by = Ticker]
    if (nrow(rev_lag) > 0) {
      rev_lag <- rev_lag[, .(Ticker, rev_lag = revenue_fy1)]
      rev_both <- merge(rev_now, rev_lag, by = "Ticker")
      c14 <- rev_both[abs(rev_lag) > 1e-6,
                       .(Ticker, Factor_Name = "C14_Revenue_Surprise",
                         Raw_Value = (rev_now - rev_lag) / abs(rev_lag))]
      c14 <- c14[is.finite(Raw_Value)]
      if (nrow(c14) > 0) results[["C14"]] <- c14
    }
  }

  # --- C15: Forecast Error Trend ---
  # Direction of change in SUE over time: latest SUE - 2nd latest SUE.
  if ("sue" %in% names(cons)) {
    setorder(cons, Ticker, -Date)
    sue_delta <- cons[!is.na(sue), {
      if (.N >= 2L) list(sue_d = sue[1L] - sue[2L])
      else list(sue_d = NA_real_)
    }, by = Ticker]
    if (nrow(sue_delta) > 0) {
      c15 <- sue_delta[!is.na(sue_d),
                        .(Ticker, Factor_Name = "C15_Forecast_Error_Trend", Raw_Value = sue_d)]
      if (nrow(c15) > 0) results[["C15"]] <- c15
    }
  }

  # --- C16: EPS Acceleration (eps_chg_1m - eps_chg_3m / 3) ---
  # Recent revision speed vs longer-term average revision speed.
  if (all(c("eps_chg_1m", "eps_chg_3m") %in% names(latest))) {
    c16 <- latest[!is.na(eps_chg_1m) & !is.na(eps_chg_3m),
                   .(Ticker, Factor_Name = "C16_EPS_Acceleration",
                     Raw_Value = eps_chg_1m - eps_chg_3m / 3)]
    c16 <- c16[is.finite(Raw_Value)]
    if (nrow(c16) > 0) results[["C16"]] <- c16
  }

  # --- C17: OP Profit Revision (consensus operating profit change) ---
  if ("op_profit_fy1" %in% names(cons)) {
    setorder(cons, Ticker, -Date)
    lag_d <- sig_d - 63L
    op_now <- cons[!is.na(op_profit_fy1), .SD[1L], by = Ticker][, .(Ticker, op_now = op_profit_fy1)]
    op_lag <- cons[Date <= lag_d & !is.na(op_profit_fy1), .SD[1L], by = Ticker]
    if (nrow(op_lag) > 0) {
      op_lag <- op_lag[, .(Ticker, op_lag = op_profit_fy1)]
      op_both <- merge(op_now, op_lag, by = "Ticker")
      c17 <- op_both[abs(op_lag) > 1e-6,
                      .(Ticker, Factor_Name = "C17_OP_Revision",
                        Raw_Value = (op_now - op_lag) / abs(op_lag))]
      c17 <- c17[is.finite(Raw_Value)]
      if (nrow(c17) > 0) results[["C17"]] <- c17
    }
  }

  # --- C18: Abnormal Returns around Earnings Announcements (3-day CAR proxy) ---
  # DATA_NEEDED: earnings_announcement_dates for true CAR
  # Proxy: for each ticker, find dates near SUE observations with large |SUE|
  # and compute 3-day cumulative abnormal return around those dates.
  if ("sue" %in% names(cons) && nrow(RAWDATA) > 0) {
    # Get latest SUE date per ticker as proxy for announcement date
    setorder(cons, Ticker, -Date)
    ann_dates <- cons[!is.na(sue), .SD[1L], by = Ticker][, .(Ticker, ann_date = Date)]
    if (nrow(ann_dates) > 0) {
      rd <- copy(RAWDATA)
      rd[, Date := as.Date(Date)]

      # BM daily returns for abnormal return calculation
      bm_daily <- unique(rd[, .(Date, BM_Ret)])
      setorder(bm_daily, Date)

      car_list <- lapply(seq_len(nrow(ann_dates)), function(i) {
        tk <- ann_dates$Ticker[i]
        ad <- ann_dates$ann_date[i]
        # 3-day window: ann_date -1 to ann_date +1
        sub <- rd[Ticker == tk & Date >= (ad - 3L) & Date <= (ad + 3L) & !is.na(Ret)]
        bm_sub <- bm_daily[Date >= (ad - 3L) & Date <= (ad + 3L) & !is.na(BM_Ret)]
        sub <- merge(sub, bm_sub[, .(Date, BM_Ret)], by = "Date")
        if (nrow(sub) >= 2L) {
          car <- sum(sub$Ret - sub$BM_Ret, na.rm = TRUE)
          data.table(Ticker = tk, car3d = car)
        } else {
          NULL
        }
      })
      car_dt <- rbindlist(car_list[!vapply(car_list, is.null, logical(1))])
      if (nrow(car_dt) > 0) {
        c18 <- car_dt[is.finite(car3d),
                       .(Ticker, Factor_Name = "C18_Earnings_CAR_3d", Raw_Value = car3d)]
        if (nrow(c18) > 0) results[["C18"]] <- c18
      }
    }
  }

  # --- C19: Composite Earnings Factor ---
  # z(SUE) + z(ESBR) + z(EPS_chg_1m) + z(TP_Gap).  At least 2 of 4 required.
  z_safe <- function(x) {
    s <- sd(x, na.rm = TRUE)
    if (is.na(s) || s < 1e-8) return(rep(NA_real_, length(x)))
    (x - mean(x, na.rm = TRUE)) / s
  }

  # Build a wide table from existing results for compositing
  comp_cols <- c("C01_SUE", "C04_ESBR", "C02_EPS_Chg_1m", "C06_TP_Gap")
  comp_list <- list()
  for (cc in comp_cols) {
    if (cc %in% names(results)) {
      tmp <- results[[sub("C0[0-9]_", "", cc)]]
    }
    # Try to find by iterating
    tmp <- NULL
    for (nm in names(results)) {
      if (grepl(cc, results[[nm]]$Factor_Name[1], fixed = TRUE)) {
        tmp <- results[[nm]]
        break
      }
    }
    if (!is.null(tmp) && nrow(tmp) > 0) {
      short_name <- gsub("^C[0-9]+_", "", cc)
      setnames_tmp <- copy(tmp)[, .(Ticker, val = Raw_Value)]
      setnames(setnames_tmp, "val", short_name)
      comp_list[[short_name]] <- setnames_tmp
    }
  }

  if (length(comp_list) >= 2L) {
    comp_dt <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = TRUE), comp_list)
    comp_names <- setdiff(names(comp_dt), "Ticker")
    for (cn in comp_names) {
      zcol <- paste0("z_", cn)
      comp_dt[, (zcol) := z_safe(get(cn))]
    }
    z_cols <- paste0("z_", comp_names)
    comp_dt[, n_c := rowSums(!is.na(.SD)), .SDcols = z_cols]
    comp_dt[n_c >= 2L, C19_val := rowMeans(.SD, na.rm = TRUE), .SDcols = z_cols]
    c19 <- comp_dt[!is.na(C19_val) & is.finite(C19_val),
                    .(Ticker, Factor_Name = "C19_Composite_Earnings", Raw_Value = C19_val)]
    if (nrow(c19) > 0) results[["C19"]] <- c19
  }

  # 결합
  if (length(results) == 0) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }
  out <- rbindlist(results, use.names = TRUE, fill = TRUE)
  out[, .(Ticker, Factor_Name, Raw_Value)]
}

cat("[factor_db] compute_consensus.R loaded (C01~C19)\n")
