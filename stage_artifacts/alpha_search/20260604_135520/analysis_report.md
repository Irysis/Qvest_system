# Strategy Diagnostic Report: AS_mom61_wintest
Generated: 2026-06-04

## Factor Signal Quality
- **IC Mean:** 0.0080 | **ICIR:** 0.049 | **IC > 0 rate:** 54.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.203 | **Positive rate:** 36.1%
- **3Y Rolling Sharpe (avg):** -0.343

## Stress Periods
- **Outperform rate vs BM:** 20.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00054 | **NW t-stat:** 0.451 (not significant)
- **Avg Cross-sectional R²:** 0.0527

## Multi-Factor Alpha
- **Best Model:** N/A | **Alpha:** 0.00%/yr (t=0.000)  | **Adj R²:** 0.0000

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1426 (lower = more diversified)
- **Avg Period Turnover:** 35.4%

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
