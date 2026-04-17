#!/bin/bash
#==============================================================================
# risk_gate.sh — PostToolUse[Bash] Hook
# 백테스트 실행 완료 후 tail_risk_result.json 포함 여부 경고
# Phase 1: warn only (block 아님)
# 작성: Forge (2026-04-09)
# 참조: tail_risk_engine.R, Pfaff (2016) Ch.7/Ch.12
#==============================================================================

trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
LOG="/tmp/risk_gate.log"

# 도구명 + 명령 추출
TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_name', ''))
" 2>/dev/null || echo "")

# Bash 도구가 아니면 즉시 통과
if [ "$TOOL_NAME" != "Bash" ]; then
  echo '{}'
  exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('command', ''))
" 2>/dev/null || echo "")

# 백테스트 실행 감지: Rscript + run_all.R 패턴
if ! echo "$COMMAND" | grep -qE 'Rscript.*source.*run_all|Rscript.*run_all\.R'; then
  echo '{}'
  exit 0
fi

# 인프라/테스트 코드 제외
case "$COMMAND" in
  *08_Tests*|*02_Infrastructure*|*test_*|*infra_*)
    echo '{}'
    exit 0
    ;;
esac

# 전략 ID 추출
STRAT_NAME=$(echo "$COMMAND" | grep -oP 'STR_\d+[A-Za-z0-9_]*' | head -1)

if [ -z "$STRAT_NAME" ]; then
  echo '{}'
  exit 0
fi

# 전략 디렉토리 탐색
PROJ_ROOT=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "")
STRAT_DIR=""

if [ -n "$PROJ_ROOT" ]; then
  STRAT_DIR=$(find "$PROJ_ROOT/04_Research/strategies" -maxdepth 1 -type d -name "${STRAT_NAME}*" 2>/dev/null | head -1)
fi

# tail_risk_result.json 존재 여부 확인
TAIL_RISK_JSON=""
if [ -n "$STRAT_DIR" ] && [ -d "$STRAT_DIR" ]; then
  TAIL_RISK_JSON=$(find "$STRAT_DIR" -name "tail_risk_result.json" 2>/dev/null | head -1)
fi

TIMESTAMP=$(date +%H:%M:%S)

if [ -z "$TAIL_RISK_JSON" ]; then
  # Phase 1: warn only (block 아님)
  echo "${TIMESTAMP} RISK_GATE_WARN: ${STRAT_NAME} — tail_risk_result.json 없음" >> "$LOG"

  MSG="[Risk Gate] ${STRAT_NAME}: tail_risk_result.json 미생성. compute_tail_risk_suite(sim_result, output_dir='${STRAT_DIR}', strategy_id='${STRAT_NAME}') 호출 권장. (Phase 1: warn only)"

  # warn via hookSpecificOutput (PostToolUse additionalContext)
  MSG_ESC=$(printf '%s' "$MSG" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}' "$MSG_ESC"
  exit 0
else
  echo "${TIMESTAMP} RISK_GATE_PASS: ${STRAT_NAME} — $(basename $TAIL_RISK_JSON) 확인됨" >> "$LOG"
  echo '{}'
  exit 0
fi
