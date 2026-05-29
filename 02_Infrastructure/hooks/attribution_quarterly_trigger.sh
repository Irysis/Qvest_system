#!/bin/bash

trap 'echo "{}"; exit 0' ERR
#==============================================================================
# Attribution Quarterly Trigger — bootstrap (7 Trends Phase 2.D — Principle 7)
#
# Quarterly automatic Brinson + Carhart 4-factor attribution audit.
# Brinson-Fachler (1985) + Carhart (1997 JoF) + NW (1987) HAC.
# Trigger: bootstrap event when current month ∈ {3, 6, 9, 12} and last_run_quarter < current.
# Output: qepm/observability/attribution/attribution_{quarter}.json
#==============================================================================

LOG="/tmp/attribution_quarterly_trigger.log"
DIR=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
[ -z "$DIR" ] && { echo '{}'; exit 0; }

OUT_DIR="$DIR/qepm/observability/attribution"
mkdir -p "$OUT_DIR"

CURRENT_MONTH=$(date +%m | sed 's/^0//')
CURRENT_YEAR=$(date +%Y)

# Only fire at quarter-end month (3, 6, 9, 12)
case "$CURRENT_MONTH" in
  3|6|9|12) QUARTER="${CURRENT_YEAR}_Q$((($CURRENT_MONTH + 2) / 3))" ;;
  *) echo "$(date +%H:%M:%S) NOT_QUARTER_END: month=$CURRENT_MONTH skip" >> "$LOG"; echo '{}'; exit 0 ;;
esac

LAST_RUN_FILE="$OUT_DIR/.last_attribution_quarter"
if [ -f "$LAST_RUN_FILE" ] && [ "$(cat "$LAST_RUN_FILE")" = "$QUARTER" ]; then
  echo "$(date +%H:%M:%S) ALREADY_RUN: $QUARTER" >> "$LOG"
  echo '{}'; exit 0
fi

ATTR_OUT="$OUT_DIR/attribution_${QUARTER}.json"
echo "$(date +%H:%M:%S) TRIGGER: Attribution audit needed for $QUARTER" >> "$LOG"

# Emit advisory (actual run is monitoring agent's responsibility per L-323 / Phase 2.D)
echo '{}'
exit 0
