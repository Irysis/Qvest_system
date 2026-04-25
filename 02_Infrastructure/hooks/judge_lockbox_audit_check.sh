#!/usr/bin/env bash
# judge_lockbox_audit_check.sh — L2 soft gate (PostToolUse[Write])
# Judge가 judge_verdict.json 작성 시 Lockbox 본질 임무 audit 검증
# v6.1 (2026-04-25)
#
# 본질 임무 (judge.md Core Mandate):
# - Lockbox period strategy NAV 측정 강제
# - "unavailable" 단순 처리 = 의무 회피
# - Forge에 frozen weights extension 위임 또는 직접 audit

set -euo pipefail
trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ "$TOOL" != "Write" ]]; then echo '{"decision":"allow"}'; exit 0; fi

if [[ ! "$FILE_PATH" =~ judge_verdict\.json$ ]]; then
  echo '{"decision":"allow"}'; exit 0
fi

CONTENT=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content",""))' 2>/dev/null || echo "")

WARN_MSG=""
if ! echo "$CONTENT" | grep -qE 'lockbox.*(measured|extension|audit|nav|frozen|buy_hold|oos_period)'; then
  WARN_MSG="LOCKBOX_AUDIT_MISSING: judge_verdict.json should reference lockbox period measurement (NAV/extension/audit). Judge core mandate v6.1."
elif echo "$CONTENT" | grep -qE 'lockbox.*(unavailable|N/A|not_available|skip)' && ! echo "$CONTENT" | grep -qE '(forge_extension_requested|frozen_weights_proxy|baseline_same_period_recomputed)'; then
  WARN_MSG="LOCKBOX_DUTY_AVOIDANCE: 'unavailable' marked but no Forge extension / frozen proxy / baseline recompute requested. Judge mandate violation."
fi

if [[ -n "$WARN_MSG" ]]; then
  echo "{\"decision\":\"allow\",\"warning\":\"$WARN_MSG\"}"
else
  echo '{"decision":"allow"}'
fi
