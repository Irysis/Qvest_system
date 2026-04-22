#==============================================================================
# H_1685 v2 Residualization Pre-Check — Option A Validation
#
# Purpose: expanding-window OLS residual(z_foreign_21d ~ z_individual_21d)가
#          H_1674 (INV07 Retail_Contrarian = -z_individual_21d)와 수식상
#          orthogonal인지 실측 검증
#
# Success criteria:
#   - Mean |corr(residual, -z_individual_21d)| < 0.20
#   - Median |corr| < 0.25
# Failure path: Option A 파기 → H_1685 번호 폐기 검토
#
# PIT compliance:
#   - strict Date < sig_d (C2)
#   - expanding window는 sig_date 시점까지 데이터만 (C1)
#   - 21d lookback (기본 — s0_record v2에서 63d sensitivity는 S2에서 진행)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

PARQUET_PATH <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/.cache/investor_stock/investor_wide.parquet"

cat("[H1685_v2] Loading investor_wide.parquet...\n")
t0 <- Sys.time()
inv <- as.data.table(arrow::read_parquet(PARQUET_PATH))
inv[, Date := as.Date(Date)]
setorder(inv, Ticker, Date)
cat(sprintf("[H1685_v2] Loaded: %d rows, %d tickers, %s~%s, elapsed %.1fs\n",
            nrow(inv), uniqueN(inv$Ticker),
            min(inv$Date), max(inv$Date),
            as.numeric(Sys.time() - t0, units = "secs")))

# ── 21d rolling net-buy intensity 원시 신호 ────────────────────────────────
# compute_investor.R INV01/INV07 패턴 — Size 정규화는 본 검증에서는 원시
# net-buy 사용 (cross-sectional z-score로 후처리하므로 scale 무관)

MIN_OBS_20 <- 15L

cat("[H1685_v2] Computing 21d rolling net-buy (per Ticker)...\n")
inv[, `:=`(
  roll_F21 = frollsum(Foreign,    n = 21L, na.rm = TRUE, align = "right"),
  roll_I21 = frollsum(Individual, n = 21L, na.rm = TRUE, align = "right"),
  n_F21    = frollsum(!is.na(Foreign),    n = 21L, align = "right"),
  n_I21    = frollsum(!is.na(Individual), n = 21L, align = "right")
), by = Ticker]

inv[n_F21 < MIN_OBS_20, roll_F21 := NA_real_]
inv[n_I21 < MIN_OBS_20, roll_I21 := NA_real_]

# ── 월말(rebalance date) 샘플만 추출 ───────────────────────────────────────
# 월말 = 각 (Ticker, YearMonth)에서 max(Date). 현실 rebalance 패턴 모사.
inv[, YM := format(Date, "%Y-%m")]
monthly <- inv[!is.na(roll_F21) & !is.na(roll_I21),
               .SD[.N],
               by = .(Ticker, YM),
               .SDcols = c("Date", "roll_F21", "roll_I21")]
setorder(monthly, Date, Ticker)

cat(sprintf("[H1685_v2] Monthly snapshots: %d rows, %d distinct months\n",
            nrow(monthly), uniqueN(monthly$YM)))

# ── 월별 cross-sectional z-score + expanding OLS residual ──────────────────
# 각 월 t:
#   z_F_t = (roll_F21 - mean_t) / sd_t   (cross-section at t)
#   z_I_t = (roll_I21 - mean_t) / sd_t
# expanding OLS: 월 t까지의 (z_F, z_I) 누적 pairs로 slope β_t 추정
#   residual_t(i) = z_F_t(i) - β_t × z_I_t(i)
# H_1674 proxy = -z_I_t(i)  (INV07 signal 수식 그대로)
# corr_t = cor(residual_t, -z_I_t)  across tickers at month t

months_sorted <- sort(unique(monthly$YM))
BURN_IN <- 60L  # s0_record v2: 60개월 burn-in

# 누적 sum을 위해 z-score 선계산
cat("[H1685_v2] Computing cross-sectional z-scores per month...\n")
monthly[, `:=`(
  z_F = as.numeric(scale(roll_F21)),
  z_I = as.numeric(scale(roll_I21))
), by = YM]
monthly <- monthly[!is.na(z_F) & !is.na(z_I)]

# Winsorize 1%/99% (s0_record v2 설계 일치)
wz <- function(x, p = 0.01) {
  q <- quantile(x, probs = c(p, 1 - p), na.rm = TRUE)
  pmin(pmax(x, q[1]), q[2])
}
monthly[, `:=`(z_F = wz(z_F), z_I = wz(z_I)), by = YM]

# expanding OLS β_t: slope of z_F on z_I using ALL pairs up to and including month t
# Since each month is already cross-sectionally z-scored, within-month slope ≈ corr(z_F, z_I).
# Expanding slope uses pooled (z_F, z_I) across all months ≤ t.
#   β_t = Σ(z_F × z_I) / Σ(z_I²)   (OLS no-intercept, both centered by month already)

cat("[H1685_v2] Computing expanding OLS slope and residuals month by month...\n")

# 효율을 위해 월별 sum(z_F*z_I), sum(z_I^2) 사전 계산 후 cumsum
month_stats <- monthly[, .(
  SxY = sum(z_F * z_I, na.rm = TRUE),
  Sxx = sum(z_I * z_I, na.rm = TRUE),
  n   = .N
), by = YM]
setkey(month_stats, YM)
month_stats <- month_stats[order(YM)]
month_stats[, `:=`(
  cum_SxY = cumsum(SxY),
  cum_Sxx = cumsum(Sxx)
)]
# β_t at month t = cum_SxY[t-1] / cum_Sxx[t-1]  (strict lag, C1 compliant — use only data BEFORE month t)
# 실제로는 expanding window가 "t까지"이므로 t에서 즉시 사용 가능할 때 C1 주의.
# 안전하게 lagged β_t = β at end of month t-1 → month t 잔차 계산에 사용
month_stats[, beta_lag := shift(cum_SxY / cum_Sxx, 1L)]  # C1: strict prior-month info only

beta_map <- setNames(month_stats$beta_lag, month_stats$YM)

# 월별 잔차 + corr(residual, -z_I) 계산
results <- list()
skipped <- 0L
for (i in seq_along(months_sorted)) {
  ym <- months_sorted[i]
  if (i <= BURN_IN) { skipped <- skipped + 1L; next }
  beta_t <- beta_map[[ym]]
  if (is.na(beta_t) || is.null(beta_t)) { skipped <- skipped + 1L; next }
  sub <- monthly[YM == ym]
  if (nrow(sub) < 50L) { skipped <- skipped + 1L; next }
  resid_t <- sub$z_F - beta_t * sub$z_I
  h1674_proxy <- -sub$z_I
  # Core check: corr(residual, H_1674 signal)
  c_h1674 <- cor(resid_t, h1674_proxy, use = "pairwise.complete.obs")
  # Auxiliary: corr(residual, z_F raw) — 외국인 정보 채널 보존 확인
  c_fraw  <- cor(resid_t, sub$z_F, use = "pairwise.complete.obs")
  # Auxiliary: corr(residual, z_I)
  c_ires  <- cor(resid_t, sub$z_I, use = "pairwise.complete.obs")
  results[[length(results) + 1L]] <- data.table(
    YM = ym, n = nrow(sub), beta_t = beta_t,
    corr_vs_H1674 = c_h1674,
    corr_vs_zF_raw = c_fraw,
    corr_vs_zI = c_ires
  )
}
res <- rbindlist(results)

cat(sprintf("\n[H1685_v2] Skipped %d months (burn-in %d + insufficient data), analyzed %d months\n",
            skipped, BURN_IN, nrow(res)))

# ── 결과 요약 ───────────────────────────────────────────────────────────────
cat("\n==============================================================\n")
cat("[H_1685 v2 VALIDATION RESULTS]\n")
cat("==============================================================\n")
cat(sprintf("Analyzed months   : %d (%s ~ %s)\n", nrow(res), min(res$YM), max(res$YM)))
cat(sprintf("Mean N per month  : %.0f\n", mean(res$n)))
cat("\n--- Core Gate: corr(residual, H_1674 signal = -z_I) ---\n")
cat(sprintf("  mean(|corr|)     = %.4f  [target < 0.20]\n", mean(abs(res$corr_vs_H1674))))
cat(sprintf("  median(|corr|)   = %.4f  [target < 0.25]\n", median(abs(res$corr_vs_H1674))))
cat(sprintf("  mean(corr)       = %.4f\n", mean(res$corr_vs_H1674)))
cat(sprintf("  median(corr)     = %.4f\n", median(res$corr_vs_H1674)))
cat(sprintf("  p95(|corr|)      = %.4f\n", quantile(abs(res$corr_vs_H1674), 0.95)))
cat("\n--- Channel Preservation: corr(residual, z_F_raw) ---\n")
cat(sprintf("  mean             = %.4f  [expect 0.40~0.70 — 외국인 정보 보존]\n",
            mean(res$corr_vs_zF_raw)))
cat(sprintf("  median           = %.4f\n", median(res$corr_vs_zF_raw)))
cat("\n--- Sanity: corr(residual, z_I) — expanding OLS orthogonality ---\n")
cat(sprintf("  mean             = %.4f  [expect ≈ 0, small residual correlation OK]\n",
            mean(res$corr_vs_zI)))
cat(sprintf("  median           = %.4f\n", median(res$corr_vs_zI)))

# ── Gate 판정 ─────────────────────────────────────────────────────────────
PASS_MEAN   <- mean(abs(res$corr_vs_H1674))   < 0.20
PASS_MEDIAN <- median(abs(res$corr_vs_H1674)) < 0.25
overall_pass <- PASS_MEAN && PASS_MEDIAN

cat("\n==============================================================\n")
cat(sprintf("GATE: mean|corr| < 0.20 : %s\n", ifelse(PASS_MEAN,   "PASS", "FAIL")))
cat(sprintf("GATE: median|corr| < 0.25 : %s\n", ifelse(PASS_MEDIAN, "PASS", "FAIL")))
cat(sprintf("OVERALL                   : %s\n", ifelse(overall_pass, "PASS", "FAIL")))
cat("==============================================================\n")

# JSON 결과 저장 (s0_record v2 참조용)
out <- list(
  validation_id    = "H_1685_v2_residual_precheck",
  timestamp        = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  lookback_days    = 21L,
  burn_in_months   = BURN_IN,
  analyzed_months  = nrow(res),
  date_range       = paste(min(res$YM), "~", max(res$YM)),
  mean_abs_corr_vs_H1674    = round(mean(abs(res$corr_vs_H1674)), 4),
  median_abs_corr_vs_H1674  = round(median(abs(res$corr_vs_H1674)), 4),
  mean_signed_corr_vs_H1674 = round(mean(res$corr_vs_H1674), 4),
  median_signed_corr_vs_H1674 = round(median(res$corr_vs_H1674), 4),
  p95_abs_corr_vs_H1674     = round(unname(quantile(abs(res$corr_vs_H1674), 0.95)), 4),
  mean_corr_vs_zF_raw       = round(mean(res$corr_vs_zF_raw), 4),
  median_corr_vs_zF_raw     = round(median(res$corr_vs_zF_raw), 4),
  mean_corr_vs_zI           = round(mean(res$corr_vs_zI), 4),
  pass_mean_gate            = PASS_MEAN,
  pass_median_gate          = PASS_MEDIAN,
  overall_pass              = overall_pass,
  verdict                   = ifelse(overall_pass, "OPTION_A_VIABLE", "OPTION_A_FAIL_CONSIDER_H1685_DEPRECATION")
)

out_path <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/stage_artifacts/h1685_v2_residual_validation_result.json"
writeLines(jsonlite::toJSON(out, auto_unbox = TRUE, pretty = TRUE), out_path)
cat(sprintf("\n[H1685_v2] Result saved: %s\n", out_path))

# 월별 상세 CSV도 저장
csv_path <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/stage_artifacts/h1685_v2_residual_validation_monthly.csv"
fwrite(res, csv_path)
cat(sprintf("[H1685_v2] Monthly detail saved: %s\n", csv_path))
