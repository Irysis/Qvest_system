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
  # ★`grep -c` 는 **0건일 때 exit 1** 이다 — 구판의 `|| echo "?"` 가 그때 함께 발화해
  #   N_DISPATCH 가 "0\n?" 라는 두 줄 값이 됐다(v9 의 빈 registry 에서 실측).
  #   그 값은 어떤 숫자 비교와도 안 맞아 "dispatch 폐지" 모드 판정이 통째로 빗나갔다.
  #   ⇒ 실패와 0건을 분리한다: grep 실패는 삼키고, 값이 비었을 때만 미측정("?")으로 둔다.
  N_DISPATCH=$(grep -c '"script"' "$POLICY" 2>/dev/null || true)
  N_DISPATCH=$(printf '%s' "$N_DISPATCH" | tr -d ' \r\n')
  [ -n "$N_DISPATCH" ] || N_DISPATCH="?"
fi

# ── (2026-07-26 probe① 도훈 승인) dispatch 필수 훅 baseline 대조 ──────────────
# 구판은 dispatch=N을 찍기만 하고 기대와 대조하지 않았다 — 라우터 policy에서 게이트급
# 훅이 조용히 빠져도 숫자만 바뀌고 경보 0 (부팅감사 커버리지 갭 ③). AX-002 동급/게이트급
# 훅만 필수 목록으로 못박는다(전수 18 아님 — 신규 등재는 자유, '해제'만 잡는 래칫).
REQUIRED_DISPATCH=(
  "safety_guard.sh"                 # Tier1 보호선
  "axiom_enforcement_hook.sh"       # AX 강제
  "discovery_graduation_gate.sh"    # HARD 3종 fail-closed
  "backtest_contract_audit.sh"      # 자체합성 차단
  "ast_spec_gate.sh"                # AST v1.1 기계 게이트 (2026-07-25 등재)
  "legacy_write_block.sh"           # legacy 격리
  "worktask_constraint_enforcer.sh" # 25종/long-only/Σw=1 (비중 상한은 v10 폐지)
)

# ── ★v9 Lean Loop (2026-08-23): 직접 등록 모드 ───────────────────────────────
# dispatch 목록이 **비어 있는 것**은 결손이 아니라 v9 의 정상 상태다 — 라우터 경유를
# 폐지하고 자본·안전 W/E 게이트를 settings.json 에 직접 등록했기 때문이다.
# 그런데 구판 로직은 "policy 에 이름이 있는가"만 보므로, 그 상태를 **결손 7종**으로
# 오보한다(직접 등록이 오히려 강한 배선인데 경보가 뜬다 = 감시기가 거짓말을 한다).
# ⇒ 모드를 먼저 판정하고, 직접 등록 모드에서는 **settings.json 의 W/E 게이트 4종**을
#    같은 래칫으로 대조한다. dispatch 가 되살아나면 구 경로가 그대로 다시 적용된다.
REQUIRED_DIRECT_WE=(
  "safety_guard.sh"                 # Tier1 보호선 (Write|Edit + Bash)
  "legacy_write_block.sh"           # legacy 격리
  "discovery_graduation_gate.sh"    # HARD 3종 fail-closed
  "worktask_constraint_enforcer.sh" # 25종/long-only/Σw=1 (비중 상한은 v10 폐지)
  "book_write_guard.sh"             # v10 2026-08-29: BOOK 정본 writer 경유 강제 + legacy book_state 재기입 차단
  "backtest_contract_audit.sh"      # 2026-08-24 재등록: 원장 integrity 게이트
)
MODE_DIRECT=0
case "$N_DISPATCH" in
  0) MODE_DIRECT=1 ;;
esac

DISPATCH_MISS=""
DIRECT_MISS=""
if [ "$MODE_DIRECT" = "1" ]; then
  if [ -f "$SETTINGS" ]; then
    for _rd in "${REQUIRED_DIRECT_WE[@]}"; do
      grep -q "hooks/$_rd" "$SETTINGS" 2>/dev/null || DIRECT_MISS="$DIRECT_MISS$_rd "
    done
  else
    DIRECT_MISS="(settings.json 부재) "
  fi
elif [ -f "$POLICY" ]; then
  for _rd in "${REQUIRED_DISPATCH[@]}"; do
    grep -q "\"$_rd\"" "$POLICY" 2>/dev/null || DISPATCH_MISS="$DISPATCH_MISS$_rd "
  done
fi

# ── 이 트리 settings.json 에 worktree 폴백이 있는가 ─────────────────────────
# v8 라우터 형식(`${QM_ROOT//\\//}`)과 v9 직접 등록 형식(`${QM_ROOT:-$PWD}`) 둘 다 인정.
# 구판은 라우터 지문만 봐서, 라우터가 사라진 v9 settings.json 을 매번 "폴백 미적용"으로
# 읽었다(= 정상 상태에 대한 거짓 경고).
FALLBACK="미적용"
if [ -f "$SETTINGS" ] && grep -qE 'QM_ROOT//|QM_ROOT:-\$PWD' "$SETTINGS" 2>/dev/null; then
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
# ★v9 직접 등록 모드가 먼저다 — 이 모드에서는 라우터 python 해석 여부가 판정과 무관하다
#   (아무것도 dispatch 하지 않으므로 python 이 없어도 게이트는 전부 발화한다).
#   구판처럼 ROUTER_OK 로 먼저 갈라면 python 부재 시 "★ROUTER 열화 → 0훅 무발화" 라는
#   **사실과 반대인** 경보가 난다.
if [ "$MODE_DIRECT" = "1" ]; then
  N_DIRECT=$(grep -oE 'hooks/[A-Za-z0-9_]+\.sh' "$SETTINGS" 2>/dev/null | sort -u | wc -l | tr -d ' ')
  if [ -n "$DIRECT_MISS" ]; then
    echo "[hook-integrity] ★필수 W/E 게이트 결손: ${DIRECT_MISS}— settings.json 직접 등록에서 게이트급 훅이 빠짐 (등재 해제는 도훈 승인 사항)" >&2
    echo "[hook-integrity] 직접 등록 모드(dispatch 폐지) · 등록 ${N_DIRECT}종 · worktree폴백=${FALLBACK}" >&2
    exit 1
  fi
  echo "[hook-integrity] 직접 등록 모드 — dispatch 폐지(v9 2026-08-23) · W/E 게이트 ${#REQUIRED_DIRECT_WE[@]}/${#REQUIRED_DIRECT_WE[@]} 직접 등록 · 등록 ${N_DIRECT}종 · worktree폴백=${FALLBACK}"
  echo "[hook-integrity]   해제 36종 원장: 02_Infrastructure/hooks/_archive_v8_enforcement/MANIFEST.md"
  exit 0
fi

if [ "$ROUTER_OK" = "1" ]; then
  echo "[hook-integrity] router=OK dispatch=${N_DISPATCH}훅 · worktree폴백=${FALLBACK} · py=$(basename "$PYX")"
  if [ -n "$DISPATCH_MISS" ]; then
    echo "[hook-integrity] ★필수 dispatch 훅 결손: ${DISPATCH_MISS}— router policy에서 게이트급 훅이 빠짐 (등재 해제는 도훈 승인 사항)"
  fi
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
