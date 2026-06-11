#!/bin/bash
#==============================================================================
# safe_run.sh — 임의 커맨드 출력을 utf8_output_guard.py로 정제해 실행 (v8.1.2)
#
# Claude Code Bash tool에서 이모지/비ASCII 출력 가능성이 있는 커맨드를 돌릴 때:
#   bash 02_Infrastructure/ops/safe_run.sh <command> [args...]
# 예:
#   bash 02_Infrastructure/ops/safe_run.sh tail -50 /tmp/qm_boot_refresh_20260611_0900.log
#   bash 02_Infrastructure/ops/safe_run.sh Rscript -e 'source("02_Infrastructure/worktask/worktask_manager.R"); wt_list()'
#
# exit code는 원 커맨드의 것을 보존 (PIPESTATUS[0]).
# python3 부재 시 무가드 passthrough (exec).
#==============================================================================
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
if [ $# -eq 0 ]; then
  echo "usage: safe_run.sh <command> [args...]" >&2
  exit 2
fi
GUARD="$PROJECT/02_Infrastructure/ops/utf8_output_guard.py"
if [ -f "$GUARD" ] && python3 -c 'import sys' >/dev/null 2>&1; then
  "$@" 2>&1 | python3 -u "$(cygpath -m "$GUARD" 2>/dev/null || echo "$GUARD")"
  exit "${PIPESTATUS[0]}"
else
  echo "[safe_run] WARN: python3/guard 부재 — 무가드 passthrough (API 400 surrogate 방지 비활성)" >&2
  exec "$@"
fi
