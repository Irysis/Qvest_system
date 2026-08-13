# longmemory_garch_2dmc.R — arXiv 2607.25189 "Long-memory GARCH via a two-dimensional
#   Markov chain" (Lee, 2026). 2026-08-02 라우터 risk 큐.
#   원문: 01_Literature/Alpha_Search_Recharge/20260802/mcp_arxiv/MCP_2607_25189.pdf (39쪽, §2 정독)
#
#------------------------------------------------------------------------------
# 논문 기전 (원문 §2 식 (1)(2)(6)(7) — 충실한 재구성, 날조 아님)
#------------------------------------------------------------------------------
# 조건부 분산을 고정 감쇠 GARCH 재귀가 아니라 **잠재 멱법칙 커널**에서 만든다:
#     h_n(t) = μ + a_n / (t + c_n)^p           ... (1)   μ>0 장기 기저, p>1 감쇠 지수
#     σ²_{n+1} = h_n(0) = μ + X_n,  X_n := a_n / c_n^p   ... (2)
# 새 충격 η²_n 이 들어오면 커널을 같은 2-모수 족 안에서 **level 과 slope 를 동시에 맞춰** 갱신한다
# (level-and-slope matching). 그 결과가 2차원 Markov 재귀:
#     X_n     = X_{n-1} (1 + τ/c_{n-1})^{-p}       + ξ η²_n            ... (6)
#     X_n/c_n = (X_{n-1}/c_{n-1}) (1 + τ/c_{n-1})^{-(p+1)} + (ξ/γ) η²_n ... (7)
#   ξ := α/γ^p, τ = 관측 간격(일별 = 1).
# ★핵심: 상태가 (X, c) 두 좌표다 — X 는 분산 수준, **c 는 내생적 기억 척도**(감쇠 속도)다.
#   고정 감쇠 GARCH 와 달리 c 가 상태에 따라 움직여서 장기기억이 유한차원 Markov 로 나온다.
#   (7) 에서 c_n = X_n / RHS(7) 로 푼다.
#
#------------------------------------------------------------------------------
# KR 사상 · Σ 구성
#------------------------------------------------------------------------------
# 논문은 **일변량 변동성 모형**이다. Σ 로 올리는 표준 분해를 쓴다: Σ = D C D
#   D = diag(모형 조건부 표준편차, 창 마지막 시점) · C = ctx$R 의 표본 상관.
#   ★상관은 손대지 않는다 — 이 논문이 바꾸는 것은 **분산의 시간구조**이지 종목 간 결합이 아니다.
#   그래야 A/B 에서 "무엇이 달라졌나"가 변동성 모형 하나로 귀속된다.
#
# ★논문이 준 것과 이 구현이 정한 것을 구분한다 (원문 §6 은 모수를 MLE 로 추정한다):
#   · 논문이 준 것 = 재귀 (6)(7) 전부. 여기 임의성 없음.
#   · 이 구현이 정한 것 = 모수 사전고정 (p=1.5 · γ=1 · τ=1 · μ 지분 0.5 · ξ=0.05).
#     MLE 를 269개월 × 25종목마다 돌리는 비용을 피하려는 선택이며, **sweep 이 아니라 단일
#     사전고정**이다(selection_type="chain", DSR 부적용). 이 값들을 바꿔가며 고르지 않았다.
#     ⚠따라서 이 arm 의 성적은 "이 모수에서의 성적"이지 모형의 최선이 아니다 — 미달이어도
#       모형 판결이 아니다(INV-7 정합).
#
# PIT: ctx$R 은 하네스가 `raw[Date < start_d]` 로 만든 trailing 행렬이다(C1/C2). ctx 밖 데이터 미사용.

LMG_P      <- 1.5    # 멱법칙 감쇠 지수 (원문 요구 p>1). 사전고정 — sweep 아님
LMG_GAMMA  <- 1.0    # 초기 감쇠 오프셋 γ. 사전고정
LMG_TAU    <- 1.0    # 관측 간격 τ (일별 스텝 = 1)
LMG_MU_SH  <- 0.5    # 장기 기저 μ 가 표본분산에서 차지하는 지분. 사전고정
LMG_XI     <- 0.05   # 충격 진폭 ξ = α/γ^p. 사전고정
LMG_MIN_N  <- 60L    # 최소 관측 — 미만이면 표본 sd 로 중립 처리(제외 아님)

.lmg_sigma_last <- function(x, mu, xi, p = LMG_P, gam = LMG_GAMMA, tau = LMG_TAU) {
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < LMG_MIN_N) return(NA_real_)
  # 초기 상태: X_0 = 표본 초과분산, c_0 = γ (커널 원점 오프셋)
  X <- max(stats::var(x) - mu, 1e-12)
  cc <- gam
  for (i in seq_len(n)) {
    e2 <- x[i]^2
    dec  <- (1 + tau / cc)
    Xn   <- X * dec^(-p) + xi * e2                      # 원문 (6)
    slope<- (X / cc) * dec^(-(p + 1)) + (xi / gam) * e2 # 원문 (7) 우변
    if (!is.finite(Xn) || Xn <= 0 || !is.finite(slope) || slope <= 0) return(NA_real_)
    cc <- Xn / slope                                    # (7) 을 c_n 에 대해 풂
    if (!is.finite(cc) || cc <= 0) return(NA_real_)
    X <- Xn
  }
  s2 <- mu + X                                          # 원문 (2): σ²_{n+1}
  if (!is.finite(s2) || s2 <= 0) NA_real_ else sqrt(s2)
}

sigma_estimate <- function(ctx) {
  a <- ctx$assets
  R <- ctx$R[, a, drop = FALSE]
  p <- length(a)

  # 표본 상관 — 이 논문이 바꾸는 축이 아니다(분산의 시간구조만 교체)
  C <- suppressWarnings(stats::cor(R, use = "pairwise.complete.obs"))
  C[!is.finite(C)] <- 0; diag(C) <- 1

  s_samp <- suppressWarnings(apply(R, 2, stats::sd, na.rm = TRUE))
  sd_model <- vapply(seq_along(a), function(j) {
    x <- R[, j]
    v <- suppressWarnings(stats::var(x, na.rm = TRUE))
    if (!is.finite(v) || v <= 0) return(NA_real_)
    .lmg_sigma_last(x, mu = LMG_MU_SH * v, xi = LMG_XI)
  }, numeric(1))

  # 추정 실패 종목은 **제외가 아니라 표본 sd 로 중립** — 제외하면 Σ 차원이 바뀌어 A/B 통제가 깨진다.
  bad <- !is.finite(sd_model) | sd_model <= 0
  sd_model[bad] <- s_samp[bad]
  if (any(!is.finite(sd_model) | sd_model <= 0)) return(NULL)   # 전부 실패 → wrapper 폴백

  S <- diag(sd_model, p) %*% C %*% diag(sd_model, p)
  dimnames(S) <- list(a, a)
  cat(sprintf("[LMGarch2DMC] p=%d · 모형실패 %d · 모형sd/표본sd 중앙 %.3f\n",
              p, sum(bad), stats::median(sd_model / pmax(s_samp, 1e-12), na.rm = TRUE)))
  S
}
