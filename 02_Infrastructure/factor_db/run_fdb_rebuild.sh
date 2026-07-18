#!/usr/bin/env bash
#==============================================================================
# run_fdb_rebuild.sh — fdb_daily rebuild, ONE R PROCESS PER PHASE.
#
# Why per-phase processes (2026-07-18 postmortem):
#   The 2026-07-17 run did phase6 -> phase7 in a SINGLE Rscript session and died
#   at phase7 [5/6] on the first parquet read with [Windows error 1224]
#   (arrow mmap section from phase6's write_parquet still held by the process).
#   The historically-successful 2026-06-08 build ran each phase as its own
#   Rscript process. So: never chain phases in one R process.
#
# Usage:
#   bash run_fdb_rebuild.sh        # FULL: phase6 (DELETES all) + 7 + 8
#   bash run_fdb_rebuild.sh 7      # RESUME: phase7 + 8 (additive, no delete)
#   bash run_fdb_rebuild.sh 8      # phase8 only
#
# Preconditions: AC power + no sleep + a fresh backup. phase6 step [0/8]
#   deletes ALL fdb_daily parquet before rebuild — must run to completion.
#==============================================================================
set -uo pipefail
START="${1:-6}"
INFRA="C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure"
RS="/c/Program Files/R/R-4.5.2/bin/Rscript.exe"
TS() { date '+%Y-%m-%d %H:%M:%S'; }
cd "$INFRA" || { echo "cannot cd $INFRA"; exit 2; }
[ -x "$RS" ] || { echo "Rscript not found: $RS"; exit 2; }

echo "[run_fdb_rebuild] START_PHASE=$START @ $(TS)"
[ "$START" -ge 7 ] && echo "[run_fdb_rebuild] RESUME mode — phase6 skipped, no delete (additive merge onto existing files)"

for P in 6 7 8; do
  if [ "$P" -lt "$START" ]; then
    echo "[run_fdb_rebuild] skip phase$P (< START=$START)"
    continue
  fi
  echo "[run_fdb_rebuild] ===== phase$P begin @ $(TS) ====="
  # each phase in its OWN R process — ASCII-only -e (source path has no backslash)
  "$RS" -e "source('factor_db/factor_db_daily_phase${P}.R')"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "[run_fdb_rebuild] !!! phase$P FAILED rc=$rc @ $(TS) — ABORT (fdb_daily left partial)"
    exit "$rc"
  fi
  echo "[run_fdb_rebuild] ===== phase$P done rc=0 @ $(TS) ====="
done
echo "[run_fdb_rebuild] ALL PHASES >= $START COMPLETE @ $(TS)"
