#!/usr/bin/env bash
#==============================================================================
# dispatch_measurement_gate.sh — PreToolUse[Write] L3 hard block
# FR 등재는 metric_type=backtested(build_bt_result 실측)만. proxy/estimated/자체합성 차단.
# 차단 대상: factor_rotation_registry.json / FR_*_result.json 쓰기 시 proxy 수치 등재.
# Reference: .claude/rules/{measurement-graduation §1·§3, backtest-contract, factor-rotation}.md
# 우회: QVEST_SKIP_DISPATCH_MEASUREMENT_GATE=1 · 로그: /tmp/dispatch_measurement_gate.log
#==============================================================================
trap 'echo "{}"; exit 0' ERR
set -u
INPUT=$(cat 2>/dev/null || echo '{}')
LOG="/tmp/dispatch_measurement_gate.log"; TS="$(date '+%Y-%m-%d %H:%M:%S')"
[ "${QVEST_SKIP_DISPATCH_MEASUREMENT_GATE:-0}" = "1" ] && { echo '{}'; exit 0; }
FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
[ -z "$FILE_PATH" ] && { echo '{}'; exit 0; }
echo "$FILE_PATH" | grep -qE '(factor_rotation_registry\.json$|FR_[0-9A-Za-z_]+_result\.json$)' || { echo '{}'; exit 0; }
# proxy/estimated/unavailable metric_type로 FR 등재 시 block
if echo "$INPUT" | grep -qE 'metric_type.{1,15}(proxy|estimated|unavailable)'; then
  echo "[$TS] L3 BLOCK — FR 등재 proxy metric_type ($FILE_PATH)" >> "$LOG"
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"FR(factor rotation) 등재는 metric_type=backtested(build_bt_result 실측)만 허용. proxy/estimated 차단 — measurement-graduation §1(real-computation 의무). canonical_screen_bt 또는 build_bt_result 경유 실측 후 재시도."}}
EOF
  exit 0
fi
# 자체합성 패턴
if echo "$INPUT" | grep -qE 'prod\(1 *\+|cumprod\(1 *\+|0\.[0-9]+ *\* *r[0-9]'; then
  echo "[$TS] L3 BLOCK — FR 자체합성 패턴 ($FILE_PATH)" >> "$LOG"
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"FR 등재에 자체합성(prod(1+r)/cumprod/가중합) 감지. PerformanceAnalytics 표준함수 + build_bt_result 경유만 — backtest-contract.md / answer-principles.md."}}
EOF
  exit 0
fi
echo "[$TS] allow ($FILE_PATH)" >> "$LOG"
echo '{}'; exit 0
