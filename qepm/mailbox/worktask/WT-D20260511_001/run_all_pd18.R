#==============================================================================
# WT-D20260511_001 PD18 — Forge re-spawn 5-sleeve composite backtest
#
# Mission (도훈 mandate 2026-05-11 옵션 A):
#   PD16 supersede with NEW alpha 184 sig_dates (155 → 184, 29 new 2023-12 ~ 2026-04).
#   redistribute primary mandate (qlead_forge_primary_variant_override.json):
#     - 5-sleeve composite monthly rebal (lockbox-scope.md forge 폐기 정합)
#     - NEW sleeve: 184 sig_dates 각각 top20 EW 5% per name monthly rebal (frozen X)
#     - sleeve weights fixed (45/22.5/18/4.5/10)
#
# Variants:
#   - PRIMARY: redistribute (NEW=0 시기 4-sleeve proportional redistribute)
#       Period: 2005-02-01 ~ 2026-04-01 (255 months)
#       NEW active 2011-01 ~ 2026-04 (184 dates) + 0 outside redistribute to 4-sleeve
#
# Inputs:
#   - sleeve_returns_master.csv (4-sleeve 255m baseline: AR, KR_10y, TSMOM, Cash)
#   - new_sleeve_returns_184m_pd18.csv (NEW 184 dates monthly rebal, just built)
#
# Outputs:
#   - backtest_result_med_10pct_pd18/ (bt_result 10-component + metrics)
#   - judge_ready/backtest_summary_med_10pct_pd18.json
#   - PerformanceAnalytics standard functions only (Backtest Contract v1.0)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(zoo)
})

WT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001"
SA_DIR <- "stage_artifacts/WT_D20260511_001"

cat("=== PD18 Forge 5-sleeve composite backtest (redistribute primary) ===\n\n")

# 1. Capture 3-package md5sum (start)
md5_start <- list(
  alpha    = tools::md5sum(file.path(WT_DIR, "alpha_package.json")),
  risk     = tools::md5sum(file.path(WT_DIR, "risk_package.json")),
  opt      = tools::md5sum(file.path(WT_DIR, "optimization_package.json"))
)
cat("3-package md5sum START:\n")
cat("  alpha:", md5_start$alpha, "\n")
cat("  risk: ", md5_start$risk, "\n")
cat("  opt:  ", md5_start$opt, "\n")

# 2. Load 4-sleeve baseline returns
sm <- fread("qepm/mailbox/worktask/WT-P20260509_001/output/sleeve_returns_master.csv")
sm[, Date := as.Date(date)]
setorder(sm, Date)
cat("\n4-sleeve baseline rows:", nrow(sm), "(2005-02 ~ 2026-04)\n")

# 3. Load NEW sleeve returns (184 dates monthly rebal)
new_dt <- fread(file.path(SA_DIR, "new_sleeve_returns_184m_pd18.csv"))
new_dt[, Date := as.Date(sig_date)]
setnames(new_dt, "monthly_ret", "NEW")
new_dt <- new_dt[, .(Date, NEW)]
cat("NEW sleeve rows:", nrow(new_dt), "(184 dates 2011-01 ~ 2026-04)\n")

# Replace NA with 0 (only 2 NA = 2026-04 partial month)
new_dt[is.na(NEW), NEW := 0]

# 4. Match dates: sm has 255 dates (2005-02 ~ 2026-04), NEW has 184 (2011-01 ~ 2026-04)
# Strategy: merge by year-month (sm is monthly, NEW is sig_date monthly)
sm[, ym := format(Date, "%Y-%m")]
new_dt[, ym := format(Date, "%Y-%m")]

# 5. Merge: sm + NEW (left join on ym)
sm_new <- merge(sm, new_dt[, .(ym, NEW)], by = "ym", all.x = TRUE)
sm_new[is.na(NEW), NEW := 0]  # outside NEW active period → 0
setorder(sm_new, Date)
cat("\nmerged sleeve panel rows:", nrow(sm_new), "\n")
cat("NEW non-zero rows:", nrow(sm_new[NEW != 0]), "\n")
cat("first NEW non-zero ym:", min(sm_new[NEW != 0]$ym), "\n")
cat("last NEW non-zero ym:", max(sm_new[NEW != 0]$ym), "\n")

# 6. Compute redistribute composite (5-sleeve fixed weights)
# Sleeve weights
w_AR    <- 0.450
w_TSMOM <- 0.225
w_KR    <- 0.180
w_CASH  <- 0.045
w_NEW   <- 0.100
w_sum   <- w_AR + w_TSMOM + w_KR + w_CASH + w_NEW
stopifnot(abs(w_sum - 1.0) < 1e-9)

# Redistribute logic: NEW=0 시기 (NEW returns absent)에 NEW weight를 4-sleeve에 proportional 재분배
# When NEW != 0: full 5-sleeve weights
# When NEW == 0: redistribute 0.10 to AR/TSMOM/KR/Cash proportionally
#   Base 4-sleeve weights = 0.45/0.225/0.18/0.045 = sum 0.90
#   Redistributed: 0.45 + 0.10*(0.45/0.90) = 0.50, etc.
#   = AR 0.50, TSMOM 0.25, KR 0.20, Cash 0.05 = S4 v2 weights

# Implementation: NEW=0 시기 4-sleeve weights scale up 10/9
sm_new[, ret_5sleeve_redistribute := ifelse(
  NEW != 0,
  w_AR * AR_on_M4 + w_TSMOM * TSMOM + w_KR * KR_10y + w_CASH * Cash + w_NEW * NEW,
  (w_AR / 0.90) * AR_on_M4 + (w_TSMOM / 0.90) * TSMOM + (w_KR / 0.90) * KR_10y + (w_CASH / 0.90) * Cash
)]

# 7. Baseline S4 v2 (4-sleeve 50/25/20/5) for comparison
w_S4_AR <- 0.50; w_S4_TSMOM <- 0.25; w_S4_KR <- 0.20; w_S4_CASH <- 0.05
sm_new[, ret_S4_baseline := w_S4_AR * AR_on_M4 + w_S4_TSMOM * TSMOM + w_S4_KR * KR_10y + w_S4_CASH * Cash]

# 8. Also compute strict variant (NEW=0 outside, no redistribute) for diagnostic
sm_new[, ret_5sleeve_strict := w_AR * AR_on_M4 + w_TSMOM * TSMOM + w_KR * KR_10y + w_CASH * Cash + w_NEW * NEW]

cat("\nComposite returns range:\n")
cat("  redistribute: min/max=", range(sm_new$ret_5sleeve_redistribute), "\n")
cat("  S4 baseline:  min/max=", range(sm_new$ret_S4_baseline), "\n")

# 9. Build xts for PerformanceAnalytics
ret_redist <- xts(sm_new$ret_5sleeve_redistribute, order.by = sm_new$Date)
ret_S4     <- xts(sm_new$ret_S4_baseline, order.by = sm_new$Date)
ret_strict <- xts(sm_new$ret_5sleeve_strict, order.by = sm_new$Date)
colnames(ret_redist) <- "redistribute_pd18"
colnames(ret_S4)     <- "S4_baseline"
colnames(ret_strict) <- "strict_pd18"

# 10. PerformanceAnalytics metrics — full 255m primary
compute_metrics <- function(r, label) {
  ann_factor <- 12
  sr_ann <- as.numeric(SharpeRatio.annualized(r, Rf = 0, scale = ann_factor, geometric = TRUE))
  cagr <- as.numeric(Return.annualized(r, scale = ann_factor, geometric = TRUE))
  mdd <- as.numeric(maxDrawdown(r))
  sort_ann <- as.numeric(SortinoRatio(r, MAR = 0)) * sqrt(ann_factor)
  cvar_95 <- as.numeric(CVaR(r, p = 0.95, method = "historical"))
  cvar_99 <- as.numeric(CVaR(r, p = 0.99, method = "historical"))
  hit_rate <- mean(as.numeric(r) > 0, na.rm = TRUE)
  mean_ann <- mean(as.numeric(r), na.rm = TRUE) * ann_factor
  vol_ann <- sd(as.numeric(r), na.rm = TRUE) * sqrt(ann_factor)
  calmar <- abs(cagr / mdd)
  list(
    label = label, n_months = length(r),
    SR_ann_geom = sr_ann, CAGR = cagr, MDD = -abs(mdd),
    Sortino_ann = sort_ann, Calmar = calmar,
    CVaR_95 = -abs(cvar_95), CVaR_99 = -abs(cvar_99),
    hit_rate = hit_rate, mean_ann = mean_ann, vol_ann = vol_ann
  )
}

m_redist <- compute_metrics(ret_redist, "redistribute_pd18_primary")
m_S4     <- compute_metrics(ret_S4, "S4_baseline")
m_strict <- compute_metrics(ret_strict, "strict_pd18_diagnostic")

cat("\n=== PD18 PRIMARY: redistribute (NEW=0 outside redistribute, 184 dates monthly rebal NEW) ===\n")
cat("n_months:", m_redist$n_months, "\n")
cat("SR_ann_geometric:", round(m_redist$SR_ann_geom, 4), "\n")
cat("CAGR:", round(m_redist$CAGR, 4), "\n")
cat("MDD:", round(m_redist$MDD, 4), "\n")
cat("Sortino_ann:", round(m_redist$Sortino_ann, 4), "\n")
cat("Calmar:", round(m_redist$Calmar, 4), "\n")
cat("CVaR_95:", round(m_redist$CVaR_95, 4), "\n")
cat("CVaR_99:", round(m_redist$CVaR_99, 4), "\n")
cat("hit_rate:", round(m_redist$hit_rate, 4), "\n")

cat("\n=== S4 v2 baseline (4-sleeve 50/25/20/5) ===\n")
cat("SR:", round(m_S4$SR_ann_geom, 4), " CAGR:", round(m_S4$CAGR, 4),
    " MDD:", round(m_S4$MDD, 4), " CVaR_95:", round(m_S4$CVaR_95, 4), "\n")

cat("\n=== strict variant (NEW=0 outside, no redistribute) — diagnostic ===\n")
cat("SR:", round(m_strict$SR_ann_geom, 4), " CAGR:", round(m_strict$CAGR, 4),
    " MDD:", round(m_strict$MDD, 4), " CVaR_95:", round(m_strict$CVaR_95, 4), "\n")

# 11. 4-axis strict improve check vs S4 v2 baseline
# S4 v2 documented baseline (WT-P20260509_001 PG2 admit Charter v1.7 §10)
S4_doc <- list(SR = 1.8334, CAGR = 0.2020, MDD = -0.1252, CVaR_95 = -0.0501)

axis_check <- list(
  SR_delta = m_redist$SR_ann_geom - S4_doc$SR,
  CAGR_delta_pp = (m_redist$CAGR - S4_doc$CAGR) * 100,
  MDD_delta_pp = (abs(S4_doc$MDD) - abs(m_redist$MDD)) * 100,  # better if reduction
  CVaR_delta_pp = (abs(S4_doc$CVaR_95) - abs(m_redist$CVaR_95)) * 100,
  SR_pass = m_redist$SR_ann_geom > S4_doc$SR,
  CAGR_pass = m_redist$CAGR > S4_doc$CAGR,
  MDD_pass = abs(m_redist$MDD) < abs(S4_doc$MDD),
  CVaR_pass = abs(m_redist$CVaR_95) < abs(S4_doc$CVaR_95)
)
axis_check$n_pass <- sum(unlist(axis_check[c("SR_pass", "CAGR_pass", "MDD_pass", "CVaR_pass")]))
axis_check$verdict <- if (axis_check$n_pass == 4) "4_PASS_STRICT_IMPROVE" else
                       sprintf("%d_PASS_%d_FAIL", axis_check$n_pass, 4 - axis_check$n_pass)

cat("\n=== 4-axis Strict Improve vs S4 v2 baseline (documented 1.83/20.20/-12.52/-5.01) ===\n")
cat("SR:    ", round(axis_check$SR_delta, 4), " | PASS:", axis_check$SR_pass, "\n")
cat("CAGR:  ", round(axis_check$CAGR_delta_pp, 4), "pp | PASS:", axis_check$CAGR_pass, "\n")
cat("MDD:   ", round(axis_check$MDD_delta_pp, 4), "pp | PASS:", axis_check$MDD_pass, "\n")
cat("CVaR:  ", round(axis_check$CVaR_delta_pp, 4), "pp | PASS:", axis_check$CVaR_pass, "\n")
cat("Verdict:", axis_check$verdict, "\n")

# 12. Diebold-Mariano test vs S4 v2 baseline (Newey-West HAC lag 6)
diff_redist <- as.numeric(ret_redist) - as.numeric(ret_S4)
n <- length(diff_redist)
mean_diff <- mean(diff_redist)

# NW HAC lag 6 standard error
nw_se <- function(x, lag = 6) {
  n <- length(x)
  x_dm <- x - mean(x)
  gamma_0 <- mean(x_dm^2)
  s2 <- gamma_0
  for (k in 1:lag) {
    w_k <- 1 - k / (lag + 1)
    gamma_k <- mean(x_dm[-(1:k)] * x_dm[-((n - k + 1):n)])
    s2 <- s2 + 2 * w_k * gamma_k
  }
  sqrt(s2 / n)
}
se_nw <- nw_se(diff_redist, lag = 6)
t_NW <- mean_diff / se_nw
p_val <- 2 * (1 - pnorm(abs(t_NW)))

cat("\n=== Diebold-Mariano test (PD18 redistribute vs S4 v2 baseline, NW HAC lag 6) ===\n")
cat("n_months:", n, "\n")
cat("mean_diff_monthly:", round(mean_diff, 6), "\n")
cat("se_NW_lag6:", round(se_nw, 6), "\n")
cat("t_NW:", round(t_NW, 4), "\n")
cat("p:", round(p_val, 4), "\n")
dm_interp <- if (abs(t_NW) > 2) {
  if (mean_diff > 0) "redistribute outperforms baseline significantly" else "baseline outperforms redistribute significantly"
} else {
  "statistically equivalent (NS)"
}
cat("interpretation:", dm_interp, "\n")

# 13. Sub-period analysis: alpha-active 184m (2011-01 ~ 2026-04) vs OOS-relevant subperiod
sm_new[, in_alpha_period := (Date >= as.Date("2011-01-01") & Date <= as.Date("2026-04-30"))]
sm_new_alpha <- sm_new[in_alpha_period == TRUE]
ret_redist_alpha <- xts(sm_new_alpha$ret_5sleeve_redistribute, order.by = sm_new_alpha$Date)
ret_S4_alpha <- xts(sm_new_alpha$ret_S4_baseline, order.by = sm_new_alpha$Date)
m_redist_alpha <- compute_metrics(ret_redist_alpha, "redistribute_alpha_active")
m_S4_alpha <- compute_metrics(ret_S4_alpha, "S4_alpha_active")

cat("\n=== Sub-period: alpha-active (2011-01 ~ 2026-04, NEW non-zero) ===\n")
cat("redistribute alpha-active SR:", round(m_redist_alpha$SR_ann_geom, 4),
    " CAGR:", round(m_redist_alpha$CAGR, 4),
    " MDD:", round(m_redist_alpha$MDD, 4), "\n")
cat("S4 baseline alpha-active SR:", round(m_S4_alpha$SR_ann_geom, 4),
    " CAGR:", round(m_S4_alpha$CAGR, 4),
    " MDD:", round(m_S4_alpha$MDD, 4), "\n")

# 14. PD13 extension sub-period (2024-01 ~ 2026-04, alpha 29 new dates)
sm_new_pd13 <- sm_new[Date >= as.Date("2024-01-01") & Date <= as.Date("2026-04-30")]
ret_redist_pd13 <- xts(sm_new_pd13$ret_5sleeve_redistribute, order.by = sm_new_pd13$Date)
ret_S4_pd13 <- xts(sm_new_pd13$ret_S4_baseline, order.by = sm_new_pd13$Date)
m_redist_pd13 <- compute_metrics(ret_redist_pd13, "redistribute_pd13_extension")
m_S4_pd13 <- compute_metrics(ret_S4_pd13, "S4_pd13_extension")

cat("\n=== Sub-period: PD13 extension (2024-01 ~ 2026-04, alpha 29 new dates monthly rebal) ===\n")
cat("redistribute PD13 SR:", round(m_redist_pd13$SR_ann_geom, 4),
    " CAGR:", round(m_redist_pd13$CAGR, 4),
    " MDD:", round(m_redist_pd13$MDD, 4),
    " n:", m_redist_pd13$n_months, "\n")
cat("S4 baseline PD13 SR:", round(m_S4_pd13$SR_ann_geom, 4),
    " CAGR:", round(m_S4_pd13$CAGR, 4),
    " MDD:", round(m_S4_pd13$MDD, 4), "\n")

# 15. Save all metrics + audit
out_dir <- file.path(WT_DIR, "backtest_result_med_10pct_pd18")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# Composite returns CSV
sm_save <- sm_new[, .(Date, ym, AR_on_M4, TSMOM, KR_10y, Cash, NEW,
                       ret_5sleeve_redistribute, ret_5sleeve_strict, ret_S4_baseline)]
fwrite(sm_save, file.path(out_dir, "composite_returns_5sleeve_pd18.csv"))
cat("\ncomposite returns saved:", file.path(out_dir, "composite_returns_5sleeve_pd18.csv"), "\n")

# Metrics summary RDS for downstream
metrics_pkg <- list(
  primary_redistribute_256m = m_redist,
  baseline_S4_documented = S4_doc,
  baseline_S4_realized_256m = m_S4,
  diagnostic_strict_256m = m_strict,
  alpha_active_184m_redist = m_redist_alpha,
  alpha_active_184m_S4 = m_S4_alpha,
  pd13_extension_29m_redist = m_redist_pd13,
  pd13_extension_29m_S4 = m_S4_pd13,
  axis_check = axis_check,
  dm_test = list(t_NW = t_NW, p = p_val, mean_diff = mean_diff,
                 se_NW = se_nw, interpretation = dm_interp)
)
saveRDS(metrics_pkg, file.path(out_dir, "metrics_pd18.rds"))
cat("metrics RDS saved\n")

# 16. md5sum end (Pure function audit)
md5_end <- list(
  alpha    = tools::md5sum(file.path(WT_DIR, "alpha_package.json")),
  risk     = tools::md5sum(file.path(WT_DIR, "risk_package.json")),
  opt      = tools::md5sum(file.path(WT_DIR, "optimization_package.json"))
)
audit_pure <- list(
  alpha_match = (md5_start$alpha == md5_end$alpha),
  risk_match  = (md5_start$risk == md5_end$risk),
  opt_match   = (md5_start$opt == md5_end$opt),
  alpha_md5_start = unname(md5_start$alpha),
  alpha_md5_end = unname(md5_end$alpha),
  risk_md5_start = unname(md5_start$risk),
  risk_md5_end = unname(md5_end$risk),
  opt_md5_start = unname(md5_start$opt),
  opt_md5_end = unname(md5_end$opt)
)
cat("\nPure function audit:\n")
cat("  alpha match:", audit_pure$alpha_match, "\n")
cat("  risk match: ", audit_pure$risk_match, "\n")
cat("  opt match:  ", audit_pure$opt_match, "\n")

saveRDS(audit_pure, file.path(out_dir, "pure_function_audit.rds"))

# 17. Print PD16 comparison
cat("\n=== PD16 vs PD18 comparison ===\n")
cat("PD16 redistribute SR (frozen alpha 155 dates base):  1.9065\n")
cat("PD18 redistribute SR (alpha 184 dates monthly rebal):", round(m_redist$SR_ann_geom, 4), "\n")
cat("Delta SR:", round(m_redist$SR_ann_geom - 1.9065, 4), "\n")
cat("\nPD16 redistribute CAGR: 0.2048\n")
cat("PD18 redistribute CAGR:", round(m_redist$CAGR, 4), "\n")
cat("Delta CAGR pp:", round((m_redist$CAGR - 0.2048) * 100, 4), "\n")
cat("\nPD16 redistribute MDD: -0.1154\n")
cat("PD18 redistribute MDD:", round(m_redist$MDD, 4), "\n")
cat("Delta MDD pp:", round((abs(0.1154) - abs(m_redist$MDD)) * 100, 4), "\n")

cat("\nDONE: PD18 backtest complete\n")
