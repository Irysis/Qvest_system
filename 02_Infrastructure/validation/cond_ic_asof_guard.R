# =============================================================================
# cond_ic_asof_guard.R — V6 조건부 IC 소비의 호출부 가드 (도훈 결정 D-E-V6-CONDITIONAL-IC 2026-09-25)
# =============================================================================
# 사실: `.cache/conditional_ic_matrix.csv` 는 stage_gate_engine.R::sg_compute_conditional_ic 가 **전기간** IC 로 만든
#   횡단면 스냅샷이다(Usable_Date 열 없음 · as-of 판이 아니다). 엔진의 소비 함수 4종이 그 conditional_value 로
#   역할·입장·효용·S5 후보를 정한다 = 평가 창 결과를 소비하는 자동 선정(pit.md C1/C14 · D-E 2026-09-23):
#     sg_compute_role_utility (w4 항)   sg_determine_role (defense 분기)
#     sg_generate_research_slate (A/B/C 슬롯 정렬)   sg_role_admission (defense 입장)
# 규칙(pit.md V6 Gap-Directed 절): 조건부 IC 는 `Usable_Date <= 결정 시점` 의 as-of 판만. 제공되지 않으면 사용하지 않는다.
# as-of 제공자: **미채택** — rf_sl_conditional_ic_asof(rf_sleeve.R) 채택은 도훈 결정 사항이다. 그래서 이 가드는
#   언제나 '미제공' 경로(행렬 가림)로 돈다(cic_asof_provided() = FALSE · fail-closed).
#
# 수리 위치 = 호출부. stage_gate_engine.R 는 바이트 불변(플랜 '하지 말 것' 8 · 결정 = 호출부 차단):
#   이 모듈은 소비 함수의 **사본**을 만들어 그 사본의 file.path 만 바꾼다 — 행렬 경로가 존재하지 않는 경로로 풀려
#   원본의 '행렬 부재' 분기로 간다(원본 함수 객체·엔진 파일은 건드리지 않는다).
#   가림 전 AST 검사: 본문 안 행렬 표지(공백 없는 문자열 상수 속 "conditional_ic")가 전부 file.path 의 직접 인자여야 하고
#   1개 이상이어야 한다. base::file.path · paste0 · list.files · sprintf 등 가림을 비껴가는 경로나, 표지가 사라진 구조
#   변경(도우미 함수로 이관 등)은 가림 범위를 알 수 없으므로 **거부**한다(stop — fail-closed).
#
# 사용(호출부):
#   source("02_Infrastructure/stage_gate_engine.R"); source("02_Infrastructure/validation/cond_ic_asof_guard.R")
#   role <- sg_determine_role_asof(s2, s3, s4)                  # defense 는 조건부 IC 근거로 나오지 않는다
#   adm  <- sg_role_admission_asof(role, s4, s3)                # defense 입장 = S5(근거 미제공)
#   u    <- sg_compute_role_utility_asof(id, role, s2, s3, s4)  # utility_score = NA(미측정 — 아래 ②)
#   sl   <- sg_generate_research_slate_asof(fid, sid)           # NULL · 파일 쓰기 없음
#   ② 효용의 w4(conditional_value) 항: 가림만 하면 원본이 cond_val=0 → cond_norm=0.5 로 정규화해 w4×0.5(defense 0.2)의
#     **가짜 기여**가 남는다. 항 제거는 역할별 척도를 바꾸고(defense 상한 0.30 vs core_alpha 0.70 — 역할 간 비교가 한쪽으로
#     기운다) 재정규화는 근거 없는 새 수치 결정이다. 그래서 U = NA(미측정 — '계약 미경유 = NA' 원칙)로 둔다. 다른 성분은
#     진단용으로 그대로 싣고, component_scores$conditional_value 도 NA 로 둔다.
# 정적 봉인(08_Tests/validation/test_cond_ic_asof_guard.R §C): 소비 함수 4종의 직접 호출·이름 참조는 엔진 정의와 이 모듈
#   밖에서 0이어야 하고, 행렬 파일명을 코드에서 부르는 파일은 허용 목록(생산자·차단기·파생 저장소 생산자)뿐이다.
# =============================================================================

CIC_GUARD_VERSION <- "D-E-V6-CONDITIONAL-IC/2026-09-25"
CIC_GUARD_TARGETS <- c("sg_compute_role_utility", "sg_determine_role", "sg_generate_research_slate", "sg_role_admission")
.CIC_MARK_RX <- "conditional_ic"

# as-of 판 제공 여부 — 제공자 미채택(도훈 결정 사항). TRUE 로 바꾸려면 이 가드를 제공자와 함께 개정한다
# (가림 대신 as-of 행렬을 싣는 경로가 이 모듈에 아직 없다 — 여기만 TRUE 로 바꾸면 아래 .cic_policy 가 멈춘다).
cic_asof_provided <- function() FALSE

.cic_policy <- function() {
  if (!identical(cic_asof_provided(), FALSE))
    stop("[cic_guard] as-of 제공 경로는 아직 구현되지 않았다 — 제공자 채택은 가드 개정과 함께(D-E-V6 · fail-closed)", call. = FALSE)
  invisible(TRUE)
}

# 함수 본문(형식 인자 기본값 포함)에서 행렬 표지를 가진 문자열 상수마다 '그 상수를 직접 인자로 받는 호출의 머리'를 돌려준다.
# 공백이 있는 문자열(메시지)은 경로가 아니므로 제외한다.
cic_marker_heads <- function(fn) {
  out <- character(0)
  walk <- function(e, head) {
    if (is.character(e)) {
      hit <- grepl(.CIC_MARK_RX, e, ignore.case = TRUE) & !grepl("[[:space:]]", e)
      if (any(hit)) out <<- c(out, rep(head, sum(hit)))
      return(invisible(NULL))
    }
    if (is.call(e)) {
      h <- e[[1L]]
      hd <- if (is.symbol(h)) as.character(h) else paste(deparse(h), collapse = "")
      if (!is.symbol(h)) walk(h, "<call-head>")
      n <- length(e)
      if (n >= 2L) for (i in 2:n) {
        if (is.symbol(e[[i]]) && !nzchar(as.character(e[[i]]))) next
        walk(e[[i]], hd)
      }
      return(invisible(NULL))
    }
    if (is.pairlist(e) || is.expression(e) || is.list(e)) for (i in seq_along(e)) {
      if (is.symbol(e[[i]]) && !nzchar(as.character(e[[i]]))) next
      walk(e[[i]], head)
    }
    invisible(NULL)
  }
  walk(formals(fn), "<formals>")
  walk(body(fn), "<body>")
  out
}

.cic_blinded_path <- function() {
  p <- file.path(tempdir(), "__cic_asof_unprovided__", "conditional_ic_matrix.unprovided")
  if (file.exists(p) || dir.exists(dirname(p)))
    stop("[cic_guard] 가림 경로가 실재한다(", p, ") — 가림이 무력해질 수 있어 멈춘다(fail-closed)", call. = FALSE)
  p
}

# 소비 함수 사본의 행렬 경로를 가린다(원본 불변). deny_write = TRUE 면 사본 안의 write_json·dir.create 도 막는다
# (가림이 어떤 이유로든 뚫려 slate 를 쓰려 하면 쓰기 전에 멈춘다).
cic_blind <- function(fn, name = "<fn>", deny_write = FALSE) {
  if (!is.function(fn) || is.primitive(fn) || is.null(environment(fn)))
    stop(sprintf("[cic_guard] %s: 클로저가 아니다 — 가릴 수 없다(fail-closed)", name), call. = FALSE)
  heads <- cic_marker_heads(fn)
  if (!length(heads))
    stop(sprintf("[cic_guard] %s: 행렬 표지 0 — 엔진 구조가 바뀌어 가림 범위를 알 수 없다(fail-closed · D-E-V6)", name), call. = FALSE)
  bad <- unique(heads[heads != "file.path"])
  if (length(bad))
    stop(sprintf("[cic_guard] %s: 행렬 표지가 file.path 밖에서 쓰인다(%s) — 가림 우회 경로(fail-closed · D-E-V6)",
                 name, paste(bad, collapse = ",")), call. = FALSE)
  blinded <- .cic_blinded_path()
  env <- new.env(parent = environment(fn))
  env$file.path <- function(...) {
    p <- base::file.path(...)
    hit <- grepl(.CIC_MARK_RX, basename(p), ignore.case = TRUE)
    if (any(hit)) p[hit] <- blinded
    p
  }
  if (isTRUE(deny_write)) {
    env$write_json <- function(...) stop(sprintf("[cic_guard] %s: 가림 상태에서 쓰기 시도 — 차단(fail-closed)", name), call. = FALSE)
    env$dir.create <- function(...) stop(sprintf("[cic_guard] %s: 가림 상태에서 디렉터리 생성 시도 — 차단(fail-closed)", name), call. = FALSE)
  }
  f <- fn
  environment(f) <- env
  f
}

.cic_orig <- function(name, envir) {
  f <- get0(name, envir = envir, mode = "function", inherits = TRUE)
  if (is.null(f))
    stop(sprintf("[cic_guard] %s 미적재 — stage_gate_engine.R 를 먼저 source 하라(fail-closed)", name), call. = FALSE)
  f
}

# ── 호출부 래퍼 4종 ─────────────────────────────────────────────────────────────
sg_determine_role_asof <- function(s2, s3, s4) {
  .cic_policy()
  pf <- parent.frame()
  f <- cic_blind(.cic_orig("sg_determine_role", pf), "sg_determine_role")
  f(s2, s3, s4)
}

sg_role_admission_asof <- function(provisional_role, s4, s3) {
  .cic_policy()
  pf <- parent.frame()
  f <- cic_blind(.cic_orig("sg_role_admission", pf), "sg_role_admission")
  invisible(utils::capture.output(r <- f(provisional_role, s4, s3)))
  # 원본은 cond 미상(NA)을 사유 문자열에 0 으로 적는다 — 미제공을 0 으로 보이게 두지 않는다.
  if (is.character(r$reason)) r$reason <- sub("cond=[-+0-9.eE]+", "cond=NA(as-of 미제공 · D-E-V6)", r$reason)
  r$cond_ic_basis <- "unprovided_asof"
  cat(sprintf("[v6] Admission: %s\n", r$reason))
  r
}

sg_compute_role_utility_asof <- function(candidate_id, provisional_role, s2, s3, s4) {
  .cic_policy()
  pf <- parent.frame()
  f <- cic_blind(.cic_orig("sg_compute_role_utility", pf), "sg_compute_role_utility")
  invisible(utils::capture.output(r <- f(candidate_id, provisional_role, s2, s3, s4)))
  r$utility_score <- NA_real_
  if (is.list(r$component_scores)) r$component_scores$conditional_value <- NA_real_
  r$utility_status <- "unmeasured:cond_ic_asof_unprovided"
  cs <- r$component_scores
  cat(sprintf("[v6] Role Utility: %s → role=%s, U=NA (조건부 IC as-of 미제공 — 미측정 · D-E-V6) (IC=%.2f, dSR=%.2f, orth=%.2f)\n",
              candidate_id, provisional_role, cs$ic_quality %||cic% NA_real_, cs$delta_sharpe %||cic% NA_real_,
              cs$orthogonality %||cic% NA_real_))
  r
}

sg_generate_research_slate_asof <- function(factor_id, strategy_id) {
  .cic_policy()
  pf <- parent.frame()
  f <- cic_blind(.cic_orig("sg_generate_research_slate", pf), "sg_generate_research_slate", deny_write = TRUE)
  invisible(utils::capture.output(r <- f(factor_id, strategy_id)))
  if (!is.null(r))
    stop("[cic_guard] 가림 뒤에도 slate 가 만들어졌다 — 가림 무력(fail-closed · D-E-V6)", call. = FALSE)
  cat(sprintf("[v6] Research Slate: %s — 조건부 IC as-of 판 미제공 → 생성 안 함(NULL · pit.md V6 · D-E-V6)\n", factor_id))
  invisible(NULL)
}

`%||cic%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
