#!/usr/bin/env bash
# codex_round_auto_trigger.sh — Tier 6 background spawn Codex critic (L2)
#
# 이벤트: PostToolUse[Write]
# 목적: agent가 *_package_draft.json 작성 시 Codex critic 자동 background spawn
# 무한루프 회피:
#   1. Strict regex — `_draft.json` only (codex_critic_response 제외)
#   2. PID file — 동시 spawn 방지
#   3. Timeout — codex 호출 1200s cap

set -euo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then echo '{}'; exit 0; fi

# Strict regex: only *_package_draft.json (NOT codex_critic_response, NOT bak/tmp/backup)
ROLE=""
if [[ "$FILE_PATH" =~ /alpha_package_draft\.json$ ]]; then ROLE="alpha"
elif [[ "$FILE_PATH" =~ /risk_package_draft\.json$ ]]; then ROLE="risk"
elif [[ "$FILE_PATH" =~ /optimization_package_draft\.json$ ]]; then ROLE="optimizer"
elif [[ "$FILE_PATH" =~ /forge_package_draft\.json$ ]]; then ROLE="forge"
elif [[ "$FILE_PATH" =~ /judge_verdict_draft\.json$ ]]; then ROLE="judge"
elif [[ "$FILE_PATH" =~ /governor_admission_draft\.json$ ]]; then ROLE="governor"
else
  echo '{}'; exit 0
fi

# Exclude result files (infinite loop prevention)
if [[ "$FILE_PATH" =~ codex_critic_response ]]; then
  echo '{}'; exit 0
fi
if [[ "$FILE_PATH" =~ \.(bak|backup|tmp)$ ]]; then
  echo '{}'; exit 0
fi

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot 2>/dev/null | head -1)}}"
HELPER="$PROJECT_ROOT/02_Infrastructure/tools/debate_helpers/run_codex_qepm_critic.sh"
[[ ! -x "$HELPER" ]] && { echo '{}'; exit 0; }

# Extract WT_id from file path
WT_ID=$(echo "$FILE_PATH" | grep -oE 'WT-[DP][0-9]{8}_[0-9]{3}' | head -1)
[[ -z "$WT_ID" ]] && { echo '{}'; exit 0; }

# PID file — prevent concurrent spawn for same (WT_id, role)
PIDFILE="/tmp/codex_round_pid_${WT_ID}_${ROLE}.pid"
if [[ -f "$PIDFILE" ]]; then
  EXISTING_PID=$(cat "$PIDFILE" 2>/dev/null || echo "0")
  if kill -0 "$EXISTING_PID" 2>/dev/null; then
    echo "{}"
    exit 0
  fi
fi

# Background spawn (nohup + timeout)
WT_DIR="$PROJECT_ROOT/qepm/mailbox/worktask/$WT_ID"
DRAFT="$WT_DIR/${ROLE}_package_draft.json"
[[ "$ROLE" == "judge" ]] && DRAFT="$WT_DIR/judge_verdict_draft.json"
[[ "$ROLE" == "governor" ]] && DRAFT="$WT_DIR/governor_admission_draft.json"

OUTPUT="$WT_DIR/codex_critic_response_${ROLE}.json"
LOG="/tmp/codex_round_auto_${WT_ID}_${ROLE}.log"

nohup bash -c "
  CODEX_TIMEOUT=1200 bash '$HELPER' --role='$ROLE' --task_id='$WT_ID' --package='$DRAFT' --output='$OUTPUT' > '$LOG' 2>&1
  rm -f '$PIDFILE'
" > /dev/null 2>&1 &

SPAWN_PID=$!
echo "$SPAWN_PID" > "$PIDFILE"

echo "{}"
