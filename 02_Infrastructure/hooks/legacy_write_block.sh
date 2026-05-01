#!/usr/bin/env bash
# legacy_write_block.sh — v7.0 Sprint 5 Read-only enforcement for legacy assets
#
# 이벤트: PreToolUse[Write|Edit]
# 목적: _archive_v55/ + legacy/ + _archive_4_6/ 디렉토리 수정 시도 차단.
#
# 단순 hook (false positive risk 낮음 — directory 명시 matcher).
# Plan: nifty-tickling-hinton.md Sprint 5 Step 3.

set -euo pipefail
LOG="/tmp/legacy_write_block.log"
trap 'echo "[$(date -Iseconds)] HOOK_ERR_TRAP" >> "$LOG"; echo "{\"decision\":\"allow\"}"; exit 0' ERR

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then
  echo '{"decision":"allow"}'
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

echo '{"decision":"allow"}'
