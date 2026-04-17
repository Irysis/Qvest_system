## S5 Mutation Lab: STR_930 DD Brake Overlay
## 목적: MDD 54.15% -> 45% 미만으로 억제해 Hard Fail 해소
## C9 준수: dd_lag <- c(0, head(dd_pct, -1)) — t-1 lag 엄격 적용
## 세 variant 비교 후 최적 선정

cat("=== STR_930 S5 Mutation: DD Brake Overlay ===\n\n")

library(xts)
library(zoo)
library(data.table)

SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())

# ── 1. sim_result 로드 ────────────────────────────────────────────────
cat("[Step 1] sim_result.rds 로드...\n")
sim <- readRDS(file.path(SCRIPT_DIR, "sim_result.rds"))
ret  <- as.numeric(sim$strategy_xts)
dts  <- as.Date(index(sim$strategy_xts))
n_f  <- length(ret)
cat(sprintf("  기간: %s ~ %s | N=%d\n",
    as.character(dts[1]), as.character(dts[n_f]), n_f))

# ── 2. Baseline 성과 (S1 결과 확인) ──────────────────────────────────
calc_perf <- function(r, dts, label = "Baseline") {
  nav     <- cumprod(1 + r)
  dd_vec  <- 1 - nav / cummax(nav)
  mdd     <- -max(dd_vec) * 100
  n_days  <- length(r)
  cagr    <- (tail(nav, 1)^(252 / n_days) - 1) * 100
  sr      <- mean(r) / sd(r) * sqrt(252)
  vol     <- sd(r) * sqrt(252) * 100
  # Turnover 추정: exposure 변화 합계 (DD overlay 적용 시 별도 계산)
  list(label=label, CAGR=round(cagr,2), SR=round(sr,3),
       MDD=round(mdd,2), Vol=round(vol,2))
}

# TO 계산 함수 (exposure 기반)
calc_to_from_exposure <- function(exp_vec) {
  # 연간 exposure 변화 합계 (monthly 리밸런싱 1회 = 100%)
  # daily exposure shift를 연율화
  to_daily <- abs(diff(exp_vec))
  to_annual <- mean(to_daily, na.rm=TRUE) * 252 * 100
  round(to_annual, 1)
}

baseline <- calc_perf(ret, dts, "S1_Baseline")
cat(sprintf("  [Baseline] CAGR=%.2f%% | SR=%.3f | MDD=%.2f%% | Vol=%.2f%%\n",
    baseline$CAGR, baseline$SR, baseline$MDD, baseline$Vol))

# ── 3. DD Brake Overlay 함수 (C9 준수) ───────────────────────────────
apply_dd_brake <- function(ret, threshold, full_cash, label) {
  n_f <- length(ret)
  nav     <- cumprod(1 + ret)
  # dd_pct: 양수 (0 = 신고, 0.54 = 54% 낙폭)
  # 1 - nav/cummax(nav) 형태로 항상 [0, 1]
  dd_pct  <- 1 - nav / cummax(nav)

  # C9: t-1 lag — 당일 DD로 당일 비중 결정 금지
  dd_lag  <- c(0, head(dd_pct, -1))

  # Linear ramp: dd가 threshold(양수, 낙폭 시작점) 초과 시 현금화 시작
  # threshold: 낙폭 시작 (양수, 예: 0.08 = 8% 하락 시 감소)
  # full_cash: 완전 현금화 낙폭 (양수, 예: 0.25 = 25% 하락 시 0%)
  exposure <- ifelse(
    dd_lag <= threshold,  1.0,                           # DD < threshold: 완전 투자
    ifelse(
      dd_lag >= full_cash, 0.0,                          # DD > full_cash: 완전 현금
      1.0 - (dd_lag - threshold) / (full_cash - threshold)  # 선형 감소
    )
  )

  adj_ret <- ret * exposure

  # TO 계산 (exposure 변화 기반, overlay only)
  to_est <- calc_to_from_exposure(exposure)

  perf <- calc_perf(adj_ret, dts, label)
  perf$TO <- to_est
  perf$threshold <- threshold * 100   # 양수 %로 저장
  perf$full_cash <- full_cash * 100
  perf$exposure_mean <- round(mean(exposure) * 100, 1)
  perf$exposure_min  <- round(min(exposure) * 100, 1)
  perf$cash_days_pct <- round(mean(exposure == 0) * 100, 1)
  perf
}

# ── 4. 3 Variant 정의 및 계산 ────────────────────────────────────────
cat("\n[Step 2] 3 Variant DD Brake 계산 (C9: t-1 lag 적용)...\n")

# M1: 표준 (threshold 8%, full cash 25%) — 양수 낙폭 기준
m1 <- apply_dd_brake(ret, threshold=0.08, full_cash=0.25, "M1_Standard")

# M2: 완화 (threshold 10%, full cash 30%)
m2 <- apply_dd_brake(ret, threshold=0.10, full_cash=0.30, "M2_Relaxed")

# M3: 보수적 (threshold 6%, full cash 20%)
m3 <- apply_dd_brake(ret, threshold=0.06, full_cash=0.20, "M3_Conservative")

# ── 5. 결과 테이블 출력 ───────────────────────────────────────────────
cat("\n=== S5 Variant 비교 테이블 ===\n")
cat(sprintf("%-18s %7s %7s %7s %7s %6s %8s %8s\n",
    "Variant", "CAGR%", "SR", "MDD%", "Vol%", "TO%", "ExpMean", "CashDays"))
cat(strrep("-", 80), "\n")

results <- list(baseline, m1, m2, m3)
for (r in results) {
  to_str   <- if (!is.null(r$TO)) sprintf("%6.1f", r$TO) else "  N/A "
  exp_str  <- if (!is.null(r$exposure_mean)) sprintf("%6.1f%%", r$exposure_mean) else "  N/A  "
  cash_str <- if (!is.null(r$cash_days_pct)) sprintf("%6.1f%%", r$cash_days_pct) else "  N/A  "
  cat(sprintf("%-18s %7.2f %7.3f %7.2f %7.2f %s %s %s\n",
      r$label, r$CAGR, r$SR, r$MDD, r$Vol, to_str, exp_str, cash_str))
}
cat(strrep("-", 80), "\n")

# ── 6. Hard Fail 해소 여부 판단 ──────────────────────────────────────
cat("\n=== Hard Fail 해소 여부 (MDD < 45% 기준) ===\n")
for (r in list(m1, m2, m3)) {
  passed <- r$MDD > -45.0
  cat(sprintf("  [%s] MDD=%.2f%% → Hard Fail %s\n",
      r$label, r$MDD, ifelse(passed, "해소 (PASS)", "미해소 (FAIL)")))
}

# ── 7. 최적 Variant 선정 ─────────────────────────────────────────────
cat("\n=== 최적 Variant 선정 ===\n")
# 기준: (1) MDD < -45% 해소, (2) SR 최대, (3) CAGR 최대
candidates <- list(m1, m2, m3)
valid <- Filter(function(r) r$MDD > -45.0, candidates)

if (length(valid) == 0) {
  cat("  경고: 3 variant 모두 Hard Fail 미해소. 가장 낮은 MDD 선택.\n")
  best <- candidates[[which.min(sapply(candidates, function(r) r$MDD))]]
} else {
  # SR 최대 기준 선정
  best <- valid[[which.max(sapply(valid, function(r) r$SR))]]
  cat(sprintf("  Hard Fail 해소 variant %d건 → SR 최고 선정: %s\n",
      length(valid), best$label))
}

cat(sprintf("\n  [최적 Variant: %s]\n", best$label))
cat(sprintf("    Threshold: -%.0f%% 낙폭 시작 | Full Cash: -%.0f%% 완전현금\n",
    best$threshold, best$full_cash))
cat(sprintf("    CAGR: %.2f%% | SR: %.3f | MDD: %.2f%% | Vol: %.2f%%\n",
    best$CAGR, best$SR, best$MDD, best$Vol))
cat(sprintf("    평균 Exposure: %.1f%% | Cash Days: %.1f%%\n",
    best$exposure_mean, best$cash_days_pct))

# ── 8. Hurdle v2.2 간이 평가 ─────────────────────────────────────────
cat("\n=== Hurdle v2.2 간이 평가 (최적 Variant) ===\n")
hard_fail <- best$MDD < -45.0
cat(sprintf("  Hard Fail (MDD>45%%): %s\n", ifelse(hard_fail, "YES - 탈락", "NO - 통과")))
cat(sprintf("  Grade A  (SR≥0.8 & CAGR≥16%%): %s\n",
    ifelse(!hard_fail & best$SR >= 0.8 & best$CAGR >= 16.0, "충족", "미충족")))
cat(sprintf("  Grade A_NOVEL (SR≥0.6 & CAGR≥12%%): %s\n",
    ifelse(!hard_fail & best$SR >= 0.6 & best$CAGR >= 12.0, "충족", "미충족")))
grade_str <- if (hard_fail) "Hard Fail" else if (!hard_fail & best$SR >= 0.8 & best$CAGR >= 16.0) "A" else if (!hard_fail & best$SR >= 0.6 & best$CAGR >= 12.0) "A_NOVEL" else "B"
cat(sprintf("  예상 Grade: %s\n", grade_str))

# ── 9. S5 Artifact 저장 ──────────────────────────────────────────────
out_dir <- file.path(SCRIPT_DIR, "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

result_dt <- data.table(
  variant   = sapply(list(baseline, m1, m2, m3), function(r) r$label),
  threshold = c(NA, m1$threshold, m2$threshold, m3$threshold),
  full_cash = c(NA, m1$full_cash, m2$full_cash, m3$full_cash),
  CAGR      = sapply(list(baseline, m1, m2, m3), function(r) r$CAGR),
  SR        = sapply(list(baseline, m1, m2, m3), function(r) r$SR),
  MDD       = sapply(list(baseline, m1, m2, m3), function(r) r$MDD),
  Vol       = sapply(list(baseline, m1, m2, m3), function(r) r$Vol),
  TO        = c(NA, m1$TO, m2$TO, m3$TO),
  hard_fail = c(TRUE, m1$MDD < -45, m2$MDD < -45, m3$MDD < -45),
  best      = c(FALSE, m1$label == best$label, m2$label == best$label, m3$label == best$label)
)
fwrite(result_dt, file.path(out_dir, "s5_dd_brake_variants.csv"))
cat(sprintf("\n[저장] %s\n", file.path(out_dir, "s5_dd_brake_variants.csv")))

cat(sprintf("\n[STR_930 S5 DD Brake Mutation 완료]\n"))
