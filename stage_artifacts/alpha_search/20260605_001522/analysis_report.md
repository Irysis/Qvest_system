# Strategy Diagnostic Report: AS_mom52wlow_ovn
Generated: 2026-06-05

## Factor Signal Quality
- **IC Mean:** 0.0405 | **ICIR:** 0.226 | **IC > 0 rate:** 59.2%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.208 | **Positive rate:** 34.9%
- **3Y Rolling Sharpe (avg):** -0.368

## Stress Periods
- **Outperform rate vs BM:** 20.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00091 | **NW t-stat:** -0.529 (not significant)
- **Avg Cross-sectional R²:** 0.0663

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -14.17%/yr (t=-3.752) (significant) | **Adj R²:** 0.4428

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1415 (lower = more diversified)
- **Avg Period Turnover:** 53.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** NO (overlap: 8690, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
