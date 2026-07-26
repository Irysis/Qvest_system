#!/bin/bash
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
N=$("$PYBIN" - "$SD" "$QUEUE" "$TODAY" <<'PY'
import json, sys, glob, os
sd, out = sys.argv[1], sys.argv[2]
today = sys.argv[3] if len(sys.argv) > 3 else None
done=set()
dp=os.path.join(sd,"factor_recheck_done.json")
if os.path.exists(dp):
    try:
        for x in json.load(open(dp,encoding="utf-8")).get("processed",[]):
            # processed[] = list of dicts {paper_id,date,verdict}; bare-string-tolerant
            pid = x.get("paper_id") if isinstance(x, dict) else x
            if pid: done.add(str(pid))
    except: done=set()
seen={}
for f in sorted(glob.glob(os.path.join(sd,"alpha_search_route_*.json"))):
    try: r=json.load(open(f,encoding="utf-8"))
    except: continue
    for p in r.get("papers",[]):
        fc=p.get("factor_candidate") or {}
        if fc.get("verdict")=="uncertain":
            pid=str(p.get("id") or p.get("arxiv_id") or p.get("paper_id") or "")
            if pid and pid not in done and pid not in seen:
                seen[pid]={"paper_id":pid,"title":p.get("title",""),"source":p.get("source",""),
                           "factor_hint":fc.get("name") or fc.get("factor_hint",""),
                           "prior_verdict":fc.get("verdict"),"prior_reason":fc.get("reason") or fc.get("summary","")}
items=list(seen.values())
json.dump({"date":today,"n":len(items),"items":items},
          open(out,"w",encoding="utf-8"),ensure_ascii=False,indent=2)
print(len(items))
PY
)
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
timeout 3000 "$CLAUDE_BIN" -p "$PROMPT_TEXT" \
  --dangerously-skip-permissions >> "$LOG" 2>&1
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
    timeout 3000 "$CLAUDE_BIN" -p "$PROMPT_TEXT" --model opus \
      --dangerously-skip-permissions >> "$LOG" 2>&1
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
