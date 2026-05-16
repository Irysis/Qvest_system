#!/usr/bin/env Rscript
# WT-D20260514_009 Step 1: Build training panel = features_master JOIN forward returns
# PIT C1: sig_date 기준 t → t+1 month forward return 측정.
# PIT C2: features 이미 t-1 lag 적용 inherit (Layer A/C는 monthly snapshot t-end pre-rebalance).
#
# Forward return spec:
#   - ret_1m_fwd[i, sig_date] = compound (1+ret_t+1d) over [sig_date+1, sig_date+1M]
#   - benchmark adjusted via BM_Ret -> active return for OOS perf if needed
#   - drop tickers with missing return path (corporate action / delisting)

suppressMessages({
  library(arrow); library(data.table); library(dplyr); library(lubridate)
})

WT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(WT_ROOT)
OUT_DIR <- "stage_artifacts/WT_D20260514_009"
dir.create(OUT_DIR, showWarnings=FALSE, recursive=TRUE)

cat("=== Step 1: Build training panel ===\n")
t0 <- Sys.time()

# --- Load features_master (1,044 features + sig_date + Ticker + Sector_Lv2) ---
cat("[1/4] Loading features_master.parquet...\n")
fm <- open_dataset("stage_artifacts/WT_D20260514_008/features_master.parquet")
features_df <- fm %>% collect() %>% as.data.table()
cat(sprintf("  features_master: %s rows × %s cols\n", format(nrow(features_df), big.mark=","), ncol(features_df)))
setkey(features_df, sig_date, Ticker)

# --- Load RAWDATA daily, build monthly forward returns ---
cat("[2/4] Loading rawdata.parquet + compute monthly forward returns...\n")
rd <- open_dataset(".cache/rawdata.parquet")

# universe = unique Tickers in features panel + relevant Date range
ticker_set <- unique(features_df$Ticker)
date_min <- as.Date(min(features_df$sig_date)) - 5  # buffer
date_max <- as.Date(max(features_df$sig_date)) + 45  # need next month return

raw_df <- rd %>%
  filter(Date >= date_min, Date <= date_max, Ticker %in% ticker_set) %>%
  select(Date, Ticker, Ret, BM_Ret) %>%
  collect() %>% as.data.table()
raw_df[, Date := as.Date(Date)]
raw_df[, Ret := as.numeric(Ret)]
raw_df[, BM_Ret := as.numeric(BM_Ret)]
setkey(raw_df, Ticker, Date)
cat(sprintf("  rawdata filtered: %s rows × %s tickers × %s days\n",
            format(nrow(raw_df), big.mark=","), uniqueN(raw_df$Ticker), uniqueN(raw_df$Date)))

# --- Build monthly forward returns ---
# For each sig_date d, compute compound return from d+1 trading day to next month-end (= d + ~21 trading days)
# Use month-end-of-next-month definition for consistency.
sig_dates <- sort(unique(as.Date(features_df$sig_date)))
cat("  sig_dates:", length(sig_dates), "from", as.character(min(sig_dates)), "to", as.character(max(sig_dates)), "\n")

# For each sig_date pair (d_t, d_{t+1}), return path = (d_t < Date <= d_{t+1}]
# Last sig_date has no forward (set NA, will be dropped from training but kept for inference)
compute_fwd_returns <- function(raw_df, sig_dates) {
  out_list <- list()
  for (i in seq_along(sig_dates)) {
    d_t <- sig_dates[i]
    if (i == length(sig_dates)) {
      # last sig_date: define forward as next 21 trading days from raw_df
      d_next <- max(raw_df$Date, na.rm=TRUE)
      if (d_next <= d_t) next
      d_next <- min(d_next, d_t + days(35))  # cap at 35 cal days
    } else {
      d_next <- sig_dates[i+1]
    }
    sub <- raw_df[Date > d_t & Date <= d_next]
    if (nrow(sub) == 0) next
    # compound by Ticker
    agg <- sub[!is.na(Ret), .(
      ret_1m_fwd = prod(1 + Ret, na.rm=TRUE) - 1,
      bm_ret_1m_fwd = prod(1 + BM_Ret, na.rm=TRUE) - 1,
      n_days_fwd = .N
    ), by = Ticker]
    agg[, sig_date := d_t]
    out_list[[i]] <- agg
    if (i %% 20 == 0) cat(sprintf("    sig_date %d/%d (%s): %d tickers\n", i, length(sig_dates), as.character(d_t), nrow(agg)))
  }
  rbindlist(out_list, use.names=TRUE, fill=TRUE)
}

fwd_dt <- compute_fwd_returns(raw_df, sig_dates)
cat(sprintf("  forward returns: %s rows\n", format(nrow(fwd_dt), big.mark=",")))
# Filter: need at least 15 trading days for valid forward
fwd_dt <- fwd_dt[n_days_fwd >= 15]
cat(sprintf("  after n_days_fwd>=15 filter: %s rows\n", format(nrow(fwd_dt), big.mark=",")))

# Add active return
fwd_dt[, active_ret_1m_fwd := ret_1m_fwd - bm_ret_1m_fwd]

# Winsorize forward returns at 1%/99% to reduce extreme outliers (corporate action / data error)
qlo <- quantile(fwd_dt$ret_1m_fwd, 0.01, na.rm=TRUE)
qhi <- quantile(fwd_dt$ret_1m_fwd, 0.99, na.rm=TRUE)
cat(sprintf("  ret_1m_fwd winsorize at 1%%-99%% = [%.4f, %.4f]\n", qlo, qhi))
fwd_dt[, ret_1m_fwd_w := pmin(pmax(ret_1m_fwd, qlo), qhi)]

# --- Merge features + forward returns ---
cat("[3/4] Merging features + forward returns...\n")
features_df[, sig_date := as.Date(sig_date)]
fwd_dt[, sig_date := as.Date(sig_date)]
setkey(features_df, sig_date, Ticker)
setkey(fwd_dt, sig_date, Ticker)

panel <- merge(features_df, fwd_dt, by=c("sig_date","Ticker"), all.x=TRUE)
cat(sprintf("  panel: %s rows × %s cols\n", format(nrow(panel), big.mark=","), ncol(panel)))
cat(sprintf("  rows with target ret_1m_fwd: %s (%.1f%%)\n",
            format(sum(!is.na(panel$ret_1m_fwd_w)), big.mark=","),
            100 * mean(!is.na(panel$ret_1m_fwd_w))))

# --- Save ---
cat("[4/4] Saving training_panel.parquet...\n")
out_path <- file.path(OUT_DIR, "training_panel.parquet")
write_parquet(panel, out_path)
cat(sprintf("  saved: %s (%.1f MB)\n", out_path, file.size(out_path)/1024^2))

# Diagnostics
diag_summary <- list(
  task_id = "WT-D20260514_009",
  step = "step1_build_training_panel",
  panel_rows = nrow(panel),
  panel_cols = ncol(panel),
  feature_cols = ncol(features_df) - 3,  # exclude sig_date, Ticker, Sector_Lv2
  target_col = "ret_1m_fwd_w (winsorized 1%-99%)",
  unique_sig_dates = uniqueN(panel$sig_date),
  unique_tickers = uniqueN(panel$Ticker),
  rows_with_target = sum(!is.na(panel$ret_1m_fwd_w)),
  target_coverage_pct = round(100 * mean(!is.na(panel$ret_1m_fwd_w)), 2),
  winsorize_bounds = c(qlo, qhi),
  date_range = c(as.character(min(panel$sig_date)), as.character(max(panel$sig_date))),
  built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)
jsonlite::write_json(diag_summary, file.path(OUT_DIR, "step1_diagnostics.json"),
                     auto_unbox=TRUE, pretty=TRUE)

cat(sprintf("\n=== Step 1 DONE (%.1f min) ===\n", as.numeric(difftime(Sys.time(), t0, units="mins"))))
