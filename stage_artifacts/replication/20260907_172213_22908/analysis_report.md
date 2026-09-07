# Strategy Diagnostic Report: RP_AUTO_170705552
Generated: 2026-09-07

## Factor Signal Quality
- **IC Mean:** 0.0136 | **ICIR:** 0.105 | **IC > 0 rate:** 58.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.477 | **Positive rate:** 26.8%
- **3Y Rolling Sharpe (avg):** -0.517

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00118 | **NW t-stat:** 1.442 (not significant)
- **Avg Cross-sectional R²:** 0.0583

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -8.81%/yr (t=-2.338) (significant) | **Adj R²:** -0.0022

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 74.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.2%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5326, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
