# Strategy Diagnostic Report: AS_mom61_top500
Generated: 2026-06-04

## Factor Signal Quality
- **IC Mean:** -0.0003 | **ICIR:** -0.002 | **IC > 0 rate:** 49.8%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.072 | **Positive rate:** 46.4%
- **3Y Rolling Sharpe (avg):** -0.137

## Stress Periods
- **Outperform rate vs BM:** 20.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00034 | **NW t-stat:** 0.273 (not significant)
- **Avg Cross-sectional R²:** 0.0653

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -7.91%/yr (t=-1.427)  | **Adj R²:** 0.3580

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1451 (lower = more diversified)
- **Avg Period Turnover:** 34.3%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** NO (overlap: 8810, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
