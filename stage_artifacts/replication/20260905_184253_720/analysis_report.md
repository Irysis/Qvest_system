# Strategy Diagnostic Report: RP_AUTO_240408129
Generated: 2026-09-05

## Factor Signal Quality
- **IC Mean:** -0.0022 | **ICIR:** -0.015 | **IC > 0 rate:** 48.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.585 | **Positive rate:** 64.6%
- **3Y Rolling Sharpe (avg):** 0.409

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00124 | **NW t-stat:** 1.074 (not significant)
- **Avg Cross-sectional R²:** 0.0627

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 4.55%/yr (t=0.906)  | **Adj R²:** 0.4565

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 13.9%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 4)
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
