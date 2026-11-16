#!/usr/bin/env bash
#==============================================================================
# paper_rigor_run.sh — 충실구현 큐 논문 방법론 수준 채점 (도훈 11-16 PAPER-ORDER-RIGOR-FILTER-20261116 = B)
#   큐 순서대로 아직 채점 안 된 논문을 N 편(기본 = 설정 daily_limit) 골라: 원문 축자본(rf_paper_text.py) → 프롬프트(paper_rigor.py prompt)
#   → LLM 1회(레인 paper_rigor · 단일 진입 rf_llm_agent_run · 도구 없음) → 기록 · low 면 건너뛰기 목록(paper_rigor.py ingest).
#   호출 = 아침 체인 morning_run.sh [0.515] · 손으로 `bash paper_rigor_run.sh [--limit N]`.
#   작업 폴더 = .cache/paper_rigor/<key>/ · 로그 = .cache/scheduler_logs/paper_rigor_<날짜>.log
# 끄기: QVEST_PAPER_RIGOR=0
#==============================================================================
set -u
[ "${QVEST_PAPER_RIGOR:-1}" = "0" ] && { echo "[paper_rigor] off"; exit 0; }
ROOT="${QM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)}"
cd "$ROOT" || exit 2
PY="${QVENV_PY:-.venv_qvest_ml/Scripts/python.exe}"
LIMIT="$("$PY" -X utf8 -c "import json;print(json.load(open('06_Registry/paper_rigor.json',encoding='utf-8')).get('daily_limit',20))" 2>/dev/null | tr -d '\r')"
REGRADE=()
while [ $# -gt 0 ]; do case "$1" in --limit) LIMIT="${2:-$LIMIT}"; shift 2 ;; --regrade) REGRADE=(--regrade); shift ;; *) shift ;; esac; done   # --regrade = 채점기 v2 전 기록 · low 건너뛰기까지 다시
LOG=".cache/scheduler_logs/paper_rigor_$(date +%Y%m%d).log"; mkdir -p .cache/scheduler_logs .cache/paper_rigor
. 02_Infrastructure/ops/rf_llm_env.sh
rf_llm_resolve paper_rigor "${QVEST_PR_MODEL:-}" "${QVEST_PR_EFFORT:-}"
LLM_FALLBACK_MODEL=""   # 이관 레인 규약(폴백 없음)
TODO="$("$PY" -X utf8 02_Infrastructure/ops/paper_rigor.py todo --limit "${LIMIT:-20}" ${REGRADE[@]+"${REGRADE[@]}"} 2>>"$LOG")"
[ -n "$TODO" ] || { echo "[paper_rigor] 채점할 논문 없음" | tee -a "$LOG"; exit 0; }
n=0; nlow=0
while IFS=$'\t' read -r KEY URL TITLE; do
  [ -n "$KEY" ] || continue
  W=".cache/paper_rigor/${KEY//[^A-Za-z0-9._-]/_}"; mkdir -p "$W"
  "$PY" -X utf8 02_Infrastructure/ops/rf_paper_text.py --url "$URL" --wdir "$W" >> "$LOG" 2>&1
  KIND="$("$PY" -X utf8 02_Infrastructure/ops/paper_rigor.py prompt "$KEY" "$TITLE" "$W/.clean_paper/paper.md" "$W/prompt.txt" 2>>"$LOG" | tr -d '\r')"
  if [ "$KIND" = "none" ]; then echo "NO_TEXT" > "$W/run.out"; LLM_RC=0; LLM_USED_MODEL=none; LLM_USED_EFFORT=none
  else rf_llm_agent_run "$W/prompt.txt" "$W/run.out" 900 --output-format text; fi
  OUT="$("$PY" -X utf8 02_Infrastructure/ops/paper_rigor.py ingest "$KEY" "$URL" "$TITLE" "$W/run.out" --text-kind "${KIND:-none}" --model "$LLM_USED_MODEL/$LLM_USED_EFFORT" 2>>"$LOG" | tr -d '\r')"
  echo "[paper_rigor $(date '+%F %T')] $KEY rc=$LLM_RC kind=$KIND $OUT" | tee -a "$LOG"
  n=$((n + 1)); case "$OUT" in *$'\t'low$'\t'*) nlow=$((nlow + 1)) ;; esac
done <<< "$TODO"
echo "[paper_rigor] 채점 $n 편 · low(큐 제외) $nlow 편" | tee -a "$LOG"
exit 0
