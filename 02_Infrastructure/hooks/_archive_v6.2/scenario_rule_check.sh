#!/usr/bin/env bash
# scenario_rule_check.sh — L2 soft gate (PostToolUse[Write])
# Governor가 governor_admission.json 작성 시 scenario rule 일치 검증
# v6.1 (2026-04-25)
#
# 결함 (Iter 5 사례):
# - 사용자 본질 = MEGA_05 upgrade research = Replacement scenario
# - Governor가 Sequential Admission TDC threshold 0.30 적용 → DEFERRED
# - 사용자 거부 후 재평가 — scenario rule misapplication
# - Mandate (governor.md): scenario_identified field + 적용 룰 일치

set -euo pipefail
trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ "$TOOL" != "Write" ]]; then echo '{"decision":"allow"}'; exit 0; fi
if [[ ! "$FILE_PATH" =~ governor_admission\.json$ ]]; then echo '{"decision":"allow"}'; exit 0; fi

CONTENT=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content",""))' 2>/dev/null || echo "")

WARN_MSG=""

if ! echo "$CONTENT" | grep -qE 'scenario_identified|scenario_type|admission_scenario'; then
  WARN_MSG="SCENARIO_NOT_IDENTIFIED: governor_admission.json missing scenario_identified field. Mandate v6.1 requires explicit replacement | sequential_admission | integration."
elif echo "$CONTENT" | grep -qE 'replacement' && echo "$CONTENT" | grep -qE 'tdc.*0\.30|sequential_admission_tdc|tdc_threshold_0\.30'; then
  WARN_MSG="SCENARIO_RULE_MISMATCH: replacement scenario identified BUT Sequential Admission TDC threshold 0.30 applied. Replacement uses direct SR/CAGR/Harvey/DSR comparison, NOT TDC threshold. Iter 5 misapplication pattern."
elif echo "$CONTENT" | grep -qE 'sequential_admission' && ! echo "$CONTENT" | grep -qE 'tdc.*<.*0\.30|tdc_threshold|family_overlap'; then
  WARN_MSG="SCENARIO_RULE_MISMATCH: sequential_admission scenario without TDC threshold check. Mandate v6.1: sequential admission requires TDC < 0.30."
fi

if [[ -n "$WARN_MSG" ]]; then
  echo "{\"decision\":\"allow\",\"warning\":\"$WARN_MSG\"}"
else
  echo '{"decision":"allow"}'
fi
