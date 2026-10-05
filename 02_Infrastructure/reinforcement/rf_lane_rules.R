#==============================================================================
# rf_lane_rules.R — 유기체 밖 **사람 규칙** 순수 함수 정본 (2026-09-25 · 유기적 강화 설계 최종판 §1.1 '유기체 밖 사람 규칙' · §11)
#
# 무엇: 이미 결정된 고정 규칙 네 가지의 판정을 한 곳에 둔다. 판정은 여기(순수 함수), 부작용(원장·로그)은 호출자
#   (reinforce_auto_parallel.R · reinforce_auto_next_paper.R) — rf_runner_gates.R 과 같은 형태.
#   ① P1-08 FIFO(플랜 qvest-1-drifting-eclipse P1-08 · 감사 D2-12): 미이월 소진 entry 를 exhausted_at 오름차순으로 판정한다.
#      구판(next_paper :61-65)은 ex[[length(ex)]](LIFO)라 최고 계보 promo4 가 이틀째 요약·승격 판정을 못 받았다.
#   ② D-G 레인 순서(결정 D-G 2026-09-23): prereg > 신규 논문 > 승격 > 반사실 · 승격 세대당 신규 논문 ≥1.
#      priority(prereg/normal/idle_only)·experiment 는 원장 entry 필드(rf_open_entry — P1-08)다. 반사실(idle_only)은
#      개설을 막지 않는다(감사 D8-02: 반사실 active 1건이 신규 요청을 16시간 선점).
#   ③ B3-STRUCTURAL-TRIM(결정 2026-09-25 18:22): 격자 구조 상태(reinforce_program.json::structure_rules — 사람 소유)를
#      칸 목록에 적용한다. 불변식 ①(시도 있는 코드 보존) ③(B4 는 diag/dormant 블록을 참조하는 칸만 뺀다) ④(빈 칸이 남으면
#      used < 칸 수 — 어기면 항등) ⑤(B4 전 승자 결합 칸 보존)을 이 함수 안에서 다시 단언한다(설계 §0.2-4 · §1.1).
#   ④ D-G B5 적응 축소(결정 D-G · ORGANIC-DE Q②′(α) 고정 사람 규칙 예외 · N_program 계상): G2 유효 pass 0 ∧ compose_only
#      연속 라운드 ≥ K → B5 = 상주 + standing_plus 칸, pass 시 복원. 값 = reinforce_auto_config.json::b5_budget(사람 소유).
#
# ★성과 소비 구분: ①②③ 은 성과를 읽지 않는다(대기열 순서 · 구조 사실). ④ 만 전기간 적대검증(G2) 판정을 읽는다 — 그래서
#   유기체(as-of 가드) 안이 아니라 여기(유기체 밖 고정 규칙)에 있고, 결정 기록에 증거 칸 수(n_evidence)를 싣는다(N_program).
# ★하드코딩 없음: 레인 순서·우선순위 어휘·세대 하한·B5 축소 값은 전부 설정(lanes · b5_budget)에서 읽는다. 설정이 없거나
#   깨졌으면 규칙을 끄고(ok=FALSE) 호출자는 구판 거동으로 돈다 — 조용히 추정한 값으로 돌지 않는다.
# 요구: rf_spec_sig.R(.rf_attempt_code · .rf_taken_codes · .rf_free_cells) · jsonlite
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.RFLR_ROOT <- function() Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
if (!exists(".rf_taken_codes", mode = "function") || !exists(".rf_free_cells", mode = "function"))
  source(file.path(.RFLR_ROOT(), "02_Infrastructure/reinforcement/rf_spec_sig.R"), local = TRUE)

.rflr_s1 <- function(x) { v <- suppressWarnings(as.character(unlist(x %||% character(0)))); v <- v[!is.na(v)]
                          if (length(v)) v[1] else "" }
.rflr_chr <- function(x) { v <- suppressWarnings(as.character(unlist(x %||% character(0)))); v[!is.na(v) & nzchar(v)] }
#' ISO 시각(원장 형식 %Y-%m-%dT%H:%M:%S%z) → epoch 초. 판독 불가 = NA.
.rflr_time <- function(s) {
  s <- .rflr_s1(s); if (!nzchar(s)) return(NA_real_)
  t <- suppressWarnings(as.numeric(as.POSIXct(s, format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")))
  if (!length(t) || !is.finite(t)) {   # 콜론 있는 오프셋(+09:00 — 파이썬 isoformat) 폴백
    s2 <- sub("([+-][0-9]{2}):([0-9]{2})$", "\\1\\2", s)
    t <- suppressWarnings(as.numeric(as.POSIXct(s2, format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")))
  }
  if (length(t) && is.finite(t)) t else NA_real_
}

# ══ ② 레인 설정 ════════════════════════════════════════════════════════════════════════════════════
RFLR_LANES <- c("prereg", "new_paper", "promotion", "counterfactual")   # 레인 **이름표**(스키마) — 순서는 설정 lanes.order 가 정한다

#' 레인 설정 판독 — reinforce_auto_config.json::lanes. 깨졌으면 ok=FALSE(호출자 = 구판 거동).
#' @return list(ok, why, order, enum, nonblocking, priority_lane, min_new, attempt_statuses, inflight_statuses)
rf_lane_cfg <- function(cfg) {
  L <- if (is.list(cfg)) cfg$lanes else NULL
  bad <- function(why) list(ok = FALSE, why = why)
  if (!is.list(L)) return(bad("lanes_absent"))
  ord <- .rflr_chr(L$order); enum <- .rflr_chr(L$priority_enum); nb <- .rflr_chr(L$nonblocking_priorities)
  pl <- L$priority_lane %||% list()
  if (length(ord) != length(RFLR_LANES) || anyDuplicated(ord) || !setequal(ord, RFLR_LANES))
    return(bad(sprintf("lanes.order 는 %s 의 순열이어야 한다(값 %s)", paste(RFLR_LANES, collapse = ","), paste(ord, collapse = ","))))
  if (!("normal" %in% enum) || anyDuplicated(enum)) return(bad("lanes.priority_enum 에 normal 이 없거나 중복"))
  if (length(setdiff(nb, enum))) return(bad(sprintf("lanes.nonblocking_priorities ⊄ priority_enum (%s)", paste(setdiff(nb, enum), collapse = ","))))
  if (!is.list(pl) || length(setdiff(names(pl), enum))) return(bad("lanes.priority_lane 키가 priority_enum 밖"))
  plv <- vapply(names(pl), function(k) .rflr_s1(pl[[k]]), character(1))
  if (length(setdiff(plv[nzchar(plv)], RFLR_LANES))) return(bad("lanes.priority_lane 값이 레인 이름표 밖"))
  mn <- suppressWarnings(as.integer(L$min_new_papers_per_promotion_generation %||% NA))
  if (length(mn) != 1L || is.na(mn) || mn < 0L) return(bad("lanes.min_new_papers_per_promotion_generation 판독 불가"))
  list(ok = TRUE, why = "ok", order = ord, enum = enum, nonblocking = nb, priority_lane = as.list(plv), min_new = mn,
       attempt_statuses = .rflr_chr(L$request_attempt_statuses), inflight_statuses = .rflr_chr(L$request_inflight_statuses))
}

#' entry 우선순위 — 필드 부재(P1-08 이전 entry) = "normal".
rf_entry_priority <- function(e) { p <- .rflr_s1(e$priority); if (nzchar(p)) p else "normal" }
#' 사전등록 실험 entry — rf_open_entry(experiment=) 가 남긴 비어 있지 않은 목록.
rf_entry_is_experiment <- function(e) is.list(e$experiment) && length(e$experiment) > 0L
#' entry 레인 — priority 가 레인을 지정하면 그것(prereg · idle_only→counterfactual), 아니면 구조(부모 있음 = 승격 · 없음 = 신규 논문).
rf_entry_lane <- function(e, L) {
  if (isTRUE(L$ok)) { ln <- .rflr_s1(L$priority_lane[[rf_entry_priority(e)]]); if (nzchar(ln)) return(ln) }
  if (nzchar(.rflr_s1((e$parent %||% list())$base_id))) "promotion" else "new_paper"
}
#' 세대 하한이 세는 '신규 논문' — 신규 논문 레인 ∧ 결합 entry 아님(결합은 논문 착수가 아니다) ∧ 실험 아님.
rf_entry_is_new_paper <- function(e, L) identical(rf_entry_lane(e, L), "new_paper") && is.null(e$combo) && !rf_entry_is_experiment(e)

#' 러너가 돌릴 active entry 순서 — 레인 순위(lanes.order) → 원장 순서(안정). 실험 entry 는 제외한다: 사전등록 arm 의 칸은
#'   격자가 아니라 사전등록이 정한다 — 전용 실행기(P2 별판 · 현재 live 경로 없음 · prereg_config.run.live_enabled=false)가 맡는다.
#'   설정이 깨졌으면 구판 거동(원장 순서 그대로 · 제외 없음).
#' @return list(entries, lanes, ranks, excluded_experiment, ok)
rf_lane_select <- function(entries, L) {
  idx <- which(vapply(entries %||% list(), function(e) identical(.rflr_s1(e$status), "active"), logical(1)))
  act <- entries[idx]
  if (!isTRUE(L$ok)) return(list(entries = act, lanes = rep(NA_character_, length(act)), ranks = seq_along(act),
                                 excluded_experiment = character(0), ok = FALSE))
  ex <- vapply(act, rf_entry_is_experiment, logical(1))
  exid <- vapply(act[ex], function(e) .rflr_s1(e$base_id), character(1))
  act <- act[!ex]
  ln <- vapply(act, rf_entry_lane, character(1), L = L)
  rk <- match(ln, L$order); rk[is.na(rk)] <- length(L$order) + 1L
  o <- order(rk, seq_along(act))
  list(entries = act[o], lanes = ln[o], ranks = rk[o], excluded_experiment = exid, ok = TRUE)
}

#' 개설을 막는 active entry — 비차단 우선순위(lanes.nonblocking_priorities · 반사실)와 실험 entry 를 뺀 active.
#'   설정이 깨졌으면 구판 거동(active 전부가 막는다).
rf_blocking_active <- function(entries, L) {
  act <- Filter(function(e) identical(.rflr_s1(e$status), "active"), entries %||% list())
  if (!isTRUE(L$ok)) return(act)
  Filter(function(e) !rf_entry_is_experiment(e) && !(rf_entry_priority(e) %in% L$nonblocking), act)
}

# ══ ① P1-08 FIFO ═══════════════════════════════════════════════════════════════════════════════════
#' 미이월 소진 entry — exhausted_at 오름차순(동률·판독 불가는 원장 순서 · 판독 불가는 뒤로). 실험 entry 는 승격·요약에서 제외.
#'   FIFO 는 설정 값이 아니라 수리다(설정 없이도 선다).
#' @return list(entries, ids, skipped_experiment, time_unreadable)
rf_fifo_exhausted <- function(entries) {
  ix <- which(vapply(entries %||% list(), function(e) identical(.rflr_s1(e$status), "exhausted") && !isTRUE(e$handed_off), logical(1)))
  ex <- entries[ix]
  isx <- vapply(ex, rf_entry_is_experiment, logical(1))
  skipped <- vapply(ex[isx], function(e) .rflr_s1(e$base_id), character(1))
  ex <- ex[!isx]; ix <- ix[!isx]
  t <- vapply(ex, function(e) .rflr_time(e$exhausted_at), numeric(1))
  o <- order(is.na(t), t, ix)
  list(entries = ex[o], ids = vapply(ex[o], function(e) .rflr_s1(e$base_id), character(1)),
       skipped_experiment = skipped, time_unreadable = vapply(ex[is.na(t)], function(e) .rflr_s1(e$base_id), character(1)))
}

#' 승격 세대 하한 — 가장 최근 승격 자식의 개설 뒤 신규 논문 착수가 lanes.min_new_papers_per_promotion_generation 이상이어야
#'   다음 승격을 연다(D-G "승격 세대당 신규 논문 ≥1"). 착수 = 원장의 신규 논문 entry 개설(기저 관문 파킹 포함) + 그 뒤 발행돼
#'   entry 없이 끝난 충실구현 요청(request_attempt_statuses — 스킵리스트·재현 불가: 논문을 실제로 시도했다).
#' @param request 06_Registry/replication_request.json 내용(list) 또는 NULL
#' @return list(ok, applied, why, last_promotion, since, n_new_entries, n_request_attempts, need)
rf_generation_gate <- function(entries, L, request = NULL) {
  if (!isTRUE(L$ok)) return(list(ok = TRUE, applied = FALSE, why = paste0("lanes_cfg:", L$why %||% "absent")))
  pr <- Filter(function(e) nzchar(.rflr_s1((e$parent %||% list())$base_id)), entries %||% list())
  if (!length(pr)) return(list(ok = TRUE, applied = TRUE, why = "no_prior_promotion", need = L$min_new, n_new_entries = 0L))
  tp <- vapply(pr, function(e) .rflr_time(e$opened_at), numeric(1))
  if (all(is.na(tp))) return(list(ok = TRUE, applied = FALSE, why = "promotion_time_unreadable"))
  k <- which.max(replace(tp, is.na(tp), -Inf)); t0 <- tp[k]
  nn <- sum(vapply(entries %||% list(), function(e) {
    t <- .rflr_time(e$opened_at); rf_entry_is_new_paper(e, L) && is.finite(t) && t > t0 }, logical(1)))
  nr <- 0L
  if (is.list(request) && nn == 0L) {
    tr <- .rflr_time(request$requested_at)
    if (is.finite(tr) && tr > t0 && .rflr_s1(request$status) %in% L$attempt_statuses) nr <- 1L
  }
  list(ok = (nn + nr) >= L$min_new, applied = TRUE, why = if ((nn + nr) >= L$min_new) "satisfied" else "new_paper_first",
       last_promotion = .rflr_s1(pr[[k]]$base_id), since = .rflr_s1(pr[[k]]$opened_at),
       n_new_entries = as.integer(nn), n_request_attempts = as.integer(nr), need = L$min_new)
}

#' 충실구현 요청이 진행 중인가(대기·실행·세션 대기) — 반사실 양보 판정. 상태 어휘 = lanes.request_inflight_statuses.
rf_request_inflight <- function(request, L) is.list(request) && isTRUE(L$ok) && .rflr_s1(request$status) %in% L$inflight_statuses

# ══ ③ 격자 구조 상태 (B3-STRUCTURAL-TRIM) ═══════════════════════════════════════════════════════════════
RFLR_STRUCT_STATES <- c("diag", "dormant")   # 사람 구조 상태 어휘(설계 §1.4 full→reduced→diag/dormant 중 이 규칙이 쓰는 둘)

#' 구조 규칙 판독 — reinforce_program.json::structure_rules. 무효 규칙은 버리고 사유를 돌려준다(조용한 통과 없음).
#' @return list(rules = list(list(id, block, state, keep)), invalid = character, protected, combo_block)
rf_structure_rules <- function(PROG) {
  S <- PROG$structure_rules
  out <- list(rules = list(), invalid = character(0), protected = character(0), combo_block = "")
  if (!is.list(S)) return(out)
  out$protected <- .rflr_chr(S$protected_blocks); out$combo_block <- .rflr_s1(S$combo_block)
  ids <- vapply(PROG$blocks %||% list(), function(b) .rflr_s1(b$id), character(1))
  for (r in S$rules %||% list()) {
    rid <- .rflr_s1(r$id); b <- .rflr_s1(r$block); st <- .rflr_s1(r$state); keep <- .rflr_chr(r$keep_cells)
    bad <- function(w) out$invalid <<- c(out$invalid, sprintf("%s: %s", if (nzchar(rid)) rid else "(id 없음)", w))
    if (!(b %in% ids)) { bad(sprintf("블록 %s 없음", b)); next }
    if (b %in% out$protected || identical(b, out$combo_block)) { bad(sprintf("보호 블록 %s(휴면·축소 불가 — 09-04 지시)", b)); next }
    if (!(st %in% RFLR_STRUCT_STATES)) { bad(sprintf("state %s 어휘 밖", st)); next }
    codes <- vapply(PROG$blocks[[match(b, ids)]]$cells %||% list(), function(c) .rflr_s1(c$code), character(1))
    if (identical(st, "diag") && (!length(keep) || length(setdiff(keep, codes)))) { bad("diag 인데 keep_cells 가 비었거나 격자 밖"); next }
    if (identical(st, "dormant") && length(keep)) { bad("dormant 인데 keep_cells 가 있다"); next }
    out$rules[[length(out$rules) + 1L]] <- list(id = rid, block = b, state = st, keep = keep)
  }
  out
}

#' B4(결합 블록) 에서 뺄 칸 — 불변식 ③: combo.use 에 diag/dormant 블록이 든 칸만 · 불변식 ⑤: combo.use 가 가장 넓은 칸(전 승자 결합)은 보존.
#' @return list(drop, keep_widest)
rf_structure_combo_drop <- function(PROG, trimmed_blocks, combo_block) {
  ids <- vapply(PROG$blocks %||% list(), function(b) .rflr_s1(b$id), character(1))
  if (!nzchar(combo_block) || !(combo_block %in% ids) || !length(trimmed_blocks)) return(list(drop = character(0), keep_widest = character(0)))
  cc <- PROG$blocks[[match(combo_block, ids)]]$cells %||% list()
  use <- lapply(cc, function(c) .rflr_chr((c$combo %||% list())$use))
  w <- vapply(use, length, integer(1)); wide <- if (length(w)) which(w == max(w)) else integer(0)
  code <- vapply(cc, function(c) .rflr_s1(c$code), character(1))
  hit <- vapply(use, function(u) any(u %in% trimmed_blocks), logical(1))
  list(drop = code[hit & !(seq_along(cc) %in% wide)], keep_widest = code[wide])
}

#' 구조 상태를 이번 tick 의 칸 목록에 적용 — 설계 적용·상주 삽입 **뒤**(최종 칸 목록 · 러너 상주 칸 삽입 끝).
#'   · 절단 전 계획으로 진입한 블록(keep·결합 보존 칸 **밖** 코드에 시도가 있다)은 동결 — 손대지 않는다(불변식 ② 동형 ·
#'     진행 중 entry 의 계획을 바꾸지 않는다). 절단된 계획으로 진입한 블록은 계속 절단 상태다(동결 판정이 절단 칸을 되살리지 않게).
#'   · 미진입 diag 블록: 그 블록 칸 = 격자의 keep_cells(설계가 그 블록을 통째로 갈았어도 격자 진단 칸으로 되돌린다).
#'   · 미진입 결합 블록: rf_structure_combo_drop 의 칸을 뺀다.
#'   · 불변식 ①: 시도가 있는 코드는 어떤 경우에도 빼지 않는다.
#'   · 불변식 ④: 결과에 빈 칸이 남는데 used ≥ 칸 수면 **항등**(정지 방지) — 사유 inv4.
#'   · 불변식 ⑤: 원래 목록에 있던 전 승자 결합 칸이 결과에 없으면 항등 — 사유 inv5.
#' @return 칸 목록(attr "structure_trim" = list(applied, removed, inserted, frozen, reason, invalid))
rf_structure_cells <- function(cells, E, PROG) {
  S <- rf_structure_rules(PROG)
  info <- list(applied = FALSE, removed = character(0), inserted = character(0), frozen = character(0),
               reason = "no_rules", invalid = S$invalid, rules = vapply(S$rules, function(r) r$id, character(1)))
  ret <- function(x, inf) { attr(x, "structure_trim") <- inf; x }
  if (!length(S$rules)) return(ret(cells, info))
  att <- E$attempts %||% list()
  taken <- .rf_taken_codes(att)
  blk <- function(c) .rflr_s1(c$block); code <- function(c) .rflr_s1(c$code)
  ids <- vapply(PROG$blocks %||% list(), function(b) .rflr_s1(b$id), character(1))
  out <- cells; trimmed <- character(0)
  for (r in S$rules) {
    trimmed <- c(trimmed, r$block)               # 결합 칸 판정은 상태로 한다(이 entry 의 그 블록이 동결이어도 — 불변식 ③ 문언)
    ## ★동결 = 절단 전 계획으로 이미 들어간 블록 — 남길 칸(keep) 밖의 코드에 시도가 있다(불변식 ② · 첫 시도 tick 의 계획 유지).
    ##   절단된 계획으로 들어간 블록(시도가 keep 코드뿐)은 동결이 아니다 — 그걸 동결로 보면 다음 tick 에 절단 칸이 되살아난다.
    if (length(setdiff(taken[startsWith(taken, paste0(r$block, "_"))], r$keep))) { info$frozen <- c(info$frozen, r$block); next }
    inb <- which(vapply(out, function(c) identical(blk(c), r$block), logical(1)))
    keep_cells <- list()
    if (identical(r$state, "diag")) {
      g <- PROG$blocks[[match(r$block, ids)]]
      keep_cells <- lapply(Filter(function(c) code(c) %in% r$keep, g$cells %||% list()), function(c) {
        c$block <- r$block; c$axis <- .rflr_s1(g$axis); c })
    }
    rm_codes <- setdiff(vapply(out[inb], code, character(1)), c(r$keep, taken))
    info$removed <- c(info$removed, rm_codes)
    have <- vapply(out[inb], code, character(1))
    ins <- Filter(function(c) !(code(c) %in% have), keep_cells)
    info$inserted <- c(info$inserted, vapply(ins, code, character(1)))
    keepers <- c(Filter(function(c) !(code(c) %in% rm_codes), out[inb]), ins)
    if (length(inb)) pos <- inb[1] else {          # 블록 칸이 목록에 없으면 격자 순서상 다음 블록의 첫 칸 앞(없으면 끝)
      nxt <- ids[seq_along(ids) > match(r$block, ids)]
      k <- which(vapply(out, function(c) blk(c) %in% nxt, logical(1)))
      pos <- if (length(k)) k[1] else length(out) + 1L
    }
    rest <- out[setdiff(seq_along(out), inb)]
    out <- append(rest, keepers, after = pos - 1L)
  }
  cb <- S$combo_block
  cd <- if (nzchar(cb)) rf_structure_combo_drop(PROG, unique(trimmed), cb) else list(drop = character(0), keep_widest = character(0))
  if (nzchar(cb) && !length(intersect(cd$drop, taken))) {   # 결합 블록 동결 = 뺄 칸 중 하나라도 시도가 있다(절단 전 계획으로 진입)
    drop <- setdiff(cd$drop, taken)
    if (length(drop)) {
      info$removed <- c(info$removed, intersect(drop, vapply(out, code, character(1))))
      out <- Filter(function(c) !(identical(blk(c), cb) && code(c) %in% drop), out)
    }
    wide0 <- intersect(cd$keep_widest, vapply(cells, code, character(1)))
    if (length(setdiff(wide0, vapply(out, code, character(1))))) {
      info$reason <- "inv5_identity"; return(ret(cells, info)) }
  } else if (nzchar(cb)) info$frozen <- c(info$frozen, cb)
  lost <- setdiff(intersect(taken, vapply(cells, code, character(1))), vapply(out, code, character(1)))
  if (length(lost)) { info$reason <- "inv1_identity"; info$lost <- lost; return(ret(cells, info)) }   # 시도 코드가 목록에서 빠졌다 — 방어적 재확인
  used <- suppressWarnings(as.integer(E$attempts_used %||% length(att))); if (is.na(used)) used <- length(att)
  free <- .rf_free_cells(out, att)
  if (length(free) && used >= length(out)) { info$reason <- "inv4_identity"; return(ret(cells, info)) }
  info$applied <- length(info$removed) > 0L || length(info$inserted) > 0L
  info$reason <- if (info$applied) "applied" else if (length(info$frozen)) "frozen" else "noop"
  ret(out, info)
}

# ══ ④ D-G B5 적응 축소 ════════════════════════════════════════════════════════════════════════════════
#' b5_budget 설정 판독 — 값이 하나라도 판독 불가면 ok=FALSE(규칙 꺼짐 · 호출자는 항등).
rf_b5_budget_cfg <- function(cfg) {
  B <- if (is.list(cfg)) cfg$b5_budget else NULL
  if (!is.list(B)) return(list(ok = FALSE, why = "b5_budget_absent", enabled = FALSE))
  en <- B$enabled; sp <- suppressWarnings(as.integer(B$standing_plus %||% NA)); k <- suppressWarnings(as.integer(B$compose_only_consecutive_rounds %||% NA))
  rs <- B$restore_on_g2_pass
  if (!(is.logical(en) && length(en) == 1L && !is.na(en))) return(list(ok = FALSE, why = "b5_budget.enabled 논리값 아님", enabled = FALSE))
  if (length(sp) != 1L || is.na(sp) || sp < 0L) return(list(ok = FALSE, why = "b5_budget.standing_plus 판독 불가", enabled = FALSE))
  if (length(k) != 1L || is.na(k) || k < 1L) return(list(ok = FALSE, why = "b5_budget.compose_only_consecutive_rounds 판독 불가", enabled = FALSE))
  if (!(is.logical(rs) && length(rs) == 1L && !is.na(rs))) return(list(ok = FALSE, why = "b5_budget.restore_on_g2_pass 논리값 아님", enabled = FALSE))
  list(ok = TRUE, why = "ok", enabled = isTRUE(en), standing_plus = sp, k = k, restore = isTRUE(rs))
}

#' G2 pass 가 유효한가 — 표식 칸의 pass 는 세지 않는다. 표식 필터는 A 자격 관문과 **같은 설정**(a_eligibility_gate.json::
#'   vintage_flag 의 flags·verdicts — rf_a_gate_config)을 쓴다: 그 관문이 A 로 소비하지 않을 칸이면 여기서도 증거가 아니다.
.rflr_flag_hit <- function(fl, G) {
  if (!is.list(fl) || !length(fl)) return(FALSE)
  flags <- .rflr_chr(G$vintage_flags); verd <- .rflr_chr(G$vintage_verdicts)
  if (!length(flags)) flags <- "*"                                           # 설정을 못 읽으면 보수(아무 표식이나 무효)
  any(vapply(fl, function(z) { f <- .rflr_s1(z$flag); v <- .rflr_s1(z$verdict)
    nzchar(f) && ("*" %in% flags || f %in% flags) && (!length(verd) || v %in% verd) }, logical(1)))
}

#' D-G B5 축소 판정 — (compose_only 연속 라운드 ≥ K) ∧ (그 연속 구간 시작 뒤 유효 G2 pass 0) → active.
#'   라운드 = 원장 entry$b5_design$rounds(전 entry · at 시각순 · B5 설계 레인이 쓴다). 'compose_only 지속' 은 stagnation_window 와
#'   단위가 다르다(그 창은 arm 을 낸 라운드만 센다 — rf_b5_design_lib.R H3) — 그래서 별도 키 compose_only_consecutive_rounds.
#'   복원 = 그 구간에서 유효 G2 pass 1건 이상 또는 compose_only 가 아닌 라운드(연속이 끊김).
#' @param G A 관문 설정(rf_a_gate_config) — 표식 필터 · NULL 이고 gate_fn 도 없으면 보수 필터(아무 표식이나 무효)
#' @param gate_fn G 를 늦게 읽는 함수(구간 안 pass 가 실제로 있을 때만 부른다 — 매 tick 관문 설정 판독을 피한다)
#' @return list(active, why, run_len, run_start, n_valid_pass, n_pass_flagged, n_evidence, standing_plus, k)
rf_b5_budget_decide <- function(entries, cfg, G = NULL, gate_fn = NULL) {
  B <- rf_b5_budget_cfg(cfg)
  base <- list(active = FALSE, why = B$why, run_len = 0L, run_start = "", n_valid_pass = 0L, n_pass_flagged = 0L, n_evidence = 0L,
               standing_plus = B$standing_plus %||% NA_integer_, k = B$k %||% NA_integer_)
  if (!isTRUE(B$ok)) return(base)
  if (!isTRUE(B$enabled)) { base$why <- "disabled"; return(base) }
  rr <- list()
  for (e in entries %||% list()) for (r in ((e$b5_design %||% list())$rounds %||% list())) if (is.list(r))
    rr[[length(rr) + 1L]] <- list(t = .rflr_time(r$at), at = .rflr_s1(r$at), co = isTRUE(r$compose_only))
  rr <- Filter(function(z) is.finite(z$t), rr)
  if (!length(rr)) { base$why <- "no_rounds"; return(base) }
  rr <- rr[order(vapply(rr, function(z) z$t, numeric(1)))]
  co <- vapply(rr, function(z) z$co, logical(1))
  run <- 0L; for (i in rev(seq_along(co))) { if (co[i]) run <- run + 1L else break }
  base$run_len <- run
  if (run < B$k) { base$why <- "compose_only_run_short"; return(base) }
  t0 <- rr[[length(rr) - run + 1L]]$t; base$run_start <- rr[[length(rr) - run + 1L]]$at
  nv <- 0L; nf <- 0L; ne <- 0L
  for (e in entries %||% list()) for (a in e$attempts %||% list()) {
    cd <- tryCatch(.rf_attempt_code(a), error = function(z) NA_character_)
    if (is.na(cd) || !startsWith(cd, "B5_")) next
    v <- .rflr_s1((a$adversary %||% list())$verdict); if (!nzchar(v)) next
    ne <- ne + 1L
    if (!identical(v, "pass")) next
    ta <- .rflr_time((a$adversary %||% list())$recorded_at %||% (a$adversary %||% list())$at)
    if (!is.finite(ta) || ta < t0) next
    if (is.null(G) && is.function(gate_fn)) G <- tryCatch(gate_fn(), error = function(z) list())
    if (.rflr_flag_hit(a$vintage_flags, G %||% list())) nf <- nf + 1L else nv <- nv + 1L
  }
  base$n_valid_pass <- nv; base$n_pass_flagged <- nf; base$n_evidence <- ne
  if (nv > 0L && isTRUE(B$restore)) { base$why <- "g2_pass_restore"; return(base) }
  base$active <- TRUE; base$why <- "g2_pass0_compose_only_run"
  base
}

#' D-G 축소를 칸 목록에 적용 — B5 칸 = 상주 칸 전부 + 비상주 앞 standing_plus 칸(설계·격자 순서 = 결정론).
#'   축소 전 계획으로 진입한 B5(남길 칸 밖 B5 코드에 시도)는 동결. 불변식 ①④ 재단언(어기면 항등).
#' @return 칸 목록(attr "b5_budget" = list(applied, removed, reason))
rf_b5_budget_cells <- function(cells, E, dec) {
  info <- list(applied = FALSE, removed = character(0), reason = "inactive")
  ret <- function(x) { attr(x, "b5_budget") <- info; x }
  if (!isTRUE(dec$active)) return(ret(cells))
  att <- E$attempts %||% list(); taken <- .rf_taken_codes(att)
  code <- function(c) .rflr_s1(c$code)
  b5 <- which(vapply(cells, function(c) identical(.rflr_s1(c$block), "B5"), logical(1)))
  if (!length(b5)) { info$reason <- "no_b5_cells"; return(ret(cells)) }
  st <- b5[vapply(cells[b5], function(c) isTRUE(c$standing), logical(1))]
  ns <- setdiff(b5, st)
  keep_ns <- utils::head(ns, dec$standing_plus)
  keep_codes <- vapply(cells[c(st, keep_ns)], code, character(1))
  ## ★동결 = 축소 전 계획으로 이미 들어간 B5 — 남길 칸 밖 B5 코드에 시도가 있다(불변식 ②). 축소 계획으로 들어간 B5 는 계속 축소.
  if (length(setdiff(taken[startsWith(taken, "B5_")], keep_codes))) { info$reason <- "b5_entered_frozen"; return(ret(cells)) }
  rm <- setdiff(ns, keep_ns)
  rm <- rm[!(vapply(cells[rm], code, character(1)) %in% taken)]
  if (!length(rm)) { info$reason <- "within_budget"; return(ret(cells)) }
  out <- cells[setdiff(seq_along(cells), rm)]
  used <- suppressWarnings(as.integer(E$attempts_used %||% length(att))); if (is.na(used)) used <- length(att)
  if (length(.rf_free_cells(out, att)) && used >= length(out)) { info$reason <- "inv4_identity"; return(ret(cells)) }
  info$applied <- TRUE; info$removed <- vapply(cells[rm], code, character(1)); info$reason <- "applied"
  ret(out)
}

#' 블록별 칸 수 — 예산 재도출(rf_budget_auto n_b5_cells)이 **최종 칸 목록**에서 센다(설계 칸 수가 아니라).
rf_block_cell_count <- function(cells, block) sum(vapply(cells %||% list(), function(c) identical(.rflr_s1(c$block), block), logical(1)))

if (sys.nframe() == 0L)
  cat("[rf_lane_rules.R] Loaded — rf_lane_cfg / rf_lane_select / rf_blocking_active / rf_fifo_exhausted / rf_generation_gate / rf_request_inflight /",
      "rf_structure_rules / rf_structure_combo_drop / rf_structure_cells / rf_b5_budget_cfg / rf_b5_budget_decide / rf_b5_budget_cells / rf_block_cell_count\n")
