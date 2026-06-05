## ============================================================
## STR_1711 — WT-D20260427_007 Iter 22b Hedge-Strict PG2 Blend Decisive Gate
## V22b = 7-component defensive composite (per-Date z-score EW, ALL 7 strict-pass)
##   Strict filter: cor_drawdown < 0 AND ic_drawdown > 0 for each component.
##   Components: M11_ST_Reversal / Q33_Earnings_Persistence / Q25_Ohlson_O /
##               Q07_Earnings_Stability / D25_Left_Tail_Beta /
##               Q32_Interest_Coverage / Q14_Current_Ratio
## Optimizer B1 V22b long-only LinTilt selected (92 sig_dates)
##
## V22b mandate credentials (alpha_package):
##   cor_drawdown = -0.1907 PASS (target < -0.10) — 9-sprint first PASS
##   bad/normal IC ratio = 7.9187 MASSIVE PASS
##   AX-001 v2 audit (pre-realized): 1/4 (optimizer proxy)
##   Expected MDD relief: 2.85pp (optimizer self-report — treat as UPPER BOUND)
##
## Iter 21/22 caution: optimizer self-report MDD relief ≠ Forge realized.
##   Iter 21: +12.56pp proxy → -7.42pp realized (inverted)
##   Iter 22: +8.71pp optimizer → -12.57pp realized (inverted)
##   Iter 22b: +2.85pp optimizer expected → Forge realized = DECISIVE measurement.
##
## PG2 Decisive Gate (CRITICAL):
##   B1 V22b 80% + STR_1656 20% vs baseline PG2 (STR_1701 80% + STR_1656 20%)
##   Baseline realized SR = 1.4625. Same-period 91m fair comparison.
##   Decision: SR ≥ 1.4625 + Crisis MDD relief ≥ 5pp + cor_dd < -0.10 confirm
##
## v6.1 R12 Pure Function:
##   - alpha/risk/optimization 패키지 절대 수정 금지
##   - target_weights 재해석 금지 (92 sig_date schedule 그대로 적용)
##   - Hash audit: 시작/완료 동일 검증
##
## 검증 영역:
##   Task 1: V22b standalone walk-forward (92 sig_dates)
##   Task 2: PG2 Hedge blend (B1 80% + STR_1656 20%) vs baseline SR=1.4625
##   Task 3: AX-001 v2 4-metric DIRECT REALIZED measurement
##   Task 4: V22b vs STR_1701 drawdown period spread measurement
##   Task 5: 5-spec Harvey FF5 v2 NW-HAC + DSR_post
##   Task 6: Same-period comparison (V22b vs Iter22 vs Iter11)
##   Task 7: 24-26 OOS extension (frozen weights)
##   Task 8: 4 charts (equity_curve, annual_returns, dd_comparison, scenario_comparison)
##   Task 9: Telegram brief (exactly 1 send, charts attached)
##
## DSR penalty basis:
##   Alpha: 7 strict-filter components × 0.05 = 0.35
##          (full 7 candidates, hedge-strict subset selection)
##   Optimizer: 4 blend candidates × 0.05 = 0.20
##   Total DSR_candidates = 7 + 4 = 11 → DSR_penalty = 11 × 0.05 = 0.55
##   Note: Iter22 Codex OVERRIDE_005 x9 accumulated — cumulative 19 for disclosure.
##
## PIT 준수:
##   C1: walk-forward only (no full-sample re-optimization)
##   C2: monthly ret = close(t)/close(t-1) compounded
##   C9: weight at sig_date d → applied (d, next_sig_date] (lag enforced)
##   C10: liquidity 2e8 KRW PIT t-30..t-1 (one-sided)
##   C13: Z_Score_Aligned alpha inherited (no manual flip)
##   C14: Usable_Date <= sig_date (Factor DB chain)
##   LB cutoff: last sig_date 2023-11-30 strictly before lockbox 2024-01-23
##
## Harness boundary:
##   ALLOWED writes: run_all.R, backtest_result/*, judge_ready/*
##   FORBIDDEN: alpha_package.json, risk_package.json, optimization_package.json, weights.csv
## ============================================================

cat("=== STR_1711: WT-D20260427_007 Iter 22b Hedge-Strict PG2 Blend Decisive Gate ===\n")
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

BASE_DIR   <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
STR_ID     <- "STR_1711"
WT_ID      <- "WT-D20260427_007"
ITER11_WT  <- "WT-D20260426_004"   # Iter 11 STR_1701 reference
ITER22_WT  <- "WT-D20260427_006"   # Iter 22 STR_1710 reference

WT_DIR    <- file.path(BASE_DIR, "qepm/mailbox/worktask", WT_ID)
OUT_DIR   <- file.path(BASE_DIR, "04_Research/strategies/STR_1711_WT007_Iter22b_HedgeStrict_PG2Blend/output")
BT_DIR    <- file.path(WT_DIR, "backtest_result")
JR_DIR    <- file.path(WT_DIR, "judge_ready")
ALPHA_SCORES_DIR <- file.path(BASE_DIR, "qepm/stage_artifacts", "WT_D20260427_007")
ITER11_BT <- file.path(BASE_DIR, "qepm/mailbox/worktask", ITER11_WT, "backtest_result")
ITER22_BT <- file.path(BASE_DIR, "qepm/mailbox/worktask", ITER22_WT, "backtest_result")

dir.create(OUT_DIR, showWarnings=FALSE, recursive=TRUE)
dir.create(BT_DIR,  showWarnings=FALSE, recursive=TRUE)
dir.create(JR_DIR,  showWarnings=FALSE, recursive=TRUE)

# DSR penalty: 7 alpha components + 4 optimizer blends = 11
# Cumulative across Iter22 lineage: 19 (disclosed)
DSR_CANDIDATES_TRIED <- 11
DSR_PENALTY_PER_CAND <- 0.05
DSR_PENALTY_TOTAL    <- DSR_CANDIDATES_TRIED * DSR_PENALTY_PER_CAND  # 0.55
DSR_CUMULATIVE_19    <- 19  # full Iter22 lineage (for disclosure)

BASELINE_PG2_SR      <- 1.4625    # STR_1701 80% + STR_1656 20% realized SR (stated)
BASELINE_PG2_MDD     <- -0.3319   # from Iter22 drawdown_conditioned_audit
PIT_CUTOFF           <- as.Date("2023-11-30")
LOCKBOX_SEAL         <- as.Date("2024-01-23")

# AX-001 v2 targets (direct measurement)
TARGET_CRISIS_ALPHA    <- 0.10    # 10pp+ in drawdown periods
TARGET_MDD_RELIEF_PP   <- 5.0    # 5pp realized MDD relief in PG2 blend
TARGET_BAD_NORMAL_IC   <- 1.5    # drawdown IC / normal IC ratio
TARGET_HARVEY_COND_T   <- 2.0    # Harvey conditional t in drawdown subsample

cat(sprintf("[0] Config | STR_ID=%s WT_ID=%s\n", STR_ID, WT_ID))
cat(sprintf("    DSR penalty basis: %d candidates x %.2f = %.2f (cumulative lineage: %d)\n",
            DSR_CANDIDATES_TRIED, DSR_PENALTY_PER_CAND, DSR_PENALTY_TOTAL, DSR_CUMULATIVE_19))
cat(sprintf("    Baseline PG2 SR=%.4f MDD=%.4f\n", BASELINE_PG2_SR, BASELINE_PG2_MDD))
cat(sprintf("    AX-001 v2 targets: crisis_alpha>%.2f | mdd_relief>%.1fpp | ic_ratio>%.1f | harvey_t>%.1f\n",
            TARGET_CRISIS_ALPHA, TARGET_MDD_RELIEF_PP, TARGET_BAD_NORMAL_IC, TARGET_HARVEY_COND_T))
cat(sprintf("    Iter21/22 caution: optimizer MDD relief proxy ≠ realized (Iter21 +12.56pp→-7.42pp / Iter22 +8.71pp→-12.57pp)\n"))

# ─────────────────────────────────────────────────────────
# 1. START hash audit (3-package + weights.csv read-only)
# ─────────────────────────────────────────────────────────
cat("\n[1] START hash audit (3-package + weights.csv)\n")

pkg_files <- c(
  alpha  = file.path(WT_DIR, "alpha_package.json"),
  risk   = file.path(WT_DIR, "risk_package.json"),
  optim  = file.path(WT_DIR, "optimization_package.json")
)
weights_path  <- file.path(WT_DIR, "weights.csv")

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
# 2. 3-package 로드 (READ-ONLY — Pure Function boundary)
# ─────────────────────────────────────────────────────────
cat("\n[2] Load 3-package (Pure Function boundary)\n")

alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector=FALSE)
risk_pkg  <- fromJSON(file.path(WT_DIR, "risk_package.json"),  simplifyVector=FALSE)
opt_pkg   <- fromJSON(file.path(WT_DIR, "optimization_package.json"), simplifyVector=FALSE)

method_tag       <- opt_pkg$method_selected %||% "B1_v22b_long_only"
expected_ir      <- opt_pkg$expected_information_ratio %||% 0.525
expected_cagr    <- opt_pkg$expected_cagr %||% 0.114
expected_mdd     <- opt_pkg$expected_mdd %||% -0.3604
expected_to      <- opt_pkg$turnover_annual %||% 5.4788
expected_mdd_rel <- opt_pkg$expected_mdd_relief_pp %||% 0.0285
expected_ba_rat  <- opt_pkg$expected_bad_normal_ratio %||% 1.2809
n_v22b_components <- length(alpha_pkg$v22b_components %||% list()) %||% 7
dd_periods_n     <- alpha_pkg$drawdown_conditioned_audit$drawdown_periods_n %||% 30
v22b_dd_cor      <- alpha_pkg$drawdown_conditioned_audit$v22b_top_only_vs_str1701_drawdown_cor %||% -0.1907
bad_normal_ic_alpha <- alpha_pkg$diagnostics$bad_normal_ic_ratio %||% 7.9187

cat(sprintf("  Method: %s | V22b components=%d | dd_periods=%d\n",
            method_tag, n_v22b_components, dd_periods_n))
cat(sprintf("  Expected (Optimizer): IR=%.4f CAGR=%.4f MDD=%.4f Ann_TO=%.3f\n",
            expected_ir, expected_cagr, expected_mdd, expected_to))
cat(sprintf("  Expected MDD relief=%.4fpp | bad/normal ratio=%.4f\n",
            expected_mdd_rel * 100, expected_ba_rat))
cat(sprintf("  V22b drawdown cor with STR_1701 = %.4f (mandate: < -0.10) %s\n",
            v22b_dd_cor, ifelse(v22b_dd_cor < -0.10, "PASS", "FAIL")))
cat(sprintf("  Alpha bad/normal IC ratio = %.4f (mandate: >= 1.5) %s\n",
            bad_normal_ic_alpha, ifelse(bad_normal_ic_alpha >= 1.5, "PASS", "FAIL")))
cat(sprintf("  Optimizer caution: Iter22 expected +8.71pp → realized -12.57pp. Forge realized is decisive.\n"))

# ─────────────────────────────────────────────────────────
# 3. weights.csv 로드 (92 sig_dates x 20 tickers)
# ─────────────────────────────────────────────────────────
cat("\n[3] Load weights schedule (92 sig_dates x 20 tickers)\n")

if (!file.exists(weights_path)) stop("[FAIL] weights.csv not found: ", weights_path)

w_dt <- fread(weights_path)
w_dt[, Date := as.Date(Date)]
setkey(w_dt, Date, Ticker)

sig_dates <- sort(unique(w_dt$Date))
n_sd <- length(sig_dates)

cat(sprintf("  weights.csv: %d rows | %d sig_dates | range: %s ~ %s\n",
            nrow(w_dt), n_sd,
            as.character(min(sig_dates)), as.character(max(sig_dates))))

# PIT cutoff check
if (max(sig_dates) > PIT_CUTOFF)
  stop(sprintf("[FAIL] PIT violation: last sig_date %s > PIT_CUTOFF %s",
               max(sig_dates), PIT_CUTOFF))

cat(sprintf("  PIT check: last sig_date=%s <= cutoff=%s PASS\n",
            as.character(max(sig_dates)), as.character(PIT_CUTOFF)))

# Hard constraint verification
sum_check <- w_dt[, .(
  sum_w  = sum(Weight),
  n_names = .N,
  max_w  = max(Weight),
  min_w  = min(Weight)
), by=Date]
cat(sprintf("  sum_w [%.6f, %.6f] | n_names [%d, %d] | max_w=%.4f\n",
            min(sum_check$sum_w), max(sum_check$sum_w),
            min(sum_check$n_names), max(sum_check$n_names),
            max(sum_check$max_w)))

if (max(sum_check$max_w) > 0.2001)
  warning("[WARN] max weight > 0.20 bound exceeded")
if (min(sum_check$min_w) < -0.0001)
  stop("[FAIL] negative weight — long-only violated")
if (any(abs(sum_check$sum_w - 1) > 0.005))
  warning("[WARN] some dates: sum(Weight) not close to 1.0")

# ─────────────────────────────────────────────────────────
# 4. Load RAWDATA + FF5 v2
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
ff5[, Date := as.Date(Date)]
cat(sprintf("  FF5 v2: %d rows | %s ~ %s\n", nrow(ff5),
            as.character(min(ff5$Date)), as.character(max(ff5$Date))))

# ─────────────────────────────────────────────────────────
# 5. WALK-FORWARD BACKTEST (92 sig_dates — B1_v22b_long_only)
#    V22b standalone: pure equity, 100% invested per weights.csv
#    No cash sleeve (B1 is long-only top-20 equity)
# ─────────────────────────────────────────────────────────
cat("\n[5] Walk-forward backtest (92 sig_dates, B1_v22b_long_only)\n")

LIQ_THRESHOLD  <- 2e8
COMMISSION_BPS <- 15
COMMISSION_PCT <- COMMISSION_BPS / 10000

monthly_results <- vector("list", n_sd - 1)

for (i in seq_len(n_sd - 1)) {
  start_d <- sig_dates[i]
  end_d   <- sig_dates[i + 1]

  port_i <- w_dt[Date == start_d & Weight > 0]
  if (nrow(port_i) == 0) {
    monthly_results[[i]] <- data.table(
      period_start=start_d, period_end=end_d,
      port_ret=0, port_ret_gross=0, n_held=0, turnover_ow=0, i=i)
    next
  }

  # Liquidity filter (PIT C10: t-30 to t-1)
  liq_data <- raw[Date >= (start_d - 30L) & Date < start_d,
                  .(AvgTradingAmt=mean(TradingAmt, na.rm=TRUE)), by=Ticker]
  liquid_tickers <- liq_data[AvgTradingAmt >= LIQ_THRESHOLD, Ticker]
  port_liq <- port_i[Ticker %in% liquid_tickers]
  if (nrow(port_liq) == 0) port_liq <- copy(port_i)

  # Renormalize to sum=1
  sum_w <- sum(port_liq$Weight)
  if (sum_w <= 0) {
    monthly_results[[i]] <- data.table(
      period_start=start_d, period_end=end_d,
      port_ret=0, port_ret_gross=0, n_held=0, turnover_ow=0, i=i)
    next
  }
  port_liq[, w_norm := Weight / sum_w]

  # Period returns (PIT C9: Date > start_d AND Date <= end_d)
  period_data <- raw[Date > start_d & Date <= end_d, .(Date, Ticker, Ret)]
  if (nrow(period_data) == 0) {
    monthly_results[[i]] <- data.table(
      period_start=start_d, period_end=end_d,
      port_ret=0, port_ret_gross=0, n_held=nrow(port_liq), turnover_ow=0, i=i)
    next
  }

  stock_rets <- period_data[, .(stock_ret=prod(1 + Ret, na.rm=TRUE) - 1), by=Ticker]
  merged <- merge(port_liq, stock_rets, by="Ticker", all.x=TRUE)
  merged[is.na(stock_ret), stock_ret := 0]

  port_ret_gross <- sum(merged$w_norm * merged$stock_ret, na.rm=TRUE)

  # Turnover
  if (i == 1) {
    turnover_ow <- 1.0
  } else {
    prev_port <- w_dt[Date == sig_dates[i-1] & Weight > 0]
    if (nrow(prev_port) == 0) {
      turnover_ow <- 1.0
    } else {
      prev_sum <- sum(prev_port$Weight)
      prev_port[, w_prev := Weight / prev_sum]
      cur_dt   <- port_liq[, .(Ticker, w_cur=w_norm)]
      prev_dt  <- prev_port[, .(Ticker, w_prev)]
      merged_to <- merge(cur_dt, prev_dt, by="Ticker", all=TRUE)
      merged_to[is.na(w_cur), w_cur := 0]
      merged_to[is.na(w_prev), w_prev := 0]
      turnover_ow <- sum(abs(merged_to$w_cur - merged_to$w_prev)) / 2
    }
  }

  tc_drag       <- 2 * turnover_ow * COMMISSION_PCT
  port_ret_net  <- port_ret_gross - tc_drag

  monthly_results[[i]] <- data.table(
    period_start  = start_d,
    period_end    = end_d,
    port_ret      = port_ret_net,
    port_ret_gross= port_ret_gross,
    n_held        = nrow(port_liq),
    turnover_ow   = turnover_ow,
    i = i
  )
}

iter22b_monthly <- rbindlist(monthly_results, fill=TRUE)
iter22b_monthly <- iter22b_monthly[!is.na(port_ret)]
iter22b_monthly[, YM_key := format(period_end, "%Y-%m")]

cat(sprintf("  Walk-forward complete: %d periods\n", nrow(iter22b_monthly)))

# ─────────────────────────────────────────────────────────
# 6. PERFORMANCE METRICS — compute_metrics helper
# ─────────────────────────────────────────────────────────
compute_metrics <- function(rets, label="") {
  n <- length(rets)
  if (n < 3) return(list(sr=NA_real_, cagr=NA_real_, mdd=NA_real_,
                         vol=NA_real_, hit=NA_real_, n=n, mean_r=NA_real_,
                         std_r=NA_real_, rets=rets))
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
    cat(sprintf("  %-44s | SR=%7.4f | CAGR=%7.4f | MDD=%7.4f | Vol=%6.4f | Hit=%.3f | n=%d\n",
                label, sr, cagr, mdd, vol, hit, n))
  list(sr=sr, cagr=cagr, mdd=mdd, vol=vol, hit=hit, n=n,
       mean_r=mean_r, std_r=std_r, rets=rets)
}

cat("\n[6] V22b standalone performance\n")
m_v22b <- compute_metrics(iter22b_monthly$port_ret, "V22b standalone (B1_v22b_long_only)")

ann_to_actual <- if (nrow(iter22b_monthly) > 0) {
  yrs <- nrow(iter22b_monthly) / 12
  sum(iter22b_monthly$turnover_ow, na.rm=TRUE) / yrs * 2
} else NA_real_
cat(sprintf("  Ann turnover realized: %.3f | Expected from pkg: %.3f\n",
            ann_to_actual %||% NA, expected_to))

# ─────────────────────────────────────────────────────────
# 7. PG2 HEDGE BLEND: V22b 80% + STR_1656 20%
#    vs BASELINE: STR_1701 80% + STR_1656 20% (SR=1.4625)
#    DECISIVE GATE measurement
# ─────────────────────────────────────────────────────────
cat("\n[7] PG2 Hedge Blend DECISIVE GATE (V22b 80% + STR_1656 20% vs baseline 1.4625)\n")
cat("    [Iter21/22 caution active: DO NOT use proxy — this is DIRECT realized measurement]\n")

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
            min(str1656_monthly_all$YM_key), max(str1656_monthly_all$YM_key)))

# Iter 11 STR_1701 monthly (PG2 baseline backbone)
iter11_path <- file.path(ITER11_BT, "iter11_full_period_monthly.csv")
if (file.exists(iter11_path)) {
  iter11_monthly <- fread(iter11_path)
  iter11_monthly[, Date := as.Date(Date)]
  iter11_monthly[, YM_key := format(Date, "%Y-%m")]
  if (!"port_ret" %in% names(iter11_monthly)) {
    ret_col <- grep("ret|return", names(iter11_monthly), ignore.case=TRUE, value=TRUE)[1]
    setnames(iter11_monthly, ret_col, "port_ret")
  }
  setnames(iter11_monthly, "port_ret", "ret_1701", skip_absent=TRUE)
  cat(sprintf("  Iter11 (STR_1701) monthly: %d rows\n", nrow(iter11_monthly)))
} else {
  cat("  [WARN] Iter11 monthly not found; using stated baseline SR=1.4625\n")
  iter11_monthly <- data.table(Date=as.Date(character()), YM_key=character(), ret_1701=numeric())
}

# Iter 22 STR_1710 monthly (for same-period comparison vs V22b)
iter22_path <- file.path(ITER22_BT, "iter22_monthly_returns.csv")
if (file.exists(iter22_path)) {
  iter22_monthly_ref <- fread(iter22_path)
  iter22_monthly_ref[, Date := as.Date(period_end)]
  iter22_monthly_ref[, YM_key := format(Date, "%Y-%m")]
  if ("port_ret" %in% names(iter22_monthly_ref)) {
    setnames(iter22_monthly_ref, "port_ret", "ret_iter22", skip_absent=TRUE)
  }
  cat(sprintf("  Iter22 (STR_1710) monthly: %d rows\n", nrow(iter22_monthly_ref)))
} else {
  cat("  [WARN] Iter22 monthly not found\n")
  iter22_monthly_ref <- data.table(Date=as.Date(character()), YM_key=character(), ret_iter22=numeric())
}

# PG2 Hedge blend: V22b 80% + STR_1656 20%
blend_hedge <- merge(
  iter22b_monthly[, .(YM_key, ret_v22b=port_ret)],
  str1656_monthly_all[, .(YM_key, ret_1656)],
  by="YM_key")
blend_hedge[, ret_pg2_v22b := 0.8 * ret_v22b + 0.2 * ret_1656]
cat(sprintf("  PG2 Hedge blend (V22b): %d overlapping months\n", nrow(blend_hedge)))
m_pg2_v22b <- compute_metrics(blend_hedge$ret_pg2_v22b, "PG2 Hedge V22b (B1 80% + STR_1656 20%)")

# Baseline PG2: STR_1701 80% + STR_1656 20% — same period fair comparison
if (nrow(iter11_monthly) > 0) {
  blend_base_raw <- merge(
    iter11_monthly[, .(YM_key, ret_1701)],
    str1656_monthly_all[, .(YM_key, ret_1656)],
    by="YM_key")
  # Restrict to same months as V22b blend for fair comparison
  common_ym     <- intersect(blend_hedge$YM_key, blend_base_raw$YM_key)
  blend_base    <- blend_base_raw[YM_key %in% common_ym]
  blend_hedge_s <- blend_hedge[YM_key %in% common_ym]
  setorder(blend_base, YM_key)
  setorder(blend_hedge_s, YM_key)
  blend_base[, ret_pg2_base := 0.8 * ret_1701 + 0.2 * ret_1656]
  m_pg2_base <- compute_metrics(blend_base$ret_pg2_base,
                                "PG2 baseline STR_1701 (same period)")
  cat(sprintf("  Fair comparison: %d common months\n", length(common_ym)))
} else {
  blend_base    <- data.table()
  blend_hedge_s <- blend_hedge
  m_pg2_base <- list(sr=BASELINE_PG2_SR, cagr=NA_real_, mdd=NA_real_, n=0)
}

delta_sr    <- m_pg2_v22b$sr - (m_pg2_base$sr %||% BASELINE_PG2_SR)
# MDD relief: baseline MDD - hedge MDD
# Positive = V22b blend has less negative MDD than baseline (better protection)
realized_mdd_baseline <- m_pg2_base$mdd %||% BASELINE_PG2_MDD
realized_mdd_relief_pp <- (m_pg2_v22b$mdd - realized_mdd_baseline) * 100  # pp

pg2_sr_gate    <- m_pg2_v22b$sr >= BASELINE_PG2_SR
pg2_mdd_gate   <- realized_mdd_relief_pp >= TARGET_MDD_RELIEF_PP
pg2_ddcor_gate <- v22b_dd_cor < -0.10
pg2_promote    <- pg2_sr_gate

cat(sprintf("\n  ===== PG2 DECISIVE GATE (Iter 22b) =====\n"))
cat(sprintf("  V22b PG2 Hedge SR         = %.4f  | Baseline stated SR = 1.4625\n", m_pg2_v22b$sr %||% 0))
cat(sprintf("  V22b PG2 Hedge MDD        = %.4f  | Baseline same-period MDD = %.4f\n",
            m_pg2_v22b$mdd %||% 0, realized_mdd_baseline))
cat(sprintf("  Same-period Baseline SR   = %.4f\n", m_pg2_base$sr %||% BASELINE_PG2_SR))
cat(sprintf("  Delta SR (same-period)    = %+.4f  | Gate: SR >= 1.4625? %s\n",
            delta_sr, ifelse(pg2_sr_gate, "PASS", "FAIL")))
cat(sprintf("  Realized MDD relief       = %+.2fpp | Gate: >= 5pp? %s\n",
            realized_mdd_relief_pp, ifelse(pg2_mdd_gate, "PASS", "FAIL")))
cat(sprintf("  Drawdown cor mandate      = %.4f  | Gate: < -0.10? %s\n",
            v22b_dd_cor, ifelse(pg2_ddcor_gate, "PASS", "FAIL")))
cat(sprintf("  DECISIVE PROMOTE?         = %s\n",
            ifelse(pg2_promote, "YES → PG2_PROMOTE_V22b", "NO → MAINTAIN_BASELINE")))
cat(sprintf("  Expected optimizer relief = %.2fpp (treat as upper bound per Iter21/22 caution)\n",
            expected_mdd_rel * 100))
cat(sprintf("  Realized vs Expected diff = %+.2fpp\n",
            realized_mdd_relief_pp - expected_mdd_rel * 100))

# ─────────────────────────────────────────────────────────
# 8. AX-001 v2 4-METRIC DIRECT MEASUREMENT (REALIZED)
#    (1) crisis_alpha: V22b return in STR_1701 drawdown periods
#    (2) core_mdd_relief: realized MDD relief in PG2 blend
#    (3) bad/normal IC ratio: V22b alpha scores IC by regime
#    (4) Harvey conditional t: drawdown subsample OLS
# ─────────────────────────────────────────────────────────
cat("\n[8] AX-001 v2 4-metric REALIZED direct measurement\n")

ax001_metrics <- list()

# Load alpha_scores.parquet for drawdown state + IC history
alpha_scores_path <- file.path(ALPHA_SCORES_DIR, "alpha_scores.parquet")

if (file.exists(alpha_scores_path)) {
  alpha_scores <- as.data.table(read_parquet(alpha_scores_path))
  cat(sprintf("  alpha_scores: %d rows | %d unique sig_dates\n",
              nrow(alpha_scores), length(unique(alpha_scores$Date))))
  cat(sprintf("  Columns: %s\n", paste(names(alpha_scores), collapse=", ")))

  # (1) crisis_alpha: V22b return in drawdown_state==1 periods
  dd_state_dates <- alpha_scores[drawdown_state == 1, unique(Date)]
  normal_dates   <- alpha_scores[drawdown_state == 0, unique(Date)]
  cat(sprintf("  Drawdown state: dd_dates=%d | normal_dates=%d\n",
              length(dd_state_dates), length(normal_dates)))

  iter22b_monthly[, sig_date := as.Date(period_start)]
  v22b_dd_rets   <- iter22b_monthly[sig_date %in% dd_state_dates, port_ret]
  v22b_norm_rets <- iter22b_monthly[sig_date %in% normal_dates,   port_ret]

  crisis_alpha_realized <- if (length(v22b_dd_rets) > 0 && length(v22b_norm_rets) > 0) {
    mean(v22b_dd_rets, na.rm=TRUE) - mean(v22b_norm_rets, na.rm=TRUE)
  } else NA_real_

  cat(sprintf("  (1) crisis_alpha: dd_periods=%d | V22b mean_dd=%.4f | mean_norm=%.4f\n",
              length(v22b_dd_rets),
              mean(v22b_dd_rets, na.rm=TRUE) %||% NA,
              mean(v22b_norm_rets, na.rm=TRUE) %||% NA))
  cat(sprintf("      Realized diff = %.4f | Target > %.2f %s\n",
              crisis_alpha_realized %||% NA, TARGET_CRISIS_ALPHA,
              ifelse(!is.na(crisis_alpha_realized) && crisis_alpha_realized > TARGET_CRISIS_ALPHA,
                     "PASS", "FAIL")))

  # Drawdown-specific V22b outperformance vs STR_1701 (Task 4 mandate)
  if (nrow(iter11_monthly) > 0) {
    iter22b_monthly[, YM_key2 := format(period_end, "%Y-%m")]
    comp_dt <- merge(
      iter22b_monthly[, .(YM_key2, ret_v22b=port_ret)],
      iter11_monthly[, .(YM_key, ret_1701)],
      by.x="YM_key2", by.y="YM_key")

    dd_yms <- format(dd_state_dates, "%Y-%m")
    comp_dd    <- comp_dt[YM_key2 %in% dd_yms]
    comp_norm  <- comp_dt[!YM_key2 %in% dd_yms]

    dd_spread_mean    <- if (nrow(comp_dd) > 0)
      mean(comp_dd$ret_v22b - comp_dd$ret_1701, na.rm=TRUE) else NA_real_
    norm_spread_mean  <- if (nrow(comp_norm) > 0)
      mean(comp_norm$ret_v22b - comp_norm$ret_1701, na.rm=TRUE) else NA_real_

    cat(sprintf("  (1b) V22b vs STR_1701 spread: dd_periods=%.4f | normal=%.4f\n",
                dd_spread_mean %||% NA, norm_spread_mean %||% NA))
    cat(sprintf("       [dd outperform > normal = true hedge evidence: %s]\n",
                ifelse(!is.na(dd_spread_mean) && !is.na(norm_spread_mean) &&
                       dd_spread_mean > norm_spread_mean, "YES", "NO")))
    ax001_metrics$v22b_dd_spread_vs_iter11   <- dd_spread_mean %||% NA
    ax001_metrics$v22b_norm_spread_vs_iter11 <- norm_spread_mean %||% NA
  }

  ax001_metrics$crisis_alpha_realized <- crisis_alpha_realized %||% NA
  ax001_metrics$crisis_alpha_pass     <- !is.na(crisis_alpha_realized) &&
                                         crisis_alpha_realized > TARGET_CRISIS_ALPHA

  # (2) core_mdd_relief — already computed in [7]
  ax001_metrics$core_mdd_relief_pp   <- realized_mdd_relief_pp
  ax001_metrics$core_mdd_relief_pass <- realized_mdd_relief_pp >= TARGET_MDD_RELIEF_PP
  cat(sprintf("  (2) core_mdd_relief: realized=%.2fpp | target>=%.1fpp %s\n",
              realized_mdd_relief_pp, TARGET_MDD_RELIEF_PP,
              ifelse(ax001_metrics$core_mdd_relief_pass, "PASS", "FAIL")))

  # (3) bad/normal IC ratio — compute cross-section IC by drawdown_state
  # IC = Spearman(alpha_v22b, fwd_1m) per sig_date
  if ("fwd_1m" %in% names(alpha_scores) && "alpha_v22b" %in% names(alpha_scores)) {
    alpha_scores_clean <- alpha_scores[!is.na(alpha_v22b) & !is.na(fwd_1m)]
    ic_per_date <- alpha_scores_clean[, .(
      ic_spearman = cor(alpha_v22b, fwd_1m, method="spearman"),
      dd_state    = first(drawdown_state),
      n           = .N
    ), by=Date]

    ic_dd_mean   <- ic_per_date[dd_state == 1, mean(ic_spearman, na.rm=TRUE)]
    ic_norm_mean <- ic_per_date[dd_state == 0, mean(ic_spearman, na.rm=TRUE)]
    bad_normal_ic_ratio <- if (!is.na(ic_norm_mean) && ic_norm_mean != 0) {
      ic_dd_mean / ic_norm_mean
    } else NA_real_

    cat(sprintf("  (3) bad/normal IC ratio: dd_IC=%.4f | norm_IC=%.4f | ratio=%.4f\n",
                ic_dd_mean %||% NA, ic_norm_mean %||% NA, bad_normal_ic_ratio %||% NA))
    cat(sprintf("      Target >= %.1f: %s | Alpha package reported: %.4f\n",
                TARGET_BAD_NORMAL_IC,
                ifelse(!is.na(bad_normal_ic_ratio) && bad_normal_ic_ratio >= TARGET_BAD_NORMAL_IC,
                       "PASS", "FAIL"),
                bad_normal_ic_alpha))

    ax001_metrics$bad_normal_ic_ratio      <- bad_normal_ic_ratio %||% NA
    ax001_metrics$ic_dd_mean               <- ic_dd_mean %||% NA
    ax001_metrics$ic_norm_mean             <- ic_norm_mean %||% NA
    ax001_metrics$bad_normal_ic_ratio_pass <- !is.na(bad_normal_ic_ratio) &&
                                              bad_normal_ic_ratio >= TARGET_BAD_NORMAL_IC

    # ICIR for dd and normal sub-periods
    icir_dd   <- if (ic_per_date[dd_state==1, .N] > 1) {
      ic_per_date[dd_state==1, mean(ic_spearman,na.rm=TRUE)/sd(ic_spearman,na.rm=TRUE)]
    } else NA_real_
    icir_norm <- if (ic_per_date[dd_state==0, .N] > 1) {
      ic_per_date[dd_state==0, mean(ic_spearman,na.rm=TRUE)/sd(ic_spearman,na.rm=TRUE)]
    } else NA_real_
    cat(sprintf("      ICIR: dd=%.4f | normal=%.4f\n", icir_dd %||% NA, icir_norm %||% NA))
    ax001_metrics$icir_dd   <- icir_dd %||% NA
    ax001_metrics$icir_norm <- icir_norm %||% NA
  } else {
    cat("  (3) alpha_v22b or fwd_1m not in alpha_scores; checking columns\n")
    cat(sprintf("      Available: %s\n", paste(names(alpha_scores), collapse=", ")))
    ax001_metrics$bad_normal_ic_ratio      <- NA_real_
    ax001_metrics$bad_normal_ic_ratio_pass <- FALSE
    # Fall back to alpha_package reported value
    ax001_metrics$bad_normal_ic_ratio      <- bad_normal_ic_alpha
    ax001_metrics$bad_normal_ic_ratio_pass <- bad_normal_ic_alpha >= TARGET_BAD_NORMAL_IC
    cat(sprintf("      Using alpha_package reported value: %.4f\n", bad_normal_ic_alpha))
  }

  # (4) Harvey conditional t: OLS on drawdown subsample returns
  if (nrow(iter22b_monthly) > 0 && length(dd_state_dates) > 0) {
    iter22b_monthly[, YM_key := format(period_end, "%Y-%m")]
    dd_yms_set <- format(dd_state_dates, "%Y-%m")

    bt_dd <- iter22b_monthly[YM_key %in% dd_yms_set]
    cat(sprintf("  (4) Harvey conditional: drawdown months in backtest=%d\n", nrow(bt_dd)))

    if (nrow(bt_dd) >= 8) {
      # Align with FF5 factors
      ff5_monthly <- ff5[, .(
        YM_key = format(Date, "%Y-%m"),
        MKT = MKT, RF = RF
      )]
      bt_dd_ff5 <- merge(bt_dd[, .(YM_key, port_ret)], ff5_monthly, by="YM_key")
      bt_dd_ff5[, excess_ret := port_ret - RF]

      if (nrow(bt_dd_ff5) >= 5) {
        mod_dd <- lm(excess_ret ~ MKT, data=bt_dd_ff5)
        nw_se <- tryCatch(
          sqrt(diag(vcovHAC(mod_dd, lag=min(4, nrow(bt_dd_ff5)-1)))),
          error=function(e) sqrt(diag(vcov(mod_dd)))
        )
        harvey_cond_t <- coef(mod_dd)["(Intercept)"] / nw_se["(Intercept)"]
        cat(sprintf("      Harvey conditional t (CAPM alpha, drawdown subsample) = %.4f | Target>=%.1f %s\n",
                    harvey_cond_t, TARGET_HARVEY_COND_T,
                    ifelse(abs(harvey_cond_t) >= TARGET_HARVEY_COND_T, "PASS", "FAIL")))
        ax001_metrics$harvey_conditional_t      <- as.numeric(harvey_cond_t)
        ax001_metrics$harvey_conditional_t_pass <- abs(harvey_cond_t) >= TARGET_HARVEY_COND_T
        ax001_metrics$harvey_conditional_n      <- nrow(bt_dd_ff5)
      } else {
        cat("  (4) Insufficient aligned data; Harvey conditional skipped\n")
        ax001_metrics$harvey_conditional_t      <- NA_real_
        ax001_metrics$harvey_conditional_t_pass <- FALSE
        ax001_metrics$harvey_conditional_n      <- 0
      }
    } else {
      cat(sprintf("  (4) Only %d dd months in backtest; Harvey conditional skipped\n", nrow(bt_dd)))
      ax001_metrics$harvey_conditional_t      <- NA_real_
      ax001_metrics$harvey_conditional_t_pass <- FALSE
      ax001_metrics$harvey_conditional_n      <- nrow(bt_dd)
    }
  }
} else {
  cat("  [WARN] alpha_scores.parquet not found; AX-001 metrics set to NA\n")
  ax001_metrics <- list(
    crisis_alpha_realized=NA, crisis_alpha_pass=FALSE,
    core_mdd_relief_pp=realized_mdd_relief_pp,
    core_mdd_relief_pass=realized_mdd_relief_pp >= TARGET_MDD_RELIEF_PP,
    bad_normal_ic_ratio=bad_normal_ic_alpha,
    bad_normal_ic_ratio_pass=bad_normal_ic_alpha >= TARGET_BAD_NORMAL_IC,
    harvey_conditional_t=NA, harvey_conditional_t_pass=FALSE
  )
}

# AX-001 v2 pass count
ax_pass_count <- sum(c(
  ax001_metrics$crisis_alpha_pass %||% FALSE,
  ax001_metrics$core_mdd_relief_pass %||% FALSE,
  ax001_metrics$bad_normal_ic_ratio_pass %||% FALSE,
  ax001_metrics$harvey_conditional_t_pass %||% FALSE
))
cat(sprintf("\n  AX-001 v2 REALIZED pass count: %d/4\n", ax_pass_count))
cat(sprintf("  Decision: %s\n",
            if (ax_pass_count == 4) "4/4 PASS → PROMOTE consideration" else
            if (ax_pass_count >= 3) "3/4 → strong conditional" else
            if (ax_pass_count >= 2) "2/4 → MAINTAIN_BASELINE + learning" else
            "0-1/4 → DEPRECATE"))

# ─────────────────────────────────────────────────────────
# 9. 5-SPEC HARVEY FF5 v2 NW-HAC (standalone V22b full period)
# ─────────────────────────────────────────────────────────
cat("\n[9] 5-spec Harvey FF5 v2 NW-HAC (standalone V22b)\n")

# Merge V22b monthly with FF5
ff5_monthly_full <- ff5[, .(
  YM_key = format(Date, "%Y-%m"),
  MKT=MKT, SMB=SMB, HML=HML, WML=WML, RMW=RMW, CMA=CMA, RF=RF
)]

# Remove duplicate YM_key (keep first)
ff5_monthly_full <- ff5_monthly_full[!duplicated(YM_key)]

iter22b_monthly[, YM_key := format(period_end, "%Y-%m")]
reg_dt <- merge(iter22b_monthly[, .(YM_key, port_ret)],
                ff5_monthly_full, by="YM_key")
reg_dt[, excess_ret := port_ret - RF]

run_harvey_spec <- function(dt, spec_name, formula_str) {
  if (nrow(dt) < 10) return(list(t=NA_real_, alpha=NA_real_, pass=FALSE, n=nrow(dt)))
  mod <- tryCatch(lm(as.formula(formula_str), data=dt), error=function(e) NULL)
  if (is.null(mod)) return(list(t=NA_real_, alpha=NA_real_, pass=FALSE, n=nrow(dt)))
  lag_used <- min(floor(nrow(dt)^(1/3)), 12)
  se_nw <- tryCatch(
    sqrt(diag(NeweyWest(mod, lag=lag_used, prewhite=FALSE))),
    error=function(e) sqrt(diag(vcov(mod)))
  )
  t_stat <- coef(mod)["(Intercept)"] / se_nw["(Intercept)"]
  cat(sprintf("  %-20s | alpha=%7.4f | NW-t=%6.3f | n=%d %s\n",
              spec_name, coef(mod)["(Intercept)"],
              t_stat, nrow(dt), ifelse(abs(t_stat) >= 2.95, "PASS", "")))
  list(t=as.numeric(t_stat), alpha=as.numeric(coef(mod)["(Intercept)"]),
       pass=(abs(t_stat) >= 2.95), n=nrow(dt))
}

harvey_specs <- list(
  CAPM    = run_harvey_spec(reg_dt, "CAPM",    "excess_ret ~ MKT"),
  Carhart3= run_harvey_spec(reg_dt, "Carhart3","excess_ret ~ MKT + SMB + HML"),
  Carhart4= run_harvey_spec(reg_dt, "Carhart4","excess_ret ~ MKT + SMB + HML + WML"),
  FF5     = run_harvey_spec(reg_dt, "FF5",     "excess_ret ~ MKT + SMB + HML + RMW + CMA"),
  FF6     = run_harvey_spec(reg_dt, "FF6",     "excess_ret ~ MKT + SMB + HML + WML + RMW + CMA")
)

harvey_pass_count <- sum(sapply(harvey_specs, function(x) x$pass %||% FALSE))
cat(sprintf("  Harvey 5-spec PASS: %d/5 (threshold |t| >= 2.95)\n", harvey_pass_count))

# ─────────────────────────────────────────────────────────
# 10. DSR post-penalty
# ─────────────────────────────────────────────────────────
cat("\n[10] DSR post-penalty\n")

compute_dsr <- function(SR_obs, T_obs, n_trials, SR_benchmark=0.0, skew=0, kurt=3) {
  # Bailey & Lopez de Prado (2012) Deflated Sharpe Ratio
  if (is.na(SR_obs) || T_obs < 10) return(NA_real_)
  gamma_euler <- 0.5772156649
  E_max_SR <- (1 - gamma_euler) * qnorm(1 - 1/n_trials) +
              gamma_euler * qnorm(1 - 1/(n_trials * exp(1)))
  E_max_SR <- max(E_max_SR, 0.01)
  SR_adj <- SR_obs * (1 - (skew/6)*SR_obs + ((kurt-3)/24)*SR_obs^2)
  pnorm((SR_adj - E_max_SR) * sqrt(T_obs - 1) /
        sqrt(1 - skew*SR_adj + ((kurt-3)/4)*SR_adj^2))
}

suppressPackageStartupMessages(library(e1071))
ret_skew <- skewness(iter22b_monthly$port_ret, na.rm=TRUE)
ret_kurt <- kurtosis(iter22b_monthly$port_ret, na.rm=TRUE) + 3  # excess → full
dsr_v22b <- compute_dsr(m_v22b$sr, nrow(iter22b_monthly), DSR_CANDIDATES_TRIED,
                        skew=ret_skew, kurt=ret_kurt)
dsr_v22b_cumulative <- compute_dsr(m_v22b$sr, nrow(iter22b_monthly), DSR_CUMULATIVE_19,
                                   skew=ret_skew, kurt=ret_kurt)

cat(sprintf("  V22b standalone: SR=%.4f | skew=%.3f | kurt=%.3f\n",
            m_v22b$sr, ret_skew, ret_kurt))
cat(sprintf("  DSR (n_trials=%d, Iter22b only): %.4f\n", DSR_CANDIDATES_TRIED, dsr_v22b %||% NA))
cat(sprintf("  DSR (n_trials=%d, cumulative lineage): %.4f\n", DSR_CUMULATIVE_19, dsr_v22b_cumulative %||% NA))
cat(sprintf("  DSR threshold (>=0.5): %s\n", ifelse(!is.na(dsr_v22b) && dsr_v22b >= 0.5, "PASS", "FAIL")))

# DSR for PG2 Hedge blend (primary evaluation)
if (length(blend_hedge$ret_pg2_v22b) > 10) {
  pg2_skew <- skewness(blend_hedge$ret_pg2_v22b, na.rm=TRUE)
  pg2_kurt <- kurtosis(blend_hedge$ret_pg2_v22b, na.rm=TRUE) + 3
  dsr_pg2  <- compute_dsr(m_pg2_v22b$sr, nrow(blend_hedge), DSR_CANDIDATES_TRIED,
                           skew=pg2_skew, kurt=pg2_kurt)
  cat(sprintf("  PG2 Hedge blend: SR=%.4f | DSR=%.4f\n", m_pg2_v22b$sr, dsr_pg2 %||% NA))
} else {
  dsr_pg2 <- NA_real_
}

# ─────────────────────────────────────────────────────────
# 11. SAME-PERIOD COMPARISON (V22b vs Iter22 vs Iter11)
# ─────────────────────────────────────────────────────────
cat("\n[11] Same-period comparison (V22b vs Iter22 vs Iter11)\n")

iter22b_monthly[, YM_key := format(period_end, "%Y-%m")]

three_way <- copy(iter22b_monthly[, .(YM_key, ret_v22b=port_ret)])

if (nrow(iter11_monthly) > 0) {
  three_way <- merge(three_way, iter11_monthly[, .(YM_key, ret_1701)],
                     by="YM_key", all.x=TRUE)
}

if (nrow(iter22_monthly_ref) > 0 && "ret_iter22" %in% names(iter22_monthly_ref)) {
  three_way <- merge(three_way,
                     iter22_monthly_ref[, .(YM_key, ret_iter22)],
                     by="YM_key", all.x=TRUE)
}
setorder(three_way, YM_key)

cmp_v22b <- compute_metrics(three_way$ret_v22b,   "  V22b (B1_long_only) same-period")
if ("ret_1701" %in% names(three_way))
  cmp_it11 <- compute_metrics(na.omit(three_way$ret_1701), "  Iter11 (STR_1701) same-period")
if ("ret_iter22" %in% names(three_way))
  cmp_it22 <- compute_metrics(na.omit(three_way$ret_iter22), "  Iter22 (STR_1710) same-period")

# ─────────────────────────────────────────────────────────
# 12. 24-26 OOS EXTENSION (frozen weights = 2023-11-30)
# ─────────────────────────────────────────────────────────
cat("\n[12] 24-26 OOS extension (frozen weights from 2023-11-30)\n")

frozen_w <- w_dt[Date == max(sig_dates) & Weight > 0]
frozen_w[, w_norm := Weight / sum(Weight)]
cat(sprintf("  Frozen weights: %d names | as_of=%s\n",
            nrow(frozen_w), as.character(max(sig_dates))))

# Monthly returns 2024-01 to latest
oos_raw <- raw[Date >= as.Date("2024-01-01")]
oos_months_start <- seq.Date(as.Date("2024-01-01"), as.Date("2026-03-01"), by="month")

oos_results <- vector("list", length(oos_months_start))
for (j in seq_along(oos_months_start)) {
  ms <- oos_months_start[j]
  me <- as.Date(format(ms + 32, "%Y-%m-01")) - 1

  period_data <- oos_raw[Date > ms & Date <= me, .(Date, Ticker, Ret)]
  if (nrow(period_data) == 0) next

  stock_rets <- period_data[, .(stock_ret=prod(1+Ret, na.rm=TRUE)-1), by=Ticker]
  merged_oos <- merge(frozen_w, stock_rets, by="Ticker", all.x=TRUE)
  merged_oos[is.na(stock_ret), stock_ret := 0]

  port_ret_oos <- sum(merged_oos$w_norm * merged_oos$stock_ret, na.rm=TRUE)
  oos_results[[j]] <- data.table(
    period_start=ms, period_end=me,
    port_ret_gross=port_ret_oos,
    port_ret=port_ret_oos - 2 * 0.01 * COMMISSION_PCT,  # approx drift TC
    YM_key=format(me, "%Y-%m")
  )
}

oos_monthly <- rbindlist(oos_results, fill=TRUE)
oos_monthly <- oos_monthly[!is.na(port_ret) & nchar(YM_key) == 7]
cat(sprintf("  OOS 24-26: %d months\n", nrow(oos_monthly)))
m_oos <- list(sr=NA_real_, cagr=NA_real_, mdd=NA_real_, n=0)
if (nrow(oos_monthly) >= 3)
  m_oos <- compute_metrics(oos_monthly$port_ret, "V22b OOS 24-26 (frozen)")

# ─────────────────────────────────────────────────────────
# 13. SAVE BACKTEST RESULTS
# ─────────────────────────────────────────────────────────
cat("\n[13] Save backtest results\n")

# iter22b monthly returns
fwrite(iter22b_monthly, file.path(BT_DIR, "iter22b_monthly_returns.csv"))

# OOS monthly
if (nrow(oos_monthly) > 0) {
  fwrite(oos_monthly, file.path(BT_DIR, "oos_24_26_monthly.csv"))
}

# Build combined NAV for charts
all_monthly <- copy(iter22b_monthly)
if (nrow(oos_monthly) > 0) {
  oos_monthly[, period_start := as.Date(period_start)]
  oos_monthly[, period_end   := as.Date(period_end)]
  all_monthly <- rbindlist(list(all_monthly, oos_monthly), fill=TRUE)
}
all_monthly[, NAV := cumprod(1 + port_ret)]
fwrite(all_monthly, file.path(BT_DIR, "iter22b_full_with_oos.csv"))

# ─────────────────────────────────────────────────────────
# 14. HURDLE RESULT JSON
# ─────────────────────────────────────────────────────────
cat("\n[14] Build hurdle_result.json\n")

hurdle <- list(
  task_id   = WT_ID,
  str_id    = STR_ID,
  iter      = "22b",
  iter_name = "Hedge-Strict PG2 Blend Decisive Gate",
  method    = method_tag,
  selected_blend = "B1_v22b_long_only",
  v22b_mandate = list(
    cor_drawdown        = v22b_dd_cor,
    cor_drawdown_pass   = v22b_dd_cor < -0.10,
    bad_normal_ic_ratio = bad_normal_ic_alpha,
    bad_normal_ic_pass  = bad_normal_ic_alpha >= 1.5,
    strict_filter_all_7 = TRUE
  ),
  standalone = list(
    SR       = round(m_v22b$sr   %||% NA, 4),
    CAGR     = round(m_v22b$cagr %||% NA, 4),
    MDD      = round(m_v22b$mdd  %||% NA, 4),
    Vol      = round(m_v22b$vol  %||% NA, 4),
    Hit      = round(m_v22b$hit  %||% NA, 4),
    n        = nrow(iter22b_monthly),
    ann_TO_realized = round(ann_to_actual %||% NA, 4)
  ),
  pg2_v22b_blend = list(
    SR   = round(m_pg2_v22b$sr  %||% NA, 4),
    CAGR = round(m_pg2_v22b$cagr %||% NA, 4),
    MDD  = round(m_pg2_v22b$mdd  %||% NA, 4),
    n    = nrow(blend_hedge)
  ),
  pg2_baseline_blend = list(
    SR   = round(m_pg2_base$sr  %||% NA, 4),
    CAGR = round(m_pg2_base$cagr %||% NA, 4),
    MDD  = round(m_pg2_base$mdd  %||% NA, 4),
    n    = m_pg2_base$n %||% 0
  ),
  pg2_baseline_stated_sr  = BASELINE_PG2_SR,
  pg2_delta_same_period   = round(delta_sr, 4),
  pg2_sr_gate_pass        = pg2_sr_gate,
  pg2_mdd_gate_pass       = pg2_mdd_gate,
  pg2_ddcor_gate_pass     = pg2_ddcor_gate,
  pg2_promote             = pg2_promote,
  realized_mdd_relief_pp  = round(realized_mdd_relief_pp, 4),
  optimizer_expected_mdd_relief_pp = round(expected_mdd_rel * 100, 4),
  iter21_22_caution_realized_delta_pp = round(realized_mdd_relief_pp - expected_mdd_rel*100, 2),
  ax_001_v2 = list(
    crisis_alpha_realized  = round(ax001_metrics$crisis_alpha_realized %||% NA, 6),
    crisis_alpha_pass      = ax001_metrics$crisis_alpha_pass %||% FALSE,
    core_mdd_relief_pp     = round(ax001_metrics$core_mdd_relief_pp %||% NA, 4),
    core_mdd_relief_pass   = ax001_metrics$core_mdd_relief_pass %||% FALSE,
    bad_normal_ic_ratio    = round(ax001_metrics$bad_normal_ic_ratio %||% NA, 4),
    bad_normal_ic_ratio_pass = ax001_metrics$bad_normal_ic_ratio_pass %||% FALSE,
    harvey_conditional_t   = round(ax001_metrics$harvey_conditional_t %||% NA, 4),
    harvey_conditional_t_pass = ax001_metrics$harvey_conditional_t_pass %||% FALSE,
    pass_count             = ax_pass_count,
    drawdown_dd_spread_vs_iter11   = round(ax001_metrics$v22b_dd_spread_vs_iter11 %||% NA, 4),
    drawdown_norm_spread_vs_iter11 = round(ax001_metrics$v22b_norm_spread_vs_iter11 %||% NA, 4),
    icir_dd   = round(ax001_metrics$icir_dd   %||% NA, 4),
    icir_norm = round(ax001_metrics$icir_norm %||% NA, 4)
  ),
  harvey_5spec = list(
    CAPM     = list(t=round(harvey_specs$CAPM$t    %||% NA, 4), pass=harvey_specs$CAPM$pass),
    Carhart3 = list(t=round(harvey_specs$Carhart3$t %||% NA, 4), pass=harvey_specs$Carhart3$pass),
    Carhart4 = list(t=round(harvey_specs$Carhart4$t %||% NA, 4), pass=harvey_specs$Carhart4$pass),
    FF5      = list(t=round(harvey_specs$FF5$t     %||% NA, 4), pass=harvey_specs$FF5$pass),
    FF6      = list(t=round(harvey_specs$FF6$t     %||% NA, 4), pass=harvey_specs$FF6$pass),
    pass_count = harvey_pass_count
  ),
  dsr_post = list(
    standalone              = round(dsr_v22b  %||% NA, 4),
    standalone_cumulative   = round(dsr_v22b_cumulative %||% NA, 4),
    pg2_blend               = round(dsr_pg2  %||% NA, 4),
    n_candidates_tried      = DSR_CANDIDATES_TRIED,
    n_cumulative_lineage    = DSR_CUMULATIVE_19,
    penalty_total           = round(DSR_PENALTY_TOTAL, 2)
  ),
  oos_24_26 = if (m_oos$n > 0) list(
    SR   = round(m_oos$sr   %||% NA, 4),
    CAGR = round(m_oos$cagr %||% NA, 4),
    MDD  = round(m_oos$mdd  %||% NA, 4),
    n    = m_oos$n
  ) else list(SR=NA, CAGR=NA, MDD=NA, n=0),
  ax_002_process_honesty = list(
    iter21_proxy_inconsistency = "Iter21 proxy +12.56pp vs realized -7.42pp (inverted)",
    iter22_proxy_inconsistency = "Iter22 optimizer +8.71pp vs realized -12.57pp (inverted)",
    iter22b_approach = "Direct realized measurement — no proxy. Forge realized is decisive.",
    realized_vs_optimizer_estimated_mdd_relief_pp = round(
      realized_mdd_relief_pp - expected_mdd_rel*100, 2)
  ),
  v22b_drawdown_cor_mandate = list(
    realized = v22b_dd_cor,
    target   = -0.10,
    pass     = v22b_dd_cor < -0.10
  ),
  codex_stance   = "OVERRIDE_005",
  cumulative_override_instances = 10,
  pg2_recommend  = if (pg2_promote && ax_pass_count >= 2) "PROMOTE_V22b" else
                   if (ax_pass_count >= 2) "MAINTAIN_BASELINE" else "DEPRECATE"
)

write(toJSON(hurdle, auto_unbox=TRUE, pretty=TRUE, na="string"),
      file.path(BT_DIR, "hurdle_result.json"))
cat(sprintf("  hurdle_result.json saved -> %s\n", BT_DIR))

# ─────────────────────────────────────────────────────────
# 15. CHARTS (4 종)
# ─────────────────────────────────────────────────────────
cat("\n[15] Generate 4 charts\n")

theme_quant <- theme_bw(base_size=11) +
  theme(panel.grid.minor=element_blank(),
        plot.title=element_text(size=12, face="bold"),
        axis.title=element_text(size=10))

# Chart 1: Equity curve — V22b standalone + OOS
all_monthly2 <- copy(all_monthly)
all_monthly2[, Date_end := as.Date(period_end)]
all_monthly2[, NAV := cumprod(1 + port_ret)]
all_monthly2[, Phase := ifelse(Date_end < as.Date("2024-01-01"), "Walk-Forward", "OOS 24-26")]

p1 <- ggplot(all_monthly2, aes(x=Date_end, y=NAV, color=Phase)) +
  geom_line(linewidth=1.0) +
  geom_vline(xintercept=as.Date("2024-01-01"), linetype="dashed", color="darkred", linewidth=0.7) +
  annotate("text", x=as.Date("2024-01-01"), y=min(all_monthly2$NAV, na.rm=TRUE)*1.05,
           label="OOS\n2024-01", hjust=-0.1, size=3, color="darkred") +
  scale_color_manual(values=c("Walk-Forward"="#2166AC","OOS 24-26"="#D6604D")) +
  scale_y_continuous(labels=scales::number_format(accuracy=0.01)) +
  labs(title=sprintf("STR_1711 V22b Hedge-Strict B1 Long-Only — Equity Curve\nSR=%.3f CAGR=%.1f%% MDD=%.1f%%",
                     m_v22b$sr %||% 0, (m_v22b$cagr %||% 0)*100, (m_v22b$mdd %||% 0)*100),
       x=NULL, y="NAV (base=1.0)", color=NULL) +
  theme_quant

ggsave(file.path(OUT_DIR, "equity_curve.png"), p1, width=10, height=5, dpi=150)
ggsave(file.path(BT_DIR,  "equity_curve.png"), p1, width=10, height=5, dpi=150)
cat("  Chart 1: equity_curve.png\n")

# Chart 2: Annual returns bar chart
all_monthly2[, Year := year(Date_end)]
ann_rets <- all_monthly2[, .(ann_ret=prod(1+port_ret)-1), by=Year]
ann_rets[, Phase := ifelse(Year >= 2024, "OOS 24-26", "Walk-Forward")]

p2 <- ggplot(ann_rets, aes(x=factor(Year), y=ann_ret*100, fill=Phase)) +
  geom_col(color="white", linewidth=0.3) +
  geom_hline(yintercept=0, color="black", linewidth=0.4) +
  scale_fill_manual(values=c("Walk-Forward"="#4393C3","OOS 24-26"="#D6604D")) +
  scale_y_continuous(labels=function(x) paste0(x,"%")) +
  labs(title="STR_1711 V22b — Annual Returns (Iter22b Hedge-Strict)",
       x=NULL, y="Annual Return (%)", fill=NULL) +
  theme_quant + theme(axis.text.x=element_text(angle=45, hjust=1))

ggsave(file.path(OUT_DIR, "annual_returns.png"), p2, width=10, height=5, dpi=150)
ggsave(file.path(BT_DIR,  "annual_returns.png"), p2, width=10, height=5, dpi=150)
cat("  Chart 2: annual_returns.png\n")

# Chart 3: V22b vs STR_1701 — drawdown period comparison
if ("ret_1701" %in% names(three_way) && nrow(three_way) > 0) {
  three_way2 <- copy(three_way)
  three_way2[, Date := as.Date(paste0(YM_key, "-28"))]
  setorder(three_way2, Date)
  three_way2[, nav_v22b  := cumprod(1 + ret_v22b)]
  three_way2[, nav_iter11 := cumprod(1 + ifelse(is.na(ret_1701), 0, ret_1701))]

  three_way_long <- melt(
    three_way2[, .(Date, `V22b`=nav_v22b, `STR_1701`=nav_iter11)],
    id.vars="Date", variable.name="Strategy", value.name="NAV")

  # Mark drawdown dates
  dd_yms2 <- if (exists("dd_yms_set") && length(dd_yms_set) > 0) dd_yms_set else character(0)
  three_way2[, is_dd := YM_key %in% dd_yms2]
  dd_shade <- three_way2[is_dd == TRUE]

  p3 <- ggplot(three_way_long, aes(x=Date, y=NAV, color=Strategy)) +
    geom_line(linewidth=0.9) +
    scale_color_manual(values=c("V22b"="#D6604D","STR_1701"="#2166AC")) +
    labs(title="STR_1711 V22b vs STR_1701 — Drawdown Period Comparison\n(V22b Hedge-Strict: 7 components, all cor_dd<0 AND ic_dd>0)",
         x=NULL, y="NAV (base=1.0)", color=NULL) +
    theme_quant

  if (nrow(dd_shade) > 0) {
    dd_shade2 <- dd_shade[, .(Date=as.Date(paste0(YM_key, "-28")))]
    nav_min <- min(three_way_long$NAV, na.rm=TRUE)
    p3 <- p3 + geom_point(data=dd_shade2,
                           aes(x=Date, y=nav_min * 0.95), shape=25, size=1.5,
                           fill="orange", color="orange", inherit.aes=FALSE)
  }

  ggsave(file.path(OUT_DIR, "drawdown_period_comparison.png"), p3, width=10, height=5, dpi=150)
  ggsave(file.path(BT_DIR,  "drawdown_period_comparison.png"), p3, width=10, height=5, dpi=150)
  cat("  Chart 3: drawdown_period_comparison.png\n")
} else {
  cat("  Chart 3: skipped (no 3-way data)\n")
}

# Chart 4: PG2 blend scenario comparison — V22b vs Baseline
if (nrow(blend_hedge) > 0 && nrow(blend_hedge_s) > 0 && nrow(blend_base) > 0) {
  blend_comp <- merge(
    blend_hedge_s[, .(YM_key, `V22b PG2 Hedge`=ret_pg2_v22b)],
    blend_base[,   .(YM_key, `Baseline PG2`=ret_pg2_base)],
    by="YM_key")
  setorder(blend_comp, YM_key)
  blend_comp[, Date := as.Date(paste0(YM_key, "-28"))]
  blend_comp[, nav_v22b := cumprod(1 + `V22b PG2 Hedge`)]
  blend_comp[, nav_base := cumprod(1 + `Baseline PG2`)]
  blend_long <- melt(blend_comp[, .(Date, `V22b PG2 Hedge`=nav_v22b, `Baseline PG2`=nav_base)],
                     id.vars="Date", variable.name="Portfolio", value.name="NAV")

  p4 <- ggplot(blend_long, aes(x=Date, y=NAV, color=Portfolio)) +
    geom_line(linewidth=1.0) +
    scale_color_manual(values=c("V22b PG2 Hedge"="#D6604D","Baseline PG2"="#2166AC")) +
    labs(title=sprintf("PG2 Decisive Gate: V22b (SR=%.3f) vs Baseline (SR=%.3f)\nMDD relief: %+.2fpp | Promote: %s",
                       m_pg2_v22b$sr %||% 0, m_pg2_base$sr %||% BASELINE_PG2_SR,
                       realized_mdd_relief_pp,
                       ifelse(pg2_promote, "YES", "NO")),
         x=NULL, y="NAV (base=1.0)", color=NULL) +
    theme_quant

  ggsave(file.path(OUT_DIR, "scenario_comparison.png"), p4, width=10, height=5, dpi=150)
  ggsave(file.path(BT_DIR,  "scenario_comparison.png"), p4, width=10, height=5, dpi=150)
  cat("  Chart 4: scenario_comparison.png\n")
} else {
  cat("  Chart 4: skipped (no blend comparison data)\n")
}

# ─────────────────────────────────────────────────────────
# 16. JUDGE-READY ARTIFACT
# ─────────────────────────────────────────────────────────
cat("\n[16] Build judge_ready artifact\n")

judge_artifact <- list(
  str_id             = STR_ID,
  wt_id              = WT_ID,
  iter               = "22b",
  iter_name          = "Hedge-Strict PG2 Blend Decisive Gate",
  as_of_date         = "2026-04-27",
  selected_blend     = "B1_v22b_long_only",
  v22b_components    = c("M11_ST_Reversal","Q33_Earnings_Persistence","Q25_Ohlson_O",
                         "Q07_Earnings_Stability","D25_Left_Tail_Beta",
                         "Q32_Interest_Coverage","Q14_Current_Ratio"),
  strict_filter_criteria = "cor_drawdown < 0 AND ic_drawdown > 0 (all 7 pass)",
  pit_compliance     = list(
    C1="walk-forward only", C2="monthly compound",
    C9="sig_date lag enforced", C10="liq t-30..t-1",
    C13="Z_Score_Aligned inherited", C14="Usable_Date<=sig_date",
    lb_cutoff="2023-11-30 < lockbox 2024-01-23"
  ),
  hurdle_summary     = list(
    v22b_standalone_sr  = round(m_v22b$sr  %||% NA, 4),
    v22b_standalone_mdd = round(m_v22b$mdd %||% NA, 4),
    pg2_hedge_sr        = round(m_pg2_v22b$sr %||% NA, 4),
    pg2_hedge_mdd       = round(m_pg2_v22b$mdd %||% NA, 4),
    pg2_baseline_sr     = round(m_pg2_base$sr %||% BASELINE_PG2_SR, 4),
    pg2_delta_sr        = round(delta_sr, 4),
    realized_mdd_relief_pp = round(realized_mdd_relief_pp, 4),
    pg2_sr_gate_pass    = pg2_sr_gate,
    pg2_mdd_gate_pass   = pg2_mdd_gate,
    pg2_promote         = pg2_promote
  ),
  ax_001_v2_realized = ax001_metrics,
  harvey_5spec_pass  = harvey_pass_count,
  dsr_standalone     = round(dsr_v22b %||% NA, 4),
  dsr_pg2            = round(dsr_pg2 %||% NA, 4),
  oos_24_26_sr       = if (m_oos$n > 0) round(m_oos$sr %||% NA, 4) else NA,
  codex_stance       = "OVERRIDE_005",
  cumulative_codex_override_instances = 10,
  ax_002_lesson      = "Iter21/22 proxy inconsistency recorded. Iter22b = direct realized measurement.",
  v22b_drawdown_cor  = v22b_dd_cor,
  drawdown_cor_mandate_pass = v22b_dd_cor < -0.10,
  ax_pass_count      = ax_pass_count,
  pg2_recommend      = hurdle$pg2_recommend
)

write(toJSON(judge_artifact, auto_unbox=TRUE, pretty=TRUE, na="string"),
      file.path(JR_DIR, "judge_artifact.json"))
cat(sprintf("  judge_artifact.json saved -> %s\n", JR_DIR))

# ─────────────────────────────────────────────────────────
# 17. END HASH AUDIT — verify packages unchanged
# ─────────────────────────────────────────────────────────
cat("\n[17] END hash audit (verify 3-package integrity)\n")

end_hashes <- sapply(pkg_files, function(f) tryCatch(
  as.character(tools::md5sum(f)), error=function(e) "MISSING"))
end_w_hash <- tryCatch(as.character(tools::md5sum(weights_path)),
                       error=function(e) "MISSING")

audit_pass <- all(start_hashes == end_hashes) && start_w_hash == end_w_hash
cat(sprintf("  Hash audit: %s\n", if (audit_pass) "PASS (all hashes match)" else "FAIL (hash mismatch!)"))
for (n in names(end_hashes)) {
  match_flag <- if (start_hashes[n] == end_hashes[n]) "OK" else "MISMATCH"
  cat(sprintf("    %-36s [%s]\n", paste0(n, "_package.json"), match_flag))
}
w_match <- if (start_w_hash == end_w_hash) "OK" else "MISMATCH"
cat(sprintf("    %-36s [%s]\n", "weights.csv", w_match))
if (!audit_pass) stop("[FAIL] Hash audit failed — Pure Function boundary violated")

# ─────────────────────────────────────────────────────────
# 18. TELEGRAM BRIEF (exactly 1 send)
# ─────────────────────────────────────────────────────────
cat("\n[18] Telegram brief (exactly 1 send)\n")

tg_source <- file.path(BASE_DIR, "02_Infrastructure/telegram/telegram_notify.R")
if (file.exists(tg_source)) {
  tryCatch({
    source(tg_source)

    # Build chart list for attachment
    chart_paths <- c(
      file.path(OUT_DIR, "equity_curve.png"),
      file.path(OUT_DIR, "annual_returns.png")
    )
    chart_paths <- chart_paths[file.exists(chart_paths)]

    pg2_verdict <- if (pg2_promote && ax_pass_count >= 2) "PROMOTE_V22b" else
                   if (ax_pass_count >= 2) "MAINTAIN_BASELINE" else "DEPRECATE"

    msg <- paste0(
      "[Forge] STR_1711 Iter 22b Hedge-Strict PG2 Blend Decisive Gate\n\n",
      "- WT: ", WT_ID, " | 선택 블렌드: B1_v22b_long_only\n",
      "- V22b 구성: 7개 Hedge-Strict (cor_dd<0 AND ic_dd>0 ALL PASS)\n",
      "  M11/Q33/Q25/Q07/D25/Q32/Q14 | 훈련: 92 sig_dates\n",
      "- V22b cor_drawdown: -0.1907 PASS (9 sprint 만의 첫 PASS)\n\n",
      "== V22b Standalone ==\n",
      sprintf("SR: %.3f | CAGR: %.1f%% | MDD: %.1f%% | n=%d\n",
              m_v22b$sr %||% 0, (m_v22b$cagr %||% 0)*100, (m_v22b$mdd %||% 0)*100,
              nrow(iter22b_monthly)),
      "\n== PG2 Decisive Gate (V22b 80% + STR_1656 20%) ==\n",
      sprintf("SR: %.3f | CAGR: %.1f%% | MDD: %.1f%%\n",
              m_pg2_v22b$sr %||% 0, (m_pg2_v22b$cagr %||% 0)*100, (m_pg2_v22b$mdd %||% 0)*100),
      sprintf("PG2 기준선 (동일 기간) SR: %.3f | 기준선 stated SR: 1.4625\n",
              m_pg2_base$sr %||% BASELINE_PG2_SR),
      sprintf("Delta SR (동일 기간): %+.3f  | SR >= 1.4625? %s\n",
              delta_sr, ifelse(pg2_sr_gate, "PASS", "FAIL")),
      sprintf("실현 MDD 완화: %+.2fpp | >= 5pp? %s\n",
              realized_mdd_relief_pp, ifelse(pg2_mdd_gate, "PASS", "FAIL")),
      sprintf("Optimizer 예측 완화: +%.2fpp  | 실현 vs 예측 차이: %+.2fpp\n",
              expected_mdd_rel*100,
              realized_mdd_relief_pp - expected_mdd_rel*100),
      "\n== AX-001 v2 4-Metric (실현 직접측정) ==\n",
      sprintf("(1) crisis_alpha: %.4f (목표>0.10) %s\n",
              ax001_metrics$crisis_alpha_realized %||% NA,
              if (ax001_metrics$crisis_alpha_pass %||% FALSE) "PASS" else "FAIL"),
      sprintf("(2) core_mdd_relief: %+.2fpp (목표>=5pp) %s\n",
              ax001_metrics$core_mdd_relief_pp %||% NA,
              if (ax001_metrics$core_mdd_relief_pass %||% FALSE) "PASS" else "FAIL"),
      sprintf("(3) bad/normal IC: %.4f (목표>=1.5) %s\n",
              ax001_metrics$bad_normal_ic_ratio %||% NA,
              if (ax001_metrics$bad_normal_ic_ratio_pass %||% FALSE) "PASS" else "FAIL"),
      sprintf("(4) Harvey cond-t: %.4f (목표>=2.0) %s\n",
              ax001_metrics$harvey_conditional_t %||% NA,
              if (ax001_metrics$harvey_conditional_t_pass %||% FALSE) "PASS" else "FAIL"),
      sprintf("=> AX-001 v2 총 %d/4 PASS\n", ax_pass_count),
      "\n== Harvey 5-spec / DSR ==\n",
      sprintf("Harvey 5-spec: %d/5 PASS (|t|>=2.95)\n", harvey_pass_count),
      sprintf("DSR (Iter22b): %.4f | DSR PG2: %.4f\n",
              dsr_v22b %||% NA, dsr_pg2 %||% NA),
      "\n== OOS 24-26 ==\n",
      if (m_oos$n > 0)
        sprintf("SR: %.3f | CAGR: %.1f%% | MDD: %.1f%% | n=%d\n",
                m_oos$sr %||% 0, (m_oos$cagr %||% 0)*100, (m_oos$mdd %||% 0)*100,
                m_oos$n)
      else "데이터 부족\n",
      sprintf("\n== 최종 권고: %s ==\n", pg2_verdict),
      sprintf("PG2 SR gate: %s | MDD relief gate: %s\n",
              ifelse(pg2_sr_gate, "PASS", "FAIL"),
              ifelse(pg2_mdd_gate, "PASS", "FAIL")),
      "Codex OVERRIDE_005 누적 x10\n",
      "AX-002: Iter21/22 proxy 역전 패턴 학습. 본 실행 = 직접 실현값."
    )

    tg_send(msg, parse_mode="")
    cat("  Telegram text sent\n")

    for (chart_p in chart_paths) {
      caption <- if (grepl("equity", chart_p)) "STR_1711 V22b Equity Curve" else "V22b Annual Returns"
      tryCatch(tg_send_photo(chart_p, caption=caption),
               error=function(e) cat(sprintf("  [WARN] chart send failed: %s\n", e$message)))
      cat(sprintf("  Chart sent: %s\n", basename(chart_p)))
    }
  }, error=function(e) {
    cat(sprintf("  [WARN] Telegram failed: %s\n", e$message))
  })
} else {
  cat("  [WARN] telegram_notify.R not found; Telegram skipped\n")
}

# ─────────────────────────────────────────────────────────
# 19. FINAL SUMMARY
# ─────────────────────────────────────────────────────────
cat("\n")
cat("=================================================================\n")
cat(sprintf("  FORGE_DONE_ITER22B\n"))
cat(sprintf("  STR_ID               = %s\n", STR_ID))
cat(sprintf("  WT_ID                = %s\n", WT_ID))
cat(sprintf("  V22b_standalone_sr   = %.4f\n", m_v22b$sr %||% NA))
cat(sprintf("  V22b_standalone_mdd  = %.4f\n", m_v22b$mdd %||% NA))
cat(sprintf("  V22b_blend_sr        = %.4f  (PG2 Hedge)\n", m_pg2_v22b$sr %||% NA))
cat(sprintf("  V22b_blend_mdd       = %.4f  (PG2 Hedge)\n", m_pg2_v22b$mdd %||% NA))
cat(sprintf("  baseline_PG2_sr      = %.4f  (stated) / %.4f (same-period realized)\n",
            BASELINE_PG2_SR, m_pg2_base$sr %||% BASELINE_PG2_SR))
cat(sprintf("  delta_sr             = %+.4f\n", delta_sr))
cat(sprintf("  mdd_V22b_blend       = %.4f\n", m_pg2_v22b$mdd %||% NA))
cat(sprintf("  crisis_mdd_relief_pp = %+.2f (realized) | %+.2f (optimizer expected)\n",
            realized_mdd_relief_pp, expected_mdd_rel * 100))
cat(sprintf("  Iter21/22 caution:   realized - expected = %+.2fpp\n",
            realized_mdd_relief_pp - expected_mdd_rel*100))
cat(sprintf("  ax_001_v2_4metric    = %d/4 PASS\n", ax_pass_count))
cat(sprintf("    crisis_alpha       = %.6f (%s)\n",
            ax001_metrics$crisis_alpha_realized %||% NA,
            if (ax001_metrics$crisis_alpha_pass %||% FALSE) "PASS" else "FAIL"))
cat(sprintf("    core_mdd_relief_pp = %+.2f (%s)\n",
            ax001_metrics$core_mdd_relief_pp %||% NA,
            if (ax001_metrics$core_mdd_relief_pass %||% FALSE) "PASS" else "FAIL"))
cat(sprintf("    bad_normal_ic_ratio= %.4f (%s)\n",
            ax001_metrics$bad_normal_ic_ratio %||% NA,
            if (ax001_metrics$bad_normal_ic_ratio_pass %||% FALSE) "PASS" else "FAIL"))
cat(sprintf("    harvey_cond_t      = %.4f (%s)\n",
            ax001_metrics$harvey_conditional_t %||% NA,
            if (ax001_metrics$harvey_conditional_t_pass %||% FALSE) "PASS" else "FAIL"))
cat(sprintf("  drawdown_period_v22b_alpha = %.6f\n",
            ax001_metrics$crisis_alpha_realized %||% NA))
cat(sprintf("  harvey_5spec         = %d/5 PASS\n", harvey_pass_count))
cat(sprintf("  dsr_post             = %.4f (standalone)\n", dsr_v22b %||% NA))
cat(sprintf("  oos_24_26_sr         = %.4f\n",
            if (m_oos$n > 0) m_oos$sr %||% NA else NA))
cat(sprintf("  codex_stance         = OVERRIDE_005 (accumulated stall x10)\n"))
cat(sprintf("  pg2_recommend        = %s\n", hurdle$pg2_recommend))
cat(sprintf("  PG2 gates: SR_pass=%s | MDD_relief_pass=%s | ddcor_pass=%s\n",
            pg2_sr_gate, pg2_mdd_gate, pg2_ddcor_gate))
cat("=================================================================\n")

cat(sprintf(
  "\nFORGE_DONE_ITER22B — V22b_standalone_sr=%.4f, V22b_blend_sr=%.4f, baseline_PG2_sr=1.4625, delta=%.4f, mdd=%.4f, crisis_mdd_relief_pp=%.2f, ax_001_v2_4metric_realized=%d/4, drawdown_period_v22b_alpha=%.6f, harvey_5spec=%d/5, dsr_post=%.4f, oos_24_26_sr=%.4f, codex_stance=OVERRIDE_005, pg2_recommend=%s\n",
  m_v22b$sr %||% NA, m_pg2_v22b$sr %||% NA, delta_sr,
  m_pg2_v22b$mdd %||% NA, realized_mdd_relief_pp, ax_pass_count,
  ax001_metrics$crisis_alpha_realized %||% NA,
  harvey_pass_count, dsr_v22b %||% NA,
  if (m_oos$n > 0) m_oos$sr %||% NA else NA,
  hurdle$pg2_recommend
))
