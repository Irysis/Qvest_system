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
trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR

INPUT=$(cat)

SUBAGENT_TYPE=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("subagent_type",""))' 2>/dev/null || echo "")
PROMPT=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("prompt",""))' 2>/dev/null || echo "")

# WT ID 추출 (prompt 내부 WT{YYYYMMDD}_{NNN} 패턴)
WT_ID=$(echo "$PROMPT" | grep -oE 'WT[0-9]{8}_[0-9]{3}' | head -1 || echo "")

# WT ID 없으면 legacy mode → allow
if [[ -z "$WT_ID" ]]; then
  echo '{"decision":"allow","reason":"no_wt_id_legacy_mode"}'
  exit 0
fi

PROJECT_ROOT="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR="$PROJECT_ROOT/qepm/mailbox/worktask/$WT_ID"

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
    echo '{"decision":"allow"}'
    ;;
  optimizer-research)
    # Optimizer는 alpha + risk 필수
    check_prerequisite "alpha_package.json" "Alpha Agent 산출물"
    check_prerequisite "risk_package.json" "Risk Agent 산출물"
    echo '{"decision":"allow"}'
    ;;
  forge)
    # Forge WT 모드는 3 package 모두 필요
    # 단, prompt에 "BLEND" 또는 "WT"가 명시적으로 포함된 경우만 3-agent 모드로 간주
    if echo "$PROMPT" | grep -qE "3-agent|work_task|BLEND_WT"; then
      check_prerequisite "alpha_package.json" "Alpha Agent 산출물"
      check_prerequisite "risk_package.json" "Risk Agent 산출물"
      check_prerequisite "optimization_package.json" "Optimizer Agent 산출물"
    fi
    echo '{"decision":"allow"}'
    ;;
  *)
    echo '{"decision":"allow"}'
    ;;
esac
