#!/usr/bin/env bash
# test_scn_data_refresh_heal.sh — 일일 체인 층 배터리 · 아침 자가 복구(실패 단계만 · 1통 · 시간 상한) · 실행 사본 시나리오 (감사 레인 A · 2026-11-10)
#
# 실제 코드 조각을 모래상자에서 돌린다 — 실수집 · 실리프레시 · 실발송 · 운영 잠금 없음:
#   T  배터리 층: dr_battery_tier(원본에서 추출) 일요일 00:03 = weekly · 화요일 00:03 = nightly · 명시 변수 우선 ·
#      [9] 블록(원본 추출)이 가짜 러너에 QVEST_BATTERY_TIER 를 넘긴다 · 돌연변이(전달 삭제) → 러너가 층을 못 받는다
#   B  자가 복구 배터리 생략: 후처리 블록(원본 추출)을 가짜 Rscript · 가짜 러너로 — selfheal = 호출 0 + 건너뜀 1줄 · full = 러너 호출 ·
#      돌연변이(selfheal 분기 무력화) → 러너가 불린다
#   P  계획기(dr_heal_plan.py): 11-10 밤(qw 실패) → qw,universe,macro,krf,fdb · 상태 없음/어제/자가 복구 상태 = FULL · 중도 사망 = 미완 단계부터 ·
#      dart 만 실패 → dart,krf,fdb · 모르는 낡은 항목 = FULL · 돌연변이(qw 하류 비움) → 하류 누락
#   S  단계 기계(원본 추출 · 가짜 단계): 실패 주입 → 상태 파일 기록 → 계획 → 그 단계만 재실행(나머지 건너뜀 로그)
#   N  알림 1회(ensure_data_current 원본 · 모의 발송기): [7] 보고가 나간 실패 = 추가 0 · 사후 감사 조용 · 보고 전 사망 = 1 · 성공 = 0
#   K  시간 상한: 자식을 띄운 가짜 리프레시 → 상한 초과 시 부모 · 자식 모두 종료 + 1통 · 돌연변이(트리 종료 무력화) → 자식 생존
#   X  실행 사본: 원본 스크립트 머리(추출)로 돈 스크립트는 실행 중 원본을 고쳐도 출력이 같다 · 사본 끔(양성 대조) = 출력이 바뀐다 ·
#      daily_refresh.sh --dry-run 은 사본으로 돌고 계획 줄만 낸다
# 요약: 마지막 줄 {"test":"scn_data_refresh_heal","pass":N,"fail":N,"total":N}
set -uo pipefail
T=scn_data_refresh_heal
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; PROJ="$(cd "$_SELF_DIR/../.." && pwd)"
fin() { echo "{\"test\":\"$T\",\"pass\":$1,\"fail\":$2,\"total\":$(( $1 + $2 ))}"; [ "$2" -eq 0 ]; exit $?; }
DR="$PROJ/02_Infrastructure/data/daily_refresh.sh"; EDC="$PROJ/02_Infrastructure/ops/ensure_data_current.sh"
PLN="$PROJ/02_Infrastructure/data/dr_heal_plan.py"
PY="$PROJ/.venv_qvest_ml/Scripts/python.exe"; [ -x "$PY" ] || PY="$PROJ/.venv_qvest_ml/bin/python"
for f in "$DR" "$EDC" "$PLN" "$PY"; do [ -e "$f" ] || { echo "대상 없음: $f"; fin 0 1; }; done
TMP="$(mktemp -d)"; KILLME=()
cleanup() { for p in "${KILLME[@]+"${KILLME[@]}"}"; do kill -KILL "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1 — 기대 '$2' / 실제 '$3'"; fi; }
sub1() { "$PY" -c "import sys;s=open(sys.argv[1],encoding='utf-8').read();n=s.count(sys.argv[3]);open(sys.argv[2],'w',encoding='utf-8',newline='\n').write(s.replace(sys.argv[3],sys.argv[4],1));print(n)" "$@"; }
echo "== $T =="

# ── T 배터리 층 ──
awk '/^dr_battery_tier\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$DR" > "$TMP/tier.sh"
tier() { ( unset QVEST_BATTERY_TIER; source "$TMP/tier.sh"; QVEST_DR_NOW="$1" dr_battery_tier ); }
chk "T1 일요일 00:03(토요일 밤) = weekly" weekly "$(tier '2026-11-15 00:03')"
chk "T2 화요일 00:03 = nightly" nightly "$(tier '2026-11-10 00:03')"
chk "T3 토요일 낮 13:00(금요일 밤 아님 · 토 07시 이후) = weekly" weekly "$(tier '2026-11-14 13:00')"
chk "T4 명시 변수 우선" weekly "$( source "$TMP/tier.sh"; QVEST_BATTERY_TIER=weekly QVEST_DR_NOW='2026-11-10 00:03' dr_battery_tier )"
awk '/^if \[ "\$\{QVEST_DR_SKIP_BATTERY:-0\}" = "1" \]; then$/{f=1} f{print} f&&/^fi$/{exit}' "$DR" > "$TMP/battery.sh"
chk "T5 [9] 블록 추출" YES "$(grep -q 'suite_totals_watch.sh' "$TMP/battery.sh" && echo YES || echo NO)"
mkdir -p "$TMP/infra/ops"
printf '#!/usr/bin/env bash\necho "tier=${QVEST_BATTERY_TIER:-UNSET} args=$*" >> "%s/runner.log"\n' "$TMP" > "$TMP/infra/ops/suite_totals_watch.sh"
runbat() { ( source "$TMP/tier.sh"; INFRA="$TMP/infra"; QVEST_DR_NOW="$1"; unset QVEST_BATTERY_TIER QVEST_DR_SKIP_BATTERY; source "$2" ) >/dev/null 2>&1; tail -1 "$TMP/runner.log" 2>/dev/null; }
chk "T6 가짜 러너가 nightly 를 받는다(화 00:03)" "tier=nightly args=--collect" "$(runbat '2026-11-10 00:03' "$TMP/battery.sh")"
chk "T7 가짜 러너가 weekly 를 받는다(일 00:03)" "tier=weekly args=--collect" "$(runbat '2026-11-15 00:03' "$TMP/battery.sh")"
n=$(sub1 "$TMP/battery.sh" "$TMP/battery_mut.sh" 'QVEST_BATTERY_TIER="$_bt_tier" bash' 'bash')
chk "T8 돌연변이 치환 1곳" 1 "$n"
chk "T8b 돌연변이(층 전달 삭제) → 러너가 층을 못 받는다" "tier=UNSET args=--collect" "$(runbat '2026-11-10 00:03' "$TMP/battery_mut.sh")"

# ── B 자가 복구 배터리 · 후처리 생략 ──
awk '/^if \[ "\$DR_MODE" = "selfheal" \]; then$/{f=1} f{print} /^fi   # ── 후처리/{exit}' "$DR" > "$TMP/post.sh"
chk "B0 후처리 블록 추출" YES "$(grep -q 'build_artifact_index.R' "$TMP/post.sh" && grep -q 'suite_totals_watch.sh' "$TMP/post.sh" && echo YES || echo NO)"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/rscript.log"; exit 0\n' "$TMP" > "$TMP/fakeR"; chmod +x "$TMP/fakeR"
mkdir -p "$TMP/infra/ops" "$TMP/base"
runpost() {  # $1=mode $2=block
  rm -f "$TMP/runner.log" "$TMP/rscript.log"
  ( source "$TMP/tier.sh"; RSCRIPT="$TMP/fakeR"; INFRA="$TMP/infra"; BASE="$TMP/base"; DR_MODE="$1"; unset QVEST_DR_SKIP_BATTERY; [ -n "${3:-}" ] && QVEST_DR_SKIP_BATTERY="$3"
    run_r() { echo "run_r" >> "$TMP/rscript.log"; }; unset QVEST_BATTERY_TIER; QVEST_DR_NOW='2026-11-10 00:03'; source "$2" ) > "$TMP/post.out" 2>&1
  echo "$( [ -f "$TMP/runner.log" ] && wc -l < "$TMP/runner.log" | tr -d ' ' || echo 0)|$( [ -f "$TMP/rscript.log" ] && wc -l < "$TMP/rscript.log" | tr -d ' ' || echo 0)"
}
chk "B1 selfheal(스위치 없이 모드만) — 러너 0 · Rscript 0" "0|0" "$(runpost selfheal "$TMP/post.sh")"
r=$(runpost full "$TMP/post.sh" 1); chk "B1c full + QVEST_DR_SKIP_BATTERY=1 — 러너 0" 0 "${r%%|*}"
chk "B1b 건너뛴 사실 로그 1줄" 1 "$(grep -c '^\[9\] 시험 배터리 건너뜀' "$TMP/post.out")"
r=$(runpost full "$TMP/post.sh"); chk "B2 full — 러너 1회" 1 "${r%%|*}"
n=$(sub1 "$TMP/post.sh" "$TMP/post_mut.sh" 'if [ "$DR_MODE" = "selfheal" ]; then' 'if false; then')
chk "B3 돌연변이 치환 1곳" 1 "$n"
r=$(runpost selfheal "$TMP/post_mut.sh"); chk "B3b 돌연변이(selfheal 분기 무력화) → 러너가 불린다" 1 "${r%%|*}"

# ── P 계획기 ──
st() { printf '{"schema":"daily_refresh_state_v1","run_date":"%s","mode":"%s","status":"%s","stages":[%s],"failed":[]}' "$1" "$2" "$3" "$4" > "$TMP/st.json"; }
S() { printf '{"name":"%s","status":"%s","sec":1}' "$1" "$2"; }
ALLOK="$(S ingest ok),$(S qw failed),$(S universe ok),$(S macro ok),$(S dart ok),$(S krf ok),$(S fdb ok),$(S nonret ok)"
plan() { "$PY" -X utf8 "${PLN_OVERRIDE:-$PLN}" --state "$TMP/st.json" --today 2026-11-10 "$@" | sed -n 's/.*plan=\([^	]*\).*/\1/p'; }
st 2026-11-10 full done "$ALLOK"
chk "P1 11-10 밤(qw 실패 · 벤치 낡음) → qw 와 하류" "qw,universe,macro,krf,fdb" "$(plan --stale 'benchmark(STALE,lag=3d)' --qw-behind 1)"
rm -f "$TMP/st.json"; chk "P2 상태 없음 → FULL" FULL "$(plan)"
st 2026-11-09 full done "$ALLOK"; chk "P3 어제 상태(오늘 밤 실행 없음) → FULL" FULL "$(plan)"
st 2026-11-10 selfheal done "$ALLOK"; chk "P4 자가 복구 상태 → FULL" FULL "$(plan)"
st 2026-11-10 full running "$(S ingest ok),$(S qw ok)"; chk "P5 중도 사망(qw 뒤) → 미완 단계 전부" "universe,macro,dart,krf,fdb,nonret" "$(plan)"
st 2026-11-10 full done "$(S ingest ok),$(S qw ok),$(S universe ok),$(S macro ok),$(S dart failed),$(S krf ok),$(S fdb ok),$(S nonret ok)"
chk "P6 dart 만 실패 → dart,krf,fdb" "dart,krf,fdb" "$(plan)"
chk "P7 모르는 낡은 항목 → FULL" FULL "$(plan --stale 'mystery(STALE)')"
st 2026-11-10 full done "$(S ingest ok),$(S qw ok),$(S universe ok),$(S macro ok),$(S dart ok),$(S krf ok),$(S fdb ok),$(S nonret ok)"
chk "P8 실패 0 · rawdata 낡음 → qw 와 하류" "qw,universe,macro,krf,fdb" "$(plan --stale 'rawdata(STALE,lag=3d)')"
st 2026-11-10 full done "$(S ingest ok),$(S qw ok),$(S universe ok),$(S macro failed),$(S dart ok),$(S krf ok),$(S fdb ok),$(S nonret ok)"
chk "P8b macro 만 실패 → macro 와 하류(krf 포함 — FF 요인의 무위험 금리가 macro 의 ECOS 금리)" "macro,krf,fdb" "$(plan)"
n=$(sub1 "$PLN" "$TMP/plan_mut.py" '"qw": ["universe", "macro", "krf", "fdb"],' '"qw": [],')
chk "P9 돌연변이 치환 1곳" 1 "$n"
st 2026-11-10 full done "$ALLOK"
chk "P9b 돌연변이(qw 하류 비움) → 하류 누락" qw "$(PLN_OVERRIDE="$TMP/plan_mut.py" plan)"

# ── S 단계 기계 + 계획 → 그 단계만 재실행 ──
awk '/^DR_FAILED=\(\)$/{f=1} f{print} f&&/^dr_fail_summary\(\)/{g=1} g&&/^}$/{exit}' "$DR" > "$TMP/mach.sh"
awk '/^DR_MODE="\$\{QVEST_DR_MODE:-full\}"$/{f=1} /^# 배터리 층/{f=0} f' "$DR" >> "$TMP/mach.sh"
chk "S0 단계 기계 추출" YES "$(grep -q 'dr_stage_end()' "$TMP/mach.sh" && grep -q 'dr_state_write()' "$TMP/mach.sh" && echo YES || echo NO)"
fakechain() {  # $1=실패 주입 단계 · 환경 QVEST_DR_ONLY_STAGES · 실행 기록 = ran.log
  ( set -u; DR_DRYRUN=0; BASE="$TMP/base"; mkdir -p "$BASE/.cache"; QVEST_DR_STATE="$TMP/state.json"; source "$TMP/mach.sh"
    for s in $DR_STAGES_ORDER; do
      if dr_want "$s"; then dr_stage_begin "$s"; echo "$s" >> "$TMP/ran.log"; [ "$s" = "$1" ] && DR_FAILED+=("fake_$s(rc=1)"); dr_stage_end; fi
    done
    dr_state_write done "$([ "${#DR_FAILED[@]}" -gt 0 ] && echo 1 || echo 0)" ) > "$TMP/chain.out" 2>&1
}
rm -f "$TMP/ran.log"; unset QVEST_DR_ONLY_STAGES; fakechain qw
chk "S1 밤 실행 — 8단계 전부" 8 "$(wc -l < "$TMP/ran.log" | tr -d ' ')"
chk "S2 상태 파일 — qw failed 기록" YES "$("$PY" -c "import json,sys;d=json.load(open(sys.argv[1]));print('YES' if [s['status'] for s in d['stages'] if s['name']=='qw']==['failed'] and d['status']=='done' else 'NO')" "$TMP/state.json")"
sed -i "s/\"run_date\":\"[0-9-]*\"/\"run_date\":\"2026-11-10\"/" "$TMP/state.json"
P=$("$PY" -X utf8 "$PLN" --state "$TMP/state.json" --today 2026-11-10 | sed -n 's/.*plan=\([^	]*\).*/\1/p')
chk "S3 계획 = qw 와 하류" "qw,universe,macro,krf,fdb" "$P"
rm -f "$TMP/ran.log"; QVEST_DR_ONLY_STAGES="$P" fakechain none
chk "S4 재실행 = 계획한 단계만" "qw universe macro krf fdb" "$(tr '\n' ' ' < "$TMP/ran.log" | sed 's/ $//')"
chk "S5 건너뛴 단계 로그(ingest · dart · nonret)" 3 "$(grep -c '^\[stage\] .* 건너뜀' "$TMP/chain.out")"

# ── N · K ensure_data_current(원본 · 모래상자) ──
B="$TMP/edc"; mkdir -p "$B/02_Infrastructure/hooks" "$B/02_Infrastructure/ops/morning_steps" "$B/02_Infrastructure/data" "$B/.cache" "$B/qepm/observability"
: > "$B/02_Infrastructure/hooks/qvest_hook_router.py"; : > "$B/02_Infrastructure/ops/morning_steps/freshness_audit.R"
sed "s#^LOCKDIR=\"/tmp/qm_daily_refresh.lock\"#LOCKDIR=\"$B/refresh.lock\"#" "$EDC" > "$B/02_Infrastructure/ops/ensure_data_current.sh"
cp "$PROJ/02_Infrastructure/ops/resolve_project.sh" "$B/02_Infrastructure/ops/"; cp "$PLN" "$B/02_Infrastructure/data/"
chk "N0 잠금 경로 격리 치환" YES "$(grep -q "^LOCKDIR=\"$B/refresh.lock\"" "$B/02_Infrastructure/ops/ensure_data_current.sh" && echo YES || echo NO)"
printf '#!/usr/bin/env bash\necho "quiet=${QVEST_FRESHNESS_QUIET:-?}" >> "%s/audit.log"\necho "EDC_RESULT stale=1 as_of=2026-11-09 items=rawdata"\n' "$B" > "$B/fakeR"
printf '#!/usr/bin/env bash\ncase "$*" in *krx_holidays.py*) echo "0|2026-11-09|2026-11-09" ;; *) exec "%s" "$@" ;; esac\n' "$PY" > "$B/fakepy"
chmod +x "$B/fakeR" "$B/fakepy"
mkrefresh() {  # $1 = 본문(bash)
  printf '#!/usr/bin/env bash\nS="%s/.cache/daily_refresh_state.json"\n%s\n' "$B" "$1" > "$B/02_Infrastructure/data/daily_refresh.sh"; chmod +x "$B/02_Infrastructure/data/daily_refresh.sh"; }
edc() { rm -f "$B/.cache/data_currency_stamp.json" "$B/mock_tg.txt" "$B/audit.log"
  ( cd "$B" && QM_ROOT="$B" RSCRIPT="$B/fakeR" QVEST_PY="$B/fakepy" QVEST_EDC_MAX_WAIT=1 QVEST_EDC_TG_MOCK="$B/mock_tg.txt" \
      QVEST_EDC_POLL_S=1 QVEST_EDC_HEAL_TIMEOUT_S="${1:-600}" bash "${2:-$B/02_Infrastructure/ops/ensure_data_current.sh}" > "$B/edc.log" 2>&1; echo $? ); }
ntg() { [ -f "$B/mock_tg.txt" ] && wc -l < "$B/mock_tg.txt" | tr -d ' ' || echo 0; }
TODAY="$(date +%F)"
mkrefresh "echo \"mode=\$QVEST_DR_MODE only=\$QVEST_DR_ONLY_STAGES skipbat=\$QVEST_DR_SKIP_BATTERY rep=\$QVEST_DR_REPORT_TG\" > \"$B/refresh_env.txt\"
printf '{\"schema\":\"daily_refresh_state_v1\",\"run_date\":\"$TODAY\",\"mode\":\"selfheal\",\"status\":\"done\",\"rc\":1,\"reported\":1,\"stages\":[],\"failed\":[\"x\"]}' > \"\$S\"; exit 1"
printf '{"schema":"daily_refresh_state_v1","run_date":"%s","mode":"full","status":"done","rc":1,"reported":1,"stages":[%s],"failed":[]}' "$TODAY" "$ALLOK" > "$B/.cache/daily_refresh_state.json"
edc >/dev/null
chk "N1 자가 복구 환경 — selfheal · 계획 · 배터리 생략 · 보고 켬" "mode=selfheal only=qw,universe,macro,krf,fdb skipbat=1 rep=1" "$(cat "$B/refresh_env.txt" 2>/dev/null)"
chk "N2 [7] 보고가 나간 실패 → 추가 알림 0" 0 "$(ntg)"
chk "N3 사후 감사 조용(QUIET=1)" "quiet=1" "$(tail -1 "$B/audit.log")"
mkrefresh "exit 1"; edc >/dev/null
chk "N4 보고 전에 끝난 실패 → 1통" 1 "$(ntg)"
mkrefresh "printf '{\"schema\":\"daily_refresh_state_v1\",\"run_date\":\"$TODAY\",\"mode\":\"selfheal\",\"status\":\"done\",\"rc\":0,\"reported\":1,\"stages\":[],\"failed\":[]}' > \"\$S\"; exit 0"; edc >/dev/null
chk "N5 성공 → 추가 알림 0" 0 "$(ntg)"
# K 시간 상한 — 가짜 리프레시가 자식(sleep)을 띄우고 오래 돈다
mkrefresh "sleep 120 & echo \$! > \"$B/child.pid\"; sleep 25"
rcK=$(edc 3); cpid=$(cat "$B/child.pid" 2>/dev/null); KILLME+=("${cpid:-0}")
chk "K1 상한 초과 → 1통" 1 "$(ntg)"
chk "K1b 알림에 상한 사유" YES "$(grep -q '상한' "$B/mock_tg.txt" 2>/dev/null && echo YES || echo NO)"
chk "K2 자식 프로세스 정리됨" DEAD "$(kill -0 "${cpid:-999999}" 2>/dev/null && echo ALIVE || echo DEAD)"
chk "K3 종료 코드 = 3(stale_after_refresh) · 종료코드 124 기록" YES "$([ "$rcK" = 3 ] && grep -q 'daily_refresh 종료코드=124' "$B/edc.log" && echo YES || echo NO)"
n=$(sub1 "$B/02_Infrastructure/ops/ensure_data_current.sh" "$B/02_Infrastructure/ops/edc_mut.sh" '    _kill_tree "$RPID"' '    :')
chk "K4 돌연변이 치환 1곳" 1 "$n"
mkrefresh "sleep 120 & echo \$! > \"$B/child.pid\"; sleep 6"
edc 2 "$B/02_Infrastructure/ops/edc_mut.sh" >/dev/null; cpid=$(cat "$B/child.pid" 2>/dev/null); KILLME+=("${cpid:-0}")
chk "K4b 돌연변이(트리 종료 무력화) → 자식 생존" ALIVE "$(kill -0 "${cpid:-999999}" 2>/dev/null && echo ALIVE || echo DEAD)"
kill -KILL "${cpid:-0}" 2>/dev/null

# ── X 실행 사본 ──
awk '/^_dr_self="\$\{BASH_SOURCE\[0\]:-\$0\}"$/{f=1} f{print} f&&/^fi$/{exit}' "$DR" > "$TMP/snaphead.sh"
chk "X0 사본 머리 추출" YES "$(grep -q 'exec "${BASH:-bash}" "$_dr_snap"' "$TMP/snaphead.sh" && echo YES || echo NO)"
mkx() { rm -f "$TMP/x.started"; { echo '#!/usr/bin/env bash'; cat "$TMP/snaphead.sh"; echo ': > "$TMP/x.started"'; echo 'sleep 3'; echo 'echo LINE_A'; echo 'echo LINE_B'; } > "$TMP/x.sh"; }
edit_mid() { local i=0; until [ -e "$TMP/x.started" ] || [ "$i" -ge 200 ]; do sleep 0.1; i=$((i+1)); done   # 머리(사본 exec)를 지난 뒤에 고친다 — 부하에서 경합 제거
  { echo '#!/usr/bin/env bash'; echo '# 앞에 긴 주석을 넣어 읽던 자리를 민다 ................................................................'; cat "$TMP/snaphead.sh"; echo 'sleep 3'; echo 'echo EDITED_A'; echo 'echo EDITED_B'; } > "$TMP/x.sh.new"; cat "$TMP/x.sh.new" > "$TMP/x.sh"; }
mkx; ( unset QVEST_DR_SNAPSHOT; export TMP; TMPDIR="$TMP" bash "$TMP/x.sh" > "$TMP/x.out" 2>&1 ) & xp=$!; edit_mid; wait "$xp"
chk "X1 실행 중 원본 편집 — 사본 출력 불변" "LINE_A LINE_B" "$(grep -E '^(LINE|EDITED)' "$TMP/x.out" | tr '\n' ' ' | sed 's/ $//')"
mkx; ( unset QVEST_DR_SNAPSHOT; export TMP; QVEST_DR_NO_SNAPSHOT=1 bash "$TMP/x.sh" > "$TMP/x2.out" 2>&1 ) & xp=$!; edit_mid; wait "$xp"
chk "X2 양성 대조(사본 끔) — 출력이 원본 편집에 끌려간다" CHANGED "$(grep -qE '^LINE_A$' "$TMP/x2.out" && grep -qE '^LINE_B$' "$TMP/x2.out" && echo SAME || echo CHANGED)"
DRY=$(cd "$PROJ" && TMPDIR="$TMP" QVEST_DR_MODE=selfheal QVEST_DR_ONLY_STAGES=qw,fdb bash "$DR" --dry-run 2>&1)
chk "X3 dry-run 은 사본으로" YES "$(printf '%s' "$DRY" | grep -q '^\[snapshot\] 실행 사본' && echo YES || echo NO)"
chk "X4 dry-run 계획 — qw · fdb 만 run · 후처리 skip" "qw fdb post:skip" "$(printf '%s\n' "$DRY" | awk -F'\t' '$1=="DR_PLAN" && $3=="run" && $2!="verify" && $2!="report"{printf "%s ", $2} $1=="DR_PLAN" && $2=="post"{printf "post:%s", $3}')"
: > "$TMP/qm_dr_snapshot_OLD000.sh"; touch -d "3 days ago" "$TMP/qm_dr_snapshot_OLD000.sh"
( cd "$PROJ" && TMPDIR="$TMP" bash "$DR" --dry-run >/dev/null 2>&1 )
chk "X5 2일 지난 실행 사본은 다음 실행이 지운다" NO "$([ -e "$TMP/qm_dr_snapshot_OLD000.sh" ] && echo YES || echo NO)"
# (11-10 적대적 검토 2차) 부모 체인의 표식을 물려받은 중첩 호출(밤 배터리 속 시나리오 시험) — 제 사본을 뜨고 · 부모 사본을 지우지 않고 · 묵은 사본 정리도 한다
: > "$TMP/qm_dr_snapshot_PARENT.sh"; : > "$TMP/qm_dr_snapshot_OLD111.sh"; touch -d "3 days ago" "$TMP/qm_dr_snapshot_OLD111.sh"
DRY2=$(cd "$PROJ" && TMPDIR="$TMP" QVEST_DR_SNAPSHOT="$TMP/qm_dr_snapshot_PARENT.sh" QVEST_DR_SRC_DIR="/nonexistent_parent_dir" bash "$DR" --dry-run 2>&1)
chk "X6 물려받은 남의 표식 → 제 사본으로 돈다(부모 사본 경로가 아님) · 계획 출력 정상" YES "$(printf '%s\n' "$DRY2" | grep '^\[snapshot\] 실행 사본' | grep -vq 'qm_dr_snapshot_PARENT' && printf '%s\n' "$DRY2" | grep -q '^DR_PLAN' && echo YES || echo NO)"
chk "X6b 부모 사본은 남는다 · 묵은 사본은 정리된다" "KEEP GONE" "$([ -e "$TMP/qm_dr_snapshot_PARENT.sh" ] && echo KEEP || echo LOST) $([ -e "$TMP/qm_dr_snapshot_OLD111.sh" ] && echo STAY || echo GONE)"
chk "X7 표식을 자식에게 물려주지 않는다(export 없음 · unset 있음)" YES "$(! grep -q 'export QVEST_DR_SNAPSHOT' "$DR" && grep -q '^unset QVEST_DR_SNAPSHOT QVEST_DR_SRC_DIR' "$DR" && echo YES || echo NO)"
# 보고 표식 — [7] 발송이 실제로 성사됐을 때만 reported=1 (구판: 무조건 1 → 발송 실패한 자가 복구가 0통으로 끝났다)
awk '/^DR_REPORTED=0; \[/{print; exit}' "$DR" > "$TMP/rep.sh"
rep_of() { ( BASE="$TMP/repb"; mkdir -p "$BASE/.cache"; QVEST_DR_TGSENT_NAME="t.txt"; rm -f "$BASE/.cache/t.txt"; [ "$1" = "-" ] || printf '%s\n' "$1" > "$BASE/.cache/t.txt"; DR_REPORTED=9; . "$TMP/rep.sh"; echo "$DR_REPORTED" ); }
chk "R1 발송 성사(TRUE) → reported 1 · 실패(FALSE) → 0 · 표식 없음(R 블록 사망 · 발송 생략) → 0" "1 0 0" "$(rep_of TRUE) $(rep_of FALSE) $(rep_of -)"
chk "R2 보고 표식 줄 추출 · 무조건 1 로 적는 구판 줄 없음" YES "$([ -s "$TMP/rep.sh" ] && ! grep -q '^DR_REPORTED=1; dr_state_write' "$DR" && echo YES || echo NO)"
# 상태 파일 — 더 늦게 시작한 실행의 기록을 덮지 않는다
awk '/^dr_state_write\(\) \{/{f=1} f{print} f&&/^\}$/{exit}' "$DR" > "$TMP/sw.sh"
sw_of() { ( DR_DRYRUN=0; BASE="$TMP/swb"; mkdir -p "$BASE/.cache"; QVEST_DR_STATE="$BASE/.cache/st.json"; printf '{"schema":"daily_refresh_state_v1","started_at":"%s","mode":"selfheal","reported":1}\n' "$1" > "$QVEST_DR_STATE"
  DR_STAGE_REC=(); DR_FAILED=(); DR_RUN_DATE=2026-11-10; DR_RUN_AT="2026-11-10T00:03:00"; DR_MODE=full; DR_ONLY=""; DR_REPORTED=0; DR_STALE_NAMES=""; _dr_js() { printf '%s' "$1"; }
  . "$TMP/sw.sh"; dr_state_write done 1 >/dev/null; grep -o '"mode":"[a-z]*"' "$QVEST_DR_STATE" ); }
chk "W1 더 늦게 시작한 자가 복구 상태(07:10)는 밤 실행(00:03)이 덮지 않는다 · 앞선 상태(어제)는 덮는다" '"mode":"selfheal" "mode":"full"' "$(sw_of 2026-11-10T07:10:00) $(sw_of 2026-11-09T00:03:00)"
fin "$PASS" "$FAIL"
