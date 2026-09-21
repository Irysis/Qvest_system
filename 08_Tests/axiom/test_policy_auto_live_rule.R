#!/usr/bin/env Rscript
#==============================================================================
# test_policy_auto_live_rule.R — 정책 상태기계 (2026-09-21 플랜 Part 3 · D5)
#   양방향 검사: 조건 전부 충족일 때만 전이가 일어나고, 조건 하나만 빠져도 막힌다(각 조건별 돌연변이).
#   proposed→shadow 바 · shadow→live 자동(도훈 ①: 4주·불일치 3·재리플레이·플라시보·상한) · 킬스위치 2종 · live→demoted(3/5) ·
#   강등 2회/8주 → tombstoned · tombstoned 불변 · 되돌리기 명령 동봉.
#==============================================================================
ROOT <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"policy_auto_live_rule","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', PASS, FAIL, PASS + FAIL)); quit(status = if (FAIL == 0L) 0L else 1L) }
source(file.path(ROOT, "02_Infrastructure/axiom/replay/policy_state.R"))
cfg <- pol_cfg(); env_on <- list(rf_policy_off = FALSE, unattended = TRUE)
good_shadow <- list(heldout_win = 0.65, null_pct = 0.97, discovery_drop = 0.05, unreachable = 0.10, best_loss = 0.0, peek_blocked = TRUE, static_clean = TRUE, negative_control_ok = TRUE)
t <- pol_transition("proposed", good_shadow, cfg, env_on)
if (identical(t$to, "shadow")) ok("proposed→shadow: 바 전항 통과") else ng("proposed→shadow", t$reason)
for (k in c("heldout_win", "null_pct", "discovery_drop", "unreachable", "best_loss", "peek_blocked", "static_clean", "negative_control_ok")) {
  m <- good_shadow; m[[k]] <- if (is.logical(m[[k]])) FALSE else if (k %in% c("heldout_win", "null_pct")) 0.3 else 0.5
  t <- pol_transition("proposed", m, cfg, env_on)
  if (identical(t$to, "proposed")) ok(sprintf("proposed 돌연변이 %s → 막힘", k)) else ng(sprintf("proposed 돌연변이 %s 통과됨", k)) }
good_live <- list(shadow_weeks = 4, informative_disagreements = 3, newest_replay_win = TRUE, placebo_ok = TRUE, live_same_kind = 0, live_total = 1, activations_this_week = 0, demotions_8w = 0)
t <- pol_transition("shadow", good_live, cfg, env_on, "POL-T")
if (identical(t$to, "live") && grepl("deactivate_policy", t$undo, fixed = TRUE) && grepl("QVEST_RF_POLICY=off", t$undo, fixed = TRUE)) ok("shadow→live 자동 · 되돌리기 명령 동봉") else ng("shadow→live", t$reason)
muts <- list(shadow_weeks = 3, informative_disagreements = 2, newest_replay_win = FALSE, placebo_ok = FALSE, live_same_kind = 1, live_total = 2, activations_this_week = 1)
for (k in names(muts)) { m <- good_live; m[[k]] <- muts[[k]]; t <- pol_transition("shadow", m, cfg, env_on)
  if (identical(t$to, "shadow")) ok(sprintf("shadow 돌연변이 %s=%s → 막힘", k, muts[[k]])) else ng(sprintf("shadow 돌연변이 %s 통과됨", k)) }
t <- pol_transition("shadow", good_live, cfg, list(rf_policy_off = TRUE, unattended = TRUE))
if (identical(t$to, "shadow") && grepl("QVEST_RF_POLICY=off", t$reason, fixed = TRUE)) ok("킬스위치 QVEST_RF_POLICY=off → live 금지") else ng("킬스위치 1", t$reason)
t <- pol_transition("shadow", good_live, cfg, list(rf_policy_off = FALSE, unattended = FALSE))
if (identical(t$to, "shadow") && grepl("UNATTENDED", t$reason, fixed = TRUE)) ok("킬스위치 QVEST_POLICY_UNATTENDED=0 → 자동 live 금지") else ng("킬스위치 2", t$reason)
t <- pol_transition("live", list(recent_losses = 3), cfg, env_on); if (identical(t$to, "demoted")) ok("live: 최신 5 중 3 패 → demoted") else ng("강등", t$reason)
t <- pol_transition("live", list(recent_losses = 2), cfg, env_on); if (identical(t$to, "live")) ok("live: 2 패 → 유지") else ng("강등 음성", t$reason)
t <- pol_transition("live", list(recent_losses = NA), cfg, env_on); if (identical(t$to, "live")) ok("live: 재리플레이 결과 없음 → 유지(강등 근거 없음)") else ng("강등 NA", t$reason)
t <- pol_transition("live", list(recent_losses = 3), cfg, list(rf_policy_off = TRUE, unattended = TRUE)); if (identical(t$to, "live") && grepl("π₀", t$reason)) ok("live + RF_POLICY=off: 집행은 π₀ · 상태 유지") else ng("off 집행", t$reason)
t <- pol_transition("demoted", list(demotions_8w = 1), cfg, env_on); if (identical(t$to, "shadow")) ok("demoted(1회) → shadow 복귀") else ng("복귀", t$reason)
t <- pol_transition("demoted", list(demotions_8w = 2), cfg, env_on); if (identical(t$to, "tombstoned")) ok("demoted(8주 내 2회) → tombstoned") else ng("tombstone", t$reason)
t <- pol_transition("tombstoned", good_live, cfg, env_on); if (identical(t$to, "tombstoned")) ok("tombstoned 불변(해제 = 도훈)") else ng("tombstone 불변", t$reason)
c2 <- pol_cfg(list(shadow_min_weeks = 6)); t <- pol_transition("shadow", good_live, c2, env_on); if (identical(t$to, "shadow")) ok("문턱은 cfg 로만(6주 설정 시 4주는 막힘)") else ng("cfg 문턱")
finish()
