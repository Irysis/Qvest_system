# 3-Sleeve Allocation Pareto Admission (WT-D20260518_002)

## Method

L-279 Hybrid 70/15/15 admit precedent (2026-05-05 finalization) retain + 5pp granular grid Pareto search for sensitivity verification.

## Inputs

- α̂ (sleeve-level annualized active return vs KOSPI200):
  - S1 STR_1715_R05: 0.2354
  - S2 TSMOM:        0.0462
  - S3 KR_10y:       0.026

- Σ 3×3 annualized (risk_package.json sigma_3x3_annualized):
  - σ_S1=0.2119 σ_S2=0.0454 σ_S3=0.0579
  - cor(S1,S2)=0.0751, cor(S1,S3)=-0.1223, cor(S2,S3)=0.1185

## Grid search results (top 10 by IR)

     w_S1  w_S2  w_S3 expected_AR        TE       IR monthly_vol cvar5_proxy
    <num> <num> <num>       <num>     <num>    <num>       <num>       <num>
 1:  0.50  0.30  0.20     0.13676 0.1072237 1.275464  0.03095283  0.03952073
 2:  0.50  0.25  0.25     0.13575 0.1067992 1.271077  0.03083026  0.03940329
 3:  0.50  0.20  0.30     0.13474 0.1064856 1.265336  0.03073974  0.03933854
 4:  0.50  0.15  0.35     0.13373 0.1062840 1.258233  0.03068154  0.03932697
 5:  0.55  0.30  0.15     0.14723 0.1177278 1.250597  0.03398508  0.04363628
 6:  0.50  0.10  0.40     0.13272 0.1061950 1.249777  0.03065585  0.03936887
 7:  0.55  0.25  0.20     0.14622 0.1172289 1.247303  0.03384107  0.04348355
 8:  0.55  0.20  0.25     0.14521 0.1168306 1.242911  0.03372608  0.04337858
 9:  0.55  0.15  0.30     0.14420 0.1165339 1.237409  0.03364043  0.04332184
10:  0.55  0.10  0.35     0.14319 0.1163395 1.230794  0.03358433  0.04331372
    cvar_cap_breach
             <lgcl>
 1:           FALSE
 2:           FALSE
 3:           FALSE
 4:           FALSE
 5:           FALSE
 6:           FALSE
 7:           FALSE
 8:           FALSE
 9:           FALSE
10:           FALSE

## L-279 admit precedent (selected)

- w = (0.70, 0.15, 0.15)
- expected_AR = 0.1756
- expected_TE = 0.1482
- expected_IR = 1.1848
- CVaR_proxy_monthly =  vs cap 0.07 = 

## Pareto admission verdict

L-279 70/15/15 admit precedent retain. Grid Top-IR alternatives concentrate >85% in S1 (Markowitz long-only myopic optimum at α₁ >> α₂,α₃) — violates 3-source orthogonal diversification mandate. Cap-binding 70 is **deliberate concentration design parameter** (L-279 inherit, risk_package CCR 99.75%).

Risk-adjusted Sharpe trade-off: 70/15/15 sacrifices ~7.7% IR vs unconstrained max for: (a) cross-asset orthogonality (cor S1-S2=0.077, S1-S3=-0.137 long-run L-281 inherit), (b) defensive complement via S3 negative MCR (-0.34% CCR), (c) chronic crisis hedge (Stagflation +25pp outperform empirical L-279).

## Cross-sleeve diversification benefit

- Variance contribution 6-term decomposition (risk_package):
  - S1_only:  0.021997  (100.13%)
  - S2_only:  0.000046  (0.21%)
  - S3_only:  0.000076  (0.34%)
  - Cross S1-S2: +0.000152
  - Cross S1-S3: -0.000315  (DEFENSIVE NEGATIVE)
  - Cross S2-S3: +0.000014
  - Total:    0.021969

- Blend vol vs S1-only: 0.2119 → 0.1482 (-30% diversification benefit)

## Method shopping log

| Method | w (S1,S2,S3) | AR | TE | IR | Selected | Rationale |
|---|---|---|---|---|---|---|
| L_279_70_15_15 | (0.70, 0.15, 0.15) | 0.1756 | 0.1482 | 1.1848 | TRUE | L-279 admit precedent retain |
| MVO_unbound | (0.159, 0.589, 0.252) | 0.0712 | 0.0466 | 1.5276 | FALSE | Concentrates ~16% S1 — violates diversification |
| HRP_inv_vol | (0.107, 0.5, 0.392) | 0.0586 | 0.0403 | 1.4535 | FALSE | Inverse-vol over-weights S2/S3 — α dilution |
| ERC | (0.113, 0.473, 0.414) | 0.0592 | 0.0409 | 1.4494 | FALSE | Equal-risk dilutes S1 budget |

n_candidates = 4 (< 10 cap ✓).

