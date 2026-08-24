#!/bin/bash
# test_paper_router_backlog_axis.sh — paper_router_run.sh 백로그 축 + 자체 락 검사 (2026-08-21 신설)
#
# 왜 있나: 2026-08-21 실측에서 백로그 스캐너가 **자기 발화 조건에 눈이 먼** 상태였다.
#   판정축이 `.done` 스탬프였는데, 백로그를 만드는 실패 모드(런 중도 사망)가 바로
#   .done 을 못 남기는 모드다 → 08-15/16/17 discovery 29편씩이 로그 한 줄 없이 탈락,
#   12편 미라우팅. 수리는 축을 "discovery 있고 route 없음"으로 옮겼다.
#
# ★양방향으로 잰다 — 잡아야 할 것을 잡는지(양성 대조)와 잡지 말아야 할 것을 안 잡는지
#   (위반 주입) 둘 다. "경고 0" 은 그 자체로는 아무것도 증명하지 않는다.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REAL_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
SCRIPT="$REAL_ROOT/02_Infrastructure/ops/paper_router_run.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: $2"; }

FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/02_Infrastructure/hooks" "$FIX/stage_artifacts/paper_recharge" "$FIX/.cache/scheduler_logs"
: > "$FIX/02_Infrastructure/hooks/qvest_hook_router.py"     # 루트 marker
SD="$FIX/stage_artifacts/paper_recharge"
TODAY=$(date +%Y%m%d)
d(){ date -d "-$1 day" +%Y%m%d; }

mk_disc(){ printf '{"status":"mcp_ok","candidates":[{"arxiv_id":"2608.%s"}]}' "$2" > "$SD/mcp_discovery_$1.json"; }
mk_route(){ printf '{"date":"%s","papers":[]}' "$1" > "$SD/alpha_search_route_$1.json"; }
mk_done(){ printf 'date=%s\ndownloaded=%s\nmcp_candidates=1\n' "$1" "$2" > "$SD/paper_recharge_$1.done"; }

run_router(){   # → backlog=[...] 문자열
  rm -f "$FIX/.cache/scheduler_logs/paper_router_${TODAY}.log"
  rm -rf "$FIX/.cache/paper_router.lock"
  ( cd "$FIX" && QM_ROOT="$FIX" CLAUDE_PROJECT_DIR="$FIX" \
      QVEST_PAPER_ROUTER_ENABLE=1 QVEST_PAPER_ROUTER_DRYRUN=1 \
      bash "$SCRIPT" >/dev/null 2>&1 )
  grep -oE 'backlog=\[[^]]*\]' "$FIX/.cache/scheduler_logs/paper_router_${TODAY}.log" 2>/dev/null | tail -1
}

echo "== 양성 대조: 스탬프 없는 미소비 날짜를 잡는가 =="
# 08-15/16/17 실사고 재현 — discovery 있음 · route 없음 · .done **없음**
mk_disc "$(d 3)" 1111; mk_disc "$(d 4)" 2222
mk_disc "$TODAY" 9999; mk_done "$TODAY" 0
got=$(run_router)
for i in 3 4; do
  if [[ "$got" == *"$(d $i)"* ]]; then ok "스탬프 부재 미소비일 $(d $i) 포착"
  else ng "스탬프 부재 미소비일 $(d $i) 포착" "backlog=$got (구판 결함 재현)"; fi
done

echo "== 위반 주입 1: 이미 라우팅된 날짜는 잡지 않는가 =="
mk_route "$(d 3)"
got=$(run_router)
if [[ "$got" != *"$(d 3)"* ]]; then ok "route JSON 존재일 $(d 3) 제외"
else ng "route JSON 존재일 제외" "backlog=$got — 소비분 재처리"; fi
rm -f "$SD/alpha_search_route_$(d 3).json"

echo "== 위반 주입 2: discovery 없는 날짜는 잡지 않는가 =="
mk_done "$(d 5)" 26          # 스탬프·다운로드는 있으나 discovery 없음
got=$(run_router)
if [[ "$got" != *"$(d 5)"* ]]; then ok "discovery 부재일 $(d 5) 제외 (라우팅 소스 없음)"
else ng "discovery 부재일 제외" "backlog=$got"; fi

echo "== 위반 주입 3: 상한을 넘겨도 무한 팽창하지 않는가 =="
for i in 1 2 5 6; do mk_disc "$(d $i)" "77$i"; done
got=$(QVEST_PAPER_ROUTER_BACKLOG_MAX=2 run_router)
n=$(printf '%s' "$got" | tr ',' '\n' | grep -cE '[0-9]{8}')
if [ "$n" -le 2 ]; then ok "BACKLOG_MAX=2 준수 (실측 ${n}건)"
else ng "BACKLOG_MAX 준수" "${n}건 합류 — 상한 무효"; fi

echo "== 위반 주입 3b: 상한이 걸릴 때 만료 임박분을 살리는가 (순서) =="
# ★상한은 '무엇을 버릴지' 를 정한다 — 오름차순으로 채우면 7일 창을 곧 이탈할
#   가장 오래된 날짜가 잘려 나간다(무경보 영구 좌초). 오래된 것부터 채워야 한다.
for i in 2 7; do mk_disc "$(d $i)" "88$i"; done
got=$(QVEST_PAPER_ROUTER_BACKLOG_MAX=1 run_router)
if [[ "$got" == *"$(d 7)"* ]]; then ok "상한 1 → 최고령 $(d 7) 선택 (만료 임박분 우선)"
else ng "만료 임박 우선" "backlog=$got — 최신부터 채워 오래된 것이 무경보로 이탈"; fi

echo "== 위반 주입 4: 동시 인스턴스가 차단되는가 (자체 락) =="
rm -rf "$FIX/.cache/paper_router.lock"; mkdir -p "$FIX/.cache/paper_router.lock"
echo "$$" > "$FIX/.cache/paper_router.lock/pid"        # 살아있는 PID = 이 셸
rm -f "$FIX/.cache/scheduler_logs/paper_router_${TODAY}.log"
( cd "$FIX" && QM_ROOT="$FIX" CLAUDE_PROJECT_DIR="$FIX" \
    QVEST_PAPER_ROUTER_ENABLE=1 QVEST_PAPER_ROUTER_DRYRUN=1 \
    bash "$SCRIPT" >/dev/null 2>&1 )
if grep -q "다른 인스턴스 실행 중" "$FIX/.cache/scheduler_logs/paper_router_${TODAY}.log" 2>/dev/null; then
  ok "생존 PID 락 → 2번째 인스턴스 skip"
else ng "동시 인스턴스 차단" "락이 있는데 진행함 — 덮어쓰기 재발 가능"; fi

echo "== 양성 대조 2: 죽은 PID 락은 회수되는가 (fail-closed 과잉 방지) =="
rm -rf "$FIX/.cache/paper_router.lock"; mkdir -p "$FIX/.cache/paper_router.lock"
echo "999999" > "$FIX/.cache/paper_router.lock/pid"     # 존재하지 않는 PID
rm -f "$FIX/.cache/scheduler_logs/paper_router_${TODAY}.log"
( cd "$FIX" && QM_ROOT="$FIX" CLAUDE_PROJECT_DIR="$FIX" \
    QVEST_PAPER_ROUTER_ENABLE=1 QVEST_PAPER_ROUTER_DRYRUN=1 \
    bash "$SCRIPT" >/dev/null 2>&1 )
if grep -q "stale lock 회수" "$FIX/.cache/scheduler_logs/paper_router_${TODAY}.log" 2>/dev/null; then
  ok "죽은 PID 락 회수 후 진행 (영구 정지 방지)"
else ng "stale lock 회수" "회수 로그 없음 — 락 하나로 라우터가 영구 정지할 수 있음"; fi

echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
printf '{"test":"paper_router_backlog_axis","pass":%d,"fail":%d,"total":%d,"skipped":0}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
