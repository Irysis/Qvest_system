#!/usr/bin/env bash
# ★v10 (2026-09-03) 주의 — 이 파일은 v9 등록 해제분(사료)이고 judge_verdict 에 lockbox 측정 참조가 없으면 LOCKBOX_AUDIT_MISSING 경고 가 남아 있다.
#   전부 v10 폐지 개념(lockbox·governor·book_state·cert)이므로 **재등록 금지** — 되살리려면 그 분기를 먼저
#   제거하고 양성/음성 대조를 다시 만들 것. 파일 자체는 08_Tests·hook_e2e_battery 가 경로로 실행한다(이동 금지).
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
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
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
# (2026-07-24 Fable5 하네스 감사) raw-INPUT 조기-exit — 6분기 대상 파일 무관 W/E에서 python 3스폰 제거 (superset 필터)
if ! printf '%s' "$INPUT" | grep -qE 'optimization_package\.json|forge_package|judge_verdict\.json|governor_admission\.json|request\.json'; then echo '{}'; exit 0; fi
TOOL=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then echo '{}'; exit 0; fi
if [[ -z "$FILE_PATH" ]]; then echo '{}'; exit 0; fi

CONTENT=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content","") or d.get("tool_input",{}).get("new_string",""))' 2>/dev/null || echo "")

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

# Branch 6: request.json — universe v2 cost mandate (L-227, 2026-04-26)
# v2 universe 사용 시 cost_model_version이 universe별 권고 bps와 일치하는지 검증
if [[ "$FILE_PATH" =~ /worktask/WT[^/]+/request\.json$ ]]; then
  if echo "$CONTENT" | grep -qE '"label"\s*:\s*"KR_TOP500_FREEFLOAT"'; then
    if ! echo "$CONTENT" | grep -qE 'cost_model_version.*(20bps|25bps)'; then
      WARN_MSGS+=("UNIVERSE_V2_COST_MISMATCH (L-227): KR_TOP500_FREEFLOAT requires cost_model_version >= 20bps (mid-cap impact buffer).")
    fi
  fi
  if echo "$CONTENT" | grep -qE '"label"\s*:\s*"KR_TOP500_LIQ1E8"'; then
    if ! echo "$CONTENT" | grep -qE 'cost_model_version.*25bps'; then
      WARN_MSGS+=("UNIVERSE_V2_COST_MISMATCH (L-227): KR_TOP500_LIQ1E8 requires cost_model_version 25bps (1e8 floor concession, mandate 2e8 위반).")
    fi
  fi
fi

# Retry counter — 무한 warn 방지 (challenge_loop_limiter pattern)
if [[ ${#WARN_MSGS[@]} -gt 0 ]]; then
  COUNTER_FILE="/tmp/mandate_warn_count_$(basename "$FILE_PATH").txt"
  COUNT=0
  [[ -f "$COUNTER_FILE" ]] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
  COUNT=$((COUNT + 1))
  echo "$COUNT" > "$COUNTER_FILE"

  COMBINED=$(IFS=' || '; echo "${WARN_MSGS[*]}")
  if [[ $COUNT -ge 3 ]]; then
    COMBINED="MANDATE_RETRY_CAP (동일 파일 3+ warns — Q-Lead escalate 필요): $COMBINED"
  fi
  # (2026-07-24 Fable5 하네스 감사) 전달 복원 — 0ab8b039(2026-05-29)가 무효 decision:"allow" 래퍼를
  # 제거하며 warning 페이로드까지 소실(no-op 회귀). additionalContext로 실전달(공식 PostToolUse 스키마).
  MCC_MSG="$COMBINED" "$QVEST_PY_BIN" -c 'import json,os; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[mandate_compliance_check] "+os.environ.get("MCC_MSG","")}}))' 2>/dev/null || echo '{}'
else
  echo '{}'
fi
