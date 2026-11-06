#!/usr/bin/env bash
# run_daily_stress_task.sh — 예약 작업(Qvest_StressDaily) 실행기. 도훈 11-06 결정 "별도 예약 작업" · 같은 날 "매일 아침 받아보고 싶다 · 노트북 활성화 · 메인 PC 에서도".
#   ① 데이터 준비를 기다린다(60초 간격 · 상한 MAX_WAIT_MIN) — 둘 다 만족해야 시작:
#      (a) 밤 데이터 리프레시 잠금(/tmp/qm_daily_refresh.lock)이 없다
#      (b) 벤치(퀀티) 최신일 ≥ KRX 직전 거래일 — 정본 판정 = 02_Infrastructure/data/krx_holidays.py currency(부팅 · ensure_data_current 와 같은 판정)
#         ★(b) 를 둔 이유: 04:00 에 리프레시가 아직 시작 전이면 잠금이 없어 (a) 만으로는 묵은 데이터로 일보가 나간다.
#   ② run_daily_stress.sh(ECOS/FRED 직접 수급 → 지수 v1 → 차트 → 해설 → PDF · 엑셀 → 방법론)를 돌린다.
#   ③ 종료 코드 = 체인의 종료 코드(작업 스케줄러 LastTaskResult) · 상한 초과 = rc 7(그날 건너뜀 — 묵은 데이터로 일보를 내지 않는다).
#      로그 = 감싼 실행기 로그(%LOCALAPPDATA%\Qvest\logs\Qvest_StressDaily.log) + daily/logs/task_*.log.
# 리프레시 · daily_refresh.sh 는 건드리지 않는다(원 세션 소유).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REP="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$REP/../../.." && pwd)"
PY="$ROOT/.venv_qvest_ml/Scripts/python.exe"
LOCK="${QVEST_REFRESH_LOCK:-/tmp/qm_daily_refresh.lock}"
MAX_WAIT_MIN="${STRESS_MAX_WAIT_MIN:-480}"   # 04:00 시작 → 늦어도 12:00 까지 데이터를 기다린다(11-06 실측: 리프레시 07:20~12:14)
POLL_SEC="${STRESS_POLL_SEC:-60}"
LOG_DIR="$REP/daily/logs"; mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/task_$(date +%Y%m%d_%H%M%S).log"
say() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
bench_state() {   # '0' 최신 · '1' 미최신 · 'NA' 판정 불가(판정 불가는 막지 않는다 — 리프레시 잠금이 1차 방어)
  [ "${STRESS_SKIP_BENCH_CHECK:-0}" = "1" ] && { echo "0|skip|skip"; return; }
  PYTHONUTF8=1 "$PY" "$ROOT/02_Infrastructure/data/krx_holidays.py" currency --no-fetch 2>/dev/null | tail -1
}

say "Qvest_StressDaily start · host=${COMPUTERNAME:-?} · lock=$LOCK · max_wait=${MAX_WAIT_MIN}m"
waited=0
while :; do
  bs="$(bench_state)"; st="${bs%%|*}"
  if [ ! -e "$LOCK" ] && [ "$st" != "1" ]; then break; fi
  if [ "$waited" -ge $((MAX_WAIT_MIN * 60)) ]; then
    say "★데이터 준비 안 됨 ${MAX_WAIT_MIN}분 초과(잠금 $([ -e "$LOCK" ] && echo 있음 || echo 없음) · 벤치 ${bs}) — 오늘은 건너뜀(묵은 데이터로 일보를 내지 않는다)"
    exit 7
  fi
  [ $((waited % 600)) -eq 0 ] && say "대기 — 리프레시 잠금 $([ -e "$LOCK" ] && echo 있음 || echo 없음) · 벤치 상태 ${bs}(state|벤치 최신일|직전 거래일) · ${waited}s"
  sleep "$POLL_SEC"; waited=$((waited + POLL_SEC))
done
[ "$waited" -gt 0 ] && say "데이터 준비 확인(${waited}s 대기 · 벤치 ${bs}) — 30초 뒤 시작" && sleep 30
[ "$waited" -eq 0 ] && say "데이터 준비 확인(대기 없음 · 벤치 ${bs})"

say "run_daily_stress.sh 시작"
bash "$REP/run_daily_stress.sh" >> "$LOG" 2>&1; rc=$?
say "run_daily_stress.sh 종료 rc=$rc · latest=$(tr -d '\n' < "$REP/daily/latest/latest.json" 2>/dev/null | cut -c1-160)"
exit $rc
