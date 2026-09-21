# Strategy Diagnostic Report: RF_PAR_B6_42_3nmax
Generated: 2026-09-21

## Factor Signal Quality
- **IC Mean:** 0.0260 | **ICIR:** 0.126 | **IC > 0 rate:** 55.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.945 | **Positive rate:** 74.1%
- **3Y Rolling Sharpe (avg):** 0.647

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00000 | **NW t-stat:** 0.000 (not significant)
- **Avg Cross-sectional R²:** 0.0000

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 6.86%/yr (t=2.203) (significant) | **Adj R²:** 0.6314

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 9.9%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5336, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
