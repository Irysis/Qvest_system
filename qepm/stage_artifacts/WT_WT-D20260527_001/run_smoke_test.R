#==============================================================================
# DM-TC Smoke Test — 6 sig_dates only (3 bear + 3 normal/bull)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

source("02_Infrastructure/backtest_harness.R")
source("qepm/stage_artifacts/WT_WT-D20260527_001/dm_tc_factor_engine.R")

cat("[STEP 1] Load data...\n")
r <- load_rawdata(use_cache = TRUE)
RAW <- r$RAWDATA
BM <- r$BM_DT
BM[, Date := as.Date(Date)]

RAW <- RAW[Date >= as.Date("2018-01-01") & Date <= as.Date("2024-12-31"),
           .(Date, Ticker, Close, Vol, K200, KQ150,
             AdminStock, TradingHalt, UnfaithfulDisc, Size, Ret)]
setkey(RAW, Date, Ticker)
cat("RAWDATA rows:", nrow(RAW), "\n")

cat("[STEP 2] P4 forecasts + state...\n")
p4 <- load_p4_forecasts()
state_dt <- classify_market_state(p4, min_history = 252L)
cat("State distribution:\n")
print(table(state_dt$state, useNA = "ifany"))

# Pick 6 sample sig_dates
sample_dates <- as.Date(c("2020-02-28", "2020-03-31", "2021-12-31",
                          "2022-09-30", "2023-03-31", "2024-08-30"))

cat("\n[STEP 3] Run α for 6 sample dates sequentially (with time)...\n")
results <- list()
for (sd in sample_dates) {
  sd <- as.Date(sd)
  t0 <- Sys.time()
  a <- tryCatch(
    compute_alpha_vector(RAW, BM, state_dt, sd),
    error = function(e) {message("err: ", e$message); NULL}
  )
  dt_sec <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  state_st <- if (!is.null(a) && nrow(a) > 0) a$S_t[1] else NA_integer_
  n_alpha <- if (!is.null(a)) sum(!is.na(a$alpha)) else 0L
  n_nonzero <- if (!is.null(a)) sum(abs(a$alpha) > 1e-9, na.rm = TRUE) else 0L
  cat(sprintf("%s | state=%s | n_alpha=%d | n_nonzero=%d | time=%.1fs\n",
              sd, state_st, n_alpha, n_nonzero, dt_sec))
  results[[as.character(sd)]] <- a
}

# Show sample
cat("\n[STEP 4] Show top/bottom alpha for 2020-03-31 (bear) and 2021-12-31...\n")
for (key in c("2020-03-31", "2021-12-31")) {
  cat("\n--- sig_date:", key, "---\n")
  a <- results[[key]]
  if (!is.null(a) && nrow(a) > 0) {
    cat("State:", a$S_t[1], " | N tickers:", nrow(a), "\n")
    if (sum(!is.na(a$alpha)) > 0 && sum(abs(a$alpha) > 1e-9) > 0) {
      a_sorted <- a[order(-alpha)]
      cat("Top 5:\n")
      print(head(a_sorted[, .(Ticker, alpha, tail_beta, downside_beta, ltd_proxy, S_t)], 5))
      cat("Bottom 5:\n")
      print(tail(a_sorted[, .(Ticker, alpha, tail_beta, downside_beta, ltd_proxy, S_t)], 5))
    } else {
      cat("All alpha zero (likely state=0 normal).\n")
    }
  }
}

cat("\n========== SMOKE TEST COMPLETE ==========\n")
