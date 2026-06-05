# Strategy Diagnostic Report: AS_mom9_1
Generated: 2026-06-04

## Factor Signal Quality
- **IC Mean:** 0.0022 | **ICIR:** 0.012 | **IC > 0 rate:** 51.8%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.100 | **Positive rate:** 47.5%
- **3Y Rolling Sharpe (avg):** -0.123

## Stress Periods
- **Outperform rate vs BM:** 40.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00158 | **NW t-stat:** 1.041 (not significant)
- **Avg Cross-sectional R²:** 0.0634

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -6.95%/yr (t=-1.268)  | **Adj R²:** 0.3691

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1517 (lower = more diversified)
- **Avg Period Turnover:** 26.3%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** NO (overlap: 8750, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
