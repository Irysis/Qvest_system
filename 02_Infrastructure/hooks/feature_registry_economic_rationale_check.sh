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
printf '{}'
exit 0
