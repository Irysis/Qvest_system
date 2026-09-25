#!/usr/bin/env bash
# test_scheduler_task_health_verdict.sh — 예약작업 실패 판정 계약 (2026-08-08 신설)
#
# 왜: 2026-08-08 00:03 보고 "실패 4"가 **4건 전부 허위**였다. 두 기전(둘 다 판정이
#   잘못된 것을 잼):
#     (A) state==Running 인 작업의 rc 를 완료 판정으로 읽음
#         (실측: StrandedRepairs 가 같은 실행에서 0x800710E0 → 0. last_run 불변)
#     (B) 같은 실패 1건을 폴링마다 재보고 (MonthlyDistill·WeeklyCleaner 7일간 매회)
#
# ★이 검사기의 존재 이유: 위 수리는 **경보를 줄이는** 수리다. 경보가 줄어든 것과
#   판정이 죽은 것은 겉보기가 같다. 그래서 T1(양성 대조)과 T9/T10(돌연변이)이 본체다 —
#   진짜 실패가 여전히 잡히는지, 그리고 면제 규칙이 실제로 일을 하는지를 각각 실증한다.
#
# ★v10.4 (2026-09-24) S1~S12 = 자기보고 실패 면제(DR 완주+[7] 발송 확인 exit_1 만 경보 제외) 양방향 ·
#   D1~D5 = 기보고 원장 확정 조건(발송 안 될 신규 실패는 seen 미확정 — 09-12 영구 매몰 재발 방지).
#
# 검사 대상은 사본이 아니라 **원본 .sh 에서 떼어낸 판정 블록**이다(사본은 원본과 갈린다).
#   추출 anchor 는 수리 전후 모두 존재하는 줄(`<<'PY'` / 닫는 `PY`)로 잡는다 —
#   수리가 도입한 구조를 needle 로 쓰면 되돌렸을 때 "추출 실패"라는 정비 메시지가 떠서
#   결함이 정비 과제로 오진된다(r-portability.md ④-b 선례).
set -uo pipefail

_SELF="${BASH_SOURCE[0]:-$0}"; _SELF_DIR="$(cd "$(dirname "$_SELF")" && pwd)"
MARKER_REL="02_Infrastructure/hooks/qvest_hook_router.py"
# 앵커 1순위 = 자기가 실린 트리 (④-b 테스트 러너 self-first)
PROJ=""
for c in "$_SELF_DIR/../.." "${CLAUDE_PROJECT_DIR:-}" "${QM_ROOT:-}" "$PWD"; do
  [ -n "$c" ] && [ -f "${c//\\//}/$MARKER_REL" ] && { PROJ="$(cd "${c//\\//}" && pwd)"; break; }
done
[ -n "$PROJ" ] || { echo "PROJECT_ROOT 해석 실패" >&2
  echo '{"test":"scheduler_task_health_verdict","pass":0,"fail":1,"total":1,"preflight":"no_root"}'; exit 1; }

SRC="$PROJ/02_Infrastructure/ops/scheduler_task_health.sh"
[ -f "$SRC" ] || { echo "원본 없음: $SRC" >&2
  echo '{"test":"scheduler_task_health_verdict","pass":0,"fail":1,"total":1,"preflight":"no_src"}'; exit 1; }

# 기능 프로브 통과 인터프리터만 채택 — bare python3 는 Windows Store 스텁(exit 49)이라
# "미실행"이 "검거 실패"와 같은 출력이 된다. 후보 목록에서 영구 제외.
PY=""
for c in "${QVEST_PY:-}" "$PROJ/.venv_qvest_ml/Scripts/python.exe" "$PROJ/.venv_qvest_ml/bin/python" \
         "/c/Users/99922/AppData/Local/Programs/Python/Python312/python.exe"; do
  [ -n "$c" ] && [ -x "$c" ] && "$c" -c 'import json,datetime,io,os' >/dev/null 2>&1 && { PY="$c"; break; }
done
[ -n "$PY" ] || { echo "python 해석 실패" >&2
  echo '{"test":"scheduler_task_health_verdict","pass":0,"fail":1,"total":1,"preflight":"no_python"}'; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
JUDGE="$TMP/judge.py"
awk "/<<'PY'/{f=1;next} /^PY\$/{f=0} f" "$SRC" > "$JUDGE"
if [ ! -s "$JUDGE" ] || ! grep -q 'in_flight\|inflight\|bad' "$JUDGE"; then
  echo "판정 블록 추출 실패 (anchor 갱신 필요 아님 — 원본 구조 확인)" >&2
  echo '{"test":"scheduler_task_health_verdict","pass":0,"fail":1,"total":1,"preflight":"extract_failed"}'; exit 1
fi

PASS=0; FAIL=0
# mk <name> <state> <rc> <rc_label> <last_run> [enabled] [max_stale] [age]
mk() {
  printf '{"task":"%s","state":"%s","rc":%s,"rc_label":"%s","last_run":"%s","age_days":%s,"max_stale_days":%s,"enabled":%s,"next_run":null,"logon_type":"Interactive","stop_on_battery":false,"start_when_available":true}' \
    "$1" "$2" "$3" "$4" "$5" "${8:-0}" "${7:-null}" "${6:-true}"
}
run_judge() {   # $1=tasks-json-array  $2=seen-json ; stdout = verdict json
  local f="$TMP/fx.json" s="$TMP/seen.json"
  printf '{"schema_version":2,"measured_at":"2026-08-08T00:03:30","last_resume":null,"last_boot":null,"tasksched_oplog_enabled":false,"tasks":%s}' "$1" > "$f"
  printf '%s' "${2:-\{\}}" > "$s"
  "$PY" "${JUDGE_OVERRIDE:-$JUDGE}" "$f" "$s" 2>/dev/null
}
# has <verdict-json> <bucket> <needle>
has() { printf '%s' "$1" | "$PY" -c "
import json,sys
d=json.load(sys.stdin); print('YES' if any('$3' in x for x in d.get('$2',[])) else 'NO')" 2>/dev/null; }

chk() {  # chk <label> <expected> <actual>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"
  else FAIL=$((FAIL+1)); echo "  FAIL $1 — 기대 '$2' / 실제 '$3'"; fi
}

echo "== 예약작업 판정 계약 =="

# ── T1 양성 대조 ★본체: 진짜 실패는 반드시 신규 실패로 잡힌다.
#    이 축이 죽으면 아래 면제 축들이 전부 무의미하다(경보 0 = 판정 사망).
V=$(run_judge "[$(mk RealFail Ready 3221225786 hard_terminated_ctrlc_or_exectimelimit 2026-08-08T09:00:00)]" '{}')
chk "T1 완료된 rc≠0 = 신규 실패(양성 대조)" YES "$(has "$V" bad RealFail)"

# ── T2 (A) 기전: 실행 중 작업의 과도 rc 를 실패로 읽지 않는다
V=$(run_judge "[$(mk Inflt Running 2147946720 nt_status_0x800710E0 2026-08-08T00:00:43)]" '{}')
chk "T2 state=Running + rc≠0 → 실패 아님"      NO  "$(has "$V" bad Inflt)"
chk "T2b 같은 건이 in_flight 로 기록됨"        YES "$(has "$V" inflight Inflt)"

# ── T3 기존 still_running 면제 회귀 방지
V=$(run_judge "[$(mk Still Running 267009 still_running 2026-08-08T00:00:43)]" '{}')
chk "T3 rc=267009 still_running → 실패 아님"   NO  "$(has "$V" bad Still)"

# ── T4/T5 (B) 기전: 실패의 정체성 = (작업, 그 실행 시각)
SEEN='{"Dup":"2026-08-01T15:49:19"}'
V=$(run_judge "[$(mk Dup Ready 3221225786 hard_terminated_ctrlc_or_exectimelimit 2026-08-01T15:49:19)]" "$SEEN")
chk "T4 기보고한 (작업,실행시각) → 신규 아님"  NO  "$(has "$V" bad Dup)"
chk "T4b 기보고분은 known 으로 보존"           YES "$(has "$V" known Dup)"
V=$(run_judge "[$(mk Dup Ready 3221225786 hard_terminated_ctrlc_or_exectimelimit 2026-08-08T09:00:00)]" "$SEEN")
chk "T5 같은 작업의 **새 실행** 실패 → 신규"   YES "$(has "$V" bad Dup)"

# ── T6 성공하면 기억이 비워져 다음 실패가 신규가 된다
V=$(run_judge "[$(mk Rec Ready 0 ok 2026-08-08T09:00:00)]" '{"Rec":"2026-08-01T15:49:19"}')
chk "T6 rc=0 이면 실패로 계상 안 함"           NO  "$(has "$V" bad Rec)"
SEEN_AFTER=$(cat "$TMP/seen.json" 2>/dev/null)
chk "T6b 성공 시 기보고 원장에서 제거"         NO  "$(printf '%s' "$SEEN_AFTER" | grep -q '"Rec"' && echo YES || echo NO)"

# ── T7 비활성 작업은 판정 대상 아님
V=$(run_judge "[$(mk Off Ready 3221225786 hard_terminated_ctrlc_or_exectimelimit 2026-06-20T12:00:01 false)]" '{}')
chk "T7 enabled=false → 실패 아님"             NO  "$(has "$V" bad Off)"

# ── T8 staleness 축은 rc 축과 독립 — 되돌아오지 않는 작업은 여기서 잡힌다
V=$(run_judge "[$(mk Old Ready 0 ok 2026-07-01T09:00:00 true 2 40)]" '{}')
chk "T8 age>max_stale → 정체로 잡힘(독립 축)"  YES "$(has "$V" stale Old)"

# ── T8b (v10 2026-09-02) never_run 은 정체가 아니다 — 08-30 등록 주간작업 3개가 1999 센티넬(age 9773일)로
#    매일 '정체 3' 거짓양성 → 텔레그램 매일(도훈 지목). 면제가 실제로 일하는지 돌연변이(T8c)로 실증.
V=$(run_judge "[$(mk NeverRan Ready 267011 never_run 1999-11-30T00:00:00 true 9 9773)]" '{}')
chk "T8b rc_label=never_run + age 센티넬 → 정체 아님"  NO  "$(has "$V" stale NeverRan)"
chk "T8b2 never_run 은 실패로도 계상 안 함"           NO  "$(has "$V" bad NeverRan)"
sed 's/lbl != "never_run" and ms and ag/ms and ag/' "$JUDGE" > "$TMP/mut_never.py"
V=$(JUDGE_OVERRIDE="$TMP/mut_never.py" run_judge "[$(mk NeverRan Ready 267011 never_run 1999-11-30T00:00:00 true 9 9773)]" '{}')
chk "T8c 돌연변이(never_run 면제 제거) → T8b 가 정체로 뒤집힘" YES "$(has "$V" stale NeverRan)"

# ── T9/T10 돌연변이 ★면제 규칙이 실제로 일을 하는지: 규칙을 무력화하면 T2/T4 가 뒤집혀야 한다.
#    뒤집히지 않으면 그 "통과"는 규칙 덕이 아니라 우연이다.
sed 's/state == "Running" or lbl == "still_running"/False/' "$JUDGE" > "$TMP/mut_state.py"
V=$(JUDGE_OVERRIDE="$TMP/mut_state.py" run_judge "[$(mk Inflt Running 2147946720 nt_status_0x800710E0 2026-08-08T00:00:43)]" '{}')
chk "T9 돌연변이(state 가드 제거) → T2 가 실패로 뒤집힘" YES "$(has "$V" bad Inflt)"

sed 's/seen.get(name) == run_id and run_id/False/' "$JUDGE" > "$TMP/mut_seen.py"
V=$(JUDGE_OVERRIDE="$TMP/mut_seen.py" run_judge "[$(mk Dup Ready 3221225786 hard_terminated_ctrlc_or_exectimelimit 2026-08-01T15:49:19)]" "$SEEN")
chk "T10 돌연변이(기보고 dedup 제거) → T4 가 실패로 뒤집힘" YES "$(has "$V" bad Dup)"

# ══ v10.4 (2026-09-24) 자기보고 실패 면제(C) — DR 이 완주 후 자기 [7] 텔레그램으로 이미 알린 exit_1 만 경보 제외 ══
#   09-11~24 task_health 텔레그램 7건 중 5건이 DR exit_1 재방송(조치 0). 면제가 넓으면 진짜 사망(09-18 exit_2 ·
#   Done 줄 없음)을 삼킨다 → 양성 대조 1 + 위반 주입 8 + 돌연변이 2 로 양방향을 잰다.
# 운영 환경 변수에 끌려가지 않는다 — 배터리는 DR(QVEST_UNATTENDED=1) 안에서도 돈다. 각 케이스가 필요한 값을 명시한다.
unset QVEST_UNATTENDED; export QVEST_TH_SELFREPORT_EXEMPT=1 QVEST_NO_ALERT=0
DRLOG="$TMP/dr.log"
# mkdr <start-hdr-time> <sent-line|-> <done-line|-> [crlf]
mkdr() {
  { printf '=== Daily Refresh v2 @ Wed Sep 23 00:03:02     2026 ===\n[7/7] Telegram + NAV + Memory...\n'
    printf '[7] tg_sent=TRUE reported=ingest_freshness\n'
    printf '=== Daily Refresh v2 Done — ★실패 1스텝: ingest_freshness @ Wed Sep 23 01:13:05     2026 ===\n'
    printf '=== Daily Refresh v2 @ %s ===\n[0a/7] ...\n[7/7] Telegram + NAV + Memory...\n' "$1"
    if [ "$2" != "-" ]; then if [ "${4:-}" = "crlf" ]; then printf '%s\r\n' "$2"; else printf '%s\n' "$2"; fi; fi
    [ "$3" != "-" ] && printf '%s\n' "$3"
  } > "$DRLOG"
}
DONE1='=== Daily Refresh v2 Done — ★실패 2스텝: ingest_freshness factor_emission_regress:202608:3(INV13_A,INV13_B) @ Thu Sep 24 01:54:38     2026 ==='
SENT1='[7] tg_sent=TRUE reported=ingest_freshness factor_emission_regress:202608:3(INV13_A,INV13_B)'
DRT="$(mk Qvest_DailyRefresh Ready 1 exit_1 2026-09-24T00:03:01)"
run_judge_log() {   # $1=tasks $2=seen → 3번째 인자로 DR 로그 전달
  local f="$TMP/fx.json" s="$TMP/seen.json"
  printf '{"schema_version":2,"measured_at":"2026-09-24T11:09:27","last_resume":null,"last_boot":null,"tasksched_oplog_enabled":false,"tasks":%s}' "$1" > "$f"
  printf '%s' "${2:-\{\}}" > "$s"
  "$PY" "${JUDGE_OVERRIDE:-$JUDGE}" "$f" "$s" "$DRLOG" 2>/dev/null
}
# has2 <verdict-json> <key> <needle> — selfrep 키 판독(구 has 는 bucket 만)
mkdr "Thu Sep 24 00:03:02     2026" "$SENT1" "$DONE1"
V=$(run_judge_log "[$DRT]" '{}')
chk "S1 완주+[7] 발송 확인 DR exit_1 → 신규 실패 아님(양성 대조)" NO  "$(has "$V" bad Qvest_DailyRefresh)"
chk "S1b 같은 건이 selfrep 으로 기록됨(조용해진 것≠고쳐진 것)"     YES "$(has "$V" selfrep Qvest_DailyRefresh)"
mkdr "Thu Sep 24 00:03:02     2026" "$SENT1" "$DONE1" crlf
V=$(run_judge_log "[$DRT]" '{}')
chk "S1c [7] 줄이 CRLF(Windows R stdout)여도 면제"                NO  "$(has "$V" bad Qvest_DailyRefresh)"
V=$(run_judge_log "[$DRT]" '{"Qvest_DailyRefresh":"2026-09-24T00:03:01"}')
chk "S1d 기보고 run_id 여도 selfrep 이 우선 — known 에 남지 않음(해소 가능)" NO "$(has "$V" known Qvest_DailyRefresh)"
mkdr "Thu Sep 24 00:03:02     2026" "$SENT1" "-"
V=$(run_judge_log "[$DRT]" '{}')
chk "S2 Done 줄 없음(중도 사망 — 09-18 형) → 경보"                  YES "$(has "$V" bad Qvest_DailyRefresh)"
mkdr "Wed Sep 23 14:21:39     2026" "$SENT1" "$DONE1"
V=$(run_judge_log "[$DRT]" '{}')
chk "S3 Done 이 이전 실행 것(시작 머리줄이 run_id 창 밖) → 경보"     YES "$(has "$V" bad Qvest_DailyRefresh)"
mkdr "Thu Sep 24 00:03:02     2026" "-" "$DONE1"
V=$(run_judge_log "[$DRT]" '{}')
chk "S4 [7] 발송 증거 없음 → 경보"                                  YES "$(has "$V" bad Qvest_DailyRefresh)"
mkdr "Thu Sep 24 00:03:02     2026" "${SENT1/TRUE/FALSE}" "$DONE1"
V=$(run_judge_log "[$DRT]" '{}')
chk "S5 tg_sent=FALSE(발송 실패 반환) → 경보"                       YES "$(has "$V" bad Qvest_DailyRefresh)"
mkdr "Thu Sep 24 00:03:02     2026" "[7] tg_sent=TRUE reported=ingest_freshness" "$DONE1"
V=$(run_judge_log "[$DRT]" '{}')
chk "S6 [7] 이후 실패가 더 있음(reported≠Done 목록) → 경보"          YES "$(has "$V" bad Qvest_DailyRefresh)"
mkdr "Thu Sep 24 00:03:02     2026" "$SENT1" "$DONE1"
V=$(run_judge_log "[$(mk Qvest_DailyRefresh Ready 2 exit_2 2026-09-24T00:03:01)]" '{}')
chk "S7 exit_2(크래시) → 경보"                                      YES "$(has "$V" bad Qvest_DailyRefresh)"
V=$(run_judge_log "[$(mk Qvest_AxiomReview Ready 1 exit_1 2026-09-24T00:03:01)]" '{}')
chk "S8 다른 작업의 exit_1 → 경보(면제는 DR 전용)"                   YES "$(has "$V" bad Qvest_AxiomReview)"
V=$(QVEST_TH_SELFREPORT_EXEMPT=0 run_judge_log "[$DRT]" '{}')
chk "S9 스위치 QVEST_TH_SELFREPORT_EXEMPT=0 → 종전대로 경보(되돌리기)" YES "$(has "$V" bad Qvest_DailyRefresh)"
V=$(run_judge "[$DRT]" '{}')
chk "S10 로그 인자 없는 호출(구 2인자) → 경보"                      YES "$(has "$V" bad Qvest_DailyRefresh)"
sed 's/^def _self_reported(name, rc, run_id):$/&\n    return True/' "$JUDGE" > "$TMP/mut_selfT.py"
mkdr "Thu Sep 24 00:03:02     2026" "$SENT1" "-"
V=$(JUDGE_OVERRIDE="$TMP/mut_selfT.py" run_judge_log "[$DRT]" '{}')
chk "S11 돌연변이(면제 항상 참) → S2 가 경보 누락으로 뒤집힘"        NO  "$(has "$V" bad Qvest_DailyRefresh)"
sed 's/^def _self_reported(name, rc, run_id):$/&\n    return False/' "$JUDGE" > "$TMP/mut_selfF.py"
mkdr "Thu Sep 24 00:03:02     2026" "$SENT1" "$DONE1"
V=$(JUDGE_OVERRIDE="$TMP/mut_selfF.py" run_judge_log "[$DRT]" '{}')
chk "S12 돌연변이(면제 항상 거짓) → S1 이 경보로 뒤집힘"             YES "$(has "$V" bad Qvest_DailyRefresh)"

# ══ v10.4 기보고 원장 확정 조건(D) — 발송되지 않을 신규 실패는 seen 에 확정하지 않는다(09-12 영구 매몰 사례) ══
TODAY8="$(date +%Y%m%d)"; MK="$TMP/task_health_scheduled_task_unhealthy_${TODAY8}.alert"
seen_has() { grep -q "\"$1\"" "$TMP/seen.json" 2>/dev/null && echo YES || echo NO; }
RF="$(mk RealFail Ready 3221225786 hard_terminated_ctrlc_or_exectimelimit 2026-09-24T09:00:00)"
rm -f "$MK"; QVEST_UNATTENDED=1 run_judge "[$RF]" '{}' >/dev/null
chk "D1 무인·오늘 마커 없음(이번 실행이 발송) → seen 확정"          YES "$(seen_has RealFail)"
printf 'detail=실패: Qvest_AxiomActivate(exit_1)\n' > "$MK"; QVEST_UNATTENDED=1 run_judge "[$RF]" '{}' >/dev/null
chk "D2 무인·마커는 있는데 이 작업 미기재(스로틀로 미발송) → 미확정"  NO  "$(seen_has RealFail)"
printf 'detail=실패: RealFail(x)\n' > "$MK"; QVEST_UNATTENDED=1 run_judge "[$RF]" '{}' >/dev/null
chk "D3 무인·마커에 이 작업 기재 → 확정"                           YES "$(seen_has RealFail)"
rm -f "$MK"; run_judge "[$RF]" '{}' >/dev/null
chk "D4 수동 실행(QVEST_UNATTENDED 미선언 = 발송 안 함) → 미확정"   NO  "$(seen_has RealFail)"
V=$(run_judge "[$RF]" '{}')
chk "D4b 미확정이어도 판정(bad)은 그대로 — 경보 축 불변"            YES "$(has "$V" bad RealFail)"
sed 's/    if not _will_report(_n):/    if False:/' "$JUDGE" > "$TMP/mut_confirm.py"
printf 'detail=실패: Qvest_AxiomActivate(exit_1)\n' > "$MK"
QVEST_UNATTENDED=1 JUDGE_OVERRIDE="$TMP/mut_confirm.py" run_judge "[$RF]" '{}' >/dev/null
chk "D5 돌연변이(무조건 확정) → D2 가 확정으로 뒤집힘"              YES "$(seen_has RealFail)"
rm -f "$MK"

TOTAL=$((PASS+FAIL))
echo "  ── $PASS/$TOTAL pass"
printf '{"test":"scheduler_task_health_verdict","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$TOTAL"
[ "$FAIL" -eq 0 ]
