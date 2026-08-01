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
# ── 구분자 정규화 (2026-08-01) — 역슬래시 루트가 R **소스코드 문자열**로 주입되면
#    "C:\Users\..." 의 \U 가 유니코드 이스케이프로 파싱돼 스크립트가 죽는다.
#    실측: QM_ROOT(User scope)가 역슬래시라 daily_refresh 의 setwd("$BASE") 6지점이
#      Error: '\U' used without hex digits in character string (<input>:1:13)
#    로 halt → run_r 는 체인을 계속하므로 **개별 스텝만 침묵 실패**한다(2026-08-01 실측
#    r8/r9/r11/r12/r14 = KTRI v3 · MSM · regime_daily_v2 · SJM · cache_freshness_audit).
#    ★ dir.exists 류 존재 검사는 역슬래시 루트도 통과시킨다 — 형식은 존재가 보증하지 않는다.
#    슬래시 형태는 R·bash(MSYS)·Python 전부 정상이므로 여기서 한 번만 정규화한다.
PROJECT="${PROJECT//\\//}"

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
