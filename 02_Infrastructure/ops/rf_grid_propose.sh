#!/usr/bin/env bash
#==============================================================================
# rf_grid_propose.sh — 강화 격자의 **팩터 5종을 LLM 이 1회 제안** (도훈 지시 2026-08-30)
#
# ★설계 원칙: **LLM 은 격자를 만들 때 1회만 판단하고, 실행 중에는 없다.**
#   이 세션이 양쪽 실패를 다 보여줬다:
#     · LLM 에 설계 재량을 주면 → 게이트형 프로세스, 16회 중 12회 미측정(문헌 검토가 됨)
#     · 규칙만 쓰면 → 팩터 DB 331종 중 5종을 세션이 임의로 골랐고 최선이라는 근거가 없음
#   해법은 **시간축 분리**다. LLM 출력이 **데이터(격자 JSON)** 가 되므로 검증·수정 가능하고,
#   실행은 전부 규칙이라 무인 안전이 유지된다. 격자가 나빠도 그 논문 20칸이 헛돌 뿐 멈추지 않는다.
#
# 산출: 06_Registry/reinforce_program.json 의 **B1 cells 5개만** 교체(제안 파일 경유).
#   B2/B3/B4 구조·고정 축·실행 계약은 손대지 않는다 — LLM 이 만지는 면을 최소로 한다.
#
# 호출: 새 논문의 충실구현이 끝나 강화가 시작되기 직전(선택). 미실행이어도 기본 격자로 돈다.
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
OUT="$ROOT/.cache/rf_grid_proposal.json"
LOG="$ROOT/.cache/scheduler_logs/grid_propose_$(date +%Y%m%d).log"
JLOG="$ROOT/.cache/reinforce_auto_log.jsonl"
mkdir -p "$(dirname "$LOG")"
jl(){ "$PY" -c "
import io,json,sys,time
rec={'ts':time.strftime('%Y-%m-%dT%H:%M:%S%z'),'event':sys.argv[1],'src':'grid_propose'}
for kv in sys.argv[2:]:
    k,_,v=kv.partition('='); rec[k]=v
io.open(r'$JLOG','a',encoding='utf-8').write(json.dumps(rec,ensure_ascii=False)+'\n')
print('[grid] '+sys.argv[1])" "$@" ; }

command -v claude >/dev/null 2>&1 || { jl halt_no_claude_cli; exit 0; }

# 기저 논문 정보 (active entry 의 base)
BASE=$("$PY" -c "
import io,json
try:
    d=json.loads(io.open(r'$ROOT/06_Registry/reinforce_ledger_l1.json','rb').read().decode('utf-8'))
    a=[e for e in d['entries'] if e.get('status')=='active']
    print((a[0].get('paper_key') or a[0].get('base_id') or '') if a else '')
except Exception: print('')" 2>/dev/null)
jl start "base=$BASE"

PROMPT="강화 프로세스의 **팩터 격자 5종**을 제안하라. 산출은 JSON 파일 하나다.

## 맥락
기저 전략은 팩터 하나로 신호를 만든다. 강화 1블록(B1)은 그 기저 신호에 **제2팩터 1종을
rank-Z 50:50 으로 결합**한 셀 5개를 돌려 어느 축이 붙는지 잰다. 그 5종을 고르는 일이다.
기저: ${BASE}

## 반드시 먼저 읽어라 (진술 말고 실제 판독)
1. \`06_Registry/factor_registry.json\` 또는 \`02_Infrastructure/factor_db/factor_db_connector.R\` 로
   **실재하는 팩터 코드**를 확인하라. 현재 331종이 있다. **없는 코드를 쓰면 셀이 통째로 죽는다.**
2. \`Rscript 02_Infrastructure/tools/hypothesis_index.R lookup <키워드>\` 로 **죽은 구성 380건**을
   조회하라. 이미 실패한 조합을 다시 넣지 마라(다만 새 각도면 정당 — AX-000).
3. \`06_Registry/reinforce_ledger_l1.json\` 의 직전 entry 실측 — 어떤 축이 이미 소진됐는지.

## 선정 기준 (근거를 쓰라 — 이름이 아니라 구성으로)
- **원천 다양성**: 5종이 서로 다른 정보원이어야 한다(가격·재무·컨센서스·유동성·수급).
  가격끼리 겹치면 기저 신호와 중복돼 분산 효과가 기계적 아티팩트가 된다.
- **직교성 근거**: 기저 신호와 왜 직교할 것으로 보는지 1줄. 추측이면 추측이라 쓰라.
- **가용성**: 커버리지가 낮은 팩터는 셀이 비어 죽는다 — 실제로 로드되는지 확인하라.

## 산출 (이 파일 하나만)
\`${OUT}\` — 아래 형식 그대로:
{\"proposed_at\":\"...\",\"base\":\"${BASE}\",\"cells\":[
  {\"code\":\"B1_1\",\"label\":\"<한글 8자 내>\",\"factor2\":{\"kind\":\"db\",\"id\":\"<실재 코드>\"},
   \"rationale\":\"<왜 이 축인가 1줄>\",
   \"root_paper\":{\"title\":\"<논문>\",\"url\":\"https://...\"}}, ... 5개 ...]}
- \`kind\` 는 \"db\"(팩터 DB) 또는 \"price\"(가격 파생, id=lowvol60 만).
- **root_paper 는 실재하는 원문 링크**여야 한다 — 원장이 링크 없는 시도를 거부한다(v10).

## 금지
- \`${OUT}\` 외 쓰기. 격자 본체(reinforce_program.json)·원장·설정 직접 수정.
- 백테스트 실행. 등급 언급. 없는 팩터 코드나 지어낸 논문 링크."

# ★격자 제안도 깊이 문제 — 팩터 331종·죽은 구성 380건을 읽고 5종을 고르는 판단이다.
timeout 1800 claude -p "$PROMPT" \
  --model "${QVEST_RP_MODEL:-opus}" --effort "${QVEST_RP_EFFORT:-max}" \
  --permission-mode acceptEdits \
  --allowed-tools "Read,Write,Glob,Grep,Bash(Rscript*),WebFetch,WebSearch" \
  --disallowed-tools "Agent" \
  >> "$LOG" 2>&1
jl agent_done "rc=$?"

[ -s "$OUT" ] || { jl no_proposal; exit 1; }
QM_ROOT="$ROOT" Rscript "$ROOT/02_Infrastructure/ops/rf_grid_apply.R" >> "$LOG" 2>&1
jl apply_done "rc=$?"
