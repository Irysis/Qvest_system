#!/usr/bin/env bash
# count_prompt_tokens.sh — Qvest 프롬프트 계층 토큰 계산
# 근사치: 4 chars ≈ 1 token (영어 기준), 한글은 2~3 chars ≈ 1 token
# 사용: bash 02_Infrastructure/ops/count_prompt_tokens.sh [--json]
set -uo pipefail

ROOT="$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")"
cd "$ROOT" || exit 1

JSON_OUT=0
[[ "${1:-}" == "--json" ]] && JSON_OUT=1

declare -a FILES=(
  "CLAUDE.md"
  "02_Infrastructure/prompts/_shared_prefix.md"
  "02_Infrastructure/prompts/qlead_init.md"
  "02_Infrastructure/prompts/scout_init.md"
  "02_Infrastructure/prompts/forge_init.md"
  "02_Infrastructure/prompts/judge_init.md"
  "02_Infrastructure/prompts/governor_init.md"
  "02_Infrastructure/prompts/risk_manager_init.md"
  "02_Infrastructure/prompts/codex_critic_prompt.md"
  "02_Infrastructure/prompts/codex_s5_review_prompt.md"
  "02_Infrastructure/prompts/pit_intent_scan_prompt.md"
  ".claude/commands/qvest.md"
)

TOTAL_CHARS=0
TOTAL_LINES=0
declare -a ROWS=()

for f in "${FILES[@]}"; do
  if [[ -f "$f" ]]; then
    chars=$(wc -c < "$f" | tr -d ' ')
    lines=$(wc -l < "$f" | tr -d ' ')
    # 한글 비율 고려 3 chars/token 가정 → 보수적
    tokens=$(( chars / 3 ))
    TOTAL_CHARS=$(( TOTAL_CHARS + chars ))
    TOTAL_LINES=$(( TOTAL_LINES + lines ))
    ROWS+=("$f|$lines|$chars|$tokens")
  else
    ROWS+=("$f|MISSING|0|0")
  fi
done

TOTAL_TOKENS=$(( TOTAL_CHARS / 3 ))

if [[ $JSON_OUT -eq 1 ]]; then
  printf '{"total_lines":%d,"total_chars":%d,"total_tokens_approx":%d,"files":[' "$TOTAL_LINES" "$TOTAL_CHARS" "$TOTAL_TOKENS"
  first=1
  for row in "${ROWS[@]}"; do
    IFS='|' read -r path lines chars tokens <<< "$row"
    [[ $first -eq 0 ]] && printf ','
    first=0
    printf '{"path":"%s","lines":"%s","chars":%s,"tokens_approx":%s}' "$path" "$lines" "$chars" "$tokens"
  done
  printf ']}\n'
else
  printf "%-60s %8s %10s %10s\n" "FILE" "LINES" "CHARS" "TOKENS~"
  printf "%-60s %8s %10s %10s\n" "----" "-----" "-----" "-------"
  for row in "${ROWS[@]}"; do
    IFS='|' read -r path lines chars tokens <<< "$row"
    printf "%-60s %8s %10s %10s\n" "$path" "$lines" "$chars" "$tokens"
  done
  printf "%-60s %8s %10s %10s\n" "----" "-----" "-----" "-------"
  printf "%-60s %8d %10d %10d\n" "TOTAL" "$TOTAL_LINES" "$TOTAL_CHARS" "$TOTAL_TOKENS"
fi
