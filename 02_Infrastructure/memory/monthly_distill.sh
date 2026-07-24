#!/bin/bash
# Monthly Memory Distillation — 매월 1일 06:00
# PATCH 2026-04-29 (L-247 trigger): resolve_project.sh + memory_logger.R path 정정
# PATCH 2026-07-25: 인라인 `Rscript -e '<한글 포함>'` 세그폴트(exit 139 침묵 no-op) 수리 —
#   본문을 monthly_distill.R로 분리, source() 경유 실행. Rscript 실패 시 exit 전파(침묵 성공 위장 차단).
source "$(dirname "${BASH_SOURCE[0]:-$0}")/../ops/resolve_project.sh"
cd "$PROJECT"

echo "[monthly_distill] $(date '+%Y-%m-%d %H:%M') Starting..."

Rscript --no-save -e 'source("02_Infrastructure/memory/monthly_distill.R")' 2>&1
rc=$?
if [ $rc -ne 0 ]; then
  echo "[monthly_distill] FAILED (Rscript exit $rc)"
  exit $rc
fi

echo "[monthly_distill] Done."
