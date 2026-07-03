import json, os
TODAY="20260619"
base="stage_artifacts/paper_recharge"
disc=json.load(open(f"{base}/mcp_discovery_{TODAY}.json",encoding="utf-8"))
cand=disc["candidates"]

def aid(i): return cand[i]["arxiv_id"]

# ---- arxiv routing decisions (i -> route, kr_feasible, factor, reason) ----
# factor = None or dict(name,def,novel,kr_feasible,verdict,confidence)
A = {
 0:("risk",False,None,"S&P 다일누적수익 tempered Skew-t 분포 적합 — 꼬리분포 모델링(횡단면 종목신호 아님)"),
 1:("skip",False,None,"CAP slope=Bayes 신용스코어 calibration 이론 — 주식선택 무관"),
 2:("risk",False,None,"꼬리별 보장 conformal prediction interval — uncertainty-aware 예측구간(research_philosophy ③), 횡단면 팩터 아님"),
 3:("skip",False,None,"Agentic AI POMDP 모델검증 프레임워크 — LLM 에이전트 거버넌스"),
 4:("skip",False,None,"옵션 포트 Sharpe/Return-VaR 최대화(skew-elliptical t) — 파생상품 포트, KR 범위밖"),
 5:("regime",False,None,"Transformer 지수 1-step 예측(VN30/S&P) — 지수레벨 타이밍, 횡단면 아님"),
 6:("skip",False,None,"Agentic AI 모델리스크 LLM Bayesian filter — 에이전트 거버넌스"),
 7:("risk",False,None,"PHINN persistent homology 희귀사건 시계열 생성 — 시나리오 생성 방법론(생성모델)"),
 8:("alpha",False,None,"가설 중복하 발견 병목 기하이론(A-share 팩터발견 사례) — 우리 axiom 엔진 orthogonal-escape와 정합한 *발견 방법론*이나 구체 팩터 부재"),
 9:("skip",False,None,"LLM이 CFO 역할극으로 business sentiment 예측 — alt-data(설문/LLM), KR 개별종목 비가용"),
 10:("optimizer",False,None,"declining CVaR glidepath TDF 설계(칠레 연금) — CVaR 제약 글라이드패스 배분법"),
 11:("optimizer",False,None,"Schur damping = HRP↔MinVar 보간(1 파라미터) — optimizer 배분법(공간통계 pseudo-likelihood 연결)"),
 12:("optimizer",False,None,"Heuristic Portfolio Optimization(EW/IV/RP/HRP/RA-HRP의 Markowitz 투영) — α̂고정 A/B 대상 배분법"),
 13:("risk",False,None,"fractional Gaussian process composite likelihood 추정 — 장기기억 추정 방법론(공분산/vol)"),
 14:("risk",False,None,"시계열/커브 시나리오 생성 nonparam vs semiparam bootstrap — 스트레스 시나리오 생성"),
 15:("optimizer",False,None,"ambiguous market 학습형 Mean-Variance(robust MVO) — drift 불확실성하 동적 배분"),
 16:("alpha",False,None,"15 deep TS 모델 주식포트 벤치마크(CRSP decile+제약 quad layer) — ML 예측 *방법론 벤치마크*, 단일 신규신호 아님(batch_434 가드: 합성 금지)"),
 17:("risk",False,None,"multivariate reverse stress testing 조건부 프레임 — 역스트레스 시나리오"),
 18:("optimizer",False,None,"Bayesian VAR + Elliptical Black-Litterman(BAVAR-BLED, regime-aware heavy-tail 배분) — TD3 배분 알고리즘"),
 19:("regime",False,None,"성장-방어 sleeve 연속 cash-overlay(slow-tail + V-shape crash brake, VIX/credit/dd 상태) — 국면 cash 오버레이/크래시 브레이크"),
 20:("alpha",False,{"name":"xsec_topological_anomaly_score","def":"종목별 intraday bar Takens delay 임베딩 → BallMapper 그래프 → decoder-conditional VAE 점수(시장+peer 조건부 위상 이상치)","novel":True,"kr_feasible":False,"verdict":"infeasible","confidence":"medium"},
     "횡단면 위상 이상치 점수 intraday 수익예측(S&P 10종목) — 개념은 횡단면이나 intraday tick/Takens 임베딩 필수 → 일별 KR RAWDATA로 불가(infeasible)"),
 21:("alpha",True,{"name":"p_index_fair_downside_insurance","def":"종목별 fair-price put-insurance 비용: δ 목표수익을 만기 T(1주~1개월)에 보장하는 1달러당 보험료. K=S0*(1+δ) 유럽형 put의 공정가(Black-Scholes: S, K, r=FRED/ECOS, σ=과거수익 실현변동성, T)로 합성 — 옵션 *시장데이터 불요*. p-ratio efficiency(저평가/고평가)로 종목 랭킹","novel":True,"kr_feasible":True,"verdict":"testable","confidence":"medium"},
     "p-index = 1달러당 다운사이드 보험료(put 공정가 합성). registry에 put/insurance 팩터 부재(VaR/CVaR/downside와 구별 — 전자는 실현 손실분위, p-index는 forward 옵션공정가). 가격+과거σ+무위험금리로 PIT 합성가능(task 명시 feasible 예시). δ·정규화는 본문 미확인분 medium"),
 22:("risk",False,None,"Structural Matrix AR(volume-volatility-returns 결합동학, MDH) — 대차원 spillover/공분산 구조(volume 팩터는 기존 보유, 신규 횡단면 신호 불명)"),
 23:("alpha",False,{"name":"price_network_centrality","def":"일별 수익 rolling 상관네트워크(Pearson/MI) → MST/PMFG 필터 → 종목별 centrality. KR 일별 RAWDATA로 합성가능","novel":True,"kr_feasible":True,"verdict":"uncertain","confidence":"low"},
     "주가 정보네트워크(인니, MST/PMFG/community) — centrality 팩터는 registry 부재(novel)이나 *본문은 섹터분류 정확도만 검증, 수익예측력 미입증* → uncertain(재구성·미검증, batch_434 가드)"),
 24:("skip",False,None,"PandaAI neuro-symbolic LLM 에이전트 alpha 생성 — 에이전트 인프라"),
 25:("risk",False,{"name":"resga_predicted_ES_sort","def":"153 firm char autoencoder(수백만 파라미터)로 VaR/ES 학습 → size-enhanced decile 정렬","novel":False,"kr_feasible":False,"verdict":"uncertain","confidence":"low"},
     "ReSGA 대형 꼬리위험 모델(VaR/ES, 1926-2023 US) — 주역할 risk. 예측 ES 정렬은 기존 tail 팩터(D08/D25/R05/CVaR)와 부분중복 + 모델 재구성 비현실적 + long-short(롱온리 위배) → uncertain"),
 26:("optimizer",False,None,"Anticipatory Portfolio Optimization(enlarged filtration/horizon forecast/impact 분해 기하) — 배분 이론"),
 27:("skip",False,None,"US 종합채권지수 DL 예측 — 채권/지수레벨, KR 범위밖"),
 28:("skip",False,None,"PortBench LLM 포트운용 벤치마크(6 자산군 QA+5-stage) — 벤치마크/데이터셋"),
 29:("risk",False,None,"forward-looking SVaR GPR-HS(SACS, CCAR/ICAAP 거시시나리오) — 규제 스트레스 SVaR"),
 30:("alpha",False,{"name":"ea_day_multimodal_direction","def":"실적발표일 방향예측: 15 fundamentals+3 technicals+FinBERT 뉴스감성(LSTM/Transformer)","novel":False,"kr_feasible":False,"verdict":"infeasible","confidence":"low"},
     "실적발표일 주가방향 멀티모달 — 핵심 가치는 뉴스감성(FinBERT alt-data)+발표일 이벤트 타이밍. PEAD는 기존 개념(redundant), 뉴스감성=alt-data 불가 → kr_feasible=false"),
}

# ---- curated routing (from tags/summary_ko; factor=None all — canonical/methodology, redundant or non-xsec) ----
# tuple: (route, factor=None, reason)
C = {
 "MAN_AHL_trend_following_whats_not_to_like.pdf":("regime","추세추종/managed futures crisis_alpha — 시계열 추세=국면/오버레이(횡단면 종목팩터 아님; momentum은 registry 보유)"),
 "ACADIAN_machine_learning_in_quant_investing.pdf":("alpha","퀀트 ML 프로세스/피처 규율 — alpha-search 방법론 소스(구체 신규팩터 부재)"),
 "ROBECO_guide_to_factor_investing_global.pdf":("alpha","팩터투자 가이드(value/momentum/low-vol) — 전부 registry 기보유(redundant)"),
 "CFM_convexity_of_trend_following.pdf":("regime","추세추종 볼록성(crisis convexity) — 국면/오버레이 방법론"),
 "SCIBETA_defensive_equity_without_implicit_bets.pdf":("risk","숨은 팩터 베팅 제거한 방어주 구성 — 리스크/구성 규율(편향제거), 저변동성은 registry 보유"),
 "RA_smoother_path_multifactor_smart_beta.pdf":("optimizer","멀티팩터 smart beta 배합 설계 — 다팩터 결합/분산 배분법"),
 "RA_timing_smart_beta.pdf":("regime","상대밸류 기반 팩터 타이밍 — 국면/타이밍(팩터레벨, 횡단면 종목신호 아님)"),
 "RA_ignored_risks_factor_investing.pdf":("risk","팩터 크래시/숨은 꼬리위험 진단 — 리스크 모델(momentum crash 등)"),
 "RA_cost_capacity_smart_beta.pdf":("optimizer","팩터 비용·용량 제약 — cost-aware 구현(implementation discipline)"),
 "GMO_systematic_equity_product_primer.pdf":("alpha","시스템 주식운용 입문(value/quality/momentum) — registry 기보유(redundant)"),
 "GMO_beyond_the_factor_value_investing.pdf":("alpha","밸류 심화(quant+fundamental blend) — value registry 기보유(redundant)"),
 "GMO_no_silver_bullets_in_investing.pdf":("risk","리스크프리미아 framing/주의 — 팩터정의·구현 caution"),
 "DESHAW_market_insights_vol4_no2_20121026.pdf":("skip","시장 불안정성 commentary(2012) — 방법론/팩터 부재"),
 "WINTON_ucits_funds_icav_prospectus_2025.pdf":("skip","펀드 prospectus(전략 분류) — 리서치 아님, 추출가능 팩터 없음"),
 "WINTON_managed_futures_trend_fund_prospectus_2025.pdf":("skip","managed futures 펀드 prospectus — 리서치 아님"),
}

csv_rows=[]
import csv as _csv
with open("02_Infrastructure/config/paper_recharge_sources.csv",encoding="utf-8") as f:
    for row in _csv.DictReader(f):
        csv_rows.append(row)

papers=[]
for i,(route,krf,fac,reason) in A.items():
    papers.append({"title":cand[i]["title"].strip(),"id":aid(i),"source":"arxiv",
                   "route":route,"kr_feasible":krf,"factor_candidate":fac,"reason":reason})

cur_by_file={r["file_name"]:r for r in csv_rows}
for fn,(route,reason) in C.items():
    r=cur_by_file[fn]
    papers.append({"title":r["title"],"id":fn,"source":f"curated:{r['provider']}",
                   "route":route,"kr_feasible":False,"factor_candidate":None,"reason":reason})

from collections import Counter
counts=Counter(p["route"] for p in papers)
counts_by_route={k:counts.get(k,0) for k in ["alpha","optimizer","risk","regime","skip"]}
testable=[p for p in papers if p["factor_candidate"] and p["factor_candidate"]["verdict"]=="testable"]

out={"date":TODAY,"counts_by_route":counts_by_route,
     "n_papers":len(papers),"n_arxiv":len(A),"n_curated":len(C),
     "n_factor_candidates":len(testable),
     "factor_candidates_all":[{"id":p["id"],"name":p["factor_candidate"]["name"],"verdict":p["factor_candidate"]["verdict"],"route":p["route"]} for p in papers if p["factor_candidate"]],
     "papers":papers}
json.dump(out,open(f"{base}/alpha_search_route_{TODAY}.json","w",encoding="utf-8"),ensure_ascii=False,indent=2)

# mode_queue (optimizer/risk/regime)
mq={"date":TODAY,"optimizer":[],"risk":[],"regime":[]}
for p in papers:
    if p["route"] in ("optimizer","risk","regime"):
        item={"title":p["title"],"id":p["id"],"source":p["source"],"reason":p["reason"]}
        if p["route"]=="optimizer": item["memo"]="α̂ 고정 A/B (PG2) 대상 — 가중/배분법"
        mq[p["route"]].append(item)
json.dump(mq,open(f"{base}/mode_queue_{TODAY}.json","w",encoding="utf-8"),ensure_ascii=False,indent=2)

# alpha-search queue: (route=alpha ∧ kr_feasible) OR verdict=testable
asq=[p for p in papers if (p["route"]=="alpha" and p["kr_feasible"]) or (p["factor_candidate"] and p["factor_candidate"]["verdict"]=="testable")]
json.dump({"date":TODAY,"autorun":0,"max_alpha":2,"candidates":asq},
          open(f"{base}/alpha_search_queue_{TODAY}.json","w",encoding="utf-8"),ensure_ascii=False,indent=2)

# curated_routed history (append processed file_names)
hist_path=f"{base}/curated_routed.json"
hist={"processed":[]}
if os.path.exists(hist_path):
    hist=json.load(open(hist_path,encoding="utf-8"))
for fn in C:
    if fn not in hist["processed"]: hist["processed"].append(fn)
hist["last_run"]=TODAY
json.dump(hist,open(hist_path,"w",encoding="utf-8"),ensure_ascii=False,indent=2)

print("counts_by_route:",counts_by_route)
print("n_factor_candidates(testable):",len(testable))
print("factor_candidates_all:",[(p['factor_candidate']['name'],p['factor_candidate']['verdict']) for p in papers if p['factor_candidate']])
print("alpha_search_queue:",[c['id']+' '+(c['factor_candidate']['name'] if c['factor_candidate'] else '') for c in asq])
print("curated newly processed:",len(C))
print("OUT:",f"{base}/alpha_search_route_{TODAY}.json")
