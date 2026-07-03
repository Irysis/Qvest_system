#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
# alpha_discovery_certifier.sh — v7.0 Sprint 1 router 위임 (single source)
#
# v6.4 (147 LoC inline Python) → v7.0 router 위임 (~50 LoC).
# Eligibility logic은 02_Infrastructure/hooks/qvest_cert_eval.py 단일 source.
# cert_rules.json (data) → qvest_cert_eval.py (apply) → 본 hook (trigger).
#
# Charter §10 Alpha Discovery Certification System.
# 이벤트: PostToolUse[Write|Edit] alpha_package.json
# 동작: eligibility 충족 시 sibling alpha_discovery_certificate.json 자동 발급.
#       미충족 시 NOT_ISSUED cert + non_issuance_reason 명시 (passive deny).

set -euo pipefail
LOG="/tmp/alpha_discovery_certifier.log"
FILE_PATH=""
trap 'echo "[$(date -Iseconds)] HOOK_ERR_TRAP file=${FILE_PATH:-unknown} line=${LINENO:-?}" >> "$LOG"; echo "{}"; exit 0' ERR

PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CERT_EVAL="$PROJ_DIR/02_Infrastructure/hooks/qvest_cert_eval.py"

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then echo '{}'; exit 0; fi
if [[ ! "$FILE_PATH" =~ alpha_package\.json$ ]]; then echo '{}'; exit 0; fi
if [[ ! -f "$FILE_PATH" ]]; then echo '{}'; exit 0; fi

WT_DIR=$(dirname "$FILE_PATH")
CERT_PATH="$WT_DIR/alpha_discovery_certificate.json"

# Self-trigger 방지
if [[ -f "$CERT_PATH" ]]; then
  echo '{}'
  exit 0
fi

# wt_type 분기 (sizing_only / hyperparameter_sweep는 cert 면제)
REQ_PATH="$WT_DIR/request.json"
WT_TYPE="discovery"
if [[ -f "$REQ_PATH" ]]; then
  WT_TYPE=$("$QVEST_PY_BIN" -c "import json; print(json.load(open('$REQ_PATH')).get('wt_type','discovery'))" 2>/dev/null || echo "discovery")
fi
if [[ "$WT_TYPE" == "sizing_only" || "$WT_TYPE" == "hyperparameter_sweep" ]]; then
  echo "[$(date -Iseconds)] $WT_TYPE WT — cert skip (Role Card)" >> "$LOG"
  echo '{}'
  exit 0
fi

# v7.0: qvest_cert_eval.py issue 위임
RESULT=$("$QVEST_PY_BIN" "$CERT_EVAL" issue alpha_discovery "$FILE_PATH" "$CERT_PATH" "alpha_discovery_certifier.sh v7.0" 2>>"$LOG" || echo '{"issued":false,"reason":"cert_eval_error"}')
ISSUED=$(printf '%s' "$RESULT" | "$QVEST_PY_BIN" -c 'import json,sys; print(str(json.load(sys.stdin).get("issued",False)).lower())' 2>/dev/null || echo "false")

echo "[$(date -Iseconds)] WT_DIR=$WT_DIR issued=$ISSUED" >> "$LOG"

if [[ "$ISSUED" == "true" ]]; then
  echo "{}"
else
  echo "{}"
fi
