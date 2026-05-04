## 4-layer comparison: Original / MRS / M4 / AR
## Same period 268m. Frozen lockbox 제거 (full walk-forward only).
## Original reconstructed from M4 ret_net + cash_weight (inverse):
##   r_orig_t = (ret_net_t - cash_weight_{t-1} * rf) / (1 - cash_weight_{t-1})
## MRS = simple 10/20/40% cash overlay based on past-12m KOSPI200 return.

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(PerformanceAnalytics)
})

base_dir <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
wt_dir <- file.path(base_dir, "qepm/mailbox/worktask/WT-P20260504_001")

# ------------------------------------------------------------
# 1. Load M4 returns + cash_weight from NAV
# ------------------------------------------------------------
nav_path <- file.path(base_dir,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/02_nav.csv")
nav <- fread(nav_path)
nav[, date := as.Date(date)]
setorder(nav, date)
# Keep monthly rebalance dates
nav_m <- nav[is_rebalance_date == TRUE | is_rebalance_date == "TRUE"]
cat("[NAV] n_rebal=", nrow(nav_m), " range:",
    as.character(min(nav_m$date)), "to",
    as.character(max(nav_m$date)), "\n")

ret_path <- file.path(base_dir,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv")
ret <- fread(ret_path)
ret[, date := as.Date(date)]
setorder(ret, date)
cat("[ret] n_months=", nrow(ret), "\n")

# Merge NAV cash_weight + period returns
mr <- merge(ret[, .(date, ret_net, ret_gross, risk_free_ret, cash_weight)],
            nav_m[, .(date, drawdown_net, gross_exposure)],
            by = "date", all.x = TRUE)
setorder(mr, date)
cat("[merged] n=", nrow(mr), " cash_weight unique:",
    length(unique(round(mr$cash_weight, 3))), "\n")
print(table(round(mr$cash_weight, 2)))

# ------------------------------------------------------------
# 2. Reconstruct Original (no overlay) returns
# ------------------------------------------------------------
# In strategy, cash_weight_{t-1} (decided at t-1) determines exposure at t.
# But period_returns.csv already has the realized monthly net.
# r_net_t = (1 - cash_t) * r_risk_t + cash_t * rf_t
# r_risk_t = (r_net_t - cash_t * rf_t) / (1 - cash_t)
# rf_t in dataset is 0
# Use cash_weight as period_t exposure (intra-month constant)
mr[, cash_t := cash_weight]
mr[, exposure := pmax(1 - cash_t, 1e-6)]  # legacy: cash_weight all 0

cat("\n[Original reconstruction] cash_weight summary:\n")
print(summary(mr$cash_weight))

# Original = period_returns.csv ret_net (cash_weight all 0 confirmed)
mr[, ret_orig := ret_net]
mr[, ym := format(date, "%Y-%m")]

# Load M4 schedule from WT-D20260430_001
m4_path <- file.path(base_dir,
  "qepm/mailbox/worktask/WT-D20260430_001/judge_ready/weights.csv")
m4 <- fread(m4_path)
m4[, Date := as.Date(Date)]
m4[, ym := format(Date, "%Y-%m")]
m4[, weight_str1715_lag := shift(weight_str1715, 1, fill = 1.0)]
mr <- merge(mr, m4[, .(ym, m4_weight = weight_str1715_lag)],
            by = "ym", all.x = TRUE)
mr[is.na(m4_weight), m4_weight := 1.0]
setorder(mr, date)
cat("\n[M4 schedule loaded] m4_weight unique:",
    length(unique(round(mr$m4_weight, 3))), "\n")
print(table(round(mr$m4_weight, 2)))
mr[, ret_M4 := m4_weight * ret_orig]

# ------------------------------------------------------------
# 3. Build MRS overlay (simple 0/10/20/40 cash by past-12m BM_Ret)
# ------------------------------------------------------------
# Use BM_Ret (KOSPI200) as regime signal
bm_path <- file.path(base_dir,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/05_benchmark_returns.csv")
if (file.exists(bm_path)) {
  bm <- fread(bm_path)
  bm[, date := as.Date(date)]
  if (!"bm_ret" %in% names(bm)) {
    setnames(bm, names(bm)[grepl("ret", names(bm), ignore.case = TRUE)][1],
             "bm_ret")
  }
  bm <- bm[, .(date, bm_ret)]
  setorder(bm, date)
} else {
  raw <- as.data.table(arrow::read_parquet(file.path(base_dir,
                                                     ".cache/rawdata.parquet")))
  raw[, Date := as.Date(Date)]
  bm_d <- unique(raw[, .(Date, BM_Ret)])
  bm_d[, ym := format(Date, "%Y-%m")]
  bm <- bm_d[, .(bm_ret = prod(1 + BM_Ret) - 1), by = ym]
  bm[, date := as.Date(paste0(ym, "-01"))]
  setorder(bm, date)
}

bm[, ym := format(date, "%Y-%m")]
bm_m <- bm[, .(ym, bm_ret = bm_ret)]
bm_m <- bm_m[, .(bm_ret = bm_ret[1]), by = ym]

mr <- merge(mr, bm_m, by = "ym", all.x = TRUE)
setorder(mr, date)

# 12m trailing BM return → MRS regime
mr[, lret_bm := log(1 + pmax(bm_ret, -0.99))]
mr[, bm_12m := exp(frollsum(shift(lret_bm, 1), 12,
                              align = "right", fill = NA_real_)) - 1]

# Regime mapping (4-state):
#   bm_12m >= 10%: bull (0% cash)
#   0 <= bm_12m < 10%: normal (10% cash)
#   -10% <= bm_12m < 0: caution (20% cash)
#   bm_12m < -10%: bear (40% cash)
mr[, mrs_cash := fcase(
  is.na(bm_12m), 0,
  bm_12m >= 0.10, 0.00,
  bm_12m >= 0.00, 0.10,
  bm_12m >= -0.10, 0.20,
  default = 0.40
)]
mr[, mrs_cash_lag := shift(mrs_cash, 1, fill = 0)]
mr[, ret_MRS := (1 - mrs_cash_lag) * ret_orig]

cat("\n[MRS] cash distribution:\n")
print(table(mr$mrs_cash))

# ------------------------------------------------------------
# 4. Apply AR threshold overlay (already computed)
# ------------------------------------------------------------
beta_path <- file.path(base_dir,
  "stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv")
beta_dt <- fread(beta_path)
beta_dt[, Date := as.Date(Date)]
beta_dt[, ym := format(Date, "%Y-%m")]
beta_dt[, beta_threshold_lag := shift(beta_threshold, 1, fill = 1.0)]

mr <- merge(mr, beta_dt[, .(ym, beta_threshold_lag)], by = "ym", all.x = TRUE)
mr[is.na(beta_threshold_lag), beta_threshold_lag := 1.0]
setorder(mr, date)
mr[, db_thr := abs(beta_threshold_lag - shift(beta_threshold_lag, 1,
                                              fill = 1.0))]

# AR applied on top of M4: r_AR = β · ret_M4 - cost
mr[, ret_AR_on_M4 := beta_threshold_lag * ret_M4 - db_thr * 0.0015]

# AR applied on Original (no M4): r_AR_only = β · ret_orig - cost
mr[, ret_AR_on_Orig := beta_threshold_lag * ret_orig - db_thr * 0.0015]

# Exclude warmup (first 13m: 12m for MRS regime + 1m β lag)
dt_v <- mr[!is.na(bm_12m) & !is.na(ret_orig)]
cat("\n[Final] n_months=", nrow(dt_v), " range:",
    as.character(min(dt_v$date)), "to", as.character(max(dt_v$date)), "\n")

# ------------------------------------------------------------
# 5. Compute metrics for 5 layers
# ------------------------------------------------------------
xret <- xts::xts(as.matrix(dt_v[, .(ret_orig, ret_MRS, ret_M4,
                                     ret_AR_on_M4, ret_AR_on_Orig)]),
                 order.by = dt_v$date)

cat("\n=== ANNUALIZED METRICS (5 layers, ", nrow(dt_v), "m) ===\n")
ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
print(ann)

mddv <- maxDrawdown(xret)
cat("\n--- MaxDrawdown ---\n"); print(mddv)
sortino <- SortinoRatio(xret, MAR = 0)
cat("\n--- Sortino ---\n"); print(sortino)
calmar <- CalmarRatio(xret)
cat("\n--- Calmar ---\n"); print(calmar)

# ------------------------------------------------------------
# 6. Summary table
# ------------------------------------------------------------
build_row <- function(label, idx) {
  list(
    layer = label,
    CAGR = round(as.numeric(ann[1, idx]), 4),
    Vol = round(as.numeric(ann[2, idx]), 4),
    Sharpe = round(as.numeric(ann[3, idx]), 4),
    MDD = round(-as.numeric(mddv[idx]), 4),
    Sortino = round(as.numeric(sortino[idx]), 4),
    Calmar = round(as.numeric(calmar[idx]), 4)
  )
}

summary_dt <- rbindlist(list(
  build_row("1_Original_no_overlay", 1),
  build_row("2_MRS_simple_cash_4state", 2),
  build_row("3_M4_BOCPD_decay_BL", 3),
  build_row("4_AR_on_M4_threshold_S1", 4),
  build_row("5_AR_on_Original_no_M4", 5)
))

cat("\n=== 4-LAYER COMPARISON SUMMARY ===\n")
print(summary_dt)

# Delta vs Original
delta_dt <- data.table(
  layer = summary_dt$layer[2:5],
  delta_CAGR_pp = (summary_dt$CAGR[2:5] - summary_dt$CAGR[1]) * 100,
  delta_Vol_pp = (summary_dt$Vol[2:5] - summary_dt$Vol[1]) * 100,
  delta_Sharpe = summary_dt$Sharpe[2:5] - summary_dt$Sharpe[1],
  delta_MDD_pp_improvement = (summary_dt$MDD[2:5] - summary_dt$MDD[1]) * 100,
  delta_Sortino = summary_dt$Sortino[2:5] - summary_dt$Sortino[1],
  delta_Calmar = summary_dt$Calmar[2:5] - summary_dt$Calmar[1]
)
cat("\n=== DELTA vs Original (no overlay) ===\n")
print(delta_dt)

# Save
fwrite(summary_dt, file.path(wt_dir, "four_layer_comparison_summary.csv"))
fwrite(delta_dt, file.path(wt_dir, "four_layer_comparison_delta.csv"))
fwrite(dt_v[, .(date, ret_orig, ret_MRS, ret_M4, ret_AR_on_M4,
                ret_AR_on_Orig, cash_weight, mrs_cash_lag,
                beta_threshold_lag, bm_12m)],
       file.path(wt_dir, "four_layer_returns_path.csv"))

result <- list(
  task_id = "WT-P20260504_001",
  comparison_kind = "4_layer_actual_backtest_no_frozen",
  n_months = nrow(dt_v),
  period = paste0(min(dt_v$date), " to ", max(dt_v$date)),
  layers = list(
    Original = list(label = "STR_1715 raw walk-forward (no overlay)",
                     reconstruction = "ret_orig = ret_net / (1 - cash_weight)",
                     metrics = build_row("Original", 1)),
    MRS = list(label = "Simple 4-state cash 0/10/20/40 by trailing 12m BM",
                reconstruction = "ret_MRS = (1 - mrs_cash_lag) * ret_orig",
                metrics = build_row("MRS", 2)),
    M4 = list(label = "M4 BOCPD+decay+BL tri-pillar (current PG2)",
              source = "ret_net direct",
              metrics = build_row("M4", 3)),
    AR_on_M4 = list(label = "AR threshold on top of M4 (newly admitted)",
                     reconstruction = "β · ret_M4 - cost",
                     metrics = build_row("AR_on_M4", 4)),
    AR_on_Original = list(label = "AR threshold on Original (M4 replaced)",
                           reconstruction = "β · ret_orig - cost",
                           metrics = build_row("AR_on_Orig", 5))
  ),
  delta_vs_Original = lapply(seq_len(4), function(i) {
    list(layer = delta_dt$layer[i],
         delta_CAGR_pp = delta_dt$delta_CAGR_pp[i],
         delta_Vol_pp = delta_dt$delta_Vol_pp[i],
         delta_Sharpe = delta_dt$delta_Sharpe[i],
         delta_MDD_pp = delta_dt$delta_MDD_pp_improvement[i],
         delta_Sortino = delta_dt$delta_Sortino[i],
         delta_Calmar = delta_dt$delta_Calmar[i])
  }),
  caveats = list(
    paste0("Original reconstruction assumes risk-sleeve return is intra-month",
           " constant; for months with cash_weight > 0 this is a linear inverse"),
    paste0("MRS uses simple 4-state regime (bm_12m thresholds 10/0/-10) — ",
           "older v53 era convention, not the current M4 algorithm"),
    "M4 = current PG2 production schedule (BOCPD+decay+BL)",
    "AR overlay = newly admitted (Round 3 WT-007/WT-P20260504_001)",
    "Cost: 15bps round-trip applied for AR overlay only (M4/MRS already in ret_net)",
    paste0("Period excludes 13m warmup (12m MRS regime + 1m β lag)")
  ),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
)

write_json(result, file.path(wt_dir, "four_layer_comparison.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("\n[saved] four_layer_comparison.json + summary.csv + delta.csv + path.csv\n")
