#!/usr/bin/env python3
"""
Backlog Bucket Monitor — v53 Sprint 3 P3-B

Classifies recent S0 hypotheses (stage_artifacts/s0_record_*.json) into qepm §1
4-bucket policy and reports distribution vs target ratios.

Target (qepm §1):
  Exploit   50%  (existing Grade A 강화)
  Stabilize 20%  (near-miss 전략 강화)
  Explore   20%  (새로운 factor family)
  Diagnose  10%  (failure 원인 분석)

Classification heuristic (in priority order):
  1) explicit bucket field in s0_record
  2) revision_from → Exploit (기존 전략 기반)
  3) economic_family in existing Grade A families → Stabilize
  4) diagnose/postmortem/failure in hypothesis → Diagnose
  5) else → Explore

Output: .cache/backlog_buckets.json

Usage: python3 backlog_bucket_monitor.py [--days 30]
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
from datetime import datetime, timezone

TARGET = {"exploit": 0.50, "stabilize": 0.20, "explore": 0.20, "diagnose": 0.10}
TOLERANCE = 0.10


def _load(path: str):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _classify(rec: dict, grade_a_families: set[str]) -> str:
    explicit = (rec.get("bucket") or rec.get("backlog_bucket") or "").lower()
    if explicit in TARGET:
        return explicit

    hyp = str(rec.get("hypothesis", "")) + " " + str(rec.get("economic_rationale", ""))
    hyp_lc = hyp.lower()
    family = str(rec.get("economic_family") or rec.get("family") or "").lower()
    revision_from = str(rec.get("revision_from", ""))
    expected_role = (rec.get("expected_role") or "").lower()

    if re.search(r"diagnos|postmortem|post-mortem|failure.*analys|why.*fail|실패.*원인", hyp_lc):
        return "diagnose"
    if re.search(r"\bSTR_\d", revision_from):
        return "exploit"
    for fa in grade_a_families:
        if fa and fa.lower() in family:
            return "stabilize"
    if expected_role in ("defense",) and "defense" not in " ".join(grade_a_families).lower():
        return "explore"
    return "explore"


def _collect_grade_a_families(project_dir: str) -> set[str]:
    catalog_path = os.path.join(project_dir, "04_Research", "grade_a_catalog.json")
    fams: set[str] = set()
    catalog = _load(catalog_path)
    if isinstance(catalog, dict):
        for s in catalog.get("strategies", []):
            fam = s.get("family") or s.get("role") or ""
            if fam:
                fams.add(str(fam))
    return fams


def build(project_dir: str, days: int = 30) -> dict:
    now = datetime.now(timezone.utc).timestamp()
    cutoff = now - days * 86400
    arts = os.path.join(project_dir, "stage_artifacts")
    grade_a_fams = _collect_grade_a_families(project_dir)

    counts = {k: 0 for k in TARGET}
    classified: list[dict] = []

    for p in glob.glob(os.path.join(arts, "s0_record_*.json")):
        if os.path.getmtime(p) < cutoff:
            continue
        rec = _load(p)
        if not isinstance(rec, dict):
            continue
        bucket = _classify(rec, grade_a_fams)
        counts[bucket] += 1
        classified.append({
            "file": os.path.relpath(p),
            "factor_id": rec.get("factor_id") or rec.get("strategy_id"),
            "bucket": bucket,
            "family": rec.get("economic_family") or rec.get("family"),
            "expected_role": rec.get("expected_role"),
            "mtime": datetime.fromtimestamp(os.path.getmtime(p), tz=timezone.utc).isoformat(timespec="seconds"),
        })

    total = sum(counts.values()) or 1
    ratios = {k: counts[k] / total for k in TARGET}

    warnings: list[str] = []
    for b, tgt in TARGET.items():
        delta = ratios[b] - tgt
        if abs(delta) > TOLERANCE:
            direction = "초과" if delta > 0 else "미달"
            warnings.append(
                f"{b}: {ratios[b]*100:.1f}% vs 목표 {tgt*100:.0f}% ({direction} {abs(delta)*100:.1f}%p)"
            )

    return {
        "schema_version": "v53_p3b",
        "last_updated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "window_days": days,
        "n_s0_records": total if sum(counts.values()) > 0 else 0,
        "counts": counts,
        "ratios": {k: round(v, 3) for k, v in ratios.items()},
        "target": TARGET,
        "tolerance": TOLERANCE,
        "imbalance_warnings": warnings,
        "grade_a_families": sorted(grade_a_fams),
        "entries": classified,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project-dir",
        default=os.environ.get("QVEST_PROJECT_DIR")
        or "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--output", default=None)
    args = ap.parse_args()

    out = args.output or os.path.join(args.project_dir, ".cache", "backlog_buckets.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    data = build(args.project_dir, args.days)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print(
        f"[backlog_buckets] {out} — n={data['n_s0_records']} "
        f"ratios={data['ratios']} warnings={len(data['imbalance_warnings'])}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
