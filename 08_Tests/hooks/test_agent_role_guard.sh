#!/usr/bin/env bash
#==============================================================================
# test_agent_role_guard.sh — Phase 8 dry-run test
# qvest_hook_router.py classify + check-permission behavior 검증.
#==============================================================================

set -uo pipefail

PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(ls -d /mnt/c/Users/*/OneDrive/바탕*화면/Quant_Module_Moltbot 2>/dev/null | head -1)}"
ROUTER="$PROJ_DIR/02_Infrastructure/hooks/qvest_hook_router.py"

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

# ─── classify tests ───
ROLE1=$(python3 "$ROUTER" classify --file-path "/path/qepm/mailbox/worktask/WT-D20260601_001/alpha_package.json" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("role"))' 2>/dev/null)
check "classify_alpha_package_final" "alpha" "$ROLE1"

ROLE2=$(python3 "$ROUTER" classify --file-path "/path/qepm/mailbox/worktask/WT-D20260601_001/optimization_package_draft.json" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("role"))' 2>/dev/null)
check "classify_optimization_draft" "optimizer" "$ROLE2"

ROLE3=$(python3 "$ROUTER" classify --file-path "/path/qepm/mailbox/governor/book_state.json" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("role"))' 2>/dev/null)
check "classify_book_state_governor" "governor" "$ROLE3"

ROLE4=$(python3 "$ROUTER" classify --file-path "/path/qepm/mailbox/worktask/WT-D20260601_001/forge_package_draft.json" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("role"))' 2>/dev/null)
check "classify_forge_draft" "forge" "$ROLE4"

ROLE5=$(python3 "$ROUTER" classify --file-path "/path/qepm/mailbox/worktask/WT-D20260601_001/codex_critic_response_alpha.json" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("role"))' 2>/dev/null)
check "classify_codex_response" "codex_response" "$ROLE5"

ROLE6=$(python3 "$ROUTER" classify --file-path "/path/qepm/mailbox/worktask/WT-D20260601_001/risk_challenge_note.md" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("role"))' 2>/dev/null)
check "classify_role_specific_challenge_note" "challenge_note" "$ROLE6"

# ─── stage tests ───
STAGE1=$(python3 "$ROUTER" classify --file-path "/path/qepm/mailbox/worktask/WT-D20260601_001/risk_package.json" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("stage"))' 2>/dev/null)
check "stage_risk_final" "final" "$STAGE1"

STAGE2=$(python3 "$ROUTER" classify --file-path "/path/qepm/mailbox/worktask/WT-D20260601_001/judge_verdict_draft.json" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("stage"))' 2>/dev/null)
check "stage_judge_draft" "draft" "$STAGE2"

# Summary
echo "=== test_agent_role_guard.sh ==="
for r in "${RESULTS[@]}"; do echo "  $r"; done
echo "TOTAL: $PASS pass / $FAIL fail"

python3 - "$PASS" "$FAIL" <<PYEOF
import json, sys
print(json.dumps({
  "test": "agent_role_guard",
  "pass": int(sys.argv[1]),
  "fail": int(sys.argv[2]),
  "total": int(sys.argv[1]) + int(sys.argv[2])
}))
PYEOF

exit $FAIL
