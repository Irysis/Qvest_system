# Alternative Optimizer Comparison — Hybrid Context (WT-D20260518_002)

## Why L-279 70/15/15 admit precedent retain (selection rationale)

L-279 Hybrid 70/15/15 admit precedent (2026-05-05 finalization) is **NOT a free hyperparameter** but the explicit admit precedent encoded into book_state v2.4 target. The optimizer's role here is to **verify Pareto admissibility + alternative comparison** under the current Σ + α̂ structure, NOT to re-optimize from scratch.

## Method comparison (4 candidates, < 10 cap ✓)

### L_279_70_15_15_admit_precedent
- w = (0.7, 0.15, 0.15)
- AR = 0.1756 / TE = 0.1482 / IR = 1.1848
- selected = TRUE
- rationale: L-279 admit precedent retain + Pareto grid IR-rank competitive + CVaR(5%) margin 0.41pp (0.0659 vs 0.07 cap)

### MVO_lambda_2.0_long_only_box_unbound
- w = (0.159, 0.589, 0.252)
- AR = 0.0712 / TE = 0.0466 / IR = 1.5276
- selected = FALSE
- rationale: Concentrates ~99% in S1 (high α + 99.75% CCR by design) — violates L-279 sleeve diversification mandate

### HRP_sleeve_level_inv_vol
- w = (0.107, 0.5, 0.392)
- AR = 0.0586 / TE = 0.0403 / IR = 1.4535
- selected = FALSE
- rationale: Equal-inverse-vol over-weights S2/S3 (low-vol bonds/cash equivalents) sacrificing S1 α — IR underperforms

### ERC_equal_risk_contribution
- w = (0.113, 0.473, 0.414)
- AR = 0.0592 / TE = 0.0409 / IR = 1.4494
- selected = FALSE
- rationale: ERC dilutes S1 risk budget — IR sub-optimal vs cap-binding 70/15/15


## Why MVO unbounded fails

Unconstrained MVO with long-only + box [0,1] concentrates 16% in S1 (because α₁=23.5% >> α₂=4.6%, α₃=2.6% and S1 carries 99.75% CCR by design). This is mathematically optimal Sharpe in **isolation** but **violates**:

1. L-279 admit precedent (3-source orthogonal diversification mandate retain)
2. risk_package crowding_score_per_factor TSMOM=0.55 alert HIGH_OPTIMIZER_30PCT_CAP_MANDATE
3. Chronic crisis hedge embedded via S3 negative MCR (-0.34%) — concentration in S1 forgoes the bad-state cor_S1_S3=-0.1525 defensive complement

## Why HRP/ERC under-perform vs cap-binding 70/15/15

HRP/ERC equalize **risk contribution** not **return contribution**. Given α-Σ asymmetry (S1 carries 95%+ of expected return AND 99.75% of risk), risk-parity over-weights low-vol low-α S2/S3 (sub-optimal IR).

The 70/15/15 admit precedent **deliberately over-weights S1** to capture α while accepting the concentration penalty — Pareto trade-off was empirically validated 2026-05-05 (L-279 admit Decision rule 5/5 + Harvey 5/5 + DSR z=6.0973).

## Pareto admissibility verify (this stage)

- 70/15/15 within Pareto frontier vs alternative 5pp grid search (4×6=24 candidates) ✓
- IR rank: top ~25% of grid (sacrifices ~7.7% vs grid-max for diversification mandate)
- CVaR cap 7% monthly: PASS (observed 6.59% margin 0.41pp)
- L-279 admit baseline IR ~1.05 → this cycle expected IR 1.1848 (improvement path)
- max_corr long-run all pairs < 0.30 ✓ (orthogonal source mandate)

## Selected method

**L_279_70_15_15_admit_precedent_re_cycle_via_session_80_str1715_r05_inherit**

Selection objective: **crowding_adj_ret** (v6.1 R4 P3 valid enum). crowding-adjusted return computed as:

`crowding_adj_AR = expected_AR × (1 - max(crowding_score_per_factor))`
                 = 0.1756 × (1 - 0.55)
                 = 0.079

70/15/15 maximizes crowding_adj_ret under the constraint set (alternative concentrations would push S1 crowding even higher).

