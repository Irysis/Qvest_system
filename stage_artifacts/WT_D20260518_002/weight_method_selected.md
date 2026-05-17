# Weight Method Selected — WT-D20260518_002

## Selected method

**`L_279_70_15_15_admit_precedent_re_cycle_via_session_80_str1715_r05_inherit`**

## Selection objective

`crowding_adj_ret` (v6.1 R4 P3 enum — net_ir / to_adj_ret / uncertainty_penalty / **crowding_adj_ret**).

`crowding_adj_AR` = 0.079 (≈ 0.1756 × 0.45 crowding discount via TSMOM HIGH 0.55).

## Why this method, not others

| Method | IR | Selected | Why not |
|---|---|---|---|
| L_279_70_15_15 (selected) | 1.1848 | ✓ | L-279 admit precedent retain + Pareto admissible + CVaR cap PASS |
| MVO_unbound | 1.5276 | ✗ | ~16% S1 concentration — violates L-279 mandate |
| HRP_inv_vol | 1.4535 | ✗ | Over-weights low-α S2/S3 — α dilution |
| ERC | 1.4494 | ✗ | Equal-risk over S1 budget dilution |

## Hard constraint compliance

- max_names per sleeve: S1=20 ✓ / S2=8 ✓ / S3=1 ✓
- long-only: all sleeves ✓
- weight_bounds per sleeve: S1 [0, 0.20] ✓ / S2 [0, 0.30] enforce ✓ / S3 N/A single asset
- Σw = 1: per-date 1.0 ± 1e-10 ✓
- AX-007 EXEMPT multi-sleeve exception #1 ✓

## Risk handoff fulfilled (5 mandates)

1. **70/15/15 cap binding** (L-279 inherit baseline): ✓ enforced
2. **Sleeve 2 per-asset cap 30%**: ✓ iterative clip+renormalize enforced
3. **Sleeve 1 within**: max 20 names + [0, 0.20] + Σ=1 + long-only ✓ production retain (Iter31 ub=0.20, lro_sha frozen)
4. **CVaR cap 7% monthly**: ✓ explicit declaration with rationale (observed -6.59% margin 0.41pp PASS)
5. **PG2 mutation v2.3 → v2.4 prep**: ✓ 3-sleeve admissible schedule emitted (effective 2026-06-01)

## Expected metrics

- expected_AR = 0.1756
- expected_TE = 0.1482
- expected_IR = 1.1848
- turnover_blend = 6.0438 (cap 6.0 MARGINAL_BREACH with S1 waiver inherit, POST_DEPLOY_AR_007 T+30 binding)
- estimated_cost = 0.0181 (15bps × 2 round-trip × to_blend)

## Binding constraints

- sleeve_allocation_cap_S1_S2_S3 [70, 15, 15] L-279 inherit
- per_asset_cap_S2 TSMOM 30%
- per_name_target_S1 5% within-sleeve EW
- single_asset_S3 KR_10y A148070
- CVaR_5_monthly_7pct_explicit_relaxation_vs_Codex_2.5_default

## Lineage

- L-279/L-280/L-281: Hybrid 70/15/15 admit precedent direct retain
- L-307: AR overlay inherit precedent  (Sleeve 1)
- L-308~L-313: Session 80 R05 Layer 5 admit (Sleeve 1)
- alpha_package.json (lro_sha frozen ad3d44...)
- risk_package.json (Σ 3x3 PD cond 22.86)
- request.json (cap binding mandate)

