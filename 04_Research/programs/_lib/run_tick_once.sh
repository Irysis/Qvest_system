#!/usr/bin/env bash
# 세션에서 무인 tick 1회 실행 — 스케줄러(Qvest_ReinforceAutoLoop)가 부르는 그 진입점(reinforce_auto_tick.sh)을 그대로 부른다.
#   tick = 리프레시 배리어 → 충실구현 레인(rf_replication_auto.sh · 청정 재구현 → 사전검사 → 측정 → 충실도 감사 → 검증기) → 2계층 레인(자기 스위치).
#   인증 정형 = run_lane.sh 와 같다(데스크톱 세션 변수 제거 · 사용자 환경변수 CLAUDE_CODE_OAUTH_TOKEN 전달 · 토큰 값은 출력하지 않는다).
# 사용: bash run_tick_once.sh
set -u
ROOTW="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
U=$(env | grep -E '^(CLAUDECODE|CLAUDE_CODE_|CLAUDE_AGENT_SDK_|ANTHROPIC_|CLAUDE_EFFORT|CLAUDE_PID|CLAUDE_PREVIEW_)' | cut -d= -f1 | sed 's/^/-u /' | tr '\n' ' ')
T="$(powershell.exe -NoProfile -Command "[Environment]::GetEnvironmentVariable('CLAUDE_CODE_OAUTH_TOKEN','User')" | tr -d '\r\n')"
if [ -z "$T" ]; then echo "[run_tick_once] 사용자 환경변수 토큰 없음 — tick 을 띄우지 않는다" >&2; exit 3; fi
env $U CLAUDE_CODE_OAUTH_TOKEN="$T" QM_ROOT="$ROOTW" CLAUDE_PROJECT_DIR="$ROOTW" \
  bash -lc "bash '$ROOTW/02_Infrastructure/ops/reinforce_auto_tick.sh'"
RC=$?
echo "[run_tick_once] rc=$RC"
exit $RC
