# Strategy Diagnostic Report: RF_PAR_B7_37_k5IC1
Generated: 2026-09-22

## Factor Signal Quality
- **IC Mean:** 0.0359 | **ICIR:** 0.146 | **IC > 0 rate:** 54.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 1.222 | **Positive rate:** 75.8%
- **3Y Rolling Sharpe (avg):** 0.874

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00000 | **NW t-stat:** 0.000 (not significant)
- **Avg Cross-sectional R²:** 0.0000

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 10.24%/yr (t=3.288) (significant) | **Adj R²:** 0.6123

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 60.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 1)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5337, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
