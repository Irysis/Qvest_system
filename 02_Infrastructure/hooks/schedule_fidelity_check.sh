#!/usr/bin/env bash
# schedule_fidelity_check.sh — v6.3 Schedule Fidelity verifier (L2 soft gate)
#
# Charter §9 강제: weights.csv schedule density + run_all.R fabrication detection.
# 이벤트: PostToolUse[Write|Edit]
# 무한루프 회피: read-only, file_path regex 분기, retry counter
# Reference violation: STR_1715 Iter 31 — weights.csv 92 dates vs run_all.R 240 fabricated

set -euo pipefail
trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then echo '{"decision":"allow"}'; exit 0; fi
if [[ -z "$FILE_PATH" ]]; then echo '{"decision":"allow"}'; exit 0; fi

CONTENT=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content","") or d.get("tool_input",{}).get("new_string",""))' 2>/dev/null || echo "")

WARN_MSGS=()

# Branch 1: optimization_package.json — schedule density vs alpha sig_dates
if [[ "$FILE_PATH" =~ optimization_package\.json$ ]]; then
  WT_DIR=$(dirname "$FILE_PATH")
  WEIGHTS_CSV="$WT_DIR/weights.csv"
  ALPHA_PKG="$WT_DIR/alpha_package.json"

  if [[ -f "$WEIGHTS_CSV" && -f "$ALPHA_PKG" ]]; then
    WEIGHTS_DATES=$(awk -F',' 'NR>1 {print $1}' "$WEIGHTS_CSV" 2>/dev/null | sort -u | wc -l)
    SIG_DATES=$(python3 -c "import json; d=json.load(open('$ALPHA_PKG')); print(d.get('diagnostics',{}).get('sig_dates_count', d.get('alpha_summary',{}).get('n_sig_dates', 0)))" 2>/dev/null || echo "0")

    if [[ $SIG_DATES -gt 0 && $WEIGHTS_DATES -gt 0 ]]; then
      RATIO=$(python3 -c "print(round($WEIGHTS_DATES / $SIG_DATES, 3))" 2>/dev/null || echo "0")
      RATIO_X100=$(python3 -c "print(int($WEIGHTS_DATES / $SIG_DATES * 100))" 2>/dev/null || echo "0")
      if [[ $RATIO_X100 -lt 95 ]]; then
        # Charter §9 violation — 단, infeasibility_report 존재 시 면제
        if ! echo "$CONTENT" | grep -qE 'infeasibility_report|schedule_skip_justified|tophi_penalty_skip'; then
          WARN_MSGS+=("SCHEDULE_DENSITY_FAIL (Charter §9): weights.csv $WEIGHTS_DATES dates / alpha sig_dates $SIG_DATES = ratio $RATIO. Threshold 0.95. infeasibility_report 의무.")
        fi
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

# Branch 3: run_all.R — fabrication suspected pattern
if [[ "$FILE_PATH" =~ run_all\.R$|run_forge.*\.R$ ]]; then
  HAS_ALPHA_READ=$(echo "$CONTENT" | grep -cE 'read_parquet\([^)]*alpha_scores' || true)
  HAS_TOP_N=$(echo "$CONTENT" | grep -cE '(setorder\([^)]*-?score|setorderv\([^)]*score|order\([^)]*-?score)' || true)
  HAS_HEAD_N=$(echo "$CONTENT" | grep -cE 'head\([^,]*,\s*[0-9]+\)|\.SD\[\s*1\s*:\s*[0-9N]' || true)
  HAS_SIG_REGEN=$(echo "$CONTENT" | grep -cE 'sig_dates[a-z_]*\s*<-\s*sort\(unique\([^)]*alpha_scores' || true)
  HAS_PRODUCTION_LABEL=$(echo "$CONTENT" | grep -cE 'ProductionSchedule[0-9]+m|240\s*monthly.*production|production.*schedule.*[0-9]+m' || true)

  # 동시 매치 시 fabrication 의심 (정밀 정규식 — false positive 최소화)
  if [[ $HAS_ALPHA_READ -gt 0 && $HAS_TOP_N -gt 0 && $HAS_HEAD_N -gt 0 && $HAS_SIG_REGEN -gt 0 ]]; then
    WARN_MSGS+=("FORGE_FABRICATED_SCHEDULE_SUSPECTED (Charter §9): run_all.R reads alpha_scores + setorder(score) + head(N) + sig_dates 재생성 동시 매치. weights.csv as-is 사용 의무. STR_1715 Iter 31 패턴.")
  fi
  if [[ $HAS_PRODUCTION_LABEL -gt 0 ]]; then
    WARN_MSGS+=("FABRICATION_LABEL_DETECTED (Charter §9): run_all.R contains 'ProductionSchedule[N]m' label — Charter §9 금지. method 라벨 변경 필요.")
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
