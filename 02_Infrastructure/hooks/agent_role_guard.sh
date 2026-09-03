#!/usr/bin/env bash
# ★v10 (2026-09-03) 주의 — 이 파일은 v9 등록 해제분(사료)이고 본문의 governor 역할 경계·judge_lockbox_audit 허용 분기 가 남아 있다.
#   전부 v10 폐지 개념(lockbox·governor·book_state·cert)이므로 **재등록 금지** — 되살리려면 그 분기를 먼저
#   제거하고 양성/음성 대조를 다시 만들 것. 파일 자체는 08_Tests·hook_e2e_battery 가 경로로 실행한다(이동 금지).
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
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
# Output: {}

set -euo pipefail
trap 'echo "{}"; exit 0' ERR
export PYTHONUTF8=1  # (v8.1.2) 인코딩 사고 방지 — harness.md "Hook stdout JSON 규율"

# stdin JSON 파싱 (v8.1.2: bytes 경유 UTF-8 명시 — locale 의존 제거)
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; sys.stdout.reconfigure(encoding="utf-8",errors="replace"); d=json.loads(sys.stdin.buffer.read().decode("utf-8","replace")); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

# Agent 식별 (환경변수 또는 agent_id marker file)
# Claude Code teammate system에서 agent name은 env var CLAUDE_AGENT_NAME 또는 process context로 식별
# 임시 접근: marker file /tmp/qvest_current_agent_{pid}
# (v8.1.2) bash 내장 $PPID 사용 — MSYS ps는 -o 미지원이라 PARENT_PID가 항상 빈값
# → marker 미발견 → 역할 가드가 이 머신에서 상시 allow로 침묵 무력화되던 결함 수리
PARENT_PID="${PPID:-0}"
MARKER="/tmp/qvest_current_agent_${PARENT_PID}"
AGENT_NAME=""
if [[ -f "$MARKER" ]]; then
  AGENT_NAME=$(cat "$MARKER")
fi

# Agent 식별 실패 시 allow (teammate 안전 우회)
if [[ -z "$AGENT_NAME" ]]; then
  echo '{}'
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
  echo '{}'
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
  echo '{}'
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
  echo '{}'
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
  echo '{}'
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
  echo '{}'
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
  echo '{}'
}

check_judge_agent() {
  # v6.2: Judge Agent boundary
  # 허용 쓰기: judge_verdict.json, judge_lockbox_audit.json (harness 전용), judge_challenge_note.md
  # 금지: alpha/risk/optimization/forge package 수정, weights.csv, governor 산출물
  case "$FP_LOWER" in
    */alpha_package.json|*/alpha_scores*.parquet|*/alpha_validation.json)
      echo '{"decision":"block","reason":"v6.2 Judge: Alpha package 수정 금지 (audit 권한만, 수정은 alpha agent 영역)."}'
      exit 0
      ;;
    */risk_package.json|*/covariance*.parquet|*/tail_risk.json)
      echo '{"decision":"block","reason":"v6.2 Judge: Risk package 수정 금지 (audit 권한만)."}'
      exit 0
      ;;
    */optimization_package.json|*/weights*.csv|*/weight_method_*)
      echo '{"decision":"block","reason":"v6.2 Judge: Optimizer package + weights 수정 금지 (audit 권한만)."}'
      exit 0
      ;;
    */forge_package.json|*/forge_phase4_package.json|*/run_all.R)
      echo '{"decision":"block","reason":"v6.2 Judge: Forge 산출물 수정 금지 (audit 권한만, Lockbox harness는 별도 sub만)."}'
      exit 0
      ;;
    */governor_admission*|*/book_state.json|*/pg*_*.json)
      echo '{"decision":"block","reason":"v6.2 Judge: Governor 영역 수정 금지."}'
      exit 0
      ;;
  esac
  echo '{}'
}

check_governor_agent() {
  # v6.2: Governor Agent boundary
  # 허용: governor_admission.json, book_state.json, governor_challenge_note.md, PG_rebalance_*.json
  # 금지: alpha/risk/optimization/forge/judge 산출물 수정
  case "$FP_LOWER" in
    */alpha_package.json|*/alpha_scores*.parquet|*/alpha_validation.json)
      echo '{"decision":"block","reason":"v6.2 Governor: Alpha package 수정 금지 (admission 권한만)."}'
      exit 0
      ;;
    */risk_package.json|*/covariance*.parquet|*/tail_risk.json)
      echo '{"decision":"block","reason":"v6.2 Governor: Risk package 수정 금지."}'
      exit 0
      ;;
    */optimization_package.json|*/weights*.csv)
      echo '{"decision":"block","reason":"v6.2 Governor: Optimizer package + weights 수정 금지."}'
      exit 0
      ;;
    */forge_package.json|*/forge_phase4_package.json|*/run_all.R|*/backtest_result/*)
      echo '{"decision":"block","reason":"v6.2 Governor: Forge 산출물 수정 금지."}'
      exit 0
      ;;
    */judge_verdict*|*/judge_lockbox_audit*|*/judge_ready/*|*/judge_challenge_note*)
      echo '{"decision":"block","reason":"v6.2 Governor: Judge 산출물 수정 금지 (audit 권한 침범)."}'
      exit 0
      ;;
  esac
  echo '{}'
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
  judge*)
    check_judge_agent
    ;;
  governor*)
    check_governor_agent
    ;;
  *)
    # Q-Lead / Codex 등은 allow (orchestration 권한)
    echo '{}'
    ;;
esac
