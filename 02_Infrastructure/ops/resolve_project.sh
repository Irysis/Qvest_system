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

# ── python3 shim (2026-07-26) — bare `python3` 가 Windows Store 스텁으로 해석되는 함정 차단.
#    스텁은 "Python " 한 줄 찍고 종료한다 → 명령치환이 빈 문자열을 반환 →
#    호출부의 ${VAR:-0} / 빈 판정이 이를 삼켜 **정상처럼 위장**한다.
#    실사고: alpha_search_queue pending 이 참값 3 인데 0 으로 나와 큐가 조용히 skip.
#    ★존재(command -v)로 판별 금지 — 스텁도 존재한다. 반드시 실행(-c 'import sys')으로 확인.
#    ★resolve 는 함수 정의 *전에* 1회 수행한다. 정의 후엔 command -v python3 가 함수 자신을
#      반환해 무한 재귀가 된다.
if [ -z "${QVEST_PY_SHIM:-}" ]; then
  _qpy=""
  for _c in "${QVEST_PY:-}" \
            "$PROJECT/.venv_qvest_ml/Scripts/python.exe" \
            "/c/Users/99922/AppData/Local/Programs/Python/Python312/python.exe" \
            "$(command -v python3 2>/dev/null)" \
            "$(command -v python 2>/dev/null)"; do
    [ -n "$_c" ] || continue
    "$_c" -c 'import sys' >/dev/null 2>&1 && { _qpy="$_c"; break; }
  done
  if [ -n "$_qpy" ]; then
    QVEST_PY_RESOLVED="$_qpy"; export QVEST_PY_RESOLVED
    python3() { "$QVEST_PY_RESOLVED" "$@"; }
    QVEST_PY_SHIM=1
  fi
  unset _qpy _c
fi
