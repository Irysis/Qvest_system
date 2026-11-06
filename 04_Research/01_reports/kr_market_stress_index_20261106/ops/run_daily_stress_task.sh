#!/usr/bin/env bash
# run_daily_stress_task.sh — 예약 작업(Qvest_StressDaily) 실행기. 도훈 11-06 결정 "별도 예약 작업".
#   ① 밤 데이터 리프레시 잠금(/tmp/qm_daily_refresh.lock — 해제 = [0c] 적재 검증 뒤 데이터 완료)이 풀릴 때까지 기다린다(60초 간격 · 상한 MAX_WAIT_MIN).
#   ② run_daily_stress.sh(ECOS/FRED 직접 수급 → 지수 v1 → 차트 → PDF · 엑셀)를 돌린다.
#   ③ 종료 코드 = 체인의 종료 코드(작업 스케줄러 LastTaskResult). 출력은 감싼 실행기의 로그(%LOCALAPPDATA%\Qvest\logs\<runner>.log)와
#      daily/logs/task_*.log 에 남는다.
# 리프레시 · daily_refresh.sh 는 건드리지 않는다(원 세션 소유). FRED 와이드 캐시(아침 체인 전용)는 이 체인의 입력이 아니다 —
# 지수는 FRED 를 직접 받는다(fetch_research_inputs.py).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REP="$(cd "$HERE/.." && pwd)"
LOCK="${QVEST_REFRESH_LOCK:-/tmp/qm_daily_refresh.lock}"
MAX_WAIT_MIN="${STRESS_MAX_WAIT_MIN:-240}"
POLL_SEC="${STRESS_POLL_SEC:-60}"
LOG_DIR="$REP/daily/logs"; mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/task_$(date +%Y%m%d_%H%M%S).log"
say() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

say "Qvest_StressDaily start · lock=$LOCK · max_wait=${MAX_WAIT_MIN}m"
waited=0
while [ -e "$LOCK" ]; do
  if [ "$waited" -ge $((MAX_WAIT_MIN * 60)) ]; then
    say "★리프레시 잠금이 ${MAX_WAIT_MIN}분 넘게 유지됨 — 오늘은 건너뜀(데이터 미완료 상태로 일보를 내지 않는다)"
    exit 7
  fi
  [ $((waited % 600)) -eq 0 ] && say "리프레시 진행 중(잠금 있음) — ${waited}s 대기"
  sleep "$POLL_SEC"; waited=$((waited + POLL_SEC))
done
[ "$waited" -gt 0 ] && say "잠금 해제 확인(${waited}s 대기) — 30초 뒤 시작" && sleep 30

say "run_daily_stress.sh 시작"
bash "$REP/run_daily_stress.sh" >> "$LOG" 2>&1; rc=$?
say "run_daily_stress.sh 종료 rc=$rc · latest=$(tr -d '\n' < "$REP/daily/latest/latest.json" 2>/dev/null | cut -c1-160)"
exit $rc
