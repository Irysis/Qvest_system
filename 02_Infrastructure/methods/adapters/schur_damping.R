# schur_damping.R — arXiv 2606.14798 "Two Sides of Schur Damping: High-Dimensional
#   Pseudo-Likelihoods and Portfolio Allocation" (Cotton). 2026-06-18 라우터 optimizer 큐.
#   원문: 01_Literature/Alpha_Search_Recharge/20260618/mcp_arxiv/MCP_2606_14798.pdf (5쪽, 전문 정독)
#
#------------------------------------------------------------------------------
# 논문 기전 (원문 §2~§3, 충실한 재구성 — 날조 아님)
#------------------------------------------------------------------------------
# 자산을 블록 k 와 그 조건집합 c(나머지)로 나누면 Schur 보수
#     S_k = R_kk − R_kc R_cc^{-1} R_ck                                    ... 원문 (1)
# 는 "나머지 북으로 최적 헤지한 뒤 남는 위험"이다(b_k = R_cc^{-1} R_ck 가 그 헤지).
# 추정오차 때문에 R_cc^{-1} 가 과적합하므로 **하나의 파라미터 γ 로 감쇠**한다:
#     b_k(γ) = γ b_k ,   S_k(γ) = (1−γ) R_kk + γ S_k                      ... 원문 (2)
#   γ=0 → 블록을 서로 독립 취급 = **hierarchical risk parity**
#   γ=1 → 교차헤지 완전 활용 = **최소분산**
# 즉 γ 는 HRP↔min-var 를 잇는 1-파라미터 보간이다. 자본은 **잔여위험의 역수**로 배분한다.
#
# ★논문의 기여이자 이 어댑터가 구현하는 핵심: γ 의 **닫힌 해**
#     γ* = (n−2)ρ² / [ (n−2)ρ² + (1−ρ²) ]                                 ... 원문 (3)
#   ρ² = 그 결합의 조건부 R², n = 관측 수. James–Stein/Wiener 수축이며 교차블록 항에
#   국한한 Ledoit–Wolf 강도와 동치다("추정된 결합을 얼마나 믿을 것인가").
#   데이터가 쌓이거나 결합이 강해지면 →1, 결합이 불안정하면 →0.
#
#------------------------------------------------------------------------------
# KR long-only 사상
#------------------------------------------------------------------------------
# 논문은 배분 규칙 자체를 다루므로 L/S 가정이 없다 — 사상 왜곡 없이 그대로 쓴다.
# 블록은 상관거리 계층군집으로 만든다(원문 Table 1 "portfolio side: block/cluster structure").
# 반환은 **선호 벡터**다. long-only · Σw=1 · w≤0.20 은 wrap_adapter 가 강제한다.
#
# ★논문이 열어둔 부분과 이 구현이 정한 것을 구분해 적는다(원문 §3 "the one genuinely open
#   choice—how to set the damping"):
#   · 논문이 준 것 = 식 (1)(2)(3) 전부. γ* 는 닫힌 해이므로 **자유 파라미터가 아니다**.
#   · 이 구현이 정한 것 = ①블록 구성(상관거리 average-linkage, k=⌈√p⌉) ②ρ² 의 다변량 정의를
#     tr 기반(아래)으로 잡은 것 ③블록 내부는 역분산. 셋 다 논문이 지정하지 않은 자유도이며,
#     sweep 하지 않고 **사전 고정**했다(단일 사전 선택 → DSR 부적용, selection_type="chain").
#
# PIT: ctx$R 은 하네스가 `raw[Date < start_d]` 로 만든 trailing 행렬이다(C1/C2 준수).
#      이 어댑터는 ctx 밖 데이터를 일절 읽지 않는다 — 구조적으로 미래참조 불가.

SCHUR_MIN_OBS   <- 60L    # 상관 추정 최소 관측 (미만이면 결합을 믿지 않음 = γ*→0 경로)
SCHUR_RIDGE     <- 1e-8   # R_cc 역행렬 수치 안정화 (감쇠 γ 와 별개의 순수 수치 항)

method_weights <- function(ctx) {
  a <- ctx$assets
  p <- length(a)
  R <- ctx$R
  if (is.null(R) || !is.matrix(R) || p < 2L) return(stats::setNames(rep(1, p), a))
  R <- R[, a, drop = FALSE]
  keep <- apply(R, 2, function(x) sum(is.finite(x)) >= SCHUR_MIN_OBS)
  n <- nrow(R)

  # ── 상관행렬 + 분산 (결측은 pairwise 로 두되, 이후 비유한은 중립 처리)
  C <- suppressWarnings(stats::cor(R, use = "pairwise.complete.obs"))
  C[!is.finite(C)] <- 0
  diag(C) <- 1
  v <- suppressWarnings(apply(R, 2, stats::var, na.rm = TRUE))
  v[!is.finite(v) | v <= 0] <- stats::median(v[is.finite(v) & v > 0], na.rm = TRUE)
  if (!is.finite(stats::median(v))) return(stats::setNames(rep(1, p), a))

  # ── 블록 구성: 상관거리 계층군집. 논문이 지정하지 않은 자유도 — 사전 고정.
  #    d = sqrt(0.5(1−C)) 는 HRP 표준 상관거리.
  k_blocks <- max(2L, min(p - 1L, as.integer(ceiling(sqrt(p)))))
  grp <- tryCatch({
    # ★`pmax(0, C)` 를 쓰면 안 된다 — 첫 인자가 스칼라라 **행렬 속성이 떨어져** 벡터가 되고,
    #   as.dist 가 "non-square matrix" 경고와 함께 엉뚱한 거리를 만든다. 그러면 군집이
    #   조용히 실패해 자산별 블록으로 낙하하고, **논문의 블록 구조가 안 쓰인 채 통과**한다
    #   (실측 2026-08-13: p=8 인데 블록 8 = 완전 조건화. 비-퇴화 검사는 통과해서 안 보였다).
    D <- 0.5 * (1 - C); D[D < 0] <- 0; diag(D) <- 0
    stats::cutree(stats::hclust(stats::as.dist(sqrt(D)), method = "average"), k = k_blocks)
  }, error = function(e) rep(1L, p))
  if (length(unique(grp)) < 2L) grp <- seq_len(p)   # 군집 실패 → 자산별 블록(=완전 조건화)

  # ── 블록별 감쇠 Schur 보수 → 잔여위험
  blocks <- split(seq_len(p), grp)
  resid_risk <- rep(NA_real_, length(blocks))
  gammas     <- rep(NA_real_, length(blocks))
  for (bi in seq_along(blocks)) {
    kk <- blocks[[bi]]; cc <- setdiff(seq_len(p), kk)
    Rkk <- C[kk, kk, drop = FALSE]
    if (!length(cc)) { S <- Rkk; g <- 0 } else {
      Rcc <- C[cc, cc, drop = FALSE]; Rkc <- C[kk, cc, drop = FALSE]
      Rcc_inv <- tryCatch(solve(Rcc + diag(SCHUR_RIDGE, length(cc))), error = function(e) NULL)
      if (is.null(Rcc_inv)) { S <- Rkk; g <- 0 } else {
        S_raw <- Rkk - Rkc %*% Rcc_inv %*% t(Rkc)                      # 원문 (1)
        # ρ² = 헤지가 설명한 블록 분산 비율 (다변량 스칼라화 — 이 구현이 정한 부분)
        rho2 <- 1 - sum(diag(S_raw)) / max(sum(diag(Rkk)), 1e-12)
        rho2 <- min(max(rho2, 0), 1 - 1e-12)
        # 원문 (3) 닫힌 해. n−2 는 관측 수에서 도출 — 튜닝 대상 아님.
        g <- ((n - 2) * rho2) / ((n - 2) * rho2 + (1 - rho2))
        if (!is.finite(g)) g <- 0
        S <- (1 - g) * Rkk + g * S_raw                                 # 원문 (2)
      }
    }
    gammas[bi] <- g
    # 블록 잔여위험: 블록 내 역변동성 결합의 감쇠-잔여 분산. 상관 스케일 → 분산 스케일 복원.
    sdv <- sqrt(v[kk]); u <- 1 / pmax(sdv, 1e-12); u <- u / sum(u)
    q <- as.numeric(t(u * sdv) %*% S %*% (u * sdv))
    resid_risk[bi] <- if (is.finite(q) && q > 0) sqrt(q) else NA_real_
  }
  if (all(!is.finite(resid_risk))) return(stats::setNames(rep(1, p), a))
  resid_risk[!is.finite(resid_risk)] <- stats::median(resid_risk, na.rm = TRUE)

  # ── 자본 배분: 블록 간 = 잔여위험 역수(원문 §2 "splitting capital by inverse residual risk")
  #    블록 내 = 역분산(이 구현이 정한 부분)
  wb <- 1 / pmax(resid_risk, 1e-12); wb <- wb / sum(wb)
  w <- rep(0, p)
  for (bi in seq_along(blocks)) {
    kk <- blocks[[bi]]
    wi <- 1 / pmax(v[kk], 1e-12); wi <- wi / sum(wi)
    w[kk] <- wb[bi] * wi
  }
  # 이력 부족 종목은 **제외가 아니라 중립** — 제외하면 선별이 바뀌어 A/B 통제가 깨진다.
  if (any(!keep)) w[!keep] <- stats::median(w[keep], na.rm = TRUE)
  w[!is.finite(w) | w < 0] <- 0
  if (sum(w) <= 0) return(stats::setNames(rep(1, p), a))

  cat(sprintf("[SchurDamping] p=%d · 블록 %d · n=%d · γ* 중앙 %.3f (범위 %.3f~%.3f)\n",
              p, length(blocks), n, stats::median(gammas, na.rm = TRUE),
              min(gammas, na.rm = TRUE), max(gammas, na.rm = TRUE)))
  stats::setNames(w, a)
}
