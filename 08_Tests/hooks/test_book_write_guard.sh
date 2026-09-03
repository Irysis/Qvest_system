#!/usr/bin/env bash
#==============================================================================
# test_book_write_guard.sh — v10 BOOK 쓰기 가드의 양방향 검증 (위반 주입 + 통과)
#
# 계약: ① 06_Registry/book/** Write/Edit → block
#       ② qepm/mailbox/governor/book_state.json Write/Edit → block (legacy 동결)
#       ③ 무관 경로 Write → allow (오탐 없음)
#       ④ Bash tool_name → allow (Rscript writer 경로는 막지 않는다)
#==============================================================================
set -uo pipefail
QM="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$QM" || exit 9
HOOK="02_Infrastructure/hooks/book_write_guard.sh"
[ -f "$HOOK" ] || { echo "XX hook 부재"; exit 9; }
PY="${QVEST_PY:-.venv_qvest_ml/Scripts/python.exe}"

PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
ng(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

run_hook(){ # $1=tool $2=file_path
  "$PY" -c "import json,sys; print(json.dumps({'tool_name': sys.argv[1], 'tool_input': {'file_path': sys.argv[2], 'content': 'x'}}))" "$1" "$2" | bash "$HOOK" 2>/dev/null
}

echo "=== book_write_guard v10 양방향 검증 ==="

OUT="$(run_hook Write "C:/Users/99922/OneDrive/Quant_Module_Moltbot/06_Registry/book/book_registry.json")"
if echo "$OUT" | grep -q '"block"'; then ok "① BOOK 정본 직접 Write 차단"; else ng "① BOOK 직접 쓰기 통과됨: $OUT"; fi

OUT="$(run_hook Edit "06_Registry/book/book_registry.json")"
if echo "$OUT" | grep -q '"block"'; then ok "① 상대경로 Edit 도 차단"; else ng "① 상대경로 Edit 통과됨: $OUT"; fi

OUT="$(run_hook Write "C:/Users/99922/OneDrive/Quant_Module_Moltbot/qepm/mailbox/governor/book_state.json")"
if echo "$OUT" | grep -q '"block"' && echo "$OUT" | grep -q "legacy"; then ok "② legacy book_state 재기입 차단"; else ng "② book_state 재기입 통과됨: $OUT"; fi

OUT="$(run_hook Write "06_Registry/some_other_registry.json")"
if echo "$OUT" | grep -q '"block"'; then ng "③ 무관 경로 오탐: $OUT"; else ok "③ 무관 경로 allow (오탐 없음)"; fi

OUT="$(run_hook Bash "06_Registry/book/book_registry.json")"
if echo "$OUT" | grep -q '"block"'; then ng "④ Bash tool 이 차단됨 — writer 경로 사망: $OUT"; else ok "④ Bash tool allow (writer 경로 생존)"; fi

echo "결과: PASS=$PASS FAIL=$FAIL"
# ★러너 요약 계약 (v10 2026-09-03): 이 줄이 없으면 run_all_hooks.sh 가 UNMEASURED 로 계상해
#   이 스위트의 단언이 배터리 총계에 **0** 으로 들어간다(조용한 커버리지 구멍).
printf '{"test":"book_write_guard","pass":%d,"fail":%d,"total":%d,"skipped":0}
' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
