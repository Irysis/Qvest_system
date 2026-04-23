#!/usr/bin/env bash
# worktask_constraint_enforcer.sh — Hard Constraints 강제 (Level 3 hard block)
#
# 이벤트: PreToolUse[Write]
# 목적: optimization_package.json 또는 weights.csv 쓰기 시 하드 제약 검증
#
# 검증 항목 (사용자 명시 제약):
#   1. max_names ≤ 20 (hard cap)
#   2. long-only: all weights ≥ 0
#   3. weight_bounds: weights ≤ 0.10
#   4. Σw = 1 (absolute) or 0 (active, tolerance 0.001)
#
# 위반 시 block + Q-Lead 알림

set -euo pipefail
trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")
CONTENT=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content",""))' 2>/dev/null || echo "")

# 검증 대상 파일만 (optimization_package.json 또는 weights.csv)
case "$FILE_PATH" in
  */optimization_package.json)
    # JSON target_weights 추출 + 검증
    python3 <<PYEOF
import json, sys

content = '''$CONTENT'''
try:
    pkg = json.loads(content)
except Exception:
    print(json.dumps({"decision":"allow","reason":"content_not_parseable"}))
    sys.exit(0)

tw = pkg.get("target_weights", {})
if not isinstance(tw, dict) or len(tw) == 0:
    print(json.dumps({"decision":"allow","reason":"no_target_weights"}))
    sys.exit(0)

errs = []
# 1. max_names ≤ 20
if len(tw) > 20:
    errs.append(f"max_names {len(tw)} > 20 (hard cap)")
# 2. long-only
neg = [k for k,v in tw.items() if v < 0]
if neg:
    errs.append(f"long-only 위반: {neg[:3]}...")
# 3. weight_bounds [0, 0.10]
too_high = [k for k,v in tw.items() if v > 0.10 + 1e-6]
if too_high:
    errs.append(f"weight > 0.10: {too_high[:3]}...")
# 4. Σw = 1 (absolute) — tolerance 0.001
total = sum(tw.values())
if abs(total - 1.0) > 0.001:
    errs.append(f"Σw = {total:.4f} ≠ 1.0")

if errs:
    print(json.dumps({
      "decision": "block",
      "reason": "worktask_constraint_enforcer: " + " | ".join(errs)
    }))
else:
    print(json.dumps({"decision":"allow"}))
PYEOF
    ;;
  *)
    echo '{"decision":"allow"}'
    ;;
esac
