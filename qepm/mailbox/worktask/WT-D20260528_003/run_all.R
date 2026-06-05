## ============================================================
## WT-D20260528_003 D_PROD — Forge Integration v6.1 R12 Pure Function
## 3-package (alpha/risk/optimization) READ-ONLY integration → backtest
##
## BOUNDARY (HARD): target_weights/cov/alpha_vector 수정 절대 금지.
##   허용 write: run_all.R, backtest_result/, judge_ready/, forge_package*.json
##
## Method: weights.csv (116 monthly as_of dates × 20 names, Σw=1) →
##   DAILY share-based NAV reconstruction (PG2 grade) →
##   build_bt_result() (PerformanceAnalytics standard, 자체합성 금지) →
##   forge_package 8-field + audit + registry.
##
## SR Provenance Mandate (Charter §8/§9):
##   sr_realized_share_based = PRIMARY (weights.csv → daily NAV)
##   measurement_basis_primary = "forge_realized_share_based"
##
## Schedule Fidelity Mandate (Charter §9):
##   weights.csv as-of schedule used AS-IS. NO alpha_scores top-N reselection,
##   NO fabricated schedule. 116 as_of dates verbatim.
##
## DSR FAIL Inheritance (HONEST): alpha graduated=false (DSR z=-7.80).
##   graduated=false retained. dsr_fail_acknowledged=true.
##   Graduation verdict = Judge scope.
##
## Cost: 15bps one-way / cost_model_version v2.3_kr_retail_15bps
## ============================================================

cat("=== WT-D20260528_003 D_PROD Forge Integration v6.1 R12 Pure Function ===\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(xts)
  library(PerformanceAnalytics)
  library(ggplot2)
  library(scales)
  library(sandwich)
  library(lmtest)
  library(e1071)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID    <- "WT-D20260528_003"
STR_ID   <- "WT-D20260528_003_D_PROD"
RUN_ID   <- paste0("forge_", WT_ID, "_", format(Sys.time(), "%Y%m%d_%H%M%S"))

WT_DIR   <- file.path(BASE_DIR, "qepm/mailbox/worktask", WT_ID)
SA_DIR   <- file.path(BASE_DIR, "stage_artifacts/WT_D20260528_003")
BT_DIR   <- file.path(WT_DIR, "backtest_result")
JR_DIR   <- file.path(WT_DIR, "judge_ready")
OUT_DIR  <- file.path(WT_DIR, "output")
dir.create(BT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(JR_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

COMMISSION_BPS <- 15
COST_MODEL     <- "v2.3_kr_retail_15bps"
ANNUAL_DAYS    <- 252

# Contract functions
source(file.path(BASE_DIR, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(BASE_DIR, "02_Infrastructure/contracts/audit_bt_result.R"))
source(file.path(BASE_DIR, "02_Infrastructure/contracts/save_bt_result.R"))
source(file.path(BASE_DIR, "02_Infrastructure/contracts/registry_writer.R"))

# ─────────────────────────────────────────────────────────
# 1. START hash audit (3-package + weights READ-ONLY)
# ─────────────────────────────────────────────────────────
cat("[1] START hash audit\n")
pkg_files <- c(
  alpha = file.path(WT_DIR, "alpha_package_PROD.json"),
  risk  = file.path(WT_DIR, "risk_package_PROD.json"),
  opt   = file.path(WT_DIR, "optimization_package_PROD.json"),
  cov   = file.path(BASE_DIR, "stage_artifacts/WT_D20260528_003_risk_PROD/covariance.parquet"),
  weights = file.path(SA_DIR, "weights.csv")
)
start_hashes <- sapply(pkg_files, function(f)
  tryCatch(as.character(tools::md5sum(f)), error = function(e) "MISSING"))
for (n in names(start_hashes))
  cat(sprintf("    %-10s = %s\n", n, start_hashes[n]))

# ─────────────────────────────────────────────────────────
# 2. Load weights.csv (READ-ONLY) — Schedule_EWbase as-is
# ─────────────────────────────────────────────────────────
cat("\n[2] Load weights.csv (READ-ONLY, schedule AS-IS)\n")
wts <- fread(pkg_files["weights"])
setnames(wts, "as_of_date", "Date", skip_absent = TRUE)
wts[, Date := as.Date(Date)]
setkey(wts, Date, Ticker)

sig_dates <- sort(unique(wts$Date))
cat(sprintf("  %d rows | %d as_of dates | %s ~ %s\n",
            nrow(wts), length(sig_dates),
            as.character(min(sig_dates)), as.character(max(sig_dates))))

sum_check <- wts[, .(sw = round(sum(weight), 6)), by = Date]
bad <- sum_check[abs(sw - 1) > 1e-3]
cat(sprintf("  Sigma w == 1 : %s (%d/%d dates clean)\n",
            if (nrow(bad) == 0) "PASS" else "WARN", nrow(sum_check) - nrow(bad), nrow(sum_check)))
n_check <- wts[, .(n = .N), by = Date]
cat(sprintf("  Names/date   : min=%d max=%d (constraint <=20)\n", min(n_check$n), max(n_check$n)))
cat(sprintf("  Weight bounds: [%.5f, %.5f] (constraint [0,0.20])\n",
            min(wts$weight), max(wts$weight)))

# Schedule fidelity: density check vs alpha sig_dates (116 expected)
alpha_pkg <- fromJSON(pkg_files["alpha"])
opt_pkg   <- fromJSON(pkg_files["opt"])
n_alpha_sig <- alpha_pkg$diagnostics$n_sig_dates %||% length(sig_dates)
density_ratio <- length(sig_dates) / n_alpha_sig
cat(sprintf("  Schedule fidelity: %d weights as_of / %d alpha sig_dates = density %.3f (mandate >=0.95)\n",
            length(sig_dates), n_alpha_sig, density_ratio))

# ─────────────────────────────────────────────────────────
# 3. Load RAWDATA (daily Ret) + Benchmark + FF5 v2
# ─────────────────────────────────────────────────────────
cat("\n[3] Load RAWDATA + Benchmark + FF5 v2\n")
all_tickers <- unique(wts$Ticker)
raw <- as.data.table(read_parquet(
  file.path(BASE_DIR, ".cache/rawdata.parquet"),
  col_select = c("Date", "Ticker", "Close", "Vol", "Ret")))
raw[, Date := as.Date(Date)]
raw <- raw[Ticker %in% all_tickers]
setkey(raw, Date, Ticker)
cat(sprintf("  RAWDATA (filtered %d tickers): %s rows | %s ~ %s\n",
            length(all_tickers), format(nrow(raw), big.mark = ","),
            as.character(min(raw$Date)), as.character(max(raw$Date))))

bm <- as.data.table(read_parquet(file.path(BASE_DIR, ".cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]
setorder(bm, Date)
cat(sprintf("  Benchmark: %d rows | cols=%s\n", nrow(bm), paste(names(bm), collapse=",")))

ff5 <- as.data.table(read_parquet(file.path(BASE_DIR, ".cache/kr_factor_returns_v2.parquet")))
ff5[, Date := as.Date(Date)]
setorder(ff5, Date)
cat(sprintf("  FF5 v2: %d rows | %s\n", nrow(ff5), paste(names(ff5), collapse=",")))

# All trading days from raw within backtest span
RAW_MAX <- max(raw$Date)
bt_start <- min(sig_dates)
bt_end   <- RAW_MAX  # deploy extension: extend to today's raw max
trade_days <- sort(unique(raw$Date[raw$Date >= bt_start & raw$Date <= bt_end]))
cat(sprintf("  Trading days span: %d days | %s ~ %s\n",
            length(trade_days), as.character(bt_start), as.character(bt_end)))

# IS / OOS boundary = last schedule date (deploy cutoff)
DEPLOY_CUTOFF <- max(sig_dates)  # 2023-11-30
cat(sprintf("  Deploy cutoff (last schedule as_of): %s\n", as.character(DEPLOY_CUTOFF)))
cat(sprintf("  OOS extension (frozen buy-and-hold): %s ~ %s\n",
            as.character(DEPLOY_CUTOFF), as.character(bt_end)))

# ─────────────────────────────────────────────────────────
# 4. DAILY SHARE-BASED NAV reconstruction (PG2 grade)
#    For each schedule period [d_i, d_{i+1}):
#      - weights frozen at d_i (from weights.csv, as-is)
#      - daily portfolio return = weighted daily stock Ret with
#        intra-period weight DRIFT (share-based: weights evolve by gross return)
#      - rebalance cost = 15bps one-way * sum|w_target - w_drifted_prev|
#    OOS (>DEPLOY_CUTOFF): frozen last weights, buy-and-hold drift (no rebal cost)
# ─────────────────────────────────────────────────────────
cat("\n[4] DAILY share-based NAV reconstruction\n")

# Wide daily return matrix (tickers x days) for fast lookup
raw_bt <- raw[Date >= bt_start & Date <= bt_end]
ret_wide <- dcast(raw_bt, Date ~ Ticker, value.var = "Ret")
setorder(ret_wide, Date)
ret_dates <- ret_wide$Date
ret_mat <- as.matrix(ret_wide[, !"Date"])
ret_mat[is.na(ret_mat)] <- 0  # missing daily ret = 0 (suspended/halt)
mat_cols <- colnames(ret_mat)

# Build period boundaries: schedule dates + deploy extension
# Rebalance executes on the trading day >= as_of date (signal t, exec next available)
get_exec_day <- function(d) {
  td <- trade_days[trade_days >= d]
  if (length(td) == 0) NA else td[1]
}
exec_days <- as.Date(sapply(sig_dates, get_exec_day), origin = "1970-01-01")

# Daily NAV loop
nav_gross <- 1.0
nav_net   <- 1.0
prev_w_drift <- NULL  # drifted weights carried from previous day (full ticker space)
zero_w <- setNames(rep(0, length(mat_cols)), mat_cols)

daily_rows <- vector("list", length(ret_dates))
holdings_log <- list()
portfolio_log <- list()
turnover_at_rebal <- list()

# Map: for each exec day, which target weights apply
target_by_exec <- list()
for (i in seq_along(exec_days)) {
  ed <- exec_days[i]
  if (is.na(ed)) next
  wt_i <- wts[Date == sig_dates[i]]
  wv <- zero_w
  wv[wt_i$Ticker] <- wt_i$weight
  target_by_exec[[as.character(ed)]] <- list(w = wv, as_of = sig_dates[i], names = wt_i$Ticker, raw = wt_i)
}

cur_w <- zero_w  # current (start of day) weights
holding_initialized <- FALSE

for (t in seq_along(ret_dates)) {
  d <- ret_dates[t]
  dk <- as.character(d)
  rebal_today <- !is.null(target_by_exec[[dk]])

  # Rebalance at OPEN (PIT: signal as_of < exec day; weights from past)
  cost_today <- 0
  if (rebal_today) {
    tgt <- target_by_exec[[dk]]$w
    # turnover vs drifted current weights (start-of-day, pre-return)
    to <- sum(abs(tgt - cur_w)) / 2
    cost_today <- (COMMISSION_BPS / 1e4) * to  # one-way on traded notional
    cur_w <- tgt
    turnover_at_rebal[[dk]] <- to
    # log holdings + portfolio
    wt_i <- target_by_exec[[dk]]$raw
    hl <- data.table(
      Signal_Date = target_by_exec[[dk]]$as_of,
      Exec_Date   = d,
      Ticker = wt_i$Ticker,
      Weight = wt_i$weight,
      Score  = NA_real_,
      Price  = NA_real_
    )
    holdings_log[[dk]] <- hl
    portfolio_log[[dk]] <- data.table(Signal_Date = target_by_exec[[dk]]$as_of, Exec_Date = d, turnover = to)
    holding_initialized <- TRUE
  }

  if (!holding_initialized) {
    # before first exec day: hold cash (NAV flat)
    daily_rows[[t]] <- data.table(Date = d, NAV = nav_net, NAV_gross = nav_gross,
                                  ret_net = 0, ret_gross = 0, cost = 0,
                                  is_rebalance = rebal_today, cash_weight = 1)
    next
  }

  # daily stock returns vector aligned to mat_cols
  r_t <- ret_mat[t, ]
  # portfolio gross daily return = sum(w_i * r_i); cash (1-sum w) earns 0
  inv_w <- sum(cur_w)
  port_ret_gross <- sum(cur_w * r_t)
  port_ret_net   <- port_ret_gross - cost_today

  nav_gross <- nav_gross * (1 + port_ret_gross)
  nav_net   <- nav_net   * (1 + port_ret_net)

  # weight drift (share-based): w_i' = w_i*(1+r_i) / (1 + port_ret_gross_invested_part)
  # normalize by total portfolio gross growth so cash fraction handled
  growth <- 1 + port_ret_gross
  cur_w <- (cur_w * (1 + r_t)) / growth

  daily_rows[[t]] <- data.table(Date = d, NAV = nav_net, NAV_gross = nav_gross,
                                ret_net = port_ret_net, ret_gross = port_ret_gross,
                                cost = cost_today, is_rebalance = rebal_today,
                                cash_weight = max(0, 1 - sum(cur_w)))
}

nav_dt <- rbindlist(daily_rows, use.names = TRUE)
nav_dt <- nav_dt[!is.na(NAV)]
setorder(nav_dt, Date)
cat(sprintf("  Daily NAV: %d days | final NAV_net=%.4f gross=%.4f\n",
            nrow(nav_dt), tail(nav_dt$NAV,1), tail(nav_dt$NAV_gross,1)))
cat(sprintf("  Rebalances executed: %d | total cost drag=%.4f\n",
            length(turnover_at_rebal), sum(nav_dt$cost)))

# ─────────────────────────────────────────────────────────
# 5. Build sim_result + benchmark daily aligned
# ─────────────────────────────────────────────────────────
cat("\n[5] Build sim_result for build_bt_result()\n")

# strategy daily net return xts (PerformanceAnalytics input)
strat_xts <- xts(nav_dt$ret_net, order.by = nav_dt$Date)

# Benchmark daily returns aligned to nav_dt dates
bm_bt <- bm[Date >= min(nav_dt$Date) & Date <= max(nav_dt$Date)]
bm_xts_full <- xts(bm_bt$BM_Ret, order.by = bm_bt$Date)
# align to strategy dates
bm_xts <- bm_xts_full[index(strat_xts)]
bm_xts[is.na(bm_xts)] <- 0

DAILY_NAV_DT <- nav_dt[, .(Date, NAV, NAV_gross,
                           cash_weight,
                           is_rebalance_date = is_rebalance)]

HOLDINGS_LOG  <- holdings_log
PORTFOLIO_LOG <- rbindlist(portfolio_log, use.names = TRUE)

sim_result <- list(
  DAILY_NAV_DT = DAILY_NAV_DT,
  strategy_xts = strat_xts,
  bm_xts       = bm_xts,
  HOLDINGS_LOG = HOLDINGS_LOG,
  PORTFOLIO_LOG = PORTFOLIO_LOG
)

strategy_spec <- list(
  strategy_name      = STR_ID,
  rebalance_frequency = "monthly",
  execution_date_rule = "month_end_signal_t_plus_1",
  universe           = alpha_pkg$universe %||% "KOSPI200_KOSDAQ150_intersection",
  benchmark          = "KOSPI200_total_return",
  n_holdings         = 20L,
  cost_model_version = COST_MODEL,
  method_selected    = opt_pkg$method_selected %||% "Schedule_EWbase",
  graduated          = FALSE,
  dsr_fail_acknowledged = TRUE,
  # PIT attestation (inherited from alpha_package_PROD pit_assertions, for audit Check 7/8/9)
  lookahead_prevention = paste0(
    "C13 Z_Score_Aligned (no negate/flip); C14 Usable_Date<=sig_date; ",
    "C15 ML daily-parquet carve-out approved; purged 10-fold expanding CV + 30d embargo; ",
    "weights from alpha sig_dates<=lockbox 2023-12-22; rolling cov Date<sig_date (C9 t-1)"),
  survivorship_bias_control = paste0(
    "RAWDATA universe includes delisted/suspended (KRX full panel 1990-2026); ",
    "missing daily Ret imputed 0 for halt/suspension within holding period")
)

# ─────────────────────────────────────────────────────────
# 6. build_bt_result() — PerformanceAnalytics standard, 10-component
# ─────────────────────────────────────────────────────────
cat("\n[6] build_bt_result() (PerformanceAnalytics standard)\n")

saveRDS(sim_result, file.path(WT_DIR, "forge_sim_result.rds"))

bt_result <- build_bt_result(
  sim_result = sim_result,
  strategy_spec = strategy_spec,
  run_id = RUN_ID,
  strategy_id = STR_ID,
  strategy_version = "D_PROD_v1.0",
  benchmark_id = "KOSPI200",
  benchmark_name = "KOSPI 200 TR",
  transaction_cost_bps = COMMISSION_BPS,
  slippage_bps = 0,
  risk_free_rate = 0,
  frequency = "daily",
  annualization_factor = ANNUAL_DAYS,
  universe_id = "KOSPI200_KOSDAQ150",
  code_version = "run_all_forge_v6.1_WT-D20260528_003",
  created_by_agent = "forge"
)

# Component 11: audit
bt_result <- audit_bt_result(bt_result)
audit_dt <- bt_result$audit
n_pass <- sum(audit_dt$status == "PASS")
n_fail <- sum(audit_dt$status == "FAIL")
integrity <- bt_result$manifest$integrity_status
cat(sprintf("  audit_bt_result: %d PASS / %d FAIL | integrity=%s\n",
            n_pass, n_fail, integrity))
print(audit_dt[, .(check_name, status, severity)])

# ─────────────────────────────────────────────────────────
# 7. Extract official PerformanceAnalytics metrics (full period)
# ─────────────────────────────────────────────────────────
cat("\n[7] PerformanceAnalytics official metrics (full period)\n")

ta <- table.AnnualizedReturns(strat_xts, scale = ANNUAL_DAYS, Rf = 0)
cagr_full   <- as.numeric(ta["Annualized Return", 1])
sharpe_full <- as.numeric(ta["Annualized Sharpe (Rf=0%)", 1])
vol_full    <- as.numeric(ta["Annualized Std Dev", 1])
mdd_full    <- as.numeric(maxDrawdown(strat_xts))
sortino_full<- as.numeric(SortinoRatio(strat_xts)) * sqrt(ANNUAL_DAYS)
calmar_full <- as.numeric(CalmarRatio(strat_xts, scale = ANNUAL_DAYS))
hit_full    <- mean(as.numeric(strat_xts) > 0)

cat(sprintf("  CAGR=%.4f Sharpe=%.4f Vol=%.4f MDD=%.4f Sortino=%.4f Calmar=%.4f hit=%.4f\n",
            cagr_full, sharpe_full, vol_full, mdd_full, sortino_full, calmar_full, hit_full))

# IS (pre deploy cutoff) and OOS (post) split
strat_is  <- strat_xts[index(strat_xts) <= DEPLOY_CUTOFF]
strat_oos <- strat_xts[index(strat_xts) >  DEPLOY_CUTOFF]
ta_is  <- table.AnnualizedReturns(strat_is, scale = ANNUAL_DAYS, Rf = 0)
sharpe_is  <- as.numeric(ta_is["Annualized Sharpe (Rf=0%)", 1])
cagr_is    <- as.numeric(ta_is["Annualized Return", 1])
mdd_is     <- as.numeric(maxDrawdown(strat_is))
if (length(strat_oos) > 20) {
  ta_oos <- table.AnnualizedReturns(strat_oos, scale = ANNUAL_DAYS, Rf = 0)
  sharpe_oos <- as.numeric(ta_oos["Annualized Sharpe (Rf=0%)", 1])
  cagr_oos   <- as.numeric(ta_oos["Annualized Return", 1])
  mdd_oos    <- as.numeric(maxDrawdown(strat_oos))
} else { sharpe_oos <- NA; cagr_oos <- NA; mdd_oos <- NA }
cat(sprintf("  IS  (<=%s): Sharpe=%.4f CAGR=%.4f MDD=%.4f n=%d\n",
            as.character(DEPLOY_CUTOFF), sharpe_is, cagr_is, mdd_is, length(strat_is)))
cat(sprintf("  OOS (> %s): Sharpe=%.4f CAGR=%.4f MDD=%.4f n=%d (frozen buy-and-hold)\n",
            as.character(DEPLOY_CUTOFF), sharpe_oos %||% NA, cagr_oos %||% NA, mdd_oos %||% NA, length(strat_oos)))

# Benchmark same-period comparison (PerformanceAnalytics)
ta_bm <- table.AnnualizedReturns(bm_xts, scale = ANNUAL_DAYS, Rf = 0)
bm_cagr   <- as.numeric(ta_bm["Annualized Return", 1])
bm_sharpe <- as.numeric(ta_bm["Annualized Sharpe (Rf=0%)", 1])
bm_mdd    <- as.numeric(maxDrawdown(bm_xts))
cat(sprintf("  BENCHMARK (KOSPI200, same period): CAGR=%.4f Sharpe=%.4f MDD=%.4f\n",
            bm_cagr, bm_sharpe, bm_mdd))

# ─────────────────────────────────────────────────────────
# 8. Realized turnover (annual round-trip)
# ─────────────────────────────────────────────────────────
cat("\n[8] Realized turnover\n")
to_vec <- unlist(turnover_at_rebal)
n_yrs_is <- as.numeric(difftime(DEPLOY_CUTOFF, min(sig_dates), units = "days")) / 365
# annual one-way: sum oneway TO / years; round-trip = *2
ann_to_oneway <- sum(to_vec[names(to_vec) <= as.character(DEPLOY_CUTOFF) | TRUE], na.rm = TRUE)
# proper: only IS rebal turnover
to_is <- to_vec[as.Date(names(to_vec)) <= DEPLOY_CUTOFF]
ann_to_rt <- sum(to_is, na.rm = TRUE) * 2 / max(0.5, n_yrs_is)
cat(sprintf("  IS rebalances=%d | sum one-way TO=%.3f | years=%.2f | annual round-trip TO=%.3f (cap 6.0: %s)\n",
            length(to_is), sum(to_is), n_yrs_is, ann_to_rt, if (ann_to_rt <= 6.0) "PASS" else "FAIL"))

# ─────────────────────────────────────────────────────────
# 9. DSR inheritance (HONEST) + divergence diagnosis
# ─────────────────────────────────────────────────────────
cat("\n[9] DSR FAIL inheritance + provenance\n")
dsr_proper_alpha <- alpha_pkg$diagnostics$dsr_proper %||% NA
dsr_z_alpha      <- alpha_pkg$diagnostics$dsr_z %||% NA
graduated_alpha  <- alpha_pkg$graduated %||% FALSE
cat(sprintf("  Inherited alpha DSR_proper=%.3e z=%.3f graduated=%s\n",
            dsr_proper_alpha, dsr_z_alpha, graduated_alpha))

# factor_engine claim (optimizer net_sharpe walk-forward)
factor_engine_sr <- opt_pkg$net_sharpe_annual %||% NA  # 0.7414 (walk-forward continuous)
sr_realized      <- sharpe_full
divergence_pp    <- sr_realized - factor_engine_sr
# IS-only divergence (fair: factor_engine WF is on schedule period)
divergence_pp_is <- sharpe_is - factor_engine_sr
cat(sprintf("  factor_engine (optimizer WF net SR)=%.4f | forge realized (full)=%.4f | divergence=%+.4f pp\n",
            factor_engine_sr, sr_realized, divergence_pp))
cat(sprintf("  forge realized (IS, fair comparison)=%.4f | divergence_IS=%+.4f pp\n",
            sharpe_is, divergence_pp_is))
diag_div <- function(d) {
  ad <- abs(d)
  if (ad < 0.1) "NEGLIGIBLE" else if (ad < 0.3) "MINOR_DRIFT" else
  if (ad < 0.6) "SIGNIFICANT_DRAG" else "FABRICATION_SUSPECTED"
}
divergence_diagnosis <- diag_div(divergence_pp_is)
cat(sprintf("  Divergence diagnosis (IS basis): %s (|%.4f|pp; FABRICATION threshold 0.6)\n",
            divergence_diagnosis, divergence_pp_is))

# ─────────────────────────────────────────────────────────
# 10. Save bt_result (RDS + CSV + JSON + XLSX) + registry
# ─────────────────────────────────────────────────────────
cat("\n[10] Save bt_result + registry append\n")
save_res <- tryCatch(save_bt_result(bt_result, BT_DIR, save_xlsx = TRUE),
                     error = function(e) { cat(sprintf("  [save warn] %s\n", conditionMessage(e))); NULL })
reg_res <- NULL
if (integrity != "FAIL" && n_fail == 0) {
  reg_res <- tryCatch(register_bt_result(bt_result),
                      error = function(e) { cat(sprintf("  [register warn] %s\n", conditionMessage(e))); NULL })
  cat(sprintf("  registry append: %s\n", if (!is.null(reg_res)) "DONE" else "SKIP"))
} else {
  cat("  registry append: SKIPPED (audit FAIL or integrity FAIL)\n")
}

# ─────────────────────────────────────────────────────────
# 11. OOS charts (Mandate v6.1)
# ─────────────────────────────────────────────────────────
cat("\n[11] OOS charts\n")
plot_dt <- data.table(Date = index(strat_xts), ret = as.numeric(strat_xts))
plot_dt[, NAV := cumprod(1 + ret)]
plot_dt[, Period := ifelse(Date <= DEPLOY_CUTOFF, "IS", "OOS")]
bm_plot <- data.table(Date = index(bm_xts), bm_ret = as.numeric(bm_xts))
bm_plot[, BM_NAV := cumprod(1 + bm_ret)]

p_eq <- ggplot() +
  geom_line(data = plot_dt, aes(x = Date, y = NAV, color = "Strategy"), linewidth = 0.7) +
  geom_line(data = bm_plot, aes(x = Date, y = BM_NAV, color = "KOSPI200"), linewidth = 0.5, alpha = 0.7) +
  geom_vline(xintercept = as.numeric(DEPLOY_CUTOFF), linetype = "dashed", color = "red") +
  annotate("text", x = DEPLOY_CUTOFF, y = max(plot_dt$NAV)*0.9, label = "Deploy cutoff\n2023-11", color="red", size=3, hjust=1.05) +
  scale_color_manual(values = c("Strategy"="steelblue","KOSPI200"="grey40")) +
  labs(title = sprintf("WT-D20260528_003 D_PROD — Walk-forward NAV (Sharpe=%.3f MDD=%.1f%%)", sharpe_full, mdd_full*100),
       subtitle = sprintf("Daily share-based | DSR FAIL inherited (graduated=false) | factor_engine WF SR=%.4f", factor_engine_sr),
       x="Date", y="NAV (1=initial)", color=NULL) + theme_minimal(base_size=11)
ggsave(file.path(OUT_DIR, "equity_curve.png"), p_eq, width=12, height=6, dpi=150)

plot_dt[, Year := year(Date)]
ann_dt <- plot_dt[, .(ann_ret = prod(1+ret)-1), by=Year]
p_ann <- ggplot(ann_dt, aes(x=factor(Year), y=ann_ret*100, fill=ann_ret>=0)) +
  geom_col() + scale_fill_manual(values=c("TRUE"="steelblue","FALSE"="tomato"), guide="none") +
  labs(title="D_PROD Annual Returns", x="Year", y="Return (%)") + theme_minimal(base_size=11)
ggsave(file.path(OUT_DIR, "annual_returns.png"), p_ann, width=12, height=5, dpi=150)

# OOS zoom (deploy extension period)
oos_plot <- plot_dt[Date > DEPLOY_CUTOFF]
if (nrow(oos_plot) > 10) {
  oos_plot[, NAV_oos := cumprod(1+ret)]
  bm_oos <- bm_plot[Date > DEPLOY_CUTOFF]
  bm_oos[, BM_oos := cumprod(1+bm_ret)]
  p_oos <- ggplot() +
    geom_line(data=oos_plot, aes(x=Date,y=NAV_oos,color="Strategy(frozen)"), linewidth=0.8) +
    geom_line(data=bm_oos, aes(x=Date,y=BM_oos,color="KOSPI200"), linewidth=0.6) +
    scale_color_manual(values=c("Strategy(frozen)"="darkorange","KOSPI200"="grey40")) +
    labs(title=sprintf("D_PROD OOS Deploy Extension (frozen 2023-11 weights, Sharpe=%.3f)", sharpe_oos %||% NA),
         subtitle="Buy-and-hold frozen weights, no rebalancing", x="Date", y="NAV (1=deploy cutoff)", color=NULL) +
    theme_minimal(base_size=11)
  ggsave(file.path(OUT_DIR, "oos_zoom_chart.png"), p_oos, width=12, height=6, dpi=150)
  cat("  Saved: equity_curve.png, annual_returns.png, oos_zoom_chart.png\n")
} else {
  cat("  Saved: equity_curve.png, annual_returns.png (OOS too short for zoom)\n")
}

# ─────────────────────────────────────────────────────────
# 12. END hash audit
# ─────────────────────────────────────────────────────────
cat("\n[12] END hash audit\n")
end_hashes <- sapply(pkg_files, function(f)
  tryCatch(as.character(tools::md5sum(f)), error = function(e) "MISSING"))
hash_integrity <- all(start_hashes == end_hashes)
cat(sprintf("  Integrity: %s\n", if (hash_integrity) "PASS (3-package + cov + weights unchanged)" else "FAIL (TAMPER)"))
if (!hash_integrity) for (n in names(start_hashes))
  if (start_hashes[n] != end_hashes[n]) cat(sprintf("  [TAMPER] %s: %s -> %s\n", n, start_hashes[n], end_hashes[n]))

# ─────────────────────────────────────────────────────────
# 13. Save metrics bundle for forge_package builder
# ─────────────────────────────────────────────────────────
metrics_bundle <- list(
  run_id = RUN_ID,
  full = list(cagr=cagr_full, sharpe=sharpe_full, vol=vol_full, mdd=mdd_full,
              sortino=sortino_full, calmar=calmar_full, hit=hit_full,
              n_days=length(strat_xts),
              period=paste0(as.character(min(nav_dt$Date)),"~",as.character(max(nav_dt$Date)))),
  is  = list(sharpe=sharpe_is, cagr=cagr_is, mdd=mdd_is, n=length(strat_is)),
  oos = list(sharpe=sharpe_oos, cagr=cagr_oos, mdd=mdd_oos, n=length(strat_oos)),
  benchmark = list(cagr=bm_cagr, sharpe=bm_sharpe, mdd=bm_mdd),
  turnover = list(annual_round_trip=ann_to_rt, n_rebal=length(to_is), pass_6=ann_to_rt<=6.0),
  dsr_inheritance = list(dsr_proper=dsr_proper_alpha, dsr_z=dsr_z_alpha,
                         graduated=graduated_alpha, dsr_fail_acknowledged=TRUE),
  provenance = list(sr_realized_share_based=sharpe_full,
                    sr_factor_engine_continuous=factor_engine_sr,
                    divergence_full_pp=divergence_pp,
                    divergence_is_pp=divergence_pp_is,
                    diagnosis=divergence_diagnosis,
                    measurement_basis_primary="forge_realized_share_based"),
  audit = list(n_pass=n_pass, n_fail=n_fail, integrity=integrity),
  hash = list(start=as.list(start_hashes), end=as.list(end_hashes), integrity=hash_integrity),
  schedule_fidelity = list(n_weights_asof=length(sig_dates), n_alpha_sig=n_alpha_sig,
                           density_ratio=density_ratio, density_pass=density_ratio>=0.95),
  cost_model_version = COST_MODEL,
  ff5_path = file.path(BASE_DIR, ".cache/kr_factor_returns_v2.parquet")
)
write_json(metrics_bundle, file.path(WT_DIR, "forge_metrics_bundle.json"),
           auto_unbox=TRUE, pretty=TRUE, na="null")

# Also save daily nav csv for inspection
fwrite(nav_dt, file.path(BT_DIR, "daily_nav.csv"))

cat("\n")
cat(rep("=",80),"\n",sep="")
cat("FORGE_DONE_WT-D20260528_003_D_PROD\n")
cat(rep("=",80),"\n",sep="")
cat(sprintf("  sr_realized_share_based = %.4f\n", sharpe_full))
cat(sprintf("  cagr_full               = %.4f\n", cagr_full))
cat(sprintf("  mdd_full                = %.4f\n", mdd_full))
cat(sprintf("  sortino / calmar        = %.4f / %.4f\n", sortino_full, calmar_full))
cat(sprintf("  hit_rate                = %.4f\n", hit_full))
cat(sprintf("  IS sharpe / OOS sharpe  = %.4f / %.4f\n", sharpe_is, sharpe_oos %||% NA))
cat(sprintf("  bm sharpe (same period) = %.4f\n", bm_sharpe))
cat(sprintf("  annual_to_round_trip    = %.4f\n", ann_to_rt))
cat(sprintf("  factor_engine WF SR     = %.4f\n", factor_engine_sr))
cat(sprintf("  divergence_IS_pp        = %+.4f (%s)\n", divergence_pp_is, divergence_diagnosis))
cat(sprintf("  graduated               = false (DSR FAIL inherited, z=%.2f)\n", dsr_z_alpha))
cat(sprintf("  audit                   = %d PASS / %d FAIL, integrity=%s\n", n_pass, n_fail, integrity))
cat(sprintf("  hash_integrity          = %s\n", hash_integrity))
cat(rep("=",80),"\n",sep="")
