## STR_1425: Adaptive IC-Weighted Multi-Factor Rotation
## 5 factors: D01, C01, C04, Q07, CR08
## Expanding ICIR-based dynamic weighting. ICIR < 0.1 → deactivate.
## C1: expanding window only. C13: Z_Score_Aligned. C14: IC Usable_Date (t-1).

cat("[factor_engine] STR_1425: Adaptive IC-Weighted 5-Factor Rotation...\n")

source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

NEEDED_FACTORS <- c("D01_IdioVol", "C01_SUE", "C04_ESBR",
                     "Q07_Earnings_Stability", "CR08_Volume_Price_Divergence")
ICIR_DEACTIVATION <- 0.1
MIN_IC_MONTHS <- 12  # minimum months before ICIR is reliable

# ── Bulk load via Arrow Dataset ──
FDB_DIR <- file.path(CACHE_DIR, "factor_db")
library(arrow)
ds <- open_dataset(FDB_DIR, format = "parquet")
FDB_RAW <- ds |>
  dplyr::filter(Factor_Name %in% NEEDED_FACTORS) |>
  dplyr::collect() |>
  as.data.table()
cat(sprintf("  Loaded: %s rows, %d factors\n",
            format(nrow(FDB_RAW), big.mark = ","), uniqueN(FDB_RAW$Factor_Name)))

registry <- .load_registry()
FDB_ALL <- align_factor_direction(FDB_RAW, registry)
FDB_ALL[, Date := as.Date(Date)]
setkey(FDB_ALL, Date, Ticker)
rm(FDB_RAW, ds); gc(verbose = FALSE)

# ── Signal dates ──
setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
signal_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM][, sort(Signal_Date)]
signal_dates <- signal_dates[signal_dates >= SIGNAL_START_DATE]
cat(sprintf("  Signal dates: %d (%s ~ %s)\n",
            length(signal_dates), min(signal_dates), max(signal_dates)))

# ── Liquidity filter (C10: lagged) ──
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, 20L, align = "right"),
                            1L, type = "lag"), by = Ticker]

# ── Pre-compute 1-month forward returns for IC calculation ──
# forward_ret[t] = return from signal_date[t] to signal_date[t+1]
cat("  Pre-computing monthly forward returns for IC...\n")
sig_close <- RAWDATA[Date %in% signal_dates, .(Date, Ticker, Close)]
setkey(sig_close, Ticker, Date)

fwd_ret_list <- list()
for (i in seq_len(length(signal_dates) - 1)) {
  d0 <- signal_dates[i]; d1 <- signal_dates[i + 1]
  c0 <- sig_close[Date == d0, .(Ticker, Close0 = Close)]
  c1 <- sig_close[Date == d1, .(Ticker, Close1 = Close)]
  m <- merge(c0, c1, by = "Ticker")
  m[, FwdRet := Close1 / Close0 - 1]
  m[, Date := d0]
  fwd_ret_list[[i]] <- m[, .(Date, Ticker, FwdRet)]
}
FWD_RET <- rbindlist(fwd_ret_list)
setkey(FWD_RET, Date, Ticker)
cat(sprintf("  Forward returns: %s rows\n", format(nrow(FWD_RET), big.mark = ",")))

# ── Compute monthly IC for each factor (rank correlation) ──
cat("  Computing monthly IC for each factor...\n")
ic_history <- list()  # ic_history[[factor_name]] = data.table(Date, IC)

for (fn in NEEDED_FACTORS) {
  ic_vals <- numeric(length(signal_dates) - 1)
  ic_dates <- signal_dates[seq_len(length(signal_dates) - 1)]

  for (i in seq_along(ic_dates)) {
    d0 <- ic_dates[i]
    fdt <- FDB_ALL[Date == d0 & Factor_Name == fn, .(Ticker, Z_Score_Aligned)]
    fret <- FWD_RET[Date == d0, .(Ticker, FwdRet)]
    m <- merge(fdt, fret, by = "Ticker")
    m <- m[!is.na(Z_Score_Aligned) & !is.na(FwdRet)]

    if (nrow(m) >= 30) {
      ic_vals[i] <- cor(rank(m$Z_Score_Aligned), rank(m$FwdRet), method = "spearman")
    } else {
      ic_vals[i] <- NA_real_
    }
  }

  ic_history[[fn]] <- data.table(Date = ic_dates, IC = ic_vals)
}
cat("  IC computation complete.\n")
rm(FWD_RET, sig_close); gc(verbose = FALSE)

# ── Main scoring loop with expanding ICIR weights ──
factor_list <- vector("list", length(signal_dates))
n_done <- 0L; n_skip <- 0L

for (i in seq_along(signal_dates)) {
  sig_d <- as.Date(signal_dates[i])

  # Universe
  snap <- RAWDATA[Date == sig_d, .(Ticker, Close, AvgTV20, Sector)]
  snap <- snap[!is.na(Close) & Close > 0 & !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(snap) < 30) { n_skip <- n_skip + 1L; next }

  # Factor scores
  fdt <- FDB_ALL[Date == sig_d & Factor_Name %in% NEEDED_FACTORS,
                 .(Ticker, Factor_Name, Z_Score_Aligned)]
  if (nrow(fdt) == 0) { n_skip <- n_skip + 1L; next }
  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  dt <- merge(snap, fdt_wide, by = "Ticker")

  # Compute expanding ICIR for each factor (using IC[1:t-1] only -- C14)
  # IC[t] uses return from t to t+1, so IC[t] is known at t+1
  # At signal date sig_d, latest usable IC is from the PREVIOUS month
  factor_weights <- setNames(rep(0, length(NEEDED_FACTORS)), NEEDED_FACTORS)

  for (fn in NEEDED_FACTORS) {
    ic_dt <- ic_history[[fn]]
    # S5 M1_LAGGED_IC: 2-month IC lag for full C14 PIT compliance
    ic_cutoff <- sig_d %m-% months(2L)
    avail_ic <- ic_dt[Date <= ic_cutoff & !is.na(IC), IC]

    if (length(avail_ic) < MIN_IC_MONTHS) {
      # Not enough history -- use EW fallback
      factor_weights[fn] <- 1.0 / length(NEEDED_FACTORS)
    } else {
      icir <- mean(avail_ic) / sd(avail_ic)
      if (is.na(icir) || icir < ICIR_DEACTIVATION) {
        factor_weights[fn] <- 0  # Deactivate
      } else {
        factor_weights[fn] <- max(0, icir)
      }
    }
  }

  # Normalize weights
  w_sum <- sum(factor_weights)
  if (w_sum < 1e-8) { n_skip <- n_skip + 1L; next }
  factor_weights <- factor_weights / w_sum

  # Active factors
  active <- names(factor_weights[factor_weights > 0])
  if (length(active) == 0) { n_skip <- n_skip + 1L; next }

  # Composite score
  dt[, Score := 0]
  for (fn in active) {
    if (fn %in% names(dt)) {
      vals <- dt[[fn]]
      vals[is.na(vals)] <- 0
      dt[, Score := Score + factor_weights[fn] * vals]
    }
  }

  dt <- dt[!is.na(Score)]
  dt[, Score := Score - mean(Score, na.rm = TRUE), by = Sector]
  dt[, Date := sig_d]
  factor_list[[i]] <- dt[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)

# Cleanup
if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
for (col in c("TradingValue", "AvgTV20")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}
rm(FDB_ALL, ic_history); gc(verbose = FALSE)

cat(sprintf("  FACTORS: %s rows | %d signal dates (skip %d)\n",
            format(nrow(FACTORS), big.mark = ","), n_done, n_skip))
