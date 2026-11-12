#!/usr/bin/env bash
# test_scn_refresh_rawdata_heal.sh — RAWDATA 만 낡은 날의 자가 복구 (2026-11-13 · 진단 20261112_2201 R3 · R4 · R5 + 11-13 밤 실패 · 도훈 "리프레시 실패 … 원천해결해")
#
# 실제 ensure_data_current.sh · dr_heal_plan.py 를 모래상자 루트에서 돌린다 — 실수집 · 실리프레시 · 실발송 · 운영 잠금 · 퀀티 단말 무접촉:
#   R  재시도(R4): 같은 거래일 · 표식 stale_unfixable_by_refresh · 벤치 최신(QW_BEHIND 0) · rawdata 낡음 →
#      R1 마지막 복구 뒤 간격 ≥ 상한 = 다시 복구 · R2 간격 < 상한 = 막되 안내는 '퀀티 수급 · 적재로 고쳐지는 낡음' ·
#      R3 고쳐지지 않는 항목(모르는 이름)은 간격이 지나도 막고 종전 안내 · R4 QVEST_EDC_QW_RETRY=0 = 막음 ·
#      RM 돌연변이(rawdata · benchmark 를 대상에서 뺌 = 구판) → R1 이 막힌다(11-12 · 11-13 하루 종일 '재시도하지 않음'의 재현)
#   E  세션 확인 조건(11-11 결정 문안 = 계획에 퀀티 단계): E1 계획에 qw(벤치 최신 · rawdata 낡음) → 확인 1회 · 리프레시보다 먼저 ·
#      E2 계획에 qw 없음(dart 실패 · 거시 낡음) → 확인 0 · EM 돌연변이(구판 대리 QW_BEHIND) → E1 이 0회(11-13 01:37 재현)
#   P  계획기(R3): 11-13 밤 꼴(qw · fdb 실패 · rawdata 낡음) → ingest 부터 · 컨센서스 낡음 → ingest 부터 · 벤치 낡음 → qw 부터(ingest 없음) ·
#      PM 돌연변이(rawdata → qw · 구판) → ingest 빠짐
#   X  상한 종료 뒤 수급 Excel 정리(R5): X1 주입 명령이 불리고 끝낸 pid 가 로그에 · XM 돌연변이(호출 삭제) → 로그 없음 ·
#      X2 실제 PowerShell 거르기(가짜 이름 qmxltest.exe 프로세스 셋): 복구 뒤 생김 ∧ 표지 있음 = 끝냄 · 표지 없음 = 남김 · 복구 전 생김 = 남김
# 요약: 마지막 줄 {"test":"scn_refresh_rawdata_heal","pass":N,"fail":N,"total":N}
set -uo pipefail
T=scn_refresh_rawdata_heal
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; PROJ="$(cd "$_SELF_DIR/../.." && pwd)"
fin() { echo "{\"test\":\"$T\",\"pass\":$1,\"fail\":$2,\"total\":$(( $1 + $2 ))}"; [ "$2" -eq 0 ]; exit $?; }
EDC="${QVEST_TEST_EDC_SRC:-$PROJ/02_Infrastructure/ops/ensure_data_current.sh}"   # 후보판을 운영 교체 전에 재는 이음새
PLN="${QVEST_TEST_PLN_SRC:-$PROJ/02_Infrastructure/data/dr_heal_plan.py}"
PY="$PROJ/.venv_qvest_ml/Scripts/python.exe"; [ -x "$PY" ] || PY="$PROJ/.venv_qvest_ml/bin/python"
for f in "$EDC" "$PLN" "$PY" "$PROJ/02_Infrastructure/ops/resolve_project.sh"; do [ -e "$f" ] || { echo "대상 없음: $f"; fin 0 1; }; done
TMP="$(mktemp -d)"; KILLW=()
cleanup() { for p in "${KILLW[@]+"${KILLW[@]}"}"; do taskkill //F //PID "$p" >/dev/null 2>&1; done; rm -rf "$TMP"; }
trap cleanup EXIT
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1 — 기대 '$2' / 실제 '$3'"; fi; }
mut() { "$PY" -c "import sys;s=open(sys.argv[1],encoding='utf-8').read();n=s.count(sys.argv[3]);open(sys.argv[2],'w',encoding='utf-8',newline='\n').write(s.replace(sys.argv[3],sys.argv[4],1));print(n)" "$@"; }
echo "== $T =="

# ── 모래상자 루트 ──
B="$TMP/b"; mkdir -p "$B/02_Infrastructure/hooks" "$B/02_Infrastructure/ops/morning_steps" "$B/02_Infrastructure/data" "$B/.cache" "$B/qepm/observability"
: > "$B/02_Infrastructure/hooks/qvest_hook_router.py"; : > "$B/02_Infrastructure/ops/morning_steps/freshness_audit.R"
cp "$PROJ/02_Infrastructure/ops/resolve_project.sh" "$B/02_Infrastructure/ops/"
put_edc() { sed "s#^LOCKDIR=\"/tmp/qm_daily_refresh.lock\"#LOCKDIR=\"$B/refresh.lock\"#" "$1" > "$B/02_Infrastructure/ops/ensure_data_current.sh"; }
put_pln() { cp "$1" "$B/02_Infrastructure/data/dr_heal_plan.py"; }
put_edc "$EDC"; put_pln "$PLN"
chk "S0 잠금 경로 격리 치환" YES "$(grep -q "^LOCKDIR=\"$B/refresh.lock\"" "$B/02_Infrastructure/ops/ensure_data_current.sh" && echo YES || echo NO)"
# 감사기 스텁(Rscript): 낡은 항목 = FAKE_ITEMS · 거래일 = 2026-11-12
printf '#!/usr/bin/env bash\necho "EDC_RESULT stale=1 as_of=2026-11-12 items=${FAKE_ITEMS:-rawdata}"\n' > "$B/fakeR"
# 퀀티 축 스텁(python): krx_holidays.py currency = FAKE_QW(기본 '벤치 최신') · 그 밖(계획기)은 진짜 python
printf '#!/usr/bin/env bash\ncase "$*" in *krx_holidays.py*) echo "${FAKE_QW:-0|2026-11-12|2026-11-12}" ;; *) exec "%s" "$@" ;; esac\n' "$PY" > "$B/fakepy"
chmod +x "$B/fakeR" "$B/fakepy"
# 세션 확인 도우미 스텁 · 리프레시 스텁 — 부른 순서를 calls.log 에 남긴다
printf '#!/usr/bin/env bash\necho qse >> "%s/calls.log"\nprintf "QSE\\tstate=alive\\talive=True\\tkicks=0\\n"\n' "$B" > "$B/02_Infrastructure/ops/qw_session_ensure.sh"
printf '#!/usr/bin/env bash\necho "refresh only=${QVEST_DR_ONLY_STAGES:-ALL}" >> "%s/calls.log"\nsleep "${FAKE_DR_SLEEP:-0}"\nexit 1\n' "$B" > "$B/02_Infrastructure/data/daily_refresh.sh"
TODAY="$(date +%F)"; NOW=$(date +%s)
night_state() {  # $1 = 단계 기록(JSON 조각) — 오늘 밤 실행(full · done)
  printf '{"schema":"daily_refresh_state_v1","run_date":"%s","started_at":"%sT00:03:03","mode":"full","status":"done","rc":1,"reported":1,"stages":[%s],"failed":[]}' "$TODAY" "$TODAY" "$1" > "$B/.cache/daily_refresh_state.json"; }
S() { printf '{"name":"%s","status":"%s","sec":1}' "$1" "$2"; }
NIGHT_1113="$(S ingest ok),$(S qw failed),$(S universe ok),$(S macro ok),$(S dart ok),$(S krf ok),$(S fdb failed),$(S nonret ok)"
NIGHT_DART="$(S ingest ok),$(S qw ok),$(S universe ok),$(S macro ok),$(S dart failed),$(S krf ok),$(S fdb ok),$(S nonret ok)"
stamp() { printf '{"ran_at":"x","as_of":"2026-11-12","verdict":"%s","stale_count":1,"note":"x","qw":"x"}\n' "$1" > "$B/.cache/data_currency_stamp.json"; }
heal_mark() { printf '2026-11-12 %s\n' "$1" > "$B/.cache/data_currency_last_heal"; }
edc() {  # 환경은 호출부가 앞에 붙인다 → rc
  rm -f "$B/calls.log"
  ( cd "$B" && QM_ROOT="$B" RSCRIPT="$B/fakeR" QVEST_PY="$B/fakepy" QVEST_EDC_MAX_WAIT=1 QVEST_EDC_TG_MOCK="$B/mock_tg.txt" QVEST_EDC_POLL_S=1 \
      QVEST_EDC_HEAL_TIMEOUT_S="${HT:-600}" bash "$B/02_Infrastructure/ops/ensure_data_current.sh" > "$B/edc.log" 2>&1; echo $? ); }
calls() { [ -f "$B/calls.log" ] && tr '\n' '|' < "$B/calls.log" | sed 's/|$//' || echo "-"; }
has() { grep -q "$1" "$B/edc.log" && echo YES || echo NO; }

# ── R 재시도(R4) ──
night_state "$NIGHT_1113"; stamp stale_unfixable_by_refresh; heal_mark $(( NOW - 9100 ))
rc=$(edc); chk "R1 벤치 최신 · rawdata 낡음 · 마지막 복구 뒤 9100초(≥ 9000) → 다시 복구(세션 확인 → 리프레시)" "0|qse|refresh only=ingest,qw,universe,macro,krf,fdb" "$([ "$rc" = 3 ] && echo 0 || echo "rc$rc")|$(calls)"
chk "R1b 재시도 사유 로그" YES "$(has '↻ 같은 영업일 재시도')"
night_state "$NIGHT_1113"; stamp stale_unfixable_by_refresh; heal_mark $(( NOW - 600 ))
rc=$(edc); chk "R2 간격 600초(< 9000) → 막음(rc 3 · 리프레시 0)" "3|-" "$rc|$(calls)"
chk "R2b 안내 = '퀀티 수급 · 적재로 고쳐지는 낡음'(구판의 '고쳐지지 않는 항목'이 아니다)" "YES NO" "$(has '퀀티 수급 · 적재로 고쳐지는 낡음') $(has '리프레시로 고쳐지지 않는 항목')"
night_state "$NIGHT_1113"; stamp stale_unfixable_by_refresh; heal_mark $(( NOW - 9100 ))
rc=$(FAKE_ITEMS=mystery_item edc); chk "R3 고쳐지지 않는 항목(모르는 이름) → 간격이 지나도 막음 · 종전 안내" "3|-|YES" "$rc|$(calls)|$(has '리프레시로 고쳐지지 않는 항목')"
night_state "$NIGHT_1113"; stamp stale_unfixable_by_refresh; heal_mark $(( NOW - 9100 ))
rc=$(QVEST_EDC_QW_RETRY=0 edc); chk "R4 QVEST_EDC_QW_RETRY=0 → 막음(끄는 손잡이)" "3|-" "$rc|$(calls)"
night_state "$NIGHT_1113"; stamp stale_unfixable_by_refresh; heal_mark $(( NOW - 9100 ))
rc=$(FAKE_ITEMS=benchmark edc); chk "R5 benchmark 낡음(벤치 최신 판정 축과 따로 낡음) → 다시 복구" "0|qse|refresh only=qw,universe,macro,krf,fdb" "$([ "$rc" = 3 ] && echo 0 || echo "rc$rc")|$(calls)"
n=$(mut "$EDC" "$TMP/edc_mutR.sh" 'case ",${PRE_ACT}," in *,rawdata,*|*,benchmark,*) _QW_FIX=1 ;; esac' ':')
chk "RM 돌연변이 치환 1곳" 1 "$n"
put_edc "$TMP/edc_mutR.sh"; night_state "$NIGHT_1113"; stamp stale_unfixable_by_refresh; heal_mark $(( NOW - 9100 ))
rc=$(edc); chk "RM 돌연변이(대상 = QW_BEHIND 만 · 구판) → R1 이 막힌다 — R1 은 수리의 발화다" "3|-" "$rc|$(calls)"
put_edc "$EDC"

# ── E 세션 확인 조건(R4b) ──
rm -f "$B/.cache/data_currency_stamp.json" "$B/.cache/data_currency_last_heal"; night_state "$NIGHT_1113"
rc=$(edc); chk "E1 계획에 qw(벤치 최신 · rawdata 낡음 · 그날 첫 복구) → 세션 확인 1회 · 리프레시보다 먼저" "qse|refresh only=ingest,qw,universe,macro,krf,fdb" "$(calls)"
rm -f "$B/.cache/data_currency_stamp.json" "$B/.cache/data_currency_last_heal"; night_state "$NIGHT_DART"
rc=$(FAKE_ITEMS=msm_daily edc); chk "E2 계획에 qw 없음(dart 실패 · 거시 낡음) → 세션 확인 0 · 단말 무접촉" "refresh only=macro,dart,krf,fdb" "$(calls)"
n=$(mut "$EDC" "$TMP/edc_mutE.sh" '_plan_has_qw=0; case ",${HEAL_PLAN}," in *,FULL,*|*,qw,*) _plan_has_qw=1 ;; esac' '_plan_has_qw=0; [ "$QW_BEHIND" = "1" ] && _plan_has_qw=1')
chk "EM 돌연변이 치환 1곳" 1 "$n"
put_edc "$TMP/edc_mutE.sh"; rm -f "$B/.cache/data_currency_stamp.json" "$B/.cache/data_currency_last_heal"; night_state "$NIGHT_1113"
rc=$(edc); chk "EM 돌연변이(구판 대리 QW_BEHIND) → E1 의 세션 확인이 사라진다(11-13 01:37 재현)" "refresh only=ingest,qw,universe,macro,krf,fdb" "$(calls)"
put_edc "$EDC"

# ── P 계획기(R3) ──
plan() { "$PY" -X utf8 "${PLN_OVR:-$PLN}" --state "$B/.cache/daily_refresh_state.json" --today "$TODAY" "$@" | sed -n 's/.*plan=\([^	]*\).*/\1/p'; }
night_state "$NIGHT_1113"
chk "P1 11-13 밤 꼴(qw · fdb 실패 · rawdata 낡음) → ingest 부터(저장됐지만 안 실린 xlsx 를 먼저 싣는다)" "ingest,qw,universe,macro,krf,fdb" "$(plan --stale 'rawdata(STALE,lag=1d)' --qw-behind 0)"
night_state "$NIGHT_DART"
chk "P2 컨센서스 낡음 → ingest 와 하류" "ingest,qw,universe,macro,dart,krf,fdb" "$(plan --stale consensus)"
chk "P3 벤치만 낡음 → qw 부터(ingest 없음 — 벤치는 퀀티 수급만 고친다)" "qw,universe,macro,dart,krf,fdb" "$(plan --stale benchmark)"
n=$(mut "$PLN" "$TMP/plan_mut.py" '"rawdata": "ingest"' '"rawdata": "qw"')
chk "PM 돌연변이 치환 1곳" 1 "$n"
night_state "$NIGHT_1113"
chk "PM 돌연변이(rawdata → qw · 구판) → ingest 가 빠진다 — P1 은 수리의 발화다" "qw,universe,macro,krf,fdb" "$(PLN_OVR="$TMP/plan_mut.py" plan --stale rawdata --qw-behind 0)"

# ── X 상한 종료 뒤 수급 Excel 정리(R5) ──
rm -f "$B/.cache/data_currency_stamp.json" "$B/.cache/data_currency_last_heal"; night_state "$NIGHT_1113"
rc=$(HT=3 FAKE_DR_SLEEP=30 QVEST_EDC_XL_CLEANUP_CMD='echo killed 4242' edc)
chk "X1 상한 종료 → 정리 명령이 불리고 끝낸 pid 가 로그에" "YES|YES" "$(has '상한 3s 를 넘김')|$(has '수급 Excel 정리(복구 시작 뒤 · /automation): killed 4242')"
n=$(mut "$EDC" "$TMP/edc_mutX.sh" '    _xl_out="$(_xl_cleanup "$_t0")"; _log "   수급 Excel 정리(복구 시작 뒤 · /automation): ${_xl_out:-없음}"' '    :')
chk "XM 돌연변이 치환 1곳" 1 "$n"
put_edc "$TMP/edc_mutX.sh"; rm -f "$B/.cache/data_currency_stamp.json" "$B/.cache/data_currency_last_heal"; night_state "$NIGHT_1113"
rc=$(HT=3 FAKE_DR_SLEEP=30 QVEST_EDC_XL_CLEANUP_CMD='echo killed 4242' edc)
chk "XM 돌연변이(정리 호출 삭제) → 로그 없음 — X1 은 그 호출의 발화다" "YES|NO" "$(has '상한 3s 를 넘김')|$(has 'killed 4242')"
put_edc "$EDC"
# X2 — 실제 PowerShell 거르기: 가짜 이름(qmxltest.exe = ping.exe 사본)으로 이름 · 시각 · 명령줄 표지 세 조건을 잰다(진짜 Excel 무접촉)
awk '/^_xl_cleanup\(\) \{/{f=1} f{print} f&&/^\}$/{exit}' "$EDC" > "$TMP/xl_fn.sh"
PING="$(cygpath -u "${SYSTEMROOT:-C:\\Windows}")/System32/PING.EXE"
if [ -s "$TMP/xl_fn.sh" ] && [ -x "$PING" ] && cp "$PING" "$TMP/qmxltest.exe" 2>/dev/null; then
  wpid() { powershell.exe -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"Name='qmxltest.exe'\" | Where-Object { \$_.CommandLine -like '*-n $1 *' } | Select-Object -First 1).ProcessId" 2>/dev/null | tr -d '\r\n '; }
  alive() { powershell.exe -NoProfile -Command "if (Get-Process -Id $1 -EA SilentlyContinue) { 'A' } else { 'D' }" 2>/dev/null | tr -d '\r\n '; }
  "$TMP/qmxltest.exe" -n 61 127.0.0.1 >/dev/null 2>&1 &        # 복구 전에 생김(표지 있음) — 남아야 한다
  sleep 3; T0=$(date +%s); sleep 2
  "$TMP/qmxltest.exe" -n 62 127.0.0.1 >/dev/null 2>&1 &        # 복구 뒤 · 표지 없음 — 남아야 한다
  "$TMP/qmxltest.exe" -n 61 127.0.0.2 >/dev/null 2>&1 &        # 복구 뒤 · 표지 있음 — 끝내야 한다
  sleep 3
  p_old=$(powershell.exe -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"Name='qmxltest.exe'\" | Where-Object { \$_.CommandLine -like '*-n 61 127.0.0.1*' }).ProcessId" 2>/dev/null | tr -d '\r\n ')
  p_new=$(powershell.exe -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"Name='qmxltest.exe'\" | Where-Object { \$_.CommandLine -like '*-n 61 127.0.0.2*' }).ProcessId" 2>/dev/null | tr -d '\r\n ')
  p_oth=$(wpid 62); KILLW+=("${p_old:-0}" "${p_new:-0}" "${p_oth:-0}")
  out=$( ( . "$TMP/xl_fn.sh"; QVEST_EDC_XL_NAME=qmxltest.exe QVEST_EDC_XL_PAT='-n 61' _xl_cleanup "$T0" ) )
  sleep 1
  chk "X2 가짜 프로세스 셋 준비" YES "$([ -n "$p_old" ] && [ -n "$p_new" ] && [ -n "$p_oth" ] && echo YES || echo "NO($p_old/$p_new/$p_oth)")"
  chk "X2b 복구 뒤 ∧ 표지 = 끝냄 · 출력에 그 pid" "D|YES" "$(alive "${p_new:-0}")|$(printf '%s' "$out" | grep -q "killed ${p_new:-x}" && echo YES || echo NO)"
  chk "X2c 표지 없음 = 남김 · 복구 전 생김 = 남김" "A|A" "$(alive "${p_oth:-0}")|$(alive "${p_old:-0}")"
else
  chk "X2 준비(함수 추출 · ping 사본)" YES NO
fi
fin "$PASS" "$FAIL"
