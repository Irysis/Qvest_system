#!/bin/bash
#==============================================================================
# v53 Sprint 1: KPI 측정 스크립트
# - Pipeline 중복 실행률 (동일 strategy TRIGGER 2회 이상)
# - DONE_S5 → DONE_S6 전환 p95 latency
# - qlead_supervisor 자동 깨움 빈도 vs 수동 재진입 수
#==============================================================================

set -u
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh" 2>/dev/null || {
  # fallback
  PROJECT_ROOT=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
  export PROJECT_ROOT
}

LOG="/tmp/pipeline_trigger.log"
SV_LOG="/tmp/qlead_supervisor.log"

echo "=== v53 Sprint 1 KPI Report ($(date +%F)) ==="
echo

# 1. Pipeline 중복 실행률
if [ -f "$LOG" ]; then
  total=$(grep -c "TRIGGER:" "$LOG" 2>/dev/null)
  total=${total:-0}
  total=$(echo "$total" | tr -d '\n' | head -c 10)
  dup=$(grep "TRIGGER:" "$LOG" 2>/dev/null \
    | awk -F'(' '{print $NF}' \
    | sort | uniq -c | awk '$1 > 1 {sum += $1 - 1} END {print sum+0}')
  dup=${dup:-0}
  if [ "$total" -gt 0 ] 2>/dev/null; then
    pct=$(awk -v d="$dup" -v t="$total" 'BEGIN{printf "%.2f", (d/t)*100}')
  else
    pct="0.00"
  fi
  echo "📦 Pipeline TRIGGER total: $total | duplicates: $dup | dup%: ${pct}%"
else
  echo "📦 pipeline_trigger.log 없음 (아직 Hook 미작동 or 시작 직후)"
fi
echo

# 2. DONE_S5 → DONE_S6 p95 latency
if [ -f "$LOG" ]; then
  python3 << 'PY'
import re, os
from datetime import datetime, date
log = "/tmp/pipeline_trigger.log"
if not os.path.exists(log):
    print("log missing")
    raise SystemExit

# 패턴: 시간 + TRIGGER: Forge DONE_S5 → Judge+Codex TODO_S6 (STR_XXX)
# 패턴: 시간 + TRIGGER: Judge+Codex DONE_S6 → Judge TODO_S7 (STR_XXX)
s5_times = {}
latencies = []
with open(log) as f:
    for line in f:
        m = re.match(r'(\d\d:\d\d:\d\d).*DONE_S5.*\((STR_[A-Za-z0-9_]+)\)', line)
        if m:
            t, st = m.groups()
            s5_times[st] = t
            continue
        m = re.match(r'(\d\d:\d\d:\d\d).*DONE_S6.*→ Judge TODO_S7.*\((STR_[A-Za-z0-9_]+)\)', line)
        if m:
            t6, st = m.groups()
            if st in s5_times:
                try:
                    d5 = datetime.strptime(s5_times[st], "%H:%M:%S")
                    d6 = datetime.strptime(t6, "%H:%M:%S")
                    sec = (d6 - d5).total_seconds()
                    if sec >= 0:
                        latencies.append(sec)
                except: pass

if latencies:
    latencies.sort()
    p50 = latencies[len(latencies)//2]
    p95 = latencies[int(len(latencies)*0.95)]
    print(f"⏱  DONE_S5→S6 latency: n={len(latencies)} p50={p50:.1f}s p95={p95:.1f}s")
else:
    print("⏱  DONE_S5→S6 샘플 없음")
PY
else
  echo "⏱  log 없음"
fi
echo

# 3. qlead_supervisor 자동 깨움 빈도
if [ -f "$SV_LOG" ]; then
  auto=$(grep -c "\[sv\] pane .* woke" "$SV_LOG" 2>/dev/null || echo 0)
  echo "👻 supervisor 자동 깨움 (30초마다 check): ${auto}회"
else
  echo "👻 supervisor log 없음"
fi

echo
echo "=== KPI Report End ==="
