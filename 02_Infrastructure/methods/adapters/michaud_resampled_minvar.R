# michaud_resampled_minvar.R — Michaud 재표집 효율(Resampled Efficiency™) 최소분산 끝점 원문 구현(2026-10-16 · P3R03 구성 라운드 재료 · 측정 신뢰 결함 수리)
#
# 원문: Michaud, R. (1998) Efficient Asset Management, Harvard Business School Press · Michaud, R. & Michaud, R. (2008)
#   "Estimation Error and Portfolio Optimization: A Resampling Solution", Journal of Investment Management 6(1) — 작업판
#   https://newfrontieradvisors.com/media/rxbld4hq/estimation-error-and-portfolio-optimization-12-05.pdf §RE Technology:
#   Step 1 점추정에 중심을 둔 분포에서 평균 · 공분산을 표집(재표집 = 다변량 정규로 모의 이력 재생성 · 각주 12) · Step 2 그 추정으로 MV 해 ·
#   Step 3 수렴할 때까지 반복 · Step 4 비중 평균. 각주 14: 모의 표본 길이 = 원 자료 길이('consistent with the uncertainty in the original
#   data set'), 다변량 정규, **비음 · 합 1 제약**. p.6: 'RE optimal minimum variance portfolio is defined as the average of the portfolio
#   weights of all the simulated minimum variance portfolios'.
#
# KR 롱온리 사상: 원문이 이미 롱온리 · 합 1 이다 — 사상 없음. 엔진이 고른 ≤25종 안에서 비중만 정한다. 최소분산 끝점(기대수익 입력 없음 —
#   엔진 점수를 μ 로 쓰지 않는다: 알파 사이징이 섞이면 '구성' 단독 효과를 판정할 수 없다).
# 반복 수 B = 500: 원문 Step 3 은 '수렴까지' · New Frontier 연구가 500회 재표집을 쓴다(예: 같은 회사 연구 노트 'We use 500 simulations').
#   수렴은 매 호출 진단 줄의 몬테카를로 표준오차(max_i sd_b(w_i)/√B)로 기록한다 — 성과를 보고 B 를 고르지 않는다.
# 난수: 신호일 결정론 시드 · 전역 난수 상태 보존(다른 계산의 난수 계열을 흔들지 않는다 · R2 재현).
# PIT: ctx$R = 엔진이 Date < 신호일로 자른 창(직전 252 거래일 · 결측 없는 종목만). 점추정 = 그 창의 표본 평균 · 공분산.
# 진단 줄: '[michaud] d=… n=… B=… T=… mcse=… maxw=… effn=…'.

MICHAUD_B <- 500L   # 재표집 횟수 — 근거는 머리 주석(원문 Step 3 · New Frontier 500회 관행) · 스윕 아님

## 공분산 = ctx$Sigma(셀 엔진 = 같은 창의 표본 공분산 — 원문과 같다 · Optimizer 는 Σ 를 재추정하지 않는다) · 없으면 표본 공분산
.ctx_sigma <- function(ctx, a) {
  S <- ctx$Sigma
  if (is.null(S) || !all(a %in% colnames(S))) return(stats::cov(ctx$R[, a, drop = FALSE]))
  S[a, a, drop = FALSE]
}

.mi_with_seed <- function(seed, expr) {
  ge <- globalenv()
  had <- exists(".Random.seed", envir = ge, inherits = FALSE)
  old <- if (had) get(".Random.seed", envir = ge) else NULL
  on.exit(if (had) assign(".Random.seed", old, envir = ge) else if (exists(".Random.seed", envir = ge, inherits = FALSE)) rm(".Random.seed", envir = ge))
  set.seed(seed)
  expr
}

.mi_lo_minvar <- function(S) {
  n <- ncol(S)
  D <- S / mean(diag(S)); D <- (D + t(D)) / 2                       # 척도 정규화(해 불변)
  sol <- tryCatch(quadprog::solve.QP(Dmat = D, dvec = rep(0, n), Amat = cbind(rep(1, n), diag(n)), bvec = c(1, rep(0, n)), meq = 1),
                  error = function(e) quadprog::solve.QP(Dmat = D + diag(1e-10, n), dvec = rep(0, n), Amat = cbind(rep(1, n), diag(n)),
                                                         bvec = c(1, rep(0, n)), meq = 1))
  x <- pmax(sol$solution, 0); x[x < 1e-10 * sum(x)] <- 0
  x / sum(x)
}

michaud_resampled_minvar <- function(X, seed, B = MICHAUD_B, S = stats::cov(X)) {
  Tn <- nrow(X); n <- ncol(X)
  mu <- colMeans(X)                                                 # 점추정 평균 · 공분산(S) — 원문 Step 1 의 분포 중심
  U <- chol(S)                                                      # Z %*% U ~ N(0, S) — 양정치가 아니면 예외(래퍼가 EW 폴백을 호명)
  W <- .mi_with_seed(seed, vapply(seq_len(B), function(b) {
    Y <- matrix(stats::rnorm(Tn * n), Tn, n) %*% U + rep(mu, each = Tn)   # 모의 이력 T × n(원 자료 길이)
    .mi_lo_minvar(stats::cov(Y))                                    # 모의 추정의 롱온리 최소분산
  }, numeric(n)))
  w <- rowMeans(W)
  list(w = setNames(w / sum(w), colnames(X)), mcse = max(apply(W, 1L, stats::sd) / sqrt(B)), B = B, T = Tn)
}

method_weights <- function(ctx) {
  a <- ctx$assets
  if (length(a) < 3L) stop("자산 3종 미만 — 하네스가 먼저 EW 로 처리한다")
  seed <- if (is.null(ctx$decision_date)) 0L else as.integer(as.Date(ctx$decision_date))
  r <- michaud_resampled_minvar(ctx$R[, a, drop = FALSE], seed, S = .ctx_sigma(ctx, a))
  dd <- if (is.null(ctx$decision_date)) "NA" else format(ctx$decision_date)
  cat(sprintf("[michaud] d=%s n=%d B=%d T=%d mcse=%.5f maxw=%.4f effn=%.2f\n", dd, length(a), r$B, r$T, r$mcse, max(r$w), 1 / sum(r$w^2)))
  r$w
}
