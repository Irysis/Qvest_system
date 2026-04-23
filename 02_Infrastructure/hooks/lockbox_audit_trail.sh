#!/usr/bin/env bash
# lockbox_audit_trail.sh — Lockbox 접근 전수 로깅 (Level 2 soft gate)
# v6.1 R2 P2
#
# 이벤트: PostToolUse[Read]
# 목적: lockbox 파일 읽기 발생 시 audit trail 기록
# (block은 selection_contamination_detector.sh가 Pre 단계에서)

set -euo pipefail
trap 'exit 0' ERR

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

FP_LOWER=$(echo "$FILE_PATH" | tr '[:upper:]' '[:lower:]')

case "$FP_LOWER" in
  *lockbox*)
    PARENT_PID=$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ' || echo "0")
    MARKER="/tmp/qvest_current_agent_${PARENT_PID}"
    AGENT=$([ -f "$MARKER" ] && cat "$MARKER" || echo "unknown")
    WT_ID=$(echo "$FILE_PATH" | grep -oE 'WT-[DP][0-9]{8}_[0-9]{3}|WT[0-9]{8}_[0-9]{3}' | head -1 || echo "unknown")

    LOG_FILE="/tmp/qvest_lockbox_access_${WT_ID}.log"
    echo "$(date -Iseconds) | $AGENT | read | $FILE_PATH" >> "$LOG_FILE"
    ;;
esac

exit 0
