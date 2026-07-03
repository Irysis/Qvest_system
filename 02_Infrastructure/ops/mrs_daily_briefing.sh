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
DIR=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)

if [ -z "$DIR" ]; then
  echo "$TS [mrs_daily] PROJECT_ROOT not found" >> "$LOG"
  exit 1
fi

cd "$DIR"

# [분리 보호 2026-06-17 도훈] 상속된 QM_ROOT/CLAUDE_PROJECT_DIR가 별개 시스템(Qvest_Codex 등)을
#   가리키면 .tg_load_env()(CLAUDE_PROJECT_DIR→QM_ROOT 순)와 config.R가 잘못된 .env/캐시/차트 경로로
#   해석되어 원본 차트 미갱신 + 발송 채널 오염이 발생한다. 글로브로 확정한 원본 DIR로 강제 고정한다.
export QM_ROOT="$DIR"
export CLAUDE_PROJECT_DIR="$DIR"
export PYTHONUTF8=1

# 선행 cache 전제 체크 — 일간 regime signal 우선
REGIME_DAILY="$DIR/.cache/unified_regime_signal_daily.parquet"
REGIME_MONTHLY="$DIR/.cache/unified_regime_signal.parquet"

if [ ! -f "$REGIME_DAILY" ] && [ ! -f "$REGIME_MONTHLY" ]; then
  echo "$TS [mrs_daily] no regime signal cache — skip" >> "$LOG"
  exit 0
fi

echo "$TS [mrs_daily] start briefing v2.8" >> "$LOG"

# [외부화 2026-06-18 Q] 기존 멀티라인 `Rscript -e '...'` 블록은 Windows Git Bash 에서 첫 줄만
#   실행되는 함정(실증 확인)으로 레짐 브리핑 로직 전체가 no-op 되고 있었다(차트 미재생·발송 부재).
#   morning_steps/mrs_regime_send.R 로 분리 + 단일줄 source 호출로 회피(전 줄 실행 + UTF-8 정상).
Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/mrs_regime_send.R")' >> "$LOG" 2>&1

echo "$TS [mrs_daily] done" >> "$LOG"
exit 0
