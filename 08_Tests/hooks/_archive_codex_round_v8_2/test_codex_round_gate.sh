#!/usr/bin/env bash
#==============================================================================
# test_codex_round_gate.sh — Phase 8 dry-run test
# Codex Round Pre-Enforcer Hook (codex_round_pre_enforcer.sh) behavior 검증.
#
# 시나리오:
#   1. final package direct write (no draft, no critic) → BLOCK 예상
#   2. draft + critic_response present + final write → ALLOW 예상
#   3. waiver (codex_critic_skip_waiver in challenge_note) → ALLOW 예상
#==============================================================================

set -uo pipefail

PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(ls -d /mnt/c/Users/*/OneDrive/바탕*화면/Quant_Module_Moltbot 2>/dev/null | head -1)}"
HOOK="$PROJ_DIR/02_Infrastructure/hooks/codex_round_pre_enforcer.sh"

PASS=0
FAIL=0
RESULTS=()

check() {
  local name="$1"
  local expect="$2"
  local actual="$3"
  if [[ "$actual" == "$expect" ]]; then
    PASS=$((PASS+1))
    RESULTS+=("PASS: $name (expected=$expect)")
  else
    FAIL=$((FAIL+1))
    RESULTS+=("FAIL: $name (expected=$expect actual=$actual)")
  fi
}

# Setup synthetic test WT
TEST_WT="$PROJ_DIR/qepm/mailbox/worktask/WT99990601_999"
mkdir -p "$TEST_WT"
trap 'rm -rf "$TEST_WT"' EXIT

# ─── Test 1: final write WITHOUT draft + critic → BLOCK ───
INPUT1=$(cat <<EOF
{
  "tool_name": "Write",
  "tool_input": {
    "file_path": "$TEST_WT/alpha_package.json",
    "content": "{\"task_id\":\"WT99990601_999\"}"
  }
}
EOF
)
DECISION1=$(echo "$INPUT1" | bash "$HOOK" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("decision","unknown"))' 2>/dev/null || echo "error")
check "test_1_final_no_draft_no_critic" "block" "$DECISION1"

# ─── Test 2: draft + critic present + final write → ALLOW ───
echo '{"task_id":"WT99990601_999","wt_type":"discovery"}' > "$TEST_WT/alpha_package_draft.json"
echo '{"verdict":{"stance":"APPROVE","weakest_assumption":"none"}}' > "$TEST_WT/codex_critic_response_alpha.json"

DECISION2=$(echo "$INPUT1" | bash "$HOOK" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("decision","unknown"))' 2>/dev/null || echo "error")
check "test_2_draft_plus_critic_allow" "allow" "$DECISION2"

# ─── Test 3: waiver (codex_critic_skip_waiver) → ALLOW ───
rm -f "$TEST_WT/alpha_package_draft.json" "$TEST_WT/codex_critic_response_alpha.json"
cat > "$TEST_WT/challenge_note.md" <<EOF
# Test Challenge Note
codex_critic_skip_waiver: 도훈 명시 override (test fixture)
EOF

DECISION3=$(echo "$INPUT1" | bash "$HOOK" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("decision","unknown"))' 2>/dev/null || echo "error")
check "test_3_waiver_allow" "allow" "$DECISION3"

# ─── Summary ───
echo "=== test_codex_round_gate.sh ==="
for r in "${RESULTS[@]}"; do echo "  $r"; done
echo "TOTAL: $PASS pass / $FAIL fail"

# Output JSON for results.json append
python3 - "$PASS" "$FAIL" <<PYEOF
import json, sys
print(json.dumps({
  "test": "codex_round_gate",
  "pass": int(sys.argv[1]),
  "fail": int(sys.argv[2]),
  "total": int(sys.argv[1]) + int(sys.argv[2])
}))
PYEOF

exit $FAIL
