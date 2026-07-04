#!/usr/bin/env bash
#==============================================================================
# axiom_context_inject.sh — PreToolUse[Agent] AX 공리 컨텍스트 주입 (v8.0 WS5-3)
#   unified_agent_guard.sh(v52 legacy)의 axiom 주입 로직을 dedicated hook으로 분리.
#   legacy Stage Guard(S0~S5/STR_XXX)는 현 v6.4 WT 흐름 no-op → 폐기, 주입만 보존.
#   경량(WS5-4): AX 코드 + statement 75자 + 전문 pointer.
#==============================================================================
trap 'echo "{}"; exit 0' ERR
# (v8.1.2 2026-06-11) python stdio/open UTF-8 강제 — cache body가 cp949로 쓰이고 additionalContext에
# lone surrogate(\udcXX) 주입돼 Agent spawn 세션 전체가 API 400 나던 사건 수리.
export PYTHONUTF8=1
# (v8.2.1 HOOK-P0-1) bare python3 = Windows Store 스텁 → 주입 전체 무발화. 공용 해석기 사용.
QVEST_PARSE_RESOLVE_ONLY=1; source "$(dirname "${BASH_SOURCE[0]:-$0}")/_shared_parse.sh"; unset QVEST_PARSE_RESOLVE_ONLY
INPUT=$(cat)
# CLAUDE_PROJECT_DIR(native Windows 경로) 우선 — MSYS형(/c/...) 경로를 native python glob에 넘기면 0건 매치로
# regen 실패 → ERR trap {} 무출력이던 버그 수정 (2026-06-10). 백슬래시도 슬래시로 정규화.
DIR="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-}}"
DIR="${DIR//\\//}"
if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
  DIR=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")
fi
AGENT_NAME=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
try:
    d=json.loads(sys.stdin.buffer.read().decode("utf-8","replace")); ti=d.get("tool_input",{})
    print(ti.get("subagent_type","") or ti.get("description",""))
except Exception: print("")' 2>/dev/null || echo "")
AGENT_NAME_LC=$(printf '%s' "$AGENT_NAME" | tr "[:upper:]" "[:lower:]")

ACTIVE_DIR="$DIR/qepm/memory/axioms/active"
CACHE_BODY="$DIR/.cache/axiom_inject_body.md"

# regen body if missing or active AX newer than cache
shopt -s globstar 2>/dev/null  # mode-local(active/modes/**) 포함
NEWEST=$(ls -t "$ACTIVE_DIR"/**/AX-*.json "$ACTIVE_DIR"/AX-*.json 2>/dev/null | head -1)
if [ -n "$NEWEST" ] && { [ ! -f "$CACHE_BODY" ] || [ "$NEWEST" -nt "$CACHE_BODY" ]; }; then
  "$QVEST_PY_BIN" -c "
import json, os, glob
lines = []
_files = set(glob.glob(os.path.join('$ACTIVE_DIR', '**', 'AX-*.json'), recursive=True)) | set(glob.glob(os.path.join('$ACTIVE_DIR', 'AX-*.json')))
for f in sorted(_files):
    try:
        ax = json.load(open(f, encoding='utf-8'))
        axid = ax.get('axiom_id') or ax.get('id') or os.path.basename(f)[:-5]
        stmt = (ax.get('statement') or ax.get('text') or ax.get('name') or '')[:75]
        tt = ax.get('type') or ax.get('grade') or 'IMMUTABLE'
        tp = ax.get('polarity') or ('axiom' if ax.get('grade')=='IMMUTABLE' else '?')
        lines.append(f'  - {axid} [{tt}/{tp}]: {stmt}')
    except Exception: pass
lines.append(f'  → 전문: .claude/rules/axioms.md / active/ (+ modes/, total {len(_files)})')
open('$CACHE_BODY', 'w', encoding='utf-8').write(chr(10).join(lines))
" 2>/dev/null
fi

[ -s "$CACHE_BODY" ] || { echo '{}'; exit 0; }

case "$AGENT_NAME_LC" in
  *forge*)    HEADER='[AX 전제 — Forge] AX 범위 내 실험이면 AX 인용 + 경계 조건 명시.' ;;
  *judge*)    HEADER='[AX 전제 — Judge] AX 범위인데 반대 결과면 결과가 아닌 실험을 먼저 의심 (auditor).' ;;
  *governor*) HEADER='[AX 전제 — Governor] AX covered 전략은 core 배정 confidence 상승.' ;;
  *)          HEADER='[AX 전제] 아래 공리는 qvest 모든 행위의 대전제.' ;;
esac

# (A6 2026-07-04, 감사 SC-02) 확립 전략 진실(strategic_truths.md) 추가 주입.
#   합산 상한 2500자 — 초과 시 truths 우선 보존 + axiom 요약 라인 단위 축약.
#   파일 부재/공백 시 기존 axiom-only 주입과 동일 (회귀 없음).
# (v2 2026-07-04 엔진 재설계) ②Distilled negative/conditional top-K 추가 주입.
#   우선순위: truths > distilled > axiom body(축약 대상). 합산 상한 2500자 불변.
#   소비 대상 = status=distilled(statement_refined 존재)만 — INV-6: pending_5axis
#   초안 텍스트 주입 금지. 인덱스 부재/정제 0건 시 기존 주입과 동일 (회귀 없음).
TRUTHS_FILE="$DIR/02_Infrastructure/prompts/strategic_truths.md"
DIST_INDEX="$DIR/06_Registry/distilled_knowledge.json"
ESC=$(printf '%s' "$HEADER" | CB="$CACHE_BODY" TF="$TRUTHS_FILE" DI="$DIST_INDEX" "$QVEST_PY_BIN" -c "
import json, os, sys
def rd(p):
    try:
        return open(p, encoding='utf-8', errors='replace').read().strip()
    except Exception:
        return ''
hdr = sys.stdin.buffer.read().decode('utf-8', 'replace')
body = rd(os.environ.get('CB', ''))
truths = rd(os.environ.get('TF', ''))
# truths 파일 안의 DISTILLED generated 블록은 여기서 별도 주입하므로 제거 (이중 주입 방지)
if truths and '<!-- DISTILLED_START' in truths:
    pre, _, rest = truths.partition('<!-- DISTILLED_START')
    _, _, post = rest.partition('<!-- DISTILLED_END -->')
    truths = (pre.rstrip() + post).strip()
# ②Distilled negative/conditional top-K (K=5, 정제 완료분만 — INV-6)
dist = ''
try:
    di = json.load(open(os.environ.get('DI', ''), encoding='utf-8'))
    picks = [e for e in di.get('entries', [])
             if e.get('status') == 'distilled'
             and e.get('polarity') in ('negative', 'conditional')
             and (e.get('statement_refined') or '').strip()]
    picks.sort(key=lambda e: e.get('refined_at') or '', reverse=True)
    lines = []
    for e in picks[:5]:
        tag = '재시도금지(INV-7조건부)' if e.get('polarity') == 'negative' else '조건부'
        lines.append(f\"  - {e.get('dist_id')} [{tag}]: {(e.get('statement_refined') or '')[:110]}\")
    if lines:
        dist = '[Distilled 실패원장 — 가설 착수 전 대조 의무]' + chr(10) + chr(10).join(lines)
        if len(dist) > 700:
            dist = dist[:700] + '…'
except Exception:
    dist = ''
MAX = 2500
tail = ((chr(10)*2) + truths if truths else '') + ((chr(10)*2) + dist if dist else '')
if len(hdr) + len(body) + len(tail) + 4 > MAX:
    budget = max(0, MAX - len(hdr) - len(tail) - 60)
    kept, used = [], 0
    for ln in body.splitlines():
        if used + len(ln) + 1 > budget:
            break
        kept.append(ln); used += len(ln) + 1
    body = chr(10).join(kept) + chr(10) + '  → (축약) 전문: .claude/rules/axioms.md'
ctx = (hdr + chr(10) + body + tail)[:MAX]
ctx = ''.join(ch if not (0xD800 <= ord(ch) <= 0xDFFF) else '?' for ch in ctx)
print(json.dumps(ctx))
")
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":$ESC}}"
exit 0
