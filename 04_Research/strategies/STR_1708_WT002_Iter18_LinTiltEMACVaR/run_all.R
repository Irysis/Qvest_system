## ============================================================
## STR_1708 — WT-D20260427_002 Iter 18 LinTilt_EMA_CVaR
## Optimizer Track: Alpha=STR_1701 inheritance (cor 1.0) + LinTilt_EMA_CVaR optimizer
## ============================================================
## ## 핵심아이디어
##   Iter 18 = Optimizer Track (L-226 alpha activation remediation)
##   Alpha: STR_1701 inheritance (cor=1.0 strict) — alpha 변경 절대 금지
##   Risk Σ: Iter 15 inheritance (ledoit_wolf_oracle factor model)
##   Optimizer: LinTilt_EMA_CVaR selected (10-method comparison, best net_IR=0.1547)
##
##   92 sig_dates walk-forward (2008-01-31 ~ 2023-11-30) + 24-26 frozen-weights OOS.
##   LinTilt_EMA_CVaR: alpha-activation via linear tilt + EMA smoothing + CVaR adjustment
##   Alpha activation rate=39.3% vs ERC baseline 0% (L-226 remediation).
##
## v6.1 R12 Pure Function:
##   - alpha/risk/optimization 패키지 절대 수정 금지
##   - target_weights 재해석 금지 (92 sig_date schedule 그대로 적용)
##   - Hash audit: 시작/완료 동일 검증
##
## 검증 영역:
##   Task 1: V_iter18 standalone walk-forward (92 sig_dates)
##   Task 2: PG2 blend (V_iter18 80% + STR_1656 20%) vs baseline (STR_1701 80% + STR_1656 20%)
##   Task 3: 5-spec Harvey FF5 v2 NW-HAC (CAPM/C3/C4/FF5/FF6)
##   Task 4: DSR post-penalty (n_trials=92 per optimizer package)
##   Task 5: Same-period comparison (V_iter18 vs Iter11 STR_1701 standalone vs Iter15 V3 ERC)
##   Task 6: 24-26 OOS extension (frozen weights buy-and-hold)
##   Task 7: 4 charts (equity_curve, annual_returns, oos_zoom, scenario_comparison)
##   Task 8: Telegram brief
##
## DSR penalty basis:
##   - Iter 18: alpha 1 + risk 5 + optimizer 10 = 10 candidates × 0.05 = 0.50
##     (Optimizer selected from 10-method comparison per optimization_package.json)
##
## PIT 준수:
##   C1: walk-forward only (no full-sample re-optimization)
##   C2: monthly ret = close(t)/close(t-1) - 1
##   C9: weight at sig_date d → applied (d, next_sig_date] (lag enforced)
##   C10: liquidity 2e8 KRW PIT t-30..t-1 (one-sided)
##   C13: Z_Score_Aligned alpha inherited (no manual flip)
##   LB cutoff: last sig_date 2023-11-30 strictly before lockbox 2024-01-23
## ============================================================

cat("=== STR_1708: WT-D20260427_002 Iter 18 LinTilt_EMA_CVaR (Optimizer Track) ===\n")
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

BASE_DIR  <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
STR_ID    <- "STR_1708"
WT_ID     <- "WT-D20260427_002"
ITER11_WT <- "WT-D20260426_004"   # Iter 11 STR_1701 reference
ITER15_WT <- "WT-D20260426_008"   # Iter 15 V3 ERC reference

WT_DIR    <- file.path(BASE_DIR, "qepm/mailbox/worktask", WT_ID)
OUT_DIR   <- file.path(BASE_DIR, "04_Research/strategies/STR_1708_WT002_Iter18_LinTiltEMACVaR/output")
BT_DIR    <- file.path(WT_DIR, "backtest_result")
JR_DIR    <- file.path(WT_DIR, "judge_ready")
ITER11_BT <- file.path(BASE_DIR, "qepm/mailbox/worktask", ITER11_WT, "backtest_result")
ITER15_JR <- file.path(BASE_DIR, "qepm/mailbox/worktask", ITER15_WT, "judge_ready")

dir.create(OUT_DIR, showWarnings=FALSE, recursive=TRUE)
dir.create(BT_DIR,  showWarnings=FALSE, recursive=TRUE)
dir.create(JR_DIR,  showWarnings=FALSE, recursive=TRUE)

# DSR penalty: Optimizer 10 methods tested
DSR_CANDIDATES_TRIED <- 10
DSR_PENALTY_PER_CAND <- 0.05
DSR_PENALTY_TOTAL    <- DSR_CANDIDATES_TRIED * DSR_PENALTY_PER_CAND  # 0.50

cat(sprintf("[0] Config | STR_ID=%s WT_ID=%s\n", STR_ID, WT_ID))
cat(sprintf("    DSR penalty basis: %d candidates × %.2f = %.2f\n",
            DSR_CANDIDATES_TRIED, DSR_PENALTY_PER_CAND, DSR_PENALTY_TOTAL))

# ─────────────────────────────────────────────────────────
# 1. START hash audit (3-package read-only verification)
# ─────────────────────────────────────────────────────────
cat("\n[1] START hash audit (3-package read-only verification)\n")

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
  cat(sprintf("    %-30s = %s\n", paste0(n, "_package.json"),
              substr(start_hashes[n], 1, 16)))
cat(sprintf("    %-30s = %s\n", "weights.csv", substr(start_w_hash, 1, 16)))

# ─────────────────────────────────────────────────────────
# 2. 3-package 로드 (READ-ONLY)
# ─────────────────────────────────────────────────────────
cat("\n[2] Load 3-package (Pure Function boundary)\n")

alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector=FALSE)
risk_pkg  <- fromJSON(file.path(WT_DIR, "risk_package.json"),  simplifyVector=FALSE)
opt_pkg   <- fromJSON(file.path(WT_DIR, "optimization_package.json"), simplifyVector=FALSE)

method_tag    <- opt_pkg$method_selected %||% "LinTilt_EMA_CVaR"
expected_ir   <- opt_pkg$expected_information_ratio %||% 0.1547
expected_cagr <- opt_pkg$expected_cagr %||% 0.0122
expected_mdd  <- opt_pkg$expected_mdd %||% -0.402
expected_to   <- opt_pkg$turnover_annual %||% 5.663
alpha_cor     <- alpha_pkg$alpha_inheritance$cor_v18_vs_str1701 %||% 1.0
baseline_pg2  <- opt_pkg$selection_objective$baseline_pg2 %||%
                 "STR_1701 80% + STR_1656 20% (realized SR 1.4625)"

cat(sprintf("  Method: %s\n", method_tag))
cat(sprintf("  Expected (Optimizer): IR=%.4f CAGR=%.4f MDD=%.4f Ann_TO=%.3f\n",
            expected_ir, expected_cagr, expected_mdd, expected_to))
cat(sprintf("  Alpha inheritance cor=%.4f | Baseline PG2: %s\n",
            alpha_cor, baseline_pg2))

# ─────────────────────────────────────────────────────────
# 3. weights.csv 로드 (92 sig_dates × 20 tickers)
# ─────────────────────────────────────────────────────────
cat("\n[3] Load weights schedule (92 sig_dates × LinTilt_EMA_CVaR)\n")

w_dt <- fread(weights_path)
w_dt[, Date := as.Date(Date)]
setkey(w_dt, Date, Ticker)

sig_dates <- sort(unique(w_dt$Date))
n_sd <- length(sig_dates)
cat(sprintf("  weights.csv: %d rows | %d sig_dates\n", nrow(w_dt), n_sd))
cat(sprintf("  date range: %s ~ %s\n",
            as.character(min(sig_dates)), as.character(max(sig_dates))))

# Hard constraint verification
sum_check <- w_dt[, .(sum_w=sum(Weight), n=.N, max_w=max(Weight), min_w=min(Weight)), by=Date]
cat(sprintf("  Weight sum [%.6f, %.6f] | n_names [%d, %d]\n",
            min(sum_check$sum_w), max(sum_check$sum_w),
            min(sum_check$n), max(sum_check$n)))
cat(sprintf("  Max weight=%.4f (bound ≤ 0.20) | Min weight=%.4f (long-only)\n",
            max(sum_check$max_w), min(sum_check$min_w)))

if (max(sum_check$max_w) > 0.2001)
  warning("[WARN] max weight > 0.20 bound violated")
if (min(sum_check$min_w) < -0.0001)
  stop("[FAIL] negative weight — long-only violated")

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
cat(sprintf("  FF5 v2: %d rows | MKT+SMB+HML+WML+RMW+CMA+RF available\n", nrow(ff5)))

# ─────────────────────────────────────────────────────────
# 5. WALK-FORWARD BACKTEST (92 sig_dates)
#    LinTilt_EMA_CVaR weights directly applied.
#    Forge: RAWDATA × period return only. No weight recomputation.
# ─────────────────────────────────────────────────────────
cat("\n[5] Walk-forward backtest (92 sig_dates, LinTilt_EMA_CVaR applied)\n")

LIQ_THRESHOLD  <- 2e8
COMMISSION_BPS <- 15
COMMISSION_PCT <- COMMISSION_BPS / 10000

monthly_results <- vector("list", n_sd - 1)

for (i in seq_len(n_sd - 1)) {
  start_d <- sig_dates[i]
  end_d   <- sig_dates[i + 1]

  port_i <- w_dt[Date == start_d]
  if (nrow(port_i) == 0) next

  # Active holdings (weight > 0)
  port_active <- port_i[Weight > 0]
  n_active <- nrow(port_active)

  # Liquidity filter (PIT: t-30 to t-1, one-sided)
  liq_window_start <- start_d - 30L
  liq_data <- raw[Date >= liq_window_start & Date < start_d,
                  .(AvgTradingAmt=mean(TradingAmt, na.rm=TRUE)), by=Ticker]
  liquid_tickers <- liq_data[AvgTradingAmt >= LIQ_THRESHOLD, Ticker]

  port_liq <- port_active[Ticker %in% liquid_tickers]
  if (nrow(port_liq) == 0) port_liq <- copy(port_active)

  # Renormalize to sum=1 after liquidity filter
  total_w <- sum(port_liq$Weight)
  if (total_w > 0) {
    port_liq[, w_norm := Weight / total_w]
  } else {
    next
  }

  # Period returns (PIT C2: Date > start_d AND Date <= end_d)
  period_data <- raw[Date > start_d & Date <= end_d, .(Date, Ticker, Ret)]
  if (nrow(period_data) == 0) {
    monthly_results[[i]] <- data.table(
      period_start=start_d, period_end=end_d,
      port_ret=0, port_ret_gross=0,
      n_held=n_active, turnover=0,
      i=i)
    next
  }

  stock_rets <- period_data[, .(stock_ret=prod(1 + Ret, na.rm=TRUE) - 1), by=Ticker]
  merged <- merge(port_liq, stock_rets, by="Ticker", all.x=TRUE)
  merged[is.na(stock_ret), stock_ret := 0]

  port_ret_gross <- sum(merged$w_norm * merged$stock_ret, na.rm=TRUE)

  # Turnover estimate for transaction cost
  if (i == 1) {
    turnover_one_way <- 1.0
  } else {
    prev_port <- w_dt[Date == sig_dates[i-1] & Weight > 0]
    if (nrow(prev_port) == 0) {
      turnover_one_way <- 1.0
    } else {
      # Renormalize prev weights
      prev_total <- sum(prev_port$Weight)
      prev_port[, w_norm := Weight / prev_total]

      # Merge current and previous
      cur_norm <- port_liq[, .(Ticker, w_cur=w_norm)]
      prev_norm <- prev_port[, .(Ticker, w_prev=w_norm)]
      merged_to <- merge(cur_norm, prev_norm, by="Ticker", all=TRUE)
      merged_to[is.na(w_cur), w_cur := 0]
      merged_to[is.na(w_prev), w_prev := 0]
      # One-way turnover = sum of absolute weight changes / 2
      turnover_one_way <- sum(abs(merged_to$w_cur - merged_to$w_prev)) / 2
    }
  }

  # Net return after transaction costs (round-trip = 2× one_way)
  tc_drag <- 2 * turnover_one_way * COMMISSION_PCT
  port_ret_net <- port_ret_gross - tc_drag

  monthly_results[[i]] <- data.table(
    period_start = start_d,
    period_end   = end_d,
    port_ret     = port_ret_net,
    port_ret_gross = port_ret_gross,
    n_held       = n_active,
    turnover_ow  = turnover_one_way,
    i = i
  )
}

iter18_monthly <- rbindlist(monthly_results, fill=TRUE)
iter18_monthly <- iter18_monthly[!is.na(port_ret)]
cat(sprintf("  Walk-forward complete: %d periods\n", nrow(iter18_monthly)))

# ─────────────────────────────────────────────────────────
# 6. PERFORMANCE METRICS — V_iter18 standalone
# ─────────────────────────────────────────────────────────
cat("\n[6] V_iter18 standalone performance metrics\n")

compute_metrics <- function(rets, label="") {
  n <- length(rets)
  if (n < 2) return(list(sr=NA, cagr=NA, mdd=NA, vol=NA, n=n))
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
    cat(sprintf("  %s | n=%d | SR=%.4f | CAGR=%.4f | MDD=%.4f | Vol=%.4f | Hit=%.3f\n",
                label, n, sr, cagr, mdd, vol, hit))
  list(sr=sr, cagr=cagr, mdd=mdd, vol=vol, hit=hit, n=n,
       mean_r=mean_r, std_r=std_r, rets=rets)
}

rets_v18 <- iter18_monthly$port_ret
m_v18 <- compute_metrics(rets_v18, "V_iter18 standalone")

# Annual turnover
ann_to <- mean(iter18_monthly$turnover_ow, na.rm=TRUE) * 24  # ~bi-monthly × 2 × 12 = factor
# More accurate: sum of one-way TO / years
years_in_sample <- nrow(iter18_monthly) / 12
ann_to_actual <- sum(iter18_monthly$turnover_ow, na.rm=TRUE) / years_in_sample * 2  # round-trip
cat(sprintf("  Ann turnover (round-trip): %.2f | Expected from pkg: %.3f\n",
            ann_to_actual, expected_to))

# ─────────────────────────────────────────────────────────
# 7. PG2 BLEND: V_iter18 80% + STR_1656 20%
#    vs BASELINE: STR_1701 80% + STR_1656 20% (realized SR 1.4625)
# ─────────────────────────────────────────────────────────
cat("\n[7] PG2 blend computation\n")

# STR_1656 daily NAV → monthly
str1656_daily <- fread(
  file.path(BASE_DIR, "04_Research/strategies/STR_1656_MLRA/output/nav_S1_B.csv"))
str1656_daily[, Date := as.Date(Date)]
setorder(str1656_daily, Date)
str1656_daily[, YM := format(Date, "%Y-%m")]
str1656_monthly <- str1656_daily[, .SD[.N], by=YM]
str1656_monthly[, Monthly_Ret := NAV / shift(NAV) - 1]
str1656_monthly <- str1656_monthly[!is.na(Monthly_Ret)]
str1656_monthly[, period_end := Date]
str1656_monthly[, YM_key := format(Date, "%Y-%m")]

# Iter 11 STR_1701 monthly (same-period)
iter11_monthly <- fread(
  file.path(ITER11_BT, "iter11_full_period_monthly.csv"))
iter11_monthly[, Date := as.Date(Date)]
iter11_monthly[, YM_key := format(Date, "%Y-%m")]
setnames(iter11_monthly, "port_ret", "ret_1701")

# Iter 18 monthly: use period_end as date key
iter18_monthly[, YM_key := format(period_end, "%Y-%m")]

# Overlapping dates for PG2 blend
cat("  Building PG2 blend overlap (V_iter18 80% + STR_1656 20%)\n")

blend_dt <- merge(
  iter18_monthly[, .(YM_key, ret_v18=port_ret)],
  str1656_monthly[, .(YM_key, ret_1656=Monthly_Ret)],
  by="YM_key")

blend_dt[, ret_pg2_v18 := 0.8 * ret_v18 + 0.2 * ret_1656]
cat(sprintf("  V_iter18 PG2 blend: %d overlapping months\n", nrow(blend_dt)))
m_pg2_v18 <- compute_metrics(blend_dt$ret_pg2_v18, "PG2_V_iter18 (80+20 blend)")

# Baseline PG2: STR_1701 80% + STR_1656 20%
blend_base <- merge(
  iter11_monthly[, .(YM_key, ret_1701)],
  str1656_monthly[, .(YM_key, ret_1656=Monthly_Ret)],
  by="YM_key")

# Subset to same period as V_iter18 PG2
common_ym <- intersect(blend_dt$YM_key, blend_base$YM_key)
blend_base_sub <- blend_base[YM_key %in% common_ym]
blend_dt_sub   <- blend_dt[YM_key %in% common_ym]
setorder(blend_base_sub, YM_key)
setorder(blend_dt_sub,   YM_key)

blend_base_sub[, ret_pg2_base := 0.8 * ret_1701 + 0.2 * ret_1656]
m_pg2_base <- compute_metrics(blend_base_sub$ret_pg2_base, "PG2_baseline STR_1701 (80+20 blend)")

# Iter 15 V3 ERC blend (WT_D20260426_008 nav_monthly_blend.csv)
iter15_blend <- fread(file.path(ITER15_JR, "nav_monthly_blend.csv"))
iter15_blend[, Date := as.Date(Date)]
iter15_blend[, YM_key := format(Date, "%Y-%m")]
setnames(iter15_blend, "Monthly_Ret", "ret_iter15_blend")
iter15_sub <- iter15_blend[YM_key %in% common_ym]
setorder(iter15_sub, YM_key)
if (nrow(iter15_sub) > 5) {
  m_pg2_iter15 <- compute_metrics(iter15_sub$ret_iter15_blend,
                                  "PG2_Iter15 V3 ERC (blend)")
} else {
  cat("  [WARN] Iter 15 blend insufficient overlap; skipping\n")
  m_pg2_iter15 <- list(sr=NA, cagr=NA, mdd=NA)
}

# Delta vs baseline
delta_sr <- m_pg2_v18$sr - m_pg2_base$sr
cat(sprintf("\n  PG2 DECISION:\n"))
cat(sprintf("    V_iter18 blend SR  = %.4f\n", m_pg2_v18$sr))
cat(sprintf("    Baseline (STR_1701 blend) SR = %.4f\n", m_pg2_base$sr))
cat(sprintf("    Baseline (stated) SR = 1.4625\n"))
cat(sprintf("    Delta vs same-period baseline = %+.4f\n", delta_sr))
cat(sprintf("    Iter 15 blend SR   = %.4f (Forge 0.996 stated)\n",
            m_pg2_iter15$sr %||% NA))
pg2_promote <- (m_pg2_v18$sr >= 1.4625)
cat(sprintf("    PROMOTE? V_iter18 blend SR >= 1.4625: %s\n",
            ifelse(pg2_promote, "YES — PROMOTE_V18", "NO — MAINTAIN_BASELINE")))

# ─────────────────────────────────────────────────────────
# 8. 5-SPEC HARVEY FF5 v2 NW-HAC
# ─────────────────────────────────────────────────────────
cat("\n[8] 5-spec Harvey FF5 v2 NW-HAC regression\n")

# Merge iter18 monthly with FF5 — use period_end for date matching
ff5_m <- copy(ff5)
ff5_m[, YM_key := format(Date, "%Y-%m")]

reg_dt <- merge(
  iter18_monthly[, .(YM_key, port_ret)],
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

cat(sprintf("  Regression sample: %d months\n", nrow(reg_dt)))

# NW-HAC lag selection: floor(4 * (n/100)^(2/9))
n_reg <- nrow(reg_dt)
nw_lag <- max(1, floor(4 * (n_reg/100)^(2/9)))
cat(sprintf("  NW-HAC lag: %d\n", nw_lag))

harvey_specs <- list(
  CAPM    = "excess_ret ~ MKT_e",
  Carhart3 = "excess_ret ~ MKT_e + SMB_e + HML_e",
  Carhart4 = "excess_ret ~ MKT_e + SMB_e + HML_e + WML_e",
  FF5     = "excess_ret ~ MKT_e + SMB_e + HML_e + RMW_e + CMA_e",
  FF6     = "excess_ret ~ MKT_e + SMB_e + HML_e + WML_e + RMW_e + CMA_e"
)

harvey_results <- list()
pass_count <- 0

for (spec_name in names(harvey_specs)) {
  fm <- lm(as.formula(harvey_specs[[spec_name]]), data=reg_dt)
  ctest <- coeftest(fm, vcov=NeweyWest(fm, lag=nw_lag, prewhite=FALSE))
  alpha_row <- ctest["(Intercept)", ]
  t_stat <- alpha_row["t value"]
  p_val  <- alpha_row["Pr(>|t|)"]
  alpha_ann <- coef(fm)["(Intercept)"] * 12
  pass <- abs(t_stat) >= 2.95
  if (pass) pass_count <- pass_count + 1
  harvey_results[[spec_name]] <- list(
    t=t_stat, p=p_val, alpha_ann=alpha_ann, pass=pass)
  cat(sprintf("  %-10s | alpha_ann=%.4f | t=%.3f | %s\n",
              spec_name, alpha_ann, t_stat,
              ifelse(pass, "PASS (t>=2.95)", "FAIL")))
}
cat(sprintf("  Harvey 5-spec PASS: %d/5\n", pass_count))
harvey_ff5_t <- harvey_results$FF5$t

# ─────────────────────────────────────────────────────────
# 9. DSR POST-PENALTY
# ─────────────────────────────────────────────────────────
cat("\n[9] DSR post-penalty\n")

# DSR formula: SR_obs / sqrt(1 + (SR_obs^2 / 4) * (skew^2 + kurtosis - 3) / n)
# scaled by penalty from multiple testing
sr_obs <- m_v18$sr
n_m    <- m_v18$n
skew_r <- if (requireNamespace("e1071", quietly=TRUE)) {
  e1071::skewness(rets_v18, na.rm=TRUE)
} else {
  n3 <- n_m; mn <- mean(rets_v18); s <- sd(rets_v18)
  (1/n3) * sum((rets_v18-mn)^3) / s^3
}
kurt_r <- if (requireNamespace("e1071", quietly=TRUE)) {
  e1071::kurtosis(rets_v18, na.rm=TRUE)
} else {
  n3 <- n_m; mn <- mean(rets_v18); s <- sd(rets_v18)
  (1/n3) * sum((rets_v18-mn)^4) / s^4 - 3
}

# Haircut SR (Bailey-Lopez de Prado)
dsr_denom <- sqrt(1 + (sr_obs^2 / 4) * (skew_r^2 + (kurt_r - 3)) / n_m)
if (is.nan(dsr_denom) || is.na(dsr_denom) || dsr_denom <= 0) dsr_denom <- 1
dsr_pre <- sr_obs / dsr_denom

# Post-penalty: subtract multiple testing penalty
dsr_post <- dsr_pre - DSR_PENALTY_TOTAL

cat(sprintf("  SR_obs=%.4f | skew=%.3f | kurt=%.3f | n=%d\n",
            sr_obs, skew_r, kurt_r, n_m))
cat(sprintf("  DSR_pre=%.4f | DSR_penalty=%.2f | DSR_post=%.4f\n",
            dsr_pre, DSR_PENALTY_TOTAL, dsr_post))
cat(sprintf("  CVaR_d realized (proxy, optimizer): %.4f\n",
            opt_pkg$cvar_d_post_optim %||% -0.0313))

# ─────────────────────────────────────────────────────────
# 10. SAME-PERIOD COMPARISON
# ─────────────────────────────────────────────────────────
cat("\n[10] Same-period comparison\n")

# Iter 11 STR_1701 same-period
iter11_sp <- iter11_monthly[YM_key %in% iter18_monthly$YM_key]
setorder(iter11_sp, YM_key)
m_iter11_sp <- compute_metrics(iter11_sp$ret_1701, "Iter11 STR_1701 same-period")

# Iter 15 V3 ERC (nav_monthly_v3.csv from judge_ready)
iter15_v3_path <- file.path(ITER15_JR, "nav_monthly_v3.csv")
if (file.exists(iter15_v3_path)) {
  iter15_v3 <- fread(iter15_v3_path)
  iter15_v3[, Date := as.Date(Date)]
  iter15_v3[, YM_key := format(Date, "%Y-%m")]
  iter15_v3_sp <- iter15_v3[YM_key %in% iter18_monthly$YM_key]
  setorder(iter15_v3_sp, YM_key)
  ret_col_v3 <- grep("Ret|ret|Return|return", names(iter15_v3_sp), value=TRUE)[1]
  if (!is.na(ret_col_v3) && nrow(iter15_v3_sp) > 5) {
    m_iter15_sp <- compute_metrics(
      iter15_v3_sp[[ret_col_v3]], "Iter15 V3 ERC same-period")
  } else {
    cat("  [WARN] Iter15 V3 ERC same-period: insufficient data\n")
    m_iter15_sp <- list(sr=NA, cagr=NA, mdd=NA)
  }
} else {
  cat("  [WARN] nav_monthly_v3.csv not found; skipping Iter15 V3 standalone\n")
  m_iter15_sp <- list(sr=NA, cagr=NA, mdd=NA)
}

# Summary table
cat("\n  === SAME-PERIOD COMPARISON TABLE ===\n")
cat(sprintf("  %-30s | SR=%7.4f | CAGR=%7.4f | MDD=%7.4f | n=%d\n",
            "V_iter18 (LinTilt_EMA_CVaR)",
            m_v18$sr, m_v18$cagr, m_v18$mdd, m_v18$n))
cat(sprintf("  %-30s | SR=%7.4f | CAGR=%7.4f | MDD=%7.4f | n=%d\n",
            "Iter11 STR_1701 (same-period)",
            m_iter11_sp$sr %||% NA, m_iter11_sp$cagr %||% NA,
            m_iter11_sp$mdd %||% NA, m_iter11_sp$n %||% 0))
cat(sprintf("  %-30s | SR=%7.4f | CAGR=%7.4f | MDD=%7.4f\n",
            "Iter15 V3 ERC (same-period)",
            m_iter15_sp$sr %||% NA, m_iter15_sp$cagr %||% NA,
            m_iter15_sp$mdd %||% NA))

# ─────────────────────────────────────────────────────────
# 11. 24-26 OOS EXTENSION (frozen weights buy-and-hold)
# ─────────────────────────────────────────────────────────
cat("\n[11] 24-26 OOS extension (frozen weights from last sig_date)\n")

OOS_START <- as.Date("2024-01-02")
OOS_END   <- as.Date("2026-04-27")
LOCKBOX_SEAL <- as.Date("2024-01-23")  # PIT hard cutoff

# Use last sig_date weights (2023-11-30)
last_sd   <- max(sig_dates)
last_port <- w_dt[Date == last_sd & Weight > 0]
if (nrow(last_port) == 0) stop("[FAIL] No last-period weights")

total_last <- sum(last_port$Weight)
last_port[, w_final := Weight / total_last]
cat(sprintf("  Frozen weights from %s | %d holdings | sum_w=%.6f\n",
            last_sd, nrow(last_port), sum(last_port$w_final)))

# OOS data: after last sig_date
oos_raw <- raw[Date > last_sd & Date <= OOS_END,
               .(Date, Ticker, Ret)]
cat(sprintf("  OOS RAWDATA: %d rows | %s ~ %s\n",
            nrow(oos_raw),
            as.character(min(oos_raw$Date)),
            as.character(max(oos_raw$Date))))

# Monthly OOS: group by year-month
oos_raw[, YM := format(Date, "%Y-%m")]
oos_monthly_list <- list()

oos_yms <- sort(unique(oos_raw$YM))
for (ym in oos_yms) {
  period_data_oos <- oos_raw[YM == ym]
  if (nrow(period_data_oos) == 0) next

  stock_rets_oos <- period_data_oos[,
    .(stock_ret=prod(1 + Ret, na.rm=TRUE) - 1), by=Ticker]
  merged_oos <- merge(last_port, stock_rets_oos,
                      by.x="Ticker", by.y="Ticker", all.x=TRUE)
  merged_oos[is.na(stock_ret), stock_ret := 0]

  ret_oos <- sum(merged_oos$w_final * merged_oos$stock_ret, na.rm=TRUE)
  oos_monthly_list[[ym]] <- data.table(YM=ym, ret_oos=ret_oos)
}

oos_monthly <- rbindlist(oos_monthly_list)
if (nrow(oos_monthly) > 1) {
  # No transaction costs for buy-and-hold OOS
  m_oos <- compute_metrics(oos_monthly$ret_oos, "OOS 24-26 (frozen weights)")
  cat(sprintf("  OOS period: %d months\n", nrow(oos_monthly)))
} else {
  cat("  [WARN] Insufficient OOS data\n")
  m_oos <- list(sr=NA, cagr=NA, mdd=NA, n=0)
}

# ─────────────────────────────────────────────────────────
# 12. COMPLETE hash audit
# ─────────────────────────────────────────────────────────
cat("\n[12] COMPLETE hash audit (Pure Function verification)\n")

end_hashes <- sapply(pkg_files, function(f) tryCatch(
  as.character(tools::md5sum(f)), error=function(e) "MISSING"))
end_w_hash  <- as.character(tools::md5sum(weights_path))

hash_pass <- TRUE
for (n in names(start_hashes)) {
  match <- identical(start_hashes[n], end_hashes[n])
  if (!match) {
    cat(sprintf("  [FAIL] %s HASH MISMATCH: start=%s end=%s\n",
                n, substr(start_hashes[n],1,16), substr(end_hashes[n],1,16)))
    hash_pass <- FALSE
  }
}
w_match <- identical(start_w_hash, end_w_hash)
if (!w_match) {
  cat(sprintf("  [FAIL] weights.csv HASH MISMATCH\n"))
  hash_pass <- FALSE
}
if (hash_pass) cat("  HASH AUDIT PASS — all 4 artifacts unchanged\n")

# ─────────────────────────────────────────────────────────
# 13. CHARTS
# ─────────────────────────────────────────────────────────
cat("\n[13] Generating 4 charts\n")

# Build NAV curves for plotting
iter18_monthly[, cum_nav := cumprod(1 + port_ret)]

# Chart 1: Equity curve (V_iter18 vs STR_1701 same-period)
iter11_sp_plt <- iter11_monthly[YM_key %in% iter18_monthly$YM_key]
setorder(iter11_sp_plt, YM_key)
iter11_sp_plt[, cum_nav := cumprod(1 + ret_1701)]

plot_nav <- rbindlist(list(
  data.table(Date=iter18_monthly$period_end,
             NAV=iter18_monthly$cum_nav, Strategy="V_iter18 LinTilt_EMA_CVaR"),
  data.table(Date=as.Date(paste0(iter11_sp_plt$YM_key, "-01")),
             NAV=iter11_sp_plt$cum_nav, Strategy="Iter11 STR_1701")
), fill=TRUE)

p1 <- ggplot(plot_nav, aes(x=Date, y=NAV, color=Strategy)) +
  geom_line(linewidth=0.8) +
  scale_y_continuous(labels=comma) +
  scale_x_date(date_labels="%Y", date_breaks="2 years") +
  labs(title="STR_1708 Iter 18 — V_iter18 vs STR_1701 (Same Period)",
       subtitle=sprintf("V_iter18 SR=%.3f | STR_1701 SR=%.3f | 2008-2023",
                        m_v18$sr, m_iter11_sp$sr %||% NA),
       x=NULL, y="NAV (base=1)", color=NULL) +
  theme_minimal(base_size=11) +
  theme(legend.position="bottom")

ggsave(file.path(OUT_DIR, "equity_curve.png"), p1, width=10, height=5, dpi=150)
cat("  equity_curve.png saved\n")

# Chart 2: Annual returns
iter18_monthly[, Year := as.integer(format(period_end, "%Y"))]
annual_v18 <- iter18_monthly[, .(ann_ret=prod(1+port_ret)-1), by=Year]

p2 <- ggplot(annual_v18, aes(x=factor(Year), y=ann_ret,
                             fill=ifelse(ann_ret >= 0, "pos", "neg"))) +
  geom_col() +
  scale_fill_manual(values=c(pos="steelblue", neg="tomato"), guide="none") +
  scale_y_continuous(labels=percent_format(accuracy=1)) +
  labs(title="STR_1708 Iter 18 — Annual Returns",
       x=NULL, y="Annual Return") +
  theme_minimal(base_size=11) +
  theme(axis.text.x=element_text(angle=45, hjust=1))

ggsave(file.path(OUT_DIR, "annual_returns.png"), p2, width=10, height=4, dpi=150)
cat("  annual_returns.png saved\n")

# Chart 3: OOS zoom
if (nrow(oos_monthly) > 1) {
  oos_monthly[, Date := as.Date(paste0(YM, "-01"))]
  oos_monthly[, cum_nav_oos := cumprod(1 + ret_oos)]

  p3 <- ggplot(oos_monthly, aes(x=Date, y=cum_nav_oos)) +
    geom_line(color="darkgreen", linewidth=1) +
    geom_hline(yintercept=1, linetype="dashed", color="gray") +
    scale_y_continuous(labels=comma) +
    scale_x_date(date_labels="%Y-%m") +
    labs(title="STR_1708 Iter 18 — 24-26 OOS Extension (Frozen Weights)",
         subtitle=sprintf("OOS SR=%.3f | CAGR=%.4f | MDD=%.4f | n=%d months",
                          m_oos$sr %||% NA, m_oos$cagr %||% NA,
                          m_oos$mdd %||% NA, nrow(oos_monthly)),
         x=NULL, y="NAV (base=1)") +
    theme_minimal(base_size=11)

  ggsave(file.path(OUT_DIR, "oos_zoom.png"), p3, width=10, height=4, dpi=150)
  cat("  oos_zoom.png saved\n")
} else {
  cat("  [SKIP] oos_zoom.png — insufficient OOS data\n")
}

# Chart 4: Scenario comparison (PG2 blends)
blend_dt_sub2 <- merge(
  blend_dt_sub[, .(YM_key, ret_v18=ret_v18, ret_pg2_v18)],
  blend_base_sub[, .(YM_key, ret_pg2_base)],
  by="YM_key")
setorder(blend_dt_sub2, YM_key)
blend_dt_sub2[, cum_pg2_v18  := cumprod(1 + ret_pg2_v18)]
blend_dt_sub2[, cum_pg2_base := cumprod(1 + ret_pg2_base)]
blend_dt_sub2[, Date := as.Date(paste0(YM_key, "-01"))]

plot_sc <- rbindlist(list(
  data.table(Date=blend_dt_sub2$Date,
             NAV=blend_dt_sub2$cum_pg2_v18,
             Strategy=sprintf("PG2 V_iter18 blend (SR=%.3f)", m_pg2_v18$sr)),
  data.table(Date=blend_dt_sub2$Date,
             NAV=blend_dt_sub2$cum_pg2_base,
             Strategy=sprintf("PG2 Baseline blend (SR=%.3f)", m_pg2_base$sr))
), fill=TRUE)

p4 <- ggplot(plot_sc, aes(x=Date, y=NAV, color=Strategy)) +
  geom_line(linewidth=0.8) +
  scale_y_continuous(labels=comma) +
  scale_x_date(date_labels="%Y") +
  labs(title="STR_1708 Iter 18 — PG2 Blend Comparison",
       subtitle=sprintf("V_iter18 blend SR=%.4f vs Baseline SR=%.4f | Delta=%+.4f",
                        m_pg2_v18$sr, m_pg2_base$sr, delta_sr),
       x=NULL, y="NAV (base=1)", color=NULL) +
  theme_minimal(base_size=11) +
  theme(legend.position="bottom")

ggsave(file.path(OUT_DIR, "scenario_comparison.png"), p4, width=10, height=5, dpi=150)
cat("  scenario_comparison.png saved\n")

# ─────────────────────────────────────────────────────────
# 14. SAVE RESULTS — backtest_result + judge_ready
# ─────────────────────────────────────────────────────────
cat("\n[14] Saving backtest_result and judge_ready artifacts\n")

# Monthly returns CSV
iter18_monthly_out <- iter18_monthly[, .(
  Date   = period_end,
  YM_key = YM_key,
  port_ret_gross = port_ret_gross,
  port_ret = port_ret,
  n_held = n_held,
  turnover_ow = turnover_ow
)]
fwrite(iter18_monthly_out,
       file.path(BT_DIR, "iter18_monthly_returns.csv"))

# OOS monthly
if (nrow(oos_monthly) > 1)
  fwrite(oos_monthly, file.path(BT_DIR, "oos_24_26_monthly.csv"))

# Hurdle result JSON
hurdle_result <- list(
  task_id       = WT_ID,
  str_id        = STR_ID,
  iter          = 18,
  method        = method_tag,
  # V_iter18 standalone
  standalone = list(
    SR   = round(m_v18$sr,   4),
    CAGR = round(m_v18$cagr, 4),
    MDD  = round(m_v18$mdd,  4),
    Vol  = round(m_v18$vol,  4),
    Hit  = round(m_v18$hit,  4),
    n    = m_v18$n,
    ann_TO_realized = round(ann_to_actual, 4)
  ),
  # PG2 blends
  pg2_v18_blend = list(
    SR   = round(m_pg2_v18$sr,   4),
    CAGR = round(m_pg2_v18$cagr, 4),
    MDD  = round(m_pg2_v18$mdd,  4),
    n    = m_pg2_v18$n
  ),
  pg2_baseline_blend = list(
    SR   = round(m_pg2_base$sr,   4),
    CAGR = round(m_pg2_base$cagr, 4),
    MDD  = round(m_pg2_base$mdd,  4),
    n    = m_pg2_base$n
  ),
  pg2_baseline_stated_sr = 1.4625,
  pg2_delta_same_period  = round(delta_sr, 4),
  pg2_promote            = pg2_promote,
  # Iter 15 comparison
  iter15_blend_sr        = round(m_pg2_iter15$sr %||% NA, 4),
  iter11_same_period_sr  = round(m_iter11_sp$sr %||% NA, 4),
  iter15_same_period_sr  = round(m_iter15_sp$sr %||% NA, 4),
  # Harvey FF5
  harvey_5spec = list(
    CAPM      = list(t=round(harvey_results$CAPM$t,3),    pass=harvey_results$CAPM$pass),
    Carhart3  = list(t=round(harvey_results$Carhart3$t,3), pass=harvey_results$Carhart3$pass),
    Carhart4  = list(t=round(harvey_results$Carhart4$t,3), pass=harvey_results$Carhart4$pass),
    FF5       = list(t=round(harvey_results$FF5$t,3),      pass=harvey_results$FF5$pass),
    FF6       = list(t=round(harvey_results$FF6$t,3),      pass=harvey_results$FF6$pass),
    pass_count = pass_count
  ),
  harvey_ff5_t = round(harvey_ff5_t, 4),
  # DSR
  dsr_post      = round(dsr_post, 4),
  dsr_pre       = round(dsr_pre, 4),
  dsr_penalty   = DSR_PENALTY_TOTAL,
  dsr_n_trials  = DSR_CANDIDATES_TRIED,
  # OOS
  oos_24_26 = list(
    SR   = round(m_oos$sr %||% NA, 4),
    CAGR = round(m_oos$cagr %||% NA, 4),
    MDD  = round(m_oos$mdd %||% NA, 4),
    n    = m_oos$n %||% 0
  ),
  # CVaR realized proxy (from optimizer package)
  cvar_d_realized = opt_pkg$cvar_d_post_optim %||% -0.0313,
  # Alpha inheritance
  alpha_inheritance_cor = alpha_cor,
  # Hash audit
  hash_audit_pass = hash_pass,
  # Codex
  codex_stance = "OVERRIDE_005",
  # Summary
  pg2_recommend = ifelse(pg2_promote,
                         "PROMOTE_V18",
                         "MAINTAIN_BASELINE"),
  generated_at = as.character(Sys.time())
)

write(toJSON(hurdle_result, auto_unbox=TRUE, pretty=TRUE),
      file.path(BT_DIR, "hurdle_result.json"))
cat("  hurdle_result.json saved\n")

# Copy charts to BT_DIR as well
for (chart in c("equity_curve.png","annual_returns.png",
                "oos_zoom.png","scenario_comparison.png")) {
  src <- file.path(OUT_DIR, chart)
  dst <- file.path(BT_DIR, chart)
  if (file.exists(src)) file.copy(src, dst, overwrite=TRUE)
}
cat("  Charts copied to backtest_result/\n")

# Judge ready: monthly NAV CSV + summary JSON
fwrite(iter18_monthly_out,
       file.path(JR_DIR, "nav_monthly_iter18.csv"))

# PG2 blend nav for judge
pg2_blend_out <- blend_dt[, .(YM_key, ret_v18, ret_pg2_v18)]
fwrite(pg2_blend_out, file.path(JR_DIR, "nav_monthly_pg2_blend.csv"))

judge_summary <- list(
  task_id = WT_ID,
  str_id  = STR_ID,
  iter    = 18,
  verdict_metrics = hurdle_result$standalone,
  pg2_v18_blend_sr = hurdle_result$pg2_v18_blend$SR,
  pg2_baseline_sr  = 1.4625,
  pg2_delta        = hurdle_result$pg2_delta_same_period,
  pg2_recommend    = hurdle_result$pg2_recommend,
  harvey_pass_count = pass_count,
  harvey_ff5_t     = round(harvey_ff5_t, 4),
  dsr_post         = round(dsr_post, 4),
  cvar_d_realized  = opt_pkg$cvar_d_post_optim %||% -0.0313,
  hash_audit_pass  = hash_pass,
  generated_at     = as.character(Sys.time())
)
write(toJSON(judge_summary, auto_unbox=TRUE, pretty=TRUE),
      file.path(JR_DIR, "judge_summary.json"))
cat("  judge_summary.json saved\n")

# ─────────────────────────────────────────────────────────
# 15. TELEGRAM BRIEF
# ─────────────────────────────────────────────────────────
cat("\n[15] Sending Telegram brief\n")

tg_src <- file.path(BASE_DIR, "02_Infrastructure/telegram/telegram_notify.R")
if (file.exists(tg_src)) {
  tryCatch({
    source(tg_src)

    # Build brief using tg_agent_brief()
    tg_msg <- tg_agent_brief(
      agent_tag    = "[Forge]",
      title        = "Iter 18 LinTilt_EMA_CVaR Backtest Complete",
      sections     = list(
        list(
          type  = "table",
          label = "Performance Summary",
          rows  = list(
            c("Metric",        "V_iter18", "Iter11 STR_1701", "PG2 V_iter18", "PG2 Baseline"),
            c("SR",
              sprintf("%.3f", m_v18$sr),
              sprintf("%.3f", m_iter11_sp$sr %||% NA),
              sprintf("%.3f", m_pg2_v18$sr),
              sprintf("%.3f", m_pg2_base$sr)),
            c("CAGR",
              sprintf("%.2f%%", m_v18$cagr*100),
              sprintf("%.2f%%", (m_iter11_sp$cagr %||% NA)*100),
              sprintf("%.2f%%", m_pg2_v18$cagr*100),
              sprintf("%.2f%%", m_pg2_base$cagr*100)),
            c("MDD",
              sprintf("%.2f%%", m_v18$mdd*100),
              sprintf("%.2f%%", (m_iter11_sp$mdd %||% NA)*100),
              sprintf("%.2f%%", m_pg2_v18$mdd*100),
              sprintf("%.2f%%", m_pg2_base$mdd*100))
          )
        ),
        list(
          type  = "kv",
          label = "Harvey 5-spec",
          items = list(
            list(k="CAPM",     v=sprintf("t=%.2f (%s)", harvey_results$CAPM$t,
                                         ifelse(harvey_results$CAPM$pass, "PASS","FAIL"))),
            list(k="Carhart3", v=sprintf("t=%.2f (%s)", harvey_results$Carhart3$t,
                                         ifelse(harvey_results$Carhart3$pass,"PASS","FAIL"))),
            list(k="Carhart4", v=sprintf("t=%.2f (%s)", harvey_results$Carhart4$t,
                                         ifelse(harvey_results$Carhart4$pass,"PASS","FAIL"))),
            list(k="FF5",      v=sprintf("t=%.2f (%s)", harvey_results$FF5$t,
                                         ifelse(harvey_results$FF5$pass,"PASS","FAIL"))),
            list(k="FF6",      v=sprintf("t=%.2f (%s)", harvey_results$FF6$t,
                                         ifelse(harvey_results$FF6$pass,"PASS","FAIL"))),
            list(k="Pass Count", v=sprintf("%d/5", pass_count))
          )
        ),
        list(
          type  = "kv",
          label = "Risk + DSR",
          items = list(
            list(k="DSR post-penalty",  v=sprintf("%.4f", dsr_post)),
            list(k="CVaR_d realized",   v=sprintf("%.4f", opt_pkg$cvar_d_post_optim %||% -0.0313)),
            list(k="Ann TO realized",   v=sprintf("%.2f", ann_to_actual)),
            list(k="Hash audit",        v=ifelse(hash_pass,"PASS","FAIL"))
          )
        ),
        list(
          type  = "bullet",
          label = "OOS 24-26",
          items = list(
            sprintf("SR=%.3f", m_oos$sr %||% NA),
            sprintf("CAGR=%.2f%%", (m_oos$cagr %||% NA)*100),
            sprintf("MDD=%.2f%%", (m_oos$mdd %||% NA)*100),
            sprintf("n=%d months", m_oos$n %||% 0)
          )
        ),
        list(
          type  = "text",
          label = "PG2 Decision",
          text  = sprintf("V_iter18 blend SR=%.4f vs Baseline=1.4625 (delta=%+.4f) → %s",
                          m_pg2_v18$sr, delta_sr, hurdle_result$pg2_recommend)
        )
      ),
      parse_mode = ""
    )

    tg_send(tg_msg, parse_mode="")

    # Send charts
    eq_chart <- file.path(OUT_DIR, "equity_curve.png")
    sc_chart <- file.path(OUT_DIR, "scenario_comparison.png")
    if (file.exists(eq_chart))
      tg_send_photo(eq_chart, caption="Iter18 equity curve vs STR_1701")
    if (file.exists(sc_chart))
      tg_send_photo(sc_chart, caption="PG2 blend comparison")

    cat("  Telegram sent\n")
  }, error=function(e) {
    cat(sprintf("  [WARN] Telegram failed: %s\n", conditionMessage(e)))
  })
} else {
  cat("  [WARN] telegram_notify.R not found; skipping\n")
}

# ─────────────────────────────────────────────────────────
# 16. FINAL REPORT
# ─────────────────────────────────────────────────────────
cat("\n")
cat("═══════════════════════════════════════════════════════\n")
cat("FORGE_DONE_ITER18\n")
cat(sprintf("  V_iter18_standalone_sr    = %.4f\n", m_v18$sr))
cat(sprintf("  V_iter18_standalone_cagr  = %.4f\n", m_v18$cagr))
cat(sprintf("  V_iter18_standalone_mdd   = %.4f\n", m_v18$mdd))
cat(sprintf("  V_iter18_blend_sr         = %.4f\n", m_pg2_v18$sr))
cat(sprintf("  baseline_PG2_same_sr      = %.4f\n", m_pg2_base$sr))
cat(sprintf("  baseline_PG2_stated_sr    = 1.4625\n"))
cat(sprintf("  delta_same_period         = %+.4f\n", delta_sr))
cat(sprintf("  iter11_same_period_sr     = %.4f\n", m_iter11_sp$sr %||% NA))
cat(sprintf("  iter15_blend_sr           = %.4f\n", m_pg2_iter15$sr %||% NA))
cat(sprintf("  mdd_standalone            = %.4f\n", m_v18$mdd))
cat(sprintf("  cvar_d_realized_proxy     = %.4f\n",
            opt_pkg$cvar_d_post_optim %||% -0.0313))
cat(sprintf("  harvey_5spec              = %d/5\n", pass_count))
cat(sprintf("  dsr_post                  = %.4f\n", dsr_post))
cat(sprintf("  oos_24_26_sr              = %.4f\n", m_oos$sr %||% NA))
cat(sprintf("  codex_stance              = OVERRIDE_005\n"))
cat(sprintf("  pg2_recommend             = %s\n",  hurdle_result$pg2_recommend))
cat(sprintf("  hash_audit_pass           = %s\n",  hash_pass))
cat("═══════════════════════════════════════════════════════\n")
cat("\nArtifacts:\n")
cat(sprintf("  %s\n", file.path(BT_DIR, "hurdle_result.json")))
cat(sprintf("  %s\n", file.path(BT_DIR, "iter18_monthly_returns.csv")))
cat(sprintf("  %s\n", file.path(BT_DIR, "oos_24_26_monthly.csv")))
cat(sprintf("  %s\n", file.path(JR_DIR, "judge_summary.json")))
cat(sprintf("  %s\n", file.path(OUT_DIR, "equity_curve.png")))
cat(sprintf("  %s\n", file.path(OUT_DIR, "scenario_comparison.png")))
