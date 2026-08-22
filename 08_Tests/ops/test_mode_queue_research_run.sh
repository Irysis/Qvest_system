#!/bin/bash
# test_mode_queue_research_run.sh — opt/risk/regime 무인 러너 양방향 검사 (2026-08-21 신설)
#
# ★양방향: 막아야 할 때 막는지(위반 주입) + 막지 말아야 할 때 안 막는지(양성 대조).
#   특히 **계측 사망을 0 으로 삼키지 않는가** 를 잰다 — alpha 레인에서 bare python3 가
#   Windows Store 스텁으로 해석돼 빈 출력을 냈고, 구판이 그것을 "대기 없음" 으로 읽어
#   조용히 skip 했다(참값 3). 같은 기전이 이 러너에도 있으므로 주입으로 확인한다.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REAL_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
SCRIPT="$REAL_ROOT/02_Infrastructure/ops/mode_queue_research_run.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: $2"; }

FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/02_Infrastructure/hooks" "$FIX/02_Infrastructure/ops" \
         "$FIX/stage_artifacts/paper_recharge" "$FIX/.cache/scheduler_logs" "$FIX/06_Registry"
: > "$FIX/02_Infrastructure/hooks/qvest_hook_router.py"
cp "$REAL_ROOT/02_Infrastructure/ops/resolve_project.sh" "$FIX/02_Infrastructure/ops/" 2>/dev/null
cp "$REAL_ROOT/02_Infrastructure/ops/mode_queue_research_prompt.md" "$FIX/02_Infrastructure/ops/" 2>/dev/null
cp "$SCRIPT" "$FIX/02_Infrastructure/ops/"
RUN="$FIX/02_Infrastructure/ops/mode_queue_research_run.sh"
# ★해석기는 반드시 실물을 쓴다 — bare `python` 은 Windows Store 스텁이라
#   빈 출력을 내고, 그러면 러너의 계측-사망 가드가 전 케이스에서 발화해
#   위반 주입이 **가짜 통과**한다(2026-08-21 실제로 이 하네스가 그렇게 통과했다).
REAL_PY="${QVEST_PY:-}"
if [ -z "$REAL_PY" ] || ! "$REAL_PY" -c "print(1)" >/dev/null 2>&1; then
  echo "  SKIP  실물 python 해석기 없음(QVEST_PY 미설정) — 스텁으로는 검사 불가"; exit 0
fi
# 하네스 자기검증: 해석기가 실제로 우리가 준 문자열을 그대로 내는가
printf "%s
" "print('HARNESS_OK')" > "$FIX/_probe.py"
if [ "$("$REAL_PY" "$FIX/_probe.py" 2>/dev/null)" != "HARNESS_OK" ]; then
  echo "  FAIL  하네스 자기검증 — 해석기가 스텁"; exit 1
fi
TODAY=$(date +%Y%m%d)
LOGF="$FIX/.cache/scheduler_logs/mode_queue_research_${TODAY}.log"

# 술어 스텁 — 테스트가 통제하는 출력을 낸다(실제 술어 대신)
mk_pred(){ printf '%s\n' '#!/usr/bin/env python3' 'import sys' "print('''$1''')" \
             > "$FIX/02_Infrastructure/ops/research_pool_predicates.py"; }

fire(){ rm -f "$LOGF"; rm -rf "$FIX/.cache/mode_queue_research.lock"
        ( cd "$FIX" && QM_ROOT="$FIX" QVEST_PY="$REAL_PY" \
            env "$@" bash "$RUN" >/dev/null 2>&1 ); }

echo "== 위반 주입 1: kill switch 가 꺼져 있으면 아무것도 안 하는가 =="
mk_pred "5"
fire QVEST_MODE_QUEUE_ENABLE=0
if grep -q "disabled" "$LOGF" 2>/dev/null && ! grep -q "start mode_queue" "$LOGF" 2>/dev/null; then
  ok "ENABLE!=1 → skip (kill switch 실효)"
else ng "kill switch" "$(tail -1 "$LOGF" 2>/dev/null)"; fi

echo "== 위반 주입 2: 계측 사망을 0 으로 삼키지 않는가 (최우선) =="
mk_pred ""            # 빈 출력 = 스텁/손상 — 구판 기전이면 'pending 0 skip' 으로 위장된다
fire QVEST_MODE_QUEUE_ENABLE=1
if grep -q "pending 계측 실패" "$LOGF" 2>/dev/null \
   && ls "$FIX/.cache/scheduler_alerts/mode_queue_count_measurement_failed_${TODAY}.alert" >/dev/null 2>&1; then
  ok "빈 출력 → count_measurement_failed 경보 후 중단 (0 으로 안 삼킴)"
else ng "계측 사망 검출" "$(tail -2 "$LOGF" 2>/dev/null)"; fi
rm -rf "$FIX/.cache/scheduler_alerts"

echo "== 위반 주입 3: 비숫자 출력도 잡는가 =="
mk_pred "N/A"
fire QVEST_MODE_QUEUE_ENABLE=1
grep -q "pending 계측 실패" "$LOGF" 2>/dev/null \
  && ok "비숫자 'N/A' → 중단" || ng "비숫자 검출" "$(tail -1 "$LOGF" 2>/dev/null)"
rm -rf "$FIX/.cache/scheduler_alerts"

echo "== 양성 대조: pending 0 은 정상 skip 인가 (과잉 경보 방지) =="
mk_pred "0"
fire QVEST_MODE_QUEUE_ENABLE=1
if grep -q "pending 0 — skip" "$LOGF" 2>/dev/null \
   && ! ls "$FIX/.cache/scheduler_alerts/"*.alert >/dev/null 2>&1; then
  ok "참값 0 → 조용히 skip (경보 없음)"
else ng "pending 0 정상처리" "$(tail -1 "$LOGF" 2>/dev/null)"; fi

echo "== 양성 대조 2: pending>0 이면 실제로 진행하는가 =="
mk_pred "7"
fire QVEST_MODE_QUEUE_ENABLE=1 QVEST_MODE_QUEUE_DRYRUN=1
if grep -q "pending=7" "$LOGF" 2>/dev/null; then ok "pending 7 → 산정 진행"
else ng "정상 진행" "$(tail -1 "$LOGF" 2>/dev/null)"; fi

echo "== 위반 주입 4: 상한이 로그에 실제로 실리는가 =="
mk_pred "7"
fire QVEST_MODE_QUEUE_ENABLE=1 QVEST_MODE_QUEUE_DRYRUN=1 QVEST_MODE_QUEUE_MAX=1
grep -q "MAX_ITEMS=1" "$LOGF" 2>/dev/null \
  && ok "MAX_ITEMS=1 반영" || ng "상한 반영" "$(tail -1 "$LOGF" 2>/dev/null)"

echo "== 위반 주입 5: 동시 인스턴스가 차단되는가 =="
mk_pred "7"
rm -f "$LOGF"; rm -rf "$FIX/.cache/mode_queue_research.lock"
mkdir -p "$FIX/.cache/mode_queue_research.lock"; echo "$$" > "$FIX/.cache/mode_queue_research.lock/pid"
( cd "$FIX" && QM_ROOT="$FIX" QVEST_PY="$REAL_PY" \
    QVEST_MODE_QUEUE_ENABLE=1 QVEST_MODE_QUEUE_DRYRUN=1 bash "$RUN" >/dev/null 2>&1 )
grep -q "다른 인스턴스 실행 중" "$LOGF" 2>/dev/null \
  && ok "생존 PID 락 → 2번째 skip" || ng "동시 차단" "$(tail -1 "$LOGF" 2>/dev/null)"

echo "== 양성 대조 3: 죽은 PID 락은 회수되는가 (영구 정지 방지) =="
rm -f "$LOGF"; rm -rf "$FIX/.cache/mode_queue_research.lock"
mkdir -p "$FIX/.cache/mode_queue_research.lock"; echo "999999" > "$FIX/.cache/mode_queue_research.lock/pid"
( cd "$FIX" && QM_ROOT="$FIX" QVEST_PY="$REAL_PY" \
    QVEST_MODE_QUEUE_ENABLE=1 QVEST_MODE_QUEUE_DRYRUN=1 bash "$RUN" >/dev/null 2>&1 )
grep -q "stale lock 회수" "$LOGF" 2>/dev/null \
  && ok "죽은 PID 락 회수 후 진행" || ng "stale lock 회수" "$(tail -1 "$LOGF" 2>/dev/null)"

echo "== 계약 검사: 프롬프트가 자본 경로를 명시 금지하는가 =="
PF="$REAL_ROOT/02_Infrastructure/ops/mode_queue_research_prompt.md"
miss=""
for k in "governor" "book_state" "canonical_screen_diag" "PIT C1~C15" "MODEQ_DONE" "alpha-hypothesis" "alpha-research" "method_measure" "canonical_screen_bt"; do
  grep -q "$k" "$PF" 2>/dev/null || miss="$miss $k"
done
[ -z "$miss" ] && ok "프롬프트 하드가드+레인 9축 명시" || ng "프롬프트 가드" "누락:$miss"

echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
[ "$FAIL" -eq 0 ] || exit 1
