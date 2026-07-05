import json
from collections import Counter
TODAY = "20260705"
d = json.load(open('stage_artifacts/paper_recharge/mcp_discovery_20260705.json', encoding='utf-8'))
C = d['candidates']

R = {
0: ("risk", "Cap-axis integral diagnostic for factor-model pricing-error evaluation on cap-rank subspace; model-evaluation tool, no per-stock signal."),
1: ("alpha", "Kyle lambda + Amihud order-flow signal predicts cross-section of returns (Fama-MacBeth). Stock-selection premium so alpha route."),
2: ("optimizer", "End-to-end differentiable-Sharpe parametric portfolio policy (state to weights) on 16 CME futures; DPL-adjacent weighting methodology."),
3: ("regime", "Real-time onset detection of financial rogue waves (extreme volatility) via nonlinear Schrodinger; crisis-onset timing overlay."),
4: ("skip", "ESG greenwashing Disclosure-Performance Gap on European STOXX firms; ESG alt-data disclosure/emissions, out of KR scope."),
5: ("regime", "Regime-conditional distributional (GAMLSS/ZAGA) comparison of strategies across market conditions; regime-conditional evaluation method (RCMA-adjacent)."),
6: ("risk", "Systematic plausible stress-scenario generation via large-deviations principle; risk stress-testing methodology."),
7: ("skip", "Pareto-efficient insurance with multiple policyholders/insurers; actuarial insurance theory, out of scope."),
8: ("skip", "AI Premium factor built from OpenRouter LLM token-consumption alt-data; AI-beta needs proprietary token data so alt-data, out of KR scope."),
9: ("skip", "Self-protection vs self-insurance under VaR/TVaR; insurance/risk-reduction theory, no portfolio signal."),
10: ("risk", "Output density heads (Gaussian mixture) dominate backbone for fat-tailed return forecasting (CRPS); tail/density forecasting methodology."),
11: ("skip", "Fund2Persona LLM financial-advisor persona framework; LLM agent, out of scope."),
12: ("skip", "CLQT closed-loop benchmark for LLM portfolio-management agents; LLM benchmark, out of scope."),
13: ("skip", "Bayesian governance policy for AI decision-authority delegation; LLM governance, out of scope."),
14: ("risk", "Liquidity audit of algo strategies from trade/price history (Kyle informed/market-maker, Roll implied spread); strategy liquidity-consumption audit."),
15: ("skip", "Shareholder-value vs financial-stability under reduced-form liquidation; corporate-finance/dividend theory, out of scope."),
16: ("regime", "(In)efficient market-state and rough-volatility detection via Grunwald-Letnikov fractional derivative (Hurst self-similarity); market-state detection."),
17: ("optimizer", "Two-stage long-short portfolio: TODIMSort/MEREC multi-criteria + non-convex Omega maximization; weighting/optimization methodology (ESG inputs not KR-feasible)."),
18: ("skip", "Square-root law of market impact on single AAPL via ITCH tick feed; microstructure/tick execution, out of scope."),
19: ("regime", "Continuous HMM for equity returns with heavy-tail emissions + regime-conditional VaR; regime detection + synthetic generator."),
20: ("skip", "Ethereum Pectra staking-reward compounding; crypto, out of scope."),
21: ("skip", "IPO Finance Agent LLM benchmark on SpaceX S-1; LLM benchmark, out of scope."),
22: ("risk", "Construction dependence of factor-model performance (test-asset selection/weighting/rebalancing); factor-model construction caution, no per-stock signal."),
23: ("risk", "Tempered skew-t fit of accumulated multi-day S&P returns; heavy-tail return-distribution modeling."),
24: ("skip", "Belief-at-Risk agentic-AI model risk via LLM-inferred Bayesian state filters; LLM model-risk, out of scope."),
25: ("optimizer", "Mean-variance optimization under drift ambiguity with prior/learning (ambiguity-averse); MVO/Bayesian weighting methodology."),
26: ("optimizer", "BAVAR-BLED: Bayesian-averaging VAR + elliptical Black-Litterman in TD3 for regime/fat-tail-aware allocation; portfolio-optimization methodology."),
27: ("regime", "Continuous cash-overlay filters (slow-tail + V-shape crash-brake + max-cash) over static growth-defensive sleeve, walk-forward; regime/overlay timing (NOTE: max-cash combination already FALSIFIED locally 2026-06-26)."),
28: ("risk", "Structural Matrix Autoregressive model of joint volume/volatility/returns with cross-sectional dependence (MDH); covariance/spillover risk model."),
29: ("optimizer", "Anticipatory portfolio optimization: enriched-model control gap (enlarged filtrations, horizon forecasts, impact); optimization theory incl. impact correction."),
30: ("skip", "Deep-learning forecasting of US aggregate bond index via fractional differencing; bonds, out of KR equity universe."),
31: ("skip", "PortBench correlation-aware LLM portfolio-management benchmark; LLM benchmark, out of scope."),
32: ("risk", "Forward-looking SVaR stress testing under macro scenarios via hybrid GPR-HS; regulatory stress-testing methodology (cf. forward-macro timer settled-null locally)."),
}

FC = {
1: {"name": "kyle_lambda_orderflow", "def": "Kyle (1985) price-impact lambda + Amihud-style illiquidity from daily abs(ret)/volume; signed order-flow variant.", "novel": False, "kr_feasible": True, "verdict": "redundant", "confidence": "high", "note": "Kyle lambda=L11_Kyle_Lambda, Amihud=L01/L09/L10, price-impact=L14 already in DB. Signed order-flow (only novel piece) needs tick-level signed OF so infeasible in KR daily RAWDATA."},
14: {"name": "roll_implied_spread", "def": "Roll (1984) implied effective spread sqrt(-cov(dP_t,dP_t-1)) as per-stock illiquidity.", "novel": False, "kr_feasible": True, "verdict": "redundant", "confidence": "high", "note": "Roll spread=L08_Roll_Spread + L12_PS_Gamma already in DB (L01-L33 liquidity axis saturated)."},
}

papers = []
cnt = Counter()
for i, p in enumerate(C):
    route, reason = R[i]
    cnt[route] += 1
    fc = FC.get(i)
    kr_feas = route == "alpha" or (fc is not None and fc.get("kr_feasible"))
    papers.append({
        "title": p.get("title", "").strip(),
        "id": p.get("arxiv_id"),
        "source": "arxiv",
        "route": route,
        "kr_feasible": bool(kr_feas),
        "factor_candidate": (dict(fc) if fc else None),
        "reason": reason,
    })

n_testable = sum(1 for pp in papers if pp["factor_candidate"] and pp["factor_candidate"]["verdict"] == "testable")
n_redund = sum(1 for pp in papers if pp["factor_candidate"] and pp["factor_candidate"]["verdict"] == "redundant")

out = {
    "date": TODAY, "autorun": 0, "max_alpha": 2,
    "counts_by_route": dict(cnt),
    "n_factor_candidates": n_testable,
    "n_factor_candidates_flagged_redundant": n_redund,
    "curated_new_this_run": 0,
    "papers": papers,
}
json.dump(out, open(f'stage_artifacts/paper_recharge/alpha_search_route_{TODAY}.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print("counts_by_route:", dict(cnt), "| total", sum(cnt.values()))
print("n_testable_factors:", n_testable, "| n_redundant_flagged:", n_redund)

mq = {"date": TODAY, "optimizer": [], "risk": [], "regime": []}
for pp in papers:
    if pp["route"] in ("optimizer", "risk", "regime"):
        e = {"title": pp["title"], "id": pp["id"], "source": "arxiv", "reason": pp["reason"]}
        if pp["route"] == "optimizer":
            e["memo"] = "alpha-fixed A/B: hold current alpha_hat, swap weighting/Sigma method, gate on delta-IR"
        mq[pp["route"]].append(e)
json.dump(mq, open(f'stage_artifacts/paper_recharge/mode_queue_{TODAY}.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print("mode_queue: optimizer", len(mq["optimizer"]), "risk", len(mq["risk"]), "regime", len(mq["regime"]))

cr = json.load(open('stage_artifacts/paper_recharge/curated_routed.json', encoding='utf-8'))
cr["last_run"] = TODAY
cr["new_this_run"] = 0
json.dump(cr, open('stage_artifacts/paper_recharge/curated_routed.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print("curated: 15 already processed, 0 new; last_run ->", TODAY)
