#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
# challenge_loop_limiter.sh — Challenge Loop round 제한 (Level 2)
# v6.1 R3 P4
#
# 이벤트: PreToolUse[Write] on status.json (challenge_round 변경 시)
# 목적: Challenge round > 2 시 Q-Lead 개입 요청 (강제 block 아님, warn + notify)
#
# 무한 루프 방지 + challenge 근거 투명성 유지

set -euo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")
CONTENT=$(echo "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content",""))' 2>/dev/null || echo "")

# status.json 또는 challenge_history 포함 파일만
case "$FILE_PATH" in
  */status.json|*/governance_log.json)
    # (2026-07-24 Fable5 하네스 감사) content/fp는 env 경유 + heredoc 인용 — 소스 보간('''$CONTENT''')은
    # triple-quote/backslash content에서 python 소스가 깨져 ERR trap '{}' fail-open (v8.1.2 constraint_enforcer 동일 수리)
    CLL_CONTENT="$CONTENT" CLL_FP="$FILE_PATH" "$QVEST_PY_BIN" <<'PYEOF'
import json, os, sys

content = os.environ.get("CLL_CONTENT", "")
fp = os.environ.get("CLL_FP", "")

try:
    data = json.loads(content)
except Exception:
    print(json.dumps({}))
    sys.exit(0)

round_n = data.get("challenge_round", 0)

if round_n >= 3:
    # Hard limit (policy 2 rounds + 1 for Q-Lead intervention)
    print(json.dumps({
      "decision": "block",
      "reason": f"challenge_loop_limiter: round {round_n} >= 3 — Q-Lead 개입 필수. WT 수동 재검토 후 진행."
    }))
    sys.exit(0)
elif round_n == 2:
    # Warn + Telegram alert
    wt_id = os.path.basename(os.path.dirname(fp))
    alert_file = "/tmp/qvest_challenge_alert.log"
    with open(alert_file, "a") as f:
        import time
        f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} | {wt_id} | challenge_round=2 | Q-Lead 개입 검토\n")
    print(json.dumps({}))
else:
    print(json.dumps({}))
PYEOF
    ;;
  *)
    echo '{}'
    ;;
esac
