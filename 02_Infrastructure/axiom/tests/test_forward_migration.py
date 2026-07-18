#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Regression test — build_distilled forward-migration (2026-07-18 엔진-갭 수리).

Covers: consolidate (grown key has pending dup), rekey (no card at grown key),
multi-ancestor flag (no lossy auto-merge), polarity-mismatch guard, idempotency,
and unchanged exact-key draft update. Run: QVEST_PY test_forward_migration.py
"""
import os, sys, json, glob, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))  # 02_Infrastructure/axiom
import cluster_extractor as ce  # noqa: E402

CK = ce._cluster_key
_fail = []
def check(cond, msg):
    print(("  PASS" if cond else "  FAIL") + f" — {msg}")
    if not cond:
        _fail.append(msg)

def wdist(dd, dist_id, members, status, mode, pol, refined=None):
    d = {
        "schema_version": "distilled_v1", "dist_id": dist_id,
        "cluster_key": CK(members), "candidate_id": f"CAND_seed_{dist_id}",
        "status": status, "statement_refined": refined,
        "retry_condition": ("retry:%s" % dist_id) if refined else None,
        "refined_at": "2026-07-01T00:00:00+0900" if refined else None,
        "refined_by": "dohoon" if refined else None,
        "approved_at": "2026-07-01T00:00:00+0900" if refined else None,
        "approved_by": "dohoon" if refined else None,
        "frontier": ["frontier-%s" % dist_id] if refined else [],
        "live_trigger": [], "expiry": "2026-10-01",
        "promoted_to_axiom": None, "created_at": "2026-07-01T00:00:00+00:00",
        "updated_at": "2026-07-01T00:00:00+00:00",
        "research_mode": mode, "polarity": pol, "type": "empirical",
        "metric_type": "backtested", "supporting_l_codes": list(members),
        "cluster_members_count": len(members),
        "scope_draft": {"market": "KR", "factor_family": "test"},
    }
    with open(os.path.join(dd, dist_id + ".json"), "w", encoding="utf-8") as fh:
        json.dump(d, fh, indent=2, ensure_ascii=False)

def wcand(cd, tag, members, mode, pol):
    c = {"candidate_id": "CAND_%s" % tag, "research_mode": mode, "polarity": pol,
         "type": "empirical", "metric_type": "backtested",
         "statement_draft": "[draft] %s" % tag, "supporting_l_codes": list(members),
         "cluster_members_count": len(members),
         "scope_draft": {"market": "KR", "factor_family": "test"}}
    with open(os.path.join(cd, "CAND_%s.json" % tag), "w", encoding="utf-8") as fh:
        json.dump(c, fh, indent=2, ensure_ascii=False)

def load(dd, dist_id):
    with open(os.path.join(dd, dist_id + ".json"), encoding="utf-8") as fh:
        return json.load(fh)

def find_by_members(dd, members):
    key = CK(members)
    for f in glob.glob(os.path.join(dd, "DIST-*.json")):
        d = json.load(open(f, encoding="utf-8"))
        if d.get("cluster_key") == key:
            return d
    return None

def run(tmp):
    cd = os.path.join(tmp, "cand"); dd = os.path.join(tmp, "dist")
    os.makedirs(cd); os.makedirs(dd)
    M = "test_mode"
    # (a) CONSOLIDATE: refined R{a1,a2} + pending T{a1,a2,a3} + CAND{a1,a2,a3}
    wdist(dd, "DIST-XX-001", ["a1", "a2"], "distilled", M, "conditional", refined="APPROVED-A")
    wdist(dd, "DIST-XX-002", ["a1", "a2", "a3"], "pending_5axis", M, "conditional")
    wcand(cd, "cons", ["a1", "a2", "a3"], M, "conditional")
    # (b) REKEY: refined R{d1,d2}, no card at {d1,d2,d3}, CAND{d1,d2,d3}
    wdist(dd, "DIST-XX-003", ["d1", "d2"], "distilled", M, "negative", refined="APPROVED-D")
    wcand(cd, "rekey", ["d1", "d2", "d3"], M, "negative")
    # (c) MULTI-ANCESTOR: refined {g1,g2} + refined {g1,g3} + CAND{g1,g2,g3} (both strict-majority subsets)
    wdist(dd, "DIST-XX-004", ["g1", "g2"], "distilled", M, "negative", refined="APPROVED-G1")
    wdist(dd, "DIST-XX-005", ["g1", "g3"], "distilled", M, "negative", refined="APPROVED-G2")
    wcand(cd, "multi", ["g1", "g2", "g3"], M, "negative")
    # (d) POLARITY MISMATCH: refined {k1,k2} negative + CAND{k1,k2,k3} positive
    wdist(dd, "DIST-XX-006", ["k1", "k2"], "distilled", M, "negative", refined="APPROVED-K")
    wcand(cd, "polmis", ["k1", "k2", "k3"], M, "positive")
    # (f) EXACT-KEY baseline: pending {x1,x2} + CAND{x1,x2} (same set)
    wdist(dd, "DIST-XX-007", ["x1", "x2"], "pending_5axis", M, "negative")
    wcand(cd, "exact", ["x1", "x2"], M, "negative")
    # (g) LOW-JACCARD guard: refined {p1,p2} + CAND{p1..p5} (2 of 5 = minority → absorption, not growth)
    wdist(dd, "DIST-XX-008", ["p1", "p2"], "distilled", M, "conditional", refined="APPROVED-P")
    wcand(cd, "lowjac", ["p1", "p2", "p3", "p4", "p5"], M, "conditional")

    idx = os.path.join(tmp, "idx.json")
    ce.build_distilled(cd, dd, idx)

    print("\n[a] CONSOLIDATE")
    t = load(dd, "DIST-XX-002"); r = load(dd, "DIST-XX-001")
    check(t["status"] == "distilled", "pending T -> distilled")
    check(t.get("statement_refined") == "APPROVED-A", "T inherited approved statement")
    check(t.get("migrated_from") == "DIST-XX-001", "T.migrated_from = R")
    check(t.get("frontier") == ["frontier-DIST-XX-001"], "T inherited frontier")
    check(sorted(t.get("supporting_l_codes")) == ["a1", "a2", "a3"], "T members = grown set (draft update)")
    check(r["status"] == "expired", "ancestor R -> expired")
    check(r.get("migrated_to") == "DIST-XX-002", "R.migrated_to = T")

    print("\n[b] REKEY")
    r2 = load(dd, "DIST-XX-003")
    check(r2["status"] == "distilled", "R2 stays distilled")
    check(r2.get("statement_refined") == "APPROVED-D", "R2 keeps approved statement")
    check(r2.get("cluster_key") == CK(["d1", "d2", "d3"]), "R2 rekeyed to grown key")
    check(r2.get("migrated_from_key") == CK(["d1", "d2"]), "R2.migrated_from_key = old key")
    # no NEW pending card for {d1,d2,d3}; only R2 carries it
    all_d = [json.load(open(f, encoding="utf-8")) for f in glob.glob(os.path.join(dd, "DIST-*.json"))]
    n_dkey = sum(1 for d in all_d if d.get("cluster_key") == CK(["d1", "d2", "d3"]))
    check(n_dkey == 1, "exactly one card at grown key (no duplicate pending)")

    print("\n[c] MULTI-ANCESTOR (flagged, not migrated)")
    m1 = load(dd, "DIST-XX-004"); m2 = load(dd, "DIST-XX-005")
    check(m1["status"] == "distilled" and m2["status"] == "distilled", "both ancestors stay distilled (no auto-merge)")
    newp = find_by_members(dd, ["g1", "g2", "g3"])
    check(newp is not None and newp["status"] == "pending_5axis", "grown cluster -> new pending (normal path)")

    print("\n[g] LOW-JACCARD guard (absorption not migrated)")
    r7 = load(dd, "DIST-XX-008")
    check(r7["status"] == "distilled" and r7.get("cluster_key") == CK(["p1", "p2"]),
          "R7 unchanged (minority-of-bigger cluster not migrated)")
    pj = find_by_members(dd, ["p1", "p2", "p3", "p4", "p5"])
    check(pj is not None and pj["status"] == "pending_5axis", "absorbing cluster -> new pending (no scope creep)")

    print("\n[d] POLARITY MISMATCH (guarded)")
    r5 = load(dd, "DIST-XX-006")
    check(r5["status"] == "distilled" and r5.get("cluster_key") == CK(["k1", "k2"]), "R5 unchanged (neg not merged into pos)")
    pnew = find_by_members(dd, ["k1", "k2", "k3"])
    check(pnew is not None and pnew["status"] == "pending_5axis", "positive CAND -> new pending")

    print("\n[f] EXACT-KEY baseline")
    xk = load(dd, "DIST-XX-007")
    check(xk["status"] == "pending_5axis", "exact-key pending stays pending (no spurious migration)")

    print("\n[e] IDEMPOTENCY (second run = no re-migration; stable fields unchanged, updated_at may bump)")
    r2_before = load(dd, "DIST-XX-003").get("cluster_key")
    n_dist_before = len(glob.glob(os.path.join(dd, "DIST-*.json")))
    ce.build_distilled(cd, dd, idx)
    t2 = load(dd, "DIST-XX-002")
    check(t2["status"] == "distilled" and t2.get("statement_refined") == "APPROVED-A"
          and t2.get("migrated_from") == "DIST-XX-001", "consolidated T stable on rerun")
    check(load(dd, "DIST-XX-001")["status"] == "expired", "expired ancestor stays expired")
    check(load(dd, "DIST-XX-003").get("cluster_key") == r2_before, "rekeyed card stable (no re-migration)")
    check(len(glob.glob(os.path.join(dd, "DIST-*.json"))) == n_dist_before, "no new cards spawned on rerun")

if __name__ == "__main__":
    tmp = tempfile.mkdtemp(prefix="fwdmig_")
    try:
        run(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("\n" + ("ALL PASS" if not _fail else f"FAILURES: {len(_fail)}\n  - " + "\n  - ".join(_fail)))
    sys.exit(1 if _fail else 0)
