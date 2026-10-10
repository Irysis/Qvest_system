# Strategy Diagnostic Report: UNIV_1707_05552_W
Generated: 2026-10-10

## Factor Signal Quality
- **IC Mean:** 0.0093 | **ICIR:** 0.114 | **IC > 0 rate:** 51.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.612 | **Positive rate:** 28.2%
- **3Y Rolling Sharpe (avg):** -0.701

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00177 | **NW t-stat:** 2.691 (significant)
- **Avg Cross-sectional R²:** 0.0224

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -9.45%/yr (t=-2.483) (significant) | **Adj R²:** 0.0024

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 69.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.2%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5341, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
