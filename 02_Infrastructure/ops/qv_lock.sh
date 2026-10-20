#!/usr/bin/env bash
#==============================================================================
# qv_lock.sh — 쓰기 잠금 · GPU 임대의 셸 API (2026-10-20 · WP3 · L1-SPEED-LEVERS-20261020)
#   정본 = qv_lock.py(의미 · 디스크 형식). 셸은 그 CLI 를 부른다 — 같은 의미가 한 벌이다(R = qv_lock.R).
#   source 해서 쓴다:  . "$ROOT/02_Infrastructure/ops/qv_lock.sh"
#     gpu_lease_acquire <holder> <purpose> [cap_hours] [holder_pid]   → 종료 0 = 잡음(이미 내 것 포함) · 1 = 다른 보유자 · 2 = 오류
#     gpu_lease_release <holder>                                       → 0 = 놓음/없음 · 1 = 다른 보유자
#     gpu_lease_status                                                 → JSON 1줄(state · holder · purpose · started_at · cap_hours · expires_at · remaining_h)
#     qv_lock_acquire <path|name:N> [wait_s] [stale_s] [purpose]      → 토큰을 QV_LOCK_TOKEN 에 · 소유자 = 이 셸의 Windows pid
#     qv_lock_release <path|name:N> [token]                            → 0 = 놓음
#   ★소유자 pid = /proc/$$/winpid(오래 사는 이 스크립트) — CLI 자신의 pid 는 곧 끝나므로 넘기지 않는다(qv_lock.py CLI 주석).
#   ★GPU 임대의 holder_pid 는 선택 — 주면 그 프로세스가 죽으면 만료 전이라도 풀린다(긴 측정 스크립트가 자기 pid 를 넘길 때만).
#==============================================================================
_QV_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
_qv_py(){
  if [ -n "${QVEST_PY:-}" ] && [ -x "${QVEST_PY}" ]; then printf '%s' "$QVEST_PY"; return; fi
  local r="${QM_ROOT:-$_QV_SELF_DIR/../..}"
  if [ -x "$r/.venv_qvest_ml/Scripts/python.exe" ]; then printf '%s' "$r/.venv_qvest_ml/Scripts/python.exe"; return; fi
  command -v python 2>/dev/null || printf 'python'
}
_qv_cli(){ "$(_qv_py)" -X utf8 "$_QV_SELF_DIR/qv_lock.py" "$@"; }
_qv_winpid(){ cat "/proc/$$/winpid" 2>/dev/null || echo "$$"; }
_qv_target_args(){ case "$1" in name:*) printf -- '--name\n%s\n' "${1#name:}" ;; *) printf -- '--path\n%s\n' "$1" ;; esac; }

gpu_lease_acquire(){
  local h="${1:?holder}" p="${2:?purpose}" c="${3:-}" hp="${4:-}" a=()
  a=(lease acquire --holder "$h" --purpose "$p" --json)
  [ -n "$c" ] && a+=(--cap-hours "$c")
  [ -n "$hp" ] && a+=(--holder-pid "$hp")
  _qv_cli "${a[@]}"
}
gpu_lease_release(){ _qv_cli lease release --holder "${1:?holder}" --json; }
gpu_lease_status(){ _qv_cli lease status --json; }

qv_lock_acquire(){
  local t="${1:?target}" w="${2:-60}" s="${3:-600}" pu="${4:-sh}" k v
  mapfile -t _qv_ta < <(_qv_target_args "$t")
  QV_LOCK_TOKEN="$(_qv_cli lock acquire "${_qv_ta[@]}" --owner-pid "$(_qv_winpid)" --wait-s "$w" --stale-s "$s" --purpose "$pu" | tr -d '\r')"
  [ -n "$QV_LOCK_TOKEN" ]
}
qv_lock_release(){
  local t="${1:?target}" tok="${2:-${QV_LOCK_TOKEN:-}}"
  [ -n "$tok" ] || return 1
  mapfile -t _qv_ta < <(_qv_target_args "$t")
  _qv_cli lock release "${_qv_ta[@]}" --token "$tok" >/dev/null
}
