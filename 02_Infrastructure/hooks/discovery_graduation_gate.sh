#!/usr/bin/env bash
# discovery_graduation_gate.sh — Discovery → Deployment 전환 검증 (Level 3)
# v6.1 R1+R13
#
# 이벤트: PreToolUse[Write] on Deployment request.json
# 목적: Deployment WT 생성 시 discovery_of 참조 WT의 graduation_criteria 충족 여부 확인
#
# 우회 조건:
#   - discovery_of == null (명시적 직접 Deployment) → warn only
#   - graduation_criteria 미설정 → allow
#
# Block 조건:
#   - discovery_of 참조된 Discovery WT의 alpha_package가 graduation_criteria 미충족

set -euo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")
CONTENT=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content",""))' 2>/dev/null || echo "")

# Deployment WT request.json만 검증
case "$FILE_PATH" in
  */WT-P*/request.json)
    python3 <<PYEOF
import json, os, sys

try:
    req = json.loads('''$CONTENT''')
except Exception as e:
    print(json.dumps({}))
    sys.exit(0)

if req.get("wt_type") != "deployment":
    print(json.dumps({}))
    sys.exit(0)

discovery_of = req.get("discovery_of")
if discovery_of is None:
    # 직접 Deployment (Discovery 없이) — warn only (새 전략 직접 편성 허용)
    print(json.dumps({}))
    sys.exit(0)

# Discovery WT 참조 존재 확인
wt_root = "qepm/mailbox/worktask"
disc_dir = os.path.join(wt_root, discovery_of)
if not os.path.isdir(disc_dir):
    print(json.dumps({
      "decision": "block",
      "reason": f"discovery_of 참조 WT 없음: {discovery_of}"
    }))
    sys.exit(0)

alpha_path = os.path.join(disc_dir, "alpha_package.json")
if not os.path.exists(alpha_path):
    print(json.dumps({
      "decision": "block",
      "reason": f"{discovery_of}/alpha_package.json 없음 — Discovery WT alpha 미완료"
    }))
    sys.exit(0)

with open(alpha_path) as f:
    alpha_pkg = json.load(f)
diag = alpha_pkg.get("diagnostics", {})
criteria = req.get("graduation_criteria", {})

checks = {}
if "min_rank_ic" in criteria:
    actual = diag.get("rank_ic", 0)
    checks["rank_ic"] = {"actual": actual, "threshold": criteria["min_rank_ic"], "pass": actual >= criteria["min_rank_ic"]}
if "min_icir" in criteria:
    actual = diag.get("icir", 0)
    checks["icir"] = {"actual": actual, "threshold": criteria["min_icir"], "pass": actual >= criteria["min_icir"]}
if "min_subperiod_stability" in criteria:
    actual = diag.get("subperiod_stability", 0)
    checks["subperiod_stability"] = {"actual": actual, "threshold": criteria["min_subperiod_stability"], "pass": actual >= criteria["min_subperiod_stability"]}
if "min_harvey_t_stat" in criteria:
    actual = diag.get("harvey_t_stat", 0)
    checks["harvey_t_stat"] = {"actual": actual, "threshold": criteria["min_harvey_t_stat"], "pass": actual >= criteria["min_harvey_t_stat"]}

fails = [k for k,v in checks.items() if not v["pass"]]
if fails:
    fail_detail = [f"{k}={checks[k]['actual']:.4f}<{checks[k]['threshold']:.4f}" for k in fails]
    print(json.dumps({
      "decision": "block",
      "reason": f"graduation 미충족 ({discovery_of}): " + " | ".join(fail_detail)
    }))
else:
    print(json.dumps({}))
PYEOF
    ;;
  *)
    echo '{}'
    ;;
esac
