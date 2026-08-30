#==============================================================================
# test_rf_promote.R — B+ 승격 판정 양방향 검사 (2026-08-30)
#
# 승격 게이트는 두 방향으로 조용히 망가진다 — ①영영 승격 안 함(기능 사망) ②무조건 승격
# (한 논문이 큐 예산을 무한히 먹는다). 둘 다 로그가 조용해서 정상처럼 보인다.
# 그래서 승격/비승격을 **둘 다** 단언한다. 비승격은 사유별로 따로 건다 — 사유가 뭉개지면
# "자격 없어서 안 함" 과 "자격 있는데 못 함(스펙 부재)" 을 구분할 수 없다.
#
# 부작용 없음: 원장·설정 무접촉. 판정 함수는 순수 함수다.
#==============================================================================
source(file.path(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                 "02_Infrastructure/reinforcement/rf_promote.R"))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; writeLines(paste("  FAIL ", m, "—", d)) }
chk <- function(label, got, want_ok, want_reason) {
  if (identical(isTRUE(got$ok), want_ok) && identical(got$reason, want_reason)) ok(label)
  else ng(label, sprintf("ok=%s reason=%s (기대 ok=%s reason=%s)",
                         got$ok, got$reason, want_ok, want_reason))
}

SPEC <- tempfile(fileext = ".json"); writeLines("{}", SPEC)   # 존재하는 승자 스펙
CFG  <- list(promote_min_grade = "B", promote_max_depth = 3)
E0   <- list(base_id = "RP_TEST")                              # 부모 없음(첫 소진)
E3   <- list(base_id = "RP_TEST_promo3", parent = list(depth = 3L, best_port_t = 2.5))
bestB <- list(grade = "B", port_t = 2.24, spec = SPEC, cell_code = "B1_5")

writeLines("=== 승격 (양성 대조) ===")
chk("B등급 + 승자 스펙 존재 + 부모 없음 → 승격", rf_promote_decide(E0, bestB, CFG), TRUE, "ok")
chk("A등급도 승격 대상(루프는 A 에서 안 멈춘다)",
    rf_promote_decide(E0, modifyList(bestB, list(grade = "A")), CFG), TRUE, "ok")
chk("부모 최고치를 넘으면 사슬 연장",
    rf_promote_decide(list(base_id = "X", parent = list(depth = 1L, best_port_t = 1.5)),
                      bestB, CFG), TRUE, "ok")

writeLines("=== 비승격 (위반 주입 — 사유별) ===")
chk("C등급 → 등급 미달", rf_promote_decide(E0, modifyList(bestB, list(grade = "C")), CFG),
    FALSE, "grade_below_min")
chk("F등급 → 등급 미달", rf_promote_decide(E0, modifyList(bestB, list(grade = "F")), CFG),
    FALSE, "grade_below_min")
chk("측정 셀 없음 → no_measured_cell", rf_promote_decide(E0, NULL, CFG), FALSE, "no_measured_cell")
chk("깊이 상한 초과 → depth_cap", rf_promote_decide(E3, bestB, CFG), FALSE, "depth_cap")
chk("부모 최고치 미달 → 같은 실패의 재생산 차단",
    rf_promote_decide(list(base_id = "X", parent = list(depth = 1L, best_port_t = 3.0)),
                      bestB, CFG), FALSE, "no_improvement_over_parent")
chk("부모와 동률도 차단(초과여야 한다)",
    rf_promote_decide(list(base_id = "X", parent = list(depth = 1L, best_port_t = 2.24)),
                      bestB, CFG), FALSE, "no_improvement_over_parent")
chk("승자 스펙 부재 → winner_spec_missing",
    rf_promote_decide(E0, modifyList(bestB, list(spec = "C:/no/such/spec.json")), CFG),
    FALSE, "winner_spec_missing")
chk("설정이 min=A 면 B 는 승격 불가(설정 존중)",
    rf_promote_decide(E0, bestB, list(promote_min_grade = "A", promote_max_depth = 3)),
    FALSE, "grade_below_min")

writeLines("=== 계보 표기 ===")
r <- rf_promote_decide(E0, bestB, CFG)
if (identical(r$new_base_id, "RP_TEST_promo1")) ok("첫 승격 id = _promo1") else
  ng("승격 id", r$new_base_id)
r3 <- rf_promote_decide(list(base_id = "RP_TEST_promo1", parent = list(depth = 1L, best_port_t = 1)),
                        bestB, CFG)
if (identical(r3$new_base_id, "RP_TEST_promo2")) {
  ok("사슬 id 가 중첩되지 않는다(_promo1_promo2 금지)")
} else ng("사슬 id 중첩", r3$new_base_id)

writeLines("")
writeLines(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL))
if (FAIL > 0L) quit(status = 1L)
