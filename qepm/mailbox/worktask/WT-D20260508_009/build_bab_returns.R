## ============================================================================
## WT-D20260508_009 Forge — BAB multi-sleeve stock-level returns reconstruction
## Pure function: weights.csv (196 dates × 15-20 names) → monthly portfolio returns
## NO weight modification — Optimizer schedule as-is
## ============================================================================

suppressMessages({
  library(data.table); library(arrow); library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260508_009")
SA_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT-D20260508_009")
COST_BPS_ONEWAY <- 15

cat("[BAB returns reconstruction] Optimizer weights.csv → monthly portfolio returns\n")

# ─── Load Optimizer weights (Pure Function — as-is) ──────────────────────────
weights <- fread(file.path(SA_DIR, "weights.csv"))
weights[, as_of_date := as.Date(as_of_date)]
schedule_dates <- sort(unique(weights$as_of_date))
cat(sprintf("  weights.csv: %d rows | %d dates (%s ~ %s)\n",
            nrow(weights), length(schedule_dates),
            min(schedule_dates), max(schedule_dates)))

# ─── Load RAWDATA for stock returns ──────────────────────────────────────────
cat("  loading RAWDATA.parquet (~14M rows, may take 30s)...\n")
rd <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/RAWDATA.parquet")))
rd[, Date := as.Date(Date)]
setkey(rd, Ticker, Date)

# ─── For each weights date d, hold weights through next rebalance date ────────
# Compute monthly compounded return for each stock between d and d+1month
# Then portfolio return = Σ w_i * stock_ret_i

# Build holding period boundaries
schedule_dt <- data.table(
  d_start = schedule_dates,
  d_end = c(schedule_dates[-1], max(schedule_dates) + 32)  # last period: ~1 month forward
)

# Helper: monthly cumulative return for a single ticker between [start, end)
# We use Ret column = daily return
all_tickers <- unique(weights$ticker)
cat(sprintf("  unique tickers in weights: %d\n", length(all_tickers)))

# Filter RAWDATA to relevant tickers and date range
rd_sub <- rd[Ticker %in% all_tickers &
             Date >= min(schedule_dates) &
             Date <= max(schedule_dates) + 32,
             .(Ticker, Date, Ret)]
cat(sprintf("  rd_sub: %d rows after filter\n", nrow(rd_sub)))
setkey(rd_sub, Ticker, Date)

# Compute month-by-month returns by joining schedule with stock returns
# For each (ticker, period), compound daily Rets
period_ret_list <- vector("list", nrow(schedule_dt))
for (i in seq_len(nrow(schedule_dt))) {
  d0 <- schedule_dt$d_start[i]
  d1 <- schedule_dt$d_end[i]
  # Holdings as of d0 (rebalance date)
  h_d0 <- weights[as_of_date == d0]
  if (nrow(h_d0) == 0) next
  # Stock returns in (d0, d1] — exclusive of d0 (we hold from t+1)
  rets_d <- rd_sub[Date > d0 & Date <= d1 & Ticker %in% h_d0$ticker]
  if (nrow(rets_d) == 0) next
  # Per-ticker compounded
  per_tick <- rets_d[, .(
    period_ret = prod(1 + Ret, na.rm = TRUE) - 1,
    n_days = .N
  ), by = Ticker]
  # Merge with weights
  pe <- merge(h_d0[, .(Ticker = ticker, weight)], per_tick, by = "Ticker", all.x = TRUE)
  # Tickers with no return data → 0 (delisted / data gap)
  pe[is.na(period_ret), period_ret := 0]
  pe[is.na(n_days), n_days := 0]
  # Portfolio period return
  port_ret <- sum(pe$weight * pe$period_ret)
  # Turnover (vs prior period)
  if (i > 1) {
    h_prev <- weights[as_of_date == schedule_dt$d_start[i-1]]
    # Drift weights forward to d0 (multiply by 1+period_ret of prior, normalize)
    # Simpler: realized turnover = sum |w_t - w_{t-1}| / 2 (no drift adjustment, as Optimizer reports raw turnover)
    all_t <- union(h_d0$ticker, h_prev$ticker)
    w_now <- merge(data.table(ticker = all_t), h_d0[, .(ticker, w_now = weight)], by = "ticker", all.x = TRUE)
    w_now[is.na(w_now), w_now := 0]
    w_prev <- merge(w_now, h_prev[, .(ticker, w_prev = weight)], by = "ticker", all.x = TRUE)
    w_prev[is.na(w_prev), w_prev := 0]
    to <- sum(abs(w_prev$w_now - w_prev$w_prev)) / 2
  } else {
    to <- 1.0  # initial establishment
  }
  period_ret_list[[i]] <- data.table(
    rebal_date = d0,
    next_date = d1,
    n_days = mean(per_tick$n_days),
    n_holdings = nrow(h_d0),
    sum_w = sum(h_d0$weight),
    period_ret_gross = port_ret,
    turnover_one_way = to
  )
}

period_ret_dt <- rbindlist(period_ret_list[!sapply(period_ret_list, is.null)], fill = TRUE)
cat(sprintf("  computed %d period returns\n", nrow(period_ret_dt)))

# Apply cost: net = gross - turnover * 15bps
period_ret_dt[, cost_ret := turnover_one_way * (COST_BPS_ONEWAY / 10000)]
period_ret_dt[, period_ret_net := period_ret_gross - cost_ret]

# Save
fwrite(period_ret_dt, file.path(SA_DIR, "forge/bab_period_returns.csv"))
cat(sprintf("  saved: %s\n", file.path(SA_DIR, "forge/bab_period_returns.csv")))

# Quick sanity stats
cat("\n[BAB Standalone Stats — Optimizer weights as-is, monthly]\n")
n <- nrow(period_ret_dt)
mean_ret <- mean(period_ret_dt$period_ret_net)
sd_ret <- sd(period_ret_dt$period_ret_net)
sr_ann <- mean_ret / sd_ret * sqrt(12)
cagr <- prod(1 + period_ret_dt$period_ret_net)^(12/n) - 1
nav <- cumprod(1 + period_ret_dt$period_ret_net)
mdd <- min(nav / cummax(nav) - 1)
to_ann <- mean(period_ret_dt$turnover_one_way[-1]) * 12 * 2  # round-trip annualized

cat(sprintf("  n_periods: %d (months)\n", n))
cat(sprintf("  mean monthly net ret: %.4f%%\n", mean_ret * 100))
cat(sprintf("  std monthly net ret: %.4f%%\n", sd_ret * 100))
cat(sprintf("  Sharpe (annualized): %.4f\n", sr_ann))
cat(sprintf("  CAGR: %.4f%%\n", cagr * 100))
cat(sprintf("  MDD: %.4f%%\n", mdd * 100))
cat(sprintf("  Realized turnover round-trip annualized: %.2f%% (Optimizer reported 1037%%)\n", to_ann * 100))
cat(sprintf("  TO Hurdle 600%% breach: %s\n", to_ann > 6.0))
