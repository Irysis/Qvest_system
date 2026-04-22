#!/bin/bash
#==============================================================================
# S5 Spawn Order Guard — PreToolUse[Agent] Hook
# Forge S5 스폰 시 RiskMgr 사전 평가(s5_risk_assessment_*.json) 완료 확인.
# 미완료 시 차단 → Q-Lead가 RiskMgr 먼저 스폰하도록 강제.
#==============================================================================

trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)

# Agent 이름 + 프롬프트 추출
AGENT_NAME=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
print(ti.get('name', ''))
" 2>/dev/null || echo "")

AGENT_PROMPT=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
print(ti.get('prompt', '')[:500])
" 2>/dev/null || echo "")

# forge + s5 패턴 매칭 (이름 또는 프롬프트에서)
IS_FORGE_S5=0
if echo "$AGENT_NAME" | grep -qi "forge.*s5\|s5.*forge"; then
  IS_FORGE_S5=1
fi
if [ "$IS_FORGE_S5" -eq 0 ] && echo "$AGENT_PROMPT" | grep -qi "S5.*Mutation\|S5.*Phase\|s5_research_slate"; then
  if echo "$AGENT_NAME" | grep -qi "forge"; then
    IS_FORGE_S5=1
  fi
fi

if [ "$IS_FORGE_S5" -eq 1 ]; then
  DIR=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
  if [ -z "$DIR" ]; then
    echo '{}'
    exit 0
  fi

  RISK_FILES=$(ls "$DIR/stage_artifacts/s5_risk_assessment_"*.json 2>/dev/null | wc -l)

  if [ "$RISK_FILES" -eq 0 ]; then
    printf '{"decision":"block","reason":"[S5 Hook] Forge S5 차단: Risk Manager 사전 평가(s5_risk_assessment_*.json) 미완료. RiskMgr을 먼저 스폰하고 kill scenario 정의 후 Forge를 스폰하세요."}'
    exit 0
  fi

  echo '{}'
  exit 0
fi

echo '{}'
exit 0
