#!/bin/bash
# paper_router_run.sh — 헤드리스 claude 논문 스타일 라우터 (옵션1, 도훈 mandate 2026-06-18)
# recharge 후 당일 적재 논문을 분류(route) → alpha_search∧feasible 자동 alpha-search(cap) → 나머지 큐 → 텔레그램.
# 무인. claude -p --dangerously-skip-permissions. batch_434 오염 방지 가드는 prompt에.
#
# 게이트(전부 통과해야 실행):
#   QVEST_PAPER_ROUTER_ENABLE=1  — 라우터 자체 on (기본 0=off, kill-switch)
#   당일 mcp_discovery_<TODAY>.json 존재 (recharge가 돌았음) — 단 v3: 백로그만 있어도 실행
#   당일 신규 다운로드>0 (또는 QVEST_PAPER_ROUTER_FORCE=1, 또는 v3 백로그>0)
# 옵션:
#   QVEST_PAPER_ROUTER_AUTORUN=1 — alpha∧feasible 자동 alpha-search 실행 (기본 0=분류·큐·텔레그램만)
#   QVEST_PAPER_ROUTER_MAX_ALPHA=N — 1일 자동 alpha-search 상한 (기본 2)
#   QVEST_PAPER_ROUTER_DRYRUN=1  — v3: 대상 산정(백로그 포함)까지만 로그, claude 미호출
#
# v3 (2026-07-10, Qvest v8.3 Move M4 — 무인 인입 체인 복구·경보화):
#   1) 백로그 합류 — 최근 7일 내 downloaded>0인데 alpha_search_route_<D>.json 없는 날짜를
#      스캔해 BACKLOG_DATES로 라우팅 대상에 합류 (07-08 spend-limit 정지로 17편 좌초 재발 방지).
#   2) 침묵 정지 경보화 — claude exit≠0(특히 monthly spend limit) 시 .cache/scheduler_alerts/
#      마커 기록(fail-soft) + tg_agent_brief() 경유 텔레그램. 같은 사유 1일 1회 스로틀.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
BASE="${BASE:-${PROJECT:-$PWD}}"; PROJECT="${PROJECT:-$BASE}"
cd "$BASE" || exit 1
TODAY=$(date +%Y%m%d)
LOG="$BASE/.cache/scheduler_logs/paper_router_${TODAY}.log"
mkdir -p "$(dirname "$LOG")"

log(){ echo "$(date -Iseconds) [router] $*" >> "$LOG"; }

# ── v3 침묵 정지 경보 (fail-soft): 마커 먼저 기록 → tg_agent_brief() 경유 텔레그램 시도.
#    R 발송 실패해도 마커는 남는다. 같은 (component, reason) 은 1일 1회 스로틀.
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
         items = c("실패분은 백로그 합류 로직이 다음 성공 런에서 자동 재처리됩니다",
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

if [ "${QVEST_PAPER_ROUTER_ENABLE:-0}" != "1" ]; then
  log "disabled (QVEST_PAPER_ROUTER_ENABLE!=1) — skip"; exit 0
fi
# -- (2026-08-21 수리) 자체 상호배제 -- 호출자를 믿지 않는다 -----------------
#   실사고 2026-08-21: morning_run 재시도가 **살아있는** 직전 런을 ".done 없음 = 중도 사망"
#   으로 오판해 라우터를 2개 띄웠다(PID 35460 @07:07:49 · 9824 @07:11:27). 둘이 같은
#   route JSON 을 덮어써, 07:19 판(22,901B · schema route_v2 · autorun 2편 ·
#   factor_candidates 4종)이 07:31 판(16,419B · autorun/factor_candidates 소실)으로 사라졌고
#   20260820/20260821 두 파일이 date 필드만 다른 복제가 됐다(route 배정 불일치 0편).
#   ★morning_run 쪽 수리와 **별개로** 여기서도 막는다 -- 호출자가 하나라는 보장이 없다.
RLOCK="$BASE/.cache/paper_router.lock"
if ! mkdir "$RLOCK" 2>/dev/null; then
  _rp=$(cat "$RLOCK/pid" 2>/dev/null)
  if [ -n "${_rp:-}" ] && kill -0 "$_rp" 2>/dev/null; then
    log "다른 인스턴스 실행 중(PID=$_rp) — skip (동시 라우팅 금지)"; exit 0
  fi
  log "stale lock 회수 (PID=${_rp:-?} 생존 안 함)"
  rm -rf "$RLOCK"
  mkdir "$RLOCK" 2>/dev/null || { log "락 획득 실패 — skip"; exit 0; }
fi
echo "$$" > "$RLOCK/pid"
trap 'rm -rf "$RLOCK"' EXIT

DISC="$BASE/stage_artifacts/paper_recharge/mcp_discovery_${TODAY}.json"
STAMP="$BASE/stage_artifacts/paper_recharge/paper_recharge_${TODAY}.done"
DL=$(grep -oE 'downloaded=[0-9]+' "$STAMP" 2>/dev/null | head -1 | cut -d= -f2)
DL="${DL:-0}"
# v2(2026-06-19): curated(헤지펀드/기관) 미처리분 있으면 arxiv 0-download여도 실행. 정적 소스라 1회 라우팅 후엔
#   csv==routed 가 되어 자동 idle(매일 재처리 없음). arxiv 신규 OR curated 미처리 OR FORCE 일 때 실행.
CURATED_CSV="$BASE/02_Infrastructure/config/paper_recharge_sources.csv"
CURATED_DONE="$BASE/stage_artifacts/paper_recharge/curated_routed.json"
curated_pending=0
if [ -f "$CURATED_CSV" ]; then
  n_csv=$(( $(wc -l < "$CURATED_CSV") - 1 ))
  n_done=$(grep -oE '\.pdf"' "$CURATED_DONE" 2>/dev/null | wc -l)
  [ "$n_csv" -gt "$n_done" ] && curated_pending=1
fi
# v3(2026-07-10): 백로그 합류 — 최근 7일 내 downloaded>0인데 대응 alpha_search_route_<D>.json이
#   없는 날짜를 스캔. 실패일(예: 07-08 spend-limit exit=1, 17편) 다운로드분의 영구 좌초 방지.
#   discovery JSON이 없는 날짜는 라우팅 소스 자체가 없어 제외(로그만).
BACKLOG_DATES=""
# -- (2026-08-21 수리) 백로그 판정축을 .done 스탬프에서 **discovery 존재**로 옮긴다 --
#   구판 결함: `[ -f "$BST" ] || continue` + `downloaded>0`. 그런데 백로그를 만드는 실패
#   모드(런 중도 사망)가 **바로 .done 을 못 남기는 모드**다 -- 검사기가 자기 발화 조건에
#   눈이 멀어 있었다. 실측 2026-08-21: 08-15/16/17 은 discovery 29편씩 있는데 .done 부재라
#   **로그 한 줄 없이** 탈락했고, 12편이 어떤 route JSON 에도 없다. 7일 창 이탈(08-22/23/24)
#   시 무경보 영구 좌초 -- 만료 경보는 BACKLOG_DATES 에 든 날짜만 검사하기 때문이다.
#   ★뿌리 = 2026-08-02 수리의 **비대칭 적용**. 그때 "downloaded 는 '라우팅할 재료가 있나'가
#     아니다" 라고 선언하고 고친 건 아래 당일 축뿐이고 이 백로그 축은 그대로였다.
#     이제 두 축이 같은 기준을 쓴다: **discovery 있고 route 없음 = 미소비**.
BACKLOG_MAX="${QVEST_PAPER_ROUTER_BACKLOG_MAX:-3}"
_bl_n=0
# ★오래된 날짜부터 훑는다 — 상한(BACKLOG_MAX)이 걸릴 때 **만료 임박분을 먼저 살리기** 위해서다.
#   오름차순(1..7)이면 최신부터 채워 7일 창을 곧 이탈할 가장 오래된 날짜가 잘려나간다
#   (2026-08-22 자가 적발 — 패치 당일 발견).
for i in 7 6 5 4 3 2 1; do
  D=$(date -d "-${i} day" +%Y%m%d 2>/dev/null) || continue
  RJ_D="$BASE/stage_artifacts/paper_recharge/alpha_search_route_${D}.json"
  [ -f "$RJ_D" ] && continue
  DISC_D="$BASE/stage_artifacts/paper_recharge/mcp_discovery_${D}.json"
  [ -f "$DISC_D" ] || continue
  BST="$BASE/stage_artifacts/paper_recharge/paper_recharge_${D}.done"
  bdl=0; _stamp=N
  if [ -f "$BST" ]; then
    _stamp=Y
    bdl=$(grep -oE 'downloaded=[0-9]+' "$BST" 2>/dev/null | head -1 | cut -d= -f2); bdl="${bdl:-0}"
  fi
  if [ "$_bl_n" -ge "$BACKLOG_MAX" ]; then
    log "backlog 상한 도달($BACKLOG_MAX) — $D 이번 런 보류(차기 재합류). 프롬프트 비대화 방지"
    continue
  fi
  BACKLOG_DATES="${BACKLOG_DATES:+$BACKLOG_DATES,}$D"
  _bl_n=$((_bl_n + 1))
  log "backlog 포착: $D (downloaded=$bdl · stamp=$_stamp · discovery 존재 · route 없음) — 합류"
done

# 당일 discovery 게이트 (v3: 백로그가 있으면 당일 discovery 없어도 백로그만으로 진행)
if [ ! -f "$DISC" ]; then
  if [ -n "$BACKLOG_DATES" ]; then
    log "no discovery JSON for $TODAY — 백로그만으로 진행 (BACKLOG_DATES=$BACKLOG_DATES)"
  else
    log "no discovery JSON for $TODAY and no backlog — skip"; exit 0
  fi
fi

# ── [2026-08-02 수리] 라우팅 대상 판정을 downloaded 스탬프 단독에서 벗어나게 한다 ────
#  실사고: 08-02 recharge 는 mcp_status=mcp_ok · mcp_candidates=38 로 정상 수집했는데
#  후보가 전부 이미 registry 에 있어(skipped_duplicate_or_registered=53) downloaded=0 이 됐다.
#  라우터는 downloaded 만 보므로 "새 논문 없음"으로 skip → **38편이 라우팅되지 못하고 좌초**.
#  downloaded 는 "PDF 를 새로 내려받았나"이지 "라우팅할 재료가 있나"가 아니다. 이미 받아둔
#  논문도 route JSON 이 없으면 소비되지 않은 것이다 — 산출물(candidates)과 소비 흔적(route JSON)을
#  직접 본다. FQ-010("논문 인입 라인 재가동 + 큐 소비 배선") 실체.
UNROUTED_TODAY=0
MC=$(grep -oE 'mcp_candidates=[0-9]+' "$STAMP" 2>/dev/null | head -1 | cut -d= -f2); MC="${MC:-0}"
if [ "$MC" -gt 0 ] && [ ! -f "$BASE/stage_artifacts/paper_recharge/alpha_search_route_${TODAY}.json" ]; then
  UNROUTED_TODAY=1
  log "unrouted 포착: $TODAY mcp_candidates=$MC · downloaded=$DL · route JSON 없음 — 라우팅 대상 (downloaded=0 이어도 미소비)"
fi

if [ "$DL" -eq 0 ] && [ "$UNROUTED_TODAY" -eq 0 ] && [ "$curated_pending" -eq 0 ] && [ -z "$BACKLOG_DATES" ] && [ "${QVEST_PAPER_ROUTER_FORCE:-0}" != "1" ]; then
  log "no new arxiv downloads (downloaded=$DL), no unrouted candidates (mcp_candidates=$MC), no pending curated, no backlog — skip (QVEST_PAPER_ROUTER_FORCE=1 로 강제)"; exit 0
fi
log "trigger: downloaded=$DL unrouted_today=$UNROUTED_TODAY(mcp_candidates=$MC) curated_pending=$curated_pending backlog=[${BACKLOG_DATES:-none}]"

# v3 dry 모드: 대상 산정(백로그 포함)까지만 검증하고 claude 미호출
if [ "${QVEST_PAPER_ROUTER_DRYRUN:-0}" = "1" ]; then
  log "DRYRUN — claude 미호출. 산정 결과: downloaded=$DL curated_pending=$curated_pending backlog=[${BACKLOG_DATES:-none}]"
  exit 0
fi

CLAUDE_BIN="$(command -v claude || echo /c/Users/99922/AppData/Roaming/npm/claude)"
[ -x "$CLAUDE_BIN" ] || { log "claude CLI not found ($CLAUDE_BIN) — skip"; exit 0; }
PROMPT_FILE="$BASE/02_Infrastructure/ops/paper_router_prompt.md"
[ -f "$PROMPT_FILE" ] || { log "prompt file missing — skip"; exit 0; }
AUTORUN="${QVEST_PAPER_ROUTER_AUTORUN:-0}"
CAP="${QVEST_PAPER_ROUTER_MAX_ALPHA:-2}"

# (2026-07-26 도훈 지시) 사용률 기반 보류·감축 제거 — "한도소비 관련 제약·방어 조건 모두 없애.
#   한도 소비하면 재충전 후 내가 재개시킬게". 한도는 구독 외생 변수이지 게이트가 아니다
#   ([[feedback-spend-limit-external-not-gate]]). 실패 시 경보만 남기고 그대로 멈춘다.
log "start (downloaded=$DL, AUTORUN=$AUTORUN, MAX_ALPHA=$CAP, BACKLOG_DATES=${BACKLOG_DATES:-none})"
HEADER="TODAY=${TODAY}  AUTORUN=${AUTORUN}  MAX_ALPHA=${CAP}  BACKLOG_DATES=${BACKLOG_DATES:-none}"
# 헤드리스 1-shot. timeout 가드(자동 alpha-search 포함 시 길어질 수 있어 50분).
PROMPT_TEXT="$(printf '%s\n\n%s\n' "$HEADER" "$(cat "$PROMPT_FILE")")"
# (2026-07-25) 자격증명 사전 점검 — 무의미한 401 호출 회피 + 조치 즉시 안내
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_sched_failure_classify.sh" 2>/dev/null || true
if command -v sched_check_credentials >/dev/null 2>&1; then
  CRED_ST=$(sched_check_credentials)
  case "$CRED_ST" in ok*|unknown) : ;; *)
    log "자격증명 사전점검 실패: $CRED_ST — claude 호출 생략"
    scheduler_alert "paper_router" "credentials_${CRED_ST}" \
      "실행 전 차단 — $(sched_credentials_guidance "$CRED_ST") 백로그는 보존됨(재로그인 후 차기 런 합류)."
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

# route 산출 수(전) — 라우터의 효과는 원장이 아니라 route JSON 이다.
_ROUTE_DIR="$BASE/stage_artifacts/paper_recharge"
_ROUTE_BEFORE=$(ls -1 "$_ROUTE_DIR"/alpha_search_route_*.json 2>/dev/null | wc -l | tr -d " ")
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

_run_claude "$CLAUDE_BIN" -p "$PROMPT_TEXT" \
  --dangerously-skip-permissions >> "$LOG" 2>&1
rc=$?
log "claude -p exit=$rc"
# (2026-07-26) 성공하면 해당 컴포넌트의 미해소 마커를 아카이브 — 사유 해소 후에도 마커가
#   남으면 다음 실패가 과거와 이어져 streak 을 부풀리고 가짜 격상을 낸다(삭제 아닌 이동).
# (2026-07-26) ★실제 라우팅된 편수를 로그에 남긴다.
#   `downloaded=N` 은 **레지스트리 등록 기준**이지 "신규 N편"이 아니다. 중복·기처리분이 포함돼
#   있어 실제 라우팅 대상과 크게 다를 수 있다(오늘 실측: downloaded=16 인데 순수 신규 1편).
#   이 라벨만 보고 "16편 대기"로 오독하는 사고가 실제로 났으므로, 결과 수를 함께 찍는다.
if [ "$rc" -eq 0 ]; then
  _rj="$BASE/stage_artifacts/paper_recharge/alpha_search_route_${TODAY}.json"
  if [ -f "$_rj" ] && [ -n "${PYBIN:-}" ] || command -v sched_resolve_python >/dev/null 2>&1; then
    _pb="${PYBIN:-$(sched_resolve_python 2>/dev/null || echo python3)}"
    _routed=$("$_pb" -c "
import json,io,sys
try:
    d=json.load(io.open(sys.argv[1],encoding='utf-8')); print(len(d.get('papers',[])))
except Exception: print('?')" "$_rj" 2>/dev/null)
    log "라우팅 결과: route JSON 수록 ${_routed:-?}편 (등록기준 downloaded=$DL — 중복·기처리 포함이라 신규수와 다름)"
  fi
  # (2026-08-13) 발행 **직후** 우선순위 축 채움 검사 — 사후 패턴 감사 아님, 필드 존재 확인.
  #   비-alpha 레인의 실질 병목은 백로그가 아니라 어댑터 등재이고(Σ-A/B 는 큐가 아니라
  #   method_registry 에서 arm 을 고른다), 등재 우선순위는 이 3축(screen_priority ·
  #   shrinkage_builtin · statistic_order) 없이는 매길 수 없다. 축 지시는 08-08 도입 후
  #   11/11 준수 중 — 이 검사는 **그 준수가 조용히 풀리는 것**을 잡는 회귀 감시다.
  _AX="$BASE/02_Infrastructure/ops/mode_queue_axis_audit.py"
  if [ -f "$_AX" ]; then
    _pbx="${PYBIN:-$(command -v sched_resolve_python >/dev/null 2>&1 && sched_resolve_python || echo "${QVEST_PY:-python}")}"
    "$_pbx" "$_AX" --date "$TODAY" >> "$LOG" 2>&1 || log "axis audit 실패(비치명)"
  fi
fi
if [ "$rc" -eq 0 ] && command -v sched_mark_resolved >/dev/null 2>&1; then
  _mv=$(sched_mark_resolved "paper_router" "$BASE/.cache/scheduler_alerts")
  [ -n "${_mv:-}" ] && log "해소: 미해소 마커 ${_mv}건 _resolved/ 로 아카이브"
fi
# v3 침묵 정지 경보화: 기존엔 실패가 로그에만 남고 exit 0 종료(07-08 spend-limit 5일 침묵 정지).
if [ "$rc" -ne 0 ]; then
  # (2026-07-25) 사유 판정 공통 헬퍼 이관 — auth_expired 를 spend_limit 과 분리(조치가 정반대).
  source "$(dirname "${BASH_SOURCE[0]:-$0}")/_sched_failure_classify.sh" 2>/dev/null || true
  if command -v sched_classify_failure >/dev/null 2>&1; then
    reason=$(sched_classify_failure "$rc" "$LOG")
  else
    reason="exit_${rc}"
    tail -n 30 "$LOG" 2>/dev/null | grep -qi "spend limit" && reason="spend_limit"
  fi
  # (2026-07-24 도훈 승인 C8) Fable 한도 폴백 — spend_limit 감지 시 --model opus 1회 재시도 (07-14 정책)
  if [ "$reason" = "spend_limit" ]; then
    log "spend_limit 감지 — --model opus 폴백 재시도"
    _run_claude "$CLAUDE_BIN" -p "$PROMPT_TEXT" --model opus \
      --dangerously-skip-permissions >> "$LOG" 2>&1
    rc=$?; log "fallback(opus) exit=$rc"
    [ "$rc" -ne 0 ] && reason="spend_limit_fallback_exit_${rc}"
  fi
  if [ "$rc" -ne 0 ]; then
    _ann=""
    command -v sched_failure_annotate >/dev/null 2>&1 && 
      _ann=$(sched_failure_annotate "paper_router" "$reason" "$BASE/.cache/scheduler_alerts")
    scheduler_alert "paper_router" "$reason" \
      "claude -p exit=$rc (downloaded=$DL backlog=${BACKLOG_DATES:-none}) | ${_ann:-로그 확인 필요}"
  fi
fi
# v3.1 (2026-07-10 F-4, v8.3 적대검증): exit-0 무산출 백로그 만료 임박 경보.
#   기존엔 claude가 exit 0인데 route JSON을 안 쓴 백로그 날짜는 7일 고정 창을 지나면
#   무경보 영구 좌초(경보는 exit≠0에만 발화). 성공 런 직후 각 백로그 날짜의 route JSON
#   존재를 재확인 — 미생성 + 창 만료까지 <=2일(나이 >=5일)이면 backlog_expiring 경보
#   (scheduler_alert 스로틀 동일 적용: 같은 reason 1일 1회). claude 미호출 경로
#   (DRYRUN / 트리거 없음)는 위에서 이미 exit 0 — 이 블록 도달 불가 = 발화 금지 충족.
if [ "$rc" -eq 0 ] && [ -n "$BACKLOG_DATES" ]; then
  EXPIRING=""
  IFS=',' read -ra _bl_arr <<< "$BACKLOG_DATES"
  for D in "${_bl_arr[@]}"; do
    [ -n "$D" ] || continue
    [ -f "$BASE/stage_artifacts/paper_recharge/alpha_search_route_${D}.json" ] && continue
    ts_d=$(date -d "$D" +%s 2>/dev/null) || { log "backlog 만료검사: date 파싱 실패($D) — skip"; continue; }
    age_days=$(( ( $(date -d "$TODAY" +%s) - ts_d ) / 86400 ))
    if [ "$age_days" -ge 5 ]; then
      EXPIRING="${EXPIRING:+$EXPIRING,}${D}(창이탈까지 $((7 - age_days))d)"
      log "backlog 만료 임박: $D (age=${age_days}d, 창 이탈까지 $((7 - age_days))d) — claude exit=0 이나 route JSON 미생성"
    else
      log "backlog 미처리 잔존: $D (age=${age_days}d) — 차기 런 재합류 예정, 경보 유예"
    fi
  done
  if [ -n "$EXPIRING" ]; then
    scheduler_alert "paper_router" "backlog_expiring" "claude exit=0 이나 route JSON 미생성 백로그가 7일 창 만료 임박: $EXPIRING — 창 이탈 시 무경보 영구 좌초, 수동 라우팅 또는 창 내 재처리 필요"
  fi
fi
# --- (2026-08-22 도훈 지시 "완주할 때마다") 완주 알림 — tg_agent_brief() 단일 진입점 경유.
_ROUTE_AFTER=$(ls -1 "$_ROUTE_DIR"/alpha_search_route_*.json 2>/dev/null | wc -l | tr -d " ")
_ROUTE_DELTA=$(( ${_ROUTE_AFTER:-0} - ${_ROUTE_BEFORE:-0} ))
_EFFECT_CMP="SAME"
[ "${_ROUTE_DELTA:-0}" -gt 0 ] && _EFFECT_CMP="CHANGED"
_BL_N=0
[ -n "${BACKLOG_DATES:-}" ] && _BL_N=$(printf "%s" "$BACKLOG_DATES" | tr "," "\n" | grep -c .)
_RS="$BASE/02_Infrastructure/ops/research_run_notify.R"
if [ -f "$_RS" ] && [ "${QVEST_RUN_NOTIFY:-1}" = "1" ]; then
  QM_ROOT="$BASE" Rscript --no-save "$_RS" "paper_router" "${_BL_N:-0}" "${_ROUTE_DELTA:-0}" "$_EFFECT_CMP" "$rc" >> "$LOG" 2>&1 || log "완주 알림 실패(비치명)"
fi
exit 0
