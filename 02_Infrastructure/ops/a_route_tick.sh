#!/usr/bin/env bash
#==============================================================================
# a_route_tick.sh — A 라우터 + 무인 Judge 스폰 (2026-11-15 · 도훈 "A가 나오면 바로 judge로 가게 배선해줘" · A-ROUTE-IMMEDIATE-JUDGE-20261115)
#   호출 = reinforce_auto_tick.sh(예약 작업 Qvest_ReinforceAutoLoop · 8분) 끝. 끄기 = 06_Registry/a_router.json enabled(전체) · judge_auto(스폰만).
#   ① 라우터(02_Infrastructure/programs/a_router.R --write) — 셀 엔진 A 를 후보면 재채점 → A 자격 관문 → eligible | held · 아니면 기록 · 알림
#   ② 스폰 — judge_request.eligible.json(status pending) · 판결 없음 · 끝난 표식 없음 인 폴더 하나를 judge_run.sh 로 배경 실행.
#      한 번에 하나(살아 있는 .judge_running.json 이 있으면 띄우지 않는다) · 하루 상한(judge_daily_cap · 원장 judge_spawn 줄) ·
#      메모리 관문(mem_gate.py judge_run — 재현 측정 = 레인 검증기급 · 먼저 뜬 무거운 작업이 있으면 다음 틱).
#   시험: QVEST_AR_SPAWN=print — 띄우지 않고 무엇을 띄울지만 기록.
#==============================================================================
set -u
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"; ROOT="${ROOT//\\//}"; cd "$ROOT" || exit 0
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
CFG="$ROOT/06_Registry/a_router.json"; [ -f "$CFG" ] || exit 0
LEDGER="$ROOT/06_Registry/a_route_ledger.jsonl"
LOGD="$ROOT/.cache/scheduler_logs"; mkdir -p "$LOGD"; LOG="$LOGD/a_route_$(date +%Y%m%d).log"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
cfgv() { "$PY" -X utf8 -c "import json,sys
c=json.load(open(sys.argv[1],encoding='utf-8')); v=c.get(sys.argv[2])
print('' if v is None else (str(v).lower() if isinstance(v,bool) else v))" "$CFG" "$1" 2>/dev/null | tr -d '\r'; }
la() { "$PY" -X utf8 -c "import json,sys,time
d={'schema':'a_route_v1','at':time.strftime('%Y-%m-%dT%H:%M:%S%z')}
for kv in sys.argv[2:]:
    k,_,v=kv.partition('='); d[k]=v
open(sys.argv[1],'a',encoding='utf-8',newline='\n').write(json.dumps(d,ensure_ascii=False)+'\n')" "$LEDGER" "$@"; }
jget() { "$PY" -X utf8 -c "import json,sys
try: print(json.load(open(sys.argv[1],encoding='utf-8')).get(sys.argv[2],''))
except Exception: print('')" "$1" "$2" 2>/dev/null | tr -d '\r'; }
[ "$(cfgv enabled)" = "true" ] || exit 0

## 잠금 — 라우터와 스폰 결정이 두 틱에서 겹치지 않게(Judge 자체는 배경이라 잠금 밖)
LOCKD="$ROOT/.cache/a_route_tick.lock"
if ! mkdir "$LOCKD" 2>/dev/null; then
  h=$(cat "$LOCKD/pid" 2>/dev/null)
  if [ -n "$h" ] && kill -0 "$h" 2>/dev/null; then exit 0; fi
  rm -rf "$LOCKD"; mkdir "$LOCKD" 2>/dev/null || exit 0
fi
echo "$$" > "$LOCKD/pid"; trap 'rm -rf "$LOCKD"' EXIT

## ① 라우터 — 라우팅 대기가 없으면 한 줄도 남기지 않는다(8분마다 같은 줄이 쌓이지 않게)
out=$(timeout 1800 Rscript 02_Infrastructure/programs/a_router.R --write 2>&1); rrc=$?
printf '%s\n' "$out" | grep -E '^\[a_router\] [0-9]{8}_|^ {11}|실패|판독 불가' | while IFS= read -r l; do log "$l"; done
[ "$rrc" = "0" ] || log "[a_route] 라우터 rc $rrc — $(printf '%s' "$out" | tail -n 2 | tr '\n' ' ' | cut -c1-300)"

## ② 스폰
[ "$(cfgv judge_auto)" = "true" ] || exit 0
for m in stage_artifacts/replication/*/.judge_running.json; do
  [ -f "$m" ] || continue
  p=$(jget "$m" pid); d=$(dirname "$m")
  if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then exit 0; fi                       # 도는 Judge 가 있다 — 한 번에 하나
  w=$(jget "$m" winpid)                                                              # 다른 MSYS 런타임에서 띄운 경우 — Windows pid 로 다시 본다
  if [ -n "$w" ] && powershell.exe -NoProfile -Command "if (Get-Process -Id $w -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }" >/dev/null 2>&1; then exit 0; fi
  log "[a_route] Judge 표식이 남았는데 프로세스가 없다($(basename "$d") pid ${p:-?}) — 끝난 표식으로 바꾼다(다시 띄우지 않는다 · 사람이 본다)"
  mv -f "$m" "$d/.judge_done.json"; la "event=judge_dead" "artifacts=${d#"$ROOT"/}" "pid=${p:-}"
done
cap=$(cfgv judge_daily_cap); case "$cap" in ''|*[!0-9]*) cap=0 ;; esac
today=$(date +%Y-%m-%d)
n=$(grep -F '"event": "judge_spawn"' "$LEDGER" 2>/dev/null | grep -c -F "\"at\": \"$today")
n=${n:-0}
pick=""
for e in $(ls -t stage_artifacts/replication/*/judge_request.eligible.json 2>/dev/null); do
  d=$(dirname "$e")
  [ -f "$d/judge_verdict.json" ] && continue
  [ -f "$d/.judge_done.json" ] && continue
  [ "$(jget "$e" status)" = "pending" ] || continue
  pick="$d"; break
done
[ -n "$pick" ] || exit 0
if [ "$n" -ge "$cap" ]; then log "[a_route] Judge 대기 $(basename "$pick") — 오늘 상한 $cap 도달(내일 첫 틱)"; exit 0; fi
mg=$("$PY" -X utf8 02_Infrastructure/ops/mem_gate.py judge_run 2>&1); mrc=$?; mg=$(printf '%s' "$mg" | tail -n 1 | tr -d '\r')
if [ "$mrc" != "0" ]; then
  # 같은 대기는 한 시간에 한 줄만(8분마다 쌓이지 않게 · 시간마다 한 줄 = 틱이 살아 있다는 표지)
  if ! grep -F "Judge 대기 $(basename "$pick") — 메모리 관문" "$LOG" 2>/dev/null | grep -q -F "$(date '+%F %H'):"; then
    log "[a_route] Judge 대기 $(basename "$pick") — 메모리 관문: $mg"
  fi
  exit 0
fi
if [ "${QVEST_AR_SPAWN:-run}" = "print" ]; then log "[a_route] (print) Judge 스폰 대상 $(basename "$pick") · 관문 $mg"; exit 0; fi
nohup bash "$ROOT/02_Infrastructure/ops/judge_run.sh" "$pick" >> "$LOGD/judge_run_launch.log" 2>&1 < /dev/null &
jp=$!; disown "$jp" 2>/dev/null || true
la "event=judge_spawn" "artifacts=${pick#"$ROOT"/}" "pid=$jp" "gate=$mg"
log "[a_route] Judge 스폰 $(basename "$pick") pid $jp · 관문 $mg"
exit 0
