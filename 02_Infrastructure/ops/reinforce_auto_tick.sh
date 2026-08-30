#!/usr/bin/env bash
# reinforce_auto_tick.sh — 강화 무인 러너 스케줄 진입점 (2026-08-30)
#   스케줄러가 이 파일만 부른다. 러너 자체는 kill switch·claim·daily_cap 을 스스로 본다.
#   1 tick = 1 칸(백테스트 ~15분). daily_cap 이 하루 총량을 막는다.
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$ROOT" || exit 1
TODAY=$(date +%Y%m%d)
LOG="$ROOT/.cache/scheduler_logs/reinforce_auto_${TODAY}.log"
mkdir -p "$(dirname "$LOG")"
{
  echo "=== $(date -Iseconds) tick 시작 ==="
  MODE=$("${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}" -c "
import io,json,sys
try: print(json.loads(io.open(r'$ROOT/06_Registry/reinforce_auto_config.json','rb').read().decode('utf-8')).get('mode','sequential'))
except Exception: print('sequential')" 2>/dev/null)
  if [ "$MODE" = "parallel" ]; then
    Rscript "$ROOT/02_Infrastructure/ops/reinforce_auto_parallel.R"
  else
    Rscript "$ROOT/02_Infrastructure/ops/reinforce_auto_run.R"
  fi
  echo "=== $(date -Iseconds) tick 종료 rc=$? ==="
} >> "$LOG" 2>&1
