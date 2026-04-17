#!/bin/bash
#==============================================================================
# Unified Agent Guard — PreToolUse[Agent] Hook (v52 하네스)
# 3중 검증:
#   1. Stage Order: Agent name 기반 선행 artifact 존재 확인
#   2. S5 Spawn Order: Forge S5 전 RiskMgr 사전평가 필수
#   3. S0 Debate: s0_debate_guard.sh로 위임 (별도 Hook 유지)
#==============================================================================

trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR

INPUT=$(cat)
DIR=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
if [ -z "$DIR" ]; then echo '{"decision":"allow"}'; exit 0; fi

ARTS="$DIR/stage_artifacts"

# Agent name 추출
AGENT_NAME=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('name', ''))
except: print('')
" 2>/dev/null || echo "")

AGENT_NAME_LC=$(echo "$AGENT_NAME" | tr '[:upper:]' '[:lower:]')

# ─── 1. Stage Order Guard ────────────────────────────────────────────────────
# Agent name에서 stage 패턴 매칭 (name 기반만, 프롬프트 미검사)

# Forge S1: S0_VERDICT APPROVE 필요
if echo "$AGENT_NAME_LC" | grep -qE "forge.*(s1|cbpq|atyp|factor)"; then
  APPROVED=$(ls "$ARTS"/S0_VERDICT_*.json 2>/dev/null | head -1)
  if [ -z "$APPROVED" ]; then
    printf '{"decision":"block","reason":"[Stage Guard] Forge S1 차단: S0_VERDICT APPROVE artifact 없음. S0 Debate 먼저 완료하세요."}'
    exit 0
  fi
fi

# Judge S6: S2 + S4 + S5 artifact 필요
if echo "$AGENT_NAME_LC" | grep -qE "judge.*s6"; then
  MISSING=""
  ls "$ARTS"/s2_profile_*.json     >/dev/null 2>&1 || MISSING="${MISSING}s2_profile "
  ls "$ARTS"/s4_marginal_*.json    >/dev/null 2>&1 || MISSING="${MISSING}s4_marginal "
  ls "$ARTS"/s5_research_slate_*.json >/dev/null 2>&1 || MISSING="${MISSING}s5_research_slate "
  if [ -n "$MISSING" ]; then
    printf '{"decision":"block","reason":"[Stage Guard] Judge S6 차단: 선행 artifact 누락 [%s]. S2~S5 완료 후 스폰하세요."}' "$MISSING"
    exit 0
  fi
fi

# Governor PG: S6 Judge Grade A 필요
if echo "$AGENT_NAME_LC" | grep -qE "governor.*pg"; then
  GRADE_A=$(grep -rl '"grade".*"A"' "$ARTS"/s6_judge_*.json 2>/dev/null | head -1)
  if [ -z "$GRADE_A" ]; then
    printf '{"decision":"block","reason":"[Stage Guard] Governor PG 차단: S6 Judge Grade A artifact 없음. S6 검증 먼저 완료하세요."}'
    exit 0
  fi
fi

# ─── 2. S5 Spawn Order (기존 s5_spawn_order.sh 통합) ─────────────────────────
# Forge S5 스폰 시 RiskMgr 사전평가 필수

IS_FORGE_S5=0
if echo "$AGENT_NAME_LC" | grep -qE "forge.*s5|s5.*forge"; then
  IS_FORGE_S5=1
fi

if [ "$IS_FORGE_S5" -eq 1 ]; then
  RISK_FILES=$(ls "$ARTS"/s5_risk_assessment_*.json 2>/dev/null | wc -l)
  if [ "$RISK_FILES" -eq 0 ]; then
    printf '{"decision":"block","reason":"[S5 Hook] Forge S5 차단: Risk Manager 사전 평가(s5_risk_assessment_*.json) 미완료. RiskMgr을 먼저 스폰하세요."}'
    exit 0
  fi
fi

# ─── 3. v53 Fix #5: Scout 스폰 시 Axiom Signal 힌트 자동 주입 (additionalContext only) ──
if echo "$AGENT_NAME_LC" | grep -q "scout"; then
  SIG="$DIR/.cache/axiom_signals.json"
  if [ -f "$SIG" ]; then
    HINT=$(python3 -c "
import json
try:
    d = json.load(open('$SIG'))
    rp = [e.get('pattern','') for e in d.get('reuse_penalty',{}).get('entries',[])[:3] if e.get('pattern')]
    fc = [e.get('cluster','') for e in d.get('failure_cluster',{}).get('entries',[])[:3] if e.get('cluster')]
    parts = []
    if rp: parts.append('reuse_penalty: ' + '; '.join(rp))
    if fc: parts.append('failure_cluster: ' + '; '.join(fc))
    if parts: print('[Axiom Guard] 최근 실패 패턴 회피 권고 — ' + ' | '.join(parts))
except Exception:
    pass
" 2>/dev/null)
    if [ -n "$HINT" ]; then
      # JSON escape for additionalContext
      HINT_ESC=$(printf '%s' "$HINT" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")
      echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":$HINT_ESC}}"
      exit 0
    fi
  fi
fi

# ─── 4. 기타 (Explore, general-purpose 등) → 무조건 허용 ─────────────────────
echo '{"decision":"allow"}'
exit 0
