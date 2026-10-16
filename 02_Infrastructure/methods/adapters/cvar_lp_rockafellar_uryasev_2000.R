# cvar_lp_rockafellar_uryasev_2000.R — 조건부 VaR(CVaR) 최소화 선형계획 원문 구현(2026-10-16 · P3R03 구성 라운드 재료 · 측정 신뢰 결함 수리)
#
# 원문: Rockafellar, R.T. & Uryasev, S. (2000) "Optimization of Conditional Value-at-Risk", Journal of Risk 2(3):21-41
#   (https://doi.org/10.21314/JOR.2000.038). 정리 2: F_β(x, α) = α + (1−β)⁻¹ E[(f(x,y) − α)⁺] 를 (x, α) 에 대해 최소화하면 그 최소값이
#   CVaR_β 이고 α 는 VaR_β. 시나리오 근사(식 17 계열): α + (q(1−β))⁻¹ Σ_k u_k · u_k ≥ f(x, y_k) − α · u_k ≥ 0 — 선형계획.
#   §예제(포트폴리오) β ∈ {0.90, 0.95, 0.99}.
#
# KR 롱온리 사상: 손실 f(x, y_t) = −r_tᵀw(일별 수익 시나리오) · 제약 w ≥ 0 · Σw = 1 · 기대수익 제약 없음(최소 CVaR 끝점 — 엔진 점수를
#   μ 로 쓰지 않는다: 알파 사이징이 섞이면 '구성' 단독 효과를 판정할 수 없다). 시나리오 = 창의 과거 일별 수익 252 개(역사적 시뮬레이션 —
#   원문 예제는 정규 표본이지만 정식화는 시나리오 원천을 가리지 않는다). 종목별 상한 없음(고정 축) — LP 꼭짓점 해는 소수 종목에
#   몰릴 수 있다(진단 줄 active · maxw · effn 으로 기록 · 철학 헌장 실패 형태 '집중').
# β = 0.95: 원문 예제 3값의 가운데. 252 시나리오에서 꼬리 표본 = 12.6개(β 0.99 는 2.5개라 추정이 불안정). 스윕 아님(사전 단일 고정).
# 풀이: lpSolve(단체법 · 결정론). 변수 = w(n) · α⁺ · α⁻(자유 변수 분해) · u(T) — 모두 ≥ 0.
# PIT: ctx$R = 엔진이 Date < 신호일로 자른 창. ctx 밖을 보지 않는다.
# 진단 줄: '[cvar] d=… n=… T=… beta=… cvar=… var=… active=… maxw=… effn=…'.

CVAR_BETA <- 0.95   # 근거는 머리 주석(Rockafellar-Uryasev 2000 예제 β 0.90 · 0.95 · 0.99 의 가운데 · 252 시나리오 꼬리 12.6개)

cvar_lp_ru2000 <- function(X, beta = CVAR_BETA) {
  Tn <- nrow(X); n <- ncol(X)
  obj <- c(rep(0, n), 1, -1, rep(1 / ((1 - beta) * Tn), Tn))
  A <- rbind(cbind(X, 1, -1, diag(Tn)),                              # u_t + r_tᵀw + α ≥ 0  ⇔  u_t ≥ −r_tᵀw − α
             c(rep(1, n), 0, 0, rep(0, Tn)))                         # Σw = 1
  sol <- lpSolve::lp("min", obj, A, c(rep(">=", Tn), "="), c(rep(0, Tn), 1))
  if (!identical(as.integer(sol$status), 0L)) stop(sprintf("CVaR LP 해 없음(lpSolve status %d)", sol$status))
  x <- sol$solution
  w <- pmax(x[seq_len(n)], 0); w[w < 1e-10 * sum(w)] <- 0
  list(w = setNames(w / sum(w), colnames(X)), cvar = sol$objval, var = x[n + 1L] - x[n + 2L], T = Tn)
}

method_weights <- function(ctx) {
  a <- ctx$assets
  if (length(a) < 3L) stop("자산 3종 미만 — 하네스가 먼저 EW 로 처리한다")
  r <- cvar_lp_ru2000(ctx$R[, a, drop = FALSE])
  dd <- if (is.null(ctx$decision_date)) "NA" else format(ctx$decision_date)
  cat(sprintf("[cvar] d=%s n=%d T=%d beta=%.2f cvar=%.6f var=%.6f active=%d maxw=%.4f effn=%.2f\n", dd, length(a), r$T, CVAR_BETA,
              r$cvar, r$var, sum(r$w > 1e-8), max(r$w), 1 / sum(r$w^2)))
  r$w
}
