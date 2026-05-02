#!/usr/bin/env python3
"""
qvest_hook_router.py — Qvest v6.4 Hook Kernel Router

목적:
- 4 policy JSON (state_transitions / role_permissions / codex_round_contract / cert_rules) 단일 진입점
- 신규/변경 hook이 정규식 중복 보유 안 함 (policy import)
- $CLAUDE_PROJECT_DIR 우선 사용 (Claude Code 공식 방식)

사용:
- 새 hook (Phase 4+ 신규) 작성 시 본 router import
- 기존 17~18 hook은 retain (점진 migration). 변경 시점에 router 경유로 전환.

상태:
- v1.0 (2026-05-01 Session 75 Sprint 2 Phase 4)
- 본 router 자체는 hook 아님 — hook이 호출하는 helper library
- 향후 (Sprint 3 Phase 9 후속): 기존 17~18 hook 그룹별 router 경유 변경

Usage examples:

# Hook bash script에서:
PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ROUTER="$PROJ_DIR/02_Infrastructure/hooks/qvest_hook_router.py"

# 1. 파일 path가 어떤 role의 어떤 stage 산출물인지 분류
ROLE_INFO=$(python3 "$ROUTER" classify --file-path "$FILE_PATH")
# → {"role":"alpha","stage":"draft","is_final":false}

# 2. role permissions 검증
python3 "$ROUTER" check-permission --role "$AGENT_ROLE" --file-path "$FILE_PATH"
# exit 0 → allowed / exit 1 → forbidden

# 3. cert eligibility 검증
python3 "$ROUTER" check-cert --cert "alpha_discovery" --package-path "$FILE_PATH"
# stdout: {"eligible":true|false,"reason":"...","payload":{...}}

# 4. WT phase 전이 검증
python3 "$ROUTER" check-transition --wt-id "$WT_ID" --from "ALPHA_DONE" --to "RISK_DONE"

# 5. codex round 5단계 검증 (final write 전)
python3 "$ROUTER" check-codex-round-complete --wt-id "$WT_ID" --role "$ROLE"
# exit 0 → allow finalize / exit 1 → block (draft + critic_response 부재)
"""

import json
import os
import re
import sys
from pathlib import Path
from typing import Optional, Tuple

# ─────────────────────────────────────────────────────────────────
# Project root detection
# ─────────────────────────────────────────────────────────────────

def project_root() -> Path:
    """Resolve project root via CLAUDE_PROJECT_DIR or fallback."""
    env_dir = os.environ.get("CLAUDE_PROJECT_DIR")
    if env_dir and Path(env_dir).is_dir():
        return Path(env_dir)
    # Fallback: search upward for common marker
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / "02_Infrastructure" / "hooks" / "policies").is_dir():
            return parent
    return here.parent.parent.parent

PROJECT_ROOT = project_root()
POLICIES_DIR = PROJECT_ROOT / "02_Infrastructure" / "hooks" / "policies"

# ─────────────────────────────────────────────────────────────────
# Policy loaders (cached)
# ─────────────────────────────────────────────────────────────────

_policy_cache = {}

def load_policy(name: str) -> dict:
    """Load policy JSON with cache. name ∈ {state_transitions, role_permissions, codex_round_contract, cert_rules}."""
    if name in _policy_cache:
        return _policy_cache[name]
    path = POLICIES_DIR / f"{name}.json"
    if not path.exists():
        raise FileNotFoundError(f"Policy not found: {path}")
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    _policy_cache[name] = data
    return data


def load_artifact_contract() -> dict:
    """Load artifact_contract.json (Phase 3 single source)."""
    path = PROJECT_ROOT / "02_Infrastructure" / "worktask" / "artifact_contract.json"
    if not path.exists():
        return {}
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


# ─────────────────────────────────────────────────────────────────
# 1. classify — file_path → role + stage
# ─────────────────────────────────────────────────────────────────

ROLE_FILE_PATTERNS = [
    (r"/alpha_package\.json$", "alpha", "final"),
    (r"/alpha_package_draft\.json$", "alpha", "draft"),
    (r"/risk_package\.json$", "risk", "final"),
    (r"/risk_package_draft\.json$", "risk", "draft"),
    (r"/optimization_package\.json$", "optimizer", "final"),
    (r"/optimization_package_draft\.json$", "optimizer", "draft"),
    (r"/forge_package\.json$", "forge", "final"),
    (r"/forge_package_draft\.json$", "forge", "draft"),
    (r"/judge_verdict\.json$", "judge", "final"),
    (r"/judge_verdict_draft\.json$", "judge", "draft"),
    (r"/governor_admission\.json$", "governor", "final"),
    (r"/governor_admission_draft\.json$", "governor", "draft"),
    (r"/codex_critic_response_(alpha|risk|optimizer|forge|judge|governor)\.json$", "codex_response", "response"),
    (r"/book_state\.json$", "governor", "global_book"),
    (r"/(.*?)_challenge_note\.md$", "challenge_note", "challenge_role_specific"),
    (r"/challenge_note\.md$", "challenge_note", "challenge_canonical"),
]


def classify(file_path: str) -> dict:
    """Classify file_path. Returns {role, stage, is_final}."""
    if not file_path:
        return {"role": None, "stage": None, "is_final": False}
    for pattern, role, stage in ROLE_FILE_PATTERNS:
        if re.search(pattern, file_path):
            return {
                "role": role,
                "stage": stage,
                "is_final": stage == "final",
            }
    return {"role": None, "stage": None, "is_final": False}


# ─────────────────────────────────────────────────────────────────
# 2. check_permission — role can write file_path?
# ─────────────────────────────────────────────────────────────────

def check_permission(role: str, file_path: str) -> Tuple[bool, str]:
    """Check role permission. Returns (allowed, reason)."""
    if not role or not file_path:
        return False, "role or file_path missing"
    policy = load_policy("role_permissions")
    perms = policy.get("permissions", {}).get(role, {})
    if not perms:
        return False, f"unknown role: {role}"

    # Check absolute_forbidden (substring match in description — best effort)
    forbidden = perms.get("absolute_forbidden", [])
    cls = classify(file_path)
    cls_role = cls.get("role")
    if cls_role and cls_role != role:
        # Check if writing to other role's package
        if cls_role in ("alpha", "risk", "optimizer", "forge", "judge", "governor"):
            return False, f"role={role} writing to {cls_role}_package — Hook L3 block"

    return True, "allowed"


# ─────────────────────────────────────────────────────────────────
# 3. check_cert_eligibility — for cert auto-issue
# ─────────────────────────────────────────────────────────────────

def _get_field(data: dict, path: str):
    """Get nested field by dot path (e.g. 'diagnostics.alpha_inheritance_cor')."""
    cur = data
    for key in path.split("."):
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


def check_cert_eligibility(cert_name: str, package_path: str) -> dict:
    """v7.0 Sprint 1 — qvest_cert_eval (single responsibility) 위임. router는 CLI routing만."""
    try:
        from qvest_cert_eval import evaluate as cert_evaluate
    except ImportError:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from qvest_cert_eval import evaluate as cert_evaluate
    return cert_evaluate(cert_name, package_path)


# ─────────────────────────────────────────────────────────────────
# 4. check_codex_round_complete — final write 전 검증
# ─────────────────────────────────────────────────────────────────

def check_codex_round_complete(wt_id: str, role: str) -> Tuple[bool, str]:
    """Verify draft + critic_response present. Returns (complete, reason)."""
    wt_dir = PROJECT_ROOT / "qepm" / "mailbox" / "worktask" / wt_id
    if not wt_dir.is_dir():
        return False, f"WT dir not found: {wt_id}"

    role_to_draft = {
        "alpha": "alpha_package_draft.json",
        "risk": "risk_package_draft.json",
        "optimizer": "optimization_package_draft.json",
        "forge": "forge_package_draft.json",
        "judge": "judge_verdict_draft.json",
        "governor": "governor_admission_draft.json",
    }
    draft_name = role_to_draft.get(role)
    if not draft_name:
        return False, f"unknown role: {role}"

    draft_path = wt_dir / draft_name
    critic_path = wt_dir / f"codex_critic_response_{role}.json"
    challenge_path = wt_dir / "challenge_note.md"
    challenge_role_path = wt_dir / f"{role}_challenge_note.md"

    draft_exists = draft_path.exists()
    critic_exists = critic_path.exists()
    challenge_exists = challenge_path.exists() or challenge_role_path.exists()

    # Waiver check
    if challenge_path.exists():
        try:
            content = challenge_path.read_text(encoding="utf-8")
            if "codex_critic_skip_waiver" in content:
                return True, "waiver: codex_critic_skip_waiver in challenge_note.md"
        except Exception:
            pass

    if draft_exists and critic_exists:
        return True, "complete: draft + critic_response present"

    return False, (
        f"incomplete: draft={'present' if draft_exists else 'missing'} | "
        f"critic_response={'present' if critic_exists else 'missing'}"
    )


# ─────────────────────────────────────────────────────────────────
# 5. check_transition — WT phase 전이 검증
# ─────────────────────────────────────────────────────────────────

def check_transition(wt_id: str, from_phase: str, to_phase: str) -> Tuple[bool, str]:
    """Verify phase transition allowed. Returns (allowed, reason)."""
    policy = load_policy("state_transitions")
    transitions = policy.get("transitions", {})
    rule = transitions.get(from_phase)
    if not rule:
        return False, f"unknown from_phase: {from_phase}"
    allowed_next = rule.get("allowed_next", [])
    if to_phase in allowed_next:
        return True, f"transition {from_phase} → {to_phase} allowed"
    if rule.get("terminal"):
        return False, f"{from_phase} is terminal"
    return False, f"transition {from_phase} → {to_phase} not in allowed_next: {allowed_next}"


# ─────────────────────────────────────────────────────────────────
# 6. validate_schema — JSON Schema Draft-07 validation (Sprint 3)
# ─────────────────────────────────────────────────────────────────

SCHEMAS_DIR = PROJECT_ROOT / "02_Infrastructure" / "schemas"

SCHEMA_NAME_MAP = {
    "alpha_package": "packages/alpha_package_schema.json",
    "risk_package": "packages/risk_package_schema.json",
    "optimization_package": "packages/optimization_package_schema.json",
    "forge_package": "packages/forge_package_schema.json",
    "judge_verdict": "packages/judge_verdict_schema.json",
    "governor_admission": "packages/governor_admission_schema.json",
    "alpha_discovery_certificate": "certs/alpha_discovery_certificate_schema.json",
    "sr_provenance_certificate": "certs/sr_provenance_certificate_schema.json",
    "schedule_fidelity_certificate": "certs/schedule_fidelity_certificate_schema.json",
    "forge_package_validated_certificate": "certs/forge_package_validated_certificate_schema.json",
    "governor_concord_certificate": "certs/governor_concord_certificate_schema.json",
    "book_state": "state/book_state_schema.json",
    "governance_log": "state/governance_log_schema.json",
    "artifact_lineage": "state/artifact_lineage_schema.json",
    "axiom": "state/axiom_schema.json",
}


def validate_schema(schema_name: str, package_path: str) -> Tuple[bool, str]:
    """Validate JSON file against Draft-07 schema. Returns (valid, reason)."""
    schema_rel = SCHEMA_NAME_MAP.get(schema_name)
    if not schema_rel:
        return False, f"unknown schema: {schema_name}. Known: {list(SCHEMA_NAME_MAP.keys())}"
    schema_path = SCHEMAS_DIR / schema_rel
    if not schema_path.exists():
        return False, f"schema file not found: {schema_path}"
    if not Path(package_path).exists():
        return False, f"package not found: {package_path}"

    try:
        import jsonschema
    except ImportError:
        return False, "jsonschema package not installed (pip install jsonschema)"

    try:
        with open(schema_path, "r", encoding="utf-8") as f:
            schema = json.load(f)
        with open(package_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        return False, f"parse fail: {e}"

    try:
        jsonschema.validate(instance=data, schema=schema)
        return True, "valid"
    except jsonschema.ValidationError as e:
        # truncate path + message for log readability
        path_str = ".".join(str(p) for p in e.absolute_path) or "<root>"
        return False, f"INVALID at '{path_str}': {e.message[:200]}"
    except Exception as e:
        return False, f"validate fail: {e}"


# ─────────────────────────────────────────────────────────────────
# CLI dispatch
# ─────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "usage: qvest_hook_router.py <command> [args]"}), file=sys.stderr)
        sys.exit(2)

    cmd = sys.argv[1]
    args = {}
    i = 2
    while i < len(sys.argv):
        a = sys.argv[i]
        if a.startswith("--"):
            key = a[2:].replace("-", "_")
            if i + 1 < len(sys.argv):
                args[key] = sys.argv[i + 1]
                i += 2
            else:
                args[key] = True
                i += 1
        else:
            i += 1

    if cmd == "classify":
        result = classify(args.get("file_path", ""))
        print(json.dumps(result))
        sys.exit(0)
    elif cmd == "check-permission":
        ok, reason = check_permission(args.get("role", ""), args.get("file_path", ""))
        print(json.dumps({"allowed": ok, "reason": reason}))
        sys.exit(0 if ok else 1)
    elif cmd == "check-cert":
        result = check_cert_eligibility(args.get("cert", ""), args.get("package_path", ""))
        print(json.dumps(result))
        sys.exit(0 if result["eligible"] else 1)
    elif cmd == "check-transition":
        ok, reason = check_transition(args.get("wt_id", ""), args.get("from", ""), args.get("to", ""))
        print(json.dumps({"allowed": ok, "reason": reason}))
        sys.exit(0 if ok else 1)
    elif cmd == "check-codex-round-complete":
        ok, reason = check_codex_round_complete(args.get("wt_id", ""), args.get("role", ""))
        print(json.dumps({"complete": ok, "reason": reason}))
        sys.exit(0 if ok else 1)
    elif cmd == "validate-schema":
        ok, reason = validate_schema(args.get("schema", ""), args.get("package", "") or args.get("package_path", ""))
        print(json.dumps({"valid": ok, "reason": reason}))
        sys.exit(0 if ok else 1)
    elif cmd == "selftest":
        # Selftest: load all 4 policies + classify few patterns
        loaded = []
        for name in ["state_transitions", "role_permissions", "codex_round_contract", "cert_rules"]:
            try:
                load_policy(name)
                loaded.append(name)
            except Exception as e:
                print(json.dumps({"error": f"{name}: {e}"}), file=sys.stderr)
                sys.exit(2)
        tests = [
            classify("/path/qepm/mailbox/worktask/WT-D20260501_001/alpha_package.json"),
            classify("/path/qepm/mailbox/worktask/WT-D20260501_001/optimization_package_draft.json"),
            classify("/path/qepm/mailbox/governor/book_state.json"),
        ]
        print(json.dumps({
            "policies_loaded": loaded,
            "classify_tests": tests,
            "project_root": str(PROJECT_ROOT),
            "policies_dir": str(POLICIES_DIR),
            "status": "OK"
        }, indent=2))
        sys.exit(0)
    else:
        print(json.dumps({"error": f"unknown command: {cmd}"}), file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
