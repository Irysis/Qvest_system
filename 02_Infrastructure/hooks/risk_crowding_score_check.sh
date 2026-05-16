#!/bin/bash

trap 'echo "{}"; exit 0' ERR
#==============================================================================
# Risk Crowding Score Check — PreToolUse[Write] (7 Trends Phase 2.C — Principle 5)
#
# Verify risk_package.json contains crowding_score_per_factor field.
# Acadian (2026) "Systematic Crowding Monitoring" + Behmaram (2024) demand elasticity.
#==============================================================================

INPUT=$(cat)
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
printf '{"decision":"allow","reason":"[7-Trends P5 ADVISORY] risk_package.json에 crowding_score_per_factor 필드 부재. Acadian 2026 정합 위해 02_Infrastructure/factor_db/crowding_score_per_factor.R::crowding_score_per_factor() 호출 권장 (advisory only, grace period until Phase 2.C 적용 cycle)."}'
exit 0
