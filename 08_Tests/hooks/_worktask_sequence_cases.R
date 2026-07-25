#==============================================================================
# _worktask_sequence_cases.R — test_worktask_sequence_gate.sh 의 R 절반
#
# state_machine.R 의 sm_check_transition() 전이 10건을 실행하고
# `CASE|<name>|<expect>|<actual>` 라인을 stdout 에 낸다.
# 이 stdout 계약을 test_worktask_sequence_gate.sh 의 `while IFS='|' read` 가 소비한다.
#
# ★ 인라인 `Rscript -e '...'` 다중행 형태 금지 — 한글 포함 소스를 source 하면
#   segfault(exit 139, stdout 0)로 케이스가 통째로 증발해 "0 pass / 0 fail" 위장.
#   반드시 .R 파일 경유. (reference-rscript-e-korean-segfault, 2026-07-25 수리)
#
# cwd = PROJECT_ROOT 전제 (caller 가 cd 후 호출).
#==============================================================================

SM_PATH <- "02_Infrastructure/worktask/state_machine.R"
if (!file.exists(SM_PATH)) {
  stop(sprintf("[worktask_sequence_cases] state_machine.R not found from cwd=%s (expected %s)",
               getwd(), SM_PATH))
}
source(SM_PATH)

cases <- list(
  list(from = "SPEC_APPROVED",     to = "ALPHA_DONE",        expect = TRUE),
  list(from = "ALPHA_DONE",        to = "RISK_DONE",         expect = TRUE),
  list(from = "RISK_DONE",         to = "OPTIMIZER_DONE",    expect = TRUE),
  list(from = "SPEC_APPROVED",     to = "FORGE_DONE",        expect = FALSE),
  list(from = "ALPHA_DONE",        to = "GOVERNOR_ADMITTED", expect = FALSE),
  list(from = "COMPLETED",         to = "ALPHA_DONE",        expect = FALSE),
  list(from = "OPTIMIZER_DONE",    to = "FORGE_DONE",        expect = TRUE),
  list(from = "FORGE_DONE",        to = "JUDGE_PASSED",      expect = TRUE),
  list(from = "JUDGE_FAILED",      to = "FORGE_DONE",        expect = TRUE),
  list(from = "GOVERNOR_ADMITTED", to = "COMPLETED",         expect = TRUE)
)

suppressMessages({
  for (tc in cases) {
    res <- sm_check_transition(tc$from, tc$to)
    actual <- if (isTRUE(res$allowed)) "TRUE" else "FALSE"
    cat(sprintf("CASE|%s_%s|%s|%s\n", tc$from, tc$to, tc$expect, actual))
  }
})
