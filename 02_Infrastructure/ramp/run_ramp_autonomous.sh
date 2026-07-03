#!/usr/bin/env bash
#==============================================================================
# run_ramp_autonomous.sh — RAMP 완전자율 루프 무인 구동 (Windows Task Scheduler용)
# 매 실행: Observe(ledger) → M-code 그리드 자동탐색 → Document(L-code) → best surface.
# 자본 편입은 governor 정지(도훈 수동) — 본 루프는 리서치+적립+surface만.
# segfault 가드: 잔류 Rscript 정리 + 단일스레드.
#==============================================================================
set -uo pipefail
export QM_ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
export CLAUDE_PROJECT_DIR="$QM_ROOT"
export R_DATATABLE_NUM_THREADS=1 OMP_NUM_THREADS=1 PYTHONUTF8=1
RSCRIPT="$(command -v Rscript || echo '/c/Program Files/R/R-4.5.2/bin/Rscript.exe')"
LOGDIR="$QM_ROOT/04_Research/ramp/reports"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/autonomous_loop.log"
echo "=== RAMP 자율 루프 $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG"
taskkill //F //IM Rscript.exe >/dev/null 2>&1 || true
sleep 1
cd "$QM_ROOT"
"$RSCRIPT" --no-save -e 'source("02_Infrastructure/ramp/run_ramp_autonomous.R")' >> "$LOG" 2>&1
EC=$?
echo "  exit=$EC | $(date '+%H:%M:%S')" >> "$LOG"
# 결과 요약 append (텍스트 산출물)
[ -f "$QM_ROOT/.cache/_ramp_autonomous.txt" ] && cat "$QM_ROOT/.cache/_ramp_autonomous.txt" >> "$LOG"
echo "=== DONE ===" >> "$LOG"
exit $EC
