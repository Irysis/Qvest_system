#!/usr/bin/env bash
#==============================================================================
# qw_session_ensure.sh — 퀀티 단말 세션 확인 · 죽어 있으면 한 번 재로그인 (2026-11-11)
#   도훈 11-11 "자가 복구가 수급 전에 퀀티 세션을 먼저 확인하고, 죽어 있으면 한 번 재로그인하게 해줘"
#   (결정 QW-SELFHEAL-SESSION-ENSURE-20261111)
#
# 왜: 밤 체인의 Update_File 수급은 로그인 클릭을 하지 않고(-SkipLogin · 10-16 결정 QW-UPDATEFILE-UNATTENDED 안 A), [1pre] 벤치 수급은
#   로그인 창이 보일 때만 로그인한다. 세션이 죽었는데 로그인 창이 안 보이는 상태(종료 대화상자 · 멈춘 단말 · 날짜 문맥이 멈춘 세션)에서는
#   수급이 20초 만에 'session kicked' 로 끝난다(11-11 00:18 · 07:27 실측 — 자가 복구가 헛돌고 사람이 로그인할 때까지 정체).
# 무엇: 드라이버(ops/qw_refresh.ps1)의 -LoginOnly 를 한 번 부른다 — 살아 있으면 아무것도 하지 않고, 죽어 있으면 단말을 띄워
#   앱에 저장된 자격으로 로그인 단추를 누른다(자격 저장 확인 · 종료 알림 뒤 재로그인 1회 · 두 번째 종료 = 멈춤 — 드라이버 Ensure-Login
#   규칙 그대로). 이 스크립트는 자격을 다루지 않는다.
# 계정 잠금 방지: 로그인을 시도했는데도 세션이 안 살면(alive=False) **그날은 다시 시도하지 않는다**(날짜 표식 .cache/qw_session_ensure.json ·
#   08-29 사고 = 저장 안 된 비밀번호로 로그인 클릭 40회). 살아 있던 호출 · 로그인에 성공한 호출 뒤에는 다음 호출도 그대로 확인한다
#   (호출 간격은 자가 복구의 같은 영업일 재시도 간격이 이미 묶는다 — ensure_data_current.sh 3b). 드라이버가 뜨지 못한 것(시간 초과 ·
#   출력 없음)은 로그인 실패로 세지 않는다 — 로그인 단추를 눌렀는지 알 수 없는 실패로 하루를 잠그지 않는다.
# 호출부: ops/ensure_data_current.sh — 복구 계획에 qw 가 있을 때(= 퀀티 미갱신) 리프레시 직전. 결과와 무관하게 복구는 진행한다.
# 종료 코드: 0 = 세션 살아 있음(원래 또는 로그인 뒤) · 3 = 세션 없음(로그인 실패 · 오늘 이미 실패 · 드라이버 실패) · 10 = 꺼짐
# 마지막 줄 = 'QSE<TAB>state=<alive|logged_in|login_failed|skipped_failed_today|driver_error|disabled><TAB>alive=<True|False|?><TAB>kicks=<n>'
# 끄기: QVEST_QW_SESSION_ENSURE=0
# 검사 주입(검사 전용): QSE_DRIVER_CMD(드라이버 명령 대체) · QSE_STATE(표식 경로) · QSE_TODAY(YYYY-MM-DD) · QSE_TIMEOUT_S · QSE_LOG_DIR
#==============================================================================
set -u
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=/dev/null
source "$_SELF_DIR/resolve_project.sh" 2>/dev/null || true
BASE="${BASE:-${PROJECT:-}}"
fin() {   # $1 state · $2 alive · $3 kicks · $4 rc
  printf 'QSE\tstate=%s\talive=%s\tkicks=%s\n' "$1" "$2" "$3"
  exit "$4"
}
[ "${QVEST_QW_SESSION_ENSURE:-1}" = "1" ] || fin disabled "?" 0 10
if [ -z "${BASE:-}" ] || [ ! -f "$BASE/02_Infrastructure/hooks/qvest_hook_router.py" ]; then
  echo "[qse] 프로젝트 루트 해석 실패 — 표지 미확인" >&2; fin driver_error "?" 0 3
fi
STATE="${QSE_STATE:-$BASE/.cache/qw_session_ensure.json}"
TODAY="${QSE_TODAY:-$(date +%Y-%m-%d)}"
TMO="${QSE_TIMEOUT_S:-300}"     # 드라이버 -LoginOnly 실측 약 30초(11-11 13:42:58 → 13:43:25) — 단말 기동 대기 여유 포함 상한
LOGD="${QSE_LOG_DIR:-$BASE/.cache/scheduler_logs}"
_field() { sed -n "s/.*\"$1\":\"\\([^\"]*\\)\".*/\\1/p" "$STATE" 2>/dev/null | head -n 1; }
_write() {   # $1 result · $2 alive · $3 kicks · $4 attempted(0|1)
  mkdir -p "$(dirname "$STATE")" 2>/dev/null
  printf '{"schema":"qw_session_ensure_v1","date":"%s","at":"%s","result":"%s","alive":"%s","kicks":"%s","login_attempted":"%s"}\n' \
    "$TODAY" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$1" "$2" "$3" "$4" > "$STATE.tmp" 2>/dev/null && mv -f "$STATE.tmp" "$STATE" 2>/dev/null
}

# 오늘 이미 로그인에 실패했으면 다시 누르지 않는다
if [ "$(_field date)" = "$TODAY" ] && [ "$(_field result)" = "login_failed" ]; then
  echo "[qse] 오늘($TODAY) 로그인 시도가 이미 실패했다 — 다시 시도하지 않는다(단말에서 사람이 확인)"
  fin skipped_failed_today "False" "$(_field kicks)" 3
fi

mkdir -p "$LOGD" 2>/dev/null
LOG="$LOGD/qw_session_ensure_$(date +%Y%m%d_%H%M%S).log"
if [ -n "${QSE_DRIVER_CMD:-}" ]; then
  timeout "$TMO" bash -c "$QSE_DRIVER_CMD" > "$LOG" 2>&1; drc=$?
else
  DRV="$BASE/02_Infrastructure/ops/qw_refresh.ps1"
  [ -f "$DRV" ] || { echo "[qse] 드라이버 없음: $DRV" >&2; fin driver_error "?" 0 3; }
  timeout "$TMO" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$DRV" 2>/dev/null || echo "$DRV")" -LoginOnly > "$LOG" 2>&1; drc=$?
fi
END_LINE="$(grep -a 'LOGIN-ONLY END' "$LOG" 2>/dev/null | tail -n 1 | tr -d '\r')"
ALIVE="$(printf '%s' "$END_LINE" | sed -n 's/.*alive=\([A-Za-z]*\).*/\1/p')"
KICKS="$(printf '%s' "$END_LINE" | sed -n 's/.*kicks=\([0-9]*\).*/\1/p')"; KICKS="${KICKS:-0}"
ATTEMPT=0; grep -aq '\[login\] no session -> launching + login' "$LOG" 2>/dev/null && ATTEMPT=1
if [ -z "$END_LINE" ] || [ -z "$ALIVE" ]; then
  echo "[qse] 드라이버가 끝 줄을 내지 않았다(rc=$drc · 시간 상한 ${TMO}s) — 로그 $LOG"
  _write driver_error "?" "$KICKS" "$ATTEMPT"
  fin driver_error "?" "$KICKS" 3
fi
if [ "$ALIVE" = "True" ]; then
  if [ "$ATTEMPT" = "1" ]; then
    echo "[qse] 세션이 죽어 있어 재로그인했다 — alive=True · kicks=$KICKS · 로그 $LOG"
    _write logged_in "True" "$KICKS" 1; fin logged_in "True" "$KICKS" 0
  fi
  echo "[qse] 세션 살아 있음 — 아무것도 하지 않았다"
  _write alive "True" "$KICKS" 0; fin alive "True" "$KICKS" 0
fi
echo "[qse] ★로그인 시도 뒤에도 세션 없음(alive=$ALIVE · kicks=$KICKS) — 오늘은 다시 시도하지 않는다 · 로그 $LOG"
_write login_failed "False" "$KICKS" "$ATTEMPT"
fin login_failed "False" "$KICKS" 3
