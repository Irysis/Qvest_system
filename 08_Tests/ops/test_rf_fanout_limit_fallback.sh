#!/usr/bin/env bash
#==============================================================================
# test_rf_fanout_limit_fallback.sh — 충실도 감사 팬아웃: Fable 축의 한도 폴백 거동 (2026-11-11)
#
# 왜: 도훈 11-11 "검증도 올려"(decision_register LLM-LANE-FABLE-VERIFICATION-20261111) — 판독형(필수) 3축이 Fable 이 됐다.
#   필수 축이 한도로 죽으면 병합 판정이 unverifiable 이 되어 그 논문의 감사가 통째로 서지 않는다. 그래서 Fable 축은
#   한도 문구가 나오면 폴백 모델(설정 llm.fable_limit_fallback · opus/max)로 **처음부터 한 번** 다시 돈다
#   (rf_llm_env.sh::rf_llm_agent_run · 도훈 09-17 "fable 한도 소진하면 opus 최대 effort 로").
# 재는 것 — 가짜 claude(RF_CLAUDE_BIN) + 실제 병합기(R):
#   P1 한도 없음        축마다 1회 · Fable 축 호출에 --fallback-model opus · 그 밖 축엔 없음 · 병합 판정 faithful
#   P2 Fable 한도       Fable 축만 opus/max 로 재실행(호출 수 = 축 수 + Fable 축 수) · 1차가 쓰다 만 축 파일은 재실행 전에 치워진다 ·
#                       재실행엔 --fallback-model 없음 · 병합 판정 faithful · 로그에 fell_back=1 · 그날 로그에 한도 문구가 남지 않는다
#   P3 폴백까지 한도    재실행은 1회뿐 · 필수 축 파일 없음 → 병합 판정이 faithful 이 아니다
#   P4 Opus 축 한도     폴백 없음(호출 수 = 축 수) — 정책은 Fable 한도 한정이다
#   P5 청정 스폰        청정 표식이 실린 스폰이면 폴백 재실행도 청정 금지 목록 · 표식 그대로(정보 경계)
#   M1 돌연변이         축 모델을 폴백 없이 넘기던 구판 줄로 되돌리면 P2 가 깨진다(재실행 없음 · faithful 아님)
#   M2 돌연변이         반쪽 축 파일 청소를 지우면 재실행이 1차의 반쪽 파일을 본다
# 격리: wdir · 저널 · 로그 = 임시 디렉터리(QVEST_RP_JLOG · QVEST_FA_LOG · QVEST_RF_CONFIG) — 운영 저널 · 로그는 1바이트도 안 자란다.
#       실제 claude 는 한 번도 불리지 않는다(PATH 앞 감시 shim).
# 실행: bash 08_Tests/ops/test_rf_fanout_limit_fallback.sh     (스테이징 검증: QVEST_TEST_FANOUT_SRC=<후보 러너>)
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
ROOTF="$("$PY" -c "import sys;print(sys.argv[1].replace(chr(92),chr(47)))" "$ROOT")"
cd "$ROOTF" || exit 1
PASS=0; FAIL=0
ok(){ printf '  OK   %s\n' "$1"; PASS=$((PASS+1)); }
ng(){ printf '  FAIL %s — %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }

FAN="${QVEST_TEST_FANOUT_SRC:-$ROOTF/02_Infrastructure/ops/rf_fidelity_fanout.sh}"
AXES_SRC="$ROOTF/06_Registry/rf_fidelity_axes.json"
OPLOG="$ROOTF/.cache/scheduler_logs/fidelity_fanout_$(date +%Y%m%d).log"
OPJ="$ROOTF/.cache/reinforce_auto_log.jsonl"
fsize(){ "$PY" -c "import os,sys;print(os.path.getsize(sys.argv[1]) if os.path.exists(sys.argv[1]) else -1)" "$1"; }
OPLOG0=$(fsize "$OPLOG"); OPJ0=$(fsize "$OPJ")
[ -f "$FAN" ] || { echo "대상 없음: $FAN"; printf '{"test":"rf_fanout_limit_fallback","pass":0,"fail":1,"total":1}\n'; exit 1; }
bash -n "$FAN" && ok "S0 러너 문법(bash -n)" || ng "S0 러너 문법" "$FAN"

TMP="$ROOTF/.cache/_test_fa_limit_$$"
rm -rf "$TMP"; mkdir -p "$TMP/bin"
trap 'rm -rf "$TMP"' EXIT
# 실제 claude 감시 shim — 불리면 표식을 남긴다(러너는 RF_CLAUDE_BIN 만 불러야 한다)
printf '#!/usr/bin/env bash\ntouch "%s/real_claude_was_called"\nexit 0\n' "$TMP" > "$TMP/bin/claude"; chmod +x "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"
# 폴백 정본을 시험 안에 고정한다(운영 설정 값에 기대지 않는다)
printf '{"llm":{"model":"opus","effort":"max","fable_limit_fallback":{"model":"opus","effort":"max"}}}' > "$TMP/cfg.json"

# 축 등록부 두 벌 — 운영 등록부의 축 · 문구를 그대로 쓰되 필수(판독형) 축의 모델만 정한다(셸에 축 이름을 박지 않는다)
"$PY" - "$AXES_SRC" "$TMP/axes_fable.json" "$TMP/axes_opus.json" <<'PYAX'
import io, json, sys
d = json.load(io.open(sys.argv[1], encoding='utf-8'))
for path, m in ((sys.argv[2], 'fable'), (sys.argv[3], 'opus')):
    e = json.loads(json.dumps(d))
    for ax in e['axes']:
        if ax.get('required'):
            ax['model'] = m
    io.open(path, 'w', encoding='utf-8', newline='').write(json.dumps(e, ensure_ascii=False))
PYAX
NAX=$("$PY" -c "import io,json,sys;print(len(json.load(io.open(sys.argv[1],encoding='utf-8'))['axes']))" "$TMP/axes_fable.json" | tr -d '\r')
NREQ=$("$PY" -c "import io,json,sys;print(sum(1 for a in json.load(io.open(sys.argv[1],encoding='utf-8'))['axes'] if a.get('required')))" "$TMP/axes_fable.json" | tr -d '\r')
[ "${NREQ:-0}" -ge 1 ] && [ "${NAX:-0}" -gt "${NREQ:-0}" ] && ok "S1 축 ${NAX}개 중 필수(판독형) ${NREQ}개 — 두 부류가 다 있다" || ng "S1 축 구성" "축=$NAX 필수=$NREQ"

# 가짜 claude — 프롬프트(stdin)에서 자기 축 파일 경로를 찾아 판정을 쓴다. 호출마다 한 줄 기록(축 · 모델 · 시작 때 축 파일 유무 · 청정 표식 · 인자).
cat > "$TMP/fake_claude" <<'FAKE'
#!/usr/bin/env bash
model=""; prev=""; for a in "$@"; do [ "$prev" = "--model" ] && model="$a"; prev="$a"; done
prompt="$(cat)"
out="$(printf '%s' "$prompt" | grep -o "${FAKE_WDIR}/fidelity_axis_[a-z_]*\.json" | head -n 1)"
key="$(printf '%s' "$out" | sed 's/.*fidelity_axis_\(.*\)\.json/\1/')"
existed=0; [ -n "$out" ] && [ -f "$out" ] && existed=1
printf '%s\t%s\t%s\t%s\t%s\n' "${key:-?}" "$model" "$existed" "${QVEST_CLEAN_LANE:-0}" "$*" >> "$FAKE_CALLS"
write_axis(){ printf '{"axis":"%s","verdict":"faithful","undeclared_changes":[],"signal_mismatch":[],"evidence":"3절 대조 완료(%s)","confidence":"high","checked":"전 항목","note":""}' "$key" "$key" > "$out"; }
case "${FAKE_SCENARIO:-ok}:$model" in
  limit_fable:fable|limit_all:fable) printf 'partial-from-fable' > "$out"; echo "You've reached your Fable limit · resets 3pm (Asia/Seoul)"; exit 1 ;;
  limit_all:opus|limit_opus:opus)    echo "You've hit your session limit · resets 3pm (Asia/Seoul)"; exit 1 ;;
  *) write_axis; echo "축 $key 판정: faithful"; exit 0 ;;
esac
FAKE
chmod +x "$TMP/fake_claude"

mk_wdir(){ rm -rf "$1"; mkdir -p "$1"; printf '%s\n' 'FACTORS <- data.table::data.table(Date = as.Date("2020-01-31"), Ticker = "A", Score = 1)' > "$1/engine.R"; }
run_fan(){  # $1 = 러너 · $2 = 이름 · $3 = 시나리오 · $4 = 축 등록부 · [$5.. = 추가 환경] → 종료 코드를 $TMP/rc_<이름> 에
  local fan="$1" nm="$2" sc="$3" ax="$4"; shift 4
  local w="$TMP/w_$nm"; mk_wdir "$w"; : > "$TMP/calls_$nm.tsv"
  env QVEST_RF_ROOT="$ROOTF" QM_ROOT="$ROOTF" QVEST_RF_AXES="$ax" QVEST_RF_CONFIG="$TMP/cfg.json" QVEST_RP_JLOG="$TMP/j_$nm.jsonl" \
      QVEST_FA_LOG="$TMP/log_$nm.log" RF_CLAUDE_BIN="$TMP/fake_claude" FAKE_CALLS="$TMP/calls_$nm.tsv" FAKE_SCENARIO="$sc" FAKE_WDIR="$w" \
      QVEST_PY="$PY" "$@" bash "$fan" "$w" "" "https://arxiv.org/abs/0000.00000" "0000.00000" > "$TMP/out_$nm.txt" 2>&1
  echo $? > "$TMP/rc_$nm"
}
ncalls(){ grep -c . "$TMP/calls_$1.tsv" 2>/dev/null | tr -d ' '; }
nmodel(){ awk -F'\t' -v m="$2" '$2==m' "$TMP/calls_$1.tsv" | grep -c . | tr -d ' '; }          # 그 모델로 불린 횟수
verdict(){ "$PY" -c "import io,json,sys
try: print(json.load(io.open(sys.argv[1],encoding='utf-8')).get('verdict'))
except Exception: print('NOFILE')" "$TMP/w_$1/fidelity_audit.json" | tr -d '\r'; }
lim_re="(reached|hit) your [A-Za-z0-9 .-]*limit|(session|usage) limit"

echo "=== P1 한도 없음 — Fable 축만 폴백 인자를 싣는다 ==="
run_fan "$FAN" p1 ok "$TMP/axes_fable.json"
[ "$(ncalls p1)" = "$NAX" ] && [ "$(nmodel p1 fable)" = "$NREQ" ] && ok "P1a 축마다 1회(${NAX}) · Fable 호출 ${NREQ}" || ng "P1a 호출 수" "calls=$(ncalls p1) fable=$(nmodel p1 fable)"
_bad=$(awk -F'\t' '$2=="fable" && $5 !~ /--model fable --effort xhigh --fallback-model opus/' "$TMP/calls_p1.tsv" | grep -c . | tr -d ' ')
[ "$_bad" = 0 ] && ok "P1b Fable 축 호출 = --model fable --effort xhigh --fallback-model opus" || ng "P1b Fable 축 인자" "$(awk -F'\t' '$2=="fable"{print $5}' "$TMP/calls_p1.tsv" | head -n 1 | cut -c1-120)"
_bad=$(awk -F'\t' '$2!="fable" && $5 ~ /--fallback-model/' "$TMP/calls_p1.tsv" | grep -c . | tr -d ' ')
[ "$_bad" = 0 ] && ok "P1c Fable 이 아닌 축 호출엔 --fallback-model 없음" || ng "P1c 폴백 인자가 새어 나갔다" "$_bad 건"
[ "$(verdict p1)" = "faithful" ] && ok "P1d 병합 판정 faithful" || ng "P1d 병합 판정" "$(verdict p1) · $(tail -n 3 "$TMP/out_p1.txt" | tr '\n' ' ' | cut -c1-200)"

echo "=== P2 Fable 한도 — 그 축만 opus/max 로 처음부터 다시 돈다 ==="
run_fan "$FAN" p2 limit_fable "$TMP/axes_fable.json"
[ "$(ncalls p2)" = "$((NAX + NREQ))" ] && [ "$(nmodel p2 fable)" = "$NREQ" ] && ok "P2a 호출 수 = 축 ${NAX} + 재실행 ${NREQ}" || ng "P2a 호출 수" "calls=$(ncalls p2) fable=$(nmodel p2 fable)"
_re=$(awk -F'\t' '$2=="opus" && $5 ~ /--model opus --effort max/ && $5 !~ /--fallback-model/' "$TMP/calls_p2.tsv" | grep -c . | tr -d ' ')
[ "$_re" = "$NREQ" ] && ok "P2b 재실행 ${NREQ}건 = --model opus --effort max · --fallback-model 없음" || ng "P2b 재실행 인자" "맞는 재실행 $_re 건"
_dirty=$(awk -F'\t' '$2=="opus" && $3!="0"' "$TMP/calls_p2.tsv" | grep -c . | tr -d ' ')
[ "$_dirty" = 0 ] && [ "$_re" -ge 1 ] && ok "P2c 재실행은 빈 자리에서 시작한다(1차의 반쪽 축 파일이 치워졌다)" || ng "P2c 반쪽 축 파일" "재실행이 본 잔재 $_dirty 건"
[ "$(verdict p2)" = "faithful" ] && ok "P2d 병합 판정 faithful(필수 축이 살아남았다)" || ng "P2d 병합 판정" "$(verdict p2)"
[ "$(grep -c 'fell_back=1' "$TMP/log_p2.log" 2>/dev/null | tr -d ' ')" = "$NREQ" ] && ok "P2e 로그에 축마다 fell_back=1" || ng "P2e 폴백 로그" "$(grep -c 'fell_back=1' "$TMP/log_p2.log" 2>/dev/null)"
grep -qiE "$lim_re" "$TMP/log_p2.log" 2>/dev/null && ng "P2f 그날 로그에 한도 문구가 남았다" "뒤의 한도 판정이 이 성공을 한도로 읽는다" || ok "P2f 그날 로그에 한도 문구 없음(1차 출력은 로그에 붙지 않는다)"

echo "=== P3 폴백까지 한도 — 재실행은 한 번뿐 · faithful 이 나오지 않는다 ==="
run_fan "$FAN" p3 limit_all "$TMP/axes_fable.json"
[ "$(ncalls p3)" = "$((NAX + NREQ))" ] && ok "P3a 재실행은 축당 1회뿐(호출 $(ncalls p3))" || ng "P3a 호출 수" "$(ncalls p3)"
[ "$(verdict p3)" != "faithful" ] && [ "$(verdict p3)" != "NOFILE" ] && ok "P3b 필수 축이 다 죽으면 판정 = $(verdict p3)(faithful 아님)" || ng "P3b 병합 판정" "$(verdict p3)"

echo "=== P4 Opus 축 한도 — 폴백하지 않는다 ==="
run_fan "$FAN" p4 limit_opus "$TMP/axes_opus.json"
[ "$(ncalls p4)" = "$NAX" ] && ! grep -q -- '--fallback-model' "$TMP/calls_p4.tsv" && ok "P4a 재실행 0 · --fallback-model 0(정책 = Fable 한도 한정)" || ng "P4a" "calls=$(ncalls p4)"
[ "$(verdict p4)" != "faithful" ] && ok "P4b 판정 = $(verdict p4)(종전 거동)" || ng "P4b 병합 판정" "$(verdict p4)"

echo "=== P5 청정 스폰 — 폴백 재실행도 청정 금지 목록 · 표식 그대로 ==="
run_fan "$FAN" p5 limit_fable "$TMP/axes_fable.json" QVEST_CLEAN_LANE=1 QVEST_CLEAN_WDIR="$TMP/w_p5"
_ok5=$(awk -F'\t' '$2=="opus" && $4=="1" && $5 ~ /--disallowed-tools Bash,PowerShell,/ && $5 ~ /,Skill/' "$TMP/calls_p5.tsv" | grep -c . | tr -d ' ')
[ "$_ok5" = "$NREQ" ] && ok "P5 재실행 ${NREQ}건 모두 청정 표식 · 청정 금지 목록(PowerShell … Skill)" || ng "P5 재실행 경계" "맞는 재실행 $_ok5 건 · $(awk -F'\t' '$2=="opus"{print $4" "$5}' "$TMP/calls_p5.tsv" | head -n 1 | cut -c1-160)"

echo "=== M 돌연변이(사본 · 치환 성사 단정) ==="
mut(){  # $1 = 이름 · $2 = 바꿀 문자열 · $3 = 새 문자열 → $TMP/mut_<이름>.sh · 치환 수 1 이어야 한다
  "$PY" -c 'import io,sys
p,a,b,o=sys.argv[1:5]; s=io.open(p,encoding="utf-8").read(); n=s.count(a)
io.open(o,"w",encoding="utf-8",newline="").write(s.replace(a,b)); print(n)' "$FAN" "$2" "$3" "$TMP/mut_$1.sh" | tr -d '\r'
}
n=$(mut m1 'rf_llm_resolve fidelity_axis "$M" "$E"' 'LLM_MODEL="$M"; LLM_EFFORT="$E"; LLM_FALLBACK_MODEL=""; LLM_FALLBACK_EFFORT=""')
if [ "$n" != 1 ]; then ng "M1 치환 성사" "치환 수 $n"; else
  run_fan "$TMP/mut_m1.sh" m1 limit_fable "$TMP/axes_fable.json"
  if [ "$(ncalls m1)" = "$NAX" ] && [ "$(verdict m1)" != "faithful" ]; then ok "M1 폴백 없이 넘기던 구판 줄로 되돌리면 재실행 0 · 판정 $(verdict m1) → P2 가 잡는다"
  else ng "M1 돌연변이가 살아남았다" "calls=$(ncalls m1) verdict=$(verdict m1)"; fi
fi
n=$(mut m2 'rf_llm_before_fallback() { rm -f "$OUT"; }' 'rf_llm_before_fallback() { :; }')
if [ "$n" != 1 ]; then ng "M2 치환 성사" "치환 수 $n"; else
  run_fan "$TMP/mut_m2.sh" m2 limit_fable "$TMP/axes_fable.json"
  _dirty=$(awk -F'\t' '$2=="opus" && $3!="0"' "$TMP/calls_m2.tsv" | grep -c . | tr -d ' ')
  [ "$_dirty" = "$NREQ" ] && ok "M2 청소를 지우면 재실행 ${NREQ}건이 1차의 반쪽 파일을 본다 → P2c 가 잡는다" || ng "M2 돌연변이가 살아남았다" "잔재를 본 재실행 $_dirty 건"
fi

echo "=== Z 격리 ==="
[ ! -e "$TMP/real_claude_was_called" ] && ok "Z1 실제 claude 0회(가짜 실행 파일만)" || ng "Z1 실제 claude 가 불렸다" ""
# 운영 저널 · 로그는 살아 있는 레인이 계속 쓴다 — 크기가 아니라 '이 시험이 쓴 줄이 없는가'를 본다(시작 뒤 늘어난 부분에서 이 시험의 논문 키 · 임시 폴더 이름)
leak=$("$PY" -c "import io,sys
def tail(p,o):
    try:
        with io.open(p,'rb') as f:
            f.seek(max(0,int(o))); return f.read().decode('utf-8','replace')
    except Exception: return ''
j=tail(sys.argv[1],sys.argv[2]); l=tail(sys.argv[3],sys.argv[4]); mark=sys.argv[5]
print(int('0000.00000' in j or mark in j)+int('0000.00000' in l or mark in l))" "$OPJ" "$OPJ0" "$OPLOG" "$OPLOG0" "$(basename "$TMP")" | tr -d '\r')
[ "$leak" = 0 ] && ok "Z2 운영 저널 · 로그에 이 시험이 쓴 줄 없음" || ng "Z2 운영 파일에 시험 흔적" "leak=$leak"

echo
printf '합계: 통과 %d · 실패 %d\n' "$PASS" "$FAIL"
printf '{"test":"rf_fanout_limit_fallback","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
