#!/bin/bash
#==============================================================================
# Harness Health Check — v6.1 (2026-04-24)
# 모든 Hook 정상 작동 여부 검증. /qvest 부트스트랩에서 호출.
#==============================================================================

DIR=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
if [ -z "$DIR" ]; then echo "[HARNESS] PROJECT_ROOT not found"; exit 1; fi

HOOKS_DIR="$DIR/02_Infrastructure/hooks"
SETTINGS="$DIR/.claude/settings.json"
FAIL=0
TOTAL=0
PASS=0

echo "=== Harness Health Check (v6.1) ==="

# v7.0/v7.1 Required Hooks (v55 legacy archived to _archive_v55/, v7.1-lite Sprint 0.3 동기화)
# v55 legacy 제거: role_taxonomy_admission_gate.sh + cash_sleeve_validator.sh
# 둘 다 .claude/settings.json 등록 0건 (v7.0 Sprint 5 cleanup) → required list에서도 제거
# DEPRECATION.md 참조
REQUIRED_HOOKS=(
  # Tier 1 전역
  "safety_guard.sh"
  "axiom_enforcement_hook.sh"

  # Tier 2 Agent 경계 (v7.0 — role_taxonomy_admission_gate v55 legacy 제거)
  "unified_agent_guard.sh"
  "agent_role_guard.sh"

  # v6.1 Work Task 순서 + 제약
  "worktask_sequence_enforcer.sh"
  "worktask_spec_validator.sh"
  "worktask_constraint_enforcer.sh"
  "worktask_artifact_validator.sh"

  # v6.1 R1 Discovery/Deployment
  "discovery_graduation_gate.sh"

  # v6.1 R2 Selection/Test Isolation + Method Shopping
  "selection_contamination_detector.sh"
  "lockbox_audit_trail.sh"
  "lockbox_post_judge_seal.sh"
  "method_shopping_limiter.sh"

  # v6.1 R3 Challenge Loop
  "challenge_loop_limiter.sh"

  # v6.1 R4 Role-specific Objective
  "role_objective_guard.sh"

  # v6.1 R6 Covariance Freshness
  "covariance_freshness_gate.sh"

  # v6.1 R11 Lineage + Reproducibility
  "lineage_recorder.sh"
  "reproducibility_validator.sh"

  # v6.1 R12 Forge Transparent Integration
  "forge_integration_audit.sh"

  # Pipeline + Post-Use
  "pipeline_trigger.sh"
  "red_flag_detector.sh"
  "circuit_breaker.sh"
  "teammate_idle_guard.sh"
  "task_complete_guard.sh"

  # Session
  "harness_health.sh"
  "auto_commit_on_stop.sh"
  "milestone_commit.sh"

  # Active retain (v55 호환 — _archive_v55/ 미이동, settings.json 등록 retain)
  "trail_consistency_checker.sh"

  # v7.0 Sprint 5 신규
  "legacy_write_block.sh"
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

# ERR trap 확인 (v6.1 신규 Hook에 필수)
for HOOK in "unified_agent_guard.sh" "circuit_breaker.sh" "safety_guard.sh" \
            "selection_contamination_detector.sh" "method_shopping_limiter.sh" \
            "role_objective_guard.sh" "challenge_loop_limiter.sh" \
            "covariance_freshness_gate.sh" "agent_role_guard.sh"; do
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
