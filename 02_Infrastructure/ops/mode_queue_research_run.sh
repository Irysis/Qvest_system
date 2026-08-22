#!/bin/bash
# mode_queue_research_run.sh — 리서치 큐 무인 개시 (도훈 결정 2026-08-21 / 확장 08-22).
#   레인: method_measure(측정 백로그) · alpha(alpha-hypothesis→alpha-research) ·
#         optimizer · risk · regime. 정본 진입점 = research-queue-pending.
#
# 끊긴 칸: paper_router 가 mode_queue 를 쌓는데 소비자가 세션 수동뿐이라 12일간 등재 0건이었다
#   (누적 고유 93편 vs method_registry 16건, 전건 added 08-08~09). alpha 레인은
#   alpha_search_queue_run.sh 가 이미 무인이므로 그와 **같은 수준**으로 맞춘다.
#
# 게이트(전부 통과해야 실행):
#   QVEST_MODE_QUEUE_ENABLE=1   — 자체 on (기본 0 = kill switch)
#   pending > 0                  (또는 QVEST_MODE_QUEUE_FORCE=1)
# 옵션:
#   QVEST_MODE_QUEUE_MAX=N       — 1런 처리 상한 (기본 2)
#   QVEST_MODE_QUEUE_DRYRUN=1    — 산정까지만, claude 미호출
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
BASE="${BASE:-${PROJECT:-$PWD}}"; PROJECT="${PROJECT:-$BASE}"
cd "$BASE" || exit 1
TODAY=$(date +%Y%m%d)
LOG="$BASE/.cache/scheduler_logs/mode_queue_research_${TODAY}.log"
mkdir -p "$(dirname "$LOG")"
log(){ echo "$(date -Iseconds) [modeq] $*" >> "$LOG"; }

# 경보(alpha_search_queue_run.sh / paper_router_run.sh 와 동일 패턴, fail-soft):
#   마커를 **먼저** 남긴다 — 텔레그램이 죽어도 사실은 남아야 한다.
scheduler_alert(){
  local comp="$1" reason="$2" detail="$3"
  local adir="$BASE/.cache/scheduler_alerts"; mkdir -p "$adir"
  local marker="$adir/${comp}_${reason}_${TODAY}.alert"
  if [ -f "$marker" ]; then log "alert throttle: ${comp}/${reason} — skip"; return 0; fi
  { echo "ts=$(date -Iseconds)"; echo "component=$comp"; echo "reason=$reason"
    echo "detail=$detail"; echo "log=$LOG"; } > "$marker"
  log "alert marker 기록: $marker"
}

if [ "${QVEST_MODE_QUEUE_ENABLE:-0}" != "1" ]; then
  log "disabled (QVEST_MODE_QUEUE_ENABLE!=1) — skip"; exit 0
fi

# ── 자체 상호배제 — 2026-08-21 라우터 동시실행 실사고의 교훈을 신설 시점에 적용한다.
#    그날 morning_run 재시도가 **살아있는** 직전 런을 ".done 없음 = 중도 사망" 으로 오판해
#    라우터를 2개 띄웠고, 둘이 같은 산출물을 덮어써 풍부한 판(22,901B)이 사라졌다.
#    ★호출자가 하나라는 보장이 없다 — 호출자를 믿지 말고 여기서 막는다.
MLOCK="$BASE/.cache/mode_queue_research.lock"
if ! mkdir "$MLOCK" 2>/dev/null; then
  _mp=$(cat "$MLOCK/pid" 2>/dev/null)
  if [ -n "${_mp:-}" ] && kill -0 "$_mp" 2>/dev/null; then
    log "다른 인스턴스 실행 중(PID=$_mp) — skip"; exit 0
  fi
  log "stale lock 회수 (PID=${_mp:-?} 생존 안 함)"
  rm -rf "$MLOCK"; mkdir "$MLOCK" 2>/dev/null || { log "락 획득 실패 — skip"; exit 0; }
fi
echo "$$" > "$MLOCK/pid"
trap 'rm -rf "$MLOCK"' EXIT

# ── pending 산정: 술어 정본 경유.
#    ★여기에 술어를 다시 적지 말 것 — 소비자별 재구현이 2026-08-02 3연발 결함의 원인이다.
PYBIN="${QVEST_PY:-python}"
PRED="$BASE/02_Infrastructure/ops/research_pool_predicates.py"
QJSON="$BASE/.cache/research_queue_pending.json"
# 레인 지정 소비(선택) — 기본은 전 레인. 정렬상 앞 레인이 상한을 다 먹어 뒤 레인이
#   영영 안 도는 것을 표적 소비로 푼다(2026-08-22: method_measure 12건이 risk/opt/regime 을 막았다).
_LANE_ARG=""
[ -n "${QVEST_MODE_QUEUE_LANE:-}" ] && _LANE_ARG="--lane ${QVEST_MODE_QUEUE_LANE}"
N=$("$PYBIN" "$PRED" research-queue-pending "$BASE/stage_artifacts/paper_recharge" "$BASE" $_LANE_ARG --json "$QJSON" 2>>"$LOG")
# ★계측 사망을 0 으로 삼키지 않는다 — 숫자가 아니면 skip 이 아니라 경보 후 중단.
#   (alpha 레인 실사고: bare python3 가 Windows Store 스텁으로 해석돼 빈 출력을 냈고,
#    구판이 그것을 0 으로 삼켜 "대기 없음" 정상 skip 으로 위장됐다. 참값은 3이었다.)
case "$N" in
  ''|*[!0-9]*)
    log "pending 계측 실패 (출력='$N') — 0 으로 읽지 않고 중단"
    scheduler_alert "mode_queue" "count_measurement_failed" \
      "research_pool_predicates.py research-queue-pending 이 숫자를 내지 않음(출력='$N')"
    exit 0 ;;
esac
if [ "$N" -eq 0 ] && [ "${QVEST_MODE_QUEUE_FORCE:-0}" != "1" ]; then
  log "pending 0 — skip (FORCE=1 로 강제)"; exit 0
fi

MAXI="${QVEST_MODE_QUEUE_MAX:-2}"
if [ "${QVEST_MODE_QUEUE_DRYRUN:-0}" = "1" ]; then
  log "DRYRUN — claude 미호출. 산정 결과: pending=$N MAX_ITEMS=$MAXI queue=$QJSON"
  exit 0
fi

CLAUDE_BIN="$(command -v claude || echo /c/Users/99922/AppData/Roaming/npm/claude)"
[ -x "$CLAUDE_BIN" ] || { log "claude CLI 없음 — skip"; exit 0; }
PF="$BASE/02_Infrastructure/ops/mode_queue_research_prompt.md"
[ -f "$PF" ] || { log "prompt 없음 — skip"; exit 0; }

log "start mode_queue research (pending=$N, MAX_ITEMS=$MAXI, LANE=${QVEST_MODE_QUEUE_LANE:-all})"
PROMPT_TEXT="$(printf 'TODAY=%s  MAX_ITEMS=%s  QUEUE=%s\n\n%s\n' \
  "$TODAY" "$MAXI" ".cache/research_queue_pending.json" "$(cat "$PF")")"

# 자격증명 사전 점검 — 실패하고 나서 알리지 말고 미리 알린다
#   (alpha 레인 실사고: refreshToken 이 빈 문자열이라 401 로 8일 무인 정지, 07-19~26).
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_sched_failure_classify.sh" 2>/dev/null || true
if command -v sched_check_credentials >/dev/null 2>&1; then
  CRED_ST=$(sched_check_credentials)
  case "$CRED_ST" in ok*|unknown) : ;; *)
    log "자격증명 사전점검 실패: $CRED_ST — claude 호출 생략(무의미한 401 회피)"
    scheduler_alert "mode_queue" "credentials_${CRED_ST}" \
      "실행 전 차단. 큐 pending=$N 보존됨(재로그인 후 차기 런 자동 소비)."
    exit 0 ;;
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

# ★이번 런의 산출만 센다 — 로그는 당일 append-only 라 누적분을 이번 것으로 읽으면
#   zero_progress 가드가 통째로 무력해진다(2026-08-22 실측: risk 런이 MODEQ_DONE 을
#   내지 않았는데 11:20 런의 옛 줄이 남아 "1건" 으로 보고됐다).
# ★진척 판정을 **에이전트 자기보고에만** 걸지 않는다. 실사고 2026-08-22 16:31:
#   qepm_dossier 런이 WT 를 SPEC_APPROVED→ALPHA_DONE 으로 전이시키고 alpha_package 까지
#   만들었는데 MODEQ_DONE 을 안 내서 zero_progress 오경보가 났다.
#   원장이 진실이고 자기보고는 보조다 — 런 전후 지문을 떠서 효과를 독립 판정한다.
_EFFECT_BEFORE=$("$PYBIN" "$BASE/02_Infrastructure/ops/research_effect_signature.py" "$BASE" 2>/dev/null)
_log_lines_before=$(wc -l < "$LOG" 2>/dev/null || echo 0)
timeout 3000 "$CLAUDE_BIN" -p "$PROMPT_TEXT" --dangerously-skip-permissions >> "$LOG" 2>&1
rc=$?
log "claude -p exit=$rc"

if [ "$rc" -eq 0 ]; then
  # ★exit 0 은 "돌았다" 이지 "했다" 가 아니다 — 실제 처리 건수를 함께 찍고,
  #   0 건이면 경보한다. 하위 러너 fail-soft 가 성공으로 읽히는 구조를 여기서 끊는다.
  # ★`grep -c ... || echo 0` 은 쓰지 않는다: grep 은 0건일 때 "0" 을 **출력하고 exit 1**
  #   이라 `|| echo 0` 이 한 줄 더 붙어 _n_done="0 0" 이 되고 -eq 비교가 깨진다.
  #   (원판에 있던 결함 — 2026-08-22 증분 카운터 수리 중 발견)
  _n_done=$(tail -n "+$(( ${_log_lines_before:-0} + 1 ))" "$LOG" 2>/dev/null | grep -c "^MODEQ_DONE ")
  case "${_n_done:-}" in ""|*[!0-9]*) _n_done=0 ;; esac
  log "처리 결과: MODEQ_DONE ${_n_done}건 (pending 이었던 $N 건 중, 상한 $MAXI)"
  if [ "${_n_done:-0}" -eq 0 ]; then
    # 마커가 없더라도 원장이 바뀌었으면 진척이다 — 자기보고 누락은 경보 사유가 아니다.
    _EFFECT_CMP=$("$PYBIN" "$BASE/02_Infrastructure/ops/research_effect_signature.py" "$BASE" --compare "${_EFFECT_BEFORE:-}" 2>/dev/null)
    if [ "$_EFFECT_CMP" = "CHANGED" ]; then
      log "MODEQ_DONE 0건이나 원장 지문 변화 감지 — 진척으로 판정(에이전트 자기보고 누락)"
    else
      scheduler_alert "mode_queue" "zero_progress" "claude exit=0 · MODEQ_DONE 0건 · 원장 지문 무변화 — pending=$N 인데 실제 효과 없음"
    fi
  fi
  if command -v sched_mark_resolved >/dev/null 2>&1; then
    _mv=$(sched_mark_resolved "mode_queue" "$BASE/.cache/scheduler_alerts")
    [ -n "${_mv:-}" ] && log "해소: 미해소 마커 ${_mv}건 아카이브"
  fi
fi

if [ "$rc" -ne 0 ]; then
  if command -v sched_classify_failure >/dev/null 2>&1; then
    reason=$(sched_classify_failure "$rc" "$LOG")
  else
    reason="exit_${rc}"
  fi
  # spend_limit 폴백 (도훈 07-14 정책 / 07-24 승인 C8) — 한도는 외생변수이지 게이트가 아니다.
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
      _ann=$(sched_failure_annotate "mode_queue" "$reason" "$BASE/.cache/scheduler_alerts")
    scheduler_alert "mode_queue" "$reason" \
      "claude -p exit=$rc (pending=$N MAX_ITEMS=$MAXI) | ${_ann:-로그 확인 필요}"
  fi
fi
exit 0
