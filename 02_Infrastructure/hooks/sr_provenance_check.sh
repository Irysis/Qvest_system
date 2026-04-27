#!/usr/bin/env bash
# sr_provenance_check.sh — v6.3 SR Provenance Label verifier (L2 soft gate)
#
# Charter §8 Measurement Basis Disclosure Mandate 강제.
# 이벤트: PostToolUse[Write|Edit]
# 무한루프 회피: read-only, file_path regex 분기, retry counter
# Reference violation: STR_1715 Iter 31 — hurdle_result method "ProductionSchedule240m" + tg_*.R label 누락

set -euo pipefail
trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then echo '{"decision":"allow"}'; exit 0; fi
if [[ -z "$FILE_PATH" ]]; then echo '{"decision":"allow"}'; exit 0; fi

CONTENT=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content","") or d.get("tool_input",{}).get("new_string",""))' 2>/dev/null || echo "")

WARN_MSGS=()

# Branch 1: forge_package.json — 4 SR fields enum 검증
if [[ "$FILE_PATH" =~ forge_package(_phase[0-9]+)?\.json$ ]]; then
  if echo "$CONTENT" | grep -qE '"measurement_basis_primary"\s*:'; then
    if ! echo "$CONTENT" | grep -qE '"measurement_basis_primary"\s*:\s*"forge_realized_share_based"'; then
      WARN_MSGS+=("MEASUREMENT_BASIS_INVALID (Charter §9): measurement_basis_primary enum 강제 = 'forge_realized_share_based' only.")
    fi
  fi
fi

# Branch 2: hurdle_result.json — method_basis_label + ProductionSchedule pattern
if [[ "$FILE_PATH" =~ hurdle_result\.json$ ]]; then
  if ! echo "$CONTENT" | grep -qE '"method_basis_label"\s*:'; then
    WARN_MSGS+=("HURDLE_METHOD_BASIS_MISSING (Charter §9): hurdle_result.json missing method_basis_label field. enum: optimizer_walk_forward_simulation / factor_engine_continuous / forge_realized_share_based.")
  fi
  if ! echo "$CONTENT" | grep -qE '"production_grade"\s*:'; then
    WARN_MSGS+=("PRODUCTION_GRADE_MISSING (Charter §9): hurdle_result.json missing production_grade boolean.")
  fi
  # Fabrication label detection
  if echo "$CONTENT" | grep -qE '"method"\s*:\s*"[^"]*ProductionSchedule[0-9]+m'; then
    WARN_MSGS+=("FABRICATION_LABEL_FOUND (Charter §9): method contains 'ProductionSchedule[N]m' — fabrication label 금지. STR_1715 Iter 31 violation 패턴.")
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
    echo "{\"decision\":\"allow\",\"warning\":\"$ESCALATE_MSG | $(IFS='|'; echo "${WARN_MSGS[*]}")\"}"
    exit 0
  fi

  COMBINED=$(IFS=' || '; echo "${WARN_MSGS[*]}")
  echo "{\"decision\":\"allow\",\"warning\":\"$COMBINED\"}"
else
  echo '{"decision":"allow"}'
fi
