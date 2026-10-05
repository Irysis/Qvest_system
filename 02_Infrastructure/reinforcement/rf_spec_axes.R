#==============================================================================
# rf_spec_axes.R — 스펙 축 등록부 **정본** (결정 B4-SIX-AXIS-AND-CARRY-AXES · 도훈 2026-09-26 승인)
#
# ★왜 파일 하나인가 — "승계 목록에서 빠진 축은 없는 축이 된다"(09-05 교훈 · carry 에 overlay 가 없어 위험 통제가 세대마다 리셋)의 재발:
#   09-21 B6(집행 주기 rebalance)·B7(구조적 방어 defense_sleeve) 신설 때 축 목록이 코드 여러 곳에 따로 있었고 일부만 갱신됐다 —
#     ① 러너 carry 병합 = factors·weighting·universe·overlay 만(rebalance·defense_sleeve 누락)
#     ② 러너 B4 조립 = B1·B2·B3·B5 승자만(B6·B7 누락 — 결합이 두 축을 영영 못 봤다)
#     ③ 러너 block_accumulate = 여섯 축(여기만 갱신) · ④ rf_promote_carry = 여섯 축 기록(생산자는 실었다 — 소비자가 안 읽었다)
#     ⑤ 러너 overlay_cell 표식(자기 오버레이 층이 없는 블록) = B1·B2·B3(B6·B7 누락 — 승계 층이 그 칸의 '자기 층'으로 오귀속)
#   실사례: RP_20260913_084807_skipped_base_promo1 — carry.rebalance = buffer_2x 인데 B1_1..7 이 월간 리밸로 측정됐다
#   (P1-06 CTRL 실데이터 carry 재현 대조 E3 = fail_spec · diff=rebalance). 승자 칸(B6_36)이 이긴 이유가 버퍼였는데 자식 B1 이 그것을 벗고 돌았다.
#   ⇒ 축 목록과 축별 의미를 여기 **한 곳**에 두고 소비자는 전부 이 표에서 파생한다:
#      러너 누적(rf_axes_accumulate) · carry 병합(rf_axes_carry_fill) · B4 승자/조립(rf_axes_block_winners · rf_axes_b4_assemble) ·
#      overlay_cell 표식(rf_axes_no_layer_blocks) · 승격 carry 기록(rf_axes_promote_carry ← rf_promote.R) ·
#      carry 바닥 스펙(rf_axes_floor_from_carry ← rf_runner_gates.R::rf_carry_floor_spec) · 격자 기본 예산(rf_budget_base) · 격자 계약(rf_axes_grid_contract) ·
#      셀 스펙 초기값(rf_axes_cell_init — 교체 축) · 무처치 판정(rf_axes_same_as_carry — 전 축 carry 대조) · 승계 순서 스위치(rf_axes_inherit_order).
#   ★서명(.spec_sig · rf_spec_sig.R)은 여기서 파생하지 않는다 — 기존 원장 칸 서명을 비트 그대로 두기 위해서다. 대신 sig 필드가 두 쪽의 축 집합을
#     선언하고 검사(test_rf_spec_axes.R)가 '각 축 값을 바꾸면 서명이 바뀐다'를 축마다 재도출한다(없는 축은 grep 에 안 걸린다 — 행동으로 잰다).
#
# 등록부 필드(축마다):
#   axis     스펙 키 — 셀 스펙·carry·서명이 쓰는 이름.
#   block    소유 블록 — 그 축을 시험 축으로 바꾸는 격자 블록(reinforce_program.json blocks[].id · rf_axes_grid_contract 가 대조).
#   combine  자기 축에서 셀 값과 carry 값을 합치는 방식 — union(합집합 · 중복 제거 .dedup_factors · 러너 factors 병합) ·
#            stack(층 중첩 .ov_stack · 러너 B5 절) · replace(교체 — 셀 값). ★비소유 축은 전부 '승계'다(RF_AXES_INHERIT_ORDER).
#   carry    승격 carry 기록 — winner(승자 스펙 값) · reset(고정 축 기본값으로 리셋 + <axis>_reset_from 에 출처 · 도훈 결정 2026-09-05) ·
#            winner_filtered(오버레이 층 규칙 3종 = 상한·상주 제외·적대검증 탈락 층 제외 · rf_promote.R::.rfp_carry_overlay).
#   b4_base  B4(결합)에서 그 축의 블록이 빠졌거나(LOO) 승자가 없을 때의 값 — carry(carry 값, 없으면 default) · default.
#            ★현행 B5 처리(승자 없음·LOO = carry 오버레이 · "승자 없음 ≠ 부모 통제 해제 · LOO 대조 보존")를 전 축에 같은 원리로 편다(결정 문언).
#   default  아무것도 없을 때 값. NULL = 키 없음(엔진 기본 — 월간 리밸 · 슬리브 없음 · 오버레이 없음).
#            ★새로 정한 값이 아니다: 러너 SPEC 초기화(weighting %||% ew · universe %||% k200_kq150)와 서명 기본값(rf_spec_sig.R .spec_sig)을 옮겨 적었다.
#   sig      서명 포함 방식(선언 — 정본은 rf_spec_sig.R) — always(기본값으로 채워 항상 접는다) · if_present(있을 때만 — 없는 스펙은 구판 서명과 비트 동일).
#   label_ko 사람 표기(로그·알림).
#
# 계약: 순수 함수 · 파일 읽기/쓰기 없음(격자는 호출자가 PROG 로 넘긴다) · 등록부 무효 = stop()(축 없이 조용히 도는 판 금지 · fail-closed).
# 모드 구현 계약: union 은 factors, stack 은 overlay 에만 구현돼 있다(러너 팩터 병합·.win_factors / .ov_stack·overlay_cell·엔진 층 합성).
#   다른 축에 그 모드를 선언하면 rf_axes_check 가 거부한다 — 선언만 바꾸고 구현이 따라오지 않는 상태를 막는다.
#==============================================================================
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

RF_SPEC_AXES <- list(
  list(axis = "factors",        block = "B1", combine = "union",   carry = "winner",          b4_base = "carry",
       default = NULL,                       sig = "always",     label_ko = "팩터"),
  list(axis = "weighting",      block = "B2", combine = "replace", carry = "winner",          b4_base = "carry",
       default = list(kind = "ew"),          sig = "always",     label_ko = "비중"),
  list(axis = "universe",       block = "B3", combine = "replace", carry = "reset",           b4_base = "carry",
       default = list(kind = "k200_kq150"),  sig = "always",     label_ko = "유니버스"),
  list(axis = "overlay",        block = "B5", combine = "stack",   carry = "winner_filtered", b4_base = "carry",
       default = NULL,                       sig = "always",     label_ko = "오버레이"),
  list(axis = "rebalance",      block = "B6", combine = "replace", carry = "winner",          b4_base = "carry",
       default = NULL,                       sig = "if_present", label_ko = "집행 주기"),
  list(axis = "defense_sleeve", block = "B7", combine = "replace", carry = "winner",          b4_base = "carry",
       default = NULL,                       sig = "if_present", label_ko = "방어 슬리브"))

#' 결합 블록 — 축을 소유하지 않고 소유 블록 승자들을 전결합 1 + 축별 LOO 로 조립한다(격자 blocks[B4].cells[].combo.use).
RF_AXES_COMBO_BLOCK <- "B4"

#' 비소유 축 승계 순서 — ★결정 항목(도훈 · 권고 floor > carry):
#'   floor(바닥 = 이 entry 안 지금까지 최고 자격 칸 · P0-10 게이트가 carry 기준선 미달이면 carry 구성으로 고정) → carry(부모 승자 구성) → 셀 초기값.
#'   구판 러너는 block_accumulate(바닥) 뒤에 carry 병합이 weighting·universe·overlay 를 **덮었다** — 승격 entry 에서 B2 승자 비중이 B3 칸에 안 실렸다
#'   (실측 원장: 720_promo1 B3_12..15 = carry lean:ivol · 바닥 B2_10 = lean:score_pure · 14760_promo1 B3 4칸 같은 형태). 바닥은 carry 위에서 잰 칸이라
#'   바닥 값이 이미 carry 를 포함한다 — 바닥이 있으면 바닥, 없을 때(B1 · 자격 칸 0)만 carry 다. 구판 순서 = c("carry", "floor").
RF_AXES_INHERIT_ORDER <- c("floor", "carry")
#' 승계 순서 스위치 — reinforce_auto_config.json::spec_axes.inherit_order(부재 = 위 권고값 · 어휘 밖 = 권고값 + valid FALSE).
#'   도훈 결정 전 기본 = floor > carry. 구판 거동으로 되돌리려면 설정에 ["carry", "floor"] 한 줄(코드 수정 불필요).
rf_axes_inherit_order <- function(cfg = list()) {
  v <- tryCatch(as.character(unlist(((cfg %||% list())$spec_axes %||% list())$inherit_order)), error = function(e) character(0))
  if (!length(v)) return(list(order = RF_AXES_INHERIT_ORDER, source = "default", valid = TRUE))
  if (!length(rf_axes_check(order = v))) return(list(order = v, source = "config", valid = TRUE))
  list(order = RF_AXES_INHERIT_ORDER, source = sprintf("invalid:%s", paste(v, collapse = ",")), valid = FALSE)
}

RF_AXES_VOCAB <- list(combine = c("union", "stack", "replace"), carry = c("winner", "reset", "winner_filtered"),
                      b4_base = c("carry", "default"), sig = c("always", "if_present"))
RF_AXES_MODE_IMPL <- list(union = "factors", stack = "overlay")

.rfax_s1 <- function(x) {
  x <- tryCatch(suppressWarnings(as.character(unlist(x))), error = function(e) character(0))
  if (length(x) == 1L && !is.na(x) && nzchar(x)) x else NA_character_
}

#' 등록부 검사 — 문제 목록(비었으면 정상). 이름·블록 유일 · 어휘 · 모드 구현 계약 · 결합 블록 비소유 · 승계 순서 어휘.
rf_axes_check <- function(ax = RF_SPEC_AXES, combo_block = RF_AXES_COMBO_BLOCK, order = RF_AXES_INHERIT_ORDER) {
  if (!is.list(ax) || !length(ax)) return("등록부가 비었다")
  p <- character(0)
  nm <- vapply(ax, function(a) .rfax_s1(a$axis), character(1))
  bl <- vapply(ax, function(a) .rfax_s1(a$block), character(1))
  if (anyNA(nm)) p <- c(p, "axis 이름 결측")
  if (anyNA(bl)) p <- c(p, "block 결측")
  if (anyDuplicated(nm[!is.na(nm)])) p <- c(p, "axis 이름 중복")
  if (anyDuplicated(bl[!is.na(bl)])) p <- c(p, "소유 블록 중복(한 블록 = 한 축)")
  if (!is.na(.rfax_s1(combo_block)) && combo_block %in% bl) p <- c(p, sprintf("결합 블록 %s 가 축을 소유한다", combo_block))
  for (k in names(RF_AXES_VOCAB)) {
    v <- vapply(ax, function(a) .rfax_s1(a[[k]]), character(1))
    bad <- is.na(v) | !(v %in% RF_AXES_VOCAB[[k]])
    if (any(bad)) p <- c(p, sprintf("%s 어휘 밖: %s", k, paste(nm[bad], collapse = ",")))
  }
  for (md in names(RF_AXES_MODE_IMPL)) {
    hit <- nm[vapply(ax, function(a) identical(.rfax_s1(a$combine), md), logical(1))]
    if (length(setdiff(hit, RF_AXES_MODE_IMPL[[md]])))
      p <- c(p, sprintf("combine=%s 는 %s 축에만 구현돼 있다(선언 %s)", md, RF_AXES_MODE_IMPL[[md]], paste(hit, collapse = ",")))
  }
  ord <- as.character(unlist(order))
  if (!length(ord) || anyDuplicated(ord) || !all(ord %in% c("floor", "carry"))) p <- c(p, "승계 순서 어휘 밖(floor·carry)")
  p
}
#' 검사를 통과한 등록부 — 무효면 stop()(fail-closed).
rf_axes <- function(ax = RF_SPEC_AXES) {
  p <- rf_axes_check(ax)
  if (length(p)) stop("[rf_spec_axes] 축 등록부 무효 — ", paste(p, collapse = " · "))
  ax
}
rf_axes_names  <- function(ax = rf_axes()) vapply(ax, function(a) a$axis, character(1))
rf_axes_blocks <- function(ax = rf_axes()) vapply(ax, function(a) a$block, character(1))
#' 블록이 소유한 축(없으면 NULL — 결합 블록 · 미지 블록)
rf_axis_of_block <- function(block, ax = rf_axes()) {
  b <- .rfax_s1(block); if (is.na(b)) return(NULL)
  for (a in ax) if (identical(a$block, b)) return(a)
  NULL
}
#' 자기 오버레이 층이 없는 블록 = stack 축이 아닌 축의 소유 블록(러너 SPEC$overlay_cell <- list() 대상 · 결합 블록은 제외 — 구판 거동 유지).
rf_axes_no_layer_blocks <- function(ax = rf_axes())
  vapply(Filter(function(a) !identical(a$combine, "stack"), ax), function(a) a$block, character(1))
#' 사람 표기(블록 또는 축 이름 → label_ko · 모르면 입력 그대로)
rf_axes_label <- function(x, ax = rf_axes()) {
  vapply(as.character(x), function(k) { for (a in ax) if (identical(a$block, k) || identical(a$axis, k)) return(a$label_ko); k }, character(1),
         USE.NAMES = FALSE)
}

# ── 셀 조립 (러너 등록 루프 · 판정 불변 = 순수) ─────────────────────────────────────────────────────────────
#' 바닥 누적(block_accumulate) — 비소유 축을 바닥 스펙 값으로. union 축(팩터)은 셀 값이 비었을 때만(구판 규칙 — B1 승자가 carry 기준선
#'   게이트에 떨어져 비운 자리를 바닥이 채운다). 자기 축은 셀 값 그대로(탐색이 죽지 않는다).
#' @return list(spec, own = 자기 축 이름(NA = 없음), from_floor = 바닥이 값을 준 축 이름들 — carry 병합이 덮지 않는다)
rf_axes_accumulate <- function(SPEC, floor_spec, block, ax = rf_axes()) {
  own <- rf_axis_of_block(block, ax); own_nm <- if (is.null(own)) NA_character_ else own$axis
  got <- character(0)
  if (is.null(floor_spec)) return(list(spec = SPEC, own = own_nm, from_floor = got))
  for (a in ax) {
    nm <- a$axis
    if (identical(nm, own_nm)) next
    fv <- floor_spec[[nm]]
    if (identical(a$combine, "union")) {
      if (is.null(SPEC[[nm]]) || !length(SPEC[[nm]])) { SPEC[[nm]] <- fv; if (length(fv)) got <- c(got, nm) }
      next
    }
    if (!is.null(fv)) { SPEC[[nm]] <- fv; got <- c(got, nm) }
  }
  list(spec = SPEC, own = own_nm, from_floor = got)
}

#' carry 병합(비소유 · 비 union 축) — 승계 순서(RF_AXES_INHERIT_ORDER)대로. floor 우선이면 바닥이 이미 준 축은 덮지 않는다.
#'   union 축은 러너의 팩터 병합(.dedup_factors(c(carry, 현재)))이 한다 · 자기 축은 셀 처치(stack 축은 러너 B5 절 .ov_stack(carry, 셀)) ·
#'   결합 블록은 조립(rf_axes_b4_assemble)이 carry 를 기저로 이미 넣었다 — 셋 다 여기서 건너뛴다.
rf_axes_carry_fill <- function(SPEC, carry, block, from_floor = character(0), ax = rf_axes(), order = RF_AXES_INHERIT_ORDER,
                               combo_block = RF_AXES_COMBO_BLOCK) {
  if (is.null(carry) || identical(.rfax_s1(block), combo_block)) return(SPEC)
  own <- rf_axis_of_block(block, ax); own_nm <- if (is.null(own)) NA_character_ else own$axis
  floor_first <- identical(as.character(unlist(order))[1], "floor")
  for (a in ax) {
    nm <- a$axis
    if (identical(a$combine, "union") || identical(nm, own_nm)) next
    cv <- carry[[nm]]
    if (is.null(cv)) next
    if (floor_first && nm %in% from_floor) next
    SPEC[[nm]] <- cv
  }
  SPEC
}

#' 셀 스펙 초기값 — 교체(replace) 축은 셀 값 그대로(없으면 등록부 default · default 가 NULL 이면 **키는 두고 값 NULL** =
#'   구판 list(…, rebalance = CELL[["rebalance"]]) 와 같은 모양 · 순서 = 등록부 순서 = 구판 순서 weighting·universe·rebalance·defense_sleeve).
#'   union(팩터)·stack(오버레이) 축은 러너가 따로 싣는다(팩터 = 셀 → 구 factor2 → B1 승자 폴백 · 오버레이 = B5 절 중첩 + overlay_cell).
#'   ★구판은 네 축을 러너 리터럴로 적었다 — 09-21 B6·B7 신설 때 여기는 갱신됐지만(빠지면 그 칸은 조용한 무처치) 목록이 흩어진 자리였다.
#'   셀 쪽은 [[ ]] 정확 일치(구판 CELL$weighting 은 $ 부분 일치 — 격자 셀 키에 접두 충돌 없음 실측 · 결과 동일).
rf_axes_cell_init <- function(CELL, ax = rf_axes()) {
  rep <- Filter(function(a) identical(a$combine, "replace"), ax)
  out <- lapply(rep, function(a) CELL[[a$axis]] %||% a$default)
  names(out) <- vapply(rep, function(a) a$axis, character(1))
  out
}

#' 무처치 판정(러너 '조립이 끝난 뒤' 절) — 스펙이 carry 와 **전 축에서** 같은가(TRUE = 처치 없음 · 측정 없이 닫는다).
#'   union 축 = 키 집합(.fkeys) 동일 · 그 밖 = .same_axis(스펙 값, carry 값 %||% 등록부 default %||% 빈 목록) — 구판 여섯 줄과 같은 식.
#'   ★축 목록 = 등록부 — 구판은 여섯 축을 리터럴로 적었다. 축이 늘 때 여기서 빠지면 '그 축만 다른 칸'이 무처치로 닫혀 측정 0회로 소비된다
#'     (2026-08-31 B5 다섯 칸 사고와 같은 모양 — 계기가 재려는 것(처치가 있나) 대신 재기 쉬운 것(목록에 있는 축)을 잰다).
#'   .fkeys·.same_axis 는 rf_spec_sig.R 정본(러너가 먼저 적재한다) — 없으면 stop(무처치로 조용히 닫는 판 금지 · fail-closed).
rf_axes_same_as_carry <- function(SPEC, carry, ax = rf_axes()) {
  if (!exists(".same_axis", mode = "function") || !exists(".fkeys", mode = "function"))
    stop("[rf_spec_axes] rf_spec_sig.R(.same_axis · .fkeys) 미적재 — 무처치 판정 불가")
  for (a in ax) {
    nm <- a$axis
    if (identical(a$combine, "union")) {
      if (!identical(.fkeys(SPEC[[nm]]), .fkeys(carry[[nm]] %||% list()))) return(FALSE)
    } else if (!.same_axis(SPEC[[nm]], carry[[nm]] %||% a$default %||% list())) return(FALSE)
  }
  TRUE
}

# ── B4 결합 ───────────────────────────────────────────────────────────────────────────────────────
#' 격자 블록 · 승자 기준(blocks[].select_winner_by — 하드코딩 금지 · 없으면 NA)
rf_grid_block <- function(prog, block) {
  for (b in prog$blocks %||% list()) if (identical(.rfax_s1(b$id), .rfax_s1(block))) return(b)
  NULL
}
rf_grid_select_by <- function(prog, block) .rfax_s1((rf_grid_block(prog, block) %||% list())$select_winner_by)

#' 소유 블록마다 승자 하나 — winner_fn(block, by) 는 러너 .winner_of(규약·유니버스·창·대조 칸·적대검증 자격을 거친 argmax).
#'   격자에 블록이 없거나 승자 기준이 없으면 그 축은 승자 없음(→ B4 base) · attr "missing_blocks" 로 드러낸다.
rf_axes_block_winners <- function(prog, winner_fn, ax = rf_axes()) {
  out <- list(); miss <- character(0)
  for (a in ax) {
    by <- rf_grid_select_by(prog, a$block)
    if (is.na(by)) { miss <- c(miss, a$block); next }
    w <- winner_fn(a$block, by)
    if (!is.null(w)) out[[a$block]] <- w
  }
  attr(out, "missing_blocks") <- miss
  out
}
.rfax_winner_value <- function(w, a) {
  if (identical(a$combine, "union")) {           # 구판 .win_factors 와 같다 — 등록부 셀 factors(복수) > 구 격자 셀 factor2(단수)
    if (!is.null(w$factors) && length(w$factors)) return(w$factors)
    if (!is.null(w$factor2)) return(list(w$factor2))
    return(NULL)
  }
  w[[a$axis]] %||% a$default
}
#' B4 칸 조립 — 축마다: 소유 블록 ∈ use ∧ 승자 있음 → 승자의 그 축 값 / 아니면 b4_base(carry → default).
#'   ★구판: 팩터(B1 승자 · 없으면 NULL → carry 병합이 carry 팩터) · 비중(B2 승자 · 없으면 **EW**) · 유니버스(B3 승자 · 없으면 k200_kq150) ·
#'   오버레이(B5 승자 · 없으면 carry · LOO 도 carry). 전 축을 오버레이 원리로 편 결과 달라지는 곳 = 승격 entry 의 비중 LOO/승자 없음(EW → carry 비중).
#'   union 축은 러너 carry 병합이 carry 팩터와 합집합한다(구판과 같다). factor2/factor3 는 비운다.
#' @return list(spec, src = 축 이름 → "winner" | "carry(loo)" | "carry(no_winner)" | "default(loo)" | "default(no_winner)")
rf_axes_b4_assemble <- function(SPEC, use, winners, carry, ax = rf_axes()) {
  use <- as.character(unlist(use %||% character(0)))
  src <- character(0)
  for (a in ax) {
    nm <- a$axis; inb <- a$block %in% use
    w <- if (inb) winners[[a$block]] else NULL
    if (!is.null(w)) { v <- .rfax_winner_value(w, a); s <- "winner" } else {
      cv <- if (identical(a$b4_base, "carry") && !is.null(carry)) carry[[nm]] else NULL
      v <- if (length(cv)) cv else a$default
      s <- sprintf("%s(%s)", if (length(cv)) "carry" else "default", if (inb) "no_winner" else "loo")
    }
    SPEC[[nm]] <- v
    src[[nm]] <- s
  }
  SPEC$factor2 <- NULL; SPEC$factor3 <- NULL
  list(spec = SPEC, src = src)
}
#' 격자 B4 칸이 가져야 할 use 집합 — 전결합 1 + 축별 LOO(등록부 순서).
rf_axes_b4_expected <- function(ax = rf_axes()) {
  bl <- rf_axes_blocks(ax)
  c(list(bl), lapply(seq_along(bl), function(i) bl[-i]))
}

# ── B4 결합 칸 재도출 — 결합 대상 축 = 등록부 축 − 진단 모드 블록 (구조 규칙 × 6축 · 결정 B3-TRIM-VS-B4-SIX = (A) exclude_axis · [위임] 2026-09-26 13:35) ──────
#   격자 blocks[B4].cells 는 **코드·라벨 목록**(진단 블록이 없을 때의 전결합 1 + 축별 LOO)이다. 이 tick 에 실제로 돌 결합 칸은 격자 칸을
#   등록부 역할(전결합 · LOO-X)로 읽은 뒤 진단 모드 블록(사람 구조 규칙 B3-STRUCTURAL-TRIM 등 — HUMAN rf_lane_rules.R::rf_structure_rules 의
#   diag/dormant 블록)과 모드 스위치로 재도출한다. 모드 = reinforce_auto_config.json::b4_combo.diag_mode(부재 = 기본):
#     exclude_axis     (A · 기본 = 결정 B3-TRIM-VS-B4-SIX) 진단 블록을 결합 축에서 뺀다 — 전결합 = 등록부 축 − 진단 · LOO-X(X 비진단) = 그 집합 − X ·
#                      LOO-진단 칸은 전결합과 같아지므로 돌지 않는다(drop). 진단 블록 축은 모든 결합 칸에서 b4_base(carry → default).
#     drop_referencing (B · 구조 규칙 현행 = rf_structure_combo_drop 과 같은 결과) use 에 진단 블록이 든 칸을 빼고 가장 넓은 칸(전결합)은 보존(불변식 ⑤).
#     keep_loo         (C) 결합 칸은 절단하지 않는다 — 진단 블록 승자(진단 1칸)도 결합에 든다.
#   입력 모양은 HUMAN rf_structure_combo_drop(PROG, trimmed_blocks, combo_block) 과 같고 반환은 그 상위집합(drop · keep_widest + cells · projected · mode).
RF_AXES_B4_DIAG_MODES <- c("exclude_axis", "drop_referencing", "keep_loo")
RF_AXES_B4_DIAG_MODE_DEFAULT <- "exclude_axis"

#' 모드 스위치 판독 — cfg$b4_combo$diag_mode(어휘 밖·부재 = 기본 · source 로 드러낸다)
rf_axes_diag_mode <- function(cfg = list()) {
  v <- .rfax_s1(((cfg %||% list())$b4_combo %||% list())$diag_mode)
  if (is.na(v)) return(list(mode = RF_AXES_B4_DIAG_MODE_DEFAULT, source = "default", valid = TRUE))
  if (!(v %in% RF_AXES_B4_DIAG_MODES)) return(list(mode = RF_AXES_B4_DIAG_MODE_DEFAULT, source = sprintf("invalid:%s", v), valid = FALSE))
  list(mode = v, source = "config", valid = TRUE)
}
#' 격자 결합 칸의 등록부 역할 — "full" | "loo:<블록>" | "unknown"(등록부로 설명 안 되는 use — 계약 위반 · 그대로 둔다)
.rfax_combo_role <- function(use, owners) {
  u <- sort(unique(as.character(unlist(use))))
  if (identical(u, sort(owners))) return("full")
  miss <- setdiff(owners, u)
  if (length(miss) == 1L && identical(u, sort(setdiff(owners, miss)))) return(paste0("loo:", miss))
  "unknown"
}
#' 이 tick 의 결합 칸 목록.
#' @param PROG 격자(list) · trimmed_blocks 진단 모드 블록 · combo_block 결합 블록 · mode RF_AXES_B4_DIAG_MODES
#' @return list(cells(격자 칸 모양 + block·axis·combo$use(재도출)·combo_plan), drop, keep_widest, projected, mode, trimmed, axes, roles)
rf_axes_combo_cells <- function(PROG, trimmed_blocks = character(0), combo_block = RF_AXES_COMBO_BLOCK,
                                mode = RF_AXES_B4_DIAG_MODE_DEFAULT, ax = rf_axes()) {
  if (!(mode %in% RF_AXES_B4_DIAG_MODES)) stop("[rf_spec_axes] 결합 모드 어휘 밖: ", mode)
  owners <- rf_axes_blocks(ax)
  tr <- intersect(owners, as.character(unlist(trimmed_blocks %||% character(0))))
  cb <- rf_grid_block(PROG, combo_block)
  gcells <- (cb %||% list())$cells %||% list()
  code <- vapply(gcells, function(c) .rfax_s1(c$code), character(1))
  use0 <- lapply(gcells, function(c) as.character(unlist((c$combo %||% list())$use)))
  roles <- vapply(use0, .rfax_combo_role, character(1), owners = owners)
  w <- vapply(use0, length, integer(1)); wide <- if (length(w)) which(w == max(w)) else integer(0)
  keep <- rep(TRUE, length(gcells)); use1 <- use0
  if (length(tr) && identical(mode, "drop_referencing")) {
    hit <- vapply(use0, function(u) any(u %in% tr), logical(1))
    keep <- !(hit & !(seq_along(gcells) %in% wide))
  } else if (length(tr) && identical(mode, "exclude_axis")) {
    keep <- !(roles %in% paste0("loo:", tr))
    use1 <- lapply(use0, function(u) setdiff(u, tr))
    k <- vapply(use1, function(u) paste(sort(u), collapse = "+"), character(1))
    kk <- which(keep); keep[kk[duplicated(k[kk])]] <- FALSE   # 투영 뒤 같은 집합이 되면 남은 칸 중 격자 순서 앞 칸만(전결합 우선)
  }
  axes <- if (identical(mode, "exclude_axis")) setdiff(owners, tr) else owners
  plan <- list(mode = mode, trimmed = as.list(tr), axes = as.list(axes))
  out <- list()
  for (i in which(keep)) {
    c <- gcells[[i]]
    c$block <- combo_block; c$axis <- as.character(cb$axis %||% "combination")
    if (is.null(c$combo)) c$combo <- list()
    c$combo$use <- as.list(use1[[i]])
    c$combo_plan <- plan
    if (!identical(sort(use1[[i]]), sort(use0[[i]]))) {
      lab <- .rfax_s1(c$label); if (is.na(lab)) lab <- code[i]
      c$label <- sprintf("%s · 진단 %s 제외", lab, paste(rf_axes_label(tr, ax), collapse = "·"))
    }
    out[[length(out) + 1L]] <- c
  }
  projected <- code[keep & vapply(seq_along(gcells), function(i) !identical(sort(use1[[i]]), sort(use0[[i]])), logical(1))]
  list(cells = out, drop = code[!keep], keep_widest = code[wide], projected = projected, mode = mode, trimmed = tr,
       axes = axes, roles = stats::setNames(roles, code))
}
#' 결합 블록 계획 동결 — 이 entry 에 결합 칸 시도가 있으면 그 칸 스펙에 기록된 계획(combo_plan)을 쓴다(진행 중 entry 의 계획을 바꾸지 않는다 ·
#'   HUMAN '절단 전 계획으로 진입한 블록은 동결' 과 같은 원리). 스펙을 읽었는데 기록이 없으면(이 수리 전 칸) 절단 없는 계획(keep_loo · 진단 없음).
#'   ★스펙을 **하나도 못 읽으면**(경로 소실 · 파일 삭제) 동결 판정 불가 — mode = NA · source = "unreadable" 로 돌려주고 러너는 현 계획으로 돈다
#'     (10-03 · 7308 tick 모의 실측: 측정 칸의 스펙이 안 보이면 구판은 '수리 전 칸'으로 오인해 keep_loo 로 진단 블록 LOO 칸(B4_24)을 되살렸다 —
#'      기록 부재와 판독 실패를 같은 값으로 접으면 안 된다).
#' @param spec_of function(attempt) -> 스펙 list 또는 NULL (측정 칸 essence$spec · 미측정 칸은 러너가 WDIR 경로로 찾는다)
#' @return NULL(시도 없음) | list(mode, trimmed, source = "recorded" | "legacy_unrecorded") | list(mode = NA, source = "unreadable", n)
rf_axes_combo_frozen <- function(attempts, spec_of, combo_block = RF_AXES_COMBO_BLOCK) {
  cb <- Filter(function(a) { cd <- .rfax_s1(a$cell_code %||% (a$essence %||% list())$cell_code)
    !is.na(cd) && startsWith(cd, paste0(combo_block, "_")) }, attempts %||% list())
  if (!length(cb)) return(NULL)
  n_read <- 0L
  for (a in cb) {
    sp <- tryCatch(spec_of(a), error = function(e) NULL)
    if (!is.list(sp)) next
    n_read <- n_read + 1L
    pl <- sp$combo_plan
    if (is.list(pl) && !is.na(.rfax_s1(pl$mode)))
      return(list(mode = .rfax_s1(pl$mode), trimmed = as.character(unlist(pl$trimmed)), source = "recorded"))
  }
  if (!n_read) return(list(mode = NA_character_, trimmed = character(0), source = "unreadable", n = length(cb)))
  list(mode = "keep_loo", trimmed = character(0), source = "legacy_unrecorded")
}

# ── 승격 carry · carry 바닥 ───────────────────────────────────────────────────────────────────────
#' 승격 carry 구성(축 부분) — rf_promote.R::rf_promote_carry 가 source_cell·source_spec·overlay_dropped 를 덧붙인다.
#' @param ws 승자 스펙 · cf 승자 팩터 목록(구 factor2/factor3 정규화 후) · ov .rfp_carry_overlay 결과 list(overlay, dropped)
rf_axes_promote_carry <- function(ws, cf, ov, ax = rf_axes()) {
  out <- list()
  for (a in ax) {
    nm <- a$axis
    if (identical(a$carry, "winner")) {
      if (identical(a$combine, "union")) out[nm] <- list(cf %||% list()) else out[nm] <- list(ws[[nm]])
    } else if (identical(a$carry, "reset")) {
      out[nm] <- list(a$default)
      out[paste0(nm, "_reset_from")] <- list(ws[[nm]])
    } else if (identical(a$carry, "winner_filtered")) {
      out[nm] <- list((ov %||% list())$overlay)
    }
  }
  out
}
#' carry 구성 → 바닥 스펙의 축 부분(P0-10 게이트가 바닥을 carry 로 고정할 때 · rf_runner_gates.R::rf_carry_floor_spec).
#'   union 축 = carry 값(없으면 빈 목록) · 나머지 = carry 값 → 없으면 default → 그래도 없으면 키 없음.
rf_axes_floor_from_carry <- function(carry, ax = rf_axes()) {
  if (is.null(carry)) return(NULL)
  s <- list()
  for (a in ax) {
    nm <- a$axis; v <- carry[[nm]]
    if (identical(a$combine, "union")) { s[[nm]] <- v %||% list(); next }
    if (is.null(v)) v <- a$default
    if (!is.null(v)) s[[nm]] <- v
  }
  s
}

# ── 격자 계약 · 예산 ──────────────────────────────────────────────────────────────────────────────
#' 격자 칸 수 합(blocks[].n — 없으면 cells 길이) = 격자 기본 예산.
rf_grid_slots_total <- function(prog) {
  v <- vapply(prog$blocks %||% list(), function(b) {
    n <- suppressWarnings(as.integer(unlist(b$n %||% NA))[1])
    if (length(n) != 1L || is.na(n)) length(b$cells %||% list()) else n }, integer(1))
  as.integer(sum(v))
}
#' entry 기본 예산 = max(원장 파일 max_attempts, 격자 칸 수 합) — 원장 값은 격자 크기의 사본이라 격자가 늘면(B4 6축 7칸) 낡는다.
#'   올리기만 한다(내리면 수동 상향이 깎인다 · rf_budget_want 와 같은 원리).
rf_budget_base <- function(ledger_max, prog) {
  lm <- suppressWarnings(as.integer(unlist(ledger_max %||% NA))[1]); if (length(lm) != 1L || is.na(lm)) lm <- 0L
  max(lm, rf_grid_slots_total(prog))
}
#' 등록부 ↔ 격자 계약 — 소유 블록 실재 · 격자 블록은 전부 축 소유(결합 블록 제외) · 승자 기준 존재 · 결합 칸 = 전결합 + 축별 LOO(정확히) ·
#'   결합 블록 n = 칸 수 · requires = 소유 블록. 문제 목록을 돌려준다(러너는 로그 · 검사는 red).
rf_axes_grid_contract <- function(prog, ax = rf_axes(), combo_block = RF_AXES_COMBO_BLOCK) {
  p <- character(0)
  ids <- vapply(prog$blocks %||% list(), function(b) .rfax_s1(b$id), character(1))
  own <- rf_axes_blocks(ax)
  if (length(setdiff(own, ids))) p <- c(p, sprintf("등록부 소유 블록이 격자에 없다: %s", paste(setdiff(own, ids), collapse = ",")))
  ex <- setdiff(ids, c(own, combo_block))
  if (length(ex)) p <- c(p, sprintf("격자 블록이 등록부 축을 소유하지 않는다: %s", paste(ex, collapse = ",")))
  for (b in intersect(own, ids)) if (is.na(rf_grid_select_by(prog, b))) p <- c(p, sprintf("%s select_winner_by 부재", b))
  cb <- rf_grid_block(prog, combo_block)
  if (is.null(cb)) return(c(p, sprintf("결합 블록 %s 부재", combo_block)))
  key <- function(v) paste(sort(unique(as.character(unlist(v)))), collapse = "+")
  got <- vapply(cb$cells %||% list(), function(c) key((c$combo %||% list())$use), character(1))
  exp <- vapply(rf_axes_b4_expected(ax), key, character(1))
  if (anyDuplicated(got)) p <- c(p, "결합 칸 use 중복")
  if (length(setdiff(exp, got))) p <- c(p, sprintf("결합 칸 부족: %s", paste(setdiff(exp, got), collapse = " | ")))
  if (length(setdiff(got, exp))) p <- c(p, sprintf("결합 칸 초과(등록부로 설명 안 됨): %s", paste(setdiff(got, exp), collapse = " | ")))
  n <- suppressWarnings(as.integer(unlist(cb$n %||% NA))[1])
  if (!identical(n, length(cb$cells %||% list()))) p <- c(p, sprintf("결합 블록 n(%s) ≠ 칸 수(%d)", n, length(cb$cells %||% list())))
  if (!identical(key(cb$requires), key(own))) p <- c(p, sprintf("결합 블록 requires(%s) ≠ 소유 블록(%s)", key(cb$requires), key(own)))
  p
}
