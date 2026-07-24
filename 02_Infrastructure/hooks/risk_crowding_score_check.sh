#!/bin/bash

trap 'echo "{}"; exit 0' ERR
#==============================================================================
# Risk Crowding Score Check — PreToolUse[Write] (7 Trends Phase 2.C — Principle 5)
#
# Verify risk_package.json contains crowding_score_per_factor field.
# Acadian (2026) "Systematic Crowding Monitoring" + Behmaram (2024) demand elasticity.
#==============================================================================

INPUT=$(cat)
# (2026-07-24 Fable5 하네스 감사) raw-INPUT 조기-exit — 비-risk_package W/E에서 python 파싱 스폰 제거 (superset 필터)
if ! printf '%s' "$INPUT" | grep -q 'risk_package'; then echo '{}'; exit 0; fi
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_shared_parse.sh"

if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
  echo '{}'; exit 0
fi

LOG="/tmp/risk_crowding_score_check.log"

# Only check risk_package.json (final, no _draft)
if ! echo "$FILE_PATH" | grep -qE "risk_package\.json$" || echo "$FILE_PATH" | grep -qE "_draft\.json$"; then
  echo '{}'; exit 0
fi

if echo "$CONTENT" | grep -q '"crowding_score_per_factor"'; then
  echo "$(date +%H:%M:%S) CROWDING_OK: $FILE_PATH" >> "$LOG"
  echo '{}'; exit 0
fi

echo "$(date +%H:%M:%S) CROWDING_ADVISORY: $FILE_PATH lacks crowding_score_per_factor" >> "$LOG"
# (2026-07-24 Fable5 하네스 감사) advisory 실전달 — 라우터 context 채널(additionalContext 단일키) 격상 (종전 '{}' 무전달)
RCS_MSG="[risk_crowding_score_check] $FILE_PATH: crowding_score_per_factor 필드 부재 — research_philosophy ⑤ Crowding 진단 포함 권장." "$QVEST_PY_BIN" -c 'import json,os; print(json.dumps({"additionalContext": os.environ.get("RCS_MSG","")}, ensure_ascii=False))' 2>/dev/null || echo '{}'
exit 0
