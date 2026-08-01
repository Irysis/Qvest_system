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

# ─── 요약 ────────────────────────────────────────────────────────────────────
echo ""
echo "TOTAL: $PASS pass / $FAIL fail"
printf '{"test":"resolve_project_marker","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
