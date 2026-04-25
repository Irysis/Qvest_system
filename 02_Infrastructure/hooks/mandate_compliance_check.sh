#!/usr/bin/env bash
# mandate_compliance_check.sh — v6.2 unified mandate verifier (L2 soft gate)
#
# 통합: oos_chart_mandate_check + judge_lockbox_audit_check + optimizer_deploy_extension_check
#       + forge_baseline_fairness_check + scenario_rule_check (5 → 1)
#
# 이벤트: PostToolUse[Write]
# 목적: agent definition mandate가 실제 산출물에 반영됐는지 통합 검증
# 무한루프 회피: read-only (file write 없음), file_path regex 분기 — 자기 자신 trigger 안 함
# Retry counter: /tmp/mandate_warn_count_{file_basename}.txt — 3회+ warn 시 escalate

set -euo pipefail
trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then echo '{"decision":"allow"}'; exit 0; fi
if [[ -z "$FILE_PATH" ]]; then echo '{"decision":"allow"}'; exit 0; fi

CONTENT=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content","") or d.get("tool_input",{}).get("new_string",""))' 2>/dev/null || echo "")

WARN_MSGS=()

# Branch 1: optimization_package — deploy_cutoff field 명시
if [[ "$FILE_PATH" =~ optimization_package\.json$ ]]; then
  if ! echo "$CONTENT" | grep -qE 'deploy_cutoff|deploy_schedule|deploy_end|frozen_extension|deploy_open_ended'; then
    WARN_MSGS+=("DEPLOY_CUTOFF_MISSING (Tier3 Mandate v6.2): optimization_package.json missing deploy_cutoff field. Train cutoff != deploy cutoff.")
  fi
fi

# Branch 2: forge_package — same-period baseline + OOS chart references
if [[ "$FILE_PATH" =~ forge_package(_phase4)?\.json$ ]]; then
  if echo "$CONTENT" | grep -qE 'mega05_comparison|baseline.*comparison'; then
    if ! echo "$CONTENT" | grep -qE '(same_period|same_cost|same_dsr_penalty|baseline_recomputed|fair_comparison)'; then
      WARN_MSGS+=("BASELINE_FAIRNESS_MISSING (Tier3 v6.2): baseline comparison missing same-period/cost/DSR-penalty evidence.")
    fi
  fi
fi

# Branch 3: judge_verdict — Lockbox audit reference
if [[ "$FILE_PATH" =~ judge_verdict\.json$ ]]; then
  if ! echo "$CONTENT" | grep -qE 'lockbox.*(measured|extension|audit|nav|frozen|buy_hold|oos_period)'; then
    WARN_MSGS+=("LOCKBOX_AUDIT_MISSING (Tier3 v6.2): judge_verdict.json should reference lockbox period measurement (NAV/extension/audit). Judge core mandate.")
  elif echo "$CONTENT" | grep -qE 'lockbox.*(unavailable|N/A|not_available|skip)' && ! echo "$CONTENT" | grep -qE '(forge_extension_requested|frozen_weights_proxy|baseline_same_period_recomputed)'; then
    WARN_MSGS+=("LOCKBOX_DUTY_AVOIDANCE (Tier3 v6.2): 'unavailable' marked but no extension/proxy/recompute requested. Judge mandate violation.")
  fi
fi

# Branch 4: governor_admission — scenario_identified + rule alignment
if [[ "$FILE_PATH" =~ governor_admission\.json$ ]]; then
  if ! echo "$CONTENT" | grep -qE 'scenario_identified|scenario_type|admission_scenario'; then
    WARN_MSGS+=("SCENARIO_NOT_IDENTIFIED (Tier3 v6.2): governor_admission.json missing scenario_identified field.")
  elif echo "$CONTENT" | grep -qE 'replacement' && echo "$CONTENT" | grep -qE 'tdc.*0\.30|sequential_admission_tdc|tdc_threshold_0\.30'; then
    WARN_MSGS+=("SCENARIO_RULE_MISMATCH (Tier3 v6.2): replacement scenario BUT Sequential Admission TDC 0.30 applied. Iter 5 misapplication pattern.")
  fi
fi

# Branch 5: forge_package — OOS chart 누락
if [[ "$FILE_PATH" =~ forge_package(_phase4)?\.json$ ]]; then
  WT_DIR=$(dirname "$FILE_PATH")
  STR_DIR_GLOB="$WT_DIR/../../../04_Research/strategies/STR_*WT*/output"
  for f in equity_curve.png annual_returns.png; do
    found=0
    for d in $STR_DIR_GLOB; do
      [[ -f "$d/$f" ]] && found=1 && break
    done
    if [[ $found -eq 0 ]]; then
      WARN_MSGS+=("OOS_CHART_MISSING (Tier3 v6.2 Forge): $f not found in STR output dir.")
    fi
  done
fi

# Retry counter — 무한 warn 방지 (challenge_loop_limiter pattern)
if [[ ${#WARN_MSGS[@]} -gt 0 ]]; then
  COUNTER_FILE="/tmp/mandate_warn_count_$(basename "$FILE_PATH").txt"
  COUNT=0
  [[ -f "$COUNTER_FILE" ]] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
  COUNT=$((COUNT + 1))
  echo "$COUNT" > "$COUNTER_FILE"

  if [[ $COUNT -ge 3 ]]; then
    ESCALATE_MSG="MANDATE_RETRY_CAP (3+ warns on same file) — escalate to Q-Lead. file=$(basename "$FILE_PATH")"
    echo "{\"decision\":\"allow\",\"warning\":\"$ESCALATE_MSG | $(IFS='|'; echo "${WARN_MSGS[*]}")\"}"
    exit 0
  fi

  COMBINED=$(IFS=' || '; echo "${WARN_MSGS[*]}")
  echo "{\"decision\":\"allow\",\"warning\":\"$COMBINED\"}"
else
  echo '{"decision":"allow"}'
fi
