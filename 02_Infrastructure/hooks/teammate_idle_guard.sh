#!/bin/bash
#==============================================================================
# TeammateIdle Hook — 에이전트가 idle 되려 할 때 inbox 재확인 지시
# exit 0 = idle 허용, exit 2 = 피드백 보내고 계속 작업
#==============================================================================

source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"

INPUT=$(cat)
AGENT=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('teammate_name', d.get('agent_name', '')))
" 2>/dev/null)

# 에이전트 이름 → inbox 매핑
case "$AGENT" in
  *scout*|*Scout*) INBOX="$PROJECT/qepm/mailbox/scout/inbox"
    # Scout: S3/S5 TODO만 체크 (S0_GAP은 Q-Lead가 plan mode Agent로 처리)
    TODO_COUNT=$(ls "$INBOX"/TODO_S3_*.json "$INBOX"/TODO_S5_*.json 2>/dev/null | wc -l)
    ;;
  *forge*|*Forge*) INBOX="$PROJECT/qepm/mailbox/forge/inbox"
    TODO_COUNT=$(ls "$INBOX"/TODO_*.json 2>/dev/null | wc -l)
    ;;
  *judge*|*Judge*) INBOX="$PROJECT/qepm/mailbox/judge/inbox"
    TODO_COUNT=$(ls "$INBOX"/TODO_*.json 2>/dev/null | wc -l)
    ;;
  *governor*|*Governor*) INBOX="$PROJECT/qepm/mailbox/q_lead/inbox"
    TODO_COUNT=$(ls "$INBOX"/TODO_PG0_*.json 2>/dev/null | wc -l)
    ;;
  *) exit 0 ;;
esac

if [ "$TODO_COUNT" -gt 0 ]; then
  echo "inbox에 TODO ${TODO_COUNT}건 남아있습니다. ls ${INBOX}/TODO_*.json 으로 확인하고 처리하세요."
  exit 2
fi

exit 0
