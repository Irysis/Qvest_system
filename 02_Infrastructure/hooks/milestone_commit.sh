#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
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
LOG="${QVEST_MC_LOG:-/tmp/milestone_commit.log}"
TS="$(date '+%Y-%m-%d %H:%M:%S')"

if [ "${QVEST_SKIP_MILESTONE_COMMIT:-0}" = "1" ]; then
  echo '{}'; exit 0
fi

# ★MC_ROOT_SRC 기본 바인딩은 sentinel 블록 **밖**에 (auto_commit_on_stop.sh 와 동일 이유):
#   이 파일도 `set -u` + ERR 트랩 아래라, 위반 주입이 블록을 들어냈을 때 유일한 정의가
#   블록 안에 있으면 변종이 구 결함을 재현하기 전에 unbound 로 죽는다(주입 교락).
MC_ROOT_SRC="legacy_glob"
# >>> QVEST_ROOT_RESOLUTION >>> ──────────────────────────────────────────────
# ★2026-08-03 수리: 구 코드는 `ls -d <하드코딩 후보> | head -1` 로 첫 *존재* 후보를 집고
#   CLAUDE_PROJECT_DIR 을 읽지 않았다 — auto_commit_on_stop.sh 와 **같은 결함**이다.
#   이 훅은 PostToolUse[Write] 라 worktree 세션에서 L-code/axiom 산출물을 쓸 때마다
#   main 을 커밋한다(작업은 worktree 에 남고 보고만 성공). 08-02 유실 사고의 형제 경로.
#   형제 파일 미전파 계통 — 원본만 고치고 같은 코드를 복사해 간 훅을 두면 결함이 살아남는다.
#   가드: 08_Tests/hooks/test_auto_commit_worktree_target.sh F/G축.
PROJECT="${QVEST_MC_PROJECT:-}"
MC_ROOT_SRC="QVEST_MC_PROJECT"
if [ -z "$PROJECT" ]; then
  _rp="$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
  if [ -f "$_rp" ]; then
    trap - ERR                       # resolver 의 tier 미스는 정상 흐름
    # shellcheck source=/dev/null
    . "$_rp" || PROJECT=""
    trap 'echo "{}"; exit 0' ERR
    MC_ROOT_SRC="${QVEST_ROOT_SOURCE:-unknown}"
  else
    MC_ROOT_SRC="resolver_missing"
  fi
fi
# <<< QVEST_ROOT_RESOLUTION <<< ──────────────────────────────────────────────
[ -z "$PROJECT" ] && { echo '{}'; exit 0; }
cd "$PROJECT" || { echo '{}'; exit 0; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo '{}'; exit 0; }

# 대상 트리/브랜치 라벨 — "무엇을" 옆에 "어디에"가 없으면 유실이 성공으로 읽힌다.
MC_BRANCH="$(git branch --show-current 2>/dev/null)"
[ -n "$MC_BRANCH" ] || MC_BRANCH="(detached)"
_mc_gd="$(git rev-parse --absolute-git-dir 2>/dev/null || echo '')"
case "$_mc_gd" in
  */worktrees/*) MC_TREE="worktree:$(basename "$_mc_gd")" ;;
  *)             MC_TREE="primary:$(basename "$PROJECT")" ;;
esac
MC_TARGET="branch=$MC_BRANCH tree=$MC_TREE src=$MC_ROOT_SRC"

# 파일 경로 추출 (v8.1.2: bytes 경유 UTF-8 명시)
FILE=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c "
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
    STMT=$("$QVEST_PY_BIN" -c "
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
  # (2026-07-24 도훈 승인 C10) legacy 레인 2종 제거 — s7_disposition_*(v55 S7, 최신 2026-06-08)·
  # pg2_allocation_*(매치 파일 0건 실측). Grade A/PG2 마일스톤은 현행 경로에서 auto_commit(Stop)이 수습.
  # 부활 시 v8.3 SOT D4(grade_a_catalog) 결정과 묶어 재설계할 것. 역사 = git.
  */stage_artifacts/l_code/*/*.json|stage_artifacts/l_code/*/*.json|*/stage_artifacts/l_code_STR_*.json|stage_artifacts/l_code_STR_*.json)
    # (2026-07-24 Fable5 하네스 감사) 현행 L-code 계층 레이아웃 stage_artifacts/l_code/<mode>/*.json 매치 추가
    # (research_continuity_guard.sh:69 glob과 정합 — 구 flat l_code_STR_* 패턴은 backward-compat 유지)
    LC=$("$QVEST_PY_BIN" -c "
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
    # (2026-07-24 Fable5 하네스 감사) 'git push origin master' 버그 수리 — 현 브랜치는 main이라
    # stale master ref만 밀려 milestone 커밋이 원격 미도달이던 결함. 현재 브랜치 기준 push.
    ( git push origin "$(git branch --show-current)" >> "$LOG" 2>&1 && \
        echo "$TS PUSH_OK $HASH" >> "$LOG" || \
        echo "$TS PUSH_FAIL $HASH (daily_push가 재시도)" >> "$LOG"
    ) &
    disown 2>/dev/null || true
  fi

  MSG="[OK] [milestone] $MILESTONE $HASH - $STAGED files → $MC_TARGET"
  [ "$PUSH_IMMEDIATE" -eq 1 ] && MSG+=" (push 진행 중)"
  MSG_ESC=$(printf '%s' "$MSG" | "$QVEST_PY_BIN" -c "import sys,json; s=sys.stdin.buffer.read().decode('utf-8','replace'); print(json.dumps(''.join(ch if not(0xD800<=ord(ch)<=0xDFFF) else '?' for ch in s)))")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":$MSG_ESC}}"
else
  echo "$TS COMMIT_FAILED $MILESTONE" >> "$LOG"
  cat /tmp/milestone_commit_last.log >> "$LOG"
  echo '{}'
fi
exit 0
