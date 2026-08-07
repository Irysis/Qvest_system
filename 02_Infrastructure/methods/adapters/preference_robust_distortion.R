# preference_robust_distortion.R — arXiv 2608.02854 "Preference robust distortion risk measures"
#   (2026-08-06 라우터 risk 큐. ★paper route=risk 이지만 **adapter_kind=weight** 다 —
#    Σ 를 교체하는 게 아니라 **목적함수 자체**를 바꾼다. 이 축 혼동이 조용한 드롭을 만든다.)
#
# 논문 기여: 의사결정자의 왜곡(distortion) 선호를 하나로 특정할 수 없을 때, 후보 집합에 대한
#   **worst-case** distortion risk measure 로 평가한다. rank-dependent utility 계열의
#   선호 불확실성(Allais paradox 맥락)을 ambiguity set 으로 다루는 것이 요지.
#
# KR 사상 (충실한 재구성):
#   유한지지 distortion 측도 = 분위수의 가중합 = spectral risk measure. 그 실무 표준형이 CVaR 이고,
#   **선호 집합에 대한 worst-case = 여러 CVaR 수준의 max**. 즉
#       min_w  max_{k}  CVaR_{α_k}( -R w )
#   ★min-max 이지만 각 CVaR 가 w 에 볼록이므로 전체가 **단일 LP** 다 (Rockafellar-Uryasev).
#   변수: w(p) · 각 k 의 VaR 보조 ζ_k · 초과손실 u_{k,t} ≥ 0 · 상한 θ.
#       min θ  s.t.  ζ_k + 1/((1-α_k)T) Σ_t u_{k,t} ≤ θ
#                    u_{k,t} ≥ -(R w)_t - ζ_k ,  u ≥ 0
#                    Σw = 1, 0 ≤ w ≤ ub
#   α 집합은 **사전 고정**(0.90/0.95/0.99 — 실무 표준 3점). sweep 아님(argmax 선택 없음).
#
# 알파 미사용: 순수 risk-side 목적함수다(mu 를 쓰지 않는다). minvar 와 같은 층에서 비교된다 —
#   "분산 최소화 대신 worst-case CVaR 최소화면 나은가"가 이 논문이 묻는 것이다.
#
# PIT: ctx$R 은 매수 이전 trailing 창(run_sigma_ab 가 `raw[Date < start_d]` 로 구성). C1/C2 준수.
# 제약: 반환은 선호 벡터. long-only/Σw=1/w≤ub 는 wrap_adapter 가 강제한다(LP 도 같은 제약을
#   걸지만 이중으로 둔다 — LP 가 실패해 폴백해도 제약은 유지).

PRD_ALPHAS <- c(0.90, 0.95, 0.99)   # 사전 고정 선호 집합
PRD_MAX_T  <- 250L                  # LP 규모 상한(창이 더 길면 최근 T 만)

method_weights <- function(ctx) {
  if (!requireNamespace("lpSolve", quietly = TRUE))
    stop("lpSolve 부재 — LP 불가 (폴백은 wrap_adapter 가 처리)")
  a <- ctx$assets; p <- length(a)
  R <- ctx$R
  R <- R[is.finite(rowSums(R)), , drop = FALSE]
  if (nrow(R) > PRD_MAX_T) R <- R[(nrow(R) - PRD_MAX_T + 1L):nrow(R), , drop = FALSE]
  T <- nrow(R); K <- length(PRD_ALPHAS)
  if (T < 60L) stop(sprintf("관측 부족 T=%d", T))

  ub <- ctx$ub %||% 0.20
  # 변수 배치: [w(1..p)] [zeta(1..K)] [u(K*T)] [theta]
  iw <- seq_len(p); iz <- p + seq_len(K); iu <- p + K + seq_len(K * T); ith <- p + K + K * T + 1L
  nv <- ith
  obj <- numeric(nv); obj[ith] <- 1

  # ★모든 변수를 비음수로 두기 위한 평행이동.
  #   lpSolve 는 변수 하한 0 이 기본이라 자유변수 ζ(=VaR)·θ 를 그대로 못 쓴다.
  #   CVaR 는 평행이동 등변이고 Σw=1 이므로 R' = R − max(R) 로 두면
  #   손실' = −(R'w) = −(Rw) + max(R) ≥ 0 → ζ' ≥ 0, θ ≥ 0 이 되고 **최적 w 는 불변**이다.
  #   (부호 주의: 손실을 비음수로 만들려면 수익을 **빼야** 한다. 더하면 반대가 된다.)
  cshift <- max(R)
  Rp <- R - cshift

  rows <- list(); dir <- character(0); rhs <- numeric(0)
  add <- function(v, d, r) { rows[[length(rows) + 1L]] <<- v; dir <<- c(dir, d); rhs <<- c(rhs, r) }

  # (1) Σw = 1
  v <- numeric(nv); v[iw] <- 1; add(v, "==", 1)
  # (2) CVaR_k ≤ theta
  for (k in seq_len(K)) {
    v <- numeric(nv); v[iz[k]] <- 1
    v[iu[((k - 1L) * T + 1L):(k * T)]] <- 1 / ((1 - PRD_ALPHAS[k]) * T)
    v[ith] <- -1; add(v, "<=", 0)
  }
  # (3) u_{k,t} + (R'w)_t + zeta_k ≥ 0   (손실' = −R'w)
  for (k in seq_len(K)) for (t in seq_len(T)) {
    v <- numeric(nv); v[iw] <- Rp[t, ]; v[iz[k]] <- 1; v[iu[(k - 1L) * T + t]] <- 1
    add(v, ">=", 0)
  }
  # (4) w_i ≤ ub — ★lpSolve::lp 에는 `upper=` 인자가 **없다**(변수 하한 0 만 기본).
  #     상한은 명시 제약 행으로 넣어야 한다. 인자로 주면 조용히 무시되는 게 아니라 에러 →
  #     wrap_adapter 가 EW 폴백을 호명한다(실측으로 검거됨).
  for (i in seq_len(p)) { v <- numeric(nv); v[iw[i]] <- 1; add(v, "<=", ub) }
  cm <- do.call(rbind, rows)

  sol <- tryCatch(lpSolve::lp("min", obj, cm, dir, rhs),
                  error = function(e) { attr(e, "msg") <- conditionMessage(e); e })
  if (inherits(sol, "error")) stop(sprintf("LP 예외: %s", conditionMessage(sol)))
  if (sol$status != 0) stop(sprintf("LP 실패 (status=%s)", sol$status))
  w <- sol$solution[iw]
  if (!all(is.finite(w)) || sum(w) <= 0) stop("LP 해 무효")
  setNames(w, a)
}

`%||%` <- function(x, y) if (!is.null(x)) x else y
