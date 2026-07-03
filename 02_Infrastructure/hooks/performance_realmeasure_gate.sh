#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
#==============================================================================
# performance_realmeasure_gate.sh — Stop hook (성과 실측 강제)
# 도훈 mandate 2026-06-17: 성과 수치(YTD/Sharpe/CAGR/MDD/수익률 + 숫자%)를 응답에
#   쓰면서 *이번 턴에 백테스트/코드 실행(Rscript·run_all·run_layer5 등)이 없으면* 턴 종료 차단.
#   → 추측·인용 금지, 실제 코드 실행 실측값만. (feedback-performance-real-code-only enforcement)
# 무한루프 회피: stop_hook_active=True면 통과.
# 안전: 어떤 오류든 '{}'(통과)로 빠져 내 턴을 깨지 않음.
#==============================================================================
set -uo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("hook_event_name",""))' 2>/dev/null || echo "")
if [ "$EVENT" != "Stop" ]; then echo '{}'; exit 0; fi
ACTIVE=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("stop_hook_active",False))' 2>/dev/null || echo "False")
if [ "$ACTIVE" = "True" ]; then echo '{}'; exit 0; fi
TP=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("transcript_path",""))' 2>/dev/null || echo "")
if [ -z "$TP" ] || [ ! -f "$TP" ]; then echo '{}'; exit 0; fi

"$QVEST_PY_BIN" - "$TP" <<'PY' 2>/dev/null || echo '{}'
import json, sys, re
tp = sys.argv[1]
lines = []
with open(tp, 'r', encoding='utf-8', errors='replace') as f:
    for ln in f:
        ln = ln.strip()
        if not ln: continue
        try: lines.append(json.loads(ln))
        except Exception: pass

def is_user_prompt(m):
    if m.get('type') != 'user': return False
    c = m.get('message', {}).get('content')
    if isinstance(c, str): return True
    if isinstance(c, list):
        # genuine prompt has a text block (tool_result는 type=tool_result)
        return any(isinstance(b, dict) and b.get('type') == 'text' for b in c)
    return False

start = 0
for i, m in enumerate(lines):
    if is_user_prompt(m): start = i

atext, cmds = [], []
for m in lines[start:]:
    if m.get('type') == 'assistant':
        c = m.get('message', {}).get('content', [])
        if isinstance(c, list):
            for b in c:
                if not isinstance(b, dict): continue
                if b.get('type') == 'text': atext.append(b.get('text', ''))
                elif b.get('type') == 'tool_use' and b.get('name') in ('Bash', 'PowerShell'):
                    cmds.append(str(b.get('input', {}).get('command', '')))

full = ' '.join(atext)
allcmd = ' '.join(cmds)

perfkw = r'(YTD|Sharpe|샤프|CAGR|연율화|연간수익|MDD|수익률|누적\s*수익|초과수익|Calmar|Sortino|월별\s*수익|성과)'
has_perf = bool(re.search(perfkw, full, re.I)) and bool(re.search(r'[+\-]?\d+\.?\d*\s*%', full))
# [강화 2026-06-17] generic Rscript/수동함수(Return.portfolio·maxDrawdown) 제외 —
#   "코드 돌림"이 아니라 "권위 백테 엔진/출력을 건드림"만 인정 → 수동 side-calc은 차단.
# [확장 2026-06-18, 도훈 review 대기] measurement-graduation §1이 권위 real-computation 경로로 명시한
#   canonical_screen_bt / weighted_screen_bt(그 임의가중 일반화, build_benchmark_compare NW lag-3 경유) 추가.
#   둘 다 contract-grade(수동 side-calc 아님) — 기존 allowlist가 이들 신규 primitive를 누락해 거짓차단 발생하던 것 교정.
ran = bool(re.search(r'run_layer5|run_all\.R|period_returns_layer5|build_bt_result|save_bt_result|canonical_screen_bt|weighted_screen_bt|build_benchmark_compare', allcmd, re.I))

if has_perf and not ran:
    print(json.dumps({
        "decision": "block",
        "reason": ("[performance_realmeasure_gate] 응답에 성과 수치(%)가 있으나 이번 턴에 "
                   "백테스트/코드 실행(Rscript·run_all·run_layer5·period_returns 등)이 없습니다. "
                   "추측·과거값 인용 금지 — 실제로 코드를 돌려 실측값으로 다시 보고하세요. "
                   "(도훈 mandate: 성과는 실측만)")
    }, ensure_ascii=False))
else:
    print("{}")
PY
