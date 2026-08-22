#!/bin/bash
# test_router_backfill_paths.sh — 좌초 회수 3축의 **도달성·안전성·불변성** (2026-08-22 신설)
#
# 왜 있나 (사전 타당성 실측이 계획을 수정했다):
#   좌초 18일이 **전부 7일 창 밖**(age 34~71일)인데 백로그 루프는 `for i in 7 6 5 4 3 2 1`
#   고정이라, `QVEST_PAPER_ROUTER_FORCE` 를 풀어도 **한 편도 못 건진다**.
#   FORCE 는 "당일 discovery 없어도 진행" 스위치이고 스캔 **범위**는 별개 축인데
#   내가 두 축을 하나로 봤다 — 고치기 전에 재서 잡았다.
#
# ★3축이 함께여야 회수된다:
#   ① FORCE 를 discovery 게이트 **앞**으로 (구판은 18줄 뒤에서 처음 검사 = 필요한 상황에 도달 못 함,
#      게다가 그 skip 로그가 "FORCE=1 로 강제" 라고 **도달 못 하는 안내**를 했다)
#   ② 명시 날짜 경로 (창 확대는 매 런의 **일상 비용** — 일회성 회수는 일회성 경로로)
#   ③ BACKLOG_MAX 외부화 (3 고정이면 18일치에 6런)
#
# ★1급 축은 회수가 아니라 **기본 동작 불변**이다. env 를 안 주면 종전과 100% 같아야 한다.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
R="$ROOT/02_Infrastructure/ops/paper_router_run.sh"
LOG="$ROOT/.cache/scheduler_logs/paper_router_$(date +%Y%m%d).log"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: $2"; }

[ -f "$R" ] || { echo "  SKIP  라우터 부재"; echo "== t_summary: PASS=0 FAIL=0 =="; exit 0; }

echo "== 배선 축: 3축이 모두 존재하는가 =="
grep -q 'QVEST_PAPER_ROUTER_DATES' "$R" && ok "② 명시 날짜 경로 존재" \
  || ng "명시 날짜 경로" "창 밖 좌초일에 원리적으로 도달 불가"
grep -q 'QVEST_PAPER_ROUTER_BACKLOG_MAX' "$R" && ok "③ BACKLOG_MAX 외부화" \
  || ng "BACKLOG_MAX" "3 고정이면 18일치 회수에 6런 필요"
grep -q '그러나 FORCE=1, 진행' "$R" && ok "① FORCE 가 게이트 앞에서 검사" \
  || ng "FORCE 위치" "FORCE 가 필요한 유일한 상황에 도달하지 않는다"

echo "== ★순서 축: 명시경로 → 창루프 → discovery게이트 =="
a=$(grep -n '명시 백필 합류' "$R" | head -1 | cut -d: -f1)
b=$(grep -n 'for i in 7 6 5 4 3 2 1' "$R" | head -1 | cut -d: -f1)
c=$(grep -n 'no discovery JSON for \$TODAY and no backlog' "$R" | head -1 | cut -d: -f1)
if [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ]; then
  ok "순서 정확 ($a < $b < $c)"
else
  ng "순서" "명시경로가 게이트 뒤면 도달 불가 (a=$a b=$b c=$c)"
fi

echo "== ★불변 축: env 를 안 주면 기본값이 종전과 같은가 =="
grep -q 'BACKLOG_MAX="${QVEST_PAPER_ROUTER_BACKLOG_MAX:-3}"' "$R" \
  && ok "BACKLOG_MAX 기본 3 유지" || ng "기본값 변경" "외부화하면서 기본 동작을 바꿨다"
grep -q 'if \[ -n "${QVEST_PAPER_ROUTER_DATES:-}" \]; then' "$R" \
  && ok "명시 경로는 env 지정 시에만 발동" || ng "무조건 발동" "지정 안 해도 도는 코드는 일상 비용"

echo "== 안전 축: 명시 날짜가 잘못돼도 방어하는가 =="
grep -q '날짜 형식 아님 무시' "$R" && ok "비숫자 입력 방어" || ng "형식 검증" "임의 문자열이 경로로 들어간다"
grep -q 'route 이미 존재 — 제외' "$R" && ok "이미 route 된 날짜 제외 (재작업 방지)" \
  || ng "중복 방어" "이미 소비한 날을 다시 태운다"
grep -q 'discovery 부재 — 라우팅 소스 없음' "$R" && ok "discovery 없는 날 제외" \
  || ng "소스 검증" "라우팅할 재료가 없는 날을 합류시킨다"
grep -q 'case ",\$BACKLOG_DATES," in' "$R" && ok "창 루프와 중복 합류 방지" \
  || ng "중복 합류" "같은 날짜가 두 번 들어가 프롬프트가 비대해진다"

echo "== 행동 축: DRYRUN 실행으로 확인 (claude 미호출) =="
PYB="${QVEST_PY:-}"
[ -x "$PYB" ] || PYB="$ROOT/.venv_qvest_ml/Scripts/python.exe"
[ -x "$PYB" ] || PYB="$(command -v python3 2>/dev/null || echo python)"

HAVE=$(ls -1 "$ROOT/stage_artifacts/paper_recharge/"alpha_search_route_*.json 2>/dev/null | head -1 | grep -oE '[0-9]{8}')
MISS=$(cd "$ROOT" && "$PYB" "$ROOT/08_Tests/ops/lib/_first_orphan_date.py" 2>/dev/null)

runbf(){ (cd "$ROOT" && QVEST_PAPER_ROUTER_ENABLE=1 QVEST_PAPER_ROUTER_DRYRUN=1 \
          QVEST_PAPER_ROUTER_DATES="$1" bash "$R" >/dev/null 2>&1); tail -40 "$LOG" 2>/dev/null; }

if [ -n "$HAVE" ]; then
  runbf "$HAVE" | grep -q "$HAVE 는 route 이미 존재 — 제외" \
    && ok "route 있는 날짜 → 제외 (실행 확인)" || ng "제외 미작동" "route 가 있는 $HAVE 를 합류시킨다"
fi
if [ -n "$MISS" ]; then
  runbf "$MISS" | grep -q "명시 백필 합류: $MISS" \
    && ok "창 밖 좌초일 $MISS → 합류 (회수 경로 실증)" || ng "합류 실패" "창 밖 날짜가 여전히 도달 불가"
else
  ok "좌초일 0 — 합류 대상 없음(정상)"
fi
runbf "abc,zz99" | grep -q "날짜 형식 아님 무시" \
  && ok "비숫자 입력 → 무시 (실행 확인)" || ng "형식 방어 미작동" "임의 문자열이 통과한다"

echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
[ "$FAIL" -eq 0 ] || exit 1
