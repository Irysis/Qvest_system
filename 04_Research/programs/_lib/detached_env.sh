#!/usr/bin/env bash
# 세션 밖(WMI 분리 실행)에서 쓸 실행 환경 — 스케줄러 .bat 와 같은 경로 접두 + 프로젝트 루트.
#   세션 종료·재시작에 같이 죽지 않게 긴 측정을 세션 프로세스 트리 밖으로 띄울 때 source 한다(2026-10-14 · PC 꺼짐으로 DNN 계산 소실 뒤).
# 사용: bash detached_env.sh <스크립트> [로그]
export PATH="/c/Users/99922/AppData/Roaming/npm:/c/Users/99922/AppData/Local/Microsoft/WinGet/Packages/astral-sh.uv_Microsoft.Winget.Source_8wekyb3d8bbwe:/c/Users/99922/AppData/Local/Programs/Python/Python312:/c/Program Files/R/R-4.5.2/bin:/usr/bin:/mingw64/bin:$PATH"
export QM_ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot" CLAUDE_PROJECT_DIR="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
export QVEST_PY="$(powershell.exe -NoProfile -Command "[Environment]::GetEnvironmentVariable('QVEST_PY','User')" | tr -d '\r\n')"
export PYTHONUTF8=1
cd /c/Users/99922/OneDrive/Quant_Module_Moltbot || exit 2
S="${1:?script}"; L="${2:-/dev/null}"
echo "== $(date '+%F %T') 분리 실행 시작: $S (pid $$)" >> "$L"
bash "$S" >> "$L" 2>&1
echo "== $(date '+%F %T') 분리 실행 끝: $S rc=$?" >> "$L"
