# Iter 28 SOTA Race — Selected Method: TailRiskParity

**Task ID**: WT-D20260427_013  
**Generated**: 2026-04-27 13:23:03 KST  
**Selection objective**: net_IR (cost-adjusted SR)

## Method Race Result (8 SOTA Methods)

| Method | net_IR | Realized SR | MDD | CVaR_d | TO | Beta | Pass All |
|---|---:|---:|---:|---:|---:|---:|:---:|
| DRO_Wasserstein | 7.311 | 0.613 | -0.546 | 0.0350 | 16.80 | 0.69 | ✗ |
| HERC | 8.315 | 0.534 | -0.355 | 0.0283 | 7.98 | 0.94 | ✗ |
| HRP_TailAware | 8.320 | 0.645 | -0.315 | 0.0276 | 7.72 | 0.92 | ✗ |
| Bayes_Conf_MVO | 7.542 | 0.561 | -0.535 | 0.0340 | 15.60 | 0.67 | ✗ |
| DiffOpt_Proxy | 9.412 | 0.103 | -0.445 | 0.0259 | 11.07 | 0.69 | ✗ |
| MaxDiv | 8.812 | 0.548 | -0.340 | 0.0270 | 6.19 | 0.81 | ✗ |
| TailRiskParity | 8.243 | 0.631 | -0.344 | 0.0286 | 2.13 | 0.94 | ✓ |
| V25b_NegBeta_Cohort | 7.228 | -0.037 | -0.630 | 0.0375 | 18.00 | 0.56 | ✗ |

## Selection Rationale

Selected: **TailRiskParity** (net_IR=8.243).

Selection criterion: max(net_IR) AND pass_to AND pass_mdd AND defensive_sane AND pass_cvar.

## Hard Constraint Compliance

- max_names ≤ 20: ✓ (observed 20)
- weight_bounds [0, 0.20]: ✓ (max 0.0795)
- Σw = 1: ✓ (sum 1.000000)
- long-only: ✓ (min 0.028782)
- TO ≤ 600%: ✓ (observed 2.13×)
- MDD ≤ 45%: ✓ (observed 34.40%)
- CVaR_d ≤ 2.5%: ✓ (observed 2.86%)

## AX-001 v2 4-metric (selected)

- crisis_alpha: 0.9369
- core_mdd_relief: 0.0000
- bad/normal IC ratio: 0.5000
- harvey_t (inherited): 0.3000

## Top Overweights / Underweights

- OW: A029780, A316140, A357780, A012330, A137310
- UW: A205470, A121600, A036930, A144510, A272290
