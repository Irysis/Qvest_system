#!/bin/bash
#==============================================================================
# s0_debate_guard.sh — PreToolUse[Agent] Hook (방어선 1)
#
# S0 Debate를 단일 에이전트가 다역할 시뮬레이션하는 것을 기계적으로 차단.
#
# 허용 구성 (V6 Amendment APPROVED 2026-04-19):
#   Compact (3인): codex_critic + risk_manager + (judge OR governor)
#     → QVEST_DEBATE_MODE=compact 환경변수 설정 시 활성화
#   Full (5인): codex_critic + risk_manager + governor + quant + academic
#     → 기본값 (QVEST_DEBATE_MODE 미설정 또는 =full)
#
# 탐지 패턴:
#   1. 하나의 Agent 프롬프트에 역할 2+ 동시 포함 + 채점 지시
#   2. "각 역할" / "5인 토론" / "5개 관점" 등 시뮬레이션 유도 표현
#   3. S0 debate 관련 Agent인데 /s0-debate 스킬 미사용 시 경고
#
# 설치: settings.json PreToolUse[Agent] hook으로 등록
#==============================================================================

trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)

# Agent 프롬프트 추출 (최대 2000자)
AGENT_PROMPT=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
print(ti.get('prompt', '')[:2000])
" 2>/dev/null || echo "")

AGENT_NAME=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
print(ti.get('name', ''))
" 2>/dev/null || echo "")

LOG="/tmp/s0_debate_guard.log"

# S0 Debate 관련 Agent인지 판별 (프롬프트 또는 이름에 S0/debate/hypothesis 키워드)
IS_S0_DEBATE=0
if echo "$AGENT_PROMPT" | grep -qiE 'S0.*(Debate|토론|가설)|debate.*(S0|가설)|hypothesis.*(debate|토론|평가|채점)'; then
  IS_S0_DEBATE=1
fi
if echo "$AGENT_NAME" | grep -qi "debate"; then
  IS_S0_DEBATE=1
fi

# S0 Debate가 아니면 통과
if [ "$IS_S0_DEBATE" -eq 0 ]; then
  echo '{}'
  exit 0
fi

# ─── 탐지 1: 단일 Agent에 다수 역할 주입 ───
# 4가지 역할 키워드 중 2개 이상이 하나의 프롬프트에 포함되면 시뮬레이션 의심
ROLE_COUNT=0
echo "$AGENT_PROMPT" | grep -qiE 'critic|codex_critic|비평|비판' && ROLE_COUNT=$((ROLE_COUNT + 1))
echo "$AGENT_PROMPT" | grep -qiE 'quant|팩트체크|ICIR.*검증|수치.*검증' && ROLE_COUNT=$((ROLE_COUNT + 1))
echo "$AGENT_PROMPT" | grep -qiE 'academic|학술|논문.*타당|피어리뷰' && ROLE_COUNT=$((ROLE_COUNT + 1))
echo "$AGENT_PROMPT" | grep -qiE 'risk.?m|tail.?risk|kill.?scenario|위험.*관리자|리스크' && ROLE_COUNT=$((ROLE_COUNT + 1))
echo "$AGENT_PROMPT" | grep -qiE 'governor|gap.*alignment|family.*saturation|role.*admission|한계기여|포트폴리오.*적합' && ROLE_COUNT=$((ROLE_COUNT + 1))

# 시뮬레이션 의도가 있는지 확인 (단순 언급은 허용, 채점 지시만 차단)
HAS_SIMULATION_INTENT=0
echo "$AGENT_PROMPT" | grep -qiE '채점.*rubric|점수.*매기|각각.*평가|독립.*채점|역할.*수행.*(평가|채점)|시뮬레이션|simulate.*roles|역할별.*(20|25)점' && HAS_SIMULATION_INTENT=1

# ─── Compact mode 감지 ───
DEBATE_MODE="${QVEST_DEBATE_MODE:-full}"
if [ "$DEBATE_MODE" = "compact" ]; then
  MIN_DEBATERS=3
  DEBATER_DESC="3인 Compact (codex_critic + risk_manager + judge|governor)"
else
  MIN_DEBATERS=5
  DEBATER_DESC="5인 Full (codex_critic + risk_manager + governor + quant + academic)"
fi

if [ "$ROLE_COUNT" -ge 3 ] && [ "$HAS_SIMULATION_INTENT" -eq 1 ]; then
  REASON="[S0 Debate Guard] 단일 Agent에 ${ROLE_COUNT}개 역할 + 채점 지시가 탐지되었습니다. S0 Debate는 ${DEBATER_DESC} 독립 에이전트를 개별 스폰해야 합니다. /s0-debate 스킬을 사용하세요."
  echo "$(date +%H:%M:%S) S0_DEBATE_GUARD BLOCK: single-agent multi-role ($ROLE_COUNT roles, mode=$DEBATE_MODE)" >> "$LOG"
  ESCAPED=$(echo "$REASON" | sed 's/"/\\"/g')
  printf '{"decision":"block","reason":"%s","hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$ESCAPED" "$ESCAPED"
  exit 0
fi

# ─── 탐지 2: 시뮬레이션 유도 표현 ───
if echo "$AGENT_PROMPT" | grep -qiE '각 역할.*(평가|채점|점수)|[345]인 토론.*시뮬|[345]개 관점.*채점|역할별.*(20|25)점|모든 역할.*수행|1인 [345]역|혼자.*[345]명|[345]명.*역할.*한번에'; then
  REASON="[S0 Debate Guard] 단일 Agent에 다인 시뮬레이션 패턴이 탐지되었습니다. S0 Debate 규칙 위반: 각 역할은 독립 에이전트로 스폰해야 합니다. /s0-debate 스킬의 Phase 2를 따르세요."
  echo "$(date +%H:%M:%S) S0_DEBATE_GUARD BLOCK: simulation pattern detected (mode=$DEBATE_MODE)" >> "$LOG"
  ESCAPED=$(echo "$REASON" | sed 's/"/\\"/g')
  printf '{"decision":"block","reason":"%s","hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$ESCAPED" "$ESCAPED"
  exit 0
fi

# ─── 탐지 3: S0 debate Agent인데 역할이 불명확한 경우 경고 ───
# compact 모드: risk_manager / judge / governor / codex_critic 중 1개
# full 모드: risk_manager / quant / academic / governor / codex_critic 중 1개
CLEAR_ROLE=0
echo "$AGENT_PROMPT" | grep -qiE '"role"\s*:\s*"(risk_manager|quant|academic|judge|governor|codex_critic)"' && CLEAR_ROLE=1

if [ "$CLEAR_ROLE" -eq 0 ] && [ "$ROLE_COUNT" -eq 1 ]; then
  # 1개 역할만 있으면 OK
  CLEAR_ROLE=1
fi

if [ "$CLEAR_ROLE" -eq 0 ] && [ "$ROLE_COUNT" -eq 0 ]; then
  echo "$(date +%H:%M:%S) S0_DEBATE_GUARD WARN: S0 debate agent without clear role (mode=$DEBATE_MODE)" >> "$LOG"
  if [ "$DEBATE_MODE" = "compact" ]; then
    ROLE_LIST="risk_manager/judge/governor"
  else
    ROLE_LIST="risk_manager/quant/academic/governor"
  fi
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"[S0 Debate Guard] S0 debate Agent에 명확한 역할(${ROLE_LIST})이 지정되지 않았습니다. /s0-debate 스킬 Phase 2 준수를 확인하세요. (mode=${DEBATE_MODE})\"}}"
  exit 0
fi

echo '{}'
exit 0
