#!/usr/bin/env bash
#==============================================================================
# daily_push.sh — 매일 미푸시 commit을 origin으로 전송
#
# crontab 예시 (매일 03:00):
#   0 3 * * * bash /mnt/c/Users/User/OneDrive/바탕\ 화면/Quant_Module_Moltbot/02_Infrastructure/ops/daily_push.sh
#
# 동작:
#   1. master와 origin/master 비교 → ahead 있으면 push
#   2. 네트워크 실패 시 로그만 남김 (다음 날 재시도)
#
# 로그: /tmp/daily_push.log
#==============================================================================

set -u
LOG="/tmp/daily_push.log"
TS="$(date '+%Y-%m-%d %H:%M:%S')"

PROJECT=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
if [ -z "$PROJECT" ]; then
  echo "$TS NO_PROJECT" >> "$LOG"; exit 1
fi
cd "$PROJECT" || { echo "$TS CD_FAIL" >> "$LOG"; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "$TS NOT_REPO" >> "$LOG"; exit 1; }

# Remote 확인
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "$TS NO_REMOTE" >> "$LOG"; exit 0
fi

# ahead 수 확인 (fetch 후)
git fetch origin master 2>>"$LOG" || { echo "$TS FETCH_FAIL" >> "$LOG"; exit 0; }
AHEAD=$(git rev-list --count origin/master..HEAD 2>/dev/null || echo 0)

if [ "$AHEAD" -eq 0 ]; then
  echo "$TS UP_TO_DATE" >> "$LOG"; exit 0
fi

# Push
if git push origin master >> "$LOG" 2>&1; then
  echo "$TS PUSH_OK ahead=$AHEAD" >> "$LOG"
  exit 0
else
  echo "$TS PUSH_FAIL ahead=$AHEAD — 다음 날 재시도" >> "$LOG"
  exit 0
fi
