#!/bin/bash
# ★RETIRED (v10 2026-08-29 · 헤더 2026-09-03) — 무인 리서치 레인 퇴역: morning_run 에서 철거됐고
#   예약작업·bat 호출 0. 파일은 사료(08_Tests 가 경로로 직접 실행하므로 이동·삭제 금지).
#   재개 레시피 = git 태그 pre-v10-2layer 의 morning_run.sh [0.55]~[0.6] 구간.
# ★RETIRED (v10 2026-08-29 도훈): 무인은 수집까지만 — morning_run 배선 제거. 파일 사료 존치.
#   재개 레시피 = git pre-v10-2layer. (비-alpha 레인 폐지 — 수집은 팩터전략 단일 목적)
# factor_deep_recheck_run.sh — 2축 구조 tier-2 runner (도훈 mandate 2026-06-19).
# tier-1(paper_router_run.sh, 매일 보수적)이 uncertain으로 남긴 팩터 후보를 모아 *논문당 깊게* 재검 → testable 승격.
#
# 게이트:
#   QVEST_FACTOR_RECHECK_ENABLE=1  — 자체 on (기본 0=off)
#   uncertain 큐 비어있지 않음 (또는 QVEST_FACTOR_RECHECK_FORCE=1)
# 권장 스케줄: 주 1회(Task Scheduler). uncertain은 소량이라 매일 불요.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
BASE="${BASE:-${PROJECT:-$PWD}}"; cd "$BASE" || exit 1
TODAY=$(date +%Y%m%d)
SD="$BASE/stage_artifacts/paper_recharge"
LOG="$BASE/.cache/scheduler_logs/factor_recheck_${TODAY}.log"; mkdir -p "$(dirname "$LOG")"
log(){ echo "$(date -Iseconds) [recheck] $*" >> "$LOG"; }

if [ "${QVEST_FACTOR_RECHECK_ENABLE:-0}" != "1" ]; then log "disabled (QVEST_FACTOR_RECHECK_ENABLE!=1) — skip"; exit 0; fi

# 1) uncertain 큐 빌드 (route JSON들에서 수집 · dedup · 재검분 제외)
QUEUE="$SD/factor_recheck_queue_${TODAY}.json"
# (2026-07-26) bare `python3` = Windows Store 스텁 함정 — 빈 출력이 ${N:-0} 로 0 이 되어
#   "대기 없음" 정상 skip 으로 위장한다. 견고 해석 + 숫자 검사 후에만 신뢰.
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_sched_failure_classify.sh" 2>/dev/null || true
PYBIN=""
command -v sched_resolve_python >/dev/null 2>&1 && PYBIN=$(sched_resolve_python || true)
[ -n "$PYBIN" ] || PYBIN="python3"
# (2026-08-02 공용 모듈 승격) 술어 정본 = 02_Infrastructure/ops/research_pool_predicates.py.
#   구판은 이 자리에 heredoc 으로 술어를 직접 적었고, id 정규화 결함이
#   alpha_search_queue_run.sh 와 **독립으로 재발**했다(이쪽이 더 나빴다 — 표시가 아니라
#   실행 트리거라 끝난 논문에 매일 claude -p 토큰을 태웠다). 정의를 한 곳으로 모았다.
#   ★여기에 술어를 다시 적지 말 것.
#     배선 단언: 08_Tests/ops/test_factor_recheck_pending.py 가 이 호출의 존재를 매 실행 확인한다.
PRED="$BASE/02_Infrastructure/ops/research_pool_predicates.py"
N=$("$PYBIN" "$PRED" recheck-build "$SD" "$QUEUE" "$TODAY")
if command -v sched_assert_count >/dev/null 2>&1 && ! sched_assert_count "$N"; then
  log "★uncertain 산정 실패 (N='$N', PYBIN=$PYBIN) — 계측 사망. 0 으로 간주하지 않고 중단."
  command -v sched_alert_emit >/dev/null 2>&1 && sched_alert_emit "factor_recheck" "count_measurement_failed" \
    "uncertain 산정이 비숫자('$N') 반환 — python 인터프리터 해석 실패 추정(PYBIN=$PYBIN)."
  exit 0
fi
N="${N:-0}"
log "uncertain 큐: $N건 → $QUEUE (PYBIN=$(basename "$PYBIN"))"
if [ "$N" -eq 0 ] && [ "${QVEST_FACTOR_RECHECK_FORCE:-0}" != "1" ]; then
  log "uncertain 0 — skip (FORCE=1로 강제)"; exit 0
fi

# 2) 헤드리스 claude -p 심층 재검
CLAUDE_BIN="$(command -v claude || echo /c/Users/99922/AppData/Roaming/npm/claude)"
# ★모델·노력은 설정 정본(06_Registry/reinforce_auto_config.json::llm.lanes.factor_deep_recheck)에서 읽는다
#   (2026-09-23 도훈 지시 "무인실행에서 LLM 개입부 모두 opus max"). 구판은 --model/--effort 없이
#   CLI 기본값으로 돌아 레인 정책이 이 레인에 한 번도 닿지 않았다. 환경변수 QVEST_FDR_MODEL/QVEST_FDR_EFFORT 가 최우선.
ROOT="${ROOT:-$BASE}"
. "$BASE/02_Infrastructure/ops/rf_llm_env.sh"
rf_llm_resolve factor_deep_recheck "${QVEST_FDR_MODEL:-}" "${QVEST_FDR_EFFORT:-}"
# (P0-M1 2026-09-24) --model/--effort 는 아래 _run_claude → rf_llm_agent_run 이 LLM_MODEL/LLM_EFFORT 로 싣는다
#   (구 LANE_LLM_ARGS 배열 폐지 — 모델 인자가 두 벌이면 한쪽만 고쳐진다).
[ -x "$CLAUDE_BIN" ] || { log "claude CLI 없음 — skip"; exit 0; }
PF="$BASE/02_Infrastructure/ops/factor_deep_recheck_prompt.md"
[ -f "$PF" ] || { log "prompt 없음 — skip"; exit 0; }
# (2026-07-25) 공통 사유분류·경보 헬퍼 + 자격증명 사전 점검
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_sched_failure_classify.sh" 2>/dev/null || true
if command -v sched_check_credentials >/dev/null 2>&1; then
  CRED_ST=$(sched_check_credentials)
  case "$CRED_ST" in ok*|unknown) : ;; *)
    log "자격증명 사전점검 실패: $CRED_ST — claude 호출 생략"
    sched_alert_emit "factor_recheck" "credentials_${CRED_ST}" \
      "실행 전 차단 — $(sched_credentials_guidance "$CRED_ST")"
    exit 0
    ;;
  esac
fi
# (2026-07-26 도훈 지시) 사용률 기반 보류·감축 제거 — "한도소비 관련 제약·방어 조건 모두 없애.
#   한도 소비하면 재충전 후 내가 재개시킬게". 한도는 구독 외생 변수이지 게이트가 아니다
#   ([[feedback-spend-limit-external-not-gate]]). 실패 시 경보만 남기고 그대로 멈춘다.
log "start deep recheck (N=$N)"
PROMPT_TEXT="$(printf 'TODAY=%s\n\n%s\n' "$TODAY" "$(cat "$PF")")"
# -- (2026-08-22 수리) 자격 토큰을 **현재 셸에서** 확보한다 ------------------
#   실사고: 위 사전점검을 `CRED_ST=$(sched_check_credentials)` 로 부르는데 명령치환은
#   **서브셸**이라 그 안에서 일어난 CLAUDE_CODE_OAUTH_TOKEN export 가 부모로 오지 않는다.
#   결과 = 판정은 "ok" 인데 부모 셸 토큰은 unset -> claude 가 만료된 파일 자격으로 떨어져 401.
#   "사전점검은 통과했는데 실제 호출이 401" 이라는 관측이 정확히 이 자리였다
#   (2026-08-21 paper_router · 2026-08-22 mode_queue 재현. A/B 실증: env 토큰 있으면 OK,
#    없으면 파일 자격이 만료돼 401).
#   ★Task Scheduler 처럼 프로세스 env 에 User-scope 변수가 이미 실려 오는 컨텍스트에서는
#     증상이 안 난다 — 그래서 오래 잠복했다. Git Bash 등 env 가 빈 컨텍스트에서만 터진다.
#   ★토큰 값은 절대 로그로 내지 않는다.
command -v sched_resolve_oauth_token >/dev/null 2>&1 && sched_resolve_oauth_token >/dev/null 2>&1 || true
# ── (2026-08-22) 토큰 **지문** 한 줄 로깅 — 값이 아니라 sha256 앞 12자.
#   왜: 오늘 401 사고에서 "토큰이 만료된 것"인지 "배관이 토큰을 못 실은 것"인지
#   사후 구분이 **원리적으로 불가능**했다(두 세션이 그 구분에 시간을 썼다).
#   지문이 남으면 즉시 갈린다: 지문 없음 = 배관 실패 / 지문 있는데 401 = 진짜 만료.
#   ★sched_token_fingerprint 는 정의만 되고 호출자가 0건이었다 — 만들어두고 안 쓴 계기.
_tokfp="none"
command -v sched_token_fingerprint >/dev/null 2>&1 && _tokfp="$(sched_token_fingerprint 2>/dev/null || echo none)"
log "토큰 지문: ${_tokfp} (값 아님 · sha256 앞12자) — 401 시 이 줄로 만료/배관 구분"

# --- 무인 런 시간제한 (도훈 지시 2026-08-22 "시간제한 없애") ---------------
#   기본 = 제한 없음. QVEST_RUN_TIMEOUT=<초> 를 주면 그만큼 적용한다.
#   근거: 2026-08-22 18:13 실측 — 런이 WT-005 를 ALPHA_DONE 으로 올리고 alpha_package
#   (15KB)·certificate·validation 을 18:10 에 다 냈는데 18:13 에 상한이 죽였다.
#   상한이 자른 것은 폭주가 아니라 **끝난 일의 뒷정리**였고, 그 결과 자기보고와
#   원장 append 가 유실됐다(rc=124 로만 남음).
#   ★무한 정지 방지의 실질은 timeout 이 아니라 **자기 락**이다 — 락은 PID 를 적고
#   kill -0 로 생존을 확인하므로 죽은 런의 락은 다음 런이 회수한다.
# ★(P0-M1 2026-09-24) LLM 호출은 rf_llm_env.sh::rf_llm_agent_run 단일 진입을 거친다 — 그 안에서
#   AutoMem 차단(CLAUDE_CODE_DISABLE_AUTO_MEMORY=1)과 무인 표식(QVEST_UNATTENDED_LANE=1)이 claude 에 실린다.
#   인자: $1 = 모델 재지정(빈 값 = 위 rf_llm_resolve 값 · "opus" = 한도 폴백 재시도). 프롬프트 = $PROMPT_TEXT(stdin 파일).
#   시간제한 규약 불변: QVEST_RUN_TIMEOUT 미설정·0 = 무제한(timeout 0 = GNU 규약상 제한 없음) · 양수 = 그 초.
#   출력은 이번 실행 파일에 받아 $LOG 에 덧붙인다(구판 `>> $LOG` 와 같은 로그 내용 · 실행이 끝난 뒤 한 번에).
_run_claude(){
  local _model="${1:-${LLM_MODEL:-opus}}" _pf _rc
  # 폴백은 싣지 않는다(LLM_FALLBACK_MODEL 비움 · 구판 동작 보존 — 구판도 --fallback-model 없이 떴다).
  #   한도 폴백은 아래 spend_limit → `_run_claude opus` 재시도 한 벌이 맡는다(두 벌이면 한도 한 번에 세 번 뜬다).
  _pf="$(mktemp "${TMPDIR:-/tmp}/lane_prompt.XXXXXX")" || return 1
  printf '%s' "$PROMPT_TEXT" > "$_pf"
  RF_CLAUDE_BIN="$CLAUDE_BIN" LLM_MODEL="$_model" LLM_FALLBACK_MODEL="" \
    rf_llm_agent_run "$_pf" "$_pf.out" "${QVEST_RUN_TIMEOUT:-0}" --dangerously-skip-permissions
  _rc=$LLM_RC
  [ -f "$_pf.out.primary" ] && cat "$_pf.out.primary" >> "$LOG"
  cat "$_pf.out" >> "$LOG" 2>/dev/null
  rm -f "$_pf" "$_pf.out" "$_pf.out.primary"
  return "$_rc"
}

_run_claude ""
rc=$?
log "claude -p exit=$rc"
# (2026-07-26) 성공하면 해당 컴포넌트의 미해소 마커를 아카이브 — 사유 해소 후에도 마커가
#   남으면 다음 실패가 과거와 이어져 streak 을 부풀리고 가짜 격상을 낸다(삭제 아닌 이동).
if [ "$rc" -eq 0 ] && command -v sched_mark_resolved >/dev/null 2>&1; then
  _mv=$(sched_mark_resolved "factor_recheck" "$BASE/.cache/scheduler_alerts")
  [ -n "${_mv:-}" ] && log "해소: 미해소 마커 ${_mv}건 _resolved/ 로 아카이브"
fi
# (2026-07-25) 사유 분류 + 경보 배선. 종전엔 사유는 판정하면서 발송이 없어 실패가 조용히 묻혔다
#   (alpha/paper 는 경보 보유, 이 스크립트만 미보유 — 07-25 전수 점검서 적발).
if [ "$rc" -ne 0 ]; then
  if command -v sched_classify_failure >/dev/null 2>&1; then
    reason=$(sched_classify_failure "$rc" "$LOG")
  else
    reason="exit_${rc}"
    tail -n 30 "$LOG" 2>/dev/null | grep -qi "spend limit" && reason="spend_limit"
  fi
  # (2026-07-24 도훈 승인 C8) Fable 한도 폴백 — spend_limit 감지 시 --model opus 1회 재시도 (07-14 정책)
  if [ "$reason" = "spend_limit" ]; then
    log "spend_limit 감지 — --model opus 폴백 재시도"
    _run_claude opus
    rc=$?; log "fallback(opus) exit=$rc"
    [ "$rc" -ne 0 ] && reason="spend_limit_fallback_exit_${rc}"
  fi
  if [ "$rc" -ne 0 ] && command -v sched_alert_emit >/dev/null 2>&1; then
    _ann=$(sched_failure_annotate "factor_recheck" "$reason" "$BASE/.cache/scheduler_alerts")
    sched_alert_emit "factor_recheck" "$reason" \
      "claude -p exit=$rc (N=$N) | ${_ann}"
  fi
fi
exit 0
