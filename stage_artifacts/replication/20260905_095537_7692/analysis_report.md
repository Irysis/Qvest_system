# Strategy Diagnostic Report: RF_PAR_B3_12_KOSDAQ150
Generated: 2026-09-05

## Factor Signal Quality
- **IC Mean:** 0.0329 | **ICIR:** 0.152 | **IC > 0 rate:** 54.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 1.231 | **Positive rate:** 72.6%
- **3Y Rolling Sharpe (avg):** 0.983

## Stress Periods
- **Outperform rate vs BM:** 67.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00000 | **NW t-stat:** 0.000 (not significant)
- **Avg Cross-sectional R²:** 0.0000

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 15.24%/yr (t=2.903) (significant) | **Adj R²:** 0.4420

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 20.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 4084, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
