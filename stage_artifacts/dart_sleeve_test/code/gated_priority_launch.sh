#!/usr/bin/env bash
# gated_priority_launch.sh — 감쇠구간 우선 백필을 budget-safe 하게 발사.
# ============================================================================
# 게이트(둘 다 충족 시 발사):
#   G1. 연대순 run(dart_backfill_pipeline.py) 프로세스 부재 = API 유휴 (동시 소비 방지, 020 회피).
#   G2. 오늘 DART daily cap(10k) 소진 회피: RESET_EPOCH(다음 00:00 KST) 이후 = 신규 budget.
# 발사 후: BF_START..BF_END 우선 수집. resumable. 완료 시 consolidate + sleeve rebuild + eval 자동.
# 로그: reports/gated_priority.log
# 사용: nohup bash gated_priority_launch.sh &   (또는 run_in_background)
# ============================================================================
set -u
cd "C:/Users/99922/OneDrive/Quant_Module_Moltbot" || exit 1
LOGF="stage_artifacts/dart_sleeve_test/reports/gated_priority.log"
mkdir -p "$(dirname "$LOGF")"
log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOGF"; }

BUDGET="${BUDGET:-6000}"          # daily reset 후 여유 budget (연대순 run 4000 과 합쳐도 10k 이내)
RESET_EPOCH="${RESET_EPOCH:-0}"   # 이 epoch 이후에만 발사 (0 = 게이트 G2 무시, G1만)
export BF_START="${BF_START:-2015-01}"
export BF_END="${BF_END:-2024-02}"

log "gate armed: BF=$BF_START..$BF_END budget=$BUDGET reset_after_epoch=$RESET_EPOCH"

chrono_alive(){
  # dart_backfill_pipeline.py python 프로세스 존재 여부
  powershell -Command "if (Get-CimInstance Win32_Process -Filter \"name='python.exe'\" -ErrorAction SilentlyContinue | Where-Object { \$_.CommandLine -like '*dart_backfill*' }) { 'Y' } else { 'N' }" 2>/dev/null | tr -d '[:space:]'
}

# G1: 연대순 run 종료 대기
while true; do
  a=$(chrono_alive)
  now=$(date +%s)
  if [ "$a" = "N" ] && [ "$now" -ge "$RESET_EPOCH" ]; then
    log "gates open (chrono idle, past reset) — launching priority backfill"
    break
  fi
  log "waiting (chrono_alive=$a, now=$now, reset=$RESET_EPOCH)"
  sleep 120
done

source .venv_qvest_ml/Scripts/activate 2>/dev/null || true
# single-runner lock: nohup 런처와 scheduled task 중복 발사 방지 (020 회피).
LOCK="stage_artifacts/dart_sleeve_test/reports/.priority_running.lock"
if [ -f "$LOCK" ]; then
  lp=$(cat "$LOCK" 2>/dev/null)
  if powershell -Command "if (Get-Process -Id $lp -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }" 2>/dev/null; then
    log "another priority runner (pid=$lp) active — this instance exits (dedup)"; exit 0
  fi
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
export MODE=backfill DART_DAILY_BUDGET="$BUDGET"
log "python backfill start ($BF_START..$BF_END, budget=$BUDGET) lock=$$"
python -u stage_artifacts/dart_parser_build/code/dart_backfill_pipeline.py >> "$LOGF" 2>&1
rc=$?
log "priority backfill run ended rc=$rc — consolidating + rebuilding sleeve + eval"

python stage_artifacts/dart_parser_build/code/consolidate_netbuy.py >> "$LOGF" 2>&1
python stage_artifacts/dart_sleeve_test/code/build_dart_sleeve.py >> "$LOGF" 2>&1
RUNTAG="dart_priority_$(date +%Y%m%d)" LAG=1 Rscript stage_artifacts/dart_sleeve_test/code/eval_dart_sleeve.R \
  DINSD_OFF DINSD_OFFB DINSD_NET DINSD_BRD >> "$LOGF" 2>&1
log "eval done — see reports/results_dart_priority_*.csv"
