#!/bin/bash
#==============================================================================
# MRS Daily Briefing — v2 (Claude agent 분석 브리핑, b 스타일)
# 2026-04-24 신규
#
# Cron: 30 7 * * 1-5 (평일 07:30 KST)
# 방식: claude CLI non-interactive 호출 → Q-Lead agent가 MRS 분석 + Telegram 발송
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

# Regime cache 전제 체크 (daily_refresh 선행)
REGIME_CACHE="$DIR/.cache/unified_regime_signal.parquet"
if [ ! -f "$REGIME_CACHE" ]; then
  echo "$TS [mrs_daily] unified_regime_signal.parquet 없음 — daily_refresh 선행 필요. fallback: tg_regime_briefing() 기본." >> "$LOG"
  # Fallback: 기본 차트만 발송
  Rscript -e '
    source("02_Infrastructure/telegram/telegram_notify.R")
    tryCatch(tg_regime_briefing(),
             error = function(e) cat(sprintf("[mrs_daily] fallback err: %s\n", conditionMessage(e))))
  ' >> "$LOG" 2>&1
  exit 0
fi

# b 스타일 — Claude agent 분석 브리핑
CLAUDE_BIN="/home/quant/.local/bin/claude"
if [ ! -x "$CLAUDE_BIN" ]; then
  echo "$TS [mrs_daily] claude CLI 없음 — fallback shell briefing" >> "$LOG"
  Rscript -e '
    source("02_Infrastructure/telegram/telegram_notify.R")
    tryCatch(tg_regime_briefing(),
             error = function(e) cat(sprintf("[mrs_daily] fallback err: %s\n", conditionMessage(e))))
  ' >> "$LOG" 2>&1
  exit 0
fi

# Claude agent (Q-Lead 관점 MRS 분석 + Telegram 1회)
PROMPT='당신은 QEPM Q-Lead. 데일리 MRS 브리핑을 Telegram으로 발송하시오.

작업:
1. .cache/unified_regime_signal.parquet 최신 지표 로드 (Rscript)
2. 지표 해석 (score / regime category / 최근 변동)
3. 기존 PG2 (STR_1631 80% + STR_1656 20%) 리스크 시각 분석
4. 현 regime에 대한 전략 시사 1~2줄 (기존 Deployment 기준 action 필요 여부만)
5. source("02_Infrastructure/telegram/telegram_notify.R") 후 tg_send()로 **exactly 1회** 발송

포맷:
[Q-Lead] 📈 MRS 데일리 브리핑 — {YYYY-MM-DD}
━━━━━━━━━━━━━━━━━━━━━━━━━
📊 MRS: {score} / {category}
🔄 어제 대비: {delta}
📉 7일 trend: {trend}

🌡️ 주요 축
  VIX          {X}
  KRW/USD      {Y}
  FinStress    {Z}

🏛️ PG2 시각
  {현 regime에서 80/20 정상 or action 필요}

💡 Action
  {구체 권고 1줄}

parse_mode="" 빈 문자열. 분석 후 exit.'

"$CLAUDE_BIN" -p --permission-mode bypassPermissions "$PROMPT" >> "$LOG" 2>&1
RC=$?
echo "$TS [mrs_daily] claude exit=$RC" >> "$LOG"
exit 0
