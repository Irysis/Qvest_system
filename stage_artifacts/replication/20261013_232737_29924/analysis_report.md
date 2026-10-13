# Strategy Diagnostic Report: P0R01_E1_C4
Generated: 2026-10-13

## Factor Signal Quality
- **IC Mean:** 0.0306 | **ICIR:** 0.131 | **IC > 0 rate:** 57.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 1.156 | **Positive rate:** 65.0%
- **3Y Rolling Sharpe (avg):** 0.885

## Stress Periods
- **Outperform rate vs BM:** 60.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00000 | **NW t-stat:** 0.000 (not significant)
- **Avg Cross-sectional R²:** 0.0000

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 7.19%/yr (t=1.898)  | **Adj R²:** 0.4367

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 38.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 6494, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
