#==============================================================================
# direction_world.R — 디렉터 방향 결정의 결과 귀속·채점 (2026-09-21 도훈 승인 플랜 Part 3 · D4)
#
# 세계 = 06_Registry/rf_decisions.jsonl 의 kind="direction" 결정 중 **행동이 실행된 것**(chosen$units 비어 있지 않음) 1건 +
#   그 단위의 실현 결과(L2 원장 attempt · L1 결합 entry 최고 칸). 파일럿(04_Research/meta/axiom_replay)의 격자 리플레이와 달리
#   결정 단위라 접두 재생이 없다 — 대안은 실행되지 않았으므로 반사실이 없다(unreachable). 그래서 채점은 두 축뿐이다:
#   ① 실행 단위의 결과 vs 결정 시점의 프로그램 최고(구속 조건 이동 Δbind) ② 규칙 재현(양성 대조) · 항상-B5 규칙(음성 대조).
# 정직한 한계를 보고서에 그대로 적는다. 등급은 essence 값을 옮길 뿐 재계산하지 않는다(AX-008).
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.dw_num <- function(x) { v <- suppressWarnings(as.numeric(x %||% NA_real_)); if (length(v)) v[1] else NA_real_ }
.dw_chr <- function(x) { v <- suppressWarnings(as.character(x %||% "")); v <- v[!is.na(v)]; if (length(v)) v[1] else "" }
.dw_rj <- function(p) if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL) else NULL
.dw_time <- function(s) { s <- .dw_chr(s); if (!nzchar(s)) return(NA); suppressWarnings(as.POSIXct(substr(s, 1, 19), format = "%Y-%m-%dT%H:%M:%S", tz = "Asia/Seoul")) }

dw_load_decisions <- function(root) {
  p <- file.path(root, "06_Registry/rf_decisions.jsonl"); if (!file.exists(p)) return(list())
  out <- list()
  for (l in readLines(p, warn = FALSE, encoding = "UTF-8")) { if (!nzchar(trimws(l))) next
    r <- tryCatch(fromJSON(l, simplifyVector = FALSE), error = function(e) NULL); if (is.null(r) || !identical(r$kind, "direction")) next
    out[[length(out) + 1L]] <- r }
  out
}
# 실행 단위의 실현 결과 — L2 단위: 결정 이후 첫 L2 attempt(essence 있음) · 지시 결합: 결정 이후 열린 combo entry 의 최고 칸
dw_outcome <- function(dec, root, led1 = NULL, led2 = NULL) {
  u <- (dec$chosen$units %||% list()); if (!length(u)) return(list(kind = "none", status = "no_unit"))
  u <- u[[1]]; kind <- .dw_chr(u$kind); t0 <- .dw_time(dec$at)
  if (identical(kind, "l2_unit")) {
    led2 <- led2 %||% .dw_rj(file.path(root, "06_Registry/reinforce_ledger_l2.json"))
    e <- Filter(function(x) identical(x$base_id, .dw_chr(u$base_id)), led2$entries %||% list()); if (!length(e)) return(list(kind = kind, status = "entry_missing"))
    for (a in e[[1]]$attempts %||% list()) {
      ta <- .dw_time(a$closed_at %||% a$opened_at %||% ""); d0 <- .dw_chr(a$date)
      after <- (!is.na(ta) && !is.na(t0) && ta >= t0) || (nzchar(d0) && !is.na(t0) && d0 >= format(t0, "%Y%m%d"))
      if (!after) next
      es <- a$essence; if (!is.list(es) || !is.finite(.dw_num(es$port_t))) return(list(kind = kind, status = "pending", n = a$n))
      return(list(kind = kind, status = "measured", n = a$n, grade = .dw_chr(a$grade), calmar = .dw_num(es$calmar), port_t = .dw_num(es$port_t),
                  mdd = .dw_num(es$mdd), mc1_delivered = es$mc1_delivered, closed_at = .dw_chr(a$closed_at)))
    }
    return(list(kind = kind, status = "pending"))
  }
  if (identical(kind, "directed_combination")) {
    keys <- as.character(unlist(u$keys %||% list())); if (!length(keys)) return(list(kind = kind, status = "no_keys"))
    setkey <- paste0("combo:", paste(sort(unique(keys)), collapse = "+"))
    led1 <- led1 %||% .dw_rj(file.path(root, "06_Registry/reinforce_ledger_l1.json"))
    e <- Filter(function(x) identical(.dw_chr(x$paper_key), setkey) && { t1 <- .dw_time(x$opened_at); !is.na(t1) && !is.na(t0) && t1 >= t0 }, led1$entries %||% list())
    if (!length(e)) return(list(kind = kind, status = if (isTRUE(u$unreachable)) "unreachable" else "pending", setkey = setkey))
    e <- e[[1]]; best <- NULL
    for (a in e$attempts %||% list()) { es <- a$essence; if (!is.list(es) || !is.finite(.dw_num(es$port_t)) || !is.null(es$inherited_from)) next
      if (is.null(best) || .dw_num(es$port_t) > best$port_t) best <- list(grade = .dw_chr(a$grade), calmar = .dw_num(es$calmar), port_t = .dw_num(es$port_t), mdd = .dw_num(es$mdd), cell = .dw_chr(a$cell_code)) }
    if (is.null(best)) return(list(kind = kind, status = "pending", setkey = setkey, entry_status = .dw_chr(e$status)))
    return(c(list(kind = kind, status = "measured", setkey = setkey, entry_status = .dw_chr(e$status), n_cells = length(e$attempts %||% list())), best))
  }
  list(kind = kind, status = "unknown_kind")
}
dw_build <- function(root) {
  D <- dw_load_decisions(root); led1 <- .dw_rj(file.path(root, "06_Registry/reinforce_ledger_l1.json")); led2 <- .dw_rj(file.path(root, "06_Registry/reinforce_ledger_l2.json"))
  now_best <- .dw_num(((.dw_rj(file.path(root, ".cache/rf_director_latest.json")) %||% list())$program_best %||% list())$calmar)
  rows <- list()
  for (d in D) {
    acted <- length(d$chosen$units %||% list()) > 0L
    o <- if (acted) dw_outcome(d, root, led1, led2) else list(kind = "none", status = "no_action")
    sc <- d$scope %||% list()
    rows[[length(rows) + 1L]] <- list(decision_id = .dw_chr(d$decision_id), at = .dw_chr(d$at), acted = acted, action = .dw_chr(d$chosen$ids[[1]] %||% ""),
      rule = .dw_chr((d$rule %||% list())$branch), binding = .dw_chr(sc$binding), overlay_status = .dw_chr(sc$overlay_status),
      l2_attempts = .dw_num(sc$l2_attempts), pool_n = .dw_num(sc$pool_n), best_calmar_at = .dw_num(sc$program_best_calmar), best_port_t_at = .dw_num(sc$program_best_port_t),
      outcome = o, unit_calmar = .dw_num(o$calmar), unit_port_t = .dw_num(o$port_t), unit_grade = .dw_chr(o$grade),
      d_unit_vs_best_calmar = .dw_num(o$calmar) - .dw_num(sc$program_best_calmar),
      d_program_calmar_since = if (is.finite(now_best) && is.finite(.dw_num(sc$program_best_calmar))) now_best - .dw_num(sc$program_best_calmar) else NA_real_)
  }
  list(rows = rows, now_best_calmar = now_best, n_total = length(D))
}
# 양성 대조: 기록된 피처로 π_dir v0 를 다시 돌리면 같은 행동이 나오는가 (규칙 재현율 = 1.0 이어야 한다)
dw_reproduce <- function(rows, rule_env) {
  if (is.null(rule_env) || !exists("dir_rule_v0", envir = rule_env)) return(list(n = 0L, agree = NA_real_, note = "rf_director 미적재"))
  n <- 0L; agree <- 0L
  for (r in rows) {
    if (!nzchar(r$binding)) next
    if (startsWith(r$rule, "rule0_")) next        # 예산·낡은 입력 게이트는 scope 에 없는 상태(units_today·stale)에 의존 — 재현 대상 아님
    v <- list(binding_condition = r$binding, co_binding = list(), n_lineages_bound = 5L, n_lineages = 5L, revenue_axes_met = !(r$binding %in% c("port_t", "cagr", "sharpe")))
    ov <- list(status = if (nzchar(r$overlay_status)) r$overlay_status else "unmeasured", arms_measured = 25L, adv_pass = 0L, adv_fail = 0L, adv_other = 0L)
    l2 <- list(active_entry = "FR_003", attempts_used = r$l2_attempts, pool_n_now = r$pool_n, pool_n_at_last_run = NA, last_mc1_delivered = NA)
    got <- tryCatch(rule_env$dir_rule_v0(v, ov, l2, list(request_status = "done"), list(n_surviving_binding_class = 0L), list(act = TRUE, max_units_per_day = 1L, min_adversary_n = 10L), 0L, FALSE, list(busy = FALSE))$action, error = function(e) "ERR")
    n <- n + 1L; if (identical(got, r$action)) agree <- agree + 1L
  }
  list(n = n, agree = if (n) agree / n else NA_real_)
}
dw_score <- function(world, min_n = 8L, rule_env = NULL) {
  rows <- world$rows; acted <- Filter(function(r) isTRUE(r$acted), rows); measured <- Filter(function(r) identical(r$outcome$status, "measured"), acted)
  st <- table(vapply(acted, function(r) .dw_chr(r$outcome$status), character(1)))
  md <- function(x) { x <- x[is.finite(x)]; if (length(x)) stats::median(x) else NA_real_ }
  rep <- dw_reproduce(rows, rule_env)
  verdict <- if (length(measured) < min_n) "insufficient" else "report"
  list(verdict = verdict, min_n = min_n, n_decisions = length(rows), n_acted = length(acted), n_measured = length(measured), outcome_status = as.list(st),
       actions = as.list(table(vapply(acted, function(r) r$action, character(1)))),
       unit_grades = as.list(table(vapply(measured, function(r) r$unit_grade, character(1)))),
       d_unit_vs_best_calmar_median = md(vapply(measured, function(r) r$d_unit_vs_best_calmar, numeric(1))),
       d_program_calmar_since_median = md(vapply(measured, function(r) r$d_program_calmar_since, numeric(1))),
       now_best_calmar = world$now_best_calmar,
       mc1_delivered_rate = { v <- vapply(measured, function(r) if (isTRUE(r$outcome$mc1_delivered)) 1 else if (identical(r$outcome$mc1_delivered, FALSE)) 0 else NA_real_, numeric(1)); if (any(is.finite(v))) mean(v, na.rm = TRUE) else NA_real_ },
       controls = list(positive_rule_reproduction = rep,
                       negative_always_b5 = list(note = "항상 B5(오버레이) 규칙의 기대 Δbind = 0 — 반증 pass 0 인 레버는 구속 조건을 못 움직인다(결정 시점 overlay_status 로 확인)",
                                                 n_decisions_with_b5_dead = sum(vapply(rows, function(r) identical(r$overlay_status, "dead"), logical(1)))),
                       unreachable_note = "방향 대안은 실행되지 않았으므로 대안의 결과는 없다(unreachable). 이 채점은 실행 단위의 결과와 규칙 재현만 본다."))
}
dw_report_md <- function(S, tag) {
  c(sprintf("# direction_replay %s — 판정 %s", tag, S$verdict), "",
    sprintf("- 결정 %d · 행동 %d · 결과 측정 %d (최소 %d) · 상태 %s", S$n_decisions, S$n_acted, S$n_measured, S$min_n, paste(sprintf("%s %s", names(S$outcome_status), unlist(S$outcome_status)), collapse = " / ")),
    sprintf("- 행동 분포: %s · 단위 등급: %s", paste(sprintf("%s %s", names(S$actions), unlist(S$actions)), collapse = " / "), paste(sprintf("%s %s", names(S$unit_grades), unlist(S$unit_grades)), collapse = " / ")),
    sprintf("- Δ(단위 Calmar − 결정 시점 프로그램 최고 Calmar) 중앙 %s · Δ(프로그램 최고 Calmar 결정 이후) 중앙 %s · 현재 최고 %s · MC1 전달률 %s",
            format(S$d_unit_vs_best_calmar_median, digits = 3), format(S$d_program_calmar_since_median, digits = 3), format(S$now_best_calmar, digits = 3), format(S$mc1_delivered_rate, digits = 3)),
    sprintf("- 양성 대조(규칙 재현): %s/%s 일치 (%s) · 음성 대조(항상 B5): 기대 Δ 0 · B5 dead 결정 %d", S$controls$positive_rule_reproduction$agree * S$controls$positive_rule_reproduction$n, S$controls$positive_rule_reproduction$n,
            format(S$controls$positive_rule_reproduction$agree, digits = 3), S$controls$negative_always_b5$n_decisions_with_b5_dead),
    sprintf("- %s", S$controls$unreachable_note), "",
    if (identical(S$verdict, "insufficient")) sprintf("> 결과가 붙은 행동 결정이 %d건 미만 — 판정 보류(NO-GO 아님). 규칙 v1 제안·shadow 는 이 수를 채운 뒤(플랜 Part 3 §7).", S$min_n) else "> 판정 가능 — 규칙 v1 후보를 shadow 로 올릴지 promote.R policy tier 가 결정(D5).")
}
