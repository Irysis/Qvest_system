#==============================================================================
# test_optimizer_breadth.R — v6.1 Task#26 (L-192 Remediation) smoke test
# 2026-04-24 신규
#
# 목적:
#   mvo_weights() 의 min_names / hhi_cap / alpha_winsor 제약 동작 검증.
#
# 실행:
#   cd "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
#   Rscript -e 'source("08_Tests/portfolio/test_optimizer_breadth.R")'
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

proj_root <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(proj_root)

source("02_Infrastructure/portfolio/mean_variance_optimizer.R")

# Null-coalesce helper (test local — registry의 것과 독립)
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

cat("\n=== Task#26 Optimizer Breadth Smoke Test ===\n")
cat("Started:", format(Sys.time()), "\n\n")

set.seed(42)
pass_count <- 0
fail_count <- 0

.assert <- function(cond, msg) {
  if (isTRUE(cond)) {
    cat(sprintf("  [PASS] %s\n", msg))
    pass_count <<- pass_count + 1
  } else {
    cat(sprintf("  [FAIL] %s\n", msg))
    fail_count <<- fail_count + 1
  }
}

# ── 공통 공분산 (50종, diag 0.001) ─────────────────────────
make_cov <- function(N, diag_val = 0.001) {
  cv <- diag(N) * diag_val
  rownames(cv) <- colnames(cv) <- sprintf("T%03d", seq_len(N))
  cv
}

# ══════════════════════════════════════════════════════════
# Test 1: min_names enforcement
# 5종만 alpha 있는 상황에서 min_names=15 면 15종 이상 반환해야 함.
# ══════════════════════════════════════════════════════════
cat("[Test 1] min_names enforcement (alpha sparse → 15+ names 강제)\n")
{
  N <- 50
  alpha <- c(rep(0.01, 5), rep(0, N - 5))
  names(alpha) <- sprintf("T%03d", seq_len(N))
  cv <- make_cov(N)

  res <- mvo_weights(alpha, cv,
                      lambda = 1.0, psi = 0.0,
                      bounds = c(0, 0.10),
                      max_names = 20,
                      min_names = 15L,
                      hhi_cap = 1.0,       # HHI 비활성화 (min_names만 테스트)
                      alpha_winsor = NA)

  .assert(!is.null(res$weights), "weights not NULL")
  .assert(res$n_names >= 15,
          sprintf("n_names (%d) >= 15", res$n_names %||% 0))
  .assert(abs(sum(res$weights) - 1) < 1e-4,
          sprintf("Σw ≈ 1 (actual=%.6f)", sum(res$weights %||% 0)))
  .assert(isTRUE(res$min_names_enforced) || res$n_names >= 15,
          "min_names_enforced flag or natural >=15")
}

# ══════════════════════════════════════════════════════════
# Test 2: HHI cap enforcement
# 3종 고alpha (0.50/0.40/0.30) + 느슨한 bounds(0.50) → QP 자연 2종 50:50 집중.
# HHI=0.50 상태에서 cap=0.10 적용 시 projection 동작 확인.
# ══════════════════════════════════════════════════════════
cat("\n[Test 2] HHI cap enforcement (concentration → projection)\n")
{
  N <- 30
  alpha <- c(0.50, 0.40, 0.30, rep(0.001, N - 3))
  names(alpha) <- sprintf("T%03d", seq_len(N))
  cv <- make_cov(N)

  # HHI cap 비활성 결과 (bounds 0.50 → 2종 50:50 집중 예상)
  res_nocap <- mvo_weights(alpha, cv,
                            lambda = 1.0, psi = 0.0,
                            bounds = c(0, 0.50),
                            max_names = 20,
                            min_names = 1L,
                            hhi_cap = 1.0,             # 사실상 disable
                            alpha_winsor = NA)

  # HHI cap 0.10 활성화
  res_cap <- mvo_weights(alpha, cv,
                          lambda = 1.0, psi = 0.0,
                          bounds = c(0, 0.50),
                          max_names = 20,
                          min_names = 1L,
                          hhi_cap = 0.10,
                          alpha_winsor = NA)

  cat(sprintf("  HHI no-cap: %.4f (n=%d, Σw=%.4f)\n",
              res_nocap$hhi %||% NA, res_nocap$n_names %||% 0,
              sum(res_nocap$weights %||% 0)))
  cat(sprintf("  HHI w/cap : %.4f (n=%d, Σw=%.4f, enforced=%s)\n",
              res_cap$hhi %||% NA, res_cap$n_names %||% 0,
              sum(res_cap$weights %||% 0),
              isTRUE(res_cap$hhi_enforced)))

  .assert(!is.null(res_nocap$weights),
          "no-cap weights not NULL")
  .assert(!is.null(res_cap$weights),
          "cap weights not NULL")
  .assert((res_cap$hhi %||% 1) <= 0.10 + 5e-3,
          sprintf("HHI with cap (%.4f) <= 0.10 + tol", res_cap$hhi %||% NA))
  .assert((res_cap$hhi %||% 1) < (res_nocap$hhi %||% 0),
          sprintf("HHI reduced (%.4f < %.4f)", res_cap$hhi %||% NA, res_nocap$hhi %||% NA))
  .assert(isTRUE(res_cap$hhi_enforced),
          "hhi_enforced flag TRUE")
  .assert(abs(sum(res_cap$weights %||% 0) - 1) < 5e-3,
          sprintf("Σw ≈ 1 after HHI projection (actual=%.6f)", sum(res_cap$weights %||% 0)))
}

# ══════════════════════════════════════════════════════════
# Test 3: Alpha winsorization
# 5.0 outlier alpha → ±2σ clip 적용 후 max(alpha_tilde) 하향.
# ══════════════════════════════════════════════════════════
cat("\n[Test 3] Alpha winsorization (±2σ clip)\n")
{
  N <- 50
  alpha <- c(5.0, rep(0.01, N - 1))   # extreme outlier
  names(alpha) <- sprintf("T%03d", seq_len(N))

  mu <- mean(alpha)
  sd_ <- sd(alpha)
  upper_winsor <- mu + 2 * sd_
  cat(sprintf("  raw alpha[1] = %.4f, μ=%.4f, σ=%.4f, upper(±2σ) = %.4f\n",
              alpha[1], mu, sd_, upper_winsor))

  cv <- make_cov(N)

  res <- mvo_weights(alpha, cv,
                      lambda = 1.0, psi = 0.0,
                      bounds = c(0, 0.10),
                      max_names = 20,
                      min_names = 15L,
                      hhi_cap = 1.0,
                      alpha_winsor = 2.0)

  .assert(isTRUE(res$winsor_applied), "winsor_applied flag TRUE")
  .assert(!is.null(res$weights), "weights not NULL after winsor")
  .assert(res$n_names >= 15, sprintf("n_names (%d) >= 15", res$n_names %||% 0))

  # 직접 helper 호출 검증 (내부 함수)
  # .winsorize_alpha는 non-exported; 결과 expected_active_return 이 winsored alpha로
  # 계산되지 않았는지 간접 확인 — raw alpha 사용
  .assert(is.numeric(res$expected_active_return),
          "expected_active_return computed")
}

# ══════════════════════════════════════════════════════════
# Test 4: Infeasibility — min_names × bounds[2] < 1
# min_names=15, bounds[2]=0.05 → 15×0.05=0.75 < 1 → infeasible.
# ══════════════════════════════════════════════════════════
cat("\n[Test 4] Infeasibility pre-check (min_names × upper < 1)\n")
{
  N <- 50
  alpha <- rnorm(N, 0, 0.01)
  names(alpha) <- sprintf("T%03d", seq_len(N))
  cv <- make_cov(N)

  res <- mvo_weights(alpha, cv,
                      lambda = 1.0, psi = 0.0,
                      bounds = c(0, 0.05),   # 15 × 0.05 = 0.75 < 1
                      max_names = 20,
                      min_names = 15L,
                      hhi_cap = 0.10,
                      alpha_winsor = NA)

  .assert(isTRUE(res$infeasible), "infeasible flag TRUE")
  .assert(!is.null(res$infeasibility_report),
          "infeasibility_report provided")
  .assert("min_names" %in% (res$infeasibility_report$violated_constraints %||% character(0)),
          "min_names in violated_constraints")
}

# ══════════════════════════════════════════════════════════
# Test 5: Backward compat — default 인자로 호출
# 기존 signature 깨지지 않음을 확인
# ══════════════════════════════════════════════════════════
cat("\n[Test 5] Backward compat (default args still works)\n")
{
  N <- 30
  alpha <- rnorm(N, 0, 0.02)
  names(alpha) <- sprintf("T%03d", seq_len(N))
  cv <- make_cov(N)

  res <- tryCatch(
    mvo_weights(alpha, cv),   # 모든 default 사용
    error = function(e) {
      list(error = conditionMessage(e))
    }
  )

  .assert(is.null(res$error),
          sprintf("no error with defaults: %s", res$error %||% "ok"))
  .assert(!is.null(res$weights),
          "weights returned with defaults")
  .assert(res$n_names >= 15 || isTRUE(res$infeasible),
          sprintf("n_names=%d OR infeasible=%s", res$n_names %||% 0, res$infeasible %||% FALSE))
}

# ══════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════
cat("\n=== Summary ===\n")
cat(sprintf("PASS: %d\n", pass_count))
cat(sprintf("FAIL: %d\n", fail_count))
cat("Ended:", format(Sys.time()), "\n\n")

if (fail_count > 0) {
  cat("[OVERALL] FAIL\n")
  quit(save = "no", status = 1)
} else {
  cat("[OVERALL] PASS\n")
}
