# Strategy Diagnostic Report: AS_mom6_12_ovn
Generated: 2026-06-05

## Factor Signal Quality
- **IC Mean:** 0.0131 | **ICIR:** 0.086 | **IC > 0 rate:** 55.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.347 | **Positive rate:** 33.5%
- **3Y Rolling Sharpe (avg):** -0.456

## Stress Periods
- **Outperform rate vs BM:** 40.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00061 | **NW t-stat:** 0.447 (not significant)
- **Avg Cross-sectional R²:** 0.0644

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -15.65%/yr (t=-2.950) (significant) | **Adj R²:** 0.2863

## Portfolio Characteristics
- **Avg Sector HHI:** 0.2077 (lower = more diversified)
- **Avg Period Turnover:** 30.5%

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
