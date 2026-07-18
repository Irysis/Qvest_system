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
import glob
import hashlib
import json
import os
import re
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone
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


# v2 (2026-07-04): grade 정규화 alias — corpus가 이미 정규화(A/B/C/F)돼 있지만,
# 구 corpus/직접 호출 back-compat용 로컬 정규화 (lcode_harvester._DEFAULT_GRADE_MAP 축약판).
_GRADE_NORM = {
    "A": "A", "A_NOVEL": "A", "A_DEF": "A", "A_CONDITIONAL": "A",
    "A_CONDITIONAL_REAFFIRMED": "A", "B": "B", "B_ARCHIVE": "B",
    "C": "C", "F": "F", "REJECT": "F",
}


def _polarity(cluster: dict) -> str:
    """Infer axiom polarity from grade distribution.

    v2 수리 (2026-07-04, 비표준 grade 정규화 왜곡): 구 구현은 비표준 grade
    (REJECT/PROCESS_RULE/... 23종)가 A/C/F 어느 쪽에도 안 걸려 클러스터가
    'positive'로 오분류되는 왜곡. → ① grade 정규화(REJECT→F 등) ② record_type ≠
    performance(process/infra/summary) 멤버는 성과 증거가 아니므로 polarity 집계 제외
    ③ 성과 grade가 하나도 없으면 'unknown' (positive 오귀속 금지).

    v3 수리 (2026-07-18 도훈 mandate, default-positive 폴백 왜곡): A(검증된 성공)가
    없고 전부-실패도 아닌 grade 혼재(예: B/B/C)를 'positive'로 폴백하던 결함.
    유령 카드(alpha_research quality_profitability_positive, grades C/B/B)의
    오귀속 근본 원인 — B(archive)/C(marginal)뿐이면 성공 근거가 없다.
    → 'positive'는 A 존재+실패 0에서만. 나머지 graded-혼재 = 'mixed'(방향 불명).
    (W29 /cleaner task_07f3ac0e — DIST-AR-022/016 오귀속의 label 계열: substring
     오탐 'FQ011'→'q01'→quality_profitability로 family-접착된 3건이 A 부재인데도
     'positive'로 라벨되던 것을 'mixed'로 교정 + 아래 _is_spurious_family_only disband.)
    """
    grades = []
    for m in cluster["members"]:
        if (m.get("record_type") or "performance") != "performance":
            continue
        g = _GRADE_NORM.get(str(m.get("grade") or ""))
        if g:
            grades.append(g)
    if not grades:
        return "unknown"  # 성과 증거 無 — positive 폴백 금지 (구 왜곡 수리)
    gc = Counter(grades)
    has_a = gc.get("A", 0) >= 1
    n_fail = gc.get("F", 0) + gc.get("C", 0)
    if n_fail == len(grades) and not has_a:
        return "negative"   # 모든 성과 grade가 실패(F/C) — "이 조건에서는 실패한다"
    if has_a and n_fail >= 1:
        return "conditional"  # 성공(A)+실패 혼재 — "이 조건에서만 성공한다"
    if has_a:
        return "positive"   # 검증된 성공(A) 존재 + 실패 0 — "이 조건에서 성공한다"
    # graded이나 A 부재 + 전부-실패도 아님(B/B/C 등): 근거 없는 positive 금지 → mixed.
    return "mixed"  # 방향 불명 — promote.R/human 판정 대상 (v3, 도훈 2026-07-18)


# ── 유령 클러스터 방지 + family 이질 판별 (2026-07-18 도훈 mandate) ──────────
# 근본 원인(실측): _similarity에서 family 일치(+0.4)만으로 min_sim(0.35)을 넘겨,
# tag/lesson 공통성이 0인 이질 L-code가 'family 버킷'만으로 병합됨
# (유령 3건 pairwise tag_jac=0.000, nonfam<0.016). verdict 코히런스(polarity)와
# family 외 코로보레이션(tag/lesson)로 판별해 disband → 멤버는 singleton으로 보존.
_SPURIOUS_NONFAM_FLOOR = 0.05   # family 외(tag+lesson) 유사도 하한.
#   보정근거(corpus 315 L-code 실측): 유령 클러스터 max_nonfam=0.0158 vs
#   잔존 mixed 클러스터 min 0.0949 — 6× 분리마진. coherent(neg/cond/pos)는
#   polarity 조건에서 면제되므로 이 floor는 'mixed'(방향불명)에만 적용된다.


def _pair_nonfamily_sim(a: dict, b: dict) -> float:
    """_similarity의 family 외 성분(tag jaccard + lesson jaccard, 각 ×0.3)."""
    ta, tb = set(a.get("tags") or []), set(b.get("tags") or [])
    tj = (len(ta & tb) / max(1, len(ta | tb))) if (ta and tb) else 0.0
    la, lb = _tokenize(a.get("lesson_text", "")), _tokenize(b.get("lesson_text", ""))
    xj = (len(la & lb) / max(1, len(la | lb))) if (la and lb) else 0.0
    return 0.3 * tj + 0.3 * xj


def _max_nonfamily_sim(cluster: dict) -> float:
    best = 0.0
    for a, b in combinations(cluster["members"], 2):
        best = max(best, _pair_nonfamily_sim(a, b))
    return best


def _is_spurious_family_only(cluster: dict) -> bool:
    """family 버킷만으로 묶인 방향-불명 클러스터인가 (병합 자체가 오류).

    disband 조건 (둘 다 충족):
      1) polarity == 'mixed' — coherent verdict(negative/conditional/positive)가
         아님 = '이 family는 X한다'는 공통 결론이 없음.
      2) max_nonfamily_sim < floor — 어떤 멤버쌍도 tag/lesson 공통성이 없음
         = family 라벨 외 결합 근거 부재.
    coherent negative(전부-실패)는 1)에서 면제 — distinct construction 다수의
    실패는 오히려 강한 독립 증거이므로 유지(legit L-133/134/139/140 카드).
    disband 시 build_candidates가 멤버를 singleton 경로로 흘려 지식 보존.
    """
    if len(cluster["members"]) < 2:
        return False
    if _polarity(cluster) != "mixed":
        return False
    return _max_nonfamily_sim(cluster) < _SPURIOUS_NONFAM_FLOOR


def _dominant_family(cluster: dict):
    """멤버 factor_family의 엄격 과반(>50%)만 대표. 이질(과반 없음)이면 'mixed'.

    (2026-07-18 도훈 mandate dir#1) 종전 Counter.most_common(1)[0][0]은 2:1:1 등
    과반 없는 split도 top을 무근거 대표로 삼고, 전원 null이면 IndexError crash.
    엄격 과반 없으면 'mixed', 유효 family 없으면 None.
    """
    fams = [m.get("family") for m in cluster["members"] if m.get("family")]
    if not fams:
        return None
    top, n = Counter(fams).most_common(1)[0]
    return top if n * 2 > len(fams) else "mixed"


def _draft_statement(cluster: dict, cand_type: str, polarity: str) -> str:
    """Short human-readable statement draft — promoter/human refine 대상."""
    fams = [m.get("family") for m in cluster["members"] if m.get("family")]
    fam = Counter(fams).most_common(1)[0][0] if fams else "unknown"
    all_tags = Counter()
    for m in cluster["members"]:
        all_tags.update(m.get("tags") or [])
    top_tags = [t for t, _ in all_tags.most_common(3)]

    prefix = {"negative": "실패 규칙", "conditional": "조건부 규칙",
              "positive": "성공 규칙", "mixed": "혼재(방향불명) 규칙"}.get(
                  polarity, "규칙(성과증거 미분류)")
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
    return {
        "market": "KR",
        "factor_family": _dominant_family(cluster),  # 엄격 과반만 — 이질 시 'mixed'
        "regime": None,     # promote.R에서 r4_regime_payoff로 채움
        "construction_types": None,
    }


def _independence(cluster: dict) -> dict:
    """r7 Independence 축: distinct construction/signature 집계 (같은 construction = 상관 1건)."""
    sigs, constructions, metric_types = set(), set(), set()
    for m in cluster["members"]:
        ct = m.get("construction_type") or "unknown"
        constructions.add(ct)
        metric_types.add(m.get("metric_type") or "estimated")
        sigs.add((m.get("research_mode"), m.get("metric_type"), m.get("family"), ct))
    return {
        "n_eff_signatures": len(sigs),
        "independent_constructions": len(constructions),
        "constructions": sorted(constructions),
        "metric_types": sorted(metric_types),
    }


def _cluster_metric_type(cluster: dict) -> str:
    """INV-1: 멤버 metric_type 집계. 하나라도 proxy면 proxy, 전부 backtested여야 backtested."""
    mts = set(m.get("metric_type") or "estimated" for m in cluster["members"])
    if mts == {"backtested"}:
        return "backtested"
    if "proxy" in mts:
        return "proxy"
    return "estimated"


# ── v8.1 트랙D: L-code 실값 → draft 매핑 (없으면 빈값 유지 — 가짜 데이터 생성 금지) ──

_MECHANISM_TYPE_KEYWORDS = {
    # r7 Mechanism 축 type 추론용 (mechanism_hypothesis 텍스트 키워드 — heuristic, promote.R에서 재검증)
    "behavioral": ["과잉반응", "과소반응", "행동", "군집", "심리", "주목", "overreaction",
                   "underreaction", "behavioral", "lottery", "복권", "anchoring"],
    "risk_premium": ["리스크 프리미엄", "위험 프리미엄", "위험 보상", "베타", "변동성 보상",
                     "risk premium", "tail risk", "꼬리위험", "꼬리 위험"],
    "friction": ["거래비용", "회전율", "유동성", "마찰", "비용 소진", "비용이 알파",
                 "turnover", "liquidity", "cost", "슬리피지"],
    "structural": ["시장구조", "한국 시장", "공매도", "롱온리", "long-only", "구조적",
                   "제도", "structural", "동반급락", "mdd"],
    "information": ["정보", "공시", "실적", "애널리스트", "earnings", "information", "pead", "수급"],
}


def _draft_mechanism(cluster: dict) -> dict:
    """멤버 mechanism_hypothesis 실값 → mechanism_draft. 값 없으면 기존 빈 draft 유지."""
    hyps = []
    for m in cluster["members"]:
        v = m.get("mechanism_hypothesis")
        if v in (None, "", [], {}):
            continue
        # 일부 구 L-code는 dict/list 구조 — Python repr 오염 방지 위해 compact JSON으로 보존
        h = v.strip() if isinstance(v, str) else json.dumps(v, ensure_ascii=False)
        if h:
            hyps.append(h)
    if not hyps:
        return {"economic_explanation": None, "mechanism_type": "unknown",
                "causal_plausibility": None}
    rep = max(hyps, key=len)  # 가장 구체적(긴) 가설을 대표로
    expl = rep if len(hyps) == 1 else f"{rep} (멤버 가설 {len(hyps)}건 — promote.R에서 일치성 재검증)"
    text = " ".join(hyps).lower()
    mtype, best_hits = "unknown", 0
    for t, kws in _MECHANISM_TYPE_KEYWORDS.items():
        hits = sum(1 for k in kws if k.lower() in text)
        if hits > best_hits:
            best_hits, mtype = hits, t
    return {"economic_explanation": expl, "mechanism_type": mtype,
            "causal_plausibility": None}  # plausibility 판정은 promote.R/human — 자동 생성 금지


def _median(xs: list[float]) -> float:
    xs = sorted(xs)
    n = len(xs)
    return xs[n // 2] if n % 2 else (xs[n // 2 - 1] + xs[n // 2]) / 2


def _draft_oos(cluster: dict) -> dict:
    """멤버 oos_retention(IS65/OOS35 SR retention) 실값 median → oos_validation_draft.

    oos_months: 하드코딩 None → L-code 실값(oos_months 필드) median 매핑 (2026-07-03 수리).
    corpus 실측 survey(2026-07-03): oos_retention 651건 보유 / oos_months 0건 —
    실값이 없는 멤버뿐이면 종전대로 None 유지(추정 생성 금지, External 축은 미충족으로 남음).
    생산자(lcode_emit/run_alpha_search)가 oos_months 적립 시작 시 자동으로 흐른다
    (선행조건: lcode_harvester pass-through 목록에 oos_months 추가 필요).
    """
    vals: list[float] = []
    months: list[float] = []
    for m in cluster["members"]:
        try:
            v = float(m.get("oos_retention"))
            if v == v:  # NaN guard
                vals.append(v)
        except (TypeError, ValueError):
            pass
        try:
            mo = float(m.get("oos_months"))
            if mo == mo and mo > 0:  # NaN/비양수 guard
                months.append(mo)
        except (TypeError, ValueError):
            pass
    oos_months = round(_median(months), 1) if months else None
    if not vals:
        return {"oos_months": oos_months, "oos_effect_vs_is": None,
                "note": "promote.R r4_regime_payoff / essence_score 경유 확정"}
    med = _median(vals)
    return {
        "oos_months": oos_months,
        "oos_effect_vs_is": round(med, 3),
        "note": (f"L-code oos_retention 실값 {len(vals)}건 median (IS65/OOS35 활성SR retention)"
                 + (f" + oos_months 실값 {len(months)}건 median" if months else " — oos_months 실값 무 → None 유지")
                 + " — promote.R essence_score 경유 재확정"),
    }


def _draft_falsification(cluster: dict) -> dict:
    """멤버 falsification_attempts 실기록 집계. 기록 없으면 기존 빈 attempts 유지."""
    attempts: list = []
    for m in cluster["members"]:
        fa = m.get("falsification_attempts")
        if isinstance(fa, list):
            attempts.extend(a for a in fa if a)
        elif isinstance(fa, str) and fa.strip():
            attempts.append(fa.strip())
    note = ("L-code 기록 반증 시도 실값 집계" if attempts else
            "promote.R 5축(r7 적극 반증)에서 kr-inverse-pattern-miner 역가설 + role_honesty로 채움")
    return {"attempts": attempts, "note": note}


def _build_one_candidate(cl: dict, mode: str, today: str):
    cand_type = _classify_type(cl)
    polarity = _polarity(cl)
    family = _dominant_family(cl)  # 엄격 과반만 대표 — 이질 클러스터는 'mixed' (crash-safe)
    cluster_key = f"{mode}_{family or 'unknown'}_{polarity}_{'_'.join(sorted(cl['l_codes'])[:3])}"
    candidate_id = f"CAND_{today}_{cluster_key}"

    evidence = _draft_evidence(cl)
    evidence.update(_independence(cl))

    candidate = {
        "schema_version": "v54_ax_p0_mode",
        "candidate_id": candidate_id,
        "research_mode": mode,
        "metric_type": _cluster_metric_type(cl),
        "type": cand_type,
        "polarity": polarity,
        "statement_draft": _draft_statement(cl, cand_type, polarity),
        "supporting_l_codes": cl["l_codes"],
        "scope_draft": _draft_scope(cl),
        "evidence_draft": evidence,
        # v8.1 트랙D: 빈 하드코딩 → L-code 실값 매핑 (mechanism_hypothesis / oos_retention /
        # falsification_attempts). 실값 없으면 종전과 동일한 빈 draft — 가짜 데이터 생성 금지.
        "falsification_draft": _draft_falsification(cl),
        "mechanism_draft": _draft_mechanism(cl),
        "oos_validation_draft": _draft_oos(cl),
        "cluster_members_count": cl["size"],
        "status": "pending_5axis",
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    return candidate_id, candidate, set(cl["l_codes"])


def _write_with_superset_dedup(new_cands: list, out_dir: str) -> list[str]:
    """replace-by-superset: 신 후보가 기존 pending CAND의 supporting 진부분집합을 포함하면 subset 제거."""
    existing: dict = {}
    for f in glob.glob(os.path.join(out_dir, "CAND_*.json")):
        d = _load(f)
        if isinstance(d, dict):
            existing[f] = set(d.get("supporting_l_codes") or [])
    written: list[str] = []
    for cand_id, cand, sup in new_cands:
        cand_fname = f"{cand_id}.json"
        # subset 또는 equal(파일명 상이 — 옛 mode-less id) 제거: 새 후보가 대체/갱신
        for ef in [k for k, v in existing.items()
                   if v and v <= sup and os.path.basename(k) != cand_fname]:
            try:
                os.remove(ef)
                print(f"  [dedup] removed {os.path.basename(ef)} (subset/equal of {cand_id})")
            except OSError:
                pass
            existing.pop(ef, None)
        # 새 후보가 남은 기존의 진부분집합이면 skip
        if any(sup and sup < v for v in existing.values()):
            continue
        path = os.path.join(out_dir, f"{cand_id}.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(cand, fh, indent=2, ensure_ascii=False)
        existing[path] = sup
        written.append(path)
    return written


# ══════════════════════════════════════════════════════════════════════
# ②Distilled 계층 (2026-07-04 엔진 재설계 — 3층 산출물 모델의 소비 단위)
#   CAND가 5축 미달이어도 폐기하지 않고 DIST 초안으로 유지한다.
#   qepm/memory/axioms/distilled/DIST-<MODE>-NNN.json + 06_Registry/distilled_knowledge.json
#   lifecycle: pending_5axis(초안) → distilled(/cleaner 세션 LLM 정제 — 무인 정제 금지,
#   INV-6: statement_refined는 /cleaner에서만 작성·정제 전 텍스트 주입 금지) → promoted | expired.
#   재생성 멱등성: cluster_key(=sorted supporting_l_codes sha1)로 기존 DIST와 매칭 —
#   draft 필드만 갱신, dist_id/status/statement_refined/refined_at은 절대 보존.
# ══════════════════════════════════════════════════════════════════════

DIST_MODE_PREFIX = {
    "alpha_search": "AS", "alpha_research": "AR", "qepm_legacy": "QPM",
    "judge_gate": "JG", "governor_admission": "GV",
    "factor_rotation": "FR", "regime_research": "RR", "ramp": "RAMP",
}


def _cluster_key(l_codes: list[str]) -> str:
    return hashlib.sha1("|".join(sorted(set(l_codes))).encode("utf-8")).hexdigest()[:12]


def _next_dist_id(dist_dir: str, mode: str, taken: set[str]) -> str:
    prefix = DIST_MODE_PREFIX.get(mode, "GEN")
    nums = []
    for f in glob.glob(os.path.join(dist_dir, f"DIST-{prefix}-*.json")):
        m = re.match(rf"DIST-{prefix}-(\d+)\.json$", os.path.basename(f))
        if m:
            nums.append(int(m.group(1)))
    n = (max(nums) + 1) if nums else 1
    while f"DIST-{prefix}-{n:03d}" in taken:
        n += 1
    return f"DIST-{prefix}-{n:03d}"


_DIST_DRAFT_FIELDS = (
    "research_mode", "metric_type", "type", "polarity", "statement_draft",
    "supporting_l_codes", "scope_draft", "evidence_draft", "falsification_draft",
    "mechanism_draft", "oos_validation_draft", "cluster_members_count",
)

# negative DIST 기본 expiry (일): INV-7 'expiry = 보편 시간부활 바닥' — expiry 공백 negative는
# revival monitor의 expiry 폴백 부활조차 불가하므로 초안 단계에서 바닥을 깐다.
_DIST_DEFAULT_EXPIRY_DAYS = 90


def _fill_default_expiry(dist: dict) -> None:
    """negative 카드에 한해 expiry 공백만 +90일로 채움 — 기존 값 절대 덮어쓰기 금지(멱등)."""
    if dist.get("polarity") != "negative":
        return
    if dist.get("expiry"):
        return
    dist["expiry"] = (
        datetime.now(timezone.utc) + timedelta(days=_DIST_DEFAULT_EXPIRY_DAYS)
    ).strftime("%Y-%m-%d")


def _backfill_expiry_all(dist_dir: str) -> int:
    """기존 negative DIST 전수 순회 — expiry 공백만 기본 +90d 충전. CAND 매칭 순회는
    현행 candidate와 cluster_key가 일치하는 카드만 지나므로, candidate가 소멸한 고아
    카드에는 INV-7 시간부활 바닥이 영구 미충전 — 전수 pass로 바닥을 보장한다.
    기존 값 절대 보존(멱등) · expiry 외 필드 무변경 · 변경 카드만 재기록. 반환 n_filled."""
    n_filled = 0
    for f in sorted(glob.glob(os.path.join(dist_dir, "DIST-*.json"))):
        d = _load(f)
        if not isinstance(d, dict):
            continue
        before = d.get("expiry")
        _fill_default_expiry(d)
        if d.get("expiry") != before:
            with open(f, "w", encoding="utf-8") as fh:
                json.dump(d, fh, indent=2, ensure_ascii=False)
            n_filled += 1
    return n_filled


# 정제 지식을 앞으로 옮길 때 승계하는 필드 (draft 필드 아님 — main loop가 안 건드림).
_MIGRATE_REFINE_FIELDS = (
    "statement_refined", "retry_condition", "refined_at", "refined_by",
    "approved_at", "approved_by", "frontier", "live_trigger",
    "adversarial_verdict", "adversarial_note", "expiry",
    "constraint_firewall", "revival_spec",
)


def _plan_forward_migrations(existing: dict, cand_list: list) -> tuple[dict, dict]:
    """Forward-migration planner (2026-07-18 엔진-갭 수리, 도훈 mandate).

    cluster_key = sha1(정확한 멤버셋)이라 클러스터가 멤버 성장 시 key drift → 구 refined
    카드가 orphan + 신규 unrefined pending 중복이 생기던 갭을 닫는다. refined(status=distilled
    ∧ statement_refined) 카드의 멤버셋이 어떤 live CAND의 **진부분집합**(같은 research_mode
    ∧ polarity)이면 = 그 클러스터가 정제 후 성장한 것 → 승인 정제를 앞으로 옮긴다.

    **정확히 1개**의 refined 조상을 가진 cand_key만 채택(accepted) — 2개 이상은 무손실
    자동병합 불가라 flagged(수동 /cleaner). 각 refined 카드는 가장 가까운(최소 증가) superset
    CAND 1개에만 귀속(collision-free).

    반환 (accepted, flagged):
      accepted: {cand_key: (rid, cf, cand, S)}   # 1:1 적용 대상
      flagged:  {cand_key: [rid, ...]}           # 조상 2개+ — 자동병합 안 함
    """
    refined = []
    for _key, (_path, d) in existing.items():
        if d.get("status") == "distilled" and d.get("statement_refined"):
            refined.append((d.get("dist_id"),
                            frozenset(d.get("supporting_l_codes") or []),
                            d.get("research_mode"), d.get("polarity")))
    plans: dict = {}  # cand_key -> [(rid, cf, cand, S)]
    for (rid, rset, rmode, rpol) in refined:
        if not rset:
            continue
        best = None  # (added, cand_key, cf, cand, S)
        for (cf, cand, S, ckey) in cand_list:
            # 이 CAND가 이미 R 자신에 매핑(동일 셋)이면 성장 아님 → skip
            tgt = existing.get(ckey)
            if tgt is not None and tgt[1].get("dist_id") == rid:
                continue
            if not (rset < S):                                   # 진부분집합(성장)만
                continue
            # ★스코프 가드: 구 멤버가 새 클러스터의 strict majority(2·|old|>|new|)일 때만.
            #   = "같은 클러스터가 성장"(예: 134→139 jac 0.96)만 승계하고, 소수 멤버가
            #   훨씬 큰 grab-bag에 흡수된 경우(예: 9⊂31 jac 0.29)는 스코프 오이관이라 제외.
            if 2 * len(rset) <= len(S):
                continue
            if (cand.get("research_mode") or None) != rmode:     # 같은 모드
                continue
            if (cand.get("polarity") or None) != rpol:           # 같은 극성(neg→pos 병합 금지)
                continue
            added = len(S) - len(rset)
            if best is None or (added, ckey) < (best[0], best[1]):
                best = (added, ckey, cf, cand, S)
        if best is not None:
            plans.setdefault(best[1], []).append((rid, best[2], best[3], best[4]))
    accepted, flagged = {}, {}
    for ckey, lst in plans.items():
        if len(lst) == 1:
            accepted[ckey] = lst[0]
        else:
            flagged[ckey] = [x[0] for x in lst]
    return accepted, flagged


def build_distilled(cand_dir: str, dist_dir: str, index_path: str) -> tuple[int, int]:
    """pending CAND 전건 → DIST 초안 생성/갱신 + 통합 인덱스 재작성. 반환 (n_new, n_updated).

    2026-07-18 엔진-갭 수리: main loop 앞에 forward-migration 선-패스를 둔다 —
    정제 후 성장한 클러스터의 승인 정제를 live-key 카드로 옮겨(consolidate) 또는 rekey해
    orphan-refined + pending-중복 누적을 원천 차단(idempotent). 상세: _plan_forward_migrations.
    """
    os.makedirs(dist_dir, exist_ok=True)
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    existing: dict[str, tuple[str, dict]] = {}  # cluster_key -> (path, dist)
    by_id: dict[str, tuple[str, dict]] = {}     # dist_id -> (path, dist)
    taken_ids: set[str] = set()
    for f in glob.glob(os.path.join(dist_dir, "DIST-*.json")):
        d = _load(f)
        if isinstance(d, dict) and d.get("cluster_key"):
            existing[d["cluster_key"]] = (f, d)
            taken_ids.add(d.get("dist_id") or "")
            if d.get("dist_id"):
                by_id[d["dist_id"]] = (f, d)

    # CAND 1회 파싱 (migration 계획 + main loop 공용)
    cand_list: list = []
    for cf in sorted(glob.glob(os.path.join(cand_dir, "CAND_*.json"))):
        cand = _load(cf)
        if not isinstance(cand, dict):
            continue
        sup = cand.get("supporting_l_codes") or []
        if not sup:
            continue
        cand_list.append((cf, cand, frozenset(sup), _cluster_key(sup)))

    # ── forward-migration 선-패스 (엔진-갭 수리) ──
    n_migrated = n_consolidated = 0
    accepted, flagged = _plan_forward_migrations(existing, cand_list)
    for ckey, (rid, cf, cand, S) in accepted.items():
        if rid not in by_id:
            continue
        rpath, rd = by_id[rid]
        rset = frozenset(rd.get("supporting_l_codes") or [])
        old_key = rd.get("cluster_key")
        tgt = existing.get(ckey)
        if tgt is not None and tgt[1].get("dist_id") != rid:
            # CONSOLIDATE: 성장 key에 pending 중복 T가 이미 있음 → T가 승인 정제 상속, R은 expire
            tpath, td = tgt
            if td.get("status") == "distilled" and td.get("statement_refined"):
                continue  # T도 이미 정제됨 → 애매(자동병합 안 함)
            for fld in _MIGRATE_REFINE_FIELDS:
                if fld in rd:
                    td[fld] = rd[fld]
            td["status"] = "distilled"
            td["migrated_from"] = rid
            td["migration_note"] = (
                f"engine forward-migration 20260718: cluster grew {len(rset)}->{len(S)}; "
                f"refinement inherited from {rid}. INV-6: 승인문 재배치(신규 활성화 아님, 주입문 불변).")
            # T는 main loop가 draft 갱신하며 기록 — 여기선 미기록. R(조상)만 expire 기록.
            rd["status"] = "expired"
            rd["expired_at"] = today
            rd["migrated_to"] = td.get("dist_id")
            rd["expire_reason"] = (
                f"superseded_by_forward_migration -> {td.get('dist_id')} "
                f"(cluster grew {len(rset)}->{len(S)}; 승인 refinement carried forward; "
                f"engine-gap fix 20260718). INV-7 부활: migrated_to 카드 참조.")
            with open(rpath, "w", encoding="utf-8") as fh:
                json.dump(rd, fh, indent=2, ensure_ascii=False)
            if old_key in existing and existing[old_key][1].get("dist_id") == rid:
                del existing[old_key]
            n_consolidated += 1
        elif tgt is None:
            # REKEY: 성장 key에 카드 없음 → R을 앞으로 이동(승인 정제 유지). main loop가 기록.
            rd["cluster_key"] = ckey
            rd["candidate_id"] = cand.get("candidate_id")
            rd["migrated_from_key"] = old_key
            rd["migration_note"] = (
                f"engine forward-migration 20260718: cluster grew {len(rset)}->{len(S)}; "
                f"rekeyed {old_key}->{ckey} (승인 refinement 유지).")
            for fld in _DIST_DRAFT_FIELDS:
                if fld in cand:
                    rd[fld] = cand[fld]
            if old_key in existing:
                del existing[old_key]
            existing[ckey] = (rpath, rd)
            n_migrated += 1

    n_new = n_upd = 0
    for cf, cand, S, key in cand_list:
        if key in existing:
            path, dist = existing[key]
            for fld in _DIST_DRAFT_FIELDS:  # draft만 갱신 — 정제/상태 필드 절대 보존
                if fld in cand:
                    dist[fld] = cand[fld]
            dist["candidate_id"] = cand.get("candidate_id")
            dist["updated_at"] = now
            n_upd += 1
        else:
            mode = cand.get("research_mode") or "unknown"
            dist_id = _next_dist_id(dist_dir, mode, taken_ids)
            taken_ids.add(dist_id)
            dist = {
                "schema_version": "distilled_v1",
                "dist_id": dist_id,
                "cluster_key": key,
                "candidate_id": cand.get("candidate_id"),
                # lifecycle: pending_5axis → distilled(/cleaner 정제) → promoted | expired
                "status": "pending_5axis",
                "statement_refined": None,   # INV-6: /cleaner 세션에서만 작성 (무인 정제 금지)
                "retry_condition": None,     # negative: INV-7 재도전 조건 (/cleaner 기록)
                "refined_at": None, "refined_by": None,
                "promoted_to_axiom": None,
                "created_at": now, "updated_at": now,
            }
            for fld in _DIST_DRAFT_FIELDS:
                if fld in cand:
                    dist[fld] = cand[fld]
            path = os.path.join(dist_dir, f"{dist_id}.json")
            existing[key] = (path, dist)
            n_new += 1
        _fill_default_expiry(dist)  # negative 공백만 +90d (신규/기존 공통 — 기존 값 보존)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(dist, fh, indent=2, ensure_ascii=False)

    # candidate 소멸 고아 카드 포함 전수 expiry 바닥 — CAND 매칭 순회가 못 미치는
    # negative 공백 카드에도 INV-7 시간부활 바닥을 깐다 (기존 값 보존·멱등).
    _backfill_expiry_all(dist_dir)
    _write_distilled_index(dist_dir, index_path)
    if n_consolidated or n_migrated or flagged:
        print(f"[distilled] forward-migration: {n_consolidated} consolidated / "
              f"{n_migrated} rekeyed / {len(flagged)} multi-ancestor flagged")
        for fckey, rids in flagged.items():
            print(f"  [multi-ancestor] cand_key {fckey[:8]} <- {rids} "
                  f"(수동 /cleaner 필요 — 자동병합 안 함)")
    return n_new, n_upd


def _write_distilled_index(dist_dir: str, index_path: str) -> int:
    """06_Registry/distilled_knowledge.json 통합 인덱스 (소비 3배선의 단일 조회면).

    consumers: hooks/axiom_context_inject.sh(주입 — status=distilled·negative/conditional만)
             / tools/hypothesis_index.R(검색 — DISTILLED_* verdict)
             / 02_Infrastructure/axiom/distilled.R(truths 블록·정제 helper).
    """
    entries = []
    for f in sorted(glob.glob(os.path.join(dist_dir, "DIST-*.json"))):
        d = _load(f)
        if not isinstance(d, dict):
            continue
        fam = (d.get("scope_draft") or {}).get("factor_family")
        entries.append({
            "dist_id": d.get("dist_id"),
            "research_mode": d.get("research_mode"),
            "family": fam,
            "type": d.get("type"),
            "polarity": d.get("polarity"),
            "metric_type": d.get("metric_type"),
            "status": d.get("status"),
            "statement_refined": d.get("statement_refined"),
            "statement_draft": d.get("statement_draft"),
            "retry_condition": d.get("retry_condition"),
            # (M9 2026-07-10) distilled.R::rebuild_distilled_index와 스키마 정합 —
            # frontier/live_trigger/revival_spec/expiry 등 탐색지도·부활 필드가 주간
            # 스윕(py 재작성)마다 인덱스에서 소실되던 F9 수리. 카드에 있으면 그대로 통과.
            "adversarial_verdict": d.get("adversarial_verdict"),
            "expiry": d.get("expiry"),
            "frontier": d.get("frontier") or [],           # INV-7: 미탐색 인접 경로(원리2)
            "live_trigger": d.get("live_trigger") or [],    # INV-7: 부활 조건(원리4) — 사람용 표시
            "revival_spec": d.get("revival_spec") or [],    # 기계용 부활 spec — monitor 소비
            "constraint_firewall": d.get("constraint_firewall"),  # 방화벽 판정 기록(원리3)
            "supporting_l_codes": d.get("supporting_l_codes") or [],
            "n_supporting": len(d.get("supporting_l_codes") or []),
            "candidate_id": d.get("candidate_id"),
            "cluster_key": d.get("cluster_key"),
            "promoted_to_axiom": d.get("promoted_to_axiom"),
            "created_at": d.get("created_at"),
            "refined_at": d.get("refined_at"),
            "drafted_at": d.get("drafted_at"),
            "approved_at": d.get("approved_at"),
            "source_file": os.path.basename(f),
        })
    out = {
        "schema_version": "distilled_knowledge_v1",
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        # (M9) note도 distilled.R 판과 동일 문안으로 정렬 — R/py 재작성 간 flip-flop 방지
        "note": ("Axiom 엔진 ②Distilled 계층 통합 인덱스. lifecycle: pending_5axis→"
                 "[자동초안+적대검증]→proposed→[도훈 배치승인]→distilled→promoted|expired. "
                 "INV-6(2026-07-04 재정의: 무인 활성화 금지): 주입/truths 소비는 status=distilled만 "
                 "— proposed·pending_5axis 초안 텍스트 주입 금지(안전속성 보존)."),
        "n_entries": len(entries),
        "n_distilled": sum(1 for e in entries if e["status"] == "distilled"),
        "n_proposed": sum(1 for e in entries if e["status"] == "proposed"),
        "entries": entries,
    }
    os.makedirs(os.path.dirname(index_path), exist_ok=True)
    with open(index_path, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2, ensure_ascii=False)
    return len(entries)


def _singleton_cluster(lc: dict) -> dict:
    """단독 L-code를 1-member cluster 구조로 래핑 (콜드스타트 경로 — P1 2026-07-04).

    신규 모드의 최초 단일 L-code는 min_size=2 요건 때문에 클러스터에 못 들어가
    CAND/DIST가 영구 미생성 → 실패지식 소비 불가. 단독분도 pending_5axis 초안으로
    만들어 소비 가능하게 한다. 승격 자격(5축 INV-4)은 promote.R에서 그대로 걸리므로
    단독이라 독립성축(r7 n_eff)이 미달이면 pending에 머문다 — 초안 생성만 허용.
    """
    return {
        "cluster_index": -1,
        "size": 1,
        "l_codes": [lc["l_code"]],
        "members": [lc],
    }


def build_candidates(corpus: dict, out_dir: str) -> list[str]:
    lcodes = corpus.get("lcodes", [])
    if not lcodes:
        return []
    os.makedirs(out_dir, exist_ok=True)
    today = datetime.now(timezone.utc).strftime("%Y%m%d")

    # mode-partition: 같은 research_mode 내에서만 클러스터 (cross-mode 일반화는 promote_global 영역)
    by_mode: dict = {}
    for lc in lcodes:
        by_mode.setdefault(lc.get("research_mode") or "unknown", []).append(lc)

    new_cands: list = []
    for mode, mode_lcodes in by_mode.items():
        clusters = cluster_lcodes(mode_lcodes)
        # 유령 클러스터 disband (2026-07-18 도훈 mandate): family 버킷만으로 묶인
        #   방향-불명(mixed) 클러스터는 초안화하지 않는다. 멤버는 아래 singleton
        #   경로로 흘러 각자 독립 초안이 됨(지식 보존). coherent(neg/cond/pos)는 유지.
        kept = []
        for cl in clusters:
            if _is_spurious_family_only(cl):
                print(f"  [disband] family-only mixed cluster -> singletons: {cl['l_codes']}")
            else:
                kept.append(cl)
        clusters = kept
        clustered_ids = {lid for cl in clusters for lid in cl["l_codes"]}
        for cl in clusters:
            new_cands.append(_build_one_candidate(cl, mode, today))
        # 콜드스타트(P1): 클러스터에 못 들어간(또는 disband된) 단독 L-code도
        #   pending_5axis 초안으로. (superset dedup이 이후 진짜 클러스터가 형성되면
        #   subset singleton을 자동 대체한다.)
        for lc in mode_lcodes:
            if lc.get("l_code") and lc["l_code"] not in clustered_ids:
                new_cands.append(_build_one_candidate(_singleton_cluster(lc), mode, today))

    return _write_with_superset_dedup(new_cands, out_dir)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--project-dir",
        default=os.environ.get("QVEST_PROJECT_DIR")
        or os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("QM_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
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

    # ②Distilled 계층 (2026-07-04): CAND 전건 → DIST 초안 생성/갱신 + 통합 인덱스
    dist_dir = os.path.join(args.project_dir, "qepm", "memory", "axioms", "distilled")
    index_path = os.path.join(args.project_dir, "06_Registry", "distilled_knowledge.json")
    n_new, n_upd = build_distilled(out_dir, dist_dir, index_path)
    print(f"[cluster_extractor] distilled: {n_new} new / {n_upd} updated → {index_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
