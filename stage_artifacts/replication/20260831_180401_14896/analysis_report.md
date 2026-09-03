# Strategy Diagnostic Report: RF_PAR_B3_11_KOSDAQ150
Generated: 2026-08-31

## Factor Signal Quality
- **IC Mean:** -0.0141 | **ICIR:** -0.070 | **IC > 0 rate:** 49.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.409 | **Positive rate:** 54.4%
- **3Y Rolling Sharpe (avg):** 0.206

## Stress Periods
- **Outperform rate vs BM:** 33.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00000 | **NW t-stat:** 0.000 (not significant)
- **Avg Cross-sectional R²:** 0.0000

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 8.87%/yr (t=0.630)  | **Adj R²:** 0.0980

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 50.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 33.3%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 4079, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
