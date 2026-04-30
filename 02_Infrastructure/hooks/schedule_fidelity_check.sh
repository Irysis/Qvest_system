#!/usr/bin/env bash
# schedule_fidelity_check.sh — v1.2 Schedule Fidelity Certifier (Positive Hook + 1 Hard Block)
#
# Charter §9/§10 Schedule Fidelity Mandate.
# 이벤트: PostToolUse[Write|Edit]
#
# Positive certifier 동작:
#   - optimization_package.json density ≥ 0.95 OR infeasibility_report 명시 → schedule_fidelity_certificate.json 발급
#
# Hard block 1건 (Charter §10 system integrity):
#   - run_all.R 또는 run_forge*.R에 'ProductionSchedule[N]m' fabrication label 존재 시 → decision:"block"
#
# Reference violation: STR_1715 Iter 31 — weights.csv 92 dates vs run_all.R 240 fabricated

set -euo pipefail
LOG="/tmp/schedule_fidelity_check.log"
FILE_PATH=""
trap 'echo "[$(date -Iseconds)] HOOK_ERR_TRAP file=${FILE_PATH:-unknown} line=${LINENO:-?}" >> "$LOG"; echo "{\"decision\":\"allow\",\"warning\":\"hook_internal_error_logged\"}"; exit 0' ERR

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then echo '{"decision":"allow"}'; exit 0; fi
if [[ -z "$FILE_PATH" ]]; then echo '{"decision":"allow"}'; exit 0; fi

CONTENT=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content","") or d.get("tool_input",{}).get("new_string",""))' 2>/dev/null || echo "")

WARN_MSGS=()

# Branch 1: optimization_package.json — schedule density 검증 + Positive Certifier
if [[ "$FILE_PATH" =~ optimization_package\.json$ ]]; then
  WT_DIR=$(dirname "$FILE_PATH")
  WEIGHTS_CSV="$WT_DIR/weights.csv"
  ALPHA_PKG="$WT_DIR/alpha_package.json"
  CERT_PATH="$WT_DIR/schedule_fidelity_certificate.json"

  if [[ -f "$WEIGHTS_CSV" && -f "$ALPHA_PKG" && ! -f "$CERT_PATH" ]]; then
    WEIGHTS_DATES=$(awk -F',' 'NR>1 {print $1}' "$WEIGHTS_CSV" 2>/dev/null | sort -u | wc -l)
    SIG_DATES=$(python3 -c "import json; d=json.load(open('$ALPHA_PKG')); diag=d.get('diagnostics',{}); print(diag.get('sig_dates_count', diag.get('n_sig_dates', d.get('alpha_summary',{}).get('n_sig_dates', d.get('n_sig_dates', 0)))))" 2>/dev/null || echo "0")

    if [[ $SIG_DATES -gt 0 && $WEIGHTS_DATES -gt 0 ]]; then
      RATIO=$(python3 -c "print(round($WEIGHTS_DATES / $SIG_DATES, 3))" 2>/dev/null || echo "0")
      RATIO_X100=$(python3 -c "print(int($WEIGHTS_DATES / $SIG_DATES * 100))" 2>/dev/null || echo "0")
      HAS_INFEASIBILITY=$(echo "$CONTENT" | grep -cE 'infeasibility_report|schedule_skip_justified|tophi_penalty_skip' || true)

      # Positive certifier (v1.2 Charter §10): density ≥ 0.95 OR infeasibility 명시 → 발급
      if [[ $RATIO_X100 -ge 95 ]] || [[ $HAS_INFEASIBILITY -gt 0 ]]; then
        python3 <<PYEOF 2>>/tmp/schedule_fidelity_certifier.log || true
import json, datetime
cert = {
    "issued": True,
    "wt_id": "$(basename $WT_DIR)",
    "weights_csv_unique_dates_count": $WEIGHTS_DATES,
    "alpha_sig_dates_count": $SIG_DATES,
    "schedule_density_ratio": $RATIO,
    "infeasibility_report_cited": bool($HAS_INFEASIBILITY > 0),
    "issued_at": datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
    "issued_by": "schedule_fidelity_check.sh v1.2",
    "charter_ref": "v1.2 §9/§10 Schedule Fidelity Certificate"
}
with open("$CERT_PATH", "w") as f:
    json.dump(cert, f, indent=2, ensure_ascii=False)
PYEOF
      else
        WARN_MSGS+=("SCHEDULE_DENSITY_FAIL (Charter §9): weights.csv $WEIGHTS_DATES dates / alpha sig_dates $SIG_DATES = ratio $RATIO. Threshold 0.95. infeasibility_report 명시 또는 weights.csv 재생성 필요. certificate 미발급.")
      fi
    fi
  fi
fi

# Branch 2: forge_package.json — sr_realized_share_based + measurement_basis_primary 검증
if [[ "$FILE_PATH" =~ forge_package(_phase[0-9]+)?\.json$ ]]; then
  if ! echo "$CONTENT" | grep -qE '"sr_realized_share_based"\s*:'; then
    WARN_MSGS+=("SR_REALIZED_FIELD_MISSING (Charter §9): forge_package.json missing sr_realized_share_based field. PG2 admission grade 부적격.")
  fi
  if ! echo "$CONTENT" | grep -qE '"measurement_basis_primary"\s*:\s*"forge_realized_share_based"'; then
    WARN_MSGS+=("MEASUREMENT_BASIS_MISSING (Charter §9): measurement_basis_primary != 'forge_realized_share_based'. 4 SR fields enum 강제.")
  fi
  # Divergence diagnosis 의무 (factor_engine claim 존재 시)
  if echo "$CONTENT" | grep -qE '(sr_factor_engine_continuous|factor_engine_claimed_sr|vs_factor_engine)' && ! echo "$CONTENT" | grep -qE '"diagnosis"\s*:\s*"(NEGLIGIBLE|MINOR_DRIFT|SIGNIFICANT_DRAG|FABRICATION_SUSPECTED)"'; then
    WARN_MSGS+=("DIVERGENCE_DIAGNOSIS_MISSING (Charter §9): factor_engine claim 존재 시 vs_factor_engine.diagnosis 4-enum 의무.")
  fi
fi

# Branch 3: run_all.R / run_forge*.R — Hard block (Charter §10 fabrication label) + warn
if [[ "$FILE_PATH" =~ run_all\.R$|run_forge.*\.R$ ]]; then
  HAS_PRODUCTION_LABEL=$(echo "$CONTENT" | grep -cE 'ProductionSchedule[0-9]+m' || true)

  # v1.2 Charter §10 Hard Block: ProductionSchedule[N]m 라벨 즉시 차단
  if [[ $HAS_PRODUCTION_LABEL -gt 0 ]]; then
    BLOCK_REASON="FABRICATION_LABEL_DETECTED (Charter §9/§10 hard block): run_all.R/run_forge*.R 내 'ProductionSchedule[N]m' fabrication label. STR_1715 Iter 31 violation 패턴 재발. method 라벨 변경 후 재시도."
    echo "{\"decision\":\"block\",\"reason\":\"$BLOCK_REASON\"}"
    exit 0
  fi

  # 그 외 fabrication suspected (4종 동시 매치) → warn
  HAS_ALPHA_READ=$(echo "$CONTENT" | grep -cE 'read_parquet\([^)]*alpha_scores' || true)
  HAS_TOP_N=$(echo "$CONTENT" | grep -cE '(setorder\([^)]*-?score|setorderv\([^)]*score|order\([^)]*-?score)' || true)
  HAS_HEAD_N=$(echo "$CONTENT" | grep -cE 'head\([^,]*,\s*[0-9]+\)|\.SD\[\s*1\s*:\s*[0-9N]' || true)
  HAS_SIG_REGEN=$(echo "$CONTENT" | grep -cE 'sig_dates[a-z_]*\s*<-\s*sort\(unique\([^)]*alpha_scores' || true)

  if [[ $HAS_ALPHA_READ -gt 0 && $HAS_TOP_N -gt 0 && $HAS_HEAD_N -gt 0 && $HAS_SIG_REGEN -gt 0 ]]; then
    WARN_MSGS+=("FORGE_FABRICATED_SCHEDULE_SUSPECTED (Charter §9): run_all.R reads alpha_scores + setorder(score) + head(N) + sig_dates 재생성 동시 매치. weights.csv as-is 사용 의무. STR_1715 Iter 31 패턴.")
  fi
fi

# Retry counter — 무한 warn 방지
if [[ ${#WARN_MSGS[@]} -gt 0 ]]; then
  COUNTER_FILE="/tmp/schedule_fidelity_warn_$(basename "$FILE_PATH").txt"
  COUNT=0
  [[ -f "$COUNTER_FILE" ]] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
  COUNT=$((COUNT + 1))
  echo "$COUNT" > "$COUNTER_FILE"

  if [[ $COUNT -ge 3 ]]; then
    ESCALATE_MSG="SCHEDULE_FIDELITY_RETRY_CAP (3+ warns) — escalate Q-Lead. file=$(basename "$FILE_PATH")"
    echo "{\"decision\":\"allow\",\"warning\":\"$ESCALATE_MSG | $(IFS='|'; echo "${WARN_MSGS[*]}")\"}"
    exit 0
  fi

  COMBINED=$(IFS=' || '; echo "${WARN_MSGS[*]}")
  echo "{\"decision\":\"allow\",\"warning\":\"$COMBINED\"}"
else
  echo '{"decision":"allow"}'
fi
