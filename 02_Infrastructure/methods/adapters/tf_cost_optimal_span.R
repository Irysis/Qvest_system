# tf_cost_optimal_span.R — arXiv 2607.19497 "The Science and Practice of Trend-Following
#   Systems" (46쪽, §5 정독). 2026-07-26 라우터 regime 큐.
#   원문: 01_Literature/Alpha_Search_Recharge/20260726/mcp_arxiv/MCP_2607_19497.pdf
#
#------------------------------------------------------------------------------
# 논문 기전 (원문 §5.1~5.3, 식 5.3·5.7·5.8·5.9·5.10 — 충실한 재구성)
#------------------------------------------------------------------------------
# European TF(EWMA 필터) 시스템의 손익을 **변동성-정규화 수익률의 자기상관**으로 닫아 푼다.
#   자기상관 생성함수:  Ψν = Σ_{m≥1} ν^m ρ(m)                                  ... (5.3)
#   적재계수:           Aν = ((1−ν)/ν)Ψν ,  Bν = ((1−ν)/(1+ν))(1+2Ψν)          ... (5.8)
#                       Kν = Σ_{s≥1} ρ_s² g_{s−1}² ,  g_u = (1−ν)Σ_{m=0}^{u} ν^m ρ_{u−m}  ... (5.9)
#   일별 손익 적률(ϑ=1):
#     E[f]   = (lσ/√a)(Aν + μ²)
#     Var[f] = (lσ/√a)² [ (Bν + Aν² + κKν) + μ²(1 + Bν + 2Aν) ]                ... (5.7)
#   비용(정규화 회전율당 c):
#     E[f − cU] ≈ E[f] − (2c/√π)·σ·√(1−ν)                                       ... (5.10)
#   l = √((1+ν)/(1−ν))  (원문 항등식 l√(1−ν) = √(1+ν))
#
# ★이 어댑터가 쓰는 것은 **비용-최적 span** 이다: 위 닫힌 형 net Sharpe 를 ν 에 대해 최대화한다.
#   ⚠이것은 **sweep 이 아니다.** measurement-graduation §3 의 sweep 은 "열거된 trial 집합에서
#   백테 결과를 argmax" 하는 구조인데, 여기서는 **해석식**을 최대화한다 — 입력은 데이터에서
#   추정한 (ρ, κ, μ, c) 뿐이고 백테를 돌려 고르지 않는다. MLE 가 sweep 이 아닌 것과 같다.
#   (같은 계열의 다른 논문 2606.09025 는 216점 백테 그리드라 sweep 이다 — 그건 등재 보류했다.)
#
#------------------------------------------------------------------------------
# KR long-only 사상 · PIT
#------------------------------------------------------------------------------
# 논문의 TF 포지션은 부호가 있다(롱/숏). 헌법상 long-only·무레버리지이므로 **long leg 사상**:
#   exposure_t = clamp(TF 신호의 정규화 포지션, 0, 1) — 추세가 음이면 현금으로 물러난다.
#   이는 regime 레인의 정의(얼마나 태울지)와 정확히 같은 대상이다.
# ★PIT: 신호는 **홀딩월 시작 전** 관측만 쓴다. 각 홀딩월 i 에 대해 컷오프 = eval_date[i-1]
#   (직전 평가일 = 홀딩월 시작 전)이며 그 값을 used_cutoff 로 **신고**한다(계약 필수).
# ★자유 파라미터: 없음에 가깝다. ν 는 유도되고, c 는 헌법 상수(15bps), 자기상관 차수 S 만
#   사전고정(=24). S 를 바꿔가며 고르지 않았다.

TFCOS_C     <- 0.0015   # 편도 거래비용 15bps — 헌법 Production Constraints 상수(선택 아님)
TFCOS_S     <- 24L      # 자기상관 최대 차수. 사전고정 — sweep 아님
TFCOS_MINN  <- 36L      # 최소 관측(월). 미만이면 노출 1(중립)
TFCOS_NUGRID<- seq(0.70, 0.99, by = 0.01)   # ν 해석식 최적화용 격자(수치 최적화 격자이지 전략 trial 아님)

.tfcos_loadings <- function(rho, nu, kappa) {
  S <- length(rho)
  m <- seq_len(S)
  Psi <- sum(nu^m * rho)
  A <- ((1 - nu) / nu) * Psi
  B <- ((1 - nu) / (1 + nu)) * (1 + 2 * Psi)
  # g_u = (1-ν) Σ_{m=0..u} ν^m ρ_{u-m}   (ρ_0 := 1)
  r0 <- c(1, rho)
  g <- vapply(0:(S - 1L), function(u) (1 - nu) * sum(nu^(0:u) * r0[(u + 1L):1L]), numeric(1))
  K <- sum(rho^2 * g^2)
  list(A = A, B = B, K = K)
}

.tfcos_net_sr <- function(nu, rho, kappa, mu, a = 12) {
  L <- .tfcos_loadings(rho, nu, kappa)
  l <- sqrt((1 + nu) / (1 - nu))
  Ef  <- (l / sqrt(a)) * (L$A + mu^2)                                    # σ=1 로 정규화(σ 는 소거됨)
  Vf  <- (l / sqrt(a))^2 * ((L$B + L$A^2 + kappa * L$K) + mu^2 * (1 + L$B + 2 * L$A))
  if (!is.finite(Vf) || Vf <= 0) return(NA_real_)
  drag <- (2 * TFCOS_C / sqrt(pi)) * sqrt(1 - nu)                        # 원문 (5.10), σ=1
  (Ef - drag) / sqrt(Vf) * sqrt(a)
}

exposure_schedule <- function(ctx) {
  pr <- as.data.frame(ctx$periods)
  bg <- as.data.frame(ctx$bare_gross)
  n  <- nrow(pr)
  hold_start <- as.Date(format(as.Date(pr$decision_date), "%Y-%m-01"))
  ed <- as.Date(pr$eval_date)
  bg$Date <- as.Date(bg$Date); bg <- bg[order(bg$Date), , drop = FALSE]

  expo <- rep(1, n); cut <- as.Date(rep(NA, n)); nu_used <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    # ★컷오프: 홀딩월 시작 **이전** 관측만. eval_date 그리드에서 그 조건을 만족하는 마지막 시점.
    ok <- bg$Date < hold_start[i]
    cut[i] <- if (any(ok)) max(bg$Date[ok]) else (hold_start[i] - 1L)
    r <- bg$r[ok]
    if (length(r) < TFCOS_MINN) next
    s <- stats::sd(r, na.rm = TRUE); if (!is.finite(s) || s <= 0) next
    z <- (r - mean(r, na.rm = TRUE)) / s                      # 변동성-정규화 수익률
    S <- min(TFCOS_S, length(z) - 2L); if (S < 3L) next
    rho <- suppressWarnings(stats::acf(z, lag.max = S, plot = FALSE, demean = TRUE)$acf[-1])
    rho[!is.finite(rho)] <- 0
    kap <- {
      m4 <- mean((z - mean(z))^4); v <- stats::var(z)
      k <- if (is.finite(v) && v > 0) m4 / v^2 - 3 else 0
      if (is.finite(k)) max(min(k, 20), -2) else 0
    }
    mu <- mean(z, na.rm = TRUE) * sqrt(12)                    # 연율 드리프트(정규화 단위)

    # ── 비용-최적 span: 닫힌 형 net Sharpe 를 ν 에 대해 최대화 (해석식 최적화, 백테 아님)
    srs <- vapply(TFCOS_NUGRID, .tfcos_net_sr, numeric(1), rho = rho, kappa = kap, mu = mu)
    if (all(!is.finite(srs))) next
    nu <- TFCOS_NUGRID[which.max(replace(srs, !is.finite(srs), -Inf))]
    nu_used[i] <- nu

    # ── 그 span 의 EWMA TF 신호 → long leg 사상
    w <- (1 - nu) * nu^(rev(seq_along(z)) - 1L)               # 최근 가중
    sig <- sum(w * z) / sqrt(sum(w^2))                        # 단위분산 정규화 신호
    expo[i] <- max(0, min(1, 0.5 * (1 + tanh(sig))))          # 부호 신호 → [0,1] 노출(단조·유계)
  }
  fired <- sum(expo < 1 - 1e-9)
  cat(sprintf("[TFCostOptSpan] %d개월 · 발화 %d (%.1f%%) · 평균노출 %.4f · ν 중앙 %.2f\n",
              n, fired, 100 * fired / n, mean(expo), stats::median(nu_used, na.rm = TRUE)))
  list(exposure = data.frame(Date = ed, exposure = expo), used_cutoff = cut)
}
