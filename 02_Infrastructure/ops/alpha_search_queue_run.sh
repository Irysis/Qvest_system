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
  local RS_BIN
  RS_BIN="$(command -v Rscript || echo '/c/Program Files/R/R-4.5.2/bin/Rscript')"
  [ -x "$RS_BIN" ] || { log "alert telegram skip: Rscript 없음 (마커는 보존)"; return 0; }
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
                   "내용" = "${detail}",
                   "로그" = "${LOG}"))
  )
), error = function(e) { cat("tg fail:", conditionMessage(e), "\n"); NULL })
RS
  LC_ALL='English_United States.utf8' "$RS_BIN" "$rfile" >> "$LOG" 2>&1 \
    || log "alert telegram 발송 실패 (마커는 보존): $marker"
}

if [ "${QVEST_ALPHA_QUEUE_ENABLE:-0}" != "1" ]; then log "disabled (QVEST_ALPHA_QUEUE_ENABLE!=1) — skip"; exit 0; fi

# pending 카운트: 큐 candidates + route testable − done
N=$(python3 - "$SD" <<'PY'
import json, sys, glob, os
sd=sys.argv[1]
done=set()
dp=os.path.join(sd,"alpha_search_queue_done.json")
if os.path.exists(dp):
    try: done=set(json.load(open(dp,encoding="utf-8")).get("processed",[]))
    except: done=set()
pend=set()
for f in glob.glob(os.path.join(sd,"alpha_search_queue_*.json")):
    if f.endswith("_done.json"): continue
    try: d=json.load(open(f,encoding="utf-8"))
    except: continue
    for c in d.get("candidates",[]):
        pid=str(c.get("id") or c.get("arxiv_id") or "")
        fc=c.get("factor_candidate") or {}
        if pid and pid not in done and (fc.get("verdict")=="testable" or (c.get("route")=="alpha" and c.get("kr_feasible"))):
            pend.add(pid)
for f in glob.glob(os.path.join(sd,"alpha_search_route_*.json")):
    try: r=json.load(open(f,encoding="utf-8"))
    except: continue
    for p in r.get("papers",[]):
        pid=str(p.get("id") or p.get("arxiv_id") or "")
        fc=p.get("factor_candidate") or {}
        if pid and pid not in done and (fc.get("verdict")=="testable" or (p.get("route")=="alpha" and p.get("kr_feasible"))):
            pend.add(pid)
print(len(pend))
PY
)
N="${N:-0}"
log "pending testable(큐+route−done): $N"
if [ "$N" -eq 0 ] && [ "${QVEST_ALPHA_QUEUE_FORCE:-0}" != "1" ]; then
  log "pending 0 — skip (FORCE=1로 강제)"; exit 0
fi

CLAUDE_BIN="$(command -v claude || echo /c/Users/99922/AppData/Roaming/npm/claude)"
[ -x "$CLAUDE_BIN" ] || { log "claude CLI 없음 — skip"; exit 0; }
PF="$BASE/02_Infrastructure/ops/alpha_search_queue_prompt.md"
[ -f "$PF" ] || { log "prompt 없음 — skip"; exit 0; }
MAXA="${QVEST_ALPHA_QUEUE_MAX:-2}"
log "start alpha-search queue (pending=$N, MAX_ALPHA=$MAXA)"
PROMPT_TEXT="$(printf 'TODAY=%s  MAX_ALPHA=%s\n\n%s\n' "$TODAY" "$MAXA" "$(cat "$PF")")"
timeout 3000 "$CLAUDE_BIN" -p "$PROMPT_TEXT" \
  --dangerously-skip-permissions >> "$LOG" 2>&1
rc=$?
log "claude -p exit=$rc"
# v3 침묵 정지 경보화 (paper_router_run.sh와 동일): 실패가 로그에만 남고 exit 0 종료되는 구조 보완.
if [ "$rc" -ne 0 ]; then
  reason="exit_${rc}"
  tail -n 30 "$LOG" 2>/dev/null | grep -qi "spend limit" && reason="spend_limit"
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
    scheduler_alert "alpha_queue" "$reason" "claude -p exit=$rc (pending=$N MAX_ALPHA=$MAXA) — 큐 pending은 done 미기록이라 차기 런에서 재소비"
  fi
fi
exit 0
