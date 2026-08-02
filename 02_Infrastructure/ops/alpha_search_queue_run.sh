#!/bin/bash
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
N=$("$PYBIN" "$PRED" alpha-pending "$SD")
# ★계측 사망을 0 으로 삼키지 않는다 — 숫자가 아니면 skip 이 아니라 경보 후 중단.
if command -v sched_assert_count >/dev/null 2>&1 && ! sched_assert_count "$N"; then
  log "★pending 산정 실패 (N='$N', PYBIN=$PYBIN) — 계측 사망. 0 으로 간주하지 않고 중단."
  scheduler_alert "alpha_queue" "count_measurement_failed" \
    "pending 산정이 비숫자('$N') 반환 — python 인터프리터 해석 실패 추정(PYBIN=$PYBIN). 큐가 조용히 skip 되는 것을 막기 위해 중단. PATH 에 python312 부재 또는 Windows Store 스텁 가능."
  exit 0
fi
N="${N:-0}"
log "pending testable(큐+route−done): $N (PYBIN=$(basename "$PYBIN"))"
if [ "$N" -eq 0 ] && [ "${QVEST_ALPHA_QUEUE_FORCE:-0}" != "1" ]; then
  log "pending 0 — skip (FORCE=1로 강제)"; exit 0
fi

CLAUDE_BIN="$(command -v claude || echo /c/Users/99922/AppData/Roaming/npm/claude)"
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

timeout 3000 "$CLAUDE_BIN" -p "$PROMPT_TEXT" \
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
    timeout 3000 "$CLAUDE_BIN" -p "$PROMPT_TEXT" --model opus \
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
exit 0
