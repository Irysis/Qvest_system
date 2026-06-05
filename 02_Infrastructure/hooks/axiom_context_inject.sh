#!/usr/bin/env bash
#==============================================================================
# axiom_context_inject.sh — PreToolUse[Agent] AX 공리 컨텍스트 주입 (v8.0 WS5-3)
#   unified_agent_guard.sh(v52 legacy)의 axiom 주입 로직을 dedicated hook으로 분리.
#   legacy Stage Guard(S0~S5/STR_XXX)는 현 v6.4 WT 흐름 no-op → 폐기, 주입만 보존.
#   경량(WS5-4): AX 코드 + statement 75자 + 전문 pointer.
#==============================================================================
trap 'echo "{}"; exit 0' ERR
INPUT=$(cat)
DIR=$(ls -d /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")
AGENT_NAME=$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); ti=d.get("tool_input",{})
    print(ti.get("subagent_type","") or ti.get("description",""))
except Exception: print("")' 2>/dev/null || echo "")
AGENT_NAME_LC=$(printf '%s' "$AGENT_NAME" | tr "[:upper:]" "[:lower:]")

ACTIVE_DIR="$DIR/qepm/memory/axioms/active"
CACHE_BODY="$DIR/.cache/axiom_inject_body.md"

# regen body if missing or active AX newer than cache
shopt -s globstar 2>/dev/null  # mode-local(active/modes/**) 포함
NEWEST=$(ls -t "$ACTIVE_DIR"/**/AX-*.json "$ACTIVE_DIR"/AX-*.json 2>/dev/null | head -1)
if [ -n "$NEWEST" ] && { [ ! -f "$CACHE_BODY" ] || [ "$NEWEST" -nt "$CACHE_BODY" ]; }; then
  python3 -c "
import json, os, glob
lines = []
_files = set(glob.glob(os.path.join('$ACTIVE_DIR', '**', 'AX-*.json'), recursive=True)) | set(glob.glob(os.path.join('$ACTIVE_DIR', 'AX-*.json')))
for f in sorted(_files):
    try:
        ax = json.load(open(f))
        axid = ax.get('axiom_id') or ax.get('id') or os.path.basename(f)[:-5]
        stmt = (ax.get('statement') or ax.get('text') or ax.get('name') or '')[:75]
        tt = ax.get('type') or ax.get('grade') or 'IMMUTABLE'
        tp = ax.get('polarity') or ('axiom' if ax.get('grade')=='IMMUTABLE' else '?')
        lines.append(f'  - {axid} [{tt}/{tp}]: {stmt}')
    except Exception: pass
lines.append(f'  → 전문: .claude/rules/axioms.md / active/ (+ modes/, total {len(_files)})')
open('$CACHE_BODY', 'w').write(chr(10).join(lines))
" 2>/dev/null
fi

[ -s "$CACHE_BODY" ] || { echo '{}'; exit 0; }

case "$AGENT_NAME_LC" in
  *forge*)    HEADER='[AX 전제 — Forge] AX 범위 내 실험이면 AX 인용 + 경계 조건 명시.' ;;
  *judge*)    HEADER='[AX 전제 — Judge] AX 범위인데 반대 결과면 결과가 아닌 실험을 먼저 의심 (auditor).' ;;
  *governor*) HEADER='[AX 전제 — Governor] AX covered 전략은 core 배정 confidence 상승.' ;;
  *)          HEADER='[AX 전제] 아래 공리는 qvest 모든 행위의 대전제.' ;;
esac

CTX="$HEADER
$(cat "$CACHE_BODY")"
ESC=$(printf '%s' "$CTX" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":$ESC}}"
exit 0
