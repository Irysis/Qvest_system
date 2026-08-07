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

# ── T9/T10 돌연변이 ★면제 규칙이 실제로 일을 하는지: 규칙을 무력화하면 T2/T4 가 뒤집혀야 한다.
#    뒤집히지 않으면 그 "통과"는 규칙 덕이 아니라 우연이다.
sed 's/state == "Running" or lbl == "still_running"/False/' "$JUDGE" > "$TMP/mut_state.py"
V=$(JUDGE_OVERRIDE="$TMP/mut_state.py" run_judge "[$(mk Inflt Running 2147946720 nt_status_0x800710E0 2026-08-08T00:00:43)]" '{}')
chk "T9 돌연변이(state 가드 제거) → T2 가 실패로 뒤집힘" YES "$(has "$V" bad Inflt)"

sed 's/seen.get(name) == run_id and run_id/False/' "$JUDGE" > "$TMP/mut_seen.py"
V=$(JUDGE_OVERRIDE="$TMP/mut_seen.py" run_judge "[$(mk Dup Ready 3221225786 hard_terminated_ctrlc_or_exectimelimit 2026-08-01T15:49:19)]" "$SEEN")
chk "T10 돌연변이(기보고 dedup 제거) → T4 가 실패로 뒤집힘" YES "$(has "$V" bad Dup)"

TOTAL=$((PASS+FAIL))
echo "  ── $PASS/$TOTAL pass"
printf '{"test":"scheduler_task_health_verdict","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$TOTAL"
[ "$FAIL" -eq 0 ]
