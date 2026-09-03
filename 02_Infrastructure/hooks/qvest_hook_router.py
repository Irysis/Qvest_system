#!/usr/bin/env python3
"""
qvest_hook_router.py — Qvest Hook Kernel Router (v10.1 기준)

★dispatch 경로는 v9(2026-08-23) 폐지 — settings.json 은 12훅 직접 등록이다.
  이 파일이 살아 있는 이유는 classify / check-* / validate-schema 서브커맨드이고
  CI(qvest-kernel-ci.yml)와 hook_integrity_check 가 그것을 소비한다. 사연 = 00_Lawbook/DEPRECATION.md

목적:
- 3 policy JSON (state_transitions / role_permissions / cert_rules) 단일 진입점 (v8.2: codex_round_contract 제거 — Codex Round 폐지)
- 신규/변경 hook이 정규식 중복 보유 안 함 (policy import)
- $CLAUDE_PROJECT_DIR 우선 사용 (Claude Code 공식 방식)

사용:
- 새 hook (Phase 4+ 신규) 작성 시 본 router import
- 기존 17~18 hook은 retain (점진 migration). 변경 시점에 router 경유로 전환.

상태:
- v1.0 (2026-05-01 Session 75 Sprint 2 Phase 4)
- v1.1 (2026-07-04 HOOK-P1-4): `dispatch` 커맨드 신설 — PreToolUse[Write|Edit]
  게이트 17훅을 settings.json 1-command로 fan-out (등록 SOT:
  policies/router_dispatch.json). 그 외 이벤트(Agent/Read/Bash 매처,
  PostToolUse/Stop/SubagentStop)는 settings.json 개별 등록 유지.
- helper library 겸 dispatch 진입점 (dispatch 외 커맨드는 종전과 동일)

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
    """Load policy JSON with cache. name ∈ {state_transitions, role_permissions, cert_rules}. (v8.2: codex_round_contract 제거)"""
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
    """v8.2: Codex Critic Round 제거(Opus 4.8 자체 적대검증으로 대체). 항상 complete 반환(passthrough — 잔여 호출자 무차단)."""
    return True, "codex round removed v8.2 — self-adversarial in-agent (AX-008)"
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
# 7. dispatch — PreToolUse hook fan-out (HOOK-P1-4, 2026-07-04)
# ─────────────────────────────────────────────────────────────────
# settings.json의 PreToolUse[Write|Edit] 개별 17 command를 본 라우터
# 1-command로 통합. 등록 SOT: policies/router_dispatch.json.
# 판정 채널 보존: Qvest 훅 전수가 "stdout JSON + exit 0" 채널
# ({"decision":"block",...} 또는 hookSpecificOutput.permissionDecision)
# 이므로, dispatcher는 각 훅에 동일 payload를 stdin으로 주고
# stdout을 수집·병합한다 (first-block verbatim 전달).
# 실행 fidelity: cwd=PROJECT_ROOT(상대경로 훅 — discovery_graduation_gate),
# per-hook stderr_log(구 2>>/tmp/*.log), soft_fail(구 '|| true').
# fail-closed: dispatcher 내부 오류/훅 timeout 시 payload 보호 패턴
# (05_Production / 01_Literature 비-Korea_Research / normalizePath /
#  WT-P*+request.json graduation) 감지 시 block — safety_guard·
# discovery_graduation_gate v8.2.1 fail-closed 정책과 동일 절충.

DISPATCH_LOG = "/tmp/qvest_hook_router_dispatch.log"
HOOKS_DIR = PROJECT_ROOT / "02_Infrastructure" / "hooks"
PER_HOOK_TIMEOUT_S = 30


def _dlog(msg: str):
    """Append to dispatcher log (best-effort)."""
    try:
        import datetime
        with open(DISPATCH_LOG, "a", encoding="utf-8", errors="replace") as f:
            f.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M:%S} {msg}\n")
    except Exception:
        pass


def _fail_closed_decision(payload_text: str) -> bytes:
    """Pattern-based fail-closed (safety_guard._gate_fail_closed +
    discovery_graduation_gate 동일 절충): 보호 대상 패턴 감지 시 block, 아니면 allow."""
    hay = payload_text or ""
    protected = (
        ("05_Production" in hay)
        or ("normalizePath" in hay)
        or ("01_Literature" in hay and "Korea_Research" not in hay)
        or ("WT-P" in hay and "request.json" in hay)
    )
    if protected:
        return json.dumps({
            "decision": "block",
            "reason": ("qvest_hook_router dispatch: 내부 오류/판별불능 — 보호 대상 패턴"
                       "(05_Production, 01_Literature, normalizePath, WT-P graduation) 감지, "
                       "검증 불가 시 차단 (fail-closed)")
        }, ensure_ascii=False).encode("utf-8")
    return b"{}"


def _resolve_bash() -> Optional[str]:
    """Git Bash 우선 해석 (System32 bash = WSL — 회피)."""
    import shutil
    cand = shutil.which("bash")
    if cand and "system32" not in cand.lower():
        return cand
    for p in (r"C:\Program Files\Git\usr\bin\bash.exe",
              r"C:\Program Files\Git\bin\bash.exe",
              "/usr/bin/bash"):
        if Path(p).exists():
            return p
    return cand  # 최후: System32 bash라도 (없으면 None)


def _parse_hook_stdout(raw: bytes):
    """Classify hook stdout. Returns (kind, parsed) — kind ∈ {empty, allow, block, context, other}."""
    text = raw.decode("utf-8", "replace").strip()
    if not text:
        return "empty", None
    try:
        d = json.loads(text)
    except Exception:
        return "other", None  # plain-text advisory — verbatim 후보
    if not isinstance(d, dict) or not d:
        return "allow" if d == {} else "other", d
    if d.get("decision") in ("block", "deny"):
        return "block", d
    hso = d.get("hookSpecificOutput") or {}
    if isinstance(hso, dict) and hso.get("permissionDecision") in ("deny", "ask"):
        return "block", d
    if set(d.keys()) == {"additionalContext"}:
        return "context", d
    return "other", d


def dispatch_event(event: str) -> int:
    """Read hook payload from stdin, fan out to registered hooks, merge verdicts.
    Returns process exit code."""
    raw_payload = sys.stdin.buffer.read()
    payload_text = raw_payload.decode("utf-8", "replace")

    def emit(b: bytes) -> int:
        sys.stdout.buffer.write(b)
        sys.stdout.buffer.write(b"\n")
        sys.stdout.buffer.flush()
        return 0

    try:
        registry = load_policy("router_dispatch")
        hooks = registry.get("events", {}).get(event, {}).get("hooks", [])
        if not hooks:
            _dlog(f"dispatch: no hooks registered for event={event} — allow")
            return emit(b"{}")

        try:
            tool_name = (json.loads(payload_text) or {}).get("tool_name", "")
        except Exception:
            tool_name = ""
        if not tool_name:
            # PreToolUse는 tool_name 상시 존재 — 파싱 불능 = fail-closed 판정
            _dlog(f"dispatch: tool_name unparseable — pattern fail-closed 판정")
            return emit(_fail_closed_decision(payload_text))

        bash_bin = _resolve_bash()
        if not bash_bin:
            _dlog("dispatch: bash 실행기 미발견 — pattern fail-closed 판정")
            return emit(_fail_closed_decision(payload_text))

        import subprocess
        from concurrent.futures import ThreadPoolExecutor
        env = dict(os.environ)
        env.setdefault("CLAUDE_PROJECT_DIR", str(PROJECT_ROOT))

        blocks = []          # (script, raw stdout bytes)
        contexts = []        # additionalContext strings
        others = []          # (script, raw stdout bytes) — 미분류 verbatim 후보
        hard_stderr = []     # non-soft-fail 훅의 stderr (CC 원 semantics: verbose 표출)
        fail_closed_pending = False

        applicable = []
        for entry in hooks:
            script = entry.get("script", "")
            if tool_name not in entry.get("tools", []):
                continue
            spath = HOOKS_DIR / script
            if not spath.exists():
                # 구 semantics: bash가 파일 부재 에러 → soft는 ||true 삼킴, hard는 non-blocking error
                _dlog(f"dispatch: MISSING hook script {script} — continue (구 semantics 동일)")
                continue
            applicable.append((entry, spath))

        def _run_one(item):
            """Run single hook. Returns (entry, proc|None, err_tag)."""
            entry, spath = item
            try:
                proc = subprocess.run(
                    [bash_bin, str(spath).replace("\\", "/")],
                    input=raw_payload,
                    capture_output=True,
                    cwd=str(PROJECT_ROOT),
                    env=env,
                    timeout=PER_HOOK_TIMEOUT_S,
                )
                return entry, proc, None
            except subprocess.TimeoutExpired:
                return entry, None, "TIMEOUT"
            except Exception as e:
                return entry, None, f"SPAWN-FAIL: {e}"

        # CC 원 semantics = 매칭 훅 병렬 실행 → 병렬 fan-out (결과 병합은 등록 순서 유지)
        if applicable:
            with ThreadPoolExecutor(max_workers=len(applicable)) as pool:
                run_results = list(pool.map(_run_one, applicable))
        else:
            run_results = []

        for entry, proc, err in run_results:
            script = entry.get("script", "")
            soft = bool(entry.get("soft_fail"))
            stderr_log = entry.get("stderr_log")
            if err is not None:
                _dlog(f"dispatch: {err} {script} (soft={soft})")
                if err == "TIMEOUT" or not soft:
                    fail_closed_pending = True  # 보호 패턴 감지 시에만 block (아래)
                continue

            # stderr fidelity: 구 2>>log 경로 보존 / hard 훅은 dispatcher stderr로 전달
            if proc.stderr:
                if stderr_log:
                    try:
                        with open(stderr_log, "ab") as f:
                            f.write(proc.stderr)
                    except Exception:
                        _dlog(f"dispatch: stderr_log write fail {script} → {stderr_log}")
                else:
                    hard_stderr.append(proc.stderr)

            # exit code fidelity: 전수 훅이 정상 시 exit 0. 비정상 exit는
            # 구 semantics(soft=||true 삼킴 / hard=CC non-blocking error)와 동일하게 non-block.
            if proc.returncode != 0:
                _dlog(f"dispatch: EXIT {proc.returncode} {script} (soft={soft}) — non-block (구 semantics)")

            kind, parsed = _parse_hook_stdout(proc.stdout)
            if kind == "block":
                blocks.append((script, proc.stdout.strip()))
                _dlog(f"dispatch: BLOCK by {script} tool={tool_name}")
            elif kind == "context":
                contexts.append(str(parsed.get("additionalContext", "")))
            elif kind == "other":
                others.append((script, proc.stdout.strip()))

        # timeout/spawn-fail 훅 존재 시 pattern fail-closed 판정 (block 미존재 시에만 의미)
        if fail_closed_pending and not blocks:
            fc = _fail_closed_decision(payload_text)
            if fc != b"{}":
                return emit(fc)

        # stderr 전달 (hard 훅 — 구 semantics에서 CC verbose로 노출되던 채널)
        for sb in hard_stderr:
            try:
                sys.stderr.buffer.write(sb)
            except Exception:
                pass

        # 병합: block 최우선 (first-block verbatim — 등록 순서 = 구 settings 순서)
        if blocks:
            if len(blocks) > 1:
                _dlog("dispatch: multi-block — forwarding first: "
                      + ", ".join(s for s, _ in blocks))
            return emit(blocks[0][1])
        if contexts and not others:
            if len(contexts) == 1:
                return emit(json.dumps({"additionalContext": contexts[0]},
                                       ensure_ascii=False).encode("utf-8"))
            return emit(json.dumps({"additionalContext": "\n".join(contexts)},
                                   ensure_ascii=False).encode("utf-8"))
        if others:
            if len(others) > 1 or contexts:
                _dlog("dispatch: multiple non-block outputs — forwarding first verbatim: "
                      + ", ".join(s for s, _ in others))
            return emit(others[0][1])
        return emit(b"{}")

    except Exception as e:
        _dlog(f"dispatch: INTERNAL ERROR {type(e).__name__}: {e} — pattern fail-closed 판정")
        return emit(_fail_closed_decision(payload_text))


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
    elif cmd == "dispatch":
        # HOOK-P1-4: PreToolUse Write/Edit 게이트 fan-out (stdin = hook payload JSON)
        sys.exit(dispatch_event(args.get("event", "PreToolUse")))
    elif cmd == "selftest":
        # Selftest: load all policies + classify few patterns
        loaded = []
        for name in ["state_transitions", "role_permissions", "cert_rules"]:
            try:
                load_policy(name)
                loaded.append(name)
            except Exception as e:
                print(json.dumps({"error": f"{name}: {e}"}), file=sys.stderr)
                sys.exit(2)
        # dispatch registry 검증 (HOOK-P1-4): 존재 시 스크립트 전수 실재 확인
        dispatch_status = "absent"
        try:
            reg = load_policy("router_dispatch")
            missing = []
            n = 0
            for ev, cfg in reg.get("events", {}).items():
                for h in cfg.get("hooks", []):
                    n += 1
                    if not (HOOKS_DIR / h.get("script", "")).exists():
                        missing.append(h.get("script", ""))
            dispatch_status = f"OK ({n} hooks registered)" if not missing else f"MISSING: {missing}"
            loaded.append("router_dispatch")
        except FileNotFoundError:
            pass
        except Exception as e:
            dispatch_status = f"ERROR: {e}"
        tests = [
            classify("/path/qepm/mailbox/worktask/WT-D20260501_001/alpha_package.json"),
            classify("/path/qepm/mailbox/worktask/WT-D20260501_001/optimization_package_draft.json"),
            classify("/path/qepm/mailbox/governor/book_state.json"),
        ]
        print(json.dumps({
            "policies_loaded": loaded,
            "classify_tests": tests,
            "dispatch_registry": dispatch_status,
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
