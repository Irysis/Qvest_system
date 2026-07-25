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
# ★ 인라인 `Rscript -e` 다중행 금지 — 한글 포함 state_machine.R source 시 segfault
#   (exit 139, stdout 0) → 케이스 증발 = "0 pass / 0 fail" 위장.
#   .R 파일 경유가 유일한 정본. (reference-rscript-e-korean-segfault)
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES_R="$TEST_DIR/_worktask_sequence_cases.R"

# tr -d '\r': Windows Rscript stdout이 CRLF라 마지막 필드에 \r이 붙어
# "TRUE" != "TRUE\r" 전량 오탐이 난다 (pipefail이라 Rscript rc는 그대로 전파).
RESULT=$(cd "$PROJ_DIR" && Rscript "$CASES_R" 2>&1 | tr -d '\r')
RSCRIPT_RC=$?

while IFS='|' read -r prefix name expect actual; do
  if [[ "$prefix" == "CASE" ]]; then
    check "$name" "$expect" "$actual"
  fi
done <<< "$RESULT"

# 계측 사망 방어: 케이스가 0건이면 성공이 아니라 harness 고장이다.
if (( PASS + FAIL == 0 )); then
  FAIL=$((FAIL+1))
  RESULTS+=("FAIL: harness (0 cases executed — Rscript rc=$RSCRIPT_RC, CASE| 출력 없음)")
  echo "--- Rscript raw output (rc=$RSCRIPT_RC) ---" >&2
  echo "$RESULT" >&2
fi

# Summary
echo "=== test_worktask_sequence_gate.sh ==="
for r in "${RESULTS[@]}"; do echo "  $r"; done
echo "TOTAL: $PASS pass / $FAIL fail"

# bare python3 = Windows Store 스텁("Python" 출력 + exit 9) → JSON 라인 증발로
# run_all_hooks.sh 집계에서 이 suite가 통째로 누락된다. 정본 해석기 경유.
# (reference-python3-windows-stub-use-qvest-py / _shared_parse.sh HOOK-P0-1)
# PROJ_DIR이 아니라 TEST_DIR 기준으로 찾는다 — PROJ_DIR 오설정이야말로 이 suite가
# 보고해야 할 실패라, 그 경우에도 JSON 라인은 나와야 집계에서 누락되지 않는다.
_SHARED_PARSE="$TEST_DIR/../../02_Infrastructure/hooks/_shared_parse.sh"
if [[ -f "$_SHARED_PARSE" ]]; then
  QVEST_PARSE_RESOLVE_ONLY=1
  # shellcheck source=/dev/null
  source "$_SHARED_PARSE"
  unset QVEST_PARSE_RESOLVE_ONLY
else
  _QP="${QVEST_PY:-}"          # set -u 대비 기본값
  QVEST_PY_BIN="${_QP//\\//}"  # 백슬래시 → 슬래시 (Git Bash 실행 호환)
  [[ -x "$QVEST_PY_BIN" ]] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
fi

"$QVEST_PY_BIN" - "$PASS" "$FAIL" <<PYEOF
import json, sys
print(json.dumps({
  "test": "worktask_sequence_gate",
  "pass": int(sys.argv[1]),
  "fail": int(sys.argv[2]),
  "total": int(sys.argv[1]) + int(sys.argv[2])
}))
PYEOF

exit $FAIL
