#!/usr/bin/env bash
#==============================================================================
# auto_push_on_stop.sh — Claude Code Stop event hook (v7.2.1-boot 신규)
#
# auto_commit_on_stop.sh 다음에 실행. 현재 branch가 origin 대비 ahead면 push.
# 신규 branch면 -u 로 upstream 설정.
#
# 동작:
#   1. 현재 branch 확인
#   2. fetch origin (해당 branch만)
#   3. ahead 수 계산 — 0 이면 skip
#   4. push origin <branch> (upstream 없으면 -u)
#   5. 실패 시 log only (다음 Stop 또는 daily_push.sh가 재시도)
#
# 로그: /tmp/auto_push.log
# 우회 env: QVEST_SKIP_AUTO_PUSH=1
#
# Tier 매트릭스: Stop event Tier 1 (전역 trail consistency).
# Secret 검증은 auto_commit_on_stop.sh가 이미 처리 — 중복 안 함.
#==============================================================================

trap 'echo "{}"; exit 0' ERR
set -u
# (v8.1.2 2026-06-11) python stdio UTF-8 강제 — additionalContext lone surrogate(API 400) 수리
export PYTHONUTF8=1

INPUT=$(cat 2>/dev/null || echo '{}')
LOG="/tmp/auto_push.log"
TS="$(date '+%Y-%m-%d %H:%M:%S')"

# 우회 env
if [ "${QVEST_SKIP_AUTO_PUSH:-0}" = "1" ]; then
  echo "$TS SKIP_ENV" >> "$LOG"
  echo '{}'; exit 0
fi

PROJECT=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
if [ -z "$PROJECT" ] || [ ! -e "$PROJECT/.git" ]; then
  echo '{}'; exit 0
fi
cd "$PROJECT" || { echo '{}'; exit 0; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo '{}'; exit 0; }

# Remote 확인
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "$TS NO_REMOTE" >> "$LOG"; echo '{}'; exit 0
fi

# 현재 branch
BRANCH=$(git branch --show-current 2>/dev/null)
if [ -z "$BRANCH" ]; then
  echo "$TS DETACHED_HEAD — skip" >> "$LOG"
  echo '{}'; exit 0
fi

# Upstream 존재 여부
HAS_UPSTREAM=0
if git rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
  HAS_UPSTREAM=1
fi

# Fetch (해당 branch만 — 가벼움)
if [ "$HAS_UPSTREAM" = "1" ]; then
  if ! git fetch origin "$BRANCH" 2>>"$LOG"; then
    echo "$TS FETCH_FAIL branch=$BRANCH — 다음 Stop/daily 재시도" >> "$LOG"
    echo '{}'; exit 0
  fi
  AHEAD=$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo 0)
  if [ "$AHEAD" -eq 0 ]; then
    echo "$TS UP_TO_DATE branch=$BRANCH" >> "$LOG"
    echo '{}'; exit 0
  fi
fi

# Push
if [ "$HAS_UPSTREAM" = "1" ]; then
  if git push origin "$BRANCH" >> "$LOG" 2>&1; then
    HASH=$(git rev-parse --short HEAD)
    echo "$TS AUTO_PUSH_OK branch=$BRANCH ahead=$AHEAD hash=$HASH" >> "$LOG"
    MSG="[OK] [auto-push] $BRANCH @ $HASH - $AHEAD commits pushed."
  else
    echo "$TS AUTO_PUSH_FAIL branch=$BRANCH ahead=$AHEAD — 다음 Stop/daily 재시도" >> "$LOG"
    MSG="[WARN] [auto-push] $BRANCH push 실패 - log /tmp/auto_push.log"
  fi
else
  # 신규 branch — upstream 설정 + push
  if git push -u origin "$BRANCH" >> "$LOG" 2>&1; then
    HASH=$(git rev-parse --short HEAD)
    echo "$TS AUTO_PUSH_NEW_BRANCH branch=$BRANCH hash=$HASH" >> "$LOG"
    MSG="[OK] [auto-push] 신규 branch $BRANCH origin 등록 + push @ $HASH."
  else
    echo "$TS AUTO_PUSH_NEW_FAIL branch=$BRANCH" >> "$LOG"
    MSG="[WARN] [auto-push] 신규 branch $BRANCH push 실패 - log /tmp/auto_push.log"
  fi
fi

# 2026-05-04 patch: tag push 추가 (이전 v7.0~v7.2.1 tags origin 미push 갭 해소)
if git push origin --tags >> "$LOG" 2>&1; then
  echo "$TS TAGS_PUSH_OK" >> "$LOG"
else
  echo "$TS TAGS_PUSH_FAIL" >> "$LOG"
fi

MSG_ESC=$(printf '%s' "$MSG" | python3 -c "import sys,json; s=sys.stdin.buffer.read().decode('utf-8','replace'); print(json.dumps(''.join(ch if not(0xD800<=ord(ch)<=0xDFFF) else '?' for ch in s)))")
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"Stop\",\"additionalContext\":$MSG_ESC}}"
exit 0
