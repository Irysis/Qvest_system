# skew_rp_bruder_kostyuchyk_roncalli_2022.R — 왜도(점프) 위험 예산 포트폴리오(2026-11-11 · 비중 카탈로그 후보)
#
# 원문: Bruder, B., Kostyuchyk, N. & Roncalli, T. (2016/2022) "Risk Parity Portfolios with Skewness Risk: An Application to
#   Factor Investing and Alternative Risk Premia" — arXiv 2202.10721 (https://arxiv.org/abs/2202.10721 · LaTeX 원본으로 읽음).
#
# 논문 메커니즘(원문 절 · 식 — 식 번호는 LaTeX 라벨):
#   · §2.1.2 혼합 표현: 수익 R 은 정상 국면 N(μ, Σ)(확률 1 − λ)과 점프 국면 N(μ + μ̃, Σ + Σ̃)(확률 λ)의 2성분 가우시안 혼합.
#     'jumps occur simultaneously for all assets' — 점프는 모든 자산에서 동시에 일어난다. Remark: 'we set dt equal to one'.
#   · §2.2 식 (eq:jump1): 포트폴리오 수익 x'R 은 1차원 혼합 — μ₁(x) = x'μ · σ₁²(x) = x'Σx · μ₂(x) = x'(μ + μ̃) · σ₂²(x) = x'(Σ + Σ̃)x.
#   · §3.1 식 (eq:es1): ES_α(x) = (1 − λ)·φ(VaR_α(x), μ₁(x), σ₁(x)) + λ·φ(VaR_α(x), μ₂(x), σ₂(x)),
#       φ(a, b, c) = c/(1 − α)·ϕ((a + b)/c) − b/(1 − α)·Φ(−(a + b)/c),
#       VaR 는 '(1 − λ)Φ((VaR + μ₁)/σ₁) + λΦ((VaR + μ₂)/σ₂) = α' 의 근(손실 L = −R 기준).
#   · §3.2 식 (eq:rc1): 위험 기여 RC(x) = ϖ₁/(1 − α)(x∘δ₁) + ϖ₂/(1 − α)(x∘δ₂) − 1/(1 − α)((1 − λ)(x∘μ)Φ(−h₁) + λ(x∘(μ + μ̃))Φ(−h₂)),
#       h_i = (VaR + μ_i)/σ_i · ϖ_i = π_i ϕ(h_i)/σ_i · δ₁ · δ₂ 는 원문 그대로(아래 .skrp_es). ★δ 안의 VaR 항들은 합하면 0 이 된다
#       (VaR 조건의 미분 Σπ_iϕ(h_i)dh_i = 0) — 그래서 RC = x∘(Σ_i π_i[ϕ(h_i)·∂σ_i − Φ(−h_i)·∂μ_i])/(1 − α) 와 같다(시험 b 가 대조).
#   · §3.3 식 (eq:rb1): 위험 예산 RC_i(x) = b_i·R(x) · b_i > 0 · x_i ≥ 0 · Σb = Σx = 1. 풀이(§3.3.2 원문 'we use the following
#     optimization program (Roncalli, 2013; Spinu, 2013)'): y* = argmin ES_α(y) − Σ b_i ln y_i (y ≥ 0) · x* = y*/Σy*.
#   · §3.3.1 존재 · 유일성 정리: 'If α ≥ max(α⁻, λ), the RB portfolio exists and is unique' · α⁻ 는
#       (1 − λ)/(1 − α⁻)·ϕ(Φ⁻¹((α⁻ − λ)/(1 − λ))) + λΦ⁻¹((α⁻ − λ)/(1 − λ)) = (1 + λ)·SR₁⁺ 의 근(부록 7.6.3).
#     'in most cases, the vector of expected returns μ is equal to zero ... the maximum Sharpe ratio is equal to zero, implying that
#     there is always a unique solution' — μ = 0 이면 SR₁⁺ = 0.
#   · §4.2: 'we assume that the expected returns μ_i are equal to zero ... In the case of the Gaussian model, we obtain the traditional
#     ERC portfolio based on the volatility risk measure (Maillard et al., 2010)' — λ = 0 · μ = 0 이면 ES = c·σ(x) 라 변동성 ERC 와 같다.
#   · §4.3 점프 판정: 1차원 문턱법 'J_t = 1 ⇔ |R_t − v| ≥ r*' · 각주 'The parameter v is generally set to zero' · 필터링법(π̂_t ≥ π*)은
#     부록 7.7 이 '1차원에서는 문턱법과 동치'임을 보이고, 그 각주가 문턱의 배수를 'According to Ait-Sahalia (2004), the
#     multiplicative factor κ_σ takes its value between 3.5 and 4.0' 로 준다(J_t = 1 ⇔ |y_t + β/α| ≥ κ_σ·σ√dt).
#   · 부록 7.9 필터링 알고리즘 3단계: 정상 국면 μ̂ · Σ̂ = 점프 아닌 날만으로 '1/n_t Σ 1{π̂ ≤ π̄}(y − μ̂)(y − μ̂)ᵀ'(나눗수 n_t) ·
#     'To initialize the algorithm, we can use the traditional Gaussian estimates'(점프 없음에서 시작).
#   · §2.4 EM M-단계: π_j = Σ_t π_{j,t}/T · μ_j · Σ_j = 국면 가중 평균 · 공분산(여기서는 판정이 0/1 이라 가중 = 지시함수).
#
# KR 롱온리 사상(종목 선택은 엔진 · 이 어댑터는 선택된 ≤ 25종의 비중만):
#   ① 점프 = 시장 공통 한 요인. 25종 × 252일에서 점프 국면 모수(μ̃ n개 · Σ̃ n(n+1)/2개)는 점프일 몇 개로 식별되지 않는다.
#      그래서 받은 종목들의 균등가중 일별 수익 y_t 에 1차원 문턱 판정을 적용하고(부록 7.7 의 1차원 동치), 정상 국면 σ 는
#      부록 7.9 처럼 점프 아닌 날로 다시 재며 판정이 바뀌지 않을 때까지 되풀이한다(가우시안 추정 · 점프 없음에서 시작).
#   ② 점프 국면 모수는 점프일 표본에서 M-단계(§2.4)로: λ = n_jump/T · 시장 점프 평균 μ̃_m = mean_J(y) − μ̂_y ·
#      시장 점프 분산 σ̃_m² = max(var_J(y) − σ̂_y², 0)(식 em-pdf3 의 Σ₂ = Σ + Σ̃ · Σ̃ ⪰ 0 · 나눗수 |J|).
#      식별 제한(가장 단순한 것) = 점프 진폭 Z = b̃·J_m(계수 1개 요인): b̃_i = Σ_J (R_i − μ̂_i)e_t / Σ_J e_t² (e_t = y_t − μ̂_y · 점프일
#      초과수익의 원점 회귀) → μ̃ = b̃ μ̃_m · Σ̃ = b̃b̃ᵀ σ̃_m². 균등가중 평균 b̃ = 1(균등가중 포트폴리오의 점프 = 시장 점프 그대로).
#      점프일이 하루면 σ̃_m² = 0 · μ̃_i = 그날 초과수익(직접 평균과 같다).
#   ③ ES 의 정상 국면 기대수익 μ = 0(§4.2 · §4.3 각주) — 엔진의 ctx$mu 는 쓰지 않는다. 그래서 SR₁⁺ = 0 이고 존재 조건은 α ≥ max(α⁻, λ).
#   ④ 예산 균등 b_i = 1/n(과제 지시 · §3.3.2 ERC).
#   ⑤ 낙하(조용한 낙하 금지 — 진단 줄 fallback=): 점프일 0(nojump) · 정상 국면 표본 ≤ n 또는 Σ̂ 비양정치(estfail) · 존재 조건 실패
#      (noexist) · 점프 모형 풀이 미수렴(solver) → 가우시안 ES 위험 패리티 = 창 전체 표본 공분산(나눗수 T)의 λ = 0 모형
#      (μ = 0 이라 변동성 ERC 와 같은 해 — §4.2). 가우시안 풀이마저 미수렴이면 이름을 부르고 멈춘다(래퍼 EW 폴백 · 로그).
#
# 논문이 준 것 / 이 구현이 정한 것
#   [논문] α = 0.99(§3.3.1 'In general, α is equal to 99%' · §4.2 'using the 99% expected shortfall') · v = 0(§4.3 각주) ·
#          κ_σ ∈ [3.5, 4.0](부록 7.7 각주 — Ait-Sahalia 2004 인용) · μ = 0(§4.2) · dt = 1(§2.1.2 Remark) · 정상 국면 공분산 나눗수 n_t
#          (부록 7.9) · M-단계 π = 평균 사후확률(§2.4) · 풀이식 argmin ES − Σb ln y(§3.3.2) · 존재 조건 α ≥ max(α⁻, λ)(§3.3.1).
#   [구현] κ = 4.0(논문 인용 범위의 상단 — 가우시안 창에서 4σ 오탐 기대 횟수 252 × 6.3e-5 ≈ 0.016 · 3.5 면 ≈ 0.12 · 성과를 보고
#          고르지 않았다) · 점프 = 균등가중 시장 수익 1요인(과제 설계) · 점프 진폭 계수 b̃ = 점프일 원점 회귀 · 판정 = 필터링 π* 대신
#          1차원 문턱(필터링은 π · μ̃ · Σ̃ 를 미리 알아야 하는데 논문은 그것을 전기간 표본으로 정했다 — 우리 축에선 시점 위반이라 창 안
#          문턱 되풀이로 대신했다 · 그래서 π* = 30%(§4.3)는 쓰지 않는다) · 일별 수익 그대로(§4.1 은 '일별은 문제 · 주간/월간 선호'라
#          했지만 ctx 계약이 일별 창이다) · 낙하 처리(논문은 존재 조건이 깨질 때의 처리를 말하지 않는다 — 가장 단순한 가우시안
#          ES 위험 패리티) · 뉴턴 풀이(수치 헤시안 · 아르미호 되짚기)와 수렴 기준(수치 상수).
#
# PIT: ctx$R 은 엔진이 Date < 신호일로 자른 창이다. 어댑터는 ctx 밖을 보지 않는다(파일 · 시각 · 전역 없음 · 난수 없음 — 결정적).
# 진단 줄: 호출마다 '[skrp] d=… n=… n_jump=… pi=… es=… iters=… fallback=…' 한 줄(pi = 추정 λ = n_jump/T · es = 최종 정규화 비중의
#   일별 ES(쓰인 모형 기준) · iters = 위험 예산 풀이 반복 수 · fallback = none | nojump | estfail | noexist | solver · 성과 수치 아님).
# 반환: 선호 벡터(이름 = ctx$assets · 양수). long-only · Σw = 1 은 wrap_adapter(method_registry.R)가 강제한다.

SKRP_ALPHA <- 0.99      # §3.3.1 'In general, α is equal to 99%' · §4.2 'the 99% expected shortfall risk measure'
SKRP_KAPPA <- 4.0       # 부록 7.7 각주 'κ_σ takes its value between 3.5 and 4.0'(Ait-Sahalia 2004) — 상단 선택(구현이 정함 · 머리말)
SKRP_V     <- 0         # §4.3 각주 'The parameter v is generally set to zero'
SKRP_TOL      <- 1e-10  # 위험 예산 풀이 수렴(max|RC_i − b_i| · 해에서 ES(y) = Σb = 1) — 수치 상수
SKRP_MAX_ITER <- 200L   # 뉴턴 반복 상한 — 수치 상수
SKRP_THR_MAX  <- 100L   # 문턱 되풀이 상한 — 수치 상수

## φ(a, b, c) — 식 (eq:es1) 아래 정의 그대로
.skrp_phi <- function(a, b, c, alpha) c / (1 - alpha) * stats::dnorm((a + b) / c) - b / (1 - alpha) * stats::pnorm(-(a + b) / c)

## VaR — '(1 − λ)Φ((VaR + μ₁)/σ₁) + λΦ((VaR + μ₂)/σ₂) = α' 의 근(§3.1). 두 성분 VaR 사이에 근이 있다(혼합 분포함수가 그 둘 사이)
.skrp_var <- function(m1, s1, m2, s2, lam, alpha) {
  q <- stats::qnorm(alpha)
  if (lam <= 0) return(-m1 + s1 * q)
  F <- function(v) (1 - lam) * stats::pnorm((v + m1) / s1) + lam * stats::pnorm((v + m2) / s2) - alpha
  lo <- min(-m1 + s1 * q, -m2 + s2 * q); hi <- max(-m1 + s1 * q, -m2 + s2 * q)
  if (hi - lo <= 1e-15 * max(s1, s2)) return(lo)
  stats::uniroot(F, c(lo, hi), tol = 1e-13 * max(s1, s2), maxiter = 1000L)$root
}

## ES · VaR · 한계 위험 MR · 위험 기여 RC — 식 (eq:es1) · (eq:rc1) 원문 그대로. par = list(mu, Sig, muJ, SigJ, lam, alpha)
.skrp_es <- function(x, par) {
  al <- par$alpha; lam <- par$lam
  S2 <- par$Sig + par$SigJ
  S1x <- drop(par$Sig %*% x); S2x <- drop(S2 %*% x)
  m1 <- sum(x * par$mu); m2 <- sum(x * (par$mu + par$muJ))
  s1 <- sqrt(sum(x * S1x)); s2 <- sqrt(sum(x * S2x))
  V <- .skrp_var(m1, s1, m2, s2, lam, al)
  es <- (1 - lam) * .skrp_phi(V, m1, s1, al) + lam * .skrp_phi(V, m2, s2, al)
  h1 <- (V + m1) / s1; h2 <- (V + m2) / s2
  w1 <- (1 - lam) * stats::dnorm(h1) / s1; w2 <- lam * stats::dnorm(h2) / s2        # ϖ_i = π_i ϕ(h_i)/σ_i
  D <- w1 + w2
  d1 <- (1 + h1 / s1 * V) * S1x - V * (w1 * h1 / s1 * S1x + w2 * (h2 / s2 * S2x - par$muJ)) / D
  d2 <- (1 + h2 / s2 * V) * S2x - V * (w1 * (h1 / s1 * S1x + par$muJ) + w2 * h2 / s2 * S2x) / D
  mr <- (w1 * d1 + w2 * d2 - ((1 - lam) * par$mu * stats::pnorm(-h1) + lam * (par$mu + par$muJ) * stats::pnorm(-h2))) / (1 - al)
  list(es = es, var = V, mr = mr, rc = x * mr)
}

## α⁻ — 부록 7.6.3 · §3.3.1 의 근. 좌변은 p = (a − λ)/(1 − λ) 의 증가함수(표준정규 ES_p + λ·VaR_p)
.skrp_lhs <- function(a, lam) {
  p <- (a - lam) / (1 - lam)
  (1 - lam) / (1 - a) * stats::dnorm(stats::qnorm(p)) + lam * stats::qnorm(p)
}
.skrp_alpha_minus <- function(lam, sr1) {
  if (lam <= 0) return(0)                                     # λ = 0: 좌변 = 표준정규 ES > 0 ≥ (1 + λ)·0 — 모든 α 에서 성립
  f <- function(a) .skrp_lhs(a, lam) - (1 + lam) * sr1
  stats::uniroot(f, c(lam + 1e-12 * (1 - lam), 1 - 1e-12), tol = 1e-12)$root
}
## 존재 · 유일 조건 α ≥ max(α⁻, λ) — 좌변 단조라 'α ≥ α⁻' ⇔ 'LHS(α) ≥ (1 + λ)SR₁⁺'
.skrp_exists <- function(alpha, lam, sr1) {
  if (lam <= 0) return(TRUE)
  alpha >= lam && .skrp_lhs(alpha, lam) >= (1 + lam) * sr1
}

## 위험 예산 풀이 — §3.3.2 y* = argmin ES(y) − Σ b ln y(y > 0). 강볼록(ES 볼록 · 로그 장벽 강볼록) → 되짚기 뉴턴(수치 헤시안)
.skrp_rb <- function(par, b) {
  n <- length(b)
  y <- 1 / sqrt(diag(par$Sig + par$SigJ)); y <- y / .skrp_es(y, par)$es       # 시작 = 역변동성 · ES(y₀) = 1 = Σb 로 척도 맞춤(1차 동차)
  obj <- function(z) .skrp_es(z, par)$es - sum(b * log(z))
  it <- 0L; dev <- Inf
  repeat {
    e <- .skrp_es(y, par)
    dev <- max(abs(e$rc - b))
    if (dev < SKRP_TOL || it >= SKRP_MAX_ITER) break
    it <- it + 1L
    g <- e$mr - b / y
    H <- matrix(0, n, n)
    for (j in seq_len(n)) {
      hj <- 1e-6 * y[j]; yp <- y; ym <- y; yp[j] <- y[j] + hj; ym[j] <- y[j] - hj
      H[, j] <- (.skrp_es(yp, par)$mr - .skrp_es(ym, par)$mr) / (2 * hj)
    }
    H <- (H + t(H)) / 2 + diag(b / y^2, n)
    d <- tryCatch(-solve(H, g), error = function(z) -g)
    if (sum(g * d) >= 0) d <- -g                               # 하강 방향이 아니면 경사 하강
    f0 <- obj(y); st <- 1; moved <- FALSE
    repeat {
      yn <- y + st * d
      if (isTRUE(all(yn > 0)) && isTRUE(obj(yn) <= f0 + 1e-4 * st * sum(g * d))) { moved <- TRUE; break }
      st <- st / 2
      if (st < 1e-14) break
    }
    if (!moved) break
    y <- yn
  }
  list(y = y, iters = it, converged = dev < SKRP_TOL, rc_dev = dev)
}

## 1차원 문턱 판정(부록 7.7 동치 · 부록 7.9 되풀이) — 가우시안 추정 · 점프 없음에서 시작, 정상 σ 를 점프 아닌 날(나눗수 n_t)로 재며 고정점까지
.skrp_jump_days <- function(y, kappa = SKRP_KAPPA, v = SKRP_V) {
  J <- rep(FALSE, length(y)); k <- 0L
  repeat {
    yn <- y[!J]
    s <- sqrt(mean((yn - mean(yn))^2))
    Jn <- abs(y - v) >= kappa * s
    k <- k + 1L
    if (identical(Jn, J) || k >= SKRP_THR_MAX || sum(!Jn) < 2L) { J <- Jn; break }
    J <- Jn
  }
  list(J = J, sigma = s, iters = k)
}

## 모수 추정 — 정상 국면(부록 7.9 3단계) · 점프 국면(§2.4 M-단계 · 1요인 제한). status = none | nojump | estfail
.skrp_estimate <- function(X) {
  Tn <- nrow(X); n <- ncol(X)
  Xc <- sweep(X, 2L, colMeans(X)); Sig_full <- crossprod(Xc) / Tn             # 가우시안 모형(창 전체 · 나눗수 T)
  y <- rowMeans(X)
  jd <- .skrp_jump_days(y)
  J <- jd$J; nj <- sum(J); N <- !J; nt <- sum(N)
  out <- list(Sig_full = Sig_full, nj = nj, pi_hat = nj / Tn, status = "none")
  if (nj == 0L) { out$status <- "nojump"; return(out) }
  if (nt <= n) { out$status <- "estfail"; return(out) }
  XN <- X[N, , drop = FALSE]; mu_hat <- colMeans(XN)
  Sig <- crossprod(sweep(XN, 2L, mu_hat)) / nt                                 # 부록 7.9 — 1/n_t Σ 1{비점프}(y − μ̂)(y − μ̂)ᵀ
  if (any(!is.finite(Sig)) || min(eigen(Sig, symmetric = TRUE, only.values = TRUE)$values) <= 0) { out$status <- "estfail"; return(out) }
  yN <- y[N]; mu_y <- mean(yN); s2_y <- mean((yN - mu_y)^2)
  yJ <- y[J]; e <- yJ - mu_y
  muJm <- mean(e)                                                              # μ̃_m = mean_J(y) − μ̂_y
  sJm2 <- max(mean((yJ - mean(yJ))^2) - s2_y, 0)                               # σ̃_m² = Σ₂ − Σ(1차원) · Σ̃ ⪰ 0
  if (sum(e^2) <= 0) { out$status <- "estfail"; return(out) }
  bJ <- colSums(sweep(X[J, , drop = FALSE], 2L, mu_hat) * e) / sum(e^2)       # 점프 진폭 계수(점프일 원점 회귀)
  out$Sig <- Sig; out$muJ <- bJ * muJm; out$SigJ <- tcrossprod(bJ) * sJm2
  out$lam <- nj / Tn                                                           # §2.4 M-단계 π = 평균 사후확률(0/1 판정)
  out
}

.skrp_gauss_par <- function(est, n) list(mu = rep(0, n), Sig = est$Sig_full, muJ = rep(0, n), SigJ = matrix(0, n, n), lam = 0, alpha = SKRP_ALPHA)

method_weights <- function(ctx) {
  a <- ctx$assets
  n <- length(a)
  if (n < 3L) stop("자산 3종 미만 — 하네스가 먼저 EW 로 처리한다")
  dd <- if (is.null(ctx$decision_date)) "NA" else format(ctx$decision_date)
  X <- ctx$R[, a, drop = FALSE]
  if (!all(is.finite(X))) stop("창에 결측 · 비유한 수익 — 위험 예산 불가")
  if (any(apply(X, 2L, stats::sd) <= 0)) stop("표준편차 0 종목 — 위험 예산 불가")
  b <- rep(1 / n, n)
  est <- .skrp_estimate(X)
  fb <- est$status
  par <- if (identical(fb, "none")) list(mu = rep(0, n), Sig = est$Sig, muJ = est$muJ, SigJ = est$SigJ, lam = est$lam, alpha = SKRP_ALPHA) else .skrp_gauss_par(est, n)
  if (identical(fb, "none") && !.skrp_exists(SKRP_ALPHA, est$lam, 0)) { fb <- "noexist"; par <- .skrp_gauss_par(est, n) }   # μ = 0 → SR₁⁺ = 0
  sol <- .skrp_rb(par, b)
  if (!sol$converged && identical(fb, "none")) { fb <- "solver"; par <- .skrp_gauss_par(est, n); sol <- .skrp_rb(par, b) }
  if (!sol$converged) {
    cat(sprintf("[skrp] d=%s n=%d n_jump=%d pi=%.4f es=NA iters=%d fallback=%s unconverged=1\n", dd, n, est$nj, est$pi_hat, sol$iters, fb))
    stop(sprintf("위험 예산 풀이 미수렴(max|RC − b| = %.2e)", sol$rc_dev))
  }
  x <- sol$y / sum(sol$y)
  cat(sprintf("[skrp] d=%s n=%d n_jump=%d pi=%.4f es=%.6f iters=%d fallback=%s\n", dd, n, est$nj, est$pi_hat, .skrp_es(x, par)$es, sol$iters, fb))
  setNames(sol$y, a)
}
