#!/bin/bash
#==============================================================================
# health_full.sh — 전수 점검 (주간/수동 전용, v9 2026-08-23)
#   구 bootstrap.sh 전문(검사 ~40절)이 여기로 강등됐다. **세션(/qvest)에서 자동 호출 금지** —
#   부팅은 ops/boot_lean.sh 5줄이 전부다. digest 의 WARN 은 도훈이 지시할 때만 수리 대상.
# Usage: bash 02_Infrastructure/ops/health_full.sh [--with-tests]
#==============================================================================
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
cd "$PROJECT" || exit 0
echo "=== health_full: bootstrap.sh (구 전체 부팅) ==="
bash "$PROJECT/02_Infrastructure/ops/bootstrap.sh" || true
echo "=== health_full: alerts_digest_build.sh ==="
bash "$PROJECT/02_Infrastructure/ops/alerts_digest_build.sh" || true
if [ "${1:-}" = "--with-tests" ]; then
  echo "=== health_full: run_all_hooks.sh (전체 배터리) ==="
  bash "$PROJECT/08_Tests/hooks/run_all_hooks.sh" || true
fi
echo "=== health_full 완료 — digest: .cache/alerts_digest.md ==="
