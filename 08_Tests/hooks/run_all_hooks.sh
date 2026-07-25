#!/usr/bin/env bash
#==============================================================================
# run_all_hooks.sh — Phase 8 dry-run test runner
# 모든 hook test 실행 + results.json 생성.
#==============================================================================

set -uo pipefail

#──────────────────────────────────────────────────────────────────────────────
# (2026-07-25) bare python3 → $QVEST_PY_BIN. PATH의 python3는 Windows Store 스텁이라
# "Python"만 찍고 스크립트를 실행하지 않는다 → 각 suite의 JSON 요약 라인 파싱이 전량
# 실패 → 집계 총계 0이 "✅ ALL PASS"로 위장된다(계측 사망). 정본 해석기 경유.
# (reference-python3-windows-stub-use-qvest-py / _shared_parse.sh HOOK-P0-1)
#
# ★ QVEST_PARSE_TRAP=caller 필수: 미지정 시 _shared_parse.sh가 fail-open ERR trap
#   ('{}' 출력 후 exit 0)을 이 셸에 설치한다 → 이후 아무 명령이나 실패하면 러너가
#   조용히 성공 종료. 바로 이 버그를 고치는 중이므로 trap 설치를 거부한다.
# ★ 앵커는 PROJ_DIR이 아니라 BASH_SOURCE — PROJ_DIR 오설정이야말로 이 suite가
#   보고해야 할 실패라, 그 경우에도 해석기는 살아 있어야 한다.
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

PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(ls -d /mnt/c/Users/*/OneDrive/바탕*화면/Quant_Module_Moltbot 2>/dev/null | head -1)}"
TEST_DIR="$PROJ_DIR/08_Tests/hooks"
# 결과는 재생성 가능한 산출물 → 코드 존(08_Tests) 밖 캐시에 쓴다
# (artifact-storage.md §1·§3, 2026-07-25 도훈 confirm).
RESULTS_DIR="$PROJ_DIR/.cache/test_results"
mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/hook_dryrun_results.json"

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
  RESULT=$(eval "$cmd" 2>&1)
  echo "$RESULT"
  echo ""
  # Extract last JSON line
  JSON=$(echo "$RESULT" | tail -1)
  echo "$JSON" | "$QVEST_PY_BIN" -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print("PARSED|" + str(d.get("test","?")) + "|" + str(d.get("pass",0)) + "|" + str(d.get("fail",0)) + "|" + str(d.get("total",0)))
except Exception as e:
    print("PARSE_ERROR|" + str(e))
' | while IFS='|' read -r marker test_name pass fail total; do
    if [[ "$marker" == "PARSED" ]]; then
      ALL_RESULTS+=("{\"test\":\"$test_name\",\"pass\":$pass,\"fail\":$fail,\"total\":$total}")
      TOTAL_PASS=$((TOTAL_PASS + pass))
      TOTAL_FAIL=$((TOTAL_FAIL + fail))
    fi
  done
}

# Run all 3 tests (codex_round_gate removed v8.2 — Codex Round 폐지)
run_test "worktask_sequence_gate" "bash \"$TEST_DIR/test_worktask_sequence_gate.sh\""
run_test "agent_role_guard" "bash \"$TEST_DIR/test_agent_role_guard.sh\""
run_test "cert_rules" "Rscript \"$TEST_DIR/test_cert_rules.R\""

# Aggregate (re-extract since subshells don't propagate)
TOTAL_PASS=0
TOTAL_FAIL=0
TESTS_JSON=""
UNREPORTED=()
for test_script in test_worktask_sequence_gate.sh test_agent_role_guard.sh test_cert_rules.R; do
  if [[ "$test_script" == *.R ]]; then
    OUT=$(Rscript "$TEST_DIR/$test_script" 2>&1 | tail -1)
  else
    OUT=$(bash "$TEST_DIR/$test_script" 2>&1 | tail -1)
  fi
  if echo "$OUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.loads(sys.stdin.read()); exit(0 if "test" in d else 1)' 2>/dev/null; then
    PASS=$(echo "$OUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("pass",0))')
    FAIL=$(echo "$OUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("fail",0))')
    TOTAL_PASS=$((TOTAL_PASS + PASS))
    TOTAL_FAIL=$((TOTAL_FAIL + FAIL))
    if [[ -n "$TESTS_JSON" ]]; then TESTS_JSON+=","; fi
    TESTS_JSON+="$OUT"
  else
    # 계측 사망 방어 (2026-07-25): 요약 JSON을 못 낸 suite는 "0건 실행"이지 "통과"가
    # 아니다. 종전엔 조용히 skip → 3 suite 전부 누락 시 FINAL 0/0/0이 "✅ ALL PASS"로
    # 보고됐다(이 파일이 고치는 원 버그). 미보고 = 실패로 계상한다.
    UNREPORTED+=("$test_script")
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    echo "⚠ UNREPORTED: $test_script — 요약 JSON 파싱 실패 (마지막 줄: ${OUT:0:120})" >&2
  fi
done

if (( ${#UNREPORTED[@]} > 0 )); then
  echo "⚠ 요약 JSON 미발행 suite ${#UNREPORTED[@]}건: ${UNREPORTED[*]}" >&2
fi

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
