#!/usr/bin/env bash
#==============================================================================
# run_codex_critic_r2.sh — S0 Debate R2 Rebuttal용 Codex Critic 호출
#
# R1 transcript를 주입하여 GPT-5.4가 다른 4인의 주장을 보고 반박/동의.
#
# 환경변수:
#   R1_TRANSCRIPT  — R1 전체 transcript JSON
#   CODEX_R1_RESULT — Codex Critic R1 결과 JSON
#   HYP_ID         — 가설 ID (예: H_1643)
#
# 출력: /tmp/codex_critic_r2_result.json
#==============================================================================

set -euo pipefail

COMPANION="$HOME/.claude/plugins/cache/openai-codex/codex/1.0.2/scripts/codex-companion.mjs"
OUTPUT="/tmp/codex_critic_r2_result.json"

R1_TRANSCRIPT="${R1_TRANSCRIPT:-NO_TRANSCRIPT}"
CODEX_R1_RESULT="${CODEX_R1_RESULT:-NO_R1}"
HYP_ID="${HYP_ID:-unknown}"

if [ ! -f "$COMPANION" ]; then
  echo "ERROR: codex-companion.mjs not found: $COMPANION" >&2
  exit 1
fi

# R2 프롬프트 생성
cat > /tmp/codex_critic_r2_prompt.md << 'PROMPT_END'
# S0 Debate Round 2 — Rebuttal Phase

You are the **Codex Critic** (GPT-5.4) in Round 2 of a structured hypothesis debate.
In Round 1, you and 4 other evaluators independently scored a quant strategy hypothesis.
Now you can see everyone's Round 1 arguments.

## Your R1 Position
PROMPT_END

echo "$CODEX_R1_RESULT" >> /tmp/codex_critic_r2_prompt.md

cat >> /tmp/codex_critic_r2_prompt.md << 'PROMPT_END'

## All Evaluators' R1 Arguments (Full Transcript)
PROMPT_END

echo "$R1_TRANSCRIPT" >> /tmp/codex_critic_r2_prompt.md

cat >> /tmp/codex_critic_r2_prompt.md << 'PROMPT_END'

## Your Task

Read all 4 other evaluators' arguments carefully. Then respond with:

1. **agreements**: At least 1 point where you agree with another evaluator (specify who and what)
2. **rebuttals**: At least 1 point where you disagree (specify who, what, and why)
3. **score revision**: Your R1 score was {r1_score}/20. After seeing others' arguments, your revised score may change. If changed, explain why.
4. **strongest_opposing_argument**: Which single argument from the other 4 evaluators is the most compelling challenge to your position?

Return ONLY valid JSON:
```json
{
  "role": "codex_critic",
  "r1_score": <your R1 score>,
  "r2_score": <revised score, 0-20>,
  "score_changed": true/false,
  "score_change_reason": "reason if changed, empty if not",
  "agreements": [
    {"with": "role_name", "point": "what you agree with and why"}
  ],
  "rebuttals": [
    {"against": "role_name", "point": "what you disagree with and why", "severity": "major|minor"}
  ],
  "strongest_opposing_argument": "the single strongest challenge to your position",
  "kill_scenarios_update": "any new kill scenarios discovered from debate, or 'none'"
}
```
PROMPT_END

echo "[Codex Critic R2] Calling GPT-5.4 with R1 transcript..." >&2

node "$COMPANION" task --wait --effort xhigh "$(cat /tmp/codex_critic_r2_prompt.md)" > "$OUTPUT" 2>/tmp/codex_critic_r2_stderr.log

if [ $? -eq 0 ] && [ -s "$OUTPUT" ]; then
  echo "[Codex Critic R2] Success. Result: $OUTPUT" >&2
  cat "$OUTPUT"
else
  echo "[Codex Critic R2] FAILED. stderr:" >&2
  cat /tmp/codex_critic_r2_stderr.log >&2
  echo '{"error": "codex_critic_r2_failed", "fallback": true}' > "$OUTPUT"
  cat "$OUTPUT"
  exit 1
fi
