#!/usr/bin/env bash
# test_scn_chain_gen_guard.sh — 강화 사슬 생성기 러너(02_Infrastructure/ops/chain_gen_run.sh)의 읽기 경계 · 무인 호출 계약 (2026-11-10)
#   G  실제 arm_gen_read_guard.sh(사본) 에 생성기가 할 법한 읽기를 넣어 block / pass 단정(성과 · 사슬 측정 · 닫기 산출 · 결과 원장 · 다른 사슬 원장 ·
#      루트 표기 3꼴 · Grep 뿌리 · 작업 폴더 pass) — 양성 대조
#   R  러너를 가짜 claude(CLAUDE_BIN · 받은 환경 · 인자 · cwd 를 기록)로 돌린다: 청정 표식 · 자동 기억 차단 · 자동 커밋 끔 · 읽기 3도구 · 금지 목록 · cwd = 루트 ·
#      한도 문구 = 종료 3 · 시간 초과 = 종료 6 · 가드가 무력하면(항상 통과 훅 · 설정 미등록) claude 를 부르지 않고 종료 5
#   M  돌연변이(사본 · 소스 텍스트 치환 · 치환 성사 단정): 청정 표식 제거 · 탐침 호출 제거 · 허용 도구에 Bash 추가 · 한도 폴백 비움 되살림 → 빨강
#   F  한도 폴백(2026-11-11 · 생성기 = Fable): Fable 한도 문구 → opus 로 처음부터 1회 재실행 · 종료 0 · gen_result model=opus · fell_back=1 · 1차 출력 보존 /
#      폴백까지 한도 = 종료 3 / Opus 로 해석되면 폴백 없음(1회 · 종료 3 — 종전 그대로)
#   격리: 임시 루트(저장소 밖) · 비밀 값은 '있음/없음'만 기록 · 실제 LLM · 텔레그램 · 네트워크 0
# 실행: bash 08_Tests/scenarios/test_scn_chain_gen_guard.sh   (대상 = CT_GEN_UNDER_TEST · CT_HELPER_UNDER_TEST · CT_CFG_UNDER_TEST 또는 저장소 파일)
set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="${CT_TEST_REPO:-$(cd "$SELF_DIR/../.." && pwd)}"
GEN_SRC="${CT_GEN_UNDER_TEST:-$REPO/02_Infrastructure/ops/chain_gen_run.sh}"
HLP_SRC="${CT_HELPER_UNDER_TEST:-$REPO/02_Infrastructure/programs/chain_tick.R}"
CFG_SRC="${CT_CFG_UNDER_TEST:-$REPO/06_Registry/chain_tick.json}"
SH="${BASH:-bash}"; PY="${QVEST_PY:-python}"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: ${2:-}"; }
for f in "$GEN_SRC" "$HLP_SRC" "$CFG_SRC"; do [ -f "$f" ] || { echo "대상 없음: $f"; printf '{"test":"scn_chain_gen_guard","pass":0,"fail":1,"total":1}\n'; exit 1; }; done
"$SH" -n "$GEN_SRC" && ok "R0 문법(bash -n)" || ng "R0 문법" "$GEN_SRC"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
EV="$T/empty.Renviron"; : > "$EV"; export R_ENVIRON_USER="$EV"
mkroot(){ # $1 = 루트 이름 → 사본 루트(코드 · 정책 · 설정 사본) 경로
  local X="$T/$1"
  mkdir -p "$X/02_Infrastructure/ops" "$X/02_Infrastructure/programs" "$X/02_Infrastructure/hooks/policies" "$X/06_Registry" "$X/.claude" "$X/.cache"
  cp "$GEN_SRC" "$X/02_Infrastructure/ops/chain_gen_run.sh"; cp "$HLP_SRC" "$X/02_Infrastructure/programs/chain_tick.R"; cp "$CFG_SRC" "$X/06_Registry/chain_tick.json"
  for f in resolve_project.sh rf_llm_env.sh _sched_failure_classify.sh; do cp "$REPO/02_Infrastructure/ops/$f" "$X/02_Infrastructure/ops/"; done
  cp "$REPO/02_Infrastructure/hooks/arm_gen_read_guard.sh" "$X/02_Infrastructure/hooks/"; cp "$REPO/02_Infrastructure/hooks/policies/arm_gen_read_guard.json" "$X/02_Infrastructure/hooks/policies/"
  : > "$X/02_Infrastructure/hooks/qvest_hook_router.py"; cp "$REPO/.claude/settings.json" "$X/.claude/settings.json"
  local C="$X/04_Research/programs/P4_ASSEMBLY/P4C01_t"; mkdir -p "$C/measure" "$X/04_Research/programs/P4_ASSEMBLY/P4C02_o" "$X/06_Registry"
  echo '{}' > "$C/measure/k0.json"; echo '{}' > "$C/finalize.json"; : > "$X/06_Registry/round_outcomes.jsonl"; : > "$X/04_Research/programs/P4_ASSEMBLY/P4C02_o/chain_steps.jsonl"
  local W="$X/04_Research/programs/P4_ASSEMBLY/_lanes/P4C01_t/k1_20261110_120000"; mkdir -p "$W"
  for f in design_input.md investment_philosophy_charter.md toolbox.md parent_cell_spec.json; do echo "x" > "$W/$f"; done; echo "프롬프트" > "$W/prompt.md"
  echo "$X"
}
wp(){ (cd "$1" && pwd -W 2>/dev/null || pwd); }
FB="$T/fakebin"; mkdir -p "$FB"
cat > "$FB/claude" <<'EOF'
#!/usr/bin/env bash
R="${FAKE_REC:?}"; mkdir -p "$R"
{ printf 'CLEAN=%s\nWDIRENV=%s\nUNA=%s\nAM=%s\nSKIPAC=%s\nSKIPAP=%s\nCWD=%s\nTOKEN=%s\n' "${QVEST_CLEAN_LANE:-}" "${QVEST_CLEAN_WDIR:-}" "${QVEST_UNATTENDED_LANE:-}" \
    "${CLAUDE_CODE_DISABLE_AUTO_MEMORY:-}" "${QVEST_SKIP_AUTO_COMMIT:-}" "${QVEST_SKIP_AUTO_PUSH:-}" "$(pwd -W 2>/dev/null || pwd)" "$([ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && echo 있음 || echo 없음)"
  printf 'ARGS=%s\n' "$*"; } > "$R/call.env"
model=""; prev=""; for a in "$@"; do [ "$prev" = "--model" ] && model="$a"; prev="$a"; done
printf 'MODEL=%s ARGS=%s\n' "$model" "$*" >> "$R/calls.log"
cat > /dev/null
sleep "${FAKE_SLEEP:-0}"
case "${FAKE_MODE:-ok}:$model" in
  limit:*) echo "You've hit your weekly limit · resets 3pm" ;;
  limit_fable:fable) echo "You've reached your Fable limit · resets 3pm" ;;
  *) printf '%s\n' '설계' '```json' '{"hypothesis":"h","mechanism":"m","block_type":"weighting","delta":{"weighting":{"kind":"inv_vol","window":60}}}' '```' ;;
esac
EOF
chmod +x "$FB/claude"
run_gen(){ # $1 = 루트 · 나머지 env — 결과 rc 를 $T/rc 에
  local X="$1"; shift; local XW; XW="$(wp "$X")"
  rm -rf "$T/rec"
  ( cd "$X" && env -u QVEST_CLEAN_LANE -u QVEST_CLEAN_WDIR -u QVEST_DESIGN_LANE -u QVEST_ARM_GEN QM_ROOT="$XW" CLAUDE_PROJECT_DIR="$XW" CLAUDE_BIN="$FB/claude" FAKE_REC="$T/rec" \
      CLAUDE_CODE_OAUTH_TOKEN="test-fixture-not-a-secret" QVEST_PY="$PY" QVEST_NO_ALERT=1 QVEST_TG_DRY_RUN=1 "$@" \
      "$SH" "$X/02_Infrastructure/ops/chain_gen_run.sh" "$XW/04_Research/programs/P4_ASSEMBLY/_lanes/P4C01_t/k1_20261110_120000" "04_Research/programs/P4_ASSEMBLY/P4C01_t" ) > "$T/out.txt" 2>&1
  echo $? > "$T/rc"
}
rv(){ sed -n "s/^$1=//p" "$T/rec/call.env" 2>/dev/null | head -n 1; }
W_REL="04_Research/programs/P4_ASSEMBLY/_lanes/P4C01_t/k1_20261110_120000"

echo "== G 가드 양성 대조(실제 훅 사본) =="
X="$(mkroot g)"; XW="$(wp "$X")"; WW="$XW/$W_REL"
fire(){ # $1 = 도구 $2 = 경로
  local js; js=$(GT="$1" GPth="$2" GC="$XW" "$PY" -c "import json,os;t=os.environ['GT'];ti={'file_path' if t=='Read' else 'path':os.environ['GPth']};ti.update({} if t=='Read' else {'pattern':'*'});print(json.dumps({'session_id':'t','hook_event_name':'PreToolUse','cwd':os.environ['GC'],'tool_name':t,'tool_input':ti}))")
  (cd "$X" && printf '%s' "$js" | env -u QVEST_DESIGN_LANE -u QVEST_ARM_GEN QVEST_CLEAN_LANE=1 QVEST_CLEAN_WDIR="$WW" CLAUDE_PROJECT_DIR="$XW" QM_ROOT="$XW" QVEST_PY="$PY" \
     QVEST_ARM_GEN_GUARD_LOG="$T/guard.log" "$SH" "$X/02_Infrastructure/hooks/arm_gen_read_guard.sh" 2>/dev/null) | grep -q '"decision": *"block"' && echo block || echo pass
}
BSX="${XW//\//\\}"
for c in "Read|$XW/06_Registry/round_outcomes.jsonl|결과 원장" "Read|$XW/04_Research/programs/P4_ASSEMBLY/P4C01_t/measure/k0.json|사슬 측정(절대)" \
         "Read|04_Research/programs/P4_ASSEMBLY/P4C01_t/measure/k0.json|사슬 측정(상대)" "Read|$XW/04_Research/programs/P4_ASSEMBLY/P4C01_t/finalize.json|닫기 산출 finalize.json" \
         "Read|$XW/04_Research/programs/P4_ASSEMBLY/P4C02_o/chain_steps.jsonl|다른 사슬 원장" "Read|$XW/stage_artifacts/x/authoritative_remeasure.json|권위 등급" \
         "Read|G:/OneDrive/Quant_Module_Moltbot/04_Research/programs/P4_ASSEMBLY/P4C01_t/measure/k0.json|G: 표기" \
         "Read|C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/programs/P4_ASSEMBLY/P4C01_t/measure/k0.json|C: 접합점 표기" \
         "Read|$BSX\\04_Research\\programs\\P4_ASSEMBLY\\P4C01_t\\measure\\k0.json|역슬래시 표기" "Grep|$XW/04_Research/programs/P4_ASSEMBLY|Grep 사슬 뿌리"; do
  IFS='|' read -r tool path what <<< "$c"
  [ "$(fire "$tool" "$path")" = block ] && ok "G $what → block" || ng "G $what" "block 이 아니다: $path"
done
[ "$(fire Read "$WW/design_input.md")" = pass ] && ok "G 작업 폴더 파일 → 통과(경계가 일을 막지 않는다)" || ng "G 작업 폴더" "막혔다"

echo "== R 러너(가짜 claude) =="
X="$(mkroot r1)"; XW="$(wp "$X")"; run_gen "$X"
[ "$(cat "$T/rc")" = 0 ] && ok "R1 정상 → 종료 0" || ng "R1 종료" "rc=$(cat "$T/rc") $(tail -3 "$X/.cache/scheduler_logs/"chain_gen_*.log 2>/dev/null | tr '\n' ' ')"
grep -q '"rc":0' "$X/$W_REL/gen_result.json" 2>/dev/null && grep -q '"reason":"ok"' "$X/$W_REL/gen_result.json" && ok "R1b gen_result.json rc 0 · ok" || ng "R1b gen_result" "$(cat "$X/$W_REL/gen_result.json" 2>/dev/null)"
[ "$(rv CLEAN)" = 1 ] && [ "$(rv WDIRENV)" = "$XW/$W_REL" ] && ok "R2 청정 표식 QVEST_CLEAN_LANE=1 · QVEST_CLEAN_WDIR=작업 폴더" || ng "R2 청정 표식" "CLEAN=$(rv CLEAN) WDIR=$(rv WDIRENV)"
[ "$(rv AM)" = 1 ] && [ "$(rv UNA)" = 1 ] && ok "R3 자동 기억 차단 · 무인 표식(단일 진입 rf_llm_agent_run)" || ng "R3 표식" "AM=$(rv AM) UNA=$(rv UNA)"
[ "$(rv SKIPAC)" = 1 ] && [ "$(rv SKIPAP)" = 1 ] && ok "R4 자동 커밋 · 푸시 끔" || ng "R4" "$(rv SKIPAC)/$(rv SKIPAP)"
A="$(rv ARGS)"
case "$A" in *"--allowed-tools Read,Glob,Grep "*) ok "R5 허용 도구 = Read,Glob,Grep" ;; *) ng "R5 허용 도구" "$A" ;; esac
case "$A" in *--disallowed-tools*Bash*Agent*Write*WebFetch*) ok "R6 금지 목록에 Bash · Agent · Write · WebFetch" ;; *) ng "R6 금지 목록" "$A" ;; esac
case "$A" in *"--dangerously-skip-permissions"*) ng "R6b 권한 우회 인자" "$A" ;; *) ok "R6b 권한 우회 인자 없음(--permission-mode default)" ;; esac
[ "$(rv CWD)" = "$XW" ] && ok "R7 cwd = 저장소 루트(훅이 실린다)" || ng "R7 cwd" "$(rv CWD) ≠ $XW"
[ "$(rv TOKEN)" = "있음" ] && ! grep -rq "test-fixture-not-a-secret" "$X/.cache/scheduler_logs" && ok "R8 토큰 = 있음/없음만 · 로그에 값 없음" || ng "R8 토큰" "값 노출 또는 미전달"
grep -q '가드 탐침 통과' "$X/.cache/scheduler_logs/"chain_gen_*.log && ok "R9 LLM 전 가드 탐침 통과 기록" || ng "R9 탐침 기록" "로그에 없음"
X="$(mkroot r2)"; run_gen "$X" FAKE_MODE=limit
[ "$(cat "$T/rc")" = 3 ] && grep -q '"reason":"usage_limit"' "$X/$W_REL/gen_result.json" && ok "R10 한도 문구(weekly limit) → 종료 3 · reason usage_limit" || ng "R10 한도" "rc=$(cat "$T/rc") $(cat "$X/$W_REL/gen_result.json" 2>/dev/null)"
X="$(mkroot r3)"; run_gen "$X" QVEST_RUN_TIMEOUT=1 FAKE_SLEEP=4
[ "$(cat "$T/rc")" = 6 ] && ok "R11 시간 초과(QVEST_RUN_TIMEOUT=1) → 종료 6" || ng "R11 시간 초과" "rc=$(cat "$T/rc")"
X="$(mkroot r4)"; printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' "echo '{\"continue\":true}'" > "$X/02_Infrastructure/hooks/arm_gen_read_guard.sh"; run_gen "$X"
[ "$(cat "$T/rc")" = 5 ] && [ ! -f "$T/rec/call.env" ] && ok "R12 무력한 훅(항상 통과) → 탐침 실패 · claude 미호출 · 종료 5" || ng "R12 무력 훅" "rc=$(cat "$T/rc") call=$([ -f "$T/rec/call.env" ] && echo 있음)"
X="$(mkroot r5)"; "$PY" -c "import io,sys;p=sys.argv[1];s=io.open(p,encoding='utf-8').read();io.open(p,'w',encoding='utf-8').write(s.replace('arm_gen_read_guard.sh','arm_gen_read_guard_OFF.sh'))" "$X/.claude/settings.json"; run_gen "$X"
[ "$(cat "$T/rc")" = 5 ] && [ ! -f "$T/rec/call.env" ] && ok "R13 settings.json 에 훅 미등록 → claude 미호출 · 종료 5" || ng "R13 미등록" "rc=$(cat "$T/rc")"
X="$(mkroot r6)"; mkdir -p "$X/.cache/chain_gen_run.lock"; echo $$ > "$X/.cache/chain_gen_run.lock/pid"; run_gen "$X"
[ "$(cat "$T/rc")" = 0 ] && [ ! -f "$T/rec/call.env" ] && grep -q '다른 인스턴스' "$X/.cache/scheduler_logs/"chain_gen_*.log && ok "R14 살아 있는 잠금 → skip · claude 미호출 · 홀더 보존" || ng "R14 잠금" "rc=$(cat "$T/rc")"

echo "== F 한도 폴백(생성기 = Fable) =="
ncalls(){ wc -l < "$T/rec/calls.log" 2>/dev/null | tr -d ' '; }
mseq(){ sed -n 's/^MODEL=\([^ ]*\) .*/\1/p' "$T/rec/calls.log" 2>/dev/null | tr '\n' ','; }
gres(){ cat "$1/$W_REL/gen_result.json" 2>/dev/null; }
X="$(mkroot f1)"; run_gen "$X" QVEST_CG_MODEL=fable
[ "$(cat "$T/rc")" = 0 ] && [ "$(ncalls)" = 1 ] && grep -q -- '--model fable --effort max --fallback-model opus' "$T/rec/calls.log" \
  && gres "$X" | grep -q '"model":"fable","fell_back":0' && [ ! -f "$X/$W_REL/out.md.primary" ] \
  && ok "F1 Fable 생성기 · 한도 없음 → 1회 · --model fable --effort max --fallback-model opus · fell_back 0" || ng "F1" "rc=$(cat "$T/rc") calls=$(ncalls) seq=$(mseq) $(gres "$X")"
X="$(mkroot f2)"; run_gen "$X" QVEST_CG_MODEL=fable FAKE_MODE=limit_fable
[ "$(cat "$T/rc")" = 0 ] && [ "$(mseq)" = "fable,opus," ] && gres "$X" | grep -q '"rc":0,"reason":"ok","model":"opus","fell_back":1' \
  && grep -q 'Fable limit' "$X/$W_REL/out.md.primary" && grep -q '"hypothesis"' "$X/$W_REL/out.md" && ! grep -q 'Fable limit' "$X/$W_REL/out.md" \
  && ok "F2 Fable 한도 → opus 로 처음부터 1회 재실행 · 종료 0 · model opus · fell_back 1 · 1차 출력 보존" || ng "F2" "rc=$(cat "$T/rc") seq=$(mseq) $(gres "$X")"
_l2="$(sed -n 2p "$T/rec/calls.log" 2>/dev/null)"
[ -n "$_l2" ] && ! printf '%s' "$_l2" | grep -q -- '--fallback-model' && ok "F2b 폴백 재실행(opus · 둘째 호출)에는 --fallback-model 없음" || ng "F2b 폴백 재실행 인자" "둘째 호출=[${_l2:-없음}]"
grep -q '한도 폴백' "$X/.cache/scheduler_logs/"chain_gen_*.log && ok "F2c 폴백이 로그에 남는다" || ng "F2c 폴백 로그" "없음"
# F2d — 정보 경계(τ_D)는 둘째 호출에도 걸려야 한다: call.env 는 마지막 호출(= 폴백 재실행)의 환경 · 인자다
_a2="$(rv ARGS)"; _f2d=0
case "$_a2" in *"--model opus"*"--allowed-tools Read,Glob,Grep "*) case "$_a2" in *--disallowed-tools*Bash*Agent*Write*WebFetch*) _f2d=1 ;; esac ;; esac
[ "$_f2d" = 1 ] && [ "$(rv CLEAN)" = 1 ] && [ "$(rv WDIRENV)" = "$(wp "$X")/$W_REL" ] && [ "$(rv AM)" = 1 ] && [ "$(rv UNA)" = 1 ] \
  && ok "F2d 폴백 재실행(opus)도 청정 표식 · 작업 폴더 제한 · 자동 기억 차단 · 읽기 3도구 · 금지 목록 그대로" || ng "F2d 폴백 재실행 경계" "CLEAN=$(rv CLEAN) WDIR=$(rv WDIRENV) AM=$(rv AM) UNA=$(rv UNA) ARGS=$_a2"
X="$(mkroot f3)"; run_gen "$X" QVEST_CG_MODEL=fable FAKE_MODE=limit
[ "$(cat "$T/rc")" = 3 ] && [ "$(mseq)" = "fable,opus," ] && gres "$X" | grep -q '"reason":"usage_limit"' \
  && ok "F3 폴백까지 한도 → 재실행은 1회뿐 · 종료 3(틱이 물러난다)" || ng "F3" "rc=$(cat "$T/rc") seq=$(mseq) $(gres "$X")"
X="$(mkroot f4)"; run_gen "$X" FAKE_MODE=limit
[ "$(cat "$T/rc")" = 3 ] && [ "$(ncalls)" = 1 ] && ! grep -q -- '--fallback-model' "$T/rec/calls.log" \
  && ok "F4 Opus 생성기(기본) · 한도 → 폴백 없음 · 1회 · 종료 3(종전 그대로)" || ng "F4" "rc=$(cat "$T/rc") calls=$(ncalls) seq=$(mseq)"

echo "== M 돌연변이 =="
mutgen(){ # id from to 확인 함수 설명
  local X n; X="$(mkroot "m_$1")"
  n=$("$PY" -c 'import sys,io;p,a,b=sys.argv[1:4];s=io.open(p,encoding="utf-8").read();n=s.count(a);io.open(p,"w",encoding="utf-8",newline="").write(s.replace(a,b));print(n)' "$X/02_Infrastructure/ops/chain_gen_run.sh" "$2" "$3" | tr -d '\r')
  [ "$n" = 1 ] || { ng "$1 치환 성사" "치환 수 $n"; return; }
  [ -n "${5:-}" ] && printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' "echo '{\"continue\":true}'" > "$X/02_Infrastructure/hooks/arm_gen_read_guard.sh"
  run_gen "$X" "${@:7}"; if "$4"; then ng "$1 $6" "돌연변이가 살아남았다"; else ok "$1 $6 → 빨강"; fi   # 7번째 인자부터 = 그 돌연변이 실행에 줄 환경
}
c_clean(){ [ "$(rv CLEAN)" = 1 ]; }
c_noprobe(){ [ ! -f "$T/rec/call.env" ]; }
c_tools(){ case "$(rv ARGS)" in *"--allowed-tools Read,Glob,Grep "*) return 0 ;; *) return 1 ;; esac; }
mutgen M1 '  QVEST_CLEAN_LANE=1 QVEST_CLEAN_WDIR="$WDIR" RF_CLAUDE_BIN' '  QVEST_CLEAN_WDIR="$WDIR" RF_CLAUDE_BIN' c_clean "" "청정 표식 제거"
mutgen M2 '_guard_probe "$WDIR" || {' 'true || {' c_noprobe 1 "탐침 호출 제거(무력 훅에서 claude 호출)"
mutgen M3 '--allowed-tools "Read,Glob,Grep"' '--allowed-tools "Read,Glob,Grep,Bash"' c_tools "" "허용 도구에 Bash 추가"
c_fb(){ [ "$(cat "$T/rc")" = 0 ] && [ "$(mseq)" = "fable,opus," ]; }
mutgen M4 'LLM_FALLBACK_MODEL="$_fbm" \' 'LLM_FALLBACK_MODEL="" \' c_fb "" "한도 폴백 비움을 되살리면 Fable 한도에서 재실행이 없다" QVEST_CG_MODEL=fable FAKE_MODE=limit_fable
echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
printf '{"test":"scn_chain_gen_guard","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
