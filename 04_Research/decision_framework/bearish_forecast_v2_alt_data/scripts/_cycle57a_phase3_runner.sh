#!/usr/bin/env bash
# _cycle57a_phase3_runner.sh — Cycle 57A Phase 3 sequential GPU runner
# Waits for cycle56a (167b template instances) to finish, then runs FIXED retrains.
#
# Mandate: substitute 53H_v5e + 53I_v5f BUGGY (FRED publication-lag bug) with FIXED retrains.
# Retain 53B/54A (v4a, NO FRED).
#
# Outputs:
#   outputs/03_models/cycle57a_q15_FRED_fixed/predictions_{cycle}_FIXED_seed{S}_y_tail_q15.parquet
#   outputs/03_models/cycle57a_q15_FRED_fixed/predictions_{cycle}_FIXED_mean5_y_tail_q15.parquet
#   outputs/03_models/cycle57a_q15_FRED_fixed/_logs/

set -uo pipefail
PROJECT_ROOT="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WS="${PROJECT_ROOT}/04_Research/decision_framework/bearish_forecast_v2_alt_data"
PY="${PROJECT_ROOT}/.venv_dpl/bin/python3"
OUT_DIR="${WS}/outputs/03_models/cycle57a_q15_FRED_fixed"
LOG_DIR="${OUT_DIR}/_logs"
mkdir -p "${LOG_DIR}"

cd "${WS}"

DRIVER_LOG="${LOG_DIR}/_driver.log"

echo "[cycle57a phase3] START $(date +%FT%T)" | tee "${DRIVER_LOG}"

# Wait for any 167b template instances (cycle56a 168/169/170/171) to finish
echo "[cycle57a phase3] Waiting for cycle56a GPU runs to finish..." | tee -a "${DRIVER_LOG}"
while pgrep -fa "167b_patchtst_strict_PIT_q15_template.py" >/dev/null 2>&1; do
  sleep 30
  echo "[cycle57a phase3] still waiting at $(date +%FT%T)..." >> "${DRIVER_LOG}"
done
echo "[cycle57a phase3] cycle56a GPU runs DONE — launching FIXED retrains" | tee -a "${DRIVER_LOG}"

SCRIPTS=(
  "174_53h_v5e_q15_strict_FIXED.py"
  "175_53i_v5f_q15_strict_FIXED.py"
)

START_TS=$(date +%s)
for s in "${SCRIPTS[@]}"; do
  base=$(basename "${s}" .py)
  log="${LOG_DIR}/${base}.log"
  cyc_start=$(date +%s)
  echo "[cycle57a phase3] >>> ${s} START $(date +%FT%T)" | tee -a "${DRIVER_LOG}"
  "${PY}" -u "scripts/${s}" > "${log}" 2>&1
  rc=$?
  cyc_end=$(date +%s)
  echo "[cycle57a phase3] <<< ${s} END $(date +%FT%T) rc=${rc} elapsed=$((cyc_end - cyc_start))s" | tee -a "${DRIVER_LOG}"
  if [[ ${rc} -ne 0 ]]; then
    echo "[cycle57a phase3] FAIL on ${s} — see ${log} (continuing remaining)" | tee -a "${DRIVER_LOG}"
  fi
done

END_TS=$(date +%s)
TOTAL=$((END_TS - START_TS))
echo "[cycle57a phase3] PHASE 3 DONE $(date +%FT%T) total=${TOTAL}s" | tee -a "${DRIVER_LOG}"

# Phase 4 aggregator
echo "[cycle57a phase3] Running 177 FIXED aggregator..." | tee -a "${DRIVER_LOG}"
Rscript "scripts/177_q15_FRED_fixed_aggregate.R" > "${LOG_DIR}/177_aggregate.log" 2>&1
agg_rc=$?
echo "[cycle57a phase3] Aggregator rc=${agg_rc}" | tee -a "${DRIVER_LOG}"

exit 0
