#==============================================================================
# rf_runner_gates.R — 러너 관문 술어 **정본** (WP-R · 2026-09-17 도훈 지시 · 횡단면 오버레이 축 강화)
#
# ★왜 파일로 뽑았나: 상주 칸 삽입·entry 예산 산식·적대검증 소비 술어·Grade A 보류는 전부 러너(main) 안의
#   분기다. 러너는 source 되는 순간 kill switch 를 보고 quit 하므로 검사가 그 분기를 **직접 부를 수 없다** —
#   인라인이면 검사는 소스 grep 으로 "줄이 있다" 만 재고 "판정이 옳다" 는 못 잰다.
#   rf_spec_sig.R · rf_avoid.R · rf_arm_compat.R 과 같은 형태: 판정은 여기(순수 함수), 부작용(원장·로그)은 러너.
#
# 제공: rf_b5_redesign_active / rf_standing_decision / rf_standing_cell / rf_b5_design_counts / rf_budget_auto /
#       rf_budget_want / rf_batch_open_slots / rf_adversary_ok · rf_adversary_status(P0-11) / rf_adversary_rerun_blocks(I2) /
#       rf_grade_a_hold / rf_ov_txt /
#       시행 회계(rf_lineage_ids · rf_lineage_measured · rf_selection_accounting) /
#       ★P0-10·12·규약 혼합 가드(2026-09-24): rf_current_regime · rf_runner_ctx · rf_candidate_facts · rf_candidates_keep ·
#       rf_verified_layer_keys · rf_a_gate_config · rf_a_ctx · rf_a_eligibility · rf_parent_best_attempt · rf_carry_base_info ·
#       rf_carry_floor_spec · rf_floor_carry_gate
#       ★P0-14(2026-09-25): rf_a_eligibility ⑤ 가 원장 표식 + **관문 시점 재도출**(rf_lineage_flags.R::rflf_gate_flags — 계보 선정 기저 승계 ·
#       C11 격리)을 함께 본다. 수집 시점 새 칸은 원장 표식이 없다(표식은 사후) — 같은 사실을 관문이 스스로 재도출한다.
#       ★AUTOMEM(2026-09-26 · 결정 AUTOMEM-EXPOSED-CELLS-DISPOSITION · B5FIX-CONSUME-HOLD · FA-CLEAN-BASE-PATH 조정): ⑤ 가 entry **기저** 표식 중
#       설정 vintage_flag.entry_base_flags 에 든 것을 그 entry·계보(부모 사슬)·같은 엔진 경로·같은 엔진 내용(md5) entry 의 칸에 건다 —
#       **A 보류만**(소비 술어 rf_candidate_facts 는 attempt 표식만 읽는다 → 기저 노출 entry 도 연구는 계속). 청정 출처(lane_provenance ·
#       설정 entry_base_clean 소비 규칙) 엔진은 계보·경로 전파에서 뺀다. 목록 밖 기저 표식(fdb_* 등)은 구판처럼 칸으로 번지지 않는다.
#       ★P1-06(2026-09-25 스테이징 · 통제 칸): rf_control_codes · rf_is_control · rf_control_exempt · rf_control_cell · rf_control_plan ·
#       rf_control_insert · rf_cell_vintage · rf_series_compare · rf_carry_replay_check(E3) · rf_carry_base_resolve · rf_null_dilution_values —
#       통제 칸은 모든 소비 역할(승자·바닥·carry 부모·승격·A·N)에서 빠진다(rf_candidate_facts 머리 · rf_a_eligibility always-on control_cell ·
#       rf_lineage_measured exclude_codes).
# 요구: rf_spec_sig.R(.rf_taken_codes · .ov_arm_ids · .ov_own_layers) · rf_block_design.R(rfbd_standing_cells · .rfbd_b5_raw · rfbd_control_cells) ·
#       rf_lineage_flags.R(P0-14 · 계보 표식 술어 정본 — P0-08 derive 와 같은 함수) ·
#       reinforce_ledger.R(.rf_regime_key — regime 해석 정본) · 설정: 02_Infrastructure/worktask/constraint_defaults.json
#       (execution.exec_price · diagnostics.window_*) · 06_Registry/a_eligibility_gate.json(A 보류 코드 on/off)
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.RFG_ROOT <- function() Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
# ★스펙 축 등록부 정본(결정 B4-SIX-AXIS-AND-CARRY-AXES · 2026-09-26) — carry 바닥 스펙(rf_carry_floor_spec)과 러너 누적·carry 병합·B4 승자/조립·
#   결합 칸 재도출·격자 기본 예산이 이 표에서 파생된다. 부재 = 적재 실패(러너는 source 실패로 멈춘다 — 축 없이 조용히 도는 판 금지).
if (!exists("rf_axes", mode = "function"))
  source(file.path(.RFG_ROOT(), "02_Infrastructure/reinforcement/rf_spec_axes.R"), local = TRUE)
# ★층 정규화·상주 칸 읽기는 정본 하나만 — 러너 안에서는 이미 적재돼 있고, 단독 source(검사)면 여기서 적재한다.
if (!exists(".ov_arm_ids", mode = "function") || !exists(".rf_taken_codes", mode = "function"))
  source(file.path(.RFG_ROOT(), "02_Infrastructure/reinforcement/rf_spec_sig.R"), local = TRUE)
if (!exists("rfbd_standing_cells", mode = "function") || !exists("rfbd_control_cells", mode = "function"))
  invisible(capture.output(source(file.path(.RFG_ROOT(), "02_Infrastructure/reinforcement/rf_block_design.R"), local = TRUE)))
# ★P0-14 계보 표식 술어 정본 — 관문 ⑤ 재도출(선정 기저 승계 · C11 격리). 파일 부재 = 적재 실패(러너는 source 실패로 멈춘다 ·
#   충실구현 어댑터는 gate_error 보류) — 조용히 재도출 없이 도는 판이 생기지 않게 조건부 적재를 하지 않는다.
if (!exists("rflf_gate_flags", mode = "function"))
  invisible(capture.output(source(file.path(.RFG_ROOT(), "02_Infrastructure/reinforcement/rf_lineage_flags.R"), local = TRUE)))
# ★유기체 밖 사람 규칙 정본(2026-09-25 · 설계 최종판 §1.1·§11 — D-G 레인·세대 하한 · P1-08 FIFO · B3-STRUCTURAL-TRIM · D-G B5 축소).
#   러너·next_paper 가 이 파일을 통해 받는다. 부재 = 적재 실패(러너는 source 실패로 멈춘다 — 규칙 없이 조용히 도는 판 금지).
if (!exists("rf_lane_select", mode = "function"))
  invisible(capture.output(source(file.path(.RFG_ROOT(), "02_Infrastructure/reinforcement/rf_lane_rules.R"), local = TRUE)))

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
#' ★가산 차단 (D-G 이행 · 레버 감사 ④-3 · 2026-09-25): n_b5_cells(최종 칸 목록의 B5 칸 수 — 설계·상주·재설계·D-G 축소를 **다
#'   적용한 뒤** 센 값)가 오면 B5 몫 = max(0, n_b5_cells − slot_b5) 하나다. 구판 산식은 상주·재설계 추가를 B5 가 슬롯 안이어도
#'   무조건 더했고(설계 3칸 + 상주 1 = 4칸인데 +1), D-G 축소로 빠진 칸도 설계 칸 수로 다시 더했다(축소분 재가산). 러너는
#'   n_b5_cells 를 넘긴다. 인자가 없으면 구판 산식(검사·구 호출 호환) — 두 산식은 설계 ≥ 슬롯일 때 같은 값이다.
#'   ★예산 숫자는 올리기만 한다(rf_budget_want 의 max) — 내리면 used ≥ MAXA 로 뒤 블록(B4 전 승자 결합)이 잘린다(불변식 ⑤).
#'   축소는 격자 소진(rf_grid_consumed)으로 실현된다(설계 §1.1 '예산 숫자는 건드리지 않는다').
#' @param slot_b1/slot_b5 격자 블록 칸 수(program blocks[].n — 하드코딩 금지)
rf_budget_auto <- function(base, n_b1_design = 0L, n_b5_design = 0L, n_standing = 0L, n_redesign = 0L,
                           slot_b1 = 5L, slot_b5 = 5L, n_b5_cells = NULL, n_b1_cells = NULL) {
  z <- function(v) { v <- suppressWarnings(as.integer(v %||% 0L)); if (length(v) != 1L || is.na(v)) 0L else v }
  b5 <- if (!is.null(n_b5_cells)) max(0L, z(n_b5_cells) - z(slot_b5))
        else max(0L, z(n_b5_design) - z(slot_b5)) + max(0L, z(n_standing)) + max(0L, z(n_redesign))
  b1 <- if (!is.null(n_b1_cells)) max(0L, z(n_b1_cells) - z(slot_b1)) else max(0L, z(n_b1_design) - z(slot_b1))
  z(base) + b1 + b5
}
#' 실제 상한 = max(자동, 수동) — 수동으로 올린 예산은 덮지 않고(도훈 2026-09-17), 자동은 .auto 위로 못 올린다.
rf_budget_want <- function(auto, manual = NULL) {
  m <- suppressWarnings(as.integer(manual %||% 0L)); if (length(m) != 1L || is.na(m)) m <- 0L
  max(as.integer(auto), m)
}

#' 배치 안에서 규칙 픽커가 채울 자리 — 상주 칸은 자리를 내주지 않는다
rf_batch_open_slots <- function(batch) which(!vapply(batch %||% list(), function(c) isTRUE(c$standing), logical(1)))

#' 적대검증 소비 술어 — pass 만 소비한다. fail/error/not_candidate/deferred_refresh_lock = 보류.
#'   (rf_overlay_adversary.R 소비자 규약 · not_candidate = 바닥을 못 넘었거나 자기 층이 없던 칸)
#' ★P0-11 (2026-09-24 · 도훈 승인 플랜 qvest-1-drifting-eclipse · 감사 D6-09): 구판은 verdict **부재**를 통과로 읽었다(구 attempt
#'   호환). 그런데 부재의 대부분은 '검증 전'이 아니라 '검증 대상이었던 적 없음'이다 — G2(2026-09-17) 이전 B5 칸 전부와 적대검증이
#'   돌지 않은 칸. 그 칸이 바닥·carry·승자·A 로 소비되면 동월 누출 여부를 모르는 오버레이가 다음 세대의 바닥이 된다
#'   (프로그램 최고 Calmar 칸 B5_19 0.609 가 verdict 없이 계보 최고로 인용됐다). 그래서:
#'     · verdict 가 있으면 pass 만 TRUE (구판과 같다).
#'     · verdict 가 없고 **자기 오버레이 층이 있는 B5 칸**(.ov_own_layers)이면 'unverified' → FALSE.
#'       spec 을 못 읽는 B5 칸도 'unverified'(자기 층 유무를 모른다 — 정직 결측 · rf_grade_a_hold 와 같은 보수).
#'     · 그 밖(B1~B4·B6·B7 · 코드 없는 구 attempt · 자기 층 없는 B5)은 현행대로 TRUE.
#' @param carry_overlay entry$carry$overlay(선택) — overlay_cell 이 없는 구 스펙에서 자기 층 = overlay − carry 로 가른다.
#'   NULL 이면 overlay 전부를 자기 층으로 본다(.ov_own_layers 의 보수 폴백 — 과대 귀속 = 보류 쪽).
#' @param spec 셀 스펙(선택) — NULL 이면 a$essence$spec 경로에서 읽는다.
rf_adversary_status <- function(a, carry_overlay = NULL, spec = NULL) {
  v <- as.character((a$adversary %||% list())$verdict %||% "")[1]
  if (!is.na(v) && nzchar(v)) return(list(ok = identical(v, "pass"), status = v, detail = ""))
  code <- tryCatch(.rf_attempt_code(a), error = function(e) NA_character_)
  if (is.na(code) || !startsWith(code, "B5_")) return(list(ok = TRUE, status = "no_verdict_not_b5", detail = ""))
  sp <- spec %||% .rfg_spec_read(a)
  if (is.null(sp) || !is.list(sp)) return(list(ok = FALSE, status = "unverified", detail = "spec_unreadable"))
  own <- .ov_own_layers(sp, carry_overlay)
  if (!length(own)) return(list(ok = TRUE, status = "no_own_layers", detail = ""))
  list(ok = FALSE, status = "unverified",
       detail = paste(vapply(own, .ov_key, character(1)), collapse = ","))
}
rf_adversary_ok <- function(a, carry_overlay = NULL, spec = NULL) isTRUE(rf_adversary_status(a, carry_overlay, spec)$ok)

#' 적대검증을 다시 돌릴 블록 (러너 tick 시작 · 승자 해석 앞 · 순수)
#'   ① verdict "deferred_refresh_lock" — 리프레시 배리어로 멈춘 칸(종전 규칙 그대로).
#'   ② ★규약 거부 error 가 **그 뒤의 rebase 로 풀릴 수 있는** 칸 (2026-09-24 수리 · 통합 검증 I2): verdict "error" 이고 사유가 규약 거부
#'      (regime_* — 셀·바닥 규약 불일치·모순·판독 불가)인데, 판정 시각(adversary$at) **뒤에** 이 entry 에서 rebase(P0-06)가 있었다
#'      (칸 measurement_regime$rebased_at · 기저 base_measurement_regime$rebased_at 중 최대). rebase 가 칸·바닥 규약을 바꿨으므로
#'      같은 비교가 이제 성립할 수 있다. 구판에는 error 를 다시 검정하는 경로가 없어 rebase 전 native close_t1 B5 칸(legacy 바닥 위)이
#'      영구 error 로 남았다. 재실행이 새 판정을 쓰면 판정 시각 > rebase 시각이라 다시 서지 않는다(루프 없음). 판정 시각이 없거나
#'      읽지 못하면 rebase 가 있을 때 재실행한다(보수 — 모르는 시각을 '최신' 으로 치지 않는다).
#' @param include_deferred FALSE = ②만(러너는 ① 을 자기 술어로 따로 본다 — 표식 문자열 패리티 검사가 그 줄을 잰다)
#' @return list(blocks = 블록 코드 벡터, why = 블록 → "deferred"|"regime_rebased" · 칸 목록)
rf_adversary_rerun_blocks <- function(E, include_deferred = TRUE) {
  ts <- function(x) { s <- .rfg_s1(x); if (!nzchar(s)) return(NA_real_)
    v <- suppressWarnings(as.numeric(as.POSIXct(s, format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC"))); if (length(v) == 1L) v else NA_real_ }
  rb <- c(vapply(E$attempts %||% list(), function(a) ts((if (is.list(a[["measurement_regime"]])) a[["measurement_regime"]] else list())$rebased_at),
                 numeric(1)),
          ts((if (is.list(E$base_measurement_regime)) E$base_measurement_regime else list())$rebased_at))
  last_rb <- if (any(is.finite(rb))) max(rb[is.finite(rb)]) else NA_real_
  why <- list()
  for (a in E$attempts %||% list()) {
    v <- a$adversary %||% list(); vd <- .rfg_s1(v$verdict); blk <- .rfg_s1(v$block); if (!nzchar(blk)) blk <- "B5"
    cd <- .rfg_s1(tryCatch(.rf_attempt_code(a), error = function(e) NA_character_))
    tag <- if (identical(vd, "deferred_refresh_lock")) (if (isTRUE(include_deferred)) "deferred" else "") else
      if (identical(vd, "error") && grepl("(^|[^a-z_])regime_", .rfg_s1(v$reason)) && is.finite(last_rb) &&
          (!is.finite(ts(v$at)) || ts(v$at) < last_rb)) "regime_rebased" else ""
    if (nzchar(tag)) why[[blk]] <- unique(c(why[[blk]], sprintf("%s:%s", tag, if (nzchar(cd)) cd else paste0("n", .rfg_s1(a$n)))))
  }
  list(blocks = names(why), why = why)
}

#' Grade A 보류(적대검증 성분) — B5 칸이 자기 오버레이 층을 갖는데 적대검증 pass 가 아직 없으면 발행을 미룬다.
#'   B5 가 아니거나 자기 층이 없으면(승계분만) FALSE. spec 을 못 읽는 B5 칸은 보수적으로 보류(정직 결측).
#' ★P0-12(2026-09-24)로 A 자격 관문 rf_a_eligibility() 에 **흡수**됐다 — 이 판정은 그 관문의 adversary_unverified(자기 층) 성분과
#'   같은 코드(.rfg_self_unverified)다. 러너는 더 이상 이 함수를 직접 부르지 않는다(검사·수동 호출 호환용으로 남긴다).
rf_grade_a_hold <- function(code, spec, carry_overlay = NULL, attempt = NULL)
  .rfg_self_unverified(code, spec, carry_overlay, attempt)$hold

.rfg_self_unverified <- function(code, spec, carry_overlay = NULL, attempt = NULL) {
  if (!startsWith(as.character(code %||% "")[1], "B5_")) return(list(hold = FALSE, own = list(), why = "not_b5"))
  if (is.null(spec) || !is.list(spec)) return(list(hold = TRUE, own = list(), why = "spec_unreadable"))
  own <- .ov_own_layers(spec, carry_overlay)
  if (!length(own)) return(list(hold = FALSE, own = list(), why = "no_own_layers"))
  v <- as.character((attempt$adversary %||% list())$verdict %||% "")[1]
  list(hold = !identical(v, "pass"), own = own, why = if (identical(v, "pass")) "pass" else if (is.na(v) || !nzchar(v)) "no_verdict" else v)
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
#'   ★상속 칸(essence$inherited_from — 같은 스펙 결과를 물려받은 중복)은 새 시행이 아니다(2026-09-23 적대 리뷰 · 이중 계수 수리).
#'     rf_auto_notify.R:53-56 이 등급 집계에서 같은 이유로 뺀다.
#'   ★통제 칸(P1-06 · 2026-09-25)은 선정 후보가 아니라 새 시행이 아니다 — exclude_codes(러너 = rfbd_control_codes)로 뺀다.
#'     기본값 character(0) = 구판과 같다(rf_prereg.R 은 이 정의만 parse 해 부른다 — 코드 목록 없이도 서도록 base R 만 쓴다).
rf_lineage_measured <- function(entries, ids, exclude_codes = character(0)) {
  exclude_codes <- as.character(unlist(exclude_codes %||% character(0)))
  sum(vapply(Filter(function(x) x$base_id %in% ids, entries %||% list()), function(x)
    sum(vapply(x$attempts %||% list(), function(a) {
      v <- a$essence$port_t
      ok <- is.numeric(v) && length(v) == 1L && is.finite(v) && is.null(a$essence$inherited_from)
      if (ok && length(exclude_codes)) {
        cd <- as.character(unlist(a$cell_code %||% a$essence$cell_code %||% ""))[1]
        ok <- !(!is.na(cd) && nzchar(cd) && cd %in% exclude_codes)
      }
      ok
    }, logical(1))), numeric(1)))
}

#' 셀 spec 의 시행 회계 블록 — N = 기저 1 + 계보 선행 측정 칸 + 이번 배치 칸 수.
#'   ★기저 1 (2026-09-23 적대 리뷰 2건 독립 지적): 구판은 부모 없는 새 계보(원장 62 중 45)의 첫 칸이 N=1 이 되어
#'     essence 의 has_trials(n>1)가 거짓 → DSR NA → sweep 의 A 분기가 **조용히 도달 불가**였다. 충실구현 기저 측정은
#'     이 가족이 실제로 본 1회 시행이므로 센다 → N ≥ 2.
#'   ★배치 균일 (같은 지적): 한 배치의 칸은 동시에 측정되고 승자는 배치가 끝난 뒤 고른다 — 선택 시점의 가족 크기는
#'     칸마다 같다. 구판은 등록 순서로 45..49 가 갈렸다. 배치 칸 수는 중복·무처치로 닫힐 칸까지 포함한다(보수적 과대).
#'   A 판정의 최종 가족 N 재산출은 A 서류(P1-04) 몫. ★.spec_sig 는 명시 키만 보므로 이 블록은 서명을 바꾸지 않는다.
rf_selection_accounting <- function(ids, n_measured_prior, n_batch) {
  list(selection_type = "sweep", family_root = tail(ids, 1L), lineage = ids,
       n_family_at_registration = as.integer(1L + n_measured_prior + n_batch),
       n_trials_basis = "base1+lineage_measured(excl_inherited)+batch_size")
}


# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
# P0-10 · P0-12 · 규약 혼합 가드 (2026-09-24 · 도훈 승인 플랜 qvest-1-drifting-eclipse · 결정 D-B·D-C·D-D·EXEC-PRICE ·
#   PIT-C11-CONVENTIONS ⑧) — 판정은 여기(순수 함수 · 읽기만), 부작용(원장·큐·로그)은 러너·next_paper.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
# ★왜 한 자리인가: 바닥(.wbest_spec)·carry 기준선·블록 승자·승격 best·A 발행은 전부 "이 칸을 소비해도 되는가" 라는 같은 질문이다.
#   구판은 소비자마다 따로 물었다(바닥 = 적대검증만 · 승격 best = 아무것도 안 봄 · A = B5 접두만). 그 틈으로
#   ① 규약이 다른 수치가 한 argmax 에 섞이고(P0-04 close_t1 전환 뒤 legacy 칸 — rebase(P0-06) 전 과도기)
#   ② 고정 축 밖 유니버스가 바닥·carry 로 승계되고(D2-08 · 감사 P0-02: B5 칸 보유 99.6% 비멤버 실측)
#   ③ 창이 다른 칸(2011~13 시작 · 원장 사본 172칸)이 기준선이 됐다(D-C).
#   술어는 하나(rf_candidate_facts)이고 역할마다 보는 축만 다르다(RF_ROLE_CHECKS).
# ★regime 해석은 원장 정본(reinforce_ledger.R::.rf_regime_key · rf_attempt_regime 과 같은 규약)을 그대로 쓴다 — 사본 금지.
if (!exists(".rf_regime_key", mode = "function"))
  invisible(capture.output(suppressMessages(source(file.path(.RFG_ROOT(), "02_Infrastructure/reinforcement/reinforce_ledger.R"),
                                                   local = TRUE))))

.rfg_s1 <- function(x) {
  x <- tryCatch(suppressWarnings(as.character(unlist(x %||% ""))), error = function(e) "")
  if (length(x) < 1L || is.na(x[1])) "" else trimws(x[1])
}
.rfg_num <- function(x) {
  v <- tryCatch(suppressWarnings(as.numeric(unlist(x %||% NA_real_))), error = function(e) NA_real_)
  if (length(v) >= 1L && is.finite(v[1])) v[1] else NA_real_
}
.rfg_json <- function(p) {
  if (length(p) != 1L || is.na(p) || !nzchar(p) || !file.exists(p)) return(NULL)
  tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
}
# ★[["essence"]] 정확 일치 — $ 는 부분 일치라 essence 가 없고 essence_history 가 있으면 history 를 집는다(reinforce_ledger.R 머리 주석)
.rfg_spec_read <- function(a) .rfg_json(.rfg_s1((a[["essence"]] %||% list())$spec))
.rfg_art_dir <- function(artifacts, root) {
  if (is.list(artifacts)) artifacts <- artifacts$authoritative %||% ""
  p <- .rfg_s1(artifacts); if (!nzchar(p)) return(NA_character_)
  if (grepl("\\.json$", p, ignore.case = TRUE)) p <- dirname(p)
  if (!grepl("^([A-Za-z]:[/\\\\]|/|\\\\\\\\)", p)) p <- file.path(root, p)
  sub("[/\\\\]+$", "", p)
}
# tick 1회 판독 캐시(ctx$cache) — 같은 칸을 역할마다(바닥·승자 4블록·A) 다시 읽지 않는다. NULL 값도 캐시한다.
.rfg_cached <- function(ctx, key, f) {
  cc <- ctx$cache
  if (is.environment(cc) && exists(key, envir = cc, inherits = FALSE)) return(get(key, envir = cc, inherits = FALSE))
  v <- f()
  if (is.environment(cc)) assign(key, v, envir = cc)
  v
}
.rfg_auth <- function(a, ctx) {
  d <- .rfg_art_dir(a$artifacts, ctx$root); if (is.na(d)) return(NULL)
  .rfg_cached(ctx, paste0("auth|", d), function() .rfg_json(file.path(d, "authoritative_remeasure.json")))
}

#' 현행 측정 규약 — 등급 하네스가 **새 칸에 실제로 쓸** 체결 규약(constraint_defaults.json::execution.exec_price · 결정 EXEC-PRICE).
#'   해석은 하네스(replication_harness.R::rep_execution_config)와 같다: QVEST_CONSTRAINT_DEFAULTS(명시 레버) 우선, 없으면 root 정본.
#'   판독 불가 = NA — fail-closed(후보 전부 regime 미판정 · A 발행 보류). 폴백 리터럴 없음.
rf_current_regime <- function(root = .RFG_ROOT()) {
  ov <- Sys.getenv("QVEST_CONSTRAINT_DEFAULTS", "")
  p <- if (nzchar(ov)) ov else file.path(root, "02_Infrastructure", "worktask", "constraint_defaults.json")
  j <- .rfg_json(p)
  if (is.null(j)) return(list(regime = NA_character_, source = p, why = if (file.exists(p)) "unparseable" else "absent"))
  ex <- j[["execution"]]
  ep <- .rfg_s1(if (is.list(ex)) ex[["exec_price"]] else NULL)
  al <- as.character(unlist(if (is.list(ex)) ex[["exec_price_allowed"]] else NULL))
  if (!nzchar(ep)) return(list(regime = NA_character_, source = p, why = "exec_price_absent"))
  if (length(al) && !(ep %in% al)) return(list(regime = NA_character_, source = p, why = paste0("exec_price_not_allowed:", ep)))
  list(regime = ep, source = p, why = "ok")
}

#' ★소비 보류 표식 (B5FIX (c) · 2026-09-26 · 도훈 결정 항목) — 원장 attempt$vintage_flags 중 이 설정에 걸린 표식의 칸은 **소비 후보가
#'   아니다**(rf_candidate_facts 를 지나는 전 역할 = 블록 승자 · 누적 바닥 · carry 기준선의 부모 칸 · 승격 best). 사연: A 관문 ⑤ vintage_flag 는
#'   **발행만** 막는다. 교차 entry 결과 라벨이 노출된 설계 재료로 잰 B5 칸(design_materials_cross_entry_labels · possible · 7308 B5_16..20)이
#'   G2 pass 를 받으면 블록 승자 → B4 결합 · 승격 carry 로 그 처치가 **표식 없이** 퍼진다(표식은 사후·수기이고 이 flag 는 계보 재도출
#'   rf_lineage_flags.R 대상도 아니다 — 소비한 칸이 표식을 물려받는 경로가 없다).
#'   설정 = 06_Registry/a_eligibility_gate.json::holds.vintage_flag.consume_hold {flags, verdicts} ("*" = 모든 flag · verdicts 빈 = 모든 판정).
#'   부재·판독 불가 = 보류 표식 없음(현행 거동 그대로 · 항등) — 소비 제외는 선택 정책이라 fail-closed 로 넘어지면 러너가 선다(halt_no_b1_winner).
rf_consume_hold_config <- function(root = .RFG_ROOT()) {
  h <- (.rfg_json(file.path(root, "06_Registry", "a_eligibility_gate.json")) %||% list())[["holds"]]
  ch <- if (is.list(h) && is.list(h[["vintage_flag"]])) h[["vintage_flag"]][["consume_hold"]] else NULL
  fl <- as.character(unlist((ch %||% list())[["flags"]])); fl <- fl[!is.na(fl) & nzchar(fl)]
  vd <- as.character(unlist((ch %||% list())[["verdicts"]])); vd <- vd[!is.na(vd) & nzchar(vd)]
  list(flags = fl, verdicts = vd)
}

#' 러너 문맥 = 현행 규약 + 창 규칙(D-C) + tick 판독 캐시. 창 규칙 값은 constraint_defaults.json::diagnostics(P0-02 정본)에서만 읽는다
#'   (window_anchor_date = 고정 축 시작일 · window_allowance_months = D-C 12 — 둘 다 그 파일의 *_source 가 근거).
#' @param regime 주입(검사·리플레이 전용) — NULL 이면 rf_current_regime(root)
rf_runner_ctx <- function(root = .RFG_ROOT(), regime = NULL) {
  cur <- if (is.null(regime)) rf_current_regime(root) else list(regime = as.character(regime)[1], source = "injected", why = "injected")
  cdj <- .rfg_json(file.path(root, "02_Infrastructure", "worktask", "constraint_defaults.json")) %||% list()
  dg <- cdj[["diagnostics"]]
  anc <- tryCatch(as.Date(.rfg_s1(if (is.list(dg)) dg[["window_anchor_date"]] else NULL)), error = function(e) as.Date(NA))
  list(regime = cur$regime, regime_source = cur$source, regime_why = cur$why, root = root,
       exec_allowed = as.character(unlist((cdj[["execution"]] %||% list())[["exec_price_allowed"]])),
       window_anchor = if (length(anc) == 1L) anc else as.Date(NA),
       window_allow = .rfg_num(if (is.list(dg)) dg[["window_allowance_months"]] else NULL),
       consume_hold = rf_consume_hold_config(root),   # ★B5FIX (c) — 설정 없으면 빈 목록(무발화)
       cache = new.env(parent = emptyenv()))
}

#' measurement_regime → 체결 규약 라벨(현행 규약 execution.exec_price 와 같은 어휘). ★exec_price 가 있으면 그것이 정본이다 —
#'   P0-05 재측정 판의 regime 키는 "<exec_price>_<md5 8자리>"(하네스 md5 포함 · remeasure_from_holdings.R 머리)이고 rebase writer 는
#'   호출자가 준 regime 라벨을 쓰므로(reinforce_ledger.R .rf_rb_mr_new) 라벨 어휘가 둘일 수 있다. 가드가 막는 혼합은 체결 규약(P0-04 ·
#'   결정 EXEC-PRICE)이다. exec_price 가 없으면 regime 라벨 — 허용 규약명(execution.exec_price_allowed)으로 시작하는 키면 그 규약명.
.rfg_exec_label <- function(mr, ctx) {
  if (!is.list(mr)) return(NA_character_)
  ep <- .rfg_s1(mr$exec_price); if (nzchar(ep)) return(ep)
  r <- .rfg_s1(mr$regime); if (!nzchar(r)) return(NA_character_)
  for (x in (ctx$exec_allowed %||% character(0))) if (identical(r, x) || startsWith(r, paste0(x, "_"))) return(x)
  r
}

#' 칸 1개의 측정 regime(체결 규약 라벨) — 원장 표식(rebase 가 쓴 measurement_regime) → 산출물 auth(measurement_regime · 부재 =
#'   P0-01 이전 판 close_d_legacy). 해석 = reinforce_ledger.R::rf_attempt_regime(.rf_regime_key 공유) + exec_price 정규화(.rfg_exec_label).
rf_cell_regime <- function(a, ctx) {
  if (is.null(a[["essence"]])) return(list(regime = NA_character_, basis = "unmeasured"))
  mr <- a$measurement_regime
  if (is.list(mr) && (nzchar(.rfg_s1(mr$exec_price)) || nzchar(.rfg_s1(mr$regime))))
    return(list(regime = .rfg_exec_label(mr, ctx), basis = "ledger"))
  au <- .rfg_auth(a, ctx)
  if (is.null(au)) return(list(regime = NA_character_, basis = "auth_absent"))
  k <- .rf_regime_key(au)
  if (!is.na(k$regime) && is.list(au$measurement_regime)) k$regime <- .rfg_exec_label(au$measurement_regime, ctx) %||% k$regime
  if (is.na(k$regime)) k$regime <- NA_character_
  k
}

#' 칸 1개의 유니버스 kind — 측정된 spec 에서. spec 에 universe 키가 없으면 k200_kq150(러너 SPEC 조립 기본값 · .spec_sig 기본값과 같다).
#'   spec 을 못 읽으면 NA(판독 불가 — 통과 아님).
rf_cell_universe <- function(a, ctx) {
  p <- .rfg_s1((a[["essence"]] %||% list())$spec)
  sp <- if (nzchar(p)) .rfg_cached(ctx, paste0("spec|", p), function() .rfg_json(p)) else NULL
  if (is.null(sp)) return(NA_character_)
  u <- sp[["universe"]]
  if (is.null(u)) return("k200_kq150")
  k <- .rfg_s1(u$kind)
  if (nzchar(k)) k else NA_character_
}

#' 칸 1개의 창 이탈(D-C) — window_deviation_months = 고정 축 시작일 대비 effective_start 의 달력 월 차(정의 = essence_score.R 진단 절).
#'   출처 우선순위(모두 같은 정의): ① 원장 essence$window_deviation_months(워커 원장 요약 — 배선 예정) ② auth$essence_diag(충실구현 러너
#'   배선 예정) ③ 형제 essence_diag.json(rf_preflight.R::rf_essence_diag_backfill) ④ bt_result.rds 에서 essence_score.R 의 **같은 부품**
#'   (.essence_first_holding_date · .essence_return_span · .essence_month_diff)으로 재도출. 판독 불가 = NA(통과 아님).
rf_cell_window <- function(a, ctx) {
  allow <- .rfg_num(ctx$window_allow)
  mk <- function(dev, src) list(dev = dev, allow = allow, source = src,
                                exceeds = if (!is.finite(dev) || !is.finite(allow)) NA else (dev > allow))
  es <- a[["essence"]] %||% list()
  d <- .rfg_num(es$window_deviation_months); if (is.finite(d)) return(mk(d, "ledger_essence"))
  au <- .rfg_auth(a, ctx)
  d <- .rfg_num(((au %||% list())$essence_diag %||% list())$window_deviation_months)
  if (is.finite(d)) return(mk(d, "auth_essence_diag"))
  dir <- .rfg_art_dir(a$artifacts, ctx$root)
  if (is.na(dir)) return(mk(NA_real_, "artifacts_absent"))
  sib <- .rfg_cached(ctx, paste0("diag|", dir), function() .rfg_json(file.path(dir, "essence_diag.json")))
  d <- .rfg_num(((sib %||% list())$diagnostics %||% list())$window_deviation_months)
  if (is.finite(d)) return(mk(d, "sibling_essence_diag"))
  d <- .rfg_cached(ctx, paste0("win|", dir), function() .rfg_window_derive(dir, ctx))
  mk(d, if (is.finite(d)) "derived_bt_result" else "undetermined")
}
.rfg_es_env <- function(ctx) .rfg_cached(ctx, "ES_ENV", function() {
  p <- file.path(ctx$root, "02_Infrastructure", "contracts", "essence_score.R")
  if (!file.exists(p)) return(NULL)
  e <- new.env(parent = globalenv())
  ok <- tryCatch({ suppressPackageStartupMessages(library(data.table))
                   invisible(capture.output(suppressMessages(sys.source(p, envir = e, keep.source = FALSE)))); TRUE },
                 error = function(err) FALSE)
  if (isTRUE(ok) && exists(".essence_month_diff", envir = e, inherits = FALSE)) e else NULL
})
.rfg_window_derive <- function(dir, ctx) {
  ES <- .rfg_es_env(ctx)
  if (is.null(ES) || is.na(ctx$window_anchor)) return(NA_real_)
  bp <- file.path(dir, "bt_result.rds"); if (!file.exists(bp)) return(NA_real_)
  bt <- tryCatch(readRDS(bp), error = function(e) NULL); if (is.null(bt)) return(NA_real_)
  hd <- tryCatch(ES$.essence_first_holding_date(bt$holdings), error = function(e) as.Date(NA))
  rs <- tryCatch(ES$.essence_return_span(bt$period_returns), error = function(e) list(first = as.Date(NA)))
  cand <- c(hd, rs$first); cand <- cand[!is.na(cand)]
  if (!length(cand)) return(NA_real_)
  .rfg_num(ES$.essence_month_diff(ctx$window_anchor, min(cand)))
}

#' 역할별 검사 축 (정본 표)
#'   규약(regime) = 모든 역할 — 규약이 다른 수치를 한 argmax·한 문턱에 넣지 않는다(과도기 = config close_t1 → 신규 칸 close_t1 →
#'     과거 칸 rebase → current_axis 교체 · rebase 전에는 legacy 칸이 전부 빠진다 = 혼합 대신 정지).
#'   유니버스·창 = 바닥 / carry 기준선 / 승격 best 만(D2-08 · D-C "바닥·carry 후보 제외").
#'   블록 승자 = 규약만 — B3 승자는 유니버스 **처치**가 본업이고 B4 가 그 축을 분해한다(한정하면 B3 축이 죽는다).
RF_ROLE_CHECKS <- list(floor = c("regime", "universe", "window"), carry_base = c("regime", "universe", "window"),
                       promote = c("regime", "universe", "window"), winner = "regime")

#' 후보 자격 사실 — fail = 사유 코드(비었으면 자격 있음). 규약이 다르면 나머지는 비교 대상조차 아니라 판독을 멈춘다(비싼 창 판독 생략).
#'   ★P1-06(2026-09-25): 통제 칸(carry 재현 · null 희석)은 **어떤 역할의 후보도 아니다** — 역할 축과 무관하게 control_cell 로 떨어진다
#'     (블록 승자·바닥·carry 기준선의 부모 칸·승격 best 가 전부 이 술어를 지난다). 통제 칸 자신의 자격(재현 칸을 carry 기준선으로 쓸 때)은
#'     통제 판정을 건너뛰는 .rfg_facts_core 로 잰다.
rf_candidate_facts <- function(a, ctx, checks = c("regime", "universe", "window")) {
  if (isTRUE(tryCatch(rf_is_control(a, ctx), error = function(e) FALSE)))
    return(list(fail = "control_cell", facts = list(control = TRUE)))
  .rfg_facts_core(a, ctx, checks)
}
.rfg_facts_core <- function(a, ctx, checks = c("regime", "universe", "window")) {
  fail <- character(0); fx <- list()
  if ("regime" %in% checks) {
    r <- rf_cell_regime(a, ctx); fx$regime <- r$regime; fx$regime_basis <- r$basis
    cur <- ctx$regime %||% NA_character_
    if (length(cur) != 1L || is.na(cur) || !nzchar(cur)) fail <- c(fail, "regime_current_unknown")
    else if (is.na(r$regime)) fail <- c(fail, paste0("regime_unknown:", r$basis))
    else if (!identical(r$regime, cur)) fail <- c(fail, paste0("regime_mismatch:", r$regime))
    if (length(fail)) return(list(fail = fail, facts = fx))
  }
  if ("universe" %in% checks) {
    u <- rf_cell_universe(a, ctx); fx$universe <- u
    if (is.na(u)) fail <- c(fail, "universe_unknown")
    else if (!identical(u, "k200_kq150")) fail <- c(fail, paste0("universe:", u))
  }
  if ("window" %in% checks) {
    w <- rf_cell_window(a, ctx); fx$window_dev <- w$dev; fx$window_source <- w$source
    if (isTRUE(w$exceeds)) fail <- c(fail, sprintf("window_deviation:%dm", as.integer(w$dev)))
    else if (is.na(w$exceeds)) fail <- c(fail, paste0("window_undetermined:", w$source))
  }
  ## ★소비 보류 표식 (B5FIX (c)) — 역할 무관(이 술어를 지나는 역할은 전부 소비다) · 설정(rf_consume_hold_config)이 없으면 무발화.
  ch <- ctx$consume_hold
  if (length(ch$flags)) {
    hit <- Filter(function(z) { f <- .rfg_s1(z$flag); v <- .rfg_s1(z$verdict)
      nzchar(f) && ("*" %in% ch$flags || f %in% ch$flags) && (!length(ch$verdicts) || v %in% ch$verdicts) }, a$vintage_flags %||% list())
    if (length(hit)) {
      fx$consume_hold <- vapply(hit, function(z) sprintf("%s:%s", .rfg_s1(z$flag), .rfg_s1(z$verdict)), character(1))
      fail <- c(fail, paste0("vintage_hold:", fx$consume_hold[1]))
    }
  }
  list(fail = fail, facts = fx)
}

#' 후보 거르기 + 역할당 로그 1줄 — 제외는 조용하지 않다(사유 집계 · 칸 코드). 등급 불변 · 소비만 보류.
rf_candidates_keep <- function(cands, ctx, role, checks = NULL, log = NULL, base_id = "") {
  if (!length(cands)) return(cands)
  checks <- checks %||% RF_ROLE_CHECKS[[sub("_.*$", "", role)]] %||% c("regime", "universe", "window")
  fl <- lapply(cands, function(a) rf_candidate_facts(a, ctx, checks)$fail)
  bad <- vapply(fl, length, integer(1)) > 0L
  if (any(bad) && is.function(log)) {
    r1 <- vapply(fl[bad], function(f) f[1], character(1))
    tb <- table(sub(":.*$", "", r1))
    cds <- vapply(cands[bad], function(a) .rfg_s1(tryCatch(.rf_attempt_code(a), error = function(e) NA_character_)), character(1))
    log("candidates_excluded", base_id = base_id, role = role, n_excluded = sum(bad), n_kept = sum(!bad),
        regime_current = .rfg_s1(ctx$regime), by_reason = paste(sprintf("%s=%d", names(tb), as.integer(tb)), collapse = ","),
        codes = paste(utils::head(sprintf("%s=%s", cds, r1), 30L), collapse = ","),
        note = "후보 자격 미달 — 소비만 보류(등급 불변 · 규약 혼합 가드 · 유니버스/창 한정)")
  }
  cands[!bad]
}

#' 계보 안에서 적대검증 pass 를 받은 오버레이 층 키 — 승계 층의 A 소비 자격(P0-12 "승계 층도 보류").
#'   pass 레코드의 own_layers(rf_overlay_adversary.R 이 적는 자기 층 목록) ∪ 그 칸 spec 의 overlay_cell.
rf_verified_layer_keys <- function(entries, ids) {
  keys <- character(0)
  for (e in Filter(function(x) .rfg_s1(x$base_id) %in% ids, entries %||% list()))
    for (a in e$attempts %||% list()) {
      adv <- a$adversary %||% list()
      if (!identical(.rfg_s1(adv$verdict), "pass")) next
      for (z in adv$own_layers %||% list()) if (is.list(z)) keys <- c(keys, .ov_key(z))
      sp <- .rfg_spec_read(a)
      if (!is.null(sp) && !is.null(sp$overlay_cell)) keys <- c(keys, vapply(.ov_layers(sp$overlay_cell), .ov_key, character(1)))
    }
  unique(keys[nzchar(keys)])
}

# ── A 자격 관문 (P0-12) ─────────────────────────────────────────────────────────────────────────────────
#   보류 = 등급 불변 · 발행만 미룸(judge_request · grade_a_queue awaiting_judge · entry 졸업). 보류 A 의 entry 는 active 로 남아
#   다음 tick 도 칸을 소비한다(rf_record_result(graduate = FALSE)). 코드 on/off = 06_Registry/a_eligibility_gate.json(근거 = 결정 ID).
RF_A_HOLD_CODES <- c("legacy_regime", "adversary_unverified", "window_deviation", "n_trials_missing", "accounting_fail",
                     "vintage_flag", "sigma_w_lt_1", "dossier_pending", "rule_pending")

#' 관문 설정 — 9개 코드 전부가 논리 스칼라 active 를 가져야 한다. 판독 불가·코드 불일치·타입 불량 = ok=FALSE
#'   (관문은 gate_config 보류로 fail-closed — 설정 오타가 보류를 조용히 끄지 못하게).
rf_a_gate_config <- function(root = .RFG_ROOT()) {
  p <- file.path(root, "06_Registry", "a_eligibility_gate.json")
  bad <- function(why) list(ok = FALSE, source = p, error = why,
                            active = stats::setNames(rep(TRUE, length(RF_A_HOLD_CODES)), RF_A_HOLD_CODES),
                            vintage_flags = "*", vintage_verdicts = character(0), entry_base_flags = character(0), entry_base_clean = NULL,
                            required_selection_type = "")
  j <- .rfg_json(p)
  if (is.null(j)) return(bad(if (file.exists(p)) "unparseable" else "absent"))
  h <- j[["holds"]]
  if (!is.list(h) || is.null(names(h))) return(bad("holds_absent"))
  unk <- setdiff(names(h), RF_A_HOLD_CODES); miss <- setdiff(RF_A_HOLD_CODES, names(h))
  if (length(unk) || length(miss))
    return(bad(sprintf("codes_mismatch(unknown=%s missing=%s)", paste(unk, collapse = "+"), paste(miss, collapse = "+"))))
  typed <- vapply(RF_A_HOLD_CODES, function(k) { v <- (h[[k]] %||% list())$active
    is.logical(v) && length(v) == 1L && !is.na(v) }, logical(1))
  if (!all(typed)) return(bad(paste0("active_not_logical:", paste(RF_A_HOLD_CODES[!typed], collapse = "+"))))
  act <- vapply(RF_A_HOLD_CODES, function(k) isTRUE(h[[k]]$active), logical(1))
  vf <- h[["vintage_flag"]]
  list(ok = TRUE, source = p, error = "", active = act, schema = .rfg_s1(j$schema),
       vintage_flags = as.character(unlist(vf$flags %||% list("*"))),
       vintage_verdicts = as.character(unlist(vf$verdicts %||% list())),
       entry_base_flags = as.character(unlist(vf[["entry_base_flags"]] %||% list())),
       entry_base_clean = if (is.list(vf[["entry_base_clean"]])) vf[["entry_base_clean"]] else NULL,
       required_selection_type = .rfg_s1(h[["accounting_fail"]]$required_selection_type))
}

#' 엔진 파일 경로 해석·내용 md5 (AUTOMEM 기저 전파 · 2026-09-26) — 판독 불가 = NA
.rfg_engine_file <- function(p, root = .RFG_ROOT()) {
  p <- gsub("\\\\", "/", .rfg_s1(p)); if (!nzchar(p)) return("")
  if (!grepl("^([A-Za-z]:)?/", p)) p <- file.path(root, p)
  p
}
rf_engine_md5 <- function(p, root = .RFG_ROOT()) {
  f <- .rfg_engine_file(p, root)
  if (nzchar(f) && file.exists(f) && !dir.exists(f)) unname(as.character(tools::md5sum(f))) else NA_character_
}
.rfg_utc <- function(s) {
  s <- .rfg_s1(s); if (!nzchar(s)) return(NA_real_)
  if (grepl("Z$", s)) return(as.numeric(as.POSIXct(sub("Z$", "", s), tz = "UTC", format = "%Y-%m-%dT%H:%M:%OS")))
  as.numeric(as.POSIXct(sub("([+-][0-9]{2}):?([0-9]{2})$", "\\1\\2", s), format = "%Y-%m-%dT%H:%M:%OS%z", tz = "UTC"))
}
#' 청정 출처 판정 — 자기 신고(lane_provenance)를 현재 파일과 대조(FA-CLEAN-BASE-PATH 레인 소비 규칙 · 06_Registry/replication_clean_lane.json
#'   provenance_consumer_fields.consumer_rule): mode == require_mode ∧ clean ∧ post.engine_md5 == 현재 내용 md5 ∧ pre.at > produced_after ∧
#'   (10-03 인터페이스 갱신) engine_rel == 이 엔진의 저장소 상대경로 ∧ 엔진 디렉터리 이름이 wdir_prefix 로 시작 ∧
#'   현재 내용이 노출 기저 엔진 md5 가 아님. 설정·기록·파일 판독 불가 = 청정 아님(보수 — 전파 유지).
.rfg_rel <- function(f, root) {
  a <- tolower(gsub("\\\\", "/", .rfg_s1(f))); r <- tolower(sub("/+$", "", gsub("\\\\", "/", .rfg_s1(root))))
  if (nzchar(r) && startsWith(a, paste0(r, "/"))) substring(a, nchar(r) + 2L) else a
}
rf_engine_clean_verified <- function(p, root, cfg, md5_now = rf_engine_md5(p, root), exposed_md5 = character(0)) {
  no <- function(why) list(ok = FALSE, why = why)
  if (!is.list(cfg) || !nzchar(.rfg_s1(cfg$provenance_file))) return(no("청정 규칙 설정 없음"))
  if (!nzchar(.rfg_s1(cfg$wdir_prefix))) return(no("청정 규칙 wdir_prefix 없음(반쪽 설정으로 청정을 인정하지 않는다)"))
  f <- .rfg_engine_file(p, root); if (!nzchar(f)) return(no("엔진 경로 없음"))
  pp <- file.path(dirname(f), .rfg_s1(cfg$provenance_file)); pv <- .rfg_json(pp)
  if (is.null(pv)) return(no("출처 기록 없음"))
  if (!identical(.rfg_s1(pv$mode), .rfg_s1(cfg$require_mode)) || !isTRUE(pv$clean)) return(no(sprintf("출처 mode=%s", .rfg_s1(pv$mode))))
  if (is.na(md5_now)) return(no("엔진 판독 불가"))
  if (!identical(.rfg_s1((pv$post %||% list())$engine_md5), md5_now)) return(no("출처 post.engine_md5 ≠ 현재 엔진(청정 실행 뒤 수정)"))
  t0 <- .rfg_utc((pv$pre %||% list())$at); tc <- .rfg_utc(cfg$produced_after)
  if (!is.finite(t0) || !is.finite(tc) || t0 <= tc) return(no("청정 실행 시각이 cutoff 뒤가 아니다"))
  er <- tolower(gsub("\\\\", "/", .rfg_s1(pv$engine_rel)))
  if (!nzchar(er) || !identical(er, .rfg_rel(f, root))) return(no("출처 engine_rel ≠ 이 엔진의 저장소 상대경로(다른 디렉터리의 기록)"))
  if (!startsWith(tolower(basename(dirname(f))), tolower(.rfg_s1(cfg$wdir_prefix))))
    return(no(sprintf("엔진 디렉터리가 청정 접두(%s)로 시작하지 않는다", .rfg_s1(cfg$wdir_prefix))))
  if (md5_now %in% exposed_md5) return(no("현재 내용 = 노출 기저 엔진 내용"))
  list(ok = TRUE, why = "청정 출처(소비 규칙 충족)", provenance = pp)
}

#' A 관문 문맥 = 러너 문맥 + 관문 설정 + 계보 검증 층 키 (+ 선택: 고정 축 재도출 결과 axes · 서류/규칙 준비 표식)
rf_a_ctx <- function(rctx, entries, base_id, axes = NULL, gate = NULL, dossier_ready = FALSE, rule_ready = FALSE) {
  x <- rctx
  x$gate <- gate %||% rf_a_gate_config(rctx$root)
  x$verified <- rf_verified_layer_keys(entries, rf_lineage_ids(entries, base_id))
  x$axes <- axes; x$dossier_ready <- isTRUE(dossier_ready); x$rule_ready <- isTRUE(rule_ready)
  # ★P0-14: 관문 재도출(⑤)의 L1 원천 — 러너 tick 원장(비었으면 재도출이 root 원장 파일을 읽는다 · 충실구현 어댑터는 list())
  x$entries <- entries %||% list()
  x
}

#' A 자격 관문 (P0-12 · 순수 · rf_grade_a_hold 흡수)
#' @param entry   원장 entry(carry$overlay — 자기 층 판별). NULL 허용.
#' @param attempt list(n, cell_code, grade, essence, artifacts [, adversary, vintage_flags, measurement_regime]) — 수집 시점의 새 칸이면
#'                원장 기록 전 모양(표식 없음)을 넘긴다.
#' @param spec    셀 스펙(list) — NULL 이면 attempt essence$spec 에서 읽는다.
#' @param ctx     rf_a_ctx() 결과
#' @return list(eligible, codes = 활성 보류(발행 막음), inactive = 발화했지만 결정상 꺼진 보류(기록만), fired, detail(코드→사유),
#'              facts, gate_source, regime_current, self_unverified, evaluated_at)
rf_a_eligibility <- function(entry, attempt, spec, ctx) {
  G <- ctx$gate %||% rf_a_gate_config(ctx$root)
  fired <- character(0); detail <- list(); fx <- list()
  add <- function(code, why) { fired <<- c(fired, code); detail[[code]] <<- paste(c(detail[[code]], why), collapse = " · ") }
  if (!isTRUE(G$ok)) add("gate_config", sprintf("관문 설정 판독 불가(%s · %s) — fail-closed", G$error, G$source))
  sp <- spec %||% .rfg_spec_read(attempt)
  code <- .rfg_s1(tryCatch(.rf_attempt_code(attempt), error = function(e) NA_character_))
  if (!nzchar(code) && is.list(sp)) code <- .rfg_s1(sp$code)
  au <- .rfg_auth(attempt, ctx)
  es <- attempt[["essence"]] %||% list()
  # ⓪ control_cell (P1-06 · 2026-09-25) — 통제 칸은 선정 후보가 아니다. 설정 on/off 가 없는 always-on 보류(gate_config 와 같은 자리):
  #   RF_A_HOLD_CODES·a_eligibility_gate.json 집합에 넣지 않는다(코드 집합 일치 규칙을 건드리지 않고 끌 수도 없게).
  if (isTRUE(tryCatch(rf_is_control(attempt, ctx, spec = sp), error = function(e) FALSE)))
    add("control_cell", "통제 칸(P1-06 carry 재현·null 희석) — 선정 후보 아님 · 등급 불변 · 발행 없음")
  # ① legacy_regime — 칸 규약 ≠ 현행 규약(P0-04 결정 EXEC-PRICE · rebase 전 측정은 현행 규약의 A 가 아니다)
  r <- rf_cell_regime(attempt, ctx)
  fx$regime <- r$regime; fx$regime_basis <- r$basis; fx$regime_current <- ctx$regime %||% NA_character_
  cur <- ctx$regime %||% NA_character_
  if (length(cur) != 1L || is.na(cur) || !nzchar(cur)) add("legacy_regime", sprintf("현행 규약 판독 불가(%s)", .rfg_s1(ctx$regime_why)))
  else if (is.na(r$regime)) add("legacy_regime", sprintf("칸 규약 판독 불가(%s)", r$basis))
  else if (!identical(r$regime, cur)) add("legacy_regime", sprintf("칸 %s ≠ 현행 %s", r$regime, cur))
  # ② adversary_unverified — 자기 층(B5 · 구 rf_grade_a_hold) + 승계 층(계보에 pass 기록이 없는 층)
  su <- .rfg_self_unverified(code, sp, (entry %||% list())$carry$overlay, attempt)
  fx$own_layers <- vapply(su$own, .ov_key, character(1))
  if (isTRUE(su$hold)) add("adversary_unverified", sprintf("자기 층 %s — %s", paste(fx$own_layers, collapse = ","), su$why))
  allk <- if (is.list(sp)) vapply(.ov_layers(sp[["overlay"]]), .ov_key, character(1)) else character(0)
  inh <- setdiff(allk, fx$own_layers)
  unv <- setdiff(inh, ctx$verified %||% character(0))
  fx$inherited_layers <- inh; fx$inherited_unverified <- unv
  if (length(unv)) add("adversary_unverified", sprintf("승계 층 미검증 %s(계보에 적대검증 pass 기록 없음)", paste(unv, collapse = ",")))
  # ③ window_deviation (D-C: 허용 = 기저 최장 룩백 12개월 · 초과 칸 A 보류)
  w <- rf_cell_window(attempt, ctx)
  fx$window_dev <- w$dev; fx$window_allow <- w$allow; fx$window_source <- w$source
  if (isTRUE(w$exceeds)) add("window_deviation", sprintf("%s개월 > 허용 %s개월(D-C)", w$dev, w$allow))
  else if (is.na(w$exceeds)) add("window_deviation", sprintf("창 판독 불가(%s) — 통과 아님", w$source))
  # ④ 시행 회계 (P0-01 fail-closed — N·선택 유형을 모르면 DSR 게이트가 실제로 섰는지 모른다)
  #   ★원천: rebase 된 칸이면 **현 essence 가 온 형제 판**(원장 표식 measurement_regime.remeasure_path — P0-05 재측정 auth)이 회계 원천이다.
  #   원 산출물 auth 는 구 규약 측정의 회계라(P0-01 이전 판이면 필드 자체가 없다) 새 등급의 회계가 아니다. 없으면 원 산출물.
  mrL <- if (is.list(attempt$measurement_regime)) attempt$measurement_regime else list()
  rp <- .rfg_s1(mrL$remeasure_path)
  sib <- if (nzchar(rp)) .rfg_cached(ctx, paste0("auth|", rp), function() .rfg_json(rp)) else NULL
  if (!is.null(sib)) au <- sib
  fx$accounting_source <- if (!is.null(sib)) "rebase_sibling" else if (!is.null(au)) "artifact_auth" else "none"
  mr <- if (is.list((au %||% list())$measurement_regime)) au$measurement_regime else list()
  nt <- .rfg_num((au %||% list())$n_trials_cumulative %||% mr$n_trials_cumulative %||% es$n_trials_cumulative)
  nbs <- .rfg_s1(mr$n_trials_basis)
  fx$n_trials <- nt; fx$n_trials_basis <- nbs
  if (!is.finite(nt) || nt < 1) add("n_trials_missing", "n_trials_cumulative 부재")
  else if (startsWith(nbs, "unknown")) add("n_trials_missing", sprintf("n_trials_basis=%s — N 을 추정하지 않는다", nbs))
  sel <- .rfg_s1((au %||% list())$selection_type %||% mr$selection_type %||% es$selection_type)
  req <- .rfg_s1(G$required_selection_type)
  dsr <- .rfg_num((au %||% list())$dsr %||% ((au %||% list())$essence %||% list())$dsr %||% es$dsr)
  fx$selection_type <- sel; fx$dsr <- dsr
  if (is.null(au)) add("accounting_fail", "authoritative_remeasure.json 판독 불가")
  else if (!length(mr)) add("accounting_fail", "measurement_regime 부재(P0-01 이전 산출물)")
  if (nzchar(req) && !identical(sel, req)) add("accounting_fail", sprintf("selection_type=%s ≠ %s", if (nzchar(sel)) sel else "(없음)", req))
  if (identical(sel, "sweep") && is.finite(nt) && nt >= 2 && !is.finite(dsr)) add("accounting_fail", "sweep·N≥2 인데 DSR 부재(게이트 미적용)")
  # ⑤ vintage_flag — 원장 표식 칸(pit_c11 등) + ★관문 시점 재도출(P0-14 · 2026-09-25).
  #   구판은 원장 표식만 봤다 — 수집 시점 새 칸은 표식이 없어(표식은 사후) 표식 계보(22632 등)의 새 칸이 같은 오염 집합을 carry 로 싣고도
  #   통과했다. 재도출 = rf_lineage_flags.R::rflf_gate_flags(P0-08 derive 와 같은 술어): (a) 칸 팩터 중 as-of 출처로 증명되지 않은 부분이
  #   원장 자기 표식 칸의 전표본 선정 집합을 포함 → selection_basis_full_sample_ic(_inherited) · (b) pit_quarantine.json 효력 항목 사용 →
  #   pit_c11. 파생 표식은 원장 표식과 같은 필터(G$vintage_flags·verdicts)를 지난다. 재도출 실패·오염 집합 판독 불가·재도출 입력(칸 spec ·
  #   선언 엔진) 판독 불가 = 보류(fail-closed · 수리 2판 — 판정 규칙 변경 전문은 rf_lineage_flags.R 머리 주석 ①~⑤).
  fl <- attempt$vintage_flags %||% list()
  dv <- tryCatch(rflf_gate_flags(entry, attempt, sp, ctx, engine_paths = attempt$engine_path),
                 error = function(e) list(error = conditionMessage(e)))
  if (!is.null(dv$error)) add("vintage_flag", sprintf("계보 표식 재도출 실패(%s) — fail-closed(P0-14)", dv$error))
  if (length(dv$S_unknown))
    add("vintage_flag", sprintf("오염 집합 판독 불가 %d칸(%s) — fail-closed(P0-14)", length(dv$S_unknown),
                                paste(utils::head(dv$S_unknown, 5L), collapse = ",")))
  # ★P0-14 수리 2판 ④: 재도출 입력(칸 spec · 선언 엔진)을 못 읽으면 보류 — 파생 표식은 원장에 적지 않으므로(tick 안 기록 불가) 재평가
  #   (tick 시작 .a_eval(.ha, .rfg_spec_read(.ha)) · B5 경계 .a_recheck) 때 spec 파일이 사라지거나 깨지면 보류가 조용히 풀렸다.
  #   충실구현 어댑터(spec 미선언 + engine_path)는 엔진 파일을 읽을 수 있는 한 해당 없음.
  if (length(dv$unreadable))
    add("vintage_flag", sprintf("재도출 입력 판독 불가(%s) — fail-closed(P0-14)", paste(utils::head(dv$unreadable, 3L), collapse = " · ")))
  fl <- c(fl, dv$flags %||% list())
  # ★entry 기저 표식 전파(AUTOMEM · 2026-09-26) — 설정 entry_base_flags 에 든 base_vintage_flags 만. 경로: self(이 entry) · lineage(부모 사슬 ·
  #   rf_lineage_ids) · same_engine(같은 엔진 경로) · same_content(현재 엔진 내용 md5 = 표식 source 의 engine_md5). 청정 출처 엔진은 lineage·same_engine
  #   전파에서 뺀다(FA-CLEAN-BASE-PATH 조정). **A 보류만** — 소비 술어(rf_candidate_facts)는 attempt 표식만 읽으므로 기저 노출 entry 의 칸은
  #   바닥·승자·carry·승격 후보로 남는다(B5FIX-CONSUME-HOLD). 원장에는 쓰지 않는다(판정만). 목록이 비면 구판과 같다.
  .ebf <- as.character(unlist(G$entry_base_flags %||% character(0)))
  if (length(.ebf)) {
    .root <- ctx$root %||% .RFG_ROOT()
    .bid0 <- .rfg_s1((entry %||% list())$base_id)
    .npth <- function(p) tolower(gsub("\\\\", "/", .rfg_s1(p)))
    .all <- c(if (!is.null(entry)) list(entry), Filter(function(x) !identical(.rfg_s1(x$base_id), .bid0), ctx$entries %||% list()))
    .bfl <- function(x) Filter(function(z) .rfg_s1(z$flag) %in% .ebf, x$base_vintage_flags %||% list())
    .zmd5 <- function(z) { s <- .rfg_s1(z$source); m <- regmatches(s, regexpr("engine_md5=[0-9a-f]{32}", s)); if (length(m)) sub("engine_md5=", "", m) else "" }
    .xmd5 <- unique(unlist(lapply(.all, function(x) vapply(.bfl(x), .zmd5, character(1))))); .xmd5 <- .xmd5[nzchar(.xmd5)]
    .md50 <- if (!is.null(entry)) rf_engine_md5(entry$engine_path, .root) else NA_character_
    .cl0 <- if (!is.null(entry)) rf_engine_clean_verified(entry$engine_path, .root, G$entry_base_clean, .md50, .xmd5) else list(ok = FALSE, why = "entry 없음")
    fx$engine_clean <- .cl0$why
    .lin <- if (nzchar(.bid0)) rf_lineage_ids(.all, .bid0) else character(0)
    .eng0 <- if (!is.null(entry)) .npth(entry$engine_path) else ""
    .mk <- function(z, b, via) list(flag = .rfg_s1(z$flag), verdict = .rfg_s1(z$verdict), evidence = .rfg_s1(z$evidence),
                                    source = .rfg_s1(z$source), entry_base = b, via = via)
    .got <- character(0)
    for (.x in .all) {
      .b <- .rfg_s1(.x$base_id); .zs <- .bfl(.x); if (!length(.zs)) next
      .via <- if (identical(.b, .bid0)) "self" else if (.b %in% .lin) "lineage" else
              if (nzchar(.eng0) && identical(.npth(.x$engine_path), .eng0)) "same_engine" else
              if (!is.na(.md50) && .md50 %in% vapply(.zs, .zmd5, character(1))) "same_content" else ""
      if (!nzchar(.via)) next
      if (.via %in% c("lineage", "same_engine") && isTRUE(.cl0$ok)) next      # 청정 출처 엔진 = 전파 제외
      for (.z in .zs) { fl <- c(fl, list(.mk(.z, .b, .via))); .got <- c(.got, .via) }
    }
    fx$entry_base_via <- unique(.got)
  }
  .dtag <- function(z) if (isTRUE(z$derived)) " · 재도출 P0-14" else if (nzchar(.rfg_s1(z$entry_base))) sprintf(" · entry 기저 %s(%s)", .rfg_s1(z$entry_base), .rfg_s1(z$via)) else ""
  fx$vintage_flags <- vapply(fl, function(z) sprintf("%s:%s%s", .rfg_s1(z$flag), .rfg_s1(z$verdict),
                                                     if (isTRUE(z$derived)) "(derived)" else if (nzchar(.rfg_s1(z$entry_base))) "(entry_base)" else ""),
                             character(1))
  fx$derived_flags <- vapply(dv$flags %||% list(), function(z) sprintf("%s — %s", .rfg_s1(z$flag), .rfg_s1(z$source)), character(1))
  if (!is.null(dv$selection)) { fx$selection_basis <- dv$selection$selection_basis; fx$asof_clean_ids <- dv$selection$clean }
  hitf <- Filter(function(z) { f <- .rfg_s1(z$flag); v <- .rfg_s1(z$verdict)
    nzchar(f) && ("*" %in% G$vintage_flags || f %in% G$vintage_flags) &&
      (!length(G$vintage_verdicts) || v %in% G$vintage_verdicts) }, fl)
  if (length(hitf)) add("vintage_flag", paste(vapply(hitf, function(z) sprintf("%s(%s%s)", .rfg_s1(z$flag), .rfg_s1(z$verdict), .dtag(z)),
                                                     character(1)), collapse = ","))
  # ⑥ sigma_w_lt_1 — 결정 D-D 로 꺼짐(Σw=1 은 위험자산 정규화 · 오버레이 현금과 양립). 켜지면 축 재도출 라벨로 판정(없으면 판독 불가 = 보류).
  if (is.null(ctx$axes)) { if (isTRUE(G$active[["sigma_w_lt_1"]])) add("sigma_w_lt_1", "고정 축 재도출 결과 없음 — 판독 불가") }
  else if ("sigma_w_lt_1" %in% as.character(unlist(ctx$axes$labels))) add("sigma_w_lt_1", "Σw<1(오버레이 현금)")
  # ⑦⑧ dossier_pending · rule_pending — 결정 D-B("selection_audit 는 보고만")로 꺼짐. 켜지면 준비 표식이 없는 한 보류(기록은 늘 남긴다).
  if (!isTRUE(ctx$dossier_ready)) add("dossier_pending", "A 서류(P1-04) 미준비 — D-B: 보고만(서류는 첨부)")
  if (!isTRUE(ctx$rule_ready)) add("rule_pending", "판정 규칙 미확정 — D-B: 보고만")
  act <- if (isTRUE(G$ok)) G$active else stats::setNames(rep(TRUE, length(RF_A_HOLD_CODES)), RF_A_HOLD_CODES)
  u <- unique(fired)
  on <- u[vapply(u, function(k) k %in% c("gate_config", "control_cell") || isTRUE(act[k]), logical(1))]
  list(eligible = !length(on), codes = on, inactive = setdiff(u, on), fired = u, detail = detail, facts = fx,
       gate_source = G$source, gate_active = names(act)[act], regime_current = cur, self_unverified = isTRUE(su$hold),
       evaluated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
}

# ── carry 기준선 · 바닥 게이트 (P0-10 · D2-05 · D2-08) ─────────────────────────────────────────────────────
#' 부모 승자 attempt — carry 기준선(parent$best_port_t)을 낳은 칸. 라벨 = essence$cell_code(승격 기록 parent$cell 의 출처 ·
#'   reinforce_auto_next_paper.R best$cell_code) → 없으면 격자 좌표. 같은 라벨이 여럿(B4 결합 칸)이면 port_t 가 기록과 같은 칸.
#'   허용오차 = 원장 직렬화 해상도(toJSON digits 6 · reinforce_ledger.R RF_REBASE_TOL 과 같은 값 — 새 문턱이 아니다).
rf_parent_best_attempt <- function(E, entries) {
  pid <- .rfg_s1((E$parent %||% list())$base_id); if (!nzchar(pid)) return(NULL)
  pe <- Filter(function(x) identical(.rfg_s1(x$base_id), pid), entries %||% list()); if (!length(pe)) return(NULL)
  cell <- .rfg_s1(E$parent$cell); bp <- .rfg_num(E$parent$best_port_t)
  tol <- if (exists("RF_REBASE_TOL") && is.numeric(RF_REBASE_TOL)) RF_REBASE_TOL else 1e-6
  lab <- function(a) { ce <- .rfg_s1((a[["essence"]] %||% list())$cell_code); if (nzchar(ce)) ce else .rfg_s1(a$cell_code) }
  pt_eq <- function(a) { v <- .rfg_num((a[["essence"]] %||% list())$port_t); is.finite(v) && is.finite(bp) && abs(v - bp) <= tol }
  atts <- Filter(function(a) !is.null(a[["essence"]]), pe[[1]]$attempts %||% list())
  c1 <- Filter(function(a) nzchar(cell) && identical(lab(a), cell), atts)
  if (length(c1) > 1L) c1 <- Filter(pt_eq, c1)
  if (!length(c1)) c1 <- Filter(pt_eq, atts)
  if (length(c1)) c1[[1]] else NULL
}

#' carry 기준선 — 승계 entry 의 게이트 문턱(부모 승자 PORT_t). **비교가 성립할 때만** 값을 낸다: 부모 승자 칸이 현행 규약 ·
#'   k200_kq150(carry 는 유니버스를 리셋한다 — 처치 유니버스의 PORT_t 는 자식과 비교 불가 · D2-08) · 창 허용 안(D-C).
#'   성립하지 않으면 NA(게이트 무발화) + 사유 — 모르는 기준선으로 막지도, 섞인 기준선으로 통과시키지도 않는다. 사유는 호출자가 로그로 남긴다.
rf_carry_base_info <- function(E, entries, ctx) {
  o <- function(v, why, ...) c(list(value = v, why = why), list(...))
  if (is.null(E$carry)) return(o(NA_real_, "no_carry"))
  v <- .rfg_num((E$parent %||% list())$best_port_t)
  if (!is.finite(v)) return(o(NA_real_, "parent_best_missing"))
  u <- .rfg_s1((E$carry$universe_reset_from %||% list())$kind)
  if (nzchar(u) && !identical(u, "k200_kq150")) return(o(NA_real_, paste0("carry_source_universe:", u)))
  pa <- rf_parent_best_attempt(E, entries)
  if (is.null(pa)) return(o(NA_real_, "parent_best_attempt_not_found"))
  f <- rf_candidate_facts(pa, ctx, RF_ROLE_CHECKS$carry_base)
  if (length(f$fail)) return(o(NA_real_, paste0("parent_best_", f$fail[1]), parent_n = pa$n))
  o(v, "ok", parent_n = pa$n, regime = f$facts$regime)
}

#' carry 구성 → 바닥 스펙. E$carry 가 곧 물려받은 구성이다(rf_promote_carry: 유니버스 고정 축 리셋 · 탈락 층 제거 후).
#'   source_spec 파일을 다시 읽으면 리셋 전 유니버스·탈락 층이 되살아나므로 읽지 않고 출처(source_cell·source_spec)로만 남긴다.
#'   ★축 목록 = 등록부(rf_spec_axes.R::rf_axes_floor_from_carry · 2026-09-26) — 구판은 여기 여섯 축을 따로 적었다(같은 목록이 코드 네 곳).
#'     union 축(팩터) = carry 값(없으면 빈 목록) · 나머지 = carry 값 → 없으면 등록부 default(비중 ew · 유니버스 k200_kq150) → 그래도 없으면 키 없음.
rf_carry_floor_spec <- function(carry) {
  if (is.null(carry)) return(NULL)
  s <- rf_axes_floor_from_carry(carry)
  s$floor_source <- "carry"; s$source_cell <- .rfg_s1(carry$source_cell); s$source_spec <- .rfg_s1(carry$source_spec)
  s
}

#' P0-10 바닥 게이트 — carry 기준선이 성립하는 승계 entry 에서 바닥(entry 안 자격 칸 중 PORT_t 최고)이 기준선을 **넘지 못하면**
#'   (또는 자격 칸이 없으면) 바닥 = carry 구성. 비교는 .beats_carry 와 같다(값 > 기준선).
#'   ★구판: B1 승자에만 게이트를 걸고(factors ← NULL) 바닥에는 안 걸어서, block_accumulate 가 비운 factors 를 **같은 미달 승자**의
#'   스펙으로 다시 채웠다(D2-05 · 운영 로그 winner_below_carry_base 164건 — 14760 promo3: B1_3 3.133 < carry 3.589 인데 B5·B2·B3 가
#'   carry 4팩터 + 3팩터 희석 구성 위에서 돌았다 · 프로그램 최고 Calmar 칸 B5_19 가 그 위에서 나왔다).
#'   ★carry 를 .wbest_spec 후보에 가상 시도로 넣는 안은 불채택(비평 권고 6) — .carry_base 는 부모 시점 값이라 그 칸이 승자·A·승격
#'   후보로 새면 빈티지가 섞인다. 여기서는 바닥 구성만 carry 로 고정하고 carry 는 어떤 후보 집합에도 들어가지 않는다.
rf_floor_carry_gate <- function(floor_spec, floor_val, carry, carry_base) {
  cb <- .rfg_num(carry_base)
  if (is.null(carry) || !is.finite(cb)) return(list(use_carry = FALSE, why = "no_gate"))
  fv <- .rfg_num(floor_val)
  if (!is.null(floor_spec) && is.finite(fv) && fv > cb) return(list(use_carry = FALSE, why = "floor_beats_carry"))
  list(use_carry = TRUE, why = if (is.null(floor_spec)) "no_floor" else "floor_not_above_carry",
       spec = rf_carry_floor_spec(carry))
}


# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
# P1-06 통제 칸 (2026-09-25 스테이징 · 플랜 qvest-1-drifting-eclipse P1-06 · 검증 E3) — 판정은 여기(순수 · 읽기만), 부작용은 러너.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
# ★왜: 승격 entry 의 B1 칸은 전부 'carry + 팩터' 다. 그런데 ①carry 구성 자체를 이 entry 의 측정 문맥(규약·빈티지·조립 경로)에서 잰 적이
#   없어 기준선(.carry_base)이 부모 시점 값이었고(빈티지 혼합) ②'팩터 하나를 얹는 처치'가 무정보일 때 얼마나 흔들리는지(잡음 척도)를
#   몰랐다 — 위상쌍(B6_32/33)은 계통 효과라 SE 원천이 아니다(레버 감사). 그래서 B1 머리에 대조 두 종을 매 세대 한 번 잰다:
#     carry_replay(B1_0) — 처치 0. 같은 조립 경로라 carry 가 경로에서 새면(예: B1 칸이 carry 의 rebalance·defense_sleeve 를 안 싣는다)
#                          부모 승자 스펙과 서명이 갈라져 E3 가 붉어진다. 같은 regime 이면 carry 기준선이 이 칸의 PT 를 쓴다.
#     null_factor(B1_N*) — carry + 무정보 순위 팩터(rf_cell_engine.R kind null_perm · seed 고정 월내 순열). 칸 간 흩어짐 = 잡음 척도.
# ★통제 칸이 새면 생기는 병: 승자·바닥·승격·A 로 소비되면 무정보 칸이 다음 세대의 구성이 되고, 서명 dedup·승계·무처치 판정에 걸리면
#   재현 칸이 부모 서명과 같아 '측정 0회'로 닫힌다(공허 통과) — 그래서 E3 는 inherited·terminal 을 red 로 읽는다.
RF_CONTROL_KINDS <- c("carry_replay", "null_factor")

#' 통제 칸 설정 — 격자 정본 standing_cells[control](rf_block_design.R::rfbd_control_cells). ctx 가 있으면 tick 캐시.
.rfg_control_cfg <- function(ctx = NULL, root = NULL) {
  root <- root %||% (ctx$root %||% .RFG_ROOT())
  f <- function() {
    cl <- tryCatch(rfbd_control_cells(root), error = function(e) list())
    cd <- vapply(cl, function(x) .rfg_s1(x$code), character(1))
    # ★B4-SIX-AXIS(2026-09-26): 코드에는 격자 블록 칸의 대조 칸(같은 control 태그 — B7_40 무신호 · B7_41 부호 반전)도 든다(rfbd_control_codes =
    #   standing 통제 ∪ 격자 대조). cells 는 standing 통제만(rf_control_plan 이 B1 머리에 넣는 칸 · E3 · null 희석 판독기의 입력 — 격자 칸은 이미 격자에 있다).
    list(cells = cl, codes = unique(c(cd[nzchar(cd)], tryCatch(rfbd_control_codes(root), error = function(e) character(0)))))
  }
  if (is.list(ctx) && is.environment(ctx$cache)) .rfg_cached(ctx, paste0("ctlcfg|", root), f) else f()
}
#' 통제 칸 코드 전부(active 무관 — retired 칸도 후보에서 계속 빠져야 한다)
rf_control_codes <- function(root = .RFG_ROOT()) .rfg_control_cfg(root = root)$codes

#' attempt 가 통제 칸인가 — 두 통로: ①셀 코드 ∈ 격자 통제 코드 ②측정된 스펙의 control 필드(러너가 조립 때 싣는 부기 필드 ·
#'   격자에서 코드가 사라져도 남는 영속 표식). 어느 하나라도 참이면 통제 칸이다.
rf_is_control <- function(a, ctx = NULL, codes = NULL, spec = NULL) {
  if (is.null(codes)) codes <- .rfg_control_cfg(ctx)$codes
  cd <- .rfg_s1(tryCatch(.rf_attempt_code(a), error = function(e) NA_character_))
  if (nzchar(cd) && cd %in% codes) return(TRUE)
  sp <- spec
  if (is.null(sp)) {
    p <- .rfg_s1((a[["essence"]] %||% list())$spec)
    sp <- if (!nzchar(p)) NULL else if (is.list(ctx) && is.environment(ctx$cache))
            .rfg_cached(ctx, paste0("spec|", p), function() .rfg_json(p)) else .rfg_json(p)
  }
  is.list(sp) && nzchar(.rfg_s1(sp[["control"]]))
}
#' 러너 셀(격자 칸)이 통제 칸인가 — 무처치·서명 dedup·중복 승계·.seen_sig 등록을 건너뛰는 유일한 술어.
rf_control_exempt <- function(cell) is.list(cell) && nzchar(.rfg_s1(cell[["control"]]))

#' 통제 칸 → 러너 셀 (B1 · standing=TRUE → 회피 목록 면제 · 규칙 픽커 자리 보존(rf_batch_open_slots)).
#'   carry_replay = 팩터 0(조립 경로가 carry 를 그대로 깐다) · null_factor = null_perm 1개(carry 팩터 뒤에 붙는다 — .dedup_factors(c(carry, cur))).
rf_control_cell <- function(sc) {
  kind <- .rfg_s1(sc$control); code <- .rfg_s1(sc$code)
  out <- list(code = code, label = .rfg_s1(sc$label %||% code), block = "B1", axis = "multifactor", standing = TRUE, control = kind,
              note = "★통제 칸(P1-06) — 선정 후보가 아니다(승자·바닥·승격·A·N 제외 · 서명 dedup·승계·무처치 판정 면제).")
  if (identical(kind, "null_factor")) {
    s <- suppressWarnings(as.integer(sc$seed %||% NA))[1]
    out$factors <- list(list(kind = "null_perm", id = sprintf("null_perm_s%d", s), seed = s))
    out$control_seed <- s
    out$basis <- sprintf("통제 칸 null_factor(P1-06) — carry + 무정보 순위 팩터(seed %d · 월내 순열)", s)
  } else {
    out$factors <- list()
    out$basis <- "통제 칸 carry_replay(P1-06 · E3) — 처치 0: carry 구성을 B1 조립 경로 그대로"
  }
  out
}

#' 이번 tick 에 얹을 통제 칸 (순수) — 판정 순서:
#'   형식(코드·종류·B1·seed·격자 코드 충돌) → (a) 그 코드의 시도가 이미 있으면 항상(재개·커서·승자 해석이 코드로 칸을 찾는다) →
#'   active 아님 → applies_to(carry_present = entry$carry 가 있다) → (b) 통제 칸 없이 B1 이 이미 측정됐으면 건너뜀(entry 중간 삽입 금지 —
#'   B1 경계가 다시 서 L-code·기전·알림이 두 번 돈다) → 삽입. 건너뜀은 사유와 함께 돌려준다(러너가 로그 1줄로 모은다).
#' @return list(cells = 러너 셀 목록(.reason 포함), skipped = list(list(code, control, reason)))
rf_control_plan <- function(E, ctl_cells, cells = list()) {
  ins <- list(); skip <- list(); seeds <- integer(0)
  atts <- E$attempts %||% list()
  taken <- .rf_taken_codes(atts)
  ccodes <- vapply(ctl_cells %||% list(), function(x) .rfg_s1(x$code), character(1))
  gcodes <- vapply(cells %||% list(), function(c) .rfg_s1(c$code), character(1))
  b1_meas <- any(startsWith(setdiff(taken, ccodes), "B1_"))
  sk <- function(sc, why) skip[[length(skip) + 1L]] <<- list(code = .rfg_s1(sc$code), control = .rfg_s1(sc$control), reason = why)
  for (sc in ctl_cells %||% list()) {
    code <- .rfg_s1(sc$code); kind <- .rfg_s1(sc$control)
    if (!nzchar(code) || !(kind %in% RF_CONTROL_KINDS)) { sk(sc, "control_malformed"); next }
    if (!identical(.rfg_s1(sc$block %||% "B1"), "B1") || !startsWith(code, "B1_")) { sk(sc, "control_block_not_b1"); next }
    if (code %in% gcodes) { sk(sc, "control_code_collides_with_grid"); next }
    if (sum(ccodes == code) > 1L) { sk(sc, "control_code_duplicate"); next }
    if (identical(kind, "null_factor")) {
      s <- suppressWarnings(as.integer(sc$seed %||% NA))[1]
      if (length(s) != 1L || is.na(s)) { sk(sc, "null_seed_missing"); next }
      if (s %in% seeds) { sk(sc, "null_seed_duplicate"); next }
      seeds <- c(seeds, s)
    }
    if (code %in% taken) { ins[[length(ins) + 1L]] <- c(rf_control_cell(sc), list(.reason = "attempt_exists")); next }
    if (!isTRUE(sc$active)) { sk(sc, "inactive"); next }
    ap <- .rfg_s1(sc$applies_to %||% "carry_present")
    if (!identical(ap, "carry_present")) { sk(sc, paste0("applies_to_unknown:", ap)); next }
    if (is.null(E$carry)) { sk(sc, "no_carry"); next }
    if (b1_meas) { sk(sc, "b1_measured_before_controls"); next }
    ins[[length(ins) + 1L]] <- c(rf_control_cell(sc), list(.reason = "carry_entry_first_b1"))
  }
  list(cells = ins, skipped = skip)
}

#' 통제 칸을 B1 **머리**에 넣는다(설계·격자 B1 칸 앞 — 첫 B1 배치가 통제 배치다: 재현 PT 가 B1 승자 게이트보다 먼저 선다).
#'   B1 칸이 없으면 맨 앞. .reason(판정 사유)은 떼어낸다.
rf_control_insert <- function(cells, new) {
  if (!length(new)) return(cells)
  new <- lapply(new, function(c) { c$.reason <- NULL; c })
  k <- which(vapply(cells %||% list(), function(c) identical(.rfg_s1(c$block), "B1"), logical(1)))
  if (length(k)) append(cells, new, after = k[1] - 1L) else c(new, cells %||% list())
}

# ── 측정 판본(빈티지) · 산출물 계열 대조 ─────────────────────────────────────────────────────────────────
#' 칸의 현 essence 를 낸 산출물(rebase 된 칸 = 형제 재측정 판 measurement_regime$remeasure_path) 경로
.rfg_cur_auth_path <- function(a, ctx) {
  mrL <- if (is.list(a$measurement_regime)) a$measurement_regime else list()
  rp <- .rfg_s1(mrL$remeasure_path)
  if (nzchar(rp) && file.exists(rp)) return(list(path = rp, source = "rebase_sibling"))
  d <- .rfg_art_dir(a$artifacts, ctx$root)
  if (is.na(d)) return(list(path = "", source = "artifacts_absent"))
  list(path = file.path(d, "authoritative_remeasure.json"), source = "artifact")
}

#' 칸 1개의 데이터 판본 키 — 강도 순: fingerprint(pin_cache 지문 digest · P0-07 절단 측정) > file_stamp(재측정 판 data_vintage 의
#'   파일 크기@mtime) > snapshot_day(00_manifest data_snapshot_id + end_date — 같은 날 리프레시 전후를 못 가르는 약한 키) > unknown.
#'   두 칸의 판본이 '같다' = 강도와 키가 둘 다 같다(강도가 다르면 비교 불가 — 같다고 치지 않는다).
rf_cell_vintage <- function(a, ctx) {
  ap <- .rfg_cur_auth_path(a, ctx)
  au <- if (nzchar(ap$path)) .rfg_cached(ctx, paste0("vauth|", ap$path), function() .rfg_json(ap$path)) else NULL
  mr <- if (is.list((au %||% list())$measurement_regime)) au$measurement_regime else list()
  bt <- .rfg_s1((au %||% list())$bt_result_path)
  if (!nzchar(bt) && nzchar(ap$path)) bt <- file.path(dirname(ap$path), "bt_result.rds")
  man <- if (nzchar(bt)) .rfg_cached(ctx, paste0("man|", bt), function() .rfg_json(file.path(dirname(bt), "00_manifest.json"))) else NULL
  snap <- .rfg_s1((man %||% list())$data_snapshot_id); endd <- .rfg_s1((man %||% list())$end_date)
  fp <- .rfg_s1(((mr$data_fingerprint %||% list()))$digest)
  dv <- mr$data_vintage
  stamp <- if (is.list(dv)) {
    nm <- sort(names(dv)[vapply(dv, function(z) is.list(z) && !is.null(z$size) && !is.null(z$mtime), logical(1))])
    if (length(nm)) paste(vapply(nm, function(k) sprintf("%s:%s@%s", k, .rfg_s1(dv[[k]]$size), .rfg_s1(dv[[k]]$mtime)), character(1)), collapse = "|") else ""
  } else ""
  key <- if (nzchar(fp)) list(k = paste0("fp:", fp), s = "fingerprint") else
         if (nzchar(stamp)) list(k = paste0("stamp:", stamp), s = "file_stamp") else
         if (nzchar(snap)) list(k = sprintf("snapshot:%s|end:%s", snap, endd), s = "snapshot_day") else list(k = NA_character_, s = "unknown")
  list(key = key$k, strength = key$s, snapshot = snap, end_date = endd, auth = ap$path, auth_source = ap$source,
       bt = if (nzchar(bt)) bt else NA_character_)
}
.rfg_same_vintage <- function(v1, v2) !is.na(v1$key) && !is.na(v2$key) && identical(v1$strength, v2$strength) && identical(v1$key, v2$key)

#' 두 산출물의 계열 대조 (순수 · 읽기만) — 공통 날짜 일간 순수익(period_returns$ret_net) 최대 |차| · 공통 리밸일 보유 비중 최대 |차|.
#'   같은 스펙·같은 데이터면 비트 동일이어야 한다(엔진은 결정론 · PIT 라 뒤에 날짜가 붙어도 과거 날짜 값은 안 변한다).
#'   공통 창에서 다르면 = 데이터 판본 개정(원천 이음매·리프레시) ∨ 조립 경로 불일치 ∨ 미래 정보 누출 — 이 함수는 가르지 않고 사실만 낸다.
rf_series_compare <- function(bt_a, bt_b, tol) {
  rd <- function(p) if (length(p) == 1L && !is.na(p) && nzchar(p) && file.exists(p)) tryCatch(readRDS(p), error = function(e) NULL) else NULL
  A <- rd(bt_a); B <- rd(bt_b)
  if (is.null(A) || is.null(B)) return(list(status = "unreadable", which = c(a = is.null(A), b = is.null(B))))
  pr <- function(x) { r <- x$period_returns
    if (is.null(r) || !all(c("date", "ret_net") %in% names(r))) return(NULL)
    data.frame(date = as.Date(r$date), r = as.numeric(r$ret_net)) }
  ra <- pr(A); rb <- pr(B)
  if (is.null(ra) || is.null(rb)) return(list(status = "no_period_returns"))
  m <- merge(ra, rb, by = "date", suffixes = c("_a", "_b"))
  dr <- if (nrow(m)) max(abs(m$r_a - m$r_b), na.rm = TRUE) else NA_real_
  hl <- function(x) { h <- x$holdings
    if (is.null(h) || !all(c("date", "ticker", "target_weight") %in% names(h))) return(NULL)
    data.frame(date = as.Date(h$date), ticker = as.character(h$ticker), w = as.numeric(h$target_weight)) }
  ha <- hl(A); hb <- hl(B); dw <- NA_real_; nhd <- 0L
  if (!is.null(ha) && !is.null(hb)) {
    cd <- intersect(unique(ha$date), unique(hb$date)); nhd <- length(cd)
    if (nhd) {
      hm <- merge(ha[ha$date %in% cd, ], hb[hb$date %in% cd, ], by = c("date", "ticker"), all = TRUE, suffixes = c("_a", "_b"))
      hm$w_a[is.na(hm$w_a)] <- 0; hm$w_b[is.na(hm$w_b)] <- 0
      dw <- max(abs(hm$w_a - hm$w_b))
    }
  }
  da <- unique(ra$date); db <- unique(rb$date)
  rel <- if (setequal(da, db)) "same_dates" else if (all(db %in% da)) "a_extends_b" else if (all(da %in% db)) "b_extends_a" else "overlap"
  list(status = "ok", n_a = nrow(ra), n_b = nrow(rb), n_common = nrow(m), dates = rel,
       max_abs_dret = dr, returns_same = is.finite(dr) && dr <= tol,
       n_hold_dates_common = nhd, max_abs_dw = dw, holdings_same = if (nhd) is.finite(dw) && dw <= tol else NA, tol = tol)
}

# ── E3 — carry 재현 검사 ────────────────────────────────────────────────────────────────────────────────
#' 스펙 축별 차이 — 서명(.spec_sig)이 접는 축과 같은 정의로 축 이름만 돌려준다(서술·문서화 판정용).
.rfg_spec_axes_diff <- function(s1, s2) {
  j <- function(x) as.character(toJSON(x %||% list(), auto_unbox = TRUE, null = "null"))
  ax <- c(factors = !identical(paste(.fkeys(.rp_all_factors(s1)), collapse = "+"), paste(.fkeys(.rp_all_factors(s2)), collapse = "+")),
          base_weight = !identical(as.character(s1$base_weight %||% "ew"), as.character(s2$base_weight %||% "ew")),
          weighting = !identical(j(s1$weighting %||% list(kind = "ew")), j(s2$weighting %||% list(kind = "ew"))),
          universe = !identical(j(s1$universe %||% list(kind = "k200_kq150")), j(s2$universe %||% list(kind = "k200_kq150"))),
          overlay = !identical(j(.ov_canon(s1[["overlay"]])), j(.ov_canon(s2[["overlay"]]))),
          base_signal = !identical(as.character(s1$base_signal$path %||% s1$base_signal$kind %||% ""),
                                   as.character(s2$base_signal$path %||% s2$base_signal$kind %||% "")),
          rebalance = !identical(j(s1[["rebalance"]]), j(s2[["rebalance"]])),
          defense_sleeve = !identical(j(s1[["defense_sleeve"]]), j(s2[["defense_sleeve"]])))
  names(ax)[ax]
}

#' E3 (P1-06) — carry 재현 칸(B1_0)이 부모 승자(또는 주어진 기준 칸)를 재현하는가. 순수 · 읽기만.
#' @param ref_attempt 기준 칸(사전등록 바닥 재실행 등) — NULL 이면 rf_parent_best_attempt(E, entries)(승격 기준선을 낳은 칸)
#' @param series TRUE 면 산출물 일간 계열·보유까지 대조(bt_result.rds 두 개를 읽는다 — tick 마다 부르는 경로는 FALSE)
#' @return list(verdict, red, e3_strict(TRUE/FALSE/NA), e3_history(TRUE/FALSE/NA), use_as_carry_base, reasons, facts, tolerance)
#'   verdict: absent · pending · unmeasured_terminal(red — 측정 0회 종결) · inherited(red — 승계로 닫힘 = 공허 통과) · ref_missing ·
#'            config_missing · fail_spec(red — 서명 불일치 · carry 문서화 변환으로 설명 안 됨) · not_comparable(규약 다름 · 문서화 변환 ·
#'            판본 다름/미상) · pass(같은 규약·스펙·판본 ∧ |ΔPT| < tol ∧ (계열 대조 시) 공통 창 동일) · fail(red — 같은데 다르다)
rf_carry_replay_check <- function(E, entries, ctx, ref_attempt = NULL, series = FALSE, cfg = NULL) {
  cfg <- cfg %||% .rfg_control_cfg(ctx)
  rcell <- Filter(function(x) identical(.rfg_s1(x$control), "carry_replay"), cfg$cells %||% list())
  out <- function(verdict, red = FALSE, strict = NA, hist = NA, use = FALSE, reasons = character(0), facts = list(), tol = NA_real_)
    list(verdict = verdict, red = red, e3_strict = strict, e3_history = hist, use_as_carry_base = use, reasons = reasons,
         facts = facts, tolerance = tol)
  if (!length(rcell)) return(out("config_missing", reasons = "격자 standing_cells 에 carry_replay 통제 칸이 없다"))
  rcode <- .rfg_s1(rcell[[1]]$code)
  tol <- .rfg_num((rcell[[1]]$e3 %||% list())$tolerance)
  if (!is.finite(tol) || tol < 0) return(out("config_missing", reasons = "e3.tolerance 부재·비정상 — fail-closed(판정 안 함)"))
  ra <- Filter(function(a) identical(.rfg_s1(tryCatch(.rf_attempt_code(a), error = function(e) NA_character_)), rcode), E$attempts %||% list())
  fx <- list(replay_code = rcode)
  if (!length(ra)) return(out("absent", facts = fx, tol = tol))
  ra <- ra[[length(ra)]]; fx$replay_n <- ra$n
  es <- ra[["essence"]] %||% list()
  pt_r <- .rfg_num(es$port_t)
  if (!is.null(es$inherited_from))
    return(out("inherited", red = TRUE, reasons = sprintf("재현 칸이 %s 의 결과를 승계했다 — 측정 0회(공허 통과 · 통제 칸 dedup 면제 누락)",
                                                          .rfg_s1(es$inherited_from)), facts = fx, tol = tol))
  if (!is.finite(pt_r))
    return(if (isTRUE(ra$terminal)) out("unmeasured_terminal", red = TRUE,
                                         reasons = sprintf("재현 칸이 측정 없이 종결 — %s", substr(.rfg_s1(ra$terminal_reason), 1, 200)),
                                         facts = fx, tol = tol)
           else out("pending", facts = fx, tol = tol))
  pa <- ref_attempt %||% rf_parent_best_attempt(E, entries)
  fx$pt_replay <- pt_r
  rr <- rf_cell_regime(ra, ctx); fx$regime_replay <- rr$regime
  core <- .rfg_facts_core(ra, ctx, RF_ROLE_CHECKS$carry_base)
  fx$replay_role_fail <- core$fail
  if (is.null(pa)) return(out("ref_missing", reasons = "기준 칸(부모 승자) 부재 — 대조 불가", facts = fx, tol = tol))
  fx$ref_code <- .rfg_s1(tryCatch(.rf_attempt_code(pa), error = function(e) NA_character_)); fx$ref_n <- pa$n
  pt_p <- .rfg_num((pa[["essence"]] %||% list())$port_t); fx$pt_ref <- pt_p; fx$dpt <- pt_r - pt_p
  rp <- rf_cell_regime(pa, ctx); fx$regime_ref <- rp$regime
  s_r <- .rfg_spec_read(ra); s_p <- .rfg_spec_read(pa)
  if (is.null(s_r) || is.null(s_p)) return(out("not_comparable", reasons = "스펙 판독 불가(재현 또는 기준)", facts = fx, tol = tol))
  diff_ax <- .rfg_spec_axes_diff(s_r, s_p); fx$spec_diff_axes <- diff_ax
  sig_eq <- identical(.spec_sig(s_r), .spec_sig(s_p)); fx$sig_equal <- sig_eq
  documented <- character(0)
  urf <- .rfg_s1(((E$carry %||% list())$universe_reset_from %||% list())$kind)
  if (nzchar(urf) && !identical(urf, "k200_kq150")) documented <- c(documented, "universe")
  if (length((E$carry %||% list())$overlay_dropped)) documented <- c(documented, "overlay")
  fx$documented_transforms <- documented
  use_ok <- !length(core$fail) && identical(rr$regime, ctx$regime %||% NA_character_)
  if (!sig_eq && length(setdiff(diff_ax, documented)))
    return(out("fail_spec", red = TRUE, reasons = sprintf("재현 스펙 ≠ 기준 스펙(축 %s) — carry 문서화 변환(%s)으로 설명 안 됨: 조립 경로가 carry 를 떨어뜨린다",
                                                         paste(setdiff(diff_ax, documented), collapse = ","),
                                                         if (length(documented)) paste(documented, collapse = ",") else "없음"),
               facts = fx, tol = tol))
  if (!sig_eq) return(out("not_comparable", use = use_ok, reasons = sprintf("carry 문서화 변환(%s) — 재현은 변환된 carry 를 잰다", paste(diff_ax, collapse = ",")),
                          facts = fx, tol = tol))
  vr <- rf_cell_vintage(ra, ctx); vp <- rf_cell_vintage(pa, ctx)
  fx$vintage_replay <- vr$key; fx$vintage_ref <- vp$key; fx$vintage_strength <- c(replay = vr$strength, ref = vp$strength)
  same_reg <- !is.na(rr$regime) && identical(rr$regime, rp$regime)
  same_vin <- .rfg_same_vintage(vr, vp)
  sc <- if (isTRUE(series)) rf_series_compare(vr$bt, vp$bt, tol) else NULL
  if (!is.null(sc)) fx$series <- sc
  hist <- if (!is.null(sc) && identical(sc$status, "ok")) isTRUE(sc$returns_same) && !isFALSE(sc$holdings_same) else NA
  if (!same_reg) return(out("not_comparable", hist = hist, use = use_ok,
                            reasons = sprintf("규약 다름(재현 %s · 기준 %s) — 재현 PT 가 현행 규약의 carry 기준선", rr$regime, rp$regime), facts = fx, tol = tol))
  if (!same_vin) return(out("not_comparable", hist = hist, use = use_ok,
                            reasons = sprintf("판본 다름 또는 미상(재현 %s · 기준 %s) — ΔPT %.4f 는 빈티지 표류로만 읽는다",
                                              vr$key %||% "NA", vp$key %||% "NA", fx$dpt), facts = fx, tol = tol))
  ok_pt <- is.finite(fx$dpt) && abs(fx$dpt) < tol
  if (ok_pt && !isFALSE(hist)) return(out("pass", strict = TRUE, hist = hist, use = use_ok, facts = fx, tol = tol))
  out("fail", red = TRUE, strict = FALSE, hist = hist, use = FALSE,
      reasons = sprintf("같은 규약·스펙·판본인데 재현이 다르다(|ΔPT| %.6f · 계열 %s) — 비결정성 또는 숨은 입력 차이",
                        abs(fx$dpt), if (is.na(hist)) "미대조" else if (isTRUE(hist)) "동일" else "다름"), facts = fx, tol = tol)
}

#' carry 기준선 해석 (P1-06 — 러너가 부르는 정본) — 같은 regime 의 재현 칸 PT 우선, 아니면 부모 기록(rf_carry_base_info · 구판 그대로).
#'   재현 칸을 쓰는 조건 = E3 가 red 가 아니고(fail·fail_spec·inherited·unmeasured_terminal 아님) 재현 칸이 현행 규약 · k200_kq150 · 창 허용 안
#'   (RF_ROLE_CHECKS$carry_base — 통제 판정만 건너뛴 핵심 술어). red 면 부모 기록 경로로 떨어지고 사유를 싣는다(기준선 의미를 바꾸지 않는다).
#'   ★반환 모양은 rf_carry_base_info 와 같다(value · why) + source(replay|parent|none) · e3_verdict · parent_value · parent_why.
#'   ★승격 판정(reinforce_auto_next_paper.R)은 계속 rf_carry_base_info 를 부른다 — live 승격 규칙 교체는 안건(플랜 P1-06).
#' @param base 이미 계산한 rf_carry_base_info 결과(러너는 그 줄을 먼저 둔다 — 두 번 계산하지 않는다) · NULL 이면 여기서 계산
rf_carry_base_resolve <- function(E, entries, ctx, base = NULL) {
  base <- base %||% rf_carry_base_info(E, entries, ctx)
  if (is.null(E$carry)) return(c(base, list(source = "none")))
  e3 <- tryCatch(rf_carry_replay_check(E, entries, ctx, series = FALSE),
                 error = function(e) list(verdict = "error", red = FALSE, use_as_carry_base = FALSE, reasons = conditionMessage(e), facts = list()))
  if (isTRUE(e3$use_as_carry_base) && !isTRUE(e3$red) && is.finite(.rfg_num(e3$facts$pt_replay)))
    return(list(value = .rfg_num(e3$facts$pt_replay), why = "ok", source = "replay", replay_code = e3$facts$replay_code,
                e3_verdict = e3$verdict, parent_value = base$value, parent_why = base$why, regime = e3$facts$regime_replay))
  c(base, list(source = "parent", e3_verdict = e3$verdict, replay_reasons = paste(e3$reasons, collapse = " | ")))
}

# ── null 희석 판독기 — 사전등록 SE 원천(rf_prereg.R::rf_prereg_se_null) · 유기체 잡음 척도의 입력 ─────────────
#' entry 의 null 희석 통제 칸 값 (순수 · 읽기만). ★선택 자유도 0: 격자의 active null 칸 **전부**를 읽는다(부분집합 인자 없음 — seed 쇼핑 차단).
#' @param metric essence 키(port_t · calmar · cagr · net_sharpe · mdd · oos_retention)
#' @return list(contract = "null_dilution_cells", metric, status, reasons, codes, seeds, values, delta(값 − 재현 칸 값 · 짝지음),
#'   replay(code, value), n_finite, complete, regime, vintage, artifacts(code → auth 경로 · md5), config_codes)
#'   status ok = active null 칸 전부 측정 · 전부 현행 규약 · 재현 칸 측정 · 같은 판본 키(재현과 짝) · 유한값 ≥ 2.
#'   소비: v <- rf_null_dilution_values(E, ctx, "port_t"); if (identical(v$status, "ok")) rf_prereg_se_null(v$delta)
rf_null_dilution_values <- function(E, ctx, metric = "port_t", cfg = NULL) {
  cfg <- cfg %||% .rfg_control_cfg(ctx)
  nc <- Filter(function(x) identical(.rfg_s1(x$control), "null_factor") && isTRUE(x$active), cfg$cells %||% list())
  rc <- Filter(function(x) identical(.rfg_s1(x$control), "carry_replay"), cfg$cells %||% list())
  codes <- vapply(nc, function(x) .rfg_s1(x$code), character(1))
  seeds <- vapply(nc, function(x) suppressWarnings(as.integer(x$seed %||% NA))[1], integer(1))
  last_of <- function(cd) { z <- Filter(function(a) identical(.rfg_s1(tryCatch(.rf_attempt_code(a), error = function(e) NA_character_)), cd),
                                        E$attempts %||% list()); if (length(z)) z[[length(z)]] else NULL }
  val <- function(a) if (is.null(a) || !is.null((a[["essence"]] %||% list())$inherited_from)) NA_real_ else .rfg_num((a[["essence"]] %||% list())[[metric]])
  reasons <- character(0)
  atts <- lapply(codes, last_of)
  values <- vapply(atts, val, numeric(1))
  regs <- vapply(atts, function(a) if (is.null(a)) NA_character_ else .rfg_s1(rf_cell_regime(a, ctx)$regime), character(1))
  vins <- vapply(atts, function(a) if (is.null(a)) NA_character_ else .rfg_s1(rf_cell_vintage(a, ctx)$key), character(1))
  arts <- lapply(atts, function(a) { if (is.null(a)) return(list(path = NA_character_, md5 = NA_character_))
    p <- .rfg_cur_auth_path(a, ctx)$path
    list(path = p, md5 = if (nzchar(p) && file.exists(p)) unname(as.character(tools::md5sum(p))) else NA_character_) })
  names(values) <- codes; names(regs) <- codes; names(vins) <- codes; names(arts) <- codes
  rcode <- if (length(rc)) .rfg_s1(rc[[1]]$code) else ""
  ra <- if (nzchar(rcode)) last_of(rcode) else NULL
  rv <- val(ra)
  rreg <- if (is.null(ra)) NA_character_ else .rfg_s1(rf_cell_regime(ra, ctx)$regime)
  rvin <- if (is.null(ra)) NA_character_ else .rfg_s1(rf_cell_vintage(ra, ctx)$key)
  delta <- values - rv
  complete <- length(codes) > 0L && all(is.finite(values))
  if (!length(codes)) reasons <- c(reasons, "격자에 active null_factor 통제 칸이 없다")
  if (length(codes) && !complete) reasons <- c(reasons, sprintf("미측정 %s", paste(codes[!is.finite(values)], collapse = ",")))
  cur <- ctx$regime %||% NA_character_
  if (any(is.finite(values)) && !all(regs[is.finite(values)] %in% cur)) reasons <- c(reasons, "현행 규약 아닌 칸이 섞였다")
  if (!is.finite(rv)) reasons <- c(reasons, "재현 칸(B1_0) 미측정 — 짝지음 불가")
  else if (!identical(rreg, cur)) reasons <- c(reasons, "재현 칸 규약 ≠ 현행")
  if (is.finite(rv) && any(is.finite(values)) &&
      !all(vapply(vins[is.finite(values)], function(v) !is.na(v) && !is.na(rvin) && identical(v, rvin), logical(1))))
    reasons <- c(reasons, "판본 키가 재현 칸과 다르거나 미상인 null 칸이 있다(짝지음 무효)")
  nfin <- sum(is.finite(delta))
  if (nfin < 2L) reasons <- c(reasons, sprintf("유한 짝 %d개 < 2(rf_prereg_se_null 최소)", nfin))
  status <- if (!length(reasons)) "ok" else if (!length(codes)) "no_config" else if (!complete) "incomplete" else "invalid"
  list(contract = "null_dilution_cells", metric = metric, status = status, reasons = reasons, codes = codes, seeds = seeds,
       values = values, delta = delta, replay = list(code = rcode, value = rv, regime = rreg, vintage = rvin),
       n_finite = nfin, complete = complete, regime = regs, vintage = vins, artifacts = arts, config_codes = codes,
       regime_current = cur)
}

if (sys.nframe() == 0L)
  cat("[rf_runner_gates.R] Loaded (WP-R · P0-10/11/12) — rf_standing_decision / rf_budget_auto / rf_adversary_ok(P0-11) / rf_adversary_status / rf_grade_a_hold / rf_ov_txt / rf_lineage_ids / rf_lineage_measured / rf_selection_accounting / rf_current_regime / rf_runner_ctx / rf_candidate_facts / rf_candidates_keep / rf_a_gate_config / rf_a_ctx / rf_a_eligibility / rf_carry_base_info / rf_floor_carry_gate\n")
