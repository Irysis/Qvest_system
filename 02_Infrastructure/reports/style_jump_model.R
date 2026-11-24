##=============================================================================
## style_jump_model.R — 스타일 요인 국면 = 통계적 점프 모형(2상태) · 순수 함수(파일 I/O 0) · diagnostic_monitoring
##   2026-11-24 도훈 "점프 모형·동조화부터 진행" · 검토 04_Research/01_reports/style_regime_brief_review_20261124/
##
## 근거(원문):
##   Nystrup · Lindström · Madsen (2020) Learning hidden Markov models with persistent states by penalizing jumps, ESWA 150
##     https://doi.org/10.1016/j.eswa.2020.113307 — 목적함수 · 좌표 하강 적합 · 온라인 추론(중심값 고정 · 마지막 상태).
##   Shu · Mulvey (2024) Dynamic Factor Allocation Leveraging Regime-Switching Signals, arXiv 2410.14841 §3 —
##     요인별 2상태 모형 · 특징 표(요인 초과수익 EWMA 8/21/63 · RSI 8/21/63 · 스토캐스틱 %K 8/21/63 · MACD (8,21)(21,63) ·
##     하방 편차(로그 · 21) · 시장 β(21) · 시장 수익 EWMA 21) · 강세/약세 = 학습 창에서 상태별 누적 수익 · 학습 = 확장창 8~12년 ·
##     매달 다시 적합 · 사이 기간은 온라인 추론 · λ = 6년 검증 창의 가상 롱숏 샤프로 6개월마다 재선택.
##   이 판의 차이(정직): ① 특징 가중을 고르는 희소판(SJM · κ)이 아니라 같은 가중의 점프 모형(JM) ② 시장 환경 변수는 시장 수익만
##     (원 논문에서 시장 환경 특징은 가중이 거의 0) ③ 요인 수익 = 한국 FF 요인 정본(롱숏 스프레드 — '시장 대비 초과'가 아니라 요인 자체).
##
## 목적함수: min Σ_t ½‖x_t − θ_{s_t}‖² + λ Σ_t 1[s_{t−1} ≠ s_t]  (K = 2)
## PIT: 특징은 그날까지의 수익만(인과 필터) · 표준화 = 학습 창 평균 · 표준편차(고정) · 온라인 상태 = 앞으로만 가는 동적계획의
##   그날 최솟값 상태(뒤 자료 없음) · 강세/약세 표지 = 학습 창 안 수익만.
##=============================================================================

## 인과 EWMA(span w · alpha = 2/(w+1)) — y_t = a·x_t + (1−a)·y_{t−1}, y_1 = x_1
sjm_ewm <- function(x, w) {
  a <- 2 / (w + 1); x0 <- x; x0[!is.finite(x0)] <- 0
  as.numeric(stats::filter(a * x0, filter = 1 - a, method = "recursive", init = x0[1]))
}
sjm_roll <- function(x, w, f) {
  n <- length(x); out <- rep(NA_real_, n)
  if (n >= w) out[w:n] <- vapply(w:n, function(i) f(x[(i - w + 1L):i]), numeric(1))
  out
}

## 특징 14개(Shu · Mulvey 표의 요인 특징 13 + 시장 수익 EWMA 21) — 모두 그날까지의 값만
sjm_features <- function(r, mkt) {
  P <- cumprod(1 + r)
  g <- pmax(r, 0); l <- pmax(-r, 0)
  rsi <- function(w) { rs <- sjm_ewm(g, w) / pmax(sjm_ewm(l, w), 1e-12); 100 - 100 / (1 + rs) }
  stoch <- function(w) { lo <- data.table::frollapply(P, w, min); hi <- data.table::frollapply(P, w, max)
    ifelse(hi > lo, (P - lo) / (hi - lo), 0.5) }
  macd <- function(s, l2) sjm_ewm(P, s) / sjm_ewm(P, l2) - 1
  dd <- log(sqrt(pmax(sjm_ewm(pmin(r, 0)^2, 21), 1e-16)))
  em <- sjm_ewm(mkt, 21); er <- sjm_ewm(r, 21)
  beta <- (sjm_ewm(r * mkt, 21) - er * em) / pmax(sjm_ewm(mkt^2, 21) - em^2, 1e-16)
  X <- cbind(ret8 = sjm_ewm(r, 8), ret21 = er, ret63 = sjm_ewm(r, 63),
             rsi8 = rsi(8), rsi21 = rsi(21), rsi63 = rsi(63),
             k8 = stoch(8), k21 = stoch(21), k63 = stoch(63),
             macd_8_21 = macd(8, 21), macd_21_63 = macd(21, 63),
             logdd21 = dd, beta21 = beta, mkt21 = em)
  X
}

## 동적계획(비터비 · K=2) — 손실 L (T×2) · 전환 벌점 lam → 최적 상태열(1/2)
jm_dp <- function(L, lam) {
  n <- nrow(L); V <- L[1, ]; B <- matrix(0L, n, 2)
  for (t in seq_len(n)[-1]) {
    s1 <- c(V[1], V[2] + lam); s2 <- c(V[1] + lam, V[2])
    b1 <- if (s1[1] <= s1[2]) 1L else 2L; b2 <- if (s2[2] <= s2[1]) 2L else 1L
    V <- c(min(s1), min(s2)) + L[t, ]; B[t, ] <- c(b1, b2)
  }
  s <- integer(n); s[n] <- if (V[1] <= V[2]) 1L else 2L
  if (n > 1) for (t in n:2) s[t - 1] <- B[t, s[t]]
  s
}
## 온라인 추론(앞으로만 · 중심값 고정) — 날마다 그날까지의 최솟값 상태
jm_online <- function(L, lam) {
  n <- nrow(L); V <- L[1, ]; s <- integer(n); s[1] <- if (V[1] <= V[2]) 1L else 2L
  for (t in seq_len(n)[-1]) {
    V <- c(min(V[1], V[2] + lam), min(V[1] + lam, V[2])) + L[t, ]
    V <- V - min(V)                                      # 수치 안정(상대값만 쓴다)
    s[t] <- if (V[1] <= V[2]) 1L else 2L
  }
  s
}
jm_loss <- function(X, Th) cbind(0.5 * rowSums(sweep(X, 2, Th[1, ])^2), 0.5 * rowSums(sweep(X, 2, Th[2, ])^2))

## 좌표 하강 적합(Nystrup 외 2020) — 결정론 초기값 2개(63 · 21일 수익 특징의 부호) 중 목적함수가 낮은 쪽
jm_fit <- function(X, lam, max_iter = 30L, dp = jm_dp, inits = NULL) {
  if (is.null(inits)) inits <- list(as.integer(X[, "ret63"] <= 0) + 1L, as.integer(X[, "ret21"] <= 0) + 1L)
  best <- NULL
  for (s in inits) {
    if (length(unique(s)) < 2L) s[seq_len(nrow(X)) %% 2L == 0L] <- 3L - s[seq_len(nrow(X)) %% 2L == 0L]
    for (it in seq_len(max_iter)) {
      Th <- rbind(colMeans(X[s == 1L, , drop = FALSE]), colMeans(X[s == 2L, , drop = FALSE]))
      if (anyNA(Th)) break
      s2 <- dp(jm_loss(X, Th), lam)
      if (identical(s2, s)) break
      s <- s2
    }
    if (length(unique(s)) < 2L) next
    Th <- rbind(colMeans(X[s == 1L, , drop = FALSE]), colMeans(X[s == 2L, , drop = FALSE]))
    obj <- sum(jm_loss(X, Th)[cbind(seq_along(s), s)]) + lam * sum(diff(s) != 0L)
    if (is.null(best) || obj < best$obj) best <- list(Th = Th, s = s, obj = obj)
  }
  best
}

## 희소 점프 모형(SJM · Nystrup · Kolm · Lindström 2021 ESWA 184 https://doi.org/10.1016/j.eswa.2021.115558 ·
##   가중 갱신 = Witten · Tibshirani 2010 JASA 105(490) 희소 k-평균): 특징 j 의 군집 분산 감소 BCSS_j 를 소프트 임계 →
##   ‖w‖₂ = 1 · ‖w‖₁ ≤ κ. 가중 특징 x·√w 로 점프 모형을 다시 적합 — 가중이 멈출 때까지(최대 10회). κ = NULL 이면 같은 가중(JM).
sjm_weights <- function(Xs, s, kappa) {
  tss <- colSums(sweep(Xs, 2, colMeans(Xs))^2)
  wss <- Reduce(`+`, lapply(unique(s), function(k) { Y <- Xs[s == k, , drop = FALSE]; colSums(sweep(Y, 2, colMeans(Y))^2) }))
  a <- pmax(tss - wss, 0); if (sum(a) <= 0) return(rep(1 / sqrt(ncol(Xs)), ncol(Xs)))
  nw <- function(d) { v <- pmax(a - d, 0); v / sqrt(sum(v^2)) }
  if (sum(nw(0)) <= kappa) return(nw(0))
  lo <- 0; hi <- max(a)
  for (i in 1:60) { mid <- (lo + hi) / 2; if (sum(nw(mid)) > kappa) lo <- mid else hi <- mid }
  nw(hi)
}
jm_fit_sparse <- function(X, lam, kappa = NULL, outer = 10L, dp = jm_dp) {
  kappa <- suppressWarnings(as.numeric(unlist(kappa)))                # JSON 의 null · {} · "none" → 같은 가중
  if (!length(kappa) || !is.finite(kappa[1])) { f <- jm_fit(X, lam, dp = dp); if (!is.null(f)) f$w <- rep(1, ncol(X)); return(f) }
  kappa <- kappa[1]
  w <- rep(1 / sqrt(ncol(X)), ncol(X)); f <- NULL
  ini <- list(as.integer(X[, "ret63"] <= 0) + 1L, as.integer(X[, "ret21"] <= 0) + 1L)   # 가중 전 특징의 부호(결정론)
  for (o in seq_len(outer)) {
    Xw <- sweep(X, 2, sqrt(w), "*"); colnames(Xw) <- colnames(X)
    f <- jm_fit(Xw, lam, dp = dp, inits = c(list(f$s), ini)[!vapply(c(list(f$s), ini), is.null, TRUE)]); if (is.null(f)) return(NULL)
    w2 <- sjm_weights(X, f$s, kappa)
    if (max(abs(w2 - w)) < 1e-4) { w <- w2; break }
    w <- w2
  }
  Xw <- sweep(X, 2, sqrt(w), "*"); colnames(Xw) <- colnames(X)
  f <- jm_fit(Xw, lam, dp = dp, inits = c(list(f$s), ini)); if (!is.null(f)) f$w <- w
  f
}

## 한 요인의 그날 국면(운영 · 매달 다시 적합 규칙과 같게: 마지막 완결 월말에 적합 → 그 뒤는 온라인)
##   r · mkt · dates = 그날까지 · lam = 등록된 값 · 학습 창 = 적합일에서 최대 12년(최소 8년)
sw_jump_regime <- function(r, mkt, dates, lam, kappa = NULL, train_min_y = 8, train_max_y = 12, refit_months = 1L,
                           online = jm_online, dp = jm_dp) {
  ok <- is.finite(r) & is.finite(mkt); r <- r[ok]; mkt <- mkt[ok]; dates <- as.Date(dates[ok])
  X <- sjm_features(r, mkt)
  keep <- stats::complete.cases(X); X <- X[keep, , drop = FALSE]; rr <- r[keep]; dd <- dates[keep]
  n <- nrow(X); if (n < 300L) return(list(ok = FALSE, reason = "표본 부족"))
  ym <- format(dd, "%Y-%m")
  me <- which(c(ym[-1] != ym[-n], FALSE))                  # 각 달의 마지막 거래일(진행월 제외)
  if (refit_months > 1L) me <- me[as.integer(format(dd[me], "%m")) %% refit_months == 0L]   # λ 선택 때와 같은 적합 주기
  if (!length(me)) return(list(ok = FALSE, reason = "완결 월말 없음"))
  ## 적합이 한 상태로 무너지면(두 상태 구분 없음) 직전 적합일로 물러난다(최대 4번 · 과거 자료만 — 연구 실행 style_jump_select.R 과 같은 규칙)
  fit <- NULL
  for (fit_i in rev(utils::tail(me, 5L))) {
    t0 <- max(1L, which(dd >= (dd[fit_i] - round(365.25 * train_max_y)))[1])
    if (as.numeric(dd[fit_i] - dd[t0]) < 365.25 * train_min_y) return(list(ok = FALSE, reason = "학습 창 8년 미만"))
    tr <- t0:fit_i
    mu <- colMeans(X[tr, , drop = FALSE]); sg <- apply(X[tr, , drop = FALSE], 2, stats::sd); sg[!is.finite(sg) | sg == 0] <- 1
    Z <- sweep(sweep(X, 2, mu), 2, sg, "/")
    fit <- jm_fit_sparse(Z[tr, , drop = FALSE], lam, kappa, dp = dp)
    if (!is.null(fit)) break
  }
  if (is.null(fit)) return(list(ok = FALSE, reason = "적합 실패(한 상태 · 직전 4회 포함)"))
  mret <- vapply(1:2, function(k) mean(rr[tr][fit$s == k]), numeric(1))
  bull <- which.max(mret)
  Zw <- sweep(Z[t0:n, , drop = FALSE], 2, sqrt(fit$w), "*")
  so <- online(jm_loss(Zw, fit$Th), lam)                   # 학습 시작부터 그날까지 앞으로만(적합 가중 그대로)
  st <- ifelse(so == bull, 1L, -1L)
  last <- st[length(st)]; run <- rle(st); dur <- run$lengths[length(run$lengths)]
  list(ok = TRUE, state = last, days = dur, since = dd[t0:n][length(st) - dur + 1L], as_of = dd[n],
       exp_ann = 252 * mret[if (last == 1L) bull else 3L - bull], fit_date = dd[fit_i], train_from = dd[t0],
       lambda = lam, series = data.frame(Date = dd[t0:n], state = st))
}
