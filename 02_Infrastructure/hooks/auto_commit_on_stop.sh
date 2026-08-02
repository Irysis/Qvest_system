#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  # (2026-07-26 v2) 최후 폴백 bare python3 제거 — Windows Store 스텁이 실행돼 "Python" 스팸을
  # 남기던 잔여 트랩(구 로그 /tmp/auto_commit_on_stop.log 2026-07-03 실증). 미가용이면 빈 값 →
  # _json_msg 가 bash-only 이스케이프로 폴백.
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || true)"
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
#   3. 대량-신규 격리 밸브 v2 (2026-07-26 근본 재설계 — 본문 주석 참조):
#      단일 디렉터리에 신규(A) > BULK_DIR_THRESHOLD 집중 시 그 디렉터리의 A만 unstage.
#      M/D는 절대 격리하지 않음. 원장 .cache/auto_commit_quarantine.json → bootstrap §4h-3 WARN.
#      (v1 HYG-01 2026-07-03: NEW>100 → 코어경로만 — 누적 백로그를 재는 측정 결함으로 영구
#       개방(CORE_ONLY_STAGED 171회)·코어 밖 M/D 영구 미커밋 → v2로 대체)
#   4. commit with [auto-commit] prefix + timestamp
#
# 로그: /tmp/auto_commit.log
# 우회 env: QVEST_SKIP_AUTO_COMMIT=1
# 테스트 오버라이드 (08_Tests/hooks/test_auto_commit_valve.sh 전용):
#   QVEST_AC_PROJECT / QVEST_AC_LOG / QVEST_AC_MARKER / QVEST_AC_BULK_THRESHOLD
#==============================================================================

trap 'echo "{}"; exit 0' ERR
set -u
# (v8.1.2 2026-06-11) python stdio를 UTF-8 강제 — locale(cp949) 디코딩이 additionalContext에
# lone surrogate(\udcXX)를 만들어 이후 모든 API 요청 400 (invalid high surrogate) 유발한 사건 수리.
export PYTHONUTF8=1

INPUT=$(cat 2>/dev/null || echo '{}')
LOG="${QVEST_AC_LOG:-/tmp/auto_commit.log}"
AC_MARKER="${QVEST_AC_MARKER:-/tmp/auto_commit_abort_marker.txt}"
TS="$(date '+%Y-%m-%d %H:%M:%S')"

# ─── additionalContext JSON 이스케이프 ───────────────────────────────
# python 가용 시 surrogate-scrub 경로(v8.1.2 API 400 수리 유지), 미가용 시 bash-only 폴백.
# bare python3(Windows Store 스텁)는 어떤 경로에서도 실행하지 않는다.
_json_msg() {
  local s="$1"
  if [ -n "${QVEST_PY_BIN:-}" ] && [ -x "$QVEST_PY_BIN" ]; then
    printf '%s' "$s" | "$QVEST_PY_BIN" -c "import sys,json; t=sys.stdin.buffer.read().decode('utf-8','replace'); print(json.dumps(''.join(ch if not(0xD800<=ord(ch)<=0xDFFF) else '?' for ch in t)))" 2>/dev/null && return 0
  fi
  # 자작 메시지(ASCII+한글)라 surrogate 없음 전제 — 최소 이스케이프만.
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\r'/}; s=${s//$'\t'/\\t}
  printf '"%s"' "$s"
}

# 우회 env
if [ "${QVEST_SKIP_AUTO_COMMIT:-0}" = "1" ]; then
  echo "$TS SKIP_ENV" >> "$LOG"
  echo '{}'; exit 0
fi

# ★AC_ROOT_SRC 의 기본 바인딩은 반드시 sentinel 블록 **밖**에 둔다 (2026-08-03).
#   이 파일은 `set -u` + ERR 트랩(즉시 `echo {}; exit 0`) 아래에서 돈다. 검사기의 위반
#   주입은 sentinel 블록을 통째로 들어내는데, 유일한 정의가 블록 안에 있으면 변종은
#   112행 AC_TARGET 조립에서 unbound 로 죽는다 — **커밋에 도달하기도 전에**. 그러면
#   "primary 가 대신 커밋됨"은 빨강이 되고 나머지 주입 축 2건("worktree 정지",
#   "wt_new 아무 데도 없음")은 **공허하게 초록**이 된다. 즉 주입이 구 결함이 아니라
#   자기가 만든 문법 사고를 재는 상태(교락). 실측으로 이 상태를 확인하고 정정했다
#   ([[project-injection-fixture-confounding-20260802]] 와 동형 계통).
AC_ROOT_SRC="legacy_glob"
# >>> QVEST_ROOT_RESOLUTION >>> ──────────────────────────────────────────────
# QVEST_AC_PROJECT = 테스트 sandbox 오버라이드. 그 외에는 hooks/resolve_project.sh 규약
# (CLAUDE_PROJECT_DIR tier0 + marker 검증 · r-portability.md 금칙 ④)을 따른다.
#
# ★2026-08-02 수리 (도훈 보고): 구 코드는 `ls -d <하드코딩 후보> | head -1` 로 첫 *존재*
#   후보를 집었고 CLAUDE_PROJECT_DIR 을 **전혀 읽지 않았다**. 첫 후보는 항상 main →
#   worktree 세션의 Stop 훅이 main 의 작업트리를 커밋하고 worktree 는 건드리지 않는다.
#   그런데 훅은 "[OK] N files committed" 를 보고했다 — 무해한 no-op 이 아니라
#   **하지 않은 일에 대한 성공 보고**(작업 유실 + 유실의 은폐).
#   실측(worktree strange-leakey-dedfca): 보고 4회가 전부 main 커밋(3eeafa3d 등),
#   worktree 브랜치 HEAD 는 정지, 수리본은 어느 트리에도 없이 작업트리에만 존재 → 수동 회수.
#   ★값이 없던 게 아니라 **안 본** 것이다: 훅 안에서 CLAUDE_PROJECT_DIR 은 실제로 worktree 를
#     가리킨다(.cache/hook_integrity_log.tsv 의 DIR= 필드로 실측).
#   가드: 08_Tests/hooks/test_auto_commit_worktree_target.sh (A/B/C/D + 위반 주입 E).
#   ★sentinel 주석 2줄은 그 검사기가 **해석 블록만** 구 형태로 되돌려 검출력을 실증하는 데
#     쓴다. 지우면 위반 주입이 공허해진다(검사기가 loud FAIL 로 알린다).
PROJECT="${QVEST_AC_PROJECT:-}"
AC_ROOT_SRC="QVEST_AC_PROJECT"
if [ -z "$PROJECT" ]; then
  _rp="$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
  if [ -f "$_rp" ]; then
    trap - ERR                       # resolver 의 tier 미스는 정상 흐름 — ERR 트랩 조기종료 방지
    # shellcheck source=/dev/null
    . "$_rp" || PROJECT=""
    trap 'echo "{}"; exit 0' ERR
    AC_ROOT_SRC="${QVEST_ROOT_SOURCE:-unknown}"
  else
    AC_ROOT_SRC="resolver_missing"
  fi
fi
# <<< QVEST_ROOT_RESOLUTION <<< ──────────────────────────────────────────────
if [ -z "$PROJECT" ] || [ ! -e "$PROJECT/.git" ]; then
  echo '{}'; exit 0
fi
cd "$PROJECT" || { echo '{}'; exit 0; }
# git 작동 확인 (.git이 파일인 경우 — worktree gitlink / WSL 한글경로 gitlink)
git rev-parse --git-dir >/dev/null 2>&1 || { echo '{}'; exit 0; }

# ─── 대상 트리/브랜치 라벨 ───────────────────────────────────────────
# 보고에 "무엇을 커밋했나"만 있고 "어디에 커밋했나"가 없어서, worktree 세션에서 main 을
# 커밋한 4회가 전부 "내 작업이 저장됐다"로 읽혔다(2026-08-02). 대상이 보이게 한다.
AC_BRANCH="$(git branch --show-current 2>/dev/null)"
[ -n "$AC_BRANCH" ] || AC_BRANCH="(detached)"
_gd="$(git rev-parse --absolute-git-dir 2>/dev/null || echo '')"
case "$_gd" in
  */worktrees/*) AC_TREE="worktree:$(basename "$_gd")" ;;
  *)             AC_TREE="primary:$(basename "$PROJECT")" ;;
esac
AC_TARGET="branch=$AC_BRANCH tree=$AC_TREE src=$AC_ROOT_SRC"

# 변경 없으면 skip (★어느 트리를 봤는지 함께 남긴다 — "변경 없음"이 '틀린 트리를 봤음'의
# 위장이 되지 않도록. 오늘 계통의 공통 기전 = 결손을 정상값으로 내려앉힘)
CHANGES=$(git status --porcelain 2>/dev/null | wc -l)
if [ "$CHANGES" -eq 0 ]; then
  echo "$TS NO_CHANGES $AC_TARGET" >> "$LOG"
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
  MSG_ESC=$(_json_msg "$MSG")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"Stop\",\"additionalContext\":$MSG_ESC}}"
  exit 0
fi

# ─── Staging (gitignore 자동 적용) ──────────────────────────────────
git add -A 2>>"$LOG"

# ─── 대량-신규 격리 밸브 v2 (2026-07-26 근본 재설계, 도훈 지시) ─────────────────────
# v1(HYG-01 2026-07-03): NEW>100 → 전체 reset 후 CORE_PATHS만 재스테이징.
#   ★실측 결함(2026-07-26): 문턱이 '이번 세션 신규'가 아니라 **누적 untracked 백로그**를 쟀고
#   (fq073 dart_products 등 538건 상시 초과 → 밸브 영구 개방, CORE_ONLY_STAGED 171회),
#   처벌이 dump가 아니라 코어 밖 **전부(M/D 포함)**에 떨어졌다 — git reset이 M/D까지 쓸어
#   08_Tests 신규 회귀가드·04_Research 보고서·삭제 3건이 영영 미커밋. '수리가 git에 못 닿는'
#   worktree 좌초와 같은 실패부류를 main에서 훅 스스로 재현. (검사가 잘못된 것을 잼 계통)
# v2 원칙:
#   ① M(수정)/D(삭제)는 절대 격리하지 않는다 — 추적 중인 파일의 변경·삭제는 dump가 아니다.
#   ② 격리는 신규(A)만, 디렉터리 단위: 한 디렉터리에 A가 문턱 초과 집중 시 그 디렉터리의
#      A만 unstage (대량 dump의 전형 서명 = 단일 디렉터리 집중. 확산형 유기 산출은 통과).
#   ③ 조용한 격리 금지: 원장 .cache/auto_commit_quarantine.json → bootstrap §4h-3 부팅 WARN.
#      bulk 미검출 턴에 원장 자동 제거(드레인 완료 시 WARN 자동 소등).
BULK_DIR_THRESHOLD="${QVEST_AC_BULK_THRESHOLD:-100}"
QUAR_LEDGER="$PROJECT/.cache/auto_commit_quarantine.json"
PARTIAL_NOTE=""
A_FILES=()
while IFS= read -r -d '' _f; do A_FILES+=("$_f"); done \
  < <(git diff --cached --name-only --diff-filter=A -z 2>/dev/null || true)
NEW_COUNT=${#A_FILES[@]}
if [ "$NEW_COUNT" -gt "$BULK_DIR_THRESHOLD" ]; then
  declare -A DIRCNT=()
  for _f in ${A_FILES[@]+"${A_FILES[@]}"}; do
    _d="${_f%/*}"; [ "$_d" = "$_f" ] && _d="."
    DIRCNT["$_d"]=$(( ${DIRCNT["$_d"]:-0} + 1 ))
  done
  QUAR_DIRS=()
  for _d in "${!DIRCNT[@]}"; do
    if [ "${DIRCNT[$_d]}" -gt "$BULK_DIR_THRESHOLD" ]; then QUAR_DIRS+=("$_d"); fi
  done
  if [ "${#QUAR_DIRS[@]}" -gt 0 ]; then
    QUAR_N=0
    for _f in ${A_FILES[@]+"${A_FILES[@]}"}; do
      _d="${_f%/*}"; [ "$_d" = "$_f" ] && _d="."
      for _q in "${QUAR_DIRS[@]}"; do
        if [ "$_d" = "$_q" ]; then
          git reset -q HEAD -- "$_f" 2>>"$LOG" || true
          QUAR_N=$((QUAR_N + 1)); break
        fi
      done
    done
    {
      printf '{"ts":"%s","threshold":%s,"total_new":%s,"quarantined":[' \
        "$TS" "$BULK_DIR_THRESHOLD" "$NEW_COUNT"
      _first=1
      for _d in "${QUAR_DIRS[@]}"; do
        _esc=$(printf '%s' "$_d" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
        [ "$_first" -eq 0 ] && printf ','
        printf '{"dir":"%s","n_new":%s}' "$_esc" "${DIRCNT[$_d]}"
        _first=0
      done
      printf '],"drain_hint":"정상 산출물이면 git add <dir> 후 수동 커밋, dump면 정리 또는 .gitignore. M/D는 영향 없음(항상 커밋)."}\n'
    } > "$QUAR_LEDGER" 2>>"$LOG" || true
    echo "$TS BULK_QUARANTINE dirs=${#QUAR_DIRS[@]} files=$QUAR_N of_new=$NEW_COUNT" >> "$LOG"
    printf '%s BULK_QUARANTINE dirs=%s files=%s (원장: %s)\n' \
      "$TS" "${#QUAR_DIRS[@]}" "$QUAR_N" "$QUAR_LEDGER" > "$AC_MARKER" 2>/dev/null || true
    PARTIAL_NOTE=" [QUARANTINE: ${#QUAR_DIRS[@]}개 디렉터리·신규 ${QUAR_N}건 격리 (M/D는 전량 커밋) — $QUAR_LEDGER]"
  else
    # 총량은 크나 단일-디렉터리 집중 없음 = 확산형 유기 산출 — 격리 없이 통과 (v1 과잉처벌 제거)
    echo "$TS BULK_SPREAD_OK new=$NEW_COUNT (single-dir concentration 없음)" >> "$LOG"
    rm -f "$QUAR_LEDGER" 2>/dev/null || true
  fi
else
  rm -f "$QUAR_LEDGER" 2>/dev/null || true
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
  echo "$TS AUTO_COMMIT $HASH staged=$STAGED $AC_TARGET${PARTIAL_NOTE}" >> "$LOG"
  # ★대상($AC_TARGET)을 성공 보고 본문에 싣는다 (2026-08-03). 08-02 사고의 본체는
  #   커밋 실패가 아니라 **틀린 트리에 커밋하고 성공을 보고한 것**이었다 — 세션은
  #   "[OK] N files committed" 를 4회 받고 내 작업이 저장됐다고 읽었으나 수리본은
  #   어느 트리에도 없었다. "무엇을" 옆에 "어디에"가 없으면 유실이 성공으로 읽힌다.
  #   가드 = test_auto_commit_worktree_target.sh D축(보고에 브랜치명 + tree= 라벨).
  MSG="[OK] [auto-commit] $HASH - $STAGED files committed → $AC_TARGET. Push는 milestone/cron으로 자동.${PARTIAL_NOTE}"
  MSG_ESC=$(_json_msg "$MSG")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"Stop\",\"additionalContext\":$MSG_ESC}}"
else
  # 실패도 로그 + 마커에 남김 (HYG-01) — 조용한 실패 방지. Telegram 배선은 후속.
  echo "$TS COMMIT_FAILED${PARTIAL_NOTE}" >> "$LOG"
  cat /tmp/auto_commit_last.log >> "$LOG" 2>/dev/null || true
  printf '%s COMMIT_FAILED%s (detail: /tmp/auto_commit_last.log)\n' "$TS" "$PARTIAL_NOTE" \
    > "$AC_MARKER" 2>/dev/null || true
  echo '{}'
fi
exit 0
