#!/usr/bin/env bash
# _cycle56a_run_all.sh — Sequential 5-cycle q15 strict-PIT training driver
# 도훈 mandate: 원래 +21d 약세 확률값 mandate 회복 (Cycle 48A 이후 q126 drift 정정)

set -uo pipefail
PROJECT_ROOT="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WS="${PROJECT_ROOT}/04_Research/decision_framework/bearish_forecast_v2_alt_data"
PY="${PROJECT_ROOT}/.venv_dpl/bin/python3"
OUT_DIR="${WS}/outputs/03_models/cycle56a_q15_strict_PIT"
LOG_DIR="${OUT_DIR}/_logs"
mkdir -p "${LOG_DIR}"

cd "${WS}"

SCRIPTS=(
  "167_53h_v5e_q15_strict.py"
  "168_53b_v5b_q15_strict.py"
  "169_53i_v5f_q15_strict.py"
  "170_54a_v3_q15_strict.py"
  "171_54a_v4_q15_strict.py"
)

START_TS=$(date +%s)
echo "[cycle56a] START $(date +%FT%T)" | tee "${LOG_DIR}/_driver.log"

for s in "${SCRIPTS[@]}"; do
  base=$(basename "${s}" .py)
  log="${LOG_DIR}/${base}.log"
  cyc_start=$(date +%s)
  echo "[cycle56a] >>> ${s} START $(date +%FT%T)" | tee -a "${LOG_DIR}/_driver.log"
  "${PY}" -u "scripts/${s}" > "${log}" 2>&1
  rc=$?
  cyc_end=$(date +%s)
  echo "[cycle56a] <<< ${s} END $(date +%FT%T) rc=${rc} elapsed=$((cyc_end - cyc_start))s" | tee -a "${LOG_DIR}/_driver.log"
  if [[ ${rc} -ne 0 ]]; then
    echo "[cycle56a] FAIL on ${s} — see ${log} (continuing remaining scripts)" | tee -a "${LOG_DIR}/_driver.log"
  fi
done

END_TS=$(date +%s)
TOTAL=$((END_TS - START_TS))
echo "[cycle56a] ALL DONE $(date +%FT%T) total=${TOTAL}s ($(printf '%.1f' $(echo "${TOTAL} / 60" | bc -l))min)" | tee -a "${LOG_DIR}/_driver.log"

# Aggregate
echo "[cycle56a] Running 172 aggregator..." | tee -a "${LOG_DIR}/_driver.log"
Rscript "scripts/172_q15_strict_PIT_aggregate.R" > "${LOG_DIR}/172_aggregate.log" 2>&1
agg_rc=$?
echo "[cycle56a] Aggregator rc=${agg_rc}" | tee -a "${LOG_DIR}/_driver.log"
exit 0
