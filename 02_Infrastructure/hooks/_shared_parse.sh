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
#──────────────────────────────────────────────────────────────────────────────
# qvest_emit_event — 인라인 이벤트 원장 append (2026-07-26, 도훈 승인)
#
# 왜 여기인가: v7.0 Sprint 6 의 emit_event.sh 는 **외부 스크립트**였고, 이 머신에서
#   `bash emit_event.sh` 1회 = 230ms(실측) — 그중 52ms 가 bash 프로세스 시동, 나머지는
#   본문의 `$( )` 서브셸이다. 훅마다 이걸 부르면 세션에 수 초가 붙는다.
#   반면 이 파일은 **훅 16종이 이미 source** 하므로 함수 호출은 추가 프로세스 0 =
#   인라인 append 실측 1.4ms. 그래서 원장 배관을 여기에 둔다.
#   (emit_event.sh 는 수동 CLI·외부 호출용으로 유지 — 같은 스키마)
#
# 설계 제약(원 설계 유지): 관측성은 guard 아님 — 실패해도 훅을 차단하지 않는다.
#   모든 실패는 조용히 삼키지 않고 FAIL_LOG 에 남긴다(이 저장소의 fail-open 금지 규율).
#
# 성능 규율: `$( )` 서브셸을 쓰지 않는다. 이스케이프도 파라미터 확장으로만 처리한다.
#   (구 emit_event.sh 가 `$(_esc ...)` 4~8회로 179ms 를 태웠다)
#
# Usage: qvest_emit_event <event_type> <hook_name> <decision> [wt_id] [agent_role] [latency_ms] [file_path] [context]
#──────────────────────────────────────────────────────────────────────────────
qvest_emit_event() {
  # 비활성 스위치 — 무인 배치·성능 실측 시 끌 수 있게
  [ "${QVEST_EVENT_LEDGER:-1}" = "0" ] && return 0

  local _root="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-}}"
  [ -n "$_root" ] || return 0
  local _led="$_root/qepm/observability/events.jsonl"
  [ -d "$_root/qepm/observability" ] || return 0   # 디렉토리 없으면 조용히 skip(신규 클론)

  local _et="${1:-unknown}" _hn="${2:-unknown}" _dc="${3:-allow}"
  local _wt="${4:-}" _ar="${5:-}" _lm="${6:-0}" _fp="${7:-}" _cx="${8:-}"
  case "$_lm" in (*[!0-9]*|"") _lm=0 ;; esac

  # JSON 이스케이프 (서브셸 없이 파라미터 확장만)
  local _e
  # ★JSON 이스케이프 순서 고정: 백슬래시를 **먼저** 두 배로, 그 다음 인용부호.
  #   역순이면 인용부호용으로 넣은 백슬래시까지 두 배가 된다.
  #   (2026-07-26 실측 사고: 블록 이동 중 이 라인의 이스케이프가 한 단계 붕괴해
  #    'C:\p' 가 그대로 나가 **무효 JSON** 이 100행 적재됐다 — 원장 정리 후 재작성)
  _esc_inline() {
    _e="$1"
    _e="${_e//\\/\\\\}"
    _e="${_e//\"/\\\"}"
    _e="${_e//$'\t'/\\t}"
    _e="${_e//$'\r'/}"
    _e="${_e//$'\n'/\\n}"
  }

  local _ts
  if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2))); then
    printf -v _ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1
  else
    _ts="$(date -Iseconds 2>/dev/null)"
  fi

  local _opt=""
  if [ -n "$_wt" ]; then _esc_inline "$_wt"; _opt="$_opt,\"wt_id\":\"$_e\""; fi
  if [ -n "$_ar" ]; then _esc_inline "$_ar"; _opt="$_opt,\"agent_role\":\"$_e\""; fi
  if [ -n "$_fp" ]; then _esc_inline "$_fp"; _opt="$_opt,\"file_path\":\"$_e\""; fi
  if [ -n "$_cx" ]; then _esc_inline "$_cx"; _opt="$_opt,\"context\":\"$_e\""; fi

  local _t _h _d
  _esc_inline "$_et"; _t="$_e"
  _esc_inline "$_hn"; _h="$_e"
  _esc_inline "$_dc"; _d="$_e"

  printf '{"timestamp":"%s","event_type":"%s","hook_name":"%s","decision":"%s","latency_ms":%s%s}\n' \
    "$_ts" "$_t" "$_h" "$_d" "$_lm" "$_opt" >> "$_led" 2>/dev/null \
    || printf '[%s] qvest_emit_event append fail hook=%s\n' "$_ts" "$_hn" \
         >> "${QVEST_EMIT_FAIL_LOG:-/tmp/emit_event_fail.log}" 2>/dev/null
  return 0
}

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

