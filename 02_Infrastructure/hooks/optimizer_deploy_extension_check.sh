#!/usr/bin/env bash
# optimizer_deploy_extension_check.sh — L2 soft gate (PostToolUse[Write])
# Optimizer가 optimization_package.json 작성 시 deploy schedule 검증
# v6.1 (2026-04-25)
#
# 결함 (Iter 5 사례):
# - alpha PIT cutoff (train end 2023-11-30) → Optimizer가 weights schedule도 2023-12 종료
# - 이후 Forge가 진정한 24-26 OOS 측정 못 함 (frozen weights extension 안 함)
# - Mandate (optimizer-research.md): deploy_cutoff field 명시 + train cutoff와 분리

set -euo pipefail
trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ "$TOOL" != "Write" ]]; then echo '{"decision":"allow"}'; exit 0; fi
if [[ ! "$FILE_PATH" =~ optimization_package\.json$ ]]; then echo '{"decision":"allow"}'; exit 0; fi

CONTENT=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content",""))' 2>/dev/null || echo "")

WARN_MSG=""
if ! echo "$CONTENT" | grep -qE 'deploy_cutoff|deploy_schedule|deploy_end|frozen_extension|deploy_open_ended'; then
  WARN_MSG="DEPLOY_CUTOFF_MISSING: optimization_package.json missing deploy_cutoff field. Mandate v6.1: train cutoff != deploy cutoff. Specify 'open_ended' or actual deploy date."
fi

if [[ -n "$WARN_MSG" ]]; then
  echo "{\"decision\":\"allow\",\"warning\":\"$WARN_MSG\"}"
else
  echo '{"decision":"allow"}'
fi
