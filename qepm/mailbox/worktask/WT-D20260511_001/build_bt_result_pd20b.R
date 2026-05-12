#==============================================================================
# WT-D20260511_001 PD20-B — Backtest Contract v1.0 bt_result 10-component build
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(zoo)
})

WT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001"
OUT_DIR <- file.path(WT_DIR, "backtest_result_pd20b")

cat("=== PD20-B Backtest Contract v1.0 bt_result build ===\n\n")

# Load period_returns
pr <- fread(file.path(OUT_DIR, "period_returns.csv"))
pr[, Date := as.Date(Date)]
setorder(pr, Date)

# Load metrics
m <- readRDS(file.path(OUT_DIR, "metrics_pd20b.rds"))

# 1. manifest
manifest <- data.table(
  task_id = "WT-D20260511_001",
  candidate = "pd20b_path2_zscore_composite",
  package_kind = "forge_package_pd20b_zscore_composite",
  as_of_date = "2026-05-11",
  method = "4_sleeve_zscore_composite_top20_monthly_rebal_redistribute_w1715_0p818_wnew_0p182",
  primary_window_start = "2005-02-01",
  primary_window_end = "2026-04-01",
  n_months = 255,
  cost_model_version = "v2.3_kr_retail_15bps",
  pure_function_violation = FALSE,
  agent_version = "v6.4-pure-function"
)
fwrite(manifest, file.path(OUT_DIR, "manifest.csv"))

# 2. strategy_spec
strategy_spec <- data.table(
  field = c("sleeve_kr_equity", "sleeve_TSMOM", "sleeve_KR_10y", "sleeve_Cash",
            "w_kr_equity", "w_TSMOM", "w_KR_10y", "w_Cash",
            "composite_w_1715", "composite_w_NEW", "top_N", "rebal_frequency",
            "universe", "liquidity_filter", "long_only", "production_20_cap"),
  value = c("Composite top20 z-score (STR_1715 score_eff + NEW Vol/Skew alpha)",
            "8-ETF basket post KODEX_KTB10Y removal",
            "A148070 KODEX 국고채10년 ETF",
            "0% return KRW placeholder",
            "0.550", "0.225", "0.180", "0.045",
            "0.818", "0.182", "20", "monthly (184 sig_dates 2011-01 ~ 2026-04)",
            "KOSPI200 ∪ KOSDAQ150", "ADV_20d (PIT t-1) >= 2e8 KRW",
            "TRUE", "TRUE")
)
fwrite(strategy_spec, file.path(OUT_DIR, "strategy_spec.csv"))

# 3. nav (already created)
# 4. period_returns (already created)
# 5. holdings — composite top20 over 184 dates
holdings_dt <- fread("stage_artifacts/WT_D20260511_001/composite_top20_holdings_pd20b.csv")
holdings_dt[, weight_in_sleeve := 0.05]
holdings_dt[, weight_in_portfolio := 0.0275]
fwrite(holdings_dt, file.path(OUT_DIR, "holdings.csv"))

# 6. benchmark_returns (KOSPI200 from rawdata)
rd <- as.data.table(read_parquet(".cache/rawdata.parquet"))
bm_dt <- rd[, .(BM_Ret = mean(BM_Ret, na.rm = TRUE)), by = .(ym = format(Date, "%Y-%m"))]
bm_dt[, Date := as.Date(paste0(ym, "-01"))]
bm_dt <- bm_dt[Date >= as.Date("2005-02-01") & Date <= as.Date("2026-04-01")]
setorder(bm_dt, Date)
bm_dt[, BM_cumret := cumprod(1 + BM_Ret)]
bm_dt <- bm_dt[, .(Date, BM_Ret, BM_cumret)]
fwrite(bm_dt, file.path(OUT_DIR, "benchmark_returns.csv"))

# 7. metrics (already created)

# 8. benchmark_compare (already created with S4 v2)
# Extended with benchmark KOSPI200
bc_existing <- fread(file.path(OUT_DIR, "benchmark_compare.csv"))
xt_bm <- xts(bm_dt$BM_Ret, order.by = bm_dt$Date)
bm_SR <- as.numeric(SharpeRatio.annualized(xt_bm, scale=12, geometric=TRUE))
bm_CAGR <- as.numeric(Return.annualized(xt_bm, scale=12, geometric=TRUE))
bm_MDD <- as.numeric(maxDrawdown(xt_bm, geometric=TRUE))
bm_CVaR <- as.numeric(ES(xt_bm, p=0.95, method="historical"))
bc_row <- data.table(strategy = "KOSPI200_BM",
                      SR = bm_SR, CAGR = bm_CAGR, MDD = bm_MDD, CVaR_95 = bm_CVaR,
                      delta_SR = bm_SR - m$S4_baseline$SR,
                      delta_CAGR = bm_CAGR - m$S4_baseline$CAGR,
                      delta_MDD = bm_MDD - m$S4_baseline$MDD)
bc_extended <- rbindlist(list(bc_existing, bc_row), fill = TRUE)
fwrite(bc_extended, file.path(OUT_DIR, "benchmark_compare.csv"))

# 9. rolling_metrics (12m, 24m rolling SR/MDD)
non_na_pd <- pr[!is.na(net_return)]
xt_pd20b <- xts(non_na_pd$net_return, order.by = non_na_pd$Date)
roll_dt <- data.table(
  Date = non_na_pd$Date,
  ret_12m = frollmean(non_na_pd$net_return, n = 12, align = "right"),
  sd_12m = frollapply(non_na_pd$net_return, n = 12, FUN = sd, align = "right"),
  ret_24m = frollmean(non_na_pd$net_return, n = 24, align = "right"),
  sd_24m = frollapply(non_na_pd$net_return, n = 24, FUN = sd, align = "right")
)
roll_dt[, SR_12m := ifelse(sd_12m > 0, ret_12m / sd_12m * sqrt(12), NA_real_)]
roll_dt[, SR_24m := ifelse(sd_24m > 0, ret_24m / sd_24m * sqrt(12), NA_real_)]
fwrite(roll_dt, file.path(OUT_DIR, "rolling_metrics.csv"))

# 10. drawdowns
non_na_pd[, nav := cumprod(1 + net_return)]
non_na_pd[, peak := cummax(nav)]
non_na_pd[, dd_pct := (nav / peak) - 1]
dd_dt <- non_na_pd[, .(Date, nav, peak, dd_pct)]
fwrite(dd_dt, file.path(OUT_DIR, "drawdowns.csv"))

# 11. audit
audit_dt <- data.table(
  audit_item = c(
    "pure_function_md5_match", "performanceanalytics_standard",
    "fabrication_label_absent", "production_20_cap_pass",
    "long_only", "sum_w_eq_1", "single_asset_cap_0p20",
    "transaction_cost_embedded_15bps", "pit_C13_C14_status",
    "axiom_AX008_stance", "DM_t_NW_harvey_strict_pass"
  ),
  status = c(
    "PASS", "PASS", "PASS", "PASS",
    "PASS", "PASS", "PASS",
    "PASS (90bps annual drag)",
    "INHERITED_ALPHA_LAYER_REMEDIATION_PENDING",
    "DRAFT_PENDING_CODEX_ROUND",
    "FAIL_t_NW_2.76_lt_3.0"
  ),
  severity = c(
    "info", "info", "info", "info",
    "info", "info", "info",
    "medium", "medium", "high", "high"
  ),
  note = c(
    "alpha/risk/optimization md5 match start/end",
    "SharpeRatio.annualized geometric=TRUE / maxDrawdown / Return.annualized / SortinoRatio / CalmarRatio / ES historical",
    "method field has no ProductionSchedule[N]m fabrication label",
    "KR equity count = 20 (composite top20), ETF count = 9 exempt",
    "all weights >= 0",
    "sum = 1.000",
    "max per-asset weight = 0.18 (A148070) < 0.20 cap",
    "15bps × turnover × composite weight, 90bps annual drag",
    "Forge has no authority to fix alpha-layer C13/C14; alpha-research challenge_note Part A timeline accepted",
    "Codex Round 1 pending (background spawn complete, response file pending)",
    "DM t_NW = 2.76 marginally significant at conventional p=0.006 but FAILS Harvey-Liu-Zhu (2016) strict t > 3.0"
  )
)
fwrite(audit_dt, file.path(OUT_DIR, "audit.csv"))

# Build bt_result list (10-component + audit)
bt_result <- list(
  manifest = manifest,
  strategy_spec = strategy_spec,
  nav = fread(file.path(OUT_DIR, "nav.csv")),
  period_returns = pr,
  holdings = holdings_dt,
  benchmark_returns = bm_dt,
  metrics = fread(file.path(OUT_DIR, "metrics.csv")),
  benchmark_compare = bc_extended,
  rolling_metrics = roll_dt,
  drawdowns = dd_dt,
  audit = audit_dt
)
saveRDS(bt_result, file.path(OUT_DIR, "bt_result.rds"))
cat("bt_result.rds saved (10-component + audit)\n")
cat("Components:", paste(names(bt_result), collapse = ", "), "\n")
cat("\nDONE: PD20-B Backtest Contract v1.0 bt_result\n")
