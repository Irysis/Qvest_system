#!/usr/bin/env bash
# emit_event.sh — v7.0 Sprint 6 Non-blocking event emitter
#
# 모든 hook event 1 row append → qepm/observability/events.jsonl
#
# Codex revised #7 — Non-blocking obligation:
#   - ledger write 실패 시에도 hook 차단 안 함
#   - 항상 exit 0 (failure는 stderr만 log)
#   - 관측성은 guard 아님 — 기록 계층
#
# Usage:
#   bash emit_event.sh <event_type> <hook_name> <decision> [<wt_id>] [<agent_role>] [<latency_ms>] [<file_path>] [<context>]
#
# Plan: nifty-tickling-hinton.md Sprint 6 Step 1.

# Always exit 0 (non-blocking)
trap 'exit 0' ERR

PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
LEDGER="$PROJ_DIR/qepm/observability/events.jsonl"
FAIL_LOG="/tmp/emit_event_fail.log"

EVENT_TYPE="${1:-unknown}"
HOOK_NAME="${2:-unknown}"
DECISION="${3:-allow}"
WT_ID="${4:-}"
AGENT_ROLE="${5:-}"
LATENCY_MS="${6:-0}"
FILE_PATH="${7:-}"
CONTEXT="${8:-}"

TS="$(date -Iseconds 2>/dev/null || date)"

# Build JSON line (single line, append-only)
LINE=$(python3 -c "
import json, sys
d = {
  'timestamp': '$TS',
  'event_type': '$EVENT_TYPE',
  'hook_name': '$HOOK_NAME',
  'decision': '$DECISION',
  'wt_id': '$WT_ID' or None,
  'agent_role': '$AGENT_ROLE' or None,
  'latency_ms': int('$LATENCY_MS') if '$LATENCY_MS'.isdigit() else 0,
  'file_path': '$FILE_PATH' or None,
  'context': '$CONTEXT' or None,
}
print(json.dumps({k: v for k, v in d.items() if v is not None}))
" 2>>"$FAIL_LOG") || {
  echo "[$TS] emit_event compose fail event=$EVENT_TYPE hook=$HOOK_NAME" >> "$FAIL_LOG"
  exit 0
}

# Append (non-blocking)
mkdir -p "$(dirname "$LEDGER")" 2>/dev/null || true
(echo "$LINE" >> "$LEDGER") 2>>"$FAIL_LOG" || true

exit 0
