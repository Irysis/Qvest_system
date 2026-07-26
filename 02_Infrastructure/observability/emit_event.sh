#!/usr/bin/env bash
# emit_event.sh — v7.0 Sprint 6 Non-blocking event emitter
#
# 모든 hook event 1 row append → qepm/observability/events.jsonl
#
# Codex revised #7 — Non-blocking obligation:
#   - ledger write 실패 시에도 hook 차단 안 함
#   - 항상 exit 0 (failure는 stderr만 log)
#   - 관측성은 guard 아님 — 기록 계층
#
# Usage:
#   bash emit_event.sh <event_type> <hook_name> <decision> [<wt_id>] [<agent_role>] [<latency_ms>] [<file_path>] [<context>]
#
# Plan: nifty-tickling-hinton.md Sprint 6 Step 1.

#==============================================================================
# ★현행 상태 (2026-07-26 실측 — 배선 전 반드시 읽을 것)
#
#   이 스크립트는 **어디에서도 호출되지 않는다**(전수 grep: 참조는 문서 4곳 + 자기 자신).
#   v7.0 Sprint 6 이 설계한 "모든 hook event 1 row append" 배관은 연결된 적이 없거나
#   어느 시점에 끊겼고, events.jsonl 에 남은 247바이트는 당시 스모크 픽스처다
#   (wt_timeline 이 ledger_status "STALE (49일 미갱신, 1행)" 으로 표면화).
#
#   ① 고장이었다 → 이 수리: bare `python3` 가 Windows Store 스텁에 걸려 compose fail,
#      trap 이 exit 0 으로 삼켜 append 0건 + 실패는 FAIL_LOG 에만 남았다(실측 확인).
#      배선했더라도 원장은 계속 비고 훅은 조용히 통과했을 것이다.
#      → QVEST_PY 정본 해석기 경유 (reference-python3-windows-stub-use-qvest-py).
#   ② 비용 실측 (30회 × append 실증):
#        현행 설계(python 으로 JSON 조립)      110 ms/회   ← 전체 배선 불가
#        bash printf + date 프로세스            19 ms/회
#        bash printf + 내장 %(...)T 타임스탬프    1 ms/회   ← 전체 배선 가능
#      병목은 OneDrive I/O 가 아니라 **python 시동**이다(.cache 24ms vs OneDrive 25ms).
#      타임스탬프 하나가 나머지 비용의 95%.
#   ③ 배선 여부·설계(python 제거 여부)는 **도훈 결정 대기**.
#      close_round: HARNESS-20260726_events_ledger_cost_map (next_probe ①)
#==============================================================================

# Always exit 0 (non-blocking)
trap 'exit 0' ERR

PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
LEDGER="$PROJ_DIR/qepm/observability/events.jsonl"
FAIL_LOG="/tmp/emit_event_fail.log"

# (2026-07-26) bare python3 = Windows Store 스텁 트랩 수리. 미가용 시 조용히 넘기지 않고
#   FAIL_LOG 에 사유를 남긴다(관측 계층이라 hook 은 차단하지 않음 — 원 설계 제약 유지).
QVEST_PY_BIN="${QVEST_PY:-}"
QVEST_PY_BIN="${QVEST_PY_BIN//\\//}"
[ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ] || \
  QVEST_PY_BIN="$PROJ_DIR/.venv_qvest_ml/Scripts/python.exe"
[ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || true)"

EVENT_TYPE="${1:-unknown}"
HOOK_NAME="${2:-unknown}"
DECISION="${3:-allow}"
WT_ID="${4:-}"
AGENT_ROLE="${5:-}"
LATENCY_MS="${6:-0}"
FILE_PATH="${7:-}"
CONTEXT="${8:-}"

#──────────────────────────────────────────────────────────────────────────────
# B2 재작성 (2026-07-26, 도훈 승인) — python 제거 + bash 내장 타임스탬프.
#   비용 실측(30회 × append 실증): python 조립 110ms → date 프로세스 19ms → 내장 1ms.
#   병목은 OneDrive I/O 가 아니라 python 시동(.cache 24ms vs OneDrive 25ms)이었고,
#   나머지의 95%가 `date` 프로세스 호출이었다. 스키마가 9필드 고정이라 printf 로 충분하다.
#   회당 1ms → 원 설계 의도("모든 hook event 1 row")를 선별 없이 전체 배선할 수 있다.
#   ★python 의존을 없앴으므로 Windows Store 스텁 트랩 자체가 소거된다(재발 불가).
#──────────────────────────────────────────────────────────────────────────────

# JSON 문자열 이스케이프 (bash-only) — 훅이 넘기는 file_path 에 백슬래시·인용부호가 섞인다.
_esc() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"; s="${s//$'\r'/}"; s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

# latency 는 숫자만 (비숫자 → 0). 구 python 판의 isdigit() 동치.
case "$LATENCY_MS" in (*[!0-9]*|"") LATENCY_MS=0 ;; esac

# 내장 타임스탬프. printf %(...)T 는 bash 4.2+ — 미지원 셸에서만 date 폴백.
if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2))); then
  printf -v TS '%(%Y-%m-%dT%H:%M:%S%z)T' -1
else
  TS="$(date -Iseconds 2>/dev/null || date)"
fi

# 선택 필드는 값이 있을 때만 실어 구 스키마(None 키 제거)와 동일한 모양을 유지한다.
OPT=""
[ -n "$WT_ID" ]      && OPT="$OPT,\"wt_id\":\"$(_esc "$WT_ID")\""
[ -n "$AGENT_ROLE" ] && OPT="$OPT,\"agent_role\":\"$(_esc "$AGENT_ROLE")\""
[ -n "$FILE_PATH" ]  && OPT="$OPT,\"file_path\":\"$(_esc "$FILE_PATH")\""
[ -n "$CONTEXT" ]    && OPT="$OPT,\"context\":\"$(_esc "$CONTEXT")\""

LINE="{\"timestamp\":\"$TS\",\"event_type\":\"$(_esc "$EVENT_TYPE")\",\"hook_name\":\"$(_esc "$HOOK_NAME")\",\"decision\":\"$(_esc "$DECISION")\",\"latency_ms\":$LATENCY_MS$OPT}"

# Append (non-blocking — 원 설계 제약: 관측성은 guard 아님)
mkdir -p "$(dirname "$LEDGER")" 2>/dev/null || true
(printf '%s\n' "$LINE" >> "$LEDGER") 2>>"$FAIL_LOG" || \
  echo "[$TS] emit_event append fail event=$EVENT_TYPE hook=$HOOK_NAME" >> "$FAIL_LOG"

exit 0
