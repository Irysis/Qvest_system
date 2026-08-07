#!/usr/bin/env Rscript
# method_registry.R — 논문 유래 *가중/위험 method* 어댑터 레지스트리 (도훈 지시 2026-08-08, (b)안).
#
# 왜 있나: paper_router 가 optimizer/risk 로 분류한 논문이 **제목만 기록되고 끝나던** 문제.
#   Σ-가중 A/B 배터리(auto_sigma_weighting_ab.R)는 기계로서는 정확한 형태였는데
#   method 집합 `W_all` 이 2026-06-18 에 하드코딩된 상수라 새 논문이 **낄 자리가 없었다**.
#   → method 집합을 상수에서 **인자**로 바꾸는 것이 (b)안의 전부다.
#
# ★핵심 안전 성질: 어댑터는 "선호 벡터"만 낸다. **제약은 하네스가 건다.**
#   long-only / Σw=1 / w≤UB 는 wrap_adapter() 가 pmax(0)+normalize_long_only 로 *강제*하므로,
#   논문 method 가 아무리 이상해도 Production Constraints 를 깰 수 없다(AX-000 따름정리 — 제약은 고정 축).
#   어댑터가 부호를 반대로 내든 발산하든 결과는 항상 유효 비중이다.
#
# ★선별은 건드리지 않는다: 캐리어(현 PG2)가 종목을 고정하고 method 는 비중만 정한다.
#   그래야 성과 차이가 **가중 규칙 때문**이라고 말할 수 있다(A/B 통제).
#
# 자본 admit 없음 — 본 레지스트리는 *측정 대상*을 늘릴 뿐 채택 권한이 없다(governor 정지).

suppressWarnings(suppressMessages({ library(jsonlite) }))

# ── 프로젝트 루트: CLAUDE_PROJECT_DIR 우선 + **marker 로 정체 검사** (r-portability 금칙 ③④) ──
.mr_root <- function() {
  .marker <- file.path("02_Infrastructure", "methods", "method_registry.R")
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) {
    d <- dirname(normalizePath(f[1], winslash = "/", mustWork = FALSE))
    r <- normalizePath(file.path(d, "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(r, .marker))) return(r)
  }
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && file.exists(file.path(v, .marker))) return(v)
  }
  if (file.exists(.marker)) return(getwd())
  cand <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  if (file.exists(file.path(cand, .marker))) cand else getwd()
}

METHOD_REGISTRY_PATH <- file.path("06_Registry", "method_registry.json")

#' 어댑터 계약 (한 줄): ctx -> named numeric over ctx$assets. 스케일·부호 자유.
#'
#' ctx 필드:
#'   Sigma         공분산 (assets × assets, PIT: 매수 이전 trailing 만)
#'   R             일별 수익 행렬 (obs × assets, 같은 창)
#'   mu            named numeric — 현 book 알파 score (없을 수 있음)
#'   assets        colnames(Sigma)
#'   ub            상한 (0.20)
#'   lookback_days Σ 추정창 길이
#'   decision_date / eval_date
#' 반환: assets 순서의 numeric. NA/Inf 허용(하네스가 0 으로 처리).

#' 어댑터를 제약-강제 래퍼로 감싼다. ★어댑터는 제약을 지킬 의무가 없다 — 여기서 강제한다.
wrap_adapter <- function(fn, method_id, ub = 0.20) {
  force(fn); force(method_id); force(ub)
  function(ctx) {
    v <- tryCatch(fn(ctx), error = function(e) {
      # ★실패를 조용히 EW 로 내려앉히지 않는다 — 이름을 부르고 EW 폴백임을 남긴다.
      cat(sprintf("[method:%s] 어댑터 실패 → EW 폴백: %s\n", method_id, conditionMessage(e)))
      NULL
    })
    a <- ctx$assets
    if (is.null(v)) return(setNames(rep(1 / length(a), length(a)), a))
    w <- suppressWarnings(as.numeric(v[a]))
    w[!is.finite(w)] <- 0
    w <- pmax(w, 0)
    if (sum(w) <= 1e-12) {
      cat(sprintf("[method:%s] 전량 0/음수 선호 → EW 폴백\n", method_id))
      return(setNames(rep(1 / length(a), length(a)), a))
    }
    names(w) <- a
    # ★스케일 정규화를 **먼저** 한다 (2026-08-08 실측 결함).
    #   normalize_long_only 은 `w[w > ub] <- ub` 를 **정규화 전에** 적용한다(production verbatim).
    #   임의 스케일 선호 벡터(예: 3.8~38.2)를 그대로 넣으면 전 원소가 ub 로 잘려 **동일해지고**,
    #   그 뒤 합-정규화되어 **정확히 EW** 가 된다 — 어댑터는 "돌았는데 아무것도 안 한" 상태가 된다.
    #   실측: minvar 빌트인이 정확히 1/25(0.040000~0.040000)였다. 검사 [3] 의 EW-구별 축이 검거.
    w <- w / sum(w)
    out <- normalize_long_only(w, lb = 0, ub = ub, target_sum = 1)
    # 사후 단언 — 여기서 깨지면 어댑터가 아니라 **하네스 결함**이다(조용히 넘기지 않는다).
    stopifnot(all(is.finite(out)), all(out >= -1e-9), all(out <= ub + 1e-9),
              abs(sum(out) - 1) < 1e-6)
    out
  }
}

#' 레지스트리 로드 → verdict=="implemented" 인 어댑터만 sourcing 해 named list 반환.
#' @param route "optimizer" | "risk" — 해당 라우트 method 만.
#' @param only  선택적 method_id 벡터(그날 큐에 든 논문만 돌릴 때).
load_method_adapters <- function(route = "optimizer", only = NULL, ub = 0.20, root = .mr_root()) {
  rp <- file.path(root, METHOD_REGISTRY_PATH)
  if (!file.exists(rp)) {
    cat(sprintf("[method_registry] 레지스트리 부재: %s — 등록 method 0건\n", rp))
    return(list())
  }
  reg <- fromJSON(rp, simplifyVector = FALSE)
  ms <- reg$methods
  if (is.null(ms) || length(ms) == 0) return(list())
  out <- list()
  n_skip <- list(verdict = 0L, route = 0L, missing = 0L)
  for (m in ms) {
    if (!identical(m$route, route)) { n_skip$route <- n_skip$route + 1L; next }
    if (!is.null(only) && !(m$method_id %in% only)) next
    if (!identical(m$verdict, "implemented")) { n_skip$verdict <- n_skip$verdict + 1L; next }
    ap <- file.path(root, m$adapter)
    if (!file.exists(ap)) {
      # ★"구현됨"이라고 등재됐는데 파일이 없다 = 등재가 판정으로 위장한 상태. 이름을 부른다.
      cat(sprintf("[method_registry] ★%s: verdict=implemented 인데 어댑터 파일 부재 (%s) — 건너뜀\n",
                  m$method_id, m$adapter))
      n_skip$missing <- n_skip$missing + 1L; next
    }
    env <- new.env(parent = globalenv())
    ok <- tryCatch({ sys.source(ap, envir = env); TRUE },
                   error = function(e) { cat(sprintf("[method_registry] %s source 실패: %s\n",
                                                     m$method_id, conditionMessage(e))); FALSE })
    if (!ok) next
    fname <- m$entrypoint %||% "method_weights"
    if (!exists(fname, envir = env, inherits = FALSE)) {
      cat(sprintf("[method_registry] ★%s: 진입점 `%s` 부재 — 건너뜀\n", m$method_id, fname)); next
    }
    out[[m$method_id]] <- wrap_adapter(get(fname, envir = env), m$method_id, ub = ub)
  }
  cat(sprintf("[method_registry] route=%s 등록 %d건 로드 (건너뜀: 타route %d · 미구현 %d · 파일부재 %d)\n",
              route, length(out), n_skip$route, n_skip$verdict, n_skip$missing))
  out
}

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

#' 라우트별 triage 요약 — "등재됐다"가 아니라 "무슨 처분을 받았나"를 낸다.
#' ★원장 등재(존재)를 판정(처분)으로 읽는 사고가 반복돼 왔다([[project-screen-route-consumer-zero-20260802]]).
#'   그래서 보고에는 항상 verdict 와 blocker 를 함께 싣는다.
method_triage <- function(route, root = .mr_root()) {
  rp <- file.path(root, METHOD_REGISTRY_PATH)
  if (!file.exists(rp)) return(list())
  reg <- fromJSON(rp, simplifyVector = FALSE)
  ms <- Filter(function(m) identical(m$route, route), reg$methods %||% list())
  lapply(ms, function(m) list(
    method_id = m$method_id, paper_id = m$paper_id, verdict = m$verdict,
    blocker = m$blocker %||% (m$note %||% NA_character_),
    unblock_requirement = m$unblock_requirement %||% NA_character_))
}

#' triage 를 사람이 읽는 한 줄로.
method_triage_line <- function(route, root = .mr_root()) {
  tri <- method_triage(route, root)
  if (!length(tri)) return(sprintf("%s: 등록 method 0건", route))
  vs <- vapply(tri, function(x) as.character(x$verdict), character(1))
  paste0(sprintf("%s method %d건 — ", route, length(tri)),
         paste(sprintf("%s(%s)", vapply(tri, function(x) x$method_id, character(1)), vs), collapse = ", "))
}

#' 신규성 점검 — factor DB 중복 사고(approved 102에 EXACT 10~12쌍)의 method 판.
#' 지금은 registry 의 `similar_to` 선언을 보고 경고만 한다. 등재 시 사람이 채운다.
method_novelty_warn <- function(root = .mr_root()) {
  rp <- file.path(root, METHOD_REGISTRY_PATH)
  if (!file.exists(rp)) return(invisible(NULL))
  reg <- fromJSON(rp, simplifyVector = FALSE)
  for (m in reg$methods) {
    st <- m$similar_to
    if (!is.null(st) && length(st) > 0)
      cat(sprintf("[method_registry] ⚠신규성: %s 는 기존 %s 와 유사 선언 — 중복 여부 확인 필요\n",
                  m$method_id, paste(unlist(st), collapse = ", ")))
  }
  invisible(NULL)
}
