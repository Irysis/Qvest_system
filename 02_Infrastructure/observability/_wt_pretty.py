#!/usr/bin/env python3
"""
_wt_pretty.py — v7.1-lite Sprint 2.1 ASCII pretty-printer for WT timeline JSON

Reads timeline JSON (from qvest_observe wt <ID>) on stdin or file path.
Outputs ASCII timeline + cert table + failures + lineage.

Usage:
  qvest_observe wt <WT_ID> | python3 _wt_pretty.py
  python3 _wt_pretty.py --file <timeline.json> [--certs|--failures|--lineage]
"""

import argparse
import json
import sys
from typing import Any


CERT_GLYPH = {
    "ISSUED": "✅",
    "NOT_ISSUED": "❌",
    "ABSENT": "⏸",
    "REVOKED": "🚫",
    "N/A": "⚪",
}


def is_tty() -> bool:
    return sys.stdout.isatty()


def color(s: str, code: str) -> str:
    if not is_tty():
        return s
    return f"\033[{code}m{s}\033[0m"


def red(s: str) -> str: return color(s, "31")
def green(s: str) -> str: return color(s, "32")
def yellow(s: str) -> str: return color(s, "33")
def cyan(s: str) -> str: return color(s, "36")
def dim(s: str) -> str: return color(s, "2")


def render_full(tl: dict) -> None:
    wt_id = tl.get("wt_id", "?")
    phase = tl.get("current_phase", "UNKNOWN")
    wt_type = tl.get("wt_type", "")  # may be in lineage

    header = f"{cyan(wt_id)}  ({wt_type or 'discovery'}, current_phase={yellow(phase)})"
    print(header)

    certs = tl.get("certs") or {}
    lineage = tl.get("artifact_lineage") or []
    failures = tl.get("failures") or []
    retry = tl.get("retry_count", 0)
    n_phases = len(tl.get("phases") or [])

    role_glyph_map = {}
    for cname, cdata in certs.items():
        status = cdata.get("status", "ABSENT")
        glyph = CERT_GLYPH.get(status, "?")
        role_glyph_map[cname] = (glyph, status, cdata.get("reason", ""))

    role_order = [
        ("alpha", "alpha_discovery"),
        ("risk", None),
        ("optimizer", None),
        ("forge", "sr_provenance"),
        ("forge", "forge_package_validated"),
        ("schedule", "schedule_fidelity"),
        ("judge", None),
        ("governor", "governor_concord"),
    ]

    seen = set()
    lines = []
    for role, cert_name in role_order:
        if (role, cert_name) in seen:
            continue
        seen.add((role, cert_name))
        if cert_name and cert_name in role_glyph_map:
            g, s, r = role_glyph_map[cert_name]
            line = f"  ├─ {role:<10} {g} {s:<11} ({cert_name})"
            if r and s != "ISSUED":
                line += f" — {dim(r[:60])}"
            lines.append(line)
        else:
            # role without per-WT cert (risk/optimizer/judge): use lineage presence
            artifact_present = any(
                isinstance(a, dict) and a.get("role") == role
                for a in lineage
            )
            if artifact_present:
                lines.append(f"  ├─ {role:<10} {green('●')} generated")
            else:
                lines.append(f"  ├─ {role:<10} {dim('○')} {dim('absent')}")

    if lines:
        # Replace last ├─ with └─
        lines[-1] = lines[-1].replace("├─", "└─", 1)
        for line in lines:
            print(line)

    print()
    summary_parts = [
        f"Phases: {n_phases}",
        f"Retry: {retry}",
        f"Failures: {len(failures)}",
    ]
    if failures:
        stances = sorted(set(f.get("stance", "?") for f in failures))
        summary_parts.append(f"Codex stance: {', '.join(stances)}")
    print(" | ".join(summary_parts))


def render_certs(tl: dict) -> None:
    certs = tl.get("certs") or {}
    if not certs:
        print("(no cert data)")
        return
    print(f"{'Certificate':<35} {'Status':<12} Reason")
    print("-" * 80)
    for cname, cdata in certs.items():
        status = cdata.get("status", "ABSENT")
        glyph = CERT_GLYPH.get(status, "?")
        reason = cdata.get("reason", "")
        print(f"{glyph} {cname:<33} {status:<12} {reason[:35]}")


def render_failures(tl: dict) -> None:
    failures = tl.get("failures") or []
    if not failures:
        print("(no failures)")
        return
    for i, f in enumerate(failures, 1):
        print(f"#{i} role={f.get('agent_role','?')} stance={red(f.get('stance','?'))}")
        print(f"   concerns: {f.get('critical_concerns_count', 0)} (HIGH={f.get('high_count', 0)})")
        wa = f.get("weakest_assumption", "")
        if wa:
            print(f"   weakest: {wa[:120]}")
        print()


def render_lineage(tl: dict) -> None:
    lineage = tl.get("artifact_lineage") or []
    if not lineage:
        print("(no lineage)")
        return
    print(f"{'Role':<12} {'Artifact':<60} Generated")
    print("-" * 100)
    for a in lineage:
        if not isinstance(a, dict):
            continue
        role = a.get("role", "?")
        path = a.get("artifact_path", "")
        gen = a.get("generated_at", "")
        print(f"{role:<12} {path[:58]:<60} {gen}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", help="timeline JSON file path (otherwise stdin)")
    ap.add_argument("--certs", action="store_true")
    ap.add_argument("--failures", action="store_true")
    ap.add_argument("--lineage", action="store_true")
    args = ap.parse_args()

    if args.file:
        with open(args.file, "r", encoding="utf-8") as f:
            tl = json.load(f)
    else:
        try:
            tl = json.load(sys.stdin)
        except Exception as e:
            print(f"[ERROR] failed to parse stdin JSON: {e}", file=sys.stderr)
            sys.exit(1)

    if args.certs:
        render_certs(tl)
    elif args.failures:
        render_failures(tl)
    elif args.lineage:
        render_lineage(tl)
    else:
        render_full(tl)


if __name__ == "__main__":
    main()
