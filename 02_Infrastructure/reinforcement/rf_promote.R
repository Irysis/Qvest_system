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

# 등급 사다리 — min="B" 면 {A,B}, min="A" 면 {A}. essence enum 밖 값은 승격 불가.
.rf_promote_grades <- function(min_grade = "B") {
  lad <- c("A", "B", "C", "F")
  i <- match(toupper(min_grade %||% "B"), lad)
  if (is.na(i)) i <- 2L
  lad[seq_len(i)]
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
  if (depth > maxd) return(out(FALSE, "depth_cap"))

  # ★부모를 못 넘은 승격은 같은 실패의 재생산이다 — 25회 상한이 존재하는 이유와 같다.
  pbest <- suppressWarnings(as.numeric(entry$parent$best_port_t %||% NA_real_))
  bp    <- suppressWarnings(as.numeric(best$port_t %||% NA_real_))
  if (is.finite(pbest) && !(is.finite(bp) && bp > pbest))
    return(out(FALSE, "no_improvement_over_parent"))

  # 승자 스펙이 없으면 물려줄 구성을 재구성할 수 없다. 자격 있음과 자격 없음을 구분해 남긴다.
  sp <- best$spec %||% NA_character_
  if (is.na(sp) || !nzchar(sp) || !file.exists(sp)) return(out(FALSE, "winner_spec_missing"))

  out(TRUE, "ok")
}

#' 승격 carry 구성 — 승자 스펙에서 팩터·비중·오버레이만 물려주고 **유니버스는 고정 축으로 리셋**한다.
#'   (도훈 결정 2026-09-05) SKILL §0: B1·B2·B4 의 기본 유니버스는 K200∪KQ150 이고 B3 만 유니버스를 바꾼다.
#'   승자가 B3 칸이면 ws$universe 는 그 블록의 시험 축(예: KQ150 단독 · NAV 2010-02~)이라 그대로 물려주면
#'   다음 세대 25칸이 전부 고정 축 밖에서 돌고, 창이 다른 PORT_t(2.567 vs 2005~ 칸)가 기저가 된다(실사고 promo2 n=17).
#'   승자의 유니버스는 provenance(universe_reset_from)로만 남긴다.
#' @param ws 승자 스펙(list) · cf 팩터 목록 · best 승자 attempt 요약 · sp 스펙 경로
rf_promote_carry <- function(ws, cf, best, sp) {
  list(factors = cf %||% list(), weighting = ws$weighting,
       universe = list(kind = "k200_kq150"),
       universe_reset_from = ws$universe,
       overlay = ws$overlay,
       source_cell = best$cell_code %||% "NA", source_spec = sp)
}
