#!/usr/bin/env bash
# sr_provenance_pre_certifier.sh — v1.2 Pre-Write Positive Guide (L2 안내)
#
# Charter §10 Positive Hook 패러다임 — write 직전 4-field 충족 여부 예고.
# 이벤트: PreToolUse[Write|Edit] matcher: forge_package.json
# 동작: 차단 없음. 8 mandatory field 누락 시 positive guidance 메시지로 안내.

set -euo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then echo '{}'; exit 0; fi
if [[ ! "$FILE_PATH" =~ forge_package(_phase[0-9]+)?\.json$ ]]; then echo '{}'; exit 0; fi

CONTENT=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content","") or d.get("tool_input",{}).get("new_string",""))' 2>/dev/null || echo "")

# 8 mandatory fields (Charter §9/§10 PG2 admission grade)
MANDATORY=(
  "task_id"
  "backtest_summary"
  "sr_realized_share_based"
  "measurement_basis_primary"
  "weights_csv_unique_dates_count"
  "alpha_sig_dates_count"
  "schedule_density_ratio"
  "schedule_density_pass"
)

MISSING=()
for FIELD in "${MANDATORY[@]}"; do
  if ! echo "$CONTENT" | grep -qE "\"$FIELD\"\\s*:"; then
    MISSING+=("$FIELD")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  GUIDE_MSG="📋 sr_provenance_certificate 발급 안내: 다음 field 추가 시 자동 발급 (Charter §9/§10): $(IFS=, ; echo "${MISSING[*]}")"
  echo "{}"
else
  echo "{}"
fi
