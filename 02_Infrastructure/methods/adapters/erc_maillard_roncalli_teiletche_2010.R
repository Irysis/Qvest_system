# erc_maillard_roncalli_teiletche_2010.R — 위험 기여 균등(ERC) 원문 구현(2026-10-16 · P3R03 구성 라운드 재료 · 측정 신뢰 결함 수리)
#
# 원문: Maillard, S., Roncalli, T. & Teïletche, J. (2010) "The Properties of Equally Weighted Risk Contribution Portfolios",
#   Journal of Portfolio Management 36(4):60-70 (SSRN 1271972 · https://papers.ssrn.com/abstract=1271972).
#   정의: x_i (Σx)_i = x_j (Σx)_j  ∀i, j (총위험 σ(x) 에 대한 기여 균등) · 롱온리 · 합 1. 해는 유일하고
#   y* = argmin ½ yᵀΣy − (1/n) Σ ln y_i(y > 0) 를 합 1 로 정규화한 것과 같다(원문 §해의 존재와 유일성).
#   풀이 = 순환 좌표 하강(Griveau-Billion, Richard & Roncalli 2013, arXiv 1311.4057 — y_i ← (−c_i + √(c_i² + 4Σ_ii b_i))/(2Σ_ii) ·
#   c_i = Σ_{j≠i} Σ_ij y_j · b_i = 1/n). 수렴 = 위험 기여 비율의 최대 편차로 판정(진단 줄 rc_dev).
#
# 왜 원문 구현이 필요했나: 카탈로그 qepm:ERC(dynamic_regime_rp.R::erc_weights — 같은 순환 좌표 하강)는 카탈로그 경로에서
#   'dispatch infeasible: function_missing' 으로 EW 폴백한다(10-16 탐침 · 실효 강등). 계산식은 그 함수와 같다(검사가 대조).
# 왜 후보인가: 1차 라운드에서 알파 손실 없이 Calmar 를 올린 유일한 구성이 역변동성(K1 — 상관 0 가정 ERC)이었다. ERC 는 그 공분산 일반형.
# KR 롱온리 사상: 원문이 롱온리 · 합 1 — 사상 없음. 공분산 = 창의 표본 공분산(원문 실증의 표본 추정과 같은 종류).
# PIT: ctx$R = 엔진이 Date < 신호일로 자른 창(직전 252 거래일 · 결측 없는 종목만).
# 진단 줄: '[erc] d=… n=… iter=… rc_dev=… maxw=… effn=…'.

ERC_TOL <- 1e-10      # 좌표 하강 수렴 판정(상대 변화) — 수치 정밀도 상수(모형 모수 아님)
ERC_MAX_ITER <- 5000L # 상한 — 도달하면 진단 줄에 iter = 상한이 찍힌다

## 공분산 = ctx$Sigma(셀 엔진 = 같은 창의 표본 공분산 — 원문과 같다 · Optimizer 는 Σ 를 재추정하지 않는다) · 없으면 표본 공분산
.ctx_sigma <- function(ctx, a) {
  S <- ctx$Sigma
  if (is.null(S) || !all(a %in% colnames(S))) return(stats::cov(ctx$R[, a, drop = FALSE]))
  S[a, a, drop = FALSE]
}

erc_weights_mrt2010 <- function(S) {
  n <- ncol(S); b <- rep(1 / n, n)
  y <- 1 / sqrt(diag(S)); y <- y / sum(y)                            # 시작점 = 역변동성
  it <- 0L
  repeat {
    it <- it + 1L; y_old <- y
    for (i in seq_len(n)) {
      a <- S[i, i]; ci <- sum(S[i, ] * y) - a * y[i]
      y[i] <- (-ci + sqrt(ci^2 + 4 * a * b[i])) / (2 * a)
    }
    if (max(abs(y - y_old)) < ERC_TOL * max(abs(y_old)) || it >= ERC_MAX_ITER) break
  }
  w <- y / sum(y)
  rc <- w * as.numeric(S %*% w); rc <- rc / sum(rc)
  list(w = setNames(w, colnames(S)), iter = it, rc_dev = max(abs(rc - 1 / n)))
}

method_weights <- function(ctx) {
  a <- ctx$assets
  if (length(a) < 3L) stop("자산 3종 미만 — 하네스가 먼저 EW 로 처리한다")
  S <- .ctx_sigma(ctx, a)
  if (any(!is.finite(S)) || any(diag(S) <= 0)) stop("공분산 계산 불가(분산 0 종목)")
  r <- erc_weights_mrt2010(S)
  dd <- if (is.null(ctx$decision_date)) "NA" else format(ctx$decision_date)
  cat(sprintf("[erc] d=%s n=%d iter=%d rc_dev=%.2e maxw=%.4f effn=%.2f\n", dd, length(a), r$iter, r$rc_dev, max(r$w), 1 / sum(r$w^2)))
  r$w
}
