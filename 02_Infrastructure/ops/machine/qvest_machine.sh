#!/usr/bin/env bash
# qvest_machine.sh — 두 대 운용(메인 PC · 노트북)의 기계 역할 · 메인 우선 게이트 · OneDrive 동기화 안정 판정
#
# 2026-11-01 도훈 지시: "메인 PC 나 노트북 둘 중 하나를 켜더라도 Qvest 문제없이 작업 가능하게 · 둘 다 켜져 있을 땐
#   메인 PC 를 우선". 작업 트리는 OneDrive 로 하나를 공유한다(두 기계 모두 C:/Users/99922/OneDrive/Quant_Module_Moltbot
#   — 메인 PC 는 C:\Users\99922 → C:\Users\User 연결). 예약 작업은 두 기계에 같은 세트를 등록하고 이 게이트로 거른다
#   (qvest_tasks.ps1 -Mode Apply 가 만드는 실행기가 gate · done 을 부른다).
#
# 왜: 두 대가 같은 예약 작업을 함께 돌리면 같은 원장 · 캐시를 동시에 쓰고, OneDrive 는 그 충돌을 '이름-기계명' 사본으로
#   남긴다(실측: OneDrive/.claude_shared 의 *-MainComputer* 사본 2026-05-24). 원장이 갈라지면 사람이 정본을 가려야 한다.
#
# 규칙 (period = 주기 키: day | week | month | hour | none | local)
#   main      이 주기를 다른 기계가 이미 돌렸으면 건너뛰고, 아니면 표식(claim)을 남기고 실행.
#             방금 깨어났으면(생존 신호 오래됨 · woke 가 최근) WAKE 초 기다린 뒤 판정 — 꺼져 있던 동안 노트북이 남긴
#             표식이 OneDrive 로 내려올 시간을 준다.
#   secondary SETTLE 초 기다린 뒤 판정. 다른 기계 표식이 있으면 건너뜀. 메인이 살아 있고 그 작업을 맡고 있으면
#             GRACE 초 더 기다려 메인 표식을 확인하고, 그래도 없으면(메인이 놓침) 대신 실행.
#             period=none(수 분 간격 작업)은 기다리지 않는다 — 메인이 맡고 있으면 건너뛰고 아니면 실행.
#   local     게이트 없음 — 기계마다 따로 도는 작업(그 기계의 보안 로그를 읽는 AuditWatch 등).
#   판정할 수 없으면(잘못된 period 등) 실행한다 — 작업을 잃는 쪽보다 한 번 더 도는 쪽이 낫다.
#
# 하위 명령
#   role | status | heartbeat | gate <job> <period> | done <job> <period> <rc> | settled [project]
#   종료 코드: gate 0 = 실행 · 10 = 건너뜀 / settled 0 = 안정 · 1 = 불안정(사유 1줄 stdout) / heartbeat 2 = main 아님
# 상태: <root>/.cache/machine/ (gitignore — OneDrive 로만 공유) · heartbeat_main.txt · runs/<job>__<key>__<HOST>.txt
#   로그는 기계별 파일(gate_<HOST>.log) — 같은 파일을 두 기계가 쓰면 그 자체가 충돌 사본이 된다.
# 검사: 08_Tests/ops/test_qvest_machine.sh
set -u

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${QVEST_MACHINE_ROOT:-$(cd "$_HERE/../../.." && pwd)}"
CONF="${QVEST_MACHINE_CONF:-$_HERE/machines.conf}"
MDIR="${QVEST_MACHINE_DIR:-$ROOT/.cache/machine}"
HOST="${QVEST_HOST:-${COMPUTERNAME:-$(hostname 2>/dev/null || echo unknown)}}"
STALE_SEC="${QVEST_HEARTBEAT_STALE_SEC:-900}"
SETTLE_SEC="${QVEST_GATE_SETTLE_SEC:-300}"
GRACE_SEC="${QVEST_GATE_GRACE_SEC:-300}"
WAKE_SEC="${QVEST_GATE_WAKE_SEC:-180}"
NOW="$(date +%s)"

_upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
HOSTU="$(_upper "$HOST")"

_log() {
  mkdir -p "$MDIR" 2>/dev/null || return 0
  printf '%s %s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$HOSTU" "$*" >> "$MDIR/gate_${HOSTU}.log" 2>/dev/null || true
}

_conf() { [ -f "$CONF" ] && tr -d '\r' < "$CONF" | sed 's/#.*//'; }

_role() {
  local r="${QVEST_MACHINE_ROLE:-}"
  [ -n "$r" ] || r="$(_conf | awk -v h="$HOSTU" '$1=="machine" && toupper($2)==h {print $3; exit}')"
  case "$r" in main|secondary) echo "$r" ;; *) echo secondary ;; esac
}

_conf_period() {  # $1 job · $2 기본값
  local p
  p="$(_conf | awk -v j="$1" '$1=="period" && $2==j {print $3; exit}')"
  echo "${p:-$2}"
}

_period_key() {
  case "$1" in
    day)        date +%Y-%m-%d ;;
    week)       date +%G-W%V ;;
    month)      date +%Y-%m ;;
    hour)       date +%Y-%m-%dT%H ;;
    none|local) echo "-" ;;
    *)          return 1 ;;
  esac
}

_safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'; }

_hb_field() {  # heartbeat_main.txt 의 key=value 한 칸
  [ -f "$MDIR/heartbeat_main.txt" ] || return 1
  tr -d '\r' < "$MDIR/heartbeat_main.txt" | tr ' ' '\n' | sed -n "s/^$1=//p" | head -1
}

_num_or_empty() { case "$1" in ''|*[!0-9]*) echo "" ;; *) echo "$1" ;; esac; }

_hb_age() {
  local e; e="$(_num_or_empty "$(_hb_field epoch 2>/dev/null)")"
  [ -n "$e" ] && echo $(( NOW - e )) || echo ""
}

# 메인이 살아 있고 그 작업을 맡고 있나 — 생존 신호의 jobs 목록(메인에 등록된 실행기)에 없으면 맡지 않은 것으로 본다.
_main_covers() {  # $1 job → 0 = 맡음
  local age jobs
  age="$(_hb_age)"
  [ -n "$age" ] && [ "$age" -le "$STALE_SEC" ] || return 1
  jobs="$(_hb_field jobs 2>/dev/null)"
  [ -z "$jobs" ] && return 0
  case ",$jobs," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

_other_claim() {  # $1 job · $2 key → 다른 기계 표식이 있으면 기계명을 찍고 0
  local f h found=""
  for f in "$MDIR/runs/$(_safe "$1")__$2__"*.txt; do
    [ -e "$f" ] || continue
    h="${f##*__}"; h="${h%.txt}"
    [ "$(_upper "$h")" = "$HOSTU" ] && continue
    found="$found${found:+,}$h"
  done
  [ -n "$found" ] && { echo "$found"; return 0; }
  return 1
}

_claim() {  # $1 job · $2 key · $3 role
  [ "$2" = "-" ] && return 0
  mkdir -p "$MDIR/runs" 2>/dev/null || return 0
  printf 'host=%s role=%s start=%s\n' "$HOSTU" "$3" "$(date '+%Y-%m-%dT%H:%M:%S%z')" \
    > "$MDIR/runs/$(_safe "$1")__$2__${HOSTU}.txt" 2>/dev/null || true
}

_gate() {
  local job="${1:-}" period="${2:-day}" role key other age woke wait=0
  [ -n "$job" ] || { echo "usage: gate <job> <period>" >&2; return 2; }
  period="$(_conf_period "$job" "$period")"
  role="$(_role)"
  if [ "$period" = "local" ]; then _log "gate $job local RUN role=$role"; return 0; fi
  if ! key="$(_period_key "$period")"; then _log "gate $job period=$period RUN reason=bad_period(fail-open)"; return 0; fi
  if [ "${QVEST_GATE_FORCE:-0}" = "1" ]; then _claim "$job" "$key" "$role"; _log "gate $job $key RUN reason=force"; return 0; fi

  if [ "$role" = "main" ]; then
    age="$(_hb_age)"; woke="$(_num_or_empty "$(_hb_field woke 2>/dev/null)")"
    if [ -z "$age" ] || [ "$age" -gt "$STALE_SEC" ]; then wait="$WAKE_SEC"
    elif [ -n "$woke" ] && [ $(( NOW - woke )) -lt "$WAKE_SEC" ]; then wait=$(( WAKE_SEC - (NOW - woke) ))
    fi
    if [ "$wait" -gt 0 ] && [ "$key" != "-" ]; then
      _log "gate $job $key wake_wait=${wait}s heartbeat_age=${age:-none}"
      sleep "$wait"; NOW="$(date +%s)"
    fi
    if [ "$key" != "-" ] && other="$(_other_claim "$job" "$key")"; then
      _log "gate $job $key SKIP role=main claimed_by=$other"; return 10
    fi
    _claim "$job" "$key" main
    _log "gate $job $key RUN role=main"; return 0
  fi

  # secondary
  if [ "$key" = "-" ]; then
    if _main_covers "$job"; then _log "gate $job - SKIP role=secondary main_alive age=$(_hb_age)s"; return 10; fi
    _log "gate $job - RUN role=secondary main_heartbeat_age=$(_hb_age)"; return 0
  fi
  sleep "$SETTLE_SEC"; NOW="$(date +%s)"
  if other="$(_other_claim "$job" "$key")"; then
    _log "gate $job $key SKIP role=secondary claimed_by=$other"; return 10
  fi
  if _main_covers "$job"; then
    sleep "$GRACE_SEC"; NOW="$(date +%s)"
    if other="$(_other_claim "$job" "$key")"; then
      _log "gate $job $key SKIP role=secondary claimed_by=$other after_grace"; return 10
    fi
    _claim "$job" "$key" secondary
    _log "gate $job $key RUN role=secondary reason=main_alive_but_unclaimed"; return 0
  fi
  _claim "$job" "$key" secondary
  _log "gate $job $key RUN role=secondary reason=main_absent heartbeat_age=$(_hb_age)"; return 0
}

_done() {  # $1 job · $2 period · $3 rc
  local job="${1:-}" period="${2:-}" rc="${3:-?}" key f
  key="$(_period_key "$(_conf_period "$job" "$period")" 2>/dev/null)" || key="-"
  if [ "$key" != "-" ]; then
    f="$MDIR/runs/$(_safe "$job")__${key}__${HOSTU}.txt"
    [ -f "$f" ] || f="$(ls -t "$MDIR/runs/$(_safe "$job")__"*"__${HOSTU}.txt" 2>/dev/null | head -1)"
    [ -n "$f" ] && [ -f "$f" ] && printf 'end=%s rc=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$rc" >> "$f"
  fi
  _log "done $job $key rc=$rc"
  return 0
}

_heartbeat() {
  local role prev woke d jobs="" iso
  role="$(_role)"
  [ "$role" = "main" ] || { echo "heartbeat: 이 기계 역할 = $role (main 전용)" >&2; return 2; }
  mkdir -p "$MDIR/runs" || return 1
  prev="$(_num_or_empty "$(_hb_field epoch 2>/dev/null)")"
  woke="$(_num_or_empty "$(_hb_field woke 2>/dev/null)")"
  if [ -z "$prev" ] || [ $(( NOW - prev )) -gt "$STALE_SEC" ] || [ -z "$woke" ]; then woke="$NOW"; fi
  d="${QVEST_JOBS_DIR:-}"
  if [ -z "$d" ] && [ -n "${LOCALAPPDATA:-}" ]; then d="$(cygpath -u "$LOCALAPPDATA" 2>/dev/null || echo "$LOCALAPPDATA")/Qvest/jobs"; fi
  if [ -n "$d" ] && [ -d "$d" ]; then
    jobs="$(ls "$d" 2>/dev/null | sed -n 's/\.cmd$//p' | paste -sd, -)"
    jobs="${jobs:-(none)}"
  fi
  iso="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  printf 'epoch=%s woke=%s host=%s iso=%s jobs=%s\n' "$NOW" "$woke" "$HOSTU" "$iso" "$jobs" > "$MDIR/heartbeat_main.txt"
  find "$MDIR/runs" -maxdepth 1 -type f -name "*__${HOSTU}.txt" -mtime +35 -delete 2>/dev/null
  return 0
}

_python() {  # 기능 프로브로 고른다 — bare python 은 Windows Store 스텁일 수 있다(harness.md 종료코드 사전 점검)
  local c
  for c in "${QVEST_PY_BIN:-}" "${QVEST_PY:-}" python.exe python; do
    [ -n "$c" ] || continue
    "$c" -c 'import os, re, sys' >/dev/null 2>&1 && { echo "$c"; return 0; }
  done
  return 1
}

# 공유 저장소가 '다 내려온' 상태인가 — SessionEnd 자동 커밋 · 푸시 앞단(install_hook_guard.sh 가 끼운다).
#   ① .git 아래 클라우드 전용(아직 안 내려온) 파일 0  ② .git 최상위 · refs 의 OneDrive 충돌 사본 0
#   ③ 작업 트리에서 사라진 추적 파일 ≤ QVEST_SETTLE_MAX_DELETED(기본 200 — 동기화 중이면 수천 개)
#   ④ 기계별 보류 표식 .cache/machine/hold_<HOST> 없음 — 이전 · 복구 중인 기계를 사람이 명시로 묶어 둔다
#      (2026-11-01 메인 PC: 노트북이 10-20 수정분을 다 올리기 전까지. 2_main.ps1 이 대조 뒤 지운다)
_settled() {
  local proj="${1:-$ROOT}" gd gdw py out names ndel max="${QVEST_SETTLE_MAX_DELETED:-200}" h
  if [ "${QVEST_SETTLE_CHECK:-1}" = "0" ]; then echo "SETTLED check=off"; return 0; fi
  gd="$(git -C "$proj" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    || { echo "UNSETTLED reason=git_dir_unresolved"; return 1; }
  for h in "$MDIR/hold_${HOSTU}" "$(dirname "$gd")/.cache/machine/hold_${HOSTU}"; do
    if [ -f "$h" ]; then echo "UNSETTLED reason=hold($(tr -d '\r' < "$h" | head -1 | tr ' ' '_'))"; return 1; fi
  done
  gdw="$(cygpath -w "$gd" 2>/dev/null || echo "$gd")"
  py="$(_python)" || { echo "UNSETTLED reason=no_python"; return 1; }
  names="$( { _conf | awk '$1=="machine"{print $2}'; echo "$HOSTU"; } | paste -sd, -)"
  out="$(PYTHONUTF8=1 "$py" - "$gdw" "$names" "${QVEST_SETTLE_ATTR_MASK:-0x441000}" <<'PY'
import os, re, sys
gd, names, mask = sys.argv[1], [n for n in sys.argv[2].split(',') if n], int(sys.argv[3], 0)
cloud, first = 0, ''
stack = [gd]
while stack:
    d = stack.pop()
    try:
        it = os.scandir(d)
    except OSError:
        continue
    with it:
        for e in it:
            try:
                if e.is_dir(follow_symlinks=False):
                    stack.append(e.path)
                    continue
                a = e.stat(follow_symlinks=False).st_file_attributes
            except (OSError, AttributeError):
                continue
            if a & mask:
                cloud += 1
                first = first or os.path.relpath(e.path, gd)
conf = []
if names:
    pat = re.compile(r'^(.*)-(?:%s)(?:-\d+)?(\.[^.]*)?$' % '|'.join(re.escape(n) for n in names), re.I)
    def scan(d, rec):
        if not os.path.isdir(d):
            return
        walk = os.walk(d) if rec else [(d, None, [f for f in os.listdir(d) if os.path.isfile(os.path.join(d, f))])]
        for dp, _, fns in walk:
            have = set(fns)
            for f in fns:
                m = pat.match(f)
                if m and (m.group(1) + (m.group(2) or '')) in have:
                    conf.append(os.path.relpath(os.path.join(dp, f), gd))
    scan(gd, False)
    scan(os.path.join(gd, 'refs'), True)
clean = lambda s: (s or '-').replace(' ', '_').replace('\\', '/')
print('cloud=%d conflicts=%d first_cloud=%s first_conflict=%s' % (cloud, len(conf), clean(first), clean(conf[0] if conf else '')))
sys.exit(0 if cloud == 0 and not conf else 3)
PY
)" || { echo "UNSETTLED ${out:-reason=scan_failed}"; return 1; }
  ndel="$(git -C "$proj" ls-files --deleted 2>/dev/null | head -n $(( max + 1 )) | wc -l)"
  if [ "$ndel" -gt "$max" ]; then echo "UNSETTLED $out deleted>${max}"; return 1; fi
  echo "SETTLED $out deleted=$ndel"; return 0
}

_status() {
  local age
  echo "host=$HOSTU role=$(_role) root=$ROOT"
  if [ -f "$MDIR/heartbeat_main.txt" ]; then
    age="$(_hb_age)"
    echo "main heartbeat: host=$(_hb_field host) age=${age}s $( [ -n "$age" ] && [ "$age" -le "$STALE_SEC" ] && echo alive || echo stale) jobs=$(_hb_field jobs)"
  else
    echo "main heartbeat: none"
  fi
  echo "recent runs:"; ls -t "$MDIR/runs" 2>/dev/null | head -8 | sed 's/^/  /'
  echo "settled: $(_settled "$ROOT")"
}

cmd="${1:-status}"; [ $# -gt 0 ] && shift
case "$cmd" in
  role)      _role ;;
  status)    _status ;;
  heartbeat) _heartbeat ;;
  gate)      _gate "$@" ;;
  done)      _done "$@" ;;
  settled)   _settled "$@" ;;
  *) echo "usage: qvest_machine.sh role|status|heartbeat|gate <job> <period>|done <job> <period> <rc>|settled [project]" >&2; exit 2 ;;
esac
