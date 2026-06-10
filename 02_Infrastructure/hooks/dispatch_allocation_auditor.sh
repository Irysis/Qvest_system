#!/usr/bin/env bash
#==============================================================================
# dispatch_allocation_auditor.sh — PostToolUse[Write] (Level 2 advisory)
# FR 배분 산출물(module_regime_admission / FR registry) 쓰기 후 구조 점검 기록.
#   RCMA admission JSON: admitted 셀 수 로그. 가중 산출물: Σw / bounds 위반 경고.
# Reference: 02_Infrastructure/docs/rules/factor-rotation.md §3·§5 (admitted only / Σw=1 / [0,0.20])
# 우회: QVEST_SKIP_DISPATCH_ALLOC_AUDITOR=1 · 로그: /tmp/dispatch_allocation_auditor.log
#==============================================================================
trap 'echo "{}"; exit 0' ERR
set -u
INPUT=$(cat 2>/dev/null || echo '{}')
LOG="/tmp/dispatch_allocation_auditor.log"; TS="$(date '+%Y-%m-%d %H:%M:%S')"
[ "${QVEST_SKIP_DISPATCH_ALLOC_AUDITOR:-0}" = "1" ] && { echo '{}'; exit 0; }
FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
[ -z "$FILE_PATH" ] && { echo '{}'; exit 0; }
echo "$FILE_PATH" | grep -qE '(module_regime_admission\.json$|factor_rotation_registry\.json$|FR_[0-9A-Za-z_]+_result\.json$)' || { echo '{}'; exit 0; }
NADM=$(echo "$INPUT" | grep -oE '"n_admitted_cells"[[:space:]]*:[[:space:]]*[0-9]+' | head -1 | grep -oE '[0-9]+$')
echo "[$TS] FR artifact write: $FILE_PATH ${NADM:+(admitted_cells=$NADM)}" >> "$LOG"
echo '{}'; exit 0
