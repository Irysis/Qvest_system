#!/usr/bin/env bash
#==============================================================================
# rf_fidelity_audit.sh — **적대적 충실도 감사** (도훈 지시 2026-09-04)
#
# 임무: "논문대로 구현했다" 는 선언을 **반증하라**. 일치 확인이 아니다.
#   검증 4관문은 산출물(계약·고정축·PIT·원장)만 본다. 충실도만 재도출이 없었고,
#   FIDELITY.json 은 에이전트 자신의 진술이었다. 진술은 증거가 아니다.
#
# 어디에 값이 있나: A등급 보호보다 **F 판정의 신뢰**다. 측정이 F 면 검증기가
#   ledger_consumed 로 논문을 영구 소비한다. 구현이 틀려서 F 였다면 그 논문은
#   잘못된 이유로 영영 버려진다(반전 전략 부호 반전 = 강한 음수 t 의 지문).
#
# 경계: 읽기 전용 + 감사 파일 1개 쓰기. 등급·원장·설정 접근 금지(AX-008).
#   verdict 는 등급을 바꾸지 못하고, 귀속 라벨과 소비 보류만 움직인다.
#
# 사용: rf_fidelity_audit.sh <wdir> <artifacts_dir> <paper_url> <paper_key>
#==============================================================================
set -uo pipefail
ROOT="${QVEST_RF_ROOT:-${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
CFG="${QVEST_RF_CONFIG:-$ROOT/06_Registry/reinforce_auto_config.json}"
# ★jlog 싱크는 QVEST_RP_JLOG 로 돌린다 (2026-09-04: 검사 픽스처가 운영 로그에 design_rejected 60·audit_rejected 44건을 박았다)
JLOG="${QVEST_RP_JLOG:-$ROOT/.cache/reinforce_auto_log.jsonl}"
LOG="$ROOT/.cache/scheduler_logs/fidelity_audit_$(date +%Y%m%d).log"
mkdir -p "$(dirname "$LOG")"

WDIR="${1:-}"; ART="${2:-}"; PURL="${3:-}"; PKEY="${4:-}"
AUD="$WDIR/fidelity_audit.json"

jl(){ "$PY" -c "
import io,json,sys,time
rec={'ts':time.strftime('%Y-%m-%dT%H:%M:%S%z'),'event':sys.argv[1],'src':'fidelity_audit'}
for kv in sys.argv[2:]:
    k,_,v=kv.partition('='); rec[k]=v
io.open(r'$JLOG','a',encoding='utf-8').write(json.dumps(rec,ensure_ascii=False)+'\n')
print('[fid_audit] '+sys.argv[1])" "$@" ; }

EN=$("$PY" -c "
import io,json
try:
    c=json.loads(io.open(r'$CFG','rb').read().decode('utf-8'))
    print('1' if c.get('enabled') and (c.get('fidelity_audit') or {}).get('enabled') else '0')
except Exception: print('0')" 2>/dev/null)
[ "$EN" = "1" ] || { jl halt_disabled; exit 0; }
[ -n "$WDIR" ] && [ -s "$WDIR/engine.R" ] || { jl halt_no_engine "wdir=$WDIR"; exit 0; }
command -v claude >/dev/null 2>&1 || { jl halt_no_claude_cli; exit 0; }
rm -f "$AUD"

# ── ★축별 팬아웃으로 위임 (도훈 지시 2026-09-04) ─────────────────────────────
#   단일 감사자는 **분류한다** — 2302.10175 감사가 "최고위험 2건을 원문 대조" 라고 적었고,
#   나머지 축을 안 본 사실은 아무 데도 안 남았다. 축마다 에이전트를 세우면 안 본 축이
#   존재할 수 없다. 호출부(rf_replication_verify.R)는 그대로다 — 산출 파일도 스키마도 같다.
#   fanout.enabled=false 면 아래 단일 레인으로 돌아간다(구판 보존).
FANOUT=$("$PY" -c "
import io,json
try:
    c=json.loads(io.open(r'$CFG','rb').read().decode('utf-8'))
    print('1' if ((c.get('fidelity_audit') or {}).get('fanout') or {}).get('enabled') else '0')
except Exception: print('0')" 2>/dev/null)
if [ "$FANOUT" = "1" ]; then
  jl delegate_fanout "paper=$PKEY"
  exec bash "$ROOT/02_Infrastructure/ops/rf_fidelity_fanout.sh" "$WDIR" "$ART" "$PURL" "$PKEY"
fi

# ★원문 접근 경로를 프롬프트에 박는다 — /abs 는 초록뿐이고 /pdf 는 이 환경에서 못 읽는다.
#   그 사실을 모르면 감사자가 초록만 보고 "일치" 라고 쓴다(2026-09-02 실측 교훈).
AXID=$(printf '%s' "$PURL" | sed -n 's#.*arxiv\.org/\(abs\|html\|pdf\)/\([0-9v.]*\).*#\2#p')
HTMLU=""
[ -n "$AXID" ] && HTMLU="https://arxiv.org/html/${AXID}v1"
# ★전문 주소 줄은 미리 조립한다 — 큰따옴 안 $( ) 중첩은 셀 파서를 깨뜨린다.
HTMLLINE=""
[ -n "$HTMLU" ] && HTMLLINE="- 원문 전문(이 주소로 읽어라): $HTMLU"

. "$ROOT/02_Infrastructure/ops/rf_axiom_brief.sh"
AXB="$(rf_axiom_brief)"

PROMPT="너는 **적대적 검증자**다. 아래 구현이 논문과 다르다는 것을 **입증하라.**

${AXB}
일치를 확인하는 일이 아니다 — 다른 지점을 찾는 것이 임무다. 못 찾으면 그때 faithful 이다.

## 페르소나 — 감정을 배제한 철저한 비평가 (도훈 지시 2026-09-04)
너는 구현자에 대한 호의도 적의도 없다. 칭찬도 위로도 비난도 네 산출물에 들어가지 않는다.
- **인상은 판정이 아니다.** \"대체로 맞아 보인다\" \"큰 문제는 없어 보인다\" 는 쓰지 마라.
  모든 진술은 **원문 위치(절·식 번호·표)와 코드 행**으로 뒷받침하라. 못 대면 적지 마라.
- **관대함은 미덕이 아니다.** 넘어가 준 불일치는 나중에 누군가가 잘못된 결론을 내리는 값으로
  돌아온다. 특히 이 판정 뒤에는 논문을 영구 소비하는 경로가 있다.
- **가혹함도 미덕이 아니다.** 근거 없는 기각은 감사가 아니라 잡음이고, 침묵과 같은 값어치다.
  많이 찾는 것이 잘하는 것이 아니다 — 정확히 찾는 것이 잘하는 것이다.
- **구현자의 의도를 추측하지 마라.** \"아마 …하려던 것 같다\" 는 감사가 아니다.
  코드가 **하는 일**과 문서가 **말하는 일**의 차이만 기술하라.
- **판정을 먼저 정하고 근거를 모으지 마라.** 대조를 끝낸 뒤에 판정이 따라 나온다.
  중간에 유리한 근거가 보여도 나머지 축을 끝까지 대조하라.
- **네가 틀릴 수 있다는 것도 기록하라.** 확신이 낮으면 confidence 를 낮춰 적고,
  판정에 못 미치는 관찰은 note 에 남겨라 — 부풀리지도, 감추지도 않는다.
- 물질적 차이와 문구·위치 문제를 구분하라. 전자는 지적이고, 후자는 note 다.

## 대상
- 논문: ${PURL}
${HTMLLINE}
- 구현: ${WDIR}/engine.R
- 자기신고: ${WDIR}/FIDELITY.json   ← **이 진술을 믿지 마라. 대조 대상이다.**
- 측정 산출물: ${ART}

## 원문 접근 (실측된 함정 — 2026-09-02)
- \`arxiv.org/abs/…\` 는 **초록만** 준다. 초록만 읽고 판정하면 정의역을 틀린다.
- \`arxiv.org/pdf/…\` 는 이 환경에서 못 읽는다.
- **\`arxiv.org/html/<id>v1\` 이 유일한 전문 경로**다. 위에 그 주소를 적어 두었다.
- 전문을 못 읽었으면 verdict 는 반드시 \`unverifiable\` 이다. **모르는 것을 faithful 로 적지 마라.**

## 대조할 축 (각각 논문 원문에서 근거를 찾아라)
1. 신호 정의 — 수식·**부호**·룩백 창·표준화. 부호 반전은 강한 음수 t 로 나타난다.
2. 형성/보유 기간(J/K) · 리밸런싱 주기 · 스킵 기간
3. 유니버스와 그 필터 (우리는 K200∪KQ150 으로 바꾸는 것이 허용된다 — 그건 변경이 아니다)
4. 롱온리/롱숏 · 종목수 · 비중 방법
5. 거래비용 가정
6. **FIDELITY.json 의 changed 에 없는 변경** — 이게 핵심이다. 선언 안 된 변경을 찾아라.

## 판정
- \`faithful\`     : 논문과 실질적으로 같다(허용된 유니버스 교체 제외)
- \`adapted\`      : 다르지만 **그 차이가 changed 에 정직하게 선언돼 있다**
- \`misdeclared\`  : 다른데 선언이 없거나 선언이 사실과 다르다  ← 이걸 찾는 게 임무다
- \`unverifiable\` : 원문을 읽지 못했다

★\`misdeclared\` 는 **원문 근거 없이 낼 수 없다.** 지적 항목 최소 1건 + evidence 필수 —
  근거 없는 기각은 감사가 아니라 잡음이고, 침묵과 같은 값어치다.

## 산출 (이것만)
\`${AUD}\` :
{
  \"verdict\": \"faithful|adapted|misdeclared|unverifiable\",
  \"undeclared_changes\": [\"논문은 X 인데 구현은 Y — FIDELITY.changed 에 없음\"],
  \"signal_mismatch\": [\"논문 식 (3) 의 부호는 …, engine.R:NN 은 …\"],
  \"evidence\": \"원문에서 근거를 찾은 위치(절·식 번호·표)\",
  \"confidence\": \"high|medium|low\",
  \"_배열 규약\": \"undeclared_changes·signal_mismatch 는 **발견만** 담는다. 없으면 빈 배열 [] 로 두고, '불일치 없음' 같은 비발견을 항목으로 넣지 마라 — 근거 게이트가 배열 길이로 서므로 채움 항목이 게이트를 통과시킨다. 확인한 일치는 note 에 적어라.\",
  \"note\": \"1~2줄\"
}

## 금지
- ${WDIR} 밖 쓰기. 엔진 수정. 백테스트 실행. 등급·성과 수치 선언(계약이 낸다).
- 원문을 못 읽은 채 faithful/adapted 로 적는 것.

감사 파일을 쓰고 1줄로 판정만 보고하라."

# ★모델·노력수준은 설정의 llm 블록이 정본이다 (2026-09-04) — 네 레인이 각자 기본값을
#   들고 있으면 한 곳을 바꿔도 나머지가 그대로 남는다. 환경변수는 그대로 최우선.
. "$ROOT/02_Infrastructure/ops/rf_llm_env.sh"
rf_llm_resolve fidelity_audit "${QVEST_FA_MODEL:-}" "${QVEST_FA_EFFORT:-}"
FA_MODEL="$LLM_MODEL"
FA_EFFORT="$LLM_EFFORT"
jl start "paper=$PKEY" "wdir=$WDIR" "model=$FA_MODEL" "effort=$FA_EFFORT" "html=$HTMLU"
# ★프롬프트는 stdin 으로 (2026-09-04): argv 로 넘기면 Windows 인자 상한(32K)에 걸려 에이전트가 안 뜰다 — 승격 entry B1 설계 재료 41KB 실사고.
PF="$WDIR/fidelity_prompt.txt"
printf %s "$PROMPT" > "$PF"
timeout 1800 claude -p < "$PF" \
  --model "$FA_MODEL" --effort "$FA_EFFORT" \
  --permission-mode acceptEdits \
  --allowed-tools "Read,Write,Glob,Grep,WebFetch,WebSearch" \
  --disallowed-tools "Bash,Agent,Edit" \
  --add-dir "$WDIR" \
  >> "$LOG" 2>&1
jl agent_done "rc=$?"

if grep -qiE "OAuth access token has expired|Failed to authenticate|API Error: 401" "$LOG" 2>/dev/null; then
  jl halt_auth_expired "hint=claude 재인증 필요"; exit 2; fi

Rscript "$ROOT/02_Infrastructure/ops/rf_fidelity_audit_lib.R" verify "$AUD" >> "$LOG" 2>&1
jl verify_done "rc=$?" "paper=$PKEY"
exit 0
