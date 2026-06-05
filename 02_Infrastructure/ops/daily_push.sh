#!/usr/bin/env bash
#==============================================================================
# daily_push.sh — 매일 미푸시 commit을 origin으로 전송 (v7.2.1-boot 확장)
#
# crontab 예시 (매일 03:00):
#   0 3 * * * bash /mnt/c/Users/User/OneDrive/바탕\ 화면/Quant_Module_Moltbot/02_Infrastructure/ops/daily_push.sh
#
# 동작 (v7.2.1-boot 확장):
#   1. 모든 local branch (refs/heads/*) loop
#   2. tracked branch: ahead > 0 → push
#   3. 신규 branch (origin 미존재): -u 로 upstream 설정 + push
#   4. 네트워크 실패 시 로그만 (다음 날 재시도)
#
# 보완 관계:
#   - Stop event auto_push_on_stop.sh: 세션 종료 즉시 push (현 branch만)
#   - daily_push.sh (cron 03:00): 모든 branch 일괄 push (Stop hook fail 보완)
#
# 로그: /tmp/daily_push.log
#==============================================================================

set -u
LOG="/tmp/daily_push.log"
TS="$(date '+%Y-%m-%d %H:%M:%S')"

PROJECT=$(ls -d /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
if [ -z "$PROJECT" ]; then
  echo "$TS NO_PROJECT" >> "$LOG"; exit 1
fi
cd "$PROJECT" || { echo "$TS CD_FAIL" >> "$LOG"; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "$TS NOT_REPO" >> "$LOG"; exit 1; }

# Remote 확인
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "$TS NO_REMOTE" >> "$LOG"; exit 0
fi

# v7.2.1-boot: 모든 local branch loop (main + master 등 — 2026-05-13 rename)
TOTAL_OK=0
TOTAL_FAIL=0
TOTAL_UP=0
TOTAL_NEW=0

for BRANCH in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
  if git rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
    # Tracked branch — fetch + ahead 비교 + push
    if ! git fetch origin "$BRANCH" 2>>"$LOG"; then
      echo "$TS FETCH_FAIL branch=$BRANCH" >> "$LOG"
      TOTAL_FAIL=$((TOTAL_FAIL + 1))
      continue
    fi
    AHEAD=$(git rev-list --count "origin/$BRANCH..$BRANCH" 2>/dev/null || echo 0)
    if [ "$AHEAD" -eq 0 ]; then
      echo "$TS UP_TO_DATE branch=$BRANCH" >> "$LOG"
      TOTAL_UP=$((TOTAL_UP + 1))
      continue
    fi
    if git push origin "$BRANCH" >> "$LOG" 2>&1; then
      echo "$TS PUSH_OK branch=$BRANCH ahead=$AHEAD" >> "$LOG"
      TOTAL_OK=$((TOTAL_OK + 1))
    else
      echo "$TS PUSH_FAIL branch=$BRANCH ahead=$AHEAD — 다음 날 재시도" >> "$LOG"
      TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
  else
    # 신규 branch (origin 미존재) — -u 로 upstream 설정 + push
    if git push -u origin "$BRANCH" >> "$LOG" 2>&1; then
      echo "$TS NEW_BRANCH_PUSH_OK branch=$BRANCH" >> "$LOG"
      TOTAL_NEW=$((TOTAL_NEW + 1))
    else
      echo "$TS NEW_BRANCH_PUSH_FAIL branch=$BRANCH — 다음 날 재시도" >> "$LOG"
      TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
  fi
done

# 2026-05-04 patch: tag push 추가 (이전 v7.0~v7.2.1 tags origin 미push 갭 해소)
if git push origin --tags >> "$LOG" 2>&1; then
  echo "$TS TAGS_PUSH_OK" >> "$LOG"
else
  echo "$TS TAGS_PUSH_FAIL — 다음 날 재시도" >> "$LOG"
fi

echo "$TS DAILY_PUSH_SUMMARY ok=$TOTAL_OK new=$TOTAL_NEW up=$TOTAL_UP fail=$TOTAL_FAIL" >> "$LOG"
exit 0
