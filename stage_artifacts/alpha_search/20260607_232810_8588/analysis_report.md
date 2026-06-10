# Strategy Diagnostic Report: MAX_Lottery_Bali2011
Generated: 2026-06-07

## Factor Signal Quality
- **IC Mean:** 0.0272 | **ICIR:** 0.175 | **IC > 0 rate:** 59.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.305 | **Positive rate:** 57.7%
- **3Y Rolling Sharpe (avg):** 0.097

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00002 | **NW t-stat:** 0.015 (not significant)
- **Avg Cross-sectional R²:** 0.0660

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -3.62%/yr (t=-1.778)  | **Adj R²:** 0.6184

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0940 (lower = more diversified)
- **Avg Period Turnover:** 47.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 11.4%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 3)
- **Sample Aligned:** NO (overlap: 5256, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
