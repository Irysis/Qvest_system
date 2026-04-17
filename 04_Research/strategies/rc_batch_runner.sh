#!/bin/bash
# RC Batch Runner — STR_1152~1160 순차 실행
# Usage: bash rc_batch_runner.sh
set -e
cd "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"

STRATEGIES=(
  "STR_1153_korean_credit_cycle"
  "STR_1154_yield_curve_switch"
  "STR_1155_twin_regime"
  "STR_1156_krw_factor_tilt"
  "STR_1157_vol_regime_3state"
  "STR_1158_economic_surprise"
  "STR_1159_rc_batch"
  "STR_1160_rc_batch"
  "STR_1161_rc_batch"
  "STR_1162_rc_batch"
  "STR_1163_rc_batch"
  "STR_1164_rc_batch"
  "STR_1165_rc_batch"
  "STR_1166_rc_batch"
  "STR_1167_rc_batch"
  "STR_1168_rc_batch"
)

for strat in "${STRATEGIES[@]}"; do
  dir="research_output/strategies/$strat"
  if [ ! -f "$dir/run_all.R" ]; then
    echo "[SKIP] $strat — no run_all.R"
    continue
  fi
  if [ -f "$dir/output/performance.csv" ]; then
    echo "[SKIP] $strat — already has results"
    continue
  fi
  echo ""
  echo "================================================================"
  echo "[$(date '+%H:%M:%S')] STARTING: $strat"
  echo "================================================================"
  cd "$dir"
  Rscript -e 'source("run_all.R")' 2>&1 || echo "[ERROR] $strat failed"
  cd "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
  echo "[$(date '+%H:%M:%S')] DONE: $strat"
done

echo ""
echo "================================================================"
echo "BATCH COMPLETE — Results summary:"
echo "================================================================"
for strat in "${STRATEGIES[@]}"; do
  perf="research_output/strategies/$strat/output/performance.csv"
  if [ -f "$perf" ]; then
    echo "$strat: $(head -2 $perf | tail -1)"
  else
    echo "$strat: NO RESULTS"
  fi
done
