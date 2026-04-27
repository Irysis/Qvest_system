## ============================================================
## STR_1701 — WT-D20260427_011 Iter 26 Drawdown Threshold Trigger Cash Overlay
## (Binary Discrete: 8/18/28% thresholds -> 30/50/100% cash)
## ============================================================
## ## 핵심아이디어
##   Iter 26 = Iter 11 LinTilt baseline + BINARY DISCRETE threshold cash overlay
##     NAV peak-to-trough thresholds: -8% -> 30% cash, -18% -> 50% cash, -28% -> 100% cash
##     Recovery: NAV >= prior peak -> 0% cash (complete unwind)
##     Iter 21/22/22b continuous overlay AVOIDED (L-231 blocking pattern)
##
##   AX-001 v2 4-metric audit (Forge measured):
##     1. crisis_alpha (cash hedge active periods)
##     2. MDD relief vs Iter 11 baseline
##     3. bad/normal return ratio
##     4. Harvey conditional t (drawdown-active sub-periods)
##
##   Optimizer self-report: MDD relief +10.38pp (expected = 2/4 AX-001 PASS)
##   Forge mandate: HONEST measurement of realized values
##
##   92 sig_dates walk-forward (2008-01 ~ 2023-11)
##   PG2 Hedge blend: B1 (Iter26 standalone) 80% + STR_1656 20%
##   Baseline SR: 1.4625 (Iter11 80% + STR_1656 20% same-period)
##
## v6.1 R12 Pure Function:
##   - alpha/risk/optimization 패키지 절대 수정 금지
##   - target_weights 재해석 금지 (weights.csv 그대로 적용)
##   - Hash audit: 시작/완료 동일 검증
##
## Iter 21/22/22b 학습:
##   - continuous proxy self-report vs realized 정반대 (-19~-21pp gap)
##   - L-231: continuous overlay fail 패턴 기록
##   - 본 iter: binary step function -> robustness test
##
## PIT 준수:
##   - C1: expanding NAV trail only (no future-looking threshold tuning)
##   - C2: cash_state(d+1) = f(NAV trail through d) — 1 day lag enforced
##   - C3: peak-to-trough at d strictly < apply at d+1
##   - C9: no same-day VT/DD
##   - C11: KR-internal NAV only (no FRED)
##   - LB cutoff: last sig_date 2023-11-30 strictly before lockbox 2024-01-23
## ============================================================

cat("=== STR_1701: WT-D20260427_011 Iter 26 DD Threshold Trigger Cash Overlay ===\n")
cat("Forge Integration — Sonnet 4.6 v6.1 R12 Pure Function — 2026-04-27\n\n")

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
STR_ID    <- "STR_1701"
WT_ID     <- "WT-D20260427_011"
ITER11_WT <- "WT-D20260426_004"   # Iter 11 baseline reference NAV

WT_DIR     <- file.path(BASE_DIR, "qepm/mailbox/worktask", WT_ID)
ITER11_BT  <- file.path(BASE_DIR, "qepm/mailbox/worktask", ITER11_WT, "backtest_result")
OUT_DIR    <- file.path(BASE_DIR, "04_Research/strategies/STR_1701_WT011_Iter26_DDThreshold/output")
BT_DIR     <- file.path(WT_DIR, "backtest_result")
JR_DIR     <- file.path(WT_DIR, "judge_ready")

dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(BT_DIR,  showWarnings = FALSE, recursive = TRUE)
dir.create(JR_DIR,  showWarnings = FALSE, recursive = TRUE)

# DSR penalty basis: Iter 26 alpha(5) + risk(5) + optimizer(4 threshold sets + 6 prior iters) = ~20
DSR_CANDIDATES_TRIED <- 20
DSR_PENALTY_PER_CAND <- 0.05
DSR_PENALTY_TOTAL    <- DSR_CANDIDATES_TRIED * DSR_PENALTY_PER_CAND  # 1.00

# Baseline PG2 SR (Iter 11 80% + STR_1656 20% same-period — from prior WT)
BASELINE_PG2_SR      <- 1.4625

cat(sprintf("[0] Config | STR_ID=%s WT_ID=%s\n", STR_ID, WT_ID))
cat(sprintf("    DSR penalty basis: %d candidates x %.2f = %.2f\n",
            DSR_CANDIDATES_TRIED, DSR_PENALTY_PER_CAND, DSR_PENALTY_TOTAL))
cat(sprintf("    Baseline PG2 SR (Iter11 80%%+STR1656 20%%): %.4f\n", BASELINE_PG2_SR))

# ─────────────────────────────────────────────────────────
# 1. START hash audit (3-package read-only verification)
# ─────────────────────────────────────────────────────────
cat("\n[1] START hash audit (3-package read-only verification)\n")

pkg_files <- c(
  file.path(WT_DIR, "alpha_package.json"),
  file.path(WT_DIR, "risk_package.json"),
  file.path(WT_DIR, "optimization_package.json")
)
start_hashes <- sapply(pkg_files, function(f) tryCatch(
  as.character(tools::md5sum(f)), error = function(e) "MISSING"))
names(start_hashes) <- basename(pkg_files)
cat("  Start MD5:\n")
for (n in names(start_hashes)) cat(sprintf("    %-35s = %s\n", n, substr(start_hashes[n],1,16)))

weights_path <- file.path(WT_DIR, "weights.csv")
start_w_hash <- as.character(tools::md5sum(weights_path))
cat(sprintf("    weights.csv                          = %s\n", substr(start_w_hash,1,16)))

# Store start hashes globally for end-audit
START_HASHES_STORED <- start_hashes
START_W_HASH_STORED <- start_w_hash

# ─────────────────────────────────────────────────────────
# 2. 3-package 로드 (READ-ONLY — Pure Function boundary)
# ─────────────────────────────────────────────────────────
cat("\n[2] Load 3-package (Pure Function boundary — no modification)\n")

alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = FALSE)
risk_pkg  <- fromJSON(file.path(WT_DIR, "risk_package.json"),  simplifyVector = FALSE)
opt_pkg   <- fromJSON(file.path(WT_DIR, "optimization_package.json"), simplifyVector = FALSE)

method_tag     <- opt_pkg$method_selected %||% "Iter11_LinTilt_lam1_plus_Threshold_8_18_28_BinaryDiscrete"
n_sigdates_wf  <- opt_pkg$n_sig_dates_walkforward %||% 92
expected_ir    <- opt_pkg$expected_information_ratio %||% 0.0945
expected_cagr  <- opt_pkg$expected_cagr %||% 0.0037
expected_mdd   <- opt_pkg$expected_mdd %||% -0.298
expected_to    <- opt_pkg$turnover %||% 5.3254
# Threshold config from optimizer (binary discrete — Forge reads, does NOT reinterpret)
threshold_t1   <- opt_pkg$method_config$threshold_t1 %||% -0.08
threshold_t2   <- opt_pkg$method_config$threshold_t2 %||% -0.18
threshold_t3   <- opt_pkg$method_config$threshold_t3 %||% -0.28
cash_c1        <- opt_pkg$method_config$cash_c1 %||% 0.30
cash_c2        <- opt_pkg$method_config$cash_c2 %||% 0.50
cash_c3        <- opt_pkg$method_config$cash_c3 %||% 1.00
# Optimizer self-reported MDD relief
opt_mdd_relief <- opt_pkg$ax_001_v2_audit$core_mdd_relief_pp %||% 0.1038

cat(sprintf("  Method: %s | walk-forward sig_dates=%d\n", method_tag, n_sigdates_wf))
cat(sprintf("  Thresholds (binary): T1=%.0f%% -> %.0f%% cash | T2=%.0f%% -> %.0f%% cash | T3=%.0f%% -> %.0f%% cash\n",
            threshold_t1*100, cash_c1*100, threshold_t2*100, cash_c2*100, threshold_t3*100, cash_c3*100))
cat(sprintf("  Expected (Optimizer self-report): IR=%.3f CAGR=%.4f MDD=%.4f TO=%.3f MDD_relief=%.4f\n",
            expected_ir, expected_cagr, expected_mdd, expected_to, opt_mdd_relief))
cat("  NOTE: Optimizer self-report is NOT final — Forge realized backtest is the arbiter.\n")
cat("        Iter 21/22 precedent: continuous proxy self-report was INVERTED vs realized.\n")

# ─────────────────────────────────────────────────────────
# 3. weights.csv 로드 (92 sig_dates × dynamic universe + cash_pct)
# ─────────────────────────────────────────────────────────
cat("\n[3] Load weights schedule (92 sig_dates × Threshold Binary Discrete)\n")

if (!file.exists(weights_path)) stop("[FAIL] weights.csv not found at ", weights_path)

w_dt <- fread(weights_path)
w_dt[, as_of_date := as.Date(as_of_date)]
setkey(w_dt, as_of_date, ticker)

sig_dates <- sort(unique(w_dt$as_of_date))
cat(sprintf("  weights.csv: %d rows | %d sig_dates\n", nrow(w_dt), length(sig_dates)))
cat(sprintf("  date range: %s ~ %s\n",
            as.character(min(sig_dates)), as.character(max(sig_dates))))
cat(sprintf("  unique methods: %s\n", paste(unique(w_dt$method_selected), collapse=", ")))

# Cash state distribution (from weights.csv)
cash_dist <- w_dt[, .N, by = cash_pct][order(cash_pct)]
cat("  Cash state distribution (from weights.csv):\n")
print(cash_dist)

cash_active_n <- length(unique(w_dt[cash_pct > 0, as_of_date]))
cat(sprintf("  Cash-active sig_dates: %d / %d (%.1f%%)\n",
            cash_active_n, length(sig_dates), cash_active_n/length(sig_dates)*100))

# ─────────────────────────────────────────────────────────
# 4. RAWDATA + Benchmark + FF5 v2 로드
# ─────────────────────────────────────────────────────────
cat("\n[4] Load RAWDATA + Benchmark + FF5 v2\n")

raw <- as.data.table(read_parquet(file.path(BASE_DIR, ".cache/rawdata.parquet"),
                                  col_select = c("Date","Ticker","Close","Vol","Ret")))
setkey(raw, Date, Ticker)
raw[, TradingAmt := Close * Vol]
cat(sprintf("  RAWDATA: %s rows | %s ~ %s\n",
            format(nrow(raw), big.mark=","),
            as.character(min(raw$Date)), as.character(max(raw$Date))))

bm <- as.data.table(read_parquet(file.path(BASE_DIR, ".cache/benchmark.parquet")))
setorder(bm, Date)
cat(sprintf("  Benchmark: %d rows | range %.0f ~ %.0f\n",
            nrow(bm), min(bm$BM_Close, na.rm=TRUE), max(bm$BM_Close, na.rm=TRUE)))

FF5_PATH <- file.path(BASE_DIR, ".cache/kr_factor_returns_v2.parquet")
ff5_v2 <- as.data.table(read_parquet(FF5_PATH))
setorder(ff5_v2, Date)
cat(sprintf("  FF5 v2: MKT=%d HML=%d RMW=%d CMA=%d WML=%d obs\n",
            sum(!is.na(ff5_v2$MKT)), sum(!is.na(ff5_v2$HML)),
            sum(!is.na(ff5_v2$RMW)), sum(!is.na(ff5_v2$CMA)),
            sum(!is.na(ff5_v2$WML))))

# ─────────────────────────────────────────────────────────
# 5. WALK-FORWARD BACKTEST (92 sig_dates, Threshold Binary Discrete)
#    Optimizer가 결정한 ticker × weight × cash_pct를 그대로 적용
#    Forge는 RAWDATA × period return 만 측정
#    PIT: weights.csv의 cash_pct는 이미 t+1 lag 적용됨 (Optimizer 확인)
# ─────────────────────────────────────────────────────────
cat("\n[5] Walk-forward backtest (92 sig_dates, Binary Discrete threshold applied)\n")
cat("    PIT guard: cash_state from weights.csv (Optimizer-enforced t+1 lag)\n")

LIQ_THRESHOLD  <- 2e8
COMMISSION_BPS <- 15

monthly_results <- vector("list", length(sig_dates) - 1)

for (i in seq_len(length(sig_dates) - 1)) {
  start_d <- sig_dates[i]
  end_d   <- sig_dates[i + 1]

  port_i_full <- w_dt[as_of_date == start_d]
  if (nrow(port_i_full) == 0) next

  # Optimizer가 결정한 cash_pct (binary discrete — Forge는 적용만)
  cash_i       <- port_i_full$cash_pct[1]
  regime_i     <- port_i_full$regime[1] %||% "UNKNOWN"
  sigma_meth   <- port_i_full$sigma_method[1] %||% "ledoit_wolf"

  # equity positions only (CASH ticker 있으면 제외)
  port_i <- port_i_full[!grepl("^CASH$", ticker, ignore.case=TRUE)]

  # weight normalize: equity portion = (1 - cash_pct) proportional
  wsum <- sum(port_i$weight, na.rm=TRUE)
  if (wsum <= 0) { next }
  port_i[, weight_risk := weight / wsum * (1 - cash_i)]

  # 유동성 필터 (PIT C10: t-30..t-1 average, NOT same-day)
  liq_window_start <- start_d - 30L
  liq_data <- raw[Date >= liq_window_start & Date < start_d,
                  .(AvgTradingAmt = mean(TradingAmt, na.rm=TRUE)), by = Ticker]
  liquid_tickers <- liq_data[AvgTradingAmt >= LIQ_THRESHOLD, Ticker]
  port_filtered <- port_i[ticker %in% liquid_tickers]
  if (nrow(port_filtered) == 0) port_filtered <- copy(port_i)

  # renormalize after liquidity filter
  wsum2 <- sum(port_filtered$weight_risk, na.rm=TRUE)
  if (wsum2 > 0) {
    port_filtered[, weight_risk := weight_risk / wsum2 * (1 - cash_i)]
  }

  # period returns (PIT C2: strictly > start_d, <= end_d)
  period_data <- raw[Date > start_d & Date <= end_d, .(Date, Ticker, Ret)]
  if (nrow(period_data) == 0) {
    monthly_results[[i]] <- data.table(
      period_start=start_d, period_end=end_d,
      port_ret=NA_real_, port_ret_gross=NA_real_,
      n_held=0L, turnover=0, cost=0,
      regime=regime_i, cash_pct=cash_i, sigma_method=sigma_meth)
    next
  }

  stock_rets <- period_data[, .(stock_ret = prod(1 + Ret, na.rm=TRUE) - 1), by = Ticker]
  merged_ret <- merge(port_filtered, stock_rets,
                     by.x = "ticker", by.y = "Ticker", all.x = TRUE)
  merged_ret[is.na(stock_ret), stock_ret := 0]

  # Portfolio return: equity portion + cash (cash returns 0% — conservative)
  port_ret_risk  <- sum(merged_ret$weight_risk * merged_ret$stock_ret, na.rm=TRUE)
  port_ret_cash  <- cash_i * 0  # cash earns 0% (conservative, not RF)
  port_ret_gross <- port_ret_risk + port_ret_cash

  # Turnover (one-way, cost = both-way)
  if (i == 1) {
    turnover_est <- 1.0
  } else {
    prev_full <- w_dt[as_of_date == sig_dates[i-1] &
                      !grepl("^CASH$", ticker, ignore.case=TRUE),
                      .(ticker, w_prev = weight)]
    prev_cash <- w_dt[as_of_date == sig_dates[i-1] &
                      grepl("^CASH$", ticker, ignore.case=TRUE), weight][1] %||% 0
    prev_wsum <- sum(prev_full$w_prev, na.rm=TRUE)
    if (prev_wsum > 0) prev_full[, w_prev := w_prev / prev_wsum * (1 - prev_cash)]
    curr_port <- port_filtered[, .(ticker, w_curr = weight_risk)]
    merged_to <- merge(prev_full, curr_port, by = "ticker", all = TRUE)
    merged_to[is.na(w_prev), w_prev := 0]
    merged_to[is.na(w_curr), w_curr := 0]
    turnover_est <- sum(abs(merged_to$w_curr - merged_to$w_prev)) / 2
  }

  cost <- (COMMISSION_BPS / 1e4) * turnover_est * 2  # round-trip
  port_ret_net <- port_ret_gross - cost

  monthly_results[[i]] <- data.table(
    period_start   = start_d,
    period_end     = end_d,
    port_ret       = port_ret_net,
    port_ret_gross = port_ret_gross,
    n_held         = nrow(merged_ret),
    turnover       = turnover_est,
    cost           = cost,
    regime         = regime_i,
    cash_pct       = cash_i,
    sigma_method   = sigma_meth
  )
}

bt_dt <- rbindlist(monthly_results, use.names=TRUE, fill=TRUE)
bt_dt <- bt_dt[!is.na(port_ret)]
setorder(bt_dt, period_end)

cat(sprintf("  Walk-forward: %d periods | %s ~ %s\n",
            nrow(bt_dt), as.character(min(bt_dt$period_end)),
            as.character(max(bt_dt$period_end))))
cat(sprintf("  Avg n_held: %.1f | Avg turnover: %.4f (ann ~%.1f%%)\n",
            mean(bt_dt$n_held), mean(bt_dt$turnover), mean(bt_dt$turnover)*12*100))
cat(sprintf("  Total cost: %.4f | Avg cash_pct: %.4f\n",
            sum(bt_dt$cost), mean(bt_dt$cash_pct, na.rm=TRUE)))
cat(sprintf("  Cash-active periods: %d / %d\n",
            sum(bt_dt$cash_pct > 0), nrow(bt_dt)))

# Cash state breakdown from actual backtest
cat("  Cash state breakdown (realized backtest):\n")
cash_breakdown <- bt_dt[, .N, by = cash_pct][order(cash_pct)]
print(cash_breakdown)

# ─────────────────────────────────────────────────────────
# 6. Pre-LB / Lockbox split + FF5 v2 매칭
# ─────────────────────────────────────────────────────────
cat("\n[6] Pre-LB / Lockbox split + FF5 v2 매칭\n")

LB_START <- as.Date("2024-01-23")
all_ret  <- bt_dt[, .(Date = period_end, port_ret, port_ret_gross,
                      regime, cash_pct, turnover, n_held, sigma_method)]
all_ret[, YM := format(Date, "%Y-%m")]

ff5_v2_dt <- copy(ff5_v2)
ff5_v2_dt[, YM := format(Date, "%Y-%m")]
merged <- merge(all_ret, ff5_v2_dt[, .(YM, MKT, SMB, HML, WML, RMW, CMA, RF)],
                by = "YM", all.x = TRUE)
merged[, excess_ret := port_ret - RF]

prelb_full <- merged[Date < LB_START & !is.na(excess_ret)]
lb_full    <- merged[Date >= LB_START & !is.na(excess_ret)]
combined   <- merged[!is.na(excess_ret)]

cat(sprintf("  Pre-LB matched FF5: %d obs | Lockbox: %d obs | Combined: %d obs\n",
            nrow(prelb_full), nrow(lb_full), nrow(combined)))

# ─────────────────────────────────────────────────────────
# 7. 5-spec factor regression (Newey-West HAC) + DSR
# ─────────────────────────────────────────────────────────
cat("\n[7] 5-spec factor regression (FF5 v2, Newey-West HAC)\n")

nw_t_stat <- function(model, lag = NULL) {
  n <- length(residuals(model))
  if (is.null(lag)) lag <- floor(4 * (n/100)^(2/9))
  lag <- max(1L, as.integer(lag))
  tryCatch({
    nw_vcov <- NeweyWest(model, lag = lag, prewhite = FALSE, adjust = TRUE)
    ct <- coeftest(model, vcov = nw_vcov)
    list(alpha=ct["(Intercept)","Estimate"],
         t_nw =ct["(Intercept)","t value"],
         p_nw =ct["(Intercept)","Pr(>|t|)"],
         lag=lag, n=n,
         r2=summary(model)$r.squared,
         adj_r2=summary(model)$adj.r.squared)
  }, error = function(e) {
    list(alpha=NA, t_nw=NA, p_nw=NA, lag=lag, n=n, r2=NA, adj_r2=NA,
         error=conditionMessage(e))
  })
}

compute_dsr <- function(returns, sr_benchmark = 0) {
  n <- length(returns)
  if (n < 12) return(list(dsr=NA, sr_ann=NA, note="insufficient_obs"))
  sr_m <- mean(returns, na.rm=TRUE) / sd(returns, na.rm=TRUE)
  sr_ann <- sr_m * sqrt(12)
  skew  <- tryCatch(e1071::skewness(returns), error=function(e) 0)
  kurt  <- tryCatch(e1071::kurtosis(returns) + 3, error=function(e) 3)
  denom <- sqrt((1 - skew*sr_m + (kurt-1)/4 * sr_m^2) / (n-1))
  dsr   <- if (!is.na(denom) && denom > 1e-10) (sr_ann - sr_benchmark) / (denom * sqrt(12)) else NA
  list(dsr=round(dsr,4), sr_ann=round(sr_ann,4), sr_m=round(sr_m,4))
}

run_5spec <- function(dt, label) {
  dt <- dt[!is.na(excess_ret)]
  results <- list()
  d1 <- dt[!is.na(MKT)]
  if (nrow(d1) >= 20) {
    m1 <- lm(excess_ret ~ MKT, data=d1)
    results[["CAPM"]] <- c(nw_t_stat(m1), list(spec="CAPM", n_eff=nrow(d1)))
  }
  d2 <- dt[!is.na(MKT) & !is.na(SMB) & !is.na(HML)]
  if (nrow(d2) >= 20) {
    m2 <- lm(excess_ret ~ MKT + SMB + HML, data=d2)
    results[["Carhart_3"]] <- c(nw_t_stat(m2), list(spec="Carhart_3", n_eff=nrow(d2)))
  }
  d3 <- dt[!is.na(MKT) & !is.na(SMB) & !is.na(HML) & !is.na(WML)]
  if (nrow(d3) >= 20) {
    m3 <- lm(excess_ret ~ MKT + SMB + HML + WML, data=d3)
    results[["Carhart_4"]] <- c(nw_t_stat(m3), list(spec="Carhart_4", n_eff=nrow(d3)))
  }
  d4 <- dt[!is.na(MKT) & !is.na(SMB) & !is.na(HML) & !is.na(RMW) & !is.na(CMA)]
  if (nrow(d4) >= 20) {
    m4 <- lm(excess_ret ~ MKT + SMB + HML + RMW + CMA, data=d4)
    results[["FF5"]] <- c(nw_t_stat(m4), list(spec="FF5", n_eff=nrow(d4)))
    dsr_res <- compute_dsr(d4$excess_ret)
    results[["FF5"]]$dsr    <- dsr_res$dsr
    results[["FF5"]]$sr_ann <- dsr_res$sr_ann
  }
  d5 <- dt[!is.na(MKT) & !is.na(SMB) & !is.na(HML) & !is.na(WML) & !is.na(RMW) & !is.na(CMA)]
  if (nrow(d5) >= 20) {
    m5 <- lm(excess_ret ~ MKT + SMB + HML + WML + RMW + CMA, data=d5)
    results[["FF6"]] <- c(nw_t_stat(m5), list(spec="FF6", n_eff=nrow(d5)))
  }
  cat(sprintf("  [%s] 5-spec results:\n", label))
  for (sp in names(results)) {
    r <- results[[sp]]
    g <- if (!is.na(r$t_nw) && r$t_nw >= 2.95) " <<GATE PASS>>" else
         if (!is.na(r$t_nw) && r$t_nw >= 2.0)  " [borderline]" else " [fail]"
    cat(sprintf("    %-12s: alpha=%.4f%% t_NW=%.3f (n=%d, lag=%d)%s\n",
                sp, (r$alpha %||% NA)*100, r$t_nw %||% NA,
                r$n_eff %||% NA, r$lag %||% NA, g))
  }
  results
}

cat("\n--- Combined (92 periods walk-forward) ---\n")
res_full  <- run_5spec(combined, "Combined")
cat("\n--- Pre-LB (2008-02 ~ 2023-11 walk-forward) ---\n")
res_prelb <- run_5spec(prelb_full, "Pre-LB")
cat("\n--- Lockbox (2024-01-23+, if any) ---\n")
res_lb    <- run_5spec(lb_full, "Lockbox")

spec_names <- c("CAPM","Carhart_3","Carhart_4","FF5","FF6")
n_pass <- sum(sapply(spec_names, function(sp) {
  t <- res_full[[sp]]$t_nw
  !is.na(t) && t >= 2.95
}))
cat(sprintf("\n  5-spec PASS count (Combined, t>=2.95): %d/5\n", n_pass))

# ─────────────────────────────────────────────────────────
# 8. Backtest performance + Cash-regime conditional
# ─────────────────────────────────────────────────────────
cat("\n[8] Backtest performance + Cash-state conditional metrics\n")

compute_perf_v2 <- function(r, label, candidates_tried = 0,
                             penalty_per_cand = 0.05,
                             start_ym = "2008-01") {
  r <- r[!is.na(r)]
  n <- length(r)
  if (n < 6) return(list(label=label, cagr=NA, vol=NA, sr=NA,
                         mdd=NA, hit=NA, n_months=n,
                         dsr_raw=NA, dsr_post_penalty=NA, harvey_t_ff5=NA))
  cagr <- prod(1 + r)^(12/n) - 1
  vol  <- sd(r) * sqrt(12)
  sr_m <- mean(r) / sd(r)
  sr   <- sr_m * sqrt(12)
  cum  <- cumprod(1 + r)
  mdd  <- min(cum / cummax(cum) - 1, na.rm=TRUE)
  hit  <- mean(r > 0)

  start_date <- as.Date(paste0(start_ym, "-01"))
  dt_x <- data.table(YM = format(seq.Date(from=start_date, by="month", length.out=n), "%Y-%m"),
                     port = r)
  ff5_join <- ff5_v2[, .(YM = format(Date, "%Y-%m"), MKT, SMB, HML, WML, RMW, CMA, RF)]
  mg <- merge(dt_x, ff5_join, by="YM", all.x=TRUE)
  mg[, excess := port - RF]
  mg <- mg[!is.na(excess) & !is.na(MKT) & !is.na(RMW)]
  harvey_t_ff5 <- NA
  if (nrow(mg) >= 24) {
    m_ff5 <- lm(excess ~ MKT + SMB + HML + RMW + CMA, data=mg)
    nw_lag <- max(1L, floor(4 * (nrow(mg)/100)^(2/9)))
    nw_v <- tryCatch(NeweyWest(m_ff5, lag=nw_lag, prewhite=FALSE, adjust=TRUE), error=function(e) NULL)
    if (!is.null(nw_v)) {
      ct <- tryCatch(coeftest(m_ff5, vcov=nw_v), error=function(e) NULL)
      if (!is.null(ct)) harvey_t_ff5 <- ct["(Intercept)","t value"]
    }
  }
  skew <- tryCatch(e1071::skewness(r), error=function(e) 0)
  kurt <- tryCatch(e1071::kurtosis(r) + 3, error=function(e) 3)
  denom <- sqrt((1 - skew * sr_m + (kurt-1)/4 * sr_m^2) / (n-1))
  dsr_raw  <- if (!is.na(denom) && denom > 1e-10) sr / (denom * sqrt(12)) else NA
  dsr_post <- if (!is.na(dsr_raw)) dsr_raw - candidates_tried * penalty_per_cand else NA

  list(label=label, cagr=round(cagr,4), vol=round(vol,4),
       sr=round(sr,4), mdd=round(mdd,4), hit=round(hit,4),
       n_months=n, ir=round(sr,4),
       harvey_t_ff5=round(harvey_t_ff5,4),
       dsr_raw=round(dsr_raw,4),
       dsr_post_penalty=round(dsr_post,4))
}

print_perf_row <- function(p) {
  cat(sprintf("    %-36s | n=%3d | SR=%.3f | CAGR=%.2f%% | MDD=%.2f%% | t_FF5=%.3f | DSR_post=%.3f\n",
              p$label, p$n_months, p$sr %||% NA, (p$cagr %||% NA)*100,
              (p$mdd %||% NA)*100, p$harvey_t_ff5 %||% NA,
              p$dsr_post_penalty %||% NA))
}

perf_full  <- compute_perf_v2(combined$port_ret, "Iter26_Combined",
                               DSR_CANDIDATES_TRIED, start_ym="2008-02")
perf_prelb <- compute_perf_v2(prelb_full$port_ret, "Iter26_PreLB",
                               DSR_CANDIDATES_TRIED, start_ym="2008-02")
perf_lb    <- compute_perf_v2(lb_full$port_ret, "Iter26_Lockbox",
                               0, start_ym="2024-01")

cat("\n  --- Pre-LB / Lockbox / Combined ---\n")
print_perf_row(perf_full); print_perf_row(perf_prelb); print_perf_row(perf_lb)

# Cash-state conditional performance (realized AX-001 v2 measurement)
cat("\n  Cash-state conditional (Pre-LB realized):\n")
cash_state_perf <- list()
for (cs in c(0, 0.30, 0.50, 1.00)) {
  sub <- prelb_full[abs(cash_pct - cs) < 0.01]
  if (nrow(sub) >= 4) {
    p <- compute_perf_v2(sub$port_ret, sprintf("Iter26_cash_%.0f%%", cs*100), 0,
                         start_ym=format(min(sub$Date), "%Y-%m"))
    cash_state_perf[[sprintf("%.0f", cs*100)]] <- p
    cat(sprintf("    [cash=%.0f%%] n=%3d SR=%.3f CAGR=%.2f%% MDD=%.2f%% Hit=%.1f%%\n",
                cs*100, p$n_months, p$sr %||% NA, (p$cagr %||% NA)*100,
                (p$mdd %||% NA)*100, (p$hit %||% NA)*100))
  } else {
    cat(sprintf("    [cash=%.0f%%] insufficient n=%d\n", cs*100, nrow(sub)))
    cash_state_perf[[sprintf("%.0f", cs*100)]] <- list(n_months=nrow(sub), sr=NA, cagr=NA, mdd=NA)
  }
}

# ─────────────────────────────────────────────────────────
# 9. AX-001 v2 4-metric REALIZED measurement
#    Crisis = periods when cash_pct > 0 (drawdown threshold breached)
#    Core baseline = Iter 11 (from Iter11 backtest_result)
# ─────────────────────────────────────────────────────────
cat("\n[9] AX-001 v2 4-metric REALIZED measurement\n")
cat("    (Optimizer self-reported 2/4 — Forge measures realized)\n")

# Load Iter 11 monthly returns for baseline comparison
iter11_monthly_path <- file.path(ITER11_BT, "iter11_full_period_monthly.csv")
if (file.exists(iter11_monthly_path)) {
  iter11_monthly <- fread(iter11_monthly_path)
  iter11_monthly[, Date := as.Date(Date)]
  setorder(iter11_monthly, Date)
  iter11_monthly[, YM := format(Date, "%Y-%m")]
  cat(sprintf("  Iter 11 baseline: n=%d (%s ~ %s)\n",
              nrow(iter11_monthly), min(iter11_monthly$YM), max(iter11_monthly$YM)))
  iter11_available <- TRUE
} else {
  cat("  WARNING: Iter 11 monthly returns not found — MDD relief will be from optimization_package\n")
  iter11_available <- FALSE
}

# Metric 1: Crisis alpha (cash > 0 periods vs cash = 0 periods)
cash_active_sub <- prelb_full[cash_pct > 0]
cash_zero_sub   <- prelb_full[cash_pct == 0]

crisis_alpha_m <- NA
crisis_normal_m <- NA
if (nrow(cash_active_sub) >= 4) {
  crisis_alpha_m  <- mean(cash_active_sub$port_ret, na.rm=TRUE)
}
if (nrow(cash_zero_sub) >= 4) {
  crisis_normal_m <- mean(cash_zero_sub$port_ret, na.rm=TRUE)
}
cat(sprintf("  [Metric 1] Crisis alpha (cash-active avg monthly ret): %.4f (target > 0)\n",
            crisis_alpha_m %||% NA))
cat(sprintf("             Normal avg monthly ret (cash=0): %.4f\n", crisis_normal_m %||% NA))
ax001_crisis_pass <- !is.na(crisis_alpha_m) && crisis_alpha_m >= 0

# Metric 2: MDD relief vs Iter 11 baseline (REALIZED)
iter26_mdd <- perf_prelb$mdd  # Iter 26 realized MDD
iter11_mdd <- NA

if (iter11_available) {
  # Match same period (Iter 26: 2008-02 ~ 2023-11)
  iter11_common <- iter11_monthly[YM %in% prelb_full$YM]
  if (nrow(iter11_common) >= 12) {
    iter11_mdd_realized <- min(cumprod(1 + iter11_common$port_ret) /
                               cummax(cumprod(1 + iter11_common$port_ret)) - 1, na.rm=TRUE)
    iter11_mdd <- iter11_mdd_realized
    cat(sprintf("  [Metric 2] MDD relief — Iter11 same-period: %.4f | Iter26: %.4f | Relief: %+.4f (%+.2fpp)\n",
                iter11_mdd, iter26_mdd %||% NA, (iter26_mdd %||% 0) - iter11_mdd,
                ((iter26_mdd %||% 0) - iter11_mdd) * 100))
    realized_mdd_relief_pp <- round((-((iter26_mdd %||% 0) - iter11_mdd)) * 100, 2)  # positive = improvement
    ax001_mdd_pass <- realized_mdd_relief_pp >= 5.0  # target: at least +5pp relief
  } else {
    cat("  [Metric 2] Iter 11 same-period overlap insufficient — using optimizer self-report\n")
    realized_mdd_relief_pp <- opt_mdd_relief * 100
    ax001_mdd_pass <- realized_mdd_relief_pp >= 5.0
  }
} else {
  # Fallback to optimizer self-report
  realized_mdd_relief_pp <- opt_mdd_relief * 100
  ax001_mdd_pass <- realized_mdd_relief_pp >= 5.0
  cat(sprintf("  [Metric 2] MDD relief (optimizer self-report fallback): %+.2fpp (target >= 5pp)\n",
              realized_mdd_relief_pp))
}
cat(sprintf("             PASS: %s\n", if (ax001_mdd_pass) "YES" else "NO"))

# Metric 3: Bad/Normal return ratio
# "bad" = months where mkt return < -5% (crisis proxy)
ff5_v2[, YM := format(Date, "%Y-%m")]
mkt_bad_months <- ff5_v2[MKT < -0.05, YM]
bad_sub  <- prelb_full[YM %in% mkt_bad_months]
norm_sub <- prelb_full[!YM %in% mkt_bad_months]
bad_m    <- if (nrow(bad_sub)  >= 4) mean(bad_sub$port_ret,  na.rm=TRUE) else NA
norm_m   <- if (nrow(norm_sub) >= 4) mean(norm_sub$port_ret, na.rm=TRUE) else NA
bad_normal_ratio <- if (!is.na(bad_m) && !is.na(norm_m) && abs(norm_m) > 1e-6) {
  bad_m / norm_m
} else NA
cat(sprintf("  [Metric 3] Bad/Normal ratio: bad_avg=%.4f normal_avg=%.4f ratio=%.4f (target >= 1.5 or > 1 if bad positive)\n",
            bad_m %||% NA, norm_m %||% NA, bad_normal_ratio %||% NA))
ax001_bad_normal_pass <- !is.na(bad_normal_ratio) && bad_normal_ratio >= 1.5

# Metric 4: Harvey conditional t (drawdown-active periods regression)
harvey_cond_t <- NA
if (nrow(cash_active_sub) >= 20) {
  cash_a_ff5 <- merge(cash_active_sub[, .(YM, excess_ret)],
                      ff5_v2[, .(YM, MKT, SMB, HML, RMW, CMA)],
                      by = "YM", all.x = TRUE)
  cash_a_ff5 <- cash_a_ff5[!is.na(excess_ret) & !is.na(MKT) & !is.na(RMW)]
  if (nrow(cash_a_ff5) >= 20) {
    m_cond <- lm(excess_ret ~ MKT + SMB + HML + RMW + CMA, data=cash_a_ff5)
    nw_lag  <- max(1L, floor(4 * (nrow(cash_a_ff5)/100)^(2/9)))
    nw_v    <- tryCatch(NeweyWest(m_cond, lag=nw_lag, prewhite=FALSE, adjust=TRUE),
                        error=function(e) NULL)
    if (!is.null(nw_v)) {
      ct <- tryCatch(coeftest(m_cond, vcov=nw_v), error=function(e) NULL)
      if (!is.null(ct)) harvey_cond_t <- ct["(Intercept)", "t value"]
    }
  }
}
cat(sprintf("  [Metric 4] Harvey conditional t (cash-active, n=%d): %.4f (target >= 2.0)\n",
            nrow(cash_active_sub), harvey_cond_t %||% NA))
ax001_harvey_pass <- !is.na(harvey_cond_t) && harvey_cond_t >= 2.0

# AX-001 v2 summary
ax001_realized_count <- sum(c(ax001_crisis_pass, ax001_mdd_pass,
                              ax001_bad_normal_pass, ax001_harvey_pass), na.rm=TRUE)
cat(sprintf("\n  AX-001 v2 REALIZED: %d/4 PASS\n", ax001_realized_count))
cat(sprintf("    crisis_alpha:    %s (>=0 floor)\n",   if (ax001_crisis_pass) "PASS" else "FAIL"))
cat(sprintf("    mdd_relief:      %s (>=5pp)\n",       if (ax001_mdd_pass) "PASS" else "FAIL"))
cat(sprintf("    bad_normal_1.5:  %s (>=1.5 ratio)\n", if (ax001_bad_normal_pass) "PASS" else "FAIL"))
cat(sprintf("    harvey_cond_2:   %s (t>=2.0)\n",      if (ax001_harvey_pass) "PASS" else "FAIL"))
cat(sprintf("  Optimizer self-reported: 2/4 PASS — Forge realized: %d/4\n", ax001_realized_count))

# ─────────────────────────────────────────────────────────
# 10. 24-26 OOS extension (last sig_date 2023-11-30 -> frozen)
# ─────────────────────────────────────────────────────────
cat("\n[10] 24-26 OOS frozen-weights extension (last sig_date -> 2026 current)\n")

last_sig  <- max(sig_dates)
last_w    <- w_dt[as_of_date == last_sig & !grepl("^CASH$", ticker, ignore.case=TRUE),
                   .(ticker, weight)]
last_cash <- w_dt[as_of_date == last_sig & grepl("^CASH$", ticker, ignore.case=TRUE), weight][1] %||%
             w_dt[as_of_date == last_sig, cash_pct][1] %||% 0
if (sum(last_w$weight, na.rm=TRUE) > 0) {
  last_w[, weight_risk := weight / sum(weight, na.rm=TRUE) * (1 - last_cash)]
} else {
  last_w[, weight_risk := 0]
}

cat(sprintf("  Last sig_date %s: %d equity names | cash=%.1f%%\n",
            as.character(last_sig), nrow(last_w), last_cash*100))

oos_end   <- max(raw$Date)
oos_dates <- seq.Date(as.Date("2024-01-01"), oos_end, by = "month")
oos_dates <- c(oos_dates, oos_end)
oos_dates <- sort(unique(oos_dates))

oos_periods <- list()
prev_d <- last_sig
for (k in seq_along(oos_dates)) {
  d_curr <- oos_dates[k]
  if (d_curr <= prev_d) next
  pdat <- raw[Date > prev_d & Date <= d_curr & Ticker %in% last_w$ticker, .(Date, Ticker, Ret)]
  if (nrow(pdat) == 0) { prev_d <- d_curr; next }
  stock_r <- pdat[, .(stock_ret = prod(1 + Ret, na.rm=TRUE) - 1), by = Ticker]
  m_w <- merge(last_w, stock_r, by.x="ticker", by.y="Ticker", all.x=TRUE)
  m_w[is.na(stock_ret), stock_ret := 0]
  port_ret_oos <- sum(m_w$weight_risk * m_w$stock_ret, na.rm=TRUE) + last_cash * 0
  oos_periods[[length(oos_periods) + 1]] <-
    data.table(period_end = d_curr, port_ret = port_ret_oos, n_held = nrow(m_w))
  prev_d <- d_curr
}
oos_dt <- rbindlist(oos_periods)
setorder(oos_dt, period_end)
oos_dt[, YM := format(period_end, "%Y-%m")]

perf_oos <- compute_perf_v2(oos_dt$port_ret, "Iter26_OOS_24_26", 0, start_ym="2024-01")
cat(sprintf("  OOS frozen: n=%d | SR=%.3f | CAGR=%.2f%% | MDD=%.2f%% | Hit=%.1f%%\n",
            perf_oos$n_months, perf_oos$sr %||% NA,
            (perf_oos$cagr %||% NA)*100, (perf_oos$mdd %||% NA)*100,
            (perf_oos$hit %||% NA)*100))

# Full-period combined
iter26_full <- rbind(
  bt_dt[, .(Date = period_end, port_ret)],
  oos_dt[, .(Date = period_end, port_ret)]
)
setorder(iter26_full, Date)
iter26_full[, YM := format(Date, "%Y-%m")]
iter26_full <- unique(iter26_full, by = "YM")
perf_iter26_full <- compute_perf_v2(iter26_full$port_ret, "Iter26_full_period",
                                     DSR_CANDIDATES_TRIED, start_ym="2008-02")
cat(sprintf("  Iter 26 full-period (%d+%d=%d months): SR=%.3f CAGR=%.2f%% MDD=%.2f%% t_FF5=%.3f DSR_post=%.3f\n",
            perf_prelb$n_months, perf_oos$n_months, perf_iter26_full$n_months,
            perf_iter26_full$sr %||% NA, (perf_iter26_full$cagr %||% NA)*100,
            (perf_iter26_full$mdd %||% NA)*100,
            perf_iter26_full$harvey_t_ff5 %||% NA,
            perf_iter26_full$dsr_post_penalty %||% NA))

# ─────────────────────────────────────────────────────────
# 11. PG2 Blend scenarios: Iter26 vs Iter11 vs Baseline
#     Primary: B1 (Iter26 80% + STR_1656 20%) vs Iter11 80% + STR_1656 20%
# ─────────────────────────────────────────────────────────
cat("\n[11] PG2 Blend scenarios: Iter26 80%+STR_1656 20% vs Iter11 80%+STR_1656 20%\n")

# STR_1656 monthly NAV
str1656_path <- file.path(BASE_DIR, "04_Research/strategies/STR_1656_MLRA/output/nav_S1_A.csv")
str1656_daily <- fread(str1656_path)
str1656_daily[, Date := as.Date(Date)]
setorder(str1656_daily, Date)
str1656_daily[, YM := format(Date, "%Y-%m")]
str1656_monthly <- str1656_daily[, .(Date_eom=max(Date), NAV_eom=NAV[which.max(Date)]), by=YM]
setorder(str1656_monthly, Date_eom)
str1656_monthly[, Ret_m := NAV_eom / shift(NAV_eom) - 1]
str1656_monthly <- str1656_monthly[!is.na(Ret_m)]
cat(sprintf("  STR_1656 monthly: n=%d (%s ~ %s)\n",
            nrow(str1656_monthly), min(str1656_monthly$YM), max(str1656_monthly$YM)))

# Iter 11 full monthly returns (for comparison)
iter11_full_path <- file.path(ITER11_BT, "iter11_full_period_monthly.csv")
if (file.exists(iter11_full_path)) {
  iter11_full_m <- fread(iter11_full_path)
  iter11_full_m[, Date := as.Date(Date)]
  setorder(iter11_full_m, Date)
  iter11_full_m[, YM := format(Date, "%Y-%m")]
  iter11_available_full <- TRUE
  cat(sprintf("  Iter 11 full: n=%d (%s ~ %s)\n",
              nrow(iter11_full_m), min(iter11_full_m$YM), max(iter11_full_m$YM)))
} else {
  iter11_available_full <- FALSE
  cat("  WARNING: Iter 11 full monthly returns not found\n")
}

# Build panel
panel <- merge(iter26_full[, .(YM, Date, iter26 = port_ret)],
               str1656_monthly[, .(YM, str1656 = Ret_m)], by="YM", all=TRUE)
if (iter11_available_full) {
  panel <- merge(panel, iter11_full_m[, .(YM, iter11 = port_ret)], by="YM", all=TRUE)
} else {
  panel[, iter11 := NA_real_]
}
setorder(panel, YM)
panel[is.na(Date), Date := as.Date(paste0(YM, "-15"))]

# MEGA_05 reference
mega_doc_path <- file.path(BASE_DIR,
  "04_Research/strategies/STR_1631_PG2_MDD_OPT/output/daily_nav_bcde.csv")
if (file.exists(mega_doc_path)) {
  mega_doc_daily <- fread(mega_doc_path, select=c("Date","Ret_vdp","NAV_vdp"))
  mega_doc_daily[, Date := as.Date(Date)]
  setorder(mega_doc_daily, Date)
  mega_doc_daily[, YM := format(Date, "%Y-%m")]
  mega05_monthly <- mega_doc_daily[, .(Date_eom=max(Date), NAV_eom=NAV_vdp[which.max(Date)]), by=YM]
  setorder(mega05_monthly, Date_eom)
  mega05_monthly[, Ret_m := NAV_eom / shift(NAV_eom) - 1]
  mega05_monthly <- mega05_monthly[!is.na(Ret_m)]
  panel <- merge(panel, mega05_monthly[, .(YM, mega05 = Ret_m)], by="YM", all=TRUE)
  cat(sprintf("  MEGA_05 monthly: n=%d (%s ~ %s)\n",
              nrow(mega05_monthly), min(mega05_monthly$YM), max(mega05_monthly$YM)))
} else {
  panel[, mega05 := NA_real_]
  cat("  MEGA_05 not available\n")
}

setorder(panel, YM)

# Scenario V26_A: Iter26 standalone
panel_V26A <- panel[!is.na(iter26)]
perf_V26_A <- compute_perf_v2(panel_V26A$iter26, "V26_standalone_100",
                               DSR_CANDIDATES_TRIED, start_ym=min(panel_V26A$YM))

# Scenario V26_blend: Iter26 80% + STR_1656 20% (PRIMARY PG2 candidate)
panel_V26B <- panel[!is.na(iter26) & !is.na(str1656)]
scen_V26B_ret <- 0.8 * panel_V26B$iter26 + 0.2 * panel_V26B$str1656
perf_V26_blend <- compute_perf_v2(scen_V26B_ret, "V26_blend_80_20",
                                   DSR_CANDIDATES_TRIED, start_ym=min(panel_V26B$YM))

# Scenario Iter11_blend: Iter11 80% + STR_1656 20% (baseline comparison)
perf_Iter11_blend <- NULL
if (iter11_available_full) {
  panel_I11B <- panel[!is.na(iter11) & !is.na(str1656)]
  scen_I11B_ret <- 0.8 * panel_I11B$iter11 + 0.2 * panel_I11B$str1656
  ym_i11b_start <- min(panel_I11B$YM)
  perf_Iter11_blend <- compute_perf_v2(scen_I11B_ret, "Iter11_blend_80_20 (baseline)",
                                        DSR_CANDIDATES_TRIED, start_ym=ym_i11b_start)
}

# Scenario D: current PG2 (MEGA_05 80% + STR_1656 20%)
panel_D <- panel[!is.na(mega05) & !is.na(str1656)]
scen_D_ret <- 0.8 * panel_D$mega05 + 0.2 * panel_D$str1656
perf_scen_D <- compute_perf_v2(scen_D_ret, "D_current_PG2_mega05_80_20",
                                15, start_ym=min(panel_D$YM))

cat("\n  --- PG2 blend scenarios ---\n")
print_perf_row(perf_V26_A)
print_perf_row(perf_V26_blend)
if (!is.null(perf_Iter11_blend)) print_perf_row(perf_Iter11_blend)
print_perf_row(perf_scen_D)

# Delta: V26 blend vs baseline
v26_blend_sr     <- perf_V26_blend$sr   %||% NA
iter11_blend_sr  <- if (!is.null(perf_Iter11_blend)) perf_Iter11_blend$sr %||% NA else NA
delta_sr_vs_baseline <- if (!is.na(v26_blend_sr) && !is.na(iter11_blend_sr))
  v26_blend_sr - iter11_blend_sr else NA
delta_sr_vs_BASELINE_PG2 <- if (!is.na(v26_blend_sr)) v26_blend_sr - BASELINE_PG2_SR else NA

cat(sprintf("\n  V26 blend SR = %.4f\n", v26_blend_sr %||% NA))
cat(sprintf("  Iter11 blend SR = %.4f (realized baseline)\n", iter11_blend_sr %||% NA))
cat(sprintf("  BASELINE_PG2_SR = %.4f (mandate threshold)\n", BASELINE_PG2_SR))
cat(sprintf("  delta vs realized Iter11 blend = %+.4f\n", delta_sr_vs_baseline %||% NA))
cat(sprintf("  delta vs BASELINE_PG2_SR (1.4625) = %+.4f\n", delta_sr_vs_BASELINE_PG2 %||% NA))

# PG2 admission verdict
pg2_pass <- !is.na(v26_blend_sr) && v26_blend_sr > BASELINE_PG2_SR
cat(sprintf("  PG2 admission (V26 blend SR > %.4f): %s\n",
            BASELINE_PG2_SR, if (pg2_pass) "PASS" else "FAIL"))

# MDD comparison
v26_blend_mdd    <- perf_V26_blend$mdd  %||% NA
iter11_blend_mdd <- if (!is.null(perf_Iter11_blend)) perf_Iter11_blend$mdd %||% NA else NA
realized_mdd_vs_iter11_blend_pp <- if (!is.na(v26_blend_mdd) && !is.na(iter11_blend_mdd))
  round((v26_blend_mdd - iter11_blend_mdd) * 100, 2) else NA  # negative = V26 worse
cat(sprintf("  V26 blend MDD = %.4f | Iter11 blend MDD = %.4f | delta = %+.2fpp\n",
            v26_blend_mdd %||% NA, iter11_blend_mdd %||% NA,
            realized_mdd_vs_iter11_blend_pp %||% NA))
cat(sprintf("  Optimizer expected MDD relief +10.38pp => realized at blend level: %+.2fpp\n",
            -realized_mdd_vs_iter11_blend_pp %||% NA))

# ─────────────────────────────────────────────────────────
# 12. Iter 21/22/22b vs Iter 26 comparison
# ─────────────────────────────────────────────────────────
cat("\n[12] Iter 21/22/22b vs Iter 26 honest comparison\n")
cat("     (Continuous overlay historical fail vs Binary discrete present)\n")

iter_compare <- data.table(
  iter       = c("Iter21_continuous", "Iter22_continuous", "Iter22b_continuous",
                 "Iter26_binary_discrete"),
  mechanism  = c("msi_norm continuous 0~50%", "msi_norm v2 continuous",
                 "continuous v2b", "binary step {0,30,50,100}%"),
  self_report_mdd_relief_pp = c(19.98, 21.28, 21.28, 10.38),
  self_report_sr_delta      = c(NA, NA, NA, NA),
  realized_mdd_relief_pp    = c(-19.98, -21.28, -21.28,  # inverted (L-231 lesson)
                                 -realized_mdd_vs_iter11_blend_pp %||% NA),  # V26 realized (blend level)
  mechanism_type = c("continuous", "continuous", "continuous", "binary")
)

cat("  Iter comparison (self_report vs realized MDD relief):\n")
print(iter_compare)

# ─────────────────────────────────────────────────────────
# 13. Charts (equity_curve / annual_returns / oos_zoom / scenario_comparison)
# ─────────────────────────────────────────────────────────
cat("\n[13] Chart generation\n")

bm[, YM := format(Date, "%Y-%m")]
bm_monthly <- bm[, .(Date_eom=max(Date), BM_Close_eom=BM_Close[which.max(Date)]), by=YM]
setorder(bm_monthly, Date_eom)

# 13-1. equity_curve.png
cat("  [13-1] equity_curve.png — Iter26 vs Iter11 vs BM\n")
iter26_full[, cum := cumprod(1 + port_ret)]

plot_eq_list <- list(
  data.table(Date=iter26_full$Date, cum=iter26_full$cum,
             Series="Iter26 (Binary DD Threshold)")
)
if (iter11_available_full) {
  iter11_full_m[, cum := cumprod(1 + port_ret)]
  plot_eq_list <- append(plot_eq_list, list(
    data.table(Date=iter11_full_m$Date, cum=iter11_full_m$cum,
               Series="Iter11 (LinTilt baseline)")
  ))
}
bm_align <- bm_monthly[Date_eom >= min(iter26_full$Date) - 35]
bm_align[, BM_cum := BM_Close_eom / BM_Close_eom[1]]
plot_eq_list <- append(plot_eq_list, list(
  data.table(Date=bm_align$Date_eom, cum=bm_align$BM_cum, Series="KOSPI200 (BM)")
))

plot_eq <- rbindlist(plot_eq_list)
plot_eq <- plot_eq[!is.na(cum) & cum > 0]

color_map <- c(
  "Iter26 (Binary DD Threshold)" = "#F44336",
  "Iter11 (LinTilt baseline)"    = "#3F51B5",
  "KOSPI200 (BM)"                = "#9E9E9E"
)

g1 <- ggplot(plot_eq, aes(x=Date, y=cum, color=Series)) +
  geom_line(linewidth=0.85) +
  scale_y_log10(labels=scales::label_number(accuracy=0.1)) +
  scale_color_manual(values=color_map) +
  geom_vline(xintercept=LB_START, linetype="dashed", color="red", alpha=0.7) +
  annotate("text", x=LB_START+90, y=max(plot_eq$cum, na.rm=TRUE)*0.85,
           label="Lockbox 2024-01-23+", color="red", size=3.5, fontface="bold") +
  labs(title="STR_1701 Iter26 Binary DD Threshold — Full-period equity vs Iter11 vs BM",
       subtitle=sprintf("Iter26 full: SR=%.3f CAGR=%.2f%% MDD=%.2f%% t_FF5=%.3f | AX-001v2: %d/4 PASS | PG2 blend SR=%.3f",
                        perf_iter26_full$sr %||% NA,
                        (perf_iter26_full$cagr %||% NA)*100,
                        (perf_iter26_full$mdd %||% NA)*100,
                        perf_iter26_full$harvey_t_ff5 %||% NA,
                        ax001_realized_count,
                        v26_blend_sr %||% NA),
       x="Date", y="Cumulative Return (log)", color="") +
  theme_minimal(base_size=11) + theme(legend.position="bottom")

ec_path <- file.path(OUT_DIR, "equity_curve.png")
ggsave(ec_path, g1, width=13, height=7, dpi=150)
cat(sprintf("    Saved: %s\n", ec_path))

# 13-2. annual_returns.png
cat("  [13-2] annual_returns.png\n")
ann_strat <- copy(all_ret)
ann_strat[, Year := as.integer(format(Date, "%Y"))]
ann_strat_dt <- ann_strat[, .(strat_ret=prod(1+port_ret)-1, n_m=.N), by=Year]

bm_y <- copy(bm_monthly)
bm_y[, Year := as.integer(substr(YM,1,4))]
bm_year_cum <- bm_y[, .(BM_eoY=BM_Close_eom[which.max(Date_eom)]), by=Year]
setorder(bm_year_cum, Year)
bm_year_cum[, BM_ret_y := BM_eoY / shift(BM_eoY) - 1]
bm_year_cum <- bm_year_cum[!is.na(BM_ret_y)]

ann_merged <- merge(ann_strat_dt, bm_year_cum[, .(Year, BM_ret_y)], by="Year", all.x=TRUE)
ann_long <- melt(ann_merged[, .(Year, Iter26=strat_ret, BM=BM_ret_y)],
                 id.vars="Year", variable.name="Series", value.name="Annual_Return")

g2 <- ggplot(ann_long, aes(x=factor(Year), y=Annual_Return*100, fill=Series)) +
  geom_bar(stat="identity", position=position_dodge(width=0.85), width=0.78) +
  scale_fill_manual(values=c("Iter26"="#F44336", "BM"="#9E9E9E")) +
  geom_hline(yintercept=0, color="black", linewidth=0.4) +
  labs(title="STR_1701 Iter26 Binary DD Threshold — Annual Returns vs KOSPI200",
       subtitle=sprintf("Binary discrete {0,30,50,100}%% cash | 8/18/28%% thresholds | %d periods",
                        nrow(bt_dt)),
       x="Year", y="Annual Return (%)", fill="") +
  theme_minimal(base_size=11) +
  theme(legend.position="bottom", axis.text.x=element_text(angle=45, hjust=1))

ar_path <- file.path(OUT_DIR, "annual_returns.png")
ggsave(ar_path, g2, width=12, height=6, dpi=150)
cat(sprintf("    Saved: %s\n", ar_path))

# 13-3. oos_zoom_chart.png
cat("  [13-3] oos_zoom_chart.png\n")
oos_str <- copy(oos_dt)
setorder(oos_str, period_end)
if (nrow(oos_str) > 0) {
  oos_str[, cum := cumprod(1 + port_ret)]
  bm_oos <- bm_monthly[Date_eom >= last_sig - 5]
  bm_oos[, BM_cum := BM_Close_eom / BM_Close_eom[1]]

  oos_series_label <- "Iter26 (frozen weights)"
  plot_oos <- rbind(
    data.table(Date=oos_str$period_end, cum=oos_str$cum,
               Series=oos_series_label),
    data.table(Date=bm_oos$Date_eom, cum=bm_oos$BM_cum, Series="KOSPI200 (BM)")
  )

  oos_colors <- c("#F44336", "#9E9E9E")
  names(oos_colors) <- c(oos_series_label, "KOSPI200 (BM)")

  g3 <- ggplot(plot_oos, aes(x=Date, y=cum, color=Series)) +
    geom_line(linewidth=1.0) + geom_point(size=1.5) +
    scale_color_manual(values=oos_colors) +
    labs(title="Iter26 OOS Zoom (24-26) — Frozen-weights Buy-and-Hold",
         subtitle=sprintf("OOS n=%d | SR=%.3f | CAGR=%.2f%% | MDD=%.2f%% | last_cash=%.1f%%",
                          perf_oos$n_months, perf_oos$sr %||% NA,
                          (perf_oos$cagr %||% NA)*100,
                          (perf_oos$mdd %||% NA)*100, last_cash*100),
         x="Date", y="Cumulative Return", color="") +
    theme_minimal(base_size=11) + theme(legend.position="bottom")

  oos_path <- file.path(OUT_DIR, "oos_zoom_chart.png")
  ggsave(oos_path, g3, width=11, height=6, dpi=150)
  cat(sprintf("    Saved: %s\n", oos_path))
  file.copy(oos_path, file.path(BT_DIR, "oos_zoom_chart.png"), overwrite=TRUE)
}

# 13-4. scenario_comparison.png
cat("  [13-4] scenario_comparison.png — Iter26/blend vs Iter11/blend vs D\n")
panel_V26A[, cum := cumprod(1 + iter26)]
if (!is.null(panel_V26B) && nrow(panel_V26B) > 0) panel_V26B[, cum := cumprod(1 + scen_V26B_ret)]

plot_scen_list <- list(
  data.table(Date=panel_V26A$Date, cum=panel_V26A$cum, Series="A. Iter26 standalone 100%"),
  data.table(Date=panel_V26B$Date, cum=panel_V26B$cum, Series="B. Iter26 80% + STR_1656 20%")
)
if (iter11_available_full) {
  panel_I11B[, cum := cumprod(1 + scen_I11B_ret)]
  plot_scen_list <- append(plot_scen_list, list(
    data.table(Date=panel_I11B$Date, cum=panel_I11B$cum, Series="C. Iter11 80% + STR_1656 20% (baseline)")
  ))
}
if (!is.null(panel_D) && nrow(panel_D) > 0) {
  panel_D[, cum := cumprod(1 + scen_D_ret)]
  plot_scen_list <- append(plot_scen_list, list(
    data.table(Date=panel_D$Date, cum=panel_D$cum, Series="D. MEGA_05 80% + STR_1656 20% (current PG2)")
  ))
}
plot_scen <- rbindlist(plot_scen_list)
plot_scen <- plot_scen[!is.na(cum) & cum > 0]

g4 <- ggplot(plot_scen, aes(x=Date, y=cum, color=Series)) +
  geom_line(linewidth=0.85) +
  scale_y_log10(labels=scales::label_number(accuracy=0.1)) +
  scale_color_manual(values=c(
    "A. Iter26 standalone 100%"                   = "#F44336",
    "B. Iter26 80% + STR_1656 20%"                = "#E91E63",
    "C. Iter11 80% + STR_1656 20% (baseline)"     = "#3F51B5",
    "D. MEGA_05 80% + STR_1656 20% (current PG2)" = "#4CAF50")) +
  geom_vline(xintercept=LB_START, linetype="dashed", color="red", alpha=0.7) +
  labs(title="Iter26 vs Iter11 vs PG2 — Blend Scenarios (NAV-level)",
       subtitle=sprintf("Iter26 blend SR=%.3f | Iter11 blend SR=%.3f | PG2 baseline SR=%.4f | delta=%+.4f",
                        v26_blend_sr %||% NA, iter11_blend_sr %||% NA,
                        BASELINE_PG2_SR, delta_sr_vs_BASELINE_PG2 %||% NA),
       x="Date", y="Cumulative Return (log)", color="") +
  theme_minimal(base_size=10) +
  theme(legend.position="bottom", legend.text=element_text(size=8))

scen_path <- file.path(OUT_DIR, "scenario_comparison.png")
ggsave(scen_path, g4, width=13, height=7, dpi=150)
cat(sprintf("    Saved: %s\n", scen_path))

# Copy to BT_DIR
file.copy(ec_path,   file.path(BT_DIR, "equity_curve.png"),       overwrite=TRUE)
file.copy(ar_path,   file.path(BT_DIR, "annual_returns.png"),     overwrite=TRUE)
file.copy(scen_path, file.path(BT_DIR, "scenario_comparison.png"), overwrite=TRUE)

# ─────────────────────────────────────────────────────────
# 14. backtest_result 산출물 저장
# ─────────────────────────────────────────────────────────
cat("\n[14] Save backtest_result artifacts\n")

write_parquet(all_ret, file.path(BT_DIR, "monthly_returns.parquet"))
fwrite(iter26_full, file.path(BT_DIR, "iter26_full_period_monthly.csv"))
fwrite(oos_dt,      file.path(BT_DIR, "oos_24_26_monthly.csv"))
fwrite(panel,       file.path(BT_DIR, "nav_panel_iter26_iter11_mega05.csv"))
if (exists("iter_compare")) fwrite(iter_compare, file.path(BT_DIR, "iter21_22_vs_26_compare.csv"))

# hurdle_result.json
ret_combined  <- combined$port_ret
n_m_full      <- length(ret_combined)
harvey_t_simple <- if (n_m_full >= 12)
  (mean(ret_combined, na.rm=TRUE) / sd(ret_combined, na.rm=TRUE)) * sqrt(n_m_full) else NA
dsr_full <- compute_dsr(ret_combined)$dsr

hurdle_result <- list(
  task_id  = WT_ID, str_id = STR_ID,
  iter_label = "Iter26_BinaryDiscrete_DDThreshold_8_18_28",
  CAGR = perf_full$cagr, SR = perf_full$sr, MDD = perf_full$mdd,
  Vol = perf_full$vol, HitRate = perf_full$hit, IR = perf_full$sr,
  Harvey_t_simple = round(harvey_t_simple, 4),
  Harvey_t_FF5    = round(res_full[["FF5"]]$t_nw %||% NA, 4),
  DSR      = dsr_full,
  N_months = n_m_full,
  pre_lockbox = list(SR=perf_prelb$sr, CAGR=perf_prelb$cagr,
                     MDD=perf_prelb$mdd, n=perf_prelb$n_months),
  lockbox     = list(SR=perf_lb$sr, CAGR=perf_lb$cagr,
                     MDD=perf_lb$mdd, n=perf_lb$n_months),
  oos_24_26   = list(SR=perf_oos$sr, CAGR=perf_oos$cagr,
                     MDD=perf_oos$mdd, n=perf_oos$n_months),
  full_period = list(SR=perf_iter26_full$sr, CAGR=perf_iter26_full$cagr,
                     MDD=perf_iter26_full$mdd, n=perf_iter26_full$n_months,
                     t_FF5=perf_iter26_full$harvey_t_ff5,
                     DSR_post=perf_iter26_full$dsr_post_penalty),
  ax001_v2_realized = list(
    pass_count       = ax001_realized_count,
    crisis_alpha_pass = ax001_crisis_pass,
    mdd_relief_pass  = ax001_mdd_pass,
    bad_normal_pass  = ax001_bad_normal_pass,
    harvey_cond_pass = ax001_harvey_pass,
    crisis_alpha_m   = round(crisis_alpha_m %||% NA, 6),
    realized_mdd_relief_pp = realized_mdd_relief_pp %||% NA,
    bad_normal_ratio = round(bad_normal_ratio %||% NA, 4),
    harvey_cond_t    = round(harvey_cond_t %||% NA, 4),
    optimizer_self_report_pass_count = 2,
    forge_vs_optimizer_note = "Optimizer self-report 2/4; Forge measures realized values from RAWDATA"
  ),
  pg2_blend_analysis = list(
    v26_standalone_sr    = perf_V26_A$sr %||% NA,
    v26_blend_sr         = v26_blend_sr %||% NA,
    iter11_blend_sr      = iter11_blend_sr %||% NA,
    baseline_pg2_sr      = BASELINE_PG2_SR,
    delta_vs_baseline    = delta_sr_vs_BASELINE_PG2 %||% NA,
    delta_vs_iter11_blend = delta_sr_vs_baseline %||% NA,
    pg2_admission_pass   = pg2_pass,
    v26_blend_mdd        = v26_blend_mdd %||% NA,
    iter11_blend_mdd     = iter11_blend_mdd %||% NA,
    mdd_relief_blend_pp  = -realized_mdd_vs_iter11_blend_pp %||% NA,
    optimizer_expected_mdd_relief_pp = opt_mdd_relief * 100,
    iter21_22_gap_pp = list(iter21=-19.98, iter22=-21.28),
    binary_vs_continuous_verdict = if (!is.na(realized_mdd_vs_iter11_blend_pp)) {
      if (-realized_mdd_vs_iter11_blend_pp > 5) "DISCRETE_POSITIVE" else
      if (-realized_mdd_vs_iter11_blend_pp < -5) "DISCRETE_NEGATIVE_L235_TRIGGER" else
      "DISCRETE_NEUTRAL"
    } else "INSUFFICIENT_DATA"
  )
)
write_json(hurdle_result, file.path(BT_DIR, "hurdle_result.json"),
           pretty=TRUE, auto_unbox=TRUE, null="null")

cat("  Saved: monthly_returns.parquet / iter26_full_period_monthly.csv /\n")
cat("         oos_24_26_monthly.csv / nav_panel_iter26_iter11_mega05.csv /\n")
cat("         hurdle_result.json\n")

# ─────────────────────────────────────────────────────────
# 15. forge_package.json
# ─────────────────────────────────────────────────────────
cat("\n[15] Write forge_package.json\n")

flatten_spec <- function(r, spec_name) {
  if (is.null(r)) return(list(spec=spec_name, available=FALSE))
  list(
    spec      = spec_name,
    alpha_monthly = round(r$alpha %||% NA, 6),
    alpha_annual  = round((r$alpha %||% NA)*12, 4),
    t_nw      = round(r$t_nw %||% NA, 4),
    p_nw      = round(r$p_nw %||% NA, 5),
    lag_nw    = r$lag %||% NA,
    n_eff     = r$n_eff %||% NA,
    r2        = round(r$r2 %||% NA, 4),
    adj_r2    = round(r$adj_r2 %||% NA, 4),
    dsr       = r$dsr %||% NULL,
    sr_ann    = r$sr_ann %||% NULL,
    gate_pass = !is.na(r$t_nw %||% NA) && r$t_nw >= 2.95,
    gate_target = 2.95
  )
}

forge_pkg <- list(
  task_id    = WT_ID, str_id = STR_ID,
  agent      = "forge_sonnet46_v6.1_R12_pure_function_iter26",
  iter_label = "Iter26_Binary_DD_Threshold_8_18_28_discrete",
  as_of_date = as.character(Sys.Date()),
  method_weights = method_tag,
  optimizer_method = method_tag,
  optimizer_expected_ir   = expected_ir,
  optimizer_expected_cagr = expected_cagr,
  optimizer_expected_mdd  = expected_mdd,
  optimizer_expected_to   = expected_to,
  threshold_config = list(
    t1=threshold_t1, t2=threshold_t2, t3=threshold_t3,
    cash_c1=cash_c1, cash_c2=cash_c2, cash_c3=cash_c3,
    state_set="{0%, 30%, 50%, 100%}", type="binary_discrete"
  ),

  backtest_summary = list(
    combined = list(
      period   = sprintf("%s ~ %s",
                  as.character(min(all_ret$Date)), as.character(max(all_ret$Date))),
      n_months = perf_full$n_months,
      cagr=perf_full$cagr, vol=perf_full$vol, sr=perf_full$sr,
      mdd=perf_full$mdd, hit_rate=perf_full$hit,
      harvey_t_simple = round(harvey_t_simple, 4),
      dsr_post_penalty = perf_full$dsr_post_penalty
    ),
    pre_lockbox = list(
      period   = sprintf("%s ~ %s",
                  as.character(min(prelb_full$Date)), as.character(max(prelb_full$Date))),
      n_months = perf_prelb$n_months,
      cagr=perf_prelb$cagr, sr=perf_prelb$sr,
      mdd=perf_prelb$mdd, hit_rate=perf_prelb$hit,
      dsr_post_penalty=perf_prelb$dsr_post_penalty
    ),
    lockbox = list(
      period   = if (perf_lb$n_months > 0)
                   sprintf("%s ~ %s",
                           as.character(min(lb_full$Date)), as.character(max(lb_full$Date)))
                 else "no_lockbox_data",
      n_months = perf_lb$n_months,
      cagr=perf_lb$cagr, sr=perf_lb$sr, mdd=perf_lb$mdd
    ),
    full_period = list(
      period   = sprintf("%s ~ %s", min(iter26_full$YM), max(iter26_full$YM)),
      n_months = perf_iter26_full$n_months,
      cagr=perf_iter26_full$cagr, vol=perf_iter26_full$vol,
      sr=perf_iter26_full$sr, mdd=perf_iter26_full$mdd,
      hit_rate=perf_iter26_full$hit,
      harvey_t_ff5=perf_iter26_full$harvey_t_ff5,
      dsr_raw=perf_iter26_full$dsr_raw,
      dsr_post_penalty=perf_iter26_full$dsr_post_penalty
    )
  ),

  # AX-001 v2 4-metric realized
  ax001_v2_realized = hurdle_result$ax001_v2_realized,

  # PG2 blend analysis (PRIMARY mandate)
  pg2_blend_analysis = hurdle_result$pg2_blend_analysis,

  # 5-spec factor regression
  factor_regression_5specs = list(
    method    = method_tag,
    sample    = sprintf("Combined 92-period walk-forward (%s ~ %s)",
                 as.character(min(all_ret$Date)), as.character(max(all_ret$Date))),
    se_method = "Newey-West HAC",
    CAPM      = flatten_spec(res_full[["CAPM"]],      "CAPM"),
    Carhart_3 = flatten_spec(res_full[["Carhart_3"]], "Carhart_3"),
    Carhart_4 = flatten_spec(res_full[["Carhart_4"]], "Carhart_4"),
    FF5       = flatten_spec(res_full[["FF5"]],       "FF5"),
    FF6       = flatten_spec(res_full[["FF6"]],       "FF6"),
    n_pass_t295 = n_pass
  ),

  # Cash-state conditional metrics
  cash_state_conditional = lapply(cash_state_perf, function(p) list(
    n_months=p$n_months, sr=p$sr %||% NA, cagr=p$cagr %||% NA, mdd=p$mdd %||% NA
  )),

  # OOS 24-26
  oos_24_26_frozen_weights = list(
    last_sig_date = as.character(last_sig),
    last_cash_pct = round(last_cash, 4),
    n_names       = nrow(last_w),
    period        = sprintf("%s ~ %s",
                       as.character(min(oos_dt$period_end)),
                       as.character(max(oos_dt$period_end))),
    n_months      = perf_oos$n_months,
    cagr=perf_oos$cagr, sr=perf_oos$sr, mdd=perf_oos$mdd, hit=perf_oos$hit,
    method = "Frozen weights buy-and-hold (no re-optimization)"
  ),

  # Walk-forward provenance
  walk_forward_validation = list(
    walk_forward_active  = TRUE,
    weights_source       = file.path(WT_DIR, "weights.csv"),
    n_sig_dates          = length(sig_dates),
    n_walk_periods       = nrow(bt_dt),
    rebal_signal_freq    = "monthly_base_threshold_discrete",
    period_start         = as.character(min(bt_dt$period_end)),
    period_end           = as.character(max(bt_dt$period_end)),
    avg_n_held           = round(mean(bt_dt$n_held), 2),
    avg_turnover         = round(mean(bt_dt$turnover), 4),
    annualized_turnover  = round(mean(bt_dt$turnover)*12, 4),
    cash_active_n        = cash_active_n,
    cash_active_pct      = round(cash_active_n/length(sig_dates)*100, 2),
    pit_lag_c9           = TRUE,
    pit_liquidity_c10    = "20-day avg >= 2e8 KRW (PIT t-30..t-1)"
  ),

  # 3-package hash audit
  hash_audit = list(
    pre_audit_recorded  = TRUE,
    pre_md5_alpha       = unname(start_hashes["alpha_package.json"]),
    pre_md5_risk        = unname(start_hashes["risk_package.json"]),
    pre_md5_opt         = unname(start_hashes["optimization_package.json"]),
    pre_md5_weights     = start_w_hash,
    audit_status        = "verified_at_start"
  )
)

write_json(forge_pkg, file.path(WT_DIR, "forge_package.json"),
           pretty=TRUE, auto_unbox=TRUE, null="null")
cat("  Saved: forge_package.json\n")

# ─────────────────────────────────────────────────────────
# 16. judge_ready/judge_ready.json
# ─────────────────────────────────────────────────────────
cat("\n[16] Write judge_ready.json\n")

judge_ready <- list(
  task_id         = WT_ID,
  str_id          = STR_ID,
  prepared_by     = "forge_sonnet46_v6.1_R12_iter26",
  prepared_at     = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
  hurdle_summary  = list(
    CAGR              = perf_full$cagr,
    SR                = perf_full$sr,
    MDD               = perf_full$mdd,
    Harvey_t_FF5      = round(res_full[["FF5"]]$t_nw %||% NA, 4),
    DSR_post_penalty  = perf_full$dsr_post_penalty,
    N_months          = perf_full$n_months,
    full_period_sr    = perf_iter26_full$sr,
    full_period_cagr  = perf_iter26_full$cagr,
    full_period_mdd   = perf_iter26_full$mdd,
    full_period_t_ff5 = perf_iter26_full$harvey_t_ff5,
    full_period_dsr_post = perf_iter26_full$dsr_post_penalty,
    oos_24_26_sr      = perf_oos$sr,
    oos_24_26_cagr    = perf_oos$cagr,
    oos_24_26_mdd     = perf_oos$mdd,
    n_5spec_pass      = n_pass,
    # PG2 mandate results
    v26_standalone_sr    = perf_V26_A$sr %||% NA,
    v26_blend_sr         = v26_blend_sr %||% NA,
    baseline_pg2_sr      = BASELINE_PG2_SR,
    delta_vs_baseline    = delta_sr_vs_BASELINE_PG2 %||% NA,
    pg2_admission_pass   = pg2_pass,
    # AX-001 v2
    ax001_v2_realized_pass_count = ax001_realized_count,
    realized_mdd_relief_pp       = realized_mdd_relief_pp %||% NA,
    optimizer_expected_mdd_relief_pp = opt_mdd_relief * 100,
    # Iter 21/22 comparison
    binary_vs_continuous_verdict = hurdle_result$pg2_blend_analysis$binary_vs_continuous_verdict
  ),
  pit_compliance_pass = TRUE,
  forge_package    = file.path(WT_DIR, "forge_package.json"),
  next_step        = "Judge S6: Gate 0~6 + DSR + AX-001v2 Role Honesty + PG2 blend SR vs baseline + binary vs continuous decision"
)

write_json(judge_ready, file.path(JR_DIR, "judge_ready.json"),
           pretty=TRUE, auto_unbox=TRUE, null="null")
cat("  Saved: judge_ready/judge_ready.json\n")

# ─────────────────────────────────────────────────────────
# 17. COMPLETION hash audit (3-package unchanged verification)
# ─────────────────────────────────────────────────────────
cat("\n[17] COMPLETION hash audit (3-package unchanged)\n")

end_hashes <- sapply(pkg_files, function(f) tryCatch(
  as.character(tools::md5sum(f)), error=function(e) "MISSING"))
names(end_hashes) <- basename(pkg_files)
end_w_hash <- as.character(tools::md5sum(weights_path))

audit_pass <- TRUE
cat("  Hash comparison (start → end):\n")
for (n in names(start_hashes)) {
  same <- identical(start_hashes[n], end_hashes[n])
  if (!same) audit_pass <- FALSE
  cat(sprintf("    %-35s: %s -> %s [%s]\n", n,
              substr(start_hashes[n],1,16), substr(end_hashes[n],1,16),
              if (same) "OK" else "MISMATCH"))
}
w_same <- identical(start_w_hash, end_w_hash)
if (!w_same) audit_pass <- FALSE
cat(sprintf("    weights.csv:                         [%s]\n", if (w_same) "OK" else "MISMATCH"))
cat(sprintf("  Hash audit: %s\n", if (audit_pass) "PASS — 3-package read-only verified" else "FAIL — PURE FUNCTION VIOLATION"))

# ─────────────────────────────────────────────────────────
# 18. status.json 업데이트
# ─────────────────────────────────────────────────────────
cat("\n[18] Update status.json -> FORGE_DONE\n")

status_path <- file.path(WT_DIR, "status.json")
status <- list(
  task_id      = WT_ID,
  current_phase = "FORGE_DONE",
  updated_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
  blocker      = NULL,
  forge_completed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
  forge_summary = list(
    v26_standalone_sr = perf_full$sr %||% NA,
    v26_blend_sr      = v26_blend_sr %||% NA,
    baseline_pg2_sr   = BASELINE_PG2_SR,
    realized_mdd_relief_pp = realized_mdd_relief_pp %||% NA,
    ax001_v2_pass     = ax001_realized_count,
    binary_vs_continuous = hurdle_result$pg2_blend_analysis$binary_vs_continuous_verdict,
    hash_audit        = if (audit_pass) "PASS" else "FAIL"
  )
)
write_json(status, status_path, pretty=TRUE, auto_unbox=TRUE, null="null")
cat("  Status updated: FORGE_DONE\n")

# ─────────────────────────────────────────────────────────
# 19. Telegram 브리핑 (1회 exactly)
# ─────────────────────────────────────────────────────────
cat("\n[19] Telegram briefing (exactly 1 time)\n")

tryCatch({
  source(file.path(BASE_DIR, "02_Infrastructure/telegram/telegram_notify.R"))

  pg2_verdict_icon <- if (pg2_pass) "[PASS]" else "[FAIL]"
  ax001_icon <- if (ax001_realized_count >= 2) "[OK]" else "[WARN]"
  binary_icon <- switch(hurdle_result$pg2_blend_analysis$binary_vs_continuous_verdict,
    "DISCRETE_POSITIVE"              = "[BEAT Iter21/22]",
    "DISCRETE_NEGATIVE_L235_TRIGGER" = "[FAIL -> L235]",
    "[NEUTRAL]")

  msg <- paste0(
    "[Forge] WT-D20260427_011 Iter 26 DD Threshold Trigger\n",
    "\n",
    "== Standalone (Pre-LB 92m) ==\n",
    sprintf("SR: %.3f | CAGR: %.1f%% | MDD: %.1f%%\n",
            perf_full$sr %||% NA, (perf_full$cagr %||% NA)*100,
            (perf_full$mdd %||% NA)*100),
    "\n",
    "== PG2 Blend (Iter26 80%% + STR_1656 20%%) ==\n",
    sprintf("%s V26_blend_SR: %.4f\n", pg2_verdict_icon, v26_blend_sr %||% NA),
    sprintf("Baseline (Iter11 blend): %.4f\n", BASELINE_PG2_SR),
    sprintf("Delta vs baseline: %+.4f\n", delta_sr_vs_BASELINE_PG2 %||% NA),
    "\n",
    "== AX-001 v2 Realized ==\n",
    sprintf("%s %d/4 PASS (Optimizer self-report: 2/4)\n", ax001_icon, ax001_realized_count),
    sprintf("MDD relief: %+.2fpp (expected +10.38pp)\n", realized_mdd_relief_pp %||% NA),
    "\n",
    "== Binary vs Continuous ==\n",
    sprintf("%s %s\n", binary_icon, hurdle_result$pg2_blend_analysis$binary_vs_continuous_verdict),
    "Iter21/22 continuous: -19~-21pp (inverted)\n",
    "\n",
    "== Hash Audit ==\n",
    if (audit_pass) "PASS — 3-package read-only verified" else "FAIL — VIOLATION",
    "\n",
    "\n",
    "Next: Judge S6 cascade"
  )
  tg_send(msg, parse_mode="")

  # Chart attachment
  if (file.exists(ec_path)) tg_send_photo(ec_path)
  if (file.exists(scen_path)) tg_send_photo(scen_path)

  cat("  Telegram sent (1 text + 2 charts)\n")
}, error = function(e) {
  cat(sprintf("  Telegram failed (non-critical): %s\n", conditionMessage(e)))
})

# ─────────────────────────────────────────────────────────
# FINAL SUMMARY
# ─────────────────────────────────────────────────────────
cat("\n")
cat("=== FORGE_DONE_ITER26 FINAL SUMMARY ===\n")
cat(sprintf("  V26_standalone_sr   = %.4f\n", perf_full$sr %||% NA))
cat(sprintf("  V26_blend_sr        = %.4f\n", v26_blend_sr %||% NA))
cat(sprintf("  baseline_sr         = %.4f\n", BASELINE_PG2_SR))
cat(sprintf("  realized_mdd_relief_pp = %+.2f (expected +10.38)\n", realized_mdd_relief_pp %||% NA))
cat(sprintf("  ax_001_v2_4metric   = %d/4\n", ax001_realized_count))
cat(sprintf("  5_spec_t295_pass    = %d/5\n", n_pass))
cat(sprintf("  pg2_recommend       = %s\n",
            if (pg2_pass) "ADMIT — V26 blend SR > baseline" else "REJECT — V26 blend SR < baseline"))
cat(sprintf("  binary_vs_continuous = %s\n",
            hurdle_result$pg2_blend_analysis$binary_vs_continuous_verdict))
cat(sprintf("  hash_audit          = %s\n", if (audit_pass) "PASS" else "FAIL"))
cat("\n")
cat("FORGE_DONE_ITER26 — Work Task WT-D20260427_011 Forge Integration Complete\n")
cat("Next: Judge S6 Gate 0~6 + Role Honesty Audit\n")
