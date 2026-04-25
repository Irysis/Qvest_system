#!/usr/bin/env bash
# forge_baseline_fairness_check.sh — L2 soft gate (PostToolUse[Write])
# Forge가 forge_package.json 작성 시 baseline 비교 fairness 검증
# v6.1 (2026-04-25)
#
# 결함 (Iter 5 사례):
# - mega05_comparison.baseline = SR 1.258 "PG2 documented baseline" (period 불명)
# - 새 strategy (STR_1699) walk-forward 18Y vs documented baseline = unfair
# - Mandate (forge.md): same-period · same-cost · same-DSR-penalty 재측정 의무

set -euo pipefail
trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ "$TOOL" != "Write" ]]; then echo '{"decision":"allow"}'; exit 0; fi
if [[ ! "$FILE_PATH" =~ forge_package\.json$ ]]; then echo '{"decision":"allow"}'; exit 0; fi

CONTENT=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content",""))' 2>/dev/null || echo "")

WARN_MSG=""
if echo "$CONTENT" | grep -qE 'mega05_comparison|baseline.*comparison'; then
  if ! echo "$CONTENT" | grep -qE '(same_period|same_cost|same_dsr_penalty|baseline_recomputed|fair_comparison)'; then
    WARN_MSG="BASELINE_FAIRNESS_MISSING: baseline comparison missing same-period/cost/DSR-penalty evidence. Mandate v6.1: 'PG2 documented baseline' insufficient — recompute baseline on identical period/cost/penalty basis."
  elif echo "$CONTENT" | grep -qE 'documented_baseline|cor_assumed' && ! echo "$CONTENT" | grep -qE 'baseline_recomputed_same_period'; then
    WARN_MSG="BASELINE_FAIRNESS_PROXY: documented baseline or cor_assumed used without same-period recomputation. Mandate v6.1 requires fair comparison."
  fi
fi

if [[ -n "$WARN_MSG" ]]; then
  echo "{\"decision\":\"allow\",\"warning\":\"$WARN_MSG\"}"
else
  echo '{"decision":"allow"}'
fi
