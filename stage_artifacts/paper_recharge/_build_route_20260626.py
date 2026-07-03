# -*- coding: utf-8 -*-
# 06-26 라우팅 빌더 (Q-Lead 인라인, paper_router_prompt.md STEP1+2 준수, AUTORUN=0)
import json, os
STAGE = "stage_artifacts/paper_recharge"
TODAY = "20260626"
disc = json.load(open(f"{STAGE}/mcp_discovery_{TODAY}.json", encoding="utf-8"))
cands = disc["candidates"]
prev = json.load(open(f"{STAGE}/alpha_search_route_20260620.json", encoding="utf-8"))
prev_by_id = {p["id"]: p for p in prev.get("papers", [])}
prev_fca = {f["id"]: f for f in prev.get("factor_candidates_all", [])}

# 신규 14편 라우팅 (id > 2606.20485). reason 한국어, factor_candidate 정직.
NEW = {
 "2606.26031": ("skip", False, None, "기하볼록 수익위험측도 on AM-대수 — 위험측도 공리론(추상 함수해석). 종목신호·구성법 아님"),
 "2606.25696": ("optimizer", False, None, "2단계 ESG long-short 포트최적화(TODIMSort+MEREC 다기준가중) — 포트 구성/가중법. ESG=alt-data라 팩터불가, 가중방법론만 연료"),
 "2606.25007": ("skip", False, None, "디지털뱅킹 사기탐지(멀티스트림 트랜잭션 Transformer) — 범위밖"),
 "2606.24019": ("skip", False, None, "시장충격 square-root law (AAPL ITCH tick, 0.5B events) — 마이크로구조/intraday. 범위밖"),
 "2606.23596": ("risk", False, {"name":"market_body_tail_leg","def":"시장포트를 동적 가치가중 body/tail leg로 분해(SDF 가격오차 vs maxSharpe)","novel":True,"kr_feasible":False,"verdict":"uncertain","confidence":"low"},
                "시장 body/tail 분해 팩터모델 검정(SDF·Sharpe·CRSP) — 자산가격/팩터구조. body/tail은 시장수준 분해라 per-stock 횡단면신호 아님(uncertain)"),
 "2606.23492": ("regime", False, None, "연속 HMM 주식수익 heavy-tail emission family + regime-conditional — 국면탐지/합성수익 생성기"),
 "2606.23367": ("optimizer", False, None, "Asymmetry PRISM CPU/GPU 포트최적화 엔진(turnover/exposure/exclusion/tax 제약, deadline-bounded 리밸) — 최적화 엔진/구현"),
 "2606.23337": ("skip", False, None, "이더리움 Pectra 업그레이드 스테이킹 보상 복리 — 크립토. 범위밖"),
 "2606.23032": ("skip", False, None, "IPO Finance Agent — LLM 금융분석 에이전트 평가(Finance Agent v2 이후). LLM 벤치/에이전트. 범위밖"),
 "2606.22884": ("risk", False, None, "Universal VaR superadditivity — 중꼬리 손실서 VaR 초가법성(모든 확률수준). 위험집계 방법론(리스크모델 주의)"),
 "2606.22719": ("alpha", False, {"name":"llm_nowcast_factor_rank","def":"결정시점 real-time nowcast를 입력으로 leakage-controlled equity factor ranking(7B RAG LLM)","novel":False,"kr_feasible":False,"verdict":"infeasible","confidence":"medium"},
                "Leakage-aware LLM 예측 벤치 + 결정시점 nowcast로 equity factor ranking — PIT 팩터랭킹 개념(우리 PIT규율과 정합). 신호=LLM/매크로nowcast라 alt-data, kr_feasible 불가"),
 "2606.22162": ("risk", False, None, "다섹터 부도카운트 시간 조대화(coarse-graining) → posterior 내재 코퓰라 — 의존구조/코퓰라 모델(credit 소스 주의, 방법론만)"),
 "2606.21515": ("skip", False, None, "ZOC-TN 경계질량 비례응답 검열변환모델(0/1 mass) — 통계방법(recovery/LGD류 적용). 종목 횡단면신호 아님"),
 "2606.20903": ("optimizer", False, None, "위험민감 투자관리 RL(자유에너지-엔트로피 쌍대성, 벤치마크 자산배분) — RL 배분 방법론"),
}

papers = []
new_ids = []
unmatched = []
for c in cands:
    cid = c.get("arxiv_id") or c.get("raw",{}).get("id","")
    title = c.get("title","")
    if cid in NEW:
        route, krf, fc, reason = NEW[cid]
        papers.append({"title":title,"id":cid,"source":"arxiv","route":route,
                       "kr_feasible":krf,"factor_candidate":fc,"reason":reason})
        new_ids.append(cid)
    elif cid in prev_by_id:
        pp = prev_by_id[cid]
        papers.append({"title":pp.get("title",title),"id":cid,"source":pp.get("source","arxiv"),
                       "route":pp.get("route","skip"),"kr_feasible":pp.get("kr_feasible",False),
                       "factor_candidate":pp.get("factor_candidate"),"reason":pp.get("reason","")+ " [06-20 재사용]"})
    else:
        # discovery에 있으나 06-20 미수록 (창 차이) — 보수적 skip + 플래그
        papers.append({"title":title,"id":cid,"source":"arxiv","route":"skip",
                       "kr_feasible":False,"factor_candidate":None,
                       "reason":"06-20 route 미수록 + 신규목록 외 — 보수적 skip(미분류). 재확인 필요"})
        unmatched.append(cid)

# counts
counts = {r:0 for r in ["alpha","optimizer","risk","regime","skip"]}
for p in papers: counts[p["route"]] = counts.get(p["route"],0)+1

# factor_candidates_all = 34편 중 factor flag 있는 것 (reuse overlap + new)
fca = []
for p in papers:
    fc = p.get("factor_candidate")
    if fc:
        fca.append({"id":p["id"],"name":fc.get("name"),"verdict":fc.get("verdict"),"route":p["route"]})
n_testable = sum(1 for f in fca if str(f.get("verdict","")).lower()=="testable")

out = {
 "date": TODAY, "autorun": 0, "max_alpha": 2,
 "router": "Q-Lead inline (paper_router_prompt v2 STEP1+2, headless 미사용)",
 "counts_by_route": counts,
 "n_papers": len(papers), "n_arxiv": len(papers), "n_curated": 0,
 "n_new_routed": len(new_ids), "n_reused_from_0620": len(papers)-len(new_ids)-len(unmatched),
 "n_factor_candidates": n_testable, "n_factor_flags_total": len(fca),
 "factor_candidates_all": fca,
 "new_paper_ids": new_ids,
 "note": "신규 14편(06-21~26, id>2606.20485) 새 라우팅 + 20편 06-20 재사용. testable 신규=0(신선 KR 횡단면 알파 희귀). p_index/ReSGA는 이미 처리·QUAR(done).",
 "papers": papers,
}
json.dump(out, open(f"{STAGE}/alpha_search_route_{TODAY}.json","w",encoding="utf-8"), ensure_ascii=False, indent=2)

# mode_queue = 신규 delta만 (dispatch 재소비 방지)
mq = {"date":TODAY,"source":"06-26 신규 14편 delta","optimizer":[],"risk":[],"regime":[]}
for cid in new_ids:
    route, krf, fc, reason = NEW[cid]
    if route in ("optimizer","risk","regime"):
        title = next((p["title"] for p in papers if p["id"]==cid),"")
        entry = {"title":title,"id":cid,"source":"arxiv","reason":reason}
        if route=="optimizer": entry["note"]="α̂ 고정 A/B 대상(optimizer-research)"
        mq[route].append(entry)
json.dump(mq, open(f"{STAGE}/mode_queue_{TODAY}.json","w",encoding="utf-8"), ensure_ascii=False, indent=2)

print("=== route_20260626.json ===")
print("counts_by_route:", counts)
print(f"papers={len(papers)} new={len(new_ids)} reused={len(papers)-len(new_ids)-len(unmatched)} unmatched={len(unmatched)}")
print("n_factor_flags_total=",len(fca),"n_testable=",n_testable)
print("factor flags:", [(f["name"],f["verdict"]) for f in fca])
if unmatched: print("UNMATCHED ids:", unmatched)
print()
print("=== mode_queue_20260626.json (신규 delta) ===")
print("optimizer:", [e["id"] for e in mq["optimizer"]])
print("risk:", [e["id"] for e in mq["risk"]])
print("regime:", [e["id"] for e in mq["regime"]])
