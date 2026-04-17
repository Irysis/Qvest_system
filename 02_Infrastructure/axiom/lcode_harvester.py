#!/usr/bin/env python3
"""
L-code Harvester — Sprint 4 AX-P0 Layer 1

퀀트 리서치 산출물(L-code)을 유일한 primary 원천으로 삼아 normalized corpus를
생성한다. Axiom 엔진의 입력 단.

Inputs:
  - stage_artifacts/l_code_*.json (primary)
  - qepm/memory/axioms/active/AX-*.json (승격된 L-code 역링크 확인용)

Output:
  .cache/lcode_corpus.json

Schema:
  {
    "schema_version": "v53_ax_p0",
    "last_updated": ISO8601,
    "n_lcodes": int,
    "lcodes": [
      {
        "l_code": "L-XXX",
        "strategy_id": str,
        "lesson_text": str,
        "tags": [str, ...],
        "family": str | null,      (inferred from strategy_id/tags)
        "grade": "A|B|C|F",
        "core_reference": str,
        "source_file": str,        (relative path)
        "mtime": ISO8601,
        "promoted_to_axiom": str | null  (AX-XXX if already promoted)
      }
    ]
  }

Usage: python3 lcode_harvester.py [--project-dir PATH]
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
from datetime import datetime, timezone

RE_LCODE = re.compile(r"L-\d+")
RE_STR = re.compile(r"STR_\d+[A-Za-z0-9_]*")

FAMILY_KEYWORDS = {
    "quality_earnings": ["Q07", "Q03", "earnings_stability", "accrual_quality", "piotroski"],
    "quality_profitability": ["Q01", "GPA", "profitability", "CBPQ", "cash_profitability", "GSCD"],
    "value": ["EP", "BP", "value_trap", "BCSNA", "sector_neutral_accrual"],
    "defense": ["D29", "D25", "D04", "lowbeta", "defense"],
    "momentum": ["M01", "IndMom", "momentum", "factor_mom"],
    "ml_complexity": ["CVaR_LP", "XGB", "ML", "HRP", "FM", "factor_vol"],
    "behavioral": ["contrarian", "flow", "ret_autocorr", "atypicality"],
    "consensus": ["C19", "consensus", "analyst"],
}


def _load(path: str):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _infer_family(strategy_id: str, tags: list[str], lesson_text: str) -> str | None:
    text = (strategy_id or "") + " " + " ".join(tags or []) + " " + (lesson_text or "")[:500]
    text_lower = text.lower()
    best = None
    best_hits = 0
    for fam, kws in FAMILY_KEYWORDS.items():
        hits = sum(1 for kw in kws if kw.lower() in text_lower)
        if hits > best_hits:
            best_hits = hits
            best = fam
    return best


def _check_promoted(l_code: str, project_dir: str) -> str | None:
    """Scan active axioms for supporting_l_codes containing this L-code."""
    active_dir = os.path.join(project_dir, "qepm", "memory", "axioms", "active")
    if not os.path.isdir(active_dir):
        return None
    for ax_path in glob.glob(os.path.join(active_dir, "AX-*.json")):
        ax = _load(ax_path)
        if not isinstance(ax, dict):
            continue
        supporting = ax.get("supporting_l_codes", [])
        if isinstance(supporting, list) and l_code in supporting:
            return ax.get("axiom_id") or os.path.basename(ax_path).replace(".json", "")
    return None


def harvest(project_dir: str) -> dict:
    arts = os.path.join(project_dir, "stage_artifacts")
    lcodes: list[dict] = []

    for p in sorted(glob.glob(os.path.join(arts, "l_code_*.json"))):
        data = _load(p)
        if not isinstance(data, dict):
            continue
        l_code = data.get("l_code")
        if not l_code:
            # try to extract from filename
            m = RE_LCODE.search(os.path.basename(p))
            l_code = m.group(0) if m else None
        if not l_code:
            continue

        strategy_id = data.get("strategy_id", "")
        tags = data.get("tags", []) or []
        lesson_text = data.get("lesson_text", "") or ""
        family = _infer_family(strategy_id, tags, lesson_text)
        promoted = _check_promoted(l_code, project_dir)

        lcodes.append({
            "l_code": l_code,
            "strategy_id": strategy_id,
            "lesson_text": lesson_text,
            "tags": tags,
            "family": family,
            "grade": data.get("grade"),
            "core_reference": data.get("core_reference", ""),
            "source_file": os.path.relpath(p, project_dir),
            "mtime": datetime.fromtimestamp(os.path.getmtime(p), tz=timezone.utc).isoformat(timespec="seconds"),
            "promoted_to_axiom": promoted,
        })

    lcodes.sort(key=lambda x: x["l_code"])

    return {
        "schema_version": "v53_ax_p0",
        "last_updated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "n_lcodes": len(lcodes),
        "family_distribution": _family_dist(lcodes),
        "grade_distribution": _grade_dist(lcodes),
        "n_promoted": sum(1 for x in lcodes if x["promoted_to_axiom"]),
        "lcodes": lcodes,
    }


def _family_dist(lcodes: list[dict]) -> dict[str, int]:
    out: dict[str, int] = {}
    for x in lcodes:
        fam = x.get("family") or "unknown"
        out[fam] = out.get(fam, 0) + 1
    return dict(sorted(out.items(), key=lambda kv: -kv[1]))


def _grade_dist(lcodes: list[dict]) -> dict[str, int]:
    out: dict[str, int] = {}
    for x in lcodes:
        g = x.get("grade") or "unknown"
        out[g] = out.get(g, 0) + 1
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--project-dir",
        default=os.environ.get("QVEST_PROJECT_DIR")
        or "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
    )
    ap.add_argument("--output", default=None)
    args = ap.parse_args()

    out = args.output or os.path.join(args.project_dir, ".cache", "lcode_corpus.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)

    corpus = harvest(args.project_dir)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(corpus, f, indent=2, ensure_ascii=False)

    print(
        f"[lcode_harvester] {out} — n={corpus['n_lcodes']} "
        f"promoted={corpus['n_promoted']} "
        f"families={corpus['family_distribution']} "
        f"grades={corpus['grade_distribution']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
