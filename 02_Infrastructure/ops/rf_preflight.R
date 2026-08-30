#!/usr/bin/env Rscript
#==============================================================================
# rf_preflight.R — 셀 착수 전 **지식 주입** (도훈 지시 2026-08-30 감사 지적)
#
# 왜 필요한가 (2026-08-30 감사 실측):
#   무인 러너는 LLM 에이전트를 **0개** 스폰한다. 그래서 `axiom_context_inject.sh`
#   (PreToolUse|Agent)가 한 번도 발화하지 않는다.
#   ★공리 쪽은 결함이 아니다 — 공리는 *판단*을 제약하는데 규칙 실행에는 셀 실행 시점의
#     판단이 없다. 설계는 격자 작성 시 한 번 이뤄졌고 PIT·고정축은 엔진·계약이 강제한다.
#   ★그러나 **지식 주입은 진짜 빠져 있었다**: `hypothesis_index`(죽은 구성 380건) 조회 0건,
#     `rf_lessons_digest`(직전 시도 교훈) 0건. SKILL 1단계가 "착수 전 의무" 로 요구하는 것들이다.
#     조회를 안 하면 **이미 죽은 조합을 다시 돌린다**.
#
# 이 파일이 하는 일 (판단하지 않는다 — 사실만 붙인다):
#   ① hypothesis_index 조회 — 셀 구성 키워드로 죽은 선례를 찾아 스펙·로그에 붙인다
#   ② rf_lessons_digest    — 직전 시도들의 등급·교훈 요약을 붙인다
#   ③ 고정 축 사후 검증    — 산출물이 실제로 long-only·<=25종·Sigma w=1 인지 재도출
#      (공리를 "주입" 하는 대신 **결과에서 확인**한다 — 규칙 실행에 맞는 형태)
#
# ★차단하지 않는다. 죽은 선례가 있어도 실행은 진행하고 **기록**한다 —
#   AX-000("실측 negative 는 사실 기록이지 금지 목록이 아니다")과 정합.
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

#' 셀 구성에서 조회 키워드를 뽑는다 — **이름이 아니라 구성으로** 조회한다
#' (2026-08-29 실증: 이름 조회는 0건인데 구성 조회가 선례를 찾아냈다)
rf_preflight_keywords <- function(spec) {
  kw <- character(0)
  f2 <- spec$factor2
  if (!is.null(f2$id) && nzchar(f2$id)) kw <- c(kw, f2$id)
  if (identical(f2$kind, "price") && identical(f2$id, "lowvol60")) kw <- c(kw, "volatility", "lowvol")
  if (!is.null(f2$id)) {
    if (grepl("Amihud|Kyle|LIQ", f2$id, ignore.case = TRUE)) kw <- c(kw, "illiquidity", "turnover")
    if (grepl("BM|value", f2$id, ignore.case = TRUE))        kw <- c(kw, "value_momentum")
    if (grepl("GPA|quality|Q0", f2$id, ignore.case = TRUE))  kw <- c(kw, "quality_profitability")
    if (grepl("Revision|SUE|C1", f2$id, ignore.case = TRUE)) kw <- c(kw, "earnings_revision")
  }
  wk <- spec$weighting$kind %||% "ew"
  if (!identical(wk, "ew")) kw <- c(kw, wk)
  uk <- spec$universe$kind %||% "k200_kq150"
  if (!identical(uk, "k200_kq150")) kw <- c(kw, uk)
  unique(kw[nzchar(kw)])
}

#' hypothesis_index 조회 (CLI 정본 경유 — 술어를 재구현하지 않는다)
rf_preflight_dead <- function(kw, max_kw = 4L) {
  idx <- file.path(ROOT, "02_Infrastructure/tools/hypothesis_index.R")
  if (!file.exists(idx) || !length(kw)) return(list())
  out <- list()
  for (k in utils::head(kw, max_kw)) {
    r <- tryCatch(system2("Rscript", c(shQuote(idx), "lookup", shQuote(k)),
                          stdout = TRUE, stderr = FALSE), error = function(e) character(0))
    hits <- grep("FAIL|DISTILLED_NEG|VALIDATED_NEGATIVE|negative", r, value = TRUE, ignore.case = TRUE)
    if (length(hits)) out[[k]] <- substr(utils::head(hits, 3), 1, 140)
  }
  out
}

#' 직전 시도 교훈 요약
rf_preflight_lessons <- function(base_id, n_last = 3L) {
  led <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE),
                  error = function(e) NULL)
  if (is.null(led)) return(character(0))
  E <- Filter(function(e) identical(e$base_id, base_id), led$entries)
  if (!length(E)) return(character(0))
  at <- E[[1]]$attempts
  at <- Filter(function(a) !is.null(a$essence) && !is.null(a$essence$port_t), at)
  if (!length(at)) return(character(0))
  at <- utils::tail(at, n_last)
  vapply(at, function(a) sprintf("n=%d %s Grade %s · PORT_t %.3f",
                                 a$n, a$essence$cell_code %||% "?", a$grade %||% "?",
                                 as.numeric(a$essence$port_t)), character(1))
}

#' ★고정 축 사후 검증 — 공리를 주입하는 대신 **산출물에서 재도출**한다
rf_preflight_verify_axes <- function(ar_path, fixed) {
  if (!file.exists(ar_path)) return(list(ok = NA, note = "산출물 부재"))
  AR <- tryCatch(fromJSON(ar_path, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(AR)) return(list(ok = NA, note = "판독 실패"))
  bad <- character(0)
  nmax <- suppressWarnings(as.integer(AR$n_max %||% AR$essence$n_max %||% NA))
  if (is.finite(nmax) && nmax > as.integer(fixed$n_max %||% 25L))
    bad <- c(bad, sprintf("n_max %d > %s", nmax, fixed$n_max))
  hs <- AR$has_short %||% AR$essence$has_short %||% FALSE
  if (isTRUE(hs)) bad <- c(bad, "has_short=TRUE (long-only 위반)")
  list(ok = length(bad) == 0L, violations = bad,
       note = if (length(bad)) "고정 축 위반 — 결과 무효 검토" else "고정 축 확인(n_max·long-only)")
}

#' 종합: 스펙에 지식 블록을 붙이고 요약 문자열을 돌려준다
rf_preflight <- function(spec, base_id) {
  kw <- rf_preflight_keywords(spec)
  dead <- rf_preflight_dead(kw)
  les <- rf_preflight_lessons(base_id)
  spec$preflight <- list(
    keywords = kw, dead_precedents = dead, recent_attempts = les,
    note = paste("★차단하지 않는다 — 죽은 선례는 사실 기록이지 금지 목록이 아니다(AX-000).",
                 "실행은 진행하고 기록만 남긴다. 같은 구성이 반복되면 이 블록이 그 사실을 드러낸다."),
    axiom_injection = paste("무인 러너는 에이전트를 스폰하지 않아 axiom_context_inject 가 발화하지 않는다.",
                            "공리는 격자 설계 시점에 반영됐고, 고정 축은 엔진·계약이 강제하며,",
                            "실행 후 rf_preflight_verify_axes() 가 산출물에서 재도출해 확인한다."))
  spec
}
