#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
# legacy_write_block.sh — v7.0 Sprint 5 Read-only enforcement for legacy assets
#
# 이벤트: PreToolUse[Write|Edit]
# 목적: _archive_v55/ + legacy/ + _archive_4_6/ 디렉토리 수정 시도 차단.
#
# 단순 hook (false positive risk 낮음 — directory 명시 matcher).
# Plan: nifty-tickling-hinton.md Sprint 5 Step 3.

set -euo pipefail
LOG="/tmp/legacy_write_block.log"

# (v8.2.1 2026-07-03 감사 HOOK-P2-1/MC-07, 도훈 confirm) 게이트급 fail-closed:
#   내부 오류(ERR)·stdin 파싱 판별불능 시 무조건 '{}' allow 대신, payload에
#   legacy read-only 패턴(_archive_v55/ · legacy/v55/ · _archive_4_6/)이 잡히면 block.
#   정상 경로 로직은 불변.
_gate_fail_closed() {
  local hay="${FILE_PATH:-}"
  [ -n "$hay" ] || hay="${INPUT:-}"
  if printf '%s' "$hay" | grep -qE '/_archive_v55/|/legacy/v55/|/_archive_4_6/'; then
    echo '{"decision":"block","reason":"LEGACY_WRITE_BLOCKED (fail-closed): hook 내부 오류/판별불능 — legacy read-only 경로 패턴 감지, 검증 불가 시 차단 (v7.0 Hardening 격리 정책)"}'
    echo "[$(date -Iseconds)] HOOK_ERR_TRAP fail-closed BLOCK (legacy pattern in payload)" >> "$LOG" 2>/dev/null || true
  else
    echo '{}'
    echo "[$(date -Iseconds)] HOOK_ERR_TRAP allow (no legacy pattern)" >> "$LOG" 2>/dev/null || true
  fi
  exit 0
}
trap '_gate_fail_closed' ERR

INPUT=$(cat)

# Legacy directory matchers — (WP4 2026-10-20) 정의를 빠른 길 앞으로 옮겼다: 빠른 길이 이 배열 하나에서 판정을 파생한다
#   (패턴을 더하면 빠른 길도 함께 넓어진다). ★아래 _gate_fail_closed 의 정규식 리터럴도 같은 패턴이어야 한다(구판부터의 짝).
LEGACY_PATTERNS=(
  "/_archive_v55/"
  "/legacy/v55/"
  "/_archive_4_6/"
)

# ── 빠른 길 (WP4 2026-10-20 · 훅 지연 — 판정 불변) ─────────────────────────────────
# 증명: 차단은 FILE_PATH(해독값)가 LEGACY_PATTERNS 의 한 패턴을 담거나, fail-closed hay(FILE_PATH, 비면 원문 INPUT)가
#   같은 패턴(정규식 리터럴)을 담을 때뿐이다. 패턴을 담으면 그 패턴의 마디('/' 사이 낱말 — 영숫자·_)도 모두 담는다.
#   JSON 해독은 이스케이프를 한 글자로 바꿀 뿐 글자를 지우지 않고, 영숫자·_ 를 만드는 이스케이프는 \uXXXX 뿐이다(\/ 는
#   '/' 만 만든다) → 원문에 '\u' 가 없고 어느 패턴의 마디도 다 갖추지 못하면 어떤 파싱 결과로도 차단될 수 없으며,
#   원래 경로의 출력은 '{}' 다. 객체 모양('{…}')이 아니거나 날 제어문자(엄격 JSON 파서가 거부 — JSON.stringify 는
#   내지 않는다)가 든 입력은 원래 경로로 보낸다 — 그 경로가 파서 실패 때 남기는 'HOOK_ERR_TRAP allow' 진단 로그 줄까지
#   그대로 두기 위해서다. (남는 차이: 그 밖의 문법 오류 JSON 에서 그 진단 줄 1개 — 판정 무관 · 읽는 곳 0건 · 운영 로그 실측 0건.)
# 끄기: QVEST_HOOK_FASTPATH=0 (검사 08_Tests/hooks/test_hook_fastpath_equivalence.sh)
_lwb_may_match() {  # 원문이 어느 패턴의 마디를 모두 담으면 0(→ 원래 경로) · 순수 bash
  local p s seg all
  for p in "${LEGACY_PATTERNS[@]}"; do
    all=1; s="$p"
    while [ -n "$s" ]; do
      seg="${s%%/*}"; s="${s#"$seg"}"; s="${s#/}"
      [ -z "$seg" ] && continue
      case "$INPUT" in *"$seg"*) : ;; *) all=0; break ;; esac
    done
    [ "$all" = 1 ] && return 0
  done
  return 1
}
if [ "${QVEST_HOOK_FASTPATH:-1}" != "0" ]; then
  case "$INPUT" in
    *'\u'*|*[[:cntrl:]]*) : ;;
    '{'*'}') _lwb_may_match || { echo '{}'; exit 0; } ;;
  esac
fi

TOOL=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

# stdin 파싱 판별불능(TOOL·FILE_PATH 동시 공백 = python 파서 실패 —
# PreToolUse[Write|Edit]는 tool_name 상시 존재) → fail-closed 판정
if [[ -z "$TOOL" && -z "$FILE_PATH" ]]; then
  _gate_fail_closed
fi

if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then
  echo '{}'
  exit 0
fi

# Legacy directory matchers = 위(빠른 길 앞) LEGACY_PATTERNS 정의 하나. (WP4 2026-10-20 이동)
for pattern in "${LEGACY_PATTERNS[@]}"; do
  if [[ "$FILE_PATH" == *"$pattern"* ]]; then
    REASON="LEGACY_WRITE_BLOCKED (v7.0 Sprint 5): $pattern is read-only. v7.0 Hardening 격리 정책. legacy 자산 수정 금지. 수정 필요 시 active path로 신규 작성."
    echo "[$(date -Iseconds)] BLOCKED $TOOL on $FILE_PATH (pattern: $pattern)" >> "$LOG"
    echo "{\"decision\":\"block\",\"reason\":\"$REASON\"}"
    exit 0
  fi
done

echo '{}'
