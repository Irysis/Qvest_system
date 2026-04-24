#!/usr/bin/env bash
#==============================================================================
# run_codex_critic.sh — S0 Debate Critic을 Codex CLI(GPT-5.5)로 직접 실행
#
# 사용법 (경로는 Phase A 2026-04-22 이후 02_Infrastructure/tools/debate_helpers/):
#   bash 02_Infrastructure/tools/debate_helpers/run_codex_critic.sh \
#     "가설 요약 텍스트" \
#     "관련 L-code 텍스트" \
#     "실패 전략 목록"
#
# 또는 환경변수:
#   SCOUT_PLAN="..." L_CODE_FINDINGS="..." FAILED_STRATEGIES="..." \
#   bash 02_Infrastructure/tools/debate_helpers/run_codex_critic.sh
#
# 출력: /tmp/codex_critic_result.json
#
# ── 호출 방식 경고 (Gap-4, Session 68 Day 2, 2026-04-19) ─────────────────────
# **FOREGROUND SYNC 전용.** `nohup ... &` 또는 `&` background 호출 금지.
# 증상: nohup detach 후 stdout/stderr pipe 단절로 codex-companion이 "Turn started"
#       stderr만 남기고 OUTPUT 0 바이트로 silent exit (exit 0 반환). 호출자가
#       "성공했으나 빈 응답"을 받음. foreground `timeout 240 bash ...` 호출은 정상.
# 회피: enforcer/helper가 본 스크립트를 반드시 foreground sync로 호출.
#       병렬이 필요하면 호출자 측에서 multiple foreground processes를 spawn
#       (각자 별도 프로세스 + wait), **본 스크립트 자체는 non-detached 전제**.
# 참조: plans/v55-greedy-abelson.md Gap-4.
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

# 템플릿 치환 (python — multi-line / 특수문자 안전. sed는 멀티라인에서 깨짐)
SCOUT_PLAN="$SCOUT_PLAN" L_CODE_FINDINGS="$L_CODE_FINDINGS" FAILED_STRATEGIES="$FAILED_STRATEGIES" \
TEMPLATE_PATH="$TEMPLATE" \
python3 -c "
import os
with open(os.environ['TEMPLATE_PATH'], 'r') as f: tpl = f.read()
tpl = tpl.replace('{{SCOUT_PLAN}}', os.environ.get('SCOUT_PLAN','NO_PLAN'))
tpl = tpl.replace('{{L_CODE_FINDINGS}}', os.environ.get('L_CODE_FINDINGS','NO_LCODES'))
tpl = tpl.replace('{{FAILED_STRATEGIES}}', os.environ.get('FAILED_STRATEGIES','NO_FAILURES'))
with open('/tmp/codex_critic_filled.md', 'w') as f: f.write(tpl)
"

# ─── Block F (2026-04-19): Verdict 캐시 — 동일 가설 재토론 시 재호출 skip ──
# hash(SCOUT_PLAN + L_CODE_FINDINGS + FAILED_STRATEGIES)을 키로 캐시 조회.
# 가설 내용이 REVISE 재제출로 변경되면 hash 미스 → 새로 호출. Axiom active 폴더가
# 변경된 경우도 hash 포함하여 axiom 변경 시 캐시 무효화.
CACHE_DIR="$DIR/.cache/codex_verdicts"
mkdir -p "$CACHE_DIR" 2>/dev/null
AXIOM_SIG=""
if [ -d "$DIR/qepm/memory/axioms/active" ]; then
  AXIOM_SIG=$(find "$DIR/qepm/memory/axioms/active" -name 'AX-*.json' -printf '%T@ %p\n' 2>/dev/null | sort | sha256sum | cut -c1-12)
fi
CACHE_KEY=$(printf '%s\n%s\n%s\n%s' "$SCOUT_PLAN" "$L_CODE_FINDINGS" "$FAILED_STRATEGIES" "$AXIOM_SIG" | sha256sum | cut -c1-16)
CACHE_FILE="$CACHE_DIR/${CACHE_KEY}.json"

if [ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ] && [ "${QVEST_CODEX_CACHE_SKIP:-0}" != "1" ]; then
  echo "[Codex Critic] CACHE HIT ($CACHE_KEY) → re-using cached verdict" >&2
  cp "$CACHE_FILE" "$OUTPUT"
  # 요약만 stdout (캐시 hit 표시 포함)
  if command -v jq >/dev/null 2>&1; then
    jq -c '. + {cached: true, cache_key: "'"$CACHE_KEY"'"}' "$OUTPUT" 2>/dev/null || cat "$OUTPUT"
  else
    cat "$OUTPUT"
  fi
  exit 0
fi

echo "[Codex Critic] CACHE MISS ($CACHE_KEY) → calling GPT-5.5 via codex-companion..." >&2

# Codex CLI 직접 호출 (GPT-5.5)
node "$COMPANION" task --wait --effort xhigh "$(cat /tmp/codex_critic_filled.md)" > "$OUTPUT" 2>/tmp/codex_critic_stderr.log

# 성공 시 캐시 저장
if [ $? -eq 0 ] && [ -s "$OUTPUT" ]; then
  cp "$OUTPUT" "$CACHE_FILE" 2>/dev/null
fi

# ─── 토큰 절감 (Block C v1.1, v55 strict 2026-04-19): stdout에는 요약만 ─
# 전체 JSON은 /tmp/codex_critic_result.json 감사용 보존. Claude는 요약만 수신.
# 실패 시에도 stderr는 /tmp/에만 (Claude context 오염 방지)
if [ $? -eq 0 ] && [ -s "$OUTPUT" ]; then
  echo "[Codex Critic] Success. Full JSON: $OUTPUT (not piped to Claude)" >&2
  # v55 필수 필드: role, stance, veto_flag(=null for codex), critical_concerns, supporting_arguments, s1_gate_items, kill_scenarios
  if command -v jq >/dev/null 2>&1; then
    jq -c '{role: (.role // "codex_critic"),
            stance: (.stance // null),
            veto_flag: (.veto_flag // null),
            critical_concerns: ((.critical_concerns // [])[:3]),
            supporting_arguments: ((.supporting_arguments // [])[:2]),
            s1_gate_items: ((.s1_gate_items // [])[:3]),
            kill_scenarios: ((.kill_scenarios // [])[:2]),
            weakest_assumption: (.weakest_assumption // ""),
            result_file: "'"$OUTPUT"'"}' "$OUTPUT" 2>/dev/null \
      || cat "$OUTPUT"   # jq 실패 시 fallback
  else
    cat "$OUTPUT"   # jq 미설치 시 fallback
  fi
else
  echo "[Codex Critic] FAILED. stderr→/tmp/codex_critic_stderr.log (not piped)" >&2
  echo '{"error": "codex_critic_failed", "fallback": true, "stderr_file": "/tmp/codex_critic_stderr.log"}' > "$OUTPUT"
  cat "$OUTPUT"
  exit 1
fi
