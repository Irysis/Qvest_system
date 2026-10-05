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
# ★허용 함수 목록 (도훈 결정 B09-ALLOWLIST-PROMPT 2026-09-25): probe ③d 목록(06_Registry/overlay_probe_allowlist.json)을
#   프롬프트에 싣는다(렌더 = probe 적재기 · 사본 없음). 목록 미제공이면 LLM 을 부르지 않는다(산출이 반드시 거부된다).
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
CFG="$ROOT/06_Registry/reinforce_auto_config.json"
# ★jlog 싱크는 QVEST_RP_JLOG 로 돌린다 (2026-09-04: 검사 픽스처가 운영 로그에 design_rejected 60·audit_rejected 44건을 박았다)
JLOG="${QVEST_RP_JLOG:-$ROOT/.cache/reinforce_auto_log.jsonl}"
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
# ★v10.4 2026-09-17: **레인 몫만** 센다 — source 가 overlay_propose 이거나 필드가 없는(구판) 기록.
#   세션 수동 등재·B5 설계 레인의 방출은 자기 source 를 달고 실리므로 이 레인의 하루 예산을 먹지 않는다.
#   세는 코드는 rf_overlay_ledger_count.py 한 벌 — 검사가 같은 파일을 태운다(인라인 사본 금지).
N_TODAY=$("$PY" "$ROOT/02_Infrastructure/ops/rf_overlay_ledger_count.py" "$LEDG" 2>/dev/null | tr -d '\r' || echo 0)
[ -n "$N_TODAY" ] || N_TODAY=0
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

# ── 허용 함수 목록 (도훈 결정 B09-ALLOWLIST-PROMPT 2026-09-25 19시 · 06_Registry/decision_register.json) ─────────────
#   probe ③d(R3R)는 06_Registry/overlay_probe_allowlist.json(동결) 밖의 이름을 전부 거부한다 — 프롬프트가 목록을 모르면
#   흔한 함수 하나로 arm 을 버린다(R3R 빌드 노트: 공통 arm 하나 뺀 목록으로 그 arm 을 재면 17/23 통과). 렌더 = probe 자신의
#   적재기(overlay_allowlist_prompt.R → overlay_probe_allowlist_params · 사본 파서 없음) — 목록이 바뀌면 다음 실행 프롬프트가 따라간다.
#   ★미제공(적재기·레지스트리 부재·손상·스키마·능력 계열 오염) = LLM 을 부르지 않고 멈춘다: 이 레인의 산출은 새 arm 하나뿐이고
#     probe 가 그 arm 을 반드시 거부한다 — 부르면 모델 한도와 일간 방출 몫만 태운다. 생성이 없었으니 방출 원장에도 쓰지 않는다.
#   목록은 파일로 받는다(stdout 에는 적재 잡음이 섞일 수 있다) · 이 런 전용 경로(claim 이 직렬화한다) · 판정 = rc 0 ∧ 비지 않음 ∧ 'allowlist: ok'.
ALLOW_TXT="$LOG.allow"; rm -f "$ALLOW_TXT"
AOUT=$(Rscript "$ROOT/02_Infrastructure/reinforcement/overlay_allowlist_prompt.R" "$ALLOW_TXT" "$ROOT" 2>&1); ALRC=$?
printf '%s\n' "$AOUT" >> "$LOG"
AL_LINE=$(printf '%s\n' "$AOUT" | tr -d '\r' | grep '^allowlist:' | tail -1)
if [ "$ALRC" -ne 0 ] || [ ! -s "$ALLOW_TXT" ] || [ "${AL_LINE#allowlist: ok}" = "$AL_LINE" ]; then
  rm -f "$ALLOW_TXT"
  jl halt_allowlist_unavailable "rc=$ALRC" "why=${AL_LINE:-렌더러 출력 없음}" "action=$ACT" "state=$ST" "note=probe ③d 가 새 arm 을 전부 거부하는 상태 — LLM 미호출"
  exit 0
fi
ALLOW=$(tr -d '\r' < "$ALLOW_TXT"); rm -f "$ALLOW_TXT"
jl allowlist_rendered "line=$AL_LINE"
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
- 허용 목록 밖 이름 금지: 아래 목록에 없는 함수 호출·참조 이름·pkg:: 접두는 등재에서 자동 거부된다(파서가 전수 대조).

${ALLOW}

## 본보기
${ADIR}/dbeta_tilt.R 를 읽어라 — 계약과 문체의 기준이다.

파일 2개를 쓰고 무엇을 구현했는지 1~2줄로만 보고하라."

# ★모델·노력수준은 설정의 llm 블록이 정본이다 (2026-09-04) — 네 레인이 각자 기본값을
#   들고 있으면 한 곳을 바꿔도 나머지가 그대로 남는다. 환경변수는 그대로 최우선.
. "$ROOT/02_Infrastructure/ops/rf_llm_env.sh"
rf_llm_resolve overlay_propose "${QVEST_OV_MODEL:-}" "${QVEST_OV_EFFORT:-}"
RP_MODEL="$LLM_MODEL"
RP_EFFORT="$LLM_EFFORT"
jl model_selected "model=$RP_MODEL" "effort=$RP_EFFORT" "kind=$KIND"
# ★프롬프트는 stdin 으로 (2026-09-04): argv 로 넘기면 Windows 인자 상한(32K)에 걸려 에이전트가 안 뜰다 — 승격 entry B1 설계 재료 41KB 실사고.
PF="$ADIR/prompt_${KIND}.txt"
printf %s "$PROMPT" > "$PF"
# ★무인 LLM 단일 진입(P0-M1 2026-09-24) — rf_llm_agent_run 이 AutoMem 차단·무인 표식을 싣고
#   --model/--effort 는 위 rf_llm_resolve 값(LLM_MODEL=RP_MODEL · LLM_EFFORT=RP_EFFORT)을 쓴다.
#   QVEST_ARM_GEN=1 은 함수 호출 앞 임시 대입 — bash 는 함수 실행 동안 자식(claude·훅)에게 내보낸다(성과 열람 차단 훅의 표식).
#   이번 실행 출력 = $LOG.this (구판과 같은 파일 · 폴백이면 1차 출력 = $LOG.this.primary).
#   폴백 미탑재(LLM_FALLBACK_MODEL="" · 구판 동작 보존): 구판도 --fallback-model 없이 떴고 이 레인엔
#   반쪽 산출물 청소 훅(rf_llm_before_fallback)이 없다 — 폴백 확대는 청소 훅과 함께 별도 결정.
#   (P0-M2 2026-09-25) PowerShell 금지 추가 — 성과 열람 차단 훅의 matcher 는 Read|Grep|Glob 이라 셸 도구는 훅이 못 본다.
#   Bash 만 막고 PowerShell 을 열어 둔 것이 실제 구멍이었다(09-25 transcript: 생성 세션 PowerShell 56회 시도 · 14회 통과).
#   (P0-M2 수리 2026-09-25 · B-1) 셸 통로 전부 금지 = CLI 2.1.261 이 enablesCodeExecution 으로 표시한 내장 도구 7종
#   (Bash·PowerShell·Monitor·REPL·Workflow·CronCreate·RemoteTrigger). Monitor 는 셸 명령을 돌려 출력을 이벤트로 돌려준다 —
#   충실도 감사 세션(25caa112 · 09-17)이 Bash 금지 아래서 Monitor 로 diff 를 돌렸다. 훅 matcher(Read|Grep|Glob) 밖이라 막는 곳은 여기뿐.
QVEST_ARM_GEN=1 LLM_FALLBACK_MODEL="" rf_llm_agent_run "$PF" "$LOG.this" 1800 \
  --permission-mode acceptEdits \
  --allowed-tools "Read,Write,Edit,Glob,Grep" \
  --disallowed-tools "Bash,PowerShell,Monitor,REPL,Workflow,CronCreate,RemoteTrigger,Agent,WebFetch,WebSearch" \
  --add-dir "$ADIR"
RC=$LLM_RC
[ -f "$LOG.this.primary" ] && { cat "$LOG.this.primary" >> "$LOG"; rm -f "$LOG.this.primary"; }
cat "$LOG.this" >> "$LOG"; jl agent_done "rc=$RC" "kind=$KIND"

# ★이 런의 출력만 본다 — 어제의 401 이 오늘 다시 발화하지 않게
if grep -qE "OAuth access token has expired|Failed to authenticate|API Error: 401|Invalid API key" "$LOG.this" 2>/dev/null; then
  jl halt_auth_expired "hint=claude 재인증 필요 — 리서치 실패 아님"; rm -f "$LOG.this"; exit 2
fi
rm -f "$LOG.this"

[ -s "$ADIR/$KIND.R" ] || { jl no_arm_file "kind=$KIND"; exit 1; }

# ── ★G1 적대 감사 경유 (결정 D-G 2026-09-23 "overlay_propose 는 G1 경유 또는 dead 동안 정지" 의 성과 비소비 분기 · 2026-09-25) ────
#   구판은 등재기(rf_overlay_admit) 안의 probe 만 지나 하루 1 arm 을 등재했다(감사 D5-F2 — G1 없이 등재). B5 설계 레인은 이미
#   probe → G1(rf_overlay_audit.sh · 설계자와 다른 모델 · 축 정본 rf_overlay_adversary_axes.json) → 등재를 지난다(b5_design.note).
#   같은 감사기 · 같은 판정 규약(마지막 줄 'audit:' · rc 0 pass · 3 reject · 그 밖 unavailable)을 여기에도 건다.
#   ① probe 먼저(기계 검사 · 백테 0) — 떨어질 arm 에 감사 비용을 쓰지 않는다. probe 실패면 감사를 건너뛰고 등재기가 같은 probe 로
#      거부·기록한다(구판과 같은 방출 원장 기록). ② G1 reject/unavailable = 등재 금지 · 방출 원장에 admitted=false(stage=audit|audit_unavailable)
#      · arm 파일 제거(B5 레인과 같은 처분 — 미판정도 등재하지 않는다). ③ pass 만 등재기로 간다.
#   kill switch = config overlay_propose_g1.enabled=false(구판 흐름 · 로그). 키가 없거나 설정을 못 읽으면 감사를 건다(막는 쪽).
#   ★Rscript -e 는 한 줄 · R 코드 안에 파이프 문자 금지(Windows 에서 명령이 잘린다 — 실측 rc 255) — probe 줄 구분자는 '~'.
G1_EN=$("$PY" -c "
import json,io
try:
    v=(json.load(io.open(r'$CFG',encoding='utf-8')).get('overlay_propose_g1') or {}).get('enabled',True)
    print('False' if v is False else 'True')
except Exception: print('True')" 2>/dev/null || echo True)
if [ "$G1_EN" = "True" ]; then
  POUT="$LOG.probe_${KIND}"
  QM_ROOT="$ROOT" QVEST_OV_KIND="$KIND" Rscript -e 'suppressMessages(invisible(capture.output(source(file.path(Sys.getenv("QM_ROOT"), "02_Infrastructure/reinforcement/overlay_probe.R"))))); k <- Sys.getenv("QVEST_OV_KIND"); pr <- tryCatch(overlay_probe_arm(k, Sys.getenv("QM_ROOT")), error = function(e) list(ok = FALSE, reason = conditionMessage(e))); cat(sprintf("probe: %s ~ %s ~ %s\n", k, if (isTRUE(pr$ok)) "pass" else "fail", gsub("[[:cntrl:]]+", " ", paste(pr$reason, collapse = " ")))); quit(status = if (isTRUE(pr$ok)) 0L else 3L)' > "$POUT" 2>&1
  PR_RC=$?
  PR_LINE=$(tr -d '\r' < "$POUT" | grep '^probe:' | tail -1); cat "$POUT" >> "$LOG"; rm -f "$POUT"
  if [ "$PR_RC" -eq 0 ]; then
    AUDIT_SH="${QVEST_OV_AUDIT_SH:-$ROOT/02_Infrastructure/ops/rf_overlay_audit.sh}"
    AOUT="$LOG.audit_${KIND}"
    QVEST_RF_ROOT="$ROOT" QM_ROOT="$ROOT" QVEST_OA_ARMDIR="$ADIR" bash "$AUDIT_SH" "$KIND" > "$AOUT" 2>&1
    A_RC=$?
    A_LINE=$(tr -d '\r' < "$AOUT" | grep '^audit:' | tail -1); cat "$AOUT" >> "$LOG"; rm -f "$AOUT"
    if [ "$A_RC" -ne 0 ]; then
      if [ "$A_RC" -eq 3 ]; then G1_STAGE=audit; else G1_STAGE=audit_unavailable; fi
      QM_ROOT="$ROOT" QVEST_OV_KIND="$KIND" QVEST_OV_ACT="$ACT" QVEST_OV_ST="$ST" QVEST_OV_MODEL="$RP_MODEL" QVEST_OV_STAGE="$G1_STAGE" QVEST_OV_REASON="${A_LINE:-G1 rc=$A_RC}" Rscript -e 'suppressMessages(invisible(capture.output(source(file.path(Sys.getenv("QM_ROOT"), "02_Infrastructure/reinforcement/rf_overlay_admit.R"))))); invisible(rf_overlay_record_emission(Sys.getenv("QVEST_OV_KIND"), target = list(action = Sys.getenv("QVEST_OV_ACT"), state = Sys.getenv("QVEST_OV_ST")), n_siblings = 1L, generator_model = Sys.getenv("QVEST_OV_MODEL"), root = Sys.getenv("QM_ROOT"), source = "overlay_propose", stage = Sys.getenv("QVEST_OV_STAGE"), reason = Sys.getenv("QVEST_OV_REASON")))' >> "$LOG" 2>&1 \
        || jl emission_record_failed "kind=$KIND" "stage=$G1_STAGE"
      jl admit_rejected_g1 "kind=$KIND" "rc=$A_RC" "stage=$G1_STAGE" "verdict=${A_LINE:-}" "note=G1 미통과 — 등재하지 않는다(방출 원장 admitted=false)"
      rm -f "$ADIR/$KIND.R" "$ADIR/$KIND.arm.json"
      exit 0
    fi
    jl g1_pass "kind=$KIND" "verdict=${A_LINE:-pass}"
  else
    jl g1_skipped_probe_fail "kind=$KIND" "rc=$PR_RC" "probe=${PR_LINE:-}" "note=probe 실패 — 감사 생략 · 등재기가 같은 probe 로 거부·기록"
  fi
else
  jl g1_disabled "kind=$KIND" "note=config overlay_propose_g1.enabled=false — 구판 흐름(probe 만)"
fi

# ★반드시 스크립트 파일로 부른다 — 여러 줄 `Rscript -e` 는 Windows 에서 rc=139 로 죽는다.
#   실측(2026-09-03): 이 자리에서 죽었고, 인프라 오류인데 아래 정리가 arm 을 지워버렸다.
#   6번째 인자 = 방출 출처(source). 이 레인의 방출만 일간 상한에 든다 — 명시해 둔다(기본값에 기대지 않는다).
Rscript "$ROOT/02_Infrastructure/ops/rf_overlay_admit_cli.R" "$KIND" "$ACT" "$ST" "$RP_MODEL" 1 overlay_propose >> "$LOG" 2>&1
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
