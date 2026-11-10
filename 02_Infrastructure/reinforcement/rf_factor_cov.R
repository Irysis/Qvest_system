#==============================================================================
# rf_factor_cov.R — 요인 위험모형 공분산 공급자(as-of) · Σ_t = B_t Ω_t B_tᵀ + D_t   (2026-11-10 · 레인 E3 신설)
#
# 왜: 살아 있는 구성 경로(셀 엔진 catalog 분기 rf_cell_engine.R:521-522)가 비중 방법에 넘기는 Σ 는
#   창 252일 표본 공분산 stats::cov(R) 하나뿐이다. 요인 구조 Σ 와 위기 조건부 Σ 는 QEPM WT 체인 동결(09-25)과 함께
#   살아 있는 경로에서 빠졌다. 이 모듈은 그 Σ 를 **순수 함수**로 낸다 — 데이터를 스스로 찾지 않고, 받은 자료만 쓴다.
#
# 모형 3종(model)
#   ts  — 관측 요인 시계열 모형(Fan, Fan & Lv 2008 · J. Econometrics 147(1):186-197 · doi:10.1016/j.jeconom.2008.09.017).
#         요인 수익 F(시장 · 크기 · 가치 · 수익성 · 투자 · 모멘텀 = FF6 — build_kr_factor_returns.R 산출 · 읽기 전용)에
#         종목 수익을 시계열 회귀해 B(N×K) · 잔차 분산 D 를 얻고 Ω = cov(F). Σ = BΩBᵀ + diag(D).
#         요인 근거: Fama & French (2015) JFE 116(1):1-22 doi:10.1016/j.jfineco.2014.10.010(5요인) +
#         Carhart (1997) JF 52(1):57-82 doi:10.1111/j.1540-6261.1997.tb03808.x(모멘텀) = FF6(Fama & French 2018 JFE 128(2):234-252).
#   pca — 통계 요인 모형(요인 = 창 안 주성분 · 요인 수 K = Bai & Ng 2002 IC_p2 · Econometrica 70(1):191-221
#         doi:10.1111/1468-0262.00273). 관측 요인을 못 받았을 때의 as-of 대안(Fan, Liao & Mincheva 2013 POET 의
#         '엄격 요인' 판 — 잔차 비대각 임계화는 하지 않는다 · JRSS-B 75(4):603-680 doi:10.1111/rssb.12016).
#   cs  — 특성 횡단면 모형(BARRA 형 — Menchero, Orr & Wang 2011 'The Barra US Equity Model (USE4)' MSCI 방법론 문서).
#         노출 X = 결정 시점 as-of 특성 스냅샷(팩터 DB 결합용 뷰 fc_load_month() 경유만 · C15) · 요인 수익 f_s = 일별 횡단면 OLS
#         · Ω = cov(f) · D = 잔차 분산. 노출 부호(방향)는 Σ 를 바꾸지 않는다(열 부호 반전 → Ω 행·열 부호 반전 → XΩXᵀ 불변).
#
# 위기 조건부 변형(variant)
#   base     — 창 전체.
#   downside — 시장 요인이 음수인 날만으로 B · Ω · D (하방 베타 — Ang, Chen & Xing 2006 'Downside Risk' RFS 19(4):1191-1239
#              doi:10.1093/rfs/hhj035). 그 날들은 전부 결정 시점 이전이다(동시점 조건이지 미래 조건이 아니다).
#   dd_state — 시장 누적 경로가 직전 고점 대비 20% 이상 밑인 날(Lunde & Timmermann 2004 JBES 22(3):253-273
#              doi:10.1198/073500104000000136 의 약세장 문턱 20%). ★상태는 그 날까지의 경로로만 판정한다(as-of) —
#              LT 의 사후 전환점 판정(미래 경로가 확정)은 쓰지 않는다. Ω_state 는 결정 시점 이전 전체 요인 이력(확장 창)에서,
#              B · D 는 종목 창에서(배리어 스트레스 방식: 노출 유지 · 요인 공분산만 위기판).
#   상태 표본이 min_state_obs 미만이면 base 로 돌아가고 diag$fallback 에 사유를 적는다(조용히 바꾸지 않는다).
#
# 안전장치
#   수축(옵션) — Ledoit & Wolf (2004) 'A well-conditioned estimator for large-dimensional covariance matrices'
#               JMVA 88(2):365-411 doi:10.1016/S0047-259X(03)00096-4 · 목표 = 척도 항등(νI). Ω(K 작음)에는 기본 끔 · 표본 Σ 대조용.
#   조건수 가드 — κ(Σ) > kappa_max 면 고유값 바닥을 λ_max/kappa_max 로 올린다(배정밀도 선형계 상대오차 ≈ κ·ε —
#               Higham 2002 'Accuracy and Stability of Numerical Algorithms' 2판 SIAM §7). 요인 모형은 D>0 이면 구조상 양의 정부호.
#
# PIT(C1 · C2 · C3 · C14): 순수 함수들은 받은 행렬만 본다. 날짜가 있는 입력의 유일한 진입점 rfc_sigma_asof() 가
#   종목 수익 · 요인 수익 둘 다 Date < decision_date 로 자른다(셀 엔진 C2 규약과 같다 — rf_cell_engine.R:513).
#   요인 수익 파일 자체의 시점성(구성일 재무 = Factor_Date ≤ 구성일 · 다음 거래일부터 보유)은 빌더 계약이다(build_kr_factor_returns.R:18).
# 수치는 전부 rf_factor_cov.json(모듈 옆 설정 초안 · 근거 문구 포함). 등록부 편입은 총괄 결정.
#==============================================================================

suppressWarnings(suppressMessages({ library(data.table); library(jsonlite) }))

.RFC_MARKER <- file.path("02_Infrastructure", "reinforcement", "rf_factor_cov.R")
.rfc_root <- function() {
  for (k in c("QM_ROOT", "CLAUDE_PROJECT_DIR")) {
    v <- gsub("\\\\", "/", Sys.getenv(k, ""))
    if (nzchar(v) && file.exists(file.path(v, .RFC_MARKER))) return(v)
  }
  d <- getwd()
  for (i in 1:6) { if (file.exists(file.path(d, .RFC_MARKER))) return(d); d <- dirname(d) }
  stop("[rfc] 저장소 루트를 찾지 못했다(QM_ROOT 또는 작업 디렉터리)")
}

#' 설정 — 모듈 옆 rf_factor_cov.json. `_source` 키는 근거 문구(값 아님).
rfc_config <- function(path = NULL) {
  p <- path %||% file.path(.rfc_root(), "02_Infrastructure", "reinforcement", "rf_factor_cov.json")
  cfg <- fromJSON(p, simplifyVector = TRUE)
  need <- c("factor_columns", "market_column", "min_obs_per_param", "dd_state_threshold",
            "kappa_max", "bai_ng_kmax", "shrink_omega", "shrink_sigma_target", "max_factor_staleness_days")
  miss <- setdiff(need, names(cfg))
  if (length(miss)) stop("[rfc] 설정 키 결손: ", paste(miss, collapse = ", "))
  cfg
}
`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a

#------------------------------------------------------------------------------
# 기본 부품
#------------------------------------------------------------------------------
.rfc_cov <- function(X) { X <- as.matrix(X); stats::cov(X) }

#' Ledoit-Wolf (2004) 척도 항등 목표 수축. X = T×p 관측(평균 제거는 여기서). 반환 list(S, delta)
#'   S* = δ·νI + (1−δ)·S · ν = tr(S)/p · δ = b²/d² (식 14 계열 · 노름 ‖A‖² = tr(AAᵀ)/p)
rfc_lw2004 <- function(X) {
  X <- as.matrix(X); Tn <- nrow(X); p <- ncol(X)
  Xc <- sweep(X, 2, colMeans(X))
  S <- crossprod(Xc) / Tn
  nu <- sum(diag(S)) / p
  d2 <- sum((S - nu * diag(p))^2) / p
  b2bar <- 0
  for (t in seq_len(Tn)) { x <- Xc[t, ]; b2bar <- b2bar + sum((tcrossprod(x) - S)^2) / p }
  b2bar <- b2bar / Tn^2
  b2 <- min(b2bar, d2)
  delta <- if (d2 > 0) b2 / d2 else 1
  Ss <- delta * nu * diag(p) + (1 - delta) * S
  Ss <- Ss * Tn / (Tn - 1)                         # stats::cov 와 같은 척도(T−1)로 맞춘다
  dimnames(Ss) <- list(colnames(X), colnames(X))
  list(S = Ss, delta = delta)
}

#' 종목별 OLS: R(T×N) ~ 1 + F(T×K). 반환 B(N×K) · resid(T×N) · D(N, 자유도 T−K−1 보정)
rfc_ols_betas <- function(R, F) {
  R <- as.matrix(R); F <- as.matrix(F)
  if (nrow(R) != nrow(F)) stop("[rfc] R · F 행 수 불일치")
  Z <- cbind(1, F)
  if (nrow(Z) <= ncol(Z)) stop(sprintf("[rfc] 관측 %d ≤ 모수 %d — 회귀 불가", nrow(Z), ncol(Z)))
  qz <- qr(Z)
  if (qz$rank < ncol(Z)) stop("[rfc] 요인 행렬 계수 부족(공선) — 요인 열을 줄일 것")
  coef <- qr.coef(qz, R)                              # (K+1)×N
  res <- R - Z %*% coef
  dof <- nrow(Z) - ncol(Z)
  D <- colSums(res^2) / dof
  B <- t(coef[-1, , drop = FALSE]); dimnames(B) <- list(colnames(R), colnames(F))
  list(B = B, resid = res, D = stats::setNames(D, colnames(R)), dof = dof)
}

#' Bai & Ng (2002) IC_p2 — 요인 수 선택. R = T×N(평균 제거)
rfc_bai_ng_k <- function(R, kmax) {
  R <- sweep(as.matrix(R), 2, colMeans(R)); Tn <- nrow(R); N <- ncol(R)
  kmax <- max(1L, min(as.integer(kmax), min(Tn, N) - 1L))
  ev <- eigen(crossprod(R), symmetric = TRUE)
  tot <- sum(R^2)
  ic <- vapply(0:kmax, function(k) {
    V <- (tot - if (k) sum(ev$values[seq_len(k)]) else 0) / (N * Tn)
    log(max(V, .Machine$double.eps)) + k * ((N + Tn) / (N * Tn)) * log(min(N, Tn))
  }, numeric(1))
  max(1L, which.min(ic) - 1L)
}

#' 조건수 가드 + 대칭화. 반환 list(S, kappa_before, kappa_after, clipped)
rfc_guard <- function(S, kappa_max) {
  S <- (S + t(S)) / 2
  e <- eigen(S, symmetric = TRUE)
  lmax <- max(e$values); lmin <- min(e$values)
  k0 <- if (lmin > 0) lmax / lmin else Inf
  if (is.finite(k0) && k0 <= kappa_max) return(list(S = S, kappa_before = k0, kappa_after = k0, clipped = FALSE))
  floor_ <- lmax / kappa_max
  v <- pmax(e$values, floor_)
  S2 <- e$vectors %*% diag(v, length(v)) %*% t(e$vectors); S2 <- (S2 + t(S2)) / 2
  dimnames(S2) <- dimnames(S)
  list(S = S2, kappa_before = k0, kappa_after = max(v) / min(v), clipped = TRUE)
}

#' 상태 표식(as-of): 시장 열 m(일별 수익) → 논리 벡터
#'   downside = m < 0 · dd_state = 그 날까지의 누적 경로가 직전 고점 대비 thr 이상 밑(경로 시작 = 1)
rfc_state_mask <- function(m, variant, thr) {
  m <- as.numeric(m)
  if (identical(variant, "downside")) return(is.finite(m) & m < 0)
  if (identical(variant, "dd_state")) {
    m[!is.finite(m)] <- 0
    nav <- cumprod(1 + m); pk <- cummax(c(1, nav))[-1L]
    return(1 - nav / pk >= thr)
  }
  rep(TRUE, length(m))
}

.rfc_min_obs <- function(K, cfg) as.integer(ceiling(cfg$min_obs_per_param * (K + 1)))

#------------------------------------------------------------------------------
# 모형
#------------------------------------------------------------------------------
#' 관측 요인 시계열 모형. R(T×N) · F(T×K) 같은 행(날짜) · F_hist = 확장 창 요인 이력(dd_state 의 Ω 용 · 없으면 F)
rfc_ts_cov <- function(R, F, cfg, variant = "base", F_hist = NULL) {
  R <- as.matrix(R); F <- as.matrix(F)
  ok_col <- colSums(is.finite(F)) == nrow(F)                  # 창 안에서 결측 없는 요인만(가용성만으로 거른다 · as-of)
  dropped <- colnames(F)[!ok_col]
  F <- F[, ok_col, drop = FALSE]
  if (!ncol(F)) stop("[rfc] 창 안에 결측 없는 요인이 없다")
  K <- ncol(F); mkt <- cfg$market_column
  fb <- NA_character_
  rows <- rep(TRUE, nrow(F))
  if (identical(variant, "downside")) {
    if (!mkt %in% colnames(F)) stop("[rfc] downside 변형에 시장 열 '", mkt, "' 이 없다")
    rows <- rfc_state_mask(F[, mkt], "downside", cfg$dd_state_threshold)
    if (sum(rows) < .rfc_min_obs(K, cfg)) { fb <- sprintf("downside 표본 %d < %d → base", sum(rows), .rfc_min_obs(K, cfg)); rows[] <- TRUE }
  }
  if (sum(rows) < .rfc_min_obs(K, cfg)) stop(sprintf("[rfc] 관측 %d < 최소 %d (모수당 %s × (K+1))", sum(rows), .rfc_min_obs(K, cfg), cfg$min_obs_per_param))
  fit <- rfc_ols_betas(R[rows, , drop = FALSE], F[rows, , drop = FALSE])
  Fo <- F[rows, , drop = FALSE]
  if (identical(variant, "dd_state")) {
    H <- as.matrix(F_hist %||% F)
    H <- H[, colnames(F), drop = FALSE]
    H <- H[stats::complete.cases(H), , drop = FALSE]
    if (!mkt %in% colnames(H)) stop("[rfc] dd_state 변형에 시장 열 '", mkt, "' 이 없다")
    st <- rfc_state_mask(H[, mkt], "dd_state", cfg$dd_state_threshold)
    if (sum(st) >= .rfc_min_obs(K, cfg)) Fo <- H[st, , drop = FALSE]
    else fb <- sprintf("dd_state 표본 %d < %d → base", sum(st), .rfc_min_obs(K, cfg))
  }
  Om <- if (isTRUE(cfg$shrink_omega)) rfc_lw2004(Fo)$S else .rfc_cov(Fo)
  S <- fit$B %*% Om %*% t(fit$B) + diag(fit$D, length(fit$D))
  dimnames(S) <- list(colnames(R), colnames(R))
  g <- rfc_guard(S, cfg$kappa_max)
  list(Sigma = g$S, B = fit$B, Omega = Om, D = fit$D, K = K, model = "ts", variant = variant,
       diag = list(n_obs = sum(rows), n_omega = nrow(Fo), dropped_factors = dropped, fallback = fb,
                   kappa_before = g$kappa_before, kappa_after = g$kappa_after, clipped = g$clipped))
}

#' 통계 요인(주성분) 모형 — 요인 수 = Bai-Ng IC_p2. 상태 변형의 시장 열 = 종목 동일가중 평균(대용 · diag 에 표기)
rfc_pca_cov <- function(R, cfg, variant = "base") {
  R <- as.matrix(R)
  K <- rfc_bai_ng_k(R, cfg$bai_ng_kmax)
  Rc <- sweep(R, 2, colMeans(R))
  ev <- eigen(crossprod(Rc), symmetric = TRUE)
  V <- ev$vectors[, seq_len(K), drop = FALSE]
  Fp <- Rc %*% V; colnames(Fp) <- paste0("PC", seq_len(K))
  mk <- rowMeans(R)
  rows <- rfc_state_mask(mk, variant, cfg$dd_state_threshold)
  fb <- NA_character_
  if (sum(rows) < .rfc_min_obs(K, cfg)) { if (!identical(variant, "base")) fb <- sprintf("%s 표본 %d < %d → base", variant, sum(rows), .rfc_min_obs(K, cfg)); rows[] <- TRUE }
  fit <- rfc_ols_betas(R[rows, , drop = FALSE], Fp[rows, , drop = FALSE])
  Om <- .rfc_cov(Fp[rows, , drop = FALSE])
  S <- fit$B %*% Om %*% t(fit$B) + diag(fit$D, length(fit$D)); dimnames(S) <- list(colnames(R), colnames(R))
  g <- rfc_guard(S, cfg$kappa_max)
  list(Sigma = g$S, B = fit$B, Omega = Om, D = fit$D, K = K, model = "pca", variant = variant,
       diag = list(n_obs = sum(rows), market_proxy = "rowMeans(R)", fallback = fb,
                   kappa_before = g$kappa_before, kappa_after = g$kappa_after, clipped = g$clipped))
}

#' 특성 횡단면 모형. X = N×K 노출(행 = colnames(R) 순서 · as-of 스냅샷) · 절편(시장) 열을 더한다.
rfc_cs_cov <- function(R, X, cfg, variant = "base") {
  R <- as.matrix(R); X <- as.matrix(X)
  if (!identical(rownames(X), colnames(R))) {
    if (is.null(rownames(X)) || !all(colnames(R) %in% rownames(X))) stop("[rfc] 노출 X 행 이름이 종목과 맞지 않는다")
    X <- X[colnames(R), , drop = FALSE]
  }
  if (!all(is.finite(X))) stop("[rfc] 노출에 결측 — 로더가 missing='zero'(횡단면 중앙값)로 채워야 한다")
  X1 <- cbind(MKT = 1, X)
  qx <- qr(X1); if (qx$rank < ncol(X1)) stop("[rfc] 노출 행렬 계수 부족")
  Fc <- t(qr.coef(qx, t(R)))                        # T×(K+1) 일별 횡단면 OLS 요인 수익
  E <- R - Fc %*% t(X1)
  rows <- rfc_state_mask(Fc[, 1], variant, cfg$dd_state_threshold)
  K <- ncol(X1); fb <- NA_character_
  if (sum(rows) < .rfc_min_obs(K, cfg)) { if (!identical(variant, "base")) fb <- sprintf("%s 표본 %d < %d → base", variant, sum(rows), .rfc_min_obs(K, cfg)); rows[] <- TRUE }
  Om <- .rfc_cov(Fc[rows, , drop = FALSE])
  D <- apply(E[rows, , drop = FALSE], 2, stats::var)
  S <- X1 %*% Om %*% t(X1) + diag(D, length(D)); dimnames(S) <- list(colnames(R), colnames(R))
  g <- rfc_guard(S, cfg$kappa_max)
  list(Sigma = g$S, B = X1, Omega = Om, D = D, K = K, model = "cs", variant = variant,
       diag = list(n_obs = sum(rows), fallback = fb, kappa_before = g$kappa_before,
                   kappa_after = g$kappa_after, clipped = g$clipped))
}

#' 표본 공분산(+ 선택 수축) 기준판 — 대조용(셀 엔진 현행 = 수축 없음)
rfc_sample_cov <- function(R, cfg, shrink = FALSE) {
  S <- if (isTRUE(shrink)) rfc_lw2004(R)$S else .rfc_cov(R)
  list(Sigma = S, model = if (isTRUE(shrink)) "lw2004" else "sample", variant = "base")
}

#------------------------------------------------------------------------------
# 날짜가 있는 유일한 진입점 — PIT 컷은 여기서만 한다
#------------------------------------------------------------------------------
#' @param ret long data.table(Date, Ticker, Ret) · @param fac data.table(Date, <요인 열>) 또는 NULL(→ pca)
#' @param decision_date 결정(신호)일 — 두 입력 모두 Date < decision_date 만 쓴다
#' @param lookback 종목 창 길이(거래일 · 호출자 창 — 셀 엔진 기본 .wt$lookback_days 252 와 같게 넘긴다)
#' @param X 노출(cs 모형일 때 · as-of 스냅샷 · 로더 책임)
rfc_sigma_asof <- function(ret, fac = NULL, decision_date, assets, lookback, cfg,
                           model = c("ts", "pca", "cs"), variant = c("base", "downside", "dd_state"), X = NULL) {
  model <- match.arg(model); variant <- match.arg(variant)
  d <- as.Date(decision_date)
  ret <- as.data.table(ret)[Date < d & Ticker %in% assets]
  if (anyDuplicated(ret, by = c("Date", "Ticker"))) stop("[rfc] 수익 (Date, Ticker) 겹침 — dcast 기본 집계(length)가 값을 개수로 바꾼다")
  W <- dcast(ret, Date ~ Ticker, value.var = "Ret")
  setorder(W, Date)
  W <- utils::tail(W, as.integer(lookback))
  dates <- W$Date
  R <- as.matrix(W[, -1L, with = FALSE])
  keep <- colnames(R)[colSums(!is.finite(R)) == 0L]
  if (length(keep) < 2L) stop("[rfc] 창 안에 결측 없는 종목이 2개 미만")
  R <- R[, keep, drop = FALSE]
  out <- if (identical(model, "ts")) {
    if (is.null(fac)) stop("[rfc] ts 모형에 요인 수익이 없다")
    fh <- as.data.table(fac)[Date < d]
    setorder(fh, Date)
    cols <- intersect(cfg$factor_columns, names(fh))
    if (!length(cols)) stop("[rfc] 설정 요인 열이 요인 표에 없다")
    if (anyDuplicated(fh$Date)) stop("[rfc] 요인 표 날짜 겹침")
    nmiss <- sum(!dates %in% fh$Date)                 # 왼쪽 조인은 빠진 날을 NA 행으로 채운다 — 날짜 집합으로 직접 센다
    if (nmiss) stop(sprintf("[rfc] 요인 표가 종목 창 날짜를 덮지 못한다(%d/%d일 없음 · 요인 마지막 %s)", nmiss, length(dates),
                            if (nrow(fh)) format(max(fh$Date)) else "없음"))
    Fw <- fh[data.table(Date = dates), on = "Date"]
    rfc_ts_cov(R, as.matrix(Fw[, cols, with = FALSE]), cfg, variant = variant,
               F_hist = as.matrix(fh[, cols, with = FALSE]))
  } else if (identical(model, "pca")) rfc_pca_cov(R, cfg, variant = variant)
  else rfc_cs_cov(R, X, cfg, variant = variant)
  out$assets <- keep; out$window <- range(dates); out$decision_date <- d
  out$diag$max_used_date <- max(dates)
  if (out$diag$max_used_date >= d) stop("[rfc] PIT 단언 실패 — 창 종점이 결정일 이후")   # 구조상 도달 불가 · 계약 단언
  out
}

#------------------------------------------------------------------------------
# 운영 자료 로더(얇은 층 · 읽기 전용) — 합성 시험 범위 밖(실데이터 미확인)
#------------------------------------------------------------------------------
#' 요인 수익(일별) — build_kr_factor_returns.R 산출. Date < decision_date 만 반환.
rfc_load_factor_returns <- function(decision_date, root = .rfc_root(), cfg = rfc_config()) {
  p <- file.path(root, ".cache", cfg$factor_returns_file)
  if (!file.exists(p)) return(NULL)
  suppressMessages(library(arrow))
  F <- as.data.table(arrow::read_parquet(p, col_select = tidyselect::any_of(c("Date", cfg$factor_columns, cfg$factor_fallback$from))))
  F[, Date := as.Date(Date)]
  # 시장 열 대체(초기 무위험 수익 결측 구간): 설정이 선언한 대체만 — 값 지어내기 없음
  fbk <- cfg$factor_fallback
  if (!is.null(fbk) && fbk$to %in% names(F) && fbk$from %in% names(F))
    F[!is.finite(get(fbk$to)), (fbk$to) := get(fbk$from)]
  F[Date < as.Date(decision_date)]
}

#' 노출 스냅샷(cs 모형) — 팩터 DB 결합용 뷰 fc_load_month() 경유만(C15). 방향 = registry(Σ 는 부호 무관).
rfc_load_exposures <- function(sig_date, assets, root = .rfc_root(), cfg = rfc_config()) {
  if (!exists("fc_load_month", mode = "function"))
    source(file.path(root, "02_Infrastructure", "factor_db", "factor_combinable.R"))
  L <- fc_load_month(sig_date, direction = "registry", factors = cfg$cs_exposures, tickers = assets, missing = "zero")
  P <- as.data.table(L$panel)[Ticker %in% assets]
  X <- as.matrix(P[, intersect(cfg$cs_exposures, names(P)), with = FALSE]); rownames(X) <- P$Ticker
  X
}

#' ctx 공급자 등록(ctx_providers.R 의 register_ctx_provider 계약) — 호출자가 명시적으로 부른다(자동 등록 없음).
#'   ctx$factor_returns() = Date < decision_date 인 요인 수익 표. fixture_fn = 합성(게이트가 자료 판에 묶이지 않게).
rfc_register_ctx_provider <- function(root = .rfc_root()) {
  if (!exists("register_ctx_provider", mode = "function"))
    source(file.path(root, "02_Infrastructure", "methods", "ctx_providers.R"))
  cfg <- rfc_config(file.path(root, "02_Infrastructure", "reinforcement", "rf_factor_cov.json"))
  register_ctx_provider(
    name = "factor_returns", overwrite = TRUE,
    pit_note = "Date < decision_date(셀 엔진 C2 규약 · rf_cell_engine.R:513 과 같은 컷) · 요인 구성 = 빌더 계약(Factor_Date ≤ 구성일 · 다음 거래일 보유)",
    source_note = paste0(".cache/", cfg$factor_returns_file, " (build_kr_factor_returns.R 산출 · 읽기 전용 · 팩터 DB parquet 아님)"),
    fixture_fn = function(decision_date, assets) rfc_synth_factor_returns(as.Date(decision_date[1]), n = 300L),
    fn = function(decision_date, assets) rfc_load_factor_returns(min(as.Date(decision_date)), root = root, cfg = cfg))
}

#' 합성 요인 수익(게이트 · 시험용) — 결정일 직전까지 n 거래일
rfc_synth_factor_returns <- function(decision_date, n = 300L, seed = 20261110L, cols = c("MKT", "SMB", "HML", "RMW", "CMA", "WML")) {
  set.seed(seed)
  dd <- seq(as.Date(decision_date) - 1L - (n - 1L) * 1L, as.Date(decision_date) - 1L, by = "day")
  sd <- c(0.012, 0.006, 0.005, 0.004, 0.004, 0.008)[seq_along(cols)]
  M <- vapply(seq_along(cols), function(j) stats::rnorm(n, 0, sd[j]), numeric(n))
  out <- data.table(Date = dd); out[, (cols) := as.data.table(M)]
  out
}

#' ctx → Σ (시그마 어댑터 · 셀 엔진 패치 제안의 공급자 함수가 부른다). 관측 요인이 있으면 ts, 없으면 pca.
#'   ctx$R_dates(있으면) = R 행 날짜 · 없으면 요인 표 끝 nrow(R) 행으로 맞춘다(diag$align = "tail" — 같은 KRX 거래일력 가정 · 표기).
rfc_sigma_ctx <- function(ctx, cfg, variant = "base") {
  R <- as.matrix(ctx$R); a <- ctx$assets
  R <- R[, a, drop = FALSE]
  F <- if (is.function(ctx$factor_returns)) ctx$factor_returns() else NULL
  why <- if (is.null(F)) "요인 공급자 없음" else NA_character_
  if (!is.null(F) && nrow(F)) {
    F <- as.data.table(F)
    dd <- as.Date(ctx$decision_date)
    F <- F[Date < dd]; setorder(F, Date)
    cols <- intersect(cfg$factor_columns, names(F))
    stale <- NA_character_
    if (!is.null(ctx$R_dates)) {
      Fw <- F[data.table(Date = as.Date(ctx$R_dates)), on = "Date"]; al <- "dates"
      if (anyNA(Fw$Date) || anyNA(Fw[[cfg$market_column]])) stale <- "요인 표가 R 날짜를 덮지 못함"
    } else {
      Fw <- utils::tail(F, nrow(R)); al <- "tail"
      # ★날짜 없는 끝 맞춤은 요인 표가 낡으면 조용히 어긋난다 — 마지막 요인일이 결정일에서 너무 멀면 쓰지 않는다
      gap <- if (nrow(F)) as.numeric(dd - max(F$Date)) else Inf
      if (!is.finite(gap) || gap > cfg$max_factor_staleness_days)
        stale <- sprintf("요인 표 낡음(마지막 %s · 결정일과 %s일 > %d)", if (nrow(F)) format(max(F$Date)) else "없음", gap, cfg$max_factor_staleness_days)
    }
    if (is.na(stale) && nrow(Fw) == nrow(R) && length(cols)) {
      Fm <- as.matrix(Fw[, cols, with = FALSE])
      if (sum(colSums(is.finite(Fm)) == nrow(Fm)) >= 1L) {
        o <- rfc_ts_cov(R, Fm, cfg, variant = variant, F_hist = as.matrix(F[, cols, with = FALSE]))
        o$diag$align <- al
        return(o)
      }
    }
    why <- if (!is.na(stale)) stale else "요인 열 · 행 부족"
  }
  o <- rfc_pca_cov(R, cfg, variant = variant); o$diag$align <- "none(pca)"
  o$diag$fallback <- paste(c(why, if (!is.na(o$diag$fallback)) o$diag$fallback), collapse = " · ")
  o
}
