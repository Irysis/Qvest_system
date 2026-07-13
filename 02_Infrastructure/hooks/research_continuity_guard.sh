#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
#==============================================================================
# research_continuity_guard.sh — Stop hook (리서치 연속성 가드, warn-level)
# 도훈 mandate 2026-07-13: "자꾸 리서치를 중도 포기하는 문제" — Q-Lead 턴 마감 편향의
#   결정론적 백스톱. 4차례 메모리 강화로도 24h 내 재발 → 기계 층 추가.
# 발화 조건 (둘 다 warn — 컨텍스트 주입, 차단 아님. 2주 관찰 후 block 승격 검토):
#   W1) 종결 어휘(소진/폐쇄/종결/중단 판정형)가 있는데 다음-단계 마커가 전무
#   W2) 턴 마감이 대기-자세(대기/기다림/결정 주시면)인데 frontier 큐 in_progress가 0
# 안전: 어떤 오류든 '{}'(통과). stop_hook_active면 통과(무한루프 회피).
#==============================================================================
set -uo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("hook_event_name",""))' 2>/dev/null || echo "")
if [ "$EVENT" != "Stop" ]; then echo '{}'; exit 0; fi
ACTIVE=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("stop_hook_active",False))' 2>/dev/null || echo "False")
if [ "$ACTIVE" = "True" ]; then echo '{}'; exit 0; fi
TP=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("transcript_path",""))' 2>/dev/null || echo "")
if [ -z "$TP" ] || [ ! -f "$TP" ]; then echo '{}'; exit 0; fi

"$QVEST_PY_BIN" - "$TP" <<'PY' 2>/dev/null || echo '{}'
import json, sys, re, os

tp = sys.argv[1]
lines = []
with open(tp, 'r', encoding='utf-8', errors='replace') as f:
    for ln in f:
        ln = ln.strip()
        if not ln: continue
        try: lines.append(json.loads(ln))
        except Exception: pass

def is_user_prompt(m):
    if m.get('type') != 'user': return False
    c = m.get('message', {}).get('content')
    if isinstance(c, str): return True
    if isinstance(c, list):
        return any(isinstance(b, dict) and b.get('type') == 'text' for b in c)
    return False

start = 0
for i, m in enumerate(lines):
    if is_user_prompt(m): start = i

atext = []
for m in lines[start:]:
    if m.get('type') == 'assistant':
        c = m.get('message', {}).get('content', [])
        if isinstance(c, list):
            for b in c:
                if isinstance(b, dict) and b.get('type') == 'text':
                    atext.append(b.get('text', ''))

full = ' '.join(atext)
tail = full[-400:] if len(full) > 400 else full
if not full.strip():
    print('{}'); sys.exit(0)

# W1: 판정형 종결 어휘 (과거 인용 "R5 계열 폐쇄" 오탐을 줄이기 위해 선언형 패턴만)
terminal = re.search(r'(소진\s*판정|계열\s*소진|축\s*소진(?!\s*지대)|폐쇄\s*판정|종결\s*판정|종결합니다|중단합니다|재시도\s*가치\s*없|더\s*이상\s*경로가\s*없)', full)
nextstep = re.search(r'(next_probe|다음\s*(반복|가설|사이클|라운드|스텝)|후속|착수|스폰|프론티어|재도전|frontier|armed)', full)

# W2: 대기-자세 마감
waitclose = re.search(r'(대기\s*중입니다|대기하겠|기다리겠습니다|결정(을|만)?\s*주시면|승인하시면|말씀\s*주시면)\s*[^가-힣]*$', tail.strip()) or \
            re.search(r'(대기\s*중입니다|결정\s*대기)\W*$', tail.strip())

msgs = []
if terminal and not nextstep:
    msgs.append("[research_continuity_guard] 종결 판정 어휘가 있는데 다음-단계(next_probe/후속/착수) 마커가 없습니다. "
                "도훈 mandate: negative는 config-scoped + 프론티어 표시로만, 기전 진단에서 다음 가설 ≥2 도출이 보고 완성 요건.")

# W3 (2026-07-13 도훈 "제도화 강제력" 지적): 라운드 수집(신규 L-code) 후 계층 병목 지도 미갱신 감지 —
# 최근 6h 내 emit된 L-code가 layer_bottleneck_map.md보다 새로우면 경고 (mtime 결정론 검증).
try:
    import glob, time as _t
    root2 = os.environ.get('CLAUDE_PROJECT_DIR') or os.environ.get('QM_ROOT') or 'C:/Users/99922/OneDrive/Quant_Module_Moltbot'
    lc_files = glob.glob(os.path.join(root2, 'stage_artifacts', 'l_code', '*', '*.json'))
    if lc_files:
        newest_lc = max(os.path.getmtime(f) for f in lc_files)
        map_p = os.path.join(root2, '06_Registry', 'layer_bottleneck_map.md')
        map_mt = os.path.getmtime(map_p) if os.path.exists(map_p) else 0
        if (_t.time() - newest_lc) < 6 * 3600 and newest_lc > map_mt:
            msgs.append("[research_continuity_guard] 최근 6시간 내 L-code가 적립됐는데 계층 병목 지도"
                        "(06_Registry/layer_bottleneck_map.md)가 그보다 오래됐습니다 — 라운드 수집 시 지도 갱신 의무"
                        "(answer-principles 연속성 5호). 해당 계층 행·갭 귀속을 갱신하세요.")
except Exception:
    pass
if waitclose:
    # frontier 큐 in_progress 확인 — 진행 중 리서치가 있으면 대기 마감도 정당
    n_prog = -1
    try:
        root = os.environ.get('CLAUDE_PROJECT_DIR') or os.environ.get('QM_ROOT') or 'C:/Users/99922/OneDrive/Quant_Module_Moltbot'
        q = json.load(open(os.path.join(root, '06_Registry', 'alpha_frontier_queue.json'), encoding='utf-8'))
        n_prog = sum(1 for e in q.get('entries', []) if 'in_progress' in str(e.get('status', '')))
    except Exception:
        pass
    if n_prog == 0:
        msgs.append("[research_continuity_guard] 턴이 대기-자세로 끝났고 frontier 큐 in_progress가 0입니다. "
                    "도훈 mandate: '리서치는 누가 멈추라고 했지' — 결정-대기 항목이 있어도 envelope-안 사이클을 뽑아 병행 가동하세요.")

if msgs:
    print(' | '.join(msgs))
else:
    print('{}')
PY
