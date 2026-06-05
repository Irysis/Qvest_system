#==============================================================================
# QEPM Forge Integration + Charter v1.0 Backtest
# Task ID    : WT-D20260527_001
# Strategy   : STR_1719_WT001_DCA_v7
# Stage      : Forge (3-package integration + bt_result 10-component)
#
# Alpha     : DCA_v7_4family_static_EW_P3P4_confidence (Iter 7)
#               - 4-family static EW composite (defense + quality + value + consensus)
#               - P3/P4 distributional forecast as regime-aware confidence vector
#               - alpha_package.json hash 2dffcb69b4404e3c773315ff70ffb556
# Risk      : Ledoit-Wolf oracle, cond=14.51, PSD=TRUE
#               - risk_package.json hash 86c0436dfafd6d14abe674a821c6a83e
# Optimizer : M06_MVO_Breadth (Markowitz + Grinold-Kahn breadth)
#               - 97 sig_dates × 15 names per date
#               - weights.csv hash d76caa2ecda4ac768f91019a1e8e6762
#               - optimization_package.json hash 5e4e42bff8027901ec7ace78df78cb29
#
# Pure Function (v6.1 R12 HARD):
#   - alpha_vector / target_weights / covariance 수정 절대 금지
#   - weights.csv as-is (sig_date schedule 보존, fabrication 금지)
#   - PerformanceAnalytics 표준 함수만 (self-synthesis 금지)
#
# Schedule Fidelity (v6.3 §9):
#   - weights.csv 97 sig_dates → forward-month NAV reconstruction
#   - 임의 sig_date 재생성 금지, ProductionSchedule[N]m label 금지
#
# Cost      : v2.3_kr_retail_15bps (one-way commission)
# PIT       : C1-C15 enforced (request.json line 35 "C1-C15 all enforced")
# Universe  : KOSPI200 ∪ KOSDAQ150 intersection (liquidity 50M won 20d avg)
# Benchmark : KOSPI200 total return
#==============================================================================

cat("============================================================\n")
cat("WT-D20260527_001 Forge Stage — STR_1719_WT001_DCA_v7\n")
cat(sprintf("Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("============================================================\n")

set.seed(20260527L)

# ─── 0. Constants ─────────────────────────────────────────────────────────────

WT_ID         <- "WT-D20260527_001"
STRATEGY_ID   <- "STR_1719_WT001_DCA_v7"
STRATEGY_VER  <- "v1.0"
STRATEGY_NAME <- "DCA_v7_4family_static_EW_P3P4_confidence_M06_MVO_Breadth"

COMMISSION    <- 0.0015  # 15bps one-way (cost_model_version v2.3_kr_retail_15bps)
ANN_FACTOR    <- 252     # trading days/year (daily bt)

# Backtest temporal bounds (from optimization_package.json walk_forward_diagnostics)
SIG_FIRST     <- as.Date("2015-12-30")  # First sig_date in weights.csv
SIG_LAST      <- as.Date("2023-12-28")  # Lockbox cutoff (signal_cutoff)
# Forge backtest holds from first sig_date through end of next-business-day after SIG_LAST
# (frozen post-cutoff is NOT applied here — schedule density 1.000 from weights.csv)

# ─── 1. Infrastructure 로드 ────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(xts)
  library(zoo)
  library(PerformanceAnalytics)
  library(ggplot2)
  library(scales)
  library(digest)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/worktask/lineage_utils.R"))

# Backtest contract loaders
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/audit_bt_result.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/save_bt_result.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/registry_writer.R"))

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

WT_DIR    <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID))
STR_DIR   <- file.path(PROJECT_ROOT, "04_Research/strategies", STRATEGY_ID)
OUT_DIR   <- file.path(STR_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

cat(sprintf("[step 0] OUT_DIR = %s\n", OUT_DIR))

# ─── 2. Boundary integrity — START hashes ─────────────────────────────────────

cat("\n[step 1] Boundary integrity (START hashes)\n")

alpha_pkg_path <- file.path(WT_DIR, "alpha_package.json")
risk_pkg_path  <- file.path(WT_DIR, "risk_package.json")
opt_pkg_path   <- file.path(WT_DIR, "optimization_package.json")
weights_path   <- file.path(STAGE_DIR, "optimizer", "weights.csv")
alpha_scores_p <- file.path(STAGE_DIR, "alpha_scores.parquet")
cov_path       <- file.path(STAGE_DIR, "risk", "covariance.parquet")

hash_start <- list(
  alpha_package   = digest(file = alpha_pkg_path, algo = "md5"),
  risk_package    = digest(file = risk_pkg_path,  algo = "md5"),
  opt_package     = digest(file = opt_pkg_path,   algo = "md5"),
  weights_csv     = digest(file = weights_path,   algo = "md5"),
  alpha_scores    = digest(file = alpha_scores_p, algo = "md5"),
  covariance      = digest(file = cov_path,       algo = "md5")
)
cat(sprintf("  alpha_package  md5 = %s\n", hash_start$alpha_package))
cat(sprintf("  risk_package   md5 = %s\n", hash_start$risk_package))
cat(sprintf("  opt_package    md5 = %s\n", hash_start$opt_package))
cat(sprintf("  weights_csv    md5 = %s\n", hash_start$weights_csv))

# ─── 3. 3-Agent 산출물 로드 (Pure function — read-only) ────────────────────────

cat("\n[step 2] Load 3-agent packages (read-only)\n")

alpha_pkg <- fromJSON(alpha_pkg_path, simplifyVector = FALSE)
risk_pkg  <- fromJSON(risk_pkg_path,  simplifyVector = FALSE)
opt_pkg   <- fromJSON(opt_pkg_path,   simplifyVector = FALSE)
request   <- fromJSON(file.path(WT_DIR, "request.json"), simplifyVector = FALSE)

# weights.csv as-is (Charter §9 schedule fidelity)
weights_dt <- fread(weights_path)
weights_dt[, Date := as.Date(Date)]
weights_dt[, as_of_date := as.Date(as_of_date)]
setorder(weights_dt, Date, Ticker)

cat(sprintf("  alpha pkg iter=%d (%s) n_alpha=%d\n",
            alpha_pkg$iter, alpha_pkg$iter_name,
            length(alpha_pkg$alpha_vector)))
cat(sprintf("  risk pkg : cov_method=%s cond=%.2f PSD=%s\n",
            risk_pkg$cov_method,
            risk_pkg$covariance_diagnostics$condition_number,
            risk_pkg$covariance_diagnostics$psd_verified))
cat(sprintf("  opt pkg  : method=%s n=%d HHI=%.3f net_IR=%.4f\n",
            opt_pkg$method_selected, opt_pkg$n_names,
            opt_pkg$hhi, opt_pkg$expected_net_information_ratio))
cat(sprintf("  weights  : %d rows × %d sig_dates × %d unique tickers\n",
            nrow(weights_dt), uniqueN(weights_dt$Date),
            uniqueN(weights_dt$Ticker)))

# ─── 4. Hard Constraint 재검증 (per-sig_date) ─────────────────────────────────

cat("\n[step 3] Hard constraint per-sig_date validation\n")

per_date_check <- weights_dt[, .(
  n_names = .N,
  sum_w = sum(weight),
  max_w = max(weight),
  min_w = min(weight),
  all_nonneg = all(weight >= -1e-8)
), by = Date]

stopifnot("n_names <= 20"   = all(per_date_check$n_names <= 20))
stopifnot("|sum_w - 1|< 0.005" = all(abs(per_date_check$sum_w - 1.0) < 0.005))
stopifnot("max_w <= 0.20+eps"  = all(per_date_check$max_w <= 0.20 + 1e-6))
stopifnot("long-only"  = all(per_date_check$all_nonneg))

cat(sprintf("  All %d sig_dates pass: max(n)=%d / min(sum_w)=%.4f / max(sum_w)=%.4f / max(w)=%.4f / long-only=TRUE\n",
            nrow(per_date_check),
            max(per_date_check$n_names),
            min(per_date_check$sum_w),
            max(per_date_check$sum_w),
            max(per_date_check$max_w)))

# method_selected column check (Codex C1 fix verification)
if ("method_selected" %in% names(weights_dt)) {
  methods_in_csv <- unique(weights_dt$method_selected)
  cat(sprintf("  method_selected in csv: %s\n", paste(methods_in_csv, collapse = ", ")))
  stopifnot("M06_MVO_Breadth declared" = "M06_MVO_Breadth" %in% methods_in_csv)
}

# ─── 5. RAWDATA 로드 (1회) ────────────────────────────────────────────────────

cat("\n[step 4] Load RAWDATA (cache)\n")

raw_list <- load_rawdata(use_cache = TRUE)
RAWDATA  <- raw_list$RAWDATA
BM_DT    <- raw_list$BM_DT

RAWDATA[, Date := as.Date(Date)]
BM_DT[,   Date := as.Date(Date)]
setkey(RAWDATA, Date, Ticker)

cat(sprintf("  RAWDATA: %s rows | %s ~ %s | %d tickers\n",
            format(nrow(RAWDATA), big.mark = ","),
            min(RAWDATA$Date), max(RAWDATA$Date),
            uniqueN(RAWDATA$Ticker)))

# ─── 6. Backtest period definition ───────────────────────────────────────────

cat("\n[step 5] Backtest period definition (lockbox respect)\n")

all_dates <- sort(unique(RAWDATA$Date))

sig_dates <- sort(unique(weights_dt$Date))
n_sig <- length(sig_dates)
cat(sprintf("  Sig_dates: n=%d | first=%s | last=%s\n",
            n_sig, sig_dates[1], sig_dates[n_sig]))

# Backtest end = next month-end after SIG_LAST (forward 1m settle of last sig)
# Forge does NOT extend past last sig holding (Pure Function — uses weights.csv schedule)
sig_last_eff <- sig_dates[n_sig]
candidates_after <- all_dates[all_dates > sig_last_eff]
# Backtest extends until last available daily price (end-of-month after last signal)
# bounded by all_dates max in RAWDATA. Schedule fidelity: NO frozen extension here
# beyond the natural next-rebal anchor (=natural NAV settling till next-month last bday).
last_rebal_window_end <- if (length(candidates_after) > 0) {
  # Hold positions until 21 trading days after last sig (approx 1 month forward fill)
  candidates_after[min(21, length(candidates_after))]
} else {
  sig_last_eff
}

# Start: first sig_date
bt_start_date <- sig_dates[1]
bt_end_date   <- last_rebal_window_end

cat(sprintf("  Backtest window: %s ~ %s (n_days = %d)\n",
            bt_start_date, bt_end_date,
            sum(all_dates >= bt_start_date & all_dates <= bt_end_date)))

# ─── 7. Custom static-schedule backtest (weights.csv as-is) ───────────────────
#
# 이 백테는 weights.csv의 97 sig_dates × ticker × weight를 그대로 사용한다.
# 각 sig_date t에 대해:
#   exec_date = next trading day (T+1)
#   period_end = next sig_date의 exec_date - 1
#   기간 동안 weights[t]를 buy-and-hold (share-based, no intra-rebal mark)
# 마지막 sig_date의 holding은 last_rebal_window_end 까지 보유.
#
# Pure Function: alpha_scores.parquet 직접 활용 안 함 (진단 전용),
#   weights.csv가 정의한 sig_date schedule + ticker selection + weight 보존.
#
# PIT: weights는 sig_date t의 정보로 만들어진 산출물.
#   exec_date >= t (next biz day) → no lookahead.
#
# Cost: 15bps one-way commission, 매 sig_date에 sell + buy 모두 적용.
# ─────────────────────────────────────────────────────────────────────────────

cat("\n[step 6] Run share-based backtest (weights.csv schedule)\n")

# Helper: get T+1 trading day (PIT-strict: weights @ sig_date applied at T+1)
get_t_plus_1 <- function(t, all_dates) {
  idx <- which(all_dates > t)
  if (length(idx) == 0) return(NA_Date_)
  all_dates[idx[1]]
}

initial_cap   <- 1e8
cash          <- initial_cap
holdings      <- list()  # named list(ticker -> list(shares=, last_price=))
daily_nav_list <- list()
holdings_log_list <- list()
portfolio_log_list <- list()

# Sig_date에 대해 정렬, exec_date 계산
sig_schedule <- data.table(
  Signal_Date = sig_dates,
  Exec_Date   = sapply(sig_dates, function(d) get_t_plus_1(d, all_dates))
)
sig_schedule[, Exec_Date := as.Date(Exec_Date)]
sig_schedule <- sig_schedule[!is.na(Exec_Date)]
sig_schedule[, Period_End := c(Exec_Date[-1] - 1L, last_rebal_window_end)]
sig_schedule[, Period_End := as.Date(Period_End)]

n_rebal <- nrow(sig_schedule)
cat(sprintf("  Rebalance schedule: %d periods\n", n_rebal))
cat(sprintf("  First exec: %s | Last period_end: %s\n",
            sig_schedule$Exec_Date[1], sig_schedule$Period_End[n_rebal]))

turnover_per_rebal <- numeric(n_rebal)

# State: prev_w 비교를 위한 보유 weight vector (per sig_date 직전)
# 각 반복 i에서:
#   (1) 신규 weights 산정 + 비교 (vs 직전 i-1 보유 weight at exec_date)
#   (2) Rebal 실행 (sell→buy, both sides 15bps)
#   (3) Exec_Date[i] ~ Period_End[i] 동안 daily NAV 채우기 (holding period)
# 이렇게 하면 holding 기간 전체가 daily NAV로 captured 되어
# nav_cadence_label_consistency PASS + Sharpe daily 계산 가능.
for (i in seq_len(n_rebal)) {
  sig_date   <- sig_schedule$Signal_Date[i]
  exec_date  <- sig_schedule$Exec_Date[i]
  period_end <- sig_schedule$Period_End[i]

  # ── Compute pre-rebal NAV at exec_date (mark-to-market 이전 holdings) ──
  pre_nav <- if (length(holdings) == 0) {
    cash  # first iter: only initial cash
  } else {
    val <- cash
    for (tk in names(holdings)) {
      pr <- RAWDATA[Ticker == tk & Date == exec_date, Close]
      if (length(pr) > 0 && !is.na(pr[1])) {
        val <- val + holdings[[tk]]$shares * pr[1]
      } else {
        val <- val + holdings[[tk]]$shares * holdings[[tk]]$last_price
      }
    }
    val
  }

  # ── Current period weight schedule (from optimizer weights.csv as-is) ──
  w_sched <- weights_dt[Date == sig_date]
  target_tickers <- w_sched$Ticker
  target_w       <- setNames(w_sched$weight, target_tickers)
  target_w       <- target_w / sum(target_w)

  # ── Get exec_date prices for all target_tickers ──
  exec_px <- RAWDATA[Ticker %in% target_tickers & Date == exec_date, .(Ticker, Close)]
  exec_px <- exec_px[!is.na(Close) & Close > 0]
  if (nrow(exec_px) == 0) {
    cat(sprintf("    [warn] %s: no prices @ exec_date %s — skip\n", sig_date, exec_date))
    next
  }
  avail_tickers <- exec_px$Ticker
  w_avail <- target_w[avail_tickers]
  w_avail <- w_avail / sum(w_avail)

  # ── Current weights (PRE-rebal at exec_date) ──
  prev_w <- setNames(rep(0, length(avail_tickers)), avail_tickers)
  if (pre_nav > 0 && length(holdings) > 0) {
    for (tk in avail_tickers) {
      if (!is.null(holdings[[tk]])) {
        pr <- RAWDATA[Ticker == tk & Date == exec_date, Close]
        if (length(pr) > 0 && !is.na(pr[1])) {
          prev_w[tk] <- holdings[[tk]]$shares * pr[1] / pre_nav
        }
      }
    }
  }
  to_pct <- sum(abs(w_avail - prev_w)) / 2
  turnover_per_rebal[i] <- to_pct

  # ── Execute rebalance: charge commission on |delta_shares| × price (traded notional) ──
  # 1. MTM all current holdings to exec_date prices and compute MV
  current_mv <- list()  # ticker -> MV
  for (tk in names(holdings)) {
    pr <- RAWDATA[Ticker == tk & Date == exec_date, Close]
    px <- if (length(pr) > 0 && !is.na(pr[1])) pr[1] else holdings[[tk]]$last_price
    current_mv[[tk]] <- holdings[[tk]]$shares * px
  }
  total_assets <- cash + Reduce("+", current_mv, 0)  # NAV pre-rebal

  # 2. Compute target shares (target_w × total_assets / px_target)
  target_shares <- list()
  for (tk in avail_tickers) {
    pr_buy <- exec_px[Ticker == tk, Close]
    if (length(pr_buy) == 0 || is.na(pr_buy[1]) || pr_buy[1] <= 0) next
    target_alloc <- total_assets * w_avail[tk]
    target_shares[[tk]] <- list(shares = target_alloc / pr_buy[1], price = pr_buy[1])
  }

  # 3. For each ticker (union of holdings & targets), compute share delta + commission
  all_tickers <- unique(c(names(holdings), names(target_shares)))
  total_commission <- 0
  new_holdings <- list()
  cash_after <- cash
  for (tk in all_tickers) {
    prev_sh <- if (!is.null(holdings[[tk]])) holdings[[tk]]$shares else 0
    targ_sh <- if (!is.null(target_shares[[tk]])) target_shares[[tk]]$shares else 0
    px_t    <- if (!is.null(target_shares[[tk]])) target_shares[[tk]]$price
               else {
                 pr <- RAWDATA[Ticker == tk & Date == exec_date, Close]
                 if (length(pr) > 0 && !is.na(pr[1])) pr[1] else holdings[[tk]]$last_price
               }
    delta_sh <- targ_sh - prev_sh
    traded_notional <- abs(delta_sh) * px_t
    commission_paid <- traded_notional * COMMISSION
    total_commission <- total_commission + commission_paid

    # Cash flow: buying (delta > 0) reduces cash; selling (delta < 0) increases cash
    cash_after <- cash_after - delta_sh * px_t - commission_paid

    if (targ_sh > 0) {
      new_holdings[[tk]] <- list(shares = targ_sh, last_price = px_t)
    }
  }
  cash <- cash_after
  holdings <- new_holdings

  nav_post <- sum(sapply(names(holdings), function(tk) {
    holdings[[tk]]$shares * holdings[[tk]]$last_price
  })) + cash

  portfolio_log_list[[i]] <- data.table(
    Signal_Date = sig_date,
    Exec_Date   = exec_date,
    N_stocks    = length(holdings),
    NAV_pre     = pre_nav,
    NAV_post    = nav_post,
    Turnover    = to_pct,
    Cost_Drag   = pre_nav - nav_post
  )

  holdings_log_list[[i]] <- data.table(
    Signal_Date  = sig_date,
    Exec_Date    = exec_date,
    Ticker       = names(holdings),
    Weight       = sapply(names(holdings), function(tk) target_w[tk]),
    Shares       = sapply(holdings, `[[`, "shares"),
    Price_Entry  = sapply(holdings, `[[`, "last_price")
  )

  # ── Fill daily NAV during the HOLDING period (exec_date ~ period_end) ──
  holding_dates <- all_dates[all_dates >= exec_date & all_dates <= period_end]
  if (length(holding_dates) > 0 && length(holdings) > 0) {
    chunk <- .compute_daily_nav(RAWDATA, holdings, holding_dates, cash)
    for (ri in seq_len(nrow(chunk))) {
      daily_nav_list[[length(daily_nav_list) + 1]] <- chunk[ri]
    }
  }
}

# Final period beyond last sig_date period_end is already captured because
# sig_schedule$Period_End[n_rebal] = last_rebal_window_end.

DAILY_NAV_DT  <- rbindlist(daily_nav_list)
PORTFOLIO_LOG <- rbindlist(portfolio_log_list)
HOLDINGS_LOG  <- rbindlist(holdings_log_list)

# Deduplicate by date (take last NAV per Date)
setorder(DAILY_NAV_DT, Date)
DAILY_NAV_DT <- DAILY_NAV_DT[, .(NAV = last(NAV)), by = Date]
setorder(DAILY_NAV_DT, Date)

cat(sprintf("  Daily NAV rows: %d | %s ~ %s\n",
            nrow(DAILY_NAV_DT),
            min(DAILY_NAV_DT$Date), max(DAILY_NAV_DT$Date)))
cat(sprintf("  Portfolio log : %d rebals | mean TO=%.4f\n",
            nrow(PORTFOLIO_LOG), mean(PORTFOLIO_LOG$Turnover, na.rm = TRUE)))

# ─── 8. xts conversion + PerformanceAnalytics returns ─────────────────────────

cat("\n[step 7] Build xts + compute returns (PerformanceAnalytics)\n")

# strategy NAV xts
nav_xts <- xts(DAILY_NAV_DT$NAV, order.by = DAILY_NAV_DT$Date)

# Strategy daily returns via PerformanceAnalytics::CalculateReturns
ret_xts <- CalculateReturns(nav_xts, method = "discrete")
ret_xts[is.na(ret_xts)] <- 0
ret_xts <- ret_xts[-1]  # remove leading 0

# Benchmark daily returns (KOSPI200 total return — using BM_DT$BM_Ret which already is daily TR)
bm_sub <- BM_DT[Date >= bt_start_date & Date <= bt_end_date]
setorder(bm_sub, Date)
# BM_DT may have 'BM_Ret' or 'Ret' columns — try both
bm_ret_col <- {
  if ("BM_Ret" %in% names(bm_sub)) "BM_Ret"
  else if ("Ret" %in% names(bm_sub)) "Ret"
  else stop("BM_DT lacks BM_Ret/Ret column")
}
bm_xts_raw <- xts(bm_sub[[bm_ret_col]], order.by = bm_sub$Date)
bm_xts_raw[is.na(bm_xts_raw)] <- 0

# Align to common date range
common_dates <- intersect(index(ret_xts), index(bm_xts_raw))
common_dates <- sort(as.Date(common_dates, origin = "1970-01-01"))
ret_xts <- ret_xts[as.character(common_dates)]
bm_xts  <- bm_xts_raw[as.character(common_dates)]

cat(sprintf("  Strategy return obs: %d | BM return obs: %d | aligned obs: %d\n",
            length(ret_xts), length(bm_xts_raw), length(common_dates)))

# Quick performance summary using PerformanceAnalytics
total_return <- as.numeric(Return.cumulative(ret_xts))
cagr_v <- as.numeric(Return.annualized(ret_xts, scale = ANN_FACTOR))
ann_vol <- as.numeric(StdDev.annualized(ret_xts, scale = ANN_FACTOR))
sharpe <- as.numeric(SharpeRatio.annualized(ret_xts, Rf = 0, scale = ANN_FACTOR))
mdd_v <- as.numeric(maxDrawdown(ret_xts))

bm_total <- as.numeric(Return.cumulative(bm_xts))
bm_cagr  <- as.numeric(Return.annualized(bm_xts, scale = ANN_FACTOR))
bm_vol   <- as.numeric(StdDev.annualized(bm_xts, scale = ANN_FACTOR))
bm_sharpe <- as.numeric(SharpeRatio.annualized(bm_xts, Rf = 0, scale = ANN_FACTOR))
bm_mdd <- as.numeric(maxDrawdown(bm_xts))

cat("\n[Performance Summary — PerformanceAnalytics standard]\n")
cat(sprintf("  Strategy: Total=%.2f%% | CAGR=%.2f%% | Vol=%.2f%% | Sharpe=%.4f | MDD=%.2f%%\n",
            total_return * 100, cagr_v * 100, ann_vol * 100, sharpe, mdd_v * 100))
cat(sprintf("  KOSPI200: Total=%.2f%% | CAGR=%.2f%% | Vol=%.2f%% | Sharpe=%.4f | MDD=%.2f%%\n",
            bm_total * 100, bm_cagr * 100, bm_vol * 100, bm_sharpe, bm_mdd * 100))

# Active (Strategy - Benchmark)
active_xts <- ret_xts - bm_xts
ann_alpha  <- as.numeric(Return.annualized(active_xts, scale = ANN_FACTOR))
ann_te     <- as.numeric(StdDev.annualized(active_xts, scale = ANN_FACTOR))
realized_ir <- if (ann_te > 0) ann_alpha / ann_te else NA_real_

cat(sprintf("  Active  : Alpha=%.2f%% | TE=%.2f%% | IR=%.4f\n",
            ann_alpha * 100, ann_te * 100, realized_ir))

# ─── 9. Build sim_result list (for contract builders) ─────────────────────────

cat("\n[step 8] Build sim_result list for contract builders\n")

# NAV with both gross and net (gross would be cost-free; net is post-15bps)
# In our share-based sim, costs are EMBEDDED in shares (15bps deducted at buy).
# To create a separate gross NAV: same trades but no commission deducted.
# For correctness, we re-construct gross by undoing cost drag:
DAILY_NAV_DT[, NAV_net := NAV]
# Gross approximation: net + accumulated cost drag (per-rebal cumulative)
# This is a rough approximation; for full accuracy, replay sim w/ commission=0.
# Per Charter v1.0, ret_gross is derived from nav_gross. We compute ret_gross
# from a second backtest using commission=0 to be precise.

# ── Second pass: gross simulation (commission=0) ───────────────────────────
cat("  [pass 2] Compute gross NAV (commission=0)\n")
cash_g <- initial_cap
holdings_g <- list()
daily_nav_g_list <- list()

for (i in seq_len(n_rebal)) {
  sig_date   <- sig_schedule$Signal_Date[i]
  exec_date  <- sig_schedule$Exec_Date[i]
  period_end <- sig_schedule$Period_End[i]

  w_sched <- weights_dt[Date == sig_date]
  target_tickers <- w_sched$Ticker
  target_w <- setNames(w_sched$weight, target_tickers)
  target_w <- target_w / sum(target_w)

  exec_px <- RAWDATA[Ticker %in% target_tickers & Date == exec_date, .(Ticker, Close)]
  exec_px <- exec_px[!is.na(Close) & Close > 0]
  if (nrow(exec_px) == 0) next
  avail_tickers <- exec_px$Ticker
  w_avail <- target_w[avail_tickers]
  w_avail <- w_avail / sum(w_avail)

  # Compute total assets at gross
  current_mv_g <- 0
  for (tk in names(holdings_g)) {
    pr <- RAWDATA[Ticker == tk & Date == exec_date, Close]
    px <- if (length(pr) > 0 && !is.na(pr[1])) pr[1] else holdings_g[[tk]]$last_price
    current_mv_g <- current_mv_g + holdings_g[[tk]]$shares * px
  }
  total_assets_g <- cash_g + current_mv_g

  # Target shares at gross (no commission)
  new_holdings_g <- list()
  cash_remaining_g <- total_assets_g
  for (tk in avail_tickers) {
    pr_buy <- exec_px[Ticker == tk, Close]
    if (length(pr_buy) == 0 || is.na(pr_buy[1]) || pr_buy[1] <= 0) next
    alloc <- total_assets_g * w_avail[tk]
    shares <- alloc / pr_buy[1]
    new_holdings_g[[tk]] <- list(shares = shares, last_price = pr_buy[1])
    cash_remaining_g <- cash_remaining_g - alloc
  }
  cash_g <- cash_remaining_g
  holdings_g <- new_holdings_g

  # Daily NAV during holding period
  holding_dates_g <- all_dates[all_dates >= exec_date & all_dates <= period_end]
  if (length(holding_dates_g) > 0 && length(holdings_g) > 0) {
    chunk <- .compute_daily_nav(RAWDATA, holdings_g, holding_dates_g, cash_g)
    for (ri in seq_len(nrow(chunk))) {
      daily_nav_g_list[[length(daily_nav_g_list) + 1]] <- chunk[ri]
    }
  }
}

DAILY_NAV_G <- rbindlist(daily_nav_g_list)
setorder(DAILY_NAV_G, Date)
DAILY_NAV_G <- DAILY_NAV_G[, .(NAV_gross = last(NAV)), by = Date]
setorder(DAILY_NAV_G, Date)

# Merge gross into DAILY_NAV_DT
DAILY_NAV_DT <- merge(DAILY_NAV_DT, DAILY_NAV_G, by = "Date", all.x = TRUE)
# fill NA with last observation (forward fill)
DAILY_NAV_DT[, NAV_gross := nafill(NAV_gross, type = "locf")]
DAILY_NAV_DT[is.na(NAV_gross), NAV_gross := NAV_net]
DAILY_NAV_DT[, NAV := NAV_net]  # ensure NAV alias exists for harness

# bm_xts for sim_result (returns)
sim_result <- list(
  DAILY_NAV_DT  = DAILY_NAV_DT,
  PORTFOLIO_LOG = PORTFOLIO_LOG,
  HOLDINGS_LOG  = HOLDINGS_LOG,
  strategy_xts  = ret_xts,
  bm_xts        = bm_xts
)

# ─── 10. strategy_spec (Charter v1.0) ─────────────────────────────────────────

strategy_spec <- list(
  strategy_id              = STRATEGY_ID,
  strategy_name            = STRATEGY_NAME,
  strategy_family          = "multi_factor_distributional_confidence",
  signal_description       = paste(
    "DCA v7: 4-family static EW composite (defense IC=0.067, quality IC=0.021,",
    "value IC=0.045, consensus IC=0.051) × P3/P4 distributional confidence vector.",
    "Optimizer: M06_MVO_Breadth (Markowitz + Grinold-Kahn 2000 breadth,",
    "min_names=15, hhi_cap=0.10)."
  ),
  universe_rule            = "KOSPI200 ∪ KOSDAQ150 intersection, liquidity 50M won 20d avg",
  rebalance_frequency      = "monthly",
  signal_date_rule         = "month_end_last_trading_day",
  execution_date_rule      = "next_trading_day_first_biz",
  weighting_method         = "preset_M06_MVO_Breadth",
  max_position_weight      = 0.20,
  max_leverage             = 1.0,
  cash_rule                = "fully_invested_long_only",
  cost_model               = "v2.3_kr_retail_15bps",
  missing_data_rule        = "renormalize_to_available_tickers",
  risk_controls            = paste(
    "max_names=20 / weight[0,0.20] / Σw=1 / long-only / Ledoit-Wolf Σ (cond=14.51)",
    "/ EVT GPD tail risk diagnostic / regime correlation diagnostic"
  ),
  lookahead_prevention     = "PIT C1-C15: rolling/expanding stats, T+1 exec, t-1 liq, factor lag respected (alpha + risk + opt agents)",
  survivorship_bias_control = "KOSPI200/KOSDAQ150 historical members; RAWDATA includes delisted (Factor DB universe definition)",
  factor_engine_path       = file.path(WT_DIR, "alpha_pipeline.R")
)

# ─── 11. Build bt_result (10-component) ───────────────────────────────────────

cat("\n[step 9] Build bt_result (Charter v1.0 10-component)\n")

run_id <- sprintf("%s_%s_%s",
                  WT_ID, STRATEGY_ID,
                  format(Sys.time(), "%Y%m%d_%H%M%S"))

bt_result <- build_bt_result(
  sim_result            = sim_result,
  strategy_spec         = strategy_spec,
  run_id                = run_id,
  strategy_id           = STRATEGY_ID,
  strategy_version      = STRATEGY_VER,
  benchmark_id          = "KOSPI200",
  benchmark_name        = "KOSPI 200 Total Return",
  transaction_cost_bps  = 15,
  slippage_bps          = 0,
  risk_free_rate        = 0,
  frequency             = "daily",
  annualization_factor  = ANN_FACTOR,
  universe_id           = "KOSPI200_KOSDAQ150_LIQ_50M",
  code_version          = sprintf("STR_1719_DCA_v7_forge_v1.0_run_all_%s",
                                   format(Sys.Date(), "%Y%m%d")),
  created_by_agent      = "Forge"
)

cat(sprintf("  bt_result components: %s\n", paste(names(bt_result), collapse = ", ")))
cat(sprintf("  metrics rows: %d | nav rows: %d | period_returns rows: %d\n",
            nrow(bt_result$metrics), nrow(bt_result$nav),
            nrow(bt_result$period_returns)))

# ─── 12. Audit (10+ checks) ───────────────────────────────────────────────────

cat("\n[step 10] Run audit_bt_result\n")

bt_result <- audit_bt_result(bt_result)

audit_summary <- bt_result$audit[, .(
  n = .N,
  pass = sum(status == "PASS"),
  fail = sum(status == "FAIL"),
  warn = sum(status == "WARN")
), by = check_group]

cat("\n[Audit summary]\n")
print(audit_summary)

n_critical_fail <- nrow(bt_result$audit[severity == "critical" & status == "FAIL"])
n_high_fail     <- nrow(bt_result$audit[severity == "high" & status == "FAIL"])
integrity_status <- bt_result$manifest$integrity_status[1]
cat(sprintf("\n  Integrity status: %s | critical_fail=%d | high_fail=%d\n",
            integrity_status, n_critical_fail, n_high_fail))

# ─── 13. Save bt_result (RDS + CSV × 10 + JSON × 2 + XLSX) ────────────────────

cat("\n[step 11] Save bt_result to output dir\n")

saved <- save_bt_result(bt_result, OUT_DIR, save_xlsx = TRUE)
cat(sprintf("  Saved %d files\n", length(saved)))

# Summary JSON for forge_package
summary_json_path <- file.path(OUT_DIR, "bt_result_summary.json")
get_official_metric <- function(name) {
  m <- bt_result$metrics
  val <- m[metric_name == name & is_official == TRUE & metric_type == "backtested",
            metric_value]
  if (length(val) == 0) NA_real_ else as.numeric(val[1])
}
get_bm_metric <- function(name) {
  bc <- bt_result$benchmark_compare
  if (is.null(bc) || nrow(bc) == 0) return(NA_real_)
  val <- bc[metric_name == name, active_value]
  if (length(val) == 0) NA_real_ else as.numeric(val[1])
}
summary_obj <- list(
  run_id              = run_id,
  task_id             = WT_ID,
  strategy_id         = STRATEGY_ID,
  strategy_version    = STRATEGY_VER,
  integrity_status    = integrity_status,
  start_date          = format(min(DAILY_NAV_DT$Date), "%Y-%m-%d"),
  end_date            = format(max(DAILY_NAV_DT$Date), "%Y-%m-%d"),
  total_return_pct    = round(100 * get_official_metric("Total_Return"), 4),
  cagr_pct            = round(100 * get_official_metric("CAGR"), 4),
  ann_vol_pct         = round(100 * get_official_metric("Annualized_Volatility"), 4),
  sharpe              = round(get_official_metric("Sharpe"), 4),
  sortino             = round(get_official_metric("Sortino"), 4),
  calmar              = round(get_official_metric("Calmar"), 4),
  mdd_pct             = round(100 * get_official_metric("MDD"), 4),
  max_dd_duration_m   = round(get_official_metric("Max_DD_Duration_Months"), 1),
  cvar_99_daily_pct   = round(100 * get_official_metric("CVaR_99"), 4),
  benchmark_alpha_pct = round(100 * get_bm_metric("Alpha_Annualized"), 4),
  benchmark_beta      = round(get_bm_metric("Beta_to_Benchmark") + 1, 4),  # active+1 = strategy
  tracking_error_pct  = round(100 * get_bm_metric("Tracking_Error"), 4),
  information_ratio   = round(get_bm_metric("Information_Ratio"), 4),
  up_capture          = round(get_bm_metric("Up_Capture") + 1, 4),
  down_capture        = round(get_bm_metric("Down_Capture") + 1, 4),
  hit_ratio_vs_bm     = round(get_bm_metric("Hit_Ratio_vs_BM") + 0.5, 4),
  avg_turnover_perreb = round(get_official_metric("Average_Turnover"), 4),
  ann_turnover_l1     = round(get_official_metric("Annualized_Turnover"), 4),
  avg_n_holdings      = round(get_official_metric("Average_N_Holdings"), 2),
  audit = list(
    integrity_status = integrity_status,
    n_critical_fail  = n_critical_fail,
    n_high_fail      = n_high_fail,
    n_pass           = nrow(bt_result$audit[status == "PASS"]),
    n_warn           = nrow(bt_result$audit[status == "WARN"]),
    n_fail           = nrow(bt_result$audit[status == "FAIL"])
  )
)
write_json(summary_obj, summary_json_path, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("  Summary JSON: %s\n", summary_json_path))

# ─── 14. Charts (mandatory v6.1 OOS Chart Mandate) ────────────────────────────

cat("\n[step 12] Generate mandatory charts\n")

# Equity curve (with benchmark)
tryCatch({
  png(file.path(OUT_DIR, "equity_curve.png"), width = 1300, height = 750, res = 130)
  cum_strat <- cumprod(1 + na.omit(coredata(ret_xts)))
  cum_bm    <- cumprod(1 + na.omit(coredata(bm_xts)))
  common_idx <- index(ret_xts[!is.na(coredata(ret_xts))])
  df_plot <- data.frame(
    Date     = common_idx[seq_along(cum_strat)],
    Strategy = cum_strat,
    KOSPI200 = cum_bm[seq_along(cum_strat)]
  )
  df_long <- data.table::melt(as.data.table(df_plot), id.vars = "Date",
                               variable.name = "Series", value.name = "Growth")
  p <- ggplot(df_long, aes(x = Date, y = Growth, color = Series)) +
    geom_line(linewidth = 0.85) +
    scale_color_manual(values = c("Strategy" = "#1f77b4", "KOSPI200" = "#ff7f0e")) +
    labs(title = sprintf("%s — Walk-Forward Equity Curve", STRATEGY_ID),
         subtitle = sprintf(
           "CAGR=%.2f%% Vol=%.2f%% Sharpe=%.4f MDD=%.2f%% | BM CAGR=%.2f%% Sharpe=%.4f",
           100 * cagr_v, 100 * ann_vol, sharpe, 100 * mdd_v,
           100 * bm_cagr, bm_sharpe),
         x = NULL, y = "Cumulative Growth (1=base)") +
    theme_minimal(base_size = 13) +
    theme(legend.position = "bottom")
  print(p)
  dev.off()
  cat("  equity_curve.png saved\n")
}, error = function(e) {
  cat(sprintf("  equity_curve error: %s\n", e$message))
})

# Annual returns
tryCatch({
  png(file.path(OUT_DIR, "annual_returns.png"), width = 1300, height = 700, res = 130)
  yr_ret <- as.numeric(apply.yearly(ret_xts, Return.cumulative))
  yr_bm  <- as.numeric(apply.yearly(bm_xts,  Return.cumulative))
  yr_idx <- format(index(apply.yearly(ret_xts, Return.cumulative)), "%Y")
  n_min <- min(length(yr_ret), length(yr_bm), length(yr_idx))
  df_yr <- data.table(
    Year      = yr_idx[seq_len(n_min)],
    Strategy  = yr_ret[seq_len(n_min)] * 100,
    KOSPI200  = yr_bm[seq_len(n_min)]  * 100
  )
  df_yr_long <- data.table::melt(df_yr, id.vars = "Year",
                                  variable.name = "Series",
                                  value.name = "Return_pct")
  p <- ggplot(df_yr_long, aes(x = Year, y = Return_pct, fill = Series)) +
    geom_col(position = "dodge") +
    scale_fill_manual(values = c("Strategy" = "#1f77b4", "KOSPI200" = "#ff7f0e")) +
    geom_text(aes(label = sprintf("%.1f", Return_pct)),
              position = position_dodge(width = 0.9),
              vjust = -0.3, size = 3) +
    labs(title = sprintf("%s — Annual Returns (Strategy vs KOSPI200)", STRATEGY_ID),
         x = NULL, y = "Annual Return (%)") +
    theme_minimal(base_size = 13) +
    theme(legend.position = "bottom")
  print(p)
  dev.off()
  cat("  annual_returns.png saved\n")
}, error = function(e) {
  cat(sprintf("  annual_returns error: %s\n", e$message))
})

# OOS zoom chart (recent 3Y — given lockbox cutoff 2023-12, "recent 3Y" = 2021~2023)
tryCatch({
  zoom_start <- as.Date("2021-01-01")
  zoom_xts_r <- ret_xts[paste0(zoom_start, "/")]
  zoom_xts_b <- bm_xts[paste0(zoom_start, "/")]
  if (length(zoom_xts_r) > 60) {
    png(file.path(OUT_DIR, "oos_zoom_chart.png"), width = 1300, height = 750, res = 130)
    cum_zs <- cumprod(1 + na.omit(coredata(zoom_xts_r)))
    cum_zb <- cumprod(1 + na.omit(coredata(zoom_xts_b)))
    df_zoom <- data.frame(
      Date     = index(zoom_xts_r),
      Strategy = cum_zs[seq_along(index(zoom_xts_r))],
      KOSPI200 = cum_zb[seq_along(index(zoom_xts_r))]
    )
    df_zoom_long <- data.table::melt(as.data.table(df_zoom), id.vars = "Date",
                                      variable.name = "Series",
                                      value.name = "Growth")
    p <- ggplot(df_zoom_long, aes(x = Date, y = Growth, color = Series)) +
      geom_line(linewidth = 0.9) +
      scale_color_manual(values = c("Strategy" = "#1f77b4",
                                     "KOSPI200" = "#ff7f0e")) +
      labs(title = sprintf("%s — Recent 3Y Zoom (Pre-Lockbox)", STRATEGY_ID),
           subtitle = sprintf("Period: %s to %s",
                               format(min(index(zoom_xts_r)), "%Y-%m-%d"),
                               format(max(index(zoom_xts_r)), "%Y-%m-%d")),
           x = NULL, y = "Cumulative Growth (1=base, zoom-period)") +
      theme_minimal(base_size = 13) +
      theme(legend.position = "bottom")
    print(p)
    dev.off()
    cat("  oos_zoom_chart.png saved\n")
  }
}, error = function(e) {
  cat(sprintf("  oos_zoom error: %s\n", e$message))
})

# Drawdown chart
tryCatch({
  png(file.path(OUT_DIR, "drawdown_chart.png"), width = 1300, height = 600, res = 130)
  dd_xts <- Drawdowns(ret_xts)
  bm_dd  <- Drawdowns(bm_xts)
  df_dd <- data.frame(
    Date      = index(dd_xts),
    Strategy  = as.numeric(dd_xts) * 100,
    KOSPI200  = as.numeric(bm_dd[index(dd_xts)]) * 100
  )
  df_dd_long <- data.table::melt(as.data.table(df_dd), id.vars = "Date",
                                  variable.name = "Series", value.name = "DD")
  p <- ggplot(df_dd_long, aes(x = Date, y = DD, color = Series)) +
    geom_line(linewidth = 0.7) +
    scale_color_manual(values = c("Strategy" = "#1f77b4", "KOSPI200" = "#ff7f0e")) +
    labs(title = sprintf("%s — Drawdown Profile", STRATEGY_ID),
         x = NULL, y = "Drawdown (%)") +
    theme_minimal(base_size = 13) +
    theme(legend.position = "bottom")
  print(p)
  dev.off()
  cat("  drawdown_chart.png saved\n")
}, error = function(e) {
  cat(sprintf("  drawdown error: %s\n", e$message))
})

# ─── 15. Register to backtest_registry.csv ────────────────────────────────────

cat("\n[step 13] Register to backtest_registry.csv\n")

reg_result <- register_bt_result(bt_result, block_on_fail = TRUE)
if (isTRUE(reg_result$blocked)) {
  cat(sprintf("  L3 BLOCK: %s\n", reg_result$reason))
} else {
  cat(sprintf("  Registered: total_entries=%d\n", reg_result$total_entries))
}

# ─── 16. Boundary integrity — END hashes ──────────────────────────────────────

cat("\n[step 14] Boundary integrity (END hashes — must match START)\n")

hash_end <- list(
  alpha_package   = digest(file = alpha_pkg_path, algo = "md5"),
  risk_package    = digest(file = risk_pkg_path,  algo = "md5"),
  opt_package     = digest(file = opt_pkg_path,   algo = "md5"),
  weights_csv     = digest(file = weights_path,   algo = "md5")
)

hash_consistent <- all(
  hash_start$alpha_package == hash_end$alpha_package,
  hash_start$risk_package  == hash_end$risk_package,
  hash_start$opt_package   == hash_end$opt_package,
  hash_start$weights_csv   == hash_end$weights_csv
)

cat(sprintf("  Pure function boundary: %s\n",
            if (hash_consistent) "PASS (3-package + weights.csv unchanged)"
            else "FAIL — INTEGRITY VIOLATION"))

if (!hash_consistent) {
  cat("  [DEBUG] hash diff:\n")
  for (k in names(hash_start)) {
    if (hash_start[[k]] != hash_end[[k]]) {
      cat(sprintf("    %s: start=%s end=%s\n", k, hash_start[[k]], hash_end[[k]]))
    }
  }
  stop("Pure function boundary VIOLATED — alpha/risk/opt/weights mutated during Forge run")
}

# ─── 17. Lineage record ───────────────────────────────────────────────────────

cat("\n[step 15] Record artifact lineage\n")

setwd(PROJECT_ROOT)
lineage_entry <- record_package_lineage(
  task_id = WT_ID,
  package_type = "forge_package",
  method_selected = "M06_MVO_Breadth",
  input_file_paths = c(alpha_pkg_path, risk_pkg_path, opt_pkg_path, weights_path),
  windows = list(
    backtest_start = format(min(DAILY_NAV_DT$Date), "%Y-%m-%d"),
    backtest_end   = format(max(DAILY_NAV_DT$Date), "%Y-%m-%d"),
    sig_first      = format(SIG_FIRST, "%Y-%m-%d"),
    sig_last       = format(SIG_LAST,  "%Y-%m-%d"),
    n_rebals       = n_rebal
  ),
  random_seed = 20260527L
)

# ─── 18. Done ─────────────────────────────────────────────────────────────────

cat("\n============================================================\n")
cat(sprintf("Forge complete: integrity=%s | run_id=%s\n",
            integrity_status, run_id))
cat(sprintf("Strategy: CAGR=%.2f%% | Sharpe=%.4f | MDD=%.2f%% | IR=%.4f | TO=%.1f/y\n",
            100 * cagr_v, sharpe, 100 * mdd_v, realized_ir,
            get_official_metric("Annualized_Turnover") %||% NA))
cat(sprintf("Output: %s\n", OUT_DIR))
cat("============================================================\n")

# Final return objects for downstream consumption
forge_summary <- list(
  run_id              = run_id,
  strategy_id         = STRATEGY_ID,
  task_id             = WT_ID,
  integrity_status    = integrity_status,
  hash_start          = hash_start,
  hash_end            = hash_end,
  pure_fn_pass        = hash_consistent,
  bt_result_summary   = summary_obj
)
invisible(forge_summary)
