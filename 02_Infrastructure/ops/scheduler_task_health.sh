#!/bin/bash
# scheduler_task_health.sh — 예약작업 *바깥 경계* 판정 + 경보 (2026-07-26 신설)
#
# 오늘(07-26) 무인 파이프라인 8일 정지 수리는 전부 스크립트 *안*을 고쳤다.
# 그런데 실측해 보니 OS 작업이 아예 안 돌거나 중도에 죽는 경우를 읽는 코드가 저장소에 0건이었다:
#   · InsiderBackfill  02:00  rc=0xC000013A  로그 파일 자체 없음 — 조용히 실패 중
#   · StrandedRepairs  12:00/20:00           로그 한 줄 없이 사라짐
# 스크립트가 실행되기만 하면 오늘 만든 계측이 다 작동하지만, *실행 자체가 없으면* 전부 무의미하다.
# 이 스크립트가 그 바깥 한 겹을 덮는다.
#
# 판정 2종:
#   rc≠0           — 마지막 실행이 실패/강제종료
#   stale          — 주기 대비 실행이 끊김 (일간 2일 · 주간 9일 · 월간 35일 초과)
# 둘 다 아니면 침묵. --quiet 는 요약 1줄만.
#
# 읽기 전용: 작업을 고치거나 재발화하지 않는다(자동 복구는 판단을 숨긴다 — 도훈 통지가 목적).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
BASE="${BASE:-${PROJECT:-$PWD}}"; cd "$BASE" || exit 1
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_sched_failure_classify.sh" 2>/dev/null || true

QUIET=0; for a in "$@"; do [ "$a" = "--quiet" ] && QUIET=1; done
OUT="$BASE/06_Registry/scheduler_task_health.json"
LOG="$BASE/.cache/scheduler_logs/task_health.log"; mkdir -p "$(dirname "$LOG")"
log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; [ "$QUIET" = "1" ] || echo "[$(date '+%H:%M:%S')] $*"; }

PS1BIN="$BASE/02_Infrastructure/ops/scheduler_task_health.ps1"
[ -f "$PS1BIN" ] || { log "★ 수집기 없음: $PS1BIN"; exit 1; }

# 1) 수집 (PowerShell). 실패를 0 으로 삼키지 않는다.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass \
  -File "$(cygpath -w "$PS1BIN" 2>/dev/null || echo "$PS1BIN")" \
  -OutFile "$(cygpath -w "$OUT" 2>/dev/null || echo "$OUT")" >/dev/null 2>&1
rc=$?
if [ $rc -ne 0 ] || [ ! -s "$OUT" ]; then
  log "★ 수집 실패 (powershell exit=$rc, 산출물 $( [ -s "$OUT" ] && echo 있음 || echo 없음 )) — 계측 사망. 0건으로 간주하지 않음."
  command -v sched_alert_emit >/dev/null 2>&1 && command -v sched_is_unattended >/dev/null 2>&1 && sched_is_unattended \
    && sched_alert_emit "task_health" "count_measurement_failed" "예약작업 수집기가 산출물을 못 냈음 (powershell exit=$rc)"
  exit 1
fi

# 2) 판정
PYBIN=""; command -v sched_resolve_python >/dev/null 2>&1 && PYBIN=$(sched_resolve_python || true)
[ -n "$PYBIN" ] || PYBIN="python3"
VERDICT=$("$PYBIN" - "$OUT" <<'PY'
import json, sys, io, datetime
d = json.load(io.open(sys.argv[1], encoding="utf-8-sig"))
tasks = d.get("tasks") or []
if isinstance(tasks, dict): tasks = [tasks]        # ConvertTo-Json 은 1건이면 객체로 낸다
bad, stale = [], []
for t in tasks:
    if not t.get("enabled", True):
        continue
    if int(t.get("rc") or 0) != 0 and t.get("rc_label") not in ("still_running", "never_run"):
        bad.append("%s(%s)" % (t.get("task"), t.get("rc_label")))
    ms, ag = t.get("max_stale_days"), t.get("age_days")
    if ms and ag is not None and ag > ms:
        stale.append("%s(%.0f일>%s)" % (t.get("task"), ag, ms))

# (2026-08-01) 동시 다발 종료를 N건의 개별 실패로 세지 않는다 — **원인은 단정하지 않는다**.
#   실측 2회, 둘 다 "동일 rc·좁은 시간창" 서명이지만 의미가 정반대였다:
#     · 07-27 20:11 — PC 정지. 그때 걸려 있던 작업 6개가 동일 rc(0xC000013A)로 남음. 양성(사후 흔적).
#     · 08-01 15:46 — 부팅 직후 173초 안에 6개가 전부 강제종료. **실제 실패**(morning_run 이 두 번 죽은 원인).
#   서명이 같으므로 코드가 원인을 고를 수 없다. 따라서 하나의 *사건*으로 접기만 하고
#   (경보 6개 → 1개, 개별 실패가 소음에 묻히지 않게) 해석은 사람에게 넘긴다.
#   ★"정지" 로 단정했다가 부팅-몰살을 양성으로 오독할 뻔했다 — 라벨이 사실보다 앞서면 안 된다.
def _ts(s):
    try: return datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%S")
    except Exception: return None
groups = {}
for t in tasks:
    if not t.get("enabled", True) or not int(t.get("rc") or 0):
        continue
    lbl = t.get("rc_label")
    if lbl in ("still_running", "never_run"):
        continue
    ts = _ts(t.get("last_run") or "")
    if ts: groups.setdefault(lbl, []).append((ts, t.get("task")))
shutdown = ""
for lbl, items in groups.items():
    if len(items) < 3: continue
    span = (max(i[0] for i in items) - min(i[0] for i in items)).total_seconds()
    if span <= 300:
        t0 = min(i[0] for i in items)
        when = t0.strftime("%m-%d %H:%M")
        # 시간 위치로 두 후보를 제시만 한다(선택은 사람). 최근(6h 이내) = 머신 가동 중 몰살일 확률↑
        hrs = (datetime.datetime.now() - t0).total_seconds() / 3600.0
        hint = ("부팅/가동 중 동시 강제종료 의심 — 실제 실패" if hrs < 6
                else "머신 정지 시각의 사후 흔적일 수 있음")
        shutdown = "동시 다발 종료 %s — 작업 %d개가 동일 사유(%s)·%.0f초 창. %s" % (
            when, len(items), lbl, span, hint)
        names = set(i[1] for i in items)
        bad = [b for b in bad if b.split("(")[0] not in names]
        break
print(json.dumps({"n": len(tasks), "bad": bad, "stale": stale, "shutdown": shutdown}, ensure_ascii=False))
PY
)
if [ -z "${VERDICT:-}" ]; then
  log "★ 판정 실패 (PYBIN=$PYBIN 이 빈 출력) — 계측 사망."
  command -v sched_alert_emit >/dev/null 2>&1 && command -v sched_is_unattended >/dev/null 2>&1 && sched_is_unattended \
    && sched_alert_emit "task_health" "count_measurement_failed" "판정 단계 빈 출력 (PYBIN=$PYBIN)"
  exit 1
fi

N=$(printf '%s' "$VERDICT"     | "$PYBIN" -c 'import json,sys;print(json.load(sys.stdin)["n"])')
BAD=$(printf '%s' "$VERDICT"   | "$PYBIN" -c 'import json,sys;print(" ".join(json.load(sys.stdin)["bad"]))')
STALE=$(printf '%s' "$VERDICT" | "$PYBIN" -c 'import json,sys;print(" ".join(json.load(sys.stdin)["stale"]))')
SHUTDOWN=$(printf '%s' "$VERDICT" | "$PYBIN" -c 'import json,sys;print(json.load(sys.stdin).get("shutdown",""))')
if command -v sched_assert_count >/dev/null 2>&1 && ! sched_assert_count "$N"; then
  log "★ 작업 수가 비숫자('$N') — 계측 사망."; exit 1
fi
[ "$N" -eq 0 ] && { log "★ Qvest_* 작업 0건 — 등록이 사라졌는지 확인 필요."; }

nbad=$( [ -n "$BAD" ]   && echo "$BAD"   | wc -w || echo 0 )
nst=$(  [ -n "$STALE" ] && echo "$STALE" | wc -w || echo 0 )
log "예약작업 $N개 · 실패 ${nbad} · 정체 ${nst}${SHUTDOWN:+ · 정지 1}"
[ -n "$SHUTDOWN" ] && log "  ※$SHUTDOWN — 개별 작업 실패가 아니라 하나의 사건으로 계수"
[ -n "$BAD" ]   && log "  ★실패: $BAD"
[ -n "$STALE" ] && log "  ★정체: $STALE"

# 3) 경보 — 무인 선언 시에만 (TTY 추론 아님. 내 시험 실행이 도훈 텔레그램으로 새는 사고 재발방지)
#    시스템 정지는 그 자체로 경보 대상 — 4일간 무인 실행이 0 이었다는 뜻이기 때문(08-01 실측).
#    단 작업 수만큼이 아니라 **1건**으로 낸다.
if { [ -n "$BAD" ] || [ -n "$STALE" ] || [ -n "$SHUTDOWN" ]; } && command -v sched_is_unattended >/dev/null 2>&1 && sched_is_unattended; then
  if command -v sched_alert_emit >/dev/null 2>&1; then
    det=""
    [ -n "$SHUTDOWN" ] && det="$SHUTDOWN"
    [ -n "$BAD" ]   && det="${det}${det:+ | }실패: $BAD"
    [ -n "$STALE" ] && det="${det}${det:+ | }정체: $STALE"
    sched_alert_emit "task_health" "scheduled_task_unhealthy" \
      "$det | 상세 06_Registry/scheduler_task_health.json (작업 스크립트가 실행 자체를 못 한 경우 — 스크립트 내부 계측은 이 상황을 볼 수 없음)"
  fi
fi
exit 0
