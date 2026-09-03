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


def probe_keys(o, key):
    """소비 판정에 쓸 키. ★**발행 키와 같은 술어**로 만든다.

    2026-09-01 실사고: 판정은 `arxiv_id or paper_key or dict-key` 로 직접 만든
    키를 쓰고, 원장·스킵리스트에 적히는 키는 pid_of() 정본이었다. 큐 항목 상당수가
    `axv:2505.20608` 형태로 키가 붙어 있어 정규화 전후가 어긋났고, **이미 소비한
    논문이 영원히 큐 상단에 남았다** — 2505.20608 은 소비 7초 뒤 다시 집혀 충실구현이
    재실행됐고, 2608.23944 는 같은 이유로 4회 반복 측정(전부 PORT_t -0.408)됐다.
    이 파일 헤더가 경고한 그 병이다: "술어를 소비자 쪽에 다시 적는 순간 재발한다."
    판정 키를 다시 만드는 것 자체가 술어 재구현이다.
    ★raw 도 함께 본다 — 정본 키 도입 이전에 raw 형태로 적힌 기록을 놓치지 않기 위해서다
      (합집합이므로 누락 방향으로만 안전해진다)."""
    ks = set()
    try:
        canon = str(pid_of(o, warn=False) or "").strip()
        if canon:
            ks.add(canon)
    except Exception:
        pass
    raw = str(o.get("arxiv_id") or o.get("paper_key") or key or "").strip()
    if raw:
        ks.add(raw)
    return ks


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
    # ★재현 불가로 판정된 논문은 건너뛴다 — 없으면 같은 논문을 영원히 다시 집는다(2026-08-30).
    skip = set()
    try:
        sk = json.load(io.open(os.path.join(os.path.dirname(os.path.dirname(HERE)),
                                            "06_Registry", "replication_skiplist.json"), encoding="utf-8"))
        # ★revoked 는 건너뛰지 않는다 — 판정이 철회된 논문은 다시 후보다(AX-000)
        skip = {str(e.get("paper_key")) for e in (sk.get("entries") or [])
                if e.get("status") != "revoked"}
    except Exception:
        pass
    # ★이미 강화 원장에 들어온 논문은 소비된 것이다 (도훈 지시 2026-08-30 실사고 수리).
    #   실사고: 2026-08-30 12:43·12:44 무인 루프가 방금 끝낸 2608.24703 을 연속 두 번 다시
    #   집었다. 스킵리스트는 "재현 불가" 판정만 담고, alpha_pending() 은 L-code 소비만 본다.
    #   그 사이에 **무인 충실구현 경로가 통째로 빠져 있었다** — 이 경로로 소비된 논문은
    #   어느 명부에도 안 실려서 큐 상단에 영원히 남는다.
    #   ⇒ 원장(reinforce_ledger_l1)이 소비 기록의 정본이다. status 무관 — active/exhausted/
    #     parked/skipped_base_quality 전부 "이미 손댄 논문"이다.
    done = set()
    try:
        _led = json.load(io.open(os.path.join(os.path.dirname(os.path.dirname(HERE)),
                                              "06_Registry", "reinforce_ledger_l1.json"),
                                 encoding="utf-8"))
        for _e in (_led.get("entries") or []):
            _k = str(_e.get("paper_key") or "")
            if _k:
                done.add(_k)
    except Exception:
        pass

    skipped = 0
    n_skiplist = 0
    n_ledger = 0
    for key, o in pairs:
        pk_keys = probe_keys(o, key)
        if pk_keys & skip:
            n_skiplist += 1
            continue
        if pk_keys & done:
            n_ledger += 1
            continue
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
