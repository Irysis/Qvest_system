## ============================================================================
## WT-T20260509_001 — Phase 2: 5-Family Re-Backtest with Updated alpha_scores
##
## Pre-condition: STR_1715/run_all.R re-run complete (268m base returns ready)
##
## Track A: 4-layer overlay reconstruction (Original / MRS / M4 / AR-on-M4 / AR-on-Orig)
##   - Inline implementation (avoid Date class bug in WT-P20260504_001/four_layer_comparison.R)
##   - Inputs: STR_1715 ret_net (268m) + M4 weights (WT-D20260430_001) + β_threshold (WT_S20260504_007)
##
## Track B: 5-family backtest (S0 baseline / S1 KR10y / S2 TSMOM / S3 70/15/15 / S4 50/25/25)
##   - Inputs: AR_on_M4 (Track A) + KR10y returns (WT-S20260504_008) + TSMOM (WT-S20260504_009)
##   - Use WT-P20260505_001 weights.csv schedule (256 dates, 2005-02 ~ 2026-05)
##     NOTE: STR_1715 268m ranges 2004-01 ~ 2026-04, so 5-family coverage = intersection
##
## Boundary (Pure Function R12):
##   - 5 family 정의 변경 X (S0~S4 retain)
##   - cost = 15bps uniform (Backtest Result Contract v1.0)
##   - PerformanceAnalytics 표준 함수만
##
## Outputs:
##   - output/four_layer_returns_path_updated.csv (268m, new AR_on_M4)
##   - output/four_layer_summary_updated.csv (5 layers metrics)
##   - output/5family_updated/<Sx>/* (10-component bt_result × 5)
##   - output/5family_metrics_updated.csv
##   - phase2_audit.json
## ============================================================================

cat("\n========================================================\n")
cat("  WT-T20260509_001 Phase 2 — 4-Layer + 5-Family Backtest\n")
cat(sprintf("  Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("========================================================\n\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR  <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260509_001")
OUT_DIR <- file.path(WT_DIR, "output")
dir.create(OUT_DIR, showWarnings=FALSE, recursive=TRUE)

setwd(PROJECT_ROOT)

suppressPackageStartupMessages({
  library(jsonlite); library(data.table); library(arrow); library(lubridate)
  library(PerformanceAnalytics); library(xts)
})

source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/audit_bt_result.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/save_bt_result.R"))

COST_BPS_ONEWAY <- 15
COST_PER_DOLLAR <- COST_BPS_ONEWAY / 10000   # 0.0015
ANN_FACTOR <- 12
RUN_DT <- format(Sys.time(), "%Y%m%d_%H%M%S")

# ─── INPUT 1: STR_1715 268m base returns (after run_all.R rerun) ──────────────
str1715_dir <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output")
ret_path <- file.path(str1715_dir, "03_period_returns.csv")
if (!file.exists(ret_path)) stop("[FAIL] STR_1715 03_period_returns.csv not found — run_all.R 미실행?")
ret <- fread(ret_path)
ret[, date := as.Date(date)]
setorder(ret, date)
cat(sprintf("[INPUT-1 STR_1715 base] %d months (%s ~ %s)\n",
            nrow(ret), as.character(min(ret$date)), as.character(max(ret$date))))

nav_path <- file.path(str1715_dir, "02_nav.csv")
nav <- fread(nav_path)
# Robust Date/date column handling
if ("Date" %in% names(nav) && !"date" %in% names(nav)) setnames(nav, "Date", "date")
nav[, date := as.Date(date)]
setorder(nav, date)
# is_rebalance_date column 없으면 (Phase 1c PATCH 산출 nav) 모든 row가 monthly rebalance
if ("is_rebalance_date" %in% names(nav)) {
  nav_m <- nav[is_rebalance_date == TRUE | is_rebalance_date == "TRUE"]
} else {
  nav_m <- copy(nav)
}
# drawdown_net column이 없을 시 NA stub
if (!"drawdown_net" %in% names(nav_m)) nav_m[, drawdown_net := NA_real_]
if (!"gross_exposure" %in% names(nav_m)) nav_m[, gross_exposure := 1.0]
cat(sprintf("[INPUT-1 STR_1715 nav] %d rebalance dates\n", nrow(nav_m)))

# Merge for cash_weight (intra-month exposure)
mr <- merge(ret[, .(date, ret_net, ret_gross, risk_free_ret, cash_weight, turnover)],
            nav_m[, .(date, drawdown_net, gross_exposure)],
            by = "date", all.x = TRUE)
setorder(mr, date)
mr[, cash_t := cash_weight]
mr[, exposure := pmax(1 - cash_t, 1e-6)]
mr[, ret_orig := ret_net]   # cash_weight all 0 for STR_1715 base (no Iter31 cash overlay)
mr[, ym := format(date, "%Y-%m")]

# ─── INPUT 2: M4 schedule ─────────────────────────────────────────────────────
m4_path <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260430_001/judge_ready/weights.csv")
m4 <- fread(m4_path)
m4[, Date := as.Date(Date)]
m4[, ym := format(Date, "%Y-%m")]
m4[, weight_str1715_lag := shift(weight_str1715, 1, fill = 1.0)]
mr <- merge(mr, m4[, .(ym, m4_weight = weight_str1715_lag)], by = "ym", all.x = TRUE)
mr[is.na(m4_weight), m4_weight := 1.0]
setorder(mr, date)
mr[, ret_M4 := m4_weight * ret_orig]
cat(sprintf("[INPUT-2 M4] %d unique m4_weight: %s\n",
            length(unique(round(mr$m4_weight, 3))),
            paste(sort(unique(round(mr$m4_weight, 3))), collapse=", ")))

# ─── INPUT 3: BM (KOSPI) ─────────────────────────────────────────────────────
bm_path_csv <- file.path(str1715_dir, "05_benchmark_returns.csv")
if (file.exists(bm_path_csv)) {
  bm <- fread(bm_path_csv)
  bm[, date := as.Date(date)]
  if (!"bm_ret" %in% names(bm)) {
    setnames(bm, names(bm)[grepl("ret", names(bm), ignore.case = TRUE)][1], "bm_ret")
  }
  bm <- bm[, .(date, bm_ret)]
} else {
  raw <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/rawdata.parquet")))
  raw[, Date := as.Date(Date)]
  bm_d <- unique(raw[, .(Date, BM_Ret)])
  bm_d[, ym := format(Date, "%Y-%m")]
  bm <- bm_d[, .(bm_ret = prod(1 + BM_Ret) - 1), by = ym]
  bm[, date := as.Date(paste0(ym, "-01"))]
}
setorder(bm, date)
bm[, ym := format(date, "%Y-%m")]
bm_m <- bm[, .(ym, bm_ret = bm_ret)][, .(bm_ret = bm_ret[1]), by = ym]
mr <- merge(mr, bm_m, by = "ym", all.x = TRUE)
setorder(mr, date)

# ─── MRS overlay (12m trailing BM) ───────────────────────────────────────────
mr[, lret_bm := log(1 + pmax(bm_ret, -0.99))]
mr[, bm_12m := exp(frollsum(shift(lret_bm, 1), 12, align = "right", fill = NA_real_)) - 1]
mr[, mrs_cash := fcase(
  is.na(bm_12m), 0,
  bm_12m >= 0.10, 0.00,
  bm_12m >= 0.00, 0.10,
  bm_12m >= -0.10, 0.20,
  default = 0.40
)]
mr[, mrs_cash_lag := shift(mrs_cash, 1, fill = 0)]
mr[, ret_MRS := (1 - mrs_cash_lag) * ret_orig]

# ─── AR threshold overlay ────────────────────────────────────────────────────
beta_path <- file.path(PROJECT_ROOT, "stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv")
beta_dt <- fread(beta_path)
beta_dt[, Date := as.Date(Date)]
beta_dt[, ym := format(Date, "%Y-%m")]
beta_dt[, beta_threshold_lag := shift(beta_threshold, 1, fill = 1.0)]
mr <- merge(mr, beta_dt[, .(ym, beta_threshold_lag)], by = "ym", all.x = TRUE)
mr[is.na(beta_threshold_lag), beta_threshold_lag := 1.0]
setorder(mr, date)
mr[, db_thr := abs(beta_threshold_lag - shift(beta_threshold_lag, 1, fill = 1.0))]

# AR cost: 15bps × 2 (round-trip) when β changes
mr[, ret_AR_on_M4    := beta_threshold_lag * ret_M4   - db_thr * 0.0015]
mr[, ret_AR_on_Orig  := beta_threshold_lag * ret_orig - db_thr * 0.0015]

# Exclude warmup (12m for MRS regime + 1m β lag = 13m)
dt_v <- mr[!is.na(bm_12m) & !is.na(ret_orig)]
cat(sprintf("\n[4-LAYER] Final n_months=%d (%s ~ %s)\n",
            nrow(dt_v), as.character(min(dt_v$date)), as.character(max(dt_v$date))))

# Save 4-layer path
fwrite(dt_v[, .(date, ret_orig, ret_MRS, ret_M4, ret_AR_on_M4, ret_AR_on_Orig,
                cash_weight, mrs_cash_lag, beta_threshold_lag, bm_12m)],
       file.path(OUT_DIR, "four_layer_returns_path_updated.csv"))

# ─── Compute 4-layer metrics ─────────────────────────────────────────────────
xret <- xts::xts(as.matrix(dt_v[, .(ret_orig, ret_MRS, ret_M4, ret_AR_on_M4, ret_AR_on_Orig)]),
                 order.by = dt_v$date)

cat(sprintf("\n=== 4-LAYER ANNUALIZED METRICS (%d months) ===\n", nrow(dt_v)))
ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
print(ann)
mddv <- maxDrawdown(xret)
sortino_v <- SortinoRatio(xret, MAR = 0)
calmar_v <- CalmarRatio(xret)

build_layer_row <- function(label, idx) {
  list(
    layer = label,
    CAGR = round(as.numeric(ann[1, idx]), 4),
    Vol = round(as.numeric(ann[2, idx]), 4),
    Sharpe = round(as.numeric(ann[3, idx]), 4),
    MDD = round(-as.numeric(mddv[idx]), 4),
    Sortino = round(as.numeric(sortino_v[idx]), 4),
    Calmar = round(as.numeric(calmar_v[idx]), 4)
  )
}
four_layer_summary <- rbindlist(list(
  build_layer_row("1_Original_no_overlay", 1),
  build_layer_row("2_MRS_simple_cash", 2),
  build_layer_row("3_M4_BOCPD_BL", 3),
  build_layer_row("4_AR_on_M4_threshold", 4),
  build_layer_row("5_AR_on_Original", 5)
))
fwrite(four_layer_summary, file.path(OUT_DIR, "four_layer_summary_updated.csv"))
cat("\n[4-LAYER SUMMARY SAVED]\n")
print(four_layer_summary)

# ─── 5-Family Backtest ──────────────────────────────────────────────────────
cat("\n========================================================\n")
cat("  PHASE 2 Track B: 5-Family Backtest\n")
cat("========================================================\n\n")

# INPUT 4: weights.csv (Hybrid 70/15/15 admit, 256 dates) — for S3 capital schedule
weights <- fread(file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-P20260505_001/weights.csv"))
weights[, as_of_date := as.Date(as_of_date)]
schedule_dates_w <- sort(unique(weights$as_of_date))
cat(sprintf("[INPUT-4 weights.csv] %d unique schedule dates\n", length(schedule_dates_w)))

# INPUT 5: KR10y bond ETF returns
kr10y_path <- file.path(PROJECT_ROOT, "stage_artifacts/WT_S20260504_008/merged_returns.csv")
kr10y_full <- fread(kr10y_path)
kr10y_full[, date := as.Date(date)]
kr10y_dt <- kr10y_full[, .(date, kr_10y)]
setkey(kr10y_dt, date)
cat(sprintf("[INPUT-5 KR10y] %d obs (%s ~ %s)\n",
            nrow(kr10y_dt), as.character(min(kr10y_dt$date)), as.character(max(kr10y_dt$date))))

# INPUT 6: TSMOM rotation
tsmom_path <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-S20260504_009/docs/rotation_path_TSMOM.csv")
tsmom_full <- fread(tsmom_path)
tsmom_full[, date := as.Date(date)]
tsmom_dt <- tsmom_full[, .(date, tsmom_gross = ml_realized + 0)]
setkey(tsmom_dt, date)
cat(sprintf("[INPUT-6 TSMOM] %d obs (%s ~ %s)\n",
            nrow(tsmom_dt), as.character(min(tsmom_dt$date)), as.character(max(tsmom_dt$date))))

# Aggregate TSMOM weight matrix for internal turnover
tsmom_w_cols <- grep("^w_etf_", names(tsmom_full), value = TRUE)
tsmom_wmat <- tsmom_full[, c("date", tsmom_w_cols), with = FALSE]
tsmom_wmat_dates <- tsmom_wmat$date
tsmom_w_only <- as.matrix(tsmom_wmat[, !"date"])
tsmom_internal_to <- c(NA_real_,
  sapply(2:nrow(tsmom_w_only), function(i) sum(abs(tsmom_w_only[i,] - tsmom_w_only[i-1,])) / 2))
tsmom_to_dt <- data.table(date = tsmom_wmat_dates, tsmom_internal_to = tsmom_internal_to)
tsmom_to_dt[is.na(tsmom_internal_to), tsmom_internal_to := 0]
setkey(tsmom_to_dt, date)

# ─── Build master with all leg inputs ────────────────────────────────────────
# AR_on_M4 from Track A (updated)
ar_dt_new <- dt_v[, .(date, ret_AR_on_M4)]
setkey(ar_dt_new, date)

# STR_1715 turnover (period_returns.csv)
str1715_to <- ret[, .(date, str1715_to = turnover)]
setkey(str1715_to, date)

# BM from STR_1715 monthly bm_ret (mr$bm_ret already aligned to month-start)
bm_master <- mr[, .(date, bm_ret)]
setkey(bm_master, date)

# Master = STR_1715 dates ∩ KR10y ∩ TSMOM (some pre-2015 TSMOM unavailable, fill 0)
master <- merge(ret[, .(date)], ar_dt_new, by = "date", all.x = TRUE)
master <- merge(master, kr10y_dt, by = "date", all.x = TRUE)
master <- merge(master, tsmom_dt, by = "date", all.x = TRUE)
master <- merge(master, bm_master, by = "date", all.x = TRUE)
master <- merge(master, str1715_to, by = "date", all.x = TRUE)
master <- merge(master, tsmom_to_dt, by = "date", all.x = TRUE)
master[is.na(tsmom_gross), tsmom_gross := 0]
master[is.na(kr_10y), kr_10y := 0]
master[is.na(ret_AR_on_M4), ret_AR_on_M4 := 0]
master[is.na(bm_ret), bm_ret := 0]
master[is.na(str1715_to), str1715_to := 0]
master[is.na(tsmom_internal_to), tsmom_internal_to := 0]

cat(sprintf("\n[MASTER] %d rows | %s ~ %s\n",
            nrow(master), as.character(min(master$date)), as.character(max(master$date))))

# Restrict to 4-layer overlay valid period (post-warmup)
master <- master[date %in% dt_v$date]
cat(sprintf("[MASTER] post-warmup restriction: %d rows | %s ~ %s\n",
            nrow(master), as.character(min(master$date)), as.character(max(master$date))))

# ─── Strategy capital allocation function ────────────────────────────────────
build_strategy_returns <- function(master, label) {
  dt <- copy(master)
  if (label == "S0_baseline") {
    dt[, `:=`(c_AR = 1, c_TS = 0, c_KR = 0, c_CSH = 0)]
  } else if (label == "S1_KR10y_only") {
    dt[, `:=`(c_AR = 0.70, c_TS = 0.0, c_KR = 0.20, c_CSH = 0.10)]
  } else if (label == "S2_TSMOM_only") {
    dt[, c_AR  := 0.70]
    dt[, c_TS  := ifelse(date >= as.Date("2015-01-01"), 0.30, 0.00)]
    dt[, c_KR  := 0.00]
    dt[, c_CSH := ifelse(date >= as.Date("2015-01-01"), 0.00, 0.30)]
  } else if (label == "S3_Hybrid_70_15_15") {
    dt[, c_AR  := 0.70]
    dt[, c_TS  := ifelse(date >= as.Date("2015-01-01"), 0.15, 0.00)]
    dt[, c_KR  := 0.15]
    dt[, c_CSH := ifelse(date >= as.Date("2015-01-01"), 0.00, 0.15)]
  } else if (label == "S4_Hybrid_50_25_25") {
    dt[, c_AR  := 0.50]
    dt[, c_TS  := ifelse(date >= as.Date("2015-01-01"), 0.25, 0.00)]
    dt[, c_KR  := 0.20]
    dt[, c_CSH := 1 - c_AR - c_TS - c_KR]
  }
  dt[, c_sum := c_AR + c_TS + c_KR + c_CSH]
  if (max(abs(dt$c_sum - 1)) > 1e-8) stop(sprintf("[%s] Σcap≠1 max dev: %g", label, max(abs(dt$c_sum - 1))))

  dt[, ret_gross := c_AR * ret_AR_on_M4 + c_TS * tsmom_gross + c_KR * kr_10y + c_CSH * 0]
  dt[, cost_sleeve := c_AR * str1715_to * COST_PER_DOLLAR]
  dt[, cost_tsmom_internal := c_TS * tsmom_internal_to * COST_PER_DOLLAR]
  cap_mat <- as.matrix(dt[, .(c_AR, c_TS, c_KR, c_CSH)])
  cap_to <- c(NA_real_, sapply(2:nrow(cap_mat), function(i) sum(abs(cap_mat[i,] - cap_mat[i-1,])) / 2))
  cap_to[is.na(cap_to)] <- 0
  dt[, cap_reallocation_to := cap_to]
  dt[, cost_cap_reallocation := cap_reallocation_to * COST_PER_DOLLAR]
  dt[, cost_ret_total := cost_sleeve + cost_tsmom_internal + cost_cap_reallocation]
  dt[, ret_net := ret_gross - cost_ret_total]
  dt[, turnover_total := c_AR * str1715_to + c_TS * tsmom_internal_to + cap_reallocation_to]
  dt[, .(date, c_AR, c_TS, c_KR, c_CSH, ret_gross, ret_net, cost_ret_total,
          turnover_total, cost_sleeve, cost_tsmom_internal, cost_cap_reallocation)]
}

build_strategy_spec <- function(label, w_AR, w_TS, w_KR, w_CSH) {
  list(
    strategy_id = label,
    strategy_name = sprintf("WT-T20260509_001 %s (alpha 268m updated)", label),
    strategy_family = "hybrid_overlay_alpha_lockbox_release",
    signal_description = "STR_1715 Iter31 base + AR threshold overlay + TSMOM + KR10y bond carry, alpha_scores 268m updated (lockbox release)",
    universe_rule = "STR_1715 sleeve top20 + 9 TSMOM ETF + KODEX KTB10Y + CASH",
    rebalance_frequency = "monthly",
    signal_date_rule = "month_end",
    execution_date_rule = "next_trading_day_open",
    weighting_method = sprintf("static_capital_AR_%g_TS_%g_KR_%g_CSH_%g", w_AR, w_TS, w_KR, w_CSH),
    max_position_weight = 0.20,
    max_leverage = 1,
    cash_rule = "residual_to_cash_when_TSMOM_or_KR10y_unavailable",
    cost_model = sprintf("v2.3_kr_retail_%dbps", COST_BPS_ONEWAY),
    missing_data_rule = "drop",
    risk_controls = "TSMOM 30pct cap + KR10y 20pct cap",
    lookahead_prevention = "C1-C15 strict; PIT signals; t+1 exec",
    survivorship_bias_control = "K200∪KQ150 PIT membership"
  )
}

# Build 5-family bt_result
strategy_specs <- list(
  S0_baseline        = list(label = "S0_baseline",        cap = c(AR=1.00, TS=0.00, KR=0.00, CSH=0.00)),
  S1_KR10y_only      = list(label = "S1_KR10y_only",      cap = c(AR=0.70, TS=0.00, KR=0.20, CSH=0.10)),
  S2_TSMOM_only      = list(label = "S2_TSMOM_only",      cap = c(AR=0.70, TS=0.30, KR=0.00, CSH=0.00)),
  S3_Hybrid_70_15_15 = list(label = "S3_Hybrid_70_15_15", cap = c(AR=0.70, TS=0.15, KR=0.15, CSH=0.00)),
  S4_Hybrid_50_25_25 = list(label = "S4_Hybrid_50_25_25", cap = c(AR=0.50, TS=0.25, KR=0.20, CSH=0.05))
)

family_metrics_dt <- list()
strat_returns_list <- list()

for (sname in names(strategy_specs)) {
  spec <- strategy_specs[[sname]]
  cat(sprintf("\n[%s] capital weights: AR=%.2f TS=%.2f KR=%.2f CSH=%.2f\n",
              spec$label, spec$cap["AR"], spec$cap["TS"], spec$cap["KR"], spec$cap["CSH"]))

  strat_ret <- build_strategy_returns(master, spec$label)
  strat_returns_list[[sname]] <- strat_ret

  # PerformanceAnalytics metrics (Backtest Result Contract v1.0)
  sx <- xts(strat_ret$ret_net, order.by = strat_ret$date)
  ann_s <- table.AnnualizedReturns(sx, scale = 12, Rf = 0)
  cagr_s <- as.numeric(ann_s[1, 1])
  vol_s  <- as.numeric(ann_s[2, 1])
  sr_s   <- as.numeric(ann_s[3, 1])
  mdd_s  <- as.numeric(maxDrawdown(sx))
  sort_s <- as.numeric(SortinoRatio(sx, MAR = 0))
  cal_s  <- as.numeric(CalmarRatio(sx))
  to_avg <- mean(strat_ret$turnover_total, na.rm = TRUE) * 12   # annualized
  cost_avg <- mean(strat_ret$cost_ret_total, na.rm = TRUE) * 12

  family_metrics_dt[[sname]] <- list(
    family = sname, label = spec$label,
    n_months = nrow(strat_ret),
    period = paste0(min(strat_ret$date), " ~ ", max(strat_ret$date)),
    Sharpe = round(sr_s, 4), CAGR = round(cagr_s, 4), Vol = round(vol_s, 4),
    MDD = round(mdd_s, 4), Sortino = round(sort_s, 4), Calmar = round(cal_s, 4),
    Turnover_ann = round(to_avg, 4), Cost_ann = round(cost_avg, 6)
  )

  cat(sprintf("  Sharpe=%.4f CAGR=%.4f MDD=%.4f Sortino=%.4f Calmar=%.4f TO_ann=%.2f Cost_ann=%.4f\n",
              sr_s, cagr_s, mdd_s, sort_s, cal_s, to_avg, cost_avg))

  # Save period returns for downstream OOS / lockbox split
  strat_save_dir <- file.path(OUT_DIR, "5family_updated", sname)
  dir.create(strat_save_dir, showWarnings = FALSE, recursive = TRUE)
  fwrite(strat_ret, file.path(strat_save_dir, "period_returns.csv"))
}

family_metrics_table <- rbindlist(family_metrics_dt, fill = TRUE)
fwrite(family_metrics_table, file.path(OUT_DIR, "5family_metrics_updated.csv"))
cat("\n========================================================\n")
cat("  5-Family Metrics (Updated alpha 268m)\n")
cat("========================================================\n")
print(family_metrics_table)

# ─── OOS metric: lockbox period (2024-01 ~ 2026-04) ──────────────────────────
LB_START <- as.Date("2024-01-01")
LB_END   <- as.Date("2026-05-01")
oos_metrics_dt <- list()

for (sname in names(strategy_specs)) {
  s <- strat_returns_list[[sname]]
  s_oos <- s[date >= LB_START & date < LB_END]
  if (nrow(s_oos) >= 6) {
    sx <- xts(s_oos$ret_net, order.by = s_oos$date)
    ann_s <- table.AnnualizedReturns(sx, scale = 12, Rf = 0)
    sr_oos <- as.numeric(ann_s[3, 1])
    cagr_oos <- as.numeric(ann_s[1, 1])
    mdd_oos <- as.numeric(maxDrawdown(sx))
  } else {
    sr_oos <- NA; cagr_oos <- NA; mdd_oos <- NA
  }
  oos_metrics_dt[[sname]] <- list(
    family = sname,
    n_oos_months = nrow(s_oos),
    Sharpe_OOS = round(sr_oos, 4),
    CAGR_OOS = round(cagr_oos, 4),
    MDD_OOS = round(mdd_oos, 4)
  )
}
oos_metrics_table <- rbindlist(oos_metrics_dt, fill = TRUE)
fwrite(oos_metrics_table, file.path(OUT_DIR, "5family_OOS_metrics.csv"))
cat("\n=== OOS METRICS (2024-01 ~ 2026-04 lockbox period) ===\n")
print(oos_metrics_table)

# ─── Phase 2 audit ────────────────────────────────────────────────────────────
phase2_audit <- list(
  task_id = "WT-T20260509_001",
  phase = "Phase 2",
  track_a_4layer = list(
    n_months = nrow(dt_v),
    period = paste0(as.character(min(dt_v$date)), " ~ ", as.character(max(dt_v$date))),
    summary = four_layer_summary
  ),
  track_b_5family = list(
    cost_bps = COST_BPS_ONEWAY,
    metrics_full = family_metrics_table,
    metrics_oos = oos_metrics_table
  ),
  status = "PASS",
  timestamp_end = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
write_json(phase2_audit, file.path(WT_DIR, "phase2_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("\n[AUDIT] Saved: %s\n", file.path(WT_DIR, "phase2_audit.json")))
cat("\n========================================================\n")
cat(sprintf("  Phase 2 — PASS\n"))
cat("========================================================\n")
