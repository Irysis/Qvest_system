#!/usr/bin/env python3
"""
_query.py — v7.1-lite Sprint 1.2 In-memory query engine for search_index.jsonl

Loads JSONL → Python list (worst case ~70k rows < 80 MB).
Substring match (UTF-8 casefold) + AND multi-keyword + type/recent filter.
Output: JSON list of {type, title, source_path, timestamp, snippet}.

Usage (called from qvest_search bash entrypoint):
  python3 _query.py <query> [--type <T>] [--recent <Nd|Nh>] [--limit <N>] [--include-examples]
"""

import argparse
import datetime as dt
import json
import os
import sys
from pathlib import Path


def project_root() -> Path:
    env = os.environ.get("CLAUDE_PROJECT_DIR")
    if env and Path(env).is_dir():
        return Path(env)
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / "qepm" / "observability").is_dir():
            return parent
    return here.parent.parent.parent


PROJECT_ROOT = project_root()
INDEX_PATH = PROJECT_ROOT / "qepm" / "observability" / "search_index.jsonl"


def load_index(include_examples: bool = False) -> list[dict]:
    if not INDEX_PATH.exists():
        return []
    rows: list[dict] = []
    with open(INDEX_PATH, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            # Default: skip example-workflow paths and synthetic year 9999 WTs
            # (examples live at 02_Infrastructure/docs/examples/qvest_workflows/
            #  since 2026-07-04; substring matches old root-level examples/ too)
            sp = (row.get("source_path") or "")
            wt_id = (row.get("wt_id") or "")
            if not include_examples:
                if "examples/qvest_workflows" in sp:
                    continue
                if isinstance(wt_id, str) and wt_id.startswith("WT-D9999"):
                    continue
            rows.append(row)
    return rows


def parse_recent(spec: str | None):
    if not spec:
        return None
    try:
        if spec.endswith("h"):
            hours = int(spec[:-1])
            return dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=hours)
        if spec.endswith("d"):
            days = int(spec[:-1])
            return dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days)
    except ValueError:
        return None
    return None


def matches_query(row: dict, query_terms: list[str]) -> bool:
    """AND match — all terms must appear (casefold) in title or body."""
    haystack = (
        (row.get("title") or "") + " " +
        (row.get("body") or "") + " " +
        (row.get("id") or "") + " " +
        (row.get("source_path") or "") + " " +
        " ".join(row.get("tags") or [])
    ).casefold()
    for term in query_terms:
        if term.casefold() not in haystack:
            return False
    return True


def _extract_authority(row: dict) -> str | None:
    body = row.get("body") or ""
    if "\"authority\"" in body:
        try:
            data = json.loads(body)
            v = data.get("authority")
            if v:
                return v
        except Exception:
            pass
    for tag in row.get("tags") or []:
        if isinstance(tag, str) and tag.startswith("authority:"):
            return tag.split(":", 1)[1]
    return None


def _extract_axiom_class(row: dict) -> str | None:
    body = row.get("body") or ""
    if "\"axiom_class\"" in body:
        try:
            data = json.loads(body)
            v = data.get("axiom_class")
            if v:
                return v
        except Exception:
            pass
    return None


def _extract_memory_kind(row: dict) -> str | None:
    body = row.get("body") or ""
    if "\"memory_kind\"" in body:
        try:
            data = json.loads(body)
            v = data.get("memory_kind")
            if v:
                return v
        except Exception:
            pass
    return None


def format_result(row: dict, snippet_len: int = 200) -> dict:
    title = row.get("title") or ""
    body = row.get("body") or ""
    snippet = (body[:snippet_len] + "...") if len(body) > snippet_len else body
    return {
        "id": row.get("id"),
        "type": row.get("type"),
        "title": title,
        "source_path": row.get("source_path"),
        "wt_id": row.get("wt_id"),
        "timestamp": row.get("timestamp"),
        "snippet": snippet.replace("\n", " "),
        "authority": _extract_authority(row),
        "axiom_class": _extract_axiom_class(row),
        "memory_kind": _extract_memory_kind(row),
    }


def parse_ts(ts: str | None):
    if not ts:
        return None
    try:
        return dt.datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("query", nargs="*", help="search terms (AND)")
    ap.add_argument("--type", default=None,
                    help="filter by type (lcode|wt|cert|paper|axiom|axiom_candidate|axiom_deprecated|axiom_review|lesson|evidence_summary|registry|lawbook|critic|governance)")
    ap.add_argument("--authority", default=None,
                    help="filter by authority (low|medium|high|retired|audit)")
    ap.add_argument("--axiom-class", default=None,
                    help="filter by axiom_class (constitutional|process|empirical|methodological)")
    ap.add_argument("--memory-kind", default=None,
                    help="filter by memory_kind (axiom_active|axiom_candidate|axiom_deprecated|lesson|review_log|evidence_summary|regime_validation)")
    ap.add_argument("--recent", default=None, help="recency filter (24h, 7d, 30d)")
    ap.add_argument("--limit", type=int, default=30, help="max results (default 30)")
    ap.add_argument("--include-examples", action="store_true",
                    help="include 02_Infrastructure/docs/examples/qvest_workflows/ + WT-D9999 synthetic")
    args = ap.parse_args()

    if not args.query and not args.type:
        print(json.dumps({"error": "query or --type required"}))
        sys.exit(2)

    rows = load_index(include_examples=args.include_examples)
    if not rows:
        print(json.dumps({
            "warning": f"index empty or missing: {INDEX_PATH}",
            "results": [],
            "count": 0,
        }))
        sys.exit(0)

    since = parse_recent(args.recent)

    matches = []
    for row in rows:
        if args.type and row.get("type") != args.type:
            continue
        if args.query and not matches_query(row, args.query):
            continue
        if args.authority and _extract_authority(row) != args.authority:
            continue
        if args.axiom_class and _extract_axiom_class(row) != args.axiom_class:
            continue
        if args.memory_kind and _extract_memory_kind(row) != args.memory_kind:
            continue
        if since:
            row_ts = parse_ts(row.get("timestamp"))
            if row_ts is None or row_ts.replace(tzinfo=dt.timezone.utc) < since:
                # Without timestamp, exclude when --recent provided
                if row.get("timestamp"):
                    continue
                else:
                    continue
        matches.append(row)

    # Sort: timestamp DESC (None last)
    def sort_key(r):
        t = parse_ts(r.get("timestamp"))
        return (t is None, -(t.timestamp() if t else 0))

    matches.sort(key=sort_key)
    matches = matches[: args.limit]

    out = [format_result(m) for m in matches]
    print(json.dumps({"count": len(out), "results": out}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
