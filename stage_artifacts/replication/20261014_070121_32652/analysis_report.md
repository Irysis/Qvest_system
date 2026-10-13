# Strategy Diagnostic Report: P3R01_E1_K5
Generated: 2026-10-14

## Factor Signal Quality
- **IC Mean:** -0.0528 | **ICIR:** -0.261 | **IC > 0 rate:** 40.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.178 | **Positive rate:** 33.8%
- **3Y Rolling Sharpe (avg):** -0.324

## Stress Periods
- **Outperform rate vs BM:** 20.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00000 | **NW t-stat:** 0.000 (not significant)
- **Avg Cross-sectional R²:** 0.0000

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -18.27%/yr (t=-3.576) (significant) | **Adj R²:** 0.3932

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 21.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 6574, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
