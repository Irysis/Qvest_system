#==============================================================================
# strategy_role.R — 전략 역할 등급 계약 (규칙 기반 · v1 · 2026-10-06 도훈 결정)
#
# 왜: 1계층의 목표 = 2계층을 위한 **다양한** 전략풀 확보. 단일 잣대(essence)는 같은 형태(β≈0.8 롱온리 다요인)만 쌓는다.
#   역할마다 그 역할을 수행한다는 **측정 증거**로 등급을 매긴다. 단독 A(essence → Judge → BOOK) 경로는 불변 — 이 등급은 2계층 풀 편입용.
# 원칙:
#   - 역할 = 측정된 수익 행동(국면 = 실현 벤치 KOSPI200 정본). 라벨·서술·LLM 판정 금지(충실구현 레인의 declared_role 은 대조용 기록).
#   - 국면 통계는 **전기간 베타 하나**로 만든 잔차 e = r − β·b(α 포함)의 국면 내 평균 t. 하락월 초과(r−b)는 β<1 이면 기전 없이 양수다
#     (재생 2026-10-06: 베타 맞춤 잡음 61% 가 구 방어형 B+). 국면별 베타 분리 추정은 절편 왜곡 — 서술용으로만.
#   - PIT: 전기간 판정(essence 와 같은 성격). 2계층이 역할 소속을 배합 선택에 쓸 때는 as-of 로 다시 잰다(pit.md C1 D-E).
#     ps_bear·lt_bear 는 사후 연대기(전환점 판정에 미래 창) — 등급 산정 전용, 2계층 as-of 소비 금지. cgh36 은 월초 기지.
# 정본 수치·근거 = 06_Registry/strategy_role.json · 설계·재생 = 04_Research/01_reports/strategy_role_grading_20261006/
# 공개: sr_cfg · sr_regimes · sr_card · sr_add_diversifier · sr_card_for_series · sr_registry_load · sr_registry_upsert
# 요구: data.table · jsonlite · bbdetection(CRAN) · 02_Infrastructure/reinforcement/rf_diversification_gate.R(계열 판독·2요인)
# 검사: 08_Tests/contracts/test_strategy_role.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.sr_root <- function(root = NULL) {
  for (p in c(root, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    if (is.null(p) || !nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (dir.exists(file.path(p, "02_Infrastructure"))) return(p)
  }
  stop("[strategy_role] 프로젝트 루트 해석 실패")
}
.sr_env <- new.env(parent = globalenv())
local(sys.source(file.path(.sr_root(), "02_Infrastructure/reinforcement/rf_diversification_gate.R"), envir = .sr_env))

sr_cfg <- function(root = NULL) {
  p <- file.path(.sr_root(root), "06_Registry/strategy_role.json")
  cfg <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(cfg)) stop("[strategy_role] 설정 판독 불가: ", p)
  cfg
}

.sr_t <- function(x) { x <- x[is.finite(x)]; n <- length(x); if (n < 3L) return(NA_real_); s <- stats::sd(x); if (!is.finite(s) || s == 0) NA_real_ else mean(x) / (s / sqrt(n)) }

.sr_nw_alpha <- function(y, X, L) {
  ok <- is.finite(y) & apply(X, 1, function(r) all(is.finite(r)))
  y <- y[ok]; X <- cbind(1, X[ok, , drop = FALSE]); n <- length(y)
  if (n < ncol(X) + 5L) return(c(alpha = NA_real_, t = NA_real_))
  f <- tryCatch(stats::lm.fit(X, y), error = function(e) NULL); if (is.null(f)) return(c(alpha = NA_real_, t = NA_real_))
  XtXi <- tryCatch(solve(crossprod(X)), error = function(e) NULL); if (is.null(XtXi)) return(c(alpha = NA_real_, t = NA_real_))
  Xu <- X * f$residuals; S <- crossprod(Xu)
  for (l in seq_len(min(L, n - 1L))) { w <- 1 - l / (L + 1); G <- crossprod(Xu[(l + 1):n, , drop = FALSE], Xu[1:(n - l), , drop = FALSE]); S <- S + w * (G + t(G)) }
  V <- XtXi %*% S %*% XtXi
  c(alpha = unname(f$coefficients[1]), t = unname(f$coefficients[1] / sqrt(V[1, 1])))
}

.sr_oos <- function(v, splits) {
  v <- v[is.finite(v)]; n <- length(v); if (n < 24L) return(NA_integer_)
  sum(vapply(splits, function(s) { k <- floor(n * s); k < n && mean(v[(k + 1):n]) > 0 }, logical(1)))
}

.sr_grade <- function(t, oos, G) {
  if (!is.finite(t)) return("F")
  per <- is.finite(oos) && oos >= as.integer(G$oos_min_splits)
  if (t >= as.numeric(G$t_A) && per) return("A")
  if (t >= as.numeric(G$t_B) && per) return("B")
  if (t > 0) return("C")
  "F"
}

#' 국면 3종(월) — ps_bear · lt_bear(사후 연대기) · cgh36(월초 기지)
sr_regimes <- function(bm_daily) {
  if (!requireNamespace("bbdetection", quietly = TRUE)) stop("[strategy_role] bbdetection 미설치 — install.packages('bbdetection')")
  x <- bm_daily[order(date)][, .(date, bm)]
  x[, nav := cumprod(1 + bm)]
  me <- x[, .(nav = nav[.N]), by = .(ym = format(date, "%Y-%m"))][order(ym)]
  bbdetection::setpar_dating_alg(); me[, ps_bear := !bbdetection::run_dating_alg(nav)]
  bbdetection::setpar_filtering_alg(); me[, lt_bear := !bbdetection::run_filtering_alg(nav)]
  me[, cgh36 := data.table::shift(nav / data.table::shift(nav, 36L) - 1) < 0]
  me[, .(ym, ps_bear, lt_bear, cgh36)]
}

#' 역할 카드
#' @param m data.table(ym, r, b, ew) 월간 — r 전략 순수익 · b 정본 벤치 · ew 유니버스 동일가중(없으면 NA)
#' @param R sr_regimes() · @param cfg sr_cfg()
sr_card <- function(m, R, cfg) {
  G <- cfg$grading; L <- as.integer(G$nw_lag %||% 3L); sp <- unlist(G$oos_splits)
  m <- merge(m[is.finite(r) & is.finite(b)], R, by = "ym")[order(ym)]
  out <- list(status = "ok", n_months = nrow(m), first_ym = if (nrow(m)) m$ym[1] else NA_character_, last_ym = if (nrow(m)) m$ym[nrow(m)] else NA_character_)
  if (nrow(m) < as.integer(G$min_months)) { out$status <- "too_short"; return(out) }
  vb <- stats::var(m$b); beta <- if (vb > 0) stats::cov(m$r, m$b) / vb else NA_real_
  out$beta <- beta
  up <- m$b >= 0; out$up_capture <- mean(m$r[up]) / mean(m$b[up]); out$down_capture <- mean(m$r[!up]) / mean(m$b[!up])
  e <- m$r - beta * m$b                                  # 전기간 베타 잔차(α 포함)
  role_stat <- function(D) { D[is.na(D)] <- FALSE; list(n = sum(D), mean = mean(e[D]), t = .sr_t(e[D]), oos = .sr_oos(e[D], sp), stable = { v <- e[D]; h <- floor(length(v) / 2); if (length(v) >= 12L) mean(v[1:h]) > 0 && mean(v[(h + 1):length(v)]) > 0 else NA }) }
  roles <- list()
  d <- role_stat(m$ps_bear);  roles$defensive <- c(d, grade = .sr_grade(d$t, d$oos, G))
  o <- role_stat(!m$ps_bear); roles$offensive <- c(o, grade = .sr_grade(o$t, o$oos, G))
  rb <- role_stat(m$cgh36);   roles$rebound <- c(rb, grade = .sr_grade(rb$t, rb$oos, G))
  lt <- role_stat(m$lt_bear); out$defensive_lt_t <- lt$t; out$defensive_lt_n <- lt$n
  # 2요인 잔차 α (유니버스 동일가중이 있는 달만)
  ok <- is.finite(m$ew)
  if (sum(ok) >= as.integer(G$min_months)) {
    a <- .sr_nw_alpha(m$r[ok], cbind(m$b[ok], m$ew[ok] - m$b[ok]), L); basis <- "2f"
    f <- stats::lm.fit(cbind(1, m$b[ok], m$ew[ok] - m$b[ok]), m$r[ok]); ea <- f$residuals + f$coefficients[1]
  } else {
    a <- .sr_nw_alpha(m$r, cbind(m$b), L); basis <- "1f"
    f <- stats::lm.fit(cbind(1, m$b), m$r); ea <- f$residuals + f$coefficients[1]
  }
  both <- is.finite(d$mean) && is.finite(o$mean) && d$mean >= 0 && o$mean >= 0
  ag <- if (both) .sr_grade(a[["t"]], .sr_oos(ea, sp), G) else if (is.finite(a[["t"]]) && a[["t"]] > 0) "C" else "F"
  roles$alpha <- list(n = length(ea), mean = a[["alpha"]], t = a[["t"]], basis = basis, both_regimes_nonneg = both, grade = ag)
  out$roles <- roles
  .sr_primary(out)
}

.sr_primary <- function(out) {
  gs <- vapply(out$roles, function(z) as.character(z$grade), "")
  ts <- vapply(out$roles, function(z) { v <- suppressWarnings(as.numeric(z$t)); if (length(v) && is.finite(v)) v else -Inf }, 0)
  o <- order(match(gs, c("A", "B", "C", "F")), -ts)
  out$primary_role <- names(gs)[o[1]]; out$primary_grade <- gs[[o[1]]]
  out$roles_bplus <- names(gs)[gs %in% c("A", "B")]
  out
}

#' diversifier 역할 추가 — 기존 essence B+ 풀 대비(관련 계보 제외) 생성 회귀 α t(2요인 잔차)
sr_add_diversifier <- function(card, cand_monthly, key, pool, mats, cfg, div_cfg) {
  if (!identical(card$status, "ok")) return(card)
  me <- .sr_env$rfd_metrics(cand_monthly, key, pool, mats, div_cfg, measure = "resid2")
  G <- cfg$grading; t <- me$alpha_span_t
  g <- if (!is.finite(t) || t <= 0) "F" else if (t >= as.numeric(G$t_A)) "A" else if (t >= as.numeric(G$t_B)) "B" else "C"
  card$roles$diversifier <- list(t = t, rho_max = me$rho_max, neighbor = me$neighbor_lineage, r2_span = me$r2_span, status = me$status, grade = g)
  .sr_primary(card)
}

#' 산출물 계열(03_period_returns.csv · sim_result.rds) 하나 → 역할 카드(diversifier 제외)
sr_card_for_series <- function(series_path, root = NULL, cfg = NULL, bm = NULL, fac = NULL, R = NULL) {
  root <- .sr_root(root); cfg <- cfg %||% sr_cfg(root)
  dcfg <- .sr_env$rfd_cfg(root)
  bm <- bm %||% .sr_env$rfd_bench_daily(root, dcfg); fac <- fac %||% .sr_env$rfd_factor_monthly(root, dcfg); R <- R %||% sr_regimes(bm)
  mm <- .sr_env$rfd_monthly(.sr_env$rfd_read_series(series_path), bm, fac)
  if (is.null(mm)) return(list(status = "series_unreadable"))
  bmm <- bm[, .(b = prod(1 + bm) - 1), by = .(ym = format(date, "%Y-%m"))]
  m <- merge(merge(mm[, .(ym, r)], bmm, by = "ym"), fac, by = "ym", all.x = TRUE)
  sr_card(m, R, cfg)
}

# --- 레지스트리(06_Registry/strategy_roles.json) — 쓰기는 이 함수만 ---------------------------------
sr_registry_path <- function(root = NULL) file.path(.sr_root(root), "06_Registry/strategy_roles.json")
sr_registry_load <- function(root = NULL) {
  p <- sr_registry_path(root)
  if (!file.exists(p)) return(list(schema_version = "strategy_roles_v1", entries = list()))
  fromJSON(p, simplifyVector = FALSE)
}
#' @param items named list: id → list(card=, meta=) · 원자적 쓰기(임시 파일 → rename)
sr_registry_upsert <- function(items, root = NULL, source = "") {
  reg <- sr_registry_load(root)
  for (id in names(items)) reg$entries[[id]] <- c(items[[id]]$meta, list(card = items[[id]]$card, classified_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), source = source))
  reg$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"); reg$n_entries <- length(reg$entries)
  reg$config <- "06_Registry/strategy_role.json"
  p <- sr_registry_path(root); tmp <- paste0(p, ".tmp_", Sys.getpid())
  writeLines(toJSON(reg, auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null", null = "null"), tmp, useBytes = TRUE)
  if (!file.rename(tmp, p)) { file.copy(tmp, p, overwrite = TRUE); unlink(tmp) }
  invisible(reg$n_entries)
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
