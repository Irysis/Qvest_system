#!/usr/bin/env bash
#==============================================================================
# judge_run.sh — 무인 Judge(PIT 전담) 1건 (2026-11-15 · 도훈 "A가 나오면 바로 judge로 가게 배선해줘" · A-ROUTE-IMMEDIATE-JUDGE-20261115)
#   호출 = a_route_tick.sh(nohup 배경 · 예약 작업 환경 — 무인 인증 · PATH 상속 · 레인 슬롯과 같은 띄우기).
#   인자 = A 자격 관문을 통과한 산출 폴더(judge_request.eligible.json · status pending).
#   모델 = 06_Registry/a_router.json judge_model · judge_effort(정의 .claude/agents/judge.md model: fable) — Fable 한도면 rf_llm_env.sh 가
#   llm.fable_limit_fallback(opus)으로 처음부터 한 번 다시 돈다. 판결 산출에 실제 모델을 적게 한다.
#   표식: <폴더>/.judge_running.json(시작 · pid) → 끝나면 .judge_done.json(rc · 모델 · 판결 유무) · 원장 06_Registry/a_route_ledger.jsonl.
#   시험: QVEST_JR_DRY=1 — 프롬프트만 쓰고 claude 를 부르지 않는다(표식 · 원장 무기록).
#==============================================================================
set -u
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"; ROOT="${ROOT//\\//}"; cd "$ROOT" || exit 2
D="${1:?usage: judge_run.sh <산출 폴더>}"; D="${D//\\//}"; D="${D%/}"
[ -f "$D/judge_request.eligible.json" ] || { echo "[judge_run] 트리거 없음: $D/judge_request.eligible.json"; exit 2; }
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
CFG="$ROOT/06_Registry/a_router.json"
LEDGER="$ROOT/06_Registry/a_route_ledger.jsonl"
LOGD="$ROOT/.cache/scheduler_logs"; mkdir -p "$LOGD"
TS=$(date +%Y%m%d_%H%M%S); B=$(basename "$D"); LOG="$LOGD/judge_run_${TS}_${B}.log"
cfgv() { "$PY" -X utf8 -c "import json,sys
c=json.load(open(sys.argv[1],encoding='utf-8')); v=c.get(sys.argv[2])
print('' if v is None else (str(v).lower() if isinstance(v,bool) else v))" "$CFG" "$1" 2>/dev/null | tr -d '\r'; }
jw() {  # $1 = 파일 · 나머지 = key=value — JSON 객체 한 줄(원자 쓰기)
  local f="$1"; shift
  "$PY" -X utf8 -c "import json,sys,os
f=sys.argv[1]; d={}
for kv in sys.argv[2:]:
    k,_,v=kv.partition('='); d[k]=v
t=f+'.tmp'; open(t,'w',encoding='utf-8',newline='\n').write(json.dumps(d,ensure_ascii=False)+'\n'); os.replace(t,f)" "$f" "$@"
}
la() {  # 원장 한 줄
  "$PY" -X utf8 -c "import json,sys,time
d={'schema':'a_route_v1','at':time.strftime('%Y-%m-%dT%H:%M:%S%z')}
for kv in sys.argv[2:]:
    k,_,v=kv.partition('='); d[k]=v
open(sys.argv[1],'a',encoding='utf-8',newline='\n').write(json.dumps(d,ensure_ascii=False)+'\n')" "$LEDGER" "$@"
}
REL="${D#"$ROOT"/}"
MODEL=$(cfgv judge_model); EFFORT=$(cfgv judge_effort); TMO=$(cfgv judge_timeout_s)
_RFLE="$ROOT/02_Infrastructure/ops/rf_llm_env.sh"; . "$_RFLE"
rf_llm_resolve judge "${MODEL:-fable}" "${EFFORT:-max}"
PF="$LOGD/judge_prompt_${TS}_${B}.md"
cat > "$PF" <<EOF
너는 Judge(PIT 전담) 에이전트다. 다음 두 파일을 처음부터 끝까지 읽고 그 정의대로만 일하라: .claude/agents/judge.md · 02_Infrastructure/prompts/judge_init.md

- 트리거: $REL/judge_request.eligible.json (schema judge_request_v2 · status pending · A 자격 관문 통과)
- 대상 산출 폴더: $REL — 권위 기록 authoritative_remeasure.json · 선택 현실 점검 selection_reality_check.json · a_route.json(라우팅 근거 · 시행 집합)
- 이 실행은 무인 A 라우터(06_Registry/a_router.json · 결정 A-ROUTE-IMMEDIATE-JUDGE-20261115)가 띄웠다. 대화 상대가 없다 — 묻지 말고 판결까지 마쳐라.
- 판결 산출(judge_verdict.json · schema judge_verdict_v2 · 산출 폴더 + stage_artifacts/judge/ 사본)에 실제로 쓴 모델을 적어라(1차 $LLM_MODEL/$LLM_EFFORT · 한도 폴백 ${LLM_FALLBACK_MODEL:-없음}).
- 재현 검증처럼 무거운 측정을 돌리기 전에 \`python -X utf8 02_Infrastructure/ops/mem_gate.py judge_run\` 이 rc 0 인지 본다. rc 1 이면 10분씩 기다렸다 다시 본다(최대 3시간 — 넘으면 재현을 돌리지 못한 사유를 판결에 적는다).
- 등급 재채점 · 전략 수정 · 판정 규칙 변경 금지(judge.md). 텔레그램은 judge.md 규칙의 1건(tg_agent_brief(agent="Judge", ...))뿐이다.
EOF
if [ "${QVEST_JR_DRY:-0}" = "1" ]; then
  echo "[judge_run] 드라이런 — 프롬프트 $PF · 모델 $LLM_MODEL/$LLM_EFFORT · 폴백 ${LLM_FALLBACK_MODEL:-없음} · 대상 $REL"; exit 0
fi
WINPID=$(cat /proc/$$/winpid 2>/dev/null)
jw "$D/.judge_running.json" "pid=$$" "winpid=${WINPID:-}" "started_at=$(date -Iseconds)" "model=$LLM_MODEL" "effort=$LLM_EFFORT" "log=${LOG#"$ROOT"/}"
la "event=judge_start" "artifacts=$REL" "pid=$$" "model=$LLM_MODEL" "log=${LOG#"$ROOT"/}"
echo "== $(date '+%F %T') Judge 시작 — $REL · $LLM_MODEL/$LLM_EFFORT · 폴백 ${LLM_FALLBACK_MODEL:-없음}" >> "$LOG"
rf_llm_agent_run "$PF" "$LOG.run" "${TMO:-10800}" \
  --permission-mode acceptEdits \
  --allowed-tools "Read,Write,Glob,Grep,Bash" \
  --disallowed-tools "Agent,Edit,WebFetch,WebSearch,Skill,Workflow,CronCreate,RemoteTrigger" \
  --add-dir "$ROOT"
RC=$LLM_RC
cat "$LOG.run" >> "$LOG" 2>/dev/null; rm -f "$LOG.run" "$LOG.run.primary"
V=0; [ -f "$D/judge_verdict.json" ] && V=1
jw "$D/.judge_done.json" "rc=$RC" "finished_at=$(date -Iseconds)" "model_used=${LLM_USED_MODEL:-$LLM_MODEL}" "fell_back=${LLM_FELL_BACK:-0}" "verdict=$V" "log=${LOG#"$ROOT"/}"
rm -f "$D/.judge_running.json"
la "event=judge_done" "artifacts=$REL" "rc=$RC" "verdict=$V" "model_used=${LLM_USED_MODEL:-$LLM_MODEL}" "fell_back=${LLM_FELL_BACK:-0}"
echo "== $(date '+%F %T') Judge 끝 — rc $RC · 판결 파일 $V · 모델 ${LLM_USED_MODEL:-$LLM_MODEL}" >> "$LOG"
exit 0
