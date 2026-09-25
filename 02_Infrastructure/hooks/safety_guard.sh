#!/bin/bash

#==============================================================================
# Safety Guard — PreToolUse Hook (3중 방어선 1선)
# Write/Edit/Bash 실행 전에 금지 패턴 차단.
#
# (v8.2.1 2026-07-03 감사 HOOK-P2-1/MC-07, 도훈 confirm) 게이트급 fail-closed 전환:
#   구 Phase C3 trap(내부 오류 시 무조건 '{}' allow)을 보호 대상 판정 후 결정으로 교체.
#   ERR/파싱 판별불능 시 payload에 보호 패턴(05_Production / 01_Literature
#   비-Korea_Research / normalizePath)이 잡히면 block, 아니면 allow.
#   정상 경로 로직(Rule 1/2)은 불변.
#
# (P0-M1 2026-09-24 · 도훈 "기억 무결성 전부 승인") Rule 3 — 무인 레인 기억 쓰기 차단:
#   QVEST_UNATTENDED_LANE=1(무인 LLM 단일 진입 rf_llm_env.sh::rf_llm_agent_run 이 싣는 표식)일 때만
#   Claude 기억 디렉터리(~/.claude/projects/*/memory · MEMORY.md) 쓰기를 막고 06_Registry/memory_inbox/ 로 안내한다.
#   왜: 무인 레인 27 세션이 기억 디렉터리에 카드 19장을 쓰고 MEMORY.md 를 통째로 재작성했다(D7-02).
#   자동 기억 스위치(CLAUDE_CODE_DISABLE_AUTO_MEMORY=1)가 1층, 이 규칙이 2층이다 — 스위치가 풀려도 쓰기는 막힌다.
#   ★표식이 없으면(대화형 세션·Q) 이 규칙은 **한 줄도 실행되지 않는다** — 평시 비용·소음 0.
#   Bash 판정은 정적 최선이다(우회 3종 — 글롭·문자열 결합·find — 는 검사가 양성 대조로 잡는다).
#   ★한계(명시): 이 훅의 등록 matcher 는 Write|Edit · Bash 뿐이다(settings.json) — MultiEdit·NotebookEdit·
#     PowerShell 도구 경로는 여기 오지 않는다. 등록 확장은 settings.json 변경(별도 결정)이다.
#   검사: 08_Tests/hooks/test_safety_guard_memory.sh
#==============================================================================

# ── Rule 3 도우미 (무인 레인 전용 · 순수 bash · 서브셸 0) ─────────────────────
# 판정 규칙 코드(차단 사유에 싣는다 — 고정 집합이라 JSON 이스케이프 불요):
#   path   Write/Edit 경로가 기억 디렉터리
#   tok    한 토큰에 .claude + memor           dotmem  명령에 .claude + 단어 memory
#   mdfile 명령에 memory.md                    projmem projects/ + /memory
#   homemem 홈 참조(~ · $HOME · %USERPROFILE%) + /memory
#   glob   글롭 토큰(명령 안 cd/pushd 를 따라간 유효 cwd 기준)이 기억 디렉터리(또는 그 조상)와 일치
#   find   find 시작 경로가 기억 디렉터리의 조상이거나 .claude 를 지난다
#   cd     cd/pushd 대상이 .claude 를 지난다
_QMEM_WHY=""

_qmem_home_forms() {  # → _QH1(/c/users/x) · _QH2(c:/users/x) · _QSLUG(프로젝트 슬러그)
  local h="${HOME:-${USERPROFILE:-}}" p
  h="${h//\\//}"; h="${h,,}"
  case "$h" in
    /[a-z]/*) _QH1="$h"; _QH2="${h:1:1}:${h:2}" ;;
    [a-z]:/*) _QH2="$h"; _QH1="/${h:0:1}${h:2}" ;;
    *)        _QH1="$h"; _QH2="$h" ;;
  esac
  p="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-${PWD:-}}}"
  p="${p//\\//}"
  case "$p" in /[a-zA-Z]/*) p="${p:1:1}:${p:2}" ;; esac
  p="${p//[^A-Za-z0-9]/-}"
  _QSLUG="${p,,}"
}

_qmem_resolve() {  # $1 경로(정규화된 소문자) [$2 기준 디렉터리 — 기본 PWD] → _QR : . · .. 해소
  local s="$1" base="${2:-}" seg out=() _qsegs=()
  case "$s" in
    /*|[a-z]:/*) : ;;
    *) [ -n "$base" ] || { base="${PWD:-/}"; base="${base//\\//}"; base="${base,,}"; }
       s="$base/$s" ;;
  esac
  local IFS='/'
  read -r -a _qsegs <<< "$s"
  for seg in "${_qsegs[@]}"; do
    case "$seg" in
      ""|.) : ;;
      ..) if [ "${#out[@]}" -gt 0 ]; then unset 'out[${#out[@]}-1]'; fi ;;
      *) out+=("$seg") ;;
    esac
  done
  _QR="/${out[*]}"
  case "$s" in [a-z]:/*) _QR="${_QR#/}" ;; esac
}

_qmem_home_sub() {  # $1 토큰 → _QT : 홈 참조를 _QH1 로 치환
  local t="$1"
  case "$t" in "~"|"~/"*) t="${_QH1}${t:1}" ;; esac
  t="${t//\$\{home\}/$_QH1}"; t="${t//\$home/$_QH1}"
  t="${t//\$\{userprofile\}/$_QH1}"; t="${t//\$userprofile/$_QH1}"
  t="${t//%userprofile%/$_QH1}"; t="${t//\$env:userprofile/$_QH1}"
  _QT="$t"
}

_qmem_path_is_mem() {  # $1 = 정규화 경로 — 기억 디렉터리(또는 그 안)인가
  local r="$1" cfg
  [[ "$r" =~ /(\.claude|\.claud~[0-9])/+projects/+[^/]+/+memory(/|$) ]] && return 0
  cfg="${CLAUDE_CONFIG_DIR:-}"
  if [ -n "$cfg" ]; then
    cfg="${cfg//\\//}"; cfg="${cfg,,}"
    [[ "$r" == "$cfg"/projects/*/memory || "$r" == "$cfg"/projects/*/memory/* ]] && return 0
  fi
  return 1
}

_qmem_cands() {  # 기억 디렉터리와 그 조상 — 글롭·find 판정의 후보 경로
  local H
  _QCANDS=()
  for H in "$_QH1" "$_QH2"; do
    _QCANDS+=("$H/.claude" "$H/.claude/" "$H/.claude/projects" "$H/.claude/projects/"
              "$H/.claude/projects/$_QSLUG" "$H/.claude/projects/$_QSLUG/"
              "$H/.claude/projects/$_QSLUG/memory" "$H/.claude/projects/$_QSLUG/memory/"
              "$H/.claude/projects/$_QSLUG/memory/memory.md" "$H/.claude/projects/$_QSLUG/memory/probe_card.md")
  done
}

_qmem_glob_hits() {  # $1 = 해소된 글롭 패턴 — 패턴 자체 또는 그 디렉터리부가 후보와 일치하면 0
  local r="$1" rd cand
  rd="${r%/*}"
  for cand in "${_QCANDS[@]}"; do
    # shellcheck disable=SC2053 — 우변은 의도적으로 따옴표 없는 패턴이다
    if [[ "$cand" == $r ]]; then return 0; fi
    if [ -n "$rd" ] && [ "$rd" != "$r" ] && [[ "$cand" == $rd ]]; then return 0; fi
  done
  return 1
}

_qmem_cmd_hit() {  # $1 = Bash 명령 원문 → 0(차단) + _QMEM_WHY
  local raw="$1" v c tok t r cand k n j sp ecwd
  local -a toks
  _qmem_home_forms; _qmem_cands
  # 두 정규화: ① 백슬래시→슬래시(윈도 경로) ② 백슬래시 제거(이스케이프 결합). 공통: 따옴표 제거 · 소문자.
  for v in 1 2; do
    c="$raw"
    if [ "$v" = 1 ]; then c="${c//\\//}"; else c="${c//\\/}"; fi
    c="${c//\"/}"; c="${c//\'/}"; c="${c//\`/ }"; c="${c,,}"
    if [[ "$c" == *memory.md* ]]; then _QMEM_WHY="mdfile"; return 0; fi
    if [[ "$c" == *.claude* && "$c" =~ (^|[^a-z0-9_])memory([^a-z0-9_]|$) ]]; then _QMEM_WHY="dotmem"; return 0; fi
    if [[ "$c" == *projects/* && ( "$c" == */memory* || "$c" == *memory/* ) ]]; then _QMEM_WHY="projmem"; return 0; fi
    if [[ ( "$c" == *"~/"* || "$c" == *'$home'* || "$c" == *'${home}'* || "$c" == *userprofile* ) \
          && ( "$c" == */memory* || "$c" == *memory/* ) ]]; then _QMEM_WHY="homemem"; return 0; fi
    # 토큰 단위 — 공백·셸 연산자·= · , 로 가른다
    t="$c"
    for k in ';' '|' '&' '(' ')' '<' '>' '=' ',' '{' '}'; do t="${t//"$k"/ }"; done
    read -r -a toks <<< "$t"
    n="${#toks[@]}"
    # 유효 cwd — 명령 안의 cd/pushd 를 따라간다(`cd ~ && cp x .c*/p*/*/m*/` 처럼 상대 글롭으로 들어가는 우회)
    # Git Bash 는 /tmp 같은 가상 마운트를 PWD 에 싣는다 — 실경로(pwd -W = C:/…)로 받아야 조상 판정이 맞다
    ecwd="$(pwd -W 2>/dev/null || pwd 2>/dev/null || printf '/')"; ecwd="${ecwd//\\//}"; ecwd="${ecwd,,}"
    for ((k = 0; k < n; k++)); do
      tok="${toks[$k]}"
      if [[ "$tok" == *.claude* && "$tok" == *memor* ]]; then _QMEM_WHY="tok"; return 0; fi
      if [[ "$tok" == cd || "$tok" == pushd ]]; then
        sp="${toks[$((k + 1))]:-~}"
        case "$sp" in -*) sp="~" ;; esac
        if [[ "$sp" == *.claude* ]]; then _QMEM_WHY="cd"; return 0; fi
        _qmem_home_sub "$sp"; _qmem_resolve "$_QT" "$ecwd"; ecwd="$_QR"
      fi
      # 글롭 토큰 — 유효 cwd 기준으로 해소해 기억 디렉터리(또는 그 조상)와 맞대 본다
      if [[ "$tok" == *[*?[]* ]]; then
        _qmem_home_sub "$tok"; _qmem_resolve "$_QT" "$ecwd"
        if _qmem_glob_hits "$_QR"; then _QMEM_WHY="glob"; return 0; fi
      fi
      # find 시작 경로 — find 다음 토큰부터 첫 옵션(-x · ! · \()까지
      if [[ "$tok" == find || "$tok" == */find || "$tok" == find.exe || "$tok" == */find.exe ]]; then
        j=$((k + 1))
        while [ "$j" -lt "$n" ]; do
          sp="${toks[$j]}"
          case "$sp" in -*|'!'|'\('|'(') break ;; esac
          if [[ "$sp" == *.claude* ]]; then _QMEM_WHY="find"; return 0; fi
          _qmem_home_sub "$sp"; _qmem_resolve "$_QT" "$ecwd"; r="${_QR%/}"
          for cand in "${_QCANDS[@]}"; do
            if [[ "$r" == "" || "$r" == "/" || "$r" =~ ^[a-z]:$ || "$cand" == "$r"/* || "$cand" == "$r" ]]; then
              _QMEM_WHY="find"; return 0
            fi
          done
          j=$((j + 1))
        done
      fi
    done
  done
  return 1
}

_qmem_file_hit() {  # $1 = Write/Edit file_path
  local p="$1"
  [ -n "$p" ] || return 1
  p="${p//\\//}"; p="${p,,}"
  _qmem_resolve "$p"
  if _qmem_path_is_mem "$_QR" || _qmem_path_is_mem "$p"; then _QMEM_WHY="path"; return 0; fi
  return 1
}

_qmem_block() {
  printf '{"decision":"block","reason":"safety_guard[P0-M1 %s]: 무인 레인(QVEST_UNATTENDED_LANE=1)은 Claude 기억 디렉터리(~/.claude/projects/*/memory · MEMORY.md)를 쓸 수 없습니다. 남길 교훈은 06_Registry/memory_inbox/<YYYYMMDD>_<레인>_<주제>.md 로 쓰세요(형식 = 06_Registry/memory_inbox/README.md · 주간 /cleaner 검토 뒤 세션이 기억으로 옮깁니다)."}\n' "${_QMEM_WHY:-unknown}"
  if declare -F qvest_emit_event >/dev/null 2>&1; then
    qvest_emit_event "hook_block" "safety_guard.sh" "block" "" "unattended_lane" "0" "${FILE_PATH:-}" "p0m1_memory_${_QMEM_WHY:-unknown}" || true
  fi
  exit 0
}

_gate_fail_closed() {
  local hay="${FILE_PATH:-}${COMMAND:-}"
  [ -n "$hay" ] || hay="${INPUT:-}"
  if printf '%s' "$hay" | grep -qE '05_Production|normalizePath' \
     || { printf '%s' "$hay" | grep -q '01_Literature' \
          && ! printf '%s' "$hay" | grep -q 'Korea_Research'; }; then
    echo '{"decision":"block","reason":"safety_guard: hook 내부 오류/판별불능 — 보호 대상(05_Production, 01_Literature, normalizePath) 패턴 감지, 검증 불가 시 차단 (fail-closed)"}'
  elif [ "${QVEST_UNATTENDED_LANE:-}" = "1" ] \
       && printf '%s' "$hay" | grep -qiE '\.claude|memory\.md|projects[\\/]' \
       && printf '%s' "$hay" | grep -qiE 'memor'; then
    # (P0-M1) 무인 레인 안에서 판별 불능 + 기억 경로 흔적 → 막는다(평시는 이 가지에 오지 않는다)
    echo '{"decision":"block","reason":"safety_guard[P0-M1 fail_closed]: hook 내부 오류/판별불능 — 무인 레인에서 기억 경로 패턴 감지, 검증 불가 시 차단. 교훈은 06_Registry/memory_inbox/ 로."}'
  else
    echo '{}'
  fi
  exit 0
}
trap '_gate_fail_closed' ERR

INPUT=$(cat)
# (v8.2.1 2026-07-04 감사 A7d) source 구간 fail-open 봉인: _shared_parse.sh 내부
# fail-open trap('{}' allow) 설치를 옵트아웃(QVEST_PARSE_TRAP=caller) — 위에서
# 선장전한 _gate_fail_closed trap이 source 실행 구간(파싱 python 호출 등) 오류까지
# fail-closed 커버. source 후 unset (자식/후속에 누출 방지).
QVEST_PARSE_TRAP=caller
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_shared_parse.sh"
unset QVEST_PARSE_TRAP
# 방어적 재장전 (옵트아웃으로 내부 trap 미설치이나, 향후 변경 대비 불변식 유지)
trap '_gate_fail_closed' ERR

# stdin 파싱 판별불능(TOOL_NAME 공백 = 파서 실패 — PreToolUse는 tool_name 상시 존재) → fail-closed 판정
[ -n "${TOOL_NAME:-}" ] || _gate_fail_closed

# Rule 1: Write/Edit to 05_Production/ 차단 (file_path만 체크)
if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
  if echo "$FILE_PATH" | grep -q "05_Production"; then
    echo '{"decision":"block","reason":"05_Production/ is read-only"}'
    exit 0
  fi
  if echo "$FILE_PATH" | grep -q "01_Literature"; then
    # Korea_Research 폴더는 예외 허용 (Session 50 승인)
    if echo "$FILE_PATH" | grep -q "Korea_Research"; then
      : # allow
    else
      echo '{"decision":"block","reason":"01_Literature/ is read-only"}'
      exit 0
    fi
  fi
fi

# Rule 2: Bash에서 05_Production에 쓰기 시도 차단 (> 또는 mv/cp 대상일 때만)
if [ "$TOOL_NAME" = "Bash" ]; then
  if echo "$COMMAND" | grep -qE "(>|mv|cp|rm).*05_Production"; then
    echo '{"decision":"block","reason":"05_Production/ write attempt via Bash"}'
    exit 0
  fi
  # normalizePath 차단
  if echo "$COMMAND" | grep -q "normalizePath"; then
    echo '{"decision":"block","reason":"normalizePath() breaks Korean paths in WSL2"}'
    exit 0
  fi
fi

# Rule 3 (P0-M1): 무인 레인의 기억 디렉터리 쓰기 차단 → memory_inbox 안내. 표식 없으면 건너뛴다.
if [ "${QVEST_UNATTENDED_LANE:-}" = "1" ]; then
  case "$TOOL_NAME" in
    Write|Edit|MultiEdit)
      if _qmem_file_hit "$FILE_PATH"; then _qmem_block; fi ;;
    Bash)
      if _qmem_cmd_hit "$COMMAND"; then _qmem_block; fi ;;
  esac
fi

echo '{}'
exit 0
