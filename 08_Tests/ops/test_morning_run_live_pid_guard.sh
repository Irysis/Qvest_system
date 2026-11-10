#!/bin/bash
# test_morning_run_live_pid_guard.sh — morning_run 재시도의 "생존 PID" 가드 검사 (2026-08-22 신설)
#
# 왜 있나 (실사고 2026-08-21):
#   구판은 `.done` 마커 부재를 **직전 런의 사망**으로 단정했다. 그런데 morning_run 은
#   [0.5/3] paper_router 에서 최대 50분을 쓴다 — 그 동안 .done 은 원리적으로 없다.
#   07:06:27 런이 살아 있는데 07:10:02 cron 이 재시도로 진입해 라우터를 2개 띄웠고
#   (PID 35460 / 9824), 둘이 같은 route JSON 을 덮어써 07:19 판(22,901B · route_v2 ·
#   autorun 2편 · factor_candidates 4종)이 07:31 판(16,419B)으로 사라졌다. 07:58 에 3번째까지.
#   ★생존 판정에 쓸 PID 는 락 파일 첫 필드에 **이미 적혀 있었다** — 쓰고도 읽지 않았다.
#
# ★양방향: 살아있으면 막고(위반 주입), 죽었으면 막지 않는다(양성 대조 — 과잉 fail-closed 방지).
#
# ★격리 (2026-11-10 감사 레인 B 개정): 구판은 **운영 락**(/tmp/qm_morning_run_<오늘>.lock)을 백업 · 덮어쓰기 · 복원하고
#   **운영 루트**의 morning_run.sh 를 운영 로그(.cache/scheduler_logs/morning_run.log)에 trigger=test 로 돌렸다.
#   이 검사는 daily_refresh [8.x] 검사 배터리 안에서 매일 밤 · 아침 돌아, 운영 로그에 가짜 실행 15줄(11-06~11-10)을 남기고
#   superfan 아침 체인 감시가 읽는 로그를 오염시켰다. 가드가 회귀하면 운영 루트의 체인 단계가 실제로 시작될 수도 있었다.
#   → morning_run.sh 의 덮어쓰기(QVEST_MORNING_BASE · QVEST_MORNING_LOG · QVEST_MORNING_LOCK_DIR)로 임시 루트에서만 돈다.
#   임시 루트에는 단계 스크립트가 없으므로 가드가 뚫려도 실제 단계는 하나도 실행되지 않는다(전부 'skip (missing)').
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REAL_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
SCRIPT="$REAL_ROOT/02_Infrastructure/ops/morning_run.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: $2"; }

TMPR="$(mktemp -d)"; trap 'rm -rf "$TMPR"' EXIT
mkdir -p "$TMPR/root/.cache/scheduler_logs" "$TMPR/locks"
export QVEST_MORNING_BASE="$TMPR/root" QVEST_MORNING_LOG="$TMPR/mr.log" QVEST_MORNING_LOCK_DIR="$TMPR/locks"
unset QVEST_UNATTENDED
TODAY=$(date +%Y%m%d)
LOCK="$TMPR/locks/qm_morning_run_${TODAY}.lock"
PROD_LOG="$REAL_ROOT/.cache/scheduler_logs/morning_run.log"
prod_sz0=$(wc -c < "$PROD_LOG" 2>/dev/null || echo 0)

OUT="$TMPR/out.txt"
_off=0
snap(){ _off=$(wc -c < "$QVEST_MORNING_LOG" 2>/dev/null || echo 0); }
grab(){ tail -c "+$((_off+1))" "$QVEST_MORNING_LOG" 2>/dev/null > "$OUT"; }

echo "== 위반 주입: 직전 런이 **생존 중**이면 재시도를 막는가 =="
printf '%s @ %s trigger=test\n' "$$" "$(date)" > "$LOCK"
rm -f "${LOCK}.done" "${LOCK}.retry"
snap; timeout 60 bash "$SCRIPT" test >/dev/null 2>&1; grab
if grep -q "생존 중 — 재시도하지 않고 종료" "$OUT" 2>/dev/null \
   && ! grep -q "재시도 진입" "$OUT" 2>/dev/null \
   && ! grep -q "\[0/3\]" "$OUT" 2>/dev/null; then
  ok "생존 PID → 즉시 종료 (체인 미진입)"
else
  ng "생존 PID 차단" "$(grep -m3 -E '재시도|생존|\[0/3\]' "$OUT" 2>/dev/null | tr '\n' ' ')"
fi

echo "== 양성 대조: 직전 런이 **죽었으면** 막지 않는가 (과잉 fail-closed 방지) =="
printf '%s @ %s trigger=test\n' "999999" "$(date)" > "$LOCK"
rm -f "${LOCK}.done" "${LOCK}.retry"
snap; MORNING_MAX_RETRY=0 timeout 60 bash "$SCRIPT" test >/dev/null 2>&1; grab
if ! grep -q "생존 중 — 재시도하지 않고 종료" "$OUT" 2>/dev/null \
   && grep -q "재시도 상한 도달" "$OUT" 2>/dev/null; then
  ok "죽은 PID → 가드 침묵, 기존 재시도 로직으로 진행"
else
  ng "죽은 PID 통과" "$(grep -m3 -E '재시도|생존' "$OUT" 2>/dev/null | tr '\n' ' ')"
fi

echo "== 양성 대조 2: PID 를 못 읽는 락은 구판 경로로 가는가 (보수적) =="
printf 'garbage-no-pid\n' > "$LOCK"
rm -f "${LOCK}.done" "${LOCK}.retry"
snap; MORNING_MAX_RETRY=0 timeout 60 bash "$SCRIPT" test >/dev/null 2>&1; grab
if ! grep -q "생존 중 — 재시도하지 않고 종료" "$OUT" 2>/dev/null; then
  ok "PID 불명 → 차단하지 않음 (읽기 실패를 '생존'으로 단정하지 않음)"
else
  ng "PID 불명 처리" "읽기 실패를 생존으로 오판 — 하루 전체가 막힐 수 있음"
fi

echo "== 격리: 운영 로그가 한 바이트도 늘지 않았는가 =="
prod_sz1=$(wc -c < "$PROD_LOG" 2>/dev/null || echo 0)
[ "$prod_sz1" = "$prod_sz0" ] && ok "운영 morning_run.log 무접촉 ($prod_sz0 B)" \
  || ng "운영 로그 오염" "$prod_sz0 → $prod_sz1 B (동시에 실제 예약 실행이 돌았다면 그 몫일 수 있음)"

echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
printf '{"test":"morning_run_live_pid_guard","pass":%d,"fail":%d,"total":%d,"skipped":0}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
