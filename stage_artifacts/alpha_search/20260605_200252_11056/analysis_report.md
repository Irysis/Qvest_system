# Strategy Diagnostic Report: LowVol
Generated: 2026-06-05

## Factor Signal Quality
- **IC Mean:** 0.0353 | **ICIR:** 0.177 | **IC > 0 rate:** 54.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.413 | **Positive rate:** 61.1%
- **3Y Rolling Sharpe (avg):** 0.187

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00180 | **NW t-stat:** 1.227 (not significant)
- **Avg Cross-sectional R²:** 0.0729

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -1.37%/yr (t=-0.620)  | **Adj R²:** 0.5442

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1029 (lower = more diversified)
- **Avg Period Turnover:** 7.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 11.3%
- **Crowding Risk:** LOW (persistent>75%: 4, common>50%: 6)
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
