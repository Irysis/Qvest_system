#!/bin/bash

trap 'echo "{}"; exit 0' ERR
#==============================================================================
# ML Cost-aware Audit — PostToolUse[Write] (7 Trends Phase 1.B — Principle 2)
#
# Detect summary_metrics.json writes lacking net_port_sr columns and emit advisory.
# Jensen-Kelly-Malamud-Pedersen (2022 SSRN 4187217) — Net > Gross.
#==============================================================================

INPUT=$(cat)
# (2026-07-24 Fable5 하네스 감사) raw-INPUT 조기-exit — 비-summary_metrics W/E에서 python 파싱 스폰 제거 (superset 필터)
if ! printf '%s' "$INPUT" | grep -q 'summary_metrics\.json'; then echo '{}'; exit 0; fi
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_shared_parse.sh"

if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
  echo '{}'; exit 0
fi

LOG="/tmp/ml_cost_aware_audit.log"

if ! echo "$FILE_PATH" | grep -qE "ml_pipeline.*summary_metrics\.json$|summary_metrics\.json$"; then
  echo '{}'; exit 0
fi

# Heuristic content check: look for net_port_sr column in the written JSON
if echo "$CONTENT" | grep -q '"net_port_sr"'; then
  echo "$(date +%H:%M:%S) COST_AWARE_OK: $FILE_PATH (net_port_sr present)" >> "$LOG"
  echo '{}'; exit 0
fi

echo "$(date +%H:%M:%S) COST_AWARE_ADVISORY: $FILE_PATH lacks net_port_sr field" >> "$LOG"
printf '{}'
exit 0
