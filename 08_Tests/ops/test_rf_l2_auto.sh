#!/usr/bin/env bash
#==============================================================================
# test_rf_l2_auto.sh — 2계층 무인 레인 게이트 (2026-09-21 플랜 Part 3 · D2)
#   격리 env(QVEST_RF_CONFIG · QVEST_L2_REQUEST · QVEST_RP_JLOG · QVEST_L2_DRY_GATE=1)로 셸 게이트만 검사. 드라이버 미호출.
#   ① disabled → halt_disabled ② 요청 없음 → not_due ③ pending + R1 미결 → halt_r1_undecided ④ 전부 충족 → gate_pass
#   ⑤ tick 등록(호출 줄 존재 · 리프레시 배리어 뒤 · 충실구현 레인 뒤 직렬) + 돌연변이 ⑤m1·⑤m2 ⑥ 구문
#
# (v10.01 2026-10-13) ⑤ 재표현 — 구판 "L2 레인이 러너 앞"(같은 틱의 러너가 L2 드라이버의 claim 을 보고 물러나는 직렬화)은
#   강화 러너(reinforce_auto_parallel.R) 퇴역으로 대상이 사라졌다. 틱이 지금 하는 일 = 리프레시 배리어 → 충실구현 레인 →
#   2계층 레인(전부 포그라운드 순차). 그래서 ⑤ 는 "틱 배리어가 L2 도 덮는다 · 같은 틱 안에서 충실구현 레인과 겹치지 않는다" 를
#   재고, ⑤m1(L2 호출을 배리어 앞으로) · ⑤m2(충실구현 레인을 백그라운드로)로 판별력을 실증한다.
#   픽스처의 전역 enabled = false(운영 퇴역값) — rf_l2_auto.sh 가 자기 스위치(l2_auto.enabled)만 보는지(v10.01 스위치 분리)를
#   ②~④ 가 함께 잰다. 롤백 태그 pre-v10.01-prescription-20261013
#==============================================================================
set -uo pipefail
QM="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$QM" || exit 9
PY="${QVEST_PY:-python}"
SH="02_Infrastructure/ops/rf_l2_auto.sh"; TK="02_Infrastructure/ops/reinforce_auto_tick.sh"
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
ng(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
# ★임시 경로는 Windows 형으로 — 레인의 jl/게이트는 네이티브 python 이라 /tmp/... (MSYS 경로)를 못 연다(실측 2026-09-21: 이벤트 0건)
T=$(cygpath -m "$(mktemp -d)" 2>/dev/null || mktemp -d); export QVEST_RF_CONFIG="$T/cfg.json" QVEST_L2_REQUEST="$T/req.json" QVEST_RP_JLOG="$T/jlog.jsonl" QVEST_L2_DRY_GATE=1
last(){ tail -1 "$QVEST_RP_JLOG" 2>/dev/null | python -c "import sys,json; print(json.loads(sys.stdin.read()).get('event'))" 2>/dev/null; }
# (v10.01) 전역 enabled = false — 퇴역 러너 스위치. 레인은 l2_auto.enabled 만 본다(구판 = 두 스위치 AND).
cfg(){ printf '{"enabled":false,"l2_auto":{"enabled":%s,"selection_type":"%s","decided_by":"%s","decided_at":"%s"}}' "$1" "$2" "$3" "$4" > "$QVEST_RF_CONFIG"; }

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

echo "=== 틱 순서 (v10.01 — 배리어 → 충실구현 레인 → 2계층 레인) ==="
# $1 = 틱 파일 → 위반 사유(없으면 빈 줄). 주석 줄의 언급은 세지 않는다.
tick_l2_order(){
  local f="$1" lb lr ll why=""
  lb=$(grep -nE '^[[:space:]]*rb_status([[:space:]]|$)' "$f" | head -1 | cut -d: -f1)
  lr=$(grep -nE '^[^#]*bash[^#]*rf_replication_auto\.sh' "$f" | head -1 | cut -d: -f1)
  ll=$(grep -nE '^[^#]*bash[^#]*rf_l2_auto\.sh' "$f" | head -1 | cut -d: -f1)
  [ -n "$ll" ] || { printf ' no_l2_call'; return 0; }
  { [ -n "$lb" ] && [ "$lb" -lt "$ll" ]; } || why="$why l2_before_barrier(barrier=$lb l2=$ll)"
  { [ -n "$lr" ] && [ "$lr" -lt "$ll" ]; } || why="$why l2_before_replication(rp=$lr l2=$ll)"
  grep -qE '^[^#]*bash[^#]*rf_(replication|l2)_auto\.sh[^#]*[^&]&[[:space:]]*$' "$f" && why="$why backgrounded"
  printf '%s' "$why"
}
w=$(tick_l2_order "$TK")
[ -z "$w" ] && ok "⑤ tick 등록: L2 레인 호출 존재 · 리프레시 배리어 뒤 · 충실구현 레인 뒤 직렬(포그라운드)" || ng "⑤ tick 순서 —$w"
"$PY" - "$TK" "$T/tick_m1.sh" "$T/tick_m2.sh" <<'PYM'
import io, re, sys
s = io.open(sys.argv[1], encoding='utf-8').read().split('\n')
k = [i for i, l in enumerate(s) if re.match(r'^[^#]*bash[^#]*rf_l2_auto\.sh', l)]
r = [i for i, l in enumerate(s) if re.match(r'^[^#]*bash[^#]*rf_replication_auto\.sh', l)]
b = [i for i, l in enumerate(s) if re.match(r'^\s*RB_SH="\$\(dirname', l)]
if len(k) != 1 or len(r) != 1 or len(b) != 1 or not (b[0] < k[0]): sys.exit(3)
m1 = list(s); l2 = m1.pop(k[0]); m1.insert(b[0], l2)          # ⑤m1: L2 호출을 배리어 앞으로
m2 = list(s); m2[r[0]] = m2[r[0]].rstrip() + ' &'             # ⑤m2: 충실구현 레인을 백그라운드로(L2 와 겹친다)
io.open(sys.argv[2], 'w', encoding='utf-8', newline='').write('\n'.join(m1))
io.open(sys.argv[3], 'w', encoding='utf-8', newline='').write('\n'.join(m2))
PYM
MRC=$?
if [ "$MRC" = 0 ]; then
  w1=$(tick_l2_order "$T/tick_m1.sh"); case "$w1" in *l2_before_barrier*) ok "⑤m1 [돌연변이] L2 호출을 배리어 앞으로 옮기면 검사가 잡는다";; *) ng "⑤m1 미검출 [$w1]";; esac
  w2=$(tick_l2_order "$T/tick_m2.sh"); case "$w2" in *backgrounded*) ok "⑤m2 [돌연변이] 충실구현 레인을 백그라운드(&)로 돌리면 검사가 잡는다(같은 틱에서 L2 와 겹침)";; *) ng "⑤m2 미검출 [$w2]";; esac
else ng "⑤m 돌연변이 앵커 없음(rc=$MRC) — 틱의 L2·충실구현 호출 또는 배리어 줄을 못 찾았다"; fi
rm -rf "$T"
echo "결과: PASS=$PASS FAIL=$FAIL"
printf '{"test":"rf_l2_auto_gate","pass":%d,"fail":%d,"total":%d,"skipped":0}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
