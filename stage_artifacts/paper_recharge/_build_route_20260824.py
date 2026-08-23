import json, datetime

# Done queue IDs
done_ids = {'2608.20020', '2608.16749', '2608.12283', '2608.14323'}

# Previously non-skip routed (redundant)
prev_routed = {
    '2608.20179': ('optimizer', '20260823'),
    '2608.18783': ('optimizer', '20260823'),
    '2608.18022': ('optimizer', '20260823'),
    '2608.17808': ('optimizer', '20260823'),
    '2608.15841': ('optimizer', '20260823'),
    '2608.15667': ('optimizer', '20260823'),
    '2608.18299': ('risk', '20260823'),
    '2608.17481': ('risk', '20260823'),
    '2608.13056': ('risk', '20260823'),
    '2608.12634': ('alpha', '20260820~22'),
    '2608.12251': ('risk', '20260820~22; in mode_queue_20260822'),
}

candidates = [
    ('2608.20304', 'Calibration-Induced Degeneracy in LLM Financial Forecasting: An Audit-Trailed Case Study on Next-Day Market Risk'),
    ('2608.20179', 'Dynamic Portfolio Optimization under CVaR Constraints'),
    ('2608.20020', 'The Reconfiguration Premium: Co-movement Structure as an Unspanned Dimension of the Variance Risk Premium'),
    ('2608.19394', 'Deep-MKV-TS: Path-Dependent McKean-Vlasov Control for Financial Time Series Generation'),
    ('2608.19389', 'Concentrated Liquidity Provision: a Reinforcement Learning Perspective'),
    ('2608.18783', 'When to Sell an Asset? - A Distribution Builder Approach'),
    ('2608.18299', "The Market's Conditioning Representation: Equilibrium, Crowding, and Convention Multiplicity"),
    ('2608.18022', 'Entropic Value-at-Risk portfolio optimization for tempered stable Levy processes'),
    ('2608.17808', 'Self-Consistent Adjoint Policy Iteration for Constrained Dynamic Portfolio Choice'),
    ('2608.17715', 'Communicating Credit Risk with Large Language Models'),
    ('2608.17481', 'A generic nonparametric value-at-risk estimator for high dimensions'),
    ('2608.17363', 'Conservation of Short-term Flows: Signed Optimal Transport'),
    ('2608.16856', 'zLend: A Dual-Scope Cash-Flow Reconstruction Framework for On-Chain Credit Underwriting'),
    ('2608.16842', 'When ratios fall: A dynamic approach to contingent convertibles'),
    ('2608.16749', 'Rough Volatility Across Assets'),
    ('2608.15841', 'Self-Supervised Auxiliary Task Discovery for Stable Reinforcement Learning in Stock Trading'),
    ('2608.15743', 'Behavioral Participating Insurance: Optimal Investment under Probability Distortion and Aspiration Constraints'),
    ('2608.15667', 'Scalable Pontryagin-Guided Adjoint-to-Control Recovery for Constrained Dynamic Portfolio Choice'),
    ('2608.15447', 'Detecting Money Laundering in Rwandan Mobile Money: A Machine Learning Framework'),
    ('2608.15212', 'Is the medium the message? Social disclosure channels and firm risk'),
    ('2608.14859', 'Disclosed Human-Capital Disruption and Firm-Specific Risk'),
    ('2608.14323', 'Dependence-Informed Sparse Neural Architecture for Stock Return Prediction'),
    ('2608.14014', 'Buy the Rumor, Sell the News: When Is News Priced In?'),
    ('2608.13745', 'Dynamic Physical Hedging amid Jump Losses, Reconstruction-Price Uncertainty, Population Interactions'),
    ('2608.13056', 'Simulating Stress Laws under Extremal Dependence: Characterizing What Generative Models Must Preserve'),
    ('2608.12634', 'The Price of Permission: Classification Uncertainty in Constrained Capital Markets'),
    ('2608.12283', 'Large Language Model-Driven Small-Capitalization Trading: Integrating Financial News Sentiment, Macroeconomic Indicators, and Technical Signals'),
    ('2608.12251', 'Regime-Gated Residual Mixture-of-Experts for Cross-Sectional Volatility Forecasting'),
    ('2608.09087', 'Joint Lyapunov Certificates for K-Agent Generative AI Governance: Stochastic Stability, Emergent Ensemble Risk, and Zero-Knowledge Governance Attestation'),
    ('2608.02311', 'AI Governance for Institutional Readiness in Finance'),
    ('2608.00885', 'Optimal Trading of Microstructure Mean Reversion'),
    ('2607.27039', 'Forcing and duality-corrected contracts for volatility control'),
    ('2607.26245', 'OpenMarket: A Synchronized Polymarket-Binance Dataset for High-Frequency Prediction-Market Research'),
]

done_reasons = {
    '2608.20020': 'already backtested (done queue) — comovement_reconfiguration_rate; QUARANTINE 08/23; signal REVERSED, OOS retention -0.926',
    '2608.16749': 'already backtested (done queue) — rough volatility roughness; not a cross-sectional stock-selection signal',
    '2608.12283': 'already backtested (done queue) — LLM small-cap trading (news + macro + technical); alt-data route',
    '2608.14323': 'already backtested (done queue) — MFCF neural score; SKIP_PROHIBITED (v8.4 금지: 평균표적 ML 구성)',
}

skip_reasons = {
    '2608.20304': 'LLM calibration audit for next-day broad-market risk; no cross-sectional stock factor; requires LLM outputs (alt-data)',
    '2608.19394': 'McKean-Vlasov framework for financial scenario generation; risk simulation methodology, not alpha signal',
    '2608.19389': 'DeFi AMM concentrated liquidity (RL); not KR equity alpha context',
    '2608.18783': 'Optimal asset sale timing via distribution builder; mathematical finance, no cross-sectional factor',
    '2608.17715': 'LLM explanation of credit risk model outputs; not return-predictive; alt-data',
    '2608.17363': 'Signed optimal transport theory (math); no empirical equity signal derivable from it',
    '2608.16856': 'On-chain DeFi credit underwriting (zLend); not KR listed equity',
    '2608.16842': 'CoCo bond valuation via jump-diffusion model; derivatives pricing, not equity cross-section',
    '2608.15743': 'Insurance behavioral optimization (probability distortion); not equity factor',
    '2608.15447': 'Rwanda mobile money AML (ML); no KR equity relevance',
    '2608.15212': 'Social disclosure channel -> firm risk via SEC/sustainability reports; requires text alt-data not in KR RAWDATA',
    '2608.14859': 'Human-capital disruption from earnings call NLP; alt-data (transcripts) not available in RAWDATA',
    '2608.14014': 'When news is priced in (AI/LLM); requires news alt-data not in RAWDATA',
    '2608.13745': 'Catastrophe insurance physical hedging (jump diffusion); insurance mathematics, not equity',
    '2608.09087': 'K-agent generative AI governance (Lyapunov certificates); AI governance math, not a trading signal',
    '2608.02311': 'AI governance survey for asset management; no cross-sectional factor',
    '2608.00885': 'Intraday microstructure mean reversion (seconds-scale); requires tick data, infeasible for monthly factor',
    '2607.27039': 'Principal-agent volatility control theory (2BSDEs); continuous-time math, not testable as equity factor',
    '2607.26245': 'Polymarket prediction market + Binance crypto HFT dataset; not KR equity',
}

papers = []
n_redundant_done = 0
n_redundant_prev = 0
n_skip = 0

for arxiv_id, title in candidates:
    if arxiv_id in done_ids:
        papers.append({
            'arxiv_id': arxiv_id,
            'title': title,
            'source': 'arxiv',
            'route': 'skip',
            'kr_feasible': False,
            'factor_candidate': None,
            'reason': done_reasons.get(arxiv_id, 'already processed (done queue)'),
            'verdict': 'redundant',
        })
        n_redundant_done += 1
    elif arxiv_id in prev_routed:
        prev_r, prev_d = prev_routed[arxiv_id]
        papers.append({
            'arxiv_id': arxiv_id,
            'title': title,
            'source': 'arxiv',
            'route': 'skip',
            'kr_feasible': True,
            'factor_candidate': None,
            'reason': f'redundant — already dispatched as {prev_r} on {prev_d}; skip to avoid duplicate queue entry',
            'verdict': 'redundant',
        })
        n_redundant_prev += 1
    else:
        papers.append({
            'arxiv_id': arxiv_id,
            'title': title,
            'source': 'arxiv',
            'route': 'skip',
            'kr_feasible': False,
            'factor_candidate': None,
            'reason': skip_reasons.get(arxiv_id, 'not applicable to KR equity factor research'),
            'verdict': 'infeasible',
        })
        n_skip += 1

n_redundant = n_redundant_done + n_redundant_prev
total = len(papers)

route_out = {
    'date': '20260824',
    'schema_version': 'route_v2',
    'generated_at': '2026-08-24T09:00:00+0900',
    'counts_by_route': {
        'alpha': 0,
        'optimizer': 0,
        'risk': 0,
        'regime': 0,
        'skip': n_skip,
        'redundant': n_redundant,
    },
    'n_factor_candidates': 0,
    'n_factor_testable': 0,
    'curated_new_processed': 0,
    'autorun_planned': 0,
    'autorun_completed': 0,
    'papers': papers,
    'factor_candidates_summary': [],
    'notes': f'All {total} candidates from mcp_discovery_20260824 are redundant or infeasible. {n_redundant_done} in done queue, {n_redundant_prev} previously routed (non-skip). No new alpha/risk/optimizer/regime entries generated.',
}

with open('stage_artifacts/paper_recharge/alpha_search_route_20260824.json', 'w', encoding='utf-8') as f:
    json.dump(route_out, f, ensure_ascii=False, indent=2)

print(f'Written: alpha_search_route_20260824.json')
print(f'Total: {total} | redundant: {n_redundant} (done:{n_redundant_done} prev:{n_redundant_prev}) | skip(infeasible): {n_skip}')

# mode_queue: empty since no new entries
mode_queue_out = {
    'date': '20260824',
    'schema_version': 'paper_router_v2',
    'generated_at': '2026-08-24T09:00:00+0900',
    'optimizer': [],
    'risk': [],
    'regime': [],
    'notes': 'No new papers to dispatch today; all candidates were previously routed or already backtested.',
}

with open('stage_artifacts/paper_recharge/mode_queue_20260824.json', 'w', encoding='utf-8') as f:
    json.dump(mode_queue_out, f, ensure_ascii=False, indent=2)

print('Written: mode_queue_20260824.json')
