# beta_controlled_alpha.R — β-통제 α 병기 계약 (measurement-graduation.md §2, 2026-08-22)
#
# 왜 있나:
#   §2 는 "PORT_t 를 보고할 때 β 를 통제한 α 와 t(α) 를 함께 보고" 하도록 **의무화**했다.
#   그런데 계산 함수가 없어 매 라운드 손으로 짜게 된다 — 그러면 구현이 갈리고,
#   갈리면 수치를 나란히 인용할 수 없다(오늘 하루 세 번 겪은 정규화 문제와 같은 계통).
#   ⇒ 한 번 정의하고 소비자는 이걸 부른다.
#
# 왜 필요한가 (기전):
#   PORT_t 는 `mean(r − r_bm)` 의 t 통계량이므로 **α + (β−1)·E[r_bm]** 를 섞어 본다.
#   · β>1 → 알파를 **과대** 표시 (DFA T3 실측: 활성수익의 52%가 β 기여, PORT_t 1.065 vs t(α) 0.560)
#   · β<1 → 알파를 **과소** 표시 (q90_pinball 실측: β 기여 −37.3%, PORT_t 0.837 vs t(α) 1.207)
#   ★양방향이다. 과소 쪽을 모르면 **살릴 것을 버린다**.
#
# ★판정 규칙은 불변: HARD 게이트는 여전히 PORT_t ≥ 2.95 다.
#   이 함수는 판정을 바꾸지 않고 **서술의 근거**를 정한다 —
#   "신호가 실재한다"·"선별력이 있다" 류는 t(α) 를 근거로만 할 수 있다(§2).
#
# 사용:
#   source("02_Infrastructure/contracts/beta_controlled_alpha.R")
#   res <- beta_controlled_alpha(port_ret, bench_ret, periods_per_year = 12, nw_lag = 3)
#   res$t_alpha · res$alpha_ann · res$beta · res$port_t · res$beta_share

# Newey-West 보정 t (HAC, Bartlett kernel). lag 기본 3 = §2 규약.
.nw_fit <- function(y, X = NULL, lag = 3L) {
  y <- as.numeric(y)
  n <- length(y)
  Xm <- if (is.null(X)) matrix(1, n, 1) else cbind(1, as.matrix(X))
  k <- ncol(Xm)
  if (n <= k) stop("관측이 회귀 자유도보다 적습니다 (n=", n, ", k=", k, ")")
  XtXi <- tryCatch(solve(crossprod(Xm)), error = function(e)
    stop("설계행렬 특이 — 벤치가 상수이거나 완전공선"))
  bhat <- as.numeric(XtXi %*% crossprod(Xm, y))
  e <- as.numeric(y - Xm %*% bhat)
  S <- matrix(0, k, k)
  for (i in seq_len(n)) S <- S + e[i]^2 * tcrossprod(Xm[i, ])
  if (lag >= 1L) for (L in seq_len(lag)) {
    w <- 1 - L / (lag + 1)
    if (n > L) for (i in (L + 1):n) {
      u <- e[i] * Xm[i, ]; v <- e[i - L] * Xm[i - L, ]
      S <- S + w * (tcrossprod(u, v) + tcrossprod(v, u))
    }
  }
  V <- XtXi %*% S %*% XtXi
  se <- sqrt(pmax(diag(V), 0))
  list(coef = bhat, se = se, t = ifelse(se > 0, bhat / se, NA_real_), n = n)
}

#' @param port_ret  포트폴리오 수익 시계열 (net 권장 — 어느 것을 썼는지 라벨에 남길 것)
#' @param bench_ret 같은 길이·같은 정렬의 벤치마크 수익
#' @param periods_per_year 연율화 계수 (월간 12 · 일간 252)
#' @param nw_lag    Newey-West lag (§2 규약 = 3)
beta_controlled_alpha <- function(port_ret, bench_ret, periods_per_year = 12, nw_lag = 3L) {
  r <- as.numeric(port_ret); b <- as.numeric(bench_ret)
  if (length(r) != length(b)) stop("두 시계열 길이가 다릅니다 — 정렬(merge)을 먼저 하십시오")
  ok <- is.finite(r) & is.finite(b)
  # ★결손을 조용히 0 으로 채우지 않는다. 몇 개를 버렸는지 반환에 남긴다.
  n_drop <- sum(!ok)
  r <- r[ok]; b <- b[ok]
  if (length(r) < 12) stop("유효 관측 12 미만 — 판정 불가")

  active <- r - b
  f_act <- .nw_fit(active, NULL, nw_lag)          # PORT_t basis
  f_reg <- .nw_fit(r, matrix(b, ncol = 1), nw_lag) # r = α + β·bm + ε

  alpha_p <- f_reg$coef[1]; beta <- f_reg$coef[2]
  beta_contrib <- (beta - 1) * mean(b)
  share <- if (abs(mean(active)) > .Machine$double.eps) beta_contrib / mean(active) else NA_real_

  list(
    n = length(r), n_dropped = n_drop, nw_lag = nw_lag,
    port_t          = unname(f_act$t[1]),                 # = PORT_t (활성수익 basis)
    active_ann      = mean(active) * periods_per_year,
    alpha_ann       = alpha_p * periods_per_year,
    t_alpha         = unname(f_reg$t[1]),
    beta            = unname(beta),
    t_beta          = unname(f_reg$t[2]),
    bench_ann       = mean(b) * periods_per_year,
    beta_contrib_ann = beta_contrib * periods_per_year,
    beta_share      = share,                              # 활성수익 중 β 기여 비중
    direction = if (!is.finite(beta)) "미상"
                else if (beta > 1) "β>1 — PORT_t 가 α 를 과대 표시"
                else if (beta < 1) "β<1 — PORT_t 가 α 를 과소 표시"
                else "β=1 — PORT_t ≈ t(α)",
    metric_type = "backtested_beta_controlled",
    note = paste0("HARD 게이트는 PORT_t 로 판정(불변). t(α) 는 '신호가 실재한다' 류 ",
                  "서술의 유일한 근거(measurement-graduation.md §2).")
  )
}

#' 사람이 읽는 1블록 — 보고서에 그대로 붙일 수 있게.
format_beta_alpha <- function(x, hard = 2.95) {
  sprintf(paste0(
    "  n=%d (버린 관측 %d) · NW lag-%d\n",
    "  활성수익 %+.3f%%/yr · PORT_t %+.3f\n",
    "  β-통제 α %+.3f%%/yr · t(α) %+.3f · β %.3f (t %+.2f)\n",
    "  분해: α 기여 %+.3f%% + (β−1)·E[bm] %+.3f%% (E[bm] %+.2f%%/yr) → β 비중 %.1f%%\n",
    "  %s\n",
    "  HARD %.2f 대비: PORT_t %s · t(α) %s\n"),
    x$n, x$n_dropped, x$nw_lag,
    x$active_ann * 100, x$port_t,
    x$alpha_ann * 100, x$t_alpha, x$beta, x$t_beta,
    x$alpha_ann * 100, x$beta_contrib_ann * 100, x$bench_ann * 100,
    100 * (if (is.finite(x$beta_share)) x$beta_share else NA_real_),
    x$direction, hard,
    if (is.finite(x$port_t) && x$port_t >= hard) "통과" else "미달",
    if (is.finite(x$t_alpha) && x$t_alpha >= hard) "통과" else "미달")
}
