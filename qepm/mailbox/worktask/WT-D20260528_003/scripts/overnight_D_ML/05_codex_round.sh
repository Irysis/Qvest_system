#!/usr/bin/env bash
#==============================================================================
# WT-D20260528_003 Hypothesis D — Codex Critic Round 5-단계
# v6.0 mandate (Charter §10, .claude/rules/codex-round.md)
#
# Flow:
#   1. Draft 작성: alpha_package_draft_D_ML.json (Step 3 emit)
#   2. Codex async spawn (helper script)
#   3. Codex response 검토: codex_critic_response_alpha_D_ML.json
#   4. challenge_note 의무 기록
#   5. Final 작성: alpha_package_D_ML.json (PreToolUse enforcer 통과)
#==============================================================================

set -euo pipefail

PROJ="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID="WT-D20260528_003"
WT_DIR="$PROJ/qepm/mailbox/worktask/$WT_ID"

DRAFT="$WT_DIR/alpha_package_draft_D_ML.json"
OUT="$WT_DIR/codex_critic_response_alpha_D_ML.json"

if [[ ! -f "$DRAFT" ]]; then
  echo "[ERR] Draft not found: $DRAFT" >&2
  exit 1
fi

echo "[Codex Round D-ML] Spawning critic..."
echo "  draft:    $DRAFT"
echo "  output:   $OUT"

bash "$PROJ/02_Infrastructure/tools/debate_helpers/run_codex_qepm_critic.sh" \
  --role=alpha \
  --task_id="$WT_ID" \
  --package="$DRAFT" \
  --output="$OUT"

echo "[Codex Round D-ML] Complete. Response:"
jq -r '.stance, .weakest_assumption, (.critical_concerns | length | tostring + " concerns")' "$OUT" 2>/dev/null || cat "$OUT"
