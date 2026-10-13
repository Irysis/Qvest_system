#!/usr/bin/env bash
# 세션에서 청정 레인 1회 실행 — 인증 정형(기억 카드 reference-session-launched-lanes-inherit-desktop-auth-env-20261010):
#   데스크톱 앱 세션 변수를 지우고 사용자 환경변수 CLAUDE_CODE_OAUTH_TOKEN 을 넘겨 bash -lc 로 rx_lane.sh 를 띄운다(토큰 값은 출력하지 않는다).
# 사용: bash run_lane.sh <lane_dir(절대)> [model=opus] [effort=max] [timeout_sec=3600]
set -u
LANE="${1:?usage: run_lane.sh <lane_dir> [model] [effort] [timeout]}"
MODEL="${2:-opus}"; EFFORT="${3:-max}"; TMO="${4:-3600}"
ROOTW="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
U=$(env | grep -E '^(CLAUDECODE|CLAUDE_CODE_|CLAUDE_AGENT_SDK_|ANTHROPIC_|CLAUDE_EFFORT|CLAUDE_PID|CLAUDE_PREVIEW_)' | cut -d= -f1 | sed 's/^/-u /' | tr '\n' ' ')
T="$(powershell.exe -NoProfile -Command "[Environment]::GetEnvironmentVariable('CLAUDE_CODE_OAUTH_TOKEN','User')" | tr -d '\r\n')"
if [ -z "$T" ]; then echo "[run_lane] 사용자 환경변수 토큰 없음 — 레인을 띄우지 않는다" >&2; exit 3; fi
env $U CLAUDE_CODE_OAUTH_TOKEN="$T" QM_ROOT="$ROOTW" CLAUDE_PROJECT_DIR="$ROOTW" \
  bash -lc "bash '$ROOTW/02_Infrastructure/programs/rx_lane.sh' '$LANE' '$MODEL' '$EFFORT' '$TMO'"
RC=$?
echo "[run_lane] $(basename "$LANE") rc=$RC"
exit $RC
