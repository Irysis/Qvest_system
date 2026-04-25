# Optimizer Iter 12 — Method Selection Rationale  
## WT-D20260426_005

**Selected**: `LinTilt_Kelly_Overlay_Quarterly`
**Selection objective**: net_ir (R4 P3 hard)

## Method shopping summary (10 candidates)

| Method | netIR | SR | CAGR | MDD | TO | CVaR_d | passTO | passCVaR | selected |
|---|---|---|---|---|---|---|---|---|---|
| LinTilt_Kelly_Overlay_Quarterly | 0.644 | 0.644 | 11.30% | -39.31% | 472% | 2.44% | YES | YES | **YES** |
| MVO_Kelly_Overlay | 0.604 | 0.604 | 13.27% | -55.12% | 871% | 2.97% | NO | NO |  |
| LinTilt_Kelly_only | 0.599 | 0.599 | 12.56% | -50.88% | 828% | 3.03% | NO | NO |  |
| LinTilt15_Kelly_Overlay | 0.582 | 0.582 | 11.72% | -49.59% | 825% | 2.87% | NO | NO |  |
| LinTilt_Kelly_Overlay_FULL | 0.581 | 0.581 | 11.56% | -48.49% | 815% | 2.86% | NO | NO |  |
| LinTilt_only | 0.550 | 0.550 | 10.64% | -43.63% | 774% | 3.01% | NO | NO |  |
| HRP_baseline_Iter5 | 0.543 | 0.543 | 9.62% | -39.85% | 759% | 2.79% | NO | NO |  |
| LinTilt_Overlay_only | 0.530 | 0.530 | 9.69% | -41.49% | 762% | 2.85% | NO | NO |  |
| InvVol_Overlay | 0.530 | 0.530 | 9.24% | -37.14% | 719% | 2.74% | NO | NO |  |
| HRP_Overlay | 0.524 | 0.524 | 8.79% | -37.66% | 748% | 2.65% | NO | NO |  |

## Stack Layer breakdown (selected)

- Layer 1 Linear Tilt: enabled=TRUE, λ=1, κ=0.5
- Layer 2 Kelly fractional: enabled=TRUE, frac=0.5
- Layer 3a DD Brake: enabled=TRUE, avg_scale=0.738, pct_active=49.8%
- Layer 3b VolReg 12%: enabled=TRUE, avg_scale=0.868, pct_active=30.5%
- Layer 3c FM regime cash: enabled=TRUE, avg_cash=21.77%, pct_dates_cash>0=89.7%
- Layer 4 Pooled-Σ fallback: enforced (CRISIS/CAUTION) + max_w 0.10 shrink

## HRP baseline (Iter 5) comparison

- HRP baseline (no overlay): netIR=0.543 SR=0.543 CAGR=9.62% MDD=-39.85%
- Selected vs HRP: ΔnetIR=+0.100, ΔSR=+0.100

## Iter 6 (InvVol_Overlay) comparison

- InvVol_Overlay (Iter 6 STR_1700-style): netIR=0.530 SR=0.530 CAGR=9.24% MDD=-37.14%
- Selected vs Iter 6: ΔnetIR=+0.114

## Hard constraints (compliance)
- max_names = 20 / 20 ✓
- weight_bounds [0, 0.20]: max_observed = 0.2000 ✓
- Σw = 1: max_abs_error = 1.11e-16 ✓
- long_only: min_observed = 0.001217 ✓
- cash overlay cap 0.30: max_observed = 0.3000 ✓
