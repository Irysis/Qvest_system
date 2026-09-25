#==============================================================================
# policy_state.R — 방향 규칙(정책) 상태기계 (2026-09-21 도훈 승인 플랜 Part 3 · D5)
#
#   proposed → shadow → live → demoted(→shadow) → tombstoned
#   도훈 결정(2026-09-21 ①): live 는 **shadow N주 뒤 자동** — 조건: shadow ≥ shadow_min_weeks ∧ 유익한 불일치 ≥ informative_min
#     ∧ 최신 세계 재리플레이 승 ∧ placebo 통과 ∧ 상한(live per kind ≤1 · 총 ≤2 · 주간 활성화 ≤1). 되돌리기 경로 항상 동봉.
#   강등: 최신 m 트리 중 k 패(demote_k_of_m) → shadow · 8주 안 2회 강등 → tombstoned(재제안 SKIP · 해제 = 도훈).
#   킬스위치: QVEST_RF_POLICY=off → live 전이 금지(기존 live 는 즉시 π₀ · 상태는 유지) · QVEST_POLICY_UNATTENDED=0 → 자동 live 금지(제안만).
#   순수 함수 — 파일을 읽거나 쓰지 않는다(배선은 promote.R policy tier · rf_axiom_activate.R --tree policies: D5 잔여).
#   모든 문턱은 cfg 로 받는다(기본값 = 플랜 Part 3 §4.5/§4.6 · 출처 표기). 여기 수치를 박지 않는다.
#==============================================================================
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
POL_STATES <- c("proposed", "shadow", "live", "demoted", "tombstoned")
pol_cfg <- function(c0 = list()) list(
  shadow_min_weeks = as.integer(c0$shadow_min_weeks %||% 4L),             # 도훈 2026-09-21 ① "shadow 4주 이상"
  informative_min = as.integer(c0$informative_disagreements_min %||% 3L), # 도훈 2026-09-21 ① "유익한 불일치 3건 이상"
  max_live_per_kind = as.integer(c0$max_live_per_kind %||% 1L),          # 플랜 §4.5 .TIER$policy
  max_live_total = as.integer(c0$max_live_total %||% 2L),
  weekly_activation_max = as.integer(c0$weekly_activation_max %||% 1L),
  demote_k = as.integer((c0$demote_k_of_m %||% c(3L, 5L))[1]), demote_m = as.integer((c0$demote_k_of_m %||% c(3L, 5L))[2]),
  tombstone_demotions = as.integer(c0$tombstone_demotions %||% 2L), tombstone_window_weeks = as.integer(c0$tombstone_window_weeks %||% 8L),
  heldout_win_min = as.numeric(c0$heldout_win_min %||% 0.60),             # 파일럿 §3 GO 바 (proposed→shadow)
  null_percentile_min = as.numeric(c0$null_percentile_min %||% 0.95),
  discovery_drop_max = as.numeric(c0$discovery_drop_max %||% 0.10),
  unreachable_max = as.numeric(c0$unreachable_max %||% 0.20),
  best_loss_max = as.numeric(c0$best_loss_max %||% 0.05))
# stats 필드(채점기가 채운다): heldout_win, null_pct, discovery_drop, unreachable, best_loss, peek_blocked, static_clean, negative_control_ok,
#   shadow_weeks, informative_disagreements, newest_replay_win, placebo_ok, recent_losses(최신 m 트리 중 패 수), demotions_8w,
#   live_same_kind(현재 live 수 · 같은 kind), live_total, activations_this_week
# ★2026-09-24 도훈 결정 DIR-ABSORB-ITEMS ④: 자동 live 기본 OFF — 소유가 P1-07(선택 연산자 리플레이)로 옮겨졌고,
#   P1-07 은 'QVEST_POLICY_UNATTENDED=0 강제 · live 는 도훈 confirm 후'를 요구한다. 구 기본 "1"(자동 live)은
#   운영 호출자 0 인 채 잠복해 있었다. 켜려면 환경변수를 명시적으로 "1" 로.
pol_env <- function() list(rf_policy_off = identical(Sys.getenv("QVEST_RF_POLICY", ""), "off"),
                           unattended = identical(Sys.getenv("QVEST_POLICY_UNATTENDED", "0"), "1"))
.pol_ok <- function(x) isTRUE(x)
pol_gate_shadow <- function(st, cfg) {
  why <- character(0)
  if (!isTRUE(.n(st$heldout_win) >= cfg$heldout_win_min)) why <- c(why, sprintf("held-out 승률 %s < %s", .f(st$heldout_win), cfg$heldout_win_min))
  if (!isTRUE(.n(st$null_pct) >= cfg$null_percentile_min)) why <- c(why, sprintf("귀무 백분위 %s < %s", .f(st$null_pct), cfg$null_percentile_min))
  if (!isTRUE(.n(st$discovery_drop) <= cfg$discovery_drop_max)) why <- c(why, sprintf("발견률 하락 %s > %s", .f(st$discovery_drop), cfg$discovery_drop_max))
  if (!isTRUE(.n(st$unreachable) <= cfg$unreachable_max)) why <- c(why, sprintf("unreachable %s > %s", .f(st$unreachable), cfg$unreachable_max))
  if (!isTRUE(.n(st$best_loss) <= cfg$best_loss_max)) why <- c(why, sprintf("프로그램 최고 손실 %s > %s", .f(st$best_loss), cfg$best_loss_max))
  for (k in c("peek_blocked", "static_clean", "negative_control_ok")) if (!.pol_ok(st[[k]])) why <- c(why, sprintf("%s 미통과", k))
  list(ok = !length(why), why = why)
}
pol_gate_live <- function(st, cfg, env = pol_env()) {
  why <- character(0)
  if (isTRUE(env$rf_policy_off)) why <- c(why, "QVEST_RF_POLICY=off — live 전이 금지")
  if (!isTRUE(env$unattended)) why <- c(why, "QVEST_POLICY_UNATTENDED=0 — 자동 live 금지(도훈 승인 필요)")
  if (!isTRUE(.n(st$shadow_weeks) >= cfg$shadow_min_weeks)) why <- c(why, sprintf("shadow %s주 < %d", .f(st$shadow_weeks), cfg$shadow_min_weeks))
  if (!isTRUE(.n(st$informative_disagreements) >= cfg$informative_min)) why <- c(why, sprintf("유익한 불일치 %s < %d", .f(st$informative_disagreements), cfg$informative_min))
  if (!.pol_ok(st$newest_replay_win)) why <- c(why, "최신 세계 재리플레이 패")
  if (!.pol_ok(st$placebo_ok)) why <- c(why, "플라시보 미통과")
  if (!isTRUE(.n(st$live_same_kind) < cfg$max_live_per_kind)) why <- c(why, sprintf("같은 kind live %s ≥ %d", .f(st$live_same_kind), cfg$max_live_per_kind))
  if (!isTRUE(.n(st$live_total) < cfg$max_live_total)) why <- c(why, sprintf("live 총 %s ≥ %d", .f(st$live_total), cfg$max_live_total))
  if (!isTRUE(.n(st$activations_this_week) < cfg$weekly_activation_max)) why <- c(why, sprintf("주간 활성화 %s ≥ %d (회로차단기)", .f(st$activations_this_week), cfg$weekly_activation_max))
  list(ok = !length(why), why = why)
}
pol_gate_demote <- function(st, cfg) {
  lost <- .n(st$recent_losses); if (!is.finite(lost)) return(list(demote = FALSE, why = "최신 재리플레이 결과 없음"))
  list(demote = lost >= cfg$demote_k, why = sprintf("최신 %d 트리 중 %s 패 (강등 문턱 %d)", cfg$demote_m, .f(lost), cfg$demote_k))
}
#' @return list(from, to, reason, undo) — undo 는 되돌리기 명령 문자열(텔레그램 동봉용)
pol_transition <- function(state, st, cfg = pol_cfg(), env = pol_env(), policy_id = "POL-?") {
  state <- match.arg(state, POL_STATES)
  undo <- sprintf("Rscript -e 'source(\"02_Infrastructure/axiom/promote.R\"); deactivate_policy(\"%s\", \"undo\")' · 즉시 정지 = QVEST_RF_POLICY=off", policy_id)
  if (identical(state, "tombstoned")) return(list(from = state, to = state, reason = "tombstoned — 재제안 SKIP · 해제 = 도훈 clear_tombstone", undo = ""))
  if (identical(state, "proposed")) { g <- pol_gate_shadow(st, cfg)
    return(list(from = state, to = if (g$ok) "shadow" else "proposed", reason = if (g$ok) "proposed→shadow 바 전항 통과" else paste(g$why, collapse = " · "), undo = "")) }
  if (identical(state, "shadow")) {
    if (isTRUE(.n(st$demotions_8w) >= cfg$tombstone_demotions)) return(list(from = state, to = "tombstoned", reason = sprintf("%d주 내 강등 %s회 ≥ %d", cfg$tombstone_window_weeks, .f(st$demotions_8w), cfg$tombstone_demotions), undo = ""))
    g <- pol_gate_live(st, cfg, env)
    return(list(from = state, to = if (g$ok) "live" else "shadow", reason = if (g$ok) "shadow→live 자동(도훈 2026-09-21 ①) — 조건 전항 통과" else paste(g$why, collapse = " · "), undo = if (g$ok) undo else "")) }
  if (identical(state, "live")) {
    if (isTRUE(env$rf_policy_off)) return(list(from = state, to = "live", reason = "QVEST_RF_POLICY=off — 집행은 π₀(상태 유지)", undo = undo))
    d <- pol_gate_demote(st, cfg)
    return(list(from = state, to = if (d$demote) "demoted" else "live", reason = d$why, undo = undo)) }
  if (identical(state, "demoted")) {
    if (isTRUE(.n(st$demotions_8w) >= cfg$tombstone_demotions)) return(list(from = state, to = "tombstoned", reason = sprintf("%d주 내 강등 %s회 ≥ %d → tombstone", cfg$tombstone_window_weeks, .f(st$demotions_8w), cfg$tombstone_demotions), undo = ""))
    return(list(from = state, to = "shadow", reason = "강등 → shadow 복귀(재검증 대기)", undo = "")) }
  list(from = state, to = state, reason = "no-op", undo = "")
}
.n <- function(x) { v <- suppressWarnings(as.numeric(x %||% NA_real_)); if (length(v)) v[1] else NA_real_ }
.f <- function(x) { v <- .n(x); if (is.finite(v)) format(v, digits = 3) else "NA" }
