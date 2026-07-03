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
#==============================================================================

_gate_fail_closed() {
  local hay="${FILE_PATH:-}${COMMAND:-}"
  [ -n "$hay" ] || hay="${INPUT:-}"
  if printf '%s' "$hay" | grep -qE '05_Production|normalizePath' \
     || { printf '%s' "$hay" | grep -q '01_Literature' \
          && ! printf '%s' "$hay" | grep -q 'Korea_Research'; }; then
    echo '{"decision":"block","reason":"safety_guard: hook 내부 오류/판별불능 — 보호 대상(05_Production, 01_Literature, normalizePath) 패턴 감지, 검증 불가 시 차단 (fail-closed)"}'
  else
    echo '{}'
  fi
  exit 0
}
trap '_gate_fail_closed' ERR

INPUT=$(cat)
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_shared_parse.sh"
# _shared_parse.sh가 자체 fail-open trap('{}')을 설치하므로 fail-closed trap 재장전
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

echo '{}'
exit 0
