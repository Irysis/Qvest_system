#!/bin/bash
# test_stage_timeout_and_recharge_stall.sh — 한 스테이지가 **그날 전체를 먹지 않는가** (2026-08-22)
#
# 왜 있나 (실측 08-22):
#   10:36:58  reboot 이 paper_recharge 락 획득(PID 1486)
#   10:38:31  다른 런: "another run is active (age 92s)"
#   11:40:20  다른 런: "another run is active (age 2923s)"   ← 48분째 살아있음
#   11:43:02  "lock 소유자 판정 불가 — age 3085s 로 skip"
#   ⇒ 10:36 런이 **51분 점유**했고 morning_run 은 [0/3] 에서 반환을 기다리다 멈췄다.
#     10:39 cron 은 "직전 실행 생존 중" 으로 종료 ⇒ **그날 파이프라인 통과 0회**.
#     실 무인 경로(test 제외) 미완주 6건 중 **4건이 [0/3] 정지**다.
#
# ★두 층을 구분한다 — 이걸 섞으면 도훈 지시와 충돌한다:
#   · 리서치 런의 시간제한(제거됨) = **일하는 런을 자르는** 문제였다. 18:10 에 alpha_package 를
#     다 내고 18:13 에 잘려 기록만 잃었다. 그래서 없앤 것이 옳다.
#   · 스테이지 상한(신설) = **아무 일도 안 하며 줄을 막는** 문제다. 락에 걸린 recharge 가
#     51분간 0바이트를 쓰며 그날 전체를 먹었다. 이건 자르는 게 아니라 **줄을 푸는 것**이다.
#
# ★1급 축은 "상한이 있는가" 가 아니라 **"정상 소요를 자르지 않는가"** 다.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
MR="$ROOT/02_Infrastructure/ops/morning_run.sh"
RR="$ROOT/02_Infrastructure/tools/paper_recharge_daily.R"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: $2"; }

echo "== 배선 축: morning_run [0/3] 에 스테이지 상한이 있는가 =="
if [ -f "$MR" ]; then
  grep -q 'QVEST_STAGE_TIMEOUT_MIN' "$MR" && ok "스테이지 상한 배선" \
    || ng "상한 부재" "한 스테이지가 그날 전체를 먹는다(실측 51분)"
  grep -q 'QVEST_STAGE_TIMEOUT_MIN:-20' "$MR" && ok "기본 20분 (정상 소요 1~2분 대비 넉넉)" \
    || ng "기본값" "너무 짧으면 일하는 런을 자른다"
  grep -q '다음 스테이지로 진행(체인 보존)' "$MR" && ok "초과 시 체인을 죽이지 않고 진행" \
    || ng "체인 중단" "한 스테이지 초과로 나머지를 못 돈다"
  grep -q 'stage_result "paper_recharge" "\$_prc"' "$MR" && ok "종료코드가 stage_result 로 전달(마커 발행)" \
    || ng "코드 전달" "초과가 경보로 안 남는다"
else
  ng "morning_run" "파일 부재"
fi

echo "== ★불변 축: env 0 이면 종전 동작(무제한) 인가 =="
grep -q 'if \[ "\$_stm" != "0" \]' "$MR" && ok "0 이면 timeout 미사용 (되돌리기가 env 하나)" \
  || ng "되돌림 불가" "코드 수정 없이 무제한으로 못 돌린다"

echo "== ★분리 축: 리서치 런 시간제한을 되살리지 않았는가 (도훈 지시 보존) =="
# 러너들의 claude 호출에 하드코딩 timeout 이 다시 들어가면 안 된다.
back=0
for f in paper_router_run.sh alpha_search_queue_run.sh mode_queue_research_run.sh factor_deep_recheck_run.sh; do
  [ -f "$ROOT/02_Infrastructure/ops/$f" ] || continue
  grep -q 'timeout 3000 "\$CLAUDE_BIN"' "$ROOT/02_Infrastructure/ops/$f" && back=$((back+1))
done
[ "$back" -eq 0 ] && ok "리서치 런 하드코딩 상한 0건 (지시 보존)" \
  || ng "지시 역행" "스테이지 상한을 넣으면서 리서치 런 상한을 되살렸다 (${back}건)"

echo "== 행동 축: 정상 소요는 자르지 않고 초과만 발동하는가 =="
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '#!/bin/bash\nsleep 2\n' > "$T/quick.sh"
if command -v timeout >/dev/null 2>&1; then
  timeout 60s bash "$T/quick.sh"; rc=$?
  [ "$rc" -eq 0 ] && ok "정상 소요(2초) + 60초 상한 → rc=0 (안 자름)" || ng "과잉 절단" "rc=$rc"
  timeout 1s bash "$T/quick.sh"; rc=$?
  [ "$rc" -eq 124 ] && ok "초과(2초 작업 + 1초 상한) → rc=124 (발동)" || ng "상한 무효" "rc=$rc"
else
  echo "  SKIP  timeout 명령 부재"
fi

echo "== paper_recharge 축: 살아있는 홀더의 장기 점유를 경보하는가 =="
if [ -f "$RR" ]; then
  grep -q 'reason=stalled_lock' "$RR" && ok "stalled_lock 경보 배선" \
    || ng "무음 점유" "alive 가지가 quit(0) 만 하고 조용하다 — 실측상 가장 흔한 경우"
  grep -q 'QVEST_STALL_ALERT_MIN' "$RR" && ok "문턱 외부화" || ng "문턱 하드코딩" "레인별 조정 불가"
  # 죽이지 않는가 (동시 실행 방지 보존)
  seg=$(awk '/isTRUE\(alive\)/{f=1} f{print} /quit\(status = 0\)/{if(f)exit}' "$RR")
  echo "$seg" | grep -qE 'unlink\(lock_dir|\.claim_lock\(\)' \
    && ng "락 탈취" "정체 판정으로 남의 락을 뺏는다 — 비가역" \
    || ok "경보만, 락 회수 없음"
  # 3분기 보존 (alive / dead / unknown)
  n=0
  for k in 'isTRUE(alive)' 'identical(alive, FALSE)' 'lock_owner_unknown'; do
    grep -qF "$k" "$RR" && n=$((n+1))
  done
  [ "$n" -eq 3 ] && ok "락 3분기 보존 (alive/dead/unknown)" || ng "분기 손상" "$n/3"
else
  ng "paper_recharge_daily.R" "파일 부재"
fi

echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
printf '{"test":"stage_timeout_and_recharge_stall","pass":%d,"fail":%d,"total":%d,"skipped":0}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
