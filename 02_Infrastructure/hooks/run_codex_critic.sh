#!/usr/bin/env bash
#==============================================================================
# run_codex_critic.sh — S0 Debate Critic을 Codex CLI(GPT-5.4)로 직접 실행
#
# 사용법:
#   bash 02_Infrastructure/hooks/run_codex_critic.sh \
#     "가설 요약 텍스트" \
#     "관련 L-code 텍스트" \
#     "실패 전략 목록"
#
# 또는 환경변수:
#   SCOUT_PLAN="..." L_CODE_FINDINGS="..." FAILED_STRATEGIES="..." \
#   bash 02_Infrastructure/hooks/run_codex_critic.sh
#
# 출력: /tmp/codex_critic_result.json
#==============================================================================

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE="$DIR/02_Infrastructure/prompts/codex_critic_prompt.md"
COMPANION="$HOME/.claude/plugins/cache/openai-codex/codex/1.0.2/scripts/codex-companion.mjs"
OUTPUT="/tmp/codex_critic_result.json"

# 인자 또는 환경변수에서 읽기
SCOUT_PLAN="${1:-${SCOUT_PLAN:-NO_PLAN}}"
L_CODE_FINDINGS="${2:-${L_CODE_FINDINGS:-NO_LCODES}}"
FAILED_STRATEGIES="${3:-${FAILED_STRATEGIES:-NO_FAILURES}}"

if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: Critic template not found: $TEMPLATE" >&2
  exit 1
fi

if [ ! -f "$COMPANION" ]; then
  echo "ERROR: codex-companion.mjs not found: $COMPANION" >&2
  exit 1
fi

# 템플릿 치환
FILLED=$(cat "$TEMPLATE" \
  | sed "s|{{SCOUT_PLAN}}|$SCOUT_PLAN|g" \
  | sed "s|{{L_CODE_FINDINGS}}|$L_CODE_FINDINGS|g" \
  | sed "s|{{FAILED_STRATEGIES}}|$FAILED_STRATEGIES|g")

# /tmp에 저장
echo "$FILLED" > /tmp/codex_critic_filled.md

echo "[Codex Critic] Calling GPT-5.4 via codex-companion..." >&2

# Codex CLI 직접 호출 (GPT-5.4)
node "$COMPANION" task --wait --effort xhigh "$(cat /tmp/codex_critic_filled.md)" > "$OUTPUT" 2>/tmp/codex_critic_stderr.log

if [ $? -eq 0 ] && [ -s "$OUTPUT" ]; then
  echo "[Codex Critic] Success. Result: $OUTPUT" >&2
  cat "$OUTPUT"
else
  echo "[Codex Critic] FAILED. stderr:" >&2
  cat /tmp/codex_critic_stderr.log >&2
  echo '{"error": "codex_critic_failed", "fallback": true}' > "$OUTPUT"
  cat "$OUTPUT"
  exit 1
fi
