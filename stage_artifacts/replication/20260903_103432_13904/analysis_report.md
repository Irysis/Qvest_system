# Strategy Diagnostic Report: RF_PAR_B3_12_KOSPI200
Generated: 2026-09-03

## Factor Signal Quality
- **IC Mean:** -0.0091 | **ICIR:** -0.042 | **IC > 0 rate:** 47.9%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.571 | **Positive rate:** 59.8%
- **3Y Rolling Sharpe (avg):** 0.223

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00000 | **NW t-stat:** 0.000 (not significant)
- **Avg Cross-sectional R²:** 0.0000

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 0.26%/yr (t=0.118)  | **Adj R²:** 0.7828

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 18.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 14)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5324, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
