#!/usr/bin/env bash
#==============================================================================
# _shared_parse.sh — stdin JSON 1회 파싱 → env export
#
# 사용법: 다른 hook에서 source. stdin을 1회만 python3로 파싱하여
# TOOL_NAME / FILE_PATH / COMMAND / CONTENT / AGENT_NAME / AGENT_PROMPT 환경변수 export.
#
# 절감 효과: 각 hook이 stdin을 3-4회 python3으로 파싱하던 것을 1회로 통합.
#
# 전제: INPUT 변수에 stdin 내용이 이미 있거나 없어야 함.
# 사용 예:
#   #!/bin/bash
#   INPUT=$(cat)
#   source "$(dirname "$0")/_shared_parse.sh"
#   # 이제 $TOOL_NAME, $FILE_PATH 등 사용 가능
#==============================================================================

trap 'echo "{}"; exit 0' ERR

# INPUT이 설정되지 않았으면 stdin을 읽음
if [ -z "${INPUT+x}" ]; then
  INPUT=$(cat)
fi

PARSED=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {}) or {}
    # Lines 1-6: tool_name, file_path, command, content_preview, agent_name, agent_prompt_preview
    print(d.get('tool_name', ''))
    print(ti.get('file_path', ''))
    print(ti.get('command', ''))
    # content는 Write 도구의 경우 전체, Edit은 new_string
    content = ti.get('content') or ti.get('new_string') or ''
    # 1500자 preview (패턴 매칭 용도만, full은 불필요)
    print(content[:1500])
    # Agent tool용
    print(ti.get('subagent_type') or ti.get('name') or '')
    prompt = ti.get('prompt') or ''
    print(prompt[:1500])
except Exception:
    for _ in range(6):
        print('')
" 2>/dev/null || printf '\n\n\n\n\n\n')

export TOOL_NAME=$(printf '%s\n' "$PARSED" | sed -n '1p')
export FILE_PATH=$(printf '%s\n' "$PARSED" | sed -n '2p')
export COMMAND=$(printf '%s\n' "$PARSED" | sed -n '3p')
export CONTENT=$(printf '%s\n' "$PARSED" | sed -n '4p')
export AGENT_NAME=$(printf '%s\n' "$PARSED" | sed -n '5p')
export AGENT_PROMPT=$(printf '%s\n' "$PARSED" | sed -n '6p')
export AGENT_NAME_LC=$(printf '%s' "$AGENT_NAME" | tr 'A-Z' 'a-z')
