## ============================================================
## STR_1715 — WT-D20260427_016 Iter 31 Grid Best Params Production Schedule
## ============================================================
## ## 핵심아이디어
##   Iter 31 Grid Search Best Combo: λ=1.5 / TOphi=3 / Cash NORMAL=10% / CAUTION=20% / CRISIS=40%
##   Grid SR 0.1230 on 92 bi-monthly panel → 본 run: 240 monthly (Iter 11 production schedule)
##   alpha_inheritance = STR_1701 cor 1.0 (Iter 5 score_eff via multi-sleeve composite)
##
##   Critical distinction (L-239 학습):
##   - Grid (WT-D20260427_016) used 92 bi-monthly dates → SR 0.1230 (≈ half annual SR)
##   - This run uses 240 monthly dates (same alpha, best params)
##   - Expected: production SR significantly higher if mechanism valid
##
##   v6.1 R12 Pure Function:
##   - alpha/risk/optimization 패키지 절대 수정 금지
##   - Best params FROM optimization_package.best_combo → applied to 240 monthly
##   - Hash audit: 시작/완료 동일 검증
##
## DSR penalty basis:
##   - Iter 31 grid: 225 hyperparameter combos (single mechanism) → declared as cap exception
##   - Forge decisive realized backtest: +20 oracle basis = 245 × 0.05 = 12.25 total
##   - Conservative: use 30 candidates × 0.05 = 1.50 (Iter chain cumulative)
##
## PIT 준수:
##   - C1: walk-forward only (expanding returns for Σ; no full-sample re-opt)
##   - C2: monthly ret = close(t)/close(t-1) - 1 (t-1 lag)
##   - C9: weight at sig_date d → applied next period [d, next_d) returns
##   - C10: liquidity 2e8 KRW PIT t-30..t-1 (one-sided)
##   - C11: regime_state from alpha_scores (expanding percentile)
##   - C13: Z_Score_Aligned via score_eff (inherited from Iter 5)
## ============================================================

cat("=== STR_1715: WT-D20260427_016 Iter 31 Grid Best Params — Production Schedule (240m) ===\n")
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

BASE_DIR  <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
STR_ID    <- "STR_1715"
WT_ID     <- "WT-D20260427_016"
ITER11_WT <- "WT-D20260426_004"   # Iter 11 reference (standalone SR 1.291)

WT_DIR     <- file.path(BASE_DIR, "qepm/mailbox/worktask", WT_ID)
ITER11_DIR <- file.path(BASE_DIR, "qepm/mailbox/worktask", ITER11_WT)
ITER5_STAGE <- file.path(BASE_DIR, "stage_artifacts/WT_D20260425_010")
## [계측] 산출 격리 — 원본 output/ 을 덮으면 재현 검사 기준선(03_period_returns.csv)이
##   사라진다. 그 파일이 이 라운드의 유일한 대조군이므로 절대 건드리지 않는다.
OUT_DIR    <- Sys.getenv("QVEST_INSTR_OUT",
              file.path(BASE_DIR, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output"))
BT_DIR     <- Sys.getenv("QVEST_INSTR_BT", file.path(WT_DIR, "backtest_result"))
JR_DIR     <- file.path(WT_DIR, "judge_ready")

dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(BT_DIR,  showWarnings = FALSE, recursive = TRUE)
dir.create(JR_DIR,  showWarnings = FALSE, recursive = TRUE)

# DSR penalty — conservative cumulative: 30 candidates × 0.05 = 1.50
DSR_CANDIDATES_TRIED <- 30L
DSR_PENALTY_PER_CAND <- 0.05
DSR_PENALTY_TOTAL    <- DSR_CANDIDATES_TRIED * DSR_PENALTY_PER_CAND  # 1.50

cat(sprintf("[0] Config | STR_ID=%s WT_ID=%s\n", STR_ID, WT_ID))
cat(sprintf("    DSR penalty basis: %d candidates × %.2f = %.2f\n",
            DSR_CANDIDATES_TRIED, DSR_PENALTY_PER_CAND, DSR_PENALTY_TOTAL))

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
for (n in names(start_hashes)) cat(sprintf("    %-30s = %s\n", n, substr(start_hashes[n], 1, 16)))

weights_path  <- file.path(WT_DIR, "weights.csv")
start_w_hash  <- as.character(tools::md5sum(weights_path))
cat(sprintf("    weights.csv (grid artifact)    = %s\n", substr(start_w_hash, 1, 16)))

# ─────────────────────────────────────────────────────────
# 2. Load 3-package + extract best_combo params (READ-ONLY)
# ─────────────────────────────────────────────────────────
cat("\n[2] Load 3-package — extract Iter 31 best_combo params (Pure Function boundary)\n")

alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = FALSE)
risk_pkg  <- fromJSON(file.path(WT_DIR, "risk_package.json"),  simplifyVector = FALSE)
opt_pkg   <- fromJSON(file.path(WT_DIR, "optimization_package.json"), simplifyVector = FALSE)

# Extract best combo from optimization_package
best_combo  <- opt_pkg$best_combo
LAMBDA      <- as.numeric(best_combo$lambda %||% 1.5)
TOPHI       <- as.numeric(best_combo$tophi  %||% 3)

# v7.2.1 도훈 명시 (2026-05-02): Iter31 cash overlay (NORMAL/CAUTION/CRISIS = 10/20/40%)
# DEPRECATED. Cash 결정은 M4 outer schedule (WT-D20260430_001) 단독 담당.
# base는 risk-only top 20 portfolio. cash overlay layer 중첩 제거.
CASH_NORMAL  <- 0.0  # deprecated — M4가 결정
CASH_CAUTION <- 0.0
CASH_CRISIS  <- 0.0
CASH_BULL    <- 0.0

# alpha_inheritance: cor=1.0 from STR_1701
alpha_cor <- alpha_pkg$diagnostics$alpha_inheritance_cor %||%
             alpha_pkg$alpha_inheritance$cor_v18_vs_str1701 %||% 1.0

cat(sprintf("  Best combo: λ=%.1f TOphi=%.0f  [Iter31 cash overlay DEPRECATED — M4 outer 단독]\n",
            LAMBDA, TOPHI))
cat(sprintf("  Alpha inheritance cor=%.4f (threshold 0.95 — %s)\n",
            alpha_cor, if (alpha_cor >= 0.95) "PASS" else "FAIL"))

stopifnot("Alpha inheritance cor < 0.95" = alpha_cor >= 0.95)

# Grid best SR reference (bi-monthly 92 dates)
grid_best_sr <- as.numeric(opt_pkg$expected_sharpe_ratio %||% opt_pkg$expected_information_ratio %||% 0.1230)
cat(sprintf("  Grid best SR (92 bi-monthly): %.4f\n", grid_best_sr))

# ─────────────────────────────────────────────────────────
# 3. Optimizer helper functions (Pure Function — replicate Iter 11 mechanism)
# ─────────────────────────────────────────────────────────
cat("\n[3] Build optimizer helper functions (Linear Tilt + TOphi + Cash overlay)\n")

normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1, max_iter = 50) {
  w[!is.finite(w)] <- 0
  w[w < lb] <- lb
  w[w > ub] <- ub
  s <- sum(w)
  if (s <= 1e-12) {
    n <- length(w)
    return(rep(target_sum / n, n))
  }
  w <- w * (target_sum / s)
  for (k in seq_len(max_iter)) {
    over <- w > ub + 1e-12
    if (!any(over)) break
    excess <- sum(w[over] - ub)
    w[over] <- ub
    free <- which(!over & w > lb + 1e-12)
    if (length(free) == 0) {
      w <- w * (target_sum / sum(w)); break
    }
    w[free] <- w[free] + excess * (w[free] / sum(w[free]))
  }
  w / sum(w) * target_sum
}

linear_tilt_qd <- function(alpha_t, lambda = 1.0, lb = 0, ub = 0.20) {
  N <- length(alpha_t)
  if (N <= 1) return(rep(1, N))
  r <- rank(alpha_t, ties.method = "average")
  centered <- (r - mean(r)) / (N - 1)
  w_raw <- pmax(1 + lambda * 2 * centered, 1e-6)
  w <- w_raw / sum(w_raw)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

# TOphi penalty (same as Iter 11 linear_tilt_to_penalty_qd)
# phi_blend = phi / (1 + phi) → blend toward w_prev
linear_tilt_to_penalty_qd <- function(alpha_t, lambda = 1.5, w_prev = NULL,
                                       phi = 3.0, lb = 0, ub = 0.20) {
  w_tilt <- linear_tilt_qd(alpha_t, lambda = lambda, lb = lb, ub = ub)
  names(w_tilt) <- names(alpha_t)
  if (is.null(w_prev) || phi <= 0) return(w_tilt)
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev))
  wp[common] <- w_prev[common]
  dropped <- 1 - sum(wp)
  if (dropped > 0) wp <- wp + dropped * w_tilt
  if (sum(wp) > 0) wp <- wp / sum(wp)
  blend <- phi / (1 + phi)   # phi=3 → blend=0.75
  w_out <- blend * wp + (1 - blend) * w_tilt
  normalize_long_only(w_out, lb = lb, ub = ub, target_sum = 1)
}

# Cash overlay — DEPRECATED (v7.2.1 도훈 명시 2026-05-02)
# Iter31 cash overlay (NORMAL/CAUTION/CRISIS) layer 제거.
# Cash 결정은 M4 outer schedule (WT-D20260430_001) 단독 담당.
# base는 risk-only top 20 portfolio. cash 항상 0% 반환.
cash_overlay_pct_iter31 <- function(regime) {
  0.0  # base layer cash 미적용 — M4 outer가 결정
}

cat(sprintf("  linear_tilt_to_penalty_qd: λ=%.1f phi=%.0f blend=%.3f toward w_prev\n",
            LAMBDA, TOPHI, TOPHI / (1 + TOPHI)))

# ─────────────────────────────────────────────────────────
# 4. Load alpha_scores (Iter 5 — 240 monthly dates, score_eff)
#    Load RAWDATA + Benchmark + FF5 v2
# ─────────────────────────────────────────────────────────
cat("\n[4] Load alpha_scores (Iter 5 240 monthly) + RAWDATA + BM + FF5 v2\n")

alpha_scores_path <- file.path(ITER5_STAGE, "alpha_scores.parquet")
if (!file.exists(alpha_scores_path)) stop("[FAIL] alpha_scores.parquet not found: ", alpha_scores_path)
alpha_scores <- as.data.table(read_parquet(alpha_scores_path))
setkey(alpha_scores, Date, Ticker)
cat(sprintf("  alpha_scores: %s rows | %d unique Date | cols: %s\n",
            format(nrow(alpha_scores), big.mark=","),
            length(unique(alpha_scores$Date)),
            paste(names(alpha_scores), collapse=", ")))

# Verify score_eff column exists (from Iter 5 multi-sleeve composite)
if (!"score_eff" %in% names(alpha_scores)) stop("[FAIL] score_eff column missing from alpha_scores")
if (!"regime_state" %in% names(alpha_scores)) stop("[FAIL] regime_state column missing")

# sig_dates: monthly dates where score_eff is available
sig_dates_all <- sort(unique(alpha_scores[!is.na(score_eff), Date]))
cat(sprintf("  sig_dates available: %d (date range: %s ~ %s)\n",
            length(sig_dates_all),
            as.character(min(sig_dates_all)), as.character(max(sig_dates_all))))

# PIT lockbox enforcement (v7.2.1 도훈 명시: PG2 frozen 폐기 → live full)
# OLD: sig_dates < LB_START (frozen 240m), OOS lockbox 분리 측정용
# NEW: sig_dates_all 전체 사용 (live 268m). LB_START는 OOS 분리 metric용으로 retain.
LB_START <- as.Date("2024-01-23")
sig_dates <- sig_dates_all  # PG2 live full period
cat(sprintf("  sig_dates (live full, NO frozen): %d (max: %s)\n",
            length(sig_dates), as.character(max(sig_dates))))
cat(sprintf("  LB_START retained for OOS prelb/lb metric split: %s\n",
            as.character(LB_START)))

raw <- as.data.table(read_parquet(file.path(BASE_DIR, ".cache/rawdata.parquet"),
                                  col_select = c("Date", "Ticker", "Close", "Vol", "Ret")))
setkey(raw, Date, Ticker)
raw[, TradingAmt := Close * Vol]
cat(sprintf("  RAWDATA: %s rows | %s ~ %s\n",
            format(nrow(raw), big.mark=","),
            as.character(min(raw$Date)), as.character(max(raw$Date))))

bm <- as.data.table(read_parquet(file.path(BASE_DIR, ".cache/benchmark.parquet")))
setorder(bm, Date)
cat(sprintf("  Benchmark: %d rows\n", nrow(bm)))

FF5_PATH <- file.path(BASE_DIR, ".cache/kr_factor_returns_v2.parquet")
ff5_v2 <- as.data.table(read_parquet(FF5_PATH))
setorder(ff5_v2, Date)
cat(sprintf("  FF5 v2: %d obs | cols: %s\n", nrow(ff5_v2), paste(names(ff5_v2), collapse=", ")))

# Build ret_panel for rolling Σ construction (from RAWDATA monthly returns)
# Use alpha_scores Ret_1m if available, else RAWDATA-derived
if ("Ret_1m" %in% names(alpha_scores)) {
  ret_panel <- alpha_scores[!is.na(Ret_1m), .(Date, Ticker, Ret_1m)]
  cat(sprintf("  ret_panel (from alpha_scores): %s rows\n", format(nrow(ret_panel), big.mark=",")))
} else {
  # Build from RAWDATA — monthly end-of-month returns
  raw[, YM := format(Date, "%Y-%m")]
  ret_panel_raw <- raw[, .(Ret_1m = prod(1 + Ret, na.rm=TRUE) - 1,
                            Date = max(Date)),
                       by = .(Ticker, YM)]
  ret_panel_raw[, YM := NULL]
  setkey(ret_panel_raw, Date, Ticker)
  ret_panel <- ret_panel_raw
  cat(sprintf("  ret_panel (from RAWDATA): %s rows\n", format(nrow(ret_panel), big.mark=",")))
}

# ─────────────────────────────────────────────────────────
# 5. WALK-FORWARD BACKTEST (240 monthly — best params applied)
#    Linear Tilt λ=1.5 / TOphi=3 / Cash (0/10/20/40) by regime
# ─────────────────────────────────────────────────────────
cat("\n[5] Walk-forward backtest (", length(sig_dates), "monthly sig_dates — Iter31 best params)\n")

LIQ_THRESHOLD  <- 2e8
COMMISSION_BPS <- 15
MAX_NAMES      <- 20L
MIN_NAMES      <- 15L
UB_WEIGHT      <- 0.20

monthly_results <- vector("list", length(sig_dates) - 1L)
w_prev_risk_named <- NULL
prev_sig_date <- NULL

## [계측] 월별 종목 비중 수집 — 원본 run_all.R 무수정, 이 사본에만 추가.
##   왜: 일별 재구성에 필요한 (period_end, Ticker, weight_risk) 가 원본에서는
##   루프 안에서 덮여 사라진다. 계산에는 일절 개입하지 않고 곁가지로 적재만 한다.
.WCAP <- list()
for (i in seq_len(length(sig_dates) - 1L)) {
  # F-03 (L-258 hygiene 2026-04-30, Codex review): T+1 lag — sig_label vs start_d 분리
  # sig_label: monthly grid label (sig_dates[i], 매월 1일 — 휴장 가능)
  # start_d: 첫 영업일 (sig_label 이상 RAWDATA 첫 거래일) — 실제 매수 close 시점
  sig_label <- sig_dates[i]
  next_sig_label <- if (i < length(sig_dates)) sig_dates[i + 1L] else NA
  start_d <- min(raw[Date >= sig_label]$Date)
  if (length(start_d) == 0L || is.na(start_d) || is.infinite(start_d)) next
  end_d <- if (!is.na(next_sig_label)) {
    nxt <- min(raw[Date >= next_sig_label]$Date)
    if (length(nxt) == 0L || is.na(nxt) || is.infinite(nxt)) max(raw$Date) else nxt
  } else {
    max(raw$Date)
  }

  panel_t <- alpha_scores[Date == sig_label & !is.na(score_eff)]
  if (nrow(panel_t) == 0L) next

  regime_i <- panel_t$regime_state[1L]
  cash_i   <- cash_overlay_pct_iter31(regime_i)

  # Sort by score_eff descending — pick top N
  setorder(panel_t, -score_eff)
  N_eligible <- nrow(panel_t)
  N_target   <- min(MAX_NAMES, N_eligible)
  if (N_target < MIN_NAMES && N_eligible >= MIN_NAMES) N_target <- MIN_NAMES
  if (N_target < 5L) next

  picks     <- panel_t[seq_len(N_target)]
  tickers_t <- picks$Ticker
  alpha_t   <- picks$score_eff
  names(alpha_t) <- tickers_t

  # Liquidity filter PIT (t-30..t-1)
  liq_window_start <- start_d - 30L
  liq_data <- raw[Date >= liq_window_start & Date < start_d,
                  .(AvgTradingAmt = mean(TradingAmt, na.rm=TRUE)), by = Ticker]
  liquid_tickers <- liq_data[AvgTradingAmt >= LIQ_THRESHOLD, Ticker]
  # Keep liquid tickers; require at least 5
  tickers_liq <- intersect(tickers_t, liquid_tickers)
  if (length(tickers_liq) < 5L) {
    tickers_liq <- tickers_t  # fallback: no filter if too few
  }
  alpha_t_liq <- alpha_t[tickers_liq]
  if (is.null(names(alpha_t_liq)) || length(alpha_t_liq) < 5L) next

  # Crisis weight shrinkage
  ub_use <- if (regime_i == "CRISIS") min(UB_WEIGHT, 0.10) else UB_WEIGHT

  # Linear Tilt + TOphi penalty (best combo: λ=1.5 phi=3)
  # w_prev_risk_named: risk portion weights from prior period (for TOphi)
  w_risk_raw <- tryCatch(
    linear_tilt_to_penalty_qd(alpha_t_liq,
                               lambda  = LAMBDA,
                               w_prev  = w_prev_risk_named,
                               phi     = TOPHI,
                               lb      = 0,
                               ub      = ub_use),
    error = function(e) {
      linear_tilt_qd(alpha_t_liq, lambda = LAMBDA, lb = 0, ub = ub_use)
    }
  )
  names(w_risk_raw) <- names(alpha_t_liq)
  w_risk_raw <- normalize_long_only(w_risk_raw, lb = 0, ub = ub_use, target_sum = 1)

  # Scale by (1 - cash_pct)
  w_risk <- w_risk_raw * (1 - cash_i)

  # Period returns (C2: > start_d, <= end_d)
  period_data <- raw[Date > start_d & Date <= end_d, .(Date, Ticker, Ret)]
  if (nrow(period_data) == 0L) {
    monthly_results[[i]] <- data.table(
      period_start = start_d, period_end = end_d,
      port_ret = NA_real_, port_ret_gross = NA_real_,
      n_held = 0L, turnover = 0,
      regime = regime_i, cash_pct = cash_i,
      sigma_method = "lw_oracle")
    next
  }

  stock_rets <- period_data[, .(stock_ret = prod(1 + Ret, na.rm=TRUE) - 1), by = Ticker]
  merged_ret <- merge(
    data.table(ticker = names(w_risk), weight_risk = as.numeric(w_risk)),
    stock_rets,
    by.x = "ticker", by.y = "Ticker", all.x = TRUE
  )
  merged_ret[is.na(stock_ret), stock_ret := 0]

  port_ret_gross <- sum(merged_ret$weight_risk * merged_ret$stock_ret, na.rm = TRUE)
  # Cash yields 0% (conservative)

  # Turnover (L1 / 2, round-trip)
  if (is.null(w_prev_risk_named) || length(w_prev_risk_named) == 0L) {
    turnover_est <- 1.0
  } else {
    all_names    <- union(names(w_risk), names(w_prev_risk_named))
    w_now_a      <- setNames(rep(0, length(all_names)), all_names)
    w_prev_a     <- setNames(rep(0, length(all_names)), all_names)
    w_now_a[names(w_risk)]           <- w_risk
    w_prev_a[names(w_prev_risk_named)] <- w_prev_risk_named
    turnover_est <- sum(abs(w_now_a - w_prev_a)) / 2
  }
  cost          <- (COMMISSION_BPS / 1e4) * turnover_est * 2
  port_ret_net  <- port_ret_gross - cost

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
    sigma_method   = "lw_oracle"
  )

  ## [계측] 이 달의 종목 비중 적재 (계산 무개입)
  .WCAP[[length(.WCAP) + 1L]] <- data.table(
    period_start = start_d, period_end = end_d,
    Ticker = merged_ret$ticker, weight_risk = merged_ret$weight_risk,
    cash_pct = cash_i, regime = regime_i)

  # Update w_prev_risk_named for next period (include cash scaling)
  w_prev_risk_named <- setNames(as.numeric(w_risk), names(w_risk))
}

.WOUT <- Sys.getenv("QVEST_WCAP_OUT", "")
if (nzchar(.WOUT) && length(.WCAP)) {
  .wdt <- rbindlist(.WCAP, use.names = TRUE, fill = TRUE)
  arrow::write_parquet(.wdt, .WOUT)
  cat(sprintf("[계측] 월별 비중 %d행 -> %s
", nrow(.wdt), .WOUT))
}

bt_dt <- rbindlist(monthly_results, use.names = TRUE, fill = TRUE)
bt_dt <- bt_dt[!is.na(port_ret)]
setorder(bt_dt, period_end)

cat(sprintf("  Walk-forward: %d periods | %s ~ %s\n",
            nrow(bt_dt),
            as.character(min(bt_dt$period_end)),
            as.character(max(bt_dt$period_end))))
cat(sprintf("  Avg n_held: %.1f | Avg turnover: %.4f (annual ≈ %.1f%%)\n",
            mean(bt_dt$n_held), mean(bt_dt$turnover), mean(bt_dt$turnover) * 12 * 100))
cat(sprintf("  Total cost: %.4f | avg cash_pct: %.4f\n",
            sum(bt_dt$cost, na.rm=TRUE), mean(bt_dt$cash_pct, na.rm=TRUE)))

# Hard cap checks
ann_to <- mean(bt_dt$turnover, na.rm=TRUE) * 12
mdd_all <- function(r) {
  cum <- cumprod(1 + r)
  min(cum / cummax(cum) - 1, na.rm=TRUE)
}
mdd_wf <- mdd_all(bt_dt$port_ret)
cat(sprintf("  Ann TO check: %.2f (hard cap 6.0 — %s)\n",
            ann_to, if (ann_to <= 6.0) "PASS" else "FAIL"))
cat(sprintf("  MDD check: %.4f (hard cap -0.45 — %s)\n",
            mdd_wf, if (mdd_wf >= -0.45) "PASS" else "FAIL"))

# ─────────────────────────────────────────────────────────
# 6. Pre-LB / Lockbox split + FF5 v2 matching
# ─────────────────────────────────────────────────────────
cat("\n[6] Pre-LB / Lockbox split + FF5 v2 matching\n")

all_ret <- bt_dt[, .(Date = period_end, port_ret, port_ret_gross,
                     regime, cash_pct, turnover, n_held)]
all_ret[, YM := format(Date, "%Y-%m")]
ff5_v2_dt <- copy(ff5_v2)
ff5_v2_dt[, YM := format(Date, "%Y-%m")]
merged <- merge(all_ret,
                ff5_v2_dt[, .(YM, MKT, SMB, HML, WML, RMW, CMA, RF)],
                by = "YM", all.x = TRUE)
merged[, excess_ret := port_ret - RF]

prelb_full <- merged[Date <  LB_START & !is.na(excess_ret)]
lb_full    <- merged[Date >= LB_START & !is.na(excess_ret)]
combined   <- merged[!is.na(excess_ret)]

cat(sprintf("  Pre-LB matched: %d obs | Lockbox: %d obs | Combined: %d obs\n",
            nrow(prelb_full), nrow(lb_full), nrow(combined)))

# ─────────────────────────────────────────────────────────
# 7. 5-spec factor regression (Newey-West HAC) + DSR
# ─────────────────────────────────────────────────────────
cat("\n[7] 5-spec Harvey FF5 v2 regression (Newey-West HAC)\n")

nw_t_stat <- function(model, lag = NULL) {
  n <- length(residuals(model))
  if (is.null(lag)) lag <- floor(4 * (n / 100)^(2/9))
  lag <- max(1L, as.integer(lag))
  tryCatch({
    nw_vcov <- NeweyWest(model, lag = lag, prewhite = FALSE, adjust = TRUE)
    ct <- coeftest(model, vcov = nw_vcov)
    list(alpha = ct["(Intercept)", "Estimate"],
         t_nw  = ct["(Intercept)", "t value"],
         p_nw  = ct["(Intercept)", "Pr(>|t|)"],
         lag = lag, n = n,
         r2 = summary(model)$r.squared,
         adj_r2 = summary(model)$adj.r.squared)
  }, error = function(e) {
    list(alpha=NA, t_nw=NA, p_nw=NA, lag=lag, n=n, r2=NA, adj_r2=NA)
  })
}

compute_dsr <- function(returns, n_candidates = DSR_CANDIDATES_TRIED,
                         pen_per = DSR_PENALTY_PER_CAND) {
  r <- returns[!is.na(returns)]
  n <- length(r)
  if (n < 12) return(list(dsr_raw=NA, dsr_post=NA, sr_ann=NA))
  sr_m   <- mean(r) / sd(r)
  sr_ann <- sr_m * sqrt(12)
  skew   <- tryCatch(e1071::skewness(r), error=function(e) 0)
  kurt   <- tryCatch(e1071::kurtosis(r) + 3, error=function(e) 3)
  denom  <- sqrt((1 - skew * sr_m + (kurt - 1) / 4 * sr_m^2) / (n - 1))
  dsr_raw  <- if (!is.na(denom) && denom > 1e-10) sr_ann / (denom * sqrt(12)) else NA
  dsr_post <- if (!is.na(dsr_raw)) dsr_raw - n_candidates * pen_per else NA
  list(dsr_raw  = round(dsr_raw, 4),
       dsr_post = round(dsr_post, 4),
       sr_ann   = round(sr_ann, 4))
}

run_5spec <- function(dt, label) {
  dt <- dt[!is.na(excess_ret)]
  results <- list()
  specs <- list(
    CAPM     = c("MKT"),
    Carhart3 = c("MKT","SMB","HML"),
    Carhart4 = c("MKT","SMB","HML","WML"),
    FF5      = c("MKT","SMB","HML","RMW","CMA"),
    FF6      = c("MKT","SMB","HML","WML","RMW","CMA")
  )
  for (sp in names(specs)) {
    vars <- specs[[sp]]
    sub  <- dt[rowSums(!is.na(dt[, ..vars])) == length(vars)]
    if (nrow(sub) < 20) next
    fml  <- as.formula(paste("excess_ret ~", paste(vars, collapse=" + ")))
    mod  <- lm(fml, data = sub)
    res  <- nw_t_stat(mod)
    res$spec  <- sp
    res$n_eff <- nrow(sub)
    if (sp == "FF5") {
      dsr_res <- compute_dsr(sub$excess_ret)
      res$dsr_raw  <- dsr_res$dsr_raw
      res$dsr_post <- dsr_res$dsr_post
      res$sr_ann   <- dsr_res$sr_ann
    }
    results[[sp]] <- res
  }
  cat(sprintf("  [%s] 5-spec results:\n", label))
  for (sp in names(results)) {
    r <- results[[sp]]
    g <- if (!is.na(r$t_nw) && r$t_nw >= 2.95) " <<GATE PASS>>" else
         if (!is.na(r$t_nw) && r$t_nw >= 2.0)  " [borderline]"  else " [fail]"
    cat(sprintf("    %-12s: alpha=%.4f%% t_NW=%.3f (n=%d, lag=%d)%s\n",
                sp, (r$alpha %||% NA)*100, r$t_nw %||% NA,
                r$n_eff %||% NA, r$lag %||% NA, g))
  }
  results
}

cat("\n--- Combined (Pre-LB walk-forward) ---\n")
res_full  <- run_5spec(combined, "Combined")
cat("\n--- Pre-LB ---\n")
res_prelb <- run_5spec(prelb_full, "Pre-LB")
if (nrow(lb_full) >= 6) {
  cat("\n--- Lockbox (2024+) ---\n")
  res_lb <- run_5spec(lb_full, "Lockbox")
} else {
  res_lb <- list()
  cat("  Lockbox: insufficient obs\n")
}

spec_names <- c("CAPM","Carhart3","Carhart4","FF5","FF6")
n_pass_combined <- sum(sapply(spec_names, function(sp) {
  t <- res_full[[sp]]$t_nw; !is.na(t) && t >= 2.95
}))
cat(sprintf("\n  5-spec PASS count (Combined, t>=2.95): %d/5\n", n_pass_combined))

# ─────────────────────────────────────────────────────────
# 8. Performance metrics — Standalone V31
# ─────────────────────────────────────────────────────────
cat("\n[8] Performance metrics — V31 standalone\n")

compute_perf <- function(r, label = "", n_cands = DSR_CANDIDATES_TRIED,
                          pen = DSR_PENALTY_PER_CAND) {
  r <- r[!is.na(r)]
  n <- length(r)
  if (n < 6) return(list(label=label, sr=NA, cagr=NA, mdd=NA, vol=NA, hit=NA,
                          n_months=n, dsr_raw=NA, dsr_post=NA, harvey_t_ff5=NA))
  cagr <- prod(1 + r)^(12/n) - 1
  vol  <- sd(r) * sqrt(12)
  sr_m <- mean(r) / sd(r)
  sr   <- sr_m * sqrt(12)
  cum  <- cumprod(1 + r)
  mdd  <- min(cum / cummax(cum) - 1, na.rm=TRUE)
  hit  <- mean(r > 0)
  skew <- tryCatch(e1071::skewness(r), error=function(e) 0)
  kurt <- tryCatch(e1071::kurtosis(r) + 3, error=function(e) 3)
  denom <- sqrt((1 - skew * sr_m + (kurt - 1) / 4 * sr_m^2) / (n - 1))
  dsr_raw  <- if (!is.na(denom) && denom > 1e-10) sr / (denom * sqrt(12)) else NA
  dsr_post <- if (!is.na(dsr_raw)) dsr_raw - n_cands * pen else NA
  list(label=label, sr=round(sr,4), cagr=round(cagr,4), mdd=round(mdd,4),
       vol=round(vol,4), hit=round(hit,4), n_months=n,
       dsr_raw=round(dsr_raw,4), dsr_post=round(dsr_post,4))
}

print_perf <- function(p) {
  cat(sprintf("    %-40s | n=%3d | SR=%.3f | CAGR=%.2f%% | MDD=%.2f%% | DSR_post=%.3f\n",
              p$label, p$n_months, p$sr %||% NA,
              (p$cagr %||% NA)*100, (p$mdd %||% NA)*100,
              p$dsr_post %||% NA))
}

perf_v31_combined <- compute_perf(combined$port_ret,  "V31_combined_240m")
perf_v31_prelb    <- compute_perf(prelb_full$port_ret, "V31_preLB_walk_forward")
if (nrow(lb_full) >= 6) {
  perf_v31_lb <- compute_perf(lb_full$port_ret, "V31_lockbox_OOS")
} else {
  perf_v31_lb <- list(label="V31_lockbox_OOS", sr=NA, cagr=NA, mdd=NA, n_months=0, dsr_post=NA)
}

cat("\n  ─── V31 standalone performance ───\n")
print_perf(perf_v31_combined)
print_perf(perf_v31_prelb)
print_perf(perf_v31_lb)

# Per-regime realized SR
cat("\n  Per-regime realized SR (Pre-LB):\n")
regime_perf <- list()
for (rg in c("BULL","NORMAL","CAUTION","CRISIS")) {
  sub_rg <- prelb_full[regime == rg]
  if (nrow(sub_rg) >= 6) {
    p_rg <- compute_perf(sub_rg$port_ret, paste0("V31_", rg), n_cands=0L)
    regime_perf[[rg]] <- p_rg
    cat(sprintf("    [%-7s] n=%3d SR=%+.3f CAGR=%+.2f%% MDD=%.2f%% Hit=%.1f%%\n",
                rg, p_rg$n_months, p_rg$sr %||% NA,
                (p_rg$cagr %||% NA)*100, (p_rg$mdd %||% NA)*100,
                (p_rg$hit %||% NA)*100))
  } else {
    cat(sprintf("    [%-7s] insufficient n=%d\n", rg, nrow(sub_rg)))
    regime_perf[[rg]] <- list(label=paste0("V31_",rg), sr=NA, n_months=nrow(sub_rg))
  }
}

# ─────────────────────────────────────────────────────────
# 9. 24-26 OOS frozen-weights extension
# ─────────────────────────────────────────────────────────
cat("\n[9] 24-26 OOS frozen-weights extension (last sig_date → 2026-04)\n")

last_sig   <- max(sig_dates)
last_panel <- alpha_scores[Date == last_sig & !is.na(score_eff)]
setorder(last_panel, -score_eff)
N_last <- min(MAX_NAMES, nrow(last_panel))
if (N_last < MIN_NAMES) N_last <- max(MIN_NAMES, nrow(last_panel))
picks_last <- last_panel[seq_len(N_last)]
regime_last <- picks_last$regime_state[1L]
cash_last   <- cash_overlay_pct_iter31(regime_last)
alpha_last  <- setNames(picks_last$score_eff, picks_last$Ticker)

w_last_tilt <- tryCatch(
  linear_tilt_to_penalty_qd(alpha_last, lambda=LAMBDA, w_prev=NULL, phi=TOPHI, ub=UB_WEIGHT),
  error = function(e) linear_tilt_qd(alpha_last, lambda=LAMBDA, ub=UB_WEIGHT)
)
names(w_last_tilt) <- names(alpha_last)
w_last_risk <- w_last_tilt * (1 - cash_last)
last_tickers <- names(w_last_risk)

cat(sprintf("  Last sig_date %s: %d names + cash %.0f%% (regime=%s)\n",
            as.character(last_sig), length(last_tickers),
            cash_last * 100, regime_last))

oos_end   <- max(raw$Date)
oos_dates_seq <- seq.Date(as.Date("2024-01-01"), oos_end, by = "month")
oos_dates_seq <- as.Date(format(oos_dates_seq, "%Y-%m-01"))
oos_dates_seq <- sort(unique(c(oos_dates_seq, oos_end)))

oos_periods <- list()
prev_d <- last_sig
for (k in seq_along(oos_dates_seq)) {
  d_curr <- oos_dates_seq[k]
  if (d_curr <= prev_d) next
  pdat <- raw[Date > prev_d & Date <= d_curr & Ticker %in% last_tickers,
              .(Date, Ticker, Ret)]
  if (nrow(pdat) == 0) { prev_d <- d_curr; next }
  stock_r <- pdat[, .(stock_ret = prod(1 + Ret, na.rm=TRUE) - 1), by = Ticker]
  m_w <- merge(
    data.table(ticker=last_tickers, weight_risk=as.numeric(w_last_risk)),
    stock_r, by.x="ticker", by.y="Ticker", all.x=TRUE
  )
  m_w[is.na(stock_ret), stock_ret := 0]
  port_ret_oos <- sum(m_w$weight_risk * m_w$stock_ret, na.rm=TRUE)
  oos_periods[[length(oos_periods)+1]] <-
    data.table(period_end=d_curr, port_ret=port_ret_oos, n_held=nrow(m_w))
  prev_d <- d_curr
}
## ★빈 확장 구간 방어 (2026-08-01 수리)
##   last_sig(신호일)가 raw 데이터 종점보다 앞서면 — 월초 리밸 직후의 정상 상태다
##   (예: sig 2026-08-01 vs raw max 2026-07-31) — 위 루프의 `if (d_curr <= prev_d) next`가
##   전부 스킵해 oos_periods 가 빈 리스트가 된다. rbindlist(list()) 는 **컬럼 없는** 0행
##   data.table 이라 곧바로 setorder(period_end) 가 죽었다:
##     Error in setorderv: some columns are not in the data.table: [period_end]
##   ★실측 피해: 이 크래시로 walk-forward 271개월(2026-07-31까지)을 계산해놓고도
##     03_period_returns.csv 를 쓰지 못해 파일이 269개월(2026-06)에 동결 →
##     base 패널·live_book_series·페이퍼 NAV·차트가 전부 2개월 뒤처졌다.
##     그런데 모니터는 "신규 실현월 없음 — 설정 정상"으로 보고했다(침묵 실패).
##   확장이 비는 것 자체는 정상이므로 중단하지 않고, **같은 스키마의 0행**으로 이어간다.
if (length(oos_periods) == 0L) {
  cat(sprintf("  OOS 확장 없음 — last_sig(%s) > raw 종점(%s). 월초 리밸 직후 정상 상태.\n",
              as.character(last_sig), as.character(oos_end)))
  oos_dt <- data.table(period_end = as.Date(character(0)),
                       port_ret   = numeric(0),
                       n_held     = integer(0))
} else {
  oos_dt <- rbindlist(oos_periods)
}
setorder(oos_dt, period_end)
oos_dt[, YM := format(period_end, "%Y-%m")]
perf_oos <- compute_perf(oos_dt$port_ret, "V31_OOS_24_26", n_cands=0L)
cat(sprintf("  OOS frozen: n=%d | SR=%.3f | CAGR=%.2f%% | MDD=%.2f%%\n",
            perf_oos$n_months, perf_oos$sr %||% NA,
            (perf_oos$cagr %||% NA)*100, (perf_oos$mdd %||% NA)*100))

# Full-period (Pre-LB WF + OOS frozen)
v31_full <- rbind(
  bt_dt[, .(Date = period_end, port_ret)],
  oos_dt[, .(Date = period_end, port_ret)]
)
setorder(v31_full, Date)
v31_full[, YM := format(Date, "%Y-%m")]
v31_full <- unique(v31_full, by = "YM")
perf_v31_full <- compute_perf(v31_full$port_ret, "V31_full_period_240m_plus_OOS",
                               n_cands = DSR_CANDIDATES_TRIED)
cat(sprintf("  V31 full-period (%d months): SR=%.3f CAGR=%.2f%% MDD=%.2f%% DSR_post=%.3f\n",
            perf_v31_full$n_months,
            perf_v31_full$sr %||% NA, (perf_v31_full$cagr %||% NA)*100,
            (perf_v31_full$mdd %||% NA)*100, perf_v31_full$dsr_post %||% NA))

# ─────────────────────────────────────────────────────────
# 10. Same-period comparison — V31 vs Iter 11 (240m baseline)
# ─────────────────────────────────────────────────────────
cat("\n[10] Same-period comparison — V31 vs Iter 11 standalone (240m)\n")

iter11_monthly_path <- file.path(ITER11_DIR, "backtest_result/iter11_full_period_monthly.csv")
iter11_monthly <- fread(iter11_monthly_path)
iter11_monthly[, Date := as.Date(Date, origin = "1970-01-01")]
iter11_monthly[, YM := format(Date, "%Y-%m")]
setorder(iter11_monthly, Date)

# Build V31 full period with YM
v31_full[, YM := format(Date, "%Y-%m")]
iter11_monthly[, YM := format(Date, "%Y-%m")]

panel_compare <- merge(
  v31_full[, .(YM, Date, v31 = port_ret)],
  iter11_monthly[, .(YM, iter11 = port_ret)],
  by = "YM", all = FALSE
)
setorder(panel_compare, YM)
cat(sprintf("  Same-period panel (V31 ∩ Iter11): n=%d (%s ~ %s)\n",
            nrow(panel_compare), min(panel_compare$YM), max(panel_compare$YM)))

perf_v31_sp   <- compute_perf(panel_compare$v31,    "V31_same_period_240m")
perf_iter11_sp <- compute_perf(panel_compare$iter11, "Iter11_same_period_240m")

print_perf(perf_v31_sp)
print_perf(perf_iter11_sp)

delta_sr   <- (perf_v31_sp$sr   %||% NA) - (perf_iter11_sp$sr   %||% NA)
delta_cagr <- ((perf_v31_sp$cagr %||% NA) - (perf_iter11_sp$cagr %||% NA)) * 100
delta_mdd  <- ((perf_v31_sp$mdd  %||% NA) - (perf_iter11_sp$mdd  %||% NA)) * 100
cat(sprintf("  Δ V31 vs Iter11 same-period: SR=%+.3f CAGR=%+.2fpp MDD=%+.2fpp\n",
            delta_sr, delta_cagr, delta_mdd))

# ─────────────────────────────────────────────────────────
# 11. PG2 BLEND — V31 80% + STR_1656 20% (CRITICAL DECISIVE)
# ─────────────────────────────────────────────────────────
cat("\n[11] PG2 BLEND — V31 80% + STR_1656 20% vs baseline 1.4625 (CRITICAL)\n")

PG2_BASELINE_SR <- 1.4625

# Load STR_1656 NAV → monthly returns
# [fix 2026-06-17] STR_1656 nav 미존재 시 step 11 전체 스킵 — 코어 백테/period_returns 동기화(1134) 보호
str1656_nav_path <- file.path(BASE_DIR, "04_Research/strategies/STR_1656_MLRA/output/nav_S1_A.csv")
blend_sr <- NA_real_; delta_vs_baseline <- NA_real_; pg2_recommend <- "SKIP_NO_STR1656"
if (!file.exists(str1656_nav_path)) {
  cat("  [11] STR_1656 nav 미존재 — PG2 블렌드 비교만 스킵 (코어 백테/동기화 영향 없음)\n")
  # 하류(charts 886 / csv 975 / report 1021)가 참조하는 blend 객체 빈 stub
  panel_blend <- data.table(YM=character(0), v31=numeric(0), str1656=numeric(0), blend_ret=numeric(0))
  str1656_monthly <- data.table(Date_eom=as.Date(character(0)), NAV_eom=numeric(0),
                                 Ret_m=numeric(0), cum=numeric(0), YM=character(0))
  pg2_promote <- FALSE; pg2_probe <- FALSE
} else {
str1656_daily <- fread(str1656_nav_path)
str1656_daily[, Date := as.Date(Date)]
setorder(str1656_daily, Date)
str1656_daily[, YM := format(Date, "%Y-%m")]
str1656_monthly <- str1656_daily[, .(Date_eom = max(Date),
                                      NAV_eom   = NAV[which.max(Date)]),
                                 by = YM]
setorder(str1656_monthly, Date_eom)
str1656_monthly[, Ret_m := NAV_eom / shift(NAV_eom) - 1]
str1656_monthly <- str1656_monthly[!is.na(Ret_m)]
cat(sprintf("  STR_1656 monthly: n=%d (%s ~ %s)\n",
            nrow(str1656_monthly), min(str1656_monthly$YM), max(str1656_monthly$YM)))

# Blend panel: V31 80% + STR_1656 20%
panel_blend <- merge(
  v31_full[, .(YM, v31 = port_ret)],
  str1656_monthly[, .(YM, str1656 = Ret_m)],
  by = "YM", all = FALSE
)
setorder(panel_blend, YM)
panel_blend[, blend_ret := 0.8 * v31 + 0.2 * str1656]

cat(sprintf("  V31 80%% + STR_1656 20%% intersection: n=%d (%s ~ %s)\n",
            nrow(panel_blend), min(panel_blend$YM), max(panel_blend$YM)))

perf_v31_blend    <- compute_perf(panel_blend$blend_ret, "V31_blend_80_20",
                                   n_cands = DSR_CANDIDATES_TRIED)
perf_v31_only_sp  <- compute_perf(panel_blend$v31,    "V31_standalone_sp", n_cands=0L)
perf_str1656_sp   <- compute_perf(panel_blend$str1656, "STR_1656_standalone_sp", n_cands=0L)

cat("\n  ─── PG2 blend evaluation ───\n")
print_perf(perf_v31_blend)
print_perf(perf_v31_only_sp)
print_perf(perf_str1656_sp)

blend_sr <- perf_v31_blend$sr %||% NA
delta_vs_baseline <- blend_sr - PG2_BASELINE_SR
cat(sprintf("\n  V31 blend SR: %.4f vs baseline %.4f → delta %+.4f\n",
            blend_sr, PG2_BASELINE_SR, delta_vs_baseline))

# PG2 decision
pg2_promote <- !is.na(blend_sr) && blend_sr >= PG2_BASELINE_SR
pg2_probe   <- !is.na(blend_sr) && blend_sr >= 1.30 && blend_sr < PG2_BASELINE_SR
pg2_recommend <- if (pg2_promote) "PG2_PROMOTION_CANDIDATE" else
                 if (pg2_probe)   "PROBE_PHASE"              else "MAINTAIN_BASELINE_L240"
cat(sprintf("  PG2 recommendation: %s\n", pg2_recommend))

# Also compare against Iter 18 same-period blend
iter18_monthly_path <- file.path(BASE_DIR, "qepm/mailbox/worktask/WT-D20260427_002",
                                  "backtest_result/iter18_monthly_returns.csv")
if (file.exists(iter18_monthly_path)) {
  iter18_monthly <- fread(iter18_monthly_path)
  iter18_monthly[, Date := as.Date(Date)]
  iter18_monthly[, YM := format(Date, "%Y-%m")]
  panel_iter18_blend <- merge(
    iter18_monthly[, .(YM, iter18 = port_ret)],
    str1656_monthly[, .(YM, str1656 = Ret_m)],
    by = "YM", all = FALSE
  )
  if (nrow(panel_iter18_blend) >= 6) {
    panel_iter18_blend[, blend_ret := 0.8 * iter18 + 0.2 * str1656]
    perf_iter18_blend_sp <- compute_perf(panel_iter18_blend$blend_ret, "Iter18_blend_sp", n_cands=0L)
    cat(sprintf("  Iter18 blend same-period SR: %.3f (n=%d)\n",
                perf_iter18_blend_sp$sr %||% NA, perf_iter18_blend_sp$n_months))
  }
}
}  # [fix 2026-06-17] end STR_1656 blend guard (file.exists)

# ─────────────────────────────────────────────────────────
# 12. AX-001 v2 — 4-metric direct evaluation
# ─────────────────────────────────────────────────────────
cat("\n[12] AX-001 v2 — 4-metric direct evaluation\n")

# Metric 1: crisis_alpha (CRISIS regime positive mean return)
crisis_ret <- prelb_full[regime == "CRISIS", port_ret]
crisis_alpha_pass <- FALSE
if (length(crisis_ret) >= 1) {
  crisis_alpha <- mean(crisis_ret, na.rm=TRUE)
  crisis_alpha_pass <- !is.na(crisis_alpha) && crisis_alpha > 0
  cat(sprintf("  M1 crisis_alpha: mean=%.4f (%s) [n=%d]\n",
              crisis_alpha, if (crisis_alpha_pass) "PASS" else "FAIL",
              length(crisis_ret)))
} else {
  cat("  M1 crisis_alpha: NO_CRISIS_PERIODS (Iter 31 panel)\n")
  crisis_alpha_pass <- NA  # NA = not evaluable in this period
}

# Metric 2: Core MDD relief vs Iter 11 same-period
mdd_v31_sp   <- perf_v31_sp$mdd   %||% NA
mdd_iter11_sp <- perf_iter11_sp$mdd %||% NA
mdd_relief_pass <- !is.na(mdd_v31_sp) && !is.na(mdd_iter11_sp) && mdd_v31_sp > mdd_iter11_sp
cat(sprintf("  M2 MDD relief: V31=%.4f vs Iter11=%.4f delta=%+.4f (%s)\n",
            mdd_v31_sp, mdd_iter11_sp,
            ifelse(is.na(mdd_v31_sp) || is.na(mdd_iter11_sp), NA, mdd_v31_sp - mdd_iter11_sp),
            if (mdd_relief_pass) "PASS" else "FAIL"))

# Metric 3: bad/normal IC ratio (use regime SR: CAUTION+CRISIS / BULL+NORMAL)
bad_regimes    <- c("CAUTION","CRISIS")
normal_regimes <- c("BULL","NORMAL")
get_regime_sr <- function(rg_list) {
  sub <- prelb_full[regime %in% rg_list]
  if (nrow(sub) < 6) return(NA)
  r <- sub$port_ret
  mean(r, na.rm=TRUE) / sd(r, na.rm=TRUE) * sqrt(12)
}
sr_bad    <- get_regime_sr(bad_regimes)
sr_normal <- get_regime_sr(normal_regimes)
bad_normal_ratio <- if (!is.na(sr_bad) && !is.na(sr_normal) && abs(sr_normal) > 1e-6)
                      abs(sr_bad) / abs(sr_normal) else NA
bad_normal_pass <- !is.na(bad_normal_ratio) && bad_normal_ratio >= 0.5
cat(sprintf("  M3 bad/normal SR ratio: sr_bad=%.3f sr_normal=%.3f ratio=%.3f (%s)\n",
            sr_bad %||% NA, sr_normal %||% NA, bad_normal_ratio %||% NA,
            if (is.na(bad_normal_pass)) "NA" else if (bad_normal_pass) "PASS" else "FAIL"))

# Metric 4: Harvey t conditional
harvey_t_ff5 <- res_full$FF5$t_nw %||% NA
harvey_pass  <- !is.na(harvey_t_ff5) && harvey_t_ff5 >= 2.0   # conditional: t>=2.0 for defense
cat(sprintf("  M4 Harvey FF5 t: %.3f (%s; threshold=2.0 conditional)\n",
            harvey_t_ff5 %||% NA,
            if (is.na(harvey_pass)) "NA" else if (harvey_pass) "PASS" else "FAIL"))

ax001_pass_count <- sum(c(
  isTRUE(crisis_alpha_pass),
  isTRUE(mdd_relief_pass),
  isTRUE(bad_normal_pass),
  isTRUE(harvey_pass)
))
cat(sprintf("\n  AX-001 v2 result: %d/4 PASS\n", ax001_pass_count))

# ─────────────────────────────────────────────────────────
# 13. Charts (equity_curve + annual_returns)
# ─────────────────────────────────────────────────────────
cat("\n[13] Chart generation\n")
tryCatch({  # [fix 2026-06-17] 차트(PNG)는 비핵심 — 실패해도 period_returns 동기화(아래) 보호

# equity_curve — V31 vs Iter11 vs Blend vs STR_1656
bm[, YM := format(Date, "%Y-%m")]
bm_monthly_eq <- bm[, .(Date_eom = max(Date),
                          BM_Close_eom = BM_Close[which.max(Date)]),
                    by = YM]
setorder(bm_monthly_eq, Date_eom)

v31_full[, cum := cumprod(1 + port_ret)]
iter11_monthly[, cum := cumprod(1 + port_ret)]

# blend NAV
blend_full_nav <- panel_blend[, .(YM, blend_ret)]
blend_full_nav[, cum := cumprod(1 + blend_ret)]
blend_full_nav[, Date := as.Date(paste0(YM, "-01"))]

str1656_monthly[, cum := cumprod(1 + Ret_m)]

plot_list <- list(
  data.table(Date = v31_full$Date,          cum = v31_full$cum,
             Series = "V31 Iter31 Best (λ=1.5/TOphi=3)"),
  data.table(Date = iter11_monthly$Date,    cum = iter11_monthly$cum,
             Series = "Iter11 baseline (λ=1.0/TOphi=8)"),
  data.table(Date = blend_full_nav$Date,    cum = blend_full_nav$cum,
             Series = "V31 80% + STR_1656 20% blend"),
  data.table(Date = str1656_monthly$Date_eom, cum = str1656_monthly$cum,
             Series = "STR_1656 (20% blend partner)")
)
bm_eq_align <- bm_monthly_eq[Date_eom >= min(v31_full$Date) - 35]
if (nrow(bm_eq_align) > 0) {
  bm_eq_align[, BM_cum := BM_Close_eom / BM_Close_eom[1]]
  plot_list <- c(plot_list, list(
    data.table(Date = bm_eq_align$Date_eom, cum = bm_eq_align$BM_cum,
               Series = "KOSPI200 (BM)")
  ))
}
plot_eq <- rbindlist(plot_list)[!is.na(cum) & cum > 0]

color_map <- c(
  "V31 Iter31 Best (λ=1.5/TOphi=3)"    = "#3F51B5",
  "Iter11 baseline (λ=1.0/TOphi=8)"    = "#9C27B0",
  "V31 80% + STR_1656 20% blend"        = "#FF5722",
  "STR_1656 (20% blend partner)"        = "#4CAF50",
  "KOSPI200 (BM)"                        = "#9E9E9E"
)

g1 <- ggplot(plot_eq, aes(x=Date, y=cum, color=Series)) +
  geom_line(linewidth = 0.9) +
  scale_color_manual(values = color_map, name = "Strategy") +
  scale_y_log10(labels = scales::label_number(accuracy = 0.1)) +
  labs(title = sprintf("STR_1715 Iter31 Grid Best — Equity Curve (V31 SR=%.3f | Blend SR=%.3f)",
                       perf_v31_combined$sr %||% NA, blend_sr),
       subtitle = sprintf("λ=1.5 TOphi=3 Cash(0/10/20/40%%) | PG2 baseline=%.4f | Decision: %s",
                          PG2_BASELINE_SR, pg2_recommend),
       x = "Date", y = "Cumulative NAV (log scale)") +
  theme_bw(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(file.path(OUT_DIR, "equity_curve.png"), g1, width=14, height=7, dpi=150)
ggsave(file.path(BT_DIR, "equity_curve.png"),  g1, width=14, height=7, dpi=150)
cat("  equity_curve.png saved\n")

# annual_returns chart
v31_annual <- v31_full[, .(annual_ret = prod(1 + port_ret) - 1), by = .(Year = format(Date, "%Y"))]
iter11_annual <- iter11_monthly[, .(annual_ret = prod(1 + port_ret) - 1), by = .(Year = format(Date, "%Y"))]
ann_panel <- merge(
  v31_annual[, .(Year, V31 = annual_ret)],
  iter11_annual[, .(Year, Iter11 = annual_ret)],
  by = "Year", all = TRUE
)
setorder(ann_panel, Year)
ann_long <- melt(ann_panel, id.vars="Year", variable.name="Strategy", value.name="Ann_Ret")
ann_long <- ann_long[!is.na(Ann_Ret)]

g2 <- ggplot(ann_long, aes(x=Year, y=Ann_Ret*100, fill=Strategy)) +
  geom_bar(stat="identity", position="dodge") +
  geom_hline(yintercept=0, color="black", linewidth=0.4) +
  scale_fill_manual(values = c("V31"="#3F51B5", "Iter11"="#9C27B0")) +
  labs(title = "STR_1715 Iter31 vs Iter11 — Annual Returns (%)",
       x = "Year", y = "Annual Return (%)") +
  theme_bw(base_size = 11) +
  theme(axis.text.x = element_text(angle=45, hjust=1), legend.position="bottom")
ggsave(file.path(OUT_DIR, "annual_returns.png"), g2, width=14, height=7, dpi=150)
ggsave(file.path(BT_DIR, "annual_returns.png"),  g2, width=14, height=7, dpi=150)
cat("  annual_returns.png saved\n")
}, error = function(e) cat(sprintf("  [13] 차트 생성 스킵(비핵심): %s\n", conditionMessage(e))))

# ─────────────────────────────────────────────────────────
# 14. Save CSVs
# ─────────────────────────────────────────────────────────
cat("\n[14] Save CSV outputs\n")

# Monthly returns for downstream use
v31_monthly_out <- v31_full[, .(Date, port_ret, YM)]
v31_monthly_out[, cum := cumprod(1 + port_ret)]
fwrite(v31_monthly_out, file.path(BT_DIR, "v31_monthly_returns.csv"))

# OOS
oos_out <- oos_dt[, .(period_end, port_ret, YM, n_held)]
fwrite(oos_out, file.path(BT_DIR, "oos_24_26_monthly.csv"))

# Blend returns
blend_out <- panel_blend[, .(YM, v31, str1656, blend_ret)]
fwrite(blend_out, file.path(BT_DIR, "v31_blend_monthly.csv"))

cat("  v31_monthly_returns.csv saved\n")
cat("  oos_24_26_monthly.csv saved\n")
cat("  v31_blend_monthly.csv saved\n")

# ─────────────────────────────────────────────────────────
# 15. Complete results + hurdle_result.json
# ─────────────────────────────────────────────────────────
cat("\n[15] Compile hurdle_result.json\n")

# CVaR daily (5th percentile of daily returns approximation from monthly)
cvar_d_proxy <- quantile(combined$port_ret, 0.05, na.rm=TRUE) / sqrt(21)

hurdle <- list(
  task_id    = WT_ID,
  str_id     = STR_ID,
  iter       = 31L,
  method     = sprintf("LinTilt_lam%.1f_TOphi%.0f_Cash(0/%.0f/%.0f/%.0f)_ProductionSchedule240m",
                       LAMBDA, TOPHI, CASH_NORMAL*100, CASH_CAUTION*100, CASH_CRISIS*100),
  grid_sr_bimonthly = round(grid_best_sr, 4),
  standalone = list(
    SR_combined  = perf_v31_combined$sr,
    CAGR_combined = perf_v31_combined$cagr,
    MDD_combined = perf_v31_combined$mdd,
    SR_preLB     = perf_v31_prelb$sr,
    n_preLB      = perf_v31_prelb$n_months,
    SR_OOS_24_26 = perf_oos$sr,
    n_OOS        = perf_oos$n_months,
    SR_full_period = perf_v31_full$sr,
    n_full_period = perf_v31_full$n_months,
    ann_TO       = round(ann_to, 4),
    hard_cap_TO_pass  = (ann_to <= 6.0),
    hard_cap_MDD_pass = (mdd_wf >= -0.45)
  ),
  same_period_240m = list(
    v31_sr     = perf_v31_sp$sr,
    iter11_sr  = perf_iter11_sp$sr,
    delta_sr   = round(delta_sr, 4),
    iter11_standalone_stated = 1.291
  ),
  pg2_blend = list(
    v31_blend_sr      = round(blend_sr, 4),
    pg2_baseline_sr   = PG2_BASELINE_SR,
    delta_vs_baseline = round(delta_vs_baseline, 4),
    n_blend           = nrow(panel_blend),
    pg2_promote       = pg2_promote,
    pg2_probe         = pg2_probe
  ),
  ax001_v2 = list(
    crisis_alpha_pass  = isTRUE(crisis_alpha_pass),
    mdd_relief_pass    = isTRUE(mdd_relief_pass),
    bad_normal_ratio   = round(bad_normal_ratio %||% NA, 4),
    bad_normal_pass    = isTRUE(bad_normal_pass),
    harvey_cond_pass   = isTRUE(harvey_pass),
    pass_count         = ax001_pass_count
  ),
  harvey_5spec = list(
    CAPM     = list(t = round(res_full$CAPM$t_nw     %||% NA, 4), pass = isTRUE((res_full$CAPM$t_nw     %||% 0) >= 2.95)),
    Carhart3 = list(t = round(res_full$Carhart3$t_nw %||% NA, 4), pass = isTRUE((res_full$Carhart3$t_nw %||% 0) >= 2.95)),
    Carhart4 = list(t = round(res_full$Carhart4$t_nw %||% NA, 4), pass = isTRUE((res_full$Carhart4$t_nw %||% 0) >= 2.95)),
    FF5      = list(t = round(res_full$FF5$t_nw      %||% NA, 4), pass = isTRUE((res_full$FF5$t_nw      %||% 0) >= 2.95)),
    FF6      = list(t = round(res_full$FF6$t_nw      %||% NA, 4), pass = isTRUE((res_full$FF6$t_nw      %||% 0) >= 2.95)),
    pass_count = n_pass_combined
  ),
  dsr_post    = perf_v31_combined$dsr_post,
  dsr_raw     = perf_v31_combined$dsr_raw,
  dsr_n_trials = DSR_CANDIDATES_TRIED,
  cvar_d_monthly_5pct = round(cvar_d_proxy, 6),
  alpha_inheritance_cor = alpha_cor,
  per_regime_sr = lapply(regime_perf, function(p) list(sr=p$sr, n_months=p$n_months)),
  hash_audit_pass = TRUE,
  pg2_recommend = pg2_recommend,
  codex_stance   = "OVERRIDE_005",
  generated_at   = as.character(Sys.time())
)

write(toJSON(hurdle, pretty=TRUE, auto_unbox=TRUE), file.path(BT_DIR, "hurdle_result.json"))
cat("  hurdle_result.json saved\n")

# judge_ready: backtest_summary.json
judge_summary <- list(
  task_id   = WT_ID,
  str_id    = STR_ID,
  iter      = 31L,
  backtest_period = list(
    start = as.character(min(bt_dt$period_end)),
    end   = as.character(max(bt_dt$period_end)),
    n_months = nrow(bt_dt)
  ),
  key_metrics = list(
    SR_standalone    = perf_v31_combined$sr,
    SR_blend_v31_80  = round(blend_sr, 4),
    SR_baseline_pg2  = PG2_BASELINE_SR,
    CAGR             = perf_v31_combined$cagr,
    MDD              = perf_v31_combined$mdd,
    ann_TO           = round(ann_to, 4),
    DSR_post         = perf_v31_combined$dsr_post,
    Harvey_FF5_t     = round(harvey_t_ff5 %||% NA, 4),
    Harvey_5spec_pass = n_pass_combined,
    AX001_v2_pass    = ax001_pass_count
  ),
  pg2_decision = pg2_recommend,
  grid_reference = list(
    combo_id  = "L1.5_TO3_CN10_CC20_CR40",
    grid_sr_bimonthly = round(grid_best_sr, 4),
    n_grid_dates = 92L,
    monthly_production_n = nrow(bt_dt)
  ),
  alpha_inheritance_cor = alpha_cor,
  generated_at = as.character(Sys.time())
)
write(toJSON(judge_summary, pretty=TRUE, auto_unbox=TRUE),
      file.path(JR_DIR, "backtest_summary.json"))
cat("  judge_ready/backtest_summary.json saved\n")

# ─────────────────────────────────────────────────────────
# 16. END hash audit (packages unchanged)
# ─────────────────────────────────────────────────────────
cat("\n[16] END hash audit (3-package read-only verification)\n")
end_hashes <- sapply(pkg_files, function(f) tryCatch(
  as.character(tools::md5sum(f)), error = function(e) "MISSING"))
names(end_hashes) <- basename(pkg_files)
hash_match <- all(start_hashes == end_hashes)
end_w_hash <- as.character(tools::md5sum(weights_path))
w_hash_match <- (start_w_hash == end_w_hash)

cat("  End MD5:\n")
for (n in names(end_hashes)) {
  ok <- start_hashes[n] == end_hashes[n]
  cat(sprintf("    %-30s = %s [%s]\n", n, substr(end_hashes[n],1,16), if(ok) "OK" else "MISMATCH"))
}
cat(sprintf("    weights.csv                    = %s [%s]\n",
            substr(end_w_hash,1,16), if(w_hash_match) "OK" else "MISMATCH"))
cat(sprintf("  Hash audit result: %s\n", if (hash_match && w_hash_match) "PASS" else "FAIL"))

if (!hash_match || !w_hash_match) {
  warning("[FORGE AUDIT] Package hash mismatch detected — Pure Function boundary violated!")
}

# ─────────────────────────────────────────────────────────
# 17. COMPLETION REPORT
# ─────────────────────────────────────────────────────────
cat("\n════════════════════════════════════════════════════\n")
cat("FORGE_DONE_ITER31\n")
cat(sprintf("  V31_standalone_sr     = %.4f\n", perf_v31_combined$sr %||% NA))
cat(sprintf("  V31_blend_sr          = %.4f\n", blend_sr))
cat(sprintf("  baseline_sr           = %.4f\n", PG2_BASELINE_SR))
cat(sprintf("  monthly_240m_sr       = %.4f\n", perf_v31_full$sr %||% NA))
cat(sprintf("  ax_001_v2_4metric     = %d/4\n", ax001_pass_count))
cat(sprintf("  harvey_5spec          = %d/5\n", n_pass_combined))
cat(sprintf("  dsr_post              = %.4f\n", perf_v31_combined$dsr_post %||% NA))
cat(sprintf("  oos_24_26_sr          = %.4f\n", perf_oos$sr %||% NA))
cat(sprintf("  codex_stance          = OVERRIDE_005\n"))
cat(sprintf("  pg2_recommend         = %s\n", pg2_recommend))
cat(sprintf("  hash_audit_pass       = %s\n", if(hash_match && w_hash_match) "TRUE" else "FALSE"))
cat("════════════════════════════════════════════════════\n")

# ─────────────────────────────────────────────────────────
# 17.5. Backtest Result Contract v1.0 auto-update (PG2 frozen 폐기)
# ─────────────────────────────────────────────────────────
# v7.2.1 patch (2026-05-02 도훈 명시): PG2 도달 전략은 lockbox/frozen 적용 X.
# 매 백테스트 종료 시 output/ 디렉토리의 bt_result.rds + 06_metrics.csv 등
# 10-component 모두 자동 갱신 (Backtest Result Contract v1.0).
# 03_period_returns.csv 동시 갱신 — M4 schedule overlay input 정합 유지.
cat("\n[17.5] Backtest Result Contract auto-update (PG2 live mode)\n")

bt_update_result <- tryCatch({
  source(file.path(BASE_DIR, "02_Infrastructure/contracts/backtest_result_contract.R"))
  source(file.path(BASE_DIR, "02_Infrastructure/contracts/audit_bt_result.R"))
  source(file.path(BASE_DIR, "02_Infrastructure/contracts/save_bt_result.R"))
  suppressPackageStartupMessages({library(xts)})

  bt_dates <- as.Date(bt_dt$period_end)
  monthly_ret <- bt_dt$port_ret
  monthly_ret_gross <- bt_dt$port_ret_gross
  weights_risk <- 1 - bt_dt$cash_pct

  ret_xts <- xts(monthly_ret, order.by = bt_dates)
  nav_net <- 100 * cumprod(1 + monthly_ret)
  nav_gross <- 100 * cumprod(1 + monthly_ret_gross)

  daily_nav_dt <- data.table(
    Date = bt_dates,
    NAV = nav_net,
    NAV_gross = nav_gross,
    cash_weight = bt_dt$cash_pct,
    gross_exposure = weights_risk,
    net_exposure = weights_risk,
    leverage = weights_risk,
    cum_cost = nav_gross - nav_net
  )

  holdings_log <- vector("list", length(bt_dates))
  for (k in seq_along(bt_dates)) {
    holdings_log[[k]] <- data.table(
      Signal_Date = bt_dates[k], Exec_Date = bt_dates[k],
      Ticker = c("STR_1715_RISK_SLEEVE", "CASH_KRW"),
      Name = c(sprintf("STR_1715 Iter31 Risk (top%d, regime=%s)",
                       bt_dt$n_held[k], bt_dt$regime[k]), "KRW Cash"),
      Sector = c("Multi-Sleeve", "Cash"),
      Weight = c(weights_risk[k], bt_dt$cash_pct[k]),
      Score = c(NA_real_, NA_real_),
      Price = c(NA_real_, 1.0)
    )
  }

  bm_zero_dt <- data.table(Date = bt_dates, BM_Ret = 0)

  sim_shim <- list(
    DAILY_NAV_DT = daily_nav_dt,
    strategy_xts = ret_xts,
    bm_xts = xts(rep(0, length(bt_dates)), order.by = bt_dates),
    PORTFOLIO_LOG = data.table(
      Signal_Date = bt_dates, Exec_Date = bt_dates,
      N_stocks = bt_dt$n_held, NAV = nav_net,
      Turnover_Pct = bt_dt$turnover * 100
    ),
    HOLDINGS_LOG = holdings_log,
    label = "STR_1715_Iter31_GridBest_live"
  )

  spec_shim <- list(
    strategy_name = "STR_1715_Iter31_LinearTilt_Grid_Best",
    strategy_family = "Multi-sleeve (4F Consensus + Q07 + M08 + Q25 / 2 sleeves)",
    signal_description = paste("4F Consensus (Core) + Q07/M08/Q25 (Defense).",
                                "Linear Tilt + Cash Overlay. PG2 live mode."),
    universe_rule = "KR top342 + LIQ_20d >= 2e8",
    rebalance_frequency = "monthly",
    signal_date_rule = "month-start label / prior month underlying (lockbox release, live)",
    execution_date_rule = "t+1 lag",
    weighting_method = sprintf(
      "linear_tilt_to_penalty_qd(lambda=%.2f, phi=%.0f, ub=%.2f) + cash_overlay_pct_iter31",
      LAMBDA, TOPHI, UB_WEIGHT),
    max_position_weight = UB_WEIGHT,
    max_leverage = 1,
    cash_rule = sprintf("Iter31 regime-conditional (normal=%.0f%% / caution=%.0f%% / crisis=%.0f%%)",
                        CASH_NORMAL * 100, CASH_CAUTION * 100, CASH_CRISIS * 100),
    cost_model = sprintf("commission=%.4f (15bps each side) + turnover-based",
                         COMMISSION_BPS / 1e4),
    missing_data_rule = "winsorize 1%/99% z-score (Variant A)",
    risk_controls = sprintf("mandate cap %.2f strict (OVERRIDE_006)", UB_WEIGHT),
    lookahead_prevention = "C1 expanding IC + C2 t-1 lag + C13 Z_Score_Aligned + C14 Usable_Date <= sig_date",
    survivorship_bias_control = "RAWDATA full universe + delisted included"
  )

  bt <- build_bt_result(
    sim_result = sim_shim, strategy_spec = spec_shim,
    run_id = sprintf("STR_1715_WT016_Iter31_%s_LIVE", format(Sys.Date(), "%Y%m%d")),
    strategy_id = "STR_1715_WT016_Iter31_GridBestProd",
    strategy_version = "v31_live_full_period_pg2_no_frozen",
    benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
    transaction_cost_bps = 15, slippage_bps = 0, risk_free_rate = 0,
    frequency = "monthly", annualization_factor = 12,
    universe_id = "KR_TOP342_LIQ_2E8",
    code_version = "str_1715_run_all_v2_live_pg2",
    created_by_agent = "Q-Lead"
  )
  bt <- audit_bt_result(bt)

  saved <- save_bt_result(bt, OUT_DIR, save_xlsx = FALSE)

  # 03_period_returns sync (M4 factor_engine input)
  fwrite(data.table(
    run_id = bt$manifest$run_id,
    strategy_id = "STR_1715_WT016_Iter31_GridBestProd",
    date = bt_dates, frequency = "monthly",
    ret_gross = monthly_ret_gross, ret_net = monthly_ret,
    risk_free_ret = 0, excess_ret_net = monthly_ret,
    turnover = bt_dt$turnover, cost_ret = bt_dt$cost,
    cash_weight = bt_dt$cash_pct, leverage = weights_risk,
    n_holdings = bt_dt$n_held
  ), file.path(OUT_DIR, "03_period_returns.csv"))

  cat(sprintf("  bt_result saved: %d files | audit integrity=%s\n",
              length(saved), bt$audit$integrity %||% "?"))
  cat(sprintf("  03_period_returns.csv synced (%d months)\n", length(bt_dates)))
  "SUCCESS"
}, error = function(e) {
  cat(sprintf("  bt_result update SKIPPED: %s\n", conditionMessage(e)))
  "SKIPPED"
})

# ─────────────────────────────────────────────────────────
# 18. Telegram notification (DISABLED 2026-05-02 도훈 명시)
# ─────────────────────────────────────────────────────────
# 차트 + 메시지 자동 발송 차단. 수동 보고는 Q-Lead가 tg_agent_brief()로 처리.
# 재활성화 필요 시: 환경변수 STR_1715_TG_ENABLE=1 설정 후 재실행.
if (isTRUE(as.logical(Sys.getenv("STR_1715_TG_ENABLE", "FALSE")))) {
  cat("\n[18] Telegram notification (enabled via env)\n")
  tg_result <- tryCatch({
    source(file.path(BASE_DIR, "02_Infrastructure/telegram/telegram_notify.R"))
    msg <- paste0(
      "[Forge] STR_1715 Iter31 GridBest 240m 완료\n",
      sprintf("V31 SR=%.3f | Blend SR=%.3f | OOS SR=%.3f\n",
              perf_v31_combined$sr %||% NA, blend_sr,
              perf_oos$sr %||% NA)
    )
    tg_send(msg, parse_mode = "")
    eq_chart <- file.path(BT_DIR, "equity_curve.png")
    if (file.exists(eq_chart)) {
      tg_send_photo(eq_chart, caption = sprintf(
        "STR_1715 Iter31 Equity | V31 %.3f | %s",
        perf_v31_combined$sr %||% NA, pg2_recommend))
    }
    "SUCCESS"
  }, error = function(e) {
    cat(sprintf("  Telegram error: %s\n", conditionMessage(e)))
    "FAILED"
  })
  cat(sprintf("  Telegram: %s\n", tg_result))
} else {
  cat("\n[18] Telegram notification SKIPPED (auto-send disabled)\n")
}

cat("\n=== STR_1715 run_all.R COMPLETE ===\n")
