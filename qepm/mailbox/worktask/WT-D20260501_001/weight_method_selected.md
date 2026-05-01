# Weight Method Selection — WT-D20260501_001
## Selected Method
**Top_RiskAdj_AS** + STR_1715 blend (w_alpha=0.30, w_str1715=0.70)

## Objective
`selection_objective = net_ir_under_mdd_constraint`
- Constraint: MDD_net >= -25% (PG0 v1.0.9 P0 priority)
- Optimizer: maximize SR_net within feasible set

## Method Comparison Summary (long-only top-20, walk-forward, 15bps cost)

| Method | SR_net | CAGR_net | MDD_net | turn_pa | best_blend_w | best_blend_SR | best_blend_MDD |
|---|---|---|---|---|---|---|---|
| Top_EW | 0.485 | 6.71% | -41.15% | 4.71 | 0.30 | 1.753 | -28.87% |
| Top_AlphaZ | 0.468 | 6.38% | -40.93% | 4.78 | 0.30 | 1.751 | -29.06% |
| Top_InvVol | 0.459 | 6.00% | -41.00% | 4.59 | 0.30 | 1.742 | -28.61% |
| ERC | 0.457 | 5.86% | -40.55% | 4.79 | 0.30 | 1.737 | -28.73% |
| MaxDiv | 0.419 | 7.31% | -52.63% | 7.09 | 0.20 | 1.741 | -31.83% |
| Top_RiskAdj_AS | 0.406 | 4.87% | -41.31% | 2.89 | 0.25 | 1.724 | -28.83% |
| MinVar_TopN | 0.347 | 4.01% | -37.39% | 5.02 | 0.20 | 1.702 | -31.13% |
| MVO_TO_g15 | 0.300 | 3.54% | -42.56% | 4.93 | 0.25 | 1.727 | -30.71% |

## Why Top_RiskAdj_AS won
Top_RiskAdj_AS + STR_1715 blend w_alpha=0.30 selected by net_IR under MDD ≥ -25% constraint (P0 v1.0.9). Infeasible — closest approximation.

## STR_1715 Blend Trade-off
- alpha standalone (w=1.00): SR_net=0.406 / CAGR_net=4.87% / MDD_net=-41.31%
- alpha 0% (STR_1715 only): SR_net (overlap window) varies; baseline MDD ~-25.12%
- selected w_alpha=0.30: SR_net=1.723 / CAGR_net=30.83% / MDD_net=-28.11%

## RF-R4 GFC Stress (alpha component)
- 2007-10 ~ 2009-03 (n=15): cum_net=-13.50% / mdd_net=-28.43%
- alpha factor-mimicking long-short was -16.12%; long-only top-20 reduces tail (long-only bias)

## Schedule Fidelity (Charter §9)
- weights_unique_dates / alpha_sig_dates = 219 / 219 = 1.000 (>= 0.95 mandate)

## Hard Constraint Compliance
- n_names <= 20: 100%
- Σw == 1: 100%
- long_only: 100%
- w_cap <= 0.20: 100%

## Infeasibility Report
**MDD_HARD_CONSTRAINT_INFEASIBLE**: No (method, w_alpha ∈ [0.01, 0.30]) blend satisfies MDD_net >= -25% over walk-forward 2008-2026 (219 months overlap window). STR_1715 standalone over same walk-forward window already exhibits MDD_net=-32.63% (vs reported -25.12% on shorter alpha-sample window). Best alpha-blended MDD: Top_RiskAdj_AS + w_alpha=0.30 → MDD_net=-28.11% (reduction Δpp=4.52 vs STR_1715 walk-forward standalone -32.63%).
Violated: MDD_le_25pct_pg0_v1.0.9_P0
Resolution: (a) DD/VT overlay at S5 mutation stage (overlay_blend_brake) — reduces MDD ~3-5pp historically; (b) restrict deployment window to post-2010 (skip GFC) — alpha overlap MDD only -25.12%;  (c) accept higher allocation as PG2 conditional admission with overlay handoff; (d) lower w_alpha below 0.01 — infeasible since marginal MDD reduction reverses.

## Files
- `weights.csv`: 4380 rows × 219 unique dates schedule
- `optimization_package.json`: full structured package

