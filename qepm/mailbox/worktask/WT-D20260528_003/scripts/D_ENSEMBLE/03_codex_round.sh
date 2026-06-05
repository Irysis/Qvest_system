#!/bin/bash
# WT-D20260528_003 / Track 3 — D_ENSEMBLE
# Codex Round 5단계 — Step 1: spawn critic on draft
#
# Usage: bash 03_codex_round.sh
#
# Outputs:
#   qepm/mailbox/worktask/WT-D20260528_003/codex_critic_response_alpha_D_ENSEMBLE.json

set -e
PROJ="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
cd "$PROJ"

DRAFT="$PROJ/qepm/mailbox/worktask/WT-D20260528_003/alpha_package_draft_D_ENSEMBLE.json"
OUTPUT="$PROJ/qepm/mailbox/worktask/WT-D20260528_003/codex_critic_response_alpha_D_ENSEMBLE.json"

if [ ! -f "$DRAFT" ]; then
  echo "[ERROR] draft not found: $DRAFT" >&2
  exit 1
fi

echo "[$(date +%H:%M:%S)] Codex Round spawn — D_ENSEMBLE"
echo "  draft: $DRAFT"
echo "  output: $OUTPUT"

# helper script invocation per CLAUDE.md codex-round.md
bash "$PROJ/02_Infrastructure/tools/debate_helpers/run_codex_qepm_critic.sh" \
  --role=alpha \
  --task_id=WT-D20260528_003 \
  --package="$DRAFT" \
  --output="$OUTPUT"

if [ -f "$OUTPUT" ]; then
  echo "[$(date +%H:%M:%S)] Codex critic response received:"
  python3 -c "
import json
with open('$OUTPUT') as f:
    r = json.load(f)
print(f\"  stance: {r.get('stance', 'UNKNOWN')}\")
print(f\"  concerns: {len(r.get('critical_concerns', []))}\")
high = [c for c in r.get('critical_concerns', []) if c.get('severity') == 'HIGH']
print(f\"  HIGH severity: {len(high)}\")
print(f\"  weakest_assumption: {r.get('weakest_assumption', 'n/a')[:120]}\")
"
else
  echo "[ERROR] codex output not produced" >&2
  exit 1
fi
