# -*- coding: utf-8 -*-
import json
PR = "stage_artifacts/paper_recharge"
TODAY, BACK = "20260926", "20260925"

rec = json.load(open(f"{PR}/mcp_discovery_{TODAY}_recovered.json", encoding="utf-8"))
cands = rec["candidates"]
r24 = json.load(open(f"{PR}/alpha_search_route_20260924.json", encoding="utf-8"))
prior = {p.get("paper_key"): p for p in r24["papers"]}

papers = []
for c in cands:
    pk = c["paper_key"]
    pv = prior.get(pk) or {}
    pvv = pv.get("verdict") or (pv.get("factor_candidate") or {}).get("verdict") or "unknown"
    reason = (
        f"신규 아님 — 20260924 라우팅(alpha_search_route_20260924.json)에서 이미 판정됨"
        f"(당시 verdict={pvv}, route={pv.get('route')}). 수집기 질의 집합·categories·max_results·"
        f"sortBy·recency_days=0 이 20260924 와 완전 동일해 복구 결과도 동일 253건이다."
    )
    papers.append({
        "title": c["title"], "id": c["arxiv_id"], "paper_key": pk,
        "source": "arxiv", "route": "skip", "verdict": "redundant",
        "factor_candidate": None,
        "prior_route_date": "20260924", "prior_verdict": pvv,
        "reason": reason,
    })

note = (
    "수집원 복구 + 원인 정정. mcp_discovery_20260926.json 은 status=mcp_error·candidates=0 "
    "(arxiv-mcp-server 0.7.2 전 질의 HTTP 406). ★20260924 노트의 원인 진단('무간격 연사 throttle')은 "
    "오진이다 — 본 세션 통제 실험: 단건·무간격 아님·trivial 질의(all:electron)·UA 유무·Accept/"
    "Accept-Encoding 변형·http/https·arxiv.org·export.arxiv.org 전 조합에서 Python HTTP 클라이언트"
    "(urllib)는 0.2~0.5초 내 즉시 406, 반면 curl 은 동일 URL 에 HTTP 200(0.06~0.5s). 즉 arXiv 는 정상이고 "
    "406 은 이 호스트의 Python 클라이언트 경로에 한정된 차단이다(arxiv-mcp-server 가 Python 이라 죽는 이유). "
    "대조 증거: 본 세션 urllib 판 복구 시도는 30/30 질의 406 실패, curl 판은 30/30 성공·실패 0. "
    "복구 = 질의 스펙 바이트 동일 유지 + 전송만 curl 로 교체, 3.1초 간격 → 253건 유니크 복구. "
    "dedup = paper_registry(853건)+alpha_search_queue_done::processed(77)+route 이력 49종(3,947행)"
    "+data_pipeline_queue(49), arXiv 신·구 표기 모두(2504.01234 및 cond-mat/0410079 꼴 22건 포함). "
    "★결과: 복구 253건이 20260924 기처리분과 100% 일치(교집합 253/253) → 신규 0건. "
    "구조적 원인 = 수집 스펙이 포화다. 30개 고정 질의 · sort_by=relevance · recency_days=0 · date_from=null "
    "이라 날짜창이 없어 매일 같은 상위 10건/질의를 돌려준다 — 406 을 고쳐도 신규 논문은 나오지 않는다. "
    "신규 유입에는 수집 스펙 변경(sortBy=submittedDate 또는 recency_days>0 / date_from 지정 / 질의 확장)이 "
    "필요하다 — 이는 트리아지 소관 밖(도훈 판단 사항). "
    "curated 시드(paper_recharge_sources.csv 26건)는 curated_routed.json 기준 전건 기처리 → 신규 0, append 0. "
    "data_pipeline_queue append 0건(금일 data_pipeline_required 판정 0). "
    "참고: 20260924 의 유일한 testable(axv:2603.20271 · KR 투자자유형 Transfer Entropy)은 "
    "alpha_search_queue_done::processed 에 없어 아직 미소비 상태다."
)

out = {
    "date": TODAY, "schema_version": "paper_router_v4",
    "counts_by_route": {"replication": 0, "skip": len(papers)},
    "counts_by_verdict": {"testable": 0, "redundant": len(papers),
                          "data_pipeline_required": 0, "skip": 0},
    "n_factor_candidates": 0,
    "n_candidates_recovered": len(cands),
    "discovery_source": f"recovered_direct_arxiv_api_via_curl (mcp_discovery_{TODAY}.json = mcp_error/0)",
    "papers": papers, "note": note,
}
json.dump(out, open(f"{PR}/alpha_search_route_{TODAY}.json", "w", encoding="utf-8"),
          ensure_ascii=False, indent=1)

back = {
    "date": BACK, "schema_version": "paper_router_v4",
    "counts_by_route": {"replication": 0, "skip": 0},
    "counts_by_verdict": {"testable": 0, "redundant": 0,
                          "data_pipeline_required": 0, "skip": 0},
    "n_factor_candidates": 0, "n_candidates_recovered": 0,
    "discovery_source": f"mcp_discovery_{BACK}.json = mcp_error/0 (rolled into {TODAY})",
    "papers": [],
    "note": (
        f"mcp_discovery_{BACK}.json 역시 status=mcp_error·candidates=0(동일 406, Python 클라이언트 차단). "
        f"질의 집합·categories·max_results·sortBy 가 {TODAY} 와 필드 단위로 완전 동일하고 recency_days=0·"
        f"date_from=null(relevance 정렬, 날짜창 없음)이라 복구 결과는 두 날짜에 동일하다. 이중 라우팅을 피하려고 "
        f"복구 253건 전량을 alpha_search_route_{TODAY}.json 에 단일 귀속시켰다 — 본 파일은 백로그 소비 사실의 "
        f"기록이며 신규 라우팅 0건이다(20260923→20260924 선례와 동일 처리)."
    ),
}
json.dump(back, open(f"{PR}/alpha_search_route_{BACK}.json", "w", encoding="utf-8"),
          ensure_ascii=False, indent=1)

print("route", TODAY, out["counts_by_route"], out["counts_by_verdict"], "n_papers", len(papers))
print("route", BACK, back["counts_by_route"])
