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
# 요구: rf_spec_sig.R(.rf_taken_codes · .ov_arm_ids · .ov_own_layers) · rf_block_design.R(rfbd_standing_cells · .rfbd_b5_raw) ·
#       rf_lineage_flags.R(P0-14 · 계보 표식 술어 정본 — P0-08 derive 와 같은 함수) ·
#       reinforce_ledger.R(.rf_regime_key — regime 해석 정본) · 설정: 02_Infrastructure/worktask/constraint_defaults.json
#       (execution.exec_price · diagnostics.window_*) · 06_Registry/a_eligibility_gate.json(A 보류 코드 on/off)
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.RFG_ROOT <- function() Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
# ★층 정규화·상주 칸 읽기는 정본 하나만 — 러너 안에서는 이미 적재돼 있고, 단독 source(검사)면 여기서 적재한다.
if (!exists(".ov_arm_ids", mode = "function") || !exists(".rf_taken_codes", mode = "function"))
  source(file.path(.RFG_ROOT(), "02_Infrastructure/reinforcement/rf_spec_sig.R"), local = TRUE)
if (!exists("rfbd_standing_cells", mode = "function"))
  invisible(capture.output(source(file.path(.RFG_ROOT(), "02_Infrastructure/reinforcement/rf_block_design.R"), local = TRUE)))
# ★P0-14 계보 표식 술어 정본 — 관문 ⑤ 재도출(선정 기저 승계 · C11 격리). 파일 부재 = 적재 실패(러너는 source 실패로 멈춘다 ·
#   충실구현 어댑터는 gate_error 보류) — 조용히 재도출 없이 도는 판이 생기지 않게 조건부 적재를 하지 않는다.
if (!exists("rflf_gate_flags", mode = "function"))
  invisible(capture.output(source(file.path(.RFG_ROOT(), "02_Infrastructure/reinforcement/rf_lineage_flags.R"), local = TRUE)))

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
rf_lineage_measured <- function(entries, ids) {
  sum(vapply(Filter(function(x) x$base_id %in% ids, entries %||% list()), function(x)
    sum(vapply(x$attempts %||% list(), function(a) {
      v <- a$essence$port_t
      is.numeric(v) && length(v) == 1L && is.finite(v) && is.null(a$essence$inherited_from)
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
rf_candidate_facts <- function(a, ctx, checks = c("regime", "universe", "window")) {
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
                            vintage_flags = "*", vintage_verdicts = character(0), required_selection_type = "")
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
       required_selection_type = .rfg_s1(h[["accounting_fail"]]$required_selection_type))
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
  .dtag <- function(z) if (isTRUE(z$derived)) " · 재도출 P0-14" else ""
  fx$vintage_flags <- vapply(fl, function(z) sprintf("%s:%s%s", .rfg_s1(z$flag), .rfg_s1(z$verdict), if (isTRUE(z$derived)) "(derived)" else ""),
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
  on <- u[vapply(u, function(k) identical(k, "gate_config") || isTRUE(act[k]), logical(1))]
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
rf_carry_floor_spec <- function(carry) {
  if (is.null(carry)) return(NULL)
  s <- list(factors = carry$factors %||% list(), weighting = carry$weighting,
            universe = carry[["universe"]] %||% list(kind = "k200_kq150"))
  if (!is.null(carry[["overlay"]])) s$overlay <- carry[["overlay"]]
  if (!is.null(carry[["rebalance"]])) s$rebalance <- carry[["rebalance"]]
  if (!is.null(carry[["defense_sleeve"]])) s$defense_sleeve <- carry[["defense_sleeve"]]
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

if (sys.nframe() == 0L)
  cat("[rf_runner_gates.R] Loaded (WP-R · P0-10/11/12) — rf_standing_decision / rf_budget_auto / rf_adversary_ok(P0-11) / rf_adversary_status / rf_grade_a_hold / rf_ov_txt / rf_lineage_ids / rf_lineage_measured / rf_selection_accounting / rf_current_regime / rf_runner_ctx / rf_candidate_facts / rf_candidates_keep / rf_a_gate_config / rf_a_ctx / rf_a_eligibility / rf_carry_base_info / rf_floor_carry_gate\n")
