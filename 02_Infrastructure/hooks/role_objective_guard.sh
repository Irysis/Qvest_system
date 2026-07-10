#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
# role_objective_guard.sh — P3 Role-specific Objective 강제 (Level 3)
# v6.1 R4
#
# 이벤트: PreToolUse[Write] on *_package.json
# 목적: 각 agent package의 selection_objective 필드 도메인 검증
#   - Alpha: canonical_port_t / rank_ic / icir / monotonicity / subperiod_stability 만
#     (v8.3 M1 2026-07-10: canonical_port_t = canonical_screen_bt 실측 PORT_t NW lag-3 1급 추가.
#      IC-계열은 advisory 유지. SR/CAGR/MDD proxy 손계산은 여전히 금지)
#   - Risk: condition_number / stress_robust / crowding / shrinkage_quality 만
#   - Optimizer: net_ir / to_adj_ret / uncertainty_penalty / crowding_adj_ret 만
#
# 위반 (예: Alpha가 selection_objective="sharpe") → block
# 의도: selection pressure 3-agent 공유 방지 (SR 중심 수렴 차단)

set -euo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")
CONTENT=$(echo "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content",""))' 2>/dev/null || echo "")

case "$FILE_PATH" in
  */alpha_package.json)
    pkg_type="alpha"
    allowed_objectives="canonical_port_t,rank_ic,icir,monotonicity,subperiod_stability"
    ;;
  */risk_package.json)
    pkg_type="risk"
    allowed_objectives="condition_number,stress_robust,crowding,shrinkage_quality"
    ;;
  */optimization_package.json)
    pkg_type="optimizer"
    allowed_objectives="net_ir,to_adj_ret,uncertainty_penalty,crowding_adj_ret"
    ;;
  *)
    echo '{}'
    exit 0
    ;;
esac

"$QVEST_PY_BIN" <<PYEOF
import json, sys

pkg_type = "$pkg_type"
allowed = set("$allowed_objectives".split(","))
content = '''$CONTENT'''

try:
    pkg = json.loads(content)
except Exception:
    print(json.dumps({}))
    sys.exit(0)

so = pkg.get("selection_objective")
if so is None:
    # Selection objective 미지정 — v6.0 backward compat allow + warn
    print(json.dumps({}))
    sys.exit(0)

if so not in allowed:
    print(json.dumps({
      "decision": "block",
      "reason": f"role_objective_guard ({pkg_type}): selection_objective='{so}' 금지. 허용: {sorted(allowed)}. P3 selection pressure 공유 방지."
    }))
else:
    print(json.dumps({}))
PYEOF
