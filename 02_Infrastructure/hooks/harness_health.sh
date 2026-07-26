#!/bin/bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
#==============================================================================
# Harness Health Check — v8.1 (v6.1 kernel absorbed)
# 모든 Hook 정상 작동 여부 검증. /qvest 부트스트랩에서 호출.
#==============================================================================

is_qvest_root() {
  [ -n "$1" ] && [ -d "$1/02_Infrastructure/hooks" ] && [ -f "$1/.claude/settings.json" ]
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DIR=""
for cand in "$CLAUDE_PROJECT_DIR" "$QM_ROOT" "$PWD" "$SCRIPT_DIR/../.."; do
  if is_qvest_root "$cand"; then
    DIR="$(cd "$cand" && pwd -P)"
    break
  fi
done
if [ -z "$DIR" ]; then
  cur="$PWD"
  while [ "$cur" != "/" ]; do
    if is_qvest_root "$cur"; then DIR="$(cd "$cur" && pwd -P)"; break; fi
    cur="$(dirname "$cur")"
  done
fi
if [ -z "$DIR" ]; then echo "[HARNESS] PROJECT_ROOT not found"; exit 1; fi

HOOKS_DIR="$DIR/02_Infrastructure/hooks"
SETTINGS="$DIR/.claude/settings.json"
FAIL=0
TOTAL=0
PASS=0

echo "=== Harness Health Check (v8.1) ==="

# v7.0/v7.1 Required Hooks (v55 legacy archived to _archive_v55/, v7.1-lite Sprint 0.3 동기화)
# v55 legacy 제거: role_taxonomy_admission_gate.sh + cash_sleeve_validator.sh
# 둘 다 .claude/settings.json 등록 0건 (v7.0 Sprint 5 cleanup) → required list에서도 제거
# DEPRECATION.md 참조
REQUIRED_HOOKS=(
  # Tier 1 전역
  "safety_guard.sh"
  "axiom_enforcement_hook.sh"

  # Tier 2 Agent (v8.0 WS5-3 — axiom_context_inject가 unified_agent_guard[v52] 대체. AX 공리 주입)
  "axiom_context_inject.sh"
  "agent_role_guard.sh"

  # v6.1 Work Task 순서 + 제약
  "worktask_sequence_enforcer.sh"
  "worktask_spec_validator.sh"
  "worktask_constraint_enforcer.sh"
  "worktask_artifact_validator.sh"

  # v6.1 R1 Discovery/Deployment
  "discovery_graduation_gate.sh"

  # v6.1 R2 Selection/Test Isolation + Method Shopping
  # (2026-07-24 도훈 승인 C2) selection_contamination_detector.sh = 등록 해제(구조적 상시-allow 실증), FS retain — 목록 제외
  "lockbox_audit_trail.sh"
  "lockbox_post_judge_seal.sh"
  "method_shopping_limiter.sh"

  # v6.1 R3 Challenge Loop
  "challenge_loop_limiter.sh"

  # v6.1 R4 Role-specific Objective
  "role_objective_guard.sh"

  # v6.1 R6 Covariance Freshness
  # (2026-07-24 도훈 승인 C2) covariance_freshness_gate.sh = 등록 해제(advisory 무전달+유물 캐시), FS retain — 목록 제외

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
  # (2026-07-26 부팅감사 수리) Continuity Firewall Stop 게이트 — AX-002 동급 계약(2026-07-15
  # 도훈 mandate)인데 required 목록에 없어 settings.json에서 빠져도 harness_health가 PASS였음
  "research_continuity_guard.sh"

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
# (2026-07-26 부팅감사 수리) 구현 2중 결함: ① open('$SETTINGS')에 MSYS 경로(/c/...)가 박혀
# 네이티브 Windows python이 FileNotFoundError → ② `|| echo "0"` fail-open으로 "0 entries"가
# INFO로 통과. settings.json hooks 블록을 통째로 비워도 부팅 출력이 동일했다(46-hook 침묵사망
# 감지선 단절). 수리 = stdin 전달(경로 번역 무관) + 계측실패/0건 = FAIL(0은 정상 상태가 아니다).
if [ -f "$SETTINGS" ]; then
  REG_COUNT=$(cat "$SETTINGS" | "$QVEST_PY_BIN" -c "
import json, sys
d = json.load(sys.stdin)
hooks = d.get('hooks', {})
total = sum(len(v) for v in hooks.values())
print(total)
" 2>/dev/null || echo "UNREPORTED")
  if [ "$REG_COUNT" = "UNREPORTED" ] || [ "${REG_COUNT:-0}" = "0" ]; then
    echo "  [FAIL] settings.json: hook 등록 계측 실패 또는 0건 (REG_COUNT=$REG_COUNT) — hooks 블록 소실/파서 사망 의심"
    FAIL=$((FAIL + 1))
  else
    echo "  [INFO] settings.json: $REG_COUNT hook entries registered"
  fi
else
  echo "  [FAIL] settings.json not found"
  FAIL=$((FAIL + 1))
fi

# ERR trap 확인 (v6.1 신규 Hook에 필수)
for HOOK in "axiom_context_inject.sh" "circuit_breaker.sh" "safety_guard.sh" \
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
