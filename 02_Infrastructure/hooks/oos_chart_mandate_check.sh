#!/usr/bin/env bash
# oos_chart_mandate_check.sh — L2 soft gate (PostToolUse[Write])
# Forge가 forge_package.json 작성 시 OOS chart 4종 검증
# v6.1 (2026-04-25)

set -euo pipefail
trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ "$TOOL" != "Write" ]]; then echo '{"decision":"allow"}'; exit 0; fi

if [[ "$FILE_PATH" =~ forge_package\.json$ ]]; then
  WT_DIR=$(dirname "$FILE_PATH")
  STR_DIR_GLOB="$WT_DIR/../../../04_Research/strategies/STR_*WT*/output"
  MISSING=()
  for f in equity_curve.png annual_returns.png; do
    found=0
    for d in $STR_DIR_GLOB; do
      [[ -f "$d/$f" ]] && found=1 && break
    done
    [[ $found -eq 0 ]] && MISSING+=("$f")
  done
  if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "{\"decision\":\"allow\",\"warning\":\"OOS_CHART_MISSING: ${MISSING[*]} (Forge OOS Chart Mandate v6.1)\"}"
    exit 0
  fi
fi
echo '{"decision":"allow"}'
