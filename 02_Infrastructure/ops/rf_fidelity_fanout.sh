#!/usr/bin/env bash
#==============================================================================
# rf_fidelity_fanout.sh — 적대적 충실도 감사 **축별 팬아웃** (도훈 지시 2026-09-04)
#
# 왜 팬아웃인가: 단일 감사자는 **분류한다**. 2026-09-04 2302.10175 감사가 자기 산출물에
#   "최고위험 2건을 원문 대조" 라고 적었다 — 나머지 축은 안 봤다는 뜻인데, verdict 는
#   그래도 하나로 나온다. **무엇을 안 봤는지가 아무 데도 안 남는다.**
#   축마다 에이전트를 세우면 '안 본 축' 이 존재할 수 없고, 못 찾은 축은 no_finding 으로
#   명시적으로 남는다. 축 정본 = 06_Registry/rf_fidelity_axes.json.
#
# 왜 오케스트레이터를 안 쓰나: opus 하나가 "무엇을 위임할지" 고르면 **분류가 한 층 위로
#   올라갈 뿐 사라지지 않는다** — 지금 고치려는 병이 그것이다. 축은 이미 고정이라
#   오케스트레이터가 결정할 것이 없다. 게다가 무인 레인은 claude -p 로 도는데 그 안에서
#   Agent 를 또 스폰하면 12분 레인이 30분이 되고 클레임·타임아웃이 두 겹이 된다.
#
# 왜 축마다 모델이 다른가: 판독형(원문 문장을 해석해 코드와 대조)은 깊이 문제라 opus,
#   대조형(논문의 수치를 찾아 코드 수치와 비교)은 해석이 안 들어가 sonnet 으로 충분하다.
#   축이 좁아지는 것 자체가 비용 절감이다 — 각자 논문 전문이 아니라 자기 절만 읽는다.
#
# 경계: 각 레인은 읽기 전용 + 자기 축 파일 1개 쓰기. 병합은 **R 이 한다**(LLM 판정자 없음)
#   — 이 저장소 규약과 같다("R 이 등재한다. LLM 은 카탈로그를 못 쓴다").
#
# 사용: rf_fidelity_fanout.sh <wdir> <artifacts_dir> <paper_url> <paper_key>
#==============================================================================
set -uo pipefail
ROOT="${QVEST_RF_ROOT:-${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}}"
# ★슬래시 정규화 (2026-09-06 실사고 — merge_done rc=1: 09-04 16:19 · 09-06 17:58 · 18:08).
#   Windows User-scope QM_ROOT 는 역슬래시(C:\Users\…)다. 그 문자열이 아래 `Rscript -e "source('$ROOT/…')"`
#   의 R 리터럴에 들어가면 '\U' 가 이스케이프로 읽혀 병합기가 한 줄도 못 돌고 죽는다.
#   verify(R)→system2(bash) 경로는 R 이 ~/.Renviron 의 슬래시 값을 물려줘 살고, 세션 셸·스케줄러 셸에서
#   직접 기동하면 죽었다 — 같은 스크립트가 기동 부모에 따라 살고 죽는 형태. 여기서 한 번 뒤집는다.
#   (--file= 은 저장소 규칙으로 금지 · rf_weight_catalog_grow.sh 와 같은 한 줄 · 검사 = test_rf_fanout_merge_root.sh)
ROOT="${ROOT//\\//}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
AXES="${QVEST_RF_AXES:-$ROOT/06_Registry/rf_fidelity_axes.json}"
# ★jlog 싱크는 QVEST_RP_JLOG 로 돌린다 (2026-09-04: 검사 픽스처가 운영 로그에 design_rejected 60·audit_rejected 44건을 박았다)
JLOG="${QVEST_RP_JLOG:-$ROOT/.cache/reinforce_auto_log.jsonl}"
# ★QVEST_FA_LOG — 검사가 병합 단계만 분리 실행할 때 운영 로그에 실패 지문('\U' 오류 등)을 남기지 않게 돌린다
LOG="${QVEST_FA_LOG:-$ROOT/.cache/scheduler_logs/fidelity_fanout_$(date +%Y%m%d).log}"
mkdir -p "$(dirname "$LOG")"

WDIR="${1:-}"; ART="${2:-}"; PURL="${3:-}"; PKEY="${4:-}"

jl(){ "$PY" -c "
import io,json,sys,time
rec={'ts':time.strftime('%Y-%m-%dT%H:%M:%S%z'),'event':sys.argv[1],'src':'fidelity_fanout'}
for kv in sys.argv[2:]:
    k,_,v=kv.partition('='); rec[k]=v
io.open(r'$JLOG','a',encoding='utf-8').write(json.dumps(rec,ensure_ascii=False)+'\n')
print('[fanout] '+sys.argv[1])" "$@" ; }

[ -n "$WDIR" ] && [ -s "$WDIR/engine.R" ] || { jl halt_no_engine "wdir=$WDIR"; exit 0; }

# ── 병합 + 스키마 검증 — R 이 한다 (LLM 판정자 없음) ──────────────────────────
#   ★함수로 둔 이유: 검사가 QVEST_FA_MERGE_ONLY=1 로 **이 단계만** 분리 실행한다(claude -p 없이).
#   ★병합 실패는 크게 (2026-09-06): 구판은 `merge_done rc=1` 을 적고도 exit 0 이었고, 호출자(verify)는
#     감사 파일 부재를 unverifiable 로 읽어 proceed 했다 — 감사 없이 소비·개설이 일어났다.
#     이제 rc≠0 이면 merge_failed 저널 + exit 3. 성공하면 단일 레인과 같이 스키마 검증(audit_verified)까지 남긴다
#     (검증기가 형식 위반 파일을 지우므로, 그 뒤의 부재는 verify 쪽 rf_audit_gate 가 미실행으로 잡는다).
fa_merge(){
  Rscript -e "source('$ROOT/02_Infrastructure/ops/rf_fidelity_merge.R')" "$WDIR" "$AXES" >> "$LOG" 2>&1
  local rc=$?
  if [ "$rc" != "0" ]; then jl merge_failed "rc=$rc" "paper=$PKEY"; return 3; fi
  jl merge_done "rc=$rc" "paper=$PKEY"
  Rscript "$ROOT/02_Infrastructure/ops/rf_fidelity_audit_lib.R" verify "$WDIR/fidelity_audit.json" >> "$LOG" 2>&1
  jl verify_done "rc=$?" "paper=$PKEY"
  return 0
}
if [ "${QVEST_FA_MERGE_ONLY:-0}" = "1" ]; then fa_merge; exit $?; fi

command -v claude >/dev/null 2>&1 || { jl halt_no_claude_cli; exit 0; }

# ★원문 접근 경로 — /abs 는 초록뿐이고 /pdf 는 이 환경에서 못 읽는다(2026-09-02 실측).
AXID=$(printf '%s' "$PURL" | sed -n 's#.*arxiv\.org/\(abs\|html\|pdf\)/\([0-9v.]*\).*#\2#p')
HTMLU=""
[ -n "$AXID" ] && HTMLU="https://arxiv.org/html/${AXID}v1"

. "$ROOT/02_Infrastructure/ops/rf_axiom_brief.sh"
AXB="$(rf_axiom_brief)"

# ── 축별 프롬프트 조립 (등록부에서 — 셸에 축을 박지 않는다) ────────────────────
PLAN="$WDIR/.audit_plan.tsv"
rm -f "$PLAN"
AXB="$AXB" HTMLU="$HTMLU" PURL="$PURL" WDIR="$WDIR" ART="$ART" AXES="$AXES" PLAN="$PLAN" \
"$PY" - <<'PYEOF'
import io, json, os
axes = json.load(io.open(os.environ['AXES'], encoding='utf-8'))['axes']
W, A = os.environ['WDIR'], os.environ['ART']
htmlline = ("- 원문 전문(이 주소로 읽어라): " + os.environ['HTMLU']) if os.environ['HTMLU'] else \
           "- ★arxiv id 를 못 뽑았다. 원문 전문을 못 읽으면 verdict 는 unverifiable 이다."
rows = []
for ax in axes:
    k = ax['key']
    out = "%s/fidelity_axis_%s.json" % (W, k)
    p = """너는 **적대적 검증자**다. 아래 구현이 논문과 다르다는 것을 **입증하라.**
너에게 배정된 축은 **하나뿐**이다 — 그 축만 본다. 다른 축은 다른 검증자가 동시에 보고 있다.

%s
## 네 축: %s
%s

### 이 축에서 할 일
%s

**반례를 구성하라.** %s

## 페르소나 — 감정을 배제한 철저한 비평가
너는 구현자에 대한 호의도 적의도 없다. 칭찬도 위로도 비난도 네 산출물에 들어가지 않는다.
- **인상은 판정이 아니다.** "대체로 맞아 보인다" 는 쓰지 마라. 모든 진술은 **원문 위치(절·식 번호·표)와 코드 행**으로 뒷받침하라. 못 대면 적지 마라.
- **관대함은 미덕이 아니다.** 넘어가 준 불일치는 나중에 누군가가 잘못된 결론을 내리는 값으로 돌아온다. 이 판정 뒤에는 논문을 영구 소비하는 경로가 있다.
- **가혹함도 미덕이 아니다.** 근거 없는 기각은 감사가 아니라 잡음이고, 침묵과 같은 값어치다.
- **구현자의 의도를 추측하지 마라.** 코드가 **하는 일**과 문서가 **말하는 일**의 차이만 기술하라.
- **판정을 먼저 정하고 근거를 모으지 마라.** 대조를 끝낸 뒤에 판정이 따라 나온다.
- **네 축에서 아무것도 못 찾는 것은 정상이고, 정직한 결과다.** 없는 것을 만들어 내지 마라 —
  축 6개 중 발견이 있는 축은 보통 소수다. 빈손으로 돌아오는 것이 이 설계의 기본값이다.
- **네 축 밖의 것을 보고하지 마라.** 다른 축에서 이상한 것이 눈에 띄면 note 에 한 줄만 남겨라.

## 대상
- 논문: %s
%s
- 구현: %s/engine.R
- 자기신고: %s/FIDELITY.json   ← **이 진술을 믿지 마라. 대조 대상이다.**
- 측정 산출물: %s

## 원문 접근 (실측된 함정 — 2026-09-02)
- `arxiv.org/abs/...` 는 **초록만** 준다. 초록만 읽고 판정하면 정의역을 틀린다.
- `arxiv.org/pdf/...` 는 이 환경에서 못 읽는다.
- **`arxiv.org/html/<id>v1` 이 유일한 전문 경로**다.
- 네 축의 근거를 원문에서 못 찾았으면 verdict 는 반드시 `unverifiable` 이다. **모르는 것을 faithful 로 적지 마라.**

## 판정 (네 축에 한정)
- `faithful`     : 이 축에서 논문과 실질적으로 같다 (허용된 유니버스 교체 제외)
- `adapted`      : 다르지만 **그 차이가 FIDELITY.changed 에 정직하게 선언돼 있다**
- `misdeclared`  : 다른데 선언이 없거나 선언이 사실과 다르다  ← 이걸 찾는 게 임무다
- `unverifiable` : 이 축의 근거를 원문에서 확인하지 못했다

★`misdeclared` 는 **원문 근거 없이 낼 수 없다.** 지적 항목 최소 1건 + evidence 필수.

## 산출 (이것만)
`%s` :
{
  "axis": "%s",
  "verdict": "faithful|adapted|misdeclared|unverifiable",
  "undeclared_changes": ["[한 줄 요약] 논문은 X 인데 구현은 Y - FIDELITY.changed 에 없음"],
  "signal_mismatch": ["[한 줄 요약] 논문 식 (3) 의 부호는 ..., engine.R:NN 은 ..."],
  "counterexample": "구현이 논문과 다른 값을 내는 구체적 상황. 구성 못 했으면 그 사실을 적어라.",
  "evidence": "원문에서 근거를 찾은 위치(절·식 번호·표)",
  "confidence": "high|medium|low",
  "checked": "이 축에서 실제로 대조한 항목들 - 한 줄",
  "_항목 서술 규약": "★모든 항목은 대괄호 **한 줄 요약**으로 시작한다 - 12~30자 · 그 항목만 읽고도 무엇이 어긋났는지 아는 문장 · 원문 인용이나 파일:행을 요약에 넣지 마라(뒤 본문에 적는다). 이 요약이 통지에 그대로 실리고 본문은 안 실린다 - 요약이 없으면 사람은 잘린 원문 조각을 받는다. 예: '[숏 레그 그로스 익스포저 24%% 미달]' · '[유니버스 탈락분 비중 재분배 없음]' · '[은닉층 순환 구조 미구현]'. ★용어는 그 분야의 정통 표기를 쓴다 - 임의 한글 조어를 만들지 말고, 원문 용어가 영문이면 통용 표기를 그대로(gross exposure · long/short leg · winsorize · lookback), 우리 지표는 정본 표기를 그대로(PORT_t · Calmar · MDD · OOS retention). 뜻이 통해도 조어면 읽는 사람이 두 번 해석한다.",
  "_배열 규약": "undeclared_changes·signal_mismatch 는 **발견만** 담는다. 없으면 빈 배열 [] 로 두고 '불일치 없음' 같은 비발견을 항목으로 넣지 마라 - 근거 게이트가 배열 길이로 선다.",
  "note": "1~2줄"
}

## 금지
- %s 밖 쓰기. 엔진 수정. 백테스트 실행. 등급·성과 수치 선언(계약이 낸다).
- 원문을 못 읽은 채 faithful/adapted 로 적는 것.
- 네 축 파일 말고 다른 파일을 쓰는 것.

축 파일을 쓰고 1줄로 판정만 보고하라.""" % (
        os.environ['AXB'], ax['title'], ax.get('tier',''), ax['focus'], ax['counterexample'],
        os.environ['PURL'], htmlline, W, W, A, out, k, W)
    pf = "%s/.audit_prompt_%s.txt" % (W, k)
    io.open(pf, 'w', encoding='utf-8', newline='').write(p)
    rows.append("\t".join([k, ax['model'], ax['effort'], pf, out]))
io.open(os.environ['PLAN'], 'w', encoding='utf-8', newline='').write("\n".join(rows) + "\n")
print("axes=%d" % len(rows))
PYEOF
[ -s "$PLAN" ] || { jl halt_no_plan; exit 0; }
NAX=$(grep -c . "$PLAN")
jl start "paper=$PKEY" "wdir=$WDIR" "axes=$NAX" "html=$HTMLU"

# ── 병렬 실행 ────────────────────────────────────────────────────────────────
# ★한 축이 죽어도 나머지는 간다. 죽은 축은 파일이 없고, 병합기가 그걸 unverifiable 로
#   **명시적으로** 센다 — 조용히 빠지는 축이 없다는 것이 이 설계의 요점이다.
# ★무인 LLM 단일 진입(P0-M1 2026-09-24) — 축마다 rf_llm_agent_run(AutoMem 차단·무인 표식)을 거친다.
#   모델·노력 = 축 계획 값(M/E · rf_fidelity_axes.json) — 서브셸 안에서 LLM_MODEL/LLM_EFFORT 로 넘긴다.
#   구판과 같이 축 레인엔 폴백을 싣지 않는다(LLM_FALLBACK_MODEL 비움).
_RFLE="$ROOT/02_Infrastructure/ops/rf_llm_env.sh"
[ -f "$_RFLE" ] || _RFLE="$(dirname "${BASH_SOURCE[0]:-$0}")/rf_llm_env.sh"
. "$_RFLE"
PIDS=""
while IFS=$'\t' read -r K M E PF OUT; do
  [ -n "${K:-}" ] || continue
  rm -f "$OUT"
  (
    LLM_MODEL="$M"; LLM_EFFORT="$E"; LLM_FALLBACK_MODEL=""; LLM_FALLBACK_EFFORT=""
    rf_llm_agent_run "$PF" "$LOG.$K.run" "${QVEST_FA_TIMEOUT:-1800}" \
      --permission-mode acceptEdits \
      --allowed-tools "Read,Write,Glob,Grep,WebFetch,WebSearch" \
      --disallowed-tools "Bash,Agent,Edit" \
      --add-dir "$WDIR"
    _arc=$LLM_RC
    cat "$LOG.$K.run" >> "$LOG.$K" 2>/dev/null
    rm -f "$LOG.$K.run" "$LOG.$K.run.primary"
    echo "[axis $K] rc=$_arc model=$M" >> "$LOG"
  ) &
  PIDS="$PIDS $!"
done < "$PLAN"
for p in $PIDS; do wait "$p" 2>/dev/null; done
jl agents_done "axes=$NAX"

for f in "$LOG".*; do
  [ -f "$f" ] || continue
  if grep -qiE "OAuth access token has expired|Failed to authenticate|API Error: 401" "$f" 2>/dev/null; then
    jl halt_auth_expired "hint=claude 재인증 필요"; exit 2; fi
  cat "$f" >> "$LOG"; rm -f "$f"
done

# ── 병합 — fa_merge (위 정의). 실패 = exit 3 (호출자 audit.sh 는 exec 라 그대로 verify 에 전파된다) ──
fa_merge; exit $?
