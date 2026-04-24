#!/usr/bin/env bash
#==============================================================================
# run_codex_critic_r2.sh — S0 Debate R2 Rebuttal용 Codex Critic 호출 (v55)
#
# R1 transcript를 주입하여 GPT-5.5가 다른 토론자들의 stance를 보고 자기 stance 갱신.
# 점수제 폐기 — stance_change / new_stance / addressed_concerns / unresolved 출력.
#
# 환경변수:
#   R1_TRANSCRIPT  — R1 전체 transcript JSON (모든 debater의 R1 결과 병합)
#   CODEX_R1_RESULT — Codex Critic R1 결과 JSON (자기 R1 stance/veto/concerns)
#   HYP_ID         — 가설 ID (예: H_1643)
#
# 출력: /tmp/codex_critic_r2_result.json
# 스키마 ground truth: 00_Lawbook/v55_consensus_addendum.md §1 + .claude/skills/s0-debate/SKILL.md Round 2
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

# R2 프롬프트 생성 (v55 Consensus)
cat > /tmp/codex_critic_r2_prompt.md << 'PROMPT_END'
# S0 Debate Round 2 — Rebuttal Phase (v55 Consensus)

You are the **Codex Critic** (GPT-5.5) in Round 2 of a structured hypothesis debate.
In Round 1, you and the other evaluators independently expressed a `stance` on a quant strategy hypothesis.
Now you can see everyone's Round 1 arguments and stances.

**v55 Consensus rules**: No numerical scoring. Express your R2 position as `stance_change` + `new_stance`
+ `addressed_concerns` + `unresolved` + `veto_flag`. Codex never holds veto power — `veto_flag` MUST be `null`.

## Your R1 Position
PROMPT_END

echo "$CODEX_R1_RESULT" >> /tmp/codex_critic_r2_prompt.md

cat >> /tmp/codex_critic_r2_prompt.md << 'PROMPT_END'

## All Evaluators' R1 Arguments (Full Transcript)
PROMPT_END

echo "$R1_TRANSCRIPT" >> /tmp/codex_critic_r2_prompt.md

cat >> /tmp/codex_critic_r2_prompt.md << 'PROMPT_END'

## Your Task

Read all other evaluators' R1 stances and arguments carefully. Then respond with:

1. **stance_change**: One of `UNCHANGED` / `UPGRADED` / `DOWNGRADED`.
   - `UNCHANGED` if your R1 stance still holds after debate.
   - `UPGRADED` if you move toward APPROVE (e.g., REVISE → APPROVE_CONDITIONAL → APPROVE).
   - `DOWNGRADED` if you move toward REJECT (e.g., APPROVE → APPROVE_CONDITIONAL → REVISE → REJECT).
2. **new_stance**: Your R2 final stance (APPROVE / APPROVE_CONDITIONAL / REVISE / REJECT). May be the same as R1.
3. **stance_change_reason**: REQUIRED if `stance_change != UNCHANGED`. Min 50 characters explaining what specific argument or evidence shifted you.
4. **addressed_concerns**: R1 critical_concerns (yours or others') that other debaters resolved. Empty array if none.
5. **unresolved**: At least 1 item — points that remain unresolved after debate. These will become S1 gate items.
6. **veto_flag**: **MUST be null** for Codex.

Return ONLY valid JSON. No markdown, no commentary outside the JSON:

```json
{
  "role": "codex_critic",
  "r1_stance": "<your R1 stance copied from above>",
  "r1_veto_flag": null,
  "stance_change": "UNCHANGED | UPGRADED | DOWNGRADED",
  "new_stance": "APPROVE | APPROVE_CONDITIONAL | REVISE | REJECT",
  "stance_change_reason": "string (>=50 chars if changed, empty if UNCHANGED)",
  "veto_flag": null,
  "addressed_concerns": [
    {"by": "role_name", "concern": "what was resolved and how"}
  ],
  "unresolved": [
    {"with": "role_name_or_self", "point": "what remains contested or needs S1 measurement"}
  ],
  "strongest_opposing_argument": "the single strongest challenge to your position",
  "kill_scenarios_update": "any new kill scenarios discovered from debate, or 'none'"
}
```
PROMPT_END

echo "[Codex Critic R2 v55] Calling GPT-5.5 with R1 transcript..." >&2

node "$COMPANION" task --wait --effort xhigh "$(cat /tmp/codex_critic_r2_prompt.md)" > "$OUTPUT" 2>/tmp/codex_critic_r2_stderr.log

# ─── 토큰 절감 (Block C v1.1 v55 strict, 2026-04-19): 요약만 ──────────
if [ $? -eq 0 ] && [ -s "$OUTPUT" ]; then
  echo "[Codex Critic R2 v55] Success. Full JSON: $OUTPUT (not piped)" >&2
  if command -v jq >/dev/null 2>&1; then
    jq -c '{role: (.role // "codex_critic"),
            r1_stance: (.r1_stance // null),
            r1_veto_flag: (.r1_veto_flag // null),
            stance_change: (.stance_change // null),
            new_stance: (.new_stance // null),
            stance_change_reason: (.stance_change_reason // ""),
            veto_flag: (.veto_flag // null),
            addressed_concerns: ((.addressed_concerns // [])[:2]),
            unresolved: ((.unresolved // [])[:3]),
            strongest_opposing_argument: (.strongest_opposing_argument // ""),
            result_file: "'"$OUTPUT"'"}' "$OUTPUT" 2>/dev/null \
      || cat "$OUTPUT"
  else
    cat "$OUTPUT"
  fi
else
  echo "[Codex Critic R2 v55] FAILED. stderr→/tmp/codex_critic_r2_stderr.log (not piped)" >&2
  echo '{"error": "codex_critic_r2_failed", "fallback": true, "stderr_file": "/tmp/codex_critic_r2_stderr.log"}' > "$OUTPUT"
  cat "$OUTPUT"
  exit 1
fi
