#!/usr/bin/env bash
# test_scn_data_task_never_run.sh — "예약 작업이 한 번도 안 돈 상태(rc 267011)를 누가 알아채는가" 시나리오 (감사 레인 A · 2026-11-10)
#
# 사고: 11-10 이 PC 에서 Qvest_WeeklyCleaner(주간) · Qvest_MonthlyDistill(월간)이 rc 267011(never_run)인데 next_run 이 있어
#   scheduler_task_health 판정의 어느 축(rc · 마지막 실행 나이 · 다음 실행 없음)에도 안 걸렸다. 판정 블록 주석은
#   "'다음 실행 없음' 축이 잡는다"고 했지만 다음 실행이 있는 never_run 에는 거짓이었다.
# 수리: 판정 블록이 never_run 작업의 **첫 관측 시각**을 기계별로 기억(.cache/scheduler_alerts/task_first_seen.json)하고,
#   그 뒤 주기(max_stale_days)를 넘겨도 한 번도 안 돌았으면 정체로 올린다.
# 방법: 원본 scheduler_task_health.sh 에서 판정 블록(<<'PY' … PY)을 떼어 합성 작업 표로 돌린다(사본 재구현 없음 · 운영 원장 무접촉).
#   N1 첫 관측 → 경보 없음 + 기억 기록 · N2 첫 관측 10일 뒤(주간 9) → 정체 · N3 5일 뒤 → 없음 · N4 비활성 → 없음
#   N5 로그온 트리거 전용 → 없음 · N6 손상된 기억 파일 → 죽지 않고 오늘부터 센다 · N7 다른 기계 키는 섞이지 않는다
#   N8 돌연변이(문턱 +9999) → N2 를 놓친다 · N9 한 번이라도 돈 작업(ok)은 이 축과 무관
# 요약: 마지막 줄 {"test":"scn_data_task_never_run","pass":N,"fail":N,"total":N}
set -uo pipefail
T=scn_data_task_never_run
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
MARK="02_Infrastructure/hooks/qvest_hook_router.py"
PROJ=""
for c in "$_SELF_DIR/../.." "${CLAUDE_PROJECT_DIR:-}" "${QM_ROOT:-}"; do
  [ -n "$c" ] && [ -f "${c//\\//}/$MARK" ] && { PROJ="$(cd "${c//\\//}" && pwd)"; break; }
done
fin() { echo "{\"test\":\"$T\",\"pass\":$1,\"fail\":$2,\"total\":$(( $1 + $2 ))}"; [ "$2" -eq 0 ]; exit $?; }
[ -n "$PROJ" ] || { echo "루트 해석 실패"; fin 0 1; }
SRC="$PROJ/02_Infrastructure/ops/scheduler_task_health.sh"
PY=""
for c in "$PROJ/.venv_qvest_ml/Scripts/python.exe" "$PROJ/.venv_qvest_ml/bin/python" "${QVEST_PY:-}"; do
  [ -n "$c" ] && [ -x "$c" ] && "$c" -c 'import json,datetime,io,os' >/dev/null 2>&1 && { PY="$c"; break; }
done
[ -n "$PY" ] || { echo "python 없음"; fin 0 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
JUDGE="$TMP/judge.py"
awk "/<<'PY'/{f=1;next} /^PY\$/{f=0} f" "$SRC" > "$JUDGE"
grep -q 'task_first_seen.json' "$JUDGE" || { echo "판정 블록에 never_run 축 없음(미설치)"; fin 0 1; }

PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1 — 기대 '$2' / 실제 '$3'"; fi; }
# mk <name> <rc> <label> <enabled> <max_stale> <time_scheduled> [last_run]
mk() { local lr="null"; [ -n "${7:-}" ] && lr="\"$7\""
  printf '{"task":"%s","state":"Ready","rc":%s,"rc_label":"%s","last_run":%s,"age_days":%s,"max_stale_days":%s,"enabled":%s,"next_run":"2099-01-01T09:00:00","time_scheduled":%s,"logon_type":"Interactive","stop_on_battery":false,"start_when_available":true}' \
    "$1" "$2" "$3" "$lr" "$([ -n "${7:-}" ] && echo 0.5 || echo null)" "$5" "$4" "$6"; }
run() {  # $1=tasks array  $2=first_seen json(또는 RAW:<내용>)  [$3=judge]
  printf '{"schema_version":2,"measured_at":"x","last_resume":null,"last_boot":null,"tasksched_oplog_enabled":false,"tasks":%s}' "$1" > "$TMP/fx.json"
  printf '{}' > "$TMP/seen.json"
  case "$2" in RAW:*) printf '%s' "${2#RAW:}" > "$TMP/task_first_seen.json" ;; "") rm -f "$TMP/task_first_seen.json" ;; *) printf '%s' "$2" > "$TMP/task_first_seen.json" ;; esac
  COMPUTERNAME=TESTPC QVEST_UNATTENDED=0 "$PY" "${3:-$JUDGE}" "$TMP/fx.json" "$TMP/seen.json" 2>"$TMP/err.txt"
}
stale_has() { printf '%s' "$1" | "$PY" -c "import json,sys;d=json.load(sys.stdin);print('YES' if any(x.startswith('$2(') and '한 번도' in x for x in d.get('stale',[])) else 'NO')" 2>/dev/null || echo PARSE_FAIL; }
ago() { "$PY" -c "import datetime;print((datetime.datetime.now()-datetime.timedelta(days=$1)).strftime('%Y-%m-%dT%H:%M:%S'))"; }

echo "== $T =="
W="$(mk Weekly 267011 never_run true 9 true)"
V=$(run "[$W]" "")
chk "N1 첫 관측 — 경보 없음" NO "$(stale_has "$V" Weekly)"
chk "N1b 첫 관측 기억 기록(TESTPC|Weekly)" YES "$(grep -q '"TESTPC|Weekly"' "$TMP/task_first_seen.json" 2>/dev/null && echo YES || echo NO)"
V=$(run "[$W]" "{\"TESTPC|Weekly\":\"$(ago 10)\"}")
chk "N2 첫 관측 10일 뒤(주간 9) — 정체" YES "$(stale_has "$V" Weekly)"
V=$(run "[$W]" "{\"TESTPC|Weekly\":\"$(ago 5)\"}")
chk "N3 첫 관측 5일 뒤 — 경보 없음" NO "$(stale_has "$V" Weekly)"
V=$(run "[$(mk Off 267011 never_run false 9 true)]" "{\"TESTPC|Off\":\"$(ago 30)\"}")
chk "N4 비활성 작업 — 경보 없음" NO "$(stale_has "$V" Off)"
V=$(run "[$(mk Logon 267011 never_run true null false)]" "{\"TESTPC|Logon\":\"$(ago 30)\"}")
chk "N5 로그온 트리거 전용 — 경보 없음" NO "$(stale_has "$V" Logon)"
V=$(run "[$W]" "RAW:{not json")
chk "N6 손상된 기억 — 죽지 않음(판정 출력 있음)" YES "$(printf '%s' "$V" | grep -q '"stale"' && echo YES || echo NO)"
chk "N6b 손상 뒤 오늘부터 센다(경보 없음)" NO "$(stale_has "$V" Weekly)"
V=$(run "[$W]" "{\"OTHERPC|Weekly\":\"$(ago 30)\"}")
chk "N7 다른 기계의 첫 관측은 쓰지 않는다" NO "$(stale_has "$V" Weekly)"
V=$(run "[$(mk Ran 0 ok true 9 true 2026-11-09T09:00:00)]" "{\"TESTPC|Ran\":\"$(ago 30)\"}")
chk "N9 한 번이라도 돈 작업 — 이 축과 무관" NO "$(stale_has "$V" Ran)"
# N8 돌연변이 — 소스 텍스트 치환 정확히 1곳
MUT="$TMP/judge_mut.py"; NEEDLE='if nr_age > float(ms):'
n=$(grep -cF "$NEEDLE" "$JUDGE")
chk "N8 치환 대상 정확히 1곳" 1 "$n"
"$PY" -c "import sys;s=open(sys.argv[1],encoding='utf-8').read();open(sys.argv[2],'w',encoding='utf-8').write(s.replace(sys.argv[3],'if nr_age > float(ms) + 9999:',1))" "$JUDGE" "$MUT" "$NEEDLE"
chk "N8 치환 성사" YES "$(cmp -s "$JUDGE" "$MUT" && echo NO || echo YES)"
V=$(run "[$W]" "{\"TESTPC|Weekly\":\"$(ago 10)\"}" "$MUT")
chk "N8 돌연변이는 N2 를 놓친다" NO "$(stale_has "$V" Weekly)"
fin "$PASS" "$FAIL"
