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
JLOG="$ROOT/.cache/reinforce_auto_log.jsonl"
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

# ★원문 접근 경로를 프롬프트에 박는다 — /abs 는 초록뿐이고 /pdf 는 이 환경에서 못 읽는다.
#   그 사실을 모르면 감사자가 초록만 보고 "일치" 라고 쓴다(2026-09-02 실측 교훈).
AXID=$(printf '%s' "$PURL" | sed -n 's#.*arxiv\.org/\(abs\|html\|pdf\)/\([0-9v.]*\).*#\2#p')
HTMLU=""
[ -n "$AXID" ] && HTMLU="https://arxiv.org/html/${AXID}v1"
# ★전문 주소 줄은 미리 조립한다 — 큰따옴 안 $( ) 중첩은 셀 파서를 깨뜨린다.
HTMLLINE=""
[ -n "$HTMLU" ] && HTMLLINE="- 원문 전문(이 주소로 읽어라): $HTMLU"

PROMPT="너는 **적대적 검증자**다. 아래 구현이 논문과 다르다는 것을 **입증하라.**
일치를 확인하는 일이 아니다 — 다른 지점을 찾는 것이 임무다. 못 찾으면 그때 faithful 이다.

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
  \"note\": \"1~2줄\"
}

## 금지
- ${WDIR} 밖 쓰기. 엔진 수정. 백테스트 실행. 등급·성과 수치 선언(계약이 낸다).
- 원문을 못 읽은 채 faithful/adapted 로 적는 것.

감사 파일을 쓰고 1줄로 판정만 보고하라."

FA_MODEL="${QVEST_FA_MODEL:-opus}"
FA_EFFORT="${QVEST_FA_EFFORT:-max}"
jl start "paper=$PKEY" "wdir=$WDIR" "model=$FA_MODEL" "html=$HTMLU"
timeout 1800 claude -p "$PROMPT" \
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
