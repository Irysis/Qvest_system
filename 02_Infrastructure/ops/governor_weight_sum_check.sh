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

# (2026-07-26) python3 shim — bare `python3` 가 Windows Store 스텁으로 해석되면 빈 출력이 되고,
#   PASS="" 가 되어 **Gate 16 판정이 조용히 무너진다**(게이트 경로라 최우선 수리).
#   존재가 아니라 실행으로 판별. resolve_project.sh source 는 set -e 하에서 위험해 인라인.
PYBIN=""
for _c in "${QVEST_PY:-}" \
          "/c/Users/99922/AppData/Local/Programs/Python/Python312/python.exe" \
          "$(command -v python3 2>/dev/null)" "$(command -v python 2>/dev/null)"; do
  [ -n "$_c" ] || continue
  "$_c" -c 'import sys' >/dev/null 2>&1 && { PYBIN="$_c"; break; }
done
if [ -z "$PYBIN" ]; then
  echo "FAIL: python 인터프리터 해석 불가 — weight_sum 검증 불능 (스텁만 존재 가능). 판정 보류."
  exit 1
fi

# python3로 weight 합산 (jq 한글 경로 버그 회피)
SLOTS_KEY="${SLOTS_PATH#.}"   # leading dot 제거 → "scenario_d_v4_2_composition.slots"
PASS=$("$PYBIN" - "$JSON_FILE" "$SLOTS_KEY" << 'PYEOF'
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
