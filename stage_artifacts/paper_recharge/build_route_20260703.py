import json
TODAY = "20260703"
disc = json.load(open("stage_artifacts/paper_recharge/mcp_discovery_20260703.json", encoding="utf-8"))
c = disc["candidates"]

route_by_idx = {}
for i in [0, 18, 25, 30, 31, 34]: route_by_idx[i] = "optimizer"
for i in [4, 8, 9, 16, 17, 20, 26, 27, 33, 37]: route_by_idx[i] = "risk"
for i in [1, 3, 15, 21, 28, 32]: route_by_idx[i] = "regime"
for i in [2, 5, 6, 7, 10, 11, 12, 13, 14, 19, 22, 23, 24, 29, 35, 36]: route_by_idx[i] = "skip"

new_ids = {"2607.00475", "2606.31475", "2606.31469", "2606.31122", "2606.30779"}

reasons = {
 0: "End-to-end differentiable-Sharpe policy mapping market states to weights on CME futures. Cross-asset FUTURES universe (out of KR equity scope), but the METHOD = parametric portfolio policy / DPL-style weight learning -> optimizer-research A/B vs risk-parity/TSMOM. research_philosophy(4) Direct Portfolio Learning fuel. No per-stock equity factor (futures).",
 1: "Real-time detection of financial rogue waves (extreme onset). Regime/crisis-onset DETECTION method -> regime overlay research. Note predictive crisis-ONSET timing is settled-null in KR (predictive-crisis-timer); routed as analysis-flag (coincident detection), not a new timing bet. No per-stock signal.",
 2: "ESG rating divergence / greenwashing measurement across rating providers. Requires multi-provider ESG rating panels = alt-data absent from KR RAWDATA/factor_db (crossmarket/alt-data ban). No PIT-feasible per-stock factor. skip.",
 3: "GAMLSS/ZAGA regime-conditional distributional comparison of a poly-SVM vs buy-and-hold on S&P500 index. Index-level 2-strategy evaluation methodology -> regime (RCMA / measurement-graduation regime-conditional discipline). No cross-sectional per-stock signal.",
 4: "Generating plausible stress scenarios via large-deviations theory -> risk-research stress/scenario methodology. Scenario generator, not a selection signal.",
 5: "Pareto-efficient insurance with multiple policyholders/insurers/indemnity envs. Actuarial/insurance theory, out of KR equity scope. skip.",
 6: "AI Premium cross-sectional exposure to AI. Requires firm-level AI-exposure text/labels = alt-data, not in KR factor_db. econ.GN. infeasible/skip.",
 7: "Self-protection vs self-insurance decision theory (risk reduction). Insurance/decision theory, no equity selection signal. skip.",
 8: "Hidden dependence and aggregate tail risk under dependence uncertainty (credit-risk application). Distributionally-robust tail aggregation -> risk-research (tail/dependence). No per-stock signal.",
 9: "Output-head (point vs Gaussian vs mixture density) dominates backbone for fat-tailed return forecasting (S&P monthly, walk-forward). Uncertainty-aware/density forecasting methodology -> risk-research (distributional/tail modeling; also informs alpha ML uncertainty head). No specific cross-sectional factor.",
 10: "Fund2Persona: LLM personas from fund disclosure. LLM/agent tooling. skip.",
 11: "CLQT: LLM portfolio-management agent benchmark. LLM benchmark. skip.",
 12: "Bayesian governance policy for AI delegation authority. AI-governance theory. skip.",
 13: "Liquidity-based audit of algo-trading strategies (microstructure/execution). HFT/microstructure. skip.",
 14: "Shareholder value vs financial stability under reduced-form liquidation. Corporate-finance/MF. skip.",
 15: "Grunwald-Letnikov fractional-derivative KS test for rough volatility / (in)efficient market states; Hurst estimator on RV and index prices. Regime/efficiency-state detection -> regime. Per-stock Hurst signals settled-fail in KR (kr-momentum-novel-hunt Hurst FALSIFIED); index/RV-level here -> no fresh factor.",
 16: "Comparative review + decision framework for uncertainty representation in risk management. Risk methodology survey -> risk-research. No signal.",
 17: "Decision-geometry / regret identity for covariance estimation in GMV under heavy tails. Directly a covariance-estimator evaluation -> risk-research (Sigma estimation) with optimizer relevance (GMV). Strong risk methodology fuel.",
 18: "Two-stage decision-support for sustainability-aware long-short portfolio optimization. Weight-construction method -> optimizer-research (long-leg mapping, ESG aside). Optimizer route.",
 19: "Empirical confirmation of square-root market-impact law (US large-cap). Microstructure/impact. skip (execution scope, no route).",
 20: "Body-Tail test of factor models: decompose market into cap-ranked body/tail legs, test spanning (q5/FF3/FF5). Factor-MODEL consistency methodology -> risk-research. Body/tail split = capitalization (existing size axis) -> no NOVEL per-stock factor.",
 21: "Continuous HMM for equity returns with heavy-tail emissions + regime-conditional VaR (SPY walk-forward). Regime model + synthetic generator -> regime (regime detection) / risk (VaR). Routed regime. No cross-sectional selection factor.",
 22: "Ethereum Pectra staking rewards. Crypto. skip.",
 23: "IPO Finance LLM analyst benchmark. LLM benchmark. skip.",
 24: "Leakage-aware benchmarking of LLM macro nowcasts for factor ranking. LLM forecasting benchmark. skip.",
 25: "RL for risk-sensitive investment via free-energy/entropy duality. Weight/allocation RL method -> optimizer-research. Optimizer route.",
 26: "Construction-dependence of factor-model performance (random test-asset portfolios, weighting/holding/rebalance). Factor-model EVALUATION methodology -> risk-research. No selection factor.",
 27: "Tempered skew-t fit to accumulated stock returns. Tail-distribution modeling -> risk-research (tail). No cross-sectional signal.",
 28: "Robust Transformer one-step stock-INDEX forecasting (VN30, S&P) with shifted data augmentation. Index-level timing forecast -> regime (overlay timing). Index level, not cross-sectional.",
 29: "Belief-at-Risk: agentic-AI model risk via LLM Bayesian state filters. LLM/AI risk. skip.",
 30: "Mean-variance optimization in ambiguous markets with learning. Robust MVO weight method -> optimizer-research.",
 31: "BAVAR-BLED: Bayesian-VAR + elliptical Black-Litterman + TD3, regime-aware fat-tailed allocation. Weight-construction (BL) + regime -> optimizer-research (alpha-fixed A/B). Optimizer route.",
 32: "Continuous cash-overlay filters (slow-tail + V-shape crash-brake) with max-cash combination on a static growth-defensive sleeve. Overlay/timing -> regime. NOTE max-cash overlay combination settled-FALSIFIED in KR (maxcash-overlay-combine-falsified); routed regime as analysis-flag only, not re-tested.",
 33: "Structural Matrix-AR for joint volume/volatility/return dynamics (DJIA); finds volatility drives volume (MDH). Structural dependence model -> risk-research. Possible volume-systematicity per-stock signal is UNCERTAIN (paper shows no return-predictive cross-sectional signal; volume/vol factors already in DB) -> not testable, no fabrication.",
 34: "Anticipatory portfolio optimization. Forward-looking weight method -> optimizer-research.",
 35: "Deep-learning forecast of US aggregate BOND index. Bonds/fixed-income. skip.",
 36: "PortBench: correlation-aware LLM portfolio-management benchmark. LLM benchmark. skip.",
 37: "Forward-looking macro stress testing, stable SVaR via hybrid GPR-HS. Risk stress-testing methodology -> risk-research.",
}

papers = []
counts = {"alpha": 0, "optimizer": 0, "risk": 0, "regime": 0, "skip": 0}
for i, x in enumerate(c):
    r = route_by_idx[i]
    counts[r] += 1
    aid = x.get("arxiv_id")
    status = "new" if aid in new_ids else "carried"
    kr_feasible = r in ("optimizer", "risk", "regime")
    papers.append({
        "title": x.get("title", "").strip(),
        "id": aid,
        "source": "arxiv",
        "status": status,
        "route": r,
        "kr_feasible": bool(kr_feasible),
        "factor_candidate": None,
        "reason": reasons[i],
    })

out = {
 "date": TODAY,
 "router_version": "paper_router_v2",
 "sources_summary": {
   "arxiv_candidates_total": len(c),
   "arxiv_new_today": 5,
   "arxiv_carried_prior": 33,
   "carried_note": "33/38 re-surfaced from prior routing days (180-day recency window). Carried papers retain their original route (idempotent) and are NOT re-dispatched; prior mode_queues already consumed them. Only the 5 new ids are queued today.",
   "curated_total_in_csv": 15,
   "curated_new_today": 0,
   "curated_note": "All 15 curated institutional papers already processed (curated_routed.json last_run 20260702). No new curated PDFs to fetch.",
 },
 "counts_by_route": counts,
 "new_today": {
   "ids": sorted(new_ids),
   "by_route": {"optimizer": ["2607.00475"], "risk": ["2606.31122"], "regime": ["2606.31475"], "skip": ["2606.31469", "2606.30779"], "alpha": []},
 },
 "n_factor_candidates": 0,
 "n_factor_testable": 0,
 "factor_mining_note": "STEP2 overlay applied to all 5 new sources + re-checked carried. Zero novel KR-feasible cross-sectional factors. Nearest misses honestly logged: (33) SMAR volume-systematicity = uncertain (no return-predictive cross-sectional signal shown; vol/volume factors already in DB); (15) Hurst/roughness = settled-fail in KR; (20) body/tail = capitalization/size (redundant); (2/6) ESG/AI-premium = alt-data infeasible. batch_434 guard: no synthetic/fallback signal fabricated.",
 "alpha_autorun": {
   "AUTORUN": 1, "MAX_ALPHA": 2, "n_run": 0,
   "reason": "No source qualifies as alpha-search candidate ((route=alpha AND kr_feasible) OR factor.verdict=testable). Today's batch is entirely optimizer/risk/regime methodology + LLM/crypto/insurance/bond skips; no cross-sectional per-stock equity selection signal. Honest null, no fabrication (batch_434 guard).",
 },
 "papers": papers,
}
json.dump(out, open("stage_artifacts/paper_recharge/alpha_search_route_%s.json" % TODAY, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("counts:", counts, "sum:", sum(counts.values()))

mq = {
 "date": TODAY,
 "note": "Only genuinely-new ids queued; 33 carried already consumed by prior paper_research_dispatch.R runs.",
 "optimizer": [{"id": "2607.00475", "title": "End-to-End Parametric Portfolio Policies for Cross-Asset Futures Timing", "memo": "alpha-fixed A/B: differentiable-Sharpe E2E policy (states->weights, DPL-style) vs risk-parity / TSMOM baselines. research_philosophy(4) DPL fuel. Apply to KR equity sleeve weights (not futures)."}],
 "risk": [{"id": "2606.31122", "title": "Generating Plausible Stress Scenarios via Large Deviations", "memo": "Analysis flag: large-deviations stress-scenario generator for risk-research stress module."}],
 "regime": [{"id": "2606.31475", "title": "Real-time identification of the onset of financial rogue waves", "memo": "Analysis flag: coincident extreme-onset detection. CAUTION predictive crisis-onset settled-null (KR) - evaluate as detection not forward timing."}],
 "skip_logged": ["2606.31469 (ESG greenwashing alt-data)", "2606.30779 (insurance Pareto theory)"],
}
json.dump(mq, open("stage_artifacts/paper_recharge/mode_queue_%s.json" % TODAY, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("wrote route + mode_queue for", TODAY)
