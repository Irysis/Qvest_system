#!/usr/bin/env python3
"""
Mutation Tracker — v53 Sprint 2 S2.7

Scans stage_artifacts/s5_mutation_*.json and s5_research_slate_*.json to produce
.cache/mutation_tracker.json, which unified_agent_guard.sh consults to block
S5 Forge spawns that fail S5 Rules (mutations>=9, categories>=2, synthesis_tested).

Usage:
    python3 mutation_tracker.py [--project-dir PATH]

Outputs .cache/mutation_tracker.json with schema:
{
  "last_updated": ISO8601,
  "strategies": {
    "<strategy_id>": {
      "mutations_attempted": int,
      "f_category_count": int,
      "categories": [str, ...],
      "synthesis_tested": bool,
      "slate_slots": [str, ...],    # A/B/C/D filled
      "slate_complete": bool,
      "sources": [path, ...],
      "passes_s5_rule": bool        # mutations>=9 && f_category>=2 && synthesis_tested
    }
  }
}
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
from datetime import datetime, timezone

RE_STR = re.compile(r"(STR_\d+[A-Za-z0-9_]*?)(?:_M\d+|_[A-Z]+_[A-Z\d_]+|)?$")


def _load_json(path: str):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _infer_strategy_id(data: dict, path: str) -> str:
    for key in ("strategy_id", "factor_id", "base_strategy"):
        val = data.get(key)
        if val:
            return str(val)
    base = os.path.basename(path).replace(".json", "")
    stripped = re.sub(r"^(s5_mutation_|s5_research_slate_|s5_synthesis_slate_)", "", base)
    return stripped


def _aggregate_mutation_file(data: dict, path: str, bucket: dict) -> None:
    sid = _infer_strategy_id(data, path)
    entry = bucket.setdefault(
        sid,
        {
            "mutations_attempted": 0,
            "f_category_count": 0,
            "categories": [],
            "synthesis_tested": False,
            "slate_slots": [],
            "slate_complete": False,
            "sources": [],
        },
    )
    entry["sources"].append(os.path.relpath(path))

    attempted = data.get("mutations_attempted")
    mutations = data.get("mutations", [])
    if attempted is None and isinstance(mutations, list):
        attempted = len(mutations)
    if isinstance(attempted, int):
        entry["mutations_attempted"] = max(entry["mutations_attempted"], attempted)

    cats_field = data.get("categories")
    cats: set[str] = set(entry["categories"])
    if isinstance(cats_field, dict):
        cats.update(cats_field.keys())
    elif isinstance(cats_field, list):
        cats.update(str(c) for c in cats_field)
    if isinstance(mutations, list):
        for m in mutations:
            if isinstance(m, dict) and m.get("category"):
                cats.add(str(m["category"]))
    entry["categories"] = sorted(cats)

    fcc = data.get("f_category_count")
    if isinstance(fcc, int):
        entry["f_category_count"] = max(entry["f_category_count"], fcc)
    else:
        entry["f_category_count"] = max(entry["f_category_count"], len(entry["categories"]))

    if data.get("synthesis_tested") is True:
        entry["synthesis_tested"] = True


def _aggregate_slate_file(data: dict, path: str, bucket: dict) -> None:
    sid = _infer_strategy_id(data, path)
    entry = bucket.setdefault(
        sid,
        {
            "mutations_attempted": 0,
            "f_category_count": 0,
            "categories": [],
            "synthesis_tested": False,
            "slate_slots": [],
            "slate_complete": False,
            "sources": [],
        },
    )
    entry["sources"].append(os.path.relpath(path))

    slate = data.get("research_slate") or data.get("slots") or {}
    if isinstance(slate, dict):
        slots = sorted(set(list(entry["slate_slots"]) + list(slate.keys())))
        entry["slate_slots"] = slots
        required = {"A", "B", "C", "D"}
        entry["slate_complete"] = required.issubset(set(slots))


def scan(project_dir: str) -> dict:
    arts = os.path.join(project_dir, "stage_artifacts")
    bucket: dict = {}

    for p in glob.glob(os.path.join(arts, "s5_mutation_*.json")):
        data = _load_json(p)
        if isinstance(data, dict):
            _aggregate_mutation_file(data, p, bucket)

    for p in glob.glob(os.path.join(arts, "s5_research_slate_*.json")) + glob.glob(
        os.path.join(arts, "s5_synthesis_slate_*.json")
    ):
        data = _load_json(p)
        if isinstance(data, dict):
            _aggregate_slate_file(data, p, bucket)

    for entry in bucket.values():
        entry["passes_s5_rule"] = bool(
            entry["mutations_attempted"] >= 9
            and entry["f_category_count"] >= 2
            and entry["synthesis_tested"]
        )

    return {
        "last_updated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "strategies": bucket,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--project-dir",
        default=os.environ.get("QVEST_PROJECT_DIR")
        or "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
    )
    ap.add_argument(
        "--output",
        default=None,
        help="Override output path (default: <project>/.cache/mutation_tracker.json)",
    )
    args = ap.parse_args()

    project_dir = args.project_dir
    output_path = args.output or os.path.join(project_dir, ".cache", "mutation_tracker.json")

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    tracker = scan(project_dir)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(tracker, f, indent=2, ensure_ascii=False)

    print(
        f"[MutationTracker] {output_path} updated — {len(tracker['strategies'])} strategies"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
