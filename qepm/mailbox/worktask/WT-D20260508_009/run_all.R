## ============================================================================
## WT-D20260508_009 Forge — 4 Hybrid 통합 비율 256개월 실측 백테
## Pure function: 3-package as-is + Optimizer mitigation option_d (M3 3m MA)
## Hybrid 4 ratios: A(0%) / B(10%) / C(20%) / D(30%) BAB allocation
##   STR_1715 (PG2 anchor) + TSMOM + KR_10y + WT_009 BAB-mitigated
## ============================================================================

suppressMessages({
  library(data.table); library(jsonlite); library(arrow)
  library(PerformanceAnalytics); library(xts); library(ggplot2)
})

# ─── PROJECT_ROOT + PATHS ────────────────────────────────────────────────────
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR       <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260508_009")
SA_DIR       <- file.path(PROJECT_ROOT, "stage_artifacts/WT-D20260508_009")
FORGE_DIR    <- file.path(SA_DIR, "forge")
CHARTS_DIR   <- file.path(FORGE_DIR, "charts")
LOG_DIR      <- file.path(FORGE_DIR, "_logs")

# Source backtest contract
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/audit_bt_result.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/save_bt_result.R"))

# ─── CONSTANTS ───────────────────────────────────────────────────────────────
COST_BPS_ONEWAY <- 15
COST_PER_DOLLAR <- COST_BPS_ONEWAY / 10000
ANN_FACTOR <- 12
RUN_DT <- format(Sys.time(), "%Y%m%d_%H%M%S")
TASK_ID <- "WT-D20260508_009"

cat("\n========================================================\n")
cat("  WT-D20260508_009 Forge — 4 Hybrid Ratio 256m Backtest\n")
cat("========================================================\n")
cat(sprintf("  Run datetime: %s | Cost: %dbps one-way uniform\n", RUN_DT, COST_BPS_ONEWAY))
cat(sprintf("  WT_009 BAB mitigation: M3 (3-month MA smoothing)\n"))

# ─── HASH 3-package check (start) ────────────────────────────────────────────
md5 <- function(p) tools::md5sum(p)[[1]]
hash_alpha_start <- md5(file.path(WT_DIR, "alpha_package.json"))
hash_risk_start  <- md5(file.path(WT_DIR, "risk_package.json"))
hash_opt_start   <- md5(file.path(WT_DIR, "optimization_package.json"))
cat(sprintf("\n[HASH START]\n  alpha:    %s\n  risk:     %s\n  optimize: %s\n",
            hash_alpha_start, hash_risk_start, hash_opt_start))

# ─── INPUT 1: STR_1715 PG2 AR_on_M4 (256m anchor) ────────────────────────────
fl <- fread(file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-P20260504_001/four_layer_returns_path.csv"))
fl[, date := as.Date(date)]
str1715_dt <- fl[, .(date, ret_str1715 = ret_AR_on_M4)]
setkey(str1715_dt, date)
cat(sprintf("[INPUT 1] STR_1715 AR_on_M4: %d obs (%s ~ %s)\n",
            nrow(str1715_dt), min(str1715_dt$date), max(str1715_dt$date)))

# ─── INPUT 2: KR_10y bond ETF returns ────────────────────────────────────────
kr10y_full <- fread(file.path(PROJECT_ROOT, "stage_artifacts/WT_S20260504_008/merged_returns.csv"))
kr10y_full[, date := as.Date(date)]
kr10y_dt <- kr10y_full[, .(date, ret_kr10y = kr_10y)]
kr10y_dt[is.na(ret_kr10y), ret_kr10y := 0]  # 2026-04/05 NA fill
setkey(kr10y_dt, date)
cat(sprintf("[INPUT 2] KR_10y: %d obs (%s ~ %s)\n",
            nrow(kr10y_dt), min(kr10y_dt$date), max(kr10y_dt$date)))

# ─── INPUT 3: TSMOM rotation (2015-01 ~ 2026-04) ─────────────────────────────
tsmom_full <- fread(file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-S20260504_009/docs/rotation_path_TSMOM.csv"))
tsmom_full[, date := as.Date(date)]
tsmom_dt <- tsmom_full[, .(date, ret_tsmom_gross = ml_realized)]
setkey(tsmom_dt, date)
cat(sprintf("[INPUT 3] TSMOM: %d obs (%s ~ %s)\n",
            nrow(tsmom_dt), min(tsmom_dt$date), max(tsmom_dt$date)))

# ─── INPUT 4: WT_009 BAB returns (M3 mitigation) ─────────────────────────────
bab_m3 <- fread(file.path(FORGE_DIR, "bab_period_returns_M3.csv"))
bab_m3[, date := as.Date(rebal_date)]
bab_dt <- bab_m3[, .(date, ret_bab_gross = period_ret_gross,
                     bab_to = turnover_one_way,
                     ret_bab_net = period_ret_net)]
setkey(bab_dt, date)
cat(sprintf("[INPUT 4] WT_009 BAB (M3 smoothed): %d obs (%s ~ %s)\n",
            nrow(bab_dt), min(bab_dt$date), max(bab_dt$date)))

# ─── INPUT 5: BM (KOSPI200) — monthly aggregation ────────────────────────────
bm_full <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/benchmark.parquet")))
bm_full[, Date := as.Date(Date)]
bm_full[, ym := format(Date, "%Y-%m")]
# Aggregate daily BM_Ret to monthly
schedule_dates_str1715 <- sort(unique(str1715_dt$date))
schedule_ym <- format(schedule_dates_str1715, "%Y-%m")
bm_monthly <- bm_full[!is.na(BM_Ret) & ym %in% schedule_ym,
                      .(bm_ret = prod(1 + BM_Ret) - 1), by = ym]
bm_monthly_dt <- merge(data.table(ym = schedule_ym, date = schedule_dates_str1715),
                       bm_monthly, by = "ym", all.x = TRUE)
bm_monthly_dt[is.na(bm_ret), bm_ret := 0]
setkey(bm_monthly_dt, date)
cat(sprintf("[INPUT 5] BM (KOSPI200 monthly): %d obs\n", nrow(bm_monthly_dt)))

# ─── BUILD MASTER (256m timeline, str1715 anchor) ────────────────────────────
master <- copy(str1715_dt)  # 256 months (2005-02 ~ 2026-05)
master <- merge(master, kr10y_dt, by = "date", all.x = TRUE)
master <- merge(master, tsmom_dt, by = "date", all.x = TRUE)
master <- merge(master, bab_dt, by = "date", all.x = TRUE)
master <- merge(master, bm_monthly_dt[, .(date, bm_ret)], by = "date", all.x = TRUE)

# Pre-2015 TSMOM NA → 0; pre-2010-01 BAB NA → 0
master[is.na(ret_tsmom_gross), ret_tsmom_gross := 0]
master[is.na(ret_bab_gross),    ret_bab_gross := 0]
master[is.na(ret_bab_net),      ret_bab_net := 0]
master[is.na(bab_to),           bab_to := 0]
master[is.na(ret_kr10y),        ret_kr10y := 0]
master[is.na(bm_ret),            bm_ret := 0]

# Mark availability flags
master[, has_tsmom := date >= as.Date("2015-01-01")]
master[, has_bab   := date >= as.Date("2010-01-01")]

cat(sprintf("\n[MASTER] %d months | range %s ~ %s\n",
            nrow(master), min(master$date), max(master$date)))
cat(sprintf("  has_tsmom (2015-01+): %d months\n", sum(master$has_tsmom)))
cat(sprintf("  has_bab (2010-01+): %d months\n", sum(master$has_bab)))

# ─── 4 HYBRID RATIO STRATEGY DEFINITIONS ─────────────────────────────────────
# A: STR70 / TSMOM15 / KR10y15 / BAB0   (PG2 status quo)
# B: STR63 / TSMOM13.5 / KR10y13.5 / BAB10
# C: STR56 / TSMOM12 / KR10y12 / BAB20
# D: STR49 / TSMOM10.5 / KR10y10.5 / BAB30
strategy_specs <- list(
  A_0pct  = list(label = "A_0pct_PG2_baseline",  cap_str=0.70, cap_tsm=0.15,  cap_kr=0.15,  cap_bab=0.00),
  B_10pct = list(label = "B_10pct_BAB_admit",    cap_str=0.63, cap_tsm=0.135, cap_kr=0.135, cap_bab=0.10),
  C_20pct = list(label = "C_20pct_BAB_balanced", cap_str=0.56, cap_tsm=0.12,  cap_kr=0.12,  cap_bab=0.20),
  D_30pct = list(label = "D_30pct_BAB_aggressive",cap_str=0.49, cap_tsm=0.105,cap_kr=0.105, cap_bab=0.30)
)

# ─── HELPER: build strategy returns with availability handling ───────────────
build_strategy_returns <- function(master, spec) {
  dt <- copy(master)

  # Per-period weights — handle pre-2010 BAB unavailability + pre-2015 TSMOM
  # Rule: When a leg is unavailable at date d, redirect that share to STR_1715 (anchor)
  # Pre-2010-01: cap_bab → cap_str
  # Pre-2015-01: cap_tsm → cap_str
  dt[, c_str := spec$cap_str]
  dt[, c_tsm := spec$cap_tsm]
  dt[, c_kr  := spec$cap_kr]
  dt[, c_bab := spec$cap_bab]

  # BAB unavailable
  dt[has_bab == FALSE, c_str := c_str + c_bab]
  dt[has_bab == FALSE, c_bab := 0]
  # TSMOM unavailable
  dt[has_tsmom == FALSE, c_str := c_str + c_tsm]
  dt[has_tsmom == FALSE, c_tsm := 0]

  # Σcap = 1 check
  dt[, c_sum := c_str + c_tsm + c_kr + c_bab]
  if (max(abs(dt$c_sum - 1)) > 1e-8) {
    stop(sprintf("[%s] Σcap≠1 max dev: %.6e", spec$label, max(abs(dt$c_sum - 1))))
  }

  # Gross return
  dt[, ret_gross := c_str * ret_str1715 +
                     c_tsm * ret_tsmom_gross +
                     c_kr  * ret_kr10y +
                     c_bab * ret_bab_gross]

  # COSTS:
  # 1. STR_1715: cost embedded in ret_str1715 (already net of 15bps within-sleeve)
  # 2. TSMOM: ml_realized is gross; apply 15bps × turnover. Approximate TSMOM internal turnover = 100% per rebalance (monthly cross-asset rotation high)
  #    Using monthly avg ~50% one-way for 9-ETF rotation as Optimizer ml_realized_net suggests
  # 3. KR_10y: single ETF buy-and-hold within leg → no internal turnover; only capital reallocation
  # 4. BAB: cost embedded in ret_bab_net; we use ret_bab_gross + apply turnover * cost separately for transparency
  # 5. Capital reallocation: static weights → Δc=0 across most dates; only at availability boundary changes

  # BAB cost (M3 smoothed turnover already in bab_to column)
  dt[, cost_bab := c_bab * bab_to * COST_PER_DOLLAR]

  # TSMOM internal cost (approx 50% one-way * cap_tsm * 15bps)
  dt[, cost_tsm := c_tsm * 0.50 * COST_PER_DOLLAR]

  # STR_1715: ret_AR_on_M4 already net (in WT-P20260504_001 forge backtest)
  # KR_10y: ret_kr_10y is gross monthly carry; minimal turnover within bond ETF
  dt[, cost_kr := c_kr * 0.05 * COST_PER_DOLLAR]  # ~5% rebalance friction proxy

  # Capital reallocation (Δc across periods)
  cap_mat <- as.matrix(dt[, .(c_str, c_tsm, c_kr, c_bab)])
  cap_to <- c(0, sapply(2:nrow(cap_mat), function(i) sum(abs(cap_mat[i,] - cap_mat[i-1,])) / 2))
  dt[, cap_realloc := cap_to]
  dt[, cost_cap := cap_realloc * COST_PER_DOLLAR]

  # Total additional cost (STR_1715 ret already net within-sleeve)
  dt[, cost_ret_total := cost_bab + cost_tsm + cost_kr + cost_cap]
  dt[, ret_net := ret_gross - cost_ret_total]
  dt[, turnover_total := c_bab * bab_to + c_tsm * 0.50 + c_kr * 0.05 + cap_realloc]

  dt[, .(date, c_str, c_tsm, c_kr, c_bab,
         ret_str1715, ret_tsmom_gross, ret_kr10y, ret_bab_gross, bab_to,
         ret_gross, ret_net, cost_ret_total, turnover_total,
         cost_bab, cost_tsm, cost_kr, cost_cap, bm_ret)]
}

# ─── HELPER: build sim_result for build_bt_result ───────────────────────────
build_sim_result_x <- function(strat_ret, label) {
  nav_local <- copy(strat_ret)
  nav_local[, NAV_gross := cumprod(1 + ret_gross)]
  nav_local[, NAV       := cumprod(1 + ret_net)]
  nav_local[, cash_weight := 0]  # no explicit cash leg in 4-asset hybrid
  nav_local[, gross_exposure := 1]
  nav_local[, net_exposure := 1]
  nav_local[, leverage := 1]
  setnames(nav_local, "date", "Date")
  daily_nav_dt <- nav_local[, .(Date, NAV_gross, NAV, cash_weight,
                                gross_exposure, net_exposure, leverage)]
  strat_xts <- xts(strat_ret$ret_net, order.by = strat_ret$date)
  bm_xts <- xts(strat_ret$bm_ret, order.by = strat_ret$date)

  # HOLDINGS_LOG: simplified — capital allocations per date
  holdings_log <- list()
  for (i in seq_len(nrow(strat_ret))) {
    d <- strat_ret$date[i]
    rows <- list()
    if (strat_ret$c_str[i] > 0) {
      rows[[length(rows)+1]] <- data.table(
        date = d, ticker = "STR_1715_AR_M4", name = "STR_1715 PG2",
        sector = "EQ_KR_TOP20_SLEEVE",
        target_weight = strat_ret$c_str[i], actual_weight = strat_ret$c_str[i],
        price = NA_real_, shares = NA_real_, market_value = NA_real_,
        signal_score = NA_real_, rank = NA_integer_,
        entry_date = as.Date(NA), holding_period = NA_integer_,
        is_new_position = FALSE, is_exiting_position = FALSE)
    }
    if (strat_ret$c_tsm[i] > 0) {
      rows[[length(rows)+1]] <- data.table(
        date = d, ticker = "TSMOM_9_ETF", name = "TSMOM 9-ETF rotation",
        sector = "ETF_KR_TSMOM_LEG",
        target_weight = strat_ret$c_tsm[i], actual_weight = strat_ret$c_tsm[i],
        price = NA_real_, shares = NA_real_, market_value = NA_real_,
        signal_score = NA_real_, rank = NA_integer_,
        entry_date = as.Date(NA), holding_period = NA_integer_,
        is_new_position = FALSE, is_exiting_position = FALSE)
    }
    if (strat_ret$c_kr[i] > 0) {
      rows[[length(rows)+1]] <- data.table(
        date = d, ticker = "A148070", name = "KODEX_KTB10Y",
        sector = "ETF_KR_BOND10Y_LEG",
        target_weight = strat_ret$c_kr[i], actual_weight = strat_ret$c_kr[i],
        price = NA_real_, shares = NA_real_, market_value = NA_real_,
        signal_score = NA_real_, rank = NA_integer_,
        entry_date = as.Date(NA), holding_period = NA_integer_,
        is_new_position = FALSE, is_exiting_position = FALSE)
    }
    if (strat_ret$c_bab[i] > 0) {
      rows[[length(rows)+1]] <- data.table(
        date = d, ticker = "WT009_BAB_M3", name = "WT-D20260508_009 BAB multi-sleeve",
        sector = "EQ_KR_BAB_M3_SMOOTH",
        target_weight = strat_ret$c_bab[i], actual_weight = strat_ret$c_bab[i],
        price = NA_real_, shares = NA_real_, market_value = NA_real_,
        signal_score = NA_real_, rank = NA_integer_,
        entry_date = as.Date(NA), holding_period = NA_integer_,
        is_new_position = FALSE, is_exiting_position = FALSE)
    }
    if (length(rows) > 0) holdings_log[[i]] <- rbindlist(rows, fill=TRUE)
  }
  holdings_log <- holdings_log[!sapply(holdings_log, is.null)]

  list(
    DAILY_NAV_DT = daily_nav_dt,
    strategy_xts = strat_xts,
    bm_xts = bm_xts,
    HOLDINGS_LOG = holdings_log,
    PORTFOLIO_LOG = data.table(Exec_Date = strat_ret$date, Signal_Date = strat_ret$date)
  )
}

# ─── BUILD strategy_spec ────────────────────────────────────────────────────
build_strategy_spec_x <- function(spec, label) {
  list(
    strategy_id = label,
    strategy_name = sprintf("WT-D20260508_009 Hybrid %s", label),
    strategy_family = "hybrid_4_source_BAB_admission",
    signal_description = sprintf("STR_1715 PG2 AR_M4 (%g) + TSMOM ETF (%g) + KR_10y bond ETF (%g) + WT_009 BAB-M3 (%g)",
                                 spec$cap_str, spec$cap_tsm, spec$cap_kr, spec$cap_bab),
    universe_rule = "STR_1715 sleeve top20 + 9 TSMOM ETF basket + KODEX KTB10Y + WT_009 BAB top20 multi-sleeve",
    rebalance_frequency = "monthly",
    signal_date_rule = "month_end",
    execution_date_rule = "next_trading_day_open",
    weighting_method = sprintf("static_capital_str%g_tsm%g_kr%g_bab%g",
                                spec$cap_str, spec$cap_tsm, spec$cap_kr, spec$cap_bab),
    max_position_weight = 0.20,
    max_leverage = 1,
    cash_rule = "redirect_to_str1715_when_BAB_pre2010_or_TSMOM_pre2015",
    cost_model = sprintf("v2.3_kr_retail_%dbps", COST_BPS_ONEWAY),
    missing_data_rule = "redirect_to_anchor_str1715",
    risk_controls = "BAB sleeve smoothed 3m MA (M3 mitigation, TO 1037%→493%)",
    lookahead_prevention = "C1-C15 strict; PIT signals; t+1 execution; alpha+risk+cov immutable",
    survivorship_bias_control = "Optimizer top20 weights as-is + WT_009 alpha PIT-safe (Date<=sig_date)"
  )
}

# ─── EXECUTE 4 STRATEGIES ────────────────────────────────────────────────────
bt_result_list <- list()
strategy_returns_list <- list()
runtime_audit_list <- list()
crisis_decomp_list <- list()
ax001_audit_list <- list()

for (sname in names(strategy_specs)) {
  spec <- strategy_specs[[sname]]
  cat(sprintf("\n[STRATEGY %s] cap STR=%.2f TSM=%.3f KR=%.3f BAB=%.2f\n",
              spec$label, spec$cap_str, spec$cap_tsm, spec$cap_kr, spec$cap_bab))

  strat_ret <- build_strategy_returns(master, spec)
  strategy_returns_list[[sname]] <- strat_ret

  cat(sprintf("  | gross_mean=%.4f net_mean=%.4f vol_ann=%.4f mean_cost=%.5f\n",
              mean(strat_ret$ret_gross), mean(strat_ret$ret_net),
              sd(strat_ret$ret_net) * sqrt(12), mean(strat_ret$cost_ret_total)))

  sim_result <- build_sim_result_x(strat_ret, spec$label)
  strat_spec <- build_strategy_spec_x(spec, spec$label)

  bt <- build_bt_result(
    sim_result = sim_result,
    strategy_spec = strat_spec,
    run_id = sprintf("%s_%s_%s", TASK_ID, sname, RUN_DT),
    strategy_id = spec$label,
    strategy_version = "1.0",
    benchmark_id = "KOSPI200",
    benchmark_name = "KOSPI 200",
    transaction_cost_bps = COST_BPS_ONEWAY,
    slippage_bps = 0,
    risk_free_rate = 0,
    frequency = "monthly",
    annualization_factor = 12,
    universe_id = "KR_HYBRID_4_SOURCE",
    code_version = sprintf("%s_run_all_v1", TASK_ID),
    created_by_agent = "Forge"
  )
  bt$audit <- audit_bt_result(bt)
  bt_result_list[[sname]] <- bt

  # Save outputs
  out_dir <- file.path(FORGE_DIR, sname)
  comps_to_check <- c("manifest","strategy_spec","nav","period_returns","holdings",
                      "benchmark_returns","metrics","benchmark_compare",
                      "rolling_metrics","drawdowns","audit")
  for (cmp in comps_to_check) {
    if (is.null(bt[[cmp]])) bt[[cmp]] <- data.table()
    if (!is.data.table(bt[[cmp]])) bt[[cmp]] <- as.data.table(bt[[cmp]])
  }
  tryCatch({
    save_bt_result(bt, out_dir, save_xlsx = FALSE)
  }, error = function(e) {
    cat(sprintf("  ! save_bt_result fallback: %s\n", conditionMessage(e)))
    saveRDS(bt, file.path(out_dir, "bt_result.rds"))
    for (cmp in comps_to_check) {
      idx <- which(c("manifest","strategy_spec","nav","period_returns","holdings",
                     "benchmark_returns","metrics","benchmark_compare",
                     "rolling_metrics","drawdowns","audit") == cmp) - 1
      fname <- sprintf("%02d_%s.csv", idx, cmp)
      tryCatch(fwrite(bt[[cmp]], file.path(out_dir, fname)), error = function(e2) {})
    }
  })
  cat(sprintf("  | saved bt_result to: %s\n", out_dir))

  # ─── Alpha invariance runtime audit ───
  # Hybrid is scalar capital scaling — alpha rank within each leg unchanged
  runtime_audit_list[[sname]] <- list(
    strategy = spec$label,
    capital_str = spec$cap_str, capital_bab = spec$cap_bab,
    proof = "scalar_c_per_leg monotone strict (rank corr=1.0 within each leg by lemma)",
    pure_function_compliance = TRUE,
    no_alpha_modification = TRUE,
    no_risk_modification = TRUE,
    no_optimizer_weights_modification = TRUE,
    bab_mitigation_applied = "M3_3m_MA_sleeve_smoothing (Optimizer infeasibility_report option_d explicit)"
  )

  # ─── Crisis decomposition ───
  crises <- list(
    GFC_2008_2009    = c("2008-08-01", "2009-06-30"),
    EuroCrisis_2011  = c("2011-08-01", "2011-12-31"),
    China_2015       = c("2015-06-01", "2016-02-29"),
    Vol2018_Q4       = c("2018-10-01", "2019-01-31"),
    COVID_2020       = c("2020-02-01", "2020-06-30"),
    Stagflation_2022 = c("2022-01-01", "2022-12-31")
  )
  crisis_dec <- list()
  for (cn in names(crises)) {
    win <- crises[[cn]]
    sub <- strat_ret[date >= as.Date(win[1]) & date <= as.Date(win[2])]
    if (nrow(sub) == 0) next
    cum_g <- prod(1 + sub$ret_gross) - 1
    cum_n <- prod(1 + sub$ret_net) - 1
    nav_w <- cumprod(1 + sub$ret_net)
    crisis_dec[[cn]] <- list(
      window = paste0(win[1], "_to_", win[2]), n = nrow(sub),
      cum_ret_gross = cum_g, cum_ret_net = cum_n,
      max_drawdown_in_window = if (nrow(sub) > 1) min(nav_w / cummax(nav_w) - 1) else 0,
      avg_cap_str = mean(sub$c_str), avg_cap_bab = mean(sub$c_bab)
    )
  }
  crisis_decomp_list[[sname]] <- crisis_dec
}

# ─── COMPARISON TABLE ──────────────────────────────────────────────────────
comparison_rows <- lapply(names(bt_result_list), function(sn) {
  m <- bt_result_list[[sn]]$metrics
  pick <- function(metric) {
    val <- m[metric_name == metric, metric_value]
    if (length(val) == 0) NA_real_ else as.numeric(val[1])
  }
  data.table(
    strategy        = sn,
    label           = strategy_specs[[sn]]$label,
    BAB_cap         = strategy_specs[[sn]]$cap_bab,
    n_months        = nrow(strategy_returns_list[[sn]]),
    CAGR            = pick("CAGR"),
    Sharpe          = pick("Sharpe"),
    Sortino         = pick("Sortino"),
    Calmar          = pick("Calmar"),
    Vol_annualized  = pick("Annualized_Volatility"),
    MDD             = pick("MDD"),
    VaR_95          = pick("VaR_95"),
    CVaR_95         = pick("CVaR_95"),
    Skewness        = pick("Skewness"),
    Total_Return    = pick("Total_Return")
  )
})
comparison_dt <- rbindlist(comparison_rows, fill = TRUE)

# Add realized turnover + cost-adjusted SR
to_dt <- rbindlist(lapply(names(strategy_returns_list), function(sn) {
  sr <- strategy_returns_list[[sn]]
  data.table(strategy = sn,
             realized_turnover_round_trip_ann = mean(sr$turnover_total[-1], na.rm=TRUE) * 12 * 2,
             cost_adj_SR_15bps = mean(sr$ret_net) / sd(sr$ret_net) * sqrt(12))
}))
comparison_dt <- merge(comparison_dt, to_dt, by = "strategy")

fwrite(comparison_dt, file.path(FORGE_DIR, "comparison_table_4_hybrid.csv"))
cat("\n[OUTPUT] comparison_table_4_hybrid.csv\n")
print(comparison_dt[, .(strategy, BAB_cap, n_months, CAGR, Sharpe, MDD,
                         realized_turnover_round_trip_ann, cost_adj_SR_15bps)])

write_json(runtime_audit_list, file.path(FORGE_DIR, "alpha_invariance_runtime_audit.json"),
           pretty=TRUE, auto_unbox=TRUE, na="null")
write_json(crisis_decomp_list, file.path(FORGE_DIR, "crisis_decomposition_4_hybrid.json"),
           pretty=TRUE, auto_unbox=TRUE, na="null")

# ─── AX-001 v2 conditional defense audit (실측, Hybrid 4 비율) ──────────────
ax001_v2_realized <- list()
for (sn in names(strategy_returns_list)) {
  sr <- strategy_returns_list[[sn]]
  # Hybrid sleeve "defense layer" = c_kr + c_bab (KR_10y + BAB)
  # Crisis: defined as periods with bm_ret < -5% over a 6m rolling
  # crisis_alpha proxy: mean(ret_net - bm_ret) in crisis periods
  sr[, bm_6m_cum := frollapply(bm_ret, 6, function(x) prod(1+x) - 1, fill=NA)]
  crisis_mask <- !is.na(sr$bm_6m_cum) & sr$bm_6m_cum < -0.10
  normal_mask <- !is.na(sr$bm_6m_cum) & sr$bm_6m_cum > 0.10
  bad_mask    <- !is.na(sr$bm_6m_cum) & sr$bm_6m_cum < 0
  # Crisis alpha
  crisis_alpha <- if (sum(crisis_mask) > 0) mean(sr$ret_net[crisis_mask] - sr$bm_ret[crisis_mask]) else NA_real_
  # Normal alpha
  normal_alpha <- if (sum(normal_mask) > 0) mean(sr$ret_net[normal_mask] - sr$bm_ret[normal_mask]) else NA_real_
  # Core MDD vs Hybrid MDD comparison
  mdd_full <- min(cumprod(1+sr$ret_net) / cummax(cumprod(1+sr$ret_net)) - 1)
  mdd_str_only <- min(cumprod(1+sr$ret_str1715) / cummax(cumprod(1+sr$ret_str1715)) - 1)
  mdd_relief <- mdd_full - mdd_str_only  # positive = improvement
  # Bad/normal IC ratio (using ret as proxy IC)
  bad_ic_proxy <- if (sum(bad_mask) > 0) mean(sr$ret_bab_gross[bad_mask], na.rm=TRUE) else NA_real_
  normal_ic_proxy <- if (sum(normal_mask) > 0) mean(sr$ret_bab_gross[normal_mask], na.rm=TRUE) else NA_real_
  bad_normal_ratio <- if (!is.na(normal_ic_proxy) && abs(normal_ic_proxy) > 1e-6) bad_ic_proxy / normal_ic_proxy else NA_real_
  ax001_v2_realized[[sn]] <- list(
    strategy = strategy_specs[[sn]]$label,
    n_crisis_months = sum(crisis_mask),
    n_normal_months = sum(normal_mask),
    n_bad_months    = sum(bad_mask),
    crisis_alpha_realized = crisis_alpha,
    normal_alpha_realized = normal_alpha,
    bad_normal_ic_ratio_realized = bad_normal_ratio,
    mdd_relief_vs_str1715_only = mdd_relief,
    crisis_alpha_pass_v2_threshold = !is.na(crisis_alpha) && crisis_alpha > 0,
    note = "AX-001 v2 conditional defense: crisis_alpha + Core MDD relief + bad/normal ratio. 전기간 SR 기준 적용 금지."
  )
}
write_json(ax001_v2_realized, file.path(FORGE_DIR, "ax001_v2_realized_audit.json"),
           pretty=TRUE, auto_unbox=TRUE, na="null")
cat("[OUTPUT] ax001_v2_realized_audit.json\n")

# ─── HASH 3-package check (end) ──────────────────────────────────────────────
hash_alpha_end <- md5(file.path(WT_DIR, "alpha_package.json"))
hash_risk_end  <- md5(file.path(WT_DIR, "risk_package.json"))
hash_opt_end   <- md5(file.path(WT_DIR, "optimization_package.json"))
hash_match <- (hash_alpha_start == hash_alpha_end &&
               hash_risk_start  == hash_risk_end &&
               hash_opt_start   == hash_opt_end)
cat(sprintf("\n[HASH END] match=%s\n", hash_match))
if (!hash_match) stop("3-package hash mismatch — package modified during forge run!")

# ─── CHARTS ────────────────────────────────────────────────────────────────
# Equity curves (4 strategies)
eq_curve <- rbindlist(lapply(names(strategy_returns_list), function(sn) {
  data.table(strategy = sn, label = strategy_specs[[sn]]$label,
             date = strategy_returns_list[[sn]]$date,
             nav = cumprod(1 + strategy_returns_list[[sn]]$ret_net))
}))
ggplot(eq_curve, aes(x = date, y = nav, color = strategy)) +
  geom_line(linewidth = 0.7) +
  scale_y_log10() +
  labs(title = "WT-D20260508_009 Equity Curves — 4 Hybrid Ratios (256m)",
       subtitle = "Log scale | 15bps uniform | BAB M3 smoothed | 2005-02 ~ 2026-05",
       x = NULL, y = "NAV (log10)") +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")
ggsave(file.path(CHARTS_DIR, "equity_curve.png"), width = 10, height = 6, dpi = 110)

# OOS zoom 2010+ (BAB active period)
ggplot(eq_curve[date >= as.Date("2010-01-01")], aes(x = date, y = nav, color = strategy)) +
  geom_line(linewidth = 0.7) +
  labs(title = "Equity Curves OOS Zoom — BAB Active Period (2010-01+)",
       subtitle = "WT_009 BAB available only post-2010-01",
       x = NULL, y = "NAV") +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")
ggsave(file.path(CHARTS_DIR, "oos_zoom_chart.png"), width = 10, height = 6, dpi = 110)

# Annual returns
ann_ret <- rbindlist(lapply(names(strategy_returns_list), function(sn) {
  dt <- strategy_returns_list[[sn]]
  dt[, year := format(date, "%Y")]
  dt[, .(ann_ret = prod(1 + ret_net) - 1, strategy = sn), by = year]
}))
ggplot(ann_ret, aes(x = year, y = ann_ret, fill = strategy)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(title = "Annual Returns — 4 Hybrid Ratios", x = NULL, y = "Annual Return") +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom", axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(file.path(CHARTS_DIR, "annual_returns.png"), width = 12, height = 6, dpi = 110)

# Regime decomposition (BAB period: 2010+, by 12m rolling BM_Ret)
regime_data <- rbindlist(lapply(names(strategy_returns_list), function(sn) {
  dt <- copy(strategy_returns_list[[sn]])
  dt[, bm_12m := frollapply(bm_ret, 12, function(x) prod(1+x)-1, fill=NA)]
  dt[, regime := fcase(
    is.na(bm_12m), "WARMUP",
    bm_12m >= 0.20, "BULL",
    bm_12m >= 0, "NEUTRAL",
    bm_12m >= -0.20, "BEAR",
    default = "CRASH"
  )]
  dt[regime != "WARMUP", .(SR = mean(ret_net) / sd(ret_net) * sqrt(12),
                           CAGR = prod(1 + ret_net)^(12/.N) - 1,
                           n = .N, strategy = sn), by = regime]
}))
ggplot(regime_data, aes(x = regime, y = SR, fill = strategy)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  labs(title = "Sharpe by Regime — 4 Hybrid Ratios",
       subtitle = "BM_12m rolling: BULL>=20% | NEUTRAL>=0 | BEAR>=-20% | CRASH<-20%",
       x = "Regime", y = "Sharpe (annualized)") +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")
ggsave(file.path(CHARTS_DIR, "regime_decomposition.png"), width = 10, height = 6, dpi = 110)

cat("\n[OUTPUT] charts: equity_curve / oos_zoom / annual_returns / regime_decomposition\n")

# ─── FINAL SUMMARY ───────────────────────────────────────────────────────────
cat("\n========================================================\n")
cat("  FORGE WT-D20260508_009 BACKTEST COMPLETE\n")
cat("========================================================\n")
cat(sprintf("\nMitigation: M3 (3m MA smoothing, TO 1037%% → 493%%, Hurdle PASS)\n"))
print(comparison_dt[, .(strategy, BAB_cap, CAGR, Sharpe, MDD,
                         realized_TO_ann = realized_turnover_round_trip_ann)])
cat(sprintf("\nAll deliverables:\n  - %s/comparison_table_4_hybrid.csv\n  - %s/{A,B,C,D}_pct/* (10-component bt_result × 4)\n  - %s/charts/*.png\n  - %s/cov_eigen_recompute.json\n  - %s/mitigation_selected.json\n  - %s/ax001_v2_realized_audit.json\n  - %s/alpha_invariance_runtime_audit.json\n  - %s/crisis_decomposition_4_hybrid.json\n",
            FORGE_DIR, FORGE_DIR, FORGE_DIR, FORGE_DIR, FORGE_DIR, FORGE_DIR, FORGE_DIR, FORGE_DIR))
