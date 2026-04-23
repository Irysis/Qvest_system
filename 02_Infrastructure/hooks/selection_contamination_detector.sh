#!/usr/bin/env bash
# selection_contamination_detector.sh — Lockbox 데이터 오염 차단 (Level 3 hard block)
# v6.1 R2 P2
#
# 이벤트: PreToolUse[Read]
# 목적: Alpha/Risk/Optimizer agent가 lockbox 데이터 접근 시도 시 block
# Judge만 lockbox 읽기 허용.
#
# Lockbox 판별:
#   - 파일 경로에 "lockbox" 포함
#   - stage_artifacts/WT*/lockbox/ 경로
#   - evaluation_windows.lockbox_window 범위 내 날짜

set -euo pipefail
trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

FP_LOWER=$(echo "$FILE_PATH" | tr '[:upper:]' '[:lower:]')

# Lockbox 파일 판별
case "$FP_LOWER" in
  *lockbox*|*stage_artifacts/wt*/lockbox*)
    # Agent 식별
    PARENT_PID=$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ' || echo "0")
    MARKER="/tmp/qvest_current_agent_${PARENT_PID}"
    AGENT_NAME=""
    if [[ -f "$MARKER" ]]; then
      AGENT_NAME=$(cat "$MARKER")
    fi

    case "$AGENT_NAME" in
      judge*)
        # Judge만 허용. Audit trail 기록
        WT_ID=$(echo "$FILE_PATH" | grep -oE 'WT-[DP][0-9]{8}_[0-9]{3}|WT[0-9]{8}_[0-9]{3}' | head -1 || echo "unknown")
        echo "$(date -Iseconds) | judge | $FILE_PATH" >> "/tmp/qvest_lockbox_access_${WT_ID}.log"
        echo '{"decision":"allow","reason":"judge_lockbox_access_logged"}'
        ;;
      alpha*|risk*|optimizer*|opt_*|forge*)
        echo "{\"decision\":\"block\",\"reason\":\"P2 Data Separation 위반: $AGENT_NAME 이 lockbox 데이터 접근 시도 — Judge만 허용. WT 오염 방지.\"}"
        ;;
      *)
        # Q-Lead / unidentified → allow
        echo '{"decision":"allow","reason":"non_research_agent_default_allow"}'
        ;;
    esac
    ;;
  *)
    echo '{"decision":"allow"}'
    ;;
esac
