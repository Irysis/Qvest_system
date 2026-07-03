#!/bin/bash
# paper_router_run.sh — 헤드리스 claude 논문 스타일 라우터 (옵션1, 도훈 mandate 2026-06-18)
# recharge 후 당일 적재 논문을 분류(route) → alpha_search∧feasible 자동 alpha-search(cap) → 나머지 큐 → 텔레그램.
# 무인. claude -p --dangerously-skip-permissions. batch_434 오염 방지 가드는 prompt에.
#
# 게이트(전부 통과해야 실행):
#   QVEST_PAPER_ROUTER_ENABLE=1  — 라우터 자체 on (기본 0=off, kill-switch)
#   당일 mcp_discovery_<TODAY>.json 존재 (recharge가 돌았음)
#   당일 신규 다운로드>0 (또는 QVEST_PAPER_ROUTER_FORCE=1)
# 옵션:
#   QVEST_PAPER_ROUTER_AUTORUN=1 — alpha∧feasible 자동 alpha-search 실행 (기본 0=분류·큐·텔레그램만)
#   QVEST_PAPER_ROUTER_MAX_ALPHA=N — 1일 자동 alpha-search 상한 (기본 2)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
BASE="${BASE:-${PROJECT:-$PWD}}"; PROJECT="${PROJECT:-$BASE}"
cd "$BASE" || exit 1
TODAY=$(date +%Y%m%d)
LOG="$BASE/.cache/scheduler_logs/paper_router_${TODAY}.log"
mkdir -p "$(dirname "$LOG")"

log(){ echo "$(date -Iseconds) [router] $*" >> "$LOG"; }

if [ "${QVEST_PAPER_ROUTER_ENABLE:-0}" != "1" ]; then
  log "disabled (QVEST_PAPER_ROUTER_ENABLE!=1) — skip"; exit 0
fi
DISC="$BASE/stage_artifacts/paper_recharge/mcp_discovery_${TODAY}.json"
[ -f "$DISC" ] || { log "no discovery JSON for $TODAY — skip"; exit 0; }
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
if [ "$DL" -eq 0 ] && [ "$curated_pending" -eq 0 ] && [ "${QVEST_PAPER_ROUTER_FORCE:-0}" != "1" ]; then
  log "no new arxiv downloads (downloaded=$DL) and no pending curated — skip (QVEST_PAPER_ROUTER_FORCE=1 로 강제)"; exit 0
fi
log "trigger: downloaded=$DL curated_pending=$curated_pending"

CLAUDE_BIN="$(command -v claude || echo /c/Users/99922/AppData/Roaming/npm/claude)"
[ -x "$CLAUDE_BIN" ] || { log "claude CLI not found ($CLAUDE_BIN) — skip"; exit 0; }
PROMPT_FILE="$BASE/02_Infrastructure/ops/paper_router_prompt.md"
[ -f "$PROMPT_FILE" ] || { log "prompt file missing — skip"; exit 0; }
AUTORUN="${QVEST_PAPER_ROUTER_AUTORUN:-0}"
CAP="${QVEST_PAPER_ROUTER_MAX_ALPHA:-2}"

log "start (downloaded=$DL, AUTORUN=$AUTORUN, MAX_ALPHA=$CAP)"
HEADER="TODAY=${TODAY}  AUTORUN=${AUTORUN}  MAX_ALPHA=${CAP}"
# 헤드리스 1-shot. timeout 가드(자동 alpha-search 포함 시 길어질 수 있어 50분).
timeout 3000 "$CLAUDE_BIN" -p "$(printf '%s\n\n%s\n' "$HEADER" "$(cat "$PROMPT_FILE")")" \
  --dangerously-skip-permissions >> "$LOG" 2>&1
rc=$?
log "claude -p exit=$rc"
exit 0
