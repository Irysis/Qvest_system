#!/bin/bash
# ★RETIRED (v10 2026-09-03) — settings.json·라우터 어디에도 등록 이력이 없는 pre-v9 훅.
#   재등록 금지(되살리려면 v10 폐지 개념 분기부터 제거하고 양성/음성 대조를 새로 만들 것). 파일은 사료 존치.
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
#==============================================================================
# cash_sleeve_validator.sh — PostToolUse[Write] Hook (v55 Tier 3.1)
#
# STR_CASH_* 또는 role=cash_allocation 전략의 산출물 검증.
#  - cash_component 필드 존재 확인
#  - max_cash_weight <= 0.35 검증
#  - opportunity_cost_bps < 20 권장 확인 (warn)
#==============================================================================

trap 'echo "{}"; exit 0' ERR
export PYTHONUTF8=1  # (v8.1.2) additionalContext lone surrogate(API 400) 방지

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', ''))
except: print('')
" 2>/dev/null)

[ -z "$FILE" ] && { echo '{}'; exit 0; }

LOG="/tmp/cash_sleeve_validator.log"

# Cash sleeve 관련 파일만 처리
case "$FILE" in
  *STR_CASH_*hurdle_result.json|*cash_allocation_*.json|*s0_record_*cash*.json)
    V55_CHECK=$("$QVEST_PY_BIN" <<PYEOF
import json, sys
try:
    with open('$FILE') as f: d = json.load(f)
except Exception as e:
    print(f'PARSE_ERROR|{e}')
    sys.exit(0)

errors = []
warnings = []

role = d.get('role', '')
cc = d.get('cash_component') or {}

if role == 'cash_allocation':
    if not cc:
        errors.append('cash_allocation role requires cash_component')
    else:
        max_cw = cc.get('max_cash_weight', 0)
        if max_cw > 0.35:
            errors.append(f'max_cash_weight={max_cw} > 0.35 (admission threshold)')
        if max_cw <= 0:
            errors.append('max_cash_weight must be > 0')

    audit = d.get('audit_cash_allocation', {})
    if audit:
        opp_cost = audit.get('opportunity_cost_bps_annualized', 999)
        if opp_cost >= 20:
            warnings.append(f'opportunity_cost={opp_cost}bps >= 20bps (Gate 7 CONDITIONAL)')

if errors:
    print('BLOCK|' + '; '.join(errors))
elif warnings:
    print('WARN|' + '; '.join(warnings))
else:
    print('PASS|cash_sleeve_validator OK')
PYEOF
)

    V55_STATUS=$(echo "$V55_CHECK" | cut -d'|' -f1)
    V55_MSG=$(echo "$V55_CHECK" | cut -d'|' -f2-)

    if [ "$V55_STATUS" = "BLOCK" ]; then
      echo "$(date +%H:%M:%S) CASH_VALIDATOR BLOCK: $FILE — $V55_MSG" >> "$LOG"
      CTX=$(printf '%s' "[Cash Sleeve Validator] ${V55_MSG}. admission_rule_v352 §1.4 참조." | "$QVEST_PY_BIN" -c "import sys,json; s=sys.stdin.buffer.read().decode('utf-8','replace'); print(json.dumps(''.join(ch if not(0xD800<=ord(ch)<=0xDFFF) else '?' for ch in s)))")
      echo "{\"decision\":\"block\",\"reason\":${CTX}}"
      exit 0
    fi

    if [ "$V55_STATUS" = "WARN" ]; then
      echo "$(date +%H:%M:%S) CASH_VALIDATOR WARN: $FILE — $V55_MSG" >> "$LOG"
    else
      echo "$(date +%H:%M:%S) CASH_VALIDATOR PASS: $FILE" >> "$LOG"
    fi
    ;;
esac

echo '{}'
