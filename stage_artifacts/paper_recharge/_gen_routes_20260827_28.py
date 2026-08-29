"""Route generator for 20260827 + 20260828 backlog."""
import json, datetime, os

now_str = datetime.datetime.now().strftime('%Y-%m-%dT%H:%M:%S+0900')

# ──────────────────────────────────────────────────────────────────────────────
# 20260827 PAPERS (21)
# ──────────────────────────────────────────────────────────────────────────────
papers_27 = [
    # ── alpha ──────────────────────────────────────────────────────────────────
    {
        "arxiv_id": "2608.24703",
        "title": "Lead-Lag Relationships in Financial Markets: A Comparison of Multiple Clustering Algorithms",
        "source": "arxiv",
        "route": "alpha",
        "kr_feasible": True,
        "factor_candidate": {
            "name": "lead_lag_mcp_cluster_signal",
            "def": (
                "60거래일 가격 시계열을 MiniRocket-KMeans로 군집화 후 "
                "리더 군집의 t-1 확인 lag 보정 수익률로 팔로워 군집 매수 신호 생성. "
                "리더-팔로워 관계는 Granger 방향성으로 검증, 신호는 t-1 종가 기준 PIT 준수."
            ),
            "novel": True,
            "novel_vs_db": "MiniRocket 기반 lead-lag 군집화 신호는 factor_db 미등재. DTW-lead-lag 시스템과 메커니즘 상이(MiniRocket 변환 공간).",
            "kr_feasible": True,
            "data_required": "RAWDATA daily Close/Ret (2005-). 옵션/alt-data 불필요.",
            "verdict": "testable",
            "confidence": 0.55
        },
        "reason": (
            "MiniRocket-KMeans 군집화로 lead-lag 관계를 식별해 팔로워 매수. "
            "KR 가격 데이터만으로 PIT 구현 가능. 원논문 MDD=-63.9%는 KR 고정 축 "
            "25종목+15bps 환경에서 개선 여지. lead leg long-only 사상 적합. SR=0.866."
        )
    },
    {
        "arxiv_id": "2608.22768",
        "title": "The Loop-Gain Matrix: Coupled Rebalancing Feedback and the Blind Spots of Scalar Stability Monitoring",
        "source": "arxiv",
        "route": "alpha",
        "kr_feasible": True,
        "factor_candidate": {
            "name": "letf_closing_displacement_reversal",
            "def": (
                "국내 레버리지 ETF 일 마감 리밸런싱 규모(공시 NAV 기반)를 추정해 "
                "수신 종목(receiver)의 종가 이탈(closing displacement)을 측정. "
                "이탈이 큰 종목의 다음날 역방향(리버설) long 신호. "
                "신호는 전일(t-1) ETF NAV 공시 기준 PIT 준수."
            ),
            "novel": True,
            "novel_vs_db": "LETF 리밸런싱 전달 기반 종가 리버설은 factor_db 미등재. 한국 시장 직접 실증 있음(SK하이닉스→삼성전자, DiD z=-2.82, p=0.0055).",
            "kr_feasible": True,
            "data_required": "RAWDATA daily Close/Open/Ret + ETF 일별 NAV/AUM 공시(공개 데이터, KRX 또는 ETF운용사).",
            "verdict": "testable",
            "confidence": 0.65
        },
        "reason": (
            "KR LETF 에피소드에서 직접 실증(2026). ETF 리밸런싱 피드백이 수신 종목 종가를 이탈시키고 "
            "다음날 리버설. 한국 시장 KSE 마감 단일 venue에서 효과 집중. "
            "Samsung Electronics closing 이탈 분산의 약 41%가 SK Hynix LETF 전달분. ETF NAV 공시 데이터는 공개 정보."
        )
    },
    # ── optimizer ──────────────────────────────────────────────────────────────
    {
        "arxiv_id": "2608.23393",
        "title": "KellyBoost: Growth-Optimal Portfolio Construction with Gradient-Boosted Trees",
        "source": "arxiv",
        "route": "optimizer",
        "kr_feasible": True,
        "factor_candidate": None,
        "reason": "XGBoost softmax 출력이 직접 포트폴리오 비중. 목적함수 = -log(1+wy). Kelly-optimal 비중 산출기. 신호 없음, 비중 방법론.",
        "mode_queue_meta": {
            "method_type": "kelly_growth_optimal_xgboost",
            "shrinkage_builtin": "implicit_via_regularization",
            "screen_priority": "우선",
            "screen_priority_reason": "Kelly criterion XGBoost 직접 구현. closed-form gradient/Hessian. 기존 EW/MVO 대비 growth-optimal 목표 차별화. QEPM 비중 방법론 후보."
        }
    },
    {
        "arxiv_id": "2608.24449",
        "title": "Generalizing Markowitz Portfolio Optimization by a Quadratic Risk Measure",
        "source": "arxiv",
        "route": "optimizer",
        "kr_feasible": True,
        "factor_candidate": None,
        "reason": "임의 SPD 행렬로 Markowitz 확장. closed-form efficient frontier/tangency. 거래비용·공분산 정규화·팩터 모델 통합. Optimizer 확장 방법론.",
        "mode_queue_meta": {
            "method_type": "generalized_markowitz_quadratic_risk",
            "shrinkage_builtin": "yes_via_regularization_term",
            "screen_priority": "우선",
            "screen_priority_reason": "거래비용 quadratic penalty 내포. tangency != max-SR 신규 기하 현상. closed-form 공식 제공."
        }
    },
    # ── risk ───────────────────────────────────────────────────────────────────
    {
        "arxiv_id": "2608.23808",
        "title": "Equity Strategy Backtesting: Luck or Edge? The MinervaScore as a Statistical Robustness Grade",
        "source": "arxiv",
        "route": "risk",
        "kr_feasible": True,
        "factor_candidate": None,
        "reason": "DSR+PBO+SPA+MTRL+레짐안정성 결합 후검증 등급 시스템. AUROC 0.989(합성). 실시장 forward rho=0.013(무의미). 백테 과적합 검증 레이어 도구.",
        "mode_queue_meta": {
            "use_case": "post_selection_robustness_grading",
            "components": "DSR+PBO+SPA+MTRL+regime_stability",
            "calibration_records": 359062,
            "screen_priority": "우선",
            "screen_priority_reason": "5개 검증 지표 통합 0-100 점수화. KR 백테 과적합 검증에 직접 적용 가능. 실시장 forward 예측력은 없음 — 검증 레이어 역할."
        }
    },
    {
        "arxiv_id": "2608.23944",
        "title": "Bulk Phase Transition and Edge Behavior in Temporally Correlated Random Matrices",
        "source": "arxiv",
        "route": "risk",
        "kr_feasible": True,
        "factor_candidate": None,
        "reason": "AR(1)/power-law 시간 상관 무작위 행렬 스펙트럼 분포. gamma_c=0.5 임계점. 공분산 추정 이론적 기반 확장.",
        "mode_queue_meta": {
            "use_case": "covariance_spectral_analysis",
            "correlation_type": "temporal_AR1_powerlaw",
            "critical_exponent": 0.5,
            "screen_priority": "후순위",
            "screen_priority_reason": "이론 결과. KR 공분산 추정 개선에 간접 기여. 직접 구현 레시피 미제공."
        }
    },
    {
        "arxiv_id": "2608.20842",
        "title": "Rethinking Synthetic Scenario Realism: Compatibility, Not Fidelity, Drives Hedging Performance",
        "source": "arxiv",
        "route": "risk",
        "kr_feasible": True,
        "factor_candidate": None,
        "reason": "합성 시나리오 평가 — fidelity 아닌 compatibility(전략-생성기 정렬)가 헤징 성과 결정. 스트레스 테스트/시뮬레이션 설계 기준.",
        "mode_queue_meta": {
            "use_case": "stress_test_scenario_design",
            "key_insight": "compatibility_over_realism",
            "screen_priority": "후순위",
            "screen_priority_reason": "헤징 전략 전용. QEPM 롱온리 백테 스트레스 시나리오 적용은 간접적."
        }
    },
    {
        "arxiv_id": "2608.20727",
        "title": "A Multiscale Ball Test for Conditional Mean Independence",
        "source": "arxiv",
        "route": "risk",
        "kr_feasible": True,
        "factor_candidate": None,
        "reason": "다중 스케일 볼 조건부 평균 독립 검정. KR 월별 금융 데이터 전체샘플 기각 사례 포함. 알파 신호 비선형 구조 검증 도구.",
        "mode_queue_meta": {
            "use_case": "signal_nonlinearity_validation",
            "data_type": "monthly_financial_panel",
            "screen_priority": "우선",
            "screen_priority_reason": "cross-fitted residual 검정으로 동월 look-ahead 제거. KR 월별 패널에 직접 적용 가능."
        }
    },
    # ── regime ─────────────────────────────────────────────────────────────────
    {
        "arxiv_id": "2608.22864",
        "title": "From Exponential to Polynomial: An Exact Filter for High-Dimensional MSM Models",
        "source": "arxiv",
        "route": "regime",
        "kr_feasible": True,
        "factor_candidate": None,
        "reason": "MSM 정확 필터 계산복잡도 O(D^k)→O(k^D) 감소. KR 변동성 레짐 식별에 MSM 모델 실용화 가능.",
        "mode_queue_meta": {
            "use_case": "volatility_regime_identification",
            "model": "MSM_exact_filter",
            "complexity_reduction": "O(D^k) to O(k^D)",
            "screen_priority": "우선",
            "screen_priority_reason": "MSM 레짐 식별 계산 장벽 제거. KR KOSPI200 변동성 레짐 분류에 직접 적용."
        }
    },
    # ── skip ───────────────────────────────────────────────────────────────────
    {
        "arxiv_id": "2608.24786",
        "title": "Harvesting the Volatility Risk Premium: A Learning-to-Rank Approach",
        "source": "arxiv", "route": "skip", "kr_feasible": False, "factor_candidate": None,
        "reason": "SPXW 0DTE 옵션 데이터(1분 해상도 마진 요건) 필요. KR 개별종목 0DTE 옵션 없음."
    },
    {
        "arxiv_id": "2608.23416",
        "title": "The Axiomatic Trader: Latent Regularity, Information Budgets, and the Canonical Form of a Quantitative Investment System",
        "source": "arxiv", "route": "skip", "kr_feasible": False, "factor_candidate": None,
        "reason": "순수 이론 프레임워크(5개 상수 선언). 구현 가능한 신호 없음."
    },
    {
        "arxiv_id": "2608.22852",
        "title": "Your AI, On a Dial: Controlling Investment Bias in LLMs with a Single Neuron",
        "source": "arxiv", "route": "skip", "kr_feasible": False, "factor_candidate": None,
        "reason": "LLM 뉴런 개입 기법. KR RAWDATA/factor_db만으로 신호 생성 불가."
    },
    {
        "arxiv_id": "2608.22497",
        "title": "Reflexivity from Hierarchical Causality",
        "source": "arxiv", "route": "skip", "kr_feasible": False, "factor_candidate": None,
        "reason": "반사성 이론 논문. 구현 신호 없음."
    },
    {
        "arxiv_id": "2608.24871",
        "title": "NatPar: Natural Parametric Modeling",
        "source": "arxiv", "route": "skip", "kr_feasible": False, "factor_candidate": None,
        "reason": "자연재해 파라메트릭 보험 모델. KR 주식 시장 무관."
    },
    {
        "arxiv_id": "2608.24582",
        "title": "findr: Transparent and Fair Credit Risk Decisions through Semi-Structured Regressions",
        "source": "arxiv", "route": "skip", "kr_feasible": False, "factor_candidate": None,
        "reason": "신용 리스크 모델링. KR 주식 유니버스 무관."
    },
    {
        "arxiv_id": "2608.24206",
        "title": "Capital allocation on decentralized lending platforms",
        "source": "arxiv", "route": "skip", "kr_feasible": False, "factor_candidate": None,
        "reason": "DeFi 렌딩 플랫폼(Morpho/USDC/WETH). KR 주식 시장 무관."
    },
    {
        "arxiv_id": "2608.23915",
        "title": "Equilibrium in closed constant-function market maker economies",
        "source": "arxiv", "route": "skip", "kr_feasible": False, "factor_candidate": None,
        "reason": "DeFi CFMM 이론. KR 주식 시장 무관."
    },
    {
        "arxiv_id": "2608.23274",
        "title": "The Physical Crash Frontier: What Finite Option Quotes Can and Cannot Reveal",
        "source": "arxiv", "route": "skip", "kr_feasible": False, "factor_candidate": None,
        "reason": "SPX 옵션 호가 기반 충돌 확률 추정. 옵션 데이터 필요."
    },
    {
        "arxiv_id": "2608.22703",
        "title": "Diagonal Frog meets ADI: trading matrix exponentials for rational maps in the Fokker-Planck equation",
        "source": "arxiv", "route": "skip", "kr_feasible": False, "factor_candidate": None,
        "reason": "Fokker-Planck 수치해석 방법론. 트레이딩 신호 없음."
    },
    {
        "arxiv_id": "2608.22620",
        "title": "WSVI: A Dimensionless Shape Family for Implied Volatility and Its Static No-Arbitrage Structure",
        "source": "arxiv", "route": "skip", "kr_feasible": False, "factor_candidate": None,
        "reason": "내재변동성 곡면 모델. 옵션 데이터 필요."
    },
    {
        "arxiv_id": "2608.21873",
        "title": "Discrete asset pricing under transaction costs and model uncertainty with and without short-sale constraints",
        "source": "arxiv", "route": "skip", "kr_feasible": False, "factor_candidate": None,
        "reason": "이산시간 자산가격결정 이론. 구현 신호 없음."
    },
]

from collections import Counter
counts_27 = Counter(p["route"] for p in papers_27)
testable_27 = [p for p in papers_27 if p.get("factor_candidate") and p["factor_candidate"].get("verdict") == "testable"]

route_27 = {
    "date": "20260827",
    "schema_version": "paper_router_v2",
    "generated_at": now_str,
    "counts_by_route": dict(counts_27),
    "n_factor_candidates": sum(1 for p in papers_27 if p.get("factor_candidate")),
    "n_factor_testable": len(testable_27),
    "curated_new_processed": 0,
    "autorun_planned": len(testable_27),
    "autorun_completed": 0,
    "papers": papers_27,
    "factor_candidates_summary": [
        {
            "arxiv_id": p["arxiv_id"],
            "name": p["factor_candidate"]["name"],
            "verdict": p["factor_candidate"]["verdict"],
            "confidence": p["factor_candidate"]["confidence"]
        }
        for p in papers_27 if p.get("factor_candidate")
    ],
    "notes": "BACKLOG 20260827 라우팅. lead-lag 군집(MiniRocket)·LETF closing displacement 리버설 2건 testable. optimizer 2(Kelly/Markowitz)·risk 4·regime 1(MSM)·skip 12."
}

out_27 = "stage_artifacts/paper_recharge/alpha_search_route_20260827.json"
with open(out_27, "w", encoding="utf-8") as f:
    json.dump(route_27, f, ensure_ascii=False, indent=2)
print(f"Written: {out_27}")
print(f"counts: {dict(counts_27)}, testable: {len(testable_27)}")

# ──────────────────────────────────────────────────────────────────────────────
# 20260828 PAPERS (9)
# ──────────────────────────────────────────────────────────────────────────────
papers_28 = [
    # ── alpha ──────────────────────────────────────────────────────────────────
    {
        "arxiv_id": "2608.27156",
        "title": "Traveling Waves in Equity Markets with Rank-Based Entry and Exit",
        "source": "arxiv",
        "route": "alpha",
        "kr_feasible": True,
        "factor_candidate": {
            "name": "rank_based_diversity_weight_momentum",
            "def": (
                "시가총액 순위(rank) 기반 입출 강도를 추정해 하위→상위 순위 이동 속도가 "
                "빠른 종목(rank momentum)을 long. "
                "diversity-weighted 포트폴리오: 순위 개선 상위 N종목을 시가총액 역비례 가중. "
                "신호 = 과거 3개월 rank percentile 변화율(t-1 기준 PIT 준수)."
            ),
            "novel": True,
            "novel_vs_db": "rank-based entry/exit intensity 기반 diversity-weight는 factor_db 미등재. cap-weight 모멘텀과 기전 상이(순위 동학 vs 절대가격).",
            "kr_feasible": True,
            "data_required": "RAWDATA daily Close/시가총액 only(2005-). 옵션/alt-data 불필요.",
            "verdict": "testable",
            "confidence": 0.55
        },
        "reason": (
            "CRSP 실증에서 turnover(rank 이동)가 diversity-weighted 포트폴리오 이득의 대부분을 설명. "
            "KR KOSPI200+KOSDAQ150 순위 동학 적용 가능. 시가총액 데이터만 필요. "
            "long leg: 순위 개선 상위 종목 long-only 사상 적합."
        )
    },
    {
        "arxiv_id": "2608.27076",
        "title": "Tabular Deep Learning for Algorithmic Trading: Cross-Regime Bayesian Optimisation for Equity Signal Generation",
        "source": "arxiv",
        "route": "alpha",
        "kr_feasible": True,
        "factor_candidate": {
            "name": "xgboost_tabnet_regime_robust_ensemble",
            "def": (
                "XGBoost + TabNet rank aggregation 앙상블. 기술적(모멘텀·레버리지·거래량) + "
                "기본적(ROE·PBR·GP/A) 피처 입력. "
                "3개 레짐(상승·하락·횡보)에서 균등한 signal precision을 목표로 Bayesian OP hyperparameter 최적화. "
                "long leg 상위 25종목(short 제외). 신호는 t-1 기준 PIT 준수."
            ),
            "novel": True,
            "novel_vs_db": "cross-regime BO 기반 tabular DL 앙상블은 factor_db 미등재. 레짐-robust 하이퍼파라미터 최적화 차별점.",
            "kr_feasible": True,
            "data_required": "RAWDATA daily Ret/Vol/Close + factor_db 기본적 데이터(ROE/PBR/GP). alt-data 제외.",
            "verdict": "testable",
            "confidence": 0.55
        },
        "reason": (
            "US 대형주: SR=2.44·CAGR=51.26%(L/S). beta~0 순수 선별 알파. "
            "KR: long leg만 추출 → 25종목 long-only. alt-data 없이 tech+fundamental으로 재현 가능. "
            "cross-regime BO가 OOS 안정성 핵심(4분기 모두 random baseline 이상)."
        )
    },
    # ── regime ─────────────────────────────────────────────────────────────────
    {
        "arxiv_id": "2608.25844",
        "title": "Output-Only Identification and Spectral Monitoring of Coupled Feedback Networks with Known Time-Varying Actuation",
        "source": "arxiv",
        "route": "regime",
        "kr_feasible": True,
        "factor_candidate": None,
        "reason": "LETF 피드백 네트워크 spectral radius 추정 — 2608.22768의 식별론 companion. 일별 fund 공시를 known gain으로 사용해 coupling matrix L_t 추정.",
        "mode_queue_meta": {
            "use_case": "letf_feedback_network_monitoring",
            "companion_paper": "2608.22768",
            "data_required": "ETF NAV/AUM daily public disclosure + RAWDATA close",
            "screen_priority": "우선",
            "screen_priority_reason": "LETF 피드백 강도 실시간 모니터링. 2608.22768의 alpha 신호와 결합 시 동적 activation 가능."
        }
    },
    # ── skip ───────────────────────────────────────────────────────────────────
    {
        "arxiv_id": "2608.27374",
        "title": "Distribution-constrained optimal multiple stopping: the Root-type solution",
        "source": "arxiv", "route": "skip", "kr_feasible": False, "factor_candidate": None,
        "reason": "수학적 최적 정지 이론(Skorokhod embedding). 구현 신호 없음."
    },
    {
        "arxiv_id": "2608.27295",
        "title": "A Temporal Multiplex Graph Neural Network for Systemic Risk Transmission in Global Banking",
        "source": "arxiv", "route": "skip", "kr_feasible": False, "factor_candidate": None,
        "reason": "글로벌 은행 CDS 스프레드 + 분기 패널 필요. KR 주식 유니버스(비은행) 적용 불가."
    },
    {
        "arxiv_id": "2608.27229",
        "title": "On the approximation of posterior laws in compound loss models by conditional Wasserstein GANs",
        "source": "arxiv", "route": "skip", "kr_feasible": False, "factor_candidate": None,
        "reason": "보험 손실 복합 모델(자연재해). 주식 시장 무관."
    },
    {
        "arxiv_id": "2608.26837",
        "title": "Interpretable hybrid credit scoring for thin-file and underbanked populations",
        "source": "arxiv", "route": "skip", "kr_feasible": False, "factor_candidate": None,
        "reason": "신용 리스크(아프리카 마이크로파이낸스). KR 주식 유니버스 무관."
    },
    {
        "arxiv_id": "2608.26473",
        "title": "DTD-VAE: Disentangled Temporal Dependencies VAE for Credit Risk Prediction",
        "source": "arxiv", "route": "skip", "kr_feasible": False, "factor_candidate": None,
        "reason": "신용 리스크 VAE. KR 주식 유니버스 무관."
    },
    {
        "arxiv_id": "2608.25223",
        "title": "On the hedging problem in general 1D diffusion markets",
        "source": "arxiv", "route": "skip", "kr_feasible": False, "factor_candidate": None,
        "reason": "PDE 기반 헤징 방법론(1D 확산). 트레이딩 신호 없음."
    },
]

counts_28 = Counter(p["route"] for p in papers_28)
testable_28 = [p for p in papers_28 if p.get("factor_candidate") and p["factor_candidate"].get("verdict") == "testable"]

route_28 = {
    "date": "20260828",
    "schema_version": "paper_router_v2",
    "generated_at": now_str,
    "counts_by_route": dict(counts_28),
    "n_factor_candidates": sum(1 for p in papers_28 if p.get("factor_candidate")),
    "n_factor_testable": len(testable_28),
    "curated_new_processed": 0,
    "autorun_planned": len(testable_28),
    "autorun_completed": 0,
    "papers": papers_28,
    "factor_candidates_summary": [
        {
            "arxiv_id": p["arxiv_id"],
            "name": p["factor_candidate"]["name"],
            "verdict": p["factor_candidate"]["verdict"],
            "confidence": p["factor_candidate"]["confidence"]
        }
        for p in papers_28 if p.get("factor_candidate")
    ],
    "notes": (
        "TODAY 20260828 라우팅. rank-based diversity momentum·XGBoost+TabNet 크로스레짐 앙상블 2건 testable. "
        "regime 1(LETF spectral monitoring, 2608.22768 companion)·skip 6."
    )
}

out_28 = "stage_artifacts/paper_recharge/alpha_search_route_20260828.json"
with open(out_28, "w", encoding="utf-8") as f:
    json.dump(route_28, f, ensure_ascii=False, indent=2)
print(f"Written: {out_28}")
print(f"counts: {dict(counts_28)}, testable: {len(testable_28)}")

# ──────────────────────────────────────────────────────────────────────────────
# mode_queue files
# ──────────────────────────────────────────────────────────────────────────────
def make_mode_queue(date, papers):
    optimizer = []
    risk = []
    regime = []
    for p in papers:
        if p["route"] == "optimizer":
            optimizer.append({
                "arxiv_id": p["arxiv_id"],
                "title": p["title"],
                "kr_feasible": p.get("kr_feasible", True),
                "reason": p.get("reason", ""),
                "meta": p.get("mode_queue_meta", {})
            })
        elif p["route"] == "risk":
            risk.append({
                "arxiv_id": p["arxiv_id"],
                "title": p["title"],
                "kr_feasible": p.get("kr_feasible", True),
                "reason": p.get("reason", ""),
                "meta": p.get("mode_queue_meta", {})
            })
        elif p["route"] == "regime":
            regime.append({
                "arxiv_id": p["arxiv_id"],
                "title": p["title"],
                "kr_feasible": p.get("kr_feasible", True),
                "reason": p.get("reason", ""),
                "meta": p.get("mode_queue_meta", {})
            })
    return {
        "date": date,
        "schema_version": "paper_router_v2",
        "generated_at": now_str,
        "optimizer": optimizer,
        "risk": risk,
        "regime": regime,
        "notes": f"{date} mode queue — optimizer {len(optimizer)}·risk {len(risk)}·regime {len(regime)}"
    }

mq_27 = make_mode_queue("20260827", papers_27)
mq_28 = make_mode_queue("20260828", papers_28)

mq_out_27 = "stage_artifacts/paper_recharge/mode_queue_20260827.json"
mq_out_28 = "stage_artifacts/paper_recharge/mode_queue_20260828.json"
with open(mq_out_27, "w", encoding="utf-8") as f:
    json.dump(mq_27, f, ensure_ascii=False, indent=2)
with open(mq_out_28, "w", encoding="utf-8") as f:
    json.dump(mq_28, f, ensure_ascii=False, indent=2)
print(f"Written: {mq_out_27} (opt={len(mq_27['optimizer'])} risk={len(mq_27['risk'])} regime={len(mq_27['regime'])})")
print(f"Written: {mq_out_28} (opt={len(mq_28['optimizer'])} risk={len(mq_28['risk'])} regime={len(mq_28['regime'])})")
print("DONE")
