#!/bin/bash
#==============================================================================
# MRS Daily Briefing — 매일 MRS + regime 전송
# 2026-04-24 신규 (Pilot 3 이후 루틴 추가)
#
# Cron: 30 7 * * * (매일 07:30 KST)
# 목적: tg_regime_briefing() 호출 → 텔레그램 차트 + 지표 발송
#==============================================================================

set -u
LOG=/tmp/qm_mrs_daily.log
TS=$(date -Iseconds)
DIR=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)

if [ -z "$DIR" ]; then
  echo "$TS [mrs_daily] PROJECT_ROOT not found" >> "$LOG"
  exit 1
fi

cd "$DIR"

# Regime signal refresh 의존성 (unified_regime_signal.parquet)
# daily_refresh.sh (00:03) 또는 build_regime_signal_table() 선행 전제
# 없으면 스킵 + 경고만
REGIME_CACHE="$DIR/.cache/unified_regime_signal.parquet"
if [ ! -f "$REGIME_CACHE" ]; then
  echo "$TS [mrs_daily] unified_regime_signal.parquet 없음 — daily_refresh 선행 필요. skip." >> "$LOG"
  exit 0
fi

Rscript -e '
options(warn = 1)
source("02_Infrastructure/telegram/telegram_notify.R")
tryCatch({
  tg_regime_briefing()
  cat("[mrs_daily] briefing sent OK\n")
}, error = function(e) {
  cat(sprintf("[mrs_daily] ERROR: %s\n", conditionMessage(e)))
})
' >> "$LOG" 2>&1

echo "$TS [mrs_daily] done" >> "$LOG"
exit 0
