#!/usr/bin/env bash
#==============================================================================
# arm_gen_read_guard.sh — arm 생성 세션의 **성과 열람 차단** (v10.2 2026-09-03)
#
# ★왜: 생성기의 핵심 안전 속성은 "성과를 보지 않는다" 다. 그래야 방출이 선언 축의
#   결정론적 함수가 되고, argmax 를 사후에 취해도 selection_type 이 정직하게 남는다
#   (generate_weight_variants.R 이 시그니처에서 ir/measured 를 빼는 것과 같은 규율).
#   그런데 `--add-dir` 는 워크스페이스를 넓힐 뿐 **읽기를 가두지 않는다**. Read 가 허용
#   목록에 있는 한 생성 세션은 원장을 그냥 열어 셀별 등급·Calmar 를 전부 볼 수 있다.
#   그러면 "구조적으로 불가" 라는 주장이 거짓이 된다 — 존재하지 않는 방어선을 세는 것이
#   이 저장소가 가장 자주 죽는 방식이다.
#
# 발화 조건: QVEST_ARM_GEN=1 일 때만. 평시에는 첫 줄에서 통과 — 소음 0.
# 검사: 08_Tests/hooks/test_arm_gen_read_guard.sh (위반 주입 + 평시 음성 대조)
#==============================================================================
set -uo pipefail

# ★평시 무발화 — 생성 세션이 아니면 아무것도 하지 않는다.
if [ "${QVEST_ARM_GEN:-0}" != "1" ]; then echo '{}'; exit 0; fi

LOG="/tmp/arm_gen_read_guard.log"
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || \
    QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
fi

# 측정 산출물 경로 — 등급·성과가 들어 있는 것들.
MEASURE_RE='reinforce_ledger_l[0-9]+\.json|authoritative_remeasure\.json|bt_result|rf_parallel/result_|overlay_ab_results|overlay_mechanism_map\.json|reinforce_auto_log\.jsonl|overlay_arm_ledger\.jsonl|essence_score|hurdle_result'

_deny() {
  echo "{\"decision\":\"block\",\"reason\":\"ARM_GEN_READ_BLOCKED: $1 — 생성기는 성과를 보지 않는다(측정 전 방출). 표적 칸과 함수 계약은 프롬프트에 이미 들어 있다.\"}"
  echo "[$(date -Iseconds)] BLOCK $1" >> "$LOG" 2>/dev/null || true
  exit 0
}

INPUT=$(cat)

# ★fail-closed — 생성 세션 안에서 판별 불능이면 막는다(평시엔 위에서 이미 빠져나갔다).
_fail_closed() {
  if printf '%s' "${INPUT:-}" | grep -qE "$MEASURE_RE"; then
    _deny "판별 불능 + 측정 경로 패턴 감지"
  fi
  echo '{}'; exit 0
}
trap '_fail_closed' ERR

PTH=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c \
  'import json,sys; d=json.load(sys.stdin); ti=d.get("tool_input",{}) or {}; print(ti.get("file_path") or ti.get("path") or "")' \
  2>/dev/null || echo "")

if [ -n "$PTH" ] && printf '%s' "$PTH" | grep -qE "$MEASURE_RE"; then
  _deny "$PTH"
fi

echo '{}'
exit 0
