#!/bin/bash
#==============================================================================
# MRS Daily Briefing — v2.8 (2026-04-24 최종 확정 양식)
#
# Cron: 30 7 * * 1-5 (평일 07:30 KST)
# 방식: tg_regime_briefing() 직접 호출 (v2.8 — text + 3 charts)
#   Chart 1: Daily Regime Score (12M) — EWMA/Raw 2-line + Category 색띠
#   Chart 2: 3-Layer Signal (Month-end + Latest Daily) — MSM/KTRI/VEA + MRS Deep Purple
#   Chart 3: KTRI 9-Quadrant Map (252d)
#
# 전제: 06:30 regime_data_refresh.sh 선행 (MSM/FRED/KTRI/signal 갱신)
# Log: /tmp/qm_mrs_daily.log
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

# 선행 cache 전제 체크 — 일간 regime signal 우선
REGIME_DAILY="$DIR/.cache/unified_regime_signal_daily.parquet"
REGIME_MONTHLY="$DIR/.cache/unified_regime_signal.parquet"

if [ ! -f "$REGIME_DAILY" ] && [ ! -f "$REGIME_MONTHLY" ]; then
  echo "$TS [mrs_daily] no regime signal cache — skip" >> "$LOG"
  exit 0
fi

echo "$TS [mrs_daily] start briefing v2.8" >> "$LOG"

Rscript -e '
  PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
  CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
  setwd(PROJECT_ROOT)
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/telegram/telegram_notify.R")
  tryCatch({
    tg_regime_briefing()
    cat("[mrs_daily] briefing sent OK\n")
  }, error = function(e) {
    cat(sprintf("[mrs_daily] ERR: %s\n", conditionMessage(e)))
  })
' >> "$LOG" 2>&1

echo "$TS [mrs_daily] done" >> "$LOG"
exit 0
