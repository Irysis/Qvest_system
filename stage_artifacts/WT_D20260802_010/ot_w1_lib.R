# =============================================================================
# ot_w1_lib.R — WT-D20260802_010 최적수송(1D Wasserstein) 팩터 라이브러리
#
# 수학 근거 (사전등록 preregistration.json 정합):
#   - 1D W1(F,G) = ∫_0^1 |F^{-1}(u) − G^{-1}(u)| du  (분위함수 L1 — 닫힌형)
#   - 1D W2 barycenter (Agueh-Carlier 2011): 분위함수의 가중평균이 barycenter의
#     분위함수 (1차원 정확 닫힌형). 본 라운드는 단순평균 barycenter 사용.
#   - robust 정규화 z=(r−median)/MAD: median·MAD의 affine 동변성으로
#     location/scale 채널을 정리 수준에서 정확 소거 (검증 T5).
#
# SPECIAL_OP escape 대상 (𝒪 28 밖). 학습/적합 파라미터 0 — walk-forward 결정론.
# =============================================================================

# ── 분위 grid (사전등록: K=31 midpoint) ──────────────────────────────────────
OT_K <- 31L
ot_grid <- function(K = OT_K) (seq_len(K) - 0.5) / K
OT_U <- ot_grid()
OT_RIGHT_IDX <- which(OT_U > 0.8)   # j=26..31 (u>=0.823)
OT_LEFT_IDX  <- which(OT_U < 0.2)   # j=1..6  (u<=0.177)

# ── W1 거리 (분위 grid 위 L1 — Riemann midpoint 근사) ────────────────────────
w1_grid <- function(qa, qb) mean(abs(qa - qb))

# 위반 주입용 오구현 ① — L2 (Cramér 형). 검증 T8a가 이걸 잡아야 함.
w1_grid_l2_BROKEN <- function(qa, qb) sqrt(mean((qa - qb)^2))

# ── 경험분위 (type 7 — 사전등록) ─────────────────────────────────────────────
emp_q <- function(x, u) as.numeric(stats::quantile(x, probs = u, type = 7, names = FALSE))

# 위반 주입용 오구현 ② — 정렬 누락 인덱싱 버그. 검증 T8b가 잡아야 함.
emp_q_unsorted_BROKEN <- function(x, u) x[pmax(1L, ceiling(u * length(x)))]

# ── robust 정규화 (median / MAD, IQR 폴백) ───────────────────────────────────
ot_robust_ms <- function(r) {
  m <- stats::median(r)
  s <- stats::mad(r)                        # constant = 1.4826 기본
  if (!is.finite(s) || s <= 0) s <- stats::IQR(r) / 1.349
  if (!is.finite(s) || s <= 0) return(NULL)
  list(m = m, s = s)
}

# ── 종목-창 피처: 정규화/원시 분위 + 대조 모멘트 ─────────────────────────────
# r: 창 내 일간 저장 Ret (유효값만 전달). min_days 미달 → NULL.
ot_stock_quantiles <- function(r, min_days = 40L, U = OT_U) {
  r <- r[is.finite(r)]
  n <- length(r)
  if (n < min_days) return(NULL)
  ms <- ot_robust_ms(r)
  if (is.null(ms)) return(NULL)
  z <- (r - ms$m) / ms$s
  sdr <- stats::sd(r)
  if (!is.finite(sdr) || sdr <= 0) return(NULL)
  rc <- r - mean(r)
  list(
    n = n, m = ms$m, s = ms$s,
    q_norm = emp_q(z, U),
    q_raw  = emp_q(r, U),
    vol  = sdr,
    dsd  = sqrt(mean(pmin(r, 0)^2)),
    skew = mean(rc^3) / sdr^3,
    kurt = mean(rc^4) / sdr^4 - 3,
    max5 = mean(sort(r, decreasing = TRUE)[seq_len(min(5L, n))])
  )
}

# ── 횡단면 분해: 분위행렬 → barycenter 편차 성분 ─────────────────────────────
# Qn: n_stocks x K 정규화 분위행렬 (barycenter = 열평균, 1D 닫힌형)
ot_cs_decompose <- function(Qn, right_idx = OT_RIGHT_IDX, left_idx = OT_LEFT_IDX) {
  qbar <- colMeans(Qn)
  D <- sweep(Qn, 2L, qbar)
  list(
    qbar     = qbar,
    rtail    = rowMeans(D[, right_idx, drop = FALSE]),
    ltail    = rowMeans(D[, left_idx,  drop = FALSE]),
    w1_shape = rowMeans(abs(D))
  )
}

# ── 검증용 이론값 헬퍼 ───────────────────────────────────────────────────────
# W1(N(mu1,s1), N(mu2,s2)) 수치 정적분 (고밀도 grid) — 닫힌형 대조의 참조 적분기
w1_gauss_theory <- function(mu1, s1, mu2, s2, K = 200001L) {
  u <- ot_grid(K)
  mean(abs((mu1 + s1 * stats::qnorm(u)) - (mu2 + s2 * stats::qnorm(u))))
}
