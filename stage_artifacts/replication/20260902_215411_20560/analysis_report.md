# Strategy Diagnostic Report: RF_PAR_B3_12_KOSPI200
Generated: 2026-09-02

## Factor Signal Quality
- **IC Mean:** -0.0264 | **ICIR:** -0.124 | **IC > 0 rate:** 45.1%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.495 | **Positive rate:** 66.0%
- **3Y Rolling Sharpe (avg):** 0.408

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00000 | **NW t-stat:** 0.000 (not significant)
- **Avg Cross-sectional R²:** 0.0000

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 0.94%/yr (t=0.358)  | **Adj R²:** 0.5263

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 30.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 4827, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
