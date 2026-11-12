#!/usr/bin/env bash
# P1S02 시드(E2 · E3 = 2002.06975 DNN · torch) 측정 감시 셸 — 판 2 첫 측정(2026-11-11 작성 · 11-12 개정: 판단 T1 C-20261111-086 · 점검 v1 S-6)
#   코어 v3 의 측정(rc_standing_measure_item)은 GPU 관문(레인 측정 0 + 임대)을 스스로 지난다 — 임대는 코어 관문이 측정 때 잡고 측정이 끝나면 놓는다.
#   이 셸은 **임대를 미리 쥐지 않는다**(창을 기다리는 동안 레인 GPU 슬롯을 세우지 않는다 · 옛 판은 레인 측정 0 이 되자마자 임대를 쥐고 창을 기다렸다).
#   순서 = W(측정 창) → L(레인 측정 0) → M(측정):
#   W: 측정 창 — 낮 창 시작 08:20~11:45(측정 E2 + E3 약 6시간 가정 → 17:45 전 종료) · 밤/아침 체인 미실행 · 배리어 free · 지문 20분 안정 · 가용 메모리 ≥ 16 GB
#      (신선도는 코어가 측정 직전에 본다). 이른 창(02:30~)은 없앴다 — 밤 체인(00:03~약 06:00)과 아침 체인(07:10) 사이에 6시간 창이 없다.
#   L: 창이 열려 있는 동안 레인 GPU 슬롯 측정 0 을 본다(임대 요청 없음). 둘 다 서면 M.
#   M: measure-item E2 → (E2 ok · 지문 동일이면) E3 용 임대를 곧바로 한 번 선점(관문이 쓸 것과 같은 보유자 이름 — 관문 요청은 already_held 로 통과)
#      → measure-item E3 → standing-status. 코어가 'GPU · 신선도 건너뜀'(원장 무기록)으로 돌려주면 W 로 돌아가 다시 기다린다.
#      **판정 · 발송은 하지 않는다**(판정 전 점검 10항목을 세션이 본 뒤 judge — DESIGN.md §5).
#   종료: 0 = M 끝 · 3 = E2 측정 실패(E3 생략) · 6 = 대기 상한 · 2 = 준비 실패. 어느 종료든 trap 이 두 보유자 이름의 임대를 놓는다(쥔 것이 없으면 무동작).
#   이 셸이 죽으면 선점한 임대는 보유자 pid 사망으로 풀린다(레인 재개 = 안전 쪽). 본문을 main() 안에 둔다 — 실행 중 파일이 바뀌어도 읽은 정의로 돈다.
#   띄우는 때: 창 직전이 아니어도 된다(임대를 쥐지 않으므로 기다리는 동안 레인을 막지 않는다).
main() {
  set -u
  local ROOTP=/c/Users/99922/OneDrive/Quant_Module_Moltbot
  cd "$ROOTP" || exit 2
  PY="${QVEST_PY:-}"; [ -x "$PY" ] || PY="/c/Users/99922/AppData/Local/Programs/Python/Python315/python.exe"
  BOARD=04_Research/programs/P1_RETURN/P1S02_standing_qualification
  RS=04_Research/programs/_lib/round_core/round.sh
  FPS=04_Research/programs/_lib/round_core/v3/fingerprint.sh
  CLAIM=.cache/rf_replication.claim.gpu1
  H_E2="rc_standing:P1S02:P1S02_E2_C0"      # 코어 관문이 쓰는 보유자 이름(standing.R: sprintf("rc_standing:%s:%s", 판 꼬리표, code))
  H_E3="rc_standing:P1S02:P1S02_E3_RX0"
  PURPOSE="P1S02 상설 판 2 첫 측정 — 시드 E2 · E3(2002.06975 DNN · torch) · 감시 셸"
  TS=$(date +%Y%m%d_%H%M%S)
  LOG=.cache/scheduler_logs/p1s02_seed_watch_${TS}.log
  STATE=.cache/scheduler_logs/p1s02_seed_watch_state.txt
  WINPID=$(cat /proc/$$/winpid 2>/dev/null)
  DAY_A=${P1S02_DAY_A:-500};     DAY_Z=${P1S02_DAY_Z:-705}          # 낮 창 시작 허용(분) 08:20~11:45 — 측정 약 6시간 가정(판 1 추정 J-017 · 5~6시간) → 17:45 전 종료
  FP_STABLE_S=${P1S02_FP_STABLE_S:-1200}
  # 가용 메모리 하한 16 GB 의 근거: 물리 31.8 GB − 레인 측정 실측 12.7 GB − 기저 사용 약 3 GB ≈ 16 GB.
  #   즉 '레인급 작업이 지금 돌고 있지 않다'는 표지다(DNN 칸 지속 25~33 GB 를 보장하는 문턱이 아니다 — 그 겹침은 레인 측정 0 조건이 막는다).
  #   근거 = 기억 카드 main-pc-commit-limit(11-11 실측: 레인 12.7 GB + R 작업 8.7 GB · 물리 31.8 GB).
  MEM_MIN_GB=${P1S02_MEM_MIN_GB:-16}
  MAX_WAIT_S=${P1S02_MAX_WAIT_S:-172800}
  T0=$(date +%s)
  case "$WINPID" in ''|*[!0-9]*) echo "winpid 판독 불가" >&2; exit 2 ;; esac
  [ -f "$BOARD/round_spec.json" ] || { echo "판 2 사양 없음: $BOARD" >&2; exit 2; }
  if [ "${P1S02_SELFTEST:-0}" = "1" ]; then   # 도우미 한 번씩 · 임대 · 측정 없음
    LOG=/dev/stdout
    echo "winpid=$WINPID · lane_dir_busy=$(lane_dir_busy && echo 1 || echo 0) · lane_status=$(lane_status) · lease=$(lease_now)"
    echo "DailyRefresh running=$(task_running Qvest_DailyRefresh && echo 1 || echo 0) · MorningBrief running=$(task_running Qvest_MorningBrief && echo 1 || echo 0)"
    echo "barrier_free=$(barrier_free && echo 1 || echo 0) · mem_gb=$(mem_gb) · fp=$(bash "$FPS" equality 2>/dev/null | md5sum | cut -c1-12) · nowm=$((10#$(date +%H) * 60 + 10#$(date +%M))) · 낮 창 ${DAY_A}~${DAY_Z}분"
    exit 0
  fi
  trap 'on_exit' EXIT
  log "시작 · msys pid $$ · winpid $WINPID · 낮 창 ${DAY_A}~${DAY_Z}분 · 지문 안정 ${FP_STABLE_S}s · 메모리 ≥ ${MEM_MIN_GB}GB · 임대 미리 안 쥠"

  # ── M: 측정(판정 · 발송 없음) ────────────────────────────────────────────────────
  local rc_e2 rc_e3=-1 e2ok exitc=0
  rc_e2=$(measure_until_done P1S02_E2_C0) || exit $?
  try_acquire "$H_E3" || log "M: E3 임대 선점 실패 — 관문이 스스로 잡는다(레인이 먼저 잡았으면 gpu_wait → 다시 기다린다)"
  e2ok=$(grep -F "측정 P1S02_E2_C0 ok=TRUE" "$LOG" | grep -cF "지문 동일=TRUE")
  if [ "$e2ok" -ge 1 ]; then
    rc_e3=$(measure_until_done P1S02_E3_RX0) || exit $?
  else
    log "M: E2 측정이 ok · 지문 동일이 아니다(rc=$rc_e2) — E3 생략(같은 기저 · 같은 경로) · 세션이 본다"; exitc=3
  fi
  run standing-status
  log "M: 끝 — E2 rc=$rc_e2 · E3 rc=$rc_e3 · 판정 전 점검 → judge → 보고는 세션 몫"
  st "끝(측정만) — E2 rc=$rc_e2 · E3 rc=$rc_e3"
  exit $exitc
}

# W → L 을 지난 뒤 measure-item 한 번 · 코어가 GPU · 신선도로 건너뛰면(원장 무기록) 다시 W → L. 표준 출력 = measure-item rc
measure_until_done() {
  local code=$1 n0 n1 rc
  while :; do
    wait_window_and_lane "$code" || return 6
    st "M 측정 중 — $code"
    n0=$(grep -cF "측정 $code 건너뜀" "$LOG" 2>/dev/null); n0=${n0:-0}
    run measure-item "$code"; rc=$?
    n1=$(grep -cF "측정 $code 건너뜀" "$LOG" 2>/dev/null); n1=${n1:-0}
    if [ "$n1" -gt "$n0" ]; then log "M: $code 측정 건너뜀(코어 관문 — GPU · 신선도) — 다시 기다린다"; sleep 60; continue; fi
    echo "$rc"; return 0
  done
}

# W: 측정 창 · L: 레인 측정 0 — 둘 다 서면 0 · 대기 상한이면 1(임대를 잡지 않는다)
wait_window_and_lane() {
  local code=$1 now fp_last="" fp_since last_why=0 why fp nowm mg ls
  fp_since=$(date +%s)
  st "W 측정 창 · 레인 측정 0 대기 — $code(임대 없음)"
  while :; do
    now=$(date +%s)
    [ $((now - T0)) -gt "$MAX_WAIT_S" ] && { log "W: 대기 상한 초과"; return 1; }
    fp=$(bash "$FPS" equality 2>/dev/null | md5sum | cut -c1-32)
    if [ "$fp" != "$fp_last" ]; then [ -n "$fp_last" ] && log "W: 데이터 지문 변경 ${fp_last:0:8} → ${fp:0:8}"; fp_last=$fp; fp_since=$now; fi
    why=""
    nowm=$((10#$(date +%H) * 60 + 10#$(date +%M)))
    if ! { [ "$nowm" -ge "$DAY_A" ] && [ "$nowm" -le "$DAY_Z" ]; }; then why="시각 창 밖(${nowm}분)"; fi
    if [ -z "$why" ]; then task_running Qvest_DailyRefresh && why="밤 체인 실행 중"; fi
    if [ -z "$why" ]; then task_running Qvest_MorningBrief && why="아침 체인 실행 중"; fi
    if [ -z "$why" ]; then barrier_free || why="리프레시 배리어 held"; fi
    if [ -z "$why" ] && [ $((now - fp_since)) -lt "$FP_STABLE_S" ]; then why="지문 안정 $((now - fp_since))s < ${FP_STABLE_S}s"; fi
    if [ -z "$why" ]; then mg=$(mem_gb); { [ -n "$mg" ] && [ "$mg" -ge "$MEM_MIN_GB" ]; } 2>/dev/null || why="가용 메모리 ${mg:-?}GB < ${MEM_MIN_GB}GB"; fi
    if [ -z "$why" ]; then
      if lane_dir_busy; then why="레인 GPU 슬롯 claim 디렉터리 있음"
      else ls=$(lane_status); { [ "$ls" = "live" ] || [ "$ls" = "unreadable" ]; } && why="레인 측정 status=$ls"; fi
    fi
    if [ -z "$why" ]; then log "W · L: 창 열림 · 레인 측정 0 — $code 측정 · 가용 메모리 ${mg}GB · 지문 ${fp:0:8}"; return 0; fi
    if [ $((now - last_why)) -ge 600 ]; then log "W: 대기($code) — $why"; st "W 대기($code) — $why"; last_why=$now; fi
    sleep 60
  done
}

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
st()  { printf '%s\t%s\tlog=%s\n' "$(date '+%F %T')" "$*" "$LOG" > "$STATE"; }
lane_dir_busy() {   # 0 = 레인 GPU 슬롯 claim 디렉터리 있음 또는 연쇄 표식이 10분 안
  [ -d "$CLAIM" ] && return 0
  if [ -e "$CLAIM.chain" ]; then
    local a=$(( $(date +%s) - $(stat -c %Y "$CLAIM.chain" 2>/dev/null || echo 0) ))
    [ "$a" -lt 600 ] && return 0
  fi
  return 1
}
lane_status() {     # 살아 있는 레인 claim 이 하나라도 있으면 live(코어 관문과 같은 기준 — 슬롯 전부 + legacy)
  timeout 90 "$PY" -X utf8 02_Infrastructure/ops/rf_replication_slots.py status --json 2>/dev/null | "$PY" -X utf8 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    live = [x for x in d.get('slots', []) if x.get('claim') == 'live']
    if (d.get('legacy') or {}).get('claim') == 'live': live.append(1)
    print('live' if live else 'free')
except Exception:
    print('unreadable')"
}
lease_now() {       # 출력: state holder expires_epoch
  timeout 90 "$PY" -X utf8 02_Infrastructure/ops/qv_lock.py lease status --json 2>/dev/null | "$PY" -X utf8 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read().strip().splitlines()[-1])
    print('%s %s %d' % (d.get('state') or 'none', d.get('holder') or '-', int(float(d.get('expires_epoch') or 0))))
except Exception:
    print('unreadable - 0')"
}
try_acquire() {     # $1 = 보유자 이름(E2 끝난 직후 E3 용 선점 한 번에만 쓴다)
  local out res ls2 lh2 le2
  out=$(timeout 120 "$PY" -X utf8 02_Infrastructure/ops/qv_lock.py lease acquire --holder "$1" --purpose "$PURPOSE" --holder-pid "$WINPID" --json 2>>"$LOG" | tr -d '\r')
  log "임대 요청($1) → $(printf '%s' "$out" | tail -n 1 | cut -c1-400)"
  res=$(printf '%s' "$out" | "$PY" -X utf8 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read().strip().splitlines()[-1]); print('%s %s' % (d.get('ok'), d.get('reason')))
except Exception:
    print('False unreadable')")
  case "$res" in
    "True acquired"|"True already_held")
      read -r ls2 lh2 le2 <<< "$(lease_now)"
      if [ "$ls2" = "held" ] && [ "$lh2" = "$1" ]; then log "임대 보유 확인($1) · 만료 $(date -d @"$le2" '+%F %T')"; return 0; fi
      log "임대를 잡았다는데 상태가 $ls2/$lh2"; return 1 ;;
    *) log "임대 실패($res)"; return 1 ;;
  esac
}
task_running() {
  local s; s=$(timeout 90 powershell.exe -NoProfile -NonInteractive -Command "(Get-ScheduledTask -TaskName '$1').State" 2>/dev/null | tr -d '\r\n ')
  [ "$s" = "Running" ]
}
barrier_free() { bash 02_Infrastructure/ops/refresh_barrier.sh status 2>/dev/null | grep -q "state=free"; }
mem_gb() { timeout 90 powershell.exe -NoProfile -NonInteractive -Command "[math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB)" 2>/dev/null | tr -d '\r\n '; }
run() { log "M: round.sh <판> $*"; bash "$RS" "$BOARD" "$@" >> "$LOG" 2>&1; local rc=$?; log "M: rc=$rc ($*)"; return $rc; }
on_exit() {
  local rc=$? h out
  for h in "$H_E2" "$H_E3"; do
    out=$(timeout 120 "$PY" -X utf8 02_Infrastructure/ops/qv_lock.py lease release --holder "$h" --json 2>&1 | tr -d '\r' | tail -n 1)
    log "종료 rc=$rc · 임대 놓기($h) → $(printf '%s' "$out" | cut -c1-200)"
  done
}

main "$@"
exit $?
