#!/bin/bash
# WT-D20260427_001 Iter 17 — Codex R1 critic invocation
# OVERRIDE_005 substitute permitted if Codex CLI stall (per L-207)

set -e
cd "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"

WT_ID="WT-D20260427_001"
PACKAGE_PATH="qepm/mailbox/worktask/${WT_ID}/alpha_package.json"
OUTPUT_PATH="qepm/mailbox/worktask/${WT_ID}/codex_critic_response_alpha.json"

if [ ! -f "$PACKAGE_PATH" ]; then
  echo "ERROR: $PACKAGE_PATH not found" >&2
  exit 1
fi

echo "=== Codex R1 critic invocation (Iter 17) ==="
echo "Package: $PACKAGE_PATH"
echo "Output:  $OUTPUT_PATH"
echo ""

# Try Codex critic with 5-min timeout (CLI stall fallback per L-207)
timeout 300 bash 02_Infrastructure/tools/debate_helpers/run_codex_qepm_critic.sh \
  --role=alpha \
  --task_id="$WT_ID" \
  --package="$PACKAGE_PATH" \
  > "$OUTPUT_PATH.stdout" 2> "$OUTPUT_PATH.stderr"

EXIT_CODE=$?
if [ $EXIT_CODE -eq 124 ]; then
  echo "[CODEX_STALL] timeout 300s — OVERRIDE_005 substitute applies"
  exit 124
elif [ $EXIT_CODE -ne 0 ]; then
  echo "[CODEX_ERROR] exit=$EXIT_CODE"
  exit $EXIT_CODE
fi

echo "[CODEX_OK]"
ls -la "$OUTPUT_PATH"* 2>/dev/null
