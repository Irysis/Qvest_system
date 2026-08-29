#!/usr/bin/env bash
#==============================================================================
# test_worktask_constraint_enforcer_v10.sh — v10 비중 상한 폐지의 **양방향** 검증
#
# 계약 (v10 2026-08-29 도훈 지시 "종목별 20% 제한도 완전히 삭제해버려"):
#   deployment WT 의 optimization_package.json 검증 축 = ①max_names ≤25
#   ②long-only(w≥0) ③Σw=1 — **비중 상한 검사는 없다**.
#
# 이 테스트가 재는 것 (검사기는 양방향으로 잰다 — 양성 대조 + 위반 주입):
#   ① w=0.35 단일 종목 집중 → **통과** (구판이면 block — 상한 폐지 실증)
#   ② 26종 → block (max_names 잔존 실증)
#   ③ 음수 비중 → block (long-only 잔존 실증)
#   ④ Σw=0.8 → block (Σw=1 잔존 실증)
#==============================================================================
set -uo pipefail
QM="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$QM" || exit 9
HOOK="02_Infrastructure/hooks/worktask_constraint_enforcer.sh"
[ -f "$HOOK" ] || { echo "XX hook 부재"; exit 9; }
PY="${QVEST_PY:-.venv_qvest_ml/Scripts/python.exe}"
[ -f "$PY" ] || { echo "XX venv python 부재"; exit 9; }

PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
ng(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

# stdin 계약: {tool_input:{file_path, content}} — deployment 추론은 경로 WT-P 로 유도
mk_input(){ # $1 = target_weights JSON
  "$PY" -c "
import json, sys
tw = json.loads(sys.argv[1])
print(json.dumps({'tool_input': {
  'file_path': 'qepm/mailbox/worktask/WT-P20990101_001/optimization_package.json',
  'content': json.dumps({'target_weights': tw})}}))
" "$1"
}

run_hook(){ mk_input "$1" | bash "$HOOK" 2>/dev/null; }

echo "=== worktask_constraint_enforcer v10 양방향 검증 ==="

# ① 상한 폐지: 25종, 최대 비중 0.35, Σw=1 → 통과해야 한다
TW1="$("$PY" -c "
import json
w = {'A%02d' % i: 0.35 if i == 0 else 0.65/24 for i in range(25)}
print(json.dumps(w))")"
OUT="$(run_hook "$TW1")"
if echo "$OUT" | grep -q '"block"'; then ng "① w=0.35 집중이 차단됨 — 상한 폐지 미반영: $OUT"
else ok "① w=0.35 집중 통과 (비중 상한 폐지 실증)"; fi

# ② 26종 → block
TW2="$("$PY" -c "
import json
w = {'A%02d' % i: 1.0/26 for i in range(26)}
print(json.dumps(w))")"
OUT="$(run_hook "$TW2")"
if echo "$OUT" | grep -q '"block"' && echo "$OUT" | grep -q "max_names"; then ok "② 26종 차단 (max_names 잔존)"
else ng "② 26종이 통과됨 — max_names 축 사망: $OUT"; fi

# ③ 음수 비중 → block
TW3="$("$PY" -c "
import json
w = {'A%02d' % i: 1.05/24 for i in range(24)}; w['SHORT'] = -0.05
print(json.dumps(w))")"
OUT="$(run_hook "$TW3")"
if echo "$OUT" | grep -q '"block"' && echo "$OUT" | grep -q "long-only"; then ok "③ 음수 비중 차단 (long-only 잔존)"
else ng "③ 음수 비중이 통과됨 — long-only 축 사망: $OUT"; fi

# ④ Σw=0.8 → block
TW4="$("$PY" -c "
import json
w = {'A%02d' % i: 0.8/20 for i in range(20)}
print(json.dumps(w))")"
OUT="$(run_hook "$TW4")"
if echo "$OUT" | grep -q '"block"'; then ok "④ Σw=0.8 차단 (Σw=1 잔존)"
else ng "④ Σw=0.8 이 통과됨 — Σw 축 사망: $OUT"; fi

echo "결과: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
