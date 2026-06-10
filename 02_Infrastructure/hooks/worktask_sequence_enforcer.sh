#!/usr/bin/env bash
# worktask_sequence_enforcer.sh — QEPM WT 순차 실행 강제 (Level 3 hard block)
#
# 이벤트: PreToolUse[Agent]
# 목적:
#   - Risk Agent spawn 시 alpha_package.json 존재 확인
#   - Optimizer Agent spawn 시 alpha + risk package 존재 확인
#   - Forge spawn 시 3 package 모두 존재 확인 (WT 모드)
#
# 비-WT 모드 (기존 legacy): allow
#
# Hook JSON input (stdin):
#   {"hook_event_name":"PreToolUse", "tool_name":"Agent",
#    "tool_input":{"subagent_type":"...", "prompt":"..."}}

set -euo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)

SUBAGENT_TYPE=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("subagent_type",""))' 2>/dev/null || echo "")
PROMPT=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("prompt",""))' 2>/dev/null || echo "")

# WT ID 추출 (v6.1 WT-D/WT-P + legacy WT 모두 지원)
WT_ID=$(echo "$PROMPT" | grep -oE 'WT-[DP][0-9]{8}_[0-9]{3}|WT[0-9]{8}_[0-9]{3}' | head -1 || echo "")
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot 2>/dev/null | head -1)}}"
WT_DIR="$PROJECT_ROOT/qepm/mailbox/worktask/$WT_ID"

# v6.1 R9: Monitoring Agent는 WT ID 없어도 검증 필요 (book-wide 감시)
if [[ "$SUBAGENT_TYPE" == "monitoring" ]]; then
  BOOK_STATE="$PROJECT_ROOT/qepm/mailbox/governor/book_state.json"
  if [[ ! -f "$BOOK_STATE" ]]; then
    echo "{\"decision\":\"block\",\"reason\":\"R9 Monitoring: book_state.json 없음. Governor admission 후 생성 대기.\"}"
    exit 0
  fi
  N=$(python3 -c "import json; d=json.load(open('$BOOK_STATE')); print(len(d.get('admitted_ids',[])))" 2>/dev/null || echo "0")
  if [[ "$N" == "0" ]]; then
    echo "{\"decision\":\"block\",\"reason\":\"R9 Monitoring: admitted_ids 비어있음. 감시할 WT 없음.\"}"
    exit 0
  fi
  echo '{}'
  exit 0
fi

# WT ID 없으면 legacy mode → allow (monitoring 제외)
if [[ -z "$WT_ID" ]]; then
  echo '{}'
  exit 0
fi

check_prerequisite() {
  local pkg_file="$1"
  local pkg_desc="$2"
  local full_path="$WT_DIR/$pkg_file"
  if [[ ! -f "$full_path" ]]; then
    echo "{\"decision\":\"block\",\"reason\":\"WT $WT_ID: $pkg_desc 필요 ($pkg_file 없음). 이전 단계 agent 먼저 실행.\"}"
    exit 0
  fi
}

case "$SUBAGENT_TYPE" in
  risk-research|risk-manager)
    # Risk Agent는 alpha_package 필수
    check_prerequisite "alpha_package.json" "Alpha Agent 산출물"
    echo '{}'
    ;;
  optimizer-research)
    # Optimizer는 alpha + risk 필수
    check_prerequisite "alpha_package.json" "Alpha Agent 산출물"
    check_prerequisite "risk_package.json" "Risk Agent 산출물"
    echo '{}'
    ;;
  forge)
    # Forge WT 모드는 3 package 모두 필요
    if echo "$PROMPT" | grep -qE "3-agent|work_task|BLEND_WT"; then
      check_prerequisite "alpha_package.json" "Alpha Agent 산출물"
      check_prerequisite "risk_package.json" "Risk Agent 산출물"
      check_prerequisite "optimization_package.json" "Optimizer Agent 산출물"
    fi
    echo '{}'
    ;;
  execution)
    # v6.1 R8: Execution Agent는 Deployment WT의 optimization_package 필수
    # Discovery WT는 Execution 차단 (paper-trade only)
    if [[ "$WT_ID" == WT-D* ]]; then
      echo "{\"decision\":\"block\",\"reason\":\"R8 Execution Agent: Discovery WT ($WT_ID) 는 실집행 불가. Deployment WT (WT-P*) 로 graduation 후 재시도.\"}"
      exit 0
    fi
    check_prerequisite "optimization_package.json" "Optimizer Agent 산출물"
    # infeasibility_report null 체크
    INFEAS=$(python3 -c "import json; d=json.load(open('$WT_DIR/optimization_package.json')); print(d.get('infeasibility_report') or 'null')" 2>/dev/null || echo "null")
    if [[ "$INFEAS" != "null" && "$INFEAS" != "None" ]]; then
      echo "{\"decision\":\"block\",\"reason\":\"R8 Execution: optimization_package.infeasibility_report != null. WT abort 후 재검토.\"}"
      exit 0
    fi
    # Judge 통과 확인 (deployment WT는 JUDGE_PASSED + GOVERNOR_ADMITTED 후만 execution)
    PHASE=$(python3 -c "import json; print(json.load(open('$WT_DIR/status.json')).get('current_phase',''))" 2>/dev/null || echo "")
    if [[ "$PHASE" != "GOVERNOR_ADMITTED" && "$PHASE" != "EXECUTION_PENDING" ]]; then
      echo "{\"decision\":\"block\",\"reason\":\"R8 Execution: phase=$PHASE. GOVERNOR_ADMITTED 이후만 execution 허용.\"}"
      exit 0
    fi
    echo '{}'
    ;;
  *)
    echo '{}'
    ;;
esac
