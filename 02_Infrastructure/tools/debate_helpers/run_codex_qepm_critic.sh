#!/usr/bin/env bash
#==============================================================================
# run_codex_qepm_critic.sh — Codex Devil's Advocate (alpha/risk/optimizer)
#
# 목적: Claude (Opus/Sonnet) 산출물에 대한 GPT-5.5 cross-model critique.
#       QEPM 도메인 전문가 페르소나 (base context + role-specific).
#
# 사용:
#   bash run_codex_qepm_critic.sh \
#     --role={alpha|risk|optimizer} \
#     --task_id=WT-XXX \
#     --package=qepm/mailbox/worktask/WT-XXX/{role}_package.json \
#     [--output=qepm/mailbox/worktask/WT-XXX/codex_critic_response_{role}.json]
#
# 출력: codex_critic_response_{role}.json (JSON schema in role prompt)
# Verdict: stance + critical_concerns + weakest_assumption + AX cite
#
# v6.0 (2026-04-25): qepm_codex_base_context.md + 3 role prompts 통합
#==============================================================================

set -euo pipefail

# Args parsing
ROLE=""
TASK_ID=""
PACKAGE=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role=*) ROLE="${1#*=}"; shift ;;
    --role) ROLE="$2"; shift 2 ;;
    --task_id=*) TASK_ID="${1#*=}"; shift ;;
    --task_id) TASK_ID="$2"; shift 2 ;;
    --package=*) PACKAGE="${1#*=}"; shift ;;
    --package) PACKAGE="$2"; shift 2 ;;
    --output=*) OUTPUT="${1#*=}"; shift ;;
    --output) OUTPUT="$2"; shift 2 ;;
    *) echo "[ERR] Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Validation
if [[ ! "$ROLE" =~ ^(alpha|risk|optimizer)$ ]]; then
  echo "[ERR] --role must be one of: alpha, risk, optimizer (got: $ROLE)" >&2
  exit 2
fi

if [[ -z "$TASK_ID" ]]; then
  echo "[ERR] --task_id required (e.g., WT-D20260425_006)" >&2
  exit 2
fi

if [[ -z "$PACKAGE" || ! -f "$PACKAGE" ]]; then
  echo "[ERR] --package not found: $PACKAGE" >&2
  exit 2
fi

# Project root resolution (한글 경로 안전)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PROMPTS_DIR="$PROJECT_ROOT/02_Infrastructure/prompts"

BASE_CONTEXT="$PROMPTS_DIR/qepm_codex_base_context.md"
ROLE_PROMPT="$PROMPTS_DIR/codex_${ROLE}_critic_prompt.md"

if [[ ! -f "$BASE_CONTEXT" ]]; then
  echo "[ERR] base context missing: $BASE_CONTEXT" >&2
  exit 2
fi

if [[ ! -f "$ROLE_PROMPT" ]]; then
  echo "[ERR] role prompt missing: $ROLE_PROMPT" >&2
  exit 2
fi

# Default output path
if [[ -z "$OUTPUT" ]]; then
  WT_DIR=$(dirname "$PACKAGE")
  OUTPUT="$WT_DIR/codex_critic_response_${ROLE}.json"
fi

# Audit log
AUDIT_LOG="/tmp/codex_qepm_critic_${TASK_ID}_${ROLE}_$(date +%s).log"

echo "[Codex QEPM Critic] role=$ROLE task=$TASK_ID" | tee -a "$AUDIT_LOG"
echo "  package: $PACKAGE" | tee -a "$AUDIT_LOG"
echo "  output:  $OUTPUT" | tee -a "$AUDIT_LOG"
echo "  base:    $BASE_CONTEXT" | tee -a "$AUDIT_LOG"
echo "  role:    $ROLE_PROMPT" | tee -a "$AUDIT_LOG"

# Compact prompt: codex agent reads the context files itself (avoids argv limit)
WT_PKG_DIR=$(dirname "$PACKAGE")
STAGE_DIR_A="$PROJECT_ROOT/qepm/stage_artifacts/WT_${TASK_ID}"
STAGE_DIR_B="$PROJECT_ROOT/stage_artifacts/WT_${TASK_ID#WT-}"

PROMPT_PAYLOAD=$(cat <<EOF
You are QEPM Devil's Advocate (GPT-5.5 cross-model critic). External perspective on Claude's output. Echo chamber 회피 + KR market QEPM 도메인 전문가.

REQUIRED READS (in order):
1. ${BASE_CONTEXT}
   (QEPM domain base context — PIT C1~C15, AX-000~008, Hard Constraints, L-codes, Charter 8 principles)
2. ${ROLE_PROMPT}
   (role-specific RF flags + verification matrix + JSON output schema)

CRITIQUE TARGET (task=${TASK_ID}, role=${ROLE}):
- Primary package: ${PACKAGE}
- Other 3-agent context: ${WT_PKG_DIR}/{alpha_package,risk_package,optimization_package,*_challenge_note}.{json,md}
- Stage artifacts dir A: ${STAGE_DIR_A}
- Stage artifacts dir B: ${STAGE_DIR_B}
- weights.csv: ${WT_PKG_DIR}/weights.csv (시계열 schedule 검증)
- alpha_scores.parquet: ${STAGE_DIR_A}/alpha_scores.parquet (시계열 차원 검증, Iter 4 RF-A7 사례)
- covariance.parquet: ${STAGE_DIR_A}/covariance.parquet (PSD + cond ≤ 100 post-shrink)

CRITIQUE STEPS:
1. Read all required files (base + role + target package + stage artifacts).
2. Verify every checklist item in role prompt (RF-${ROLE^^}1~N).
3. Identify weakest_assumption (single most fragile claim).
4. Detect rationalization phrases per base context auto-flag list.
5. Cite AX-axiom / PIT-CXX / L-XXX / RF-XX in EVERY critical_concern.
6. Output ONLY valid JSON matching the role prompt's JSON schema. No prose, no markdown, no commentary outside the JSON object.

stance must be one of: APPROVE | APPROVE_CONDITIONAL | REVISE | REJECT.
veto_flag must be false (no veto권한).

Begin critique now.
EOF
)

# Token estimate (compact prompt only — codex reads files itself)
TOKEN_EST=$(echo "$PROMPT_PAYLOAD" | wc -w)
echo "  prompt_words: $TOKEN_EST (compact — files read by codex agent)" | tee -a "$AUDIT_LOG"

# Codex companion (legacy proven pattern from run_codex_critic.sh)
COMPANION=$(ls -t "$HOME/.claude/plugins/cache/openai-codex/codex/"*/scripts/codex-companion.mjs 2>/dev/null | head -1)

if [[ -z "$COMPANION" || ! -f "$COMPANION" ]]; then
  echo "[ERR] codex-companion.mjs not found. Install codex plugin." >&2
  cat > "$OUTPUT" <<JSON
{
  "agent_id": "codex_qepm_critic",
  "role": "${ROLE}_critic",
  "model": "gpt-5.5",
  "timestamp": "$(date -Iseconds)",
  "task_id": "$TASK_ID",
  "stance": "STUB",
  "stance_rationale": "codex-companion runtime unavailable.",
  "critical_concerns": [{"id": "STUB-1", "severity": "INFO", "description": "Codex unavailable", "ax_cite": "AX-008"}],
  "weakest_assumption": "stub",
  "rationalization_red_flags": [],
  "verification_triangulation": {"ax_008_status": "FAIL", "agree_with_claude": false, "additional_perspective": "stub"}
}
JSON
  exit 0
fi

echo "[Codex] companion: $COMPANION" | tee -a "$AUDIT_LOG"
echo "[Codex] invoking node companion ..." | tee -a "$AUDIT_LOG"

timeout "${CODEX_TIMEOUT:-1200}" node "$COMPANION" task --wait --effort xhigh "$PROMPT_PAYLOAD" > "$OUTPUT" 2>>"$AUDIT_LOG" || {
  echo "[WARN] Codex returned non-zero or timed out." | tee -a "$AUDIT_LOG"
}

# Validate output is valid JSON
if ! python3 -c "import json; json.load(open('$OUTPUT'))" 2>/dev/null; then
  echo "[WARN] Codex output not valid JSON. Wrapping into error envelope." | tee -a "$AUDIT_LOG"
  RAW=$(cat "$OUTPUT" 2>/dev/null || echo "")
  cat > "$OUTPUT" <<JSON
{
  "agent_id": "codex_qepm_critic",
  "role": "${ROLE}_critic",
  "model": "gpt-5.5",
  "timestamp": "$(date -Iseconds)",
  "task_id": "$TASK_ID",
  "stance": "ERROR",
  "stance_rationale": "Codex output was not valid JSON. See raw_output_excerpt.",
  "raw_output_excerpt": $(echo "$RAW" | head -c 500 | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
  "audit_log": "$AUDIT_LOG"
}
JSON
fi

# Extract verdict for caller
STANCE=$(python3 -c "import json; print(json.load(open('$OUTPUT')).get('stance',''))" 2>/dev/null || echo "?")
WEAKEST=$(python3 -c "import json; print(json.load(open('$OUTPUT')).get('weakest_assumption',''))" 2>/dev/null || echo "?")

echo ""
echo "[Codex QEPM Critic] DONE"
echo "  stance: $STANCE"
echo "  weakest_assumption: $WEAKEST"
echo "  output: $OUTPUT"
echo "  audit_log: $AUDIT_LOG"
