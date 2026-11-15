#!/usr/bin/env bash
# P1S04(레인 갈래 판 3 · 코어 v4) 시드 측정 감시 셸 — 판 2 tools/p1s02_seed_watch.sh 를 판 3 경로 · 코어 v4 로 옮김(11-15 · 격리 점검 v1 R-3)
#   바뀐 것: 판 경로 · 보유자 이름(rc_standing:P1S04:…) · 지문 = v4 fingerprint.sh(결합용 뷰 줄 포함) · PYTHON_CPU_COUNT=4(도훈 결정 — DNN 워커 3 ·
#   engine.R 의 os.cpu_count() 를 Python 3.13+ 가 이 값으로 읽는다) · 낮 창 시작 상한 10:00(워커 3 · 측정 시간 미실측 → 밤 체인 22:48 전 12시간 남김 —
#   첫 측정 실측 뒤 다시 잡는다) · 환경 변수 접두어 P1S04_. 나머지 순서 · 조건(W → L → M · 임대 미리 안 쥠 · E3 follow · 판정 · 발송 없음)은 판 2 그대로(아래 원문).
# P1S04 시드(E2 · E3 = 2002.06975 DNN · torch) 측정 감시 셸 — 판 2 첫 측정(2026-11-11 작성 · 11-12 개정: 판단 T1 C-20261111-086 · 점검 v1 S-6)
#   코어 v3 · v4 의 측정(rc_standing_measure_item)은 GPU 관문(레인 측정 0 + 임대)을 스스로 지난다 — 임대는 코어 관문이 측정 때 잡고 측정이 끝나면 놓는다.
#   이 셸은 **임대를 미리 쥐지 않는다**(창을 기다리는 동안 레인 GPU 슬롯을 세우지 않는다 · 옛 판은 레인 측정 0 이 되자마자 임대를 쥐고 창을 기다렸다).
#   순서 = W(측정 창) → L(레인 측정 0) → M(측정):
#   W: 측정 창 — 낮 창 시작 08:20~11:45(측정 E2 + E3 약 6시간 가정 → 17:45 전 종료) · 밤/아침 체인 미실행 · 배리어 free · 지문 20분 안정 · 메모리 관문 mem_gate.py 통과(11-15 — 아래 MG_KEY 주석)
#      (신선도는 코어가 측정 직전에 본다). 이른 창(02:30~)은 없앴다 — 밤 체인(00:03~약 06:00)과 아침 체인(07:10) 사이에 6시간 창이 없다.
#   L: 창이 열려 있는 동안 레인 GPU 슬롯 측정 0 을 본다(임대 요청 없음). 둘 다 서면 M.
#   M: measure-item E2 → (E2 ok · 지문 동일이면) E3 용 임대를 곧바로 한 번 선점(관문이 쓸 것과 같은 보유자 이름 — 관문 요청은 already_held 로 통과)
#      → E3 는 follow 대기(격리 점검 v2 R-1 · 11-12): 시각 창 · 지문 안정 대기 없이 체인 · 배리어 · 메모리 · 레인 조건만 보고, 지문이 E2 측정
#      시작 때와 같을 때 곧바로 잰다(같은 창 · 같은 자료 판 · 기저 캐시 공유). 지문이 달라졌으면 선점 임대를 놓고 보통 대기(W)로 돌아간다.
#      E2 가 실패하면 선점하지 않는다. → measure-item E3 → standing-status. 코어가 'GPU · 신선도 건너뜀'(원장 무기록)으로 돌려주면 W 로 돌아가 다시 기다린다.
#      **판정 · 발송은 하지 않는다**(판정 전 점검 10항목을 세션이 본 뒤 judge — DESIGN.md §5).
#   종료: 0 = M 끝 · 3 = E2 측정 실패(E3 생략) · 6 = 대기 상한 · 7 = 측정 직전 precheck 실패(핀 불일치 — 판 3 추가) · 2 = 준비 실패. 어느 종료든 trap 이 두 보유자 이름의 임대를 놓는다(쥔 것이 없으면 무동작).
#   이 셸이 죽으면 선점한 임대는 보유자 pid 사망으로 풀린다(레인 재개 = 안전 쪽). 본문을 main() 안에 둔다 — 실행 중 파일이 바뀌어도 읽은 정의로 돈다.
#   띄우는 때: 창 직전이 아니어도 된다(임대를 쥐지 않으므로 기다리는 동안 레인을 막지 않는다).
main() {
  set -u
  local ROOTP=/c/Users/99922/OneDrive/Quant_Module_Moltbot
  cd "$ROOTP" || exit 2
  export PYTHON_CPU_COUNT=${PYTHON_CPU_COUNT:-4}   # 도훈 결정 P1S02-EDITION3-REGISTER-LATER-20261114 — DNN 워커 3(engine.R: ncpu = os.cpu_count())
  PY="${QVEST_PY:-}"; [ -x "$PY" ] || PY="/c/Users/99922/AppData/Local/Programs/Python/Python315/python.exe"
  BOARD=04_Research/programs/P1_RETURN/P1S04_standing_qualification
  RS=04_Research/programs/_lib/round_core/round.sh
  FPS=04_Research/programs/_lib/round_core/v4/fingerprint.sh
  CLAIM=.cache/rf_replication.claim.gpu1
  H_E2="rc_standing:P1S04:P1S04_E2_C0"      # 코어 관문이 쓰는 보유자 이름(standing.R: sprintf("rc_standing:%s:%s", 판 꼬리표, code))
  H_E3="rc_standing:P1S04:P1S04_E3_RX0"
  PURPOSE="P1S04 상설 판 3 첫 측정 — 시드 E2 · E3(2002.06975 DNN · torch) · 감시 셸"
  TS=$(date +%Y%m%d_%H%M%S)
  LOG=.cache/scheduler_logs/p1s04_seed_watch_${TS}.log
  STATE=.cache/scheduler_logs/p1s04_seed_watch_state.txt
  FP_E2=.cache/scheduler_logs/p1s04_seed_watch_fp_e2.txt   # E2 측정 시작 때의 데이터 지문(E3 follow 대조 · 점검 v2 R-1)
  WINPID=$(cat /proc/$$/winpid 2>/dev/null)
  DAY_A=${P1S04_DAY_A:-500};     DAY_Z=${P1S04_DAY_Z:-600}   # 판 3: 시작 상한 10:00(워커 3 · 측정 시간 미실측 — 밤 체인 22:48 전 12시간 남김)          # 낮 창 시작 허용(분) 08:20~11:45 — 측정 약 6시간 가정(판 1 추정 J-017 · 5~6시간) → 17:45 전 종료
  FP_STABLE_S=${P1S04_FP_STABLE_S:-1200}
  # 메모리 관문(11-15 도훈 MEMORY-USE-90PCT · MEMORY-PEAK-BACKCALC · MEMORY-GATE-LANE-TICKS — 원 세션 요청으로 mem_gate.py 배선):
  #   판정 = 02_Infrastructure/ops/mem_gate.py <키>(단일 출처 · rc 0 통과 · 1 대기 · 2 판독 불가 — 0 이 아니면 띄우지 않는다): 가용 − 예상 정점 ≥ reserve_gb
  #   ∧ 먼저 뜬 무거운 작업 표지(레인 검증기 · 셀 워커 · DNN 학습) 없음. 키 = E2 · E3 보통 대기 dnn_seed_cell(12.8 GB · 성공 출발 역산)
  #   · E3 follow standing_cell(7.9 GB · E2 기저 캐시 적중 셀 워커) — 값 · 출처 정본 = 06_Registry/memory_policy.json peaks(11-15 실측: 순간 15.3 · 지속 11.5).
  #   E3 보통 대기는 지문이 E2 때와 달라져 기저 캐시 키가 갈리므로 DNN 을 다시 돈다 → DNN 키. 구 고정 16 GB · 정책 식 직접 계산 · 정점 환경 변수는 폐기.
  MG_KEY_DNN=dnn_seed_cell; MG_KEY_E3F=standing_cell
  MAX_WAIT_S=${P1S04_MAX_WAIT_S:-172800}
  T0=$(date +%s)
  case "$WINPID" in ''|*[!0-9]*) echo "winpid 판독 불가" >&2; exit 2 ;; esac
  [ -f "$BOARD/prereg.json" ] || { echo "판 3 등록본 없음(등록 전에는 띄우지 않는다): $BOARD" >&2; exit 2; }
  local mgo0 mgrc0; mgo0=$(mem_gate "$MG_KEY_DNN"); mgrc0=$?   # 판독 불가(정책 · 키 · 파이썬 · 프로세스 목록)는 기다리지 않고 바로 끝낸다
  [ "$mgrc0" = "2" ] && { echo "메모리 관문 판독 불가 — 띄우지 않는다: $mgo0" >&2; exit 2; }
  if [ "${P1S04_SELFTEST:-0}" = "1" ]; then   # 도우미 한 번씩 · 임대 · 측정 없음
    LOG=/dev/stdout
    echo "winpid=$WINPID · lane_dir_busy=$(lane_dir_busy && echo 1 || echo 0) · lane_status=$(lane_status) · lease=$(lease_now)"
    echo "DailyRefresh running=$(task_running Qvest_DailyRefresh && echo 1 || echo 0) · MorningBrief running=$(task_running Qvest_MorningBrief && echo 1 || echo 0)"
    echo "barrier_free=$(barrier_free && echo 1 || echo 0) · fp=$(bash "$FPS" equality 2>/dev/null | md5sum | cut -c1-12) · nowm=$((10#$(date +%H) * 60 + 10#$(date +%M))) · 낮 창 ${DAY_A}~${DAY_Z}분"
    local sc sm src
    for sc in "P1S04_E2_C0 normal" "P1S04_E3_RX0 follow" "P1S04_E3_RX0 normal"; do
      read -r sc sm <<< "$sc"
      mem_ok "$sc" "$sm"; src=$?
      echo "메모리 관문 $sc($sm) rc=$src · 키 $mgk — $mgo"
    done
    exit 0
  fi
  trap 'on_exit' EXIT
  log "시작 · msys pid $$ · winpid $WINPID · 낮 창 ${DAY_A}~${DAY_Z}분 · 지문 안정 ${FP_STABLE_S}s · 메모리 관문 = mem_gate.py(E2 · E3 보통 ${MG_KEY_DNN} · E3 follow ${MG_KEY_E3F} · 정본 memory_policy.json peaks · 파이썬 ${MG_PY:-없음}) · 임대 미리 안 쥠"
  local ev; for ev in P1S04_MEM_MIN_GB P1S04_PEAK_GB_DNN P1S04_PEAK_GB_E3F P1S04_MEM_POLICY; do
    [ -n "${!ev:-}" ] && log "${ev}=${!ev} 는 11-15 폐기(메모리 관문 mem_gate.py · 정점 = 정책 파일 peaks) — 무시"; done

  # ── M: 측정(판정 · 발송 없음) ────────────────────────────────────────────────────
  local rc_e2 rc_e3=-1 e2ok exitc=0
  rc_e2=$(measure_until_done P1S04_E2_C0 normal) || exit $?
  e2ok=$(grep -F "측정 P1S04_E2_C0 ok=TRUE" "$LOG" | grep -cF "지문 동일=TRUE")
  if [ "$e2ok" -ge 1 ]; then
    # (격리 점검 v2 R-1 · 11-12) E3 는 E2 와 같은 창 · 같은 자료 판에서 곧바로 잰다 — 시각 창 · 지문 안정 대기를 다시 하지 않는다
    #   (체인 · 배리어 · 메모리 · 레인 조건은 그대로 · 지문은 E2 측정 시작 때와 같아야 한다 — 다르면 임대를 놓고 보통 대기로 돌아간다).
    #   선점은 E2 성공 뒤에만 한다(E2 실패면 쥐지 않는다).
    try_acquire "$H_E3" || log "M: E3 임대 선점 실패 — 관문이 스스로 잡는다(레인이 먼저 잡았으면 gpu_wait → 다시 기다린다)"
    rc_e3=$(measure_until_done P1S04_E3_RX0 follow) || exit $?
  else
    log "M: E2 측정이 ok · 지문 동일이 아니다(rc=$rc_e2) — E3 생략(같은 기저 · 같은 경로) · 임대 선점 안 함 · 세션이 본다"; exitc=3
  fi
  run standing-status
  log "M: 끝 — E2 rc=$rc_e2 · E3 rc=$rc_e3 · 판정 전 점검 → judge → 보고는 세션 몫"
  st "끝(측정만) — E2 rc=$rc_e2 · E3 rc=$rc_e3"
  exit $exitc
}

# W → L 을 지난 뒤 measure-item 한 번 · 코어가 GPU · 신선도로 건너뛰면(원장 무기록) 다시 W → L. 표준 출력 = measure-item rc
measure_until_done() {   # $2 = normal | follow(E3 — E2 와 같은 창 · 같은 자료 판)
  local code=$1 mode=${2:-normal} n0 n1 rc
  while :; do
    wait_window_and_lane "$code" "$mode" || return 6
    mode=normal                                     # 건너뜀(코어 관문) 뒤 다시 기다릴 때는 보통 대기
    st "M 측정 중 — $code"
    # 판단 T1 C-20261115-058: 측정(코어가 GPU 임대를 잡는다) 직전에 핀 불일치 0 을 확인 — 판 2 는 등록 뒤 핀 갈림으로 멈췄다(상설 판 재핀 경로 없음)
    if ! bash "$RS" "$BOARD" precheck >> "$LOG" 2>&1; then log "M: precheck 실패(핀 불일치 등) — $code 측정하지 않는다(판단 C-20261115-058)"; st "끝 — precheck 실패(측정 안 함)"; return 7; fi
    n0=$(grep -cF "측정 $code 건너뜀" "$LOG" 2>/dev/null); n0=${n0:-0}
    run measure-item "$code"; rc=$?
    n1=$(grep -cF "측정 $code 건너뜀" "$LOG" 2>/dev/null); n1=${n1:-0}
    if [ "$n1" -gt "$n0" ]; then log "M: $code 측정 건너뜀(코어 관문 — GPU · 신선도) — 다시 기다린다"; sleep 60; continue; fi
    echo "$rc"; return 0
  done
}

# W: 측정 창 · L: 레인 측정 0 — 둘 다 서면 0 · 대기 상한이면 1(임대를 잡지 않는다)
wait_window_and_lane() {   # $2 = normal | follow — follow 면 시각 창 · 지문 안정 대기를 건너뛰되 지문 = E2 측정 시작 때여야 한다
  local code=$1 mode=${2:-normal} now fp_last="" fp_since last_why=0 why fp nowm mgo="" mgk ls fpe2
  fp_since=$(date +%s)
  if [ "$mode" = "follow" ]; then
    fpe2=$(cat "$FP_E2" 2>/dev/null)
    st "W(follow) E2 직후 — $code(시각 창 · 지문 안정 대기 없음 · 지문 = E2 때 · 체인 · 배리어 · 메모리 · 레인 조건만)"
  else
    st "W 측정 창 · 레인 측정 0 대기 — $code(임대 없음)"
  fi
  while :; do
    now=$(date +%s)
    [ $((now - T0)) -gt "$MAX_WAIT_S" ] && { log "W: 대기 상한 초과"; return 1; }
    fp=$(bash "$FPS" equality 2>/dev/null | md5sum | cut -c1-32)
    if [ "$fp" != "$fp_last" ]; then [ -n "$fp_last" ] && log "W: 데이터 지문 변경 ${fp_last:0:8} → ${fp:0:8}"; fp_last=$fp; fp_since=$now; fi
    if [ "$mode" = "follow" ] && [ "$fp" != "$fpe2" ]; then
      log "W(follow): 지문이 E2 측정 시작 때(${fpe2:0:8})와 다르다(${fp:0:8}) — E3 는 다른 자료 판이 된다 · 선점 임대를 놓고 보통 대기로 돌아간다"
      release_lease "$H_E3"; mode=normal; fp_since=$now
    fi
    why=""
    nowm=$((10#$(date +%H) * 60 + 10#$(date +%M)))
    if [ "$mode" != "follow" ] && ! { [ "$nowm" -ge "$DAY_A" ] && [ "$nowm" -le "$DAY_Z" ]; }; then why="시각 창 밖(${nowm}분)"; fi
    if [ -z "$why" ]; then task_running Qvest_DailyRefresh && why="밤 체인 실행 중"; fi
    if [ -z "$why" ]; then task_running Qvest_MorningBrief && why="아침 체인 실행 중"; fi
    if [ -z "$why" ]; then barrier_free || why="리프레시 배리어 held"; fi
    if [ -z "$why" ] && [ "$mode" != "follow" ] && [ $((now - fp_since)) -lt "$FP_STABLE_S" ]; then why="지문 안정 $((now - fp_since))s < ${FP_STABLE_S}s"; fi
    if [ -z "$why" ]; then mem_ok "$code" "$mode" || why="메모리 관문(${mgk}) — ${mgo}"; fi
    if [ -z "$why" ]; then
      if lane_dir_busy; then why="레인 GPU 슬롯 claim 디렉터리 있음"
      else ls=$(lane_status); { [ "$ls" = "live" ] || [ "$ls" = "unreadable" ]; } && why="레인 측정 status=$ls"; fi
    fi
    if [ -z "$why" ]; then
      [ "$mode" != "follow" ] && printf '%s\n' "$fp" > "$FP_E2"   # E3 follow 대조용 — E2(첫 측정) 시작 때의 지문
      log "W · L: 창 열림 · 레인 측정 0 — $code 측정($mode) · 메모리 관문(${mgk}) ${mgo} · 지문 ${fp:0:8}"; return 0
    fi
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
release_lease() {   # $1 = 보유자 이름 — follow 대기에서 지문이 E2 때와 달라 보통 대기로 돌아갈 때 선점을 놓는다
  local out; out=$(timeout 120 "$PY" -X utf8 02_Infrastructure/ops/qv_lock.py lease release --holder "$1" --json 2>&1 | tr -d '\r' | tail -n 1)
  log "임대 놓기($1) → $(printf '%s' "$out" | cut -c1-200)"
}
task_running() {
  local s; s=$(timeout 90 powershell.exe -NoProfile -NonInteractive -Command "(Get-ScheduledTask -TaskName '$1').State" 2>/dev/null | tr -d '\r\n ')
  [ "$s" = "Running" ]
}
barrier_free() { bash 02_Infrastructure/ops/refresh_barrier.sh status 2>/dev/null | grep -q "state=free"; }
## 메모리 관문 = mem_gate.py(standing_board_run.sh · chain_tick.sh 와 같은 래퍼) — rc 0 통과 · 1 대기 · 2 판독 불가 · 끄기(시험) = QVEST_MEMGATE=off
##   시험 주입 = mem_gate.py 의 MG_POLICY · MG_AVAIL_MB · MG_PROCS_FILE(환경 변수가 그대로 넘어간다)
MG_PYF=/c/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/ops/mem_gate.py
MG_PY=""; for _c in /c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe "${QVEST_PY:-}" python; do [ -n "$_c" ] && command -v "$_c" >/dev/null 2>&1 && { MG_PY=$_c; break; }; done
mem_gate() { [ "${QVEST_MEMGATE:-on}" = "off" ] && { echo "꺼짐(QVEST_MEMGATE=off)"; return 0; }
  [ -n "$MG_PY" ] || { echo "판독 불가 — 파이썬 없음"; return 2; }
  local o rc; o=$(timeout 150 "$MG_PY" -X utf8 "$MG_PYF" "$1" 2>&1); rc=$?; printf '%s' "$o" | tail -n 1 | tr -d '\r'; return $rc; }
mem_ok() {   # $1 = code · $2 = normal | follow — 키를 골라 mem_gate 를 부른다 · 부르는 쪽 변수 mgk(키) · mgo(판정 한 줄)를 채운다 · rc = mem_gate rc
  case "$1:$2" in P1S04_E3_RX0:follow) mgk=$MG_KEY_E3F ;; *) mgk=$MG_KEY_DNN ;; esac
  mgo=$(mem_gate "$mgk")
}
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
