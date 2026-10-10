# Strategy Diagnostic Report: UNIV_2608_14014_F
Generated: 2026-10-10

## Factor Signal Quality
- **IC Mean:** -0.0030 | **ICIR:** -0.025 | **IC > 0 rate:** 49.8%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.278 | **Positive rate:** 55.2%
- **3Y Rolling Sharpe (avg):** 0.084

## Stress Periods
- **Outperform rate vs BM:** 25.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00103 | **NW t-stat:** -1.117 (not significant)
- **Avg Cross-sectional R²:** 0.0623

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -4.62%/yr (t=-1.432)  | **Adj R²:** 0.5849

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 88.7%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5341, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
