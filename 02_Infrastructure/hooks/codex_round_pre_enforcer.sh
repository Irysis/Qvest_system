#!/usr/bin/env bash
#==============================================================================
# codex_round_pre_enforcer.sh — Tier 4 PreToolUse hard block (L3)
#
# 이벤트: PreToolUse[Write|Edit]
# 목적: agent가 *_package.json (no _draft suffix) 직접 작성 시 차단
#       Codex critic round 미완료 우회 방지
#
# 차단 조건 (AND):
#   1. 파일명이 alpha_package.json | risk_package.json | optimization_package.json
#      | forge_package.json | judge_verdict.json | governor_admission.json
#   2. 동일 디렉토리에 다음 둘 모두 부재:
#      - {role}_package_draft.json
#      - codex_critic_response_{role}.json
#
# 통과 조건:
#   - 위 2건 존재 (정상 cycle: _draft → critic → final)
#   - OR challenge_note.md 에 codex_critic_skip_waiver 명시 (도훈 override)
#
# Reference: Session 75 L-269 — v6.0 Codex Critic Round 의무 우회 사례
#==============================================================================

set -euo pipefail
LOG="/tmp/codex_round_pre_enforcer.log"
trap 'echo "[$(date -Iseconds)] HOOK_ERR_TRAP" >> "$LOG"; echo "{}"; exit 0' ERR

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then echo '{}'; exit 0; fi

# Strict regex: only final *_package.json / *_verdict.json / *_admission.json (NOT _draft, NOT codex_critic_response, NOT bak)
ROLE=""
if [[ "$FILE_PATH" =~ /alpha_package\.json$ ]]; then ROLE="alpha"
elif [[ "$FILE_PATH" =~ /risk_package\.json$ ]]; then ROLE="risk"
elif [[ "$FILE_PATH" =~ /optimization_package\.json$ ]]; then ROLE="optimizer"
elif [[ "$FILE_PATH" =~ /forge_package\.json$ ]]; then ROLE="forge"
elif [[ "$FILE_PATH" =~ /judge_verdict\.json$ ]]; then ROLE="judge"
elif [[ "$FILE_PATH" =~ /governor_admission\.json$ ]]; then ROLE="governor"
else
  echo '{}'; exit 0
fi

# Exclude _draft / codex_critic_response / backup paths (false positive 방지)
if [[ "$FILE_PATH" =~ _draft\.json$|codex_critic_response|\.(bak|backup|tmp)$ ]]; then
  echo '{}'; exit 0
fi

WT_DIR=$(dirname "$FILE_PATH")
DRAFT_PATH="$WT_DIR/${ROLE}_package_draft.json"
[[ "$ROLE" == "judge" ]] && DRAFT_PATH="$WT_DIR/judge_verdict_draft.json"
[[ "$ROLE" == "governor" ]] && DRAFT_PATH="$WT_DIR/governor_admission_draft.json"

CRITIC_RESPONSE="$WT_DIR/codex_critic_response_${ROLE}.json"
CHALLENGE_NOTE="$WT_DIR/challenge_note.md"

# Waiver 검증 (challenge_note.md에 codex_critic_skip_waiver 명시 시 통과)
if [[ -f "$CHALLENGE_NOTE" ]] && grep -q "codex_critic_skip_waiver" "$CHALLENGE_NOTE" 2>/dev/null; then
  echo "[$(date -Iseconds)] WAIVER_GRANTED file=$FILE_PATH challenge_note=$CHALLENGE_NOTE" >> "$LOG"
  echo '{}'
  exit 0
fi

# Hard block: _draft.json + codex_critic_response 둘 다 존재해야 통과
DRAFT_EXISTS="missing"
CRITIC_EXISTS="missing"
[[ -f "$DRAFT_PATH" ]] && DRAFT_EXISTS="present"
[[ -f "$CRITIC_RESPONSE" ]] && CRITIC_EXISTS="present"

if [[ "$DRAFT_EXISTS" == "present" && "$CRITIC_EXISTS" == "present" ]]; then
  # (2026-06-10) STUB 침묵통과 차단 — codex CLI 부재 시 생성되는 stance=STUB 응답은
  # 실제 교차검증이 아니므로 형식 존재만으로 통과 금지 (WT-D20260604_001 alpha 사례, AX-008)
  if grep -q '"stance"[[:space:]]*:[[:space:]]*"STUB"' "$CRITIC_RESPONSE" 2>/dev/null; then
    echo "[$(date -Iseconds)] BLOCK_STUB file=$FILE_PATH role=$ROLE critic=STUB" >> "$LOG"
    printf '{"decision":"block","reason":"CODEX_CRITIC_STUB (AX-008): codex_critic_response_%s.json stance=STUB — codex CLI 부재 시 생성된 무검증 응답. codex 설치 확인 후 round 재실행, 또는 challenge_note.md에 codex_critic_skip_waiver + 사유 명시."}\n' "$ROLE"
    exit 0
  fi
  echo "[$(date -Iseconds)] PASS file=$FILE_PATH role=$ROLE draft=present critic=present" >> "$LOG"
  echo '{}'
  exit 0
fi

# Block
BLOCK_REASON="CODEX_CRITIC_ROUND_REQUIRED (v6.0 의무 단계, L-269): role=$ROLE | draft=$DRAFT_EXISTS | critic_response=$CRITIC_EXISTS. 절차: (1) ${ROLE}_package_draft.json Write → (2) PostToolUse codex_round_auto_trigger.sh background spawn 대기 (~9-15분) → (3) codex_critic_response_${ROLE}.json 도착 후 challenge_note.md 기록 → (4) ${ROLE}_package.json finalize. waiver 필요 시 challenge_note.md 에 'codex_critic_skip_waiver' 명시 + 사유 + 도훈 override 인용."

echo "[$(date -Iseconds)] BLOCK file=$FILE_PATH role=$ROLE draft=$DRAFT_EXISTS critic=$CRITIC_EXISTS" >> "$LOG"
python3 -c "
import json
print(json.dumps({
    'decision': 'block',
    'reason': '''$BLOCK_REASON'''
}))
"
exit 0
