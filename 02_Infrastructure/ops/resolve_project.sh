#!/bin/bash
# resolve_project.sh — 디바이스/드라이브 독립적 프로젝트 경로 해석
# 우선순위: QM_ROOT → 자기 위치 역추론($ROOT/02_Infrastructure/ops/) → 후보 glob.
# 어느 드라이브/경로로 옮겨도 무수정 동작 (자기 위치 추론이 1차 안전망).
# Usage: source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"

PROJECT=""
# 1) 명시 override
if [ -n "$QM_ROOT" ] && [ -d "$QM_ROOT" ]; then
  PROJECT="$QM_ROOT"
fi
# 2) 자기 위치에서 역추론 (이 파일은 $ROOT/02_Infrastructure/ops/ 에 위치)
if [ -z "$PROJECT" ]; then
  _self="${BASH_SOURCE[0]:-$0}"
  _cand="$(cd "$(dirname "$_self")/../.." 2>/dev/null && pwd)"
  if [ -n "$_cand" ] && [ -d "$_cand/02_Infrastructure" ]; then
    PROJECT="$_cand"
  fi
fi
# 3) 후보 경로 glob (드라이브 무관)
if [ -z "$PROJECT" ]; then
  PROJECT=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/g/Ent/Quant_Module_Moltbot \
                  /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
fi
if [ -z "$PROJECT" ] || [ ! -d "$PROJECT" ]; then
  echo "[ERROR] Quant_Module_Moltbot 디렉토리를 찾을 수 없습니다 (QM_ROOT 환경변수를 설정하세요)" >&2
  return 1 2>/dev/null || exit 1
fi
# 스크립트별 변수명 호환
PROJECT_ROOT="$PROJECT"
BASE="$PROJECT"
