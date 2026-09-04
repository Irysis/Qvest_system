#!/usr/bin/env bash
#==============================================================================
# rf_lcode_mechanism.sh — 블록 L-code 의 **기전 서술** 1회 (도훈 지시 2026-09-04)
#
# 규칙이 낸 수치 척추 위에 "왜" 한 문단을 얹는다. 수치·등급·next_probe 는 건드리지 않고,
# 병합은 R(rf_lcode_mechanism_lib::lcm_merge)이 한다 — 에이전트는 L-code 파일에 손대지 못한다.
#
# ★도훈 지시: "이번 배치에서 쌓인 교훈들 참고해서 작성" — 재료에 이 전략의 앞선 블록
#   L-code(규칙 요약·앞서 적힌 기전·다음 탐침)를 함께 넣는다. 기전은 블록 하나가 아니라
#   블록 **사이**에서 드러나는 일이 많다(2026-09-04: B1 방어계열 3칸 F ↔ B5 종목별 arm 성공).
#
# 사용: rf_lcode_mechanism.sh <base_id> <block_id>
#==============================================================================
set -uo pipefail
ROOT="${QVEST_RF_ROOT:-${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
CFG="${QVEST_RF_CONFIG:-$ROOT/06_Registry/reinforce_auto_config.json}"
JLOG="$ROOT/.cache/reinforce_auto_log.jsonl"
LOG="$ROOT/.cache/scheduler_logs/lcode_mechanism_$(date +%Y%m%d).log"
WDIR="$ROOT/.cache/rf_lcode_mech"
mkdir -p "$(dirname "$LOG")" "$WDIR"

BID="${1:-}"; BLK="${2:-}"
jl(){ "$PY" -c "
import io,json,sys,time
rec={'ts':time.strftime('%Y-%m-%dT%H:%M:%S%z'),'event':sys.argv[1],'src':'lcode_mechanism'}
for kv in sys.argv[2:]:
    k,_,v=kv.partition('='); rec[k]=v
io.open(r'$JLOG','a',encoding='utf-8').write(json.dumps(rec,ensure_ascii=False)+'\n')
print('[lcode_mech] '+sys.argv[1])" "$@" ; }

[ -n "$BID" ] && [ -n "$BLK" ] || { jl halt_no_args; exit 0; }
EN=$("$PY" -c "
import io,json
try:
    c=json.loads(io.open(r'$CFG','rb').read().decode('utf-8'))
    print('1' if c.get('enabled') and (c.get('lcode_mechanism') or {}).get('enabled') else '0')
except Exception: print('0')" 2>/dev/null)
[ "$EN" = "1" ] || { jl halt_disabled; exit 0; }
command -v claude >/dev/null 2>&1 || { jl halt_no_claude_cli; exit 0; }

MAT="$WDIR/${BID:0:50}_${BLK}.materials.txt"
OUT="$WDIR/${BID:0:50}_${BLK}.mechanism.json"
rm -f "$OUT"
Rscript "$ROOT/02_Infrastructure/ops/rf_lcode_mechanism_lib.R" materials "$BID" "$BLK" "$MAT" >> "$LOG" 2>&1 || {
  jl materials_failed "base_id=$BID" "block=$BLK"; exit 0; }

PROMPT="이 강화 블록의 **기전**을 한 문단으로 써라. 수치는 이미 규칙이 적었다 — 너는 **왜**를 쓴다.

$(cat "$MAT")

## 무엇을 쓰는가
무엇이 켜졌고 무엇이 꺼졌는가. 칸들을 갈라 놓고 보면 무엇이 그 차이를 만들었는가.
- 셀들을 **묶어서** 보라. 같은 계열이 나란히 죽었는가 · 한 축만 살았는가 · 순서가 있는가.
- 위에 준 **앞선 블록의 교훈**과 이어 붙여라. 블록 하나 안에서는 안 보이고 사이에서 보이는
  것이 기전인 경우가 많다(예: 어떤 위험 축이 횡단면에선 죽고 노출 스케일에선 살았다면,
  그건 팩터의 실패가 아니라 **소비 지점**의 문제다).
- 반증 가능하게 써라. \"대체로 좋았다\" 는 기전이 아니다.
- 모르면 모른다고 써라. 세 칸으로 기전을 단정하는 것보다 \"이 블록만으로는 안 갈린다,
  가르려면 무엇이 필요하다\" 가 낫다.

## 쓰지 않는 것
- **등급·합격·졸업·BOOK 관련 주장 금지.** 판정은 계약이 한다(정규식으로 차단된다).
- 수치를 새로 만들지 마라. 위 표에 있는 값만 인용한다.
- 이 블록 셀 코드(${BLK}_n)를 **최소 하나** 인용하라 — 일반론은 기전이 아니다.

## 그리고 — 다음 블록에 무엇을 할 것인가 (도훈 지시 2026-09-04)
진단만으로는 다음 칸이 안 바뀐다. 위 기전에서 **곧바로 따라 나오는 처치**를 적어라.
- 각 항목은 **다음 블록에서 실제로 집행 가능한 형태**여야 한다: 어떤 축을 · 무엇으로 · 왜.
  \"더 잘하자\" 는 처치가 아니다. \"감쇠 강도를 0.3/0.5/0.7 로 스윕해 감쇠량과 신호파괴를
  분리한다\" 는 처치다.
- **무엇을 하지 말지도** 적어라. 벽이 확인된 축에 칸을 또 쓰는 것이 예산의 가장 큰 낭비다.
- 이 격자에서 남은 블록이 무엇인지 보고 적어라(위 표의 블록 순서). 없는 축을 요구하지 마라.
- 근거가 이 블록 밖에 있으면 그렇다고 적어라 — 다음 블록으로 못 가르는 것도 정보다.

## 산출 (이것만)
\`${OUT}\` :
{
  \"mechanism\": \"한 문단(40~1200자). 셀 코드를 인용하며 무엇이 왜 갈렸는지.\",
  \"next_block_actions\": [
     {\"action\": \"다음 블록에서 집행할 처치 1줄\", \"why\": \"위 기전의 어느 대목에서 따라 나오는가\",
      \"expect\": \"이게 맞으면 무엇이 달라지는가(반증 가능하게)\"}
  ],
  \"avoid\": [\"다음 블록에서 쓰지 말 것 + 그 이유(벽이 확인된 축)\"],
  \"prior_lessons_used\": [\"참고한 앞선 블록 id\"],
  \"confidence\": \"high|medium|low\"
}

파일을 쓰고 1줄로 기전 요지만 보고하라."

. "$ROOT/02_Infrastructure/ops/rf_llm_env.sh"
rf_llm_resolve lcode_mechanism "${QVEST_LM_MODEL:-}" "${QVEST_LM_EFFORT:-}"
jl start "base_id=$BID" "block=$BLK" "model=$LLM_MODEL" "effort=$LLM_EFFORT"
timeout 900 claude -p "$PROMPT" \
  --model "$LLM_MODEL" --effort "$LLM_EFFORT" \
  --permission-mode acceptEdits \
  --allowed-tools "Read,Write,Glob,Grep" \
  --disallowed-tools "Bash,Agent,Edit,WebFetch,WebSearch" \
  --add-dir "$WDIR" \
  >> "$LOG" 2>&1
jl agent_done "rc=$?"

# ★병합은 R 이 한다 — 검증(셀 인용·금칙어·길이)을 통과해야만 L-code 에 얹힌다.
#   실패해도 L-code 는 그대로 남는다: 규칙 척추는 기전이 없어도 성립한다.
Rscript "$ROOT/02_Infrastructure/ops/rf_lcode_mechanism_lib.R" merge "$BID" "$BLK" "$OUT" >> "$LOG" 2>&1
jl merge_done "rc=$?" "base_id=$BID" "block=$BLK"
exit 0
