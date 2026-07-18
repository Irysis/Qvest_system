#==============================================================================
# test_optimizer_breadth.R — v6.1 Task#26 (L-192 Remediation) smoke test
# 2026-04-24 신규
# 2026-07-18 Test 6 추가 (RF-O5: p>max_names에서 HHI projection의 top-N 밖 누출
#            회귀 — FQ-057 NP4 engine defect task_1b9e50a3) + proj_root 경로 수리
#            (구 WSL 경로 실행 불가 → QM_ROOT env 우선, canonical fallback)
#
# 목적:
#   mvo_weights() 의 min_names / hhi_cap / alpha_winsor / max_names 제약 동작 검증.
#
# 실행:
#   Rscript -e 'source("08_Tests/portfolio/test_optimizer_breadth.R")'
#   (다른 체크아웃 검증 시: QM_ROOT=<root> 지정)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

# proj_root 해석 (worktree-aware): 실행된 체크아웃(현재 cwd)에 대상 파일이 있으면
# 그 체크아웃을 검증한다. ~/.Renviron 의 QM_ROOT 는 R 시작 시 shell 값을 덮어써
# 항상 main repo 를 가리키므로(2026-07-18 실측), QM_ROOT 를 무조건 따르면 worktree
# 편집을 검증하지 못한다 → cwd 우선, 없으면 QM_ROOT env, 그다음 canonical fallback.
proj_root <- local({
  marker <- "02_Infrastructure/portfolio/mean_variance_optimizer.R"
  cwd0 <- getwd()
  if (file.exists(file.path(cwd0, marker))) return(cwd0)
  r <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  if (file.exists(file.path(r, marker))) return(r)
  cwd0
})
setwd(proj_root)
cat(sprintf("[proj_root] %s\n", proj_root))

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
# Test 2: HHI cap enforcement (non-truncated regime: D <= max_names)
# 3종 고alpha (0.50/0.40/0.30) + 느슨한 bounds(0.50) → QP 자연 2종 50:50 집중.
# HHI=0.50 상태에서 cap=0.10 적용 시 projection이 universe 내로 breadth 확산해
# HHI≤cap 달성. max_names=N(=30)으로 truncation 미발동(RF-O5 무관 순수 HHI 경로).
# ★2026-07-18: 구 config(max_names=20 < N=30)은 절단을 유발했고, 구코드는
# projection이 n=30까지 확산해 HHI는 맞췄으나 max_names=20을 조용히 위반했다
# (RF-O5). 그 위반 행동을 정답으로 인코딩한 테스트였음 → non-truncated로 교정,
# 절단 regime의 RF-O5 준수는 Test 6이 담당.
# ══════════════════════════════════════════════════════════
cat("\n[Test 2] HHI cap enforcement (non-truncated: D<=max_names, concentration → projection)\n")
{
  N <- 30
  alpha <- c(0.50, 0.40, 0.30, rep(0.001, N - 3))
  names(alpha) <- sprintf("T%03d", seq_len(N))
  cv <- make_cov(N)

  # HHI cap 비활성 결과 (bounds 0.50 → 2종 50:50 집중 예상)
  res_nocap <- mvo_weights(alpha, cv,
                            lambda = 1.0, psi = 0.0,
                            bounds = c(0, 0.50),
                            max_names = N,           # = 30, truncation 미발동
                            min_names = 1L,
                            hhi_cap = 1.0,             # 사실상 disable
                            alpha_winsor = NA)

  # HHI cap 0.10 활성화
  res_cap <- mvo_weights(alpha, cv,
                          lambda = 1.0, psi = 0.0,
                          bounds = c(0, 0.50),
                          max_names = N,             # = 30, truncation 미발동
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
  .assert((res_cap$n_names %||% 999) <= N,
          sprintf("RF-O5: n_names (%d) <= max_names %d", res_cap$n_names %||% 999, N))
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
# Test 6: RF-O5 — max_names × hhi_cap 상호작용 (p > max_names)
# FQ-057 NP4 실측 결함(task_1b9e50a3) 회귀: 유니버스-레벨(p=300) MVO에서
# top-N 절단 후 HHI projection이 w=0 종목을 absorber로 써 top-N 밖으로
# 비중 누출 → n_names > max_names. 수리(v2.3) 후 support-제한 projection.
# ══════════════════════════════════════════════════════════
cat("\n[Test 6] RF-O5: p=300 + 집중해 → HHI projection이 max_names 하드캡 준수\n")
{
  P6 <- 300L
  # alpha-rank 상관 분산(top=저분산 → corner 집중) + 지수감쇠 알파:
  # 자연해 n=14, post-topN HHI≈0.149 > cap 0.10 (검증 배터리 실측 구성)
  vv <- pmin(0.008 + 0.0006 * (seq_len(P6) - 1), 0.03)
  cv6 <- diag(vv)
  rownames(cv6) <- colnames(cv6) <- sprintf("T%03d", seq_len(P6))
  a6 <- c(0.05 * exp(-(seq_len(14L) - 1) / 3.5), rep(-0.02, P6 - 14L))
  set.seed(911); a6 <- a6 + rnorm(P6, 0, 5e-4)
  names(a6) <- sprintf("T%03d", seq_len(P6))
  mvo6 <- function(hhi) mvo_weights(a6, cv6,
                                     lambda = 16.0, psi = 0.0,
                                     bounds = c(0, 0.20),
                                     max_names = 25,
                                     min_names = 10L,
                                     hhi_cap = hhi,
                                     alpha_winsor = NA)

  # precondition: cap 비활성 자연해가 실제로 HHI > cap (테스트 공허화 방지)
  res6_pre <- mvo6(NA)
  .assert(!is.null(res6_pre$weights) && (res6_pre$hhi %||% 0) > 0.10 + 1e-6,
          sprintf("precondition: natural post-topN HHI (%.4f) > cap 0.10",
                  res6_pre$hhi %||% NA))

  res6 <- mvo6(0.10)
  .assert(!is.null(res6$weights), "weights not NULL")
  .assert(isTRUE(res6$hhi_enforced), "hhi_enforced flag TRUE (projection 실발동)")
  .assert((res6$n_names %||% 999) <= 25,
          sprintf("RF-O5: n_names (%d) <= max_names 25", res6$n_names %||% 999))
  .assert(all(names(res6$weights) %in% names(res6_pre$weights)),
          "projection이 top-N support 밖 종목을 추가하지 않음")
  .assert(abs(sum(res6$weights %||% 0) - 1) < 1e-6,
          sprintf("Σw = 1 (actual=%.8f)", sum(res6$weights %||% 0)))
  .assert(max(res6$weights %||% 1) <= 0.20 + 1e-6,
          sprintf("max w (%.4f) <= bounds[2] 0.20", max(res6$weights %||% 1)))
  .assert((res6$hhi %||% 1) <= 0.10 + 1e-4,
          sprintf("HHI (%.4f) <= cap 0.10 + tol", res6$hhi %||% NA))

  # 6b: support-내 달성불가(1/k > cap) — support 확장 대신 정직 보고
  set.seed(931); a6b <- setNames(rnorm(P6, 0, 0.01), sprintf("T%03d", seq_len(P6)))
  a6b[1:4] <- c(0.30, 0.29, 0.28, 0.27)
  cv6b <- cv6
  res6b <- mvo_weights(a6b, cv6b,
                        lambda = 1.0, psi = 0.0,
                        bounds = c(0, 0.30),
                        max_names = 25,
                        min_names = 1L,
                        hhi_cap = 0.10,
                        alpha_winsor = NA)
  .assert((res6b$n_names %||% 999) <= 25,
          sprintf("6b RF-O5: n_names (%d) <= 25 (support 확장 없음)", res6b$n_names %||% 999))
  .assert("hhi_cap" %in% (res6b$infeasibility_report$violated_constraints %||% character(0)),
          "6b: support-내 달성불가 시 hhi_cap 위반 정직 flag")
  # ★Σw=1 보존: support 확장 불가로 HHI cap 미달이어도 Σw=1 hard constraint 는
  # 반드시 지켜야 함 (.project_hhi no-absorber 조기-break Σw 파손 회귀 — 2026-07-18).
  .assert(abs(sum(res6b$weights %||% 0) - 1) < 1e-6,
          sprintf("6b Σw = 1 (infeasible-in-support에서도 보존, actual=%.8f)",
                  sum(res6b$weights %||% 0)))
}

# ══════════════════════════════════════════════════════════
# Test 7: box-vertex 고정 포트폴리오 Σw 보존 (D <= max_names, non-truncated)
# 적대검증 L3 실측(2026-07-18): D×bounds[2] == target_sum 이면 전 종목이 상한에
# 고정되어 w=0 absorber 가 없다. 구코드 .project_hhi 는 top weight 감액 후 no-absorber
# break 하여 Σw=0.995(감액분 dec 소실)를 반환했다 — 이는 절단과 무관하게 D<=max_names
# 전체벡터 경로에서도 발생. 수리(v2.3 edit#2, 감액-전 판정) 후 Σw=1 보존.
# ══════════════════════════════════════════════════════════
cat("\n[Test 7] box-vertex 고정 포트폴리오 Σw 보존 (L3 회귀, D<=max_names)\n")
{
  # D=5, bounds[2]=0.20 → 5×0.20=1.0=target_sum → 유일해 = 전 종목 0.20 (w=0 부재).
  # HHI = 5×0.04 = 0.20 > hhi_cap 0.15 → projection 발동 → no-absorber.
  a7 <- c(A = 0.01, B = 0.02, C = 0.03, D = 0.04, E = 0.05)
  cv7 <- diag(0.04, 5); rownames(cv7) <- colnames(cv7) <- names(a7)
  res7 <- mvo_weights(a7, cv7,
                      lambda = 1.0, psi = 0.3,
                      bounds = c(0, 0.20),
                      max_names = 25,
                      min_names = 5L,
                      hhi_cap = 0.15,
                      alpha_winsor = 2.0)
  cat(sprintf("  n=%d Σw=%.10f hhi=%.6f (전 종목 상한 0.20 고정, cap 미달=정직 보고)\n",
              res7$n_names %||% 0, sum(res7$weights %||% 0), res7$hhi %||% NA))
  .assert(!is.null(res7$weights), "weights not NULL")
  .assert(abs(sum(res7$weights %||% 0) - 1) < 1e-6,
          sprintf("★Σw = 1 (구코드 0.995 회귀, actual=%.10f)", sum(res7$weights %||% 0)))
  .assert((res7$n_names %||% 999) <= 25,
          sprintf("n_names (%d) <= max_names 25", res7$n_names %||% 999))
  .assert(all((res7$weights %||% 1) <= 0.20 + 1e-9),
          "모든 weight <= bounds[2] 0.20 (box vertex)")
}

# ══════════════════════════════════════════════════════════
# Test 8: min_names > max_names 모순 config → fail-loud infeasible (RF-O5)
# 적대검증 L1 실측: min_names 보충이 max_names 절단 뒤에 실행되어 n_names 를 하드캡
# 위로 밀어 올리던 pre-existing RF-O5 hole. 수리(v2.3 edit#3) 후 precheck 로 차단.
# ══════════════════════════════════════════════════════════
cat("\n[Test 8] min_names > max_names → infeasible precheck (RF-O5)\n")
{
  N8 <- 50
  a8 <- rnorm(N8, 0, 0.01); names(a8) <- sprintf("T%03d", seq_len(N8))
  cv8 <- make_cov(N8)
  res8 <- mvo_weights(a8, cv8,
                      lambda = 1.0, psi = 0.0,
                      bounds = c(0, 0.20),
                      max_names = 20,
                      min_names = 25L,     # 25 > 20 = 모순
                      hhi_cap = 0.10,
                      alpha_winsor = NA)
  .assert(isTRUE(res8$infeasible), "infeasible flag TRUE")
  .assert(is.null(res8$weights),
          "weights NULL (모순 config는 산출 거부)")
  .assert("max_names" %in% (res8$infeasibility_report$violated_constraints %||% character(0)),
          "max_names in violated_constraints")
  # 정합성: min_names == max_names (경계, 비모순)는 정상 산출
  res8b <- mvo_weights(a8, cv8,
                       lambda = 1.0, psi = 0.0,
                       bounds = c(0, 0.20),
                       max_names = 20,
                       min_names = 20L,     # == max, 허용
                       hhi_cap = 1.0,
                       alpha_winsor = NA)
  .assert(!isTRUE(res8b$infeasible) && (res8b$n_names %||% 0) <= 20,
          sprintf("min_names == max_names 경계는 정상 (n=%d, infeasible=%s)",
                  res8b$n_names %||% 0, res8b$infeasible %||% FALSE))
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
