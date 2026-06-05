#!/usr/bin/env bash
# v8.0: 3-mode 2-tier axiom pipeline (weekly cron)
#   harvester → cluster_extractor → mode-local promote(INV-4 hurdle) → weekly_report(INV-3)
#   global 승격은 자동 X (cross-mode + backtested + AX-008 2/3 — promote_global.R 수동/조건부).
#   crontab 권장: 0 3 * * 1 bash /g/Quant_Module_Moltbot/02_Infrastructure/ops/axiom_weekly.sh
set -u
DIR=$(ls -d /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot 2>/dev/null | head -1)
[ -z "$DIR" ] && DIR="G:/Quant_Module_Moltbot"
[ -d "$DIR" ] || { echo "[axiom_weekly] project root not found" >&2; exit 2; }
LOG="${QVEST_AXIOM_LOG:-/tmp/axiom_weekly.log}"
export CLAUDE_PROJECT_DIR="$DIR" PYTHONUTF8=1
# Windows-native 인터프리터 (anaconda python / R 4.5.2). 환경변수로 override.
PY="${QVEST_PY:-C:/Users/User/anaconda3/python.exe}"
RS="${QVEST_RSCRIPT:-C:/Program Files/R/R-4.5.2/bin/Rscript.exe}"
cd "$DIR" || exit 2

echo "=== $(date -Iseconds) axiom_weekly v8.0 start ===" >> "$LOG"

"$PY" "$DIR/02_Infrastructure/axiom/lcode_harvester.py"   >> "$LOG" 2>&1
"$PY" "$DIR/02_Infrastructure/axiom/cluster_extractor.py" >> "$LOG" 2>&1

# mode-local promote 시도 (pending candidate 순회; INV-4 5축 hurdle 미달은 review_log/AX-PENDING)
for cand in "$DIR/qepm/memory/axioms/candidates/CAND_"*.json; do
  [ -f "$cand" ] || continue
  echo "--- promote: $(basename "$cand") ---" >> "$LOG"
  "$RS" "$DIR/02_Infrastructure/axiom/promote.R" "$cand" >> "$LOG" 2>&1 || true
done

# 주간 점검 리포트 (INV-3: proxy/global 검토요망 + 롤백후보 + enforcement confirm 대기)
"$RS" "$DIR/02_Infrastructure/axiom/axiom_weekly_report.R" ${QVEST_AXIOM_TELEGRAM:+--telegram} >> "$LOG" 2>&1 || true

echo "=== $(date -Iseconds) axiom_weekly end ===" >> "$LOG"
echo "[axiom_weekly] done — log: $LOG"
