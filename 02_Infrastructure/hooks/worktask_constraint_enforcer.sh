#!/usr/bin/env bash
# worktask_constraint_enforcer.sh — Hard Constraints 강제 (Level 3 hard block)
# v6.1 R1+R13: wt_type 분기 (Discovery = SOFT 면제, Deployment = 전부 강제)
#
# 이벤트: PreToolUse[Write]
# 목적: optimization_package.json 쓰기 시 wt_type 따라 제약 검증
#
# 검증 항목 (Deployment WT만):
#   1. max_names ≤ 20 (hard cap)
#   2. long-only: all weights ≥ 0
#   3. weight_bounds: weights ≤ 0.20
#   4. Σw = 1 (absolute, tolerance 0.001)
#
# Discovery WT: SOFT 제약 SKIP, HARD mandate (PIT + liquidity floor 50M)만.

set -euo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")
CONTENT=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content",""))' 2>/dev/null || echo "")

case "$FILE_PATH" in
  */optimization_package.json)
    python3 <<PYEOF
import json, os, re, sys

content = '''$CONTENT'''
fp = '''$FILE_PATH'''

try:
    pkg = json.loads(content)
except Exception:
    print(json.dumps({}))
    sys.exit(0)

# WT_id 추출 (파일 경로 WT-D{...} or WT-P{...})
m = re.search(r'WT-([DP])(\d{8}_\d{3})', fp)
if not m:
    # legacy WT (v6, 접두사 없음) 또는 알 수 없음
    wt_type = "deployment"  # 기본 안전 정책
    wt_id_legacy = re.search(r'WT(\d{8}_\d{3})', fp)
    if wt_id_legacy:
        wt_id = f"WT{wt_id_legacy.group(1)}"
    else:
        wt_id = "unknown"
else:
    tag = m.group(1)
    wt_id = f"WT-{tag}{m.group(2)}"
    wt_type = "discovery" if tag == "D" else "deployment"

# Request.json에서 wt_type 재확인 (파일명보다 우선)
request_path = fp.replace("optimization_package.json", "request.json")
if os.path.exists(request_path):
    try:
        with open(request_path) as f:
            req = json.load(f)
        wt_type = req.get("wt_type", wt_type)
    except Exception:
        pass

tw = pkg.get("target_weights", {})
if not isinstance(tw, dict) or len(tw) == 0:
    print(json.dumps({}))
    sys.exit(0)

errs = []

# Discovery WT: SOFT 제약 SKIP, long-only는 mandate 따름만
if wt_type == "discovery":
    # Discovery는 breadth 허용 — max_names / weight_bounds skip
    # 단 long-only mandate가 TRUE인 경우만 체크
    mandate_long_only = req.get("hard_mandate", {}).get("long_only_mandate", "configurable") if os.path.exists(request_path) else "configurable"
    if mandate_long_only is True:
        neg = [k for k,v in tw.items() if v < 0]
        if neg:
            errs.append(f"long-only mandate 위반: {neg[:3]}")

    # Σw check (absolute=1 or active=0 — discovery 기본 absolute)
    total = sum(tw.values())
    if abs(total - 1.0) > 0.001 and abs(total) > 0.001:
        errs.append(f"Σw = {total:.4f} (absolute 1.0 or active 0.0 아님)")

else:
    # Deployment WT: 전체 제약 강제
    if len(tw) > 20:
        errs.append(f"max_names {len(tw)} > 20 (deployment hard cap)")
    neg = [k for k,v in tw.items() if v < 0]
    if neg:
        errs.append(f"long-only 위반: {neg[:3]}")
    too_high = [k for k,v in tw.items() if v > 0.20 + 1e-6]
    if too_high:
        errs.append(f"weight > 0.20: {too_high[:3]}")
    total = sum(tw.values())
    if abs(total - 1.0) > 0.001:
        errs.append(f"Σw = {total:.4f} ≠ 1.0")

if errs:
    print(json.dumps({
      "decision": "block",
      "reason": f"worktask_constraint_enforcer ({wt_type}): " + " | ".join(errs)
    }))
else:
    print(json.dumps({}))
PYEOF
    ;;
  *)
    echo '{}'
    ;;
esac
