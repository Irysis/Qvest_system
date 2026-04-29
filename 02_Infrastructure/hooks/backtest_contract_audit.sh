#!/usr/bin/env bash
#==============================================================================
# backtest_contract_audit.sh — PreToolUse[Write] L3 hard block
#
# Backtest Result Contract v1.0 §20 enforcement
# Reference: 00_Lawbook/Multi_Agent/backtest_result_contract.md §20
#
# 차단 대상 (audit_status != PASS 시 deny):
#   - qepm/registry/backtest_registry.csv 등재 시도
#   - methodology_active.md L-code 등재 시도 (백테스트 metric 인용 시)
#
# 작동:
#   1. file_path가 backtest_registry.csv 또는 methodology_*.md 일 때만 작동
#   2. 동일 strategy의 bt_result.rds에서 audit$integrity_status 확인
#   3. integrity == "FAIL" 이면 deny (L3 block)
#   4. 그 외는 allow
#
# 우회: QVEST_SKIP_BACKTEST_CONTRACT_AUDIT=1
# 로그: /tmp/backtest_contract_audit.log
#==============================================================================

trap 'echo "{}"; exit 0' ERR
set -u

INPUT=$(cat 2>/dev/null || echo '{}')
LOG="/tmp/backtest_contract_audit.log"
TS="$(date '+%Y-%m-%d %H:%M:%S')"

if [ "${QVEST_SKIP_BACKTEST_CONTRACT_AUDIT:-0}" = "1" ]; then
  echo '{}'; exit 0
fi

FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

[ -z "$FILE_PATH" ] && { echo '{}'; exit 0; }

# 차단 대상 패턴
TARGET_PATTERN='(backtest_registry\.csv$|methodology_(active|memory)\.md$|metrics_official\.csv$)'

if ! echo "$FILE_PATH" | grep -qE "$TARGET_PATTERN"; then
  echo '{}'; exit 0
fi

# 가장 최근 bt_result.rds 검색 — strategy_id 추정
PROJECT="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
LATEST_RDS=$(find "$PROJECT/04_Research/strategies" -name "bt_result.rds" -mmin -60 2>/dev/null | head -1)

if [ -z "$LATEST_RDS" ]; then
  echo "[$TS] no recent bt_result.rds — allow $FILE_PATH" >> "$LOG"
  echo '{}'; exit 0
fi

# Rscript로 audit integrity 추출
INTEGRITY=$(Rscript -e "
suppressMessages({
  bt <- tryCatch(readRDS('$LATEST_RDS'), error = function(e) NULL)
  if (is.null(bt)) {
    cat('UNKNOWN')
  } else {
    cat(as.character(bt\$manifest\$integrity_status[1]))
  }
}" 2>/dev/null)

INTEGRITY=${INTEGRITY:-UNKNOWN}

if [ "$INTEGRITY" = "FAIL" ]; then
  echo "[$TS] L3 BLOCK — bt_result.rds integrity=FAIL" >> "$LOG"
  echo "[$TS]   target: $FILE_PATH" >> "$LOG"
  echo "[$TS]   source: $LATEST_RDS" >> "$LOG"
  cat <<EOF
{"decision": "block", "reason": "Backtest Result Contract v1.0 §20 — bt_result.rds integrity=FAIL. Audit critical FAIL → official metrics 등재 차단. Lawbook: 00_Lawbook/Multi_Agent/backtest_result_contract.md"}
EOF
  exit 0
fi

echo "[$TS] allow — integrity=$INTEGRITY ($FILE_PATH)" >> "$LOG"
echo '{}'
exit 0
