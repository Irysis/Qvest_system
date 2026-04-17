#==============================================================================
# Copula Opinion Pooling (COP) — Pfaff Ch.13.4.2
# Pfaff (2016) "Financial Risk Modelling and Portfolio Optimization with R"
#   Ch.13.4.2: Copula Opinion Pooling (Meucci 2010)
# 참조: Meucci (2010) "Fully Flexible Views: Theory and Practice"
#        Risk 23(10): 97–102
#        Meucci (2011) "A New Breed of Copulas for Risk and Portfolio Management"
#        Risk 24(9): 122–126
#
# 핵심 알고리즘 (Pfaff Ch.13.4.2, 5단계):
#   1. 뷰 좌표 변환:  V = prior_sim %*% t(P̄)  (P̄: K×N pick 행렬)
#   2. 비모수 CDF + copula C 추정 (empirical quantile)
#   3. 뷰별 확률 대체: F̃_{j,k} = c_k * F̂(W_{j,k}) + (1-c_k) * rank(j)/(J+1)
#   4. 사후 분위수 회복 (copula 구조 보존 역변환)
#   5. 역변환: M̃ = Ṽ %*% solve(t(P̄))
#
# 패키지: MASS (mvrnorm), stats (ecdf, quantile)
# 작성: Forge (2026-04-09)
# 사용처: S5 뷰 통합, Judge S6 copula 구조 검증
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(MASS)     # mvrnorm
})

# ─────────────────────────────────────────────────────────────────────────────
# 1. COP 5단계 알고리즘
#    Pfaff Ch.13.4.2, Meucci (2010) Algorithm 1
# ─────────────────────────────────────────────────────────────────────────────
#' @param prior_sim   J×N MC 시뮬레이션 행렬 (J 시나리오, N 자산)
#' @param P           K×N pick 행렬 (BL 형식: 각 행 = 하나의 뷰 포트폴리오)
#'                    long-only 뷰: P[k, l] = 1 (l번 자산 매수)
#'                    long-short 뷰: P[k, l] = 1, P[k, m] = -1
#' @param q           K×1 뷰 수익률 (각 뷰 포트폴리오의 목표 기대값)
#' @param confidence  K×1 또는 스칼라 뷰별 신뢰도 (0~1)
#'                    0 = 뷰 무시, 1 = 뷰 완전 신뢰
#' @return list(posterior_sim, posterior_mean, posterior_cov)
apply_cop_views <- function(prior_sim,
                             P,
                             q,
                             confidence = rep(0.5, nrow(P))) {
  stopifnot(
    is.matrix(prior_sim),
    nrow(prior_sim) >= 20L,
    is.matrix(P),
    ncol(P) == ncol(prior_sim),
    length(q) == nrow(P)
  )

  J <- nrow(prior_sim)
  N <- ncol(prior_sim)
  K <- nrow(P)     # 뷰 수

  # confidence를 K 길이로 맞춤
  if (length(confidence) == 1L) confidence <- rep(confidence, K)
  stopifnot(length(confidence) == K, all(confidence >= 0), all(confidence <= 1))

  # ── Step 1: 뷰 좌표 변환 ────────────────────────────────────────────────────
  # P̄: K×N (정규화: 각 행 단위 벡터)
  P_bar <- .normalize_pick_matrix(P)  # K×N

  # V = prior_sim %*% t(P_bar)  →  J×K (시나리오 × 뷰)
  V <- prior_sim %*% t(P_bar)         # J×K

  # ── Step 2: 비모수 경험적 CDF 추정 ─────────────────────────────────────────
  # 각 뷰 k마다 경험적 CDF F̂_k
  F_hat <- matrix(0, nrow = J, ncol = K)
  for (k in seq_len(K)) {
    v_k    <- V[, k]
    ranks  <- rank(v_k, ties.method = "average")
    F_hat[, k] <- ranks / (J + 1)   # (0, 1) 범위의 empirical probability
  }

  # ── Step 3: 뷰 도입 — 뷰 분포와 혼합 ──────────────────────────────────────
  # F̃_{j,k} = c_k * F_view(W_{j,k}) + (1-c_k) * F̂(V_{j,k})
  # W_{j,k}: 뷰 목표 q[k]를 평균으로 하는 분포에서의 값
  #
  # COP 단순화: 뷰 확률을 q[k] 기준 단조 이동으로 표현
  # Pfaff eq.(13.62): 뷰 CDF = 경험적 + shift
  F_tilde <- matrix(0, nrow = J, ncol = K)

  for (k in seq_len(K)) {
    c_k    <- confidence[k]
    q_k    <- q[k]
    v_k    <- V[, k]

    if (c_k < 1e-8) {
      # 뷰 무시: 사전 분포 그대로
      F_tilde[, k] <- F_hat[, k]
    } else {
      # 뷰 CDF: q_k를 중위수로 갖는 분포
      # 경험적 CDF에 뷰 목표 위치를 반영
      # COP step 3: F̃_{j,k} = (1-c_k)*F̂_{j,k} + c_k * F_view_{j,k}
      # F_view: q_k가 0.5 분위수가 되도록 재조정된 CDF
      mu_v     <- mean(v_k)
      sd_v     <- sd(v_k)
      shift    <- q_k - mu_v            # 목표 평균으로 이동
      v_view_k <- v_k + shift           # 이동된 시나리오 값
      # 이동된 값의 경험적 CDF (원래 V의 분위수 격자로 보간)
      f_view_k <- .emp_cdf(v_view_k, v_k)

      F_tilde[, k] <- (1 - c_k) * F_hat[, k] + c_k * f_view_k
    }

    # [0,1] 범위 강제
    F_tilde[, k] <- pmin(pmax(F_tilde[, k], 1e-6), 1 - 1e-6)
  }

  # ── Step 4: copula 구조 보존하며 사후 시뮬레이션 생성 ────────────────────
  # 사후 Ṽ: F̃를 역분위수 변환으로 사후 값 복원
  V_tilde <- matrix(0, nrow = J, ncol = K)
  for (k in seq_len(K)) {
    v_k     <- V[, k]
    # 경험적 분위수 함수: F̃_{j,k}에 해당하는 원래 분포 분위수
    V_tilde[, k] <- as.numeric(quantile(v_k, probs = F_tilde[, k], type = 7))
  }

  # ── Step 5: 역변환 — 뷰 좌표에서 자산 좌표로 ───────────────────────────────
  # M̃ = Ṽ %*% pinv(t(P_bar))
  # P_bar가 정방 행렬이 아닌 경우 Moore-Penrose 유사역행렬 사용
  M_tilde <- .invert_cop(V_tilde, P_bar, prior_sim)   # J×N

  # ── 사후 통계량 ─────────────────────────────────────────────────────────────
  mu_post  <- colMeans(M_tilde)
  cov_post <- cov(M_tilde)

  list(
    posterior_sim  = M_tilde,
    posterior_mean = mu_post,
    posterior_cov  = cov_post
  )
}

# ── 내부: pick 행렬 정규화 ─────────────────────────────────────────────────
# 각 행을 L2 단위 벡터로 정규화
.normalize_pick_matrix <- function(P) {
  for (k in seq_len(nrow(P))) {
    row_norm <- sqrt(sum(P[k, ]^2))
    if (row_norm > 1e-10) P[k, ] <- P[k, ] / row_norm
  }
  P
}

# ── 내부: 경험적 CDF 보간 ─────────────────────────────────────────────────
# x_eval에 대한 x_base의 경험적 CDF 값 반환
.emp_cdf <- function(x_eval, x_base) {
  J    <- length(x_base)
  # ECDF of base distribution, evaluated at x_eval points
  cdf_fn <- ecdf(x_base)
  as.numeric(cdf_fn(x_eval))
}

# ── 내부: 역변환 (Step 5) ────────────────────────────────────────────────────
# K < N: underdetermined → 사전 분포의 잔차 부분 보존
# Pfaff의 접근: prior_sim에서 뷰 방향 성분 교체, 나머지 보존
.invert_cop <- function(V_tilde, P_bar, prior_sim) {
  J <- nrow(prior_sim)
  N <- ncol(prior_sim)
  K <- nrow(P_bar)

  if (K == 0L) return(prior_sim)

  # P_bar의 열 공간 (K×N) 기반 사영
  # 완전 역변환: M̃ = prior_sim + (V_tilde - V_prior) %*% P_bar
  # (P_bar 방향 성분만 교체, 나머지 보존)
  V_prior <- prior_sim %*% t(P_bar)   # J×K (원래 뷰 값)
  delta_V <- V_tilde - V_prior         # J×K (뷰 변화량)

  # 자산 공간으로 역투영: delta_M = delta_V %*% P_bar  (J×N)
  # P_bar는 정규화된 단위 벡터이므로 t(P_bar) = P_bar^{-1} in row direction
  delta_M <- delta_V %*% P_bar         # J×N

  M_tilde <- prior_sim + delta_M

  M_tilde
}


# ─────────────────────────────────────────────────────────────────────────────
# 2. BL 뷰를 COP 형식으로 변환
#    Black-Litterman P/q/Omega → COP prior_sim + apply_cop_views()
# ─────────────────────────────────────────────────────────────────────────────
#' @param mu_prior    N×1 사전 기대수익 벡터 (BL 평형 수익률)
#' @param Sigma_prior N×N 사전 공분산 행렬
#' @param P           K×N BL pick 행렬
#' @param q           K×1 BL 뷰 수익률
#' @param Omega       K×K 뷰 불확실성 행렬 (NULL이면 비례 설정)
#' @param n_sim       MC 시나리오 수 (기본 10000)
#' @param confidence  K×1 또는 스칼라 뷰 신뢰도
#' @return apply_cop_views() 반환값과 동일
bl_to_cop <- function(mu_prior,
                       Sigma_prior,
                       P,
                       q,
                       Omega      = NULL,
                       n_sim      = 10000,
                       confidence = rep(0.5, nrow(P))) {
  stopifnot(
    is.numeric(mu_prior), length(mu_prior) >= 1L,
    is.matrix(Sigma_prior),
    nrow(Sigma_prior) == length(mu_prior),
    is.matrix(P), ncol(P) == length(mu_prior),
    length(q) == nrow(P)
  )

  N <- length(mu_prior)
  K <- nrow(P)

  # ── MC 시뮬레이션 생성 ────────────────────────────────────────────────────
  # BL 사전 분포: X ~ N(mu_prior, Sigma_prior)
  # 수치 안정화: Sigma가 PD인지 확인
  Sigma_reg <- Sigma_prior + diag(1e-8, N)

  prior_sim <- tryCatch(
    MASS::mvrnorm(n = n_sim, mu = mu_prior, Sigma = Sigma_reg),
    error = function(e) {
      warning("[BL→COP] mvrnorm 실패: ", conditionMessage(e), " → 대각 공분산")
      sd_vec <- sqrt(pmax(diag(Sigma_prior), 1e-8))
      matrix(rnorm(n_sim * N, mean = rep(mu_prior, each = n_sim),
                   sd = rep(sd_vec, each = n_sim)),
             nrow = n_sim, ncol = N, byrow = FALSE)
    }
  )

  if (!is.null(colnames(Sigma_prior))) {
    colnames(prior_sim) <- colnames(Sigma_prior)
  }

  # ── COP 적용 ──────────────────────────────────────────────────────────────
  apply_cop_views(
    prior_sim  = prior_sim,
    P          = P,
    q          = q,
    confidence = confidence
  )
}


# ─────────────────────────────────────────────────────────────────────────────
# 3. COP → 포트폴리오 최적화
#    사후 시뮬레이션 → Tangency portfolio (EP와 동일한 구조)
# ─────────────────────────────────────────────────────────────────────────────
#' @param cop_result  apply_cop_views() 또는 bl_to_cop() 반환값
#' @param rf          무위험 이자율 (연율화)
#' @param max_w       단일 자산 최대 비중
#' @return list(weights, posterior_sr)
cop_portfolio <- function(cop_result, rf = 0.03, max_w = 0.40) {
  stopifnot(
    is.list(cop_result),
    !is.null(cop_result$posterior_mean),
    !is.null(cop_result$posterior_cov)
  )

  mu_post  <- cop_result$posterior_mean
  cov_post <- cop_result$posterior_cov
  N        <- length(mu_post)

  excess_mu <- mu_post - rf / 252
  cov_reg   <- cov_post + diag(1e-8, N)

  w_tang <- tryCatch({
    cov_inv <- solve(cov_reg)
    w_raw   <- as.numeric(cov_inv %*% excess_mu)
    w_raw   <- pmax(w_raw, 0)
    if (sum(w_raw) < 1e-10) w_raw <- rep(1, N)
    w_clamp <- pmin(w_raw, max_w * sum(w_raw))
    w_clamp / sum(w_clamp)
  }, error = function(e) {
    warning("[COP Portfolio] Tangency 실패: ", conditionMessage(e), " → EW")
    rep(1 / N, N)
  })

  port_mu  <- sum(w_tang * mu_post)
  port_var <- as.numeric(t(w_tang) %*% cov_post %*% w_tang)
  port_sr  <- if (port_var > 0) (port_mu - rf / 252) / sqrt(port_var) else 0

  list(
    weights      = w_tang,
    posterior_sr = port_sr * sqrt(252)
  )
}


# ─────────────────────────────────────────────────────────────────────────────
# 4. 독립 테스트 (source 직접 실행 시)
# ─────────────────────────────────────────────────────────────────────────────
if (sys.nframe() == 0L) {
  cat("=== Copula Opinion Pooling — 단위 테스트 ===\n")
  set.seed(42)

  # ── 2자산 MC 시뮬레이션 ──────────────────────────────────────────────────────
  J <- 5000
  N <- 2
  mu0   <- c(0.0004, 0.0002)
  Sigma <- matrix(c(2e-4, 6e-5, 6e-5, 1e-4), 2, 2)
  sim   <- MASS::mvrnorm(J, mu0, Sigma)
  colnames(sim) <- c("Asset1", "Asset2")

  cat("\n[Prior] mean:", round(colMeans(sim) * 252, 4),
      "| vol:", round(apply(sim, 2, sd) * sqrt(252), 4), "\n")
  cat("  corr:", round(cor(sim)[1,2], 4), "\n")

  # ── COP 직접 적용 (방향성 뷰) ───────────────────────────────────────────────
  cat("\n[COP Direct] Asset1 상승 뷰 (q=0.0006/day)\n")
  P1 <- matrix(c(1, 0), nrow = 1)   # Asset1 매수 뷰
  q1 <- c(0.0006)                    # 뷰 기대수익 (사전 0.0004보다 높음)

  cop1 <- apply_cop_views(
    prior_sim  = sim,
    P          = P1,
    q          = q1,
    confidence = 0.7
  )

  cat("  사전 mean:   ", round(colMeans(sim) * 252, 4), "\n")
  cat("  사후 mean:   ", round(cop1$posterior_mean * 252, 4), "\n")
  cat("  사전 vol:    ", round(apply(sim, 2, sd) * sqrt(252), 4), "\n")
  cat("  사후 vol:    ",
      round(sqrt(diag(cop1$posterior_cov)) * sqrt(252), 4), "\n")
  cat("  사후 corr:   ", round(cov2cor(cop1$posterior_cov)[1, 2], 4), "\n")

  # ── Long-Short 뷰: Asset1 - Asset2 = 0.0003/day ───────────────────────────
  cat("\n[COP Long-Short] Asset1 - Asset2 = 0.0003/day\n")
  P2 <- matrix(c(1, -1), nrow = 1)
  q2 <- c(0.0003)

  cop2 <- apply_cop_views(
    prior_sim  = sim,
    P          = P2,
    q          = q2,
    confidence = 0.5
  )
  spread_prior <- mean(sim[, 1] - sim[, 2]) * 252
  spread_post  <- cop2$posterior_mean[1] - cop2$posterior_mean[2]
  cat("  사전 spread (연율화):", round(spread_prior, 4), "\n")
  cat("  사후 spread (연율화):", round(spread_post * 252, 4), "\n")
  cat("  뷰 목표 (연율화):    ", round(q2 * 252, 4), "\n")

  # ── BL → COP 변환 ───────────────────────────────────────────────────────────
  cat("\n[BL→COP] Black-Litterman 형식 입력\n")
  cop3 <- bl_to_cop(
    mu_prior    = mu0,
    Sigma_prior = Sigma,
    P           = P1,
    q           = q1,
    confidence  = 0.7
  )
  cat("  사후 mean:", round(cop3$posterior_mean * 252, 4), "\n")

  # ── COP Portfolio ──────────────────────────────────────────────────────────
  cat("\n[COP Portfolio]\n")
  port1 <- cop_portfolio(cop1)
  cat("  weights:", round(port1$weights, 4), "\n")
  cat("  posterior SR:", round(port1$posterior_sr, 4), "(연율화)\n")

  # ── 신뢰도 민감도 ────────────────────────────────────────────────────────────
  cat("\n[신뢰도 민감도] Asset1 뷰 q=0.0006\n")
  for (conf in c(0.0, 0.3, 0.5, 0.7, 1.0)) {
    cop_c <- apply_cop_views(sim, P1, q1, confidence = conf)
    cat(sprintf("  confidence=%.1f → mean=[%.5f, %.5f] (연율화)\n",
                conf,
                cop_c$posterior_mean[1] * 252,
                cop_c$posterior_mean[2] * 252))
  }

  cat("\n=== 테스트 완료 ===\n")
}
