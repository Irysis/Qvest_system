# proper_score_gas.R — arXiv 2608.02828 "Proper-score observation-driven filters: local geometry,
#   estimation, and continuous-time limits" (2026-08-06 라우터 risk 큐).
#
# 논문 기여: proper scoring rule 기반 GAS(Generalized Autoregressive Score) 일반화. 핵심 성질은
#   **극단값 전파의 제한** — 두꺼운 꼬리 분포의 score 가 큰 관측을 자동 감쇠해, 한 번의 극단
#   수익이 이후 변동성 추정을 오래 오염시키지 않는다. (GARCH 계열은 x² 를 그대로 먹어 전파된다.)
#
# KR 사상 (충실한 재구성): 종목별 GAS-t(1,1) 변동성 필터 → 표준화 잔차의 축소 상관 → Σ = D C D.
#   Student-t score 의 가중 (ν+1)/(ν-2+x²/σ²) 가 **바로 그 감쇠 기제**다 — |x| 가 커질수록
#   가중이 0 으로 가서 유계 영향(bounded influence). 이게 논문이 말하는 성질의 표준 구현이다.
#
# ★파라미터는 **사전 고정**이다(sweep 아님 → measurement-graduation §3 DSR 부적용):
#   ν=5(KR 월간 수익 꼬리 관례), α=0.05, β=0.94 (RiskMetrics 관례 지속성).
#   ω 는 표본분산으로 타게팅해 자유 파라미터를 늘리지 않는다. 종목별 MLE 추정은 하지 않는다 —
#   25종목 × 269개월 재추정은 과적합 표면만 키우고, 논문 기여는 지속성 값이 아니라 **감쇠 기제**다.
#
# PIT: ctx$R 은 run_sigma_ab 가 `raw[Date < start_d]` 로 만든 매수-이전 창이다(C1/C2 준수).
# 유효성(정방/대칭/유한/PD)은 wrap_sigma_estimator 가 강제한다 — 여기서 지킬 의무 없음.

GAS_NU    <- 5      # Student-t 자유도
GAS_ALPHA <- 0.05   # score 반응
GAS_BETA  <- 0.94   # 지속성

#' 단일 계열 GAS-t(1,1) 변동성 필터 → 마지막 시점 조건부 표준편차
.gas_t_sigma <- function(x) {
  x <- x[is.finite(x)]
  n <- length(x)
  v <- stats::var(x)
  if (!is.finite(v) || v <= 0 || n < 40L) return(if (is.finite(v) && v > 0) sqrt(v) else NA_real_)
  omega <- (1 - GAS_ALPHA - GAS_BETA) * v
  s2 <- v
  for (t in seq_len(n)) {
    e2 <- x[t]^2
    # ★유계 score: |x| 가 커질수록 w → 0. GARCH 의 e2 직접 투입과 다른 지점.
    w  <- (GAS_NU + 1) / (GAS_NU - 2 + e2 / s2)
    s2 <- omega + GAS_ALPHA * (w * e2 - s2) + GAS_BETA * s2
    if (!is.finite(s2) || s2 <= 0) s2 <- v      # 수치 이탈 시 무조건분산으로 되돌림
  }
  sqrt(s2)
}

sigma_estimate <- function(ctx) {
  a <- ctx$assets
  R <- ctx$R
  p <- length(a)

  # ── 1) 종목별 GAS-t 조건부 변동성 (마지막 시점)
  sd_g <- vapply(seq_len(p), function(j) .gas_t_sigma(R[, j]), numeric(1))
  # 실패 종목은 표본 sd 로 — **제외가 아니라 대체**(제외하면 선별이 바뀐다)
  sd_s <- apply(R, 2, function(x) stats::sd(x[is.finite(x)]))
  bad  <- !is.finite(sd_g) | sd_g <= 0
  sd_g[bad] <- sd_s[bad]
  sd_g[!is.finite(sd_g) | sd_g <= 0] <- stats::median(sd_g[is.finite(sd_g) & sd_g > 0])

  # ── 2) 표준화 잔차의 상관 + 항등행렬 축소
  #   축소 강도는 데이터 형상만으로 정한다(자유 파라미터 아님): δ = p/(p+T).
  #   T≫p 면 δ→0(표본상관 신뢰), p 가 T 에 근접하면 δ→0.5(강한 축소). 25종목/250일 → δ≈0.09.
  Z <- sweep(R, 2, sd_g, "/")
  Z[!is.finite(Z)] <- 0
  C <- suppressWarnings(stats::cor(Z))
  C[!is.finite(C)] <- 0
  diag(C) <- 1
  Tn <- nrow(R)
  delta <- p / (p + Tn)
  C <- (1 - delta) * C + delta * diag(p)

  S <- diag(sd_g, p) %*% C %*% diag(sd_g, p)
  dimnames(S) <- list(a, a)
  S
}
