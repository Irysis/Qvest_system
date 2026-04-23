#!/usr/bin/env bash
# agent_role_guard.sh — QEPM 3-Agent 역할 경계 강제 (Level 3 hard block)
# supersedes: forge_code_guard.sh (archived 2026-04-23)
#
# 이벤트: PreToolUse[Write|Edit]
# 목적: Alpha/Risk/Optimizer Agent가 자기 역할 밖 파일 쓰기 시도 시 block
#
# 역할 경계:
#   Alpha Agent:    alpha_package.json, alpha_scores.parquet 만
#                   금지: covariance/*, weights.csv, risk_package.json
#   Risk Agent:     risk_package.json, covariance.parquet, tail_risk.json 만
#                   금지: alpha_scores, weights.csv, alpha_package.json 수정
#   Optimizer:      optimization_package.json, weights.csv 만
#                   금지: alpha_scores, covariance, 앞 package 수정
#
# Hook JSON input (stdin):
#   {"hook_event_name":"PreToolUse", "tool_name":"Write"|"Edit",
#    "tool_input":{"file_path":"..."}}
#
# Output: {"decision":"allow"|"block", "reason":"..."}

set -euo pipefail
trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR

# stdin JSON 파싱
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

# Agent 식별 (환경변수 또는 agent_id marker file)
# Claude Code teammate system에서 agent name은 env var CLAUDE_AGENT_NAME 또는 process context로 식별
# 임시 접근: marker file /tmp/qvest_current_agent_{pid}
PARENT_PID=$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ' || echo "0")
MARKER="/tmp/qvest_current_agent_${PARENT_PID}"
AGENT_NAME=""
if [[ -f "$MARKER" ]]; then
  AGENT_NAME=$(cat "$MARKER")
fi

# Agent 식별 실패 시 allow (teammate 안전 우회)
if [[ -z "$AGENT_NAME" ]]; then
  echo '{"decision":"allow","reason":"agent_unidentified_default_allow"}'
  exit 0
fi

# 파일 경로 소문자화 + 표준 패턴 매칭
FP_LOWER=$(echo "$FILE_PATH" | tr '[:upper:]' '[:lower:]')

check_alpha_agent() {
  # Alpha Agent 금지 경로
  case "$FP_LOWER" in
    */risk_package.json|*/covariance*.parquet|*/tail_risk.json|*/regime_correlation*.parquet)
      echo '{"decision":"block","reason":"Alpha Agent가 Risk Agent 산출물 쓰기 시도 — Common Charter 원칙 8 (No Silent Override) 위반"}'
      exit 0
      ;;
    */optimization_package.json|*/weights*.csv|*/weight_method_*)
      echo '{"decision":"block","reason":"Alpha Agent가 Optimizer Agent 산출물 쓰기 시도 — 역할 침범"}'
      exit 0
      ;;
  esac
  echo '{"decision":"allow"}'
}

check_risk_agent() {
  case "$FP_LOWER" in
    */alpha_package.json|*/alpha_scores*.parquet|*/alpha_hypothesis.json|*/alpha_validation.json)
      echo '{"decision":"block","reason":"Risk Agent가 Alpha Agent 산출물 쓰기/수정 시도 — Common Charter 원칙 8 위반"}'
      exit 0
      ;;
    */optimization_package.json|*/weights*.csv|*/weight_method_*)
      echo '{"decision":"block","reason":"Risk Agent가 Optimizer Agent 산출물 쓰기 시도 — 역할 침범"}'
      exit 0
      ;;
  esac
  echo '{"decision":"allow"}'
}

check_optimizer_agent() {
  case "$FP_LOWER" in
    */alpha_package.json|*/alpha_scores*.parquet|*/alpha_hypothesis.json|*/alpha_validation.json)
      echo '{"decision":"block","reason":"Optimizer Agent가 Alpha Agent 산출물 쓰기/수정 시도 — Common Charter 원칙 8 위반"}'
      exit 0
      ;;
    */risk_package.json|*/covariance*.parquet|*/tail_risk.json|*/regime_correlation*.parquet)
      echo '{"decision":"block","reason":"Optimizer Agent가 Risk Agent 산출물 쓰기/수정 시도 — 역할 침범"}'
      exit 0
      ;;
  esac
  echo '{"decision":"allow"}'
}

check_forge() {
  # v6.1 R12: Forge Pure Function — 3-agent 산출물 완전 read-only
  # Forge가 쓸 수 있는 것: run_all.R, output/*, backtest_result/*, stage_artifacts/WT_*/judge_ready/*
  case "$FP_LOWER" in
    */alpha_package.json|*/alpha_scores*.parquet|*/alpha_hypothesis.json|*/alpha_validation.json)
      echo '{"decision":"block","reason":"R12 Forge Pure Function: Alpha package 수정 금지. Forge는 통합만 (재해석 엔진化 방지, P4 No Silent Override)."}'
      exit 0
      ;;
    */risk_package.json|*/covariance*.parquet|*/tail_risk.json|*/regime_correlation*.parquet|*/exposure_matrix*)
      echo '{"decision":"block","reason":"R12 Forge Pure Function: Risk package 수정 금지. Forge는 통합만."}'
      exit 0
      ;;
    */optimization_package.json|*/weights*.csv|*/weight_method_selected*|*/optimizer_research*)
      echo '{"decision":"block","reason":"R12 Forge Pure Function: Optimizer package 수정 금지. Forge는 통합만."}'
      exit 0
      ;;
  esac
  echo '{"decision":"allow"}'
}

check_execution_agent() {
  # v6.1 R8: Execution Agent는 3-package 전수 read-only
  # 쓰기 허용: execution_package.json, trade_list.csv, realized_slippage_*.csv, impact_estimate.json
  case "$FP_LOWER" in
    */alpha_package.json|*/alpha_scores*.parquet|*/alpha_hypothesis.json|*/alpha_validation.json)
      echo '{"decision":"block","reason":"R8 Execution: Alpha package 수정 금지 (target_weights 재해석 차단)."}'
      exit 0
      ;;
    */risk_package.json|*/covariance*.parquet|*/tail_risk.json)
      echo '{"decision":"block","reason":"R8 Execution: Risk package 수정 금지."}'
      exit 0
      ;;
    */optimization_package.json|*/weights*.csv|*/weight_method_*)
      echo '{"decision":"block","reason":"R8 Execution: Optimizer package + weights.csv 수정 금지 (target_weights 불변)."}'
      exit 0
      ;;
    */judge_verdict*|*/judge_ready/*|*/judge_result*)
      echo '{"decision":"block","reason":"R8 Execution: Judge 산출물 수정 금지."}'
      exit 0
      ;;
    */governor_admission*|*/book_state.json|*/pg*_*.json)
      echo '{"decision":"block","reason":"R8 Execution: Governor 산출물 수정 금지."}'
      exit 0
      ;;
  esac
  echo '{"decision":"allow"}'
}

check_monitoring_agent() {
  # v6.1 R9: Monitoring Agent는 read-only + monitoring_report만 쓰기 허용
  case "$FP_LOWER" in
    */alpha_package.json|*/risk_package.json|*/optimization_package.json|*/execution_package.json)
      echo '{"decision":"block","reason":"R9 Monitoring: 타 agent 산출물 수정 금지 (read-only, drift 감지만)."}'
      exit 0
      ;;
    */weights*.csv|*/judge_verdict*|*/governor_admission*|*/book_state.json)
      echo '{"decision":"block","reason":"R9 Monitoring: 운영 산출물 수정 금지. 전략 수정 권한 없음 (Q-Lead 영역)."}'
      exit 0
      ;;
  esac
  echo '{"decision":"allow"}'
}

case "$AGENT_NAME" in
  alpha*)
    check_alpha_agent
    ;;
  risk*)
    check_risk_agent
    ;;
  optimizer*|opt_*)
    check_optimizer_agent
    ;;
  forge*)
    check_forge
    ;;
  execution*)
    check_execution_agent
    ;;
  monitoring*)
    check_monitoring_agent
    ;;
  *)
    # Q-Lead / Judge / Governor / Codex 등은 allow (orchestration 권한)
    echo '{"decision":"allow"}'
    ;;
esac
