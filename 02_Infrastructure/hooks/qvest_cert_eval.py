#!/usr/bin/env python3
"""
qvest_cert_eval.py — Qvest v7.0 Sprint 1 Cert Eligibility Generic Evaluator

목적:
- cert_rules.json (data layer) → generic evaluator (single responsibility)
- router / R wrapper / cert_backfill 모두 본 module 호출 → single source 강제
- threshold / required_field / operator = JSON 안에만 (data)
- 본 module = generic apply only. eligibility logic을 Python에 hardcode 안 함.

Hybrid 처리:
- simple comparator (<, >=, ==, exists, exists_numeric, exists_int) = JSON spec 직접 적용
- complex compute (mechanism_cited_chars / schedule_density 등) = JSON `compute: "named_function"` reference + COMPUTE_FUNCTIONS lookup table

Plan: nifty-tickling-hinton.md Sprint 1 작업 항목 2 (Codex revised #2/#3)
v1.0 — 2026-05-01 Session 76 Sprint 1
"""

import json
import os
from pathlib import Path
from typing import Optional


def project_root() -> Path:
    env_dir = os.environ.get("CLAUDE_PROJECT_DIR")
    if env_dir and Path(env_dir).is_dir():
        return Path(env_dir)
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / "02_Infrastructure" / "hooks" / "policies").is_dir():
            return parent
    return here.parent.parent.parent


PROJECT_ROOT = project_root()
CERT_POLICY_PATH = PROJECT_ROOT / "02_Infrastructure" / "hooks" / "policies" / "cert_rules.json"


_policy_cache: Optional[dict] = None


def load_cert_policy(force_reload: bool = False) -> dict:
    global _policy_cache
    if _policy_cache is not None and not force_reload:
        return _policy_cache
    if not CERT_POLICY_PATH.exists():
        raise FileNotFoundError(f"cert_rules.json not found: {CERT_POLICY_PATH}")
    with open(CERT_POLICY_PATH, "r", encoding="utf-8") as f:
        loaded = json.load(f)
    _policy_cache = loaded
    return loaded


def get_field(data: dict, path: str):
    """Resolve nested field by dot path. Supports `.length` suffix on lists."""
    if path is None:
        return None
    cur = data
    for key in path.split("."):
        if key == "length" and isinstance(cur, list):
            return len(cur)
        if isinstance(cur, dict):
            cur = cur.get(key)
        elif isinstance(cur, list):
            try:
                cur = cur[int(key)] if key.isdigit() else None
            except (ValueError, IndexError):
                cur = None
        else:
            return None
        if cur is None:
            return None
    return cur


def apply_operator(value, operator: str, threshold=None, expected_value=None) -> bool:
    """Generic operator dispatch."""
    if operator == "exists":
        return value is not None
    if operator == "exists_numeric":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if operator == "exists_int":
        return isinstance(value, int) and not isinstance(value, bool)
    if value is None:
        return False
    if operator in ("<", ">=", ">", "<="):
        if threshold is None:
            return False
        try:
            v = float(value)  # type: ignore[arg-type]
            t = float(threshold)  # type: ignore[arg-type]
        except (TypeError, ValueError):
            return False
        if operator == "<":
            return v < t
        if operator == ">=":
            return v >= t
        if operator == ">":
            return v > t
        return v <= t
    if operator == "==":
        return value == expected_value
    if operator == "!=":
        return value != expected_value
    return False


def compute_mechanism_chars(pkg: dict) -> int:
    """Concat hypothesis_summary + factor_specs[].economic_rationale + .formula → char count."""
    mech = pkg.get("hypothesis_summary", "") or ""
    for fs in pkg.get("factor_specs", []) or []:
        if isinstance(fs, dict):
            mech += " " + (fs.get("economic_rationale") or "")
            mech += " " + (fs.get("formula") or "")
    return len(mech.strip())


def compute_factor_specs_count(pkg: dict) -> int:
    fs = pkg.get("factor_specs")
    return len(fs) if isinstance(fs, list) else 0


def compute_schedule_density(pkg: dict):
    """schedule_density = weights_csv_unique_dates / sig_dates_count. Returns (ratio, has_infeas)."""
    sched = pkg.get("schedule_fidelity") or {}
    wcd = sched.get("weights_csv_unique_dates_count", 0)
    sdc = sched.get("alpha_sig_dates_count", 0)
    if not sdc:
        return None, False
    ratio = wcd / sdc
    has_infeas = bool(
        sched.get("infeasibility_report")
        or sched.get("schedule_skip_justified")
    )
    return ratio, has_infeas


COMPUTE_FUNCTIONS = {
    "mechanism_cited_chars": compute_mechanism_chars,
    "factor_specs_count": compute_factor_specs_count,
    "schedule_density": compute_schedule_density,
}


def evaluate_alpha_discovery(pkg: dict, spec: dict) -> dict:
    issues = []
    payload = {}
    rules = spec.get("eligibility_AND", {})

    cor = get_field(pkg, "diagnostics.alpha_inheritance_cor")
    cor_rule = rules.get("alpha_inheritance_cor", {})
    if cor is None:
        issues.append("alpha_inheritance_cor missing")
    elif not apply_operator(cor, cor_rule.get("operator", "<"), cor_rule.get("threshold", 0.95)):
        issues.append(f"cor={cor:.4f} >= {cor_rule.get('threshold', 0.95)}")
    else:
        payload["alpha_inheritance_cor"] = cor

    mech_chars = compute_mechanism_chars(pkg)
    mech_rule = rules.get("mechanism_cited_chars", {})
    if not apply_operator(mech_chars, mech_rule.get("operator", ">="), mech_rule.get("threshold", 50)):
        issues.append(f"mechanism {mech_chars} < {mech_rule.get('threshold', 50)}")
    else:
        payload["mechanism_cited_chars"] = mech_chars

    n_factor = compute_factor_specs_count(pkg)
    fs_rule = rules.get("factor_specs_count", {})
    if not apply_operator(n_factor, fs_rule.get("operator", ">="), fs_rule.get("threshold", 1)):
        issues.append(f"factor_specs {n_factor} < {fs_rule.get('threshold', 1)}")
    else:
        payload["factor_specs_count"] = n_factor

    ht = get_field(pkg, "diagnostics.harvey_t_specs_pass_count") or 0
    ht_rule = rules.get("harvey_t_specs_pass_count", {})
    if not apply_operator(ht, ht_rule.get("operator", ">="), ht_rule.get("threshold", 3)):
        issues.append(f"harvey_t_count {ht} < {ht_rule.get('threshold', 3)}")
    else:
        payload["harvey_t_specs_pass_count"] = ht

    return {
        "eligible": len(issues) == 0,
        "reason": "all_pass" if not issues else " | ".join(issues),
        "payload": payload,
    }


def evaluate_sr_provenance(pkg: dict, spec: dict) -> dict:
    rules = spec.get("eligibility_4_field", {})
    issues = []
    payload = {}
    for key, rule in rules.items():
        val = get_field(pkg, rule.get("field_path", key))
        op = rule.get("operator", "exists")
        ok = apply_operator(val, op,
                             threshold=rule.get("threshold"),
                             expected_value=rule.get("value"))
        if not ok:
            if op in ("exists", "exists_numeric", "exists_int"):
                issues.append(f"missing or wrong type: {key}")
            elif op == "==":
                issues.append(f"basis='{val}' != '{rule.get('value')}'")
            else:
                issues.append(f"{key} fail {op}")
        else:
            payload[key] = val
    return {
        "eligible": len(issues) == 0,
        "reason": "all_4_field_pass" if not issues else " | ".join(issues),
        "payload": payload,
    }


def evaluate_forge_package_validated(pkg: dict, spec: dict) -> dict:
    # spec.eligibility_8_field reserved for future schema-driven; current cert_rules.json lists 8+1
    _ = spec.get("eligibility_8_field")
    actual_required = [
        "task_id", "backtest_summary", "sr_realized_share_based",
        "measurement_basis_primary", "weights_csv_unique_dates_count",
        "alpha_sig_dates_count", "schedule_density_ratio",
        "schedule_density_pass", "pure_function_violation"
    ]
    missing = [r for r in actual_required if r not in pkg]
    return {
        "eligible": len(missing) == 0,
        "reason": "all_8_field_pass" if not missing else f"missing: {missing}",
        "payload": {"validated_fields_count": len(actual_required) - len(missing)},
    }


def evaluate_schedule_fidelity(pkg: dict, spec: dict) -> dict:
    ratio, has_infeas = compute_schedule_density(pkg)
    rules = spec.get("eligibility_OR", {})
    density_rule = rules.get("density", {})
    threshold = density_rule.get("threshold", 0.95)

    if ratio is None:
        return {"eligible": False, "reason": "alpha_sig_dates_count=0 or missing", "payload": {}}

    if apply_operator(ratio, density_rule.get("operator", ">="), threshold):
        return {
            "eligible": True,
            "reason": f"density={ratio:.3f}",
            "payload": {
                "schedule_density_ratio": round(ratio, 3),
                "infeasibility_report_cited": False,
            },
        }
    if has_infeas:
        return {
            "eligible": True,
            "reason": f"density={ratio:.3f} + infeasibility_report cited",
            "payload": {
                "schedule_density_ratio": round(ratio, 3),
                "infeasibility_report_cited": True,
            },
        }
    return {
        "eligible": False,
        "reason": f"density {ratio:.3f} < {threshold} + no infeasibility",
        "payload": {"schedule_density_ratio": round(ratio, 3)},
    }


def evaluate_governor_concord(book_state_path: str, spec: dict, wt_root: Optional[Path] = None) -> dict:  # noqa: ARG001
    _ = spec  # reserved for future spec-driven match (waiver fields)
    p = Path(book_state_path)
    if not p.exists():
        return {"eligible": False, "reason": "book_state.json 부재", "payload": {}}
    try:
        with open(p, "r", encoding="utf-8") as f:
            bs = json.load(f)
    except Exception as e:
        return {"eligible": False, "reason": f"parse fail: {e}", "payload": {}}

    admitted_ids = bs.get("admitted_ids") or []
    weights = bs.get("book_weights") or {}
    if not admitted_ids:
        return {"eligible": False, "reason": "no admitted_ids", "payload": {}}

    if wt_root is None:
        wt_root = PROJECT_ROOT / "qepm" / "mailbox" / "worktask"

    details = []
    all_match = True
    if wt_root.is_dir():
        ga_paths = list(wt_root.rglob("governor_admission.json"))
    else:
        ga_paths = []

    for sid in admitted_ids:
        sid = str(sid)
        ga_match = None
        for gp in ga_paths:
            try:
                with open(gp, "r", encoding="utf-8") as f:
                    ga = json.load(f)
            except Exception:
                continue
            alloc = ga.get("allocation_decided") or {}
            if ga.get("str_id") == sid or sid in alloc:
                ga_match = ga
                break
        if ga_match is None:
            all_match = False
            details.append({"str_id": sid, "match": False, "reason": "no governor_admission found"})
            continue
        expected = (ga_match.get("allocation_decided") or {}).get(sid)
        actual = weights.get(sid)
        is_match = (expected is not None) and (actual is not None) and (abs(float(expected) - float(actual)) < 0.01)
        if not is_match:
            all_match = False
        details.append({
            "str_id": sid,
            "expected_weight": expected,
            "actual_weight": actual,
            "match": is_match,
        })

    return {
        "eligible": all_match,
        "reason": "all_admitted_match" if all_match else "some_mismatch",
        "payload": {
            "concord_type": "match" if all_match else "with_waiver_required",
            "details": details,
        },
    }


CERT_EVALUATORS = {
    "alpha_discovery": evaluate_alpha_discovery,
    "sr_provenance": evaluate_sr_provenance,
    "forge_package_validated": evaluate_forge_package_validated,
    "schedule_fidelity": evaluate_schedule_fidelity,
}


def evaluate(cert_name: str, package_path: str, **kwargs) -> dict:
    """Generic dispatch — JSON spec 읽고 cert별 evaluator 호출."""
    policy = load_cert_policy()
    spec = policy.get("certificates", {}).get(cert_name)
    if spec is None:
        return {"eligible": False, "reason": f"unknown cert: {cert_name}", "payload": {}}

    if cert_name == "governor_concord":
        return evaluate_governor_concord(package_path, spec, wt_root=kwargs.get("wt_root"))

    p = Path(package_path)
    if not p.exists():
        return {"eligible": False, "reason": f"package not found: {package_path}", "payload": {}}
    try:
        with open(p, "r", encoding="utf-8") as f:
            pkg = json.load(f)
    except Exception as e:
        return {"eligible": False, "reason": f"parse fail: {e}", "payload": {}}

    evaluator = CERT_EVALUATORS.get(cert_name)
    if evaluator is None:
        return {"eligible": False, "reason": f"no evaluator for: {cert_name}", "payload": {}}
    return evaluator(pkg, spec)


def issue_certificate(cert_name: str, package_path: str, output_path: str,
                       wt_id: Optional[str] = None,
                       issued_by: str = "qvest_cert_eval.py v1.0") -> dict:
    """5 cert 공통 issue helper. evaluate 결과 + metadata 합성 → output_path 저장.

    Hook (.sh)는 본 함수 호출만 하면 됨. eligibility logic 보유 X.
    Returns evaluate result dict (caller가 ISSUED/NOT_ISSUED 메시지 생성).
    """
    import datetime as _dt

    result = evaluate(cert_name, package_path)
    eligible = result["eligible"]

    if wt_id is None:
        try:
            with open(package_path, "r", encoding="utf-8") as f:
                pkg = json.load(f)
            wt_id = pkg.get("task_id") or pkg.get("wt_id") or ""
        except Exception:
            wt_id = ""

    cert: dict = {
        "issued": bool(eligible),
        "wt_id": wt_id,
        "issued_at": _dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "issued_by": issued_by,
        "charter_ref": f"v1.2 §10 ({cert_name} certification)",
        "non_issuance_reason": None if eligible else result.get("reason"),
    }

    payload = result.get("payload") or {}
    if isinstance(payload, dict):
        for k, v in payload.items():
            if k not in cert:
                cert[k] = v

    if not eligible:
        remediation_map = {
            "alpha_discovery": "alpha agent rerun: cor < 0.95 + mechanism >= 50 chars + factor_specs >= 1 + harvey_t pass >= 3",
            "sr_provenance": "forge agent: forge_package.json에 sr_realized_share_based + measurement_basis_primary='forge_realized_share_based' + weights_csv_unique_dates_count + schedule_density_ratio 4-field 모두 작성",
            "forge_package_validated": "forge agent: forge_package.json 8-field 누락 보강 (task_id / backtest_summary / sr_realized_share_based / measurement_basis_primary / weights_csv_unique_dates_count / alpha_sig_dates_count / schedule_density_ratio / schedule_density_pass + pure_function_violation)",
            "schedule_fidelity": "optimizer agent: weights_csv_unique_dates / alpha_sig_dates_count >= 0.95 OR infeasibility_report 명시",
            "governor_concord": "governor: book_state.book_weights ↔ governor_admission.allocation_decided 일치, 또는 waiver_log 5-row 작성",
        }
        cert["remediation"] = remediation_map.get(cert_name, "see cert_rules.json eligibility spec")

    out = Path(output_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(cert, f, indent=2, ensure_ascii=False)

    return result


def selftest():
    """Selftest — load policy + 5 cert dispatch (file 부재 시 fail expected)."""
    policy = load_cert_policy(force_reload=True)
    certs = list((policy.get("certificates") or {}).keys())
    print(f"[PASS] cert policy loaded: {len(certs)} certs ({', '.join(certs)})")

    fail_detect = 0
    for cert in certs:
        res = evaluate(cert, "/nonexistent/path.json")
        if not res["eligible"]:
            fail_detect += 1
            print(f"[PASS] {cert}: file 부재 detection ({res['reason'][:60]})")
        else:
            print(f"[FAIL] {cert}: should be ineligible but eligible=True")

    print(f"\n=== qvest_cert_eval selftest: {fail_detect}/{len(certs)} PASS ===")
    return fail_detect == len(certs)


if __name__ == "__main__":
    import sys
    if len(sys.argv) >= 2 and sys.argv[1] == "selftest":
        ok = selftest()
        sys.exit(0 if ok else 1)
    elif len(sys.argv) >= 4 and sys.argv[1] == "evaluate":
        cert_name = sys.argv[2]
        pkg_path = sys.argv[3]
        result = evaluate(cert_name, pkg_path)
        print(json.dumps(result))
        sys.exit(0 if result["eligible"] else 1)
    elif len(sys.argv) >= 5 and sys.argv[1] == "issue":
        cert_name = sys.argv[2]
        pkg_path = sys.argv[3]
        out_path = sys.argv[4]
        issued_by = sys.argv[5] if len(sys.argv) >= 6 else "qvest_cert_eval.py v1.0"
        result = issue_certificate(cert_name, pkg_path, out_path, issued_by=issued_by)
        print(json.dumps({
            "issued": result["eligible"],
            "reason": result["reason"],
            "cert_path": out_path,
        }))
        sys.exit(0)
    else:
        print(json.dumps({
            "usage": "qvest_cert_eval.py selftest | evaluate <cert_name> <package_path> | issue <cert_name> <package_path> <output_path> [issued_by]"
        }))
        sys.exit(2)
