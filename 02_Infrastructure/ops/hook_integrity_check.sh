#!/usr/bin/env bash
#==============================================================================
# hook_integrity_check.sh — 현 트리에서 훅 집행이 실제로 살아 있는지 1줄 자가진단
#
# 왜 필요한가 (2026-07-25 실사고):
#   settings.json 의 PreToolUse 라우터는 `PYX="$DIR/.venv_qvest_ml/Scripts/python.exe"`
#   로 python 을 찾는데 DIR=CLAUDE_PROJECT_DIR 이고 venv 는 main 트리에만 있다.
#   → worktree 세션에서는 라우터가 실행조차 못 되고 4패턴 grep fail-closed 로 열화,
#     dispatch 대상 17개 훅(게이트급 다수)이 **조용히 무발화**했다.
#   결함 자체보다 나쁜 건 **아무 신호가 없었다**는 점이다. 그래서 이 진단을 만든다.
#
# 무엇을 보는가:
#   (1) 이 트리 settings.json 의 라우터 command 에 worktree 폴백이 들어 있는가
#   (2) 그 해석 체인으로 실제 실행 가능한 python 이 잡히는가
#   (3) 라우터가 dispatch 하기로 등록된 훅이 몇 개인가 (= 열화 시 사라지는 수)
#
# 종료코드: 0=정상 / 1=열화(경고) — 부트를 깨지 않도록 호출부에서 `|| true` 권장.
# 단독 실행: bash 02_Infrastructure/ops/hook_integrity_check.sh
#==============================================================================
set -uo pipefail

# 백슬래시 → 슬래시. ★set -u 하에서 미설정 변수를 그대로 확장하면 unbound 로 죽으므로
#   반드시 ${VAR:-} 를 거친다(실측: env 제거 시 스크립트가 진단 전에 사망).
_norm() { local p="${1:-}"; printf '%s' "${p//\\//}"; }

DIR="$(_norm "${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}")"
SETTINGS="$DIR/.claude/settings.json"
POLICY="$DIR/02_Infrastructure/hooks/policies/router_dispatch.json"

# ── python 해석: settings.json 의 라우터와 동일 체인 ────────────────────────
QM_N="$(_norm "${QM_ROOT:-}")"
QP_N="$(_norm "${QVEST_PY:-}")"

PYX="$DIR/.venv_qvest_ml/Scripts/python.exe"
if [ ! -x "$PYX" ] && [ -n "$QM_N" ]; then PYX="$QM_N/.venv_qvest_ml/Scripts/python.exe"; fi
if [ ! -x "$PYX" ] && [ -n "$QP_N" ]; then PYX="$QP_N"; fi

ROUTER_OK=0
[ -x "$PYX" ] && ROUTER_OK=1

# ── dispatch 등록 훅 수 ────────────────────────────────────────────────────
# ★python 에 경로를 넘기지 않는다 — Git Bash 의 /c/... (MSYS) 형식을 Windows python 이
#   해석하지 못해 '?' 가 나온다(실측). 셸 grep 으로 세면 경로 형식과 무관하고,
#   라우터가 죽어 있어도(=진단이 가장 필요한 상황) 숫자를 낼 수 있다.
N_DISPATCH="?"
if [ -f "$POLICY" ]; then
  N_DISPATCH=$(grep -c '"script"' "$POLICY" 2>/dev/null || echo "?")
fi

# ── 이 트리 settings.json 에 worktree 폴백이 있는가 ─────────────────────────
FALLBACK="미적용"
if [ -f "$SETTINGS" ] && grep -q 'QM_ROOT//' "$SETTINGS" 2>/dev/null; then
  FALLBACK="적용"
fi

# ── 관측 축적 (2026-07-25 next_probe ③) ────────────────────────────────────
# 열화가 **간헐적**이라는 가설이 재현 실패로 미확정 상태다. 매 발화를 append 해 두면
# 다음 발생 시 DIR/py 후보 상태가 로그로 남아 가설을 확정하거나 기각할 수 있다.
# (판정 자체는 stdout, 여기는 사후 분석용 원장)
LOGDIR="$DIR/.cache"
if [ -d "$LOGDIR" ] || mkdir -p "$LOGDIR" 2>/dev/null; then
  printf '%s\trouter_ok=%s\tdispatch=%s\tfallback=%s\tDIR=%s\tpy=%s\n' \
    "$(date -Iseconds)" "$ROUTER_OK" "$N_DISPATCH" "$FALLBACK" "$DIR" "${PYX:-}" \
    >> "$LOGDIR/hook_integrity_log.tsv" 2>/dev/null || true
fi

# ── 판정 ───────────────────────────────────────────────────────────────────
if [ "$ROUTER_OK" = "1" ]; then
  echo "[hook-integrity] router=OK dispatch=${N_DISPATCH}훅 · worktree폴백=${FALLBACK} · py=$(basename "$PYX")"
  if [ "$FALLBACK" = "미적용" ]; then
    echo "[hook-integrity] ⚠ 이 트리 settings.json 에 worktree 폴백이 없습니다 — main 병합 시 복구됩니다." >&2
    echo "[hook-integrity]   (지금 라우터가 도는 건 이 셸의 env 덕이지 settings.json 덕이 아닙니다)" >&2
    exit 1
  fi
  exit 0
else
  echo "[hook-integrity] ★ROUTER 열화 — python 해석 실패 → dispatch ${N_DISPATCH}훅 무발화, grep 4패턴만 동작" >&2
  echo "[hook-integrity]   DIR=$DIR" >&2
  echo "[hook-integrity]   후보: \$DIR/.venv_qvest_ml · \$QM_ROOT/.venv_qvest_ml · \$QVEST_PY(='${QVEST_PY:-미설정}')" >&2
  echo "[hook-integrity]   조치: QM_ROOT/QVEST_PY env 확인 또는 main 의 settings.json 폴백 병합" >&2
  exit 1
fi
