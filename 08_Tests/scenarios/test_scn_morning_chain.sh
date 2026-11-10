#!/bin/bash
# test_scn_morning_chain.sh — 아침 체인(morning_run.sh) 운영 시나리오 시험 (2026-11-10 감사 레인 B)
#
# 실제 morning_run.sh 를 임시 루트에서 돌린다(QVEST_MORNING_BASE · _LOG · _LOCK_DIR · _STAGE_LOG_DIR).
#   임시 루트의 단계 스크립트는 모의본(즉시 끝나거나 · 실패하거나 · 멈춘다)이라 수집기 · 리프레시 · 텔레그램은 하나도 안 돈다.
#   경보 발송 차단 = QVEST_UNATTENDED 해제 + QVEST_NO_ALERT=1 (sched_alert_should_send 가 둘 다 '발송 안 함').
#
# 시나리오
#   S1 정상 흐름 — 모든 단계 exit 0 → 완주 줄 · .done 마커
#   S2 중간 단계 실패 — paper_router 가 exit 3 · 자기 경보 없음 → 체인은 계속(다음 단계 실행) · 오케스트레이터가 stage_exit 마커를 대신 남김
#   S3 재실행 — 같은 날 다시 부르면: 경보 마커가 있으니 재시도 진입(1/3) · 상한 넘으면 skip
#   S4 무경보 완주 뒤 재실행 — 'already ran today' 로 skip (중복 실행 없음)
#   S5 멈춘 단계 — paper_recharge 가 30초 잠듦 · 상한 3초(QVEST_STAGE_TIMEOUT_MIN=0.05) → 상한 줄 · 다음 단계로 진행
#   S6 동시 실행 — 살아 있는 PID 의 락이 있으면 체인에 들어가지 않는다
#   S7 격리 — 운영 morning_run.log · 운영 /tmp/qm_morning.log 크기 불변
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REAL_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
MR="$REAL_ROOT/02_Infrastructure/ops/morning_run.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: $2"; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/root"; mkdir -p "$R/02_Infrastructure/ops" "$R/.cache/scheduler_logs" "$R/.cache/scheduler_alerts" "$T/locks" "$T/stage"
cp "$REAL_ROOT/02_Infrastructure/ops/_sched_failure_classify.sh" "$R/02_Infrastructure/ops/"
export QVEST_MORNING_BASE="$R" QVEST_MORNING_LOG="$T/mr.log" QVEST_MORNING_LOCK_DIR="$T/locks" QVEST_MORNING_STAGE_LOG_DIR="$T/stage"
export QVEST_NO_ALERT=1 QVEST_PY=""; unset QVEST_UNATTENDED
: > "$QVEST_MORNING_LOG"
TODAY=$(date +%Y%m%d); LOCK="$T/locks/qm_morning_run_${TODAY}.lock"
PROD_MR="$REAL_ROOT/.cache/scheduler_logs/morning_run.log"; PROD_MB="/tmp/qm_morning.log"
p0=$(wc -c < "$PROD_MR" 2>/dev/null || echo 0); m0=$(wc -c < "$PROD_MB" 2>/dev/null || echo 0)

stub(){ # $1=이름 $2=본문
  printf '#!/bin/bash\n%s\n' "$2" > "$R/02_Infrastructure/ops/$1"; }
reset_stubs(){
  for s in paper_recharge_daily.sh paper_router_run.sh paper_atlas_run.sh scheduler_task_health.sh cleaner_distill_run.sh \
           morning_briefing.sh mrs_daily_briefing.sh ensure_data_current.sh alerts_digest_build.sh; do
    stub "$s" "echo stub-$s ran >> \"$T/ran.txt\"; exit 0"
  done
}
fresh_day(){ rm -f "$LOCK" "$LOCK.done" "$LOCK.retry" "$T/ran.txt"; rm -f "$R/.cache/scheduler_alerts/"*.alert 2>/dev/null; }
run(){ _o=$(wc -c < "$QVEST_MORNING_LOG" 2>/dev/null || echo 0); timeout 60 bash "$MR" test >/dev/null 2>&1; echo $? > "$T/rc"
       tail -c "+$((_o+1))" "$QVEST_MORNING_LOG" > "$T/out.txt" 2>/dev/null; }
has(){ grep -q -- "$1" "$T/out.txt"; }

echo "== S1 정상 흐름 =="
reset_stubs; fresh_day; run
has "morning_run done" && ok "S1a 완주 줄" || ng "S1a 완주 줄" "$(tail -3 "$T/out.txt" | tr '\n' ' ')"
[ -f "$LOCK.done" ] && ok "S1b .done 마커" || ng "S1b .done 마커" "없음"
grep -q "stub-paper_recharge_daily.sh" "$T/ran.txt" 2>/dev/null && grep -q "stub-cleaner_distill_run.sh" "$T/ran.txt" \
  && ok "S1c 단계 모의본 실행(임시 루트)" || ng "S1c 단계 실행" "$(cat "$T/ran.txt" 2>/dev/null | tr '\n' ' ')"

echo "== S4 무경보 완주 뒤 재실행 = skip =="
run
has "already ran today" && ok "S4 같은 날 재실행 skip" || ng "S4 재실행 skip" "$(head -3 "$T/out.txt" | tr '\n' ' ')"

echo "== S2 중간 단계 실패 — 격리되는가 · 한 번 표식되는가 =="
reset_stubs; fresh_day
stub paper_router_run.sh "echo stub-router-fail >> \"$T/ran.txt\"; exit 3"
run
has "paper_router exit=3" && ok "S2a 실패 단계 exit 표기" || ng "S2a exit 표기" "$(grep router "$T/out.txt" | tr '\n' ' ')"
has "stage_exit_3" && ok "S2b 오케스트레이터가 stage_exit 경보 표식(자기 경보 없는 단계)" || ng "S2b 경보 표식" "-"
ls "$R/.cache/scheduler_alerts/paper_router_stage_exit_3_${TODAY}.alert" >/dev/null 2>&1 && ok "S2c 마커 파일 1개" || ng "S2c 마커" "없음"
grep -q "stub-paper_atlas_run.sh" "$T/ran.txt" && grep -q "stub-cleaner_distill_run.sh" "$T/ran.txt" \
  && ok "S2d 다음 단계 계속 실행(체인 미사망)" || ng "S2d 다음 단계" "$(cat "$T/ran.txt" | tr '\n' ' ')"

echo "== S3 경보 있는 날 재실행 = 재시도(상한 3) =="
run
has "재시도 진입 (1/3)" && ok "S3a 경보 마커 → 재시도 1/3" || ng "S3a 재시도" "$(head -3 "$T/out.txt" | tr '\n' ' ')"
nm=$(ls "$R/.cache/scheduler_alerts/" | grep -c "paper_router_stage_exit_3_${TODAY}")
[ "$nm" = "1" ] && ok "S3b 같은 실패 재발에도 마커 1개(1일 1회)" || ng "S3b 마커 수" "$nm"
echo 3 > "$LOCK.retry"; run   # 재시도 2회를 더 돈 것과 같은 상태(사유별 상한 = sched_retry_cap · 환경변수 상한은 경보 사유가 있으면 덮인다)
has "재시도 상한 도달 (3/3)" && ok "S3c 상한 3 도달 뒤 skip" || ng "S3c 상한" "$(head -3 "$T/out.txt" | tr '\n' ' ')"

echo "== S5 멈춘 단계 — 상한 뒤 다음 단계로 =="
reset_stubs; fresh_day
stub paper_recharge_daily.sh "sleep 30; exit 0"
_t0=$(date +%s); QVEST_STAGE_TIMEOUT_MIN=0.05 run; _dt=$(( $(date +%s) - _t0 ))
has "스테이지 상한" && ok "S5a 상한 초과 줄" || ng "S5a 상한 줄" "$(grep -m2 'paper_recharge' "$T/out.txt" | tr '\n' ' ')"
[ "$_dt" -lt 25 ] && ok "S5b 30초 멈춤을 기다리지 않음(${_dt}s)" || ng "S5b 소요" "${_dt}s"
grep -q "stub-paper_router_run.sh" "$T/ran.txt" && ok "S5c 다음 단계 진행" || ng "S5c 다음 단계" "-"

echo "== S6 동시 실행 — 생존 락 =="
reset_stubs; fresh_day; printf '%s @ x trigger=test\n' "$$" > "$LOCK"; run
has "생존 중" && [ ! -f "$T/ran.txt" ] && ok "S6 생존 PID → 단계 0개 실행" || ng "S6 생존 락" "$(cat "$T/ran.txt" 2>/dev/null | tr '\n' ' ')"

echo "== S7 격리 =="
p1=$(wc -c < "$PROD_MR" 2>/dev/null || echo 0); m1=$(wc -c < "$PROD_MB" 2>/dev/null || echo 0)
[ "$p1" = "$p0" ] && [ "$m1" = "$m0" ] && ok "S7 운영 로그 2종 무접촉" || ng "S7 운영 로그" "morning_run $p0→$p1 · qm_morning $m0→$m1 (실제 예약 실행과 겹쳤을 수 있음)"

echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
printf '{"test":"scn_morning_chain","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
