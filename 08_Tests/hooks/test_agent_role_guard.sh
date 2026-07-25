#!/usr/bin/env bash
#==============================================================================
# test_agent_role_guard.sh — Phase 8 dry-run test
# qvest_hook_router.py classify + check-permission behavior 검증.
#==============================================================================

set -uo pipefail

#──────────────────────────────────────────────────────────────────────────────
# (2026-07-25) bare python3 → $QVEST_PY_BIN. PATH의 python3는 Windows Store 스텁이라
# router가 아예 실행되지 않는다 → 전 케이스 actual 공백 → 8/8 FAIL(또는 요약 JSON
# 증발로 러너 집계에서 통째 누락). 정본 해석기 경유.
# (reference-python3-windows-stub-use-qvest-py / _shared_parse.sh HOOK-P0-1)
#
# ★ QVEST_PARSE_TRAP=caller 필수: 미지정 시 _shared_parse.sh가 fail-open ERR trap
#   ('{}' 출력 후 exit 0)을 설치한다 → 실패 케이스가 있는 순간 테스트가 조용히
#   성공 종료. 테스트 하네스는 fail-open을 받아들이면 안 된다.
# ★ 앵커는 PROJ_DIR이 아니라 BASH_SOURCE (PROJ_DIR 오설정 = 이 suite가 보고할 실패).
#──────────────────────────────────────────────────────────────────────────────
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SHARED_PARSE="$_SELF_DIR/../../02_Infrastructure/hooks/_shared_parse.sh"
if [[ -f "$_SHARED_PARSE" ]]; then
  QVEST_PARSE_TRAP=caller
  QVEST_PARSE_RESOLVE_ONLY=1
  # shellcheck source=/dev/null
  source "$_SHARED_PARSE"
  unset QVEST_PARSE_RESOLVE_ONLY QVEST_PARSE_TRAP
else
  _QP="${QVEST_PY:-}"          # set -u 대비 기본값
  QVEST_PY_BIN="${_QP//\\//}"  # 백슬래시 → 슬래시 (Git Bash 실행 호환)
  [[ -x "$QVEST_PY_BIN" ]] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi

# PROJ_DIR 해석 (2026-07-25 수리): 구 폴백 = WSL 전용 glob → 이 머신에선 빈 문자열 →
# ROUTER 경로가 깨져 8/8 FAIL. 후보를 **표지 검증**으로 확인한다(표지 = 실제 소비 대상).
_MARKER="02_Infrastructure/hooks/qvest_hook_router.py"
_pick_proj_dir() {
  local c
  for c in "${CLAUDE_PROJECT_DIR:-}" "${QM_ROOT:-}" "$_SELF_DIR/../.." "$PWD"; do
    if [[ -n "$c" && -f "$c/$_MARKER" ]]; then (cd "$c" && pwd); return 0; fi
  done
  return 1
}
# 해석 실패해도 여기서 죽지 않는다 — PROJ_DIR 오설정은 이 suite 가 *보고해야 할* 실패라,
# 케이스를 전부 FAIL 로 돌리고 요약 JSON 은 반드시 발행해 집계 누락을 막는다.
PROJ_DIR="$(_pick_proj_dir || echo "${CLAUDE_PROJECT_DIR:-}")"
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
ROLE1=$("$QVEST_PY_BIN" "$ROUTER" classify --file-path "/path/qepm/mailbox/worktask/WT-D20260601_001/alpha_package.json" 2>/dev/null | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("role"))' 2>/dev/null)
check "classify_alpha_package_final" "alpha" "$ROLE1"

ROLE2=$("$QVEST_PY_BIN" "$ROUTER" classify --file-path "/path/qepm/mailbox/worktask/WT-D20260601_001/optimization_package_draft.json" 2>/dev/null | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("role"))' 2>/dev/null)
check "classify_optimization_draft" "optimizer" "$ROLE2"

ROLE3=$("$QVEST_PY_BIN" "$ROUTER" classify --file-path "/path/qepm/mailbox/governor/book_state.json" 2>/dev/null | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("role"))' 2>/dev/null)
check "classify_book_state_governor" "governor" "$ROLE3"

ROLE4=$("$QVEST_PY_BIN" "$ROUTER" classify --file-path "/path/qepm/mailbox/worktask/WT-D20260601_001/forge_package_draft.json" 2>/dev/null | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("role"))' 2>/dev/null)
check "classify_forge_draft" "forge" "$ROLE4"

ROLE5=$("$QVEST_PY_BIN" "$ROUTER" classify --file-path "/path/qepm/mailbox/worktask/WT-D20260601_001/codex_critic_response_alpha.json" 2>/dev/null | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("role"))' 2>/dev/null)
check "classify_codex_response" "codex_response" "$ROLE5"

ROLE6=$("$QVEST_PY_BIN" "$ROUTER" classify --file-path "/path/qepm/mailbox/worktask/WT-D20260601_001/risk_challenge_note.md" 2>/dev/null | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("role"))' 2>/dev/null)
check "classify_role_specific_challenge_note" "challenge_note" "$ROLE6"

# ─── stage tests ───
STAGE1=$("$QVEST_PY_BIN" "$ROUTER" classify --file-path "/path/qepm/mailbox/worktask/WT-D20260601_001/risk_package.json" 2>/dev/null | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("stage"))' 2>/dev/null)
check "stage_risk_final" "final" "$STAGE1"

STAGE2=$("$QVEST_PY_BIN" "$ROUTER" classify --file-path "/path/qepm/mailbox/worktask/WT-D20260601_001/judge_verdict_draft.json" 2>/dev/null | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("stage"))' 2>/dev/null)
check "stage_judge_draft" "draft" "$STAGE2"

# Summary
echo "=== test_agent_role_guard.sh ==="
for r in "${RESULTS[@]}"; do echo "  $r"; done
echo "TOTAL: $PASS pass / $FAIL fail"

"$QVEST_PY_BIN" - "$PASS" "$FAIL" <<PYEOF
import json, sys
print(json.dumps({
  "test": "agent_role_guard",
  "pass": int(sys.argv[1]),
  "fail": int(sys.argv[2]),
  "total": int(sys.argv[1]) + int(sys.argv[2])
}))
PYEOF

exit $FAIL
