#!/usr/bin/env bash
#==============================================================================
# v53 Sprint 2 S2.5: Judge Autospawn Hook
# 이벤트: PostToolUse[Write(*/output/hurdle_result.json)]
# 역할:
#   - hurdle_result.json 생성 + 60초 경과 시 대응 s6_validation 존재 확인
#   - 없으면 Judge mailbox에 TODO_S6_REVIEW 생성 (중복 방지)
#   - pipeline_trigger.sh가 해당 TODO를 감지하여 Judge teammate에 라우팅
#
# Monitoring mode — 실제 Judge agent 강제 스폰 X (Q-Lead가 TeamCreate로 위임).
# backward-compat: Judge가 hurdle 직후 바로 s6_validation 작성하는 기존 워크플로 존중.
#==============================================================================

trap 'echo "{}"; exit 0' ERR
set -u

INPUT=$(cat 2>/dev/null || echo '{}')
FILE=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try: print(json.load(sys.stdin).get('tool_input', {}).get('file_path', ''))
except: print('')
" 2>/dev/null)

# hurdle_result.json만 처리
case "$FILE" in
  *hurdle_result.json) ;;
  *) echo '{}'; exit 0 ;;
esac

[ ! -f "$FILE" ] && { echo '{}'; exit 0; }

source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh" 2>/dev/null
[ -z "${PROJECT_ROOT:-}" ] && { echo '{}'; exit 0; }

LOG="/tmp/judge_autospawn.log"

# Grace period: hurdle 생성 직후 60초는 Judge가 자발적 작성 시간
age=$(( $(date +%s) - $(stat -c %Y "$FILE" 2>/dev/null || echo 0) ))
if [ "$age" -lt 60 ]; then
  echo "$(date +%H:%M:%S) GRACE: age=${age}s $FILE" >> "$LOG"
  echo '{}'
  exit 0
fi

# strategy name 추출 (경로에서 STR_XXX 패턴)
STRATEGY=$(echo "$FILE" | grep -oP 'STR_[A-Za-z0-9_]+' | head -1)
if [ -z "$STRATEGY" ]; then
  echo "$(date +%H:%M:%S) SKIP: no STR_ name $FILE" >> "$LOG"
  echo '{}'
  exit 0
fi

# 대응 s6_validation 존재 확인
existing=$(find "$PROJECT_ROOT/stage_artifacts" -maxdepth 1 \
  -name "s6_validation*${STRATEGY}*.json" 2>/dev/null | head -1)
if [ -n "$existing" ]; then
  echo "$(date +%H:%M:%S) SKIP: s6_validation exists for $STRATEGY" >> "$LOG"
  echo '{}'
  exit 0
fi

# Judge inbox에 TODO_S6_REVIEW 생성 (중복 방지)
INBOX="$PROJECT_ROOT/qepm/mailbox/judge/inbox"
mkdir -p "$INBOX" 2>/dev/null
TODO="$INBOX/TODO_S6_REVIEW_${STRATEGY}.json"
if [ -f "$TODO" ]; then
  echo "$(date +%H:%M:%S) SKIP: TODO already exists: $STRATEGY" >> "$LOG"
  echo '{}'
  exit 0
fi

cat > "$TODO" << EOF
{
  "task_type": "S6_REVIEW_TRIGGERED_BY_HURDLE",
  "strategy_id": "$STRATEGY",
  "hurdle_result_path": "$FILE",
  "trigger": "judge_autospawn",
  "created_at": "$(date -Iseconds)",
  "age_at_trigger_seconds": $age,
  "note": "hurdle_result.json 생성 ${age}s 경과. s6_validation 미생성 → Judge 검토 필요."
}
EOF
echo "$(date +%H:%M:%S) SPAWN: TODO_S6_REVIEW_${STRATEGY} (age=${age}s)" >> "$LOG"
echo '{}'
exit 0
