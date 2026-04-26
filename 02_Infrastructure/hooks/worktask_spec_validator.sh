#!/usr/bin/env bash
# worktask_spec_validator.sh — Work Task Spec 검증 (Level 3 hard block)
#
# 이벤트: PreToolUse[Write]
# 목적: qepm/mailbox/worktask/WT*/request.json 쓰기 시 schema 검증
#
# 검증 항목:
#   - task_id 형식 (^WT[0-9]{8}_[0-9]{3}$)
#   - universe_definition.label allowed list
#   - hard_constraints.max_names ≤ 20
#   - data_lag_rules 필수 필드 4종

set -euo pipefail
trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")
CONTENT=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content",""))' 2>/dev/null || echo "")

# request.json만 검증
case "$FILE_PATH" in
  */worktask/WT*/request.json)
    python3 <<PYEOF
import json, re, sys

content = '''$CONTENT'''
try:
    req = json.loads(content)
except Exception as e:
    print(json.dumps({"decision":"block","reason":f"JSON parse fail: {e}"}))
    sys.exit(0)

errs = []

# task_id 형식
tid = req.get("task_id", "")
if not re.match(r'^WT[0-9]{8}_[0-9]{3}$', tid):
    errs.append(f"task_id format invalid: {tid}")

# universe
allowed_univs = [
    "KOSPI200", "KOSDAQ150", "KOSPI200_KOSDAQ150_intersection", "KR_top500",
    # universe_v2 (L-227 architect advisory, 2026-04-26)
    "KR_top342", "KR_TOP500_FREEFLOAT", "KR_KOSPI300_KOSDAQ150", "KR_TOP500_LIQ1E8"
]
uni = req.get("universe_definition", {})
if uni.get("label") not in allowed_univs:
    errs.append(f"universe label not allowed: {uni.get('label')}")

# max_names ≤ 20
hc = req.get("hard_constraints", {})
if hc.get("max_names", 999) > 20:
    errs.append(f"max_names {hc.get('max_names')} > 20 (사용자 hard cap)")

# data_lag_rules 필수 4종
dlr = req.get("data_lag_rules", {})
required = ["fundamental", "price", "investor_flow", "macro"]
missing = [k for k in required if k not in dlr]
if missing:
    errs.append(f"data_lag_rules missing: {missing}")

# cost_model_version 형식
cmv = req.get("cost_model_version", "")
if not re.match(r'^v[0-9.]+_.+_[0-9]+bps$', cmv):
    errs.append(f"cost_model_version format invalid: {cmv}")

if errs:
    print(json.dumps({
      "decision": "block",
      "reason": "worktask_spec_validator: " + " | ".join(errs)
    }))
else:
    print(json.dumps({"decision":"allow"}))
PYEOF
    ;;
  *)
    echo '{"decision":"allow"}'
    ;;
esac
