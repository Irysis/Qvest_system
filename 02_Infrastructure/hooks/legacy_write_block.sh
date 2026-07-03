#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
# legacy_write_block.sh — v7.0 Sprint 5 Read-only enforcement for legacy assets
#
# 이벤트: PreToolUse[Write|Edit]
# 목적: _archive_v55/ + legacy/ + _archive_4_6/ 디렉토리 수정 시도 차단.
#
# 단순 hook (false positive risk 낮음 — directory 명시 matcher).
# Plan: nifty-tickling-hinton.md Sprint 5 Step 3.

set -euo pipefail
LOG="/tmp/legacy_write_block.log"

# (v8.2.1 2026-07-03 감사 HOOK-P2-1/MC-07, 도훈 confirm) 게이트급 fail-closed:
#   내부 오류(ERR)·stdin 파싱 판별불능 시 무조건 '{}' allow 대신, payload에
#   legacy read-only 패턴(_archive_v55/ · legacy/v55/ · _archive_4_6/)이 잡히면 block.
#   정상 경로 로직은 불변.
_gate_fail_closed() {
  local hay="${FILE_PATH:-}"
  [ -n "$hay" ] || hay="${INPUT:-}"
  if printf '%s' "$hay" | grep -qE '/_archive_v55/|/legacy/v55/|/_archive_4_6/'; then
    echo '{"decision":"block","reason":"LEGACY_WRITE_BLOCKED (fail-closed): hook 내부 오류/판별불능 — legacy read-only 경로 패턴 감지, 검증 불가 시 차단 (v7.0 Hardening 격리 정책)"}'
    echo "[$(date -Iseconds)] HOOK_ERR_TRAP fail-closed BLOCK (legacy pattern in payload)" >> "$LOG" 2>/dev/null || true
  else
    echo '{}'
    echo "[$(date -Iseconds)] HOOK_ERR_TRAP allow (no legacy pattern)" >> "$LOG" 2>/dev/null || true
  fi
  exit 0
}
trap '_gate_fail_closed' ERR

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

# stdin 파싱 판별불능(TOOL·FILE_PATH 동시 공백 = python 파서 실패 —
# PreToolUse[Write|Edit]는 tool_name 상시 존재) → fail-closed 판정
if [[ -z "$TOOL" && -z "$FILE_PATH" ]]; then
  _gate_fail_closed
fi

if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then
  echo '{}'
  exit 0
fi

# Legacy directory matchers
LEGACY_PATTERNS=(
  "/_archive_v55/"
  "/legacy/v55/"
  "/_archive_4_6/"
)

for pattern in "${LEGACY_PATTERNS[@]}"; do
  if [[ "$FILE_PATH" == *"$pattern"* ]]; then
    REASON="LEGACY_WRITE_BLOCKED (v7.0 Sprint 5): $pattern is read-only. v7.0 Hardening 격리 정책. legacy 자산 수정 금지. 수정 필요 시 active path로 신규 작성."
    echo "[$(date -Iseconds)] BLOCKED $TOOL on $FILE_PATH (pattern: $pattern)" >> "$LOG"
    echo "{\"decision\":\"block\",\"reason\":\"$REASON\"}"
    exit 0
  fi
done

echo '{}'
