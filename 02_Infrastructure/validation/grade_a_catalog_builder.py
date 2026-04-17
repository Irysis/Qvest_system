#!/usr/bin/env python3
"""
Grade A Catalog Builder — v53 Sprint 2 S2.15 (Legacy Cleanup)

Scans 04_Research/strategies/*/output*/hurdle_result.json AND
stage_artifacts/s6_judge_*.json for Grade A/A_NOVEL/A_DEF/A_CONDITIONAL records.

Produces 04_Research/grade_a_catalog.json consumed by:
  - qepm/R/blender_scaffold.R (ensemble activation check)
  - .claude/agents/blender.md (Grade A population for ensemble design)
  - governor PG0 gap assessment

Usage: python3 grade_a_catalog_builder.py [--project-dir PATH]
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
from datetime import datetime, timezone

GRADE_A_SET = {"A", "A_NOVEL", "A_DEF", "A_CONDITIONAL"}

RE_STR = re.compile(r"STR_[0-9A-Za-z_]+")


def _load(path: str):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _strategy_id(data: dict, path: str) -> str:
    for key in ("strategy_id", "strategy", "factor_id"):
        v = data.get(key)
        if isinstance(v, str) and v.strip():
            return v.strip()
    m = RE_STR.search(path)
    return m.group(0) if m else os.path.basename(path)


def _pick_grade(data: dict) -> str | None:
    for key in ("grade", "final_grade", "grade_v21"):
        v = data.get(key)
        if isinstance(v, str) and v in GRADE_A_SET:
            return v
    verdict = data.get("verdict") if isinstance(data.get("verdict"), dict) else None
    if verdict:
        v = verdict.get("grade")
        if isinstance(v, str) and v in GRADE_A_SET:
            return v
    return None


def _flat_metric(data: dict, key: str):
    metrics = data.get("metrics")
    if isinstance(metrics, dict) and key in metrics:
        return metrics[key]
    return data.get(key)


def _extract_record(data: dict, path: str, mtime: float) -> dict | None:
    grade = _pick_grade(data)
    if grade is None:
        return None
    sid = _strategy_id(data, path)
    return {
        "strategy_id": sid,
        "grade": grade,
        "grade_v21": data.get("grade_v21"),
        "score": data.get("total_score") or data.get("score"),
        "sharpe": _flat_metric(data, "Sharpe") or _flat_metric(data, "sharpe"),
        "cagr": _flat_metric(data, "CAGR") or _flat_metric(data, "cagr"),
        "mdd": _flat_metric(data, "MDD") or _flat_metric(data, "mdd"),
        "role": data.get("role") or data.get("role_label"),
        "family": data.get("family") or data.get("alpha_family"),
        "novelty_bonus": data.get("novelty_bonus"),
        "source": os.path.relpath(path),
        "source_mtime": datetime.fromtimestamp(mtime, tz=timezone.utc).isoformat(timespec="seconds"),
    }


def build(project_dir: str) -> dict:
    records: dict[str, dict] = {}

    hurdle_paths = glob.glob(
        os.path.join(project_dir, "04_Research", "strategies", "*", "output*", "hurdle_result.json"),
        recursive=False,
    )
    judge_paths = glob.glob(os.path.join(project_dir, "stage_artifacts", "s6_judge_*.json"))

    for p in hurdle_paths + judge_paths:
        data = _load(p)
        if not isinstance(data, dict):
            continue
        mtime = os.path.getmtime(p)
        rec = _extract_record(data, p, mtime)
        if rec is None:
            continue
        sid = rec["strategy_id"]
        prev = records.get(sid)
        if prev is None or prev["source_mtime"] < rec["source_mtime"]:
            records[sid] = rec

    sorted_list = sorted(records.values(), key=lambda r: r["source_mtime"], reverse=True)

    grade_counts: dict[str, int] = {}
    for r in sorted_list:
        grade_counts[r["grade"]] = grade_counts.get(r["grade"], 0) + 1

    return {
        "schema_version": "v53_s2_15",
        "last_updated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "n_strategies": len(sorted_list),
        "grade_counts": grade_counts,
        "strategies": sorted_list,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--project-dir",
        default=os.environ.get("QVEST_PROJECT_DIR")
        or "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
    )
    ap.add_argument("--output", default=None)
    args = ap.parse_args()

    project_dir = args.project_dir
    out_path = args.output or os.path.join(project_dir, "04_Research", "grade_a_catalog.json")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    catalog = build(project_dir)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(catalog, f, indent=2, ensure_ascii=False)

    print(
        f"[grade_a_catalog] {out_path} — {catalog['n_strategies']} strategies "
        f"(grades: {catalog['grade_counts']})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
