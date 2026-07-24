#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
# method_shopping_limiter.sh — P1 Selection Freedom 제약 (Level 3)
# v6.1 R2 P1
#
# 이벤트: PreToolUse[Write] on *_package.json
# 목적: agent 내부 후보 탐색 수 상한 강제
#   - Alpha: candidates_tried ≤ 5
#   - Risk: candidates_tried ≤ 5
#   - Optimizer: candidates_tried ≤ 10
#
# method_shopping_log.json에 전수 기록 의무. Judge가 DSR penalty 적용용.

set -euo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")
CONTENT=$(echo "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content",""))' 2>/dev/null || echo "")

case "$FILE_PATH" in
  */alpha_package.json)
    pkg_type="alpha"; limit=5 ;;
  */risk_package.json)
    pkg_type="risk"; limit=5 ;;
  */optimization_package.json)
    pkg_type="optimizer"; limit=10 ;;
  *)
    echo '{}'
    exit 0
    ;;
esac

# (2026-07-24 Fable5 하네스 감사) content는 env 경유 + heredoc 인용 — 소스 보간('''$CONTENT''')은
# triple-quote/backslash content에서 python 소스가 깨져 ERR trap '{}' fail-open (v8.1.2 constraint_enforcer 동일 수리)
MSL_CONTENT="$CONTENT" MSL_PKG_TYPE="$pkg_type" MSL_LIMIT="$limit" "$QVEST_PY_BIN" <<'PYEOF'
import json, os, sys

pkg_type = os.environ.get("MSL_PKG_TYPE", "")
limit = int(os.environ.get("MSL_LIMIT", "999"))
content = os.environ.get("MSL_CONTENT", "")

try:
    pkg = json.loads(content)
except Exception:
    print(json.dumps({}))
    sys.exit(0)

# method_shopping 카운트 추출 (agent별 다름)
if pkg_type == "alpha":
    count = len(pkg.get("factor_specs", []))
elif pkg_type == "risk":
    # Risk는 method_comparison (shrinkage 여러 시도)
    count = len(pkg.get("diagnostics", {}).get("methods_tried", []))
    if count == 0 and pkg.get("diagnostics", {}).get("shrinkage_method"):
        count = 1
elif pkg_type == "optimizer":
    mc = pkg.get("method_comparison", {})
    count = len(mc) if isinstance(mc, dict) else 0

if count > limit:
    print(json.dumps({
      "decision": "block",
      "reason": f"method_shopping_limiter ({pkg_type}): candidates_tried {count} > {limit} — 탐색 공간 과다. Judge DSR penalty 우회 방지."
    }))
else:
    print(json.dumps({}))
PYEOF
