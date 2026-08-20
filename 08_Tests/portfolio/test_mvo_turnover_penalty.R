#==============================================================================
# test_mvo_turnover_penalty.R — v2.3 TC-aware MVO 배선 회귀 테스트
# 2026-07-18 신규 (FQ-057 NP4 dead-parameter 수리 검증)
#
# 검증 대상: 02_Infrastructure/portfolio/mean_variance_optimizer.R v2.3
#   [T1] 비활성 경로 불변 계약: (phi=0, cw=valid) ≡ (phi=0, cw=NULL) 전체 identical,
#        (phi>0, cw=NULL) 은 method 라벨 제외 identical — v2.2 bit-parity 계약의 영속형
#   [T2] 회전율 단조성: L1 turnover 가 phi 에 대해 비증가 + phi=15bps 비퇴화
#   [T3] no-trade region: 신호 미세변동을 충분한 phi 가 흡수 (w == w_prev)
#        + 임의 feasible w_prev 로의 full pull (phi 대)
#   [T4] n=2 해석해 대조: 1e-5 그리드 brute-force argmin 과 QP 일치 (내부/kink 양측)
#   [T5] 유니버스 정렬: 누락 이름(신규 진입)=0 처리 ≡ 명시 0-fill / 밖 이름 무시
#   [T6] mvo_grid_search current_weights 관통 + tc 필드 라벨 정확성
#   [T7] w_prev 가 ub 위반(0.40>0.20)이어도 강제 트림 해 존재 + 제약 준수
#
# 실행:
#   Rscript -e 'source("08_Tests/portfolio/test_mvo_turnover_penalty.R")'
#   (다른 체크아웃 검증 시: QM_ROOT=<root> 지정)
#==============================================================================

suppressPackageStartupMessages({
  library(quadprog)
})

# proj_root 해석 (worktree-aware, sibling test_optimizer_breadth.R와 동일 패턴):
# ~/.Renviron 의 QM_ROOT 는 R 시작 시 shell 값을 덮어써 항상 main repo 를 가리키므로
# (2026-07-18 실측), 무조건 따르면 worktree 편집이 아닌 main 파일을 검증한다 →
# cwd(실행된 체크아웃) 우선, 없으면 QM_ROOT env, 그다음 canonical fallback.
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

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

cat("\n=== v2.3 TC-aware MVO Turnover Penalty Test ===\n")
cat("Root:", proj_root, "\n")
cat("Started:", format(Sys.time()), "\n\n")

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

# ── 공통 헬퍼 ─────────────────────────────────────────────
make_case <- function(n, k = 3, seed) {
  set.seed(seed)
  B <- matrix(rnorm(n * k), n, k)
  Sig <- tcrossprod(B) * 4e-4 + diag(runif(n, 2e-3, 1.2e-2))
  tk <- sprintf("T%03d", seq_len(n))
  dimnames(Sig) <- list(tk, tk)
  alpha <- setNames(0.01 * rnorm(n), tk)
  list(alpha = alpha, Sig = Sig, tk = tk)
}
full_w <- function(res, tk) {
  w <- setNames(numeric(length(tk)), tk)
  if (!is.null(res$weights)) w[names(res$weights)] <- res$weights
  w
}
l1 <- function(w, wp) sum(abs(w - wp))

# ══════════════════════════════════════════════════════════
# [T1] 비활성 경로 불변 계약
# ══════════════════════════════════════════════════════════
cat("[T1] inactive-path invariance (phi=0 / cw=NULL routing)\n")
{
  cs <- make_case(60, seed = 101)
  wp <- setNames(numeric(60), cs$tk); wp[1:20] <- 0.05
  args_base <- list(alpha = cs$alpha, cov_matrix = cs$Sig, lambda = 2.0, psi = 0.3,
                    bounds = c(0, 0.20), max_names = 25, min_names = 15L,
                    hhi_cap = 0.10, alpha_winsor = 2.0)
  rA <- do.call(mvo_weights, c(args_base, list(turnover_penalty = 0.0)))
  rB <- do.call(mvo_weights, c(args_base, list(turnover_penalty = 0.0,
                                               current_weights = wp)))
  rC <- do.call(mvo_weights, c(args_base, list(turnover_penalty = 0.5)))
  strip_method <- function(r) r[setdiff(names(r), "method")]
  .assert(identical(rA, rB), "(phi=0, cw=valid) identical to (phi=0, cw=NULL) - full object")
  .assert(identical(strip_method(rA), strip_method(rC)),
          "(phi=0.5, cw=NULL) identical ex-method-label (penalty = constant under sum=1)")
  .assert(is.null(rA$tc_penalty_active) && is.null(rB$tc_penalty_active) &&
            is.null(rC$tc_penalty_active),
          "no tc_* fields on inactive path (return object unchanged vs v2.2)")
}

# ══════════════════════════════════════════════════════════
# [T2] 회전율 단조성 (phi grid)
# ══════════════════════════════════════════════════════════
cat("\n[T2] turnover monotonicity in phi\n")
{
  cs2 <- make_case(25, seed = 202)
  wp2 <- setNames(numeric(25), cs2$tk); wp2[1:20] <- 0.05
  phis <- c(0, 0.0015, 0.005, 0.02, 0.10)
  run2 <- function(ph) {
    mvo_weights(cs2$alpha, cs2$Sig, lambda = 2.0, psi = 0.3,
                bounds = c(0, 0.20), max_names = 25, min_names = 1L,
                hhi_cap = NA, alpha_winsor = NA,
                current_weights = wp2, turnover_penalty = ph)
  }
  res_list <- lapply(phis, run2)
  tos <- vapply(res_list, function(r) l1(full_w(r, cs2$tk), wp2), numeric(1))
  cat(sprintf("  turnover(phi=%s): %s\n",
              paste(phis, collapse = "/"), paste(sprintf("%.4f", tos), collapse = " -> ")))
  .assert(all(diff(tos) <= 1e-8), "turnover non-increasing across phi grid")
  .assert(tos[length(tos)] < tos[1] - 1e-6,
          sprintf("strict reduction at max phi (%.4f -> %.4f)", tos[1], tos[length(tos)]))
  .assert(tos[2] > 1e-3,
          sprintf("phi=15bps still trades (%.4f) - penalty prunes, not freezes", tos[2]))
  r_mid <- res_list[[3]]
  manual_l1 <- l1(full_w(r_mid, cs2$tk), wp2)
  .assert(abs((r_mid$trade_l1_final %||% NA) - manual_l1) < 5e-5,
          sprintf("trade_l1_final consistent with weights (%.6f vs %.6f, tol 5e-5 = nonzero filter)",
                  r_mid$trade_l1_final %||% NA, manual_l1))
  .assert(isTRUE(r_mid$tc_penalty_active) && (r_mid$phi_used %||% 0) == 0.005,
          "tc_penalty_active + phi_used fields present on active path")
}

# ══════════════════════════════════════════════════════════
# [T3] no-trade region + full pull
# ══════════════════════════════════════════════════════════
cat("\n[T3] no-trade region (signal jiggle absorbed by phi)\n")
{
  cs2 <- make_case(25, seed = 202)
  run3 <- function(av, cw, ph) {
    mvo_weights(av, cs2$Sig, lambda = 2.0, psi = 0.3,
                bounds = c(0, 0.20), max_names = 25, min_names = 1L,
                hhi_cap = NA, alpha_winsor = NA,
                current_weights = cw, turnover_penalty = ph)
  }
  r0 <- run3(cs2$alpha, NULL, 0)
  wp3 <- full_w(r0, cs2$tk)
  set.seed(303)
  alpha_j <- cs2$alpha + 0.0005 * rnorm(25)   # 신호 5% 스케일 미세변동
  r_free <- run3(alpha_j, NULL, 0)
  r_hold <- run3(alpha_j, wp3, 0.02)
  to_free <- l1(full_w(r_free, cs2$tk), wp3)
  to_hold <- l1(full_w(r_hold, cs2$tk), wp3)
  .assert(to_free > 1e-3,
          sprintf("precondition: phi=0 re-opt trades on jiggle (%.4f)", to_free))
  .assert(to_hold < 1e-6,
          sprintf("no-trade region: phi=0.02 absorbs jiggle (%.2e ~ 0)", to_hold))
  # full pull: 임의 feasible w_prev, phi 大 -> w == w_prev
  wp2 <- setNames(numeric(25), cs2$tk); wp2[1:20] <- 0.05
  r_pull <- run3(cs2$alpha, wp2, 1.0)
  .assert(l1(full_w(r_pull, cs2$tk), wp2) < 1e-6,
          "full pull: phi=1.0 returns exactly w_prev (feasible attractor)")
}

# ══════════════════════════════════════════════════════════
# [T4] n=2 해석해 brute-force 대조
# ══════════════════════════════════════════════════════════
cat("\n[T4] n=2 brute-force grid vs QP\n")
{
  a2 <- c(T001 = 0.012, T002 = 0.010)
  S2 <- matrix(c(0.010, 0.003, 0.003, 0.020), 2, 2,
               dimnames = list(names(a2), names(a2)))
  wp4 <- c(T001 = 0.70, T002 = 0.30)
  lam4 <- 2.0
  # 손계산: 무펜널티 최적 x1*=0.75, kink(0.70)에서 |grad|=0.0024
  #   -> phi=0.0005 (2*phi<0.0024): 내부해 x1=(0.036-0.001)/0.048=0.729167
  #   -> phi=0.0100 (2*phi>0.0024): kink 포획 x1=0.70 (no-trade)
  brute <- function(ph) {
    g <- seq(0, 1, by = 1e-5)
    quad <- (lam4 / 2) * (g^2 * S2[1, 1] + 2 * g * (1 - g) * S2[1, 2] +
                            (1 - g)^2 * S2[2, 2])
    lin <- g * a2[1] + (1 - g) * a2[2]
    pen <- ph * (abs(g - wp4[1]) + abs((1 - g) - wp4[2]))
    g[which.min(quad - lin + pen)]
  }
  run4 <- function(ph) {
    r <- mvo_weights(a2, S2, lambda = lam4, psi = 0, bounds = c(0, 1),
                     max_names = 25, min_names = 1L, hhi_cap = NA,
                     alpha_winsor = NA, current_weights = wp4,
                     turnover_penalty = ph)
    full_w(r, names(a2))[1]
  }
  for (ph in c(0.0005, 0.01)) {
    x_bf <- brute(ph); x_qp <- run4(ph)
    .assert(abs(x_qp - x_bf) < 5e-5,
            sprintf("phi=%.4f: QP x1=%.6f vs brute-force %.6f (tol 5e-5)", ph, x_qp, x_bf))
  }
  r4 <- mvo_weights(a2, S2, lambda = lam4, psi = 0, bounds = c(0, 1),
                    max_names = 25, min_names = 1L, hhi_cap = NA,
                    alpha_winsor = NA, current_weights = wp4,
                    turnover_penalty = 0.0005)
  x1 <- full_w(r4, names(a2))[1]
  .assert(abs((r4$trade_l1_final %||% NA) - 2 * abs(x1 - 0.70)) < 1e-8,
          "trade_l1_final == 2*|x1 - 0.70| (L1 exactness, complementarity held)")
}

# ══════════════════════════════════════════════════════════
# [T5] 유니버스 정렬 (신규 진입 / 탈락 이름)
# ══════════════════════════════════════════════════════════
cat("\n[T5] universe alignment of current_weights\n")
{
  cs5 <- make_case(30, seed = 505)
  wp_full <- setNames(numeric(30), cs5$tk); wp_full[1:10] <- 0.10
  wp_miss <- wp_full[-(1:2)]              # T001,T002 이름 자체 누락 -> 0 취급 기대
  wp_zero <- wp_full; wp_zero[1:2] <- 0   # 명시 0
  wp_extra <- c(wp_miss, c(ZZZ1 = 0.05, ZZZ2 = 0.03))  # 유니버스 밖 이름
  run5 <- function(cw) {
    mvo_weights(cs5$alpha, cs5$Sig, lambda = 2.0, psi = 0.3,
                bounds = c(0, 0.20), max_names = 25, min_names = 1L,
                hhi_cap = NA, alpha_winsor = NA,
                current_weights = cw, turnover_penalty = 0.01)
  }
  rM <- run5(wp_miss); rZ <- run5(wp_zero); rX <- run5(wp_extra)
  .assert(identical(rM$weights, rZ$weights), "missing names == explicit zero-fill")
  .assert(identical(rM$weights, rX$weights), "out-of-universe names ignored")
  rE <- tryCatch(run5(unname(wp_full)), error = function(e) e)
  .assert(inherits(rE, "error"), "unnamed current_weights rejected with error")
}

# ══════════════════════════════════════════════════════════
# [T6] mvo_grid_search 관통
# ══════════════════════════════════════════════════════════
cat("\n[T6] mvo_grid_search current_weights pass-through\n")
{
  cs2 <- make_case(25, seed = 202)
  wp2 <- setNames(numeric(25), cs2$tk); wp2[1:20] <- 0.05
  gs <- mvo_grid_search(cs2$alpha, cs2$Sig,
                        lambda_grid = c(1.0, 2.0), phi_grid = c(0.0, 0.05),
                        bounds = c(0, 0.20), max_names = 25, min_names = 1L,
                        hhi_cap = NA, alpha_winsor = NA,
                        current_weights = wp2)
  pick <- function(lam, ph) {
    hit <- which(vapply(gs$all_results,
                        function(r) isTRUE(r$lambda == lam && r$phi == ph), logical(1)))
    gs$all_results[[hit[1]]]
  }
  c00 <- pick(2.0, 0.0); c05 <- pick(2.0, 0.05)
  to00 <- l1(full_w(c00, cs2$tk), wp2)
  to05 <- l1(full_w(c05, cs2$tk), wp2)
  .assert(to05 <= to00 + 1e-8,
          sprintf("grid cell phi=0.05 turnover (%.4f) <= phi=0 (%.4f)", to05, to00))
  .assert(isTRUE(c05$tc_penalty_active) && is.null(c00$tc_penalty_active),
          "tc field only on phi>0 cells (phi=0 cell = inactive path)")
  .assert(gs$n_tested == 4, "grid tested 2x2 cells")
}

# ══════════════════════════════════════════════════════════
# [T7] ub 위반 w_prev — 강제 트림
# ══════════════════════════════════════════════════════════
cat("\n[T7] ub-violating w_prev (0.40 > ub 0.20) forced trim\n")
{
  cs2 <- make_case(25, seed = 202)
  wp7 <- setNames(numeric(25), cs2$tk)
  wp7[1] <- 0.40; wp7[2:13] <- 0.05
  r7 <- mvo_weights(cs2$alpha, cs2$Sig, lambda = 2.0, psi = 0.3,
                    bounds = c(0, 0.20), max_names = 25, min_names = 1L,
                    hhi_cap = NA, alpha_winsor = NA,
                    current_weights = wp7, turnover_penalty = 0.05)
  w7 <- full_w(r7, cs2$tk)
  .assert(!is.null(r7$weights) && abs(sum(w7) - 1) < 1e-6, "solution exists + sum(w)=1")
  .assert(max(w7) <= 0.20 + 1e-8, "ub respected (forced trim executed)")
  .assert(w7[1] >= 0.20 - 1e-6,
          sprintf("trim stops at ub (w1=%.4f, no over-selling beyond forced)", w7[1]))
  .assert((r7$trade_l1_final %||% 0) >= 0.4 - 1e-6,
          sprintf("trade_l1_final >= 0.40 (forced sell 0.20 + forced buy 0.20): %.4f",
                  r7$trade_l1_final %||% 0))
}

# ══════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════
cat("\n=== Summary ===\n")
cat(sprintf("PASS: %d\n", pass_count))
cat(sprintf("FAIL: %d\n", fail_count))
cat("Ended:", format(Sys.time()), "\n\n")

# 2026-08-20: 배터리는 마지막 유효 JSON 줄만 읽는다 — 이 줄이 없어 미편입 상태였다.
cat(sprintf("{\"test\":\"test_mvo_turnover_penalty\",\"pass\":%d,\"fail\":%d,\"total\":%d}
", pass_count, fail_count, pass_count + fail_count))
if (fail_count > 0) {
  cat("[OVERALL] FAIL\n")
  quit(save = "no", status = 1)
} else {
  cat("[OVERALL] PASS\n")
}
