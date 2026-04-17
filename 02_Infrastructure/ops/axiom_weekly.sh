#!/usr/bin/env bash
# Sprint 4 AX-P3: Weekly axiom pipeline
# 매주 1회 실행 (crontab 등록 권장):
#   0 3 * * 1 bash /path/to/02_Infrastructure/ops/axiom_weekly.sh
#
# 수행: harvester → cluster_extractor → 신규 candidate 승격 시도

set -u
DIR=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
[ -z "$DIR" ] && { echo "[axiom_weekly] project root not found" >&2; exit 2; }
LOG="${QVEST_AXIOM_LOG:-/tmp/axiom_weekly.log}"
cd "$DIR" || exit 2

echo "=== $(date -Iseconds) axiom_weekly start ===" >> "$LOG"

QVEST_PROJECT_DIR="$DIR" python3 "$DIR/02_Infrastructure/axiom/lcode_harvester.py" >> "$LOG" 2>&1
QVEST_PROJECT_DIR="$DIR" python3 "$DIR/02_Infrastructure/axiom/cluster_extractor.py" >> "$LOG" 2>&1

# candidate 순회하며 promote 시도 (pending_5axis 상태만)
for cand in "$DIR/qepm/memory/axioms/candidates/CAND_"*.json; do
  [ -f "$cand" ] || continue
  echo "--- promote attempt: $(basename "$cand") ---" >> "$LOG"
  QVEST_PROJECT_DIR="$DIR" Rscript "$DIR/02_Infrastructure/axiom/promote.R" "$cand" \
    >> "$LOG" 2>&1 || true
done

echo "=== $(date -Iseconds) axiom_weekly end ===" >> "$LOG"
