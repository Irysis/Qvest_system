#!/usr/bin/env bash
# ★v10 (2026-09-03) 주의 — 이 파일은 v9 등록 해제분(사료)이고 judge_lockbox_audit 스키마 · governor_admission · cert 발급 라우팅 가 남아 있다.
#   전부 v10 폐지 개념(lockbox·governor·book_state·cert)이므로 **재등록 금지** — 되살리려면 그 분기를 먼저
#   제거하고 양성/음성 대조를 다시 만들 것. 파일 자체는 08_Tests·hook_e2e_battery 가 경로로 실행한다(이동 금지).
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
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
FILE_PATH=$(echo "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

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

"$QVEST_PY_BIN" <<PYEOF 2>>"$LOG"
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
    optional_v62 = ["gate_results", "lockbox_audit_ref", "role_honesty_audit"]
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

# ── FQ-119 라벨 자격 관문 (2026-08-08 배선, warn level) ────────────────────────
# 왜 여기인가: schema.json 에는 조건부 required 를 넣었지만 이 저장소에 JSON-Schema
# 실행 엔진이 배선돼 있지 않다(R jsonvalidate 미설치 · wt_validate_package 호출부 0).
# 그래서 스키마만 고치면 그것도 dead 계약이 된다 — 실제로 발화하는 표면은 이 훅이다.
# PostToolUse 라 block 은 불가(구조상 warn) — 승격은 PreToolUse 이설이 필요하며 별건.
LBL_DECL_HINTS = ("CRISIS", "CAUTION", "RISK_ON", "RISK_OFF",
                  "regime_label", "regime_category", "unified_regime_signal")
lc = pkg.get("label_consumption")
declared = isinstance(lc, dict) and lc.get("consumes_regime_label") is True

def _lbl_warn(kind, detail):
    print(f"[WARN] {fp} ({pkg_type}) label_gate {kind}: {detail}", file=sys.stderr)
    with open(alerts, "a") as f:
        f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} | {pkg_type} | {fp} | label_gate_{kind}={detail}\n")

if declared:
    ev = lc.get("label_eligibility")
    if not isinstance(ev, dict):
        _lbl_warn("evidence_missing",
                  "consumes_regime_label=true 인데 label_eligibility 증거 없음 (02_Infrastructure/contracts/label_eligibility_gate.R 경유 제출 필요)")
    else:
        verdict = ev.get("verdict")
        gaps = [k for k in ("event_definition", "label_definition", "contract", "fisher_p") if not ev.get(k)]
        if gaps:
            _lbl_warn("evidence_incomplete", "증거 필드 누락 " + str(gaps) + " — 사건정의 없는 판정은 인용 불가(자격은 (라벨,사건정의) 쌍에 붙는다)")
        elif verdict != "ELIGIBLE":
            _lbl_warn("ineligible_label",
                      f"verdict={verdict} — 판별력 없는 라벨은 중립이 아니라 발화 월수에 비례해 유해(WT-019 paired -3.77). 이 라운드의 소비면 결과는 해석 불가")
        else:
            print(f"[OK] {fp} label_gate ELIGIBLE ({ev.get('event_definition')})", file=sys.stderr)
else:
    # 미선언 우회 탐지 — 선언을 생략하면 스키마 조건부는 영원히 발화하지 않는다.
    #   ★한글 혼재 텍스트라 정규식 경계(\b)는 조용히 FALSE 가 되므로 부분문자열 포함만 쓴다.
    try:
        blob = json.dumps(pkg, ensure_ascii=False)
    except Exception:
        blob = ""
    hits = sorted({t for t in LBL_DECL_HINTS if t in blob})
    if hits:
        _lbl_warn("undeclared_consumption",
                  "라벨 소비 흔적 " + str(hits) + " 이 있는데 label_consumption 선언·자격 증거 없음 (흔적 기반 warn — 오탐 가능)")

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
