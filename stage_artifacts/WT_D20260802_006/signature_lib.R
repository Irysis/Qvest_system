# =============================================================================
# signature_lib.R — WT-D20260802_006
#   Truncated path signature (level 1~3) for piecewise-linear paths.
#
#   수학: 조각선형 경로의 시그니처는 Chen 항등식으로 정확 계산된다.
#     선형 세그먼트(증분 Δ)의 시그니처 = exp⊗(Δ):
#       level1 = Δ, level2 = Δ⊗Δ/2, level3 = Δ⊗Δ⊗Δ/6
#     연접(S 다음 T):
#       (S⊗T)_1 = S1 + T1
#       (S⊗T)_2 = S2 + S1⊗T1 + T2
#       (S⊗T)_3 = S3 + S2⊗T1 + S1⊗T2 + T3
#   인덱스 규약: S2[j,k] = ∫∫_{u<v} dX^j_u dX^k_v (j 먼저).
#   Lévy area: A_jk = ½(S2[j,k] − S2[k,j]).
#   log-signature (BCH, 레벨 3 절단): A = S − 1,
#     logS2 = S2 − S1⊗S1/2            (반대칭 — logS2[j,k] = A_jk)
#     logS3 = S3 − ½(S1⊗S2 + S2⊗S1) + ⅓ S1⊗S1⊗S1
#
#   두 구현:
#     sig3_ref(X)  — 참조 루프(전 텐서, d임의). 검증 기준.
#     sig3_fast(D) — cumsum 벡터화(증분 행렬 입력, 전 텐서). 생산용.
#   parity는 run_wt006_verify.R에서 무작위 경로로 실측.
#
#   SPECIAL_OP escape 계약의 op_code_path 대상 파일. walk_forward=TRUE
#   (trailing 창의 결정론적 함수 — 적합 파라미터 0, full-sample 통계 없음).
# =============================================================================

# ── 참조 구현: 경로 값 행렬 X (n_points × d) → list(s1, s2, s3) ──────────────
sig3_ref <- function(X) {
  X <- as.matrix(X)
  d <- ncol(X); n <- nrow(X)
  s1 <- numeric(d); s2 <- matrix(0, d, d); s3 <- array(0, c(d, d, d))
  if (n < 2L) return(list(s1 = s1, s2 = s2, s3 = s3))
  for (i in 2:n) {
    dl <- X[i, ] - X[i - 1L, ]
    # s3 먼저 (구 s1, s2 사용)
    for (j in 1:d) for (k in 1:d) for (l in 1:d) {
      s3[j, k, l] <- s3[j, k, l] + s2[j, k] * dl[l] +
        s1[j] * dl[k] * dl[l] / 2 + dl[j] * dl[k] * dl[l] / 6
    }
    s2 <- s2 + outer(s1, dl) + outer(dl, dl) / 2
    s1 <- s1 + dl
  }
  list(s1 = s1, s2 = s2, s3 = s3)
}

# ── Chen 연접 (검증용): 두 truncated 시그니처의 텐서곱 ───────────────────────
sig3_concat <- function(A, B) {
  d <- length(A$s1)
  s1 <- A$s1 + B$s1
  s2 <- A$s2 + outer(A$s1, B$s1) + B$s2
  s3 <- A$s3 + B$s3
  for (j in 1:d) for (k in 1:d) for (l in 1:d) {
    s3[j, k, l] <- s3[j, k, l] + A$s2[j, k] * B$s1[l] + A$s1[j] * B$s2[k, l]
  }
  list(s1 = s1, s2 = s2, s3 = s3)
}

# ── 벡터화 구현: 증분 행렬 D (n_seg × d) → list(s1, s2, s3) ─────────────────
#   S2[j,k]   = Σ_i [ P_j(i−1)·D_ik + D_ij·D_ik/2 ],  P_j(i−1) = Σ_{m<i} D_mj
#   S3[j,k,l] = Σ_i [ Q_jk(i−1)·D_il + P_j(i−1)·D_ik·D_il/2 + D_ij·D_ik·D_il/6 ]
#   Q_jk(i−1) = S2[j,k]의 i−1까지 누적.
sig3_fast <- function(D) {
  D <- as.matrix(D)
  d <- ncol(D); n <- nrow(D)
  s1 <- colSums(D)
  s2 <- matrix(0, d, d); s3 <- array(0, c(d, d, d))
  if (n == 0L) return(list(s1 = numeric(d), s2 = s2, s3 = s3))
  # P[, j] = 세그먼트 i 이전까지의 누적 (shifted cumsum)
  P <- apply(D, 2, function(x) c(0, cumsum(x)[-n]))
  if (is.null(dim(P))) P <- matrix(P, nrow = n)   # n==1 방어
  for (j in 1:d) for (k in 1:d) {
    inc2 <- P[, j] * D[, k] + D[, j] * D[, k] / 2
    s2[j, k] <- sum(inc2)
    Q <- c(0, cumsum(inc2)[-n])
    for (l in 1:d) {
      s3[j, k, l] <- sum(Q * D[, l] + P[, j] * D[, k] * D[, l] / 2 +
                           D[, j] * D[, k] * D[, l] / 6)
    }
  }
  list(s1 = s1, s2 = s2, s3 = s3)
}

# ── log-signature 레벨 2·3 (BCH 절단) ────────────────────────────────────────
logsig3 <- function(S) {
  d <- length(S$s1)
  l2 <- S$s2 - outer(S$s1, S$s1) / 2
  l3 <- S$s3
  for (j in 1:d) for (k in 1:d) for (l in 1:d) {
    l3[j, k, l] <- S$s3[j, k, l] -
      (S$s1[j] * S$s2[k, l] + S$s2[j, k] * S$s1[l]) / 2 +
      S$s1[j] * S$s1[k] * S$s1[l] / 3
  }
  list(l2 = l2, l3 = l3)
}

levy_area <- function(S, j, k) (S$s2[j, k] - S$s2[k, j]) / 2

# ── 종목-창 피처 추출 (생산 경로) ────────────────────────────────────────────
#   입력: close, vol (동일 길이, 유효일만 — 0/NA 제거 후), 표준화 규약은
#   preregistration.json primary 정의 그대로.
#   출력: named numeric — A_pv(primary 원료), 레벨1·레벨2 나머지·레벨3 진단.
sig_features_pv <- function(close, vol, min_days = 40L) {
  n <- length(close)
  na_out <- c(n_days = n, A_pv = NA_real_, lvl1_p = NA_real_, lvl1_v = NA_real_,
              A_tp = NA_real_, A_tv = NA_real_,
              logsig3_ppv = NA_real_, logsig3_pvv = NA_real_)
  if (n < min_days) return(na_out)
  p <- log(close); v <- log(vol * close)
  dp <- diff(p); dv <- diff(v)
  sp <- stats::sd(dp); sv <- stats::sd(dv)
  if (!is.finite(sp) || sp <= 0 || !is.finite(sv) || sv <= 0) return(na_out)
  dt <- rep(1 / (n - 1L), n - 1L)          # 시간 채널: 유효일 위 [0,1] 정규화
  D <- cbind(t = dt, p = dp / sp, v = dv / sv)
  S <- sig3_fast(D)
  L <- logsig3(S)
  c(n_days = n,
    A_pv = unname(levy_area(S, 2L, 3L)),
    lvl1_p = unname(S$s1[2L]), lvl1_v = unname(S$s1[3L]),
    A_tp = unname(levy_area(S, 1L, 2L)), A_tv = unname(levy_area(S, 1L, 3L)),
    logsig3_ppv = unname(L$l3[2L, 2L, 3L]), logsig3_pvv = unname(L$l3[2L, 3L, 3L]))
}

# A_pv 단독(경량 — 창 강건성 21/126용)
levy_pv_only <- function(close, vol, min_days = 40L) {
  n <- length(close)
  if (n < min_days) return(NA_real_)
  dp <- diff(log(close)); dv <- diff(log(vol * close))
  sp <- stats::sd(dp); sv <- stats::sd(dv)
  if (!is.finite(sp) || sp <= 0 || !is.finite(sv) || sv <= 0) return(NA_real_)
  x <- dp / sp; y <- dv / sv
  nn <- length(x)
  Px <- c(0, cumsum(x)[-nn]); Py <- c(0, cumsum(y)[-nn])
  # A = ½(S_xy − S_yx); S_xy = Σ Px·y + Σ xy/2 ; S_yx = Σ Py·x + Σ xy/2
  (sum(Px * y) - sum(Py * x)) / 2
}

if (sys.nframe() == 0)
  cat("[signature_lib.R] Loaded — sig3_ref/sig3_fast/sig3_concat/logsig3/levy_area/sig_features_pv\n")
