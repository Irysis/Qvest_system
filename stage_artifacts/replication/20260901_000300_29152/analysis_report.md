# Strategy Diagnostic Report: RP_AUTO_260814014
Generated: 2026-09-01

## Factor Signal Quality
- **IC Mean:** -0.0033 | **ICIR:** -0.029 | **IC > 0 rate:** 50.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.268 | **Positive rate:** 56.6%
- **3Y Rolling Sharpe (avg):** 0.088

## Stress Periods
- **Outperform rate vs BM:** 25.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00111 | **NW t-stat:** -1.174 (not significant)
- **Avg Cross-sectional R²:** 0.0623

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -4.98%/yr (t=-1.566)  | **Adj R²:** 0.5714

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 88.6%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5321, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
