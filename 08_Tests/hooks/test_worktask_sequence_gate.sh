#!/usr/bin/env bash
#==============================================================================
# test_worktask_sequence_gate.sh — Phase 8 dry-run test
# State Machine sm_check_transition + sm_check_artifacts behavior 검증.
#==============================================================================

set -uo pipefail

PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(ls -d /mnt/c/Users/*/OneDrive/바탕*화면/Quant_Module_Moltbot 2>/dev/null | head -1)}"

PASS=0
FAIL=0
RESULTS=()

check() {
  local name="$1"
  local expect="$2"
  local actual="$3"
  if [[ "$actual" == "$expect" ]]; then
    PASS=$((PASS+1))
    RESULTS+=("PASS: $name")
  else
    FAIL=$((FAIL+1))
    RESULTS+=("FAIL: $name (expected=$expect actual=$actual)")
  fi
}

# Test cases via Rscript
RESULT=$(cd "$PROJ_DIR" && Rscript -e '
source("02_Infrastructure/worktask/state_machine.R")
suppressMessages({
  cases <- list(
    list(from="SPEC_APPROVED", to="ALPHA_DONE", expect=TRUE),
    list(from="ALPHA_DONE", to="RISK_DONE", expect=TRUE),
    list(from="RISK_DONE", to="OPTIMIZER_DONE", expect=TRUE),
    list(from="SPEC_APPROVED", to="FORGE_DONE", expect=FALSE),
    list(from="ALPHA_DONE", to="GOVERNOR_ADMITTED", expect=FALSE),
    list(from="COMPLETED", to="ALPHA_DONE", expect=FALSE),
    list(from="OPTIMIZER_DONE", to="FORGE_DONE", expect=TRUE),
    list(from="FORGE_DONE", to="JUDGE_PASSED", expect=TRUE),
    list(from="JUDGE_FAILED", to="FORGE_DONE", expect=TRUE),
    list(from="GOVERNOR_ADMITTED", to="COMPLETED", expect=TRUE)
  )
  for (c in cases) {
    res <- sm_check_transition(c$from, c$to)
    actual <- if (res$allowed) "TRUE" else "FALSE"
    cat(sprintf("CASE|%s_%s|%s|%s\n", c$from, c$to, c$expect, actual))
  }
})
' 2>&1)

while IFS='|' read -r prefix name expect actual; do
  if [[ "$prefix" == "CASE" ]]; then
    check "$name" "$expect" "$actual"
  fi
done <<< "$RESULT"

# Summary
echo "=== test_worktask_sequence_gate.sh ==="
for r in "${RESULTS[@]}"; do echo "  $r"; done
echo "TOTAL: $PASS pass / $FAIL fail"

python3 - "$PASS" "$FAIL" <<PYEOF
import json, sys
print(json.dumps({
  "test": "worktask_sequence_gate",
  "pass": int(sys.argv[1]),
  "fail": int(sys.argv[2]),
  "total": int(sys.argv[1]) + int(sys.argv[2])
}))
PYEOF

exit $FAIL
