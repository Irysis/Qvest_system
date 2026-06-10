#!/usr/bin/env bash
# worktask_artifact_validator.sh — WT 3-package schema 검증 (Level 2 soft gate)
# supersedes: artifact_validator.sh (archived 2026-04-23)
#
# 이벤트: PostToolUse[Write]
# 목적: alpha_package.json / risk_package.json / optimization_package.json 저장 후 schema 검증
#
# 필수 필드 누락 시 warn + log (block 아님, PostToolUse이므로)

set -euo pipefail
LOG="/tmp/worktask_artifact_validator.log"
FILE_PATH=""
trap 'echo "[$(date -Iseconds)] HOOK_ERR_TRAP file=${FILE_PATH:-unknown} line=${LINENO:-?}" >> "$LOG"; exit 0' ERR

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

# 대상 파일 확인 (v6.2: forge/judge/governor 추가)
case "$FILE_PATH" in
  */alpha_package.json|*/risk_package.json|*/optimization_package.json)
    ;;
  */forge_package.json|*/forge_phase4_package.json)
    ;;
  */judge_verdict.json|*/judge_lockbox_audit.json)
    ;;
  */governor_admission.json)
    ;;
  *)
    exit 0
    ;;
esac

LOG="/tmp/worktask_artifact_validator.log"

python3 <<PYEOF 2>>"$LOG"
import json, sys

fp = "$FILE_PATH"
try:
    with open(fp) as f:
        pkg = json.load(f)
except Exception as e:
    print(f"[WARN] {fp} JSON parse fail: {e}", file=sys.stderr)
    sys.exit(0)

# Defensive: pkg는 반드시 dict (list / scalar / null이면 schema 검증 자체 부적용)
if not isinstance(pkg, dict):
    print(f"[WARN] {fp} top-level not dict (got {type(pkg).__name__}) — schema check skipped", file=sys.stderr)
    sys.exit(0)

# package type 결정 (v6.2: forge/judge/governor 추가)
fp_lower = fp.lower()

if "alpha_vector" in pkg:
    required = ["task_id", "as_of_date", "alpha_vector", "factor_specs", "diagnostics"]
    # Tier 1 Iter5 mandate: 시계열 alpha (≥60 sig_dates) — alpha_scores_ref 또는 alpha_scores_path 또는 time_series_audit
    optional_v62 = ["alpha_scores_ref", "ax_axiom_compliance", "challenge_note_ref"]
    pkg_type = "alpha_package"
elif "factor_covariance_ref" in pkg:
    required = ["task_id", "as_of_date", "factor_covariance_ref", "risk_summary", "diagnostics"]
    optional_v62 = ["sigma_method", "cond_post_shrink", "tail_risk", "crowding_diagnostic"]
    pkg_type = "risk_package"
elif "method_selected" in pkg or "target_weights" in pkg:
    required = ["task_id", "as_of_date", "method_selected", "expected_tracking_error"]
    # Tier 1 v6.2 mandate: deploy_cutoff field 명시
    optional_v62 = ["deploy_cutoff", "method_shopping_log", "weights_csv_ref"]
    pkg_type = "optimization_package"
elif "forge_phase4_package" in fp_lower or "phase4_decision" in pkg:
    required = ["task_id", "backtest_summary", "scenario_comparison"]
    optional_v62 = ["same_period_baseline", "oos_24_26", "dsr_penalty_basis"]
    pkg_type = "forge_phase4_package"
elif "forge_package" in fp_lower or "backtest_summary" in pkg:
    # v6.3 Charter §9 SoT — 8 mandatory fields for PG2 admission grade
    required = [
        "task_id", "backtest_summary",
        "sr_realized_share_based",
        "measurement_basis_primary",
        "weights_csv_unique_dates_count",
        "alpha_sig_dates_count",
        "schedule_density_ratio",
        "schedule_density_pass",
        "pure_function_violation"
    ]
    optional_v62 = [
        "factor_regression_5_specs", "mega_baseline_same_period_ref", "regime_conditional_metrics",
        "sr_factor_engine_continuous", "sr_lockbox_daily_harness",
        "divergence_factor_engine_vs_realized_pp", "vs_factor_engine"
    ]
    pkg_type = "forge_package"
elif "judge_lockbox_audit" in fp_lower:
    required = ["wt_id", "lockbox_period", "lockbox_measurement_attempted"]
    optional_v62 = ["lockbox_nav", "verdict_basis"]
    pkg_type = "judge_lockbox_audit"
elif "judge_verdict" in fp_lower or "gate_results" in pkg or "verdict" in pkg and "gate" in str(pkg):
    required = ["task_id", "verdict"]
    optional_v62 = ["gate_results", "lockbox_audit_ref", "codex_round_response_ref", "role_honesty_audit"]
    pkg_type = "judge_verdict"
elif "governor_admission" in fp_lower or "scenario_identified" in pkg:
    required = ["task_id", "verdict"]
    optional_v62 = ["scenario_identified", "book_state_delta", "phase_decision_pending", "rule_misapplication_check"]
    pkg_type = "governor_admission"
else:
    print(f"[WARN] {fp} unknown package type", file=sys.stderr)
    sys.exit(0)

missing = [k for k in required if k not in pkg]
missing_v62 = [k for k in optional_v62 if k not in pkg]

# v6.2 mandate field 검증 추가 (warn level)
import os, time
alerts = "/tmp/worktask_alerts.log"

if missing:
    print(f"[WARN] {fp} ({pkg_type}) missing required fields: {missing}", file=sys.stderr)
    with open(alerts, "a") as f:
        f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} | {pkg_type} | {fp} | missing_required={missing}\n")
elif missing_v62:
    print(f"[INFO] {fp} ({pkg_type}) missing v6.2 mandate fields (soft warn): {missing_v62}", file=sys.stderr)
    with open(alerts, "a") as f:
        f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} | {pkg_type} | {fp} | missing_v62_mandate={missing_v62}\n")
else:
    print(f"[OK] {fp} ({pkg_type}) schema + v6.2 mandate PASS", file=sys.stderr)

# v7.0 Sprint 1 Charter §10 Positive Certifier — qvest_cert_eval router 위임
if pkg_type == "forge_package" and not missing:
    import os, sys as _sys
    wt_dir = os.path.dirname(fp)
    cert_path = os.path.join(wt_dir, "forge_package_validated_certificate.json")
    if not os.path.exists(cert_path):
        try:
            _sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else "/c/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/hooks")
            # router 단일 source
            from qvest_cert_eval import issue_certificate
            issue_certificate("forge_package_validated", fp, cert_path,
                              issued_by="worktask_artifact_validator.sh v7.0 (router 위임)")
        except Exception as _e:
            print(f"[WARN] cert issue 실패 fallback: {_e}", file=_sys.stderr)
PYEOF

exit 0
