#!/bin/bash
# ★RETIRED (v10 2026-09-03) — settings.json·라우터 어디에도 등록 이력이 없는 pre-v9 훅.
#   재등록 금지(되살리려면 v10 폐지 개념 분기부터 제거하고 양성/음성 대조를 새로 만들 것). 파일은 사료 존치.
#   governor mailbox 라우팅 — v10 에서 목적지 소멸.
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi

trap 'echo "{}"; exit 0' ERR  # Phase C3 전수 강제
#==============================================================================
# TeammateIdle Hook — 에이전트가 idle 되려 할 때 inbox 재확인 지시
# exit 0 = idle 허용, exit 2 = 피드백 보내고 계속 작업
#==============================================================================

source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"

INPUT=$(cat)
AGENT=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c "
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
