#!/usr/bin/env bash
#==============================================================================
# _shared_parse.sh — stdin JSON 1회 파싱 → env export
#
# 사용법: 다른 hook에서 source. stdin을 1회만 $QVEST_PY_BIN 으로 파싱하여
# TOOL_NAME / FILE_PATH / COMMAND / CONTENT / AGENT_NAME / AGENT_PROMPT 환경변수 export.
# 추가로 QVEST_PY_BIN(실행 가능한 python 절대경로)도 export — bare python3 금지.
#
# 절감 효과: 각 hook이 stdin을 3-4회 python으로 파싱하던 것을 1회로 통합.
#
# 전제: INPUT 변수에 stdin 내용이 이미 있거나 없어야 함.
# 사용 예:
#   #!/bin/bash
#   INPUT=$(cat)
#   source "$(dirname "$0")/_shared_parse.sh"
#   # 이제 $TOOL_NAME, $FILE_PATH 등 사용 가능
#==============================================================================

# (v8.2.1 2026-07-04 감사 A7d) 게이트급 호출자 옵트아웃: 호출자가 source 전에
# QVEST_PARSE_TRAP=caller 를 선지정하면 아래 내부 fail-open ERR trap('{}' allow)
# 설치를 생략 — 호출자가 선장전한 자기 fail-closed trap이 본 파일 실행 구간
# (파싱 python 호출 등)의 오류까지 커버한다. 미지정(기본)은 종전과 동일
# (advisory 훅 수십 개 영향 0).
if [ "${QVEST_PARSE_TRAP:-}" != "caller" ]; then
  trap 'echo "{}"; exit 0' ERR
fi

#──────────────────────────────────────────────────────────────────────────────
# (v8.2.1 2026-07-03 HOOK-P0-1) Python 해석 — PATH의 python3/python이 Windows Store
# 스텁(WindowsApps alias, exit≠0 + 무의미 출력)이라 하드블록 훅 전체가 조용히
# fail-open 되던 결함 수리. 우선순위:
#   ① $QVEST_PY (User scope 영구 env, CLAUDE.md Key Paths)
#   ② 프로젝트 venv .venv_qvest_ml/Scripts/python.exe
#   ③ command -v python.exe (최후 fallback — 스텁일 수 있음)
# 결과는 QVEST_PY_BIN으로 export. 다른 훅은 "$QVEST_PY_BIN" 으로 호출할 것.
# 해석만 필요한 훅(자체 stdin 파싱 유지)은:
#   QVEST_PARSE_RESOLVE_ONLY=1; source _shared_parse.sh; unset QVEST_PARSE_RESOLVE_ONLY
#──────────────────────────────────────────────────────────────────────────────
if [ -z "${QVEST_PY_BIN:-}" ]; then
  _QP="${QVEST_PY:-}"
  _QP="${_QP//\\//}"  # 백슬래시 → 슬래시 (Git Bash 실행 호환)
  if [ -n "$_QP" ] && [ -x "$_QP" ]; then
    QVEST_PY_BIN="$_QP"
  else
    QVEST_PY_BIN=""
    for _CAND in \
      /c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe \
      /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe \
      "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"; do
      if [ -x "$_CAND" ]; then QVEST_PY_BIN="$_CAND"; break; fi
    done
    if [ -z "$QVEST_PY_BIN" ]; then
      QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
    fi
    unset _CAND
  fi
  unset _QP
fi
export QVEST_PY_BIN

# 해석-only 모드: stdin 파싱 없이 종료 (source 전용)
if [ "${QVEST_PARSE_RESOLVE_ONLY:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

# INPUT이 설정되지 않았으면 stdin을 읽음
if [ -z "${INPUT+x}" ]; then
  INPUT=$(cat)
fi

# (v8.1.2 2026-06-11) bytes 경유 UTF-8 명시 디코딩 + stdout UTF-8 고정 — locale(cp949) 의존이던
# 파싱을 결정론화. (현 런타임은 surrogateescape 왕복으로 우연히 무사했음 — env 운에 의존 금지)
PARSED=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c "
import sys, json
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
try:
    d = json.loads(sys.stdin.buffer.read().decode('utf-8', 'replace'))
    ti = d.get('tool_input', {}) or {}
    # Lines 1-6: tool_name, file_path, command, content_preview, agent_name, agent_prompt_preview
    print(d.get('tool_name', ''))
    print(ti.get('file_path', ''))
    print(ti.get('command', ''))
    # content는 Write 도구의 경우 전체, Edit은 new_string
    content = ti.get('content') or ti.get('new_string') or ''
    # 1500자 preview (패턴 매칭 용도만, full은 불필요)
    print(content[:1500])
    # Agent tool용
    print(ti.get('subagent_type') or ti.get('name') or '')
    prompt = ti.get('prompt') or ''
    print(prompt[:1500])
except Exception:
    for _ in range(6):
        print('')
" 2>/dev/null || printf '\n\n\n\n\n\n')

export TOOL_NAME=$(printf '%s\n' "$PARSED" | sed -n '1p')
export FILE_PATH=$(printf '%s\n' "$PARSED" | sed -n '2p')
export COMMAND=$(printf '%s\n' "$PARSED" | sed -n '3p')
export CONTENT=$(printf '%s\n' "$PARSED" | sed -n '4p')
export AGENT_NAME=$(printf '%s\n' "$PARSED" | sed -n '5p')
export AGENT_PROMPT=$(printf '%s\n' "$PARSED" | sed -n '6p')
export AGENT_NAME_LC=$(printf '%s' "$AGENT_NAME" | tr 'A-Z' 'a-z')
