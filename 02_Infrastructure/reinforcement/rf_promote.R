#==============================================================================
# rf_promote.R — B등급 이상 승격 판정 (도훈 지시 2026-08-30 "추가 강화프로세스")
#
# 왜 함수로 떼어내는가:
#   승격 게이트가 회귀하면 두 방향으로 조용히 망가진다 — ①영영 승격 안 함(기능 사망,
#   로그엔 아무 것도 안 남는다) ②무조건 승격(한 논문이 큐 예산을 무한히 먹는다).
#   둘 다 "정상처럼" 보인다. 러너 안에 인라인으로 두면 검사가 못 건드리므로 순수 함수로
#   분리해 양방향(승격/비승격 각각)을 단언한다.
#
# 계약: 부작용 없음 — 원장·파일을 쓰지 않는다. 판정만 돌려준다.
#==============================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.RFP_ROOT <- function() Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
# ★층 정규화·상주 칸 읽기는 정본 하나만 (2026-09-17): rf_spec_sig.R(.ov_layers/.ov_key) · rf_block_design.R(rfbd_standing_picks/rfbd_max_layers).
#   러너 안에서는 이미 적재돼 있고, 단독 source(검사·next_paper)면 여기서 적재한다. 읽기뿐 — 이 파일은 여전히 쓰지 않는다.
if (!exists(".ov_layers", mode = "function"))
  source(file.path(.RFP_ROOT(), "02_Infrastructure/reinforcement/rf_spec_sig.R"), local = TRUE)
if (!exists("rfbd_standing_picks", mode = "function"))
  invisible(capture.output(source(file.path(.RFP_ROOT(), "02_Infrastructure/reinforcement/rf_block_design.R"), local = TRUE)))
# ★후보 자격 술어는 러너와 같은 정본(rf_runner_gates.R · 2026-09-24 P0-12) — 승격 best 가 바닥·carry 와 다른 자로 고르면
#   자식의 carry 기준선이 부모 바닥과 다른 규약·유니버스·창의 값이 된다(D2-08). 읽기뿐 — 이 파일은 여전히 쓰지 않는다.
if (!exists("rf_candidate_facts", mode = "function"))
  invisible(capture.output(source(file.path(.RFP_ROOT(), "02_Infrastructure/reinforcement/rf_runner_gates.R"), local = TRUE)))
# ★carry 축 목록은 등록부 정본(rf_spec_axes.R · 결정 B4-SIX-AXIS-AND-CARRY-AXES 2026-09-26) — 관문이 이미 적재했으면 그대로 쓴다.
if (!exists("rf_axes_promote_carry", mode = "function"))
  source(file.path(.RFP_ROOT(), "02_Infrastructure/reinforcement/rf_spec_axes.R"), local = TRUE)

#' 승격 best 후보 자격 (P0-12 · D2-08 · D-C · 규약 혼합 가드 · P0-11 · 2026-09-24)
#'   구판(reinforce_auto_next_paper.R)은 소진 entry 의 **전 칸** PORT_t 최대를 best 로 골랐다. B3 유니버스 처치 칸(KQ150 단독 ·
#'   2010~ 창)이 best 가 되면 carry 는 유니버스를 k200_kq150 으로 리셋하는데(rf_promote_carry) 자식의 기준선(parent$best_port_t)은
#'   그 처치 창의 값이 되어 부모-자식 비교가 재현 불가였다(D2-08). 창 이탈 칸(D-C)·규약이 다른 칸(P0-04 과도기)·자기 층이
#'   미검증인 B5 칸(P0-11)도 같은 이유로 물려줄 승자가 아니다.
#'   자격 = rf_candidate_facts(RF_ROLE_CHECKS$promote: 규약·유니버스 k200_kq150·창) ∧ rf_adversary_ok(carry 오버레이 기준 자기 층).
#' @param E   소진 entry
#' @param ctx rf_runner_ctx() 결과(현행 규약 · 창 규칙 · 캐시)
#' @return list(i = 선택 attempt 인덱스(NA = 없음), reason, defer, n_measured, n_eligible, excluded = named character(칸 코드 → 사유))
#'   defer = 자격 칸이 하나도 없는데 그 중 규약 판정 탈락이 있다 → 호출자는 이월(hand-off)하지 말고 rebase(P0-06)를 기다린다
#'   (legacy 칸만 가진 entry 를 과도기에 넘겨 버리면 승격 사슬이 영구히 끊긴다 — 정지는 로그로 드러난다).
rf_promote_best <- function(E, ctx) {
  atts <- E$attempts %||% list()
  pts <- vapply(atts, function(a) {
    v <- tryCatch(suppressWarnings(as.numeric((a[["essence"]] %||% list())$port_t)), error = function(e) NA_real_)
    if (length(v) != 1L) NA_real_ else v }, numeric(1))
  meas <- which(is.finite(pts))
  res <- function(i, reason, defer, n_ok, exc) list(i = i, reason = reason, defer = defer, n_measured = length(meas),
                                                    n_eligible = as.integer(n_ok), excluded = exc)
  if (!length(meas)) return(res(NA_integer_, "no_measured_cell", FALSE, 0L, character(0)))
  cov <- (E$carry %||% list())$overlay
  why <- vapply(meas, function(k) {
    f <- rf_candidate_facts(atts[[k]], ctx, RF_ROLE_CHECKS$promote)$fail
    if (length(f)) return(f[1])
    st <- rf_adversary_status(atts[[k]], carry_overlay = cov)
    if (isTRUE(st$ok)) "" else paste0("adversary:", st$status) }, character(1))
  ok <- meas[!nzchar(why)]
  exc <- why[nzchar(why)]
  names(exc) <- vapply(atts[meas[nzchar(why)]], function(a)
    .rfg_s1(tryCatch(.rf_attempt_code(a), error = function(e) NA_character_)), character(1))
  if (!length(ok)) {
    dfr <- any(startsWith(why, "regime_"))
    return(res(NA_integer_, if (dfr) "regime_mismatch" else "no_eligible_cell", dfr, 0L, exc))
  }
  res(ok[which.max(pts[ok])], "ok", FALSE, length(ok), exc)
}

# 등급 사다리 — min="B" 면 {A,B}, min="A" 면 {A}. essence enum 밖 값은 승격 불가.
.rf_promote_grades <- function(min_grade = "B") {
  lad <- c("A", "B", "C", "F")
  i <- match(toupper(min_grade %||% "B"), lad)
  if (is.na(i)) i <- 2L
  lad[seq_len(i)]
}

#' 깊이 상한의 **조건부 연장** — 상한을 깊이가 아니라 게이트 축의 개선으로 옮긴다 (도훈 결정 2026-09-21).
#'   사연·근거 수치는 reinforce_auto_config.json::promote_extend_note 가 정본이다(여기 숫자를 박지 않는다).
#'   판정: 연장 스위치 ON ∧ 깊이 ≤ 하드 상한 ∧ **게이트 축이 부모 대비 min_delta 초과 개선**.
#'   ★부모에 게이트 축 값이 없으면(구판 entry) 연장하지 않는다 — 확인 못 하는 것을 통과시키지 않는다.
rf_promote_extend_ok <- function(entry, best, depth, cfg = list()) {
  if (!isTRUE(cfg$promote_extend_on_gate_axis %||% FALSE)) return(list(ok = FALSE, reason = "depth_cap"))
  hard <- suppressWarnings(as.integer(cfg$promote_max_depth_hard %||% 6L))
  if (!is.finite(hard)) hard <- 6L
  if (as.integer(depth) > hard) return(list(ok = FALSE, reason = "depth_cap_hard"))
  axis <- as.character(cfg$promote_gate_axis %||% "calmar")
  mind <- suppressWarnings(as.numeric(cfg$promote_extend_min_delta %||% 0))
  if (!is.finite(mind)) mind <- 0
  pv <- suppressWarnings(as.numeric((entry$parent %||% list())[[paste0("best_", axis)]] %||% NA_real_))
  bv <- suppressWarnings(as.numeric(best[[axis]] %||% NA_real_))
  if (!is.finite(pv) || !is.finite(bv)) return(list(ok = FALSE, reason = "gate_axis_unknown"))
  if (!((bv - pv) > mind)) return(list(ok = FALSE, reason = "gate_axis_no_improvement"))
  list(ok = TRUE, reason = "ok_extended", axis = axis, delta = bv - pv)
}

#' @param entry 소진된 원장 entry (parent 가 있으면 승격 사슬 중이다)
#' @param best  그 entry 의 최고 셀 요약 (grade · port_t · spec · cell_code)
#' @param cfg   reinforce_auto_config.json (promote_min_grade · promote_max_depth)
#' @return list(ok, reason, depth, new_base_id)
rf_promote_decide <- function(entry, best, cfg = list(), existing_ids = NULL) {
  depth <- as.integer(entry$parent$depth %||% 0L) + 1L
  maxd  <- as.integer(cfg$promote_max_depth %||% 3L)
  nid   <- sprintf("%s_promo%d", sub("_promo[0-9]+$", "", entry$base_id %||% "unknown"), depth)
  out   <- function(ok, reason) list(ok = ok, reason = reason, depth = depth, new_base_id = nid)

  ## ★이미 승격한 entry 는 다시 승격하지 않는다 (2026-09-05 실사고: promo2 가 handed_off 없이 남아
  ##   손자(promo3)가 큐로 넘어간 뒤 매 tick "승격" 을 반복 — rf_open_entry 는 기존 entry 를 조용히
  ##   재사용하므로 로그엔 promoted 가 찍히고 라운드 리뷰 텔레그램이 중복 발송됐다. 큐 논문은 미착수).
  ##   자식 base_id 가 원장에 있으면 승격은 끝난 사건이다 — handed_off 표식과 별개로 여기서도 막는다.
  if (!is.null(existing_ids) && nid %in% as.character(existing_ids)) return(out(FALSE, "child_exists"))
  if (isTRUE(entry$handed_off)) return(out(FALSE, "already_handed_off"))

  if (is.null(best)) return(out(FALSE, "no_measured_cell"))
  if (!((best$grade %||% "") %in% .rf_promote_grades(cfg$promote_min_grade %||% "B")))
    return(out(FALSE, "grade_below_min"))
  ## ★깊이 상한은 더 이상 종점이 아니다 — 게이트 축이 개선 중이면 연장한다(위 rf_promote_extend_ok).
  .ext <- if (depth > maxd) rf_promote_extend_ok(entry, best, depth, cfg) else list(ok = NA)
  if (isFALSE(.ext$ok)) return(out(FALSE, .ext$reason))

  # ★부모를 못 넘은 승격은 같은 실패의 재생산이다 — 25회 상한이 존재하는 이유와 같다.
  pbest <- suppressWarnings(as.numeric(entry$parent$best_port_t %||% NA_real_))
  bp    <- suppressWarnings(as.numeric(best$port_t %||% NA_real_))
  if (is.finite(pbest) && !(is.finite(bp) && bp > pbest))
    return(out(FALSE, "no_improvement_over_parent"))

  # 승자 스펙이 없으면 물려줄 구성을 재구성할 수 없다. 자격 있음과 자격 없음을 구분해 남긴다.
  sp <- best$spec %||% NA_character_
  if (is.na(sp) || !nzchar(sp) || !file.exists(sp)) return(out(FALSE, "winner_spec_missing"))

  out(TRUE, if (isTRUE(.ext$ok)) "ok_extended" else "ok")
}

#' 승격 carry 구성 — 승자 스펙에서 등록부 축(팩터·비중·오버레이·집행 주기·방어 슬리브)을 물려주고 **유니버스는 고정 축으로 리셋**한다.
#'   (도훈 결정 2026-09-05) SKILL §0: B1·B2·B4 의 기본 유니버스는 K200∪KQ150 이고 B3 만 유니버스를 바꾼다.
#'   승자가 B3 칸이면 ws$universe 는 그 블록의 시험 축(예: KQ150 단독 · NAV 2010-02~)이라 그대로 물려주면
#'   다음 세대 25칸이 전부 고정 축 밖에서 돌고, 창이 다른 PORT_t(2.567 vs 2005~ 칸)가 기저가 된다(실사고 promo2 n=17).
#'   승자의 유니버스는 provenance(universe_reset_from)로만 남긴다.
#' ★오버레이 carry 규칙 3종 (2026-09-17 · WP-Z 스택 설계):
#'   ① 상한 — 물려주는 층 수 ≤ max_layers(config b5_design.max_layers · 부재 시 3). 넘치면 **가장 오래된 carry 층부터**
#'      버린다. 스택 순서는 .ov_stack(carry, own) 이라 앞이 조상, 끝이 이 칸의 몫이다 — 최근 것이 곧 이 승자를 만든 처치다.
#'   ② 상주 제외 — program standing_cells 의 overlay_pick(pg2_risk_overlay_v1)은 물려주지 않는다. 상주 칸은 다음 세대에서도
#'      B5 마다 자기 코드로 다시 돌므로, carry 에 실으면 같은 노출을 두 번 곱한다(이중 축소).
#'   ③ 적대검증 — 승자 attempt 에 adversary$verdict 가 **있고** "pass" 가 아니면 그 attempt 의 **자기 층**(overlay_cell ·
#'      없으면 overlay − 부모 carry · 그것도 없으면 B5 칸의 마지막 층)은 물려주지 않는다. 검증에 진 처치를 다음 세대의
#'      바닥으로 깔지 않는다. verdict 가 없는 구 attempt 는 구판 거동 그대로(전부 승계).
#'   ★어느 규칙도 안 걸리면 overlay 는 **입력 그대로**(단수 객체·리스트 형태 불변 — carry 서명이 바뀌지 않는다).
#'   버린 층은 overlay_dropped 에 {kind, arm_id, why} 로 남긴다(조용한 소실 금지 · 러너 로그가 읽는다).
#' @param ws 승자 스펙(list) · cf 팩터 목록 · best 승자 attempt 요약(grade·port_t·spec·cell_code · 선택 adversary) · sp 스펙 경로
#' @param cfg reinforce_auto_config(list) — b5_design$max_layers 를 읽는다(없으면 config 파일 → 3)
#' @param root 저장소 루트(상주 칸·config 읽기) · parent_carry 부모 entry 의 carry$overlay(자기 층 판별 정밀도용 · 선택)
rf_promote_carry <- function(ws, cf, best, sp, cfg = list(), root = .RFP_ROOT(), parent_carry = NULL) {
  ov <- .rfp_carry_overlay(ws, best, cfg, root, parent_carry)
  # ★축 목록 = 등록부(rf_spec_axes.R::rf_axes_promote_carry · 2026-09-26) — 축마다 carry 방식(winner · reset · winner_filtered)을 등록부가 정한다.
  #   집행 주기(B6)·방어 슬리브(B7)는 승계 축이다(winner) — 유니버스처럼 리셋하지 않는다(빠뜨리면 세대마다 월간·슬리브 없음으로 되돌아간다 —
  #   overlay 사고와 동형). 구판도 여기서는 여섯 축을 실었다 — 병은 소비자(러너 carry 병합·B4)가 두 축을 안 읽은 것이었다(같은 등록부로 닫는다).
  #   ★키 순서는 등록부 순서다(구판 factors·weighting·rebalance·defense_sleeve·universe·… → factors·weighting·universe·universe_reset_from·overlay·
  #     rebalance·defense_sleeve) — 값·키 집합은 같다(소비자는 전부 이름으로 읽는다).
  out <- c(rf_axes_promote_carry(ws, cf, ov),
           list(source_cell = best$cell_code %||% "NA", source_spec = sp))
  if (length(ov$dropped)) out$overlay_dropped <- ov$dropped
  out
}

#' 승자 attempt 의 **자기 층** 키 — overlay_cell(정본) > overlay − 부모 carry > B5 칸이면 마지막 층 > 없음(보수)
.rfp_own_keys <- function(ws, best, parent_carry = NULL) {
  if (!is.null(ws$overlay_cell)) return(vapply(.ov_layers(ws$overlay_cell), .ov_key, character(1)))
  keys <- vapply(.ov_layers(ws$overlay), .ov_key, character(1))
  if (!length(keys)) return(character(0))
  if (!is.null(parent_carry)) return(setdiff(keys, vapply(.ov_layers(parent_carry), .ov_key, character(1))))
  if (startsWith(as.character(best$cell_code %||% ""), "B5_")) return(keys[length(keys)])
  character(0)   # B1~B4 승자의 오버레이는 승계분(또는 B5 승자의 것)이지 이 칸의 처치가 아니다 — 판별 불가면 안 버린다
}

.rfp_carry_overlay <- function(ws, best, cfg = list(), root = .RFP_ROOT(), parent_carry = NULL) {
  L <- .ov_layers(ws$overlay)
  if (!length(L)) return(list(overlay = ws$overlay, dropped = list()))
  keys <- vapply(L, .ov_key, character(1))
  aids <- vapply(L, function(z) as.character(z$arm_id %||% ""), character(1))
  why  <- rep("", length(L))
  ## ③ 적대검증 — verdict 가 있고 pass 가 아닐 때만. 구 attempt(verdict 없음)는 손대지 않는다.
  verdict <- as.character((best$adversary %||% list())$verdict %||% "")[1]
  if (nzchar(verdict) && !identical(verdict, "pass")) {
    own <- .rfp_own_keys(ws, best, parent_carry)
    why[keys %in% own] <- paste0("adversary:", verdict)
  }
  ## ② 상주 arm 은 물려주지 않는다
  st <- tryCatch(rfbd_standing_picks(root), error = function(e) character(0))
  why[why == "" & nzchar(aids) & aids %in% st] <- "standing"
  ## ① 상한 — 남은 층이 상한을 넘으면 앞(가장 오래된 carry)부터 버린다
  maxl <- suppressWarnings(as.integer((cfg$b5_design %||% list())$max_layers %||% NA_integer_))[1]
  if (is.na(maxl) || maxl < 1L) maxl <- tryCatch(rfbd_max_layers(root), error = function(e) 3L)
  keep <- which(why == "")
  if (length(keep) > maxl) why[utils::head(keep, length(keep) - maxl)] <- sprintf("cap:%d", maxl)
  if (all(why == "")) return(list(overlay = ws$overlay, dropped = list()))   # 입력 그대로 — 형태·서명 불변
  kept <- L[why == ""]
  dropped <- lapply(which(why != ""), function(i) list(kind = as.character(L[[i]]$kind %||% ""),
                                                        arm_id = aids[i], why = why[i]))
  list(overlay = if (!length(kept)) NULL else if (length(kept) == 1L) kept[[1]] else kept,
       dropped = dropped)
}
