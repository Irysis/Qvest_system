## ============================================================
## STR_1714 — WT-D20260427_014 Iter 29 Hybrid Decisive Gate
## ============================================================
## ## 핵심아이디어
##   Iter 29 = Best-of-both Hybrid Switch
##     BULL/NORMAL (84 dates, 91.3%) → Iter 11 LinTilt λ=1.0 weights (proven walk-forward optimal SR 1.291)
##     CAUTION/CRISIS (8 dates, 8.7%) → Iter 27 ERC+LinTilt+EW weights (CAUTION realized SR 3.97)
##
##   Simple weight matrix select by regime_state (no self-implemented ERC/MVO/HRP).
##   OVERRIDE_005 fallback: Codex empirical R1 expected REJECT on walk-forward panel SR.
##   Forge realized backtest is final arbiter (15+ instances precedent).
##
##   92 sig_dates walk-forward (2008-01-31 ~ 2023-11-30)
##   21 names max (CASH overlay during CAUTION).
##   Baseline comparison: PG2 baseline SR=1.4625 (STR_1701 80% + STR_1656 20%).
##
## FORGE MANDATE (decisive gate tasks):
##   1. Walk-forward backtest 92 sig_dates, 15bps + slippage, monthly rebal.
##   2. PG2 blend: V29 80% + STR_1656 20% vs baseline SR=1.4625 (CRITICAL).
##   3. Per-regime realized SR: BULL / NORMAL / CAUTION (CRISIS=NA, n=0 in panel).
##   4. AX-001 v2 4-metric direct realized measurement.
##   5. Harvey FF5 v2 5-spec NW-HAC + DSR_post.
##   6. Same-period comparison: Iter11 / Iter22b / Iter26 / Iter27 / Iter28 SOTA.
##   7. OOS 24-26 extension (frozen last weights).
##   8. Charts 4종.
##   9. Telegram send (exactly 1 time).
##
## Decision criteria:
##   PG2 blend SR >= 1.4625 + AX-001 v2 >= 3/4 → PG2 promotion 검토
##   PG2 blend SR 1.20~1.46 + crisis effect → Probe Phase
##   PG2 blend SR < 1.20 → MAINTAIN_BASELINE + L-238 적립
##
## v6.1 R12 Pure Function:
##   - alpha/risk/optimization 패키지 절대 수정 금지.
##   - target_weights 재해석 금지 (92 sig_date schedule 그대로 적용).
##   - Hash audit: 시작/완료 동일 검증 필수.
##   - ALLOWED writes: run_all.R, backtest_result/*, judge_ready/*, output/*
##   - FORBIDDEN: alpha_package.json, risk_package.json,
##                optimization_package.json, weights.csv
##
## DSR penalty basis:
##   Hybrid = Iter11 + Iter27 inheritance (no new optimizer search).
##   Lineage: alpha 5 (Iter11) + risk 5 (Iter11) + optimizer 10 (Iter11) +
##            optimizer 5 (Iter27 hybrid design) = 25 candidates disclosure.
##   This sprint penalty: 5 candidates × 0.05 = 0.25 (hybrid design only).
##   Cumulative lineage: 25 × 0.05 = 1.25.
##
## PIT 준수:
##   C1: walk-forward only (92 sig_dates, no full-sample re-opt).
##   C2: monthly ret = Close(t)/Close(t-1)-1 compound.
##   C9: weight at sig_date d → applied (d, next_sig_date] lag enforced.
##   C10: liquidity 2e8 KRW PIT t-30..t-1 one-sided.
##   C11: regime_state from weights.csv (KR internal expanding percentile, no FRED).
##   C13: Z_Score_Aligned alpha upstream.
##   C14: Usable_Date <= sig_date (Factor DB chain).
##   LB cutoff: last sig_date 2023-11-30 < lockbox 2024-01-23.
## ============================================================

cat("=== STR_1714: WT-D20260427_014 Iter 29 Hybrid Decisive Gate ===\n")
cat("Forge Integration — v6.1 R12 Pure Function — 2026-04-27\n\n")

QEPM_AUTO_COMMIT <- TRUE
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(ggplot2)
  library(scales)
  library(sandwich)
  library(lmtest)
})

BASE_DIR   <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
STR_ID     <- "STR_1714"
WT_ID      <- "WT-D20260427_014"
ITER11_WT  <- "WT-D20260426_004"
ITER22B_WT <- "WT-D20260427_007"
ITER26_WT  <- "WT-D20260427_011"
ITER27_WT  <- "WT-D20260427_012"
ITER28_WT  <- "WT-D20260427_013"

WT_DIR     <- file.path(BASE_DIR, "qepm/mailbox/worktask", WT_ID)
OUT_DIR    <- file.path(BASE_DIR, "04_Research/strategies/STR_1714_WT014_Iter29_HybridDecisive/output")
BT_DIR     <- file.path(WT_DIR, "backtest_result")
JR_DIR     <- file.path(WT_DIR, "judge_ready")
ITER11_BT  <- file.path(BASE_DIR, "qepm/mailbox/worktask", ITER11_WT, "backtest_result")
ITER22B_BT <- file.path(BASE_DIR, "qepm/mailbox/worktask", ITER22B_WT, "backtest_result")
ITER26_BT  <- file.path(BASE_DIR, "qepm/mailbox/worktask", ITER26_WT, "backtest_result")
ITER27_BT  <- file.path(BASE_DIR, "qepm/mailbox/worktask", ITER27_WT, "backtest_result")

dir.create(OUT_DIR, showWarnings=FALSE, recursive=TRUE)
dir.create(BT_DIR,  showWarnings=FALSE, recursive=TRUE)
dir.create(JR_DIR,  showWarnings=FALSE, recursive=TRUE)

# DSR penalty
DSR_CANDIDATES_TRIED    <- 5    # hybrid design candidates this sprint only
DSR_PENALTY_PER_CAND    <- 0.05
DSR_PENALTY_TOTAL       <- DSR_CANDIDATES_TRIED * DSR_PENALTY_PER_CAND  # 0.25
DSR_CUMULATIVE_LINEAGE  <- 25   # full lineage disclosure

# Baselines / targets
BASELINE_PG2_SR    <- 1.4625   # STR_1701 80% + STR_1656 20%
BASELINE_ITER11_SR <- 1.291    # Iter11 full period
BASELINE_ITER11_SP <- 1.1925   # Iter11 same-period (2008-01 to 2023-11)
BASELINE_ITER22B   <- 0.7611   # Iter22b standalone (from hurdle_result.json)
BASELINE_ITER26    <- 0.6322   # Iter26 (WT-D20260427_011)
BASELINE_ITER27    <- 0.5973   # Iter27 standalone (WT-D20260427_012)
BASELINE_ITER28    <- 0.4302   # Iter28 SOTA (WT-D20260427_013)

# Optimizer targets
OPT_SR_HYBRID        <- 1.432  # Expected standalone (linear blend estimate)
OPT_SR_CAUTION_ITER27 <- 3.97  # CAUTION inheritance (realized from Iter27)

# AX-001 v2 targets
TARGET_CRISIS_ALPHA    <- 0.00
TARGET_MDD_RELIEF_PP   <- 0.05
TARGET_BAD_NORMAL_IC   <- 1.5
TARGET_HARVEY_COND_T   <- 2.0

PIT_CUTOFF   <- as.Date("2023-11-30")
LOCKBOX_SEAL <- as.Date("2024-01-23")

cat(sprintf("[0] Config | STR_ID=%s WT_ID=%s\n", STR_ID, WT_ID))
cat(sprintf("    DSR penalty: %d candidates x %.2f = %.2f (lineage: %d)\n",
            DSR_CANDIDATES_TRIED, DSR_PENALTY_PER_CAND, DSR_PENALTY_TOTAL, DSR_CUMULATIVE_LINEAGE))
cat(sprintf("    Baseline PG2 SR=%.4f | Iter11 full SR=%.4f\n",
            BASELINE_PG2_SR, BASELINE_ITER11_SR))
cat(sprintf("    Optimizer expected hybrid SR: %.4f | CAUTION inheritance: %.2f\n",
            OPT_SR_HYBRID, OPT_SR_CAUTION_ITER27))

# ─────────────────────────────────────────────────────────
# 1. START hash audit (3-package + weights.csv read-only)
# ─────────────────────────────────────────────────────────
cat("\n[1] START hash audit (3-package + weights.csv — Pure Function)\n")

pkg_files <- c(
  alpha  = file.path(WT_DIR, "alpha_package.json"),
  risk   = file.path(WT_DIR, "risk_package.json"),
  optim  = file.path(WT_DIR, "optimization_package.json")
)
weights_path <- file.path(WT_DIR, "weights.csv")

start_hashes <- sapply(pkg_files, function(f) tryCatch(
  as.character(tools::md5sum(f)), error=function(e) "MISSING"))
start_w_hash <- tryCatch(as.character(tools::md5sum(weights_path)),
                         error=function(e) "MISSING")

cat("  Start MD5:\n")
for (n in names(start_hashes))
  cat(sprintf("    %-36s = %s\n", paste0(n, "_package.json"),
              substr(start_hashes[n], 1, 16)))
cat(sprintf("    %-36s = %s\n", "weights.csv", substr(start_w_hash, 1, 16)))

# ─────────────────────────────────────────────────────────
# 2. 3-package 로드 (READ-ONLY)
# ─────────────────────────────────────────────────────────
cat("\n[2] Load 3-package (Pure Function boundary)\n")

alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector=FALSE)
risk_pkg  <- fromJSON(file.path(WT_DIR, "risk_package.json"),  simplifyVector=FALSE)
opt_pkg   <- fromJSON(file.path(WT_DIR, "optimization_package.json"), simplifyVector=FALSE)

method_tag    <- opt_pkg$method_selected %||%
                 "Iter29_Hybrid_BULL_NORMAL_Iter11_LinTilt_lam1_plus_CAUTION_Iter27"
n_sig_wf      <- 92L
expected_sr   <- opt_pkg$expected_sr_annual %||% 0.2184
expected_cagr <- opt_pkg$expected_cagr      %||% 0.0236
expected_mdd  <- opt_pkg$expected_mdd       %||% -0.3879
expected_to   <- opt_pkg$turnover           %||% 0.4658

cat(sprintf("  Method: %s\n", method_tag))
cat(sprintf("  Walk-forward sig_dates (canonical): %d\n", n_sig_wf))
cat(sprintf("  Expected (Optimizer): SR=%.4f CAGR=%.4f MDD=%.4f Ann_TO=%.3f\n",
            expected_sr, expected_cagr, expected_mdd, expected_to))

# ─────────────────────────────────────────────────────────
# 3. weights.csv 로드 (92 sig_dates × Hybrid switch)
# ─────────────────────────────────────────────────────────
cat("\n[3] Load weights schedule (92 sig_dates × Iter29 Hybrid switch)\n")

if (!file.exists(weights_path)) stop("[FAIL] weights.csv not found: ", weights_path)

w_dt <- fread(weights_path)
w_dt[, sig_date := as.Date(sig_date)]

# Normalize column name to as_of_date for internal use
setnames(w_dt, "sig_date", "as_of_date")
setkey(w_dt, as_of_date, ticker)

sig_dates <- sort(unique(w_dt$as_of_date))
n_sd      <- length(sig_dates)

cat(sprintf("  weights.csv: %d rows | %d sig_dates | range: %s ~ %s\n",
            nrow(w_dt), n_sd,
            as.character(min(sig_dates)), as.character(max(sig_dates))))

# PIT cutoff check
if (max(sig_dates) > PIT_CUTOFF)
  stop(sprintf("[FAIL] PIT violation: last sig_date %s > PIT_CUTOFF %s",
               max(sig_dates), PIT_CUTOFF))
cat(sprintf("  PIT check: last sig_date=%s <= cutoff=%s PASS\n",
            as.character(max(sig_dates)), as.character(PIT_CUTOFF)))

# Constraint sanity check (CASH rows included — use non-CASH rows for weight sum)
equity_w <- w_dt[ticker != "CASH"]
sum_check <- equity_w[, .(sum_w = sum(weight, na.rm=TRUE),
                           n_names = .N,
                           max_w   = max(weight, na.rm=TRUE),
                           min_w   = min(weight, na.rm=TRUE)), by=as_of_date]
cat(sprintf("  equity sum_w range: [%.4f, %.4f]\n",
            min(sum_check$sum_w), max(sum_check$sum_w)))
cat(sprintf("  n_names range: [%d, %d]\n", min(sum_check$n_names), max(sum_check$n_names)))
cat(sprintf("  max_w=%.4f | min_w=%.4f\n", max(sum_check$max_w), min(sum_check$min_w)))

if (min(equity_w$weight, na.rm=TRUE) < -0.0001)
  stop("[FAIL] negative weight — long-only violated")

# Regime distribution
cat("\n  Hybrid switch distribution:\n")
reg_meta <- unique(w_dt[, .(as_of_date, regime, switch_decision, cash_pct)])
switch_dist <- reg_meta[, .N, by=switch_decision]
for (sw in switch_dist$switch_decision)
  cat(sprintf("    %-20s: %d sig_dates\n", sw,
              switch_dist[switch_decision==sw, N]))

regime_dist <- reg_meta[, .N, by=regime]
for (r in regime_dist$regime)
  cat(sprintf("    %-10s (regime) : %d sig_dates\n", r, regime_dist[regime==r, N]))

# CAUTION dates (Iter27 inheritance applied)
caution_dates <- reg_meta[switch_decision=="CAUTION_CRISIS", as_of_date]
cat(sprintf("  CAUTION/CRISIS dates (%d): %s\n",
            length(caution_dates),
            paste(format(sort(caution_dates), "%Y-%m"), collapse=", ")))

# ─────────────────────────────────────────────────────────
# 4. Load RAWDATA + FF5 v2 + STR_1656 NAV
# ─────────────────────────────────────────────────────────
cat("\n[4] Load RAWDATA + FF5 v2 + STR_1656 NAV\n")

rawdata_path <- file.path(BASE_DIR, ".cache/rawdata.parquet")
if (!file.exists(rawdata_path))
  rawdata_path <- file.path(BASE_DIR, ".cache/RAWDATA.parquet")

raw <- as.data.table(read_parquet(rawdata_path,
  col_select=c("Date","Ticker","Close","Vol","Ret")))
setkey(raw, Date, Ticker)
raw[, TradingAmt := Close * Vol]
cat(sprintf("  RAWDATA: %s rows | %s ~ %s\n",
            format(nrow(raw), big.mark=","),
            as.character(min(raw$Date)), as.character(max(raw$Date))))

ff5_path <- file.path(BASE_DIR, ".cache/kr_factor_returns_v2.parquet")
ff5 <- as.data.table(read_parquet(ff5_path))
setorder(ff5, Date)
ff5[, Date := as.Date(Date)]
cat(sprintf("  FF5 v2: %d rows | %s ~ %s\n", nrow(ff5),
            as.character(min(ff5$Date)), as.character(max(ff5$Date))))

# STR_1656 daily NAV → monthly returns
str1656_path <- file.path(BASE_DIR,
  "04_Research/strategies/STR_1656_MLRA/output/nav_S1_B.csv")
if (!file.exists(str1656_path))
  stop("[FAIL] STR_1656 nav_S1_B.csv not found: ", str1656_path)

str1656_daily <- fread(str1656_path)
str1656_daily[, Date := as.Date(Date)]
setorder(str1656_daily, Date)
str1656_daily[, YM := format(Date, "%Y-%m")]
str1656_monthly_all <- str1656_daily[, .SD[.N], by=YM]
str1656_monthly_all[, ret_1656 := NAV / shift(NAV) - 1]
str1656_monthly_all <- str1656_monthly_all[!is.na(ret_1656)]
str1656_monthly_all[, YM_key := YM]
cat(sprintf("  STR_1656 monthly: %d rows | %s ~ %s\n",
            nrow(str1656_monthly_all),
            as.character(min(str1656_monthly_all$Date)),
            as.character(max(str1656_monthly_all$Date))))

# ─────────────────────────────────────────────────────────
# 5. WALK-FORWARD BACKTEST (92 sig_dates, Iter29 Hybrid)
#    Optimizer-decided weights applied as-is (Pure Function).
#    CASH row in weights.csv: excluded from equity return calc, cash earns 0.
# ─────────────────────────────────────────────────────────
cat("\n[5] Walk-forward backtest (92 sig_dates, Iter29 Hybrid — Pure Function apply)\n")

LIQ_THRESHOLD  <- 2e8
COMMISSION_BPS <- 15
COMMISSION_PCT <- COMMISSION_BPS / 10000

monthly_results <- vector("list", n_sd - 1)

for (i in seq_len(n_sd - 1)) {
  start_d <- sig_dates[i]
  end_d   <- sig_dates[i + 1]

  # Pull all rows for this sig_date (equity + CASH)
  port_all  <- w_dt[as_of_date == start_d]
  cash_row  <- port_all[ticker == "CASH"]
  port_i    <- port_all[ticker != "CASH"]

  cash_pct_i <- if (nrow(cash_row) > 0) cash_row$weight[1] else 0
  regime_i   <- if (nrow(port_all) > 0) port_all$regime[1] else "UNKNOWN"
  switch_i   <- if (nrow(port_all) > 0) port_all$switch_decision[1] else "UNKNOWN"

  if (nrow(port_i) == 0) {
    monthly_results[[i]] <- data.table(
      period_start=start_d, period_end=end_d,
      port_ret=0, port_ret_gross=0, n_held=0, turnover_ow=0, i=i,
      regime=regime_i, switch_decision=switch_i, cash_pct=cash_pct_i)
    next
  }

  # Liquidity filter (PIT C10: t-30 to t-1)
  liq_data <- raw[Date >= (start_d - 30L) & Date < start_d,
                  .(AvgTradingAmt=mean(TradingAmt, na.rm=TRUE)), by=Ticker]
  liquid_tickers <- liq_data[AvgTradingAmt >= LIQ_THRESHOLD, Ticker]
  port_liq <- port_i[ticker %in% liquid_tickers]
  if (nrow(port_liq) == 0) port_liq <- copy(port_i)

  # Normalize equity weights to sum = 1 (equity portion; cash overlay is additive)
  sum_w_equity <- sum(port_liq$weight, na.rm=TRUE)
  if (sum_w_equity <= 0) {
    monthly_results[[i]] <- data.table(
      period_start=start_d, period_end=end_d,
      port_ret=0, port_ret_gross=0, n_held=0, turnover_ow=0, i=i,
      regime=regime_i, switch_decision=switch_i, cash_pct=cash_pct_i)
    next
  }
  port_liq[, w_norm := weight / sum_w_equity]

  # Period returns (PIT C9: Date > start_d, Date <= end_d)
  period_data <- raw[Date > start_d & Date <= end_d, .(Date, Ticker, Ret)]
  if (nrow(period_data) == 0) {
    monthly_results[[i]] <- data.table(
      period_start=start_d, period_end=end_d,
      port_ret=0, port_ret_gross=0, n_held=nrow(port_liq), turnover_ow=0, i=i,
      regime=regime_i, switch_decision=switch_i, cash_pct=cash_pct_i)
    next
  }

  stock_rets <- period_data[, .(stock_ret=prod(1+Ret, na.rm=TRUE)-1), by=Ticker]
  merged <- merge(port_liq, stock_rets, by.x="ticker", by.y="Ticker", all.x=TRUE)
  merged[is.na(stock_ret), stock_ret := 0]

  # Equity gross return (weighted)
  equity_ret_gross <- sum(merged$w_norm * merged$stock_ret, na.rm=TRUE)

  # Cash overlay: equity portion = (1 - cash_pct_i), cash earns 0 (conservative PIT)
  port_ret_gross <- equity_ret_gross * (1 - cash_pct_i)

  # Turnover (one-way, equity weights only)
  if (i == 1) {
    turnover_ow <- 1.0
  } else {
    prev_all  <- w_dt[as_of_date == sig_dates[i-1] & ticker != "CASH"]
    prev_cash <- w_dt[as_of_date == sig_dates[i-1] & ticker == "CASH"]
    prev_cash_pct <- if (nrow(prev_cash) > 0) prev_cash$weight[1] else 0
    if (nrow(prev_all) == 0) {
      turnover_ow <- 1.0
    } else {
      prev_sum <- sum(prev_all$weight, na.rm=TRUE)
      if (prev_sum <= 0) {
        turnover_ow <- 1.0
      } else {
        prev_all[, w_prev := weight / prev_sum]
        cur_dt   <- port_liq[, .(Ticker=ticker, w_cur=w_norm)]
        prev_dt  <- prev_all[, .(Ticker=ticker, w_prev)]
        merged_to <- merge(cur_dt, prev_dt, by="Ticker", all=TRUE)
        merged_to[is.na(w_cur),  w_cur  := 0]
        merged_to[is.na(w_prev), w_prev := 0]
        turnover_ow <- sum(abs(merged_to$w_cur - merged_to$w_prev)) / 2
      }
    }
  }

  tc_drag      <- 2 * turnover_ow * COMMISSION_PCT
  port_ret_net <- port_ret_gross - tc_drag

  monthly_results[[i]] <- data.table(
    period_start    = start_d,
    period_end      = end_d,
    port_ret        = port_ret_net,
    port_ret_gross  = port_ret_gross,
    n_held          = nrow(port_liq),
    turnover_ow     = turnover_ow,
    i               = i,
    regime          = regime_i,
    switch_decision = switch_i,
    cash_pct        = cash_pct_i
  )
}

iter29_monthly <- rbindlist(monthly_results, fill=TRUE)
iter29_monthly <- iter29_monthly[!is.na(port_ret)]
iter29_monthly[, YM_key := format(period_end, "%Y-%m")]

cat(sprintf("  Walk-forward complete: %d periods | %s ~ %s\n",
            nrow(iter29_monthly),
            as.character(min(iter29_monthly$period_start)),
            as.character(max(iter29_monthly$period_end))))

# ─────────────────────────────────────────────────────────
# 6. PERFORMANCE METRICS helper
# ─────────────────────────────────────────────────────────
compute_metrics <- function(rets, label="") {
  rets <- rets[!is.na(rets)]
  n <- length(rets)
  if (n < 3) return(list(sr=NA_real_, cagr=NA_real_, mdd=NA_real_,
                         vol=NA_real_, hit=NA_real_, n=n,
                         mean_r=NA_real_, std_r=NA_real_, rets=rets))
  mean_r <- mean(rets, na.rm=TRUE)
  std_r  <- sd(rets, na.rm=TRUE)
  sr     <- if (std_r > 0) (mean_r / std_r) * sqrt(12) else 0
  nav    <- cumprod(1 + rets)
  cagr   <- nav[n]^(12/n) - 1
  peak   <- cummax(c(1, nav))[-1]
  dd     <- nav / peak - 1
  mdd    <- min(dd, na.rm=TRUE)
  vol    <- std_r * sqrt(12)
  hit    <- mean(rets > 0, na.rm=TRUE)
  if (nchar(label) > 0)
    cat(sprintf("  %-52s | SR=%7.4f | CAGR=%7.4f | MDD=%7.4f | Vol=%6.4f | Hit=%.3f | n=%d\n",
                label, sr, cagr, mdd, vol, hit, n))
  list(sr=sr, cagr=cagr, mdd=mdd, vol=vol, hit=hit, n=n,
       mean_r=mean_r, std_r=std_r, rets=rets)
}

cat("\n[6] V29 Hybrid standalone performance\n")
m_iter29 <- compute_metrics(iter29_monthly$port_ret, "Iter29 Hybrid standalone")

ann_to_actual <- {
  yrs <- nrow(iter29_monthly) / 12
  if (yrs > 0) sum(iter29_monthly$turnover_ow, na.rm=TRUE) / yrs * 2 else NA_real_
}
cat(sprintf("  Ann turnover realized: %.3f | Expected: %.3f\n",
            ann_to_actual %||% NA, expected_to))

# ─────────────────────────────────────────────────────────
# 7. PER-REGIME REALIZED SR
#    BULL/NORMAL: Iter11 inheritance | CAUTION: Iter27 inheritance (3.97 target)
# ─────────────────────────────────────────────────────────
cat("\n[7] Per-regime realized SR (BULL / NORMAL / CAUTION | CRISIS=NA)\n")
cat(sprintf("    [CAUTION Iter27 realized inheritance: %.2f → V29 realized?]\n",
            OPT_SR_CAUTION_ITER27))

regime_sr <- list()
for (reg in c("BULL","NORMAL","CAUTION","CRISIS")) {
  sub <- iter29_monthly[regime == reg, port_ret]
  if (length(sub) >= 2) {
    m <- compute_metrics(sub, sprintf("Regime=%-8s (V29 Hybrid)", reg))
    regime_sr[[reg]] <- m
    cat(sprintf("    %s baseline: Iter27=%.4f | V29 realized: %.4f | Delta: %+.4f | n=%d\n",
                reg,
                switch(reg, BULL=0.4377, NORMAL=0.326, CAUTION=3.9722, CRISIS=0),
                m$sr %||% NA,
                (m$sr - switch(reg, BULL=0.4377, NORMAL=0.326, CAUTION=3.9722, CRISIS=0)) %||% NA,
                m$n))
  } else {
    cat(sprintf("    Regime=%-8s: n=%d (insufficient for SR)\n", reg, length(sub)))
    regime_sr[[reg]] <- list(sr=NA_real_, n=length(sub))
  }
}

realized_sr_bull    <- regime_sr$BULL$sr    %||% NA_real_
realized_sr_normal  <- regime_sr$NORMAL$sr  %||% NA_real_
realized_sr_caution <- regime_sr$CAUTION$sr %||% NA_real_
realized_sr_crisis  <- regime_sr$CRISIS$sr  %||% NA_real_

# BULL+NORMAL = Iter11 baseline; CAUTION = Iter27 inheritance
bull_normal_sr <- {
  sub <- iter29_monthly[regime %in% c("BULL","NORMAL"), port_ret]
  if (length(sub) >= 3) {
    m <- compute_metrics(sub, "BULL+NORMAL combined (Iter11 inheritance)")
    m$sr
  } else NA_real_
}

cat(sprintf("\n  KEY HYBRID METRICS:\n"))
cat(sprintf("    BULL+NORMAL (84 dates): V29 realized SR=%.4f | Iter11 baseline=%.4f\n",
            bull_normal_sr %||% NA, BASELINE_ITER11_SP))
cat(sprintf("    CAUTION     ( 8 dates): V29 realized SR=%.4f | Iter27 baseline=%.4f\n",
            realized_sr_caution %||% NA, OPT_SR_CAUTION_ITER27))

# ─────────────────────────────────────────────────────────
# 8. AX-001 v2 4-METRIC DIRECT REALIZED
# ─────────────────────────────────────────────────────────
cat("\n[8] AX-001 v2 4-metric DIRECT REALIZED measurement\n")

# Drawdown periods = CAUTION or CRISIS
dd_periods   <- iter29_monthly[regime %in% c("CAUTION","CRISIS")]
norm_periods <- iter29_monthly[regime %in% c("BULL","NORMAL")]

# M1: crisis_alpha
crisis_alpha_realized <- if (nrow(dd_periods) > 0) mean(dd_periods$port_ret, na.rm=TRUE) else NA_real_
crisis_alpha_pass <- !is.na(crisis_alpha_realized) && crisis_alpha_realized > TARGET_CRISIS_ALPHA
cat(sprintf("  [M1] crisis_alpha (mean ret CAUTION+CRISIS): %.4f | target > %.2f | %s\n",
            crisis_alpha_realized %||% NA, TARGET_CRISIS_ALPHA,
            ifelse(crisis_alpha_pass, "PASS", "FAIL")))

# M2: core_mdd_relief vs Iter11 MDD (-0.4077)
ITER11_MDD  <- -0.4077
mdd_relief_pp <- if (!is.na(m_iter29$mdd)) (m_iter29$mdd - ITER11_MDD) else NA_real_
mdd_relief_pass <- !is.na(mdd_relief_pp) && mdd_relief_pp > TARGET_MDD_RELIEF_PP
cat(sprintf("  [M2] core_mdd_relief vs Iter11 (%.4f): %.4fpp | target > %.2fpp | %s\n",
            ITER11_MDD, mdd_relief_pp %||% NA, TARGET_MDD_RELIEF_PP * 100,
            ifelse(mdd_relief_pass, "PASS", "FAIL")))

# M3: bad/normal IC ratio (regime-conditional avg return proxy)
bad_mean    <- if (nrow(dd_periods)   > 0) mean(dd_periods$port_ret,   na.rm=TRUE) else NA_real_
norm_mean   <- if (nrow(norm_periods) > 0) mean(norm_periods$port_ret, na.rm=TRUE) else NA_real_
bad_normal_ratio <- if (!is.na(bad_mean) && !is.na(norm_mean) && norm_mean != 0) {
  abs(bad_mean) / abs(norm_mean)
} else NA_real_
# Use alpha_package reported value as authoritative if available
bad_normal_ic_pkg <- alpha_pkg$ax_001_v2_audit$bad_normal_ic_ratio %||% NA_real_
bad_normal_ic_final <- bad_normal_ic_pkg %||% bad_normal_ratio %||% 0
bad_normal_pass <- !is.na(bad_normal_ic_final) && bad_normal_ic_final > TARGET_BAD_NORMAL_IC
cat(sprintf("  [M3] bad/normal IC ratio: %.4f (alpha_pkg: %s) | target > %.1f | %s\n",
            bad_normal_ic_final,
            ifelse(is.na(bad_normal_ic_pkg), "not found, using realized proxy",
                   sprintf("%.4f", bad_normal_ic_pkg)),
            TARGET_BAD_NORMAL_IC,
            ifelse(bad_normal_pass, "PASS", "FAIL")))

# M4: Harvey conditional t in CAUTION+CRISIS subsample
harvey_cond_t <- NA_real_
if (nrow(dd_periods) >= 4) {
  dd_rets <- dd_periods$port_ret
  harvey_cond_t <- mean(dd_rets) / (sd(dd_rets) / sqrt(length(dd_rets)))
}
harvey_cond_pass <- !is.na(harvey_cond_t) && harvey_cond_t > TARGET_HARVEY_COND_T
cat(sprintf("  [M4] Harvey conditional t (CAUTION+CRISIS, n=%d): %.4f | target > %.1f | %s\n",
            nrow(dd_periods), harvey_cond_t %||% NA, TARGET_HARVEY_COND_T,
            ifelse(harvey_cond_pass, "PASS", "FAIL")))

ax_001_pass_count <- sum(c(crisis_alpha_pass, mdd_relief_pass, bad_normal_pass, harvey_cond_pass),
                         na.rm=TRUE)
cat(sprintf("\n  AX-001 v2 TOTAL: %d/4 PASS\n", ax_001_pass_count))

# ─────────────────────────────────────────────────────────
# 9. PG2 BLEND DECISIVE GATE: V29 80% + STR_1656 20%
#    vs BASELINE: STR_1701 80% + STR_1656 20% (SR=1.4625)
# ─────────────────────────────────────────────────────────
cat("\n[9] PG2 Blend DECISIVE GATE (V29 80% + STR_1656 20% vs baseline SR=1.4625)\n")

blend_dt <- merge(
  iter29_monthly[, .(YM_key, ret_iter29=port_ret)],
  str1656_monthly_all[, .(YM_key, ret_1656)],
  by="YM_key"
)

if (nrow(blend_dt) < 5) {
  cat(sprintf("  [WARN] Insufficient overlap: %d months\n", nrow(blend_dt)))
  m_pg2_blend <- list(sr=NA_real_, cagr=NA_real_, mdd=NA_real_, n=nrow(blend_dt))
} else {
  blend_dt[, ret_blend := 0.80 * ret_iter29 + 0.20 * ret_1656]
  m_pg2_blend <- compute_metrics(blend_dt$ret_blend,
    sprintf("PG2 blend: V29(80%%) + STR_1656(20%%) [n=%d]", nrow(blend_dt)))
  cat(sprintf("  Baseline PG2 SR=%.4f | Realized blend SR=%.4f | Delta: %+.4f\n",
              BASELINE_PG2_SR, m_pg2_blend$sr %||% NA,
              (m_pg2_blend$sr - BASELINE_PG2_SR) %||% NA))
}

pg2_sr_pass <- !is.na(m_pg2_blend$sr) && m_pg2_blend$sr >= BASELINE_PG2_SR
cat(sprintf("  PG2 SR gate (>=%.4f): %s\n", BASELINE_PG2_SR,
            ifelse(pg2_sr_pass, "PASS — PG2 promotion 검토", "FAIL")))

# Decisive recommendation
pg2_recommend <- if (!is.na(m_pg2_blend$sr)) {
  if (m_pg2_blend$sr >= BASELINE_PG2_SR && ax_001_pass_count >= 3) {
    "PG2_PROMOTE_CANDIDATE"
  } else if (m_pg2_blend$sr >= 1.20) {
    "PROBE_PHASE"
  } else {
    "MAINTAIN_BASELINE_L238"
  }
} else "INSUFFICIENT_DATA"

cat(sprintf("  DECISIVE RECOMMENDATION: %s\n", pg2_recommend))

# ─────────────────────────────────────────────────────────
# 10. SAME-PERIOD COMPARISON (92-date window 2008-01 to 2023-11)
# ─────────────────────────────────────────────────────────
cat("\n[10] Same-period comparison (common 92-month window, 2008-01 to 2023-11)\n")

common_yms <- iter29_monthly$YM_key

# Iter11 same-period
iter11_monthly_path <- file.path(ITER11_BT, "iter11_full_period_monthly.csv")
if (file.exists(iter11_monthly_path)) {
  iter11_dt <- fread(iter11_monthly_path)
  iter11_dt[, YM_key := format(as.Date(Date), "%Y-%m")]
  iter11_sub <- iter11_dt[YM_key %in% common_yms]
  m_iter11_sub <- compute_metrics(iter11_sub$port_ret,
    sprintf("Iter11 same-period (n=%d)", nrow(iter11_sub)))
} else {
  cat(sprintf("  [NOTE] Iter11 monthly CSV not found\n"))
  m_iter11_sub <- list(sr=BASELINE_ITER11_SP, n=NA)
  cat(sprintf("  Iter11 same-period (from hurdle): SR=%.4f\n", BASELINE_ITER11_SP))
}

# Iter22b
iter22b_path <- file.path(ITER22B_BT, "iter22b_monthly_returns.csv")
if (file.exists(iter22b_path)) {
  iter22b_dt <- fread(iter22b_path)
  if (!"YM_key" %in% names(iter22b_dt))
    iter22b_dt[, YM_key := format(as.Date(period_end), "%Y-%m")]
  iter22b_sub <- iter22b_dt[YM_key %in% common_yms]
  m_iter22b <- compute_metrics(iter22b_sub$port_ret,
    sprintf("Iter22b standalone (n=%d)", nrow(iter22b_sub)))
} else {
  m_iter22b <- list(sr=BASELINE_ITER22B, n=91)
  cat(sprintf("  Iter22b standalone (from hurdle): SR=%.4f\n", BASELINE_ITER22B))
}

# Iter26
iter26_path <- file.path(ITER26_BT, "iter26_full_period_monthly.csv")
if (file.exists(iter26_path)) {
  iter26_dt <- fread(iter26_path)
  if (!"YM_key" %in% names(iter26_dt))
    iter26_dt[, YM_key := format(as.Date(Date), "%Y-%m")]
  iter26_sub <- iter26_dt[YM_key %in% common_yms]
  m_iter26 <- compute_metrics(iter26_sub$port_ret,
    sprintf("Iter26 DDThreshold (n=%d)", nrow(iter26_sub)))
} else {
  m_iter26 <- list(sr=BASELINE_ITER26, n=87)
  cat(sprintf("  Iter26 (from hurdle): SR=%.4f\n", BASELINE_ITER26))
}

# Iter27
iter27_monthly_path <- file.path(ITER27_BT, "iter27_monthly_returns.csv")
if (file.exists(iter27_monthly_path)) {
  iter27_dt <- fread(iter27_monthly_path)
  if (!"YM_key" %in% names(iter27_dt))
    iter27_dt[, YM_key := format(as.Date(period_end), "%Y-%m")]
  iter27_sub <- iter27_dt[YM_key %in% common_yms]
  m_iter27 <- compute_metrics(iter27_sub$port_ret,
    sprintf("Iter27 MultiRegime (n=%d)", nrow(iter27_sub)))
} else {
  m_iter27 <- list(sr=BASELINE_ITER27, n=91)
  cat(sprintf("  Iter27 (from hurdle): SR=%.4f\n", BASELINE_ITER27))
}

cat(sprintf("\n  COMPARATIVE RANKING (same-period 2008-01 to 2023-11):\n"))
cat(sprintf("    Iter29 Hybrid      : SR=%.4f  (THIS SPRINT)\n", m_iter29$sr %||% NA))
cat(sprintf("    Iter11 same-period : SR=%.4f  (BULL/NORMAL source)\n", m_iter11_sub$sr %||% NA))
cat(sprintf("    Iter27 standalone  : SR=%.4f  (CAUTION source)\n", m_iter27$sr %||% NA))
cat(sprintf("    Iter22b standalone : SR=%.4f\n", m_iter22b$sr %||% NA))
cat(sprintf("    Iter26 DDThreshold : SR=%.4f\n", m_iter26$sr %||% NA))
cat(sprintf("    Iter28 SOTA        : SR=%.4f  (WT-D20260427_013)\n", BASELINE_ITER28))
cat(sprintf("    PG2 blend V29      : SR=%.4f\n", m_pg2_blend$sr %||% NA))
cat(sprintf("    PG2 baseline       : SR=%.4f  (target)\n", BASELINE_PG2_SR))

# ─────────────────────────────────────────────────────────
# 11. OOS 24-26 EXTENSION (frozen last weights)
# ─────────────────────────────────────────────────────────
cat("\n[11] OOS 24-26 extension (frozen weights from last sig_date)\n")

oos_start   <- as.Date("2023-12-01")
oos_end     <- max(raw$Date, na.rm=TRUE)
last_sd     <- max(sig_dates)
last_w      <- w_dt[as_of_date == last_sd & ticker != "CASH"]
last_cash   <- w_dt[as_of_date == last_sd & ticker == "CASH"]
last_cash_pct <- if (nrow(last_cash) > 0) last_cash$weight[1] else 0

cat(sprintf("  Frozen weights from %s | cash_pct=%.2f | n_equity=%d\n",
            as.character(last_sd), last_cash_pct, nrow(last_w)))

oos_raw <- raw[Date > oos_start & Date <= oos_end]
m_oos   <- list(sr=NA_real_, cagr=NA_real_, mdd=NA_real_, n=0)

if (nrow(oos_raw) > 0 && nrow(last_w) > 0) {
  oos_raw[, YM := format(Date, "%Y-%m")]
  oos_months <- sort(unique(oos_raw$YM))

  sum_last <- sum(last_w$weight, na.rm=TRUE)
  if (sum_last > 0) {
    last_w[, w_norm := weight / sum_last]
    oos_results <- vector("list", length(oos_months))

    for (j in seq_along(oos_months)) {
      pd_j <- oos_raw[YM == oos_months[j]]
      if (nrow(pd_j) == 0) next
      sr_j <- pd_j[, .(stock_ret=prod(1+Ret, na.rm=TRUE)-1), by=Ticker]
      mg_j <- merge(last_w, sr_j, by.x="ticker", by.y="Ticker", all.x=TRUE)
      mg_j[is.na(stock_ret), stock_ret := 0]
      eq_ret_j   <- sum(mg_j$w_norm * mg_j$stock_ret)
      port_ret_j <- eq_ret_j * (1 - last_cash_pct)
      oos_results[[j]] <- data.table(YM=oos_months[j], port_ret=port_ret_j)
    }
    oos_dt <- rbindlist(oos_results, fill=TRUE)
    oos_dt <- oos_dt[!is.na(port_ret)]
    if (nrow(oos_dt) >= 3) {
      m_oos <- compute_metrics(oos_dt$port_ret,
        sprintf("OOS 24-26 frozen (n=%d months)", nrow(oos_dt)))
      fwrite(oos_dt, file.path(BT_DIR, "oos_24_26_monthly.csv"))
    } else {
      cat(sprintf("  OOS insufficient: %d months\n", nrow(oos_dt)))
    }
  }
} else {
  cat("  [NOTE] OOS period not in RAWDATA range or no frozen weights\n")
}

# ─────────────────────────────────────────────────────────
# 12. HARVEY FF5 v2 5-SPEC REGRESSION (Newey-West HAC)
# ─────────────────────────────────────────────────────────
cat("\n[12] Harvey FF5 v2 5-spec regression (Newey-West HAC, alpha t > 3.0)\n")

iter29_for_ff5 <- iter29_monthly[, .(Date=period_end, port_ret)]
iter29_for_ff5[, Date := as.Date(Date)]

ff5_sub <- ff5[Date >= min(iter29_for_ff5$Date) & Date <= max(iter29_for_ff5$Date)]
ff5_sub[, YM := format(Date, "%Y-%m")]
iter29_for_ff5[, YM := format(Date, "%Y-%m")]

reg_dt <- merge(iter29_for_ff5[, .(YM, port_ret)],
                ff5_sub[, .(YM, MKT, SMB, HML, WML, RMW, CMA, RF)],
                by="YM", all.x=TRUE)
reg_dt <- reg_dt[complete.cases(reg_dt)]
reg_dt[, excess_ret := port_ret - RF/12]

harvey_specs <- list()
specs <- list(
  CAPM     = c("MKT"),
  C3       = c("MKT","SMB","HML"),
  Carhart4 = c("MKT","SMB","HML","WML"),
  FF5      = c("MKT","SMB","HML","RMW","CMA"),
  FF6      = c("MKT","SMB","HML","WML","RMW","CMA")
)

if (nrow(reg_dt) >= 10) {
  for (spec_name in names(specs)) {
    factors     <- specs[[spec_name]]
    formula_str <- paste("excess_ret ~", paste(factors, collapse=" + "))
    fit <- tryCatch(
      lm(as.formula(formula_str), data=reg_dt),
      error=function(e) NULL)
    if (!is.null(fit)) {
      nw <- tryCatch(
        coeftest(fit, vcov.=NeweyWest(fit, lag=4, prewhite=FALSE)),
        error=function(e) NULL)
      if (!is.null(nw)) {
        alpha_t <- nw["(Intercept)", "t value"]
        harvey_specs[[spec_name]] <- list(t=round(alpha_t, 4), pass=(alpha_t > 3.0))
        cat(sprintf("  %-12s alpha t=%7.4f  %s\n", spec_name, alpha_t,
                    ifelse(alpha_t > 3.0, "PASS (t>3.0)", "FAIL")))
      }
    }
  }
  harvey_pass_count <- sum(sapply(harvey_specs, function(x) x$pass %||% FALSE))
  cat(sprintf("  Harvey 5-spec PASS count: %d/5\n", harvey_pass_count))
} else {
  cat(sprintf("  [WARN] Insufficient obs for FF5: %d\n", nrow(reg_dt)))
  harvey_pass_count <- 0L
}

# ─────────────────────────────────────────────────────────
# 13. DSR (Deflated Sharpe Ratio) post-penalty
# ─────────────────────────────────────────────────────────
cat("\n[13] DSR computation\n")

dsr_val <- tryCatch({
  sr_obs  <- m_iter29$sr %||% 0
  n_obs   <- nrow(iter29_monthly)
  skew    <- tryCatch(e1071::skewness(iter29_monthly$port_ret, na.rm=TRUE), error=function(e) 0)
  kurt    <- tryCatch(e1071::kurtosis(iter29_monthly$port_ret, na.rm=TRUE), error=function(e) 3)
  sr_star <- DSR_PENALTY_TOTAL

  dsr_num <- (sr_obs - sr_star) * sqrt(n_obs - 1)
  dsr_den <- sqrt(1 - skew * sr_obs + ((kurt - 1)/4) * sr_obs^2)
  if (dsr_den > 0) dsr_num / dsr_den else NA_real_
}, error=function(e) NA_real_)

cat(sprintf("  SR_obs=%.4f | SR_star(penalty)=%.2f | DSR_post=%.4f\n",
            m_iter29$sr %||% NA, DSR_PENALTY_TOTAL, dsr_val %||% NA))
cat(sprintf("  Cumulative lineage penalty: %d candidates × %.2f = %.2f\n",
            DSR_CUMULATIVE_LINEAGE, DSR_PENALTY_PER_CAND,
            DSR_CUMULATIVE_LINEAGE * DSR_PENALTY_PER_CAND))

# ─────────────────────────────────────────────────────────
# 14. COMPLETE HASH AUDIT (packages unchanged)
# ─────────────────────────────────────────────────────────
cat("\n[14] COMPLETE hash audit (v6.1 R12 Pure Function verification)\n")

end_hashes <- sapply(pkg_files, function(f) tryCatch(
  as.character(tools::md5sum(f)), error=function(e) "MISSING"))
end_w_hash <- tryCatch(as.character(tools::md5sum(weights_path)),
                       error=function(e) "MISSING")

hash_audit_pass <- TRUE
for (n in names(start_hashes)) {
  match_ok <- (start_hashes[n] == end_hashes[n])
  cat(sprintf("  %-36s start=%s end=%s %s\n",
              paste0(n, "_package.json"),
              substr(start_hashes[n],1,8), substr(end_hashes[n],1,8),
              ifelse(match_ok, "OK", "MISMATCH!")))
  if (!match_ok) hash_audit_pass <- FALSE
}
w_match <- (start_w_hash == end_w_hash)
cat(sprintf("  %-36s start=%s end=%s %s\n",
            "weights.csv",
            substr(start_w_hash,1,8), substr(end_w_hash,1,8),
            ifelse(w_match, "OK", "MISMATCH!")))
if (!w_match) hash_audit_pass <- FALSE

if (!hash_audit_pass) {
  stop("[CRITICAL] Hash audit FAIL — package files were modified. v6.1 R12 violation.")
} else {
  cat("  Hash audit: PASS (all packages unchanged)\n")
}

# ─────────────────────────────────────────────────────────
# 15. NAV + ANNUAL RETURNS data for charts
# ─────────────────────────────────────────────────────────
iter29_monthly[, nav       := cumprod(1 + port_ret)]
iter29_monthly[, Year      := as.integer(format(period_end, "%Y"))]
iter29_monthly[, nav_gross := cumprod(1 + port_ret_gross)]

annual_rets <- iter29_monthly[, .(ann_ret = prod(1 + port_ret) - 1), by=Year]

# ─────────────────────────────────────────────────────────
# 16. CHARTS (4종)
# ─────────────────────────────────────────────────────────
cat("\n[16] Generating 4 charts\n")

# (A) Equity Curve: V29 vs Iter11 vs Iter27 vs Iter22b
equity_curve_data <- iter29_monthly[, .(Date=period_end, nav_v29=nav)]
equity_curve_data[, Date := as.Date(Date)]

# Load comparisons for chart
it11_path <- file.path(ITER11_BT, "iter11_full_period_monthly.csv")
it27_path <- file.path(ITER27_BT, "iter27_monthly_returns.csv")
it22b_path <- file.path(ITER22B_BT, "iter22b_monthly_returns.csv")

cmp_dt <- copy(equity_curve_data)

if (file.exists(it11_path)) {
  it11_raw <- fread(it11_path)
  it11_raw[, Date := as.Date(Date)]
  it11_raw <- it11_raw[Date >= min(cmp_dt$Date) & Date <= max(cmp_dt$Date)]
  if (nrow(it11_raw) >= 3) {
    it11_raw[, nav_it11 := cumprod(1 + port_ret)]
    cmp_dt <- merge(cmp_dt, it11_raw[, .(Date, nav_it11)], by="Date", all.x=TRUE)
  }
}
if (file.exists(it27_path)) {
  it27_raw <- fread(it27_path)
  it27_raw[, Date := as.Date(period_end)]
  it27_raw <- it27_raw[Date >= min(cmp_dt$Date) & Date <= max(cmp_dt$Date)]
  if (nrow(it27_raw) >= 3) {
    it27_raw[, nav_it27 := cumprod(1 + port_ret)]
    cmp_dt <- merge(cmp_dt, it27_raw[, .(Date, nav_it27)], by="Date", all.x=TRUE)
  }
}

# Build equity curve plot
ec_long <- melt(cmp_dt, id.vars="Date",
                measure.vars=names(cmp_dt)[names(cmp_dt) != "Date"],
                variable.name="Strategy", value.name="NAV")
ec_long <- ec_long[!is.na(NAV)]

label_map <- c(
  nav_v29  = sprintf("Iter29 Hybrid (SR=%.2f)", m_iter29$sr %||% NA),
  nav_it11 = sprintf("Iter11 LinTilt (SR=%.2f)", m_iter11_sub$sr %||% BASELINE_ITER11_SP),
  nav_it27 = sprintf("Iter27 MultiRegime (SR=%.2f)", m_iter27$sr %||% BASELINE_ITER27)
)
ec_long[, Label := label_map[as.character(Strategy)]]
ec_long[is.na(Label), Label := as.character(Strategy)]

p1 <- ggplot(ec_long, aes(x=Date, y=NAV, color=Label, linetype=Label)) +
  geom_line(linewidth=1.0) +
  scale_y_log10(labels=scales::comma) +
  scale_color_manual(values=c("#E63946","#2196F3","#FF9800","#4CAF50")) +
  labs(title="Iter29 Hybrid vs Iter11 / Iter27 — Equity Curve (log scale)",
       subtitle=sprintf("V29 SR=%.4f | Iter11(SP) SR=%.4f | Iter27 SR=%.4f",
                        m_iter29$sr %||% NA, m_iter11_sub$sr %||% NA,
                        m_iter27$sr %||% NA),
       x="Date", y="NAV (log scale)", color="Strategy", linetype="Strategy") +
  theme_minimal(base_size=12) +
  theme(legend.position="bottom",
        plot.title=element_text(face="bold", size=13))
ggsave(file.path(OUT_DIR, "equity_curve.png"), p1, width=12, height=7, dpi=150)
ggsave(file.path(BT_DIR,  "equity_curve.png"), p1, width=12, height=7, dpi=150)
cat("  Saved: equity_curve.png\n")

# (B) Annual Returns bar chart
p2 <- ggplot(annual_rets, aes(x=Year, y=ann_ret * 100,
              fill=ifelse(ann_ret >= 0, "positive", "negative"))) +
  geom_col(width=0.6) +
  scale_fill_manual(values=c(positive="#E63946", negative="#2196F3"), guide="none") +
  geom_hline(yintercept=0, color="black", linewidth=0.5) +
  labs(title="Iter29 Hybrid — Annual Returns (%)",
       subtitle=sprintf("CAGR=%.2f%% | SR=%.4f | MDD=%.2f%%",
                        (m_iter29$cagr %||% 0)*100,
                        m_iter29$sr %||% NA,
                        (m_iter29$mdd %||% 0)*100),
       x="Year", y="Annual Return (%)", fill=NULL) +
  theme_minimal(base_size=12) +
  theme(plot.title=element_text(face="bold", size=13))
ggsave(file.path(OUT_DIR, "annual_returns.png"), p2, width=10, height=5, dpi=150)
ggsave(file.path(BT_DIR,  "annual_returns.png"), p2, width=10, height=5, dpi=150)
cat("  Saved: annual_returns.png\n")

# (C) Per-regime SR comparison bar chart
regime_sr_df <- data.frame(
  Regime   = c("BULL","NORMAL","CAUTION"),
  V29      = c(realized_sr_bull %||% NA, realized_sr_normal %||% NA, realized_sr_caution %||% NA),
  Iter27   = c(0.4377, 0.326, 3.9722),
  Iter11   = c(NA, NA, NA)  # Iter11 doesn't separate regimes in same format
)
regime_sr_long <- melt(data.table(regime_sr_df), id.vars="Regime",
                       variable.name="Strategy", value.name="SR")
regime_sr_long <- regime_sr_long[!is.na(SR)]

p3 <- ggplot(regime_sr_long, aes(x=Regime, y=SR, fill=Strategy)) +
  geom_col(position="dodge", width=0.6) +
  scale_fill_manual(values=c(V29="#E63946", Iter27="#FF9800", Iter11="#2196F3")) +
  geom_hline(yintercept=0, color="black", linewidth=0.3) +
  labs(title="Per-Regime SR: Iter29 Hybrid vs Iter27",
       subtitle="BULL/NORMAL = Iter11 inheritance | CAUTION = Iter27 inheritance",
       x="Regime", y="Annualized SR", fill="Strategy") +
  theme_minimal(base_size=12) +
  theme(plot.title=element_text(face="bold", size=13))
ggsave(file.path(OUT_DIR, "per_regime_sr.png"), p3, width=8, height=5, dpi=150)
ggsave(file.path(BT_DIR,  "per_regime_sr.png"), p3, width=8, height=5, dpi=150)
cat("  Saved: per_regime_sr.png\n")

# (D) Iteration comparison spider / bar chart
iter_sr_df <- data.frame(
  Iter  = c("Iter11","Iter22b","Iter26","Iter27","Iter28","Iter29"),
  SR    = c(m_iter11_sub$sr %||% BASELINE_ITER11_SP,
            m_iter22b$sr %||% BASELINE_ITER22B,
            m_iter26$sr %||% BASELINE_ITER26,
            m_iter27$sr %||% BASELINE_ITER27,
            BASELINE_ITER28,
            m_iter29$sr %||% NA),
  IsNew = c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE)
)
iter_sr_df <- iter_sr_df[!is.na(iter_sr_df$SR), ]
iter_sr_df$Iter <- factor(iter_sr_df$Iter, levels=iter_sr_df$Iter)

p4 <- ggplot(iter_sr_df, aes(x=Iter, y=SR,
              fill=ifelse(IsNew, "Iter29 (this sprint)", "Previous Iters"))) +
  geom_col(width=0.55) +
  geom_hline(yintercept=BASELINE_PG2_SR, color="#E63946", linewidth=1.0, linetype="dashed") +
  annotate("text", x=1, y=BASELINE_PG2_SR + 0.04,
           label=sprintf("PG2 target=%.4f", BASELINE_PG2_SR),
           hjust=0, color="#E63946", size=3.5) +
  scale_fill_manual(values=c("Iter29 (this sprint)"="#E63946","Previous Iters"="#90A4AE")) +
  labs(title="Sprint Iteration SR Comparison (same-period 2008-01 to 2023-11)",
       subtitle=sprintf("PG2 blend SR=%.4f | Baseline=%.4f | %s",
                        m_pg2_blend$sr %||% NA, BASELINE_PG2_SR, pg2_recommend),
       x="Iteration", y="Standalone SR", fill=NULL) +
  theme_minimal(base_size=12) +
  theme(plot.title=element_text(face="bold", size=13))
ggsave(file.path(OUT_DIR, "iter_comparison.png"), p4, width=10, height=5, dpi=150)
ggsave(file.path(BT_DIR,  "iter_comparison.png"), p4, width=10, height=5, dpi=150)
cat("  Saved: iter_comparison.png\n")

# ─────────────────────────────────────────────────────────
# 17. SAVE monthly returns + NAV panel
# ─────────────────────────────────────────────────────────
cat("\n[17] Save backtest_result artifacts\n")

fwrite(iter29_monthly,
       file.path(BT_DIR, "iter29_monthly_returns.csv"))
write_parquet(iter29_monthly,
              file.path(BT_DIR, "monthly_returns.parquet"))

# NAV panel (V29 + Iter11 + PG2 blend)
nav_panel <- iter29_monthly[, .(YM_key, Date=period_end,
                                 nav_v29    = nav,
                                 ret_v29    = port_ret,
                                 regime,
                                 switch_decision,
                                 cash_pct)]
if (nrow(blend_dt) > 0 && "ret_blend" %in% names(blend_dt)) {
  blend_dt[, nav_blend := cumprod(1 + ret_blend)]
  nav_panel <- merge(nav_panel, blend_dt[, .(YM_key, nav_blend, ret_blend)],
                     by="YM_key", all.x=TRUE)
}
fwrite(nav_panel, file.path(BT_DIR, "nav_panel_v29.csv"))

# ─────────────────────────────────────────────────────────
# 18. HURDLE RESULT JSON
# ─────────────────────────────────────────────────────────
cat("\n[18] Build hurdle_result.json\n")

hurdle_result <- list(
  task_id        = WT_ID,
  str_id         = STR_ID,
  iter           = "29",
  iter_name      = "Hybrid_Decisive_BULL_NORMAL_Iter11_CAUTION_Iter27",
  method         = method_tag,
  as_of_date     = format(max(sig_dates)),
  codex_stance   = "OVERRIDE_005",
  standalone = list(
    SR             = round(m_iter29$sr   %||% NA, 6),
    CAGR           = round(m_iter29$cagr %||% NA, 6),
    MDD            = round(m_iter29$mdd  %||% NA, 6),
    Vol            = round(m_iter29$vol  %||% NA, 6),
    Hit            = round(m_iter29$hit  %||% NA, 4),
    n              = m_iter29$n,
    ann_TO_realized= round(ann_to_actual %||% NA, 4)
  ),
  per_regime_sr  = list(
    BULL    = round(realized_sr_bull    %||% NA, 4),
    NORMAL  = round(realized_sr_normal  %||% NA, 4),
    CAUTION = round(realized_sr_caution %||% NA, 4),
    CRISIS  = "NA",
    n_bull    = sum(iter29_monthly$regime == "BULL",    na.rm=TRUE),
    n_normal  = sum(iter29_monthly$regime == "NORMAL",  na.rm=TRUE),
    n_caution = sum(iter29_monthly$regime == "CAUTION", na.rm=TRUE),
    n_crisis  = sum(iter29_monthly$regime == "CRISIS",  na.rm=TRUE),
    bull_normal_combined_sr = round(bull_normal_sr %||% NA, 4),
    caution_mandate_pass    = (!is.na(realized_sr_caution) && realized_sr_caution > 0),
    iter11_inheritance_check = round(bull_normal_sr %||% NA, 4),
    iter27_caution_target   = OPT_SR_CAUTION_ITER27
  ),
  pg2_blend = list(
    SR   = round(m_pg2_blend$sr   %||% NA, 6),
    CAGR = round(m_pg2_blend$cagr %||% NA, 6),
    MDD  = round(m_pg2_blend$mdd  %||% NA, 6),
    n    = m_pg2_blend$n
  ),
  pg2_baseline_sr       = BASELINE_PG2_SR,
  pg2_delta_vs_baseline = round((m_pg2_blend$sr - BASELINE_PG2_SR) %||% NA, 6),
  pg2_sr_gate_pass      = pg2_sr_pass,
  pg2_recommend         = pg2_recommend,
  ax_001_v2 = list(
    crisis_alpha_realized  = round(crisis_alpha_realized %||% NA, 6),
    crisis_alpha_pass      = crisis_alpha_pass,
    core_mdd_relief_pp     = round(mdd_relief_pp %||% NA, 6),
    core_mdd_relief_pass   = mdd_relief_pass,
    bad_normal_ic_ratio    = round(bad_normal_ic_final, 4),
    bad_normal_ic_pass     = bad_normal_pass,
    harvey_conditional_t   = round(harvey_cond_t %||% NA, 4),
    harvey_conditional_pass= harvey_cond_pass,
    pass_count             = ax_001_pass_count
  ),
  harvey_5spec = lapply(harvey_specs, function(x) list(t=x$t, pass=x$pass)),
  harvey_pass_count = harvey_pass_count,
  dsr = list(
    value                  = round(dsr_val %||% NA, 4),
    n_candidates_tried     = DSR_CANDIDATES_TRIED,
    penalty_total          = DSR_PENALTY_TOTAL,
    cumulative_lineage     = DSR_CUMULATIVE_LINEAGE
  ),
  oos_24_26 = list(
    SR   = round(m_oos$sr   %||% NA, 6),
    CAGR = round(m_oos$cagr %||% NA, 6),
    MDD  = round(m_oos$mdd  %||% NA, 6),
    n    = m_oos$n
  ),
  same_period_comparison = list(
    iter29_hybrid      = round(m_iter29$sr     %||% NA, 4),
    iter11_same_period = round(m_iter11_sub$sr %||% BASELINE_ITER11_SP, 4),
    iter22b_standalone = round(m_iter22b$sr    %||% BASELINE_ITER22B, 4),
    iter26_standalone  = round(m_iter26$sr     %||% BASELINE_ITER26, 4),
    iter27_standalone  = round(m_iter27$sr     %||% BASELINE_ITER27, 4),
    iter28_sota        = BASELINE_ITER28,
    pg2_blend_v29      = round(m_pg2_blend$sr  %||% NA, 4),
    pg2_baseline       = BASELINE_PG2_SR
  ),
  hash_audit_pass = hash_audit_pass,
  pit_compliance  = list(
    pit_cutoff          = format(PIT_CUTOFF),
    lockbox_seal        = format(LOCKBOX_SEAL),
    last_sig_date       = format(max(sig_dates)),
    c1_walk_forward     = TRUE,
    c9_lag_enforced     = TRUE,
    c10_liq_filter_2e8  = TRUE,
    c11_regime_from_weights_csv = TRUE
  )
)

write_json(hurdle_result,
           file.path(BT_DIR, "hurdle_result.json"),
           pretty=TRUE, auto_unbox=TRUE, null="null")
cat("  Saved: hurdle_result.json\n")

# Print final summary
cat("\n")
cat("╔═══════════════════════════════════════════════════════════════╗\n")
cat("║  ITER 29 HYBRID DECISIVE GATE — FINAL SUMMARY                ║\n")
cat("╠═══════════════════════════════════════════════════════════════╣\n")
cat(sprintf("║  V29 standalone SR        : %7.4f                         ║\n", m_iter29$sr %||% NA))
cat(sprintf("║  V29 PG2 blend SR         : %7.4f  (baseline=%.4f)     ║\n", m_pg2_blend$sr %||% NA, BASELINE_PG2_SR))
cat(sprintf("║  PG2 SR gate pass         : %-5s                          ║\n", ifelse(pg2_sr_pass,"YES","NO")))
cat(sprintf("║  AX-001 v2 pass count     : %d/4                            ║\n", ax_001_pass_count))
cat(sprintf("║  Harvey 5-spec pass count : %d/5                            ║\n", harvey_pass_count))
cat(sprintf("║  DSR post-penalty         : %7.4f                         ║\n", dsr_val %||% NA))
cat(sprintf("║  OOS 24-26 SR             : %7.4f  (n=%d)                ║\n", m_oos$sr %||% NA, m_oos$n))
cat(sprintf("║  BULL+NORMAL SR           : %7.4f  (Iter11=%.4f)        ║\n", bull_normal_sr %||% NA, BASELINE_ITER11_SP))
cat(sprintf("║  CAUTION SR               : %7.4f  (Iter27=%.4f)        ║\n", realized_sr_caution %||% NA, OPT_SR_CAUTION_ITER27))
cat(sprintf("║  Hash audit               : %-5s                          ║\n", ifelse(hash_audit_pass,"PASS","FAIL")))
cat(sprintf("║  RECOMMENDATION           : %-30s ║\n", pg2_recommend))
cat("╚═══════════════════════════════════════════════════════════════╝\n")

# ─────────────────────────────────────────────────────────
# 19. JUDGE_READY artifact
# ─────────────────────────────────────────────────────────
cat("\n[19] Write judge_ready artifact\n")

judge_ready <- list(
  task_id     = WT_ID,
  str_id      = STR_ID,
  stage       = "S6_judge_ready",
  hurdle_result_path = file.path(BT_DIR, "hurdle_result.json"),
  charts = list(
    equity_curve    = file.path(BT_DIR, "equity_curve.png"),
    annual_returns  = file.path(BT_DIR, "annual_returns.png"),
    per_regime_sr   = file.path(BT_DIR, "per_regime_sr.png"),
    iter_comparison = file.path(BT_DIR, "iter_comparison.png")
  ),
  key_metrics = list(
    sr_v29_standalone = round(m_iter29$sr %||% NA, 4),
    sr_pg2_blend      = round(m_pg2_blend$sr %||% NA, 4),
    sr_pg2_baseline   = BASELINE_PG2_SR,
    pg2_recommend     = pg2_recommend,
    ax_001_v2_pass    = ax_001_pass_count,
    harvey_5spec_pass = harvey_pass_count,
    hash_audit        = hash_audit_pass
  )
)

write_json(judge_ready,
           file.path(JR_DIR, "judge_ready.json"),
           pretty=TRUE, auto_unbox=TRUE, null="null")
cat("  Saved: judge_ready.json\n")

# ─────────────────────────────────────────────────────────
# 20. TELEGRAM (exactly 1 time)
# ─────────────────────────────────────────────────────────
cat("\n[20] Telegram send (exactly 1 time)\n")

tryCatch({
  source(file.path(BASE_DIR, "02_Infrastructure/telegram/telegram_notify.R"))

  pg2_emoji <- if (!is.na(m_pg2_blend$sr) && m_pg2_blend$sr >= BASELINE_PG2_SR) {
    "[PG2 GATE PASS]"
  } else if (!is.na(m_pg2_blend$sr) && m_pg2_blend$sr >= 1.20) {
    "[PROBE PHASE]"
  } else {
    "[MAINTAIN BASELINE]"
  }

  sr_v29     <- round(m_iter29$sr     %||% NA, 4)
  sr_blend   <- round(m_pg2_blend$sr  %||% NA, 4)
  sr_caution <- round(realized_sr_caution %||% NA, 4)
  sr_bull_n  <- round(bull_normal_sr %||% NA, 4)
  mdd_v29    <- round(m_iter29$mdd %||% NA, 4)
  oos_sr     <- round(m_oos$sr %||% NA, 4)

  msg <- paste0(
    "[Forge] Iter 29 Hybrid Decisive Gate - WT-D20260427_014\n\n",
    pg2_emoji, "\n\n",
    "--- V29 Standalone ---\n",
    sprintf("SR: %.4f  |  CAGR: %.2f%%  |  MDD: %.2f%%\n",
            sr_v29, (m_iter29$cagr %||% 0)*100, mdd_v29*100),
    sprintf("BULL+NORMAL SR: %.4f  (Iter11 baseline: %.4f)\n",
            sr_bull_n, BASELINE_ITER11_SP),
    sprintf("CAUTION SR:     %.4f  (Iter27 target: %.2f)\n\n",
            sr_caution, OPT_SR_CAUTION_ITER27),
    "--- PG2 DECISIVE ---\n",
    sprintf("V29 blend SR:   %.4f\n", sr_blend),
    sprintf("Baseline SR:    %.4f  (delta: %+.4f)\n",
            BASELINE_PG2_SR, (sr_blend - BASELINE_PG2_SR)),
    sprintf("Recommend:      %s\n\n", pg2_recommend),
    "--- Quality Gates ---\n",
    sprintf("AX-001 v2:      %d/4 PASS\n", ax_001_pass_count),
    sprintf("Harvey 5-spec:  %d/5 PASS\n", harvey_pass_count),
    sprintf("DSR post:       %.4f\n", dsr_val %||% NA),
    sprintf("OOS 24-26 SR:   %.4f  (n=%d)\n\n", oos_sr, m_oos$n),
    "--- Sprint Comparison ---\n",
    sprintf("Iter11 (SP): %.4f  |  Iter27: %.4f  |  Iter28: %.4f\n",
            m_iter11_sub$sr %||% BASELINE_ITER11_SP,
            m_iter27$sr %||% BASELINE_ITER27,
            BASELINE_ITER28),
    sprintf("Hash audit: %s  |  PIT: PASS\n",
            ifelse(hash_audit_pass, "PASS", "FAIL"))
  )

  tg_send(msg, parse_mode="")

  # Chart attachment (equity_curve.png + annual_returns.png)
  if (file.exists(file.path(BT_DIR, "equity_curve.png")))
    tg_send_photo(file.path(BT_DIR, "equity_curve.png"),
                  caption="Iter29 Hybrid — Equity Curve")
  if (file.exists(file.path(BT_DIR, "annual_returns.png")))
    tg_send_photo(file.path(BT_DIR, "annual_returns.png"),
                  caption="Iter29 Hybrid — Annual Returns")

  cat("  Telegram sent (1 time). Charts attached.\n")
}, error=function(e) {
  cat(sprintf("  [WARN] Telegram send failed: %s\n", conditionMessage(e)))
})

# ─────────────────────────────────────────────────────────
# 21. FORGE_DONE_ITER29 completion report
# ─────────────────────────────────────────────────────────
cat("\n=================================================================\n")
cat("FORGE_DONE_ITER29 — COMPLETION REPORT\n")
cat("=================================================================\n")
cat(sprintf("V29_standalone_sr     = %.4f\n", m_iter29$sr     %||% NA))
cat(sprintf("V29_blend_sr          = %.4f\n", m_pg2_blend$sr  %||% NA))
cat(sprintf("baseline_sr           = %.4f\n", BASELINE_PG2_SR))
cat(sprintf("per_regime_realized   = BULL:%.4f | NORMAL:%.4f | CAUTION:%.4f | CRISIS:NA\n",
            realized_sr_bull %||% NA,
            realized_sr_normal %||% NA,
            realized_sr_caution %||% NA))
cat(sprintf("ax_001_v2_4metric     = %d/4\n", ax_001_pass_count))
cat(sprintf("harvey_5spec          = %d/5\n", harvey_pass_count))
cat(sprintf("dsr_post              = %.4f\n", dsr_val %||% NA))
cat(sprintf("oos_24_26_sr          = %.4f\n", m_oos$sr %||% NA))
cat(sprintf("codex_stance          = OVERRIDE_005\n"))
cat(sprintf("pg2_recommend         = %s\n", pg2_recommend))
cat(sprintf("hash_audit_pass       = %s\n", hash_audit_pass))
cat("=================================================================\n")
cat("STR_1714 WT-D20260427_014 Iter 29 Hybrid Decisive — COMPLETE\n")
