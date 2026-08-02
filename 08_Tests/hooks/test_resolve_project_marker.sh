#!/usr/bin/env bash
#==============================================================================
# test_resolve_project_marker.sh — resolve_project.sh 루트 marker 게이트 위반 주입 테스트
#
# 계약: 02_Infrastructure/docs/rules/r-portability.md 금칙 ③
#       "루트 후보 판정에 dir.exists()/-d 만 쓰지 말 것 → marker 파일로 검증"
#
# 왜 이 검사기가 필요한가 (2026-08-01 실사고):
#   resolve_project.sh 의 QM_ROOT 분기가 `[ -d "$QM_ROOT" ]` 만 보고 후보를 수락했다.
#   User scope QM_ROOT 가 역슬래시 형식(`C:\Users\...`)이었는데 `-d` 는 통과 →
#   daily_refresh.sh 의 setwd("$BASE") 6지점이 R 소스문자열에서 `\U` 로 파싱돼
#   Error: '\U' used without hex digits ... 로 halt.
#   run_r 는 체인을 계속하므로 **5개 스텝만 침묵 실패**했다
#   (KTRI v3 · MSM · regime_daily_v2 · SJM · cache_freshness_audit).
#   같은 기전으로 "존재하지만 그 프로젝트가 아닌" 디렉토리(예: Windows R 이 /mnt/c/... 를
#   C:/mnt/c/... 로 해석해 남긴 빈 잔재)도 조용히 루트로 수락된다.
#
# 검사 축:
#   A  위반 주입    — marker 없는 임시 디렉토리를 QM_ROOT 로 넣고 **기각 + 다음 tier 낙하** 확인
#   B  양성 통제    — 진짜 루트는 수락되고 QVEST_ROOT_SOURCE=QM_ROOT
#   C  역슬래시     — 08-01 실사고 형식이 수락되되 **슬래시로 정규화**되어 나오는지
#   D  검사기 사망  — marker 게이트를 `-d` 로 되돌린 **돌연변이**를 만들어, A 가 실제로
#                    뒤집히는지 확인. 안 뒤집히면 A 의 "통과"는 계측 사망이지 통과가 아니다.
#   E  2벌 동기화   — ops/ 판과 hooks/ 판 **둘 다** A 를 만족하는지 (동명 2벌 드리프트 방지)
#   F  self/glob    — marker 없는 위치의 사본은 self-inference 에서 기각되고 glob 으로 낙하
#
# 단독 실행: bash 08_Tests/hooks/test_resolve_project_marker.sh
#==============================================================================
set -uo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER_REL="02_Infrastructure/hooks/qvest_hook_router.py"

# PROJ_DIR 해석 — 후보를 표지로 확인한다(이 파일이 강제하는 규율을 자기 자신에게도 적용).
#   ★앵커 1순위 = BASH_SOURCE, env 아님. 테스트는 **자기가 실린 트리**를 검사해야 한다.
#     최초 구현은 CLAUDE_PROJECT_DIR→QM_ROOT 를 먼저 봤는데, worktree 에서 QM_ROOT 가
#     main 을 가리키는 탓에 worktree 의 수리본이 아니라 **main 의 구판을 검사**했다
#     (실측: 수리 직후 7 fail — 고친 파일을 아예 안 보고 있었음).
#     "수리는 worktree 에 있는데 초록은 main 에서 났다"가 이 리포지토리의 기존 실패 부류다.
_pick_proj_dir() {
  local c
  for c in "$_SELF_DIR/../.." "${CLAUDE_PROJECT_DIR:-}" "${QM_ROOT:-}" "$PWD"; do
    if [[ -n "$c" && -f "${c//\\//}/$MARKER_REL" ]]; then (cd "${c//\\//}" && pwd); return 0; fi
  done
  return 1
}
if ! PROJ_DIR="$(_pick_proj_dir)"; then
  echo "❌ PROJECT_ROOT 해석 실패 — 표지 '$MARKER_REL' 를 가진 후보 없음" >&2
  echo '{"test":"resolve_project_marker","pass":0,"fail":1,"total":1}'
  exit 1
fi

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS: %s%s\n' "$1" "${2:+ — $2}"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL: %s — %s\n' "$1" "$2"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# marker 없는 "존재하지만 그 프로젝트가 아닌" 디렉토리 = 금칙 ③ 의 함정 그 자체.
BOGUS="$TMP/bogus_root"
mkdir -p "$BOGUS/02_Infrastructure"   # 02_Infrastructure 까지 만든다 —
                                      # 구 branch2 는 이것만 보고 수락했으므로 검사가 헐거우면 통과한다.

# resolver 를 격리된 자식 프로세스에서 source 하고 "PROJECT|QVEST_ROOT_SOURCE" 를 받는다.
#   ★자식 프로세스인 이유: 이 셸의 QM_ROOT/PROJECT 오염 없이 시나리오별 env 를 세우기 위함.
#   ★stderr 는 버리지 않고 따로 잡는다 — 경보 발화 자체가 검사 대상이다(F 축 아님, B/A 축 보조).
run_resolver() {  # $1=resolver 경로  $2=QM_ROOT(""→unset)  $3=CLAUDE_PROJECT_DIR(""→unset)
  local resolver="$1" qm="${2:-}" cpd="${3:-}"
  # 두 변수를 항상 명시적으로 지운 뒤 필요한 것만 세운다 — 호출 셸의 상속값이
  # 시나리오를 오염시키면 그 결과는 무엇도 재지 못한다.
  local -a pre=(env -u QM_ROOT -u CLAUDE_PROJECT_DIR)
  [ -n "$qm" ]  && pre+=("QM_ROOT=$qm")
  [ -n "$cpd" ] && pre+=("CLAUDE_PROJECT_DIR=$cpd")
  "${pre[@]}" bash -c 'source "$1" >/dev/null 2>"$2"; printf "%s|%s" "${PROJECT:-}" "${QVEST_ROOT_SOURCE:-}"' _ "$resolver" "$TMP/stderr.txt"
}

OPS_RESOLVER="$PROJ_DIR/02_Infrastructure/ops/resolve_project.sh"
HOOKS_RESOLVER="$PROJ_DIR/02_Infrastructure/hooks/resolve_project.sh"

echo "=== resolve_project marker gate ==="
echo "  proj: $PROJ_DIR"
echo "  bogus QM_ROOT: $BOGUS (marker 부재, 02_Infrastructure 는 존재)"
echo ""

# ─── A + E: 위반 주입 (두 벌 모두) ───────────────────────────────────────────
for _pair in "ops:$OPS_RESOLVER" "hooks:$HOOKS_RESOLVER"; do
  _tag="${_pair%%:*}"; _res="${_pair#*:}"
  if [ ! -f "$_res" ]; then bad "injection_${_tag}" "resolver 부재: $_res"; continue; fi

  OUT="$(run_resolver "$_res" "$BOGUS")"
  GOT_PROJECT="${OUT%%|*}"; GOT_SOURCE="${OUT##*|}"

  if [ "$GOT_PROJECT" = "$BOGUS" ]; then
    bad "injection_${_tag}" "marker 없는 QM_ROOT 를 루트로 수락함 (금칙 ③ 위반 — 게이트 무력)"
  elif [ -z "$GOT_PROJECT" ]; then
    bad "injection_${_tag}" "기각은 했으나 다음 tier 로 낙하하지 못함 (PROJECT 빈 값)"
  elif [ ! -f "$GOT_PROJECT/$MARKER_REL" ]; then
    bad "injection_${_tag}" "낙하 결과가 marker 없는 경로: $GOT_PROJECT"
  else
    ok "injection_${_tag}" "bogus 기각 → tier '${GOT_SOURCE}' 로 낙하 ($GOT_PROJECT)"
  fi

  if grep -q "WARN.*marker" "$TMP/stderr.txt" 2>/dev/null; then
    ok "injection_${_tag}_warns" "기각을 stderr 로 보고 (조용한 fall-through 아님)"
  else
    bad "injection_${_tag}_warns" "marker 기각이 무경보 — 침묵 낙하는 이 계통의 재발 기전"
  fi
done

# ─── B: 양성 통제 (진짜 루트는 수락) ─────────────────────────────────────────
OUT="$(run_resolver "$OPS_RESOLVER" "$PROJ_DIR")"
if [ "${OUT%%|*}" = "$PROJ_DIR" ] && [ "${OUT##*|}" = "QM_ROOT" ]; then
  ok "positive_control" "marker 보유 QM_ROOT 수락 (source=QM_ROOT)"
else
  bad "positive_control" "진짜 루트를 수락하지 못함 — got '$OUT', want '$PROJ_DIR|QM_ROOT'"
fi

# ─── C: 역슬래시 형식 (2026-08-01 실사고 형식) ───────────────────────────────
# `-d` 는 역슬래시도 통과시키므로 구판은 그대로 R 에 흘려보냈다. 수락하되 정규화돼야 한다.
#   실사고 형식은 `C:\Users\...` (Windows native) — cygpath 가 있으면 그 형식을 쓴다.
#   판정은 "특정 문자열과 일치"가 아니라 **역슬래시 부재 + marker 도달**로 한다
#   (C:/... 와 /c/... 는 둘 다 유효한 같은 루트라, 문자열 동일성은 잘못된 잣대다).
BS_ROOT="$(cygpath -w "$PROJ_DIR" 2>/dev/null || printf '%s' "${PROJ_DIR//\//\\}")"
OUT="$(run_resolver "$OPS_RESOLVER" "$BS_ROOT")"
GOT_PROJECT="${OUT%%|*}"
if [[ "$GOT_PROJECT" == *'\'* ]]; then
  bad "backslash_normalized" "역슬래시가 그대로 반환됨 ('$GOT_PROJECT') — R setwd() 주입 시 '\\U' 파싱 사망 재발"
elif [ -n "$GOT_PROJECT" ] && [ -f "$GOT_PROJECT/$MARKER_REL" ]; then
  ok "backslash_normalized" "역슬래시 QM_ROOT 수락 + 슬래시 정규화 ($BS_ROOT → $GOT_PROJECT)"
else
  bad "backslash_normalized" "역슬래시 QM_ROOT 처리 이상 — got '$GOT_PROJECT' (marker 미도달)"
fi

# ─── D: 검사기 사망 통제 (돌연변이) ──────────────────────────────────────────
# marker 게이트를 구판 `-d` 로 되돌린 사본을 만들어, A 의 판정이 실제로 뒤집히는지 본다.
# 뒤집히지 않으면 A 는 무엇도 재고 있지 않다("오탐 제거"와 "검사 사망"은 겉보기가 같다).
#   ★sed 금지 — 패턴에 `|`(`|| return 1`)와 `/`(marker 경로)가 둘 다 들어 구분자가 충돌한다
#     (실측: `sed: unknown option to 's'`). bash 리터럴 치환(패턴 인용)으로 대체.
MUT="$TMP/mutant_resolve_project.sh"
_NEEDLE='[ -f "$c/$QVEST_ROOT_MARKER" ] || return 1'
_REPL='[ -d "$c" ] || return 1'
_SRC="$(cat "$OPS_RESOLVER")"
if [[ "$_SRC" != *"$_NEEDLE"* ]]; then
  bad "mutant_built" "돌연변이 생성 실패 — marker 검사 줄을 찾지 못함(리팩터 시 _NEEDLE 갱신 필요)"
else
  printf '%s\n' "${_SRC//"$_NEEDLE"/$_REPL}" > "$MUT"
  OUT="$(run_resolver "$MUT" "$BOGUS")"
  if [ "${OUT%%|*}" = "$BOGUS" ]; then
    ok "mutant_detected" "게이트 제거 시 bogus 가 수락됨 — A 축이 실제로 이 차이를 재고 있음"
  else
    bad "mutant_detected" "게이트를 제거해도 bogus 가 기각됨 (got '${OUT%%|*}') — A 축이 무력(계측 사망)"
  fi
fi

# ─── F: self-inference 기각 → glob 낙하 ──────────────────────────────────────
# marker 없는 트리에 놓인 사본: branch1 skip(QM_ROOT unset) → branch2 는 자기 위치를
# 기각해야 하고 → branch3 glob 이 진짜 루트를 집어야 한다.
FAKE_TREE="$TMP/fake/02_Infrastructure/ops"
mkdir -p "$FAKE_TREE"
cp "$OPS_RESOLVER" "$FAKE_TREE/resolve_project.sh"
OUT="$(run_resolver "$FAKE_TREE/resolve_project.sh" "")"
GOT_PROJECT="${OUT%%|*}"; GOT_SOURCE="${OUT##*|}"
if [ "$GOT_PROJECT" = "$TMP/fake" ] || [ "$GOT_SOURCE" = "self" ]; then
  bad "self_inference_rejected" "marker 없는 자기 위치를 루트로 수락함 (got '$GOT_PROJECT', source=$GOT_SOURCE)"
elif [ -n "$GOT_PROJECT" ] && [ -f "$GOT_PROJECT/$MARKER_REL" ]; then
  ok "self_inference_rejected" "self 기각 → tier '${GOT_SOURCE}' 로 낙하 ($GOT_PROJECT)"
else
  bad "self_inference_rejected" "self 기각 후 유효 루트로 낙하 실패 (got '$GOT_PROJECT')"
fi

# ─── G: 우선순위 분기 (2026-08-01 도훈 결정) ─────────────────────────────────
# hooks 판만 CLAUDE_PROJECT_DIR 이 tier 0, ops 판은 QM_ROOT-first 유지.
# **양방향으로** 못박는다 — 한쪽만 검사하면 "둘을 통합" 리팩터가 조용히 통과한다.
#   ALT = marker 를 갖춘 두 번째 루트(합성). main 존재에 의존하지 않기 위해 임시로 만든다.
ALT="$TMP/alt_root"
mkdir -p "$ALT/02_Infrastructure/hooks"
: > "$ALT/02_Infrastructure/hooks/qvest_hook_router.py"

OUT="$(run_resolver "$HOOKS_RESOLVER" "$PROJ_DIR" "$ALT")"
if [ "${OUT%%|*}" = "$ALT" ] && [ "${OUT##*|}" = "CLAUDE_PROJECT_DIR" ]; then
  ok "precedence_hooks_cpd_first" "hooks 판: CPD 가 QM_ROOT 를 이김 (settings.json 라우터와 동일 트리)"
else
  bad "precedence_hooks_cpd_first" "hooks 판이 CPD 를 tier 0 로 쓰지 않음 — got '$OUT', want '$ALT|CLAUDE_PROJECT_DIR'"
fi

OUT="$(run_resolver "$OPS_RESOLVER" "$PROJ_DIR" "$ALT")"
if [ "${OUT%%|*}" = "$PROJ_DIR" ] && [ "${OUT##*|}" = "QM_ROOT" ]; then
  ok "precedence_ops_qmroot_first" "ops 판: QM_ROOT 유지 (스케줄러·데몬 28 소비자 의미 불변)"
else
  bad "precedence_ops_qmroot_first" "ops 판 우선순위가 바뀜 — got '$OUT', want '$PROJ_DIR|QM_ROOT'. 스케줄러/데몬 루트 해석 영향"
fi

# ─── H: CPD 도 marker 로 검증되는가 (hooks 판) ───────────────────────────────
# tier 0 를 추가했으므로 tier 0 자체도 게이트를 지나야 한다. 오염된 CPD 를 상속받아도
# (예: 별개 Qvest 시스템, mrs_daily_briefing.sh:27-28 이 기록한 실사례) QM_ROOT 로 낙하해야 한다.
OUT="$(run_resolver "$HOOKS_RESOLVER" "$PROJ_DIR" "$BOGUS")"
if [ "${OUT%%|*}" = "$BOGUS" ]; then
  bad "cpd_marker_gated" "marker 없는 CPD 를 tier 0 에서 수락함 — 게이트가 QM_ROOT 분기에만 걸림"
elif [ "${OUT%%|*}" = "$PROJ_DIR" ] && [ "${OUT##*|}" = "QM_ROOT" ]; then
  ok "cpd_marker_gated" "marker 없는 CPD 기각 → QM_ROOT 로 낙하"
else
  bad "cpd_marker_gated" "CPD 기각 후 낙하 이상 — got '$OUT', want '$PROJ_DIR|QM_ROOT'"
fi

# ─── I/J/K: 테스트 러너 앵커 우선순위 (2026-08-02) ───────────────────────────
# 위 A~H 는 **공유 resolver 2벌**(훅·스케줄러의 데이터 루트)을 다룬다. 러너 자신의 앵커는
# 별개 계약이고, 그게 비어 있어서 다음 결함이 8개월 살아 있었다:
#
#   run_all_hooks.sh 의 _pick_proj_dir 가 CLAUDE_PROJECT_DIR → QM_ROOT → self 순이었다.
#   Bash 툴 환경엔 CPD 가 없고(훅 안에서만 설정) QM_ROOT 는 **main** 을 가리키므로,
#   worktree 에서 배터리를 돌리면 SUITES 는 worktree 사본에서 오는데 PROJ_DIR 은 main —
#   **전 suite 가 main 코드에 대해 실행**됐다. 실측 헤더:
#     `Project: /c/Users/99922/OneDrive/Quant_Module_Moltbot` (cwd 는 worktree)
#   파급 (둘 다 오독을 낳는다):
#     ① worktree 초록이 worktree 를 검증하지 않는다 — "고쳤는데 main 엔 없다" 계통의
#        정반대 짝: **안 고친 것을 고쳤다고 읽게 만든다**.
#     ② worktree 신설 suite 는 main 에 파일이 없어 UNREPORTED=1 fail → "테스트 실패"로
#        보이지만 실제로는 앵커 오설정 (실측 FINAL 569 pass / 1 fail).
#
# ★표지(marker) 검증은 이 갈림을 **판별하지 못한다** — main 도 worktree 도 표지를 갖는다.
#   A~H 가 전부 통과해도 이 결함은 그대로다. 판별하는 것은 오직 후보 **순서**뿐이라,
#   순서 자체를 계약으로 못박는다.
# ★공유 resolver 2벌은 무변경 — 소비자 계층이 다르다(축 G 가 그 순서를 양방향 고정).
#   러너만 self-first 인 이유: 테스트는 *자기가 실린 트리*를 재야 한다.
#
# 검사 대상은 사본이 아니라 **원본 .sh 에서 추출한 해석 프롤로그**다. 러너 전체를 돌리면
# 모든 suite 를 2회 실행하므로(운영상 수 분), 프롤로그(_MARKER= ~ TEST_DIR= 직전)만
# 떼어 자식 셸에서 평가한다 — 실행되는 바이트 그대로이되 비용 0.
RUNNER="$PROJ_DIR/08_Tests/hooks/run_all_hooks.sh"
RUNNER_FRAG="$TMP/runner_anchor_frag.sh"

# 표지만 갖춘 **두 번째 러너 트리** = main 의 대역. QM_ROOT 가 여기를 가리키는 상황이
# 실사고 배치 그대로다(worktree 에서 실행 + QM_ROOT=main).
ALT_RUNNER="$TMP/alt_runner_tree"
mkdir -p "$ALT_RUNNER/08_Tests/hooks"
: > "$ALT_RUNNER/08_Tests/hooks/run_all_hooks.sh"

# 프롤로그를 자식 셸에서 평가하고 PROJ_DIR 을 회수. stderr 는 따로 잡는다(경보가 검사 대상).
run_runner_anchor() {  # $1=fragment  $2=_SELF_DIR  $3=QM_ROOT(""→unset)  $4=CPD(""→unset)
  local frag="$1" self="$2" qm="${3:-}" cpd="${4:-}"
  local -a pre=(env -u QM_ROOT -u CLAUDE_PROJECT_DIR)
  [ -n "$qm" ]  && pre+=("QM_ROOT=$qm")
  [ -n "$cpd" ] && pre+=("CLAUDE_PROJECT_DIR=$cpd")
  "${pre[@]}" bash -c '_SELF_DIR="$2"; source "$1"; printf "%s" "${PROJ_DIR:-}"' \
      _ "$frag" "$self" 2>"$TMP/runner_stderr.txt"
}

# ★추출 가드는 **순서에 무관한 구조**만 본다 (2026-08-02 자기수정).
#   초판은 가드의 needle 을 *수리된* 후보 순서 줄로 잡았다. 그 결과 순서를 구판으로
#   되돌리면 I/J/K 가 아예 실행되지 않고 "프롤로그 추출 실패 — 리팩터 시 needle 갱신 필요"
#   가 떴다(실측). 결함 상태를 **정비 과제로 오진**시키는 메시지라, 그대로 두면 다음 사람이
#   needle 을 갱신하는 것으로 "고치고" env-first 를 조용히 재수용한다.
#   → 가드는 `for c in` 존재만 확인하고, 순서 판정은 **행동 축(I)** 이 direct 로 한다.
_ANCHOR_ENVFIRST='  for c in "${CLAUDE_PROJECT_DIR:-}" "${QM_ROOT:-}" "$_SELF_DIR/../.." "$PWD"; do'

if [ ! -f "$RUNNER" ]; then
  bad "runner_anchor_extracted" "러너 부재: $RUNNER"
else
  awk '/^_MARKER=/{f=1} /^TEST_DIR=/{f=0} f{print}' "$RUNNER" > "$RUNNER_FRAG"
  # 추출 실패를 조용한 통과로 만들지 않는다 — 빈 조각을 source 하면 PROJ_DIR 이 빈 값이
  # 되고, 아래 축들이 전부 "기대와 다름"이 아니라 **무엇도 재지 않은 채** 굴러간다.
  _FRAG_SRC="$(cat "$RUNNER_FRAG")"
  _ANCHOR_LINE="$(printf '%s\n' "$_FRAG_SRC" | grep -m1 'for c in ')"
  if [ ! -s "$RUNNER_FRAG" ] || [[ "$_FRAG_SRC" != *"_pick_proj_dir"* ]] || [ -z "$_ANCHOR_LINE" ]; then
    bad "runner_anchor_extracted" "프롤로그 추출 실패 — _pick_proj_dir/후보 루프 부재(러너 구조 변경 시 awk 범위 갱신 필요)"
  else
    ok "runner_anchor_extracted" "러너 해석 프롤로그 추출 ($(wc -l < "$RUNNER_FRAG" | tr -d ' ') 줄)"

    # ── I: 위반 주입 — QM_ROOT 가 **표지를 가진 다른 트리**를 가리켜도 자기 트리를 골라야 ──
    #    (CPD 는 미설정 = Bash 툴 실환경 그대로. 실사고 배치의 정확한 재현.)
    GOT="$(run_runner_anchor "$RUNNER_FRAG" "$PROJ_DIR/08_Tests/hooks" "$ALT_RUNNER")"
    if [ "$GOT" = "$PROJ_DIR" ]; then
      ok "runner_anchor_self_first" "QM_ROOT=별개 트리여도 자기 트리 선택 ($GOT)"
    elif [ "$GOT" = "$ALT_RUNNER" ]; then
      bad "runner_anchor_self_first" "QM_ROOT 트리를 검사 대상으로 선택함 — 러너가 자기가 실린 트리를 안 잼(worktree 초록이 main 을 재는 원 결함)"
    else
      bad "runner_anchor_self_first" "예상 밖 해석 — got '$GOT', want '$PROJ_DIR'"
    fi

    # 자기 트리를 골랐으면 override 경보는 **없어야** 한다(정상 실행에 잡음 금지).
    if grep -q "ANCHOR OVERRIDE" "$TMP/runner_stderr.txt" 2>/dev/null; then
      bad "runner_anchor_quiet_when_self" "자기 트리 해석인데 override 경보 발화 — 상시 경보는 곧 무시된다"
    else
      ok "runner_anchor_quiet_when_self" "자기 트리 해석 시 무경보"
    fi

    # ── J: 검사기 사망 통제 (돌연변이) ────────────────────────────────────────
    # 후보 순서를 **구판(env-first)** 으로 되돌린 사본에서 I 가 실제로 뒤집히는지 본다.
    # 안 뒤집히면 I 는 순서를 재고 있지 않다("오탐 제거"와 "검사 사망"은 겉보기가 같다).
    #   ★돌연변이는 **현재 후보 줄이 무엇이든** 그것을 env-first 로 갈아끼워 만든다
    #     (수리본 문자열에 의존하지 않음 — 위 가드 주석의 오진 기전과 같은 함정).
    if [ "$_ANCHOR_LINE" = "$_ANCHOR_ENVFIRST" ]; then
      bad "runner_anchor_mutant_detected" "원본이 이미 env-first — 돌연변이가 원본과 동일해 J 축이 공허(결함 자체는 I 축이 보고)"
    else
      MUT_RUNNER="$TMP/mutant_runner_frag.sh"
      printf '%s\n' "${_FRAG_SRC//"$_ANCHOR_LINE"/$_ANCHOR_ENVFIRST}" > "$MUT_RUNNER"
      GOT="$(run_runner_anchor "$MUT_RUNNER" "$PROJ_DIR/08_Tests/hooks" "$ALT_RUNNER")"
      if [ "$GOT" = "$ALT_RUNNER" ]; then
        ok "runner_anchor_mutant_detected" "순서를 env-first 로 되돌리면 별개 트리가 선택됨 — I 축이 실제로 이 차이를 잼"
      else
        bad "runner_anchor_mutant_detected" "env-first 로 되돌려도 자기 트리 선택 (got '$GOT') — I 축이 무력(계측 사망)"
      fi
    fi

    # ── K: 의도적 override 는 **보이게** ───────────────────────────────────────
    # 표지 없는 위치의 러너 사본 → self 기각 → env 로 낙하. 낙하 자체는 정당하지만
    # 침묵하면 안 된다(침묵 낙하 = 이 계통의 재발 기전).
    BARE_SELF="$TMP/bare_self/bin"
    mkdir -p "$BARE_SELF"
    GOT="$(run_runner_anchor "$RUNNER_FRAG" "$BARE_SELF" "$ALT_RUNNER")"
    if [ "$GOT" = "$ALT_RUNNER" ]; then
      ok "runner_anchor_override_value" "표지 없는 self 기각 → QM_ROOT 로 낙하 ($GOT)"
    else
      bad "runner_anchor_override_value" "self 기각 후 낙하 실패 — got '$GOT', want '$ALT_RUNNER'"
    fi
    if grep -q "ANCHOR OVERRIDE" "$TMP/runner_stderr.txt" 2>/dev/null; then
      ok "runner_anchor_override_warns" "앵커 갈림을 stderr 로 보고 (조용한 override 아님)"
    else
      bad "runner_anchor_override_warns" "앵커가 자기 트리와 갈렸는데 무경보 — '어느 트리를 쟀나'가 로그에 안 남는다"
    fi
  fi
fi

# ─── 요약 ────────────────────────────────────────────────────────────────────
echo ""
echo "TOTAL: $PASS pass / $FAIL fail"
printf '{"test":"resolve_project_marker","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
