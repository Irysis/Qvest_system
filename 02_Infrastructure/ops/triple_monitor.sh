#!/bin/bash
#==============================================================================
# triple_monitor.sh — Triple-layer live monitor wrapper
#
# Usage:
#   triple_monitor.sh daily         # Daily 약세예측 v1.3 monitor (07:15 cron)
#   triple_monitor.sh monthly       # Monthly V1aV3 Hybrid monitor (월초 1일)
#   triple_monitor.sh both          # 동시 실행 (수동 호출용)
#
# Triple-layer structure:
#   Layer 1: STR_1715 admit baseline (자동, 별도 인프라)
#   Layer 2: V1aV3 Hybrid (monthly) — live_monitor_v1av3.R
#   Layer 3: 약세예측 v1.3 (daily) — daily_bearish_monitor.R
#
# Crontab suggestion:
#   15 7 * * 1-5  cd /mnt/c/Users/.../Quant_Module_Moltbot && \
#                 02_Infrastructure/ops/triple_monitor.sh daily
#   0 9 1 * *     cd /mnt/c/Users/.../Quant_Module_Moltbot && \
#                 02_Infrastructure/ops/triple_monitor.sh monthly
#==============================================================================

set -e

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot 2>/dev/null | head -1)}}"
WS="$PROJECT_ROOT/04_Research/decision_framework/bearish_forecast_v2_alt_data"
LOG_DIR="$PROJECT_ROOT/qepm/observability"
mkdir -p "$LOG_DIR"

MODE="${1:-daily}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

LOG_FILE="$LOG_DIR/triple_monitor_$(date '+%Y%m%d').log"
echo "" >> "$LOG_FILE"
echo "━━━ $TIMESTAMP — triple_monitor.sh mode=$MODE ━━━" >> "$LOG_FILE"

run_daily() {
  # DISABLED Cycle 51 (2026-05-20): bearish forecast model backward label bug.
  # 02_target_builder.R line 39: shift(BM_Close, n=-H, type="lead") = x[t-H] (BACKWARD).
  # daily_bearish_monitor.R는 buggy era v1.3 model (PR-AUC 0.608 fabricated)을 의존하므로 disable.
  # 재가동: forward label 재baseline + AX-008 2/3 PASS + bear_date_audit.R PASS 후.
  # 자세한 사항: 04_Research/decision_framework/bearish_forecast_v2_alt_data/STATUS_BUGGY_ERA.md
  echo "[$(date '+%H:%M:%S')] DISABLED Cycle 51 — daily bearish monitor (backward label bug)" | tee -a "$LOG_FILE"
  echo "[$(date '+%H:%M:%S')] re-enable: forward baseline + bear_date_audit PASS 후" | tee -a "$LOG_FILE"
  return 0
  # cd "$WS" || exit 1
  # if Rscript scripts/daily_bearish_monitor.R --telegram >> "$LOG_FILE" 2>&1; then
  #   echo "[$(date '+%H:%M:%S')] ✅ daily monitor OK" | tee -a "$LOG_FILE"
  #   return 0
  # else
  #   echo "[$(date '+%H:%M:%S')] ❌ daily monitor FAILED — see $LOG_FILE" | tee -a "$LOG_FILE"
  #   return 1
  # fi
}

run_monthly() {
  # DISABLED Cycle 51 (2026-05-20): V1aV3 Hybrid (L-332/L-333)이 buggy era model에 직접 의존하지는
  # 않으나 (V1aV3 trigger는 KOSPI 6m DD 기반 model-free), bearish forecast model 전체 가족을
  # 안전 정지하여 forward label 재검증 cycle 후 재가동 결정 의무.
  # 재가동: forward baseline 측정 완료 + V1aV3 재실증 + 도훈 mandate.
  echo "[$(date '+%H:%M:%S')] DISABLED Cycle 51 — monthly V1aV3 monitor (bearish model family safety stop)" | tee -a "$LOG_FILE"
  return 0
  # # Only run if today is first business day of month (Mon-Fri AND day <= 7)
  # DAY=$(date '+%d')
  # DOW=$(date '+%u')  # 1=Mon 7=Sun
  # if [ "$MODE" = "monthly" ] && [ "$DAY" -gt 7 ]; then
  #   echo "[$(date '+%H:%M:%S')] Skip monthly (day=$DAY > 7)" | tee -a "$LOG_FILE"
  #   return 0
  # fi
  # if [ "$DOW" -gt 5 ]; then
  #   echo "[$(date '+%H:%M:%S')] Skip monthly (weekend, dow=$DOW)" | tee -a "$LOG_FILE"
  #   return 0
  # fi
  # echo "[$(date '+%H:%M:%S')] Running monthly V1aV3 Hybrid monitor..." | tee -a "$LOG_FILE"
  # cd "$WS" || exit 1
  # if Rscript scripts/live_monitor_v1av3.R --telegram >> "$LOG_FILE" 2>&1; then
  #   echo "[$(date '+%H:%M:%S')] ✅ monthly monitor OK" | tee -a "$LOG_FILE"
  #   return 0
  # else
  #   echo "[$(date '+%H:%M:%S')] ❌ monthly monitor FAILED" | tee -a "$LOG_FILE"
  #   return 1
  # fi
}

case "$MODE" in
  daily)
    run_daily
    ;;
  monthly)
    run_monthly
    ;;
  both)
    run_monthly
    run_daily
    ;;
  *)
    echo "Usage: $0 {daily|monthly|both}"
    exit 1
    ;;
esac

echo "━━━ DONE $(date '+%H:%M:%S') ━━━" >> "$LOG_FILE"
