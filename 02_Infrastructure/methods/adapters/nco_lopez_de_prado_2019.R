# nco_lopez_de_prado_2019.R — 군집 중첩 최적화(NCO) + 마르첸코-파스투르 잡음 제거 원문 구현(2026-10-16 · P3R03 구성 라운드 재료 · 측정 신뢰 결함 수리)
#
# 원문: López de Prado, M. (2019) "A Robust Estimator of the Efficient Frontier", SSRN 3469961 · 같은 저자 Machine Learning for Asset
#   Managers(2020, Cambridge Elements) §2(잡음 제거) · §4(군집) · §7(NCO) · 코드 = 특허 US20210081828A1 코드 5
#   (https://patents.google.com/patent/US20210081828A1/en — `if bWidth>0:cov1=deNoiseCov(cov1,nObs*1./cov1.shape[1],bWidth)` →
#   `optPort_nco(cov1,mu1,cov1.shape[0]/2)` · `clusterKMeansBase(corr0,maxNumClusters,n_init=10)` · `KMeans(n_clusters=i,n_init=1)` ·
#   `silhouette_samples` · 선택 = 실루엣 평균/표준편차 최대).
#   ① 잡음 제거(deNoiseCov · 상수 잔여 고유값): 상관행렬 고유값 분포에 MP 밀도를 맞춰(KDE 대역폭 bWidth · σ² ∈ (1e-5, 1−1e-5) 경계 최소화 ·
#      격자 1000점) λ_max = σ²(1+√(1/q))² 이상 고유값(nFacts)은 남기고 나머지는 평균으로 평평하게 → 상관 재정규화 → 공분산.
#   ② 군집(clusterKMeansBase): 관측 행렬 x = sqrt((1−ρ)/2) · k = 2..maxNumClusters × 초기값 n_init · k-means(n_init=1) ·
#      실루엣 표본(유클리드) · t = mean/std(모집단 표준편차) 최대 선택(처음은 무조건 채택 — 원문 `np.isnan(stat[1])`).
#   ③ 군집 내 최적화 → 군집 사이 축약 공분산 Wᵀ Σ W → 군집 간 최적화 → 최종 = 군집 내 × 군집 간.
#
# KR 롱온리 사상(우리 축: long-only · ≤25종 · Σw ≤ 1 — 종목 선택은 엔진 · 이 어댑터는 선택된 종목의 비중만):
#   · 원문 optPort(cov, mu=None) = 부호 제약 없는 최소분산(inv·1/1ᵀinv·1). NCO 는 군집 내 · 간 최적화기를 바꿔 끼우는 메타 알고리즘이므로
#     두 단계 모두 **롱온리 · 합 1 최소분산**(2차 계획 · quadprog)으로 사상한다 — mu = None(최소분산 판)과 같은 목적 · 부호 제약만 축의 것.
#   · maxNumClusters = floor(n/2)(원문 `cov1.shape[0]/2` · Python 2 정수 나눗셈). n < 4 면 군집 1개(= 잡음 제거 공분산 롱온리 최소분산).
#   · k-means 초기화 = k-means++ 시드 + Lloyd 반복(sklearn KMeans 기본 · max_iter 300). 난수 = 신호일 결정론 시드 · 전역 난수 상태 보존
#     (다른 계산의 난수 계열을 흔들지 않는다 · R2 재현).
# PIT: ctx$R = 엔진이 Date < 신호일로 자른 창(직전 252 거래일 · 결측 없는 종목만) · q = T/n. ctx 밖을 보지 않는다.
# 진단 줄: '[nco] d=… n=… q=… nfacts=… mp_var=… k=… maxw=… effn=…'.

NCO_BWIDTH <- 0.01    # KDE 대역폭 — MLAM §2 `findMaxEval(np.diag(eVal0),q,bWidth=.01)` · 특허 코드 5 deNoiseCov(…, bWidth)
NCO_N_INIT <- 10L     # clusterKMeansBase(…, n_init=10)
NCO_MP_PTS <- 1000L   # errPDFs(var, eVal, q, bWidth, pts=1000)
NCO_KM_ITER <- 300L   # sklearn KMeans max_iter 기본값(원문은 기본값 사용)

## 공분산 = ctx$Sigma(셀 엔진 = 같은 창의 표본 공분산 — 원문과 같다 · Optimizer 는 Σ 를 재추정하지 않는다) · 없으면 표본 공분산
.ctx_sigma <- function(ctx, a) {
  S <- ctx$Sigma
  if (is.null(S) || !all(a %in% colnames(S))) return(stats::cov(ctx$R[, a, drop = FALSE]))
  S[a, a, drop = FALSE]
}

.nco_with_seed <- function(seed, expr) {
  ge <- globalenv()
  had <- exists(".Random.seed", envir = ge, inherits = FALSE)
  old <- if (had) get(".Random.seed", envir = ge) else NULL
  on.exit(if (had) assign(".Random.seed", old, envir = ge) else if (exists(".Random.seed", envir = ge, inherits = FALSE)) rm(".Random.seed", envir = ge))
  set.seed(seed)
  expr
}

## ── ① 잡음 제거 ─────────────────────────────────────────────────────────────
.nco_mp_pdf <- function(var, q, pts) {
  eMin <- var * (1 - sqrt(1 / q))^2; eMax <- var * (1 + sqrt(1 / q))^2
  e <- seq(eMin, eMax, length.out = pts)
  list(x = e, pdf = q / (2 * pi * var * e) * sqrt(pmax((eMax - e) * (e - eMin), 0)))
}
.nco_kde <- function(obs, bw, x) vapply(x, function(z) mean(stats::dnorm((z - obs) / bw)) / bw, numeric(1))
.nco_err <- function(var, ev, q, bw) { m <- .nco_mp_pdf(var, q, NCO_MP_PTS); sum((.nco_kde(ev, bw, m$x) - m$pdf)^2) }
.nco_find_max_eval <- function(ev, q, bw) {
  o <- tryCatch(stats::optim(0.5, .nco_err, ev = ev, q = q, bw = bw, method = "L-BFGS-B", lower = 1e-5, upper = 1 - 1e-5),
                error = function(e) NULL)
  var <- if (!is.null(o) && identical(o$convergence, 0L)) o$par else 1     # 원문: out['success'] 아니면 var = 1
  list(eMax = var * (1 + sqrt(1 / q))^2, var = var)
}
.nco_cov2corr <- function(S) { s <- sqrt(diag(S)); C <- S / (s %o% s); C[C < -1] <- -1; C[C > 1] <- 1; C }
nco_denoise_cov <- function(S, q, bw = NCO_BWIDTH) {
  sd <- sqrt(diag(S)); C <- .nco_cov2corr(S); n <- ncol(C)
  e <- eigen(C, symmetric = TRUE)                                   # 내림차순(getPCA)
  f <- .nco_find_max_eval(e$values, q, bw)
  nF <- sum(e$values >= f$eMax)                                     # n − searchsorted(오름차순, eMax) = eMax 이상 개수
  nF <- min(nF, n - 1L)                                             # 전부 신호면 평평하게 할 잔여가 없다(원문은 0 나눗셈)
  ev <- e$values
  ev[(nF + 1L):n] <- sum(ev[(nF + 1L):n]) / (n - nF)                # denoisedCorr
  C1 <- .nco_cov2corr(e$vectors %*% (ev * t(e$vectors)))
  list(S = C1 * (sd %o% sd), nFacts = nF, var = f$var)
}

## ── ② 군집 ───────────────────────────────────────────────────────────────────
.nco_kmeanspp <- function(X, k) {
  n <- nrow(X); idx <- sample.int(n, 1L)
  while (length(idx) < k) {
    d2 <- apply(X, 1L, function(r) min(colSums((t(X[idx, , drop = FALSE]) - r)^2)))
    if (sum(d2) <= 0) return(NULL)
    idx <- c(idx, sample.int(n, 1L, prob = d2 / sum(d2)))
  }
  X[idx, , drop = FALSE]
}
.nco_silhouette <- function(D, lab) {
  vapply(seq_along(lab), function(i) {
    own <- lab == lab[i]
    if (sum(own) <= 1L) return(0)                                   # sklearn: 단독 군집 = 0
    a <- sum(D[i, own]) / (sum(own) - 1L)
    b <- min(vapply(setdiff(unique(lab), lab[i]), function(cc) mean(D[i, lab == cc]), numeric(1)))
    (b - a) / max(a, b)
  }, numeric(1))
}
nco_cluster_kmeans_base <- function(C, max_k, n_init = NCO_N_INIT) {
  X <- sqrt(pmax((1 - C) / 2, 0)); D <- as.matrix(stats::dist(X))
  best <- NULL; best_t <- NA_real_
  for (init in seq_len(n_init)) for (k in seq.int(2L, max_k)) {
    C0 <- .nco_kmeanspp(X, k); if (is.null(C0)) next
    km <- tryCatch(suppressWarnings(stats::kmeans(X, centers = C0, iter.max = NCO_KM_ITER, algorithm = "Lloyd")), error = function(e) NULL)
    if (is.null(km) || length(unique(km$cluster)) < k) next         # 빈 군집이 생긴 시도 = 실패한 초기값(sklearn 은 빈 군집을 남기지 않는다)
    s <- .nco_silhouette(D, km$cluster)
    t_new <- mean(s) / sqrt(mean((s - mean(s))^2))                   # numpy std = 모집단
    if (is.na(best_t) || (is.finite(t_new) && t_new > best_t)) { best <- km$cluster; best_t <- t_new }
  }
  list(labels = best, t = best_t)
}

## ── ③ 롱온리 최소분산(군집 내 · 간 공통) ──────────────────────────────────────
.nco_lo_minvar <- function(S) {
  n <- ncol(S); if (n == 1L) return(1)
  D <- S / mean(diag(S)); D <- (D + t(D)) / 2                       # 척도 정규화(해 불변)
  if (min(eigen(D, symmetric = TRUE, only.values = TRUE)$values) <= 1e-12) D <- D + diag(1e-10, n)
  sol <- quadprog::solve.QP(Dmat = D, dvec = rep(0, n), Amat = cbind(rep(1, n), diag(n)), bvec = c(1, rep(0, n)), meq = 1)
  x <- pmax(sol$solution, 0); x[x < 1e-10 * sum(x)] <- 0
  x / sum(x)
}

nco_weights_ldp2019 <- function(X, seed, S = stats::cov(X)) {
  n <- ncol(X); Tn <- nrow(X)
  dn <- nco_denoise_cov(S, q = Tn / n)                              # 잡음 제거는 원문 방법의 일부(받은 Σ 를 변환)
  S1 <- dn$S
  max_k <- n %/% 2L
  lab <- if (max_k >= 2L) .nco_with_seed(seed, nco_cluster_kmeans_base(.nco_cov2corr(S1), max_k))$labels else NULL
  if (is.null(lab)) lab <- rep(1L, n)
  ks <- sort(unique(lab))
  W <- matrix(0, n, length(ks))
  for (j in seq_along(ks)) { id <- which(lab == ks[j]); W[id, j] <- .nco_lo_minvar(S1[id, id, drop = FALSE]) }
  w_inter <- .nco_lo_minvar(t(W) %*% S1 %*% W)
  w <- as.numeric(W %*% w_inter)
  list(w = setNames(w / sum(w), colnames(X)), k = length(ks), nFacts = dn$nFacts, var = dn$var, q = Tn / n)
}

method_weights <- function(ctx) {
  a <- ctx$assets
  if (length(a) < 3L) stop("자산 3종 미만 — 하네스가 먼저 EW 로 처리한다")
  seed <- if (is.null(ctx$decision_date)) 0L else as.integer(as.Date(ctx$decision_date))   # 신호일 결정론 시드(일 수)
  r <- nco_weights_ldp2019(ctx$R[, a, drop = FALSE], seed, .ctx_sigma(ctx, a))
  dd <- if (is.null(ctx$decision_date)) "NA" else format(ctx$decision_date)
  cat(sprintf("[nco] d=%s n=%d q=%.2f nfacts=%d mp_var=%.4f k=%d maxw=%.4f effn=%.2f\n", dd, length(a), r$q, r$nFacts, r$var, r$k,
              max(r$w), 1 / sum(r$w^2)))
  r$w
}
