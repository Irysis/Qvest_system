#!/usr/bin/env bash
#==============================================================================
# auto_commit_on_stop.sh — Claude Code Stop event hook
#
# 세션 종료 시 자동 commit.
# Push는 안 함 (daily_push.sh cron 또는 milestone_commit.sh가 담당).
#
# 동작:
#   1. secret 스캔 (Telegram token / API key / .env staging)
#   2. git add -A (gitignore 자동 적용)
#   3. 신규 파일 >100개면 abort (실수 방지)
#   4. commit with [auto-commit] prefix + timestamp
#
# 로그: /tmp/auto_commit.log
# 우회 env: QVEST_SKIP_AUTO_COMMIT=1
#==============================================================================

trap 'echo "{}"; exit 0' ERR
set -u

INPUT=$(cat 2>/dev/null || echo '{}')
LOG="/tmp/auto_commit.log"
TS="$(date '+%Y-%m-%d %H:%M:%S')"

# 우회 env
if [ "${QVEST_SKIP_AUTO_COMMIT:-0}" = "1" ]; then
  echo "$TS SKIP_ENV" >> "$LOG"
  echo '{}'; exit 0
fi

PROJECT=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
if [ -z "$PROJECT" ] || [ ! -e "$PROJECT/.git" ]; then
  echo '{}'; exit 0
fi
cd "$PROJECT" || { echo '{}'; exit 0; }
# git 작동 확인 (.git이 파일인 경우 — WSL 한글경로 gitlink)
git rev-parse --git-dir >/dev/null 2>&1 || { echo '{}'; exit 0; }

# 변경 없으면 skip
CHANGES=$(git status --porcelain 2>/dev/null | wc -l)
if [ "$CHANGES" -eq 0 ]; then
  echo "$TS NO_CHANGES" >> "$LOG"
  echo '{}'; exit 0
fi

# ─── Secret 스캔 ─────────────────────────────────────────────────────
# 1. Telegram bot token 패턴 (현재 저장된 것과 달라도 삼중 방어)
TOKEN_HITS=$(git diff --no-color HEAD 2>/dev/null | \
  grep -cE 'bot[0-9]{9,11}:A[A-Za-z0-9_-]{34,}' || echo 0)
# 2. 일반 API key / password hardcoded
GENERIC_HITS=$(git diff --no-color HEAD 2>/dev/null | \
  grep -ciE '^\+.*(api_?key|api_?secret|password|access_?token|private_?key)\s*[=:]\s*[\"'"'"'][A-Za-z0-9_+/=-]{24,}' || echo 0)
# 3. .env 실수 포함 여부
ENV_INCLUDED=0
git status --porcelain 2>/dev/null | awk '{print $2}' | grep -q '^\.env$' && ENV_INCLUDED=1

if [ "$TOKEN_HITS" -gt 0 ] || [ "$GENERIC_HITS" -gt 0 ] || [ "$ENV_INCLUDED" -eq 1 ]; then
  echo "$TS SECRET_ABORT token=$TOKEN_HITS generic=$GENERIC_HITS env=$ENV_INCLUDED" >> "$LOG"
  MSG="⚠️ [auto-commit] Secret 탐지로 자동 commit 중단."
  MSG+=" token=$TOKEN_HITS generic=$GENERIC_HITS env=$ENV_INCLUDED."
  MSG+=" /tmp/auto_commit.log 확인 후 수동 정리 필요."
  MSG_ESC=$(printf '%s' "$MSG" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"Stop\",\"additionalContext\":$MSG_ESC}}"
  exit 0
fi

# ─── Staging (gitignore 자동 적용) ──────────────────────────────────
git add -A 2>>"$LOG"

# 신규 파일 과다 abort (실수 방지)
NEW_COUNT=$(git diff --cached --name-status 2>/dev/null | awk '$1=="A"' | wc -l)
if [ "$NEW_COUNT" -gt 100 ]; then
  echo "$TS TOO_MANY_NEW ($NEW_COUNT) — abort + reset" >> "$LOG"
  git reset HEAD -- . 2>>"$LOG"
  MSG="⚠️ [auto-commit] 신규 파일 $NEW_COUNT개 (>100) — 실수 방지로 abort. 수동 검토 후 커밋 필요."
  MSG_ESC=$(printf '%s' "$MSG" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"Stop\",\"additionalContext\":$MSG_ESC}}"
  exit 0
fi

STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l)
if [ "$STAGED" -eq 0 ]; then
  echo "$TS NO_STAGED" >> "$LOG"
  echo '{}'; exit 0
fi

# ─── Commit ──────────────────────────────────────────────────────────
SUMMARY="$(git diff --cached --shortstat 2>/dev/null | head -1)"
SESSION_TAG="${QVEST_SESSION_TAG:-Session $(date +%Y%m%d)}"

git commit -m "$(cat <<COMMIT_EOF
[auto-commit] $TS — $STAGED files

$SUMMARY

자동 생성 (Stop hook). $SESSION_TAG 세션 변경분 보존.
Secret 스캔 통과. Push는 milestone hook 또는 daily cron.

Co-Authored-By: Claude Code (Stop hook) <noreply@anthropic.com>
COMMIT_EOF
)" > /tmp/auto_commit_last.log 2>&1

if [ $? -eq 0 ]; then
  HASH=$(git rev-parse --short HEAD)
  echo "$TS AUTO_COMMIT $HASH staged=$STAGED" >> "$LOG"
  MSG="✅ [auto-commit] $HASH — $STAGED files committed. Push는 milestone/cron으로 자동."
  MSG_ESC=$(printf '%s' "$MSG" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"Stop\",\"additionalContext\":$MSG_ESC}}"
else
  echo "$TS COMMIT_FAILED" >> "$LOG"
  cat /tmp/auto_commit_last.log >> "$LOG"
  echo '{}'
fi
exit 0
