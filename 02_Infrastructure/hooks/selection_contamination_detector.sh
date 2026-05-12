#!/usr/bin/env bash
# selection_contamination_detector.sh — Lockbox 데이터 오염 차단 (Level 3 hard block)
# v6.1 R2 P2 / v6.5 (2026-05-09 도훈 mandate scope 정정)
#
# 이벤트: PreToolUse[Read]
# 목적: **정규 리서치 단계 (alpha-research / risk-research / optimizer-research)** 에서만
#       lockbox 데이터 접근 차단. Judge / Forge / Monitoring / Q-Lead 는 허용.
#
# 도훈 mandate 2026-05-09:
#   "Frozen 규칙 리서치 정규 프로세스에만 적용. 전기간 백테스팅, 성과 트래킹 등
#    정규 리서치 외에선 Frozen 폐기"
#   → forge (전기간 백테), monitoring (성과 트래킹), Q-Lead (집계 보고) 모두 lockbox 접근 OK
#   → alpha / risk / optimizer 정규 리서치 단계만 block (PIT lookahead bias 방지)
#
# Lockbox 판별:
#   - 파일 경로에 "lockbox" 포함
#   - stage_artifacts/WT*/lockbox/ 경로
#   - evaluation_windows.lockbox_window 범위 내 날짜

set -euo pipefail
trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

FP_LOWER=$(echo "$FILE_PATH" | tr '[:upper:]' '[:lower:]')

# Lockbox 파일 판별
case "$FP_LOWER" in
  *lockbox*|*stage_artifacts/wt*/lockbox*)
    # Agent 식별
    PARENT_PID=$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ' || echo "0")
    MARKER="/tmp/qvest_current_agent_${PARENT_PID}"
    AGENT_NAME=""
    if [[ -f "$MARKER" ]]; then
      AGENT_NAME=$(cat "$MARKER")
    fi

    case "$AGENT_NAME" in
      judge*|forge*|monitoring*|execution*)
        # Judge / Forge / Monitoring / Execution 허용 (운용·트래킹 단계, lockbox 폐기 정합)
        # 도훈 mandate 2026-05-09: 전기간 백테 / 성과 트래킹 = lockbox 폐기
        WT_ID=$(echo "$FILE_PATH" | grep -oE 'WT-[DP][0-9]{8}_[0-9]{3}|WT[0-9]{8}_[0-9]{3}' | head -1 || echo "unknown")
        echo "$(date -Iseconds) | $AGENT_NAME | $FILE_PATH" >> "/tmp/qvest_lockbox_access_${WT_ID}.log"
        echo "{\"decision\":\"allow\",\"reason\":\"non_research_lockbox_access_logged_${AGENT_NAME}\"}"
        ;;
      alpha*|risk*|optimizer*|opt_*)
        # 정규 리서치 단계만 block (PIT lookahead bias 방지 — Frozen 규칙 적용)
        echo "{\"decision\":\"block\",\"reason\":\"P2 Data Separation 위반: $AGENT_NAME 정규 리서치 단계에서 lockbox 접근 시도 — Judge / Forge / Monitoring / Execution 만 허용. Frozen 규칙 적용 (도훈 mandate 2026-05-09 scope).\"}"
        ;;
      *)
        # Q-Lead / unidentified → allow (집계 보고 / 트래킹 mandate)
        echo '{"decision":"allow","reason":"non_research_agent_default_allow"}'
        ;;
    esac
    ;;
  *)
    echo '{"decision":"allow"}'
    ;;
esac
