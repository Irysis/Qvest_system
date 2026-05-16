#!/bin/bash

trap 'echo "{}"; exit 0' ERR
#==============================================================================
# ML Uncertainty Audit — PostToolUse[Write] (7 Trends Phase 1.A — Principle 3)
#
# Detect predictions.parquet writes lacking CI extension and emit advisory warning.
# Liao-Ma-Neuhierl-Schilling (2025) RFS — CI > Point Estimate.
#==============================================================================

INPUT=$(cat)
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_shared_parse.sh"

# Post-write events on predictions.parquet
if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
  echo '{}'; exit 0
fi

LOG="/tmp/ml_uncertainty_audit.log"

# Only check on predictions.parquet writes (final ML cycle output)
if ! echo "$FILE_PATH" | grep -qE "ml_pipeline.*predictions\.parquet$|predictions\.parquet$"; then
  echo '{}'; exit 0
fi

# Skip if predictions_with_ci.parquet exists alongside
DIR_OF_FILE=$(dirname "$FILE_PATH" 2>/dev/null)
if [ -f "$DIR_OF_FILE/predictions_with_ci.parquet" ]; then
  echo "$(date +%H:%M:%S) UNCERTAINTY_OK: $FILE_PATH (CI extension present)" >> "$LOG"
  echo '{}'; exit 0
fi

echo "$(date +%H:%M:%S) UNCERTAINTY_ADVISORY: $FILE_PATH lacks predictions_with_ci.parquet" >> "$LOG"
printf '{"decision":"allow","reason":"[7-Trends P3 ADVISORY] predictions.parquet에 CI extension (predictions_with_ci.parquet) 부재. Liao 2025 RFS Phase 1.A 정합 위해 run_ml_cycle.py --enable-uncertainty 권장 (advisory only, grace period)."}'
exit 0
