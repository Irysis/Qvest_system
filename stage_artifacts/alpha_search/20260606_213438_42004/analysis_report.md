# Strategy Diagnostic Report: Seasonality_HS2008
Generated: 2026-06-06

## Factor Signal Quality
- **IC Mean:** -0.0073 | **ICIR:** -0.089 | **IC > 0 rate:** 48.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.486 | **Positive rate:** 63.6%
- **3Y Rolling Sharpe (avg):** 0.246

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00200 | **NW t-stat:** -3.544 (significant)
- **Avg Cross-sectional R²:** 0.0544

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -1.21%/yr (t=-0.622)  | **Adj R²:** 0.7227

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0731 (lower = more diversified)
- **Avg Period Turnover:** 54.3%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.3%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 31)
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
