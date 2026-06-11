#!/usr/bin/env bash
#==============================================================================
# milestone_commit.sh — PostToolUse[Write] Hook
#
# 중요 이벤트 artifact Write 감지 → 즉시 commit + push.
#
# Milestone 종류:
#   - AX 승격       : qepm/memory/axioms/active/AX-*.json (IMMUTABLE 제외)
#   - Grade A S7    : stage_artifacts/s7_disposition_*.json + grade="A"
#   - PG2 배분      : stage_artifacts/pg2_allocation_*.json
#   - 신규 L-code   : stage_artifacts/l_code_STR_*.json
#
# 동작:
#   1. FILE_PATH milestone 패턴 확인 → 아니면 skip
#   2. secret 스캔 (삼중 방어)
#   3. 해당 파일 + 관련 파일 staging
#   4. semantic commit message 생성
#   5. commit + push (background, non-blocking)
#
# 로그: /tmp/milestone_commit.log
# 우회 env: QVEST_SKIP_MILESTONE_COMMIT=1
#==============================================================================

trap 'echo "{}"; exit 0' ERR
set -u
# (v8.1.2 2026-06-11) python stdio UTF-8 강제 — additionalContext lone surrogate(API 400) 수리
export PYTHONUTF8=1

INPUT=$(cat 2>/dev/null || echo '{}')
LOG="/tmp/milestone_commit.log"
TS="$(date '+%Y-%m-%d %H:%M:%S')"

if [ "${QVEST_SKIP_MILESTONE_COMMIT:-0}" = "1" ]; then
  echo '{}'; exit 0
fi

PROJECT=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
[ -z "$PROJECT" ] && { echo '{}'; exit 0; }
cd "$PROJECT" || { echo '{}'; exit 0; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo '{}'; exit 0; }

# 파일 경로 추출 (v8.1.2: bytes 경유 UTF-8 명시)
FILE=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
try:
    d = json.loads(sys.stdin.buffer.read().decode('utf-8', 'replace'))
    print(d.get('tool_input', {}).get('file_path', ''))
except: print('')
" 2>/dev/null || echo "")

[ -z "$FILE" ] && { echo '{}'; exit 0; }
[ ! -f "$FILE" ] && { echo '{}'; exit 0; }

# ─── Milestone 분류 ──────────────────────────────────────────────────
MILESTONE=""
COMMIT_MSG=""
PUSH_IMMEDIATE=0

case "$FILE" in
  */qepm/memory/axioms/active/AX-*.json|qepm/memory/axioms/active/AX-*.json)
    AX_ID=$(basename "$FILE" .json)
    # IMMUTABLE (AX-000/001/002) 제외
    if [ "$AX_ID" = "AX-000" ] || [ "$AX_ID" = "AX-001" ] || [ "$AX_ID" = "AX-002" ]; then
      echo '{}'; exit 0
    fi
    MILESTONE="AX_PROMOTE"
    # (v8.1.2) 경로는 argv 전달 + encoding 명시 — 소스 보간 open('$FILE')은 quote 포함 경로에서 주입형
    STMT=$(python3 -c "
import json, sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
try:
    d = json.load(open(sys.argv[1], encoding='utf-8'))
    s = (d.get('statement') or '')[:80]
    print(s)
except: print('')" "$FILE" 2>/dev/null)
    COMMIT_MSG="feat(axiom): $AX_ID 승격 — $STMT"
    PUSH_IMMEDIATE=1
    ;;
  */stage_artifacts/s7_disposition_*.json|stage_artifacts/s7_disposition_*.json)
    # Grade A/A_NOVEL/A_DEF만
    GRADE=$(python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding='utf-8'))
    print(d.get('grade') or d.get('final_grade') or '')
except: print('')" "$FILE" 2>/dev/null)
    case "$GRADE" in
      A|A_NOVEL|A_DEF)
        STR_ID=$(basename "$FILE" .json | sed 's/^s7_disposition_//')
        MILESTONE="GRADE_A"
        COMMIT_MSG="feat(strategy): $STR_ID Grade $GRADE 확정"
        PUSH_IMMEDIATE=1
        ;;
      *) echo '{}'; exit 0 ;;
    esac
    ;;
  */stage_artifacts/pg2_allocation_*.json|stage_artifacts/pg2_allocation_*.json)
    MILESTONE="PG2_ALLOC"
    BN=$(basename "$FILE" .json | sed 's/^pg2_allocation_//')
    COMMIT_MSG="feat(portfolio): PG2 배분 갱신 — $BN"
    PUSH_IMMEDIATE=1
    ;;
  */stage_artifacts/l_code_STR_*.json|stage_artifacts/l_code_STR_*.json)
    LC=$(python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding='utf-8'))
    print(d.get('l_code') or '')
except: print('')" "$FILE" 2>/dev/null)
    [ -z "$LC" ] && LC=$(basename "$FILE" .json)
    MILESTONE="LCODE_NEW"
    COMMIT_MSG="docs(lesson): $LC 추가"
    PUSH_IMMEDIATE=0  # 일반 L-code는 Stop hook이 수습
    ;;
  *) echo '{}'; exit 0 ;;
esac

# ─── Secret 스캔 (삼중 방어) ────────────────────────────────────────
TOKEN_HITS=$( (git diff --no-color HEAD 2>/dev/null \
  | grep -cE 'bot[0-9]{9,11}:A[A-Za-z0-9_-]{34,}') 2>/dev/null || echo 0)
TOKEN_HITS=${TOKEN_HITS//[^0-9]/}; TOKEN_HITS=${TOKEN_HITS:-0}
if [ "$TOKEN_HITS" -gt 0 ]; then
  echo "$TS SECRET_ABORT $MILESTONE token_hits=$TOKEN_HITS" >> "$LOG"
  echo '{}'; exit 0
fi

# ─── Staging ─────────────────────────────────────────────────────────
# milestone 파일 + 관련 아티팩트만 conservative staging
git add "$FILE" 2>>"$LOG"
# 부가: 역링크 업데이트된 L-code, CLAUDE.md, 관련 stage_artifacts도 같이
case "$MILESTONE" in
  AX_PROMOTE)
    git add qepm/memory/axioms/active/ qepm/memory/axioms/candidates/ \
            qepm/memory/axioms/review_log/ CLAUDE.md \
            02_Infrastructure/prompts/*_init.md \
            stage_artifacts/l_code_*.json 2>>"$LOG" || true
    ;;
  GRADE_A)
    STR_ID=$(basename "$FILE" .json | sed 's/^s7_disposition_//')
    git add stage_artifacts/s6_judge_*"$STR_ID"*.json \
            stage_artifacts/role_honesty_*"$STR_ID"*.json \
            stage_artifacts/l_code_*"$STR_ID"*.json \
            04_Research/grade_a_catalog.json 2>>"$LOG" || true
    ;;
  PG2_ALLOC)
    git add stage_artifacts/pg0_*.json stage_artifacts/pg1_*.json \
            stage_artifacts/pg2_*.json 2>>"$LOG" || true
    ;;
  LCODE_NEW)
    git add .cache/lcode_corpus.json 2>>"$LOG" || true
    ;;
esac

STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l)
if [ "$STAGED" -eq 0 ]; then
  echo "$TS NO_STAGED $MILESTONE" >> "$LOG"
  echo '{}'; exit 0
fi

# ─── Commit ─────────────────────────────────────────────────────────
git commit -m "$(cat <<COMMIT_EOF
$COMMIT_MSG

$MILESTONE 자동 commit. milestone_commit.sh (PostToolUse hook).
$STAGED files · $TS

Co-Authored-By: Claude Code (milestone hook) <noreply@anthropic.com>
COMMIT_EOF
)" > /tmp/milestone_commit_last.log 2>&1

if [ $? -eq 0 ]; then
  HASH=$(git rev-parse --short HEAD)
  echo "$TS MILESTONE_COMMIT $MILESTONE $HASH staged=$STAGED" >> "$LOG"

  # ─── Push (background, non-blocking) ─────────────────────────────
  if [ "$PUSH_IMMEDIATE" -eq 1 ]; then
    ( git push origin master >> "$LOG" 2>&1 && \
        echo "$TS PUSH_OK $HASH" >> "$LOG" || \
        echo "$TS PUSH_FAIL $HASH (daily_push가 재시도)" >> "$LOG"
    ) &
    disown 2>/dev/null || true
  fi

  MSG="[OK] [milestone] $MILESTONE $HASH - $STAGED files"
  [ "$PUSH_IMMEDIATE" -eq 1 ] && MSG+=" (push 진행 중)"
  MSG_ESC=$(printf '%s' "$MSG" | python3 -c "import sys,json; s=sys.stdin.buffer.read().decode('utf-8','replace'); print(json.dumps(''.join(ch if not(0xD800<=ord(ch)<=0xDFFF) else '?' for ch in s)))")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":$MSG_ESC}}"
else
  echo "$TS COMMIT_FAILED $MILESTONE" >> "$LOG"
  cat /tmp/milestone_commit_last.log >> "$LOG"
  echo '{}'
fi
exit 0
