#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
#==============================================================================
# auto_commit_on_stop.sh — Claude Code Stop event hook
#
# 세션 종료 시 자동 commit.
# Push는 안 함 (daily_push.sh cron 또는 milestone_commit.sh가 담당).
#
# 동작:
#   1. secret 스캔 (Telegram token / API key / .env staging)
#   2. git add -A (gitignore 자동 적용)
#   3. 신규 파일 >100개면 코어 경로만 선별 커밋 + 나머지 skip (HYG-01 2026-07-03,
#      구 전체-abort가 973회 연속 abort 유발 → 강등. 마커: /tmp/auto_commit_abort_marker.txt)
#   4. commit with [auto-commit] prefix + timestamp
#
# 로그: /tmp/auto_commit.log
# 우회 env: QVEST_SKIP_AUTO_COMMIT=1
#==============================================================================

trap 'echo "{}"; exit 0' ERR
set -u
# (v8.1.2 2026-06-11) python stdio를 UTF-8 강제 — locale(cp949) 디코딩이 additionalContext에
# lone surrogate(\udcXX)를 만들어 이후 모든 API 요청 400 (invalid high surrogate) 유발한 사건 수리.
export PYTHONUTF8=1

INPUT=$(cat 2>/dev/null || echo '{}')
LOG="/tmp/auto_commit.log"
TS="$(date '+%Y-%m-%d %H:%M:%S')"

# 우회 env
if [ "${QVEST_SKIP_AUTO_COMMIT:-0}" = "1" ]; then
  echo "$TS SKIP_ENV" >> "$LOG"
  echo '{}'; exit 0
fi

PROJECT=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
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
TOKEN_HITS=$( (git diff --no-color HEAD 2>/dev/null \
  | grep -cE 'bot[0-9]{9,11}:A[A-Za-z0-9_-]{34,}') 2>/dev/null || echo 0)
TOKEN_HITS=${TOKEN_HITS//[^0-9]/}; TOKEN_HITS=${TOKEN_HITS:-0}
# 2. 일반 API key / password hardcoded
GENERIC_HITS=$( (git diff --no-color HEAD 2>/dev/null \
  | grep -ciE '^\+.*(api_?key|api_?secret|password|access_?token|private_?key)[[:space:]]*[=:][[:space:]]*["'"'"'][A-Za-z0-9_+/=-]{24,}') 2>/dev/null || echo 0)
GENERIC_HITS=${GENERIC_HITS//[^0-9]/}; GENERIC_HITS=${GENERIC_HITS:-0}
# 3. .env 실수 포함 여부
ENV_INCLUDED=0
git status --porcelain 2>/dev/null | awk '{print $2}' | grep -q '^\.env$' && ENV_INCLUDED=1

if [ "$TOKEN_HITS" -gt 0 ] || [ "$GENERIC_HITS" -gt 0 ] || [ "$ENV_INCLUDED" -eq 1 ]; then
  echo "$TS SECRET_ABORT token=$TOKEN_HITS generic=$GENERIC_HITS env=$ENV_INCLUDED" >> "$LOG"
  MSG="[WARN] [auto-commit] Secret 탐지로 자동 commit 중단."
  MSG+=" token=$TOKEN_HITS generic=$GENERIC_HITS env=$ENV_INCLUDED."
  MSG+=" /tmp/auto_commit.log 확인 후 수동 정리 필요."
  MSG_ESC=$(printf '%s' "$MSG" | "$QVEST_PY_BIN" -c "import sys,json; s=sys.stdin.buffer.read().decode('utf-8','replace'); print(json.dumps(''.join(ch if not(0xD800<=ord(ch)<=0xDFFF) else '?' for ch in s)))")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"Stop\",\"additionalContext\":$MSG_ESC}}"
  exit 0
fi

# ─── Staging (gitignore 자동 적용) ──────────────────────────────────
git add -A 2>>"$LOG"

# 신규 파일 과다 시: 전체 abort → 코어 경로 선별 커밋으로 강등 (HYG-01, 2026-07-03)
# 구 동작(전체 reset + abort)이 973회 연속 abort를 만들어 세션 변경분이 영영 미커밋되던 결함 수리.
# 코어 경로(.claude/ 02_Infrastructure/ 00_Lawbook/ qepm/memory/ 06_Registry/ CLAUDE.md)만 스테이징,
# 나머지 대량 신규 파일은 skip + 로그/마커 기록 (Telegram 배선은 후속 — 로그+마커까지만).
NEW_COUNT=$(git diff --cached --name-status 2>/dev/null | awk '$1=="A"' | wc -l)
PARTIAL_NOTE=""
if [ "$NEW_COUNT" -gt 100 ]; then
  echo "$TS TOO_MANY_NEW ($NEW_COUNT) — core-path selective staging fallback" >> "$LOG"
  git reset HEAD -- . 2>>"$LOG" || true
  CORE_PATHS=".claude 02_Infrastructure 00_Lawbook qepm/memory 06_Registry CLAUDE.md"
  for p in $CORE_PATHS; do
    if [ -e "$p" ]; then git add -- "$p" 2>>"$LOG" || true; fi
  done
  SKIPPED=$(git status --porcelain 2>/dev/null | grep -c '^??' || true)
  SKIPPED=${SKIPPED//[^0-9]/}; SKIPPED=${SKIPPED:-0}
  echo "$TS CORE_ONLY_STAGED new=$NEW_COUNT untracked_skipped=$SKIPPED" >> "$LOG"
  printf '%s TOO_MANY_NEW=%s untracked_skipped=%s (core-path selective commit)\n' \
    "$TS" "$NEW_COUNT" "$SKIPPED" > /tmp/auto_commit_abort_marker.txt 2>/dev/null || true
  PARTIAL_NOTE=" [PARTIAL: 신규 ${NEW_COUNT}개>100 — 코어 경로만 커밋, untracked ${SKIPPED}건 skip]"
fi

STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l)
if [ "$STAGED" -eq 0 ]; then
  echo "$TS NO_STAGED" >> "$LOG"
  echo '{}'; exit 0
fi

# ─── Commit ──────────────────────────────────────────────────────────
SUMMARY="$(git diff --cached --shortstat 2>/dev/null | head -1)"
SESSION_TAG="${QVEST_SESSION_TAG:-Session $(date +%Y%m%d)}"

# (2026-07-25) 하네스/규범 변경 감사성 보강.
#   auto-commit 이 하네스 파일을 먼저 집어가면 이력에 "[auto-commit] N files" 로만 남아
#   **변경 근거·검증이 사라진다**(실측: 감시 probe 수리 2파일이 그렇게 커밋됨 → 별도
#   --allow-empty 근거 커밋으로 보강해야 했다). 근거 없는 하네스 변경은 나중에 인용·감사가
#   불가하므로, 대상 경로가 섞이면 파일 목록과 함께 후속 근거 커밋을 요구하는 표시를 남긴다.
#   ★제외(add 대상에서 빼기)는 하지 않는다 — 그러면 수리가 커밋되지 않고 worktree 에
#     갇히는 재발 패턴(이 저장소에서 3회 관측)이 되살아난다. 보존이 우선, 표시로 보완.
GUARDED=$(git diff --cached --name-only 2>/dev/null \
          | grep -E '^(02_Infrastructure/(hooks|ops|contracts|validation)/|\.claude/(settings|rules|agents)|00_Lawbook/)' || true)
GUARD_NOTE=""
if [ -n "$GUARDED" ]; then
  GUARD_NOTE="$(printf '\n⚠ 하네스/규범 경로 포함 — 근거 미기록 커밋입니다.\n  후속으로 `git commit --allow-empty` 근거 커밋(기전·검증 실측)을 붙이세요.\n  대상:\n%s\n' \
                "$(printf '%s\n' "$GUARDED" | sed 's/^/    - /' | head -20)")"
fi

git commit -m "$(cat <<COMMIT_EOF
[auto-commit] $TS — $STAGED files

$SUMMARY
$GUARD_NOTE
자동 생성 (Stop hook). $SESSION_TAG 세션 변경분 보존.
Secret 스캔 통과. Push는 milestone hook 또는 daily cron.

Co-Authored-By: Claude Code (Stop hook) <noreply@anthropic.com>
COMMIT_EOF
)" > /tmp/auto_commit_last.log 2>&1

if [ $? -eq 0 ]; then
  HASH=$(git rev-parse --short HEAD)
  echo "$TS AUTO_COMMIT $HASH staged=$STAGED${PARTIAL_NOTE}" >> "$LOG"
  MSG="[OK] [auto-commit] $HASH - $STAGED files committed. Push는 milestone/cron으로 자동.${PARTIAL_NOTE}"
  MSG_ESC=$(printf '%s' "$MSG" | "$QVEST_PY_BIN" -c "import sys,json; s=sys.stdin.buffer.read().decode('utf-8','replace'); print(json.dumps(''.join(ch if not(0xD800<=ord(ch)<=0xDFFF) else '?' for ch in s)))")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"Stop\",\"additionalContext\":$MSG_ESC}}"
else
  # 실패도 로그 + 마커에 남김 (HYG-01) — 조용한 실패 방지. Telegram 배선은 후속.
  echo "$TS COMMIT_FAILED${PARTIAL_NOTE}" >> "$LOG"
  cat /tmp/auto_commit_last.log >> "$LOG" 2>/dev/null || true
  printf '%s COMMIT_FAILED%s (detail: /tmp/auto_commit_last.log)\n' "$TS" "$PARTIAL_NOTE" \
    > /tmp/auto_commit_abort_marker.txt 2>/dev/null || true
  echo '{}'
fi
exit 0
