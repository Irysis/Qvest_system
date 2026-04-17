#!/bin/bash
#==============================================================================
# Sequential runner: STR_012 → STR_013 → STR_014 → STR_016 → STR_015
# Run after DART pipeline completes
# Usage: bash run_dart_strategies.sh
# NOTE: Uses Rscript -e "source()" to avoid Korean path encoding bug
#==============================================================================

BASE="/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot"
LOG="$BASE/research_output/run_dart_strategies.log"

echo "$(date): Starting DART strategy sequence" | tee -a "$LOG"

# Verify DART data is ready
Rscript -e "
.libPaths(c('~/R/libs', .libPaths()))
suppressMessages({library(arrow); library(data.table)})
f <- '$BASE/.cache/fundamental_dart.parquet'
dt <- as.data.table(read_parquet(f))
if (nrow(dt) < 1000) stop('DART data insufficient: ', nrow(dt), ' rows')
cat('[OK] DART data ready:', nrow(dt), 'records,', uniqueN(dt\$Ticker), 'tickers\n')
" 2>&1 | tee -a "$LOG"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
  echo "$(date): ERROR - DART data not ready. Aborting." | tee -a "$LOG"
  exit 1
fi

run_strategy() {
  local name="$1"
  local path="$2"
  echo "" | tee -a "$LOG"
  echo "$(date): Running $name..." | tee -a "$LOG"
  Rscript -e ".libPaths(c('~/R/libs', .libPaths())); source('$path')" 2>&1 | tee -a "$LOG"
  if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "$(date): $name complete" | tee -a "$LOG"
  else
    echo "$(date): $name FAILED" | tee -a "$LOG"
  fi
}

run_strategy "STR_012 (Sloan Accrual)"    "$BASE/research_output/strategies/STR_012_sloan_accrual/run_all.R"
run_strategy "STR_013 (QMJ Quality)"      "$BASE/research_output/strategies/STR_013_qmj_quality/run_all.R"
run_strategy "STR_014 (Asset Growth)"     "$BASE/research_output/strategies/STR_014_asset_growth/run_all.R"
run_strategy "STR_016 (Composite Mispricing)" "$BASE/research_output/strategies/STR_016_composite_mispricing/run_all.R"

echo "" | tee -a "$LOG"
echo "$(date): All DART strategies complete (STR_012~014, 016). Check results in research_output/strategies/" | tee -a "$LOG"

# STR_015 is price-based (no DART needed) — only run here if not already running
if ! pgrep -f "STR_015" > /dev/null 2>&1; then
  run_strategy "STR_015 (Enhanced LowVol)" "$BASE/research_output/strategies/STR_015_lowvol_enhanced/run_all.R"
else
  echo "$(date): STR_015 already running, skipping." | tee -a "$LOG"
fi

echo "" | tee -a "$LOG"
echo "$(date): All strategies complete (STR_012~016). Check results in research_output/strategies/" | tee -a "$LOG"
