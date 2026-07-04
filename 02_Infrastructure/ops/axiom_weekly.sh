#!/usr/bin/env bash
# ★ 2026-07-04: 주간 axiom 사이클의 정규 경로 = Cleaner 통합 —
#   weekly_cleaner_sweep.R step [3.5] (토 09:00 Task Scheduler Qvest_WeeklyCleaner)이
#   harvester → cluster_extractor → promote 진단을 실행하고 cleaner_pending.json에
#   axiom_candidates 현황(n_pending/failing_axis_histogram/near_miss)을 기록,
#   다이제스트는 /cleaner 스킬이 수행한다. 본 스크립트는 수동/보조 실행용 retain
#   (weekly_report 포함 — cron 등록은 권장하지 않음, 이중 실행 방지).
#
# v8.0: 3-mode 2-tier axiom pipeline (weekly)
#   harvester → cluster_extractor → mode-local promote(INV-4 hurdle) → weekly_report(INV-3)
#   global 승격은 자동 X (cross-mode + backtested + AX-008 2/3 — promote_global.R 수동/조건부).
set -u
DIR=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot 2>/dev/null | head -1)
[ -z "$DIR" ] && DIR="G:/Quant_Module_Moltbot"
[ -d "$DIR" ] || { echo "[axiom_weekly] project root not found" >&2; exit 2; }
LOG="${QVEST_AXIOM_LOG:-/tmp/axiom_weekly.log}"
export CLAUDE_PROJECT_DIR="$DIR" PYTHONUTF8=1
# Windows-native 인터프리터 (anaconda python / R 4.5.2). 환경변수로 override.
PY="${QVEST_PY:-C:/Users/99922/AppData/Local/Programs/Python/Python312/python.exe}"
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
