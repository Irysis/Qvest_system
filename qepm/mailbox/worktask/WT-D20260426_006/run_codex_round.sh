#!/usr/bin/env bash
# =============================================================================
# WT-D20260426_006 — Codex Round (Alpha) trigger
# =============================================================================
# Usage: bash run_codex_round.sh
# Runs Codex (GPT-5.5) cross-model critique on alpha_package_draft.json.
# Outputs codex_critic_response_alpha.json.
#
# AX-008 Triangulation: Alpha (Forge view) + Codex (cross-model) + Architect.
# =============================================================================

set -uo pipefail

PROJECT_ROOT="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID="WT-D20260426_006"
WT_DIR="${PROJECT_ROOT}/qepm/mailbox/worktask/${WT_ID}"

DRAFT="${WT_DIR}/alpha_package_draft.json"
OUTPUT="${WT_DIR}/codex_critic_response_alpha.json"

if [[ ! -f "$DRAFT" ]]; then
  echo "[ERR] draft not found: $DRAFT" >&2
  exit 2
fi

cd "$PROJECT_ROOT"

# Codex round (best-effort; agent definition mandates the call but outcome may vary)
bash 02_Infrastructure/tools/debate_helpers/run_codex_qepm_critic.sh \
  --role=alpha \
  --task_id="$WT_ID" \
  --package="$DRAFT" \
  --output="$OUTPUT"

CODEX_EXIT=$?

if [[ $CODEX_EXIT -ne 0 ]]; then
  echo "[WARN] Codex round exit=$CODEX_EXIT — proceeding with NOT_RUN status"
  # Write a fallback JSON so finalize sees no-codex-response gracefully
  if [[ ! -f "$OUTPUT" ]]; then
    cat > "$OUTPUT" <<EOF
{
  "rounds_executed": 0,
  "verdict": "NOT_RUN",
  "stance": "NOT_RUN",
  "weakest_assumption": "Codex helper exit=${CODEX_EXIT}; Discovery WT proceeds with internal-only critique",
  "critical_concerns": [],
  "agree_with_claude": null,
  "note": "Codex round failed gracefully — Discovery WT non-blocking"
}
EOF
  fi
fi

ls -la "$OUTPUT" 2>&1 | head -3
echo "[DONE] codex round artifact: $OUTPUT"
