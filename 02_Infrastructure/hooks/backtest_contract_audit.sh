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
#   - .py 백테스트 자체합성 idiom (python-policy.md §5, v8.x Phase 3 이행)
#
# 작동:
#   1. file_path가 backtest_registry.csv / methodology_*.md / *.py 일 때만 작동
#   1b. *.py 는 자체합성 idiom (np.prod(1+r) / (1+r).cumprod() / (w*r).sum()
#       / .prod()-1) 감지 시 deny (L3 block) — dispatch_measurement_gate.sh
#       R 패턴(prod(1+r)/cumprod)과 동일 구조의 $INPUT grep
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

# 차단 대상 패턴 (.py = python-policy.md §5 자체합성 커버리지)
TARGET_PATTERN='(backtest_registry\.csv$|methodology_(active|memory)\.md$|metrics_official\.csv$|\.py$)'

if ! echo "$FILE_PATH" | grep -qE "$TARGET_PATTERN"; then
  echo '{}'; exit 0
fi

# .py 자체합성 idiom L3 block (python-policy.md §4 금지 목록)
# 구조 = dispatch_measurement_gate.sh R 패턴(prod(1+r)/cumprod)과 동일 ($INPUT grep)
if echo "$FILE_PATH" | grep -qE '\.py$'; then
  PY_SYNTH_PATTERN='np\.prod\( *1 *\+|\( *1 *\+ *[A-Za-z_][A-Za-z0-9_.]* *\)\.cumprod\(|\( *w *\* *r *\)\.sum\(|\.prod\( *\) *- *1|0\.[0-9]+ *\* *r[0-9]'
  if echo "$INPUT" | grep -qE "$PY_SYNTH_PATTERN"; then
    echo "[$TS] L3 BLOCK — Python 자체합성 idiom 감지 ($FILE_PATH)" >> "$LOG"
    cat <<EOF
{"decision": "block", "reason": "python-policy.md §4 — Python backtest 자체합성 금지 (np.prod(1+r) / (1+r).cumprod() / (w*r).sum() / .prod()-1). Return.portfolio R bridge + build_bt_result 경유만 허용. Reference: .claude/rules/python-policy.md / backtest-contract.md"}
EOF
    exit 0
  fi
  # .py 는 자체합성 스캔만 수행 — registry/methodology integrity 체크 비대상
  echo "[$TS] allow — .py synth-scan clean ($FILE_PATH)" >> "$LOG"
  echo '{}'; exit 0
fi

# 가장 최근 bt_result.rds 검색 — strategy_id 추정
PROJECT="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-/c/Users/99922/OneDrive/Quant_Module_Moltbot}}"
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
