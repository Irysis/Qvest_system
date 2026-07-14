#!/bin/bash
# run_prod_samples.sh — production _recompute_alpha_asof.R (2-3 noLayer4, current PG2 canonical)
# executed VERBATIM (read-only vs real tree) inside junction sandbox:
#   CLAUDE_PROJECT_DIR=SB -> script ROOT=SB; .cache/02_Infrastructure are junctions to real;
#   the script's only write target (stage_artifacts/WT_D20260425_010/alpha_scores.parquet) is a sandbox COPY.
# Purpose: Dohoon mandate 2026-07-14 — production-code direct parity for clean 268m panel (>=3 sample months).
set -u
SB="C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/3d6b0eb6-6786-4a56-916d-9681f94897fe/scratchpad/prod_sandbox"
PROD="C:/Users/99922/OneDrive/Quant_Module_Moltbot/05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/01_reproducible_code/_recompute_alpha_asof.R"
LOG="C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/plumbing_fq044_20260714/prod_samples_log.txt"
: > "$LOG"
for M in 2006-06-01 2013-09-01 2020-02-01 2026-03-01; do
  echo "===== PG2_AS_OF=$M $(date) =====" >> "$LOG"
  PG2_AS_OF=$M CLAUDE_PROJECT_DIR="$SB" Rscript -e "source('$PROD')" >> "$LOG" 2>&1
  echo "exit=$? for $M" >> "$LOG"
done
echo "ALL_PROD_SAMPLES_DONE" >> "$LOG"
