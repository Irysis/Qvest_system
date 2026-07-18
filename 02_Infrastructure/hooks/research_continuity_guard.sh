#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
#==============================================================================
# research_continuity_guard.sh — Stop hook (Continuity Firewall: 포기 원천차단)
#
# 도훈 mandate 2026-07-15: "자체적으로 포기하지 않는 자가발전형 아키텍처. 누적 실패 후
#   '끝남 표현들'로 라운드를 마무리하려는 것을 원천차단."
#   → warn-only(2026-07-13)에서 BLOCK으로 승격. settings.json _doc이 예고한 "2주 관찰 후
#     block 승격"의 집행 + 도훈 명시 mandate.
#
# 아키텍처(4레이어 — SOT 02_Infrastructure/docs/rules/continuity-firewall.md):
#   L1 차단 이빨: 이 훅이 continuity_gate.py 판정을 받아 {"decision":"block"} 발행 →
#                 종결 턴을 되돌려 강제 속행(사후 넛지가 아니라 현재 턴 개입).
#   L2 독립 semantic 판정: continuity_gate.py = 케이스 결정론 + verdict-close 일반화(신어
#                 커버) + 선택적 Haiku(QVEST_CONTINUITY_LLM=1). 편향 당사자 self-certify 차단.
#   L3 건설적 종료계약: 종결 프레이밍 감지 시 next_probe≥2 (+negative면 live_trigger) 요구.
#                 close_round()가 이 계약을 인자로 강제(paved path) → 마커로 게이트 자동 통과.
#   L4 자가발전: 06_Registry/continuity_cases.json 성장(잡을수록 강해짐). 차단 이력은
#                 .cache/continuity_blocks.jsonl 감사 → 주간 /cleaner가 신규 우회를 케이스로 승격.
#
# 무한루프 방지: continuity_gate.py 내부 per-turn cap(기본 3) + stop_hook_active + ERR trap.
# 안전: 어떤 오류든 '{}'(통과)로 빠져 내 턴을 깨지 않음(fail-open — 포기억제가 목적이지
#       작업차단이 아님).
#==============================================================================
set -uo pipefail
trap 'echo "{}"; exit 0' ERR

DIR="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}}"
GATE="$DIR/02_Infrastructure/axiom/continuity_gate.py"

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("hook_event_name",""))' 2>/dev/null || echo "")
if [ "$EVENT" != "Stop" ]; then echo '{}'; exit 0; fi
TP=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("transcript_path",""))' 2>/dev/null || echo "")
if [ -z "$TP" ] || [ ! -f "$TP" ]; then echo '{}'; exit 0; fi

# ── L1~L3: continuity_gate 판정 (block JSON 또는 '{}') ────────────────────────
GATE_OUT='{}'
if [ -f "$GATE" ]; then
  GATE_OUT=$(CLAUDE_PROJECT_DIR="$DIR" PYTHONUTF8=1 "$QVEST_PY_BIN" "$GATE" --transcript "$TP" 2>>/tmp/continuity_gate.stderr.log || echo '{}')
  [ -n "$GATE_OUT" ] || GATE_OUT='{}'
fi

# block 발행 시 그대로 전달(이빨). 차단 이력 감사는 gate 내부(_log_block)가 확장 스키마
# ({ts,tp,categories,verdict_tokens,matched_terms,reason,span_hash})로 continuity_blocks.jsonl에
# 직접 기록 — 여기서 {ts,tp} 중복 append 하지 않음(C4 정합). pass 분모는 gate가
# .cache/continuity_gate_counters/passes_YYYYMMDD.json 일자 카운트로 확보.
if printf '%s' "$GATE_OUT" | grep -q '"decision"'; then
  printf '%s\n' "$GATE_OUT"
  exit 0
fi

# ── W3(유지): 라운드 수집(신규 L-code) 후 계층 병목 지도 미갱신 warn ──────────
# gate가 pass일 때만. block과 달리 순수 컨텍스트 넛지.
ACTIVE=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("stop_hook_active",False))' 2>/dev/null || echo "False")
if [ "$ACTIVE" = "True" ]; then echo '{}'; exit 0; fi

"$QVEST_PY_BIN" - "$DIR" <<'PY' 2>/dev/null || echo '{}'
import os, sys, glob, time, json
root = sys.argv[1]
msgs = []
try:
    lc_files = glob.glob(os.path.join(root, 'stage_artifacts', 'l_code', '*', '*.json'))
    if lc_files:
        newest_lc = max(os.path.getmtime(f) for f in lc_files)
        map_p = os.path.join(root, '06_Registry', 'layer_bottleneck_map.md')
        map_mt = os.path.getmtime(map_p) if os.path.exists(map_p) else 0
        if (time.time() - newest_lc) < 6 * 3600 and newest_lc > map_mt:
            msgs.append("[research_continuity_guard/W3] 최근 6시간 내 L-code가 적립됐는데 계층 병목 지도"
                        "(06_Registry/layer_bottleneck_map.md)가 그보다 오래됐습니다 — 라운드 수집 시 지도 갱신 의무"
                        "(answer-principles 연속성 5호). 해당 계층 행·갭 귀속을 갱신하세요.")
except Exception:
    pass
print(' | '.join(msgs) if msgs else '{}')
PY
