#!/bin/bash
#==============================================================================
# Safety Guard — PreToolUse Hook (3중 방어선 1선)
# Write/Edit/Bash 실행 전에 금지 패턴 차단.
#==============================================================================

INPUT=$(cat)
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_shared_parse.sh"

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
