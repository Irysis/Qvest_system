#!/bin/bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
#==============================================================================
# role_taxonomy_admission_gate.sh — PreToolUse[Agent] Hook (v55 Tier 3.1)
#
# 6종 role 기반 agent spawn 제어.
# Scout/Forge/Judge/Governor 스폰 시 expected_role 힌트 검증.
# unknown 또는 invalid role 감지 시 warn (block하지 않음, soft gate).
#==============================================================================

trap 'echo "{}"; exit 0' ERR
# (v8.1.2 2026-06-11) python stdio UTF-8 강제 — additionalContext lone surrogate(API 400) 수리
export PYTHONUTF8=1

INPUT=$(cat)
LOG="/tmp/role_taxonomy_gate.log"

AGENT_NAME=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('name', ''))
except: print('')
" 2>/dev/null || echo "")

AGENT_PROMPT=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c "
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
    HINT="[Role Taxonomy Gate] Scout 스폰 감지. v55: s0_record에 expected_role 필수 (6종 중 하나). 'unknown' 사용 금지. GAP-Directed 가설 설계 시 portfolio_gap_vector의 sleeve_needs를 참고하되, sleeve_needs는 조향 enum(overlay_refinement/residual_orthogonal_sleeve/non_return_datasource/dpl_feature; core_alpha_standalone=closed 16/16 admission FAIL)입니다 — role bucket이 아닌 탐색 방향이므로 방향에 부합하는 role(6종)을 별도로 명시하세요 (구 core_alpha/defense/diversifier 라벨은 legacy JSON에서만 등장). 참조: 02_Infrastructure/portfolio/gap_vector_steering.R + 00_Lawbook/v55_consensus_addendum.md §2."
    HINT_ESC=$(printf '%s' "$HINT" | "$QVEST_PY_BIN" -c "import sys,json; s=sys.stdin.buffer.read().decode('utf-8','replace'); print(json.dumps(''.join(ch if not(0xD800<=ord(ch)<=0xDFFF) else '?' for ch in s)))")
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
    HINT_ESC=$(printf '%s' "$HINT" | "$QVEST_PY_BIN" -c "import sys,json; s=sys.stdin.buffer.read().decode('utf-8','replace'); print(json.dumps(''.join(ch if not(0xD800<=ord(ch)<=0xDFFF) else '?' for ch in s)))")
    echo "$(date +%H:%M:%S) ROLE_GATE WARN (forge_s1): $AGENT_NAME (no explicit trail)" >> "$LOG"
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":$HINT_ESC}}"
    exit 0
  fi
fi

echo '{}'
