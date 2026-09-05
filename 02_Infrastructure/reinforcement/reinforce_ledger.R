# =============================================================================
# reinforce_ledger.R — 강화 프로세스 원장 (v10 2026-08-29 신설, 통일 스키마 v2)
# =============================================================================
# 도훈 지시:
#   1계층: "강화 프로세스는 최대 20회 진행 … 실패의 재생산을 방지하기 위해 20회 제한"
#          ★2026-09-01 격자 재편(B5 리스크 오버레이 블록 신설 · 5블록×5)으로 상한 25 — 원장 파일 max_attempts=25 가 정본. 위 인용은 8-29 원문.
#          + "논문 3개마다 Q-Lead 가 아이디어 결합을 자체 검토"
#   2계층: "강화 프로세스 시도 횟수 제한이 없으며 교훈을 지속적으로 주입 받으면서
#          A등급 달성까지 무한 리서치 모드"
#   공통: "리서치 계획 설계 전에 Axiom 엔진을 활용하여 공리·교훈 주입, 완결 이후
#          교훈 생산 필수" + "모든 의사결정에 근거 논문(원문 링크) 필수"
#
# ★코드베이스에 시도 카운터 개념이 없었다(2026-08-29 전수 실측) — 이 원장이 유일 정본.
# ★root_papers 필수 거부는 2026-09-03 **해제**(도훈 "강화에는 근거논문 필요없게 배선해").
#   지금은 거부하지 않고 시도 레코드에 evidence = paper/method/none 을 남긴다.
# ★구 reinforce_ladder_ledger.json(기계 사다리, v9.21)은 read-only 동결 — 별개 파일.
#
# 파일: 06_Registry/reinforce_ledger_l1.json (max_attempts=25)
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
    max_attempts = if (layer == 1L) 25L else NULL,   # NULL = 무한 (2계층)
    note = if (layer == 1L)
      "v10 1계층 강화 원장 — QEPM(alpha→risk→optimizer→forge→등급) 기반, 논문당 최대 25회(격자 5블록×5). root_papers 는 선택(2026-09-03 의무 해제) — 시도마다 evidence=paper/method/none 기록. 논문 3편마다 combination_review 의무." else
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

#' 소진 요약 표식 — 요약·승격 판정은 entry 당 한 번이다 (2026-09-04).
#'   실측: 결합 설계 요청이 진행 중이면 handed_off 가 안 서서(둘 중 하나만 간다) exhausted_summary·
#'   promote_skipped 가 tick 마다 다시 찍혔다(combo_rulefast 3회). 이월은 handed_off 가, 요약은 이 표식이 막는다.
rf_is_summarized <- function(entry) nzchar(as.character(entry$summarized_at %||% ""))
rf_mark_summarized <- function(layer, base_id, root = .rf_root()) {
  obj <- rf_load(layer, root)
  k <- which(vapply(obj$entries, function(e) identical(e$base_id, base_id), logical(1)))
  if (!length(k)) stop("[reinforce_ledger] entry not found: ", base_id)
  obj$entries[[k[1]]]$summarized_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  .rf_write(obj, layer, root)
  invisible(TRUE)
}

#' 이월 완료 표식 — 이 entry 는 다음 tick 부터 요약·승격 대상이 아니다.
#'   두 이월 경로(다음 논문 hand-off · 승격)가 **같은 표식**을 남겨야 한다. 2026-09-05 실사고: 승격 경로가
#'   부모에 표식을 안 남겨, 손자가 큐로 넘어간 뒤 부모(promo2)가 "마지막 미이월 소진 entry" 로 다시 떠올라
#'   매 tick 재승격(기존 promo3 재사용)했다 — 큐 논문 미착수 + 라운드 리뷰 텔레그램 중복.
#' @param promoted_to 승격 경로면 자식 base_id (provenance) · hand-off 면 NULL
#' @param reason 소급 표식 등 사유(선택)
rf_mark_handed_off <- function(layer, base_id, root = .rf_root(), promoted_to = NULL, reason = NULL) {
  obj <- rf_load(layer, root)
  k <- which(vapply(obj$entries, function(e) identical(e$base_id, base_id), logical(1)))
  if (!length(k)) stop("[reinforce_ledger] entry not found: ", base_id)
  obj$entries[[k[1]]]$handed_off    <- TRUE
  obj$entries[[k[1]]]$handed_off_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  if (!is.null(promoted_to) && nzchar(promoted_to)) obj$entries[[k[1]]]$promoted_to <- promoted_to
  if (!is.null(reason) && nzchar(reason)) obj$entries[[k[1]]]$handed_off_reason <- reason
  .rf_write(obj, layer, root)
  invisible(TRUE)
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
    # ★측정 축 각인 (2026-09-01) — 새 entry 는 그 시점의 current_axis 를 달고 태어난다.
    #   이게 없으면 다음 축 전환 때 rf_mark_axis_epoch 이 "라벨 없음 = 구축" 으로 보고
    #   **신규분을 legacy 로 오분류**한다. 축은 비교 가능성의 경계이므로 태어날 때 정해야 한다.
    measurement_axis = obj$current_axis %||% "unlabeled", axis_valid = TRUE,
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

#' 강화 시도 1회 사전 등록 — ★여기가 25회 게이트다 (1계층 — 값은 원장 max_attempts)
#' root_papers = list(list(url=..., claim=...), ...) — 선택. 비어도 거부하지 않고 evidence="none" 으로 기록한다.
rf_append_attempt <- function(layer, base_id, idea, keyword_axis, root_papers,
                              wt_id = NULL, root = .rf_root(),
                              unmapped_families = NULL,
                              axiom_injected = FALSE,
                              cell_code = NULL) {
  axes <- if (layer == 1L) RF_KEYWORD_AXES_L1 else RF_KEYWORD_AXES_L2
  if (!keyword_axis %in% axes)
    stop(sprintf("[reinforce_ledger] keyword_axis '%s' 는 L%d 축이 아님 (허용: %s)",
                 keyword_axis, layer, paste(axes, collapse = "/")))
  # ★근거 논문 의무 — 강화 레인에서 해제 (도훈 지시 2026-09-03 "강화에는 근거논문 필요없게 배선해").
  #   구판은 url(또는 risk_overlay 의 method)이 하나도 없으면 stop 으로 거부했다. 이제 거부하지 않는다.
  #   ★해제 범위는 이 함수(강화 전용)뿐이다 — 충실구현은 run_paper_replication 의 source_paper 를
  #     쓰는 별도 경로이고, 논문을 재현하는 단계에서 논문을 뺄 수는 없으므로 그대로 둔다.
  #   ★왜 바뀌었나: 계열→논문 표(.RFF_FAMILY_PAPER)가 8계열만 담아 선정 풀 332종 중 91종(27%)이
  #     미매핑이었다. 깊이 1 셀은 거부되고 깊이 2+ 는 **형제 계열의 논문**으로 통과했다 —
  #     게이트가 시험 중인 축을 덮지 않는 근거로 충족되는, 지키는 척만 하는 상태였다.
  #     축의 정당성은 이제 격자(reinforce_program.json)와 팩터 등록부가 진다.
  #   root_papers 는 **있으면 그대로 기록**한다(출처 추적은 유지). 없다고 막지만 않는다.
  .rp   <- root_papers %||% list()
  urls  <- vapply(.rp, function(x) as.character(x$url    %||% ""), character(1))
  meths <- vapply(.rp, function(x) as.character(x$method %||% ""), character(1))
  .ok_url    <- length(urls)  && any(nzchar(urls))
  .ok_method <- length(meths) && any(nzchar(meths))
  .evidence  <- if (.ok_url) "paper" else if (.ok_method) "method" else "none"
  if (identical(.evidence, "none"))
    cat("[reinforce_ledger] 근거 논문 없음 — 기록만 하고 진행 (강화 레인 근거 의무 해제, 2026-09-03)\n")

  # ★서술 의무 (2026-09-03 신설) — 근거 의무(root_papers)와 같은 층에 둔다.
  #   sprintf 는 인자 하나가 NULL/character(0) 이면 **경고 없이** character(0) 을 돌려준다.
  #   호출자가 그걸 그대로 넘기면 원장에 idea=[] 가 박히고, 그 시도는 등급만 있고
  #   무엇을 한 시도인지 영원히 알 수 없게 된다(실측 184/305 = 60%).
  #   원장 밖 강화가 없듯, 서술 없는 시도도 없다.
  .idea <- suppressWarnings(as.character(idea %||% character(0)))
  .idea <- .idea[!is.na(.idea) & nzchar(trimws(.idea))]
  if (!length(.idea))
    stop("[reinforce_ledger] idea 가 비었다 — 무엇을 시도하는지 적지 않은 강화는 거부한다. ",
         "sprintf 조립이면 조각 하나가 NULL/character(0) 일 수 있다(영길이 붕괴).")

  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s — rf_open_entry 먼저", base_id))
  e <- obj$entries[[i]]
  if (!identical(e$status, "active"))
    stop(sprintf("[reinforce_ledger] entry status=%s — active 아님", e$status))
  # ★25회 상한 (1계층만 — 원장 max_attempts)
# ★entry 별 상한 (2026-09-04 도훈 지시). B1 이 설계에 따라 가변 길이가 되면서,
#   전역 25 를 그대로 두면 B1 이 쓴 만큼 뒤 블록이 잘린다 — 실측: B1 14칸 -> B4(결합)가
#   아예 못 돌았다. 각 블록 승자를 합치는 칸을 못 보면 그 entry 는 A 로 갈 길이 없다.
#   "칸 수 제한을 두지 마라" 를 B1 에만 적용하고 총예산에 안 적용한 비대칭을 닫는다.
  maxa <- e$max_attempts %||% obj$max_attempts
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
  # ★격자 좌표를 **등록 시점에** 박는다 (2026-09-04). 구판은 cell_code 가 essence 안에만
  #   있어서, 측정 전에는 이 시도가 격자의 어느 칸인지 원장만 봐서는 알 수 없었다.
  #   그래서 러너 커서가 개수(attempts_used+1)로 움직였고, 등록이 한 건 거부되면
  #   격자 위치와 시도 수가 영구히 어긋났다(실측: B1_1 미측정 · B1_5 2회 소각 ·
  #   승자 스펙이 재실행분으로 덮여 20칸이 다른 기저 위에 섬). 좌표는 자리를 잡을 때 남긴다.
  .cell_code <- { .cc <- suppressWarnings(as.character(cell_code %||% character(0)))
                  .cc <- .cc[!is.na(.cc) & nzchar(trimws(.cc))]
                  if (length(.cc)) .cc[1] else NA_character_ }
  att <- list(n = n, date = format(Sys.Date(), "%Y%m%d"),
              cell_code = .cell_code,
              idea = .idea, keyword_axis = keyword_axis,
              root_papers = root_papers, wt_id = wt_id,
              # ★근거 종류 — paper(원문 url) / method(방법 명시) / none. 의무는 해제됐지만
              #   사후에 "이 시도가 무엇에 기대어 돌았는가" 는 계속 셀 수 있어야 한다.
              evidence = .evidence,
              # ★근거 공백 표식 — 이 시도의 팩터 계열 중 논문 매핑이 없는 것들.
              #   비어 있지 않다는 것은 "형제 계열 논문으로 게이트를 통과했다" 는 뜻이다.
              unmapped_families = as.character(unmapped_families %||% character(0)),
              # ★상수 TRUE 였다(2026-09-03 수리). axiom_context_inject 는 PreToolUse[Agent] 라
              #   무인 R 레인을 지나지 않는데 316 시도 전부 TRUE 로 적혀 있었다 — 거짓 기록이다.
              #   지금은 호출자가 **실제 적재 여부**를 넘긴다. 기본값 FALSE = 증명 못 하면 안 적는다.
              axiom_injected = isTRUE(axiom_injected),
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


#' 블록 순서 사전등록 (v10.2 2026-09-03 · C층)
#' ★한 번만 쓴다. 이미 있으면 거부한다 — 결과를 보고 순서를 고쳐 쓰면 사후 선택이다.
#' @param order  블록 id 벡터(격자 blocks 의 부분순열이 아니라 **전체 순열**이어야 한다)
#' @param reason 결정 근거 — 진단 수치를 그대로 담는다(사후에 규칙을 재구성할 수 있게)
#' entry 별 시도 상한 기록 (2026-09-04) — B1 설계가 기본 칸수보다 많이 쓰면 총예산을 늘린다.
#'   ★전역 max_attempts 는 건드리지 않는다. 다른 논문의 예산까지 같이 움직이면 그건
#'   "이 설계가 진 교환" 이 아니라 규율 완화가 된다.
rf_record_entry_budget <- function(layer, base_id, max_attempts, reason, root = .rf_root()) {
  stopifnot(is.numeric(max_attempts) || !is.na(suppressWarnings(as.integer(max_attempts))))
  if (!nzchar(as.character(reason %||% ""))) stop("[reinforce_ledger] entry 상한 변경은 사유 필수")
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s", base_id))
  obj$entries[[i]]$max_attempts <- as.integer(max_attempts)
  obj$entries[[i]]$max_attempts_reason <- as.character(reason)
  obj$entries[[i]]$max_attempts_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  .rf_write(obj, layer, root)
  cat(sprintf("[reinforce_ledger] entry 상한 %s -> %d (%s)\n", base_id,
              as.integer(max_attempts), substr(reason, 1, 60)))
  invisible(as.integer(max_attempts))
}

rf_record_block_order <- function(layer, base_id, order, reason, adaptive = FALSE,
                                  root = .rf_root()) {
  order <- as.character(order); order <- order[nzchar(order)]
  if (!length(order)) stop("[reinforce_ledger] block_order 가 비었다")
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s", base_id))
  e <- obj$entries[[i]]
  if (length(as.character(e$block_order %||% character(0))))
    stop("[reinforce_ledger] block_order 는 이미 기록됐다 — 덮어쓰기 금지(사후 선택 방지)")
  e$block_order        <- as.list(order)
  e$block_order_reason <- as.character(reason %||% "")
  e$block_order_at     <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  # ★적응 탐색이면 표시한다 — 이 entry 의 탐색 경로가 측정에 의존했다는 사실이 남아야
  #   Judge 6축(selection 정직성)이 사후에 판정할 수 있다.
  e$search_adaptive    <- isTRUE(adaptive)
  obj$entries[[i]] <- e
  .rf_write(obj, layer, root)
  cat(sprintf("[reinforce_ledger] block_order 사전등록: %s [%s]%s\n",
              base_id, paste(order, collapse = ">"),
              if (isTRUE(adaptive)) " ★적응" else ""))
  invisible(order)
}

#' 시도 결과 기록 (QEPM 완주 후 — 등급·교훈·산출물)
#'
#' @param terminal 이 칸을 **더 이상 재시도하지 않는다**는 표식. 병렬 러너의 재개(resume)는
#'   essence 없는 칸을 무한히 다시 띄우는데, 그 설계는 *일시적* 실패(워커 미기동·시간초과)만
#'   상정했다. 구조적 실패 — 같은 스펙이면 몇 번을 돌려도 같은 자리에서 죽는 것 — 에는
#'   출구가 없어 루프가 제자리를 돈다(2026-08-31 실사고: B3_11 이 7.5시간 16회 동일 실패).
#'   terminal 은 "측정하지 못했다" 를 기록으로 **닫는다** — 성공으로 위장하지 않고(essence 는
#'   여전히 NULL), 재개 대상에서만 빠진다.
#' @param terminal_reason 왜 닫는가. 사유 없이 닫지 않는다.
rf_record_result <- function(layer, base_id, n, grade, essence = NULL,
                             artifacts = NULL, l_code = NULL, lessons = NULL,
                             terminal = FALSE, terminal_reason = NULL,
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
  # 실패 횟수는 등급이 아니라 **재시도 예산**의 축이다 — 소비자(러너)가 상한을 건다.
  if (is.null(essence)) {
    e$attempts[[j]]$fail_count <- as.integer(e$attempts[[j]]$fail_count %||% 0L) + 1L
  }
  if (isTRUE(terminal)) {
    if (!nzchar(as.character(terminal_reason %||% "")))
      stop("[reinforce_ledger] terminal 은 사유 필수 — 왜 닫는지 없이 닫지 않는다")
    e$attempts[[j]]$terminal <- TRUE
    e$attempts[[j]]$terminal_reason <- as.character(terminal_reason)
  }
  if (identical(as.character(grade), "A")) {
    e$status <- "graduated"
    cat(sprintf("[reinforce_ledger] ★Grade A — %s graduated. Judge(PIT) 스폰 → PASS 시 BOOK 등록\n", base_id))
  }
  obj$entries[[i]] <- e
  .rf_write(obj, layer, root)
  invisible(e$attempts[[j]])
}

#' 조기 중단(파킹) — 25회 소진 전에 도훈 결정으로 논문을 접을 때
#'
#' ★왜 필요한가: status enum 은 active / exhausted(25회 소진) / graduated(Grade A) 뿐이라
#' "25회를 다 쓰지 않았지만 도훈이 접기로 했다" 를 표현할 어휘가 없었다. active 로 남기면
#' v10 /qvest 규칙("원장 L1 active 우선")이 다음 세션에서 그 논문을 **자동 재개**해 결정과
#' 어긋난다(boot_lean.sh:56 이 status=="active" 만 센다). parked 는 재개 가능한 중단이다 —
#' 되돌리려면 status 를 active 로 명시적으로 되돌려야 하고, 그 사이 rf_append_attempt 의
#' active 검사(line ~142)가 새 시도를 막는다.
#' 측정 축 전환 기록 — 과거 entry 를 **무효 표시**하고 새 축의 시작을 남긴다
#'
#' 왜 필요한가 (2026-09-01 실사고): 강화 셀이 전부 **3종목 포트폴리오**를 재고 있었다.
#'   고정 축은 25인데 ① 엔진이 이미 상위 25를 잘라 FACTORS 를 내보내고
#'   ② run_paper_replication 의 top_n_long 이 그 25를 다시 분위(10%)로 잘랐다.
#'   거들던 것은 키 불일치 — 셀 실행 경로가 `n =` 을 넘기는데 러너는 spec$n_max/$n_long 을
#'   읽어서 **격자의 n_max 가 한 번도 전달된 적이 없었다**.
#'   축이 바뀌면 과거 측정은 "틀린 값" 이 아니라 **다른 축에서 잰 값**이다. 지우지 않고
#'   표시한다 — 비교만 막고 기록은 남긴다(사후 재현·귀속이 살아 있어야 한다).
#'
#' @param epoch  새 축 이름(예: "n_max_25")
#' @param legacy 과거 축 이름(예: "legacy_double_selection")
#' @param reason 왜 축이 바뀌었나 (필수)
#' @param evidence 실측 근거 1줄 (필수 — 진술만으로 무효화하지 않는다)
#' 25칸 소진 — status=exhausted (2026-09-05 · 퇴역 러너의 인라인 루틴을 writer 로 승격)
#'   실사고: 러너 단일화(09-05)로 병렬 러너의 소진 위임부가 퇴역된 reinforce_auto_run.R 을 부르고 있었고,
#'   그 파일은 안내문만 찍고 종료해 promo2 소진 → 승격이 조용히 실패했다(exhaust_reached 이벤트 0건).
#'   park 아님 — park 은 도훈 조기중단 전용. 이미 exhausted 면 멱등.
rf_exhaust_entry <- function(layer, base_id, root = .rf_root()) {
  obj <- rf_load(layer, root)
  i <- .rf_find(obj, base_id)
  if (is.na(i)) stop(sprintf("[reinforce_ledger] entry 부재: %s", base_id))
  if (!identical(obj$entries[[i]]$status, "exhausted")) {
    obj$entries[[i]]$status <- "exhausted"
    obj$entries[[i]]$exhausted_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    .rf_write(obj, layer, root)
  }
  invisible(obj$entries[[i]])
}

rf_mark_axis_epoch <- function(layer, epoch, legacy, reason, evidence, root = .rf_root()) {
  for (.a in list(epoch, legacy, reason, evidence))
    if (!nzchar(as.character(.a %||% "")))
      stop("[reinforce_ledger] 축 전환은 epoch/legacy/reason/evidence 전부 필수 — 근거 없이 무효화하지 않는다")
  obj <- rf_load(layer, root)
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  n_marked <- 0L
  for (i in seq_along(obj$entries)) {
    if (is.null(obj$entries[[i]]$measurement_axis)) {
      obj$entries[[i]]$measurement_axis <- legacy
      obj$entries[[i]]$axis_valid <- FALSE
      obj$entries[[i]]$axis_marked_at <- now
      n_marked <- n_marked + 1L
    }
  }
  obj$axis_epochs <- c(obj$axis_epochs %||% list(), list(list(
    epoch = epoch, legacy = legacy, switched_at = now,
    reason = reason, evidence = evidence, entries_marked = n_marked,
    note = paste0("이 시점 이후 개설되는 entry 는 measurement_axis='", epoch,
                  "' 로 태어난다. 축이 다른 entry 끼리는 등급·PORT_t 를 비교하지 않는다."))))
  obj$current_axis <- epoch
  .rf_write(obj, layer, root)
  cat(sprintf("[reinforce_ledger] 축 전환 %s -> %s · 과거 entry %d건 무효 표시
", legacy, epoch, n_marked))
  invisible(n_marked)
}

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

cat("[reinforce_ledger.R] Loaded (v10) — rf_open_entry / rf_append_attempt(★L1 25회 게이트·서술 의무 · root_papers 선택) / rf_record_result / rf_park_entry(조기 중단·사유 필수) / rf_record_judge / rf_record_combination_review / rf_lessons_digest\n")
