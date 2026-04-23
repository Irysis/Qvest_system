#!/usr/bin/env bash
#==============================================================================
# s0_verdict_router.sh — FileChanged Hook for S0_VERDICT_*.json
#==============================================================================

# ERR trap (Phase C3 전수 강제) — hook 실패 시 도구 차단 방지
trap 'echo "{}"; exit 0' ERR

#==============================================================================
# v55 Consensus 기반 판정 (점수제 폐지):
#   debaters[].stance (APPROVE/APPROVE_CONDITIONAL/REVISE/REJECT) 집계
#   veto_flag 동의 → REVISE/REJECT 강제
#   unresolved_disputes → S1 gate 승격 (APPROVE_CONDITIONAL)
#
# V6 Amendment (2026-04-19): debaters 수에 따라 자동 분기
#
# 5인 Full 집계 규칙 (기존):
#   4+ APPROVE       → APPROVE
#   3+ REJECT        → REJECT
#   veto 2+ 동의     → REVISE
#   3+ APPROVE/COND && REJECT<=1 → APPROVE_CONDITIONAL
#   그 외            → REVISE
#
# 3인 Compact 집계 규칙 (V6 신규):
#   3/3 APPROVE      → APPROVE
#   2+ REJECT        → REJECT
#   veto 1+ (Risk or Judge) → REVISE (veto 도메인)
#   2+ APPROVE/COND && 0 REJECT → APPROVE_CONDITIONAL
#   그 외            → REVISE
#
# 하위호환: stance 필드 없으면 score 기반 레거시 판정 (경고 로그)
#==============================================================================

INPUT=$(cat)

# 변경된 파일 경로
CHANGED_FILE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('file_path',''))" 2>/dev/null)

if [ -z "$CHANGED_FILE" ] || [ ! -f "$CHANGED_FILE" ]; then
  echo '{}'
  exit 0
fi

# ─── 방어선 3: debaters 무결성 사후 검증 (3인 Compact / 5인 Full 동적) ───
DEBATER_CHECK=$(python3 -c "
import json, sys, os
from collections import Counter
try:
    with open('$CHANGED_FILE') as f:
        d = json.load(f)

    debaters = d.get('debaters', [])
    if not debaters:
        if d.get('score_breakdown') or d.get('scores'):
            print('WARN|debaters 배열 없음 (구 형식). 라우팅 진행하되, 향후 debaters 형식 필수.')
        else:
            print('FAIL|debaters 배열 완전 누락. S0 Debate 미실행 의심.')
        sys.exit(0)

    n_debaters = len(debaters)
    # 3인 Compact vs 5인 Full 자동 감지 (debaters 수 기반)
    is_compact = (n_debaters == 3)
    min_debaters = 3

    errors = []

    agent_ids = [db.get('agent_id', '') for db in debaters]
    unique_ids = set(aid for aid in agent_ids if aid)

    if len(unique_ids) < min_debaters:
        errors.append(f'독립 agent_id {len(unique_ids)}개 (최소 {min_debaters}개 필요)')

    dupes = {k: v for k, v in Counter(agent_ids).items() if v > 1 and k}
    if dupes:
        errors.append(f'agent_id 중복: {dupes}')

    roles = set(db.get('role', '').lower() for db in debaters)
    normalized = set()
    for r in roles:
        if 'critic' in r: normalized.add('codex_critic')
        elif 'risk' in r: normalized.add('risk_manager')
        elif 'gov' in r: normalized.add('governor')
        elif 'judge' in r: normalized.add('judge')
        elif 'quant' in r: normalized.add('quant')
        elif 'academic' in r: normalized.add('academic')

    if is_compact:
        # Compact: codex_critic + risk_manager + (judge OR governor)
        compact_core = {'codex_critic', 'risk_manager'}
        compact_flex = {'judge', 'governor'}
        missing_core = compact_core - normalized
        if missing_core:
            errors.append(f'Compact 필수 역할 누락: {missing_core}')
        if not normalized.intersection(compact_flex):
            errors.append('Compact: judge 또는 governor 중 하나 필수')
    else:
        # Full 5인
        required = {'codex_critic', 'risk_manager', 'governor', 'quant', 'academic'}
        missing = required - normalized
        if missing:
            errors.append(f'역할 누락: {missing}')

    if errors:
        print('FAIL|' + '; '.join(errors))
    else:
        mode_tag = 'compact' if is_compact else 'full'
        print(f'PASS|OK|{mode_tag}')
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
    "additionalContext": "[S0 Verdict Router BLOCKED] debaters 검증 실패: ${DEBATER_MSG}\n\nS0_VERDICT가 생성되었으나 독립 토론 증거가 부족합니다.\n[Compact 3인] codex_critic + risk_manager + (judge OR governor)\n[Full 5인] codex_critic + risk_manager + governor + quant + academic\n\n1. /s0-debate 스킬을 사용하여 독립 에이전트 스폰\n2. 각 에이전트의 agent_id가 고유해야 합니다\n3. debaters 배열에 {agent_id, role, stance, veto_flag, critical_concerns, supporting_arguments} 필수 (v55 Consensus)\n4. S0_VERDICT를 재작성하세요: ${CHANGED_FILE}"
  }
}
EOF
  exit 0
fi

if [ "$DEBATER_STATUS" = "WARN" ]; then
  echo "$(date +%H:%M:%S) VERDICT_ROUTER WARN: $CHANGED_FILE — $DEBATER_MSG" >> /tmp/s0_verdict.log
fi

# ─── v55/V6 Consensus-based Verdict Aggregation (3인 Compact / 5인 Full) ───
# 환경변수로 파일 경로 전달
export CHANGED_FILE
CONSENSUS_RESULT=$(CHANGED_FILE="$CHANGED_FILE" python3 <<'PYEOF'
import json, sys, os
from collections import Counter

try:
    with open(os.environ['CHANGED_FILE']) as f:
        d = json.load(f)
except Exception as e:
    print(f'ERROR|parse_failed|{e}|0|0|0|0|0|0|unknown|')
    sys.exit(0)

debaters = d.get('debaters', [])
n_debaters = len(debaters)
is_compact = (n_debaters <= 3)
factor_id = d.get('factor_id', 'unknown')
strategy_id = d.get('strategy_id', '')

has_stance = any(db.get('stance') for db in debaters)

if has_stance:
    stances = [str(db.get('stance', '')).upper() for db in debaters]
    veto_list = [(db.get('veto_flag'), str(db.get('role','')).lower()) for db in debaters if db.get('veto_flag') and str(db.get('veto_flag')).lower() not in ('null','none','')]
    unresolved = d.get('unresolved_disputes', [])

    approve_cnt = sum(1 for s in stances if s == 'APPROVE')
    cond_cnt = sum(1 for s in stances if s in ('APPROVE_CONDITIONAL','CONDITIONAL'))
    revise_cnt = sum(1 for s in stances if s == 'REVISE')
    reject_cnt = sum(1 for s in stances if s == 'REJECT')

    # Codex veto 권한 없음 (flag만) - 제외
    effective_vetoes = [vf for vf, role in veto_list if 'codex' not in role]
    veto_cnt = len(effective_vetoes)
    unresolved_cnt = len(unresolved)

    if is_compact:
        # ─── 3인 Compact 집계 규칙 (V6 Amendment §S0.1) ───
        if approve_cnt == 3:
            verdict = 'APPROVE'
        elif reject_cnt >= 2:
            verdict = 'REJECT'
        elif veto_cnt >= 1:
            # Risk or Judge veto 1+ → REVISE
            verdict = 'REVISE'
        elif (approve_cnt + cond_cnt) >= 2 and reject_cnt == 0:
            verdict = 'APPROVE_CONDITIONAL'
        else:
            verdict = 'REVISE'
    else:
        # ─── 5인 Full 집계 규칙 (기존 유지) ───
        if reject_cnt >= 3:
            verdict = 'REJECT'
        elif approve_cnt >= 4:
            verdict = 'APPROVE'
        elif veto_cnt >= 2:
            verdict = 'REVISE'
        elif (approve_cnt + cond_cnt) >= 3 and reject_cnt <= 1:
            verdict = 'APPROVE_CONDITIONAL'
        else:
            verdict = 'REVISE'

    # Consensus tag
    total = n_debaters
    if approve_cnt == total or reject_cnt == total:
        ctag = 'UNANIMOUS'
    elif approve_cnt >= (total - 1) or reject_cnt >= (total - 1):
        ctag = 'MAJORITY'
    elif approve_cnt == 0 and reject_cnt == 0:
        ctag = 'DEADLOCK'
    else:
        ctag = 'MINORITY'

    mode_tag = 'compact' if is_compact else 'full'
    print(f'CONSENSUS|{verdict}|{approve_cnt}|{cond_cnt}|{revise_cnt}|{reject_cnt}|{veto_cnt}|{unresolved_cnt}|{ctag}|{factor_id}|{strategy_id}|{mode_tag}')
else:
    verdict_field = str(d.get('verdict', 'UNKNOWN')).upper()
    total_score = d.get('total_score', 0) or sum(db.get('score', 0) for db in debaters)

    if verdict_field == 'APPROVE':
        verdict = 'APPROVE'
    elif verdict_field in ('APPROVE_CONDITIONAL','CONDITIONAL'):
        verdict = 'APPROVE_CONDITIONAL'
    elif verdict_field == 'REJECT':
        verdict = 'REJECT'
    else:
        verdict = 'REVISE'

    print(f'LEGACY|{verdict}|0|0|0|0|0|0|LEGACY_SCORE_{total_score}|{factor_id}|{strategy_id}|legacy')
PYEOF
)

MODE=$(echo "$CONSENSUS_RESULT" | cut -d'|' -f1)
VERDICT=$(echo "$CONSENSUS_RESULT" | cut -d'|' -f2)
APPROVE_CNT=$(echo "$CONSENSUS_RESULT" | cut -d'|' -f3)
COND_CNT=$(echo "$CONSENSUS_RESULT" | cut -d'|' -f4)
REVISE_CNT=$(echo "$CONSENSUS_RESULT" | cut -d'|' -f5)
REJECT_CNT=$(echo "$CONSENSUS_RESULT" | cut -d'|' -f6)
VETO_CNT=$(echo "$CONSENSUS_RESULT" | cut -d'|' -f7)
UNRESOLVED_CNT=$(echo "$CONSENSUS_RESULT" | cut -d'|' -f8)
CTAG=$(echo "$CONSENSUS_RESULT" | cut -d'|' -f9)
FACTOR_ID=$(echo "$CONSENSUS_RESULT" | cut -d'|' -f10)
STRATEGY_ID=$(echo "$CONSENSUS_RESULT" | cut -d'|' -f11)
DEBATE_SIZE=$(echo "$CONSENSUS_RESULT" | cut -d'|' -f12)

echo "$(date +%H:%M:%S) VERDICT_ROUTER v55/V6 [$MODE/$DEBATE_SIZE]: $FACTOR_ID → $VERDICT (A=$APPROVE_CNT, C=$COND_CNT, REV=$REVISE_CNT, REJ=$REJECT_CNT, veto=$VETO_CNT, unresolved=$UNRESOLVED_CNT, tag=$CTAG)" >> /tmp/s0_verdict.log

# ─── 라우팅 ───
case "$VERDICT" in
  APPROVE)
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "FileChanged",
    "additionalContext": "[S0 Verdict: APPROVE] ${FACTOR_ID} — Consensus ${CTAG} (A=${APPROVE_CNT}, COND=${COND_CNT}, REJECT=${REJECT_CNT}, veto=${VETO_CNT})\n\nScout plan을 승인하고 다음을 실행하세요:\n1. allocate_str() → STR 번호 할당\n2. sg_init() → stage tracker\n3. s0_record.json 작성 (expected_role 6종 / trail 3종 / gap_targeting_axes 필수)\n4. Forge inbox에 TODO_S1 생성\n5. 텔레그램 발송\n\n판정 상세: ${CHANGED_FILE}"
  }
}
EOF
    ;;
  APPROVE_CONDITIONAL)
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "FileChanged",
    "additionalContext": "[S0 Verdict: APPROVE_CONDITIONAL] ${FACTOR_ID} — Consensus ${CTAG} (A=${APPROVE_CNT}, COND=${COND_CNT}, REJECT=${REJECT_CNT}, veto=${VETO_CNT}, unresolved=${UNRESOLVED_CNT})\n\nScout plan 조건부 승인. unresolved_disputes는 S1 gate에서 실측 의무화:\n1. allocate_str() → STR 번호 할당\n2. sg_init() → stage tracker\n3. s0_record.json 작성 (expected_role 6종 / trail 3종 / gap_targeting_axes / cash_component 필수)\n4. Forge inbox에 TODO_S1 생성 (unresolved_disputes를 s1_gate_items로 전달)\n5. 텔레그램 발송\n\n판정 상세: ${CHANGED_FILE}"
  }
}
EOF
    ;;
  REVISE)
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "FileChanged",
    "additionalContext": "[S0 Verdict: REVISE] ${FACTOR_ID} — Consensus ${CTAG} (REVISE=${REVISE_CNT}, veto=${VETO_CNT})\n\n재설계 필요. veto 2+ 동의 또는 과반 REVISE:\n1. ${CHANGED_FILE} 읽고 unresolved_disputes + critical_concerns 확인\n2. Scout을 plan mode로 재스폰 (name: scout-s0)\n3. critical_concerns를 모두 addressing하는 revised hypothesis 설계\n4. 재설계 후 다시 토론팀 스폰\n\n주의: 동일 가설 재설계 2회 이상 REVISE 시 가설 근본 재고."
  }
}
EOF
    ;;
  REJECT)
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "FileChanged",
    "additionalContext": "[S0 Verdict: REJECT] ${FACTOR_ID} — Consensus ${CTAG} (REJECT=${REJECT_CNT})\n\n가설 폐기 (3+ debater REJECT):\n1. 폐기 사유는 ${CHANGED_FILE} 참조\n2. 새로운 가설 방향 탐색 필요\n3. conditional_ic_matrix + gap_targeting_axes 우선순위에서 다른 factor 조합 검토\n4. GAP-directed: 현재 포트폴리오 부족 role(defense/diversifier/cash) 우선"
  }
}
EOF
    ;;
  *)
    echo '{}'
    ;;
esac
