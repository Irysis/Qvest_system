#!/bin/bash
# Daily first-run paper recharge wrapper.
# Called by bootstrap/morning runner; the R script owns once-per-day locking.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
cd "$PROJECT"

LOG_DIR="$PROJECT/stage_artifacts/paper_recharge"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/paper_recharge_daily_$(date +%Y%m%d).log"

if ! command -v Rscript >/dev/null 2>&1; then
  echo "[paper-recharge] Rscript missing; skip" >> "$LOG"
  exit 0
fi

exec Rscript "$PROJECT/02_Infrastructure/tools/paper_recharge_daily.R" "$@" >> "$LOG" 2>&1
