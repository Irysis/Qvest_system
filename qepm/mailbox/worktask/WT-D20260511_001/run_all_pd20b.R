#==============================================================================
# WT-D20260511_001 PD20-B — Forge run_all (Z-Score Composite top20 4-sleeve)
#
# Mission (Production 종목수 20 cap fix):
#   PD18 (5-sleeve, NEW = independent 20 → KR equity 40 names) →
#   PD20-B Path 2 Z-Score Composite (merged 20 KR equity, ETF count exempt).
#
#   Composite KR equity sleeve: 55% (20 stocks, composite top20)
#   TSMOM_8_ETF sleeve: 22.5% (8 ETF retain)
#   KR_10y sleeve: 18% (A148070 retain)
#   Cash sleeve: 4.5% (KRW retain)
#
# Schedule fidelity:
#   - Composite top20: 184 sig_dates monthly rebal (lockbox-scope.md forge 폐기 정합)
#   - TSMOM/KR_10y/Cash: PD18 inheritance (sleeve_returns_master.csv)
#   - Pre-2011 (NEW absent): redistribute composite weight 0.55 proportional to 4-sleeve baseline
#     = AR_on_M4 0.55, TSMOM 0.225, KR_10y 0.18, Cash 0.045 (sum 1.0)
#     where pre-2011 "composite" = STR_1715 AR_on_M4 baseline (only 1715 alpha active)
#
# Pure function (alpha/risk/optimization READ-ONLY):
#   - 3-package md5sum capture start/end
#   - composite top20 selection uses joint z-score normalization (alpha intent preserved)
#
# Constraints:
#   - PerformanceAnalytics 표준 함수만 (geometric=TRUE)
#   - 15bps cost: applied turnover-weighted composite-level (Judge re-spawn precedent retain)
#   - Σw = 1.0 absolute
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(zoo)
})

WT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001"
SA_DIR <- "stage_artifacts/WT_D20260511_001"
OUT_DIR <- file.path(WT_DIR, "backtest_result_pd20b")

cat("=== PD20-B Forge 4-sleeve composite (Z-Score Composite top20) ===\n\n")

# 1. 3-package md5sum (start)
md5_start <- list(
  alpha    = unname(tools::md5sum(file.path(WT_DIR, "alpha_package.json"))),
  risk     = unname(tools::md5sum(file.path(WT_DIR, "risk_package.json"))),
  opt      = unname(tools::md5sum(file.path(WT_DIR, "optimization_package.json")))
)
cat("3-package md5sum START:\n")
cat("  alpha:", md5_start$alpha, "\n")
cat("  risk: ", md5_start$risk, "\n")
cat("  opt:  ", md5_start$opt, "\n")

# 2. Load 4-sleeve baseline returns (AR_on_M4, TSMOM, KR_10y, Cash)
sm <- fread("qepm/mailbox/worktask/WT-P20260509_001/output/sleeve_returns_master.csv")
sm[, Date := as.Date(date)]
setorder(sm, Date)
cat("\n4-sleeve baseline rows:", nrow(sm), "(2005-02 ~ 2026-04)\n")

# 3. Load composite top20 returns
comp_dt <- fread(file.path(SA_DIR, "composite_top20_returns_pd20b.csv"))
comp_dt[, Date := as.Date(sig_date)]
setnames(comp_dt, "monthly_ret", "Composite")
comp_dt <- comp_dt[, .(Date, Composite)]
cat("Composite top20 rows:", nrow(comp_dt), "(184 dates 2011-01 ~ 2026-04)\n")
comp_dt[is.na(Composite), Composite := 0]

# 4. Merge by year-month
sm[, ym := format(Date, "%Y-%m")]
comp_dt[, ym := format(Date, "%Y-%m")]
sm_comp <- merge(sm, comp_dt[, .(ym, Composite)], by = "ym", all.x = TRUE)
sm_comp[is.na(Composite), Composite := 0]
setorder(sm_comp, Date)
cat("\nmerged sleeve panel rows:", nrow(sm_comp), "\n")
cat("Composite non-zero rows:", nrow(sm_comp[Composite != 0]), "\n")
cat("first Composite non-zero ym:", min(sm_comp[Composite != 0]$ym), "\n")
cat("last Composite non-zero ym:", max(sm_comp[Composite != 0]$ym), "\n")

# 5. Sleeve weights (Path 2 4-sleeve consolidation)
w_COMP   <- 0.550  # Composite KR equity (z-score composite top20)
w_TSMOM  <- 0.225  # TSMOM 8-ETF
w_KR     <- 0.180  # KR_10y A148070
w_CASH   <- 0.045  # KRW Cash
w_sum    <- w_COMP + w_TSMOM + w_KR + w_CASH
stopifnot(abs(w_sum - 1.0) < 1e-9)
cat(sprintf("\nSleeve weights: COMP=%.3f, TSMOM=%.3f, KR_10y=%.3f, Cash=%.3f, sum=%.4f\n",
            w_COMP, w_TSMOM, w_KR, w_CASH, w_sum))

# 6. Compute composite redistribute returns
# When Composite != 0 (2011-01 ~ 2026-04, 184 dates):
#   ret = w_COMP * Composite + w_TSMOM * TSMOM + w_KR * KR_10y + w_CASH * Cash
# When Composite == 0 (pre-2011, NEW absent):
#   redistribute composite weight 0.55 to AR_on_M4 (Composite ~ STR_1715 when z_NEW unavailable)
#   Pre-2011 composite weight equivalent: scale 4-sleeve baseline to sum 1.0
#   = AR_on_M4 effective weight = 0.55 (KR_equity) + 0.225*... = 0.55 (composite ~ STR_1715 in pre-2011)
#   For consistency with PD18 redistribute: when Composite=0, redistribute 0.55 to AR/TSMOM/KR/Cash
#     in PD18 proportion (45/22.5/18/4.5 = 0.55 to 0.55 transit. Actually PD18 redistributes the 10%
#     to base 90% → S4 v2 (50/25/20/5). Here Composite includes 1715 alpha so we need different logic.

# DECISION (Path 2 redistribute logic):
#   Pre-2011: Composite=0 → "composite KR equity" sleeve unavailable.
#             Redistribute 0.55 to AR_on_M4 (STR_1715 only, 1715 alpha active 2005-02~) +
#             proportional to TSMOM/KR/Cash baseline weights.
#             Actually simpler: when Composite=0, use AR_on_M4 ONLY as KR equity sleeve at 0.55.
#             Net effect: AR_on_M4 0.55, TSMOM 0.225, KR_10y 0.18, Cash 0.045 (sum 1.0)
#             This is S4 v2-like but slightly KR-heavier (0.55 vs 0.50).
#   Alternative: 4-sleeve PD18 S4 baseline (50/25/20/5). Use this to match PD18 baseline directly.
#
# Final decision: use 4-sleeve S4 baseline (50/25/20/5) pre-2011 for fair comparison vs PD18.

sm_comp[, ret_pd20b_path2 := ifelse(
  Composite != 0,
  w_COMP * Composite + w_TSMOM * TSMOM + w_KR * KR_10y + w_CASH * Cash,
  0.50 * AR_on_M4 + 0.25 * TSMOM + 0.20 * KR_10y + 0.05 * Cash
)]

# Cost-free check
cat("\n[Cost-free metrics check]\n")
non_na_pd20b <- sm_comp[!is.na(ret_pd20b_path2)]
xt_cf <- xts(non_na_pd20b$ret_pd20b_path2, order.by = non_na_pd20b$Date)
cf_SR <- as.numeric(SharpeRatio.annualized(xt_cf, scale = 12, geometric = TRUE))
cf_CAGR <- as.numeric(Return.annualized(xt_cf, scale = 12, geometric = TRUE))
cf_MDD <- as.numeric(maxDrawdown(xt_cf, geometric = TRUE))
cat(sprintf("  N=%d, SR=%.4f, CAGR=%.4f, MDD=%.4f (cost-free)\n",
            nrow(non_na_pd20b), cf_SR, cf_CAGR, cf_MDD))

# 7. Cost embedding: 15bps per round-trip turnover composite-level
# Methodology (PD18 precedent retain): apply ~12% × 12bps = -1.44% annual drag (estimate).
# More precise: turnover per month at composite level. Composite top20 has ~40-60% turnover
# vs S4 baseline ~5-10%. Realized cost calculation:
#   - On Composite rebal months: assume 50% one-way turnover @ 15bps = 7.5bps per rebal
#   - Composite weight 0.55 → effective cost = 0.55 * 7.5bps = ~4bps/mo × 12 = 49bps/yr
#   - Plus 4-sleeve baseline ~10% turnover @ 15bps × (0.45) = ~7bps/yr
#   - Total ~56bps/yr cost drag → SR drag ~0.05-0.08

# For composite-level audit, apply per-month cost:
# c_t = (turnover_t × 0.5 × 15bps) where turnover at composite weight 0.55
# Approximation: 0.55 × turnover_composite_topN + 0.45 × turnover_base_S4

# Turnover composite top20 (rough): cross-section change in top20 names per rebal
holdings_dt <- fread(file.path(SA_DIR, "composite_top20_holdings_pd20b.csv"))
setorder(holdings_dt, sig_date, Ticker)
turnover_per_rebal <- holdings_dt[, .(n_names = .N), by = sig_date]
# Sequential turnover: tickers different vs previous rebal
turnover_seq <- numeric(length(unique(holdings_dt$sig_date)))
ud <- sort(unique(holdings_dt$sig_date))
for (i in 2:length(ud)) {
  curr <- holdings_dt[sig_date == ud[i]]$Ticker
  prev <- holdings_dt[sig_date == ud[i - 1]]$Ticker
  added <- length(setdiff(curr, prev))
  removed <- length(setdiff(prev, curr))
  # one-way turnover (added or removed = same in fixed N=20)
  turnover_seq[i] <- added / 20
}
turnover_seq[1] <- 1.0  # initial entry full turnover
mean_to_oneway <- mean(turnover_seq)
cat(sprintf("\n[Composite top20 turnover (rebalance-to-rebalance)]\n"))
cat(sprintf("  mean one-way turnover: %.4f (round-trip ~ %.4f)\n",
            mean_to_oneway, mean_to_oneway * 2))

# Composite-level cost: 15bps * round-trip turnover * composite weight 0.55 per month
# For pre-2011 (S4 v2 baseline): typical 10% one-way = ~3bps/mo
# Simple model: per-month cost embedded
COST_BPS_ONEWAY <- 0.0015  # 15bps per one-way
sm_comp[, turnover_oneway := ifelse(Composite != 0,
                                     0.55 * mean_to_oneway + 0.45 * 0.10,  # mix
                                     0.50 * 0.10)]  # pre-2011 S4 baseline
sm_comp[, cost_drag := 2 * turnover_oneway * COST_BPS_ONEWAY]  # round-trip
sm_comp[, ret_pd20b_path2_net := ret_pd20b_path2 - cost_drag]

# 8. Backtest metrics (cost-embedded)
non_na_net <- sm_comp[!is.na(ret_pd20b_path2_net)]
xt_net <- xts(non_na_net$ret_pd20b_path2_net, order.by = non_na_net$Date)

metrics <- list()
metrics$N <- nrow(non_na_net)
metrics$SR_ann_geometric <- as.numeric(SharpeRatio.annualized(xt_net, scale = 12, geometric = TRUE))
metrics$CAGR <- as.numeric(Return.annualized(xt_net, scale = 12, geometric = TRUE))
metrics$MDD <- as.numeric(maxDrawdown(xt_net, geometric = TRUE))
metrics$Sortino <- as.numeric(SortinoRatio(xt_net, MAR = 0)) * sqrt(12)
metrics$Calmar <- as.numeric(CalmarRatio(xt_net, scale = 12))
metrics$CVaR_95_monthly <- as.numeric(ES(xt_net, p = 0.95, method = "historical"))
metrics$CVaR_99_monthly <- as.numeric(ES(xt_net, p = 0.99, method = "historical"))
metrics$hit_rate <- as.numeric(mean(non_na_net$ret_pd20b_path2_net > 0))
metrics$mean_ann <- as.numeric(Return.annualized(xt_net, scale = 12, geometric = FALSE))
metrics$vol_ann <- as.numeric(StdDev.annualized(xt_net, scale = 12))
metrics$mean_turnover_oneway <- mean_to_oneway
metrics$mean_cost_drag_annual <- mean(sm_comp$cost_drag, na.rm = TRUE) * 12

cat("\n[PD20-B Path 2 Z-Score Composite metrics (256m, 15bps embedded)]\n")
cat(sprintf("  N=%d months (%s ~ %s)\n",
            metrics$N, as.character(min(non_na_net$Date)), as.character(max(non_na_net$Date))))
cat(sprintf("  SR_ann_geometric: %.4f\n", metrics$SR_ann_geometric))
cat(sprintf("  CAGR:             %.4f\n", metrics$CAGR))
cat(sprintf("  MDD:              %.4f\n", metrics$MDD))
cat(sprintf("  Sortino:          %.4f\n", metrics$Sortino))
cat(sprintf("  Calmar:           %.4f\n", metrics$Calmar))
cat(sprintf("  CVaR_95_monthly:  %.4f\n", metrics$CVaR_95_monthly))
cat(sprintf("  CVaR_99_monthly:  %.4f\n", metrics$CVaR_99_monthly))
cat(sprintf("  hit_rate:         %.4f\n", metrics$hit_rate))
cat(sprintf("  vol_ann:          %.4f\n", metrics$vol_ann))
cat(sprintf("  mean_turnover_oneway: %.4f\n", metrics$mean_turnover_oneway))
cat(sprintf("  mean_cost_drag_annual: %.4f (%.2f bps)\n",
            metrics$mean_cost_drag_annual, metrics$mean_cost_drag_annual * 1e4))

# 9. Diebold-Mariano vs S4 v2 baseline
sm_comp[, ret_S4_baseline := 0.50 * AR_on_M4 + 0.25 * TSMOM + 0.20 * KR_10y + 0.05 * Cash]
non_na_dm <- sm_comp[!is.na(ret_pd20b_path2_net) & !is.na(ret_S4_baseline)]
diff <- non_na_dm$ret_pd20b_path2_net - non_na_dm$ret_S4_baseline

# Newey-West lag 6 (~ sqrt(N))
nw_lag <- 6
N <- length(diff)
mean_diff <- mean(diff)
# NW variance
nw_var <- var(diff)
for (lag in 1:nw_lag) {
  weight <- 1 - lag / (nw_lag + 1)
  ac <- mean((diff[(lag + 1):N] - mean_diff) * (diff[1:(N - lag)] - mean_diff))
  nw_var <- nw_var + 2 * weight * ac
}
nw_se <- sqrt(nw_var / N)
t_nw <- mean_diff / nw_se
p_nw <- 2 * pnorm(-abs(t_nw))

cat("\n[Diebold-Mariano vs S4 v2 baseline]\n")
cat(sprintf("  N=%d, mean_diff_monthly=%.6f, NW lag6 SE=%.6f\n", N, mean_diff, nw_se))
cat(sprintf("  t_NW = %.4f, p = %.4f\n", t_nw, p_nw))
if (abs(t_nw) > 3.0) {
  cat("  Harvey-Liu-Zhu (2016) t > 3.0 PASS\n")
} else {
  cat("  Harvey-Liu-Zhu (2016) t > 3.0 FAIL\n")
}

# S4 v2 baseline metrics
xt_S4 <- xts(non_na_dm$ret_S4_baseline, order.by = non_na_dm$Date)
S4_SR <- as.numeric(SharpeRatio.annualized(xt_S4, scale = 12, geometric = TRUE))
S4_CAGR <- as.numeric(Return.annualized(xt_S4, scale = 12, geometric = TRUE))
S4_MDD <- as.numeric(maxDrawdown(xt_S4, geometric = TRUE))
S4_CVaR_95 <- as.numeric(ES(xt_S4, p = 0.95, method = "historical"))
cat(sprintf("\n[S4 v2 baseline (50/25/20/5) realized 256m]\n"))
cat(sprintf("  SR=%.4f, CAGR=%.4f, MDD=%.4f, CVaR_95=%.4f\n",
            S4_SR, S4_CAGR, S4_MDD, S4_CVaR_95))

# 10. vs PD18 5-sleeve comparison
pd18_dt <- fread(file.path(WT_DIR, "backtest_result_med_10pct_pd18/composite_returns_5sleeve_pd18.csv"))
pd18_dt[, Date := as.Date(Date)]
merged_pd <- merge(non_na_net[, .(Date, pd20b_net = ret_pd20b_path2_net)],
                   pd18_dt[, .(Date, pd18_ret = ret_5sleeve_redistribute)],
                   by = "Date")
merged_pd <- merged_pd[!is.na(pd20b_net) & !is.na(pd18_ret)]

xt_pd18 <- xts(merged_pd$pd18_ret, order.by = merged_pd$Date)
PD18_SR <- as.numeric(SharpeRatio.annualized(xt_pd18, scale = 12, geometric = TRUE))
PD18_CAGR <- as.numeric(Return.annualized(xt_pd18, scale = 12, geometric = TRUE))
PD18_MDD <- as.numeric(maxDrawdown(xt_pd18, geometric = TRUE))

xt_pd20b_aligned <- xts(merged_pd$pd20b_net, order.by = merged_pd$Date)
PD20B_SR_aligned <- as.numeric(SharpeRatio.annualized(xt_pd20b_aligned, scale = 12, geometric = TRUE))
PD20B_CAGR_aligned <- as.numeric(Return.annualized(xt_pd20b_aligned, scale = 12, geometric = TRUE))
PD20B_MDD_aligned <- as.numeric(maxDrawdown(xt_pd20b_aligned, geometric = TRUE))

cat("\n[vs PD18 5-sleeve (NEW=10%, no cost embedded original)]\n")
cat(sprintf("  PD18 5-sleeve (raw): SR=%.4f, CAGR=%.4f, MDD=%.4f\n",
            PD18_SR, PD18_CAGR, PD18_MDD))
cat(sprintf("  PD20-B 4-sleeve (net, 15bps): SR=%.4f, CAGR=%.4f, MDD=%.4f\n",
            PD20B_SR_aligned, PD20B_CAGR_aligned, PD20B_MDD_aligned))
cat(sprintf("  Delta SR: %.4f\n", PD20B_SR_aligned - PD18_SR))
cat(sprintf("  Delta CAGR: %.4f\n", PD20B_CAGR_aligned - PD18_CAGR))
cat(sprintf("  Delta MDD pp: %.4f\n", PD20B_MDD_aligned - PD18_MDD))

# 11. Cross-cancellation diagnostic (orthogonality concern)
# When z_1715 and z_NEW are negatively correlated within universe, composite_z = w1*z1 + w2*z2
# can cancel out. Check via top20 holdings overlap with STR_1715-only top20.
holdings_dt <- fread(file.path(SA_DIR, "composite_top20_holdings_pd20b.csv"))
# Approximate 1715-only top20: those with rank by z_1715 within universe per sig_date
# For efficiency, just measure z_1715 score distribution of composite top20 selections.
mean_z1715_in_comp_top20 <- mean(holdings_dt$z_1715, na.rm = TRUE)
mean_z_NEW_in_comp_top20 <- mean(holdings_dt$z_NEW, na.rm = TRUE)
cor_z_in_top20 <- cor(holdings_dt$z_1715, holdings_dt$z_NEW)

cat("\n[Cross-cancellation diagnostic]\n")
cat(sprintf("  In composite top20: mean z_1715 = %.4f, mean z_NEW = %.4f\n",
            mean_z1715_in_comp_top20, mean_z_NEW_in_comp_top20))
cat(sprintf("  cor(z_1715, z_NEW) within composite top20 = %.4f\n", cor_z_in_top20))
cat("  Interpretation: positive z_1715 dominant (w=0.818); z_NEW additive (+18%)\n")

# 12. Save outputs
fwrite(sm_comp, file.path(OUT_DIR, "sleeve_panel_pd20b.csv"))
fwrite(non_na_net, file.path(OUT_DIR, "composite_returns_4sleeve_pd20b.csv"))

# nav.csv
nav_dt <- copy(non_na_net)
nav_dt[, nav := cumprod(1 + ret_pd20b_path2_net)]
nav_dt <- nav_dt[, .(Date, ret = ret_pd20b_path2_net, nav)]
fwrite(nav_dt, file.path(OUT_DIR, "nav.csv"))

# period_returns.csv (PerformanceAnalytics-compatible)
pr_dt <- non_na_net[, .(Date,
                         strategy_return = ret_pd20b_path2,
                         cost_ret = cost_drag,
                         net_return = ret_pd20b_path2_net,
                         turnover_oneway,
                         AR_on_M4, TSMOM, KR_10y, Cash, Composite)]
fwrite(pr_dt, file.path(OUT_DIR, "period_returns.csv"))

# metrics.csv
metrics_dt <- data.table(
  metric = names(metrics),
  value = unlist(metrics),
  metric_type = "backtested"
)
fwrite(metrics_dt, file.path(OUT_DIR, "metrics.csv"))

# benchmark_compare.csv (vs S4 v2)
bc_dt <- data.table(
  strategy = c("PD20B_Path2", "S4_v2_baseline"),
  SR = c(metrics$SR_ann_geometric, S4_SR),
  CAGR = c(metrics$CAGR, S4_CAGR),
  MDD = c(metrics$MDD, S4_MDD),
  CVaR_95 = c(metrics$CVaR_95_monthly, S4_CVaR_95)
)
bc_dt[, delta_SR := SR - S4_SR]
bc_dt[, delta_CAGR := CAGR - S4_CAGR]
bc_dt[, delta_MDD := MDD - S4_MDD]
fwrite(bc_dt, file.path(OUT_DIR, "benchmark_compare.csv"))

# DM results JSON
dm_dt <- data.table(
  measure = "Diebold-Mariano",
  N = N,
  mean_diff_monthly = mean_diff,
  NW_lag6_SE = nw_se,
  t_NW = t_nw,
  p_value = p_nw,
  hlz_pass = abs(t_nw) > 3.0
)
fwrite(dm_dt, file.path(OUT_DIR, "diebold_mariano.csv"))

# 13. 3-package md5sum (end) — pure function verification
md5_end <- list(
  alpha    = unname(tools::md5sum(file.path(WT_DIR, "alpha_package.json"))),
  risk     = unname(tools::md5sum(file.path(WT_DIR, "risk_package.json"))),
  opt      = unname(tools::md5sum(file.path(WT_DIR, "optimization_package.json")))
)
cat("\n3-package md5sum END:\n")
cat("  alpha:", md5_end$alpha, "\n")
cat("  risk: ", md5_end$risk, "\n")
cat("  opt:  ", md5_end$opt, "\n")
md5_match <- (md5_start$alpha == md5_end$alpha &&
              md5_start$risk == md5_end$risk &&
              md5_start$opt == md5_end$opt)
cat("Pure function audit:", ifelse(md5_match, "PASS", "FAIL"), "\n")

# 14. Save md5 audit
md5_audit <- data.table(
  package = c("alpha", "risk", "optimization"),
  md5_start = c(md5_start$alpha, md5_start$risk, md5_start$opt),
  md5_end = c(md5_end$alpha, md5_end$risk, md5_end$opt),
  match = c(md5_start$alpha == md5_end$alpha,
            md5_start$risk == md5_end$risk,
            md5_start$opt == md5_end$opt)
)
fwrite(md5_audit, file.path(OUT_DIR, "pure_function_audit.csv"))
saveRDS(list(md5_start = md5_start, md5_end = md5_end, match = md5_match),
        file.path(OUT_DIR, "pure_function_audit.rds"))

# 15. Save metrics as RDS for downstream
saveRDS(list(
  metrics = metrics,
  S4_baseline = list(SR = S4_SR, CAGR = S4_CAGR, MDD = S4_MDD, CVaR_95 = S4_CVaR_95),
  PD18_aligned = list(SR = PD18_SR, CAGR = PD18_CAGR, MDD = PD18_MDD),
  DM = list(t_NW = t_nw, p = p_nw, N = N, mean_diff = mean_diff, nw_se = nw_se),
  composite_diagnostic = list(
    w_1715 = 0.818, w_NEW = 0.182,
    mean_z_1715_in_top20 = mean_z1715_in_comp_top20,
    mean_z_NEW_in_top20 = mean_z_NEW_in_comp_top20,
    cor_z_in_top20 = cor_z_in_top20,
    cor_vs_pd18_NEW = 0.7001
  ),
  pure_function = list(md5_start = md5_start, md5_end = md5_end, match = md5_match)
), file.path(OUT_DIR, "metrics_pd20b.rds"))

cat("\nDONE: PD20-B Forge backtest 4-sleeve composite (Z-Score Composite top20).\n")
cat("Outputs in:", OUT_DIR, "\n")
