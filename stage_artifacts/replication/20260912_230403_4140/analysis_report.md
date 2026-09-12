# Strategy Diagnostic Report: RP_AUTO_201105381
Generated: 2026-09-12

## Factor Signal Quality
- **IC Mean:** -0.0190 | **ICIR:** -0.128 | **IC > 0 rate:** 46.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.477 | **Positive rate:** 64.4%
- **3Y Rolling Sharpe (avg):** 0.233

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00136 | **NW t-stat:** -0.914 (not significant)
- **Avg Cross-sectional R²:** 0.0718

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -0.85%/yr (t=-0.314)  | **Adj R²:** 0.6716

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 2.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.2%
- **Crowding Risk:** HIGH (persistent>75%: 38, common>50%: 123)
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
