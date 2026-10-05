#==============================================================================
# rf_trial_producers.R — 시행 로그 생산자 공용 (P1-02 · O0a 2026-09-25 · 설계 organic_design_final §1.0(e) E3 · §3 G1 · 플랜 P1-02·P1-05)
#
# ★왜: 결정 생산자 7곳(블록 승자 · 바닥 · b1/b2/b5 pick · 승격 · 결합)은 이긴 선택만 남기고 후보·기각을 남기지 않았다(rf_decisions.jsonl 은
#   a_eligibility·direction 둘뿐). 칸마다 "어디서 온 설계인가"도 없었다 — 설계 파일 존재로 사후 도출하면 entry 단위가 돼, 설계 검증에
#   떨어져 규칙으로 폴백한 칸을 LLM 칸으로 센다(E3). 이 파일은 러너·이월·결합 스크립트가 **칸을 조립한 자리**에서 부르는 순수 판정 +
#   얇은 기록 호출(reinforce_ledger.R::rf_record_trial_decision · rf_trial_log_append)만 담는다.
# 계약:
#   · 칸 출처 = 조립 지점 표식(cell$design_origin) → 설계 출처 어휘(reinforce_ledger.R::RF_DESIGN_SOURCES). 표식 없음 = 격자.
#   · LLM B1 칸의 재료 노출은 **파일별로 도출**한다(설계 §0.2 사실 3): .cache/rf_b1_design/<BID[1:60]>.materials.txt 의 교차 entry 절을
#     B1 가림 계약(rf_b1_design_lib.R::rf_b1_has_stats — 정의 parse 추출 · 복제 금지)으로 판정 — 수치 잔존 = crossentry_exposed ·
#     절은 있고 수치 없음 = masked · 절 없음(교훈 없음 표지) = own_entry · 판독 불가·재료가 설계보다 새것 = unknown.
#     블록 설계 레인(B2/B3/B5)은 재료를 남기지 않는다 → llm_exposure_unknown(모르면 unknown — 청정 층에 넣지 않는다).
#   · 기록 실패는 러너를 세우지 않는다 — 호출부가 tryCatch 로 감싸 jlog("trial_log_failed") 를 남긴다(K2 감사가 조인 결손으로 잡는다).
#   · 이 파일은 측정·등급을 읽지 않는다(후보 피처 = 호출부가 넘긴 지표 값 · 등급 객체 금지는 writer 가 막는다).
#==============================================================================
## `%||%` — 호출자가 이미 둔 판(러너·이월·결합·사람 명령 스크립트 · 원장의 NA 처리판)을 덮지 않는다(O0a s2 · 2026-09-26): 이 파일이 전역에
##   source 되면 정의 한 줄이 호출자 함수 전부의 `%||%` 의미를 바꾼다(pi0 비트 동일 위협 — rf_combination_launch.R 는 전역 source).
##   보이는 판이 없거나 base 판(R ≥ 4.4 · NULL 만 대체)뿐일 때만 길이 0 도 대체하는 판을 이 파일 환경에 둔다.
if (!exists("%||%", mode = "function") || identical(environmentName(environment(`%||%`)), "base"))
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
RF_TP_B1_LIB <- "02_Infrastructure/ops/rf_b1_design_lib.R"
RF_TP_B1_DIR <- ".cache/rf_b1_design"
# 교차 entry 절·교훈 없음 표지 — rf_b1_design_lib.R::b1_materials 가 쓰는 머리글(아래 .rftp_contract 가 생산자 코드에 실재하는지 매 적재 재확인)
RF_TP_XENTRY_HDR <- "## 앞선 논문들에서 이미 배운 것"
RF_TP_OWN_HDR    <- "## 앞선 논문 교훈: 없음"
# 조립 지점 표식 → 설계 출처 · 레인
RF_TP_ORIGINS <- c("grid", "llm_b1", "llm_block", "standing", "rule_factor", "rule_factor_fallback", "rule_overlay", "rule_weight")

.rftp_s1 <- function(x) { x <- tryCatch(suppressWarnings(as.character(unlist(x %||% ""))), error = function(e) "")
  if (length(x) < 1L || is.na(x[1])) "" else trimws(x[1]) }
.RFTP <- new.env(parent = emptyenv())

#' B1 가림 계약 적재 — 생산자 파일에서 정의만 parse→eval(통째 source 금지: 머리의 source·전역 부작용). 머리글 계약도 여기서 확인.
.rftp_contract <- function(root) {
  key <- paste0("c|", root)
  if (!is.null(.RFTP[[key]])) return(.RFTP[[key]])
  p <- file.path(root, RF_TP_B1_LIB)
  out <- tryCatch({
    if (!file.exists(p)) stop("B1 lib 부재")
    ex <- parse(p, encoding = "UTF-8", keep.source = FALSE)
    env <- new.env(parent = baseenv())
    want <- c("RF_B1_STAT_PROTECT", "RF_B1_STAT_RULES", "RF_B1_STAT_METRIC", "RF_B1_STAT_MASK", "rf_b1_has_stats")
    for (e in as.list(ex)) if (is.call(e) && as.character(e[[1]])[1] %in% c("<-", "=") && is.name(e[[2]]) &&
                             as.character(e[[2]]) %in% want) eval(e, env)
    miss <- want[!vapply(want, exists, logical(1), envir = env, inherits = FALSE)]
    if (length(miss)) stop(sprintf("가림 계약 정의 부재: %s", paste(miss, collapse = ",")))
    src <- readLines(p, warn = FALSE, encoding = "UTF-8")
    hdr_ok <- any(grepl(RF_TP_XENTRY_HDR, src, fixed = TRUE)) && any(grepl(RF_TP_OWN_HDR, src, fixed = TRUE))
    list(ok = TRUE, env = env, header_ok = hdr_ok, why = if (hdr_ok) "" else "header_contract_missing")
  }, error = function(e) list(ok = FALSE, env = NULL, header_ok = FALSE, why = conditionMessage(e)))
  assign(key, out, envir = .RFTP)
  out
}

#' 재료 파일 1개의 교차 entry 노출 — list(exposure = crossentry_exposed|masked|own_entry|unknown, why, n_mask, materials)
rf_design_exposure <- function(materials, root, design_json = NULL) {
  u <- function(why) list(exposure = "unknown", why = why, n_mask = NA_integer_, materials = materials)
  if (!nzchar(.rftp_s1(materials)) || !file.exists(materials)) return(u("materials_absent"))
  if (!is.null(design_json) && file.exists(design_json) &&
      isTRUE(file.info(materials)$mtime > file.info(design_json)$mtime + 5))
    return(u("materials_newer_than_design"))       # 재료가 설계 뒤에 다시 쓰였다 — 이 설계를 낳은 재료라는 증명이 없다
  C <- .rftp_contract(root)
  if (!isTRUE(C$ok)) return(u(paste0("contract:", C$why)))
  if (!isTRUE(C$header_ok)) return(u("header_contract_missing"))
  L <- tryCatch(readLines(materials, warn = FALSE, encoding = "UTF-8"), error = function(e) NULL)
  if (is.null(L)) return(u("materials_unreadable"))
  i <- which(startsWith(L, RF_TP_XENTRY_HDR))
  if (length(i)) {
    nxt <- which(startsWith(L, "## ") & seq_along(L) > i[1])
    sec <- L[(i[1] + 1L):(if (length(nxt)) nxt[1] - 1L else length(L))]
    nm <- sum(lengths(regmatches(sec, gregexpr(C$env$RF_B1_STAT_MASK, sec, fixed = TRUE))))
    return(list(exposure = if (isTRUE(C$env$rf_b1_has_stats(sec))) "crossentry_exposed" else "masked",
                why = "section", n_mask = as.integer(nm), materials = materials))
  }
  if (any(startsWith(L, RF_TP_OWN_HDR))) return(list(exposure = "own_entry", why = "no_prior_lessons", n_mask = 0L, materials = materials))
  u("no_section_marker")
}

#' 칸 1개의 설계 출처 — 조립 지점 표식(design_origin)에서. 반환 = reinforce_ledger.R::rf_append_attempt(design=) · 시행 로그 cells 모양.
rf_cell_design_source <- function(cell, base_id, root) {
  og <- .rftp_s1(cell$design_origin); if (!nzchar(og)) og <- if (isTRUE(cell$standing)) "standing" else "grid"
  sb <- .rftp_s1(cell$selection_basis)
  ex <- NA_character_; mat <- ""
  ds <- switch(og,
    grid = if (identical(sb, "full_sample_ic")) "rule_full_ic" else "grid",
    standing = "standing",
    rule_factor = if (identical(sb, "asof_ic")) "rule_asof" else if (identical(sb, "full_sample_ic")) "rule_full_ic" else "unknown",
    rule_factor_fallback = "rule_full_ic",
    rule_overlay = "rule_catalog", rule_weight = "rule_catalog",
    llm_block = { ex <- "unknown"; "llm_exposure_unknown" },
    llm_b1 = {
      d <- file.path(root, RF_TP_B1_DIR)
      m <- file.path(d, sprintf("%s.materials.txt", substr(base_id, 1L, 60L)))
      j <- file.path(d, sprintf("%s.json", substr(base_id, 1L, 60L)))
      e <- rf_design_exposure(m, root, design_json = j); ex <- e$exposure
      mat <- if (startsWith(m, paste0(root, "/"))) substring(m, nchar(root) + 2L) else m
      switch(ex, crossentry_exposed = "llm_crossentry_exposed", masked = "llm_masked", own_entry = "llm_own_entry", "llm_exposure_unknown")
    },
    "unknown")
  out <- list(code = .rftp_s1(cell$code), design_source = ds, design_lane = og)
  if (!is.na(ex)) out$exposure <- ex
  if (nzchar(sb)) out$selection_basis <- sb
  if (nzchar(mat)) out$materials <- mat
  b <- .rftp_s1(cell$basis); if (nzchar(b)) out$basis <- substr(b, 1L, 160L)
  out
}
#' 표식 붙이기 — 이미 표식이 있으면 두지 않는다(조립 지점이 먼저 정한 값 우선)
rf_tp_tag <- function(cells, origin) lapply(cells, function(c) { if (!nzchar(.rftp_s1(c$design_origin))) c$design_origin <- origin; c })

#' 후보 목록 조립 — ids · (선택) 값 · (선택) 사유 → rank(값 내림차순 · 값 없으면 입력 순)
rf_tp_candidates <- function(ids, vals = NULL, reasons = NULL, extra_reason = character(0)) {
  ids <- as.character(ids); if (!length(ids)) return(list())
  o <- if (length(vals) == length(ids)) order(-replace(as.numeric(vals), !is.finite(as.numeric(vals)), -Inf)) else seq_along(ids)
  lapply(seq_along(o), function(r) { k <- o[r]
    c <- list(id = ids[k], rank = r, reason = if (length(reasons) == length(ids)) .rftp_s1(reasons[k]) else "")
    if (length(vals) == length(ids) && is.finite(as.numeric(vals[k]))) c$features <- list(value = as.numeric(vals[k]))
    c })
}

#' 기록 1건 — rf_record_trial_decision 을 부르고 decision_id 를 돌려준다(실패 = stop · 호출부가 감싼다)
rf_tp_record <- function(kind, base_id, candidates, chosen, rule_src, scope = list(), cells = list(), root) {
  r <- rf_record_trial_decision(kind, base_id, candidates, chosen, rule = list(src = rule_src), scope = scope, cells = cells, root = root)
  invisible(r$decision$decision_id)
}

#' P1-06 통제 칸 코드 — 정본 rf_runner_gates.R::rf_control_codes(격자 standing_cells[control]). 통제 칸은 c0→c1 에서 rf_candidates_keep 의
#'   control_cell 로 빠진다 — 그 사유를 '규약 자격 미달' 로 적지 않는다(10-03 시스템 렌즈). 함수가 없거나 실패 = 빈 집합(구판 거동).
RF_TP_WHY_CONTROL <- "통제 칸(P1-06 · 선정 후보 아님)"
.rftp_control_codes <- function(root) tryCatch(
  if (exists("rf_control_codes", mode = "function")) as.character(unlist(rf_control_codes(root))) else character(0),
  error = function(e) character(0))
#' 블록 승자 기록 — .winner_of 가 남긴 단계별 후보(c0 측정 · c1 규약 자격 · c2 적대검증 통과 · win 선택)에서 후보·기각 사유를 조립
rf_tp_winner <- function(base_id, block, note, consumed_by, root) {
  if (is.null(note) || !length(note$c0)) return(invisible(NULL))
  c0 <- note$c0; c1 <- note$c1 %||% character(0); c2 <- note$c2 %||% character(0)
  vals <- note$vals %||% numeric(0); names(vals) <- note$vcodes %||% character(0)
  ids <- unique(c(c2, setdiff(c1, c2), setdiff(c0, c1)))
  ctl <- .rftp_control_codes(root)
  why <- vapply(ids, function(i) if (i %in% c2) "" else if (i %in% ctl) RF_TP_WHY_CONTROL else if (i %in% c1) "적대검증 pass 아님(소비 보류)" else "후보 자격 미달(규약)", character(1))
  v <- vapply(ids, function(i) if (i %in% names(vals)) as.numeric(vals[[i]]) else NA_real_, numeric(1))
  ch <- .rftp_s1(note$chosen); if (!nzchar(ch) || !(ch %in% ids)) ch <- "none"
  rf_tp_record("block_winner", base_id, rf_tp_candidates(ids, v, why), ch,
               "02_Infrastructure/ops/reinforce_auto_parallel.R::.winner_of",
               scope = list(block = block, by = .rftp_s1(note$by), consumed_by = consumed_by), root = root)
}

#' 바닥 기록 — 단계별 후보(c0 측정 · c1 바닥 자격(규약·유니버스·창) · c2 적대검증 통과) + P0-10 carry 게이트 결과(src = attempt|carry|none)
rf_tp_floor <- function(base_id, note, src, code, gate_why, consumed_by, root) {
  note <- note %||% list()
  c0 <- note$c0 %||% character(0); c1 <- note$c1 %||% character(0); c2 <- note$c2 %||% character(0)
  vals <- note$vals %||% numeric(0); names(vals) <- note$vcodes %||% character(0)
  ids <- unique(c(c2, setdiff(c1, c2), setdiff(c0, c1)))
  ctl <- .rftp_control_codes(root)
  why <- vapply(ids, function(i) if (i %in% c2) "" else if (i %in% ctl) RF_TP_WHY_CONTROL else if (i %in% c1) "적대검증 pass 아님(소비 보류)" else "바닥 자격 미달(규약·유니버스·창)", character(1))
  v <- vapply(ids, function(i) if (i %in% names(vals)) as.numeric(vals[[i]]) else NA_real_, numeric(1))
  cands <- rf_tp_candidates(ids, v, why)
  src <- .rftp_s1(src)
  if (identical(src, "carry")) {
    cands <- c(list(list(id = "carry", rank = 0L, reason = paste0("P0-10 carry 기준선 게이트: ", .rftp_s1(gate_why)))), cands)
    ch <- "carry"
  } else ch <- if (identical(src, "attempt") && nzchar(.rftp_s1(code)) && .rftp_s1(code) %in% ids) .rftp_s1(code) else "none"
  rf_tp_record("floor", base_id, cands, ch, "02_Infrastructure/ops/reinforce_auto_parallel.R::바닥(.wbest_spec)+rf_floor_carry_gate",
               scope = list(block = "floor", by = "port_t", consumed_by = consumed_by, floor_source = src), root = root)
}

#' 픽 기록(b1_factor_pick · b2_weight_pick · b5_overlay_pick) — 선택 = 배치에 들어간 픽 · 기각 = 제외 목록(사유 붙임)
#' @param picked   선택 id(칸마다 1 — 팩터 집합 키 · 비중 label · 오버레이 arm id)
#' @param excluded list(<사유> = ids) — 이미 측정·carry·상주·IC 없음·축 제외 등
rf_tp_pick <- function(kind, base_id, picked, excluded = list(), batch = list(), rule_src, scope = list(), root) {
  picked <- unique(as.character(picked[nzchar(as.character(picked))]))
  ex_ids <- character(0); ex_why <- character(0)
  for (k in names(excluded)) { x <- setdiff(unique(as.character(unlist(excluded[[k]]))), c(picked, ex_ids)); x <- x[nzchar(x)]
    ex_ids <- c(ex_ids, x); ex_why <- c(ex_why, rep(k, length(x))) }
  cands <- c(lapply(seq_along(picked), function(i) list(id = picked[i], rank = i, reason = "배치 선택")),
             lapply(seq_along(ex_ids), function(i) list(id = ex_ids[i], rank = length(picked) + i, reason = ex_why[i])))
  cells <- lapply(batch, function(c) rf_cell_design_source(c, base_id, root))
  rf_tp_record(kind, base_id, cands, if (length(picked)) picked else "none", rule_src, scope = scope, cells = cells, root = root)
}
#' 칸 등록 기록 — 원장 등록이 성공한 칸만(n 확정 뒤). design = rf_cell_design_source 결과.
rf_tp_cell_registered <- function(base_id, n, design, block, root) {
  d <- design %||% list(); d$n <- as.integer(n)
  rf_trial_log_append("cell_registered", base_id, cells = list(d), src = "reinforce_auto_parallel",
                      scope = list(block = .rftp_s1(block)), root = root)
}
#' 팩터 집합 키 — 칸의 factors id 정렬 결합(러너 .done_fsets 와 같은 모양)
rf_tp_fset_key <- function(cell) {
  f <- cell$factors %||% list()
  if (!length(f)) f <- Filter(Negate(is.null), list(cell$factor2, cell$factor3))   # 구 격자 셀(factor2/3 단수)
  ids <- vapply(f, function(z) .rftp_s1(if (is.list(z)) z$id %||% z$kind else z), character(1))
  k <- paste(sort(ids[nzchar(ids)]), collapse = "+")
  if (nzchar(k)) k else paste0("cell:", .rftp_s1(cell$code))
}
