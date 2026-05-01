#!/usr/bin/env bash
#==============================================================================
# run_all_hooks.sh — Phase 8 dry-run test runner
# 모든 hook test 실행 + results.json 생성.
#==============================================================================

set -uo pipefail

PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(ls -d /mnt/c/Users/*/OneDrive/바탕*화면/Quant_Module_Moltbot 2>/dev/null | head -1)}"
TEST_DIR="$PROJ_DIR/08_Tests/hooks"
RESULTS_FILE="$TEST_DIR/results.json"

echo "=== Qvest v6.4 Hook Test Suite ==="
echo "Project: $PROJ_DIR"
echo "Tests dir: $TEST_DIR"
echo "Started: $(date -Iseconds)"
echo ""

ALL_RESULTS=()
TOTAL_PASS=0
TOTAL_FAIL=0

run_test() {
  local name="$1"
  local cmd="$2"
  echo "─── Running: $name ───"
  RESULT=$($cmd 2>&1)
  echo "$RESULT"
  echo ""
  # Extract last JSON line
  JSON=$(echo "$RESULT" | tail -1)
  echo "$JSON" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(f"PARSED|{d.get(\"test\",\"?\")}|{d.get(\"pass\",0)}|{d.get(\"fail\",0)}|{d.get(\"total\",0)}")
except Exception as e:
    print(f"PARSE_ERROR|{e}")
' | while IFS='|' read -r marker test_name pass fail total; do
    if [[ "$marker" == "PARSED" ]]; then
      ALL_RESULTS+=("{\"test\":\"$test_name\",\"pass\":$pass,\"fail\":$fail,\"total\":$total}")
      TOTAL_PASS=$((TOTAL_PASS + pass))
      TOTAL_FAIL=$((TOTAL_FAIL + fail))
    fi
  done
}

# Run all 4 tests
run_test "codex_round_gate" "bash $TEST_DIR/test_codex_round_gate.sh"
run_test "worktask_sequence_gate" "bash $TEST_DIR/test_worktask_sequence_gate.sh"
run_test "agent_role_guard" "bash $TEST_DIR/test_agent_role_guard.sh"
run_test "cert_rules" "Rscript $TEST_DIR/test_cert_rules.R"

# Aggregate (re-extract since subshells don't propagate)
TOTAL_PASS=0
TOTAL_FAIL=0
TESTS_JSON=""
for test_script in test_codex_round_gate.sh test_worktask_sequence_gate.sh test_agent_role_guard.sh test_cert_rules.R; do
  if [[ "$test_script" == *.R ]]; then
    OUT=$(Rscript "$TEST_DIR/$test_script" 2>&1 | tail -1)
  else
    OUT=$(bash "$TEST_DIR/$test_script" 2>&1 | tail -1)
  fi
  if echo "$OUT" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); exit(0 if "test" in d else 1)' 2>/dev/null; then
    PASS=$(echo "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("pass",0))')
    FAIL=$(echo "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("fail",0))')
    TOTAL_PASS=$((TOTAL_PASS + PASS))
    TOTAL_FAIL=$((TOTAL_FAIL + FAIL))
    if [[ -n "$TESTS_JSON" ]]; then TESTS_JSON+=","; fi
    TESTS_JSON+="$OUT"
  fi
done

# Final results JSON
cat > "$RESULTS_FILE" <<EOF
{
  "suite": "qvest_v6_4_hook_dryrun",
  "version": "1.0",
  "ran_at": "$(date -Iseconds)",
  "total_pass": $TOTAL_PASS,
  "total_fail": $TOTAL_FAIL,
  "total": $((TOTAL_PASS + TOTAL_FAIL)),
  "status": "$(if [[ $TOTAL_FAIL -eq 0 ]]; then echo PASS; else echo FAIL; fi)",
  "tests": [$TESTS_JSON]
}
EOF

echo ""
echo "════════════════════════════════════════"
echo "FINAL: $TOTAL_PASS pass / $TOTAL_FAIL fail / $((TOTAL_PASS + TOTAL_FAIL)) total"
if [[ $TOTAL_FAIL -eq 0 ]]; then
  echo "STATUS: ✅ ALL PASS"
else
  echo "STATUS: ❌ FAIL ($TOTAL_FAIL test failures)"
fi
echo "Results: $RESULTS_FILE"
echo "════════════════════════════════════════"

exit $TOTAL_FAIL
