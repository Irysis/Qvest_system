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

# (v10 2026-09-02) Rscript 프로세스에만 유효 로케일을 준다 — Qvest_MorningReboot.bat 의 LC_ALL=C.UTF-8 은
#   bash 한글 파싱 방어용(REM v8.3 2026-07-10)이라 bat 은 건드리지 않고, R 은 그 값을 설정 못 해 C 로케일로 떠서
#   read.csv/한글 처리가 어긋났다(curated_sources_missing 거짓 경보). 같은 규약 = paper_router_run.sh 의 Rscript prefix.
LC_ALL='English_United States.utf8' exec Rscript "$PROJECT/02_Infrastructure/tools/paper_recharge_daily.R" "$@" >> "$LOG" 2>&1
