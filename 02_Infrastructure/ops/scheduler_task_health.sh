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
SEEN_LEDGER="$BASE/.cache/scheduler_alerts/reported_failures.json"
mkdir -p "$(dirname "$SEEN_LEDGER")" 2>/dev/null
VERDICT=$("$PYBIN" - "$OUT" "$SEEN_LEDGER" <<'PY'
import json, sys, io, datetime, os
d = json.load(io.open(sys.argv[1], encoding="utf-8-sig"))
SEEN_PATH = sys.argv[2] if len(sys.argv) > 2 else ""
tasks = d.get("tasks") or []
if isinstance(tasks, dict): tasks = [tasks]        # ConvertTo-Json 은 1건이면 객체로 낸다

# ── 실패 판정 2종 수리 (2026-08-08) ──────────────────────────────────────────
# 구판은 rc≠0 이면 곧장 "실패"로 셌다. 그 결과 08-08 00:03 보고 "실패 4"가 **4건 모두
# 허위**였다. 두 개의 서로 다른 기전:
#
# (A) 실행 중인 작업의 rc 를 판정으로 읽음.
#     `state` 는 수집기가 이미 기록하는데(scheduler_task_health.ps1:65) 판정은 rc 만 봤다.
#     구판의 면제는 `rc_label == "still_running"`(rc 267009) 하나뿐인데, 실행 중 작업이
#     **직전 실행의 rc 를 그대로 들고 있는** 경우가 있어 그 면제를 빗나간다.
#     ★실측 증명(같은 실행, 84초 간격, last_run 불변 2026-08-08T00:00:43):
#         00:03:30  Qvest_StrandedRepairs  state=Running  rc=0x800710E0  → "실패"로 계상
#         00:04:54  Qvest_StrandedRepairs  state=Ready    rc=0           → 그 실행의 진짜 결과
#     즉 0x800710E0 은 **비행 중 과도값**이었고 해당 실행은 성공했다. 08-06 20:12 에도
#     같은 작업이 같은 rc 로 떴다가 20:58 에 사라졌다(동일 서명 2회).
#     → 권위 필드는 `state`. 실행 중이면 "완료된 실행의 판정"이 존재하지 않으므로
#       ok 도 fail 도 아닌 **제3상태 in_flight** 로 둔다(전제-부재 skip 규약과 동형).
#
# (B) 같은 실패 1건을 폴링 때마다 재보고.
#     rc 는 다음 실행 전까지 고정이다. MonthlyDistill·WeeklyCleaner 는 2026-08-01T15:49:19
#     1회 실패 이후 재실행 기회가 없었는데, 그 1건이 **7일간 매 health 실행마다** "실패 2"로
#     찍혔다(task_health.log 08-03~08-08 전 행). 상시 발화는 읽는 사람을 훈련시켜
#     채널을 죽인다 — 실제로 08-08 의 신규 2건이 그 상시 2건 옆에 묻혔다.
#     → 실패의 정체성은 **(작업, 그 실행 시각)**. 이미 보고한 (task, last_run) 은
#       기지(known)로 접고 신규만 경보한다. 매일 실패하는 작업은 매일 last_run 이 바뀌므로
#       매일 새 경보가 난다 — 검출력 손실 없음. 되돌아오지 않는 경우는 staleness 축이 별도로 잡는다.
seen = {}
if SEEN_PATH and os.path.exists(SEEN_PATH):
    try: seen = json.load(io.open(SEEN_PATH, encoding="utf-8")) or {}
    except Exception: seen = {}
if not isinstance(seen, dict): seen = {}

def _ts(s):
    try: return datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%S")
    except Exception: return None

now = datetime.datetime.now()
bad, stale, inflight, known = [], [], [], []
seen_next = dict(seen)
for t in tasks:
    if not t.get("enabled", True):
        continue
    name  = t.get("task")
    state = (t.get("state") or "").strip()
    lbl   = t.get("rc_label")
    rc    = int(t.get("rc") or 0)

    if state == "Running" or lbl == "still_running":
        inflight.append("%s(%s)" % (name, lbl))          # (A) 판정 보류 — 실패 아님
    elif rc != 0 and lbl != "never_run":
        run_id = t.get("last_run") or ""
        if seen.get(name) == run_id and run_id:
            known.append("%s(%s·%s)" % (name, lbl, run_id[5:16]))   # (B) 기보고
        else:
            bad.append("%s(%s)" % (name, lbl))
            seen_next[name] = run_id
    elif rc == 0 and name in seen_next:
        seen_next.pop(name, None)                        # 성공하면 기억을 비운다(다음 실패는 신규)

    ms, ag = t.get("max_stale_days"), t.get("age_days")
    if ms and ag is not None and ag > ms:
        stale.append("%s(%.0f일>%s)" % (name, ag, ms))

# (2026-08-01) 동시 다발 종료를 N건의 개별 실패로 세지 않는다 — **원인은 단정하지 않는다**.
#   실측 2회, 둘 다 "동일 rc·좁은 시간창" 서명이지만 의미가 정반대였다:
#     · 07-27 20:11 — PC 정지. 그때 걸려 있던 작업 6개가 동일 rc(0xC000013A)로 남음. 양성(사후 흔적).
#     · 08-01 15:46 — 부팅 직후 173초 안에 6개가 전부 강제종료. **실제 실패**(morning_run 이 두 번 죽은 원인).
#   서명이 같으므로 코드가 원인을 고를 수 없다. 따라서 하나의 *사건*으로 접기만 하고
#   (경보 6개 → 1개, 개별 실패가 소음에 묻히지 않게) 해석은 사람에게 넘긴다.
#   ★"정지" 로 단정했다가 부팅-몰살을 양성으로 오독할 뻔했다 — 라벨이 사실보다 앞서면 안 된다.
groups = {}
for t in tasks:
    if not t.get("enabled", True) or not int(t.get("rc") or 0):
        continue
    lbl = t.get("rc_label")
    if lbl in ("still_running", "never_run") or (t.get("state") or "").strip() == "Running":
        continue   # 비행 중 rc 는 완료 판정이 아니다 — 동시종료 클러스터의 재료가 될 수 없다
    ts = _ts(t.get("last_run") or "")
    if ts: groups.setdefault(lbl, []).append((ts, t.get("task")))
shutdown = ""
cotermination = None
resume = _ts(d.get("last_resume") or "")
by_name = {t.get("task"): t for t in tasks}
for lbl, items in groups.items():
    if len(items) < 3: continue
    span = (max(i[0] for i in items) - min(i[0] for i in items)).total_seconds()
    if span <= 300:
        t0 = min(i[0] for i in items)
        when = t0.strftime("%m-%d %H:%M")
        names = set(i[1] for i in items)

        # (2026-08-02 개정) ★분류를 **증거**로 한다 — 경과 시간이 아니라.
        #   구판은 hrs<6 이면 "실제 실패", 아니면 "정지 흔적"이라고 라벨을 뒤집었다.
        #   경과 시간은 원인에 대해 아무 정보가 없다 — 같은 사건이 6시간 뒤에 다른 라벨이
        #   된다. 이 저장소가 반복해서 고쳐온 "잘못된 것을 재는 검사기" 계열이다.
        #   대신 재개(resume) 시각과의 근접성을 본다: 재개 직후 15분 안에 동시 시작 =
        #   밀린 트리거 일괄 발화(StartWhenAvailable) 서명.
        mins_after_resume = None
        if resume:
            dt_r = (t0 - resume).total_seconds()
            if dt_r >= 0: mins_after_resume = dt_r / 60.0

        if mins_after_resume is not None and mins_after_resume <= 15.0:
            cls  = "catchup_burst_after_resume"
            hint = ("시스템 재개(%s) 후 %.0f분에 동시 시작 — 밀린 트리거 일괄 발화(catch-up) 서명. "
                    "정지 기간 동안 무인 실행이 0이었다는 뜻" % (resume.strftime("%m-%d %H:%M"), mins_after_resume))
        else:
            cls  = "unclassified"
            hint = "재개 직후 아님 — 개별 실패/머신 정지 양쪽 가능. 원인 단정 금지"

        # 가설 소거 — 기록만으로 반증되는 것은 여기서 잘라낸다(매번 라이브 조회 불필요).
        ruled_out = []
        cl_tasks = [by_name.get(n) or {} for n in names]
        if cl_tasks and all(t.get("stop_on_battery") is False for t in cl_tasks):
            ruled_out.append("배터리 정책(StopIfGoingOnBatteries=false)")
        if cl_tasks and all((t.get("logon_type") or "") == "Interactive" for t in cl_tasks):
            hint += " · 전 작업 LogonType=Interactive = 세션 종료 시 함께 죽는 수명"

        shutdown = "동시 다발 종료 %s — 작업 %d개가 동일 사유(%s)·%.0f초 창. %s%s" % (
            when, len(items), lbl, span, hint,
            (" [소거: %s]" % ", ".join(ruled_out)) if ruled_out else "")
        cotermination = {
            "when": t0.strftime("%Y-%m-%dT%H:%M:%S"), "n": len(items), "rc_label": lbl,
            "span_sec": int(span), "tasks": sorted(names), "classification": cls,
            "minutes_after_resume": (round(mins_after_resume, 1) if mins_after_resume is not None else None),
            "ruled_out": ruled_out, "hint": hint,
            # 사망 주체를 이름으로 지목하려면 이 로그가 켜져 있어야 한다. 꺼져 있으면
            # 사후 규명이 **불가능**하므로 "미확정"이 정직한 판정이다(추정 금지).
            "terminator_identifiable": bool(d.get("tasksched_oplog_enabled")),
        }
        bad = [b for b in bad if b.split("(")[0] not in names]
        break

# ★판정을 원장에 되쓴다 — 소비자(bootstrap)가 raw rc 로 **다시 판정하지 않게**.
#   08-02 실측: 부팅 4i 가 이 클러스터링을 모른 채 원시 rc 만 보고 5건을 개별 "★실패"로
#   보고했다(권위 스크립트는 같은 데이터로 "실패 1 · 정지 1"). 렌더러가 둘이면 판정도 둘이다.
d["cotermination"] = cotermination
# 제3상태와 기보고 실패를 **원장에 남긴다** — 경보에서 접었다고 기록에서까지 지우면
# "조용해진 것"과 "고쳐진 것"을 구분할 수 없다(침묵 실패 계통 그 자체).
d["verdict"] = {
    "failed_new": bad, "failed_known": known, "in_flight": inflight, "stale": stale,
    "note": "in_flight=state==Running(완료 판정 부재, 실패 아님) / failed_known=이미 보고한 (task,last_run) 재출현",
}
try:
    io.open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(d, ensure_ascii=False, indent=2))
except Exception:
    pass   # 되쓰기 실패가 판정 자체를 막지는 않는다(원장은 보조 표면)

# 기보고 원장 갱신 — 실패를 **경보한 뒤에만** 기록한다(경보 없이 기록하면 그 실패는 영영 안 보인다)
if SEEN_PATH:
    try:
        io.open(SEEN_PATH, "w", encoding="utf-8").write(json.dumps(seen_next, ensure_ascii=False, indent=2))
    except Exception:
        pass

print(json.dumps({"n": len(tasks), "bad": bad, "stale": stale, "shutdown": shutdown,
                  "inflight": inflight, "known": known}, ensure_ascii=False))
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
INFLT=$(printf '%s' "$VERDICT"  | "$PYBIN" -c 'import json,sys;print(" ".join(json.load(sys.stdin).get("inflight",[])))')
KNOWN=$(printf '%s' "$VERDICT"  | "$PYBIN" -c 'import json,sys;print(" ".join(json.load(sys.stdin).get("known",[])))')
if command -v sched_assert_count >/dev/null 2>&1 && ! sched_assert_count "$N"; then
  log "★ 작업 수가 비숫자('$N') — 계측 사망."; exit 1
fi
[ "$N" -eq 0 ] && { log "★ Qvest_* 작업 0건 — 등록이 사라졌는지 확인 필요."; }

nbad=$( [ -n "$BAD" ]    && echo "$BAD"    | wc -w || echo 0 )
nst=$(  [ -n "$STALE" ]  && echo "$STALE"  | wc -w || echo 0 )
nif=$(  [ -n "$INFLT" ]  && echo "$INFLT"  | wc -w || echo 0 )
nkn=$(  [ -n "$KNOWN" ]  && echo "$KNOWN"  | wc -w || echo 0 )
log "예약작업 $N개 · 신규실패 ${nbad} · 정체 ${nst} · 진행중 ${nif} · 기지실패 ${nkn}${SHUTDOWN:+ · 정지 1}"
[ -n "$SHUTDOWN" ] && log "  ※$SHUTDOWN — 개별 작업 실패가 아니라 하나의 사건으로 계수"
[ -n "$BAD" ]   && log "  ★신규실패: $BAD"
[ -n "$STALE" ] && log "  ★정체: $STALE"
# 아래 2종은 경보 대상이 아니지만 **로그에는 남긴다** — 조용해진 것과 고쳐진 것을 구분하기 위함
[ -n "$INFLT" ] && log "  · 진행중(판정 보류): $INFLT"
[ -n "$KNOWN" ] && log "  · 기보고 실패(재시도 대기): $KNOWN"

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
