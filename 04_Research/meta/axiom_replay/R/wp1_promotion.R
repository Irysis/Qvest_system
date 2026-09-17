# wp1_promotion.R — 승격 게이트 문턱 재채점 (사전등록 §2.1)
#
# 질문: 승격 여유 문턱 m 을 두었다면 칸을 얼마나 아끼고 프로그램 최고 PORT_t 를 얼마나 잃었나.
# 규칙 두 판을 잰다.
#   current : 현행 코드 그대로 — 개선 검사는 parent$best_port_t 가 있을 때만 (깊이 1 은 무검사)
#   uniform : 시작점 대비 개선을 균일 요구 — 깊이 1 은 그 entry 의 **충실구현 기저 PORT_t** 를 시작점으로
#
# ★막힌 승격의 자손은 기록에 있으므로 제거 효과를 셀 수 있다.
# ★현행이 이미 막은 승격(promote_skipped)의 자식은 존재하지 않는다 — 평가 불가(unreachable).

source("R/ledger_io.R")

.wp1_base_port_t <- function(base_artifacts, cache = new.env(parent = emptyenv())) {
  key <- .ar_chr(base_artifacts)
  if (is.na(key) || !nzchar(key)) return(NA_real_)
  if (!is.null(cache[[key]])) return(cache[[key]])
  p <- file.path(key, "authoritative_remeasure.json")
  v <- NA_real_
  if (file.exists(p)) {
    j <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(j)) v <- .ar_num(j$essence$portfolio_alpha_t_nw_lag3)
  }
  cache[[key]] <- v
  v
}

#' 승격 사건 표 — 사건 1행 = 부모가 소진되며 자식을 낳은 결정 1회
wp1_events <- function(ent, att) {
  cache <- new.env(parent = emptyenv())
  ent$base_port_t <- vapply(ent$base_artifacts, .wp1_base_port_t, numeric(1), cache = cache)
  kids <- ent[!is.na(ent$parent_id), , drop = FALSE]
  rows <- list()
  for (i in seq_len(nrow(kids))) {
    k  <- kids[i, ]
    pi <- match(k$parent_id, ent$base_id)
    if (is.na(pi)) next
    P  <- ent[pi, ]
    # bp = 부모의 최고 (원장 기록) · 교차검증용으로 attempts 에서 재도출한 값도 같이 둔다
    bp_rec <- k$parent_best
    bp_cmp <- P$best_port_t
    pbest  <- P$parent_best                      # 부모의 부모 최고 — 현행 규칙의 비교 기준
    start_u <- if (is.finite(pbest)) pbest else P$base_port_t   # 균일 규칙의 시작점
    desc <- c(k$base_id, ar_descendants(ent, k$base_id))
    di   <- match(desc, ent$base_id)
    rows[[length(rows) + 1L]] <- data.frame(
      event_id    = sprintf("%s->%s", P$base_id, k$base_id),
      parent_id   = P$base_id, child_id = k$base_id,
      depth       = k$parent_depth,
      bp_recorded = bp_rec, bp_computed = bp_cmp,
      pbest       = pbest, base_port_t = P$base_port_t, start_uniform = start_u,
      child_best  = k$best_port_t,
      payoff      = k$best_port_t - bp_rec,
      subtree_n   = length(desc),
      subtree_cells   = sum(ent$n_cells[di], na.rm = TRUE),
      subtree_minutes = sum(ent$minutes[di], na.rm = TRUE),
      stringsAsFactors = FALSE)
  }
  do.call(rbind, rows)
}

#' 문턱 m 하에서 사라지는 entry 집합 — 깊이 순으로 전파(부모가 막히면 자손 전부 소멸)
.wp1_removed <- function(ev, ent, rule, m) {
  removed <- character(0)
  for (d in sort(unique(ev$depth))) {
    e <- ev[ev$depth == d, , drop = FALSE]
    for (i in seq_len(nrow(e))) {
      if (e$parent_id[i] %in% removed) next            # 이미 사라진 가지
      ref <- if (identical(rule, "current")) e$pbest[i] else e$start_uniform[i]
      if (!is.finite(ref)) next                        # 기준 없음 = 검사 없음(현행 깊이1)
      bp <- e$bp_recorded[i]
      blocked <- !(is.finite(bp) && bp > ref + m)
      if (blocked) removed <- unique(c(removed, e$child_id[i],
                                       ar_descendants(ent, e$child_id[i])))
    }
  }
  removed
}

wp1_sweep <- function(ent, att, margins = c(0, 0.10, 0.25, 0.50, 0.75),
                      rules = c("current", "uniform")) {
  prog_best_all <- max(att$port_t[att$measured], na.rm = TRUE)
  ev <- wp1_events(ent, att)
  out <- list()
  for (rule in rules) for (m in margins) {
    rm_ids <- .wp1_removed(ev, ent, rule, m)
    keep   <- att[!(att$base_id %in% rm_ids), , drop = FALSE]
    pb     <- if (any(keep$measured)) max(keep$port_t[keep$measured], na.rm = TRUE) else NA_real_
    ci     <- ent$base_id %in% rm_ids
    out[[length(out) + 1L]] <- data.frame(
      rule = rule, margin = m,
      n_blocked_entries = length(rm_ids),
      cells_saved   = sum(ent$n_cells[ci], na.rm = TRUE),
      minutes_saved = sum(ent$minutes[ci], na.rm = TRUE),
      program_best  = pb,
      best_loss     = prog_best_all - pb,
      stringsAsFactors = FALSE)
  }
  list(events = ev, sweep = do.call(rbind, out), program_best = prog_best_all)
}
