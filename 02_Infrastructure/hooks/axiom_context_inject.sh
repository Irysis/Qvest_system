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
#   우선순위: 고정 제약-축 > truths > distilled > axiom body(축약 대상). 합산 상한 2500자 불변.
#   소비 대상 = status=distilled(statement_refined 존재)만 — INV-6: pending_5axis
#   초안 텍스트 주입 금지. 인덱스 부재/정제 0건 시 기존 주입과 동일 (회귀 없음).
# (E+F 2026-07-04 실패지식) 고정 제약 7종 문제-축 블록 무조건 주입(제약 완화=레버 금지, AX-000) +
#   distilled negative 톤을 '실패' → '탐색됨+프론티어(봉투 안 차별점 시 진행)' 지도-프레임으로 전환.
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
# (E+F 2026-07-04) 고정 제약 7종 = 불가침 문제-축 블록. 제약 완화는 레버 아님(AX-000).
axis = ('[문제의 고정 축 — 변수 아님, 이 안에서 풀 것]' + chr(10) +
        '  long-only(w>=0)·<=25종·K200∪KQ150·15bps(v2.4 delta)·[0,0.20]·Σw=1 + PIT C1~C15.' + chr(10) +
        '  이건 배포 현실이 정의한 문제의 고정 축이다. \"long-only라서/25종이라서 실패\"식 제약-귀속 금지.' + chr(10) +
        '  봉투 안 레버만 프론티어: overlay·잔차sleeve·비-return 데이터·DPL·regime-conditional·multi-sleeve·composite·ML sizing.')
# ②Distilled negative/conditional top-K (K=5, 정제 완료분만 — INV-6)
#   (E+F 2026-07-04) '이건 실패' 톤 → '탐색됨 + 봉투 안 프론티어' 지도-프레임 톤.
dist = ''
dist_min = ''
try:
    di = json.load(open(os.environ.get('DI', ''), encoding='utf-8'))
    picks = [e for e in di.get('entries', [])
             if e.get('status') == 'distilled'
             and e.get('polarity') in ('negative', 'conditional')
             and (e.get('statement_refined') or '').strip()]
    picks.sort(key=lambda e: e.get('refined_at') or '', reverse=True)
    lines = []
    for e in picks[:5]:
        tag = '탐색됨→프론티어(INV-7 봉투 안 차별점 시 진행)' if e.get('polarity') == 'negative' else '조건부'
        lines.append(f\"  - {e.get('dist_id')} [{tag}]: {(e.get('statement_refined') or '')[:110]}\")
    if lines:
        _dhdr = '[Distilled 탐색지도 — 가설 착수 전 대조: 판결 아닌 방향(프론티어) 표시]'
        dist = _dhdr + chr(10) + chr(10).join(lines)
        if len(dist) > 700:
            dist = dist[:700] + '…'
        # (P1 2026-07-04 감사 잔여 finding) 실패지식 예산 바닥: 최상위 1건은 예산 압박 시에도
        #   소비면에 남긴다. dist 나머지(2~5)는 기존대로 truths에 양보하되, top-1은 truths보다 늦게 버림.
        dist_min = _dhdr + chr(10) + lines[0]
        if len(dist_min) > 260:
            dist_min = dist_min[:260] + '…'
except Exception:
    dist = ''
    dist_min = ''
MAX = 2500
# (P0#4 2026-07-04 감사) 절단불가 코어 보호. 우선순위:
#   [hdr + 제약 문제-축(axis) + 코어 공리(active Law AX-000/001/002/008)] = 불변  (구 negative AX-003/004/005/007은 2026-07-05 Distilled 강등 — active 아님)
#   > distilled top-K(감축 대상) > truths > positive/method 공리 body(축약 대상).
# 기존 버그: body 전체를 균일 라인절단 → 성실히 채운 negative 코어 공리가 tail에 밀려 조용히 소실.
# 코어 라인 식별 = 렌더된 body 라인의 자기라벨('/negative]') 또는 코어 ID(AX-000/002/008).
import re as _re
def _is_core(ln):
    if '/negative]' in ln:            # distilled negative가 body에 오면 절단불가
        return True
    # (2026-07-05) 모든 active 공리 라인 = core. AX-003/004/005/007 Distilled 강등 후
    #   active Law는 AX-000/001/002/008 4건뿐 — 전부 절단불가(구 AX-00[028]은 AX-001 IMMUTABLE 누락 버그).
    return bool(_re.match(r'\s*-\s*AX-\d', ln))
_body_lines = body.splitlines()
_core_lines = [ln for ln in _body_lines if _is_core(ln)]
_soft_lines = [ln for ln in _body_lines if not _is_core(ln)]
core_block = chr(10).join(_core_lines)
# 코어 공리 + 제약축은 항상 산다. dist/truths/soft body는 남는 예산 안에서만.
# fixed = 절대 감축 불가(hdr + axis + core). axis는 tail의 첫 요소.
fixed_len = len(hdr) + 1 + len(core_block) + (len(chr(10)*2) + len(axis))
def _assemble(soft_lines, dist_s, truths_s):
    parts = [hdr]
    b = core_block
    if soft_lines:
        b = b + chr(10) + chr(10).join(soft_lines) if b else chr(10).join(soft_lines)
    t = (chr(10)*2) + axis
    if truths_s:
        t += (chr(10)*2) + truths_s
    if dist_s:
        t += (chr(10)*2) + dist_s
    return parts[0] + chr(10) + b + t
full = _assemble(_soft_lines, dist, truths)
if len(full) + 4 > MAX:
    # 1단계: soft body 라인을 예산 내로 절단 (코어/axis/dist/truths는 아직 유지)
    reserve = len(chr(10)*2) + len(axis) + \
              (len(chr(10)*2) + len(truths) if truths else 0) + \
              (len(chr(10)*2) + len(dist) if dist else 0)
    budget = max(0, MAX - fixed_len - reserve - 60)
    kept, used = [], 0
    for ln in _soft_lines:
        if used + len(ln) + 1 > budget:
            break
        kept.append(ln); used += len(ln) + 1
    if len(kept) < len(_soft_lines):
        kept.append('  → (축약) 전문: .claude/rules/axioms.md')
    _dist2, _truths2 = dist, truths
    cand = _assemble(kept, _dist2, _truths2)
    # 2단계: 초과 시 실패지식(distilled)에 예산 바닥(reserved floor) 부여.
    #   2a) dist를 top-1(dist_min)로 축소 (나머지 2~5건은 truths에 양보)
    #   2b) 그래도 초과면 truths 감축
    #   2c) 그래도 초과면 dist_min까지 포기 (최후)
    #   → 최상위 실패지식 탐색지도 1건은 truths보다 늦게 버려져 소비면 도달 보장.
    if len(cand) + 4 > MAX and _dist2 and dist_min and _dist2 != dist_min:
        _dist2 = dist_min
        cand = _assemble(kept, _dist2, _truths2)
    if len(cand) + 4 > MAX and _truths2:
        _truths2 = ''
        cand = _assemble(kept, _dist2, _truths2)
    if len(cand) + 4 > MAX and _dist2:
        _dist2 = ''
        cand = _assemble(kept, _dist2, _truths2)
    # 3단계: 극단(코어+axis만으로 초과) — 코어는 절대 자르지 않고 hard cap만 적용(코어 우선 보존).
    full = cand
ctx = full[:MAX]
ctx = ''.join(ch if not (0xD800 <= ord(ch) <= 0xDFFF) else '?' for ch in ctx)
print(json.dumps(ctx))
")
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":$ESC}}"
exit 0
