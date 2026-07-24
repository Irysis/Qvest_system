#!/usr/bin/env bash
# lockbox_audit_trail.sh — Lockbox 접근 전수 로깅 (Level 2 soft gate)
# v6.1 R2 P2
#
# 이벤트: PostToolUse[Read]
# 목적: lockbox 파일 읽기 발생 시 audit trail 기록
# (block은 selection_contamination_detector.sh가 Pre 단계에서)

set -euo pipefail
trap 'exit 0' ERR

# (v8.2.1 HOOK-P0-1) bare python3 = Windows Store 스텁 → 로깅 무발화 결함 수리.
# 공용 파서(_shared_parse.sh) 경유: FILE_PATH + QVEST_PY_BIN export.
INPUT=$(cat)
# (2026-07-24 Fable5 하네스 감사) raw-INPUT 조기-exit — 비-lockbox Read에서 python 파싱 스폰 제거 (superset 필터)
if ! printf '%s' "$INPUT" | grep -qi 'lockbox'; then exit 0; fi
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_shared_parse.sh"

FP_LOWER=$(echo "$FILE_PATH" | tr '[:upper:]' '[:lower:]')

case "$FP_LOWER" in
  *lockbox*)
    # (v8.2.1 AGT-01) Git Bash ps는 -o 미지원 → $PPID로 이식 (의미 동일: 현 셸의 부모 PID)
    PARENT_PID="${PPID:-0}"
    MARKER="/tmp/qvest_current_agent_${PARENT_PID}"
    AGENT=$([ -f "$MARKER" ] && cat "$MARKER" || echo "unknown")
    # (v8.2.1 HOOK-P1-2) WT-[DP] → WT-[DPSH]: 실제 mailbox 분포 D/S/P/H 반영
    WT_ID=$(echo "$FILE_PATH" | grep -oE 'WT-[DPSH][0-9]{8}_[0-9]{3}|WT[0-9]{8}_[0-9]{3}' | head -1 || echo "unknown")

    LOG_FILE="/tmp/qvest_lockbox_access_${WT_ID}.log"
    echo "$(date -Iseconds) | $AGENT | read | $FILE_PATH" >> "$LOG_FILE"
    ;;
esac

exit 0
