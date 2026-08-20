#==============================================================================
# test_msm_daily_refit.R — Session 70 Step 8
#
# 검증 범위:
#   1. .hmm_em() EM loop 합성 daily returns 로 수렴 — mu/sigma 유한값 반환
#   2. 2-state HMM label — higher sigma = stress state (회귀 후 식별 OK)
#   3. gamma probabilities 범위 [0, 1]
#
# 주의:
#   - compute_hmm_daily_signal() 전체 파이프라인 실행은 benchmark.parquet
#     실 파일을 요구하므로, 여기서는 .hmm_em 코어 + Crisis_Prob 범위만 검증
#     (full pipeline 은 run_all.R orchestrator 에서 실 데이터로 smoke test).
#==============================================================================

suppressPackageStartupMessages({
  library(testthat)
  library(data.table)
})

if (!exists("PROJECT_ROOT")) {
  # [fix 2026-07-25] 구 하드코딩 WSL 폴백 제거. 이 가드는 환경변수를 보지 않아
  # 단독 실행 시 무조건 없는 경로로 가 source(config.R) 가 죽었고,
  # 그 결과 러너가 "0 passed / 0 failed (of 0 total)" 을 성공처럼 냈다.
  # 후보를 **표지 파일 검증**으로 확인한다 — 존재검사로 정체성검사를 대체하지 않는다.
  .qv_marker <- "02_Infrastructure/config.R"
  .qv_argv <- commandArgs(trailingOnly = FALSE)
  .qv_f <- grep("^--file=", .qv_argv, value = TRUE)
  .qv_sd <- if (length(.qv_f)) dirname(sub("^--file=", "", .qv_f[1])) else ""
  for (.qv_c in c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
                  Sys.getenv("QM_ROOT", unset = ""),
                  if (nzchar(.qv_sd)) file.path(.qv_sd, "..", "..") else "",
                  getwd())) {
    if (nzchar(.qv_c) && file.exists(file.path(.qv_c, .qv_marker))) {
      PROJECT_ROOT <- .qv_c
      break
    }
  }
  if (!exists("PROJECT_ROOT")) {
    stop(sprintf(paste0("[regime] PROJECT_ROOT 해석 실패 — 표지 '%s' 를 가진 후보 없음.\n",
                        "  cwd=%s / CLAUDE_PROJECT_DIR='%s' / QM_ROOT='%s'"),
                 .qv_marker, getwd(),
                 Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
                 Sys.getenv("QM_ROOT", unset = "")))
  }
  rm(list = intersect(ls(), c(".qv_marker", ".qv_argv", ".qv_f", ".qv_sd", ".qv_c")))
}

# ── Load .hmm_em from regime_hmm.R ──────────────────────────────────
hmm_env <- new.env()
source(file.path(PROJECT_ROOT, "02_Infrastructure/regime/regime_hmm.R"),
       local = hmm_env)
hmm_em <- hmm_env$.hmm_em

pass_count <- 0L
fail_count <- 0L
.assert <- function(cond, msg) {
  if (isTRUE(cond)) {
    cat(sprintf("  [PASS] %s\n", msg))
    pass_count <<- pass_count + 1L
  } else {
    cat(sprintf("  [FAIL] %s\n", msg))
    fail_count <<- fail_count + 1L
  }
}

cat("\n── Assertions ──\n")

# ── Synthetic 2-regime daily returns ────────────────────────────────
set.seed(7)
n_days <- 1000L
# Simulate mixture: 800 normal days + 200 stress days interspersed
labels <- rep("normal", n_days)
stress_days <- sample(seq_len(n_days), 200L)
labels[stress_days] <- "stress"

rets <- numeric(n_days)
rets[labels == "normal"] <- rnorm(sum(labels == "normal"),
                                    mean = 0.0005, sd = 0.010)
rets[labels == "stress"] <- rnorm(sum(labels == "stress"),
                                    mean = -0.002, sd = 0.025)

cat(sprintf("[test_msm] synth returns: n=%d, normal=%d, stress=%d\n",
            n_days, sum(labels == "normal"), sum(labels == "stress")))

# ── Run .hmm_em ─────────────────────────────────────────────────────
fit <- tryCatch(
  hmm_em(rets, max_iter = 50L, tol = 1e-5,
         mu_init = c(0.0005, -0.002),
         sigma_init = c(0.010, 0.025)),
  error = function(e) { cat("fit err:", e$message, "\n"); NULL }
)

.assert(!is.null(fit), ".hmm_em returns non-NULL result")

if (!is.null(fit)) {
  .assert(length(fit$mu) == 2 && all(is.finite(fit$mu)),
          sprintf("mu 2-vector finite (mu = [%.4f, %.4f])",
                  fit$mu[1], fit$mu[2]))

  .assert(length(fit$sigma) == 2 && all(is.finite(fit$sigma)) &&
            all(fit$sigma > 0),
          sprintf("sigma 2-vector finite & positive (sigma = [%.4f, %.4f])",
                  fit$sigma[1], fit$sigma[2]))

  # Stress state = higher sigma identification
  sigma_diff <- abs(fit$sigma[2] - fit$sigma[1])
  .assert(sigma_diff > 1e-4,
          sprintf("2 states distinct (|σ2 - σ1| = %.5f)", sigma_diff))

  # gamma matrix shape
  .assert(!is.null(fit$gamma) && is.matrix(fit$gamma) &&
            nrow(fit$gamma) == n_days && ncol(fit$gamma) == 2,
          sprintf("gamma matrix shape (%d × 2)",
                  if (!is.null(fit$gamma)) nrow(fit$gamma) else 0L))

  # gamma in [0, 1] + rows sum to 1
  if (!is.null(fit$gamma)) {
    in_range <- all(fit$gamma >= 0 & fit$gamma <= 1, na.rm = TRUE)
    .assert(in_range, "gamma probabilities ∈ [0, 1]")

    row_sums <- rowSums(fit$gamma)
    .assert(all(abs(row_sums - 1) < 1e-6, na.rm = TRUE),
            "gamma row sums = 1")
  }

  # Crisis_Prob = gamma[, stress_state]
  stress_state <- if (fit$sigma[2] > fit$sigma[1]) 2L else 1L
  if (!is.null(fit$gamma)) {
    crisis_prob <- fit$gamma[, stress_state]
    .assert(all(crisis_prob >= 0 & crisis_prob <= 1, na.rm = TRUE),
            "Crisis_Prob = gamma[, stress_state] ∈ [0, 1]")

    # Sanity: crisis_prob mean should be > 0.05 (we injected 20% stress)
    .assert(mean(crisis_prob, na.rm = TRUE) > 0.05,
            sprintf("Crisis_Prob mean > 5%% (actual: %.1f%%)",
                    100 * mean(crisis_prob, na.rm = TRUE)))
  }
}

cat(sprintf("\n── test_msm_daily_refit: %d passed, %d failed ──\n\n",
            pass_count, fail_count))

# 2026-08-20: 배터리는 마지막 유효 JSON 줄만 읽는다 — 이 줄이 없어 미편입 상태였다.
cat(sprintf("{\"test\":\"test_msm_daily_refit\",\"pass\":%d,\"fail\":%d,\"total\":%d}
", pass_count, fail_count, pass_count + fail_count))
if (fail_count > 0) stop(sprintf("test_msm_daily_refit: %d failures", fail_count))
invisible(list(pass = pass_count, fail = fail_count))
