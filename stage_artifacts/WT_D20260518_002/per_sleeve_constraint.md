# Per-Sleeve Constraint Validation (WT-D20260518_002)

## Sleeve 1 — STR_1715_AR_on_M4_R05_overlay_PG2 (70%)

| Constraint | Value | Status |
|---|---|---|
| max_names | 20 | PASS (top-20 selected per date) |
| per_name_cap | 0.20 within-sleeve / 0.14 blend-level | PASS (EW 5% × 0.70 = 3.5% blend) |
| Σw within sleeve | 1.0 | PASS |
| long-only | weights ≥ 0 | PASS |
| production_retain | Iter31 ub=0.20 strict (lro_sha frozen) | PASS — lro_sha ad3d44... preserved |
| dates with n=20 | 268/268 | PASS |

## Sleeve 2 — TSMOM ETF rotation 8 assets (15%)

| Constraint | Value | Status |
|---|---|---|
| max_assets | 8 | PASS |
| per_asset_cap | 0.30 within-sleeve / 0.045 blend-level | PASS (enforced via iterative clip+renormalize) |
| Σw within sleeve | 1.0 | PASS |
| long-only | weights ≥ 0 | PASS |
| pre-enforce max | observed alpha-stage 0.2 | enforce step required |
| post-enforce max | 0.2 | PASS |

ETF universe (8): KODEX_200, TIGER_SP500_H, KODEX_GOLD_H, KODEX_UST10Y_H, KODEX_200_UST_composite, KODEX_KR_REIT, KODEX_200_LV, TIGER_SHORT_TERM (cash default).

## Sleeve 3 — KR_10y_bond KODEX_KTB10Y_A148070 (15%)

| Constraint | Value | Status |
|---|---|---|
| single_asset | A148070 | PASS |
| weight within sleeve | 1.0 | PASS |
| blend-level | 0.15 | PASS |
| long-only | weight ≥ 0 | PASS |

## AX-007 multi-sleeve exemption verify

- Exception #1 (multi-sleeve) — Hybrid 3-sleeve composition (L-279 precedent retain) qualifies automatically.
- AX-007 EXEMPT (alpha_package + risk_package + this optimizer stage consistent).

## Final admissible schedule integrity

- Total instruments per date: 29 (20 + 8 + 1)
- Σw_target per date: 1.0 ± 1e-10 ✓
- Dates with sleeve breakdown S1=20, S2=8, S3=1 invariant: PASS (268/268)

