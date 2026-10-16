# hrp_lopez_de_prado_2016.R — 계층적 위험 균등(HRP) 원문 구현(2026-10-16 · P3R03 구성 라운드 재료 · Superfan C-20261016-006 · 측정 신뢰 결함 수리)
#
# 원문: López de Prado, M. (2016) "Building Diversified Portfolios that Outperform Out-of-Sample", Journal of Portfolio Management 42(4):59-69 ·
#   SSRN 2708678(https://papers.ssrn.com/abstract=2708678) — 부록 A.3 코드(getIVP · getClusterVar · getQuasiDiag · getRecBipart · correlDist · main).
#   ① 상관 거리 d_ij = sqrt(½(1−ρ_ij)) (correlDist) ② 거리의 거리 d̃ = d 의 열 벡터 사이 유클리드 거리(§2단계 · `sch.linkage(dist,'single')` 이
#   2차원 배열을 관측 행렬로 받아 행 사이 거리를 계산) ③ **단일 연결**(single · 최근접점) 계층 군집 ④ 준대각화(getQuasiDiag — 마지막 병합의
#   두 자식에서 시작해 군집을 [작은 id, 큰 id] 순 두 자식으로 제자리 치환) ⑤ 재귀 이분(getRecBipart — 정렬된 목록을 위치로 반분 · Python 2
#   정수 나눗셈 len/2 · 두 반쪽의 군집 분산 V0 · V1 은 그 안의 역분산 비중(IVP)으로 잰 분산 · α = 1 − V0/(V0+V1)).
#   공분산 · 상관 = 표본(pandas x.cov() · x.corr()). 원문 몬테카를로 = 직전 260 관측 · 22 관측마다 재추정(우리 축: 창 252 거래일 · 월간 리밸).
#
# 카탈로그의 다른 HRP 와 다른 점(그래서 원문 구현이 필요했다):
#   · lean:hrp / qepm:HRP(dynamic_regime_rp.R::hrp_weights) = ward.D2 연결 · d 자체로 군집(거리의 거리 아님) · 이분 ceiling(len/2).
#   · qepm:HRP 는 카탈로그 경로에서 함수 부재로 EW 폴백(10-16 탐침 · 실효 강등).
# scipy 규약 대응: R hclust 의 병합 행렬(음수 = 원소 · 양수 = 단계)을 scipy id(원소 0..n−1 · 단계 k 의 군집 n+k−1)로 바꾸고, 행마다
#   작은 id 를 앞에 둔다(scipy `label` — x_root < y_root 이면 그 순서). 단일 연결은 동률이 없으면 병합 순서가 유일하다.
# KR 롱온리 사상: HRP 는 본래 롱온리 · Σw = 1 이라 사상이 필요 없다. 엔진이 고른 ≤25종 안에서 비중만 정한다.
# PIT: ctx$R = 엔진이 Date < 신호일로 자른 창(직전 252 거래일 · 결측 없는 종목만). ctx 밖을 보지 않는다.
# 진단 줄: 호출마다 '[hrp] d=… n=… maxw=… effn=…'(최대 비중 · 유효 종목 수 1/Σw² — 철학 헌장 실패 형태 '집중'의 기록).

HRP_LINKAGE <- "single"   # 원문 부록 A.3 `link=sch.linkage(dist,'single')` (SSRN 2708678 p.15-16) — 스윕 아님

## 공분산 = ctx$Sigma(셀 엔진 = 같은 창의 표본 공분산 — 원문과 같다 · Optimizer 는 Σ 를 재추정하지 않는다) · 없으면 표본 공분산
.ctx_sigma <- function(ctx, a) {
  S <- ctx$Sigma
  if (is.null(S) || !all(a %in% colnames(S))) return(stats::cov(ctx$R[, a, drop = FALSE]))
  S[a, a, drop = FALSE]
}

## ①~③ 상관 거리 → 거리의 거리 → 단일 연결 · scipy 형식 병합 행렬(0-based id · 행마다 작은 id 먼저)
.hrp_linkage <- function(C) {
  n <- ncol(C)
  d <- sqrt(pmax((1 - C) / 2, 0))                       # correlDist
  dt <- stats::dist(d)                                  # d̃ = 행(= 열 · d 대칭) 사이 유클리드 거리
  hc <- stats::hclust(dt, method = HRP_LINKAGE)
  to_id <- function(v) ifelse(v < 0, -v - 1L, n + v - 1L)
  Z <- cbind(to_id(hc$merge[, 1]), to_id(hc$merge[, 2]))
  Z <- t(apply(Z, 1L, sort))
  list(Z = matrix(as.integer(Z), ncol = 2L), height = hc$height, n = n, dtilde = as.matrix(dt))
}

## ④ 준대각화 — getQuasiDiag: 마지막 병합의 두 자식에서 시작해 군집 id(≥ n)를 두 자식으로 제자리 치환(순서 보존)
.hrp_quasi_diag <- function(L) {
  n <- L$n; Z <- L$Z
  ord <- Z[nrow(Z), ]
  while (any(ord >= n)) {
    ord <- unlist(lapply(ord, function(v) if (v >= n) Z[v - n + 1L, ] else v), use.names = FALSE)
  }
  as.integer(ord) + 1L                                  # 1-based 열 번호
}

## getIVP · getClusterVar
.hrp_cluster_var <- function(S, idx) {
  s <- S[idx, idx, drop = FALSE]
  w <- 1 / diag(s); w <- w / sum(w)
  as.numeric(t(w) %*% s %*% w)
}

## ⑤ 재귀 이분 — getRecBipart(위치 반분 · floor(len/2) · 짝지어 α 배분)
.hrp_rec_bipart <- function(S, ord) {
  w <- setNames(rep(1, length(ord)), as.character(ord))
  items <- list(ord)
  repeat {
    nxt <- list()
    for (it in items) if (length(it) > 1L) {
      h <- length(it) %/% 2L
      nxt <- c(nxt, list(it[seq_len(h)]), list(it[(h + 1L):length(it)]))
    }
    items <- nxt
    if (!length(items)) break
    for (k in seq(1L, length(items), by = 2L)) {
      c0 <- items[[k]]; c1 <- items[[k + 1L]]
      v0 <- .hrp_cluster_var(S, c0); v1 <- .hrp_cluster_var(S, c1)
      a <- 1 - v0 / (v0 + v1)
      w[as.character(c0)] <- w[as.character(c0)] * a
      w[as.character(c1)] <- w[as.character(c1)] * (1 - a)
    }
  }
  w
}

hrp_weights_ldp2016 <- function(X, S = stats::cov(X)) {
  if (any(!is.finite(S)) || any(diag(S) <= 0)) stop("공분산 계산 불가(분산 0 종목)")
  L <- .hrp_linkage(stats::cov2cor(S))                  # x.corr() = 공분산의 상관 변환과 같다
  ord <- .hrp_quasi_diag(L)
  w <- .hrp_rec_bipart(S, ord)
  out <- numeric(ncol(S)); out[as.integer(names(w))] <- w
  setNames(out / sum(out), colnames(S))
}

method_weights <- function(ctx) {
  a <- ctx$assets
  if (length(a) < 3L) stop("자산 3종 미만 — 하네스가 먼저 EW 로 처리한다")
  w <- hrp_weights_ldp2016(ctx$R[, a, drop = FALSE], .ctx_sigma(ctx, a))
  dd <- if (is.null(ctx$decision_date)) "NA" else format(ctx$decision_date)
  cat(sprintf("[hrp] d=%s n=%d maxw=%.4f effn=%.2f\n", dd, length(a), max(w), 1 / sum(w^2)))
  w
}
