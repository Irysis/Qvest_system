#==============================================================================
# WT-D20260511_001 PD20-A Path 1 — 5-sleeve composite backtest
#
# Mission (도훈 mandate 2026-05-11 KST PD20-A):
#   Production Constraints 종목수 max 20 정합화.
#   Path 1 (sleeve-weighted top-N):
#     - STR_1715 H1 sleeve weight 45% × sleeve internal top16 EW
#     - NEW Vol/Skew sleeve weight 10% × sleeve internal top4 EW
#     - TSMOM (22.5%), KR_10y (18%), Cash (4.5%) inherit
#     - Aggregate KR equity 16 + 4 = 20 (= 20 cap PASS)
#
# Variants:
#   - PRIMARY: redistribute (NEW=0 시기 4-sleeve proportional redistribute = S4 v2)
#   - DIAGNOSTIC: strict (NEW=0 outside, no redistribute)
#
# Cost embedding:
#   PD18 inherit issue (turnover/cost embedding deferred to Judge)
#   Path 1 = cost-free primary + cost-embedded variant (15bps × turnover) 정량
#
# Outputs:
#   - qepm/mailbox/worktask/WT-D20260511_001/backtest_result_pd20a_path1/
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(zoo)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260511_001")
SA_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260511_001")

cat("=== PD20-A Path 1 — 5-sleeve composite backtest (1715 top16 + NEW top4) ===\n\n")

# 1. md5sum start
md5_start <- list(
  alpha = tools::md5sum(file.path(WT_DIR, "alpha_package.json")),
  risk  = tools::md5sum(file.path(WT_DIR, "risk_package.json")),
  opt   = tools::md5sum(file.path(WT_DIR, "optimization_package.json"))
)
cat("3-package md5sum START:\n")
cat("  alpha:", md5_start$alpha, "\n")
cat("  risk: ", md5_start$risk, "\n")
cat("  opt:  ", md5_start$opt, "\n\n")

# 2. Load 4-sleeve baseline (TSMOM, KR_10y, Cash retain; AR_on_M4 will be replaced by top16)
sm <- fread(file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-P20260509_001/output/sleeve_returns_master.csv"))
sm[, Date := as.Date(date)]
setorder(sm, Date)
cat("4-sleeve master rows:", nrow(sm), "(2005-02 ~ 2026-04)\n")

# 3. Load 1715 top16 EW returns (Path 1) — replace AR_on_M4
str1715_top16 <- fread(file.path(SA_DIR, "str1715_sleeve_top16_returns_pd20a.csv"))
str1715_top16[, Date := as.Date(sig_date)]
setnames(str1715_top16, "monthly_ret", "AR_top16_path1")
str1715_top16 <- str1715_top16[, .(Date, AR_top16_path1)]
str1715_top16[is.na(AR_top16_path1), AR_top16_path1 := 0]
str1715_top16[, ym := format(Date, "%Y-%m")]
cat("1715 top16 rows:", nrow(str1715_top16), "(", as.character(range(str1715_top16$Date)), ")\n")

# 4. Load NEW top4 EW returns
new_top4 <- fread(file.path(SA_DIR, "new_sleeve_top4_returns_184m_pd20a.csv"))
new_top4[, Date := as.Date(sig_date)]
setnames(new_top4, "monthly_ret", "NEW_top4")
new_top4 <- new_top4[, .(Date, NEW_top4)]
new_top4[is.na(NEW_top4), NEW_top4 := 0]
new_top4[, ym := format(Date, "%Y-%m")]
cat("NEW top4 rows:", nrow(new_top4), "(", as.character(range(new_top4$Date)), ")\n\n")

# 5. Merge by ym
sm[, ym := format(Date, "%Y-%m")]
sm_path1 <- merge(sm, str1715_top16[, .(ym, AR_top16_path1)], by = "ym", all.x = TRUE)
sm_path1 <- merge(sm_path1, new_top4[, .(ym, NEW_top4)], by = "ym", all.x = TRUE)
sm_path1[is.na(AR_top16_path1), AR_top16_path1 := AR_on_M4]  # fallback to AR_on_M4 if no top16 data
sm_path1[is.na(NEW_top4), NEW_top4 := 0]
setorder(sm_path1, Date)
cat("merged path1 panel rows:", nrow(sm_path1), "\n")
cat("rows where AR_top16_path1 != AR_on_M4 (i.e., new top16 calc applied):",
    nrow(sm_path1[abs(AR_top16_path1 - AR_on_M4) > 1e-8]), "/", nrow(sm_path1), "\n")
cat("NEW top4 non-zero rows:", nrow(sm_path1[NEW_top4 != 0]), "\n")
cat("first NEW non-zero ym:", min(sm_path1[NEW_top4 != 0]$ym), "\n")
cat("last NEW non-zero ym:", max(sm_path1[NEW_top4 != 0]$ym), "\n\n")

# 6. Compute composite returns
w_AR    <- 0.450
w_TSMOM <- 0.225
w_KR    <- 0.180
w_CASH  <- 0.045
w_NEW   <- 0.100
stopifnot(abs(w_AR + w_TSMOM + w_KR + w_CASH + w_NEW - 1.0) < 1e-9)

# PRIMARY: redistribute
sm_path1[, ret_path1_redist := ifelse(
  NEW_top4 != 0,
  w_AR * AR_top16_path1 + w_TSMOM * TSMOM + w_KR * KR_10y + w_CASH * Cash + w_NEW * NEW_top4,
  (w_AR / 0.90) * AR_top16_path1 + (w_TSMOM / 0.90) * TSMOM + (w_KR / 0.90) * KR_10y + (w_CASH / 0.90) * Cash
)]

# DIAGNOSTIC: strict (NEW=0 outside redistribute)
sm_path1[, ret_path1_strict := w_AR * AR_top16_path1 + w_TSMOM * TSMOM + w_KR * KR_10y + w_CASH * Cash + w_NEW * NEW_top4]

# S4 v2 baseline (4-sleeve 50/25/20/5 with AR_on_M4 original PG2)
w_S4_AR <- 0.50; w_S4_TSMOM <- 0.25; w_S4_KR <- 0.20; w_S4_CASH <- 0.05
sm_path1[, ret_S4_baseline := w_S4_AR * AR_on_M4 + w_S4_TSMOM * TSMOM + w_S4_KR * KR_10y + w_S4_CASH * Cash]

# PD18 baseline (5-sleeve top20) — load PD18 composite returns for comparison
pd18_returns <- fread(file.path(WT_DIR, "backtest_result_med_10pct_pd18/composite_returns_5sleeve_pd18.csv"))
pd18_returns[, Date := as.Date(Date)]
sm_path1 <- merge(sm_path1, pd18_returns[, .(Date, ret_pd18_redist = ret_5sleeve_redistribute)],
                  by = "Date", all.x = TRUE)
setorder(sm_path1, Date)

cat("\nComposite returns range:\n")
cat("  path1 redistribute: min/max=", range(sm_path1$ret_path1_redist), "\n")
cat("  S4 baseline:        min/max=", range(sm_path1$ret_S4_baseline), "\n")

# 7. PerformanceAnalytics metrics
ret_path1_redist <- xts(sm_path1$ret_path1_redist, order.by = sm_path1$Date)
ret_path1_strict <- xts(sm_path1$ret_path1_strict, order.by = sm_path1$Date)
ret_S4           <- xts(sm_path1$ret_S4_baseline, order.by = sm_path1$Date)
ret_pd18         <- xts(sm_path1$ret_pd18_redist, order.by = sm_path1$Date)
colnames(ret_path1_redist) <- "path1_redist"
colnames(ret_path1_strict) <- "path1_strict"
colnames(ret_S4)            <- "S4_baseline"
colnames(ret_pd18)          <- "pd18_top20"

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

m_path1_redist <- compute_metrics(ret_path1_redist, "path1_redistribute_PRIMARY")
m_path1_strict <- compute_metrics(ret_path1_strict, "path1_strict_DIAGNOSTIC")
m_S4           <- compute_metrics(ret_S4, "S4_baseline")
m_pd18         <- compute_metrics(ret_pd18, "pd18_top20_baseline")

cat("\n=== PD20-A Path 1 PRIMARY: redistribute (top16+4) ===\n")
cat("n_months:", m_path1_redist$n_months, "\n")
cat("SR_ann_geometric:", round(m_path1_redist$SR_ann_geom, 4), "\n")
cat("CAGR:", round(m_path1_redist$CAGR, 4), "\n")
cat("MDD:", round(m_path1_redist$MDD, 4), "\n")
cat("Sortino_ann:", round(m_path1_redist$Sortino_ann, 4), "\n")
cat("Calmar:", round(m_path1_redist$Calmar, 4), "\n")
cat("CVaR_95:", round(m_path1_redist$CVaR_95, 4), "\n")
cat("CVaR_99:", round(m_path1_redist$CVaR_99, 4), "\n")
cat("hit_rate:", round(m_path1_redist$hit_rate, 4), "\n")

cat("\n=== PD18 top20 baseline (reference) ===\n")
cat("SR:", round(m_pd18$SR_ann_geom, 4),
    " CAGR:", round(m_pd18$CAGR, 4),
    " MDD:", round(m_pd18$MDD, 4),
    " CVaR_95:", round(m_pd18$CVaR_95, 4), "\n")

cat("\n=== S4 v2 baseline (4-sleeve 50/25/20/5) ===\n")
cat("SR:", round(m_S4$SR_ann_geom, 4),
    " CAGR:", round(m_S4$CAGR, 4),
    " MDD:", round(m_S4$MDD, 4),
    " CVaR_95:", round(m_S4$CVaR_95, 4), "\n")

cat("\n=== Diagnostic: path1 strict (NEW=0 outside, no redistribute) ===\n")
cat("SR:", round(m_path1_strict$SR_ann_geom, 4),
    " CAGR:", round(m_path1_strict$CAGR, 4),
    " MDD:", round(m_path1_strict$MDD, 4), "\n")

# 8. Path 1 vs PD18 delta
cat("\n=== Path 1 vs PD18 (top16+4 vs top20+20) — Truncation Effect ===\n")
delta_vs_pd18 <- list(
  delta_SR = m_path1_redist$SR_ann_geom - m_pd18$SR_ann_geom,
  delta_CAGR_pp = (m_path1_redist$CAGR - m_pd18$CAGR) * 100,
  delta_MDD_pp = (abs(m_pd18$MDD) - abs(m_path1_redist$MDD)) * 100,
  delta_CVaR95_pp = (abs(m_pd18$CVaR_95) - abs(m_path1_redist$CVaR_95)) * 100,
  delta_Sortino = m_path1_redist$Sortino_ann - m_pd18$Sortino_ann,
  delta_Calmar = m_path1_redist$Calmar - m_pd18$Calmar
)
cat("Δ SR:        ", round(delta_vs_pd18$delta_SR, 4), "\n")
cat("Δ CAGR:      ", round(delta_vs_pd18$delta_CAGR_pp, 4), "pp\n")
cat("Δ MDD:       ", round(delta_vs_pd18$delta_MDD_pp, 4), "pp (positive = MDD reduction)\n")
cat("Δ CVaR_95:   ", round(delta_vs_pd18$delta_CVaR95_pp, 4), "pp (positive = CVaR reduction)\n")
cat("Δ Sortino:   ", round(delta_vs_pd18$delta_Sortino, 4), "\n")
cat("Δ Calmar:    ", round(delta_vs_pd18$delta_Calmar, 4), "\n")

# 9. 4-axis strict improve check vs S4 v2 (PD18 baseline reference)
S4_doc <- list(SR = 1.8334, CAGR = 0.2020, MDD = -0.1252, CVaR_95 = -0.0501)
axis_check <- list(
  SR_delta = m_path1_redist$SR_ann_geom - S4_doc$SR,
  CAGR_delta_pp = (m_path1_redist$CAGR - S4_doc$CAGR) * 100,
  MDD_delta_pp = (abs(S4_doc$MDD) - abs(m_path1_redist$MDD)) * 100,
  CVaR_delta_pp = (abs(S4_doc$CVaR_95) - abs(m_path1_redist$CVaR_95)) * 100,
  SR_pass = m_path1_redist$SR_ann_geom > S4_doc$SR,
  CAGR_pass = m_path1_redist$CAGR > S4_doc$CAGR,
  MDD_pass = abs(m_path1_redist$MDD) < abs(S4_doc$MDD),
  CVaR_pass = abs(m_path1_redist$CVaR_95) < abs(S4_doc$CVaR_95)
)
axis_check$n_pass <- sum(unlist(axis_check[c("SR_pass", "CAGR_pass", "MDD_pass", "CVaR_pass")]))
axis_check$verdict <- if (axis_check$n_pass == 4) "4_PASS_STRICT_IMPROVE" else
                       sprintf("%d_PASS_%d_FAIL", axis_check$n_pass, 4 - axis_check$n_pass)

cat("\n=== 4-axis Strict Improve vs S4 v2 ===\n")
cat("SR:    ", round(axis_check$SR_delta, 4), "| PASS:", axis_check$SR_pass, "\n")
cat("CAGR:  ", round(axis_check$CAGR_delta_pp, 4), "pp | PASS:", axis_check$CAGR_pass, "\n")
cat("MDD:   ", round(axis_check$MDD_delta_pp, 4), "pp | PASS:", axis_check$MDD_pass, "\n")
cat("CVaR:  ", round(axis_check$CVaR_delta_pp, 4), "pp | PASS:", axis_check$CVaR_pass, "\n")
cat("Verdict:", axis_check$verdict, "\n")

# 10. Diebold-Mariano test vs S4 v2
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

diff_vs_S4 <- as.numeric(ret_path1_redist) - as.numeric(ret_S4)
n <- length(diff_vs_S4)
mean_diff_S4 <- mean(diff_vs_S4)
se_S4 <- nw_se(diff_vs_S4, lag = 6)
t_NW_S4 <- mean_diff_S4 / se_S4
p_S4 <- 2 * (1 - pnorm(abs(t_NW_S4)))

cat("\n=== Diebold-Mariano vs S4 v2 (NW HAC lag 6) ===\n")
cat("n_months:", n, "\n")
cat("mean_diff:", round(mean_diff_S4, 6), "\n")
cat("t_NW:", round(t_NW_S4, 4), "\n")
cat("p:", round(p_S4, 4), "\n")

# Path 1 vs PD18 DM
diff_vs_pd18 <- as.numeric(ret_path1_redist) - as.numeric(ret_pd18)
mean_diff_pd18 <- mean(diff_vs_pd18, na.rm = TRUE)
diff_clean <- diff_vs_pd18[!is.na(diff_vs_pd18)]
se_pd18 <- nw_se(diff_clean, lag = 6)
t_NW_pd18 <- mean_diff_pd18 / se_pd18
p_pd18 <- 2 * (1 - pnorm(abs(t_NW_pd18)))

cat("\n=== Diebold-Mariano vs PD18 (truncation effect) ===\n")
cat("n_months:", length(diff_clean), "\n")
cat("mean_diff:", round(mean_diff_pd18, 6), "\n")
cat("t_NW:", round(t_NW_pd18, 4), "\n")
cat("p:", round(p_pd18, 4), "\n")
dm_interp_pd18 <- if (abs(t_NW_pd18) > 2) {
  if (mean_diff_pd18 > 0) "Path 1 (top16+4) outperforms PD18 (top20+20) significantly" else "PD18 (top20+20) outperforms Path 1 (top16+4) significantly"
} else {
  "statistically equivalent (NS)"
}
cat("interpretation:", dm_interp_pd18, "\n")

# 11. Sub-period: alpha-active 184m (2011-01 ~ 2026-04)
sm_path1[, in_alpha := (Date >= as.Date("2011-01-01") & Date <= as.Date("2026-04-30"))]
sm_alpha <- sm_path1[in_alpha == TRUE]
ret_path1_alpha <- xts(sm_alpha$ret_path1_redist, order.by = sm_alpha$Date)
ret_pd18_alpha <- xts(sm_alpha$ret_pd18_redist, order.by = sm_alpha$Date)
m_path1_alpha <- compute_metrics(ret_path1_alpha, "path1_alpha_active")
m_pd18_alpha <- compute_metrics(ret_pd18_alpha, "pd18_alpha_active")

cat("\n=== Sub-period: alpha-active 184m (2011-01 ~ 2026-04) ===\n")
cat("Path 1 alpha-active SR:", round(m_path1_alpha$SR_ann_geom, 4),
    " CAGR:", round(m_path1_alpha$CAGR, 4),
    " MDD:", round(m_path1_alpha$MDD, 4), "\n")
cat("PD18 alpha-active SR:", round(m_pd18_alpha$SR_ann_geom, 4),
    " CAGR:", round(m_pd18_alpha$CAGR, 4),
    " MDD:", round(m_pd18_alpha$MDD, 4), "\n")

# 12. Cost-embedded variant (15bps × estimated turnover)
# PD20-A inherits PD18 issue: composite-level turnover not realized
# Estimate: at each rebal date, sleeve internal name turnover ~ 100% monthly (worst case sleeve top16 + top4 are dynamic)
# Approximation: 15bps cost × sleeve weight × monthly turnover (1.0 within sleeve)
# Internal turnover impact monthly_ret_post_cost = monthly_ret - cost_bp
# Conservative: 15bps × 2 (round trip) × sleeve_internal_weight × sleeve_weight
# 1715: 0.0015 × 2 × 1.0 × 0.45 = 13.5bps/mo on 1715 sleeve
# NEW:   0.0015 × 2 × 1.0 × 0.10 = 3.0bps/mo on NEW sleeve
# TSMOM: 0.0015 × 2 × 1.0 × 0.225 = 6.75bps/mo (8-ETF rotation)
# KR_10y: 0.0015 × 2 × 0.05 × 0.18 = 0.27bps/mo (low turnover bond)
# Cash:  0 turnover
# Total: ~23.5bps/mo composite-level cost

# Apply uniform cost drag 23.5bps per month
COMPOSITE_COST_BP_PER_MONTH <- 0.00235
ret_path1_redist_cost <- ret_path1_redist - COMPOSITE_COST_BP_PER_MONTH
colnames(ret_path1_redist_cost) <- "path1_redist_cost"
m_path1_redist_cost <- compute_metrics(ret_path1_redist_cost, "path1_redist_cost_embedded")

cat("\n=== Cost-embedded variant (composite ~23.5bps/mo estimate) ===\n")
cat("SR:", round(m_path1_redist_cost$SR_ann_geom, 4),
    " CAGR:", round(m_path1_redist_cost$CAGR, 4),
    " MDD:", round(m_path1_redist_cost$MDD, 4), "\n")
cat("SR drag:", round(m_path1_redist$SR_ann_geom - m_path1_redist_cost$SR_ann_geom, 4), "\n")

# 13. PIT extension sub-period
sm_pd13 <- sm_path1[Date >= as.Date("2024-01-01") & Date <= as.Date("2026-04-30")]
ret_path1_pd13 <- xts(sm_pd13$ret_path1_redist, order.by = sm_pd13$Date)
m_path1_pd13 <- compute_metrics(ret_path1_pd13, "path1_pd13_extension")

cat("\n=== Sub-period: PD13 extension 29m (2024-01 ~ 2026-04) ===\n")
cat("SR:", round(m_path1_pd13$SR_ann_geom, 4),
    " CAGR:", round(m_path1_pd13$CAGR, 4),
    " MDD:", round(m_path1_pd13$MDD, 4),
    " n:", m_path1_pd13$n_months, "\n")

# 14. Save outputs
out_dir <- file.path(WT_DIR, "backtest_result_pd20a_path1")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

sm_save <- sm_path1[, .(Date, ym, AR_on_M4, AR_top16_path1, TSMOM, KR_10y, Cash, NEW_top4,
                         ret_path1_redist, ret_path1_strict, ret_S4_baseline, ret_pd18_redist)]
fwrite(sm_save, file.path(out_dir, "composite_returns_5sleeve_pd20a_path1.csv"))
cat("\ncomposite returns saved: composite_returns_5sleeve_pd20a_path1.csv\n")

metrics_pkg <- list(
  primary_redistribute_path1_256m = m_path1_redist,
  primary_redistribute_path1_cost_embedded = m_path1_redist_cost,
  diagnostic_strict_path1_256m = m_path1_strict,
  baseline_pd18_top20_256m = m_pd18,
  baseline_S4_doc = S4_doc,
  baseline_S4_realized_256m = m_S4,
  path1_alpha_active_184m = m_path1_alpha,
  pd18_alpha_active_184m = m_pd18_alpha,
  path1_pd13_extension_29m = m_path1_pd13,
  axis_check = axis_check,
  delta_vs_pd18 = delta_vs_pd18,
  dm_test_vs_S4 = list(t_NW = t_NW_S4, p = p_S4, mean_diff = mean_diff_S4, se_NW = se_S4),
  dm_test_vs_pd18 = list(t_NW = t_NW_pd18, p = p_pd18, mean_diff = mean_diff_pd18,
                          se_NW = se_pd18, interpretation = dm_interp_pd18),
  composite_cost_assumption = list(
    monthly_bp = COMPOSITE_COST_BP_PER_MONTH * 1e4,
    annual_pct = COMPOSITE_COST_BP_PER_MONTH * 12 * 100,
    note = "Estimated 23.5bps/month composite-level drag from sleeve internal turnover × sleeve weight × 15bps × 2 round trip"
  ),
  path1_topn_config = list(
    str1715_topN = 16, new_topN = 4,
    aggregate_KR_equity_count = 20,
    etf_count = 9, cash_count = 1,
    production_max_20_pass = TRUE,
    etf_excluded_per_dohoon_mandate = TRUE
  )
)
saveRDS(metrics_pkg, file.path(out_dir, "metrics_pd20a_path1.rds"))
cat("metrics RDS saved\n")

# 15. md5sum end (Pure function audit)
md5_end <- list(
  alpha = tools::md5sum(file.path(WT_DIR, "alpha_package.json")),
  risk  = tools::md5sum(file.path(WT_DIR, "risk_package.json")),
  opt   = tools::md5sum(file.path(WT_DIR, "optimization_package.json"))
)
audit_pure <- list(
  alpha_match = (md5_start$alpha == md5_end$alpha),
  risk_match  = (md5_start$risk == md5_end$risk),
  opt_match   = (md5_start$opt == md5_end$opt),
  alpha_md5_start = unname(md5_start$alpha), alpha_md5_end = unname(md5_end$alpha),
  risk_md5_start = unname(md5_start$risk), risk_md5_end = unname(md5_end$risk),
  opt_md5_start = unname(md5_start$opt), opt_md5_end = unname(md5_end$opt)
)
cat("\nPure function audit:\n")
cat("  alpha match:", audit_pure$alpha_match, "\n")
cat("  risk match: ", audit_pure$risk_match, "\n")
cat("  opt match:  ", audit_pure$opt_match, "\n")
saveRDS(audit_pure, file.path(out_dir, "pure_function_audit.rds"))

# 16. Print PD18 truncation effect summary
cat("\n=========================================\n")
cat("=== PD20-A Path 1 vs PD18 — Truncation Effect Summary ===\n")
cat("=========================================\n")
cat("PD18 (top20+20) primary 256m SR:    ", round(m_pd18$SR_ann_geom, 4), "\n")
cat("PD20-A Path 1 (top16+4) primary SR: ", round(m_path1_redist$SR_ann_geom, 4), "\n")
cat("Δ SR (truncation effect):          ", round(delta_vs_pd18$delta_SR, 4), "\n\n")
cat("PD18 CAGR:   ", round(m_pd18$CAGR, 4), "\n")
cat("Path 1 CAGR:", round(m_path1_redist$CAGR, 4), "\n")
cat("Δ CAGR pp:   ", round(delta_vs_pd18$delta_CAGR_pp, 4), "\n\n")
cat("PD18 MDD:    ", round(m_pd18$MDD, 4), "\n")
cat("Path 1 MDD: ", round(m_path1_redist$MDD, 4), "\n")
cat("Δ MDD pp:    ", round(delta_vs_pd18$delta_MDD_pp, 4), "\n\n")
cat("Production 종목수 max 20 cap status: PASS ✓ (1715 top16 + NEW top4 = 20, ETF + Cash excluded)\n")
cat("DM test vs PD18: t_NW=", round(t_NW_pd18, 4), " p=", round(p_pd18, 4), "\n")
cat("Interpretation:", dm_interp_pd18, "\n")
cat("\nDONE: PD20-A Path 1 backtest complete\n")
