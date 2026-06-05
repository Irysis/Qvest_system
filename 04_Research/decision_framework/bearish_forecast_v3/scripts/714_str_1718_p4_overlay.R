#!/usr/bin/env Rscript
#==============================================================================
# 714_str_1718_p4_overlay.R — STR_1718 = STR_1715 R5 + P4 Multi-Trigger cash overlay
#
# 도훈 mandate 2026-05-27:
# - STR_1715 R5 (PG2 admit) base
# - P4 산출물 5종 (VaR5/σ/λ/μ/ν) z-score 기반 Multi-Trigger
# - 월말 직전 영업일 P4 signal 산출 → 다음 월 cash overlay 적용
#
# Multi-Trigger spec (z > 1.0 시작, expanding z):
#   trigger_var  = clip(0, 0.30, max(0, -z_VaR5 - 1.0) × 0.10)
#   trigger_vol  = clip(0, 0.30, max(0, z_σ     - 1.0) × 0.10)
#   trigger_skew = clip(0, 0.30, max(0, -z_λ    - 1.0) × 0.20)
#   trigger_tail = clip(0, 0.30, max(0, z_1/ν   - 1.0) × 0.20)
#   cash_p4 = pmin(0.50, max(4 trigger))
#
# Cost model: cost = 15bps × |Δcash_p4| (cash transition only, alpha은 R5 baked-in)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(PerformanceAnalytics); library(xts)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
STR_VARIANT <- "ret_L5_V5"  # default admit variant (도훈 confirm 필요 시 V1~V4 sweep)

# ── 1. STR_1715 R5 monthly returns ────────────────────────────────────────
bt <- readRDS(file.path(PROJECT_ROOT,
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/bt_result_layer5_R05.rds"))
pr <- bt$period_returns[!is.na(get(STR_VARIANT))][, .(anchor_date, realized_ym,
                                                       ret_str1715 = get(STR_VARIANT))]
setorder(pr, anchor_date)
cat(sprintf("[STR_1715 R5] %d months (%s ~ %s)\n",
            nrow(pr), pr$anchor_date[1], pr$anchor_date[nrow(pr)]))

# ── 2. P4 daily predictions → month-end signal ────────────────────────────
p4 <- as.data.table(read_parquet(file.path(PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v3/03_models/p4_ecdf_final/all_predictions_extended.parquet")))
p4[, Date := as.Date(Date)]
p4[, ym := format(Date, "%Y-%m")]
# Last business day per month
p4_m <- p4[, .SD[.N], by=ym]
setorder(p4_m, Date)
cat(sprintf("[P4 monthly] %d months (%s ~ %s)\n",
            nrow(p4_m), as.character(p4_m$Date[1]), as.character(p4_m$Date[nrow(p4_m)])))

# ── 3. Expanding z-score + clip ±3 ─────────────────────────────────────────
expanding_z <- function(x, min_obs=12L) {
  n <- length(x); out <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (i < min_obs) next
    v <- x[1:i]; m <- mean(v, na.rm=TRUE); s <- sd(v, na.rm=TRUE)
    if (is.na(s) || s == 0) next
    out[i] <- (x[i] - m) / s
  }
  out
}
clip_z <- function(z, cap=3) pmin(pmax(z, -cap), cap)

# z conventions: each "z" defined so that POSITIVE z = stress
p4_m[, z_var_stress  := clip_z(expanding_z(-var_05))]      # var_05 더 음수 → z positive
p4_m[, z_sigma       := clip_z(expanding_z(sigma))]
p4_m[, z_lam_stress  := clip_z(expanding_z(-lam))]         # lam 더 음수 → z positive
p4_m[, z_inv_nu      := clip_z(expanding_z(1 / pmax(nu, 1)))]  # nu 낮음 → 1/nu 큼 → z positive

# ── 4. Multi-Trigger ────────────────────────────────────────────────────────
clip_to <- function(x, lo=0, hi=0.30) pmin(pmax(x, lo), hi)
p4_m[, trigger_var  := clip_to(pmax(0, z_var_stress - 1.0) * 0.10)]
p4_m[, trigger_vol  := clip_to(pmax(0, z_sigma      - 1.0) * 0.10)]
p4_m[, trigger_skew := clip_to(pmax(0, z_lam_stress - 1.0) * 0.20)]
p4_m[, trigger_tail := clip_to(pmax(0, z_inv_nu     - 1.0) * 0.20)]
p4_m[, cash_p4 := pmin(0.50, pmax(trigger_var, trigger_vol, trigger_skew, trigger_tail))]
p4_m[is.na(cash_p4), cash_p4 := 0]

cat(sprintf("[Multi-Trigger] cash_p4 distribution:\n"))
print(summary(p4_m$cash_p4))
cat(sprintf("  cash_p4 > 0: %d / %d months (%.1f%%)\n",
            sum(p4_m$cash_p4 > 0), nrow(p4_m), mean(p4_m$cash_p4 > 0)*100))
cat(sprintf("  cash_p4 > 0.10: %d months\n", sum(p4_m$cash_p4 > 0.10)))
cat(sprintf("  cash_p4 > 0.30: %d months\n", sum(p4_m$cash_p4 > 0.30)))

# ── 5. Merge: STR_1715 R5 (이 달의 ret) + P4 cash (전월말 신호로 결정) ────
# anchor_date (월초) = 운용 시작점. 그 직전 영업일 P4 signal 사용.
# P4 월말 signal → 다음 월의 cash_p4로 적용 (lag 1 month).
pr[, ym := format(anchor_date, "%Y-%m")]
# P4 signal for month T = P4 last day of (T-1). i.e., shift forward by 1 month.
p4_m[, ym_apply := format(Date + 35, "%Y-%m")]  # 다음 월 (rough +35d)
# Cleaner: explicit shift via realized_ym
p4_m[, year_int := as.integer(substr(ym, 1, 4))]
p4_m[, month_int := as.integer(substr(ym, 6, 7))]
p4_m[, ym_next := sprintf("%04d-%02d",
                           ifelse(month_int == 12, year_int + 1, year_int),
                           ifelse(month_int == 12, 1, month_int + 1))]

p4_signal <- p4_m[, .(ym = ym_next, cash_p4, trigger_var, trigger_vol, trigger_skew, trigger_tail)]
merged <- merge(pr, p4_signal, by = "ym", all.x = TRUE)
setorder(merged, anchor_date)
merged[is.na(cash_p4), cash_p4 := 0]  # P4 미적용 기간 = base 그대로

# ── 6. STR_1718 ret = ret_str1715 × (1 - cash_p4) − transition cost ────────
COMMISSION <- 0.0015  # 15bps one-way
merged[, prev_cash := shift(cash_p4, n=1, type="lag", fill=0)]
merged[, cash_delta := abs(cash_p4 - prev_cash)]
merged[, cost := COMMISSION * cash_delta]  # cash 전환 cost
merged[, ret_str1718 := ret_str1715 * (1 - cash_p4) - cost]

# ── 7. NAV + metrics ───────────────────────────────────────────────────────
make_xts <- function(returns_vec, dates) {
  xts(returns_vec, order.by = as.Date(dates))
}
ret_xts_1715 <- make_xts(merged$ret_str1715, merged$anchor_date)
ret_xts_1718 <- make_xts(merged$ret_str1718, merged$anchor_date)

# Baseline vs P4-overlay metrics
metrics_compare <- function(r_xts, label) {
  cumret <- prod(1 + r_xts) - 1
  ann_ret <- as.numeric(Return.annualized(r_xts, scale=12))
  ann_vol <- as.numeric(StdDev.annualized(r_xts, scale=12))
  sr <- as.numeric(SharpeRatio.annualized(r_xts, scale=12))
  mdd <- as.numeric(maxDrawdown(r_xts))
  cat(sprintf("[%s] n=%d  CAGR=%.2f%%  Vol=%.2f%%  Sharpe=%.3f  MDD=%.2f%%  CumRet=%.1f%%\n",
              label, length(r_xts), ann_ret*100, ann_vol*100, sr, mdd*100, cumret*100))
  list(CAGR=ann_ret, Vol=ann_vol, Sharpe=sr, MDD=mdd, CumRet=cumret)
}

cat("\n=== Backtest Comparison ===\n")
m1715 <- metrics_compare(ret_xts_1715, "STR_1715 R5 (baseline)")
m1718 <- metrics_compare(ret_xts_1718, "STR_1718 (R5 + P4 overlay)")

# Period subset: P4 prediction 시작점부터
p4_first_ym <- min(p4_m$ym_next, na.rm=TRUE)
merged_sub <- merged[ym >= p4_first_ym]
ret_xts_1715_sub <- make_xts(merged_sub$ret_str1715, merged_sub$anchor_date)
ret_xts_1718_sub <- make_xts(merged_sub$ret_str1718, merged_sub$anchor_date)

cat(sprintf("\n=== P4 운용 가능 기간만 (%s ~) ===\n", p4_first_ym))
m1715_sub <- metrics_compare(ret_xts_1715_sub, "STR_1715 R5 (P4-window)")
m1718_sub <- metrics_compare(ret_xts_1718_sub, "STR_1718 (R5 + P4 overlay)")

# ── 8. Save ────────────────────────────────────────────────────────────────
out_dir <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1718_R5_P4_overlay/output")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)
fwrite(merged, file.path(out_dir, "monthly_returns.csv"))
cat(sprintf("\n[saved] %s\n", file.path(out_dir, "monthly_returns.csv")))

summary_list <- list(
  variant = STR_VARIANT,
  full_window = list(
    str_1715 = m1715, str_1718 = m1718,
    n_months = nrow(merged), date_range = as.character(range(merged$anchor_date))
  ),
  p4_window = list(
    str_1715 = m1715_sub, str_1718 = m1718_sub,
    n_months = nrow(merged_sub), date_range = as.character(range(merged_sub$anchor_date)),
    cash_p4_dist = as.list(summary(merged_sub$cash_p4)),
    n_active = sum(merged_sub$cash_p4 > 0),
    avg_cash_when_active = mean(merged_sub$cash_p4[merged_sub$cash_p4 > 0])
  )
)
jsonlite::write_json(summary_list, file.path(out_dir, "summary.json"),
                      pretty=TRUE, auto_unbox=TRUE, digits=6)
cat(sprintf("[saved] %s\n", file.path(out_dir, "summary.json")))
