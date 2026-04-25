# Weight Method Selection — WT-D20260425_005
_as_of 2023-11-30, universe 160, n=20 hard, bounds [0.00, 0.15], HHI cap 0.15_

## Selected
**ScoreMerged_MVO_lam2_psi03**  — net_IR 2.091, IR 2.098, AR_a 39.80%, TE_a 18.96%, HHI 0.058

## Rationale
- Selection objective: **net_ir** (turnover-adjusted IR, after 15bps one-way cost).
- Method shopping: 5 candidates across 3 families (classical MVO / risk-parity / tail-aware proxy).
- Cross-family sleeve strategy: 3-sleeve alpha (A/B/C) with pairwise alpha-side TDC 0.10~0.13 (hard threshold 0.40) (Mega Sprint MEGA_03 base-line + confidence-aware MVO overlay).
- Risk side: Σ_full Ledoit-Wolf Oracle (cond=182.55, PSD, AX-002 proxy 0.40%).

## Ranking (PASS only)
1. **ScoreMerged_MVO_lam2_psi03** — net_IR 2.091, IR 2.098, AR_a 39.80%, TE_a 18.96%, HHI 0.058
2. **MinVol_AlphaTilt_CVaRproxy** — net_IR 1.860, IR 1.867, AR_a 40.08%, TE_a 21.47%, HHI 0.058
3. **ERC_AlphaTilt** — net_IR 1.748, IR 1.755, AR_a 40.84%, TE_a 23.27%, HHI 0.055
4. **HRP_AlphaTilt** — net_IR 1.604, IR 1.614, AR_a 26.65%, TE_a 16.51%, HHI 0.055
5. **Sleeve_MVO_50_30_20** — net_IR 1.138, IR 1.147, AR_a 19.41%, TE_a 16.92%, HHI 0.067

## Hard Gates
- n_names == 20: **PASS**
- Σw == 1: 1.000000 (**PASS**)
- long-only: min=0.0309, max=0.1102 (**PASS**)
- HHI: 0.0577 ≤ 0.15 (**PASS**)

## Top-5 Overweights
- A185750
- A084870
- A009270
- A900120
- A245620

## Methodology Notes
- **Sleeve_MVO_50_30_20**: per-sleeve MVO (Slot A/B/C) with confidence-aware FU penalty ψ=0.3, per-sleeve max_names=7, merged into stock-level via request.json sleeve weights (0.50/0.30/0.20). Top-20 sparsify if merged > 20.
- **ScoreMerged_MVO**: confidence-aware MVO on alpha_combined (0.5·A + 0.3·B + 0.2·C) with Σ_full, λ=2.0, ψ=0.3, HHI projection, ±2σ winsor.
- **HRP_AlphaTilt**: López de Prado 2016 HRP on Σ_full → α×confidence tilt (0.5×z_α) → top-20 sparsify.
- **ERC_AlphaTilt**: top-40 pre-selection by α×c → iterative ERC (long-only, max_w cap) → α-tilt → top-20.
- **MinVol_AlphaTilt_CVaRproxy**: MEGA_03 pattern emulation — top-40 pre-selection, inverse-σ core, 0.6×z_α tilt (stronger α signal in presence of regime Σ proxy). AX-002 proxy 0.40%.

## v6.1 Compliance
- **selection_objective**: `net_ir` (Hook enforcement: no `sharpe` alone).
- **confidence propagation**: `mvo_weights(confidence = ...)` native for MVO; other methods use α×c pre-scale.
- **method_shopping_log cap**: 5 ≤ 10 (v6.1 R2-C).
- **Hard Constraint Enforcement**: bounds [0, 0.15], min_names 20, HHI 0.15. Compliant with user mandate.

## Cross-Family Diagnostics
- alpha-side TDC (A-B 0.098, A-C 0.130, B-C 0.111) all ≤ 0.40 — ensemble validity confirmed.
- return-based TDC (0.56~0.78) elevated but structural (KR long-only 90% market beta); alpha-side TDC is primary.
- Regime correlation Crisis 0.843 ≈ Normal 0.892 — diversification preserved across regimes.

## Risk Flags Acknowledged
- RF-R1 Market 90.2% variance: unavoidable for KR long-only mandate. Stock-level bounds 0.15 + HHI 0.15 hedge concentration.
- Top-5 mcap 69.1%: weight cap 0.15 prevents > 3× equal-weight concentration per name.
- Slot C stagflation Inflation_2022 -24.3%: accepted; sleeve weight 0.20 limits portfolio impact to < 5%.

## Monthly Rolling Signal
- `weights_rolling.parquet`: 1840 rows across 92 months (2008-01-31 ~ 2023-11-30).
- Forge downstream: walk-forward backtest with monthly rebalance, 15bps TC, KOSPI200 benchmark.

