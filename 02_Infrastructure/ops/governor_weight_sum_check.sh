#!/bin/bash
# Governor pre-publish weight_sum assert (Gate 16 — v3.5.4)
# Usage: ./governor_weight_sum_check.sh <json_file> [slots_path]
# Example: ./governor_weight_sum_check.sh governor_rev9.json ".scenario_d.slots"
# Returns: PASS (exit 0) or FAIL (exit 1)

set -euo pipefail

JSON_FILE="${1:-}"
SLOTS_PATH="${2:-.scenario_d_v4_2_composition.slots}"

if [ -z "$JSON_FILE" ] || [ ! -f "$JSON_FILE" ]; then
  echo "Usage: $0 <json_file> [slots_jq_path]"
  echo "  slots_jq_path default: .scenario_d_v4_2_composition.slots"
  exit 1
fi

# python3로 weight 합산 (jq 한글 경로 버그 회피)
SLOTS_KEY="${SLOTS_PATH#.}"   # leading dot 제거 → "scenario_d_v4_2_composition.slots"
PASS=$(python3 - "$JSON_FILE" "$SLOTS_KEY" << 'PYEOF'
import sys, json
json_file, slots_key = sys.argv[1], sys.argv[2]
try:
    with open(json_file, encoding='utf-8') as f:
        d = json.load(f)
    # nested key traversal: "a.b.c" → d["a"]["b"]["c"]
    obj = d
    for k in slots_key.split('.'):
        obj = obj[k]
    weights = [float(s.get('weight', 0)) for s in obj]
    s = sum(weights)
    ok = abs(s - 1.0) < 1e-9
    status = 'PASS' if ok else 'FAIL'
    print(status)
    print(f'  weight_sum = {s:.10f}')
    print(f'  delta = {abs(s-1.0):.2e}')
    print(f'  slots ({len(weights)}): {weights}')
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(2)
PYEOF
)

echo "[Gate16] WEIGHT_SUM_ARITHMETIC_ASSERT"
echo "[Gate16] File: ${JSON_FILE}"
echo "[Gate16] Path: ${SLOTS_PATH}"
echo "$PASS"

# exit code
echo "$PASS" | grep -q "^PASS" && exit 0 || exit 1
