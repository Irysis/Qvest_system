#!/bin/bash
#==============================================================================
# Harness Health Check — v52
# 모든 Hook 정상 작동 여부 검증. /qvest 부트스트랩에서 호출.
#==============================================================================

DIR=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
if [ -z "$DIR" ]; then echo "[HARNESS] PROJECT_ROOT not found"; exit 1; fi

HOOKS_DIR="$DIR/02_Infrastructure/hooks"
SETTINGS="$DIR/.claude/settings.json"
FAIL=0
TOTAL=0
PASS=0

echo "=== Harness Health Check (v52) ==="

# 필수 Hook 파일 목록 (v53 Legacy Cleanup: s0_verdict_validator → s0_verdict_router, s0_debate_chain → s0_debate_enforcer)
REQUIRED_HOOKS=(
  "safety_guard.sh"
  "forge_code_guard.sh"
  "unified_agent_guard.sh"
  "s0_debate_guard.sh"
  "s0_debate_enforcer.sh"
  "s0_verdict_router.sh"
  "artifact_validator.sh"
  "pipeline_trigger.sh"
  "risk_gate.sh"
  "circuit_breaker.sh"
  "teammate_idle_guard.sh"
  "task_complete_guard.sh"
  "axiom_enforcement_hook.sh"
  "harness_health.sh"
  "auto_commit_on_stop.sh"
  "milestone_commit.sh"
)

for HOOK in "${REQUIRED_HOOKS[@]}"; do
  TOTAL=$((TOTAL + 1))
  FPATH="$HOOKS_DIR/$HOOK"
  if [ -f "$FPATH" ]; then
    if [ -x "$FPATH" ]; then
      PASS=$((PASS + 1))
    else
      echo "  [WARN] $HOOK — not executable"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  [FAIL] $HOOK — missing"
    FAIL=$((FAIL + 1))
  fi
done

# settings.json Hook 등록 확인
if [ -f "$SETTINGS" ]; then
  REG_COUNT=$(python3 -c "
import json
with open('$SETTINGS') as f:
    d = json.load(f)
hooks = d.get('hooks', {})
total = sum(len(v) for v in hooks.values())
print(total)
" 2>/dev/null || echo "0")
  echo "  [INFO] settings.json: $REG_COUNT hook entries registered"
else
  echo "  [FAIL] settings.json not found"
  FAIL=$((FAIL + 1))
fi

# ERR trap 확인 (신규 Hook에 필수)
for HOOK in "unified_agent_guard.sh" "circuit_breaker.sh" "s0_debate_guard.sh" "s0_verdict_router.sh" "safety_guard.sh"; do
  FPATH="$HOOKS_DIR/$HOOK"
  if [ -f "$FPATH" ]; then
    if ! grep -q "trap.*ERR\|trap.*err" "$FPATH"; then
      echo "  [WARN] $HOOK — ERR trap missing"
    fi
  fi
done

echo ""
echo "=== Result: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  echo "[HARNESS] $FAIL issues detected. Fix before proceeding."
  exit 1
fi
echo "[HARNESS] All hooks healthy."
exit 0
