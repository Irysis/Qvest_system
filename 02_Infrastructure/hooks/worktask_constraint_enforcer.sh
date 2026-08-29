#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
# worktask_constraint_enforcer.sh — Hard Constraints 강제 (Level 3 hard block)
# v6.1 R1+R13: wt_type 분기 (Discovery = SOFT 면제, Deployment = 전부 강제)
#
# 이벤트: PreToolUse[Write]
# 목적: optimization_package.json 쓰기 시 wt_type 따라 제약 검증
#
# 검증 항목 (Deployment WT만):
#   1. max_names ≤ 25 (hard cap, 도훈 mandate 2026-05-29 20→25)
#   2. long-only: all weights ≥ 0
#   3. Σw = 1 (absolute, tolerance 0.001)
#   ★종목별 비중 상한(구 ≤0.20)은 v10 에서 mandate 층 전체 삭제 (도훈 지시 2026-08-29
#     "종목별 20% 제한도 완전히 삭제해버려"). 등록 전략 frozen 스펙 내부의 캡은 별개.
#
# Discovery WT: SOFT 제약 SKIP, HARD mandate (PIT + liquidity floor 50M)만.

set -euo pipefail
trap 'echo "{}"; exit 0' ERR
export PYTHONUTF8=1  # (v8.1.2) 인코딩 사고 방지 — harness.md "Hook stdout JSON 규율"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; sys.stdout.reconfigure(encoding="utf-8",errors="replace"); d=json.loads(sys.stdin.buffer.read().decode("utf-8","replace")); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")
CONTENT=$(echo "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; sys.stdout.reconfigure(encoding="utf-8",errors="replace"); d=json.loads(sys.stdin.buffer.read().decode("utf-8","replace")); print(d.get("tool_input",{}).get("content",""))' 2>/dev/null || echo "")

case "$FILE_PATH" in
  */optimization_package.json)
    # (v8.1.2) content/fp는 env 경유 + heredoc 인용 — 소스 보간('''$CONTENT''')은 triple-quote/
    # backslash content에서 python 소스가 깨져 ERR trap '{}' fail-open (Tier-3 게이트 침묵 무력화)
    WTE_CONTENT="$CONTENT" WTE_FP="$FILE_PATH" "$QVEST_PY_BIN" <<'PYEOF'
import json, os, re, sys

content = os.environ.get("WTE_CONTENT", "")
fp = os.environ.get("WTE_FP", "")

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
# (v8.1.2) req 선초기화 — open 실패 시 아래 mandate 참조가 NameError → ERR trap fail-open 되던 갭
req = {}
request_path = fp.replace("optimization_package.json", "request.json")
if os.path.exists(request_path):
    try:
        with open(request_path, encoding="utf-8") as f:
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
    if len(tw) > 25:
        errs.append(f"max_names {len(tw)} > 25 (deployment hard cap, 도훈 mandate 2026-05-29 20→25)")
    neg = [k for k,v in tw.items() if v < 0]
    if neg:
        errs.append(f"long-only 위반: {neg[:3]}")
    # (v10 2026-08-29) 종목별 비중 상한 검사 삭제 — mandate 층 [0,0.20] 폐지 (도훈 지시).
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
