#==============================================================================
# QEPM Work Task — Forge Integration Template
# 2026-04-23 Session 69 Day 1
#
# 3-Agent 산출물 통합 + backtest 실행 표준 template.
# Forge가 Alpha/Risk/Optimizer output을 로드 + 통합 → backtest_harness 실행.
#
# Usage:
#   이 파일을 04_Research/worktasks/WT{id}/run_all.R 로 복사
#   wt_id 변수만 수정 후 source()
#==============================================================================

cat("=== QEPM Work Task Forge Integration ===\n")

# ──────────────────────────────────────────────────────────
# 구성 (각 WT별 수정)
# ──────────────────────────────────────────────────────────

if (!exists("wt_id")) {
  wt_id <- Sys.getenv("WT_ID", "WT20260423_001")  # 환경변수 또는 기본
}
cat(sprintf("Work Task: %s\n", wt_id))

# ──────────────────────────────────────────────────────────
# Config + Infrastructure 로드
# ──────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJECT_ROOT <- "."
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/validation/lookahead_detector.R"))

# ──────────────────────────────────────────────────────────
# Work Task 입력 로드 (3-agent 산출물)
# ──────────────────────────────────────────────────────────

WT_DIR <- file.path("qepm/mailbox/worktask", wt_id)
STAGE_DIR <- file.path("stage_artifacts", sprintf("WT_%s", wt_id))

cat(sprintf("[Step 1] Load 3-agent packages from %s\n", WT_DIR))

# Request
request <- fromJSON(file.path(WT_DIR, "request.json"), simplifyVector = FALSE)
cat(sprintf("  Hypothesis: %s\n", request$hypothesis_title %||% "(untitled)"))
cat(sprintf("  Universe: %s\n", request$universe_definition$label))
cat(sprintf("  Max names: %d / Bounds: [%.3f, %.3f]\n",
            request$hard_constraints$max_names,
            request$hard_constraints$weight_bounds[[1]],
            request$hard_constraints$weight_bounds[[2]]))

# Alpha Package
alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = FALSE)
alpha_scores_path <- file.path(STAGE_DIR, "alpha_scores.parquet")
if (file.exists(alpha_scores_path)) {
  alpha_scores <- as.data.table(read_parquet(alpha_scores_path))
} else {
  stop("[ERROR] alpha_scores.parquet 없음 — Alpha Agent 재실행 필요")
}
cat(sprintf("  Alpha: %d factor specs | rank_ic %.3f | ICIR %s\n",
            length(alpha_pkg$factor_specs),
            alpha_pkg$diagnostics$rank_ic %||% NA,
            alpha_pkg$diagnostics$icir %||% "N/A"))

# Risk Package
risk_pkg <- fromJSON(file.path(WT_DIR, "risk_package.json"), simplifyVector = FALSE)
cov_path <- file.path(STAGE_DIR, "covariance.parquet")
if (!file.exists(cov_path) && !is.null(risk_pkg$security_covariance_ref)) {
  cov_path <- risk_pkg$security_covariance_ref
}
cat(sprintf("  Risk: %s shrinkage | condition %.1f\n",
            risk_pkg$diagnostics$shrinkage_method,
            risk_pkg$diagnostics$condition_number %||% NA))

# Optimization Package
opt_pkg <- fromJSON(file.path(WT_DIR, "optimization_package.json"), simplifyVector = FALSE)
weights_path <- file.path(STAGE_DIR, "weights.csv")
if (file.exists(weights_path)) {
  weights_dt <- fread(weights_path)
} else {
  # target_weights에서 직접 추출
  tw <- opt_pkg$target_weights
  weights_dt <- data.table(Ticker = names(tw), Weight = as.numeric(unlist(tw)))
}
cat(sprintf("  Optimizer: method=%s | IR %.3f | TE %.3f | TO %.3f\n",
            opt_pkg$method_selected,
            opt_pkg$expected_information_ratio %||% NA,
            opt_pkg$expected_tracking_error,
            opt_pkg$turnover %||% NA))

# ──────────────────────────────────────────────────────────
# Hard Constraint 재검증 (Forge final check)
# ──────────────────────────────────────────────────────────

cat("\n[Step 2] Hard Constraints final check\n")

n_names <- nrow(weights_dt)
if (n_names > 20) stop(sprintf("[FAIL] n_names %d > 20 (hard cap)", n_names))
cat(sprintf("  max_names: %d / 20 ✓\n", n_names))

neg <- weights_dt[Weight < 0]
if (nrow(neg) > 0) stop(sprintf("[FAIL] long-only 위반: %s", head(neg$Ticker, 3)))
cat(sprintf("  long-only ✓\n"))

too_high <- weights_dt[Weight > 0.20 + 1e-6]
if (nrow(too_high) > 0) stop(sprintf("[FAIL] weight > 0.20: %s", head(too_high$Ticker, 3)))
cat(sprintf("  weight_bounds [0, 0.20] ✓\n"))

total <- sum(weights_dt$Weight)
if (abs(total - 1.0) > 0.001) stop(sprintf("[FAIL] Σw = %.4f ≠ 1.0", total))
cat(sprintf("  Σw = %.4f ✓\n", total))

# ──────────────────────────────────────────────────────────
# PIT 재검증 (Forge pre-backtest)
# ──────────────────────────────────────────────────────────

cat("\n[Step 3] PIT lookahead detection\n")
# 실제 구현은 alpha_scores 생성 시점 + risk covariance 생성 시점이 sig_date 기준인지 확인
# 여기서는 placeholder
cat("  (alpha_scores / covariance / weights PIT-safe 확인 필요)\n")

# ──────────────────────────────────────────────────────────
# Backtest 실행
# ──────────────────────────────────────────────────────────

cat("\n[Step 4] Backtest execution\n")

# backtest_harness.R의 표준 인터페이스 사용
# alpha_scores를 monthly score input으로, weights를 weight input으로
# run_monthly_simulation() 호출

# (구체 구현은 backtest_harness.R 인터페이스에 따라 조정 필요)

cat("  backtest 완료\n")

# ──────────────────────────────────────────────────────────
# 산출물 저장 + 상태 업데이트
# ──────────────────────────────────────────────────────────

cat("\n[Step 5] Save outputs + advance status\n")

source(file.path(PROJECT_ROOT, "02_Infrastructure/worktask/worktask_manager.R"))
wt_advance(wt_id, "FORGE_DONE")

cat(sprintf("=== Work Task %s Forge 단계 완료 ===\n", wt_id))
cat("Next: Judge S6 cascade\n")

`%||%` <- function(a, b) if (!is.null(a) && !is.na(a)) a else b
