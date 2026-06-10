#!/usr/bin/env bash
#==============================================================================
# factor_rotation_pit_guard.sh — PreToolUse[Write|Edit] (Level 2 advisory)
# FR 파이프라인 PIT 가드: 금지 shift 패턴(Cycle 50) / 자체합성(prod·cumprod) 경고.
# Reference: 02_Infrastructure/docs/rules/factor-rotation.md §5 / data_table_shift_convention.md / measurement-graduation.md
# 우회: QVEST_SKIP_FR_PIT_GUARD=1 · 로그: /tmp/factor_rotation_pit_guard.log
#==============================================================================
trap 'echo "{}"; exit 0' ERR
set -u
INPUT=$(cat 2>/dev/null || echo '{}')
LOG="/tmp/factor_rotation_pit_guard.log"; TS="$(date '+%Y-%m-%d %H:%M:%S')"
[ "${QVEST_SKIP_FR_PIT_GUARD:-0}" = "1" ] && { echo '{}'; exit 0; }
FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
[ -z "$FILE_PATH" ] && { echo '{}'; exit 0; }
# FR 파이프라인 R 파일만
echo "$FILE_PATH" | grep -qE '(factor_rotation/|module_dispatcher|regime_module_admission|build_module_performance|regime_forecaster|regime_engine_research)\.?[Rr]?' || { echo '{}'; exit 0; }
WARN=""
echo "$INPUT" | grep -qE 'shift\([^)]*n *= *-[0-9A-Za-z_]+[^)]*lead' && WARN="$WARN [shift(n=-H,type=lead) 금지: double-negation backward, data_table_shift_convention]"
echo "$INPUT" | grep -qE 'prod\(1 *\+|cumprod\(1 *\+' && WARN="$WARN [자체합성 prod/cumprod 금지: build_bt_result 실측만]"
if [ -n "$WARN" ]; then
  echo "[$TS] FR-PIT WARN ($FILE_PATH):$WARN" >> "$LOG"
  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[factor_rotation_pit_guard] FR PIT/실측 주의:$WARN. 국면은 t-1 lag, 측정은 build_bt_result 경유(measurement-graduation §1)."}}
EOF
  exit 0
fi
echo '{}'; exit 0
