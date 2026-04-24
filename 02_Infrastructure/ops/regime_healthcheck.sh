#!/bin/bash
#==============================================================================
# regime_healthcheck.sh — 매일 cron 07:35 (mrs_daily_briefing 후)
# Session 70 Step 7 — 2026-04-24
#
# Cron 등록 예시 (※ 등록은 사용자 승인 필요):
#   35 7 * * * bash /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot/02_Infrastructure/ops/regime_healthcheck.sh
#
# 책임:
#   - regime_healthcheck.R 호출
#   - STALE/BROKEN/MISSING 감지 시 Telegram alert (tg_send_rich)
#   - /tmp/qm_regime_healthcheck.log 에 stdout/stderr 축적
#
# 금지:
#   - 기존 cache 수정 금지 (read-only 검사만)
#   - crontab 자동 등록 금지 (사용자 승인 별도)
#==============================================================================

set -u
LOG=/tmp/qm_regime_healthcheck.log
TS=$(date -Iseconds)
DIR=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)

if [ -z "$DIR" ]; then
  echo "$TS [regime_healthcheck] PROJECT_ROOT not found" >> "$LOG"
  exit 1
fi

cd "$DIR" || exit 1

Rscript -e '
  source("02_Infrastructure/regime/regime_healthcheck.R")
  res <- regime_health_check(alert_on_fail = TRUE,
                              severity_threshold = "WARN")
  cat(sprintf("[regime_healthcheck.sh] issues=%d alerted=%s\n",
              attr(res, "issues_n"),
              as.character(attr(res, "alerted"))))
' >> "$LOG" 2>&1

RC=$?
echo "$TS [regime_healthcheck] exit=$RC" >> "$LOG"
exit $RC
