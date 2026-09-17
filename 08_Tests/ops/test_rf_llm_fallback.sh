#!/usr/bin/env bash
#==============================================================================
# test_rf_llm_fallback.sh — Fable 한도 → Opus 최신·max 폴백 + 모델 별칭 정책 **양방향 검사** (2026-09-17)
#
# 도훈 지시 2026-09-17:
#   ① "fable 한도 소진하면 opus 5 최대 effort 로 진행되게"
#   ② "opus, fable 모두 다른 명령 없이도 항상 최신 모델 쓰게끔"
# 계기마다 정상 경로와 위반 주입을 **둘 다** 건다. claude 는 가짜 실행 파일(RF_CLAUDE_BIN)로 대체 —
#   실제 모델 호출 0 · 한도 소모 0. 실모델 별칭 확인은 RF_LLM_LIVE=1 일 때만(G절, 한도를 조금 쓴다).
#
# 실행: bash 08_Tests/ops/test_rf_llm_fallback.sh      (부작용 없음 — .cache/_test_rf_llm_fallback.<pid> 만 쓰고 지운다)
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
export QVEST_PY="$PY"
PASS=0; FAIL=0
ok(){ printf '  OK   %s\n' "$1"; PASS=$((PASS+1)); }
ng(){ printf '  FAIL %s — %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
T="$ROOT/.cache/_test_rf_llm_fallback.$$"
rm -rf "$T"; mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
unset QVEST_LLM_FALLBACK RF_CLAUDE_BIN
. "$ROOT/02_Infrastructure/ops/rf_llm_env.sh"

#── A. 해석기 — 폴백은 Fable 계열에만 · 설정 정본 · 스위치 · 마지막 방어선 ──────────────
echo "=== A. 해석기 ==="
cat > "$T/cfg.json" <<'EOF'
{"llm": {"model": "opus", "effort": "max",
  "fable_limit_fallback": {"model": "opus", "effort": "max"},
  "lanes": {"replication": {"model": "fable", "effort": "max"},
            "b1_design":   {"model": "opus",  "effort": "high"}}}}
EOF
export QVEST_RF_CONFIG="$T/cfg.json"
rf_llm_resolve replication "" ""
r="$LLM_MODEL/$LLM_EFFORT/$LLM_FALLBACK_MODEL/$LLM_FALLBACK_EFFORT"
[ "$r" = "fable/max/opus/max" ] && ok "A1 Fable 레인 → 폴백 opus/max 가 실린다" || ng "A1" "$r"
rf_llm_resolve b1_design "" ""
[ -z "$LLM_FALLBACK_MODEL" ] && [ "$LLM_MODEL/$LLM_EFFORT" = "opus/high" ] \
  && ok "A2 Opus 레인 → 폴백 없음(같은 계열 재실행은 무의미)" || ng "A2" "$LLM_MODEL/$LLM_EFFORT/$LLM_FALLBACK_MODEL"
rf_llm_resolve b1_design "claude-fable-5-1" ""
[ "$LLM_FALLBACK_MODEL" = "opus" ] && ok "A3 환경변수로 Fable ID 를 넣어도 계열로 판정 → 폴백 실림" || ng "A3" "[$LLM_FALLBACK_MODEL]"
QVEST_LLM_FALLBACK=off rf_llm_resolve replication "" ""
[ -z "$LLM_FALLBACK_MODEL" ] && ok "A4 QVEST_LLM_FALLBACK=off → 폴백 꺼짐" || ng "A4" "[$LLM_FALLBACK_MODEL]"
printf '{"llm":{"lanes":{"replication":{"model":"fable"}}}}' > "$T/cfg_noblock.json"
QVEST_RF_CONFIG="$T/cfg_noblock.json" rf_llm_resolve replication "" ""
[ "$LLM_FALLBACK_MODEL/$LLM_FALLBACK_EFFORT" = "opus/max" ] \
  && ok "A5 설정에 폴백 블록이 없어도 opus/max(마지막 방어선)" || ng "A5" "$LLM_FALLBACK_MODEL/$LLM_FALLBACK_EFFORT"

#── B. 한도 문구 판정 — 실측 문구는 잡고 정상 출력은 안 잡는다 ────────────────────────
echo "=== B. 한도 문구 판정 ==="
i=0
for s in "You've reached your Fable limit" \
         "You've hit your session limit · resets 2am (Asia/Seoul)" \
         'API Error: 429 {"type":"error","error":{"type":"rate_limit_error"}}'; do
  i=$((i+1)); printf '%s\n' "$s" > "$T/b.out"
  rf_llm_limit_hit "$T/b.out" && ok "B+$i 한도 문구 감지" || ng "B+$i" "$s"
done
i=0
for s in "engine.R 작성 완료 — 가격제한폭(price limit) 30% 를 논문대로 반영" \
         "Done. FIDELITY.json written (limit orders excluded)." \
         ""; do
  i=$((i+1)); printf '%s\n' "$s" > "$T/b.out"
  rf_llm_limit_hit "$T/b.out" && ng "B-$i 오탐" "$s" || ok "B-$i 정상 출력은 한도가 아니다"
done
rf_llm_limit_hit "$T/nonexistent.out" && ng "B-4 파일 부재를 한도로 읽음" || ok "B-4 출력 파일 부재 → 한도 아님"

#── C. 실행기 — 가짜 claude 로 한도 발생·미발생·폴백까지 한도·Opus 레인·스위치 off ──────────
echo "=== C. 실행기 rf_llm_agent_run ==="
cat > "$T/claude_stub.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_CALLS"
model=""; prev=""
for a in "$@"; do [ "$prev" = "--model" ] && model="$a"; prev="$a"; done
cat > /dev/null
case "$STUB_SCENARIO:$model" in
  ok:fable)            printf 'fable engine\n' > "$STUB_WDIR/engine.R"; echo "Done."; exit 0 ;;
  limit_then_ok:fable) printf 'partial\n' > "$STUB_WDIR/engine.R"; echo "You've reached your Fable limit · resets 2am (Asia/Seoul)"; exit 1 ;;
  limit_then_ok:opus)  printf 'opus engine\n' > "$STUB_WDIR/engine.R"; echo "Done."; exit 0 ;;
  limit_both:*)        echo "You've hit your session limit · resets 2am (Asia/Seoul)"; exit 1 ;;
  opus_limit:opus)     echo "You've hit your session limit · resets 2am (Asia/Seoul)"; exit 1 ;;
  *)                   echo "stub: unexpected $STUB_SCENARIO:$model"; exit 3 ;;
esac
EOF
chmod +x "$T/claude_stub.sh"
printf 'prompt body' > "$T/pf.txt"
HOOKS=0
rf_llm_before_fallback() { HOOKS=$((HOOKS+1)); [ -f "$STUB_WDIR/engine.R" ] && mv -f "$STUB_WDIR/engine.R" "$STUB_WDIR/partial.R"; }
run_case() {   # $1 시나리오 · $2 레인
  export STUB_SCENARIO="$1" STUB_CALLS="$T/calls_$1.log" STUB_WDIR="$T/w_$1"
  rm -rf "$STUB_WDIR"; mkdir -p "$STUB_WDIR"; : > "$STUB_CALLS"; HOOKS=0
  rf_llm_resolve "$2" "" ""
  RF_CLAUDE_BIN="$T/claude_stub.sh" rf_llm_agent_run "$T/pf.txt" "$STUB_WDIR/.agent_run.out" 60 --add-dir "$STUB_WDIR"
}
ncalls() { wc -l < "$STUB_CALLS" | tr -d ' '; }

run_case ok replication
c1=$(sed -n 1p "$STUB_CALLS")
if [ "$(ncalls)" = 1 ] && [ "$LLM_RC" = 0 ] && [ "$LLM_FELL_BACK" = 0 ] && [ "$HOOKS" = 0 ] \
   && printf '%s' "$c1" | grep -q -- "--model fable --effort max --fallback-model opus" \
   && grep -q "fable engine" "$STUB_WDIR/engine.R" && [ ! -f "$STUB_WDIR/.agent_run.out.primary" ]; then
  ok "C1 한도 없음 → 1회 · --model fable --effort max --fallback-model opus · 재실행·훅 없음"
else ng "C1" "calls=$(ncalls) rc=$LLM_RC fb=$LLM_FELL_BACK hooks=$HOOKS args=[$c1]"; fi

run_case limit_then_ok replication
c2=$(sed -n 2p "$STUB_CALLS")
if [ "$(ncalls)" = 2 ] && [ "$LLM_RC" = 0 ] && [ "$LLM_FELL_BACK" = 1 ] && [ "$HOOKS" = 1 ] \
   && [ "$LLM_USED_MODEL/$LLM_USED_EFFORT" = "opus/max" ] \
   && printf '%s' "$c2" | grep -q -- "--model opus --effort max" \
   && ! printf '%s' "$c2" | grep -q -- "--fallback-model" \
   && grep -q "opus engine" "$STUB_WDIR/engine.R" && grep -q "partial" "$STUB_WDIR/partial.R" \
   && rf_llm_limit_hit "$STUB_WDIR/.agent_run.out.primary" && ! rf_llm_limit_hit "$STUB_WDIR/.agent_run.out"; then
  ok "C2 Fable 한도 → 훅 1회(반쪽 engine 치움) → opus/max 로 처음부터 재실행 · 1차 출력 보존 · 최종 출력엔 한도 없음"
else ng "C2" "calls=$(ncalls) rc=$LLM_RC fb=$LLM_FELL_BACK hooks=$HOOKS used=$LLM_USED_MODEL/$LLM_USED_EFFORT args2=[$c2]"; fi

run_case limit_both replication
if [ "$(ncalls)" = 2 ] && [ "$LLM_RC" = 1 ] && [ "$LLM_FELL_BACK" = 1 ] && rf_llm_limit_hit "$STUB_WDIR/.agent_run.out"; then
  ok "C3 폴백까지 한도 → 재실행은 1회뿐 · 최종 출력에 한도 문구가 남아 레인이 환경 실패로 잡는다"
else ng "C3" "calls=$(ncalls) rc=$LLM_RC fb=$LLM_FELL_BACK"; fi

run_case opus_limit b1_design
if [ "$(ncalls)" = 1 ] && [ "$LLM_FELL_BACK" = 0 ] && ! grep -q -- "--fallback-model" "$STUB_CALLS"; then
  ok "C4 [위반 주입] Opus 레인이 한도에 걸려도 폴백하지 않는다(정책 = Fable 한도 한정)"
else ng "C4" "calls=$(ncalls) fb=$LLM_FELL_BACK"; fi

export QVEST_LLM_FALLBACK=off
run_case limit_then_ok replication
unset QVEST_LLM_FALLBACK
if [ "$(ncalls)" = 1 ] && [ "$LLM_FELL_BACK" = 0 ] && [ "$LLM_RC" = 1 ] && ! grep -q -- "--fallback-model" "$STUB_CALLS"; then
  ok "C5 [스위치] QVEST_LLM_FALLBACK=off → 1회만 · --fallback-model 없음 · 구판 거동"
else ng "C5" "calls=$(ncalls) fb=$LLM_FELL_BACK rc=$LLM_RC"; fi

#── D. 충실구현 레인 배선 — 신판이 왔는가 + 구판이 남았는가(돌연변이로 검사기 자체도 잰다) ──────
echo "=== D. 충실구현 레인 배선 ==="
LANE="$ROOT/02_Infrastructure/ops/rf_replication_auto.sh"
lane_check() {   # $1 = 레인 파일 → 위반 사유를 한 줄에 모아 출력(없으면 빈 줄)
  local f="$1" why=""
  grep -q "rf_llm_agent_run " "$f"              || why="$why no_agent_run"
  grep -q "^rf_llm_before_fallback()" "$f"      || why="$why no_before_fallback_hook"
  local blk; blk=$(sed -n '/^ENV_FAIL=""/,/^fi$/p' "$f")
  printf '%s' "$blk" | grep -q 'RUN_OUT'        || why="$why env_fail_not_on_run_out"
  printf '%s' "$blk" | grep -q '"\$LOG"'        && why="$why env_fail_greps_day_log"
  grep -qE '^[[:space:]]*timeout [0-9]+ claude -p' "$f" && why="$why direct_claude_call_left"
  printf '%s' "$why"
}
w=$(lane_check "$LANE")
[ -z "$w" ] && ok "D1 레인이 실행기·훅을 쓰고, 환경 실패 판정은 이번 실행 출력만 본다" || ng "D1" "$w"
sed 's/elif rf_llm_limit_hit "\$RUN_OUT"; then/elif grep -qiE "$RF_LLM_LIMIT_RE" "$LOG"; then/' "$LANE" > "$T/lane_mut1.sh"
w=$(lane_check "$T/lane_mut1.sh")
printf '%s' "$w" | grep -q "env_fail_greps_day_log" && ok "D2 [돌연변이] 판정을 그날 로그로 되돌리면 검사가 잡는다" || ng "D2" "[$w]"
{ cat "$LANE"; printf '\ntimeout 3000 claude -p < "$PF" --model fable\n'; } > "$T/lane_mut2.sh"
w=$(lane_check "$T/lane_mut2.sh")
printf '%s' "$w" | grep -q "direct_claude_call_left" && ok "D3 [돌연변이] 실행기를 우회한 직접 호출이 생기면 검사가 잡는다" || ng "D3" "[$w]"
bash -n "$LANE" && ok "D4 레인 문법" || ng "D4" "bash -n 실패"

#── E. 모델 별칭 정책 — 활성 설정에 모델 ID 고정이 없다(이력 키는 대상 아님) ─────────────────
echo "=== E. 모델 별칭 정책 ==="
pin_check() {   # $1 = 설정 · $2 = 팬아웃 축 등록부 → 고정 ID 목록(없으면 빈 줄)
  "$PY" - "$1" "$2" <<'PYE'
import io, json, re, sys
pat = re.compile(r'^claude-(opus|fable|sonnet|haiku|mythos)-')
bad = []
def chk(name, v):
    if isinstance(v, str) and pat.match(v): bad.append('%s=%s' % (name, v))
c = json.loads(io.open(sys.argv[1], 'rb').read().decode('utf-8'))
llm = c.get('llm') or {}
chk('llm.model', llm.get('model'))
chk('llm.fable_limit_fallback.model', (llm.get('fable_limit_fallback') or {}).get('model'))
for k, v in (llm.get('lanes') or {}).items(): chk('llm.lanes.%s.model' % k, (v or {}).get('model'))
try:
    a = json.loads(io.open(sys.argv[2], 'rb').read().decode('utf-8'))
    for i, ax in enumerate(a.get('axes') or []): chk('axes[%d].model' % i, ax.get('model'))
except Exception:
    pass
print(';'.join(bad))
PYE
}
w=$(pin_check "$ROOT/06_Registry/reinforce_auto_config.json" "$ROOT/06_Registry/rf_fidelity_axes.json" | tr -d '\r')
[ -z "$w" ] && ok "E1 운영 설정·팬아웃 축 전부 별칭(fable/opus/sonnet) — 항상 최신 모델" || ng "E1 모델 ID 고정" "$w"
"$PY" - "$ROOT/06_Registry/reinforce_auto_config.json" "$T/cfg_pinned.json" <<'PYM'
import io, json, sys
c = json.loads(io.open(sys.argv[1], 'rb').read().decode('utf-8'))
c['llm']['lanes']['replication']['model'] = 'claude-fable-5-1'
io.open(sys.argv[2], 'w', encoding='utf-8').write(json.dumps(c, ensure_ascii=False))
PYM
w=$(pin_check "$T/cfg_pinned.json" "$T/none.json" | tr -d '\r')
printf '%s' "$w" | grep -q "llm.lanes.replication.model=claude-fable-5-1" \
  && ok "E2 [돌연변이] replication 을 ID 로 고정하면 검사가 잡는다" || ng "E2" "[$w]"
unset QVEST_RF_CONFIG
rf_llm_resolve replication "" ""
[ "$LLM_MODEL/$LLM_FALLBACK_MODEL/$LLM_FALLBACK_EFFORT" = "fable/opus/max" ] \
  && ok "E3 운영 설정 해석: replication = fable → 한도 시 opus/max" || ng "E3" "$LLM_MODEL/$LLM_FALLBACK_MODEL/$LLM_FALLBACK_EFFORT"

#── G. (선택) 실모델 별칭 확인 — RF_LLM_LIVE=1 일 때만. 한도를 조금 쓴다 ─────────────────────
echo "=== G. 실모델 별칭 (RF_LLM_LIVE=1 일 때만) ==="
if [ "${RF_LLM_LIVE:-0}" = "1" ]; then
  for pair in "fable:claude-fable-" "opus:claude-opus-"; do
    al="${pair%%:*}"; pre="${pair#*:}"
    got=$(cd "$T" && printf 'Reply with exactly: OK' | timeout 300 claude -p --model "$al" --effort low \
            --no-session-persistence --output-format json 2>/dev/null \
          | "$PY" -c "import json,sys; d=json.load(sys.stdin); print(','.join(sorted((d.get('modelUsage') or {}).keys())))" 2>/dev/null | tr -d '\r')
    case "$got" in "$pre"*) ok "G $al → $got (산출물 modelUsage 로 확인)" ;; *) ng "G $al" "[$got]" ;; esac
  done
else
  echo "  SKIP (RF_LLM_LIVE=1 로 실행하면 fable/opus 별칭이 푸는 실제 모델을 산출물로 확인)"
fi

echo
printf '합계: 통과 %d · 실패 %d\n' "$PASS" "$FAIL"
printf '{"test":"rf_llm_fallback","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
