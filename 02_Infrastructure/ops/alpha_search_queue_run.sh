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
# (2026-08-02 수리) 아래 블록은 `08_Tests/ops/test_alpha_queue_pending.py` 가 **이 파일에서
#   heredoc 을 그대로 추출**해 픽스처로 돌린다(복사본 검사 금지 — 사본은 드리프트한다).
#   시작/끝 마커(`<<'PY'` … 단독 `PY`)를 바꾸면 검사기부터 고칠 것.
N=$("$PYBIN" - "$SD" <<'PY'
import json, sys, glob, os, re
sd=sys.argv[1]

# ── (2026-08-02 결함1 수리) id 표기 정규화.
#   생산자 3계열이 서로 다른 표기를 낸다 — 실측:
#     alpha_search_route_20260727.json  papers[].id      = "arxiv:2607.19497"
#     그 외 route(0619~0726) / 구 queue  .id/.arxiv_id    = bare "2607.19497"
#     alpha_search_queue_done.json      processed[]      = bare
#   → 정규화 없이 문자열 비교하면 `pid not in done` 이 **항상 참** → 이미 소비·QUARANTINE
#     판정난 건이 영구 pending 으로 남는다(07-27 소비분 2건이 그 자리였다).
#   ★curated 논문 id 는 arXiv 형태가 아닌 파일명(MAN_AHL_*.pdf 등, 실측 15건)이므로
#     arXiv 꼴일 때만 접두/버전을 벗기고 그 외는 원형 보존한다.
_AXPFX = re.compile(r"^(?:https?://)?(?:www\.)?(?:arxiv\.org/(?:abs|pdf)/|arxiv[:/])", re.I)
_AXID  = re.compile(r"^(\d{4}\.\d{4,5})(?:v\d+)?$")
def nid(v):
    s = str(v if v is not None else "").strip()
    if not s: return ""
    s = _AXPFX.sub("", s).strip()
    m = _AXID.match(s)
    return m.group(1) if m else s

# ── (2026-08-02 결함2 수리) id 키 이름 드리프트.
#   구판은 `id` → `arxiv_id` 만 봤는데 queue_20260726/20260727 의 candidates 는 키가
#   `paper_id` 다 → pid='' → 해당 후보 **전부 침묵 미계수**(결함1과 반대 방향의 오계수).
#   구 파일(0619/0621)만 `id` 라 우연히 계수되고 있었다.
_IDKEYS = ("paper_id", "id", "arxiv_id")
def pid_of(o, src):
    vals = {nid(o.get(k)) for k in _IDKEYS if o.get(k)}
    vals.discard("")
    if len(vals) > 1:
        # 같은 레코드가 서로 다른 id 를 이고 있으면 어느 쪽을 골라도 오계수다. 숨기지 않는다.
        sys.stderr.write("[alpha_queue] id 키 충돌 %s: %s\n" % (src, sorted(vals)))
    for k in _IDKEYS:
        v = nid(o.get(k))
        if v: return v
    return ""

# ── (2026-08-02) verdict 위치 드리프트 — queue_20260726 은 candidate **최상위** verdict 이고
#   route/구 queue 는 factor_candidate.verdict 다. 한쪽만 보면 역시 침묵 미계수.
def testable(o):
    fc = o.get("factor_candidate") or {}
    v = str(fc.get("verdict") or o.get("verdict") or "").strip().lower()
    if v == "testable": return True
    return o.get("route") == "alpha" and bool(o.get("kr_feasible"))

# ── (2026-08-02) 위 두 수리로 **새 후보를 읽게 되므로** 이미 종결된 레코드를 되살리지 않도록
#   레코드 자신의 종결 표식을 존중한다(done 원장 누락분 — 결함3 — 에 대한 2차 방어이기도 하다).
_TERMINAL = {"quarantine","quarantined","adopt","adopted","done","processed","skip","skipped"}
def resolved(o):
    for k in ("status","gate_decision"):
        if str(o.get(k) or "").strip().lower() in _TERMINAL: return True
    return False

done=set()
dp=os.path.join(sd,"alpha_search_queue_done.json")
if os.path.exists(dp):
    try:
        _d=json.load(open(dp,encoding="utf-8"))
        done={nid(x) for x in (_d.get("processed") or []) if nid(x)}
        # records[] 도 소비 사실이다 — processed append 를 빠뜨린 런이 실재한다(결함3).
        for r in (_d.get("records") or []):
            if isinstance(r,dict):
                v=pid_of(r,"done.records")
                if v: done.add(v)
    except Exception: done=set()

pend=set()
def scan(objs, src):
    for o in objs:
        if not isinstance(o, dict): continue
        p = pid_of(o, src)
        if p and p not in done and testable(o) and not resolved(o):
            pend.add(p)

for f in glob.glob(os.path.join(sd,"alpha_search_queue_*.json")):
    if f.endswith("_done.json"): continue
    try: d=json.load(open(f,encoding="utf-8"))
    except Exception: continue
    scan(d.get("candidates") or [], os.path.basename(f))
for f in glob.glob(os.path.join(sd,"alpha_search_route_*.json")):
    try: r=json.load(open(f,encoding="utf-8"))
    except Exception: continue
    scan(r.get("papers") or [], os.path.basename(f))
print(len(pend))
PY
)
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
