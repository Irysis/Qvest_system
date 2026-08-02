#!/usr/bin/env bash
#==============================================================================
# test_auto_commit_worktree_target.sh — git 쓰기 훅 3종의 "어느 트리에 커밋하나" 계약
#
# 배경 (2026-08-02 실측, 도훈 보고):
#   auto_commit_on_stop.sh:66 이 프로젝트 루트를 하드코딩 glob
#   `ls -d <후보들> | head -1` 로 해석하고 CLAUDE_PROJECT_DIR 을 **전혀 읽지 않았다**.
#   첫 후보는 항상 main → worktree 세션에서 Stop 훅이 main 의 작업트리를 커밋하고
#   worktree 는 건드리지 않는다. 그런데 훅은 "[OK] N files committed" 를 보고한다.
#   ★ 무해한 no-op 이 아니다 = 하지 않은 일에 대한 성공 보고(작업 유실 + 유실의 은폐).
#   실측: worktree strange-leakey-dedfca 세션의 보고 4회가 전부 main 커밋
#   (3eeafa3d/26d638aa/8e2d75e1 …), worktree 브랜치 HEAD 는 d34c9ee1 에 정지,
#   정작 수리본은 어느 트리에도 커밋되지 않은 채 작업트리에만 존재 → 수동 회수(54daebfc).
#   같은 기전이 메모리에 개별 부주의로 기록돼 온 "수리했는데 main 에 없음" 계통
#   (date32 writer · lcode harvester · resolve_project marker · AST monthly asof)의 후보 원인.
#
# 검증 축 (실제 git repo + 실제 linked worktree 에서 훅을 실 구동 — 로직 재현 아님):
#   F  구조: 훅 3종이 무조건-glob 을 쓰지 않고 resolve_project 규약을 경유한다.
#      ★F 가 빨강이면 그 훅의 행동 축은 **실행하지 않는다** — 구 glob 은 실 저장소를
#        집으므로 sandbox 테스트가 진짜 main 을 커밋/푸시하게 된다(검사가 사고를 일으킴).
#   A  worktree 세션(CLAUDE_PROJECT_DIR=<worktree>)의 변경분이 **그 worktree 브랜치**에 커밋
#   B  같은 실행에서 **primary 트리는 오염되지 않음** (HEAD 불변 · dirty 잔존)
#   C  커밋할 게 없으면 성공 보고를 내지 않음 ([OK] 부재 · HEAD 불변)
#   D  보고 문구에 대상 브랜치 + 트리 라벨이 드러난다 (오늘의 오독 재발 방지)
#   E  ★위반 주입: 루트 해석만 구 glob 형태(첫 존재 후보 · CPD 미조회)로 되돌린 변종은
#      A/B 를 **실패**한다 — A/B 의 초록이 해석 규약에서 나온 것임을 실증(죽은 검사 방지)
#   G  milestone_commit.sh (PostToolUse) 도 worktree 브랜치에 커밋
#   H  auto_push_on_stop.sh 는 worktree 트리를 보고, upstream 없는 ephemeral 브랜치를
#      말없이 publish 하지 않으며(성공 보고도 없음), opt-in 시에만 push
#
# 요약 규약: 마지막 줄 {"test":"auto_commit_worktree_target","pass":N,"fail":N,"total":N}
#==============================================================================
set -u

# 앵커 = self-first (2026-08-02 러너 앵커 수리 정합 — env-first 면 worktree 에서 돌린
# 배터리가 main 의 훅을 검사한다. 순서만이 판별한다.)
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$_SELF_DIR/../.." && pwd)"
HOOKS="$ROOT/02_Infrastructure/hooks"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $1  ($2)"; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expect=$2 actual=$3"; fi; }

SANDBOXES=()
cleanup() {
  for s in ${SANDBOXES[@]+"${SANDBOXES[@]}"}; do
    # linked worktree 가 잠긴 경우 대비 — 실패해도 테스트 결과에 영향 없음
    rm -rf "$s" 2>/dev/null || true
  done
}
trap cleanup EXIT

echo "=== test_auto_commit_worktree_target (트리 표적 계약) ==="
echo "ROOT=$ROOT"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# F. 구조 축 — 무조건-glob 부재 + resolve_project 규약 경유
#    (행동 축의 실행 가드이기도 하다)
# ─────────────────────────────────────────────────────────────────────────────
declare -A STRUCT_OK=()
struct_check() { # $1=hook basename
  local f="$HOOKS/$1" glob_hit src_hit
  if [ ! -f "$f" ]; then bad "F[$1] 훅 존재" "부재: $f"; STRUCT_OK["$1"]=0; return; fi
  glob_hit=$(grep -Fc 'PROJECT=$(ls -d /c/Users' "$f" || true)
  src_hit=$(grep -Fc 'resolve_project.sh' "$f" || true)
  if [ "$glob_hit" != "0" ]; then
    bad "F[$1] 무조건-glob 부재" "PROJECT=\$(ls -d /c/Users… 잔존 ${glob_hit}건 (CPD 미조회 = 구 결함)"
    STRUCT_OK["$1"]=0
  else
    ok "F[$1] 무조건-glob 부재"
  fi
  if [ "$src_hit" = "0" ]; then
    bad "F[$1] resolve_project 규약 경유" "resolve_project.sh 참조 0건"
    STRUCT_OK["$1"]=0
  else
    ok "F[$1] resolve_project 규약 경유"
  fi
  [ -n "${STRUCT_OK[$1]:-}" ] || STRUCT_OK["$1"]=1
}
struct_check auto_commit_on_stop.sh
struct_check auto_push_on_stop.sh
struct_check milestone_commit.sh
echo ""

skip_behavior() { # $1=hook basename $2=축 라벨들(설명)
  bad "$2" "F[$1] 빨강 — 구 glob 은 **실 저장소**를 집으므로 행동 축 실행 생략(테스트가 main 을 커밋하는 사고 방지)"
}

# ─────────────────────────────────────────────────────────────────────────────
# sandbox: primary repo + linked worktree + bare origin
# ─────────────────────────────────────────────────────────────────────────────
new_env() { # stdout = base dir ($base/primary, $base/wt, $base/meta, $base/origin.git)
  local base; base=$(mktemp -d); SANDBOXES+=("$base")
  local main="$base/primary" wt="$base/wt" meta="$base/meta"
  mkdir -p "$main" "$meta"
  git -C "$main" init -q -b main 2>/dev/null || {
    git -C "$main" init -q
    git -C "$main" symbolic-ref HEAD refs/heads/main
  }
  git -C "$main" config user.email "test@qvest.local"
  git -C "$main" config user.name  "wt-target-test"
  git -C "$main" config commit.gpgsign false
  mkdir -p "$main/02_Infrastructure/hooks"
  # ★ marker = resolve_project.sh 가 정체성을 검사하는 파일. 커밋해야 worktree 체크아웃에도 존재.
  printf '# sandbox marker (qvest root)\n' > "$main/02_Infrastructure/hooks/qvest_hook_router.py"
  # 훅 사본은 **파일명을 유지**한다 (main-guard basename 함정 회피)
  cp "$HOOKS/resolve_project.sh"        "$main/02_Infrastructure/hooks/" 2>/dev/null || true
  cp "$HOOKS/auto_commit_on_stop.sh"    "$main/02_Infrastructure/hooks/" 2>/dev/null || true
  cp "$HOOKS/auto_push_on_stop.sh"      "$main/02_Infrastructure/hooks/" 2>/dev/null || true
  cp "$HOOKS/milestone_commit.sh"       "$main/02_Infrastructure/hooks/" 2>/dev/null || true
  printf '.cache/\n' > "$main/.gitignore"
  printf 'base\n' > "$main/tracked.txt"
  git -C "$main" add -A >/dev/null 2>&1
  git -C "$main" commit -qm "base" >/dev/null 2>&1
  git -C "$main" worktree add -q -b feature "$wt" >/dev/null 2>&1
  printf '%s' "$base"
}

head_of()   { git -C "$1" rev-parse HEAD 2>/dev/null; }
ncommits()  { git -C "$1" rev-list --count HEAD 2>/dev/null; }
in_head()   { git -C "$1" show --name-status --format="" HEAD 2>/dev/null | grep -c "$2" || true; }

run_ac() { # $1=cpd $2=qm_root $3=meta $4=hook경로
  echo '{}' | env CLAUDE_PROJECT_DIR="$1" QM_ROOT="$2" \
    QVEST_AC_LOG="$3/ac.log" QVEST_AC_MARKER="$3/ac.marker" \
    QVEST_SKIP_AUTO_COMMIT=0 QVEST_AC_PROJECT= \
    bash "$4" 2>>"$3/ac.stderr"
}

# ─────────────────────────────────────────────────────────────────────────────
# A/B/D. worktree 세션 → worktree 브랜치 커밋 · primary 무오염 · 보고에 대상 표기
# ─────────────────────────────────────────────────────────────────────────────
if [ "${STRUCT_OK[auto_commit_on_stop.sh]:-0}" = "1" ]; then
  BASE=$(new_env); MAIN="$BASE/primary"; WT="$BASE/wt"; META="$BASE/meta"
  printf 'worktree work\n' > "$WT/wt_new.txt"
  printf 'primary dirt\n'  > "$MAIN/main_dirty.txt"
  MAIN_HEAD0=$(head_of "$MAIN"); WT_N0=$(ncommits "$WT")
  # ★QM_ROOT 를 primary 로 준다 = CPD(tier0) 가 QM_ROOT(tier1) 를 이기는지의 양성 대조
  OUT=$(run_ac "$WT" "$MAIN" "$META" "$WT/02_Infrastructure/hooks/auto_commit_on_stop.sh")

  chk "A worktree 브랜치에 커밋 1건 증가"   "$((WT_N0+1))" "$(ncommits "$WT")"
  chk "A wt_new.txt 가 worktree HEAD 에"    "1"            "$(in_head "$WT" 'wt_new.txt')"
  chk "B primary HEAD 불변"                 "$MAIN_HEAD0"  "$(head_of "$MAIN")"
  chk "B primary dirty 잔존(미커밋)"        "1"            "$(git -C "$MAIN" status --porcelain | grep -c 'main_dirty.txt' || true)"
  # ★`--all` 을 쓰면 안 된다 (2026-08-03 정정): linked worktree 는 primary 와 **ref 저장소를
  #   공유**하므로 --all 은 worktree 가 방금 커밋한 refs/heads/feature 까지 훑는다 →
  #   훅이 **올바로 동작할 때 정확히 이 축이 빨강**이 된다(수리를 결함으로 신고하는 축).
  #   이 축의 의도는 "primary 의 자기 브랜치가 오염되지 않았나" 이므로 main 으로 좁힌다.
  #   E 축(200~202행)의 --all 은 의미가 다르다 — 거기선 "변종이 커밋한 흔적이 **어느 ref
  #   에도** 없나"를 재는 것이라 넓은 범위가 정본이다. 같은 표현이지만 묻는 질문이 다르다.
  chk "B primary(main) 는 wt_new 를 모름"   "0"            "$(git -C "$MAIN" log --oneline main -- wt_new.txt 2>/dev/null | wc -l | tr -d ' ')"

  case "$OUT" in *feature*) ok "D 보고에 브랜치명(feature)" ;; *) bad "D 보고에 브랜치명(feature)" "out=${OUT:0:200}" ;; esac
  case "$OUT" in *tree=*)   ok "D 보고에 트리 라벨(tree=)"  ;; *) bad "D 보고에 트리 라벨(tree=)"  "out=${OUT:0:200}" ;; esac
  case "$OUT" in *'[OK]'*)  ok "D 커밋 시 성공 보고 존재"   ;; *) bad "D 커밋 시 성공 보고 존재"   "out=${OUT:0:200}" ;; esac

  # ── C. 변경 없음 → 성공 보고 금지 ──────────────────────────────────────────
  WT_HEAD1=$(head_of "$WT")
  OUT2=$(run_ac "$WT" "$MAIN" "$META" "$WT/02_Infrastructure/hooks/auto_commit_on_stop.sh")
  chk "C 변경 없음 → HEAD 불변"            "$WT_HEAD1" "$(head_of "$WT")"
  case "$OUT2" in *'[OK]'*) bad "C 변경 없음 → 성공 보고 없음" "out=${OUT2:0:200}" ;; *) ok "C 변경 없음 → 성공 보고 없음" ;; esac
  if grep -q 'NO_CHANGES' "$META/ac.log" 2>/dev/null; then ok "C 로그에 NO_CHANGES"; else bad "C 로그에 NO_CHANGES" "log=$(tail -2 "$META/ac.log" 2>/dev/null | tr '\n' ';')"; fi
else
  skip_behavior auto_commit_on_stop.sh "A/B/C/D auto_commit 행동 축"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# E. ★위반 주입 — 루트 해석만 구 glob 형태로 되돌린 변종은 primary 를 커밋한다
#    (sandbox 후보로만 glob 을 구성 — 실 저장소는 절대 후보에 넣지 않는다)
# ─────────────────────────────────────────────────────────────────────────────
make_legacy() { # $1=src $2=dst $3=첫후보 $4=둘째후보 ; rc=0 변이 적용됨
  local src="$1" dst="$2" c1="$3" c2="$4"
  if grep -Fq 'QVEST_ROOT_RESOLUTION >>>' "$src"; then
    awk -v c1="$c1" -v c2="$c2" '
      index($0,"QVEST_ROOT_RESOLUTION >>>")>0 {
        print; print "PROJECT=$(ls -d \"" c1 "\" \"" c2 "\" 2>/dev/null | head -1)"; skip=1; next }
      index($0,"QVEST_ROOT_RESOLUTION <<<")>0 { skip=0 }
      !skip { print }
    ' "$src" > "$dst"
  else
    # 수리 전 형태 — 구 glob 라인 자체를 sandbox 후보로 치환 (기전 동일: 첫 존재 후보 · CPD 미조회)
    awk -v c1="$c1" -v c2="$c2" '
      index($0,"PROJECT=$(ls -d /c/Users")>0 {
        print "PROJECT=$(ls -d \"" c1 "\" \"" c2 "\" 2>/dev/null | head -1)"; next }
      { print }
    ' "$src" > "$dst"
  fi
  # 변이가 실제로 적용됐는지 (미적용 시 E 는 공허해진다 — 여기서 크게 실패시킨다)
  if cmp -s "$src" "$dst"; then return 1; fi
  if grep -Fq 'ls -d /c/Users' "$dst"; then return 2; fi   # 실 저장소 후보 잔존 = 실행 금지
  return 0
}

BASE=$(new_env); MAIN="$BASE/primary"; WT="$BASE/wt"; META="$BASE/meta"
LEGACY="$WT/02_Infrastructure/hooks/auto_commit_on_stop.sh"
if make_legacy "$HOOKS/auto_commit_on_stop.sh" "$LEGACY" "$MAIN" "$WT"; then
  printf 'worktree work\n' > "$WT/wt_new.txt"
  printf 'primary dirt\n'  > "$MAIN/main_dirty.txt"
  MAIN_N0=$(ncommits "$MAIN"); WT_N0=$(ncommits "$WT")
  run_ac "$WT" "$MAIN" "$META" "$LEGACY" > /dev/null
  # 구 기전은 CPD 를 무시하고 첫 후보(primary)를 집는다 → primary 가 커밋되고 worktree 는 정지
  chk "E 주입: primary 가 대신 커밋됨"      "$((MAIN_N0+1))" "$(ncommits "$MAIN")"
  chk "E 주입: worktree 브랜치 정지"        "$WT_N0"         "$(ncommits "$WT")"
  chk "E 주입: wt_new 는 아무 데도 없음"    "0"              "$(git -C "$MAIN" log --all --oneline -- wt_new.txt 2>/dev/null | wc -l | tr -d ' ')"
else
  rc=$?
  if [ "$rc" = "1" ]; then bad "E 위반 주입 적용" "변이 미적용 — 해석 블록 sentinel/구 glob 라인을 못 찾음(검사기 갱신 필요)"
  else                     bad "E 위반 주입 적용" "변종에 실 저장소 glob 잔존 — 실행 금지"; fi
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# G. milestone_commit.sh (PostToolUse[Write]) 도 worktree 브랜치에
# ─────────────────────────────────────────────────────────────────────────────
if [ "${STRUCT_OK[milestone_commit.sh]:-0}" = "1" ]; then
  BASE=$(new_env); MAIN="$BASE/primary"; WT="$BASE/wt"; META="$BASE/meta"
  mkdir -p "$WT/stage_artifacts/l_code/qpm"
  LC_FILE="$WT/stage_artifacts/l_code/qpm/l_code_TEST_0001.json"
  printf '{"l_code":"L-WTTEST-0001","note":"sandbox"}\n' > "$LC_FILE"
  MAIN_HEAD0=$(head_of "$MAIN"); WT_N0=$(ncommits "$WT")
  printf '{"tool_input":{"file_path":"%s"}}' "$LC_FILE" \
    | env CLAUDE_PROJECT_DIR="$WT" QM_ROOT="$MAIN" QVEST_MC_LOG="$META/mc.log" \
          QVEST_SKIP_MILESTONE_COMMIT=0 \
          bash "$WT/02_Infrastructure/hooks/milestone_commit.sh" > "$META/mc.out" 2>>"$META/mc.stderr"
  chk "G milestone → worktree 커밋 1건"   "$((WT_N0+1))" "$(ncommits "$WT")"
  chk "G milestone → primary HEAD 불변"   "$MAIN_HEAD0"  "$(head_of "$MAIN")"
  case "$(cat "$META/mc.out" 2>/dev/null)" in *feature*) ok "G 보고에 브랜치명" ;; *) bad "G 보고에 브랜치명" "out=$(head -c 200 "$META/mc.out" 2>/dev/null)" ;; esac
else
  skip_behavior milestone_commit.sh "G milestone 행동 축"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# H. auto_push_on_stop.sh — worktree 트리를 보되 ephemeral 브랜치를 말없이 publish 금지
# ─────────────────────────────────────────────────────────────────────────────
if [ "${STRUCT_OK[auto_push_on_stop.sh]:-0}" = "1" ]; then
  BASE=$(new_env); MAIN="$BASE/primary"; WT="$BASE/wt"; META="$BASE/meta"
  ORIGIN="$BASE/origin.git"
  git init -q --bare "$ORIGIN"
  git -C "$MAIN" remote add origin "$ORIGIN"
  git -C "$MAIN" push -q -u origin main
  # primary 는 origin 대비 ahead(구 기전이면 이걸 밀어버린다) · worktree 는 upstream 없음
  printf 'ahead\n' >> "$MAIN/tracked.txt"
  git -C "$MAIN" commit -qam "primary ahead"
  printf 'wt commit\n' > "$WT/wt_only.txt"
  git -C "$WT" add -A >/dev/null 2>&1; git -C "$WT" commit -qm "worktree commit"
  ORIGIN_MAIN0=$(git -C "$ORIGIN" rev-parse refs/heads/main)

  OUT=$(echo '{}' | env CLAUDE_PROJECT_DIR="$WT" QM_ROOT="$MAIN" QVEST_AP_LOG="$META/ap.log" \
        QVEST_SKIP_AUTO_PUSH=0 bash "$WT/02_Infrastructure/hooks/auto_push_on_stop.sh" 2>>"$META/ap.stderr")
  chk "H origin/main 미전진 (primary 를 보지 않음)" "$ORIGIN_MAIN0" "$(git -C "$ORIGIN" rev-parse refs/heads/main)"
  chk "H ephemeral 브랜치 미publish"                "0" "$(git -C "$ORIGIN" rev-parse --verify -q refs/heads/feature >/dev/null 2>&1 && echo 1 || echo 0)"
  case "$OUT" in *'[OK]'*) bad "H push 안 했으면 성공 보고 없음" "out=${OUT:0:200}" ;; *) ok "H push 안 했으면 성공 보고 없음" ;; esac
  if grep -q 'WORKTREE_NEW_BRANCH_SKIP' "$META/ap.log" 2>/dev/null; then ok "H 로그에 사유 기록(WORKTREE_NEW_BRANCH_SKIP)"
  else bad "H 로그에 사유 기록(WORKTREE_NEW_BRANCH_SKIP)" "log=$(tail -3 "$META/ap.log" 2>/dev/null | tr '\n' ';')"; fi

  # opt-in 시에는 push (기능 자체가 죽지 않았음을 실증 — 침묵 무력화 방지)
  echo '{}' | env CLAUDE_PROJECT_DIR="$WT" QM_ROOT="$MAIN" QVEST_AP_LOG="$META/ap2.log" \
      QVEST_SKIP_AUTO_PUSH=0 QVEST_AC_PUSH_WORKTREE=1 \
      bash "$WT/02_Infrastructure/hooks/auto_push_on_stop.sh" > /dev/null 2>>"$META/ap.stderr"
  chk "H opt-in 시 feature push 됨" "1" "$(git -C "$ORIGIN" rev-parse --verify -q refs/heads/feature >/dev/null 2>&1 && echo 1 || echo 0)"
else
  skip_behavior auto_push_on_stop.sh "H auto_push 행동 축"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
echo "{\"test\":\"auto_commit_worktree_target\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ] || exit 1
