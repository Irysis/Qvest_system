#!/usr/bin/env bash
#==============================================================================
# test_rf_l2_auto.sh — 2계층 무인 레인 게이트 (2026-09-21 플랜 Part 3 · D2)
#   격리 env(QVEST_RF_CONFIG · QVEST_L2_REQUEST · QVEST_RP_JLOG · QVEST_L2_DRY_GATE=1)로 셸 게이트만 검사. 드라이버 미호출.
#   ① disabled → halt_disabled ② 요청 없음 → not_due ③ pending + R1 미결 → halt_r1_undecided ④ 전부 충족 → gate_pass
#   ⑤ tick 등록(호출 줄 존재 · 러너 앞) ⑥ 구문
#==============================================================================
set -uo pipefail
QM="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$QM" || exit 9
SH="02_Infrastructure/ops/rf_l2_auto.sh"; TK="02_Infrastructure/ops/reinforce_auto_tick.sh"
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
ng(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
# ★임시 경로는 Windows 형으로 — 레인의 jl/게이트는 네이티브 python 이라 /tmp/... (MSYS 경로)를 못 연다(실측 2026-09-21: 이벤트 0건)
T=$(cygpath -m "$(mktemp -d)" 2>/dev/null || mktemp -d); export QVEST_RF_CONFIG="$T/cfg.json" QVEST_L2_REQUEST="$T/req.json" QVEST_RP_JLOG="$T/jlog.jsonl" QVEST_L2_DRY_GATE=1
last(){ tail -1 "$QVEST_RP_JLOG" 2>/dev/null | python -c "import sys,json; print(json.loads(sys.stdin.read()).get('event'))" 2>/dev/null; }
cfg(){ printf '{"enabled":true,"l2_auto":{"enabled":%s,"selection_type":"%s","decided_by":"%s","decided_at":"%s"}}' "$1" "$2" "$3" "$4" > "$QVEST_RF_CONFIG"; }

echo "=== rf_l2_auto.sh 게이트 ==="
bash -n "$SH" && ok "⑥ 구문" || ng "⑥ 구문 오류"
cfg false "" "" ""; rm -f "$QVEST_L2_REQUEST" "$QVEST_RP_JLOG"; bash "$SH" >/dev/null 2>&1
[ "$(last)" = "halt_disabled" ] && ok "① disabled → halt_disabled" || ng "① got $(last)"
cfg true chain dohoon 2026-09-21; rm -f "$QVEST_RP_JLOG"; bash "$SH" >/dev/null 2>&1
[ "$(last)" = "not_due" ] && ok "② 요청 없음 → not_due" || ng "② got $(last)"
printf '{"status":"pending","base_id":"FR_003"}' > "$QVEST_L2_REQUEST"
cfg true "" "" ""; rm -f "$QVEST_RP_JLOG"; bash "$SH" >/dev/null 2>&1
[ "$(last)" = "halt_r1_undecided" ] && ok "③ pending + R1 미결 → halt_r1_undecided" || ng "③ got $(last)"
cfg true chain "" ""; rm -f "$QVEST_RP_JLOG"; bash "$SH" >/dev/null 2>&1
[ "$(last)" = "halt_r1_undecided" ] && ok "③b selection_type 만 있고 결정자 없음 → halt_r1_undecided" || ng "③b got $(last)"
cfg true chain dohoon 2026-09-21; rm -f "$QVEST_RP_JLOG"; bash "$SH" >/dev/null 2>&1
[ "$(last)" = "gate_pass" ] && ok "④ 전부 충족 → gate_pass(드라이버 미호출 · dry gate)" || ng "④ got $(last)"
printf '{"status":"done","base_id":"FR_003"}' > "$QVEST_L2_REQUEST"; rm -f "$QVEST_RP_JLOG"; bash "$SH" >/dev/null 2>&1
[ "$(last)" = "not_due" ] && ok "④b 요청 done → not_due" || ng "④b got $(last)"
if grep -qE '^[^#]*bash[^#]*rf_l2_auto\.sh' "$TK"; then
  ln_l2=$(grep -nE '^[^#]*bash[^#]*rf_l2_auto\.sh' "$TK" | head -1 | cut -d: -f1); ln_run=$(grep -nE '^[^#]*Rscript[^#]*reinforce_auto_parallel\.R' "$TK" | head -1 | cut -d: -f1)
  if [ -n "$ln_l2" ] && [ -n "$ln_run" ] && [ "$ln_l2" -lt "$ln_run" ]; then ok "⑤ tick 등록: L2 레인($ln_l2) 이 러너($ln_run) 앞"; else ng "⑤ tick 순서 l2=$ln_l2 runner=$ln_run"; fi
else ng "⑤ tick 에 rf_l2_auto.sh 호출 없음(미배포)"; fi
rm -rf "$T"
echo "결과: PASS=$PASS FAIL=$FAIL"
printf '{"test":"rf_l2_auto_gate","pass":%d,"fail":%d,"total":%d,"skipped":0}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
