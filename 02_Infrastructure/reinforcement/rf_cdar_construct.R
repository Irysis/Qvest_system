#==============================================================================
# rf_cdar_construct.R — 낙폭 목적 구성(CDaR 선형계획 · 희소 입력 · 후보 선별 → 풀이 → 25종 가지치기)   (2026-11-10 · 레인 E3 신설)
#
# 원문: Chekhlov, Uryasev & Zabarankin (2005) 'Drawdown Measure in Portfolio Optimization', IJTAF 8(1):13-58
#   https://doi.org/10.1142/S0219024905002767 . 누적 수익(비복리) y_t(w) = Σ_{s≤t} r_sᵀw · 낙폭 D_t = max_{0≤s≤t} y_s − y_t (y_0 = 0)
#   CDaR_α(w) = min_ζ { ζ + 1/((1−α)T) Σ_t (D_t − ζ)⁺ }  — Rockafellar & Uryasev (2000) J. Risk 2(3):21-41 의 CVaR 정식을 낙폭 표본에.
#   선형화(원문 §3): 보조 변수 u_t(= 경로 고점) · z_t(초과 낙폭):
#     u_t ≥ C_tᵀw · u_t ≥ u_{t−1} · u_0 = 0 · z_t ≥ u_t − C_tᵀw − ζ · z_t ≥ 0       (C_t = Σ_{s≤t} r_s)
#   원문 문제 = 기대수익 최대화 s.t. CDaR ≤ ν·자본 · 예산 제약. 최소 CDaR 끝점은 그 문제의 한 끝.
#
# 두 방식(mode)
#   min_cdar        — min CDaR s.t. Σw = 1 (현행 qepm:CDaR_LP = advanced_weights.R::calc_cdar_weights 와 같은 문제 — 등가 대조용).
#   max_mu_cdar_cap — max μᵀw s.t. CDaR(w) ≤ ν · Σw = 1 또는 Σw ≤ 1(잔여 현금). μ = 엔진 점수(척도 무관 — LP 해는 μ 의 양의 배수에 불변).
#                     ν 규칙(nu_rule): ew_candidates = κ × CDaR(같은 후보 동일가중) — 기준판(EW)보다 낙폭 경로를 나쁘게 하지 않는다(κ = 1).
#                     Σw = 1 이면 EW 가 항상 가능해라 해가 존재한다. Σw ≤ 1 이면 CDaR 이 양의 1차 동차라 κ < 1 도 늘 가능(현금으로 채운다).
#
# 풀 수 있는 크기로(09-06/07 시간 초과의 원인 = cccp 밀집 IPM ~T³ · T 252 에서 월 27~36 s × 260 리밸 — advanced_weights.R:1105-1110)
#   ① lpSolve 단체법 + **희소 삼중항 입력**(dense.const) — 제약 행렬 비영 원소 ≈ 2Tn + 5T(밀집 판은 (6T+2p) × (p+3T) 전부를 만든다).
#   ② 후보 선별(pool) → 풀이 → 비영 비중 > max_names 면 상위 max_names 로 줄여 다시 푼다(LP 꼭짓점 해는 대개 이미 희소하다).
#   ③ 월 1회 호출(셀 엔진 신호일마다 1회 — 호출 빈도는 엔진이 정한다). 따뜻한 시작: lpSolve R 인터페이스는 기저 재사용을 노출하지 않는다
#      (lpSolveAPI 미설치) → 쓰지 않는다. 실측 소요 시간은 시험이 잰다.
#   ④ 회전 인지 항(선택 · 기본 끔): λ Σ|w − w_prev| (보조 변수 s_i ≥ ±(w_i − w_prev_i)). 15bps 비용은 측정 계약이 붙인다 — 여기서 이중 과금하지 않는다.
#
# PIT: 시나리오 = 받은 수익 행렬 R(호출자가 Date < 결정일로 자른 창 — 셀 엔진 rf_cell_engine.R:513). 날짜가 있는 진입점 rcd_construct_asof() 는
#   스스로 Date < decision_date 로 자른다. 시장 경로(bench)도 같은 컷.
# 수치는 rf_cdar_construct.json(모듈 옆 설정 초안 · 근거 문구 포함).
#==============================================================================

suppressWarnings(suppressMessages({ library(data.table); library(jsonlite) }))
`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a

.RCD_MARKER <- file.path("02_Infrastructure", "reinforcement", "rf_cdar_construct.R")
.rcd_root <- function() {
  for (k in c("QM_ROOT", "CLAUDE_PROJECT_DIR")) {
    v <- gsub("\\\\", "/", Sys.getenv(k, ""))
    if (nzchar(v) && file.exists(file.path(v, .RCD_MARKER))) return(v)
  }
  d <- getwd()
  for (i in 1:6) { if (file.exists(file.path(d, .RCD_MARKER))) return(d); d <- dirname(d) }
  stop("[rcd] 저장소 루트를 찾지 못했다")
}

rcd_config <- function(path = NULL) {
  p <- path %||% file.path(.rcd_root(), "02_Infrastructure", "reinforcement", "rf_cdar_construct.json")
  cfg <- fromJSON(p, simplifyVector = TRUE)
  need <- c("alpha", "max_names", "pool_size", "nu_rule", "nu_kappa", "weight_tol", "tc_lambda", "adapter_mode", "max_prune_rounds")
  miss <- setdiff(need, names(cfg)); if (length(miss)) stop("[rcd] 설정 키 결손: ", paste(miss, collapse = ", "))
  cfg
}

#------------------------------------------------------------------------------
# 평가기 — LP 와 독립인 정확 계산(검사가 LP 목적값을 재도출할 때 쓴다)
#------------------------------------------------------------------------------
#' 비복리 낙폭(CUZ 정의 · y_0 = 0 포함 고점)
rcd_drawdowns <- function(rp) { y <- cumsum(as.numeric(rp)); pk <- cummax(pmax(y, 0)); pk - y }

#' CDaR_α (RU 정식의 정확 최소화 — 볼록 조각선형이라 최소는 꺾임점 ζ ∈ {D_t} 또는 0 에 있다)
rcd_cdar <- function(rp, alpha) {
  D <- rcd_drawdowns(rp); Tn <- length(D)
  cand <- sort(unique(c(0, D)))
  f <- vapply(cand, function(z) z + sum(pmax(D - z, 0)) / ((1 - alpha) * Tn), numeric(1))
  min(f)
}

#' 행동 카드 판(복리 NAV · 상위 ceil((1−α)T) 평균 — behavior_card.R:220 .bc_cdar 과 같은 식) — 정보용(LP 는 비복리를 최적화한다)
rcd_cdar_card <- function(rp, alpha) {
  nav <- cumprod(1 + as.numeric(rp)); dd <- 1 - nav / cummax(nav)
  k <- max(1L, as.integer(ceiling((1 - alpha) * length(dd))))
  mean(sort(dd, decreasing = TRUE)[seq_len(k)])
}

#------------------------------------------------------------------------------
# LP (희소 삼중항)
#------------------------------------------------------------------------------
#' @return list(sol, layout) — sol = lpSolve::lp 결과
rcd_lp <- function(R, alpha, mode = c("min_cdar", "max_mu_cdar_cap"), mu = NULL, nu = NULL,
                   budget = c("eq", "le"), w_prev = NULL, tc_lambda = 0, ub = 1, ret_floor = NULL) {
  mode <- match.arg(mode); budget <- match.arg(budget)
  R <- as.matrix(R); Tn <- nrow(R); n <- ncol(R)
  if (Tn < 2L || n < 1L) stop("[rcd] 시나리오 2개 · 자산 1개 이상 필요")
  if (identical(mode, "min_cdar") && identical(budget, "le") && is.null(ret_floor))
    stop("[rcd] min_cdar + Σw ≤ 1 은 w = 0 으로 퇴화한다 — eq 를 쓰거나 ret_floor 를 준다")
  if (identical(mode, "max_mu_cdar_cap") && (is.null(mu) || is.null(nu))) stop("[rcd] max_mu_cdar_cap 은 mu · nu 필요")
  use_tc <- is.finite(tc_lambda) && tc_lambda > 0 && !is.null(w_prev)
  iw <- seq_len(n); iu <- n + seq_len(Tn); iz <- n + Tn + seq_len(Tn); izeta <- n + 2L * Tn + 1L
  is_ <- if (use_tc) izeta + seq_len(n) else integer(0)
  nv <- izeta + length(is_)
  Cm <- apply(R, 2, cumsum); if (!is.matrix(Cm)) Cm <- matrix(Cm, nrow = Tn)
  cz <- 1 / ((1 - alpha) * Tn)
  # 블록 삼중항(행 · 열 · 값)을 한꺼번에 만든다(행 루프 대신 벡터화)
  blk <- function(ri, cj, v) cbind(ri, cj, v)
  tt <- seq_len(Tn)
  # (1) u_t − C_tᵀw ≥ 0
  b1 <- rbind(blk(tt, iu[tt], 1), blk(rep(tt, n), rep(iw, each = Tn), -as.numeric(Cm)))
  # (2) u_t − u_{t−1} ≥ 0 (t ≥ 2)
  t2 <- if (Tn >= 2L) 2:Tn else integer(0)
  b2 <- rbind(blk(Tn + seq_along(t2), iu[t2], 1), blk(Tn + seq_along(t2), iu[t2 - 1L], -1))
  # (3) z_t − u_t + C_tᵀw + ζ ≥ 0
  o3 <- Tn + length(t2)
  b3 <- rbind(blk(o3 + tt, iz[tt], 1), blk(o3 + tt, iu[tt], -1), blk(o3 + tt, izeta, 1),
              blk(rep(o3 + tt, n), rep(iw, each = Tn), as.numeric(Cm)))
  M <- rbind(b1, b2, b3)
  dir <- rep(">=", o3 + Tn); rhs <- rep(0, o3 + Tn); nr <- o3 + Tn
  more <- function(cols, vals, d, b) { nr <<- nr + 1L; M <<- rbind(M, cbind(nr, cols, vals)); dir <<- c(dir, d); rhs <<- c(rhs, b) }
  more(iw, rep(1, n), if (identical(budget, "eq")) "=" else "<=", 1)
  if (identical(mode, "max_mu_cdar_cap")) more(c(izeta, iz), c(1, rep(cz, Tn)), "<=", nu)
  if (!is.null(ret_floor)) more(iw, as.numeric(mu), ">=", ret_floor)
  if (is.finite(ub) && ub < 1) for (i in iw) more(i, 1, "<=", ub)
  if (use_tc) for (i in seq_len(n)) {
    more(c(is_[i], iw[i]), c(1, -1), ">=", -w_prev[i])
    more(c(is_[i], iw[i]), c(1, 1), ">=", w_prev[i])
  }
  obj <- numeric(nv)
  if (identical(mode, "min_cdar")) {
    obj[izeta] <- 1; obj[iz] <- cz; if (use_tc) obj[is_] <- tc_lambda
    dirn <- "min"
  } else {
    obj[iw] <- as.numeric(mu); if (use_tc) obj[is_] <- -tc_lambda
    dirn <- "max"
  }
  M <- M[M[, 3] != 0, , drop = FALSE]
  sol <- lpSolve::lp(dirn, obj, const.dir = dir, const.rhs = rhs, dense.const = M)
  list(sol = sol, iw = iw, izeta = izeta, iz = iz, cz = cz, nnz = nrow(M), nrows = nr, nvars = nv)
}

#' 한 번 풀이 → 비중 · CDaR · 상태
rcd_solve <- function(R, cfg, mode = "min_cdar", mu = NULL, nu = NULL, budget = "eq", w_prev = NULL, tc_lambda = NULL, ub = 1) {
  t0 <- proc.time()[["elapsed"]]
  L <- rcd_lp(R, cfg$alpha, mode = mode, mu = mu, nu = nu, budget = budget, w_prev = w_prev,
              tc_lambda = tc_lambda %||% cfg$tc_lambda, ub = ub)
  st <- as.integer(L$sol$status)
  if (!identical(st, 0L)) return(list(ok = FALSE, status = st, sec = proc.time()[["elapsed"]] - t0, nnz = L$nnz))
  x <- L$sol$solution
  w <- pmax(x[L$iw], 0); w[w < cfg$weight_tol] <- 0; names(w) <- colnames(R)
  lp_cdar <- x[L$izeta] + L$cz * sum(x[L$iz])
  list(ok = TRUE, status = st, w = w, cash = max(0, 1 - sum(w)), lp_cdar = lp_cdar,
       cdar = rcd_cdar(as.matrix(R) %*% w, cfg$alpha), objective = L$sol$objval,
       sec = proc.time()[["elapsed"]] - t0, nnz = L$nnz, nrows = L$nrows, nvars = L$nvars)
}

#' 구성 = 후보 선별 → 풀이 → 25종 가지치기 → (필요 시) 재풀이. 반환 비중은 R 의 전 열(제외 = 0).
rcd_construct <- function(R, cfg, mu = NULL, mode = NULL, budget = "eq", nu = NULL, w_prev = NULL, bench = NULL, nu_rule = NULL) {
  R <- as.matrix(R); a <- colnames(R)
  if (!is.null(nu_rule)) cfg$nu_rule <- rcd_nu_rule(nu_rule)   # 칸 선택지(기본 = 설정값 · 비트 동일)
  mode <- mode %||% (if (is.null(mu)) "min_cdar" else cfg$adapter_mode)
  if (!is.null(mu)) mu <- stats::setNames(as.numeric(mu[a]), a)
  cand <- a
  if (!is.null(mu) && length(a) > cfg$pool_size) {
    o <- order(-mu, a); cand <- a[o][seq_len(cfg$pool_size)]
  }
  # ν: 같은 후보의 동일가중 CDaR × κ (또는 시장 경로 × κ · 또는 호출자 값)
  if (identical(mode, "max_mu_cdar_cap") && is.null(nu)) {
    nu <- switch(cfg$nu_rule,
      ew_candidates = cfg$nu_kappa * rcd_cdar(rowMeans(R[, cand, drop = FALSE]), cfg$alpha),
      bench = { if (is.null(bench)) stop("[rcd] nu_rule=bench 인데 시장 경로가 없다"); cfg$nu_kappa * rcd_cdar(bench, cfg$alpha) },
      stop("[rcd] 미지 nu_rule: ", cfg$nu_rule))
  }
  wp <- if (is.null(w_prev)) NULL else { v <- as.numeric(w_prev[cand]); v[!is.finite(v)] <- 0; v }
  fb <- NA_character_; rounds <- 0L; secs <- 0
  repeat {
    s <- rcd_solve(R[, cand, drop = FALSE], cfg, mode = mode, mu = if (is.null(mu)) NULL else mu[cand],
                   nu = nu, budget = budget, w_prev = wp)
    secs <- secs + s$sec; rounds <- rounds + 1L
    if (!isTRUE(s$ok)) {
      if (identical(mode, "max_mu_cdar_cap")) {        # 실행 불가(가지친 집합에서 ν 를 못 맞춤) → 같은 집합 최소 CDaR 로 복원 · 표기
        fb <- sprintf("max_mu 실행 불가(status %d) → min_cdar 복원", s$status)
        s <- rcd_solve(R[, cand, drop = FALSE], cfg, mode = "min_cdar", budget = "eq", w_prev = wp)
        secs <- secs + s$sec
        if (!isTRUE(s$ok)) stop("[rcd] min_cdar 도 실패(status ", s$status, ")")
      } else stop("[rcd] LP 실패(status ", s$status, ")")
    }
    act <- names(s$w)[s$w > 0]
    if (length(act) <= cfg$max_names || rounds > cfg$max_prune_rounds) break
    keep <- names(sort(s$w, decreasing = TRUE))[seq_len(cfg$max_names)]
    cand <- keep; if (!is.null(wp)) wp <- as.numeric(w_prev[cand]) %||% NULL
  }
  w <- stats::setNames(numeric(length(a)), a); w[names(s$w)] <- s$w
  if (sum(w > 0) > cfg$max_names) stop("[rcd] 가지치기 후에도 비영 비중 > max_names")
  list(w = w, cash = max(0, 1 - sum(w)), cdar = s$cdar, lp_cdar = s$lp_cdar, nu = nu, mode = mode,
       budget = budget, n_active = sum(w > 0), effn = if (sum(w) > 0) sum(w)^2 / sum(w^2) else 0,
       rounds = rounds, sec = secs, fallback = fb, nnz = s$nnz)
}

#' ν 규칙 어휘 — "ew"(= "ew_candidates" · 기본) | "bench"(같은 창 벤치 CDaR × κ). 그 밖은 멈춘다.
rcd_nu_rule <- function(x) {
  x <- as.character(x)[1]
  if (identical(x, "ew")) return("ew_candidates")
  if (!x %in% c("ew_candidates", "bench")) stop("[rcd] nu_rule 어휘 밖: ", x, " (ew | bench)")
  x
}

#' 벤치 낙폭 예산용 정렬(2026-11-10 · nu_rule = bench) — 후보 수익 창(R · R_dates)과 벤치 일별 수익(Date, r)을 날짜 교집합으로 맞춘다.
#'   PIT: 벤치는 Date < decision_date 만(넘겨받은 표에 그 뒤 행이 있어도 여기서 자른다). 시나리오도 교집합 날짜로 줄인다
#'   (ν 와 후보 CDaR 이 같은 날짜 위에서 재여야 비교가 성립한다).
#'   최소 관측 = ceiling(1 / (1 − α)) — CDaR_α 꼬리에 표본이 하나 이상 들어가는 최소 크기(설정 alpha 에서 유도 · 새 숫자 아님). 미달이면 멈춘다.
rcd_bench_align <- function(R, R_dates, bench, decision_date, alpha) {
  if (is.null(bench) || !NROW(bench)) stop("[rcd] nu_rule = bench 인데 벤치 수익이 없다(ew 로 조용히 내려가지 않는다)")
  if (is.null(R_dates) || length(R_dates) != nrow(R)) stop("[rcd] nu_rule = bench 는 R 행 날짜(R_dates)가 필요하다")
  B <- as.data.table(bench)
  if (!all(c("Date", "r") %in% names(B))) stop("[rcd] 벤치 표는 (Date, r) 열")
  B <- B[as.Date(Date) < as.Date(decision_date) & is.finite(r), .(Date = as.Date(Date), r = as.numeric(r))]
  if (anyDuplicated(B$Date)) stop("[rcd] 벤치 날짜 겹침")
  rd <- as.Date(R_dates)
  keep <- rd %in% B$Date & rd < as.Date(decision_date)
  n_min <- as.integer(ceiling(1 / (1 - alpha)))
  if (sum(keep) < n_min) stop(sprintf("[rcd] 벤치 · 후보 창 교집합 %d일 < 최소 %d(= ceiling(1/(1−α)))", sum(keep), n_min))
  list(R = R[keep, , drop = FALSE], b = B$r[match(rd[keep], B$Date)], n = sum(keep), dropped = sum(!keep))
}

#' 날짜가 있는 진입점 — Date < decision_date 로 자른 뒤 창 lookback 행만 시나리오로 쓴다.
#' @param ret long data.table(Date, Ticker, Ret) · @param bench data.table(Date, r) 또는 NULL
rcd_construct_asof <- function(ret, decision_date, assets, lookback, cfg, mu = NULL, bench = NULL, ...) {
  d <- as.Date(decision_date)
  X <- as.data.table(ret)[Date < d & Ticker %in% assets]
  if (anyDuplicated(X, by = c("Date", "Ticker"))) stop("[rcd] 수익 (Date, Ticker) 겹침 — dcast 기본 집계(length)가 값을 개수로 바꾼다")
  W <- dcast(X, Date ~ Ticker, value.var = "Ret"); setorder(W, Date)
  W <- utils::tail(W, as.integer(lookback))
  R <- as.matrix(W[, -1L, with = FALSE]); keep <- colnames(R)[colSums(!is.finite(R)) == 0L]
  R <- R[, keep, drop = FALSE]
  bp <- if (is.null(bench)) NULL else { B <- as.data.table(bench)[Date < d]; B[data.table(Date = W$Date), on = "Date"]$r }
  if (!is.null(bp) && anyNA(bp)) stop("[rcd] 시장 경로가 창 날짜를 덮지 못한다")
  o <- rcd_construct(R, cfg, mu = if (is.null(mu)) NULL else mu[keep], bench = bp, ...)
  o$window <- range(W$Date); o$max_used_date <- max(W$Date)
  if (o$max_used_date >= d) stop("[rcd] PIT 단언 실패 — 시나리오 종점이 결정일 이후")
  o
}
