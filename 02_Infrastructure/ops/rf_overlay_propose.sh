#!/usr/bin/env bash
#==============================================================================
# rf_overlay_propose.sh — 오버레이 arm 생성 레인 (v10.2 2026-09-03 · Phase 3)
#
# 흐름: 포화 감지(미측정 칸 있음?) → claude -p 헤드리스 → 오프라인 probe → 등재
# ★생성기는 성과를 보지 않는다: 프롬프트에 성과 수치가 없고(rf_target_brief 축약본),
#   세션은 QVEST_ARM_GEN=1 로 돌아 arm_gen_read_guard 가 측정 산출물 Read/Grep 을 막는다.
# ★기존 레인의 알려진 결함 2종은 복제하지 않는다:
#   (a) auth grep 이 일간 로그 전체를 훑어 오전 401 이 오후에 재발화 → 이 런의 로그만 본다
#   (b) 죽은 알림 heredoc → 알림은 jl 이벤트로만 남긴다
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
CFG="$ROOT/06_Registry/reinforce_auto_config.json"
JLOG="$ROOT/.cache/reinforce_auto_log.jsonl"
LEDG="$ROOT/06_Registry/overlay_arm_ledger.jsonl"
CLAIM="$ROOT/.cache/rf_overlay_propose.claim"
TODAY=$(date +%Y%m%d)
LOG="$ROOT/.cache/scheduler_logs/overlay_propose_${TODAY}.log"
mkdir -p "$(dirname "$LOG")" "$(dirname "$JLOG")"
: > "$LOG.this"          # ★이 런의 출력만 따로 — auth 판정이 어제 로그를 다시 읽지 않게

jl() { local ev="$1"; shift
  "$PY" -c "
import json,sys,datetime
d={'ts':datetime.datetime.now().astimezone().isoformat(timespec='seconds'),'event':sys.argv[1],'src':'overlay_propose'}
for kv in sys.argv[2:]:
    k,_,v=kv.partition('='); d[k]=v
open(r'$JLOG','a',encoding='utf-8').write(json.dumps(d,ensure_ascii=False)+'\n')" "$ev" "$@" 2>/dev/null || true
  echo "[ov_propose] $ev $*"; }

ENABLED=$("$PY" -c "
import json,io
try: print(json.load(io.open(r'$CFG',encoding='utf-8')).get('enabled',False))
except Exception: print(False)" 2>/dev/null || echo False)
[ "$ENABLED" = "True" ] || { jl halt_disabled; exit 0; }

# 하루 1건 — 원장에서 오늘 방출 수를 센다(별도 카운터를 만들지 않는다)
N_TODAY=$("$PY" -c "
import io,json,datetime
d=datetime.date.today().isoformat(); n=0
try:
    for ln in io.open(r'$LEDG',encoding='utf-8'):
        ln=ln.strip()
        if not ln: continue
        r=json.loads(ln)
        if r.get('record_type')=='arm_emission' and str(r.get('emitted_at','')).startswith(d): n+=1
except FileNotFoundError: pass
print(n)" 2>/dev/null || echo 0)
CAP="${QVEST_OV_DAILY_CAP:-1}"
[ "$N_TODAY" -lt "$CAP" ] || { jl halt_daily_cap "n=$N_TODAY" "cap=$CAP"; exit 0; }

command -v claude >/dev/null 2>&1 || { jl halt_no_claude_cli; exit 0; }
mkdir "$CLAIM" 2>/dev/null || { jl halt_claimed; exit 0; }
echo $$ > "$CLAIM/owner"
trap 'rm -rf "$CLAIM"' EXIT

# ── 표적 — 미포화 칸이 없으면 부르지 않는다(포화는 결함이 아니라 절단점) ─────
# ★Rscript -e 는 반드시 한 줄 (개행 들어가면 Windows 에서 rc=139) · R 문자열 안 파이프 금지
#   · QM_ROOT 는 export 해야 자식이 루트를 찾는다. 셋 다 실측으로 죽어본 자리다.
export QM_ROOT="$ROOT"
RMAP='suppressMessages(source(file.path(Sys.getenv("QM_ROOT"), "02_Infrastructure/reinforcement/rf_mechanism_map.R")))'
TG=$(Rscript -e "$RMAP; tg <- rf_next_target(); if (is.null(tg)) cat(\"NONE\") else cat(paste(tg\$action, tg\$state, tg\$n_measured, sep=\"~\"))" 2>/dev/null | tail -1)
[ -n "$TG" ] && [ "$TG" != "NONE" ] || { jl halt_all_saturated; exit 0; }
ACT="${TG%%~*}"; REST="${TG#*~}"; ST="${REST%%~*}"
jl target_picked "action=$ACT" "state=$ST"

BRIEF=$(Rscript -e "$RMAP; cat(rf_target_brief())" 2>/dev/null)
ADIR="$ROOT/02_Infrastructure/reinforcement/overlay_arms"
KIND="gen_$(date +%Y%m%d_%H%M%S)"

PROMPT="리스크 오버레이 arm 하나를 새로 구현하라. 산출은 파일 2개다.

## 표적 (기전 지도가 지목한 미측정 칸)
action = ${ACT}   — 포트폴리오에 무엇을 하는가
state  = ${ST}    — 무엇을 보고 반응하는가

현재 기전 지도(측정 횟수와 포화 여부만. 성과 수치는 주지 않는다):
${BRIEF}

## 산출 (이것만)
1. ${ADIR}/${KIND}.R
   함수 하나: overlay_expo_${KIND} <- function(H, t, ctx)
   반환 = 스칼라 e (0~1)  또는  data.table(Ticker, e) — 종목별 노출.
   ★표적 action 이 cross_sectional 이면 **반드시 종목별 표**를 돌려줘야 한다.
     스칼라만 내면 처치가 전달되지 않아 등재에서 거부된다.
2. ${ADIR}/${KIND}.arm.json
   {\"id\":\"<고유id>\",\"family\":\"<계열>\",\"basis\":\"<방법 근거 1~3문장>\",\"est_cost_min\":8}
   basis 는 비면 거부된다. 무엇을 어떻게 추정하는지 적어라.

## 입력 계약
H = 월별 특징 확장창 (t 행까지만 존재. 미래 행 없음).
  열: Date, rv20, rv60, rv120, dd, r252, nav, ew1..ew10, xs, fwd
  ★H\$fwd 의 t 행은 **익월 수익 = 신호일에 미실현**이다. 절대 읽지 마라(학습에 쓰려면 t-1 이하만).
ctx = list(t, date, v_now, tgt, n_min, hold)
  ctx\$hold = 그 달 보유 종목의 확장창 상태 data.table:
    Ticker, beta, dbeta(하방베타), ovol(자체 변동성), bcorr(시장 상관), n_obs
  보유가 없으면 NULL 일 수 있다 — 그때는 1 을 돌려라.

## 절대 금칙
- 임의 상수 문턱 금지: H 나 hold 의 열을 숫자 리터럴과 직접 비교하지 마라
  (H\$dd[t] > 0.2 같은 형태는 자동 거부된다). 문턱은 quantile/median/ecdf 등
  **확장창 추정**으로 그 시점 데이터에서 뽑아라.
- 성과 필드 참조 금지: 소스에 sharpe, calmar, essence_score, bt_result, port_t 같은
  단어를 쓰지 마라(주석 포함). 등재 스캐너가 거부한다.
- 추정 불가·표본 부족이면 e <- 1 (무개입) 으로 떨어져라. 오류를 던지지 마라.
- ${ADIR} 밖에 쓰지 마라.

## 본보기
${ADIR}/dbeta_tilt.R 를 읽어라 — 계약과 문체의 기준이다.

파일 2개를 쓰고 무엇을 구현했는지 1~2줄로만 보고하라."

RP_MODEL="${QVEST_OV_MODEL:-opus}"; RP_EFFORT="${QVEST_OV_EFFORT:-max}"
jl model_selected "model=$RP_MODEL" "effort=$RP_EFFORT" "kind=$KIND"
QVEST_ARM_GEN=1 timeout 1800 claude -p "$PROMPT" \
  --model "$RP_MODEL" --effort "$RP_EFFORT" \
  --permission-mode acceptEdits \
  --allowed-tools "Read,Write,Edit,Glob,Grep" \
  --disallowed-tools "Bash,Agent,WebFetch,WebSearch" \
  --add-dir "$ADIR" >> "$LOG.this" 2>&1
RC=$?
cat "$LOG.this" >> "$LOG"; jl agent_done "rc=$RC" "kind=$KIND"

# ★이 런의 출력만 본다 — 어제의 401 이 오늘 다시 발화하지 않게
if grep -qE "OAuth access token has expired|Failed to authenticate|API Error: 401|Invalid API key" "$LOG.this" 2>/dev/null; then
  jl halt_auth_expired "hint=claude 재인증 필요 — 리서치 실패 아님"; rm -f "$LOG.this"; exit 2
fi
rm -f "$LOG.this"

[ -s "$ADIR/$KIND.R" ] || { jl no_arm_file "kind=$KIND"; exit 1; }

# ★반드시 스크립트 파일로 부른다 — 여러 줄 `Rscript -e` 는 Windows 에서 rc=139 로 죽는다.
#   실측(2026-09-03): 이 자리에서 죽었고, 인프라 오류인데 아래 정리가 arm 을 지워버렸다.
Rscript "$ROOT/02_Infrastructure/ops/rf_overlay_admit_cli.R" "$KIND" "$ACT" "$ST" "$RP_MODEL" 1 >> "$LOG" 2>&1
ARC=$?
if [ "$ARC" -eq 0 ]; then
  jl admitted "kind=$KIND" "action=$ACT" "state=$ST"
elif [ "$ARC" -eq 3 ]; then
  # 등재기가 실제로 돌고 거부했다 — 원장엔 방출 기록이 남았으므로 파일만 치운다.
  jl admit_rejected "kind=$KIND" "rc=$ARC"
  rm -f "$ADIR/$KIND.R" "$ADIR/$KIND.arm.json"
else
  # ★인프라 오류(등재기가 못 돌았다)에는 arm 을 지우지 않는다 — 판정되지 않은 산출을
  #   실패로 처리하면 다음 tick 이 같은 칸을 다시 생성해 예산만 태운다.
  jl admit_infra_error "kind=$KIND" "rc=$ARC" "note=arm 보존 — 판정 안 됨"
fi
exit 0
