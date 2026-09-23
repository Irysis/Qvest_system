#==============================================================================
# rf_runner_gates.R — 러너 관문 술어 **정본** (WP-R · 2026-09-17 도훈 지시 · 횡단면 오버레이 축 강화)
#
# ★왜 파일로 뽑았나: 상주 칸 삽입·entry 예산 산식·적대검증 소비 술어·Grade A 보류는 전부 러너(main) 안의
#   분기다. 러너는 source 되는 순간 kill switch 를 보고 quit 하므로 검사가 그 분기를 **직접 부를 수 없다** —
#   인라인이면 검사는 소스 grep 으로 "줄이 있다" 만 재고 "판정이 옳다" 는 못 잰다.
#   rf_spec_sig.R · rf_avoid.R · rf_arm_compat.R 과 같은 형태: 판정은 여기(순수 함수), 부작용(원장·로그)은 러너.
#
# 제공: rf_b5_redesign_active / rf_standing_decision / rf_standing_cell / rf_b5_design_counts / rf_budget_auto /
#       rf_budget_want / rf_batch_open_slots / rf_adversary_ok / rf_grade_a_hold / rf_ov_txt
# 요구: rf_spec_sig.R(.rf_taken_codes · .ov_arm_ids · .ov_own_layers) · rf_block_design.R(rfbd_standing_cells · .rfbd_b5_raw)
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.RFG_ROOT <- function() Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
# ★층 정규화·상주 칸 읽기는 정본 하나만 — 러너 안에서는 이미 적재돼 있고, 단독 source(검사)면 여기서 적재한다.
if (!exists(".ov_arm_ids", mode = "function") || !exists(".rf_taken_codes", mode = "function"))
  source(file.path(.RFG_ROOT(), "02_Infrastructure/reinforcement/rf_spec_sig.R"), local = TRUE)
if (!exists("rfbd_standing_cells", mode = "function"))
  invisible(capture.output(source(file.path(.RFG_ROOT(), "02_Infrastructure/reinforcement/rf_block_design.R"), local = TRUE)))

#' B5 재설계 라운드가 열려 있는가 — 원장 entry$b5_redesign (B5 설계 레인 계약 2026-09-17).
#'   계약: {active: logical, round: integer(2 = 첫 재설계), at, cells_added: integer, base_design_cells: integer}.
#'   부재 또는 active != TRUE = 재설계 아님. (bare TRUE 도 열림으로 읽는다 — 관용)
rf_b5_redesign_active <- function(entry) {
  x <- entry$b5_redesign
  if (is.null(x)) return(FALSE)
  if (is.logical(x)) return(isTRUE(x[1]))
  is.list(x) && isTRUE(x$active)
}

#' 상주 칸을 이번 tick 의 격자에 얹는가 (도훈 지시 2026-09-17 · 상주 = 매 세대 B5 마다 도는 대조 칸)
#'   (a) 그 코드의 시도가 이미 있다 → 항상 얹는다(재개·소비 일관성 — 코드가 없으면 커서·승자 해석이 그 칸을 잃는다)
#'   (b) 이 entry 에 B5 시도가 아직 없고 ∧ arm 이 카탈로그 active ∧ carry$overlay 에 이미 없다 → 얹는다
#'   (c) 재설계 라운드가 열려 있고 그 코드의 시도가 없다 → 얹는다
#'   그 밖은 사유와 함께 건너뛴다(조용한 통과 없음).
#' @param sc 격자 standing_cells 원소 {code, block, label, overlay_pick}
#' @param catalog .rfbd_b5_raw(root) 형태 — [{id, kind, status, basis}] (status 보존본 · active 만 (b) 자격)
#' @return list(insert, reason, kind, basis)
rf_standing_decision <- function(sc, attempts, carry_overlay = NULL, catalog = list(), redesign_active = FALSE) {
  code <- as.character(sc$code %||% "")[1]; pick <- as.character(sc$overlay_pick %||% "")[1]
  blk  <- as.character(sc$block %||% "B5")[1]
  out  <- function(insert, reason, kind = "", basis = "") list(insert = insert, reason = reason, kind = kind, basis = basis)
  if (is.na(code) || !nzchar(code) || is.na(pick) || !nzchar(pick)) return(out(FALSE, "standing_cell_malformed"))
  hit <- Filter(function(x) identical(as.character(x$id %||% ""), pick), catalog %||% list())
  kind  <- if (length(hit)) as.character(hit[[1]]$kind %||% pick) else pick   # (a) 는 retired 여도 코드 유지 — kind 폴백
  basis <- if (length(hit)) as.character(hit[[1]]$basis %||% "") else ""
  active <- length(hit) && identical(as.character(hit[[1]]$status %||% "active"), "active")
  taken <- .rf_taken_codes(attempts %||% list())
  if (code %in% taken) return(out(TRUE, "attempt_exists", kind, basis))
  if (!active) return(out(FALSE, if (length(hit)) "arm_not_active" else "arm_not_in_catalog", kind, basis))
  if (pick %in% .ov_arm_ids(carry_overlay)) return(out(FALSE, "carry_has_arm", kind, basis))
  if (!any(startsWith(taken, paste0(blk, "_")))) return(out(TRUE, "first_b5_round", kind, basis))
  if (isTRUE(redesign_active)) return(out(TRUE, "redesign_round", kind, basis))
  out(FALSE, "b5_measured_no_redesign", kind, basis)
}

#' 상주 칸 → 러너 셀 (규칙 픽커·설계 소비와 같은 모양 · standing=TRUE 표식)
rf_standing_cell <- function(sc, kind, basis = "") {
  pick <- as.character(sc$overlay_pick %||% "")[1]
  list(code = as.character(sc$code)[1], label = as.character(sc$label %||% pick)[1],
       block = as.character(sc$block %||% "B5")[1], axis = "risk_overlay",
       overlay = list(kind = as.character(kind)[1], arm_id = pick),
       basis = sprintf("상주 칸(program standing_cells) · %s · %s", pick, substr(as.character(basis %||% ""), 1, 200)),
       standing = TRUE,
       note = "★상주 칸 — 설계·규칙 선정·회피 목록과 무관하게 매 세대 B5 에서 한 번 잰다(승격 carry 에는 안 실린다).")
}

#' B5 설계 칸 수 분해 — 예산 이중 계산 방지 (재설계 계약: 레인이 측정된 칸을 앞에 두고 새 칸을 **뒤에 덧붙인다**)
#'   재설계가 열려 있으면 base = base_design_cells(없으면 n_design − cells_added) · redesign = cells_added.
#'   닫혀 있으면 base = n_design(덧붙인 칸이 이미 설계 안에 있어 초과분으로 센다) · redesign = 0 — 두 상태의 합이 같아 예산이 요동하지 않는다.
rf_b5_design_counts <- function(n_design, entry) {
  n_design <- as.integer(n_design %||% 0L)
  if (!rf_b5_redesign_active(entry)) return(list(n_design = n_design, n_base = n_design, n_redesign = 0L))
  x <- if (is.list(entry$b5_redesign)) entry$b5_redesign else list()
  added <- suppressWarnings(as.integer(x$cells_added %||% 0L)); if (is.na(added) || added < 0L) added <- 0L
  base  <- suppressWarnings(as.integer(x$base_design_cells %||% NA_integer_))
  if (is.na(base) || base < 0L) base <- max(0L, n_design - added)
  list(n_design = n_design, n_base = base, n_redesign = added)
}

#' entry 자동 예산 = 기본 + B1 설계 초과 + B5 설계 초과 + 상주 삽입 + 재설계 추가 (도훈 2026-09-04 · 2026-09-17 확장)
#'   초과분만 더한다 — 설계가 5칸보다 적어도 예산을 깎지 않는다(격자 소진이 그 경우를 닫는다 · rf_grid_consumed).
#' @param slot_b1/slot_b5 격자 블록 칸 수(program blocks[].n — 하드코딩 금지)
rf_budget_auto <- function(base, n_b1_design = 0L, n_b5_design = 0L, n_standing = 0L, n_redesign = 0L,
                           slot_b1 = 5L, slot_b5 = 5L) {
  z <- function(v) { v <- suppressWarnings(as.integer(v %||% 0L)); if (length(v) != 1L || is.na(v)) 0L else v }
  z(base) + max(0L, z(n_b1_design) - z(slot_b1)) + max(0L, z(n_b5_design) - z(slot_b5)) + max(0L, z(n_standing)) + max(0L, z(n_redesign))
}
#' 실제 상한 = max(자동, 수동) — 수동으로 올린 예산은 덮지 않고(도훈 2026-09-17), 자동은 .auto 위로 못 올린다.
rf_budget_want <- function(auto, manual = NULL) {
  m <- suppressWarnings(as.integer(manual %||% 0L)); if (length(m) != 1L || is.na(m)) m <- 0L
  max(as.integer(auto), m)
}

#' 배치 안에서 규칙 픽커가 채울 자리 — 상주 칸은 자리를 내주지 않는다
rf_batch_open_slots <- function(batch) which(!vapply(batch %||% list(), function(c) isTRUE(c$standing), logical(1)))

#' 적대검증 소비 술어 — verdict 부재(구 attempt) 또는 pass 만 소비한다. fail/error/not_candidate = 보류.
#'   (rf_overlay_adversary.R 소비자 규약 · not_candidate = 바닥을 못 넘었거나 자기 층이 없던 칸)
rf_adversary_ok <- function(a) {
  v <- as.character((a$adversary %||% list())$verdict %||% "")[1]
  is.na(v) || !nzchar(v) || identical(v, "pass")
}

#' Grade A 보류 — B5 칸이 자기 오버레이 층을 갖는데 적대검증 pass 가 아직 없으면 judge/큐 발행을 미룬다.
#'   B5 가 아니거나 자기 층이 없으면(승계분만) 보류하지 않는다. spec 을 못 읽는 B5 칸은 보수적으로 보류(정직 결측).
rf_grade_a_hold <- function(code, spec, carry_overlay = NULL, attempt = NULL) {
  if (!startsWith(as.character(code %||% "")[1], "B5_")) return(FALSE)
  if (is.null(spec) || !is.list(spec)) return(TRUE)
  if (!length(.ov_own_layers(spec, carry_overlay))) return(FALSE)
  !identical(as.character((attempt$adversary %||% list())$verdict %||% "")[1], "pass")
}

#' 오버레이 스택 표기 — arm id 를 " × " 로 잇는다(단층·NULL 호환 · 로그·idea·사유 문자열 공용)
rf_ov_txt <- function(ov) { v <- .ov_arm_ids(ov); if (length(v)) paste(v, collapse = " \u00d7 ") else "none" }

# ── 시행 회계 (2026-09-23 · 강화 전수감사 D3-01 · 플랜 P0-01) ─────────────────────────────
#   구판은 강화 셀 전수를 chain·n_trials=1 로 채점했다(run_paper_replication.R 하드코딩 · 1,099/1,099 dsr=null).
#   러너는 열거 격자에서 전기간 지표 argmax 로 승자·바닥·승격을 고른다 = sweep(measurement-graduation §3 chain ② 미충족).
#   셀 spec 에 계보 누적 측정 시행수를 싣고 워커가 sweep 으로 넘긴다. 판정은 여기(순수), 부작용은 러너.

#' 계보 id 사슬 — 이 entry + parent 사슬(승격 carry 는 부모 승자를 물려받으므로 부모의 선택이 이 칸의 선택 이력이다).
#'   순환(자기 참조)·결손(부모 entry 부재)·깊이 가드. max_depth 는 폭주 방지선이지 연구 수치가 아니다(승격 깊이 상한보다 넉넉히).
rf_lineage_ids <- function(entries, bid, max_depth = 20L) {
  ids <- as.character(bid)[1]
  cur <- Filter(function(x) identical(x$base_id, ids[1]), entries %||% list())
  p <- if (length(cur)) as.character(cur[[1]]$parent$base_id %||% "")[1] else ""
  while (!is.na(p) && nzchar(p) && !(p %in% ids) && length(ids) <= max_depth) {
    ids <- c(ids, p)
    pe <- Filter(function(x) identical(x$base_id, p), entries)
    p <- if (length(pe)) as.character(pe[[1]]$parent$base_id %||% "")[1] else ""
  }
  ids
}

#' 계보 안 **측정된** 칸 수 — essence$port_t 가 유한 수치인 attempt 만 센다(미측정 NA 종결은 평가되지 않은 시행).
rf_lineage_measured <- function(entries, ids) {
  sum(vapply(Filter(function(x) x$base_id %in% ids, entries %||% list()), function(x)
    sum(vapply(x$attempts %||% list(), function(a) {
      v <- a$essence$port_t
      is.numeric(v) && length(v) == 1L && is.finite(v)
    }, logical(1))), numeric(1)))
}

#' 셀 spec 의 시행 회계 블록 — 등록 시점 값(도착 순서 의존). A 판정의 최종 가족 N 재산출은 A 서류(P1-04) 몫.
#'   ★.spec_sig 는 명시 키만 보므로 이 블록은 서명을 바꾸지 않는다(rf_spec_sig.R).
rf_selection_accounting <- function(ids, n_measured_prior, n_batch_reg) {
  list(selection_type = "sweep", family_root = tail(ids, 1L), lineage = ids,
       n_family_at_registration = as.integer(n_measured_prior + n_batch_reg),
       n_trials_basis = "lineage_measured_cells_at_registration")
}

if (sys.nframe() == 0L)
  cat("[rf_runner_gates.R] Loaded (WP-R) — rf_standing_decision / rf_budget_auto / rf_adversary_ok / rf_grade_a_hold / rf_ov_txt / rf_lineage_ids / rf_lineage_measured / rf_selection_accounting\n")
