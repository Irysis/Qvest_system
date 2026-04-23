#!/usr/bin/env bash
# worktask_artifact_validator.sh — WT 3-package schema 검증 (Level 2 soft gate)
# supersedes: artifact_validator.sh (archived 2026-04-23)
#
# 이벤트: PostToolUse[Write]
# 목적: alpha_package.json / risk_package.json / optimization_package.json 저장 후 schema 검증
#
# 필수 필드 누락 시 warn + log (block 아님, PostToolUse이므로)

set -euo pipefail
trap 'exit 0' ERR

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

# 대상 파일 확인
case "$FILE_PATH" in
  */alpha_package.json|*/risk_package.json|*/optimization_package.json)
    # 계속
    ;;
  *)
    exit 0
    ;;
esac

LOG="/tmp/worktask_artifact_validator.log"

python3 <<PYEOF 2>>"$LOG"
import json, sys

fp = "$FILE_PATH"
try:
    with open(fp) as f:
        pkg = json.load(f)
except Exception as e:
    print(f"[WARN] {fp} JSON parse fail: {e}", file=sys.stderr)
    sys.exit(0)

# package type 결정
if "alpha_vector" in pkg:
    required = ["task_id", "as_of_date", "alpha_vector", "factor_specs", "diagnostics"]
    pkg_type = "alpha_package"
elif "factor_covariance_ref" in pkg:
    required = ["task_id", "as_of_date", "factor_covariance_ref", "risk_summary", "diagnostics"]
    pkg_type = "risk_package"
elif "method_selected" in pkg or "target_weights" in pkg:
    required = ["task_id", "as_of_date", "method_selected", "expected_tracking_error"]
    pkg_type = "optimization_package"
else:
    print(f"[WARN] {fp} unknown package type", file=sys.stderr)
    sys.exit(0)

missing = [k for k in required if k not in pkg]
if missing:
    print(f"[WARN] {fp} ({pkg_type}) missing fields: {missing}", file=sys.stderr)
    # Q-Lead 알림을 위해 /tmp/worktask_alerts 에 기록
    import os, time
    alerts = "/tmp/worktask_alerts.log"
    with open(alerts, "a") as f:
        f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} | {pkg_type} | {fp} | missing={missing}\n")
else:
    print(f"[OK] {fp} ({pkg_type}) schema PASS", file=sys.stderr)
PYEOF

exit 0
