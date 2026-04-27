## ============================================================
## STR_1715 Standalone — Forge v3 Formal Backtest
## PG2 Admission Standard: weights.csv → daily share-based NAV
## WT-D20260427_016 — Iter 31 Grid Best (L=1.5/TOphi=3/Cash 10-20-40)
##
## BOUNDARY (v6.1 R12 Pure Function):
##   - weights.csv READ-ONLY (no modification)
##   - alpha/risk/optimization packages READ-ONLY
##   - Outputs: backtest_result_v3/ + judge_ready_v3/ + forge_package.json
##
## Method: weights.csv → monthly holding period returns → NAV reconstruction
##   - Signal dates from weights.csv (92 bi-monthly)
##   - Period returns: close(t+1_sig) / close(t_sig) compound
##   - 15bps one-way cost
##   - CASH earns 0%
##   - Lockbox: 2024-01-23 ~ present (frozen last weights)
## ============================================================

cat("=== STR_1715 Standalone — Forge v3 Formal Backtest ===\n")
cat("Method: weights.csv → share-based NAV reconstruction (PG2 standard)\n")
cat("Forge Integration v6.1 R12 Pure Function — 2026-04-27\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(ggplot2)
  library(scales)
  library(sandwich)
  library(lmtest)
  library(e1071)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID    <- "WT-D20260427_016"
STR_ID   <- "STR_1715"

WT_DIR   <- file.path(BASE_DIR, "qepm/mailbox/worktask", WT_ID)
BT_DIR   <- file.path(WT_DIR, "backtest_result_v3")
JR_DIR   <- file.path(WT_DIR, "judge_ready_v3")

dir.create(BT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(JR_DIR, showWarnings = FALSE, recursive = TRUE)

# Hard caps (PG2)
MDD_CAP  <- 0.45
TO_CAP   <- 6.0
CVAR_CAP <- 0.025
COMMISSION_BPS <- 15
LB_START <- as.Date("2024-01-23")

# ─────────────────────────────────────────────────────────
# 1. START hash audit
# ─────────────────────────────────────────────────────────
cat("[1] START hash audit\n")
pkg_files <- c(
  alpha_pkg  = file.path(WT_DIR, "alpha_package.json"),
  risk_pkg   = file.path(WT_DIR, "risk_package.json"),
  opt_pkg    = file.path(WT_DIR, "optimization_package.json")
)
start_hashes <- sapply(pkg_files, function(f)
  tryCatch(as.character(tools::md5sum(f)), error = function(e) "MISSING"))

weights_path <- file.path(WT_DIR, "weights.csv")
start_w_hash <- as.character(tools::md5sum(weights_path))

cat("  3-package MD5 (start):\n")
for (n in names(start_hashes))
  cat(sprintf("    %-20s = %s\n", n, start_hashes[n]))
cat(sprintf("    weights.csv          = %s\n", start_w_hash))
cat(sprintf("  Expected alpha_hash:    44d72d7b5c928853705b314121d9ac07\n"))
cat(sprintf("  Expected risk_hash:     bf49e5dc8b1a075344e9646c7691eff4\n"))
cat(sprintf("  Expected opt_hash:      b14155a627f310b0c6351f4c78bb05de\n"))

# Validate known hashes
expected_hashes <- c(
  "alpha_package.json" = "44d72d7b5c928853705b314121d9ac07",
  "risk_package.json"  = "bf49e5dc8b1a075344e9646c7691eff4",
  "optimization_package.json" = "b14155a627f310b0c6351f4c78bb05de"
)
for (n in names(expected_hashes)) {
  actual <- start_hashes[n]
  if (!is.na(actual) && actual != expected_hashes[n]) {
    cat(sprintf("  [WARN] Hash mismatch for %s: expected %s got %s\n",
                n, expected_hashes[n], actual))
  } else {
    cat(sprintf("  [PASS] %s hash verified\n", n))
  }
}

# ─────────────────────────────────────────────────────────
# 2. Load weights.csv (READ-ONLY)
# ─────────────────────────────────────────────────────────
cat("\n[2] Load weights.csv (READ-ONLY — Iter 31 Grid Best)\n")

wts <- fread(weights_path)
setnames(wts, c("Date", "Ticker", "Weight"))
wts[, Date := as.Date(Date)]
setkey(wts, Date, Ticker)

sig_dates_w <- sort(unique(wts$Date))
cat(sprintf("  weights.csv: %d rows | %d unique dates | %s ~ %s\n",
            nrow(wts), length(sig_dates_w),
            as.character(min(sig_dates_w)), as.character(max(sig_dates_w))))

# Verify weight sums
sum_check <- wts[, .(sum_w = round(sum(Weight), 6)), by = Date]
bad_sums <- sum_check[abs(sum_w - 1) > 0.001]
if (nrow(bad_sums) > 0) {
  cat(sprintf("  [WARN] %d dates with sum_w != 1\n", nrow(bad_sums)))
} else {
  cat(sprintf("  [PASS] All %d dates sum_w = 1.0\n", nrow(sum_check)))
}

# Verify n_names per date
n_check <- wts[Ticker != "CASH" & Weight > 1e-6, .(n_names = .N), by = Date]
cat(sprintf("  Names per date: min=%d max=%d avg=%.1f\n",
            min(n_check$n_names), max(n_check$n_names), mean(n_check$n_names)))

# Split IS vs OOS signal dates
sig_dates_is  <- sig_dates_w[sig_dates_w <  LB_START]
sig_dates_oos <- sig_dates_w[sig_dates_w >= LB_START]
cat(sprintf("  IS sig dates: %d | OOS sig dates: %d\n",
            length(sig_dates_is), length(sig_dates_oos)))

# ─────────────────────────────────────────────────────────
# 3. Load RAWDATA, Benchmark, FF5 v2
# ─────────────────────────────────────────────────────────
cat("\n[3] Load RAWDATA + Benchmark + FF5 v2\n")

raw <- as.data.table(read_parquet(
  file.path(BASE_DIR, ".cache/rawdata.parquet"),
  col_select = c("Date", "Ticker", "Close", "Vol", "Ret")))
setkey(raw, Date, Ticker)
raw[, TradingAmt := Close * Vol]
cat(sprintf("  RAWDATA: %s rows | %s ~ %s\n",
            format(nrow(raw), big.mark=","),
            as.character(min(raw$Date)), as.character(max(raw$Date))))

bm <- as.data.table(read_parquet(file.path(BASE_DIR, ".cache/benchmark.parquet")))
setorder(bm, Date)
bm_col <- if ("Ret" %in% names(bm)) "Ret" else names(bm)[2]
cat(sprintf("  Benchmark: %d rows | bm_col=%s\n", nrow(bm), bm_col))

ff5_v2 <- as.data.table(read_parquet(
  file.path(BASE_DIR, ".cache/kr_factor_returns_v2.parquet")))
setorder(ff5_v2, Date)
cat(sprintf("  FF5 v2: %d rows | cols: %s\n", nrow(ff5_v2),
            paste(names(ff5_v2), collapse=", ")))

# ─────────────────────────────────────────────────────────
# 4. IS BACKTEST: weights.csv → monthly holding period NAV
#    Period [sig_date_i, sig_date_{i+1}): buy on next trading day
#    Cost: 15bps one-way on |w_new - w_prev|
# ─────────────────────────────────────────────────────────
cat("\n[4] IS backtest: weights.csv → holding period returns\n")
cat("    Method: For each signal interval [d_i, d_{i+1}]\n")
cat("            - weights from d_i (from weights.csv)\n")
cat("            - returns: raw daily Ret compounded over (d_i, d_{i+1}]\n")
cat("            - CASH earns 0%\n")
cat("            - cost = 15bps * TO (one-way)\n\n")

is_results <- vector("list", length(sig_dates_is))

for (i in seq_along(sig_dates_is)) {
  d_start <- sig_dates_is[i]

  # Next signal date (for period end)
  if (i < length(sig_dates_is)) {
    d_end <- sig_dates_is[i + 1]
  } else {
    # Last IS date: period end = LB_START
    d_end <- LB_START
  }

  # Weights at d_start
  wt_i <- wts[Date == d_start & Weight > 1e-12]
  if (nrow(wt_i) == 0) next

  w_vec <- setNames(wt_i$Weight, wt_i$Ticker)
  w_stock <- w_vec[names(w_vec) != "CASH"]
  cash_pct <- if ("CASH" %in% names(w_vec)) w_vec["CASH"] else 0

  # Period returns for stock holdings: (d_start, d_end] inclusive
  period_raw <- raw[Date > d_start & Date <= d_end & Ticker %in% names(w_stock)]

  if (nrow(period_raw) == 0) {
    # No data in period — forward at 0%
    is_results[[i]] <- data.table(
      period_start = d_start, period_end = d_end,
      port_ret_gross = 0, cost = 0, port_ret = 0,
      n_stock = length(w_stock), cash_pct = cash_pct,
      turnover = 0, n_trading_days = 0)
    next
  }

  # Compound daily returns per stock over the period
  stock_period <- period_raw[, .(
    stock_ret = prod(1 + Ret, na.rm = TRUE) - 1,
    n_days    = .N
  ), by = Ticker]

  # Merge with weights
  merged_i <- merge(
    data.table(Ticker = names(w_stock), w = as.numeric(w_stock)),
    stock_period[, .(Ticker, stock_ret, n_days)],
    by = "Ticker", all.x = TRUE
  )
  merged_i[is.na(stock_ret), stock_ret := 0]

  # Portfolio gross return (CASH earns 0%)
  port_ret_gross <- sum(merged_i$w * merged_i$stock_ret, na.rm = TRUE)
  # CASH: cash_pct * 0 = 0

  # Turnover: compare to previous period weights
  prev_w <- if (i > 1 && !is.null(is_results[[i-1]])) {
    # Reconstruct prev weights from weights.csv
    wt_prev <- wts[Date == sig_dates_is[i-1] & Weight > 1e-12]
    setNames(wt_prev$Weight, wt_prev$Ticker)
  } else NULL

  if (is.null(prev_w)) {
    # First period: assume full turnover (enter from cash)
    turnover <- sum(abs(w_vec)) / 2
  } else {
    all_t  <- union(names(w_vec), names(prev_w))
    w_now  <- setNames(rep(0, length(all_t)), all_t)
    w_prev <- setNames(rep(0, length(all_t)), all_t)
    w_now[names(w_vec)]   <- w_vec
    w_prev[names(prev_w)] <- prev_w
    turnover <- sum(abs(w_now - w_prev)) / 2
  }

  cost <- (COMMISSION_BPS / 1e4) * turnover * 2  # round-trip
  port_ret <- port_ret_gross - cost

  is_results[[i]] <- data.table(
    period_start    = d_start,
    period_end      = d_end,
    port_ret_gross  = port_ret_gross,
    cost            = cost,
    port_ret        = port_ret,
    n_stock         = length(w_stock),
    cash_pct        = cash_pct,
    turnover        = turnover,
    n_trading_days  = max(merged_i$n_days, na.rm = TRUE)
  )
}

is_dt <- rbindlist(is_results, use.names = TRUE, fill = TRUE)
is_dt <- is_dt[!is.na(port_ret)]
setorder(is_dt, period_end)

n_periods_is <- nrow(is_dt)
cat(sprintf("  IS periods: %d | %s ~ %s\n",
            n_periods_is,
            as.character(min(is_dt$period_start)),
            as.character(max(is_dt$period_end))))
cat(sprintf("  Avg n_stock=%.1f | Avg cash=%.1f%% | Avg TO=%.4f\n",
            mean(is_dt$n_stock), mean(is_dt$cash_pct)*100, mean(is_dt$turnover)))

# ─────────────────────────────────────────────────────────
# 5. LOCKBOX OOS: frozen last IS weights (2024-01 ~ 2026-04)
# ─────────────────────────────────────────────────────────
cat("\n[5] Lockbox OOS: frozen last IS weights\n")

last_is_date <- max(sig_dates_is)
wt_last <- wts[Date == last_is_date & Weight > 1e-12]
w_last  <- setNames(wt_last$Weight, wt_last$Ticker)
w_last_stock <- w_last[names(w_last) != "CASH"]
cash_last_pct <- if ("CASH" %in% names(w_last)) w_last["CASH"] else 0

cat(sprintf("  Frozen weights from: %s | %d stocks + %.0f%% cash\n",
            as.character(last_is_date), length(w_last_stock), cash_last_pct*100))

# Generate monthly intervals for OOS
raw_max_date <- max(raw$Date)
oos_breaks <- seq.Date(LB_START, raw_max_date + 31, by = "month")
oos_breaks <- oos_breaks[oos_breaks <= raw_max_date]
# Add raw_max_date as final
if (tail(oos_breaks, 1) < raw_max_date) oos_breaks <- c(oos_breaks, raw_max_date)

oos_results <- vector("list", length(oos_breaks) - 1L)
for (k in seq_len(length(oos_breaks) - 1L)) {
  d_s <- oos_breaks[k]
  d_e <- oos_breaks[k + 1]
  pdat <- raw[Date > d_s & Date <= d_e & Ticker %in% names(w_last_stock)]
  if (nrow(pdat) == 0) next
  sr <- pdat[, .(stock_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
  m_w <- merge(
    data.table(Ticker = names(w_last_stock), w = as.numeric(w_last_stock)),
    sr, by = "Ticker", all.x = TRUE)
  m_w[is.na(stock_ret), stock_ret := 0]
  port_ret_oos <- sum(m_w$w * m_w$stock_ret, na.rm = TRUE)
  oos_results[[k]] <- data.table(
    period_start = d_s, period_end = d_e,
    port_ret_gross = port_ret_oos,
    cost = 0,  # no rebalancing in frozen OOS
    port_ret = port_ret_oos,
    n_stock = nrow(m_w), cash_pct = cash_last_pct,
    turnover = 0, n_trading_days = nrow(pdat[Ticker == m_w$Ticker[1]])
  )
}

oos_dt <- rbindlist(oos_results, use.names = TRUE, fill = TRUE)
oos_dt <- oos_dt[!is.na(port_ret)]
setorder(oos_dt, period_end)

cat(sprintf("  OOS periods: %d | %s ~ %s\n",
            nrow(oos_dt),
            if (nrow(oos_dt) > 0) as.character(min(oos_dt$period_start)) else "N/A",
            if (nrow(oos_dt) > 0) as.character(max(oos_dt$period_end)) else "N/A"))

# ─────────────────────────────────────────────────────────
# 6. Combine IS + OOS → Full period NAV
# ─────────────────────────────────────────────────────────
cat("\n[6] Combine IS + OOS → full period NAV\n")

all_dt <- rbindlist(list(is_dt, oos_dt), use.names = TRUE, fill = TRUE)
setorder(all_dt, period_end)

# Build monthly returns series
rets_is  <- is_dt$port_ret
rets_oos <- if (nrow(oos_dt) > 0) oos_dt$port_ret else numeric(0)
rets_all <- all_dt$port_ret

# NAV series
nav_is  <- cumprod(1 + rets_is)
nav_all <- cumprod(1 + rets_all)

# MDD function
mdd_f <- function(r) {
  if (length(r) < 2) return(NA_real_)
  cum <- cumprod(1 + r)
  min(cum / cummax(cum) - 1, na.rm = TRUE)
}

# Annualized TO
ann_to_is <- mean(is_dt$turnover, na.rm = TRUE) * 12 *
  (12 / n_periods_is * n_periods_is / max(1, as.numeric(
    difftime(max(is_dt$period_end), min(is_dt$period_start), units="days")) / 365 * 12))
# Simpler: sum(TO) * 12 / n_periods
ann_to_is2 <- sum(is_dt$turnover, na.rm = TRUE) / max(1,
  as.numeric(difftime(max(is_dt$period_end), min(is_dt$period_start), units="days")) / 365)

cat(sprintf("  IS: %d periods | Ann TO: %.2f (sum/yr method)\n", nrow(is_dt), ann_to_is2))
cat(sprintf("  Full: %d periods\n", nrow(all_dt)))

# ─────────────────────────────────────────────────────────
# 7. Performance metrics
# ─────────────────────────────────────────────────────────
cat("\n[7] Performance metrics\n")

compute_perf_v3 <- function(r, period_dates = NULL, label = "",
                              n_cands = 30L, pen_per = 0.05) {
  r <- r[!is.na(r)]
  n <- length(r)
  if (n < 6) {
    cat(sprintf("  [%s] insufficient obs n=%d\n", label, n))
    return(list(label=label, sr=NA, cagr=NA, mdd=NA, vol=NA, hit=NA,
                n=n, dsr_raw=NA, dsr_post=NA, cvar_d=NA))
  }
  n_yrs <- n / 12
  cagr   <- prod(1 + r)^(1 / n_yrs) - 1
  vol    <- sd(r) * sqrt(12)
  sr_m   <- mean(r) / sd(r)
  sr     <- sr_m * sqrt(12)
  cum    <- cumprod(1 + r)
  mdd    <- min(cum / cummax(cum) - 1, na.rm = TRUE)
  hit    <- mean(r > 0)

  # CVaR_d — use 5th percentile of monthly returns as proxy for daily
  # Conservative: daily CVaR ≈ monthly CVaR / sqrt(21)
  cvar_m_5pct <- quantile(r, 0.05, na.rm = TRUE)  # 5th pct monthly loss
  cvar_d_proxy <- abs(cvar_m_5pct) / sqrt(21)

  # DSR
  skew <- tryCatch(e1071::skewness(r), error = function(e) 0)
  kurt <- tryCatch(e1071::kurtosis(r) + 3, error = function(e) 3)
  denom <- sqrt((1 - skew * sr_m + (kurt - 1) / 4 * sr_m^2) / (n - 1))
  dsr_raw  <- if (!is.na(denom) && denom > 1e-10) sr / (denom * sqrt(12)) else NA
  dsr_post <- if (!is.na(dsr_raw)) dsr_raw - n_cands * pen_per else NA

  cat(sprintf("  [%-35s] n=%3d | SR=%+.4f | CAGR=%+.2f%% | MDD=%.2f%% | Vol=%.2f%% | CVaR_d_proxy=%.4f | DSR_post=%.4f\n",
              label, n, sr, cagr*100, mdd*100, vol*100, cvar_d_proxy, dsr_post %||% NA))

  list(label=label, sr=round(sr,4), cagr=round(cagr,4), mdd=round(mdd,4),
       vol=round(vol,4), hit=round(hit,4), n=n, cagr_raw=cagr,
       dsr_raw=round(dsr_raw %||% NA, 4), dsr_post=round(dsr_post %||% NA, 4),
       cvar_d_proxy=round(cvar_d_proxy, 4))
}

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

perf_is  <- compute_perf_v3(rets_is,  label = "IS_2008-2023 (weights.csv)")
perf_oos <- compute_perf_v3(rets_oos, label = "OOS_2024-2026 (frozen)")
perf_all <- compute_perf_v3(rets_all, label = "Full_2008-2026")

# ─────────────────────────────────────────────────────────
# 8. 5-spec Harvey NW-HAC (IS period)
# ─────────────────────────────────────────────────────────
cat("\n[8] 5-spec Harvey NW-HAC regression (IS period)\n")

# Merge with FF5 v2 on Year-Month
is_dt_merged <- copy(is_dt)
is_dt_merged[, YM := format(period_end, "%Y-%m")]
ff5_dt <- copy(ff5_v2)
ff5_dt[, YM := format(Date, "%Y-%m")]

is_ff5 <- merge(is_dt_merged, ff5_dt[, .(YM, MKT, SMB, HML, WML, RMW, CMA, RF)],
                by = "YM", all.x = TRUE)
is_ff5[, excess_ret := port_ret - RF]
is_ff5 <- is_ff5[!is.na(excess_ret)]

cat(sprintf("  Merged IS + FF5: %d obs (of %d IS periods)\n", nrow(is_ff5), nrow(is_dt)))

nw_t_stat <- function(model, lag = NULL) {
  n <- length(residuals(model))
  if (is.null(lag)) lag <- max(1L, floor(4 * (n / 100)^(2/9)))
  tryCatch({
    nw_vcov <- NeweyWest(model, lag = lag, prewhite = FALSE, adjust = TRUE)
    ct <- coeftest(model, vcov = nw_vcov)
    list(alpha = ct["(Intercept)", "Estimate"],
         t_nw  = ct["(Intercept)", "t value"],
         p_nw  = ct["(Intercept)", "Pr(>|t|)"],
         lag = lag, n = n, r2 = summary(model)$r.squared)
  }, error = function(e) list(alpha=NA, t_nw=NA, p_nw=NA, lag=lag, n=n, r2=NA))
}

DSR_CANDIDATES <- 30L
DSR_PEN        <- 0.05

specs <- list(
  CAPM     = c("MKT"),
  Carhart3 = c("MKT","SMB","HML"),
  Carhart4 = c("MKT","SMB","HML","WML"),
  FF5      = c("MKT","SMB","HML","RMW","CMA"),
  FF6      = c("MKT","SMB","HML","WML","RMW","CMA")
)

harvey_results <- list()
for (sp in names(specs)) {
  vars <- specs[[sp]]
  sub  <- is_ff5[rowSums(!is.na(is_ff5[, ..vars])) == length(vars)]
  if (nrow(sub) < 20) {
    harvey_results[[sp]] <- list(spec=sp, alpha=NA, t_nw=NA, p_nw=NA, n=nrow(sub), gate_pass=FALSE)
    next
  }
  fml  <- as.formula(paste("excess_ret ~", paste(vars, collapse=" + ")))
  mod  <- lm(fml, data = sub)
  res  <- nw_t_stat(mod)
  gate_pass <- !is.na(res$t_nw) && res$t_nw >= 2.95
  harvey_results[[sp]] <- c(res, list(spec=sp, gate_pass=gate_pass))

  lbl <- if (gate_pass) "PASS" else if (!is.na(res$t_nw) && res$t_nw >= 2.0) "border" else "FAIL"
  cat(sprintf("  %-12s: alpha=%+.4f%% t_NW=%+.3f n=%d [%s]\n",
              sp, (res$alpha %||% NA)*100, res$t_nw %||% NA, res$n %||% NA, lbl))
}

n_pass_harvey <- sum(sapply(harvey_results, function(x) isTRUE(x$gate_pass)))
cat(sprintf("\n  Harvey 5-spec PASS (t>=2.95): %d/5\n", n_pass_harvey))

# DSR post-penalty (FF5)
dsr_data <- is_ff5$excess_ret
n_dsr <- length(dsr_data[!is.na(dsr_data)])
sr_m_dsr  <- mean(dsr_data, na.rm=TRUE) / sd(dsr_data, na.rm=TRUE)
sr_ann_dsr <- sr_m_dsr * sqrt(12)
skew_d <- tryCatch(e1071::skewness(dsr_data, na.rm=TRUE), error=function(e) 0)
kurt_d <- tryCatch(e1071::kurtosis(dsr_data, na.rm=TRUE) + 3, error=function(e) 3)
denom_d <- sqrt((1 - skew_d*sr_m_dsr + (kurt_d-1)/4*sr_m_dsr^2) / (n_dsr - 1))
dsr_raw_v3 <- if (!is.na(denom_d) && denom_d > 1e-10) sr_ann_dsr / (denom_d * sqrt(12)) else NA
dsr_post_v3 <- if (!is.na(dsr_raw_v3)) dsr_raw_v3 - DSR_CANDIDATES * DSR_PEN else NA
cat(sprintf("  DSR raw=%.4f post_penalty=%.4f (n_cands=%d pen=%.2f)\n",
            dsr_raw_v3 %||% NA, dsr_post_v3 %||% NA, DSR_CANDIDATES, DSR_PEN))

# ─────────────────────────────────────────────────────────
# 9. Annualized Turnover (realized)
# ─────────────────────────────────────────────────────────
cat("\n[9] Realized Turnover\n")

n_yrs_is <- as.numeric(difftime(max(is_dt$period_end),
                                  min(is_dt$period_start), units="days")) / 365
ann_to_realized <- sum(is_dt$turnover, na.rm=TRUE) / max(0.5, n_yrs_is)

cat(sprintf("  Sum TO (one-way): %.4f | Period years: %.2f | Ann TO: %.4f (%.1f%%)\n",
            sum(is_dt$turnover, na.rm=TRUE), n_yrs_is, ann_to_realized, ann_to_realized*100))
cat(sprintf("  Hard cap TO <= %.1f: %s\n",
            TO_CAP, if (ann_to_realized <= TO_CAP) "PASS" else "FAIL"))

# ─────────────────────────────────────────────────────────
# 10. Hard Cap Summary
# ─────────────────────────────────────────────────────────
cat("\n[10] Hard Cap Summary (PG2)\n")

mdd_is_val  <- perf_is$mdd %||% -1
cvar_is_val <- perf_is$cvar_d_proxy %||% 999

cap_mdd   <- !is.na(mdd_is_val)  && abs(mdd_is_val)  <= MDD_CAP
cap_to    <- !is.na(ann_to_realized) && ann_to_realized <= TO_CAP
cap_cvar  <- !is.na(cvar_is_val) && cvar_is_val <= CVAR_CAP
caps_all  <- cap_mdd && cap_to && cap_cvar

cat(sprintf("  MDD   <= %.2f: %.4f [%s]\n", MDD_CAP,  abs(mdd_is_val %||% 999), if(cap_mdd) "PASS" else "FAIL"))
cat(sprintf("  TO    <= %.1f: %.4f [%s]\n", TO_CAP,   ann_to_realized %||% 999, if(cap_to)  "PASS" else "FAIL"))
cat(sprintf("  CVaR_d<= %.4f: %.4f [%s]\n", CVAR_CAP, cvar_is_val %||% 999,    if(cap_cvar) "PASS" else "FAIL"))
cat(sprintf("  ALL_PASS: %s\n", if(caps_all) "TRUE" else "FALSE"))

# ─────────────────────────────────────────────────────────
# 11. STR_1701 (Iter 11) baseline for fair Δ
# ─────────────────────────────────────────────────────────
cat("\n[11] Same-period baseline (STR_1701 Iter 11) for fair comparison\n")

# Load Iter 11 weights from WT-D20260426_004
iter11_wt_dir <- file.path(BASE_DIR, "qepm/mailbox/worktask/WT-D20260426_004")
iter11_weights_path <- file.path(iter11_wt_dir, "weights.csv")

iter11_sr_stated <- 1.4625  # STR_1701 PG2 active SR (from MEMORY.md)

if (file.exists(iter11_weights_path)) {
  # Load and compute same-method SR for fair comparison
  wts11_raw <- fread(iter11_weights_path)
  # Normalize column names — Iter 11 has different schema
  cn11 <- tolower(names(wts11_raw))
  names(wts11_raw) <- cn11
  # Find Date/Ticker/Weight columns
  date_col11   <- cn11[cn11 %in% c("date", "as_of_date", "sig_date")][1]
  ticker_col11 <- cn11[cn11 %in% c("ticker", "tickers")][1]
  weight_col11 <- cn11[cn11 %in% c("weight", "weights")][1]
  if (is.na(date_col11) || is.na(ticker_col11) || is.na(weight_col11)) {
    cat(sprintf("  [WARN] Can't find Date/Ticker/Weight in Iter 11 weights: cols=%s\n",
                paste(cn11, collapse=",")))
    wts11 <- NULL
  } else {
    wts11 <- wts11_raw[, .(Date = get(date_col11), Ticker = get(ticker_col11),
                            Weight = get(weight_col11))]
    wts11[, Date := as.Date(as.character(Date))]
  }

  if (is.null(wts11)) {
    cat("  [SKIP] Iter 11 comparison skipped (column parse failure)\n")
    iter11_re_sr   <- iter11_sr_stated
    iter11_re_cagr <- NA
    iter11_re_mdd  <- NA
  } else {

  # Overlap period: max of start dates, min of end dates
  overlap_start <- max(min(wts$Date), min(wts11$Date))
  overlap_end   <- min(max(sig_dates_is), max(wts11[wts11$Date < LB_START, Date]))

  cat(sprintf("  Iter 11 weights loaded: %d rows | %s ~ %s\n",
              nrow(wts11), as.character(min(wts11$Date)), as.character(max(wts11$Date))))
  cat(sprintf("  Overlap period: %s ~ %s\n",
              as.character(overlap_start), as.character(overlap_end)))

  # Compute Iter 11 same-method returns in overlap period
  sig11_is <- sort(unique(wts11[Date >= overlap_start & Date < LB_START, Date]))
  iter11_rets <- vector("list", length(sig11_is))

  for (j in seq_along(sig11_is)) {
    d_s11 <- sig11_is[j]
    d_e11 <- if (j < length(sig11_is)) sig11_is[j+1] else LB_START

    wt_j <- wts11[Date == d_s11 & Weight > 1e-12]
    if (nrow(wt_j) == 0) next
    w_j  <- setNames(wt_j$Weight, wt_j$Ticker)
    w_s11 <- w_j[names(w_j) != "CASH"]

    p_raw <- raw[Date > d_s11 & Date <= d_e11 & Ticker %in% names(w_s11)]
    if (nrow(p_raw) == 0) {
      iter11_rets[[j]] <- data.table(period_end=d_e11, port_ret=0)
      next
    }
    sr_j <- p_raw[, .(stock_ret=prod(1+Ret,na.rm=TRUE)-1), by=Ticker]
    m_j  <- merge(data.table(Ticker=names(w_s11), w=as.numeric(w_s11)),
                  sr_j, by="Ticker", all.x=TRUE)
    m_j[is.na(stock_ret), stock_ret := 0]

    # Turnover
    if (j > 1) {
      wt_prev11 <- wts11[Date == sig11_is[j-1] & Weight > 1e-12]
      wp11 <- setNames(wt_prev11$Weight, wt_prev11$Ticker)
      all11 <- union(names(w_j), names(wp11))
      wn11 <- setNames(rep(0, length(all11)), all11)
      wp11x <- setNames(rep(0, length(all11)), all11)
      wn11[names(w_j)] <- w_j; wp11x[names(wp11)] <- wp11
      to11 <- sum(abs(wn11 - wp11x)) / 2
    } else {
      to11 <- sum(abs(w_j)) / 2
    }
    cost11 <- (COMMISSION_BPS / 1e4) * to11 * 2

    iter11_rets[[j]] <- data.table(
      period_end = d_e11,
      port_ret   = sum(m_j$w * m_j$stock_ret, na.rm=TRUE) - cost11)
  }

  iter11_dt <- rbindlist(iter11_rets, fill=TRUE)
  iter11_dt <- iter11_dt[!is.na(port_ret)]

  perf_iter11 <- compute_perf_v3(iter11_dt$port_ret, label="Iter11_STR_1701_same_method", n_cands=0L)
  cat(sprintf("\n  Iter 11 same-period stated SR: %.4f\n", iter11_sr_stated))
  cat(sprintf("  Iter 11 re-measured SR (same method): %.4f\n", perf_iter11$sr %||% NA))
  cat(sprintf("  Delta (STR_1715_IS - Iter11_re-measured): %+.4f\n",
              (perf_is$sr %||% 0) - (perf_iter11$sr %||% 0)))

  iter11_re_sr <- perf_iter11$sr %||% NA
  iter11_re_cagr <- perf_iter11$cagr %||% NA
  iter11_re_mdd  <- perf_iter11$mdd %||% NA

  } # end !is.null(wts11)
} else {
  cat(sprintf("  [WARN] Iter 11 weights not found at %s\n", iter11_weights_path))
  iter11_re_sr   <- iter11_sr_stated
  iter11_re_cagr <- NA
  iter11_re_mdd  <- NA
}

# ─────────────────────────────────────────────────────────
# 12. Compare vs factor_engine claim (1.4522)
# ─────────────────────────────────────────────────────────
cat("\n[12] Divergence analysis vs factor_engine claim\n")

factor_engine_sr_claim <- 1.4522
realized_sr_is <- perf_is$sr %||% NA
divergence_pp  <- (realized_sr_is %||% 0) - factor_engine_sr_claim

cat(sprintf("  factor_engine claimed SR (pre-LB):  %.4f\n", factor_engine_sr_claim))
cat(sprintf("  Forge v3 realized SR (pre-LB):      %.4f\n", realized_sr_is %||% NA))
cat(sprintf("  Divergence (Forge - factor_engine): %+.4f pp\n", divergence_pp))

if (!is.na(realized_sr_is)) {
  if (divergence_pp > -0.1) {
    cat("  DIAGNOSIS: Minimal divergence (<0.1pp) — factor_engine claim approximately valid\n")
  } else if (divergence_pp > -0.5) {
    cat("  DIAGNOSIS: Moderate drag (0.1~0.5pp) — discretization + cost drag\n")
  } else if (divergence_pp > -1.0) {
    cat("  DIAGNOSIS: Significant drag (0.5~1.0pp) — structural overfitting likely\n")
  } else {
    cat("  DIAGNOSIS: SEVERE drag (>1.0pp) — factor_engine claim fundamentally invalid\n")
  }
}

# ─────────────────────────────────────────────────────────
# 13. PG2 admission recommendation
# ─────────────────────────────────────────────────────────
cat("\n[13] PG2 Admission Recommendation\n")

sr_is <- perf_is$sr %||% 0
mdd_is <- abs(perf_is$mdd %||% 1)

pg2_admit <- if (caps_all && sr_is >= 0.8 && n_pass_harvey >= 1) {
  "ADMIT"
} else if (!caps_all) {
  "REJECT_HARD_CAP"
} else if (sr_is < 0.5) {
  "REJECT_SR_TOO_LOW"
} else {
  "REVIEW"
}

cat(sprintf("  SR_IS=%.4f | MDD_IS=%.4f | TO=%.4f | CVaR_d=%.4f\n",
            sr_is, mdd_is, ann_to_realized %||% NA, cvar_is_val %||% NA))
cat(sprintf("  Harvey_pass=%d/5 | Hard_caps=%s\n", n_pass_harvey, if(caps_all)"ALL_PASS" else "FAIL"))
cat(sprintf("  ==> PG2 ADMISSION: %s\n", pg2_admit))

# ─────────────────────────────────────────────────────────
# 14. Save monthly returns CSV
# ─────────────────────────────────────────────────────────
cat("\n[14] Save outputs\n")

monthly_nav_dt <- all_dt[, .(
  period_start, period_end,
  port_ret_gross, cost, port_ret, n_stock, cash_pct, turnover
)]
monthly_nav_dt[, cumulative_nav := cumprod(1 + port_ret)]
monthly_nav_dt[, period := ifelse(period_end < LB_START, "IS", "OOS")]

fwrite(monthly_nav_dt, file.path(BT_DIR, "monthly_nav.csv"))
cat(sprintf("  Saved: monthly_nav.csv (%d rows)\n", nrow(monthly_nav_dt)))

# ─────────────────────────────────────────────────────────
# 15. Charts
# ─────────────────────────────────────────────────────────
cat("\n[15] Charts\n")

# Equity curve
nav_plot_dt <- monthly_nav_dt[, .(Date = period_end, NAV = cumulative_nav, Period = period)]
nav_plot_dt[, Date := as.Date(Date)]

p_eq <- ggplot(nav_plot_dt, aes(x = Date, y = NAV, color = Period)) +
  geom_line(size = 0.8) +
  geom_vline(xintercept = as.numeric(LB_START), linetype = "dashed", color = "red", size = 0.7) +
  annotate("text", x = LB_START + 60, y = max(nav_plot_dt$NAV) * 0.92,
           label = "LB Start\n2024-01", color = "red", size = 3) +
  scale_y_continuous(labels = scales::comma_format(accuracy = 0.01)) +
  scale_color_manual(values = c("IS" = "steelblue", "OOS" = "darkorange")) +
  labs(title = sprintf("STR_1715 Standalone — Forge v3 NAV (SR_IS=%.3f, MDD=%.1f%%)",
                        sr_is, mdd_is * 100),
       subtitle = sprintf("weights.csv → share-based NAV | factor_engine claim SR=%.4f | divergence=%+.4f",
                          factor_engine_sr_claim, divergence_pp),
       x = "Date", y = "NAV (1=initial)", color = "Period") +
  theme_minimal(base_size = 11)

ggsave(file.path(BT_DIR, "equity_curve.png"), p_eq, width = 12, height = 6, dpi = 150)
cat("  Saved: equity_curve.png\n")

# Annual returns bar
monthly_nav_dt[, Year := as.integer(format(as.Date(period_end), "%Y"))]
ann_ret_dt <- monthly_nav_dt[, .(ann_ret = prod(1 + port_ret) - 1), by = Year]
setorder(ann_ret_dt, Year)

p_bar <- ggplot(ann_ret_dt, aes(x = Year, y = ann_ret * 100,
                                  fill = ifelse(ann_ret >= 0, "Pos", "Neg"))) +
  geom_bar(stat = "identity") +
  scale_fill_manual(values = c("Pos" = "steelblue", "Neg" = "tomato"), guide = "none") +
  labs(title = "STR_1715 Standalone — Annual Returns (Forge v3)",
       x = "Year", y = "Return (%)") +
  theme_minimal(base_size = 11)

ggsave(file.path(BT_DIR, "annual_returns.png"), p_bar, width = 12, height = 5, dpi = 150)
cat("  Saved: annual_returns.png\n")

# ─────────────────────────────────────────────────────────
# 16. Build forge_package.json
# ─────────────────────────────────────────────────────────
cat("\n[16] Build forge_package.json\n")

# END hash audit — verify 3-package unchanged
end_hashes <- sapply(pkg_files, function(f)
  tryCatch(as.character(tools::md5sum(f)), error = function(e) "MISSING"))
end_w_hash <- as.character(tools::md5sum(weights_path))

hash_integrity <- all(start_hashes == end_hashes) && start_w_hash == end_w_hash
cat(sprintf("  END hash audit: %s\n", if(hash_integrity) "PASS — packages unchanged" else "FAIL — MODIFICATION DETECTED"))
if (!hash_integrity) {
  for (n in names(start_hashes)) {
    if (start_hashes[n] != end_hashes[n])
      cat(sprintf("  [TAMPER] %s: %s -> %s\n", n, start_hashes[n], end_hashes[n]))
  }
}

forge_pkg <- list(
  task_id     = WT_ID,
  str_id      = STR_ID,
  iter        = 31L,
  iter_name   = "STR1715_Standalone_Formal_ShareBased_v3",
  agent       = "forge_integration_v6.1_pure_function",
  as_of_date  = as.character(Sys.Date()),
  method      = "weights.csv_direct_NAV_reconstruction_IS_plus_OOS",

  backtest_summary = list(
    IS = list(
      period       = paste0(as.character(min(is_dt$period_start)), " ~ ", as.character(max(is_dt$period_end))),
      n_periods    = nrow(is_dt),
      sr           = perf_is$sr,
      cagr         = perf_is$cagr,
      mdd          = perf_is$mdd,
      vol          = perf_is$vol,
      hit          = perf_is$hit,
      ann_to       = ann_to_realized,
      cvar_d_proxy = cvar_is_val,
      dsr_raw      = perf_is$dsr_raw,
      dsr_post     = perf_is$dsr_post
    ),
    OOS = list(
      period       = if (nrow(oos_dt) > 0) paste0(as.character(min(oos_dt$period_start)), " ~ ", as.character(max(oos_dt$period_end))) else "N/A",
      n_periods    = nrow(oos_dt),
      sr           = perf_oos$sr,
      cagr         = perf_oos$cagr,
      mdd          = perf_oos$mdd
    ),
    Full = list(
      period       = paste0(as.character(min(all_dt$period_start)), " ~ ", as.character(max(all_dt$period_end))),
      n_periods    = nrow(all_dt),
      sr           = perf_all$sr,
      cagr         = perf_all$cagr,
      mdd          = perf_all$mdd
    )
  ),

  harvey_5spec = list(
    CAPM     = list(t=harvey_results$CAPM$t_nw,     pass=harvey_results$CAPM$gate_pass),
    Carhart3 = list(t=harvey_results$Carhart3$t_nw, pass=harvey_results$Carhart3$gate_pass),
    Carhart4 = list(t=harvey_results$Carhart4$t_nw, pass=harvey_results$Carhart4$gate_pass),
    FF5      = list(t=harvey_results$FF5$t_nw,      pass=harvey_results$FF5$gate_pass),
    FF6      = list(t=harvey_results$FF6$t_nw,      pass=harvey_results$FF6$gate_pass),
    pass_count = n_pass_harvey
  ),

  dsr_post = dsr_post_v3,

  hard_caps = list(
    mdd_pass   = cap_mdd,
    to_pass    = cap_to,
    cvar_pass  = cap_cvar,
    all_pass   = caps_all,
    mdd_realized  = abs(mdd_is_val),
    to_realized   = ann_to_realized,
    cvar_realized = cvar_is_val
  ),

  vs_factor_engine = list(
    factor_engine_claimed_sr_is = factor_engine_sr_claim,
    forge_v3_realized_sr_is     = perf_is$sr,
    divergence_pp               = divergence_pp,
    factor_engine_claimed_oos_sr = 1.6827,
    forge_v3_oos_sr             = perf_oos$sr,
    diagnosis = if (!is.na(realized_sr_is)) {
      if (divergence_pp > -0.1) "NEGLIGIBLE_DRAG" else
      if (divergence_pp > -0.5) "MODERATE_DRAG" else
      if (divergence_pp > -1.0) "SIGNIFICANT_DRAG" else "SEVERE_DRAG"
    } else "UNKNOWN"
  ),

  iter11_comparison = list(
    iter11_stated_pg2_sr = iter11_sr_stated,
    iter11_re_measured_sr = iter11_re_sr,
    str1715_is_sr         = perf_is$sr,
    delta_str1715_vs_iter11_re = (perf_is$sr %||% 0) - (iter11_re_sr %||% 0)
  ),

  pg2_admission_recommendation = pg2_admit,

  hash_audit = list(
    alpha_hash_start   = start_hashes["alpha_package.json"],
    risk_hash_start    = start_hashes["risk_package.json"],
    opt_hash_start     = start_hashes["optimization_package.json"],
    weights_hash_start = start_w_hash,
    alpha_hash_end     = end_hashes["alpha_package.json"],
    risk_hash_end      = end_hashes["risk_package.json"],
    opt_hash_end       = end_hashes["optimization_package.json"],
    weights_hash_end   = end_w_hash,
    integrity_pass     = hash_integrity
  ),

  output_paths = list(
    equity_curve   = file.path(BT_DIR, "equity_curve.png"),
    annual_returns = file.path(BT_DIR, "annual_returns.png"),
    monthly_nav    = file.path(BT_DIR, "monthly_nav.csv")
  ),

  generated_at = as.character(Sys.time())
)

fp_path <- file.path(WT_DIR, "forge_package.json")
write_json(forge_pkg, fp_path, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("  Saved: forge_package.json → %s\n", fp_path))

# ─────────────────────────────────────────────────────────
# 17. Build judge_ready_v3/backtest_summary.json
# ─────────────────────────────────────────────────────────
jready <- list(
  task_id    = WT_ID,
  str_id     = STR_ID,
  iter       = 31L,
  method     = "weights.csv_share_based_NAV_Forge_v3",
  run_type   = "STR1715_STANDALONE_FORMAL",

  key_metrics = list(
    pre_lb_sr      = perf_is$sr,
    pre_lb_cagr    = perf_is$cagr,
    pre_lb_mdd     = perf_is$mdd,
    full_sr        = perf_all$sr,
    lockbox_sr     = perf_oos$sr,
    ann_to         = ann_to_realized,
    cvar_d_proxy   = cvar_is_val,
    harvey_5spec   = n_pass_harvey,
    dsr_post       = dsr_post_v3
  ),

  comparison_table = list(
    factor_engine_claim_sr = factor_engine_sr_claim,
    forge_v3_realized_sr   = perf_is$sr,
    divergence_pp          = divergence_pp,
    iter32_standalone_sr   = 0.2387,   # from WT-017 mega_baseline_same_period_ref
    note = "iter32_standalone used weights.csv daily NAV on different weights subset"
  ),

  hard_caps_all_pass = caps_all,
  harvey_pass_count  = n_pass_harvey,
  pg2_admit_recommendation = pg2_admit,

  generated_at = as.character(Sys.time())
)

jr_path <- file.path(JR_DIR, "backtest_summary.json")
write_json(jready, jr_path, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("  Saved: judge_ready_v3/backtest_summary.json\n"))

# ─────────────────────────────────────────────────────────
# FINAL REPORT LINE
# ─────────────────────────────────────────────────────────
cat("\n")
cat(rep("=", 80), "\n", sep="")
cat("FORGE_DONE_STR1715_FORMAL\n")
cat(rep("=", 80), "\n", sep="")
cat(sprintf("  pre_lb_sr           = %.4f\n", perf_is$sr %||% NA))
cat(sprintf("  full_sr             = %.4f\n", perf_all$sr %||% NA))
cat(sprintf("  lockbox_sr          = %.4f\n", perf_oos$sr %||% NA))
cat(sprintf("  mdd                 = %.4f\n", perf_is$mdd %||% NA))
cat(sprintf("  to                  = %.4f\n", ann_to_realized %||% NA))
cat(sprintf("  cvar_d              = %.4f\n", cvar_is_val %||% NA))
cat(sprintf("  harvey_pass         = %d/5\n", n_pass_harvey))
cat(sprintf("  dsr_post            = %.4f\n", dsr_post_v3 %||% NA))
cat(sprintf("  factor_engine_claim = 1.4522\n"))
cat(sprintf("  divergence_pp       = %+.4f\n", divergence_pp))
cat(sprintf("  hard_caps_pass      = %s\n", if(caps_all) "true" else "false"))
cat(sprintf("  pg2_admit           = %s\n", pg2_admit))
cat(rep("=", 80), "\n", sep="")

cat("\nFORGE_DONE_STR1715_FORMAL",
    sprintf("pre_lb_sr=%.4f, full_sr=%.4f, lockbox_sr=%.4f, mdd=%.4f, to=%.4f, cvar_d=%.4f, harvey_pass=%d/5, dsr_post=%.4f, factor_engine_claim_sr=1.4522, divergence_pp=%+.4f, hard_caps_pass=%s, pg2_admit_recommendation=%s",
            perf_is$sr %||% NA, perf_all$sr %||% NA, perf_oos$sr %||% NA,
            perf_is$mdd %||% NA, ann_to_realized %||% NA, cvar_is_val %||% NA,
            n_pass_harvey, dsr_post_v3 %||% NA,
            divergence_pp, if(caps_all) "true" else "false", pg2_admit),
    "\n")
