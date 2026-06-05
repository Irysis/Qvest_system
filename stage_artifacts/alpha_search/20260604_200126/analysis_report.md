# Strategy Diagnostic Report: AS_streversal_sp
Generated: 2026-06-04

## Factor Signal Quality
- **IC Mean:** 0.0327 | **ICIR:** 0.196 | **IC > 0 rate:** 54.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.106 | **Positive rate:** 39.9%
- **3Y Rolling Sharpe (avg):** -0.233

## Stress Periods
- **Outperform rate vs BM:** 40.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00320 | **NW t-stat:** 2.445 (significant)
- **Avg Cross-sectional R²:** 0.0713

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -15.16%/yr (t=-2.709) (significant) | **Adj R²:** 0.3145

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1712 (lower = more diversified)
- **Avg Period Turnover:** 87.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** NO (overlap: 8914, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
