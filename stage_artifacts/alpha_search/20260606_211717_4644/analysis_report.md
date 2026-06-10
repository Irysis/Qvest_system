# Strategy Diagnostic Report: STR_altman_z
Generated: 2026-06-06

## Factor Signal Quality
- **IC Mean:** -0.0077 | **ICIR:** -0.050 | **IC > 0 rate:** 48.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.354 | **Positive rate:** 62.4%
- **3Y Rolling Sharpe (avg):** 0.182

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00042 | **NW t-stat:** -0.375 (not significant)
- **Avg Cross-sectional R²:** 0.0730

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -1.63%/yr (t=-0.622)  | **Adj R²:** 0.5099

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1353 (lower = more diversified)
- **Avg Period Turnover:** 3.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 6)
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
