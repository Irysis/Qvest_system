# Strategy Diagnostic Report: RF_PAR_B1_7_sizeprobe
Generated: 2026-09-05

## Factor Signal Quality
- **IC Mean:** 0.0145 | **ICIR:** 0.070 | **IC > 0 rate:** 54.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.921 | **Positive rate:** 61.8%
- **3Y Rolling Sharpe (avg):** 0.716

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00000 | **NW t-stat:** 0.000 (not significant)
- **Avg Cross-sectional R²:** 0.0000

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 4.54%/yr (t=0.987)  | **Adj R²:** 0.5664

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 16.6%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 3)
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
