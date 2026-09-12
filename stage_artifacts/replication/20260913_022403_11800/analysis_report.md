# Strategy Diagnostic Report: RP_AUTO_combo140381252007
Generated: 2026-09-13

## Factor Signal Quality
- **IC Mean:** -0.0054 | **ICIR:** -0.032 | **IC > 0 rate:** 50.2%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.675 | **Positive rate:** 63.4%
- **3Y Rolling Sharpe (avg):** 0.476

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00257 | **NW t-stat:** -1.575 (not significant)
- **Avg Cross-sectional R²:** 0.0773

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 5.05%/yr (t=1.126)  | **Adj R²:** 0.4114

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 37.9%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5331, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
