#!/usr/bin/env bash
#==============================================================================
# test_auto_commit_session_scope.sh — SessionEnd 자동 커밋의 **세션 범위** 계약 (WP4 2026-10-20)
#
# 배경: 독립 프로그램 라운드를 여러 세션이 동시에 돌리면(L1-SPEED-PLAN-20261020 §13 전제 3), 한 세션의
#   SessionEnd 가 `git add -A` 로 다른 세션의 미커밋 파일·인덱스까지 자기 auto-commit 에 쓸어 담았다.
#   훅 기본 범위 = 그 세션 전사(transcript_path + <sid>/subagents/*.jsonl)의 Write·Edit·MultiEdit·NotebookEdit
#   경로 ∩ 바뀐 경로. 스테이징·비밀 스캔·격리·커밋 = 임시 인덱스, 커밋 뒤 실 인덱스는 커밋한 경로만 동기화.
#
# 검증 축 (sandbox git repo 에서 훅 전체를 실 구동 — 로직 재현이 아니라 실물 실행):
#   S1  교차 세션 격리 — A 세션 경로(새 파일·수정)만 커밋, B 세션 새 파일·수정은 작업 트리에 그대로
#   S2  인덱스 격리 — B 가 git add 해 둔 파일은 A 커밋에 안 들어가고 실 인덱스에 스테이징된 채 남는다
#   S3  실 인덱스 동기화 — 커밋한 경로는 git status 에서 깨끗(되돌림 스테이징 유령 없음)
#   S4  전사 없음('{}') → 커밋 0 · NO_SESSION_SCOPE 기록(범위를 모르면 쓸어 담지 않는다)
#   S5  전사 파일 부재 → 커밋 0 · NO_SESSION_SCOPE
#   S6  subagents 전사의 쓰기도 그 세션 범위
#   S7  경로 형태(역슬래시 · 슬래시 · /c/ · 대소문자 · 한글) 통일 · 저장소 밖 · gitignore 경로 제외
#   S8  범위 안 변경 0(이미 커밋됨) → NO_CHANGES · 다른 세션 dirty 가 있어도 HEAD 불변
#   S9  비밀(토큰) 든 세션 새 파일 → 커밋 0 · 실 인덱스 불변(B 스테이징 유지 · A 파일 미스테이징)
#   S10 격리 밸브가 세션 범위에서도 동작(bulk/ 120 신규 격리 · 나머지 커밋 · 원장)
#   S11 충돌 마커 든 세션 파일은 제외 · 나머지 커밋
#   S12 세션이 고친 추적 파일의 삭제도 커밋
#   S13 linked worktree 세션 → worktree 브랜치에만 · primary dirty 무접촉
#   V1  ★위반 주입: 같은 입력을 QVEST_AC_SCOPE=all 로 → B 파일이 쓸려 들어간다(S1 초록이 범위 기전에서 나옴을 실증)
#   M1  ★뮤테이션: 세션 pathspec 스테이징을 `git add -A` 로 바꾼 사본 → S1 이 빨강
#   M2  ★뮤테이션: 커밋 뒤 실 인덱스 동기화를 지운 사본 → S3 이 빨강
#
# 요약 규약: 마지막 줄 {"test":"auto_commit_session_scope","pass":N,"fail":N,"total":N}
#==============================================================================
set -u

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$_SELF_DIR/../../02_Infrastructure/hooks/auto_commit_on_stop.sh"
if [ ! -f "$HOOK" ]; then
  echo "FATAL: hook 부재: $HOOK"
  echo '{"test":"auto_commit_session_scope","pass":0,"fail":1,"total":1}'
  exit 1
fi
PY="${QVEST_PY:-}"; PY="${PY//\\//}"
[ -n "$PY" ] && [ -x "$PY" ] || PY="C:/Users/99922/AppData/Local/Programs/Python/Python312/python.exe"
if [ ! -x "$PY" ]; then
  echo "FATAL: python 부재"
  echo '{"test":"auto_commit_session_scope","pass":0,"fail":1,"total":1}'
  exit 1
fi

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $1  ($2)"; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expect=$2 actual=$3"; fi; }

SANDBOXES=()
cleanup() { for s in ${SANDBOXES[@]+"${SANDBOXES[@]}"}; do rm -rf "$s" 2>/dev/null || true; done; }
trap cleanup EXIT

new_repo() { # stdout = sandbox 경로 (+ $sb.meta = 로그·전사 · repo 밖)
  local sb; sb=$(mktemp -d); SANDBOXES+=("$sb" "$sb.meta")
  git -C "$sb" init -q
  git -C "$sb" config user.email "test@qvest.local"
  git -C "$sb" config user.name  "scope-test"
  git -C "$sb" config commit.gpgsign false
  git -C "$sb" config core.autocrlf false
  echo ".cache/" > "$sb/.gitignore"
  echo "base1" > "$sb/tracked1.txt"; echo "base2" > "$sb/tracked2.txt"; echo "base3" > "$sb/tracked3.txt"
  git -C "$sb" add -A; git -C "$sb" commit -qm "base"
  mkdir -p "$sb/.cache" "$sb.meta/proj"
  printf '%s' "$sb"
}

# mk_transcript <transcript.jsonl> <path...> — 실 전사와 같은 꼴(assistant · message.content[].tool_use)
#   경로 앞에 'E:' 를 붙이면 Edit, 'N:' 은 NotebookEdit(notebook_path), 없으면 Write.
mk_transcript() {
  local out="$1"; shift
  "$PY" - "$out" "$@" <<'PYEOF'
import json, sys
out, items = sys.argv[1], sys.argv[2:]
with open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write(json.dumps({"type": "user", "message": {"role": "user", "content": "go"}}) + "\n")
    for i, it in enumerate(items):
        name, key, p = "Write", "file_path", it
        if it.startswith("E:"):
            name, p = "Edit", it[2:]
        elif it.startswith("N:"):
            name, key, p = "NotebookEdit", "notebook_path", it[2:]
        ti = {key: p, "content": "x"} if name == "Write" else {key: p, "old_string": "a", "new_string": "b"}
        rec = {"type": "assistant", "sessionId": "S", "cwd": "C:\\nowhere",
               "message": {"role": "assistant", "content": [
                   {"type": "text", "text": "writing"},
                   {"type": "tool_use", "id": "toolu_%03d" % i, "name": name, "input": ti}]}}
        f.write(json.dumps(rec, ensure_ascii=False, separators=(",", ":")) + "\n")
PYEOF
}

wpath() { cygpath -w "$1"; }   # 실 전사 꼴(C:\Users\…)

run_hook() { # $1=sandbox $2=input-json [$3=hook경로] [$4=scope]
  local sb="$1" in="$2" hk="${3:-$HOOK}" scope="${4:-}"
  printf '%s' "$in" | env -u QVEST_UNATTENDED_LANE -u QVEST_CLEAN_LANE -u GIT_INDEX_FILE \
    QVEST_AC_LANE_CHECK=0 QVEST_AC_PROJECT="$sb" QVEST_AC_LOG="$sb.meta/ac.log" \
    QVEST_AC_MARKER="$sb.meta/ac.marker" QVEST_SKIP_AUTO_COMMIT=0 \
    ${scope:+QVEST_AC_SCOPE="$scope"} bash "$hk" 2>>"$sb.meta/ac.stderr"
}
end_input() { # $1=sid $2=transcript (윈도 경로로 싣는다)
  "$PY" -c 'import json,sys; print(json.dumps({"session_id":sys.argv[1],"transcript_path":sys.argv[2],"cwd":"C:\\x","hook_event_name":"SessionEnd","reason":"other"}))' "$1" "$2"
}

n_commits() { git -C "$1" rev-list --count HEAD 2>/dev/null; }
in_head()   { git -C "$1" show --name-only --format="" HEAD 2>/dev/null | grep -c "$2" || true; }
st_line()   { git -C "$1" status --porcelain -uall -- "$2" 2>/dev/null | head -1; }
staged()    { git -C "$1" diff --cached --name-only 2>/dev/null | grep -c "$2" || true; }

# 공통 무대: A 세션 = a_new.txt(신규) + tracked1.txt(수정) / B 세션 = b_new.txt(신규) + tracked2.txt(수정) + b_staged.txt(add)
stage_two_sessions() {
  local sb="$1"
  echo "A" > "$sb/a_new.txt"; echo "A-mod" >> "$sb/tracked1.txt"
  echo "B" > "$sb/b_new.txt"; echo "B-mod" >> "$sb/tracked2.txt"
  echo "BS" > "$sb/b_staged.txt"; git -C "$sb" add b_staged.txt
  mk_transcript "$sb.meta/proj/sessA.jsonl" "$(wpath "$sb/a_new.txt")" "E:$(wpath "$sb/tracked1.txt")"
}

echo "=== test_auto_commit_session_scope (세션 범위 자동 커밋) ==="

# ── S1 · S2 · S3 ─────────────────────────────────────────────────────────────
SB=$(new_repo); stage_two_sessions "$SB"
OUT=$(run_hook "$SB" "$(end_input sessA "$(wpath "$SB.meta/proj/sessA.jsonl")")")
chk "S1 커밋 1건"                          "2" "$(n_commits "$SB")"
chk "S1 A 신규(a_new) 커밋됨"              "1" "$(in_head "$SB" 'a_new.txt')"
chk "S1 A 수정(tracked1) 커밋됨"           "1" "$(in_head "$SB" 'tracked1.txt')"
chk "S1 B 신규(b_new) 커밋 제외"           "0" "$(in_head "$SB" 'b_new.txt')"
chk "S1 B 수정(tracked2) 커밋 제외"        "0" "$(in_head "$SB" 'tracked2.txt')"
chk "S1 B 신규 작업 트리 잔존(untracked)"  "?? b_new.txt" "$(st_line "$SB" b_new.txt)"
chk "S1 B 수정 작업 트리 잔존"             " M tracked2.txt" "$(st_line "$SB" tracked2.txt)"
chk "S2 B 스테이징(b_staged) 커밋 제외"    "0" "$(in_head "$SB" 'b_staged.txt')"
chk "S2 B 스테이징 실 인덱스에 유지"        "1" "$(staged "$SB" 'b_staged.txt')"
chk "S3 커밋 경로 깨끗(a_new)"             "" "$(st_line "$SB" a_new.txt)"
chk "S3 커밋 경로 깨끗(tracked1)"          "" "$(st_line "$SB" tracked1.txt)"
case "$OUT" in *'scope=session'*) ok "S1 보고에 범위 표기(scope=session)" ;; *) bad "S1 보고에 범위 표기" "out=${OUT:0:160}" ;; esac
if git -C "$SB" log -1 --format=%B | grep -q '범위 = 이 세션'; then ok "S1 커밋 본문에 범위 문장"; else bad "S1 커밋 본문에 범위 문장" "$(git -C "$SB" log -1 --format=%B | tail -5 | tr '\n' '|')"; fi
S1_SB="$SB"

# ── S4 · S5 전사 없음 / 부재 ─────────────────────────────────────────────────
SB=$(new_repo); stage_two_sessions "$SB"
run_hook "$SB" '{}' > /dev/null
chk "S4 전사 없음 → 커밋 0"               "1" "$(n_commits "$SB")"
if grep -q 'NO_SESSION_SCOPE' "$SB.meta/ac.log" 2>/dev/null; then ok "S4 NO_SESSION_SCOPE 기록"; else bad "S4 NO_SESSION_SCOPE 기록" "log=$(tail -2 "$SB.meta/ac.log" 2>/dev/null | tr '\n' '|')"; fi
chk "S4 실 인덱스 불변(b_staged 유지)"     "1" "$(staged "$SB" 'b_staged.txt')"
run_hook "$SB" "$(end_input sessZ "$(wpath "$SB.meta/proj/none.jsonl")")" > /dev/null
chk "S5 전사 파일 부재 → 커밋 0"          "1" "$(n_commits "$SB")"
chk "S5 NO_SESSION_SCOPE(transcript_missing)" "1" "$(grep -c 'transcript_missing' "$SB.meta/ac.log" 2>/dev/null || true)"

# ── S6 · S7 subagents · 경로 형태 ────────────────────────────────────────────
SB=$(new_repo)
mkdir -p "$SB/sub" "$SB/한글 폴더" "$SB.meta/proj/sessC/subagents" "$SB.meta/outside"
echo s > "$SB/sub/from_subagent.txt"; echo f > "$SB/sub/fwd.txt"; echo m > "$SB/sub/msys.txt"
echo c > "$SB/sub/Case.txt"; echo k > "$SB/한글 폴더/메모.md"; echo o > "$SB.meta/outside/out.txt"
echo g > "$SB/.cache/ignored.txt"; echo n > "$SB/not_in_transcript.txt"
SBW="$(wpath "$SB")"; SBM="$(cygpath -m "$SB")"; SBU="$(cygpath -u "$SB")"
mk_transcript "$SB.meta/proj/sessC.jsonl" "$SBM/sub/fwd.txt" "$SBU/sub/msys.txt" \
  "${SBW^^}\\SUB\\CASE.TXT" "$SBW\\한글 폴더\\메모.md" "$(wpath "$SB.meta/outside/out.txt")" "$SBW\\.cache\\ignored.txt"
mk_transcript "$SB.meta/proj/sessC/subagents/agent-x.jsonl" "$SBW\\sub\\from_subagent.txt"
run_hook "$SB" "$(end_input sessC "$(wpath "$SB.meta/proj/sessC.jsonl")")" > /dev/null
chk "S6 subagents 전사 경로 커밋"          "1" "$(in_head "$SB" 'sub/from_subagent.txt')"
chk "S7 슬래시 형태(C:/…)"                 "1" "$(in_head "$SB" 'sub/fwd.txt')"
chk "S7 MSYS 형태(/c/…)"                   "1" "$(in_head "$SB" 'sub/msys.txt')"
chk "S7 대소문자 다른 표기"                "1" "$(in_head "$SB" 'sub/Case.txt')"
chk "S7 한글 경로"                         "1" "$(git -C "$SB" -c core.quotepath=false show --name-only --format= HEAD | grep -c '메모.md' || true)"
chk "S7 전사에 없는 파일 제외"             "0" "$(in_head "$SB" 'not_in_transcript.txt')"
chk "S7 gitignore 경로 제외"               "0" "$(in_head "$SB" 'ignored.txt')"
chk "S7 커밋 파일 수 = 5"                  "5" "$(git -C "$SB" show --name-only --format= HEAD | grep -c . || true)"

# ── S8 범위 안 변경 0 ────────────────────────────────────────────────────────
H0=$(git -C "$S1_SB" rev-parse HEAD)
run_hook "$S1_SB" "$(end_input sessA "$(wpath "$S1_SB.meta/proj/sessA.jsonl")")" > /dev/null
chk "S8 범위 안 변경 0 → HEAD 불변"        "$H0" "$(git -C "$S1_SB" rev-parse HEAD)"
chk "S8 NO_CHANGES 기록"                   "1" "$(tail -1 "$S1_SB.meta/ac.log" | grep -c 'NO_CHANGES' || true)"

# ── S9 비밀 → 중단 · 실 인덱스 불변 ──────────────────────────────────────────
SB=$(new_repo); stage_two_sessions "$SB"
FAKE_TOKEN="bot123456789"":A""$(printf 'x%.0s' $(seq 1 40))"     # 소스에 리터럴로 남기지 않는다
echo "tg = \"$FAKE_TOKEN\"" > "$SB/a_secret.txt"
mk_transcript "$SB.meta/proj/sessS.jsonl" "$(wpath "$SB/a_new.txt")" "$(wpath "$SB/a_secret.txt")"
OUT=$(run_hook "$SB" "$(end_input sessS "$(wpath "$SB.meta/proj/sessS.jsonl")")")
chk "S9 비밀 → 커밋 0"                     "1" "$(n_commits "$SB")"
case "$OUT" in *Secret*) ok "S9 비밀 경고 보고" ;; *) bad "S9 비밀 경고 보고" "out=${OUT:0:160}" ;; esac
chk "S9 실 인덱스: B 스테이징 유지"         "1" "$(staged "$SB" 'b_staged.txt')"
chk "S9 실 인덱스: A 파일 미스테이징"       "0" "$(staged "$SB" 'a_')"

# ── S10 격리 밸브(세션 범위) ─────────────────────────────────────────────────
SB=$(new_repo); mkdir -p "$SB/bulk"
ITEMS=()
for i in $(seq 1 120); do echo "$i" > "$SB/bulk/f$i.json"; ITEMS+=("$(wpath "$SB/bulk/f$i.json")"); done
echo "keep" > "$SB/keep.txt"; ITEMS+=("$(wpath "$SB/keep.txt")"); echo "mod" >> "$SB/tracked1.txt"; ITEMS+=("E:$(wpath "$SB/tracked1.txt")")
mk_transcript "$SB.meta/proj/sessQ.jsonl" "${ITEMS[@]}"
OUT=$(run_hook "$SB" "$(end_input sessQ "$(wpath "$SB.meta/proj/sessQ.jsonl")")")
chk "S10 커밋 발생"                        "2" "$(n_commits "$SB")"
chk "S10 bulk/ 격리(커밋 제외)"            "0" "$(in_head "$SB" 'bulk/')"
chk "S10 소량 신규 · 수정 커밋"            "2" "$(git -C "$SB" show --name-only --format= HEAD | grep -cE '^(keep|tracked1)\.txt$' || true)"
chk "S10 bulk/ 120건 untracked 잔존"       "120" "$(git -C "$SB" status --porcelain -uall | grep -c '^?? bulk/' || true)"
if grep -q '"dir":"bulk"' "$SB/.cache/auto_commit_quarantine.json" 2>/dev/null; then ok "S10 격리 원장"; else bad "S10 격리 원장" "부재"; fi

# ── S11 충돌 마커 ────────────────────────────────────────────────────────────
SB=$(new_repo)
printf '<<<<<<< HEAD\nx\n=======\ny\n>>>>>>> other\n' > "$SB/conflicted.txt"; echo ok > "$SB/fine.txt"
mk_transcript "$SB.meta/proj/sessM.jsonl" "$(wpath "$SB/conflicted.txt")" "$(wpath "$SB/fine.txt")"
run_hook "$SB" "$(end_input sessM "$(wpath "$SB.meta/proj/sessM.jsonl")")" > /dev/null
chk "S11 충돌 마커 파일 제외"              "0" "$(in_head "$SB" 'conflicted.txt')"
chk "S11 나머지 커밋"                      "1" "$(in_head "$SB" 'fine.txt')"
chk "S11 충돌 파일 실 인덱스 미스테이징"    "0" "$(staged "$SB" 'conflicted.txt')"

# ── S12 삭제 ─────────────────────────────────────────────────────────────────
SB=$(new_repo)
rm -f "$SB/tracked3.txt"; rm -f "$SB/tracked2.txt"
mk_transcript "$SB.meta/proj/sessD.jsonl" "E:$(wpath "$SB/tracked3.txt")"
run_hook "$SB" "$(end_input sessD "$(wpath "$SB.meta/proj/sessD.jsonl")")" > /dev/null
chk "S12 세션 파일 삭제 커밋"              "D	tracked3.txt" "$(git -C "$SB" show --name-status --format= HEAD | grep tracked3 || true)"
chk "S12 남의 삭제는 미커밋"               " D tracked2.txt" "$(st_line "$SB" tracked2.txt)"

# ── S13 linked worktree ──────────────────────────────────────────────────────
BASE=$(mktemp -d); SANDBOXES+=("$BASE"); MAIN="$BASE/primary"; WT="$BASE/wt"; META="$BASE/meta"
mkdir -p "$MAIN/02_Infrastructure/hooks" "$META/proj"
git -C "$MAIN" init -q -b main 2>/dev/null || { git -C "$MAIN" init -q; git -C "$MAIN" symbolic-ref HEAD refs/heads/main; }
git -C "$MAIN" config user.email "test@qvest.local"; git -C "$MAIN" config user.name "scope-test"; git -C "$MAIN" config commit.gpgsign false
git -C "$MAIN" config core.autocrlf false
printf '# sandbox marker (qvest root)\n' > "$MAIN/02_Infrastructure/hooks/qvest_hook_router.py"
cp "$_SELF_DIR/../../02_Infrastructure/hooks/resolve_project.sh" "$_SELF_DIR/../../02_Infrastructure/hooks/auto_commit_on_stop.sh" "$MAIN/02_Infrastructure/hooks/"
printf '.cache/\n' > "$MAIN/.gitignore"; printf 'base\n' > "$MAIN/tracked.txt"
git -C "$MAIN" add -A >/dev/null 2>&1; git -C "$MAIN" commit -qm base >/dev/null 2>&1
git -C "$MAIN" worktree add -q -b feature "$WT" >/dev/null 2>&1
echo w > "$WT/wt_new.txt"; echo o > "$WT/wt_other.txt"; echo p > "$MAIN/main_dirty.txt"
mk_transcript "$META/proj/sessW.jsonl" "$(wpath "$WT/wt_new.txt")" "$(wpath "$MAIN/main_dirty.txt")"
MAIN_H0=$(git -C "$MAIN" rev-parse HEAD); WT_N0=$(git -C "$WT" rev-list --count HEAD)
printf '%s' "$(end_input sessW "$(wpath "$META/proj/sessW.jsonl")")" | env -u QVEST_UNATTENDED_LANE -u QVEST_CLEAN_LANE -u GIT_INDEX_FILE \
  QVEST_AC_LANE_CHECK=0 CLAUDE_PROJECT_DIR="$WT" QM_ROOT="$MAIN" QVEST_AC_PROJECT= QVEST_AC_LOG="$META/ac.log" \
  QVEST_AC_MARKER="$META/ac.marker" QVEST_SKIP_AUTO_COMMIT=0 bash "$WT/02_Infrastructure/hooks/auto_commit_on_stop.sh" > /dev/null 2>>"$META/ac.stderr"
chk "S13 worktree 브랜치 커밋 1건"         "$((WT_N0+1))" "$(git -C "$WT" rev-list --count HEAD)"
chk "S13 wt_new 커밋"                      "1" "$(in_head "$WT" 'wt_new.txt')"
chk "S13 worktree 의 남의 파일 제외"        "0" "$(in_head "$WT" 'wt_other.txt')"
chk "S13 primary HEAD 불변"                "$MAIN_H0" "$(git -C "$MAIN" rev-parse HEAD)"
chk "S13 primary dirty 무접촉"             "?? main_dirty.txt" "$(st_line "$MAIN" main_dirty.txt)"

# ── V1 ★위반 주입: 같은 무대를 QVEST_AC_SCOPE=all 로 ─────────────────────────
SB=$(new_repo); stage_two_sessions "$SB"
run_hook "$SB" "$(end_input sessA "$(wpath "$SB.meta/proj/sessA.jsonl")")" "$HOOK" all > /dev/null
chk "V1 주입(all): B 신규가 쓸려 들어감"    "1" "$(in_head "$SB" 'b_new.txt')"
chk "V1 주입(all): B 스테이징도 쓸려 들어감" "1" "$(in_head "$SB" 'b_staged.txt')"

# ── M1 · M2 ★뮤테이션 ────────────────────────────────────────────────────────
MUT_DIR=$(mktemp -d); SANDBOXES+=("$MUT_DIR")
cp "$_SELF_DIR/../../02_Infrastructure/hooks/resolve_project.sh" "$MUT_DIR/" 2>/dev/null || true
M1="$MUT_DIR/auto_commit_on_stop.sh"
sed 's#^git --literal-pathspecs add -A --pathspec-from-file="\$AC_TMPD/scope.z" --pathspec-file-nul 2>>"\$LOG"$#git add -A 2>>"$LOG"#' "$HOOK" > "$M1"
if cmp -s "$HOOK" "$M1"; then
  bad "M1 뮤테이션 적용" "치환 0건 — 세션 스테이징 줄을 못 찾음(검사기 갱신 필요)"
else
  SB=$(new_repo); stage_two_sessions "$SB"
  run_hook "$SB" "$(end_input sessA "$(wpath "$SB.meta/proj/sessA.jsonl")")" "$M1" > /dev/null
  chk "M1 뮤테이션(전체 add): S1 격리가 깨짐을 검출" "1" "$(in_head "$SB" 'b_new.txt')"
fi
M2="$MUT_DIR/ac_m2.sh"
awk '/env -u GIT_INDEX_FILE git --literal-pathspecs reset -q HEAD/ { sub(/env -u GIT_INDEX_FILE git --literal-pathspecs reset -q HEAD --pathspec-from-file="\$AC_TMPD\/committed.z" --pathspec-file-nul 2>>"\$LOG"/, "true") } { print }' "$HOOK" > "$M2"
cp "$M2" "$MUT_DIR/auto_commit_on_stop.sh"
if cmp -s "$HOOK" "$M2"; then
  bad "M2 뮤테이션 적용" "치환 0건 — 동기화 줄을 못 찾음(검사기 갱신 필요)"
else
  SB=$(new_repo); stage_two_sessions "$SB"
  run_hook "$SB" "$(end_input sessA "$(wpath "$SB.meta/proj/sessA.jsonl")")" "$MUT_DIR/auto_commit_on_stop.sh" > /dev/null
  M2_ST="$(st_line "$SB" a_new.txt)"
  if [ -n "$M2_ST" ]; then ok "M2 뮤테이션(동기화 제거): S3 유령 스테이징 검출 [$M2_ST]"; else bad "M2 뮤테이션(동기화 제거)" "실 인덱스가 깨끗 — S3 가 동기화 기전을 재지 못함"; fi
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
echo "{\"test\":\"auto_commit_session_scope\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ] || exit 1
