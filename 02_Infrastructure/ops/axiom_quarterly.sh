#!/usr/bin/env bash
# Sprint 4 AX-P3: Quarterly axiom review
# 분기 1회 실행 (crontab):
#   0 4 1 */3 * bash /path/to/02_Infrastructure/ops/axiom_quarterly.sh
#
# 수행: review_all_active_axioms() — 열화/반증 축적분 deprecate 처리

set -u
DIR=$(ls -d /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
[ -z "$DIR" ] && { echo "[axiom_quarterly] project root not found" >&2; exit 2; }
LOG="${QVEST_AXIOM_LOG:-/tmp/axiom_quarterly.log}"
cd "$DIR" || exit 2

echo "=== $(date -Iseconds) axiom_quarterly start ===" >> "$LOG"

QVEST_PROJECT_DIR="$DIR" Rscript "$DIR/02_Infrastructure/axiom/review.R" --all \
  >> "$LOG" 2>&1

echo "=== $(date -Iseconds) axiom_quarterly end ===" >> "$LOG"
