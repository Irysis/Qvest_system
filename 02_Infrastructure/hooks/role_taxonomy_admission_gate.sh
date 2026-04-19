#!/bin/bash
#==============================================================================
# role_taxonomy_admission_gate.sh — PreToolUse[Agent] Hook (v55 Tier 3.1)
#
# 6종 role 기반 agent spawn 제어.
# Scout/Forge/Judge/Governor 스폰 시 expected_role 힌트 검증.
# unknown 또는 invalid role 감지 시 warn (block하지 않음, soft gate).
#==============================================================================

trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
LOG="/tmp/role_taxonomy_gate.log"

AGENT_NAME=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('name', ''))
except: print('')
" 2>/dev/null || echo "")

AGENT_PROMPT=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('prompt', '')[:3000])
except: print('')
" 2>/dev/null || echo "")

AGENT_LC=$(echo "$AGENT_NAME" | tr '[:upper:]' '[:lower:]')

# Scout 에이전트인 경우 expected_role 힌트 검증
if echo "$AGENT_LC" | grep -qE "scout"; then
  # prompt에서 expected_role 언급 여부 체크
  ROLE_MENTION=$(echo "$AGENT_PROMPT" | grep -oiE "expected_role[^a-z]*(core_alpha|diversifier|defense|cash_allocation|regime_adaptive|ml_predictive|unknown)" | head -1)

  # Scout이 S0 가설 설계하는데 role이 unknown이거나 명시 안 됨
  if echo "$AGENT_PROMPT" | grep -qiE "s0|hypothesis|가설" \
     && ! echo "$ROLE_MENTION" | grep -qiE "core_alpha|diversifier|defense|cash_allocation|regime_adaptive|ml_predictive"; then
    HINT="[Role Taxonomy Gate] Scout 스폰 감지. v55: s0_record에 expected_role 필수 (6종 중 하나). 'unknown' 사용 금지. GAP-Directed 가설 설계 시 portfolio_gap_vector의 sleeve_needs를 참고하여 role을 결정하세요. 참조: 00_Lawbook/v55_consensus_addendum.md §2."
    HINT_ESC=$(printf '%s' "$HINT" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")
    echo "$(date +%H:%M:%S) ROLE_GATE WARN (scout): $AGENT_NAME (no explicit role hint)" >> "$LOG"
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":$HINT_ESC}}"
    exit 0
  fi
fi

# Forge S1 스폰 시 trail 힌트 검증
if echo "$AGENT_LC" | grep -qE "forge.*s1|s1.*forge"; then
  TRAIL_MENTION=$(echo "$AGENT_PROMPT" | grep -oiE "trail[^a-z]*(standard|ml_empirical_first|kr_statistical)" | head -1)

  if [ -z "$TRAIL_MENTION" ]; then
    HINT="[Role Taxonomy Gate] Forge S1 스폰. v55: s0_record의 trail 필드가 S1 코딩 컨벤션 결정 (standard/ml_empirical_first/kr_statistical). trail 명시 없으면 standard로 진행. 참조: 02_Infrastructure/prompts/forge_init.md."
    HINT_ESC=$(printf '%s' "$HINT" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")
    echo "$(date +%H:%M:%S) ROLE_GATE WARN (forge_s1): $AGENT_NAME (no explicit trail)" >> "$LOG"
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":$HINT_ESC}}"
    exit 0
  fi
fi

echo '{}'
