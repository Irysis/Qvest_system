#==============================================================================
# Entropy Pooling — Meucci (2010), Pfaff Ch.13.4.3
# Pfaff (2016) "Financial Risk Modelling and Portfolio Optimization with R"
#   Ch.13.4.3: Entropy Pooling (EP) — 최소 상대 엔트로피로 비선형 뷰 통합
# 참조: Meucci (2010) "Fully Flexible Views: Theory and Practice"
#        Risk 23(10): 97–102
#
# 핵심 수식 (Pfaff eq.13.71~13.74):
#   min_{p̃} Σ_j p̃_j * log(p̃_j / p_j)
#   s.t.  Ã p̃ = b̃  (등식: 기대값 뷰)
#         A  p̃ ≤ b  (부등식: 확률 범위 뷰)
#
# Dual form (BFGS):
#   f_d(λ,ν) = log(Σ_j p_j * exp(-1 - A'ν - Ã'λ)) + b'ν + b̃'λ
#
# 패키지: MASS (mvrnorm), stats (optim BFGS)
# 작성: Forge (2026-04-09)
# 사용처: S5 overlay, Judge S6 사후분포 검증
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(MASS)     # mvrnorm
})

# ─────────────────────────────────────────────────────────────────────────────
# 1. EP 최적화 — BFGS Dual Form
#    Pfaff eq.(13.68~13.73)
# ─────────────────────────────────────────────────────────────────────────────
#' @param prior_sim    J×N MC 시뮬레이션 행렬 (J 시나리오, N 자산)
#'                     각 행 = 1개 시나리오의 자산 수익률
#' @param Aeq          M_eq × J 등식 뷰 행렬  (Aeq %*% p̃ = beq)
#'                     NULL이면 등식 뷰 없음
#'                     주의: Pfaff 표기와 달리, 여기서 Aeq는 M×J (전치 형태)
#' @param beq          M_eq × 1 등식 RHS
#' @param A            M_ineq × J 부등식 뷰 행렬  (A %*% p̃ ≤ b)  — 미구현(복잡도)
#' @param b            M_ineq × 1 부등식 RHS
#' @param confidence   0~1 신뢰도 → 최종: p_c = (1-c)*prior + c*posterior
#'                     스칼라 또는 길이 1 벡터
#' @return list(posterior_prob, posterior_mean, posterior_cov, kl_div)
apply_entropy_pooling <- function(prior_sim,
                                   Aeq        = NULL,
                                   beq        = NULL,
                                   A          = NULL,
                                   b          = NULL,
                                   confidence = 0.5) {
  stopifnot(
    is.matrix(prior_sim),
    nrow(prior_sim) >= 10L,
    ncol(prior_sim) >= 1L,
    confidence >= 0, confidence <= 1
  )

  J <- nrow(prior_sim)
  N <- ncol(prior_sim)

  # 균등 사전 확률
  p0 <- rep(1 / J, J)

  # ── 뷰가 없으면 사전 분포 그대로 반환 ─────────────────────────────────────
  if (is.null(Aeq) && is.null(A)) {
    mu_post  <- colMeans(prior_sim)
    cov_post <- cov(prior_sim)
    return(list(
      posterior_prob = p0,
      posterior_mean = mu_post,
      posterior_cov  = cov_post,
      kl_div         = 0
    ))
  }

  # ── 등식 뷰 설정 ────────────────────────────────────────────────────────────
  # 반드시 합산 제약(Σp=1) 포함
  # Aeq 형태: M×J → 각 행이 하나의 뷰 제약 (Aeq[m,] %*% p̃ = beq[m])
  # 합산 제약: 모든 p̃ 합 = 1
  A_sum <- matrix(1, nrow = 1, ncol = J)
  b_sum <- 1.0

  if (!is.null(Aeq)) {
    stopifnot(is.matrix(Aeq), ncol(Aeq) == J, length(beq) == nrow(Aeq))
    Aeq_full <- rbind(A_sum, Aeq)
    beq_full  <- c(b_sum, beq)
  } else {
    Aeq_full <- A_sum
    beq_full  <- b_sum
  }

  M_eq <- nrow(Aeq_full)

  # ── BFGS Dual 목적함수 ──────────────────────────────────────────────────────
  # Pfaff eq.(13.72): f_d(λ) = Σ_j p_j * exp(Aeq_full[,j]'λ) - beq'λ
  # (최소화 형태: 음수 log-partition + 선형항)
  #
  # 정확한 dual:
  #   g(λ) = log(Σ_j p_j * exp(-Aeq_full %*% δ_j) ) + beq'λ
  #   where δ_j = j-th column of Aeq_full (= Aeq_full[,j])
  #
  # 주의: Aeq_full은 M×J → 각 열 = 시나리오 j에 대한 제약값 벡터

  dual_fn <- function(lam) {
    # lam: M_eq × 1 dual 변수
    # Aeq_full: M_eq × J  →  t(Aeq_full) %*% lam: J × 1 (시나리오별 기여)
    linear_combo <- as.numeric(t(Aeq_full) %*% lam)  # J×1
    # log-sum-exp trick for numerical stability
    lc_max           <- max(linear_combo)
    log_part         <- log(sum(p0 * exp(linear_combo - lc_max))) + lc_max
    obj              <- log_part - sum(beq_full * lam)
    obj
  }

  dual_gr <- function(lam) {
    linear_combo <- as.numeric(t(Aeq_full) %*% lam)  # J×1
    log_arg_shifted <- linear_combo - max(linear_combo)
    w_unnorm <- p0 * exp(log_arg_shifted)
    w_norm   <- w_unnorm / sum(w_unnorm)    # 정규화 사후 확률
    # gradient: Aeq_full %*% w_norm - beq_full (M_eq×1)
    as.numeric(Aeq_full %*% w_norm) - beq_full
  }

  # ── BFGS 최적화 ─────────────────────────────────────────────────────────────
  lam0 <- rep(0, M_eq)
  opt  <- tryCatch(
    optim(
      par     = lam0,
      fn      = dual_fn,
      gr      = dual_gr,
      method  = "BFGS",
      control = list(maxit = 1000, reltol = 1e-10, trace = 0)
    ),
    error = function(e) {
      warning("[EP] BFGS 실패: ", conditionMessage(e))
      list(par = lam0, convergence = 1)
    }
  )

  if (opt$convergence != 0) {
    warning("[EP] BFGS 수렴 실패 (code=", opt$convergence, "). 사전 분포 사용.")
    p_post <- p0
  } else {
    lam_star     <- opt$par
    linear_combo <- as.numeric(t(Aeq_full) %*% lam_star)
    lc_shifted   <- linear_combo - max(linear_combo)
    w_unnorm     <- p0 * exp(lc_shifted)
    p_post       <- w_unnorm / sum(w_unnorm)
  }

  # ── 신뢰도 블렌딩 (Meucci 2010 eq.11) ─────────────────────────────────────
  # p_c = (1-c)*p_prior + c*p_posterior
  c_val  <- confidence[1]
  p_final <- (1 - c_val) * p0 + c_val * p_post

  # ── 사후 통계량 ─────────────────────────────────────────────────────────────
  mu_post  <- as.numeric(t(prior_sim) %*% p_final)   # N×1
  # 확률가중 공분산: cov.wt()
  cov_post <- tryCatch(
    cov.wt(prior_sim, wt = p_final)$cov,
    error = function(e) cov(prior_sim)
  )

  # ── KL Divergence: Σ p̃ log(p̃/p) ─────────────────────────────────────────
  kl_div <- sum(p_final * log(p_final / p0 + 1e-300))

  list(
    posterior_prob = p_final,
    posterior_mean = mu_post,
    posterior_cov  = cov_post,
    kl_div         = kl_div
  )
}


# ─────────────────────────────────────────────────────────────────────────────
# 2. 변동성 뷰 생성 (GARCH 기반)
#    Pfaff eq.(13.74): Σ_j p̃_j * (X_{j,k})^2 = μ̂_k^2 + σ̂_k^2
#    → 2차 모멘트 뷰: E[X_k^2] = mu_k^2 + sigma_k^2
# ─────────────────────────────────────────────────────────────────────────────
#' @param prior_sim          J×N MC 시뮬레이션 행렬
#' @param garch_vol_forecast GARCH/ES 예측값. 두 형식 지원:
#'   (a) length-N named vector: N 자산별 예측 변동성 (연율화 일간 σ)
#'   (b) list(mu=N-vec, sigma=N-vec): 평균 + 변동성 별도
#'   tail_risk_engine.R의 forecast_conditional_es() 반환값 호환
#' @return list(Aeq, beq) — apply_entropy_pooling()에 직접 전달 가능
create_vol_views <- function(prior_sim, garch_vol_forecast) {
  stopifnot(
    is.matrix(prior_sim),
    nrow(prior_sim) >= 10L
  )

  J <- nrow(prior_sim)
  N <- ncol(prior_sim)

  # ── 입력 형식 정규화 ────────────────────────────────────────────────────────
  if (is.list(garch_vol_forecast)) {
    mu_k    <- as.numeric(garch_vol_forecast$mu)
    sigma_k <- as.numeric(garch_vol_forecast$sigma)
    if (length(mu_k)    != N) mu_k    <- rep(0, N)
    if (length(sigma_k) != N) sigma_k <- rep(0.01, N)
  } else {
    sigma_k <- as.numeric(garch_vol_forecast)
    if (length(sigma_k) != N) sigma_k <- rep(0.01, N)
    mu_k    <- colMeans(prior_sim)
  }

  # ── 2차 모멘트 뷰 행렬 ──────────────────────────────────────────────────────
  # Aeq[k, j] = X_{j,k}^2  (시나리오 j의 자산 k 제곱 수익률)
  # beq[k]    = mu_k^2 + sigma_k^2  (GARCH 예측 2차 모멘트)
  Aeq_vol <- t(prior_sim^2)       # N×J
  beq_vol <- mu_k^2 + sigma_k^2  # N×1

  list(Aeq = Aeq_vol, beq = beq_vol)
}


# ─────────────────────────────────────────────────────────────────────────────
# 3. EP → 포트폴리오 최적화
#    사후 확률 → 확률가중 평균/공분산 → Tangency portfolio
# ─────────────────────────────────────────────────────────────────────────────
#' @param prior_sim   J×N MC 시뮬레이션 행렬
#' @param views_Aeq   M×J 뷰 행렬 (create_vol_views()의 Aeq)
#' @param views_beq   M×1 뷰 RHS
#' @param confidence  뷰 신뢰도 0~1
#' @param rf          무위험 이자율 (연율화, 기본 0.03)
#' @param max_w       단일 자산 최대 비중 (기본 0.40)
#' @return list(weights, posterior_sr, posterior_mean, posterior_cov)
ep_portfolio <- function(prior_sim,
                          views_Aeq,
                          views_beq,
                          confidence = 0.5,
                          rf         = 0.03,
                          max_w      = 0.40) {
  stopifnot(is.matrix(prior_sim))

  N <- ncol(prior_sim)

  # ── EP 사후 분포 계산 ────────────────────────────────────────────────────────
  ep_result <- apply_entropy_pooling(
    prior_sim  = prior_sim,
    Aeq        = views_Aeq,
    beq        = views_beq,
    confidence = confidence
  )

  mu_post  <- ep_result$posterior_mean
  cov_post <- ep_result$posterior_cov

  # ── Tangency Portfolio (최대 Sharpe) ────────────────────────────────────────
  # Pfaff eq.(13.75): ω* = Σ^{-1}(μ - rf·1) / (1'Σ^{-1}(μ - rf·1))
  excess_mu <- mu_post - rf / 252   # 일간 무위험률

  # Sigma 수치 안정화
  cov_reg <- cov_post + diag(1e-8, N)

  w_tang <- tryCatch({
    cov_inv <- solve(cov_reg)
    w_raw   <- as.numeric(cov_inv %*% excess_mu)
    # 롱온리 제약: 음수 제거 후 정규화
    w_raw   <- pmax(w_raw, 0)
    if (sum(w_raw) < 1e-10) w_raw <- rep(1, N)
    w_clamp <- pmin(w_raw, max_w * sum(w_raw))  # 비중 상한 (정규화 전)
    w_clamp / sum(w_clamp)
  }, error = function(e) {
    warning("[EP Portfolio] Tangency 실패: ", conditionMessage(e), " → EW")
    rep(1 / N, N)
  })

  # ── 사후 Sharpe Ratio 계산 ──────────────────────────────────────────────────
  port_mu  <- sum(w_tang * mu_post)
  port_var <- as.numeric(t(w_tang) %*% cov_post %*% w_tang)
  port_sr  <- if (port_var > 0) (port_mu - rf / 252) / sqrt(port_var) else 0

  list(
    weights        = w_tang,
    posterior_sr   = port_sr * sqrt(252),   # 연율화
    posterior_mean = mu_post,
    posterior_cov  = cov_post,
    kl_div         = ep_result$kl_div
  )
}


# ─────────────────────────────────────────────────────────────────────────────
# 4. 독립 테스트 (source 직접 실행 시)
# ─────────────────────────────────────────────────────────────────────────────
if (sys.nframe() == 0L) {
  cat("=== Entropy Pooling — 단위 테스트 ===\n")
  set.seed(42)

  # ── 2자산 MC 시뮬레이션 ──────────────────────────────────────────────────────
  J     <- 5000
  N     <- 2
  mu0   <- c(0.0004, 0.0002)          # 일간 기대수익
  Sigma <- matrix(c(2e-4, 5e-5, 5e-5, 1e-4), 2, 2)
  sim   <- MASS::mvrnorm(J, mu0, Sigma)
  colnames(sim) <- c("Asset1", "Asset2")

  cat("\n[Prior] mean:", round(colMeans(sim) * 252, 4),
      "| vol:", round(apply(sim, 2, sd) * sqrt(252), 4), "\n")

  # ── 변동성 뷰 생성 ─────────────────────────────────────────────────────────
  # GARCH 예측: Asset1 변동성이 20% → sigma_daily = 0.20/sqrt(252)
  garch_forecast <- list(
    mu    = c(0.0005, 0.00015),
    sigma = c(0.20 / sqrt(252), 0.15 / sqrt(252))
  )

  vol_views <- create_vol_views(sim, garch_forecast)
  cat("\n[Vol Views] Aeq dim:", dim(vol_views$Aeq),
      "| beq:", round(vol_views$beq, 8), "\n")

  # ── EP 적용 ─────────────────────────────────────────────────────────────────
  cat("\n[EP confidence=0.7]\n")
  ep_r <- apply_entropy_pooling(
    prior_sim  = sim,
    Aeq        = vol_views$Aeq,
    beq        = vol_views$beq,
    confidence = 0.7
  )

  cat("  KL divergence:    ", round(ep_r$kl_div, 6), "\n")
  cat("  Posterior mean:   ", round(ep_r$posterior_mean * 252, 4), "(연율화)\n")
  cat("  Posterior vol:    ",
      round(sqrt(diag(ep_r$posterior_cov)) * sqrt(252), 4), "(연율화)\n")
  cat("  Sum(posterior_p): ", round(sum(ep_r$posterior_prob), 8), "\n")
  cat("  Max(posterior_p): ", round(max(ep_r$posterior_prob), 6), "\n")

  # ── EP 포트폴리오 비중 ────────────────────────────────────────────────────
  cat("\n[EP Portfolio]\n")
  port_r <- ep_portfolio(
    prior_sim  = sim,
    views_Aeq  = vol_views$Aeq,
    views_beq  = vol_views$beq,
    confidence = 0.7
  )
  cat("  weights:       ", round(port_r$weights, 4), "\n")
  cat("  posterior SR:  ", round(port_r$posterior_sr, 4), "(연율화)\n")
  cat("  KL div:        ", round(port_r$kl_div, 6), "\n")

  # ── 신뢰도 민감도 ────────────────────────────────────────────────────────────
  cat("\n[신뢰도 민감도]\n")
  for (conf in c(0.0, 0.3, 0.5, 0.7, 1.0)) {
    ep_c <- apply_entropy_pooling(sim, vol_views$Aeq, vol_views$beq, confidence = conf)
    cat(sprintf("  confidence=%.1f → KL=%.4f, mean=[%.5f, %.5f]\n",
                conf, ep_c$kl_div,
                ep_c$posterior_mean[1] * 252,
                ep_c$posterior_mean[2] * 252))
  }

  cat("\n=== 테스트 완료 ===\n")
}
