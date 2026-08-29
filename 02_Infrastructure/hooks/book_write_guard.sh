#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
# book_write_guard.sh — BOOK 정본 직접 편집 차단 (v10 2026-08-29 신설)
#
# 이벤트: PreToolUse[Write|Edit]
# 목적: ① 06_Registry/book/** 직접 편집 차단 — 쓰기는 book_registry.R writer 경유만
#         (등록 자격 검증 A+Judge PASS·append-only 가 writer 안에 있다. 직접 쓰면 우회).
#       ② qepm/mailbox/governor/book_state.json 재기입 차단 — v10 legacy 동결
#         (governor 폐지 — BOOK 이 승계. 사료는 읽기 전용).
# 등록: governor_concord_certifier.sh 의 자리를 승계 (감시 대상이 book_state → BOOK 으로
#   이동했으므로 훅도 함께 이동 — hooks ≤12 예산 유지).
# 검사: 08_Tests/hooks/test_book_write_guard.sh (위반 주입 + 통과 양방향)

set -euo pipefail
LOG="/tmp/book_write_guard.log"

# 게이트급 fail-closed: 판별불능 시 payload 에 BOOK 경로 패턴이 잡히면 block
_gate_fail_closed() {
  local hay="${FILE_PATH:-}"
  [ -n "$hay" ] || hay="${INPUT:-}"
  if printf '%s' "$hay" | grep -qE '06_Registry/book/|qepm/mailbox/governor/book_state\.json'; then
    echo '{"decision":"block","reason":"BOOK_WRITE_BLOCKED (fail-closed): hook 내부 오류/판별불능 — BOOK 정본/legacy book_state 경로 패턴 감지, 검증 불가 시 차단 (v10)"}'
    echo "[$(date -Iseconds)] HOOK_ERR_TRAP fail-closed BLOCK" >> "$LOG" 2>/dev/null || true
  else
    echo '{}'
    echo "[$(date -Iseconds)] HOOK_ERR_TRAP allow (no book pattern)" >> "$LOG" 2>/dev/null || true
  fi
  exit 0
}
trap '_gate_fail_closed' ERR

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ -z "$TOOL" && -z "$FILE_PATH" ]]; then
  _gate_fail_closed
fi

if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then
  echo '{}'
  exit 0
fi

# 정규화 (백슬래시 → 슬래시)
FP_NORM="${FILE_PATH//\\//}"

if [[ "$FP_NORM" == *"06_Registry/book/"* ]]; then
  echo "[$(date -Iseconds)] BLOCKED $TOOL on $FILE_PATH (BOOK direct edit)" >> "$LOG" 2>/dev/null || true
  echo '{"decision":"block","reason":"BOOK_WRITE_BLOCKED (v10): 06_Registry/book/** 은 book_registry.R writer 경유만 쓴다 — register_book_entry(A등급+Judge PASS 검증)/update_book_tracking/set_book_status. 직접 편집은 등록 자격 검증을 우회한다. Rscript -e '"'"'source(\"02_Infrastructure/book/book_registry.R\"); ...'"'"' 를 사용할 것."}'
  exit 0
fi

if [[ "$FP_NORM" == *"qepm/mailbox/governor/book_state.json"* ]]; then
  echo "[$(date -Iseconds)] BLOCKED $TOOL on $FILE_PATH (legacy book_state)" >> "$LOG" 2>/dev/null || true
  echo '{"decision":"block","reason":"BOOK_WRITE_BLOCKED (v10): book_state.json 은 legacy 동결 사료다 (governor 폐지 2026-08-29 — BOOK 이 승계). 현행 정본 = 06_Registry/book/book_registry.json (writer 경유)."}'
  exit 0
fi

echo '{}'
