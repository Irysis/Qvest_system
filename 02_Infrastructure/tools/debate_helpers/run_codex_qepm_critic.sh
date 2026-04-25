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

# Compose Codex prompt (base + role + package payload)
PROMPT_FILE=$(mktemp /tmp/codex_qepm_prompt_XXXXXX.md)
trap "rm -f $PROMPT_FILE" EXIT

{
  cat "$BASE_CONTEXT"
  echo ""
  echo "---"
  echo ""
  cat "$ROLE_PROMPT"
  echo ""
  echo "---"
  echo ""
  echo "## Critique Target Package (task: $TASK_ID, role: $ROLE)"
  echo ""
  echo '```json'
  cat "$PACKAGE"
  echo ""
  echo '```'
  echo ""
  echo "## Stage Artifacts (시계열 / Σ structure / weights schedule)"
  echo ""

  # Add relevant stage artifacts based on role
  STAGE_DIR="$PROJECT_ROOT/qepm/stage_artifacts/WT_${TASK_ID}"
  STAGE_DIR2="$PROJECT_ROOT/stage_artifacts/WT_${TASK_ID#WT-}"

  for D in "$STAGE_DIR" "$STAGE_DIR2"; do
    if [[ -d "$D" ]]; then
      echo "### Stage artifacts dir: \`$D\`"
      ls -la "$D" 2>/dev/null | head -20
      echo ""
    fi
  done

  # Role-specific schema hints
  case "$ROLE" in
    alpha)
      echo "### Verify alpha_scores.parquet time-series structure"
      echo "Expected schema: \`Date × Ticker × score_*\` (multi sig_dates)"
      echo "Single-snapshot risk: RF-A7 critical (Iter 4 사례)"
      ;;
    risk)
      echo "### Verify covariance.parquet PD + cond + factor coverage"
      echo "Expected: BΩB' + D decomposition. cond ≤ 100 post-shrink."
      ;;
    optimizer)
      WT_DIR=$(dirname "$PACKAGE")
      WEIGHTS_CSV="$WT_DIR/weights.csv"
      if [[ -f "$WEIGHTS_CSV" ]]; then
        echo "### weights.csv (head 5 lines)"
        echo '```'
        head -5 "$WEIGHTS_CSV"
        echo '```'
        echo ""
        echo "n_sig_dates_in_weights: $(awk -F',' 'NR>1 {print $1}' "$WEIGHTS_CSV" | sort -u | wc -l)"
      fi
      ;;
  esac

  echo ""
  echo "---"
  echo ""
  echo "## Critique Instructions"
  echo ""
  echo "1. **Read** package + stage artifacts."
  echo "2. **Verify** all checklist items in role prompt."
  echo "3. **Identify** weakest_assumption (single most fragile claim)."
  echo "4. **Detect** rationalization phrases (auto-flag list in base context)."
  echo "5. **Cite** AX-axiom + PIT-CXX + L-XXX + RF-XX in every critical_concern."
  echo "6. **Output** valid JSON matching the role prompt schema. No prose outside JSON."
  echo ""
  echo "Begin critique:"
} > "$PROMPT_FILE"

# Token estimate
TOKEN_EST=$(wc -w < "$PROMPT_FILE")
echo "  prompt_words: $TOKEN_EST" | tee -a "$AUDIT_LOG"

# Codex CLI invocation (uses codex-companion runtime per project convention)
CODEX_CMD="codex"
if ! command -v "$CODEX_CMD" >/dev/null 2>&1; then
  # Fallback: try project's local codex helper
  if [[ -x "$PROJECT_ROOT/02_Infrastructure/tools/codex/codex" ]]; then
    CODEX_CMD="$PROJECT_ROOT/02_Infrastructure/tools/codex/codex"
  else
    echo "[ERR] codex CLI not found. Install or check codex-companion runtime." >&2
    echo "[FALLBACK] Stub response written to $OUTPUT" >&2

    # Stub response (so pipeline doesn't break in dev environments)
    cat > "$OUTPUT" <<JSON
{
  "agent_id": "codex_qepm_critic",
  "role": "${ROLE}_critic",
  "model": "gpt-5.5",
  "timestamp": "$(date -Iseconds)",
  "task_id": "$TASK_ID",
  "stance": "STUB",
  "stance_rationale": "codex CLI unavailable — stub response. Real critique requires codex-companion runtime.",
  "critical_concerns": [{"id": "STUB-1", "severity": "INFO", "description": "Codex unavailable", "ax_cite": "AX-008"}],
  "weakest_assumption": "stub",
  "rationalization_red_flags": [],
  "verification_triangulation": {"ax_008_status": "FAIL", "agree_with_claude": false, "additional_perspective": "stub"}
}
JSON
    exit 0
  fi
fi

# Execute Codex (with timeout safeguard)
echo "[Codex] invoking $CODEX_CMD ..." | tee -a "$AUDIT_LOG"
timeout 600 "$CODEX_CMD" exec --model gpt-5.5 --output-format json < "$PROMPT_FILE" > "$OUTPUT" 2>>"$AUDIT_LOG" || {
  echo "[WARN] Codex returned non-zero or timed out. Output: $OUTPUT" | tee -a "$AUDIT_LOG"
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
