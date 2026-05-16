#==============================================================================
# WT-D20260514_003 — Method Comparison Backtest
# 5 methods × 267m forward returns → SR/MDD/CAGR/Sortino/Calmar/CVaR
# Backtest Contract v1.0 (PerformanceAnalytics standard functions only)
#==============================================================================

suppressMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics); library(xts)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID <- "WT-D20260514_003"
STAGE <- "stage_artifacts/WT_D20260514_003"

# Load data
weights_dt <- fread(file.path(STAGE, "optimizer_workspace", "weights_long_raw.csv"))
sleeve_dt  <- fread(file.path(STAGE, "optimizer_workspace", "sleeve_summary.csv"))
weights_dt[, as_of_date := as.Date(as_of_date)]
sleeve_dt[, as_of_date := as.Date(as_of_date)]

# RAWDATA + BM
suppressMessages({
  RAWDATA <- as.data.table(read_parquet(".cache/RAWDATA.parquet"))
  BM_DT   <- as.data.table(read_parquet(".cache/benchmark.parquet"))
})
setkey(RAWDATA, Date, Ticker)
setkey(BM_DT, Date)

# Monthly returns: per ticker, return from sig_date to next sig_date end
# Use RAWDATA monthly close (we get monthly returns from close-to-close)
get_monthly_ret <- function() {
  # Use RAWDATA Ret (which is daily). Aggregate to monthly per Ticker.
  rd <- RAWDATA[, .(Date, Ticker, Ret)]
  rd[, ym := format(Date, "%Y-%m")]
  # Monthly geometric return per ticker
  monthly <- rd[!is.na(Ret), .(
    monthly_ret = prod(1 + Ret) - 1,
    end_date = max(Date)
  ), by = .(Ticker, ym)]
  # Convert ym to month-end Date
  monthly[, sig_date := as.Date(end_date)]
  setkey(monthly, sig_date, Ticker)
  monthly
}

cat("[backtest] Building monthly returns panel...\n")
monthly <- get_monthly_ret()
cat(sprintf("  rows: %d | tickers: %d | months: %d\n",
            nrow(monthly), uniqueN(monthly$Ticker), uniqueN(monthly$ym)))

# Benchmark monthly
bm_d <- BM_DT[, .(Date, BM_Ret)]
bm_d[, ym := format(Date, "%Y-%m")]
bm_monthly <- bm_d[!is.na(BM_Ret), .(
  bm_monthly_ret = prod(1 + BM_Ret) - 1,
  end_date = max(Date)
), by = ym]
bm_monthly[, sig_date := as.Date(end_date)]
setkey(bm_monthly, sig_date)

# ─── Portfolio return per method per sig_date ────────────
# Strategy: at sig_date t, weights determine, hold until t+1 sig_date
# return_t = w_t · r_{t→t+1}  (next month monthly return)
methods <- unique(weights_dt$method)
cat("[backtest] Methods:", methods, "\n\n")

port_ret_records <- list()
weights_dt[, ym := format(as_of_date, "%Y-%m")]
weights_dt[, year := as.integer(format(as_of_date, "%Y"))]

# Map sig_date → next_month_ym for fwd return
all_sig_dates <- sort(unique(weights_dt$as_of_date))
next_ym <- format(all_sig_dates + 31, "%Y-%m")  # approximate +1 month
sig_to_next <- data.table(as_of_date = all_sig_dates, next_ym = next_ym)

# Use next sig_date's ym for forward returns (not arithmetic +31 days)
all_sig_dates_ord <- sort(unique(weights_dt$as_of_date))
sig_to_next_dt <- data.table(
  as_of_date = all_sig_dates_ord[-length(all_sig_dates_ord)],
  next_sig_date = all_sig_dates_ord[-1]
)
sig_to_next_dt[, next_ym := format(next_sig_date, "%Y-%m")]
setkey(sig_to_next_dt, as_of_date)

for (m in methods) {
  cat("[backtest]", m, "\n")
  w_m <- weights_dt[method == m, .(as_of_date, Ticker, weight)]
  w_m <- merge(w_m, sig_to_next_dt[, .(as_of_date, next_ym, next_sig_date)],
                by = "as_of_date", all.x = FALSE)
  # Compute portfolio fwd return per sig_date
  port_rets <- w_m[, {
    nxt_ym <- next_ym[1]
    n_held <- .N
    # Next month return per ticker (geometric monthly return)
    nxt <- monthly[ym == nxt_ym & Ticker %in% Ticker, .(Ticker, monthly_ret)]
    if (nrow(nxt) == 0L) {
      .(port_ret = NA_real_, n_held = n_held, n_matched = 0L,
        next_sig_date = next_sig_date[1])
    } else {
      w_join <- merge(.SD[, .(Ticker, weight)], nxt, by = "Ticker", all.x = TRUE)
      w_join[is.na(monthly_ret), monthly_ret := 0]
      .(port_ret = sum(w_join$weight * w_join$monthly_ret),
        n_held = n_held, n_matched = nrow(nxt),
        next_sig_date = next_sig_date[1])
    }
  }, by = as_of_date]
  port_rets[, method := m]
  port_ret_records[[m]] <- port_rets
}

port_ret_dt <- rbindlist(port_ret_records)
fwrite(port_ret_dt, file.path(STAGE, "optimizer_workspace", "port_ret_long.csv"))
cat(sprintf("[backtest] Port returns saved: %d rows\n", nrow(port_ret_dt)))
cat("[backtest] Mean returns per method (annualized × 12):\n")
print(port_ret_dt[!is.na(port_ret), .(
  n = .N,
  mean_ret = mean(port_ret, na.rm = TRUE),
  ann_ret = mean(port_ret, na.rm = TRUE) * 12,
  sd_ret = sd(port_ret, na.rm = TRUE),
  ann_vol = sd(port_ret, na.rm = TRUE) * sqrt(12),
  arith_SR = mean(port_ret, na.rm = TRUE) * 12 / (sd(port_ret, na.rm = TRUE) * sqrt(12))
), by = method])

# ─── Compute metrics per method via PerformanceAnalytics ─
# Drop last sig_date (no forward return) + first sig_date (initial)
cat("\n[backtest] Computing PerformanceAnalytics metrics...\n")

metrics_list <- list()
for (m in methods) {
  dt_m <- port_ret_dt[method == m & !is.na(port_ret)]
  setorder(dt_m, as_of_date)
  # Drop first row (initial) and last (no next return)
  # Actually keep first and use proper xts construction
  if (nrow(dt_m) < 24L) {
    cat("  ", m, ": insufficient data\n")
    next
  }
  # xts: indexed by next_sig_date (forward return realized at end of next month)
  next_dates <- as.Date(dt_m$next_sig_date)
  ret_xts <- xts(dt_m$port_ret, order.by = next_dates)
  colnames(ret_xts) <- m
  # remove NA
  ret_xts <- ret_xts[!is.na(coredata(ret_xts))]

  # PerformanceAnalytics standard metrics
  ann_ret_obj <- table.AnnualizedReturns(ret_xts, scale = 12, geometric = TRUE)
  cag    <- as.numeric(ann_ret_obj[1, 1])
  ann_sd <- as.numeric(ann_ret_obj[2, 1])
  sr     <- as.numeric(ann_ret_obj[3, 1])
  # Drawdowns
  dd_xts <- Drawdowns(ret_xts, geometric = TRUE)
  mdd <- maxDrawdown(ret_xts, geometric = TRUE)
  # Sortino
  sortino <- as.numeric(SortinoRatio(ret_xts))
  # Calmar
  calmar <- as.numeric(CalmarRatio(ret_xts, scale = 12))
  # CVaR (monthly)
  cvar95_m <- as.numeric(CVaR(ret_xts, p = 0.95, method = "historical"))
  cvar99_m <- as.numeric(CVaR(ret_xts, p = 0.99, method = "historical"))

  # Total cumulative
  total_cum <- as.numeric(Return.cumulative(ret_xts, geometric = TRUE))

  metrics_list[[m]] <- data.table(
    method = m,
    n_months = nrow(ret_xts),
    Sharpe_PerfA = round(sr, 4),
    MDD_PerfA = round(mdd, 4),
    CAGR_PerfA = round(cag, 4),
    AnnVol_PerfA = round(ann_sd, 4),
    Sortino_PerfA = round(sortino, 4),
    Calmar_PerfA = round(calmar, 4),
    CVaR_95_monthly = round(cvar95_m, 4),
    CVaR_99_monthly = round(cvar99_m, 4),
    Cum_Total_geom = round(total_cum, 4)
  )
  cat(sprintf("  %s: SR %.4f MDD %.4f CAGR %.4f Sortino %.4f Calmar %.4f\n",
              m, sr, mdd, cag, sortino, calmar))
}

metrics_dt <- rbindlist(metrics_list)
fwrite(metrics_dt, file.path(STAGE, "optimizer_workspace", "method_metrics_perfa.csv"))
cat("\n[backtest] Method metrics saved.\n")
print(metrics_dt)
