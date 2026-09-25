#!/usr/bin/env bash
#==============================================================================
# rf_b1_design.sh — B1(멀티팩터) 블록 **설계 1회** (도훈 지시 2026-09-04)
#
# 무엇을 바꾸나:
#   구판 B1 은 깊이 1~5 · 5칸 고정이었고, 팩터 선정은 rf_factor_arms 의 그리디 사슬
#   (IC 시계열 상관 최소 · 계열 라운드로빈)이 했다. 규칙이라 감독은 쉬웠지만, 등록부
#   332종을 놓고 "왜 이 다섯인가" 에 답하는 것은 정렬이지 판단이 아니었다.
#   ⇒ 블록 진입 시 **한 번** 에이전트가 그 논문 전용 조합을 설계하고, 칸들은 그 설계를
#      규칙으로 전개한다. LLM 이 닿는 지점은 하나이고 산출물은 기계 검증을 통과해야 쓰인다.
#      (칸마다 부르지 않는 이유 = 강화 레인의 "규칙 개시" 경계와 비용 25배.)
#
# 안전:
#   ① 산출은 설계 JSON 하나 — 측정·등급·PIT 는 계약이 강제한다.
#   ② 권한 축소: 쓰기 디렉터리 1개 · Bash/Agent 금지.
#   ③ 검증 실패 = 설계 폐기 + **규칙 선정으로 폴백**(조용한 통과 없음).
#   ④ claim 으로 중복 실행 차단, 하루 상한으로 폭주 차단.
#
# 호출: tick(러너 앞) 또는 수동. 조건이 안 맞으면 즉시 물러난다.
#==============================================================================
set -uo pipefail
ROOT="${QVEST_RF_ROOT:-${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
CFG="${QVEST_RF_CONFIG:-$ROOT/06_Registry/reinforce_auto_config.json}"
# ★jlog 싱크는 QVEST_RP_JLOG 로 돌린다 (2026-09-04: 검사 픽스처가 운영 로그에 design_rejected 60·audit_rejected 44건을 박았다)
JLOG="${QVEST_RP_JLOG:-$ROOT/.cache/reinforce_auto_log.jsonl}"
LOG="$ROOT/.cache/scheduler_logs/b1_design_$(date +%Y%m%d).log"
DDIR="$ROOT/.cache/rf_b1_design"
CLAIM="$ROOT/.cache/rf_b1_design.claim"
mkdir -p "$(dirname "$LOG")" "$DDIR"

jl(){ "$PY" -c "
import io,json,sys,time
rec={'ts':time.strftime('%Y-%m-%dT%H:%M:%S%z'),'event':sys.argv[1],'src':'b1_design'}
for kv in sys.argv[2:]:
    k,_,v=kv.partition('='); rec[k]=v
io.open(r'$JLOG','a',encoding='utf-8').write(json.dumps(rec,ensure_ascii=False)+'\n')
print('[b1_design] '+sys.argv[1])" "$@" ; }

EN=$("$PY" -c "
import io,json
try:
    c=json.loads(io.open(r'$CFG','rb').read().decode('utf-8'))
    print('1' if c.get('enabled') and (c.get('b1_design') or {}).get('enabled') else '0')
except Exception: print('0')" 2>/dev/null)
[ "$EN" = "1" ] || { jl halt_disabled; exit 0; }

# 대상: 활성 entry 이면서 B1 이 아직 시작 안 됐고 설계가 없는 것
read -r BID NEED <<<"$("$PY" -c "
import io,json
try:
    led=json.loads(io.open(r'$ROOT/06_Registry/reinforce_ledger_l1.json','rb').read().decode('utf-8'))
except Exception:
    print('- 0'); raise SystemExit
act=[e for e in led.get('entries') or [] if e.get('status')=='active']
if not act: print('- 0'); raise SystemExit
e=act[0]
codes=set()
for a in e.get('attempts') or []:
    cc=a.get('cell_code') or ((a.get('essence') or {}).get('cell_code'))
    if cc: codes.add(cc)
b1_started=any(str(c).startswith('B1_') for c in codes)
print('%s %s' % (e.get('base_id'), '0' if b1_started else '1'))" 2>/dev/null)"
[ "${NEED:-0}" = "1" ] || { jl not_due "base_id=${BID:--}" "note=B1 이미 시작됐거나 활성 entry 없음"; exit 0; }
DES="$DDIR/${BID:0:60}.json"
[ -s "$DES" ] && { jl already_designed "base_id=$BID"; exit 0; }

command -v claude >/dev/null 2>&1 || { jl halt_no_claude_cli; exit 0; }
mkdir "$CLAIM" 2>/dev/null || { jl halt_claimed; exit 0; }
echo $$ > "$CLAIM/owner"
trap 'rm -rf "$CLAIM" 2>/dev/null' EXIT

MAT="$DDIR/${BID:0:60}.materials.txt"
Rscript "$ROOT/02_Infrastructure/ops/rf_b1_design_lib.R" materials "$BID" "$MAT" >> "$LOG" 2>&1 || {
  jl materials_failed "base_id=$BID"; exit 1; }
MAXC=$("$PY" -c "
import io,json
try: print((json.loads(io.open(r'$CFG','rb').read().decode('utf-8')).get('b1_design') or {}).get('max_cells') or 15)
except Exception: print(15)" 2>/dev/null)

. "$ROOT/02_Infrastructure/ops/rf_axiom_brief.sh"
AXB="$(rf_axiom_brief)"

PROMPT="이 전략의 **B1 멀티팩터 블록**을 설계하라. 산출은 설계 JSON 파일 하나다.

${AXB}

$(cat "$MAT")

## 무엇을 설계하는가
기저 신호 **위에** 팩터를 얹어 횡단면 컴포짓을 만든다(기저 가중 w0=0.5 고정, 나머지를 팩터가 등분).
너는 **어떤 팩터를 · 몇 개씩 · 몇 칸으로** 시험할지 정한다.

## 제한하지 않는 것 (도훈 2026-09-04)
- 칸 수: 네가 정한다(상한 ${MAXC} — 예산 폭주 방지일 뿐이다).
  ★칸 수가 곧 이 entry 의 총예산이다: **총예산 = 25 + max(0, 칸수 − 5)**. 5칸이면 25, 15칸이면 35.
    뒤 블록(비중·유니버스·오버레이·결합)은 그 예산 안에서 각 5칸을 그대로 받는다 — 즉 B1 을 넓게
    가져가도 뒤 블록이 잘리지 않는다. 그러니 **넓힐 이유가 있으면 넓히고, 없으면 좁혀라**(측정은 비싸다).
- 팩터 개수: 칸마다 달라도 된다. 깊이를 1,2,3,4,5 로 누적할 이유도 없다.
- 조합 방식: 누적 사슬이든, 계열 대비든, 한 축을 고정하고 다른 축만 바꾸든 네가 정한다.

## 제한하는 것 (계약이지 설계 취향이 아니다)
- 팩터 id 는 **위 등록부에 있는 것만**. 없는 id 가 하나라도 있으면 설계 전체가 기각된다.
- 칸끼리 팩터 집합이 같으면 안 된다(같은 구성에 다른 이름 = 칸 낭비).
- 각 칸에 factors 최소 1개, label 필수.
- **승계 절이 있으면**(승격 entry) 네 factors 는 승계 집합에 *더해지는* 것이다. 승계 팩터를 다시
  넣은 칸은 중복 제거 후 승계와 같아져 **미측정으로 닫힌다** — 그 칸은 버려진다.

## 앞선 논문들의 교훈을 쓰라 (도훈 지시 2026-09-04)
위 재료에 \"앞선 논문들에서 이미 배운 것\" 절이 있으면 **반드시 읽고 설계에 반영하라**.
- 수치는 그 논문의 것이라 여기에 의미가 없다. **기전**만 옮겨 붙는다
  (예: 어떤 축이 횡단면에선 죽고 노출 스케일에선 산다 — 이건 기저가 달라도 성립한다).
- 이미 벽이 확인된 축에 칸을 쓰지 마라. 그게 예산의 가장 큰 낭비다.
- 다만 **금지 목록이 아니다**(AX-000). 다른 각도라면 재시도는 정당하고,
  그때는 \"무엇이 다른 각도인지\" 를 rationale 에 적어라.

## 참고 — 지금까지의 규칙 선정이 하던 일
IC 시계열 상관이 최소가 되는 순서로 팩터를 하나씩 붙이고(계열 중복 금지), 그 사슬의
접두 집합을 깊이 1~5 다섯 칸으로 냈다. 그 방식을 다시 골라도 되지만, **그 논문의 기전에
비추어 무엇이 기저를 보완하는가**를 읽고 고르라는 것이 이 설계의 목적이다.

## 산출 (이것만)
\`${DES}\` — 아래 형태의 JSON:
{
  \"schema\": \"rf_b1_design_v1\",
  \"base_id\": \"${BID}\",
  \"rationale\": \"이 논문의 기저에 무엇이 왜 부족한지, 그래서 어떤 축으로 붙이는지 2~3줄\",
  \"cells\": [
    {\"label\": \"짧은 이름\", \"factors\": [\"FACTOR_ID\", \"...\"], \"rationale\": \"이 칸이 무엇을 가르는가 1줄\"}
  ]
}

## 금지
- ${DDIR} 밖 쓰기. 원장·설정·훅·테스트 수정. 백테스트 실행(측정은 계약이 한다).
- 등급·성과 수치 선언. 등록부에 없는 팩터 id.

설계 파일을 쓰고 1~2줄로 무엇을 시험하려는지만 보고하라."

# ★모델·노력수준은 설정의 llm 블록이 정본이다 (2026-09-04) — 네 레인이 각자 기본값을
#   들고 있으면 한 곳을 바꿔도 나머지가 그대로 남는다. 환경변수는 그대로 최우선.
. "$ROOT/02_Infrastructure/ops/rf_llm_env.sh"
rf_llm_resolve b1_design "${QVEST_B1_MODEL:-}" "${QVEST_B1_EFFORT:-}"
B1_MODEL="$LLM_MODEL"
B1_EFFORT="$LLM_EFFORT"
jl start "base_id=$BID" "model=$B1_MODEL" "effort=$B1_EFFORT" "max_cells=$MAXC"
# ★프롬프트는 stdin 으로 (2026-09-04): argv 로 넘기면 Windows 인자 상한(32K)에 걸려 에이전트가 안 뜰다 — 승격 entry B1 설계 재료 41KB 실사고.
PF="$DDIR/prompt_${BID:0:60}.txt"
printf %s "$PROMPT" > "$PF"
# ★무인 LLM 단일 진입(P0-M1 2026-09-24) — rf_llm_agent_run 이 AutoMem 차단·무인 표식을 싣고
#   --model/--effort 는 위 rf_llm_resolve 값(LLM_MODEL=B1_MODEL · LLM_EFFORT=B1_EFFORT)을 쓴다.
#   출력은 이번 실행 파일에 받고 로그에 덧붙인다(구판 `>> $LOG` 와 같은 로그 내용).
RUN_OUT="$(mktemp "${TMPDIR:-/tmp}/rf_b1_run.XXXXXX")"
#   폴백 미탑재(LLM_FALLBACK_MODEL="" · 구판 동작 보존): 구판도 --fallback-model 없이 떴고 이 레인엔
#   반쪽 산출물 청소 훅(rf_llm_before_fallback)이 없다 — 폴백 확대는 청소 훅과 함께 별도 결정.
# ★설계 레인 성과 열람 봉쇄(P0-M2 2026-09-25): QVEST_DESIGN_LANE=1 = 함수 호출 앞 임시 대입 — 이 claude 와 그 훅에만 실리고
#   호출 뒤 셸에는 남지 않는다. 훅 arm_gen_read_guard.sh 가 원장·측정 산출물·기억 디렉터리 Read/Grep/Glob 을 막는다
#   (설계는 재료만 본다 — 형제 entry 원장 직접 열람은 의도적으로 막힌다). PowerShell 도 금지 — 훅 matcher(Read|Grep|Glob) 밖이라
#   셸로는 막을 수 없다(09-25 transcript: 설계 세션이 PowerShell findstr 로 원장 calmar 를 읽었다).
#   (P0-M2 수리 2026-09-25 · B-1) 셸 통로 전부 금지 = CLI 2.1.261 이 enablesCodeExecution 으로 표시한 내장 도구 7종
#   (Bash·PowerShell·Monitor·REPL·Workflow·CronCreate·RemoteTrigger). Monitor 는 셸 명령을 돌려 출력을 이벤트로 돌려준다 —
#   충실도 감사 세션(25caa112 · 09-17)이 Bash 금지 아래서 Monitor 로 diff 를 돌렸다. 훅 matcher(Read|Grep|Glob) 밖이라 막는 곳은 여기뿐.
QVEST_DESIGN_LANE=1 LLM_FALLBACK_MODEL="" rf_llm_agent_run "$PF" "$RUN_OUT" 1800 \
  --permission-mode acceptEdits \
  --allowed-tools "Read,Write,Edit,Glob,Grep,WebFetch,WebSearch" \
  --disallowed-tools "Bash,PowerShell,Monitor,REPL,Workflow,CronCreate,RemoteTrigger,Agent" \
  --add-dir "$DDIR"
ARC=$LLM_RC
[ -f "$RUN_OUT.primary" ] && cat "$RUN_OUT.primary" >> "$LOG"
cat "$RUN_OUT" >> "$LOG" 2>/dev/null
rm -f "$RUN_OUT" "$RUN_OUT.primary"
jl agent_done "rc=$ARC"

if grep -qiE "OAuth access token has expired|Failed to authenticate|API Error: 401" "$LOG" 2>/dev/null; then
  jl halt_auth_expired "hint=claude 재인증 필요 — 리서치 실패 아님"; exit 2; fi

# ★검증은 기계가 재도출한다 — 에이전트 진술은 근거가 아니다.
#   실패하면 설계를 지우고 물러난다. 러너는 설계가 없으면 규칙 선정으로 돈다(폴백).
Rscript "$ROOT/02_Infrastructure/ops/rf_b1_design_lib.R" verify "$BID" "$DES" >> "$LOG" 2>&1
VRC=$?
jl verify_done "rc=$VRC" "base_id=$BID"
exit $VRC
