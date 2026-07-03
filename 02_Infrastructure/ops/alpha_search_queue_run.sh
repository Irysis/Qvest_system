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
timeout 3000 "$CLAUDE_BIN" -p "$(printf 'TODAY=%s  MAX_ALPHA=%s\n\n%s\n' "$TODAY" "$MAXA" "$(cat "$PF")")" \
  --dangerously-skip-permissions >> "$LOG" 2>&1
log "claude -p exit=$?"
exit 0
