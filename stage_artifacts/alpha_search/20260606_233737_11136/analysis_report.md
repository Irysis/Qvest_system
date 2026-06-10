# Strategy Diagnostic Report: High52W_GH2004
Generated: 2026-06-06

## Factor Signal Quality
- **IC Mean:** 0.0128 | **ICIR:** 0.068 | **IC > 0 rate:** 57.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.741 | **Positive rate:** 69.2%
- **3Y Rolling Sharpe (avg):** 0.446

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00021 | **NW t-stat:** -0.130 (not significant)
- **Avg Cross-sectional R²:** 0.0701

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 2.22%/yr (t=0.885)  | **Adj R²:** 0.6727

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0658 (lower = more diversified)
- **Avg Period Turnover:** 18.3%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.3%
- **Crowding Risk:** MEDIUM (persistent>75%: 12, common>50%: 71)
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
