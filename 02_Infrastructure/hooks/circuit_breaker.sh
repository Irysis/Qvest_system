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
# Circuit Breaker — PostToolUse[Bash] Hook (v52 하네스)
# 동일 전략 3회 연속 Rscript 실패 시 자동 차단.
# "무한 재시도 금지" 규칙의 기계적 강제.
#==============================================================================

trap 'exit 0' ERR

INPUT=$(cat)
MAX_FAIL=3

# Bash command + output 추출
PARSED=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {})
    tr = d.get('tool_result', {})
    cmd = ti.get('command', '')
    stdout = tr.get('stdout', '') if isinstance(tr, dict) else str(tr)[:2000]
    print(cmd)
    print('---SEP---')
    print(stdout[:2000])
except:
    print('')
    print('---SEP---')
    print('')
" 2>/dev/null || echo "")

COMMAND=$(printf '%s' "$PARSED" | sed -n '1p')
OUTPUT=$(printf '%s' "$PARSED" | sed '1,/---SEP---/d')

# Rscript 실행인지 확인
if ! echo "$COMMAND" | grep -qi "rscript\|source.*run_all"; then
  exit 0
fi

# 전략 이름 추출 (STR_XXXX)
STR_NAME=$(echo "$COMMAND" | grep -oP 'STR_\d+[A-Za-z0-9_]*' | head -1)
if [ -z "$STR_NAME" ]; then exit 0; fi

COUNT_FILE="/tmp/circuit_breaker_${STR_NAME}.count"

# 에러 감지 (exit code 또는 Error 패턴)
IS_ERROR=0
if echo "$OUTPUT" | grep -qiE "^Error|fatal|execution halted|cannot open|stopped"; then
  IS_ERROR=1
fi

if [ "$IS_ERROR" -eq 1 ]; then
  # 실패 카운터 증가
  CURRENT=$(cat "$COUNT_FILE" 2>/dev/null || echo "0")
  NEW_COUNT=$((CURRENT + 1))
  echo "$NEW_COUNT" > "$COUNT_FILE"

  if [ "$NEW_COUNT" -ge "$MAX_FAIL" ]; then
    # 3회 도달 → 경고 (PostToolUse에서는 block 대신 additionalContext)
    echo "{\"additionalContext\":\"[Circuit Breaker] ${STR_NAME} ${NEW_COUNT}회 연속 실패. 원인 분류 → 수정 → 재실행 필수. /tmp/circuit_breaker_${STR_NAME}.count 리셋: echo 0 > ${COUNT_FILE}\"}"
    exit 0
  fi
else
  # 성공 시 카운터 리셋
  echo "0" > "$COUNT_FILE" 2>/dev/null
fi

exit 0
