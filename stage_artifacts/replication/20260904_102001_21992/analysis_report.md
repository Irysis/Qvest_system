# Strategy Diagnostic Report: RP_AUTO_combo200708115230
Generated: 2026-09-04

## Factor Signal Quality
- **IC Mean:** -0.0210 | **ICIR:** -0.125 | **IC > 0 rate:** 46.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.375 | **Positive rate:** 56.2%
- **3Y Rolling Sharpe (avg):** 0.101

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00140 | **NW t-stat:** -1.153 (not significant)
- **Avg Cross-sectional R²:** 0.0680

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -1.91%/yr (t=-0.372)  | **Adj R²:** 0.4909

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 32.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5325, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
