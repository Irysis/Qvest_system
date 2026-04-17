#!/bin/bash
# resolve_project.sh — 디바이스 독립적 프로젝트 경로 해석
# 노트북(User) / PC(99922) 어디서든 동작.
# Usage: source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"

PROJECT=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
if [ -z "$PROJECT" ]; then
  echo "[ERROR] Quant_Module_Moltbot 디렉토리를 찾을 수 없습니다" >&2
  return 1 2>/dev/null || exit 1
fi
# 스크립트별 변수명 호환
PROJECT_ROOT="$PROJECT"
BASE="$PROJECT"
