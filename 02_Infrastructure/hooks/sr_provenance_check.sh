#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
# sr_provenance_check.sh — v1.2 SR Provenance Certifier (Positive Hook + 1 Hard Block)
#
# Charter §8/§9/§10 Measurement Basis Disclosure + SoT for SR + Certification.
# 이벤트: PostToolUse[Write|Edit]
#
# Positive certifier 동작:
#   - forge_package.json에 4-field 모두 존재 (sr_realized_share_based / measurement_basis_primary='forge_realized_share_based' /
#     weights_csv_unique_dates_count / schedule_density_ratio) → sr_provenance_certificate.json 자동 발급
#
# Hard block 1건 (Charter §10 system integrity):
#   - hurdle_result.json 또는 forge_package.json에 'ProductionSchedule[N]m' fabrication label 존재 시 → decision:"block"
#
# Reference violation: STR_1715 Iter 31 — hurdle_result method "ProductionSchedule240m" 잔존 사고.

set -euo pipefail
LOG="/tmp/sr_provenance_check.log"
FILE_PATH=""
trap 'echo "[$(date -Iseconds)] HOOK_ERR_TRAP file=${FILE_PATH:-unknown} line=${LINENO:-?}" >> "$LOG"; echo "{}"; exit 0' ERR

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then echo '{}'; exit 0; fi
if [[ -z "$FILE_PATH" ]]; then echo '{}'; exit 0; fi

CONTENT=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content","") or d.get("tool_input",{}).get("new_string",""))' 2>/dev/null || echo "")

WARN_MSGS=()

# v1.2 Charter §10: HARD BLOCK 1건 — fabrication label (system integrity 위협)
# hurdle_result.json 또는 forge_package.json에 ProductionSchedule[N]m 패턴 매치 시 즉시 차단
if [[ "$FILE_PATH" =~ (hurdle_result\.json$|forge_package(_phase[0-9]+)?\.json$) ]]; then
  if echo "$CONTENT" | grep -qE '"method"\s*:\s*"[^"]*ProductionSchedule[0-9]+m'; then
    BLOCK_REASON="FABRICATION_LABEL_DETECTED (Charter §9/§10 hard block): method 필드에 'ProductionSchedule[N]m' fabrication label. STR_1715 Iter 31 violation 패턴 재발. 라벨 변경 후 재시도."
    echo "{\"decision\":\"block\",\"reason\":\"$BLOCK_REASON\"}"
    exit 0
  fi
fi

# Branch 1: forge_package.json — 4 SR fields enum 검증 + sr_provenance_certificate 발급
if [[ "$FILE_PATH" =~ forge_package(_phase[0-9]+)?\.json$ ]]; then
  if echo "$CONTENT" | grep -qE '"measurement_basis_primary"\s*:'; then
    if ! echo "$CONTENT" | grep -qE '"measurement_basis_primary"\s*:\s*"forge_realized_share_based"'; then
      WARN_MSGS+=("MEASUREMENT_BASIS_INVALID (Charter §9): measurement_basis_primary enum 강제 = 'forge_realized_share_based' only.")
    fi
  fi

  # Positive certifier (v7.0 Sprint 1: qvest_cert_eval router 위임)
  if [[ -f "$FILE_PATH" ]]; then
    WT_DIR=$(dirname "$FILE_PATH")
    CERT_PATH="$WT_DIR/sr_provenance_certificate.json"
    if [[ ! -f "$CERT_PATH" ]]; then
      PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
      "$QVEST_PY_BIN" "$PROJ_DIR/02_Infrastructure/hooks/qvest_cert_eval.py" \
        issue sr_provenance "$FILE_PATH" "$CERT_PATH" \
        "sr_provenance_check.sh v7.0 (router 위임)" >>/tmp/sr_provenance_certifier.log 2>&1 || true
    fi
  fi
fi

# Branch 2: hurdle_result.json — method_basis_label + production_grade 검증 (warn only)
if [[ "$FILE_PATH" =~ hurdle_result\.json$ ]]; then
  if ! echo "$CONTENT" | grep -qE '"method_basis_label"\s*:'; then
    WARN_MSGS+=("HURDLE_METHOD_BASIS_MISSING (Charter §9): hurdle_result.json missing method_basis_label field. enum: optimizer_walk_forward_simulation / factor_engine_continuous / forge_realized_share_based.")
  fi
  if ! echo "$CONTENT" | grep -qE '"production_grade"\s*:'; then
    WARN_MSGS+=("PRODUCTION_GRADE_MISSING (Charter §9): hurdle_result.json missing production_grade boolean.")
  fi
fi

# Branch 3: tg_*.R / qlead_*.R / *_tg.R — SR 인용 시 source label 의무
if [[ "$FILE_PATH" =~ (tg_[^/]+|qlead_[^/]+|[^/]+_tg)\.R$ ]]; then
  # SR 숫자 등장 (예: "SR 1.45", "Sharpe 0.61", "SR_combined: 1.4522")
  if echo "$CONTENT" | grep -qE '\b(SR|sharpe|Sharpe|SHARPE|SR_combined|SR_preLB|SR_full|SR_OOS|샤프)\b\s*[:=]?\s*[\(\-]?[0-9]+\.?[0-9]*'; then
    # 같은 파일 내 source label 인용 확인
    if ! echo "$CONTENT" | grep -qE '(forge_realized|factor_engine_meta|factor_engine_continuous|lockbox_daily|optimizer_simulation|measurement_basis|source_label|_provenance)'; then
      WARN_MSGS+=("SR_PROVENANCE_LABEL_MISSING (Charter §8): SR cited but no source_label (forge_realized|factor_engine_meta|lockbox_daily|optimizer_simulation). measurement_basis 인자 필수.")
    fi
  fi
fi

# Retry counter
if [[ ${#WARN_MSGS[@]} -gt 0 ]]; then
  COUNTER_FILE="/tmp/sr_provenance_warn_$(basename "$FILE_PATH").txt"
  COUNT=0
  [[ -f "$COUNTER_FILE" ]] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
  COUNT=$((COUNT + 1))
  echo "$COUNT" > "$COUNTER_FILE"

  if [[ $COUNT -ge 3 ]]; then
    ESCALATE_MSG="SR_PROVENANCE_RETRY_CAP (3+ warns) — escalate Q-Lead. file=$(basename "$FILE_PATH")"
    echo "{}"
    exit 0
  fi

  COMBINED=$(IFS=' || '; echo "${WARN_MSGS[*]}")
  echo "{}"
else
  echo '{}'
fi
