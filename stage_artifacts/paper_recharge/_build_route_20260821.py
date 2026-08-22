import json, os

papers_raw = [
    {"i":1,"id":"2608.18783","title":"When to Sell an Asset? - A Distribution Builder Approach","route":"optimizer","reason":"자산 매도 최적 타이밍 - 분포 빌더(목표 수익분포 직접 지정) 기반. alpha-fixed 가중배분 A/B 테스트 대상.","kr_feasible":False,"factor_candidate":None,"mode_q":{"shrinkage_builtin":"no","statistic_order":"<=2nd","screen_priority":"⭐","reason":"분포 표적 지정 자체가 축소 없음; 2차 통계량 의존이나 내장 정규화 부재"}},
    {"i":2,"id":"2608.18299","title":"The Market's Conditioning Representation: Equilibrium, Crowding, and Convention Multiplicity","route":"risk","reason":"표현 선택이 가격 크라우딩 프리미엄 결정 - 위험모델 크라우딩 정의 확장 이론.","kr_feasible":False,"factor_candidate":None,"mode_q":{"shrinkage_builtin":"weak","statistic_order":"<=2nd","screen_priority":"⭐","reason":"이론적 크라우딩 프레임; 추정 구현에 축소 요소 개입 가능하나 논문엔 명시 없음"}},
    {"i":3,"id":"2608.18022","title":"Entropic Value-at-Risk portfolio optimization for tempered stable Levy processes","route":"risk","reason":"EVaR 기반 포트 최적화 - 비정규 tempered stable 분포 꼬리 모델링.","kr_feasible":False,"factor_candidate":None,"mode_q":{"shrinkage_builtin":"no","statistic_order":"tail_quantile","screen_priority":"후순위","reason":"꼬리 통계량(EVaR) 의존 + 축소 미내장 - 실측 3/3 미달 계열과 동일 패턴"}},
    {"i":4,"id":"2608.17808","title":"Self-Consistent Adjoint Policy Iteration for Constrained Dynamic Portfolio Choice","route":"optimizer","reason":"연속시간 제약 포트 선택을 자기일관 adjoint 반복법으로 풀음 - RL 기반 동적 비중 결정.","kr_feasible":False,"factor_candidate":None,"mode_q":{"shrinkage_builtin":"no","statistic_order":"<=2nd","screen_priority":"⭐","reason":"RL 동적 최적화; 축소 미내장이나 제약-포함 정책 개선이 정규화 역할 가능"}},
    {"i":5,"id":"2608.17715","title":"Communicating Credit Risk with Large Language Models","route":"skip","reason":"신용리스크 설명가능성 - KR 주식 횡단면 투자 범위 외.","kr_feasible":False,"factor_candidate":None,"mode_q":None},
    {"i":6,"id":"2608.17481","title":"A generic nonparametric value-at-risk estimator for high dimensions","route":"risk","reason":"고차원 비모수 VaR+CVaR 추정기 - 내장 차원축소로 공분산 추정 개선.","kr_feasible":False,"factor_candidate":None,"mode_q":{"shrinkage_builtin":"yes","statistic_order":"tail_quantile","screen_priority":"⭐","reason":"내장 차원축소(비모수) = 암묵적 shrinkage; 단 꼬리 통계 의존으로 우선순위 조건부"}},
    {"i":7,"id":"2608.17363","title":"Conservation of Short-term Flows: Signed Optimal Transport","route":"risk","reason":"서명 최적수송 이론 프레임 - 자금흐름 보존법칙 기반 리스크 정량화.","kr_feasible":False,"factor_candidate":None,"mode_q":{"shrinkage_builtin":"no","statistic_order":"<=2nd","screen_priority":"후순위","reason":"이론 프레임, 축소 없음. 실제 구현 경로 불명확"}},
    {"i":8,"id":"2608.16856","title":"zLend: A Dual-Scope Cash-Flow Reconstruction Framework for On-Chain Credit Underwriting","route":"skip","reason":"블록체인 온체인 신용 - 암호화폐/DeFi, KR 주식 범위 외.","kr_feasible":False,"factor_candidate":None,"mode_q":None},
    {"i":9,"id":"2608.16842","title":"When ratios fall: A dynamic approach to contingent convertibles","route":"skip","reason":"CoCo 채권 가격결정 - 채권/파생상품, KR 주식 범위 외.","kr_feasible":False,"factor_candidate":None,"mode_q":None},
    {"i":10,"id":"2608.16749","title":"Rough Volatility Across Assets","route":"risk","reason":"3926개 미국 주식 Hurst 지수 실증 - 개별주식 변동성 거칠기 계량화. route=risk이나 testable 팩터 내장.","kr_feasible":True,"factor_candidate":{"name":"VOL_HURST","def":"일별 실현변동성(일간 로그수익률 제곱)의 rolling 252일 Hurst 지수(R/S 분석 또는 DFA). 횡단면 단면에서 H 낮은(rough) vs 높은(persistent) 종목의 수익률 차이 검증. 부호: 실증 의존(low-H premium 가설).","novel":True,"kr_feasible":True,"verdict":"testable","confidence":0.80},"mode_q":{"shrinkage_builtin":"no","statistic_order":"higher","screen_priority":"⭐","reason":"Hurst 추정은 고차 자기상관 의존 - rolling window가 사실상 정규화 역할. 실측 전 판단 어려움"}},
    {"i":11,"id":"2608.15841","title":"Self-Supervised Auxiliary Task Discovery for Stable Reinforcement Learning in Stock Trading","route":"alpha","reason":"RL 기반 주식 매매 - SATD로 안정적 정책 학습. 횡단면 종목 선택 RL 전략.","kr_feasible":False,"factor_candidate":{"name":None,"def":None,"novel":None,"kr_feasible":False,"verdict":"infeasible","confidence":0.0,"note":"RL 정책 내부학습 - 단순 팩터 추출 불가. 전체 RL 파이프라인 필요"},"mode_q":None},
    {"i":12,"id":"2608.15743","title":"Behavioral Participating Insurance: Optimal Investment under Probability Distortion and Aspiration Constraints","route":"skip","reason":"보험계약자 최적투자 - 보험계리, KR 주식 범위 외.","kr_feasible":False,"factor_candidate":None,"mode_q":None},
    {"i":13,"id":"2608.15667","title":"Scalable Pontryagin-Guided Adjoint-to-Control Recovery for Constrained Dynamic Portfolio Choice","route":"optimizer","reason":"Paper 4의 확장판 - Pontryagin 원리 기반 제약 포트 choice의 scalable 구현.","kr_feasible":False,"factor_candidate":None,"mode_q":{"shrinkage_builtin":"no","statistic_order":"<=2nd","screen_priority":"⭐","reason":"Paper 4와 동계열 동적 최적화; 확장성 개선이 핵심"}},
    {"i":14,"id":"2608.15447","title":"Detecting Money Laundering in Rwandan Mobile Money: A Machine Learning Framework","route":"skip","reason":"르완다 모바일머니 AML - 신흥국 fintech, KR 주식 범위 외.","kr_feasible":False,"factor_candidate":None,"mode_q":None},
    {"i":15,"id":"2608.15212","title":"Is the medium the message? Social disclosure channels and firm risk","route":"alpha","reason":"공시 채널(SEC/지속가능보고서/재무제표) 선택이 특이적 리스크와 연계 - 공시 채널 팩터화 가능.","kr_feasible":True,"factor_candidate":{"name":"DART_DISCL_CHANNEL","def":"DART 공시의 최초 vs 계속 공시 여부 + 공시 채널 분류(의무/자율). 전년도 동기 대비 채널 전환이 다음달 특이리스크 예측. KR: DART 공시 분류코드 경유.","novel":True,"kr_feasible":True,"verdict":"uncertain","confidence":0.55,"note":"DART 공시분류코드로 채널 구분 가능 여부 미확인 - infra 확인 필요"},"mode_q":None},
    {"i":16,"id":"2608.14859","title":"Disclosed Human-Capital Disruption and Firm-Specific Risk","route":"alpha","reason":"실적발표 컨퍼런스콜 텍스트 -> 인적자본 혼란 측정 -> 특이리스크 예측.","kr_feasible":False,"factor_candidate":{"name":None,"def":None,"novel":None,"kr_feasible":False,"verdict":"infeasible","confidence":0.0,"note":"한국어 실적발표 컨퍼런스콜 NLP 인프라 부재 - alt-data"},"mode_q":None},
    {"i":17,"id":"2608.14323","title":"Dependence-Informed Sparse Neural Architecture for Stock Return Prediction","route":"alpha","reason":"MFCF로 팩터 간 의존구조 추정 -> HNN 아키텍처 생성 - 횡단면 수익률 예측.","kr_feasible":True,"factor_candidate":{"name":"MFCF_CLUSTER_SIGNAL","def":"MFCF로 팩터 클러스터 구조 추정 후 클러스터별 합성신호 생성. KR 팩터DB로 의존구조 추정 가능.","novel":True,"kr_feasible":True,"verdict":"uncertain","confidence":0.50,"note":"전체 MFCF+HNN 훈련 필요 - 단순 팩터 추출 어려움"},"mode_q":None},
    {"i":18,"id":"2608.14014","title":"Buy the Rumor, Sell the News: When Is News Priced In?","route":"alpha","reason":"뉴스 발표 전후 가격 반영 비율 실증 - 공시-수익률 타이밍 팩터.","kr_feasible":True,"factor_candidate":{"name":"DART_PREDISCL_DRIFT","def":"DART 공시일 기준 -5~-1일 누적수익률(사전드리프트) vs +1~+5일 수익률(사후반전) 비율. 사전드리프트 높은 종목 = 정보누출 프록시 -> 사후 저수익 예측.","novel":True,"kr_feasible":True,"verdict":"uncertain","confidence":0.60,"note":"DART 공시 날짜로 구현 가능하나 intraday 공시 시간 불명 시 same-day PIT 리스크(C2/C3)"},"mode_q":None},
    {"i":19,"id":"2608.13745","title":"Dynamic Physical Hedging amid Jump Losses, Reconstruction-Price Uncertainty, Population Interactions","route":"skip","reason":"보험사 재해손실 헤지 - 보험계리/파생, KR 주식 범위 외.","kr_feasible":False,"factor_candidate":None,"mode_q":None},
    {"i":20,"id":"2608.13340","title":"Fee Implied Volatility on Uniswap v3: A DEX Native Proxy and Its Limits","route":"skip","reason":"Uniswap v3 수수료 기반 내재변동성 - 암호화폐/DeFi, KR 주식 범위 외.","kr_feasible":False,"factor_candidate":None,"mode_q":None},
    {"i":21,"id":"2608.13082","title":"LOB-ID: Evaluating Synthetic Market Data by Inception Distances","route":"skip","reason":"LOB 합성 시장데이터 평가 - HFT/마이크로구조, KR 주식 범위 외.","kr_feasible":False,"factor_candidate":None,"mode_q":None},
    {"i":22,"id":"2608.12777","title":"Physical Extinction and Long-Run Pricing under Time-Varying Beliefs","route":"skip","reason":"시변 신념 채권 장기수익 이론 - 채권이론, KR 주식 범위 외.","kr_feasible":False,"factor_candidate":None,"mode_q":None},
    {"i":23,"id":"2608.12634","title":"The Price of Permission: Classification Uncertainty in Constrained Capital Markets","route":"alpha","reason":"샤리아 분류 불확실성이 투자자 기반 변동 -> 수익률 예측 - 분류불확실성 팩터화.","kr_feasible":False,"factor_candidate":{"name":"ESG_CLASS_UNCERTAINTY","def":"다중 ESG 평가기관 간 등급 불일치도를 투자자 기반 변동성 프록시로 사용.","novel":True,"kr_feasible":False,"verdict":"infeasible","confidence":0.0,"note":"다중 ESG 공급사 데이터 미보유"},"mode_q":None},
    {"i":24,"id":"2608.12283","title":"Large Language Model-Driven Small-Capitalization Trading","route":"optimizer","reason":"LLM 불확실성 분해(aleatoric+epistemic)를 공분산 행렬에 직접 주입 - 불확실성 인식 공분산 구성.","kr_feasible":True,"factor_candidate":{"name":"UNCERTAINTY_COV_ADJUST","def":"모델 예측 불확실성을 공분산 보정에 활용하는 구조. LLM 없이 앙상블 분산으로 불확실성 추정 가능.","novel":True,"kr_feasible":True,"verdict":"uncertain","confidence":0.55,"note":"신호 측은 LLM 의존(infeasible); 공분산 보정 구조만 추출하면 optimizer 소스"},"mode_q":{"shrinkage_builtin":"yes","statistic_order":"<=2nd","screen_priority":"⭐⭐","reason":"epistemic uncertainty -> 암묵적 shrinkage; 2차 통계량 기반. 내장 불확실성 정규화 가장 명시적"}},
    {"i":25,"id":"2608.12251","title":"Regime-Gated Residual Mixture-of-Experts for Cross-Sectional Volatility Forecasting","route":"risk","reason":"국면조건부 잔차 MoE로 횡단면 5일 실현변동성 예측(1027개 미국 주식) - 리스크 모델 개선.","kr_feasible":True,"factor_candidate":{"name":"REGIME_RVOL_RESIDUAL","def":"국면 조건부 예측 모델의 횡단면 잔차(예측 초과 실현 변동성). 잔차 낮은 종목 = 리스크 과대평가 -> alpha 기회.","novel":True,"kr_feasible":True,"verdict":"uncertain","confidence":0.45,"note":"전체 MoE 시스템 구현 필요"},"mode_q":{"shrinkage_builtin":"weak","statistic_order":"<=2nd","screen_priority":"⭐","reason":"잔차 MoE는 암묵적 정규화 있음; 변동성(2차 통계) 예측 대상으로 <=2nd"}},
    {"i":26,"id":"2608.12424","title":"AI-Driven Multiscenario Interest Rate Forecasting","route":"regime","reason":"다시나리오 금리 예측(계량모형+AI) - 매크로 레짐 입력신호(금리 국면 예측) 소스.","kr_feasible":True,"factor_candidate":None,"mode_q":None},
    {"i":27,"id":"2608.09087","title":"Joint Lyapunov Certificates for K-Agent Generative AI Governance","route":"skip","reason":"다중 AI 에이전트 거버넌스 안정성 수학 이론 - 투자 팩터 범위 외.","kr_feasible":False,"factor_candidate":None,"mode_q":None},
    {"i":28,"id":"2608.02311","title":"AI Governance for Institutional Readiness in Finance","route":"skip","reason":"금융기관 AI 거버넌스 실무 프레임워크 - 규제/컴플라이언스, 투자 팩터 범위 외.","kr_feasible":False,"factor_candidate":None,"mode_q":None},
    {"i":29,"id":"2608.00885","title":"Optimal Trading of Microstructure Mean Reversion","route":"skip","reason":"초단기 중간가 평균회귀 최적매매 - HFT/마이크로구조 intraday, KR 주식 범위 외.","kr_feasible":False,"factor_candidate":None,"mode_q":None},
    {"i":30,"id":"2607.27039","title":"Forcing and duality-corrected contracts for volatility control","route":"skip","reason":"주인-대리인 볼동성 제어 계약 최적 인센티브(2BSDE) - 계약이론/제어, 투자 팩터 범위 외.","kr_feasible":False,"factor_candidate":None,"mode_q":None},
    {"i":31,"id":"2607.26245","title":"OpenMarket: A Synchronized Polymarket-Binance Dataset","route":"skip","reason":"Polymarket-Binance 동기화 데이터셋(BTC HFT) - 암호화폐/예측시장, KR 주식 범위 외.","kr_feasible":False,"factor_candidate":None,"mode_q":None},
    {"i":32,"id":"2607.25162","title":"Quantum Transformer BSDE Solver via Multi-Layer Fully-Connected Variational Quantum Circuits","route":"skip","reason":"양자 변환기 기반 고차원 PDE 풀이 - 양자컴퓨팅 이론, 실용 투자 범위 외.","kr_feasible":False,"factor_candidate":None,"mode_q":None},
    {"i":33,"id":"2607.19497","title":"The Science and Practice of Trend-Following Systems","route":"alpha","reason":"추세추종 3분류 통합이론 - ARFIMA 자기상관 구조 기반 변동성 표준화 모멘텀 신호.","kr_feasible":True,"factor_candidate":{"name":"ARFIMA_TSMOM","def":"월별 변동성 표준화 수익률(r_t/sigma_t)의 rolling 자기상관 구조 기반 모멘텀. 구현: (1) 종목별 12개월 변동성 표준화 월간 수익률 (2) 분산비 VR(K)=Var(K-period)/(K*Var(1-period)) 추정 (3) VR>1 종목에 12-1 MOM 적용, VR<=1 종목 제외 또는 반전. 해석: VR>1=양의 자기상관=추세 적합=모멘텀 신호 유효.","novel":True,"kr_feasible":True,"verdict":"testable","confidence":0.72},"mode_q":None},
]

def make_route_json(date):
    counts = {"alpha":0,"optimizer":0,"risk":0,"regime":0,"skip":0}
    papers_out = []
    testable_factors = []
    for p in papers_raw:
        counts[p["route"]] += 1
        fc = p["factor_candidate"]
        entry = {"title":p["title"],"id":p["id"],"source":"arxiv","route":p["route"],"kr_feasible":p["kr_feasible"],"factor_candidate":fc,"reason":p["reason"]}
        papers_out.append(entry)
        if fc and fc.get("verdict") == "testable":
            testable_factors.append({"title":p["title"],"factor":fc["name"],"route":p["route"]})
    n_testable = sum(1 for p in papers_raw if p.get("factor_candidate") and p["factor_candidate"].get("verdict") == "testable")
    return {"date":date,"schema_version":"mode_queue_v1","counts_by_route":counts,"n_factor_candidates":n_testable,"testable_factors":testable_factors,"papers":papers_out}

def make_mode_queue(date):
    optimizer, risk, regime = [], [], []
    for p in papers_raw:
        if p["route"] == "optimizer" and p["mode_q"]:
            optimizer.append({"title":p["title"],"id":p["id"],"source":"arxiv",**p["mode_q"]})
        elif p["route"] == "risk" and p["mode_q"]:
            risk.append({"title":p["title"],"id":p["id"],"source":"arxiv",**p["mode_q"]})
        elif p["route"] == "regime":
            regime.append({"title":p["title"],"id":p["id"],"source":"arxiv","screen_priority":"⭐","reason":"매크로 레짐 입력신호 소스"})
    return {"date":date,"schema_version":"mode_queue_v1","generated_at":date+"T000000Z","optimizer":optimizer,"risk":risk,"regime":regime}

os.makedirs("stage_artifacts/paper_recharge", exist_ok=True)
for date in ["20260820","20260821"]:
    with open("stage_artifacts/paper_recharge/alpha_search_route_{}.json".format(date),"w",encoding="utf-8") as f:
        json.dump(make_route_json(date), f, ensure_ascii=False, indent=2)
    with open("stage_artifacts/paper_recharge/mode_queue_{}.json".format(date),"w",encoding="utf-8") as f:
        json.dump(make_mode_queue(date), f, ensure_ascii=False, indent=2)

print("Done")
r = make_route_json("20260821")
print("Counts:", r["counts_by_route"])
print("Testable:", r["testable_factors"])
mq = make_mode_queue("20260821")
print("Opt:", len(mq["optimizer"]), "Risk:", len(mq["risk"]), "Regime:", len(mq["regime"]))
