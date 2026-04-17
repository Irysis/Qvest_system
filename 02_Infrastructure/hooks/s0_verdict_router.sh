#!/usr/bin/env bash
#==============================================================================
# s0_verdict_router.sh — FileChanged Hook for S0_VERDICT_*.json
#
# 토론 판정 결과(S0_VERDICT)가 생성되면 자동 라우팅:
#   APPROVE → Q-Lead에 실행 승인 지시
#   REVISE  → Scout에 피드백 전달 지시
#   REJECT  → 폐기 로그 + 새 가설 탐색 지시
#==============================================================================

INPUT=$(cat)

# 변경된 파일 경로
CHANGED_FILE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('file_path',''))" 2>/dev/null)

if [ -z "$CHANGED_FILE" ] || [ ! -f "$CHANGED_FILE" ]; then
  echo '{}'
  exit 0
fi

# ─── 방어선 3: debaters 무결성 사후 검증 (verdict_router가 라우팅 전 최종 검증) ───
DEBATER_CHECK=$(python3 -c "
import json, sys
from collections import Counter
try:
    with open('$CHANGED_FILE') as f:
        d = json.load(f)

    # debaters 필드 존재 확인
    debaters = d.get('debaters', [])
    if not debaters:
        # 호환성: score_breakdown이 있으면 debaters 미전환 경고
        if d.get('score_breakdown') or d.get('scores'):
            print('WARN|debaters 배열 없음 (구 형식). 라우팅 진행하되, 향후 debaters 형식 필수.')
        else:
            print('FAIL|debaters 배열 완전 누락. S0 Debate 미실행 의심.')
        sys.exit(0)

    errors = []

    # agent_id 중복 검사
    agent_ids = [db.get('agent_id', '') for db in debaters]
    unique_ids = set(aid for aid in agent_ids if aid)

    if len(unique_ids) < 5:
        errors.append(f'독립 agent_id {len(unique_ids)}개 (최소 5개 필요)')

    dupes = {k: v for k, v in Counter(agent_ids).items() if v > 1 and k}
    if dupes:
        errors.append(f'agent_id 중복: {dupes}')

    # 필수 역할
    roles = set(db.get('role', '').lower() for db in debaters)
    required = {'codex_critic', 'risk_manager', 'governor', 'quant', 'academic'}
    normalized = set()
    for r in roles:
        if 'critic' in r: normalized.add('codex_critic')
        elif 'risk' in r: normalized.add('risk_manager')
        elif 'gov' in r: normalized.add('governor')
        elif 'quant' in r: normalized.add('quant')
        elif 'academic' in r: normalized.add('academic')
    missing = required - normalized
    if missing:
        errors.append(f'역할 누락: {missing}')

    if errors:
        print('FAIL|' + '; '.join(errors))
    else:
        print('PASS|OK')
except Exception as e:
    print(f'ERROR|{e}')
" 2>/dev/null)

DEBATER_STATUS=$(echo "$DEBATER_CHECK" | cut -d'|' -f1)
DEBATER_MSG=$(echo "$DEBATER_CHECK" | cut -d'|' -f2-)

if [ "$DEBATER_STATUS" = "FAIL" ]; then
  echo "$(date +%H:%M:%S) VERDICT_ROUTER BLOCK: $CHANGED_FILE — $DEBATER_MSG" >> /tmp/s0_verdict.log
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "FileChanged",
    "additionalContext": "[S0 Verdict Router BLOCKED] debaters 검증 실패: ${DEBATER_MSG}\n\nS0_VERDICT가 생성되었으나 5인 독립 토론 증거가 부족합니다.\n1. /s0-debate 스킬을 사용하여 5개 독립 에이전트 스폰 (codex_critic, risk_manager, governor, quant, academic)\n2. 각 에이전트의 agent_id가 고유해야 합니다\n3. debaters 배열에 5건의 {agent_id, role, score, findings} 필수\n4. S0_VERDICT를 재작성하세요: ${CHANGED_FILE}"
  }
}
EOF
  exit 0
fi

if [ "$DEBATER_STATUS" = "WARN" ]; then
  echo "$(date +%H:%M:%S) VERDICT_ROUTER WARN: $CHANGED_FILE — $DEBATER_MSG" >> /tmp/s0_verdict.log
fi

# S0_VERDICT JSON에서 판정 추출
VERDICT=$(python3 -c "
import json, sys
try:
    with open('$CHANGED_FILE') as f:
        d = json.load(f)
    print(d.get('verdict', 'UNKNOWN'))
except:
    print('UNKNOWN')
" 2>/dev/null)

TOTAL_SCORE=$(python3 -c "
import json
try:
    with open('$CHANGED_FILE') as f:
        d = json.load(f)
    print(d.get('total_score', 0))
except:
    print(0)
" 2>/dev/null)

FACTOR_ID=$(python3 -c "
import json
try:
    with open('$CHANGED_FILE') as f:
        d = json.load(f)
    print(d.get('factor_id', 'unknown'))
except:
    print('unknown')
" 2>/dev/null)

case "$VERDICT" in
  APPROVE|APPROVE_CONDITIONAL)
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "FileChanged",
    "additionalContext": "[S0 Verdict: ${VERDICT}] ${FACTOR_ID} (${TOTAL_SCORE}/100점)\n\nScout plan을 승인하고 다음을 실행하세요:\n1. allocate_str() → STR 번호 할당\n2. sg_init() → stage tracker\n3. s0_record.json 작성\n4. Forge inbox에 TODO_S1 생성\n5. 텔레그램 발송\n\n판정 상세: ${CHANGED_FILE}"
  }
}
EOF
    ;;
  REVISE)
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "FileChanged",
    "additionalContext": "[S0 Verdict: REVISE] ${FACTOR_ID} (${TOTAL_SCORE}/100점)\n\n점수 미달로 재설계 필요합니다:\n1. ${CHANGED_FILE} 읽고 피드백 확인\n2. Scout을 plan mode로 재스폰 (name: scout-s0)\n3. 피드백 내용을 Scout 프롬프트에 주입\n4. 재설계 후 다시 토론팀 스폰 (자동 체인)"
  }
}
EOF
    ;;
  REJECT)
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "FileChanged",
    "additionalContext": "[S0 Verdict: REJECT] ${FACTOR_ID} (${TOTAL_SCORE}/100점)\n\n가설이 폐기되었습니다:\n1. 폐기 사유는 ${CHANGED_FILE} 참조\n2. 새로운 가설 방향 탐색이 필요합니다\n3. conditional_ic_matrix에서 다른 팩터 조합을 검토하세요"
  }
}
EOF
    ;;
  *)
    echo '{}'
    ;;
esac
