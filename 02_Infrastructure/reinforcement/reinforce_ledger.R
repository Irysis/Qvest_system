# =============================================================================
# reinforce_ledger.R — 강화 프로세스 원장 (v10 2026-08-29 신설, 통일 스키마 v2)
# =============================================================================
# 도훈 지시:
#   1계층: "강화 프로세스는 최대 20회 진행 … 실패의 재생산을 방지하기 위해 20회 제한"
#          + "논문 3개마다 Q-Lead 가 아이디어 결합을 자체 검토"
#   2계층: "강화 프로세스 시도 횟수 제한이 없으며 교훈을 지속적으로 주입 받으면서
#          A등급 달성까지 무한 리서치 모드"
#   공통: "리서치 계획 설계 전에 Axiom 엔진을 활용하여 공리·교훈 주입, 완결 이후
#          교훈 생산 필수" + "모든 의사결정에 근거 논문(원문 링크) 필수"
#
# ★코드베이스에 시도 카운터 개념이 없었다(2026-08-29 전수 실측) — 이 원장이 유일 정본.
# ★root_papers 필수 거부 = "하드코딩 전면 금지 · 논문 근거 의무"의 기계 강제점.
# ★구 reinforce_ladder_ledger.json(기계 사다리, v9.21)은 read-only 동결 — 별개 파일.
#
# 파일: 06_Registry/reinforce_ledger_l1.json (max_attempts=20)
#       06_Registry/reinforce_ledger_l2.json (max_attempts=null — 무한)
# 쓰기 계약: 원자(tmp+rename) + 쓰기 직전 재파싱 검증 (paper_id_norm append 계약 미러).
# =============================================================================

suppressPackageStartupMessages({ library(jsonlite) })

.rf_root <- function() {
  cands <- unique(c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd()))
  is_root <- function(p) nzchar(p) && dir.exists(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))
  for (p in cands) if (is_root(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  cur <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  repeat {
    if (is_root(cur)) return(cur)
    parent <- dirname(cur)
    if (identical(parent, cur)) break
    cur <- parent
  }
  stop("[reinforce_ledger] project root 미발견 — QM_ROOT 설정 필요")
}

# ★universe 는 2026-08-30 도훈 지시로 격자 B3 가 리스크오버레이 → 유니버스로 바뀌면서 생겼다.
#   그런데 이 목록은 안 따라와서 B3 5칸이 **등록 자체로 거부**됐고(append_failed → halt_no_jobs)
#   루프가 10/20 에서 멈췄다. risk_overlay 는 격자 밖 경로에서 쓰이므로 존치한다.
RF_KEYWORD_AXES_L1 <- c("multifactor", "weighting", "universe", "risk_overlay", "combination")
RF_KEYWORD_AXES_L2 <- c("regime_identification", "strategy_combination")
RF_STATUS_ENUM <- c("active", "graduated", "exhausted", "superseded", "parked")

.rf_path <- function(layer, root = .rf_root()) {
  stopifnot(layer %in% c(1L, 2L))
  file.path(root, "06_Registry", sprintf("reinforce_ledger_l%d.json", layer))
}

.rf_skeleton <- function(layer) {
  list(
    schema_version = "reinforce_ledger_v2",
    layer = as.integer(layer),
    max_attempts = if (layer == 1L) 20L else NULL,   # NULL = 무한 (2계층)
    note = if (layer == 1L)
      "v10 1계층 강화 원장 — QEPM(alpha→risk→optimizer→forge→등급) 기반, 논문당 최대 20회. root_papers 없는 attempt 는 거부(논문 근거 의무). 논문 3편마다 combination_review 의무." else
      "v10 2계층 강화 원장 — 국면식별/전략결합 축, A등급까지 무한. 착수 시 직전 attempts 의 lessons 주입 의무.",
    entries = list(),
    combination_review = if (layer == 1L)
      list(papers_since_last_review = 0L, last_review_date = "", history = list()) else NULL,
    last_updated = ""
  )
}

rf_load <- function(layer, root = .rf_root()) {
  p <- .rf_path(layer, root)
  if (!file.exists(p)) return(.rf_skeleton(layer))
  obj <- fromJSON(p, simplifyVector = FALSE)
  if (!identical(obj$schema_version, "reinforce_ledger_v2"))
    stop(sprintf("[reinforce_ledger] schema_version 불일치: %s", obj$schema_version))
  obj
}

.rf_write <- function(obj, layer, root = .rf_root()) {
  # 재파싱 검증 후 원자 쓰기
  obj$last_updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  txt <- toJSON(obj, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6)
  chk <- tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(chk) || length(chk$entries) != length(obj$entries))
    stop("[reinforce_ledger] 쓰기 직전 재파싱 검증 실패 — 원본 불변")
  p <- .rf_path(layer, root)
  tmp <- paste0(p, ".tmp")
  write(txt, tmp)
  ok <- suppressWarnings(file.rename(tmp, p))
  if (!ok) { file.copy(tmp, p, overwrite = TRUE); unlink(tmp) }  # Windows 폴백(소비자 재시도 별도)
  invisible(p)
}

.rf_find <- function(obj, base_id) {
  for (i in seq_along(obj$entries)) if (identical(obj$entries[[i]]$base_id, base_id)) return(i)
  NA_integer_
}

#' 강화 대상 등록 (충실구현/로테이션 라운드가 A 미달로 끝났을 때)
#' @param carry  승격 entry 전용 — 부모의 승자 구성(factors/weighting/universe).
#'   러너가 매 셀 스펙에 이것을 먼저 깔고 그 위에 격자 축을 얹는다.
#' @param parent 승격 계보(부모 base_id · 승자 셀 · 그 때 port_t · 깊이).
#' @param count_paper 논문 소비 카운터를 올릴지. ★승격은 새 논문이 아니다 — FALSE 로 부른다.
#'   (TRUE 로 두면 결합 검토 3편 주기가 승격 횟수만큼 앞당겨져 검토 대상이 헛돈다)
rf_open_entry <- function(layer, base_id, base_grade,
                          paper_key = "", paper_id = "",
                          base_artifacts = "", engine_path = "",
                          carry = NULL, parent = NULL, count_paper = TRUE,
                          root = .rf_root()) {
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (!is.na(i)) {
    cat(sprintf("[reinforce_ledger] 기존 entry 재사용: %s (attempts %d)\n",
                base_id, obj$entries[[i]]$attempts_used))
    return(invisible(obj$entries[[i]]))
  }
  entry <- list(
    base_id = base_id, base_grade = as.character(base_grade),
    paper_key = as.character(paper_key), paper_id = as.character(paper_id),
    base_artifacts = as.character(base_artifacts), engine_path = as.character(engine_path),
    status = "active", target_grade = "A",
    attempts_used = 0L, attempts = list(),
    judge = list(spawned = FALSE, verdict_path = NULL),
    opened_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  if (!is.null(carry))  entry$carry  <- carry
  if (!is.null(parent)) entry$parent <- parent
  obj$entries[[length(obj$entries) + 1L]] <- entry
  # 1계층: 논문 소비 카운터 +1 → 3편마다 결합 검토 플래그
  if (layer == 1L && isTRUE(count_paper)) {
    n <- as.integer(obj$combination_review$papers_since_last_review %||% 0L) + 1L
    obj$combination_review$papers_since_last_review <- n
    if (n >= 3L)
      cat("[reinforce_ledger] ★결합 검토 도래 — 논문 3편 소비. Q-Lead 는 논문 간 아이디어 결합 기회를 검토하고 rf_record_combination_review() 로 기록할 것 (착수 여부 무관 — 검토 자체가 의무)\n")
  }
  .rf_write(obj, layer, root)
  cat(sprintf("[reinforce_ledger] L%d entry open: %s (base %s)\n", layer, base_id, base_grade))
  invisible(entry)
}

#' 강화 시도 1회 사전 등록 — ★여기가 20회 게이트다 (1계층)
#' root_papers = list(list(url=..., claim=...), ...) — 비면 거부(논문 근거 의무).
rf_append_attempt <- function(layer, base_id, idea, keyword_axis, root_papers,
                              wt_id = NULL, root = .rf_root()) {
  axes <- if (layer == 1L) RF_KEYWORD_AXES_L1 else RF_KEYWORD_AXES_L2
  if (!keyword_axis %in% axes)
    stop(sprintf("[reinforce_ledger] keyword_axis '%s' 는 L%d 축이 아님 (허용: %s)",
                 keyword_axis, layer, paste(axes, collapse = "/")))
  # ★논문 근거 의무 (v10 절대 규칙) — 기계 강제점
  urls <- vapply(root_papers %||% list(),
                 function(x) as.character(x$url %||% ""), character(1))
  if (!length(urls) || !any(nzchar(urls)))
    stop("[reinforce_ledger] root_papers 에 원문 url 이 1건도 없음 — 논문 근거 없는 강화 시도는 거부한다 (v10 하드코딩 금지·논문 근거 의무)")

  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s — rf_open_entry 먼저", base_id))
  e <- obj$entries[[i]]
  if (!identical(e$status, "active"))
    stop(sprintf("[reinforce_ledger] entry status=%s — active 아님", e$status))
  # ★20회 상한 (1계층만)
  maxa <- obj$max_attempts
  if (!is.null(maxa) && e$attempts_used >= maxa) {
    e$status <- "exhausted"
    obj$entries[[i]] <- e
    .rf_write(obj, layer, root)
    stop(sprintf("[reinforce_ledger] ★%d회 소진 — entry %s status=exhausted. 새 논문으로 1계층 재개 (도훈 지시: 실패의 재생산 방지)", maxa, base_id))
  }
  # 같은 뿌리 논문 연속 3회 경고 (한 논문 매몰 금지 — 차단 아님)
  prev_urls <- unlist(lapply(tail(e$attempts, 2L), function(a)
    vapply(a$root_papers %||% list(), function(x) as.character(x$url %||% ""), character(1))))
  if (length(e$attempts) >= 2L && all(urls %in% prev_urls) && length(urls) > 0)
    cat("[reinforce_ledger] WARN: 같은 root_papers 3회 연속 — 한 논문 매몰 금지 (교차 논문 탐색 권장)\n")

  n <- e$attempts_used + 1L
  att <- list(n = n, date = format(Sys.Date(), "%Y%m%d"),
              idea = as.character(idea), keyword_axis = keyword_axis,
              root_papers = root_papers, wt_id = wt_id,
              axiom_injected = TRUE,   # PreToolUse[Agent] axiom_context_inject 자동 (스폰 경유 시)
              grade = NA, essence = NULL, artifacts = NULL, l_code = NULL,
              lessons = NULL, opened_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  e$attempts[[length(e$attempts) + 1L]] <- att
  e$attempts_used <- n
  obj$entries[[i]] <- e
  .rf_write(obj, layer, root)
  cap_txt <- if (is.null(maxa)) "무한" else sprintf("%d/%d", n, maxa)
  cat(sprintf("[reinforce_ledger] L%d attempt %s 등록: %s [%s]\n", layer, cap_txt, base_id, keyword_axis))
  invisible(att)
}

#' 시도 결과 기록 (QEPM 완주 후 — 등급·교훈·산출물)
rf_record_result <- function(layer, base_id, n, grade, essence = NULL,
                             artifacts = NULL, l_code = NULL, lessons = NULL,
                             root = .rf_root()) {
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s", base_id))
  e <- obj$entries[[i]]
  j <- which(vapply(e$attempts, function(a) identical(as.integer(a$n), as.integer(n)), logical(1)))
  if (!length(j)) stop(sprintf("[reinforce_ledger] attempt n=%s 부재 (%s)", n, base_id))
  j <- j[1]
  e$attempts[[j]]$grade <- as.character(grade)
  e$attempts[[j]]$essence <- essence
  e$attempts[[j]]$artifacts <- artifacts
  e$attempts[[j]]$l_code <- l_code
  e$attempts[[j]]$lessons <- lessons
  e$attempts[[j]]$closed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  if (identical(as.character(grade), "A")) {
    e$status <- "graduated"
    cat(sprintf("[reinforce_ledger] ★Grade A — %s graduated. Judge(PIT) 스폰 → PASS 시 BOOK 등록\n", base_id))
  }
  obj$entries[[i]] <- e
  .rf_write(obj, layer, root)
  invisible(e$attempts[[j]])
}

#' 조기 중단(파킹) — 20회 소진 전에 도훈 결정으로 논문을 접을 때
#'
#' ★왜 필요한가: status enum 은 active / exhausted(20회 소진) / graduated(Grade A) 뿐이라
#' "20회를 다 쓰지 않았지만 도훈이 접기로 했다" 를 표현할 어휘가 없었다. active 로 남기면
#' v10 /qvest 규칙("원장 L1 active 우선")이 다음 세션에서 그 논문을 **자동 재개**해 결정과
#' 어긋난다(boot_lean.sh:56 이 status=="active" 만 센다). parked 는 재개 가능한 중단이다 —
#' 되돌리려면 status 를 active 로 명시적으로 되돌려야 하고, 그 사이 rf_append_attempt 의
#' active 검사(line ~142)가 새 시도를 막는다.
rf_park_entry <- function(layer, base_id, reason, root = .rf_root()) {
  if (!nzchar(as.character(reason %||% "")))
    stop("[reinforce_ledger] parked 는 사유 필수 — 왜 접었는지 없이 접지 않는다")
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s", base_id))
  e <- obj$entries[[i]]
  if (!identical(e$status, "active"))
    stop(sprintf("[reinforce_ledger] entry status=%s — active 만 park 할 수 있다", e$status))
  e$status        <- "parked"
  e$parked_reason <- as.character(reason)
  e$parked_at     <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  e$parked_at_attempt <- as.integer(e$attempts_used %||% 0L)
  obj$entries[[i]] <- e
  .rf_write(obj, layer, root)
  cat(sprintf("[reinforce_ledger] entry %s parked (시도 %d/%s 소진) — %s
",
              base_id, as.integer(e$attempts_used %||% 0L),
              as.character(obj$max_attempts %||% "inf"), reason))
  invisible(e)
}

#' Judge verdict 기록
rf_record_judge <- function(layer, base_id, verdict_path, pit_pass, root = .rf_root()) {
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s", base_id))
  obj$entries[[i]]$judge <- list(spawned = TRUE, verdict_path = as.character(verdict_path),
                                 pit_pass = isTRUE(pit_pass),
                                 judged_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  if (!isTRUE(pit_pass)) {
    obj$entries[[i]]$status <- "active"   # PIT FAIL → 결과 무효, 수리·재측정 (등급 재산출)
    cat("[reinforce_ledger] PIT FAIL — 등급 무효, entry 재활성화 (수리 후 재측정)\n")
  }
  .rf_write(obj, layer, root)
  invisible(obj$entries[[i]])
}

#' 결합 검토 기록 (1계층 — 논문 3편마다 의무. 착수 여부와 무관하게 검토 자체를 기록)
rf_record_combination_review <- function(reviewed_papers, verdict, note = "",
                                         combined_entry_base_id = NULL, root = .rf_root()) {
  obj <- rf_load(1L, root)
  h <- obj$combination_review$history %||% list()
  h[[length(h) + 1L]] <- list(
    date = format(Sys.Date(), "%Y-%m-%d"),
    reviewed_papers = reviewed_papers,
    verdict = as.character(verdict),   # "combined" | "no_combination" (+사유)
    note = as.character(note),
    combined_entry_base_id = combined_entry_base_id)
  obj$combination_review$history <- h
  obj$combination_review$papers_since_last_review <- 0L
  obj$combination_review$last_review_date <- format(Sys.Date(), "%Y-%m-%d")
  .rf_write(obj, 1L, root)
  cat(sprintf("[reinforce_ledger] 결합 검토 기록 (%s) — 카운터 리셋\n", verdict))
  invisible(h[[length(h)]])
}

#' 착수 시 교훈 주입용 — 해당 entry 의 직전 attempts 요약 (2계층 무한 모드의 "지속 주입")
rf_lessons_digest <- function(layer, base_id, n_last = 5L, root = .rf_root()) {
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) return(character(0))
  atts <- tail(obj$entries[[i]]$attempts, n_last)
  vapply(atts, function(a) sprintf("n%s [%s] %s → %s%s",
                                   a$n, a$keyword_axis,
                                   substr(as.character(a$idea), 1, 60),
                                   a$grade %||% "미측정",
                                   if (!is.null(a$lessons)) paste0(" | ", paste(unlist(a$lessons), collapse = "; ")) else ""),
         character(1))
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

cat("[reinforce_ledger.R] Loaded (v10) — rf_open_entry / rf_append_attempt(★L1 20회 게이트·root_papers 필수) / rf_record_result / rf_park_entry(조기 중단·사유 필수) / rf_record_judge / rf_record_combination_review / rf_lessons_digest\n")
