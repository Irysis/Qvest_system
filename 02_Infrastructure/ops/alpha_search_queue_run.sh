#!/bin/bash
# ★RETIRED (v10 2026-08-29 · 헤더 2026-09-03) — 무인 리서치 레인 퇴역: morning_run 에서 철거됐고
#   예약작업·bat 호출 0. 파일은 사료(08_Tests 가 경로로 직접 실행하므로 이동·삭제 금지).
#   재개 레시피 = git 태그 pre-v10-2layer 의 morning_run.sh [0.55]~[0.6] 구간.
# ★v10 (2026-08-29): 무인 morning_run 배선 제거 — 세션 수동 도구로만 존치 (무인은 수집까지).
#   내부의 게이트 루프(lean_verify_build→auto_alpha_gate→append-done)는 수동 실행 시 유효.
# alpha_search_queue_run.sh — 팩터추출 → alpha-search 모드 가동 (마지막 고리, 도훈 mandate 2026-06-19).
# tier-1/tier-2가 alpha_search_queue에 쌓은 testable 팩터를 읽어 alpha-search를 실제 구동(5층 검증게이트).
# 기존 끊김: tier-1 autorun은 *그 패스서 발견한* testable만 즉석 실행 → 큐(tier-2 승격분·오버플로)는 소비자 없어 미실행.
#
# 게이트:
#   QVEST_ALPHA_QUEUE_ENABLE=1     — 자체 on (기본 0)
#   pending(큐 testable − done) > 0 (또는 QVEST_ALPHA_QUEUE_FORCE=1)
# 옵션: QVEST_ALPHA_QUEUE_MAX=N (1런 자동실행 상한, 기본 2).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
BASE="${BASE:-${PROJECT:-$PWD}}"; cd "$BASE" || exit 1
TODAY=$(date +%Y%m%d)
SD="$BASE/stage_artifacts/paper_recharge"
LOG="$BASE/.cache/scheduler_logs/alpha_queue_${TODAY}.log"; mkdir -p "$(dirname "$LOG")"
log(){ echo "$(date -Iseconds) [alpha_queue] $*" >> "$LOG"; }

# ── v3(2026-07-10) 침묵 정지 경보 (paper_router_run.sh와 동일 패턴, fail-soft):
#    마커 먼저 기록 → tg_agent_brief() 경유 텔레그램 시도. 같은 (component, reason) 1일 1회 스로틀.
scheduler_alert(){
  local comp="$1" reason="$2" detail="$3"
  local adir="$BASE/.cache/scheduler_alerts"; mkdir -p "$adir"
  local marker="$adir/${comp}_${reason}_${TODAY}.alert"
  if [ -f "$marker" ]; then log "alert throttle: ${comp}/${reason} 오늘 이미 발보 — skip"; return 0; fi
  {
    echo "ts=$(date -Iseconds)"
    echo "component=$comp"
    echo "reason=$reason"
    echo "detail=$detail"
    echo "log=$LOG"
  } > "$marker"
  log "alert marker 기록: $marker"
  # (2026-07-26) 무인 선언(QVEST_UNATTENDED=1)이 없는 실행은 마커만 남기고 텔레그램 생략.
  #   실사고: 토큰 없는 개발 셸에서 수동 실행 시 정상 차단이 도훈 텔레그램 오경보로 전달됨.
  if command -v sched_alert_should_send >/dev/null 2>&1 && ! sched_alert_should_send; then
    log "alert telegram skip: 무인 선언 없음 — 마커만 보존. 발송하려면 QVEST_ALERT_FORCE=1"
    return 0
  fi
  local RS_BIN
  RS_BIN="$(command -v Rscript || echo '/c/Program Files/R/R-4.5.2/bin/Rscript')"
  [ -x "$RS_BIN" ] || { log "alert telegram skip: Rscript 없음 (마커는 보존)"; return 0; }
  # (2026-07-25) R 문자열 리터럴 주입 가드: Windows 역슬래시 경로를 R 이 유니코드 이스케이프로
  #   오해해(C:\Users → '\U' used without hex digits) 텔레그램만 조용히 죽던 잠복 버그.
  #   마커는 남으므로 더 안 보인다. 주입 전 역슬래시 → 슬래시 정규화.
  #   ⚠ ${v//\\//} 형태는 이 셸에서 '/' 를 지우고 '\' 를 남긴다(실측) — tr 로만 처리할 것.
  local LOG_R detail_R
  LOG_R=$(printf '%s' "$LOG" | tr '\\' '/')
  detail_R=$(printf '%s' "$detail" | tr '\\' '/')
  local rfile="$adir/_tg_alert_${comp}_${TODAY}.R"
  cat > "$rfile" <<RS
suppressWarnings(suppressMessages({
  root <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
  source(file.path(root, "02_Infrastructure", "telegram", "telegram_notify.R"))
}))
res <- tryCatch(tg_agent_brief(
  agent = "Q-Lead",
  title = "무인 스케줄러 경보 — ${comp}",
  relaxed = TRUE, force = TRUE,
  lock_scope = "sched_alert_${comp}_${reason}_${TODAY}",
  sections = list(
    list(type = "summary", emoji = "\U0001F6A8",
         body = "무인 파이프라인 ${comp} 가 ${reason} 사유로 정지했습니다. 수동 확인 필요."),
    list(type = "bullet", emoji = "\U0001F4A1", heading = "조치 안내",
         items = c("큐 pending은 보존되어 다음 성공 런에서 자동 재처리됩니다",
                   "spend limit 등 외부 구독 한도는 월 리셋 시 자동 해소 — 무인 런이 차기 사이클 자동 재시도")),
    list(type = "kv", emoji = "\U0001F4CB", heading = "상세",
         kv = list("구성요소" = "${comp}",
                   "사유" = "${reason}",
                   "내용" = "${detail_R}",
                   "로그" = "${LOG_R}"))
  )
), error = function(e) { cat("tg fail:", conditionMessage(e), "\n"); NULL })
RS
  LC_ALL='English_United States.utf8' "$RS_BIN" "$rfile" >> "$LOG" 2>&1 \
    || log "alert telegram 발송 실패 (마커는 보존): $marker"
}

if [ "${QVEST_ALPHA_QUEUE_ENABLE:-0}" != "1" ]; then log "disabled (QVEST_ALPHA_QUEUE_ENABLE!=1) — skip"; exit 0; fi

# pending 카운트: 큐 candidates + route testable − done
# (2026-07-26) bare `python3` 는 PATH 에 python312 가 없는 컨텍스트에서 Windows Store 스텁으로
#   해석돼 빈 출력을 낸다 → 구 `N="${N:-0}"` 가 이를 0 으로 삼켜 "대기 없음" 정상 skip 으로 위장.
#   실측: 스텁 경로 N=0 / 참값 3. ★총계 0 = 계측 사망일 수 있으므로 숫자 검사 후에만 신뢰한다.
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_sched_failure_classify.sh" 2>/dev/null || true
PYBIN=""
command -v sched_resolve_python >/dev/null 2>&1 && PYBIN=$(sched_resolve_python || true)
[ -n "$PYBIN" ] || PYBIN="python3"
# (2026-08-02 공용 모듈 승격) 술어 정본 = 02_Infrastructure/ops/research_pool_predicates.py.
#   구판은 이 자리에 heredoc 으로 술어를 **직접 적었다**. 같은 술어를 factor_deep_recheck_run.sh ·
#   paper_research_dispatch.R · research_pool_status.py 가 각자 다시 적었고, 그래서 같은 결함이
#   소비자 수만큼 독립 재발했다(08-02 하루 3건). 도훈 사전등록 조건("세 번째 소비자가 나타나면
#   공용 모듈 승격 재판정")이 부팅 리더 등장으로 발효 → 정의를 한 곳으로 모았다.
#   ★여기에 술어를 다시 적지 말 것 — 재분기가 이번 결함들의 원인이다.
#     배선 단언: 08_Tests/ops/test_alpha_queue_pending.py 가 이 호출의 존재를 매 실행 확인한다.
PRED="$BASE/02_Infrastructure/ops/research_pool_predicates.py"
#     ★stderr 를 로그로 — 2026-08-23 사고에서 두 러너가 같은 원장 파손으로 죽었는데
#       mode_queue 만 원인(LEDGER_UNREADABLE …:1063)을 알 수 있었던 이유가 이 리다이렉트다.
# ── 계측은 공용 헬퍼 경유 (2026-08-24 v9.2 S1c, _sched_failure_classify.sh).
#    사유별 재시도: 원장 파손은 재시도 0회(5초 뒤에도 깨져 있다) · 일시 실패만 10s/20s 2회.
#    ★"0 으로 읽지 않고 중단"은 그대로다 — 헬퍼는 그 판정에 **파일명이 든 이름**을 붙일 뿐이다.
if command -v sched_measure_pending >/dev/null 2>&1; then
  N=$(sched_measure_pending "$PYBIN" "$PRED" alpha-pending "$SD" 2>>"$LOG")
  _mrc=$?
else
  N=$("$PYBIN" "$PRED" alpha-pending "$SD" 2>>"$LOG"); _mrc=$?
  sched_assert_count "$N" 2>/dev/null || _mrc=1
fi
# ★계측 사망을 0 으로 삼키지 않는다 — 숫자가 아니면 skip 이 아니라 경보 후 중단.
if [ "${_mrc:-1}" -ne 0 ]; then
  _mreason=$(sched_measure_reason 2>/dev/null || echo count_measurement_failed)
  _mdetail=$(sched_measure_detail 2>/dev/null)
  log "★pending 산정 실패 (N='$N', 사유=$_mreason, PYBIN=$PYBIN) — 계측 사망. 0 으로 간주하지 않고 중단."
  scheduler_alert "alpha_queue" "$_mreason" \
    "${_mdetail:-pending 산정이 비숫자('$N') 반환(PYBIN=$PYBIN). 큐가 조용히 skip 되는 것을 막기 위해 중단.}"
  exit 0
fi
N="${N:-0}"
log "pending testable(큐+route−done): $N (PYBIN=$(basename "$PYBIN"))"
if [ "$N" -eq 0 ] && [ "${QVEST_ALPHA_QUEUE_FORCE:-0}" != "1" ]; then
  log "pending 0 — skip (FORCE=1로 강제)"; exit 0
fi

CLAUDE_BIN="$(command -v claude || echo /c/Users/99922/AppData/Roaming/npm/claude)"
# ★모델·노력은 설정 정본(06_Registry/reinforce_auto_config.json::llm.lanes.alpha_search_queue)에서 읽는다
#   (2026-09-23 도훈 지시 "무인실행에서 LLM 개입부 모두 opus max"). 구판은 --model/--effort 없이
#   CLI 기본값으로 돌아 레인 정책이 이 레인에 한 번도 닿지 않았다. 환경변수 QVEST_ASQ_MODEL/QVEST_ASQ_EFFORT 가 최우선.
ROOT="${ROOT:-$BASE}"
. "$BASE/02_Infrastructure/ops/rf_llm_env.sh"
rf_llm_resolve alpha_search_queue "${QVEST_ASQ_MODEL:-}" "${QVEST_ASQ_EFFORT:-}"
LANE_LLM_ARGS=(--model "$LLM_MODEL" --effort "$LLM_EFFORT")
[ -x "$CLAUDE_BIN" ] || { log "claude CLI 없음 — skip"; exit 0; }
PF="$BASE/02_Infrastructure/ops/alpha_search_queue_prompt.md"
[ -f "$PF" ] || { log "prompt 없음 — skip"; exit 0; }
MAXA="${QVEST_ALPHA_QUEUE_MAX:-2}"
# (2026-07-26 도훈 지시) 사용률 기반 보류·감축 제거 — "한도소비 관련 제약·방어 조건 모두 없애.
#   한도 소비하면 재충전 후 내가 재개시킬게". 한도는 구독 외생 변수이지 게이트가 아니다
#   ([[feedback-spend-limit-external-not-gate]]). 실패 시 경보만 남기고 그대로 멈춘다.
log "start alpha-search queue (pending=$N, MAX_ALPHA=$MAXA)"
PROMPT_TEXT="$(printf 'TODAY=%s  MAX_ALPHA=%s\n\n%s\n' "$TODAY" "$MAXA" "$(cat "$PF")")"
# (2026-07-25) 자격증명 사전 점검 — 실패하고 나서 알리지 말고 미리 알린다.
#   실사고: refreshToken 이 빈 문자열이라 자동 갱신 불가 → 401 로 8일(07-19~26) 무인 정지.
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_sched_failure_classify.sh" 2>/dev/null || true
if command -v sched_check_credentials >/dev/null 2>&1; then
  CRED_ST=$(sched_check_credentials)
  case "$CRED_ST" in ok*|unknown) : ;; *)
    log "자격증명 사전점검 실패: $CRED_ST — claude 호출 생략(무의미한 401 회피)"
    scheduler_alert "alpha_queue" "credentials_${CRED_ST}" \
      "실행 전 차단 — $(sched_credentials_guidance "$CRED_ST") 큐 pending=$N 보존됨(재로그인 후 차기 런 자동 소비)."
    exit 0
    ;;
  esac
fi

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

# 효과 지문(전) — 에이전트 자기보고가 빠져도 원장 변화로 진척을 판정한다(2026-08-22 오경보 수리).
_EFFECT_SIG="$BASE/02_Infrastructure/ops/research_effect_signature.py"
_EFFECT_BEFORE=""
[ -f "$_EFFECT_SIG" ] && _EFFECT_BEFORE=$("$PYBIN" "$_EFFECT_SIG" "$BASE" 2>/dev/null || true)
# --- 무인 런 시간제한 (도훈 지시 2026-08-22 "시간제한 없애") ---------------
#   기본 = 제한 없음. QVEST_RUN_TIMEOUT=<초> 를 주면 그만큼 적용한다.
#   근거: 2026-08-22 18:13 실측 — 런이 WT-005 를 ALPHA_DONE 으로 올리고 alpha_package
#   (15KB)·certificate·validation 을 18:10 에 다 냈는데 18:13 에 상한이 죽였다.
#   상한이 자른 것은 폭주가 아니라 **끝난 일의 뒷정리**였고, 그 결과 자기보고와
#   원장 append 가 유실됐다(rc=124 로만 남음).
#   ★무한 정지 방지의 실질은 timeout 이 아니라 **자기 락**이다 — 락은 PID 를 적고
#   kill -0 로 생존을 확인하므로 죽은 런의 락은 다음 런이 회수한다.
_run_claude(){
  if [ -n "${QVEST_RUN_TIMEOUT:-}" ] && [ "${QVEST_RUN_TIMEOUT}" != "0" ]; then
    timeout "${QVEST_RUN_TIMEOUT}" "$@"
  else
    "$@"
  fi
}

# 알림 창 기준점 — 이 시각 **이후** 산출만 이 런의 것으로 본다.
#   안 넘기면 기본 4시간 창이 쓰여 직전 3.5시간의 남의 산출까지 자기 것으로 보고한다
#   (오늘 여섯 번 겪은 "범위를 안 정하고 센다" 의 알림 판본).
_NOTIFY_SINCE=$(date +%s)

# ── (2026-08-23 v9 Lean Loop) 산출 디렉터리 **전/후 목록**.
#   왜 mtime 창이 아니라 목록 차집합인가: 시간 창은 "범위를 안 정하고 센다" 의 재발원이다
#   (병렬 세션·수동 실행의 산출을 자기 것으로 집는다). 목록 차집합은 **이 런이 만든 것만**
#   집는다 — 범위가 정의상 닫힌다.
_ASD="$BASE/stage_artifacts/alpha_search"
_AS_BEFORE="$(mktemp)"; _AS_AFTER="$(mktemp)"
ls -1 "$_ASD" 2>/dev/null | sort > "$_AS_BEFORE"
_run_claude "$CLAUDE_BIN" -p "$PROMPT_TEXT" "${LANE_LLM_ARGS[@]}" \
  --dangerously-skip-permissions >> "$LOG" 2>&1
rc=$?
log "claude -p exit=$rc"
# (2026-07-26) 성공하면 해당 컴포넌트의 미해소 마커를 아카이브 — 사유 해소 후에도 마커가
#   남으면 다음 실패가 과거와 이어져 streak 을 부풀리고 가짜 격상을 낸다(삭제 아닌 이동).
if [ "$rc" -eq 0 ] && command -v sched_mark_resolved >/dev/null 2>&1; then
  _mv=$(sched_mark_resolved "alpha_queue" "$BASE/.cache/scheduler_alerts")
  [ -n "${_mv:-}" ] && log "해소: 미해소 마커 ${_mv}건 _resolved/ 로 아카이브"
fi
# v3 침묵 정지 경보화 (paper_router_run.sh와 동일): 실패가 로그에만 남고 exit 0 종료되는 구조 보완.
if [ "$rc" -ne 0 ]; then
  # (2026-07-25) 사유 판정을 공통 헬퍼로 이관 — 구 구현은 "spend limit" 한 패턴만 특별취급해
  #   자동복구되는 실패와 사람이 재인증해야 풀리는 실패를 같은 라벨로 뭉갰다(8일 정지 기전).
  if command -v sched_classify_failure >/dev/null 2>&1; then
    reason=$(sched_classify_failure "$rc" "$LOG")
  else
    reason="exit_${rc}"
    tail -n 30 "$LOG" 2>/dev/null | grep -qi "spend limit" && reason="spend_limit"
  fi
  # (2026-07-24 도훈 승인 C8) Fable 한도 폴백 — spend_limit 감지 시 --model opus 1회 재시도
  # (도훈 07-14 정책: 상태 FS 외부화라 모델 전환 무손실. 폴백 성공=로그만, 실패 시에만 경보 — 한도는 외생변수)
  if [ "$reason" = "spend_limit" ]; then
    log "spend_limit 감지 — --model opus 폴백 재시도"
    _run_claude "$CLAUDE_BIN" -p "$PROMPT_TEXT" --model opus --effort "$LLM_EFFORT" \
      --dangerously-skip-permissions >> "$LOG" 2>&1
    rc=$?; log "fallback(opus) exit=$rc"
    [ "$rc" -ne 0 ] && reason="spend_limit_fallback_exit_${rc}"
  fi
  if [ "$rc" -ne 0 ]; then
    _ann=""
    command -v sched_failure_annotate >/dev/null 2>&1 && 
      _ann=$(sched_failure_annotate "alpha_queue" "$reason" "$BASE/.cache/scheduler_alerts")
    scheduler_alert "alpha_queue" "$reason" \
      "claude -p exit=$rc (pending=$N MAX_ALPHA=$MAXA) | ${_ann:-로그 확인 필요}"
  fi
fi
# ══ (2026-08-23 v9 Lean Loop) 산출물 전수 판정 + 원장 append ═══════════════════
#   구 체인은 이 두 가지를 **프롬프트에게** 시켰다: L1~L3 verdict 를 손으로 모으고,
#   L4 로 `claude -p` 를 한 번 더 스폰하고, 원장을 손편집했다. 결과 —
#     · 원장 배열이 두 번 파손돼 소비자가 `LEDGER_UNREADABLE` 을 봤다(08-09 · 08-23)
#     · L4 는 31건 동안 판정을 한 번도 바꾸지 않았다
#     · 런이 중도 사망하면 판정도 원장도 통째로 유실됐다("실행됐는데 pending")
#   ⇒ 판정 입력은 **산출물에서 기계로** 뽑고(`lean_verify_build.py`), 판정은 결정적
#     게이트가 하고(`auto_alpha_gate.R`), 원장은 **원자적 append CLI** 가 쓴다.
#   ★rc 와 무관하게 돈다 — 런이 실패로 끝나도 그 전에 만든 산출은 판정 대상이다.
_GATE="$BASE/02_Infrastructure/ops/auto_alpha_gate.R"
_LVB="$BASE/02_Infrastructure/ops/lean_verify_build.py"
_PIDN="$BASE/02_Infrastructure/ops/paper_id_norm.py"
_RS_BIN="$(command -v Rscript || echo '/c/Program Files/R/R-4.5.2/bin/Rscript')"
_jget(){ "$PYBIN" -c "import json,io,sys
try:
    print(json.load(io.open(sys.argv[1], encoding='utf-8-sig')).get(sys.argv[2]) or '')
except Exception:
    print('')" "$1" "$2" 2>/dev/null; }
_gated=0; _adopt=0; _screen=0; _quar=0; _unread=0; _noart=0
if [ -d "$_ASD" ] && [ -f "$_GATE" ] && [ -f "$_LVB" ] && [ -x "$_RS_BIN" ]; then
  ls -1 "$_ASD" 2>/dev/null | sort > "$_AS_AFTER"
  _NEW_IDS=$(comm -13 "$_AS_BEFORE" "$_AS_AFTER")
  log "신규 alpha_search 산출 디렉터리: $(printf '%s' "$_NEW_IDS" | grep -c . || true)건"
  while IFS= read -r _id; do
    [ -n "$_id" ] || continue
    [ -d "$_ASD/$_id" ] || continue
    _INFO=$("$PYBIN" "$_LVB" "$_ASD/$_id" 2>>"$LOG")
    _st=$(printf '%s\n' "$_INFO" | sed -n 's/^STATUS=//p' | head -1)
    if [ "$_st" != "ok" ]; then
      _noart=$((_noart+1))
      log "  [$_id] 판정 대상 아님 (STATUS=${_st:-unreadable}) — 백테 산출물 없음. 0 으로 삼키지 않고 라벨만 남긴다."
      continue
    fi
    _vp=$(printf  '%s\n' "$_INFO" | sed -n 's/^VERIFY_PATH=//p'      | head -1)
    _pid=$(printf '%s\n' "$_INFO" | sed -n 's/^PAPER_ID=//p'          | head -1)
    _psrc=$(printf '%s\n' "$_INFO" | sed -n 's/^PAPER_ID_SOURCE=//p'  | head -1)
    _sid=$(printf '%s\n' "$_INFO" | sed -n 's/^STRATEGY_ID=//p'       | head -1)
    _grade=$(printf '%s\n' "$_INFO" | sed -n 's/^GRADE=//p'           | head -1)
    _pt=$(printf  '%s\n' "$_INFO" | sed -n 's/^PORT_T=//p'            | head -1)
    "$_RS_BIN" --no-save "$_GATE" "$_vp" >> "$LOG" 2>&1
    _dec=$(_jget "$_vp" gate_decision)
    _route=$(_jget "$_vp" screen_route)
    _abs=$(_jget "$_vp" gate_absent_layers)
    _gated=$((_gated+1))
    log "  [$_id] gate=${_dec:-?} grade=${_grade:-?} port_t=${_pt:-NA} route=${_route:-NONE} paper=${_pid}(${_psrc}) 결측층=${_abs:-none}"
    case "$_dec" in
      ADOPT)       _adopt=$((_adopt+1)) ;;
      SCREEN_TIER) _screen=$((_screen+1)) ;;
      QUARANTINE)  _quar=$((_quar+1)) ;;
      *)           _unread=$((_unread+1)) ;;
    esac
    # ★ERROR_UNREADABLE 은 판정이 아니라 입력 계약 불일치다 — 원장에 판정으로 적지 않는다.
    if [ "$_dec" = "ADOPT" ] || [ "$_dec" = "SCREEN_TIER" ] || [ "$_dec" = "QUARANTINE" ]; then
      _AR=( append-done --paper-id "$_pid" --gate "$_dec" --strategy-id "$_sid"
            --processed-date "$TODAY" --verify-path "$_vp" --bt-result-dir "$_ASD/$_id"
            --note "alpha_search_queue_run.sh v9 lean gate (paper_id_source=${_psrc})" )
      [ -n "${_grade:-}" ] && _AR+=( --grade "$_grade" )
      [ -n "${_pt:-}" ]    && _AR+=( --port-t "$_pt" )
      [ -n "${_route:-}" ] && _AR+=( --screen-route "$_route" )
      if "$PYBIN" "$_PIDN" "${_AR[@]}" >> "$LOG" 2>&1; then
        log "  [$_id] 원장 append 완료 → $_pid / $_dec"
      else
        log "  [$_id] ★원장 append 실패 — 다음 런이 같은 논문을 다시 태운다. 수동 확인 필요."
        scheduler_alert "alpha_queue" "ledger_append_failed" \
          "판정($_dec)은 났는데 원장 append 가 실패했다 — paper_id=$_pid strategy=$_sid verify=$_vp"
      fi
    else
      log "  [$_id] 원장 append 생략 — 판정이 아니라 입력 계약 불일치(${_dec:-empty})."
    fi
  done <<EOF_NEWIDS
$_NEW_IDS
EOF_NEWIDS
  log "게이트 결과: 판정 $_gated (ADOPT $_adopt / SCREEN_TIER $_screen / QUARANTINE $_quar / 미판정 $_unread) · 산출없음 $_noart"
else
  log "게이트 건너뜀 — 구성요소 부재 (ASD=$_ASD gate=$([ -f "$_GATE" ] && echo y || echo n) lvb=$([ -f "$_LVB" ] && echo y || echo n) Rscript=$([ -x "$_RS_BIN" ] && echo y || echo n))"
fi
rm -f "$_AS_BEFORE" "$_AS_AFTER" 2>/dev/null || true

# --- (v9.1 §7-S2c) 스크린 큐 리프레시 — 무인 런당 1회, 순차 ---------------------
#   왜: 게이트가 라벨(screen_route)을 산출물에 찍어도 큐 빌더 3종이 전부 수동이라
#   라벨이 소비자에게 도달하지 않는다("생산자만 있고 소비자 0" 계통의 재발).
#   순서·뮤텍스·개별 tryCatch 는 refresh_screen_queues.R 이 갖는다. 여기서는 1회 호출뿐이다.
#   ★부팅/모닝브리핑에는 넣지 않는다 — bootstrap.sh:993 "상태라인은 읽기 전용"(8j 규약).
if [ "$_gated" -gt 0 ] && [ "${QVEST_SCREEN_QUEUE_NORUN:-0}" != "1" ] && [ -x "$_RS_BIN" ]; then
  log "스크린 큐 리프레시 시작 (overlay → standalone → auto_spawn)"
  if "$_RS_BIN" --no-save "$BASE/02_Infrastructure/ops/refresh_screen_queues.R" >> "$LOG" 2>&1; then
    log "스크린 큐 리프레시 완료"
  else
    log "★큐 리프레시 실패 — 라벨은 산출물에 있으나 큐에 도달 못 함"
  fi
fi

# --- (v10 2026-08-29) 구 기계 사다리 자동 기동 **퇴역** -----------------------
#   도훈 결정: 강화 프로세스 = QEPM 기반 세션 주도 리서치(.claude/skills/reinforce/SKILL.md,
#   1계층 ≤20회 · 원장 reinforce_ledger_l1.json)로 대체 + 무인 파이프라인은 수집까지만.
#   reinforce_ladder.R 는 파일 존치(RETIRED 배너) — 구 v9.21 §2-d 호출 블록은 git 사료.
log "강화 프로세스(기계 사다리) 자동 기동 — 퇴역 (v10 2026-08-29: QEPM 기반 세션 강화로 대체)"

_EFFECT_CMP=""
if [ -n "${_EFFECT_BEFORE:-}" ]; then
  _EFFECT_CMP=$("$PYBIN" "$_EFFECT_SIG" "$BASE" --compare "${_EFFECT_BEFORE}" 2>/dev/null || true)
fi
# --- (2026-08-22 도훈 지시 "완주할 때마다") 완주 알림 — tg_agent_brief() 단일 진입점 경유.
#   구조: 지금까지 텔레그램은 **실패**(scheduler_alert)에만 나갔다. 무인이 무엇을 해냈는지는
#   도훈에게 도달하지 않았다 — 오늘 반복 확인된 "기록은 되는데 읽는 쪽이 없다" 의 텔레그램 판본.
_RS="$BASE/02_Infrastructure/ops/research_run_notify.R"
if [ -f "$_RS" ] && [ "${QVEST_RUN_NOTIFY:-1}" = "1" ]; then
  QM_ROOT="$BASE" Rscript --no-save "$_RS" "alpha_search" "$N" "0" "${_EFFECT_CMP:-}" "$rc" "" "${_NOTIFY_SINCE:-}" >> "$LOG" 2>&1 || log "완주 알림 실패(비치명)"
fi
exit 0
