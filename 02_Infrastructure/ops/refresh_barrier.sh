#!/usr/bin/env bash
#==============================================================================
# refresh_barrier.sh — 리프레시 배리어 **판정기 단일 정본** (도훈 결정 OPS-RUNNER-REFRESH-BARRIER · 2026-09-24)
#
# 왜: daily_refresh.sh 는 [0b] 퀀티 증분(incremental_update_file.R — 창 행 삭제 후 재부착 · 직접 쓰기)부터
#   [3/7] 유니버스 매핑까지 RAWDATA 의 K200/KQ150 이 NA 인 창을 만든다. 강화 셀은 rf_cell_engine.R 에서
#   그 두 열로 유니버스를 자르므로, 창 안에서 RAWDATA 를 읽은 셀은 **에러 없이 틀린 등급**을 낸다.
#   Qvest_DailyRefresh 는 StartWhenAvailable=True 라 창이 00:03 에 고정되지 않는다 — 시각이 아니라 잠금으로 판정한다.
#   daily_refresh.sh 는 무변경(결정 조건). 러너 쪽이 그 잠금을 읽는다.
#
# 무엇을 보나 (둘 중 하나라도 held 면 held):
#   ① 리프레시 잠금  ${QM_REFRESH_LOCKDIR:-/tmp/qm_daily_refresh.lock}   ← daily_refresh.sh:24 와 같은 문자열
#   ② RAWDATA writer 잠금 ${QM_RAWDATA_WRITER_LOCKDIR:-/tmp/qm_rawdata_writer.lock}
#      — 잠금 없이 RAWDATA 를 쓰던 아침 체인 writer(morning_briefing.sh 의 krx_update·naver_supplement·self_heal)가
#        rb_writer_acquire/rb_writer_release 로 쥔다. 보유자마다 pid.<MSYS pid> 파일 1개(동시 보유 허용).
#   (QM_* 두 변수는 **검사 주입 전용**이다 — 운영은 기본값.)
#
# held 판정 = 잠금 존재 ∧ 보유 프로세스 생존. 직전 검증에서 실측된 함정 4종을 여기서 한 번에 닫는다:
#   ① "/tmp" 는 층마다 다르다 — R 의 "/tmp" 는 C:\tmp, Git Bash 의 /tmp 는 %TEMP%. 그래서 판정은 **bash 가** 한다
#      (R 은 refresh_barrier.R 이 이 파일을 부른다). paths 명령이 bash 가 본 윈도 경로를 내 패리티를 잰다.
#   ② 잠금 pid 는 MSYS pid 다 — R 의 Sys.getpid()/tasklist 와 공간이 다르다. kill -0 + /proc/<pid> 로 판정하고,
#      MSYS 표에 죽은 항목이 남는 경우(2026-09-05 실측: 죽은 owner 에 kill -0 TRUE)는 /proc/<pid>/winpid 를
#      ps -W(윈도 프로세스 표)로 한 번 더 본다.
#   ③ mkdir 과 pid 기록 사이에는 pid 파일이 빈 창이 있다 — 빈 pid = **보유 중**으로 보고 짧은 유예 뒤 재판정한다.
#      유예 뒤에도 비어 있으면: pid 파일(없으면 잠금 디렉터리) 나이 ≤ RB_EMPTY_HELD_MAX_S(600s) 동안 held,
#      넘으면 stale(쓰기 사이 창은 마이크로초라 10분 빈 pid 는 보유가 아니라 파손이다).
#   ④ 재부팅 뒤 pid 재사용 — pid 파일 mtime 이 부팅 시각보다 이전이면 stale(pre_boot). 같은 부팅 안의 재사용은
#      프로세스 시작 시각(/proc/<pid> mtime)이 pid 파일 mtime 보다 늦으면 stale(pid_reused) — 보유자는 시작 **후에** 쓴다.
#      ★디렉터리가 아니라 **pid 파일** mtime 을 쓴다: daily_refresh 의 stale 인계는 mkdir 없이 pid 만 덮어쓰므로
#        디렉터리 mtime 은 옛 부팅의 것일 수 있다(그걸 쓰면 인계한 살아 있는 리프레시를 stale 로 오판한다).
#   ⑤ (추가) 보유자의 **자손**은 막지 않는다 — daily_refresh.sh 가 잠금을 쥔 채 테스트 배터리(suite_totals_watch
#      --collect → run_all_hooks.sh)와 rf_factor_backfill_tick.R 을 돌린다. 자기 잠금에 자기 자식이 막히면 배터리가
#      빨개지거나 대기로 멈춘다. 판정: 내 MSYS 조상 사슬과 **윈도** 조상 사슬(PowerShell 표 · 생성시각 역전에서 끊음)을
#      번갈아 올라가 보유자(MSYS pid 또는 지금 winpid)를 만나면 state=self(진행) — 한 사슬만으로는 네이티브 경계(Rscript)나
#      Cygwin exec 지점에서 끊긴다(_rb_is_ancestor 주석 · 실측). 조회 실패는 self 가 아니다(fail-closed).
#
# 상태: free(잠금 없음) · held(대기/건너뜀) · stale(대기 안 함 + 로그) · self(보유자 자손 — 진행)
#   rc: 0 = 진행(free/stale/self) · 10 = held
#
# 사용:
#   CLI   bash refresh_barrier.sh status            → "RB<TAB>state=..<TAB>lock=..<TAB>..." 한 줄 · rc 0/10
#         bash refresh_barrier.sh wait <max_s> [poll_s] → held 인 동안 대기 · 마지막 status 줄 + waited_s · rc 0/10
#         bash refresh_barrier.sh paths             → bash 가 보는 두 잠금의 윈도 경로(R 패리티 검사용)
#   source . refresh_barrier.sh; rb_status; echo "$RB_STATE"   (rb_wait · rb_line · rb_jlog 도 같은 방식)
#   writer (source 필수 — 보유자는 호출 셸의 $$):  rb_writer_acquire <tag> … rb_writer_release
#
# ★외부 도구는 /usr/bin 절대경로로 부른다 — source 한 셸의 PATH 를 건드리지 않기 위해서다(잠금 없음 경로 비트 동일).
# ★판정 로직은 이 파일 하나다. R 쪽(refresh_barrier.R)은 부르고 파싱만 한다 — 두 벌이 되면 갈린다.
#==============================================================================

_rb_now()   { /usr/bin/date +%s; }
_rb_mtime() { /usr/bin/stat -c %Y -- "$1" 2>/dev/null; }
_rb_boot()  {
  local b up
  b=$(/usr/bin/awk '$1=="btime"{print $2; exit}' /proc/stat 2>/dev/null)
  if [ -z "$b" ]; then
    up=$(/usr/bin/cut -d' ' -f1 /proc/uptime 2>/dev/null); up=${up%%.*}
    [ -n "$up" ] && b=$(( $(_rb_now) - up ))
  fi
  echo "${b:-0}"
}
# pid 파일 첫 줄 — 숫자만 유효. 비었거나 숫자가 아니면 빈 문자열(= 아직 안 쓰였거나 파손)
_rb_pid_of() {
  local v=""
  [ -f "$1" ] && v=$(/usr/bin/head -n 1 -- "$1" 2>/dev/null | /usr/bin/tr -d '\r\n\t ')
  case "$v" in ''|*[!0-9]*) v="" ;; esac
  echo "$v"
}
_rb_tag_of() { [ -f "$1" ] && /usr/bin/sed -n '2p' -- "$1" 2>/dev/null | /usr/bin/tr -d '\r\n\t ' ; }
# 윈도 pid 생존 — 0 = 있음 · 1 = 없음 · 2 = 판정 불가(판정 불가는 호출자가 '있음'으로 접는다 · 보수)
_rb_win_alive() {
  local wp="$1" out
  out=$(/usr/bin/ps -W 2>/dev/null) || return 2
  [ -n "$out" ] || return 2
  printf '%s\n' "$out" | /usr/bin/awk -v w="$wp" '$4==w || $5==w {f=1} END {exit !f}' && return 0
  return 1
}
# 윈도 프로세스 표 "winpid 부모winpid 생성틱" — 실패하면 빈 출력
_rb_win_table() {
  local ps
  ps=$(command -v powershell.exe 2>/dev/null)
  [ -n "$ps" ] || ps=/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
  [ -x "$ps" ] || return 0
  /usr/bin/timeout "${RB_PS_TIMEOUT_S:-30}" "$ps" -NoProfile -NonInteractive -Command \
    'Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId,CreationDate | ForEach-Object { "{0} {1} {2}" -f $_.ProcessId, $_.ParentProcessId, $(if ($_.CreationDate) { $_.CreationDate.Ticks } else { 0 }) }' \
    2>/dev/null | /usr/bin/tr -d '\r'
}
# 보유자가 내 조상인가 — $1 = 보유자 MSYS pid · $2 = 보유자 winpid(지금 값 · 없으면 빈 값)
#   ★MSYS 사슬과 윈도 사슬을 **번갈아** 탄다(2026-09-24 실측). 두 사슬 모두 혼자서는 끊긴다:
#     · MSYS 사슬은 네이티브 프로세스(Rscript 등)가 띄운 bash 에서 ppid=1 로 끊긴다.
#     · 윈도 사슬은 Cygwin exec 지점에서 끊긴다 — exec 한 원래 윈도 프로세스는 사라지고 새 프로세스의 부모 winpid 가
#       죽은 번호를 가리킨다(실측: bash -c '...; timeout 60 Rscript' 의 timeout.exe 부모 = 사라진 bash). 그런데 MSYS pid 와
#       MSYS ppid 는 exec 를 건너 유지된다.
#   ⇒ MSYS 로 오르다 ppid=1 이면 그 프로세스의 winpid 에서 윈도로 오르고, 윈도로 오르다 Cygwin 프로세스(/proc/*/winpid 에
#     있는 번호)를 만나면 그 MSYS pid 로 돌아간다. 생성시각이 자식보다 늦은 부모 = pid 재사용 → 끊는다. 조회 실패 = 아님(fail-closed).
_rb_is_ancestor() {
  local hp="$1" hw="$2" cur="$$" pm w q d m wv steps=0 wt
  local -A WP WC W2M M2W
  while [ "$steps" -lt 128 ]; do
    steps=$((steps + 1))
    [ "$cur" = "$hp" ] && return 0
    pm=""; read -r pm < "/proc/$cur/ppid" 2>/dev/null
    if [ -n "$pm" ] && [ "$pm" != "1" ] && [ "$pm" != "0" ] && [ -d "/proc/$pm" ]; then cur="$pm"; continue; fi
    # ── MSYS 사슬 끝 → 윈도 사슬로 (표는 필요할 때 한 번만 뜬다)
    if [ -z "${wt:-}" ]; then
      wt=$(_rb_win_table); [ -n "$wt" ] || return 1
      while read -r w q d; do [ -n "$w" ] && { WP[$w]="$q"; WC[$w]="$d"; }; done <<< "$wt"
      for d in /proc/[0-9]*; do
        m="${d#/proc/}"; wv=""; read -r wv < "$d/winpid" 2>/dev/null
        [ -n "$wv" ] && { W2M[$wv]="$m"; M2W[$m]="$wv"; }
      done
    fi
    w="${M2W[$cur]:-}"; [ -n "$w" ] || return 1
    while :; do
      [ -n "$hw" ] && [ "$w" = "$hw" ] && return 0
      q="${WP[$w]:-}"; [ -n "$q" ] || return 1
      [ -n "${WC[$q]:-}" ] || return 1                           # 부모가 표에 없다(종료) — 이 가지는 끝
      [ "${WC[$q]}" -gt "${WC[$w]:-0}" ] && return 1             # 부모가 자식보다 늦게 생김 = pid 재사용
      w="$q"
      [ -n "$hw" ] && [ "$w" = "$hw" ] && return 0
      m="${W2M[$w]:-}"
      if [ -n "$m" ] && [ "$m" != "$cur" ]; then cur="$m"; break; fi   # Cygwin 프로세스 → MSYS 사슬로 복귀
    done
  done
  return 1
}

# 보유자 1건 판정 — $1 = 잠금 디렉터리 · $2 = pid 파일
#   → RB_J_STATE(held|stale|self|gone) RB_J_PID RB_J_WINPID RB_J_REASON RB_J_AGE RB_J_TAG
_rb_judge() {
  local L="$1" F="$2" pid t=0 grace="${RB_EMPTY_GRACE_S:-3}" now boot m s wp wa
  RB_J_STATE=""; RB_J_PID=""; RB_J_WINPID=""; RB_J_REASON=""; RB_J_AGE=""; RB_J_TAG=""
  pid=$(_rb_pid_of "$F")
  # ③ 빈 pid = 보유 중으로 보고 짧게 유예 후 재판정 (mkdir → echo $$ 사이의 창)
  while [ -z "$pid" ] && [ "$t" -lt "$grace" ]; do
    /usr/bin/sleep 1; t=$((t + 1))
    [ -d "$L" ] || { RB_J_STATE=gone; RB_J_REASON=released_during_grace; return 0; }
    pid=$(_rb_pid_of "$F")
  done
  RB_J_TAG=$(_rb_tag_of "$F")
  now=$(_rb_now); boot=$(_rb_boot)
  m=$(_rb_mtime "$F"); [ -n "$m" ] || m=$(_rb_mtime "$L"); [ -n "$m" ] || m=0
  RB_J_AGE=$(( now - m ))
  if [ -z "$pid" ]; then
    if [ "$m" -lt "$boot" ]; then RB_J_STATE=stale; RB_J_REASON=empty_pid_pre_boot
    elif [ "$RB_J_AGE" -le "${RB_EMPTY_HELD_MAX_S:-600}" ]; then RB_J_STATE=held; RB_J_REASON=empty_pid
    else RB_J_STATE=stale; RB_J_REASON=empty_pid_expired; fi
    return 0
  fi
  RB_J_PID="$pid"
  # ④ 재부팅 전 기록 = 지금 그 번호를 쓰는 프로세스는 보유자가 아니다
  if [ "$m" -lt $((boot - 2)) ]; then RB_J_STATE=stale; RB_J_REASON=pre_boot; return 0; fi
  # ② MSYS 생존
  if ! kill -0 "$pid" 2>/dev/null || [ ! -d "/proc/$pid" ]; then RB_J_STATE=stale; RB_J_REASON=dead; return 0; fi
  # ④ 같은 부팅 안 재사용 — 보유자는 시작한 **뒤에** pid 를 쓴다
  s=$(_rb_mtime "/proc/$pid")
  if [ -n "$s" ] && [ "$s" -gt $((m + 2)) ]; then RB_J_STATE=stale; RB_J_REASON=pid_reused; return 0; fi
  # ② MSYS 표 잔존 항목 — 윈도 표에서 한 번 더 (판정 불가면 살아 있는 것으로 둔다)
  wp=$(/usr/bin/tr -d '\r\n ' < "/proc/$pid/winpid" 2>/dev/null); RB_J_WINPID="$wp"
  if [ -n "$wp" ]; then
    _rb_win_alive "$wp"; wa=$?
    if [ "$wa" = "1" ]; then RB_J_STATE=stale; RB_J_REASON=win_dead; return 0; fi
  fi
  # ⑤ 보유자 자손은 진행
  if _rb_is_ancestor "$pid" "$wp"; then RB_J_STATE=self; RB_J_REASON=own_descendant; return 0; fi
  RB_J_STATE=held; RB_J_REASON=alive
  return 0
}

# 판정 1건을 합산 상태에 싣는다 — 우선순위 held > stale > self > free (stale/self 는 로그용으로 첫 건을 남긴다)
_rb_take() { # $1=lock 이름 $2=경로
  case "$RB_J_STATE" in
    held) RB_STATE=held ;;
    stale) [ "$RB_STATE" = held ] && return 0; [ "$RB_STATE" = stale ] && return 0; RB_STATE=stale ;;
    self)  case "$RB_STATE" in held|stale|self) return 0 ;; esac; RB_STATE=self ;;
    *) return 0 ;;
  esac
  RB_LOCK="$1"; RB_PATH="$2"; RB_PID="$RB_J_PID"; RB_WINPID="$RB_J_WINPID"
  RB_REASON="$RB_J_REASON"; RB_AGE="$RB_J_AGE"; RB_TAG="$RB_J_TAG"
}

# 합산 판정 — rc 0 = 진행 · 10 = held
rb_status() {
  local RL="${QM_REFRESH_LOCKDIR:-/tmp/qm_daily_refresh.lock}"
  local WL="${QM_RAWDATA_WRITER_LOCKDIR:-/tmp/qm_rawdata_writer.lock}"
  local f
  RB_STATE=free; RB_LOCK=""; RB_PATH=""; RB_PID=""; RB_WINPID=""; RB_REASON=""; RB_AGE=""; RB_TAG=""
  if [ -d "$RL" ]; then
    _rb_judge "$RL" "$RL/pid"; _rb_take refresh "$RL"
    [ "$RB_STATE" = held ] && return 10
  fi
  if [ -d "$WL" ]; then
    for f in "$WL"/pid.*; do
      [ -e "$f" ] || continue
      _rb_judge "$WL" "$f"; _rb_take writer "$WL"
      [ "$RB_STATE" = held ] && return 10
    done
  fi
  return 0
}

# held 인 동안 대기 — $1 = 상한 초 · $2 = 폴링 초. rc 0 = 진행 · 10 = 상한 뒤에도 held. RB_WAITED 에 대기 초.
#   ★상한은 벽시계로 잰다 — held 판정 1회에 조상 조회(PowerShell)가 ~3초 들어 sleep 합으로 세면 상한이 늘어난다.
rb_wait() {
  local max="${1:-600}" poll="${2:-20}" t0 w=0 rc
  case "$max" in ''|*[!0-9]*) max=600 ;; esac
  case "$poll" in ''|*[!0-9]*|0) poll=20 ;; esac
  t0=$(_rb_now)
  while :; do
    rb_status; rc=$?
    w=$(( $(_rb_now) - t0 ))
    if [ "$rc" -ne 10 ]; then RB_WAITED=$w; return 0; fi
    if [ "$w" -ge "$max" ]; then RB_WAITED=$w; return 10; fi
    if [ $((w + poll)) -gt "$max" ]; then /usr/bin/sleep $((max - w)); else /usr/bin/sleep "$poll"; fi
  done
}

# 판정 줄 — 탭 구분 key=value (경로에 공백이 있어도 안 깨진다). path 는 윈도 혼합형(C:/…)
rb_line() {
  local wpath=""
  [ -n "$RB_PATH" ] && wpath=$(/usr/bin/cygpath -m "$RB_PATH" 2>/dev/null || printf '%s' "$RB_PATH")
  printf 'RB\tstate=%s\tlock=%s\tpid=%s\twinpid=%s\treason=%s\tage_s=%s\ttag=%s\tpath=%s\n' \
    "$RB_STATE" "$RB_LOCK" "$RB_PID" "$RB_WINPID" "$RB_REASON" "$RB_AGE" "$RB_TAG" "$wpath"
}

# 러너 로그(.cache/reinforce_auto_log.jsonl) 기존 형식 한 줄 — $1 = 파일 · $2 = event · $3 = src · 나머지 key=value
rb_jlog() {
  local jf="$1" ev="$2" src="$3" kv k v line; shift 3
  _rb_js() { printf '%s' "$1" | /usr/bin/sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | /usr/bin/tr -d '\r\n'; }
  line="{\"ts\":\"$(/usr/bin/date +%Y-%m-%dT%H:%M:%S%z)\",\"event\":\"$(_rb_js "$ev")\",\"src\":\"$(_rb_js "$src")\""
  line="$line,\"state\":\"$(_rb_js "$RB_STATE")\",\"lock\":\"$(_rb_js "$RB_LOCK")\",\"pid\":\"$(_rb_js "$RB_PID")\",\"reason\":\"$(_rb_js "$RB_REASON")\",\"path\":\"$(_rb_js "$RB_PATH")\""
  for kv in "$@"; do k="${kv%%=*}"; v="${kv#*=}"; line="$line,\"$(_rb_js "$k")\":\"$(_rb_js "$v")\""; done
  printf '%s}\n' "$line" >> "$jf"
}

# ── writer 잠금 (아침 체인 RAWDATA writer 전용 · source 해서 쓴다) ──────────────────────────
#   보유자 = 호출 셸($$). 파일 pid.<$$> 1줄째 = pid · 2줄째 = 태그. 여러 보유자가 동시에 있어도 된다.
#   ★보유자 셸이 죽으면(파일이 남으면) 판정기가 dead/pid_reused/pre_boot 로 stale 처리한다 — 영구 차단 없음.
rb_writer_acquire() {
  local WL="${QM_RAWDATA_WRITER_LOCKDIR:-/tmp/qm_rawdata_writer.lock}" i
  for i in 1 2 3; do
    /usr/bin/mkdir -p -- "$WL" 2>/dev/null
    if printf '%s\n%s\n' "$$" "${1:-writer}" > "$WL/pid.$$" 2>/dev/null; then RB_WRITER_HELD=1; return 0; fi
    /usr/bin/sleep 1   # 다른 보유자의 rmdir 과 겹친 경우 — 재시도
  done
  RB_WRITER_HELD=0; return 1
}
rb_writer_release() {
  local WL="${QM_RAWDATA_WRITER_LOCKDIR:-/tmp/qm_rawdata_writer.lock}"
  /usr/bin/rm -f -- "$WL/pid.$$" 2>/dev/null
  /usr/bin/rmdir -- "$WL" 2>/dev/null   # 다른 보유자가 남아 있으면 실패 — 정상
  RB_WRITER_HELD=0
  return 0
}

# ── CLI ───────────────────────────────────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-status}" in
    status) rb_status; rc=$?; rb_line; exit "$rc" ;;
    wait)   rb_wait "${2:-600}" "${3:-20}"; rc=$?; rb_line; printf 'RB_WAITED\t%s\n' "${RB_WAITED:-0}"; exit "$rc" ;;
    paths)
      printf 'RB_PATHS\trefresh=%s\twriter=%s\n' \
        "$(/usr/bin/cygpath -m "${QM_REFRESH_LOCKDIR:-/tmp/qm_daily_refresh.lock}" 2>/dev/null)" \
        "$(/usr/bin/cygpath -m "${QM_RAWDATA_WRITER_LOCKDIR:-/tmp/qm_rawdata_writer.lock}" 2>/dev/null)"
      exit 0 ;;
    *) echo "usage: refresh_barrier.sh status|wait <max_s> [poll_s]|paths" >&2; exit 2 ;;
  esac
fi
