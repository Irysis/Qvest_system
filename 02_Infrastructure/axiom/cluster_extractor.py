#!/usr/bin/env python3
"""
Cluster & Rule Extractor — Sprint 4 AX-P0 Layer 2

L-code corpus를 family/tag/keyword 유사도로 클러스터링 → 조건부 정량 규칙 초안
→ AX candidate JSON 생성.

Input:  .cache/lcode_corpus.json
Output: qepm/memory/axioms/candidates/CAND_<id>.json

Candidate type:
  - empirical : "특정 factor/family/regime에서 alpha/risk 정량 규칙"
  - methodological : "연구 프로세스 규칙"

Clustering strategy:
  1) 같은 family + tag 교집합 ≥ 1 → cluster
  2) lesson_text 키워드 overlap (TF-IDF 간이) ≥ 0.3 → cluster
  3) 같은 strategy_family prefix (예: STR_1631_*) → cluster
  최소 size=2 (독립성 축 확보용)

Rule extraction (초안만 — 5축 검증은 promote.R):
  - Grade 분포: F만이면 "실패 패턴" → empirical (negative axiom 후보)
  - A+F 혼재면 "조건부 alpha 패턴" → empirical
  - tag가 METHODOLOGY / OVERLAY / TIMING / RISK_MGMT 계열이면 methodological
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from itertools import combinations

METHODOLOGY_TAG_KEYWORDS = {
    "OVERLAY", "RISK_MGMT", "TIMING", "DFA", "REBAL", "BLEND", "SYNTHESIS",
    "HYBRID_OVERLAY", "FACTOR_TIMING_VS_RISK_MGMT", "ANCHOR_INFERIOR",
    "SECTOR_NEUTRAL_DILUTION", "IS_OVERFIT", "OOS_COLLAPSE",
    "SCORE_DILUTION", "ALPHA_DECAY_SEVERE",
}


def _load(path: str):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _tokenize(text: str) -> set[str]:
    """Simple Korean+English keyword extractor for overlap scoring."""
    text = text or ""
    # extract 2+ char alnum + Hangul words
    tokens = re.findall(r"[A-Za-z0-9_]{2,}|[\uac00-\ud7a3]{2,}", text)
    # drop short/common
    stop = {"기업", "팩터", "전략", "실험", "결과", "있는", "있다", "없다", "대비", "경우", "the", "and", "for"}
    return {t.lower() for t in tokens if len(t) >= 2 and t.lower() not in stop}


def _similarity(a: dict, b: dict) -> float:
    """Pairwise L-code similarity 0~1."""
    score = 0.0
    # family match (+0.4)
    if a.get("family") and a.get("family") == b.get("family"):
        score += 0.4
    # tag intersection (+0.3 × jaccard)
    ta, tb = set(a.get("tags") or []), set(b.get("tags") or [])
    if ta and tb:
        jac = len(ta & tb) / max(1, len(ta | tb))
        score += 0.3 * jac
    # lesson text token overlap (+0.3 × jaccard)
    la, lb = _tokenize(a.get("lesson_text", "")), _tokenize(b.get("lesson_text", ""))
    if la and lb:
        jac = len(la & lb) / max(1, len(la | lb))
        score += 0.3 * jac
    return score


def cluster_lcodes(lcodes: list[dict], min_sim: float = 0.35, min_size: int = 2) -> list[dict]:
    """Simple transitive closure clustering — pair if sim>=threshold, union."""
    n = len(lcodes)
    parent = list(range(n))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(i, j):
        ri, rj = find(i), find(j)
        if ri != rj:
            parent[ri] = rj

    for i, j in combinations(range(n), 2):
        if _similarity(lcodes[i], lcodes[j]) >= min_sim:
            union(i, j)

    groups: dict[int, list[int]] = {}
    for i in range(n):
        groups.setdefault(find(i), []).append(i)

    clusters: list[dict] = []
    for idx, members in enumerate(groups.values()):
        if len(members) < min_size:
            continue
        cl_lcodes = [lcodes[i] for i in members]
        clusters.append({
            "cluster_index": idx,
            "size": len(cl_lcodes),
            "l_codes": [x["l_code"] for x in cl_lcodes],
            "members": cl_lcodes,
        })
    return clusters


def _classify_type(cluster: dict) -> str:
    """empirical vs methodological."""
    all_tags = set()
    for m in cluster["members"]:
        all_tags.update(m.get("tags") or [])
    meth_hits = len(all_tags & METHODOLOGY_TAG_KEYWORDS)
    # lesson text에 process/method 키워드가 많으면 methodological
    text = " ".join(m.get("lesson_text", "")[:500] for m in cluster["members"])
    text_lower = text.lower()
    meth_text_kw = ["process", "overlay", "리밸", "배분", "allocation",
                     "방법론", "rebalanc", "blending", "timing",
                     "risk management", "risk_mgmt"]
    meth_text_hits = sum(1 for k in meth_text_kw if k in text_lower)
    if meth_hits >= 2 or meth_text_hits >= 3:
        return "methodological"
    return "empirical"


def _polarity(cluster: dict) -> str:
    """Infer axiom polarity from grade distribution."""
    grades = [m.get("grade") for m in cluster["members"]]
    gc = Counter(grades)
    has_a = gc.get("A", 0) >= 1
    only_fail = gc.get("F", 0) + gc.get("C", 0) == len(grades) and not has_a
    if only_fail:
        return "negative"   # "이 조건에서는 실패한다"
    if has_a and (gc.get("F", 0) >= 1 or gc.get("C", 0) >= 1):
        return "conditional"  # "이 조건에서만 성공한다"
    return "positive"  # "이 조건에서 성공한다"


def _draft_statement(cluster: dict, cand_type: str, polarity: str) -> str:
    """Short human-readable statement draft — promoter/human refine 대상."""
    fams = [m.get("family") for m in cluster["members"] if m.get("family")]
    fam = Counter(fams).most_common(1)[0][0] if fams else "unknown"
    all_tags = Counter()
    for m in cluster["members"]:
        all_tags.update(m.get("tags") or [])
    top_tags = [t for t, _ in all_tags.most_common(3)]

    prefix = {"negative": "실패 규칙", "conditional": "조건부 규칙", "positive": "성공 규칙"}[polarity]
    type_str = "실증" if cand_type == "empirical" else "방법론"
    return (
        f"[{type_str} {prefix} 초안] family={fam}, tags={','.join(top_tags)}, "
        f"supporting={len(cluster['members'])}건 L-code. (promote.R 5축 검증에서 범위·메커니즘·OOS 확정 필요)"
    )


def _draft_evidence(cluster: dict) -> dict:
    """Extract draft evidence fields from member L-codes."""
    ids = [m["l_code"] for m in cluster["members"]]
    strategies = list({m["strategy_id"] for m in cluster["members"] if m.get("strategy_id")})
    return {
        "independent_l_codes": len(set(ids)),
        "independent_strategies": len(strategies),
        "strategies": strategies,
        "effect_direction_consistency": None,  # promote.R에서 계산
        "note": "evidence_draft — promote.R 5축 검증에서 hurdle_result/grade_a_catalog 교차검증으로 확정",
    }


def _draft_scope(cluster: dict) -> dict:
    families = Counter(m.get("family") for m in cluster["members"] if m.get("family"))
    return {
        "market": "KR",
        "factor_family": families.most_common(1)[0][0] if families else None,
        "regime": None,     # promote.R에서 r4_regime_payoff로 채움
        "construction_types": None,
    }


def build_candidates(corpus: dict, out_dir: str) -> list[str]:
    lcodes = corpus.get("lcodes", [])
    if not lcodes:
        return []
    clusters = cluster_lcodes(lcodes)
    os.makedirs(out_dir, exist_ok=True)

    today = datetime.now(timezone.utc).strftime("%Y%m%d")
    written: list[str] = []

    for cl in clusters:
        cand_type = _classify_type(cl)
        polarity = _polarity(cl)
        family = Counter(m.get("family") for m in cl["members"]).most_common(1)[0][0]
        cluster_key = f"{family or 'unknown'}_{polarity}_{'_'.join(sorted(cl['l_codes'])[:3])}"
        candidate_id = f"CAND_{today}_{cluster_key}"

        candidate = {
            "schema_version": "v53_ax_p0",
            "candidate_id": candidate_id,
            "type": cand_type,
            "polarity": polarity,
            "statement_draft": _draft_statement(cl, cand_type, polarity),
            "supporting_l_codes": cl["l_codes"],
            "scope_draft": _draft_scope(cl),
            "evidence_draft": _draft_evidence(cl),
            "falsification_draft": {
                "attempts": [],
                "note": "promote.R 5축 검증에서 evidence_summary/ + role_honesty 스캔으로 채움",
            },
            "mechanism_draft": {
                "economic_explanation": None,   # human/LLM-filled pre-promote
                "mechanism_type": "unknown",
                "causal_plausibility": None,
            },
            "oos_validation_draft": {
                "oos_months": None,
                "oos_effect_vs_is": None,
                "note": "promote.R에서 r4_regime_payoff 호출로 확정",
            },
            "cluster_members_count": cl["size"],
            "status": "pending_5axis",
            "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }

        path = os.path.join(out_dir, f"{candidate_id}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(candidate, f, indent=2, ensure_ascii=False)
        written.append(path)

    return written


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--project-dir",
        default=os.environ.get("QVEST_PROJECT_DIR")
        or "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
    )
    ap.add_argument("--corpus", default=None)
    ap.add_argument("--out-dir", default=None)
    args = ap.parse_args()

    corpus_path = args.corpus or os.path.join(args.project_dir, ".cache", "lcode_corpus.json")
    out_dir = args.out_dir or os.path.join(args.project_dir, "qepm", "memory", "axioms", "candidates")

    corpus = _load(corpus_path)
    if not corpus:
        print(f"[cluster_extractor] corpus not found: {corpus_path}", file=sys.stderr)
        return 2

    written = build_candidates(corpus, out_dir)
    print(f"[cluster_extractor] {len(written)} candidate(s) written to {out_dir}")
    for p in written:
        print(f"  - {os.path.basename(p)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
