#!/usr/bin/env bash
# paper_atlas_run.sh — 메커니즘 지도 추출 무인 레인 (v10.01 · 2026-10-13 도훈 지시 "논문 최신화 등 지속가능하게")
#
# 흐름: 일감(ma_pending — 프로그램 재료 큐 중 지도에 없는 논문) → claude -p(추출 · 스테이징 1파일)
#       → R 검증기(mechanism_atlas.R --ingest)가 검사 통과분만 지도에 합친다. LLM 은 지도를 쓰지 않는다.
# 게이트: QVEST_PAPER_ATLAS_ENABLE=1 일 때만 돈다(기본 꺼짐 — 라우터와 같은 규약).
# 상한: QVEST_PAPER_ATLAS_MAX(기본 5편/런). 자기 락(PID 생존 판정)으로 중복 실행을 막는다.
# 모델: 설정 정본 06_Registry/reinforce_auto_config.json::llm.lanes.paper_atlas (rf_llm_resolve) — 개선안 §10.4
# 검사: 08_Tests/programs/test_paper_atlas_run.sh
set -uo pipefail
BASE="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
# R 은 POSIX 경로(/tmp/...)를 못 읽는다 — 혼합 형식(C:/...)으로 바꿔 넘긴다
command -v cygpath >/dev/null 2>&1 && BASE="$(cygpath -m "$BASE")"
ROOT="$BASE"
TODAY="$(date +%Y%m%d)"
LOG="$BASE/.cache/scheduler_logs/paper_atlas_${TODAY}.log"
mkdir -p "$(dirname "$LOG")"
log(){ echo "$(date '+%Y-%m-%dT%H:%M:%S') [paper_atlas] $*" | tee -a "$LOG"; }

if [ "${QVEST_PAPER_ATLAS_ENABLE:-0}" != "1" ]; then
  log "게이트 꺼짐(QVEST_PAPER_ATLAS_ENABLE!=1) — 건너뜀"
  exit 0
fi

LOCK="$BASE/.cache/paper_atlas.lock"
if [ -f "$LOCK" ]; then
  _pid="$(cat "$LOCK" 2>/dev/null | tr -d '\r' || true)"
  if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then log "다른 런 진행 중(PID $_pid) — 건너뜀"; exit 0; fi
  log "죽은 락 회수(PID ${_pid:-?})"
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

MAXN="${QVEST_PAPER_ATLAS_MAX:-5}"
WDIR="$BASE/stage_artifacts/paper_atlas/${TODAY}_$$"
mkdir -p "$WDIR"
JOB="$WDIR/job.json"; OUT="$WDIR/staging.json"

# 일감 — 지도에 없는 프로그램 재료(논문)
(cd "$BASE" && QM_ROOT="$BASE" Rscript 02_Infrastructure/programs/mechanism_atlas.R --pending "$MAXN" --root "$BASE") > "$JOB" 2>>"$LOG"
_n="$("${QVEST_PY:-python}" -c "import json,sys; print(len(json.load(open(sys.argv[1],encoding='utf-8'))))" "$JOB" 2>/dev/null || echo 0)"
_n="$(printf '%s' "$_n" | tr -d '\r')"
if [ "${_n:-0}" = "0" ]; then rm -rf "$WDIR"; log "일감 0편 — 종료"; exit 0; fi
log "일감 ${_n}편 → 추출 시작"

if [ "${QVEST_PAPER_ATLAS_DRYRUN:-0}" = "1" ]; then log "DRYRUN — claude 미호출 · 일감=$JOB"; exit 0; fi

. "$BASE/02_Infrastructure/ops/rf_llm_env.sh"
rf_llm_resolve paper_atlas "${QVEST_ATLAS_MODEL:-}" "${QVEST_ATLAS_EFFORT:-}"
CLAUDE_BIN="$(command -v claude || echo /c/Users/99922/AppData/Roaming/npm/claude)"
[ -x "$CLAUDE_BIN" ] || { log "claude CLI 없음 — 건너뜀"; exit 0; }
source "$BASE/02_Infrastructure/ops/_sched_failure_classify.sh" 2>/dev/null || true
command -v sched_resolve_oauth_token >/dev/null 2>&1 && sched_resolve_oauth_token >/dev/null 2>&1 || true

PF="$WDIR/prompt.txt"
printf 'JOB_FILE=%s\nOUT_FILE=%s\n\n%s\n' "$JOB" "$OUT" "$(cat "$BASE/02_Infrastructure/ops/paper_atlas_prompt.md")" > "$PF"
RF_CLAUDE_BIN="$CLAUDE_BIN" LLM_FALLBACK_MODEL="" \
  rf_llm_agent_run "$PF" "$WDIR/run.out" "${QVEST_RUN_TIMEOUT:-0}" --dangerously-skip-permissions
rc=$LLM_RC
cat "$WDIR/run.out" >> "$LOG" 2>/dev/null
log "claude -p exit=$rc · 모델 ${LLM_MODEL}/${LLM_EFFORT}"

if [ ! -s "$OUT" ]; then
  log "스테이징 산출 없음 — 지도 변경 0"
  command -v scheduler_alert >/dev/null 2>&1 && scheduler_alert "paper_atlas" "no_staging" "추출 레인이 스테이징 파일을 내지 않았다(rc=$rc). 로그: $LOG"
  exit 0
fi
(cd "$BASE" && QM_ROOT="$BASE" Rscript 02_Infrastructure/programs/mechanism_atlas.R --ingest "$OUT" --root "$BASE") >> "$LOG" 2>&1
log "검증 · 합치기 완료(rc=$?) — 상세는 위 [mechanism_atlas] 줄"
exit 0
