#!/bin/bash
# resolve_project.sh — 디바이스/드라이브 독립적 프로젝트 경로 해석
# 우선순위: QM_ROOT → 자기 위치 역추론($ROOT/02_Infrastructure/ops/) → 후보 glob.
# 어느 드라이브/경로로 옮겨도 무수정 동작 (자기 위치 추론이 1차 안전망).
# Usage: source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
#
# ★모든 tier 는 **marker 파일**로 정체성을 검사한다 (r-portability.md 금칙 ③).
#   `-d` 존재 검사만으로는 "존재하지만 그 프로젝트가 아닌" 디렉토리가 통과한다 —
#   Windows R 이 /mnt/c/... 를 C:/mnt/c/... 로 해석해 남긴 빈 잔재가 대표 사례다.
#   marker 미충족 후보는 **기각하고 다음 tier 로 흘린다**(조용히 수용 금지).
#   검사기: 08_Tests/hooks/test_resolve_project_marker.sh (위반 주입 테스트 포함)

# marker = 이 리포지토리에만 있는 파일. rule 본문(금칙 ③)과 동일 경로를 쓴다.
QVEST_ROOT_MARKER="02_Infrastructure/hooks/qvest_hook_router.py"

# 후보가 *이* 프로젝트 루트인지 판정. 성공 시 정규화된 경로를 stdout 으로 반환.
#   ★역슬래시(`C:\Users\...`)는 판정 **전에** 정규화한다 — 2026-08-01 실사고에서
#     User scope QM_ROOT 가 역슬래시라 R 소스문자열 주입 시 `\U` 로 파싱돼 죽었다.
#     형식이 틀려도 `-d` 는 통과하므로, 정규화를 검사 뒤로 미루면 의미가 없다.
_qvest_root_ok() {
  local c="${1:-}"
  [ -n "$c" ] || return 1
  c="${c//\\//}"
  [ -f "$c/$QVEST_ROOT_MARKER" ] || return 1
  printf '%s' "$c"
}

PROJECT=""
QVEST_ROOT_SOURCE=""    # 어느 tier 가 해석했는지 (진단용)

# 1) 명시 override (QM_ROOT)
if PROJECT="$(_qvest_root_ok "${QM_ROOT:-}")"; then
  QVEST_ROOT_SOURCE="QM_ROOT"
else
  PROJECT=""
  # 설정돼 있는데 기각된 경우만 경보 — 조용한 fall-through 는 이 계통의 재발 기전이다.
  if [ -n "${QM_ROOT:-}" ]; then
    echo "[WARN] QM_ROOT='${QM_ROOT}' 기각 — marker 부재($QVEST_ROOT_MARKER). 다음 tier 로 해석합니다." >&2
  fi
fi

# 2) 자기 위치에서 역추론 (이 파일은 $ROOT/02_Infrastructure/ops/ 에 위치)
if [ -z "$PROJECT" ]; then
  _self="${BASH_SOURCE[0]:-$0}"
  _cand="$(cd "$(dirname "$_self")/../.." 2>/dev/null && pwd)"
  if PROJECT="$(_qvest_root_ok "$_cand")"; then
    QVEST_ROOT_SOURCE="self"
  else
    PROJECT=""
  fi
  unset _self _cand
fi

# 3) 후보 경로 glob (드라이브 무관)
#    ★`ls -d ... | head -1` 금지 — 첫 *존재* 후보를 무조건 집어 marker 검사를 건너뛴다.
#      한 줄씩 읽어 marker 통과분 중 첫 항목을 쓴다. 파이프가 아니라 프로세스 치환인
#      이유: 파이프는 subshell 이라 PROJECT 대입이 소실된다.
if [ -z "$PROJECT" ]; then
  while IFS= read -r _g; do
    if PROJECT="$(_qvest_root_ok "$_g")"; then
      QVEST_ROOT_SOURCE="glob"
      break
    fi
    PROJECT=""
  done < <(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/g/Ent/Quant_Module_Moltbot \
                 /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null)
  unset _g
fi

if [ -z "$PROJECT" ]; then
  echo "[ERROR] Quant_Module_Moltbot 루트를 찾을 수 없습니다 — marker($QVEST_ROOT_MARKER) 를 가진 후보 0건." >&2
  echo "[ERROR]   QM_ROOT 환경변수를 marker 가 있는 루트로 설정하세요 (현재: '${QM_ROOT:-미설정}')" >&2
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
#    (_qvest_root_ok 가 이미 정규화해 반환하므로 현재는 방어적 no-op — 경로 추가 시 안전망)
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
