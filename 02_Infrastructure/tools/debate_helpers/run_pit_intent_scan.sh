#!/usr/bin/env bash
#==============================================================================
# run_pit_intent_scan.sh — 로컬 Codex CLI(@openai/codex) 기반 PIT Intent Scanner
# v53 Sprint 2 S2.3 (revised: plugin API → local CLI)
#
# 변경 이력:
#   - v1: node codex-companion.mjs (plugin API) — Codex crredit 소비
#   - v2 (현재): 로컬 codex CLI (codex exec) — 이미 codex login 된 상태 사용
#
# 사용법:
#   bash run_pit_intent_scan.sh <strategy_dir> [scan_mode=diff|full]
# 출력: /tmp/pit_intent_result_<STR>.json
#==============================================================================

set -u

STRATEGY_DIR="${1:-}"
SCAN_MODE="${2:-diff}"

if [ -z "$STRATEGY_DIR" ] || [ ! -d "$STRATEGY_DIR" ]; then
  echo '{"verdict":"SKIP","reason":"strategy_dir not provided or not exists"}'
  exit 0
fi

DIR=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
TEMPLATE="$DIR/02_Infrastructure/prompts/pit_intent_scan_prompt.md"
STR_NAME=$(basename "$STRATEGY_DIR" | head -c 50)
OUTPUT="/tmp/pit_intent_result_${STR_NAME}.json"
LAST_MSG="/tmp/pit_intent_last_${STR_NAME}.txt"

# ── 로컬 codex CLI 탐색 ────────────────────────────────────────────────
CODEX_BIN=""
if command -v codex >/dev/null 2>&1; then
  CODEX_BIN=$(command -v codex)
elif [ -x "$HOME/.npm-global/bin/codex" ]; then
  CODEX_BIN="$HOME/.npm-global/bin/codex"
fi

if [ -z "$CODEX_BIN" ] || [ ! -f "$TEMPLATE" ]; then
  cat > "$OUTPUT" << EOF
{"verdict":"SKIP","reason":"codex CLI or template unavailable","codex_bin":"$CODEX_BIN","template_exists":$([ -f "$TEMPLATE" ] && echo true || echo false)}
EOF
  cat "$OUTPUT"
  exit 0
fi

# ── run_all.R 찾기 + code content 구성 (diff | full) ────────────────────
RUN_ALL=$(find "$STRATEGY_DIR" -name "run_all.R" -type f 2>/dev/null | head -1)
if [ -z "$RUN_ALL" ]; then
  echo '{"verdict":"SKIP","reason":"run_all.R not found in strategy_dir"}'
  exit 0
fi

if [ "$SCAN_MODE" = "diff" ]; then
  CODE_CONTENT=$(cd "$DIR" && git diff HEAD~1 -- "$RUN_ALL" 2>/dev/null | head -400)
  if [ -z "$CODE_CONTENT" ]; then
    CODE_CONTENT=$(head -300 "$RUN_ALL")
    SCAN_MODE="full(diff empty)"
  fi
else
  CODE_CONTENT=$(cat "$RUN_ALL")
fi

# ── 프롬프트 치환 (Python으로 안전하게) ────────────────────────────────
PROMPT=$(python3 -c "
import sys
with open('$TEMPLATE') as f: t = f.read()
code = sys.stdin.read()
print(t.replace('{{CODE}}', code).replace('{{STRATEGY_DIR}}', '$STRATEGY_DIR').replace('{{SCAN_MODE}}', '$SCAN_MODE'))
" <<< "$CODE_CONTENT")

echo "$PROMPT" > "/tmp/pit_intent_filled_${STR_NAME}.md"

# ── codex exec 호출 (로컬 CLI, read-only sandbox) ──────────────────────
echo "[pit_intent] Calling local codex ($CODEX_BIN)..." >&2

if "$CODEX_BIN" exec \
    --color never \
    --skip-git-repo-check \
    --cd "$DIR" \
    --output-last-message "$LAST_MSG" \
    -s read-only \
    "$PROMPT" \
    > "/tmp/pit_intent_stdout_${STR_NAME}.log" 2>"/tmp/pit_intent_stderr_${STR_NAME}.log"; then

  if [ -s "$LAST_MSG" ]; then
    # JSON 추출 (응답에 markdown fence 또는 설명 텍스트 섞일 수 있음)
    python3 -c "
import json, re, sys
with open('$LAST_MSG') as f: raw = f.read()
m = re.search(r'\{[\s\S]*\}', raw)
if m:
    try:
        d = json.loads(m.group(0))
        with open('$OUTPUT', 'w') as out: json.dump(d, out, indent=2, ensure_ascii=False)
        print(json.dumps(d, ensure_ascii=False))
    except Exception as e:
        err = {'verdict':'SKIP','reason':'json parse failed: '+str(e),'raw':raw[:300]}
        with open('$OUTPUT', 'w') as out: json.dump(err, out, indent=2, ensure_ascii=False)
        print(json.dumps(err, ensure_ascii=False))
else:
    err = {'verdict':'SKIP','reason':'no json in response','raw':raw[:300]}
    with open('$OUTPUT', 'w') as out: json.dump(err, out, indent=2, ensure_ascii=False)
    print(json.dumps(err, ensure_ascii=False))
"
    exit 0
  fi
fi

# ── fallback ──
cat > "$OUTPUT" << EOF
{"verdict":"SKIP","reason":"codex call failed","stderr":"$(tail -3 /tmp/pit_intent_stderr_${STR_NAME}.log 2>/dev/null | tr '\n' ' ' | head -c 300)"}
EOF
cat "$OUTPUT"
