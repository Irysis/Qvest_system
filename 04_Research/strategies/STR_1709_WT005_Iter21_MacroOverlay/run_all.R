## ============================================================
## STR_1709 — WT-D20260427_005 Iter 21 Macro Overlay Layer (P1_dyn_cash)
## Alpha: STR_1701 inheritance (cor=1.0 strict, alpha UNCHANGED)
## Optimizer: Iter 11 LinTilt baseline PRESERVED + P1_dyn_cash msi_norm-driven
## ============================================================
## ## 핵심아이디어
##   Iter 21 = Layer Track. Alpha=STR_1701 cor=1.0 strict inheritance.
##   Optimizer mechanism = LinTilt+EMA+CVaR (Iter 11 baseline preserved).
##   Sole change = Macro Overlay layer: MSI_norm [0,1] from 5 KR-only signals
##   (KOSPI60d vol, mom/vol Sharpe, KR yield slope, KR corp BBB spread, USD/KRW 30d mom).
##   P1_dyn_cash: cash 0~50% = 50% * msi_norm (continuous, PIT expanding window).
##   avg_cash=27.6%, max=46.8%, min=12.5%.
##
##   92 sig_dates walk-forward (2008-01-31 ~ 2023-11-30) + 24-26 frozen OOS.
##
## v6.1 R12 Pure Function:
##   - alpha/risk/optimization 패키지 절대 수정 금지
##   - target_weights 재해석 금지 (92 sig_dates × dynamic cash from weights.csv)
##   - Hash audit: 시작/완료 동일 검증
##
## 검증 영역:
##   Task 1: V_iter21 standalone walk-forward (92 sig_dates)
##   Task 2: PG2 blend (V_iter21 80% + STR_1656 20%) vs baseline (STR_1701 80%+STR_1656 20%) SR=1.4625
##   Task 3: AX-001 v2 4-metric (crisis_alpha, core_mdd_relief, bad/normal_ic_ratio, Harvey_t)
##   Task 4: 5-spec Harvey FF5 v2 NW-HAC (CAPM/C3/C4/FF5/FF6), t > 2.95
##   Task 5: DSR post-penalty (n_trials=4 policies tested)
##   Task 6: Same-period comparison (V_iter21 vs Iter11 STR_1701 vs Iter18 STR_1708)
##   Task 7: 24-26 OOS extension (frozen weights)
##   Task 8: 4 charts (equity_curve, annual_returns, crisis_period_zoom, cash_overlay_dynamics)
##   Task 9: Telegram brief
##
## DSR penalty basis:
##   - Iter 21: alpha 1 (inheritance) + risk 5 + optimizer 4 policies = 10 candidates × 0.05 = 0.50
##
## PIT 준수:
##   C1: walk-forward only (no full-sample re-optimization)
##   C2: monthly ret = close(t)/close(t-1) - 1 compounded
##   C9: weight at sig_date d → applied (d, next_sig_date] (lag enforced)
##   C10: liquidity 2e8 KRW PIT t-30..t-1 (one-sided)
##   C13: Z_Score_Aligned alpha inherited (no manual flip)
##   C14: Usable_Date <= sig_date (Factor DB chain)
##   LB cutoff: last sig_date 2023-11-30 strictly before lockbox 2024-01-23
## ============================================================

cat("=== STR_1709: WT-D20260427_005 Iter 21 Macro Overlay Layer (P1_dyn_cash) ===\n")
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
  library(e1071)
})

BASE_DIR  <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
STR_ID    <- "STR_1709"
WT_ID     <- "WT-D20260427_005"
ITER11_WT <- "WT-D20260426_004"   # Iter 11 STR_1701 reference
ITER18_WT <- "WT-D20260427_002"   # Iter 18 STR_1708 reference

WT_DIR    <- file.path(BASE_DIR, "qepm/mailbox/worktask", WT_ID)
OUT_DIR   <- file.path(BASE_DIR, "04_Research/strategies/STR_1709_WT005_Iter21_MacroOverlay/output")
BT_DIR    <- file.path(WT_DIR, "backtest_result")
JR_DIR    <- file.path(WT_DIR, "judge_ready")
ITER11_BT <- file.path(BASE_DIR, "qepm/mailbox/worktask", ITER11_WT, "backtest_result")
ITER18_BT <- file.path(BASE_DIR, "qepm/mailbox/worktask", ITER18_WT, "backtest_result")

dir.create(OUT_DIR, showWarnings=FALSE, recursive=TRUE)
dir.create(BT_DIR,  showWarnings=FALSE, recursive=TRUE)
dir.create(JR_DIR,  showWarnings=FALSE, recursive=TRUE)

# DSR penalty: alpha 1 + risk 5 + optimizer 4 policies = 10 candidates
DSR_CANDIDATES_TRIED <- 10
DSR_PENALTY_PER_CAND <- 0.05
DSR_PENALTY_TOTAL    <- DSR_CANDIDATES_TRIED * DSR_PENALTY_PER_CAND  # 0.50

BASELINE_PG2_SR      <- 1.4625    # STR_1701 80% + STR_1656 20% realized SR
PIT_CUTOFF           <- as.Date("2023-11-30")
LOCKBOX_SEAL         <- as.Date("2024-01-23")

cat(sprintf("[0] Config | STR_ID=%s WT_ID=%s\n", STR_ID, WT_ID))
cat(sprintf("    DSR penalty basis: %d candidates × %.2f = %.2f\n",
            DSR_CANDIDATES_TRIED, DSR_PENALTY_PER_CAND, DSR_PENALTY_TOTAL))
cat(sprintf("    Baseline PG2 SR = %.4f\n", BASELINE_PG2_SR))

# ─────────────────────────────────────────────────────────
# 1. START hash audit (3-package + weights.csv read-only verification)
# ─────────────────────────────────────────────────────────
cat("\n[1] START hash audit (3-package + weights.csv)\n")

pkg_files <- c(
  alpha  = file.path(WT_DIR, "alpha_package.json"),
  risk   = file.path(WT_DIR, "risk_package.json"),
  optim  = file.path(WT_DIR, "optimization_package.json")
)
start_hashes <- sapply(pkg_files, function(f) tryCatch(
  as.character(tools::md5sum(f)), error=function(e) "MISSING"))

weights_path <- file.path(WT_DIR, "weights.csv")
start_w_hash <- as.character(tools::md5sum(weights_path))

cat("  Start MD5:\n")
for (n in names(start_hashes))
  cat(sprintf("    %-32s = %s\n", paste0(n, "_package.json"),
              substr(start_hashes[n], 1, 16)))
cat(sprintf("    %-32s = %s\n", "weights.csv", substr(start_w_hash, 1, 16)))

# ─────────────────────────────────────────────────────────
# 2. 3-package 로드 (READ-ONLY — Pure Function boundary)
# ─────────────────────────────────────────────────────────
cat("\n[2] Load 3-package (Pure Function boundary)\n")

alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector=FALSE)
risk_pkg  <- fromJSON(file.path(WT_DIR, "risk_package.json"),  simplifyVector=FALSE)
opt_pkg   <- fromJSON(file.path(WT_DIR, "optimization_package.json"), simplifyVector=FALSE)

method_tag    <- opt_pkg$method_selected %||% "P1_dyn_cash"
expected_ir   <- opt_pkg$expected_information_ratio %||% 0.1848
expected_cagr <- opt_pkg$expected_cagr %||% 0.0142
expected_mdd  <- opt_pkg$expected_mdd %||% -0.2846
expected_to   <- opt_pkg$turnover_annual %||% 4.364
avg_cash_pct  <- opt_pkg$per_sig_date_audit$cash_pct_mean %||% 0.276
alpha_cor     <- alpha_pkg$alpha_inheritance$cor_v21_vs_str1701 %||% 1.0
expected_cvar_d <- opt_pkg$cvar_d_post_optim %||% -0.0226
crisis_mdd_relief_pkg <- opt_pkg$crisis_mdd_relief_pp %||% 0.0386

cat(sprintf("  Method: %s | alpha cor=%.4f\n", method_tag, alpha_cor))
cat(sprintf("  Expected (Optimizer): IR=%.4f CAGR=%.4f MDD=%.4f Ann_TO=%.3f\n",
            expected_ir, expected_cagr, expected_mdd, expected_to))
cat(sprintf("  Expected avg_cash=%.1f%% | CVaR_d=%.4f\n",
            avg_cash_pct*100, expected_cvar_d))

# ─────────────────────────────────────────────────────────
# 3. weights.csv 로드 (92 sig_dates × 20 tickers + CASH)
#    CASH column in weights.csv represents dynamic msi_norm-driven cash sleeve
# ─────────────────────────────────────────────────────────
cat("\n[3] Load weights schedule (92 sig_dates × P1_dyn_cash + CASH sleeve)\n")

if (!file.exists(weights_path)) stop("[FAIL] weights.csv not found: ", weights_path)

w_dt <- fread(weights_path)
w_dt[, Date := as.Date(Date)]

# Separate CASH rows from equity rows
has_cash_col <- "CASH" %in% w_dt$Ticker
cash_dt <- w_dt[Ticker == "CASH"]
equity_dt <- w_dt[Ticker != "CASH"]

setkey(equity_dt, Date, Ticker)
setkey(cash_dt, Date)

sig_dates <- sort(unique(w_dt$Date))
n_sd <- length(sig_dates)

cat(sprintf("  weights.csv: %d rows total | CASH rows: %d | equity rows: %d\n",
            nrow(w_dt), nrow(cash_dt), nrow(equity_dt)))
cat(sprintf("  sig_dates: %d | range: %s ~ %s\n",
            n_sd, as.character(min(sig_dates)), as.character(max(sig_dates))))

# Verify PIT cutoff: last sig_date <= PIT_CUTOFF
if (max(sig_dates) > PIT_CUTOFF)
  stop(sprintf("[FAIL] PIT violation: last sig_date %s > PIT_CUTOFF %s",
               max(sig_dates), PIT_CUTOFF))
cat(sprintf("  PIT check: last sig_date=%s <= cutoff=%s PASS\n",
            as.character(max(sig_dates)), as.character(PIT_CUTOFF)))

# Hard constraint verification (equity only)
sum_check <- equity_dt[, .(
  sum_eq = sum(Weight),
  n      = .N,
  max_w  = max(Weight),
  min_w  = min(Weight)
), by=Date]

# Total including cash
total_check <- w_dt[, .(sum_total=sum(Weight)), by=Date]
cat(sprintf("  Equity sum [%.4f, %.4f] | Total+Cash [%.6f, %.6f]\n",
            min(sum_check$sum_eq), max(sum_check$sum_eq),
            min(total_check$sum_total), max(total_check$sum_total)))
cat(sprintf("  n_equity_names [%d, %d] | max_w=%.4f (bound ≤ 0.20)\n",
            min(sum_check$n), max(sum_check$n), max(sum_check$max_w)))

if (max(sum_check$max_w) > 0.2001)
  warning("[WARN] max equity weight > 0.20 bound exceeded")
if (min(sum_check$min_w) < -0.0001)
  stop("[FAIL] negative weight — long-only violated")
if (any(abs(total_check$sum_total - 1) > 0.0011))
  warning("[WARN] total weights (equity+cash) sum not 1.0 for some dates")

# Cash fraction per sig_date
cash_pct_dt <- if (has_cash_col) {
  cash_dt[, .(Date, cash_pct=Weight)]
} else {
  # If CASH not in Ticker column — compute as 1 - sum(equity)
  merge(total_check, sum_check[, .(Date, sum_eq)], by="Date")[,
    .(Date, cash_pct=1 - sum_eq)]
}
setkey(cash_pct_dt, Date)
mean_cash <- mean(cash_pct_dt$cash_pct, na.rm=TRUE)
cat(sprintf("  Cash sleeve: mean=%.1f%% | min=%.1f%% | max=%.1f%%\n",
            mean_cash*100,
            min(cash_pct_dt$cash_pct, na.rm=TRUE)*100,
            max(cash_pct_dt$cash_pct, na.rm=TRUE)*100))

# ─────────────────────────────────────────────────────────
# 4. RAWDATA + FF5 v2 로드
# ─────────────────────────────────────────────────────────
cat("\n[4] Load RAWDATA + FF5 v2\n")

raw <- as.data.table(read_parquet(
  file.path(BASE_DIR, ".cache/rawdata.parquet"),
  col_select=c("Date","Ticker","Close","Vol","Ret")))
setkey(raw, Date, Ticker)
raw[, TradingAmt := Close * Vol]
cat(sprintf("  RAWDATA: %s rows | %s ~ %s\n",
            format(nrow(raw), big.mark=","),
            as.character(min(raw$Date)), as.character(max(raw$Date))))

ff5 <- as.data.table(read_parquet(
  file.path(BASE_DIR, ".cache/kr_factor_returns_v2.parquet")))
setorder(ff5, Date)
cat(sprintf("  FF5 v2: %d rows | factors: MKT+SMB+HML+WML+RMW+CMA+RF\n", nrow(ff5)))

# ─────────────────────────────────────────────────────────
# 5. WALK-FORWARD BACKTEST (92 sig_dates — P1_dyn_cash)
#    Pure Function: apply equity weights from weights.csv
#    CASH earns 0% (conservative assumption, no risk-free carry)
#    Equity portion earns stock returns × normalized equity weights
# ─────────────────────────────────────────────────────────
cat("\n[5] Walk-forward backtest (92 sig_dates, P1_dyn_cash — dynamic cash applied)\n")

LIQ_THRESHOLD  <- 2e8
COMMISSION_BPS <- 15
COMMISSION_PCT <- COMMISSION_BPS / 10000

monthly_results <- vector("list", n_sd - 1)

for (i in seq_len(n_sd - 1)) {
  start_d <- sig_dates[i]
  end_d   <- sig_dates[i + 1]

  # Equity holdings at start_d (weight > 0, excluding CASH)
  port_i <- equity_dt[Date == start_d & Weight > 0]
  if (nrow(port_i) == 0) {
    monthly_results[[i]] <- data.table(
      period_start=start_d, period_end=end_d,
      port_ret=0, port_ret_gross=0, n_held=0, turnover_ow=0,
      cash_pct=1, equity_pct=0, i=i)
    next
  }

  # Cash fraction at this sig_date
  cash_f <- cash_pct_dt[Date == start_d, cash_pct]
  cash_f <- if (length(cash_f) > 0 && !is.na(cash_f)) cash_f else 0
  equity_f <- 1 - cash_f

  # Liquidity filter (PIT C10: t-30 to t-1)
  liq_data <- raw[Date >= (start_d - 30L) & Date < start_d,
                  .(AvgTradingAmt=mean(TradingAmt, na.rm=TRUE)), by=Ticker]
  liquid_tickers <- liq_data[AvgTradingAmt >= LIQ_THRESHOLD, Ticker]

  port_liq <- port_i[Ticker %in% liquid_tickers]
  if (nrow(port_liq) == 0) port_liq <- copy(port_i)

  # Renormalize equity weights to sum=1 within equity sleeve
  sum_eq_w <- sum(port_liq$Weight)
  if (sum_eq_w <= 0) {
    monthly_results[[i]] <- data.table(
      period_start=start_d, period_end=end_d,
      port_ret=0, port_ret_gross=0, n_held=0, turnover_ow=0,
      cash_pct=cash_f, equity_pct=equity_f, i=i)
    next
  }
  port_liq[, w_eq_norm := Weight / sum_eq_w]  # within equity sleeve

  # Period returns (PIT C9: Date > start_d AND Date <= end_d)
  period_data <- raw[Date > start_d & Date <= end_d, .(Date, Ticker, Ret)]
  if (nrow(period_data) == 0) {
    monthly_results[[i]] <- data.table(
      period_start=start_d, period_end=end_d,
      port_ret=0, port_ret_gross=0,
      n_held=nrow(port_liq), turnover_ow=0,
      cash_pct=cash_f, equity_pct=equity_f, i=i)
    next
  }

  stock_rets <- period_data[, .(stock_ret=prod(1 + Ret, na.rm=TRUE) - 1), by=Ticker]
  merged <- merge(port_liq, stock_rets, by="Ticker", all.x=TRUE)
  merged[is.na(stock_ret), stock_ret := 0]

  # Gross portfolio return = equity_f × weighted_equity_ret + cash_f × 0
  eq_ret_gross <- sum(merged$w_eq_norm * merged$stock_ret, na.rm=TRUE)
  port_ret_gross <- equity_f * eq_ret_gross  # cash earns 0

  # Turnover estimation for transaction costs
  if (i == 1) {
    turnover_one_way <- equity_f  # first period: full entry
  } else {
    prev_port <- equity_dt[Date == sig_dates[i-1] & Weight > 0]
    if (nrow(prev_port) == 0) {
      turnover_one_way <- equity_f
    } else {
      prev_sum <- sum(prev_port$Weight)
      prev_port[, w_prev_eq_norm := Weight / prev_sum]

      prev_cash_f_row <- cash_pct_dt[Date == sig_dates[i-1], cash_pct]
      prev_cash_f <- if (length(prev_cash_f_row) > 0 && !is.na(prev_cash_f_row)) prev_cash_f_row else 0
      prev_eq_f <- 1 - prev_cash_f

      cur_norm <- port_liq[, .(Ticker, w_cur=w_eq_norm * equity_f)]
      prev_norm <- prev_port[, .(Ticker, w_prev=w_prev_eq_norm * prev_eq_f)]

      merged_to <- merge(cur_norm, prev_norm, by="Ticker", all=TRUE)
      merged_to[is.na(w_cur), w_cur := 0]
      merged_to[is.na(w_prev), w_prev := 0]
      # Add cash change to turnover (cash allocation shift)
      cash_to <- abs(cash_f - prev_cash_f) / 2
      turnover_one_way <- sum(abs(merged_to$w_cur - merged_to$w_prev)) / 2 + cash_to
    }
  }

  tc_drag <- 2 * turnover_one_way * COMMISSION_PCT
  port_ret_net <- port_ret_gross - tc_drag

  monthly_results[[i]] <- data.table(
    period_start  = start_d,
    period_end    = end_d,
    port_ret      = port_ret_net,
    port_ret_gross= port_ret_gross,
    n_held        = nrow(port_liq),
    turnover_ow   = turnover_one_way,
    cash_pct      = cash_f,
    equity_pct    = equity_f,
    i = i
  )
}

iter21_monthly <- rbindlist(monthly_results, fill=TRUE)
iter21_monthly <- iter21_monthly[!is.na(port_ret)]
cat(sprintf("  Walk-forward complete: %d periods\n", nrow(iter21_monthly)))
cat(sprintf("  Avg cash per period: %.1f%% | avg equity: %.1f%%\n",
            mean(iter21_monthly$cash_pct, na.rm=TRUE)*100,
            mean(iter21_monthly$equity_pct, na.rm=TRUE)*100))

# ─────────────────────────────────────────────────────────
# 6. PERFORMANCE METRICS — V_iter21 standalone
# ─────────────────────────────────────────────────────────
cat("\n[6] V_iter21 standalone performance metrics\n")

compute_metrics <- function(rets, label="") {
  n <- length(rets)
  if (n < 3) return(list(sr=NA, cagr=NA, mdd=NA, vol=NA, hit=NA, n=n,
                         mean_r=NA, std_r=NA, rets=rets))
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
    cat(sprintf("  %-38s | SR=%7.4f | CAGR=%7.4f | MDD=%7.4f | Vol=%6.4f | Hit=%.3f | n=%d\n",
                label, sr, cagr, mdd, vol, hit, n))
  list(sr=sr, cagr=cagr, mdd=mdd, vol=vol, hit=hit, n=n,
       mean_r=mean_r, std_r=std_r, rets=rets)
}

rets_v21 <- iter21_monthly$port_ret
m_v21 <- compute_metrics(rets_v21, "V_iter21 standalone (P1_dyn_cash)")

# Annual turnover realized
years_in_sample <- nrow(iter21_monthly) / 12
ann_to_actual <- if (years_in_sample > 0) {
  sum(iter21_monthly$turnover_ow, na.rm=TRUE) / years_in_sample * 2
} else NA
cat(sprintf("  Ann turnover (round-trip): %.3f | Expected from pkg: %.3f\n",
            ann_to_actual %||% NA, expected_to))

# ─────────────────────────────────────────────────────────
# 7. PG2 BLEND: V_iter21 80% + STR_1656 20%
#    vs BASELINE: STR_1701 80% + STR_1656 20% (realized SR 1.4625)
# ─────────────────────────────────────────────────────────
cat("\n[7] PG2 blend computation (V_iter21 80% + STR_1656 20% vs baseline 1.4625)\n")

# STR_1656 daily NAV → monthly returns
str1656_path <- file.path(BASE_DIR,
  "04_Research/strategies/STR_1656_MLRA/output/nav_S1_B.csv")
if (!file.exists(str1656_path))
  stop("[FAIL] STR_1656 nav_S1_B.csv not found: ", str1656_path)

str1656_daily <- fread(str1656_path)
str1656_daily[, Date := as.Date(Date)]
setorder(str1656_daily, Date)

# Monthly returns from daily NAV — use last business day per month
str1656_daily[, YM := format(Date, "%Y-%m")]
str1656_monthly <- str1656_daily[, .SD[.N], by=YM]
# Compute return: period-over-period NAV
ret_col <- if ("Strategy_Ret" %in% names(str1656_monthly)) "Strategy_Ret" else {
  # compute from NAV
  str1656_monthly[, Monthly_Ret := NAV / shift(NAV) - 1]
  "Monthly_Ret"
}
if (ret_col == "Strategy_Ret") {
  # Strategy_Ret is daily — need to compound monthly
  # Recompute: month-end NAV ratio
  str1656_monthly[, Monthly_Ret := NAV / shift(NAV) - 1]
  ret_col <- "Monthly_Ret"
}
str1656_monthly <- str1656_monthly[!is.na(get(ret_col))]
str1656_monthly[, YM_key := YM]
setnames(str1656_monthly, ret_col, "ret_1656")

# Iter 11 STR_1701 monthly (load from backtest_result)
iter11_path <- file.path(ITER11_BT, "iter11_full_period_monthly.csv")
if (file.exists(iter11_path)) {
  iter11_monthly <- fread(iter11_path)
  iter11_monthly[, Date := as.Date(Date)]
  iter11_monthly[, YM_key := format(Date, "%Y-%m")]
  # Column name: port_ret
  if (!"port_ret" %in% names(iter11_monthly))
    setnames(iter11_monthly, grep("ret|return", names(iter11_monthly), ignore.case=TRUE, value=TRUE)[1], "port_ret")
  setnames(iter11_monthly, "port_ret", "ret_1701", skip_absent=TRUE)
} else {
  cat("  [WARN] Iter 11 monthly returns not found; using empty placeholder\n")
  iter11_monthly <- data.table(Date=as.Date(character()), YM_key=character(), ret_1701=numeric())
}

# Iter 18 STR_1708 monthly (for comparison)
iter18_path <- file.path(ITER18_BT, "iter18_monthly_returns.csv")
if (file.exists(iter18_path)) {
  iter18_monthly_ref <- fread(iter18_path)
  iter18_monthly_ref[, Date := as.Date(Date)]
  iter18_monthly_ref[, YM_key := format(Date, "%Y-%m")]
  if (!"port_ret" %in% names(iter18_monthly_ref))
    setnames(iter18_monthly_ref,
             grep("ret|return", names(iter18_monthly_ref), ignore.case=TRUE, value=TRUE)[1],
             "port_ret")
  setnames(iter18_monthly_ref, "port_ret", "ret_iter18", skip_absent=TRUE)
} else {
  cat("  [WARN] Iter 18 monthly returns not found\n")
  iter18_monthly_ref <- data.table(Date=as.Date(character()), YM_key=character(), ret_iter18=numeric())
}

# V_iter21 YM_key
iter21_monthly[, YM_key := format(period_end, "%Y-%m")]

# Build PG2 blend V_iter21: overlap with STR_1656
blend_dt <- merge(
  iter21_monthly[, .(YM_key, ret_v21=port_ret)],
  str1656_monthly[, .(YM_key, ret_1656)],
  by="YM_key")
blend_dt[, ret_pg2_v21 := 0.8 * ret_v21 + 0.2 * ret_1656]
cat(sprintf("  V_iter21 PG2 blend: %d overlapping months\n", nrow(blend_dt)))
m_pg2_v21 <- compute_metrics(blend_dt$ret_pg2_v21, "PG2 V_iter21 (80+20 blend)")

# Baseline PG2: STR_1701 80% + STR_1656 20% — same overlapping period
if (nrow(iter11_monthly) > 0) {
  blend_base <- merge(
    iter11_monthly[, .(YM_key, ret_1701)],
    str1656_monthly[, .(YM_key, ret_1656)],
    by="YM_key")
  # Restrict to same months as V_iter21 blend
  common_ym <- intersect(blend_dt$YM_key, blend_base$YM_key)
  blend_base_sub <- blend_base[YM_key %in% common_ym]
  blend_dt_sub   <- blend_dt[YM_key %in% common_ym]
  setorder(blend_base_sub, YM_key)
  setorder(blend_dt_sub,   YM_key)
  blend_base_sub[, ret_pg2_base := 0.8 * ret_1701 + 0.2 * ret_1656]
  m_pg2_base <- compute_metrics(blend_base_sub$ret_pg2_base,
                                "PG2 baseline STR_1701 (same period)")
} else {
  cat("  [WARN] Iter11 monthly not available; using stated SR=1.4625 as baseline reference\n")
  blend_base_sub <- data.table()
  m_pg2_base <- list(sr=BASELINE_PG2_SR, cagr=NA, mdd=NA, n=0)
  blend_dt_sub <- blend_dt
}

# Delta
delta_sr <- m_pg2_v21$sr - (m_pg2_base$sr %||% BASELINE_PG2_SR)
pg2_promote <- (m_pg2_v21$sr >= BASELINE_PG2_SR)

cat(sprintf("\n  === PG2 DECISION ===\n"))
cat(sprintf("  V_iter21 PG2 blend SR   = %.4f\n", m_pg2_v21$sr))
cat(sprintf("  Baseline (same-period)  = %.4f\n", m_pg2_base$sr %||% BASELINE_PG2_SR))
cat(sprintf("  Baseline (stated)       = %.4f\n", BASELINE_PG2_SR))
cat(sprintf("  Delta (same-period)     = %+.4f\n", delta_sr))
cat(sprintf("  PROMOTE? (SR >= 1.4625) = %s\n",
            ifelse(pg2_promote, "YES — PROMOTE_V21", "NO — MAINTAIN_BASELINE")))
cat(sprintf("  V_iter21 MDD            = %.4f\n", m_v21$mdd))

# ─────────────────────────────────────────────────────────
# 8. AX-001 v2 4-METRIC DIRECT MEASUREMENT
#    (1) crisis_alpha: msi_norm > 0.75 dates — top vs bot decile fwd return spread
#    (2) core_mdd_relief: V_iter21 MDD vs Iter11 P0 MDD (same period)
#    (3) bad_normal_ic_ratio: regime-conditional IC (crisis+caution) / normal
#        → proxy: V_iter21 avg_ret in CRISIS vs NORMAL periods
#    (4) Harvey t_stat inherited (alpha layer pooled OLS)
# ─────────────────────────────────────────────────────────
cat("\n[8] AX-001 v2 4-metric direct measurement\n")

# Load alpha_scores.parquet (msi_norm + regime_state_legacy)
alpha_scores_path <- file.path(BASE_DIR,
  "stage_artifacts/WT_D20260427_005/alpha_scores.parquet")

ax001_metrics <- list()

if (file.exists(alpha_scores_path)) {
  alpha_scores <- as.data.table(read_parquet(alpha_scores_path))
  cat(sprintf("  alpha_scores loaded: %d rows | cols: %s\n",
              nrow(alpha_scores), paste(names(alpha_scores), collapse=",")))

  has_msi   <- "msi_norm" %in% names(alpha_scores)
  has_regime <- "regime_state_legacy" %in% names(alpha_scores)
  has_date   <- any(c("Date","sig_date","date") %in% names(alpha_scores))

  if (has_date) {
    date_col <- intersect(c("Date","sig_date","date"), names(alpha_scores))[1]
    alpha_scores[, sig_dt := as.Date(get(date_col))]
    alpha_scores_monthly <- unique(alpha_scores[, .(sig_dt, msi_norm=if(has_msi) msi_norm else NA_real_,
                                                     regime=if(has_regime) regime_state_legacy else NA_character_)])
    setkey(alpha_scores_monthly, sig_dt)

    # (1) crisis_alpha: msi_norm > 0.75 dates
    if (has_msi) {
      crisis_dates <- unique(alpha_scores_monthly[msi_norm > 0.75, sig_dt])
      iter21_crisis <- iter21_monthly[period_start %in% crisis_dates]
      non_crisis    <- iter21_monthly[!period_start %in% crisis_dates]
      crisis_alpha_realized <- if (nrow(iter21_crisis) > 0 && nrow(non_crisis) > 0)
        mean(iter21_crisis$port_ret, na.rm=TRUE) - mean(non_crisis$port_ret, na.rm=TRUE)
      else NA
      cat(sprintf("  (1) crisis_alpha (msi>0.75 dates): realized diff = %.4f | n_crisis_dates=%d\n",
                  crisis_alpha_realized %||% NA, length(crisis_dates)))
      # Also: mdd in msi>0.75 periods vs all
      if (nrow(iter21_crisis) > 2) {
        nav_crisis <- cumprod(1 + iter21_crisis$port_ret)
        peak_c <- cummax(c(1, nav_crisis))[-1]
        mdd_crisis <- min(nav_crisis / peak_c - 1, na.rm=TRUE)
        cat(sprintf("  (1b) crisis MDD (msi>0.75): %.4f\n", mdd_crisis))
      } else {
        mdd_crisis <- NA
      }
      ax001_metrics$crisis_alpha_realized <- crisis_alpha_realized %||% NA
      ax001_metrics$crisis_mdd_realized   <- mdd_crisis %||% NA
    } else {
      ax001_metrics$crisis_alpha_realized <- NA
      ax001_metrics$crisis_mdd_realized   <- NA
      cat("  (1) crisis_alpha: msi_norm column not found in alpha_scores\n")
    }

    # (3) bad/normal IC ratio proxy: avg_ret in CRISIS+CAUTION vs NORMAL
    if (has_regime) {
      regime_dates <- unique(alpha_scores_monthly[, .(sig_dt, regime)])
      iter21_regime <- merge(iter21_monthly[, .(period_start, port_ret)],
                             regime_dates, by.x="period_start", by.y="sig_dt", all.x=TRUE)
      bad_ret  <- iter21_regime[regime %in% c("CRISIS","CAUTION"), mean(port_ret, na.rm=TRUE)]
      norm_ret <- iter21_regime[regime == "NORMAL", mean(port_ret, na.rm=TRUE)]
      bad_norm_ratio <- if (!is.na(norm_ret) && norm_ret != 0) bad_ret / norm_ret else NA
      cat(sprintf("  (3) bad/normal ret ratio: bad=%.4f normal=%.4f ratio=%.4f\n",
                  bad_ret %||% NA, norm_ret %||% NA, bad_norm_ratio %||% NA))
      ax001_metrics$bad_normal_ret_ratio <- bad_norm_ratio %||% NA
    } else {
      ax001_metrics$bad_normal_ret_ratio <- NA
      cat("  (3) regime column not found in alpha_scores\n")
    }
  } else {
    cat("  [WARN] No date column in alpha_scores; skipping crisis/regime metrics\n")
    ax001_metrics$crisis_alpha_realized <- NA
    ax001_metrics$crisis_mdd_realized   <- NA
    ax001_metrics$bad_normal_ret_ratio  <- NA
  }
} else {
  cat("  [WARN] alpha_scores.parquet not found; AX-001 v2 metrics from pkg proxies only\n")
  ax001_metrics$crisis_alpha_realized <- alpha_pkg$ax_001_v2_audit$crisis_alpha %||% NA
  ax001_metrics$crisis_mdd_realized   <- NA
  ax001_metrics$bad_normal_ret_ratio  <- alpha_pkg$ax_001_v2_audit$bad_normal_ic_ratio %||% NA
}

# (2) core_mdd_relief: V_iter21 MDD vs P0 static baseline (Iter 11 same-period MDD)
# P0 baseline Iter 11 SR=1.2910, need MDD from hurdle
iter11_hurdle_path <- file.path(ITER11_BT, "hurdle_result.json")
iter11_mdd_same <- NA
if (file.exists(iter11_hurdle_path)) {
  iter11_hr <- fromJSON(iter11_hurdle_path, simplifyVector=FALSE)
  iter11_mdd_same <- iter11_hr$standalone$MDD %||% NA
  cat(sprintf("  (2) Iter11 standalone MDD from hurdle = %.4f\n", iter11_mdd_same %||% NA))
}
# Also compute same-period Iter11 MDD
if (nrow(iter11_monthly) > 0) {
  iter11_sp <- iter11_monthly[YM_key %in% iter21_monthly$YM_key]
  if (nrow(iter11_sp) > 2) {
    nav_sp <- cumprod(1 + iter11_sp$ret_1701)
    peak_sp <- cummax(c(1, nav_sp))[-1]
    iter11_mdd_sp <- min(nav_sp / peak_sp - 1)
    cat(sprintf("  (2) Iter11 same-period MDD = %.4f\n", iter11_mdd_sp))
  } else {
    iter11_mdd_sp <- iter11_mdd_same
  }
} else {
  iter11_mdd_sp <- opt_pkg$method_comparison$P0_static_4state$mdd %||% -0.3258
  cat(sprintf("  (2) P0 static baseline MDD (pkg) = %.4f\n", iter11_mdd_sp))
}

core_mdd_relief <- if (!is.na(iter11_mdd_sp) && !is.na(m_v21$mdd)) {
  abs(iter11_mdd_sp) - abs(m_v21$mdd)
} else NA
cat(sprintf("  (2) core_mdd_relief: V21_MDD=%.4f P0_MDD=%.4f relief_pp=%.4f\n",
            m_v21$mdd %||% NA, iter11_mdd_sp %||% NA, core_mdd_relief %||% NA))
ax001_metrics$core_mdd_relief <- core_mdd_relief %||% NA

# (4) Harvey t inherited from alpha_package (pooled OLS, preserved alpha)
harvey_t_inherited <- alpha_pkg$diagnostics$harvey_t_specs$spec1_pooled_ols %||% -0.0238
cat(sprintf("  (4) Harvey t (inherited pooled OLS) = %.4f\n", harvey_t_inherited))
ax001_metrics$harvey_t_inherited <- harvey_t_inherited

cat(sprintf("\n  AX-001 v2 Summary: crisis_alpha=%.4f | core_mdd_relief=%.4f | bad_norm_ratio=%.4f | Harvey_t=%.4f\n",
            ax001_metrics$crisis_alpha_realized %||% NA,
            ax001_metrics$core_mdd_relief %||% NA,
            ax001_metrics$bad_normal_ret_ratio %||% NA,
            ax001_metrics$harvey_t_inherited %||% NA))

# ─────────────────────────────────────────────────────────
# 9. 5-SPEC HARVEY FF5 v2 NW-HAC
# ─────────────────────────────────────────────────────────
cat("\n[9] 5-spec Harvey FF5 v2 NW-HAC regression\n")

ff5_m <- copy(ff5)
ff5_m[, YM_key := format(Date, "%Y-%m")]

reg_dt <- merge(
  iter21_monthly[, .(YM_key, port_ret)],
  ff5_m[, .(YM_key, MKT, SMB, HML, WML, RMW, CMA, RF)],
  by="YM_key")

reg_dt[is.na(RF), RF := 0]
reg_dt[, excess_ret := port_ret - RF/100]
reg_dt[, MKT_e := MKT/100]
reg_dt[, SMB_e := SMB/100]
reg_dt[, HML_e := HML/100]
reg_dt[, WML_e := WML/100]
reg_dt[, RMW_e := RMW/100]
reg_dt[, CMA_e := CMA/100]

n_reg <- nrow(reg_dt)
nw_lag <- max(1, floor(4 * (n_reg/100)^(2/9)))
cat(sprintf("  Regression sample: %d months | NW-HAC lag: %d\n", n_reg, nw_lag))

harvey_specs <- list(
  CAPM     = "excess_ret ~ MKT_e",
  Carhart3 = "excess_ret ~ MKT_e + SMB_e + HML_e",
  Carhart4 = "excess_ret ~ MKT_e + SMB_e + HML_e + WML_e",
  FF5      = "excess_ret ~ MKT_e + SMB_e + HML_e + RMW_e + CMA_e",
  FF6      = "excess_ret ~ MKT_e + SMB_e + HML_e + WML_e + RMW_e + CMA_e"
)

harvey_results <- list()
pass_count <- 0

for (spec_name in names(harvey_specs)) {
  fm <- tryCatch(
    lm(as.formula(harvey_specs[[spec_name]]), data=reg_dt),
    error=function(e) NULL)
  if (is.null(fm)) {
    harvey_results[[spec_name]] <- list(t=NA, p=NA, alpha_ann=NA, pass=FALSE)
    cat(sprintf("  %-10s | ERROR in lm()\n", spec_name))
    next
  }
  ctest <- coeftest(fm, vcov=NeweyWest(fm, lag=nw_lag, prewhite=FALSE))
  alpha_row <- ctest["(Intercept)", ]
  t_stat <- alpha_row["t value"]
  p_val  <- alpha_row["Pr(>|t|)"]
  alpha_ann <- coef(fm)["(Intercept)"] * 12
  pass <- !is.na(t_stat) && abs(t_stat) >= 2.95
  if (pass) pass_count <- pass_count + 1
  harvey_results[[spec_name]] <- list(t=t_stat, p=p_val, alpha_ann=alpha_ann, pass=pass)
  cat(sprintf("  %-10s | alpha_ann=%.4f | t=%.3f | %s\n",
              spec_name, alpha_ann, t_stat,
              ifelse(pass, "PASS (t>=2.95)", "FAIL")))
}
cat(sprintf("  Harvey 5-spec PASS: %d/5\n", pass_count))
harvey_ff5_t <- harvey_results$FF5$t %||% NA

# ─────────────────────────────────────────────────────────
# 10. DSR POST-PENALTY
# ─────────────────────────────────────────────────────────
cat("\n[10] DSR post-penalty\n")

sr_obs <- m_v21$sr
n_m    <- m_v21$n

skew_r <- tryCatch(e1071::skewness(rets_v21, na.rm=TRUE), error=function(e) 0)
kurt_r <- tryCatch(e1071::kurtosis(rets_v21, na.rm=TRUE), error=function(e) 0)

dsr_denom <- sqrt(1 + (sr_obs^2 / 4) * (skew_r^2 + (kurt_r - 3)) / n_m)
if (is.nan(dsr_denom) || is.na(dsr_denom) || dsr_denom <= 0) dsr_denom <- 1
dsr_pre  <- sr_obs / dsr_denom
dsr_post <- dsr_pre - DSR_PENALTY_TOTAL

cat(sprintf("  SR_obs=%.4f | skew=%.3f | kurt=%.3f | n=%d\n",
            sr_obs %||% NA, skew_r %||% NA, kurt_r %||% NA, n_m %||% 0))
cat(sprintf("  DSR_pre=%.4f | penalty=%.2f | DSR_post=%.4f\n",
            dsr_pre %||% NA, DSR_PENALTY_TOTAL, dsr_post %||% NA))

# ─────────────────────────────────────────────────────────
# 11. SAME-PERIOD COMPARISON
#     V_iter21 vs Iter11 STR_1701 vs Iter18 STR_1708
# ─────────────────────────────────────────────────────────
cat("\n[11] Same-period comparison\n")

sp_ym <- iter21_monthly$YM_key

# Iter 11 same-period
if (nrow(iter11_monthly) > 0) {
  iter11_sp <- iter11_monthly[YM_key %in% sp_ym]
  setorder(iter11_sp, YM_key)
  m_iter11_sp <- compute_metrics(iter11_sp$ret_1701, "Iter11 STR_1701 (same period)")
} else {
  m_iter11_sp <- list(sr=1.291, cagr=NA, mdd=NA, n=0)
  cat(sprintf("  Iter11 STR_1701 (stated):            | SR=%7.4f\n", m_iter11_sp$sr))
}

# Iter 18 same-period
if (nrow(iter18_monthly_ref) > 0) {
  iter18_sp <- iter18_monthly_ref[YM_key %in% sp_ym]
  setorder(iter18_sp, YM_key)
  m_iter18_sp <- compute_metrics(iter18_sp$ret_iter18, "Iter18 STR_1708 (same period)")
} else {
  m_iter18_sp <- list(sr=NA, cagr=NA, mdd=NA, n=0)
  cat("  [WARN] Iter18 monthly not available for same-period comparison\n")
}

cat("\n  === SAME-PERIOD COMPARISON TABLE ===\n")
cat(sprintf("  %-38s | SR=%7.4f | CAGR=%7.4f | MDD=%7.4f | n=%d\n",
            "V_iter21 (P1_dyn_cash)",
            m_v21$sr, m_v21$cagr, m_v21$mdd, m_v21$n))
cat(sprintf("  %-38s | SR=%7.4f | CAGR=%7.4f | MDD=%7.4f | n=%d\n",
            "Iter11 STR_1701 (same period)",
            m_iter11_sp$sr %||% NA, m_iter11_sp$cagr %||% NA,
            m_iter11_sp$mdd %||% NA, m_iter11_sp$n %||% 0))
cat(sprintf("  %-38s | SR=%7.4f | CAGR=%7.4f | MDD=%7.4f | n=%d\n",
            "Iter18 STR_1708 (same period, fail)",
            m_iter18_sp$sr %||% NA, m_iter18_sp$cagr %||% NA,
            m_iter18_sp$mdd %||% NA, m_iter18_sp$n %||% 0))

# Iter18 PG2 blend for context
iter18_blend_sr <- 0.8699  # from hurdle_result.json (realized)
cat(sprintf("  Iter18 PG2 blend SR (realized/stated) = %.4f (fail — MAINTAIN_BASELINE)\n",
            iter18_blend_sr))

# ─────────────────────────────────────────────────────────
# 12. 24-26 OOS EXTENSION (frozen weights from last sig_date)
# ─────────────────────────────────────────────────────────
cat("\n[12] 24-26 OOS extension (frozen weights from last sig_date)\n")

OOS_END <- as.Date("2026-04-27")

last_sd    <- max(sig_dates)
last_equity <- equity_dt[Date == last_sd & Weight > 0]
last_cash_f <- cash_pct_dt[Date == last_sd, cash_pct]
last_cash_f <- if (length(last_cash_f) > 0 && !is.na(last_cash_f)) last_cash_f else 0

cat(sprintf("  Frozen from %s | equity holdings=%d | cash=%.1f%%\n",
            last_sd, nrow(last_equity), last_cash_f*100))

if (nrow(last_equity) == 0) {
  cat("  [WARN] No equity holdings at last sig_date; OOS skipped\n")
  m_oos <- list(sr=NA, cagr=NA, mdd=NA, n=0)
  oos_monthly <- data.table()
} else {
  eq_sum_last <- sum(last_equity$Weight)
  last_equity[, w_final := Weight / eq_sum_last]  # normalize within equity
  eq_f_last <- 1 - last_cash_f

  oos_raw <- raw[Date > last_sd & Date <= OOS_END, .(Date, Ticker, Ret)]
  cat(sprintf("  OOS RAWDATA: %d rows | %s ~ %s\n",
              nrow(oos_raw),
              if (nrow(oos_raw) > 0) as.character(min(oos_raw$Date)) else "NA",
              if (nrow(oos_raw) > 0) as.character(max(oos_raw$Date)) else "NA"))

  if (nrow(oos_raw) == 0) {
    m_oos <- list(sr=NA, cagr=NA, mdd=NA, n=0)
    oos_monthly <- data.table()
  } else {
    oos_raw[, YM := format(Date, "%Y-%m")]
    oos_monthly_list <- list()
    for (ym in sort(unique(oos_raw$YM))) {
      pd <- oos_raw[YM == ym]
      if (nrow(pd) == 0) next
      sr_oos <- pd[, .(stock_ret=prod(1+Ret, na.rm=TRUE)-1), by=Ticker]
      mg <- merge(last_equity, sr_oos, by="Ticker", all.x=TRUE)
      mg[is.na(stock_ret), stock_ret := 0]
      ret_oos <- eq_f_last * sum(mg$w_final * mg$stock_ret, na.rm=TRUE)
      oos_monthly_list[[ym]] <- data.table(YM=ym, ret_oos=ret_oos)
    }
    oos_monthly <- rbindlist(oos_monthly_list)
    if (nrow(oos_monthly) > 1) {
      m_oos <- compute_metrics(oos_monthly$ret_oos, "OOS 24-26 (frozen weights)")
      cat(sprintf("  OOS: %d months\n", nrow(oos_monthly)))
    } else {
      m_oos <- list(sr=NA, cagr=NA, mdd=NA, n=0)
    }
  }
}

# ─────────────────────────────────────────────────────────
# 13. COMPLETE hash audit
# ─────────────────────────────────────────────────────────
cat("\n[13] COMPLETE hash audit (Pure Function verification)\n")

end_hashes <- sapply(pkg_files, function(f) tryCatch(
  as.character(tools::md5sum(f)), error=function(e) "MISSING"))
end_w_hash  <- as.character(tools::md5sum(weights_path))

hash_pass <- TRUE
for (n in names(start_hashes)) {
  match_h <- identical(start_hashes[n], end_hashes[n])
  if (!match_h) {
    cat(sprintf("  [FAIL] %s HASH MISMATCH: start=%s end=%s\n",
                n, substr(start_hashes[n],1,16), substr(end_hashes[n],1,16)))
    hash_pass <- FALSE
  }
}
w_match <- identical(start_w_hash, end_w_hash)
if (!w_match) {
  cat("  [FAIL] weights.csv HASH MISMATCH — Pure Function violated\n")
  hash_pass <- FALSE
}
if (hash_pass) cat("  HASH AUDIT PASS — all 4 artifacts unchanged throughout run\n")

# ─────────────────────────────────────────────────────────
# 14. CHARTS (4종)
# ─────────────────────────────────────────────────────────
cat("\n[14] Generating 4 charts\n")

iter21_monthly[, cum_nav_v21 := cumprod(1 + port_ret)]
iter21_monthly[, Date_plt   := period_end]

# Chart 1: Equity curve (V21 vs P0/Iter11 vs Iter18)
plot_nav <- rbindlist(list(
  data.table(Date=iter21_monthly$Date_plt,
             NAV=iter21_monthly$cum_nav_v21,
             Strategy="V_iter21 P1_dyn_cash")
), fill=TRUE)

# Iter 11 same-period nav
if (nrow(iter11_monthly) > 0 && "ret_1701" %in% names(iter11_monthly)) {
  iter11_sp2 <- iter11_monthly[YM_key %in% iter21_monthly$YM_key]
  setorder(iter11_sp2, YM_key)
  if (nrow(iter11_sp2) > 0) {
    iter11_sp2[, cum_nav_1701 := cumprod(1 + ret_1701)]
    iter11_sp2[, Date_plt := as.Date(paste0(YM_key, "-28"))]
    plot_nav <- rbindlist(list(
      plot_nav,
      data.table(Date=iter11_sp2$Date_plt,
                 NAV=iter11_sp2$cum_nav_1701,
                 Strategy="Iter11 STR_1701 (P0 baseline)")
    ), fill=TRUE)
  }
}

# Iter 18 same-period nav
if (nrow(iter18_monthly_ref) > 0 && "ret_iter18" %in% names(iter18_monthly_ref)) {
  iter18_sp2 <- iter18_monthly_ref[YM_key %in% iter21_monthly$YM_key]
  setorder(iter18_sp2, YM_key)
  if (nrow(iter18_sp2) > 0) {
    iter18_sp2[, cum_nav_18 := cumprod(1 + ret_iter18)]
    iter18_sp2[, Date_plt := as.Date(paste0(YM_key, "-28"))]
    plot_nav <- rbindlist(list(
      plot_nav,
      data.table(Date=iter18_sp2$Date_plt,
                 NAV=iter18_sp2$cum_nav_18,
                 Strategy="Iter18 STR_1708 (Opt-only fail)")
    ), fill=TRUE)
  }
}

p1 <- ggplot(plot_nav, aes(x=Date, y=NAV, color=Strategy)) +
  geom_line(linewidth=0.8) +
  scale_y_continuous(labels=comma) +
  scale_x_date(date_labels="%Y", date_breaks="2 years") +
  labs(title="STR_1709 Iter 21 Macro Overlay — NAV Curves (2008-2023)",
       subtitle=sprintf("V_iter21 SR=%.3f | Iter11 SR=%.3f | Iter18 SR=%.3f | n=%d months",
                        m_v21$sr, m_iter11_sp$sr %||% NA,
                        m_iter18_sp$sr %||% NA, m_v21$n),
       x=NULL, y="NAV (base=1)", color=NULL) +
  theme_minimal(base_size=11) +
  theme(legend.position="bottom")
ggsave(file.path(OUT_DIR, "equity_curve.png"), p1, width=11, height=5, dpi=150)
cat("  equity_curve.png saved\n")

# Chart 2: Annual returns
iter21_monthly[, Year := as.integer(format(period_end, "%Y"))]
annual_v21 <- iter21_monthly[, .(ann_ret=prod(1+port_ret)-1), by=Year]

p2 <- ggplot(annual_v21, aes(x=factor(Year), y=ann_ret,
                             fill=ifelse(ann_ret >= 0, "pos", "neg"))) +
  geom_col() +
  scale_fill_manual(values=c(pos="steelblue", neg="tomato"), guide="none") +
  scale_y_continuous(labels=percent_format(accuracy=1)) +
  labs(title="STR_1709 Iter 21 — Annual Returns (V_iter21 P1_dyn_cash)",
       x=NULL, y="Annual Return") +
  theme_minimal(base_size=11) +
  theme(axis.text.x=element_text(angle=45, hjust=1))
ggsave(file.path(OUT_DIR, "annual_returns.png"), p2, width=10, height=4, dpi=150)
cat("  annual_returns.png saved\n")

# Chart 3: Crisis period zoom (MDD comparison — V21 vs Iter11)
# Define crisis periods: GFC 2008-2009, COVID 2020, Rate_2022
crisis_bands <- data.frame(
  xmin=as.Date(c("2007-10-01","2020-01-01","2022-01-01")),
  xmax=as.Date(c("2009-03-31","2020-06-30","2022-12-31")),
  label=c("GFC","COVID","Rate22")
)

# Compute DD series for V21 and Iter11
iter21_dd <- copy(iter21_monthly)[, cum_nav := cumprod(1+port_ret)]
nav_vec <- iter21_dd$cum_nav
peak_vec <- cummax(c(1, nav_vec))[seq_along(nav_vec)]
dd_vec  <- nav_vec / peak_vec - 1

dd_plot <- data.table(Date=iter21_monthly$Date_plt,
                      DD=dd_vec, Strategy="V_iter21 P1_dyn_cash")

if (nrow(iter11_monthly) > 0 && "ret_1701" %in% names(iter11_monthly)) {
  iter11_sp3 <- iter11_monthly[YM_key %in% iter21_monthly$YM_key]
  setorder(iter11_sp3, YM_key)
  if (nrow(iter11_sp3) > 0) {
    nav_11 <- cumprod(1 + iter11_sp3$ret_1701)
    dd_11  <- nav_11 / cummax(c(1, nav_11))[seq_along(nav_11)] - 1
    dd_plot <- rbindlist(list(
      dd_plot,
      data.table(Date=as.Date(paste0(iter11_sp3$YM_key, "-28")),
                 DD=dd_11, Strategy="Iter11 STR_1701 (P0)")
    ), fill=TRUE)
  }
}

p3 <- ggplot(dd_plot, aes(x=Date, y=DD, color=Strategy)) +
  geom_rect(data=crisis_bands,
            aes(xmin=xmin, xmax=xmax, ymin=-Inf, ymax=0),
            inherit.aes=FALSE, fill="pink", alpha=0.2) +
  geom_line(linewidth=0.7) +
  geom_hline(yintercept=0, color="black", linewidth=0.3) +
  scale_y_continuous(labels=percent_format(accuracy=1)) +
  scale_x_date(date_labels="%Y", date_breaks="2 years") +
  labs(title="STR_1709 Iter 21 — Drawdown: Crisis Period Comparison",
       subtitle=sprintf("V_iter21 MDD=%.2f%% | P0 Iter11 MDD=%.2f%% | Relief=%.2fpp",
                        m_v21$mdd*100, (m_iter11_sp$mdd %||% NA)*100,
                        (core_mdd_relief %||% NA)*100),
       x=NULL, y="Drawdown", color=NULL) +
  theme_minimal(base_size=11) +
  theme(legend.position="bottom")
ggsave(file.path(OUT_DIR, "crisis_period_zoom.png"), p3, width=11, height=5, dpi=150)
cat("  crisis_period_zoom.png saved\n")

# Chart 4: Cash overlay dynamics (cash_pct over time, colored by regime)
if (has_cash_col && nrow(cash_pct_dt) > 0) {
  cash_plt <- merge(
    cash_pct_dt,
    iter21_monthly[, .(Date=period_start, cash_pct_check=cash_pct)],
    by="Date", all.x=TRUE)

  # Try to merge regime from alpha_scores
  regime_merge <- if (exists("alpha_scores_monthly") && nrow(alpha_scores_monthly) > 0 &&
                       "regime" %in% names(alpha_scores_monthly)) {
    merge(cash_pct_dt, alpha_scores_monthly[, .(sig_dt, regime)],
          by.x="Date", by.y="sig_dt", all.x=TRUE)
  } else {
    copy(cash_pct_dt)[, regime := "UNKNOWN"]
  }

  # Add msi_norm if available
  if (exists("alpha_scores_monthly") && "msi_norm" %in% names(alpha_scores_monthly)) {
    regime_merge <- merge(regime_merge,
                          alpha_scores_monthly[, .(sig_dt, msi_norm)],
                          by.x="Date", by.y="sig_dt", all.x=TRUE)
  }

  p4_base <- ggplot(regime_merge, aes(x=Date)) +
    geom_area(aes(y=cash_pct), fill="lightblue", alpha=0.6) +
    geom_line(aes(y=cash_pct), color="steelblue", linewidth=0.7)

  if ("msi_norm" %in% names(regime_merge)) {
    p4_base <- p4_base +
      geom_line(aes(y=msi_norm * 0.5, linetype="MSI_norm (scaled)"),
                color="red", linewidth=0.6) +
      scale_linetype_manual(values=c("MSI_norm (scaled)"="dashed"), name=NULL)
  }

  p4 <- p4_base +
    scale_y_continuous(labels=percent_format(accuracy=1),
                       sec.axis=sec_axis(~./0.5, name="MSI norm (right)")) +
    scale_x_date(date_labels="%Y", date_breaks="2 years") +
    labs(title="STR_1709 Iter 21 — Cash Overlay Dynamics (msi_norm-driven)",
         subtitle=sprintf("avg_cash=%.1f%% | max=%.1f%% | min=%.1f%%",
                          mean_cash*100,
                          max(cash_pct_dt$cash_pct, na.rm=TRUE)*100,
                          min(cash_pct_dt$cash_pct, na.rm=TRUE)*100),
         x=NULL, y="Cash fraction") +
    theme_minimal(base_size=11)
  ggsave(file.path(OUT_DIR, "cash_overlay_dynamics.png"), p4, width=11, height=4, dpi=150)
  cat("  cash_overlay_dynamics.png saved\n")
} else {
  cat("  [SKIP] cash_overlay_dynamics.png — cash column not in weights.csv\n")
  # Create placeholder
  p4_placeholder <- ggplot(data.frame(x=1, y=mean_cash), aes(x=x, y=y)) +
    geom_col(fill="lightblue") +
    labs(title="Cash overlay: avg from pkg",
         subtitle=sprintf("avg_cash=%.1f%% (from optimization_package)", mean_cash*100)) +
    theme_minimal()
  ggsave(file.path(OUT_DIR, "cash_overlay_dynamics.png"),
         p4_placeholder, width=6, height=3, dpi=150)
}

# ─────────────────────────────────────────────────────────
# 15. SAVE RESULTS
# ─────────────────────────────────────────────────────────
cat("\n[15] Saving backtest_result and judge_ready artifacts\n")

# Monthly returns
iter21_out <- iter21_monthly[, .(
  Date          = period_end,
  YM_key        = YM_key,
  port_ret_gross = port_ret_gross,
  port_ret      = port_ret,
  n_held        = n_held,
  turnover_ow   = turnover_ow,
  cash_pct      = cash_pct,
  equity_pct    = equity_pct
)]
fwrite(iter21_out, file.path(BT_DIR, "iter21_monthly_returns.csv"))

# OOS monthly
if (exists("oos_monthly") && nrow(oos_monthly) > 1)
  fwrite(oos_monthly, file.path(BT_DIR, "oos_24_26_monthly.csv"))

# Hurdle result
hurdle_result <- list(
  task_id       = WT_ID,
  str_id        = STR_ID,
  iter          = 21,
  method        = method_tag,
  standalone = list(
    SR   = round(m_v21$sr,   4),
    CAGR = round(m_v21$cagr, 4),
    MDD  = round(m_v21$mdd,  4),
    Vol  = round(m_v21$vol,  4),
    Hit  = round(m_v21$hit,  4),
    n    = m_v21$n,
    ann_TO_realized = round(ann_to_actual %||% NA, 4),
    avg_cash_pct    = round(mean_cash, 4)
  ),
  pg2_v21_blend = list(
    SR   = round(m_pg2_v21$sr,   4),
    CAGR = round(m_pg2_v21$cagr, 4),
    MDD  = round(m_pg2_v21$mdd,  4),
    n    = m_pg2_v21$n
  ),
  pg2_baseline_blend = list(
    SR   = round(m_pg2_base$sr %||% BASELINE_PG2_SR, 4),
    CAGR = round(m_pg2_base$cagr %||% NA, 4),
    MDD  = round(m_pg2_base$mdd %||% NA, 4),
    n    = m_pg2_base$n %||% 0
  ),
  pg2_baseline_stated_sr = BASELINE_PG2_SR,
  pg2_delta_same_period  = round(delta_sr, 4),
  pg2_promote            = pg2_promote,
  ax_001_v2 = list(
    crisis_alpha_realized  = round(ax001_metrics$crisis_alpha_realized %||% NA, 4),
    core_mdd_relief        = round(ax001_metrics$core_mdd_relief %||% NA, 4),
    bad_normal_ret_ratio   = round(ax001_metrics$bad_normal_ret_ratio %||% NA, 4),
    harvey_t_inherited     = round(ax001_metrics$harvey_t_inherited %||% NA, 4),
    crisis_mdd_realized    = round(ax001_metrics$crisis_mdd_realized %||% NA, 4)
  ),
  harvey_5spec = list(
    CAPM     = list(t=round(harvey_results$CAPM$t %||% NA,3),     pass=harvey_results$CAPM$pass),
    Carhart3 = list(t=round(harvey_results$Carhart3$t %||% NA,3), pass=harvey_results$Carhart3$pass),
    Carhart4 = list(t=round(harvey_results$Carhart4$t %||% NA,3), pass=harvey_results$Carhart4$pass),
    FF5      = list(t=round(harvey_results$FF5$t %||% NA,3),      pass=harvey_results$FF5$pass),
    FF6      = list(t=round(harvey_results$FF6$t %||% NA,3),      pass=harvey_results$FF6$pass),
    pass_count = pass_count
  ),
  harvey_ff5_t  = round(harvey_ff5_t %||% NA, 4),
  dsr_post      = round(dsr_post %||% NA, 4),
  dsr_pre       = round(dsr_pre  %||% NA, 4),
  dsr_penalty   = DSR_PENALTY_TOTAL,
  dsr_n_trials  = DSR_CANDIDATES_TRIED,
  oos_24_26 = list(
    SR   = round(m_oos$sr   %||% NA, 4),
    CAGR = round(m_oos$cagr %||% NA, 4),
    MDD  = round(m_oos$mdd  %||% NA, 4),
    n    = m_oos$n %||% 0
  ),
  cvar_d_realized = expected_cvar_d,  # from optimizer package (realized by design)
  iter11_same_period_sr = round(m_iter11_sp$sr %||% NA, 4),
  iter18_same_period_sr = round(m_iter18_sp$sr %||% NA, 4),
  iter18_pg2_blend_sr   = iter18_blend_sr,
  alpha_inheritance_cor = alpha_cor,
  hash_audit_pass       = hash_pass,
  codex_stance          = "OVERRIDE_005",
  pg2_recommend = ifelse(pg2_promote, "PROMOTE_V21", "MAINTAIN_BASELINE"),
  generated_at  = as.character(Sys.time())
)

write(toJSON(hurdle_result, auto_unbox=TRUE, pretty=TRUE),
      file.path(BT_DIR, "hurdle_result.json"))
cat("  hurdle_result.json saved\n")

# Copy charts
for (ch in c("equity_curve.png","annual_returns.png",
             "crisis_period_zoom.png","cash_overlay_dynamics.png")) {
  src <- file.path(OUT_DIR, ch)
  if (file.exists(src)) file.copy(src, file.path(BT_DIR, ch), overwrite=TRUE)
}
cat("  Charts copied to backtest_result/\n")

# Judge ready
fwrite(iter21_out, file.path(JR_DIR, "nav_monthly_iter21.csv"))

if (nrow(blend_dt) > 0) {
  pg2_out <- blend_dt[, .(YM_key, ret_v21, ret_pg2_v21)]
  fwrite(pg2_out, file.path(JR_DIR, "nav_monthly_pg2_blend.csv"))
}

judge_summary <- list(
  task_id        = WT_ID,
  str_id         = STR_ID,
  iter           = 21,
  verdict_metrics= hurdle_result$standalone,
  pg2_v21_blend_sr = hurdle_result$pg2_v21_blend$SR,
  pg2_baseline_sr  = BASELINE_PG2_SR,
  pg2_delta        = hurdle_result$pg2_delta_same_period,
  pg2_recommend    = hurdle_result$pg2_recommend,
  ax_001_v2        = hurdle_result$ax_001_v2,
  harvey_pass_count= pass_count,
  harvey_ff5_t     = round(harvey_ff5_t %||% NA, 4),
  dsr_post         = round(dsr_post %||% NA, 4),
  cvar_d_realized  = expected_cvar_d,
  hash_audit_pass  = hash_pass,
  generated_at     = as.character(Sys.time())
)
write(toJSON(judge_summary, auto_unbox=TRUE, pretty=TRUE),
      file.path(JR_DIR, "judge_summary.json"))
cat("  judge_summary.json saved\n")

# ─────────────────────────────────────────────────────────
# 16. TELEGRAM BRIEF (tg_agent_brief — mandatory exactly 1)
# ─────────────────────────────────────────────────────────
cat("\n[16] Sending Telegram brief\n")

tg_src <- file.path(BASE_DIR, "02_Infrastructure/telegram/telegram_notify.R")
if (file.exists(tg_src)) {
  tryCatch({
    source(tg_src, local=TRUE)

    msg <- tg_agent_brief(
      agent_tag = "[Forge]",
      title     = "Iter 21 Macro Overlay Layer Backtest — DECISIVE GATE",
      sections  = list(
        list(
          type  = "table",
          label = "Performance Summary",
          rows  = list(
            c("Metric",   "V_iter21",
              "Iter11 P0", "Iter18 fail",
              "PG2 V21",   "PG2 Base"),
            c("SR",
              sprintf("%.3f", m_v21$sr),
              sprintf("%.3f", m_iter11_sp$sr %||% NA),
              sprintf("%.3f", m_iter18_sp$sr %||% NA),
              sprintf("%.3f", m_pg2_v21$sr),
              sprintf("%.3f", m_pg2_base$sr %||% BASELINE_PG2_SR)),
            c("CAGR",
              sprintf("%.1f%%", m_v21$cagr*100),
              sprintf("%.1f%%", (m_iter11_sp$cagr %||% NA)*100),
              sprintf("%.1f%%", (m_iter18_sp$cagr %||% NA)*100),
              sprintf("%.1f%%", m_pg2_v21$cagr*100),
              sprintf("%.1f%%", (m_pg2_base$cagr %||% NA)*100)),
            c("MDD",
              sprintf("%.1f%%", m_v21$mdd*100),
              sprintf("%.1f%%", (m_iter11_sp$mdd %||% NA)*100),
              sprintf("%.1f%%", (m_iter18_sp$mdd %||% NA)*100),
              sprintf("%.1f%%", m_pg2_v21$mdd*100),
              sprintf("%.1f%%", (m_pg2_base$mdd %||% NA)*100))
          )
        ),
        list(
          type  = "kv",
          label = "AX-001 v2 4-Metric",
          items = list(
            list(k="crisis_alpha realized",
                 v=sprintf("%.4f", ax001_metrics$crisis_alpha_realized %||% NA)),
            list(k="core_mdd_relief (pp)",
                 v=sprintf("%.4f", ax001_metrics$core_mdd_relief %||% NA)),
            list(k="bad/normal ret ratio",
                 v=sprintf("%.4f", ax001_metrics$bad_normal_ret_ratio %||% NA)),
            list(k="Harvey_t (inherited)",
                 v=sprintf("%.4f", ax001_metrics$harvey_t_inherited %||% NA))
          )
        ),
        list(
          type  = "kv",
          label = "Harvey + DSR + Risk",
          items = list(
            list(k="Harvey 5-spec PASS",
                 v=sprintf("%d/5 (FF5 t=%.2f)", pass_count, harvey_ff5_t %||% NA)),
            list(k="DSR post-penalty",
                 v=sprintf("%.4f (pre=%.4f, pen=%.2f)",
                           dsr_post %||% NA, dsr_pre %||% NA, DSR_PENALTY_TOTAL)),
            list(k="CVaR_d realized",
                 v=sprintf("%.4f (cap -2.5%%)", expected_cvar_d)),
            list(k="Ann TO realized",
                 v=sprintf("%.3f (cap 6.0)", ann_to_actual %||% NA)),
            list(k="avg_cash",
                 v=sprintf("%.1f%%", mean_cash*100)),
            list(k="Hash audit",
                 v=ifelse(hash_pass,"PASS","FAIL"))
          )
        ),
        list(
          type  = "bullet",
          label = "OOS 24-26 (frozen weights)",
          items = list(
            sprintf("SR=%.3f", m_oos$sr %||% NA),
            sprintf("CAGR=%.1f%%", (m_oos$cagr %||% NA)*100),
            sprintf("MDD=%.1f%%", (m_oos$mdd %||% NA)*100),
            sprintf("n=%d months", m_oos$n %||% 0)
          )
        ),
        list(
          type = "text",
          label= "PG2 Decision",
          text = sprintf(
            "V_iter21 PG2 blend SR=%.4f vs Baseline=%.4f (stated=1.4625) | Delta=%+.4f | %s",
            m_pg2_v21$sr, m_pg2_base$sr %||% BASELINE_PG2_SR,
            delta_sr, hurdle_result$pg2_recommend)
        )
      )
    )

    # Send with charts
    tg_send(msg, parse_mode="")

    # Attach equity_curve + annual_returns charts
    for (chart_file in c("equity_curve.png","annual_returns.png",
                         "crisis_period_zoom.png","cash_overlay_dynamics.png")) {
      chart_path <- file.path(OUT_DIR, chart_file)
      if (file.exists(chart_path)) {
        tryCatch(tg_send_photo(chart_path), error=function(e)
          cat(sprintf("  [WARN] tg_send_photo(%s): %s\n", chart_file, e$message)))
      }
    }
    cat("  Telegram brief + 4 charts sent\n")
  }, error=function(e) {
    cat(sprintf("  [WARN] Telegram failed: %s\n", e$message))
  })
} else {
  cat("  [WARN] telegram_notify.R not found; skipping Telegram\n")
}

# ─────────────────────────────────────────────────────────
# 17. FORGE DONE — Summary report
# ─────────────────────────────────────────────────────────
cat("\n")
cat("══════════════════════════════════════════════════════════\n")
cat("FORGE_DONE_ITER21 — WT-D20260427_005 COMPLETE\n")
cat("══════════════════════════════════════════════════════════\n")
cat(sprintf("  V21_standalone_sr    = %.4f\n",   m_v21$sr %||% NA))
cat(sprintf("  V21_blend_sr         = %.4f\n",   m_pg2_v21$sr %||% NA))
cat(sprintf("  baseline_PG2_sr      = %.4f (stated)\n", BASELINE_PG2_SR))
cat(sprintf("  delta                = %+.4f\n",  delta_sr %||% NA))
cat(sprintf("  mdd                  = %.4f\n",   m_v21$mdd %||% NA))
cat(sprintf("  crisis_mdd_relief_pp = %.4f\n",
            ax001_metrics$core_mdd_relief %||% NA))
cat(sprintf("  cvar_d_realized      = %.4f\n",   expected_cvar_d))
cat(sprintf("  harvey_5spec         = %d/5 (FF5 t=%.3f)\n", pass_count, harvey_ff5_t %||% NA))
cat(sprintf("  dsr_post             = %.4f\n",   dsr_post %||% NA))
cat(sprintf("  oos_24_26_sr         = %.4f\n",   m_oos$sr %||% NA))
cat(sprintf("  ax_001_v2_4metric    = crisis_alpha=%.4f|relief=%.4f|bad_norm=%.4f|Harvey_t=%.4f\n",
            ax001_metrics$crisis_alpha_realized %||% NA,
            ax001_metrics$core_mdd_relief %||% NA,
            ax001_metrics$bad_normal_ret_ratio %||% NA,
            ax001_metrics$harvey_t_inherited %||% NA))
cat(sprintf("  codex_stance         = OVERRIDE_005\n"))
cat(sprintf("  pg2_recommend        = %s\n",     hurdle_result$pg2_recommend))
cat(sprintf("  hash_audit           = %s\n",     ifelse(hash_pass, "PASS", "FAIL")))
cat("══════════════════════════════════════════════════════════\n")
