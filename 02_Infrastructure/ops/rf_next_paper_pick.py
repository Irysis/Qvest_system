#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#==============================================================================
# rf_next_paper_pick.py — 강화 무인 러너용 **큐 상단 논문 1편 어댑터** (2026-08-30)
#
# 왜 얇은가: 술어(어떤 논문이 미소비 testable 인가)는 research_pool_predicates.py 가
#   **유일 정의**다. 그 파일이 명시한 계약이 "소비자는 import 하거나 CLI 로 호출한다.
#   술어를 소비자 쪽에 다시 적는 순간 3연발 결함이 재발한다." 이 파일은 그 계약을 지켜
#   alpha_pending() 을 import 하고, **정렬·선택만** 한다.
#
# 출력: 큐 상단 1편을 JSON 1줄로 stdout. 없으면 {} 를 낸다(러너가 무동작 종료).
# 정렬: alpha_pending() 이 준 순서를 그대로 따른다 — 재검색·재정렬 금지(lean-loop 규약).
#   단 **원문 링크가 없는 항목은 건너뛴다** (v10: 근거 논문 없는 착수 금지 — 원장이 거부한다).
#==============================================================================
import io, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

try:
    from research_pool_predicates import alpha_pending, display_name, pid_of
except Exception as e:                                   # pragma: no cover
    print(json.dumps({"error": "predicate_import_failed: %s" % e}, ensure_ascii=False))
    sys.exit(0)


def _url_of(o, key=""):
    """항목에서 원문 링크를 얻는다.

    ★2026-08-30 실측: alpha_pending() 은 **arxiv_id 를 키로 하는 dict** 를 주고
      값 dict 에는 url 키가 없다(키: arxiv_id/title/source/route/kr_feasible/
      factor_candidate/reason). 그래서 arxiv_id 로 링크를 **구성**한다 —
      추측이 아니라 arXiv 의 안정 URL 규약이다. 큐가 전부 arXiv 라
      전문 접근이 보장되고, 2026-08-29 15/20 을 죽인 페이월 실패 모드가 없다.
    """
    if not isinstance(o, dict):
        return ""
    for k in ("url", "source_url", "pdf_url", "link", "abs_url", "landing_page_url"):
        v = o.get(k)
        if isinstance(v, str) and v.startswith("http"):
            return v
    aid = str(o.get("arxiv_id") or key or "").strip()
    if aid and str(o.get("source") or "").lower() == "arxiv":
        return "https://arxiv.org/abs/" + aid
    doi = o.get("doi")
    if isinstance(doi, str) and doi.strip():
        d = doi.strip()
        return d if d.startswith("http") else ("https://doi.org/" + d.lstrip("/"))
    return ""


def main(argv):
    stage = argv[0] if argv else os.path.join(
        os.path.dirname(os.path.dirname(HERE)), "stage_artifacts", "paper_recharge")
    try:
        items = alpha_pending(stage)
    except Exception as e:
        print(json.dumps({"error": "alpha_pending_failed: %s" % e}, ensure_ascii=False))
        return 0
    if isinstance(items, int):                            # 구현이 개수만 주는 경우
        print(json.dumps({"error": "alpha_pending_returned_count_only", "n": items}, ensure_ascii=False))
        return 0
    # ★dict(키=arxiv_id) 또는 list 둘 다 받는다. dict 는 삽입순서를 그대로 큐 순서로 쓴다.
    if isinstance(items, dict):
        pairs = list(items.items())
    else:
        pairs = [("", o) for o in (items or [])]
    skipped = 0
    for key, o in pairs:
        u = _url_of(o, key)
        if not u:
            skipped += 1
            continue
        try:
            title = display_name(o)
        except Exception:
            title = str(o.get("title") or "")
        try:
            pk = pid_of(o, warn=False)
        except Exception:
            pk = str(o.get("paper_key") or o.get("arxiv_id") or key or "")
        fc = o.get("factor_candidate") or {}
        print(json.dumps({
            "title": title,
            "paper_title": str(o.get("title") or title),          # 원 제목(요약명이 아니라)
            "url": u, "paper_key": pk, "source": o.get("source"),
            "reason": str(o.get("reason") or "")[:400],           # 왜 이 논문인가(트리아지 사유)
            "factor_name": str(fc.get("name") or ""),
            "factor_def": str(fc.get("def") or "")[:300],         # 후보 팩터 정의
            "kr_feasible": o.get("kr_feasible"),
            "skipped_no_url": skipped}, ensure_ascii=False))
        return 0
    print(json.dumps({"error": "no_item_with_url", "skipped_no_url": skipped,
                      "n_total": len(pairs)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
