#!/bin/bash

trap 'echo "{}"; exit 0' ERR
#==============================================================================
# Feature Registry Economic Rationale Check — PreToolUse[Write] (7 Trends P1)
#
# Block writes of feature_registry.json that lack economic_rationale field.
# Factor Zoo 축소 mandate: Validation > Discovery (Harvey-Liu-Zhu 2016).
# advisory level — grace period until next feature cycle migration.
#==============================================================================

INPUT=$(cat)
# (2026-07-24 Fable5 하네스 감사) raw-INPUT 조기-exit — 비-registry W/E에서 python 파싱 스폰 제거 (superset 필터)
if ! printf '%s' "$INPUT" | grep -qE 'feature_registry\.json|factor_registry\.json'; then echo '{}'; exit 0; fi
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_shared_parse.sh"

if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
  echo '{}'; exit 0
fi

LOG="/tmp/feature_registry_economic_rationale.log"

if ! echo "$FILE_PATH" | grep -qE "feature_registry\.json$|factor_registry\.json$"; then
  echo '{}'; exit 0
fi

if echo "$CONTENT" | grep -q '"economic_rationale"'; then
  echo "$(date +%H:%M:%S) RATIONALE_OK: $FILE_PATH" >> "$LOG"
  echo '{}'; exit 0
fi

echo "$(date +%H:%M:%S) RATIONALE_ADVISORY: $FILE_PATH lacks economic_rationale" >> "$LOG"
# (2026-07-24 Fable5 하네스 감사) advisory 실전달 — 라우터 context 채널(additionalContext 단일키) 격상 (종전 '{}' 무전달)
FRC_MSG="[feature_registry_economic_rationale] $FILE_PATH: economic_rationale 필드 부재 — Factor Zoo 축소 mandate(P1). 등재 전 경제 논거 추가 권장." "$QVEST_PY_BIN" -c 'import json,os; print(json.dumps({"additionalContext": os.environ.get("FRC_MSG","")}, ensure_ascii=False))' 2>/dev/null || echo '{}'
exit 0
