#!/bin/bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
#==============================================================================
# Harness Health Check — v8.1 (v6.1 kernel absorbed)
# 모든 Hook 정상 작동 여부 검증. /qvest 부트스트랩에서 호출.
#==============================================================================

is_qvest_root() {
  [ -n "$1" ] && [ -d "$1/02_Infrastructure/hooks" ] && [ -f "$1/.claude/settings.json" ]
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DIR=""
for cand in "$CLAUDE_PROJECT_DIR" "$QM_ROOT" "$PWD" "$SCRIPT_DIR/../.."; do
  if is_qvest_root "$cand"; then
    DIR="$(cd "$cand" && pwd -P)"
    break
  fi
done
if [ -z "$DIR" ]; then
  cur="$PWD"
  while [ "$cur" != "/" ]; do
    if is_qvest_root "$cur"; then DIR="$(cd "$cur" && pwd -P)"; break; fi
    cur="$(dirname "$cur")"
  done
fi
if [ -z "$DIR" ]; then echo "[HARNESS] PROJECT_ROOT not found"; exit 1; fi

HOOKS_DIR="$DIR/02_Infrastructure/hooks"
SETTINGS="$DIR/.claude/settings.json"
FAIL=0
TOTAL=0
PASS=0

echo "=== Harness Health Check (v10.1) ==="

# v7.0/v7.1 Required Hooks (v55 legacy archived to _archive_v55/, v7.1-lite Sprint 0.3 동기화)
# v55 legacy 제거: role_taxonomy_admission_gate.sh + cash_sleeve_validator.sh
# 둘 다 .claude/settings.json 등록 0건 (v7.0 Sprint 5 cleanup) → required list에서도 제거
# DEPRECATION.md 참조
# ★v9 Lean Loop (2026-08-23) — 목록을 **현행 등록 종 + 자기 자신**으로 축소.
#   ★v10 (2026-09-02): 등록 12종으로 갱신 — governor_concord_certifier(v10 RETIRED·등록 해제) 제거,
#     book_write_guard(v10 08-29 승계)·backtest_contract_audit(08-24 재등록) 추가. 구 목록은 두 파일이 사라져도
#     12/12 PASS 를 내던 낡은 초록이었다.
#   구판은 v6.1~v8.x 누적 28종을 요구했는데, 그중 대다수는 v9 에서 등록 해제됐다
#   (라우터 dispatch 폐지 + Stop 훅 0 + PostToolUse 2종). 목록을 그대로 두면
#   "등록도 안 된 훅의 파일 존재"를 계속 요구하게 되고, 그건 이 검사가 답하려는
#   질문("지금 집행되는 훅이 성한가")과 다른 질문이다.
#   ★해제 36종의 파일은 **삭제하지 않았다** — harness_health/배터리/08_Tests 31파일이
#     경로로 직접 호출한다. 목록·사유·재등록 레시피 =
#     02_Infrastructure/hooks/_archive_v8_enforcement/MANIFEST.md
REQUIRED_HOOKS=(
  # PreToolUse Write|Edit — 보호선 (+ v10 BOOK 정본 writer 경유 강제)
  "safety_guard.sh"
  "legacy_write_block.sh"
  "book_write_guard.sh"

  # PreToolUse Write — 측정 규율 게이트(graduation HARD 3종) + 고정축 + 원장 integrity(08-24 재등록)
  "discovery_graduation_gate.sh"
  "worktask_constraint_enforcer.sh"
  "backtest_contract_audit.sh"

  # PreToolUse Bash
  "telegram_direct_call_guard.sh"

  # PreToolUse Agent — 지식 주입
  "axiom_context_inject.sh"

  # PreToolUse Read|Grep|Glob — arm 생성 세션 성과 열람 차단(평시 무발화, v10.2)
  "arm_gen_read_guard.sh"

  # PostToolUse Write|Edit — PIT C5 advisory (governor_concord_certifier 는 v10 RETIRED — 등록 해제)
  "overlay_pit_grep.sh"

  # SessionStart / SessionEnd
  "boot_stamp_check.sh"
  "auto_commit_on_stop.sh"
  "auto_push_on_stop.sh"

  # 자기 자신 (이 검사기도 파일로 존재·실행 가능해야 한다)
  "harness_health.sh"
)

for HOOK in "${REQUIRED_HOOKS[@]}"; do
  TOTAL=$((TOTAL + 1))
  FPATH="$HOOKS_DIR/$HOOK"
  if [ -f "$FPATH" ]; then
    if [ -x "$FPATH" ]; then
      PASS=$((PASS + 1))
    else
      echo "  [WARN] $HOOK — not executable"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  [FAIL] $HOOK — missing"
    FAIL=$((FAIL + 1))
  fi
done

# settings.json Hook 등록 확인
# (2026-07-26 부팅감사 수리) 구현 2중 결함: ① open('$SETTINGS')에 MSYS 경로(/c/...)가 박혀
# 네이티브 Windows python이 FileNotFoundError → ② `|| echo "0"` fail-open으로 "0 entries"가
# INFO로 통과. settings.json hooks 블록을 통째로 비워도 부팅 출력이 동일했다(46-hook 침묵사망
# 감지선 단절). 수리 = stdin 전달(경로 번역 무관) + 계측실패/0건 = FAIL(0은 정상 상태가 아니다).
if [ -f "$SETTINGS" ]; then
  REG_COUNT=$(cat "$SETTINGS" | "$QVEST_PY_BIN" -c "
import json, sys
d = json.load(sys.stdin)
hooks = d.get('hooks', {})
total = sum(len(v) for v in hooks.values())
print(total)
" 2>/dev/null || echo "UNREPORTED")
  if [ "$REG_COUNT" = "UNREPORTED" ] || [ "${REG_COUNT:-0}" = "0" ]; then
    echo "  [FAIL] settings.json: hook 등록 계측 실패 또는 0건 (REG_COUNT=$REG_COUNT) — hooks 블록 소실/파서 사망 의심"
    FAIL=$((FAIL + 1))
  else
    echo "  [INFO] settings.json: $REG_COUNT hook entries registered"
  fi
else
  echo "  [FAIL] settings.json not found"
  FAIL=$((FAIL + 1))
fi

# ERR trap 확인 — 등록 훅은 내부 오류 시 조용히 죽지 말고 fail-open/fail-closed 판정을
#   명시 발행해야 한다. (v9 2026-08-23: 목록을 현행 등록 종으로 교체 — 구판은 해제·부재
#   훅 4종을 검사해 항상 침묵했다. v10 2026-09-02: 등록 12종으로 동기 — book_write_guard·backtest_contract_audit
#   추가(둘 다 trap 보유 실측), governor_concord_certifier 제거.)
for HOOK in "safety_guard.sh" "legacy_write_block.sh" "book_write_guard.sh" \
            "discovery_graduation_gate.sh" "worktask_constraint_enforcer.sh" "backtest_contract_audit.sh" \
            "telegram_direct_call_guard.sh" "axiom_context_inject.sh" \
            "overlay_pit_grep.sh" \
            "boot_stamp_check.sh" "auto_commit_on_stop.sh" "auto_push_on_stop.sh"; do
  FPATH="$HOOKS_DIR/$HOOK"
  if [ -f "$FPATH" ]; then
    if ! grep -q "trap.*ERR\|trap.*err" "$FPATH"; then
      echo "  [WARN] $HOOK — ERR trap missing"
    fi
  fi
done

echo ""
echo "=== Result: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  echo "[HARNESS] $FAIL issues detected. Fix before proceeding."
  exit 1
fi
echo "[HARNESS] All hooks healthy."
exit 0
