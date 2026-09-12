# Strategy Diagnostic Report: RP_AUTO_200206975
Generated: 2026-09-13

## Factor Signal Quality
- **IC Mean:** 0.0682 | **ICIR:** 0.596 | **IC > 0 rate:** 70.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.787 | **Positive rate:** 64.9%
- **3Y Rolling Sharpe (avg):** 0.615

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00489 | **NW t-stat:** 4.428 (significant)
- **Avg Cross-sectional R²:** 0.0594

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 8.92%/yr (t=2.387) (significant) | **Adj R²:** 0.0156

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 54.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.1%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 3)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5331, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
