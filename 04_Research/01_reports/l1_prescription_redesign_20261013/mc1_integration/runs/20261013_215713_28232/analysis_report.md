# Strategy Diagnostic Report: MC1_INTEG_cond_mat_0410079_ALL_HYG_defaults
Generated: 2026-10-13

## Factor Signal Quality
- **IC Mean:** -0.0122 | **ICIR:** -0.138 | **IC > 0 rate:** 44.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.340 | **Positive rate:** 54.0%
- **3Y Rolling Sharpe (avg):** 0.121

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00109 | **NW t-stat:** -2.159 (significant)
- **Avg Cross-sectional R²:** 0.0478

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -5.45%/yr (t=-2.020) (significant) | **Adj R²:** 0.6436

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 29.3%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5578, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
