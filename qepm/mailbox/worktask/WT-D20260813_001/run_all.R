#==============================================================================
# Forge Integration — WT-D20260813_001 run_all.R
# q90 pinball LGBM (upside quantile target) — forge re-measurement
#
# Agent: Forge v6.1 Pure Function
#
# HARD MANDATE:
#   - 3-package read-only (alpha/risk/optimization 수정 절대 금지)
#   - target_weights 수정 금지 — weights.csv 그대로 사용 (schedule fidelity)
#   - 15bps delta-based cost (v2.4_kr_retail_15bps)
#   - metric_type = "backtested" (forge-authoritative)
#   - graduation HARD 3종 통과 주장 X — 실측 정직 보고
#   - Hash audit: start/end md5sum 일치 확인
#==============================================================================

cat("=== WT-D20260813_001 Forge — q90 pinball LGBM re-measurement ===\n")
cat(sprintf("Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

# ──────────────────────────────────────────────────────────
# 0. Project Root + 시작 Hash 검증
# ──────────────────────────────────────────────────────────
PROJECT_ROOT <- Sys.getenv("QM_ROOT",
                  unset = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
WT_ID   <- "WT-D20260813_001"
WT_DIR  <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", WT_ID)
OUT_DIR <- file.path(STAGE_DIR, "backtest_result")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

cat("\n[Hash Audit] START — 3-package md5sum\n")
ALPHA_PKG_PATH <- file.path(WT_DIR, "alpha_package.json")
RISK_PKG_PATH  <- file.path(WT_DIR, "risk_package.json")
OPT_PKG_PATH   <- file.path(WT_DIR, "optimization_package.json")
hash_start <- list(
  alpha = tools::md5sum(ALPHA_PKG_PATH),
  risk  = tools::md5sum(RISK_PKG_PATH),
  opt   = tools::md5sum(OPT_PKG_PATH)
)
cat(sprintf("  alpha: %s\n  risk:  %s\n  opt:   %s\n",
            hash_start$alpha, hash_start$risk, hash_start$opt))

# ──────────────────────────────────────────────────────────
# 1. Libraries + Infrastructure
# ──────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(zoo); library(PerformanceAnalytics)
  library(ggplot2); library(scales); library(sandwich); library(lmtest)
})

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/audit_bt_result.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/essence_score.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/no_signal_control.R"))

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

# ──────────────────────────────────────────────────────────
# 2. Weights 로드 + Hard Constraint 재검증 (as-is, schedule fidelity)
# ──────────────────────────────────────────────────────────
cat("\n[Step 1] Load weights.csv + Hard Constraint check\n")
WEIGHTS_PATH <- file.path(STAGE_DIR, "weights.csv")
w_dt <- fread(WEIGHTS_PATH)
w_dt[, as_of_date  := as.Date(as_of_date)]
w_dt[, holding_month := as.Date(holding_month)]
setnames(w_dt, "weight", "Weight")

holding_months <- sort(unique(w_dt$holding_month))
cat(sprintf("  Unique holding_months: %d | %s ~ %s\n",
            length(holding_months), min(holding_months), max(holding_months)))

# max 25 names
npd <- w_dt[Weight > 1e-9, .N, by = holding_month]
stopifnot("n_names > 25 violation" = all(npd$N <= 25))
cat(sprintf("  max_names: %d <= 25 PASS\n", max(npd$N)))
# long-only
stopifnot("long_only violation" = nrow(w_dt[Weight < -1e-9]) == 0)
cat("  long-only: PASS\n")
# weight bounds [0, 0.20]
stopifnot("weight > 0.20 violation" = nrow(w_dt[Weight > 0.20 + 1e-6]) == 0)
cat("  weight_bounds [0, 0.20]: PASS\n")
# sum = 1 per holding_month
spd <- w_dt[, .(sw = sum(Weight)), by = holding_month]
stopifnot("Sigma_w != 1" = nrow(spd[abs(sw - 1) > 0.001]) == 0)
cat("  Sigma_w = 1 (all months): PASS\n")

# ──────────────────────────────────────────────────────────
# 3. RAWDATA 로드
# ──────────────────────────────────────────────────────────
cat("\n[Step 2] Load RAWDATA\n")
rd_all <- load_rawdata(use_cache = TRUE)
RAWDATA <- rd_all$RAWDATA
BM_DT   <- rd_all$BM_DT
setkey(RAWDATA, Date, Ticker)
all_dates_rd <- sort(unique(RAWDATA$Date))
cat(sprintf("  RAWDATA: %s rows | %s ~ %s\n",
            format(nrow(RAWDATA), big.mark = ","), min(RAWDATA$Date), max(RAWDATA$Date)))

# ──────────────────────────────────────────────────────────
# 4. Walk-Forward Backtest — holding_month schedule as-is
#    weights.csv holding_month = 보유 시작(수익 벌리는 달). PIT: sig=as_of_date(월말),
#    holding=익월+1 첫거래일. 각 holding_month 를 exec/entry 로 그대로 소비.
#    delta-based 15bps: 종목별 |Δ보유명목| 절대값 × 0.0015 (레그당).
# ──────────────────────────────────────────────────────────
cat("\n[Step 3] Walk-Forward Backtest (weights.csv holding schedule -> daily NAV)\n")
COMMISSION  <- 0.0015    # 15bps one-way, delta-based
INITIAL_CAP <- 1e8

# 각 holding_month h -> entry_date = first trading day >= h
entry_of <- function(hm) {
  cand <- all_dates_rd[all_dates_rd >= hm]
  if (length(cand) == 0) return(as.Date(NA)) else as.Date(cand[1])
}
entry_dates <- as.Date(vapply(holding_months, function(x) as.numeric(entry_of(x)), numeric(1)),
                       origin = "1970-01-01")
keep <- !is.na(entry_dates)
holding_months <- holding_months[keep]
entry_dates    <- entry_dates[keep]
cat(sprintf("  Effective holding periods: %d | first entry %s | last entry %s\n",
            length(entry_dates), min(entry_dates), max(entry_dates)))

daily_nav_list <- list()
portfolio_log  <- list()
holdings_log_list <- list()

cash      <- INITIAL_CAP
holdings  <- list()   # ticker -> list(shares, last_price, weight)
prev_date <- min(all_dates_rd)
prev_w    <- setNames(numeric(0), character(0))

for (hi in seq_along(holding_months)) {
  if (hi %% 40 == 0) cat(sprintf("  ... holding %d / %d\n", hi, length(holding_months)))
  hm        <- holding_months[hi]
  exec_date <- entry_dates[hi]

  # daily NAV from prev_date (excl) to exec_date (incl) holding old book
  exec_range <- all_dates_rd[all_dates_rd > prev_date & all_dates_rd <= exec_date]
  if (length(exec_range) > 0 && length(holdings) > 0) {
    daily_nav_list <- c(daily_nav_list,
                        list(.compute_daily_nav(RAWDATA, holdings, exec_range, cash)))
  }

  # target weights for this holding month (as-is)
  w_at <- w_dt[holding_month == hm & Weight > 1e-9, .(Ticker, Weight)]

  # execution prices at exec_date (union of old + new)
  tickers_all <- unique(c(names(holdings), w_at$Ticker))
  ep <- RAWDATA[Ticker %in% tickers_all & Date == exec_date, .(Ticker, Close)][!is.na(Close)]
  w_tr <- w_at[Ticker %in% ep$Ticker]
  if (nrow(w_tr) == 0) { prev_date <- exec_date; next }
  # renormalize among tradeable (fully invested, no cash sleeve in schedule)
  w_tr[, W_norm := Weight / sum(Weight)]

  # current portfolio value marked at exec_date
  curr_val <- 0
  for (tk in names(holdings)) {
    prn <- ep[Ticker == tk, Close]
    if (length(prn) == 0 || is.na(prn[1])) prn <- holdings[[tk]]$last_price
    curr_val <- curr_val + holdings[[tk]]$shares * prn[1]
  }
  total_val <- curr_val + cash

  # ── delta-based rebalance: charge 15bps on |Δ notional| per name per leg ──
  target_notional <- setNames(w_tr$W_norm * total_val, w_tr$Ticker)
  all_names <- union(names(holdings), names(target_notional))
  cost_total <- 0
  new_holdings <- list()
  invested <- 0
  for (tk in all_names) {
    prn <- ep[Ticker == tk, Close]
    if (length(prn) == 0 || is.na(prn[1])) {
      prn <- if (tk %in% names(holdings)) holdings[[tk]]$last_price else NA_real_
    } else prn <- prn[1]
    cur_notional <- if (tk %in% names(holdings)) {
      pp <- ep[Ticker == tk, Close]
      if (length(pp) == 0 || is.na(pp[1])) holdings[[tk]]$shares * holdings[[tk]]$last_price
      else holdings[[tk]]$shares * pp[1]
    } else 0
    tgt_notional <- if (tk %in% names(target_notional)) target_notional[[tk]] else 0
    cost_total <- cost_total + abs(tgt_notional - cur_notional) * COMMISSION
    if (tgt_notional > 0 && !is.na(prn) && prn > 0) {
      shr <- floor(tgt_notional / prn)
      new_holdings[[tk]] <- list(shares = shr, last_price = prn,
                                 weight = w_tr[Ticker == tk, W_norm])
      invested <- invested + shr * prn
    }
  }
  cash <- total_val - invested - cost_total

  # turnover (weight-diff L1/2)
  cur_w <- setNames(w_tr$W_norm, w_tr$Ticker)
  u <- union(names(prev_w), names(cur_w))
  to_pct <- sum(abs((cur_w[u] %||% 0) - (prev_w[u] %||% 0)), na.rm = TRUE)
  to_oneway <- sum(abs(ifelse(is.na(cur_w[u]), 0, cur_w[u]) -
                       ifelse(is.na(prev_w[u]), 0, prev_w[u]))) / 2

  portfolio_log[[hi]] <- data.table(
    Signal_Date = w_dt[holding_month == hm, as_of_date][1],
    Exec_Date   = exec_date,
    N_stocks    = nrow(w_tr),
    NAV         = total_val,
    Turnover_oneway = round(to_oneway, 4)
  )
  h_rows <- lapply(names(new_holdings), function(tk) {
    nm <- RAWDATA[Ticker == tk & Date == exec_date, Name]
    sc <- RAWDATA[Ticker == tk & Date == exec_date, Sector]
    data.table(Signal_Date = w_dt[holding_month == hm, as_of_date][1],
               Exec_Date = exec_date, Ticker = tk,
               Name = if (length(nm) > 0) nm[1] else NA_character_,
               Sector = if (length(sc) > 0) sc[1] else NA_character_,
               Weight = new_holdings[[tk]]$weight,
               Price = new_holdings[[tk]]$last_price)
  })
  holdings_log_list[[hi]] <- rbindlist(h_rows, fill = TRUE)

  holdings  <- new_holdings
  prev_date <- exec_date
  prev_w    <- cur_w
}

# final daily NAV after last holding month (hold to end of data)
rem <- all_dates_rd[all_dates_rd > prev_date]
if (length(rem) > 0 && length(holdings) > 0) {
  daily_nav_list <- c(daily_nav_list, list(.compute_daily_nav(RAWDATA, holdings, rem, cash)))
}

DAILY_NAV_DT  <- rbindlist(daily_nav_list)
PORTFOLIO_LOG <- rbindlist(portfolio_log, fill = TRUE)
HOLDINGS_LOG  <- if (length(holdings_log_list) > 0) rbindlist(holdings_log_list, fill = TRUE) else data.table()
setorder(DAILY_NAV_DT, Date)
DAILY_NAV_DT <- unique(DAILY_NAV_DT, by = "Date")
DAILY_NAV_DT[, NAV_gross := NAV]  # cost already netted into NAV; gross tracked separately below
cat(sprintf("  Daily NAV rows: %d | %s ~ %s\n",
            nrow(DAILY_NAV_DT), min(DAILY_NAV_DT$Date), max(DAILY_NAV_DT$Date)))

# ──────────────────────────────────────────────────────────
# 5. sim_result assembly (contract input)
#    freq=monthly: contract build_metrics uses nav length with annualization_factor=12.
#    ⇒ NAV series fed to sim_result must be MONTHLY (last NAV per month) so
#      CAGR=(final/initial)^(12/n_months)-1 is correct (daily-length NAV would corrupt
#      CAGR/Calmar — self-adversarial check caught this: daily-len NAV gave CAGR 0.66%
#      vs true monthly-compounded 14.52%). period_returns already monthly via apply.monthly.
# ──────────────────────────────────────────────────────────
DAILY_NAV_DT[, Strategy_Ret := NAV / shift(NAV) - 1]
strat_xts_daily <- xts(DAILY_NAV_DT$Strategy_Ret[-1], order.by = DAILY_NAV_DT$Date[-1])

# monthly NAV (last trading-day NAV per calendar month)
DAILY_NAV_DT[, ym := format(Date, "%Y-%m")]
MONTHLY_NAV_DT <- DAILY_NAV_DT[, .SD[.N], by = ym, .SDcols = c("Date", "NAV")]
setorder(MONTHLY_NAV_DT, Date)
MONTHLY_NAV_DT[, NAV_gross := NAV]

# strategy monthly returns (from daily, PerformanceAnalytics apply.monthly)
strat_m_xts <- apply.monthly(strat_xts_daily, Return.cumulative)

# benchmark daily returns aligned to strategy dates (KOSPI200)
bm_daily <- BM_DT[Date %in% DAILY_NAV_DT$Date, .(Date, BM_Ret)]
setorder(bm_daily, Date)
bm_xts_daily <- xts(bm_daily$BM_Ret, order.by = bm_daily$Date)

sim_result <- list(
  DAILY_NAV_DT  = MONTHLY_NAV_DT[, .(Date, NAV, NAV_gross)],  # monthly for correct CAGR
  strategy_xts  = strat_xts_daily,   # daily; contract aggregates to monthly
  bm_xts        = bm_xts_daily,      # daily; contract aggregates to monthly
  HOLDINGS_LOG  = HOLDINGS_LOG,
  PORTFOLIO_LOG = PORTFOLIO_LOG,
  cost_model_version = "v2.4_kr_retail_15bps"
)

strategy_spec <- list(
  strategy_id = "WT_D20260813_001_q90_pinball",
  strategy_name = "q90 pinball LGBM upside quantile top-25 EW semicap50",
  strategy_family = "target_form/upside_quantile",
  signal_description = "conditional q90 (pinball tau=0.9, LightGBM, 324 registry factors)",
  universe_rule = "KOSPI200 U KOSDAQ150",
  rebalance_frequency = "monthly",
  signal_date_rule = "month_end_sig; holding starts month+1 first trading day",
  execution_date_rule = "holding_month first trading day",
  weighting_method = "EW top-25 + semiconductor cap 0.50",
  max_position_weight = 0.20, max_leverage = 1,
  cash_rule = "fully invested", cost_model = "v2.4_kr_retail_15bps delta-based",
  missing_data_rule = "renormalize among tradeable",
  risk_controls = "sector cap 0.50 (semiconductor)",
  lookahead_prevention = "walk-forward train sig_date < holding anchor; features load_month_factors Z_Score_Aligned",
  survivorship_bias_control = "K200/KQ150 membership panel",
  cost_model_version = "v2.4_kr_retail_15bps"
)

# ──────────────────────────────────────────────────────────
# 6. build_bt_result (10-component, monthly basis for graduation metrics)
#    forge-authoritative: metrics on monthly returns (annualization=12)
# ──────────────────────────────────────────────────────────
cat("\n[Step 4] build_bt_result (monthly basis, PerformanceAnalytics 표준)\n")
bt_result <- build_bt_result(
  sim_result, strategy_spec,
  run_id = sprintf("forge_%s_%s", WT_ID, format(Sys.time(), "%Y%m%d%H%M%S")),
  strategy_id = "WT_D20260813_001_q90_pinball",
  strategy_version = "forge_v6.1",
  benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
  transaction_cost_bps = 15, slippage_bps = 0,
  frequency = "monthly", annualization_factor = 12,
  universe_id = "K200_KQ150",
  code_version = "forge_run_all_wt813",
  created_by_agent = "forge"
)
bt_result <- audit_bt_result(bt_result)

# ──────────────────────────────────────────────────────────
# 7. 핵심 지표 추출 (forge-authoritative)
# ──────────────────────────────────────────────────────────
cat("\n[Step 5] Extract forge-authoritative metrics\n")
bc <- as.data.table(bt_result$benchmark_compare)
mt <- as.data.table(bt_result$metrics)

getbc <- function(nm) { v <- bc[metric_name == nm, active_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
getm  <- function(nm) { v <- mt[metric_name == nm, metric_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }

port_t_nw3 <- getbc("Portfolio_Alpha_t_NW_lag3")
ann_sr   <- getm("Sharpe")
ann_cagr <- getm("CAGR")
ann_mdd  <- getm("MDD")
calmar   <- getm("Calmar")

# beta-controlled alpha t (measurement-graduation §2) — NW lag-3 on monthly
prtb <- as.data.table(bt_result$period_returns)
brtb <- as.data.table(bt_result$benchmark_returns)
mrg  <- merge(prtb[, .(date, ret_net)], brtb[, .(date, benchmark_ret)], by = "date")
setorder(mrg, date)
reg_ba <- lm(ret_net ~ benchmark_ret, data = mrg)
ct_ba  <- coeftest(reg_ba, vcov = NeweyWest(reg_ba, lag = 3, prewhite = FALSE))
alpha_t_beta_adj <- as.numeric(ct_ba[1, 3])
alpha_ann_beta_adj <- as.numeric(ct_ba[1, 1]) * 12
beta_to_bm <- as.numeric(ct_ba[2, 1])

cat(sprintf("  PORT_t (NW lag-3, mean active) = %.4f\n", port_t_nw3))
cat(sprintf("  beta-controlled t(alpha)       = %.4f  (alpha_ann=%.4f, beta=%.4f)\n",
            alpha_t_beta_adj, alpha_ann_beta_adj, beta_to_bm))
cat(sprintf("  ann_SR=%.4f | ann_CAGR=%.4f | ann_MDD=%.4f | calmar=%.4f\n",
            ann_sr, ann_cagr, ann_mdd, calmar))

# ──────────────────────────────────────────────────────────
# 8. oos_retention (essence_score v2, anchored 55/65/75 median)
# ──────────────────────────────────────────────────────────
cat("\n[Step 6] oos_retention via essence_score (v2)\n")
ess <- tryCatch(
  essence_score(bt_result, n_trials_cumulative = 1, selection_type = "chain",
                oos_stat_version = "v2"),
  error = function(e) { cat(sprintf("  [WARN] essence_score: %s\n", conditionMessage(e))); NULL }
)
# essence_score exposes retention at $essence$oos_retention (scalar) + $oos_retention_splits (vec).
oos_splits <- if (!is.null(ess)) as.numeric(ess$oos_retention_splits) else NA_real_
oos_retention <- if (!is.null(ess)) {
  v <- suppressWarnings(as.numeric(ess$essence$oos_retention))
  if (length(v) == 1 && is.finite(v)) v
  else if (any(is.finite(oos_splits))) stats::median(oos_splits[is.finite(oos_splits)])
  else NA_real_
} else NA_real_
oos_retention <- as.numeric(oos_retention)[1]
oos_str <- if (is.finite(oos_retention)) sprintf("%.4f", oos_retention) else "NA"
cat(sprintf("  oos_retention (median 55/65/75) = %s | splits = %s\n",
            oos_str, paste(round(oos_splits, 3), collapse = "/")))

# ──────────────────────────────────────────────────────────
# 9. no_signal_gate (제약형 롱온리 대조군: 시총 상위 25종 cap-w)
# ──────────────────────────────────────────────────────────
cat("\n[Step 7] no_signal_gate (market-cap top-25 cap-w control)\n")
# strategy monthly returns aligned to control month grid
strat_m <- prtb[, .(ym = format(date, "%Y-%m"), ret_net)]
strat_m <- strat_m[order(ym)]
bm_m    <- brtb[, .(ym = format(date, "%Y-%m"), benchmark_ret)]
bm_m    <- bm_m[order(ym)]
mgrid   <- strat_m$ym

nsg_result <- "미시행"; nsg_note <- NULL; nsg_full <- NULL
nsg <- tryCatch({
  ctl <- build_no_signal_control(months = mgrid, n_stocks = 25L, cap = 0.20,
                                 freq = 1L, bps = 15,
                                 rawdata_path = file.path(PROJECT_ROOT, ".cache/rawdata.parquet"))
  # align: strat/ctl/bm on mgrid
  strat_vec <- strat_m$ret_net
  bm_vec    <- bm_m[match(mgrid, ym), benchmark_ret]
  res <- no_signal_gate(strat_vec, ctl$ret, bm_vec)
  res
}, error = function(e) { nsg_note <<- conditionMessage(e); NULL })

if (!is.null(nsg)) {
  nsg_result <- nsg$verdict
  nsg_full <- nsg
  cat(sprintf("  verdict = %s | diff_ann=%.4f diff_NW_t=%.4f corr=%.4f\n",
              nsg$verdict, nsg$diff_ann, nsg$diff_nw_t, nsg$corr))
  cat(sprintf("  strategy: t(alpha)=%.3f PORT_t=%.3f | control: t(alpha)=%.3f PORT_t=%.3f\n",
              nsg$strategy[["t_alpha"]], nsg$strategy[["port_t"]],
              nsg$control[["t_alpha"]], nsg$control[["port_t"]]))
} else {
  cat(sprintf("  [WARN] no_signal_gate 미시행: %s\n", nsg_note %||% "unknown"))
}

# ──────────────────────────────────────────────────────────
# 10. graduation verdict (HARD 3종)
# ──────────────────────────────────────────────────────────
port_t_hard <- if (is.finite(port_t_nw3) && port_t_nw3 >= 2.95) "PASS" else "FAIL"
oos_hard <- if (!is.finite(oos_retention)) {
  "FAIL"
} else if (oos_retention >= 0.7) {
  "PASS"
} else if (oos_retention >= 0.5) {
  "CONDITIONAL"
} else {
  "FAIL"
}
calmar_hard <- if (is.finite(calmar) && calmar >= 0.64) "PASS" else "FAIL"
overall <- if (port_t_hard == "PASS" && oos_hard == "PASS" && calmar_hard == "PASS") "PASS" else "FAIL"

cat("\n[Step 8] Graduation HARD 3종\n")
cat(sprintf("  PORT_t>=2.95:      %s (%.4f)\n", port_t_hard, port_t_nw3))
cat(sprintf("  oos_retention>=0.7: %s (%s)\n", oos_hard, oos_str))
cat(sprintf("  calmar>=0.64:      %s (%.4f)\n", calmar_hard, calmar))
cat(sprintf("  OVERALL:           %s\n", overall))

# ──────────────────────────────────────────────────────────
# 11. Charts (equity curve + annual returns + OOS zoom)
# ──────────────────────────────────────────────────────────
cat("\n[Step 9] Charts\n")
tryCatch({
  cum_nav <- DAILY_NAV_DT[-1, .(Date, cum = cumprod(1 + Strategy_Ret))]
  bmc <- bm_daily[Date %in% cum_nav$Date]; bmc[, cum := cumprod(1 + BM_Ret)]
  cdt <- rbind(
    data.table(Date = cum_nav$Date, NAV = cum_nav$cum, Series = "q90_pinball"),
    data.table(Date = bmc$Date, NAV = bmc$cum, Series = "KOSPI200")
  )
  p_eq <- ggplot(cdt, aes(Date, NAV, color = Series)) + geom_line(linewidth = 0.9) +
    scale_color_manual(values = c(q90_pinball = "#FF1493", KOSPI200 = "gray40")) +
    scale_y_log10() +
    labs(title = sprintf("WT-D20260813_001 q90 pinball | SR=%.3f CAGR=%.1f%% MDD=%.1f%% PORT_t=%.2f",
                         ann_sr, ann_cagr * 100, ann_mdd * 100, port_t_nw3),
         x = "Date", y = "Cumulative NAV (log)") + theme_minimal(base_size = 12)
  ggsave(file.path(OUT_DIR, "equity_curve.png"), p_eq, width = 14, height = 7, dpi = 110)

  DAILY_NAV_DT[, Year := year(Date)]
  ar <- DAILY_NAV_DT[-1][, .(ar = prod(1 + Strategy_Ret) - 1), by = Year]
  p_ar <- ggplot(ar, aes(Year, ar, fill = ar >= 0)) + geom_col(width = 0.7) +
    geom_hline(yintercept = 0) +
    scale_fill_manual(values = c("TRUE" = "#2196F3", "FALSE" = "#F44336")) +
    scale_y_continuous(labels = percent_format(accuracy = 1)) +
    labs(title = "q90 pinball — Annual Returns", x = "Year", y = "Annual Return") +
    theme_minimal(base_size = 12) + theme(legend.position = "none")
  ggsave(file.path(OUT_DIR, "annual_returns.png"), p_ar, width = 12, height = 6, dpi = 110)

  # OOS zoom: recent 5Y
  zoom_start <- max(DAILY_NAV_DT$Date) - 365 * 5
  cz <- cdt[Date >= zoom_start]
  cz[, cum_reb := NAV / NAV[1], by = Series]
  p_z <- ggplot(cz, aes(Date, cum_reb, color = Series)) + geom_line(linewidth = 0.9) +
    scale_color_manual(values = c(q90_pinball = "#FF1493", KOSPI200 = "gray40")) +
    labs(title = "q90 pinball — recent 5Y (rebased)", x = "Date", y = "Rebased NAV") +
    theme_minimal(base_size = 12)
  ggsave(file.path(OUT_DIR, "oos_zoom_chart.png"), p_z, width = 12, height = 6, dpi = 110)
  cat("  equity_curve.png / annual_returns.png / oos_zoom_chart.png saved\n")
}, error = function(e) cat(sprintf("  [WARN] charts: %s\n", conditionMessage(e))))

# ──────────────────────────────────────────────────────────
# 12. Save bt_result (RDS + CSV)
# ──────────────────────────────────────────────────────────
cat("\n[Step 10] Save bt_result\n")
saveRDS(bt_result, file.path(STAGE_DIR, "bt_result.rds"))
fwrite(mt, file.path(OUT_DIR, "metrics.csv"))
fwrite(bc, file.path(OUT_DIR, "benchmark_compare.csv"))
fwrite(prtb, file.path(OUT_DIR, "period_returns.csv"))
fwrite(DAILY_NAV_DT[, .(Date, NAV, Strategy_Ret)], file.path(OUT_DIR, "daily_nav.csv"))
cat(sprintf("  bt_result.rds + 4 CSV saved to %s\n", STAGE_DIR))

# annualized turnover (weight-diff, one-way)
ann_to <- if (nrow(PORTFOLIO_LOG) > 1) {
  mean(PORTFOLIO_LOG$Turnover_oneway[-1], na.rm = TRUE) * 12
} else NA_real_
cat(sprintf("  Annualized turnover (one-way): %.4f\n", ann_to))

# ──────────────────────────────────────────────────────────
# 13. forge_package.json
# ──────────────────────────────────────────────────────────
cat("\n[Step 11] forge_package.json\n")
hash_end <- list(
  alpha = tools::md5sum(ALPHA_PKG_PATH),
  risk  = tools::md5sum(RISK_PKG_PATH),
  opt   = tools::md5sum(OPT_PKG_PATH)
)
integrity_pass <- (hash_start$alpha == hash_end$alpha) &&
                  (hash_start$risk  == hash_end$risk)  &&
                  (hash_start$opt   == hash_end$opt)
if (!integrity_pass) stop("[AUDIT FAIL] 3-package integrity violated during backtest!")
cat("  [AUDIT PASS] 3-package integrity confirmed\n")

forge_package <- list(
  task_id = WT_ID,
  forge_authoritative = TRUE,
  metric_type = "backtested",
  measurement_basis_primary = "forge_realized_share_based",
  portfolio_alpha_t_nw_lag3 = round(port_t_nw3, 4),
  portfolio_alpha_t_beta_adj = round(alpha_t_beta_adj, 4),
  beta_controlled_alpha_ann = round(alpha_ann_beta_adj, 4),
  beta_to_bm = round(beta_to_bm, 4),
  oos_retention = if (is.finite(oos_retention)) round(oos_retention, 4) else NA,
  oos_retention_splits = if (length(oos_splits) > 1) round(oos_splits, 3) else NA,
  calmar = round(calmar, 4),
  ann_sr = round(ann_sr, 4),
  ann_cagr = round(ann_cagr, 4),
  ann_mdd = round(ann_mdd, 4),
  annualized_turnover_oneway = round(ann_to, 4),
  n_months = nrow(prtb),
  sr_realized_share_based = round(ann_sr, 4),
  graduation_verdict = list(
    port_t_hard = port_t_hard,
    oos_retention_hard = oos_hard,
    calmar_hard = calmar_hard,
    overall = overall,
    thresholds = list(port_t = 2.95, oos_retention = 0.7, calmar = 0.64)
  ),
  no_signal_gate_result = nsg_result,
  no_signal_gate_detail = if (!is.null(nsg_full)) list(
    diff_ann = round(nsg_full$diff_ann, 4),
    diff_nw_t = round(nsg_full$diff_nw_t, 4),
    corr = round(nsg_full$corr, 4),
    strategy_t_alpha = round(nsg_full$strategy[["t_alpha"]], 4),
    strategy_port_t = round(nsg_full$strategy[["port_t"]], 4),
    control_t_alpha = round(nsg_full$control[["t_alpha"]], 4),
    control_port_t = round(nsg_full$control[["port_t"]], 4)
  ) else NULL,
  no_signal_gate_note = if (nsg_result == "미시행") (nsg_note %||% "unknown") else NA,
  cost_model_version = "v2.4_kr_retail_15bps",
  schedule = list(
    source = "stage_artifacts/WT-D20260813_001/weights.csv (as-is)",
    n_holding_months = length(holding_months),
    period = sprintf("%s ~ %s", min(entry_dates), max(entry_dates)),
    fidelity = "weights.csv holding_month schedule consumed as-is; no alpha_scores re-selection"
  ),
  hash_audit = list(
    alpha_hash_start = as.character(hash_start$alpha),
    risk_hash_start  = as.character(hash_start$risk),
    opt_hash_start   = as.character(hash_start$opt),
    alpha_hash_end = as.character(hash_end$alpha),
    risk_hash_end  = as.character(hash_end$risk),
    opt_hash_end   = as.character(hash_end$opt),
    integrity_pass = integrity_pass
  ),
  upstream_verdict = "NOT_SUPPORTED (alpha research_verdict; paired NW3 t=+0.828)",
  scope_note = paste0("forge re-measurement of q90 pinball weights.csv schedule. ",
                      "graduation HARD 3종 통과 주장 아님 — 실측 정직 보고. ",
                      "PORT_t 는 alpha+(beta-1)*E[bm] 를 섞으므로 알파 판정은 beta-controlled t(alpha) 로."),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00"),
  bt_result_path = file.path("stage_artifacts", WT_ID, "bt_result.rds")
)

write_json(forge_package, file.path(WT_DIR, "forge_package.json"),
           auto_unbox = TRUE, pretty = TRUE, na = "null", digits = 6)
cat(sprintf("  forge_package.json saved: %s\n", file.path(WT_DIR, "forge_package.json")))

# ──────────────────────────────────────────────────────────
# 14. status.json
# ──────────────────────────────────────────────────────────
status <- list(
  task_id = WT_ID,
  current_phase = "FORGE_DONE",
  updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00"),
  blocker = NA,
  verdict = sprintf("forge %s | PORT_t=%.3f oos=%s calmar=%.3f",
                    overall, port_t_nw3, oos_str, calmar),
  note = sprintf(paste0("q90 pinball forge re-measurement. ann_SR=%.3f CAGR=%.1f%% MDD=%.1f%%. ",
                        "graduation HARD: PORT_t %s / oos %s / calmar %s -> %s. no_signal_gate=%s"),
                 ann_sr, ann_cagr * 100, ann_mdd * 100,
                 port_t_hard, oos_hard, calmar_hard, overall, nsg_result)
)
write_json(status, file.path(WT_DIR, "status.json"),
           auto_unbox = TRUE, pretty = TRUE, na = "null")
cat("  status.json -> FORGE_DONE\n")

# ──────────────────────────────────────────────────────────
# 15. MODEQ_DONE line
# ──────────────────────────────────────────────────────────
cat("\n=== FORGE COMPLETE — WT-D20260813_001 ===\n")
cat(sprintf("Completed: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat(sprintf("MODEQ_DONE %s qepm_dossier %s port_t=%.4f oos=%s calmar=%.4f\n",
            WT_ID, overall, port_t_nw3,
            if (is.finite(oos_retention)) sprintf("%.4f", oos_retention) else "NA",
            calmar))
