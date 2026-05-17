# 3-Sleeve Sigma Design (WT-D20260518_002)

## Architecture

Hybrid 70/15/15 portfolio variance:
```
σ²_blend = w₁²·σ²_S1 + w₂²·σ²_S2 + w₃²·σ²_S3
        + 2·w₁·w₂·cov(S1,S2) + 2·w₁·w₃·cov(S1,S3) + 2·w₂·w₃·cov(S2,S3)
```

with `w = (0.70, 0.15, 0.15)` and Σ = BΩB' + D structure.

For sleeve-level aggregation: B = I₃ (sleeves are the factors), D = 0₃ (no residual at this level),  
so Σ = Ω = sample sleeve covariance.

## Individual Σ per sleeve (annualized, balanced 135m panel 2015-01 ~ 2026-03)

| Sleeve | Asset | σ_ann | Source |
|--------|-------|-------|--------|
| S1 | STR_1715_AR_on_M4_R05_overlay_PG2 (70%) | 0.2119 | NAV V1 production retain (lro_sha frozen) |
| S2 | TSMOM 8-ETF rotation (15%) | 0.0454 | WT-S20260504_009 inherit, post-inception KOFIA NAV |
| S3 | KR_10y bond ETF A148070 (15%) | 0.0579 | ECOS yield + KOFIA NAV inherit |

Long sample cross-check (256m, S1+S3 only since TSMOM has_ts=FALSE pre-2015):
- σ_S1_long = 0.2160 (close to 135m 0.2119, +1.9% drift)
- σ_S3_long = 0.0629 (close to 135m 0.0579, +8.6% drift)

## Data provenance (v5 학습 strict)

| Data | Source | Real PIT verified |
|------|--------|-------------------|
| r_AR (S1) | WT-P20260505_001/architect_hybrid_returns_full256m.csv ← STR_1715 production NAV V1 (R05 admit, Session 80) | YES (lro_sha frozen) |
| r_TSMOM (S2) | WT-P20260505_001/architect_hybrid_returns_full256m.csv ← WT-S20260504_009 inherit (8 ETF post-inception KOFIA + pre-inception synthetic caveat RF-A1) | PARTIAL (post-2015 real, pre-2015 synthetic) |
| r_KR10y (S3) | WT-P20260505_001/architect_hybrid_returns_full256m.csv ← WT-S20260504_008 ECOS yield + post-2011 KOFIA A148070 real NAV | YES (post-2011 real, pre-2011 synthetic ΔSharpe monotonic decay = conservative inheritance) |

NO ret_comp self-合成. NO `0.70*r1 + 0.15*r2 + 0.15*r3` manual blend in primary Σ — sleeves processed via real PIT inherits + Σ 3x3 directly computed from underlying returns.

## Σ 3x3 (annualized, balanced 135m panel)

```
        S1          S2          S3
S1   0.044891   0.000723   -0.001501
S2   0.000723   0.002064    0.000312
S3  -0.001501   0.000312    0.003357
```

Eigenvalues: [0.04496, 0.00339, 0.00197]  
Condition number: 22.86 (PASS: << 500 threshold)  
Positive Definite: TRUE  
Min eigenvalue: 0.001967 (well above 0 + machine epsilon)

## Method shopping log

| candidate | method | condition | PD | selected |
|-----------|--------|-----------|-----|---------|
| 1 | Sample (balanced 135m, full Pearson) | 22.86 | TRUE | YES |
| 2 | Ledoit-Wolf shrinkage | (not needed: n=135 >> p=3) | N/A | N |
| 3 | Gerber/RMT noise filter | (not needed: p=3 small) | N/A | N |

`candidates_tried = 1, selected = sample`. Rationale: 3-sleeve sleeve-level Σ at N=135 (T/p = 45) is well-conditioned via Sample. Shrinkage adds bias without variance reduction. Within-sleeve Σ (stock-level S1) inherited from STR_1715 production retain (lro_sha frozen, separate estimation domain).

## Hybrid blend variance

- σ²_blend = 0.021969
- σ_blend (annualized) = 0.1482 = 14.82% 
- L-279 admit precedent blend MDD -16.6% retain ~ ann vol consistent

## Variance contribution decomposition

| sleeve | weight² | contribution | % of total | interpretation |
|--------|---------|-------------|-----------|----------------|
| S1 | 0.49 | 0.021997 | 100.12% | dominant (concentrated 70%) |
| S2 | 0.0225 | 0.000046 | 0.21% | negligible (low vol + 15% weight) |
| S3 | 0.0225 | 0.000076 | 0.34% | negligible |
| S1-S2 cross | 2·0.105·cov | 0.000152 | 0.69% | small positive (long-run orthogonal) |
| S1-S3 cross | 2·0.105·cov | **-0.000315** | **-1.43%** | **DEFENSIVE: negative diversification benefit** |
| S2-S3 cross | 2·0.0225·cov | 0.000014 | 0.06% | negligible |
| **TOTAL** | | **0.021969** | **100%** | |

→ S1 dominance is overwhelming (100% variance). S2/S3 effectively provide tail diversification rather than vol reduction.

## MCR / CCR

| sleeve | weight | vol_individual | MCR | CCR | CCR % |
|--------|--------|----------------|-----|-----|-------|
| S1 | 0.70 | 0.2119 | 0.2112 | 0.1479 | **99.75%** |
| S2 | 0.15 | 0.0454 | 0.0058 | 0.0009 | 0.59% |
| S3 | 0.15 | 0.0579 | **-0.0034** | **-0.0005** | **-0.34%** (defensive) |

→ S3 KR_10y has **negative MCR** = adding S3 reduces blend vol (Markowitz hedge).  
→ S2 TSMOM has tiny positive MCR — marginal diversifier.  
→ S1 STR_1715 dominates risk budget at 99.75% — concentration trade-off vs Sharpe.

## Note on Σ 3x3 PD healthy

condition = 22.86 << 500 hook threshold. No shrinkage needed. The 3-sleeve cov is parsimonious (3×3) and well-estimated at T=135 (T/p ≈ 45, sample regime).

## Output

- `stage_artifacts/WT_D20260518_002/covariance.parquet` (3x3 sleeve Σ)
- `stage_artifacts/WT_D20260518_002/factor_covariance.parquet` (= Ω)
- `stage_artifacts/WT_D20260518_002/exposure_matrix.parquet` (= I₃)
- `stage_artifacts/WT_D20260518_002/specific_risk.parquet` (= 0₃)
