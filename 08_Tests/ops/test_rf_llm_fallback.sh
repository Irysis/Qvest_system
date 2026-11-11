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
#
# (v10.01 2026-10-13) LLM 레인 정책 D12(도훈 채택 — 판단 = Opus · 명확한 사양 실행 = Sonnet · Fable 미사용 · 퇴역 레인 8종 키 삭제)에
#   맞춰 E3 를 다시 썼다: 구판 "13 레인 전부 opus/max" → E3(D12 편성표 13 레인 해석) · E3b(설정의 모든 레인이 명시 model/effort 로
#   해석 · fable 0 · 폴백 0 — 목록은 설정에서 재도출) · E3c(퇴역 레인 = 해석기 기본값 llm.model/effort 낙하) · E3m(E3b 돌연변이).
#   A·C 절 합성 픽스처의 Opus 레인 이름을 퇴역 b1_design → 살아 있는 fidelity_audit 로 바꿨다(합성값 · 거동 불변).
#   Fable 한도 폴백 기제(A~C)는 그대로 잰다. 롤백 태그 pre-v10.01-prescription-20261013
# (v10.2 2026-11-11) 도훈 지시 "1계층 리서치 LLM 호출 중 고품질 추론이 필요한 곳에 최신 페이블 적용"(decision_register LLM-LANE-FABLE-GENERATION-20261111)에 맞춰
#   E3 · E3b · E3m 을 옮겼다: 구판 "fable 0 · 폴백 0" → E3(편성표 14 레인 — 만드는 쪽 replication · chain_generator = fable/max + 폴백 opus/max) ·
#   E3b(Fable 은 지정 레인 FABLE_LANES 에만 · Fable 레인은 폴백 필수 · 그 밖 레인은 폴백 없음 — 목록은 설정에서 재도출) · E3m(지정 밖 fable · 암묵값) ·
#   E3m2(폴백을 끈 돌연변이). 재는 성질은 같다 — 운영 설정이 채택된 편성과 일치하고, 편성 밖 Fable · 폴백 없는 Fable 이 생기면 잡는다.
#   스테이징 검증: QVEST_TEST_LLM_CFG=<후보 설정> 을 주면 운영 설정 대신 그 파일을 잰다.
# (같은 날 "검증도 올려" · LLM-LANE-FABLE-VERIFICATION-20261111) E4(감사 축 편성 — 판독형 3축 fable · 대조형 3축 sonnet) · E4m · E5(Judge 정의 fable/max) 추가.
#   스테이징: QVEST_TEST_AXES=<후보 축 등록부> · QVEST_TEST_JUDGE_MD=<후보 judge.md>.
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
export QVEST_PY="$PY"
LIVE_CFG="${QVEST_TEST_LLM_CFG:-$ROOT/06_Registry/reinforce_auto_config.json}"   # 운영 설정(스테이징 검증 = 후보 설정 경로)
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
  "lanes": {"replication":    {"model": "fable", "effort": "max"},
            "fidelity_audit": {"model": "opus",  "effort": "high"}}}}
EOF
export QVEST_RF_CONFIG="$T/cfg.json"
rf_llm_resolve replication "" ""
r="$LLM_MODEL/$LLM_EFFORT/$LLM_FALLBACK_MODEL/$LLM_FALLBACK_EFFORT"
[ "$r" = "fable/max/opus/max" ] && ok "A1 Fable 레인 → 폴백 opus/max 가 실린다" || ng "A1" "$r"
rf_llm_resolve fidelity_audit "" ""
[ -z "$LLM_FALLBACK_MODEL" ] && [ "$LLM_MODEL/$LLM_EFFORT" = "opus/high" ] \
  && ok "A2 Opus 레인 → 폴백 없음(같은 계열 재실행은 무의미)" || ng "A2" "$LLM_MODEL/$LLM_EFFORT/$LLM_FALLBACK_MODEL"
rf_llm_resolve fidelity_audit "claude-fable-5-1" ""
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

run_case opus_limit fidelity_audit
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
w=$(pin_check "$LIVE_CFG" "$ROOT/06_Registry/rf_fidelity_axes.json" | tr -d '\r')
[ -z "$w" ] && ok "E1 운영 설정·팬아웃 축 전부 별칭(fable/opus/sonnet) — 항상 최신 모델" || ng "E1 모델 ID 고정" "$w"
"$PY" - "$LIVE_CFG" "$T/cfg_pinned.json" <<'PYM'
import io, json, sys
c = json.loads(io.open(sys.argv[1], 'rb').read().decode('utf-8'))
c['llm']['lanes']['replication']['model'] = 'claude-fable-5-1'
io.open(sys.argv[2], 'w', encoding='utf-8').write(json.dumps(c, ensure_ascii=False))
PYM
w=$(pin_check "$T/cfg_pinned.json" "$T/none.json" | tr -d '\r')
printf '%s' "$w" | grep -q "llm.lanes.replication.model=claude-fable-5-1" \
  && ok "E2 [돌연변이] replication 을 ID 로 고정하면 검사가 잡는다" || ng "E2" "[$w]"
if [ -n "${QVEST_TEST_LLM_CFG:-}" ]; then export QVEST_RF_CONFIG="$LIVE_CFG"; else unset QVEST_RF_CONFIG; fi   # 평소 = 해석기의 기본 경로(운영 설정)를 그대로 탄다
## ★2026-09-23 도훈 지시 "무인실행에서 LLM 개입부 모두 opus max" — 구판 E3 는 운영 설정의 replication = fable 을 단정했다.
##   정책이 바뀌었으므로 운영 설정 단정은 **전 레인 opus/max · opus 레인엔 폴백 미부착**으로 옮긴다.
##   Fable 폴백 기제 자체는 위 C 절(합성 픽스처)이 계속 잰다 — 운영 상태를 빌리지 않는다.
## ★(v10.01 2026-10-13) D12(도훈 채택) 역할별 재배정 — 판단(판독·분석·처방·리뷰·감사·감독) = Opus · 명확한 사양 실행(코딩·분류·요약) =
##   Sonnet · Fable 미사용. 퇴역 레인 키 8종은 llm.lanes 에서 빠져 해석기 기본값(llm.model/effort = opus/max)으로 떨어진다.
##   정신은 그대로다 — 운영 설정의 모든 레인이 **명시값**으로 해석되고 fable(따라서 한도 폴백)이 없다.
## ★(v10.2 2026-11-11) 도훈 지시 "최신 페이블 적용"(decision_register LLM-LANE-FABLE-GENERATION-20261111) — 만드는 쪽 두 레인(replication · chain_generator)만
##   Fable(별칭 · 한도 폴백 opus/max). 검증(감사 · 리뷰 · 감독) = Opus · 사양 실행 = Sonnet 은 D12 그대로다. 편성표 셋째 칸 = 실리는 폴백(없으면 none).
PLAN="replication=fable/max/opus:max chain_generator=fable/max/opus:max fidelity_audit=opus/xhigh/none overlay_audit=opus/xhigh/none
      cleaner_distill=sonnet/high/none paper_router=sonnet/high/none paper_atlas=opus/xhigh/none analyst=opus/max/none prescriber=opus/max/none
      reviewer=opus/max/none steward=opus/max/none factor_definer=opus/xhigh/none coder=sonnet/high/none report_writer=sonnet/medium/none"
_e3_bad=""; _e3_n=0
for _p in $PLAN; do
  _l="${_p%%=*}"; _want="${_p#*=}"; _e3_n=$((_e3_n+1))
  rf_llm_resolve "$_l" "" ""
  _got="$LLM_MODEL/$LLM_EFFORT/${LLM_FALLBACK_MODEL:-none}${LLM_FALLBACK_MODEL:+:$LLM_FALLBACK_EFFORT}"
  [ "$_got" = "$_want" ] || _e3_bad="$_e3_bad $_l=$_got(기대 $_want)"
done
[ -z "$_e3_bad" ] && ok "E3 운영 설정 해석 = 11-11 편성 ${_e3_n} 레인(만드는 쪽 2 = fable + 폴백 opus/max · 판단 opus · 사양 실행 sonnet)" || ng "E3" "$_e3_bad"
# E3b — 목록을 설정에서 재도출한다(편성표 밖 레인이 새로 생겨도 같은 규율을 받는다). $1 = 설정 → 위반 목록(없으면 빈 줄)
_lanes_of(){ "$PY" -c "import io,json,sys
c=json.loads(io.open(sys.argv[1],'rb').read().decode('utf-8'))
for k,v in sorted(((c.get('llm') or {}).get('lanes') or {}).items()):
    v=v if isinstance(v,dict) else {}
    print('%s|%s|%s'%(k,v.get('model') or '',v.get('effort') or ''))" "$1" | tr -d '\r'; }
FABLE_LANES=" replication chain_generator "   # Fable 을 쓰기로 정한 레인(도훈 11-11 · LLM-LANE-FABLE-GENERATION-20261111) — 여기 없는 레인의 fable 은 위반
lane_policy_check(){   # 암묵값(model/effort 미기재) · 해석 불일치 · 지정 밖 fable · Fable 레인의 폴백 부재 · 그 밖 레인의 폴백 부착
  local cfg="$1" bad="" l m e
  while IFS='|' read -r l m e; do
    [ -n "$l" ] || continue
    if [ -z "$m" ] || [ -z "$e" ]; then bad="$bad $l:implicit($m/$e)"; continue; fi
    QVEST_RF_CONFIG="$cfg" rf_llm_resolve "$l" "" ""
    [ "$LLM_MODEL/$LLM_EFFORT" = "$m/$e" ] || bad="$bad $l:resolved=$LLM_MODEL/$LLM_EFFORT(설정 $m/$e)"
    if rf_llm_is_fable "$LLM_MODEL"; then
      case "$FABLE_LANES" in *" $l "*) ;; *) bad="$bad $l:fable" ;; esac
      { [ -n "$LLM_FALLBACK_MODEL" ] && ! rf_llm_is_fable "$LLM_FALLBACK_MODEL"; } || bad="$bad $l:no_fallback"
    else
      [ -z "$LLM_FALLBACK_MODEL" ] || bad="$bad $l:fallback=$LLM_FALLBACK_MODEL"
    fi
  done < <(_lanes_of "$cfg")
  printf '%s' "$bad"
}
_n_cfg=$(_lanes_of "$LIVE_CFG" | grep -c '|')
w=$(lane_policy_check "$LIVE_CFG")
[ -z "$w" ] && [ "${_n_cfg:-0}" -ge 1 ] && ok "E3b 설정 llm.lanes 의 모든 레인(${_n_cfg}) — 명시 model/effort 그대로 해석 · Fable 은 지정 레인만(폴백 필수) · 그 밖 레인 폴백 0" || ng "E3b" "n=$_n_cfg [$w]"
# E3c — 퇴역 레인(D12 키 삭제 8종)은 설정에 없고 해석기 기본값으로 떨어진다(alpha_search_queue 등 스크립트가 남은 레인 포함)
_gm=$("$PY" -c "import io,json,sys
c=json.loads(io.open(sys.argv[1],'rb').read().decode('utf-8')); l=c.get('llm') or {}
print('%s/%s'%(l.get('model') or '',l.get('effort') or ''))" "$LIVE_CFG" | tr -d '\r')
_rt_bad=""
for _l in b1_design b5_design lcode_mechanism overlay_propose grid_propose alpha_search_queue mode_queue_research factor_deep_recheck; do
  _lanes_of "$LIVE_CFG" | grep -q "^$_l|" && _rt_bad="$_rt_bad $_l:in_lanes"
  rf_llm_resolve "$_l" "" ""
  [ "$LLM_MODEL/$LLM_EFFORT/${LLM_FALLBACK_MODEL:-none}" = "$_gm/none" ] || _rt_bad="$_rt_bad $_l=$LLM_MODEL/$LLM_EFFORT/${LLM_FALLBACK_MODEL:-none}"
done
[ "$_gm" = "opus/max" ] && [ -z "$_rt_bad" ] && ok "E3c 퇴역 레인 8종 — llm.lanes 에 없고 해석기 기본값 llm.model/effort($_gm)로 떨어진다 · 폴백 0" || ng "E3c" "llm=$_gm [$_rt_bad]"
# E3m — 돌연변이: E3b 검사기가 fable 배정·암묵값을 실제로 잡는가(판별력)
"$PY" - "$LIVE_CFG" "$T/cfg_lane_mut.json" <<'PYM'
import io, json, sys
c = json.loads(io.open(sys.argv[1], 'rb').read().decode('utf-8'))
c['llm']['lanes']['paper_router']['model'] = 'fable'   # 사양 실행 레인 하나를 fable 로
c['llm']['lanes']['coder'].pop('effort', None)          # 다른 레인의 effort 를 지운다(해석기 기본값 max 로 조용히 떨어진다)
io.open(sys.argv[2], 'w', encoding='utf-8').write(json.dumps(c, ensure_ascii=False))
PYM
w=$(lane_policy_check "$T/cfg_lane_mut.json")
if printf '%s' "$w" | grep -q "paper_router:fable" && printf '%s' "$w" | grep -q "coder:implicit"; then
  ok "E3m [돌연변이] 지정 밖 레인 하나를 fable 로 · 다른 레인의 effort 를 지우면 E3b 검사가 잡는다"
else ng "E3m" "[$w]"; fi
# E3m2 — 돌연변이: 폴백 스위치를 끄면 Fable 레인 둘이 폴백 없이 뜬다 → E3b 검사가 잡는가
w=$(QVEST_LLM_FALLBACK=off lane_policy_check "$LIVE_CFG")
if printf '%s' "$w" | grep -q "replication:no_fallback" && printf '%s' "$w" | grep -q "chain_generator:no_fallback"; then
  ok "E3m2 [돌연변이] 폴백을 끄면 Fable 레인 둘의 폴백 부재를 E3b 검사가 잡는다"
else ng "E3m2" "[$w]"; fi
# E4 — 감사 축 등록부 편성(11-11 도훈 "검증도 올려" · LLM-LANE-FABLE-VERIFICATION-20261111): 판독형(필수) 3축 = fable/xhigh · 대조형 3축 = sonnet/high
AXES_LIVE="${QVEST_TEST_AXES:-$ROOT/06_Registry/rf_fidelity_axes.json}"
axes_plan(){ "$PY" -c "import io,json,sys
a=json.loads(io.open(sys.argv[1],'rb').read().decode('utf-8'))['axes']
print(' '.join('%s=%s/%s/%s'%(x['key'],x['model'],x['effort'],'req' if x.get('required') else 'opt') for x in a))" "$1" | tr -d '\r'; }
AX_WANT="signal=fable/xhigh/req timing=sonnet/high/opt universe=sonnet/high/opt portfolio=fable/xhigh/req cost=sonnet/high/opt undeclared=fable/xhigh/req"
_ax="$(axes_plan "$AXES_LIVE")"
[ "$_ax" = "$AX_WANT" ] && ok "E4 감사 축 편성 = 판독형(필수) 3축 fable/xhigh · 대조형 3축 sonnet/high" || ng "E4 감사 축 편성" "[$_ax]"
# E4m — 돌연변이: 필수 축 하나를 opus 로 되돌린 등록부는 편성 대조가 잡는다
"$PY" -c "import io,json,sys
d=json.loads(io.open(sys.argv[1],'rb').read().decode('utf-8'))
[x.update(model='opus') for x in d['axes'] if x['key']=='signal']
io.open(sys.argv[2],'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False))" "$AXES_LIVE" "$T/axes_mut.json"
_axm="$(axes_plan "$T/axes_mut.json")"
[ "$_axm" != "$AX_WANT" ] && printf '%s' "$_axm" | grep -q 'signal=opus/' && ok "E4m [돌연변이] 필수 축을 opus 로 되돌리면 편성 대조가 잡는다" || ng "E4m" "[$_axm]"
# E5 — Judge 에이전트 정의(11-11 도훈 "검증도 올려"): 모델 = 별칭 fable · 노력 max(ID 고정이 아니다 — 별칭이 최신으로 풀린다)
JDG="${QVEST_TEST_JUDGE_MD:-$ROOT/.claude/agents/judge.md}"
_jm="$(sed -n '1,12p' "$JDG" | tr -d '\r' | sed -n 's/^model:[[:space:]]*//p' | head -n 1)"
_je="$(sed -n '1,12p' "$JDG" | tr -d '\r' | sed -n 's/^effort:[[:space:]]*//p' | head -n 1)"
[ "$_jm/$_je" = "fable/max" ] && ok "E5 Judge 정의 = model fable(별칭) · effort max" || ng "E5 Judge 정의" "$_jm/$_je"

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
