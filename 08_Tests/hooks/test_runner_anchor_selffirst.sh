#!/usr/bin/env bash
#==============================================================================
# test_runner_anchor_selffirst.sh — 테스트 러너 앵커 순서(self-first) 위반 주입 테스트
#
# 계약: **테스트 러너는 자기가 실린 트리를 검사한다.**
#       루트 후보 1순위 = 스크립트 자신의 위치(R `--file=` / Python `__file__`),
#       환경변수(CLAUDE_PROJECT_DIR / QM_ROOT)는 그 뒤. 표지 검증은 모든 tier 에.
#       참조: 02_Infrastructure/docs/rules/r-portability.md 금칙 ④(resolver 우선순위)
#
# 왜 이 검사기가 필요한가 (2026-08-02 실사고 계통):
#   Bash 툴 환경에서 CLAUDE_PROJECT_DIR 은 **미설정**(훅 안에서만 세워진다)이고
#   QM_ROOT 는 ~/.Renviron 이 **main 트리**로 고정한다. 그래서 env-first 러너를
#   worktree 에서 돌리면 루트가 main 으로 해석되고 — 발견/import 가 전부 main 을 향한다.
#   실측(수리 전):
#     · 08_Tests/regime/run_all.R      : worktree 6개 / main 5개 상태에서
#                                        worktree 실행 → "Test files found: 5" (main 것)
#     · 02_Infrastructure/tests/test_continuity_gate.py
#                                      : cwd=worktree → ROOT=main, `G.__file__` = main 의 파일
#   파급은 둘 다 **오독**이다 — worktree 의 수리본이 한 번도 검사되지 않는데 초록이 뜬다
#   ("안 고친 것을 고쳤다고 읽게 만든다"). 신설 파일은 아예 실행조차 안 된다.
#
# ★표지(marker) 검증은 이 갈림을 **판별하지 못한다** — main 도 worktree 도 표지를 갖는다.
#   가르는 것은 오직 후보 **순서**뿐이라, 순서 자체를 계약으로 못박는다.
# ★공유 resolver 2벌(02_Infrastructure/{hooks,ops}/resolve_project.sh)은 **무변경**이며
#   여기서 검사하지 않는다 — 소비자 계층이 다르다(hooks=CPD-first / ops=QM_ROOT-first,
#   2026-08-01 도훈 결정. 그 순서는 test_resolve_project_marker.sh 축 G 가 양방향 고정).
#   러너만 self-first 인 이유: 테스트는 *자기가 실린 트리*를 재야 한다.
# ★자매 검사기: test_resolve_project_marker.sh(공유 resolver 2벌 / run_all_hooks.sh 앵커).
#   이 파일은 그 검사기가 구조적으로 못 보는 표면 — **.R 러너와 .py 배터리** — 을 덮는다.
#
# 검사 축 (러너 2종 각각):
#   1 prologue_extracted  — 해석 프롤로그 추출 성공.
#                           ★가드 needle 은 **수리 전후 모두 존재하는 구조**만 본다
#                             (R: `if (!exists("PROJECT_ROOT"))` ~ `setwd(PROJECT_ROOT)` /
#                              Py: 파일 머리 ~ `sys.path.insert`). 수리가 도입한 구조를
#                             needle 로 잡으면, 수리를 통째로 되돌렸을 때 축이 아예 실행되지
#                             않고 "needle 갱신 필요" 정비 메시지가 뜬다 — 결함 상태를
#                             유지보수 과제로 오진시킨다(run_all_hooks 앵커 수리 중 실제로
#                             저지르고 정정한 실수). **구판을 넣어도 축 2 가 행동으로 잡아야 한다.**
#                           ★순서 줄(`.qv_order` / `_ANCHOR_ORDER`)의 부재는 추출 실패가
#                             아니라 **계약 위반**으로 따로 보고한다(축 4). 앵커 순서는
#                             단일 감사 가능한 줄로 노출돼 있어야 한다.
#   2 self_first          — 위반 주입: env 가 **표지를 가진 다른 트리**를 가리켜도 자기 트리 선택
#   3 quiet_when_self     — 자기 트리 해석 시 override 경보 무발화(상시 경보는 곧 무시된다)
#   4 mutant_detected     — 순서를 구판(env-first)으로 되돌린 사본에서 축 2 가 실제로 뒤집히는지.
#                           안 뒤집히면 축 2 의 "통과"는 계측 사망이지 통과가 아니다.
#   5 override_warns      — 표지 없는 self 는 기각되어 env 로 낙하하되 **stderr 로 보고**.
#                           침묵 낙하 = 이 계통의 재발 기전.
#   + py_no_main_fallback — Python 판의 하드코딩 main 폴백이 실제로 제거됐는지(정적 축).
#
# 단독 실행: bash 08_Tests/hooks/test_runner_anchor_selffirst.sh
#==============================================================================
set -uo pipefail

# ★앵커 1순위 = BASH_SOURCE, env 아님 — 이 파일이 강제하는 규율을 자기 자신에게도 적용한다.
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER_REL="02_Infrastructure/hooks/qvest_hook_router.py"
_pick_proj_dir() {
  local c
  for c in "$_SELF_DIR/../.." "${CLAUDE_PROJECT_DIR:-}" "${QM_ROOT:-}" "$PWD"; do
    if [[ -n "$c" && -f "${c//\\//}/$MARKER_REL" ]]; then (cd "${c//\\//}" && pwd); return 0; fi
  done
  return 1
}
if ! PROJ_DIR="$(_pick_proj_dir)"; then
  echo "❌ PROJECT_ROOT 해석 실패 — 표지 '$MARKER_REL' 를 가진 후보 없음" >&2
  echo '{"test":"runner_anchor_selffirst","pass":0,"fail":1,"total":1}'
  exit 1
fi

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS: %s%s\n' "$1" "${2:+ — $2}"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL: %s — %s\n' "$1" "$2"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Windows 인터프리터(R/python)에 넘길 경로는 mixed 형이어야 한다 — MSYS `/tmp/...` 는
# bash 에선 유효하고 Windows R/python 에선 `C:/tmp/...` 로 오해석돼 표지 검사가 조용히
# 빗나간다(r-portability 금칙 ③ 확장 · bootstrap.sh:20-22 의 `cygpath -m` 정본 idiom).
TMPW="$(cygpath -m "$TMP" 2>/dev/null || printf '%s' "$TMP")"

echo "=== runner anchor: self-first ==="
echo "  proj: $PROJ_DIR"
echo "  tmp : $TMPW"
echo ""

# ─── 공용: 표지를 갖춘 합성 트리 ──────────────────────────────────────────────
# ALT = "표지를 가진 **다른** 트리" = main 의 대역. 실사고 배치(worktree 실행 + env=main)
#   를 그대로 재현한다. main 실재에 의존하지 않기 위해 합성한다.
mk_tree() {  # $1=경로  $2=표지 상대경로
  mkdir -p "$1/$(dirname "$2")" && : > "$1/$2"
}

#==============================================================================
# (1) R 러너 — 08_Tests/regime/run_all.R
#==============================================================================
R_RUNNER="$PROJ_DIR/08_Tests/regime/run_all.R"
R_MARKER="02_Infrastructure/config.R"
R_ENVFIRST='  .qv_order <- c("CLAUDE_PROJECT_DIR", "QM_ROOT", "self", "cwd")'

# self 트리(표지 有) / bare self 트리(표지 無) / ALT(표지 有)
R_SELF="$TMP/r_self";  mk_tree "$R_SELF" "$R_MARKER"; mkdir -p "$R_SELF/08_Tests/regime"
R_BARE="$TMP/r_bare";  mkdir -p "$R_BARE/08_Tests/regime"     # 표지 없음 — self 기각 대상
R_ALT="$TMP/r_alt";    mk_tree "$R_ALT" "$R_MARKER"

# ★QM_ROOT 는 **shell 로 덮어쓸 수 없다** — R 이 시작 시 ~/.Renviron 을 적용해
#   `QM_ROOT=<main>` 이 셸 값을 덮는다(실측). 주입은 R_ENVIRON_USER 로 .Renviron 자체를
#   갈아끼워야 한다. 이 사실 자체가 "env 로 회피하면 되지 않나"를 봉쇄한다.
printf 'QM_ROOT=%s\n' "$TMPW/r_alt" > "$TMP/inject.Renviron"
: > "$TMP/empty.Renviron"

run_r_anchor() {  # $1=조각 경로(mixed)  $2=inject|clean  $3=CPD(""→unset)
  local frag="$1" mode="$2" cpd="${3:-}"
  local renv="$TMP/empty.Renviron"
  [ "$mode" = "inject" ] && renv="$TMP/inject.Renviron"
  local -a pre=(env -u QM_ROOT -u CLAUDE_PROJECT_DIR "R_ENVIRON_USER=$renv")
  [ -n "$cpd" ] && pre+=("CLAUDE_PROJECT_DIR=$cpd")
  # cwd = 표지 없는 중립 디렉토리(cwd tier 가 결과를 오염시키지 않도록) + 그 자리의
  # .Renviron 이 R_ENVIRON_USER 를 이기므로 비어 있어야 한다.
  ( cd "$TMP/neutral" && "${pre[@]}" Rscript "$frag" 2>"$TMP/r_stderr.txt" ) | tr -d '\r' \
    | grep '^RESOLVED=' | head -1 | sed 's/^RESOLVED=//'
}
mkdir -p "$TMP/neutral"

if [ ! -f "$R_RUNNER" ]; then
  bad "r_prologue_extracted" "러너 부재: $R_RUNNER"
else
  # 프롤로그만 떼어 낸다 — 러너 전체를 돌리면 regime 테스트 전량이 실행된다(수십 초~분).
  # 실행되는 바이트 그대로이되 비용 0.
  # ★범위 anchor 는 수리 전후 모두 존재하는 줄이다 — 구판(env-first)을 넣어도 추출은
  #   성공하고, 결함은 축 2 가 **행동으로** 보고한다.
  _R_FRAG_SRC="$(awk '/^if \(!exists\("PROJECT_ROOT"\)\)/{f=1} /^setwd\(PROJECT_ROOT\)/{f=0} f{print}' "$R_RUNNER")"
  _R_ORDER_LINE="$(printf '%s\n' "$_R_FRAG_SRC" | grep -m1 '\.qv_order *<-')"
  if [ -z "$_R_FRAG_SRC" ] || [[ "$_R_FRAG_SRC" != *"PROJECT_ROOT"* ]]; then
    # 추출 실패를 조용한 통과로 만들지 않는다 — 빈 조각은 아래 축들을 "기대와 다름"이
    # 아니라 **무엇도 재지 않은 채** 굴러가게 한다.
    bad "r_prologue_extracted" "프롤로그 추출 실패 — PROJECT_ROOT 해석 블록 부재(러너 구조 변경 시 awk 범위 갱신 필요)"
  else
    ok "r_prologue_extracted" "R 해석 프롤로그 추출 ($(printf '%s\n' "$_R_FRAG_SRC" | wc -l | tr -d ' ') 줄)"

    _r_emit() {  # $1=대상 트리  $2=본문
      mkdir -p "$1/08_Tests/regime"
      { printf '%s\n' "$2"; printf 'cat("RESOLVED=", PROJECT_ROOT, "\\n", sep = "")\n'; } \
        > "$1/08_Tests/regime/run_all.R"
    }
    _r_emit "$R_SELF" "$_R_FRAG_SRC"
    _r_emit "$R_BARE" "$_R_FRAG_SRC"

    # ── 축 2: 위반 주입 (QM_ROOT = 표지 가진 다른 트리) ─────────────────────
    GOT="$(run_r_anchor "$TMPW/r_self/08_Tests/regime/run_all.R" inject)"
    if [ "$GOT" = "$TMPW/r_self" ]; then
      ok "r_self_first" "QM_ROOT=별개 트리여도 자기 트리 선택 ($GOT)"
    elif [ "$GOT" = "$TMPW/r_alt" ]; then
      bad "r_self_first" "QM_ROOT 트리를 검사 대상으로 선택함 — 러너가 자기가 실린 트리를 안 잼(worktree 초록이 main 을 재는 원 결함)"
    else
      bad "r_self_first" "예상 밖 해석 — got '$GOT', want '$TMPW/r_self'"
    fi

    # 같은 계약을 CPD 에 대해서도 — 훅 경로는 CPD 를 세우므로 tier 2 도 self 뒤여야 한다.
    GOT="$(run_r_anchor "$TMPW/r_self/08_Tests/regime/run_all.R" clean "$TMPW/r_alt")"
    if [ "$GOT" = "$TMPW/r_self" ]; then
      ok "r_self_beats_cpd" "CLAUDE_PROJECT_DIR=별개 트리여도 자기 트리 선택"
    else
      bad "r_self_beats_cpd" "CPD 트리를 선택함 — got '$GOT', want '$TMPW/r_self'"
    fi

    # ── 축 3: 자기 트리 해석이면 무경보 ─────────────────────────────────────
    if grep -q "ANCHOR OVERRIDE" "$TMP/r_stderr.txt" 2>/dev/null; then
      bad "r_quiet_when_self" "자기 트리 해석인데 override 경보 발화 — 상시 경보는 곧 무시된다"
    else
      ok "r_quiet_when_self" "자기 트리 해석 시 무경보"
    fi

    # ── 축 4: 검사기 사망 통제 (돌연변이) ───────────────────────────────────
    # ★돌연변이는 **현재 후보 줄이 무엇이든** 그것을 env-first 로 갈아끼워 만든다
    #   (수리본 문자열에 의존하지 않음 — 위 가드 주석의 오진 기전과 같은 함정).
    if [ -z "$_R_ORDER_LINE" ]; then
      bad "r_mutant_detected" "앵커 순서가 단일 감사 가능한 줄(.qv_order)로 노출돼 있지 않음 — 계약 위반(순서를 기계가 읽고 갈아끼울 수 없으면 검출력을 실증할 수 없다)"
    elif [ "$_R_ORDER_LINE" = "$R_ENVFIRST" ]; then
      bad "r_mutant_detected" "원본이 이미 env-first — 돌연변이가 원본과 동일해 이 축이 공허(결함 자체는 r_self_first 가 보고)"
    else
      _r_emit "$TMP/r_mut" "${_R_FRAG_SRC//"$_R_ORDER_LINE"/$R_ENVFIRST}"
      GOT="$(run_r_anchor "$TMPW/r_mut/08_Tests/regime/run_all.R" inject)"
      if [ "$GOT" = "$TMPW/r_alt" ]; then
        ok "r_mutant_detected" "순서를 env-first 로 되돌리면 별개 트리가 선택됨 — r_self_first 가 실제로 이 차이를 잼"
      else
        bad "r_mutant_detected" "env-first 로 되돌려도 자기 트리 선택 (got '$GOT') — r_self_first 가 무력(계측 사망)"
      fi
    fi

    # ── 축 5: 표지 없는 self → env 낙하 + 경보 ──────────────────────────────
    GOT="$(run_r_anchor "$TMPW/r_bare/08_Tests/regime/run_all.R" inject)"
    if [ "$GOT" = "$TMPW/r_alt" ]; then
      ok "r_override_value" "표지 없는 self 기각 → QM_ROOT 로 낙하 ($GOT)"
    else
      bad "r_override_value" "self 기각 후 낙하 실패 — got '$GOT', want '$TMPW/r_alt'"
    fi
    if grep -q "ANCHOR OVERRIDE" "$TMP/r_stderr.txt" 2>/dev/null; then
      ok "r_override_warns" "앵커 갈림을 stderr 로 보고 (조용한 override 아님)"
    else
      bad "r_override_warns" "앵커가 자기 트리와 갈렸는데 무경보 — '어느 트리를 쟀나'가 로그에 안 남는다"
    fi
  fi
fi

#==============================================================================
# (2) Python 배터리 — 02_Infrastructure/tests/test_continuity_gate.py
#==============================================================================
PY_RUNNER="$PROJ_DIR/02_Infrastructure/tests/test_continuity_gate.py"
PY_MARKER="02_Infrastructure/axiom/continuity_gate.py"
PY_ENVFIRST='_ANCHOR_ORDER = ("CLAUDE_PROJECT_DIR", "QM_ROOT", "self", "cwd")'

# 해석기: bare python3 금지(Windows Store 스텁이라 스크립트를 실행하지 않는다 —
#   총계 0 이 "ALL PASS" 로 위장되는 계통. [[reference-python3-windows-stub-use-qvest-py]]).
PY_BIN="${QVEST_PY_BIN:-${QVEST_PY:-}}"; PY_BIN="${PY_BIN//\\//}"
[ -x "$PY_BIN" ] || PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"

PY_SELF="$TMP/py_self"; mk_tree "$PY_SELF" "$PY_MARKER"
PY_BARE="$TMP/py_bare"; mkdir -p "$PY_BARE"                    # 표지 없음
PY_ALT="$TMP/py_alt";   mk_tree "$PY_ALT" "$PY_MARKER"

run_py_anchor() {  # $1=조각 경로(mixed)  $2=QM_ROOT(""→unset)  $3=CPD(""→unset)
  local frag="$1" qm="${2:-}" cpd="${3:-}"
  local -a pre=(env -u QM_ROOT -u CLAUDE_PROJECT_DIR)
  [ -n "$qm" ]  && pre+=("QM_ROOT=$qm")
  [ -n "$cpd" ] && pre+=("CLAUDE_PROJECT_DIR=$cpd")
  ( cd "$TMP/neutral" && "${pre[@]}" "$PY_BIN" "$frag" 2>"$TMP/py_stderr.txt" ) | tr -d '\r' \
    | grep '^RESOLVED=' | head -1 | sed 's/^RESOLVED=//'
}

if [ ! -f "$PY_RUNNER" ]; then
  bad "py_prologue_extracted" "배터리 부재: $PY_RUNNER"
else
  # 하드코딩 main 폴백 제거의 정적 축 — 요청된 수리의 핵심 한 조각이라 따로 못박는다.
  # (행동 축만 두면 "표지 검증은 붙였는데 폴백 리터럴은 남아 있는" 절반 수리가 통과한다.)
  if grep -q 'or *"C:/Users/99922/OneDrive/Quant_Module_Moltbot"' "$PY_RUNNER"; then
    bad "py_no_main_fallback" "하드코딩 main 경로 폴백이 남아 있음 — 표지 없는 환경에서 조용히 main 을 검사한다"
  else
    ok "py_no_main_fallback" "하드코딩 main 폴백 제거됨 (표지 검증으로 대체)"
  fi

  # ★범위 = **파일 머리부터 `sys.path.insert` 직전까지**. 이 종결 줄은 수리 전후 모두
  #   존재하므로(구판도 ROOT 를 세운 직후 같은 줄을 쓴다) 구판을 넣어도 추출이 성공하고,
  #   결함은 축 2 가 **행동으로** 보고한다. 머리에 import 가 포함돼 있어 별도 주입 불필요.
  _PY_FRAG_SRC="$(awk '/^sys\.path\.insert\(0, os\.path\.join\(ROOT/{exit} {print}' "$PY_RUNNER")"
  _PY_ORDER_LINE="$(printf '%s\n' "$_PY_FRAG_SRC" | grep -m1 '^_ANCHOR_ORDER *=')"
  if [ -z "$_PY_FRAG_SRC" ] || ! grep -q '^sys\.path\.insert(0, os\.path\.join(ROOT' "$PY_RUNNER"; then
    bad "py_prologue_extracted" "프롤로그 추출 실패 — 종결 줄 sys.path.insert(0, os.path.join(ROOT ... 부재(구조 변경 시 awk 범위 갱신 필요)"
  else
    ok "py_prologue_extracted" "Python 해석 프롤로그 추출 ($(printf '%s\n' "$_PY_FRAG_SRC" | wc -l | tr -d ' ') 줄)"

    _py_emit() {  # $1=대상 트리  $2=본문
      mkdir -p "$1/02_Infrastructure/tests"
      { printf '%s\n' "$2"
        printf 'print("RESOLVED=" + ROOT.replace(chr(92), "/"))\n'; } \
        > "$1/02_Infrastructure/tests/anchor_frag.py"
    }
    _py_emit "$PY_SELF" "$_PY_FRAG_SRC"
    _py_emit "$PY_BARE" "$_PY_FRAG_SRC"

    # ── 축 2: 위반 주입 (QM_ROOT / CPD = 표지 가진 다른 트리) ───────────────
    GOT="$(run_py_anchor "$TMPW/py_self/02_Infrastructure/tests/anchor_frag.py" "$TMPW/py_alt")"
    if [ "$GOT" = "$TMPW/py_self" ]; then
      ok "py_self_first" "QM_ROOT=별개 트리여도 자기 트리 선택 ($GOT)"
    elif [ "$GOT" = "$TMPW/py_alt" ]; then
      bad "py_self_first" "QM_ROOT 트리를 검사 대상으로 선택함 — 배터리가 main 의 continuity_gate.py 를 검사(원 결함)"
    else
      bad "py_self_first" "예상 밖 해석 — got '$GOT', want '$TMPW/py_self'"
    fi

    GOT="$(run_py_anchor "$TMPW/py_self/02_Infrastructure/tests/anchor_frag.py" "" "$TMPW/py_alt")"
    if [ "$GOT" = "$TMPW/py_self" ]; then
      ok "py_self_beats_cpd" "CLAUDE_PROJECT_DIR=별개 트리여도 자기 트리 선택"
    else
      bad "py_self_beats_cpd" "CPD 트리를 선택함 — got '$GOT', want '$TMPW/py_self'"
    fi

    # ── 축 3: 자기 트리 해석이면 무경보 ─────────────────────────────────────
    if grep -q "ANCHOR OVERRIDE" "$TMP/py_stderr.txt" 2>/dev/null; then
      bad "py_quiet_when_self" "자기 트리 해석인데 override 경보 발화 — 상시 경보는 곧 무시된다"
    else
      ok "py_quiet_when_self" "자기 트리 해석 시 무경보"
    fi

    # ── 축 4: 검사기 사망 통제 (돌연변이) ───────────────────────────────────
    if [ -z "$_PY_ORDER_LINE" ]; then
      bad "py_mutant_detected" "앵커 순서가 단일 감사 가능한 줄(_ANCHOR_ORDER)로 노출돼 있지 않음 — 계약 위반(순서를 기계가 읽고 갈아끼울 수 없으면 검출력을 실증할 수 없다)"
    elif [ "$_PY_ORDER_LINE" = "$PY_ENVFIRST" ]; then
      bad "py_mutant_detected" "원본이 이미 env-first — 돌연변이가 원본과 동일해 이 축이 공허(결함 자체는 py_self_first 가 보고)"
    else
      _py_emit "$TMP/py_mut" "${_PY_FRAG_SRC//"$_PY_ORDER_LINE"/$PY_ENVFIRST}"
      GOT="$(run_py_anchor "$TMPW/py_mut/02_Infrastructure/tests/anchor_frag.py" "$TMPW/py_alt")"
      if [ "$GOT" = "$TMPW/py_alt" ]; then
        ok "py_mutant_detected" "순서를 env-first 로 되돌리면 별개 트리가 선택됨 — py_self_first 가 실제로 이 차이를 잼"
      else
        bad "py_mutant_detected" "env-first 로 되돌려도 자기 트리 선택 (got '$GOT') — py_self_first 가 무력(계측 사망)"
      fi
    fi

    # ── 축 5: 표지 없는 self → env 낙하 + 경보 ──────────────────────────────
    GOT="$(run_py_anchor "$TMPW/py_bare/02_Infrastructure/tests/anchor_frag.py" "$TMPW/py_alt")"
    if [ "$GOT" = "$TMPW/py_alt" ]; then
      ok "py_override_value" "표지 없는 self 기각 → QM_ROOT 로 낙하 ($GOT)"
    else
      bad "py_override_value" "self 기각 후 낙하 실패 — got '$GOT', want '$TMPW/py_alt'"
    fi
    if grep -q "ANCHOR OVERRIDE" "$TMP/py_stderr.txt" 2>/dev/null; then
      ok "py_override_warns" "앵커 갈림을 stderr 로 보고 (조용한 override 아님)"
    else
      bad "py_override_warns" "앵커가 자기 트리와 갈렸는데 무경보 — '어느 트리를 쟀나'가 로그에 안 남는다"
    fi
  fi
fi

# ─── 요약 ────────────────────────────────────────────────────────────────────
echo ""
echo "TOTAL: $PASS pass / $FAIL fail"
printf '{"test":"runner_anchor_selffirst","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
