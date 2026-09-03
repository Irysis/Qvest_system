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
  # ★충실구현 대기가 있으면 먼저 처리한다 — active entry 없이는 강화가 못 돈다.
  #   자체 claim/게이트를 갖고 있어 대기가 없으면 즉시 종료한다.
  bash "$ROOT/02_Infrastructure/ops/rf_replication_auto.sh"
  # ★arm 생성 레인 (v10.2) — 기전 지도가 미측정 칸을 지목할 때만 발화한다.
  #   자체 claim·일 상한(1건)·포화 게이트를 갖고 있어 조건이 없으면 즉시 종료한다.
  bash "$ROOT/02_Infrastructure/ops/rf_overlay_propose.sh"
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
