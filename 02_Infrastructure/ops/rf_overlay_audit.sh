#!/usr/bin/env bash
#==============================================================================
# rf_overlay_audit.sh — 오버레이 arm **G1 적대적 설계시점 감사** (v10.4 2026-09-17)
#
# 무엇: probe(기계 검사)가 못 재는 세 가지 — 룩어헤드·probe 회피 / 위장 비타이밍·전표본 문턱 / 활성 arm 과의
#   행동 중복 — 를 설계자와 **다른 모델**이 코드를 읽고 반례로 입증한다. 축 정본 = 06_Registry/rf_overlay_adversary_axes.json.
#   축은 순차로 돈다(가장 단순한 형태 — 축 3개 · 축당 상한 1200초). 병합은 R(rf_overlay_audit_merge.R · 결정론)이 한다:
#   근거를 파일에서 재도출해 실재하는 발견만 채택한다. 진술은 증거가 아니다.
#
# 사용: bash rf_overlay_audit.sh <kind>
#   → <out>/<kind>/axis_<id>.json (감사자가 씀) · lane_status.json (이 스크립트) · audit.json (병합기)
#   → 마지막 줄에 판정 출력 · 종료 0 pass · 3 reject · 4 unavailable(호출자는 등재 금지 — 재실행 사유)
# 재지정(검사·샌드박스): QVEST_OA_AXES · QVEST_OA_CATALOG · QVEST_OA_ARMDIR · QVEST_OA_OUT · QVEST_OA_TIMEOUT ·
#   QVEST_OA_MODEL/QVEST_OA_EFFORT(최우선) · QVEST_RF_CONFIG · QVEST_RP_JLOG · QVEST_OA_LOG · RF_CLAUDE_BIN(가짜 claude)
# ★알려진 결함을 복제하지 않는다: auth·한도 판정은 **이번 실행 출력**만 본다(그날 로그 전체 X) · 알림은 jl 이벤트로만.
# ★아직 어느 레인에도 배선되지 않았다 — B5 설계 레인/rf_overlay_propose.sh 는 별도 패키지가 잇는다.
#==============================================================================
set -uo pipefail
ROOT="${QVEST_RF_ROOT:-${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}}"
ROOT="${ROOT//\\//}"          # 역슬래시 QM_ROOT 가 R 리터럴에 들어가면 '\U' 이스케이프로 죽는다(fanout 실사고)
# POSIX 형(/c/…)은 Windows 형으로 — jl() 의 파이썬이 -c 코드 안에 박힌 /c/… 를 못 연다(세션 셸에서 QM_ROOT=$PWD 로 기동한 경우)
case "$ROOT" in /[A-Za-z]/*) command -v cygpath >/dev/null 2>&1 && ROOT=$(cygpath -m "$ROOT") ;; esac
cd "$ROOT" || exit 4
export QM_ROOT="$ROOT"
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
AXES="${QVEST_OA_AXES:-$ROOT/06_Registry/rf_overlay_adversary_axes.json}"
CATALOG="${QVEST_OA_CATALOG:-$ROOT/06_Registry/overlay_catalog.json}"
ADIR="${QVEST_OA_ARMDIR:-$ROOT/02_Infrastructure/reinforcement/overlay_arms}"
OUT_ROOT="${QVEST_OA_OUT:-$ROOT/.cache/rf_overlay_audit}"
TMO="${QVEST_OA_TIMEOUT:-1200}"
JLOG="${QVEST_RP_JLOG:-$ROOT/.cache/reinforce_auto_log.jsonl}"
LOG="${QVEST_OA_LOG:-$ROOT/.cache/scheduler_logs/overlay_audit_$(date +%Y%m%d).log}"
mkdir -p "$(dirname "$LOG")" "$(dirname "$JLOG")"
export QVEST_OA_AXES="$AXES" QVEST_OA_CATALOG="$CATALOG" QVEST_OA_ARMDIR="$ADIR" QVEST_OA_OUT="$OUT_ROOT"

KIND="${1:-}"
[ -n "$KIND" ] || { echo "usage: rf_overlay_audit.sh <kind>"; exit 4; }
ODIR="$OUT_ROOT/$KIND"
mkdir -p "$ODIR"

jl() { local ev="$1"; shift
  "$PY" -c "
import json,sys,datetime
d={'ts':datetime.datetime.now().astimezone().isoformat(timespec='seconds'),'event':sys.argv[1],'src':'overlay_audit'}
for kv in sys.argv[2:]:
    k,_,v=kv.partition('='); d[k]=v
open(r'$JLOG','a',encoding='utf-8').write(json.dumps(d,ensure_ascii=False)+'\n')" "$ev" "$@" 2>/dev/null || true
  echo "[ov_audit] $ev $*" | tee -a "$LOG" >/dev/null; }

# ── 병합 (R · 결정론). 검사가 QVEST_OA_MERGE_ONLY=1 로 이 단계만 분리 실행한다 ──────────────
oa_merge() {
  local line rc mo="$ODIR/.merge.out"
  # ★종료 코드는 파일 경유로 받는다 — $(…) 안의 파이프라인 PIPESTATUS 는 바깥 셸에서 못 읽는다
  Rscript "$ROOT/02_Infrastructure/ops/rf_overlay_audit_merge.R" "$KIND" > "$mo" 2>>"$LOG"; rc=$?
  line=$(tr -d '\r' < "$mo" | tail -1); rm -f "$mo"
  case "$rc" in 0|3|4) ;; *) line="audit: $KIND | unavailable | 병합기 실행 실패 rc=$rc"; rc=4 ;; esac
  jl merge_done "kind=$KIND" "rc=$rc"
  echo "$line"
  return "$rc"
}
if [ "${QVEST_OA_MERGE_ONLY:-0}" = "1" ]; then oa_merge; exit $?; fi

# ── 이전 실행 잔재 제거 — 낡은 축 파일이 이번 판정에 섞이면 안 된다 ──────────────────────
rm -f "$ODIR"/axis_*.json "$ODIR"/lane_status.json "$ODIR"/audit.json
STATUS_TSV="$ODIR/.lane_status.tsv"; : > "$STATUS_TSV"
write_status() {   # axis rc model_used effort fell_back env_failure
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >> "$STATUS_TSV"; }
finalize_status() {
  KIND="$KIND" TSV="$STATUS_TSV" OUT="$ODIR/lane_status.json" "$PY" - <<'PYEOF'
import io, json, os, time
axes = {}
for ln in io.open(os.environ['TSV'], encoding='utf-8'):
    p = ln.rstrip('\n').split('\t')
    if len(p) < 6: continue
    axes[p[0]] = {'rc': p[1], 'model_used': p[2], 'effort': p[3], 'fell_back': p[4] == '1', 'env_failure': p[5]}
io.open(os.environ['OUT'], 'w', encoding='utf-8').write(json.dumps(
    {'kind': os.environ['KIND'], 'ran_at': time.strftime('%Y-%m-%dT%H:%M:%S%z'), 'axes': axes}, ensure_ascii=False, indent=1))
PYEOF
  rm -f "$STATUS_TSV"
}

[ -s "$ADIR/$KIND.R" ] || { jl halt_no_arm "kind=$KIND" "path=$ADIR/$KIND.R"; finalize_status; oa_merge; exit $?; }

# ── 축별 프롬프트 조립 (등록부에서 — 셸에 축을 박지 않는다) ─────────────────────────────
PLAN="$ODIR/.audit_plan.tsv"; rm -f "$PLAN"
AXES="$AXES" ADIR="$ADIR" KIND="$KIND" CATALOG="$CATALOG" ODIR="$ODIR" PLAN="$PLAN" "$PY" - <<'PYEOF'
import io, json, os
A = json.load(io.open(os.environ['AXES'], encoding='utf-8'))
axes = A['axes']; schema = json.dumps(A.get('output_schema', {}), ensure_ascii=False, indent=2)
ADIR, KIND, ODIR = os.environ['ADIR'], os.environ['KIND'], os.environ['ODIR']
arm_path = os.path.join(ADIR, KIND + '.R')
meta_path = os.path.join(ADIR, KIND + '.arm.json')
arm_lines = io.open(arm_path, encoding='utf-8', errors='replace').read().splitlines()
numbered = "\n".join("%4d | %s" % (i + 1, l) for i, l in enumerate(arm_lines))
meta_txt = io.open(meta_path, encoding='utf-8', errors='replace').read() if os.path.exists(meta_path) else "(없음 — <kind>.arm.json 부재)"
try: self_id = json.loads(meta_txt).get('id', '')
except Exception: self_id = ''
cat_lines = []
try:
    C = json.load(io.open(os.environ['CATALOG'], encoding='utf-8'))
    for a in C.get('arms', []):
        if a.get('status') != 'active' or a.get('id') == self_id or a.get('kind') == KIND: continue
        p = os.path.join(ADIR, str(a.get('kind', '')) + '.R')
        loc = p if os.path.exists(p) else '(엔진 내장 arm — 02_Infrastructure/reinforcement/rf_cell_engine.R 의 .ov_kind 분기)'
        cat_lines.append("- id=%s · kind=%s · family=%s · action=%s · state=%s\n  basis: %s\n  코드: %s" % (
            a.get('id'), a.get('kind'), a.get('family'), a.get('action', '?'), a.get('state', '?'),
            (a.get('basis') or '')[:200], loc))
except Exception as e:
    cat_lines.append("(카탈로그를 못 읽었다: %s)" % e)
catalog_block = "\n".join(cat_lines) if cat_lines else "(활성 arm 없음)"

contract = """## arm 계약 (엔진 = 02_Infrastructure/reinforcement/rf_cell_engine.R 의 오버레이 사슬)
- 함수: overlay_expo_%s(H, t, ctx) → 스칼라 e ∈ [0,1] 또는 data.table(Ticker, e). 추정 불가 시 1(무개입).
- H = 월별 특징 **확장창** — t 행까지만 존재한다. 열: Date, i, rv20, rv60, rv120, dd, r252, nav, ew1..ew10, xs, fwd.
  전부 KOSPI200 벤치마크 계열에서 파생된 시장 상태다(rv = 실현변동성 창, dd = 낙폭, r252 = 12개월 수익, nav = 누적, xs = 횡단면분산).
  ★H$fwd 의 t 행 = 익월 수익 = 신호일에 **미실현**. t 행을 읽으면 누출이다. shift(…, type="lead")·tail·전체 열 통계도 같다.
- ctx = list(t, date, v_now, tgt, n_min, hold, strict)
  t = 행 색인 · date = 신호일(월말 거래일) · v_now = H$rv60[t] · tgt = 자기 이력 중앙 rv60 · n_min = 표본 하한 ·
  hold = 그 달 보유 종목의 확장창 상태 data.table(Ticker, beta, dbeta(하방베타), ovol(자체변동성), bcorr(시장상관), n_obs) — 없으면 NULL ·
  strict = PIT 엄격 모드 플래그(있으면 TRUE/FALSE).
- 홀딩월 = ctx$date 의 **익월**. 집행 = 익월 첫 거래일.

## PIT 요약 (.claude/rules/pit.md — 절대 규칙)
- C5: 오버레이 신호는 **홀딩월 시작일(익월 1일) 이전** 데이터로만 계산·적용한다. 컷오프 = 익월 1일 미만.
- C11: 외부 데이터의 시간축(공표 시차·as-of)을 검증한다 — 파일에 있다고 그 날 알려진 정보가 아니다.
- C15: 팩터 DB 는 load_month_factors() 단일 경유. parquet 직접 load 금지.
- C1: 전표본 통계 금지 — rolling/expanding 만. H 위의 통계는 정상(H 는 t 행까지), H 밖 원천의 전기간 통계는 위반.
- probe 픽스처(overlay_probe.R): 2006-01-31 기점 240개월 합성 · 종목 T001~T025 · n_obs 3000 · 위기 2구간 주입.
  합성에서 무개입이고 실데이터에서만 켜지는 조건 = probe 회피.
""" % KIND

rows = []
for ax in axes:
    k = ax['id']; out = os.path.join(ODIR, "axis_%s.json" % k)
    dup_block = ""
    if k == 'duplicate':
        dup_block = "\n## 활성 카탈로그 arm (대조 대상 — 각 .R 파일을 열어 결정 규칙을 읽어라)\n" + catalog_block + "\n"
    p = "".join([
        "너는 **적대적 검증자**다. 아래 오버레이 arm 이 등재되면 안 된다는 것을 **입증하라.**\n",
        "너에게 배정된 축은 **하나뿐**이다 — 그 축만 본다. 다른 축은 다른 검증자가 보고 있다.\n\n",
        "## 네 축: %s\n%s\n\n### 이 축에서 할 일\n%s\n\n**반례를 구성하라.** %s\n\n" % (ax['title'], "/".join(ax.get('finding_types', [])), ax['focus'], ax.get('counterexample', '')),
        "## 페르소나 — 감정을 배제한 철저한 비평가\n",
        "- **인상은 판정이 아니다.** 모든 발견은 **행 번호와 그 행의 코드 인용**으로 뒷받침하라. 병합기(R)가 파일을 다시 읽어 인용이 그 행에 실재하는지 확인한다 — 실재하지 않는 근거는 버려진다.\n",
        "- **관대함은 미덕이 아니다.** 넘어간 누출은 등급 인플레로 돌아오고, 그 뒤엔 BOOK 이 있다.\n",
        "- **가혹함도 미덕이 아니다.** 근거 없는 기각은 감사가 아니라 잡음이다 — 병합기가 버리므로 판정에 아무 영향이 없다.\n",
        "- **설계자의 의도를 추측하지 마라.** 코드가 **하는 일**만 기술하라. basis 문장은 대조 대상이지 증거가 아니다.\n",
        "- **네 축에서 아무것도 못 찾는 것은 정상이고 정직한 결과다.** 빈 findings 로 pass 를 내라.\n",
        "- **네 축 밖의 것을 보고하지 마라.**\n\n",
        "## 대상 arm: %s\n### %s (행 번호는 파일의 실제 행 — evidence 에 이 번호를 쓴다)\n```r\n%s\n```\n\n### %s.arm.json\n```json\n%s\n```\n\n" % (KIND, KIND + '.R', numbered, KIND, meta_txt),
        contract, dup_block,
        "\n## 산출 (이것만) — 아래 파일 하나를 Write 로 써라\nAUDIT_OUTPUT_FILE=%s\n스키마:\n%s\n" % (out, schema),
        "- type 은 이 축의 finding_types(%s) 중 하나. evidence 는 `%s.R:<행> <그 행의 코드 인용 그대로>` — 여러 위치면 `;` 로 잇는다.\n" % ("/".join(ax.get('finding_types', [])), KIND),
        "- duplicate 는 duplicate_of 에 위 목록의 **활성 id 를 정확히** 적는다(그 밖은 null).\n",
        "- verdict 는 findings 가 비어 있으면 pass, 하나라도 있으면 reject 로 적는다. 판정은 병합기가 채택된 발견으로 다시 낸다.\n",
        "- findings 에 비발견('이상 없음')을 항목으로 넣지 마라 — 빈 배열로 둔다.\n\n",
        "## 금지\n- 산출 파일 말고 다른 파일 쓰기 · arm 수정 · 백테스트 실행 · 성과 수치 언급.\n",
        "- 원문(파일)을 읽지 않고 판정하는 것.\n\n축 파일을 쓰고 1줄로 판정만 보고하라.\n"])
    pf = os.path.join(ODIR, "prompt_%s.txt" % k)
    io.open(pf, 'w', encoding='utf-8', newline='').write(p)
    rows.append("\t".join([k, ax.get('model', ''), ax.get('effort', ''), pf, out]))
io.open(os.environ['PLAN'], 'w', encoding='utf-8', newline='').write("\n".join(rows) + "\n")
print("axes=%d" % len(rows))
PYEOF
[ -s "$PLAN" ] || { jl halt_no_plan "kind=$KIND"; finalize_status; oa_merge; exit $?; }
NAX=$(grep -c . "$PLAN")
jl start "kind=$KIND" "axes=$NAX"

# ── 실행 — 순차. 모델·노력수준은 설정(llm.lanes.overlay_audit) < 축별 < 환경변수 ─────────────
. "$ROOT/02_Infrastructure/ops/rf_llm_env.sh"
CLAUDE_BIN="${RF_CLAUDE_BIN:-claude}"
if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  jl halt_no_claude_cli "kind=$KIND"
  while IFS=$'\t' read -r K M E PF OUT <&3; do [ -n "${K:-}" ] && write_status "$K" "" "" "" 0 "no_claude_cli"; done 3< "$PLAN"
  finalize_status; oa_merge; exit $?
fi
HALT=""
while IFS=$'\t' read -r K M E PF OUT <&3; do
  [ -n "${K:-}" ] || continue
  if [ -n "$HALT" ]; then write_status "$K" "" "" "" 0 "$HALT"; continue; fi
  rm -f "$OUT"
  rf_llm_resolve overlay_audit "${QVEST_OA_MODEL:-$M}" "${QVEST_OA_EFFORT:-$E}"
  RUN_OUT="$ODIR/run_${K}.out"
  rf_llm_agent_run "$PF" "$RUN_OUT" "$TMO" \
    --permission-mode acceptEdits \
    --allowed-tools "Read,Glob,Grep,Write" \
    --disallowed-tools "Bash,Agent" \
    --add-dir "$ODIR"
  RC=$LLM_RC
  ENV_FAIL=""
  # ★이번 실행 출력만 본다 — 어제의 401·한도가 오늘 다시 발화하지 않게
  if grep -qE "OAuth access token has expired|Failed to authenticate|API Error: 401|Invalid API key" "$RUN_OUT" 2>/dev/null; then
    ENV_FAIL="auth_expired"; HALT="auth_expired_earlier_axis"
    jl halt_auth_expired "kind=$KIND" "axis=$K" "hint=claude 재인증 필요 — 리서치 판정 아님"
  elif rf_llm_limit_hit "$RUN_OUT"; then
    ENV_FAIL="limit"; jl env_failure_limit "kind=$KIND" "axis=$K" "model=$LLM_USED_MODEL" "fell_back=$LLM_FELL_BACK"
  fi
  write_status "$K" "$RC" "$LLM_USED_MODEL" "$LLM_USED_EFFORT" "$LLM_FELL_BACK" "$ENV_FAIL"
  cat "$RUN_OUT" >> "$LOG" 2>/dev/null
  jl axis_done "kind=$KIND" "axis=$K" "rc=$RC" "model=$LLM_USED_MODEL" "effort=$LLM_USED_EFFORT" "fell_back=$LLM_FELL_BACK" "out=$([ -s "$OUT" ] && echo 1 || echo 0)"
done 3< "$PLAN"
finalize_status

# ── 병합 — 판정 1줄 출력 + 종료 0/3/4 ─────────────────────────────────────────────────
oa_merge; exit $?
